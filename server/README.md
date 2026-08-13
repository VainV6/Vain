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
- **Troll commands** (`/fling`, `/kick`, … below, or the in-game Troll Commands
  module) — same strictly-lower-rank rule, Privileged and up. Queues one of a
  fixed set of joke effects for the target's own Vain client to run on itself.

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
    │  /whitelist edit, /whitelistadmin ..., /fling, /kick, ...
    ▼
Cloudflare Worker  (POST /discord/interactions, Ed25519-signed)

Privileged+ Vain client                      target's Vain client
    │  POST /troll (Bearer token)                 │  GET /commands/<own UserId>
    ▼                                             ▼   (polled every 5s)
Cloudflare Worker  ──(rank check, then cmdq:<targetRobloxId>)──► effect runs, queue cleared
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
6. **Bot** tab → **Privileged Gateway Intents** → turn on **Server Members
   Intent**. Rank checks are plain REST calls (no gateway connection), but
   `GET /guilds/{id}/members/{user}` is gated behind that intent — without it
   Discord answers 403 and *everyone* resolves as Free. No elevated bot
   *permissions* are needed beyond that.
7. **OAuth2 → URL Generator** → scopes `bot` + `applications.commands`. Use
   the generated URL to invite the bot to your server.
8. With Developer Mode on in Discord, copy your server's ID
   (`DISCORD_GUILD_ID`) and each rank role's ID into `[vars.RANK_ROLES]`
   (listing the tier names in priority order in `RANK_ORDER`).
9. **Deploy first, wire the endpoint second** — the Interactions Endpoint URL
   can't be saved until the Worker is live to answer Discord's signature
   handshake:
   ```sh
   wrangler deploy
   ```
   Then in the Developer Portal → **General Information** → **Interactions
   Endpoint URL**, set `https://<worker>.workers.dev/discord/interactions` and
   save. Discord fires a signed PING at save time and won't save until it gets
   a valid signed PONG back.
10. Register the commands (guild-scoped, so they show up in seconds):
    ```sh
    export DISCORD_APPLICATION_ID=... DISCORD_GUILD_ID=... DISCORD_BOT_TOKEN=...
    npm run register-commands
    ```
11. Point `RANK_API` in `libraries/entity.lua` at your deployed Worker URL if
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

Troll commands — **one command per action**, all Privileged and above, all
usable only on someone at a strictly lower rank. `<target>` is a Discord
mention (needs a binding) or a Roblox username (works whether or not they've
ever touched Discord — unbound is just Free):

- `/fling <target>` — launch their character across the map.
- `/spin <target> [seconds]` — spin them like a top.
- `/freeze <target> [seconds]` — anchor them in place.
- `/shake <target> [seconds]` — shake their camera.
- `/invert <target> [seconds]` — invert their movement controls.
- `/blind <target> [seconds]` — black out their screen.
- `/notify <target> [message]` — pop a Vain notification on their screen.
- `/kill <target>` — kill their character.
- `/kick <target>` — disconnect them. The reason is fixed ("You have been
  kicked due to suspicious client activity") rather than sender-supplied, so it
  reads as an anti-cheat action and doesn't advertise what actually happened.
- `/uninject <target>` — tear their Vain down immediately. They stop polling, so
  nothing further reaches them until they inject again.

And one that isn't an effect:
- `/list` — everyone injected within the last `PRESENCE_TTL` (3 min).
  Privileged and above. It deliberately shows no per-player "last seen" age:
  see Delivery below for why that number would be fiction.

Plus the token that authenticates the in-game path:
- `/whitelist token` — self-service, Privileged and above: issues the secret
  the *in-game* path authenticates with, and rotates it if you run it again.
  Anyone holding it can troll as you, so treat it like a password.

`seconds` is clamped to 1–15 (default 5) and every timed effect restores what
it touched when it ends. Each command only advertises the inputs its action
actually uses — `/fling` takes no duration, `/kill` takes neither.

Visible pranks tell the victim who hit them (attribution is half the joke);
`notify`, `kill`, `kick` and `uninject` fire silently, since a notification
naming Vain would undo the kick reason's cover story. That's the `Silent` flag
in `trolllib.Actions`.

### Adding an action

The catalogue in [`src/troll.js`](src/troll.js) drives everything: the slash
command and its options are generated from it by
[`register-commands.mjs`](register-commands.mjs), and routing is keyed off the
command name, which *is* the action. So a new effect is two edits — an entry
there, and its implementation in `EFFECTS` in
[`libraries/troll.lua`](../libraries/troll.lua) (those keys are the wire
format) — then `npm run register-commands`.

### In-game path

Deliberately unadvertised: there is **no module**, nothing in the menu names
this feature, and the only visible surface is a bare **Settings → General →
Token** box (label "Token", placeholder "Paste token"). Pasting the token there
writes `vain/profiles/ranktoken.txt` and blanks the box.

Sending from in-game is then `vain.Libraries.troll.send(target, action, opts, cb)`
for anyone who knows it exists — `POST /troll` re-runs the whole rank check
server-side either way, so editing the Lua gets you nothing but a 403. Discord
is the normal way to send.

### Delivery

Commands are **pulled, not pushed**: they sit in `cmdq:<robloxUserId>` until
that player's own client asks for them (`GET /commands/<id>`, every 5s), and
expire after 120s. So a command only ever lands on someone *running Vain* —
send one to a player who isn't injected and it simply evaporates.

That same poll carries `?name=&place=` and doubles as the presence heartbeat
behind `/list` (`online:<robloxUserId>`, in KV metadata so `/list` is one
`list()` call). A poll only *writes* when the existing key is older than
`PRESENCE_REFRESH`, because KV's free tier allows ~1k writes/day and writing
every 5s would exhaust that in under two user-hours.

The consequence is that the stored timestamp is the age of the last *write*,
not of the last poll — a player polling this very second can be carrying a
two-minute-old one. That's why `/list` prints no age: the only thing the data
honestly supports is "checked in within `PRESENCE_TTL`". If you want finer
resolution, lower both constants at the top of [`src/troll.js`](src/troll.js)
and pay for it in writes (one user costs `3600/PRESENCE_REFRESH` writes/hour).

## Honest limits

This is a courtesy system, not a security boundary. Anything enforced
client-side (the target-immunity check in `libraries/entity.lua`, and every
troll effect, which by definition runs on the victim's own machine) can be
patched out by someone willing to edit the Lua before running it — same
caveat as every other client-side protection in this codebase. What this
setup actually buys: a low-friction way for Discord roles to translate into
in-game recognition and a moderation command surface, not tamper-resistance.

Two specifics worth knowing about the troll path:

- `GET /commands/<robloxUserId>` is public and clears the queue, so anyone who
  knows a Roblox user id can poll it and swallow commands meant for that player.
  That's a nuisance (a joke doesn't fire), not a compromise — nothing sensitive
  is in there, and nobody can *send* without a token.
- KV has no compare-and-swap, so two commands queued for the same target in the
  same instant can overwrite each other. Worth exactly what it costs to fix.
