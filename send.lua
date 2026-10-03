-- ============================================================
-- Seed Sender GUI (Multi-Select)
-- - Klik 1 seed → payload 1 item
-- - Klik 2-5 seed → payload multi-item
-- - Tombol Kill Character di header
-- - Username preset: krinjguy67, andri21649, notexd777
-- ============================================================
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer

-- ===== REMOTE =====
local remote = ReplicatedStorage:WaitForChild("SharedModules")
	:WaitForChild("Packet"):WaitForChild("RemoteEvent")

-- ===== SEED CONFIG =====
local SEEDS = {
	{ display = "Gold",        lookup = "Gold Seed" },
	{ display = "Mega",        lookup = "Mega Seed" },
	{ display = "Rainbow",     lookup = "Rainbow Seed" },
	{ display = "Briar Rose",  lookup = "Briar Rose Seed" },
	{ display = "Spirethorn", lookup = "Spirethorn Seed" },
}

-- ===== USERNAME PRESETS =====
local USERNAME_PRESETS = {
	"krinjguy67",
	"andri21649",
	"notexd777",
}

-- ===== USERNAME → ID =====
local idCache = {}

local function getUserIdFromUsername(username)
	username = username:gsub("^%s+", ""):gsub("%s+$", "")
	if username == "" then return nil end

	if idCache[username] then
		return idCache[username]
	end

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

-- ===== BUILDER PAYLOAD (1 item) =====
local function buildSinglePayload(targetUserId, itemName, count, category)
	local nameLen = #itemName
	local catLen = #category
	if nameLen > 255 or catLen > 255 then return nil end
	if count < 0 or count > 255 then return nil end

	local buf = buffer.create(512)
	local pos = 0

	buffer.writeu8(buf, pos, 0x8C); pos += 1
	buffer.writeu8(buf, pos, 0x01); pos += 1
	buffer.writeu8(buf, pos, 0x69); pos += 1
	buffer.writef64(buf, pos, targetUserId); pos += 8

	buffer.writeu8(buf, pos, 0x1C); pos += 1
	buffer.writeu8(buf, pos, 0x05); pos += 1
	buffer.writeu8(buf, pos, 0x01); pos += 1
	buffer.writeu8(buf, pos, 0x1C); pos += 1

	local function writeString(s)
		local len = #s
		buffer.writeu8(buf, pos, 0x0B); pos += 1
		buffer.writeu8(buf, pos, len); pos += 1
		for i = 1, len do
			buffer.writeu8(buf, pos, string.byte(s, i)); pos += 1
		end
	end

	local function writeInt(n)
		buffer.writeu8(buf, pos, 0x05); pos += 1
		buffer.writeu8(buf, pos, n); pos += 1
	end

	writeString("ItemKey")
	writeString(itemName)
	writeString("Count")
	writeInt(count)
	writeString("Category")
	writeString(category)

	buffer.writeu8(buf, pos, 0x00); pos += 1
	buffer.writeu8(buf, pos, 0x00); pos += 1
	buffer.writeu8(buf, pos, 0x00); pos += 1

	local final = buffer.create(pos)
	buffer.copy(final, 0, buf, 0, pos)
	return final
end

-- ===== BUILDER PAYLOAD (multi item) =====
local function buildMultiPayload(targetUserId, items, category)
	-- items = { { name = "...", count = N }, ... }
	if #items == 0 then return nil end

	local buf = buffer.create(2048)
	local pos = 0

	local function writeU8(n)
		buffer.writeu8(buf, pos, n); pos += 1
	end

	local function writeString(s)
		writeU8(0x0B)
		writeU8(#s)
		for i = 1, #s do
			writeU8(string.byte(s, i))
		end
	end

	local function writeInt(n)
		writeU8(0x05)
		writeU8(n)
	end

	-- Header
	writeU8(0x8C)
	writeU8(0x01)
	writeU8(0x69)
	buffer.writef64(buf, pos, targetUserId); pos += 8

	-- Metadata
	writeU8(0x1C)
	writeU8(0x05)
	writeU8(0x01)
	writeU8(0x1C)

	-- Loop items
	for i, item in ipairs(items) do
		writeString("ItemKey")
		writeString(item.name)
		writeString("Count")
		writeInt(item.count)
		writeString("Category")
		writeString(category or "Seeds")

		writeU8(0x00)
		if i < #items then
			writeU8(0x05)
			writeU8(i + 1)
			writeU8(0x1C)
		end
	end

	-- Terminator
	writeU8(0x00)
	writeU8(0x00)
	writeU8(0x00)

	local final = buffer.create(pos)
	buffer.copy(final, 0, buf, 0, pos)
	return final
end

-- ===== BACKPACK SCANNER =====
local GRID_PATH_PARTS = {
	"BackpackGui", "Backpack", "Inventory",
	"ScrollingFrame", "UIGridFrame"
}

local function getBackpackGrid()
	local node = player:FindFirstChild("PlayerGui")
	if not node then return nil end
	for _, name in ipairs(GRID_PATH_PARTS) do
		node = node:FindFirstChild(name)
		if not node then return nil end
	end
	return node
end

local function parseCount(text)
	if not text or text == "" then return 0 end
	local num = text:match("%d+")
	return tonumber(num) or 0
end

local function scanBackpackMap()
	local map = {}
	local grid = getBackpackGrid()
	if not grid then return map end

	for _, slot in ipairs(grid:GetChildren()) do
		if slot:IsA("Frame") or slot:IsA("TextButton") or slot:IsA("ImageButton") then
			local tn = slot:FindFirstChild("ToolName")
			local tc = slot:FindFirstChild("ToolCount")
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

local function lookupCount(map, seedName)
	if map[seedName] then return map[seedName] end
	local target = seedName:lower():gsub("^%s+", ""):gsub("%s+$", "")
	for name, count in pairs(map) do
		local norm = name:lower():gsub("^%s+", ""):gsub("%s+$", "")
		if norm == target then
			return count
		end
	end
	return 0
end

-- ===== BUILD GUI =====
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "SeedSenderGui"
screenGui.ResetOnSpawn = false
screenGui.Parent = player:WaitForChild("PlayerGui")

local COLORS = {
	bg        = Color3.fromRGB(22, 22, 28),
	header    = Color3.fromRGB(16, 16, 20),
	input     = Color3.fromRGB(15, 15, 20),
	text      = Color3.fromRGB(235, 235, 240),
	textDim   = Color3.fromRGB(140, 140, 155),
	placeholder = Color3.fromRGB(110, 110, 125),
	accent    = Color3.fromRGB(60, 130, 200),
	accentHv  = Color3.fromRGB(80, 160, 230),
	selected  = Color3.fromRGB(120, 60, 200),
	selectedHv = Color3.fromRGB(140, 80, 220),
	green     = Color3.fromRGB(80, 200, 120),
	greenHv   = Color3.fromRGB(100, 220, 140),
	red       = Color3.fromRGB(200, 70, 70),
	redHv     = Color3.fromRGB(220, 90, 90),
	yellow    = Color3.fromRGB(220, 200, 120),
	disabled  = Color3.fromRGB(60, 60, 70),
	stroke    = Color3.fromRGB(60, 60, 72),
	preset    = Color3.fromRGB(45, 45, 55),
	presetHv  = Color3.fromRGB(60, 60, 72),
}

local function corner(p, r)
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r or 6); c.Parent = p
end

local frame = Instance.new("Frame")
frame.Size = UDim2.new(0, 320, 0, 430)
frame.Position = UDim2.new(0, 30, 0, 30)
frame.BackgroundColor3 = COLORS.bg
frame.BorderSizePixel = 0
frame.Active = true
frame.Draggable = true
frame.Parent = screenGui
corner(frame, 10)

local stroke = Instance.new("UIStroke")
stroke.Color = COLORS.stroke
stroke.Transparency = 0.4
stroke.Parent = frame

-- ===== TITLE BAR =====
local titleBar = Instance.new("Frame")
titleBar.Size = UDim2.new(1, 0, 0, 32)
titleBar.BackgroundColor3 = COLORS.header
titleBar.BorderSizePixel = 0
titleBar.ZIndex = 20
titleBar.Parent = frame
corner(titleBar, 10)

local fix = Instance.new("Frame")
fix.Size = UDim2.new(1, 0, 0, 10)
fix.Position = UDim2.new(0, 0, 1, -10)
fix.BackgroundColor3 = COLORS.header
fix.BorderSizePixel = 0
fix.ZIndex = 20
fix.Parent = titleBar

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -110, 1, 0)
title.Position = UDim2.new(0, 14, 0, 0)
title.BackgroundTransparency = 1
title.Text = "📨 Seed Sender"
title.TextColor3 = COLORS.text
title.Font = Enum.Font.GothamBold
title.TextSize = 13
title.TextXAlignment = Enum.TextXAlignment.Left
title.ZIndex = 21
title.Parent = titleBar

-- Kill button
local killBtn = Instance.new("TextButton")
killBtn.Size = UDim2.new(0, 22, 0, 22)
killBtn.Position = UDim2.new(1, -80, 0, 5)
killBtn.BackgroundColor3 = COLORS.yellow
killBtn.Text = "💀"
killBtn.TextColor3 = Color3.fromRGB(30, 30, 30)
killBtn.Font = Enum.Font.GothamBold
killBtn.TextSize = 13
killBtn.BorderSizePixel = 0
killBtn.AutoButtonColor = false
killBtn.ZIndex = 21
killBtn.Parent = titleBar
corner(killBtn, 6)

-- Close button
local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 22, 0, 22)
closeBtn.Position = UDim2.new(1, -28, 0, 5)
closeBtn.BackgroundColor3 = COLORS.red
closeBtn.Text = "×"
closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 16
closeBtn.BorderSizePixel = 0
closeBtn.AutoButtonColor = false
closeBtn.ZIndex = 21
closeBtn.Parent = titleBar
corner(closeBtn, 6)

-- ===== USERNAME INPUT =====
local userBox = Instance.new("TextBox")
userBox.Size = UDim2.new(1, -24, 0, 34)
userBox.Position = UDim2.new(0, 12, 0, 44)
userBox.BackgroundColor3 = COLORS.input
userBox.Text = ""
userBox.PlaceholderText = "Username target..."
userBox.TextColor3 = COLORS.text
userBox.PlaceholderColor3 = COLORS.placeholder
userBox.Font = Enum.Font.GothamMedium
userBox.TextSize = 12
userBox.TextXAlignment = Enum.TextXAlignment.Left
userBox.ClearTextOnFocus = false
userBox.BorderSizePixel = 0
userBox.Parent = frame
corner(userBox, 6)
local uPad = Instance.new("UIPadding", userBox)
uPad.PaddingLeft = UDim.new(0, 10)
uPad.PaddingRight = UDim.new(0, 10)

-- ===== USERNAME PRESET ROW =====
local presetRow = Instance.new("Frame")
presetRow.Size = UDim2.new(1, -24, 0, 24)
presetRow.Position = UDim2.new(0, 12, 0, 82)
presetRow.BackgroundTransparency = 1
presetRow.Parent = frame

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
	corner(pBtn, 4)
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

-- ===== INFO LABEL =====
local infoLbl = Instance.new("TextLabel")
infoLbl.Size = UDim2.new(1, -24, 0, 22)
infoLbl.Position = UDim2.new(0, 12, 0, 112)
infoLbl.BackgroundColor3 = COLORS.header
infoLbl.BorderSizePixel = 0
infoLbl.Text = "  Pilih 1-5 seed, isi username, klik SEND"
infoLbl.TextColor3 = COLORS.textDim
infoLbl.Font = Enum.Font.Code
infoLbl.TextSize = 10
infoLbl.TextXAlignment = Enum.TextXAlignment.Left
infoLbl.Parent = frame
corner(infoLbl, 4)

-- ===== SEED BUTTONS =====
local buttonRefs = {}
local selectedSeeds = {}   -- set: [display] = true

local function setInfo(text, color)
	infoLbl.Text = "  " .. text
	infoLbl.TextColor3 = color or COLORS.textDim
end

local function refreshCounts()
	local map = scanBackpackMap()
	for _, seed in ipairs(SEEDS) do
		local count = lookupCount(map, seed.lookup)
		local ref = buttonRefs[seed.display]
		if ref then
			ref.count = count
			ref.countLbl.Text = "x" .. count
			ref.countLbl.TextColor3 = (count > 0) and COLORS.green or COLORS.disabled

			-- Update warna tombol
			if selectedSeeds[seed.display] then
				ref.btn.BackgroundColor3 = COLORS.selected
			elseif count > 0 then
				ref.btn.BackgroundColor3 = COLORS.accent
			else
				ref.btn.BackgroundColor3 = COLORS.disabled
			end
		end
	end
end

local function updateSelectionInfo()
	local count = 0
	for _ in pairs(selectedSeeds) do count += 1 end
	if count == 0 then
		setInfo("Pilih 1-5 seed, isi username, klik SEND", COLORS.textDim)
	else
		setInfo(string.format("%d seed terpilih, isi username lalu klik SEND", count), COLORS.selectedHv)
	end
end

local yStart = 142
local btnHeight = 36
local btnGap = 6

for i, seed in ipairs(SEEDS) do
	local y = yStart + (i - 1) * (btnHeight + btnGap)

	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(1, -24, 0, btnHeight)
	btn.Position = UDim2.new(0, 12, 0, y)
	btn.BackgroundColor3 = COLORS.accent
	btn.Text = ""
	btn.TextColor3 = Color3.fromRGB(255, 255, 255)
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 13
	btn.BorderSizePixel = 0
	btn.AutoButtonColor = false
	btn.Parent = frame
	corner(btn, 6)

	local nameLbl = Instance.new("TextLabel")
	nameLbl.Size = UDim2.new(1, -70, 1, 0)
	nameLbl.Position = UDim2.new(0, 12, 0, 0)
	nameLbl.BackgroundTransparency = 1
	nameLbl.Text = "🌱 " .. seed.display
	nameLbl.TextColor3 = Color3.fromRGB(255, 255, 255)
	nameLbl.Font = Enum.Font.GothamBold
	nameLbl.TextSize = 13
	nameLbl.TextXAlignment = Enum.TextXAlignment.Left
	nameLbl.ZIndex = 2
	nameLbl.Parent = btn

	local countLbl = Instance.new("TextLabel")
	countLbl.Size = UDim2.new(0, 60, 1, 0)
	countLbl.Position = UDim2.new(1, -70, 0, 0)
	countLbl.BackgroundTransparency = 1
	countLbl.Text = "x0"
	countLbl.TextColor3 = COLORS.green
	countLbl.Font = Enum.Font.GothamBold
	countLbl.TextSize = 13
	countLbl.TextXAlignment = Enum.TextXAlignment.Right
	countLbl.ZIndex = 2
	countLbl.Parent = btn

	buttonRefs[seed.display] = {
		btn = btn,
		nameLbl = nameLbl,
		countLbl = countLbl,
		count = 0,
	}

	-- Hover
	btn.MouseEnter:Connect(function()
		if selectedSeeds[seed.display] then
			btn.BackgroundColor3 = COLORS.selectedHv
		elseif btn.Active then
			btn.BackgroundColor3 = COLORS.accentHv
		end
	end)
	btn.MouseLeave:Connect(function()
		refreshCounts()
	end)

	-- Click: toggle selection
	btn.MouseButton1Click:Connect(function()
		local count = buttonRefs[seed.display].count
		if count <= 0 then
			setInfo("❌ " .. seed.display .. " gak ada di backpack", COLORS.red)
			return
		end

		if selectedSeeds[seed.display] then
			selectedSeeds[seed.display] = nil
		else
			-- max 5
			local n = 0
			for _ in pairs(selectedSeeds) do n += 1 end
			if n >= 5 then
				setInfo("⚠ Max 5 seed per kiriman", COLORS.yellow)
				return
			end
			selectedSeeds[seed.display] = true
		end

		refreshCounts()
		updateSelectionInfo()
	end)
end

-- ===== SEND BUTTON =====
local sendBtn = Instance.new("TextButton")
sendBtn.Size = UDim2.new(1, -24, 0, 38)
sendBtn.Position = UDim2.new(0, 12, 0, 380)
sendBtn.BackgroundColor3 = COLORS.green
sendBtn.Text = "SEND"
sendBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
sendBtn.Font = Enum.Font.GothamBold
sendBtn.TextSize = 14
sendBtn.BorderSizePixel = 0
sendBtn.AutoButtonColor = false
sendBtn.Parent = frame
corner(sendBtn, 8)

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

sendBtn.MouseEnter:Connect(function()
	if sendBtn.Active then
		sendBtn.BackgroundColor3 = COLORS.greenHv
	end
end)
sendBtn.MouseLeave:Connect(function()
	if sendBtn.Active then
		sendBtn.BackgroundColor3 = COLORS.green
	end
end)

-- ===== SEND ACTION =====
sendBtn.MouseButton1Click:Connect(function()
	-- Collect selected seeds
	local selectedList = {}
	for _, seed in ipairs(SEEDS) do
		if selectedSeeds[seed.display] then
			local ref = buttonRefs[seed.display]
			if ref and ref.count > 0 then
				local count = ref.count
				if count > 255 then count = 255 end
				table.insert(selectedList, {
					name = seed.display,
					count = count,
				})
			end
		end
	end

	if #selectedList == 0 then
		flashSend("❌ Pilih seed dulu", COLORS.red)
		return
	end

	local username = userBox.Text:gsub("%s", "")
	if username == "" then
		flashSend("❌ Username kosong", COLORS.red)
		return
	end

	sendBtn.Text = "⏳ Resolving..."
	sendBtn.Active = false

	task.spawn(function()
		local targetId = getUserIdFromUsername(username)

		if not targetId then
			flashSend("❌ User gak ketemu", COLORS.red)
			return
		end

		sendBtn.Text = string.format("⏳ Sending %d...", #selectedList)

		local payload
		if #selectedList == 1 then
			-- single item payload
			payload = buildSinglePayload(targetId, selectedList[1].name, selectedList[1].count, "Seeds")
		else
			-- multi item payload
			payload = buildMultiPayload(targetId, selectedList, "Seeds")
		end

		if not payload then
			flashSend("❌ Payload fail", COLORS.red)
			return
		end

		local ok = pcall(function()
			remote:FireServer(payload)
		end)

		if ok then
			flashSend(string.format("✅ Sent %d", #selectedList), COLORS.success or COLORS.green, 2)

			-- Reset selection
			selectedSeeds = {}
			refreshCounts()
			updateSelectionInfo()
		else
			flashSend("❌ Fire fail", COLORS.red)
		end
	end)
end)

-- ===== KILL CHARACTER =====
killBtn.MouseButton1Click:Connect(function()
	local char = player.Character
	if not char then return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.Health = 0
	end
end)

killBtn.MouseEnter:Connect(function()
	killBtn.BackgroundColor3 = Color3.fromRGB(255, 220, 140)
end)
killBtn.MouseLeave:Connect(function()
	killBtn.BackgroundColor3 = COLORS.yellow
end)

-- ===== CLOSE =====
closeBtn.MouseButton1Click:Connect(function()
	screenGui:Destroy()
end)

-- ===== INIT =====
refreshCounts()
updateSelectionInfo()

-- Auto-refresh tiap 2 detik
task.spawn(function()
	while screenGui.Parent do
		refreshCounts()
		task.wait(2)
	end
end)
