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
local store = { inventories = {} }
local getfontsize = vain.Libraries.getfontsize
-- No "Map"/"Worlds" folder exists in the lobby (that's match-only geography),
-- so this stays nil here -- the couple of exotic Kit Tracker branches that use
-- it (world-placed structures like the black market shop) are wrapped in their
-- own task.spawn, so a nil world folder there just fails that one isolated
-- async task instead of anything else.
local function getWorldFolder()
	return store.map
end
local function removeTags(str)
	str = str:gsub('<br%s*/>', '\n')
	return (str:gsub('<[^<>]->', ''))
end
local function addBlur(parent)
	local blur = Instance.new('ImageLabel')
	blur.Name = 'Blur'
	blur.Size = UDim2.new(1, 89, 1, 52)
	blur.Position = UDim2.fromOffset(-48, -31)
	blur.BackgroundTransparency = 1
	blur.Image = getcustomasset('vain/assets/new/blur.png')
	blur.ScaleType = Enum.ScaleType.Slice
	blur.SliceCenter = Rect.new(52, 31, 261, 502)
	blur.Parent = parent
	return blur
end
-- Set globally by whichever Knit-init entry point ran this session (the match
-- file's own setup does this); falls back to an empty table so remotes.Ranks
-- is just nil (rank icon fetch pcall's and no-ops) if nothing set it yet.
local remotes = getgenv().remotes or {}
local kitImageIds = {
	['none'] = "rbxassetid://16493320215",
	["random"] = "rbxassetid://79773209697352",
	["cowgirl"] = "rbxassetid://9155462968",
	["davey"] = "rbxassetid://9155464612",
	["warlock"] = "rbxassetid://15186338366",
	["ember"] = "rbxassetid://9630017904",
	["black_market_trader"] = "rbxassetid://18922642482",
	["yeti"] = "rbxassetid://9166205917",
	["scarab"] = "rbxassetid://137137517627492",
	["defender"] = "rbxassetid://131690429591874",
	["cactus"] = "rbxassetid://104436517801089",
	["oasis"] = "rbxassetid://120283205213823",
	["berserker"] = "rbxassetid://90258047545241",
	["sword_shield"] = "rbxassetid://131690429591874",
	["airbender"] = "rbxassetid://74712750354593",
	["gun_blade"] = "rbxassetid://138231219644853",
	["frost_hammer_kit"] = "rbxassetid://11838567073",
	["spider_queen"] = "rbxassetid://95237509752482",
	["archer"] = "rbxassetid://9224796984",
	["axolotl"] = "rbxassetid://9155466713",
	["baker"] = "rbxassetid://9155463919",
	["barbarian"] = "rbxassetid://9166207628",
	["builder"] = "rbxassetid://9155463708",
	["necromancer"] = "rbxassetid://11343458097",
	["cyber"] = "rbxassetid://9507126891",
	["sorcerer"] = "rbxassetid://97940108361528",
	["bigman"] = "rbxassetid://9155467211",
	["spirit_assassin"] = "rbxassetid://10406002412",
	["farmer_cletus"] = "rbxassetid://9155466936",
	["ice_queen"] = "rbxassetid://9155466204",
	["grim_reaper"] = "rbxassetid://9155467410",
	["spirit_gardener"] = "rbxassetid://132108376114488",
	["hannah"] = "rbxassetid://10726577232",
	["shielder"] = "rbxassetid://9155464114",
	["summoner"] = "rbxassetid://18922378956",
	["glacial_skater"] = "rbxassetid://84628060516931",
	["dragon_sword"] = "rbxassetid://16215630104",
	["lumen"] = "rbxassetid://9630018371",
	["flower_bee"] = "rbxassetid://101569742252812",
	["jellyfish"] = "rbxassetid://18129974852",
	["melody"] = "rbxassetid://9155464915",
	["mimic"] = "rbxassetid://14783283296",
	["miner"] = "rbxassetid://9166208461",
	["nazar"] = "rbxassetid://18926951849",
	["seahorse"] = "rbxassetid://11902552560",
	["elk_master"] = "rbxassetid://15714972287",
	["rebellion_leader"] = "rbxassetid://18926409564",
	["void_hunter"] = "rbxassetid://122370766273698",
	["taliyah"] = "rbxassetid://13989437601",
	["angel"] = "rbxassetid://9166208240",
	["harpoon"] = "rbxassetid://18250634847",
	["void_walker"] = "rbxassetid://78915127961078",
	["spirit_summoner"] = "rbxassetid://95760990786863",
	["triple_shot"] = "rbxassetid://9166208149",
	["void_knight"] = "rbxassetid://73636326782144",
	["regent"] = "rbxassetid://9166208904",
	["vulcan"] = "rbxassetid://9155465543",
	["owl"] = "rbxassetid://12509401147",
	["dasher"] = "rbxassetid://9155467645",
	["disruptor"] = "rbxassetid://11596993583",
	["wizard"] = "rbxassetid://13353923546",
	["aery"] = "rbxassetid://9155463221",
	["agni"] = "rbxassetid://17024640133",
	["alchemist"] = "rbxassetid://9155462512",
	["spearman"] = "rbxassetid://9166207341",
	["beekeeper"] = "rbxassetid://9312831285",
	["falconer"] = "rbxassetid://17022941869",
	["bounty_hunter"] = "rbxassetid://9166208649",
	["blood_assassin"] = "rbxassetid://12520290159",
	["battery"] = "rbxassetid://10159166528",
	["steam_engineer"] = "rbxassetid://15380413567",
	["vesta"] = "rbxassetid://9568930198",
	["beast"] = "rbxassetid://9155465124",
	["dino_tamer"] = "rbxassetid://9872357009",
	["drill"] = "rbxassetid://12955100280",
	["elektra"] = "rbxassetid://13841413050",
	["fisherman"] = "rbxassetid://9166208359",
	["queen_bee"] = "rbxassetid://12671498918",
	["card"] = "rbxassetid://13841410580",
	["frosty"] = "rbxassetid://9166208762",
	["gingerbread_man"] = "rbxassetid://9155464364",
	["ghost_catcher"] = "rbxassetid://9224802656",
	["tinker"] = "rbxassetid://17025762404",
	["ignis"] = "rbxassetid://13835258938",
	["oil_man"] = "rbxassetid://9166206259",
	["jade"] = "rbxassetid://9166306816",
	["dragon_slayer"] = "rbxassetid://10982192175",
	["paladin"] = "rbxassetid://11202785737",
	["pinata"] = "rbxassetid://10011261147",
	["merchant"] = "rbxassetid://9872356790",
	["metal_detector"] = "rbxassetid://9378298061",
	["slime_tamer"] = "rbxassetid://15379766168",
	["nyoka"] = "rbxassetid://17022941410",
	["midnight"] = "rbxassetid://9155462763",
	["pyro"] = "rbxassetid://9155464770",
	["raven"] = "rbxassetid://9166206554",
	["santa"] = "rbxassetid://9166206101",
	["sheep_herder"] = "rbxassetid://9155465730",
	["smoke"] = "rbxassetid://9155462247",
	["spirit_catcher"] = "rbxassetid://9166207943",
	["star_collector"] = "rbxassetid://9872356516",
	["styx"] = "rbxassetid://17014536631",
	["block_kicker"] = "rbxassetid://15382536098",
	["trapper"] = "rbxassetid://9166206875",
	["hatter"] = "rbxassetid://12509388633",
	["ninja"] = "rbxassetid://15517037848",
	["jailor"] = "rbxassetid://11664116980",
	["warrior"] = "rbxassetid://9166207008",
	["mage"] = "rbxassetid://10982191792",
	["void_dragon"] = "rbxassetid://10982192753",
	["cat"] = "rbxassetid://15350740470",
	["wind_walker"] = "rbxassetid://9872355499",
	['skeleton'] = "rbxassetid://120123419412119",
	['winter_lady'] = "rbxassetid://83274578564074",
	['soul_broker'] = 'rbxassetid://130409166262430'
}

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



pcall(function()
    local NameTags
    local Targets
    local Color
    local Background
    local DisplayName
    local Health
    local HealthColorToggle
    local HealthColorFull
    local HealthColorMid
    local HealthColorLow
    local Distance
    local Equipment
    local DrawingToggle
    local BossESP
    local ShowKits
    local KitTracker
    local Rank
    local DeviceIcon
    local GloopIndicator
    local Enchant
    local Scale
    local FontOption
    local Teammates
    local DistanceCheck
    local DistanceLimit
    local Strings, Sizes, Reference = {}, {}, {}
    local bossNametags = {}
    local Folder = Instance.new('Folder')
    Folder.Parent = vain.gui
    local methodused
    local lastUpdate = {}
    local kitCache = {}
    local equipmentCache = {}
    local enchantCache = {}
    local enchantConnections = {}
    local gloopConnections = {}
    local kitTrackerConnections = {}
    local tick = tick
    local math_floor = math.floor
    local math_round = math.round
    local math_clamp = math.clamp
    local math_huge = math.huge
    local string_format = string.format
    local vector2new = Vector2.new
    local vector3new = Vector3.new
    local color3fromHSV = Color3.fromHSV
    local color3new = Color3.new
    local udim2fromOffset = UDim2.fromOffset

    local function getHealthColor(ent)
        local ratio = math.clamp((ent.Health or 0) / (ent.MaxHealth and ent.MaxHealth > 0 and ent.MaxHealth or 1), 0, 1)
        if HealthColorToggle and HealthColorToggle.Enabled then
            local fullC = Color3.fromHSV(HealthColorFull.Hue, HealthColorFull.Sat, HealthColorFull.Value)
            local midC  = Color3.fromHSV(HealthColorMid.Hue,  HealthColorMid.Sat,  HealthColorMid.Value)
            local lowC  = Color3.fromHSV(HealthColorLow.Hue,  HealthColorLow.Sat,  HealthColorLow.Value)
            if ratio >= 0.5 then
                return fullC:Lerp(midC, (1 - ratio) / 0.5)
            else
                return midC:Lerp(lowC, (0.5 - ratio) / 0.5)
            end
        else
            return Color3.fromHSV(math.clamp(ratio / 2.5, 0, 1), 0.89, 0.75)
        end
    end

    local function getHealthColorStr(ent)
        local c = getHealthColor(ent)
        return 'rgb('..math.floor(c.R*255)..','..math.floor(c.G*255)..','..math.floor(c.B*255)..')'
    end

    local enchantImageMap = nil
    local function buildEnchantMap()
        if enchantImageMap then return enchantImageMap end
        enchantImageMap = {}
        task.spawn(function()
            if vain.ThreadFix then setthreadidentity(8) end
            local ok, meta = pcall(function()
                return require(game:GetService('ReplicatedStorage').TS.enchant['enchant-meta'])
            end)
            if not ok or not meta then return end
            for _, subMeta in pairs({meta.EnchantMeta, meta.ToolEnchantMeta, meta.ArmorEnchantMeta}) do
                if type(subMeta) == 'table' then
                    for _, v in pairs(subMeta) do
                        if type(v) == 'table' and v.statusEffect and v.image then
                            enchantImageMap[v.statusEffect] = v.image
                        end
                    end
                end
            end
        end)
        return enchantImageMap
    end

    local function getActiveEnchantImage(char)
        if not char then return '' end
        local map = buildEnchantMap()
        for attr, val in pairs(char:GetAttributes()) do
            if attr:sub(1, 13) == 'StatusEffect_' and type(val) == 'number' and val < 0 then
                local effectName = attr:sub(14)
                if not effectName:find('stacks') then
                    local img = map[effectName]
                    if img and img ~= '' then return img end
                end
            end
        end
        return ''
    end

    local function getBossDisplayName(ent)
        if not ent.NPC or not ent.Character then return nil end
        local char = ent.Character
        if char:GetAttribute("BossType") == "Bhaa" then
            return "Bhaa"
        end
        if char.Name:lower() == "bhaa" then
            return "Bhaa"
        end
        if char:FindFirstChild("BhaaModel") or char:FindFirstChild("BhaaHead") then
            return "Bhaa"
        end
        if char.Name == "Titan" then
            return "Titan"
        end
        return nil
    end

    local Added = {
        Normal = function(ent)
            if not Targets.Players.Enabled and ent.Player then return end
            local bossNames = {Titan = true, Bhaa = true}
            local isBoss = ent.NPC and ent.Character and bossNames[ent.Character.Name] == true
            local bossDisplayName = isBoss and getBossDisplayName(ent) or nil
            if isBoss then
                if not BossESP.Enabled then return end
            else
                if not Targets.NPCs.Enabled and ent.NPC then return end
                if Teammates.Enabled and (not ent.Targetable) and (not ent.Friend) then return end
            end
            if not ent.Player and ent.Character and not ent.Character:FindFirstChildOfClass('Humanoid') then return end

            if ent.Player then
                local _ntTier = getAccountTier(ent.Player)
                local _ntMyTier = getAccountTier(lplr)
                if (_ntTier >= 1 and _ntMyTier == 0) or (_ntTier >= 2 and _ntMyTier <= 1) then return end
            end
            local entityName = bossDisplayName or (ent.Player and nil) or ent.Character.Name
            Strings[ent] = ent.Player and (DisplayName.Enabled and ent.Player.DisplayName or ent.Player.Name) or entityName

            if ent.Player and getAccountTier(lplr) > 0 then
                local injData = getgenv()._aeroInjectedUsers and getgenv()._aeroInjectedUsers[ent.Player.UserId]
                if injData and getAccountTier(lplr) > injData.tier then
                    Strings[ent] = '<font color="#00FF88">[T'..tostring(injData.tier)..']</font> ' .. Strings[ent]
                end
            end

            if Health.Enabled then
                local colorStr = getHealthColorStr(ent)
                Strings[ent] = Strings[ent]..' <font color="'..colorStr..'">'..math.round(ent.Health)..'</font>'
            end

            if Distance.Enabled then
                Strings[ent] = '[%s] ' .. Strings[ent]
            end
            local textSize = 14 * Scale.Value
            local fontFace = FontOption.Value
            local size = getfontsize(removeTags(Strings[ent]), textSize, fontFace, vector2new(100000, 100000))
            local nametag = Instance.new('TextLabel')
            nametag.Name = ent.Player and ent.Player.Name or ent.Character.Name
            nametag.Size = udim2fromOffset(size.X + 8, size.Y + 7)
            nametag.AnchorPoint = vector2new(0.5, 1)
            nametag.BackgroundColor3 = color3new()
            nametag.BackgroundTransparency = Background.Value
            nametag.BorderSizePixel = 0
            nametag.Visible = false
            nametag.Text = Strings[ent]
            nametag.TextColor3 = entitylib.getEntityColor(ent) or color3fromHSV(Color.Hue, Color.Sat, Color.Value)
            nametag.RichText = true
            nametag.TextSize = textSize
            nametag.FontFace = fontFace
            nametag.Parent = Folder

            if KitTracker and KitTracker.Enabled and ent.Player then
                local vkRoman = {'I','II','III','IV','V'}
                local ktLabel = Instance.new('TextLabel')
                ktLabel.Name = 'KitTrackerLabel'
                ktLabel.BackgroundTransparency = 1
                ktLabel.TextScaled = false
                ktLabel.TextSize = 13
                ktLabel.FontFace = FontOption.Value
                ktLabel.RichText = true
                ktLabel.AnchorPoint = Vector2.new(1, 0.5)
                ktLabel.Position = UDim2.new(0, -2, 0.5, 0)
                ktLabel.Size = UDim2.new(0, 40, 1, 0)
                ktLabel.ZIndex = 2
                ktLabel.Parent = nametag

                local stroke = Instance.new('UIStroke')
                stroke.Color = Color3.new(0, 0, 0)
                stroke.Thickness = 1.5
                stroke.Parent = ktLabel

                local function updateKtLabel()
					if not KitTracker.Enabled then ktLabel.Text = '' return end
                    local playerKit = ent.Player:GetAttribute('PlayingAsKits') or 'none'
                    if playerKit == 'void_knight' then
                        local tier = ent.Player:GetAttribute('VoidKnightTier') or 0
                        if tier > 0 then
                            ktLabel.Text = '【' .. (vkRoman[tier] or tostring(tier)) .. '】'
                            ktLabel.TextColor3 = Color3.fromRGB(180, 80, 255)
                        else
                            ktLabel.Text = ''
                        end
                    elseif playerKit == 'block_kicker' then
                        local char = ent.Character
                        local count = (char and char:GetAttribute('BlockKickerKit_BlockCount')) or ent.Player:GetAttribute('BlockKickerKit_BlockCount') or 0
                        ktLabel.Text = count > 0 and '【' .. tostring(count) .. '】' or ''
                        ktLabel.TextColor3 = Color3.fromRGB(100, 210, 100)
                    elseif playerKit == 'elk_master' then
                        local char = ent.Character
                        local isMounted = char and char:FindFirstChild('elk') ~= nil
                        if isMounted then
                            ktLabel.Text = '【🦌】'
                            ktLabel.TextColor3 = Color3.fromRGB(160, 220, 80)
                        else
                            ktLabel.Text = ''
                        end
					elseif playerKit == 'summoner' then
						local tier = ent.Player:GetAttribute("Summoner_ClawLevel") or 0
						if not tier or tier == 0 then ktLabel.Text = '' return end
						ktLabel.Text = '【 ' .. (vkRoman[tier] or tostring(tier)) .. ' 】'
						ktLabel.TextColor3 = Color3.fromRGB(191, 0, 255)
					elseif playerKit == 'paladin' then
						ktLabel.Text = '【 🪽 】'
						ktLabel.TextColor3 = Color3.fromRGB(255, 242, 150)
					elseif playerKit == 'davey' then
						local tier = ent.Character and ent.Character:GetAttribute('StatusEffect_powdered_stacks') or 0
						if tier > 0 then
							ktLabel.Text = '【 ' .. tostring(tier) .. ' 】'
						else
							ktLabel.Text = ''
						end
						ktLabel.TextColor3 = Color3.fromRGB(255, 105, 130)
					elseif playerKit == 'airbender' then
						ktLabel.Text = ''
						ktLabel.TextColor3 = Color3.fromRGB(255, 200, 80)
						task.spawn(function()
							NameTags:Clean(bedwars.Client:Get("Airbender_UseTornadoFromServer"):Connect(function(p12)
								if not KitTracker.Enabled then ktLabel.Text = '' return end
								if p12.tornadoData.owner == ent.Player then
									ktLabel.Text = '【 🌪️ 】'
								end
							end))
							NameTags:Clean(bedwars.Client:Get("Airbender_EndTornadoFromServer"):Connect(function(p13)
								if not KitTracker.Enabled then ktLabel.Text = '' return end
								if p13.tornadoData.owner == ent.Player then
									ktLabel.Text = ''
								end
							end))
						end)
					elseif playerKit == 'hatter' then
						ktLabel.Text = ''
						ktLabel.TextColor3 = Color3.fromRGB(45, 15, 80)
						task.spawn(function()
							if vain.ThreadFix then setthreadidentity(8) end
							NameTags:Clean(bedwars.Client:OnEvent("HatterUseTeleport", function(p14)
								if not KitTracker.Enabled then ktLabel.Text = '' return end
								local dtc = p14.arriveTime - workspace:GetServerTimeNow() + 0.05
								if vain.ThreadFix then setthreadidentity(8) end
								if p14.hatterPlayer == ent.Player then
									ktLabel.Text = '【 🎩 】'
									task.wait(dtc)
									if vain.ThreadFix then setthreadidentity(8) end
									ktLabel.Text = ''
								else
									ktLabel.Text = ''
								end
							end))
						end)
					elseif playerKit == 'black_market_trader' then
						ktLabel.Text = ''
						ktLabel.TextColor3 = Color3.fromRGB(30, 10, 60)
						task.spawn(function()
							NameTags:Clean(bedwars.Client:Get("BlackMarketPlaceShop"):Connect(function(p15)
								if not KitTracker.Enabled then ktLabel.Text = '' return end
								if p15.shopOwnerUserId == ent.Player.UserId then
									ktLabel.Text = '【 🏪 】'
								end
							end))
							local worldFolder = getWorldFolder()
							local blocks = worldFolder:WaitForChild("Blocks", math.huge)
							NameTags:Clean(blocks.ChildAdded:Connect(function(obj)
								if obj.Name == 'black_market_shop' and obj:GetAttribute('PlacedByUserId') == ent.Player.UserId then
									local billboard = Instance.new('BillboardGui')
									billboard.Parent = obj
									billboard.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
									billboard.Size = UDim2.fromOffset(36, 36)
									billboard.AlwaysOnTop = true
									billboard.ClipsDescendants = false
									local blur = addBlur(billboard)
									blur.Visible = Background.Enabled
									local image = Instance.new('ImageLabel')
									image.Size = UDim2.fromOffset(36, 36)
									image.Position = UDim2.fromScale(0.5, 0.5)
									image.AnchorPoint = Vector2.new(0.5, 0.5)
									image.BackgroundColor3 = Color3.fromHSV(0, 0, 0)
									image.BackgroundTransparency = 0.85
									image.BorderSizePixel = 0
									image.Image = bedwars.getIcon({itemType = 'shadow_coin'}, true)
									image.Parent = billboard
									local uicorner = Instance.new('UICorner')
									uicorner.CornerRadius = UDim.new(0, 4)
									uicorner.Parent = image
									getgenv()[ent.Player.Name] = billboard
								end
							end))
						end)
					elseif playerKit == 'wizard' then
						ktLabel.TextColor3 = Color3.fromRGB(100, 70, 220)
						local function getStaffTier(v)
							local inv = store.inventories[v] and store.inventories[v].items or {}
							for _, item in inv do
								local nowstr = string.lower(item.itemType or '')
								if string.find(nowstr, 'wizard_staff') then
									return tonumber(item.itemType:sub(#item.itemType, #item.itemType)) or 1
								end
							end
						end
						local tier = getStaffTier(ent.Player)
						if not tier or tier < 0 then ktLabel.Text = '' return end
						ktLabel.Text = '【' .. (vkRoman[tier] or tostring(tier)) .. '】'
					elseif playerKit == 'aery' then
						ktLabel.TextColor3 = Color3.fromRGB(130, 210, 255)
						local stacks = ent.Player:GetAttribute('AeryStacks') or 0
						ktLabel.Text = '【' .. tostring(stacks) .. '】'
					elseif playerKit == 'mimic' then
						ktLabel.TextColor3 = Color3.fromRGB(180, 210, 60)
						ktLabel.Text = ''
						task.spawn(function()
							if vain.ThreadFix then setthreadidentity(8) end
							NameTags:Clean(bedwars.Client:OnEvent("ValidatedMimicBlock", function(p14)
								if not KitTracker.Enabled then ktLabel.Text = '' return end
								if vain.ThreadFix then setthreadidentity(8) end
								if p14.player == ent.Player then
									ktLabel.Text = '【 👔 】'
								else
									ktLabel.Text = ''
								end
							end))
							local val = workspace:FindFirstChild('DisguisedPlayerBlock_' .. ent.Player.UserId) ~= nil
							if val then ktLabel.Text = '【 👔 】' end
						end)
					elseif playerKit == 'disruptor' then
						ktLabel.Text = ''
						ktLabel.TextColor3 = Color3.fromRGB(40, 180, 140)
						task.spawn(function()
							local worldFolder = getWorldFolder()
							local blocks = worldFolder:WaitForChild("Blocks", math.huge)
							NameTags:Clean(blocks.ChildAdded:Connect(function(obj)
								if obj.Name == 'satellite_dish' and obj:GetAttribute('PlacedByUserId') == ent.Player.UserId then
									local billboard = Instance.new('BillboardGui')
									billboard.Parent = obj
									billboard.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
									billboard.Size = UDim2.fromOffset(36, 36)
									billboard.AlwaysOnTop = true
									billboard.ClipsDescendants = false
									local blur = addBlur(billboard)
									blur.Visible = Background.Enabled
									local image = Instance.new('ImageLabel')
									image.Size = UDim2.fromOffset(36, 36)
									image.Position = UDim2.fromScale(0.5, 0.5)
									image.AnchorPoint = Vector2.new(0.5, 0.5)
									image.BackgroundColor3 = Color3.fromHSV(0, 0, 0)
									image.BackgroundTransparency = 0.85
									image.BorderSizePixel = 0
									image.Image = bedwars.getIcon({itemType = 'satellite_dish'}, true)
									image.Parent = billboard
									local uicorner = Instance.new('UICorner')
									uicorner.CornerRadius = UDim.new(0, 4)
									uicorner.Parent = image
									getgenv()[ent.Player.Name] = billboard
								end
							end))
							ktLabel.Text = '【 ' .. (ent.Player:GetAttribute('DisruptorTarget') and ent.Player:GetAttribute('DisruptorTarget') .. ' Team' or 'Unknown Team') .. ' 】'
						end)
					elseif playerKit == 'winter_lady' then
						ktLabel.TextColor3 = Color3.fromRGB(200, 225, 255)
						local function getWandTier(v)
							local inv = store.inventories[v] and store.inventories[v].items or {}
							for _, item in inv do
								local nowstr = string.lower(item.itemType or '')
								if string.find(nowstr, 'frost_staff') then
									return tonumber(item.itemType:sub(#item.itemType, #item.itemType)) or 1
								end
							end
						end
						local tier = getWandTier(ent.Player)
						if not tier or tier < 0 then ktLabel.Text = '' return end
						ktLabel.Text = '【' .. (vkRoman[tier] or tostring(tier)) .. '】'
                    else
                        ktLabel.Text = ''
                    end
                end

                updateKtLabel()

                if ent.Character then
                    ent.Character.AttributeChanged:Connect(function(attr)
						if attr == 'BlockKickerKit_BlockCount' or attr == 'StatusEffect_powdered_stacks' then
							updateKtLabel()
						end
                    end)
					ent.Player.AttributeChanged:Connect(function(attr)
						if attr == 'DisruptorTarget' or attr == 'DisruptorActivation'
						or attr == 'AeryStacks' or attr == 'VoidKnightTier'
						or attr == 'PaladinStartTime' or attr == 'Summoner_ClawLevel' then
							updateKtLabel()
						end
					end)
                    ent.Character.ChildAdded:Connect(function(child)
						if child.Name == 'elk' or string.find(child.Name, "wizard_staff") or string.find(child.Name, "frost_staff") then
							updateKtLabel()
						end
					end)
					ent.Character.ChildRemoved:Connect(function(child)
						if child and (child.Name == 'elk' or string.find(child.Name, "wizard_staff") or string.find(child.Name, "frost_staff")) then
							updateKtLabel()
						end
					end)
					workspace.ChildAdded:Connect(function(child)
						if child and string.find(child.Name, "DisguisedPlayerBlock") then
							updateKtLabel()
						end
					end)
					workspace.ChildRemoved:Connect(function(child)
						if child and string.find(child.Name, "DisguisedPlayerBlock") then
							updateKtLabel()
						end
					end)
                end
                ent.Player:GetAttributeChangedSignal('PlayingAsKits'):Connect(updateKtLabel)
            end

            if Equipment.Enabled then
                for i, v in { 'Hand', 'Helmet', 'Chestplate', 'Boots' } do
                    local Icon = Instance.new('ImageLabel')
                    Icon.Name = v
                    Icon.Size = udim2fromOffset(30, 30)
                    Icon.Position = udim2fromOffset(-60 + (i * 30), -30)
                    Icon.BackgroundTransparency = 1
                    Icon.Image = ''
                    Icon.Parent = nametag
                end

                local function applyEquipmentIcons()
                    if not ent.Player then return end
                    local inventory = store.inventories[ent.Player]
                    if not inventory then return end
                    if nametag.Hand then nametag.Hand.Image = bedwars.getIcon(inventory.hand or { itemType = '' }, true) end
                    if nametag.Helmet then nametag.Helmet.Image = bedwars.getIcon(inventory.armor and inventory.armor[4] or { itemType = '' }, true) end
                    if nametag.Chestplate then nametag.Chestplate.Image = bedwars.getIcon(inventory.armor and inventory.armor[5] or { itemType = '' }, true) end
                    if nametag.Boots then nametag.Boots.Image = bedwars.getIcon(inventory.armor and inventory.armor[6] or { itemType = '' }, true) end
                end
                applyEquipmentIcons()
                if ent.Player and not store.inventories[ent.Player] then
                    task.spawn(function()
                        local attempts = 0
                        while not store.inventories[ent.Player] and NameTags.Enabled and attempts < 20 do
                            task.wait(0.5)
                            attempts += 1
                        end
                        if nametag and nametag.Parent then
                            applyEquipmentIcons()
                        end
                    end)
                end
            end

            if ShowKits.Enabled and ent.Player then
                local kitIcon = Instance.new('ImageLabel')
                kitIcon.Name = 'KitIcon'
                kitIcon.Size = udim2fromOffset(30, 30)
                kitIcon.AnchorPoint = vector2new(0.5, 0)
                kitIcon.BackgroundTransparency = 1
                kitIcon.Image = ''

                if Equipment.Enabled then
                    kitIcon.Position = udim2fromOffset(110, -30)
                else
                    kitIcon.Position = UDim2.new(0.5, 0, 0, -35)
                end

                kitIcon.Parent = nametag

                local kit = ent.Player:GetAttribute('PlayingAsKits')
                if kit then
                    local kitImage = kitImageIds[kit:lower()]
                    kitIcon.Image = kitImage or kitImageIds["none"]
                    kitCache[ent] = kitImage or kitImageIds["none"]
                else
                    kitIcon.Image = kitImageIds["none"]
                    kitCache[ent] = kitImageIds["none"]
                end
            end

            if DeviceIcon and DeviceIcon.Enabled and ent.Player then
                local function getPlayerDevice(plr)
                    local val = plr:GetAttribute('UserInputType') or 'Unknown'
                    if not val then return 'Unknown' end
                    val = val:upper()
                    if val == 'MOBILE' then return 'Mobile'
                    elseif val == 'GAMEPAD' or val == 'CONTROLLER' then return 'Controller'
                    else return 'PC' end
                end
                local deviceType = getPlayerDevice(ent.Player)
                if deviceType then
                    local deviceEmoji = {Mobile = '📱', PC = '🖥', Controller = '🎮', Unknown = '❔'}
                    local deviceLabel = Instance.new('TextLabel')
                    deviceLabel.Name = 'DeviceIcon'
                    deviceLabel.Size = udim2fromOffset(22, 22)
                    deviceLabel.Position = udim2fromOffset(size.X + 10, -1)
                    deviceLabel.BackgroundTransparency = 1
                    deviceLabel.BorderSizePixel = 0
                    deviceLabel.Text = deviceEmoji[deviceType] or ''
                    deviceLabel.RichText = false
                    deviceLabel.TextScaled = false
                    deviceLabel.TextSize = 16
                    deviceLabel.FontFace = Font.fromEnum(Enum.Font.Arial)
                    deviceLabel.TextColor3 = Color3.new(1, 1, 1)
                    deviceLabel.Parent = nametag
                end
            end

            if Rank.Enabled and ent.Player and not (getAccountTier(ent.Player) >= 1 and getAccountTier(lplr) == 0) or (getAccountTier(ent.Player) >= 2 and getAccountTier(lplr) <= 1) then
                local rankIcon = Instance.new('ImageLabel')
                rankIcon.Name = 'RankIcon'
                rankIcon.Size = udim2fromOffset(30, 30)
                rankIcon.Position = udim2fromOffset(size.X + (DeviceIcon and DeviceIcon.Enabled and 42 or 10), -4)
                rankIcon.BackgroundTransparency = 1
                rankIcon.Image = ''
                rankIcon.Parent = nametag

                task.spawn(function()
                    task.wait(math.random() * 0.5)
                    if vain.ThreadFix then setthreadidentity(8) end
                    local plr = playersService:GetPlayerFromCharacter(ent.Character)
                    if not plr then return end
                    if not rankIcon or not rankIcon.Parent then return end

                    local ok, success, data = pcall(function()
                        return bedwars.Client:Get(remotes.Ranks):CallServerAsync({ plr.UserId }):await()
                    end)

                    if vain.ThreadFix then setthreadidentity(8) end

                    if ok and success and type(data) == "table" then
                        local division = data[1] and data[1].rankDivision
                        if division and bedwars.RankMeta and bedwars.RankMeta[division] then
                            if rankIcon and rankIcon.Parent then
                                rankIcon.Image = bedwars.RankMeta[division].image
                            end
                        end
                    end
                end)
            end

            if GloopIndicator and GloopIndicator.Enabled and ent.Character and not (ent.Player and getAccountTier(ent.Player) >= 1 and getAccountTier(lplr) == 0) then
                local gloopIcon = Instance.new('ImageLabel')
                gloopIcon.Name = 'GloopIcon'
                gloopIcon.Size = udim2fromOffset(24, 24)
                gloopIcon.BackgroundTransparency = 1
                gloopIcon.Image = bedwars.getIcon({itemType = 'glue_projectile'}, true)
                gloopIcon.Visible = false
                if Rank.Enabled and DeviceIcon and DeviceIcon.Enabled then
                    gloopIcon.Position = udim2fromOffset(size.X + 74, -2)
                elseif Rank.Enabled or (DeviceIcon and DeviceIcon.Enabled) then
                    gloopIcon.Position = udim2fromOffset(size.X + 42, -2)
                else
                    gloopIcon.Position = udim2fromOffset(size.X + 10, -2)
                end
                gloopIcon.Parent = nametag
                local gloopTimer = nil
                gloopConnections[ent] = ent.Character.AttributeChanged:Connect(function(attr)
                    if attr ~= 'GlueSlow' then return end
                    local val = ent.Character:GetAttribute('GlueSlow')
                    if val ~= nil and val ~= 0 then
                        gloopIcon.Visible = true
                        if gloopTimer then task.cancel(gloopTimer) end
                        gloopTimer = task.delay(10, function()
                            gloopIcon.Visible = false
                            gloopTimer = nil
                        end)
                    end
                end)
            end

            if Enchant.Enabled and ent.Player and ent.Character and not (getAccountTier(ent.Player) >= 1 and getAccountTier(lplr) == 0) or (getAccountTier(ent.Player) >= 2 and getAccountTier(lplr) <= 1) then
                local Icon = Instance.new('ImageLabel')
                Icon.Name = 'EnchantIcon'
                Icon.Size = udim2fromOffset(30, 30)
                Icon.Position = udim2fromOffset(-30, -4)
                Icon.BackgroundTransparency = 1
                Icon.Image = getActiveEnchantImage(ent.Character)
                Icon.Parent = nametag
                enchantCache[ent] = Icon.Image
                enchantConnections[ent] = ent.Character.AttributeChanged:Connect(function(attr)
                    if attr:sub(1, 13) ~= 'StatusEffect_' then return end
                    local val = ent.Character:GetAttribute(attr)
                    if type(val) ~= 'number' then return end
                    local newImage = getActiveEnchantImage(ent.Character)
                    if enchantCache[ent] ~= newImage then
                        Icon.Image = newImage
                        enchantCache[ent] = newImage
                    end
                end)
            end

            Reference[ent] = nametag
            lastUpdate[ent] = 0
        end,

        Drawing = function(ent)
            if not Targets.Players.Enabled and ent.Player then return end
            local bossNames = {Titan = true, Bhaa = true}
            local isBoss = ent.NPC and ent.Character and bossNames[ent.Character.Name] == true
            local bossDisplayName = isBoss and getBossDisplayName(ent) or nil
            if isBoss then
                if not BossESP.Enabled then return end
            else
                if not Targets.NPCs.Enabled and ent.NPC then return end
                if Teammates.Enabled and (not ent.Targetable) and (not ent.Friend) then return end
            end
            if not ent.Player and ent.Character and not ent.Character:FindFirstChildOfClass('Humanoid') then return end

            local nametag = {}
            nametag.BG = Drawing.new('Square')
            nametag.BG.Filled = true
            nametag.BG.Transparency = 1 - Background.Value
            nametag.BG.Color = color3new()
            nametag.BG.ZIndex = 1
            nametag.Text = Drawing.new('Text')
            nametag.Text.Size = 15 * Scale.Value
            nametag.Text.Font = 0
            nametag.Text.ZIndex = 2

            if ent.Player then
                local _ntTier = getAccountTier(ent.Player)
                local _ntMyTier = getAccountTier(lplr)
                if (_ntTier >= 1 and _ntMyTier == 0) or (_ntTier >= 2 and _ntMyTier <= 1) then return end
            end
            local entityName = bossDisplayName or (ent.Player and nil) or ent.Character.Name
            Strings[ent] = ent.Player and (DisplayName.Enabled and ent.Player.DisplayName or ent.Player.Name) or entityName

            if Health.Enabled then
                local c = getHealthColor(ent)
                nametag.Text.Color = c
                Strings[ent] = Strings[ent]..' '..math.round(ent.Health)
            end

            if Distance.Enabled then
                Strings[ent] = '[%s] ' .. Strings[ent]
            end

            if ShowKits.Enabled and ent.Player then
                local kit = ent.Player:GetAttribute('PlayingAsKits')
                if kit then
                    local kitName = kit:gsub("_", " "):gsub("^%l", string.upper)
                    Strings[ent] = Strings[ent] .. ' (' .. kitName .. ')'
                end
            end

            nametag.Text.Text = Strings[ent]
            nametag.Text.Color = entitylib.getEntityColor(ent) or color3fromHSV(Color.Hue, Color.Sat, Color.Value)
            nametag.BG.Size = vector2new(nametag.Text.TextBounds.X + 8, nametag.Text.TextBounds.Y + 7)
            Reference[ent] = nametag
            lastUpdate[ent] = 0
        end
    }

    local Removed = {
        Normal = function(ent)
            local v = Reference[ent]
            if v then
                Reference[ent] = nil
                Strings[ent] = nil
                Sizes[ent] = nil
                lastUpdate[ent] = nil
                kitCache[ent] = nil
                equipmentCache[ent] = nil
                enchantCache[ent] = nil
                if enchantConnections[ent] then
                    enchantConnections[ent]:Disconnect()
                    enchantConnections[ent] = nil
                end
                if gloopConnections[ent] then
                    gloopConnections[ent]:Disconnect()
                    gloopConnections[ent] = nil
                end
                if kitTrackerConnections[ent] then
                    for _, c in ipairs(kitTrackerConnections[ent]) do
                        pcall(function() c:Disconnect() end)
                    end
                    kitTrackerConnections[ent] = nil
                end
                v:Destroy()
            end
        end,
        Drawing = function(ent)
            local v = Reference[ent]
            if v then
                Reference[ent] = nil
                Strings[ent] = nil
                Sizes[ent] = nil
                lastUpdate[ent] = nil
                kitCache[ent] = nil
                for _, obj in v do
                    pcall(function()
                        obj.Visible = false
                        obj:Remove()
                    end)
                end
            end
        end
    }

    local Updated = {
        Normal = function(ent)
            local nametag = Reference[ent]
            if not nametag then return end

            local now = tick()
            if lastUpdate[ent] and (now - lastUpdate[ent]) < 0.2 then return end
            lastUpdate[ent] = now

            Sizes[ent] = nil
            local bossNames = {Titan = true, Bhaa = true}
            local isBoss = ent.NPC and ent.Character and bossNames[ent.Character.Name] == true
            local bossDisplayName = isBoss and getBossDisplayName(ent) or nil
            local entityName = bossDisplayName or (ent.Player and nil) or ent.Character.Name
            Strings[ent] = ent.Player and (DisplayName.Enabled and ent.Player.DisplayName or ent.Player.Name) or entityName

            if ent.Player and getAccountTier(lplr) > 0 then
                local injData = getgenv()._aeroInjectedUsers and getgenv()._aeroInjectedUsers[ent.Player.UserId]
                if injData and getAccountTier(lplr) > injData.tier then
                    Strings[ent] = '<font color="#00FF88">[T'..tostring(injData.tier)..']</font> ' .. Strings[ent]
                end
            end

            if Health.Enabled then
                local colorStr = getHealthColorStr(ent)
                Strings[ent] = Strings[ent]..' <font color="'..colorStr..'">'..math.round(ent.Health)..'</font>'
            end

            if Distance.Enabled then
                Strings[ent] = '[%s] ' .. Strings[ent]
            end

            if Equipment.Enabled and ent.Player then
                local inventory = store.inventories[ent.Player] or {hand = nil, armor = {}}
                local currentEquip = {
                    tostring(inventory.hand and inventory.hand.itemType or ''),
                    tostring((inventory.armor and inventory.armor[4] and inventory.armor[4].itemType) or ''),
                    tostring((inventory.armor and inventory.armor[5] and inventory.armor[5].itemType) or ''),
                    tostring((inventory.armor and inventory.armor[6] and inventory.armor[6].itemType) or '')
                }
                local equipKey = table.concat(currentEquip, "|")
                if equipmentCache[ent] ~= equipKey then
                    equipmentCache[ent] = equipKey
                    if nametag.Hand then
                        nametag.Hand.Image = bedwars.getIcon(inventory.hand or { itemType = '' }, true)
                    end
                    if nametag.Helmet then
                        nametag.Helmet.Image = bedwars.getIcon(inventory.armor and inventory.armor[4] or { itemType = '' }, true)
                    end
                    if nametag.Chestplate then
                        nametag.Chestplate.Image = bedwars.getIcon(inventory.armor and inventory.armor[5] or { itemType = '' }, true)
                    end
                    if nametag.Boots then
                        nametag.Boots.Image = bedwars.getIcon(inventory.armor and inventory.armor[6] or { itemType = '' }, true)
                    end
                end
            end

            local size = getfontsize(removeTags(Strings[ent]), nametag.TextSize, nametag.FontFace, vector2new(100000, 100000))
            nametag.Size = udim2fromOffset(size.X + 8, size.Y + 7)
            nametag.Text = Strings[ent]
            nametag.TextColor3 = entitylib.getEntityColor(ent) or color3fromHSV(Color.Hue, Color.Sat, Color.Value)
        end,

        Drawing = function(ent)
            local nametag = Reference[ent]
            if nametag then
                if vain.ThreadFix then setthreadidentity(8) end
                Sizes[ent] = nil
                local bossNames = {Titan = true, Bhaa = true}
                local isBoss = ent.NPC and ent.Character and bossNames[ent.Character.Name] == true
                local bossDisplayName = isBoss and getBossDisplayName(ent) or nil
                local entityName = bossDisplayName or (ent.Player and nil) or ent.Character.Name
                Strings[ent] = ent.Player and (DisplayName.Enabled and ent.Player.DisplayName or ent.Player.Name) or entityName

                if Health.Enabled then
                    Strings[ent] = Strings[ent]..' '..math.round(ent.Health)
                    nametag.Text.Color = getHealthColor(ent)
                end

                if Distance.Enabled then
                    Strings[ent] = '[%s] ' .. Strings[ent]
                    nametag.Text.Text = entitylib.isAlive and string_format(Strings[ent], math_floor((entitylib.character.RootPart.Position - ent.RootPart.Position).Magnitude)) or Strings[ent]
                else
                    nametag.Text.Text = Strings[ent]
                end

                if ShowKits.Enabled and ent.Player then
                    local kit = ent.Player:GetAttribute('PlayingAsKits')
                    if kit then
                        local kitName = kit:gsub("_", " "):gsub("^%l", string.upper)
                        nametag.Text.Text = nametag.Text.Text .. ' (' .. kitName .. ')'
                    end
                end

                nametag.BG.Size = vector2new(nametag.Text.TextBounds.X + 8, nametag.Text.TextBounds.Y + 7)
                if not Health.Enabled then
                    nametag.Text.Color = entitylib.getEntityColor(ent) or color3fromHSV(Color.Hue, Color.Sat, Color.Value)
                end
            end
        end
    }

    local ColorFunc = {
        Normal = function(hue, sat, val)
            local color = color3fromHSV(hue, sat, val)
            for i, v in Reference do
                v.TextColor3 = entitylib.getEntityColor(i) or color
            end
        end,
        Drawing = function(hue, sat, val)
            local color = color3fromHSV(hue, sat, val)
            for i, v in Reference do
                if not Health.Enabled then
                    v.Text.Color = entitylib.getEntityColor(i) or color
                end
            end
        end
    }

    local frameCounter = 0
    Loop = {
        Normal = function()
            frameCounter = frameCounter + 1
            local skipPosition = frameCounter % 3 == 0
            local skipVisCheck = frameCounter % 2 ~= 0
            local updateEquipment = frameCounter % 30 == 0
            local updateKit = frameCounter % 30 == 0
            local updateDistanceText = frameCounter % 6 == 0

            for ent, nametag in Reference do
                if ent.Player and getAccountTier(ent.Player) >= 4 and getAccountTier(lplr) == 0 then
                    nametag.Visible = false
                    continue
                end
                if DistanceCheck.Enabled then
                    local distance = entitylib.isAlive and (entitylib.character.RootPart.Position - ent.RootPart.Position).Magnitude or math_huge
                    if distance < DistanceLimit.ValueMin or distance > DistanceLimit.ValueMax then
                        nametag.Visible = false
                        continue
                    end
                end

                if not skipVisCheck then
                    local headPos, headVis = gameCamera:WorldToViewportPoint(ent.RootPart.Position + vector3new(0, ent.HipHeight + 1, 0))
                    nametag.Visible = headVis
                    if headVis then
                        nametag.Position = udim2fromOffset(headPos.X, headPos.Y)
                    end
                end
                if not nametag.Visible then continue end

                if skipPosition and headPos and headPos.X then
                    nametag.Position = udim2fromOffset(headPos.X, headPos.Y)
                end

                if Distance.Enabled then
                    local mag = entitylib.isAlive and math_floor((entitylib.character.RootPart.Position - ent.RootPart.Position).Magnitude) or 0
                    if Sizes[ent] ~= mag then
                        nametag.Text = string_format(Strings[ent], mag)
                        if updateDistanceText then
                            local size = getfontsize(removeTags(nametag.Text), nametag.TextSize, nametag.FontFace, vector2new(100000, 100000))
                            nametag.Size = udim2fromOffset(size.X + 8, size.Y + 7)
                        end
                        Sizes[ent] = mag
                    end
                end

                if Equipment.Enabled and updateEquipment then
                    if ent.Player and store.inventories[ent.Player] then
                        local inventory = store.inventories[ent.Player]
                        local currentEquip = {
                            (inventory.hand and inventory.hand.itemType) or '',
                            (inventory.armor and inventory.armor[4] and inventory.armor[4].itemType) or '',
                            (inventory.armor and inventory.armor[5] and inventory.armor[5].itemType) or '',
                            (inventory.armor and inventory.armor[6] and inventory.armor[6].itemType) or ''
                        }
                        local equipKey = table.concat(currentEquip, "|")
                        if equipmentCache[ent] ~= equipKey then
                            equipmentCache[ent] = equipKey
                            if nametag.Hand then
                                nametag.Hand.Image = bedwars.getIcon(inventory.hand or { itemType = '' }, true)
                            end
                            if nametag.Helmet then
                                nametag.Helmet.Image = bedwars.getIcon(inventory.armor and inventory.armor[4] or { itemType = '' }, true)
                            end
                            if nametag.Chestplate then
                                nametag.Chestplate.Image = bedwars.getIcon(inventory.armor and inventory.armor[5] or { itemType = '' }, true)
                            end
                            if nametag.Boots then
                                nametag.Boots.Image = bedwars.getIcon(inventory.armor and inventory.armor[6] or { itemType = '' }, true)
                            end
                        end
                    end
                end

                if ShowKits.Enabled and updateKit then
                    local kitIcon = nametag:FindFirstChild('KitIcon')
                    if kitIcon and ent.Player then
                        local kit = ent.Player:GetAttribute('PlayingAsKits')
                        local suc, res = pcall(function()
                            return bedwars.BedwarsKitMeta[kit]
                        end)
                        local newKitImage = nil
                        if suc and res then
                            newKitImage = res.renderImage
                        else
                            if not suc then
                                warn(`[AEROV4 MODULE ISSUE]: [Module - NameTags (Using bedwars.BedwarsKitMeta)] [Error]: {res}`)
                            end
                            newKitImage = kitImageIds[kit] or kitImageIds['none']
                        end
                        if kitCache[ent] ~= newKitImage then
                            kitIcon.Image = newKitImage
                            kitCache[ent] = newKitImage
                        end
                    end
                end
            end
        end,

        Drawing = function()
            frameCounter = frameCounter + 1
            local skipFrame = frameCounter % 2 ~= 0

            for ent, nametag in Reference do
                if ent.Player and getAccountTier(ent.Player) >= 4 and getAccountTier(lplr) == 0 then
                    nametag.Visible = false
                    continue
                end
                if DistanceCheck.Enabled then
                    local distance = entitylib.isAlive and (entitylib.character.RootPart.Position - ent.RootPart.Position).Magnitude or math_huge
                    if distance < DistanceLimit.ValueMin or distance > DistanceLimit.ValueMax then
                        nametag.Text.Visible = false
                        nametag.BG.Visible = false
                        continue
                    end
                end

                local headPos, headVis = gameCamera:WorldToViewportPoint(ent.RootPart.Position + vector3new(0, ent.HipHeight + 1, 0))
                nametag.Text.Visible = headVis
                nametag.BG.Visible = headVis
                if not headVis then continue end
                if skipFrame then continue end

                if Health.Enabled then
                    nametag.Text.Color = getHealthColor(ent)
                end

                if Distance.Enabled then
                    local mag = entitylib.isAlive and math_floor((entitylib.character.RootPart.Position - ent.RootPart.Position).Magnitude) or 0
                    if Sizes[ent] ~= mag then
                        nametag.Text.Text = string_format(Strings[ent], mag)
                        nametag.BG.Size = vector2new(nametag.Text.TextBounds.X + 8, nametag.Text.TextBounds.Y + 7)
                        Sizes[ent] = mag
                    end
                end

                nametag.BG.Position = vector2new(headPos.X - (nametag.BG.Size.X / 2), headPos.Y - nametag.BG.Size.Y)
                nametag.Text.Position = nametag.BG.Position + vector2new(4, 3)
            end
        end
    }

    NameTags = vain.Categories.Render:CreateModule({
        Name = 'Name Tags',
        Function = function(callback)
            if callback then
                methodused = DrawingToggle.Enabled and 'Drawing' or 'Normal'
                frameCounter = 0

                if Removed[methodused] then
                    NameTags:Clean(entitylib.Events.EntityRemoved:Connect(Removed[methodused]))
                end

                if Added[methodused] then
                    for _, v in entitylib.List do
                        if Reference[v] then Removed[methodused](v) end
                        pcall(Added[methodused], v)
                    end
                    task.spawn(function()
                        task.wait(1)
                        if not NameTags.Enabled then return end
                        for _, v in entitylib.List do
                            if Reference[v] then Removed[methodused](v) end
                            pcall(Added[methodused], v)
                        end
                    end)
                    NameTags:Clean(entitylib.Events.EntityAdded:Connect(function(ent)
                        task.spawn(function()
                            task.wait(0.5)
                            if not NameTags.Enabled then return end
                            if Reference[ent] then Removed[methodused](ent) end
                            pcall(Added[methodused], ent)
                        end)
                    end))
                    NameTags:Clean(playersService.PlayerAdded:Connect(function(p)
                        NameTags:Clean(p.CharacterAdded:Connect(function()
                            task.delay(0.3, function()
                                if not NameTags.Enabled then return end
                                for _, v in entitylib.List do
                                    if v.Player == p and not Reference[v] then
                                        pcall(Added[methodused], v)
                                    end
                                end
                            end)
                        end))
                    end))
                end

                if Updated[methodused] then
                    NameTags:Clean(entitylib.Events.EntityUpdated:Connect(Updated[methodused]))
                    for _, v in entitylib.List do
                        Updated[methodused](v)
                    end
                end

                if ColorFunc[methodused] then
                    NameTags:Clean(vain.Categories.Friends.ColorUpdate.Event:Connect(function()
                        ColorFunc[methodused](Color.Hue, Color.Sat, Color.Value)
                    end))
                end

                if Loop[methodused] then
                    NameTags:Clean(runService.RenderStepped:Connect(Loop[methodused]))
                end
            else
                if Removed[methodused] then
                    for i in Reference do
                        Removed[methodused](i)
                    end
                end
                lastUpdate = {}
                kitCache = {}
                equipmentCache = {}
                enchantCache = {}
                enchantConnections = {}
            end
        end,
        Tooltip = 'Renders nametags on entities through walls.'
    })

    Targets = NameTags:CreateTargets({
        Players = true,
        Function = function()
            if NameTags.Enabled then
                NameTags:Toggle()
                NameTags:Toggle()
            end
        end
    })

    FontOption = NameTags:CreateFont({
        Name = 'Font',
        Blacklist = 'Arial',
        Function = function()
            if NameTags.Enabled then
                NameTags:Toggle()
                NameTags:Toggle()
            end
        end
    })

    Color = NameTags:CreateColorSlider({
        Name = 'Player Color',
        Function = function(hue, sat, val)
            if NameTags.Enabled and ColorFunc[methodused] then
                ColorFunc[methodused](hue, sat, val)
            end
        end
    })

    Scale = NameTags:CreateSlider({
        Name = 'Scale',
        Function = function()
            if NameTags.Enabled then
                NameTags:Toggle()
                NameTags:Toggle()
            end
        end,
        Default = 1,
        Min = 0.1,
        Max = 1.5,
        Decimal = 10
    })

    Background = NameTags:CreateSlider({
        Name = 'Transparency',
        Function = function()
            if NameTags.Enabled then
                NameTags:Toggle()
                NameTags:Toggle()
            end
        end,
        Default = 0.5,
        Min = 0,
        Max = 1,
        Decimal = 10
    })

    Health = NameTags:CreateToggle({
        Name = 'Health',
        Function = function(callback)
            HealthColorToggle.Object.Visible = callback
            HealthColorFull.Object.Visible = callback and HealthColorToggle.Enabled
            HealthColorMid.Object.Visible = callback and HealthColorToggle.Enabled
            HealthColorLow.Object.Visible = callback and HealthColorToggle.Enabled
            if NameTags.Enabled then
                NameTags:Toggle()
                NameTags:Toggle()
            end
        end
    })

    HealthColorToggle = NameTags:CreateToggle({
        Name = 'Custom Health Colors',
        Darker = true,
        Visible = false,
        Tooltip = 'Set custom colors for full, mid, and low health',
        Function = function(callback)
            HealthColorFull.Object.Visible = callback
            HealthColorMid.Object.Visible = callback
            HealthColorLow.Object.Visible = callback
            if NameTags.Enabled then
                NameTags:Toggle()
                NameTags:Toggle()
            end
        end
    })

    HealthColorFull = NameTags:CreateColorSlider({
        Name = 'Full HP Color',
        Darker = true,
        Visible = false,
        DefaultHue = 0.4,
        DefaultSat = 0.89,
        DefaultValue = 0.75,
        Function = function()
            if NameTags.Enabled then
                NameTags:Toggle()
                NameTags:Toggle()
            end
        end
    })

    HealthColorMid = NameTags:CreateColorSlider({
        Name = 'Mid HP Color',
        Darker = true,
        Visible = false,
        DefaultHue = 0.15,
        DefaultSat = 0.89,
        DefaultValue = 0.75,
        Function = function()
            if NameTags.Enabled then
                NameTags:Toggle()
                NameTags:Toggle()
            end
        end
    })

    HealthColorLow = NameTags:CreateColorSlider({
        Name = 'Low HP Color',
        Darker = true,
        Visible = false,
        DefaultHue = 0,
        DefaultSat = 0.89,
        DefaultValue = 0.75,
        Function = function()
            if NameTags.Enabled then
                NameTags:Toggle()
                NameTags:Toggle()
            end
        end
    })

    Distance = NameTags:CreateToggle({
        Name = 'Distance',
        Function = function()
            if NameTags.Enabled then
                NameTags:Toggle()
                NameTags:Toggle()
            end
        end
    })

    Equipment = NameTags:CreateToggle({
        Name = 'Equipment',
        Function = function()
            if NameTags.Enabled then
                NameTags:Toggle()
                NameTags:Toggle()
            end
        end
    })

    ShowKits = NameTags:CreateToggle({
        Name = 'Show Kits',
        Function = function()
            if NameTags.Enabled then
                NameTags:Toggle()
                NameTags:Toggle()
            end
        end,
        Tooltip = 'Shows player kits with icons in nametags'
    })

    KitTracker = NameTags:CreateToggle({
        Name = 'Kit Tracker',
        Tooltip = 'Shows kit specific stats',
        Function = function()
            if NameTags.Enabled then
                NameTags:Toggle()
                NameTags:Toggle()
            end
        end
    })

    Rank = NameTags:CreateToggle({
        Name = 'Rank',
        Tooltip = 'Displays player\'s rank icon',
        Function = function()
            if NameTags.Enabled then
                NameTags:Toggle()
                NameTags:Toggle()
            end
        end
    })

    DeviceIcon = NameTags:CreateToggle({
        Name = 'Device Icon',
        Tooltip = 'Shows device type (Mobile, PC, Controller) next to rank',
        Function = function()
            if NameTags.Enabled then
                NameTags:Toggle()
                NameTags:Toggle()
            end
        end
    })

    GloopIndicator = NameTags:CreateToggle({
        Name = 'Gloop',
        Default = true,
        Tooltip = 'Shows a gloop icon on nametags when a player is glooped',
        Function = function()
            if NameTags.Enabled then
                NameTags:Toggle()
                NameTags:Toggle()
            end
        end
    })

    Enchant = NameTags:CreateToggle({
        Name = 'Enchant',
        Tooltip = 'Displays active weapon enchant icon',
        Default = true,
        Function = function()
            if NameTags.Enabled then
                NameTags:Toggle()
                NameTags:Toggle()
            end
        end
    })

    DisplayName = NameTags:CreateToggle({
        Name = 'Use Displayname',
        Function = function()
            if NameTags.Enabled then
                NameTags:Toggle()
                NameTags:Toggle()
            end
        end,
        Default = true
    })

    Teammates = NameTags:CreateToggle({
        Name = 'Priority Only',
        Function = function()
            if NameTags.Enabled then
                NameTags:Toggle()
                NameTags:Toggle()
            end
        end,
        Default = true
    })

    DrawingToggle = NameTags:CreateToggle({
        Name = 'Drawing',
        Function = function()
            if NameTags.Enabled then
                NameTags:Toggle()
                NameTags:Toggle()
            end
        end,
    })

    BossESP = NameTags:CreateToggle({
        Name = 'Boss ESP',
        Tooltip = 'Shows nametags for Titan and Bhaa bosses',
        Function = function()
            if NameTags.Enabled then
                NameTags:Toggle()
                NameTags:Toggle()
            end
        end
    })

    DistanceCheck = NameTags:CreateToggle({
        Name = 'Distance Check',
        Function = function(callback)
            DistanceLimit.Object.Visible = callback
        end
    })

    DistanceLimit = NameTags:CreateTwoSlider({
        Name = 'Player Distance',
        Min = 0,
        Max = 256,
        DefaultMin = 0,
        DefaultMax = 64,
        Darker = true,
        Visible = false
    })

    task.defer(function()
        if DistanceLimit and DistanceLimit.Object then
            DistanceLimit.Object.Visible = false
        end
        if HealthColorToggle and HealthColorToggle.Object then
            HealthColorToggle.Object.Visible = false
        end
        if HealthColorFull and HealthColorFull.Object then
            HealthColorFull.Object.Visible = false
        end
        if HealthColorMid and HealthColorMid.Object then
            HealthColorMid.Object.Visible = false
        end
        if HealthColorLow and HealthColorLow.Object then
            HealthColorLow.Object.Visible = false
        end
    end)
end)

shared.bedwars = bedwars
shared.GlobalBedwars = bedwars
shared.VapeBWLoaded = true
--VAINEOF
