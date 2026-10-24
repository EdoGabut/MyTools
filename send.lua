-- ============================================================
-- Mail Sender (Item + Fruit) — Combined
-- Items: TextBox qty per row | Fruits: tombol +/-
-- ============================================================
local CoreGui           = game:GetService("CoreGui")
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService       = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer

--// ==== REMOTE ====
local remote = ReplicatedStorage:WaitForChild("SharedModules")
    :WaitForChild("Packet")
    :WaitForChild("RemoteEvent")

--// ============================================================
--// ==== CONFIG ====
--// ============================================================
local CONFIG = {
    FRAME_WIDTH   = 320,
    FRAME_HEIGHT  = 440,
    ROW_HEIGHT    = 30,
    VISIBLE_ROWS  = 6,
}

local CATEGORY_FRUIT   = "HarvestedFruits"
local REFRESH_RATE     = 3
local BULK_DELAY       = 0.05
local DEFAULT_TARGET   = "Alizaberss"

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
local C_WARN    = Color3.fromRGB(230, 180, 60)

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
                usernames = { username }, excludeBannedUsers = false
            })
        })
    end)
    if ok2 and response and response.Body then
        local data = HttpService:JSONDecode(response.Body)
        if data.data and data.data[1] then return data.data[1].id end
    end
    return nil
end

--// ==== FRUIT SCAN ====
local function scanFruits()
    local items = {}
    local backpack = LocalPlayer:FindFirstChild("Backpack")
    if not backpack then return items end
    for _, item in ipairs(backpack:GetChildren()) do
        local uuid = item:GetAttribute("Id")
        if uuid then
            if item:GetAttribute("PottedPlant") == true then continue end
            if item:GetAttribute("PlantName") ~= nil then continue end
            local weight = item:GetAttribute("Weight")
            local fruitName = item:GetAttribute("FruitName") or item:GetAttribute("Fruit")
            if weight == nil and fruitName == nil then continue end
            table.insert(items, {
                name     = item.Name,
                uuid     = uuid,
                isFav    = item:GetAttribute("IsFavorite") == true,
                weight   = weight,
                mutation = item:GetAttribute("Mutation"),
            })
        end
    end
    return items
end

--// ==== ITEM SCAN ====
local function getCategoryFromAttributes(tool)
    local attrs = tool:GetAttributes()
    if attrs.PottedPlant == true then return nil end
    local checks = {
        { key = "SeedTool",    cat = "Seeds" },
        { key = "WateringCan", cat = "WateringCans" },
        { key = "Sprinkler",   cat = "Sprinklers" },
        { key = "Trowel",      cat = "Trowels" },
        { key = "Crate",       cat = "Crates" },
    }
    for _, c in ipairs(checks) do
        if attrs[c.key] ~= nil then return c.cat end
    end
    local seedVal = attrs.Seed
    if type(seedVal) == "string" and seedVal ~= "" then return "Seeds" end
    local mainCat = attrs.MainCategory
    if type(mainCat) == "string" then
        local map = {
            Seed = "Seeds", WateringCan = "WateringCans",
            Sprinkler = "Sprinklers", Trowel = "Trowels", Crate = "Crates",
        }
        if map[mainCat] then return map[mainCat] end
    end
    return nil
end

local function isFruitName(name)
    if not name then return false end
    if name:match("%[%s*[%d%.]+%s*kg%s*%]") then return true end
    local c = 0
    for _ in name:gmatch("%b[]") do
        c += 1
        if c >= 2 then return true end
    end
    return false
end

local function isPottedName(name)
    if not name then return false end
    return name:match("%[%s*Potted%s*%]") ~= nil
end

local function stripSeedSuffix(name)
    if not name then return name end
    name = name:gsub("%s+Seeds$", "")
    name = name:gsub("%s+Seed$", "")
    return name
end

local function scanItems()
    local result = {}
    local seen = {}
    local grouped = {}

    local function addTool(tool)
        if seen[tool] then return end
        seen[tool] = true
        local displayName = tool.Name
        local attrs = tool:GetAttributes()
        if isFruitName(displayName) then return end
        if isPottedName(displayName) or attrs.PottedPlant == true then return end
        local cat = getCategoryFromAttributes(tool)
        if not cat then return end
        local mult = tonumber(attrs.Count) or 1
        if mult < 1 then mult = 1 end
        local key = displayName .. "|" .. cat
        if grouped[key] then
            grouped[key].count += mult
        else
            grouped[key] = {
                name = stripSeedSuffix(displayName),
                display = displayName,
                category = cat,
                count = mult,
            }
        end
    end

    local bp = LocalPlayer:FindFirstChild("Backpack")
    if bp then
        for _, t in ipairs(bp:GetChildren()) do
            if t:IsA("Tool") then addTool(t) end
        end
    end
    local char = LocalPlayer.Character
    if char then
        for _, t in ipairs(char:GetChildren()) do
            if t:IsA("Tool") then addTool(t) end
        end
    end

    for _, v in pairs(grouped) do table.insert(result, v) end
    table.sort(result, function(a, b)
        if a.category ~= b.category then return a.category < b.category end
        return a.display:lower() < b.display:lower()
    end)
    return result
end

--// ==== PAYLOAD BUILDER ====
local function buildMultiCategoryPayload(targetUserId, entries)
    local needed = 3 + 8 + 1 + 3
    for _, e in ipairs(entries) do
        needed = needed + 3
            + (2 + #"ItemKey")  + (2 + #e.uuid)
            + (2 + #"Count")    + 2
            + (2 + #"Category") + (2 + #e.category)
            + 1
    end
    local buf = buffer.create(needed)
    local pos = 0
    local function w(n) buffer.writeu8(buf, pos, n); pos += 1 end
    local function ws(s)
        w(0x0B); w(#s)
        for i = 1, #s do w(string.byte(s, i)) end
    end

    w(0x8C); w(0x01); w(0x69)
    buffer.writef64(buf, pos, targetUserId); pos += 8
    w(0x1C)

    for i, e in ipairs(entries) do
        w(0x05); w(i % 256); w(0x1C)
        ws("ItemKey");  ws(e.uuid)
        ws("Count");    w(0x05); w(e.count % 256)
        ws("Category"); ws(e.category)
        w(0x00)
    end

    w(0x00); w(0x00); w(0x00)
    local final = buffer.create(pos)
    buffer.copy(final, 0, buf, 0, pos)
    return final
end

local function expandEntries(entries)
    local out = {}
    for _, e in ipairs(entries) do
        local remaining = e.count or 1
        if remaining < 1 then remaining = 1 end
        while remaining > 0 do
            table.insert(out, {
                uuid     = e.uuid,
                category = e.category,
                count    = math.min(remaining, 255),
            })
            remaining -= 255
        end
    end
    return out
end

local function favoriteFruit(uuid)
    remote:FireServer(buffer.fromstring("\179\0004$" .. uuid .. "\001"))
end
local function unfavoriteFruit(uuid)
    remote:FireServer(buffer.fromstring("\179\0006$" .. uuid .. "\000"))
end

--// ==== GUI ====
local old = CoreGui:FindFirstChild("MailSenderCombined")
if old then old:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "MailSenderCombined"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.IgnoreGuiInset = true
gui.DisplayOrder = 999
gui.Parent = CoreGui

local HEADER_H   = 30
local TARGET_H   = 28 + 8
local STATUS_H   = 18
local TAB_H      = 26 + 8
local SEARCH_H   = 26 + 4
local COUNTER_H  = 14 + 2
local LIST_H     = CONFIG.VISIBLE_ROWS * CONFIG.ROW_HEIGHT + 8

local main = Instance.new("Frame")
main.Size = UDim2.new(0, CONFIG.FRAME_WIDTH, 0, CONFIG.FRAME_HEIGHT)
main.Position = UDim2.new(0.5, -CONFIG.FRAME_WIDTH/2, 0.5, -CONFIG.FRAME_HEIGHT/2)
main.BackgroundColor3 = C_BG
main.BorderSizePixel = 0
main.Active = true
main.Draggable = true
main.Parent = gui
Instance.new("UICorner", main).CornerRadius = UDim.new(0, 14)
local ms = Instance.new("UIStroke"); ms.Color = C_BORDER; ms.Thickness = 1; ms.Parent = main

-- Header
local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, HEADER_H)
header.BackgroundColor3 = C_CARD
header.BorderSizePixel = 0
header.Parent = main
Instance.new("UICorner", header).CornerRadius = UDim.new(0, 14)
local hfix = Instance.new("Frame")
hfix.Size = UDim2.new(1, 0, 0, 12); hfix.Position = UDim2.new(0, 0, 1, -12)
hfix.BackgroundColor3 = C_CARD; hfix.BorderSizePixel = 0; hfix.Parent = header

local titleLbl = Instance.new("TextLabel")
titleLbl.Size = UDim2.new(1, -40, 1, 0)
titleLbl.Position = UDim2.new(0, 12, 0, 0)
titleLbl.BackgroundTransparency = 1
titleLbl.Text = "📨 Mail Sender"
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

-- Target card
local targetCard = Instance.new("Frame")
targetCard.Size = UDim2.new(1, -20, 0, 28)
targetCard.Position = UDim2.new(0, 10, 0, HEADER_H + 8)
targetCard.BackgroundColor3 = C_CARD
targetCard.BorderSizePixel = 0
targetCard.Parent = main
Instance.new("UICorner", targetCard).CornerRadius = UDim.new(0, 8)
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
Instance.new("UICorner", checkBtn).CornerRadius = UDim.new(0, 6)

-- Status
local statusLbl = Instance.new("TextLabel")
statusLbl.Size = UDim2.new(1, -20, 0, 16)
statusLbl.Position = UDim2.new(0, 10, 0, HEADER_H + 8 + TARGET_H)
statusLbl.BackgroundTransparency = 1
statusLbl.Text = "  —"
statusLbl.TextColor3 = C_SUB
statusLbl.Font = Enum.Font.Gotham
statusLbl.TextSize = 9
statusLbl.TextXAlignment = Enum.TextXAlignment.Left
statusLbl.TextTruncate = Enum.TextTruncate.AtEnd
statusLbl.Parent = main

-- Tab bar
local TAB_Y = HEADER_H + 8 + TARGET_H + STATUS_H
local tabBar = Instance.new("Frame")
tabBar.Size = UDim2.new(1, -20, 0, 26)
tabBar.Position = UDim2.new(0, 10, 0, TAB_Y)
tabBar.BackgroundColor3 = C_CARD
tabBar.BorderSizePixel = 0
tabBar.Parent = main
Instance.new("UICorner", tabBar).CornerRadius = UDim.new(0, 8)
local tbs = Instance.new("UIStroke"); tbs.Color = C_BORDER; tbs.Thickness = 1; tbs.Parent = tabBar

local itemTabBtn = Instance.new("TextButton")
itemTabBtn.Size = UDim2.new(0.5, -2, 1, -4)
itemTabBtn.Position = UDim2.new(0, 2, 0, 2)
itemTabBtn.BackgroundColor3 = C_ACCENT
itemTabBtn.Text = "🌱 Items"
itemTabBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
itemTabBtn.Font = Enum.Font.GothamBold
itemTabBtn.TextSize = 10
itemTabBtn.Parent = tabBar
Instance.new("UICorner", itemTabBtn).CornerRadius = UDim.new(0, 6)

local fruitTabBtn = Instance.new("TextButton")
fruitTabBtn.Size = UDim2.new(0.5, -2, 1, -4)
fruitTabBtn.Position = UDim2.new(0.5, 0, 0, 2)
fruitTabBtn.BackgroundColor3 = C_CARD
fruitTabBtn.Text = "🍎 Fruits"
fruitTabBtn.TextColor3 = C_TEXT
fruitTabBtn.Font = Enum.Font.GothamBold
fruitTabBtn.TextSize = 10
fruitTabBtn.Parent = tabBar
Instance.new("UICorner", fruitTabBtn).CornerRadius = UDim.new(0, 6)

-- Search
local SEARCH_Y = TAB_Y + TAB_H
local searchCard = Instance.new("Frame")
searchCard.Size = UDim2.new(1, -20, 0, 26)
searchCard.Position = UDim2.new(0, 10, 0, SEARCH_Y)
searchCard.BackgroundColor3 = C_CARD
searchCard.BorderSizePixel = 0
searchCard.Parent = main
Instance.new("UICorner", searchCard).CornerRadius = UDim.new(0, 8)
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
searchInput.PlaceholderText = "cari..."
searchInput.PlaceholderColor3 = C_SUB
searchInput.TextColor3 = C_TEXT
searchInput.Font = Enum.Font.Gotham
searchInput.TextSize = 10
searchInput.TextXAlignment = Enum.TextXAlignment.Left
searchInput.ClearTextOnFocus = false
searchInput.Parent = searchCard

-- Counter
local COUNTER_Y = SEARCH_Y + SEARCH_H
local counterLbl = Instance.new("TextLabel")
counterLbl.Size = UDim2.new(1, -20, 0, 14)
counterLbl.Position = UDim2.new(0, 10, 0, COUNTER_Y)
counterLbl.BackgroundTransparency = 1
counterLbl.Text = "0 item"
counterLbl.TextColor3 = C_SUB
counterLbl.Font = Enum.Font.Gotham
counterLbl.TextSize = 9
counterLbl.TextXAlignment = Enum.TextXAlignment.Left
counterLbl.Parent = main

-- List
local LIST_Y = COUNTER_Y + COUNTER_H
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
Instance.new("UICorner", listFrame).CornerRadius = UDim.new(0, 8)
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

-- Bottom
local BOTTOM_Y = LIST_Y + LIST_H + 8

-- Item bottom
local itemBtnRow = Instance.new("Frame")
itemBtnRow.Size = UDim2.new(1, -20, 0, 26)
itemBtnRow.Position = UDim2.new(0, 10, 0, BOTTOM_Y)
itemBtnRow.BackgroundTransparency = 1
itemBtnRow.Parent = main

local clearBtn = Instance.new("TextButton")
clearBtn.Size = UDim2.new(0, 40, 1, 0)
clearBtn.BackgroundColor3 = C_ROW
clearBtn.Text = "🗑"
clearBtn.TextColor3 = C_TEXT
clearBtn.Font = Enum.Font.GothamBold
clearBtn.TextSize = 12
clearBtn.Parent = itemBtnRow
Instance.new("UICorner", clearBtn).CornerRadius = UDim.new(0, 8)

local sendItemBtn = Instance.new("TextButton")
sendItemBtn.Size = UDim2.new(1, -46, 1, 0)
sendItemBtn.Position = UDim2.new(0, 46, 0, 0)
sendItemBtn.BackgroundColor3 = C_GREEN
sendItemBtn.Text = "🔥 SEND ITEM"
sendItemBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
sendItemBtn.Font = Enum.Font.GothamBold
sendItemBtn.TextSize = 11
sendItemBtn.Parent = itemBtnRow
Instance.new("UICorner", sendItemBtn).CornerRadius = UDim.new(0, 8)

-- Fruit bottom
local fruitBottom = Instance.new("Frame")
fruitBottom.Size = UDim2.new(1, -20, 0, 58)
fruitBottom.Position = UDim2.new(0, 10, 0, BOTTOM_Y)
fruitBottom.BackgroundTransparency = 1
fruitBottom.Visible = false
fruitBottom.Parent = main

local fruitTopRow = Instance.new("Frame")
fruitTopRow.Size = UDim2.new(1, 0, 0, 26)
fruitTopRow.BackgroundTransparency = 1
fruitTopRow.Parent = fruitBottom

local clearFruitBtn = Instance.new("TextButton")
clearFruitBtn.Size = UDim2.new(0, 40, 1, 0)
clearFruitBtn.BackgroundColor3 = C_ROW
clearFruitBtn.Text = "🗑"
clearFruitBtn.TextColor3 = C_TEXT
clearFruitBtn.Font = Enum.Font.GothamBold
clearFruitBtn.TextSize = 12
clearFruitBtn.Parent = fruitTopRow
Instance.new("UICorner", clearFruitBtn).CornerRadius = UDim.new(0, 8)

local favAllBtn = Instance.new("TextButton")
favAllBtn.Size = UDim2.new(0.5, -24, 1, 0)
favAllBtn.Position = UDim2.new(0, 46, 0, 0)
favAllBtn.BackgroundColor3 = Color3.fromRGB(60, 130, 90)
favAllBtn.Text = "⭐ Fav All"
favAllBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
favAllBtn.Font = Enum.Font.GothamBold
favAllBtn.TextSize = 10
favAllBtn.Parent = fruitTopRow
Instance.new("UICorner", favAllBtn).CornerRadius = UDim.new(0, 8)

local unfavAllBtn = Instance.new("TextButton")
unfavAllBtn.Size = UDim2.new(0.5, -24, 1, 0)
unfavAllBtn.Position = UDim2.new(0.5, 0, 0, 0)
unfavAllBtn.BackgroundColor3 = Color3.fromRGB(120, 80, 80)
unfavAllBtn.Text = "☆ Unfav All"
unfavAllBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
unfavAllBtn.Font = Enum.Font.GothamBold
unfavAllBtn.TextSize = 10
unfavAllBtn.Parent = fruitTopRow
Instance.new("UICorner", unfavAllBtn).CornerRadius = UDim.new(0, 8)

local sendFruitBtn = Instance.new("TextButton")
sendFruitBtn.Size = UDim2.new(1, 0, 0, 26)
sendFruitBtn.Position = UDim2.new(0, 0, 0, 30)
sendFruitBtn.BackgroundColor3 = C_GREEN
sendFruitBtn.Text = "🔥 SEND FRUIT"
sendFruitBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
sendFruitBtn.Font = Enum.Font.GothamBold
sendFruitBtn.TextSize = 11
sendFruitBtn.Parent = fruitBottom
Instance.new("UICorner", sendFruitBtn).CornerRadius = UDim.new(0, 8)

-- ============ STATE ============
local currentTab         = "items"
local itemList           = {}
local fruitList          = {}
local itemEntries        = {}
local fruitEntries       = {}
local targetId           = nil
local targetName         = nil
local rowRefs            = {}
local query              = ""
local favFingerprint     = ""
local favWatchers        = {}
local backpackConn       = nil
local currentBackpack    = nil

-- ============ HELPERS ============
local function setStatus(text, color)
    statusLbl.Text = "  " .. text
    statusLbl.TextColor3 = color or C_SUB
end

local function updateCounter()
    if currentTab == "items" then
        local nEntries = 0
        for _ in pairs(itemEntries) do nEntries += 1 end
        counterLbl.Text = string.format("%d item  •  %d mail", #itemList, nEntries)
    else
        local favTotal = 0
        for _, e in ipairs(fruitList) do if e.isFav then favTotal += 1 end end
        local nEntries = 0
        for _ in pairs(fruitEntries) do nEntries += 1 end
        counterLbl.Text = string.format("%d fruit  •  %d fav  •  %d mail",
            #fruitList, favTotal, nEntries)
    end
end

local function matchesQuery(text, q)
    if q == "" then return true end
    return text:lower():find(q:lower(), 1, true) ~= nil
end

local function computeFavFingerprint(items)
    local t = {}
    for _, e in ipairs(items) do
        table.insert(t, e.uuid .. ":" .. (e.isFav and "1" or "0"))
    end
    table.sort(t)
    return table.concat(t, "|")
end

local onFavChanged

local function attachFavWatchers(items)
    for uuid, conn in pairs(favWatchers) do
        if conn then conn:Disconnect() end
    end
    favWatchers = {}
    for _, e in ipairs(items) do
        local inst = nil
        local bp = LocalPlayer:FindFirstChild("Backpack")
        if bp then
            for _, c in ipairs(bp:GetChildren()) do
                if c:GetAttribute("Id") == e.uuid then inst = c; break end
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
        if not fruitEntries[uuid] then
            ref.row.BackgroundColor3 = newFav and C_ROW_FAV or C_ROW
        end
    end
    for _, it in ipairs(fruitList) do
        if it.uuid == uuid then it.isFav = newFav end
    end
    updateCounter()
    setStatus((newFav and "★ fav'd " or "☆ unfav'd ") .. inst.Name, C_SUB)
end

local function sanitizeQty(text, maxVal)
    local n = tonumber(text) or 0
    n = math.floor(n)
    if n < 0 then n = 0 end
    if maxVal and n > maxVal then n = maxVal end
    return n
end

-- ============ RENDER ============
local function rebuildList()
    local savedScroll = listFrame.CanvasPosition
    for _, c in ipairs(listFrame:GetChildren()) do
        if c:IsA("TextButton") or c:IsA("TextLabel") or c:IsA("TextBox") then c:Destroy() end
    end
    rowRefs = {}

    if currentTab == "items" then
        itemList = scanItems()

        local live = {}
        for _, it in ipairs(itemList) do
            live[it.category .. "|" .. it.display] = true
        end
        for key in pairs(itemEntries) do
            if not live[key] then itemEntries[key] = nil end
        end

        local filtered = {}
        for _, it in ipairs(itemList) do
            if matchesQuery(it.display, query) or matchesQuery(it.category, query) then
                table.insert(filtered, it)
            end
        end

        for i, it in ipairs(filtered) do
            local key = it.category .. "|" .. it.display
            local sel = itemEntries[key]

            local row = Instance.new("TextButton")
            row.Size = UDim2.new(1, 0, 0, CONFIG.ROW_HEIGHT)
            row.BackgroundColor3 = (sel and sel.count > 0) and C_ROW_SEL or C_ROW
            row.Text = ""
            row.LayoutOrder = i
            row.AutoButtonColor = false
            row.Parent = listFrame
            Instance.new("UICorner", row).CornerRadius = UDim.new(0, 6)

            local catLbl = Instance.new("TextLabel")
            catLbl.Size = UDim2.new(0, 80, 0, 12)
            catLbl.Position = UDim2.new(0, 6, 0, 2)
            catLbl.BackgroundTransparency = 1
            catLbl.Text = it.category
            catLbl.TextColor3 = C_ACCENT
            catLbl.Font = Enum.Font.GothamBold
            catLbl.TextSize = 8
            catLbl.TextXAlignment = Enum.TextXAlignment.Left
            catLbl.Parent = row

            local nameLbl = Instance.new("TextLabel")
            nameLbl.Size = UDim2.new(1, -130, 0, 13)
            nameLbl.Position = UDim2.new(0, 6, 0, 13)
            nameLbl.BackgroundTransparency = 1
            nameLbl.Text = it.display
            nameLbl.TextColor3 = C_TEXT
            nameLbl.Font = Enum.Font.GothamMedium
            nameLbl.TextSize = 10
            nameLbl.TextXAlignment = Enum.TextXAlignment.Left
            nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
            nameLbl.Parent = row

            local stockLbl = Instance.new("TextLabel")
            stockLbl.Size = UDim2.new(0, 40, 1, 0)
            stockLbl.Position = UDim2.new(1, -96, 0, 0)
            stockLbl.BackgroundTransparency = 1
            stockLbl.Text = string.format("x%d", it.count)
            stockLbl.TextColor3 = C_GREEN
            stockLbl.Font = Enum.Font.Code
            stockLbl.TextSize = 9
            stockLbl.TextXAlignment = Enum.TextXAlignment.Right
            stockLbl.Parent = row

            local qtyBox = Instance.new("TextBox")
            qtyBox.Size = UDim2.new(0, 50, 0, 22)
            qtyBox.Position = UDim2.new(1, -56, 0, 4)
            qtyBox.BackgroundColor3 = C_CARD
            qtyBox.BorderSizePixel = 0
            qtyBox.Text = sel and tostring(sel.count) or "0"
            qtyBox.PlaceholderText = "0"
            qtyBox.PlaceholderColor3 = C_SUB
            qtyBox.TextColor3 = C_WARN
            qtyBox.Font = Enum.Font.Code
            qtyBox.TextSize = 11
            qtyBox.TextXAlignment = Enum.TextXAlignment.Center
            qtyBox.ClearTextOnFocus = false
            qtyBox.Parent = row
            Instance.new("UICorner", qtyBox).CornerRadius = UDim.new(0, 6)
            local qtyStroke = Instance.new("UIStroke")
            qtyStroke.Color = C_BORDER; qtyStroke.Thickness = 1; qtyStroke.Parent = qtyBox

            qtyBox.FocusLost:Connect(function()
                local n = sanitizeQty(qtyBox.Text, it.count)
                qtyBox.Text = tostring(n)
                if n > 0 then
                    itemEntries[key] = {
                        name = it.name,
                        display = it.display,
                        category = it.category,
                        count = n,
                    }
                    row.BackgroundColor3 = C_ROW_SEL
                    qtyBox.TextColor3 = C_WARN
                    qtyStroke.Color = C_WARN
                else
                    itemEntries[key] = nil
                    row.BackgroundColor3 = C_ROW
                    qtyBox.TextColor3 = C_SUB
                    qtyStroke.Color = C_BORDER
                end
                updateCounter()
            end)

            rowRefs[key] = { row = row, qtyBox = qtyBox }
        end

        if #filtered == 0 then
            local empty = Instance.new("TextLabel")
            empty.Size = UDim2.new(1, 0, 0, 30)
            empty.BackgroundTransparency = 1
            empty.Text = "  (tidak ada item)"
            empty.TextColor3 = C_SUB
            empty.Font = Enum.Font.Gotham
            empty.TextSize = 10
            empty.TextXAlignment = Enum.TextXAlignment.Left
            empty.Parent = listFrame
        end
    else
        -- ✅ FRUITS: tombol + / − (versi semula)
        fruitList = scanFruits()
        local live = {}
        for _, e in ipairs(fruitList) do live[e.uuid] = true end
        for uuid in pairs(fruitEntries) do
            if not live[uuid] then fruitEntries[uuid] = nil end
        end
        table.sort(fruitList, function(a, b)
            if a.isFav ~= b.isFav then return a.isFav end
            return (a.weight or 0) > (b.weight or 0)
        end)
        local filtered = {}
        for _, e in ipairs(fruitList) do
            if query == "" or matchesQuery(e.name, query) then
                table.insert(filtered, e)
            end
        end
        for i, e in ipairs(filtered) do
            local row = Instance.new("TextButton")
            row.Size = UDim2.new(1, 0, 0, CONFIG.ROW_HEIGHT)
            row.BackgroundColor3 = e.isFav and C_ROW_FAV or C_ROW
            row.Text = ""
            row.LayoutOrder = i
            row.AutoButtonColor = true
            row:SetAttribute("IsFav", e.isFav)
            row.Parent = listFrame
            Instance.new("UICorner", row).CornerRadius = UDim.new(0, 6)

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
            Instance.new("UICorner", actionBtn).CornerRadius = UDim.new(0, 6)

            if fruitEntries[e.uuid] then
                row.BackgroundColor3 = C_ROW_SEL
                actionBtn.BackgroundColor3 = C_RED
                actionBtn.Text = "−"
            end
            rowRefs[e.uuid] = { row = row, actionBtn = actionBtn, star = star }

            actionBtn.MouseButton1Click:Connect(function()
                if fruitEntries[e.uuid] then
                    fruitEntries[e.uuid] = nil
                    row.BackgroundColor3 = e.isFav and C_ROW_FAV or C_ROW
                    actionBtn.BackgroundColor3 = C_GREEN
                    actionBtn.Text = "+"
                else
                    fruitEntries[e.uuid] = { count = 1, name = e.name }
                    row.BackgroundColor3 = C_ROW_SEL
                    actionBtn.BackgroundColor3 = C_RED
                    actionBtn.Text = "−"
                end
                updateCounter()
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
        attachFavWatchers(fruitList)
        favFingerprint = computeFavFingerprint(fruitList)
    end
    updateCounter()
    task.defer(function()
        if listFrame.Parent then listFrame.CanvasPosition = savedScroll end
    end)
end

-- Tab switch
local function setTab(tab)
    currentTab = tab
    if tab == "items" then
        itemTabBtn.BackgroundColor3 = C_ACCENT
        itemTabBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
        fruitTabBtn.BackgroundColor3 = C_CARD
        fruitTabBtn.TextColor3 = C_TEXT
        itemBtnRow.Visible = true
        fruitBottom.Visible = false
        searchInput.PlaceholderText = "cari item..."
    else
        fruitTabBtn.BackgroundColor3 = C_ACCENT
        fruitTabBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
        itemTabBtn.BackgroundColor3 = C_CARD
        itemTabBtn.TextColor3 = C_TEXT
        itemBtnRow.Visible = false
        fruitBottom.Visible = true
        searchInput.PlaceholderText = "cari buah..."
    end
    query = ""
    searchInput.Text = ""
    rebuildList()
end

itemTabBtn.MouseButton1Click:Connect(function() setTab("items") end)
fruitTabBtn.MouseButton1Click:Connect(function() setTab("fruits") end)

searchInput:GetPropertyChangedSignal("Text"):Connect(function()
    query = searchInput.Text
    rebuildList()
end)

-- Target
checkBtn.MouseButton1Click:Connect(function()
    local username = targetInput.Text
    setStatus("⏳ resolving " .. username .. "…", C_WARN)
    task.spawn(function()
        local id = resolveUsername(username)
        if id then
            targetId = id
            targetName = username
            setStatus(string.format("✅ %s  •  ID %d", username, id), C_GREEN)
        else
            targetId = nil
            targetName = nil
            setStatus("❌ gagal resolve: " .. username, C_RED)
        end
    end)
end)

-- Send item
sendItemBtn.MouseButton1Click:Connect(function()
    local list = {}
    for _, data in pairs(itemEntries) do
        if data.count > 0 then
            table.insert(list, {
                uuid     = data.name,
                count    = data.count,
                category = data.category,
            })
        end
    end
    if #list == 0 then
        setStatus("❌ belum ada item di mail", C_RED)
        return
    end
    if not targetId then
        setStatus("❌ target belum di-set", C_RED)
        return
    end
    setStatus("🔥 sending " .. #list .. " item entry…", C_WARN)
    local expanded = expandEntries(list)
    local payload  = buildMultiCategoryPayload(targetId, expanded)
    local ok, err  = pcall(function() remote:FireServer(payload) end)
    if ok then
        setStatus(string.format("✅ sent %d item (%d entry)", #list, #expanded), C_GREEN)
        task.delay(0.5, rebuildList)
        task.delay(1.5, rebuildList)
    else
        setStatus("❌ error: " .. tostring(err), C_RED)
    end
end)

clearBtn.MouseButton1Click:Connect(function()
    itemEntries = {}
    rebuildList()
    setStatus("🗑 mail cleared", C_SUB)
end)

-- Send fruit
sendFruitBtn.MouseButton1Click:Connect(function()
    local list = {}
    for uuid, data in pairs(fruitEntries) do
        if data.count > 0 then
            table.insert(list, {
                uuid     = uuid,
                count    = data.count,
                category = CATEGORY_FRUIT,
            })
        end
    end
    if #list == 0 then
        setStatus("❌ belum ada buah di mail", C_RED)
        return
    end
    if not targetId then
        setStatus("❌ target belum di-set", C_RED)
        return
    end
    setStatus("🔥 sending " .. #list .. " fruit…", C_WARN)
    local expanded = expandEntries(list)
    local payload  = buildMultiCategoryPayload(targetId, expanded)
    local ok, err  = pcall(function() remote:FireServer(payload) end)
    if ok then
        setStatus(string.format("✅ sent %d fruit (%d entry)", #list, #expanded), C_GREEN)
        task.delay(0.5, rebuildList)
        task.delay(1.5, rebuildList)
    else
        setStatus("❌ error: " .. tostring(err), C_RED)
    end
end)

clearFruitBtn.MouseButton1Click:Connect(function()
    fruitEntries = {}
    rebuildList()
    setStatus("🗑 mail cleared", C_SUB)
end)

-- Fav / unfav all
local function bulkFav(isFav)
    local items = scanFruits()
    if #items == 0 then
        setStatus("❌ backpack kosong", C_RED)
        return
    end
    local targets = {}
    for _, e in ipairs(items) do
        if e.isFav ~= isFav then table.insert(targets, e) end
    end
    if #targets == 0 then
        setStatus(isFav and "✅ semua udah fav" or "✅ semua udah unfav", C_SUB)
        return
    end
    setStatus(string.format("⏳ %s %d item…",
        isFav and "favoriting" or "unfavoriting", #targets), C_WARN)
    task.spawn(function()
        local okCount, failCount = 0, 0
        for _, e in ipairs(targets) do
            local ok = pcall(function()
                if isFav then favoriteFruit(e.uuid) else unfavoriteFruit(e.uuid) end
            end)
            if ok then okCount += 1 else failCount += 1 end
            task.wait(BULK_DELAY)
        end
        setStatus(string.format("%s %d ok • %d gagal",
            isFav and "⭐ fav'd" or "☆ unfav'd", okCount, failCount),
            failCount == 0 and C_GREEN or C_RED)
        task.wait(0.3)
        rebuildList()
    end)
end

favAllBtn.MouseButton1Click:Connect(function() bulkFav(true) end)

-- Confirm popup unfav all
local confirmGui = Instance.new("ScreenGui")
confirmGui.Name = "MailSenderConfirm"
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
Instance.new("UICorner", dialog).CornerRadius = UDim.new(0, 12)
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
            "🔴 Matikan dulu script AUTO SELL sebelum lanjut."
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
Instance.new("UICorner", confirmBtn).CornerRadius = UDim.new(0, 8)

local returnBtn = Instance.new("TextButton")
returnBtn.Size = UDim2.new(0, 110, 0, 28)
returnBtn.Position = UDim2.new(1, -124, 1, -38)
returnBtn.BackgroundColor3 = C_ROW
returnBtn.Text = "↩ RETURN"
returnBtn.TextColor3 = C_TEXT
returnBtn.Font = Enum.Font.GothamBold
returnBtn.TextSize = 11
returnBtn.Parent = dialog
Instance.new("UICorner", returnBtn).CornerRadius = UDim.new(0, 8)

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

-- Init
rebuildList()

task.spawn(function()
    local id = resolveUsername(DEFAULT_TARGET)
    if id then
        targetId = id
        targetName = DEFAULT_TARGET
        setStatus(string.format("✅ %s  •  ID %d", DEFAULT_TARGET, id), C_GREEN)
    end
end)

-- Auto refresh
local function hookBackpack()
    local bp = LocalPlayer:FindFirstChild("Backpack")
    if not bp then return end
    if currentBackpack == bp and backpackConn then return end
    if backpackConn and backpackConn.Disconnect then backpackConn:Disconnect() end
    currentBackpack = bp

    local connAdd = bp.ChildAdded:Connect(function(child)
        if child:GetAttribute("Id") or child:IsA("Tool") then
            task.wait(0.1)
            rebuildList()
        end
    end)

    local connRemove = bp.ChildRemoved:Connect(function(child)
        if child:GetAttribute("Id") or child:IsA("Tool") then
            task.defer(rebuildList)
        end
    end)

    backpackConn = {
        Disconnect = function()
            connAdd:Disconnect()
            connRemove:Disconnect()
        end
    }
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
        local bp = LocalPlayer:FindFirstChild("Backpack")
        if bp and currentTab == "fruits" then
            local snapshot = scanFruits()
            local newFp = computeFavFingerprint(snapshot)
            if newFp ~= favFingerprint then
                rebuildList()
            end
        end
    end
end)

print("✅ Mail Sender Combined (items TextBox / fruits +/-) loaded")
