--// ============================================================
-- AUCTION SNIPER — Per-Item Timer + Minimize
-- FORMAT BARU: [DD 01] [LENGTH] [LOT_ID] [00 00 00] [f64 TS]
-- ============================================================

local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local LP = Players.LocalPlayer

local remote = ReplicatedStorage:WaitForChild("SharedModules")
    :WaitForChild("Packet")
    :WaitForChild("RemoteEvent")

--// ==== CONFIG — WATCHLIST + DEFAULT TIMER ====
local WATCHLIST = {
    { name = "Fence Crate",          defaultTimer = 360 },  -- 6 menit
    { name = "Common Egg",           defaultTimer = 180 },  -- 3 menit
    { name = "Super Sprinkler",      defaultTimer = 120 },  -- 2 menit
    { name = "Super Watering Can",   defaultTimer = 120 },  -- 2 menit
    { name = "Teleporter Pad Crate", defaultTimer = 60 },   -- 1 menit
    { name = "Bear Trap Crate",      defaultTimer = 60 },   -- 1 menit
    { name = "Mushroom",             defaultTimer = 60 },   -- 1 menit
}

local MONEY_LOT_COUNT = 6
local FIRE_INTERVAL = 5
local SCAN_INTERVAL = 1
local OFFSCREEN_OFFSET = 5000

-- Ukuran GUI
local FULL_W = 340
local FULL_H = 500
local MINI_W = 180  -- header compact saat minimize
local MINI_H = 24

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
    if #segments == 0 then return nil end
    if segments[1] ~= "game" then return nil end
    table.remove(segments, 1)
    local node = game
    for i, seg in ipairs(segments) do
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
                local nx = node:FindFirstChild(seg)
                if not nx then return nil end
                node = nx
            end
        end
    end
    return node
end

local function extractLotInfo(name)
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

local function parseTimerInput(text)
    if not text or text == "" then return 60 end
    text = text:lower():gsub("%s+", "")

    local mVal = text:match("([%d%.]+)m")
    if mVal then return math.floor(tonumber(mVal) * 60) end

    local sVal = text:match("([%d%.]+)s")
    if sVal then return math.floor(tonumber(sVal)) end

    local num = text:match("([%d%.]+)")
    if num then return math.floor(tonumber(num)) end

    return 60
end

local function formatTimerInput(sec)
    if not sec then return "1m" end
    if sec >= 60 and sec % 60 == 0 then
        return (sec / 60) .. "m"
    elseif sec >= 60 then
        return string.format("%dm%ds", math.floor(sec/60), sec%60)
    else
        return sec .. "s"
    end
end

local function parsePrice(text)
    if not text or text == "" then return nil end
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

local function normalizeName(s)
    if not s then return "" end
    s = s:lower()
    s = s:gsub("%s+", " ")
    s = s:gsub("^%s+", "")
    s = s:gsub("%s+$", "")
    return s
end

local function getLotPrice(lot)
    local buyBtn = nil
    for _, obj in ipairs(lot:GetDescendants()) do
        if obj:IsA("TextButton") and obj.Name == "BuyButton" then
            buyBtn = obj
            break
        end
    end
    if not buyBtn then return nil, nil end

    local textFrame = buyBtn:FindFirstChild("Text")
    if textFrame then
        local tl = textFrame:FindFirstChild("TextLabel")
        if tl then
            local nested = tl:FindFirstChild("TextLabel")
            if nested and nested.Text and nested.Text ~= "" then
                local price = parsePrice(nested.Text)
                if price then return price, nested.Text end
            end
            if tl.Text and tl.Text ~= "" then
                local price = parsePrice(tl.Text)
                if price then return price, tl.Text end
            end
        end
    end

    for _, obj in ipairs(buyBtn:GetDescendants()) do
        if obj:IsA("TextLabel") then
            local txt = obj.Text or ""
            if txt:find("¢") or txt:match("^[%d,%.]+[KkMmBb]?¢?$") then
                local price = parsePrice(txt)
                if price then return price, txt end
            end
        end
    end

    local p = parsePrice(buyBtn.Text)
    return p, buyBtn.Text
end

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
        return "SOLD", timerSec, timerText
    end
    if expired and expired.Visible then
        return "EXP", timerSec, timerText
    end
    if timerSec and timerSec <= 0 then
        return "EXP", timerSec, timerText
    end
    return "OK", timerSec, timerText
end

--// ==== BUILD PAYLOAD ====
local function buildPayload(lotId, timestamp)
    local lotIdLen = #lotId
    local totalLen = 2 + 1 + lotIdLen + 3 + 8
    local buf = buffer.create(totalLen)
    local pos = 0

    buffer.writeu8(buf, pos, 0xDD); pos += 1
    buffer.writeu8(buf, pos, 0x01); pos += 1
    buffer.writeu8(buf, pos, lotIdLen); pos += 1

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
        remote:FireServer(payload)
    end)
    return ok, err
end

--// ==== OFF-SCREEN AUCTION ====
local auctionKeepAliveConn = nil
local auctionPosConn = nil
local isShutdown = false
local auctionOriginalPos = nil

local function setupAuctionOffScreen()
    local auction = resolvePath(AUCTION_PATH)
    if not auction then return false end

    auction.Enabled = true
    auction.DisplayOrder = -1000

    local mainFrame = auction:FindFirstChild("Frame")
    if mainFrame then
        auctionOriginalPos = mainFrame.Position
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
        if mainFrame and auctionOriginalPos then
            pcall(function() mainFrame.Position = auctionOriginalPos end)
        end
        pcall(function() auction.Enabled = false end)
    end
end

--// ==== PALETTE ====
local C_BG      = Color3.fromRGB(18, 18, 22)
local C_CARD    = Color3.fromRGB(28, 28, 34)
local C_ROW     = Color3.fromRGB(36, 36, 44)
local C_ROW_ACT = Color3.fromRGB(34, 60, 40)
local C_ROW_WAIT = Color3.fromRGB(45, 42, 25)
local C_ACCENT  = Color3.fromRGB(96, 140, 230)
local C_GREEN   = Color3.fromRGB(80, 190, 120)
local C_GREEN_B = Color3.fromRGB(130, 240, 150)
local C_RED     = Color3.fromRGB(220, 80, 90)
local C_GOLD    = Color3.fromRGB(255, 210, 90)
local C_TEXT    = Color3.fromRGB(235, 235, 240)
local C_SUB     = Color3.fromRGB(140, 145, 160)
local C_BORDER  = Color3.fromRGB(48, 48, 60)

--// ==== GUI ====
local old = CoreGui:FindFirstChild("AuctionSniperGui")
if old then old:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "AuctionSniperGui"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.IgnoreGuiInset = true
gui.DisplayOrder = 999
gui.Parent = CoreGui

local main = Instance.new("Frame")
main.Size = UDim2.new(0, FULL_W, 0, FULL_H)
main.Position = UDim2.new(0, 20, 0.5, -FULL_H/2)
main.BackgroundColor3 = C_BG
main.BorderSizePixel = 0
main.Active = true
main.Draggable = true
main.Parent = gui

local mc = Instance.new("UICorner"); mc.CornerRadius = UDim.new(0, 12); mc.Parent = main
local ms = Instance.new("UIStroke"); ms.Color = C_BORDER; ms.Thickness = 1; ms.Parent = main

-- Header (compact)
local header = Instance.new("Frame")
header.Name = "Header"
header.Size = UDim2.new(1, 0, 0, 24)
header.BackgroundColor3 = C_CARD
header.BorderSizePixel = 0
header.Parent = main
local hc = Instance.new("UICorner"); hc.CornerRadius = UDim.new(0, 12); hc.Parent = header
local hfix = Instance.new("Frame")
hfix.Size = UDim2.new(1, 0, 0, 8); hfix.Position = UDim2.new(0, 0, 1, -8)
hfix.BackgroundColor3 = C_CARD; hfix.BorderSizePixel = 0; hfix.Parent = header

local titleLbl = Instance.new("TextLabel")
titleLbl.Size = UDim2.new(1, -80, 1, 0)
titleLbl.Position = UDim2.new(0, 10, 0, 0)
titleLbl.BackgroundTransparency = 1
titleLbl.Text = "🎯 Auction Sniper"
titleLbl.TextColor3 = C_TEXT
titleLbl.TextXAlignment = Enum.TextXAlignment.Left
titleLbl.Font = Enum.Font.GothamBold
titleLbl.TextSize = 10
titleLbl.Parent = header

-- Minimize button
local minimizeBtn = Instance.new("TextButton")
minimizeBtn.Size = UDim2.new(0, 18, 0, 18)
minimizeBtn.Position = UDim2.new(1, -44, 0.5, -9)
minimizeBtn.BackgroundColor3 = Color3.fromRGB(90, 90, 100)
minimizeBtn.BorderSizePixel = 0
minimizeBtn.Text = "—"
minimizeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
minimizeBtn.Font = Enum.Font.GothamBold
minimizeBtn.TextSize = 11
minimizeBtn.Parent = header
local mbc = Instance.new("UICorner"); mbc.CornerRadius = UDim.new(0, 4); mbc.Parent = minimizeBtn

-- Close button
local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 18, 0, 18)
closeBtn.Position = UDim2.new(1, -24, 0.5, -9)
closeBtn.BackgroundColor3 = C_RED
closeBtn.BorderSizePixel = 0
closeBtn.Text = "✕"
closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 10
closeBtn.Parent = header
local cbc = Instance.new("UICorner"); cbc.CornerRadius = UDim.new(0, 4); cbc.Parent = closeBtn

-- Content (biar bisa hide saat minimize)
local content = Instance.new("Frame")
content.Name = "Content"
content.Size = UDim2.new(1, 0, 1, -24)
content.Position = UDim2.new(0, 0, 0, 24)
content.BackgroundTransparency = 1
content.Parent = main

-- Status
local statusLbl = Instance.new("TextLabel")
statusLbl.Size = UDim2.new(1, -20, 0, 14)
statusLbl.Position = UDim2.new(0, 10, 0, 8)
statusLbl.BackgroundTransparency = 1
statusLbl.Text = "🔍 Loading auction..."
statusLbl.TextColor3 = C_SUB
statusLbl.Font = Enum.Font.Gotham
statusLbl.TextSize = 9
statusLbl.TextXAlignment = Enum.TextXAlignment.Left
statusLbl.Parent = content

-- Scroll
local scroll = Instance.new("ScrollingFrame")
scroll.Size = UDim2.new(1, -20, 1, -56)
scroll.Position = UDim2.new(0, 10, 0, 28)
scroll.BackgroundColor3 = Color3.fromRGB(14, 14, 18)
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 3
scroll.ScrollBarImageColor3 = C_BORDER
scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.Parent = content
local sc = Instance.new("UICorner"); sc.CornerRadius = UDim.new(0, 8); sc.Parent = scroll
local ss = Instance.new("UIStroke"); ss.Color = C_BORDER; ss.Thickness = 1; ss.Parent = scroll

local scrollLayout = Instance.new("UIListLayout")
scrollLayout.Padding = UDim.new(0, 3)
scrollLayout.SortOrder = Enum.SortOrder.LayoutOrder
scrollLayout.Parent = scroll

local scrollPad = Instance.new("UIPadding")
scrollPad.PaddingTop = UDim.new(0, 4)
scrollPad.PaddingBottom = UDim.new(0, 4)
scrollPad.PaddingLeft = UDim.new(0, 4)
scrollPad.PaddingRight = UDim.new(0, 4)
scrollPad.Parent = scroll

-- ============ STATE ============
local watchData = {}
local currentLots = {}
local minimized = false
local fullSize = UDim2.new(0, FULL_W, 0, FULL_H)
local miniSize = UDim2.new(0, MINI_W, 0, MINI_H)

-- ============ CREATE WATCH ROW ============
local function createWatchRow(itemName, defaultTimer)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 76)
    row.BackgroundColor3 = C_ROW
    row.BorderSizePixel = 0
    row.Parent = scroll
    local rc = Instance.new("UICorner"); rc.CornerRadius = UDim.new(0, 6); rc.Parent = row

    local rp = Instance.new("UIPadding")
    rp.PaddingTop = UDim.new(0, 4)
    rp.PaddingBottom = UDim.new(0, 4)
    rp.PaddingLeft = UDim.new(0, 6)
    rp.PaddingRight = UDim.new(0, 6)
    rp.Parent = row

    local nameLbl = Instance.new("TextLabel")
    nameLbl.Size = UDim2.new(1, -60, 0, 14)
    nameLbl.Position = UDim2.new(0, 0, 0, 0)
    nameLbl.BackgroundTransparency = 1
    nameLbl.Text = itemName
    nameLbl.TextColor3 = C_TEXT
    nameLbl.Font = Enum.Font.GothamBold
    nameLbl.TextSize = 10
    nameLbl.TextXAlignment = Enum.TextXAlignment.Left
    nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
    nameLbl.Parent = row

    local infoLbl = Instance.new("TextLabel")
    infoLbl.Size = UDim2.new(1, -60, 0, 12)
    infoLbl.Position = UDim2.new(0, 0, 0, 14)
    infoLbl.BackgroundTransparency = 1
    infoLbl.Text = "💰 — | ⏱️ —"
    infoLbl.TextColor3 = C_SUB
    infoLbl.Font = Enum.Font.Code
    infoLbl.TextSize = 8
    infoLbl.TextXAlignment = Enum.TextXAlignment.Left
    infoLbl.TextTruncate = Enum.TextTruncate.AtEnd
    infoLbl.Parent = row

    local timerInput = Instance.new("TextBox")
    timerInput.Size = UDim2.new(0, 80, 0, 18)
    timerInput.Position = UDim2.new(0, 0, 0, 28)
    timerInput.BackgroundColor3 = C_BG
    timerInput.BorderSizePixel = 0
    timerInput.Text = formatTimerInput(defaultTimer)
    timerInput.PlaceholderText = "1m"
    timerInput.TextColor3 = C_GOLD
    timerInput.PlaceholderColor3 = C_SUB
    timerInput.Font = Enum.Font.Code
    timerInput.TextSize = 8
    timerInput.ClearTextOnFocus = false
    timerInput.TextXAlignment = Enum.TextXAlignment.Center
    timerInput.Parent = row
    local pic = Instance.new("UICorner"); pic.CornerRadius = UDim.new(0, 4); pic.Parent = timerInput

    local setBtn = Instance.new("TextButton")
    setBtn.Size = UDim2.new(0, 34, 0, 18)
    setBtn.Position = UDim2.new(0, 84, 0, 28)
    setBtn.BackgroundColor3 = C_ACCENT
    setBtn.Text = "SET"
    setBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    setBtn.Font = Enum.Font.GothamBold
    setBtn.TextSize = 8
    setBtn.Parent = row
    local sbc = Instance.new("UICorner"); sbc.CornerRadius = UDim.new(0, 4); sbc.Parent = setBtn

    local toggleBtn = Instance.new("TextButton")
    toggleBtn.Size = UDim2.new(0, 40, 0, 18)
    toggleBtn.Position = UDim2.new(1, -40, 0, 28)
    toggleBtn.BackgroundColor3 = C_BG
    toggleBtn.BorderSizePixel = 0
    toggleBtn.Text = ""
    toggleBtn.AutoButtonColor = false
    toggleBtn.Parent = row
    local tbc = Instance.new("UICorner"); tbc.CornerRadius = UDim.new(0, 9); tbc.Parent = toggleBtn
    local tbs = Instance.new("UIStroke"); tbs.Color = C_BORDER; tbs.Thickness = 1; tbs.Parent = toggleBtn

    local knob = Instance.new("Frame")
    knob.Size = UDim2.new(0, 14, 0, 14)
    knob.Position = UDim2.new(0, 2, 0.5, -7)
    knob.BackgroundColor3 = Color3.fromRGB(200, 200, 210)
    knob.BorderSizePixel = 0
    knob.Parent = toggleBtn
    local kc = Instance.new("UICorner"); kc.CornerRadius = UDim.new(1, 0); kc.Parent = knob

    local statusLbl2 = Instance.new("TextLabel")
    statusLbl2.Size = UDim2.new(1, 0, 0, 10)
    statusLbl2.Position = UDim2.new(0, 0, 0, 50)
    statusLbl2.BackgroundTransparency = 1
    statusLbl2.Text = "⏹️ OFF"
    statusLbl2.TextColor3 = C_SUB
    statusLbl2.Font = Enum.Font.Code
    statusLbl2.TextSize = 8
    statusLbl2.TextXAlignment = Enum.TextXAlignment.Left
    statusLbl2.Parent = row

    local d = {
        name = itemName,
        row = row,
        infoLbl = infoLbl,
        timerInput = timerInput,
        setBtn = setBtn,
        toggleBtn = toggleBtn,
        knob = knob,
        statusLbl = statusLbl2,
        targetTimer = defaultTimer,
        enabled = false,
        match = nil,
        lastFire = 0,
        fireCount = 0,
    }
    watchData[itemName] = d

    setBtn.MouseButton1Click:Connect(function()
        local val = parseTimerInput(timerInput.Text)
        if val and val > 0 then
            d.targetTimer = val
            timerInput.Text = formatTimerInput(val)
            setBtn.Text = "✓"
            setBtn.BackgroundColor3 = C_GREEN
            task.wait(0.8)
            setBtn.Text = "SET"
            setBtn.BackgroundColor3 = C_ACCENT
        else
            setBtn.Text = "✗"
            setBtn.BackgroundColor3 = C_RED
            task.wait(0.8)
            setBtn.Text = "SET"
            setBtn.BackgroundColor3 = C_ACCENT
        end
    end)

    timerInput.FocusLost:Connect(function()
        local val = parseTimerInput(timerInput.Text)
        if val and val > 0 then
            d.targetTimer = val
            timerInput.Text = formatTimerInput(val)
        end
    end)

    toggleBtn.MouseButton1Click:Connect(function()
        d.enabled = not d.enabled
        if d.enabled then
            toggleBtn.BackgroundColor3 = Color3.fromRGB(40, 60, 90)
            tbs.Color = C_GREEN
            knob:TweenPosition(UDim2.new(1, -16, 0.5, -7), Enum.EasingDirection.Out, Enum.EasingStyle.Quad, 0.15, true)
        else
            toggleBtn.BackgroundColor3 = C_BG
            tbs.Color = C_BORDER
            knob:TweenPosition(UDim2.new(0, 2, 0.5, -7), Enum.EasingDirection.Out, Enum.EasingStyle.Quad, 0.15, true)
        end
    end)
end

for _, item in ipairs(WATCHLIST) do
    createWatchRow(item.name, item.defaultTimer)
end

-- ============ SCAN ============
local normalizedWatchlist = {}
for _, item in ipairs(WATCHLIST) do
    normalizedWatchlist[normalizeName(item.name)] = item.name
end

local function scanAuction()
    local root = resolvePath(SCROLLFRAME_PATH)
    if not root then return end

    currentLots = {}
    for _, item in ipairs(WATCHLIST) do
        currentLots[item.name] = {}
    end

    for _, child in ipairs(root:GetChildren()) do
        if child.Name:match("^Lot_") then
            local idx, ts = extractLotInfo(child.Name)
            if idx and idx < MONEY_LOT_COUNT then
                local itemName = nil
                for _, obj in ipairs(child:GetDescendants()) do
                    if obj:IsA("TextLabel") and obj.Name == "ItemName" then
                        itemName = obj.Text
                        break
                    end
                end

                if itemName then
                    local norm = normalizeName(itemName)
                    local watchName = normalizedWatchlist[norm]
                    if watchName then
                        local price, priceText = getLotPrice(child)
                        local status, timerSec, timerText = getLotStatus(child)
                        table.insert(currentLots[watchName], {
                            lotName = child.Name,
                            lotId = lotNameToId(child.Name),
                            timestamp = ts,
                            lotIndex = idx,
                            price = price,
                            priceText = priceText,
                            status = status,
                            timerSec = timerSec,
                            timerText = timerText,
                        })
                    end
                end
            end
        end
    end
end

-- ============ UPDATE UI ============
local function updateUI()
    for _, item in ipairs(WATCHLIST) do
        local name = item.name
        local d = watchData[name]
        local matches = currentLots[name] or {}

        if #matches == 0 then
            d.match = nil
            d.infoLbl.Text = "💰 — | ⏱️ —"
            d.infoLbl.TextColor3 = C_SUB
            d.statusLbl.Text = d.enabled and "🟡 nunggu muncul" or "⏹️ OFF"
            d.statusLbl.TextColor3 = d.enabled and C_GOLD or C_SUB
            d.row.BackgroundColor3 = C_ROW
        else
            local m = matches[1]
            d.match = m

            d.infoLbl.Text = string.format("💰 %s | ⏱️ %s | Lot #%d",
                m.priceText or "?", formatTimer(m.timerSec), m.lotIndex)
            d.infoLbl.TextColor3 = C_GOLD

            local isExpired = m.status == "EXP" or m.status == "SOLD"
                or (m.timerSec and m.timerSec <= 0)

            if isExpired then
                d.statusLbl.Text = string.format("⏸️ %s", m.status)
                d.statusLbl.TextColor3 = C_GOLD
                d.row.BackgroundColor3 = C_ROW
            elseif d.enabled then
                if m.timerSec and m.timerSec <= d.targetTimer then
                    d.statusLbl.Text = string.format("🔥 AKTIF — %s ≤ %s (x%d)",
                        formatTimer(m.timerSec), formatTimerInput(d.targetTimer), d.fireCount)
                    d.statusLbl.TextColor3 = C_GREEN_B
                    d.row.BackgroundColor3 = C_ROW_ACT
                else
                    d.statusLbl.Text = string.format("⏳ %s > %s",
                        formatTimer(m.timerSec), formatTimerInput(d.targetTimer))
                    d.statusLbl.TextColor3 = C_GOLD
                    d.row.BackgroundColor3 = C_ROW_WAIT
                end
            else
                d.statusLbl.Text = "⚪ siap (toggle OFF)"
                d.statusLbl.TextColor3 = C_SUB
                d.row.BackgroundColor3 = C_ROW
            end
        end
    end
end

-- ============ AUTO-FIRE ============
local function autoFireCheck()
    local now = tick()

    for _, item in ipairs(WATCHLIST) do
        local name = item.name
        local d = watchData[name]
        if d.enabled and d.match then
            local m = d.match
            local isExpired = m.status == "EXP" or m.status == "SOLD"
                or (m.timerSec and m.timerSec <= 0)

            if not isExpired then
                if m.timerSec and m.timerSec <= d.targetTimer then
                    if now - d.lastFire >= FIRE_INTERVAL then
                        d.lastFire = now
                        d.fireCount = d.fireCount + 1
                        pcall(function()
                            firePayload(m)
                        end)
                    end
                end
            end
        end
    end
end

-- ============ MINIMIZE / CLOSE ============
minimizeBtn.MouseButton1Click:Connect(function()
    minimized = not minimized

    if minimized then
        -- Minimize: kecilin frame ke header tipis
        TweenService:Create(main, TweenInfo.new(0.2, Enum.EasingStyle.Quad), {
            Size = miniSize
        }):Play()
        content.Visible = false
        minimizeBtn.Text = "▢"
    else
        -- Expand: balik ke full size
        TweenService:Create(main, TweenInfo.new(0.2, Enum.EasingStyle.Quad), {
            Size = fullSize
        }):Play()
        content.Visible = true
        minimizeBtn.Text = "—"
    end
end)

closeBtn.MouseButton1Click:Connect(function()
    isShutdown = true
    restoreAuction()
    gui:Destroy()
    print("[Sniper] Closed — auction disabled")
end)

-- ============ INIT ============
local setupOk = setupAuctionOffScreen()
if not setupOk then
    statusLbl.Text = "❌ Auction gak ditemukan"
    statusLbl.TextColor3 = C_RED
    return
end

task.wait(1.5)

scanAuction()
updateUI()
statusLbl.Text = "✅ Ready — set timer target & toggle"
statusLbl.TextColor3 = C_GREEN

task.spawn(function()
    while gui.Parent do
        task.wait(SCAN_INTERVAL)
        if not gui.Parent then break end
        pcall(scanAuction)
        pcall(updateUI)
    end
end)

task.spawn(function()
    while gui.Parent do
        task.wait(1)
        if not gui.Parent then break end
        pcall(autoFireCheck)
    end
end)

print("✅ Auction Sniper (Per-Item Timer + Minimize) loaded")
print("[Sniper] Watchlist:")
for _, item in ipairs(WATCHLIST) do
    print(string.format("  • %s — default ≤ %s", item.name, formatTimerInput(item.defaultTimer)))
end
