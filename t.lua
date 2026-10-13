-- ============================================================
-- Trowel Sender — FIXED (byte 0x04 + nonce-aware)
-- ============================================================
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local UserInputService  = game:GetService("UserInputService")

local player = Players.LocalPlayer
local remote = ReplicatedStorage:WaitForChild("SharedModules")
    :WaitForChild("Packet"):WaitForChild("RemoteEvent")

-- ===== CONFIG =====
local TARGET_USER_ID = 11142670172
local ITEM_NAME      = "Trowel"
local CATEGORY       = "Trowels"
local DEFAULT_COUNT  = 10
local MAX_COUNT      = 255   -- format 0x05 cuma 1 byte

-- ===== PAYLOAD ASLI (dari spy) =====
-- Ini payload yang LU SPY, bukan hasil decode.
-- f64 di offset 2 = nonce/hash, BUKAN UserID.
local RAW_TEMPLATE = "\140\001-\000\000\224:=\193\004B\028\005\001\028\v\aItemKey\v\006Trowel\v\005Count\005\n\v\bCategory\v\aTrowels\000\000\000"
local RAW_BUF      = buffer.fromstring(RAW_TEMPLATE)
local HEADER_F64   = buffer.readf64(RAW_BUF, 2)   -- nilai nonce/hash

print(string.format("[Trowel] nonce f64 = %.6f", HEADER_F64))
print("[Trowel] raw template len =", #RAW_TEMPLATE)

-- ===== PAYLOAD BUILDER (FIXED) =====
-- Header benar: 8C 01 [f64 8B] 04 42 1C 05 01 1C
local function buildPayload(f64Value, itemName, count, category)
    local buf = buffer.create(256)
    local pos = 0

    local function w8(n) buffer.writeu8(buf, pos, n); pos += 1 end
    local function wstr(s)
        w8(0x0B); w8(#s)
        for i = 1, #s do w8(string.byte(s, i)) end
    end
    local function wint(n) w8(0x05); w8(n) end

    -- Header
    w8(0x8C); w8(0x01)
    buffer.writef64(buf, pos, f64Value); pos += 8
    w8(0x04)                          -- ← FIX: byte yang hilang
    w8(0x42); w8(0x1C)
    w8(0x05); w8(0x01); w8(0x1C)

    -- Data
    wstr("ItemKey");  wstr(itemName)
    wstr("Count");    wint(count)
    wstr("Category"); wstr(category)

    -- Terminator
    w8(0x00); w8(0x00); w8(0x00)

    local final = buffer.create(pos)
    buffer.copy(final, 0, buf, 0, pos)
    return final
end

-- ===== HEX DUMP (dari cheatsheet §9) =====
local function dumpHex(buf)
    local hex = ""
    for i = 0, buffer.len(buf) - 1 do
        hex = hex .. string.format("%02X ", buffer.readu8(buf, i))
    end
    return hex
end

-- ============================================================
-- ===== GUI =====
-- ============================================================
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "TrowelSender"
screenGui.ResetOnSpawn = false
screenGui.Parent = player:WaitForChild("PlayerGui")

local COLORS = {
    bg = Color3.fromRGB(22,22,28), header = Color3.fromRGB(16,16,20),
    input = Color3.fromRGB(15,15,20), text = Color3.fromRGB(235,235,240),
    textDim = Color3.fromRGB(140,140,155), placeholder = Color3.fromRGB(110,110,125),
    green = Color3.fromRGB(80,200,120), greenHv = Color3.fromRGB(100,220,140),
    red = Color3.fromRGB(200,70,70), stroke = Color3.fromRGB(60,60,72),
}

local function corner(p, r)
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r or 8); c.Parent = p
end

local frame = Instance.new("Frame")
frame.Size = UDim2.new(0, 280, 0, 210)
frame.Position = UDim2.new(0, 15, 0, 15)
frame.BackgroundColor3 = COLORS.bg
frame.BorderSizePixel = 0
frame.Active = true
frame.Parent = screenGui
corner(frame, 12)

local stroke = Instance.new("UIStroke")
stroke.Color = COLORS.stroke; stroke.Transparency = 0.4; stroke.Parent = frame

-- Drag
local dragging, dragStart, startPos
frame.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
    or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true; dragStart = input.Position; startPos = frame.Position
    end
end)
frame.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
    or input.UserInputType == Enum.UserInputType.Touch then
        dragging = false
    end
end)
UserInputService.InputChanged:Connect(function(input)
    if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
    or input.UserInputType == Enum.UserInputType.Touch) then
        local d = input.Position - dragStart
        frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X,
                                   startPos.Y.Scale, startPos.Y.Offset + d.Y)
    end
end)

-- Title
local titleBar = Instance.new("Frame")
titleBar.Size = UDim2.new(1, 0, 0, 30)
titleBar.BackgroundColor3 = COLORS.header
titleBar.BorderSizePixel = 0
titleBar.ZIndex = 20
titleBar.Parent = frame
corner(titleBar, 12)

local fix = Instance.new("Frame")
fix.Size = UDim2.new(1, 0, 0, 10)
fix.Position = UDim2.new(0, 0, 1, -10)
fix.BackgroundColor3 = COLORS.header
fix.BorderSizePixel = 0
fix.ZIndex = 20
fix.Parent = titleBar

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -40, 1, 0)
title.Position = UDim2.new(0, 12, 0, 0)
title.BackgroundTransparency = 1
title.Text = "🛠 Trowel Sender"
title.TextColor3 = COLORS.text
title.Font = Enum.Font.GothamBold
title.TextSize = 12
title.TextXAlignment = Enum.TextXAlignment.Left
title.ZIndex = 21
title.Parent = titleBar

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 24, 0, 24)
closeBtn.Position = UDim2.new(1, -30, 0, 3)
closeBtn.BackgroundColor3 = COLORS.red
closeBtn.Text = "x"                              -- ASCII saja
closeBtn.TextColor3 = Color3.fromRGB(255,255,255)
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 14
closeBtn.BorderSizePixel = 0
closeBtn.AutoButtonColor = false
closeBtn.ZIndex = 21
closeBtn.Parent = titleBar
corner(closeBtn, 5)

local body = Instance.new("Frame")
body.Size = UDim2.new(1, -16, 1, -42)
body.Position = UDim2.new(0, 8, 0, 38)
body.BackgroundTransparency = 1
body.Parent = frame

-- User ID input
local idRow = Instance.new("Frame")
idRow.Size = UDim2.new(1, 0, 0, 32)
idRow.Position = UDim2.new(0, 0, 0, 0)
idRow.BackgroundTransparency = 1
idRow.Parent = body

local idLbl = Instance.new("TextLabel")
idLbl.Size = UDim2.new(0, 90, 1, 0)
idLbl.BackgroundTransparency = 1
idLbl.Text = "Target ID:"
idLbl.TextColor3 = COLORS.textDim
idLbl.Font = Enum.Font.GothamMedium
idLbl.TextSize = 11
idLbl.TextXAlignment = Enum.TextXAlignment.Left
idLbl.Parent = idRow

local idBox = Instance.new("TextBox")
idBox.Size = UDim2.new(1, -90, 1, 0)
idBox.Position = UDim2.new(0, 90, 0, 0)
idBox.BackgroundColor3 = COLORS.input
idBox.Text = tostring(TARGET_USER_ID)
idBox.TextColor3 = COLORS.text
idBox.Font = Enum.Font.Code
idBox.TextSize = 12
idBox.TextXAlignment = Enum.TextXAlignment.Center
idBox.ClearTextOnFocus = false
idBox.BorderSizePixel = 0
idBox.Parent = idRow
corner(idBox, 6)

-- Count input
local cntRow = Instance.new("Frame")
cntRow.Size = UDim2.new(1, 0, 0, 32)
cntRow.Position = UDim2.new(0, 0, 0, 38)
cntRow.BackgroundTransparency = 1
cntRow.Parent = body

local cntLbl = Instance.new("TextLabel")
cntLbl.Size = UDim2.new(0, 90, 1, 0)
cntLbl.BackgroundTransparency = 1
cntLbl.Text = "Count (1-255):"
cntLbl.TextColor3 = COLORS.textDim
cntLbl.Font = Enum.Font.GothamMedium
cntLbl.TextSize = 11
cntLbl.TextXAlignment = Enum.TextXAlignment.Left
cntLbl.Parent = cntRow

local cntBox = Instance.new("TextBox")
cntBox.Size = UDim2.new(1, -90, 1, 0)
cntBox.Position = UDim2.new(0, 90, 0, 0)
cntBox.BackgroundColor3 = COLORS.input
cntBox.Text = tostring(DEFAULT_COUNT)
cntBox.TextColor3 = COLORS.text
cntBox.Font = Enum.Font.Code
cntBox.TextSize = 12
cntBox.TextXAlignment = Enum.TextXAlignment.Center
cntBox.ClearTextOnFocus = false
cntBox.BorderSizePixel = 0
cntBox.Parent = cntRow
corner(cntBox, 6)

-- Send button
local sendBtn = Instance.new("TextButton")
sendBtn.Size = UDim2.new(1, 0, 0, 34)
sendBtn.Position = UDim2.new(0, 0, 0, 78)
sendBtn.BackgroundColor3 = COLORS.green
sendBtn.Text = "SEND TROWEL"
sendBtn.TextColor3 = Color3.fromRGB(255,255,255)
sendBtn.Font = Enum.Font.GothamBold
sendBtn.TextSize = 12
sendBtn.BorderSizePixel = 0
sendBtn.AutoButtonColor = false
sendBtn.Parent = body
corner(sendBtn, 8)

-- Info label
local infoLbl = Instance.new("TextLabel")
infoLbl.Size = UDim2.new(1, 0, 0, 14)
infoLbl.Position = UDim2.new(0, 0, 0, 118)
infoLbl.BackgroundTransparency = 1
infoLbl.Text = string.format("nonce f64: %.2f", HEADER_F64)
infoLbl.TextColor3 = COLORS.textDim
infoLbl.Font = Enum.Font.Code
infoLbl.TextSize = 10
infoLbl.TextXAlignment = Enum.TextXAlignment.Center
infoLbl.Parent = body

-- Hex output
local hexLbl = Instance.new("TextLabel")
hexLbl.Size = UDim2.new(1, 0, 0, 30)
hexLbl.Position = UDim2.new(0, 0, 0, 136)
hexLbl.BackgroundColor3 = COLORS.input
hexLbl.Text = ""
hexLbl.TextColor3 = COLORS.textDim
hexLbl.Font = Enum.Font.Code
hexLbl.TextSize = 9
hexLbl.TextWrapped = true
hexLbl.TextXAlignment = Enum.TextXAlignment.Left
hexLbl.BorderSizePixel = 0
hexLbl.Parent = body
corner(hexLbl, 6)

-- ===== CLAMP =====
cntBox.FocusLost:Connect(function()
    local n = tonumber(cntBox.Text) or DEFAULT_COUNT
    n = math.clamp(math.floor(n), 1, MAX_COUNT)
    cntBox.Text = tostring(n)
end)

idBox.FocusLost:Connect(function()
    local id = tonumber(idBox.Text)
    if not id or id < 1 then
        idBox.Text = tostring(TARGET_USER_ID)
    end
end)

-- ===== SEND =====
local function flashSend(text, color, duration)
    sendBtn.Text = text
    sendBtn.BackgroundColor3 = color
    sendBtn.Active = false
    task.delay(duration or 1.5, function()
        sendBtn.Text = "SEND TROWEL"
        sendBtn.BackgroundColor3 = COLORS.green
        sendBtn.Active = true
    end)
end

sendBtn.MouseButton1Click:Connect(function()
    local userId = tonumber(idBox.Text) or TARGET_USER_ID
    local count  = tonumber(cntBox.Text) or DEFAULT_COUNT
    count = math.clamp(math.floor(count), 1, MAX_COUNT)

    sendBtn.Text = "Sending..."
    sendBtn.Active = false

    task.spawn(function()
        -- PENTING: f64 di header BUKAN UserID.
        -- Pakai nilai nonce asli dari payload spy.
        local payload = buildPayload(HEADER_F64, ITEM_NAME, count, CATEGORY)

        local hex = dumpHex(payload)
        hexLbl.Text = hex
        print("[Trowel] payload len:", buffer.len(payload))
        print("[Trowel] hex:", hex)

        -- Bandingkan sama template
        if count == 10 then
            if buffer.tostring(payload) == RAW_TEMPLATE then
                print("[Trowel] ✓ EXACT MATCH dengan payload asli")
                flashSend("✓ Match x10", COLORS.green, 2)
            else
                print("[Trowel] ✗ MISMATCH — cek hex di atas")
                flashSend("✗ Mismatch", COLORS.red, 2)
            end
            return
        end

        local ok, err = pcall(function()
            remote:FireServer(payload)
        end)

        if ok then
            flashSend(string.format("✓ Sent x%d", count), COLORS.green, 2)
        else
            warn("[Trowel] FireServer err:", err)
            flashSend("✗ Fire fail", COLORS.red, 2)
        end
    end)
end)

sendBtn.MouseEnter:Connect(function()
    if sendBtn.Active then
        TweenService:Create(sendBtn, TweenInfo.new(0.1),
            { BackgroundColor3 = COLORS.greenHv }):Play()
    end
end)
sendBtn.MouseLeave:Connect(function()
    if sendBtn.Active then
        TweenService:Create(sendBtn, TweenInfo.new(0.1),
            { BackgroundColor3 = COLORS.green }):Play()
    end
end)

closeBtn.MouseButton1Click:Connect(function()
    screenGui:Destroy()
end)

print("[Trowel] loaded. template len =", #RAW_TEMPLATE)
