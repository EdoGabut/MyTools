-- ============================================================
-- Crate Sender — Batch 3 Crate
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
local ITEMS = {
	{ display = "Fog Machine Crate",    name = "Fog Machine Crate",    lookup = "Fog Machine Crate",    category = "Crates" },
	{ display = "Halloween Prop Crate", name = "Halloween Prop Crate", lookup = "Halloween Prop Crate", category = "Crates" },
	{ display = "Gravestone Crate",     name = "Gravestone Crate",     lookup = "Gravestone Crate",     category = "Crates" },
}

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

-- ===== PAYLOAD BUILDER (HEADER FIXED) =====
-- Header: 8C 01 [UserID f64] 1C 05 01 1C
local function buildMultiPayload(targetUserId, items)
	local buf = buffer.create(4096)
	local pos = 0
	local function writeU8(n) buffer.writeu8(buf, pos, n); pos += 1 end
	local function writeString(s)
		writeU8(0x0B); writeU8(#s)
		for i = 1, #s do writeU8(string.byte(s, i)) end
	end
	local function writeInt(n) writeU8(0x05); writeU8(n) end

	-- Header (FIXED)
	writeU8(0x8C); writeU8(0x01)
	buffer.writef64(buf, pos, targetUserId); pos += 8
	writeU8(0x1C); writeU8(0x05); writeU8(0x01); writeU8(0x1C)

	-- Items
	for i, item in ipairs(items) do
		writeU8(0x05); writeU8(i); writeU8(0x1C)
		writeString("ItemKey"); writeString(item.name)
		writeString("Count"); writeInt(item.count)
		writeString("Category"); writeString(item.category or "Crates")
		writeU8(0x00)
	end

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
screenGui.Name = "CrateSenderMini"
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
}

local function corner(p, r)
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r or 8); c.Parent = p
end

local frame = Instance.new("Frame")
frame.Size = UDim2.new(0, 240, 0, 180)
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
titleBar.Size = UDim2.new(1, 0, 0, 26)
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
title.Size = UDim2.new(1, -60, 1, 0)
title.Position = UDim2.new(0, 10, 0, 0)
title.BackgroundTransparency = 1
title.Text = "📦 Crate Sender"
title.TextColor3 = COLORS.text
title.Font = Enum.Font.GothamBold
title.TextSize = 11
title.TextXAlignment = Enum.TextXAlignment.Left
title.ZIndex = 21
title.Parent = titleBar

local presetBtn = Instance.new("TextButton")
presetBtn.Size = UDim2.new(0, 90, 0, 18)
presetBtn.Position = UDim2.new(1, -114, 0, 4)
presetBtn.BackgroundColor3 = COLORS.preset
presetBtn.Text = USERNAME_PRESETS[1]
presetBtn.TextColor3 = COLORS.textDim
presetBtn.Font = Enum.Font.GothamMedium
presetBtn.TextSize = 9
presetBtn.BorderSizePixel = 0
presetBtn.AutoButtonColor = false
presetBtn.TextTruncate = Enum.TextTruncate.AtEnd
presetBtn.ZIndex = 21
presetBtn.Parent = titleBar
corner(presetBtn, 5)

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 18, 0, 18)
closeBtn.Position = UDim2.new(1, -22, 0, 4)
closeBtn.BackgroundColor3 = COLORS.red
closeBtn.Text = "×"
closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 12
closeBtn.BorderSizePixel = 0
closeBtn.AutoButtonColor = false
closeBtn.ZIndex = 21
closeBtn.Parent = titleBar
corner(closeBtn, 5)

-- Body
local body = Instance.new("Frame")
body.Size = UDim2.new(1, -12, 1, -32)
body.Position = UDim2.new(0, 6, 0, 28)
body.BackgroundTransparency = 1
body.Parent = frame

-- Log
local logLbl = Instance.new("TextLabel")
logLbl.Size = UDim2.new(1, 0, 0, 80)
logLbl.Position = UDim2.new(0, 0, 0, 0)
logLbl.BackgroundColor3 = COLORS.header
logLbl.BorderSizePixel = 0
logLbl.Text = "Scanning..."
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
lPad.PaddingTop = UDim.new(0, 6)

-- Send button
local sendBtn = Instance.new("TextButton")
sendBtn.Size = UDim2.new(1, 0, 0, 32)
sendBtn.Position = UDim2.new(0, 0, 1, -32)
sendBtn.BackgroundColor3 = COLORS.green
sendBtn.Text = "SEND CRATES"
sendBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
sendBtn.Font = Enum.Font.GothamBold
sendBtn.TextSize = 12
sendBtn.BorderSizePixel = 0
sendBtn.AutoButtonColor = false
sendBtn.Parent = body
corner(sendBtn, 8)

-- ============================================================
-- ===== STATE =====
-- ============================================================
local cachedScan = {}
local currentCounts = {}
local selectedUser = USERNAME_PRESETS[1]

local function collectCrates()
	local list = {}
	for _, item in ipairs(ITEMS) do
		local count = currentCounts[item.display] or 0
		if count > 0 then
			table.insert(list, {
				name = item.name,
				count = math.min(count, 255),
				category = item.category,
				display = item.display,
			})
		end
	end
	return list
end

local function buildSummary()
	for _, item in ipairs(ITEMS) do
		currentCounts[item.display] = lookupCount(cachedScan, item.lookup)
	end

	local lines = {}
	local totalAll = 0

	for _, item in ipairs(ITEMS) do
		local c = currentCounts[item.display] or 0
		totalAll += c
		local mark = (c > 0) and "✅" or "❌"
		table.insert(lines, string.format("%s %s x%d", mark, item.display, c))
	end

	table.insert(lines, string.format("Total: %d crate", totalAll))

	return table.concat(lines, "\n")
end

local function render()
	logLbl.Text = buildSummary()
	logLbl.TextColor3 = COLORS.text
end

local function refresh()
	cachedScan = scanAll()
	render()
end

-- Preset selector
presetBtn.MouseButton1Click:Connect(function()
	local idx = 1
	for i, u in ipairs(USERNAME_PRESETS) do
		if u == selectedUser then idx = i break end
	end
	selectedUser = USERNAME_PRESETS[(idx % #USERNAME_PRESETS) + 1]
	presetBtn.Text = selectedUser
end)

-- ===== SEND =====
local function flashSend(text, color, duration)
	sendBtn.Text = text
	sendBtn.BackgroundColor3 = color
	sendBtn.Active = false
	task.delay(duration or 1.5, function()
		sendBtn.Text = "SEND CRATES"
		sendBtn.BackgroundColor3 = COLORS.green
		sendBtn.Active = true
	end)
end

sendBtn.MouseButton1Click:Connect(function()
	refresh()

	local sendItems = collectCrates()

	if #sendItems == 0 then
		flashSend("Gak ada crate", COLORS.red)
		return
	end

	sendBtn.Text = "Loading..."
	sendBtn.Active = false

	task.spawn(function()
		local targetId = getUserIdFromUsername(selectedUser)
		if not targetId then
			flashSend("User gak ketemu", COLORS.red)
			return
		end

		local payload = buildMultiPayload(targetId, sendItems)

		local ok = pcall(function() remote:FireServer(payload) end)

		if ok then
			flashSend(string.format("✓ %d crate", #sendItems), COLORS.green, 2)
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

closeBtn.MouseButton1Click:Connect(function()
	screenGui:Destroy()
end)

-- ===== INIT =====
refresh()

task.spawn(function()
	while screenGui.Parent do
		task.wait(2)
		refresh()
	end
end)
