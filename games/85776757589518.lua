-- Dungeon Quest (universe 9931749389) — Vain modules.
-- Remotes verified from the place dump: ReplicatedStorage.remotes.*
-- Combat: weapon Accessory RemoteEvent + weaponUsed; abilities via abilityUsed(slot, child).

local run = function(func)
	local ok, err = pcall(func)
	if not ok then
		local vain = shared.vain
		if vain and vain.CreateNotification then
			vain:CreateNotification('Vain DQ', 'Module failed to load: ' .. tostring(err), 5, 'alert')
		end
	end
end

local cloneref = cloneref or function(o) return o end
local playersService = cloneref(game:GetService('Players'))
local replicatedStorage = cloneref(game:GetService('ReplicatedStorage'))
local lplr = playersService.LocalPlayer
local vain = shared.vain

-- Guarded remote lookup so a missing/renamed remote can never error a module.
local remotesFolder = replicatedStorage:FindFirstChild('remotes')
if not remotesFolder then
	pcall(function() remotesFolder = replicatedStorage:WaitForChild('remotes', 10) end)
end
local function remote(name)
	return remotesFolder and remotesFolder:FindFirstChild(name)
end

-- True only while actually inside a dungeon (not town/lobby, not mid-cast).
local function inCombat()
	local char = lplr.Character
	local peaceful = lplr:FindFirstChild('peaceful')
	if not (char and peaceful and peaceful.Value == false) then return false, char end
	local busy = char:FindFirstChild('busyCasting')
	if busy and busy.Value ~= false then return false, char end
	return true, char
end

-- Shared enemy targeting: nearest live mob under an 'enemyFolder' (cached), plus a
-- helper to turn the character to face it. DQ weapon swings and abilities fire in
-- the character's LOOK direction, so facing the enemy is what makes them connect.
local _enemyParts, _enemyScan = {}, 0
local function scanEnemyParts()
	_enemyParts = {}
	pcall(function()
		for _, d in workspace:GetDescendants() do
			if d:IsA('Humanoid') and d.Health > 0 then
				local m = d.Parent
				if m and m:IsA('Model') and not playersService:GetPlayerFromCharacter(m) and m:FindFirstAncestor('enemyFolder') then
					local part = m.PrimaryPart or m:FindFirstChild('HumanoidRootPart') or m:FindFirstChildWhichIsA('BasePart')
					if part then table.insert(_enemyParts, part) end
				end
			end
		end
	end)
	_enemyScan = os.clock()
end
local function nearestEnemyPart(pos)
	if os.clock() - _enemyScan > 1 or #_enemyParts == 0 then scanEnemyParts() end
	local best, bestDist
	for i = #_enemyParts, 1, -1 do
		local part = _enemyParts[i]
		if not (part and part.Parent) then
			table.remove(_enemyParts, i)
		else
			local dist = (part.Position - pos).Magnitude
			if not bestDist or dist < bestDist then best, bestDist = part, dist end
		end
	end
	return best
end
-- rotate the character to face the nearest enemy (horizontal), staying in place.
local function faceNearest()
	local char = lplr.Character
	local hrp = char and char:FindFirstChild('HumanoidRootPart')
	if not hrp then return end
	local part = nearestEnemyPart(hrp.Position)
	if part and (part.Position - hrp.Position).Magnitude > 0.5 then
		-- horizontal only: a Humanoid is force-kept upright, so PITCHING the RootPart
		-- just makes it fight our CFrame every frame (the Y-axis jitter). Keep it level.
		hrp.CFrame = CFrame.lookAt(hrp.Position, Vector3.new(part.Position.X, hrp.Position.Y, part.Position.Z))
	end
end

-- A simple toggle that fires a no-arg remote on a loop (server ignores it when
-- the action isn't valid, so this is safe to leave running).
local function looper(category, name, tooltip, remoteName, interval, gate)
	run(function()
		local Module
		Module = category:CreateModule({
			Name = name,
			Tooltip = tooltip,
			Function = function(callback)
				if not callback then return end
				repeat
					pcall(function()
						if gate and not gate() then return end
						local r = remote(remoteName)
						if r then r:FireServer() end
					end)
					task.wait(interval)
				until not Module.Enabled
			end,
		})
	end)
end

-- ── Auto Attack ──────────────────────────────────────────────────────────────
run(function()
	local AutoAttack, AttackDelay
	AutoAttack = vain.Categories.Blatant:CreateModule({
		Name = 'Auto Attack',
		Tooltip = 'Automatically swings your equipped weapon while in a dungeon.',
		Function = function(callback)
			if not callback then return end
			local weaponUsed = remote('weaponUsed')
			repeat
				pcall(function()
					local ok, char = inCombat()
					if not ok then return end
					faceNearest() -- point at the enemy so the swing lands
					local weapon
					for _, c in char:GetChildren() do
						if c:IsA('Accessory') and c:FindFirstChild('Weapon') then weapon = c break end
					end
					if not weapon then return end
					local rem = weapon:FindFirstChildOfClass('RemoteEvent')
					if rem then rem:FireServer() end
					if weaponUsed then weaponUsed:FireServer() end
				end)
				task.wait(AttackDelay.Value)
			until not AutoAttack.Enabled
		end,
	})
	AttackDelay = AutoAttack:CreateSlider({
		Name = 'Attack Delay', Min = 0, Max = 1, Default = 0.12, Decimal = 100, Suffix = 's',
		Tooltip = 'Delay between swings. Lower is faster; too low may be throttled server-side.',
	})
end)

-- ── Auto Skill ───────────────────────────────────────────────────────────────
run(function()
	local AutoSkill
	AutoSkill = vain.Categories.Blatant:CreateModule({
		Name = 'Auto Skill',
		Tooltip = 'Casts your Q and E abilities the instant they come off cooldown.',
		Function = function(callback)
			if not callback then return end
			local abilityUsed = remote('abilityUsed')
			repeat
				pcall(function()
					local ok = inCombat()
					if not (ok and abilityUsed) then return end
					faceNearest() -- point at the enemy so directional abilities go the right way
					for _, slot in { 'q', 'e' } do
						for _, child in lplr.Backpack:GetChildren() do
							if child:FindFirstChild('abilitySlot') and child.abilitySlot.Value == slot then
								local cd = child:FindFirstChild('cooldown')
								if not (cd and cd.Value > 0) then -- not on cooldown
									local le = child:FindFirstChild('localEvent')
									if le then le:Fire() end
									abilityUsed:FireServer(slot, child)
								end
								break
							end
						end
					end
				end)
				task.wait(0.1)
			until not AutoSkill.Enabled
		end,
	})
end)

-- ── Dungeon flow (no-arg remotes) ────────────────────────────────────────────
-- Auto Start only fires from the lobby/town (peaceful == true); the rest are safe
-- to fire on a loop since the server ignores them when they don't apply.
local inLobby = function()
	local p = lplr:FindFirstChild('peaceful')
	return p and p.Value == true
end
-- Auto Start Dungeon / Auto Ready Up / Auto Boss Raid are lobby actions -> they
-- live in the lobby file (games/77649408247578.lua). Auto Return to Lobby stays
-- here since it fires from the in-dungeon results screen.
looper(vain.Categories.Utility, 'Auto Return to Lobby',
	'Returns to the lobby automatically when a dungeon ends.', 'ReturnToLobbyEvent', 1)

-- ── Auto Replay ──────────────────────────────────────────────────────────────
-- The replay call needs the game's own config table, so instead of guessing it we
-- click the real Replay button the results screen shows — the game then fires
-- replayDungeon with the correct payload (re-equips gear, advances tier, etc.).
run(function()
	local AutoReplay

	-- The dungeon is "over" when the results screen is up — which happens BOTH on a
	-- boss kill and on a hardcore wipe — or when the boss room's dungeonFinished flag
	-- is set. Gate on that so it never replays mid-run.
	local function dungeonOver()
		local pg = lplr:FindFirstChild('PlayerGui')
		local holder = pg and pg:FindFirstChild('rewardGuiHolder')
		if holder and #holder:GetChildren() > 0 then return true end
		local df = workspace:FindFirstChild('dungeonFinished', true)
		if df and df:IsA('BoolValue') and df.Value == true then return true end
		return false
	end

	AutoReplay = vain.Categories.Blatant:CreateModule({
		Name = 'Auto Replay',
		Tooltip = 'Once the dungeon is over (final boss defeated, or the party wiped in hardcore), clicks the real Replay button so the game handles gear/tier correctly.',
		Function = function(callback)
			if not callback then return end
			repeat
				pcall(function()
					if not (firesignal and dungeonOver()) then return end
					local pg = lplr:FindFirstChild('PlayerGui')
					local btn = pg and pg:FindFirstChild('ReplayDungeonButton', true)
					if btn and not btn:IsA('GuiButton') then btn = btn:FindFirstChildWhichIsA('GuiButton', true) end
					if btn and btn:IsA('GuiButton') then firesignal(btn.MouseButton1Click) end
				end)
				task.wait(0.6)
			until not AutoReplay.Enabled
		end,
	})
end)

-- ── Auto Farm (full dungeon clear) ───────────────────────────────────────────
-- Finds the nearest live enemy, positions ABOVE it (so ground melee whiffs),
-- and bursts it with weapon swing + both abilities. Safety: if HP drops below the
-- threshold it floats high out of reach and waits to recover, so it never dies.
-- When a room is clear it walks forward to trigger the next one.
run(function()
	local AutoFarm, SafeHP, RecoverHP, HoverHeight, EnemyOffset, FarmDelay, UseTeleport, HealSwap

	-- storage items may store a field as a plain value or as {Value=x}.
	local function fv(item, key)
		local v = item[key]
		if type(v) == 'table' and v.Value ~= nil then v = v.Value end
		return v
	end

	local function equippedWeapon(char)
		for _, c in char:GetChildren() do
			if c:IsA('Accessory') and c:FindFirstChild('Weapon') then return c end
		end
	end
	local function swing(char, weaponUsed)
		local w = equippedWeapon(char)
		if not w then return end
		local rem = w:FindFirstChildOfClass('RemoteEvent')
		if rem then rem:FireServer() end
		if weaponUsed then weaponUsed:FireServer() end
	end
	local function castAbilities(abilityUsed)
		for _, slot in { 'q', 'e' } do
			for _, child in lplr.Backpack:GetChildren() do
				if child:FindFirstChild('abilitySlot') and child.abilitySlot.Value == slot then
					local cd = child:FindFirstChild('cooldown')
					if not (cd and cd.Value > 0) then
						local le = child:FindFirstChild('localEvent')
						if le then le:Fire() end
						if abilityUsed then abilityUsed:FireServer(slot, child) end
					end
					break
				end
			end
		end
	end

	-- cached list of enemy models (non-player Humanoids), refreshed periodically.
	local enemyCache, lastScan = {}, 0
	local function enemyPart(m)
		return m.PrimaryPart or m:FindFirstChild('HumanoidRootPart') or m:FindFirstChild('Torso')
			or m:FindFirstChild('UpperTorso') or m:FindFirstChildWhichIsA('BasePart')
	end
	local function rescan()
		enemyCache = {}
		pcall(function()
			for _, d in workspace:GetDescendants() do
				if d:IsA('Humanoid') and d.Health > 0 then
					local m = d.Parent
					-- only real dungeon mobs: a Model living under an 'enemyFolder'
					-- (NOT town NPCs, players, pets or decorations).
					if m and m:IsA('Model') and enemyPart(m)
						and not playersService:GetPlayerFromCharacter(m)
						and m:FindFirstAncestor('enemyFolder') then
						table.insert(enemyCache, m)
					end
				end
			end
		end)
		lastScan = os.clock()
	end
	local function nearestEnemy(pos)
		if os.clock() - lastScan > 1.5 or #enemyCache == 0 then rescan() end
		local best, bestPart, bestDist
		for i = #enemyCache, 1, -1 do
			local m = enemyCache[i]
			local hum = m and m.Parent and m:FindFirstChildOfClass('Humanoid')
			local part = m and enemyPart(m)
			if not (m and m.Parent and hum and hum.Health > 0 and part) then
				table.remove(enemyCache, i)
			else
				local dist = (part.Position - pos).Magnitude
				if not bestDist or dist < bestDist then best, bestPart, bestDist = m, part, dist end
			end
		end
		return best, bestPart
	end

	-- Heal-swap: when HP is low, if the inventory has heal spell(s), save the current
	-- loadout, switch to the best spell-power (mage) weapon + 1-2 heal spells, cast them
	-- to full HP while floating safe, then restore the original loadout. Returns false
	-- (so the caller falls back to float-and-regen) if there's no heal spell.
	local function healSwap()
		local getStorage, equip, abilityUsed = remote('reloadInvy'), remote('equipItem'), remote('abilityUsed')
		if not (getStorage and equip and abilityUsed) then return false end
		local storage = getStorage:InvokeServer()
		if type(storage) ~= 'table' or type(storage.abilities) ~= 'table' then return false end

		-- heal spells in inventory (detected by name, e.g. "Chain Heal" / "Universal Heal")
		local heals = {}
		for id, item in pairs(storage.abilities) do
			if tostring(fv(item, 'name') or ''):lower():find('heal') then
				table.insert(heals, tostring(id):sub(9))
			end
		end
		if #heals == 0 then return false end

		-- remember the current loadout (weapon + q/e abilities), whatever set it is
		local savedWeapon, savedQ, savedE
		if type(storage.weapons) == 'table' then
			for id, item in pairs(storage.weapons) do
				if item.equipped == true then savedWeapon = tostring(id):sub(8) break end
			end
		end
		for id, item in pairs(storage.abilities) do
			local eq = item.equipped
			if type(eq) == 'table' then
				if eq.q then savedQ = tostring(id):sub(9) end
				if eq.e then savedE = tostring(id):sub(9) end
			end
		end

		-- switch to the best spell-power weapon + the heal spell(s)
		local bestW, bestSP
		if type(storage.weapons) == 'table' then
			for id, item in pairs(storage.weapons) do
				local sp = tonumber(fv(item, 'spellPower')) or 0
				if not bestSP or sp > bestSP then bestW, bestSP = tostring(id):sub(8), sp end
			end
		end
		if bestW then pcall(function() equip:InvokeServer('weapon', bestW) end) end
		pcall(function() equip:InvokeServer('ability', heals[1], 'q') end)
		if #heals >= 2 then pcall(function() equip:InvokeServer('ability', heals[2], 'e') end) end
		task.wait(0.4)

		-- cast the heals until full HP (staying floated out of reach)
		local t0 = os.clock()
		while AutoFarm.Enabled and os.clock() - t0 < 12 do
			local char = lplr.Character
			local hum = char and char:FindFirstChildOfClass('Humanoid')
			local hrp = char and char:FindFirstChild('HumanoidRootPart')
			if not (hum and hrp) then break end
			if hum.MaxHealth > 0 and hum.Health / hum.MaxHealth >= 0.98 then break end
			hrp.CFrame = CFrame.new(hrp.Position.X, hrp.Position.Y + HoverHeight.Value, hrp.Position.Z)
			for _, slot in { 'q', 'e' } do
				for _, child in lplr.Backpack:GetChildren() do
					if child:FindFirstChild('abilitySlot') and child.abilitySlot.Value == slot then
						local cd = child:FindFirstChild('cooldown')
						if not (cd and cd.Value > 0) then
							local le = child:FindFirstChild('localEvent'); if le then le:Fire() end
							pcall(function() abilityUsed:FireServer(slot, child) end)
						end
						break
					end
				end
			end
			task.wait(0.2)
		end

		-- restore the original loadout (mage or warrior — whatever it was)
		if savedWeapon then pcall(function() equip:InvokeServer('weapon', savedWeapon) end) end
		if savedQ then pcall(function() equip:InvokeServer('ability', savedQ, 'q') end) end
		if savedE then pcall(function() equip:InvokeServer('ability', savedE, 'e') end) end
		return true
	end

	AutoFarm = vain.Categories.Blatant:CreateModule({
		Name = 'Auto Farm',
		Tooltip = 'Clears the whole dungeon automatically: kills every enemy with your weapon + Q/E, and floats to safety to recover HP so you never die. Teleports onto enemies (may trip anti-cheat on some servers).',
		Function = function(callback)
			if not callback then return end
			local weaponUsed = remote('weaponUsed')
			local abilityUsed = remote('abilityUsed')
			local retreating = false
			repeat
				pcall(function()
					local char = lplr.Character
					local hrp = char and char:FindFirstChild('HumanoidRootPart')
					local hum = char and char:FindFirstChildOfClass('Humanoid')
					if not (char and hrp and hum) then return end
					local peaceful = lplr:FindFirstChild('peaceful')
					if peaceful and peaceful.Value == true then return end -- in town/lobby, nothing to farm

					-- safety: drop into retreat below SafeHP, resume once RecoverHP reached
					local hpFrac = hum.MaxHealth > 0 and hum.Health / hum.MaxHealth or 1
					if hpFrac <= SafeHP.Value / 100 then retreating = true end
					if retreating then
						hum.PlatformStand = true
						hrp.Anchored = false
						hrp.CFrame = CFrame.new(hrp.Position.X, hrp.Position.Y + HoverHeight.Value, hrp.Position.Z)
						hrp.AssemblyLinearVelocity = Vector3.zero
						-- heal-swap first (heals to full + restores loadout); if it can't
						-- (no heal spell owned) fall back to waiting for natural regen.
						if HealSwap.Enabled and healSwap() then
							retreating = false
							hum.PlatformStand = false
							hrp.Anchored = false
							return
						end
						if hpFrac >= math.min(RecoverHP.Value / 100, 0.98) then
							retreating = false
							hum.PlatformStand = false
							hrp.Anchored = false
						end
						return
					end

					local target, part = nearestEnemy(hrp.Position)
					if target and part then
						local busy = char:FindFirstChild('busyCasting')
						if UseTeleport.Enabled then
							-- hover beside the enemy and FACE it in full 3D (pitch on X AND Y so
							-- swing + abilities travel INTO it, not over its head).
							local ep = part.Position
							local dir = (hrp.Position - ep) * Vector3.new(1, 0, 1)
							dir = dir.Magnitude > 0.1 and dir.Unit or Vector3.new(0, 0, 1)
							local myPos = ep + dir * 4 + Vector3.new(0, EnemyOffset.Value, 0)
							hrp.Anchored = false
							-- PlatformStand disables the Humanoid's auto-upright, so the pitched
							-- look-at HOLDS instead of snapping back every frame (that snap-back
							-- was the "Y axis is buggy" jitter). It is NOT anchoring, so the game
							-- still sees us as a live target and combat works both ways.
							hum.PlatformStand = true
							hrp.CFrame = CFrame.lookAt(myPos, ep)
							hrp.AssemblyLinearVelocity = Vector3.zero
						else
							hrp.Anchored = false
							hum.PlatformStand = false
							hum:Move((part.Position - hrp.Position) * Vector3.new(1, 0, 1))
							faceNearest()
						end
						if not (busy and busy.Value ~= false) then
							swing(char, weaponUsed)
							castAbilities(abilityUsed)
						end
					else
						-- room clear: unanchor and nudge forward to trigger the next room
						hrp.Anchored = false
						hum.PlatformStand = false
						hum:Move(hrp.CFrame.LookVector * Vector3.new(1, 0, 1))
					end
				end)
				task.wait(FarmDelay.Value)
			until not AutoFarm.Enabled
			pcall(function()
				local ch = lplr.Character
				local hum = ch and ch:FindFirstChildOfClass('Humanoid')
				local hrp = ch and ch:FindFirstChild('HumanoidRootPart')
				if hum then hum.PlatformStand = false end
				if hrp then hrp.Anchored = false end -- never leave the character stuck anchored
			end)
		end,
	})
	SafeHP = AutoFarm:CreateSlider({ Name = 'Retreat below HP', Min = 5, Max = 90, Default = 55, Suffix = '%',
		Tooltip = 'Anchor high out of reach and stop fighting when your HP drops below this. Raise it if you still die.' })
	RecoverHP = AutoFarm:CreateSlider({ Name = 'Resume at HP', Min = 20, Max = 100, Default = 85, Suffix = '%',
		Tooltip = 'Come back down and resume once HP recovers to this.' })
	HoverHeight = AutoFarm:CreateSlider({ Name = 'Retreat Height', Min = 20, Max = 400, Default = 150, Suffix = ' studs',
		Tooltip = 'How high to float above the map while recovering (out of enemy reach).' })
	EnemyOffset = AutoFarm:CreateSlider({ Name = 'Attack Height', Min = 0, Max = 30, Default = 2, Suffix = ' studs',
		Tooltip = 'Studs above each enemy. Keep it LOW (0-3) so you fight at their level and your swing/abilities land (facing is horizontal to avoid the Y-axis jitter). Raise it for safety, but hits start missing since you aim level, not down.' })
	FarmDelay = AutoFarm:CreateSlider({ Name = 'Loop Delay', Min = 0, Max = 0.5, Default = 0.1, Decimal = 100, Suffix = 's',
		Tooltip = 'Time between farm ticks (attack + reposition).' })
	UseTeleport = AutoFarm:CreateToggle({ Name = 'Teleport to Enemies', Default = true,
		Tooltip = 'On: instantly reposition onto each enemy (fast, may trip anti-cheat). Off: walk to them (slower, safer).' })
	HealSwap = AutoFarm:CreateToggle({ Name = 'Heal Swap when low', Default = true,
		Tooltip = 'When low, if you own a heal spell: swap to best spell-power weapon + 1-2 heals, heal to full, then restore your set. Requires the game to allow mid-run equipping.' })
end)

--VAINEOF
