-- ============================================================
-- Crate Tracker
-- Cek jumlah crate di hotbar + backpack
-- ============================================================
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

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
end

local FRAME_WIDTH = 280
local FRAME_HEIGHT = 220
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
game:GetService("UserInputService").InputChanged:Connect(function(input)
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
title
