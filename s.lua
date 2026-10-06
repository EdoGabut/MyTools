-- LocalScript: Auto Buy Seeds & Gear (Minimalis + Dropdown)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer

-- ===== REMOTE =====
local remote = ReplicatedStorage:WaitForChild("SharedModules")
	:WaitForChild("Packet"):WaitForChild("RemoteEvent")

-- ===== DATA =====
local GEAR_LIST = {
	"Cider Watering Can",
	"Common Cider Sprinkler",
	"Uncommon Cider Sprinkler",
	"Rare Cider Sprinkler",
	"Legendary Cider Sprinkler",
	"Super Cider Sprinkler",
	"Trowel",
	"Rare Magic Mail",
	"Legendary Magic Mail",
	"Super Magic Mail",
	"The Bone",
	"Candy Basket",
	"Necromancer Staff",
	"Bat Charm",
	"Cauldron Charm",
	"Super Cider Watering Can",
}

local SEED_LIST = {
	"Spirit Carrot",
	"Spirit Strawberry",
	"Spirit Blueberry",
	"Spirit Tulip",
	"Spirit Tomato",
	"Spirit Apple",
	"Spirit Bamboo",
	"Spirit Corn",
	"Spirit Cactus",
	"Spirit Pineapple",
	"Spirit Mushroom",
	"Spirit Green Bean",
	"Spirit Banana",
	"Spirit Grape",
	"Spirit Coconut",
	"Spirit Mango",
	"Spirit Dragon Fruit",
	"Spirit Acorn",
	"Spirit Cherry",
	"Spirit Sunflower",
	"Spirit Venus Fly Trap",
	"Spirit Pomegranate",
	"Spirit Poison Apple",
	"Spirit Venom Spitter",
	"Great Pumpkin",
	"Vampire Bloom",
}

-- ===== PAYLOAD BUILDERS =====
local function buildGearPayload(name)
	local len = #name
	if len > 255 then return nil end
	return buffer.fromstring("\206\000" .. string.char(len) .. name)
end

local function buildSeedPayload(name)
	local len = #name
	if len > 255 then return nil end
	return buffer.fromstring("\184\000" .. string.char(len) .. name)
end

-- ===== PATH BUILDERS =====
local GEAR_BASE = "game.Players.LocalPlayer.PlayerGui.GearShop.Frame.ScrollingFrame"
local SEED_BASE = "game.Players.LocalPlayer.PlayerGui.SeedShop.Frame.NormalShop"

local function getGearStockPath(name)
	return GEAR_BASE .. "." .. name .. ".Main_Frame.Stock_Text"
end

local function getSeedStockPath(name)
	return SEED_BASE .. "." .. name .. ".Main_Frame.Stock_Text"
end

-- ===== HELPERS =====
local function resolvePath(pathStr)
	if not pathStr or pathStr == "" then return nil end
	pathStr = pathStr:gsub("^%s+", ""):gsub("%s+$", "")
	local segments = {}
	for seg in pathStr:gmatch("[^%.]+") do
		table.insert(segments, seg)
	end
	if #segments == 0 then return nil end

	local node = game
	if segments[1] == "game" then table.remove(segments, 1) end

	for _, seg in ipairs(segments) do
		if not node then return nil end
		if seg == "LocalPlayer" then
			node = player
		else
			node = node:FindFirstChild(seg)
		end
	end
	return node
end

local function parseStock(label)
	if not label or not label.Text then return nil end
	return tonumber(label.Text:match("[xX](%d+)")) or tonumber(label.Text:match("(%d+)"))
end

-- ===== COLORS =====
local COLORS = {
	bg = Color3.fromRGB(24, 24, 28),
	header = Color3.fromRGB(18, 18, 22),
	section = Color3.fromRGB(40, 40, 48),
	sectionHover = Color3.fromRGB(48, 48, 58),
	row = Color3.fromRGB(30, 30, 36),
	rowHover = Color3.fromRGB(38, 38, 46),
	text = Color3.fromRGB(225, 225, 230),
	textDim = Color3.fromRGB(140, 140, 150),
	stockOk = Color3.fromRGB(150, 230, 160),
	stockEmpty = Color3.fromRGB(120, 120, 130),
	accentOn = Color3.fromRGB(80, 200, 120),
	accentOff = Color3.fromRGB(55, 55, 65),
	stroke = Color3.fromRGB(60, 60, 72),
	close = Color3.fromRGB(200, 70, 70),
	minimize = Color3.fromRGB(230, 180, 60),
}

-- ===== BUILD GUI =====
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "AutoBuyShop"
screenGui.ResetOnSpawn = false
screenGui.Parent = player:WaitForChild("PlayerGui")

local frame = Instance.new("Frame")
frame.Size = UDim2.new(0, 300, 0, 520)
frame.Position = UDim2.new(0, 20, 0, 20)
frame.BackgroundColor3 = COLORS.bg
frame.BorderSizePixel = 0
frame.Active = true
frame.Draggable = true
frame.Parent = screenGui
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 10)

local stroke = Instance.new("UIStroke")
stroke.Color = COLORS.stroke
stroke.Transparency = 0.4
stroke.Parent = frame

-- Title bar
local titleBar = Instance.new("Frame")
titleBar.Size = UDim2.new(1, 0, 0, 32)
titleBar.BackgroundColor3 = COLORS.header
titleBar.BorderSizePixel = 0
titleBar.Parent = frame
Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 10)

local titleBarFix = Instance.new("Frame")
titleBarFix.Size = UDim2.new(1, 0, 0, 10)
titleBarFix.Position = UDim2.new(0, 0, 1, -10)
titleBarFix.BackgroundColor3 = COLORS.header
titleBarFix.BorderSizePixel = 0
titleBarFix.Parent = titleBar

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -80, 1, 0)
title.Position = UDim2.new(0, 14, 0, 0)
title.BackgroundTransparency = 1
title.Text = "Auto Buy Shop"
title.TextColor3 = COLORS.text
title.Font = Enum.Font.GothamBold
title.TextSize = 12
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = titleBar

local minBtn = Instance.new("TextButton")
minBtn.Size = UDim2.new(0, 22, 0, 22)
minBtn.Position = UDim2.new(1, -54, 0, 5)
minBtn.BackgroundColor3 = COLORS.minimize
minBtn.Text = "−"
minBtn.TextColor3 = Color3.fromRGB(30, 30, 30)
minBtn.Font = Enum.Font.GothamBold
minBtn.TextSize = 14
minBtn.BorderSizePixel = 0
minBtn.AutoButtonColor = false
minBtn.Parent = titleBar
Instance.new("UICorner", minBtn).CornerRadius = UDim.new(0, 6)

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 22, 0, 22)
closeBtn.Position = UDim2.new(1, -28, 0, 5)
closeBtn.BackgroundColor3 = COLORS.close
closeBtn.Text = "×"
closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 16
closeBtn.BorderSizePixel = 0
closeBtn.AutoButtonColor = false
closeBtn.Parent = titleBar
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 6)

-- Main scroll container
local mainScroll = Instance.new("ScrollingFrame")
mainScroll.Size = UDim2.new(1, -16, 1, -42)
mainScroll.Position = UDim2.new(0, 8, 0, 36)
mainScroll.BackgroundTransparency = 1
mainScroll.BorderSizePixel = 0
mainScroll.ScrollBarThickness = 4
mainScroll.ScrollBarImageColor3 = Color3.fromRGB(80, 80, 100)
mainScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
mainScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
mainScroll.Parent = frame

local mainLayout = Instance.new("UIListLayout")
mainLayout.Padding = UDim.new(0, 6)
mainLayout.SortOrder = Enum.SortOrder.LayoutOrder
mainLayout.Parent = mainScroll

-- ===== STATE =====
local autoBuyStates = {}  -- [key] = { enabled, token }
local stockLabels = {}    -- [key] = TextLabel
local BUY_INTERVAL = 0.5

-- ===== AUTO BUY LOOP =====
local function startAutoBuy(key, stockPath, payloadBuilder)
	local entry = autoBuyStates[key]
	if not entry then return end
	local myToken = entry.token

	task.spawn(function()
		while entry.enabled and entry.token == myToken do
			local label = resolvePath(stockPath)
			local stock = parseStock(label)

			if stock and stock > 0 then
				local payload = payloadBuilder(key)
				if payload then
					pcall(function()
						remote:FireServer(payload)
					end)
				end
			end

			task.wait(BUY_INTERVAL)
		end
	end)
end

-- ===== DROPDOWN SECTION =====
local function makeDropdownSection(sectionTitle, items, getStockPath, payloadBuilder)
	local sectionOrder = 0

	local container = Instance.new("Frame")
	container.Size = UDim2.new(1, -4, 0, 28)
	container.BackgroundTransparency = 1
	container.AutomaticSize = Enum.AutomaticSize.Y
	container.LayoutOrder = (sectionTitle == "Seeds") and 0 or 1
	container.Parent = mainScroll

	local containerLayout = Instance.new("UIListLayout")
	containerLayout.Padding = UDim.new(0, 3)
	containerLayout.SortOrder = Enum.SortOrder.LayoutOrder
	containerLayout.Parent = container

	-- Header (clickable)
	local header = Instance.new("TextButton")
	header.Size = UDim2.new(1, 0, 0, 30)
	header.BackgroundColor3 = COLORS.section
	header.Text = ""
	header.BorderSizePixel = 0
	header.AutoButtonColor = false
	header.LayoutOrder = 0
	header.Parent = container
	Instance.new("UICorner", header).CornerRadius = UDim.new(0, 6)

	local arrow = Instance.new("TextLabel")
	arrow.Size = UDim2.new(0, 20, 1, 0)
	arrow.Position = UDim2.new(0, 8, 0, 0)
	arrow.BackgroundTransparency = 1
	arrow.Text = "▶"
	arrow.TextColor3 = COLORS.text
	arrow.Font = Enum.Font.GothamBold
	arrow.TextSize = 10
	arrow.Parent = header

	local headerTitle = Instance.new("TextLabel")
	headerTitle.Size = UDim2.new(1, -40, 1, 0)
	headerTitle.Position = UDim2.new(0, 28, 0, 0)
	headerTitle.BackgroundTransparency = 1
	headerTitle.Text = sectionTitle .. " (" .. #items .. ")"
	headerTitle.TextColor3 = COLORS.text
	headerTitle.Font = Enum.Font.GothamBold
	headerTitle.TextSize = 11
	headerTitle.TextXAlignment = Enum.TextXAlignment.Left
	headerTitle.Parent = header

	-- Content container
	local content = Instance.new("Frame")
	content.Size = UDim2.new(1, 0, 0, 0)
	content.BackgroundTransparency = 1
	content.AutomaticSize = Enum.AutomaticSize.Y
	content.Visible = false
	content.LayoutOrder = 1
	content.Parent = container

	local contentLayout = Instance.new("UIListLayout")
	contentLayout.Padding = UDim.new(0, 3)
	contentLayout.SortOrder = Enum.SortOrder.LayoutOrder
	contentLayout.Parent = content

	-- Section toggle state
	local expanded = false
	local function setExpanded(state)
		expanded = state
		content.Visible = expanded
		arrow.Text = expanded and "▼" or "▶"
		TweenService:Create(header, TweenInfo.new(0.15), {
			BackgroundColor3 = expanded and COLORS.sectionHover or COLORS.section
		}):Play()
	end

	header.MouseEnter:Connect(function()
		if not expanded then
			TweenService:Create(header, TweenInfo.new(0.1), {
				BackgroundColor3 = COLORS.sectionHover
			}):Play()
		end
	end)
	header.MouseLeave:Connect(function()
		if not expanded then
			TweenService:Create(header, TweenInfo.new(0.1), {
				BackgroundColor3 = COLORS.section
			}):Play()
		end
	end)

	header.MouseButton1Click:Connect(function()
		setExpanded(not expanded)
	end)

	-- Build rows
	for _, itemName in ipairs(items) do
		sectionOrder += 1

		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, -8, 0, 28)
		row.Position = UDim2.new(0, 8, 0, 0)
		row.BackgroundColor3 = COLORS.row
		row.BorderSizePixel = 0
		row.LayoutOrder = sectionOrder
		row.Parent = content
		Instance.new("UICorner", row).CornerRadius = UDim.new(0, 5)

		local nameLbl = Instance.new("TextLabel")
		nameLbl.Size = UDim2.new(1, -100, 1, 0)
		nameLbl.Position = UDim2.new(0, 10, 0, 0)
		nameLbl.BackgroundTransparency = 1
		nameLbl.Text = itemName
		nameLbl.TextColor3 = COLORS.text
		nameLbl.Font = Enum.Font.GothamMedium
		nameLbl.TextSize = 10
		nameLbl.TextXAlignment = Enum.TextXAlignment.Left
		nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
		nameLbl.Parent = row

		local stockLbl = Instance.new("TextLabel")
		stockLbl.Size = UDim2.new(0, 36, 1, 0)
		stockLbl.Position = UDim2.new(1, -92, 0, 0)
		stockLbl.BackgroundTransparency = 1
		stockLbl.Text = "x-"
		stockLbl.TextColor3 = COLORS.stockEmpty
		stockLbl.Font = Enum.Font.Code
		stockLbl.TextSize = 10
		stockLbl.TextXAlignment = Enum.TextXAlignment.Right
		stockLbl.Parent = row
		stockLabels[itemName] = stockLbl

		-- Toggle
		local track = Instance.new("Frame")
		track.Size = UDim2.new(0, 34, 0, 17)
		track.Position = UDim2.new(1, -50, 0.5, -8)
		track.BackgroundColor3 = COLORS.accentOff
		track.BorderSizePixel = 0
		track.Parent = row
		Instance.new("UICorner", track).CornerRadius = UDim.new(1, 0)

		local knob = Instance.new("Frame")
		knob.Size = UDim2.new(0, 13, 0, 13)
		knob.Position = UDim2.new(0, 2, 0.5, -6)
		knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		knob.BorderSizePixel = 0
		knob.Parent = track
		Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)

		local clickArea = Instance.new("TextButton")
		clickArea.Size = UDim2.new(1, 0, 1, 0)
		clickArea.BackgroundTransparency = 1
		clickArea.Text = ""
		clickArea.BorderSizePixel = 0
		clickArea.Parent = row

		local entry = { enabled = false, token = 0 }
		autoBuyStates[itemName] = entry

		local function setVisual(on)
			TweenService:Create(track, TweenInfo.new(0.15), {
				BackgroundColor3 = on and COLORS.accentOn or COLORS.accentOff
			}):Play()
			TweenService:Create(knob, TweenInfo.new(0.15), {
				Position = on and UDim2.new(1, -15, 0.5, -6) or UDim2.new(0, 2, 0.5, -6)
			}):Play()
			nameLbl.TextColor3 = on and Color3.fromRGB(150, 240, 170) or COLORS.text
		end

		clickArea.MouseEnter:Connect(function()
			if not entry.enabled then
				TweenService:Create(row, TweenInfo.new(0.1), {
					BackgroundColor3 = COLORS.rowHover
				}):Play()
			end
		end)
		clickArea.MouseLeave:Connect(function()
			if not entry.enabled then
				TweenService:Create(row, TweenInfo.new(0.1), {
					BackgroundColor3 = COLORS.row
				}):Play()
			end
		end)

		clickArea.MouseButton1Click:Connect(function()
			entry.enabled = not entry.enabled
			entry.token += 1
			setVisual(entry.enabled)

			if entry.enabled then
				row.BackgroundColor3 = Color3.fromRGB(30, 45, 38)
				startAutoBuy(itemName, getStockPath(itemName), payloadBuilder)
			else
				row.BackgroundColor3 = COLORS.row
			end
		end)
	end

	setExpanded(true)
	return container
end

-- ===== BUILD SECTIONS =====
makeDropdownSection("Seeds", SEED_LIST, getSeedStockPath, buildSeedPayload)
makeDropdownSection("Gear", GEAR_LIST, getGearStockPath, buildGearPayload)

-- ===== STOCK REFRESH LOOP =====
task.spawn(function()
	while screenGui.Parent do
		-- Update seeds
		for _, seedName in ipairs(SEED_LIST) do
			local label = stockLabels[seedName]
			if label and label.Parent then
				local labelInst = resolvePath(getSeedStockPath(seedName))
				local stock = parseStock(labelInst)
				if stock then
					label.Text = "x" .. stock
					label.TextColor3 = stock > 0 and COLORS.stockOk or COLORS.stockEmpty
				else
					label.Text = "x-"
					label.TextColor3 = COLORS.stockEmpty
				end
			end
		end

		-- Update gear
		for _, gearName in ipairs(GEAR_LIST) do
			local label = stockLabels[gearName]
			if label and label.Parent then
				local labelInst = resolvePath(getGearStockPath(gearName))
				local stock = parseStock(labelInst)
				if stock then
					label.Text = "x" .. stock
					label.TextColor3 = stock > 0 and COLORS.stockOk or COLORS.stockEmpty
				else
					label.Text = "x-"
					label.TextColor3 = COLORS.stockEmpty
				end
			end
		end

		task.wait(1.0)
	end
end)

-- ===== MINIMIZE =====
local isMinimized = false
local FRAME_HEIGHT = 520
local FRAME_HEIGHT_MIN = 32

minBtn.MouseButton1Click:Connect(function()
	isMinimized = not isMinimized
	if isMinimized then
		mainScroll.Visible = false
		frame.Size = UDim2.new(0, 300, 0, FRAME_HEIGHT_MIN)
		minBtn.Text = "+"
	else
		mainScroll.Visible = true
		frame.Size = UDim2.new(0, 300, 0, FRAME_HEIGHT)
		minBtn.Text = "−"
	end
end)

-- ===== CLOSE =====
closeBtn.MouseButton1Click:Connect(function()
	for _, entry in pairs(autoBuyStates) do
		entry.enabled = false
		entry.token += 1
	end
	screenGui:Destroy()
end)

print("[AutoBuyShop] Loaded - Seeds: " .. #SEED_LIST .. " | Gear: " .. #GEAR_LIST)
