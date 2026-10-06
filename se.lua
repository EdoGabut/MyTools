-- ============================================================
-- Item Sender v10
-- - Pilih kategori (dropdown)
-- - Tanpa log
-- - Payload: header 0x05 0x42 0x1C (fixed opcode)
-- ============================================================
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")

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

	-- ===== TROWELS =====
	{ display = "Trowel",                   lookup = "Trowel",                   category = "Trowels" },
}

-- Urutan kategori di dropdown (harus match dengan category di ITEMS)
local CATEGORIES = { "Seeds", "Sprinklers", "WateringCans", "Trowels" }
local CATEGORY_LABEL = {
	Seeds        = "🌱 Seeds",
	Sprinklers   = "💧 Sprinklers",
	WateringCans = "🚿 Watering Cans",
	Trowels      = "🛠 Trowels",
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

-- ===== PAYLOAD BUILDER =====
local OPCODE = 0x42

local function buildPayload(targetUserId, items)
	local buf = buffer.create(2048)
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
	writeU8(0x05); writeU8(OPCODE); writeU8(0x1C)

	-- Entries
	for i, item in ipairs(items) do
		writeU8(0x05); writeU8(i); writeU8(0x1C)
		writeString("ItemKey");  writeString(item.name)
		writeString("Count");    writeInt(item.count)
		writeString("Category"); writeString(item.category or "Seeds")
		writeU8(0x00)
	end

	-- Penutup array
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
	local hotbarMap = scanContainer(resolveFromPlayerGui(HOTBAR_PATH))
	local backpackMap = scanContainer(resolveFromPlayerGui(BACKPACK_PATH))
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
-- GUI
-- ============================================================
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ItemSenderMini"
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
	yellow    = Color3.fromRGB(230, 190, 120),
	active    = Color3.fromRGB(60, 130, 200),
}

local function corner(p, r)
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r or 8); c.Parent = p
end

local FRAME_WIDTH = 260
local FRAME_HEIGHT = 320

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
local function bindDrag(handle)
	handle.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = input.Position
			startPos = frame.Position
		end
	end)
	handle.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
end
bindDrag(frame)
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
title.Size = UDim2.new(1, -80, 1, 0)
title.Position = UDim2.new(0, 12, 0, 0)
title.BackgroundTransparency = 1
title.Text = "📨 Item Sender"
title.TextColor3 = COLORS.text
title.Font = Enum.Font.GothamBold
title.TextSize = 12
title.TextXAlignment = Enum.TextXAlignment.Left
title.ZIndex = 21
title.Parent = titleBar

local function makeTitleBtn(xOffset, bg, txt)
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(0, 22, 0, 22)
	b.Position = UDim2.new(1, xOffset, 0, 4)
	b.BackgroundColor3 = bg
	b.Text = txt
	b.TextColor3 = Color3.fromRGB(255, 255, 255)
	b.Font = Enum.Font.GothamBold
	b.TextSize = 14
	b.BorderSizePixel = 0
	b.AutoButtonColor = false
	b.ZIndex = 21
	b.Parent = titleBar
	corner(b, 6)
	return b
end

local minimizeBtn = makeTitleBtn(-54, COLORS.preset, "—")
local closeBtn    = makeTitleBtn(-28, COLORS.red,    "×")

-- Body
local body = Instance.new("Frame")
body.Size = UDim2.new(1, -16, 1, -38)
body.Position = UDim2.new(0, 8, 0, 34)
body.BackgroundTransparency = 1
body.Parent = frame

-- Username input
local userBox = Instance.new("TextBox")
userBox.Size = UDim2.new(1, 0, 0, 32)
userBox.Position = UDim2.new(0, 0, 0, 0)
userBox.BackgroundColor3 = COLORS.input
userBox.Text = ""
userBox.PlaceholderText = "Username / ID (target)"
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

-- Preset row
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

	pBtn.MouseButton1Click:Connect(function() userBox.Text = uname end)
	pBtn.MouseEnter:Connect(function()
		pBtn.BackgroundColor3 = COLORS.presetHv
		pBtn.TextColor3 = COLORS.text
	end)
	pBtn.MouseLeave:Connect(function()
		pBtn.BackgroundColor3 = COLORS.preset
		pBtn.TextColor3 = COLORS.textDim
	end)
end

-- ===== KATEGORI DROPDOWN =====
local catLabel = Instance.new("TextLabel")
catLabel.Size = UDim2.new(1, 0, 0, 14)
catLabel.Position = UDim2.new(0, 0, 0, 62)
catLabel.BackgroundTransparency = 1
catLabel.Text = "📂 Kategori:"
catLabel.TextColor3 = COLORS.textDim
catLabel.Font = Enum.Font.GothamMedium
catLabel.TextSize = 10
catLabel.TextXAlignment = Enum.TextXAlignment.Left
catLabel.Parent = body

local catBtn = Instance.new("TextButton")
catBtn.Size = UDim2.new(1, 0, 0, 28)
catBtn.Position = UDim2.new(0, 0, 0, 78)
catBtn.BackgroundColor3 = COLORS.input
catBtn.Text = "🌱 Seeds  ▾"
catBtn.TextColor3 = COLORS.text
catBtn.Font = Enum.Font.GothamMedium
catBtn.TextSize = 11
catBtn.TextXAlignment = Enum.TextXAlignment.Left
catBtn.BorderSizePixel = 0
catBtn.AutoButtonColor = false
catBtn.Parent = body
corner(catBtn, 6)
local catPad = Instance.new("UIPadding", catBtn)
catPad.PaddingLeft = UDim.new(0, 10)
catPad.PaddingRight = UDim.new(0, 10)

-- Dropdown list (muncul saat diklik)
local catList = Instance.new("Frame")
catList.Size = UDim2.new(1, 0, 0, 0)
catList.Position = UDim2.new(0, 0, 0, 108)
catList.BackgroundColor3 = COLORS.header
catList.BorderSizePixel = 0
catList.Visible = false
catList.ZIndex = 50
catList.Parent = body
corner(catList, 6)

local catListLayout = Instance.new("UIListLayout")
catListLayout.FillDirection = Enum.FillDirection.Vertical
catListLayout.Padding = UDim.new(0, 2)
catListLayout.SortOrder = Enum.SortOrder.LayoutOrder
catListLayout.Parent = catList

local catListPad = Instance.new("UIPadding", catList)
catListPad.PaddingLeft = UDim.new(0, 4)
catListPad.PaddingRight = UDim.new(0, 4)
catListPad.PaddingTop = UDim.new(0, 4)
catListPad.PaddingBottom = UDim.new(0, 4)

-- State
local selectedCategory = "Seeds"
local dropdownOpen = false

-- Item rows per kategori (dibuat nanti, di-update saat kategori berubah)
local infoScroll -- deklarasikan dulu

-- ===== INFO ITEM =====
local infoFrame = Instance.new("Frame")
infoFrame.Size = UDim2.new(1, 0, 0, 130)
infoFrame.Position = UDim2.new(0, 0, 0, 112)
infoFrame.BackgroundColor3 = COLORS.header
infoFrame.BorderSizePixel = 0
infoFrame.Parent = body
corner(infoFrame, 6)

local iPad = Instance.new("UIPadding", infoFrame)
iPad.PaddingLeft = UDim.new(0, 8)
iPad.PaddingRight = UDim.new(0, 8)
iPad.PaddingTop = UDim.new(0, 4)
iPad.PaddingBottom = UDim.new(0, 4)

local infoHeader = Instance.new("TextLabel")
infoHeader.Size = UDim2.new(1, 0, 0, 14)
infoHeader.BackgroundTransparency = 1
infoHeader.Text = "📦 Siap dikirim:"
infoHeader.TextColor3 = COLORS.textDim
infoHeader.Font = Enum.Font.Code
infoHeader.TextSize = 10
infoHeader.TextXAlignment = Enum.TextXAlignment.Left
infoHeader.Parent = infoFrame

infoScroll = Instance.new("ScrollingFrame")
infoScroll.Size = UDim2.new(1, 0, 1, -16)
infoScroll.Position = UDim2.new(0, 0, 0, 16)
infoScroll.BackgroundTransparency = 1
infoScroll.BorderSizePixel = 0
infoScroll.ScrollBarThickness = 3
infoScroll.ScrollBarImageColor3 = COLORS.presetHv
infoScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
infoScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
infoScroll.ScrollingDirection = Enum.ScrollingDirection.Y
infoScroll.Parent = infoFrame

local infoLayout = Instance.new("UIListLayout")
infoLayout.FillDirection = Enum.FillDirection.Vertical
infoLayout.SortOrder = Enum.SortOrder.LayoutOrder
infoLayout.Padding = UDim.new(0, 2)
infoLayout.Parent = infoScroll

-- Send button
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

-- ============================================================
-- STATE
-- ============================================================
local currentCounts = {}   -- [display] = count
local infoRows = {}        -- [display] = TextLabel
local activeCategory = "Seeds"

-- Buat row untuk semua item (di-hide/show sesuai kategori)
for i, item in ipairs(ITEMS) do
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1, 0, 0, 14)
	lbl.BackgroundTransparency = 1
	lbl.Text = "  • " .. item.display .. " x0"
	lbl.TextColor3 = COLORS.disabled
	lbl.Font = Enum.Font.Code
	lbl.TextSize = 10
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.TextYAlignment = Enum.TextYAlignment.Top
	lbl.TextWrapped = true
	lbl.LayoutOrder = i
	lbl.Visible = false
	lbl.Parent = infoScroll
	infoRows[item.display] = lbl
end

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
	local totalJenis = 0

	-- Update semua count dulu
	for _, item in ipairs(ITEMS) do
		currentCounts[item.display] = lookupCount(combined, item.lookup)
	end

	-- Tampilkan hanya item dari kategori aktif
	for _, item in ipairs(ITEMS) do
		local row = infoRows[item.display]
		if row then
			if item.category == activeCategory then
				local count = currentCounts[item.display] or 0
				if count > 0 then
					row.Visible = true
					row.Text = string.format("  • %s x%d", item.display, count)
					row.TextColor3 = COLORS.green
					totalJenis += 1
				else
					row.Visible = true
					row.Text = string.format("  • %s x0", item.display)
					row.TextColor3 = COLORS.disabled
				end
			else
				row.Visible = false
			end
		end
	end

	if totalJenis == 0 then
		infoHeader.Text = string.format("📦 %s: (kosong)", CATEGORY_LABEL[activeCategory] or activeCategory)
		infoHeader.TextColor3 = COLORS.disabled
	else
		infoHeader.Text = string.format("📦 %s: %d jenis", CATEGORY_LABEL[activeCategory] or activeCategory, totalJenis)
		infoHeader.TextColor3 = COLORS.textDim
	end
end

-- ============================================================
-- DROPDOWN LOGIC
-- ============================================================
local function closeDropdown()
	dropdownOpen = false
	catList.Visible = false
end

local function openDropdown()
	dropdownOpen = true
	catList.Visible = true
	-- Update tinggi list sesuai jumlah kategori
	local h = #CATEGORIES * 26 + 8
	catList.Size = UDim2.new(1, 0, 0, h)
end

-- Buat tombol per kategori di dropdown
for i, cat in ipairs(CATEGORIES) do
	local optBtn = Instance.new("TextButton")
	optBtn.Size = UDim2.new(1, 0, 0, 24)
	optBtn.BackgroundColor3 = COLORS.preset
	optBtn.Text = CATEGORY_LABEL[cat] or cat
	optBtn.TextColor3 = COLORS.text
	optBtn.Font = Enum.Font.GothamMedium
	optBtn.TextSize = 11
	optBtn.TextXAlignment = Enum.TextXAlignment.Left
	optBtn.BorderSizePixel = 0
	optBtn.AutoButtonColor = false
	optBtn.LayoutOrder = i
	optBtn.ZIndex = 51
	optBtn.Parent = catList
	corner(optBtn, 4)
	local pad = Instance.new("UIPadding", optBtn)
	pad.PaddingLeft = UDim.new(0, 10)
	pad.PaddingRight = UDim.new(0, 10)

	optBtn.MouseButton1Click:Connect(function()
		activeCategory = cat
		catBtn.Text = (CATEGORY_LABEL[cat] or cat) .. "  ▾"
		closeDropdown()
		refreshStatus()
	end)
	optBtn.MouseEnter:Connect(function()
		optBtn.BackgroundColor3 = COLORS.presetHv
	end)
	optBtn.MouseLeave:Connect(function()
		optBtn.BackgroundColor3 = COLORS.preset
	end)
end

catBtn.MouseButton1Click:Connect(function()
	if dropdownOpen then
		closeDropdown()
	else
		openDropdown()
	end
end)
catBtn.MouseEnter:Connect(function()
	catBtn.BackgroundColor3 = COLORS.presetHv
end)
catBtn.MouseLeave:Connect(function()
	catBtn.BackgroundColor3 = COLORS.input
end)

-- ============================================================
-- SEND LOGIC
-- ============================================================
local function flashSend(text, color, duration)
	sendBtn.Text = text
	sendBtn.BackgroundColor3 = color
	task.delay(duration or 1.5, function()
		sendBtn.Text = "SEND"
		sendBtn.BackgroundColor3 = COLORS.green
	end)
end

local function collectSendItems()
	local items = {}
	for _, item in ipairs(ITEMS) do
		if item.category == activeCategory then
			local count = currentCounts[item.display] or 0
			if count > 0 then
				table.insert(items, {
					name = item.lookup,
					count = math.min(count, 255),
					category = item.category,
				})
			end
		end
	end
	return items
end

local function doSend(username)
	if username == "" then
		return false, "username kosong"
	end

	local items = collectSendItems()
	if #items == 0 then
		return false, "gak ada item di " .. activeCategory
	end

	local targetId = getUserIdFromUsername(username)
	if not targetId then
		return false, "user gak ketemu"
	end

	local payload = buildPayload(targetId, items)
	if not payload then
		return false, "payload fail"
	end

	local ok = pcall(function()
		remote:FireServer(payload)
	end)

	if not ok then
		return false, "fire fail"
	end

	return true, string.format("%d item", #items)
end

-- ============================================================
-- MANUAL SEND
-- ============================================================
sendBtn.MouseButton1Click:Connect(function()
	refreshStatus()

	local username = userBox.Text:gsub("%s", "")
	if username == "" then
		flashSend("❌ Isi username", COLORS.red)
		return
	end

	sendBtn.Text = "⏳ Sending..."
	sendBtn.BackgroundColor3 = COLORS.yellow

	task.spawn(function()
		local ok, msg = doSend(username)
		if ok then
			flashSend("✅ " .. msg, COLORS.green, 2)
		else
			flashSend("❌ " .. msg, COLORS.red, 2)
		end
		task.wait(1.5)
		refreshStatus()
	end)
end)

sendBtn.MouseEnter:Connect(function()
	if sendBtn.BackgroundColor3 == COLORS.green then
		TweenService:Create(sendBtn, TweenInfo.new(0.1), { BackgroundColor3 = COLORS.greenHv }):Play()
	end
end)
sendBtn.MouseLeave:Connect(function()
	if sendBtn.BackgroundColor3 == COLORS.greenHv then
		TweenService:Create(sendBtn, TweenInfo.new(0.1), { BackgroundColor3 = COLORS.green }):Play()
	end
end)

-- ============================================================
-- REFRESH LOOP
-- ============================================================
task.spawn(function()
	while screenGui.Parent do
		refreshStatus()
		task.wait(2)
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
			Size = UDim2.new(0, FRAME_WIDTH, 0, 30)
		}):Play()
		body.Visible = false
		title.Text = "📨 Item Sender (—)"
	else
		TweenService:Create(frame, TweenInfo.new(0.2), {
			Size = UDim2.new(0, FRAME_WIDTH, 0, savedSize)
		}):Play()
		body.Visible = true
		title.Text = "📨 Item Sender"
	end
end)

closeBtn.MouseButton1Click:Connect(function()
	screenGui:Destroy()
end)

-- ============================================================
-- INIT
-- ============================================================
refreshStatus()
