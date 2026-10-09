-- ============================================================
-- FARM MONSTER + GUARD + CYCLE (Stand + Briar + Cauldron)
-- v2: Night re-lock safeguard
-- ============================================================
local Players            = game:GetService("Players")
local RunService         = game:GetService("RunService")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local VirtualInputManager= game:GetService("VirtualInputManager")
local VirtualUser        = game:GetService("VirtualUser")
local UserInputService   = game:GetService("UserInputService")
local Lighting           = game:GetService("Lighting")

local player = Players.LocalPlayer

-- ============================================================
-- CONFIG
-- ============================================================
local CONFIG = {
    -- ===== Auto Farm (Monster only) =====
    MONSTER_FOLDER = "Workspace.MonsterVisuals",
    MONSTER_RANGE  = 10,
    WALK_SPEED         = 30,
    CYCLE_WALK_SPEED   = 20,
    ATTACK_COOLDOWN    = 0.12,
    RETARGET_INTERVAL  = 0.1,
    SEARCH_INTERVAL    = 0.3,

    -- ===== Fox Guard =====
    FOX_MODELS_PATH    = "game.Workspace._PetVisualClient.Models",
    FOX_NAME_FILTER    = "VampireFox",
    FOX_MIN_DIST       = 0,
    FOX_MAX_DIST       = 10,
    FOX_CLICK_COOLDOWN = 0.05,
    FOX_SCAN_ACTIVE    = 0.05,
    FOX_SCAN_IDLE      = 0.20,

    -- ===== Cycle =====
    SORE_HOUR   = 15,
    NIGHT_HOUR  = 18,
    PAGI_HOUR   = 6,

    STAND_WALK_STUD     = 60,
    STAND_WAIT_AFTER_FIRE = 1,
    STAND_MOVE_TIMEOUT  = 8,

    BRIAR_FIRE_COUNT    = 2,
    BRIAR_FIRE_GAP      = 1.5,

    PACKET_STAND    = "\020\000\006Garden~\000\192\151\200C\006\129\018C\b\172\003\195",
    PACKET_BRIAR    = "\195\0009\nBriar Rose",

    TARGET_PATH     = { "WitchCauldron", "WitchCauldron", "WitchCauldron", "Part4" },
    WATER_FOLDER_PATH = { "WitchCauldron", "WitchCauldron", "WitchCauldron", "Water" },
    ARRIVE_DISTANCE = 2,
    WALK_TIMEOUT    = 45,
    E_TIMES         = 2,
    E_GAP           = 1,
    E_HOLD          = 0.1,

    POLL_INTERVAL   = 0.2,
    MAX_LOGS        = 200,

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
        ALWAYS_CLEAR_INTERVAL = 5,
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
local locked = false
local sequenceRunning = false

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

-- Lock
local State = {
    locked = false,
    lockPos = nil,
    lockCFrame = nil,
    lockConn = nil,
    velConn = nil,
}

-- ============================================================
-- LOGGER
-- ============================================================
local Logs = {}
local function addLog(tag, msg)
    local entry = string.format("[%s] [%s] %s", os.date("%H:%M:%S"), tag, msg)
    table.insert(Logs, entry)
    if #Logs > CONFIG.MAX_LOGS then table.remove(Logs, 1) end
    print("[Cycle] " .. entry)
end

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

local function getChar()
    local c = player.Character
    if not c then return nil end
    local hum = c:FindFirstChildOfClass("Humanoid")
    local root = c:FindFirstChild("HumanoidRootPart")
    if hum and root then return hum, root, c end
    return nil
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
-- FIRE REMOTE
-- ============================================================
local function fireRemote(packetString)
    local ok, err = pcall(function()
        local args = { buffer.fromstring(packetString) }
        ReplicatedStorage
            :WaitForChild("SharedModules")
            :WaitForChild("Packet")
            :WaitForChild("RemoteEvent")
            :FireServer(unpack(args))
    end)
    if ok then return true
    else addLog("ERR", "Fire gagal: " .. tostring(err)); return false end
end

-- ============================================================
-- MOVE FORWARD
-- ============================================================
local function moveForward(stud)
    local hum, root = getChar()
    if not hum or not root then return false end

    local look = root.CFrame.LookVector
    local dir = Vector3.new(look.X, 0, look.Z)
    if dir.Magnitude < 0.01 then dir = Vector3.new(0, 0, -1) end
    dir = dir.Unit

    local startPos = root.Position
    local targetPos = startPos + dir * stud

    addLog("MOVE", string.format("Walk %d stud...", stud))

    local t0 = tick()
    while tick() - t0 < CONFIG.STAND_MOVE_TIMEOUT do
        local h, r = getChar()
        if not h or not r then break end
        local flatTarget = Vector3.new(targetPos.X, r.Position.Y, targetPos.Z)
        if (flatTarget - r.Position).Magnitude < 1 then break end
        h:MoveTo(flatTarget)
        task.wait(0.05)
    end

    local h, r = getChar()
    if h and r then
        h:Move(Vector3.zero, false)
        task.wait(0.05)
        addLog("MOVE", "Arrived")
        return true, r.Position
    end
    return false
end

-- ============================================================
-- LOCK
-- ============================================================
local function startLock(lockPos)
    if State.lockConn then State.lockConn:Disconnect() end
    if State.velConn then State.velConn:Disconnect() end

    State.locked = true
    locked = true
    State.lockPos = lockPos

    local _, root = getChar()
    if root then State.lockCFrame = root.CFrame end

    State.lockConn = RunService.RenderStepped:Connect(function()
        if not State.locked then return end
        local h, r = getChar()
        if not h or not r then return end
        r.AssemblyLinearVelocity = Vector3.zero
        r.AssemblyAngularVelocity = Vector3.zero
        r.Velocity = Vector3.zero
        r.RotVelocity = Vector3.zero
        if State.lockPos and (State.lockPos - r.Position).Magnitude > 0.3 then
            r.CFrame = State.lockCFrame
        end
        h:Move(Vector3.zero, false)
        h.WalkSpeed = 0
        h.JumpPower = 0
        h.JumpHeight = 0
    end)

    State.velConn = RunService.Stepped:Connect(function()
        if not State.locked then return end
        local _, r = getChar()
        if not r then return end
        r.AssemblyLinearVelocity = Vector3.zero
        r.AssemblyAngularVelocity = Vector3.zero
    end)

    addLog("LOCK", string.format("Locked at (%.1f, %.1f, %.1f)",
        lockPos.X, lockPos.Y, lockPos.Z))
end

local function stopLock()
    if not State.locked then return end
    State.locked = false
    locked = false
    State.lockPos = nil
    State.lockCFrame = nil
    if State.lockConn then State.lockConn:Disconnect() State.lockConn = nil end
    if State.velConn then State.velConn:Disconnect() State.velConn = nil end
    local h = getChar()
    if h then
        h.WalkSpeed = CONFIG.WALK_SPEED
        h.JumpPower = 50
        h.JumpHeight = 7.2
    end
    addLog("LOCK", "Unlocked")
end

-- ============================================================
-- FARM MODE (Monster only)
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

local function runFarmMode(hum, root, monsterFolder, myToken, isRunningFn)
    local currentTarget, currentRp = nil, nil
    local lastSearch = 0

    while isRunningFn() and myToken == runToken and not busy and not locked do
        local myPos = root.Position
        local now = tick()

        if (now - lastSearch) >= CONFIG.SEARCH_INTERVAL or not currentTarget then
            lastSearch = now
            local mTarget, mRp = findNearestMonster(monsterFolder, myPos)
            currentTarget = mTarget
            currentRp = mRp
        end

        if not currentTarget or not currentRp or not currentRp.Parent then
            currentTarget, currentRp = nil, nil
            hum:Move(Vector3.zero, false)
            task.wait(0.15)
        else
            local targetPos = currentRp.Position
            local flatDir = Vector3.new(targetPos.X - myPos.X, 0, targetPos.Z - myPos.Z)
            local dist = flatDir.Magnitude

            if dist <= CONFIG.MONSTER_RANGE then
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
            if not locked then
                local char = player.Character
                if char then
                    local hum = char:FindFirstChildOfClass("Humanoid")
                    if hum and hum.WalkSpeed ~= CONFIG.WALK_SPEED then
                        pcall(function() hum.WalkSpeed = CONFIG.WALK_SPEED end)
                    end
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
    if not monsterFolder then
        addLog("ERR", "Monster folder tidak ditemukan")
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
        if busy or locked then
            task.wait(0.2)
        else
            runFarmMode(hum, root, monsterFolder, myToken, isRunningFn)
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
    addLog("FARM", "Started")
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
    addLog("FARM", "Stopped")
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
    addLog("GUARD", "Fox guard ON")
end

local function stopFoxGuard()
    foxEnabled = false
    if foxConn then foxConn:Disconnect() foxConn = nil end
    addLog("GUARD", "Fox guard OFF")
end

-- ============================================================
-- WALK KE PART4
-- ============================================================
local function walkToPart4()
    local target = resolveArrayPath(CONFIG.TARGET_PATH)
    if not target or not target:IsA("BasePart") then
        addLog("ERR", "Part4 gak ada")
        return false
    end

    local char = player.Character
    if not char then return false end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return false end

    addLog("MOVE", "Walk ke Part4...")

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

-- ============================================================
-- CYCLE ACTIONS
-- ============================================================

-- SORE (15:00): stop farm + fire stand + walk 60 + lock
local function doSoreSequence()
    if sequenceRunning then return false end
    if State.locked then
        addLog("INFO", "Sore: already locked, skip")
        return false
    end

    local hum, root = getChar()
    if not hum or not root then
        addLog("ERR", "Sore: no character, abort")
        return false
    end

    sequenceRunning = true
    busy = true
    addLog("ACTION", "=== SORE 15:00 → stand + walk + lock ===")

    stopFarm()

    if fireRemote(CONFIG.PACKET_STAND) then
        addLog("ACTION", "Stand fired OK")
    else
        addLog("ERR", "Stand fire failed")
    end

    task.wait(CONFIG.STAND_WAIT_AFTER_FIRE)

    local moved, newPos = moveForward(CONFIG.STAND_WALK_STUD)

    if moved and newPos then
        startLock(newPos)
    else
        local _, r = getChar()
        if r then startLock(r.Position) end
    end

    addLog("ACTION", "=== SORE DONE ===")
    sequenceRunning = false
    return true
end

-- MALAM (18:00): re-lock safeguard + fire Briar 2x
local function doNightSequence()
    if sequenceRunning then return false end
    sequenceRunning = true
    addLog("ACTION", "=== MALAM 18:00 → safeguard lock + briar x" .. CONFIG.BRIAR_FIRE_COUNT .. " ===")

    -- === SAFEGUARD: kalau sore lock gagal, coba lock sekarang ===
    if not State.locked then
        local _, root = getChar()
        if root then
            addLog("LOCK", "Safeguard: sore lock gagal, re-lock di posisi sekarang")
            startLock(root.Position)
        else
            addLog("ERR", "Safeguard: no root, skip lock")
        end
    else
        addLog("LOCK", "Safeguard: sudah locked, skip re-lock")
    end

    -- Fire Briar 2x
    for i = 1, CONFIG.BRIAR_FIRE_COUNT do
        if stopFlag then break end
        if fireRemote(CONFIG.PACKET_BRIAR) then
            addLog("ACTION", string.format("Briar #%d fired", i))
        else
            addLog("ERR", string.format("Briar #%d failed", i))
        end
        if i < CONFIG.BRIAR_FIRE_COUNT then
            task.wait(CONFIG.BRIAR_FIRE_GAP)
        end
    end

    addLog("ACTION", "=== MALAM DONE ===")
    sequenceRunning = false
    return true
end

-- PAGI (06:00): unlock + walk part4 + E 2x + resume farm
local function doPagiSequence()
    if sequenceRunning then return false end
    sequenceRunning = true
    busy = true
    addLog("ACTION", "=== PAGI 06:00 → unlock + cauldron + resume farm ===")

    stopLock()

    local ok = walkToPart4()
    if stopFlag then
        busy = false
        sequenceRunning = false
        return false
    end

    if ok then
        addLog("ACTION", "Sampai Part4 → E")
        task.wait(0.3)
        for i = 1, CONFIG.E_TIMES do
            if stopFlag then break end
            forcePrompt(findPromptInWater())
            addLog("ACTION", "E #" .. i)
            tapE()
            if i < CONFIG.E_TIMES then task.wait(CONFIG.E_GAP) end
        end
    else
        addLog("ERR", "Walk Part4 gagal")
    end

    busy = false
    if running and not stopFlag then
        startFarm()
    end

    addLog("ACTION", "=== PAGI DONE ===")
    sequenceRunning = false
    return true
end

-- ============================================================
-- PHASE WATCHER (transition-based, anti-skip)
-- ============================================================
local phaseConn = nil
local lastHour = -1

local function startPhaseWatcher()
    if phaseConn then phaseConn:Disconnect() end
    lastHour = math.floor(Lighting.ClockTime or 0)

    phaseConn = RunService.Heartbeat:Connect(function()
        if not running or stopFlag then return end
        local ct = Lighting.ClockTime or 0
        local hour = math.floor(ct)

        if hour ~= lastHour then
            local prev = lastHour
            lastHour = hour

            -- SORE: 15 → 18
            if prev < CONFIG.SORE_HOUR and hour >= CONFIG.SORE_HOUR and hour < CONFIG.NIGHT_HOUR then
                task.spawn(doSoreSequence)
            end

            -- MALAM: 18 → pagi
            if prev < CONFIG.NIGHT_HOUR and hour >= CONFIG.NIGHT_HOUR then
                task.spawn(doNightSequence)
            end

            -- PAGI: 6 → 15
            if prev < CONFIG.PAGI_HOUR and hour >= CONFIG.PAGI_HOUR and hour < CONFIG.SORE_HOUR then
                task.spawn(doPagiSequence)
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
    addLog("INFO", "▶ START — farm + guard + cycle aktif")
end

local function stopAll()
    stopFlag = true
    running = false
    stopPhaseWatcher()
    stopFarm()
    stopFoxGuard()
    stopLock()
    if _G.__SetToggle then _G.__SetToggle(false) end
    addLog("INFO", "■ STOP")
end

-- ============================================================
-- GUI: TOGGLE ON/OFF DI KANAN
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
screenGui.Name = "FarmCycleToggle"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = player:WaitForChild("PlayerGui")

local W, H = 100, 40

local frame = Instance.new("Frame")
frame.Size = UDim2.new(0, W, 0, H)
frame.Position = UDim2.new(1, -W - 12, 0.5, -H / 2)
frame.BackgroundColor3 = COLORS.bg
frame.BackgroundTransparency = 0.1
frame.BorderSizePixel = 0
frame.Active = false
frame.Parent = screenGui
corner(frame, 8)

local stroke = Instance.new("UIStroke")
stroke.Color = COLORS.stroke
stroke.Transparency = 0.3
stroke.Thickness = 1.5
stroke.Parent = frame

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
addLog("INFO", "Loaded | toggle ON/OFF di kanan layar")
addLog("INFO", "Cycle: 15:00 stand+walk+lock | 18:00 safeguard+briar x2 | 06:00 unlock+cauldron+farm")
