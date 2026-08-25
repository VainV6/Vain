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
looper(vain.Categories.Blatant, 'Auto Start Dungeon',
	'Starts your run as soon as the lobby is ready.', 'startDungeon', 1, inLobby)
looper(vain.Categories.Blatant, 'Auto Ready Up',
	'Automatically readies up in the lobby.', 'readyUp', 1)
looper(vain.Categories.Blatant, 'Auto Boss Raid',
	'Starts the boss raid as soon as the lobby is ready.', 'startBossRaid', 1, inLobby)
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
