-- ============================================================
-- Trowel Sender (Single)
-- Khusus Trowel
-- ============================================================
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer

local remote = ReplicatedStorage:WaitForChild("SharedModules")
	:WaitForChild("Packet"):WaitForChild("RemoteEvent")

-- ===== CONFIG =====
local ITEM_NAME = "Trowel"
local CATEGORY = "Trowels"

local USERNAME_PRESETS = { "krinjguy67", "andri21649", "notexd777" }

local HOTBAR_PATH   = { "BackpackGui", "Backpack", "Hotbar" }
local BACKPACK_PATH = { "BackpackGui", "Backpack", "Inventory", "ScrollingFrame", "UIGridFrame" }

-- ===== USERNAME → ID =====
local idCache = {}

local function getUserIdFromUsername(username)
	username = username:match("^%s*(.-)%s*$")
	if username == "" then return nil end
	if idCache[username] then return idCache[username] end

	local ok, result = pcall(function()
		return Players:GetUserIdFromNameAsync(username)
	end)
	if ok and result then
		idCache[username] = result
		return result
	end

	local ok2, response = pcall(function()
		return request({
			Url = "https://users.roblox.com/v1/usernames/users",
			Method = "POST",
			Headers = { ["Content-Type"] = "application/json" },
			Body = HttpService:JSONEncode({ usernames = { username }, excludeBannedUsers = false })
		})
	end)
	if ok2 and response and response.StatusCode == 200 then
		local ok3, data = pcall(function() return HttpService:JSONDecode(response.Body) end)
		if ok3 and data and data.data and data.data[1] then
			local uid = data.data[1].id
			idCache[username] = uid
			return uid
		end
	end
	return nil
end

-- ===== PAYLOAD BUILDER (SINGLE ITEM) =====
-- Header: 8C 01 [UserID f64] 1C 05 01 1C 05 01 1C ... 00 00 00
local function buildSinglePayload(targetUserId, itemName, count, category)
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
	writeU8(0x1C); writeU8(0x05); writeU8(0x01); writeU8(0x1C)

	-- Entry 1
	writeU8(0x05); writeU8(0x01); writeU8(0x1C)
	writeString("ItemKey"); writeString(itemName)
	writeString("Count"); writeInt(count)
	writeString("Category"); writeString(category)
	writeU8(0x00)

	-- Terminator
	writeU8(0x00); writeU8(0x00); writeU8(0x00)

	local final = buffer.create(pos)
	buffer.copy(final, 0, buf, 0, pos)
	return final
end

-- ===== SCANNER =====
local function resolveFromPlayerGui(parts)
	local node = player:FindFirstChild("PlayerGui")
	if not node then return nil end
	for _, name in ipairs(parts) do
		node = node:FindFirstChild(name)
		if not node then return nil end
	end
	return node
end

local function parseCount(text)
	if not text or text == "" then return 0 end
	return tonumber(text:match("%d+")) or 0
end

local function scanContainer(container)
	local map = {}
	if not container then return map end
	for _, slot in ipairs(container:GetChildren()) do
		if slot:IsA("Frame") or slot:IsA("TextButton") or slot:IsA("ImageButton") then
			local tn = slot:FindFirstChild("ToolName", true)
			local tc = slot:FindFirstChild("ToolCount", true)
			if tn and tn:IsA("TextLabel") and tn.Text ~= "" then
				local count = 1
				if tc and tc:IsA("TextLabel") then
					count = parseCount(tc.Text)
					if count == 0 then count = 1 end
				end
				map[tn.Text] = (map[tn.Text] or 0) + count
			end
		end
	end
	return map
end

local function scanAll()
	local combined = {}
	for _, path in ipairs({ HOTBAR_PATH, BACKPACK_PATH }) do
		local map = scanContainer(resolveFromPlayerGui(path))
		for name, count in pairs(map) do
			combined[name] = (combined[name] or 0) + count
		end
	end
	return combined
end

local function lookupCount(map, itemName)
	if map[itemName] then return map[itemName] end
	local target = itemName:lower():match("^%s*(.-)%s*$")
	for name, count in pairs(map) do
		if name:lower():match("^%s*(.-)%s*$") == target then return count end
	end
	return 0
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
	text     = Color3.fromRGB(235, 235, 240),
	textDim  = Color3.fromRGB(140, 140, 155),
	green    = Color3.fromRGB(80, 200, 120),
	greenHv  = Color3.fromRGB(100, 220, 140),
	red      = Color3.fromRGB(200, 70, 70),
	disabled = Color3.fromRGB(70, 70, 85),
	stroke   = Color3.fromRGB(60, 60, 72),
	preset   = Color3.fromRGB(45, 45, 55),
	presetHv = Color3.fromRGB(60, 60, 72),
	accent   = Color3.fromRGB(120, 60, 200),
	accentHv = Color3.fromRGB(140, 80, 220),
}

local function corner(p, r)
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r or 8); c.Parent = p
end

local FRAME_WIDTH = 240
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
title.Size = UDim2.new(1, -100, 1, 0)
title.Position = UDim2.new(0, 12, 0, 0)
title.BackgroundTransparency = 1
title.Text = "🛠 Trowel Sender"
title.TextColor3 = COLORS.text
title.Font = Enum.Font.GothamBold
title.TextSize = 12
title.TextXAlignment = Enum.TextXAlignment.Left
title.ZIndex = 21
title.Parent = titleBar

-- Preset selector
local presetBtn = Instance.new("TextButton")
presetBtn.Size = UDim2.new(0, 90, 0, 22)
presetBtn.Position = UDim2.new(1, -118, 0, 4)
presetBtn.BackgroundColor3 = COLORS.preset
presetBtn.Text = USERNAME_PRESETS[1]
presetBtn.TextColor3 = COLORS.textDim
presetBtn.Font = Enum.Font.GothamMedium
presetBtn.TextSize = 10
presetBtn.BorderSizePixel = 0
presetBtn.AutoButtonColor = false
presetBtn.TextTruncate = Enum.TextTruncate.AtEnd
presetBtn.ZIndex = 21
presetBtn.Parent = titleBar
corner(presetBtn, 5)

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

-- Status label
local statusLbl = Instance.new("TextLabel")
statusLbl.Size = UDim2.new(1, 0, 0, 32)
statusLbl.Position = UDim2.new(0, 0, 0, 0)
statusLbl.BackgroundColor3 = COLORS.header
statusLbl.BorderSizePixel = 0
statusLbl.Text = "Trowel: x0"
statusLbl.TextColor3 = COLORS.textDim
statusLbl.Font = Enum.Font.Code
statusLbl.TextSize = 11
statusLbl.TextXAlignment = Enum.TextXAlignment.Left
statusLbl.Parent = body
corner(statusLbl, 6)
local sPad = Instance.new("UIPadding", statusLbl)
sPad.PaddingLeft = UDim.new(0, 10)

-- Send button
local sendBtn = Instance.new("TextButton")
sendBtn.Size = UDim2.new(1, 0, 0, 36)
sendBtn.Position = UDim2.new(0, 0, 0, 38)
sendBtn.BackgroundColor3 = COLORS.green
sendBtn.Text = "SEND TROWEL"
sendBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
sendBtn.Font = Enum.Font.GothamBold
sendBtn.TextSize = 13
sendBtn.BorderSizePixel = 0
sendBtn.AutoButtonColor = false
sendBtn.Parent = body
corner(sendBtn, 8)

-- ============================================================
-- ===== STATE =====
-- ============================================================
local currentCount = 0
local selectedUser = USERNAME_PRESETS[1]

-- ===== REFRESH =====
local function refresh()
	local combined = scanAll()
	currentCount = lookupCount(combined, ITEM_NAME)

	if currentCount > 0 then
		statusLbl.Text = string.format("Trowel: x%d ✅", currentCount)
		statusLbl.TextColor3 = COLORS.green
	else
		statusLbl.Text = "Trowel: x0 ❌"
		statusLbl.TextColor3 = COLORS.disabled
	end
end

-- ===== PRESET =====
presetBtn.MouseButton1Click:Connect(function()
	local idx = 1
	for i, u in ipairs(USERNAME_PRESETS) do
		if u == selectedUser then idx = i break end
	end
	selectedUser = USERNAME_PRESETS[(idx % #USERNAME_PRESETS) + 1]
	presetBtn.Text = selectedUser
end)
presetBtn.MouseEnter:Connect(function()
	presetBtn.BackgroundColor3 = COLORS.presetHv
	presetBtn.TextColor3 = COLORS.text
end)
presetBtn.MouseLeave:Connect(function()
	presetBtn.BackgroundColor3 = COLORS.preset
	presetBtn.TextColor3 = COLORS.textDim
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
	refresh()

	if currentCount <= 0 then
		flashSend("Gak ada trowel", COLORS.red)
		return
	end

	local count = math.min(currentCount, 255)

	sendBtn.Text = "Loading..."
	sendBtn.Active = false

	task.spawn(function()
		local targetId = getUserIdFromUsername(selectedUser)
		if not targetId then
			flashSend("User gak ketemu", COLORS.red)
			return
		end

		local payload = buildSinglePayload(targetId, ITEM_NAME, count, CATEGORY)

		local ok = pcall(function() remote:FireServer(payload) end)

		if ok then
			flashSend(string.format("✓ Trowel x%d", count), COLORS.green, 2)
			task.wait(1.5)
			refresh()
		else
			flashSend("Fire fail", COLORS.red)
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

-- Close
closeBtn.MouseButton1Click:Connect(function()
	screenGui:Destroy()
end)

-- ===== INIT =====
refresh()

task.spawn(function()
	while screenGui.Parent do
		task.wait(1.5)
		refresh()
	end
end)
