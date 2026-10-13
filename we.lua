-- ============================================
-- FRUIT SCANNER + ESP + PER-FRUIT COPY
-- Tiap buah ada tombol Copy sendiri
-- ============================================

local CoreGui = game:GetService("CoreGui")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer
local ROOT = workspace:WaitForChild("Gardens")

-- ============ ESP SYSTEM ============

local espFolder = Instance.new("Folder")
espFolder.Name = "FruitESP"
espFolder.Parent = CoreGui

local espParts = {}
local espEnabled = true

local function createESP(part, labelText)
    if espParts[part] then return end

    local highlight = Instance.new("Highlight")
    highlight.Name = "ESPHighlight"
    highlight.FillColor = Color3.fromRGB(255, 80, 80)
    highlight.FillTransparency = 0.5
    highlight.OutlineColor = Color3.fromRGB(255, 255, 0)
    highlight.OutlineTransparency = 0
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.Adornee = part
    highlight.Parent = espFolder

    local billboard = Instance.new("BillboardGui")
    billboard.Name = "ESPBillboard"
    billboard.Size = UDim2.new(0, 200, 0, 50)
    billboard.StudsOffset = Vector3.new(0, 3, 0)
    billboard.AlwaysOnTop = true
    billboard.Adornee = part
    billboard.Parent = espFolder

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, 0, 1, 0)
    label.BackgroundTransparency = 1
    label.Text = labelText
    label.TextColor3 = Color3.fromRGB(255, 255, 100)
    label.TextStrokeTransparency = 0
    label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    label.Font = Enum.Font.GothamBold
    label.TextSize = 12
    label.TextWrapped = true
    label.Parent = billboard

    espParts[part] = {
        highlight = highlight,
        billboard = billboard,
        label = label,
    }
end

local function removeESP(part)
    local data = espParts[part]
    if not data then return end
    if data.highlight then data.highlight:Destroy() end
    if data.billboard then data.billboard:Destroy() end
    espParts[part] = nil
end

local function clearAllESP()
    for part, _ in pairs(espParts) do
        removeESP(part)
    end
    espParts = {}
end

-- ============ COLLECT ============

local function getAllFruits()
    local out = {}
    for _, plot in ipairs(ROOT:GetChildren()) do
        local plants = plot:FindFirstChild("Plants")
        if plants then
            for _, plant in ipairs(plants:GetChildren()) do
                local fruits = plant:FindFirstChild("Fruits")
                if fruits then
                    for _, fruit in ipairs(fruits:GetChildren()) do
                        table.insert(out, {
                            fruit = fruit,
                            plant = plant,
                            plot = plot,
                        })
                    end
                end
            end
        end
    end
    return out
end

-- ============ PROPERTY READER ============

local function formatValue(val)
    local t = typeof(val)

    if t == "Vector3" then
        return string.format("(%.4f, %.4f, %.4f)", val.X, val.Y, val.Z)
    elseif t == "CFrame" then
        local p = val.Position
        return string.format("Pos(%.3f, %.3f, %.3f)", p.X, p.Y, p.Z)
    elseif t == "PhysicalProperties" then
        return string.format("D=%.3f F=%.3f E=%.3f",
            val.Density, val.Friction, val.Elasticity)
    elseif t == "Instance" then
        return val:GetFullName()
    elseif t == "Color3" then
        return string.format("RGB(%d, %d, %d)",
            val.R * 255, val.G * 255, val.B * 255)
    elseif t == "BrickColor" then
        return val.Name
    elseif t == "number" then
        if val == math.floor(val) then
            return tostring(val)
        else
            return string.format("%.4f", val)
        end
    elseif t == "table" then
        local parts = {}
        for k, v in pairs(val) do
            table.insert(parts, tostring(k) .. "=" .. tostring(v))
        end
        return "{" .. table.concat(parts, ", ") .. "}"
    else
        return tostring(val)
    end
end

local function colorForType(t)
    if t == "number" then return Color3.fromRGB(180, 230, 180)
    elseif t == "string" then return Color3.fromRGB(255, 200, 150)
    elseif t == "boolean" then return Color3.fromRGB(150, 200, 255)
    elseif t == "Vector3" then return Color3.fromRGB(255, 220, 100)
    elseif t == "CFrame" then return Color3.fromRGB(255, 180, 200)
    elseif t == "Instance" then return Color3.fromRGB(180, 255, 180)
    elseif t == "Color3" then return Color3.fromRGB(255, 150, 200)
    elseif t == "BrickColor" then return Color3.fromRGB(255, 180, 220)
    elseif t == "Material" then return Color3.fromRGB(200, 255, 220)
    else return Color3.fromRGB(200, 200, 200)
    end
end

local COMMON_PROPS = {
    "Name", "ClassName",
    "Size", "Position", "Orientation", "CFrame",
    "Anchored", "CanCollide", "CanTouch", "CanQuery",
    "Transparency", "Reflectance", "Material",
    "Color", "BrickColor",
    "Massless", "RootPriority",
    "AssemblyLinearVelocity", "AssemblyAngularVelocity",
    "CustomPhysicalProperties",
}

local MODEL_PROPS = {
    "Scale", "PrimaryPart", "WorldPivot",
}

local function readProperties(inst)
    local props = {}
    local propList = {}

    for _, p in ipairs(COMMON_PROPS) do table.insert(propList, p) end
    if inst:IsA("Model") then
        for _, p in ipairs(MODEL_PROPS) do
            if not table.find(propList, p) then table.insert(propList, p) end
        end
    end

    for _, propName in ipairs(propList) do
        local ok, val = pcall(function() return inst[propName] end)
        if ok and val ~= nil then
            table.insert(props, {
                name = propName,
                value = val,
                type = typeof(val),
            })
        end
    end

    if inst:IsA("BasePart") then
        local ok, mass = pcall(function() return inst:GetMass() end)
        if ok then
            table.insert(props, { name = "GetMass()", value = mass, type = "number" })
        end
    end

    if inst:IsA("Model") then
        local ok, ext = pcall(function() return inst:GetExtentsSize() end)
        if ok then
            table.insert(props, { name = "GetExtentsSize()", value = ext, type = "Vector3" })
        end
        if inst.GetScale then
            local ok2, scale = pcall(function() return inst:GetScale() end)
            if ok2 then
                table.insert(props, { name = "GetScale()", value = scale, type = "number" })
            end
        end
    end

    local attrs = inst:GetAttributes()
    for attrName, attrVal in pairs(attrs) do
        table.insert(props, {
            name = "ATTR:" .. attrName,
            value = attrVal,
            type = "attr/" .. typeof(attrVal),
        })
    end

    local tags = inst:GetTags()
    if #tags > 0 then
        table.insert(props, {
            name = "Tags",
            value = table.concat(tags, ", "),
            type = "tags",
        })
    end

    return props
end

-- ============ COPY HELPER ============

local function copyToClipboard(text)
    local copied = false
    if setclipboard and pcall(setclipboard, text) then copied = true end
    if not copied and toclipboard and pcall(toclipboard, text) then copied = true end
    if not copied then
        print(text)
    end
    return copied
end

local function buildFruitDump(entry)
    local lines = {}
    table.insert(lines, "=== FRUIT DUMP ===")
    table.insert(lines, "Fruit: " .. entry.fruit.Name)
    table.insert(lines, "FullName: " .. entry.fruit:GetFullName())
    table.insert(lines, "")

    local fruit = entry.fruit
    local model = fruit:IsA("Model") and fruit or fruit:FindFirstChildOfClass("Model")

    if model then
        table.insert(lines, "[MODEL] " .. model.Name .. " [" .. model.ClassName .. "]")
        local modelProps = readProperties(model)
        for _, p in ipairs(modelProps) do
            table.insert(lines, string.format("  %s = %s (%s)",
                p.name, formatValue(p.value), p.type))
        end
        table.insert(lines, "")
    end

    local parts = {}
    for _, d in ipairs(fruit:GetDescendants()) do
        if d:IsA("BasePart") then table.insert(parts, d) end
    end

    for i, part in ipairs(parts) do
        table.insert(lines, "[PART #" .. i .. "] " .. part.Name .. " [" .. part.ClassName .. "]")
        table.insert(lines, "  FullName: " .. part:GetFullName())
        local props = readProperties(part)
        for _, p in ipairs(props) do
            table.insert(lines, string.format("  %s = %s (%s)",
                p.name, formatValue(p.value), p.type))
        end
        table.insert(lines, "")
    end

    table.insert(lines, "=== END ===")
    return table.concat(lines, "\n")
end

-- ============ GUI ============

local old = CoreGui:FindFirstChild("FruitScannerESP")
if old then old:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "FruitScannerESP"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = CoreGui

local main = Instance.new("Frame")
main.Size = UDim2.new(0, 1000, 0, 660)
main.Position = UDim2.new(0, 20, 0, 20)
main.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
main.BorderSizePixel = 0
main.Active = true
main.Draggable = true
main.Parent = gui

local mc = Instance.new("UICorner")
mc.CornerRadius = UDim.new(0, 10)
mc.Parent = main

-- Title
local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 0, 32)
title.BackgroundColor3 = Color3.fromRGB(40, 40, 52)
title.BorderSizePixel = 0
title.Text = "  🍎 Fruit Scanner + ESP + Per-Fruit Copy"
title.TextColor3 = Color3.fromRGB(230, 230, 240)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Font = Enum.Font.GothamBold
title.TextSize = 13
title.Parent = main

local tc = Instance.new("UICorner")
tc.CornerRadius = UDim.new(0, 10)
tc.Parent = title

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 32, 0, 32)
closeBtn.Position = UDim2.new(1, -32, 0, 0)
closeBtn.BackgroundTransparency = 1
closeBtn.Text = "✕"
closeBtn.TextColor3 = Color3.fromRGB(255, 100, 100)
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 16
closeBtn.Parent = title
closeBtn.MouseButton1Click:Connect(function()
    clearAllESP()
    gui:Destroy()
end)

-- Toolbar
local toolbar = Instance.new("Frame")
toolbar.Size = UDim2.new(1, -16, 0, 40)
toolbar.Position = UDim2.new(0, 8, 0, 40)
toolbar.BackgroundColor3 = Color3.fromRGB(32, 32, 42)
toolbar.BorderSizePixel = 0
toolbar.Parent = main

local tbc = Instance.new("UICorner")
tbc.CornerRadius = UDim.new(0, 6)
tbc.Parent = toolbar

local espToggle = Instance.new("TextButton")
espToggle.Size = UDim2.new(0, 140, 0, 28)
espToggle.Position = UDim2.new(0, 8, 0, 6)
espToggle.BackgroundColor3 = Color3.fromRGB(40, 130, 70)
espToggle.Text = "🎯 ESP: ON"
espToggle.TextColor3 = Color3.fromRGB(230, 230, 240)
espToggle.Font = Enum.Font.GothamBold
espToggle.TextSize = 11
espToggle.Parent = toolbar

local etc = Instance.new("UICorner")
etc.CornerRadius = UDim.new(0, 4)
etc.Parent = espToggle

local clearEspBtn = Instance.new("TextButton")
clearEspBtn.Size = UDim2.new(0, 130, 0, 28)
clearEspBtn.Position = UDim2.new(0, 154, 0, 6)
clearEspBtn.BackgroundColor3 = Color3.fromRGB(120, 60, 60)
clearEspBtn.Text = "🗑️ Clear ESP"
clearEspBtn.TextColor3 = Color3.fromRGB(255, 230, 230)
clearEspBtn.Font = Enum.Font.GothamBold
clearEspBtn.TextSize = 11
clearEspBtn.Parent = toolbar

local cec = Instance.new("UICorner")
cec.CornerRadius = UDim.new(0, 4)
cec.Parent = clearEspBtn

local espCountLbl = Instance.new("TextLabel")
espCountLbl.Size = UDim2.new(1, -300, 1, 0)
espCountLbl.Position = UDim2.new(0, 290, 0, 0)
espCountLbl.BackgroundTransparency = 1
espCountLbl.Text = "ESP: 0 part"
espCountLbl.TextColor3 = Color3.fromRGB(180, 200, 255)
espCountLbl.Font = Enum.Font.Code
espCountLbl.TextSize = 11
espCountLbl.TextXAlignment = Enum.TextXAlignment.Left
espCountLbl.Parent = toolbar

-- LEFT: list fruits
local leftFrame = Instance.new("Frame")
leftFrame.Size = UDim2.new(0, 340, 1, -140)
leftFrame.Position = UDim2.new(0, 8, 0, 88)
leftFrame.BackgroundColor3 = Color3.fromRGB(24, 24, 32)
leftFrame.BorderSizePixel = 0
leftFrame.Parent = main

local lc = Instance.new("UICorner")
lc.CornerRadius = UDim.new(0, 6)
lc.Parent = leftFrame

local leftLabel = Instance.new("TextLabel")
leftLabel.Size = UDim2.new(1, -10, 0, 20)
leftLabel.Position = UDim2.new(0, 5, 0, 4)
leftLabel.BackgroundTransparency = 1
leftLabel.Text = "🍎 Fruits (0)"
leftLabel.TextColor3 = Color3.fromRGB(180, 200, 255)
leftLabel.Font = Enum.Font.GothamBold
leftLabel.TextSize = 11
leftLabel.TextXAlignment = Enum.TextXAlignment.Left
leftLabel.Parent = leftFrame

local listScroll = Instance.new("ScrollingFrame")
listScroll.Size = UDim2.new(1, -8, 1, -32)
listScroll.Position = UDim2.new(0, 4, 0, 26)
listScroll.BackgroundTransparency = 1
listScroll.BorderSizePixel = 0
listScroll.ScrollBarThickness = 6
listScroll.ScrollBarImageColor3 = Color3.fromRGB(80, 80, 100)
listScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
listScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
listScroll.Parent = leftFrame

local lsLayout = Instance.new("UIListLayout")
lsLayout.Padding = UDim.new(0, 3)
lsLayout.SortOrder = Enum.SortOrder.LayoutOrder
lsLayout.Parent = listScroll

-- RIGHT: property viewer
local rightFrame = Instance.new("Frame")
rightFrame.Size = UDim2.new(1, -364, 1, -140)
rightFrame.Position = UDim2.new(0, 356, 0, 88)
rightFrame.BackgroundColor3 = Color3.fromRGB(24, 24, 32)
rightFrame.BorderSizePixel = 0
rightFrame.Parent = main

local rc = Instance.new("UICorner")
rc.CornerRadius = UDim.new(0, 6)
rc.Parent = rightFrame

local rightLabel = Instance.new("TextLabel")
rightLabel.Size = UDim2.new(1, -10, 0, 20)
rightLabel.Position = UDim2.new(0, 5, 0, 4)
rightLabel.BackgroundTransparency = 1
rightLabel.Text = "🔍 Properties (klik buah dulu)"
rightLabel.TextColor3 = Color3.fromRGB(180, 200, 255)
rightLabel.Font = Enum.Font.GothamBold
rightLabel.TextSize = 11
rightLabel.TextXAlignment = Enum.TextXAlignment.Left
rightLabel.Parent = rightFrame

local propScroll = Instance.new("ScrollingFrame")
propScroll.Size = UDim2.new(1, -8, 1, -32)
propScroll.Position = UDim2.new(0, 4, 0, 26)
propScroll.BackgroundTransparency = 1
propScroll.BorderSizePixel = 0
propScroll.ScrollBarThickness = 6
propScroll.ScrollBarImageColor3 = Color3.fromRGB(80, 80, 100)
propScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
propScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
propScroll.Parent = rightFrame

local psLayout = Instance.new("UIListLayout")
psLayout.Padding = UDim.new(0, 1)
psLayout.SortOrder = Enum.SortOrder.LayoutOrder
psLayout.Parent = propScroll

-- Info bar
local infoBar = Instance.new("TextLabel")
infoBar.Size = UDim2.new(1, -16, 0, 22)
infoBar.Position = UDim2.new(0, 8, 1, -52)
infoBar.BackgroundColor3 = Color3.fromRGB(32, 32, 42)
infoBar.BorderSizePixel = 0
infoBar.Text = "  Ready."
infoBar.TextColor3 = Color3.fromRGB(180, 200, 255)
infoBar.Font = Enum.Font.Code
infoBar.TextSize = 10
infoBar.TextXAlignment = Enum.TextXAlignment.Left
infoBar.Parent = main

local ibc = Instance.new("UICorner")
ibc.CornerRadius = UDim.new(0, 4)
ibc.Parent = infoBar

-- Buttons
local btnFrame = Instance.new("Frame")
btnFrame.Size = UDim2.new(1, -16, 0, 30)
btnFrame.Position = UDim2.new(0, 8, 1, -82)
btnFrame.BackgroundTransparency = 1
btnFrame.Parent = main

local refreshBtn = Instance.new("TextButton")
refreshBtn.Size = UDim2.new(0.5, -3, 1, 0)
refreshBtn.BackgroundColor3 = Color3.fromRGB(60, 90, 130)
refreshBtn.Text = "🔄 Refresh Fruits"
refreshBtn.TextColor3 = Color3.fromRGB(230, 230, 240)
refreshBtn.Font = Enum.Font.GothamBold
refreshBtn.TextSize = 12
refreshBtn.Parent = btnFrame

local rbc = Instance.new("UICorner")
rbc.CornerRadius = UDim.new(0, 5)
rbc.Parent = refreshBtn

local copySelectedBtn = Instance.new("TextButton")
copySelectedBtn.Size = UDim2.new(0.5, -3, 1, 0)
copySelectedBtn.Position = UDim2.new(0.5, 3, 0, 0)
copySelectedBtn.BackgroundColor3 = Color3.fromRGB(90, 60, 130)
copySelectedBtn.Text = "📋 Copy Selected Fruit"
copySelectedBtn.TextColor3 = Color3.fromRGB(230, 230, 240)
copySelectedBtn.Font = Enum.Font.GothamBold
copySelectedBtn.TextSize = 12
copySelectedBtn.Parent = btnFrame

local csb = Instance.new("UICorner")
csb.CornerRadius = UDim.new(0, 5)
csb.Parent = copySelectedBtn

-- ============ ESP TOGGLE ============

espToggle.MouseButton1Click:Connect(function()
    espEnabled = not espEnabled
    if espEnabled then
        espToggle.Text = "🎯 ESP: ON"
        espToggle.BackgroundColor3 = Color3.fromRGB(40, 130, 70)
        for part, data in pairs(espParts) do
            if data.highlight then data.highlight.Enabled = true end
            if data.billboard then data.billboard.Enabled = true end
        end
    else
        espToggle.Text = "🎯 ESP: OFF"
        espToggle.BackgroundColor3 = Color3.fromRGB(60, 60, 75)
        for part, data in pairs(espParts) do
            if data.highlight then data.highlight.Enabled = false end
            if data.billboard then data.billboard.Enabled = false end
        end
    end
end)

clearEspBtn.MouseButton1Click:Connect(function()
    clearAllESP()
    espCountLbl.Text = "ESP: 0 part"
    infoBar.Text = "  🗑️ ESP cleared"
end)

task.spawn(function()
    while gui.Parent do
        task.wait(1)
        local count = 0
        for part, _ in pairs(espParts) do
            if part.Parent then count = count + 1 end
        end
        espCountLbl.Text = "ESP: " .. count .. " part"
    end
end)

-- ============ RENDER ============

local currentEntry = nil
local currentPropertyData = {}
local selectedPart = nil

local function clearScroll(scroll, classFilter)
    for _, c in ipairs(scroll:GetChildren()) do
        if not classFilter or c:IsA(classFilter) then
            c:Destroy()
        end
    end
end

local function addRow(order, name, value, type, partName, isHeader)
    local row = Instance.new("TextButton")
    row.Size = UDim2.new(1, 0, 0, isHeader and 22 or 20)
    row.BackgroundColor3 = isHeader
        and Color3.fromRGB(50, 50, 70)
        or (order % 2 == 0
            and Color3.fromRGB(30, 30, 40)
            or Color3.fromRGB(36, 36, 48))
    row.BorderSizePixel = 0
    row.LayoutOrder = order
    row.Text = ""
    row.AutoButtonColor = true
    row.Parent = propScroll

    local rc2 = Instance.new("UICorner")
    rc2.CornerRadius = UDim.new(0, 3)
    rc2.Parent = row

    local nameLbl = Instance.new("TextLabel")
    nameLbl.Size = UDim2.new(0.28, -4, 1, 0)
    nameLbl.Position = UDim2.new(0, 4, 0, 0)
    nameLbl.BackgroundTransparency = 1
    nameLbl.Text = name
    nameLbl.TextColor3 = isHeader
        and Color3.fromRGB(255, 255, 200)
        or Color3.fromRGB(220, 220, 230)
    nameLbl.Font = isHeader and Enum.Font.GothamBold or Enum.Font.Code
    nameLbl.TextSize = 10
    nameLbl.TextXAlignment = Enum.TextXAlignment.Left
    nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
    nameLbl.Parent = row

    if not isHeader then
        local valLbl = Instance.new("TextLabel")
        valLbl.Size = UDim2.new(0.32, -4, 1, 0)
        valLbl.Position = UDim2.new(0.28, 0, 0, 0)
        valLbl.BackgroundTransparency = 1
        valLbl.Text = value
        valLbl.TextColor3 = colorForType(type)
        valLbl.Font = Enum.Font.Code
        valLbl.TextSize = 10
        valLbl.TextXAlignment = Enum.TextXAlignment.Left
        valLbl.TextTruncate = Enum.TextTruncate.AtEnd
        valLbl.Parent = row

        local typeLbl = Instance.new("TextLabel")
        typeLbl.Size = UDim2.new(0.15, -4, 1, 0)
        typeLbl.Position = UDim2.new(0.60, 0, 0, 0)
        typeLbl.BackgroundTransparency = 1
        typeLbl.Text = type
        typeLbl.TextColor3 = Color3.fromRGB(150, 150, 180)
        typeLbl.Font = Enum.Font.Code
        typeLbl.TextSize = 9
        typeLbl.TextXAlignment = Enum.TextXAlignment.Left
        typeLbl.Parent = row

        local partLbl = Instance.new("TextLabel")
        partLbl.Size = UDim2.new(0.25, -4, 1, 0)
        partLbl.Position = UDim2.new(0.75, 0, 0, 0)
        partLbl.BackgroundTransparency = 1
        partLbl.Text = partName or ""
        partLbl.TextColor3 = Color3.fromRGB(180, 180, 220)
        partLbl.Font = Enum.Font.Code
        partLbl.TextSize = 9
        partLbl.TextXAlignment = Enum.TextXAlignment.Left
        partLbl.TextTruncate = Enum.TextTruncate.AtEnd
        partLbl.Parent = row
    end

    return row
end

local function renderProperties(entry)
    clearScroll(propScroll, "TextButton")
    currentPropertyData = {}

    local fruit = entry.fruit
    local model = fruit:IsA("Model") and fruit or fruit:FindFirstChildOfClass("Model")

    local order = 0
    local function no() order = order + 1 return order end

    addRow(no(), "🍎 " .. fruit.Name, "", "", "", true)

    if model then
        addRow(no(), "▸ MODEL: " .. model.Name .. " [" .. model.ClassName .. "]", "", "", "", true)
        local modelProps = readProperties(model)
        for _, p in ipairs(modelProps) do
            addRow(no(), p.name, formatValue(p.value), p.type, model.Name, false)
        end
    end

    local parts = {}
    for _, d in ipairs(fruit:GetDescendants()) do
        if d:IsA("BasePart") then table.insert(parts, d) end
    end

    for i, part in ipairs(parts) do
        local header = addRow(no(),
            "▸ PART #" .. i .. ": " .. part.Name .. " [" .. part.ClassName .. "]",
            "", "", "", true)

        local props = readProperties(part)
        table.insert(currentPropertyData, {
            part = part,
            props = props,
        })

        header.MouseButton1Click:Connect(function()
            selectedPart = part
            infoBar.Text = "  ✅ Part selected: " .. part:GetFullName()
        end)

        for _, p in ipairs(props) do
            addRow(no(), p.name, formatValue(p.value), p.type, part.Name, false)
        end
    end

    rightLabel.Text = "🔍 " .. fruit.Name .. " (" .. #parts .. " parts)"
end

local function renderList()
    clearScroll(listScroll, "TextButton")
    local fruits = getAllFruits()
    leftLabel.Text = "🍎 Fruits (" .. #fruits .. ")"

    for i, entry in ipairs(fruits) do
        -- Container per buah
        local container = Instance.new("Frame")
        container.Size = UDim2.new(1, 0, 0, 56)
        container.BackgroundColor3 = Color3.fromRGB(40, 40, 52)
        container.BorderSizePixel = 0
        container.LayoutOrder = i
        container.Parent = listScroll

        local cc = Instance.new("UICorner")
        cc.CornerRadius = UDim.new(0, 4)
        cc.Parent = container

        -- Baris 1: Nama buah (bisa diklik untuk pilih + ESP)
        local nameBtn = Instance.new("TextButton")
        nameBtn.Size = UDim2.new(1, -70, 0, 26)
        nameBtn.Position = UDim2.new(0, 4, 0, 2)
        nameBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 65)
        nameBtn.Text = entry.fruit.Name
        nameBtn.TextColor3 = Color3.fromRGB(220, 220, 230)
        nameBtn.Font = Enum.Font.GothamBold
        nameBtn.TextSize = 10
        nameBtn.TextXAlignment = Enum.TextXAlignment.Left
        nameBtn.TextTruncate = Enum.TextTruncate.AtEnd
        nameBtn.AutoButtonColor = true
        nameBtn.Parent = container

        local nbc = Instance.new("UICorner")
        nbc.CornerRadius = UDim.new(0, 3)
        nbc.Parent = nameBtn

        -- Tombol COPY per buah
        local copyBtn = Instance.new("TextButton")
        copyBtn.Size = UDim2.new(0, 62, 0, 26)
        copyBtn.Position = UDim2.new(1, -66, 0, 2)
        copyBtn.BackgroundColor3 = Color3.fromRGB(90, 60, 130)
        copyBtn.Text = "📋 COPY"
        copyBtn.TextColor3 = Color3.fromRGB(240, 230, 255)
        copyBtn.Font = Enum.Font.GothamBold
        copyBtn.TextSize = 10
        copyBtn.Parent = container

        local cbc2 = Instance.new("UICorner")
        cbc2.CornerRadius = UDim.new(0, 3)
        cbc2.Parent = copyBtn

        -- Baris 2: info part count
        local infoLbl = Instance.new("TextLabel")
        infoLbl.Size = UDim2.new(1, -8, 0, 20)
        infoLbl.Position = UDim2.new(0, 4, 0, 32)
        infoLbl.BackgroundTransparency = 1

        local partCount = 0
        for _, d in ipairs(entry.fruit:GetDescendants()) do
            if d:IsA("BasePart") then partCount = partCount + 1 end
        end

        infoLbl.Text = string.format("%d parts | %s", partCount, entry.fruit.ClassName)
        infoLbl.TextColor3 = Color3.fromRGB(150, 200, 255)
        infoLbl.Font = Enum.Font.Code
        infoLbl.TextSize = 9
        infoLbl.TextXAlignment = Enum.TextXAlignment.Left
        infoLbl.Parent = container

        -- Klik nama = pilih + render properties + ESP
        nameBtn.MouseButton1Click:Connect(function()
            currentEntry = entry
            renderProperties(entry)

            local count = 0
            for _, d in ipairs(entry.fruit:GetDescendants()) do
                if d:IsA("BasePart") then
                    local labelText = string.format("%s\n%s\n%.2f, %.2f, %.2f",
                        entry.fruit.Name, d.Name,
                        d.Size.X, d.Size.Y, d.Size.Z)
                    createESP(d, labelText)
                    if not espEnabled then
                        local data = espParts[d]
                        if data then
                            if data.highlight then data.highlight.Enabled = false end
                            if data.billboard then data.billboard.Enabled = false end
                        end
                    end
                    count = count + 1
                end
            end

            infoBar.Text = string.format("  🎯 %s | %d part di-ESP", entry.fruit.Name, count)
        end)

        -- Klik COPY = copy dump buah ini
        copyBtn.MouseButton1Click:Connect(function()
            local text = buildFruitDump(entry)
            local ok = copyToClipboard(text)

            local orig = copyBtn.Text
            local origColor = copyBtn.BackgroundColor3
            if ok then
                copyBtn.Text = "✅"
                copyBtn.BackgroundColor3 = Color3.fromRGB(40, 130, 70)
                infoBar.Text = "  ✅ Copied: " .. entry.fruit.Name
            else
                copyBtn.Text = "⚠️"
                copyBtn.BackgroundColor3 = Color3.fromRGB(180, 130, 40)
                infoBar.Text = "  ⚠️ Gagal copy, cek console"
            end
            task.delay(1.2, function()
                if copyBtn and copyBtn.Parent then
                    copyBtn.Text = orig
                    copyBtn.BackgroundColor3 = origColor
                end
            end)
        end)
    end
end

-- ============ EVENTS ============

refreshBtn.MouseButton1Click:Connect(function()
    renderList()
    if currentEntry then renderProperties(currentEntry) end
end)

copySelectedBtn.MouseButton1Click:Connect(function()
    if not currentEntry then
        copySelectedBtn.Text = "⚠️ Pilih buah dulu"
        task.delay(1.5, function() copySelectedBtn.Text = "📋 Copy Selected Fruit" end)
        return
    end

    local text = buildFruitDump(currentEntry)
    local ok = copyToClipboard(text)

    local orig = copySelectedBtn.Text
    local origColor = copySelectedBtn.BackgroundColor3
    if ok then
        copySelectedBtn.Text = "✅ Copied!"
        copySelectedBtn.BackgroundColor3 = Color3.fromRGB(40, 130, 70)
    else
        copySelectedBtn.Text = "⚠️ See console"
        copySelectedBtn.BackgroundColor3 = Color3.fromRGB(180, 130, 40)
    end
    task.delay(1.5, function()
        if copySelectedBtn and copySelectedBtn.Parent then
            copySelectedBtn.Text = orig
            copySelectedBtn.BackgroundColor3 = origColor
        end
    end)
end)

-- ============ INIT ============

renderList()

task.spawn(function()
    while gui.Parent do
        task.wait(5)
        if gui.Parent then renderList() end
    end
end)

print("✅ Fruit Scanner + ESP + Per-Fruit Copy loaded")
print("Klik nama buah → ESP + properties")
print("Klik 📋 COPY per buah → copy dump buah itu saja")
