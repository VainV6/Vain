local run = function(func) func() end
local cloneref = cloneref or function(obj) return obj end

local playersService = cloneref(game:GetService('Players'))
local replicatedStorage = cloneref(game:GetService('ReplicatedStorage'))
local inputService = cloneref(game:GetService('UserInputService'))
local runService = cloneref(game:GetService('RunService'))

local lplr = playersService.LocalPlayer
local vain = shared.vain
local entitylib = vain.Libraries.entity
local sessioninfo = vain.Libraries.sessioninfo
local color = vain.Libraries.color
local uipallet = vain.Libraries.uipallet
local getcustomasset = vain.Libraries.getcustomasset
local bedwars = {}
local gameCamera = workspace.CurrentCamera

local function notif(...)
	return vain:CreateNotification(...)
end

local function getAccountTier(player)
	if getgenv().getAccountTier then
		return getgenv().getAccountTier(player)
	end
	return 0
end

local function isEnemy(ent)
	if not ent then return false end
	if ent.Targetable ~= nil then return ent.Targetable end
	local ok, res = pcall(entitylib.targetCheck, ent)
	return ok and res or false
end

run(function()
	local function dumpRemote(tab)
		local ind = table.find(tab, 'Client')
		return ind and tab[ind + 1] or ''
	end

	local KnitInit, Knit
	repeat
		KnitInit, Knit = pcall(function() return debug.getupvalue(require(lplr.PlayerScripts.TS.knit).setup, 9) end)
		if KnitInit then break end
		task.wait()
	until KnitInit
	if not debug.getupvalue(Knit.Start, 1) then
		repeat task.wait() until debug.getupvalue(Knit.Start, 1)
	end
	local Flamework = require(replicatedStorage['rbxts_include']['node_modules']['@flamework'].core.out).Flamework
	local Client = require(replicatedStorage.TS.remotes).default.Client

	bedwars = setmetatable({
		Client = Client,
		CrateItemMeta = debug.getupvalue(Flamework.resolveDependency('client/controllers/global/reward-crate/crate-controller@CrateController').onStart, 3),
		Store = require(lplr.PlayerScripts.TS.ui.store).ClientStore
	}, {
		__index = function(self, ind)
			rawset(self, ind, Knit.Controllers[ind])
			return rawget(self, ind)
		end
	})

	local kills = sessioninfo:AddItem('Kills')
	local beds = sessioninfo:AddItem('Beds')
	local wins = sessioninfo:AddItem('Wins')
	local games = sessioninfo:AddItem('Games')

	vain:Clean(function()
		table.clear(bedwars)
	end)
end)

for _, v in vain.Modules do
	if v.Category == 'Combat' or v.Category == 'Minigames' then
		vain:Remove(i)
	end
end

for _, dupeName in {'Anti Fall'} do
	if vain.Modules[dupeName] then
		vain:Remove(dupeName)
	end
end

run(function()
	local Sprint
	local old
	
	Sprint = vain.Categories.Combat:CreateModule({
		Name = 'Sprint',
		Function = function(callback)
			if callback then
				if inputService.TouchEnabled then pcall(function() lplr.PlayerGui.MobileUI['2'].Visible = false end) end
				old = bedwars.SprintController.stopSprinting
				bedwars.SprintController.stopSprinting = function(...)
					local call = old(...)
					bedwars.SprintController:startSprinting()
					return call
				end
				Sprint:Clean(entitylib.Events.LocalAdded:Connect(function() bedwars.SprintController:stopSprinting() end))
				bedwars.SprintController:stopSprinting()
			else
				if inputService.TouchEnabled then pcall(function() lplr.PlayerGui.MobileUI['2'].Visible = true end) end
				bedwars.SprintController.stopSprinting = old
				bedwars.SprintController:stopSprinting()
			end
		end,
		Tooltip = 'Sets your sprinting to true.'
	})
end)
	
run(function()
	local AutoGamble
	
	AutoGamble = vain.Categories.Minigames:CreateModule({
		Name = 'AutoGamble',
		Function = function(callback)
			if callback then
				AutoGamble:Clean(bedwars.Client:GetNamespace('RewardCrate'):Get('CrateOpened'):Connect(function(data)
					if data.openingPlayer == lplr then
						local tab = bedwars.CrateItemMeta[data.reward.itemType] or {displayName = data.reward.itemType or 'unknown'}
						notif('AutoGamble', 'Won '..tab.displayName, 5)
					end
				end))
	
				repeat
					if not bedwars.CrateAltarController.activeCrates[1] then
						for _, v in bedwars.Store:getState().Consumable.inventory do
							if v.consumable:find('crate') then
								bedwars.CrateAltarController:pickCrate(v.consumable, 1)
								task.wait(1.2)
								if bedwars.CrateAltarController.activeCrates[1] and bedwars.CrateAltarController.activeCrates[1][2] then
									bedwars.Client:GetNamespace('RewardCrate'):Get('OpenRewardCrate'):SendToServer({
										crateId = bedwars.CrateAltarController.activeCrates[1][2].attributes.crateId
									})
								end
								break
							end
						end
					end
					task.wait(1)
				until not AutoGamble.Enabled
			end
		end,
		Tooltip = 'Automatically opens lucky crates, piston inspired!'
	})
end)

run(function()
	local KeybindFix
	local oldRegister
	local oldSend
	local remoteObj

	-- BedWars' own settings menu registers keybinds with whatever it changed,
	-- not the full set -- anything it omits gets treated as unset and silently
	-- falls back to default, wiping every other custom bind. Backfill any
	-- missing action from the currently-registered keybinds (the state right
	-- before this call takes effect) so nothing not being written this call
	-- can ever be lost.
	local function keyName(k)
		if k == nil then return nil end
		return typeof(k) == 'EnumItem' and k.Name or tostring(k)
	end

	local function fillMissingActions(target)
		if not target then return end
		local ok, current = pcall(function() return bedwars.KeybindLoadController:getKeybinds() end)
		local currentKb = ok and current and current.keyboard
		if not currentKb then return end

		for _, group in { 'controlActions', 'abilityActions' } do
			target[group] = target[group] or {}
			for action, key in (currentKb[group] or {}) do
				if target[group][action] == nil then
					target[group][action] = key
				end
			end
		end

		-- BedWars also silently resets EVERY key back to default if two actions
		-- end up sharing the same key -- assigning a key that's already used
		-- elsewhere would otherwise let that happen. Find whichever action(s)
		-- actually changed this call (their key differs from a moment ago) and
		-- locally unbind any OTHER action still holding that same key, so the
		-- payload we forward can never contain a duplicate.
		local changed = {}
		for _, group in { 'controlActions', 'abilityActions' } do
			for action, key in target[group] do
				local prevKey = currentKb[group] and currentKb[group][action]
				local kn = keyName(key)
				if kn ~= nil and kn ~= keyName(prevKey) then
					changed[kn] = { group = group, action = action }
				end
			end
		end
		for kn, winner in changed do
			for _, group in { 'controlActions', 'abilityActions' } do
				for action, key in target[group] do
					if not (group == winner.group and action == winner.action) and keyName(key) == kn then
						target[group][action] = nil
					end
				end
			end
		end
	end

	KeybindFix = vain.Categories.Utility:CreateModule({
		Name = 'Keybind fix',
		Tooltip = "Prevent keybind reset",
		Function = function(callback)
			if callback then
				local klc = bedwars.KeybindLoadController
				if klc and not oldRegister then
					oldRegister = klc.registerKeybinds
					klc.registerKeybinds = function(self, data, ...)
						pcall(fillMissingActions, data and data.keyboard)
						return oldRegister(self, data, ...)
					end
				end
				local ok, remote = pcall(function() return bedwars.Client:Get('UpdateProfileDataKeybinds') end)
				if ok and remote and not oldSend then
					remoteObj = remote
					oldSend = remote.SendToServer
					remote.SendToServer = function(self, payload, ...)
						pcall(fillMissingActions, payload and payload.keyboardKeybindDefinition)
						return oldSend(self, payload, ...)
					end
				end
			else
				if bedwars.KeybindLoadController and oldRegister then
					bedwars.KeybindLoadController.registerKeybinds = oldRegister
				end
				oldRegister = nil
				if remoteObj and oldSend then
					remoteObj.SendToServer = oldSend
				end
				oldSend = nil
				remoteObj = nil
			end
		end,
	})
	-- CreateModule has no concept of a module-level "Default" (that's an
	-- option-level thing) -- the old `Default = true` field silently did
	-- nothing and the hooks above never actually installed unless the player
	-- happened to click this on manually. bedwars is fully populated by this
	-- point in the file, so it's safe to enable immediately.
	KeybindFix:Toggle()
end)


shared.bedwars = bedwars
shared.GlobalBedwars = bedwars
shared.VapeBWLoaded = true
--VAINEOF
