-- ============================================
-- SIMPLE WELD TOGGLE (COMPACT)
-- - Slider on/off minimalis, compact
-- - Bisa di-drag & minimize
-- - Weld karakter di tempat (freeze posisi)
-- - Saat ON: anti-sit / anti-seat
-- ============================================

local CoreGui           = game:GetService("CoreGui")
local Players           = game:GetService("Players")
local UserInputService  = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer

-- ============ STATE ============
local ALIVE = true
local isWeldOn = false
local savedCFrame = nil
local antiSitConn = nil

-- ============ WELD LOGIC ============
local function weldCharacter()
    local char = LocalPlayer.Character
    if not char then return false end

    local hrp = char:FindFirstChild("HumanoidRootPart")
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if not hrp or not humanoid then return false end

    savedCFrame = hrp.CFrame

    -- Freeze physics
    for _, part in ipairs(char:GetDescendants()) do
        if part:IsA("BasePart") then
            part.Anchored = true
        end
    end

    humanoid.PlatformStand = true
    humanoid.WalkSpeed = 0
    humanoid.JumpPower = 0
    humanoid.JumpHeight = 0

    -- === Anti-sit / anti-seat ===
    -- Kalau humanoid lagi duduk, paksa berdiri
    pcall(function()
        humanoid.Sit = false
        humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
    end)

    -- Listener: begitu ada yang coba sit-kan, langsung tolak
    antiSitConn = humanoid.StateChanged:Connect(function(_, newState)
        if not isWeldOn then return end
        if newState == Enum.HumanoidStateType.Seated
           or newState == Enum.HumanoidStateType.Sitting then
            pcall(function()
                humanoid.Sit = false
                humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
            end)
        end
    end)

    return true
end

local function unweldCharacter()
    local char = LocalPlayer.Character
    if not char then return false end

    local humanoid = char:FindFirstChildOfClass("Humanoid")

    -- Putus listener anti-sit
    if antiSitConn then
        antiSitConn:Disconnect()
        antiSitConn = nil
    end

    for _, part in ipairs(char:GetDescendants()) do
        if part:IsA("BasePart") then
            part.Anchored = false
        end
    end

    if humanoid then
        humanoid.PlatformStand = false
        humanoid.WalkSpeed = 16
        humanoid.JumpPower = 50
        humanoid.JumpHeight = 7.2
    end

    savedCFrame = nil
    return true
end

-- ============ SHUTDOWN ============
local function shutdown(reason)
    if not ALIVE then return end
    ALIVE = false
    if isWeldOn then
        unweldCharacter()
        isWeldOn = false
    end
    if reason then
        print("🛑 Weld GUI dimatikan:", reason)
    end
end

-- ============ GUI ============
local old = CoreGui:FindFirstChild("SimpleWeld")
if old then old:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "SimpleWeld"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = CoreGui

-- Layout compact
local FULL_W = 130
local FULL_H = 36
local MINI_W = 90
local MINI_H = 24

local main = Instance.new("Frame")
main.Size = UDim2.new(0, FULL_W, 0, FULL_H)
main.Position = UDim2.new(0, 20, 0, 60)
main.BackgroundColor3 = Color3.fromRGB(24, 24, 30)
main.BorderSizePixel = 0
main.Active = true
main.Draggable = true
main.Parent = gui

local mc = Instance.new("UICorner")
mc.CornerRadius = UDim.new(0, 8)
mc.Parent = main

-- ===== Minimize button (pojok kiri atas) =====
local minBtn = Instance.new("TextButton")
minBtn.Size = UDim2.new(0, 16, 0, 16)
minBtn.Position = UDim2.new(0, 4, 0, 4)
minBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 62)
minBtn.Text = "—"
minBtn.TextColor3 = Color3.fromRGB(230, 230, 240)
minBtn.Font = Enum.Font.GothamBold
minBtn.TextSize = 11
minBtn.Parent = main

local minc = Instance.new("UICorner")
minc.CornerRadius = UDim.new(0, 5)
minc.Parent = minBtn

-- ===== Close button (pojok kanan atas) =====
local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 16, 0, 16)
closeBtn.Position = UDim2.new(1, -20, 0, 4)
closeBtn.BackgroundTransparency = 1
closeBtn.Text = "✕"
closeBtn.TextColor3 = Color3.fromRGB(255, 100, 100)
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 11
closeBtn.Parent = main

closeBtn.MouseButton1Click:Connect(function()
    shutdown("GUI ditutup")
    if gui then gui:Destroy() end
end)

-- ===== Body =====
local body = Instance.new("Frame")
body.Name = "Body"
body.Size = UDim2.new(1, 0, 1, -20)
body.Position = UDim2.new(0, 0, 0, 20)
body.BackgroundTransparency = 1
body.Parent = main

-- ===== Slider ON/OFF (compact) =====
local SLIDER_W = 44
local KNOB_W = 14
local SLIDER_RANGE = SLIDER_W - KNOB_W  -- 30px

local sliderTrack = Instance.new("Frame")
sliderTrack.Size = UDim2.new(0, SLIDER_W, 0, 14)
sliderTrack.Position = UDim2.new(0, 6, 0, 1)
sliderTrack.BackgroundColor3 = Color3.fromRGB(50, 50, 62)
sliderTrack.BorderSizePixel = 0
sliderTrack.Parent = body

local stc = Instance.new("UICorner")
stc.CornerRadius = UDim.new(0, 7)
stc.Parent = sliderTrack

local sliderKnob = Instance.new("Frame")
sliderKnob.Size = UDim2.new(0, KNOB_W, 0, 14)
sliderKnob.Position = UDim2.new(0, 0, 0, 0)
sliderKnob.BackgroundColor3 = Color3.fromRGB(230, 230, 240)
sliderKnob.BorderSizePixel = 0
sliderKnob.Parent = sliderTrack

local skc = Instance.new("UICorner")
skc.CornerRadius = UDim.new(0, 7)
skc.Parent = sliderKnob

-- Label ON/OFF (di kanan track)
local stateLbl = Instance.new("TextLabel")
stateLbl.Size = UDim2.new(0, 60, 0, 14)
stateLbl.Position = UDim2.new(0, 56, 0, 1)
stateLbl.BackgroundTransparency = 1
stateLbl.Text = "OFF"
stateLbl.TextColor3 = Color3.fromRGB(180, 180, 200)
stateLbl.Font = Enum.Font.GothamBold
stateLbl.TextSize = 10
stateLbl.TextXAlignment = Enum.TextXAlignment.Left
stateLbl.Parent = body

-- ===== Slider logic =====
local function updateSliderVisual(on)
    if on then
        sliderKnob.Position = UDim2.new(0, SLIDER_RANGE, 0, 0)
        sliderTrack.BackgroundColor3 = Color3.fromRGB(40, 130, 70)
        stateLbl.Text = "ON"
        stateLbl.TextColor3 = Color3.fromRGB(150, 255, 150)
    else
        sliderKnob.Position = UDim2.new(0, 0, 0, 0)
        sliderTrack.BackgroundColor3 = Color3.fromRGB(50, 50, 62)
        stateLbl.Text = "OFF"
        stateLbl.TextColor3 = Color3.fromRGB(180, 180, 200)
    end
end

local function toggleWeld()
    if not ALIVE then return end

    if isWeldOn then
        if unweldCharacter() then
            isWeldOn = false
            updateSliderVisual(false)
            print("🔓 Weld OFF")
        end
    else
        if weldCharacter() then
            isWeldOn = true
            updateSliderVisual(true)
            print("🔒 Weld ON (anti-sit aktif)")
        else
            warn("❌ Gagal weld (karakter belum spawn?)")
        end
    end
end

-- Klik track / knob = toggle
sliderTrack.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
       or input.UserInputType == Enum.UserInputType.Touch then
        toggleWeld()
    end
end)

-- Drag knob
local dragging = false

sliderKnob.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
       or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
       or input.UserInputType == Enum.UserInputType.Touch then
        dragging = false
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if not ALIVE then return end
    if not dragging then return end

    if input.UserInputType == Enum.UserInputType.MouseMovement
       or input.UserInputType == Enum.UserInputType.Touch then

        local trackX = sliderTrack.AbsolutePosition.X
        local relX = input.Position.X - trackX
        local pct = math.clamp((relX - KNOB_W/2) / SLIDER_RANGE, 0, 1)

        local newOn = pct > 0.5
        if newOn ~= isWeldOn then
            toggleWeld()
        end
    end
end)

-- ===== MINIMIZE LOGIC =====
local isMinimized = false

minBtn.MouseButton1Click:Connect(function()
    isMinimized = not isMinimized

    if isMinimized then
        body.Visible = false
        main.Size = UDim2.new(0, MINI_W, 0, MINI_H)
        minBtn.Text = "+"
    else
        body.Visible = true
        main.Size = UDim2.new(0, FULL_W, 0, FULL_H)
        minBtn.Text = "—"
    end
end)

-- ============ AUTO UNWELD SAAT RESPAWN ============
LocalPlayer.CharacterAdded:Connect(function()
    if isWeldOn then
        isWeldOn = false
        updateSliderVisual(false)
    end
end)

-- ============ CLEANUP HANDLER ============
gui.Destroying:Connect(function()
    shutdown("GUI Destroying event")
end)

Players.PlayerRemoving:Connect(function(p)
    if p == LocalPlayer then
        shutdown("Player keluar game")
    end
end)

-- ============ INIT ============
updateSliderVisual(false)
print("✅ Simple Weld GUI loaded")
