-- ============================================================
-- Auto Brew — Cek Malam Sekali, lalu Loop
-- Alur:
--   1. Tunggu malam SEKALI (ClockTime >= 18 atau < 6)
--   2. Loop terus:
--        a. Fire Briar
--        b. Fire Spirethorn
--        c. Tunggu 12 menit
--        d. Fire Claim
--        e. Tunggu 5 detik
--        f. Ulang
-- ============================================================
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local UserInputService  = game:GetService("UserInputService")
local Lighting          = game:GetService("Lighting")

local player = Players.LocalPlayer

local remote = ReplicatedStorage
    :WaitForChild("SharedModules")
    :WaitForChild("Packet")
    :WaitForChild("RemoteEvent")

-- ============================================================
-- CONFIG
-- ============================================================
local CONFIG = {
    BREW_WAIT      = 11 * 60,   -- 720s
    CLAIM_WAIT     = 5,
    POST_FIRE_WAIT = 1.5,       -- jeda Briar → Spirethorn
    NIGHT_POLL     = 0.5,       -- interval cek malam (sekali saja)
}

-- Payload (cache sekali)
local BRIAR      = buffer.fromstring("\195\0009\nBriar Rose")
local SPIRETHORN = buffer.fromstring("\195\000^\016Common Seed Pack")
local CLAIM      = buffer.fromstring("\196\000O")

-- ============================================================
-- STATE
-- ============================================================
local isRunning = false
local runToken  = 0

-- ============================================================
-- HELPERS
-- ============================================================
local function isNight()
    local ct = tonumber(Lighting.ClockTime) or 0
    local h = ((math.floor(ct) % 24) + 24) % 24
    return h >= 18 or h < 6
end

local function preciseWait(seconds, isCancelled)
    local deadline = os.clock() + seconds
    while true do
        if isCancelled and isCancelled() then return false end
        local remaining = deadline - os.clock()
        if remaining <= 0 then return true end
        task.wait(math.min(remaining, 0.25))
    end
end

-- ============================================================
-- GUI
-- ============================================================
local COLORS = {
    bg        = Color3.fromRGB(22, 22, 28),
    header    = Color3.fromRGB(16, 16, 20),
    text      = Color3.fromRGB(235, 235, 240),
    green     = Color3.fromRGB(80, 200, 120),
    greenHv   = Color3.fromRGB(100, 220, 140),
    red       = Color3.fromRGB(200, 70, 70),
    yellow    = Color3.fromRGB(220, 180, 80),
    accentOff = Color3.fromRGB(60, 60, 72),
    stroke    = Color3.fromRGB(60, 60, 72),
}

local function corner(p, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, r or 8)
    c.Parent = p
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "AutoBrewMini"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Parent = player:WaitForChild("PlayerGui")

local FRAME_WIDTH  = 170
local FRAME_HEIGHT = 76

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
        dragging  = true
        dragStart = input.Position
        startPos  = frame.Position
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
title.Text = "🍺 Auto Brew"
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

-- Toggle
local toggleBtn = Instance.new("TextButton")
toggleBtn.Size = UDim2.new(1, -16, 0, 36)
toggleBtn.Position = UDim2.new(0, 8, 0, 32)
toggleBtn.BackgroundColor3 = COLORS.green
toggleBtn.Text = "▶ START"
toggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
toggleBtn.Font = Enum.Font.GothamBold
toggleBtn.TextSize = 13
toggleBtn.BorderSizePixel = 0
toggleBtn.AutoButtonColor = false
toggleBtn.Parent = frame
corner(toggleBtn, 8)

local function setToggleUI(state) -- "idle" | "running" | "waiting"
    if state == "running" then
        toggleBtn.Text = "■ STOP"
        toggleBtn.BackgroundColor3 = COLORS.red
    elseif state == "waiting" then
        toggleBtn.Text = "… WAIT"
        toggleBtn.BackgroundColor3 = COLORS.yellow
    else
        toggleBtn.Text = "▶ START"
        toggleBtn.BackgroundColor3 = COLORS.green
    end
end

-- ============================================================
-- MAIN CYCLE
-- ============================================================
local function mainCycle()
    runToken += 1
    local myToken = runToken

    local function cancelled()
        return not isRunning or myToken ~= runToken
    end

    -- ===== 1. TUNGGU MALAM (SEKALI SAJA) =====
    setToggleUI("waiting")
    while not cancelled() and not isNight() do
        task.wait(CONFIG.NIGHT_POLL)
    end
    if cancelled() then return end

    setToggleUI("running")
    print("[AutoBrew] Malam tiba, mulai loop...")

    -- ===== 2. LOOP TERUS TANPA CEK MALAM LAGI =====
    while not cancelled() do
        -- a. Fire Briar
        remote:FireServer(BRIAR)
        if not preciseWait(CONFIG.POST_FIRE_WAIT, cancelled) then break end

        -- b. Fire Spirethorn
        remote:FireServer(SPIRETHORN)
        if not preciseWait(CONFIG.POST_FIRE_WAIT, cancelled) then break end

        -- c. Tunggu 12 menit
        if not preciseWait(CONFIG.BREW_WAIT, cancelled) then break end

        -- d. Fire Claim
        remote:FireServer(CLAIM)
        if not preciseWait(CONFIG.CLAIM_WAIT, cancelled) then break end

        -- e. Ulang
    end
end

-- ============================================================
-- START / STOP
-- ============================================================
local function startLoop()
    if isRunning then return end
    isRunning = true
    setToggleUI("waiting")
    task.spawn(mainCycle)
end

local function stopLoop()
    if not isRunning then return end
    isRunning = false
    runToken += 1
    setToggleUI("idle")
end

toggleBtn.MouseButton1Click:Connect(function()
    if isRunning then stopLoop() else startLoop() end
end)

toggleBtn.MouseEnter:Connect(function()
    if not isRunning then
        TweenService:Create(toggleBtn, TweenInfo.new(0.1), {
            BackgroundColor3 = COLORS.greenHv
        }):Play()
    end
end)
toggleBtn.MouseLeave:Connect(function()
    if not isRunning then
        TweenService:Create(toggleBtn, TweenInfo.new(0.1), {
            BackgroundColor3 = COLORS.green
        }):Play()
    end
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
    else
        TweenService:Create(frame, TweenInfo.new(0.2), {
            Size = UDim2.new(0, FRAME_WIDTH, 0, savedSize)
        }):Play()
        toggleBtn.Visible = true
    end
end)

closeBtn.MouseButton1Click:Connect(function()
    stopLoop()
    screenGui:Destroy()
end)

-- ============================================================
-- INIT
-- ============================================================
setToggleUI("idle")
