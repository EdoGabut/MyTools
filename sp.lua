-- ============================================================
-- Set WalkSpeed ke 30
-- ============================================================
local Players = game:GetService("Players")
local player = Players.LocalPlayer

local SPEED = 30

local function applySpeed(char)
	if not char then return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.WalkSpeed = SPEED
	end
end

-- Apply ke character sekarang
applySpeed(player.Character)

-- Apply tiap kali respawn
player.CharacterAdded:Connect(function(char)
	task.wait(0.5)
	applySpeed(char)
end)
