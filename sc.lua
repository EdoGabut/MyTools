-- ============================================================
-- DevTools v4.1 — 5 Tools in 1 Minimalist GUI
-- Tools: Scanner | TextSearch | Viewer | PathHelper | Actions
-- Fitur: Move (Walk) to Path, Fire Prompt by Path
-- ============================================================
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

-- ===== THEME =====
local T = {
    Bg      = Color3.fromRGB(20, 20, 26),
    Panel   = Color3.fromRGB(13, 13, 17),
    Row     = Color3.fromRGB(30, 30, 38),
    RowAlt  = Color3.fromRGB(26, 26, 33),
    Accent  = Color3.fromRGB(60, 130, 200),
    Accent2 = Color3.fromRGB(120, 60, 200),
    Green   = Color3.fromRGB(80, 180, 120),
    Text    = Color3.fromRGB(240, 240, 245),
    Dim     = Color3.fromRGB(150, 150, 160),
    Warn    = Color3.fromRGB(220, 200, 120),
    Danger  = Color3.fromRGB(220, 120, 120),
    Code    = Color3.fromRGB(255, 220, 150),
    Pink    = Color3.fromRGB(220, 120, 180),
    Orange  = Color3.fromRGB(230, 140, 60),
}

-- ===== UTILS =====
local U = {}

function U.corner(p, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, r or 6)
    c.Parent = p
    return c
end

function U.pad(p, t, b, l, r)
    local x = Instance.new("UIPadding")
    x.PaddingTop = UDim.new(0, t or 0)
    x.PaddingBottom = UDim.new(0, b or 0)
    x.PaddingLeft = UDim.new(0, l or 0)
    x.PaddingRight = UDim.new(0, r or 0)
    x.Parent = p
    return x
end

function U.stroke(p, color, thickness)
    local s = Instance.new("UIStroke")
    s.Color = color or T.Accent
    s.Thickness = thickness or 1
    s.Transparency = 0.5
    s.Parent = p
    return s
end

function U.path(inst)
    if not inst then return "" end
    local parts = {}
    local node = inst
    while node and node ~= game do
        table.insert(parts, 1, node.Name)
        node = node.Parent
    end
    return "game." .. table.concat(parts, ".")
end

function U.clip(text)
    if setclipboard then setclipboard(text); return true end
    if syn and syn.setclipboard then syn.setclipboard(text); return true end
    if writefile then writefile("devtools_clip.txt", text); return true end
    return false
end

function U.resolve(pathStr)
    if not pathStr or pathStr == "" then return nil end
    pathStr = pathStr:gsub("^%s+", ""):gsub("%s+$", "")
    local segments = {}
    for seg in pathStr:gmatch("[^%.]+") do
        table.insert(segments, seg)
    end
    if #segments == 0 then return nil end

    local node
    local startIdx = 1
    if segments[1]:lower() == "game" then
        node = game
        startIdx = 2
    else
        node = game
    end

    for i = startIdx, #segments do
        if not node then return nil end
        local seg = segments[i]
        if seg == "LocalPlayer" then
            node = player
        elseif seg == "Players" and node == game then
            node = game:GetService("Players")
        elseif seg == "Workspace" and node == game then
            node = game:GetService("Workspace")
        elseif seg == "ReplicatedStorage" and node == game then
            node = game:GetService("ReplicatedStorage")
        elseif seg == "ServerStorage" and node == game then
            node = game:GetService("ServerStorage")
        elseif seg == "ServerScriptService" and node == game then
            node = game:GetService("ServerScriptService")
        elseif seg == "StarterGui" and node == game then
            node = game:GetService("StarterGui")
        elseif seg == "StarterPack" and node == game then
            node = game:GetService("StarterPack")
        elseif seg == "StarterPlayer" and node == game then
            node = game:GetService("StarterPlayer")
        elseif seg == "Lighting" and node == game then
            node = game:GetService("Lighting")
        elseif seg == "SoundService" and node == game then
            node = game:GetService("SoundService")
        elseif seg == "Chat" and node == game then
            node = game:GetService("Chat")
        elseif seg == "Teams" and node == game then
            node = game:GetService("Teams")
        else
            node = node:FindFirstChild(seg)
        end
    end
    return node
end

function U.adornee(gui)
    if not gui then return nil end
    local ad = gui.Adornee
    if ad and ad:IsA("BasePart") then return ad end
    local p = gui.Parent
    if p and p:IsA("BasePart") then return p end
    if p and p:IsA("Attachment") then
        local ap = p.Parent
        if ap and ap:IsA("BasePart") then return ap end
    end
    return nil
end

-- FIX: handle ProximityPrompt, Attachment, dan BasePart
function U.guiPos(gui)
    if not gui then return nil end
    -- ProximityPrompt / Attachment / BasePart langsung
    if gui:IsA("BasePart") then return gui.Position end
    if gui:IsA("Attachment") then return gui.WorldPosition end
    if gui:IsA("ProximityPrompt") then
        local p = gui.Parent
        if p then
            if p:IsA("BasePart") then return p.Position end
            if p:IsA("Attachment") then return p.WorldPosition end
        end
        return nil
    end
    -- GUI objects: pakai adornee
    local part = U.adornee(gui)
    if part then return part.Position end
    if gui:IsA("BillboardGui") and gui.Adornee then
        local ad = gui.Adornee
        if ad:IsA("Attachment") then return ad.WorldPosition end
        if ad:IsA("BasePart") then return ad.Position end
    end
    return nil
end

function U.getTexts(gui)
    local texts = {}
    for _, d in ipairs(gui:GetDescendants()) do
        if d:IsA("TextLabel") and d.Text ~= "" then
            table.insert(texts, d.Text)
        elseif d:IsA("TextButton") and d.Text ~= "" then
            table.insert(texts, "[Btn] " .. d.Text)
        elseif d:IsA("TextBox") and d.Text ~= "" then
            table.insert(texts, "[Box] " .. d.Text)
        end
    end
    return texts
end

function U.getProps(inst, maxCount)
    local props = {}
    local count = 0
    maxCount = maxCount or 50
    if inst.GetProperties then
        local ok, list = pcall(function() return inst:GetProperties() end)
        if ok and list then
            for _, prop in ipairs(list) do
                count += 1
                if count > maxCount then break end
                local ok2, val = pcall(function() return inst[prop] end)
                if ok2 then
                    local str
                    local t = typeof(val)
                    if t == "Vector3" then
                        str = string.format("(%.1f, %.1f, %.1f)", val.X, val.Y, val.Z)
                    elseif t == "Vector2" then
                        str = string.format("(%.1f, %.1f)", val.X, val.Y)
                    elseif t == "CFrame" then
                        str = string.format("(%.1f, %.1f, %.1f)", val.X, val.Y, val.Z)
                    elseif t == "UDim2" then
                        str = string.format("(%.2f, %d, %.2f, %d)", val.X.Scale, val.X.Offset, val.Y.Scale, val.Y.Offset)
                    elseif t == "Color3" then
                        str = string.format("RGB(%d, %d, %d)", val.R * 255, val.G * 255, val.B * 255)
                    elseif t == "Instance" then
                        str = val.Name
                    elseif t == "table" then
                        str = "{...}"
                    else
                        str = tostring(val)
                    end
                    table.insert(props, { name = prop, value = str, type = t })
                end
            end
            return props
        end
    end
    local manual = {
        "Name", "ClassName", "Position", "Size", "Rotation", "Anchored",
        "CanCollide", "Transparency", "Color", "Material", "Value",
        "Text", "TextColor3", "TextSize", "Font", "Visible", "Enabled",
        "BackgroundColor3", "BackgroundTransparency", "Image", "Adornee",
        "AlwaysOnTop", "LightInfluence", "MaxDistance", "SizeOffset",
        "StudsOffset", "ExtentsOffset", "ZIndex", "LayoutOrder",
        "ActionText", "ObjectText", "HoldDuration", "MaxActivationDistance",
        "RequiresLineOfSight", "KeyboardKeyCode", "GamepadKeyCode",
        "Style", "Exclusivity", "AutoLocalize",
    }
    for _, prop in ipairs(manual) do
        count += 1
        if count > maxCount then break end
        local ok, val = pcall(function() return inst[prop] end)
        if ok and val ~= nil then
            local str
            local t = typeof(val)
            if t == "Vector3" then
                str = string.format("(%.1f, %.1f, %.1f)", val.X, val.Y, val.Z)
            elseif t == "UDim2" then
                str = string.format("(%.2f, %d, %.2f, %d)", val.X.Scale, val.X.Offset, val.Y.Scale, val.Y.Offset)
            elseif t == "Color3" then
                str = string.format("RGB(%d, %d, %d)", val.R * 255, val.G * 255, val.B * 255)
            elseif t == "Instance" then
                str = val.Name
            elseif t == "table" then
                str = "{...}"
            else
                str = tostring(val)
            end
            table.insert(props, { name = prop, value = str, type = t })
        end
    end
    return props
end

function U.getTargetPart(inst)
    if not inst then return nil end
    if inst:IsA("BasePart") then return inst end
    local ad = U.adornee(inst)
    if ad then return ad end
    local anc = inst:FindFirstAncestorOfClass("BasePart")
    if anc then return anc end
    for _, d in ipairs(inst:GetDescendants()) do
        if d:IsA("BasePart") then return d end
    end
    return nil
end

-- ===== MAIN GUI =====
local State = {
    tabs = {},
    activeTab = nil,
    statusBar = nil,
    highlight = nil,
    walkConn = nil,
    walkThread = nil,
}

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "DevToolsV4"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = player:WaitForChild("PlayerGui")

local mainFrame = Instance.new("Frame")
mainFrame.Size = UDim2.fromOffset(440, 460)
mainFrame.Position = UDim2.fromOffset(30, 30)
mainFrame.BackgroundColor3 = T.Bg
mainFrame.BorderSizePixel = 0
mainFrame.Active = true
mainFrame.Draggable = true
mainFrame.Parent = screenGui
U.corner(mainFrame, 10)
U.stroke(mainFrame, T.Accent, 1)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -80, 0, 26)
title.Position = UDim2.new(0, 12, 0, 4)
title.BackgroundTransparency = 1
title.Text = "🛠️ DevTools v4.1"
title.TextColor3 = T.Text
title.Font = Enum.Font.GothamBold
title.TextSize = 14
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = mainFrame

local minBtn = Instance.new("TextButton")
minBtn.Size = UDim2.fromOffset(22, 22)
minBtn.Position = UDim2.new(1, -52, 0, 4)
minBtn.BackgroundColor3 = Color3.fromRGB(70, 70, 85)
minBtn.Text = "—"
minBtn.TextColor3 = T.Text
minBtn.Font = Enum.Font.GothamBold
minBtn.TextSize = 13
minBtn.BorderSizePixel = 0
minBtn.Parent = mainFrame
U.corner(minBtn, 5)

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.fromOffset(22, 22)
closeBtn.Position = UDim2.new(1, -28, 0, 4)
closeBtn.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
closeBtn.Text = "X"
closeBtn.TextColor3 = T.Text
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 12
closeBtn.BorderSizePixel = 0
closeBtn.Parent = mainFrame
U.corner(closeBtn, 5)

local tabBar = Instance.new("Frame")
tabBar.Size = UDim2.new(1, -16, 0, 28)
tabBar.Position = UDim2.new(0, 8, 0, 32)
tabBar.BackgroundColor3 = T.Panel
tabBar.BorderSizePixel = 0
tabBar.Parent = mainFrame
U.corner(tabBar, 6)

local tabScroll = Instance.new("ScrollingFrame")
tabScroll.Size = UDim2.new(1, 0, 1, 0)
tabScroll.BackgroundTransparency = 1
tabScroll.BorderSizePixel = 0
tabScroll.ScrollBarThickness = 0
tabScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
tabScroll.AutomaticCanvasSize = Enum.AutomaticSize.X
tabScroll.ScrollingDirection = Enum.ScrollingDirection.X
tabScroll.Parent = tabBar

local tabLayout = Instance.new("UIListLayout")
tabLayout.FillDirection = Enum.FillDirection.Horizontal
tabLayout.Padding = UDim.new(0, 3)
tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
tabLayout.VerticalAlignment = Enum.VerticalAlignment.Center
tabLayout.Parent = tabScroll
U.pad(tabScroll, 0, 0, 6, 6)

local content = Instance.new("Frame")
content.Size = UDim2.new(1, -16, 1, -100)
content.Position = UDim2.new(0, 8, 0, 66)
content.BackgroundColor3 = T.Panel
content.BorderSizePixel = 0
content.Parent = mainFrame
U.corner(content, 6)

local statusBar = Instance.new("TextLabel")
statusBar.Size = UDim2.new(1, -16, 0, 20)
statusBar.Position = UDim2.new(0, 8, 1, -26)
statusBar.BackgroundColor3 = T.Panel
statusBar.BorderSizePixel = 0
statusBar.Text = "  Ready."
statusBar.TextColor3 = T.Dim
statusBar.Font = Enum.Font.Code
statusBar.TextSize = 10
statusBar.TextXAlignment = Enum.TextXAlignment.Left
statusBar.Parent = mainFrame
U.corner(statusBar, 4)

function State.status(text, color)
    statusBar.Text = "  " .. text
    statusBar.TextColor3 = color or T.Dim
end

function State.highlightObject(inst)
    if State.highlight then
        pcall(function() State.highlight:Destroy() end)
        State.highlight = nil
    end
    if not inst then return end
    local part = inst
    if not part:IsA("BasePart") then
        part = U.adornee(inst) or inst:FindFirstAncestorOfClass("BasePart")
    end
    if not part or not part:IsA("BasePart") then return end
    local hl = Instance.new("Highlight")
    hl.FillColor = T.Accent
    hl.OutlineColor = T.Accent2
    hl.FillTransparency = 0.5
    hl.OutlineTransparency = 0
    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    hl.Adornee = part
    hl.Parent = workspace
    State.highlight = hl
    task.delay(5, function()
        if State.highlight == hl then
            pcall(function() hl:Destroy() end)
            State.highlight = nil
        end
    end)
end

function State.stopWalk()
    if State.walkConn then
        pcall(function() State.walkConn:Disconnect() end)
        State.walkConn = nil
    end
    State.walkThread = nil
    local char = player.Character
    if char then
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum then
            pcall(function() hum:MoveTo(hum.RootPart and hum.RootPart.Position or Vector3.new()) end)
        end
    end
end

function State.walkTo(targetPart)
    State.stopWalk()
    local char = player.Character
    if not char then State.status("❌ Karakter tidak ada.", T.Danger); return false end
    local hum = char:FindFirstChildOfClass("Humanoid")
    local root = char:FindFirstChild("HumanoidRootPart")
    if not hum or not root then State.status("❌ Humanoid/Root tidak ada.", T.Danger); return false end
    if not targetPart or not targetPart:IsA("BasePart") then
        State.status("❌ Target bukan BasePart.", T.Danger); return false
    end

    local goalPos = targetPart.Position
    local offsetDist = math.max(targetPart.Size.Magnitude / 2, 3)
    local dir = (root.Position - goalPos)
    dir = Vector3.new(dir.X, 0, dir.Z)
    if dir.Magnitude > 0 then
        dir = dir.Unit
    else
        dir = Vector3.new(0, 0, 1)
    end
    local dest = goalPos + dir * offsetDist

    State.status("🚶 Walking to " .. targetPart.Name .. "...", T.Green)

    local PathfindingService = game:GetService("PathfindingService")
    local ok, path = pcall(function()
        local p = PathfindingService:CreatePath({
            AgentRadius = 2,
            AgentHeight = 5,
            AgentCanJump = true,
        })
        p:ComputeAsync(root.Position, dest)
        return p
    end)

    State.walkThread = task.spawn(function()
        if ok and path and path.Status == Enum.PathStatus.Success then
            local waypoints = path:GetWaypoints()
            for i, wp in ipairs(waypoints) do
                if State.walkThread ~= coroutine.running() then return end
                if not char.Parent or not hum.Parent then return end
                hum:MoveTo(wp.Position)
                if wp.Action == Enum.PathWaypointAction.Jump then
                    hum.Jump = true
                end
                local t0 = tick()
                while (root.Position - wp.Position).Magnitude > 3 do
                    if State.walkThread ~= coroutine.running() then return end
                    if not char.Parent or not hum.Parent then return end
                    if tick() - t0 > 5 then break end
                    task.wait(0.1)
                end
            end
            State.status("✅ Sampai tujuan!", T.Green)
        else
            State.status("⚠ Pathfinding gagal, MoveTo langsung.", T.Warn)
            hum:MoveTo(dest)
            local t0 = tick()
            while (root.Position - dest).Magnitude > 4 do
                if State.walkThread ~= coroutine.running() then return end
                if not char.Parent or not hum.Parent then return end
                if tick() - t0 > 15 then break end
                task.wait(0.1)
            end
            State.status("✅ Selesai (fallback).", T.Green)
        end
    end)

    return true
end

local minimized = false
minBtn.MouseButton1Click:Connect(function()
    minimized = not minimized
    content.Visible = not minimized
    tabBar.Visible = not minimized
    statusBar.Visible = not minimized
    mainFrame.Size = minimized and UDim2.fromOffset(440, 32) or UDim2.fromOffset(440, 460)
end)

closeBtn.MouseButton1Click:Connect(function()
    State.stopWalk()
    screenGui:Destroy()
end)

function State.addTab(name, icon)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.fromOffset(0, 22)
    btn.AutomaticSize = Enum.AutomaticSize.X
    btn.BackgroundColor3 = T.Bg
    btn.Text = " " .. icon .. " " .. name .. " "
    btn.TextColor3 = T.Dim
    btn.Font = Enum.Font.GothamMedium
    btn.TextSize = 11
    btn.BorderSizePixel = 0
    btn.Parent = tabScroll
    U.corner(btn, 4)
    U.pad(btn, 0, 0, 6, 6)

    local container = Instance.new("Frame")
    container.Size = UDim2.new(1, 0, 1, 0)
    container.BackgroundTransparency = 1
    container.Visible = false
    container.Parent = content

    State.tabs[name] = { button = btn, container = container }

    btn.MouseButton1Click:Connect(function()
        State.selectTab(name)
    end)

    return container
end

function State.selectTab(name)
    for tabName, tab in pairs(State.tabs) do
        local active = (tabName == name)
        tab.container.Visible = active
        tab.button.BackgroundColor3 = active and T.Accent or T.Bg
        tab.button.TextColor3 = active and T.Text or T.Dim
    end
    State.activeTab = name
end

-- ===== Result Row =====
local function buildResultRow(scroll, icon, mainText, subText, copyText, inst)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, -4, 0, 0)
    row.AutomaticSize = Enum.AutomaticSize.Y
    row.BackgroundColor3 = T.Row
    row.BorderSizePixel = 0
    row.Parent = scroll
    U.corner(row, 6)
    U.pad(row, 5, 5, 8, 58)

    local rl = Instance.new("UIListLayout")
    rl.Padding = UDim.new(0, 2)
    rl.Parent = row

    local tLbl = Instance.new("TextLabel")
    tLbl.Size = UDim2.new(1, 0, 0, 0)
    tLbl.AutomaticSize = Enum.AutomaticSize.Y
    tLbl.BackgroundTransparency = 1
    tLbl.Text = icon .. " " .. mainText
    tLbl.TextColor3 = T.Code
    tLbl.Font = Enum.Font.GothamMedium
    tLbl.TextSize = 11
    tLbl.TextXAlignment = Enum.TextXAlignment.Left
    tLbl.TextWrapped = true
    tLbl.Parent = row

    if subText and subText ~= "" then
        local pLbl = Instance.new("TextLabel")
        pLbl.Size = UDim2.new(1, 0, 0, 0)
        pLbl.AutomaticSize = Enum.AutomaticSize.Y
        pLbl.BackgroundTransparency = 1
        pLbl.Text = subText
        pLbl.TextColor3 = T.Dim
        pLbl.Font = Enum.Font.Code
        pLbl.TextSize = 9
        pLbl.TextXAlignment = Enum.TextXAlignment.Left
        pLbl.TextWrapped = true
        pLbl.Parent = row
    end

    local cp = Instance.new("TextButton")
    cp.Size = UDim2.fromOffset(24, 24)
    cp.Position = UDim2.new(1, -52, 0, 4)
    cp.BackgroundColor3 = T.Accent2
    cp.Text = "📋"
    cp.TextColor3 = T.Text
    cp.Font = Enum.Font.GothamBold
    cp.TextSize = 11
    cp.BorderSizePixel = 0
    cp.Parent = row
    U.corner(cp, 5)

    cp.MouseButton1Click:Connect(function()
        if U.clip(copyText) then
            State.status("📋 Copied", T.Green)
        end
    end)

    if inst then
        local ip = Instance.new("TextButton")
        ip.Size = UDim2.fromOffset(24, 24)
        ip.Position = UDim2.new(1, -26, 0, 4)
        ip.BackgroundColor3 = T.Accent
        ip.Text = "🔎"
        ip.TextColor3 = T.Text
        ip.Font = Enum.Font.GothamBold
        ip.TextSize = 11
        ip.BorderSizePixel = 0
        ip.Parent = row
        U.corner(ip, 5)

        ip.MouseButton1Click:Connect(function()
            State.highlightObject(inst)
            State.status("🔎 Highlighted: " .. inst.Name, T.Accent)
        end)
    end

    return row
end

-- ============================================================
-- TOOL 1: SCANNER (FIXED PROMPT)
-- ============================================================
local function buildScanner(container)
    local scanMode = "object"
    local lastResult = nil
    local isScanning = false

    local modeRow = Instance.new("Frame")
    modeRow.Size = UDim2.new(1, -16, 0, 26)
    modeRow.Position = UDim2.new(0, 8, 0, 6)
    modeRow.BackgroundTransparency = 1
    modeRow.Parent = container

    local modeLayout = Instance.new("UIListLayout")
    modeLayout.FillDirection = Enum.FillDirection.Horizontal
    modeLayout.Padding = UDim.new(0, 3)
    modeLayout.Parent = modeRow

    local modes = {
        { key = "object",    label = "📦 Obj" },
        { key = "prompt",    label = "🎯 Prompt" },
        { key = "billboard", label = "📺 BB" },
        { key = "surface",   label = "🖼️ Surf" },
        { key = "textlabel", label = "📝 Text" },
    }

    local modeBtns = {}
    for _, m in ipairs(modes) do
        local b = Instance.new("TextButton")
        b.Size = UDim2.fromOffset(0, 24)
        b.AutomaticSize = Enum.AutomaticSize.X
        b.BackgroundColor3 = (m.key == "object") and T.Accent or Color3.fromRGB(60, 60, 75)
        b.Text = " " .. m.label .. " "
        b.TextColor3 = T.Text
        b.Font = Enum.Font.GothamBold
        b.TextSize = 10
        b.BorderSizePixel = 0
        b.Parent = modeRow
        U.corner(b, 5)
        U.pad(b, 0, 0, 4, 4)
        modeBtns[m.key] = b

        b.MouseButton1Click:Connect(function()
            scanMode = m.key
            lastResult = nil
            for k, btn in pairs(modeBtns) do
                btn.BackgroundColor3 = (k == scanMode) and T.Accent or Color3.fromRGB(60, 60, 75)
            end
            State.status("Mode: " .. m.label, T.Accent)
        end)
    end

    local actionRow = Instance.new("Frame")
    actionRow.Size = UDim2.new(1, -16, 0, 30)
    actionRow.Position = UDim2.new(0, 8, 0, 36)
    actionRow.BackgroundTransparency = 1
    actionRow.Parent = container

    local actionLayout = Instance.new("UIListLayout")
    actionLayout.FillDirection = Enum.FillDirection.Horizontal
    actionLayout.Padding = UDim.new(0, 4)
    actionLayout.Parent = actionRow

    local scanBtn = Instance.new("TextButton")
    scanBtn.Size = UDim2.new(0.5, -2, 1, 0)
    scanBtn.BackgroundColor3 = T.Accent
    scanBtn.Text = "🔍 Scan"
    scanBtn.TextColor3 = T.Text
    scanBtn.Font = Enum.Font.GothamBold
    scanBtn.TextSize = 12
    scanBtn.BorderSizePixel = 0
    scanBtn.Parent = actionRow
    U.corner(scanBtn, 6)

    local copyBtn = Instance.new("TextButton")
    copyBtn.Size = UDim2.new(0.25, -3, 1, 0)
    copyBtn.BackgroundColor3 = T.Accent2
    copyBtn.Text = "📋 Copy"
    copyBtn.TextColor3 = T.Text
    copyBtn.Font = Enum.Font.GothamBold
    copyBtn.TextSize = 11
    copyBtn.BorderSizePixel = 0
    copyBtn.Parent = actionRow
    U.corner(copyBtn, 6)

    local hlBtn = Instance.new("TextButton")
    hlBtn.Size = UDim2.new(0.25, -3, 1, 0)
    hlBtn.BackgroundColor3 = T.Pink
    hlBtn.Text = "✨ HL"
    hlBtn.TextColor3 = T.Text
    hlBtn.Font = Enum.Font.GothamBold
    hlBtn.TextSize = 11
    hlBtn.BorderSizePixel = 0
    hlBtn.Parent = actionRow
    U.corner(hlBtn, 6)

    local pathBox = Instance.new("TextBox")
    pathBox.Size = UDim2.new(1, -16, 1, -110)
    pathBox.Position = UDim2.new(0, 8, 0, 72)
    pathBox.BackgroundColor3 = T.Bg
    pathBox.Text = ""
    pathBox.PlaceholderText = "Hasil scan muncul di sini..."
    pathBox.TextColor3 = T.Code
    pathBox.PlaceholderColor3 = T.Dim
    pathBox.Font = Enum.Font.Code
    pathBox.TextSize = 10
    pathBox.TextXAlignment = Enum.TextXAlignment.Left
    pathBox.TextYAlignment = Enum.TextYAlignment.Top
    pathBox.TextWrapped = true
    pathBox.ClearTextOnFocus = false
    pathBox.MultiLine = true
    pathBox.BorderSizePixel = 0
    pathBox.Parent = container
    U.corner(pathBox, 6)
    U.pad(pathBox, 6, 6, 6, 6)

    local function getMyPos()
        local char = player.Character
        if not char then return nil end
        local root = char:FindFirstChild("HumanoidRootPart")
        return root and root.Position or nil
    end

    local function scanNearest()
        local myPos = getMyPos()
        if not myPos then
            pathBox.Text = "❌ Karakter tidak ada."
            State.status("No character", T.Warn)
            return
        end
        local char = player.Character
        local nearest, nearestDist = nil, math.huge
        local extraInfo = ""

        if scanMode == "object" then
            local i = 0
            for _, obj in ipairs(workspace:GetDescendants()) do
                i += 1
                if i % 500 == 0 then task.wait() end
                if obj:IsA("BasePart") and not obj:IsDescendantOf(char) then
                    local d = (obj.Position - myPos).Magnitude
                    if d < nearestDist then
                        nearestDist = d; nearest = obj
                    end
                end
            end
            if nearest then
                extraInfo = string.format("Class: %s\nDistance: %.1f stud\nSize: (%.1f, %.1f, %.1f)",
                    nearest.ClassName, nearestDist, nearest.Size.X, nearest.Size.Y, nearest.Size.Z)
            end

        elseif scanMode == "prompt" then
            -- FIX: ProximityPrompt tidak punya .Position langsung.
            -- Ambil posisi dari Parent (BasePart / Attachment).
            local i = 0
            for _, obj in ipairs(workspace:GetDescendants()) do
                i += 1
                if i % 500 == 0 then task.wait() end
                if obj:IsA("ProximityPrompt") then
                    local pos = U.guiPos(obj)
                    if pos then
                        local d = (pos - myPos).Magnitude
                        if d < nearestDist then nearestDist = d; nearest = obj end
                    end
                end
            end
            if nearest then
                local parent = nearest.Parent
                local parentInfo = parent and (parent.Name .. " (" .. parent.ClassName .. ")") or "nil"
                extraInfo = string.format(
                    "ActionText: %s\nObjectText: %s\nHoldDuration: %.2f\nMaxDist: %.1f\nEnabled: %s\nParent: %s\nDistance: %.1f stud",
                    nearest.ActionText,
                    nearest.ObjectText,
                    nearest.HoldDuration,
                    nearest.MaxActivationDistance,
                    tostring(nearest.Enabled),
                    parentInfo,
                    nearestDist
                )
            end

        elseif scanMode == "billboard" then
            local i = 0
            for _, obj in ipairs(workspace:GetDescendants()) do
                i += 1
                if i % 500 == 0 then task.wait() end
                if obj:IsA("BillboardGui") then
                    local pos = U.guiPos(obj)
                    if pos then
                        local d = (pos - myPos).Magnitude
                        if d < nearestDist then nearestDist = d; nearest = obj end
                    end
                end
            end
            if nearest then
                local texts = U.getTexts(nearest)
                local textStr = #texts > 0 and table.concat(texts, " | ") or "(no text)"
                extraInfo = string.format("Adornee: %s\nAlwaysOnTop: %s\nMaxDistance: %s\nSize: %s\nTexts: %s\nDistance: %.1f stud",
                    nearest.Adornee and nearest.Adornee.Name or "nil",
                    tostring(nearest.AlwaysOnTop),
                    tostring(nearest.MaxDistance),
                    tostring(nearest.Size),
                    textStr, nearestDist)
            end

        elseif scanMode == "surface" then
            local i = 0
            for _, obj in ipairs(workspace:GetDescendants()) do
                i += 1
                if i % 500 == 0 then task.wait() end
                if obj:IsA("SurfaceGui") then
                    local pos = U.guiPos(obj)
                    if pos then
                        local d = (pos - myPos).Magnitude
                        if d < nearestDist then nearestDist = d; nearest = obj end
                    end
                end
            end
            if nearest then
                local texts = U.getTexts(nearest)
                extraInfo = string.format("Adornee: %s\nFace: %s\nPixelsPerStud: %.1f\nTexts: %s\nDistance: %.1f stud",
                    nearest.Adornee and nearest.Adornee.Name or "nil",
                    tostring(nearest.Face),
                    nearest.PixelsPerStud,
                    #texts > 0 and table.concat(texts, " | ") or "(none)",
                    nearestDist)
            end

        elseif scanMode == "textlabel" then
            local i = 0
            for _, obj in ipairs(workspace:GetDescendants()) do
                i += 1
                if i % 200 == 0 then task.wait() end
                if obj:IsA("TextLabel") and obj.Text ~= "" then
                    local gui = obj:FindFirstAncestorOfClass("BillboardGui") or obj:FindFirstAncestorOfClass("SurfaceGui")
                    local pos = gui and U.guiPos(gui)
                    if pos then
                        local d = (pos - myPos).Magnitude
                        if d < nearestDist then nearestDist = d; nearest = obj end
                    end
                end
            end
            if nearest then
                local gui = nearest:FindFirstAncestorOfClass("BillboardGui") or nearest:FindFirstAncestorOfClass("SurfaceGui")
                extraInfo = string.format("Text: %s\nTextSize: %.1f\nTextColor: RGB(%d,%d,%d)\nGUI: %s\nDistance: %.1f stud",
                    nearest.Text, nearest.TextSize,
                    nearest.TextColor3.R*255, nearest.TextColor3.G*255, nearest.TextColor3.B*255,
                    gui and gui.ClassName or "nil", nearestDist)
            end
        end

        if nearest then
            lastResult = nearest
            pathBox.Text = U.path(nearest) .. "\n\n" .. extraInfo
            State.status(string.format("✅ Found @ %.1f stud", nearestDist), T.Green)
        else
            lastResult = nil
            pathBox.Text = "❌ Tidak ada " .. scanMode .. " di sekitar."
            State.status("No result", T.Warn)
        end
    end

    scanBtn.MouseButton1Click:Connect(function()
        if isScanning then return end
        isScanning = true
        scanBtn.Active = false
        scanBtn.Text = "⏳..."
        pathBox.Text = "🔍 Scanning..."
        task.wait(0.05)
        local ok, err = pcall(scanNearest)
        if not ok then
            pathBox.Text = "❌ Error: " .. tostring(err)
            State.status("Scan error", T.Danger)
        end
        isScanning = false
        scanBtn.Active = true
        scanBtn.Text = "🔍 Scan"
    end)

    copyBtn.MouseButton1Click:Connect(function()
        if not lastResult then
            State.status("Belum ada hasil.", T.Warn)
            return
        end
        if U.clip(U.path(lastResult)) then
            State.status("📋 Copied path", T.Green)
        end
    end)

    hlBtn.MouseButton1Click:Connect(function()
        if not lastResult then
            State.status("Belum ada hasil.", T.Warn)
            return
        end
        State.highlightObject(lastResult)
        State.status("✨ Highlighted", T.Accent)
    end)
end

-- ============================================================
-- TOOL 2: TEXT SEARCH
-- ============================================================
local function buildTextSearch(container)
    local results = {}
    local searchScope = "playergui"
    local isSearching = false

    local searchBox = Instance.new("TextBox")
    searchBox.Size = UDim2.new(1, -110, 0, 28)
    searchBox.Position = UDim2.new(0, 8, 0, 6)
    searchBox.BackgroundColor3 = T.Bg
    searchBox.Text = ""
    searchBox.PlaceholderText = "Cari text..."
    searchBox.TextColor3 = T.Text
    searchBox.PlaceholderColor3 = T.Dim
    searchBox.Font = Enum.Font.Code
    searchBox.TextSize = 11
    searchBox.TextXAlignment = Enum.TextXAlignment.Left
    searchBox.ClearTextOnFocus = false
    searchBox.BorderSizePixel = 0
    searchBox.Parent = container
    U.corner(searchBox, 6)
    U.pad(searchBox, 0, 0, 8, 8)

    local searchBtn = Instance.new("TextButton")
    searchBtn.Size = UDim2.fromOffset(60, 28)
    searchBtn.Position = UDim2.new(1, -100, 0, 6)
    searchBtn.BackgroundColor3 = T.Accent
    searchBtn.Text = "🔍 Cari"
    searchBtn.TextColor3 = T.Text
    searchBtn.Font = Enum.Font.GothamBold
    searchBtn.TextSize = 11
    searchBtn.BorderSizePixel = 0
    searchBtn.Parent = container
    U.corner(searchBtn, 6)

    local copyAllBtn = Instance.new("TextButton")
    copyAllBtn.Size = UDim2.fromOffset(28, 28)
    copyAllBtn.Position = UDim2.new(1, -36, 0, 6)
    copyAllBtn.BackgroundColor3 = T.Accent2
    copyAllBtn.Text = "📋"
    copyAllBtn.TextColor3 = T.Text
    copyAllBtn.Font = Enum.Font.GothamBold
    copyAllBtn.TextSize = 12
    copyAllBtn.BorderSizePixel = 0
    copyAllBtn.Parent = container
    U.corner(copyAllBtn, 6)

    local scopeRow = Instance.new("Frame")
    scopeRow.Size = UDim2.new(1, -16, 0, 22)
    scopeRow.Position = UDim2.new(0, 8, 0, 38)
    scopeRow.BackgroundTransparency = 1
    scopeRow.Parent = container

    local scopeLayout = Instance.new("UIListLayout")
    scopeLayout.FillDirection = Enum.FillDirection.Horizontal
    scopeLayout.Padding = UDim.new(0, 3)
    scopeLayout.Parent = scopeRow

    local scopes = {
        { key = "playergui", label = "🎮 PlayerGui" },
        { key = "workspace", label = "🌍 Workspace" },
        { key = "both",      label = "🌐 Both" },
    }
    local scopeBtns = {}
    for _, s in ipairs(scopes) do
        local b = Instance.new("TextButton")
        b.Size = UDim2.fromOffset(0, 20)
        b.AutomaticSize = Enum.AutomaticSize.X
        b.BackgroundColor3 = (s.key == "playergui") and T.Accent or Color3.fromRGB(60, 60, 75)
        b.Text = " " .. s.label .. " "
        b.TextColor3 = T.Text
        b.Font = Enum.Font.GothamMedium
        b.TextSize = 10
        b.BorderSizePixel = 0
        b.Parent = scopeRow
        U.corner(b, 4)
        U.pad(b, 0, 0, 4, 4)
        scopeBtns[s.key] = b

        b.MouseButton1Click:Connect(function()
            searchScope = s.key
            for k, btn in pairs(scopeBtns) do
                btn.BackgroundColor3 = (k == searchScope) and T.Accent or Color3.fromRGB(60, 60, 75)
            end
        end)
    end

    local info = Instance.new("TextLabel")
    info.Size = UDim2.new(1, -16, 0, 14)
    info.Position = UDim2.new(0, 8, 0, 64)
    info.BackgroundTransparency = 1
    info.Text = "Masukkan keyword lalu Cari."
    info.TextColor3 = T.Dim
    info.Font = Enum.Font.Gotham
    info.TextSize = 10
    info.TextXAlignment = Enum.TextXAlignment.Left
    info.Parent = container

    local scroll = Instance.new("ScrollingFrame")
    scroll.Size = UDim2.new(1, -16, 1, -88)
    scroll.Position = UDim2.new(0, 8, 0, 80)
    scroll.BackgroundColor3 = T.Bg
    scroll.BorderSizePixel = 0
    scroll.ScrollBarThickness = 6
    scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    scroll.Parent = container
    U.corner(scroll, 6)

    local layout = Instance.new("UIListLayout")
    layout.Padding = UDim.new(0, 3)
    layout.Parent = scroll
    U.pad(scroll, 5, 5, 5, 5)

    local function clearRows()
        for _, c in ipairs(scroll:GetChildren()) do
            if c:IsA("Frame") then c:Destroy() end
        end
        results = {}
    end

    local function addResult(obj)
        local path = U.path(obj)
        local kind = obj.ClassName
        local text = obj.Text
        table.insert(results, { text = text, path = path, class = kind })
        local sub = string.format("%s | %s", kind, path)
        buildResultRow(scroll, "📝", text, sub, path, obj)
    end

    local function doSearch(keyword)
        clearRows()
        if not keyword or keyword == "" then
            info.Text = "⚠ Keyword kosong."
            info.TextColor3 = T.Warn
            return
        end
        local kw = keyword:lower()
        local found = 0
        local roots = {}
        if searchScope == "playergui" or searchScope == "both" then
            table.insert(roots, player:FindFirstChild("PlayerGui"))
        end
        if searchScope == "workspace" or searchScope == "both" then
            table.insert(roots, workspace)
        end

        for _, root in ipairs(roots) do
            if root then
                local i = 0
                for _, obj in ipairs(root:GetDescendants()) do
                    i += 1
                    if i % 300 == 0 then task.wait() end
                    if (obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox"))
                        and obj.Text ~= "" and obj.Text:lower():find(kw, 1, true) then
                        addResult(obj)
                        found += 1
                    end
                end
            end
        end

        if found == 0 then
            info.Text = string.format("❌ Tidak ada hasil untuk '%s'", keyword)
            info.TextColor3 = T.Danger
            State.status("No results", T.Warn)
        else
            info.Text = string.format("✅ %d text ditemukan.", found)
            info.TextColor3 = T.Green
            State.status(string.format("%d results", found), T.Green)
        end
    end

    searchBtn.MouseButton1Click:Connect(function()
        if isSearching then return end
        isSearching = true
        searchBtn.Active = false
        searchBtn.Text = "⏳"
        task.wait(0.05)
        local ok, err = pcall(doSearch, searchBox.Text)
        if not ok then
            info.Text = "❌ Error: " .. tostring(err)
            info.TextColor3 = T.Danger
        end
        isSearching = false
        searchBtn.Active = true
        searchBtn.Text = "🔍 Cari"
    end)

    searchBox.FocusLost:Connect(function(enter)
        if enter and not isSearching then
            isSearching = true
            task.spawn(function()
                pcall(doSearch, searchBox.Text)
                isSearching = false
            end)
        end
    end)

    copyAllBtn.MouseButton1Click:Connect(function()
        if #results == 0 then
            State.status("Belum ada hasil.", T.Warn)
            return
        end
        local lines = { string.format("=== %d RESULTS ===", #results), "" }
        for i, r in ipairs(results) do
            table.insert(lines, string.format("[%d] [%s] %s", i, r.class, r.text))
            table.insert(lines, "    " .. r.path)
            table.insert(lines, "")
        end
        if U.clip(table.concat(lines, "\n")) then
            State.status(string.format("📋 Copied %d results", #results), T.Green)
        end
    end)
end

-- ============================================================
-- TOOL 3: VIEWER (Tree)
-- ============================================================
local function buildViewer(container)
    local pathBox = Instance.new("TextBox")
    pathBox.Size = UDim2.new(1, -80, 0, 28)
    pathBox.Position = UDim2.new(0, 8, 0, 6)
    pathBox.BackgroundColor3 = T.Bg
    pathBox.Text = "Workspace"
    pathBox.PlaceholderText = "Contoh: Workspace.NPCS"
    pathBox.TextColor3 = T.Code
    pathBox.PlaceholderColor3 = T.Dim
    pathBox.Font = Enum.Font.Code
    pathBox.TextSize = 11
    pathBox.TextXAlignment = Enum.TextXAlignment.Left
    pathBox.ClearTextOnFocus = false
    pathBox.BorderSizePixel = 0
    pathBox.Parent = container
    U.corner(pathBox, 6)
    U.pad(pathBox, 0, 0, 8, 8)

    local goBtn = Instance.new("TextButton")
    goBtn.Size = UDim2.fromOffset(60, 28)
    goBtn.Position = UDim2.new(1, -70, 0, 6)
    goBtn.BackgroundColor3 = T.Accent
    goBtn.Text = "➜ View"
    goBtn.TextColor3 = T.Text
    goBtn.Font = Enum.Font.GothamBold
    goBtn.TextSize = 11
    goBtn.BorderSizePixel = 0
    goBtn.Parent = container
    U.corner(goBtn, 6)

    local info = Instance.new("TextLabel")
    info.Size = UDim2.new(1, -16, 0, 14)
    info.Position = UDim2.new(0, 8, 0, 38)
    info.BackgroundTransparency = 1
    info.Text = "Masukkan path, klik View."
    info.TextColor3 = T.Dim
    info.Font = Enum.Font.Gotham
    info.TextSize = 10
    info.TextXAlignment = Enum.TextXAlignment.Left
    info.Parent = container

    local scroll = Instance.new("ScrollingFrame")
    scroll.Size = UDim2.new(1, -16, 1, -62)
    scroll.Position = UDim2.new(0, 8, 0, 54)
    scroll.BackgroundColor3 = T.Bg
    scroll.BorderSizePixel = 0
    scroll.ScrollBarThickness = 6
    scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    scroll.Parent = container
    U.corner(scroll, 6)

    local layout = Instance.new("UIListLayout")
    layout.Padding = UDim.new(0, 2)
    layout.Parent = scroll
    U.pad(scroll, 5, 5, 5, 5)

    local rootNode = nil
    local expandedSet = {}

    local function clearRows()
        for _, c in ipairs(scroll:GetChildren()) do
            if c:IsA("Frame") then c:Destroy() end
        end
    end

    local makeRow

    local function render(node, depth)
        makeRow(node, depth)
        if expandedSet[node] then
            for _, child in ipairs(node:GetChildren()) do
                render(child, depth + 1)
            end
        end
    end

    makeRow = function(inst, depth)
        local hasChildren = #inst:GetChildren() > 0
        local isExpanded = expandedSet[inst]

        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, -4, 0, 20)
        row.BackgroundColor3 = (depth % 2 == 0) and T.Row or T.RowAlt
        row.BorderSizePixel = 0
        row.Parent = scroll
        U.corner(row, 4)
        U.pad(row, 0, 0, 4 + depth * 12, 4)

        local arrow = Instance.new("TextButton")
        arrow.Size = UDim2.fromOffset(16, 16)
        arrow.Position = UDim2.new(0, 0, 0.5, -8)
        arrow.BackgroundTransparency = 1
        arrow.Text = hasChildren and (isExpanded and "▼" or "▶") or "•"
        arrow.TextColor3 = hasChildren and T.Accent or T.Dim
        arrow.Font = Enum.Font.GothamBold
        arrow.TextSize = 9
        arrow.BorderSizePixel = 0
        arrow.Parent = row

        local nameLbl = Instance.new("TextLabel")
        nameLbl.Size = UDim2.new(1, -72, 1, 0)
        nameLbl.Position = UDim2.new(0, 18, 0, 0)
        nameLbl.BackgroundTransparency = 1
        nameLbl.Text = inst.Name
        nameLbl.TextColor3 = hasChildren and T.Text or T.Code
        nameLbl.Font = Enum.Font.Code
        nameLbl.TextSize = 10
        nameLbl.TextXAlignment = Enum.TextXAlignment.Left
        nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
        nameLbl.Parent = row

        local classLbl = Instance.new("TextLabel")
        classLbl.Size = UDim2.fromOffset(64, 1)
        classLbl.Position = UDim2.new(1, -68, 0, 0)
        classLbl.BackgroundTransparency = 1
        classLbl.Text = inst.ClassName
        classLbl.TextColor3 = T.Dim
        classLbl.Font = Enum.Font.Code
        classLbl.TextSize = 8
        classLbl.TextXAlignment = Enum.TextXAlignment.Right
        classLbl.TextTruncate = Enum.TextTruncate.AtEnd
        classLbl.Parent = row

        local cpBtn = Instance.new("TextButton")
        cpBtn.Size = UDim2.fromOffset(18, 16)
        cpBtn.Position = UDim2.new(1, -20, 0.5, -8)
        cpBtn.BackgroundColor3 = T.Accent2
        cpBtn.Text = "📋"
        cpBtn.TextColor3 = T.Text
        cpBtn.Font = Enum.Font.GothamBold
        cpBtn.TextSize = 9
        cpBtn.BorderSizePixel = 0
        cpBtn.Parent = row
        U.corner(cpBtn, 4)

        cpBtn.MouseButton1Click:Connect(function()
            if U.clip(U.path(inst)) then
                State.status("📋 Copied: " .. inst.Name, T.Green)
            end
        end)

        local function toggle()
            if not hasChildren then return end
            expandedSet[inst] = not expandedSet[inst]
            clearRows()
            if rootNode then render(rootNode, 0) end
        end

        arrow.MouseButton1Click:Connect(toggle)
        nameLbl.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                toggle()
            end
        end)
    end

    local function viewPath()
        clearRows()
        expandedSet = {}
        local inst = U.resolve(pathBox.Text)
        if not inst then
            info.Text = "❌ Path tidak ditemukan: " .. pathBox.Text
            info.TextColor3 = T.Danger
            State.status("Path not found", T.Warn)
            rootNode = nil
            return
        end
        rootNode = inst
        expandedSet[inst] = false
        local childCount = #inst:GetChildren()
        info.Text = string.format("📂 %s (%s) — %d children", inst.Name, inst.ClassName, childCount)
        info.TextColor3 = T.Green
        State.status(string.format("Viewing %s", inst.Name), T.Green)
        makeRow(inst, 0)
    end

    goBtn.MouseButton1Click:Connect(function()
        pcall(viewPath)
    end)

    pathBox.FocusLost:Connect(function(enter)
        if enter then pcall(viewPath) end
    end)
end

-- ============================================================
-- TOOL 4: PATH HELPER
-- ============================================================
local function buildPathHelper(container)
    local pathBox = Instance.new("TextBox")
    pathBox.Size = UDim2.new(1, -80, 0, 28)
    pathBox.Position = UDim2.new(0, 8, 0, 6)
    pathBox.BackgroundColor3 = T.Bg
    pathBox.Text = ""
    pathBox.PlaceholderText = "Contoh: Workspace.NPCS"
    pathBox.TextColor3 = T.Code
    pathBox.PlaceholderColor3 = T.Dim
    pathBox.Font = Enum.Font.Code
    pathBox.TextSize = 11
    pathBox.TextXAlignment = Enum.TextXAlignment.Left
    pathBox.ClearTextOnFocus = false
    pathBox.BorderSizePixel = 0
    pathBox.Parent = container
    U.corner(pathBox, 6)
    U.pad(pathBox, 0, 0, 8, 8)

    local goBtn = Instance.new("TextButton")
    goBtn.Size = UDim2.fromOffset(60, 28)
    goBtn.Position = UDim2.new(1, -70, 0, 6)
    goBtn.BackgroundColor3 = T.Accent
    goBtn.Text = "🔎 Inspect"
    goBtn.TextColor3 = T.Text
    goBtn.Font = Enum.Font.GothamBold
    goBtn.TextSize = 11
    goBtn.BorderSizePixel = 0
    goBtn.Parent = container
    U.corner(goBtn, 6)

    local qaRow = Instance.new("Frame")
    qaRow.Size = UDim2.new(1, -16, 0, 24)
    qaRow.Position = UDim2.new(0, 8, 0, 38)
    qaRow.BackgroundTransparency = 1
    qaRow.Parent = container

    local qaLayout = Instance.new("UIListLayout")
    qaLayout.FillDirection = Enum.FillDirection.Horizontal
    qaLayout.Padding = UDim.new(0, 3)
    qaLayout.Parent = qaRow

    local function makeQuick(label, color, fn)
        local b = Instance.new("TextButton")
        b.Size = UDim2.fromOffset(0, 22)
        b.AutomaticSize = Enum.AutomaticSize.X
        b.BackgroundColor3 = color
        b.Text = " " .. label .. " "
        b.TextColor3 = T.Text
        b.Font = Enum.Font.GothamBold
        b.TextSize = 10
        b.BorderSizePixel = 0
        b.Parent = qaRow
        U.corner(b, 4)
        U.pad(b, 0, 0, 4, 4)
        b.MouseButton1Click:Connect(fn)
        return b
    end

    local currentInst = nil

    makeQuick("✨ HL", T.Pink, function()
        if currentInst then
            State.highlightObject(currentInst)
            State.status("✨ Highlighted", T.Accent)
        else
            State.status("Inspect dulu.", T.Warn)
        end
    end)

    makeQuick("📋 Copy", T.Accent2, function()
        if currentInst then
            if U.clip(U.path(currentInst)) then
                State.status("📋 Copied", T.Green)
            end
        end
    end)

    makeQuick("🚶 Walk", T.Green, function()
        if not currentInst then State.status("Inspect dulu.", T.Warn); return end
        local part = U.getTargetPart(currentInst)
        if part then
            State.walkTo(part)
        else
            State.status("Target bukan BasePart.", T.Warn)
        end
    end)

    makeQuick("🔥 Fire", T.Warn, function()
        if not currentInst then State.status("Inspect dulu.", T.Warn); return end
        if currentInst:IsA("ProximityPrompt") then
            local ok = pcall(function()
                if fireproximityprompt then
                    fireproximityprompt(currentInst)
                else
                    error("fireproximityprompt tidak tersedia")
                end
            end)
            if ok then
                State.status("🔥 Prompt fired", T.Green)
            else
                State.status("❌ Gagal fire prompt.", T.Danger)
            end
        else
            State.status("Bukan ProximityPrompt.", T.Warn)
        end
    end)

    local out = Instance.new("ScrollingFrame")
    out.Size = UDim2.new(1, -16, 1, -94)
    out.Position = UDim2.new(0, 8, 0, 86)
    out.BackgroundColor3 = T.Bg
    out.BorderSizePixel = 0
    out.ScrollBarThickness = 6
    out.CanvasSize = UDim2.new(0, 0, 0, 0)
    out.AutomaticCanvasSize = Enum.AutomaticSize.Y
    out.Parent = container
    U.corner(out, 6)

    local layout = Instance.new("UIListLayout")
    layout.Padding = UDim.new(0, 1)
    layout.Parent = out
    U.pad(out, 6, 6, 6, 6)

    local function clearRows()
        for _, c in ipairs(out:GetChildren()) do
            if c:IsA("TextLabel") then c:Destroy() end
        end
    end

    local function addLine(text, color)
        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, -4, 0, 0)
        lbl.AutomaticSize = Enum.AutomaticSize.Y
        lbl.BackgroundTransparency = 1
        lbl.Text = text
        lbl.TextColor3 = color or T.Text
        lbl.Font = Enum.Font.Code
        lbl.TextSize = 10
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.TextWrapped = true
        lbl.Parent = out
    end

    local function inspect()
        clearRows()
        local inst = U.resolve(pathBox.Text)
        if not inst then
            addLine("❌ Path tidak ditemukan.", T.Danger)
            currentInst = nil
            State.status("Path not found", T.Warn)
            return
        end
        currentInst = inst
        addLine("📦 " .. inst.Name, T.Accent)
        addLine("Class: " .. inst.ClassName, T.Text)
        addLine("Path: " .. U.path(inst), T.Code)
        addLine("Children: " .. #inst:GetChildren(), T.Text)
        addLine("Parent: " .. (inst.Parent and inst.Parent.Name or "nil"), T.Text)
        addLine("─────────────────────", T.Dim)
        addLine("Properties:", T.Accent)

        local props = U.getProps(inst, 60)
        for _, p in ipairs(props) do
            addLine(string.format("  %s = %s", p.name, p.value), T.Dim)
        end

        if inst:IsA("BillboardGui") or inst:IsA("SurfaceGui") then
            addLine("─────────────────────", T.Dim)
            addLine("📝 Texts:", T.Pink)
            local texts = U.getTexts(inst)
            if #texts == 0 then
                addLine("  (kosong)", T.Dim)
            else
                for i, t in ipairs(texts) do
                    addLine(string.format("  [%d] %s", i, t), T.Code)
                end
            end
        end

        State.status("Inspected: " .. inst.Name, T.Green)
    end

    goBtn.MouseButton1Click:Connect(function()
        pcall(inspect)
    end)

    pathBox.FocusLost:Connect(function(enter)
        if enter then pcall(inspect) end
    end)
end

-- ============================================================
-- TOOL 5: ACTIONS
-- ============================================================
local function buildActions(container)
    -- MOVE SECTION
    local moveLbl = Instance.new("TextLabel")
    moveLbl.Size = UDim2.new(1, -16, 0, 14)
    moveLbl.Position = UDim2.new(0, 8, 0, 6)
    moveLbl.BackgroundTransparency = 1
    moveLbl.Text = "🚶  MOVE (WALK) TO PATH"
    moveLbl.TextColor3 = T.Green
    moveLbl.Font = Enum.Font.GothamBold
    moveLbl.TextSize = 11
    moveLbl.TextXAlignment = Enum.TextXAlignment.Left
    moveLbl.Parent = container

    local moveBox = Instance.new("TextBox")
    moveBox.Size = UDim2.new(1, -16, 0, 28)
    moveBox.Position = UDim2.new(0, 8, 0, 22)
    moveBox.BackgroundColor3 = T.Bg
    moveBox.Text = ""
    moveBox.PlaceholderText = "Paste path object (BasePart)..."
    moveBox.TextColor3 = T.Code
    moveBox.PlaceholderColor3 = T.Dim
    moveBox.Font = Enum.Font.Code
    moveBox.TextSize = 11
    moveBox.TextXAlignment = Enum.TextXAlignment.Left
    moveBox.ClearTextOnFocus = false
    moveBox.BorderSizePixel = 0
    moveBox.Parent = container
    U.corner(moveBox, 6)
    U.pad(moveBox, 0, 0, 8, 8)

    local moveRow = Instance.new("Frame")
    moveRow.Size = UDim2.new(1, -16, 0, 28)
    moveRow.Position = UDim2.new(0, 8, 0, 54)
    moveRow.BackgroundTransparency = 1
    moveRow.Parent = container

    local moveLayout = Instance.new("UIListLayout")
    moveLayout.FillDirection = Enum.FillDirection.Horizontal
    moveLayout.Padding = UDim.new(0, 4)
    moveLayout.Parent = moveRow

    local moveBtn = Instance.new("TextButton")
    moveBtn.Size = UDim2.new(0.6, -2, 1, 0)
    moveBtn.BackgroundColor3 = T.Green
    moveBtn.Text = "🚶 Move (Walk)"
    moveBtn.TextColor3 = T.Text
    moveBtn.Font = Enum.Font.GothamBold
    moveBtn.TextSize = 12
    moveBtn.BorderSizePixel = 0
    moveBtn.Parent = moveRow
    U.corner(moveBtn, 6)

    local stopBtn = Instance.new("TextButton")
    stopBtn.Size = UDim2.new(0.4, -2, 1, 0)
    stopBtn.BackgroundColor3 = T.Danger
    stopBtn.Text = "⛔ Stop"
    stopBtn.TextColor3 = T.Text
    stopBtn.Font = Enum.Font.GothamBold
    stopBtn.TextSize = 12
    stopBtn.BorderSizePixel = 0
    stopBtn.Parent = moveRow
    U.corner(stopBtn, 6)

    -- FIRE PROMPT SECTION
    local fireLbl = Instance.new("TextLabel")
    fireLbl.Size = UDim2.new(1, -16, 0, 14)
    fireLbl.Position = UDim2.new(0, 8, 0, 90)
    fireLbl.BackgroundTransparency = 1
    fireLbl.Text = "🔥  FIRE PROMPT BY PATH"
    fireLbl.TextColor3 = T.Orange
    fireLbl.Font = Enum.Font.GothamBold
    fireLbl.TextSize = 11
    fireLbl.TextXAlignment = Enum.TextXAlignment.Left
    fireLbl.Parent = container

    local fireBox = Instance.new("TextBox")
    fireBox.Size = UDim2.new(1, -16, 0, 28)
    fireBox.Position = UDim2.new(0, 8, 0, 106)
    fireBox.BackgroundColor3 = T.Bg
    fireBox.Text = ""
    fireBox.PlaceholderText = "Paste path ProximityPrompt..."
    fireBox.TextColor3 = T.Code
    fireBox.PlaceholderColor3 = T.Dim
    fireBox.Font = Enum.Font.Code
    fireBox.TextSize = 11
    fireBox.TextXAlignment = Enum.TextXAlignment.Left
    fireBox.ClearTextOnFocus = false
    fireBox.BorderSizePixel = 0
    fireBox.Parent = container
    U.corner(fireBox, 6)
    U.pad(fireBox, 0, 0, 8, 8)

    local fireRow = Instance.new("Frame")
    fireRow.Size = UDim2.new(1, -16, 0, 28)
    fireRow.Position = UDim2.new(0, 8, 0, 138)
    fireRow.BackgroundTransparency = 1
    fireRow.Parent = container

    local fireLayout = Instance.new("UIListLayout")
    fireLayout.FillDirection = Enum.FillDirection.Horizontal
    fireLayout.Padding = UDim.new(0, 4)
    fireLayout.Parent = fireRow

    local fireBtn = Instance.new("TextButton")
    fireBtn.Size = UDim2.new(0.4, -2, 1, 0)
    fireBtn.BackgroundColor3 = T.Orange
    fireBtn.Text = "🔥 Fire"
    fireBtn.TextColor3 = T.Text
    fireBtn.Font = Enum.Font.GothamBold
    fireBtn.TextSize = 12
    fireBtn.BorderSizePixel = 0
    fireBtn.Parent = fireRow
    U.corner(fireBtn, 6)

    local enableBtn = Instance.new("TextButton")
    enableBtn.Size = UDim2.new(0.3, -2, 1, 0)
    enableBtn.BackgroundColor3 = T.Accent
    enableBtn.Text = "👁️ Enable"
    enableBtn.TextColor3 = T.Text
    enableBtn.Font = Enum.Font.GothamBold
    enableBtn.TextSize = 11
    enableBtn.BorderSizePixel = 0
    enableBtn.Parent = fireRow
    U.corner(enableBtn, 6)

    local infoBtn = Instance.new("TextButton")
    infoBtn.Size = UDim2.new(0.3, -2, 1, 0)
    infoBtn.BackgroundColor3 = T.Accent2
    infoBtn.Text = "ℹ️ Info"
    infoBtn.TextColor3 = T.Text
    infoBtn.Font = Enum.Font.GothamBold
    infoBtn.TextSize = 11
    infoBtn.BorderSizePixel = 0
    infoBtn.Parent = fireRow
    U.corner(infoBtn, 6)

    -- OUTPUT LOG
    local logLbl = Instance.new("TextLabel")
    logLbl.Size = UDim2.new(1, -16, 0, 14)
    logLbl.Position = UDim2.new(0, 8, 0, 174)
    logLbl.BackgroundTransparency = 1
    logLbl.Text = "📜  LOG"
    logLbl.TextColor3 = T.Dim
    logLbl.Font = Enum.Font.GothamBold
    logLbl.TextSize = 10
    logLbl.TextXAlignment = Enum.TextXAlignment.Left
    logLbl.Parent = container

    local logBox = Instance.new("ScrollingFrame")
    logBox.Size = UDim2.new(1, -16, 1, -202)
    logBox.Position = UDim2.new(0, 8, 0, 190)
    logBox.BackgroundColor3 = T.Bg
    logBox.BorderSizePixel = 0
    logBox.ScrollBarThickness = 6
    logBox.CanvasSize = UDim2.new(0, 0, 0, 0)
    logBox.AutomaticCanvasSize = Enum.AutomaticSize.Y
    logBox.Parent = container
    U.corner(logBox, 6)

    local logLayout = Instance.new("UIListLayout")
    logLayout.Padding = UDim.new(0, 1)
    logLayout.Parent = logBox
    U.pad(logBox, 6, 6, 6, 6)

    local function addLog(text, color)
        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, -4, 0, 0)
        lbl.AutomaticSize = Enum.AutomaticSize.Y
        lbl.BackgroundTransparency = 1
        lbl.Text = "» " .. text
        lbl.TextColor3 = color or T.Text
        lbl.Font = Enum.Font.Code
        lbl.TextSize = 10
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.TextWrapped = true
        lbl.Parent = logBox
    end

    moveBtn.MouseButton1Click:Connect(function()
        local path = moveBox.Text
        if path == "" then
            State.status("⚠ Path kosong.", T.Warn)
            addLog("Path kosong.", T.Warn)
            return
        end
        local inst = U.resolve(path)
        if not inst then
            State.status("❌ Path tidak ditemukan.", T.Danger)
            addLog("Path tidak ditemukan: " .. path, T.Danger)
            return
        end
        local part = U.getTargetPart(inst)
        if not part then
            State.status("❌ Target bukan BasePart.", T.Danger)
            addLog("Target bukan BasePart: " .. inst.ClassName, T.Danger)
            return
        end
        addLog(string.format("🚶 Walking to %s (%.1f, %.1f, %.1f)...",
            part.Name, part.Position.X, part.Position.Y, part.Position.Z), T.Green)
        State.walkTo(part)
    end)

    stopBtn.MouseButton1Click:Connect(function()
        State.stopWalk()
        State.status("⛔ Walk stopped.", T.Warn)
        addLog("Walk dihentikan.", T.Warn)
    end)

    fireBtn.MouseButton1Click:Connect(function()
        local path = fireBox.Text
        if path == "" then
            State.status("⚠ Path kosong.", T.Warn)
            addLog("Fire: path kosong.", T.Warn)
            return
        end
        local inst = U.resolve(path)
        if not inst then
            State.status("❌ Path tidak ditemukan.", T.Danger)
            addLog("Fire: path tidak ditemukan.", T.Danger)
            return
        end
        if not inst:IsA("ProximityPrompt") then
            State.status("❌ Bukan ProximityPrompt.", T.Danger)
            addLog("Fire: object bukan ProximityPrompt (" .. inst.ClassName .. ")", T.Danger)
            return
        end
        if type(fireproximityprompt) ~= "function" then
            State.status("❌ fireproximityprompt() tidak tersedia.", T.Danger)
            addLog("Executor tidak support fireproximityprompt().", T.Danger)
            return
        end
        local ok, err = pcall(function()
            fireproximityprompt(inst)
        end)
        if ok then
            State.status("🔥 Prompt fired!", T.Green)
            addLog("🔥 Fired: " .. inst.Name .. " | Action: " .. inst.ActionText, T.Green)
        else
            State.status("❌ Gagal fire prompt.", T.Danger)
            addLog("Gagal fire: " .. tostring(err), T.Danger)
        end
    end)

    enableBtn.MouseButton1Click:Connect(function()
        local path = fireBox.Text
        if path == "" then return end
        local inst = U.resolve(path)
        if inst and inst:IsA("ProximityPrompt") then
            inst.Enabled = true
            inst.MaxActivationDistance = 10000
            State.status("👁️ Prompt enabled.", T.Green)
            addLog("Prompt di-enable (MaxDist=10000).", T.Green)
        else
            State.status("❌ Bukan ProximityPrompt.", T.Warn)
        end
    end)

    infoBtn.MouseButton1Click:Connect(function()
        local path = fireBox.Text
        if path == "" then return end
        local inst = U.resolve(path)
        if not inst then
            addLog("Info: path tidak ditemukan.", T.Danger)
            return
        end
        if inst:IsA("ProximityPrompt") then
            addLog("─── PROMPT INFO ───", T.Accent)
            addLog("Name: " .. inst.Name, T.Text)
            addLog("Path: " .. U.path(inst), T.Code)
            addLog("ActionText: " .. inst.ActionText, T.Code)
            addLog("ObjectText: " .. inst.ObjectText, T.Code)
            addLog("HoldDuration: " .. tostring(inst.HoldDuration), T.Text)
            addLog("MaxActivationDistance: " .. tostring(inst.MaxActivationDistance), T.Text)
            addLog("Enabled: " .. tostring(inst.Enabled), T.Text)
            addLog("RequiresLineOfSight: " .. tostring(inst.RequiresLineOfSight), T.Text)
            addLog("KeyboardKeyCode: " .. tostring(inst.KeyboardKeyCode), T.Text)
            addLog("Style: " .. tostring(inst.Style), T.Text)
            addLog("Exclusivity: " .. tostring(inst.Exclusivity), T.Text)
            addLog("Parent: " .. (inst.Parent and inst.Parent.Name or "nil"), T.Text)
        else
            addLog("Bukan ProximityPrompt (" .. inst.ClassName .. ")", T.Warn)
        end
    end)

    addLog("Actions tab siap.", T.Dim)
    addLog("1. Paste path → klik Move (Walk)", T.Dim)
    addLog("2. Paste path prompt → klik Fire", T.Dim)
end

-- ============================================================
-- REGISTER TABS (5 tab — BBoard dihapus)
-- ============================================================
State.addTab("Scan", "🎯")
State.addTab("Text", "🔍")
State.addTab("Tree", "🌳")
State.addTab("Path", "🧭")
State.addTab("Actions", "⚡")

buildScanner(State.tabs["Scan"].container)
buildTextSearch(State.tabs["Text"].container)
buildViewer(State.tabs["Tree"].container)
buildPathHelper(State.tabs["Path"].container)
buildActions(State.tabs["Actions"].container)

State.selectTab("Actions")
State.status("Ready. DevTools v4.1 loaded.", T.Green)

-- ===== HOTKEY: RightCtrl = toggle GUI =====
local guiVisible = true
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == Enum.KeyCode.RightControl then
        guiVisible = not guiVisible
        mainFrame.Visible = guiVisible
    end
end)
