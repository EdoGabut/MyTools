-- ============================================================
-- Crate Tracker + Auto Cycle
-- ============================================================
local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local RS = game:GetService("ReplicatedStorage")
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

-- Cycle config
local CYCLE_DELAY    = 5       -- jeda antar crate (detik)
local MAX_FIRE       = 30      -- total fire sebelum cooldown
local COOLDOWN_TIME  = 2 * 60 * 60  -- 2 jam (detik)

-- Packet payload per crate
local PACKETS = {
	["Gravestone Crate"] = buffer.fromstring(
		"\133\001$\015Rare Magic Mail\006Crates\016Gravestone Crate\000\000\000\000\000\000\240?"
	),
	["Halloween Prop Crate"] = buffer.fromstring(
		"\133\001i\015Rare Magic Mail\006Crates\020Halloween Prop Crate\000\000\000\000\000\000\240?"
	),
	["Fog Machine Crate"] = buffer.fromstring(
		"\133\0013\020Legendary Magic Mail\006Crates\017Fog Machine Crate\000\000\000\000\000\000\240?"
	),
}

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

local function getCount(crate)
	local h = scanContainer(resolve(HOTBAR_PATH))
	local b = scanContainer(resolve(BACKPACK_PATH))
	return lookup(h, crate) + lookup(b, crate)
end

-- ===== REMOTE =====
local function getRemote()
	local ok, remote = pcall(function()
		return RS:WaitForChild("SharedModules", 10)
			:WaitForChild("Packet", 10)
			:WaitForChild("RemoteEvent", 10)
	end)
	if ok then return remote end
	return nil
end

local function fireCrate(crate)
	local packet = PACKETS[crate]
	if not packet then return false end
	local remote = getRemote()
	if not remote then return false end
	local ok = pcall(function()
		remote:FireServer(packet)
	end)
	return ok
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
	orange = Color3.fromRGB(230, 160, 60),
	stroke = Color3.fromRGB(55, 55, 65),
}

local function corner(p, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r or 6)
	c.Parent = p
end

-- ===== MAIN FRAME =====
local frame = Instance.new("Frame")
frame.Size = UDim2.new(0, 220, 0, 26)
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

-- ===== HEADER =====
local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 26)
header.BackgroundTransparency = 1
header.Parent = frame

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -70, 1, 0)
title.Position = UDim2.new(0, 10, 0, 0)
title.BackgroundTransparency = 1
title.Text = "Crates"
title.TextColor3 = COLORS.dim
title.Font = Enum.Font.GothamMedium
title.TextSize = 11
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = header

-- Toggle button (scan on/off)
local toggleBtn = Instance.new("TextButton")
toggleBtn.Size = UDim2.new(0, 16, 0, 16)
toggleBtn.Position = UDim2.new(1, -60, 0, 5)
toggleBtn.BackgroundColor3 = COLORS.green
toggleBtn.Text = ""
toggleBtn.BorderSizePixel = 0
toggleBtn.AutoButtonColor = false
toggleBtn.Parent = header
corner(toggleBtn, 4)

-- Cycle button (auto fire on/off)
local cycleBtn = Instance.new("TextButton")
cycleBtn.Size = UDim2.new(0, 16, 0, 16)
cycleBtn.Position = UDim2.new(1, -40, 0, 5)
cycleBtn.BackgroundColor3 = COLORS.dim
cycleBtn.Text = ""
cycleBtn.BorderSizePixel = 0
cycleBtn.AutoButtonColor = false
cycleBtn.Parent = header
corner(cycleBtn, 4)

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

-- ===== BODY =====
local body = Instance.new("Frame")
body.Size = UDim2.new(1, 0, 0, (#CRATE_LIST * 18) + 30)
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

-- Status line
local statusLbl = Instance.new("TextLabel")
statusLbl.Size = UDim2.new(1, -20, 0, 16)
statusLbl.Position = UDim2.new(0, 10, 0, #CRATE_LIST * 18 + 6)
statusLbl.BackgroundTransparency = 1
statusLbl.Text = "Fire: 0 / " .. MAX_FIRE .. "  |  IDLE"
statusLbl.TextColor3 = COLORS.dim
statusLbl.Font = Enum.Font.Code
statusLbl.TextSize = 10
statusLbl.TextXAlignment = Enum.TextXAlignment.Left
statusLbl.Parent = body

local FULL_HEIGHT = 26 + (#CRATE_LIST * 18) + 30
local MIN_HEIGHT = 26

-- ============================================================
-- ===== STATE =====
-- ============================================================
local scanActive = true
local cycleActive = false
local fireCount = 0
local cooldownUntil = 0  -- os.clock() target
local currentIndex = 1   -- index crate yang sedang diproses

-- ============================================================
-- ===== REFRESH =====
-- ============================================================
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

-- ============================================================
-- ===== STATUS UPDATE =====
-- ============================================================
local function updateStatus()
	if os.clock() < cooldownUntil then
		local remaining = math.floor(cooldownUntil - os.clock())
		local h = math.floor(remaining / 3600)
		local m = math.floor((remaining % 3600) / 60)
		local s = remaining % 60
		statusLbl.Text = string.format("COOLDOWN: %02d:%02d:%02d", h, m, s)
		statusLbl.TextColor3 = COLORS.orange
	elseif cycleActive then
		local crate = CRATE_LIST[currentIndex] or "?"
		statusLbl.Text = string.format("Fire: %d/%d  |  %s", fireCount, MAX_FIRE, crate)
		statusLbl.TextColor3 = COLORS.green
	else
		statusLbl.Text = string.format("Fire: %d/%d  |  IDLE", fireCount, MAX_FIRE)
		statusLbl.TextColor3 = COLORS.dim
	end
end

-- ============================================================
-- ===== CYCLE LOOP =====
-- ============================================================
task.spawn(function()
	while screenGui.Parent do
		if cycleActive and os.clock() >= cooldownUntil then
			-- Reset fireCount kalau udah lewat cooldown
			if fireCount >= MAX_FIRE then
				fireCount = 0
			end

			-- Cek apakah semua crate kosong
			local anyAvail = false
			for _, crate in ipairs(CRATE_LIST) do
				if getCount(crate) > 0 then
					anyAvail = true
					break
				end
			end

			if not anyAvail then
				statusLbl.Text = "NO CRATES  |  WAITING..."
				statusLbl.TextColor3 = COLORS.orange
				task.wait(2)
			else
				local crate = CRATE_LIST[currentIndex]

				if getCount(crate) > 0 then
					-- Fire!
					local ok = fireCrate(crate)
					if ok then
						fireCount = fireCount + 1
						updateStatus()
					end

					-- Cek batas fire
					if fireCount >= MAX_FIRE then
						cooldownUntil = os.clock() + COOLDOWN_TIME
						updateStatus()
						task.wait(1)
					else
						-- Lanjut ke crate berikutnya setelah jeda
						currentIndex = currentIndex % #CRATE_LIST + 1
						task.wait(CYCLE_DELAY)
					end
				else
					-- Skip crate kosong, lanjut ke berikutnya tanpa jeda panjang
					currentIndex = currentIndex % #CRATE_LIST + 1
					task.wait(0.5)
				end
			end
		else
			updateStatus()
			task.wait(1)
		end
	end
end)

-- ============================================================
-- ===== BUTTON HANDLERS =====
-- ============================================================
toggleBtn.MouseButton1Click:Connect(function()
	scanActive = not scanActive
	if scanActive then
		toggleBtn.BackgroundColor3 = COLORS.green
		body.Visible = true
		frame.Size = UDim2.new(0, 220, 0, FULL_HEIGHT)
		pcall(refresh)
	else
		toggleBtn.BackgroundColor3 = COLORS.dim
		body.Visible = false
		frame.Size = UDim2.new(0, 220, 0, MIN_HEIGHT)
	end
end)

cycleBtn.MouseButton1Click:Connect(function()
	cycleActive = not cycleActive
	if cycleActive then
		cycleBtn.BackgroundColor3 = COLORS.green
		fireCount = 0
		currentIndex = 1
		cooldownUntil = 0
		updateStatus()
	else
		cycleBtn.BackgroundColor3 = COLORS.dim
		updateStatus()
	end
end)

closeBtn.MouseButton1Click:Connect(function()
	screenGui:Destroy()
end)

-- ============================================================
-- ===== SCAN LOOP =====
-- ============================================================
task.spawn(function()
	while screenGui.Parent do
		if scanActive then pcall(refresh) end
		task.wait(1)
	end
end)

-- ===== INIT =====
pcall(refresh)
updateStatus()
print("[Crate Tracker] Loaded")
