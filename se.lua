-- ============================================================
-- Seed Sender v3
-- - Auto-send: 1 Briar Rose ATAU 5 Spirethorn → langsung kirim
-- - Log panel: nampilin history kirim ke siapa
-- - Minimize button
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
local SEEDS = {
	{ display = "Spirethorn", lookup = "Spirethorn Seed" },
	{ display = "Briar Rose", lookup = "Briar Rose Seed" },
	{ display = "Gold",       lookup = "Gold Seed" },
	{ display = "Mega",       lookup = "Mega Seed" },
	{ display = "Rainbow",    lookup = "Rainbow Seed" },
}

local USERNAME_PRESETS = { "krinjguy67", "andri21649", "notexd777" }

local HOTBAR_PATH   = { "BackpackGui", "Backpack", "Hotbar" }
local BACKPACK_PATH = { "BackpackGui", "Backpack", "Inventory", "ScrollingFrame", "UIGridFrame" }
local TOOL_NAME_LABEL  = "ToolName"
local TOOL_COUNT_LABEL = "ToolCount"

-- Auto-send rules: begitu salah satu kondisi terpenuhi → kirim
local AUTO_SEND = {
	ENABLED = true,
	-- kirim semua seed yang ada begitu trigger terpenuhi
	TRIGGERS = {
		{ display = "Briar Rose", min = 1 },   -- ≥1 Briar Rose
		{ display = "Spirethorn", min = 5 },   -- ≥5 Spirethorn
	},
	-- username target (kalau nil, ambil dari preset pertama atau input manual)
	TARGET_MODE = "manual",  -- "manual" | "rotate" | "fixed"
	FIXED_TARGET = "krinjguy67",
	-- jeda minimum antar auto-send (biar nggak spam)
	COOLDOWN = 3,
}

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
-- GUI
-- ============================================================
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
	logBg     = Color3.fromRGB(14, 14, 18),
}

local function corner(p, r)
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r or 8); c.Parent = p
end

local FRAME_WIDTH = 250
local FRAME_HEIGHT = 260   -- lebih tinggi karena ada log

local frame = Instance.new("Frame")
frame.Size = UDim2.new(0, FRAME_WIDTH, 0, FRAME_HEIGHT)
frame.Position = UDim2.new(0, 15, 0, 15)
frame.BackgroundColor3 = COLORS.bg
frame.BorderSizePixel = 0
frame.Active = true
frame.Parent = screenGui
corner(frame, 12)

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "SeedSenderMini"
screenGui.ResetOnSpawn = false
screenGui.Parent = player:WaitForChild("PlayerGui")
-- (pindah ke atas setelah instance dibuat)
frame.Parent = screenGui

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

-- ===== TITLE BAR =====
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
title.Text = "📨 Seed Sender"
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

-- ===== BODY =====
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

-- Info seed (1 baris ringkas)
local infoLbl = Instance.new("TextLabel")
infoLbl.Size = UDim2.new(1, 0, 0, 24)
infoLbl.Position = UDim2.new(0, 0, 0, 62)
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

-- ===== LOG PANEL =====
local logLbl = Instance.new("TextLabel")
logLbl.Size = UDim2.new(1, 0, 0, 58)
logLbl.Position = UDim2.new(0, 0, 0, 90)
logLbl.BackgroundColor3 = COLORS.logBg
logLbl.BorderSizePixel = 0
logLbl.Text = "📜 Log:\n  (belum ada aktivitas)"
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
lPad.PaddingBottom = UDim.new(0, 4)

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

-- ============================================================
-- STATE
-- ============================================================
local currentCounts = {}
local lastSendTime = 0
local logLines = {}
local MAX_LOG_LINES = 4

local function pushLog(line)
	local time = os.date("%H:%M:%S")
	local entry = string.format("[%s] %s", time, line)
	table.insert(logLines, 1, entry)  -- newest di atas
	while #logLines > MAX_LOG_LINES do
		table.remove(logLines)
	end
	logLbl.Text = "📜 Log:\n" .. table.concat(logLines, "\n")
end

local function refreshStatus()
	local combined = scanAll()
	local parts = {}
	local totalJenis = 0

	for _, seed in ipairs(SEEDS) do
		local count = lookupCount(combined, seed.lookup)
		currentCounts[seed.display] = count
		if count > 0 then
			totalJenis += 1
			table.insert(parts, string.format("%s x%d", seed.display, count))
		end
	end

	if totalJenis == 0 then
		infoLbl.Text = "🌱 Tidak ada seed"
		infoLbl.TextColor3 = COLORS.disabled
	else
		infoLbl.Text = "🌱 " .. table.concat(parts, " · ")
		infoLbl.TextColor3 = COLORS.green
	end
end

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

-- Kumpulkan seed yang mau dikirim (semua yang count > 0)
local function collectSendItems()
	local items = {}
	for _, seed in ipairs(SEEDS) do
		local count = currentCounts[seed.display] or 0
		if count > 0 then
			table.insert(items, {
				name = seed.display,
				count = math.min(count, 255),
			})
		end
	end
	return items
end

-- Kirim ke username, return true/false + pesan
local function doSend(username)
	if username == "" then
		return false, "username kosong"
	end

	local items = collectSendItems()
	if #items == 0 then
		return false, "gak ada seed"
	end

	local targetId = getUserIdFromUsername(username)
	if not targetId then
		return false, "user '" .. username .. "' gak ketemu"
	end

	local payload
	if #items == 1 then
		payload = buildSinglePayload(targetId, items[1].name, items[1].count, "Seeds")
	else
		payload = buildMultiPayload(targetId, items, "Seeds")
	end

	if not payload then
		return false, "payload fail"
	end

	local ok = pcall(function()
		remote:FireServer(payload)
	end)

	if not ok then
		return false, "fire fail"
	end

	-- ringkasan item
	local itemStr = {}
	for _, it in ipairs(items) do
		table.insert(itemStr, string.format("%s x%d", it.name, it.count))
	end
	return true, string.format("→ %s (%s)", username, table.concat(itemStr, ", "))
end

-- Cek apakah trigger auto-send terpenuhi
local function checkAutoTrigger()
	if not AUTO_SEND.ENABLED then return false end
	for _, trig in ipairs(AUTO_SEND.TRIGGERS) do
		local cnt = currentCounts[trig.display] or 0
		if cnt >= trig.min then
			return true, trig
		end
	end
	return false
end

-- Ambil username target auto
local function getAutoTarget()
	if AUTO_SEND.TARGET_MODE == "fixed" then
		return AUTO_SEND.FIXED_TARGET
	elseif AUTO_SEND.TARGET_MODE == "rotate" then
		-- rotasi preset (belum diimplement state, fallback ke pertama)
		return USERNAME_PRESETS[1]
	else
		-- manual: ambil dari input kalau ada, kalau kosong pakai preset pertama
		local manual = userBox.Text:gsub("%s", "")
		if manual ~= "" then return manual end
		return USERNAME_PRESETS[1]
	end
end

-- ============================================================
-- MANUAL SEND BUTTON
-- ============================================================
sendBtn.MouseButton1Click:Connect(function()
	refreshStatus()

	local username = userBox.Text:gsub("%s", "")
	if username == "" then
		username = getAutoTarget()
		userBox.Text = username
	end

	sendBtn.Text = "⏳ Sending..."
	sendBtn.BackgroundColor3 = COLORS.yellow

	task.spawn(function()
		local ok, msg = doSend(username)
		if ok then
			pushLog("✅ " .. msg)
			flashSend("✅ Terkirim", COLORS.green, 2)
		else
			pushLog("❌ Gagal: " .. msg)
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
-- AUTO-SEND LOOP
-- ============================================================
task.spawn(function()
	while screenGui.Parent do
		refreshStatus()

		if AUTO_SEND.ENABLED and (tick() - lastSendTime) >= AUTO_SEND.COOLDOWN then
			local triggered, trig = checkAutoTrigger()
			if triggered then
				local target = getAutoTarget()
				lastSendTime = tick()
				pushLog(string.format("🔔 Trigger: %s x%d", trig.display, currentCounts[trig.display] or 0))

				task.spawn(function()
					local ok, msg = doSend(target)
					if ok then
						pushLog("✅ AUTO " .. msg)
					else
						pushLog("❌ AUTO gagal: " .. msg)
					end
				end)
			end
		end

		task.wait(1)
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
		title.Text = "📨 Seed Sender (—)"
	else
		TweenService:Create(frame, TweenInfo.new(0.2), {
			Size = UDim2.new(0, FRAME_WIDTH, 0, savedSize)
		}):Play()
		body.Visible = true
		title.Text = "📨 Seed Sender"
	end
end)

closeBtn.MouseButton1Click:Connect(function()
	screenGui:Destroy()
end)

-- ============================================================
-- INIT
-- ============================================================
refreshStatus()
pushLog("siap. auto-send: Briar≥1 / Spire≥5")
