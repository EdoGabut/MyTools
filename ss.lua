-- LocalScript: Auto Buy Gear + Seeds (Log Only) + Toggle Seeds
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
	"Super Cider Watering Can",
	"Common Cider Sprinkler",
	"Uncommon Cider Sprinkler",
	"Rare Cider Sprinkler",
	"Legendary Cider Sprinkler",
	"Super Cider Sprinkler",
	"Rare Magic Mail",
	"Legendary Magic Mail",
	"Candy Basket",
	"Cauldron Charm",
	"Trowel",
}

local SEED_LIST = {
	"Spirit Carrot",
	"Spirit Tulip",
	"Great Pumpkin",
	"Vampire Bloom",
}

-- ===== PAYLOAD =====
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

-- ===== PATH =====
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

local function logBought(kind, name, stockBefore)
	print(string.format("[BUY] %s | %s | stok terakhir: %d", kind, name, stockBefore))
end

-- ===== COLORS =====
local C = {
	bg = Color3.fromRGB(18, 18, 20),
	header = Color3.fromRGB(24, 24, 27),
	text = Color3.fromRGB(220, 220, 225),
	textDim = Color3.fromRGB(110, 110, 120),
	green = Color3.fromRGB(80, 200, 120),
	red = Color3.fromRGB(190, 65, 65),
	stroke = Color3.fromRGB(48, 48, 56),
	close = Color3.fromRGB(190, 65, 65),
	min = Color3.fromRGB(220, 170, 60),
}

-- ===== GUI =====
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "AutoBuyMini"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Parent = player:WaitForChild("PlayerGui")

local FRAME_W = 220
local FRAME_H = 62

local frame = Instance.new("Frame")
frame.Size = UDim2.new(0, FRAME_W, 0, FRAME_H)
frame.Position = UDim2.new(0, 12, 0, 60)
frame.BackgroundColor3 = C.bg
frame.BorderSizePixel = 0
frame.Active = true
frame.Draggable = true
frame.Parent = screenGui
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)

local stroke = Instance.new("UIStroke")
stroke.Color = C.stroke
stroke.Thickness = 1
stroke.Transparency = 0.3
stroke.Parent = frame

-- Title bar
local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -50, 0, 26)
title.Position = UDim2.new(0, 10, 0, 0)
title.BackgroundTransparency = 1
title.Text = "⚙️ Auto Buy (Log)"
title.TextColor3 = C.text
title.Font = Enum.Font.GothamBold
title.TextSize = 11
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = frame

-- Dot indicator (status gear - selalu ON)
local dot = Instance.new("Frame")
dot.Size = UDim2.new(0, 8, 0, 8)
dot.Position = UDim2.new(1, -46, 0, 9)
dot.BackgroundColor3 = C.green
dot.BorderSizePixel = 0
dot.Parent = frame
Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 18, 0, 18)
closeBtn.Position = UDim2.new(1, -24, 0, 4)
closeBtn.BackgroundColor3 = C.close
closeBtn.Text = "×"
closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 13
closeBtn.BorderSizePixel = 0
closeBtn.AutoButtonColor = false
closeBtn.Parent = frame
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 4)

-- Toggle SEED ON/OFF
local seedToggle = Instance.new("TextButton")
seedToggle.Size = UDim2.new(1, -16, 0, 26)
seedToggle.Position = UDim2.new(0, 8, 0, 30)
seedToggle.BackgroundColor3 = C.green
seedToggle.Text = "🌱 SEED: ON"
seedToggle.TextColor3 = Color3.fromRGB(255, 255, 255)
seedToggle.Font = Enum.Font.GothamBold
seedToggle.TextSize = 11
seedToggle.BorderSizePixel = 0
seedToggle.AutoButtonColor = false
seedToggle.Parent = frame
Instance.new("UICorner", seedToggle).CornerRadius = UDim.new(0, 6)

-- ===== AUTO BUY =====
local BUY_INTERVAL = 0.5
local lastStock = {}  -- [key] = stok terakhir (biar tidak spam log)

local seedEnabled = true   -- flag ON/OFF untuk seed

local function startAutoBuy(key, kind, stockPath, payloadBuilder, isEnabledFn)
	task.spawn(function()
		while screenGui.Parent do
			if isEnabledFn() then
				local label = resolvePath(stockPath)
				local stock = parseStock(label)

				if stock and stock > 0 then
					local payload = payloadBuilder(key)
					if payload then
						local ok = pcall(function() remote:FireServer(payload) end)
						if ok then
							if lastStock[key] ~= stock then
								lastStock[key] = stock
								logBought(kind, key, stock)
							end
						end
					end
				else
					if stock == 0 then lastStock[key] = nil end
				end
			end

			task.wait(BUY_INTERVAL)
		end
	end)
end

-- ===== START ALL =====
print("=====================================")
print("[AutoBuy] Starting...")
print(string.format("[AutoBuy] Gear: %d | Seeds: %d", #GEAR_LIST, #SEED_LIST))
print("=====================================")

-- Gear (selalu ON)
for _, name in ipairs(GEAR_LIST) do
	startAutoBuy(name, "GEAR", getGearStockPath(name), buildGearPayload, function()
		return true
	end)
end

-- Seeds (bisa di-toggle)
for _, name in ipairs(SEED_LIST) do
	startAutoBuy(name, "SEED", getSeedStockPath(name), buildSeedPayload, function()
		return seedEnabled
	end)
end

-- ===== TOGGLE LOGIC =====
seedToggle.MouseButton1Click:Connect(function()
	seedEnabled = not seedEnabled
	if seedEnabled then
		seedToggle.Text = "🌱 SEED: ON"
		seedToggle.BackgroundColor3 = C.green
		print("[AutoBuy] Seed auto-buy: ON")
	else
		seedToggle.Text = "🌱 SEED: OFF"
		seedToggle.BackgroundColor3 = C.red
		print("[AutoBuy] Seed auto-buy: OFF")
	end
end)

-- ===== CLOSE =====
closeBtn.MouseButton1Click:Connect(function()
	screenGui:Destroy()
	print("[AutoBuy] Stopped.")
end)

print("[AutoBuy] Loaded | Aktif. Klik toggle buat ON/OFF seed.")
