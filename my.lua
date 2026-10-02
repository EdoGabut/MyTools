-- ============================================================
-- Auto Grind + SeedPack Priority (Minimal GUI - Left Side)
-- ============================================================
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local VirtualUser = game:GetService("VirtualUser")

local player = Players.LocalPlayer

-- ============================================================
-- CLEAR GARDENS (ClearAllChildren)
-- ============================================================
local g = workspace:FindFirstChild("Gardens")
if g then
    g:ClearAllChildren()
    print("✅ Gardens cleared!")
else
    warn("❌ Workspace.Gardens tidak ditemukan")
end

-- ============================================================
-- CONFIG
-- ============================================================
local CONFIG = {
    MONSTER_FOLDER = "Workspace.MonsterVisuals",
    PUMPKIN_FOLDER = "Workspace.Pumpkins",
    MONSTER_RANGE = 10,
    PUMPKIN_RANGE = 5,
    ATTACK_COOLDOWN = 0.12,
    RETARGET_INTERVAL = 0.1,

    SEEDPACK_PATH = "Workspace.Map.SeedPackSpawnServerLocations",
    SEEDPACK_STOP_DIST = 5,
    SEEDPACK_MOVE_TIMEOUT = 15,
    SEEDPACK_MOVE_REFRESH = 0.15,
    SEEDPACK_IDLE_DELAY = 0.5,
    SEEDPACK_TRIGGER_COOLDOWN = 0.1,
    SEEDPACK_TRIGGERED_TTL = 1.5,

    WALK_SPEED = 30,

    WITCH_PATH = "Workspace.WitchCauldron.WitchCauldron.WitchCauldron",

    DELETE_CHILDREN = {
        "Workspace.Map.Middle",
        "Workspace.Map.Stands",
        "Workspace.NPCS",
        "Workspace.ExplorerStand",
        "Workspace.AuctionStand",
    },
    DISABLE_COLLIDER = {
        "Workspace.WitchCauldron",
    },
}

-- ============================================================
-- STATE
-- ============================================================
local isRunning = false
local runToken = 0
local activeHumanoid = nil
local lastClickTime = 0

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
        local nearest = findNearestSeedPack(prompts, myPos, triggeredSet)

        if not nearest then
            task.wait(CONFIG.SEEDPACK_IDLE_DELAY)
        else
            local currentTarget = nearest

            while isRunningFn() and myToken == runToken do
                if not currentTarget or not currentTarget.Parent then
                    local newPrompts = getSeedPackPrompts()
                    if #newPrompts == 0 then
                        return true
                    end
                    local newNearest = findNearestSeedPack(newPrompts, root.Position, triggeredSet)
                    if not newNearest then break end
                    currentTarget = newNearest
                end

                local result = moveToSeedPack(
                    hum, root, currentTarget,
                    CONFIG.SEEDPACK_STOP_DIST,
                    function() return not isRunningFn() or myToken ~= runToken end
                )

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
-- FARM TARGET
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
                        bestDist = d; best = child; bestKind = "monster"
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
                    bestDist = d; best = child; bestKind = "pumpkin"
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

        -- Prioritas 1: SeedPack
        local seedPackPrompts = getSeedPackPrompts()
        if #seedPackPrompts > 0 then
            runSeedPackMode(hum, root, myToken, isRunningFn)
            currentTarget = nil
            currentKind = nil
            lastSearch = 0
        else
            -- Prioritas 2: Farm
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
    end

    if activeHumanoid == hum and hum.Parent then
        pcall(function() hum:Move(Vector3.zero, false) end)
    end
    releaseE()
end

-- ============================================================
-- MINIMAL GUI (LEFT SIDE)
-- ============================================================
local COLORS = {
    bg        = Color3.fromRGB(24, 24, 28),
    row       = Color3.fromRGB(30, 30, 36),
    text      = Color3.fromRGB(225, 225, 230),
    accentOn  = Color3.fromRGB(80, 200, 120),
    accentOff = Color3.fromRGB(55, 55, 65),
    stroke    = Color3.fromRGB(60, 60, 72),
    btn       = Color3.fromRGB(140, 80, 200),  -- ungu witch vibe
}

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "AutoGrindSeedPack"
screenGui.ResetOnSpawn = false
screenGui.Parent = player:WaitForChild("PlayerGui")

local main = Instance.new("Frame")
main.Size = UDim2.new(0, 180, 0, 100)
main.Position = UDim2.new(0, 20, 0.5, -50)   -- ← kiri tengah layar
main.BackgroundColor3 = COLORS.bg
main.BorderSizePixel = 0
main.Active = true
main.Draggable = true
main.Parent = screenGui
Instance.new("UICorner", main).CornerRadius = UDim.new(0, 10)

local mainStroke = Instance.new("UIStroke")
mainStroke.Color = COLORS.stroke
mainStroke.Thickness = 1
mainStroke.Transparency = 0.4
mainStroke.Parent = main

-- ===== Toggle row =====
local toggleRow = Instance.new("Frame")
toggleRow.Size = UDim2.new(1, -20, 0, 36)
toggleRow.Position = UDim2.new(0, 10, 0, 10)
toggleRow.BackgroundColor3 = COLORS.row
toggleRow.BorderSizePixel = 0
toggleRow.Parent = main
Instance.new("UICorner", toggleRow).CornerRadius = UDim.new(0, 7)

local toggleLbl = Instance.new("TextLabel")
toggleLbl.Size = UDim2.new(1, -70, 1, 0)
toggleLbl.Position = UDim2.new(0, 12, 0, 0)
toggleLbl.BackgroundTransparency = 1
toggleLbl.Text = "Auto Grind"
toggleLbl.TextColor3 = COLORS.text
toggleLbl.Font = Enum.Font.GothamMedium
toggleLbl.TextSize = 12
toggleLbl.TextXAlignment = Enum.TextXAlignment.Left
toggleLbl.Parent = toggleRow

local track = Instance.new("Frame")
track.Size = UDim2.new(0, 42, 0, 20)
track.Position = UDim2.new(1, -54, 0.5, -10)
track.BackgroundColor3 = COLORS.accentOff
track.BorderSizePixel = 0
track.Parent = toggleRow
Instance.new("UICorner", track).CornerRadius = UDim.new(1, 0)

local knob = Instance.new("Frame")
knob.Size = UDim2.new(0, 16, 0, 16)
knob.Position = UDim2.new(0, 2, 0.5, -8)
knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
knob.BorderSizePixel = 0
knob.Parent = track
Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)

local toggleClick = Instance.new("TextButton")
toggleClick.Size = UDim2.new(1, 0, 1, 0)
toggleClick.BackgroundTransparency = 1
toggleClick.Text = ""
toggleClick.BorderSizePixel = 0
toggleClick.Parent = toggleRow

local function setToggle(on)
    TweenService:Create(track, TweenInfo.new(0.15), {
        BackgroundColor3 = on and COLORS.accentOn or COLORS.accentOff
    }):Play()
    TweenService:Create(knob, TweenInfo.new(0.15), {
        Position = on
            and UDim2.new(1, -18, 0.5, -8)
            or UDim2.new(0, 2, 0.5, -8)
    }):Play()
    toggleLbl.TextColor3 = on and Color3.fromRGB(150, 240, 170) or COLORS.text
end

-- ===== Move to Witch Button =====
local moveBtn = Instance.new("TextButton")
moveBtn.Size = UDim2.new(1, -20, 0, 32)
moveBtn.Position = UDim2.new(0, 10, 0, 56)
moveBtn.BackgroundColor3 = COLORS.btn
moveBtn.Text = "Move to Witch"
moveBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
moveBtn.Font = Enum.Font.GothamBold
moveBtn.TextSize = 12
moveBtn.BorderSizePixel = 0
moveBtn.AutoButtonColor = false
moveBtn.Parent = main
Instance.new("UICorner", moveBtn).CornerRadius = UDim.new(0, 7)

moveBtn.MouseButton1Click:Connect(function()
    local char = player.Character
    if not char then return end
    local root = char:FindFirstChild("HumanoidRootPart")
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not root or not hum then return end

    local target = resolvePath(CONFIG.WITCH_PATH)
    if not target then
        local wc = resolvePath("Workspace.WitchCauldron")
        if wc then
            for _, d in ipairs(wc:GetDescendants()) do
                if d:IsA("BasePart") then target = d; break end
            end
        end
    end
    if not target then return end

    local targetPos = target:IsA("BasePart") and target.Position or target:GetPivot().Position
    local myPos = root.Position
    local goal = Vector3.new(targetPos.X, myPos.Y, targetPos.Z)
    hum:MoveTo(goal)

    task.spawn(function()
        local t0 = tick()
        while tick() - t0 < 10 do
            if not root.Parent then break end
            local d = (Vector3.new(goal.X, root.Position.Y, goal.Z) - root.Position).Magnitude
            if d < 4 then
                hum:Move(Vector3.zero, false)
                break
            end
            task.wait(0.1)
        end
    end)
end)

-- ============================================================
-- START / STOP
-- ============================================================
local function stopLoop()
    isRunning = false
    runToken += 1
    setToggle(false)
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
end

local function startLoop()
    cleanMap()
    isRunning = true
    setToggle(true)
    task.spawn(mainLoop)
end

-- ============================================================
-- EVENTS
-- ============================================================
toggleClick.MouseButton1Click:Connect(function()
    if isRunning then
        stopLoop()
    else
        startLoop()
    end
end)

player.CharacterAdded:Connect(function()
    if isRunning then
        stopLoop()
    end
end)
