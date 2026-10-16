--// ============================================================
-- RAW DUMP — Semua Attribute, Property, Children, Tags
-- Tanpa filter, tanpa deteksi, mentah-mentah
-- ============================================================

local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local CollectionService = game:GetService("CollectionService")

local LP = Players.LocalPlayer

--// ============================================================
-- GUI
-- ============================================================
local oldGui = CoreGui:FindFirstChild("RawDumpGui")
if oldGui then oldGui:Destroy() end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "RawDumpGui"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent = CoreGui

local Main = Instance.new("Frame")
Main.Size = UDim2.new(0, 700, 0, 560)
Main.Position = UDim2.new(0.5, -350, 0.5, -280)
Main.BackgroundColor3 = Color3.fromRGB(28, 28, 34)
Main.BorderSizePixel = 0
Main.Active = true
Main.Draggable = true
Main.Parent = ScreenGui

local MainCorner = Instance.new("UICorner")
MainCorner.CornerRadius = UDim.new(0, 8)
MainCorner.Parent = Main

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, 0, 0, 32)
Title.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
Title.BorderSizePixel = 0
Title.Text = "  🔬 RAW Dump — Attribute + Property + Children"
Title.TextColor3 = Color3.fromRGB(255, 255, 255)
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Font = Enum.Font.GothamBold
Title.TextSize = 14
Title.Parent = Main

local TitleCorner = Instance.new("UICorner")
TitleCorner.CornerRadius = UDim.new(0, 8)
TitleCorner.Parent = Title

--// Status
local StatusLabel = Instance.new("TextLabel")
StatusLabel.Size = UDim2.new(1, -16, 0, 20)
StatusLabel.Position = UDim2.new(0, 8, 0, 36)
StatusLabel.BackgroundTransparency = 1
StatusLabel.Text = "Ready."
StatusLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
StatusLabel.TextXAlignment = Enum.TextXAlignment.Left
StatusLabel.Font = Enum.Font.Gotham
StatusLabel.TextSize = 11
StatusLabel.Parent = Main

--// Scroll
local Scroll = Instance.new("ScrollingFrame")
Scroll.Size = UDim2.new(1, -16, 1, -110)
Scroll.Position = UDim2.new(0, 8, 0, 60)
Scroll.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
Scroll.BorderSizePixel = 0
Scroll.ScrollBarThickness = 6
Scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
Scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
Scroll.Parent = Main

local ScrollCorner = Instance.new("UICorner")
ScrollCorner.CornerRadius = UDim.new(0, 6)
ScrollCorner.Parent = Scroll

local UIListLayout = Instance.new("UIListLayout")
UIListLayout.Padding = UDim.new(0, 1)
UIListLayout.SortOrder = Enum.SortOrder.LayoutOrder
UIListLayout.Parent = Scroll

local UIPadding = Instance.new("UIPadding")
UIPadding.PaddingTop = UDim.new(0, 6)
UIPadding.PaddingLeft = UDim.new(0, 8)
UIPadding.PaddingRight = UDim.new(0, 8)
UIPadding.PaddingBottom = UDim.new(0, 6)
UIPadding.Parent = Scroll

--// Log storage
local fullLog = ""

local function addLog(text, color)
    color = color or Color3.fromRGB(200, 200, 200)
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, 0, 0, 0)
    label.AutomaticSize = Enum.AutomaticSize.Y
    label.BackgroundTransparency = 1
    label.Text = text
    label.TextColor3 = color
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.TextYAlignment = Enum.TextYAlignment.Top
    label.Font = Enum.Font.Code
    label.TextSize = 11
    label.TextWrapped = true
    label.Parent = Scroll
    fullLog = fullLog .. text .. "\n"
end

local function clearLogs()
    for _, v in ipairs(Scroll:GetChildren()) do
        if v:IsA("TextLabel") then v:Destroy() end
    end
    fullLog = ""
end

--// ============================================================
-- HELPER
-- ============================================================
local function formatRaw(v)
    local t = typeof(v)
    if t == "Instance" then
        return "Instance<" .. v.ClassName .. "> " .. v:GetFullName()
    elseif t == "EnumItem" then
        return "Enum." .. tostring(v.EnumType):gsub("Enum%.", "") .. "." .. v.Name
    elseif t == "Vector3" then
        return string.format("Vector3(%.4f, %.4f, %.4f)", v.X, v.Y, v.Z)
    elseif t == "Vector2" then
        return string.format("Vector2(%.4f, %.4f)", v.X, v.Y)
    elseif t == "CFrame" then
        local p = v.Position
        return string.format("CFrame(%.4f, %.4f, %.4f)", p.X, p.Y, p.Z)
    elseif t == "Color3" then
        return string.format("Color3(%d, %d, %d)", v.R*255, v.G*255, v.B*255)
    elseif t == "table" then
        local parts = {}
        for k, val in pairs(v) do
            table.insert(parts, tostring(k) .. "=" .. tostring(val))
        end
        return "{" .. table.concat(parts, ", ") .. "}"
    end
    return tostring(v)
end

local function getTypeName(v)
    local t = typeof(v)
    if t == "Instance" then return "Instance<" .. v.ClassName .. ">" end
    if t == "EnumItem" then return "EnumItem" end
    return t
end

local function typeColor(t)
    if t:find("^number") then return Color3.fromRGB(255, 215, 0) end
    if t:find("^string") then return Color3.fromRGB(120, 255, 120) end
    if t:find("^boolean") then return Color3.fromRGB(255, 130, 220) end
    if t:find("^Vector") then return Color3.fromRGB(100, 220, 255) end
    if t:find("^CFrame") then return Color3.fromRGB(150, 180, 255) end
    if t:find("^Color3") then return Color3.fromRGB(255, 150, 150) end
    if t:find("^Instance") then return Color3.fromRGB(200, 150, 255) end
    if t:find("^Enum") then return Color3.fromRGB(255, 200, 120) end
    return Color3.fromRGB(200, 200, 200)
end

--// ============================================================
-- INTERESTING PROPERTIES
-- ============================================================
local INTERESTING_PROPS = {
    "Name", "ClassName",
    "TextureId", "MeshId", "SoundId", "Image",
    "ToolTip", "Grip",
    "CanBeDropped", "RequiresHandle",
    "Enabled", "ManualActivationOnly",
}

--// ============================================================
-- DUMP TOOL
-- ============================================================
local function dumpTool(tool, index, total)
    local attrs = tool:GetAttributes()
    local tags = CollectionService:GetTags(tool)
    local children = tool:GetChildren()

    addLog("═══════════════════════════════════════════════════════", Color3.fromRGB(80, 80, 80))
    addLog(string.format("[%d/%d] 📦 %s", index, total, tool.Name), Color3.fromRGB(255, 215, 0))
    addLog(string.format("    ClassName: %s", tool.ClassName), Color3.fromRGB(180, 180, 180))
    addLog("", nil)

    -- 1. ATTRIBUTES
    local attrList = {}
    for name, value in pairs(attrs) do
        table.insert(attrList, {name = name, value = value})
    end
    table.sort(attrList, function(a, b) return a.name:lower() < b.name:lower() end)

    if #attrList > 0 then
        addLog(string.format("  🔷 ATTRIBUTES (%d):", #attrList), Color3.fromRGB(120, 200, 255))
        for _, pair in ipairs(attrList) do
            local tName = getTypeName(pair.value)
            local tColor = typeColor(tName)
            addLog(string.format("      %s = %s   <%s>",
                pair.name, formatRaw(pair.value), tName), tColor)
        end
    else
        addLog("  🔷 ATTRIBUTES: (none)", Color3.fromRGB(120, 120, 120))
    end
    addLog("", nil)

    -- 2. PROPERTIES
    addLog("  🔶 PROPERTIES (bawaan Roblox):", Color3.fromRGB(255, 200, 120))
    local propCount = 0
    for _, propName in ipairs(INTERESTING_PROPS) do
        local ok, value = pcall(function()
            return tool[propName]
        end)
        if ok and value ~= nil then
            local tName = getTypeName(value)
            local tColor = typeColor(tName)
            addLog(string.format("      %s = %s   <%s>",
                propName, formatRaw(value), tName), tColor)
            propCount = propCount + 1
        end
    end
    if propCount == 0 then
        addLog("      (tidak ada)", Color3.fromRGB(120, 120, 120))
    end
    addLog("", nil)

    -- 3. TAGS
    if #tags > 0 then
        addLog(string.format("  🏷️ TAGS (%d):", #tags), Color3.fromRGB(180, 255, 180))
        for _, tag in ipairs(tags) do
            addLog("      • " .. tag, Color3.fromRGB(180, 255, 180))
        end
    else
        addLog("  🏷️ TAGS: (none)", Color3.fromRGB(120, 120, 120))
    end
    addLog("", nil)

    -- 4. CHILDREN
    if #children > 0 then
        addLog(string.format("  👶 CHILDREN (%d):", #children), Color3.fromRGB(255, 180, 255))
        for _, child in ipairs(children) do
            local line = string.format("      • %s <%s>", child.Name, child.ClassName)

            local ok, val = pcall(function() return child.Value end)
            if ok and val ~= nil then
                line = line .. " = " .. formatRaw(val)
            end
            addLog(line, Color3.fromRGB(255, 180, 255))

            -- Attribute di child
            local childAttrs = child:GetAttributes()
            for cName, cVal in pairs(childAttrs) do
                addLog(string.format("          └─ attr: %s = %s", cName, formatRaw(cVal)),
                    Color3.fromRGB(200, 180, 255))
            end
        end
    else
        addLog("  👶 CHILDREN: (none)", Color3.fromRGB(120, 120, 120))
    end

    addLog("", nil)
end

--// ============================================================
-- RUN DUMP
-- ============================================================
local function runDump()
    clearLogs()

    addLog("═══════════════════════════════════════════════════════", Color3.fromRGB(100, 100, 100))
    addLog("🔬 RAW DUMP — SEMUA ATTRIBUTE + PROPERTY + CHILDREN", Color3.fromRGB(255, 215, 0))
    addLog("👤 Player: " .. LP.Name .. " (" .. LP.DisplayName .. ")", Color3.fromRGB(200, 200, 200))
    addLog("🕒 Time: " .. os.date("%Y-%m-%d %H:%M:%S"), Color3.fromRGB(150, 150, 150))
    addLog("═══════════════════════════════════════════════════════", Color3.fromRGB(100, 100, 100))
    addLog("", nil)

    local backpack = LP:FindFirstChildOfClass("Backpack")
    if not backpack then
        addLog("❌ Backpack tidak ditemukan!", Color3.fromRGB(255, 80, 80))
        return
    end

    local tools = {}
    for _, tool in ipairs(backpack:GetChildren()) do
        if tool:IsA("Tool") then
            table.insert(tools, tool)
        end
    end

    table.sort(tools, function(a, b) return a.Name:lower() < b.Name:lower() end)

    addLog(string.format("📦 Total tool: %d", #tools), Color3.fromRGB(120, 255, 120))
    addLog("", nil)

    for i, tool in ipairs(tools) do
        StatusLabel.Text = string.format("Dumping [%d/%d]: %s", i, #tools, tool.Name)
        dumpTool(tool, i, #tools)
        task.wait(0.01)
    end

    addLog("═══════════════════════════════════════════════════════", Color3.fromRGB(100, 100, 100))
    addLog("✅ DUMP SELESAI!", Color3.fromRGB(120, 255, 120))
    addLog(string.format("📦 Total: %d tool", #tools), Color3.fromRGB(200, 200, 200))
    addLog("💡 Klik 'Copy Logs' untuk copy semua hasil.", Color3.fromRGB(255, 215, 0))
    addLog("═══════════════════════════════════════════════════════", Color3.fromRGB(100, 100, 100))

    StatusLabel.Text = string.format("Done! %d tools dumped.", #tools)
end

--// ============================================================
-- BUTTONS (FIXED)
-- ============================================================
local function makeButton(text, x, w, color)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0, w, 0, 30)
    btn.Position = UDim2.new(0, x, 1, -38)
    btn.BackgroundColor3 = color
    btn.BorderSizePixel = 0
    btn.Text = text
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 11
    btn.Parent = Main
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 6)
    c.Parent = btn
    return btn
end

local DumpBtn  = makeButton("🔬 DUMP RAW",   8,   160, Color3.fromRGB(200, 130, 60))
local CopyBtn  = makeButton("📋 COPY LOGS",  176, 160, Color3.fromRGB(60, 130, 220))
local ClearBtn = makeButton("🗑️ CLEAR",      344, 120, Color3.fromRGB(200, 70, 70))
local CloseBtn = makeButton("❌ CLOSE",       472, 120, Color3.fromRGB(100, 100, 120))

--// Clipboard
local function setClipboard(text)
    if setclipboard then setclipboard(text) return true end
    if toclipboard then toclipboard(text) return true end
    if Clipboard and Clipboard.set then Clipboard.set(text) return true end
    return false
end

--// Events
DumpBtn.MouseButton1Click:Connect(runDump)

CopyBtn.MouseButton1Click:Connect(function()
    if fullLog == "" then
        addLog("⚠️ Log kosong!", Color3.fromRGB(255, 200, 100))
        return
    end
    if setClipboard(fullLog) then
        CopyBtn.Text = "✅ COPIED!"
        task.wait(1.5)
        CopyBtn.Text = "📋 COPY LOGS"
    else
        addLog("❌ Clipboard tidak tersedia!", Color3.fromRGB(255, 80, 80))
    end
end)

ClearBtn.MouseButton1Click:Connect(function()
    clearLogs()
    StatusLabel.Text = "Cleared."
    addLog("🗑️ Cleared.", Color3.fromRGB(150, 150, 150))
end)

CloseBtn.MouseButton1Click:Connect(function()
    ScreenGui:Destroy()
    print("[RawDump] GUI closed.")
end)

--// Initial
addLog("👋 RAW Dump Ready!", Color3.fromRGB(120, 255, 120))
addLog("", nil)
addLog("📋 Yang di-dump:", Color3.fromRGB(255, 215, 0))
addLog("  1. 🔷 Attributes (semua, raw)", Color3.fromRGB(120, 200, 255))
addLog("  2. 🔶 Properties bawaan Roblox", Color3.fromRGB(255, 200, 120))
addLog("  3. 🏷️ Tags", Color3.fromRGB(180, 255, 180))
addLog("  4. 👶 Children + Value", Color3.fromRGB(255, 180, 255))
addLog("", nil)
addLog("💡 Klik '🔬 DUMP RAW' untuk mulai.", Color3.fromRGB(120, 200, 255))

StatusLabel.Text = "Ready. Klik DUMP RAW."

task.wait(0.5)
runDump()

print("[RawDump] ✅ Loaded!")
