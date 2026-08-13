# Vain rank bot + public rank API

Vain itself loads the normal public way — see the root [`README.md`](../README.md)'s
plain `loadstring` snippet. This Worker is **not** in that path at all; nothing
here gates access to the code.

What it does instead: a member's **Discord role is their rank** (Free/unbound
< Privileged < Owner), and that rank does two things elsewhere in the codebase:

- **Target immunity** (`libraries/entity.lua`) — every Vain client polls
  `GET /rank/<robloxUserId>` on this Worker for any player it might target. A
  lower rank's modules (Killaura, ESP, aimbots, ...) can never see a higher
  rank as a valid target. This is a courtesy protection, not a security
  boundary — client-side, it can be patched out by someone determined enough,
  same as everything else in this codebase.
- **Command hierarchy** (`/whitelistadmin` below) — a rank can run moderation
  commands on anyone at a *strictly lower* rank. Owner acts on
  Privileged/Free, Privileged acts on Free only, Free can't run these at all.

`/whitelist edit` just binds a Discord identity to a Roblox account, open to
**everyone** including Free — it's identity mapping, not a privilege, and it's
what the rank checks above resolve against.

## How it fits together

```
Vain client (any rank)
    │  GET /rank/<robloxUserId>  (polled per potential target)
    ▼
Cloudflare Worker  ──(roblox:<id> → discord:<id> → live guild-member role)──►  Discord API
    │
    └── { tier: "owner" | "priviliged" | null }

Discord member
    │  /whitelist edit, /whitelistadmin ...
    ▼
Cloudflare Worker  (POST /discord/interactions, Ed25519-signed)
```

## One-time deploy

1. **Install & log in** (from this `server/` dir):
   ```sh
   npm i -g wrangler        # or: npx wrangler ...
   wrangler login
   ```
2. **Create the KV namespace** and paste its id into `wrangler.toml`:
   ```sh
   wrangler kv namespace create KEYS
   # -> copy the id into [[kv_namespaces]] id = "..."
   ```
3. [Discord Developer Portal](https://discord.com/developers/applications) →
   **New Application**.
4. **Bot** tab → Add Bot → copy the token:
   ```sh
   wrangler secret put DISCORD_BOT_TOKEN
   ```
5. **General Information** tab → copy **Application ID** and **Public Key**
   into `wrangler.toml`'s `[vars]` block (`DISCORD_APPLICATION_ID`,
   `DISCORD_PUBLIC_KEY`).
6. **OAuth2 → URL Generator** → scopes `bot` + `applications.commands` (no
   elevated bot permissions needed — rank checks are plain REST calls with
   the bot token, not gateway intents). Use the generated URL to invite the
   bot to your server.
7. With Developer Mode on in Discord, copy your server's ID
   (`DISCORD_GUILD_ID`) and each rank role's ID into `[vars.RANK_ROLES]`
   (listing the tier names in priority order in `RANK_ORDER`).
8. **Deploy first, wire the endpoint second** — the Interactions Endpoint URL
   can't be saved until the Worker is live to answer Discord's signature
   handshake:
   ```sh
   wrangler deploy
   ```
   Then in the Developer Portal → **General Information** → **Interactions
   Endpoint URL**, set `https://<worker>.workers.dev/discord/interactions` and
   save. Discord fires a signed PING at save time and won't save until it gets
   a valid signed PONG back.
9. Register the commands (guild-scoped, so they show up in seconds):
   ```sh
   export DISCORD_APPLICATION_ID=... DISCORD_GUILD_ID=... DISCORD_BOT_TOKEN=...
   npm run register-commands
   ```
10. Point `RANK_API` in `libraries/entity.lua` at your deployed Worker URL if
    it ever changes (currently hardcoded to `https://vain.baconcrafft.workers.dev`).

## Commands

Self-service (open to everyone, Free rank included — no gate):
- `/whitelist edit <roblox_account>` — link/re-link your Roblox account.
  Re-running it rebinds the same record to a new account rather than creating
  a second one — one Roblox account per Discord user.
- `/whitelist view` — your bound account + live rank.
- `/whitelist remove` — unlink.

Rank-hierarchy (`/whitelistadmin`, usable only on someone at a strictly lower
rank than the invoker — enforced at runtime per request, not a static Discord
permission, so anyone can attempt these and gets a clear rejection if not
allowed):
- `/whitelistadmin lookup <target>` — inspect by mention or Roblox username.
- `/whitelistadmin force <discord_user> <roblox_account>` — override a
  binding, can steal an already-claimed Roblox account.
- `/whitelistadmin ban <target>` — blocks a record from ever (re)binding.
- `/whitelistadmin unban <target>` — reverses a ban.

## Honest limits

This is a courtesy system, not a security boundary. Anything enforced
client-side (the target-immunity check in `libraries/entity.lua`) can be
patched out by someone willing to edit the Lua before running it — same
caveat as every other client-side protection in this codebase. What this
setup actually buys: a low-friction way for Discord roles to translate into
in-game recognition and a moderation command surface, not tamper-resistance.
