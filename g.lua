-- ============================================================
-- SEAT DETECTOR → SPACE + WALK PART4
-- GUI kotak minimalis ON/OFF di kanan layar
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
    TARGET_PATH = { "WitchCauldron", "WitchCauldron", "WitchCauldron", "Part4" },
    WALK_SPEED      = 20,
    ARRIVE_DISTANCE = 2,
    WALK_TIMEOUT    = 45,
    CHECK_INTERVAL  = 0.5,
    SEAT_COOLDOWN   = 3,
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
local function resolveArrayPath(path)
    local current = workspace
    for _, name in ipairs(path) do
        if not current then return nil end
        current = current:FindFirstChild(name)
    end
    return current
end

local function log(msg)
    print("[SeatWalk] " .. msg)
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
    log("␣ Space")
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
        if isSeated() then
            local now = tick()
            if now - lastSeatTime >= CONFIG.SEAT_COOLDOWN then
                lastSeatTime = now
                log("💺 Duduk → space + walk")
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
-- GUI KOTAK MINIMALIS (kanan layar, no drag, bisa close)
-- ============================================================
local COLORS = {
    bg      = Color3.fromRGB(22, 22, 28),
    text    = Color3.fromRGB(235, 235, 240),
    green   = Color3.fromRGB(80, 200, 120),
    red     = Color3.fromRGB(200, 70, 70),
    stroke  = Color3.fromRGB(60, 60, 72),
}

local function corner(p, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, r or 6)
    c.Parent = p
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "SeatWalkToggle"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = player:WaitForChild("PlayerGui")

local W, H = 110, 40

local frame = Instance.new("Frame")
frame.Size = UDim2.new(0, W, 0, H)
frame.Position = UDim2.new(1, -W - 12, 0.5, -H / 2)  -- kanan tengah
frame.BackgroundColor3 = COLORS.bg
frame.BackgroundTransparency = 0.1
frame.BorderSizePixel = 0
frame.Active = false  -- no drag
frame.Parent = screenGui
corner(frame, 8)

local stroke = Instance.new("UIStroke")
stroke.Color = COLORS.stroke
stroke.Transparency = 0.3
stroke.Thickness = 1.5
stroke.Parent = frame

-- Toggle button (kiri)
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

-- Close button (kanan)
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
        stop()
    else
        start()
    end
end)

closeBtn.MouseButton1Click:Connect(function()
    stop()
    screenGui:Destroy()
end)

player.CharacterAdded:Connect(function()
    if running then stop() end
end)

-- ============================================================
-- EXECUTE
-- ============================================================
_G.__SetToggle(false)
log("Loaded | toggle ON/OFF di kanan layar")
