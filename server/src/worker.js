/**
 * Vain Discord bot + public rank API Worker.
 *
 * Vain itself loads the normal public way (see the root README.md's plain
 * loadstring snippet) -- this Worker is NOT in that path at all. Its jobs:
 *
 *   POST /discord/interactions  -> Discord slash-command interactions (see
 *                                  ./discord.js). A member's Discord ROLE is
 *                                  their RANK (Free/unbound, Privileged, Owner).
 *   GET  /rank/<robloxUserId>   -> { tier: "owner" | "priviliged" | null },
 *                                  public/unauthenticated. Polled by every
 *                                  Vain client (libraries/entity.lua) to find
 *                                  out another player's rank for the target-
 *                                  immunity feature: a lower rank's targeting
 *                                  modules can never see a higher rank as a
 *                                  valid target.
 *   POST /troll                 -> queue a troll command from IN-GAME. Bearer
 *                                  token from `/whitelist token` (the client
 *                                  has no Discord signature to offer), same
 *                                  rank gate as the per-action slash commands
 *                                  (/fling, /kick, ...).
 *   GET  /commands/<robloxUserId>
 *                               -> pending troll commands for that player,
 *                                  cleared as they're handed over. Polled by
 *                                  every Vain client for ITSELF (see
 *                                  libraries/troll.lua). Public, like /rank:
 *                                  the commands are jokes, not secrets. A
 *                                  third party polling someone else's id can
 *                                  swallow a command before it lands, which is
 *                                  a nuisance, not a compromise.
 */

import { handleDiscordInteraction, resolveRank, authorizeTroll, discordUserIdFromToken } from "./discord.js";
import { takeCommands } from "./troll.js";

function json(obj, status = 200) {
	return new Response(JSON.stringify(obj), {
		status,
		headers: { "content-type": "application/json; charset=utf-8" },
	});
}

async function handleRankLookup(env, robloxUserId, ctx) {
	const revRaw = await env.KEYS.get(`roblox:${robloxUserId}`);
	if (!revRaw) return json({ tier: null });
	const { discordUserId } = JSON.parse(revRaw);
	const rank = await resolveRank(env, discordUserId, ctx);
	return json({ tier: rank.tier });
}

async function handleTrollPost(req, env, ctx) {
	const token = (req.headers.get("authorization") || "").replace(/^Bearer\s+/i, "").trim();
	const invokerDiscordId = await discordUserIdFromToken(env, token);
	if (!invokerDiscordId) {
		return json({ error: "Invalid or expired token -- run /whitelist token in Discord for a fresh one." }, 401);
	}

	let body;
	try {
		body = await req.json();
	} catch {
		return json({ error: "Malformed body." }, 400);
	}

	const result = await authorizeTroll(env, invokerDiscordId, body, ctx);
	if (result.error) return json({ error: result.error }, 403);
	return json({ ok: true, target: result.targetName });
}

export default {
	async fetch(req, env, ctx) {
		const url = new URL(req.url);

		if (url.pathname === "/discord/interactions" && req.method === "POST") {
			return handleDiscordInteraction(req, env, ctx);
		}

		if (url.pathname === "/troll" && req.method === "POST") {
			return handleTrollPost(req, env, ctx);
		}

		const rankMatch = url.pathname.match(/^\/rank\/(\d+)$/);
		if (rankMatch && req.method === "GET") {
			return handleRankLookup(env, rankMatch[1], ctx);
		}

		const cmdMatch = url.pathname.match(/^\/commands\/(\d+)$/);
		if (cmdMatch && req.method === "GET") {
			return json({ commands: await takeCommands(env, cmdMatch[1]) });
		}

		return json({ error: "not found" }, 404);
	},
};
