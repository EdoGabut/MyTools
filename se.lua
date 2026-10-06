-- ============================================================
-- Seed Sender Minimalis v3
-- - Info item per kategori (Seeds / Sprinklers / WateringCans)
-- - Button kategori: Seeds, Sprinklers, Watering Cans
-- - Button SEND dengan auto payload
-- - Username preset: krinjguy67, andri21649, notexd777
-- ============================================================
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

-- ===== REMOTE =====
local remote = ReplicatedStorage:WaitForChild("SharedModules")
	:WaitForChild("Packet"):WaitForChild("RemoteEvent")

-- ===== CONFIG =====
local ITEMS = {
	-- ===== SEEDS =====
	{ display = "Gold",       lookup = "Gold Seed",       category = "Seeds" },
	{ display = "Mega",       lookup = "Mega Seed",       category = "Seeds" },
	{ display = "Rainbow",    lookup = "Rainbow Seed",    category = "Seeds" },
	{ display = "Briar Rose", lookup = "Briar Rose Seed", category = "Seeds" },

	-- ===== SPRINKLERS =====
	{ display = "Common Cider Sprinkler",    lookup = "Common Cider Sprinkler",    category = "Sprinklers" },
	{ display = "Uncommon Cider Sprinkler",  lookup = "Uncommon Cider Sprinkler",  category = "Sprinklers" },
	{ display = "Rare Cider Sprinkler",      lookup = "Rare Cider Sprinkler",      category = "Sprinklers" },
	{ display = "Legendary Cider Sprinkler", lookup = "Legendary Cider Sprinkler", category = "Sprinklers" },
	{ display = "Super Cider Sprinkler",     lookup = "Super Cider Sprinkler",     category = "Sprinklers" },

	-- ===== WATERING CANS =====
	{ display = "Cider Watering Can",       lookup = "Cider Watering Can",       category = "WateringCans" },
	{ display = "Super Cider Watering Can", lookup = "Super Cider Watering Can", category = "WateringCans" },
}

local CATEGORIES = {
	{ name = "Seeds",         label = "🌱 Seeds" },
	{ name = "Sprinklers",    label = "💧 Sprinklers" },
	{ name = "WateringCans",  label = "🚿 Watering" },
}

local USERNAME_PRESETS = { "krinjguy67", "andri21649", "notexd777" }

local HOTBAR_PATH   = { "BackpackGui", "Backpack", "Hotbar" }
local BACKPACK_PATH = { "BackpackGui", "Backpack", "Inventory", "ScrollingFrame", "UIGridFrame" }
local TOOL_NAME_LABEL  = "ToolName"
local TOOL_COUNT_LABEL = "ToolCount"

-- ===== USERNAME → ID =====
local idCache = {}

local function getUserIdFromUsername(username)
	username = username:gsub("^%s+", ""):gsub("%s+$", "")
	if username == "" then return nil end
	if idCache[username] then return idCache[username] end

	local ok, result = pcall(function()
		return Players:GetUserIdFromNameAsync(username)
	end)
	if ok and result then
		idCache[username] = result
		return result
	end

	local HttpService = game:GetService("HttpService")
	local ok2, response = pcall(function()
		return request({
			Url = "https://users.roblox.com/v1/usernames/users",
			Method = "POST",
			Headers = { ["Content-Type"] = "application/json" },
			Body = HttpService:JSONEncode({
				usernames = { username },
				excludeBannedUsers = false
			})
		})
	end)
	if ok2 and response and response.StatusCode == 200 then
		local ok3, data = pcall(function()
			return HttpService:JSONDecode(response.Body)
		end)
		if ok3 and data and data.data and data.data[1] then
			local uid = data.data[1].id
			idCache[username] = uid
			return uid
		end
	end
	return nil
end

-- ===== PAYLOAD BUILDERS =====
local function buildSinglePayload(targetUserId, itemName, count, category)
	local buf = buffer.create(512)
	local pos = 0
	local function writeU8(n) buffer.writeu8(buf, pos, n); pos += 1 end
	local function writeString(s)
		writeU8(0x0B); writeU8(#s)
		for i = 1, #s do writeU8(string.byte(s, i)) end
	end
	local function writeInt(n) writeU8(0x05); writeU8(n) end

	writeU8(0x8C); writeU8(0x01); writeU8(0x69)
	buffer.writef64(buf, pos, targetUserId); pos += 8
	writeU8(0x1C); writeU8(0x05); writeU8(0x01); writeU8(0x1C)

	writeString("ItemKey"); writeString(itemName)
	writeString("Count"); writeInt(count)
	writeString("Category"); writeString(category)
	writeU8(0x00); writeU8(0x00); writeU8(0x00)

	local final = buffer.create(pos)
	buffer.copy(final, 0, buf, 0, pos)
	return final
end

local function buildMultiPayload(targetUserId, items, category)
	local buf = buffer.create(2048)
	local pos = 0
	local function writeU8(n) buffer.writeu8(buf, pos, n); pos += 1 end
	local function writeString(s)
		writeU8(0x0B); writeU8(#s)
		for i = 1, #s do writeU8(string.byte(s, i)) end
	end
	local function writeInt(n) writeU8(0x05); writeU8(n) end

	writeU8(0x8C); writeU8(0x01); writeU8(0x69)
	buffer.writef64(buf, pos, targetUserId); pos += 8
	writeU8(0x1C); writeU8(0x05); writeU8(0x01); writeU8(0x1C)

	for i, item in ipairs(items) do
		writeString("ItemKey"); writeString(item.name)
		writeString("Count"); writeInt(item.count)
		writeString("Category"); writeString(category or "Seeds")
		writeU8(0x00)
		if i < #items then
			writeU8(0x05); writeU8(i + 1); writeU8(0x1C)
		end
	end
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
			local tn = slot:FindFirstChild(TOOL_NAME_LABEL, true)
			local tc = slot:FindFirstChild(TOOL_COUNT_LABEL, true)
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
	local hotbarContainer = resolveFromPlayerGui(HOTBAR_PATH)
	local backpackContainer = resolveFromPlayerGui(BACKPACK_PATH)
	local hotbarMap = scanContainer(hotbarContainer)
	local backpackMap = scanContainer(backpackContainer)

	local combined = {}
	for _, map in pairs({ hotbarMap, backpackMap }) do
		for name, count in pairs(map) do
			combined[name] = (combined[name] or 0) + count
		end
	end
	return combined
end

local function lookupCount(map, itemName)
	if map[itemName] then return map[itemName] end
	local target = itemName:lower():gsub("^%s+", ""):gsub("%s+$", "")
	for name, count in pairs(map) do
		local norm = name:lower():gsub("^%s+", ""):gsub("%s+$", "")
		if norm == target then return count end
	end
	return 0
end

-- ============================================================
-- ===== BUILD GUI =====
-- ============================================================
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "SeedSenderMini"
screenGui.ResetOnSpawn = false
screenGui.Parent = player:WaitForChild("PlayerGui")

local COLORS = {
	bg        = Color3.fromRGB(22, 22, 28),
	header    = Color3.fromRGB(16, 16, 20),
	input     = Color3.fromRGB(15, 15, 20),
	text      = Color3.fromRGB(235, 235, 240),
	textDim   = Color3.fromRGB(140, 140, 155),
	placeholder = Color3.fromRGB(110, 110, 125),
	green     = Color3.fromRGB(80, 200, 120),
	greenHv   = Color3.fromRGB(100, 220, 140),
	red       = Color3.fromRGB(200, 70, 70),
	disabled  = Color3.fromRGB(60, 60, 70),
	stroke    = Color3.fromRGB(60, 60, 72),
	preset    = Color3.fromRGB(45, 45, 55),
	presetHv  = Color3.fromRGB(60, 60, 72),
	active    = Color3.fromRGB(80, 130, 200),
	activeHv  = Color3.fromRGB(100, 150, 220),
	inactive  = Color3.fromRGB(40, 40, 50),
}

local function corner(p, r)
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r or 8); c.Parent = p
end

local FRAME_WIDTH = 260
local FRAME_HEIGHT = 260

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
title.Size = UDim2.new(1, -50, 1, 0)
title.Position = UDim2.new(0, 12, 0, 0)
title.BackgroundTransparency = 1
title.Text = "📨 Item Sender"
title.TextColor3 = COLORS.text
title.Font = Enum.Font.GothamBold
title.TextSize = 12
title.TextXAlignment = Enum.TextXAlignment.Left
title.ZIndex = 21
title.Parent = titleBar

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 22, 0, 22)
closeBtn.Position = UDim2.new(1, -28, 0, 4)
closeBtn.BackgroundColor3 = COLORS.red
closeBtn.Text = "×"
closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 14
closeBtn.BorderSizePixel = 0
closeBtn.AutoButtonColor = false
closeBtn.ZIndex = 21
closeBtn.Parent = titleBar
corner(closeBtn, 6)

-- Body
local body = Instance.new("Frame")
body.Size = UDim2.new(1, -16, 1, -38)
body.Position = UDim2.new(0, 8, 0, 34)
body.BackgroundTransparency = 1
body.Parent = frame

-- ===== USERNAME INPUT =====
local userBox = Instance.new("TextBox")
userBox.Size = UDim2.new(1, 0, 0, 32)
userBox.Position = UDim2.new(0, 0, 0, 0)
userBox.BackgroundColor3 = COLORS.input
userBox.Text = ""
userBox.PlaceholderText = "Username / ID"
userBox.TextColor3 = COLORS.text
userBox.PlaceholderColor3 = COLORS.placeholder
userBox.Font = Enum.Font.GothamMedium
userBox.TextSize = 12
userBox.TextXAlignment = Enum.TextXAlignment.Left
userBox.ClearTextOnFocus = false
userBox.BorderSizePixel = 0
userBox.Parent = body
corner(userBox, 8)
local uPad = Instance.new("UIPadding", userBox)
uPad.PaddingLeft = UDim.new(0, 10)
uPad.PaddingRight = UDim.new(0, 10)

-- ===== USERNAME PRESETS =====
local presetRow = Instance.new("Frame")
presetRow.Size = UDim2.new(1, 0, 0, 22)
presetRow.Position = UDim2.new(0, 0, 0, 36)
presetRow.BackgroundTransparency = 1
presetRow.Parent = body

local presetLayout = Instance.new("UIListLayout")
presetLayout.FillDirection = Enum.FillDirection.Horizontal
presetLayout.Padding = UDim.new(0, 4)
presetLayout.SortOrder = Enum.SortOrder.LayoutOrder
presetLayout.Parent = presetRow

for i, uname in ipairs(USERNAME_PRESETS) do
	local pBtn = Instance.new("TextButton")
	pBtn.Size = UDim2.new(0, 0, 1, 0)
	pBtn.AutomaticSize = Enum.AutomaticSize.X
	pBtn.BackgroundColor3 = COLORS.preset
	pBtn.Text = uname
	pBtn.TextColor3 = COLORS.textDim
	pBtn.Font = Enum.Font.GothamMedium
	pBtn.TextSize = 10
	pBtn.BorderSizePixel = 0
	pBtn.AutoButtonColor = false
	pBtn.LayoutOrder = i
	pBtn.Parent = presetRow
	corner(pBtn, 5)
	local pad = Instance.new("UIPadding", pBtn)
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)

	pBtn.MouseButton1Click:Connect(function()
		userBox.Text = uname
	end)
	pBtn.MouseEnter:Connect(function()
		pBtn.BackgroundColor3 = COLORS.presetHv
		pBtn.TextColor3 = COLORS.text
	end)
	pBtn.MouseLeave:Connect(function()
		pBtn.BackgroundColor3 = COLORS.preset
		pBtn.TextColor3 = COLORS.textDim
	end)
end

-- ===== CATEGORY TABS =====
local catRow = Instance.new("Frame")
catRow.Size = UDim2.new(1, 0, 0, 26)
catRow.Position = UDim2.new(0, 0, 0, 62)
catRow.BackgroundTransparency = 1
catRow.Parent = body

local catLayout = Instance.new("UIListLayout")
catLayout.FillDirection = Enum.FillDirection.Horizontal
catLayout.Padding = UDim.new(0, 4)
catLayout.SortOrder = Enum.SortOrder.LayoutOrder
catLayout.Parent = catRow

local currentCategory = "Seeds"
local catButtons = {}

for i, cat in ipairs(CATEGORIES) do
	local cBtn = Instance.new("TextButton")
	cBtn.Size = UDim2.new(0, 0, 1, 0)
	cBtn.AutomaticSize = Enum.AutomaticSize.X
	cBtn.BackgroundColor3 = (cat.name == currentCategory) and COLORS.active or COLORS.inactive
	cBtn.Text = cat.label
	cBtn.TextColor3 = COLORS.text
	cBtn.Font = Enum.Font.GothamBold
	cBtn.TextSize = 10
	cBtn.BorderSizePixel = 0
	cBtn.AutoButtonColor = false
	cBtn.LayoutOrder = i
	cBtn.Parent = catRow
	corner(cBtn, 6)
	local pad = Instance.new("UIPadding", cBtn)
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)

	catButtons[cat.name] = cBtn

	cBtn.MouseButton1Click:Connect(function()
		currentCategory = cat.name
		for name, btn in pairs(catButtons) do
			if name == currentCategory then
				btn.BackgroundColor3 = COLORS.active
			else
				btn.BackgroundColor3 = COLORS.inactive
			end
		end
		refreshStatus()
	end)
end

-- ===== INFO LABEL =====
local infoLbl = Instance.new("TextLabel")
infoLbl.Size = UDim2.new(1, 0, 0, 26)
infoLbl.Position = UDim2.new(0, 0, 0, 92)
infoLbl.BackgroundColor3 = COLORS.header
infoLbl.BorderSizePixel = 0
infoLbl.Text = "🌱 Memuat..."
infoLbl.TextColor3 = COLORS.textDim
infoLbl.Font = Enum.Font.Code
infoLbl.TextSize = 10
infoLbl.TextXAlignment = Enum.TextXAlignment.Left
infoLbl.TextTruncate = Enum.TextTruncate.AtEnd
infoLbl.Parent = body
corner(infoLbl, 6)
local iPad = Instance.new("UIPadding", infoLbl)
iPad.PaddingLeft = UDim.new(0, 8)
iPad.PaddingRight = UDim.new(0, 8)

-- ===== ITEM LIST (SCROLL) =====
local listFrame = Instance.new("ScrollingFrame")
listFrame.Size = UDim2.new(1, 0, 0, 60)
listFrame.Position = UDim2.new(0, 0, 0, 122)
listFrame.BackgroundColor3 = COLORS.header
listFrame.BorderSizePixel = 0
listFrame.ScrollBarThickness = 3
listFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
listFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
listFrame.Parent = body
corner(listFrame, 6)
local lPad = Instance.new("UIPadding", listFrame)
lPad.PaddingLeft = UDim.new(0, 4)
lPad.PaddingRight = UDim.new(0, 4)
lPad.PaddingTop = UDim.new(0, 4)
lPad.PaddingBottom = UDim.new(0, 4)

local listLayout = Instance.new("UIListLayout")
listLayout.FillDirection = Enum.FillDirection.Vertical
listLayout.Padding = UDim.new(0, 2)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Parent = listFrame

-- ===== SEND BUTTON =====
local sendBtn = Instance.new("TextButton")
sendBtn.Size = UDim2.new(1, 0, 0, 36)
sendBtn.Position = UDim2.new(0, 0, 1, -36)
sendBtn.BackgroundColor3 = COLORS.green
sendBtn.Text = "SEND"
sendBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
sendBtn.Font = Enum.Font.GothamBold
sendBtn.TextSize = 13
sendBtn.BorderSizePixel = 0
sendBtn.AutoButtonColor = false
sendBtn.Parent = body
corner(sendBtn, 8)

-- ===== STATE =====
local currentCounts = {} -- [display] = count

local function getItemsByCategory(cat)
	local list = {}
	for _, item in ipairs(ITEMS) do
		if item.category == cat then
			table.insert(list, item)
		end
	end
	return list
end

local function refreshStatus()
	local combined = scanAll()
	local items = getItemsByCategory(currentCategory)
	local parts = {}
	local totalJenis = 0

	-- update list display
	for _, child in ipairs(listFrame:GetChildren()) do
		if child:IsA("TextLabel") then
			child:Destroy()
		end
	end

	for i, item in ipairs(items) do
		local count = lookupCount(combined, item.lookup)
		currentCounts[item.display] = count
		if count > 0 then
			totalJenis += 1
			table.insert(parts, string.format("%s x%d", item.display, count))
		end

		local row = Instance.new("TextLabel")
		row.Size = UDim2.new(1, 0, 0, 16)
		row.BackgroundTransparency = 1
		row.Text = string.format("  %s  ×%d", item.display, count)
		row.TextColor3 = (count > 0) and COLORS.green or COLORS.disabled
		row.Font = Enum.Font.Code
		row.TextSize = 10
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.LayoutOrder = i
		row.Parent = listFrame
	end

	if totalJenis == 0 then
		infoLbl.Text = "🌱 Tidak ada item di kategori ini"
		infoLbl.TextColor3 = COLORS.disabled
	else
		infoLbl.Text = "🌱 " .. table.concat(parts, " · ")
		infoLbl.TextColor3 = COLORS.green
	end
end

-- ===== SEND ACTION =====
local function flashSend(text, color, duration)
	sendBtn.Text = text
	sendBtn.BackgroundColor3 = color
	sendBtn.Active = false
	task.delay(duration or 1.5, function()
		sendBtn.Text = "SEND"
		sendBtn.BackgroundColor3 = COLORS.green
		sendBtn.Active = true
	end)
end

sendBtn.MouseButton1Click:Connect(function()
	refreshStatus()

	local sendItems = {}
	local items = getItemsByCategory(currentCategory)
	for _, item in ipairs(items) do
		local count = currentCounts[item.display] or 0
		if count > 0 then
			table.insert(sendItems, {
				name = item.lookup,
				count = math.min(count, 255),
			})
		end
	end

	if #sendItems == 0 then
		flashSend("❌ Gak ada item", COLORS.red)
		return
	end

	local username = userBox.Text:gsub("%s", "")
	if username == "" then
		flashSend("❌ Isi username", COLORS.red)
		return
	end

	sendBtn.Text = "⏳ Loading..."
	sendBtn.Active = false

	task.spawn(function()
		local targetId = getUserIdFromUsername(username)
		if not targetId then
			flashSend("❌ User gak ketemu", COLORS.red)
			return
		end

		local payload
		if #sendItems == 1 then
			payload = buildSinglePayload(targetId, sendItems[1].name, sendItems[1].count, currentCategory)
		else
			payload = buildMultiPayload(targetId, sendItems, currentCategory)
		end

		if not payload then
			flashSend("❌ Payload fail", COLORS.red)
			return
		end

		sendBtn.Text = string.format("⏳ Send %d...", #sendItems)

		local ok = pcall(function()
			remote:FireServer(payload)
		end)

		if ok then
			flashSend(string.format("✅ %d jenis", #sendItems), COLORS.green, 2)
			task.wait(1.5)
			refreshStatus()
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

-- ===== CLOSE =====
closeBtn.MouseButton1Click:Connect(function()
	screenGui:Destroy()
end)

-- ===== INIT =====
refreshStatus()

task.spawn(function()
	while screenGui.Parent do
		refreshStatus()
		task.wait(2)
	end
end)
