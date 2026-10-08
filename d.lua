-- ============================================================
-- AUTO FARM + FOX GUARD + NIGHT CYCLE (ALL-IN-ONE)
-- Alur:
--  1) Cek malam → fire packet "Briar Rose"
--  2) Timer 11 menit (farm + guard tetap jalan)
--  3) Timer habis → STOP farm & guard → walk ke Part4
--  4) Sampai → fireproximityprompt() ke CauldronPrompt
--  5) Wait 3 detik
--  6) Ulang dari step 1 (farm + guard hidup lagi)
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
    WITCH_CAULDRON_PATH     = "Workspace.WitchCauldron",
    WITCH_CAULDRON_STOP_DIST = 6,
    CLEAR_MAP = {
        DELETE_CHILDREN = {
            "Workspace.Map.Middle",
            "Workspace.Map.Stands",
            "Workspace.NPCS",
            "Workspace.ExplorerStand",
            "Workspace.AuctionStand",
            "Workspace.Map.WildPetSpawns",
        },
        CLEAR_ALL_CHILDREN = { "Workspace.Gardens" },
        DISABLE_COLLIDER   = { "Workspace.WitchCauldron" },
    },

    -- ===== Fox Guard =====
    FOX_MODELS_PATH    = "game.Workspace._PetVisualClient.Models",
    FOX_NAME_FILTER    = "VampireFox",
    FOX_MIN_DIST       = 0,
    FOX_MAX_DIST       = 10,
    FOX_CLICK_COOLDOWN = 0.05,
    FOX_SCAN_ACTIVE    = 0.05,
    FOX_SCAN_IDLE      = 0.20,

    GUARD_ENABLED = true,

    -- ===== Night Cycle =====
    TARGET_PATH     = { "WitchCauldron", "WitchCauldron", "WitchCauldron", "Part4" },
    PROMPT_PATH     = { "WitchCauldron", "WitchCauldron", "WitchCauldron", "Water", "CauldronPrompt" },
    PACKET_STRING   = "\195\0009\nBriar Rose",
    WAIT_AFTER_PACKET = 11 * 60,   -- 11 menit
    WAIT_AFTER_PROMPT = 3,         -- 3 detik
    ARRIVE_DISTANCE = 2,
    FIRE_PROMPT_DELAY = 0.35,
    WAIT_FOR_NIGHT = true,
    NIGHT_POLL_TIME = 2,
}

-- ============================================================
-- STATE
-- ============================================================
local isRunning = false
local runToken = 0
local activeHumanoid = nil
local lastClickTime = 0
local speedLoopToken = 0
local moveToCancelToken = 0

-- Fox guard
local foxEnabled = false
local foxLastScan = 0
local foxLastClick = 0
local foxConn = nil
local foxNearestDist = math.huge
local foxInRange = 0
local foxTotal = 0
local foxClickCount = 0
local foxIdleState = true

-- Cycle
local cycleRunning = false
local cycleStopFlag = false
local cycleNumber = 0

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

local function waitFolder(pathStr, timeout)
    timeout = timeout or 30
    local folder = resolvePath(pathStr)
    local t = tick()
    while not folder and tick() - t < timeout do
        task.wait(0.5)
        folder = resolvePath(pathStr)
    end
    return folder
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

local function getHumanoidRoot()
    local char = player.Character
    return char and char:FindFirstChild("HumanoidRootPart")
end

local function isNight()
    local t = Lighting.ClockTime
    return t < 6 or t >= 18
end

-- ============================================================
-- FORCE WALKSPEED
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

-- ============================================================
-- CLEAR MAP
-- ============================================================
local function cmLog(msg)
    print(string.format("[ClearMap %s] %s", os.date("%H:%M:%S"), msg))
end

local function cm_deleteChildren(path)
    local target = resolvePath(path)
    if not target then cmLog("✗ tidak ditemukan: " .. path); return end
    local count = 0
    for _, child in ipairs(target:GetChildren()) do
        if pcall(function() child:Destroy() end) then count += 1 end
    end
    cmLog(string.format("✓ %s → hapus %d anak", path, count))
end

local function cm_clearAllChildren(path)
    local target = resolvePath(path)
    if not target then cmLog("✗ tidak ditemukan: " .. path); return end
    local before = #target:GetChildren()
    if pcall(function() target:ClearAllChildren() end) then
        cmLog(string.format("✓ %s → ClearAllChildren (%d → 0)", path, before))
    else
        cmLog("✗ gagal: " .. path)
    end
end

local function cm_disableCollider(path)
    local target = resolvePath(path)
    if not target then cmLog("✗ tidak ditemukan: " .. path); return end
    local count = 0
    local function disablePart(part)
        if not part:IsA("BasePart") then return end
        part.CanCollide = false
        if part.CanTouch ~= nil then part.CanTouch = false end
        if part.CanQuery ~= nil then part.CanQuery = false end
        count += 1
    end
    disablePart(target)
    for _, d in ipairs(target:GetDescendants()) do disablePart(d) end
    cmLog(string.format("✓ %s → disable collider %d part", path, count))
end

local function runClearMap()
    cmLog("=====================================")
    cmLog("START")
    for _, path in ipairs(CONFIG.CLEAR_MAP.DELETE_CHILDREN) do cm_deleteChildren(path) end
    for _, path in ipairs(CONFIG.CLEAR_MAP.CLEAR_ALL_CHILDREN) do cm_clearAllChildren(path) end
    for _, path in ipairs(CONFIG.CLEAR_MAP.DISABLE_COLLIDER) do cm_disableCollider(path) end
    cmLog("SELESAI")
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
    pressE()
    task.wait(0.07)
    releaseE()
    return true
end

local function moveToSeedPack(hum, root, prompt, stopDistance, isCancelled, getBetterTarget)
    local t0 = tick()
    local currentPrompt = prompt

    while true do
        if isCancelled() then
            pcall(function() hum:MoveTo(root.Position) end)
            return "cancelled", currentPrompt
        end
        if not root or not root.Parent or not hum or not hum.Parent then
            return "cancelled", currentPrompt
        end
        if not currentPrompt or not currentPrompt.Parent then
            return "target_gone", currentPrompt
        end

        local myPos = root.Position
        local targetPos = getPromptPosition(currentPrompt)
        if not targetPos then return "target_gone", currentPrompt end

        local dist = (targetPos - myPos).Magnitude
        if dist <= stopDistance then
            pcall(function() hum:MoveTo(root.Position) end)
            return "reached", currentPrompt
        end
        if tick() - t0 > CONFIG.SEEDPACK_MOVE_TIMEOUT then
            pcall(function() hum:MoveTo(root.Position) end)
            return "timeout", currentPrompt
        end

        if getBetterTarget then
            local better = getBetterTarget(currentPrompt, dist)
            if better and better ~= currentPrompt then
                currentPrompt = better
                targetPos = getPromptPosition(currentPrompt)
                if not targetPos then return "target_gone", currentPrompt end
            end
        end

        hum:MoveTo(targetPos)
        task.wait(CONFIG.SEEDPACK_MOVE_REFRESH)
    end
end

local function runSeedPackMode(hum, root, myToken, isRunningFn)
    local triggeredSet = {}
    local handled = false

    while isRunningFn() and myToken == runToken do
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

            while isRunningFn() and myToken == runToken do
                if not currentTarget or not currentTarget.Parent then
                    local newPrompts = getSeedPackPrompts()
                    if #newPrompts == 0 then return true end
                    local newNearest = findNearestSeedPack(newPrompts, root.Position, triggeredSet)
                    if not newNearest then break end
                    currentTarget = newNearest
                end

                local function getBetterTarget(currentP, currentDist)
                    if currentDist <= CONFIG.SEEDPACK_STOP_DIST + 2 then return nil end
                    local p = getSeedPackPrompts()
                    local bestP, bestDist = nil, math.huge
                    for _, cand in ipairs(p) do
                        if cand and cand.Parent and cand ~= currentP and not triggeredSet[cand] then
                            local pos = getPromptPosition(cand)
                            if pos then
                                local d = (pos - root.Position).Magnitude
                                if d < bestDist then
                                    bestDist = d
                                    bestP = cand
                                end
                            end
                        end
                    end
                    if bestP and bestDist < (currentDist - CONFIG.SEEDPACK_BETTER_MARGIN) then
                        return bestP
                    end
                    return nil
                end

                local result, actualTarget = moveToSeedPack(
                    hum, root, currentTarget,
                    CONFIG.SEEDPACK_STOP_DIST,
                    function() return not isRunningFn() or myToken ~= runToken end,
                    getBetterTarget
                )

                if actualTarget then currentTarget = actualTarget end

                if result == "cancelled" then break
                elseif result == "reached" then
                    if currentTarget and currentTarget.Parent then
                        triggerSeedPack(currentTarget)
                        triggeredSet[currentTarget] = tick()
                    end
                    task.wait(CONFIG.SEEDPACK_TRIGGER_COOLDOWN)
                    break
                elseif result == "target_gone" then
                    currentTarget = nil
                elseif result == "timeout" then
                    if currentTarget then triggeredSet[currentTarget] = tick() end
                    break
                end
            end
        end
    end
    return true
end

-- ============================================================
-- TARGET FINDERS
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

-- ============================================================
-- FARM MODE
-- ============================================================
local function runFarmMode(hum, root, monsterFolder, pumpkinFolder, myToken, isRunningFn)
    local currentTarget, currentRp, currentKind = nil, nil, nil
    local lastSearch = 0

    while isRunningFn() and myToken == runToken do
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
-- MOVE TO WITCHCAULDRON (manual button)
-- ============================================================
local function moveToWitchCauldron()
    moveToCancelToken += 1
    local myToken = moveToCancelToken

    if isRunning then
        isRunning = false
        runToken += 1
        releaseE()
    end

    task.spawn(function()
        local cauldron = resolvePath(CONFIG.WITCH_CAULDRON_PATH)
        if not cauldron then
            warn("[MoveTo] WitchCauldron tidak ditemukan")
            return
        end

        local targetPart = findRootPart(cauldron) or (cauldron:IsA("BasePart") and cauldron) or nil
        if not targetPart then
            warn("[MoveTo] WitchCauldron tidak punya BasePart")
            return
        end

        local char = player.Character or player.CharacterAdded:Wait()
        local hum = char:WaitForChild("Humanoid")
        local root = char:WaitForChild("HumanoidRootPart")

        local t0 = tick()
        local timeout = 30

        while myToken == moveToCancelToken do
            if not root.Parent or not hum.Parent then return end
            if hum.Health <= 0 then return end

            local myPos = root.Position
            local tPos = targetPart.Position
            local dist = (Vector3.new(tPos.X, myPos.Y, tPos.Z) - myPos).Magnitude

            if dist <= CONFIG.WITCH_CAULDRON_STOP_DIST then
                pcall(function() hum:MoveTo(root.Position) end)
                print("[MoveTo] Sampai di WitchCauldron")
                return
            end
            if tick() - t0 > timeout then
                pcall(function() hum:MoveTo(root.Position) end)
                warn("[MoveTo] Timeout menuju WitchCauldron")
                return
            end

            hum:MoveTo(Vector3.new(tPos.X, myPos.Y, tPos.Z))
            task.wait(0.15)
        end
    end)
end

-- ============================================================
-- MAIN FARM LOOP
-- ============================================================
local function mainLoop()
    local monsterFolder = waitFolder(CONFIG.MONSTER_FOLDER, 10)
    local pumpkinFolder = waitFolder(CONFIG.PUMPKIN_FOLDER, 10)
    waitFolder(CONFIG.SEEDPACK_PATH, 5)

    if not monsterFolder and not pumpkinFolder then
        warn("[AutoFarm] Monster & Pumpkin folder tidak ditemukan")
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
        local prompts = getSeedPackPrompts()
        if #prompts > 0 then
            runSeedPackMode(hum, root, myToken, isRunningFn)
        else
            runFarmMode(hum, root, monsterFolder, pumpkinFolder, myToken, isRunningFn)
        end
    end

    if activeHumanoid == hum and hum.Parent then
        pcall(function() hum:Move(Vector3.zero, false) end)
    end
    releaseE()
end

-- ============================================================
-- FOX GUARD
-- ============================================================
local foxFilterLower = CONFIG.FOX_NAME_FILTER:lower()
local foxModelsPath = CONFIG.FOX_MODELS_PATH

local function scanFoxes(myPos)
    local container = resolvePath(foxModelsPath)
    if not container then
        foxNearestDist, foxInRange, foxTotal = math.huge, 0, 0
        return
    end

    local near, cnt, tot = math.huge, 0, 0
    local minD, maxD = CONFIG.FOX_MIN_DIST, CONFIG.FOX_MAX_DIST

    for _, child in ipairs(container:GetChildren()) do
        if child:IsA("Model") and child.Name:lower():find(foxFilterLower, 1, true) then
            tot += 1
            local rp = findRootPart(child)
            if rp then
                local d = (rp.Position - myPos).Magnitude
                if d < near then near = d end
                if d >= minD and d <= maxD then cnt += 1 end
            end
        end
    end

    foxNearestDist, foxInRange, foxTotal = near, cnt, tot
end

local function startFoxGuard()
    if foxConn then foxConn:Disconnect() end
    foxEnabled = true

    foxConn = RunService.Heartbeat:Connect(function()
        if not foxEnabled then return end
        local now = tick()

        local scanInterval = foxIdleState and CONFIG.FOX_SCAN_IDLE or CONFIG.FOX_SCAN_ACTIVE
        if now - foxLastScan >= scanInterval then
            foxLastScan = now
            local humanRoot = getHumanoidRoot()
            if not humanRoot then return end
            scanFoxes(humanRoot.Position)
            foxIdleState = (foxTotal == 0)
        end

        if foxTotal == 0 then return end

        if foxInRange > 0 then
            if now - foxLastClick >= CONFIG.FOX_CLICK_COOLDOWN then
                foxLastClick = now
                foxClickCount += 1
                clickLMB()
            end
        end
    end)
end

local function stopFoxGuard()
    foxEnabled = false
    if foxConn then
        foxConn:Disconnect()
        foxConn = nil
    end
end

-- ============================================================
-- FARM + GUARD CONTROL (dipanggil cycle)
-- ============================================================
local function startFarmGuard()
    if isRunning then return end
    isRunning = true
    moveToCancelToken += 1
    startSpeedKeeper()
    task.spawn(mainLoop)
    if CONFIG.GUARD_ENABLED then startFoxGuard() end
end

local function stopFarmGuard()
    isRunning = false
    runToken += 1
    releaseE()
    local hum = activeHumanoid
    activeHumanoid = nil
    if hum and hum.Parent then
        pcall(function()
            hum:Move(Vector3.zero, false)
            local root = hum.RootPart
            if root then hum:MoveTo(root.Position) end
        end)
    end
    stopFoxGuard()
end

-- ============================================================
-- CYCLE FUNCTIONS
-- ============================================================
local function setCycleStatus(txt, color)
    if _G.__CycleSetStatus then _G.__CycleSetStatus(txt, color) end
    print("[Cycle] " .. txt)
end

local function setCycleTimer(txt)
    if _G.__CycleSetTimer then _G.__CycleSetTimer(txt) end
end

local function firePacket()
    local ok, err = pcall(function()
        local args = { buffer.fromstring(CONFIG.PACKET_STRING) }
        ReplicatedStorage
            :WaitForChild("SharedModules")
            :WaitForChild("Packet")
            :WaitForChild("RemoteEvent")
            :FireServer(unpack(args))
    end)
    if ok then
        setCycleStatus("📦 Packet fired (Briar Rose)", Color3.fromRGB(150, 90, 220))
        return true
    else
        setCycleStatus("❌ Packet gagal: " .. tostring(err), Color3.fromRGB(200, 70, 70))
        return false
    end
end

local function fireCauldronPrompt()
    local prompt = resolveArrayPath(CONFIG.PROMPT_PATH)
    if not prompt then
        setCycleStatus("❌ CauldronPrompt tidak ditemukan", Color3.fromRGB(200, 70, 70))
        return false
    end
    if not prompt:IsA("ProximityPrompt") then
        setCycleStatus("❌ Bukan ProximityPrompt: " .. prompt.ClassName, Color3.fromRGB(200, 70, 70))
        return false
    end

    if typeof(fireproximityprompt) == "function" then
        local ok, err = pcall(function() fireproximityprompt(prompt) end)
        if ok then
            setCycleStatus("✨ Prompt fired (fireproximityprompt)", Color3.fromRGB(70, 180, 100))
            return true
        else
            setCycleStatus("⚠️ fireproximityprompt gagal: " .. tostring(err), Color3.fromRGB(240, 190, 80))
        end
    end

    local ok2, err2 = pcall(function()
        prompt:InputHoldBegin()
        task.wait(prompt.HoldDuration > 0 and prompt.HoldDuration or 0.05)
        prompt:InputHoldEnd()
    end)
    if ok2 then
        setCycleStatus("✨ Prompt fired (fallback)", Color3.fromRGB(70, 180, 100))
        return true
    else
        setCycleStatus("❌ Prompt fallback gagal: " .. tostring(err2), Color3.fromRGB(200, 70, 70))
        return false
    end
end

-- walk blocking ke Part4, return true kalau sampai
local function walkToPart4()
    local target = resolveArrayPath(CONFIG.TARGET_PATH)
    if not target or not target:IsA("BasePart") then
        setCycleStatus("❌ Target Part4 tidak ditemukan", Color3.fromRGB(200, 70, 70))
        return false
    end

    local char = player.Character
    if not char then return false end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return false end

    setCycleStatus("🚶 Walking ke Cauldron...", Color3.fromRGB(150, 90, 220))

    local arrived = false
    local conn
    conn = RunService.Heartbeat:Connect(function()
        if cycleStopFlag then conn:Disconnect() return end

        local c = player.Character
        if not c then conn:Disconnect() return end
        local h = c:FindFirstChildOfClass("Humanoid")
        if not h then conn:Disconnect() return end
        local root = c:FindFirstChild("HumanoidRootPart")
        if not root then conn:Disconnect() return end

        local tgt = resolveArrayPath(CONFIG.TARGET_PATH)
        if not tgt then
            setCycleStatus("⚠️ Target hilang saat jalan", Color3.fromRGB(240, 190, 80))
            conn:Disconnect()
            return
        end

        local myPos = root.Position
        local tgtPos = tgt.Position
        local flatDist = (Vector3.new(myPos.X, 0, myPos.Z) - Vector3.new(tgtPos.X, 0, tgtPos.Z)).Magnitude

        if flatDist <= CONFIG.ARRIVE_DISTANCE then
            arrived = true
            pcall(function() h:MoveTo(root.Position) end)
            conn:Disconnect()
            return
        end

        h.WalkSpeed = CONFIG.WALK_SPEED
        h:MoveTo(tgtPos)
    end)

    while not cycleStopFlag and not arrived do
        task.wait(0.1)
    end
    if conn.Connected then conn:Disconnect() end
    return arrived
end

local function waitCycle(seconds)
    local endT = os.clock() + seconds
    while not cycleStopFlag and os.clock() < endT do
        local remain = math.max(0, endT - os.clock())
        local m = math.floor(remain / 60)
        local s = math.floor(remain % 60)
        setCycleTimer(string.format("%02d:%02d", m, s))
        task.wait(0.25)
    end
    setCycleTimer("--:--")
    return not cycleStopFlag
end

-- ============================================================
-- MAIN CYCLE (jalan paralel sama farming)
-- ============================================================
local function mainCycle()
    cycleStopFlag = false
    while cycleRunning and not cycleStopFlag do
        cycleNumber += 1
        setCycleStatus("=== Cycle #" .. cycleNumber .. " ===", Color3.fromRGB(235, 235, 240))

        -- 1) Tunggu malam (farming tetap jalan)
        if CONFIG.WAIT_FOR_NIGHT then
            while cycleRunning and not cycleStopFlag and not isNight() do
                setCycleStatus("☀️ Siang, nunggu malam (farm tetap jalan)...", Color3.fromRGB(240, 190, 80))
                task.wait(CONFIG.NIGHT_POLL_TIME)
            end
        end
        if not cycleRunning or cycleStopFlag then break end

        -- 2) Fire packet kalau malam
        if isNight() then
            firePacket()
        else
            setCycleStatus("⚠️ Bukan malam, skip fire packet", Color3.fromRGB(240, 190, 80))
        end

        -- 3) Wait 11 menit (farming tetap jalan)
        setCycleStatus("⏳ Nunggu 11 menit (farm tetap jalan)...", Color3.fromRGB(150, 90, 220))
        if not waitCycle(CONFIG.WAIT_AFTER_PACKET) then break end

        -- 4) STOP farm & guard
        setCycleStatus("🛑 Timer habis, stop farm & guard...", Color3.fromRGB(240, 190, 80))
        stopFarmGuard()

        -- pastikan farming berhenti dulu
        task.wait(0.4)

        -- 5) Walk ke Part4
        local okWalk = walkToPart4()
        if not cycleRunning or cycleStopFlag then break end
        if not okWalk then
            setCycleStatus("❌ Walk gagal, balik ke cycle", Color3.fromRGB(200, 70, 70))
            task.wait(2)
            startFarmGuard()
            continue
        end

        setCycleStatus("✅ Sampai di Part4!", Color3.fromRGB(70, 180, 100))
        task.wait(CONFIG.FIRE_PROMPT_DELAY)

        -- 6) Fire prompt
        fireCauldronPrompt()

        -- 7) Wait 3 detik
        setCycleStatus("⏳ Nunggu 3 detik...", Color3.fromRGB(150, 90, 220))
        if not waitCycle(CONFIG.WAIT_AFTER_PROMPT) then break end

        -- 8) Hidupkan lagi farm & guard → balik ke step 1
        setCycleStatus("▶ Lanjut cycle, hidupkan farm & guard...", Color3.fromRGB(70, 180, 100))
        startFarmGuard()
        task.wait(0.3)
    end

    setCycleStatus("⏹ Cycle stopped.", Color3.fromRGB(200, 70, 70))
end

local function startCycle()
    if cycleRunning then return end
    cycleRunning = true
    cycleStopFlag = false
    cycleNumber = 0

    -- farming + guard start bareng
    startFarmGuard()
    task.spawn(mainCycle)

    setToggleUI(true)
    print("[AutoFarm+Cycle] START")
end

local function stopCycle()
    cycleStopFlag = true
    cycleRunning = false
    stopFarmGuard()
    setCycleTimer("--:--")
    setCycleStatus("⏹ All stopped.", Color3.fromRGB(200, 70, 70))
    setToggleUI(false)
    print("[AutoFarm+Cycle] STOP")
end

-- ============================================================
-- GUI
-- ============================================================
local COLORS = {
    bg        = Color3.fromRGB(22, 22, 28),
    header    = Color3.fromRGB(16, 16, 20),
    text      = Color3.fromRGB(235, 235, 240),
    textDim   = Color3.fromRGB(140, 140, 155),
    green     = Color3.fromRGB(80, 200, 120),
    greenHv   = Color3.fromRGB(100, 220, 140),
    red       = Color3.fromRGB(200, 70, 70),
    redHv     = Color3.fromRGB(220, 90, 90),
    blue      = Color3.fromRGB(70, 130, 200),
    blueHv    = Color3.fromRGB(90, 150, 220),
    accentOff = Color3.fromRGB(60, 60, 72),
    stroke    = Color3.fromRGB(60, 60, 72),
}

local function corner(p, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, r or 8)
    c.Parent = p
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "AutoFarmFoxGuardCycle"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = player:WaitForChild("PlayerGui")

local FRAME_WIDTH = 210
local FRAME_HEIGHT = 200

local frame = Instance.new("Frame")
frame.Size = UDim2.new(0, FRAME_WIDTH, 0, FRAME_HEIGHT)
frame.Position = UDim2.new(0, 12, 0, 60)
frame.BackgroundColor3 = COLORS.bg
frame.BorderSizePixel = 0
frame.Active = true
frame.Parent = screenGui
corner(frame, 10)

local stroke = Instance.new("UIStroke")
stroke.Color = COLORS.stroke
stroke.Transparency = 0.4
stroke.Parent = frame

-- Drag
local dragging, dragStart, startPos
frame.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = frame.Position
    end
end)
frame.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        dragging = false
    end
end)
UserInputService.InputChanged:Connect(function(input)
    if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = input.Position - dragStart
        frame.Position = UDim2.new(
            startPos.X.Scale, startPos.X.Offset + delta.X,
            startPos.Y.Scale, startPos.Y.Offset + delta.Y
        )
    end
end)

-- Header
local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 24)
header.BackgroundColor3 = COLORS.header
header.BorderSizePixel = 0
header.Parent = frame
corner(header, 10)

local headerFix = Instance.new("Frame")
headerFix.Size = UDim2.new(1, 0, 0, 8)
headerFix.Position = UDim2.new(0, 0, 1, -8)
headerFix.BackgroundColor3 = COLORS.header
headerFix.BorderSizePixel = 0
headerFix.Parent = header

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -60, 1, 0)
title.Position = UDim2.new(0, 10, 0, 0)
title.BackgroundTransparency = 1
title.Text = "🌾🦊🌙 Farm + Guard + Cycle"
title.TextColor3 = COLORS.text
title.Font = Enum.Font.GothamBold
title.TextSize = 11
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = header

local function makeHeaderBtn(xOffset, bg, txt)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(0, 18, 0, 18)
    b.Position = UDim2.new(1, xOffset, 0, 3)
    b.BackgroundColor3 = bg
    b.Text = txt
    b.TextColor3 = Color3.fromRGB(255, 255, 255)
    b.Font = Enum.Font.GothamBold
    b.TextSize = 12
    b.BorderSizePixel = 0
    b.AutoButtonColor = false
    b.Parent = header
    corner(b, 5)
    return b
end

local minimizeBtn = makeHeaderBtn(-42, COLORS.accentOff, "—")
local closeBtn    = makeHeaderBtn(-21, COLORS.red, "×")

-- Cycle status
local statusLbl = Instance.new("TextLabel")
statusLbl.Size = UDim2.new(1, -16, 0, 14)
statusLbl.Position = UDim2.new(0, 8, 0, 28)
statusLbl.BackgroundTransparency = 1
statusLbl.Text = "Status: OFF"
statusLbl.TextColor3 = COLORS.textDim
statusLbl.Font = Enum.Font.Code
statusLbl.TextSize = 10
statusLbl.TextXAlignment = Enum.TextXAlignment.Left
statusLbl.Parent = frame

-- Timer
local timerLbl = Instance.new("TextLabel")
timerLbl.Size = UDim2.new(1, -16, 0, 22)
timerLbl.Position = UDim2.new(0, 8, 0, 44)
timerLbl.BackgroundTransparency = 1
timerLbl.Text = "--:--"
timerLbl.TextColor3 = COLORS.text
timerLbl.Font = Enum.Font.GothamBold
timerLbl.TextSize = 18
timerLbl.TextXAlignment = Enum.TextXAlignment.Left
timerLbl.Parent = frame

-- Clock
local clockLbl = Instance.new("TextLabel")
clockLbl.Size = UDim2.new(1, -16, 0, 12)
clockLbl.Position = UDim2.new(0, 8, 0, 68)
clockLbl.BackgroundTransparency = 1
clockLbl.Text = "ClockTime: -"
clockLbl.TextColor3 = COLORS.textDim
clockLbl.Font = Enum.Font.Code
clockLbl.TextSize = 10
clockLbl.TextXAlignment = Enum.TextXAlignment.Left
clockLbl.Parent = frame

-- ===== MAIN TOGGLE =====
local toggleBtn = Instance.new("TextButton")
toggleBtn.Size = UDim2.new(1, -16, 0, 34)
toggleBtn.Position = UDim2.new(0, 8, 0, 86)
toggleBtn.BackgroundColor3 = COLORS.green
toggleBtn.Text = "▶ START ALL"
toggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
toggleBtn.Font = Enum.Font.GothamBold
toggleBtn.TextSize = 13
toggleBtn.BorderSizePixel = 0
toggleBtn.AutoButtonColor = false
toggleBtn.Parent = frame
corner(toggleBtn, 8)

-- ===== WITCH BUTTON =====
local witchBtn = Instance.new("TextButton")
witchBtn.Size = UDim2.new(1, -16, 0, 26)
witchBtn.Position = UDim2.new(0, 8, 0, 126)
witchBtn.BackgroundColor3 = COLORS.blue
witchBtn.Text = "⚗ WitchCauldron"
witchBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
witchBtn.Font = Enum.Font.GothamBold
witchBtn.TextSize = 11
witchBtn.BorderSizePixel = 0
witchBtn.AutoButtonColor = false
witchBtn.Parent = frame
corner(witchBtn, 8)

-- Info small
local infoLbl = Instance.new("TextLabel")
infoLbl.Size = UDim2.new(1, -16, 0, 12)
infoLbl.Position = UDim2.new(0, 8, 0, 158)
infoLbl.BackgroundTransparency = 1
infoLbl.Text = "Farm + Guard + Cycle 11m"
infoLbl.TextColor3 = COLORS.textDim
infoLbl.Font = Enum.Font.Code
infoLbl.TextSize = 9
infoLbl.TextXAlignment = Enum.TextXAlignment.Left
infoLbl.Parent = frame

-- ============================================================
-- UI HOOKS
-- ============================================================
_G.__CycleSetStatus = function(txt, color)
    statusLbl.Text = txt
    if color then statusLbl.TextColor3 = color end
end
_G.__CycleSetTimer = function(txt)
    timerLbl.Text = txt
end

local function setToggleUI(on)
    if on then
        toggleBtn.Text = "■ STOP ALL"
        toggleBtn.BackgroundColor3 = COLORS.red
        stroke.Color = COLORS.green
        statusLbl.Text = "Status: 🟢 RUNNING"
        statusLbl.TextColor3 = COLORS.green
    else
        toggleBtn.Text = "▶ START ALL"
        toggleBtn.BackgroundColor3 = COLORS.green
        stroke.Color = COLORS.stroke
        statusLbl.Text = "Status: 🔴 OFF"
        statusLbl.TextColor3 = COLORS.textDim
    end
end

toggleBtn.MouseButton1Click:Connect(function()
    if cycleRunning then
        stopCycle()
    else
        startCycle()
    end
end)

toggleBtn.MouseEnter:Connect(function()
    if not cycleRunning then
        TweenService:Create(toggleBtn, TweenInfo.new(0.1), { BackgroundColor3 = COLORS.greenHv }):Play()
    else
        TweenService:Create(toggleBtn, TweenInfo.new(0.1), { BackgroundColor3 = COLORS.redHv }):Play()
    end
end)
toggleBtn.MouseLeave:Connect(function()
    if not cycleRunning then
        TweenService:Create(toggleBtn, TweenInfo.new(0.1), { BackgroundColor3 = COLORS.green }):Play()
    else
        TweenService:Create(toggleBtn, TweenInfo.new(0.1), { BackgroundColor3 = COLORS.red }):Play()
    end
end)

witchBtn.MouseButton1Click:Connect(function()
    moveToWitchCauldron()
end)

witchBtn.MouseEnter:Connect(function()
    TweenService:Create(witchBtn, TweenInfo.new(0.1), { BackgroundColor3 = COLORS.blueHv }):Play()
end)
witchBtn.MouseLeave:Connect(function()
    TweenService:Create(witchBtn, TweenInfo.new(0.1), { BackgroundColor3 = COLORS.blue }):Play()
end)

-- ============================================================
-- MINIMIZE / CLOSE
-- ============================================================
local minimized = false
local savedSize = FRAME_HEIGHT

minimizeBtn.MouseButton1Click:Connect(function()
    minimized = not minimized
    if minimized then
        savedSize = frame.Size.Y.Offset
        TweenService:Create(frame, TweenInfo.new(0.2), {
            Size = UDim2.new(0, FRAME_WIDTH, 0, 24)
        }):Play()
        toggleBtn.Visible = false
        witchBtn.Visible = false
        statusLbl.Visible = false
        timerLbl.Visible = false
        clockLbl.Visible = false
        infoLbl.Visible = false
    else
        TweenService:Create(frame, TweenInfo.new(0.2), {
            Size = UDim2.new(0, FRAME_WIDTH, 0, savedSize)
        }):Play()
        toggleBtn.Visible = true
        witchBtn.Visible = true
        statusLbl.Visible = true
        timerLbl.Visible = true
        clockLbl.Visible = true
        infoLbl.Visible = true
    end
end)

closeBtn.MouseButton1Click:Connect(function()
    stopCycle()
    stopSpeedKeeper()
    screenGui:Destroy()
end)

player.CharacterAdded:Connect(function()
    if cycleRunning then
        stopCycle()
    end
end)

-- ============================================================
-- CLOCK UPDATER
-- ============================================================
task.spawn(function()
    while screenGui.Parent do
        local t = Lighting.ClockTime
        clockLbl.Text = string.format("ClockTime: %.2f  (%s)", t, isNight() and "MALAM" or "SIANG")
        task.wait(0.5)
    end
end)

-- ============================================================
-- EXECUTE
-- ============================================================
runClearMap()
setToggleUI(false)
print("[AutoFarm+Guard+Cycle] Loaded | 1 toggle buat semua")
