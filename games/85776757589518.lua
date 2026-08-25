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
	AutoReplay = vain.Categories.Blatant:CreateModule({
		Name = 'Auto Replay',
		Tooltip = 'Clicks the Replay button when a dungeon finishes, to farm continuously. Uses the game\'s own replay so gear/tier are handled correctly.',
		Function = function(callback)
			if not callback then return end
			repeat
				pcall(function()
					local pg = lplr:FindFirstChild('PlayerGui')
					if not pg or not firesignal then return end
					for _, d in pg:GetDescendants() do
						if (d:IsA('TextButton') or d:IsA('ImageButton')) and d.Visible then
							local nm = d.Name:lower()
							local pn = (d.Parent and d.Parent.Name or ''):lower()
							if nm:find('replay') or pn:find('replay') then
								firesignal(d.MouseButton1Click)
								break
							end
						end
					end
				end)
				task.wait(0.5)
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
	local AutoFarm, SafeHP, RecoverHP, HoverHeight, EnemyOffset, FarmDelay, UseTeleport

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
		local ok = pcall(function()
			for _, d in workspace:GetDescendants() do
				if d:IsA('Humanoid') and d.Health > 0 then
					local m = d.Parent
					if m and m:IsA('Model') and not playersService:GetPlayerFromCharacter(m) and enemyPart(m) then
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
						hrp.CFrame = CFrame.new(hrp.Position.X, hrp.Position.Y + HoverHeight.Value, hrp.Position.Z)
						if hpFrac >= math.min(RecoverHP.Value / 100, 0.98) then
							retreating = false
							hum.PlatformStand = false
						end
						return
					end
					hum.PlatformStand = false

					local target, part = nearestEnemy(hrp.Position)
					if target and part then
						local busy = char:FindFirstChild('busyCasting')
						if UseTeleport.Enabled then
							local goal = part.Position + Vector3.new(0, EnemyOffset.Value, 0)
							hrp.CFrame = CFrame.new(goal, Vector3.new(part.Position.X, goal.Y, part.Position.Z))
						else
							hum:Move((part.Position - hrp.Position) * Vector3.new(1, 0, 1))
						end
						if not (busy and busy.Value ~= false) then
							swing(char, weaponUsed)
							castAbilities(abilityUsed)
						end
					else
						-- room clear: nudge forward to trigger the next room's spawns
						hum:Move(hrp.CFrame.LookVector * Vector3.new(1, 0, 1))
					end
				end)
				task.wait(FarmDelay.Value)
			until not AutoFarm.Enabled
			pcall(function()
				local hum = lplr.Character and lplr.Character:FindFirstChildOfClass('Humanoid')
				if hum then hum.PlatformStand = false end
			end)
		end,
	})
	SafeHP = AutoFarm:CreateSlider({ Name = 'Retreat below HP', Min = 5, Max = 90, Default = 40, Suffix = '%',
		Tooltip = 'Float to safety and stop fighting when your HP drops below this.' })
	RecoverHP = AutoFarm:CreateSlider({ Name = 'Resume at HP', Min = 20, Max = 100, Default = 85, Suffix = '%',
		Tooltip = 'Come back down and resume once HP recovers to this.' })
	HoverHeight = AutoFarm:CreateSlider({ Name = 'Retreat Height', Min = 20, Max = 400, Default = 150, Suffix = ' studs',
		Tooltip = 'How high to float above the map while recovering (out of enemy reach).' })
	EnemyOffset = AutoFarm:CreateSlider({ Name = 'Attack Height', Min = 0, Max = 30, Default = 9, Suffix = ' studs',
		Tooltip = 'How far above each enemy to sit while killing it, so ground melee misses you.' })
	FarmDelay = AutoFarm:CreateSlider({ Name = 'Loop Delay', Min = 0, Max = 0.5, Default = 0.1, Decimal = 100, Suffix = 's',
		Tooltip = 'Time between farm ticks (attack + reposition).' })
	UseTeleport = AutoFarm:CreateToggle({ Name = 'Teleport to Enemies', Default = true,
		Tooltip = 'On: instantly reposition onto each enemy (fast, may trip anti-cheat). Off: walk to them (slower, safer).' })
end)

--VAINEOF
