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

// Cloudflare KV's expirationTtl floor is 60s; 120 gives a client that's
// mid-teleport (poll loop restarted) a chance to still pick a command up.
export const QUEUE_TTL = 120;

// Per-target queue cap -- stops one person from stacking 50 effects on someone.
export const MAX_QUEUED = 5;

// A command older than this is dropped by the client instead of run (belt and
// braces alongside QUEUE_TTL, which the KV side already enforces).
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
	notify: { timed: false, message: true,  blurb: "Pop a Vain notification on their screen" },
	kick:   { timed: false, message: true,  blurb: "Disconnect them from the game" },
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

	if (spec.message) {
		const text = sanitizeMessage(message);
		cmd.message = text || (key === "kick" ? "Trolled by Vain." : "You've been trolled.");
	}

	return { cmd };
}

const queueKey = (robloxUserId) => `cmdq:${robloxUserId}`;

async function readQueue(env, robloxUserId) {
	const raw = await env.KEYS.get(queueKey(robloxUserId));
	if (!raw) return [];
	try {
		const parsed = JSON.parse(raw);
		return Array.isArray(parsed) ? parsed : [];
	} catch {
		return [];
	}
}

/**
 * Append a command to the target's pending queue.
 *
 * KV has no compare-and-swap, so two commands enqueued for the same target in
 * the same instant can clobber each other -- acceptable here (worst case one
 * joke effect doesn't fire), and the alternative (a Durable Object per player)
 * is a lot of machinery for a troll queue.
 */
export async function enqueueCommand(env, robloxUserId, cmd) {
	const queue = await readQueue(env, robloxUserId);
	if (queue.length >= MAX_QUEUED) {
		return { error: "That player already has the maximum number of pending commands -- let them land first." };
	}
	queue.push(cmd);
	await env.KEYS.put(queueKey(robloxUserId), JSON.stringify(queue), { expirationTtl: QUEUE_TTL });
	return { queued: queue.length };
}

/**
 * Hand a client its pending commands and clear them (each command runs once).
 */
export async function takeCommands(env, robloxUserId) {
	const queue = await readQueue(env, robloxUserId);
	if (queue.length > 0) await env.KEYS.delete(queueKey(robloxUserId));
	const cutoff = Date.now() - MAX_AGE_MS;
	return queue.filter((c) => c && typeof c.action === "string" && (c.at || 0) >= cutoff);
}
