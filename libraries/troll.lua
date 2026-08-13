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

-- How often each client asks for its own pending commands. Every injected user
-- polls this forever, so it's also the Worker's steady-state request rate --
-- 5s keeps a joke feeling instant without turning into a request firehose.
local POLL_INTERVAL = 5
-- Never run more than this many effects from a single poll, however many the
-- queue somehow ended up holding.
local MAX_PER_POLL = 3

-- Ordered for the in-game dropdown (Name is what the UI shows, Action is the
-- wire value). Timed actions take Seconds; Message actions take text.
trolllib.Actions = {
	{Name = 'Fling', Action = 'fling', Tooltip = 'Launches their character across the map.'},
	{Name = 'Spin', Action = 'spin', Timed = true, Tooltip = 'Spins their character like a top.'},
	{Name = 'Freeze', Action = 'freeze', Timed = true, Tooltip = 'Anchors them in place.'},
	{Name = 'Shake', Action = 'shake', Timed = true, Tooltip = 'Shakes their camera around.'},
	{Name = 'Invert', Action = 'invert', Timed = true, Tooltip = 'Inverts their movement controls.'},
	{Name = 'Blind', Action = 'blind', Timed = true, Tooltip = 'Blacks out their screen.'},
	{Name = 'Notify', Action = 'notify', Message = true, Tooltip = 'Pops a Vain notification on their screen.'},
	{Name = 'Kick', Action = 'kick', Message = true, Tooltip = 'Disconnects them from the game.'},
}

trolllib.ActionNames = {}
local actionByName = {}
for _, v in trolllib.Actions do
	table.insert(trolllib.ActionNames, v.Name)
	actionByName[v.Name] = v
end

function trolllib.getAction(name)
	return actionByName[name]
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

EFFECTS.notify = function(cmd)
	trolllib.Notify('Vain', cmd.message or "You've been trolled.", 8, 'warning')
end

EFFECTS.kick = function(cmd)
	pcall(function()
		lplr:Kick(cmd.message or 'Trolled by Vain.')
	end)
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

	-- Announce it, then run it -- being trolled with no idea why isn't funny,
	-- and it's also the honest thing to do about a remote effect firing on
	-- someone's client.
	if cmd.action ~= 'notify' and cmd.action ~= 'kick' then
		trolllib.Notify('Vain', tostring(cmd.from or 'Someone')..' used <b>'..cmd.action..'</b> on you.', 6, 'warning')
	end
	task.spawn(effect, cmd)
end

-- ── receiving ────────────────────────────────────────────────────────────────

function trolllib.poll()
	local ok, res = pcall(req, {
		Url = trolllib.API..'/commands/'..tostring(lplr.UserId),
		Method = 'GET',
	})
	if not (ok and res and (res.StatusCode == 200 or res.Success) and res.Body) then return end

	local decOk, decoded = pcall(httpService.JSONDecode, httpService, res.Body)
	if not decOk or type(decoded) ~= 'table' or type(decoded.commands) ~= 'table' then return end

	for i, cmd in decoded.commands do
		if i > MAX_PER_POLL then break end
		trolllib.execute(cmd)
	end
end

function trolllib.start()
	if trolllib.Running or not req then return end
	trolllib.Running = true
	task.spawn(function()
		while trolllib.Running do
			pcall(trolllib.poll)
			task.wait(POLL_INTERVAL)
		end
	end)
end

function trolllib.stop()
	trolllib.Running = false
	table.clear(activeEffects)
	table.clear(seen)
end

-- ── sending ──────────────────────────────────────────────────────────────────

-- Fires POST /troll and calls back with (ok, message). Async: an HTTP round
-- trip on the main thread would hitch the game every time someone hits Send.
function trolllib.send(target, actionName, options, callback)
	callback = callback or function() end
	options = options or {}

	local action = actionByName[actionName]
	if not action then return callback(false, 'Unknown action.') end

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
