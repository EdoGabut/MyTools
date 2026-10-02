-- ============================================================
-- Auto Grind + SeedPack Priority (No GUI, Auto Start)
-- Fixed version — semua fungsi dideklarasi di atas
-- ============================================================
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local VirtualUser = game:GetService("VirtualUser")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

-- ============================================================
-- CONFIG
-- ============================================================
local CONFIG = {
    -- Farm
    MONSTER_FOLDER = "Workspace.MonsterVisuals",
    PUMPKIN_FOLDER = "Workspace.Pumpkins",
    MONSTER_RANGE = 10,
    PUMPKIN_RANGE = 5,
    ATTACK_COOLDOWN = 0.12,
    RETARGET_INTERVAL = 0.1,

    -- SeedPack
    SEEDPACK_PATH = "Workspace.Map.SeedPackSpawnServerLocations",
    SEEDPACK_STOP_DIST = 5,
    SEEDPACK_MOVE_TIMEOUT = 15,
    SEEDPACK_MOVE_REFRESH = 0.15,
    SEEDPACK_IDLE_DELAY = 0.5,
    SEEDPACK_TRIGGER_COOLDOWN = 0.1,
    SEEDPACK_TRIGGERED_TTL = 1.5,
    SEEDPACK_SCAN_INTERVAL = 0.3,   -- cek folder seedpack tiap 0.3s

    -- Speed
    WALK_SPEED = 30,

    -- Cleanup
    DELETE_CHILDREN = {
        "Workspace.Map.Middle",
        "Workspace.Map.Stands",
        "Workspace.NPCS",
        "Workspace.ExplorerStand",
        "Workspace.AuctionStand",
        -- "Workspace.Gardens",  -- HATI-HATI: ini hapus garden sendiri juga
    },
    DISABLE_COLLIDER = {
        "Workspace.WitchCauldron",
    },
}

-- ============================================================
-- STATE (dideklarasi di atas biar gak error)
-- ============================================================
local isRunning = false
local runToken = 0
local stats = { monster = 0, pumpkin = 0, seedpack = 0 }
local activeHumanoid = nil
local lastClickTime = 0

-- Forward declaration
local updateStatus, updateStats, resetStats

-- ============================================================
-- HELPER: RESOLVE PATH
-- ============================================================
local function resolvePath(pathStr)
    if not pathStr or pathStr == "" then return nil end
    pathStr = pathStr:gsub("^%s+", ""):gsub("%s+$", "")
    local segments = {}
    for seg in pathStr:gmatch("[^%.]+") do
        table.insert(segments, seg)
    end
    if #segments == 0 then return nil end

    local node = game
    if segments[1] == "game" then table.remove(segments, 1) end

    for _, seg in ipairs(segments) do
        if not node then return nil end
        if seg == "LocalPlayer" then
            node = player
        else
            node = node:FindFirstChild(seg)
        end
    end
    return node
end

local function waitFolder(pathStr)
    local folder = resolvePath(pathStr)
    local t = tick()
    while not folder and tick() - t < 30 do
        task.wait(0.5)
        folder = resolvePath(pathStr)
    end
    return folder
end

-- ============================================================
-- HELPER: POSITION
-- ============================================================
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

-- ============================================================
-- CLEANUP MAP
-- ============================================================
local function cleanMap()
    for _, path in ipairs(CONFIG.DELETE_CHILDREN) do
        local target = resolvePath(path)
        if target then
            for _, child in ipairs(target:GetChildren()) do
                pcall(function() child:Destroy() end)
            end
        end
    end
    for _, path in ipairs(CONFIG.DISABLE_COLLIDER) do
        local target = resolvePath(path)
        if target then
            if target:IsA("BasePart") then
                target.CanCollide = false
                if target.CanTouch ~= nil then target.CanTouch = false end
                if target.CanQuery ~= nil then target.CanQuery = false end
            end
            for _, d in ipairs(target:GetDescendants()) do
                if d:IsA("BasePart") then
                    d.CanCollide = false
                    if d.CanTouch ~= nil then d.CanTouch = false end
                    if d.CanQuery ~= nil then d.CanQuery = false end
                end
            end
        end
    end
end

-- ============================================================
-- INPUT SIMULATION
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
    local ok = pcall(function()
        VirtualInputManager:SendMouseButtonEvent(0, 0, 0, true, game, 1)
        task.wait(0.02)
        VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 1)
    end)
    if ok then return true end

    local ok2 = pcall(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton1(Vector2.new(0, 0))
    end)
    if ok2 then return true end

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
        if obj:IsA("ProximityPrompt") then
            table.insert(list, obj)
        end
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

local function moveToSeedPack(hum, root, prompt, stopDistance, isCancelled)
    local t0 = tick()
    while true do
        if isCancelled() then
            pcall(function() hum:MoveTo(root.Position) end)
            return "cancelled"
        end
        if not root or not root.Parent or not hum or not hum.Parent then
            return "cancelled"
        end
        if not prompt or not prompt.Parent then
            return "target_gone"
        end
        local targetPos = getPromptPosition(prompt)
        if not targetPos then
            return "target_gone"
        end
        local myPos = root.Position
        local dist = (targetPos - myPos).Magnitude
        if dist <= stopDistance then
            pcall(function() hum:MoveTo(root.Position) end)
            return "reached"
        end
        if tick() - t0 > CONFIG.SEEDPACK_MOVE_TIMEOUT then
            pcall(function() hum:MoveTo(root.Position) end)
            return "timeout"
        end
        hum:MoveTo(targetPos)
        task.wait(CONFIG.SEEDPACK_MOVE_REFRESH)
    end
end

-- SeedPack mode: return true kalau folder kosong, false kalau gak ada dari awal
local function runSeedPackMode(hum, root, myToken, isRunningFn)
    local triggeredSet = {}
    local handled = false

    while isRunningFn() and myToken == runToken do
        -- Cleanup triggered set
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
                if #getSeedPackPrompts() == 0 then
                    return true
                end
            else
                return false
            end
        else
            handled = true
        end

        local myPos = root.Position
        local nearest, dist = findNearestSeedPack(prompts, myPos, triggeredSet)

        if not nearest then
            task.wait(CONFIG.SEEDPACK_IDLE_DELAY)
        else
            updateStatus(string.format("📦 SeedPack (%.1f stud)", dist), "seedpack")

            local currentTarget = nearest
            local cancelled = false

            while isRunningFn() and myToken == runToken and not cancelled do
                if not currentTarget or not currentTarget.Parent then
                    local newPrompts = getSeedPackPrompts()
                    if #newPrompts == 0 then
                        return true
                    end
                    local newNearest = findNearestSeedPack(newPrompts, root.Position, triggeredSet)
                    if not newNearest then
                        cancelled = true
                        break
                    end
                    currentTarget = newNearest
                end

                local result = moveToSeedPack(
                    hum, root, currentTarget,
                    CONFIG.SEEDPACK_STOP_DIST,
                    function() return not isRunningFn() or myToken ~= runToken end
                )

                if result == "cancelled" then
                    cancelled = true
                    break
                elseif result == "reached" then
                    if currentTarget and currentTarget.Parent then
                        triggerSeedPack(currentTarget)
                        stats.seedpack += 1
                        updateStats()
                        triggeredSet[currentTarget] = tick()
                    end
                    task.wait(CONFIG.SEEDPACK_TRIGGER_COOLDOWN)
                    break
                elseif result == "target_gone" then
                    currentTarget = nil
                elseif result == "timeout" then
                    if currentTarget then
                        triggeredSet[currentTarget] = tick()
                    end
                    break
                end
            end
        end
    end
    return true
end

-- ============================================================
-- FARM
-- ============================================================
local function findBestFarmTarget(monsterFolder, pumpkinFolder, myPos)
    local best, bestDist, bestKind = nil, math.huge, nil

    if monsterFolder then
        for _, child in ipairs(monsterFolder:GetChildren()) do
            if child:IsA("Model") then
                local rp = findRootPart(child)
                if rp then
                    local d = (rp.Position - myPos).Magnitude
                    if d < bestDist then
                        bestDist = d
                        best = child
                        bestKind = "monster"
                    end
                end
            end
        end
    end

    if pumpkinFolder then
        for _, child in ipairs(pumpkinFolder:GetChildren()) do
            local rp
            if child:IsA("Model") then
                rp = findRootPart(child)
            elseif child:IsA("BasePart") then
                rp = child
            end
            if rp then
                local d = (rp.Position - myPos).Magnitude
                if d < bestDist then
                    bestDist = d
                    best = child
                    bestKind = "pumpkin"
                end
            end
        end
    end

    if not best then return nil end
    local rp = findRootPart(best) or (best:IsA("BasePart") and best)
    local realDist = rp and (rp.Position - myPos).Magnitude or 0
    return best, realDist, bestKind
end

-- ============================================================
-- STATUS (no GUI, cuma print)
-- ============================================================
local lastStatusText = ""
updateStatus = function(text, colorKey)
    if text ~= lastStatusText then
        lastStatusText = text
        print("[AutoGrind]", text)
    end
end

updateStats = function()
    -- print stats tiap 10 detik aja biar gak spam
    -- (bisa dimatikan)
end

resetStats = function()
    stats.seedpack = 0
    stats.monster = 0
    stats.pumpkin = 0
end

-- ============================================================
-- MAIN LOOP
-- ============================================================
local function mainLoop()
    local monsterFolder = waitFolder(CONFIG.MONSTER_FOLDER)
    local pumpkinFolder = waitFolder(CONFIG.PUMPKIN_FOLDER)
    if not monsterFolder or not pumpkinFolder then
        warn("[AutoGrind] Folder monster/pumpkin tidak ditemukan")
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

    local currentTarget = nil
    local currentKind = nil
    local lastSearch = 0

    local function isRunningFn() return isRunning and myToken == runToken end

    while isRunningFn() and hum.Health > 0 do
        if not root.Parent then break end

        -- =================================================
        -- PRIORITAS 1: SEEDPACK
        -- =================================================
        local seedPackPrompts = getSeedPackPrompts()
        if #seedPackPrompts > 0 then
            updateStatus("📦 SeedPack mode...", "seedpack")
            runSeedPackMode(hum, root, myToken, isRunningFn)
            currentTarget = nil
            currentKind = nil
            lastSearch = 0
            -- skip farm untuk iterasi ini
        else
            -- =================================================
            -- PRIORITAS 2: FARM
            -- =================================================
            hum.WalkSpeed = CONFIG.WALK_SPEED
            local myPos = root.Position
            local now = tick()

            local targetRp
            if currentTarget and currentTarget.Parent then
                if currentTarget:IsA("Model") then
                    targetRp = findRootPart(currentTarget)
                elseif currentTarget:IsA("BasePart") then
                    targetRp = currentTarget
                end
            end
            if not currentTarget or not currentTarget.Parent or not targetRp then
                currentTarget = nil
                currentKind = nil
            end

            if not currentTarget and (now - lastSearch) >= 0.3 then
                lastSearch = now
                local best, _, kind = findBestFarmTarget(monsterFolder, pumpkinFolder, myPos)
                if best then
                    currentTarget = best
                    currentKind = kind
                end
            end

            if not currentTarget then
                hum:Move(Vector3.zero, false)
                updateStatus("💤 Scan...", nil)
                task.wait(0.15)
            else
                targetRp = (currentTarget:IsA("Model") and findRootPart(currentTarget))
                    or (currentTarget:IsA("BasePart") and currentTarget)
                    or nil

                if targetRp then
                    local targetPos = targetRp.Position
                    local flatDir = Vector3.new(targetPos.X - myPos.X, 0, targetPos.Z - myPos.Z)
                    local distance = flatDir.Magnitude
                    local range = (currentKind == "pumpkin") and CONFIG.PUMPKIN_RANGE or CONFIG.MONSTER_RANGE

                    if distance <= range then
                        hum:Move(Vector3.zero, false)
                        local lookAt = CFrame.lookAt(myPos, Vector3.new(targetPos.X, myPos.Y, targetPos.Z))
                        root.CFrame = CFrame.new(myPos) * (lookAt - lookAt.Position)

                        local tnow = tick()
                        if (tnow - lastClickTime) >= CONFIG.ATTACK_COOLDOWN then
                            lastClickTime = tnow
                            clickLMB()
                            if currentKind == "monster" then
                                stats.monster += 1
                            else
                                stats.pumpkin += 1
                            end
                        end

                        updateStatus(
                            string.format("%s (%.1f)", currentKind == "monster" and "👹 Monster" or "🎃 Pumpkin", distance),
                            currentKind
                        )
                        task.wait(0.03)
                    else
                        local goal = Vector3.new(targetPos.X, myPos.Y, targetPos.Z)
                        hum:MoveTo(goal)
                        updateStatus(
                            string.format("→ %s (%.1f)", currentKind == "monster" and "👹" or "🎃", distance),
                            currentKind
                        )
                        task.wait(CONFIG.RETARGET_INTERVAL)
                    end
                end
            end
        end
    end

    if activeHumanoid == hum and hum.Parent then
        pcall(function() hum:Move(Vector3.zero, false) end)
    end
    releaseE()
end

-- ============================================================
-- AUTO START
-- ============================================================
print("[AutoGrind] Starting...")

-- Cleanup map
print("[AutoGrind] Cleaning map...")
cleanMap()
print("[AutoGrind] Map cleaned.")

-- Start loop
isRunning = true
resetStats()
updateStatus("🔄 Started", "success")

task.spawn(mainLoop)

-- Respawn guard
player.CharacterAdded:Connect(function()
    if isRunning then
        print("[AutoGrind] Character respawned — stopping")
        isRunning = false
        runToken += 1
        releaseE()
    end
end)

print("[AutoGrind] Running. SeedPack priority aktif.")
