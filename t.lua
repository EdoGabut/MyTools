-- ============================================================
-- Trowel Sender (Hardcoded ID + Header Fixed)
-- Target: 11142670172
-- ============================================================
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

local remote = ReplicatedStorage:WaitForChild("SharedModules")
	:WaitForChild("Packet"):WaitForChild("RemoteEvent")

-- ===== CONFIG =====
local TARGET_USER_ID = 11142670172  -- ID lu, hardcoded
local ITEM_NAME = "Trowel"
local CATEGORY = "Trowels"
local DEFAULT_COUNT = 200

-- ===== PAYLOAD BUILDER =====
-- Header: 8C 01 [UserID f64 8B] 42 1C 05 01 1C
local function buildPayload(targetUserId, itemName, count, category)
	local buf = buffer.create(512)
	local pos = 0
	local function writeU8(n) buffer.writeu8(buf, pos, n); pos += 1 end
	local function writeString(s)
		writeU8(0x0B); writeU8(#s)
		for i = 1, #s do writeU8(string.byte(s, i)) end
	end
	local function writeInt(n) writeU8(0x05); writeU8(n) end

	-- Header
	writeU8(0x8C); writeU8(0x01)
	buffer.writef64(buf, pos, targetUserId); pos += 8
	writeU8(0x42); writeU8(0x1C)
	writeU8(0x05); writeU8(0x01); writeU8(0x1C)

	-- Data
	writeString("ItemKey"); writeString(itemName)
	writeString("Count"); writeInt(count)
	writeString("Category"); writeString(category)

	-- Terminator
	writeU8(0x00); writeU8(0x00); writeU8(0x00)

	local final = buffer.create(pos)
	buffer.copy(final, 0, buf, 0, pos)
	return final
end

-- ============================================================
-- ===== BUILD GUI =====
-- ============================================================
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "TrowelSender"
screenGui.ResetOnSpawn = false
screenGui.Parent = player:WaitForChild("PlayerGui")

local COLORS = {
	bg       = Color3.fromRGB(22, 22, 28),
	header   = Color3.fromRGB(16, 16, 20),
	input    = Color3.fromRGB(15, 15, 20),
	text     = Color3.fromRGB(235, 235, 240),
	textDim  = Color3.fromRGB(140, 140, 155),
	placeholder = Color3.fromRGB(110, 110, 125),
	green    = Color3.fromRGB(80, 200, 120),
	greenHv  = Color3.fromRGB(100, 220, 140),
	red      = Color3.fromRGB(200, 70, 70),
	stroke   = Color3.fromRGB(60, 60, 72),
}

local function corner(p, r)
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r or 8); c.Parent = p
end

local FRAME_WIDTH = 260
local FRAME_HEIGHT = 140

local frame = Instance.new("Frame")
frame.Size = UDim2.new(0, FRAME_WIDTH, 0, FRAME_HEIGHT)
frame.Position = UDim2.new(0, 15, 0, 15)
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
titleBar.Size = UDim2.new(1, 0, 0, 30)
titleBar.BackgroundColor3 = COLORS.header
titleBar.BorderSizePixel = 0
titleBar.ZIndex = 20
titleBar.Parent = frame
corner(titleBar, 12)

local fix = Instance.new("Frame")
fix.Size = UDim2.new(1, 0, 0, 10)
fix.Position = UDim2.new(0, 0, 1, -10)
fix.BackgroundColor3 = COLORS.header
fix.BorderSizePixel = 0
fix.ZIndex = 20
fix.Parent = titleBar

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -40, 1, 0)
title.Position = UDim2.new(0, 12, 0, 0)
title.BackgroundTransparency = 1
title.Text = "🛠 Trowel Sender"
title.TextColor3 = COLORS.text
title.Font = Enum.Font.GothamBold
title.TextSize = 12
title.TextXAlignment = Enum.TextXAlignment.Left
title.ZIndex = 21
title.Parent = titleBar

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 24, 0, 24)
closeBtn.Position = UDim2.new(1, -30, 0, 3)
closeBtn.BackgroundColor3 = COLORS.red
closeBtn.Text = "×"
closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 14
closeBtn.BorderSizePixel = 0
closeBtn.AutoButtonColor = false
closeBtn.ZIndex = 21
closeBtn.Parent = titleBar
corner(closeBtn, 5)

-- Body
local body = Instance.new("Frame")
body.Size = UDim2.new(1, -16, 1, -42)
body.Position = UDim2.new(0, 8, 0, 38)
body.BackgroundTransparency = 1
body.Parent = frame

-- Count input
local countRow = Instance.new("Frame")
countRow.Size = UDim2.new(1, 0, 0, 36)
countRow.Position = UDim2.new(0, 0, 0, 0)
countRow.BackgroundTransparency = 1
countRow.Parent = body

local countLbl = Instance.new("TextLabel")
countLbl.Size = UDim2.new(0, 100, 1, 0)
countLbl.BackgroundTransparency = 1
countLbl.Text = "Jumlah:"
countLbl.TextColor3 = COLORS.textDim
countLbl.Font = Enum.Font.GothamMedium
countLbl.TextSize = 11
countLbl.TextXAlignment = Enum.TextXAlignment.Left
countLbl.Parent = countRow

local countBox = Instance.new("TextBox")
countBox.Size = UDim2.new(1, -100, 1, 0)
countBox.Position = UDim2.new(0, 100, 0, 0)
countBox.BackgroundColor3 = COLORS.input
countBox.Text = tostring(DEFAULT_COUNT)
countBox.PlaceholderText = tostring(DEFAULT_COUNT)
countBox.TextColor3 = COLORS.text
countBox.PlaceholderColor3 = COLORS.placeholder
countBox.Font = Enum.Font.Code
countBox.TextSize = 13
countBox.TextXAlignment = Enum.TextXAlignment.Center
countBox.ClearTextOnFocus = false
countBox.BorderSizePixel = 0
countBox.Parent = countRow
corner(countBox, 6)

-- Send button
local sendBtn = Instance.new("TextButton")
sendBtn.Size = UDim2.new(1, 0, 0, 38)
sendBtn.Position = UDim2.new(0, 0, 0, 50)
sendBtn.BackgroundColor3 = COLORS.green
sendBtn.Text = "SEND TROWEL"
sendBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
sendBtn.Font = Enum.Font.GothamBold
sendBtn.TextSize = 13
sendBtn.BorderSizePixel = 0
sendBtn.AutoButtonColor = false
sendBtn.Parent = body
corner(sendBtn, 8)

-- ===== COUNT CLAMP =====
countBox.FocusLost:Connect(function()
	local n = tonumber(countBox.Text) or DEFAULT_COUNT
	n = math.clamp(math.floor(n), 1, 255)
	countBox.Text = tostring(n)
end)

-- ===== SEND =====
local function flashSend(text, color, duration)
	sendBtn.Text = text
	sendBtn.BackgroundColor3 = color
	sendBtn.Active = false
	task.delay(duration or 1.5, function()
		sendBtn.Text = "SEND TROWEL"
		sendBtn.BackgroundColor3 = COLORS.green
		sendBtn.Active = true
	end)
end

sendBtn.MouseButton1Click:Connect(function()
	local count = tonumber(countBox.Text) or DEFAULT_COUNT
	count = math.clamp(math.floor(count), 1, 255)

	sendBtn.Text = "⏳ Sending..."
	sendBtn.Active = false

	task.spawn(function()
		local payload = buildPayload(TARGET_USER_ID, ITEM_NAME, count, CATEGORY)

		local ok = pcall(function() remote:FireServer(payload) end)

		if ok then
			flashSend(string.format("✓ Trowel x%d", count), COLORS.green, 2)
		else
			flashSend("❌ Fire fail", COLORS.red)
		end
	end)
end)

sendBtn.MouseEnter:Connect(function()
	if sendBtn.Active then
		TweenService:Create(sendBtn, TweenInfo.new(0.1), { BackgroundColor3 = COLORS.greenHv }):Play()
	end
end)
sendBtn.MouseLeave:Connect(function()
	if sendBtn.Active then
		TweenService:Create(sendBtn, TweenInfo.new(0.1), { BackgroundColor3 = COLORS.green }):Play()
	end
end)

closeBtn.MouseButton1Click:Connect(function()
	screenGui:Destroy()
end)
