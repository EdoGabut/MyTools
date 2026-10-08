-- ============================================================
-- AUTO FARM + FOX GUARD + BRIAR CYCLE (ALL-IN-ONE)
-- Alur:
--  1) Malam tiba → cek GUI WitchCauldron apakah ada label "Briar"
--  2) Kalau ada → fire remote "Briar Rose"
--  3) Tunggu BrewTimer.TextLabel == "Ready"
--  4) Ready → STOP farm (Guard tetap jalan) → walk ke Part4
--  5) Sampai → simulasi klik E 2x (jeda 1 detik)
--  6) Hiraukan malam → hidupkan farm lagi → tunggu malam berikutnya
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
    GUARD_ENABLED      = true,

    -- ===== Brew Cycle =====
    -- GUI cauldron yang di-scan (untuk cari "Briar")
    BRIAR_GUI_PATHS = {
        "game.Players.LocalPlayer.PlayerGui.WitchCauldron",
        "Workspace.WitchCauldron",
    },
    BRIAR_KEYWORD    = "briar",       -- keyword (case-insensitive)

    TIMER_PATH       = "Workspace.WitchCauldron.WitchCauldron.WitchCauldron.Water.BrewTimer.TextLabel",
    READY_TEXT       = "ready",
    READY_POLL_TIME  = 0.5,

    WATER_FOLDER_PATH = { "WitchCauldron", "WitchCauldron", "WitchCauldron", "Water" },
    E_HOLD_TIME       = 0.1,
    DOUBLE_E_GAP      = 1.0,

    TARGET_PATH       = { "WitchCauldron", "WitchCauldron", "WitchCauldron", "Part4" },
    ARRIVE_DISTANCE   = 2,
    WALK_TIMEOUT      = 45,

    PACKET_STRING     = "\195\0009\nBriar Rose",
    WAIT_AFTER_PROMPT = 3,

    -- Night check
    NIGHT_START = 18,
    NIGHT_END   = 6,
    NIGHT_POLL_TIME = 1,
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

local foxEnabled = false
local foxLastScan = 0
local foxLastClick = 0
local foxConn = nil
local foxNearestDist = math.huge
local foxInRange = 0
local foxTotal = 0
local foxClickCount = 0
local foxIdleState = true

local cycleRunning = false
local cycleStopFlag = false
local cycleNumber = 0

-- Flag: fire packet sekali per malam
local firedThisNight = false
local lastNightState = nil

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
    local h = (Lighting.ClockTime or 12) % 24
    return h >= CONFIG.NIGHT_START or h < CONFIG.NIGHT_END
end

-- ============================================================
-- BRIAR GUI CHECK
-- ============================================================
local function hasBriarInGui()
    for _, path in ipairs(CONFIG.BRIAR_GUI_PATHS) do
        local root = resolvePath(path)
        if root then
            for _, obj in ipairs(root:GetDescendants()) do
                if obj:IsA("TextLabel") then
                    local text = (obj.Text or ""):lower()
                    if text:find(CONFIG.BRIAR_KEYWORD, 1, true) then
                        return true
                    end
                end
            end
        end
    end
    return false
end

-- ============================================================
-- TIMER / READY CHECK
-- ============================================================
local function getTimerLabel()
    local obj = resolvePath(CONFIG.TIMER_PATH)
    if obj and (obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox")) then
        return obj
    end
    return nil
end

local function getTimerText()
    local lbl = getTimerLabel()
    return lbl and lbl.Text or ""
end

local function isReady()
    local t = getTimerText():lower()
    return t:find(CONFIG.READY_TEXT, 1, true) ~= nil
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

local function tapE(holdTime)
    holdTime = holdTime or CONFIG.E_HOLD_TIME
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
-- MANUAL MOVE TO WITCHCAULDRON
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
        if not cauldron then return end
        local targetPart = findRootPart(cauldron) or (cauldron:IsA("BasePart") and cauldron) or nil
        if not targetPart then return end

        local char = player.Character or player.CharacterAdded:Wait()
        local hum = char:WaitForChild("Humanoid")
        local root = char:WaitForChild("HumanoidRootPart")

        local t0 = tick()
        while myToken == moveToCancelToken do
            if not root.Parent or not hum.Parent then return end
            if hum.Health <= 0 then return end

            local myPos = root.Position
            local tPos = targetPart.Position
            local dist = (Vector3.new(tPos.X, myPos.Y, tPos.Z) - myPos).Magnitude

            if dist <= CONFIG.WITCH_CAULDRON_STOP_DIST then
                pcall(function() hum:MoveTo(root.Position) end)
                return
            end
            if tick() - t0 > 30 then
                pcall(function() hum:MoveTo(root.Position) end)
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

    if not monsterFolder and not pumpkinFolder then return end

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
-- FARM + GUARD CONTROL
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
    stopSpeedKeeper()
end

-- Hentikan hanya farming, guard tetap hidup
local function stopFarmOnly()
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
    stopSpeedKeeper()
end

-- ============================================================
-- CYCLE STATUS LOG
-- ============================================================
local function setCycleStatus(txt)
    print("[Cycle] " .. txt)
end

-- ============================================================
-- FIRE PACKET
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
    if ok then
        setCycleStatus("📦 Briar Rose fired")
        return true
    else
        setCycleStatus("❌ Packet gagal: " .. tostring(err))
        return false
    end
end

-- ============================================================
-- TRIGGER PROMPT DI FOLDER WATER (klik E 2x, jeda 1 detik)
-- ============================================================
local function findPromptInWater()
    local water = resolveArrayPath(CONFIG.WATER_FOLDER_PATH)
    if not water then return nil end
    for _, d in ipairs(water:GetDescendants()) do
        if d:IsA("ProximityPrompt") then
            return d
        end
    end
    return nil
end

local function triggerWaterPrompt()
    local water = resolveArrayPath(CONFIG.WATER_FOLDER_PATH)
    if not water then
        setCycleStatus("❌ Folder Water gak ada")
        return false
    end

    -- klik E pertama
    local prompt = findPromptInWater()
    if prompt then
        pcall(function()
            prompt.HoldDuration = 0
            prompt.RequiresLineOfSight = false
            prompt.Enabled = true
            prompt.KeyboardKeyCode = Enum.KeyCode.E
            prompt.ClickablePrompt = false
            prompt.MaxActivationDistance = 30
        end)
    end
    tapE(CONFIG.E_HOLD_TIME)
    setCycleStatus("E #1")

    -- jeda 1 detik
    task.wait(CONFIG.DOUBLE_E_GAP)
    if cycleStopFlag then return false end

    -- klik E kedua (re-fetch prompt)
    prompt = findPromptInWater()
    if prompt then
        pcall(function()
            prompt.HoldDuration = 0
            prompt.RequiresLineOfSight = false
            prompt.Enabled = true
            prompt.KeyboardKeyCode = Enum.KeyCode.E
            prompt.ClickablePrompt = false
            prompt.MaxActivationDistance = 30
        end)
    end
    tapE(CONFIG.E_HOLD_TIME)
    setCycleStatus("E #2")

    return true
end

-- ============================================================
-- WALK KE PART4 (blocking)
-- ============================================================
local function walkToPart4()
    local target = resolveArrayPath(CONFIG.TARGET_PATH)
    if not target or not target:IsA("BasePart") then
        setCycleStatus("❌ Part4 gak ada")
        return false
    end

    local char = player.Character
    if not char then return false end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return false end

    setCycleStatus("🚶 Walking ke Part4...")

    local arrived = false
    local conn
    local tStart = tick()

    conn = RunService.Heartbeat:Connect(function()
        if cycleStopFlag then conn:Disconnect() return end
        if tick() - tStart > CONFIG.WALK_TIMEOUT then
            conn:Disconnect()
            return
        end

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

    while not cycleStopFlag and not arrived do
        if tick() - tStart > CONFIG.WALK_TIMEOUT then break end
        task.wait(0.1)
    end
    if conn.Connected then conn:Disconnect() end
    return arrived
end

-- ============================================================
-- MAIN CYCLE
-- Alur:
--   1) Tunggu malam + flag reset → cek Briar di GUI → fire
--   2) Tunggu Ready
--   3) Stop farm only → walk ke Part4
--   4) E 2x jeda 1 detik
--   5) Hiraukan malam → hidupkan farm lagi → tunggu malam berikutnya
-- ============================================================
local function mainCycle()
    cycleStopFlag = false
    firedThisNight = false
    lastNightState = nil

    while cycleRunning and not cycleStopFlag do
        cycleNumber += 1
        setCycleStatus("=== Cycle #" .. cycleNumber .. " ===")

        -- 1) Tunggu malam berikutnya
        while cycleRunning and not cycleStopFlag and not isNight() do
            setCycleStatus("☀️ Siang, tunggu malam...")
            task.wait(CONFIG.NIGHT_POLL_TIME)
        end
        if not cycleRunning or cycleStopFlag then break end

        setCycleStatus("🌙 Malam tiba")

        -- 2) Fire packet (sekali per malam) — cek dulu ada Briar di GUI?
        if not firedThisNight then
            -- tunggu sebentar biar GUI update
            task.wait(0.5)
            if hasBriarInGui() then
                setCycleStatus("✓ Briar ada di GUI → fire")
                fireBriar()
                firedThisNight = true
            else
                setCycleStatus("✗ Briar gak ada di GUI → skip fire")
            end
        end

        -- 3) Tunggu Ready
        while cycleRunning and not cycleStopFlag and not isReady() do
            setCycleStatus("⏳ Nunggu Ready (BrewTimer: " .. getTimerText() .. ")")
            task.wait(CONFIG.READY_POLL_TIME)
        end
        if not cycleRunning or cycleStopFlag then break end

        setCycleStatus("✅ Ready!")

        -- 4) Stop FARM ONLY (guard tetap jalan) → walk ke Part4
        stopFarmOnly()
        task.wait(0.4)

        local okWalk = walkToPart4()
        if not cycleRunning or cycleStopFlag then break end

        if not okWalk then
            setCycleStatus("❌ Walk gagal")
        else
            setCycleStatus("✅ Sampai Part4")
            task.wait(0.35)

            -- 5) Klik E 2x jeda 1 detik
            triggerWaterPrompt()

            if not cycleRunning or cycleStopFlag then break end

            -- 6) Wait 3 detik (hiraukan malam)
            setCycleStatus("⏳ Wait " .. CONFIG.WAIT_AFTER_PROMPT .. "s")
            local endT = os.clock() + CONFIG.WAIT_AFTER_PROMPT
            while not cycleStopFlag and os.clock() < endT do
                task.wait(0.2)
            end
        end

        -- 7) Hidupkan farm lagi → tunggu malam berikutnya
        setCycleStatus("▶ Hidupkan farm, tunggu malam berikutnya...")
        if not isRunning then
            startFarmGuard()
        end

        -- reset flag malam HANYA saat transisi ke siang terjadi
        -- biar ga fire 2x di malam yang sama
        while cycleRunning and not cycleStopFlag and isNight() do
            task.wait(1)
        end
        if not cycleRunning or cycleStopFlag then break end

        -- sekarang siang → reset flag
        firedThisNight = false
        setCycleStatus("☀️ Siang → reset flag, tunggu malam berikutnya")
    end

    setCycleStatus("⏹ Cycle stopped")
end

local function startCycle()
    if cycleRunning then return end
    cycleRunning = true
    cycleStopFlag = false
    cycleNumber = 0

    startFarmGuard()
    task.spawn(mainCycle)

    if _G.__SetToggle then _G.__SetToggle(true) end
    print("[AutoFarm+Cycle] START")
end

local function stopCycle()
    cycleStopFlag = true
    cycleRunning = false
    stopFarmGuard()
    if _G.__SetToggle then _G.__SetToggle(false) end
    print("[AutoFarm+Cycle] STOP")
end

-- ============================================================
-- GUI MINIMALIS (mobile friendly)
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
screenGui.Name = "FarmGuardMin"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = player:WaitForChild("PlayerGui")

local W, H = 80, 80

local frame = Instance.new("Frame")
frame.Size = UDim2.new(0, W, 0, H)
frame.Position = UDim2.new(0, 20, 0, 200)
frame.BackgroundColor3 = COLORS.bg
frame.BackgroundTransparency = 0.15
frame.BorderSizePixel = 0
frame.Active = true
frame.Parent = screenGui
corner(frame, 40)

local stroke = Instance.new("UIStroke")
stroke.Color = COLORS.stroke
stroke.Transparency = 0.3
stroke.Thickness = 1.5
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

local toggleBtn = Instance.new("TextButton")
toggleBtn.Size = UDim2.new(1, -10, 1, -10)
toggleBtn.Position = UDim2.new(0, 5, 0, 5)
toggleBtn.BackgroundColor3 = COLORS.red
toggleBtn.Text = "OFF"
toggleBtn.TextColor3 = COLORS.text
toggleBtn.Font = Enum.Font.GothamBold
toggleBtn.TextSize = 16
toggleBtn.BorderSizePixel = 0
toggleBtn.AutoButtonColor = false
toggleBtn.Parent = frame
corner(toggleBtn, 36)

local statusDot = Instance.new("Frame")
statusDot.Size = UDim2.new(0, 8, 0, 8)
statusDot.Position = UDim2.new(1, -12, 0, 6)
statusDot.BackgroundColor3 = COLORS.textDim
statusDot.BorderSizePixel = 0
statusDot.Parent = frame
corner(statusDot, 4)

-- ============================================================
-- UI HOOKS
-- ============================================================
_G.__SetToggle = function(on)
    if on then
        toggleBtn.Text = "ON"
        toggleBtn.BackgroundColor3 = COLORS.green
        stroke.Color = COLORS.green
        statusDot.BackgroundColor3 = COLORS.green
    else
        toggleBtn.Text = "OFF"
        toggleBtn.BackgroundColor3 = COLORS.red
        stroke.Color = COLORS.stroke
        statusDot.BackgroundColor3 = COLORS.textDim
    end
end

toggleBtn.MouseButton1Click:Connect(function()
    if cycleRunning then
        stopCycle()
    else
        startCycle()
    end
end)

-- ============================================================
-- CHARACTER RESET
-- ============================================================
player.CharacterAdded:Connect(function()
    if cycleRunning then
        stopCycle()
    end
end)

-- ============================================================
-- EXECUTE
-- ============================================================
runClearMap()
_G.__SetToggle(false)
print("[FarmGuardMin+BriarCycle] Loaded | 1 toggle ON/OFF")
