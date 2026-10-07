-- LocalScript: Anti-AFK + Position Guard (Weld)
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer

-- ===== CONFIG =====
local CONFIG = {
	-- Anti-AFK
	ANTI_AFK_ENABLED = true,
	AFK_MIN_DELAY = 180,   -- 3 menit
	AFK_MAX_DELAY = 300,   -- 5 menit

	-- Guard Weld
	GUARD_ENABLED = true,
	GUARD_RECORD_DELAY = 1.0,   -- delay rekam posisi stlh spawn
	GUARD_MAX_DRIFT = 3.0,      -- toleransi geser (stud). Kalau lewat ini → dianggap dipindah
	GUARD_CHECK_INTERVAL = 0.15, -- cek tiap 0.15s
}

-- ===== STATE =====
local antiAfkConn = nil
local guardConn = nil
local guardAnchor = nil     -- CFrame posisi aman
local guardActive = false

-- ===== COLORS =====
local C = {
	bg = Color3.fromRGB(18, 18, 20),
	header = Color3.fromRGB(24, 24, 27),
	text = Color3.fromRGB(220, 220, 225),
	textDim = Color3.fromRGB(110, 110, 120),
	green = Color3.fromRGB(80, 200, 120),
	greenHv = Color3.fromRGB(100, 220, 140),
	red = Color3.fromRGB(190, 65, 65),
	stroke = Color3.fromRGB(48, 48, 56),
	close = Color3.fromRGB(190, 65, 65),
	blue = Color3.fromRGB(70, 130, 200),
	blueHv = Color3.fromRGB(90, 150, 220),
}

-- ============================================================
-- ANTI-AFK
-- ============================================================
local function pressSpace()
	pcall(function()
		VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.Space, false, game)
		task.wait(0.05)
		VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Space, false, game)
	end)
end

local function clickLMB()
	pcall(function()
		VirtualInputManager:SendMouseButtonEvent(0, 0, 0, true, game, 1)
		task.wait(0.03)
		VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 1)
	end)
end

local function startAntiAFK()
	if antiAfkConn then return end
	antiAfkConn = task.spawn(function()
		while CONFIG.ANTI_AFK_ENABLED do
			local delay = math.random(CONFIG.AFK_MIN_DELAY, CONFIG.AFK_MAX_DELAY)
			task.wait(delay)

			if not CONFIG.ANTI_AFK_ENABLED then break end

			-- Random: klik, space, atau dua-duanya
			local action = math.random(1, 3)
			if action == 1 then
				clickLMB()
			elseif action == 2 then
				pressSpace()
			else
				clickLMB()
				task.wait(0.1)
				pressSpace()
			end

			print(string.format("[AntiAFK] Aksi dikirim, delay berikutnya: %ds", 
				math.random(CONFIG.AFK_MIN_DELAY, CONFIG.AFK_MAX_DELAY)))
		end
	end)
end

local function stopAntiAFK()
	CONFIG.ANTI_AFK_ENABLED = false
	if antiAfkConn then
		task.cancel(antiAfkConn)
		antiAfkConn = nil
	end
end

-- ============================================================
-- GUARD WELD (kunci posisi)
-- ============================================================
local function recordAnchor()
	local char = player.Character
	if not char then return end
	local root = char:FindFirstChild("HumanoidRootPart")
	if not root then return end
	guardAnchor = root.CFrame
	guardActive = true
	print("[Guard] Posisi terkunci di:", tostring(root.Position))
end

local function stopGuard()
	guardActive = false
	guardAnchor = nil
	if guardConn then
		guardConn:Disconnect()
		guardConn = nil
	end
end

local function startGuard()
	stopGuard()
	guardAnchor = nil

	task.spawn(function()
		-- Tunggu karakter siap
		local char = player.Character or player.CharacterAdded:Wait()
		char:WaitForChild("HumanoidRootPart", 10)
		task.wait(CONFIG.GUARD_RECORD_DELAY)

		recordAnchor()
		if not guardAnchor then
			warn("[Guard] Gagal record posisi")
			return
		end

		local lastWarn = 0

		guardConn = RunService.Heartbeat:Connect(function()
			if not guardActive then return end
			local c = player.Character
			if not c then return end
			local root = c:FindFirstChild("HumanoidRootPart")
			if not root then return end

			local currentPos = root.Position
			local anchorPos = guardAnchor.Position
			local drift = (currentPos - anchorPos).Magnitude

			if drift > CONFIG.GUARD_MAX_DRIFT then
				-- Dikembalikan ke posisi anchor
				root.CFrame = guardAnchor

				-- Reset velocity biar gak ada sisa dorongan
				root.AssemblyLinearVelocity = Vector3.zero
				root.AssemblyAngularVelocity = Vector3.zero

				-- Anti-weld yang mungkin dipasang player lain ke kita
				for _, obj in ipairs(root:GetChildren()) do
					if obj:IsA("Weld") or obj:IsA("WeldConstraint") 
						or obj:IsA("Motor6D") or obj:IsA("Snap") then
						local part0 = obj.Part0
						local part1 = obj.Part1
						-- Kalau weld melibatkan part dari luar character kita → hapus
						if part0 and part0:IsDescendantOf(player.Character) == false then
							obj:Destroy()
						end
						if part1 and part1:IsDescendantOf(player.Character) == false then
							obj:Destroy()
						end
					end
				end

				-- Log kalau kejadian (batasi 1x per 2 detik)
				local now = tick()
				if now - lastWarn > 2 then
					lastWarn = now
					print(string.format("[Guard] Dipindahkan %.1f stud → dikembalikan", drift))
				end
			end
		end)
	end)
end

-- ============================================================
-- GUI
-- ============================================================
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "AntiAfkGuard"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Parent = player:WaitForChild("PlayerGui")

local FRAME_W = 220
local FRAME_H = 120

local frame = Instance.new("Frame")
frame.Size = UDim2.new(0, FRAME_W, 0, FRAME_H)
frame.Position = UDim2.new(0, 12, 0, 60)
frame.BackgroundColor3 = C.bg
frame.BorderSizePixel = 0
frame.Active = true
frame.Draggable = true
frame.Parent = screenGui
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 10)

local stroke = Instance.new("UIStroke")
stroke.Color = C.stroke
stroke.Thickness = 1
stroke.Transparency = 0.3
stroke.Parent = frame

-- Header
local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 28)
header.BackgroundColor3 = C.header
header.BorderSizePixel = 0
header.Parent = frame
Instance.new("UICorner", header).CornerRadius = UDim.new(0, 10)

local headerFix = Instance.new("Frame")
headerFix.Size = UDim2.new(1, 0, 0, 8)
headerFix.Position = UDim2.new(0, 0, 1, -8)
headerFix.BackgroundColor3 = C.header
headerFix.BorderSizePixel = 0
headerFix.Parent = header

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -40, 1, 0)
title.Position = UDim2.new(0, 10, 0, 0)
title.BackgroundTransparency = 1
title.Text = "🛡 Anti-AFK + Guard"
title.TextColor3 = C.text
title.Font = Enum.Font.GothamBold
title.TextSize = 11
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = header

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 18, 0, 18)
closeBtn.Position = UDim2.new(1, -24, 0.5, -9)
closeBtn.BackgroundColor3 = C.close
closeBtn.Text = "×"
closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 13
closeBtn.BorderSizePixel = 0
closeBtn.AutoButtonColor = false
closeBtn.Parent = header
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 4)

-- Status label
local statusLbl = Instance.new("TextLabel")
statusLbl.Size = UDim2.new(1, -16, 0, 16)
statusLbl.Position = UDim2.new(0, 8, 0, 32)
statusLbl.BackgroundTransparency = 1
statusLbl.Text = "Anti-AFK: ON | Guard: OFF"
statusLbl.TextColor3 = C.textDim
statusLbl.Font = Enum.Font.Code
statusLbl.TextSize = 9
statusLbl.TextXAlignment = Enum.TextXAlignment.Left
statusLbl.Parent = frame

-- Toggle Anti-AFK button
local afkBtn = Instance.new("TextButton")
afkBtn.Size = UDim2.new(1, -16, 0, 28)
afkBtn.Position = UDim2.new(0, 8, 0, 52)
afkBtn.BackgroundColor3 = C.green
afkBtn.Text = "▶ Anti-AFK: ON"
afkBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
afkBtn.Font = Enum.Font.GothamBold
afkBtn.TextSize = 11
afkBtn.BorderSizePixel = 0
afkBtn.AutoButtonColor = false
afkBtn.Parent = frame
Instance.new("UICorner", afkBtn).CornerRadius = UDim.new(0, 6)

-- Toggle Guard button
local guardBtn = Instance.new("TextButton")
guardBtn.Size = UDim2.new(1, -16, 0, 28)
guardBtn.Position = UDim2.new(0, 8, 0, 84)
guardBtn.BackgroundColor3 = C.blue
guardBtn.Text = "🔒 Lock Position"
guardBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
guardBtn.Font = Enum.Font.GothamBold
guardBtn.TextSize = 11
guardBtn.BorderSizePixel = 0
guardBtn.AutoButtonColor = false
guardBtn.Parent = frame
Instance.new("UICorner", guardBtn).CornerRadius = UDim.new(0, 6)

-- ===== STATE =====
local antiAfkOn = true
local guardOn = false

local function updateStatus()
	local afkStr = antiAfkOn and "ON" or "OFF"
	local gStr = guardOn and "🔒 LOCKED" or "OFF"
	statusLbl.Text = string.format("Anti-AFK: %s | Guard: %s", afkStr, gStr)
	statusLbl.TextColor3 = guardOn and C.green or C.textDim
end

-- ===== BUTTON EVENTS =====
afkBtn.MouseButton1Click:Connect(function()
	antiAfkOn = not antiAfkOn
	CONFIG.ANTI_AFK_ENABLED = antiAfkOn
	if antiAfkOn then
		afkBtn.Text = "▶ Anti-AFK: ON"
		afkBtn.BackgroundColor3 = C.green
		startAntiAFK()
	else
		afkBtn.Text = "⏸ Anti-AFK: OFF"
		afkBtn.BackgroundColor3 = C.red
		stopAntiAFK()
	end
	updateStatus()
end)

guardBtn.MouseButton1Click:Connect(function()
	guardOn = not guardOn
	if guardOn then
		guardBtn.Text = "🔓 Unlock Position"
		guardBtn.BackgroundColor3 = C.red
		startGuard()
	else
		guardBtn.Text = "🔒 Lock Position"
		guardBtn.BackgroundColor3 = C.blue
		stopGuard()
	end
	updateStatus()
end)

afkBtn.MouseEnter:Connect(function()
	if antiAfkOn then
		TweenService:Create(afkBtn, TweenInfo.new(0.1), {
			BackgroundColor3 = C.greenHv
		}):Play()
	end
end)
afkBtn.MouseLeave:Connect(function()
	if antiAfkOn then
		TweenService:Create(afkBtn, TweenInfo.new(0.1), {
			BackgroundColor3 = C.green
		}):Play()
	end
end)

guardBtn.MouseEnter:Connect(function()
	if not guardOn then
		TweenService:Create(guardBtn, TweenInfo.new(0.1), {
			BackgroundColor3 = C.blueHv
		}):Play()
	end
end)
guardBtn.MouseLeave:Connect(function()
	if not guardOn then
		TweenService:Create(guardBtn, TweenInfo.new(0.1), {
			BackgroundColor3 = C.blue
		}):Play()
	end
end)

-- ===== CLOSE =====
closeBtn.MouseButton1Click:Connect(function()
	stopAntiAFK()
	stopGuard()
	screenGui:Destroy()
end)

-- ===== CHARACTER RESPAWN =====
player.CharacterAdded:Connect(function()
	if guardOn then
		task.wait(CONFIG.GUARD_RECORD_DELAY)
		startGuard()
	end
end)

-- ===== INIT =====
startAntiAFK()
updateStatus()
print("[AntiAFK+Guard] Loaded")
