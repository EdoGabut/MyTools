-- ============================================================
-- Crate Tracker (FIXED)
-- Cek jumlah crate di hotbar + backpack
-- ============================================================
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

-- ===== CONFIG =====
local CRATE_LIST = {
	"Gravestone Crate",
	"Halloween Prop Crate",
	"Fog Machine Crate",
}

local HOTBAR_PATH   = { "BackpackGui", "Backpack", "Hotbar" }
local BACKPACK_PATH = { "BackpackGui", "Backpack", "Inventory", "ScrollingFrame", "UIGridFrame" }
local TOOL_NAME_LABEL  = "ToolName"
local TOOL_COUNT_LABEL = "ToolCount"

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
screenGui.Name = "CrateTracker"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = player:WaitForChild("PlayerGui")

local COLORS = {
	bg        = Color3.fromRGB(22, 22, 28),
	header    = Color3.fromRGB(16, 16, 20),
	row       = Color3.fromRGB(30, 30, 36),
	input     = Color3.fromRGB(15, 15, 20),
	text      = Color3.fromRGB(235, 235, 240),
	textDim   = Color3.fromRGB(140, 140, 155),
	green     = Color3.fromRGB(80, 200, 120),
	red       = Color3.fromRGB(200, 70, 70),
	yellow    = Color3.fromRGB(220, 200, 120),
	disabled  = Color3.fromRGB(60, 60, 70),
	stroke    = Color3.fromRGB(60, 60, 72),
	preset    = Color3.fromRGB(45, 45, 55),
	accent    = Color3.fromRGB(60, 130, 200),
	hotbarCol = Color3.fromRGB(180, 140, 220),
	backpackCol = Color3.fromRGB(100, 200, 220),
}

local function corner(p, r)
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r or 8); c.Parent = p
	return c
end

local FRAME_WIDTH = 280
local FRAME_HEIGHT = 220
local FRAME_HEIGHT_MIN = 32

local frame = Instance.new("Frame")
frame.Name = "MainFrame"
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

-- ===== Drag =====
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

-- ===== Title bar =====
local titleBar = Instance.new("Frame")
titleBar.Name = "TitleBar"
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
title.Size = UDim2.new(1, -130, 1, 0)
title.Position = UDim2.new(0, 12, 0, 0)
title.BackgroundTransparency = 1
title.Text = "📦 Crate Tracker"
title.TextColor3 = COLORS.text
title.Font = Enum.Font.GothamBold
title.TextSize = 12
title.TextXAlignment = Enum.TextXAlignment.Left
title.ZIndex = 21
title.Parent = titleBar

-- ===== Button positions (FIXED - no overlap) =====
-- Copy  : X = -114
-- Refresh: X = -86
-- Minimize: X = -58
-- Close : X = -30

-- Copy log button
local copyBtn = Instance.new("TextButton")
copyBtn.Size = UDim2.new(0, 26, 0, 24)
copyBtn.Position = UDim2.new(1, -114, 0, 4)
copyBtn.BackgroundColor3 = COLORS.preset
copyBtn.Text = "📋"
copyBtn.TextColor3 = COLORS.text
copyBtn.Font = Enum.Font.GothamBold
copyBtn.TextSize = 12
copyBtn.BorderSizePixel = 0
copyBtn.AutoButtonColor = false
copyBtn.ZIndex = 21
copyBtn.Parent = titleBar
corner(copyBtn, 6)

-- Refresh button
local refreshBtn = Instance.new("TextButton")
refreshBtn.Size = UDim2.new(0, 26, 0, 24)
refreshBtn.Position = UDim2.new(1, -86, 0, 4)
refreshBtn.BackgroundColor3 = COLORS.accent
refreshBtn.Text = "🔄"
refreshBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
refreshBtn.Font = Enum.Font.GothamBold
refreshBtn.TextSize = 12
refreshBtn.BorderSizePixel = 0
refreshBtn.AutoButtonColor = false
refreshBtn.ZIndex = 21
refreshBtn.Parent = titleBar
corner(refreshBtn, 6)

-- Minimize button (FIXED position)
local minBtn = Instance.new("TextButton")
minBtn.Size = UDim2.new(0, 26, 0, 24)
minBtn.Position = UDim2.new(1, -58, 0, 4)
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

-- Close
local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 26, 0, 24)
closeBtn.Position = UDim2.new(1, -30, 0, 4)
closeBtn.BackgroundColor3 = COLORS.red
closeBtn.Text = "×"
closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 15
closeBtn.BorderSizePixel = 0
closeBtn.AutoButtonColor = false
closeBtn.ZIndex = 21
closeBtn.Parent = titleBar
corner(closeBtn, 6)

-- Info label
local infoLbl = Instance.new("TextLabel")
infoLbl.Size = UDim2.new(1, -16, 0, 20)
infoLbl.Position = UDim2.new(0, 8, 0, 38)
infoLbl.BackgroundColor3 = COLORS.header
infoLbl.BorderSizePixel = 0
infoLbl.Text = "  Total: -  |  Hotbar: -  |  Backpack: -"
infoLbl.TextColor3 = COLORS.textDim
infoLbl.Font = Enum.Font.Code
infoLbl.TextSize = 10
infoLbl.TextXAlignment = Enum.TextXAlignment.Left
infoLbl.Parent = frame
corner(infoLbl, 5)

-- ===== CRATE ROWS =====
local rowRefs = {}
local yStart = 64
local rowHeight = 38
local rowGap = 4

for i, crate in ipairs(CRATE_LIST) do
	local y = yStart + (i - 1) * (rowHeight + rowGap)

	local row = Instance.new("Frame")
	row.Name = "Row_" .. i
	row.Size = UDim2.new(1, -16, 0, rowHeight)
	row.Position = UDim2.new(0, 8, 0, y)
	row.BackgroundColor3 = COLORS.row
	row.BorderSizePixel = 0
	row.Parent = frame
	corner(row, 6)

	local nameLbl = Instance.new("TextLabel")
	nameLbl.Size = UDim2.new(1, -10, 0, 16)
	nameLbl.Position = UDim2.new(0, 10, 0, 2)
	nameLbl.BackgroundTransparency = 1
	nameLbl.Text = crate
	nameLbl.TextColor3 = COLORS.text
	nameLbl.Font = Enum.Font.GothamMedium
	nameLbl.TextSize = 11
	nameLbl.TextXAlignment = Enum.TextXAlignment.Left
	nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
	nameLbl.Parent = row

	local detailLbl = Instance.new("TextLabel")
	detailLbl.Size = UDim2.new(1, -10, 0, 14)
	detailLbl.Position = UDim2.new(0, 10, 0, 20)
	detailLbl.BackgroundTransparency = 1
	detailLbl.Text = "Hotbar: 0  |  Backpack: 0  |  Total: 0"
	detailLbl.TextColor3 = COLORS.textDim
	detailLbl.Font = Enum.Font.Code
	detailLbl.TextSize = 10
	detailLbl.TextXAlignment = Enum.TextXAlignment.Left
	detailLbl.Parent = row

	rowRefs[crate] = {
		row = row,
		nameLbl = nameLbl,
		detailLbl = detailLbl,
		hotbar = 0,
		backpack = 0,
		total = 0,
	}
end

-- ===== REFRESH =====
local function refresh()
	local combined, hotbarMap, backpackMap = scanAll()

	local totalAll = 0
	local hotbarAll = 0
	local backpackAll = 0

	for _, crate in ipairs(CRATE_LIST) do
		local hotbar = lookupCount(hotbarMap, crate)
		local backpack = lookupCount(backpackMap, crate)
		local total = hotbar + backpack

		hotbarAll = hotbarAll + hotbar
		backpackAll = backpackAll + backpack
		totalAll = totalAll + total

		local ref = rowRefs[crate]
		if ref then
			ref.hotbar = hotbar
			ref.backpack = backpack
			ref.total = total

			ref.detailLbl.Text = string.format("Hotbar: %d  |  Backpack: %d  |  Total: %d",
				hotbar, backpack, total)

			if total > 0 then
				ref.nameLbl.TextColor3 = COLORS.text
				ref.detailLbl.TextColor3 = COLORS.green
			else
				ref.nameLbl.TextColor3 = COLORS.textDim
				ref.detailLbl.TextColor3 = COLORS.disabled
			end
		end
	end

	infoLbl.Text = string.format("  Total: %d  |  Hotbar: %d  |  Backpack: %d",
		totalAll, hotbarAll, backpackAll)
	infoLbl.TextColor3 = (totalAll > 0) and COLORS.green or COLORS.textDim
end

-- ===== COPY LOG =====
local function buildLogText()
	local combined, hotbarMap, backpackMap = scanAll()
	local lines = {}

	table.insert(lines, "=== CRATE TRACKER ===")
	table.insert(lines, "Time: " .. tostring(os.time()))
	table.insert(lines, "")

	local totalAll = 0

	for _, crate in ipairs(CRATE_LIST) do
		local hotbar = lookupCount(hotbarMap, crate)
		local backpack = lookupCount(backpackMap, crate)
		local total = hotbar + backpack
		totalAll = totalAll + total

		table.insert(lines, string.format("%s:", crate))
		table.insert(lines, string.format("  Hotbar:   %d", hotbar))
		table.insert(lines, string.format("  Backpack: %d", backpack))
		table.insert(lines, string.format("  Total:    %d", total))
		table.insert(lines, "")
	end

	table.insert(lines, string.format("GRAND TOTAL: %d", totalAll))

	return table.concat(lines, "\n")
end

copyBtn.MouseButton1Click:Connect(function()
	local text = buildLogText()
	local ok = pcall(function()
		if setclipboard then
			setclipboard(text)
		elseif toclipboard then
			toclipboard(text)
		else
			error("no clipboard function")
		end
	end)
	if ok then
		copyBtn.BackgroundColor3 = COLORS.green
		copyBtn.Text = "✓"
		task.delay(1, function()
			copyBtn.BackgroundColor3 = COLORS.preset
			copyBtn.Text = "📋"
		end)
	else
		print(text)
	end
end)

copyBtn.MouseEnter:Connect(function()
	if copyBtn.Text == "📋" then
		copyBtn.BackgroundColor3 = COLORS.stroke
	end
end)
copyBtn.MouseLeave:Connect(function()
	if copyBtn.Text == "📋" then
		copyBtn.BackgroundColor3 = COLORS.preset
	end
end)

-- ===== REFRESH BUTTON =====
refreshBtn.MouseButton1Click:Connect(function()
	refresh()
	refreshBtn.Text = "⏳"
	task.delay(0.5, function()
		refreshBtn.Text = "🔄"
	end)
end)

refreshBtn.MouseEnter:Connect(function()
	TweenService:Create(refreshBtn, TweenInfo.new(0.1), {
		BackgroundColor3 = Color3.fromRGB(80, 160, 230)
	}):Play()
end)
refreshBtn.MouseLeave:Connect(function()
	TweenService:Create(refreshBtn, TweenInfo.new(0.1), {
		BackgroundColor3 = COLORS.accent
	}):Play()
end)

-- ===== AUTO REFRESH =====
task.spawn(function()
	while screenGui and screenGui.Parent do
		pcall(refresh)
		task.wait(1)
	end
end)

-- ===== MINIMIZE =====
local isMinimized = false
minBtn.MouseButton1Click:Connect(function()
	isMinimized = not isMinimized
	if isMinimized then
		for _, child in ipairs(frame:GetChildren()) do
			if child ~= titleBar then
				child.Visible = false
			end
		end
		frame.Size = UDim2.new(0, FRAME_WIDTH, 0, FRAME_HEIGHT_MIN)
		minBtn.Text = "+"
	else
		for _, child in ipairs(frame:GetChildren()) do
			if child ~= titleBar then
				child.Visible = true
			end
		end
		frame.Size = UDim2.new(0, FRAME_WIDTH, 0, FRAME_HEIGHT)
		minBtn.Text = "—"
	end
end)

-- ===== CLOSE =====
closeBtn.MouseButton1Click:Connect(function()
	screenGui:Destroy()
end)

-- ===== INIT =====
pcall(refresh)
print("[Crate Tracker] Loaded successfully!")
