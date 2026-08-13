/**
 * One Durable Object per Roblox user id: that player's command inbox.
 *
 * This exists because KV cannot do the one thing this feature actually needs --
 * tell somebody that something arrived. Commands used to sit in KV until the
 * target's client next looked, and KV caches reads at the edge (misses
 * included) with a 60 SECOND floor, so a command could take that long to become
 * visible to a client that had been polling the same key. That was the 10-15s
 * delay. A Durable Object is a single addressable point for one player, so the
 * sender's request can hand the command straight to the connection that is
 * waiting for it.
 *
 * Three ways in, in descending order of how good they are:
 *
 *   /ws    A hibernatable WebSocket. The client holds it open and sends nothing
 *          but an occasional heartbeat -- no repeated HTTP requests at all --
 *          and a pushed command arrives in milliseconds. This is the path that
 *          removes the "a request every N seconds" problem outright.
 *   /wait  Long poll, for executors with no WebSocket support. Still instant on
 *          delivery (the push resolves the parked request rather than a timer
 *          noticing later), just one request per hold.
 *   /push  What the sender calls. Delivers to a live socket, else to a parked
 *          long poll, else parks it in storage for whenever they next appear.
 *
 * Storage is only for commands that arrive while nobody is listening. Anything
 * delivered to a live listener never touches it.
 */

import { MAX_AGE_MS, MAX_QUEUED, touchPresence } from "./troll.js";

// Matches the old KV hold: a parked long poll answers empty after this, so the
// client's request cycles rather than sitting open forever.
const MAX_HOLD_SECONDS = 20;

export class Inbox {
	constructor(state, env) {
		this.state = state;
		this.env = env;
		// Parked /wait requests. In-memory is correct: a Durable Object cannot
		// hibernate while it has a request in flight, so these always outlive
		// their own wait.
		this.waiters = [];
	}

	async fetch(request) {
		const url = new URL(request.url);
		switch (url.pathname) {
			case "/ws":
				return this.openSocket(request, url);
			case "/push":
				return this.push(await request.json());
			case "/wait":
				return this.wait(url);
			default:
				return new Response("not found", { status: 404 });
		}
	}

	// ---- delivery ------------------------------------------------------------

	/** Commands held for a listener that wasn't there, minus anything stale. */
	async drainStored() {
		const stored = (await this.state.storage.get("queue")) || [];
		if (stored.length > 0) await this.state.storage.delete("queue");
		const cutoff = Date.now() - MAX_AGE_MS;
		return stored.filter((cmd) => (cmd.at || 0) >= cutoff);
	}

	async push(cmd) {
		const sockets = this.state.getWebSockets();
		if (sockets.length > 0) {
			const payload = JSON.stringify({ commands: [cmd] });
			for (const ws of sockets) {
				try { ws.send(payload); } catch { /* a dead socket is closed for us */ }
			}
			return Response.json({ delivered: "socket" });
		}

		const waiter = this.waiters.shift();
		if (waiter) {
			waiter([cmd]);
			return Response.json({ delivered: "wait" });
		}

		const stored = (await this.state.storage.get("queue")) || [];
		if (stored.length >= MAX_QUEUED) {
			return Response.json({ error: "That player already has the maximum number of pending commands -- let them land first." });
		}
		stored.push(cmd);
		await this.state.storage.put("queue", stored);
		return Response.json({ delivered: "stored" });
	}

	// ---- long poll -----------------------------------------------------------

	async wait(url) {
		const stored = await this.drainStored();
		if (stored.length > 0) return Response.json({ commands: stored });

		const hold = Math.min(MAX_HOLD_SECONDS, Math.max(0, Number(url.searchParams.get("wait")) || 0));
		if (hold === 0) return Response.json({ commands: [] });

		const commands = await new Promise((resolve) => {
			const deliver = (cmds) => {
				clearTimeout(timer);
				this.waiters = this.waiters.filter((w) => w !== deliver);
				resolve(cmds);
			};
			const timer = setTimeout(() => deliver([]), hold * 1000);
			this.waiters.push(deliver);
		});
		return Response.json({ commands });
	}

	// ---- websocket -----------------------------------------------------------

	async openSocket(request, url) {
		if (request.headers.get("upgrade") !== "websocket") {
			return new Response("expected websocket", { status: 426 });
		}

		const pair = new WebSocketPair();
		// acceptWebSocket (not ws.accept) is the hibernation API: the object can
		// be evicted from memory while the connection stays open, so an idle
		// player costs nothing to keep listening.
		this.state.acceptWebSocket(pair[1]);
		pair[1].serializeAttachment({
			robloxUserId: url.searchParams.get("id"),
			name: url.searchParams.get("name"),
			place: url.searchParams.get("place"),
		});

		// Anything that arrived while they were away goes out immediately.
		const stored = await this.drainStored();
		if (stored.length > 0) {
			try { pair[1].send(JSON.stringify({ commands: stored })); } catch { /* they'll reconnect */ }
		}

		return new Response(null, { status: 101, webSocket: pair[0] });
	}

	// Heartbeats. The content doesn't matter -- receiving one means they're still
	// here, which is the presence signal /list reads. touchPresence throttles the
	// KV write itself, so this stays cheap however often they ping.
	async webSocketMessage(ws, message) {
		const info = ws.deserializeAttachment() || {};
		if (!info.robloxUserId) return;
		await touchPresence(this.env, info.robloxUserId, { name: info.name, place: info.place });
		try { ws.send('{"commands":[]}'); } catch { /* closing */ }
	}

	async webSocketClose(ws, code, reason, wasClean) {
		try { ws.close(code, reason); } catch { /* already gone */ }
	}
}
