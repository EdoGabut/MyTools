-- ============================================
-- AUTO HARVEST v2.1 (FIXED)
-- - Scan realtime semua plant & fruit
-- - Tampil berat per buah (kg)
-- - Panen manual (klik buah)
-- - Auto-panen tiap ada buah baru
-- - Filter berat (min/max)
-- ============================================

local CoreGui         = game:GetService("CoreGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players         = game:GetService("Players")

local LocalPlayer = Players.LocalPlayer

-- Guard: buffer (Luau native, tapi beberapa executor lawas mungkin nggak ada)
local buffer = buffer or (typeof and typeof(buffer) == "table" and buffer) or nil

local Packet = ReplicatedStorage:WaitForChild("SharedModules")
    :WaitForChild("Packet"):WaitForChild("RemoteEvent")

local ROOT = workspace:WaitForChild("Gardens")

-- ============ CONFIG ============

local CONFIG = {
    MIN_WEIGHT   = 0,
    MAX_WEIGHT   = 999999,
    AUTO_DELAY   = 0.3,
    AUTO_ENABLED = false,
    ONLY_MY_PLOTS = true,
    LOG_LIMIT    = 80,
}

-- ============ UTIL ============

local function stripTags(s)
    return (s:gsub("<[^>]+>", ""))
end

local function extractWeightFromText(text)
    if not text then return nil end
    local plain = stripTags(text)
    local w = plain:match("([%d%.]+)%s*[kK][gG]")
    return w and tonumber(w) or nil
end

local function extractNameFromText(text)
    if not text then return nil end
    local plain = stripTags(text)
    -- Ambil teks sebelum simbol ⚖ atau sebelum angka kg
    local name = plain:match("^%s*([^⚖%d]+)")
    if name then
        name = name:gsub("%s+$", "")
        if #name > 0 then return name end
    end
    return nil
end

-- Cari TextLabel di dalam sebuah Instance (rekursif)
local function findTextLabels(root)
    local out = {}
    for _, d in ipairs(root:GetDescendants()) do
        if d:IsA("TextLabel") or d:IsA("TextButton") then
            table.insert(out, d)
        end
    end
    return out
end

local function getFruitWeight(fruit)
    -- Prioritas: HarvestPart > HarvestPromptLabel
    local part = fruit:FindFirstChild("HarvestPart", true)
    local scope = part or fruit

    local lbl = scope:FindFirstChild("HarvestPromptLabel", true)
    if lbl then
        for _, d in ipairs(findTextLabels(lbl)) do
            local w = extractWeightFromText(d.Text)
            if w then return w end
        end
    end

    -- Fallback: scan semua descendant fruit
    for _, d in ipairs(findTextLabels(fruit)) do
        local w = extractWeightFromText(d.Text)
        if w then return w end
    end

    return nil
end

local function getFruitName(fruit)
    local part = fruit:FindFirstChild("HarvestPart", true)
    local scope = part or fruit

    local lbl = scope:FindFirstChild("HarvestPromptLabel", true)
    if lbl then
        for _, d in ipairs(findTextLabels(lbl)) do
            local n = extractNameFromText(d.Text)
            if n then return n end
        end
    end

    for _, d in ipairs(findTextLabels(fruit)) do
        local n = extractNameFromText(d.Text)
        if n and not n:match("^%s*$") then return n end
    end

    return nil
end

local function getPlantUuid(plant)
    return plant.Name:match("_(.+)$")
end

local function getFruitIndex(fruit)
    return fruit.Name:match("_(%d+)$")
end

local function getOwnerId(plant)
    local id = plant.Name:match("^(%d+)_")
    return id and tonumber(id) or nil
end

local function harvest(plant, fruit)
    if not buffer then
        return false, "buffer not supported"
    end
    local uuid = getPlantUuid(plant)
    local idx  = getFruitIndex(fruit)
    if not uuid or not idx then return false, "Format invalid" end

    local ok, err = pcall(function()
        local payload = ")\001$" .. uuid .. "\001" .. idx
        Packet:FireServer(buffer.fromstring(payload))
    end)
    if not ok then return false, tostring(err) end
    return true
end

-- ============ STATE ============

local state = {
    fruits = {},  -- [fruitInstance] = {weight, name, plant, index, userId}
    autoRunning = false,
}

-- ============ GUI ============

local old = CoreGui:FindFirstChild("AutoHarvestV2")
if old then old:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "AutoHarvestV2"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = CoreGui

local main = Instance.new("Frame")
main.Size = UDim2.new(0, 380, 0, 560)
main.Position = UDim2.new(0, 20, 0, 60)
main.BackgroundColor3 = Color3.fromRGB(24, 24, 30)
main.BorderSizePixel = 0
main.Active = true
main.Draggable = true
main.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 10)
corner.Parent = main

-- Title bar
local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 0, 32)
title.BackgroundColor3 = Color3.fromRGB(40, 40, 52)
title.BorderSizePixel = 0
title.Text = "  🌾 Auto Harvest v2.1"
title.TextColor3 = Color3.fromRGB(230, 230, 240)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Font = Enum.Font.GothamBold
title.TextSize = 13
title.Parent = main

local titleCorner = Instance.new("UICorner")
titleCorner.CornerRadius = UDim.new(0, 10)
titleCorner.Parent = title

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 32, 0, 32)
closeBtn.Position = UDim2.new(1, -32, 0, 0)
closeBtn.BackgroundTransparency = 1
closeBtn.Text = "✕"
closeBtn.TextColor3 = Color3.fromRGB(255, 100, 100)
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 16
closeBtn.Parent = title
closeBtn.MouseButton1Click:Connect(function() gui:Destroy() end)

-- ============ FILTER SECTION ============

local filterFrame = Instance.new("Frame")
filterFrame.Size = UDim2.new(1, -16, 0, 74)
filterFrame.Position = UDim2.new(0, 8, 0, 40)
filterFrame.BackgroundColor3 = Color3.fromRGB(32, 32, 42)
filterFrame.BorderSizePixel = 0
filterFrame.Parent = main

local ffCorner = Instance.new("UICorner")
ffCorner.CornerRadius = UDim.new(0, 6)
ffCorner.Parent = filterFrame

local filterTitle = Instance.new("TextLabel")
filterTitle.Size = UDim2.new(1, -10, 0, 18)
filterTitle.Position = UDim2.new(0, 6, 0, 2)
filterTitle.BackgroundTransparency = 1
filterTitle.Text = "⚖️ Filter Berat (kg)"
filterTitle.TextColor3 = Color3.fromRGB(180, 200, 255)
filterTitle.Font = Enum.Font.GothamBold
filterTitle.TextSize = 11
filterTitle.TextXAlignment = Enum.TextXAlignment.Left
filterTitle.Parent = filterFrame

local function makeInput(parent, xPos, labelText, defaultVal)
    local container = Instance.new("Frame")
    container.Size = UDim2.new(0, 160, 0, 36)
    container.Position = UDim2.new(0, xPos, 0, 24)
    container.BackgroundTransparency = 1
    container.Parent = parent

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, 0, 0, 12)
    lbl.BackgroundTransparency = 1
    lbl.Text = labelText
    lbl.TextColor3 = Color3.fromRGB(150, 150, 170)
    lbl.Font = Enum.Font.Gotham
    lbl.TextSize = 10
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = container

    local box = Instance.new("TextBox")
    box.Size = UDim2.new(1, 0, 0, 22)
    box.Position = UDim2.new(0, 0, 0, 14)
    box.BackgroundColor3 = Color3.fromRGB(45, 45, 58)
    box.BorderSizePixel = 0
    box.Text = tostring(defaultVal)
    box.TextColor3 = Color3.fromRGB(230, 230, 240)
    box.Font = Enum.Font.Code
    box.TextSize = 13
    box.ClearTextOnFocus = false
    box.Parent = container

    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 4)
    c.Parent = box

    return box
end

local minBox = makeInput(filterFrame, 8,   "Min", CONFIG.MIN_WEIGHT)
local maxBox = makeInput(filterFrame, 180, "Max", CONFIG.MAX_WEIGHT)

minBox.FocusLost:Connect(function()
    local v = tonumber(minBox.Text)
    if v then CONFIG.MIN_WEIGHT = v else minBox.Text = tostring(CONFIG.MIN_WEIGHT) end
end)
maxBox.FocusLost:Connect(function()
    local v = tonumber(maxBox.Text)
    if v then CONFIG.MAX_WEIGHT = v else maxBox.Text = tostring(CONFIG.MAX_WEIGHT) end
end)

-- ============ AUTO TOGGLE ============

local autoBtn = Instance.new("TextButton")
autoBtn.Size = UDim2.new(0.55, -8, 0, 36)
autoBtn.Position = UDim2.new(0, 8, 0, 120)
autoBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 75)
autoBtn.Text = "🤖 AUTO: OFF"
autoBtn.TextColor3 = Color3.fromRGB(230, 230, 240)
autoBtn.Font = Enum.Font.GothamBold
autoBtn.TextSize = 13
autoBtn.Parent = main

local autoCorner = Instance.new("UICorner")
autoCorner.CornerRadius = UDim.new(0, 6)
autoCorner.Parent = autoBtn

autoBtn.MouseButton1Click:Connect(function()
    CONFIG.AUTO_ENABLED = not CONFIG.AUTO_ENABLED
    if CONFIG.AUTO_ENABLED then
        autoBtn.Text = "🤖 AUTO: ON"
        autoBtn.BackgroundColor3 = Color3.fromRGB(40, 130, 70)
    else
        autoBtn.Text = "🤖 AUTO: OFF"
        autoBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 75)
    end
end)

-- Tombol Panen Semua
local harvestAllBtn = Instance.new("TextButton")
harvestAllBtn.Size = UDim2.new(0.45, -8, 0, 36)
harvestAllBtn.Position = UDim2.new(0.55, 0, 0, 120)
harvestAllBtn.BackgroundColor3 = Color3.fromRGB(90, 60, 130)
harvestAllBtn.Text = "🌾 Panen Semua"
harvestAllBtn.TextColor3 = Color3.fromRGB(240, 230, 255)
harvestAllBtn.Font = Enum.Font.GothamBold
harvestAllBtn.TextSize = 12
harvestAllBtn.Parent = main

local haCorner = Instance.new("UICorner")
haCorner.CornerRadius = UDim.new(0, 6)
haCorner.Parent = harvestAllBtn

-- ============ INFO LABEL ============

local filterInfo = Instance.new("TextLabel")
filterInfo.Size = UDim2.new(1, -16, 0, 18)
filterInfo.Position = UDim2.new(0, 8, 0, 158)
filterInfo.BackgroundTransparency = 1
filterInfo.Text = "Buah siap panen: 0"
filterInfo.TextColor3 = Color3.fromRGB(180, 180, 200)
filterInfo.Font = Enum.Font.Gotham
filterInfo.TextSize = 11
filterInfo.TextXAlignment = Enum.TextXAlignment.Left
filterInfo.Parent = main

-- ============ FRUIT LIST ============

local listLabel = Instance.new("TextLabel")
listLabel.Size = UDim2.new(1, -16, 0, 16)
listLabel.Position = UDim2.new(0, 8, 0, 178)
listLabel.BackgroundTransparency = 1
listLabel.Text = "🍎 Daftar Buah (klik untuk panen)"
listLabel.TextColor3 = Color3.fromRGB(180, 200, 255)
listLabel.Font = Enum.Font.GothamBold
listLabel.TextSize = 11
listLabel.TextXAlignment = Enum.TextXAlignment.Left
listLabel.Parent = main

local listFrame = Instance.new("ScrollingFrame")
listFrame.Size = UDim2.new(1, -16, 0, 280)
listFrame.Position = UDim2.new(0, 8, 0, 198)
listFrame.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
listFrame.BorderSizePixel = 0
listFrame.ScrollBarThickness = 6
listFrame.ScrollBarImageColor3 = Color3.fromRGB(80, 80, 100)
listFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
listFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
listFrame.Parent = main

local listCorner = Instance.new("UICorner")
listCorner.CornerRadius = UDim.new(0, 6)
listCorner.Parent = listFrame

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

-- ============ LOG ============

local logLabel = Instance.new("TextLabel")
logLabel.Size = UDim2.new(1, -16, 0, 16)
logLabel.Position = UDim2.new(0, 8, 0, 484)
logLabel.BackgroundTransparency = 1
logLabel.Text = "📋 Log"
logLabel.TextColor3 = Color3.fromRGB(180, 200, 255)
logLabel.Font = Enum.Font.GothamBold
logLabel.TextSize = 11
logLabel.TextXAlignment = Enum.TextXAlignment.Left
logLabel.Parent = main

local logFrame = Instance.new("ScrollingFrame")
logFrame.Size = UDim2.new(1, -16, 0, 60)
logFrame.Position = UDim2.new(0, 8, 0, 502)
logFrame.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
logFrame.BorderSizePixel = 0
logFrame.ScrollBarThickness = 4
logFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
logFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
logFrame.Parent = main

local logCorner = Instance.new("UICorner")
logCorner.CornerRadius = UDim.new(0, 6)
logCorner.Parent = logFrame

local logLayout = Instance.new("UIListLayout")
logLayout.Padding = UDim.new(0, 1)
logLayout.SortOrder = Enum.SortOrder.LayoutOrder
logLayout.Parent = logFrame

local logPad = Instance.new("UIPadding")
logPad.PaddingTop = UDim.new(0, 3)
logPad.PaddingBottom = UDim.new(0, 3)
logPad.PaddingLeft = UDim.new(0, 6)
logPad.PaddingRight = UDim.new(0, 6)
logPad.Parent = logFrame

local logCounter = 0

local function addLog(msg, color)
    logCounter = logCounter + 1
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, 0, 0, 14)
    lbl.BackgroundTransparency = 1
    lbl.Text = "• " .. msg
    lbl.TextColor3 = color or Color3.fromRGB(180, 180, 200)
    lbl.Font = Enum.Font.Code
    lbl.TextSize = 10
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.LayoutOrder = logCounter
    lbl.Parent = logFrame

    -- Batasi log: hapus yang paling lama kalau > LIMIT
    local labels = {}
    for _, k in ipairs(logFrame:GetChildren()) do
        if k:IsA("TextLabel") then table.insert(labels, k) end
    end
    if #labels > CONFIG.LOG_LIMIT then
        table.sort(labels, function(a, b) return a.LayoutOrder < b.LayoutOrder end)
        for i = 1, (#labels - CONFIG.LOG_LIMIT) do
            labels[i]:Destroy()
        end
    end
end

-- ============ FRUIT LIST RENDER ============

local listRowCounter = 0

local function renderFruitList()
    -- Cleanup hanya TextButton (row), biar UIListLayout & UIPadding aman
    for _, c in ipairs(listFrame:GetChildren()) do
        if c:IsA("TextButton") then c:Destroy() end
    end
    listRowCounter = 0

    local entries = {}
    for fruit, data in pairs(state.fruits) do
        if fruit.Parent then
            table.insert(entries, {
                fruit  = fruit,
                weight = data.weight,
                name   = data.name,
                plant  = data.plant,
                index  = data.index,
            })
        end
    end
    table.sort(entries, function(a, b)
        return (a.weight or 0) > (b.weight or 0)
    end)

    local readyCount = 0

    for _, e in ipairs(entries) do
        listRowCounter = listRowCounter + 1

        local inFilter = e.weight
            and e.weight >= CONFIG.MIN_WEIGHT
            and e.weight <= CONFIG.MAX_WEIGHT

        if inFilter then readyCount = readyCount + 1 end

        local row = Instance.new("TextButton")
        row.Size = UDim2.new(1, 0, 0, 26)
        row.BackgroundColor3 = inFilter
            and Color3.fromRGB(30, 60, 40)
            or Color3.fromRGB(30, 30, 40)
        row.Text = ""
        row.LayoutOrder = listRowCounter
        row.AutoButtonColor = true
        row.Parent = listFrame

        local rc = Instance.new("UICorner")
        rc.CornerRadius = UDim.new(0, 4)
        rc.Parent = row

        local nameLbl = Instance.new("TextLabel")
        nameLbl.Size = UDim2.new(0.65, 0, 1, 0)
        nameLbl.Position = UDim2.new(0, 6, 0, 0)
        nameLbl.BackgroundTransparency = 1
        nameLbl.Text = (e.name or "?") .. "  #" .. (e.index or "?")
        nameLbl.TextColor3 = inFilter
            and Color3.fromRGB(200, 255, 200)
            or Color3.fromRGB(150, 150, 160)
        nameLbl.Font = Enum.Font.Gotham
        nameLbl.TextSize = 11
        nameLbl.TextXAlignment = Enum.TextXAlignment.Left
        nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
        nameLbl.Parent = row

        local weightLbl = Instance.new("TextLabel")
        weightLbl.Size = UDim2.new(0.3, 0, 1, 0)
        weightLbl.Position = UDim2.new(0.68, 0, 0, 0)
        weightLbl.BackgroundTransparency = 1
        weightLbl.Text = e.weight and (string.format("%.2f kg", e.weight)) or "? kg"
        weightLbl.TextColor3 = inFilter
            and Color3.fromRGB(150, 255, 150)
            or Color3.fromRGB(200, 130, 130)
        weightLbl.Font = Enum.Font.GothamBold
        weightLbl.TextSize = 11
        weightLbl.TextXAlignment = Enum.TextXAlignment.Right
        weightLbl.Parent = row

        row.MouseButton1Click:Connect(function()
            if not e.fruit.Parent then
                addLog("Buah udah gak ada", Color3.fromRGB(255, 150, 150))
                state.fruits[e.fruit] = nil
                renderFruitList()
                return
            end
            local ok = harvest(e.plant, e.fruit)
            if ok then
                addLog("🌾 Panen " .. (e.name or "?") ..
                    " (" .. string.format("%.2f", e.weight or 0) .. "kg)",
                    Color3.fromRGB(150, 255, 150))
                state.fruits[e.fruit] = nil
                renderFruitList()
            else
                addLog("❌ Gagal panen " .. (e.name or "?"),
                    Color3.fromRGB(255, 150, 150))
            end
        end)
    end

    filterInfo.Text = "Buah siap panen: " .. readyCount .. " / " .. #entries
end

-- ============ SCAN ============

local function scanPlant(plant)
    local ownerId = getOwnerId(plant)
    if CONFIG.ONLY_MY_PLOTS and ownerId ~= LocalPlayer.UserId then
        return
    end

    local fruits = plant:FindFirstChild("Fruits")
    if not fruits then return end

    for _, fruit in ipairs(fruits:GetChildren()) do
        local idx = getFruitIndex(fruit)
        if idx then
            local existing = state.fruits[fruit]
            if not existing then
                local weight = getFruitWeight(fruit)
                local name   = getFruitName(fruit)
                state.fruits[fruit] = {
                    weight = weight,
                    name   = name,
                    plant  = plant,
                    index  = idx,
                    userId = ownerId,
                }
                addLog("🆕 " .. (name or "?") .. " #" .. idx ..
                    " (" .. (weight and string.format("%.2f", weight) or "?") .. "kg)",
                    Color3.fromRGB(180, 220, 255))
            else
                -- Update berat kalau berubah
                local w = getFruitWeight(fruit)
                if w and w ~= existing.weight then
                    existing.weight = w
                end
                -- Update plant reference (jaga-jaga plant di-reparent)
                existing.plant = plant
            end
        end
    end
end

local function fullScan()
    for _, plot in ipairs(ROOT:GetChildren()) do
        local plants = plot:FindFirstChild("Plants")
        if plants then
            for _, plant in ipairs(plants:GetChildren()) do
                scanPlant(plant)
            end
        end
    end

    -- Bersihkan fruit yang udah hilang
    for fruit, _ in pairs(state.fruits) do
        if not fruit.Parent then
            state.fruits[fruit] = nil
        end
    end
end

-- ============ PANEN SEMUA ============

harvestAllBtn.MouseButton1Click:Connect(function()
    local count = 0
    for fruit, data in pairs(state.fruits) do
        if fruit.Parent and data.weight
            and data.weight >= CONFIG.MIN_WEIGHT
            and data.weight <= CONFIG.MAX_WEIGHT then
            local ok = harvest(data.plant, fruit)
            if ok then count = count + 1 end
            task.wait(0.05)
        end
    end
    addLog("🌾 Panen semua: " .. count .. " buah", Color3.fromRGB(200, 180, 255))
    task.wait(0.3)
    fullScan()
    renderFruitList()
end)

-- ============ AUTO HARVEST LOOP ============

task.spawn(function()
    while gui.Parent do
        task.wait(CONFIG.AUTO_DELAY)

        if CONFIG.AUTO_ENABLED then
            local best = nil
            for fruit, data in pairs(state.fruits) do
                if fruit.Parent and data.weight
                    and data.weight >= CONFIG.MIN_WEIGHT
                    and data.weight <= CONFIG.MAX_WEIGHT then
                    if not best or data.weight > best.weight then
                        best = { fruit = fruit, data = data, weight = data.weight }
                    end
                end
            end

            if best then
                local ok = harvest(best.data.plant, best.fruit)
                if ok then
                    addLog("🤖 AUTO: " .. (best.data.name or "?") ..
                        " (" .. string.format("%.2f", best.data.weight) .. "kg)",
                        Color3.fromRGB(100, 255, 200))
                    state.fruits[best.fruit] = nil
                    renderFruitList()
                end
                task.wait(0.1)
            end
        end
    end
end)

-- ============ REALTIME SCAN ============

-- Scan tiap 1 detik (render hanya kalau perlu)
task.spawn(function()
    local lastCount = -1
    while gui.Parent do
        fullScan()
        local now = 0
        for _ in pairs(state.fruits) do now = now + 1 end
        if now ~= lastCount then
            renderFruitList()
            lastCount = now
        end
        task.wait(1)
    end
end)

-- Hook container (ChildAdded/Removed)
local function hookContainer(container)
    container.ChildAdded:Connect(function()
        task.wait(0.2)
        fullScan()
        renderFruitList()
    end)
    container.ChildRemoved:Connect(function()
        task.wait(0.1)
        fullScan()
        renderFruitList()
    end)
end

hookContainer(ROOT)
for _, plot in ipairs(ROOT:GetChildren()) do
    local plants = plot:FindFirstChild("Plants")
    if plants then hookContainer(plants) end
end
ROOT.ChildAdded:Connect(function(plot)
    task.wait(0.5)
    local plants = plot:FindFirstChild("Plants")
    if plants then hookContainer(plants) end
end)

-- ============ INIT ============

fullScan()
renderFruitList()
addLog("✅ Script loaded", Color3.fromRGB(150, 255, 150))
