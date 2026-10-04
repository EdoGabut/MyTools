-- ============================================================
-- Auto Brew Simple
-- Alur:
--   1. Tunggu malam (ClockTime >= 12 atau < 6)
--   2. Fire Briar Rose
--   3. Fire Spirethorn
--   4. Tunggu 13 menit
--   5. Fire Claim Reward
--   6. Loop
-- ============================================================
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")

local player = Players.LocalPlayer

local remote = ReplicatedStorage:WaitForChild("SharedModules")
	:WaitForChild("Packet"):WaitForChild("RemoteEvent")

-- ============================================================
-- CONFIG
-- ============================================================
local CONFIG = {
	BREW_WAIT     = 13 * 60,  -- 13 menit
	CLAIM_WAIT    = 2,        -- jeda setelah claim
	POLL_INTERVAL = 60,       -- cek malam tiap 60 detik
}

-- ============================================================
-- PAYLOAD
-- ============================================================
local function fireBriar()
	return pcall(function()
		local args = { buffer.fromstring("\195\0009\nBriar Rose") }
		remote:FireServer(unpack(args))
	end)
end

local function fireSpirethorn()
	return pcall(function()
		local args = { buffer.fromstring("\195\000^\016Common Seed Pack") }
		remote:FireServer(unpack(args))
	end)
end

local function fireClaim()
	return pcall(function()
		local args = { buffer.fromstring("\196\000O") }
		remote:FireServer(unpack(args))
	end)
end

-- ============================================================
-- STATE
-- ============================================================
local isRunning = false
local runToken = 0

-- ============================================================
-- HELPER
-- ============================================================
local function isNight()
	local ct = Lighting.ClockTime or 0
	local h = math.floor(ct) % 24
	return h >= 12 or h < 6
end

local function clockStr()
	local ct = Lighting.ClockTime or 0
	local h = math.floor(ct) % 24
	local m = math.floor((ct - math.floor(ct)) * 60)
	return string.format("%02d:%02d", h, m)
end

-- ============================================================
-- GUI
-- ============================================================
local COLORS = {
	bg        = Color3.fromRGB(22, 22, 28),
	header    = Color3.fromRGB(16, 16, 20),
	card      = Color3.fromRGB(32, 32, 40),
	text      = Color3.fromRGB(235, 235, 240),
	textDim   = Color3.fromRGB(140, 140, 155),
	green     = Color3.fromRGB(80, 200, 120),
	accentOff = Color3.fromRGB(60, 60, 72),
	red       = Color3.fromRGB(200, 70, 70),
	yellow    = Color3.fromRGB(230, 190, 120),
	purple    = Color3.fromRGB(170, 130, 230),
	night     = Color3.fromRGB(120, 140, 220),
	day       = Color3.fromRGB(255, 210, 90),
	stroke    = Color3.fromRGB(60, 60, 72),
	logBg     = Color3.fromRGB(14, 14, 18),
}

local function corner(p, r)
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r or 8); c.Parent = p
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "AutoBrewSimple"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Parent = player:WaitForChild("PlayerGui")

local FRAME_WIDTH = 230
local FRAME_HEIGHT = 230

local frame = Instance.new("Frame")
frame.Size = UDim2.new(0, FRAME_WIDTH, 0, FRAME_HEIGHT)
frame.Position = UDim2.new(0, 12, 0, 60)
frame.BackgroundColor3 = COLORS.bg
frame.BorderSizePixel = 0
frame.Active = true
frame.Parent = screenGui
corner(frame, 12)

local stroke = Instance.new("UIStroke")
stroke.Color = COLORS.stroke
stroke.Transparency = 0.4
stroke.Parent = frame

-- Drag
local dragging, dragStart, startPos
frame.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		dragging = true
		dragStart = input.Position
		startPos = frame.Position
	end
end)
frame.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		dragging = false
	end
end)
UserInputService.InputChanged:Connect(function(input)
	if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
		or input.UserInputType == Enum.UserInputType.Touch) then
		local delta = input.Position - dragStart
		frame.Position = UDim2.new(
			startPos.X.Scale, startPos.X.Offset + delta.X,
			startPos.Y.Scale, startPos.Y.Offset + delta.Y
		)
	end
end)

-- Title bar
local titleBar = Instance.new("Frame")
titleBar.Size = UDim2.new(1, 0, 0, 32)
titleBar.BackgroundColor3 = COLORS.header
titleBar.BorderSizePixel = 0
titleBar.Parent = frame
corner(titleBar, 12)

local fix = Instance.new("Frame")
fix.Size = UDim2.new(1, 0, 0, 10)
fix.Position = UDim2.new(0, 0, 1, -10)
fix.BackgroundColor3 = COLORS.header
fix.BorderSizePixel = 0
fix.Parent = titleBar

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -130, 1, 0)
title.Position = UDim2.new(0, 12, 0, 0)
title.BackgroundTransparency = 1
title.Text = "🍺 Auto Brew"
title.TextColor3 = COLORS.text
title.Font = Enum.Font.GothamBold
title.TextSize = 12
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = titleBar

local clockPill = Instance.new("TextLabel")
clockPill.Size = UDim2.new(0, 54, 0, 20)
clockPill.Position = UDim2.new(1, -110, 0, 6)
clockPill.BackgroundColor3 = COLORS.day
clockPill.Text = "00:00"
clockPill.TextColor3 = Color3.fromRGB(30, 30, 30)
clockPill.Font = Enum.Font.GothamBold
clockPill.TextSize = 11
clockPill.BorderSizePixel = 0
clockPill.Parent = titleBar
corner(clockPill, 6)

local function makeTitleBtn(xOffset, bg, txt)
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(0, 22, 0, 22)
	b.Position = UDim2.new(1, xOffset, 0, 5)
	b.BackgroundColor3 = bg
	b.Text = txt
	b.TextColor3 = Color3.fromRGB(255, 255, 255)
	b.Font = Enum.Font.GothamBold
	b.TextSize = 14
	b.BorderSizePixel = 0
	b.AutoButtonColor = false
	b.Parent = titleBar
	corner(b, 6)
	return b
end

local minimizeBtn = makeTitleBtn(-54, COLORS.accentOff, "—")
local closeBtn    = makeTitleBtn(-28, COLORS.red, "×")

-- Body
local body = Instance.new("Frame")
body.Size = UDim2.new(1, -16, 1, -40)
body.Position = UDim2.new(0, 8, 0, 36)
body.BackgroundTransparency = 1
body.Parent = frame

local statusCard = Instance.new("Frame")
statusCard.Size = UDim2.new(1, 0, 0, 50)
statusCard.Position = UDim2.new(0, 0, 0, 0)
statusCard.BackgroundColor3 = COLORS.card
statusCard.BorderSizePixel = 0
statusCard.Parent = body
corner(statusCard, 8)

local statusLbl = Instance.new("TextLabel")
statusLbl.Size = UDim2.new(1, -16, 0, 20)
statusLbl.Position = UDim2.new(0, 8, 0, 4)
statusLbl.BackgroundTransparency = 1
statusLbl.Text = "idle"
statusLbl.TextColor3 = COLORS.textDim
statusLbl.Font = Enum.Font.GothamBold
statusLbl.TextSize = 13
statusLbl.TextXAlignment = Enum.TextXAlignment.Left
statusLbl.Parent = statusCard

local subLbl = Instance.new("TextLabel")
subLbl.Size = UDim2.new(1, -16, 0, 16)
subLbl.Position = UDim2.new(0, 8, 0, 26)
subLbl.BackgroundTransparency = 1
subLbl.Text = "tap start untuk mulai"
subLbl.TextColor3 = COLORS.textDim
subLbl.Font = Enum.Font.Gotham
subLbl.TextSize = 10
subLbl.TextXAlignment = Enum.TextXAlignment.Left
subLbl.Parent = statusCard

local logLbl = Instance.new("TextLabel")
logLbl.Size = UDim2.new(1, 0, 0, 78)
logLbl.Position = UDim2.new(0, 0, 0, 56)
logLbl.BackgroundColor3 = COLORS.logBg
logLbl.BorderSizePixel = 0
logLbl.Text = "📜 Log:\n  (belum ada)"
logLbl.TextColor3 = COLORS.textDim
logLbl.Font = Enum.Font.Code
logLbl.TextSize = 10
logLbl.TextXAlignment = Enum.TextXAlignment.Left
logLbl.TextYAlignment = Enum.TextYAlignment.Top
logLbl.TextWrapped = true
logLbl.Parent = body
corner(logLbl, 6)
local lPad = Instance.new("UIPadding", logLbl)
lPad.PaddingLeft = UDim.new(0, 8)
lPad.PaddingRight = UDim.new(0, 8)
lPad.PaddingTop = UDim.new(0, 4)

local toggleBtn = Instance.new("TextButton")
toggleBtn.Size = UDim2.new(1, 0, 0, 40)
toggleBtn.Position = UDim2.new(0, 0, 1, -40)
toggleBtn.BackgroundColor3 = COLORS.green
toggleBtn.Text = "▶ START"
toggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
toggleBtn.Font = Enum.Font.GothamBold
toggleBtn.TextSize = 14
toggleBtn.BorderSizePixel = 0
toggleBtn.AutoButtonColor = false
toggleBtn.Parent = body
corner(toggleBtn, 8)

local logLines = {}
local MAX_LOG = 4

local function pushLog(msg)
	local t = os.date("%H:%M:%S")
	table.insert(logLines, 1, string.format("[%s] %s", t, msg))
	while #logLines > MAX_LOG do table.remove(logLines) end
	logLbl.Text = "📜 Log:\n" .. table.concat(logLines, "\n")
end

local function setStatus(main, sub, color)
	statusLbl.Text = main
	statusLbl.TextColor3 = color or COLORS.text
	subLbl.Text = sub or ""
end

local function setToggleUI(on)
	if on then
		toggleBtn.Text = "■ STOP"
		toggleBtn.BackgroundColor3 = COLORS.red
	else
		toggleBtn.Text = "▶ START"
		toggleBtn.BackgroundColor3 = COLORS.green
	end
end

-- Clock updater
task.spawn(function()
	while screenGui.Parent do
		local night = isNight()
		clockPill.Text = clockStr()
		clockPill.BackgroundColor3 = night and COLORS.night or COLORS.day
		clockPill.TextColor3 = night and Color3.fromRGB(255,255,255) or Color3.fromRGB(30,30,30)
		task.wait(1)
	end
end)

-- ============================================================
-- MAIN CYCLE
-- ============================================================
local function mainCycle()
	runToken += 1
	local myToken = runToken

	while isRunning and myToken == runToken do
		-- ===== TUNGGU MALAM =====
		if not isNight() then
			while isRunning and myToken == runToken and not isNight() do
				setStatus("☀️ nunggu malam", "ClockTime " .. clockStr() .. " · cek tiap " .. CONFIG.POLL_INTERVAL .. "s", COLORS.day)

				local t0 = tick()
				while isRunning and myToken == runToken and (tick() - t0) < CONFIG.POLL_INTERVAL do
					task.wait(0.5)
				end
			end
		end

		if not (isRunning and myToken == runToken) then break end

		-- ===== MALAM =====
		pushLog("🌙 malam tiba (" .. clockStr() .. ")")
		setStatus("🌙 malam", "mulai trigger", COLORS.night)
		task.wait(1)

		-- ===== FIRE BRIAR =====
		setStatus("🌹 fire Briar...", "", COLORS.purple)
		local okBriar = fireBriar()
		pushLog(okBriar and "✓ briar terkirim" or "✗ briar gagal")
		task.wait(2)

		-- ===== FIRE SPIRETHORN =====
		setStatus("🌵 fire Spirethorn...", "", COLORS.purple)
		local okSpire = fireSpirethorn()
		pushLog(okSpire and "✓ spirethorn terkirim" or "✗ spirethorn gagal")
		task.wait(2)

		-- ===== TUNGGU 13 MENIT =====
		pushLog("⏳ tunggu 13 menit")

		local t0 = tick()
		while isRunning and myToken == runToken and (tick() - t0) < CONFIG.BREW_WAIT do
			local remaining = math.max(0, CONFIG.BREW_WAIT - (tick() - t0))
			local m = math.floor(remaining / 60)
			local s = math.floor(remaining % 60)
			setStatus("🍺 brewing...", string.format("sisa %02d:%02d", m, s), COLORS.purple)
			task.wait(1)
		end

		if not (isRunning and myToken == runToken) then break end

		-- ===== CLAIM =====
		setStatus("🎁 claim reward...", "", COLORS.green)
		local okClaim = fireClaim()
		pushLog(okClaim and "✓ claim terkirim" or "✗ claim gagal")
		task.wait(CONFIG.CLAIM_WAIT)

		-- ===== LOOP =====
		pushLog("🔁 siklus selesai, cek malam lagi")
		setStatus("✅ selesai", "ulang dari awal", COLORS.green)
		task.wait(1)
	end

	setStatus("idle", "tap start untuk mulai", COLORS.textDim)
	pushLog("⏹ stopped")
end

-- ============================================================
-- START / STOP
-- ============================================================
local function startLoop()
	if isRunning then return end
	isRunning = true
	setToggleUI(true)
	pushLog("▶ started")
	task.spawn(mainCycle)
end

local function stopLoop()
	isRunning = false
	runToken += 1
	setToggleUI(false)
	setStatus("idle", "tap start untuk mulai", COLORS.textDim)
end

toggleBtn.MouseButton1Click:Connect(function()
	if isRunning then stopLoop() else startLoop() end
end)

toggleBtn.MouseEnter:Connect(function()
	if not isRunning then
		TweenService:Create(toggleBtn, TweenInfo.new(0.1), {
			BackgroundColor3 = Color3.fromRGB(100, 220, 140)
		}):Play()
	end
end)
toggleBtn.MouseLeave:Connect(function()
	if not isRunning then
		TweenService:Create(toggleBtn, TweenInfo.new(0.1), {
			BackgroundColor3 = COLORS.green
		}):Play()
	end
end)

-- ============================================================
-- MINIMIZE / CLOSE
-- ============================================================
local minimized = false
local savedSize = FRAME_HEIGHT

minimizeBtn.MouseButton1Click:Connect(function()
	minimized = not minimized
	if minimized then
		savedSize = frame.Size.Y.Offset
		TweenService:Create(frame, TweenInfo.new(0.2), {
			Size = UDim2.new(0, FRAME_WIDTH, 0, 32)
		}):Play()
		body.Visible = false
	else
		TweenService:Create(frame, TweenInfo.new(0.2), {
			Size = UDim2.new(0, FRAME_WIDTH, 0, savedSize)
		}):Play()
		body.Visible = true
	end
end)

closeBtn.MouseButton1Click:Connect(function()
	stopLoop()
	screenGui:Destroy()
end)

-- ============================================================
-- INIT
-- ============================================================
setStatus("idle", "tap start untuk mulai", COLORS.textDim)
setToggleUI(false)
