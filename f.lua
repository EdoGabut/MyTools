-- ============================================================
-- Auto LMB Clicker — VampireFox (MINIMAL GUI)
-- ============================================================
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

-- ===== CONFIG =====
local CONFIG = {
    ModelsPath = "game.Workspace._PetVisualClient.Models",
    NameFilter = "VampireFox",
    MinDist = 0,
    MaxDist = 10,
    ClickCooldown = 0.05,

    ScanInterval      = 0.05,
    ScanIntervalIdle  = 0.20,
}

-- ===== STATE =====
local enabled = false
local lastScan = 0
local lastClick = 0
local conn = nil

local nearestDist = math.huge
local inRange = 0
local total = 0
local clickCount = 0
local isClicking = false
local isIdleState = true

-- ===== UTILS =====
local function resolvePath(pathStr)
    local node = game
    for seg in pathStr:gmatch("[^%.]+") do
        if seg == "game" then
            node = game
        elseif seg == "LocalPlayer" then
            node = player
        else
            node = node and node:FindFirstChild(seg)
            if not node then return nil end
        end
    end
    return node
end

local function getHumanoidRoot()
    local char = player.Character
    return char and char:FindFirstChild("HumanoidRootPart")
end

local function findRootPart(model)
    local rp = model:FindFirstChild("RootPart")
    if rp and rp:IsA("BasePart") then return rp end
    rp = model:FindFirstChild("HumanoidRootPart")
    if rp and rp:IsA("BasePart") then return rp end
    if model.PrimaryPart then return model.PrimaryPart end
    for _, d in ipairs(model:GetChildren()) do
        if d:IsA("BasePart") then return d end
    end
    return nil
end

local function clickLMB()
    pcall(VirtualInputManager.SendMouseButtonEvent, VirtualInputManager,
        0, 0, 0, true, game, 1)
    pcall(VirtualInputManager.SendMouseButtonEvent, VirtualInputManager,
        0, 0, 0, false, game, 1)
end

-- ===== SCAN =====
local filterLower = CONFIG.NameFilter:lower()
local modelsPath = CONFIG.ModelsPath

local function scanFoxes(myPos)
    local container = resolvePath(modelsPath)
    if not container then
        nearestDist, inRange, total = math.huge, 0, 0
        return
    end

    local near, cnt, tot = math.huge, 0, 0
    local minD, maxD = CONFIG.MinDist, CONFIG.MaxDist

    for _, child in ipairs(container:GetChildren()) do
        if child:IsA("Model") and child.Name:lower():find(filterLower, 1, true) then
            tot += 1
            local rp = findRootPart(child)
            if rp then
                local d = (rp.Position - myPos).Magnitude
                if d < near then near = d end
                if d >= minD and d <= maxD then cnt += 1 end
            end
        end
    end

    nearestDist, inRange, total = near, cnt, tot
end

-- ============================================================
-- GUI MINIMALIS
-- ============================================================
local COLORS = {
    bg=Color3.fromRGB(22,22,28), header=Color3.fromRGB(16,16,20),
    text=Color3.fromRGB(235,235,240),
    green=Color3.fromRGB(80,200,120), greenHv=Color3.fromRGB(100,220,140),
    red=Color3.fromRGB(200,70,70),
    stroke=Color3.fromRGB(60,60,72),
}

local function corner(p, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, r or 8)
    c.Parent = p
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "VampireFoxMultiClicker"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = player:WaitForChild("PlayerGui")

local FRAME_WIDTH = 150
local FRAME_HEIGHT = 66

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
header.Size = UDim2.new(1, 0, 0, 22)
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
title.Text = "🦊 Fox Clicker"
title.TextColor3 = COLORS.text
title.Font = Enum.Font.GothamBold
title.TextSize = 11
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = header

local function makeHeaderBtn(xOffset, bg, txt)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(0, 16, 0, 16)
    b.Position = UDim2.new(1, xOffset, 0, 3)
    b.BackgroundColor3 = bg
    b.Text = txt
    b.TextColor3 = Color3.fromRGB(255, 255, 255)
    b.Font = Enum.Font.GothamBold
    b.TextSize = 11
    b.BorderSizePixel = 0
    b.AutoButtonColor = false
    b.Parent = header
    corner(b, 4)
    return b
end

local minimizeBtn = makeHeaderBtn(-38, COLORS.stroke, "—")
local closeBtn    = makeHeaderBtn(-19, COLORS.red, "×")

-- Toggle Button
local toggleBtn = Instance.new("TextButton")
toggleBtn.Size = UDim2.new(1, -16, 0, 34)
toggleBtn.Position = UDim2.new(0, 8, 0, 28)
toggleBtn.BackgroundColor3 = COLORS.green
toggleBtn.Text = "▶ START"
toggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
toggleBtn.Font = Enum.Font.GothamBold
toggleBtn.TextSize = 13
toggleBtn.BorderSizePixel = 0
toggleBtn.AutoButtonColor = false
toggleBtn.Parent = frame
corner(toggleBtn, 8)

-- ============================================================
-- MAIN LOOP
-- ============================================================
local startLoop, stopLoop

startLoop = function()
    if conn then conn:Disconnect() end

    conn = RunService.Heartbeat:Connect(function()
        if not enabled then return end

        local now = tick()

        local scanInterval = isIdleState and CONFIG.ScanIntervalIdle or CONFIG.ScanInterval
        if now - lastScan >= scanInterval then
            lastScan = now

            local humanRoot = getHumanoidRoot()
            if not humanRoot then return end

            scanFoxes(humanRoot.Position)
            isIdleState = (total == 0)
        end

        if total == 0 then
            isClicking = false
            return
        end

        if inRange > 0 then
            isClicking = true
            if now - lastClick >= CONFIG.ClickCooldown then
                lastClick = now
                clickCount += 1
                clickLMB()
            end
        else
            isClicking = false
        end
    end)
end

stopLoop = function()
    if conn then
        conn:Disconnect()
        conn = nil
    end
    isClicking = false
end

-- ============================================================
-- BUTTON EVENTS
-- ============================================================
local function setToggleUI(on)
    if on then
        toggleBtn.Text = "■ STOP"
        toggleBtn.BackgroundColor3 = COLORS.red
        stroke.Color = COLORS.green
    else
        toggleBtn.Text = "▶ START"
        toggleBtn.BackgroundColor3 = COLORS.green
        stroke.Color = COLORS.stroke
    end
end

toggleBtn.MouseButton1Click:Connect(function()
    enabled = not enabled
    if enabled then
        clickCount = 0
        startLoop()
        setToggleUI(true)
        print("[MultiFox] ON |", CONFIG.NameFilter, "|", CONFIG.MinDist, "-", CONFIG.MaxDist)
    else
        stopLoop()
        setToggleUI(false)
        print("[MultiFox] OFF")
    end
end)

toggleBtn.MouseEnter:Connect(function()
    if not enabled then
        TweenService:Create(toggleBtn, TweenInfo.new(0.1), {
            BackgroundColor3 = COLORS.greenHv
        }):Play()
    end
end)
toggleBtn.MouseLeave:Connect(function()
    if not enabled then
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
            Size = UDim2.new(0, FRAME_WIDTH, 0, 22)
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
-- RESPAWN HANDLER
-- ============================================================
player.CharacterAdded:Connect(function()
    if enabled then
        enabled = false
        stopLoop()
        setToggleUI(false)
    end
end)

-- ============================================================
-- INIT
-- ============================================================
setToggleUI(false)
print("[MultiFox Minimal] Loaded.")
