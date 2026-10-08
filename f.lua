-- ============================================================
-- BILLBOARD DISABLER + SEAT DETECTOR → SPACE + WALK PART4
-- ============================================================
local Players            = game:GetService("Players")
local RunService         = game:GetService("RunService")
local VirtualInputManager= game:GetService("VirtualInputManager")
local UserInputService   = game:GetService("UserInputService")

local player = Players.LocalPlayer

-- ============================================================
-- CONFIG
-- ============================================================
local CONFIG = {
    -- Root path yang di-scan BillboardGui-nya (descendant)
    BILLBOARD_ROOTS = {
        "game.Players.LocalPlayer.PlayerGui.WitchCauldron",
        "Workspace.WitchCauldron",
    },

    -- Tujuan walk
    TARGET_PATH = { "WitchCauldron", "WitchCauldron", "WitchCauldron", "Part4" },

    WALK_SPEED      = 20,
    ARRIVE_DISTANCE = 2,
    WALK_TIMEOUT    = 45,

    CHECK_INTERVAL  = 0.5,
    SEAT_COOLDOWN   = 1.5,
}

-- ============================================================
-- STATE
-- ============================================================
local running = false
local stopFlag = false
local walking = false
local lastSeatTime = 0
local walkConn = nil

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

local function log(msg)
    print("[BillboardSeat] " .. msg)
end

-- ============================================================
-- INPUT
-- ============================================================
local function pressSpace()
    pcall(function()
        VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.Space, false, game)
    end)
    task.wait(0.05)
    pcall(function()
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Space, false, game)
    end)
    log("␣ Space pressed")
end

-- ============================================================
-- BILLBOARD DISABLER
-- ============================================================
local function disableBillboards()
    for _, path in ipairs(CONFIG.BILLBOARD_ROOTS) do
        local root = resolvePath(path)
        if root then
            if root:IsA("BillboardGui") and root.Enabled then
                root.Enabled = false
                log("🚫 " .. root:GetFullName())
            end
            for _, d in ipairs(root:GetDescendants()) do
                if d:IsA("BillboardGui") and d.Enabled then
                    d.Enabled = false
                    log("🚫 " .. d:GetFullName())
                end
            end
        end
    end
end

-- ============================================================
-- SEAT CHECK
-- ============================================================
local function isSeated()
    local char = player.Character
    if not char then return false end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return false end
    return hum.Sit == true
end

-- ============================================================
-- WALK KE PART4
-- ============================================================
local function stopWalk()
    walking = false
    if walkConn then
        walkConn:Disconnect()
        walkConn = nil
    end
    local char = player.Character
    if char then
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum and hum.RootPart then
            pcall(function() hum:MoveTo(hum.RootPart.Position) end)
        end
    end
end

local function walkToPart4()
    if walking then return end
    local target = resolveArrayPath(CONFIG.TARGET_PATH)
    if not target or not target:IsA("BasePart") then
        log("❌ Part4 tidak ditemukan")
        return
    end

    local char = player.Character
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return end

    walking = true
    log("🚶 Walking ke Part4...")

    local tStart = tick()
    walkConn = RunService.Heartbeat:Connect(function()
        if stopFlag or not walking then
            if walkConn then walkConn:Disconnect() walkConn = nil end
            return
        end
        if tick() - tStart > CONFIG.WALK_TIMEOUT then
            log("⏱ Timeout")
            stopWalk()
            return
        end

        local c = player.Character
        if not c then stopWalk() return end
        local h = c:FindFirstChildOfClass("Humanoid")
        if not h then stopWalk() return end
        local root = c:FindFirstChild("HumanoidRootPart")
        if not root then stopWalk() return end

        local tgt = resolveArrayPath(CONFIG.TARGET_PATH)
        if not tgt then stopWalk() return end

        local myPos = root.Position
        local tgtPos = tgt.Position
        local flatDist = (Vector3.new(myPos.X, 0, myPos.Z) - Vector3.new(tgtPos.X, 0, tgtPos.Z)).Magnitude

        if flatDist <= CONFIG.ARRIVE_DISTANCE then
            log("✅ Sampai Part4")
            stopWalk()
            return
        end

        h.WalkSpeed = CONFIG.WALK_SPEED
        h:MoveTo(tgtPos)
    end)
end

-- ============================================================
-- MAIN LOOP
-- ============================================================
local function mainLoop()
    while running and not stopFlag do
        disableBillboards()

        if isSeated() then
            local now = tick()
            if now - lastSeatTime >= CONFIG.SEAT_COOLDOWN then
                lastSeatTime = now
                log("💺 Duduk terdeteksi → space + walk")
                pressSpace()
                task.wait(0.2)
                walkToPart4()
            end
        end

        task.wait(CONFIG.CHECK_INTERVAL)
    end
    log("⏹ Stopped")
end

-- ============================================================
-- START / STOP
-- ============================================================
local function start()
    if running then return end
    running = true
    stopFlag = false
    log("▶ Started")
    task.spawn(mainLoop)
    if _G.__SetToggle then _G.__SetToggle(true) end
end

local function stop()
    stopFlag = true
    running = false
    stopWalk()
    log("■ Stopped")
    if _G.__SetToggle then _G.__SetToggle(false) end
end

-- ============================================================
-- GUI TOGGLE BULAT MINIMALIS
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
screenGui.Name = "BillboardSeatToggle"
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
    if running then
        stop()
    else
        start()
    end
end)

player.CharacterAdded:Connect(function()
    if running then
        stop()
    end
end)

-- ============================================================
-- EXECUTE
-- ============================================================
_G.__SetToggle(false)
log("Loaded | toggle ON/OFF")
