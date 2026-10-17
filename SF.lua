-- ============================================
-- FRUIT MAIL BUILDER — v10
-- + Fav All / Unfav All
-- + Confirm popup Unfav All ("matikan Auto Sell dulu")
-- ============================================

local CoreGui           = game:GetService("CoreGui")
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService       = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer

--// ==== REMOTE ====
local remote = ReplicatedStorage:WaitForChild("SharedModules")
    :WaitForChild("Packet")
    :WaitForChild("RemoteEvent")

--// ==== CONFIG ====
local CATEGORY       = "HarvestedFruits"
local DEFAULT_TARGET = "Alizaberss"
local REFRESH_RATE   = 3
local BULK_DELAY     = 0.05

--// ==== HELPERS ====
local function resolveUsername(username)
    local ok, userId = pcall(function()
        return Players:GetUserIdFromNameAsync(username)
    end)
    if ok and userId then return userId end

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
    if ok2 and response and response.Body then
        local data = HttpService:JSONDecode(response.Body)
        if data.data and data.data[1] then
            return data.data[1].id
        end
    end
    return nil
end

local function scanBackpack()
    local items = {}
    local backpack = LocalPlayer:FindFirstChild("Backpack")
    if not backpack then return items end
    for _, item in ipairs(backpack:GetChildren()) do
        local uuid = item:GetAttribute("Id")
        if uuid then
            table.insert(items, {
                name     = item.Name,
                uuid     = uuid,
                isFav    = item:GetAttribute("IsFavorite") == true,
                weight   = item:GetAttribute("Weight"),
                mutation = item:GetAttribute("Mutation"),
            })
        end
    end
    return items
end

local function buildMultiEntryPayload(targetUserId, entries)
    local needed = 16
    for _, e in ipairs(entries) do
        needed = needed + 3
            + (2 + #"ItemKey") + (2 + #e.uuid)
            + (2 + #"Count")   + 3
            + (2 + #"Category")+ (2 + #CATEGORY)
            + 1
    end
    needed = needed + 4

    local buf = buffer.create(needed)
    local pos = 0

    buffer.writeu8(buf, pos, 0x8C); pos += 1
    buffer.writeu8(buf, pos, 0x01); pos += 1
    buffer.writeu8(buf, pos, 0x69); pos += 1
    buffer.writef64(buf, pos, targetUserId); pos += 8
    buffer.writeu8(buf, pos, 0x1C); pos += 1

    local function writeString(s)
        buffer.writeu8(buf, pos, 0x0B); pos += 1
        buffer.writeu8(buf, pos, #s);  pos += 1
        for i = 1, #s do
            buffer.writeu8(buf, pos, string.byte(s, i)); pos += 1
        end
    end
    local function writeInt(n)
        buffer.writeu8(buf, pos, 0x05); pos += 1
        buffer.writeu8(buf, pos, n % 256); pos += 1
    end

    for i, entry in ipairs(entries) do
        buffer.writeu8(buf, pos, 0x05); pos += 1
        buffer.writeu8(buf, pos, i % 256); pos += 1
        buffer.writeu8(buf, pos, 0x1C); pos += 1
        writeString("ItemKey");  writeString(entry.uuid)
        writeString("Count");    writeInt(entry.count or 1)
        writeString("Category"); writeString(CATEGORY)
        buffer.writeu8(buf, pos, 0x00); pos += 1
    end
    buffer.writeu8(buf, pos, 0x00); pos += 1
    buffer.writeu8(buf, pos, 0x00); pos += 1
    buffer.writeu8(buf, pos, 0x00); pos += 1

    local final = buffer.create(pos)
    buffer.copy(final, 0, buf, 0, pos)
    return final
end

--// ==== FAV / UNFAV PAYLOAD ====
local function favoriteFruit(uuid)
    local payload = "\179\0004$" .. uuid .. "\001"
    remote:FireServer(buffer.fromstring(payload))
end

local function unfavoriteFruit(uuid)
    local payload = "\179\0006$" .. uuid .. "\000"
    remote:FireServer(buffer.fromstring(payload))
end

--// ==== PALETTE ====
local C_BG      = Color3.fromRGB(18, 18, 22)
local C_CARD    = Color3.fromRGB(28, 28, 34)
local C_ROW     = Color3.fromRGB(36, 36, 44)
local C_ROW_FAV = Color3.fromRGB(34, 48, 40)
local C_ROW_SEL = Color3.fromRGB(50, 70, 60)
local C_ACCENT  = Color3.fromRGB(96, 140, 230)
local C_GREEN   = Color3.fromRGB(80, 190, 120)
local C_RED     = Color3.fromRGB(220, 80, 90)
local C_TEXT    = Color3.fromRGB(235, 235, 240)
local C_SUB     = Color3.fromRGB(140, 145, 160)
local C_BORDER  = Color3.fromRGB(48, 48, 60)

--// ==== GUI ====
local old = CoreGui:FindFirstChild("FruitMailBuilder")
if old then old:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "FruitMailBuilder"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.IgnoreGuiInset = true
gui.DisplayOrder = 999
gui.Parent = CoreGui

local main = Instance.new("Frame")
main.Size = UDim2.new(0, 300, 0, 390)
main.Position = UDim2.new(0.5, -150, 0.5, -195)
main.BackgroundColor3 = C_BG
main.BorderSizePixel = 0
main.Active = true
main.Draggable = true
main.Parent = gui

local mc = Instance.new("UICorner"); mc.CornerRadius = UDim.new(0, 14); mc.Parent = main
local ms = Instance.new("UIStroke"); ms.Color = C_BORDER; ms.Thickness = 1; ms.Parent = main

-- === Header ===
local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 30)
header.BackgroundColor3 = C_CARD
header.BorderSizePixel = 0
header.Parent = main
local hc = Instance.new("UICorner"); hc.CornerRadius = UDim.new(0, 14); hc.Parent = header
local hfix = Instance.new("Frame")
hfix.Size = UDim2.new(1, 0, 0, 12); hfix.Position = UDim2.new(0, 0, 1, -12)
hfix.BackgroundColor3 = C_CARD; hfix.BorderSizePixel = 0; hfix.Parent = header

local titleLbl = Instance.new("TextLabel")
titleLbl.Size = UDim2.new(1, -40, 1, 0)
titleLbl.Position = UDim2.new(0, 12, 0, 0)
titleLbl.BackgroundTransparency = 1
titleLbl.Text = "🍎 Fruit Mail v10"
titleLbl.TextColor3 = C_TEXT
titleLbl.TextXAlignment = Enum.TextXAlignment.Left
titleLbl.Font = Enum.Font.GothamBold
titleLbl.TextSize = 12
titleLbl.Parent = header

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 28, 0, 28)
closeBtn.Position = UDim2.new(1, -32, 0, 1)
closeBtn.BackgroundTransparency = 1
closeBtn.Text = "✕"
closeBtn.TextColor3 = C_SUB
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 14
closeBtn.Parent = header
closeBtn.MouseButton1Click:Connect(function() gui:Destroy() end)

-- === Target Row ===
local targetCard = Instance.new("Frame")
targetCard.Size = UDim2.new(1, -20, 0, 28)
targetCard.Position = UDim2.new(0, 10, 0, 38)
targetCard.BackgroundColor3 = C_CARD
targetCard.BorderSizePixel = 0
targetCard.Parent = main
local tc = Instance.new("UICorner"); tc.CornerRadius = UDim.new(0, 8); tc.Parent = targetCard
local ts = Instance.new("UIStroke"); ts.Color = C_BORDER; ts.Thickness = 1; ts.Parent = targetCard

local targetInput = Instance.new("TextBox")
targetInput.Size = UDim2.new(1, -70, 1, -6)
targetInput.Position = UDim2.new(0, 10, 0, 3)
targetInput.BackgroundTransparency = 1
targetInput.Text = DEFAULT_TARGET
targetInput.TextColor3 = C_TEXT
targetInput.PlaceholderText = "username..."
targetInput.PlaceholderColor3 = C_SUB
targetInput.Font = Enum.Font.Gotham
targetInput.TextSize = 11
targetInput.TextXAlignment = Enum.TextXAlignment.Left
targetInput.ClearTextOnFocus = false
targetInput.Parent = targetCard

local checkBtn = Instance.new("TextButton")
checkBtn.Size = UDim2.new(0, 50, 1, -6)
checkBtn.Position = UDim2.new(1, -56, 0, 3)
checkBtn.BackgroundColor3 = C_ACCENT
checkBtn.Text = "Set"
checkBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
checkBtn.Font = Enum.Font.GothamBold
checkBtn.TextSize = 11
checkBtn.Parent = targetCard
local cbc = Instance.new("UICorner"); cbc.CornerRadius = UDim.new(0, 6); cbc.Parent = checkBtn

-- === Status Line ===
local statusLbl = Instance.new("TextLabel")
statusLbl.Size = UDim2.new(1, -20, 0, 16)
statusLbl.Position = UDim2.new(0, 10, 0, 70)
statusLbl.BackgroundTransparency = 1
statusLbl.Text = "  —"
statusLbl.TextColor3 = C_SUB
statusLbl.Font = Enum.Font.Gotham
statusLbl.TextSize = 9
statusLbl.TextXAlignment = Enum.TextXAlignment.Left
statusLbl.TextTruncate = Enum.TextTruncate.AtEnd
statusLbl.Parent = main

-- === Search ===
local searchCard = Instance.new("Frame")
searchCard.Size = UDim2.new(1, -20, 0, 26)
searchCard.Position = UDim2.new(0, 10, 0, 88)
searchCard.BackgroundColor3 = C_CARD
searchCard.BorderSizePixel = 0
searchCard.Parent = main
local sc = Instance.new("UICorner"); sc.CornerRadius = UDim.new(0, 8); sc.Parent = searchCard
local ss = Instance.new("UIStroke"); ss.Color = C_BORDER; ss.Thickness = 1; ss.Parent = searchCard

local searchIcon = Instance.new("TextLabel")
searchIcon.Size = UDim2.new(0, 20, 1, 0)
searchIcon.Position = UDim2.new(0, 6, 0, 0)
searchIcon.BackgroundTransparency = 1
searchIcon.Text = "🔍"
searchIcon.TextSize = 10
searchIcon.TextColor3 = C_SUB
searchIcon.Parent = searchCard

local searchInput = Instance.new("TextBox")
searchInput.Size = UDim2.new(1, -32, 1, 0)
searchInput.Position = UDim2.new(0, 26, 0, 0)
searchInput.BackgroundTransparency = 1
searchInput.Text = ""
searchInput.PlaceholderText = "nama / berat / mutasi..."
searchInput.PlaceholderColor3 = C_SUB
searchInput.TextColor3 = C_TEXT
searchInput.Font = Enum.Font.Gotham
searchInput.TextSize = 10
searchInput.TextXAlignment = Enum.TextXAlignment.Left
searchInput.ClearTextOnFocus = false
searchInput.Parent = searchCard

-- === Counter ===
local counterLbl = Instance.new("TextLabel")
counterLbl.Size = UDim2.new(1, -20, 0, 14)
counterLbl.Position = UDim2.new(0, 10, 0, 118)
counterLbl.BackgroundTransparency = 1
counterLbl.Text = "0 fruit  •  0 mail"
counterLbl.TextColor3 = C_SUB
counterLbl.Font = Enum.Font.Gotham
counterLbl.TextSize = 9
counterLbl.TextXAlignment = Enum.TextXAlignment.Left
counterLbl.Parent = main

-- === List ===
local ROW_H   = 26
local VISIBLE = 5
local LIST_H  = VISIBLE * ROW_H + 8
local LIST_Y  = 134
local listFrame = Instance.new("ScrollingFrame")
listFrame.Size = UDim2.new(1, -20, 0, LIST_H)
listFrame.Position = UDim2.new(0, 10, 0, LIST_Y)
listFrame.BackgroundColor3 = Color3.fromRGB(14, 14, 18)
listFrame.BorderSizePixel = 0
listFrame.ScrollBarThickness = 3
listFrame.ScrollBarImageColor3 = C_BORDER
listFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
listFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
listFrame.Parent = main
local lfc = Instance.new("UICorner"); lfc.CornerRadius = UDim.new(0, 8); lfc.Parent = listFrame
local lfs = Instance.new("UIStroke"); lfs.Color = C_BORDER; lfs.Thickness = 1; lfs.Parent = listFrame

local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 2)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Parent = listFrame

local listPad = Instance.new("UIPadding")
listPad.PaddingTop = UDim.new(0, 4)
listPad.PaddingBottom = UDim.new(0, 4)
listPad.PaddingLeft = UDim.new(0, 4)
listPad.PaddingRight = UDim.new(0, 4)
listPad.Parent = listFrame

-- === Bottom Bar (2 baris) ===
local BOTTOM_Y = LIST_Y + LIST_H + 8
local btnRow = Instance.new("Frame")
btnRow.Size = UDim2.new(1, -20, 0, 58)
btnRow.Position = UDim2.new(0, 10, 0, BOTTOM_Y)
btnRow.BackgroundTransparency = 1
btnRow.Parent = main

-- --- baris atas: Clear + FavAll + UnfavAll ---
local topBtnRow = Instance.new("Frame")
topBtnRow.Size = UDim2.new(1, 0, 0, 26)
topBtnRow.BackgroundTransparency = 1
topBtnRow.Parent = btnRow

local clearBtn = Instance.new("TextButton")
clearBtn.Size = UDim2.new(0, 52, 1, 0)
clearBtn.BackgroundColor3 = C_ROW
clearBtn.Text = "🗑"
clearBtn.TextColor3 = C_TEXT
clearBtn.Font = Enum.Font.GothamBold
clearBtn.TextSize = 12
clearBtn.Parent = topBtnRow
local clc = Instance.new("UICorner"); clc.CornerRadius = UDim.new(0, 8); clc.Parent = clearBtn

local favAllBtn = Instance.new("TextButton")
favAllBtn.Size = UDim2.new(0, 96, 1, 0)
favAllBtn.Position = UDim2.new(0, 58, 0, 0)
favAllBtn.BackgroundColor3 = Color3.fromRGB(60, 130, 90)
favAllBtn.Text = "⭐ Fav All"
favAllBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
favAllBtn.Font = Enum.Font.GothamBold
favAllBtn.TextSize = 10
favAllBtn.Parent = topBtnRow
local fabc = Instance.new("UICorner"); fabc.CornerRadius = UDim.new(0, 8); fabc.Parent = favAllBtn

local unfavAllBtn = Instance.new("TextButton")
unfavAllBtn.Size = UDim2.new(1, -160, 1, 0)
unfavAllBtn.Position = UDim2.new(0, 160, 0, 0)
unfavAllBtn.BackgroundColor3 = Color3.fromRGB(120, 80, 80)
unfavAllBtn.Text = "☆ Unfav All"
unfavAllBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
unfavAllBtn.Font = Enum.Font.GothamBold
unfavAllBtn.TextSize = 10
unfavAllBtn.Parent = topBtnRow
local uabc = Instance.new("UICorner"); uabc.CornerRadius = UDim.new(0, 8); uabc.Parent = unfavAllBtn

-- --- baris bawah: Send ---
local sendBtn = Instance.new("TextButton")
sendBtn.Size = UDim2.new(1, 0, 0, 26)
sendBtn.Position = UDim2.new(0, 0, 0, 30)
sendBtn.BackgroundColor3 = C_GREEN
sendBtn.Text = "🔥 SEND"
sendBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
sendBtn.Font = Enum.Font.GothamBold
sendBtn.TextSize = 11
sendBtn.Parent = btnRow
local sbc = Instance.new("UICorner"); sbc.CornerRadius = UDim.new(0, 8); sbc.Parent = sendBtn

-- ============ STATE ============
local currentItems = {}
local entries      = {}
local targetId     = nil
local targetName   = nil
local rowRefs      = {}
local query        = ""

local favFingerprint = ""
local favWatchers    = {}
local backpackConn   = nil
local currentBackpack = nil

-- ============ HELPERS ============
local function entryCount()
    local n = 0
    for _ in pairs(entries) do n += 1 end
    return n
end

local function setStatus(text, color)
    statusLbl.Text = "  " .. text
    statusLbl.TextColor3 = color or C_SUB
end

local function updateCounter(favTotal)
    counterLbl.Text = string.format("%d fruit  •  %d fav  •  %d mail",
        #currentItems, favTotal or 0, entryCount())
end

local function matchesQuery(item, q)
    if q == "" then return true end
    q = q:lower()
    if item.name:lower():find(q, 1, true) then return true end
    if item.mutation and tostring(item.mutation):lower():find(q, 1, true) then return true end
    if item.weight then
        local w = tostring(item.weight)
        if w:find(q, 1, true) then return true end
        local num = tonumber(q)
        if num and item.weight >= num then return true end
        local cmp, val = q:match("^([><])(%d+%.?%d*)$")
        if cmp then
            local v = tonumber(val)
            if v then
                if cmp == ">" and item.weight > v then return true end
                if cmp == "<" and item.weight < v then return true end
            end
        end
    end
    return false
end

local function styleRow(row, actionBtn, isEntry)
    if isEntry then
        row.BackgroundColor3 = C_ROW_SEL
        actionBtn.BackgroundColor3 = C_RED
        actionBtn.Text = "−"
    else
        row.BackgroundColor3 = row:GetAttribute("IsFav") and C_ROW_FAV or C_ROW
        actionBtn.BackgroundColor3 = C_GREEN
        actionBtn.Text = "+"
    end
end

local function computeFavFingerprint(items)
    local t = {}
    for _, e in ipairs(items) do
        table.insert(t, e.uuid .. ":" .. (e.isFav and "1" or "0"))
    end
    table.sort(t)
    return table.concat(t, "|")
end

local onFavChanged -- forward decl

local function attachFavWatchers(items)
    for uuid, conn in pairs(favWatchers) do
        if conn then conn:Disconnect() end
    end
    favWatchers = {}

    for _, e in ipairs(items) do
        local inst = nil
        local backpack = LocalPlayer:FindFirstChild("Backpack")
        if backpack then
            for _, c in ipairs(backpack:GetChildren()) do
                if c:GetAttribute("Id") == e.uuid then
                    inst = c
                    break
                end
            end
        end
        if inst then
            local conn = inst:GetAttributeChangedSignal("IsFavorite"):Connect(function()
                onFavChanged(inst)
            end)
            favWatchers[e.uuid] = conn
        end
    end
end

function onFavChanged(inst)
    local uuid = inst:GetAttribute("Id")
    if not uuid then return end
    local ref = rowRefs[uuid]
    if not ref then return end

    local newFav = inst:GetAttribute("IsFavorite") == true

    if ref.row and ref.row.Parent then
        ref.row:SetAttribute("IsFav", newFav)
        if not entries[uuid] then
            ref.row.BackgroundColor3 = newFav and C_ROW_FAV or C_ROW
        end
    end

    local favTotal = 0
    for _, it in ipairs(currentItems) do
        if it.uuid == uuid then it.isFav = newFav end
        if it.isFav then favTotal += 1 end
    end
    updateCounter(favTotal)

    setStatus((newFav and "★ fav'd " or "☆ unfav'd ") .. inst.Name, C_SUB)
end

-- ============ RENDER ============
local function rebuildList()
    local savedScroll = listFrame.CanvasPosition
    for _, c in ipairs(listFrame:GetChildren()) do
        if c:IsA("TextButton") or c:IsA("TextLabel") then c:Destroy() end
    end
    rowRefs = {}

    currentItems = scanBackpack()

    local live = {}
    for _, e in ipairs(currentItems) do live[e.uuid] = true end
    for uuid, _ in pairs(entries) do
        if not live[uuid] then entries[uuid] = nil end
    end

    table.sort(currentItems, function(a, b)
        if a.isFav ~= b.isFav then return a.isFav end
        return (a.weight or 0) > (b.weight or 0)
    end)

    local favTotal = 0
    for _, e in ipairs(currentItems) do
        if e.isFav then favTotal += 1 end
    end

    local filtered = {}
    for _, e in ipairs(currentItems) do
        if matchesQuery(e, query) then
            table.insert(filtered, e)
        end
    end

    for i, e in ipairs(filtered) do
        local row = Instance.new("TextButton")
        row.Size = UDim2.new(1, 0, 0, ROW_H)
        row.BackgroundColor3 = e.isFav and C_ROW_FAV or C_ROW
        row.Text = ""
        row.LayoutOrder = i
        row.AutoButtonColor = true
        row:SetAttribute("IsFav", e.isFav)
        row.Parent = listFrame
        local rc = Instance.new("UICorner"); rc.CornerRadius = UDim.new(0, 6); rc.Parent = row

        local star = Instance.new("TextLabel")
        star.Size = UDim2.new(0, 14, 1, 0)
        star.Position = UDim2.new(0, 4, 0, 0)
        star.BackgroundTransparency = 1
        star.Text = e.isFav and "⭐" or ""
        star.TextSize = 9
        star.Parent = row

        local nameLbl = Instance.new("TextLabel")
        nameLbl.Size = UDim2.new(1, -52, 1, 0)
        nameLbl.Position = UDim2.new(0, 20, 0, 0)
        nameLbl.BackgroundTransparency = 1
        nameLbl.Text = e.name
        nameLbl.TextColor3 = C_TEXT
        nameLbl.Font = Enum.Font.GothamMedium
        nameLbl.TextSize = 10
        nameLbl.TextXAlignment = Enum.TextXAlignment.Left
        nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
        nameLbl.Parent = row

        local actionBtn = Instance.new("TextButton")
        actionBtn.Size = UDim2.new(0, 22, 0, 22)
        actionBtn.Position = UDim2.new(1, -26, 0, 2)
        actionBtn.Text = "+"
        actionBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
        actionBtn.Font = Enum.Font.GothamBold
        actionBtn.TextSize = 12
        actionBtn.BackgroundColor3 = C_GREEN
        actionBtn.Parent = row
        local abc = Instance.new("UICorner"); abc.CornerRadius = UDim.new(0, 6); abc.Parent = actionBtn

        if entries[e.uuid] then
            styleRow(row, actionBtn, true)
        end
        rowRefs[e.uuid] = { row = row, actionBtn = actionBtn, star = star }

        actionBtn.MouseButton1Click:Connect(function()
            if entries[e.uuid] then
                entries[e.uuid] = nil
                styleRow(row, actionBtn, false)
            else
                entries[e.uuid] = {
                    count    = 1,
                    name     = e.name,
                    weight   = e.weight,
                    mutation = e.mutation,
                }
                styleRow(row, actionBtn, true)
            end
            updateCounter(favTotal)
        end)

        row.MouseButton1Click:Connect(function()
            if setclipboard then pcall(setclipboard, e.uuid) end
            setStatus("📋 " .. e.uuid:sub(1, 10) .. "…", C_SUB)
        end)
    end

    if #filtered == 0 then
        local empty = Instance.new("TextLabel")
        empty.Size = UDim2.new(1, 0, 0, 30)
        empty.BackgroundTransparency = 1
        empty.Text = query ~= "" and "  (tidak ada hasil)" or "  (tas kosong)"
        empty.TextColor3 = C_SUB
        empty.Font = Enum.Font.Gotham
        empty.TextSize = 10
        empty.TextXAlignment = Enum.TextXAlignment.Left
        empty.Parent = listFrame
    end

    updateCounter(favTotal)
    attachFavWatchers(currentItems)
    favFingerprint = computeFavFingerprint(currentItems)

    task.defer(function()
        if listFrame.Parent then
            listFrame.CanvasPosition = savedScroll
        end
    end)
end

-- live search
searchInput:GetPropertyChangedSignal("Text"):Connect(function()
    query = searchInput.Text
    rebuildList()
end)

-- ============ TARGET ============
checkBtn.MouseButton1Click:Connect(function()
    local username = targetInput.Text
    setStatus("⏳ resolving " .. username .. "…", Color3.fromRGB(255, 200, 100))
    task.spawn(function()
        local id = resolveUsername(username)
        if id then
            targetId   = id
            targetName = username
            setStatus(string.format("✅ %s  •  ID %d", username, id),
                Color3.fromRGB(150, 255, 170))
        else
            targetId   = nil
            targetName = nil
            setStatus("❌ gagal resolve: " .. username, C_RED)
        end
    end)
end)

-- ============ CLEAR / SEND ============
clearBtn.MouseButton1Click:Connect(function()
    entries = {}
    for uuid, ref in pairs(rowRefs) do
        styleRow(ref.row, ref.actionBtn, false)
    end
    updateCounter()
    setStatus("🗑 mail cleared", C_SUB)
end)

sendBtn.MouseButton1Click:Connect(function()
    local list = {}
    for uuid, data in pairs(entries) do
        table.insert(list, {
            uuid     = uuid,
            count    = data.count,
            name     = data.name,
            weight   = data.weight,
            mutation = data.mutation,
        })
    end
    if #list == 0 then
        setStatus("❌ belum ada item di mail", C_RED)
        return
    end
    if not targetId then
        setStatus("❌ target belum di-set", C_RED)
        return
    end
    setStatus("🔥 sending " .. #list .. " item…", Color3.fromRGB(255, 200, 100))
    local ok, err = pcall(function()
        remote:FireServer(buildMultiEntryPayload(targetId, list))
    end)
    if ok then
        setStatus("✅ sent " .. #list .. " item", Color3.fromRGB(150, 255, 170))
    else
        setStatus("❌ error: " .. tostring(err), C_RED)
    end
end)

-- ============ FAV ALL / UNFAV ALL ============
local function bulkFav(isFav)
    local items = scanBackpack()
    if #items == 0 then
        setStatus("❌ backpack kosong", C_RED)
        return
    end

    local targets = {}
    for _, e in ipairs(items) do
        if e.isFav ~= isFav then
            table.insert(targets, e)
        end
    end

    if #targets == 0 then
        setStatus(isFav and "✅ semua udah fav" or "✅ semua udah unfav", C_SUB)
        return
    end

    setStatus(string.format("⏳ %s %d item…",
        isFav and "favoriting" or "unfavoriting", #targets),
        Color3.fromRGB(255, 200, 100))

    task.spawn(function()
        local okCount, failCount = 0, 0
        for _, e in ipairs(targets) do
            local ok, err = pcall(function()
                if isFav then favoriteFruit(e.uuid) else unfavoriteFruit(e.uuid) end
            end)
            if ok then
                okCount += 1
            else
                failCount += 1
                warn("[bulkFav] gagal " .. e.name .. ": " .. tostring(err))
            end
            task.wait(BULK_DELAY)
        end

        setStatus(string.format("%s %d ok • %d gagal",
            isFav and "⭐ fav'd" or "☆ unfav'd", okCount, failCount),
            failCount == 0 and Color3.fromRGB(150, 255, 170) or C_RED)

        task.wait(0.3)
        rebuildList()
    end)
end

favAllBtn.MouseButton1Click:Connect(function()
    bulkFav(true)
end)

-- ============ CONFIRM POPUP untuk UNFAV ALL ============
local confirmGui = Instance.new("ScreenGui")
confirmGui.Name = "FruitMailConfirm"
confirmGui.ResetOnSpawn = false
confirmGui.IgnoreGuiInset = true
confirmGui.DisplayOrder = 1000
confirmGui.Enabled = false
confirmGui.Parent = CoreGui

local overlay = Instance.new("Frame")
overlay.Size = UDim2.new(1, 0, 1, 0)
overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
overlay.BackgroundTransparency = 0.45
overlay.BorderSizePixel = 0
overlay.Parent = confirmGui

local dialog = Instance.new("Frame")
dialog.Size = UDim2.new(0, 260, 0, 160)
dialog.Position = UDim2.new(0.5, -130, 0.5, -80)
dialog.BackgroundColor3 = C_BG
dialog.BorderSizePixel = 0
dialog.Parent = overlay
local dc = Instance.new("UICorner"); dc.CornerRadius = UDim.new(0, 12); dc.Parent = dialog
local ds = Instance.new("UIStroke"); ds.Color = C_RED; ds.Thickness = 1; ds.Parent = dialog

local dTitle = Instance.new("TextLabel")
dTitle.Size = UDim2.new(1, -20, 0, 26)
dTitle.Position = UDim2.new(0, 10, 0, 8)
dTitle.BackgroundTransparency = 1
dTitle.Text = "⚠ PERINGATAN"
dTitle.TextColor3 = C_RED
dTitle.Font = Enum.Font.GothamBold
dTitle.TextSize = 13
dTitle.TextXAlignment = Enum.TextXAlignment.Center
dTitle.Parent = dialog

local dMsg = Instance.new("TextLabel")
dMsg.Size = UDim2.new(1, -24, 0, 70)
dMsg.Position = UDim2.new(0, 12, 0, 38)
dMsg.BackgroundTransparency = 1
dMsg.Text = "Unfav All akan mematikan status favorite SEMUA buah.\n\n" ..
            "🔴 Matikan dulu script AUTO SELL sebelum lanjut,\n" ..
            "supaya buah tidak ikut terjual."
dMsg.TextColor3 = C_TEXT
dMsg.Font = Enum.Font.Gotham
dMsg.TextSize = 10
dMsg.TextWrapped = true
dMsg.TextYAlignment = Enum.TextYAlignment.Top
dMsg.Parent = dialog

local confirmBtn = Instance.new("TextButton")
confirmBtn.Size = UDim2.new(0, 110, 0, 28)
confirmBtn.Position = UDim2.new(0, 14, 1, -38)
confirmBtn.BackgroundColor3 = C_RED
confirmBtn.Text = "✅ CONFIRM"
confirmBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
confirmBtn.Font = Enum.Font.GothamBold
confirmBtn.TextSize = 11
confirmBtn.Parent = dialog
local cfc = Instance.new("UICorner"); cfc.CornerRadius = UDim.new(0, 8); cfc.Parent = confirmBtn

local returnBtn = Instance.new("TextButton")
returnBtn.Size = UDim2.new(0, 110, 0, 28)
returnBtn.Position = UDim2.new(1, -124, 1, -38)
returnBtn.BackgroundColor3 = C_ROW
returnBtn.Text = "↩ RETURN"
returnBtn.TextColor3 = C_TEXT
returnBtn.Font = Enum.Font.GothamBold
returnBtn.TextSize = 11
returnBtn.Parent = dialog
local rbc = Instance.new("UICorner"); rbc.CornerRadius = UDim.new(0, 8); rbc.Parent = returnBtn

returnBtn.MouseButton1Click:Connect(function()
    confirmGui.Enabled = false
    setStatus("↩ unfav all dibatalkan", C_SUB)
end)

confirmBtn.MouseButton1Click:Connect(function()
    confirmGui.Enabled = false
    bulkFav(false)
end)

unfavAllBtn.MouseButton1Click:Connect(function()
    confirmGui.Enabled = true
end)

-- ============ INIT ============
rebuildList()

task.spawn(function()
    local id = resolveUsername(DEFAULT_TARGET)
    if id then
        targetId   = id
        targetName = DEFAULT_TARGET
        setStatus(string.format("✅ %s  •  ID %d", DEFAULT_TARGET, id),
            Color3.fromRGB(150, 255, 170))
    end
end)

-- ============ AUTO REFRESH ============
local function hookBackpack()
    local backpack = LocalPlayer:FindFirstChild("Backpack")
    if not backpack then return end
    if currentBackpack == backpack and backpackConn then return end

    if backpackConn then backpackConn:Disconnect() end
    currentBackpack = backpack

    backpackConn = backpack.ChildAdded:Connect(function(child)
        if child:GetAttribute("Id") then
            task.wait(0.1)
            rebuildList()
        end
    end)
end

hookBackpack()
LocalPlayer.ChildAdded:Connect(function(child)
    if child.Name == "Backpack" then
        task.wait(0.2)
        hookBackpack()
        rebuildList()
    end
end)

task.spawn(function()
    while gui.Parent do
        task.wait(REFRESH_RATE)
        if not gui.Parent then break end

        hookBackpack()

        local backpack = LocalPlayer:FindFirstChild("Backpack")
        if backpack then
            local snapshot = scanBackpack()
            local newFp = computeFavFingerprint(snapshot)

            if newFp ~= favFingerprint then
                rebuildList()
            else
                local live = {}
                for _, item in ipairs(backpack:GetChildren()) do
                    local uuid = item:GetAttribute("Id")
                    if uuid then live[uuid] = true end
                end
                local changed = false
                for uuid, ref in pairs(rowRefs) do
                    if not live[uuid] then
                        if ref.row and ref.row.Parent then ref.row:Destroy() end
                        rowRefs[uuid] = nil
                        if entries[uuid] then
                            entries[uuid] = nil
                            changed = true
                        end
                    end
                end
                if changed then
                    updateCounter()
                end
            end
        end
    end
end)

print("✅ Fruit Mail Builder v10 (Fav All / Unfav All + Confirm) loaded")
