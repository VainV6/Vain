#!/usr/bin/env node
/**
 * Registers /whitelist and /whitelistadmin as guild-scoped slash commands.
 * Guild-scoped (not global) so they propagate instantly instead of up to an
 * hour. Run whenever command shapes change here -- not part of the deployed
 * Worker bundle.
 *
 * Set once:
 *   export DISCORD_APPLICATION_ID=xxxxx
 *   export DISCORD_GUILD_ID=xxxxx
 *   export DISCORD_BOT_TOKEN=xxxxx
 *
 * Usage:
 *   node register-commands.mjs
 */

const APP_ID = process.env.DISCORD_APPLICATION_ID;
const GUILD_ID = process.env.DISCORD_GUILD_ID;
const TOKEN = process.env.DISCORD_BOT_TOKEN;
if (!APP_ID || !GUILD_ID || !TOKEN) {
	console.error("Set DISCORD_APPLICATION_ID, DISCORD_GUILD_ID and DISCORD_BOT_TOKEN env vars first.");
	process.exit(1);
}

// default_member_permissions is a string bitfield; "32" = MANAGE_GUILD, used
// here as the baseline staff gate. worker.js's handlers additionally check
// DISCORD_STAFF_ROLE_ID membership at runtime (defense in depth).
const STAFF_PERMISSIONS = "32";

const commands = [
	{
		name: "whitelist",
		description: "Manage your own Vain whitelist",
		options: [
			{
				type: 1, // SUB_COMMAND
				name: "edit",
				description: "Link (or re-link) your Roblox account and get your key",
				options: [
					{ type: 3, name: "roblox_account", description: "Your Roblox username", required: true },
				],
			},
			{
				type: 1,
				name: "view",
				description: "View your current whitelist status",
			},
			{
				type: 1,
				name: "remove",
				description: "Unlink your account and revoke your key",
			},
		],
	},
	{
		name: "whitelistadmin",
		description: "Staff whitelist management",
		default_member_permissions: STAFF_PERMISSIONS,
		options: [
			{
				type: 1,
				name: "lookup",
				description: "Look up a whitelist record",
				options: [
					{ type: 3, name: "target", description: "Discord mention, Roblox username, or key", required: true },
				],
			},
			{
				type: 1,
				name: "resethwid",
				description: "Unbind a machine from a key",
				options: [
					{ type: 3, name: "target", description: "Discord mention, Roblox username, or key", required: true },
				],
			},
			{
				type: 1,
				name: "force",
				description: "Force-link a Discord user to a Roblox account",
				options: [
					{ type: 6, name: "discord_user", description: "The Discord user", required: true },
					{ type: 3, name: "roblox_account", description: "The Roblox username", required: true },
				],
			},
			{
				type: 1,
				name: "ban",
				description: "Ban a whitelist record from ever binding again",
				options: [
					{ type: 3, name: "target", description: "Discord mention, Roblox username, or key", required: true },
				],
			},
		],
	},
];

async function main() {
	const res = await fetch(`https://discord.com/api/v10/applications/${APP_ID}/guilds/${GUILD_ID}/commands`, {
		method: "PUT",
		headers: {
			authorization: `Bot ${TOKEN}`,
			"content-type": "application/json",
		},
		body: JSON.stringify(commands),
	});
	const body = await res.json();
	if (!res.ok) {
		console.error(`Failed (${res.status}):`, JSON.stringify(body, null, 2));
		process.exit(1);
	}
	console.log(`Registered ${body.length} commands.`);
}
main();
