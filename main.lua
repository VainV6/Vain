repeat task.wait() until game:IsLoaded()
if shared.vain then shared.vain:Uninject() end
shared.VainBedwarsLoaded = nil

local vain
local loadstring = function(...)
	local res, err = loadstring(...)
	if err and vain then
		vain:CreateNotification('Vain', 'Failed to load : '..err, 30, 'alert')
	end
	return res
end
local queue_on_teleport = queue_on_teleport or function() end
local isfile = isfile or function(file)
	local suc, res = pcall(function()
		return readfile(file)
	end)
	return suc and res ~= nil and res ~= ''
end
local cloneref = cloneref or function(obj)
	return obj
end
local playersService = cloneref(game:GetService('Players'))
local httpService = cloneref(game:GetService('HttpService'))

local delfile = delfile or function(file) writefile(file, '') end
-- GitHub raw serves error bodies as short plain text ("400: Invalid request",
-- "404: Not Found", "429: ..."). Caching those as code is what produced the
-- [string "entitylibrary"]:2: ... got '400' error, so never write a "NNN: ..." body.
local function isHttpError(res)
	return type(res) ~= 'string' or res == '' or res:match('^%s*%d%d%d:%s') ~= nil
end
-- Large .lua files sometimes download truncated (HTTP 200, but the body got cut
-- off mid-transfer) -- that still loadstrings fine (valid Lua up to the cut) but
-- silently registers only PART of the file's modules, and the truncated copy then
-- gets cached and reused on every later inject. Every .lua file this repo serves
-- ends with a --VAINEOF sentinel line; refuse to accept/cache a .lua body that's
-- missing it, retrying the fetch a few times first.
local function isTruncatedLua(path, res)
	return path:find('%.lua') ~= nil and not res:find('VAINEOF')
end
local function downloadFile(path, func)
	-- self-heal a previously-cached error body or truncated file
	if isfile(path) and path:find('%.lua') then
		local cached = readfile(path)
		if cached:match('^%s*%d%d%d:%s') or cached:match('^%-%-This watermark[^\n]*\n%s*%d%d%d:%s') or isTruncatedLua(path, cached) then
			delfile(path)
		end
	end
	if not isfile(path) then
		-- surface progress on the Vain loading screen (built lazily in init.lua)
		if getgenv and getgenv().vainLoading then getgenv().vainLoading.status('Downloading '..path) end
		-- readfile throws on a missing commit.txt; guard it and fall back to main.
		local ok, raw = pcall(readfile, 'vain/profiles/commit.txt')
		local commit = (ok and type(raw) == 'string' and raw or ''):match('^%s*(.-)%s*$')
		if commit == '' then commit = 'main' end
		local res
		for attempt = 1, 5 do
			local suc
			suc, res = pcall(function()
				return game:HttpGet('https://raw.githubusercontent.com/VainV6/Vain/'..commit..'/'..select(1, path:gsub('vain/', '')), true)
			end)
			if not suc or isHttpError(res) then
				if attempt == 5 then error('Vain failed to download '..path..' (ref '..commit..'): '..tostring(res)) end
				res = nil
			elseif isTruncatedLua(path, res) then
				res = nil
			else
				break
			end
			if not res then task.wait(0.3) end
		end
		if not res then
			error('Vain failed to download '..path..' (ref '..commit..'): incomplete after 5 attempts')
		end
		if path:find('.lua') then
			res = '--This watermark is used to delete the file if its cached, remove it to make the file persist after vain updates.\n'..res
		end
		writefile(path, res)
		if getgenv and getgenv().vainLoading then getgenv().vainLoading.bump() end
	end
	return (func or readfile)(path)
end

-- Build a map of line number → module display name for a file's content.
-- A module only OWNS the lines inside its own `run(function() … end)` block, so
-- shared helpers, section-separator comments and the next module's preamble are
-- left unowned and can never be mis-tagged as that module being updated.
local function buildLineModuleMap(content)
	local allLines = {}
	for line in content:gmatch('([^\n]*)\n?') do
		table.insert(allLines, line)
	end

	-- find every CreateModule, its display Name, and the bounds of its block
	local moduleStarts = {}
	local lineModules = {}
	for i, line in ipairs(allLines) do
		if line:find(':CreateModule%(') then
			local name
			for j = i, math.min(i + 8, #allLines) do
				name = allLines[j]:match("Name%s*=%s*'([^']+)'")
				    or allLines[j]:match('Name%s*=%s*"([^"]+)"')
				if name then break end
			end
			if name then
				-- block start: nearest preceding top-level `run(function()` wrapper
				-- (col 0). Every module in these files is wrapped in one; fall back to
				-- the CreateModule line itself if none is found nearby.
				local startLine = i
				for k = i, math.max(i - 60, 1), -1 do
					if allLines[k]:match('^run%(function') then
						startLine = k
						break
					end
				end
				-- block end: first top-level `end)` at/after the CreateModule line
				local endLine = #allLines
				for k = i, #allLines do
					if allLines[k]:match('^end%)') then
						endLine = k
						break
					end
				end
				table.insert(moduleStarts, { line = i, name = name })
				for ln = startLine, endLine do
					-- first writer wins so nested blocks don't steal lines
					if lineModules[ln] == nil then lineModules[ln] = name end
				end
			end
		end
	end

	return lineModules, moduleStarts
end

-- Collect the NEW-FILE line numbers that were actually ADDED in a patch (i.e. the
-- '+' lines, never the unchanged context lines a hunk carries). Tracking the real
-- line counter is what makes UPD precise -- context lines used to falsely tag the
-- neighbouring module.
local function parseAddedLines(patch)
	local added = {}
	local newLine = nil
	for line in patch:gmatch('([^\n]*)\n?') do
		local hdr = line:match('^@@ %-%d+,?%d* %+(%d+)')
		if hdr then
			newLine = tonumber(hdr)
		elseif newLine then
			local c = line:sub(1, 1)
			if c == '+' then
				if line:sub(1, 3) ~= '+++' then
					table.insert(added, newLine)
					newLine = newLine + 1
				end
			elseif c == '-' then
				-- removed line: does not advance the new-file counter
			elseif c ~= '\\' then
				-- context line: advances the counter but is NOT a change
				newLine = newLine + 1
			end
		end
	end
	return added
end

-- Detect NEW modules: CreateModule lines that are pure additions in the patch
local function detectNewModulesFromPatch(patch)
	local newMods = {}
	local patchLines = {}
	for line in patch:gmatch('[^\n]+') do
		table.insert(patchLines, line)
	end
	for i, line in ipairs(patchLines) do
		if line:sub(1, 1) == '+' and line:find(':CreateModule%(') then
			for j = i, math.min(i + 8, #patchLines) do
				local name = patchLines[j]:match("Name%s*=%s*'([^']+)'")
				          or patchLines[j]:match('Name%s*=%s*"([^"]+)"')
				if name then
					newMods[name] = true
					break
				end
			end
		end
	end
	return newMods
end

local function applyBadges(changed)
	if not vain then return end
	for name, tag in changed do
		local mod = vain.Modules[name]
		if mod then
			local t = tag
			mod.ExtraText = function() return t end
			-- A separate label, never RichText on the button itself -- toggling
			-- RichText on re-measures the button's leading spaces and shifts the
			-- whole name to the right. Skip on a :Lock()ed module: Lock() already
			-- calls MarkBadge with its own MAINTENANCE/WIP tag, so applying a
			-- second NEW/UPD badge here would overlap it at the same position.
			if mod.MarkBadge and not mod.Locked then
				pcall(mod.MarkBadge, mod, tag)
			end
		end
	end
end

-- Manual module badges: tag the modules listed in vain.ModuleBadges with a
-- NEW / UPD label next to their name. No GitHub auto-diff -- the list is set by
-- hand per release and shows on every inject until the next release edits it.
local function detectUpdates()
	pcall(function()
		if not vain or type(vain.ModuleBadges) ~= 'table' then return end
		local changed = {}
		for name, tag in pairs(vain.ModuleBadges) do
			if tag == 'NEW' or tag == 'UPD' then changed[name] = tag end
		end
		if not next(changed) then return end
		applyBadges(changed)
	end)
end

local function finishLoading()
	vain.Init = nil

	-- If the Vain loading screen was shown (a fresh install / update), everything
	-- is now loaded: fill + fade it out.
	local loading = getgenv and getgenv().vainLoading
	if loading and loading.isActive() then
		loading.finish()
	end

	-- Load saved settings and start the local save loop FIRST. These are fast,
	-- local-only operations, so the GUI becomes usable immediately. Wrapped in
	-- pcall so a single bad option / GUI element can't abort the rest of loading
	-- (which previously left half the modules unregistered / unshown).
	local okLoad, loadErr = pcall(function() vain:Load() end)
	if not okLoad then
		pcall(function() vain:CreateNotification('Vain', 'Settings load error (some may not apply): '..tostring(loadErr), 8, 'warning') end)
	end
	task.spawn(function()
		repeat
			vain:Save()
			task.wait(10)
		until not vain.Loaded
	end)

	-- The whitelist check, update detection, and the welcome notification each
	-- make blocking HTTP round-trips. Running them synchronously here froze the
	-- screen for seconds on inject, so defer them to a background thread; the
	-- GUI is already interactive by the time these finish.
	task.spawn(function()
		detectUpdates()
		if not shared.vainreload and vain.Categories then
			-- Name the tier this session loaded as (Free 0 < Privileged 1 < Owner
			-- 2). entity.lua resolves it from the rank Worker as soon as the local
			-- character exists, so wait for that answer rather than announcing
			-- "Free" to an Owner just because the lookup hadn't landed yet. The
			-- deadline covers executors with no request function (nothing ever
			-- resolves) and a Worker that's down -- both fall back to Free, which
			-- is what every rank check treats an unresolved lookup as anyway.
			local entitylib = vain.Libraries and vain.Libraries.entity
			local deadline = tick() + 8
			while entitylib and not entitylib.localRankResolved and tick() < deadline do
				task.wait(0.2)
			end
			local level = entitylib and entitylib.localRankLevel or 0
			local tier = entitylib and entitylib.RankNames and entitylib.RankNames[level] or 'Free'
			vain:CreateNotification(
				'Vain',
				'Welcome to Vain! Loaded as Tier '..level..' ('..tier..')',
				10
			)
		end
		if shared.dev then
			local branch = shared.dev == true and 'dev' or tostring(shared.dev)
			pcall(function()
				vain:CreateNotification(
					'Testing Mode',
					"Using test environment ('"..branch.."' branch, not production).",
					12,
					'warning'
				)
			end)
		end
	end)

	local teleportedServers
	vain:Clean(playersService.LocalPlayer.OnTeleport:Connect(function(state)
		if (not teleportedServers) and (not shared.VainIndependent) then
			teleportedServers = true
			-- shared.dev is re-passed as the loadstring call's own second argument
			-- (not a preset shared.dev = ... line) so a teleport hop carries it
			-- forward the exact same way a manual re-inject would -- init.lua
			-- treats that argument as authoritative for THIS call either way,
			-- which is also what makes shared.dev clear itself on any inject
			-- (teleport or manual) that doesn't pass it.
			local devCallArg = 'nil'
			if shared.dev then
				devCallArg = type(shared.dev) == 'string' and ('"'..shared.dev..'"') or 'true'
			end
			local teleportScript = [[
				loadstring(game:HttpGet('https://raw.githubusercontent.com/VainV6/Vain/main/init.lua', true), 'init')(nil, ]]..devCallArg..[[)
			]]
			if shared.VainDeveloper then
				teleportScript = 'shared.VainDeveloper = true\n'..teleportScript
			end
			if shared.VainCustomProfile then
				teleportScript = 'shared.VainCustomProfile = "'..shared.VainCustomProfile..'"\n'..teleportScript
			end
			queue_on_teleport(teleportScript)
		end
	end))
end

if not isfile('vain/profiles/gui.txt') then
	writefile('vain/profiles/gui.txt', 'new')
end
local gui = 'new'

if not isfolder('vain/assets/'..gui) then
	makefolder('vain/assets/'..gui)
end
local guiLoader = loadstring(downloadFile('vain/guis/'..gui..'.lua'), 'gui')
vain = guiLoader and guiLoader()
shared.vain = vain

if not shared.VainIndependent then
	-- pcall'd: a throw anywhere in universal.lua OUTSIDE its own run() blocks
	-- (top-level code between them) would otherwise abort main.lua's remaining
	-- execution too, skipping the game-specific file entirely -- the exact
	-- "most modules silently vanished" failure mode this codebase has hit
	-- before (see guis/new.lua's topbar-parenting fix).
	local universalLoader = loadstring(downloadFile('vain/games/universal.lua'), 'universal')
	if universalLoader then
		local ok, err = pcall(universalLoader)
		if not ok then warn('[Vain] universal.lua failed: ' .. tostring(err)) end
	end
	local gamePath = 'vain/games/'..game.PlaceId..'.lua'
	-- Always route through downloadFile, even when the file's already cached --
	-- a plain isfile+readfile shortcut here bypassed downloadFile's VAINEOF
	-- self-heal check entirely, so a stale truncated copy from before that check
	-- existed would keep loading forever on every inject, no matter how many
	-- fixes landed upstream.
	local hasGameFile = isfile(gamePath)
	local probedBody
	if not hasGameFile then
		-- Probe first so a 404 place (no game-specific file) is skipped quietly
		-- instead of downloadFile hard-erroring on every place without one. This
		-- must NOT be gated on shared.VainDeveloper: doing so meant a dev/test
		-- inject with a wiped cache never loaded the game modules at all (only
		-- universal), so most BedWars modules silently vanished.
		local suc, res = pcall(function()
			return game:HttpGet('https://raw.githubusercontent.com/VainV6/Vain/'..readfile('vain/profiles/commit.txt')..'/games/'..game.PlaceId..'.lua', true)
		end)
		hasGameFile = suc and res ~= '404: Not Found' and not isHttpError(res)
		-- Keep the body already fetched instead of throwing it away and having
		-- downloadFile immediately re-fetch the exact same (often 1MB+) URL --
		-- on a fresh cache this was a guaranteed double-download of the biggest
		-- file this whole chain serves. Only reuse it if it's a complete file
		-- (has the VAINEOF sentinel); otherwise fall through to downloadFile's
		-- own retry loop like before.
		if hasGameFile and res:find('VAINEOF') then
			probedBody = res
		end
	end
	if hasGameFile then
		local gameContent
		if probedBody then
			gameContent = '--This watermark is used to delete the file if its cached, remove it to make the file persist after vain updates.\n'..probedBody
			writefile(gamePath, gameContent)
		else
			gameContent = downloadFile(gamePath)
		end
		local gameLoader = loadstring(gameContent, tostring(game.PlaceId))
		if gameLoader then
			local ok, err = pcall(gameLoader)
			if not ok then warn('[Vain] '..gamePath..' failed: ' .. tostring(err)) end
		end
	end
	finishLoading()
else
	vain.Init = finishLoading
	return vain
end

--VAINEOF
