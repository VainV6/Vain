# Vain delivery + access control

Serves the **private** `VainV6/Vain` repo through a Cloudflare Worker gated by a
per-user **key + HWID lock**. The GitHub PAT lives only in the Worker (as a
secret); users never see it. The only thing users get is `entrypoint.lua` with
their key filled in.

## How it fits together

```
user runs entrypoint.lua (key + HWID)
        │  hooks HttpGet: raw.githubusercontent.com/VainV6/Vain/*  ->  Worker
        ▼
Cloudflare Worker  ──(checks key+HWID in KV)──►  GitHub Contents API (PAT)
        │                                             │
        └───────── file body (or 403 stub) ◄──────────┘
```

Because the entrypoint transparently redirects Vain's existing raw fetches to
the Worker, **the rest of Vain needs no changes** — init.lua, guis, libraries
and per-game files keep their existing URLs.

## One-time deploy

1. **Make the repo private** on GitHub (Settings → Danger Zone → Change visibility).

2. **Fine-grained PAT** for the Worker: GitHub → Settings → Developer settings →
   Fine-grained tokens → only repository access = `VainV6/Vain`,
   Permissions → Repository → **Contents: Read-only**. Copy it.

3. **Install & log in** (from this `server/` dir):
   ```sh
   npm i -g wrangler        # or: npx wrangler ...
   wrangler login
   ```

4. **Create the KV namespace** and paste its id into `wrangler.toml`:
   ```sh
   wrangler kv namespace create KEYS
   # -> copy the id into [[kv_namespaces]] id = "..."
   ```

5. **Set secrets** (never commit these):
   ```sh
   wrangler secret put GITHUB_PAT      # paste the fine-grained PAT
   wrangler secret put ADMIN_TOKEN     # paste any long random string
   ```

6. **Deploy:**
   ```sh
   wrangler deploy
   # note the URL, e.g. https://vain.YOURNAME.workers.dev
   ```

7. Put that URL into `entrypoint.lua` (`WORKER = ...`).

## Managing keys

```sh
export VAIN_WORKER=https://vain.YOURNAME.workers.dev
export VAIN_ADMIN_TOKEN=the-admin-token-you-set

node keys.mjs new --note "buyer alice" --days 30   # -> prints a new key
node keys.mjs info   vain_xxxxx                     # inspect (hwid, expiry...)
node keys.mjs revoke vain_xxxxx                     # kill a key
node keys.mjs reset-hwid vain_xxxxx                 # let a buyer move machines
```

Give each buyer `entrypoint.lua` with their `VAIN_KEY` filled in. The key binds
to the first machine's HWID; a leaked key won't work elsewhere until you
`reset-hwid`.

## Discord whitelist bot (ranks + self-service commands)

A buyer's **Discord role is their rank**. Instead of staff manually running
`keys.mjs new` and DMing a key, a member with a qualifying rank role runs
`/whitelist edit <roblox account>` themselves and gets a key back the same way
`keys.mjs new` would give one -- the key stays the real credential, the
Roblox account you give the bot is only ever used for display/lookup, never
trusted as authentication (a Roblox UserId is public, not a secret). Every
delivery request also live-checks that the key's linked Discord user still
holds a qualifying role (cached 60s), so removing the role kills access
automatically -- no manual revoke needed.

### One-time Discord setup

1. [Discord Developer Portal](https://discord.com/developers/applications) →
   **New Application**.
2. **Bot** tab → Add Bot → copy the token:
   ```sh
   wrangler secret put DISCORD_BOT_TOKEN
   ```
3. **General Information** tab → copy **Application ID** and **Public Key**
   into `wrangler.toml`'s `[vars]` block (`DISCORD_APPLICATION_ID`,
   `DISCORD_PUBLIC_KEY`).
4. **OAuth2 → URL Generator** → scopes `bot` + `applications.commands` (no
   elevated bot permissions needed -- rank checks are plain REST calls with
   the bot token, not gateway intents). Use the generated URL to invite the
   bot to your server.
5. With Developer Mode on in Discord, copy: your server's ID
   (`DISCORD_GUILD_ID`), each rank role's ID (into `[vars.RANK_ROLES]`, and
   list the tier names in priority order in `RANK_ORDER`), and your staff
   role's ID (`DISCORD_STAFF_ROLE_ID`).
6. **Deploy first, wire the endpoint second** -- the Interactions Endpoint URL
   can't be saved until the Worker is live to answer Discord's signature
   handshake:
   ```sh
   wrangler deploy
   ```
   Then in the Developer Portal → **General Information** → **Interactions
   Endpoint URL**, set `https://<worker>.workers.dev/discord/interactions` and
   save. Discord fires a signed PING at save time and won't save until it gets
   a valid signed PONG back.
7. Register the commands (guild-scoped, so they show up in seconds):
   ```sh
   export DISCORD_APPLICATION_ID=... DISCORD_GUILD_ID=... DISCORD_BOT_TOKEN=...
   npm run register-commands
   ```

### Commands

Self-service (open to anyone, rank-gated at invocation):
- `/whitelist edit <roblox_account>` -- link/re-link your Roblox account,
  returns your key. Re-running it rebinds the same key to a new account
  rather than minting a second one -- one Roblox account per Discord user.
- `/whitelist view` -- your current binding, HWID status, live rank.
- `/whitelist remove` -- unlink and revoke your key.

Staff-only (`/whitelistadmin`, gated by Discord permissions + your staff role):
- `/whitelistadmin lookup <target>` -- inspect by mention, Roblox username, or key.
- `/whitelistadmin resethwid <target>` -- let a buyer move machines.
- `/whitelistadmin force <discord_user> <roblox_account>` -- override a
  binding regardless of rank, can steal an already-claimed Roblox account.
- `/whitelistadmin ban <target>` -- hard-block a record; survives re-binding.

Admin-issued keys from `keys.mjs` keep working exactly as before (no
`discordUserId` on the record means the rank check is skipped entirely).

## Honest limits

An executor must be handed runnable Lua, so someone hooking `loadstring` /
`HttpGet` can still dump the delivered source. This setup stops **public
readability** (private repo, no raw URLs) and **casual copying/sharing** (key +
HWID), and lets you **revoke** access. For stronger protection, run the served
Lua through an obfuscator in the Worker before returning it (add a transform in
`ghFetch`'s response path).
