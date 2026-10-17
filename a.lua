-- ============================================
-- ALL-IN-ONE v2: WATER + SPRINKLE + AUCTION
-- Minimalis, satu GUI, section terpisah
-- ============================================

local CoreGui           = game:GetService("CoreGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local Lighting          = game:GetService("Lighting")

local LP = Players.LocalPlayer
local Packet = ReplicatedStorage:WaitForChild("SharedModules")
	:WaitForChild("Packet"):WaitForChild("RemoteEvent")

local ROOT = workspace:WaitForChild("Gardens")

-- ==================================================================
-- BAGIAN 1: WATER + SPRINKLE CONFIG
-- ==================================================================

local WATER_TOOL_NAME    = "Cider Watering Can"
local SPRINKLE_TOOL_NAME = "Rare Cider Sprinkler"
local WATER_PREFIX       = "j"
local SPRINKLE_PREFIX    = "8"
local CHECK_INTERVAL     = 5
local SPRINKLE_SETTLE    = 1.0
local REC_COUNTDOWN      = 3   -- detik countdown sebelum record

local wState = {
	recordingWater    = false,
	recordingSprinkle = false,
	countingWater     = false,
	countingSprinkle  = false,
	waterPayload      = nil,
	sprinklePayload   = nil,
	hasWater          = false,
	hasSprinkle       = false,
	wateringOn        = false,
	sprinkleOn        = false,
	busySprinkle      = false,
}

local ALIVE = true

-- ==================================================================
-- BAGIAN 2: AUCTION CONFIG
-- ==================================================================

local TARGETS = {
	{ name = "Cider Watering Can",       threshold = 180, label = "CWC"  },  -- 5 menit
	{ name = "Spirit Mushroom",          threshold = 60,  label = "SM"   },
	{ name = "Super Cider Watering Can", threshold = 20,  label = "SCWC" },
	{ name = "Super Cider Sprinkler",    threshold = 20,  label = "SCS"  },
}

local MONEY_LOT_COUNT    = 6
local AUTO_FIRE_INTERVAL = 6
local OFFSCREEN_OFFSET   = 5000

local AUCTION_PATH       = string.format("game.Players.%s.PlayerGui.Auction", LP.Name)
local SCROLLFRAME_PATH   = string.format("game.Players.%s.PlayerGui.Auction.Frame.ScrollingFrame", LP.Name)

local masterEnabled = false
local itemData = {}
local heartbeatConn = nil
local isShutdown = false
local auctionKeepAliveConn = nil
local auctionPosConn = nil

-- ==================================================================
-- UTIL
-- ==================================================================

local function resolvePath(pathStr)
	pathStr = pathStr:gsub("^%s+", ""):gsub("%s+$", "")
	local segments = {}
	for seg in pathStr:gmatch("[^%.]+") do table.insert(segments, seg) end
	if #segments == 0 or segments[1] ~= "game" then return nil end
	table.remove(segments, 1)
	local node = game
	for _, seg in ipairs(segments) do
		if not node then return nil end
		if seg == "LocalPlayer" then node = LP
		elseif seg == "Players" then node = game:GetService("Players")
		elseif seg == "Workspace" then node = workspace
		elseif seg == "CoreGui" then node = game:GetService("CoreGui")
		elseif seg == "ReplicatedStorage" then node = game:GetService("ReplicatedStorage")
		else
			if node == game:GetService("Players") and seg == LP.Name then
				node = LP
			else
				node = node:FindFirstChild(seg)
			end
		end
	end
	return node
end

local function extractLotIndex(name)
	local ts, idx = name:match(":(%d+):(%d+)$")
	if ts and idx then return tonumber(idx), tonumber(ts) end
	local idx2 = name:match(":(%d+)$")
	return tonumber(idx2 or 0), 0
end

local function lotNameToId(lotName) return lotName:gsub("^Lot_", "") end

local function parseTimer(text)
	if not text or text == "" then return nil end
	local h, m, s = text:match("(%d+)h%s*(%d+)m%s*(%d+)s")
	if h and m and s then return tonumber(h)*3600 + tonumber(m)*60 + tonumber(s) end
	local m2, s2 = text:match("(%d+)m%s*(%d+)s")
	if m2 and s2 then return tonumber(m2)*60 + tonumber(s2) end
	local s3 = text:match("(%d+)s")
	if s3 then return tonumber(s3) end
	return nil
end

local function formatTimer(sec)
	if not sec then return "—" end
	if sec <= 0 then return "EXP" end
	local m = math.floor(sec / 60)
	local s = sec % 60
	return string.format("%d:%02d", m, s)
end

local function normalizeName(s)
	if not s then return "" end
	s = s:lower():gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
	return s
end

-- ==================================================================
-- WATER/SPRINKLE: PLOT DETECTION
-- ==================================================================

local MY_PLOT_NAME = nil

local function detectMyPlot()
	local mySign = LP.DisplayName .. "'s Garden"
	for _, plot in ipairs(ROOT:GetChildren()) do
		local signs = plot:FindFirstChild("Signs")
		if signs then
			local garden = signs:FindFirstChild("Garden")
			local core = garden and garden:FindFirstChild("CorePart")
			local sg = core and core:FindFirstChild("SurfaceGui")
			local playerLbl = sg and sg:FindFirstChild("Player")
			local textLbl = playerLbl and playerLbl:FindFirstChild("TextLabel")
			if textLbl and textLbl.Text == mySign then
				MY_PLOT_NAME = plot.Name
				print("✅ Plot terdeteksi:", MY_PLOT_NAME)
				return MY_PLOT_NAME
			end
		end
	end
	return nil
end

local function getMyPlot()
	if not MY_PLOT_NAME or not ROOT:FindFirstChild(MY_PLOT_NAME) then
		MY_PLOT_NAME = nil
		detectMyPlot()
	end
	return MY_PLOT_NAME and ROOT:FindFirstChild(MY_PLOT_NAME) or nil
end

detectMyPlot()

-- ==================================================================
-- SMART EQUIP
-- ==================================================================

local function ensureToolEquipped(toolName)
	local char = LP.Character or LP.CharacterAdded:Wait()
	if not char then return nil end
	local equipped = char:FindFirstChild(toolName)
	if equipped then return equipped end
	local backpack = LP:FindFirstChild("Backpack")
	if not backpack then return nil end
	local tool = backpack:FindFirstChild(toolName)
	if not tool then return nil end
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not humanoid then return nil end
	local ok = pcall(function() humanoid:EquipTool(tool) end)
	if not ok then return nil end
	local t0 = os.clock()
	while os.clock() - t0 < 0.5 do
		task.wait(0.05)
		local eq = char:FindFirstChild(toolName)
		if eq then return eq end
	end
	return char:FindFirstChild(toolName)
end

-- ==================================================================
-- WATER/SPRINKLE: SPRINKLER CHECK
-- ==================================================================

local function hasActiveSprinkler()
	local plot = getMyPlot()
	if not plot then return false, 0 end
	local sprinklers = plot:FindFirstChild("Sprinklers")
	if sprinklers then
		local n = #sprinklers:GetChildren()
		return n > 0, n
	end
	return false, 0
end

-- ==================================================================
-- HOOK (RECORDING)
-- ==================================================================

local hookActive = false
local originalNamecall = nil
local hookedMeta = nil

local function installHook()
	if hookActive then return end
	local ok = pcall(function()
		hookedMeta = getrawmetatable(game)
		if not hookedMeta then error("no metatable") end
		originalNamecall = hookedMeta.__namecall
		if not originalNamecall then error("no __namecall") end
		setreadonly(hookedMeta, false)
		hookedMeta.__namecall = newcclosure(function(self, ...)
			local method = getnamecallmethod()
			if method == "FireServer"
				and typeof(self) == "Instance"
				and self.ClassName == "RemoteEvent" then
				local args = {...}
				for _, v in ipairs(args) do
					if typeof(v) == "buffer" then
						local okStr, str = pcall(function()
							return buffer.readstring(v, 0, buffer.len(v))
						end)
						if okStr and str and #str > 0 then
							local prefix = str:sub(1, 1)
							if prefix == WATER_PREFIX and wState.recordingWater then
								wState.waterPayload = v
								wState.hasWater = true
								wState.recordingWater = false
								_G.__waterRecorded = true
							end
							if prefix == SPRINKLE_PREFIX and wState.recordingSprinkle then
								wState.sprinklePayload = v
								wState.hasSprinkle = true
								wState.recordingSprinkle = false
								_G.__sprinkleRecorded = true
							end
						end
					end
				end
			end
			return originalNamecall(self, ...)
		end)
		setreadonly(hookedMeta, true)
		hookActive = true
	end)
	if not ok then warn("❌ Hook gagal install") end
end

local function uninstallHook()
	if not hookActive then return end
	pcall(function()
		setreadonly(hookedMeta, false)
		hookedMeta.__namecall = originalNamecall
		setreadonly(hookedMeta, true)
	end)
	hookActive = false
end

-- ==================================================================
-- WATER/SPRINKLE: FIRE
-- ==================================================================

local function fireWater()
	if not ALIVE or not wState.waterPayload then return false end
	local char = LP.Character
	if not char then return false end
	local equipped = char:FindFirstChild(WATER_TOOL_NAME)
	if not equipped then
		equipped = ensureToolEquipped(WATER_TOOL_NAME)
		if not equipped then return false end
		task.wait(0.1)
	end
	return pcall(function() Packet:FireServer(wState.waterPayload, {equipped}) end)
end

local function fireSprinkle()
	if not ALIVE or not wState.sprinklePayload then return false end
	local char = LP.Character
	if not char then return false end
	local equipped = char:FindFirstChild(SPRINKLE_TOOL_NAME)
	if not equipped then
		equipped = ensureToolEquipped(SPRINKLE_TOOL_NAME)
		if not equipped then return false end
		task.wait(0.15)
	end
	return pcall(function() Packet:FireServer(wState.sprinklePayload, {equipped}) end)
end

-- ==================================================================
-- AUCTION: LOT STATUS
-- ==================================================================

local function getLotStatus(lot)
	local outOfStock, expired, timerText = nil, nil, nil
	for _, obj in ipairs(lot:GetDescendants()) do
		if obj:IsA("Frame") then
			if obj.Name == "OUT_OF_STOCK" then outOfStock = obj end
			if obj.Name == "EXPIRED" then expired = obj end
		elseif obj:IsA("TextLabel") and obj.Name == "Timer" and not timerText then
			timerText = obj.Text
		end
	end
	local timerSec = parseTimer(timerText)
	if outOfStock and outOfStock.Visible then return "SOLD_OUT", timerSec, timerText end
	if expired and expired.Visible then return "EXPIRED", timerSec, timerText end
	if timerSec and timerSec <= 0 then return "EXPIRED", timerSec, timerText end
	return "AVAILABLE", timerSec, timerText
end

local function buildPayload(lotId, timestamp)
	local totalLen = 2 + 1 + #lotId + 3 + 8
	local buf = buffer.create(totalLen)
	local pos = 0
	buffer.writeu8(buf, pos, 0xDD); pos += 1
	buffer.writeu8(buf, pos, 0x01); pos += 1
	buffer.writeu8(buf, pos, 0x20); pos += 1
	for i = 1, #lotId do
		buffer.writeu8(buf, pos, string.byte(lotId, i)); pos += 1
	end
	buffer.writeu8(buf, pos, 0x00); pos += 1
	buffer.writeu8(buf, pos, 0x00); pos += 1
	buffer.writeu8(buf, pos, 0x00); pos += 1
	buffer.writef64(buf, pos, timestamp); pos += 8
	return buf
end

local function fireAuctionPayload(lotData)
	local payload = buildPayload(lotData.lotId, lotData.timestamp)
	return pcall(function() Packet:FireServer(payload) end)
end

-- ==================================================================
-- AUCTION: OFF-SCREEN
-- ==================================================================

local function setupAuctionOffScreen()
	local auction = resolvePath(AUCTION_PATH)
	if not auction then return false end
	pcall(function() auction.Enabled = true end)
	pcall(function() auction.DisplayOrder = -1000 end)
	local mainFrame = auction:FindFirstChild("Frame")
	if mainFrame then
		pcall(function()
			mainFrame:SetAttribute("_AutoBuyOrigPos", mainFrame.Position)
			mainFrame.Position = UDim2.new(0, OFFSCREEN_OFFSET, 0, 0)
			mainFrame.Visible = true
		end)
		auctionPosConn = mainFrame:GetPropertyChangedSignal("Position"):Connect(function()
			if isShutdown then return end
			pcall(function()
				if mainFrame.Position.X.Offset ~= OFFSCREEN_OFFSET then
					mainFrame.Position = UDim2.new(0, OFFSCREEN_OFFSET, 0, 0)
				end
			end)
		end)
	end
	auctionKeepAliveConn = auction:GetPropertyChangedSignal("Enabled"):Connect(function()
		if isShutdown then return end
		pcall(function()
			if auction.Parent and not auction.Enabled then auction.Enabled = true end
		end)
	end)
	return true
end

local function restoreAuction()
	if auctionPosConn then auctionPosConn:Disconnect() auctionPosConn = nil end
	if auctionKeepAliveConn then auctionKeepAliveConn:Disconnect() auctionKeepAliveConn = nil end
	local auction = resolvePath(AUCTION_PATH)
	if auction then
		local mainFrame = auction:FindFirstChild("Frame")
		if mainFrame then
			local origPos = mainFrame:GetAttribute("_AutoBuyOrigPos")
			if origPos then pcall(function() mainFrame.Position = origPos end) end
		end
	end
end

-- ==================================================================
-- AUCTION: SCAN
-- ==================================================================

local normalizedTargets = {}
for _, tgt in ipairs(TARGETS) do
	normalizedTargets[tgt.name] = normalizeName(tgt.name)
end

local updateAuctionUIRow  -- forward declaration

local function scanAuction()
	if isShutdown then return end
	local root = resolvePath(SCROLLFRAME_PATH)
	if not root then return end

	for _, tgt in ipairs(TARGETS) do
		itemData[tgt.name].match = nil
	end

	for _, child in ipairs(root:GetChildren()) do
		if child.Name:match("^Lot_") then
			local idx, ts = extractLotIndex(child.Name)
			if idx and idx < MONEY_LOT_COUNT then
				local itemName = nil
				for _, obj in ipairs(child:GetDescendants()) do
					if obj:IsA("TextLabel") and obj.Name == "ItemName" then
						itemName = obj.Text
						break
					end
				end
				if itemName then
					local normalized = normalizeName(itemName)
					for _, tgt in ipairs(TARGETS) do
						if normalized == normalizedTargets[tgt.name] then
							local status, timerSec = getLotStatus(child)
							itemData[tgt.name].match = {
								lotName = child.Name,
								lotId = lotNameToId(child.Name),
								timestamp = ts,
								lotIndex = idx,
								actualItem = itemName,
								status = status,
								timerSec = timerSec,
							}
						end
					end
				end
			end
		end
	end

	updateAuctionUIRow()
end

-- ==================================================================
-- AUCTION: AUTO-FIRE
-- ==================================================================

local function autoFireCheck()
	if isShutdown or not masterEnabled then return end
	local now = os.clock()
	for _, tgt in ipairs(TARGETS) do
		local d = itemData[tgt.name]
		if d.match then
			local m = d.match
			local isExpired = (not m.timerSec) or m.timerSec <= 0
				or m.status == "EXPIRED" or m.status == "SOLD_OUT"
			if not isExpired then
				local timerOk = (tgt.threshold == 0) or (m.timerSec and m.timerSec <= tgt.threshold)
				if timerOk and (now - d.lastFire) >= AUTO_FIRE_INTERVAL then
					d.lastFire = now
					pcall(function() fireAuctionPayload(m) end)
				end
			end
		end
	end
end

-- ==================================================================
-- WATER/SPRINKLE: SHUTDOWN
-- ==================================================================

local function shutdown(reason)
	if not ALIVE then return end
	ALIVE = false
	isShutdown = true
	wState.wateringOn = false
	wState.sprinkleOn = false
	uninstallHook()
	restoreAuction()
	if reason then print("🛑 Shutdown:", reason) end
end

-- ==================================================================
-- GUI UNIFIED
-- ==================================================================

local old = CoreGui:FindFirstChild("WaterAuctionGui")
if old then old:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "WaterAuctionGui"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 9999
gui.Parent = CoreGui

local FULL_H = 300
local MINI_H = 28

local main = Instance.new("Frame")
main.Size = UDim2.new(0, 200, 0, FULL_H)
main.Position = UDim2.new(0, 20, 0, 60)
main.BackgroundColor3 = Color3.fromRGB(22, 22, 28)
main.BorderSizePixel = 0
main.Active = true
main.Draggable = true
main.Parent = gui
Instance.new("UICorner", main).CornerRadius = UDim.new(0, 10)

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(48, 48, 58)
stroke.Thickness = 1
stroke.Parent = main

-- Header
local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 28)
header.BackgroundColor3 = Color3.fromRGB(38, 38, 50)
header.BorderSizePixel = 0
header.Parent = main
Instance.new("UICorner", header).CornerRadius = UDim.new(0, 10)

local headerFix = Instance.new("Frame")
headerFix.Size = UDim2.new(1, 0, 0, 10)
headerFix.Position = UDim2.new(0, 0, 1, -10)
headerFix.BackgroundColor3 = Color3.fromRGB(38, 38, 50)
headerFix.BorderSizePixel = 0
headerFix.Parent = header

local minBtn = Instance.new("TextButton")
minBtn.Size = UDim2.new(0, 20, 0, 20)
minBtn.Position = UDim2.new(0, 4, 0, 4)
minBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 75)
minBtn.Text = "—"
minBtn.TextColor3 = Color3.fromRGB(230, 230, 240)
minBtn.Font = Enum.Font.GothamBold
minBtn.TextSize = 12
minBtn.Parent = header
Instance.new("UICorner", minBtn).CornerRadius = UDim.new(0, 5)

local titleLbl = Instance.new("TextLabel")
titleLbl.Size = UDim2.new(1, -50, 1, 0)
titleLbl.Position = UDim2.new(0, 26, 0, 0)
titleLbl.BackgroundTransparency = 1
titleLbl.Text = "💧🎯 Water + Auction"
titleLbl.TextColor3 = Color3.fromRGB(230, 230, 240)
titleLbl.TextXAlignment = Enum.TextXAlignment.Left
titleLbl.Font = Enum.Font.GothamBold
titleLbl.TextSize = 11
titleLbl.Parent = header

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 20, 0, 20)
closeBtn.Position = UDim2.new(1, -24, 0, 4)
closeBtn.BackgroundTransparency = 1
closeBtn.Text = "✕"
closeBtn.TextColor3 = Color3.fromRGB(255, 100, 100)
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 12
closeBtn.Parent = header

local body = Instance.new("Frame")
body.Size = UDim2.new(1, 0, 1, -28)
body.Position = UDim2.new(0, 0, 0, 28)
body.BackgroundTransparency = 1
body.Parent = body and main or main

-- ===== SECTION LABEL HELPER =====
local function makeSectionLbl(text, yPos)
	local l = Instance.new("TextLabel")
	l.Size = UDim2.new(1, -20, 0, 14)
	l.Position = UDim2.new(0, 10, 0, yPos)
	l.BackgroundTransparency = 1
	l.Text = text
	l.TextColor3 = Color3.fromRGB(120, 120, 145)
	l.Font = Enum.Font.GothamBold
	l.TextSize = 9
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Parent = body
	return l
end

-- ==================================================================
-- SECTION 1: WATER & SPRINKLE
-- ==================================================================

makeSectionLbl("💧 WATER & SPRINKLE", 6)

local waterBtn = Instance.new("TextButton")
waterBtn.Size = UDim2.new(0.5, -13, 0, 32)
waterBtn.Position = UDim2.new(0, 8, 0, 22)
waterBtn.BackgroundColor3 = Color3.fromRGB(60, 90, 140)
waterBtn.Text = "REC Water"
waterBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
waterBtn.Font = Enum.Font.GothamBold
waterBtn.TextSize = 10
waterBtn.Parent = body
Instance.new("UICorner", waterBtn).CornerRadius = UDim.new(0, 6)

local sprBtn = Instance.new("TextButton")
sprBtn.Size = UDim2.new(0.5, -13, 0, 32)
sprBtn.Position = UDim2.new(0.5, 5, 0, 22)
sprBtn.BackgroundColor3 = Color3.fromRGB(60, 120, 70)
sprBtn.Text = "REC Sprinkler"
sprBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
sprBtn.Font = Enum.Font.GothamBold
sprBtn.TextSize = 10
sprBtn.Parent = body
Instance.new("UICorner", sprBtn).CornerRadius = UDim.new(0, 6)

local resetBtn = Instance.new("TextButton")
resetBtn.Size = UDim2.new(1, -16, 0, 24)
resetBtn.Position = UDim2.new(0, 8, 0, 58)
resetBtn.BackgroundColor3 = Color3.fromRGB(90, 45, 45)
resetBtn.Text = "🔄 RESET REKAMAN"
resetBtn.TextColor3 = Color3.fromRGB(255, 230, 230)
resetBtn.Font = Enum.Font.GothamBold
resetBtn.TextSize = 10
resetBtn.Parent = body
Instance.new("UICorner", resetBtn).CornerRadius = UDim.new(0, 6)

local resetBtn2 = Instance.new("TextButton")
resetBtn2.Size = UDim2.new(1, -16, 0, 20)
resetBtn2.Position = UDim2.new(0, 8, 0, 86)
resetBtn2.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
resetBtn2.Text = "⏹️ STOP WATER/SPRINKLE"
resetBtn2.TextColor3 = Color3.fromRGB(230, 230, 240)
resetBtn2.Font = Enum.Font.GothamBold
resetBtn2.TextSize = 9
resetBtn2.Parent = body
Instance.new("UICorner", resetBtn2).CornerRadius = UDim.new(0, 6)

-- ==================================================================
-- SECTION 2: AUCTION
-- ==================================================================

makeSectionLbl("🎯 AUCTION", 114)

-- Master toggle
local masterToggle = Instance.new("TextButton")
masterToggle.Size = UDim2.new(1, -16, 0, 26)
masterToggle.Position = UDim2.new(0, 8, 0, 130)
masterToggle.BackgroundColor3 = Color3.fromRGB(16, 16, 22)
masterToggle.Text = ""
masterToggle.AutoButtonColor = false
masterToggle.Parent = body
Instance.new("UICorner", masterToggle).CornerRadius = UDim.new(0, 6)

local mtStroke = Instance.new("UIStroke")
mtStroke.Color = Color3.fromRGB(48, 48, 58)
mtStroke.Thickness = 1
mtStroke.Parent = masterToggle

local masterLabel = Instance.new("TextLabel")
masterLabel.Size = UDim2.new(1, -35, 1, 0)
masterLabel.Position = UDim2.new(0, 8, 0, 0)
masterLabel.BackgroundTransparency = 1
masterLabel.Text = "AUTO: OFF"
masterLabel.TextColor3 = Color3.fromRGB(150, 150, 165)
masterLabel.TextXAlignment = Enum.TextXAlignment.Left
masterLabel.Font = Enum.Font.GothamBold
masterLabel.TextSize = 10
masterLabel.Parent = masterToggle

local masterKnob = Instance.new("Frame")
masterKnob.Size = UDim2.new(0, 18, 0, 18)
masterKnob.Position = UDim2.new(1, -22, 0.5, -9)
masterKnob.BackgroundColor3 = Color3.fromRGB(180, 180, 190)
masterKnob.BorderSizePixel = 0
masterKnob.Parent = masterToggle
Instance.new("UICorner", masterKnob).CornerRadius = UDim.new(1, 0)

-- Item list
local listFrame = Instance.new("Frame")
listFrame.Size = UDim2.new(1, -16, 0, 96)
listFrame.Position = UDim2.new(0, 8, 0, 160)
listFrame.BackgroundTransparency = 1
listFrame.Parent = body

local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 2)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Parent = listFrame

local function createItemRow(targetCfg)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 20)
	row.BackgroundColor3 = Color3.fromRGB(26, 26, 32)
	row.BorderSizePixel = 0
	row.Parent = listFrame
	Instance.new("UICorner", row).CornerRadius = UDim.new(0, 4)

	local labelLbl = Instance.new("TextLabel")
	labelLbl.Size = UDim2.new(0, 60, 1, 0)
	labelLbl.Position = UDim2.new(0, 6, 0, 0)
	labelLbl.BackgroundTransparency = 1
	labelLbl.Text = targetCfg.label
	labelLbl.TextColor3 = Color3.fromRGB(240, 240, 245)
	labelLbl.TextXAlignment = Enum.TextXAlignment.Left
	labelLbl.Font = Enum.Font.GothamBold
	labelLbl.TextSize = 9
	labelLbl.Parent = row

	local infoLbl = Instance.new("TextLabel")
	infoLbl.Size = UDim2.new(1, -66, 1, 0)
	infoLbl.Position = UDim2.new(0, 66, 0, 0)
	infoLbl.BackgroundTransparency = 1
	infoLbl.Text = "⏹"
	infoLbl.TextColor3 = Color3.fromRGB(100, 100, 115)
	infoLbl.TextXAlignment = Enum.TextXAlignment.Right
	infoLbl.Font = Enum.Font.Code
	infoLbl.TextSize = 9
	infoLbl.Parent = row

	itemData[targetCfg.name] = {
		config = targetCfg,
		row = row,
		infoLbl = infoLbl,
		match = nil,
		lastFire = 0,
	}
end

for _, tgt in ipairs(TARGETS) do
	createItemRow(tgt)
end

-- Auction info footer
local auctionFooter = Instance.new("TextLabel")
auctionFooter.Size = UDim2.new(1, -16, 0, 14)
auctionFooter.Position = UDim2.new(0, 8, 0, 262)
auctionFooter.BackgroundTransparency = 1
auctionFooter.Text = "🎯 CWC <5m | SM<60s | SCWC<35s | SCS<25s"
auctionFooter.TextColor3 = Color3.fromRGB(120, 140, 180)
auctionFooter.Font = Enum.Font.Gotham
auctionFooter.TextSize = 8
auctionFooter.TextXAlignment = Enum.TextXAlignment.Left
auctionFooter.Parent = body

-- ===== Update auction UI (dipanggil dari scan) =====
updateAuctionUIRow = function()
	for _, tgt in ipairs(TARGETS) do
		local d = itemData[tgt.name]
		local m = d.match
		if not masterEnabled then
			d.row.BackgroundColor3 = Color3.fromRGB(26, 26, 32)
			if not m then
				d.infoLbl.Text = "⏹"
				d.infoLbl.TextColor3 = Color3.fromRGB(100, 100, 115)
			else
				local isExpired = (not m.timerSec) or m.timerSec <= 0
					or m.status == "EXPIRED" or m.status == "SOLD_OUT"
				if isExpired then
					d.infoLbl.Text = "⏸"
					d.infoLbl.TextColor3 = Color3.fromRGB(100, 100, 115)
				else
					d.infoLbl.Text = string.format("⚪ %s #%d", formatTimer(m.timerSec), m.lotIndex)
					d.infoLbl.TextColor3 = Color3.fromRGB(150, 150, 165)
				end
			end
		else
			if not m then
				d.infoLbl.Text = "🟡"
				d.infoLbl.TextColor3 = Color3.fromRGB(255, 200, 80)
				d.row.BackgroundColor3 = Color3.fromRGB(26, 26, 32)
			else
				local isExpired = (not m.timerSec) or m.timerSec <= 0
					or m.status == "EXPIRED" or m.status == "SOLD_OUT"
				if isExpired then
					d.infoLbl.Text = "⏸"
					d.infoLbl.TextColor3 = Color3.fromRGB(230, 90, 90)
					d.row.BackgroundColor3 = Color3.fromRGB(26, 26, 32)
				else
					local timerOk = (tgt.threshold == 0) or (m.timerSec and m.timerSec <= tgt.threshold)
					if timerOk then
						d.infoLbl.Text = string.format("🔴 %s #%d", formatTimer(m.timerSec), m.lotIndex)
						d.infoLbl.TextColor3 = Color3.fromRGB(130, 240, 150)
						d.row.BackgroundColor3 = Color3.fromRGB(30, 55, 35)
					else
						d.infoLbl.Text = string.format("⏳ %s #%d", formatTimer(m.timerSec), m.lotIndex)
						d.infoLbl.TextColor3 = Color3.fromRGB(190, 150, 255)
						d.row.BackgroundColor3 = Color3.fromRGB(45, 42, 25)
					end
				end
			end
		end
	end
end

-- ==================================================================
-- WATER BUTTON HANDLERS
-- ==================================================================

local function setWaterIdle()
	waterBtn.Text = "REC Water"
	waterBtn.BackgroundColor3 = Color3.fromRGB(60, 90, 140)
end
local function setWaterActive()
	waterBtn.Text = "💧 WATER: ON"
	waterBtn.BackgroundColor3 = Color3.fromRGB(40, 130, 70)
end
local function setWaterOff()
	waterBtn.Text = "💧 WATER: OFF"
	waterBtn.BackgroundColor3 = Color3.fromRGB(45, 60, 90)
end
local function setSprIdle()
	sprBtn.Text = "REC Sprinkler"
	sprBtn.BackgroundColor3 = Color3.fromRGB(60, 120, 70)
end
local function setSprActive()
	sprBtn.Text = "🌱 SPR: ON"
	sprBtn.BackgroundColor3 = Color3.fromRGB(40, 130, 70)
end
local function setSprOff()
	sprBtn.Text = "🌱 SPR: OFF"
	sprBtn.BackgroundColor3 = Color3.fromRGB(50, 70, 55)
end

waterBtn.MouseButton1Click:Connect(function()
	if not ALIVE then return end

	-- Batal kalau sedang countdown
	if wState.countingWater then
		wState.countingWater = false
		setWaterIdle()
		return
	end

	-- Batal kalau sedang recording
	if wState.recordingWater then
		wState.recordingWater = false
		setWaterIdle()
		return
	end

	-- Kalau sudah punya payload → toggle
	if wState.hasWater then
		wState.wateringOn = not wState.wateringOn
		if wState.wateringOn then setWaterActive() else setWaterOff() end
		return
	end

	-- Belum ada payload → mulai countdown lalu rekam
	local tool = ensureToolEquipped(WATER_TOOL_NAME)
	if not tool then
		waterBtn.Text = "❌ No Tool"
		task.wait(1.0)
		if ALIVE then setWaterIdle() end
		return
	end

	wState.countingWater = true
	task.spawn(function()
		for i = REC_COUNTDOWN, 1, -1 do
			if not ALIVE or not wState.countingWater then
				setWaterIdle()
				return
			end
			waterBtn.Text = string.format("⏱ %ds...", i)
			waterBtn.BackgroundColor3 = Color3.fromRGB(120, 100, 40)
			task.wait(1)
		end
		if not ALIVE or not wState.countingWater then
			setWaterIdle()
			return
		end
		wState.countingWater = false
		wState.recordingWater = true
		waterBtn.Text = "🔴 REC..."
		waterBtn.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
		installHook()
	end)
end)

sprBtn.MouseButton1Click:Connect(function()
	if not ALIVE then return end

	if wState.countingSprinkle then
		wState.countingSprinkle = false
		setSprIdle()
		return
	end

	if wState.recordingSprinkle then
		wState.recordingSprinkle = false
		setSprIdle()
		return
	end

	if wState.hasSprinkle then
		wState.sprinkleOn = not wState.sprinkleOn
		if wState.sprinkleOn then setSprActive() else setSprOff() end
		return
	end

	local tool = ensureToolEquipped(SPRINKLE_TOOL_NAME)
	if not tool then
		sprBtn.Text = "❌ No Tool"
		task.wait(1.0)
		if ALIVE then setSprIdle() end
		return
	end

	wState.countingSprinkle = true
	task.spawn(function()
		for i = REC_COUNTDOWN, 1, -1 do
			if not ALIVE or not wState.countingSprinkle then
				setSprIdle()
				return
			end
			sprBtn.Text = string.format("⏱ %ds...", i)
			sprBtn.BackgroundColor3 = Color3.fromRGB(120, 100, 40)
			task.wait(1)
		end
		if not ALIVE or not wState.countingSprinkle then
			setSprIdle()
			return
		end
		wState.countingSprinkle = false
		wState.recordingSprinkle = true
		sprBtn.Text = "🔴 REC..."
		sprBtn.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
		installHook()
	end)
end)

-- RESET REKAMAN
resetBtn.MouseButton1Click:Connect(function()
	if not ALIVE then return end
	wState.waterPayload     = nil
	wState.sprinklePayload  = nil
	wState.hasWater         = false
	wState.hasSprinkle      = false
	wState.recordingWater   = false
	wState.recordingSprinkle= false
	wState.countingWater    = false
	wState.countingSprinkle = false
	wState.wateringOn       = false
	wState.sprinkleOn       = false
	setWaterIdle()
	setSprIdle()
	print("🔄 Rekaman water & sprinkle di-reset.")
	resetBtn.Text = "✅ RESET!"
	task.wait(1)
	resetBtn.Text = "🔄 RESET REKAMAN"
end)

-- STOP ALL WATER/SPRINKLE
resetBtn2.MouseButton1Click:Connect(function()
	if not ALIVE then return end
	wState.wateringOn  = false
	wState.sprinkleOn  = false
	wState.busySprinkle = false
	if wState.hasWater then setWaterOff() else setWaterIdle() end
	if wState.hasSprinkle then setSprOff() else setSprIdle() end
	print("⏹️ Water & Sprinkle dimatikan.")
end)

-- ==================================================================
-- MASTER TOGGLE AUCTION
-- ==================================================================

local function updateMasterVisual()
	if masterEnabled then
		TweenService:Create(masterToggle, TweenInfo.new(0.15), {
			BackgroundColor3 = Color3.fromRGB(40, 60, 90)
		}):Play()
		TweenService:Create(masterKnob, TweenInfo.new(0.15), {
			BackgroundColor3 = Color3.fromRGB(90, 140, 230)
		}):Play()
		masterLabel.Text = "AUTO: ON"
		masterLabel.TextColor3 = Color3.fromRGB(130, 240, 150)
	else
		TweenService:Create(masterToggle, TweenInfo.new(0.15), {
			BackgroundColor3 = Color3.fromRGB(16, 16, 22)
		}):Play()
		TweenService:Create(masterKnob, TweenInfo.new(0.15), {
			BackgroundColor3 = Color3.fromRGB(180, 180, 190)
		}):Play()
		masterLabel.Text = "AUTO: OFF"
		masterLabel.TextColor3 = Color3.fromRGB(150, 150, 165)
	end
end

masterToggle.MouseButton1Click:Connect(function()
	masterEnabled = not masterEnabled
	updateMasterVisual()
end)

-- ==================================================================
-- MINIMIZE / CLOSE
-- ==================================================================

local isMinimized = false
minBtn.MouseButton1Click:Connect(function()
	isMinimized = not isMinimized
	body.Visible = not isMinimized
	main.Size = isMinimized and UDim2.new(0, 200, 0, MINI_H) or UDim2.new(0, 200, 0, FULL_H)
	minBtn.Text = isMinimized and "+" or "—"
end)

closeBtn.MouseButton1Click:Connect(function()
	shutdown("GUI ditutup")
	if gui then gui:Destroy() end
end)

gui.Destroying:Connect(function() shutdown("GUI Destroying event") end)

Players.PlayerRemoving:Connect(function(p)
	if p == LP then shutdown("Player keluar game") end
end)

-- ==================================================================
-- UI UPDATE LOOP (WATER RECORDED + TIME LOGIC)
-- ==================================================================

task.spawn(function()
	while ALIVE and gui.Parent do
		task.wait(0.5)
		if not ALIVE then break end

		if _G.__waterRecorded then
			_G.__waterRecorded = nil
			wState.hasWater = true
			setWaterOff()
			print("✅ Water payload recorded")
		end
		if _G.__sprinkleRecorded then
			_G.__sprinkleRecorded = nil
			wState.hasSprinkle = true
			setSprOff()
			print("✅ Sprinkle payload recorded")
		end

		-- Time logic: malam → auto ON, siang → auto OFF
		if wState.hasWater and wState.hasSprinkle then
			local clockTime = Lighting.ClockTime
			local isNight = (clockTime >= 18.0 or clockTime < 6.0)
			if isNight then
				if not wState.wateringOn or not wState.sprinkleOn then
					wState.wateringOn = true
					wState.sprinkleOn = true
					setWaterActive()
					setSprActive()
					print("🌙 Malam → AUTO START")
				end
			else
				if wState.wateringOn or wState.sprinkleOn then
					wState.wateringOn = false
					wState.sprinkleOn = false
					setWaterOff()
					setSprOff()
					print("☀️ Siang → AUTO STOP")
				end
			end
		end
	end
end)

-- ==================================================================
-- WATER MAIN LOOP
-- ==================================================================

task.spawn(function()
	while ALIVE and gui.Parent do
		task.wait(CHECK_INTERVAL)
		if not ALIVE then break end
		local has = hasActiveSprinkler()
		if wState.sprinkleOn and wState.hasSprinkle and not has and not wState.busySprinkle then
			wState.busySprinkle = true
			local ok = fireSprinkle()
			if ok then
				task.wait(SPRINKLE_SETTLE)
				if not ALIVE then break end
				hasActiveSprinkler()
			end
			wState.busySprinkle = false
		end
		if wState.wateringOn and wState.hasWater and not wState.busySprinkle then
			if has then fireWater() end
		end
	end
end)

-- ==================================================================
-- AUCTION HEARTBEAT
-- ==================================================================

local lastScan = 0
heartbeatConn = RunService.Heartbeat:Connect(function()
	if isShutdown then return end
	local now = os.clock()
	if now - lastScan >= 1 then
		lastScan = now
		pcall(scanAuction)
	end
	pcall(autoFireCheck)
end)

-- ==================================================================
-- INIT
-- ==================================================================

installHook()
setupAuctionOffScreen()
updateMasterVisual()
scanAuction()
