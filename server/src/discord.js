/**
 * Discord slash-command bot for Vain's rank system.
 *
 * A member's Discord ROLE is their RANK (Free/unbound < Privileged < Owner).
 * Ranks do two things, both implemented elsewhere and just SERVED here:
 *   - In-game target immunity (libraries/entity.lua polls GET /rank/<id> on
 *     this Worker, see worker.js) -- a lower rank's targeting modules can
 *     never see a higher rank as a valid target.
 *   - Command hierarchy: a rank can run /whitelistadmin commands on anyone at
 *     a STRICTLY lower rank. Owner acts on Privileged/Free, Privileged acts
 *     on Free only, Free can't run these at all.
 *
 * `/whitelist edit` just binds a Discord identity to a Roblox account (open
 * to everyone, Free included -- it's identity mapping, not a privilege) so
 * the rank checks above have something to resolve. There is no secret/key
 * involved anywhere in this file -- Vain loads publicly, nothing needs a
 * bearer credential.
 *
 * Every request here starts as a Discord "interaction" POST, signed with
 * Ed25519 over (timestamp + body) using the app's public key. See
 * verifyDiscordRequest(). PING (type 1) must be answered with PONG (type 1)
 * for Discord to accept the Interactions Endpoint URL at all.
 */

import { verifyKey } from "discord-interactions";

const DISCORD_API = "https://discord.com/api/v10";

function json(obj, status = 200) {
	return new Response(JSON.stringify(obj), {
		status,
		headers: { "content-type": "application/json; charset=utf-8" },
	});
}

// ---- signature verification -------------------------------------------------

export async function verifyDiscordRequest(req, env) {
	const sig = req.headers.get("x-signature-ed25519");
	const ts = req.headers.get("x-signature-timestamp");
	const body = await req.text(); // must verify the raw bytes, not parsed JSON
	if (!sig || !ts) return { ok: false, body };
	const ok = await verifyKey(body, sig, ts, env.DISCORD_PUBLIC_KEY);
	return { ok, body };
}

// ---- Discord REST helpers ----------------------------------------------------

function discordFetch(env, path, init = {}) {
	return fetch(`${DISCORD_API}${path}`, {
		...init,
		headers: {
			authorization: `Bot ${env.DISCORD_BOT_TOKEN}`,
			"content-type": "application/json",
			"user-agent": "vain-worker",
			...(init.headers || {}),
		},
	});
}

async function sendFollowup(env, interaction, content) {
	await discordFetch(
		env,
		`/webhooks/${env.DISCORD_APPLICATION_ID}/${interaction.token}/messages/@original`,
		{ method: "PATCH", body: JSON.stringify({ content, flags: 64 }) }
	);
}

// ---- rank resolution ----------------------------------------------------------

// Cloudflare KV's expirationTtl floor is 60s -- also a sane cap on Discord API
// call volume, since every Vain client polls GET /rank/<id> per opponent.
const RANK_CACHE_TTL = 60;

// Highest first, matching env.RANK_ORDER's own convention -- kept in sync with
// libraries/entity.lua's RANK_LEVEL table on the client side.
const RANK_LEVEL = { owner: 2, priviliged: 1 };
function levelOf(tier) {
	return tier ? RANK_LEVEL[tier] || 0 : 0;
}

export async function resolveRank(env, discordUserId, ctx) {
	const cached = await env.KEYS.get(`rankcache:${discordUserId}`);
	if (cached) {
		try { return JSON.parse(cached); } catch { /* fall through and refresh */ }
	}

	let tier = null;
	const res = await discordFetch(env, `/guilds/${env.DISCORD_GUILD_ID}/members/${discordUserId}`);
	if (res.ok) {
		const member = await res.json();
		const roles = new Set(member.roles || []);
		tier = (env.RANK_ORDER || []).find((t) =>
			Object.entries(env.RANK_ROLES || {}).some(([roleId, roleTier]) => roleTier === t && roles.has(roleId))
		) || null;
	}

	const rec = { tier, checkedAt: Date.now() };
	const put = env.KEYS.put(`rankcache:${discordUserId}`, JSON.stringify(rec), { expirationTtl: RANK_CACHE_TTL });
	if (ctx) ctx.waitUntil(put); else await put;
	return rec;
}

// ---- Roblox username -> id resolution -----------------------------------------

async function resolveRobloxUser(username) {
	const res = await fetch("https://users.roblox.com/v1/usernames/users", {
		method: "POST",
		headers: { "content-type": "application/json", "user-agent": "vain-worker" },
		body: JSON.stringify({ usernames: [username], excludeBannedUsers: false }),
	});
	if (res.status === 429) return { error: "Roblox lookup was rate-limited, try again shortly." };
	if (!res.ok) return { error: `Roblox lookup failed (${res.status}).` };
	const data = await res.json();
	const hit = data && data.data && data.data[0];
	if (!hit) return { error: `No Roblox account named "${username}".` };
	return { id: hit.id, name: hit.name };
}

// ---- whitelist record helpers --------------------------------------------------

async function getRecord(env, discordUserId) {
	const raw = await env.KEYS.get(`discord:${discordUserId}`);
	return raw ? JSON.parse(raw) : null;
}

async function putRecord(env, discordUserId, rec) {
	await env.KEYS.put(`discord:${discordUserId}`, JSON.stringify(rec));
}

// Resolves a staff-provided target string to { discordUserId, rec }, trying a
// Discord mention/snowflake first, then a Roblox username via the reverse index.
async function resolveTarget(env, target) {
	const raw = target.trim();

	const mention = raw.match(/^<@!?(\d+)>$/) || raw.match(/^(\d{15,25})$/);
	if (mention) {
		const rec = await getRecord(env, mention[1]);
		return rec ? { discordUserId: mention[1], rec } : null;
	}

	const resolved = await resolveRobloxUser(raw);
	if (resolved.error) return null;
	const revIdx = await env.KEYS.get(`roblox:${resolved.id}`);
	if (!revIdx) return null;
	const { discordUserId } = JSON.parse(revIdx);
	const rec = await getRecord(env, discordUserId);
	return rec ? { discordUserId, rec } : null;
}

// Find-or-create/update a whitelist binding for discordUserId -> robloxAccount.
// `allowReassign` lets staff `force` steal an already-claimed Roblox account;
// self-service `edit` never does.
async function bindWhitelist(env, discordUserId, robloxUsername, { allowReassign = false } = {}) {
	const resolved = await resolveRobloxUser(robloxUsername);
	if (resolved.error) return { error: resolved.error };

	const revRaw = await env.KEYS.get(`roblox:${resolved.id}`);
	if (revRaw) {
		const { discordUserId: ownerId } = JSON.parse(revRaw);
		if (ownerId !== discordUserId && !allowReassign) {
			return { error: `Roblox account "${resolved.name}" is already linked to another Discord account.` };
		}
	}

	let rec = await getRecord(env, discordUserId);
	if (rec && rec.banned) return { error: "This Discord account is banned from whitelisting." };
	if (!rec) rec = { banned: false };

	// Free the old reverse-index entry if the Roblox account changed.
	if (rec.robloxUserId && rec.robloxUserId !== resolved.id) {
		await env.KEYS.delete(`roblox:${rec.robloxUserId}`);
	}

	rec.robloxUserId = resolved.id;
	rec.robloxUsername = resolved.name;

	await putRecord(env, discordUserId, rec);
	await env.KEYS.put(`roblox:${resolved.id}`, JSON.stringify({ discordUserId }));

	return { rec, robloxName: resolved.name };
}

// ---- command handlers -----------------------------------------------------

async function cmdWhitelistEdit(interaction, env, ctx) {
	const invokerId = interaction.member.user.id;
	const robloxAccount = interaction.data.options[0].options.find((o) => o.name === "roblox_account").value;

	ctx.waitUntil((async () => {
		const result = await bindWhitelist(env, invokerId, robloxAccount);
		if (result.error) return sendFollowup(env, interaction, `❌ ${result.error}`);
		await sendFollowup(env, interaction, `✅ Linked to Roblox account **${result.robloxName}**.`);
	})());

	return json({ type: 5, data: { flags: 64 } });
}

async function cmdWhitelistView(interaction, env, ctx) {
	const invokerId = interaction.member.user.id;

	ctx.waitUntil((async () => {
		const rec = await getRecord(env, invokerId);
		if (!rec) return sendFollowup(env, interaction, "You haven't linked an account yet -- run `/whitelist edit`.");
		const rank = await resolveRank(env, invokerId, ctx);
		await sendFollowup(
			env,
			interaction,
			`Roblox: **${rec.robloxUsername}**\nCurrent rank: ${rank.tier || "Free"}` +
			(rec.banned ? "\n⚠️ Banned" : "")
		);
	})());

	return json({ type: 5, data: { flags: 64 } });
}

async function cmdWhitelistRemove(interaction, env, ctx) {
	const invokerId = interaction.member.user.id;

	ctx.waitUntil((async () => {
		const rec = await getRecord(env, invokerId);
		if (!rec) return sendFollowup(env, interaction, "You don't have a linked account.");
		if (rec.robloxUserId) await env.KEYS.delete(`roblox:${rec.robloxUserId}`);
		await env.KEYS.delete(`discord:${invokerId}`);
		await sendFollowup(env, interaction, "✅ Unlinked.");
	})());

	return json({ type: 5, data: { flags: 64 } });
}

// Shared permission gate for /whitelistadmin: invoker must outrank the target.
// Returns null (allowed) or a rejection message.
async function checkHierarchy(env, invokerId, targetId, ctx) {
	const [invokerRank, targetRank] = await Promise.all([
		resolveRank(env, invokerId, ctx),
		resolveRank(env, targetId, ctx),
	]);
	if (levelOf(invokerRank.tier) <= levelOf(targetRank.tier)) {
		return "You can only do this to someone at a strictly lower rank than you.";
	}
	return null;
}

async function cmdLookup(interaction, env, ctx) {
	const invokerId = interaction.member.user.id;
	const target = interaction.data.options[0].options.find((o) => o.name === "target").value;

	ctx.waitUntil((async () => {
		const found = await resolveTarget(env, target);
		if (!found) return sendFollowup(env, interaction, "No matching record.");
		const denied = await checkHierarchy(env, invokerId, found.discordUserId, ctx);
		if (denied) return sendFollowup(env, interaction, `❌ ${denied}`);
		const rank = await resolveRank(env, found.discordUserId, ctx);
		await sendFollowup(
			env,
			interaction,
			`Discord: <@${found.discordUserId}>\n` +
			`Roblox: ${found.rec.robloxUsername || "?"} (${found.rec.robloxUserId || "?"})\n` +
			`Banned: ${!!found.rec.banned}\nRank: ${rank.tier || "Free"}`
		);
	})());

	return json({ type: 5, data: { flags: 64 } });
}

async function cmdForce(interaction, env, ctx) {
	const invokerId = interaction.member.user.id;
	const opts = interaction.data.options[0].options;
	const discordUser = opts.find((o) => o.name === "discord_user").value;
	const robloxAccount = opts.find((o) => o.name === "roblox_account").value;

	ctx.waitUntil((async () => {
		const denied = await checkHierarchy(env, invokerId, discordUser, ctx);
		if (denied) return sendFollowup(env, interaction, `❌ ${denied}`);
		const result = await bindWhitelist(env, discordUser, robloxAccount, { allowReassign: true });
		if (result.error) return sendFollowup(env, interaction, `❌ ${result.error}`);
		await sendFollowup(env, interaction, `✅ Forced link: <@${discordUser}> -> **${result.robloxName}**.`);
	})());

	return json({ type: 5, data: { flags: 64 } });
}

async function cmdBan(interaction, env, ctx) {
	const invokerId = interaction.member.user.id;
	const target = interaction.data.options[0].options.find((o) => o.name === "target").value;

	ctx.waitUntil((async () => {
		const found = await resolveTarget(env, target);
		if (!found) return sendFollowup(env, interaction, "No matching record.");
		const denied = await checkHierarchy(env, invokerId, found.discordUserId, ctx);
		if (denied) return sendFollowup(env, interaction, `❌ ${denied}`);
		found.rec.banned = true;
		await putRecord(env, found.discordUserId, found.rec);
		await sendFollowup(env, interaction, `🔨 Banned <@${found.discordUserId}>.`);
	})());

	return json({ type: 5, data: { flags: 64 } });
}

async function cmdUnban(interaction, env, ctx) {
	const invokerId = interaction.member.user.id;
	const target = interaction.data.options[0].options.find((o) => o.name === "target").value;

	ctx.waitUntil((async () => {
		const found = await resolveTarget(env, target);
		if (!found) return sendFollowup(env, interaction, "No matching record.");
		const denied = await checkHierarchy(env, invokerId, found.discordUserId, ctx);
		if (denied) return sendFollowup(env, interaction, `❌ ${denied}`);
		found.rec.banned = false;
		await putRecord(env, found.discordUserId, found.rec);
		await sendFollowup(env, interaction, `✅ Unbanned <@${found.discordUserId}>.`);
	})());

	return json({ type: 5, data: { flags: 64 } });
}

const HANDLERS = {
	"whitelist:edit": cmdWhitelistEdit,
	"whitelist:view": cmdWhitelistView,
	"whitelist:remove": cmdWhitelistRemove,
	"whitelistadmin:lookup": cmdLookup,
	"whitelistadmin:force": cmdForce,
	"whitelistadmin:ban": cmdBan,
	"whitelistadmin:unban": cmdUnban,
};

function routeCommand(interaction, env, ctx) {
	const name = interaction.data.name;
	const sub = interaction.data.options && interaction.data.options[0] && interaction.data.options[0].name;
	const fn = HANDLERS[`${name}:${sub}`];
	if (!fn) return json({ type: 4, data: { content: "Unknown command.", flags: 64 } });
	return fn(interaction, env, ctx);
}

export async function handleDiscordInteraction(req, env, ctx) {
	const { ok, body } = await verifyDiscordRequest(req, env);
	if (!ok) return new Response("bad signature", { status: 401 });

	const interaction = JSON.parse(body);
	if (interaction.type === 1) return json({ type: 1 }); // PING -> PONG
	if (interaction.type === 2) return routeCommand(interaction, env, ctx);
	return json({ type: 4, data: { content: "Unsupported interaction.", flags: 64 } });
}
