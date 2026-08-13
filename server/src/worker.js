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
 */

import { handleDiscordInteraction, resolveRank } from "./discord.js";

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

export default {
	async fetch(req, env, ctx) {
		const url = new URL(req.url);

		if (url.pathname === "/discord/interactions" && req.method === "POST") {
			return handleDiscordInteraction(req, env, ctx);
		}

		const rankMatch = url.pathname.match(/^\/rank\/(\d+)$/);
		if (rankMatch && req.method === "GET") {
			return handleRankLookup(env, rankMatch[1], ctx);
		}

		return json({ error: "not found" }, 404);
	},
};
