-- ============================================================
-- Simple Seed Sender GUI (Full Manual)
-- ============================================================
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

-- ===== REMOTE =====
local remote = ReplicatedStorage:WaitForChild("SharedModules")
    :WaitForChild("Packet"):WaitForChild("RemoteEvent")

-- ===== USERNAME → ID =====
local idCache = {}

local function getUserIdFromUsername(username)
    username = username:gsub("^%s+", ""):gsub("%s+$", "")
    if username == "" then return nil end

    if idCache[username] then
        return idCache[username]
    end

    local ok, result = pcall(function()
        return Players:GetUserIdFromNameAsync(username)
    end)
    if ok and result then
        idCache[username] = result
        return result
    end

    local HttpService = game:GetService("HttpService")
    local ok2, response = pcall(function()
        return request({
            Url = "https://users.roblox.com/v1/usernames/users",
            Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = HttpService:JSONEncode({
                usernames = { username },
                excludeBannedUsers = false
            })
        })
    end)
    if ok2 and response and response.StatusCode == 200 then
        local ok3, data = pcall(function()
            return HttpService:JSONDecode(response.Body)
        end)
        if ok3 and data and data.data and data.data[1] then
            local uid = data.data[1].id
            idCache[username] = uid
            return uid
        end
    end

    return nil
end

-- ===== BUILDER PAYLOAD =====
local function buildMailPayload(targetUserId, itemName, count, category)
    local nameLen = #itemName
    local catLen = #category
    if nameLen > 255 or catLen > 255 then return nil end
    if count < 0 or count > 255 then return nil end

    local buf = buffer.create(512)
    local pos = 0

    buffer.writeu8(buf, pos, 0x8C); pos += 1
    buffer.writeu8(buf, pos, 0x01); pos += 1
    buffer.writeu8(buf, pos, 0x69); pos += 1
    buffer.writef64(buf, pos, targetUserId); pos += 8

    buffer.writeu8(buf, pos, 0x1C); pos += 1
    buffer.writeu8(buf, pos, 0x05); pos += 1
    buffer.writeu8(buf, pos, 0x01); pos += 1
    buffer.writeu8(buf, pos, 0x1C); pos += 1

    local function writeString(s)
        local len = #s
        buffer.writeu8(buf, pos, 0x0B); pos += 1
        buffer.writeu8(buf, pos, len); pos += 1
        for i = 1, len do
            buffer.writeu8(buf, pos, string.byte(s, i)); pos += 1
        end
    end

    local function writeInt(n)
        buffer.writeu8(buf, pos, 0x05); pos += 1
        buffer.writeu8(buf, pos, n); pos += 1
    end

    writeString("ItemKey")
    writeString(itemName)
    writeString("Count")
    writeInt(count)
    writeString("Category")
    writeString(category)

    buffer.writeu8(buf, pos, 0x00); pos += 1
    buffer.writeu8(buf, pos, 0x00); pos += 1
    buffer.writeu8(buf, pos, 0x00); pos += 1

    local final = buffer.create(pos)
    buffer.copy(final, 0, buf, 0, pos)
    return final
end

-- ===== BUILD GUI =====
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "SeedSenderGui"
screenGui.ResetOnSpawn = false
screenGui.Parent = player:WaitForChild("PlayerGui")

local COLORS = {
    bg          = Color3.fromRGB(22, 22, 28),
    header      = Color3.fromRGB(16, 16, 20),
    input       = Color3.fromRGB(15, 15, 20),
    text        = Color3.fromRGB(235, 235, 240),
    textDim     = Color3.fromRGB(140, 140, 155),
    placeholder = Color3.fromRGB(110, 110, 125),
    accent      = Color3.fromRGB(60, 130, 200),
    accentHv    = Color3.fromRGB(80, 160, 230),
    green       = Color3.fromRGB(80, 200, 120),
    red         = Color3.fromRGB(200, 70, 70),
    yellow      = Color3.fromRGB(220, 200, 120),
    stroke      = Color3.fromRGB(60, 60, 72),
}

local function corner(p, r)
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r or 6); c.Parent = p
end

local frame = Instance.new("Frame")
frame.Size = UDim2.new(0, 300, 0, 320)
frame.Position = UDim2.new(0, 30, 0, 30)
frame.BackgroundColor3 = COLORS.bg
frame.BorderSizePixel = 0
frame.Active = true
frame.Draggable = true
frame.Parent = screenGui
corner(frame, 10)

local stroke = Instance.new("UIStroke")
stroke.Color = COLORS.stroke
stroke.Transparency = 0.4
stroke.Parent = frame

-- Title bar
local titleBar = Instance.new("Frame")
titleBar.Size = UDim2.new(1, 0, 0, 32)
titleBar.BackgroundColor3 = COLORS.header
titleBar.BorderSizePixel = 0
titleBar.ZIndex = 20
titleBar.Parent = frame
corner(titleBar, 10)

local fix = Instance.new("Frame")
fix.Size = UDim2.new(1, 0, 0, 10)
fix.Position = UDim2.new(0, 0, 1, -10)
fix.BackgroundColor3 = COLORS.header
fix.BorderSizePixel = 0
fix.ZIndex = 20
fix.Parent = titleBar

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -50, 1, 0)
title.Position = UDim2.new(0, 14, 0, 0)
title.BackgroundTransparency = 1
title.Text = "📨 Seed Sender"
title.TextColor3 = COLORS.text
title.Font = Enum.Font.GothamBold
title.TextSize = 13
title.TextXAlignment = Enum.TextXAlignment.Left
title.ZIndex = 21
title.Parent = titleBar

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 22, 0, 22)
closeBtn.Position = UDim2.new(1, -28, 0, 5)
closeBtn.BackgroundColor3 = COLORS.red
closeBtn.Text = "×"
closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 16
closeBtn.BorderSizePixel = 0
closeBtn.AutoButtonColor = false
closeBtn.ZIndex = 21
closeBtn.Parent = titleBar
corner(closeBtn, 6)

-- Username input
local userBox = Instance.new("TextBox")
userBox.Size = UDim2.new(1, -24, 0, 34)
userBox.Position = UDim2.new(0, 12, 0, 44)
userBox.BackgroundColor3 = COLORS.input
userBox.Text = ""
userBox.PlaceholderText = "Username target..."
userBox.TextColor3 = COLORS.text
userBox.PlaceholderColor3 = COLORS.placeholder
userBox.Font = Enum.Font.GothamMedium
userBox.TextSize = 12
userBox.TextXAlignment = Enum.TextXAlignment.Left
userBox.ClearTextOnFocus = false
userBox.BorderSizePixel = 0
userBox.Parent = frame
corner(userBox, 6)
local uPad = Instance.new("UIPadding", userBox)
uPad.PaddingLeft = UDim.new(0, 10)
uPad.PaddingRight = UDim.new(0, 10)

-- Info label
local infoLbl = Instance.new("TextLabel")
infoLbl.Size = UDim2.new(1, -24, 0, 22)
infoLbl.Position = UDim2.new(0, 12, 0, 84)
infoLbl.BackgroundColor3 = COLORS.header
infoLbl.BorderSizePixel = 0
infoLbl.Text = "  Isi username, nama seed & jumlah"
infoLbl.TextColor3 = COLORS.textDim
infoLbl.Font = Enum.Font.Code
infoLbl.TextSize = 10
infoLbl.TextXAlignment = Enum.TextXAlignment.Left
infoLbl.Parent = frame
corner(infoLbl, 4)

local function setInfo(text, color)
    infoLbl.Text = "  " .. text
    infoLbl.TextColor3 = color or COLORS.textDim
end

-- ===== SEED ROWS (nama seed + jumlah seed + tombol kirim) =====
local rows = {}

local yStart = 114
local rowHeight = 36
local rowGap = 6

for i = 1, 4 do
    local y = yStart + (i - 1) * (rowHeight + rowGap)

    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, -24, 0, rowHeight)
    row.Position = UDim2.new(0, 12, 0, y)
    row.BackgroundTransparency = 1
    row.Parent = frame

    -- Nama seed input (kiri)
    local nameBox = Instance.new("TextBox")
    nameBox.Size = UDim2.new(0, 110, 1, 0)
    nameBox.Position = UDim2.new(0, 0, 0, 0)
    nameBox.BackgroundColor3 = COLORS.input
    nameBox.Text = ""
    nameBox.PlaceholderText = "Nama seed..."
    nameBox.TextColor3 = COLORS.text
    nameBox.PlaceholderColor3 = COLORS.placeholder
    nameBox.Font = Enum.Font.GothamMedium
    nameBox.TextSize = 11
    nameBox.TextXAlignment = Enum.TextXAlignment.Left
    nameBox.ClearTextOnFocus = false
    nameBox.BorderSizePixel = 0
    nameBox.Parent = row
    corner(nameBox, 6)
    local nPad = Instance.new("UIPadding", nameBox)
    nPad.PaddingLeft = UDim.new(0, 8)
    nPad.PaddingRight = UDim.new(0, 8)

    -- Jumlah seed input (tengah)
    local amountBox = Instance.new("TextBox")
    amountBox.Size = UDim2.new(0, 55, 1, 0)
    amountBox.Position = UDim2.new(0, 116, 0, 0)
    amountBox.BackgroundColor3 = COLORS.input
    amountBox.Text = ""
    amountBox.PlaceholderText = "0"
    amountBox.TextColor3 = COLORS.text
    amountBox.PlaceholderColor3 = COLORS.placeholder
    amountBox.Font = Enum.Font.GothamBold
    amountBox.TextSize = 12
    amountBox.TextXAlignment = Enum.TextXAlignment.Center
    amountBox.ClearTextOnFocus = false
    amountBox.BorderSizePixel = 0
    amountBox.Parent = row
    corner(amountBox, 6)

    -- Tombol kirim (kanan)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0, 70, 1, 0)
    btn.Position = UDim2.new(1, -70, 0, 0)
    btn.BackgroundColor3 = COLORS.accent
    btn.Text = "Kirim"
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 12
    btn.BorderSizePixel = 0
    btn.AutoButtonColor = false
    btn.Parent = row
    corner(btn, 6)

    rows[i] = { nameBox = nameBox, amountBox = amountBox, btn = btn }

    btn.MouseEnter:Connect(function()
        btn.BackgroundColor3 = COLORS.accentHv
    end)
    btn.MouseLeave:Connect(function()
        btn.BackgroundColor3 = COLORS.accent
    end)

    btn.MouseButton1Click:Connect(function()
        local username = userBox.Text:gsub("%s", "")
        if username == "" then
            setInfo("❌ Isi username dulu", COLORS.red)
            return
        end

        local seedName = nameBox.Text:gsub("^%s+", ""):gsub("%s+$", "")
        if seedName == "" then
            setInfo("❌ Isi nama seed dulu", COLORS.red)
            return
        end

        local countStr = amountBox.Text:gsub("%s", "")
        local count = tonumber(countStr)
        if not count or count <= 0 then
            setInfo("❌ Isi jumlah seed dulu", COLORS.red)
            return
        end
        count = math.floor(count)

        if count > 255 then
            setInfo("⚠ " .. seedName .. " max 255, kirim 255 aja", COLORS.yellow)
            count = 255
        end

        btn.Active = false
        btn.Text = "⏳"
        setInfo("Resolving username...", COLORS.accent)

        task.spawn(function()
            local targetId = getUserIdFromUsername(username)

            if not targetId then
                btn.Text = "Kirim"
                btn.Active = true
                setInfo("❌ Username gak ditemukan", COLORS.red)
                return
            end

            setInfo("Mengirim " .. seedName .. " x" .. count .. "...", COLORS.accent)

            local payload = buildMailPayload(targetId, seedName, count, "Seeds")
            if not payload then
                btn.Text = "Kirim"
                btn.Active = true
                setInfo("❌ Payload gagal", COLORS.red)
                return
            end

            local ok = pcall(function()
                remote:FireServer(payload)
            end)

            if ok then
                btn.Text = "✅"
                btn.BackgroundColor3 = COLORS.green
                setInfo(string.format("✅ Sent %s x%d", seedName, count), COLORS.green)

                task.wait(1.5)

                btn.Text = "Kirim"
                btn.BackgroundColor3 = COLORS.accent
                btn.Active = true
            else
                btn.Text = "Kirim"
                btn.Active = true
                setInfo("❌ Fire gagal", COLORS.red)
            end
        end)
    end)
end

-- Close
closeBtn.MouseButton1Click:Connect(function()
    screenGui:Destroy()
end)
