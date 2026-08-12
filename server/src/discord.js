/**
 * Discord slash-command bot for Vain's self-service whitelist.
 *
 * A buyer's Discord ROLE is their RANK. `/whitelist edit` lets a member with a
 * qualifying rank role bind exactly one Roblox account to their Discord
 * identity and self-issues them a delivery key (the same secret credential
 * `worker.js`'s checkAuth() has always required -- this never trusts a
 * client-claimed Roblox UserId as a credential, only as display/lookup
 * metadata, since a UserId is public and spoofable). `/whitelistadmin *` gives
 * staff the same lookup/reset-hwid/force/ban powers keys.mjs already has for
 * admin-issued keys, plus whitelist-specific overrides.
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
// call volume, since one Roblox session fires many file fetches per boot.
const RANK_CACHE_TTL = 60;

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

function isStaff(interaction, env) {
	const roles = (interaction.member && interaction.member.roles) || [];
	return env.DISCORD_STAFF_ROLE_ID && roles.includes(env.DISCORD_STAFF_ROLE_ID);
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

// ---- key helpers (mirrors worker.js's randomKey / record shape) ---------------

function randomKey() {
	const bytes = crypto.getRandomValues(new Uint8Array(18));
	const b64 = btoa(String.fromCharCode(...bytes)).replace(/[+/=]/g, "");
	return `vain_${b64}`;
}

function maskKey(key) {
	return key.length > 10 ? `${key.slice(0, 10)}${"*".repeat(Math.max(0, key.length - 10))}` : key;
}

async function getKeyRecord(env, key) {
	const raw = await env.KEYS.get(`key:${key}`);
	return raw ? JSON.parse(raw) : null;
}

async function putKeyRecord(env, key, rec) {
	await env.KEYS.put(`key:${key}`, JSON.stringify(rec));
}

// Resolves a staff-provided target string to a { key, rec } pair, trying (in
// order) a raw key, a Discord user mention/snowflake, then a Roblox username.
async function resolveTarget(env, target) {
	const raw = target.trim();

	if (raw.startsWith("vain_")) {
		const rec = await getKeyRecord(env, raw);
		return rec ? { key: raw, rec } : null;
	}

	const mention = raw.match(/^<@!?(\d+)>$/) || raw.match(/^(\d{15,25})$/);
	if (mention) {
		const idx = await env.KEYS.get(`discord:${mention[1]}`);
		if (!idx) return null;
		const { key } = JSON.parse(idx);
		const rec = await getKeyRecord(env, key);
		return rec ? { key, rec } : null;
	}

	const resolved = await resolveRobloxUser(raw);
	if (resolved.error) return null;
	const revIdx = await env.KEYS.get(`roblox:${resolved.id}`);
	if (!revIdx) return null;
	const { discordUserId } = JSON.parse(revIdx);
	const idx = await env.KEYS.get(`discord:${discordUserId}`);
	if (!idx) return null;
	const { key } = JSON.parse(idx);
	const rec = await getKeyRecord(env, key);
	return rec ? { key, rec } : null;
}

// Find-or-create/update a whitelist binding for discordUserId -> robloxAccount.
// `allowReassign` lets staff `force` steal an already-claimed Roblox account;
// self-service `edit` never does.
async function bindWhitelist(env, discordUserId, robloxUsername, { allowReassign = false, source = "discord-self-service" } = {}) {
	const resolved = await resolveRobloxUser(robloxUsername);
	if (resolved.error) return { error: resolved.error };

	const revRaw = await env.KEYS.get(`roblox:${resolved.id}`);
	if (revRaw) {
		const { discordUserId: ownerId } = JSON.parse(revRaw);
		if (ownerId !== discordUserId && !allowReassign) {
			return { error: `Roblox account "${resolved.name}" is already linked to another Discord account.` };
		}
	}

	const fwdRaw = await env.KEYS.get(`discord:${discordUserId}`);
	let key, rec;

	if (fwdRaw) {
		key = JSON.parse(fwdRaw).key;
		rec = await getKeyRecord(env, key);
		if (rec && rec.banned) return { error: "This Discord account is banned from whitelisting." };
		if (!rec) {
			// Forward index pointed at a missing record -- shouldn't happen, heal by minting fresh.
			key = randomKey();
			rec = { created: Date.now(), note: "", expires: null, hwid: null, boundAt: null, revoked: false, banned: false, lastSeen: null };
		} else {
			// Free the old reverse-index entry if the Roblox account changed.
			if (rec.robloxUserId && rec.robloxUserId !== resolved.id) {
				await env.KEYS.delete(`roblox:${rec.robloxUserId}`);
			}
			rec.revoked = false;
		}
	} else {
		key = randomKey();
		rec = { created: Date.now(), note: "", expires: null, hwid: null, boundAt: null, revoked: false, banned: false, lastSeen: null };
	}

	rec.discordUserId = discordUserId;
	rec.robloxUserId = resolved.id;
	rec.robloxUsername = resolved.name;
	rec.source = source;

	await putKeyRecord(env, key, rec);
	await env.KEYS.put(`discord:${discordUserId}`, JSON.stringify({ key }));
	await env.KEYS.put(`roblox:${resolved.id}`, JSON.stringify({ discordUserId }));

	return { key, rec, robloxName: resolved.name };
}

// ---- command handlers -----------------------------------------------------

async function cmdWhitelistEdit(interaction, env, ctx) {
	const invokerId = interaction.member.user.id;
	const robloxAccount = interaction.data.options[0].options.find((o) => o.name === "roblox_account").value;

	ctx.waitUntil((async () => {
		const rank = await resolveRank(env, invokerId, ctx);
		if (!rank.tier) {
			return sendFollowup(env, interaction, "You need an active rank role to whitelist an account.");
		}
		const result = await bindWhitelist(env, invokerId, robloxAccount);
		if (result.error) return sendFollowup(env, interaction, `❌ ${result.error}`);
		await sendFollowup(
			env,
			interaction,
			`✅ Linked to Roblox account **${result.robloxName}**.\n` +
			`Your key: \`${result.key}\`\nPaste this into \`VAIN_KEY\` in your entrypoint.lua.`
		);
	})());

	return json({ type: 5, data: { flags: 64 } });
}

async function cmdWhitelistView(interaction, env, ctx) {
	const invokerId = interaction.member.user.id;

	ctx.waitUntil((async () => {
		const fwdRaw = await env.KEYS.get(`discord:${invokerId}`);
		if (!fwdRaw) return sendFollowup(env, interaction, "You haven't linked an account yet -- run `/whitelist edit`.");
		const { key } = JSON.parse(fwdRaw);
		const rec = await getKeyRecord(env, key);
		if (!rec) return sendFollowup(env, interaction, "You haven't linked an account yet -- run `/whitelist edit`.");
		const rank = await resolveRank(env, invokerId, ctx);
		await sendFollowup(
			env,
			interaction,
			`Key: \`${maskKey(key)}\`\nRoblox: **${rec.robloxUsername}**\n` +
			`HWID bound: ${rec.hwid ? "yes" : "no"}\nCurrent rank: ${rank.tier || "none"}\n` +
			`Revoked: ${rec.revoked ? "yes" : "no"}${rec.banned ? "\n⚠️ Banned" : ""}`
		);
	})());

	return json({ type: 5, data: { flags: 64 } });
}

async function cmdWhitelistRemove(interaction, env, ctx) {
	const invokerId = interaction.member.user.id;

	ctx.waitUntil((async () => {
		const fwdRaw = await env.KEYS.get(`discord:${invokerId}`);
		if (!fwdRaw) return sendFollowup(env, interaction, "You don't have a linked account.");
		const { key } = JSON.parse(fwdRaw);
		const rec = await getKeyRecord(env, key);
		if (rec) {
			rec.revoked = true;
			await putKeyRecord(env, key, rec);
			if (rec.robloxUserId) await env.KEYS.delete(`roblox:${rec.robloxUserId}`);
		}
		await env.KEYS.delete(`discord:${invokerId}`);
		await sendFollowup(env, interaction, "✅ Unlinked. Your key has been revoked.");
	})());

	return json({ type: 5, data: { flags: 64 } });
}

async function cmdLookup(interaction, env, ctx) {
	if (!isStaff(interaction, env)) return json({ type: 5, data: { flags: 64 } });
	const target = interaction.data.options[0].options.find((o) => o.name === "target").value;

	ctx.waitUntil((async () => {
		const found = await resolveTarget(env, target);
		if (!found) return sendFollowup(env, interaction, "No matching record.");
		const rank = found.rec.discordUserId ? await resolveRank(env, found.rec.discordUserId, ctx) : { tier: null };
		await sendFollowup(
			env,
			interaction,
			`Key: \`${found.key}\`\nDiscord: <@${found.rec.discordUserId || "?"}>\n` +
			`Roblox: ${found.rec.robloxUsername || "?"} (${found.rec.robloxUserId || "?"})\n` +
			`HWID: ${found.rec.hwid || "unbound"}\nRevoked: ${found.rec.revoked}\nBanned: ${!!found.rec.banned}\n` +
			`Source: ${found.rec.source || "admin-manual"}\nLive rank: ${rank.tier || "none"}\n` +
			`Last seen: ${found.rec.lastSeen ? new Date(found.rec.lastSeen).toISOString() : "never"}`
		);
	})());

	return json({ type: 5, data: { flags: 64 } });
}

async function cmdResetHwid(interaction, env, ctx) {
	if (!isStaff(interaction, env)) return json({ type: 5, data: { flags: 64 } });
	const target = interaction.data.options[0].options.find((o) => o.name === "target").value;

	ctx.waitUntil((async () => {
		const found = await resolveTarget(env, target);
		if (!found) return sendFollowup(env, interaction, "No matching record.");
		found.rec.hwid = null;
		found.rec.boundAt = null;
		await putKeyRecord(env, found.key, found.rec);
		await sendFollowup(env, interaction, `✅ HWID reset for \`${found.key}\`.`);
	})());

	return json({ type: 5, data: { flags: 64 } });
}

async function cmdForce(interaction, env, ctx) {
	if (!isStaff(interaction, env)) return json({ type: 5, data: { flags: 64 } });
	const opts = interaction.data.options[0].options;
	const discordUser = opts.find((o) => o.name === "discord_user").value;
	const robloxAccount = opts.find((o) => o.name === "roblox_account").value;

	ctx.waitUntil((async () => {
		const result = await bindWhitelist(env, discordUser, robloxAccount, { allowReassign: true, source: "discord-staff-force" });
		if (result.error) return sendFollowup(env, interaction, `❌ ${result.error}`);
		await sendFollowup(env, interaction, `✅ Forced link: <@${discordUser}> -> **${result.robloxName}** (key \`${result.key}\`).`);
	})());

	return json({ type: 5, data: { flags: 64 } });
}

async function cmdBan(interaction, env, ctx) {
	if (!isStaff(interaction, env)) return json({ type: 5, data: { flags: 64 } });
	const target = interaction.data.options[0].options.find((o) => o.name === "target").value;

	ctx.waitUntil((async () => {
		const found = await resolveTarget(env, target);
		if (!found) return sendFollowup(env, interaction, "No matching record.");
		found.rec.banned = true;
		found.rec.revoked = true;
		await putKeyRecord(env, found.key, found.rec);
		await sendFollowup(env, interaction, `🔨 Banned \`${found.key}\`.`);
	})());

	return json({ type: 5, data: { flags: 64 } });
}

const HANDLERS = {
	"whitelist:edit": cmdWhitelistEdit,
	"whitelist:view": cmdWhitelistView,
	"whitelist:remove": cmdWhitelistRemove,
	"whitelistadmin:lookup": cmdLookup,
	"whitelistadmin:resethwid": cmdResetHwid,
	"whitelistadmin:force": cmdForce,
	"whitelistadmin:ban": cmdBan,
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
