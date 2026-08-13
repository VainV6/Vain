/**
 * Discord slash-command bot for Vain's rank system.
 *
 * A member's Discord ROLE is their RANK (Free/unbound < Privileged < Owner).
 * Ranks do three things, all implemented elsewhere and just SERVED here:
 *   - In-game target immunity (libraries/entity.lua polls GET /rank/<id> on
 *     this Worker, see worker.js) -- a lower rank's targeting modules can
 *     never see a higher rank as a valid target.
 *   - Command hierarchy: a rank can run /whitelistadmin commands on anyone at
 *     a STRICTLY lower rank. Owner acts on Privileged/Free, Privileged acts
 *     on Free only, Free can't run these at all.
 *   - Troll commands (one slash command per action here -- /fling, /kick, ... --
 *     or the in-game Troll Commands module via POST /troll): the same
 *     strictly-lower-rank rule, Privileged and up only, queueing a fixed joke
 *     effect for the target's own Vain client to run. See ./troll.js for the
 *     catalogue and authorizeTroll() below for the gate.
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
import { ACTION_NAMES, PRESENCE_TTL, enqueueCommand, listPresence, normalizeCommand } from "./troll.js";

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
		{
			method: "PATCH",
			// allowed_mentions empty: replies quote back user-supplied text (Roblox
			// names in /list, mentions in lookups) and none of it should be able to
			// ping anyone. The <@id> in lookups still renders as a name either way.
			body: JSON.stringify({ content, flags: 64, allowed_mentions: { parse: [] } }),
		}
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
	let error = null;
	const res = await discordFetch(env, `/guilds/${env.DISCORD_GUILD_ID}/members/${discordUserId}`);
	if (res.ok) {
		const member = await res.json();
		const roles = new Set(member.roles || []);
		tier = (env.RANK_ORDER || []).find((t) =>
			Object.entries(env.RANK_ROLES || {}).some(([roleId, roleTier]) => roleTier === t && roles.has(roleId))
		) || null;
	} else if (res.status !== 404) {
		// 404 is a real answer (not in the guild => Free). Anything else means we
		// never learned the roles at all, and reporting THAT as Free is how a
		// missing Server Members Intent turns into "you're not Privileged" with
		// no hint about the actual cause -- so carry the status out instead.
		error = res.status;
	}

	const rec = { tier, checkedAt: Date.now() };
	if (error) {
		// Deliberately not cached: a failed lookup cached for 60s keeps serving
		// "Free" for a minute after you fix the cause, which makes the fix look
		// like it didn't work.
		rec.error = error;
		return rec;
	}
	const put = env.KEYS.put(`rankcache:${discordUserId}`, JSON.stringify(rec), { expirationTtl: RANK_CACHE_TTL });
	if (ctx) ctx.waitUntil(put); else await put;
	return rec;
}

/**
 * Turns a failed rank lookup into something the invoker can act on, instead of
 * letting it masquerade as "you're Free". Returns null when the rank is real.
 */
function rankProblem(rank) {
	if (!rank.error) return null;
	if (rank.error === 403) {
		return "I couldn't read your roles: Discord returned 403. Turn on **Server Members Intent** " +
			"(Developer Portal -> your app -> Bot -> Privileged Gateway Intents) -- the member lookup that " +
			"ranks depend on requires it.";
	}
	if (rank.error === 401) {
		return "I couldn't read your roles: Discord returned 401, so DISCORD_BOT_TOKEN is wrong or revoked " +
			"(`wrangler secret put DISCORD_BOT_TOKEN`).";
	}
	return `I couldn't read your roles: Discord returned ${rank.error}. Check DISCORD_GUILD_ID and that the bot is still in the server.`;
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

// ---- in-game issuer tokens ------------------------------------------------------
// Discord signs its own interactions, but a Vain client firing POST /troll from
// inside a game has no signature to offer -- so a ranked member runs
// `/whitelist token`, gets a random secret, and pastes it into Vain. The token
// is what maps that HTTP request back to a Discord identity (and therefore a
// rank). Rotating simply issues a new one and drops the old key.

async function issueToken(env, discordUserId) {
	const bytes = crypto.getRandomValues(new Uint8Array(24));
	const token = Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");

	let rec = (await getRecord(env, discordUserId)) || { banned: false };
	if (rec.token) await env.KEYS.delete(`token:${rec.token}`);
	rec.token = token;
	await putRecord(env, discordUserId, rec);
	await env.KEYS.put(`token:${token}`, JSON.stringify({ discordUserId }));

	return token;
}

export async function discordUserIdFromToken(env, token) {
	if (!token || !/^[a-f0-9]{48}$/.test(token)) return null;
	const raw = await env.KEYS.get(`token:${token}`);
	if (!raw) return null;
	try {
		return JSON.parse(raw).discordUserId || null;
	} catch {
		return null;
	}
}

// Resolves a troll target to a Roblox user id. Unlike resolveTarget() this does
// NOT require the target to have a whitelist record -- an unbound player is just
// Free rank, and Free is exactly who gets trolled. A Roblox username resolves
// directly; a mention/snowflake still needs a binding, since that's the only way
// to know which Roblox account the Discord user plays on.
async function resolveTrollTarget(env, target) {
	const raw = String(target || "").trim();
	if (!raw) return { error: "No target given." };

	const mention = raw.match(/^<@!?(\d+)>$/) || raw.match(/^(\d{15,25})$/);
	if (mention) {
		const rec = await getRecord(env, mention[1]);
		if (!rec || !rec.robloxUserId) {
			return { error: "That Discord user hasn't linked a Roblox account (`/whitelist edit`), so there's nobody to send it to." };
		}
		return { robloxUserId: rec.robloxUserId, robloxName: rec.robloxUsername, discordUserId: mention[1] };
	}

	const resolved = await resolveRobloxUser(raw);
	if (resolved.error) return { error: resolved.error };

	let discordUserId = null;
	const revRaw = await env.KEYS.get(`roblox:${resolved.id}`);
	if (revRaw) {
		try { discordUserId = JSON.parse(revRaw).discordUserId || null; } catch { /* unbound */ }
	}
	return { robloxUserId: resolved.id, robloxName: resolved.name, discordUserId };
}

/**
 * The single gate both troll paths (Discord `/troll` and in-game POST /troll)
 * go through: invoker must be Privileged or above AND strictly outrank the
 * target. Returns { error } or { targetName }.
 */
export async function authorizeTroll(env, invokerDiscordId, { target, action, seconds, message }, ctx) {
	const invokerRec = await getRecord(env, invokerDiscordId);
	if (invokerRec && invokerRec.banned) return { error: "You're banned from using Vain's whitelist commands." };

	const invokerRank = await resolveRank(env, invokerDiscordId, ctx);
	const problem = rankProblem(invokerRank);
	if (problem) return { error: problem };
	if (levelOf(invokerRank.tier) < RANK_LEVEL.priviliged) {
		return { error: "Troll commands are Privileged and above only -- your roles read as Free." };
	}

	const found = await resolveTrollTarget(env, target);
	if (found.error) return { error: found.error };

	const targetTier = found.discordUserId ? (await resolveRank(env, found.discordUserId, ctx)).tier : null;
	if (levelOf(invokerRank.tier) <= levelOf(targetTier)) {
		return { error: "You can only troll someone at a strictly lower rank than you." };
	}

	const { cmd, error } = normalizeCommand({
		action,
		seconds,
		message,
		from: (invokerRec && invokerRec.robloxUsername) || "someone",
	});
	if (error) return { error };

	const queued = await enqueueCommand(env, found.robloxUserId, cmd);
	if (queued.error) return { error: queued.error };

	return { targetName: found.robloxName || found.robloxUserId };
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
		const problem = rankProblem(rank);
		await sendFollowup(
			env,
			interaction,
			`Roblox: **${rec.robloxUsername}**\nCurrent rank: ${problem ? "unknown" : rank.tier || "Free"}` +
			(problem ? `\n⚠️ ${problem}` : "") +
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

async function cmdWhitelistToken(interaction, env, ctx) {
	const invokerId = interaction.member.user.id;

	ctx.waitUntil((async () => {
		const rank = await resolveRank(env, invokerId, ctx);
		const problem = rankProblem(rank);
		if (problem) return sendFollowup(env, interaction, `⚠️ ${problem}`);
		if (levelOf(rank.tier) < RANK_LEVEL.priviliged) {
			return sendFollowup(
				env,
				interaction,
				"❌ Tokens are only useful to Privileged and above -- they authenticate in-game troll commands. " +
				"Your roles read as **Free**: check that you actually hold one of the role IDs listed under " +
				"`[vars.RANK_ROLES]` in wrangler.toml (being the server owner isn't the same as having the owner role)."
			);
		}
		const token = await issueToken(env, invokerId);
		await sendFollowup(
			env,
			interaction,
			"Your in-game token (paste it into Vain -> Settings -> General -> Token). " +
			"Anyone holding it can troll as you, so don't share or stream it -- re-run this command to rotate.\n" +
			`||\`${token}\`||`
		);
	})());

	return json({ type: 5, data: { flags: 64 } });
}

// ---- troll commands -------------------------------------------------------

function flatOption(interaction, name) {
	const opt = (interaction.data.options || []).find((o) => o.name === name);
	return opt ? opt.value : undefined;
}

// One handler behind every troll command: /fling, /kick, /spin ... differ only
// in interaction.data.name, which IS the action, so there's nothing per-command
// to keep in sync -- adding an entry to TROLL_ACTIONS gives you the slash
// command (register-commands.mjs generates it) and the routing (HANDLERS below).
async function cmdTrollAction(interaction, env, ctx) {
	const invokerId = interaction.member.user.id;
	const action = interaction.data.name;
	const target = flatOption(interaction, "target");
	const seconds = flatOption(interaction, "seconds");
	const message = flatOption(interaction, "message");

	ctx.waitUntil((async () => {
		const result = await authorizeTroll(env, invokerId, { target, action, seconds, message }, ctx);
		if (result.error) return sendFollowup(env, interaction, `❌ ${result.error}`);
		await sendFollowup(
			env,
			interaction,
			`✅ Queued **${action}** for **${result.targetName}**. It fires the next time their Vain client checks in ` +
			"(within a few seconds) -- nothing happens if they aren't running Vain."
		);
	})());

	return json({ type: 5, data: { flags: 64 } });
}

// Discord's 2000-char message cap, minus room for the "+N more" line.
const LIST_LIMIT = 40;

async function cmdList(interaction, env, ctx) {
	const invokerId = interaction.member.user.id;

	ctx.waitUntil((async () => {
		const rank = await resolveRank(env, invokerId, ctx);
		const problem = rankProblem(rank);
		if (problem) return sendFollowup(env, interaction, `⚠️ ${problem}`);
		if (levelOf(rank.tier) < RANK_LEVEL.priviliged) {
			return sendFollowup(env, interaction, "❌ Privileged and above only.");
		}

		const online = await listPresence(env);
		if (online.length === 0) {
			return sendFollowup(env, interaction, "Nobody is injected right now.");
		}

		// No per-entry "seen Xs ago": the timestamp we hold is when the heartbeat
		// key was last WRITTEN, and writes are throttled to once per
		// PRESENCE_REFRESH to stay inside KV's write budget -- so someone polling
		// this very second can carry a two-minute-old timestamp. Printing it reads
		// as "they're idle" when it only ever meant "we last wrote it then". What
		// the key's existence genuinely tells us is the window in the header.
		const lines = online.slice(0, LIST_LIMIT).map((p) =>
			`• **${p.name || p.robloxUserId}** (${p.robloxUserId})` + (p.place ? ` — place ${p.place}` : "")
		);
		if (online.length > LIST_LIMIT) lines.push(`…and ${online.length - LIST_LIMIT} more`);

		await sendFollowup(
			env,
			interaction,
			`**${online.length} injected** _(anyone who checked in within the last ${Math.round(PRESENCE_TTL / 60)} min)_\n` +
			lines.join("\n")
		);
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
	"whitelist:token": cmdWhitelistToken,
	"whitelistadmin:lookup": cmdLookup,
	"whitelistadmin:force": cmdForce,
	"whitelistadmin:ban": cmdBan,
	"whitelistadmin:unban": cmdUnban,
	// One flat command per troll action (/fling, /kick, ...) -- keyed by bare
	// name, see routeCommand.
	...Object.fromEntries(ACTION_NAMES.map((action) => [action, cmdTrollAction])),
	list: cmdList,
};

function routeCommand(interaction, env, ctx) {
	const name = interaction.data.name;
	// Only options[0] of type 1/2 (SUB_COMMAND / SUB_COMMAND_GROUP) is a
	// subcommand -- for a flat command like /troll, options[0] is just its first
	// argument, so route on the bare command name instead.
	const first = interaction.data.options && interaction.data.options[0];
	const sub = first && (first.type === 1 || first.type === 2) ? first.name : null;
	const fn = HANDLERS[sub ? `${name}:${sub}` : name];
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
