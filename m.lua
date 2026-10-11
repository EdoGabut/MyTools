-- ============================================================
-- Crate Tracker (Minimalist)
-- ============================================================
local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
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
local function resolve(parts)
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
	return map
end

local function lookup(map, name)
	if map[name] then return map[name] end
	local target = name:lower():gsub("^%s+", ""):gsub("%s+$", "")
	for k, v in pairs(map) do
		if k:lower():gsub("^%s+", ""):gsub("%s+$", "") == target then
			return v
		end
	end
	return 0
end

-- ============================================================
-- ===== GUI =====
-- ============================================================
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "CrateTracker"
screenGui.ResetOnSpawn = false
screenGui.Parent = player:WaitForChild("PlayerGui")

local COLORS = {
	bg     = Color3.fromRGB(20, 20, 25),
	text   = Color3.fromRGB(235, 235, 240),
	dim    = Color3.fromRGB(130, 130, 145),
	green  = Color3.fromRGB(80, 200, 120),
	red    = Color3.fromRGB(200, 70, 70),
	stroke = Color3.fromRGB(55, 55, 65),
}

local function corner(p, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r or 6)
	c.Parent = p
end

-- ===== MAIN FRAME =====
local frame = Instance.new("Frame")
frame.Size = UDim2.new(0, 200, 0, 26)
frame.Position = UDim2.new(0, 15, 0, 15)
frame.BackgroundColor3 = COLORS.bg
frame.BackgroundTransparency = 0.15
frame.BorderSizePixel = 0
frame.Active = true
frame.Parent = screenGui
corner(frame, 6)

local stroke = Instance.new("UIStroke")
stroke.Color = COLORS.stroke
stroke.Transparency = 0.3
stroke.Parent = frame

-- ===== DRAG =====
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
UIS.InputChanged:Connect(function(input)
	if dragging then
		local d = input.Position - dragStart
		frame.Position = UDim2.new(
			startPos.X.Scale, startPos.X.Offset + d.X,
			startPos.Y.Scale, startPos.Y.Offset + d.Y
		)
	end
end)

-- ===== HEADER (title + toggle + close) =====
local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 26)
header.BackgroundTransparency = 1
header.Parent = frame

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -50, 1, 0)
title.Position = UDim2.new(0, 10, 0, 0)
title.BackgroundTransparency = 1
title.Text = "Crates"
title.TextColor3 = COLORS.dim
title.Font = Enum.Font.GothamMedium
title.TextSize = 11
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = header

-- Toggle button
local toggleBtn = Instance.new("TextButton")
toggleBtn.Size = UDim2.new(0, 16, 0, 16)
toggleBtn.Position = UDim2.new(1, -40, 0, 5)
toggleBtn.BackgroundColor3 = COLORS.green
toggleBtn.Text = ""
toggleBtn.BorderSizePixel = 0
toggleBtn.AutoButtonColor = false
toggleBtn.Parent = header
corner(toggleBtn, 4)

-- Close button
local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 16, 0, 16)
closeBtn.Position = UDim2.new(1, -20, 0, 5)
closeBtn.BackgroundColor3 = COLORS.red
closeBtn.Text = "×"
closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 11
closeBtn.BorderSizePixel = 0
closeBtn.AutoButtonColor = false
closeBtn.Parent = header
corner(closeBtn, 4)

-- ===== BODY (list) =====
local body = Instance.new("Frame")
body.Size = UDim2.new(1, 0, 0, #CRATE_LIST * 18)
body.Position = UDim2.new(0, 0, 0, 26)
body.BackgroundTransparency = 1
body.Parent = frame

local rowLabels = {}

for i, crate in ipairs(CRATE_LIST) do
	local row = Instance.new("TextLabel")
	row.Size = UDim2.new(1, -20, 0, 18)
	row.Position = UDim2.new(0, 10, 0, (i - 1) * 18)
	row.BackgroundTransparency = 1
	row.Text = crate .. " : 0"
	row.TextColor3 = COLORS.dim
	row.Font = Enum.Font.Code
	row.TextSize = 11
	row.TextXAlignment = Enum.TextXAlignment.Left
	row.TextTruncate = Enum.TextTruncate.AtEnd
	row.Parent = body

	rowLabels[crate] = row
end

-- Resize frame tinggi total
local FULL_HEIGHT = 26 + (#CRATE_LIST * 18) + 4
local MIN_HEIGHT = 26

-- ===== REFRESH =====
local function refresh()
	local hotbar = scanContainer(resolve(HOTBAR_PATH))
	local backpack = scanContainer(resolve(BACKPACK_PATH))

	for _, crate in ipairs(CRATE_LIST) do
		local h = lookup(hotbar, crate)
		local b = lookup(backpack, crate)
		local t = h + b

		local lbl = rowLabels[crate]
		lbl.Text = crate .. " : " .. t
		lbl.TextColor3 = (t > 0) and COLORS.green or COLORS.dim
	end
end

-- ===== TOGGLE ON/OFF =====
local active = true

toggleBtn.MouseButton1Click:Connect(function()
	active = not active
	if active then
		toggleBtn.BackgroundColor3 = COLORS.green
		body.Visible = true
		frame.Size = UDim2.new(0, 200, 0, FULL_HEIGHT)
		pcall(refresh)
	else
		toggleBtn.BackgroundColor3 = COLORS.dim
		body.Visible = false
		frame.Size = UDim2.new(0, 200, 0, MIN_HEIGHT)
	end
end)

-- ===== CLOSE (stop execute) =====
closeBtn.MouseButton1Click:Connect(function()
	screenGui:Destroy()
end)

-- ===== MAIN LOOP =====
task.spawn(function()
	while screenGui.Parent do
		if active then pcall(refresh) end
		task.wait(1)
	end
end)

-- ===== INIT =====
pcall(refresh)
print("[Crate Tracker] Loaded")
