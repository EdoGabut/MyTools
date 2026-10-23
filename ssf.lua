-- ============================================================
-- Auto Buy All — Minimalis
-- - 1 toggle ON/OFF buat semua shop
-- - Scan Seed + Gear + Crate
-- - Cuma tampil item yang ada stock
-- - Skip "Green Bean" (blacklist)
-- ============================================================
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

local remote = ReplicatedStorage:WaitForChild("SharedModules")
    :WaitForChild("Packet"):WaitForChild("RemoteEvent")

-- ===== CONFIG =====
local BUY_INTERVAL = 0.5
local SCAN_INTERVAL = 1

-- ===== BLACKLIST (skip item) =====
local BLACKLIST = {
    ["Green Bean"] = true,
    ["Spirit Green Bean"] = true,
}

local SHOPS = {
    {
        name = "Seed",
        base = "game.Players.LocalPlayer.PlayerGui.SeedShop.Frame.NormalShop",
        opcode1 = 0xB8,
        opcode2 = 0x00,
        color = Color3.fromRGB(80, 200, 120),
        icon = "🌱",
    },
    {
        name = "Gear",
        base = "game.Players.LocalPlayer.PlayerGui.GearShop.Frame.ScrollingFrame",
        opcode1 = 0xCE,
        opcode2 = 0x00,
        color = Color3.fromRGB(96, 140, 230),
        icon = "💧",
    },
    {
        name = "Crate",
        base = "game.Players.LocalPlayer.PlayerGui.CrateShop.Frame.ScrollingFrame",
        opcode1 = 0xCC,
        opcode2 = 0x00,
        color = Color3.fromRGB(220, 160, 80),
        icon = "📦",
    },
}

-- ===== HELPERS =====
local function resolvePath(pathStr)
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

local function buildBuyPayload(op1, op2, itemName)
    local len = #itemName
    if len > 255 then return nil end
    return buffer.fromstring(
        string.char(op1) .. string.char(op2) ..
        string.char(len) .. itemName
    )
end

-- ===== SCAN =====
local function scanShop(shop)
    local items = {}
    local base = resolvePath(shop.base)
    if not base then return items end

    for _, child in ipairs(base:GetChildren()) do
        if child.Name ~= "ItemTemplate" and child.Name ~= "Main_Frame" then
            -- ✅ SKIP BLACKLIST
            if BLACKLIST[child.Name] then
                continue
            end

            local mainFrame = child:FindFirstChild("Main_Frame")
            if mainFrame then
                local stockLabel = mainFrame:FindFirstChild("Stock_Text")
                if stockLabel and stockLabel:IsA("TextLabel") then
                    local stock = parseStock(stockLabel)
                    if stock and stock > 0 then
                        table.insert(items, {
                            name = child.Name,
                            stock = stock,
                        })
                    end
                end
            end
        end
    end
    table.sort(items, function(a, b) return a.name < b.name end)
    return items
end

-- ============================================================
-- ===== GUI (MINIMALIS) =====
-- ============================================================
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "AutoBuyAll"
screenGui.ResetOnSpawn = false
screenGui.Parent = player:WaitForChild("PlayerGui")

local COLORS = {
    bg        = Color3.fromRGB(22, 22, 28),
    header    = Color3.fromRGB(16, 16, 20),
    card      = Color3.fromRGB(28, 28, 34),
    text      = Color3.fromRGB(235, 235, 240),
    textDim   = Color3.fromRGB(140, 145, 160),
    green     = Color3.fromRGB(80, 190, 120),
    greenHv   = Color3.fromRGB(100, 220, 140),
    red       = Color3.fromRGB(220, 80, 90),
    stroke    = Color3.fromRGB(48, 48, 60),
    disabled  = Color3.fromRGB(70, 70, 85),
}

local function corner(p, r)
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r or 8); c.Parent = p
end

local FRAME_WIDTH = 280
local FRAME_HEIGHT = 260
local FRAME_HEIGHT_MIN = 42

local main = Instance.new("Frame")
main.Size = UDim2.new(0, FRAME_WIDTH, 0, FRAME_HEIGHT)
main.Position = UDim2.new(0, 15, 0, 15)
main.BackgroundColor3 = COLORS.bg
main.BorderSizePixel = 0
main.Active = true
main.Parent = screenGui
corner(main, 12)

local mainStroke = Instance.new("UIStroke")
mainStroke.Color = COLORS.stroke
mainStroke.Thickness = 1
mainStroke.Parent = main

-- Drag
local dragging, dragStart, startPos
main.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = main.Position
    end
end)
main.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        dragging = false
    end
end)
UserInputService.InputChanged:Connect(function(input)
    if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = input.Position - dragStart
        main.Position = UDim2.new(
            startPos.X.Scale, startPos.X.Offset + delta.X,
            startPos.Y.Scale, startPos.Y.Offset + delta.Y
        )
    end
end)

-- ===== HEADER =====
local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 34)
header.BackgroundColor3 = COLORS.header
header.BorderSizePixel = 0
header.Parent = main
corner(header, 12)

local headerFix = Instance.new("Frame")
headerFix.Size = UDim2.new(1, 0, 0, 12)
headerFix.Position = UDim2.new(0, 0, 1, -12)
headerFix.BackgroundColor3 = COLORS.header
headerFix.BorderSizePixel = 0
headerFix.Parent = header

-- Toggle switch
local toggleTrack = Instance.new("Frame")
toggleTrack.Size = UDim2.new(0, 38, 0, 18)
toggleTrack.Position = UDim2.new(0, 10, 0.5, -9)
toggleTrack.BackgroundColor3 = COLORS.disabled
toggleTrack.BorderSizePixel = 0
toggleTrack.Parent = header
corner(toggleTrack, 9)

local toggleKnob = Instance.new("Frame")
toggleKnob.Size = UDim2.new(0, 14, 0, 14)
toggleKnob.Position = UDim2.new(0, 2, 0.5, -7)
toggleKnob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
toggleKnob.BorderSizePixel = 0
toggleKnob.Parent = toggleTrack
corner(toggleKnob, 7)

local titleLbl = Instance.new("TextLabel")
titleLbl.Size = UDim2.new(1, -110, 1, 0)
titleLbl.Position = UDim2.new(0, 54, 0, 0)
titleLbl.BackgroundTransparency = 1
titleLbl.Text = "🛒 Auto Buy All"
titleLbl.TextColor3 = COLORS.text
titleLbl.TextXAlignment = Enum.TextXAlignment.Left
titleLbl.Font = Enum.Font.GothamBold
titleLbl.TextSize = 12
titleLbl.Parent = header

local statusDot = Instance.new("Frame")
statusDot.Size = UDim2.new(0, 8, 0, 8)
statusDot.Position = UDim2.new(1, -76, 0.5, -4)
statusDot.BackgroundColor3 = COLORS.disabled
statusDot.BorderSizePixel = 0
statusDot.Parent = header
corner(statusDot, 4)

local minBtn = Instance.new("TextButton")
minBtn.Size = UDim2.new(0, 24, 0, 24)
minBtn.Position = UDim2.new(1, -56, 0, 5)
minBtn.BackgroundColor3 = COLORS.card
minBtn.Text = "—"
minBtn.TextColor3 = COLORS.text
minBtn.Font = Enum.Font.GothamBold
minBtn.TextSize = 12
minBtn.Parent = header
corner(minBtn, 6)

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 24, 0, 24)
closeBtn.Position = UDim2.new(1, -30, 0, 5)
closeBtn.BackgroundColor3 = COLORS.red
closeBtn.Text = "✕"
closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 12
closeBtn.Parent = header
corner(closeBtn, 6)

local toggleClick = Instance.new("TextButton")
toggleClick.Size = UDim2.new(0, 50, 1, 0)
toggleClick.Position = UDim2.new(0, 6, 0, 0)
toggleClick.BackgroundTransparency = 1
toggleClick.Text = ""
toggleClick.BorderSizePixel = 0
toggleClick.Parent = header

-- ===== BODY =====
local body = Instance.new("Frame")
body.Size = UDim2.new(1, -16, 1, -42)
body.Position = UDim2.new(0, 8, 0, 38)
body.BackgroundTransparency = 1
body.Parent = main

-- ===== LIST =====
local listFrame = Instance.new("ScrollingFrame")
listFrame.Size = UDim2.new(1, 0, 1, 0)
listFrame.BackgroundColor3 = Color3.fromRGB(14, 14, 18)
listFrame.BorderSizePixel = 0
listFrame.ScrollBarThickness = 3
listFrame.ScrollBarImageColor3 = COLORS.stroke
listFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
listFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
listFrame.Parent = body
corner(listFrame, 8)

local listStroke = Instance.new("UIStroke")
listStroke.Color = COLORS.stroke
listStroke.Thickness = 1
listStroke.Parent = listFrame

local listPad = Instance.new("UIPadding", listFrame)
listPad.PaddingTop = UDim.new(0, 6)
listPad.PaddingBottom = UDim.new(0, 6)
listPad.PaddingLeft = UDim.new(0, 6)
listPad.PaddingRight = UDim.new(0, 6)

local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 3)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Parent = listFrame

-- ===== STATE =====
local isRunning = false
local shopData = {}

local function setToggleVisual(on)
    if on then
        TweenService:Create(toggleTrack, TweenInfo.new(0.15), {
            BackgroundColor3 = COLORS.green
        }):Play()
        TweenService:Create(toggleKnob, TweenInfo.new(0.15), {
            Position = UDim2.new(1, -16, 0.5, -7)
        }):Play()
        TweenService:Create(statusDot, TweenInfo.new(0.15), {
            BackgroundColor3 = COLORS.green
        }):Play()
    else
        TweenService:Create(toggleTrack, TweenInfo.new(0.15), {
            BackgroundColor3 = COLORS.disabled
        }):Play()
        TweenService:Create(toggleKnob, TweenInfo.new(0.15), {
            Position = UDim2.new(0, 2, 0.5, -7)
        }):Play()
        TweenService:Create(statusDot, TweenInfo.new(0.15), {
            BackgroundColor3 = COLORS.disabled
        }):Play()
    end
end

local function rebuildList()
    for _, child in ipairs(listFrame:GetChildren()) do
        if child:IsA("Frame") or child:IsA("TextLabel") then
            child:Destroy()
        end
    end

    local totalItems = 0
    local order = 0

    for _, shop in ipairs(SHOPS) do
        local items = shopData[shop.name] or {}
        if #items > 0 then
            order += 1
            local sectionHeader = Instance.new("TextLabel")
            sectionHeader.Size = UDim2.new(1, 0, 0, 16)
            sectionHeader.BackgroundTransparency = 1
            sectionHeader.Text = string.format("%s %s (%d)", shop.icon, shop.name, #items)
            sectionHeader.TextColor3 = shop.color
            sectionHeader.Font = Enum.Font.GothamBold
            sectionHeader.TextSize = 10
            sectionHeader.TextXAlignment = Enum.TextXAlignment.Left
            sectionHeader.LayoutOrder = order
            sectionHeader.Parent = listFrame

            for _, item in ipairs(items) do
                order += 1
                local row = Instance.new("Frame")
                row.Size = UDim2.new(1, 0, 0, 20)
                row.BackgroundColor3 = COLORS.card
                row.BorderSizePixel = 0
                row.LayoutOrder = order
                row.Parent = listFrame
                corner(row, 4)

                local dot = Instance.new("Frame")
                dot.Size = UDim2.new(0, 5, 0, 5)
                dot.Position = UDim2.new(0, 6, 0.5, -2.5)
                dot.BackgroundColor3 = shop.color
                dot.BorderSizePixel = 0
                dot.Parent = row
                corner(dot, 2.5)

                local nameLbl = Instance.new("TextLabel")
                nameLbl.Size = UDim2.new(1, -60, 1, 0)
                nameLbl.Position = UDim2.new(0, 16, 0, 0)
                nameLbl.BackgroundTransparency = 1
                nameLbl.Text = item.name
                nameLbl.TextColor3 = COLORS.text
                nameLbl.Font = Enum.Font.GothamMedium
                nameLbl.TextSize = 9
                nameLbl.TextXAlignment = Enum.TextXAlignment.Left
                nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
                nameLbl.Parent = row

                local stockLbl = Instance.new("TextLabel")
                stockLbl.Size = UDim2.new(0, 40, 1, 0)
                stockLbl.Position = UDim2.new(1, -44, 0, 0)
                stockLbl.BackgroundTransparency = 1
                stockLbl.Text = "x" .. item.stock
                stockLbl.TextColor3 = shop.color
                stockLbl.Font = Enum.Font.Code
                stockLbl.TextSize = 9
                stockLbl.TextXAlignment = Enum.TextXAlignment.Right
                stockLbl.Parent = row

                totalItems += 1
            end
        end
    end

    if totalItems == 0 then
        local empty = Instance.new("TextLabel")
        empty.Size = UDim2.new(1, 0, 0, 40)
        empty.BackgroundTransparency = 1
        empty.Text = "📭 Gak ada stock / shop gak kebuka"
        empty.TextColor3 = COLORS.textDim
        empty.Font = Enum.Font.Gotham
        empty.TextSize = 10
        empty.TextXAlignment = Enum.TextXAlignment.Center
        empty.Parent = listFrame
    end
end

local function refreshAll()
    for _, shop in ipairs(SHOPS) do
        shopData[shop.name] = scanShop(shop)
    end
    rebuildList()
end

-- ===== AUTO BUY LOOP =====
local function startAutoBuy()
    task.spawn(function()
        while screenGui.Parent do
            if isRunning then
                for _, shop in ipairs(SHOPS) do
                    if not isRunning then break end
                    local items = shopData[shop.name] or {}
                    for _, item in ipairs(items) do
                        if not isRunning then break end
                        -- ✅ DOUBLE CHECK BLACKLIST
                        if BLACKLIST[item.name] then
                            continue
                        end
                        if item.stock and item.stock > 0 then
                            local payload = buildBuyPayload(shop.opcode1, shop.opcode2, item.name)
                            if payload then
                                pcall(function()
                                    remote:FireServer(payload)
                                end)
                            end
                        end
                    end
                end
            end
            task.wait(BUY_INTERVAL)
        end
    end)
end

-- ===== TOGGLE =====
local function toggleRun()
    isRunning = not isRunning
    setToggleVisual(isRunning)
    print("[AutoBuy] " .. (isRunning and "ON" or "OFF"))
end

toggleClick.MouseButton1Click:Connect(toggleRun)

-- ===== MINIMIZE =====
local isMinimized = false
minBtn.MouseButton1Click:Connect(function()
    isMinimized = not isMinimized
    if isMinimized then
        body.Visible = false
        main.Size = UDim2.new(0, FRAME_WIDTH, 0, FRAME_HEIGHT_MIN)
        minBtn.Text = "+"
    else
        body.Visible = true
        main.Size = UDim2.new(0, FRAME_WIDTH, 0, FRAME_HEIGHT)
        minBtn.Text = "—"
    end
end)

-- ===== CLOSE =====
closeBtn.MouseButton1Click:Connect(function()
    isRunning = false
    screenGui:Destroy()
end)

-- ===== INIT =====
refreshAll()
startAutoBuy()
setToggleVisual(false)

task.spawn(function()
    while screenGui.Parent do
        task.wait(SCAN_INTERVAL)
        refreshAll()
    end
end)

print("✅ Auto Buy All loaded")
print("   Toggle di header buat ON/OFF")
print("   Blacklist: Green Bean (skip)")
