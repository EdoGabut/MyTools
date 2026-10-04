-- ============================================================
-- Force WalkSpeed = 30 (Instant via PropertyChanged)
-- ============================================================
local Players = game:GetService("Players")
local player = Players.LocalPlayer

local SPEED = 30

local function hookHumanoid(hum)
	if not hum then return end
	-- Set langsung
	hum.WalkSpeed = SPEED
	-- Hook: begitu game ubah, langsung balikin
	hum:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
		if hum.WalkSpeed ~= SPEED then
			hum.WalkSpeed = SPEED
		end
	end)
end

local function setupChar(char)
	if not char then return end
	local hum = char:WaitForChild("Humanoid", 5)
	if hum then
		hookHumanoid(hum)
	end
end

-- Setup character sekarang
setupChar(player.Character)

-- Setup tiap respawn
player.CharacterAdded:Connect(function(char)
	task.wait(0.1)
	setupChar(char)
end)
