--// ============================================================
-- EGG SCANNER + AUTO FARM + SPEED 250 + NOCLIP + FAST PROMPT
-- Sort: BRACKET rank → LUCK tertinggi → score
-- List: 10 row kelihatan, sisanya scroll
-- FAST PROMPT: PromptAnchor auto HoldDuration = 0 (pasif)
-- ============================================================

--// ==== FAST PROMPT (langsung aktif, tanpa button) ====
do
    if not game:IsLoaded() then
        game.Loaded:Wait()
    end

    local ProximityPromptService = game:GetService("ProximityPromptService")
    local processed = setmetatable({}, {__mode = "k"})

    local function FastPrompt(prompt)
        if processed[prompt] then return end
        processed[prompt] = true
        prompt.HoldDuration = 0
    end

    local function ProcessAnchor(anchor)
        for _, obj in ipairs(anchor:GetDescendants()) do
            if obj:IsA("ProximityPrompt") then
                FastPrompt(obj)
            end
        end
    end

    ProximityPromptService.PromptShown:Connect(function(prompt)
        if prompt.HoldDuration ~= 0 then
            prompt.HoldDuration = 0
        end
    end)

    task.spawn(function()
        for _, obj in ipairs(workspace:GetChildren()) do
            if obj.Name == "PromptAnchor" then
                ProcessAnchor(obj)
            end
        end
    end)

    workspace.ChildAdded:Connect(function(child)
        if child.Name == "PromptAnchor" then
            task.defer(ProcessAnchor, child)
        end
    end)

    workspace.DescendantAdded:Connect(function(desc)
        if desc:IsA("ProximityPrompt") and desc.Parent and desc.Parent.Name == "PromptAnchor" then
            FastPrompt(desc)
        end
    end)

    print("✅ FAST PROMPT LOADED! (PromptAnchor only)")
end

--// ==== SERVICES ====
local Players    = game:GetService("Players")
local CoreGui    = game:GetService("CoreGui")
local RunService = game:GetService("RunService")

local LP = Players.LocalPlayer

--// ==== CONFIG ====
local TARGET_PATH       = "game.Workspace.Build.ZoneBuilds.Zone10.Eggs"
local SCAN_INTERVAL     = 0.5
local AGE_WARN_SECONDS  = 300
local NEAR_DISTANCE     = 15
local ESP_MAX_DISTANCE  = 2000
local AUTO_STOP_DIST    = 6
local AUTO_TICK         = 0.3

local PRESET_SPEED      = 250
local ROW_HEIGHT        = 20
local VISIBLE_ROWS      = 10
local LIST_HEIGHT       = ROW_HEIGHT * VISIBLE_ROWS + 6

local BRACKET_RANK = { TITANIC = 4, HUGE = 3, BIG = 2, ["—"] = 1, [""] = 1 }

--// ==== HELPERS ====
local function resolvePath(pathStr)
    local segs = {}
    for s in pathStr:gmatch("[^%.]+") do segs[#segs+1] = s end
    if #segs == 0 or segs[1] ~= "game" then return nil end
    table.remove(segs, 1)
    local node = game
    for _, seg in ipairs(segs) do
        if not node then return nil end
        if seg == "Workspace" then node = workspace
        elseif seg == "Players" then node = Players
        elseif seg == "LocalPlayer" then node = LP
        elseif seg == "CoreGui" then node = CoreGui
        elseif seg == "ReplicatedStorage" then node = game:GetService("ReplicatedStorage")
        else
            if node == Players and seg == LP.Name then node = LP
            else node = node:FindFirstChild(seg) end
            if not node then return nil end
        end
    end
    return node
end

local function shortName(t) return (t:gsub("%s+Egg$", "")) end

local function getEggData(model)
    local p = model:FindFirstChild("Egg")
    if not p or not p:IsA("MeshPart") then return nil end
    local hatch = p:GetAttribute("HatchSizeMult") or 0
    local oneIn = p:GetAttribute("SizeOneIn")     or 0
    local luck  = p:GetAttribute("HatchLuck")     or 0
    local br    = p:GetAttribute("WeightBracket") or ""
    local hp    = p:GetAttribute("Health")        or 0
    local maxHp = p:GetAttribute("MaxHealth")     or 1
    local spAt  = p:GetAttribute("SpawnedAt")     or 0
    local broken= p:GetAttribute("Broken")        or false
    local eType = p:GetAttribute("EggType")       or "?"

    local bracketPts = (br=="TITANIC" and 100) or (br=="HUGE" and 50)
                    or (br=="BIG" and 20) or 0
    local score = (hatch * 10) + (oneIn * 0.5) + (luck * 1) + bracketPts
    local rank  = BRACKET_RANK[br] or 1

    local bracketDisplay
    if br == "" or br == "—" or br == nil then
        bracketDisplay = "NONE"
    else
        bracketDisplay = br
    end

    return {
        model = model, part = p,
        eggType = eType, shortName = shortName(eType),
        hatchSize = hatch, oneIn = oneIn, hatchLuck = luck,
        bracket = br, bracketDisplay = bracketDisplay, bracketRank = rank,
        health = hp, maxHealth = maxHp,
        spawnedAt = spAt, broken = broken,
        hpPct = (maxHp > 0) and (hp / maxHp) or 1,
        score = score,
    }
end

local function bracketColor(b)
    if b == "TITANIC" then return Color3.fromRGB(255, 80, 80)
    elseif b == "HUGE"   then return Color3.fromRGB(255, 150, 50)
    elseif b == "BIG"    then return Color3.fromRGB(255, 210, 90)
    elseif b == "NONE"   then return Color3.fromRGB(100, 100, 115)
    else return Color3.fromRGB(120, 125, 140) end
end

local function scoreTint(s)
    if s >= 150 then return Color3.fromRGB(255, 90, 90)
    elseif s >= 90 then return Color3.fromRGB(255, 160, 70)
    elseif s >= 50 then return Color3.fromRGB(255, 210, 110)
    else return Color3.fromRGB(200, 200, 210) end
end

local function luckColor(l)
    if l >= 3.0 then return Color3.fromRGB(255, 100, 100)
    elseif l >= 2.5 then return Color3.fromRGB(255, 170, 60)
    elseif l >= 2.0 then return Color3.fromRGB(255, 210, 90)
    elseif l >= 1.5 then return Color3.fromRGB(90, 200, 130)
    else return Color3.fromRGB(130, 135, 150) end
end

local function hpPctColor(p)
    p = math.clamp(p, 0, 1)
    if p >= 0.99 then return Color3.fromRGB(90, 200, 130)
    elseif p >= 0.75 then return Color3.fromRGB(180, 210, 90)
    elseif p >= 0.5 then return Color3.fromRGB(255, 210, 90)
    elseif p >= 0.25 then return Color3.fromRGB(255, 150, 60)
    else return Color3.fromRGB(230, 70, 80) end
end

--// ==== ESP ====
local espTarget, espBillboard, espLabel, espHpFill, espHpTxt = nil,nil,nil,nil,nil

local function clearESP()
    if espBillboard then
        espBillboard:Destroy()
        espBillboard = nil
        espLabel = nil; espHpFill = nil; espHpTxt = nil
    end
    espTarget = nil
end

local function setESP(model, d)
    clearESP()
    if not model or not d or d.broken then return end
    local part = d.part
    if not part or not part.Parent then return end
    espTarget = model

    local bb = Instance.new("BillboardGui")
    bb.Name = "EggESP"
    bb.Adornee = part
    bb.Size = UDim2.new(0, 150, 0, 52)
    bb.StudsOffset = Vector3.new(0, 5, 0)
    bb.AlwaysOnTop = true
    bb.LightInfluence = 0
    bb.MaxDistance = ESP_MAX_DISTANCE
    bb.Parent = part

    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, 0, 1, 0)
    frame.BackgroundColor3 = Color3.fromRGB(16, 16, 20)
    frame.BackgroundTransparency = 0.15
    frame.BorderSizePixel = 0
    frame.Parent = bb
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 4)
    local stroke = Instance.new("UIStroke")
    stroke.Color = bracketColor(d.bracketDisplay)
    stroke.Thickness = 1; stroke.Parent = frame

    local nameLbl = Instance.new("TextLabel")
    nameLbl.Size = UDim2.new(1, -6, 0, 12); nameLbl.Position = UDim2.new(0, 3, 0, 2)
    nameLbl.BackgroundTransparency = 1
    nameLbl.Text = d.shortName
    nameLbl.TextColor3 = bracketColor(d.bracketDisplay)
    nameLbl.TextXAlignment = Enum.TextXAlignment.Left
    nameLbl.Font = Enum.Font.GothamBold; nameLbl.TextSize = 10
    nameLbl.Parent = frame

    local infoLbl = Instance.new("TextLabel")
    infoLbl.Size = UDim2.new(1, -6, 0, 10); infoLbl.Position = UDim2.new(0, 3, 0, 14)
    infoLbl.BackgroundTransparency = 1
    infoLbl.Text = string.format("×%.2f | 1/%d | L%.2f | %s",
        d.hatchSize, d.oneIn, d.hatchLuck, d.bracketDisplay)
    infoLbl.TextColor3 = Color3.fromRGB(220, 220, 230)
    infoLbl.TextXAlignment = Enum.TextXAlignment.Left
    infoLbl.Font = Enum.Font.Code; infoLbl.TextSize = 9
    infoLbl.Parent = frame

    local distLbl = Instance.new("TextLabel")
    distLbl.Size = UDim2.new(1, -6, 0, 10); distLbl.Position = UDim2.new(0, 3, 0, 26)
    distLbl.BackgroundTransparency = 1
    distLbl.Text = "—"
    distLbl.TextColor3 = Color3.fromRGB(140, 145, 160)
    distLbl.TextXAlignment = Enum.TextXAlignment.Left
    distLbl.Font = Enum.Font.Code; distLbl.TextSize = 8
    distLbl.Parent = frame

    local hpBg = Instance.new("Frame")
    hpBg.Size = UDim2.new(1, -6, 0, 6); hpBg.Position = UDim2.new(0, 3, 0, 40)
    hpBg.BackgroundColor3 = Color3.fromRGB(40, 30, 40)
    hpBg.BorderSizePixel = 0; hpBg.Parent = frame
    Instance.new("UICorner", hpBg).CornerRadius = UDim.new(1, 0)

    local hpFill = Instance.new("Frame")
    hpFill.Size = UDim2.new(math.clamp(d.hpPct, 0, 1), 0, 1, 0)
    hpFill.BackgroundColor3 = hpPctColor(d.hpPct)
    hpFill.BorderSizePixel = 0; hpFill.Parent = hpBg
    Instance.new("UICorner", hpFill).CornerRadius = UDim.new(1, 0)

    local hpTxt = Instance.new("TextLabel")
    hpTxt.Size = UDim2.new(1, -8, 0, 8); hpTxt.Position = UDim2.new(0, 3, 0, 39)
    hpTxt.BackgroundTransparency = 1
    hpTxt.Text = string.format("HP %d%%", math.floor(d.hpPct * 100 + 0.5))
    hpTxt.TextColor3 = Color3.fromRGB(255, 255, 255)
    hpTxt.TextXAlignment = Enum.TextXAlignment.Right
    hpTxt.Font = Enum.Font.Code; hpTxt.TextSize = 7
    hpTxt.Parent = frame

    espBillboard = bb; espLabel = distLbl; espHpFill = hpFill; espHpTxt = hpTxt
end

task.spawn(function()
    while true do
        task.wait(0.15)
        if not espBillboard or not espTarget or not espTarget.Parent then
            if espBillboard and not espBillboard.Parent then
                espBillboard = nil; espLabel = nil; espHpFill = nil; espHpTxt = nil; espTarget = nil
            end
        else
            local char = LP.Character
            local hrp  = char and char:FindFirstChild("HumanoidRootPart")
            local part = espTarget:FindFirstChild("Egg")
            if hrp and part then
                local dist = (hrp.Position - part.Position).Magnitude
                espBillboard.Enabled = dist > NEAR_DISTANCE
                if espLabel and espLabel.Parent then
                    espLabel.Text = string.format("%.0f studs", dist)
                end
                local hp    = part:GetAttribute("Health")    or 0
                local maxHp = part:GetAttribute("MaxHealth") or 1
                local pct   = (maxHp > 0) and (hp / maxHp) or 1
                if espHpFill and espHpFill.Parent then
                    espHpFill.Size = UDim2.new(math.clamp(pct, 0, 1), 0, 1, 0)
                    espHpFill.BackgroundColor3 = hpPctColor(pct)
                end
                if espHpTxt and espHpTxt.Parent then
                    espHpTxt.Text = string.format("HP %d%%", math.floor(pct * 100 + 0.5))
                end
            end
        end
    end
end)

--// ==== PALETTE ====
local C_BG     = Color3.fromRGB(16, 16, 20)
local C_CARD   = Color3.fromRGB(24, 24, 30)
local C_ROW    = Color3.fromRGB(30, 30, 38)
local C_HI     = Color3.fromRGB(48, 60, 90)
local C_TXT    = Color3.fromRGB(232, 232, 238)
local C_SUB    = Color3.fromRGB(130, 135, 150)
local C_BORDER = Color3.fromRGB(44, 44, 56)
local C_ACCENT = Color3.fromRGB(96, 140, 230)
local C_GREEN  = Color3.fromRGB(90, 200, 130)
local C_RED    = Color3.fromRGB(220, 80, 90)
local C_GOLD   = Color3.fromRGB(255, 210, 90)
local C_DARK   = Color3.fromRGB(12, 12, 16)
local C_PURPLE = Color3.fromRGB(170, 130, 255)

--// ==== GUI ====
local old = CoreGui:FindFirstChild("EggWalkGui")
if old then old:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "EggWalkGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 999
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = CoreGui

local W = 360
local HEADER_H = 24
local STATUS_H = 12
local BTN_ROW_Y = 42
local BTN_ROW_H = 18
local SPEED_ROW_Y = 64
local SPEED_ROW_H = 18
local COL_ROW_Y = 86
local COL_ROW_H = 13
local LIST_Y = 101
local LIST_H = LIST_HEIGHT
local MAIN_H = LIST_Y + LIST_H + 8

local main = Instance.new("Frame")
main.Size = UDim2.new(0, W, 0, MAIN_H)
main.Position = UDim2.new(0, 16, 0.5, -MAIN_H / 2)
main.BackgroundColor3 = C_BG
main.BorderSizePixel = 0
main.Active = true
main.Draggable = true
main.Parent = gui
Instance.new("UICorner", main).CornerRadius = UDim.new(0, 10)
local mst = Instance.new("UIStroke"); mst.Color = C_BORDER; mst.Thickness = 1; mst.Parent = main

-- Header
local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, HEADER_H)
header.BackgroundColor3 = C_CARD
header.BorderSizePixel = 0
header.Parent = main
Instance.new("UICorner", header).CornerRadius = UDim.new(0, 10)
local hfix = Instance.new("Frame")
hfix.Size = UDim2.new(1, 0, 0, 8); hfix.Position = UDim2.new(0, 0, 1, -8)
hfix.BackgroundColor3 = C_CARD; hfix.BorderSizePixel = 0; hfix.Parent = header

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -40, 1, 0)
title.Position = UDim2.new(0, 10, 0, 0)
title.BackgroundTransparency = 1
title.Text = "🥚 Egg Scanner"
title.TextColor3 = C_TXT
title.TextXAlignment = Enum.TextXAlignment.Left
title.Font = Enum.Font.GothamBold
title.TextSize = 10
title.Parent = header

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 18, 0, 18)
closeBtn.Position = UDim2.new(1, -22, 0.5, -9)
closeBtn.BackgroundColor3 = C_RED
closeBtn.BorderSizePixel = 0
closeBtn.Text = "✕"
closeBtn.TextColor3 = Color3.fromRGB(255,255,255)
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 9
closeBtn.Parent = header
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 4)

-- Status
local status = Instance.new("TextLabel")
status.Size = UDim2.new(1, -16, 0, STATUS_H)
status.Position = UDim2.new(0, 8, 0, 28)
status.BackgroundTransparency = 1
status.Text = "🔍 Loading..."
status.TextColor3 = C_SUB
status.Font = Enum.Font.Gotham
status.TextSize = 8
status.TextXAlignment = Enum.TextXAlignment.Left
status.Parent = main

-- Auto + Clear
local autoBtn = Instance.new("TextButton")
autoBtn.Size = UDim2.new(0.5, -12, 0, BTN_ROW_H)
autoBtn.Position = UDim2.new(0, 8, 0, BTN_ROW_Y)
autoBtn.BackgroundColor3 = C_ACCENT
autoBtn.BorderSizePixel = 0
autoBtn.Text = "▶ AUTO OFF"
autoBtn.TextColor3 = Color3.fromRGB(255,255,255)
autoBtn.Font = Enum.Font.GothamBold
autoBtn.TextSize = 8
autoBtn.Parent = main
Instance.new("UICorner", autoBtn).CornerRadius = UDim.new(0, 4)

local clearBtn = Instance.new("TextButton")
clearBtn.Size = UDim2.new(0.5, -12, 0, BTN_ROW_H)
clearBtn.Position = UDim2.new(0.5, 4, 0, BTN_ROW_Y)
clearBtn.BackgroundColor3 = C_CARD
clearBtn.BorderSizePixel = 0
clearBtn.Text = "✖ Clear ESP"
clearBtn.TextColor3 = C_RED
clearBtn.Font = Enum.Font.GothamBold
clearBtn.TextSize = 8
clearBtn.Parent = main
Instance.new("UICorner", clearBtn).CornerRadius = UDim.new(0, 4)
clearBtn.MouseButton1Click:Connect(function()
    clearESP()
    status.Text = "ESP cleared"
    status.TextColor3 = C_SUB
end)

-- Speed bar: [⚡ info] [⚡ 250] [NOCLIP]
local speedBar = Instance.new("Frame")
speedBar.Size = UDim2.new(1, -16, 0, SPEED_ROW_H)
speedBar.Position = UDim2.new(0, 8, 0, SPEED_ROW_Y)
speedBar.BackgroundTransparency = 1
speedBar.Parent = main

local speedInfo = Instance.new("TextLabel")
speedInfo.Size = UDim2.new(0, 60, 1, 0)
speedInfo.Position = UDim2.new(0, 0, 0, 0)
speedInfo.BackgroundTransparency = 1
speedInfo.Text = "⚡ —"
speedInfo.TextColor3 = C_GOLD
speedInfo.TextXAlignment = Enum.TextXAlignment.Left
speedInfo.Font = Enum.Font.Code
speedInfo.TextSize = 9
speedInfo.Parent = speedBar

local speedBtn = Instance.new("TextButton")
speedBtn.Size = UDim2.new(0, 100, 1, 0)
speedBtn.Position = UDim2.new(0, 64, 0, 0)
speedBtn.BackgroundColor3 = C_ACCENT
speedBtn.BorderSizePixel = 0
speedBtn.Text = string.format("⚡ %d", PRESET_SPEED)
speedBtn.TextColor3 = Color3.fromRGB(255,255,255)
speedBtn.Font = Enum.Font.GothamBold
speedBtn.TextSize = 8
speedBtn.Parent = speedBar
Instance.new("UICorner", speedBtn).CornerRadius = UDim.new(0, 3)

local noclipBtn = Instance.new("TextButton")
noclipBtn.Size = UDim2.new(0, 100, 1, 0)
noclipBtn.Position = UDim2.new(0, 168, 0, 0)
noclipBtn.BackgroundColor3 = C_PURPLE
noclipBtn.BorderSizePixel = 0
noclipBtn.Text = "🚪 NOCLIP OFF"
noclipBtn.TextColor3 = Color3.fromRGB(255,255,255)
noclipBtn.Font = Enum.Font.GothamBold
noclipBtn.TextSize = 8
noclipBtn.Parent = speedBar
Instance.new("UICorner", noclipBtn).CornerRadius = UDim.new(0, 3)

--// ==== SPEED KEEPER ====
local originalSpeed   = nil
local speedLockTarget = nil
local speedKeeperConn = nil

local function getHum()
    local char = LP.Character
    return char and char:FindFirstChildOfClass("Humanoid")
end

local function startSpeedKeeper()
    if speedKeeperConn then speedKeeperConn:Disconnect() end
    speedKeeperConn = RunService.Stepped:Connect(function()
        if not speedLockTarget then return end
        local hum = getHum()
        if hum and hum.WalkSpeed ~= speedLockTarget then
            pcall(function() hum.WalkSpeed = speedLockTarget end)
        end
    end)
end

local function stopSpeedKeeper()
    if speedKeeperConn then
        speedKeeperConn:Disconnect()
        speedKeeperConn = nil
    end
end

speedBtn.MouseButton1Click:Connect(function()
    local hum = getHum()
    if not hum then return end
    if not originalSpeed then originalSpeed = hum.WalkSpeed end
    hum.WalkSpeed = PRESET_SPEED
    speedLockTarget = PRESET_SPEED
    speedInfo.Text = string.format("⚡ %d", PRESET_SPEED)
    speedInfo.TextColor3 = C_GOLD
    speedBtn.BackgroundColor3 = C_GREEN
    status.Text = string.format("⚡ Speed: %d (locked)", PRESET_SPEED)
    status.TextColor3 = C_GOLD
    startSpeedKeeper()
end)

task.spawn(function()
    while gui.Parent do
        task.wait(0.3)
        local hum = getHum()
        if hum then
            local suffix = speedLockTarget and " 🔒" or ""
            speedInfo.Text = string.format("⚡ %d%s", hum.WalkSpeed, suffix)
        end
    end
end)

LP.CharacterAdded:Connect(function(char)
    local hum = char:WaitForChild("Humanoid", 5)
    if not hum then return end
    task.wait(0.1)
    if speedLockTarget then
        pcall(function() hum.WalkSpeed = speedLockTarget end)
    else
        originalSpeed = hum.WalkSpeed
    end
end)

--// ==== NOCLIP ====
local noclipActive = false
local noclipConn   = nil

local function startNoClip()
    if noclipConn then noclipConn:Disconnect() end
    noclipConn = RunService.Stepped:Connect(function()
        if not noclipActive then return end
        local char = LP.Character
        if not char then return end
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") and part.CanCollide then
                part.CanCollide = false
            end
        end
    end)
end

local function stopNoClip()
    if noclipConn then noclipConn:Disconnect() noclipConn = nil end
    local char = LP.Character
    if char then
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") then
                part.CanCollide = true
            end
        end
    end
end

noclipBtn.MouseButton1Click:Connect(function()
    noclipActive = not noclipActive
    if noclipActive then
        noclipBtn.Text = "🚪 NOCLIP ON"
        noclipBtn.BackgroundColor3 = C_GREEN
        startNoClip()
        status.Text = "🚪 NoClip enabled"
        status.TextColor3 = C_GREEN
    else
        noclipBtn.Text = "🚪 NOCLIP OFF"
        noclipBtn.BackgroundColor3 = C_PURPLE
        stopNoClip()
        status.Text = "🚪 NoClip disabled"
        status.TextColor3 = C_SUB
    end
end)

--// ==== COLUMN HEADER ====
local colH = Instance.new("Frame")
colH.Size = UDim2.new(1, -16, 0, COL_ROW_H)
colH.Position = UDim2.new(0, 8, 0, COL_ROW_Y)
colH.BackgroundColor3 = C_CARD
colH.BorderSizePixel = 0
colH.Parent = main
Instance.new("UICorner", colH).CornerRadius = UDim.new(0, 3)

local function col(text, x, w, align)
    local l = Instance.new("TextLabel")
    l.Size = UDim2.new(0, w, 1, 0)
    l.Position = UDim2.new(0, x, 0, 0)
    l.BackgroundTransparency = 1
    l.Text = text; l.TextColor3 = C_SUB
    l.TextXAlignment = align or Enum.TextXAlignment.Left
    l.Font = Enum.Font.GothamBold; l.TextSize = 7
    l.Parent = colH
    return l
end

col("EGG",        4,   56)
col("SIZE×",      62,  34, Enum.TextXAlignment.Center)
col("1IN",        98,  28, Enum.TextXAlignment.Center)
col("LUCK",       128, 34, Enum.TextXAlignment.Center)
col("BRACKET",    164, 44, Enum.TextXAlignment.Center)
col("HP",         210, 30, Enum.TextXAlignment.Center)
col("AGE",        242, 28, Enum.TextXAlignment.Center)
col("",           272, 46, Enum.TextXAlignment.Center)

--// ==== SCROLL (fix 10 row) ====
local scroll = Instance.new("ScrollingFrame")
scroll.Size = UDim2.new(1, -16, 0, LIST_H)
scroll.Position = UDim2.new(0, 8, 0, LIST_Y)
scroll.BackgroundColor3 = C_DARK
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 3
scroll.ScrollBarImageColor3 = C_BORDER
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
scroll.Parent = main
Instance.new("UICorner", scroll).CornerRadius = UDim.new(0, 6)
local sst = Instance.new("UIStroke"); sst.Color = C_BORDER; sst.Thickness = 1; sst.Parent = scroll

local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 1)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = scroll

local pad = Instance.new("UIPadding")
pad.PaddingTop = UDim.new(0, 2)
pad.PaddingBottom = UDim.new(0, 2)
pad.PaddingLeft = UDim.new(0, 2)
pad.PaddingRight = UDim.new(0, 2)
pad.Parent = scroll

--// ==== STATE ====
local rows = {}
local autoActive = false
local autoTargetModel = nil
local autoWalking = false
local autoArrived = false

--// ==== AUTO HELPERS ====
local function stopMovement()
    local char = LP.Character
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    local hum  = char and char:FindFirstChildOfClass("Humanoid")
    if hrp and hum then hum:MoveTo(hrp.Position) end
end

local function isEggAlive(d)
    if not d or d.broken then return false end
    local part = d.part
    if not part or not part.Parent then return false end
    local hp = part:GetAttribute("Health") or 0
    return hp > 0
end

local function findBestTarget(current)
    local best, bestRank, bestLuck, bestScore = nil, -1, -math.huge, -math.huge
    for model, d in pairs(current) do
        if isEggAlive(d) then
            local r = d.bracketRank
            local l = d.hatchLuck
            local s = d.score
            if r > bestRank
               or (r == bestRank and l > bestLuck)
               or (r == bestRank and l == bestLuck and s > bestScore) then
                best, bestRank, bestLuck, bestScore = {model=model, data=d}, r, l, s
            end
        end
    end
    return best
end

local function isBetter(best, current)
    if not best then return false end
    if not current then return true end
    local bb, cc = best.data, current
    if bb.bracketRank ~= cc.bracketRank then
        return bb.bracketRank > cc.bracketRank
    end
    return bb.hatchLuck > cc.hatchLuck
end

local function walkToTarget(target)
    if not target then return end
    local d = target.data
    if not isEggAlive(d) then return end

    local char = LP.Character
    local hum  = char and char:FindFirstChildOfClass("Humanoid")
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    if not hum or not hrp then return end

    autoTargetModel = target.model
    autoWalking = true
    autoArrived = false

    if speedLockTarget then
        pcall(function() hum.WalkSpeed = speedLockTarget end)
    end
    hum:MoveTo(d.part.Position)

    task.spawn(function()
        local lastPos = nil
        while autoActive and autoWalking and autoTargetModel == target.model do
            task.wait(0.15)
            local c = LP.Character
            local h = c and c:FindFirstChild("HumanoidRootPart")
            local u = c and c:FindFirstChildOfClass("Humanoid")
            local p = target.model:FindFirstChild("Egg")
            if not h or not u or not p then autoWalking = false; break end

            if not isEggAlive(getEggData(target.model)) then
                autoWalking = false
                autoTargetModel = nil
                break
            end

            local dist = (h.Position - p.Position).Magnitude
            if dist <= AUTO_STOP_DIST then
                autoWalking = false
                autoArrived = true
                u:MoveTo(h.Position)
                break
            end

            if not lastPos or (p.Position - lastPos).Magnitude > 2 then
                u:MoveTo(p.Position)
                lastPos = p.Position
            end
        end
    end)
end

task.spawn(function()
    while gui.Parent do
        task.wait(AUTO_TICK)
        if not autoActive then continue end

        local target = resolvePath(TARGET_PATH)
        if not target then continue end

        local current = {}
        for _, child in ipairs(target:GetChildren()) do
            if child:IsA("Model") then
                local d = getEggData(child)
                if d then current[child] = d end
            end
        end

        if autoArrived and autoTargetModel then
            local d = current[autoTargetModel]
            if d and isEggAlive(d) then
                local best = findBestTarget(current)
                if best and isBetter(best, d) then
                    autoArrived = false
                    walkToTarget(best)
                end
            else
                autoArrived = false                autoTargetModel = nil
            end
            continue
        end

        if autoWalking and autoTargetModel then
            local d = current[autoTargetModel]
            if not isEggAlive(d) then
                autoWalking = false
                autoTargetModel = nil
            else
                local best = findBestTarget(current)
                if best and isBetter(best, d) then
                    stopMovement()
                    autoWalking = false
                    walkToTarget(best)
                end
            end
            continue
        end

        if not autoTargetModel then
            local best = findBestTarget(current)
            if best then walkToTarget(best) end
        end
    end
end)

autoBtn.MouseButton1Click:Connect(function()
    autoActive = not autoActive
    if autoActive then
        autoBtn.Text = "■ AUTO ON"
        autoBtn.BackgroundColor3 = C_GREEN
        status.Text = "🤖 AUTO: scanning..."
        status.TextColor3 = C_GREEN
    else
        autoBtn.Text = "▶ AUTO OFF"
        autoBtn.BackgroundColor3 = C_ACCENT
        autoTargetModel = nil
        autoWalking = false
        autoArrived = false
        stopMovement()
        status.Text = "AUTO stopped"
        status.TextColor3 = C_SUB
    end
end)

--// ==== ROW ====
local function createRow(model, d)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
    row.BackgroundColor3 = d.broken and Color3.fromRGB(38, 26, 30) or C_ROW
    row.BorderSizePixel = 0
    row.Parent = scroll
    Instance.new("UICorner", row).CornerRadius = UDim.new(0, 3)

    local name = Instance.new("TextLabel")
    name.Size = UDim2.new(0, 56, 1, 0); name.Position = UDim2.new(0, 4, 0, 0)
    name.BackgroundTransparency = 1
    name.Text = d.shortName
    name.TextColor3 = d.broken and C_RED or C_TXT
    name.TextXAlignment = Enum.TextXAlignment.Left
    name.Font = Enum.Font.Code; name.TextSize = 9
    name.TextTruncate = Enum.TextTruncate.AtEnd
    name.Parent = row

    local sz = Instance.new("TextLabel")
    sz.Size = UDim2.new(0, 34, 1, 0); sz.Position = UDim2.new(0, 62, 0, 0)
    sz.BackgroundTransparency = 1
    sz.Text = string.format("%.2f", d.hatchSize)
    sz.TextColor3 = scoreTint(d.score)
    sz.TextXAlignment = Enum.TextXAlignment.Center
    sz.Font = Enum.Font.Code; sz.TextSize = 8
    sz.Parent = row

    local oneIn = Instance.new("TextLabel")
    oneIn.Size = UDim2.new(0, 28, 1, 0); oneIn.Position = UDim2.new(0, 98, 0, 0)
    oneIn.BackgroundTransparency = 1
    oneIn.Text = (d.oneIn >= 10 and ("1/"..d.oneIn)) or tostring(d.oneIn)
    oneIn.TextColor3 = (d.oneIn >= 50 and C_RED) or (d.oneIn >= 10 and C_GOLD) or C_SUB
    oneIn.TextXAlignment = Enum.TextXAlignment.Center
    oneIn.Font = Enum.Font.Code; oneIn.TextSize = 8
    oneIn.Parent = row

    local luck = Instance.new("TextLabel")
    luck.Size = UDim2.new(0, 34, 1, 0); luck.Position = UDim2.new(0, 128, 0, 0)
    luck.BackgroundTransparency = 1
    luck.Text = string.format("%.2f", d.hatchLuck)
    luck.TextColor3 = luckColor(d.hatchLuck)
    luck.TextXAlignment = Enum.TextXAlignment.Center
    luck.Font = Enum.Font.Code; luck.TextSize = 8
    luck.Parent = row

    local br = Instance.new("TextLabel")
    br.Size = UDim2.new(0, 44, 1, 0); br.Position = UDim2.new(0, 164, 0, 0)
    br.BackgroundTransparency = 1
    br.Text = d.bracketDisplay
    br.TextColor3 = bracketColor(d.bracketDisplay)
    br.TextXAlignment = Enum.TextXAlignment.Center
    br.Font = Enum.Font.GothamBold; br.TextSize = 6
    br.Parent = row

    local hpLbl = Instance.new("TextLabel")
    hpLbl.Size = UDim2.new(0, 30, 1, 0); hpLbl.Position = UDim2.new(0, 210, 0, 0)
    hpLbl.BackgroundTransparency = 1
    hpLbl.Text = string.format("%d%%", math.floor(d.hpPct * 100 + 0.5))
    hpLbl.TextColor3 = hpPctColor(d.hpPct)
    hpLbl.TextXAlignment = Enum.TextXAlignment.Center
    hpLbl.Font = Enum.Font.Code; hpLbl.TextSize = 8
    hpLbl.Parent = row

    local age = Instance.new("TextLabel")
    age.Size = UDim2.new(0, 28, 1, 0); age.Position = UDim2.new(0, 242, 0, 0)
    age.BackgroundTransparency = 1
    age.Text = "—"; age.TextColor3 = C_SUB
    age.TextXAlignment = Enum.TextXAlignment.Center
    age.Font = Enum.Font.Code; age.TextSize = 8
    age.Parent = row

    local espBtn = Instance.new("TextButton")
    espBtn.Size = UDim2.new(0, 36, 0, 15)
    espBtn.Position = UDim2.new(1, -40, 0.5, -7)
    espBtn.BackgroundColor3 = C_ACCENT
    espBtn.BorderSizePixel = 0
    espBtn.Text = "ESP"
    espBtn.TextColor3 = Color3.fromRGB(255,255,255)
    espBtn.Font = Enum.Font.GothamBold; espBtn.TextSize = 7
    espBtn.Parent = row
    Instance.new("UICorner", espBtn).CornerRadius = UDim.new(0, 3)

    local rd = {row=row, name=name, sz=sz, oneIn=oneIn, luck=luck,
                br=br, hp=hpLbl, age=age, esp=espBtn, data=d}

    espBtn.MouseButton1Click:Connect(function()
        if rd.data.broken then
            espBtn.Text = "X"; task.wait(0.8); if espBtn.Parent then espBtn.Text = "ESP" end
            return
        end
        if espTarget == model then
            clearESP()
            status.Text = "ESP cleared"; status.TextColor3 = C_SUB
            return
        end
        setESP(model, rd.data)
        if espTarget == model then
            status.Text = string.format("🎯 ESP: %s", rd.data.shortName)
            status.TextColor3 = C_GREEN
        else
            status.Text = "❌ Gagal ESP"; status.TextColor3 = C_RED
        end
    end)

    return rd
end

--// ==== UPDATE ====
local function updateRow(rd, d)
    rd.data = d
    rd.name.Text = d.shortName
    rd.name.TextColor3 = d.broken and C_RED or C_TXT
    rd.row.BackgroundColor3 =
        (autoTargetModel == d.model and Color3.fromRGB(60, 90, 60)) or
        (espTarget == d.model and C_HI) or
        (d.broken and Color3.fromRGB(38,26,30)) or C_ROW

    rd.sz.Text = string.format("%.2f", d.hatchSize)
    rd.sz.TextColor3 = scoreTint(d.score)

    rd.oneIn.Text = (d.oneIn >= 10 and ("1/"..d.oneIn)) or tostring(d.oneIn)
    rd.oneIn.TextColor3 = (d.oneIn >= 50 and C_RED) or (d.oneIn >= 10 and C_GOLD) or C_SUB

    rd.luck.Text = string.format("%.2f", d.hatchLuck)
    rd.luck.TextColor3 = luckColor(d.hatchLuck)

    rd.br.Text = d.bracketDisplay
    rd.br.TextColor3 = bracketColor(d.bracketDisplay)

    rd.hp.Text = string.format("%d%%", math.floor(d.hpPct * 100 + 0.5))
    rd.hp.TextColor3 = hpPctColor(d.hpPct)

    if d.spawnedAt and d.spawnedAt > 0 then
        local ageSec = math.max(0, os.time() - d.spawnedAt)
        if ageSec >= 3600 then
            rd.age.Text = string.format("%.1fh", ageSec/3600)
        elseif ageSec >= 60 then
            rd.age.Text = string.format("%dm", math.floor(ageSec/60))
        else
            rd.age.Text = string.format("%ds", ageSec)
        end
        rd.age.TextColor3 = (ageSec >= AGE_WARN_SECONDS) and C_RED or C_SUB
    else
        rd.age.Text = "—"; rd.age.TextColor3 = C_SUB
    end

    if d.broken then
        rd.esp.Text = "—"
        rd.esp.BackgroundColor3 = Color3.fromRGB(60,40,45)
        rd.esp.Active = false
    else
        if espTarget == d.model then
            rd.esp.Text = "ON"; rd.esp.BackgroundColor3 = C_GOLD
        else
            rd.esp.Text = "ESP"; rd.esp.BackgroundColor3 = C_ACCENT
        end
        rd.esp.Active = true
    end
end

--// ==== SCAN ====
local function sortEggs(list)
    table.sort(list, function(a, b)
        local da, db = a.data, b.data
        if da.bracketRank ~= db.bracketRank then
            return da.bracketRank > db.bracketRank
        elseif da.hatchLuck ~= db.hatchLuck then
            return da.hatchLuck > db.hatchLuck
        else
            return da.score > db.score
        end
    end)
end

local function scanEggs()
    local target = resolvePath(TARGET_PATH)
    if not target then
        status.Text = "❌ Folder Eggs tidak ditemukan"; status.TextColor3 = C_RED
        return
    end

    local current = {}
    for _, child in ipairs(target:GetChildren()) do
        if child:IsA("Model") then
            local d = getEggData(child)
            if d then current[child] = d end
        end
    end

    for model, d in pairs(current) do
        if rows[model] then
            updateRow(rows[model], d)
        else
            rows[model] = createRow(model, d)
        end
    end

    for model, rd in pairs(rows) do
        if not current[model] then
            if rd.row and rd.row.Parent then rd.row:Destroy() end
            rows[model] = nil
        end
    end

    if espTarget and (not espTarget.Parent or (current[espTarget] and current[espTarget].broken)) then
        clearESP()
    end

    local list = {}
    for model, d in pairs(current) do list[#list+1] = {model=model, data=d} end
    sortEggs(list)
    for i, e in ipairs(list) do
        local rd = rows[e.model]
        if rd and rd.row then rd.row.LayoutOrder = i end
    end

    local total, broken = 0, 0
    for _ in pairs(current) do total = total + 1 end
    for _, d in pairs(current) do if d.broken then broken = broken + 1 end end
    if not espTarget and not autoActive then
        status.Text = string.format("🥚 %d eggs | %d broken | sort: bracket→luck", total, broken)
        status.TextColor3 = C_GREEN
    end
end

--// ==== CLOSE ====
closeBtn.MouseButton1Click:Connect(function()
    autoActive = false
    speedLockTarget = nil
    stopSpeedKeeper()
    stopNoClip()
    stopMovement()
    clearESP()
    gui:Destroy()
end)

--// ==== INIT ====
task.wait(0.3)
scanEggs()

task.spawn(function()
    while gui.Parent do
        task.wait(SCAN_INTERVAL)
        if not gui.Parent then break end
        pcall(scanEggs)
    end
end)

print("✅ Egg Scanner + Speed 250 + NoClip + FastPrompt loaded")
