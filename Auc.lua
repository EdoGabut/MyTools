--// ============================================================
-- AUCTION TOGGLE — Ultra Minimalis (Mobile Friendly)
-- CWC <8m | SM <60s | SCWC <35s | SCS <25s
-- ============================================================

local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local LP = Players.LocalPlayer

--// ============================================================
-- CONFIG
-- ============================================================
local TARGETS = {
    { name = "Cider Watering Can",        threshold = 480, label = "CWC"  },
    { name = "Spirit Mushroom",           threshold = 60,  label = "SM"   },
    { name = "Super Cider Watering Can",  threshold = 35,  label = "SCWC" },
    { name = "Super Cider Sprinkler",     threshold = 25,  label = "SCS"  },
}

local MONEY_LOT_COUNT = 6
local AUTO_FIRE_INTERVAL = 5
local OFFSCREEN_OFFSET = 5000

local AUCTION_PATH = string.format(
    "game.Players.%s.PlayerGui.Auction",
    LP.Name
)

local SCROLLFRAME_PATH = string.format(
    "game.Players.%s.PlayerGui.Auction.Frame.ScrollingFrame",
    LP.Name
)

--// ============================================================
-- THEME
-- ============================================================
local THEME = {
    bg          = Color3.fromRGB(20, 20, 26),
    bgCard      = Color3.fromRGB(30, 30, 38),
    bgRow       = Color3.fromRGB(26, 26, 32),
    bgRowActive = Color3.fromRGB(30, 55, 35),
    bgRowWait   = Color3.fromRGB(45, 42, 25),
    bgInput     = Color3.fromRGB(16, 16, 22),
    border      = Color3.fromRGB(48, 48, 58),
    textPrimary = Color3.fromRGB(240, 240, 245),
    textSecondary = Color3.fromRGB(150, 150, 165),
    textMuted   = Color3.fromRGB(100, 100, 115),
    greenBright = Color3.fromRGB(130, 240, 150),
    gold        = Color3.fromRGB(255, 200, 80),
    red         = Color3.fromRGB(230, 90, 90),
    cyan        = Color3.fromRGB(90, 200, 230),
    slider      = Color3.fromRGB(90, 140, 230),
    purple      = Color3.fromRGB(190, 150, 255),
    headerBtn   = Color3.fromRGB(90, 90, 100),
}

--// ============================================================
-- HELPER
-- ============================================================
local function resolvePath(pathStr)
    pathStr = pathStr:gsub("^%s+", ""):gsub("%s+$", "")
    local segments = {}
    for seg in pathStr:gmatch("[^%.]+") do
        table.insert(segments, seg)
    end
    if #segments == 0 then return nil, "kosong" end
    if segments[1] ~= "game" then return nil, "harus 'game.'" end
    table.remove(segments, 1)
    local node = game
    for i, seg in ipairs(segments) do
        if not node then return nil, "gagal segmen #" .. i end
        if seg == "LocalPlayer" then node = LP
        elseif seg == "Players" then node = game:GetService("Players")
        elseif seg == "Workspace" then node = workspace
        elseif seg == "CoreGui" then node = game:GetService("CoreGui")
        elseif seg == "ReplicatedStorage" then node = game:GetService("ReplicatedStorage")
        else
            if node == game:GetService("Players") and seg == LP.Name then
                node = LP
            else
                local nx = node:FindFirstChild(seg)
                if not nx then return nil, "tidak ada: '" .. seg .. "'" end
                node = nx
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

local function lotNameToId(lotName)
    return lotName:gsub("^Lot_", "")
end

local function parseTimer(text)
    if not text or text == "" then return nil end
    local m, s = text:match("(%d+)m%s*(%d+)s")
    if m and s then return tonumber(m) * 60 + tonumber(s) end
    local s2 = text:match("(%d+)s")
    if s2 then return tonumber(s2) end
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
    s = s:lower()
    s = s:gsub("%s+", " ")
    s = s:gsub("^%s+", "")
    s = s:gsub("%s+$", "")
    return s
end

--// ============================================================
-- GET LOT STATUS
-- ============================================================
local function getLotStatus(lot)
    local outOfStock, expired = nil, nil
    for _, obj in ipairs(lot:GetDescendants()) do
        if obj:IsA("Frame") then
            if obj.Name == "OUT_OF_STOCK" then outOfStock = obj end
            if obj.Name == "EXPIRED" then expired = obj end
        end
    end

    local timerText = nil
    for _, obj in ipairs(lot:GetDescendants()) do
        if obj:IsA("TextLabel") and obj.Name == "Timer" then
            timerText = obj.Text
            break
        end
    end

    local timerSec = parseTimer(timerText)

    if outOfStock and outOfStock.Visible then
        return "SOLD_OUT", timerSec, timerText
    end
    if expired and expired.Visible then
        return "EXPIRED", timerSec, timerText
    end
    if timerSec and timerSec <= 0 then
        return "EXPIRED", timerSec, timerText
    end
    return "AVAILABLE", timerSec, timerText
end

--// ============================================================
-- BUILD PAYLOAD
-- ============================================================
local function buildPayload(lotId, timestamp)
    local lotIdLen = #lotId
    local totalLen = 2 + 1 + lotIdLen + 3 + 8
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

local function firePayload(lotData)
    local payload = buildPayload(lotData.lotId, lotData.timestamp)
    local ok, err = pcall(function()
        game:GetService("ReplicatedStorage")
            :WaitForChild("SharedModules")
            :WaitForChild("Packet")
            :WaitForChild("RemoteEvent")
            :FireServer(payload)
    end)
    return ok, err
end

--// ============================================================
-- OFF-SCREEN AUCTION
-- ============================================================
local auctionKeepAliveConn = nil
local auctionPosConn = nil
local isShutdown = false

local function setupAuctionOffScreen()
    local auction, err = resolvePath(AUCTION_PATH)
    if not auction then return false end

    auction.Enabled = true
    auction.DisplayOrder = -1000

    local mainFrame = auction:FindFirstChild("Frame")
    if mainFrame then
        mainFrame:SetAttribute("_AutoBuyOrigPos", mainFrame.Position)
        mainFrame.Position = UDim2.new(0, OFFSCREEN_OFFSET, 0, 0)
        mainFrame.Visible = true

        auctionPosConn = mainFrame:GetPropertyChangedSignal("Position"):Connect(function()
            if isShutdown then return end
            if mainFrame.Position.X.Offset ~= OFFSCREEN_OFFSET then
                task.defer(function()
                    mainFrame.Position = UDim2.new(0, OFFSCREEN_OFFSET, 0, 0)
                end)
            end
        end)
    end

    auctionKeepAliveConn = auction:GetPropertyChangedSignal("Enabled"):Connect(function()
        if isShutdown then return end
        if not auction.Enabled then auction.Enabled = true end
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
            if origPos then
                pcall(function() mainFrame.Position = origPos end)
            end
        end
    end
end

--// ============================================================
-- STATE
-- ============================================================
local masterEnabled = false
local itemData = {}
local heartbeatConn = nil

--// ============================================================
-- GUI — ULTRA MINIMALIS
-- ============================================================
local oldGui = CoreGui:FindFirstChild("AuctionToggleGui")
if oldGui then oldGui:Destroy() end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "AuctionToggleGui"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.DisplayOrder = 9999
ScreenGui.Parent = CoreGui

-- Main: 170x150 (compact banget)
local Main = Instance.new("Frame")
Main.Size = UDim2.new(0, 170, 0, 150)
Main.Position = UDim2.new(0, 10, 0.5, -75)
Main.BackgroundColor3 = THEME.bg
Main.BorderSizePixel = 0
Main.Active = true
Main.Draggable = true
Main.Parent = ScreenGui

local MainCorner = Instance.new("UICorner")
MainCorner.CornerRadius = UDim.new(0, 8)
MainCorner.Parent = Main

local MainStroke = Instance.new("UIStroke")
MainStroke.Color = THEME.border
MainStroke.Thickness = 1
MainStroke.Parent = Main

-- HEADER (compact)
local Header = Instance.new("Frame")
Header.Size = UDim2.new(1, 0, 0, 22)
Header.BackgroundColor3 = THEME.bgCard
Header.BorderSizePixel = 0
Header.Parent = Main

local HeaderCorner = Instance.new("UICorner")
HeaderCorner.CornerRadius = UDim.new(0, 8)
HeaderCorner.Parent = Header

local HeaderFix = Instance.new("Frame")
HeaderFix.Size = UDim2.new(1, 0, 0, 6)
HeaderFix.Position = UDim2.new(0, 0, 1, -6)
HeaderFix.BackgroundColor3 = THEME.bgCard
HeaderFix.BorderSizePixel = 0
HeaderFix.Parent = Header

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, -50, 1, 0)
Title.Position = UDim2.new(0, 6, 0, 0)
Title.BackgroundTransparency = 1
Title.Text = "🎯 Auction"
Title.TextColor3 = THEME.textPrimary
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Font = Enum.Font.GothamBold
Title.TextSize = 9
Title.Parent = Header

-- Minimize
local MinimizeBtn = Instance.new("TextButton")
MinimizeBtn.Size = UDim2.new(0, 16, 0, 16)
MinimizeBtn.Position = UDim2.new(1, -38, 0.5, -8)
MinimizeBtn.BackgroundColor3 = THEME.headerBtn
MinimizeBtn.BorderSizePixel = 0
MinimizeBtn.Text = "—"
MinimizeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
MinimizeBtn.Font = Enum.Font.GothamBold
MinimizeBtn.TextSize = 9
MinimizeBtn.Parent = Header

local MinCorner = Instance.new("UICorner")
MinCorner.CornerRadius = UDim.new(0, 4)
MinCorner.Parent = MinimizeBtn

-- Close
local CloseBtn = Instance.new("TextButton")
CloseBtn.Size = UDim2.new(0, 16, 0, 16)
CloseBtn.Position = UDim2.new(1, -20, 0.5, -8)
CloseBtn.BackgroundColor3 = THEME.red
CloseBtn.BorderSizePixel = 0
CloseBtn.Text = "✕"
CloseBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.TextSize = 9
CloseBtn.Parent = Header

local CloseCorner = Instance.new("UICorner")
CloseCorner.CornerRadius = UDim.new(0, 4)
CloseCorner.Parent = CloseBtn

-- CONTENT
local Content = Instance.new("Frame")
Content.Size = UDim2.new(1, 0, 1, -22)
Content.Position = UDim2.new(0, 0, 0, 22)
Content.BackgroundTransparency = 1
Content.Parent = Main

-- MASTER TOGGLE (compact)
local MasterToggle = Instance.new("TextButton")
MasterToggle.Size = UDim2.new(1, -10, 0, 26)
MasterToggle.Position = UDim2.new(0, 5, 0, 5)
MasterToggle.BackgroundColor3 = THEME.bgInput
MasterToggle.BorderSizePixel = 0
MasterToggle.Text = ""
MasterToggle.AutoButtonColor = false
MasterToggle.Parent = Content

local MT_Corner = Instance.new("UICorner")
MT_Corner.CornerRadius = UDim.new(0, 6)
MT_Corner.Parent = MasterToggle

local MT_Stroke = Instance.new("UIStroke")
MT_Stroke.Color = THEME.border
MT_Stroke.Thickness = 1
MT_Stroke.Parent = MasterToggle

local MasterLabel = Instance.new("TextLabel")
MasterLabel.Size = UDim2.new(1, -35, 1, 0)
MasterLabel.Position = UDim2.new(0, 8, 0, 0)
MasterLabel.BackgroundTransparency = 1
MasterLabel.Text = "AUTO: OFF"
MasterLabel.TextColor3 = THEME.textSecondary
MasterLabel.TextXAlignment = Enum.TextXAlignment.Left
MasterLabel.Font = Enum.Font.GothamBold
MasterLabel.TextSize = 10
MasterLabel.Parent = MasterToggle

local MasterKnob = Instance.new("Frame")
MasterKnob.Size = UDim2.new(0, 18, 0, 18)
MasterKnob.Position = UDim2.new(1, -22, 0.5, -9)
MasterKnob.BackgroundColor3 = Color3.fromRGB(180, 180, 190)
MasterKnob.BorderSizePixel = 0
MasterKnob.Parent = MasterToggle

local MK_Corner = Instance.new("UICorner")
MK_Corner.CornerRadius = UDim.new(1, 0)
MK_Corner.Parent = MasterKnob

-- ITEM LIST (compact)
local List = Instance.new("Frame")
List.Size = UDim2.new(1, -10, 1, -38)
List.Position = UDim2.new(0, 5, 0, 34)
List.BackgroundTransparency = 1
List.Parent = Content

local ListLayout = Instance.new("UIListLayout")
ListLayout.Padding = UDim.new(0, 2)
ListLayout.SortOrder = Enum.SortOrder.LayoutOrder
ListLayout.Parent = List

--// ============================================================
-- CREATE ITEM ROW (compact)
-- ============================================================
local function createItemRow(targetCfg)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 20)
    row.BackgroundColor3 = THEME.bgRow
    row.BorderSizePixel = 0
    row.Parent = List

    local rc = Instance.new("UICorner")
    rc.CornerRadius = UDim.new(0, 4)
    rc.Parent = row

    -- Label (kiri) — CWC <8m
    local labelLbl = Instance.new("TextLabel")
    labelLbl.Size = UDim2.new(0, 70, 1, 0)
    labelLbl.Position = UDim2.new(0, 6, 0, 0)
    labelLbl.BackgroundTransparency = 1
    labelLbl.Text = targetCfg.label
    labelLbl.TextColor3 = THEME.textPrimary
    labelLbl.TextXAlignment = Enum.TextXAlignment.Left
    labelLbl.Font = Enum.Font.GothamBold
    labelLbl.TextSize = 9
    labelLbl.Parent = row

    -- Info (kanan) — 🔴 5:30 #4
    local infoLbl = Instance.new("TextLabel")
    infoLbl.Size = UDim2.new(1, -76, 1, 0)
    infoLbl.Position = UDim2.new(0, 76, 0, 0)
    infoLbl.BackgroundTransparency = 1
    infoLbl.Text = "⏹"
    infoLbl.TextColor3 = THEME.textMuted
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

--// ============================================================
-- MASTER TOGGLE VISUAL
-- ============================================================
local function updateMasterVisual()
    if masterEnabled then
        TweenService:Create(MasterToggle, TweenInfo.new(0.15), {
            BackgroundColor3 = Color3.fromRGB(40, 60, 90)
        }):Play()
        TweenService:Create(MasterKnob, TweenInfo.new(0.15), {
            BackgroundColor3 = THEME.slider,
            Position = UDim2.new(1, -22, 0.5, -9)
        }):Play()
        MasterLabel.Text = "AUTO: ON"
        MasterLabel.TextColor3 = THEME.greenBright
    else
        TweenService:Create(MasterToggle, TweenInfo.new(0.15), {
            BackgroundColor3 = THEME.bgInput
        }):Play()
        TweenService:Create(MasterKnob, TweenInfo.new(0.15), {
            BackgroundColor3 = Color3.fromRGB(180, 180, 190),
            Position = UDim2.new(1, -22, 0.5, -9)
        }):Play()
        MasterLabel.Text = "AUTO: OFF"
        MasterLabel.TextColor3 = THEME.textSecondary
    end
end

MasterToggle.MouseButton1Click:Connect(function()
    masterEnabled = not masterEnabled
    updateMasterVisual()
end)

--// ============================================================
-- SCAN
-- ============================================================
local normalizedTargets = {}
for _, tgt in ipairs(TARGETS) do
    normalizedTargets[tgt.name] = normalizeName(tgt.name)
end

local function scanAll()
    if isShutdown then return end

    local root, err = resolvePath(SCROLLFRAME_PATH)
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
                            local status, timerSec, timerText = getLotStatus(child)
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

    -- Update UI
    for _, tgt in ipairs(TARGETS) do
        local d = itemData[tgt.name]
        local m = d.match
        local threshold = tgt.threshold

        if not masterEnabled then
            d.row.BackgroundColor3 = THEME.bgRow
            if not m then
                d.infoLbl.Text = "⏹"
                d.infoLbl.TextColor3 = THEME.textMuted
            else
                local isExpired = (not m.timerSec) or m.timerSec <= 0
                    or m.status == "EXPIRED" or m.status == "SOLD_OUT"
                if isExpired then
                    d.infoLbl.Text = "⏸"
                    d.infoLbl.TextColor3 = THEME.textMuted
                else
                    d.infoLbl.Text = string.format("⚪ %s #%d", formatTimer(m.timerSec), m.lotIndex)
                    d.infoLbl.TextColor3 = THEME.textSecondary
                end
            end
        else
            if not m then
                d.infoLbl.Text = "🟡"
                d.infoLbl.TextColor3 = THEME.gold
                d.row.BackgroundColor3 = THEME.bgRow
            else
                local isExpired = (not m.timerSec) or m.timerSec <= 0
                    or m.status == "EXPIRED" or m.status == "SOLD_OUT"
                if isExpired then
                    d.infoLbl.Text = "⏸"
                    d.infoLbl.TextColor3 = THEME.red
                    d.row.BackgroundColor3 = THEME.bgRow
                else
                    local timerOk = (threshold == 0) or (m.timerSec and m.timerSec <= threshold)
                    if timerOk then
                        d.infoLbl.Text = string.format("🔴 %s #%d", formatTimer(m.timerSec), m.lotIndex)
                        d.infoLbl.TextColor3 = THEME.greenBright
                        d.row.BackgroundColor3 = THEME.bgRowActive
                    else
                        d.infoLbl.Text = string.format("⏳ %s #%d", formatTimer(m.timerSec), m.lotIndex)
                        d.infoLbl.TextColor3 = THEME.purple
                        d.row.BackgroundColor3 = THEME.bgRowWait
                    end
                end
            end
        end
    end
end

--// ============================================================
-- AUTO-FIRE
-- ============================================================
local function autoFireCheck()
    if isShutdown then return end
    if not masterEnabled then return end

    local now = tick()

    for _, tgt in ipairs(TARGETS) do
        local d = itemData[tgt.name]
        if d.match then
            local m = d.match
            local isExpired = (not m.timerSec) or m.timerSec <= 0
                or m.status == "EXPIRED" or m.status == "SOLD_OUT"

            if not isExpired then
                local threshold = tgt.threshold
                local timerOk = (threshold == 0) or (m.timerSec and m.timerSec <= threshold)
                if timerOk then
                    if now - d.lastFire >= AUTO_FIRE_INTERVAL then
                        d.lastFire = now
                        pcall(function() firePayload(m) end)
                    end
                end
            end
        end
    end
end

--// ============================================================
-- MINIMIZE / CLOSE
-- ============================================================
local minimized = false
local oldSize = nil

MinimizeBtn.MouseButton1Click:Connect(function()
    minimized = not minimized
    if minimized then
        oldSize = Main.AbsoluteSize.Y
        TweenService:Create(Main, TweenInfo.new(0.15), {
            Size = UDim2.new(0, 170, 0, 22)
        }):Play()
        Content.Visible = false
        MinimizeBtn.Text = "▢"
    else
        TweenService:Create(Main, TweenInfo.new(0.15), {
            Size = UDim2.new(0, 170, 0, oldSize or 150)
        }):Play()
        Content.Visible = true
        MinimizeBtn.Text = "—"
    end
end)

CloseBtn.MouseButton1Click:Connect(function()
    isShutdown = true
    if heartbeatConn then heartbeatConn:Disconnect() heartbeatConn = nil end
    restoreAuction()

    TweenService:Create(Main, TweenInfo.new(0.15), {
        Size = UDim2.new(0, 0, 0, 0)
    }):Play()
    task.wait(0.2)

    ScreenGui:Destroy()
    print("[Auction Toggle] Closed.")
end)

--// ============================================================
-- HEARTBEAT
-- ============================================================
local lastScan = 0

heartbeatConn = RunService.Heartbeat:Connect(function()
    if isShutdown then return end
    local now = tick()

    if now - lastScan >= 1 then
        lastScan = now
        pcall(scanAll)
    end

    pcall(autoFireCheck)
end)

--// ============================================================
-- INIT
-- ============================================================
task.wait(0.3)

setupAuctionOffScreen()
updateMasterVisual()
scanAll()

print("[Auction Toggle] ✅ Loaded! Player: " .. LP.Name)
