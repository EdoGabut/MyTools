-- ============================================================
-- Item Sender Minimalis v8 (BATCH ALL)
-- - 1 payload untuk semua kategori
-- - Category per-item di dalam payload
-- - 1 log label ringkasan
-- - Username via preset
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
	-- SEEDS
	{ display = "Spirethorn",    name = "Spirethorn",    lookup = "Spirethorn Seed",    category = "Seeds" },
	{ display = "Briar Rose",    name = "Briar Rose",    lookup = "Briar Rose Seed",    category = "Seeds" },
	{ display = "Gold",          name = "Gold",          lookup = "Gold Seed",          category = "Seeds" },
	{ display = "Mega",          name = "Mega",          lookup = "Mega Seed",          category = "Seeds" },
	{ display = "Rainbow",       name = "Rainbow",       lookup = "Rainbow Seed",       category = "Seeds" },
	{ display = "Great Pumpkin", name = "Great Pumpkin", lookup = "Great Pumpkin Seed", category = "Seeds" },
	{ display = "Vampire Bloom", name = "Vampire Bloom", lookup = "Vampire Bloom Seed", category = "Seeds" },
	-- SPRINKLERS
	{ display = "Common Cider Sprinkler",    name = "Common Cider Sprinkler",    lookup = "Common Cider Sprinkler",    category = "Sprinklers" },
	{ display = "Uncommon Cider Sprinkler",  name = "Uncommon Cider Sprinkler",  lookup = "Uncommon Cider Sprinkler",  category = "Sprinklers" },
	{ display = "Rare Cider Sprinkler",      name = "Rare Cider Sprinkler",      lookup = "Rare Cider Sprinkler",      category = "Sprinklers" },
	{ display = "Legendary Cider Sprinkler", name = "Legendary Cider Sprinkler", lookup = "Legendary Cider Sprinkler", category = "Sprinklers" },
	{ display = "Super Cider Sprinkler",     name = "Super Cider Sprinkler",     lookup = "Super Cider Sprinkler",     category = "Sprinklers" },
	-- WATERING CANS
	{ display = "Cider Watering Can",       name = "Cider Watering Can",       lookup = "Cider Watering Can",       category = "WateringCans" },
	{ display = "Super Cider Watering Can", name = "Super Cider Watering Can", lookup = "Super Cider Watering Can", category = "WateringCans" },
}

local CATEGORIES = {
	{ name = "Seeds",        label = "🌱" },
	{ name = "Sprinklers",   label = "💧" },
	{ name = "WateringCans", label = "🚿" },
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

-- ===== PAYLOAD BUILDERS =====
-- Multi payload: tiap item punya `category` sendiri (bisa campur kategori)
local function buildMultiPayload(targetUserId, items)
	local buf = buffer.create(4096)
	local pos = 0
	local function writeU8(n) buffer.writeu8(buf, pos, n); pos += 1 end
	local function writeString(s)
		writeU8(0x0B); writeU8(#s)
		for i = 1, #s do writeU8(string.byte(s, i)) end
	end
	local function writeInt(n) writeU8(0x05); writeU8(n) end

	-- Header
	writeU8(0x8C); writeU8(0x01); writeU8(0x69)  -- header umum
	buffer.writef64(buf, pos, targetUserId); pos += 8
	writeU8(0x1C); writeU8(0x05); writeU8(0x01); writeU8(0x1C)

	-- Items (masing-masing punya Category sendiri)
	for i, item in ipairs(items) do
		writeString("ItemKey"); writeString(item.name)
		writeString("Count"); writeInt(item.count)
		writeString("Category"); writeString(item.category)
		writeU8(0x00)
		if i < #items then
			writeU8(0x05); writeU8(i + 1); writeU8(0x1C)  -- index berikutnya
		end
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
-- ===== BUILD GUI (COMPACT) =====
-- ============================================================
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ItemSenderMini"
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
	active   = Color3.fromRGB(80, 130, 200),
	inactive = Color3.fromRGB(40, 40, 50),
	preset   = Color3.fromRGB(45, 45, 55),
	presetHv = Color3.fromRGB(60, 60, 72),
}

local function corner(p, r)
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r or 8); c.Parent = p
end

local frame = Instance.new("Frame")
frame.Size = UDim2.new(0, 220, 0, 170)
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
title.Text = "📨 Sender"
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

-- CATEGORY TABS (cuma buat filter log, bukan filter kirim)
local catRow = Instance.new("Frame")
catRow.Size = UDim2.new(1, 0, 0, 24)
catRow.BackgroundTransparency = 1
catRow.Parent = body

local catLayout = Instance.new("UIListLayout")
catLayout.FillDirection = Enum.FillDirection.Horizontal
catLayout.Padding = UDim.new(0, 4)
catLayout.SortOrder = Enum.SortOrder.LayoutOrder
catLayout.Parent = catRow

local currentCategory = CATEGORIES[1].name
local catButtons = {}

-- LOG LABEL
local logLbl = Instance.new("TextLabel")
logLbl.Size = UDim2.new(1, 0, 0, 40)
logLbl.Position = UDim2.new(0, 0, 0, 30)
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

-- SEND BUTTON
local sendBtn = Instance.new("TextButton")
sendBtn.Size = UDim2.new(1, 0, 0, 32)
sendBtn.Position = UDim2.new(0, 0, 1, -32)
sendBtn.BackgroundColor3 = COLORS.green
sendBtn.Text = "SEND ALL"
sendBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
sendBtn.Font = Enum.Font.GothamBold
sendBtn.TextSize = 12
sendBtn.BorderSizePixel = 0
sendBtn.AutoButtonColor = false
sendBtn.Parent = body
corner(sendBtn, 8)

-- ============================================================
-- ===== STATE & LOGIC =====
-- ============================================================
local cachedScan = {}
local currentCounts = {}  -- [display] = count (semua kategori)
local selectedUser = USERNAME_PRESETS[1]

-- Ambil SEMUA item (semua kategori) yang count > 0
local function collectAllSendItems()
	local list = {}
	for _, item in ipairs(ITEMS) do
		local count = currentCounts[item.display] or 0
		if count > 0 then
			table.insert(list, {
				name = item.name,
				count = math.min(count, 255),
				category = item.category,  -- per-item category
				display = item.display,
			})
		end
	end
	return list
end

-- Ringkasan log
local function buildSummary()
	for _, item in ipairs(ITEMS) do
		currentCounts[item.display] = lookupCount(cachedScan, item.lookup)
	end

	local seedTotal, sprinkTotal, canTotal = 0, 0, 0
	for _, item in ipairs(ITEMS) do
		local c = currentCounts[item.display] or 0
		if c > 0 then
			if item.category == "Seeds" then seedTotal += c
			elseif item.category == "Sprinklers" then sprinkTotal += c
			elseif item.category == "WateringCans" then canTotal += c end
		end
	end

	return string.format(
		"🌱 %d  💧 %d  🚿 %d\nTotal items: %d",
		seedTotal, sprinkTotal, canTotal, seedTotal + sprinkTotal + canTotal
	)
end

local function render()
	logLbl.Text = buildSummary()
	logLbl.TextColor3 = COLORS.green
end

local function refresh()
	cachedScan = scanAll()
	render()
end

-- Buat tombol kategori (cuma visual, tidak filter kirim)
for i, cat in ipairs(CATEGORIES) do
	local cBtn = Instance.new("TextButton")
	cBtn.Size = UDim2.new(0, 0, 1, 0)
	cBtn.AutomaticSize = Enum.AutomaticSize.X
	cBtn.BackgroundColor3 = (cat.name == currentCategory) and COLORS.active or COLORS.inactive
	cBtn.Text = cat.label
	cBtn.TextColor3 = COLORS.text
	cBtn.Font = Enum.Font.GothamBold
	cBtn.TextSize = 12
	cBtn.BorderSizePixel = 0
	cBtn.AutoButtonColor = false
	cBtn.LayoutOrder = i
	cBtn.Parent = catRow
	corner(cBtn, 6)
	local pad = Instance.new("UIPadding", cBtn)
	pad.PaddingLeft = UDim.new(0, 14)
	pad.PaddingRight = UDim.new(0, 14)

	catButtons[cat.name] = cBtn

	cBtn.MouseButton1Click:Connect(function()
		if currentCategory == cat.name then return end
		currentCategory = cat.name
		for name, btn in pairs(catButtons) do
			btn.BackgroundColor3 = (name == currentCategory) and COLORS.active or COLORS.inactive
		end
		-- cuma visual, tidak mempengaruhi SEND
	end)
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
presetBtn.MouseEnter:Connect(function()
	presetBtn.BackgroundColor3 = COLORS.presetHv
	presetBtn.TextColor3 = COLORS.text
end)
presetBtn.MouseLeave:Connect(function()
	presetBtn.BackgroundColor3 = COLORS.preset
	presetBtn.TextColor3 = COLORS.textDim
end)

-- ===== SEND ACTION (BATCH ALL) =====
local function flashSend(text, color, duration)
	sendBtn.Text = text
	sendBtn.BackgroundColor3 = color
	sendBtn.Active = false
	task.delay(duration or 1.5, function()
		sendBtn.Text = "SEND ALL"
		sendBtn.BackgroundColor3 = COLORS.green
		sendBtn.Active = true
	end)
end

sendBtn.MouseButton1Click:Connect(function()
	refresh()

	-- Ambil SEMUA item dari SEMUA kategori
	local sendItems = collectAllSendItems()

	if #sendItems == 0 then
		flashSend("Gak ada item", COLORS.red)
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

		-- 1 payload untuk semua kategori
		local payload = buildMultiPayload(targetId, sendItems)

		local ok = pcall(function() remote:FireServer(payload) end)

		if ok then
			flashSend(string.format("✓ %d item", #sendItems), COLORS.green, 2)
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
