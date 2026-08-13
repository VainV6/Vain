/**
 * Troll-command catalogue + delivery queue.
 *
 * A ranked member (Privileged or Owner) can fire a small, FIXED set of joke
 * effects at a STRICTLY lower-ranked player, either from Discord (one slash
 * command per action -- /fling, /kick, ... -- all handled by cmdTrollAction in
 * ./discord.js and generated from the catalogue below by
 * ../register-commands.mjs) or from inside the game (Vain's Troll Commands
 * module -> POST /troll, see ../../libraries/troll.lua). Both paths funnel through
 * authorizeTroll() in ./discord.js for the rank check, then land here.
 *
 * Delivery is a pull queue, not a push: enqueueCommand() drops the command in
 * KV under the TARGET's Roblox user id, and that player's own Vain client
 * picks it up on its next GET /commands/<robloxUserId> poll (takeCommands()).
 * Two consequences worth being explicit about:
 *   - Commands only ever land on someone RUNNING VAIN. A target who isn't
 *     injected has nothing polling, so the command just expires unseen.
 *   - The catalogue below is the entire vocabulary. There is deliberately no
 *     "run this code" action -- the queue carries an action NAME plus a
 *     duration/message, never anything the receiving client executes as code.
 *
 * Entries expire after QUEUE_TTL seconds so a command queued for an offline
 * player doesn't ambush them an hour later.
 */

// Per-target cap on commands waiting for someone who isn't listening -- stops
// one person stacking 50 effects on a player who is offline.
export const MAX_QUEUED = 5;

// How long a command held for an absent player stays worth delivering. Nothing
// expires it in storage; the inbox drops anything older than this when it
// flushes, which is simpler and means a stale command can never ambush someone
// an hour later.
export const MAX_AGE_MS = 90 * 1000;

export const MIN_SECONDS = 1;
export const MAX_SECONDS = 15;
export const DEFAULT_SECONDS = 5;
export const MAX_MESSAGE = 120;

/**
 * The whole vocabulary. `timed` actions take a duration, `message` actions
 * take (or default) a bit of text -- and each key is also the NAME of its slash
 * command, so adding an entry here creates /<key> on the next
 * `npm run register-commands` with no other edit on the Discord side.
 *
 * Client-side implementations live in libraries/troll.lua -- keep the key names
 * in sync with the EFFECTS table there, they're the wire format.
 */
export const TROLL_ACTIONS = {
	fling:  { timed: false, message: false, blurb: "Launch their character across the map" },
	spin:   { timed: true,  message: false, blurb: "Spin their character like a top" },
	freeze: { timed: true,  message: false, blurb: "Anchor them in place" },
	shake:  { timed: true,  message: false, blurb: "Shake their camera" },
	invert: { timed: true,  message: false, blurb: "Invert their movement controls" },
	blind:  { timed: true,  message: false, blurb: "Black out their screen" },
	speed:  { timed: true,  message: false, blurb: "Make them uncontrollably fast" },
	lag:    { timed: true,  message: false, blurb: "Rubber-band them with fake lag" },
	drunk:  { timed: true,  message: false, blurb: "Roll their camera around drunkenly" },
	flip:   { timed: true,  message: false, blurb: "Turn their camera upside down" },
	zoom:   { timed: true,  message: false, blurb: "Yank their field of view to a fisheye" },
	void:   { timed: false, message: false, blurb: "Drop them through the map" },
	say:    { timed: false, message: true,  blurb: "Make them say something in chat" },
	notify: { timed: false, message: true,  blurb: "Pop a Vain notification on their screen" },
	kill:   { timed: false, message: false, blurb: "Kill their character" },
	// Fixed reason, not sender-supplied: the point is that it reads as an
	// ordinary disconnect rather than as anything to do with Vain.
	kick:   {
		timed: false,
		message: false,
		fixedMessage: "Please check your internet connection",
		blurb: "Disconnect them from the game",
	},
	uninject: { timed: false, message: false, blurb: "Uninject their Vain immediately" },
};

export const ACTION_NAMES = Object.keys(TROLL_ACTIONS);

// Vain notifications render as RichText, so angle brackets in a user-supplied
// message would be swallowed as (or break) markup -- strip them rather than
// letting someone inject <font> tags into the victim's notification.
function sanitizeMessage(raw) {
	return String(raw || "")
		.replace(/[<>]/g, "")
		.replace(/\s+/g, " ")
		.trim()
		.slice(0, MAX_MESSAGE);
}

/**
 * Validate + clamp raw user input into the exact command object that goes on
 * the wire. Returns { error } or { cmd }.
 */
export function normalizeCommand({ action, seconds, message, from }) {
	const key = String(action || "").toLowerCase().trim();
	const spec = TROLL_ACTIONS[key];
	if (!spec) {
		return { error: `Unknown action "${action}". Try one of: ${ACTION_NAMES.join(", ")}.` };
	}

	const cmd = {
		id: crypto.randomUUID(),
		action: key,
		from: sanitizeMessage(from) || "someone",
		at: Date.now(),
	};

	if (spec.timed) {
		const n = Number(seconds);
		cmd.seconds = Math.min(MAX_SECONDS, Math.max(MIN_SECONDS, Number.isFinite(n) ? Math.floor(n) : DEFAULT_SECONDS));
	}

	if (spec.fixedMessage) {
		cmd.message = spec.fixedMessage;
	} else if (spec.message) {
		cmd.message = sanitizeMessage(message) || "You've been trolled.";
	}

	return { cmd };
}

/** The Durable Object that is this player's inbox (see ./inbox.js). */
export function inboxFor(env, robloxUserId) {
	return env.INBOX.get(env.INBOX.idFromName(String(robloxUserId)));
}

/**
 * Hand a command to the target's inbox. The object delivers it straight to a
 * live WebSocket or a parked long poll -- nothing polls, and nothing waits for
 * a cache to expire. It only lands in storage if the player isn't listening at
 * all, which is also the only case where QUEUE_TTL/MAX_QUEUED matter.
 */
export async function enqueueCommand(env, robloxUserId, cmd) {
	const res = await inboxFor(env, robloxUserId).fetch("https://inbox/push", {
		method: "POST",
		headers: { "content-type": "application/json" },
		body: JSON.stringify(cmd),
	});
	const body = await res.json();
	if (body.error) return { error: body.error };
	return { delivered: body.delivered };
}

// ---- presence ---------------------------------------------------------------
// Every injected client already polls for its own commands, so that poll doubles
// as a heartbeat and /list is just "who has a live heartbeat key".
//
// The TTLs below exist because of KV's write budget, not because 3 minutes is a
// natural resolution: the free plan allows ~1k writes/day, and writing a key on
// every 5s poll would burn that in under two user-hours. So a poll only writes
// when the existing key is older than PRESENCE_REFRESH -- reads are 100x more
// generous than writes, so checking first is nearly free. Raise both if you want
// tighter "currently injected" resolution and have the write budget for it.
// Rough cost of a change here: one injected user burns 3600/PRESENCE_REFRESH
// writes an hour (24/h at 150s). The free plan's ~1k/day therefore covers about
// 40 user-hours a day; halving PRESENCE_REFRESH halves that. Whatever you pick,
// PRESENCE_TTL is the real resolution of /list -- an entry means "checked in
// within TTL", nothing finer, which is why /list doesn't print an age.
export const PRESENCE_TTL = 180;
const PRESENCE_REFRESH = 150;
const presenceKey = (robloxUserId) => `online:${robloxUserId}`;

// The name/place come off the query string, i.e. from the client, i.e. from
// anyone who can shape an HTTP request -- so treat them as display text only and
// keep them short and inert. They land in a Discord message, never in a lookup.
function sanitizeField(raw, max) {
	return String(raw || "").replace(/[^\w .\-\[\]]/g, "").trim().slice(0, max);
}

/**
 * Record that this player is injected right now. Stores the display fields in
 * KV metadata so /list needs ONE list() call instead of a get() per player.
 */
export async function touchPresence(env, robloxUserId, { name, place }) {
	const existing = await env.KEYS.getWithMetadata(presenceKey(robloxUserId));
	const seenAt = existing && existing.metadata && existing.metadata.at;
	if (seenAt && Date.now() - seenAt < PRESENCE_REFRESH * 1000) return;

	await env.KEYS.put(presenceKey(robloxUserId), "1", {
		expirationTtl: PRESENCE_TTL,
		metadata: {
			at: Date.now(),
			name: sanitizeField(name, 32),
			place: sanitizeField(place, 24),
		},
	});
}

/**
 * Everyone with a live heartbeat, newest first.
 */
export async function listPresence(env) {
	const { keys } = await env.KEYS.list({ prefix: "online:" });
	return keys
		.map((k) => ({
			robloxUserId: k.name.slice("online:".length),
			name: (k.metadata && k.metadata.name) || "",
			place: (k.metadata && k.metadata.place) || "",
			at: (k.metadata && k.metadata.at) || 0,
		}))
		.sort((a, b) => b.at - a.at);
}

export const HOLD_MAX = 20;
