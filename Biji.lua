--// ============================================================
--// EGG SCANNER — ZONE 12+13 COMBINED
--// Streaming sekali jalan, GUI delay 3s, speed 300 toggle
--// Kolom: egg | luck | petkg | hatchanimal | score | esp
--// ============================================================

if not game:IsLoaded() then game.Loaded:Wait() end

local Players         = game:GetService("Players")
local CoreGui         = game:GetService("CoreGui")
local RunService      = game:GetService("RunService")
local UserInput       = game:GetService("UserInputService")
local SoundService    = game:GetService("SoundService")
local TeleportService = game:GetService("TeleportService")
local HttpService     = game:GetService("HttpService")

local LP = Players.LocalPlayer

--// ==== CONFIG ====
local ZONES             = {12, 13}
local ZONE_BASE_PATH    = "game.Workspace.Build.ZoneBuilds.Zone%d.Eggs"
local CONTAINER_PATH    = "game.Workspace.AnimalPickups"

local SCAN_INTERVAL     = 0.5
local MON_SCAN_INTERVAL = 0.2
local ESP_MAX_DIST      = 3000

local ALERT_PETKG_MIN   = 100000
local ALERT_LUCK_MIN    = 10
local ALERT_SOUND_ID    = "117751546358455"
local ALERT_VOLUME      = 2

local SPEED_TARGET      = 300

-- Streaming (sekali jalan saat execute)
local STREAM_TIMEOUT    = 10
local STREAM_WAIT_AFTER = 1.5
local GUI_DELAY         = 3

--// ==== STATE ====
local ZonePaths         = {}
for _, z in ipairs(ZONES) do
    ZonePaths[#ZonePaths+1] = string.format(ZONE_BASE_PATH, z)
end

local Monitoring        = false
local KnownPickups      = {}
local AlertActive       = false
local ScanThread        = nil
local TotalAlerts       = 0

--// ==== ANIMAL → RARITY MAPPING ====
local ANIMAL_RARITY = {
    ["Duskcoil"]="Secret", ["Mossbelly"]="Secret", ["Tidefin"]="Secret",
    ["Cinderclub"]="Celestial", ["Sandbloom"]="Celestial",
    ["Thornmane"]="Inferno", ["Lilacwing"]="Inferno",
    ["Voidhorn"]="Void", ["Gearfang"]="Void",
    ["Spirewing"]="Omega", ["Hexhorn"]="Omega",
    ["Stormwing"]="Spectral", ["Glacierback"]="Spectral",
    ["Hydrafang"]="Ethereal", ["Shadowgale"]="Ethereal",
}
local RARITY_COLOR = {
    Secret    = Color3.fromRGB(255, 60, 60),
    Celestial = Color3.fromRGB(255, 170, 60),
    Inferno   = Color3.fromRGB(255, 100, 100),
    Void      = Color3.fromRGB(160, 60, 220),
    Omega     = Color3.fromRGB(255, 210, 70),
    Spectral  = Color3.fromRGB(90, 200, 230),
    Ethereal  = Color3.fromRGB(180, 120, 255),
}
local function getRarity(a) if not a then return nil end return ANIMAL_RARITY[a] end
local function getRarityColor(r) if not r then return Color3.fromRGB(180,120,255) end return RARITY_COLOR[r] or Color3.fromRGB(180,120,255) end

--// ==== PALETTE ====
local C_BG         = Color3.fromRGB(10, 10, 12)
local C_CARD       = Color3.fromRGB(18, 20, 24)
local C_ROW        = Color3.fromRGB(14, 14, 18)
local C_ROW_HI     = Color3.fromRGB(60, 20, 20)
local C_ROW_BROKEN = Color3.fromRGB(32, 18, 22)
local C_ROW_HATCH  = Color3.fromRGB(50, 40, 60)
local C_TXT        = Color3.fromRGB(210, 210, 220)
local C_SUB        = Color3.fromRGB(120, 125, 140)
local C_BORDER     = Color3.fromRGB(36, 40, 50)
local C_ACCENT     = Color3.fromRGB(80, 120, 200)
local C_GREEN      = Color3.fromRGB(0, 220, 120)
local C_RED        = Color3.fromRGB(220, 70, 80)
local C_GOLD       = Color3.fromRGB(255, 200, 70)
local C_CYAN       = Color3.fromRGB(90, 200, 230)
local C_PURPLE     = Color3.fromRGB(180, 120, 255)
local C_DARK       = Color3.fromRGB(6, 6, 9)
local C_GRAY       = Color3.fromRGB(120, 125, 140)

local BRACKET_RANK = { TITANIC = 4, HUGE = 3, BIG = 2, ["—"] = 1, [""] = 1 }
local BRACKET_COLOR = {
    TITANIC = Color3.fromRGB(255, 60, 60),
    HUGE    = Color3.fromRGB(255, 150, 50),
    BIG     = Color3.fromRGB(255, 210, 90),
    ["—"]   = Color3.fromRGB(120, 200, 130),
    [""]    = Color3.fromRGB(120, 200, 130),
}

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
        else
            node = node:FindFirstChild(seg)
            if not node then return nil end
        end
    end
    return node
end

local function shortName(t) return (t:gsub("%s+Egg$", "")) end

local function fmtNum(n)
    if not n then return "—" end
    if type(n) ~= "number" then return tostring(n) end
    if n >= 1e12 then return string.format("%.1fT", n/1e12) end
    if n >= 1e9  then return string.format("%.1fB", n/1e9) end
    if n >= 1e6  then return string.format("%.1fM", n/1e6) end
    if n >= 1e3  then return string.format("%.1fk", n/1e3) end
    if n == math.floor(n) then return tostring(math.floor(n)) end
    return string.format("%.1f", n)
end

local function parseNumber(str)
    if not str or str == "" then return 0 end
    str = tostring(str):gsub("[%$,%s/]", ""):upper()
    local num, suffix = str:match("^([%d%.]+)([KMBTQ]?)")
    if not num then return 0 end
    local n = tonumber(num) or 0
    local mult = ({K=1e3, M=1e6, B=1e9, T=1e12, Q=1e15})[suffix] or 1
    return n * mult
end

local function bracketTag(br) if br and br ~= "" then return br end return "—" end
local function bracketColor(br) return BRACKET_COLOR[br or ""] or BRACKET_COLOR["—"] end

local function luckColor(l)
    if l >= 3.0 then return Color3.fromRGB(255, 100, 100)
    elseif l >= 2.5 then return Color3.fromRGB(255, 170, 60)
    elseif l >= 2.0 then return Color3.fromRGB(255, 210, 90)
    elseif l >= 1.5 then return Color3.fromRGB(90, 200, 130)
    else return C_SUB end
end

local function scoreColor(s)
    if s >= 50000 then return Color3.fromRGB(255, 60, 60)
    elseif s >= 10000 then return Color3.fromRGB(255, 150, 50)
    elseif s >= 2000 then return Color3.fromRGB(255, 210, 90)
    elseif s >= 500 then return C_CYAN
    else return C_SUB end
end

--// ==== CHARACTER ====
local function getChar()
    local char = LP.Character
    if not char then return nil end
    local hum = char:FindFirstChildOfClass("Humanoid")
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hum or not hrp then return nil end
    return char, hum, hrp
end
local function getHum()
    local char = LP.Character
    return char and char:FindFirstChildOfClass("Humanoid")
end

--// ==== SPEED KEEPER ====
local originalSpeed   = nil
local speedLockTarget = nil
local speedKeeperConn = nil

local function enforceSpeed()
    if not speedLockTarget then return end
    local hum = getHum()
    if hum and hum.WalkSpeed ~= speedLockTarget then
        pcall(function() hum.WalkSpeed = speedLockTarget end)
    end
end

local function startSpeedKeeper()
    if speedKeeperConn then speedKeeperConn:Disconnect() end
    speedKeeperConn = RunService.Heartbeat:Connect(enforceSpeed)
    enforceSpeed()
end

local function stopSpeedKeeper()
    if speedKeeperConn then speedKeeperConn:Disconnect() speedKeeperConn = nil end
end

local function applySpeed(speed)
    local hum = getHum()
    if not hum then return end
    if not originalSpeed then originalSpeed = hum.WalkSpeed end
    hum.WalkSpeed = speed
    speedLockTarget = speed
    startSpeedKeeper()
end

--// ==== EGG DATA ====
local function getEggData(model)
    local p = model:FindFirstChild("Egg")
    if not p or not p:IsA("MeshPart") then return nil end
    local hatch    = p:GetAttribute("HatchSizeMult") or 0
    local sizeMult = p:GetAttribute("SizeMult")      or hatch
    local oneIn    = p:GetAttribute("SizeOneIn")     or 0
    local luck     = p:GetAttribute("HatchLuck")     or 0
    local br       = p:GetAttribute("WeightBracket") or ""
    local broken   = p:GetAttribute("Broken")        or false
    local eType    = p:GetAttribute("EggType")       or "?"
    local baseKg   = p:GetAttribute("EggBaseKg")     or 0
    local predKg   = baseKg * (sizeMult ^ 3)
    local hatchAnimal = p:GetAttribute("HatchAnimal")
    local rarity = getRarity(hatchAnimal)
    local score = luck * predKg
    return {
        model = model, part = p,
        eggType = eType, shortName = shortName(eType),
        oneIn = oneIn, hatchLuck = luck, bracket = br,
        bracketRank = BRACKET_RANK[br] or 1,
        broken = broken,
        baseKg = baseKg, predKg = predKg, sizeMult = sizeMult,
        hatchAnimal = hatchAnimal, rarity = rarity, score = score,
    }
end

--// ==== MONITOR HELPERS ====
local function getWeightFromModel(model)
    local attr = model:GetAttribute("WeightKg")
    if type(attr) == "number" and attr > 0 then return attr end
    local attr2 = model:GetAttribute("Weight")
    if type(attr2) == "number" and attr2 > 0 then return attr2 end
    local overhead = model:FindFirstChild("AnimalOverheadAttachment", true)
    if overhead then
        local ao = overhead:FindFirstChild("AnimalOverhead")
        if ao then
            for _, fname in ipairs({"Weight", "WeightKg", "WeightLabel"}) do
                local f = ao:FindFirstChild(fname, true)
                if f then
                    if f:IsA("TextLabel") then return parseNumber(f.Text) end
                    local lbl = f:FindFirstChildWhichIsA("TextLabel", true)
                    if lbl then return parseNumber(lbl.Text) end
                end
            end
        end
    end
    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA("TextLabel") and d.Text then
            local t = d.Text
            if t:find("[Kk][Gg]") or t:lower():find("weight") then
                local w = parseNumber(t)
                if w > 0 then return w end
            end
        end
    end
    return 0
end

local function getPickupInfo(pickup)
    local info = {
        name = pickup.Name,
        animalName = pickup:GetAttribute("AnimalName") or pickup.Name,
        rarity = nil, price = nil, priceValue = 0, weight = 0,
    }
    local overhead = pickup:FindFirstChild("AnimalOverheadAttachment", true)
    if overhead then
        local ao = overhead:FindFirstChild("AnimalOverhead")
        if ao then
            local rf = ao:FindFirstChild("Rarity")
            if rf then
                local rl = rf:FindFirstChild("RarityLabel")
                if rl and rl:IsA("TextLabel") then info.rarity = rl.Text end
            end
            local cps = ao:FindFirstChild("CashPerSecond")
            if cps then
                local pl = cps:FindFirstChild("CashPerSecond")
                if pl and pl:IsA("TextLabel") then
                    info.price = pl.Text
                    info.priceValue = parseNumber(pl.Text)
                end
            end
        end
    end
    info.weight = getWeightFromModel(pickup)
    return info
end

--// ==== ALERT FILTER ====
local ALERT_FILTERS = {
    { rarity = "Spectral", minPrice = 5e12 },
    { rarity = "Omega",    minPrice = 5e12 },
    { rarity = "Ethereal" },
    { rarity = "Void",     minPrice = 5e12 },
    { rarity = "Inferno",  minWeight = 900000 },
    { minPrice = 5e12 },
}

local function matchFilter(info, filter)
    if filter.name and info.animalName ~= filter.name and info.name ~= filter.name then return false end
    if filter.nameContains then
        local n = filter.nameContains:lower()
        local h1 = tostring(info.animalName):lower()
        local h2 = tostring(info.name):lower()
        if not h1:find(n, 1, true) and not h2:find(n, 1, true) then return false end
    end
    if filter.rarity and info.rarity ~= filter.rarity then return false end
    if filter.minPrice and (info.priceValue or 0) < filter.minPrice then return false end
    if filter.minWeight and (info.weight or 0) < filter.minWeight then return false end
    return true
end
local function matchAnyFilter(info)
    for _, f in ipairs(ALERT_FILTERS) do
        if matchFilter(info, f) then return true end
    end
    return false
end

--// ==== SOUND ====
local AlertSound = Instance.new("Sound")
AlertSound.Name = "EggAlertSound"
AlertSound.Volume = ALERT_VOLUME
AlertSound.Looped = true
AlertSound.SoundId = "rbxassetid://" .. ALERT_SOUND_ID
AlertSound.Parent = SoundService

local AlertMuted = false
local function PlayAlert()
    if AlertMuted then return end
    if AlertActive then return end
    AlertActive = true
    AlertSound:Stop()
    AlertSound.SoundId = "rbxassetid://" .. ALERT_SOUND_ID
    pcall(function() AlertSound:Play() end)
end
local function StopAlert()
    AlertActive = false
    pcall(function() AlertSound:Stop() end)
end

--// ==== STREAMING (SEKALI JALAN) ====
local function requestStreamForZone(zoneNum)
    local zoneFolder = resolvePath(string.format("game.Workspace.Build.ZoneBuilds.Zone%d", zoneNum))
    if not zoneFolder then return false end
    local pos
    local ok, pivot = pcall(function() return zoneFolder:GetPivot().Position end)
    if ok and pivot then
        pos = pivot
    else
        local hrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
        if not hrp then return false end
        pos = hrp.Position
    end
    local okReq = pcall(function()
        LP:RequestStreamAroundAsync(pos, STREAM_TIMEOUT)
    end)
    return okReq
end

print("[stream] mulai streaming zona 12 & 13...")
for _, z in ipairs(ZONES) do
    requestStreamForZone(z)
    task.wait(STREAM_WAIT_AFTER)
    local folder = resolvePath(string.format(ZONE_BASE_PATH, z))
    local n = 0
    if folder then
        for _, c in ipairs(folder:GetChildren()) do
            if c:IsA("Model") then n = n + 1 end
        end
    end
    print(string.format("[stream] zona %d → %d egg terlihat", z, n))
end

print(string.format("[gui] menunggu %d detik sebelum GUI muncul...", GUI_DELAY))
task.wait(GUI_DELAY)

--// ==== GUI ====
local old = CoreGui:FindFirstChild("EggScanGui")
if old then old:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "EggScanGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 999
gui.Parent = CoreGui

-- Lebar dinaikkan sedikit untuk hatchanimal
local W = 380
local HEADER_H  = 20
local STATUS_H  = 14
local BTN_H     = 20
local COLH_H    = 14
local MAIN_H    = 380

local main = Instance.new("Frame")
main.Size = UDim2.new(0, W, 0, MAIN_H)
main.Position = UDim2.new(0, 12, 0.5, -MAIN_H/2)
main.BackgroundColor3 = C_BG
main.BorderSizePixel = 0
main.Active = true
main.ClipsDescendants = true
main.Parent = gui
Instance.new("UICorner", main).CornerRadius = UDim.new(0, 4)
local mst = Instance.new("UIStroke"); mst.Color = C_BORDER; mst.Thickness = 1; mst.Parent = main

-- Header
local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, HEADER_H)
header.BackgroundColor3 = C_CARD
header.BorderSizePixel = 0
header.Parent = main
Instance.new("UICorner", header).CornerRadius = UDim.new(0, 4)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -50, 1, 0)
title.Position = UDim2.new(0, 6, 0, 0)
title.BackgroundTransparency = 1
title.Text = "🥚 egg_scan z12+13"
title.TextColor3 = C_GREEN
title.TextXAlignment = Enum.TextXAlignment.Left
title.Font = Enum.Font.Code
title.TextSize = 11
title.Parent = header

local minBtn = Instance.new("TextButton")
minBtn.Size = UDim2.new(0, 14, 0, 14)
minBtn.Position = UDim2.new(1, -34, 0.5, -7)
minBtn.BackgroundColor3 = Color3.fromRGB(200, 170, 60)
minBtn.BorderSizePixel = 0
minBtn.Text = "—"
minBtn.TextColor3 = Color3.fromRGB(255,255,255)
minBtn.Font = Enum.Font.Code
minBtn.TextSize = 10
minBtn.Parent = header
Instance.new("UICorner", minBtn).CornerRadius = UDim.new(0, 3)

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 14, 0, 14)
closeBtn.Position = UDim2.new(1, -18, 0.5, -7)
closeBtn.BackgroundColor3 = C_RED
closeBtn.BorderSizePixel = 0
closeBtn.Text = "x"
closeBtn.TextColor3 = Color3.fromRGB(255,255,255)
closeBtn.Font = Enum.Font.Code
closeBtn.TextSize = 10
closeBtn.Parent = header
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 3)

local collapseTargets = {}

-- Drag
do
    local dragging, dragStart, startPos
    header.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
           or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = main.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then dragging = false end
            end)
        end
    end)
    UserInput.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
                          or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            main.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y
            )
        end
    end)
end

-- Status
local status = Instance.new("TextLabel")
status.Size = UDim2.new(1, -10, 0, STATUS_H)
status.Position = UDim2.new(0, 5, 0, HEADER_H + 3)
status.BackgroundTransparency = 1
status.Text = "loading..."
status.TextColor3 = C_SUB
status.Font = Enum.Font.Code
status.TextSize = 9
status.TextXAlignment = Enum.TextXAlignment.Left
status.Parent = main
table.insert(collapseTargets, status)

-- Button bar (MON | HOP | SPEED | ALERT | MUTE)
local btnBar = Instance.new("Frame")
btnBar.Size = UDim2.new(1, -10, 0, BTN_H)
btnBar.Position = UDim2.new(0, 5, 0, HEADER_H + STATUS_H + 6)
btnBar.BackgroundTransparency = 1
btnBar.Parent = main
table.insert(collapseTargets, btnBar)

local function makeBtn(text, x, w, color, txtColor)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(0, w, 1, 0)
    b.Position = UDim2.new(0, x, 0, 0)
    b.BackgroundColor3 = color or C_CARD
    b.BorderSizePixel = 0
    b.Text = text
    b.TextColor3 = txtColor or C_TXT
    b.Font = Enum.Font.Code
    b.TextSize = 9
    b.Parent = btnBar
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 3)
    return b
end

local monBtn    = makeBtn("▶MON",       0,   56, Color3.fromRGB(60, 30, 30), Color3.fromRGB(255, 120, 120))
local hopBtn    = makeBtn("🔀 hop",     60,  56, C_ACCENT, Color3.fromRGB(255,255,255))
local speedBtn  = makeBtn("⚡300",      120, 56, C_ACCENT, Color3.fromRGB(255,255,255))
local alertBtn  = makeBtn("🔔 alert",   180, 64, C_CARD,   C_SUB)
local muteBtn   = makeBtn("🔕 mute",    248, 56, C_CARD,   C_SUB)

--// ==== SPEED BUTTON ====
speedBtn.MouseButton1Click:Connect(function()
    if speedLockTarget then
        speedLockTarget = nil
        stopSpeedKeeper()
        local hum = getHum()
        if hum and originalSpeed then hum.WalkSpeed = originalSpeed end
        speedBtn.BackgroundColor3 = C_ACCENT
        speedBtn.Text = "⚡300"
    else
        applySpeed(SPEED_TARGET)
        speedBtn.BackgroundColor3 = C_GREEN
        speedBtn.Text = "⚡300✓"
    end
end)

LP.CharacterAdded:Connect(function(char)
    local hum = char:WaitForChild("Humanoid", 5)
    if not hum then return end
    task.wait(0.1)
    if speedLockTarget then
        pcall(function() hum.WalkSpeed = speedLockTarget end)
        startSpeedKeeper()
    else
        originalSpeed = hum.WalkSpeed
    end
end)

--// ==== ALERT BUTTONS ====
local function refreshAlertBtn()
    if AlertMuted then
        muteBtn.BackgroundColor3 = C_GRAY
        muteBtn.TextColor3 = C_BG
        muteBtn.Text = "🔇 muted"
        alertBtn.BackgroundColor3 = C_CARD
        alertBtn.TextColor3 = C_SUB
        alertBtn.Text = "🔔 alert"
    else
        muteBtn.BackgroundColor3 = C_CARD
        muteBtn.TextColor3 = C_SUB
        muteBtn.Text = "🔕 mute"
        alertBtn.BackgroundColor3 = AlertActive and C_GREEN or C_CARD
        alertBtn.TextColor3 = AlertActive and C_BG or C_SUB
        alertBtn.Text = AlertActive and "🔔 on" or "🔔 alert"
    end
end

alertBtn.MouseButton1Click:Connect(function()
    if AlertMuted then
        AlertMuted = false
        refreshAlertBtn()
        status.Text = "🔔 alert aktif lagi"
        status.TextColor3 = C_GREEN
    else
        StopAlert()
        AlertMuted = true
        refreshAlertBtn()
        status.Text = "🔕 alert di-stop (mute)"
        status.TextColor3 = C_GRAY
    end
end)

muteBtn.MouseButton1Click:Connect(function()
    AlertMuted = not AlertMuted
    if AlertMuted then StopAlert() end
    refreshAlertBtn()
    status.Text = AlertMuted and "🔕 alert muted" or "🔔 alert aktif"
    status.TextColor3 = AlertMuted and C_GRAY or C_GREEN
end)

--// ==== HOP ====
local hopping = false
hopBtn.MouseButton1Click:Connect(function()
    if hopping then return end
    hopping = true
    hopBtn.Text = "⏳..."
    hopBtn.BackgroundColor3 = C_CARD
    hopBtn.TextColor3 = C_SUB
    local placeId = game.PlaceId
    local ok, resp = pcall(function()
        local url = "https://games.roblox.com/v1/games/" .. placeId
            .. "/servers/Public?sortOrder=Asc&limit=100"
        return HttpService:JSONDecode(game:HttpGet(url))
    end)
    if not ok or not resp or not resp.data then
        hopBtn.Text = "❌ fail"
        task.wait(1.5)
        hopBtn.Text = "🔀 hop"
        hopBtn.BackgroundColor3 = C_ACCENT
        hopBtn.TextColor3 = Color3.fromRGB(255,255,255)
        hopping = false
        return
    end
    local servers = {}
    for _, s in ipairs(resp.data) do
        if s.playing < s.maxPlayers then table.insert(servers, s.id) end
    end
    if #servers == 0 then
        hopBtn.Text = "❌ no srv"
        task.wait(1.5)
        hopBtn.Text = "🔀 hop"
        hopBtn.BackgroundColor3 = C_ACCENT
        hopBtn.TextColor3 = Color3.fromRGB(255,255,255)
        hopping = false
        return
    end
    local jobId = servers[math.random(1, #servers)]
    hopBtn.Text = "🔀 going"
    local tpOk, tpErr = pcall(function()
        TeleportService:TeleportToPlaceInstance(placeId, jobId, LP)
    end)
    if not tpOk then
        warn("[Hop] gagal: " .. tostring(tpErr))
        hopBtn.Text = "❌ tp"
        task.wait(1.5)
        hopBtn.Text = "🔀 hop"
        hopBtn.BackgroundColor3 = C_ACCENT
        hopBtn.TextColor3 = Color3.fromRGB(255,255,255)
        hopping = false
    end
end)

--// ==== ESP ====
local espGuis = {}

local function destroyESP(model)
    local bb = espGuis[model]
    if bb then bb:Destroy() espGuis[model] = nil end
end

local function destroyAllESP()
    for model, bb in pairs(espGuis) do
        if bb and bb.Parent then bb:Destroy() end
    end
    espGuis = {}
end

local function buildESP(model, p, d, isAlert)
    if espGuis[model] and espGuis[model].Parent then
        local bb = espGuis[model]
        local frame = bb:FindFirstChildOfClass("Frame")
        if frame then
            local col = isAlert and Color3.fromRGB(255, 60, 60)
                or (d.hatchAnimal and getRarityColor(d.rarity) or bracketColor(d.bracket))
            local st = frame:FindFirstChildOfClass("UIStroke")
            if st then st.Color = col end
            local nm = frame:FindFirstChild("Name")
            if nm then nm.TextColor3 = col end
        end
        return
    end
    local col = isAlert and Color3.fromRGB(255, 60, 60)
        or (d.hatchAnimal and getRarityColor(d.rarity) or bracketColor(d.bracket))

    local bb = Instance.new("BillboardGui")
    bb.Adornee = p
    bb.Size = UDim2.new(0, 170, 0, 46)
    bb.StudsOffset = Vector3.new(0, 5, 0)
    bb.AlwaysOnTop = true
    bb.LightInfluence = 0
    bb.MaxDistance = ESP_MAX_DIST
    bb.Parent = p

    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, 0, 1, 0)
    frame.BackgroundColor3 = C_DARK
    frame.BackgroundTransparency = 0.15
    frame.BorderSizePixel = 0
    frame.Parent = bb
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 3)
    local st = Instance.new("UIStroke"); st.Color = col; st.Thickness = 1; st.Parent = frame

    local nm = Instance.new("TextLabel")
    nm.Name = "Name"
    nm.Size = UDim2.new(1, -6, 0, 14); nm.Position = UDim2.new(0, 3, 0, 2)
    nm.BackgroundTransparency = 1
    local hatchStr = d.hatchAnimal and string.format("%s (%s)", d.hatchAnimal, d.rarity or "?") or ""
    nm.Text = string.format("%s [%s] %s", d.shortName, bracketTag(d.bracket), hatchStr)
    nm.TextColor3 = col
    nm.TextXAlignment = Enum.TextXAlignment.Left
    nm.Font = Enum.Font.Code; nm.TextSize = 10
    nm.Parent = frame

    local l1 = Instance.new("TextLabel")
    l1.Size = UDim2.new(1, -6, 0, 12); l1.Position = UDim2.new(0, 3, 0, 17)
    l1.BackgroundTransparency = 1
    l1.Text = string.format("PETKG = %s  |  LUCK = %.2f", fmtNum(d.predKg), d.hatchLuck)
    l1.TextColor3 = C_GOLD
    l1.TextXAlignment = Enum.TextXAlignment.Left
    l1.Font = Enum.Font.Code; l1.TextSize = 9
    l1.Parent = frame

    local l2 = Instance.new("TextLabel")
    l2.Size = UDim2.new(1, -6, 0, 10); l2.Position = UDim2.new(0, 3, 0, 30)
    l2.BackgroundTransparency = 1
    l2.Text = string.format("SCORE = %s", fmtNum(d.score))
    l2.TextColor3 = C_CYAN
    l2.TextXAlignment = Enum.TextXAlignment.Left
    l2.Font = Enum.Font.Code; l2.TextSize = 9
    l2.Parent = frame

    espGuis[model] = bb
end

--// ==== COLUMN HEADER ====
local colH = Instance.new("Frame")
colH.Size = UDim2.new(1, -10, 0, COLH_H)
colH.Position = UDim2.new(0, 5, 0, HEADER_H + STATUS_H + BTN_H + 8)
colH.BackgroundColor3 = C_CARD
colH.BorderSizePixel = 0
colH.Parent = main
Instance.new("UICorner", colH).CornerRadius = UDim.new(0, 2)
table.insert(collapseTargets, colH)

local function col(text, x, w, align)
    local l = Instance.new("TextLabel")
    l.Size = UDim2.new(0, w, 1, 0)
    l.Position = UDim2.new(0, x, 0, 0)
    l.BackgroundTransparency = 1
    l.Text = text
    l.TextColor3 = C_SUB
    l.TextXAlignment = align or Enum.TextXAlignment.Left
    l.Font = Enum.Font.Code
    l.TextSize = 9
    l.Parent = colH
end

-- Lebar W = 380
col("egg",         4,   80, Enum.TextXAlignment.Left)
col("luck",        88,  40, Enum.TextXAlignment.Center)
col("petkg",       132, 56, Enum.TextXAlignment.Center)
col("hatchanimal", 192, 100, Enum.TextXAlignment.Left)
col("score",       296, 50, Enum.TextXAlignment.Center)
col("esp",         348, 28, Enum.TextXAlignment.Center)

--// ==== SCROLL ====
local scrollH = MAIN_H - (HEADER_H + STATUS_H + BTN_H + COLH_H + 18)
local ROW_H = 18
local scroll = Instance.new("ScrollingFrame")
scroll.Size = UDim2.new(1, -10, 0, scrollH)
scroll.Position = UDim2.new(0, 5, 0, HEADER_H + STATUS_H + BTN_H + COLH_H + 10)
scroll.BackgroundColor3 = C_DARK
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 4
scroll.ScrollBarImageColor3 = C_GREEN
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
scroll.ScrollingDirection = Enum.ScrollingDirection.Y
scroll.ClipsDescendants = true
scroll.Parent = main
Instance.new("UICorner", scroll).CornerRadius = UDim.new(0, 3)
local sst = Instance.new("UIStroke"); sst.Color = C_BORDER; sst.Thickness = 1; sst.Parent = scroll
table.insert(collapseTargets, scroll)

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

--// ==== ROWS ====
local rows = {}

local function createRow(model, d)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, ROW_H)
    row.BackgroundColor3 = d.broken and C_ROW_BROKEN
        or (d.hatchAnimal and C_ROW_HATCH or C_ROW)
    row.BorderSizePixel = 0
    row.Parent = scroll
    Instance.new("UICorner", row).CornerRadius = UDim.new(0, 2)

    local name = Instance.new("TextLabel")
    name.Size = UDim2.new(0, 80, 1, 0); name.Position = UDim2.new(0, 4, 0, 0)
    name.BackgroundTransparency = 1
    name.Text = d.shortName
    name.TextColor3 = d.broken and C_RED or C_TXT
    name.TextXAlignment = Enum.TextXAlignment.Left
    name.Font = Enum.Font.Code; name.TextSize = 10
    name.TextTruncate = Enum.TextTruncate.AtEnd
    name.Parent = row

    local luck = Instance.new("TextLabel")
    luck.Size = UDim2.new(0, 40, 1, 0); luck.Position = UDim2.new(0, 88, 0, 0)
    luck.BackgroundTransparency = 1
    luck.TextColor3 = C_TXT
    luck.TextXAlignment = Enum.TextXAlignment.Center
    luck.Font = Enum.Font.Code; luck.TextSize = 10
    luck.Parent = row

    local petKg = Instance.new("TextLabel")
    petKg.Size = UDim2.new(0, 56, 1, 0); petKg.Position = UDim2.new(0, 132, 0, 0)
    petKg.BackgroundTransparency = 1
    petKg.TextColor3 = C_GOLD
    petKg.TextXAlignment = Enum.TextXAlignment.Center
    petKg.Font = Enum.Font.Code; petKg.TextSize = 10
    petKg.Parent = row

    local hatchAnimal = Instance.new("TextLabel")
    hatchAnimal.Size = UDim2.new(0, 100, 1, 0); hatchAnimal.Position = UDim2.new(0, 192, 0, 0)
    hatchAnimal.BackgroundTransparency = 1
    hatchAnimal.TextColor3 = C_PURPLE
    hatchAnimal.TextXAlignment = Enum.TextXAlignment.Left
    hatchAnimal.Font = Enum.Font.Code; hatchAnimal.TextSize = 9
    hatchAnimal.TextTruncate = Enum.TextTruncate.AtEnd
    hatchAnimal.Parent = row

    local scoreLbl = Instance.new("TextLabel")
    scoreLbl.Size = UDim2.new(0, 50, 1, 0); scoreLbl.Position = UDim2.new(0, 296, 0, 0)
    scoreLbl.BackgroundTransparency = 1
    scoreLbl.TextColor3 = C_CYAN
    scoreLbl.TextXAlignment = Enum.TextXAlignment.Center
    scoreLbl.Font = Enum.Font.Code; scoreLbl.TextSize = 10
    scoreLbl.Parent = row

    local espBtn = Instance.new("TextButton")
    espBtn.Size = UDim2.new(0, 28, 0, 14)
    espBtn.Position = UDim2.new(0, 348, 0.5, -7)
    espBtn.BackgroundColor3 = C_ACCENT
    espBtn.BorderSizePixel = 0
    espBtn.Text = "👁"
    espBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    espBtn.Font = Enum.Font.Code; espBtn.TextSize = 9
    espBtn.Parent = row
    Instance.new("UICorner", espBtn).CornerRadius = UDim.new(0, 2)

    local rd = {
        row = row, name = name, luck = luck,
        petKg = petKg, hatchAnimal = hatchAnimal,
        scoreLbl = scoreLbl, esp = espBtn, data = d,
    }

    espBtn.MouseButton1Click:Connect(function()
        if rd.data.broken then return end
        if espGuis[model] and espGuis[model].Parent then
            destroyESP(model)
            espBtn.Text = "👁"
            espBtn.BackgroundColor3 = C_ACCENT
        else
            local p = model:FindFirstChild("Egg")
            if p then
                local isAlert = (rd.data.predKg > ALERT_PETKG_MIN)
                    and (rd.data.hatchLuck > ALERT_LUCK_MIN)
                buildESP(model, p, rd.data, isAlert)
                espBtn.Text = "ON"
                espBtn.BackgroundColor3 = C_GREEN
            end
        end
    end)

    return rd
end

local function updateRow(rd, d)
    rd.data = d
    rd.name.Text = d.shortName
    rd.name.TextColor3 = d.broken and C_RED or C_TXT

    local isAlert = (d.predKg > ALERT_PETKG_MIN)
        and (d.hatchLuck > ALERT_LUCK_MIN)
        and not d.broken

    if isAlert then
        rd.row.BackgroundColor3 = C_ROW_HI
    elseif d.broken then
        rd.row.BackgroundColor3 = C_ROW_BROKEN
    elseif d.hatchAnimal then
        rd.row.BackgroundColor3 = C_ROW_HATCH
    else
        rd.row.BackgroundColor3 = C_ROW
    end

    rd.luck.Text = string.format("%.2f", d.hatchLuck)
    rd.luck.TextColor3 = isAlert and Color3.fromRGB(255, 100, 100) or luckColor(d.hatchLuck)

    rd.petKg.Text = fmtNum(d.predKg)
    rd.petKg.TextColor3 = isAlert and Color3.fromRGB(255, 60, 60) or C_GOLD

    if d.hatchAnimal then
        local rarityStr = d.rarity or "?"
        rd.hatchAnimal.Text = string.format("%s (%s)", d.hatchAnimal, rarityStr)
        rd.hatchAnimal.TextColor3 = getRarityColor(d.rarity)
    else
        rd.hatchAnimal.Text = "—"
        rd.hatchAnimal.TextColor3 = C_SUB
    end

    rd.scoreLbl.Text = fmtNum(d.score)
    rd.scoreLbl.TextColor3 = scoreColor(d.score)

    if d.broken then
        rd.esp.Text = "—"
        rd.esp.BackgroundColor3 = C_ROW_BROKEN
        rd.esp.Active = false
    else
        if espGuis[d.model] and espGuis[d.model].Parent then
            rd.esp.Text = "ON"
            rd.esp.BackgroundColor3 = C_GREEN
        else
            rd.esp.Text = "👁"
            rd.esp.BackgroundColor3 = C_ACCENT
        end
        rd.esp.Active = true
    end
end

local function sortEggs(list)
    table.sort(list, function(a, b)
        local da, db = a.data, b.data
        -- 1) Score tertinggi
        if da.score ~= db.score then return da.score > db.score end
        -- 2) PetKg sebagai tie-breaker
        if da.predKg ~= db.predKg then return da.predKg > db.predKg end
        local aHatch = da.hatchAnimal and 1 or 0
        local bHatch = db.hatchAnimal and 1 or 0
        if aHatch ~= bHatch then return aHatch > bHatch end
        local aAlert = (da.predKg > ALERT_PETKG_MIN) and (da.hatchLuck > ALERT_LUCK_MIN) and not da.broken
        local bAlert = (db.predKg > ALERT_PETKG_MIN) and (db.hatchLuck > ALERT_LUCK_MIN) and not db.broken
        if aAlert ~= bAlert then return aAlert end
        if da.bracketRank ~= db.bracketRank then return da.bracketRank > db.bracketRank end
        return da.hatchLuck > db.hatchLuck
    end)
end

--// ==== MAIN SCAN ====
local function scanEggs()
    local current = {}
    local anyFolder = false
    local missingZones = {}

    for i, pathStr in ipairs(ZonePaths) do
        local zoneNum = ZONES[i]
        local folder = resolvePath(pathStr)
        if folder then
            anyFolder = true
            for _, child in ipairs(folder:GetChildren()) do
                if child:IsA("Model") then
                    local d = getEggData(child)
                    if d then
                        d.zone = zoneNum
                        current[child] = d
                    end
                end
            end
        else
            table.insert(missingZones, zoneNum)
        end
    end

    if not anyFolder then
        status.Text = "❌ zona 12 & 13 tidak ditemukan"
        status.TextColor3 = C_RED
        for model, rd in pairs(rows) do
            if rd.row and rd.row.Parent then rd.row:Destroy() end
        end
        rows = {}
        StopAlert()
        return
    end

    local alertEgg = nil
    for model, d in pairs(current) do
        if not d.broken and d.predKg > ALERT_PETKG_MIN and d.hatchLuck > ALERT_LUCK_MIN then
            alertEgg = d
            break
        end
    end
    if alertEgg and not AlertMuted then PlayAlert() else StopAlert() end
    refreshAlertBtn()

    for model, d in pairs(current) do
        if rows[model] then updateRow(rows[model], d)
        else rows[model] = createRow(model, d) end
    end

    for model, rd in pairs(rows) do
        if not current[model] then
            destroyESP(model)
            if rd.row and rd.row.Parent then rd.row:Destroy() end
            rows[model] = nil
        end
    end

    local list = {}
    for model, d in pairs(current) do
        list[#list+1] = { model = model, data = d }
    end
    sortEggs(list)
    for i, e in ipairs(list) do
        local rd = rows[e.model]
        if rd and rd.row then rd.row.LayoutOrder = i end
    end

    local total, broken, maxPred, alertCount, hatchCount = 0, 0, 0, 0, 0
    local z12count, z13count = 0, 0
    for _, d in pairs(current) do
        total = total + 1
        if d.broken then broken = broken + 1 end
        if d.predKg > maxPred then maxPred = d.predKg end
        if not d.broken and d.predKg > ALERT_PETKG_MIN and d.hatchLuck > ALERT_LUCK_MIN then
            alertCount = alertCount + 1
        end
        if d.hatchAnimal then hatchCount = hatchCount + 1 end
        if d.zone == 12 then z12count = z12count + 1
        elseif d.zone == 13 then z13count = z13count + 1 end
    end

    local zoneStr = string.format("[z12:%d z13:%d]", z12count, z13count)
    if #missingZones > 0 then
        zoneStr = zoneStr .. " miss:" .. table.concat(missingZones, ",")
    end

    if alertCount > 0 then
        status.Text = string.format("%s ⚠ALERT%d | %degg | top %s",
            zoneStr, alertCount, total, fmtNum(maxPred))
        status.TextColor3 = C_RED
    elseif hatchCount > 0 then
        status.Text = string.format("%s 🐾%dhatch | %degg | top %s",
            zoneStr, hatchCount, total, fmtNum(maxPred))
        status.TextColor3 = C_PURPLE
    else
        status.Text = string.format("%s %degg | top %s",
            zoneStr, total, fmtNum(maxPred))
        status.TextColor3 = C_GREEN
    end
end

--// ==== MONITOR LOOP ====
local function ScanPickupsOnce()
    local container = resolvePath(CONTAINER_PATH)
    if not container then return 0, false end
    local current, count, anyAlert = {}, 0, false
    for _, pickup in ipairs(container:GetChildren()) do
        local info = getPickupInfo(pickup)
        if info.rarity or info.price then
            current[pickup] = info
            count += 1
            if matchAnyFilter(info) then anyAlert = true end
            if not KnownPickups[pickup] and matchAnyFilter(info) then
                TotalAlerts += 1
            end
        end
    end
    KnownPickups = current
    return count, anyAlert
end

local function StartMonitor()
    if Monitoring then return end
    Monitoring = true
    KnownPickups = {}
    TotalAlerts = 0
    monBtn.Text = "■MON"
    monBtn.BackgroundColor3 = Color3.fromRGB(40, 60, 40)
    monBtn.TextColor3 = Color3.fromRGB(120, 255, 120)

    if ScanThread then task.cancel(ScanThread) end
    ScanThread = task.spawn(function()
        while Monitoring and gui.Parent do
            pcall(function()
                local count, alert = ScanPickupsOnce()
                if alert and not AlertActive then
                    PlayAlert()
                elseif not alert and AlertActive then
                    StopAlert()
                end
                refreshAlertBtn()
                status.Text = string.format("%s | pickups:%d | alerts:%d",
                    alert and "⚠alert" or "●live", count, TotalAlerts)
                status.TextColor3 = alert and C_RED or C_GREEN
            end)
            task.wait(MON_SCAN_INTERVAL)
        end
    end)
end

local function StopMonitor()
    Monitoring = false
    AlertActive = false
    StopAlert()
    monBtn.Text = "▶MON"
    monBtn.BackgroundColor3 = Color3.fromRGB(60, 30, 30)
    monBtn.TextColor3 = Color3.fromRGB(255, 120, 120)
    if ScanThread then task.cancel(ScanThread) ScanThread = nil end
end

monBtn.MouseButton1Click:Connect(function()
    if Monitoring then StopMonitor() else StartMonitor() end
end)

--// ==== MINIMIZE ====
local minimized = false
local FULL_SIZE = UDim2.new(0, W, 0, MAIN_H)
local MINI_SIZE = UDim2.new(0, W, 0, HEADER_H)

local function setMinimized(state)
    minimized = state
    if minimized then
        for _, obj in ipairs(collapseTargets) do
            if obj and obj.Parent then obj.Visible = false end
        end
        main.Size = MINI_SIZE
        minBtn.Text = "□"
        minBtn.BackgroundColor3 = C_GREEN
    else
        for _, obj in ipairs(collapseTargets) do
            if obj and obj.Parent then obj.Visible = true end
        end
        main.Size = FULL_SIZE
        minBtn.Text = "—"
        minBtn.BackgroundColor3 = Color3.fromRGB(200, 170, 60)
    end
end

minBtn.MouseButton1Click:Connect(function()
    setMinimized(not minimized)
end)

--// ==== CLOSE ====
closeBtn.MouseButton1Click:Connect(function()
    Monitoring = false
    speedLockTarget = nil
    stopSpeedKeeper()
    local hum = getHum()
    if hum and originalSpeed then hum.WalkSpeed = originalSpeed end
    if ScanThread then task.cancel(ScanThread) end
    destroyAllESP()
    StopAlert()
    pcall(function() AlertSound:Destroy() end)
    gui:Destroy()
end)

--// ==== INIT ====
local h0 = getHum()
if h0 then originalSpeed = h0.WalkSpeed end
refreshAlertBtn()
scanEggs()

task.spawn(function()
    while gui.Parent do
        task.wait(SCAN_INTERVAL)
        if not gui.Parent then break end
        pcall(scanEggs)
    end
end)
