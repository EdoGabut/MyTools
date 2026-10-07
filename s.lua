-- LocalScript: Auto Buy Gear (Auto Active)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer

-- ===== REMOTE =====
local remote = ReplicatedStorage:WaitForChild("SharedModules")
	:WaitForChild("Packet"):WaitForChild("RemoteEvent")

-- ===== DATA =====
local GEAR_GROUPS = {
	{
		name = "Watering Can",
		items = {
			"Cider Watering Can",
			"Super Cider Watering Can",
		}
	},
	{
		name = "Sprinkler",
		items = {
			"Common Cider Sprinkler",
			"Uncommon Cider Sprinkler",
			"Rare Cider Sprinkler",
			"Legendary Cider Sprinkler",
			"Super Cider Sprinkler",
		}
	},
	{
		name = "Magic Mail",
		items = {
			"Rare Magic Mail",
			"Legendary Magic Mail",
		}
	},
	{
		name = "Event Gear",
		items = {
			"Candy Basket",
			"Cauldron Charm",
			"Trowel",
		}
	},
}

-- Flat list
local ALL_GEAR = {}
for _, g in ipairs(GEAR_GROUPS) do
	for _, item in ipairs(g.items) do table.insert(ALL_GEAR, item) end
end

-- ===== PAYLOAD =====
local function buildGearPayload(name)
	local len = #name
	if len > 255 then return nil end
	return buffer.fromstring("\206\000" .. string.char(len) .. name)
end

-- ===== PATH =====
local GEAR_BASE = "game.Players.LocalPlayer.PlayerGui.GearShop.Frame.ScrollingFrame"

local function getGearStockPath(name)
	return GEAR_BASE .. "." .. name .. ".Main_Frame.Stock_Text"
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
local C = {
	bg = Color3.fromRGB(18, 18, 20),
	header = Color3.fromRGB(24, 24, 27),
	row = Color3.fromRGB(22, 22, 25),
	rowOn = Color3.fromRGB(24, 44, 32),
	text = Color3.fromRGB(220, 220, 225),
	textOn = Color3.fromRGB(120, 230, 150),
	textDim = Color3.fromRGB(110, 110, 120),
	stockOk = Color3.fromRGB(120, 220, 140),
	accentOn = Color3.fromRGB(70, 200, 120),
	stroke = Color3.fromRGB(48, 48, 56),
	close = Color3.fromRGB(190, 65, 65),
	min = Color3.fromRGB(220, 170, 60),
}

-- ===== GUI =====
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "AutoBuyGear"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Parent = player:WaitForChild("PlayerGui")

local FRAME_W = 240
local FRAME_H = 320

local frame = Instance.new("Frame")
frame.Size = UDim2.new(0, FRAME_W, 0, FRAME_H)
frame.Position = UDim2.new(0, 12, 0.5, -FRAME_H / 2)
frame.BackgroundColor3 = C.bg
frame.BorderSizePixel = 0
frame.Active = true
frame.Draggable = true
frame.Parent = screenGui
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 10)

local stroke = Instance.new("UIStroke")
stroke.Color = C.stroke
stroke.Thickness = 1
stroke.Transparency = 0.3
stroke.Parent = frame

-- Title bar
local titleBar = Instance.new("Frame")
titleBar.Size = UDim2.new(1, 0, 0, 30)
titleBar.BackgroundColor3 = C.header
titleBar.BorderSizePixel = 0
titleBar.Parent = frame
Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 10)

local tbFix = Instance.new("Frame")
tbFix.Size = UDim2.new(1, 0, 0, 8)
tbFix.Position = UDim2.new(0, 0, 1, -8)
tbFix.BackgroundColor3 = C.header
tbFix.BorderSizePixel = 0
tbFix.Parent = titleBar

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -70, 1, 0)
title.Position = UDim2.new(0, 12, 0, 0)
title.BackgroundTransparency = 1
title.Text = "⚙️ Auto Buy Gear"
title.TextColor3 = C.text
title.Font = Enum.Font.GothamBold
title.TextSize = 12
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = titleBar

local minBtn = Instance.new("TextButton")
minBtn.Size = UDim2.new(0, 20, 0, 20)
minBtn.Position = UDim2.new(1, -48, 0, 5)
minBtn.BackgroundColor3 = C.min
minBtn.Text = "−"
minBtn.TextColor3 = Color3.fromRGB(20, 20, 20)
minBtn.Font = Enum.Font.GothamBold
minBtn.TextSize = 13
minBtn.BorderSizePixel = 0
minBtn.AutoButtonColor = false
minBtn.Parent = titleBar
Instance.new("UICorner", minBtn).CornerRadius = UDim.new(0, 5)

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 20, 0, 20)
closeBtn.Position = UDim2.new(1, -26, 0, 5)
closeBtn.BackgroundColor3 = C.close
closeBtn.Text = "×"
closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 14
closeBtn.BorderSizePixel = 0
closeBtn.AutoButtonColor = false
closeBtn.Parent = titleBar
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 5)

-- Scroll
local scroll = Instance.new("ScrollingFrame")
scroll.Size = UDim2.new(1, -12, 1, -40)
scroll.Position = UDim2.new(0, 6, 0, 34)
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 3
scroll.ScrollBarImageColor3 = Color3.fromRGB(70, 70, 85)
scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.Parent = frame

local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 5)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = scroll

-- ===== STATE =====
local stockLabels = {}
local BUY_INTERVAL = 0.5

-- ===== AUTO BUY (LANGSUNG AKTIF) =====
local function startAutoBuy(key, stockPath)
	task.spawn(function()
		while screenGui.Parent do
			local label = resolvePath(stockPath)
			local stock = parseStock(label)
			if stock and stock > 0 then
				local payload = buildGearPayload(key)
				if payload then
					pcall(function() remote:FireServer(payload) end)
				end
			end
			task.wait(BUY_INTERVAL)
		end
	end)
end

-- ===== BUILD GROUP =====
local function makeGroup(groups, baseLayoutOrder)
	local outerOrder = baseLayoutOrder

	for _, group in ipairs(groups) do
		outerOrder += 1

		local wrapper = Instance.new("Frame")
		wrapper.Size = UDim2.new(1, -2, 0, 20)
		wrapper.BackgroundTransparency = 1
		wrapper.AutomaticSize = Enum.AutomaticSize.Y
		wrapper.LayoutOrder = outerOrder
		wrapper.Parent = scroll

		local wLayout = Instance.new("UIListLayout")
		wLayout.Padding = UDim.new(0, 2)
		wLayout.SortOrder = Enum.SortOrder.LayoutOrder
		wLayout.Parent = wrapper

		-- Group header
		local gh = Instance.new("TextLabel")
		gh.Size = UDim2.new(1, 0, 0, 18)
		gh.BackgroundTransparency = 1
		gh.Text = "  " .. group.name
		gh.TextColor3 = C.textDim
		gh.Font = Enum.Font.GothamBold
		gh.TextSize = 9
		gh.TextXAlignment = Enum.TextXAlignment.Left
		gh.LayoutOrder = 0
		gh.Parent = wrapper

		-- Baris item
		local rowIndex = 0
		for _, itemName in ipairs(group.items) do
			rowIndex += 1

			local row = Instance.new("Frame")
			row.Size = UDim2.new(1, 0, 0, 26)
			row.BackgroundColor3 = C.rowOn  -- ⬅️ langsung hijau (aktif)
			row.BorderSizePixel = 0
			row.LayoutOrder = rowIndex
			row.Parent = wrapper
			Instance.new("UICorner", row).CornerRadius = UDim.new(0, 5)

			-- Nama
			local displayName = itemName
				:gsub("^Cider ", "")
				:gsub("^Super Cider ", "Super ")
				:gsub(" Cider Sprinkler", " Sprinkler")
				:gsub(" Cider Watering Can", " Watering Can")

			local nameLbl = Instance.new("TextLabel")
			nameLbl.Size = UDim2.new(1, -60, 1, 0)
			nameLbl.Position = UDim2.new(0, 10, 0, 0)
			nameLbl.BackgroundTransparency = 1
			nameLbl.Text = displayName
			nameLbl.TextColor3 = C.textOn  -- ⬅️ hijau (aktif)
			nameLbl.Font = Enum.Font.Gotham
			nameLbl.TextSize = 10
			nameLbl.TextXAlignment = Enum.TextXAlignment.Left
			nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
			nameLbl.Parent = row

			-- Stock label
			local stockLbl = Instance.new("TextLabel")
			stockLbl.Size = UDim2.new(0, 40, 1, 0)
			stockLbl.Position = UDim2.new(1, -50, 0, 0)
			stockLbl.BackgroundTransparency = 1
			stockLbl.Text = "-"
			stockLbl.TextColor3 = C.textDim
			stockLbl.Font = Enum.Font.Code
			stockLbl.TextSize = 9
			stockLbl.TextXAlignment = Enum.TextXAlignment.Right
			stockLbl.Parent = row
			stockLabels[itemName] = stockLbl

			-- 🔥 LANGSUNG AUTO BUY
			startAutoBuy(itemName, getGearStockPath(itemName))
		end
	end
end

-- ===== BUILD =====
makeGroup(GEAR_GROUPS, 0)

-- ===== STOCK REFRESH =====
task.spawn(function()
	while screenGui.Parent do
		for _, name in ipairs(ALL_GEAR) do
			local lbl = stockLabels[name]
			if lbl and lbl.Parent then
				local inst = resolvePath(getGearStockPath(name))
				local s = parseStock(inst)
				if s then
					lbl.Text = tostring(s)
					lbl.TextColor3 = s > 0 and C.stockOk or C.textDim
				else
					lbl.Text = "-"
					lbl.TextColor3 = C.textDim
				end
			end
		end
		task.wait(1.0)
	end
end)

-- ===== MINIMIZE =====
local isMin = false
minBtn.MouseButton1Click:Connect(function()
	isMin = not isMin
	if isMin then
		scroll.Visible = false
		frame.Size = UDim2.new(0, FRAME_W, 0, 30)
		minBtn.Text = "+"
	else
		scroll.Visible = true
		frame.Size = UDim2.new(0, FRAME_W, 0, FRAME_H)
		minBtn.Text = "−"
	end
end)

-- ===== CLOSE =====
closeBtn.MouseButton1Click:Connect(function()
	screenGui:Destroy()
end)

print("[AutoBuyGear] Loaded | Auto Active | Gear: " .. #ALL_GEAR)
