-- ============================================================
-- Crate Sender v2
-- - Kirim 1 per 1 (single send)
-- - Tampil crate + count di tas/toolbar
-- - Klik item buat kirim
-- - Langsung kirim ke ID lu (11142670172)
-- ============================================================
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

local remote = ReplicatedStorage:WaitForChild("SharedModules")
	:WaitForChild("Packet"):WaitForChild("RemoteEvent")

-- ===== CONFIG =====
local TARGET_USER_ID = 11142670172  -- ID lu

local ITEMS = {
	{ display = "Fog Machine Crate",    name = "Fog Machine Crate",    lookup = "Fog Machine Crate",    category = "Crates" },
	{ display = "Halloween Prop Crate", name = "Halloween Prop Crate", lookup = "Halloween Prop Crate", category = "Crates" },
	{ display = "Gravestone Crate",     name = "Gravestone Crate",     lookup = "Gravestone Crate",     category = "Crates" },
}

local HOTBAR_PATH   = { "BackpackGui", "Backpack", "Hotbar" }
local BACKPACK_PATH = { "BackpackGui", "Backpack", "Inventory", "ScrollingFrame", "UIGridFrame" }

-- ===== PAYLOAD BUILDER (SINGLE) =====
-- Header: 8C 01 [UserID f64] 1C 05 01 1C
-- Entry: 05 01 1C "ItemKey" [nama] "Count" [n] "Category" [cat] 00
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

	-- Single entry (index 01)
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
	local hotbarMap = scanContainer(resolveFromPlayerGui(HOTBAR_PATH))
	local backpackMap = scanContainer(resolveFromPlayerGui(BACKPACK_PATH))
	local combined = {}
	for _, map in pairs({ hotbarMap, backpackMap }) do
		for name, count in pairs(map) do
			combined[name] = (combined[name] or 0) + count
		end
	end
	return combined, hotbarMap, backpackMap
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
screenGui.Name = "CrateSenderSingle"
screenGui.ResetOnSpawn = false
screenGui.Parent = player:WaitForChild("PlayerGui")

local COLORS = {
	bg        = Color3.fromRGB(22, 22, 28),
	header    = Color3.fromRGB(16, 16, 20),
	row       = Color3.fromRGB(30, 30, 36),
	rowHover  = Color3.fromRGB(38, 38, 46),
	rowActive = Color3.fromRGB(30, 45, 38),
	text      = Color3.fromRGB(235, 235, 240),
	textDim   = Color3.fromRGB(140, 140, 155),
	green     = Color3.fromRGB(80, 200, 120),
	greenHv   = Color3.fromRGB(100, 220, 140),
	red       = Color3.fromRGB(200, 70, 70),
	disabled  = Color3.fromRGB(60, 60, 70),
	stroke    = Color3.fromRGB(60, 60, 72),
	preset    = Color3.fromRGB(45, 45, 55),
}

local function corner(p, r)
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r or 8); c.Parent = p
end

local FRAME_WIDTH = 260
local FRAME_HEIGHT = 200
local FRAME_HEIGHT_MIN = 32

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
titleBar.Size = UDim2.new(1, 0, 0, 32)
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
title.Text = "📦 Crate Sender"
title.TextColor3 = COLORS.text
title.Font = Enum.Font.GothamBold
title.TextSize = 12
title.TextXAlignment = Enum.TextXAlignment.Left
title.ZIndex = 21
title.Parent = titleBar

local minBtn = Instance.new("TextButton")
minBtn.Size = UDim2.new(0, 24, 0, 24)
minBtn.Position = UDim2.new(1, -56, 0, 4)
minBtn.BackgroundColor3 = COLORS.preset
minBtn.Text = "—"
minBtn.TextColor3 = COLORS.text
minBtn.Font = Enum.Font.GothamBold
minBtn.TextSize = 12
minBtn.BorderSizePixel = 0
minBtn.AutoButtonColor = false
minBtn.ZIndex = 21
minBtn.Parent = titleBar
corner(minBtn, 6)

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 24, 0, 24)
closeBtn.Position = UDim2.new(1, -30, 0, 4)
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
body.Size = UDim2.new(1, -16, 1, -42)
body.Position = UDim2.new(0, 8, 0, 38)
body.BackgroundTransparency = 1
body.Parent = frame

-- Info header
local infoLbl = Instance.new("TextLabel")
infoLbl.Size = UDim2.new(1, 0, 0, 20)
infoLbl.Position = UDim2.new(0, 0, 0, 0)
infoLbl.BackgroundColor3 = COLORS.header
infoLbl.BorderSizePixel = 0
infoLbl.Text = string.format("  Target: ID %d | Tap crate to send", TARGET_USER_ID)
infoLbl.TextColor3 = COLORS.textDim
infoLbl.Font = Enum.Font.Code
infoLbl.TextSize = 9
infoLbl.TextXAlignment = Enum.TextXAlignment.Left
infoLbl.Parent = body
corner(infoLbl, 5)

-- ===== CRATE ROWS =====
local rowRefs = {}
local yStart = 26
local rowHeight = 40
local rowGap = 4

-- Refresh function (dideklarasi dulu biar bisa dipake di click)
local refreshStatus

for i, item in ipairs(ITEMS) do
	local y = yStart + (i - 1) * (rowHeight + rowGap)

	-- TextButton biar bisa diklik
	local row = Instance.new("TextButton")
	row.Size = UDim2.new(1, 0, 0, rowHeight)
	row.Position = UDim2.new(0, 0, 0, y)
	row.BackgroundColor3 = COLORS.row
	row.BorderSizePixel = 0
	row.Text = ""
	row.AutoButtonColor = false
	row.Parent = body
	corner(row, 6)

	local nameLbl = Instance.new("TextLabel")
	nameLbl.Size = UDim2.new(1, -80, 0, 16)
	nameLbl.Position = UDim2.new(0, 10, 0, 4)
	nameLbl.BackgroundTransparency = 1
	nameLbl.Text = item.display
	nameLbl.TextColor3 = COLORS.text
	nameLbl.Font = Enum.Font.GothamBold
	nameLbl.TextSize = 11
	nameLbl.TextXAlignment = Enum.TextXAlignment.Left
	nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
	nameLbl.Active = false
	nameLbl.Parent = row

	local detailLbl = Instance.new("TextLabel")
	detailLbl.Size = UDim2.new(1, -80, 0, 14)
	detailLbl.Position = UDim2.new(0, 10, 0, 22)
	detailLbl.BackgroundTransparency = 1
	detailLbl.Text = "Tap untuk kirim"
	detailLbl.TextColor3 = COLORS.textDim
	detailLbl.Font = Enum.Font.Code
	detailLbl.TextSize = 9
	detailLbl.TextXAlignment = Enum.TextXAlignment.Left
	detailLbl.Active = false
	detailLbl.Parent = row

	local countLbl = Instance.new("TextLabel")
	countLbl.Size = UDim2.new(0, 70, 1, 0)
	countLbl.Position = UDim2.new(1, -75, 0, 0)
	countLbl.BackgroundTransparency = 1
	countLbl.Text = "x0"
	countLbl.TextColor3 = COLORS.disabled
	countLbl.Font = Enum.Font.GothamBold
	countLbl.TextSize = 14
	countLbl.TextXAlignment = Enum.TextXAlignment.Right
	countLbl.Active = false
	countLbl.Parent = row

	rowRefs[item.display] = {
		row = row,
		nameLbl = nameLbl,
		detailLbl = detailLbl,
		countLbl = countLbl,
		count = 0,
		item = item,
	}

	-- Hover
	row.MouseEnter:Connect(function()
		if rowRefs[item.display].count > 0 then
			TweenService:Create(row, TweenInfo.new(0.1), {
				BackgroundColor3 = COLORS.rowHover
			}):Play()
		end
	end)
	row.MouseLeave:Connect(function()
		TweenService:Create(row, TweenInfo.new(0.1), {
			BackgroundColor3 = COLORS.row
		}):Play()
	end)

	-- Click = kirim
	row.MouseButton1Click:Connect(function()
		local ref = rowRefs[item.display]
		if not ref then return end
		if ref.count <= 0 then
			ref.detailLbl.Text = "❌ Gak ada di tas"
			ref.detailLbl.TextColor3 = COLORS.red
			task.delay(1.5, function()
				ref.detailLbl.Text = "Tap untuk kirim"
				ref.detailLbl.TextColor3 = COLORS.textDim
			end)
			return
		end

		local count = math.min(ref.count, 255)

		-- Flash loading
		ref.detailLbl.Text = "⏳ Mengirim..."
		ref.detailLbl.TextColor3 = COLORS.green
		row.BackgroundColor3 = COLORS.rowActive

		-- Build payload single
		local payload = buildSinglePayload(TARGET_USER_ID, item.name, count, item.category)

		local ok = pcall(function()
			remote:FireServer(payload)
		end)

		if ok then
			ref.detailLbl.Text = string.format("✅ Terkirim x%d", count)
			ref.detailLbl.TextColor3 = COLORS.green
		else
			ref.detailLbl.Text = "❌ Gagal kirim"
			ref.detailLbl.TextColor3 = COLORS.red
		end

		task.delay(2, function()
			TweenService:Create(row, TweenInfo.new(0.2), {
				BackgroundColor3 = COLORS.row
			}):Play()
			refreshStatus()
		end)
	end)
end

-- ===== REFRESH =====
refreshStatus = function()
	local combined = scanAll()

	for _, item in ipairs(ITEMS) do
		local count = lookupCount(combined, item.lookup)
		local ref = rowRefs[item.display]
		if ref then
			ref.count = count
			ref.countLbl.Text = "x" .. count

			if count > 0 then
				ref.countLbl.TextColor3 = COLORS.green
				ref.nameLbl.TextColor3 = COLORS.text
				ref.row.BackgroundColor3 = COLORS.row
			else
				ref.countLbl.TextColor3 = COLORS.disabled
				ref.nameLbl.TextColor3 = COLORS.textDim
			end
		end
	end
end

-- ===== MINIMIZE =====
local isMinimized = false
minBtn.MouseButton1Click:Connect(function()
	isMinimized = not isMinimized
	if isMinimized then
		body.Visible = false
		frame.Size = UDim2.new(0, FRAME_WIDTH, 0, FRAME_HEIGHT_MIN)
		minBtn.Text = "+"
	else
		body.Visible = true
		frame.Size = UDim2.new(0, FRAME_WIDTH, 0, FRAME_HEIGHT)
		minBtn.Text = "—"
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
		task.wait(1.5)
		refreshStatus()
	end
end)
