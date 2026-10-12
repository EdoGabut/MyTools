-- ============================================================
-- FARM PUMPKIN + MONSTER + GUARD + NIGHT/DAY CYCLE
-- (tanpa GUI killer)
-- ============================================================
local Players            = game:GetService("Players")
local RunService         = game:GetService("RunService")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local TweenService       = game:GetService("TweenService")
local VirtualInputManager= game:GetService("VirtualInputManager")
local VirtualUser        = game:GetService("VirtualUser")
local UserInputService   = game:GetService("UserInputService")
local Lighting           = game:GetService("Lighting")

local player = Players.LocalPlayer

-- ============================================================
-- CONFIG
-- ============================================================
local CONFIG = {
    -- ===== Auto Farm =====
    MONSTER_FOLDER = "Workspace.MonsterVisuals",
    PUMPKIN_FOLDER = "Workspace.Pumpkins",
    SEEDPACK_PATH  = "Workspace.Map.SeedPackSpawnServerLocations",
    MONSTER_RANGE  = 10,
    PUMPKIN_RANGE  = 8,
    WALK_SPEED         = 30,
    CYCLE_WALK_SPEED   = 20,
    ATTACK_COOLDOWN    = 0.12,
    RETARGET_INTERVAL  = 0.1,
    SEARCH_INTERVAL    = 0.3,
    SEEDPACK_STOP_DIST      = 5,
    SEEDPACK_MOVE_TIMEOUT   = 15,
    SEEDPACK_MOVE_REFRESH   = 0.15,
    SEEDPACK_IDLE_DELAY     = 0.5,
    SEEDPACK_TRIGGER_COOLDOWN = 0.15,
    SEEDPACK_TRIGGERED_TTL  = 1.5,
    SEEDPACK_BETTER_MARGIN  = 10,

    -- ===== Fox Guard =====
    FOX_MODELS_PATH    = "game.Workspace._PetVisualClient.Models",
    FOX_NAME_FILTER    = "VampireFox",
    FOX_MIN_DIST       = 0,
    FOX_MAX_DIST       = 10,
    FOX_CLICK_COOLDOWN = 0.05,
    FOX_SCAN_ACTIVE    = 0.05,
    FOX_SCAN_IDLE      = 0.20,
    GUARD_ENABLED      = true,

    -- ===== Cycle =====
    NIGHT_START = 18,
    NIGHT_END   = 6,
    PACKET_STRING   = "\195\0009\nBriar Rose",

    TARGET_PATH     = { "WitchCauldron", "WitchCauldron", "WitchCauldron", "Part4" },
    WATER_FOLDER_PATH = { "WitchCauldron", "WitchCauldron", "WitchCauldron", "Water" },
    ARRIVE_DISTANCE = 2,
    WALK_TIMEOUT    = 45,
    E_TIMES         = 2,
    E_GAP           = 1,
    E_HOLD          = 0.1,

    -- ===== Clear Map =====
    CLEAR_MAP = {
        DELETE_CHILDREN = {
            "Workspace.Map.Middle",
            "Workspace.Map.Stands",
            "Workspace.NPCS",
            "Workspace.ExplorerStand",
            "Workspace.AuctionStand",
        },
        CLEAR_ALL_CHILDREN = {
            "Workspace.Gardens",
        },
        DISABLE_COLLIDER = {
            "Workspace.WitchCauldron",
        },
        ALWAYS_CLEAR_INTERVAL = 5,  -- tiap 5 detik clear WildPetSpawns
    },
    ALWAYS_CLEAR_CHILDREN = {
        "Workspace.Map.WildPetSpawns",
    },
}

-- ============================================================
-- STATE
-- ============================================================
local running = false
local stopFlag = false
local busy = false
local lastPhase = nil

local isRunning = false
local runToken = 0
local activeHumanoid = nil
local lastClickTime = 0
local speedLoopToken = 0

-- Fox
local foxEnabled = false
local foxLastScan = 0
local foxLastClick = 0
local foxConn = nil
local foxIdleState = true
local foxTotal = 0
local foxInRange = 0

-- ============================================================
-- HELPERS
-- ============================================================
local function resolvePath(pathStr)
    if not pathStr or pathStr == "" then return nil end
    pathStr = pathStr:gsub("^%s+", ""):gsub("%s+$", "")
    local segments = {}
    for seg in pathStr:gmatch("[^%.]+") do table.insert(segments, seg) end
    if #segments == 0 then return nil end
    local node = game
    if segments[1] == "game" then table.remove(segments, 1) end
    for _, seg in ipairs(segments) do
        if not node then return nil end
        if seg == "LocalPlayer" then node = player
        else node = node:FindFirstChild(seg) end
    end
    return node
end

local function resolveArrayPath(path)
    local current = workspace
    for _, name in ipairs(path) do
        if not current then return nil end
        current = current:FindFirstChild(name)
    end
    return current
end

local function findRootPart(model)
    if not model or not model.Parent then return nil end
    local rp = model:FindFirstChild("RootPart")
    if rp and rp:IsA("BasePart") then return rp end
    rp = model:FindFirstChild("HumanoidRootPart")
    if rp and rp:IsA("BasePart") then return rp end
    if model.PrimaryPart and model.PrimaryPart:IsA("BasePart") then return model.PrimaryPart end
    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA("BasePart") then return d end
    end
    return nil
end

local function getPromptPosition(prompt)
    if not prompt or not prompt.Parent then return nil end
    local parent = prompt.Parent
    if parent:IsA("BasePart") then return parent.Position end
    if parent:IsA("Attachment") and parent.Parent and parent.Parent:IsA("BasePart") then
        return parent.Parent.Position
    end
    for _, d in ipairs(parent:GetDescendants()) do
        if d:IsA("BasePart") then return d.Position end
    end
    if parent.Parent then
        for _, d in ipairs(parent.Parent:GetDescendants()) do
            if d:IsA("BasePart") then return d.Position end
        end
    end
    return nil
end

local function isNight()
    local h = (Lighting.ClockTime or 12) % 24
    return h >= CONFIG.NIGHT_START or h < CONFIG.NIGHT_END
end

local function log(msg)
    print("[Farm] " .. msg)
end

-- ============================================================
-- CLEAR MAP
-- ============================================================
local function cmLog(msg)
    print(string.format("[ClearMap %s] %s", os.date("%H:%M:%S"), msg))
end

local function cm_deleteChildren(path)
    local t = resolvePath(path)
    if not t then cmLog("✗ tidak ditemukan: " .. path); return end
    local n = 0
    for _, c in ipairs(t:GetChildren()) do
        if pcall(function() c:Destroy() end) then n += 1 end
    end
    cmLog(string.format("✓ %s → hapus %d anak", path, n))
end

local function cm_clearAllChildren(path)
    local t = resolvePath(path)
    if not t then cmLog("✗ tidak ditemukan: " .. path); return end
    local before = #t:GetChildren()
    if pcall(function() t:ClearAllChildren() end) then
        cmLog(string.format("✓ %s → ClearAllChildren (%d → 0)", path, before))
    end
end

local function cm_disableCollider(path)
    local t = resolvePath(path)
    if not t then cmLog("✗ tidak ditemukan: " .. path); return end
    local n = 0
    local function disablePart(p)
        if not p:IsA("BasePart") then return end
        p.CanCollide = false
        if p.CanTouch ~= nil then p.CanTouch = false end
        if p.CanQuery ~= nil then p.CanQuery = false end
        n += 1
    end
    disablePart(t)
    for _, d in ipairs(t:GetDescendants()) do disablePart(d) end
    cmLog(string.format("✓ %s → disable collider %d part", path, n))
end

local function runClearMapOnce()
    cmLog("=====================================")
    cmLog("START")
    for _, p in ipairs(CONFIG.CLEAR_MAP.DELETE_CHILDREN) do cm_deleteChildren(p) end
    for _, p in ipairs(CONFIG.CLEAR_MAP.CLEAR_ALL_CHILDREN) do cm_clearAllChildren(p) end
    for _, p in ipairs(CONFIG.CLEAR_MAP.DISABLE_COLLIDER) do cm_disableCollider(p) end
    cmLog("SELESAI")
end

local function runAlwaysClear()
    while running and not stopFlag do
        for _, p in ipairs(CONFIG.ALWAYS_CLEAR_CHILDREN) do
            local t = resolvePath(p)
            if t then
                for _, c in ipairs(t:GetChildren()) do
                    pcall(function() c:Destroy() end)
                end
            end
        end
        task.wait(CONFIG.CLEAR_MAP.ALWAYS_CLEAR_INTERVAL)
    end
end

-- ============================================================
-- INPUT
-- ============================================================
local function pressE()
    pcall(function()
        VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game)
    end)
end

local function releaseE()
    pcall(function()
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game)
    end)
end

local function tapE(holdTime)
    holdTime = holdTime or CONFIG.E_HOLD
    pressE()
    task.wait(holdTime)
    releaseE()
end

local function clickLMB()
    if pcall(function()
        VirtualInputManager:SendMouseButtonEvent(0, 0, 0, true, game, 1)
        task.wait(0.02)
        VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 1)
    end) then return true end
    if pcall(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton1(Vector2.new(0, 0))
    end) then return true end
    local char = player.Character
    if char then
        local tool = char:FindFirstChildOfClass("Tool")
        if tool then
            pcall(function() tool:Activate() end)
            return true
        end
    end
    return false
end

-- ============================================================
-- SEEDPACK
-- ============================================================
local function getSeedPackPrompts()
    local folder = resolvePath(CONFIG.SEEDPACK_PATH)
    if not folder then return {} end
    local list = {}
    for _, obj in ipairs(folder:GetDescendants()) do
        if obj:IsA("ProximityPrompt") then table.insert(list, obj) end
    end
    return list
end

local function findNearestSeedPack(prompts, myPos, skipSet)
    local nearest, nearestDist = nil, math.huge
    for _, p in ipairs(prompts) do
        if p and p.Parent and not (skipSet and skipSet[p]) then
            local pos = getPromptPosition(p)
            if pos then
                local d = (pos - myPos).Magnitude
                if d < nearestDist then
                    nearestDist = d
                    nearest = p
                end
            end
        end
    end
    return nearest, nearestDist
end

local function triggerSeedPack(prompt)
    if not prompt or not prompt.Parent then return false end
    pcall(function()
        prompt.HoldDuration = 0
        prompt.RequiresLineOfSight = false
        prompt.Enabled = true
        prompt.KeyboardKeyCode = Enum.KeyCode.E
        prompt.ClickablePrompt = false
        prompt.MaxActivationDistance = 30
    end)
    tapE(0.07)
    return true
end

local function runSeedPackMode(hum, root, myToken, isRunningFn)
    local triggeredSet = {}
    local handled = false

    while isRunningFn() and myToken == runToken and not busy do
        local now = tick()
        for prompt, t in pairs(triggeredSet) do
            if (now - t) > CONFIG.SEEDPACK_TRIGGERED_TTL or not prompt.Parent then
                triggeredSet[prompt] = nil
            end
        end

        local prompts = getSeedPackPrompts()
        if #prompts == 0 then
            if handled then
                task.wait(CONFIG.SEEDPACK_IDLE_DELAY)
                if #getSeedPackPrompts() == 0 then return true end
            else
                return false
            end
        else
            handled = true
        end

        local myPos = root.Position
        local nearest = findNearestSeedPack(prompts, myPos, triggeredSet)

        if not nearest then
            task.wait(CONFIG.SEEDPACK_IDLE_DELAY)
        else
            local currentTarget = nearest

            while isRunningFn() and myToken == runToken and not busy do
                if not currentTarget or not currentTarget.Parent then
                    local newPrompts = getSeedPackPrompts()
                    if #newPrompts == 0 then return true end
                    local newNearest = findNearestSeedPack(newPrompts, root.Position, triggeredSet)
                    if not newNearest then break end
                    currentTarget = newNearest
                end

                local myPos2 = root.Position
                local targetPos = getPromptPosition(currentTarget)
                if not targetPos then break end
                local dist = (targetPos - myPos2).Magnitude

                if dist <= CONFIG.SEEDPACK_STOP_DIST then
                    pcall(function() hum:MoveTo(root.Position) end)
                    triggerSeedPack(currentTarget)
                    triggeredSet[currentTarget] = tick()
                    task.wait(CONFIG.SEEDPACK_TRIGGER_COOLDOWN)
                    break
                end

                hum:MoveTo(targetPos)
                task.wait(CONFIG.SEEDPACK_MOVE_REFRESH)
            end
        end
    end
    return true
end

-- ============================================================
-- FARM MODE
-- ============================================================
local function findNearestMonster(monsterFolder, myPos)
    local nearest, nearestRp, nearestDist = nil, nil, math.huge
    if not monsterFolder then return nil, nil end
    for _, child in ipairs(monsterFolder:GetChildren()) do
        if child:IsA("Model") then
            local rp = findRootPart(child)
            if rp and rp.Parent then
                local d = (rp.Position - myPos).Magnitude
                if d < nearestDist then
                    nearestDist = d
                    nearest = child
                    nearestRp = rp
                end
            end
        end
    end
    return nearest, nearestRp, nearestDist
end

local function findNearestPumpkin(pumpkinFolder, myPos)
    local nearest, nearestRp, nearestDist = nil, nil, math.huge
    if not pumpkinFolder then return nil, nil end
    for _, child in ipairs(pumpkinFolder:GetChildren()) do
        local rp
        if child:IsA("Model") then rp = findRootPart(child)
        elseif child:IsA("BasePart") then rp = child end
        if rp and rp.Parent then
            local d = (rp.Position - myPos).Magnitude
            if d < nearestDist then
                nearestDist = d
                nearest = child
                nearestRp = rp
            end
        end
    end
    return nearest, nearestRp, nearestDist
end

local function runFarmMode(hum, root, monsterFolder, pumpkinFolder, myToken, isRunningFn)
    local currentTarget, currentRp, currentKind = nil, nil, nil
    local lastSearch = 0

    while isRunningFn() and myToken == runToken and not busy do
        local prompts = getSeedPackPrompts()
        if #prompts > 0 then return end

        local myPos = root.Position
        local now = tick()

        local monsterTarget, monsterRp = findNearestMonster(monsterFolder, myPos)

        if monsterTarget then
            if currentKind ~= "monster" or currentTarget ~= monsterTarget then
                currentTarget = monsterTarget
                currentRp = monsterRp
                currentKind = "monster"
            end
        else
            if currentKind == "pumpkin" and currentTarget and (not currentTarget.Parent or not currentRp or not currentRp.Parent) then
                currentTarget, currentRp, currentKind = nil, nil, nil
            end
            if currentKind ~= "pumpkin" or not currentTarget then
                if (now - lastSearch) >= CONFIG.SEARCH_INTERVAL then
                    lastSearch = now
                    local pTarget, pRp = findNearestPumpkin(pumpkinFolder, myPos)
                    if pTarget then
                        currentTarget = pTarget
                        currentRp = pRp
                        currentKind = "pumpkin"
                    else
                        currentTarget, currentRp, currentKind = nil, nil, nil
                    end
                end
            end
        end

        if not currentTarget or not currentRp or not currentRp.Parent then
            hum:Move(Vector3.zero, false)
            task.wait(0.15)
        else
            local targetPos = currentRp.Position
            local flatDir = Vector3.new(targetPos.X - myPos.X, 0, targetPos.Z - myPos.Z)
            local dist = flatDir.Magnitude
            local range = (currentKind == "monster") and CONFIG.MONSTER_RANGE or CONFIG.PUMPKIN_RANGE

            if dist <= range then
                hum:Move(Vector3.zero, false)
                local lookAt = CFrame.lookAt(myPos, Vector3.new(targetPos.X, myPos.Y, targetPos.Z))
                root.CFrame = CFrame.new(myPos) * (lookAt - lookAt.Position)

                local tnow = tick()
                if (tnow - lastClickTime) >= CONFIG.ATTACK_COOLDOWN then
                    lastClickTime = tnow
                    clickLMB()
                end
                task.wait(0.03)
            else
                local goal = Vector3.new(targetPos.X, myPos.Y, targetPos.Z)
                hum:MoveTo(goal)
                task.wait(CONFIG.RETARGET_INTERVAL)
            end
        end
    end
end

-- ============================================================
-- MAIN FARM LOOP
-- ============================================================
local function startSpeedKeeper()
    speedLoopToken += 1
    local myToken = speedLoopToken
    task.spawn(function()
        while myToken == speedLoopToken do
            local char = player.Character
            if char then
                local hum = char:FindFirstChildOfClass("Humanoid")
                if hum and hum.WalkSpeed ~= CONFIG.WALK_SPEED then
                    pcall(function() hum.WalkSpeed = CONFIG.WALK_SPEED end)
                end
            end
            task.wait(0.1)
        end
    end)
end

local function stopSpeedKeeper()
    speedLoopToken += 1
end

local function mainFarmLoop()
    local monsterFolder = resolvePath(CONFIG.MONSTER_FOLDER)
    local pumpkinFolder = resolvePath(CONFIG.PUMPKIN_FOLDER)
    if not monsterFolder and not pumpkinFolder then
        log("❌ Monster & Pumpkin folder tidak ditemukan")
        return
    end

    local char = player.Character or player.CharacterAdded:Wait()
    local hum = char:WaitForChild("Humanoid")
    local root = char:WaitForChild("HumanoidRootPart")

    hum.AutoRotate = true
    hum.WalkSpeed = CONFIG.WALK_SPEED
    activeHumanoid = hum

    runToken += 1
    local myToken = runToken
    local function isRunningFn() return isRunning and myToken == runToken end

    while isRunningFn() and hum.Health > 0 do
        if not root.Parent then break end
        if busy then
            task.wait(0.1)
        else
            local prompts = getSeedPackPrompts()
            if #prompts > 0 then
                runSeedPackMode(hum, root, myToken, isRunningFn)
            else
                runFarmMode(hum, root, monsterFolder, pumpkinFolder, myToken, isRunningFn)
            end
        end
    end

    if activeHumanoid == hum and hum.Parent then
        pcall(function() hum:Move(Vector3.zero, false) end)
    end
end

local function startFarm()
    if isRunning then return end
    isRunning = true
    startSpeedKeeper()
    task.spawn(mainFarmLoop)
end

local function stopFarm()
    isRunning = false
    runToken += 1
    local hum = activeHumanoid
    activeHumanoid = nil
    if hum and hum.Parent then
        pcall(function()
            hum:Move(Vector3.zero, false)
            local root = hum.RootPart
            if root then hum:MoveTo(root.Position) end
        end)
    end
    stopSpeedKeeper()
end

-- ============================================================
-- FOX GUARD
-- ============================================================
local function scanFoxes(myPos)
    local container = resolvePath(CONFIG.FOX_MODELS_PATH)
    if not container then foxTotal, foxInRange = 0, 0 return end
    local near, cnt, tot = math.huge, 0, 0
    local minD, maxD = CONFIG.FOX_MIN_DIST, CONFIG.FOX_MAX_DIST
    local filter = CONFIG.FOX_NAME_FILTER:lower()
    for _, child in ipairs(container:GetChildren()) do
        if child:IsA("Model") and child.Name:lower():find(filter, 1, true) then
            tot += 1
            local rp = findRootPart(child)
            if rp then
                local d = (rp.Position - myPos).Magnitude
                if d < near then near = d end
                if d >= minD and d <= maxD then cnt += 1 end
            end
        end
    end
    foxTotal, foxInRange = tot, cnt
end

local function startFoxGuard()
    if foxConn then foxConn:Disconnect() end
    foxEnabled = true
    foxConn = RunService.Heartbeat:Connect(function()
        if not foxEnabled then return end
        local now = tick()
        local interval = foxIdleState and CONFIG.FOX_SCAN_IDLE or CONFIG.FOX_SCAN_ACTIVE
        if now - foxLastScan >= interval then
            foxLastScan = now
            local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
            if not root then return end
            scanFoxes(root.Position)
            foxIdleState = (foxTotal == 0)
        end
        if foxTotal == 0 then return end
        if foxInRange > 0 then
            if now - foxLastClick >= CONFIG.FOX_CLICK_COOLDOWN then
                foxLastClick = now
                clickLMB()
            end
        end
    end)
end

local function stopFoxGuard()
    foxEnabled = false
    if foxConn then foxConn:Disconnect() foxConn = nil end
end

-- ============================================================
-- FIRE REMOTE
-- ============================================================
local function fireBriar()
    local ok, err = pcall(function()
        local args = { buffer.fromstring(CONFIG.PACKET_STRING) }
        ReplicatedStorage
            :WaitForChild("SharedModules")
            :WaitForChild("Packet")
            :WaitForChild("RemoteEvent")
            :FireServer(unpack(args))
    end)
    if ok then log("📦 Briar fired")
    else log("❌ Fire gagal: " .. tostring(err)) end
    return ok
end

-- ============================================================
-- WALK KE PART4
-- ============================================================
local function walkToPart4()
    local target = resolveArrayPath(CONFIG.TARGET_PATH)
    if not target or not target:IsA("BasePart") then
        log("❌ Part4 gak ada")
        return false
    end

    local char = player.Character
    if not char then return false end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return false end

    log("🚶 Walk ke Part4...")

    local arrived = false
    local tStart = tick()
    local conn
    conn = RunService.Heartbeat:Connect(function()
        if stopFlag then conn:Disconnect() return end
        if tick() - tStart > CONFIG.WALK_TIMEOUT then conn:Disconnect() return end

        local c = player.Character
        if not c then conn:Disconnect() return end
        local h = c:FindFirstChildOfClass("Humanoid")
        if not h then conn:Disconnect() return end
        local root = c:FindFirstChild("HumanoidRootPart")
        if not root then conn:Disconnect() return end

        local tgt = resolveArrayPath(CONFIG.TARGET_PATH)
        if not tgt then conn:Disconnect() return end

        local myPos = root.Position
        local tgtPos = tgt.Position
        local flatDist = (Vector3.new(myPos.X, 0, myPos.Z) - Vector3.new(tgtPos.X, 0, tgtPos.Z)).Magnitude

        if flatDist <= CONFIG.ARRIVE_DISTANCE then
            arrived = true
            pcall(function() h:MoveTo(root.Position) end)
            conn:Disconnect()
            return
        end

        h.WalkSpeed = CONFIG.CYCLE_WALK_SPEED
        h:MoveTo(tgtPos)
    end)

    while not stopFlag and not arrived do
        if tick() - tStart > CONFIG.WALK_TIMEOUT then break end
        task.wait(0.1)
    end
    if conn.Connected then conn:Disconnect() end
    return arrived
end

-- ============================================================
-- PROMPT DI WATER (E 2x)
-- ============================================================
local function findPromptInWater()
    local water = resolveArrayPath(CONFIG.WATER_FOLDER_PATH)
    if not water then return nil end
    for _, d in ipairs(water:GetDescendants()) do
        if d:IsA("ProximityPrompt") then return d end
    end
    return nil
end

local function forcePrompt(prompt)
    if not prompt then return end
    pcall(function()
        prompt.HoldDuration = 0
        prompt.RequiresLineOfSight = false
        prompt.Enabled = true
        prompt.KeyboardKeyCode = Enum.KeyCode.E
        prompt.ClickablePrompt = false
        prompt.MaxActivationDistance = 30
    end)
end

local function doDayAction()
    if busy then return end
    busy = true
    log("☀️ SIANG → walk + E 2x")

    stopSpeedKeeper()

    local ok = walkToPart4()
    if stopFlag then busy = false return end

    if ok then
        log("✅ Sampai Part4 → E")
        task.wait(0.3)
        for i = 1, CONFIG.E_TIMES do
            if stopFlag then break end
            forcePrompt(findPromptInWater())
            log("E #" .. i)
            tapE()
            if i < CONFIG.E_TIMES then task.wait(CONFIG.E_GAP) end
        end
    else
        log("❌ Walk gagal")
    end

    busy = false
    log("✓ Balik farming")
    if isRunning then startSpeedKeeper() end
end

-- ============================================================
-- NIGHT ACTION
-- ============================================================
local function doNightAction()
    if busy then return end
    busy = true
    log("🌙 MALAM → fire Briar")
    fireBriar()
    busy = false
    log("✓ Balik farming")
end

-- ============================================================
-- PHASE WATCHER
-- ============================================================
local phaseConn = nil

local function startPhaseWatcher()
    if phaseConn then phaseConn:Disconnect() end
    lastPhase = isNight() and "night" or "day"

    phaseConn = RunService.Heartbeat:Connect(function()
        if not running or stopFlag then return end
        local now = isNight() and "night" or "day"
        if now ~= lastPhase then
            lastPhase = now
            if now == "night" then
                task.spawn(doNightAction)
            else
                task.spawn(doDayAction)
            end
        end
    end)
end

local function stopPhaseWatcher()
    if phaseConn then phaseConn:Disconnect() phaseConn = nil end
end

-- ============================================================
-- START / STOP
-- ============================================================
local function startAll()
    if running then return end
    running = true
    stopFlag = false
    busy = false

    startFarm()
    startFoxGuard()
    startPhaseWatcher()
    task.spawn(runAlwaysClear)

    if _G.__SetToggle then _G.__SetToggle(true) end
    log("▶ START — farming + guard + cycle aktif")
end

local function stopAll()
    stopFlag = true
    running = false
    stopPhaseWatcher()
    stopFarm()
    stopFoxGuard()
    if _G.__SetToggle then _G.__SetToggle(false) end
    log("■ STOP")
end

-- ============================================================
-- GUI: TOGGLE ON/OFF DI KANAN, NO DRAG, BISA CLOSE
-- ============================================================
local COLORS = {
    bg      = Color3.fromRGB(22, 22, 28),
    text    = Color3.fromRGB(235, 235, 240),
    textDim = Color3.fromRGB(160, 160, 175),
    green   = Color3.fromRGB(80, 200, 120),
    red     = Color3.fromRGB(200, 70, 70),
    stroke  = Color3.fromRGB(60, 60, 72),
}

local function corner(p, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, r or 8)
    c.Parent = p
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "FarmToggle"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = player:WaitForChild("PlayerGui")

local W, H = 100, 40

local frame = Instance.new("Frame")
frame.Size = UDim2.new(0, W, 0, H)
-- KANAN LAYAR
frame.Position = UDim2.new(1, -W - 12, 0.5, -H / 2)
frame.BackgroundColor3 = COLORS.bg
frame.BackgroundTransparency = 0.1
frame.BorderSizePixel = 0
frame.Active = false   -- NO DRAG
frame.Parent = screenGui
corner(frame, 8)

local stroke = Instance.new("UIStroke")
stroke.Color = COLORS.stroke
stroke.Transparency = 0.3
stroke.Thickness = 1.5
stroke.Parent = frame

-- Tombol toggle (kiri)
local toggleBtn = Instance.new("TextButton")
toggleBtn.Size = UDim2.new(1, -28, 1, -8)
toggleBtn.Position = UDim2.new(0, 4, 0, 4)
toggleBtn.BackgroundColor3 = COLORS.red
toggleBtn.Text = "OFF"
toggleBtn.TextColor3 = COLORS.text
toggleBtn.Font = Enum.Font.GothamBold
toggleBtn.TextSize = 14
toggleBtn.BorderSizePixel = 0
toggleBtn.AutoButtonColor = false
toggleBtn.Parent = frame
corner(toggleBtn, 6)

-- Tombol close (kanan)
local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 20, 1, -8)
closeBtn.Position = UDim2.new(1, -24, 0, 4)
closeBtn.BackgroundColor3 = COLORS.red
closeBtn.Text = "×"
closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 14
closeBtn.BorderSizePixel = 0
closeBtn.AutoButtonColor = false
closeBtn.Parent = frame
corner(closeBtn, 6)

-- ============================================================
-- UI HOOKS
-- ============================================================
_G.__SetToggle = function(on)
    if on then
        toggleBtn.Text = "ON"
        toggleBtn.BackgroundColor3 = COLORS.green
        stroke.Color = COLORS.green
    else
        toggleBtn.Text = "OFF"
        toggleBtn.BackgroundColor3 = COLORS.red
        stroke.Color = COLORS.stroke
    end
end

toggleBtn.MouseButton1Click:Connect(function()
    if running then
        stopAll()
    else
        startAll()
    end
end)

closeBtn.MouseButton1Click:Connect(function()
    stopAll()
    screenGui:Destroy()
end)

player.CharacterAdded:Connect(function()
    if running then stopAll() end
end)

-- ============================================================
-- EXECUTE
-- ============================================================
runClearMapOnce()
_G.__SetToggle(false)
log("Loaded | toggle ON/OFF di kanan layar")
