--// ============================================================
-- SNIPER — Super Magic Mail < 70
-- Toggle ON/OFF, auto-fire, auto-timestamp
-- ============================================================

local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local RunService = game:GetService("RunService")

local LP = Players.LocalPlayer

--// ==== CONFIG ====
local TARGET_ITEM = "Super Magic Mail"
local MAX_PRICE = 70
local MONEY_LOT_COUNT = 6
local FIRE_INTERVAL = 1   -- fire tiap 1 detik
local OFFSCREEN_OFFSET = 5000

local AUCTION_PATH = string.format(
    "game.Players.%s.PlayerGui.Auction",
    LP.Name
)

local SCROLLFRAME_PATH = string.format(
    "game.Players.%s.PlayerGui.Auction.Frame.ScrollingFrame",
    LP.Name
)

--// ==== HELPERS ====
local function resolvePath(pathStr)
    local segments = {}
    for seg in pathStr:gmatch("[^%.]+") do
        table.insert(segments, seg)
    end
    local node = game
    for i, seg in ipairs(segments) do
        if i == 1 and seg == "game" then
            -- skip
        elseif seg == "Players" then
            node = game:GetService("Players")
        else
            local nx = node:FindFirstChild(seg)
            if not nx then return nil end
            node = nx
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

-- Parse harga: "65¢B" → 65B, "5.95K¢" → 5950
local function parsePrice(text)
    if not text or text == "" then return nil end
    -- Hapus ¢, spasi, koma
    local cleaned = text:gsub("[¢%s]", ""):gsub(",", "")
    if cleaned == "" then return nil end

    local tVal = cleaned:match("([%d%.]+)[Tt]")
    if tVal then return math.floor(tonumber(tVal) * 1000000000000) end

    local bVal = cleaned:match("([%d%.]+)[Bb]")
    if bVal then return math.floor(tonumber(bVal) * 1000000000) end

    local mVal = cleaned:match("([%d%.]+)[Mm]")
    if mVal then return math.floor(tonumber(mVal) * 1000000) end

    local kVal = cleaned:match("([%d%.]+)[Kk]")
    if kVal then return math.floor(tonumber(kVal) * 1000) end

    local num = cleaned:match("([%d%.]+)")
    if num then return math.floor(tonumber(num)) end
    return nil
end

local function parseTimer(text)
    if not text or text == "" then return nil end
    local m, s = text:match("(%d+)m%s*(%d+)s")
    if m and s then return tonumber(m) * 60 + tonumber(s) end
    local s2 = text:match("(%d+)s")
    if s2 then return tonumber(s2) end
    return nil
end

local function formatPrice(p)
    if not p then return "—" end
    if p >= 1000000000000 then
        return string.format("%.2fT", p / 1000000000000)
    elseif p >= 1000000000 then
        return string.format("%.2fB", p / 1000000000)
    elseif p >= 1000000 then
        return string.format("%.2fM", p / 1000000)
    elseif p >= 1000 then
        return string.format("%.2fK", p / 1000)
    else
        return tostring(p)
    end
end

local function normalizeName(s)
    if not s then return "" end
    s = s:lower()
    s = s:gsub("%s+", " ")
    s = s:gsub("^%s+", "")
    s = s:gsub("%s+$", "")
    return s
end

--// ==== GET LOT PRICE (ROBUST — coba semua path) ====
local function getLotPrice(lot)
    local buyBtn = nil
    for _, obj in ipairs(lot:GetDescendants()) do
        if obj:IsA("TextButton") and obj.Name == "BuyButton" then
            buyBtn = obj
            break
        end
    end
    if not buyBtn then return nil, nil end

    -- Path 1: BuyButton.Text.TextLabel.TextLabel (dari log)
    local textFrame = buyBtn:FindFirstChild("Text")
    if textFrame then
        local tl = textFrame:FindFirstChild("TextLabel")
        if tl then
            -- Coba nested TextLabel dulu
            local nested = tl:FindFirstChild("TextLabel")
            if nested and nested.Text and nested.Text ~= "" then
                local price = parsePrice(nested.Text)
                if price then return price, nested.Text end
            end
            -- Fallback ke tl langsung
            if tl.Text and tl.Text ~= "" then
                local price = parsePrice(tl.Text)
                if price then return price, tl.Text end
            end
        end
    end

    -- Path 2: Semua TextLabel di dalam BuyButton
    for _, obj in ipairs(buyBtn:GetDescendants()) do
        if obj:IsA("TextLabel") then
            local txt = obj.Text or ""
            if txt:find("¢") or txt:match("^[%d,%.]+[KkMmBb]?¢?$") then
                local price = parsePrice(txt)
                if price then return price, txt end
            end
        end
    end

    -- Path 3: BuyButton.Text langsung
    local p = parsePrice(buyBtn.Text)
    return p, buyBtn.Text
end

--// ==== GET LOT STATUS ====
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

--// ==== BUILD PAYLOAD ====
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

--// ==== OFF-SCREEN AUCTION ====
local auctionKeepAliveConn = nil
local auctionPosConn = nil
local isShutdown = false

local function setupAuctionOffScreen()
    local auction = resolvePath(AUCTION_PATH)
    if not auction then return false end

    auction.Enabled = true
    auction.DisplayOrder = -1000

    local mainFrame = auction:FindFirstChild("Frame")
    if mainFrame then
        mainFrame:SetAttribute("_SniperOrigPos", mainFrame.Position)
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
            local origPos = mainFrame:GetAttribute("_SniperOrigPos")
            if origPos then
                pcall(function() mainFrame.Position = origPos end)
            end
        end
    end
end

--// ==== GUI — SIMPLE TOGGLE ====
local oldGui = CoreGui:FindFirstChild("SniperGui")
if oldGui then oldGui:Destroy() end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "SniperGui"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.DisplayOrder = 9999
ScreenGui.Parent = CoreGui

local Main = Instance.new("Frame")
Main.Size = UDim2.new(0, 180, 0, 70)
Main.Position = UDim2.new(0, 20, 0.5, -35)
Main.BackgroundColor3 = Color3.fromRGB(20, 20, 26)
Main.BorderSizePixel = 0
Main.Active = true
Main.Draggable = true
Main.Parent = ScreenGui

local mc = Instance.new("UICorner"); mc.CornerRadius = UDim.new(0, 10); mc.Parent = Main
local ms = Instance.new("UIStroke"); ms.Color = Color3.fromRGB(48, 48, 58); ms.Thickness = 1; ms.Parent = Main

-- Header
local Header = Instance.new("Frame")
Header.Size = UDim2.new(1, 0, 0, 22)
Header.BackgroundColor3 = Color3.fromRGB(30, 30, 38)
Header.BorderSizePixel = 0
Header.Parent = Main
local hc = Instance.new("UICorner"); hc.CornerRadius = UDim.new(0, 10); hc.Parent = Header
local hfix = Instance.new("Frame")
hfix.Size = UDim2.new(1, 0, 0, 6); hfix.Position = UDim2.new(0, 0, 1, -6)
hfix.BackgroundColor3 = Color3.fromRGB(30, 30, 38); hfix.BorderSizePixel = 0; hfix.Parent = Header

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, -30, 1, 0)
Title.Position = UDim2.new(0, 6, 0, 0)
Title.BackgroundTransparency = 1
Title.Text = "🎯 Sniper SMM"
Title.TextColor3 = Color3.fromRGB(235, 235, 240)
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Font = Enum.Font.GothamBold
Title.TextSize = 9
Title.Parent = Header

-- Close
local CloseBtn = Instance.new("TextButton")
CloseBtn.Size = UDim2.new(0, 16, 0, 16)
CloseBtn.Position = UDim2.new(1, -20, 0.5, -8)
CloseBtn.BackgroundColor3 = Color3.fromRGB(220, 80, 90)
CloseBtn.BorderSizePixel = 0
CloseBtn.Text = "✕"
CloseBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.TextSize = 9
CloseBtn.Parent = Header
local cc = Instance.new("UICorner"); cc.CornerRadius = UDim.new(0, 4); cc.Parent = CloseBtn

-- Toggle Button (BESAR)
local ToggleBtn = Instance.new("TextButton")
ToggleBtn.Size = UDim2.new(1, -12, 0, 28)
ToggleBtn.Position = UDim2.new(0, 6, 0, 26)
ToggleBtn.BackgroundColor3 = Color3.fromRGB(36, 36, 44)
ToggleBtn.BorderSizePixel = 0
ToggleBtn.Text = "⏹️ OFF"
ToggleBtn.TextColor3 = Color3.fromRGB(235, 235, 240)
ToggleBtn.Font = Enum.Font.GothamBold
ToggleBtn.TextSize = 12
ToggleBtn.Parent = Main
local tc = Instance.new("UICorner"); tc.CornerRadius = UDim.new(0, 6); tc.Parent = ToggleBtn
local ts = Instance.new("UIStroke"); ts.Color = Color3.fromRGB(48, 48, 58); ts.Thickness = 1; ts.Parent = ToggleBtn

-- Status
local StatusLbl = Instance.new("TextLabel")
StatusLbl.Size = UDim2.new(1, -12, 0, 12)
StatusLbl.Position = UDim2.new(0, 6, 0, 56)
StatusLbl.BackgroundTransparency = 1
StatusLbl.Text = "—"
StatusLbl.TextColor3 = Color3.fromRGB(140, 145, 160)
StatusLbl.Font = Enum.Font.Code
StatusLbl.TextSize = 8
StatusLbl.TextXAlignment = Enum.TextXAlignment.Left
StatusLbl.TextTruncate = Enum.TextTruncate.AtEnd
StatusLbl.Parent = Main

--// ==== STATE ====
local enabled = false
local currentMatch = nil
local lastFireTime = 0
local heartbeatConn = nil

--// ==== SCAN ====
local targetNorm = normalizeName(TARGET_ITEM)

local function scanAuction()
    if isShutdown then return end

    local root = resolvePath(SCROLLFRAME_PATH)
    if not root then
        currentMatch = nil
        return
    end

    local found = nil
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

                if itemName and normalizeName(itemName) == targetNorm then
                    local price, priceText = getLotPrice(child)
                    local status, timerSec, timerText = getLotStatus(child)
                    found = {
                        lotName = child.Name,
                        lotId = lotNameToId(child.Name),
                        timestamp = ts,
                        lotIndex = idx,
                        price = price,
                        priceText = priceText,
                        status = status,
                        timerSec = timerSec,
                        timerText = timerText,
                    }
                    break
                end
            end
        end
    end

    currentMatch = found

    -- Update status
    if found then
        if found.status == "EXPIRED" or found.status == "SOLD_OUT" then
            StatusLbl.Text = string.format("⏸️ %s", found.status)
            StatusLbl.TextColor3 = Color3.fromRGB(230, 150, 60)
        elseif found.price and found.price <= MAX_PRICE then
            StatusLbl.Text = string.format("🔥 %s ≤ %d", found.priceText or "?", MAX_PRICE)
            StatusLbl.TextColor3 = Color3.fromRGB(130, 240, 150)
        else
            StatusLbl.Text = string.format("⏳ %s > %d", found.priceText or "?", MAX_PRICE)
            StatusLbl.TextColor3 = Color3.fromRGB(255, 200, 80)
        end
    else
        StatusLbl.Text = "🔍 mencari..."
        StatusLbl.TextColor3 = Color3.fromRGB(140, 145, 160)
    end
end

--// ==== AUTO-FIRE ====
local function autoFireCheck()
    if isShutdown then return end
    if not enabled then return end
    if not currentMatch then return end

    local m = currentMatch
    if m.status == "EXPIRED" or m.status == "SOLD_OUT" then return end
    if not m.price or m.price > MAX_PRICE then return end

    local now = tick()
    if now - lastFireTime >= FIRE_INTERVAL then
        lastFireTime = now
        pcall(function() firePayload(m) end)
    end
end

--// ==== TOGGLE ====
ToggleBtn.MouseButton1Click:Connect(function()
    enabled = not enabled
    if enabled then
        ToggleBtn.Text = "🔴 ON"
        ToggleBtn.BackgroundColor3 = Color3.fromRGB(40, 60, 90)
        ToggleBtn.TextColor3 = Color3.fromRGB(130, 240, 150)
        ts.Color = Color3.fromRGB(90, 210, 110)
    else
        ToggleBtn.Text = "⏹️ OFF"
        ToggleBtn.BackgroundColor3 = Color3.fromRGB(36, 36, 44)
        ToggleBtn.TextColor3 = Color3.fromRGB(235, 235, 240)
        ts.Color = Color3.fromRGB(48, 48, 58)
    end
end)

--// ==== CLOSE ====
CloseBtn.MouseButton1Click:Connect(function()
    isShutdown = true
    if heartbeatConn then heartbeatConn:Disconnect() heartbeatConn = nil end
    restoreAuction()
    ScreenGui:Destroy()
    print("[Sniper] Closed.")
end)

--// ==== HEARTBEAT ====
local lastScan = 0

heartbeatConn = RunService.Heartbeat:Connect(function()
    if isShutdown then return end
    local now = tick()

    if now - lastScan >= 1 then
        lastScan = now
        pcall(scanAuction)
    end

    pcall(autoFireCheck)
end)

--// ==== INIT ====
task.wait(0.3)
setupAuctionOffScreen()
scanAuction()

print("[Sniper] ✅ Loaded!")
print("[Sniper] 🎯 Target: Super Magic Mail")
print("[Sniper] 💰 Max: " .. MAX_PRICE)
