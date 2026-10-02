-- ============================================================
-- Auto Grind + SeedPack Priority
-- Farm monster/pumpkin, prioritas seedpack kalau muncul
-- ============================================================
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
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

    -- Speed
    WALK_SPEED = 30,

    -- Cleanup
    DELETE_CHILDREN = {
        "Workspace.Map.Middle",
        "Workspace.Map.Stands",
        "Workspace.NPCS",
        "Workspace.ExplorerStand",
        "Workspace.AuctionStand",
        "Workspace.Gardens",
    },
    DISABLE_COLLIDER = {
        "Workspace.WitchCauldron",
    },
}

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
    while not folder do
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
-- SEEDPACK: SCAN & TRIGGER
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

-- Move to target via Humanoid:MoveTo, return status
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

-- SeedPack mode: return true kalau ada seedpack yg di-handle, false kalau folder kosong
local function runSeedPackMode(hum, root, myToken, isRunningFn)
    local triggeredSet = {}
    local lastTrigger = 0
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
            -- Folder kosong → keluar dari seedpack mode
            if handled then
                task.wait(CONFIG.SEEDPACK_IDLE_DELAY)
                -- Cek sekali lagi, kalau masih kosong, keluar
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
            continue
        end

        updateStatus(string.format("📦 SeedPack (%.1f stud)", dist), "seedpack")

        -- Move ke seedpack
        local currentTarget = nearest
        local cancelled = false

        while isRunningFn() and myToken == runToken and not cancelled do
            if not currentTarget or not currentTarget.Parent then
                -- Re-target
                local newPrompts = getSeedPackPrompts()
                if #newPrompts == 0 then
                    return true  -- folder kosong, keluar
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

    return true
end

-- ============================================================
-- FARM: CARI TARGET
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
-- STATE
-- ============================================================
local isRunning = false
local runToken = 0
local stats = { monster = 0, pumpkin = 0, seedpack = 0 }
local activeHumanoid = nil
local lastClickTime = 0

-- ============================================================
-- GUI
-- ============================================================
local COLORS = {
    bg         = Color3.fromRGB(24, 24, 28),
    header     = Color3.fromRGB(18, 18, 22),
    row        = Color3.fromRGB(30, 30, 36),
    text       = Color3.fromRGB(225, 225, 230),
    textDim    = Color3.fromRGB(140, 140, 150),
    accentOn   = Color3.fromRGB(80, 200, 120),
    accentOff  = Color3.fromRGB(55, 55, 65),
    stroke     = Color3.fromRGB(60, 60, 72),
    close      = Color3.fromRGB(200, 70, 70),
    minimize   = Color3.fromRGB(230, 180, 60),
    seedpack   = Color3.fromRGB(240, 180, 80),
    monster    = Color3.fromRGB(220, 100, 120),
    pumpkin    = Color3.fromRGB(240, 150, 60),
}

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "AutoGrindSeedPack"
screenGui.ResetOnSpawn = false
screenGui.Parent = player:WaitForChild("PlayerGui")

local FRAME_H = 210
local FRAME_H_MIN = 32

local main = Instance.new("Frame")
main.Size = UDim2.new(0, 240, 0, FRAME_H)
main.Position = UDim2.new(0, 20, 0, 20)
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

-- Title bar
local titleBar = Instance.new("Frame")
titleBar.Size = UDim2.new(1, 0, 0, 32)
titleBar.BackgroundColor3 = COLORS.header
titleBar.BorderSizePixel = 0
titleBar.Parent = main
Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 10)

local titleBarFix = Instance.new("Frame")
titleBarFix.Size = UDim2.new(1, 0, 0, 10)
titleBarFix.Position = UDim2.new(0, 0, 1, -10)
titleBarFix.BackgroundColor3 = COLORS.header
titleBarFix.BorderSizePixel = 0
titleBarFix.Parent = titleBar

local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(1, -80, 1, 0)
titleLabel.Position = UDim2.new(0, 14, 0, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "Auto Grind + SeedPack"
titleLabel.TextColor3 = COLORS.text
titleLabel.Font = Enum.Font.GothamBold
titleLabel.TextSize = 12
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.Parent = titleBar

local minBtn = Instance.new("TextButton")
minBtn.Size = UDim2.new(0, 22, 0, 22)
minBtn.Position = UDim2.new(1, -54, 0, 5)
minBtn.BackgroundColor3 = COLORS.minimize
minBtn.Text = "−"
minBtn.TextColor3 = Color3.fromRGB(30, 30, 30)
minBtn.Font = Enum.Font.GothamBold
minBtn.TextSize = 14
minBtn.BorderSizePixel = 0
minBtn.AutoButtonColor = false
minBtn.Parent = titleBar
Instance.new("UICorner", minBtn).CornerRadius = UDim.new(0, 6)

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 22, 0, 22)
closeBtn.Position = UDim2.new(1, -28, 0, 5)
closeBtn.BackgroundColor3 = COLORS.close
closeBtn.Text = "×"
closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 16
closeBtn.BorderSizePixel = 0
closeBtn.AutoButtonColor = false
closeBtn.Parent = titleBar
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 6)

-- Body
local body = Instance.new("Frame")
body.Size = UDim2.new(1, -16, 1, -42)
body.Position = UDim2.new(0, 8, 0, 38)
body.BackgroundTransparency = 1
body.Parent = main

local bodyLayout = Instance.new("UIListLayout")
bodyLayout.Padding = UDim.new(0, 4)
bodyLayout.SortOrder = Enum.SortOrder.LayoutOrder
bodyLayout.Parent = body

-- Status label
local statusLbl = Instance.new("TextLabel")
statusLbl.Size = UDim2.new(1, 0, 0, 24)
statusLbl.BackgroundColor3 = COLORS.row
statusLbl.BorderSizePixel = 0
statusLbl.Text = "⏸ Idle"
statusLbl.TextColor3 = COLORS.text
statusLbl.Font = Enum.Font.GothamMedium
statusLbl.TextSize = 11
statusLbl.TextXAlignment = Enum.TextXAlignment.Left
statusLbl.LayoutOrder = 1
statusLbl.Parent = body
Instance.new("UICorner", statusLbl).CornerRadius = UDim.new(0, 6)
local statusPad = Instance.new("UIPadding", statusLbl)
statusPad.PaddingLeft = UDim.new(0, 10)

-- Stats label
local statsLbl = Instance.new("TextLabel")
statsLbl.Size = UDim2.new(1, 0, 0, 18)
statsLbl.BackgroundTransparency = 1
statsLbl.Text = "📦 0  |  👹 0  |  🎃 0"
statsLbl.TextColor3 = COLORS.textDim
statsLbl.Font = Enum.Font.Code
statsLbl.TextSize = 10
statsLbl.TextXAlignment = Enum.TextXAlignment.Left
statsLbl.LayoutOrder = 2
statsLbl.Parent = body

-- Toggle row
local function makeToggle(text, order, initialState)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 36)
    row.BackgroundColor3 = COLORS.row
    row.BorderSizePixel = 0
    row.LayoutOrder = order
    row.Parent = body
    Instance.new("UICorner", row).CornerRadius = UDim.new(0, 7)

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, -70, 1, 0)
    lbl.Position = UDim2.new(0, 12, 0, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text = text
    lbl.TextColor3 = COLORS.text
    lbl.Font = Enum.Font.GothamMedium
    lbl.TextSize = 12
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = row

    local track = Instance.new("Frame")
    track.Size = UDim2.new(0, 42, 0, 20)
    track.Position = UDim2.new(1, -54, 0.5, -10)
    track.BackgroundColor3 = initialState and COLORS.accentOn or COLORS.accentOff
    track.BorderSizePixel = 0
    track.Parent = row
    Instance.new("UICorner", track).CornerRadius = UDim.new(1, 0)

    local knob = Instance.new("Frame")
    knob.Size = UDim2.new(0, 16, 0, 16)
    knob.Position = initialState
        and UDim2.new(1, -18, 0.5, -8)
        or UDim2.new(0, 2, 0.5, -8)
    knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    knob.BorderSizePixel = 0
    knob.Parent = track
    Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)

    local click = Instance.new("TextButton")
    click.Size = UDim2.new(1, 0, 1, 0)
    click.BackgroundTransparency = 1
    click.Text = ""
    click.BorderSizePixel = 0
    click.Parent = row

    local state = initialState

    local function set(on)
        state = on
        TweenService:Create(track, TweenInfo.new(0.15), {
            BackgroundColor3 = on and COLORS.accentOn or COLORS.accentOff
        }):Play()
        TweenService:Create(knob, TweenInfo.new(0.15), {
            Position = on
                and UDim2.new(1, -18, 0.5, -8)
                or UDim2.new(0, 2, 0.5, -8)
        }):Play()
        lbl.TextColor3 = on and Color3.fromRGB(150, 240, 170) or COLORS.text
    end

    return row, click, set, function() return state end
end

local _, toggleClick, toggleSet, toggleGet = makeToggle("Auto Grind", 3, false)

-- ============================================================
-- STATUS HELPERS
-- ============================================================
local function updateStatus(text, colorKey)
    statusLbl.Text = text
    local c = COLORS.text
    if colorKey == "seedpack" then c = COLORS.seedpack
    elseif colorKey == "monster" then c = COLORS.monster
    elseif colorKey == "pumpkin" then c = COLORS.pumpkin
    elseif colorKey == "success" then c = COLORS.accentOn
    elseif colorKey == "fail" then c = COLORS.close
    end
    statusLbl.TextColor3 = c
end

local function updateStats()
    statsLbl.Text = string.format("📦 %d  |  👹 %d  |  🎃 %d",
        stats.seedpack, stats.monster, stats.pumpkin)
end

local function resetStats()
    stats.seedpack = 0
    stats.monster = 0
    stats.pumpkin = 0
    updateStats()
end

-- ============================================================
-- MAIN LOOP
-- ============================================================
local function mainLoop()
    local monsterFolder = waitFolder(CONFIG.MONSTER_FOLDER)
    local pumpkinFolder = waitFolder(CONFIG.PUMPKIN_FOLDER)

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
            -- Setelah seedpack selesai/kosong, reset target farm
            currentTarget = nil
            currentKind = nil
            lastSearch = 0
            goto continue
        end

        -- =================================================
        -- PRIORITAS 2: FARM
        -- =================================================
        hum.WalkSpeed = CONFIG.WALK_SPEED
        local myPos = root.Position
        local now = tick()

        -- Validasi target
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

        -- Cari target baru
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
                        updateStats()
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

        ::continue::
    end

    -- Cleanup
    if activeHumanoid == hum and hum.Parent then
        pcall(function() hum:Move(Vector3.zero, false) end)
    end
    releaseE()
end

-- ============================================================
-- STOP / START
-- ============================================================
local function stopLoop()
    isRunning = false
    runToken += 1
    toggleSet(false)
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

    updateStatus("⏸ Stopped", "fail")
end

local function startLoop()
    -- Cleanup map dulu
    updateStatus("🧹 Cleanup map...", nil)
    cleanMap()

    isRunning = true
    toggleSet(true)
    resetStats()
    updateStatus("🔄 Starting...", "success")

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

-- Minimize
local isMinimized = false
minBtn.MouseButton1Click:Connect(function()
    isMinimized = not isMinimized
    if isMinimized then
        body.Visible = false
        main.Size = UDim2.new(0, 240, 0, FRAME_H_MIN)
        minBtn.Text = "+"
    else
        body.Visible = true
        main.Size = UDim2.new(0, 240, 0, FRAME_H)
        minBtn.Text = "−"
    end
end)

-- Close
closeBtn.MouseButton1Click:Connect(function()
    stopLoop()
    screenGui:Destroy()
end)

-- Character respawn guard
player.CharacterAdded:Connect(function()
    if isRunning then
        stopLoop()
        updateStatus("⚠ Respawn — stop", "fail")
    end
end)

-- Init
updateStats()
updateStatus("⏸ Idle", nil)
