-- ============================================
-- AUTO HARVEST + AUTO-SELL + WELD + ANTI-SIT + ANTI-AFK
-- (COMBINED FINAL)
--
-- Payload Harvest: )\001$uuid[flag][index]
-- Payload Sell:    \015\001\018
-- Rumus: weight = SizeMulti × 9
-- Preset: 80 / 100 kg
-- Priority mutations (langsung panen): Electric, Gold, Frozen, Rainbow, Starstruck
-- Plot terdeteksi via nickname di Signs
-- Guard: semua loop mati saat GUI ditutup
-- ============================================

local CoreGui           = game:GetService("CoreGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")
local UserInputService  = game:GetService("UserInputService")
local VirtualUser       = game:GetService("VirtualUser")

local LocalPlayer = Players.LocalPlayer

local Packet = ReplicatedStorage:WaitForChild("SharedModules")
    :WaitForChild("Packet"):WaitForChild("RemoteEvent")

local ROOT = workspace:WaitForChild("Gardens")

-- ============ CONFIG ============

local CONFIG = {
    MAX_WEIGHT          = 80,
    AUTO_ENABLED        = false,
    AUTO_SELL_ENABLED   = false,
    AUTO_SELL_INTERVAL  = 5,
    AUTO_DELAY          = 0.25,
    ONLY_MY_PLOTS       = true,
    WELD_ENABLED        = false,   -- master slider (weld + anti-sit + anti-afk)
}

local WEIGHT_K = 9

-- Mutasi PRIORITAS (langsung panen, abaikan berat)
local PRIORITY_MUTATIONS = {
    Electric    = true,
    Gold        = true,
    Frozen      = true,
    Rainbow     = true,
    Starstruck  = true,
}

local SELL_PAYLOAD = "\015\001\018"

-- ============ STATE ============

local ALIVE        = true
local isWeldOn     = false
local antiSitConn  = nil
local antiAfkConn  = nil
local antiAfkThread = nil

-- ============ PLOT DETECTION ============

local MY_PLOT_NAME = nil

local function detectMyPlot()
    local mySign = LocalPlayer.DisplayName .. "'s Garden"

    for _, plot in ipairs(ROOT:GetChildren()) do
        local signs = plot:FindFirstChild("Signs")
        if signs then
            local garden = signs:FindFirstChild("Garden")
            local core   = garden and garden:FindFirstChild("CorePart")
            local sg     = core and core:FindFirstChild("SurfaceGui")
            local playerLbl = sg and sg:FindFirstChild("Player")
            local textLbl   = playerLbl and playerLbl:FindFirstChild("TextLabel")

            if textLbl and textLbl.Text == mySign then
                MY_PLOT_NAME = plot.Name
                print("✅ Plot terdeteksi:", MY_PLOT_NAME)
                return MY_PLOT_NAME
            end
        end
    end
    return nil
end

local function getMyPlot()
    if not MY_PLOT_NAME or not ROOT:FindFirstChild(MY_PLOT_NAME) then
        local old = MY_PLOT_NAME
        MY_PLOT_NAME = nil
        detectMyPlot()
        if old and MY_PLOT_NAME and MY_PLOT_NAME ~= old then
            print("🔄 Plot berubah:", old, "→", MY_PLOT_NAME)
        end
    end
    return MY_PLOT_NAME and ROOT:FindFirstChild(MY_PLOT_NAME) or nil
end

detectMyPlot()

-- ============ UTIL ============

local function getPlantUuid(plant)
    return plant.Name:match("_(.+)$")
end

local function getFruitIndex(fruit)
    return fruit.Name:match("_(%d+)$")
end

local function getOwnerId(plant)
    local id = plant.Name:match("^(%d+)_")
    return id and tonumber(id) or nil
end

local function getSizeMulti(fruit)
    local ok, val = pcall(function() return fruit:GetAttribute("SizeMulti") end)
    if ok and val then return val end
    local model = fruit:IsA("Model") and fruit or fruit:FindFirstChildOfClass("Model")
    if model then
        local ok2, val2 = pcall(function() return model:GetAttribute("SizeMulti") end)
        if ok2 and val2 then return val2 end
    end
    return nil
end

local function getFruitWeight(fruit)
    local sm = getSizeMulti(fruit)
    if not sm then return nil end
    return sm * WEIGHT_K
end

local function getMutation(fruit)
    local ok, val = pcall(function() return fruit:GetAttribute("Mutation") end)
    if ok and val and val ~= "" and val ~= "None" then
        return val
    end
    local model = fruit:IsA("Model") and fruit or fruit:FindFirstChildOfClass("Model")
    if model then
        local ok2, val2 = pcall(function() return model:GetAttribute("Mutation") end)
        if ok2 and val2 and val2 ~= "" and val2 ~= "None" then
            return val2
        end
    end
    return nil
end

local function harvest(plant, fruit)
    if not ALIVE then return false end
    local uuid  = getPlantUuid(plant)
    local index = getFruitIndex(fruit)
    if not uuid or not index then return false end

    local flag = string.char(#index)
    local payload = ")\001$" .. uuid .. flag .. index

    local ok = pcall(function()
        Packet:FireServer(buffer.fromstring(payload))
    end)
    return ok
end

local function sellBackpack()
    if not ALIVE then return false end
    local ok = pcall(function()
        Packet:FireServer(buffer.fromstring(SELL_PAYLOAD))
    end)
    return ok
end

-- ============ WELD / ANTI-SIT ============

local function weldCharacter()
    local char = LocalPlayer.Character
    if not char then return false end

    local hrp      = char:FindFirstChild("HumanoidRootPart")
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if not hrp or not humanoid then return false end

    for _, part in ipairs(char:GetDescendants()) do
        if part:IsA("BasePart") then
            part.Anchored = true
        end
    end

    humanoid.PlatformStand = true
    humanoid.WalkSpeed     = 0
    humanoid.JumpPower     = 0
    humanoid.JumpHeight    = 0

    pcall(function()
        humanoid.Sit = false
        humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
    end)

    -- Anti-sit listener
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
        humanoid.WalkSpeed     = 16
        humanoid.JumpPower     = 50
        humanoid.JumpHeight    = 7.2
    end

    return true
end

-- ============ ANTI-AFK ============

local function startAntiAfk()
    -- Idled event (untuk kasus Roblox idle detection)
    if not antiAfkConn then
        antiAfkConn = LocalPlayer.Idled:Connect(function()
            if not ALIVE or not CONFIG.WELD_ENABLED then return end
            pcall(function()
                VirtualUser:CaptureController()
                VirtualUser:ClickButton2(Vector2.new())
            end)
        end)
    end

    -- Loop klik LMB 3x tiap 5-10 menit acak
    if not antiAfkThread then
        antiAfkThread = task.spawn(function()
            while ALIVE do
                task.wait(1)
                if not CONFIG.WELD_ENABLED then
                    -- tunggu sampai slider ON
                    continue
                end

                -- 3x klik LMB
                for i = 1, 3 do
                    if not ALIVE or not CONFIG.WELD_ENABLED then break end
                    pcall(function()
                        VirtualUser:CaptureController()
                        local pos = UserInputService:GetMouseLocation()
                        VirtualUser:ClickButton1(Vector2.new(pos.X, pos.Y))
                    end)
                    task.wait(0.15 + math.random() * 0.15)
                end

                -- tunggu 5-10 menit (300-600 detik), tapi tetap cek toggle tiap detik
                local totalWait = math.random(300, 600)
                local elapsed   = 0
                while elapsed < totalWait and ALIVE do
                    task.wait(1)
                    elapsed = elapsed + 1
                    if not CONFIG.WELD_ENABLED then break end
                end
            end
        end)
    end
end

local function stopAntiAfk()
    if antiAfkConn then
        antiAfkConn:Disconnect()
        antiAfkConn = nil
    end
    if antiAfkThread then
        antiAfkThread = nil  -- biar loop-nya berhenti sendiri via cek CONFIG
    end
end

-- ============ SHUTDOWN ============

local function shutdown(reason)
    if not ALIVE then return end
    ALIVE = false
    CONFIG.AUTO_ENABLED      = false
    CONFIG.AUTO_SELL_ENABLED = false
    CONFIG.WELD_ENABLED      = false

    if isWeldOn then
        pcall(unweldCharacter)
        isWeldOn = false
    end
    pcall(stopAntiAfk)

    if reason then
        print("🛑 Script dimatikan:", reason)
    end
end

-- ============ GUI ============

local old = CoreGui:FindFirstChild("AutoHarvestMini")
if old then old:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "AutoHarvestMini"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = CoreGui

local FULL_HEIGHT = 254
local MINI_HEIGHT = 28

local main = Instance.new("Frame")
main.Size = UDim2.new(0, 200, 0, FULL_HEIGHT)
main.Position = UDim2.new(0, 20, 0, 60)
main.BackgroundColor3 = Color3.fromRGB(24, 24, 30)
main.BorderSizePixel = 0
main.Active = true
main.Draggable = true
main.Parent = gui

local mc = Instance.new("UICorner")
mc.CornerRadius = UDim.new(0, 10)
mc.Parent = main

-- ===== HEADER =====
local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 28)
header.BackgroundColor3 = Color3.fromRGB(40, 40, 52)
header.BorderSizePixel = 0
header.Parent = main

local hc = Instance.new("UICorner")
hc.CornerRadius = UDim.new(0, 10)
hc.Parent = header

local headerFix = Instance.new("Frame")
headerFix.Size = UDim2.new(1, 0, 0, 10)
headerFix.Position = UDim2.new(0, 0, 1, -10)
headerFix.BackgroundColor3 = Color3.fromRGB(40, 40, 52)
headerFix.BorderSizePixel = 0
headerFix.Parent = header

local minBtn = Instance.new("TextButton")
minBtn.Size = UDim2.new(0, 22, 0, 22)
minBtn.Position = UDim2.new(0, 4, 0, 3)
minBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 75)
minBtn.Text = "—"
minBtn.TextColor3 = Color3.fromRGB(230, 230, 240)
minBtn.Font = Enum.Font.GothamBold
minBtn.TextSize = 14
minBtn.Parent = header

local minc = Instance.new("UICorner")
minc.CornerRadius = UDim.new(0, 6)
minc.Parent = minBtn

local titleLbl = Instance.new("TextLabel")
titleLbl.Size = UDim2.new(1, -60, 1, 0)
titleLbl.Position = UDim2.new(0, 30, 0, 0)
titleLbl.BackgroundTransparency = 1
titleLbl.Text = "🌾 Harvest + Weld"
titleLbl.TextColor3 = Color3.fromRGB(230, 230, 240)
titleLbl.TextXAlignment = Enum.TextXAlignment.Left
titleLbl.Font = Enum.Font.GothamBold
titleLbl.TextSize = 12
titleLbl.Parent = header

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 22, 0, 22)
closeBtn.Position = UDim2.new(1, -26, 0, 3)
closeBtn.BackgroundTransparency = 1
closeBtn.Text = "✕"
closeBtn.TextColor3 = Color3.fromRGB(255, 100, 100)
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 13
closeBtn.Parent = header

closeBtn.MouseButton1Click:Connect(function()
    shutdown("GUI ditutup")
    if gui then gui:Destroy() end
end)

-- ===== BODY =====
local body = Instance.new("Frame")
body.Name = "Body"
body.Size = UDim2.new(1, 0, 1, -28)
body.Position = UDim2.new(0, 0, 0, 28)
body.BackgroundTransparency = 1
body.Parent = main

-- ===== PRESET BUTTONS (80 / 100) =====
local presetValues = { 80, 100 }
local presetBtns = {}

local presetRow = Instance.new("Frame")
presetRow.Size = UDim2.new(1, -20, 0, 36)
presetRow.Position = UDim2.new(0, 10, 0, 10)
presetRow.BackgroundTransparency = 1
presetRow.Parent = body

for i, val in ipairs(presetValues) do
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0.5, -4, 1, 0)
    btn.Position = UDim2.new((i - 1) * 0.5, (i == 1 and 0 or 4), 0, 0)
    btn.BackgroundColor3 = Color3.fromRGB(50, 50, 65)
    btn.Text = val .. " kg"
    btn.TextColor3 = Color3.fromRGB(220, 220, 230)
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 13
    btn.Parent = presetRow

    local bc = Instance.new("UICorner")
    bc.CornerRadius = UDim.new(0, 6)
    bc.Parent = btn

    presetBtns[val] = btn

    btn.MouseButton1Click:Connect(function()
        CONFIG.MAX_WEIGHT = val
        for v, b in pairs(presetBtns) do
            if v == val then
                b.BackgroundColor3 = Color3.fromRGB(40, 130, 70)
                b.TextColor3 = Color3.fromRGB(255, 255, 255)
            else
                b.BackgroundColor3 = Color3.fromRGB(50, 50, 65)
                b.TextColor3 = Color3.fromRGB(220, 220, 230)
            end
        end
    end)
end

presetBtns[CONFIG.MAX_WEIGHT].BackgroundColor3 = Color3.fromRGB(40, 130, 70)
presetBtns[CONFIG.MAX_WEIGHT].TextColor3 = Color3.fromRGB(255, 255, 255)

-- ===== AUTO TOGGLE =====
local autoBtn = Instance.new("TextButton")
autoBtn.Size = UDim2.new(1, -20, 0, 40)
autoBtn.Position = UDim2.new(0, 10, 0, 54)
autoBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 75)
autoBtn.Text = "🤖 AUTO: OFF"
autoBtn.TextColor3 = Color3.fromRGB(230, 230, 240)
autoBtn.Font = Enum.Font.GothamBold
autoBtn.TextSize = 14
autoBtn.Parent = body

local ac = Instance.new("UICorner")
ac.CornerRadius = UDim.new(0, 8)
ac.Parent = autoBtn

autoBtn.MouseButton1Click:Connect(function()
    CONFIG.AUTO_ENABLED = not CONFIG.AUTO_ENABLED
    if CONFIG.AUTO_ENABLED then
        autoBtn.Text = "🤖 AUTO: ON"
        autoBtn.BackgroundColor3 = Color3.fromRGB(40, 130, 70)
    else
        autoBtn.Text = "🤖 AUTO: OFF"
        autoBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 75)
    end
end)

-- ===== AUTO-SELL TOGGLE =====
local sellToggle = Instance.new("TextButton")
sellToggle.Size = UDim2.new(1, -20, 0, 32)
sellToggle.Position = UDim2.new(0, 10, 0, 102)
sellToggle.BackgroundColor3 = Color3.fromRGB(60, 60, 75)
sellToggle.Text = "💰 Auto-Sell: OFF"
sellToggle.TextColor3 = Color3.fromRGB(230, 230, 240)
sellToggle.Font = Enum.Font.GothamBold
sellToggle.TextSize = 13
sellToggle.Parent = body

local stc = Instance.new("UICorner")
stc.CornerRadius = UDim.new(0, 6)
stc.Parent = sellToggle

sellToggle.MouseButton1Click:Connect(function()
    CONFIG.AUTO_SELL_ENABLED = not CONFIG.AUTO_SELL_ENABLED
    if CONFIG.AUTO_SELL_ENABLED then
        sellToggle.Text = "💰 Auto-Sell: ON"
        sellToggle.BackgroundColor3 = Color3.fromRGB(40, 130, 70)
    else
        sellToggle.Text = "💰 Auto-Sell: OFF"
        sellToggle.BackgroundColor3 = Color3.fromRGB(60, 60, 75)
    end
end)

-- ===== SLIDER AUTO-SELL INTERVAL =====
local sellSliderFrame = Instance.new("Frame")
sellSliderFrame.Size = UDim2.new(1, -20, 0, 22)
sellSliderFrame.Position = UDim2.new(0, 10, 0, 140)
sellSliderFrame.BackgroundTransparency = 1
sellSliderFrame.Parent = body

local sellSliderBg = Instance.new("Frame")
sellSliderBg.Size = UDim2.new(1, -44, 0, 8)
sellSliderBg.Position = UDim2.new(0, 0, 0, 7)
sellSliderBg.BackgroundColor3 = Color3.fromRGB(45, 45, 58)
sellSliderBg.BorderSizePixel = 0
sellSliderBg.Parent = sellSliderFrame

local ssbc = Instance.new("UICorner")
ssbc.CornerRadius = UDim.new(0, 4)
ssbc.Parent = sellSliderBg

local sellSliderFill = Instance.new("Frame")
sellSliderFill.Size = UDim2.new(0.4, 0, 1, 0)
sellSliderFill.BackgroundColor3 = Color3.fromRGB(40, 130, 70)
sellSliderFill.BorderSizePixel = 0
sellSliderFill.Parent = sellSliderBg

local ssfc = Instance.new("UICorner")
ssfc.CornerRadius = UDim.new(0, 4)
ssfc.Parent = sellSliderFill

local sellSliderKnob = Instance.new("Frame")
sellSliderKnob.Size = UDim2.new(0, 16, 0, 16)
sellSliderKnob.Position = UDim2.new(0.4, -8, 0, 3)
sellSliderKnob.BackgroundColor3 = Color3.fromRGB(230, 230, 240)
sellSliderKnob.BorderSizePixel = 0
sellSliderKnob.Parent = sellSliderFrame

local sskc = Instance.new("UICorner")
sskc.CornerRadius = UDim.new(0, 8)
sskc.Parent = sellSliderKnob

local sellSliderLabel = Instance.new("TextLabel")
sellSliderLabel.Size = UDim2.new(0, 40, 1, 0)
sellSliderLabel.Position = UDim2.new(1, -40, 0, 0)
sellSliderLabel.BackgroundTransparency = 1
sellSliderLabel.Text = CONFIG.AUTO_SELL_INTERVAL .. "s"
sellSliderLabel.TextColor3 = Color3.fromRGB(180, 200, 255)
sellSliderLabel.Font = Enum.Font.Code
sellSliderLabel.TextSize = 11
sellSliderLabel.TextXAlignment = Enum.TextXAlignment.Right
sellSliderLabel.Parent = sellSliderFrame

local SELL_SLIDER_MIN = 1
local SELL_SLIDER_MAX = 10
local sellSliderDragging = false

local function updateSellSliderFromX(x)
    local relX = math.clamp(x, 0, sellSliderBg.AbsoluteSize.X)
    local pct = relX / sellSliderBg.AbsoluteSize.X
    local val = math.floor(SELL_SLIDER_MIN + pct * (SELL_SLIDER_MAX - SELL_SLIDER_MIN) + 0.5)
    val = math.clamp(val, SELL_SLIDER_MIN, SELL_SLIDER_MAX)
    CONFIG.AUTO_SELL_INTERVAL = val

    local newPct = (val - SELL_SLIDER_MIN) / (SELL_SLIDER_MAX - SELL_SLIDER_MIN)
    sellSliderFill.Size = UDim2.new(newPct, 0, 1, 0)
    sellSliderKnob.Position = UDim2.new(newPct, -8, 0, 3)
    sellSliderLabel.Text = val .. "s"
end

sellSliderKnob.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
       or input.UserInputType == Enum.UserInputType.Touch then
        sellSliderDragging = true
    end
end)

sellSliderKnob.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
       or input.UserInputType == Enum.UserInputType.Touch then
        sellSliderDragging = false
    end
end)

sellSliderBg.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
       or input.UserInputType == Enum.UserInputType.Touch then
        local relX = input.Position.X - sellSliderBg.AbsolutePosition.X
        updateSellSliderFromX(relX)
    end
end)

-- ===== WELD SLIDER TOGGLE (Weld + Anti-Sit + Anti-AFK) =====
local weldRow = Instance.new("Frame")
weldRow.Size = UDim2.new(1, -20, 0, 40)
weldRow.Position = UDim2.new(0, 10, 0, 172)
weldRow.BackgroundTransparency = 1
weldRow.Parent = body

local weldLabel = Instance.new("TextLabel")
weldLabel.Size = UDim2.new(1, 0, 0, 14)
weldLabel.Position = UDim2.new(0, 0, 0, 0)
weldLabel.BackgroundTransparency = 1
weldLabel.Text = "🔒 Weld + Anti-Sit + Anti-AFK"
weldLabel.TextColor3 = Color3.fromRGB(200, 200, 220)
weldLabel.Font = Enum.Font.GothamBold
weldLabel.TextSize = 11
weldLabel.TextXAlignment = Enum.TextXAlignment.Left
weldLabel.Parent = weldRow

-- Track slider weld
local WELD_SLIDER_W = 60
local WELD_KNOB_W   = 18
local WELD_RANGE    = WELD_SLIDER_W - WELD_KNOB_W

local weldTrack = Instance.new("Frame")
weldTrack.Size = UDim2.new(0, WELD_SLIDER_W, 0, 18)
weldTrack.Position = UDim2.new(0, 0, 0, 18)
weldTrack.BackgroundColor3 = Color3.fromRGB(50, 50, 62)
weldTrack.BorderSizePixel = 0
weldTrack.Parent = weldRow

local wtc = Instance.new("UICorner")
wtc.CornerRadius = UDim.new(0, 9)
wtc.Parent = weldTrack

local weldKnob = Instance.new("Frame")
weldKnob.Size = UDim2.new(0, WELD_KNOB_W, 0, 18)
weldKnob.Position = UDim2.new(0, 0, 0, 0)
weldKnob.BackgroundColor3 = Color3.fromRGB(230, 230, 240)
weldKnob.BorderSizePixel = 0
weldKnob.Parent = weldTrack

local wkc = Instance.new("UICorner")
wkc.CornerRadius = UDim.new(0, 9)
wkc.Parent = weldKnob

local weldStateLbl = Instance.new("TextLabel")
weldStateLbl.Size = UDim2.new(1, -WELD_SLIDER_W - 8, 1, 0)
weldStateLbl.Position = UDim2.new(0, WELD_SLIDER_W + 8, 0, 0)
weldStateLbl.BackgroundTransparency = 1
weldStateLbl.Text = "OFF"
weldStateLbl.TextColor3 = Color3.fromRGB(180, 180, 200)
weldStateLbl.Font = Enum.Font.GothamBold
weldStateLbl.TextSize = 12
weldStateLbl.TextXAlignment = Enum.TextXAlignment.Left
weldStateLbl.Parent = weldRow

local function updateWeldVisual(on)
    if on then
        weldKnob.Position = UDim2.new(0, WELD_RANGE, 0, 0)
        weldTrack.BackgroundColor3 = Color3.fromRGB(40, 130, 70)
        weldStateLbl.Text = "ON"
        weldStateLbl.TextColor3 = Color3.fromRGB(150, 255, 150)
    else
        weldKnob.Position = UDim2.new(0, 0, 0, 0)
        weldTrack.BackgroundColor3 = Color3.fromRGB(50, 50, 62)
        weldStateLbl.Text = "OFF"
        weldStateLbl.TextColor3 = Color3.fromRGB(180, 180, 200)
    end
end

local function toggleWeldAll()
    if not ALIVE then return end

    if CONFIG.WELD_ENABLED then
        -- OFF
        if isWeldOn then
            pcall(unweldCharacter)
        end
        isWeldOn = false
        CONFIG.WELD_ENABLED = false
        updateWeldVisual(false)
        print("🔓 Weld + Anti-Sit + Anti-AFK OFF")
    else
        -- ON
        if weldCharacter() then
            isWeldOn = true
            CONFIG.WELD_ENABLED = true
            updateWeldVisual(true)
            print("🔒 Weld + Anti-Sit + Anti-AFK ON")
        else
            warn("❌ Gagal weld (karakter belum spawn?)")
        end
    end
end

-- Klik track = toggle
weldTrack.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
       or input.UserInputType == Enum.UserInputType.Touch then
        toggleWeldAll()
    end
end)

-- Drag knob
local weldDragging = false

weldKnob.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
       or input.UserInputType == Enum.UserInputType.Touch then
        weldDragging = true
    end
end)

-- ===== GLOBAL INPUT HANDLERS =====
UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
       or input.UserInputType == Enum.UserInputType.Touch then
        sellSliderDragging = false
        weldDragging = false
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if not ALIVE then return end

    if input.UserInputType == Enum.UserInputType.MouseMovement
       or input.UserInputType == Enum.UserInputType.Touch then

        -- sell slider
        if sellSliderDragging then
            local relX = input.Position.X - sellSliderBg.AbsolutePosition.X
            updateSellSliderFromX(relX)
        end

        -- weld slider
        if weldDragging then
            local trackX = weldTrack.AbsolutePosition.X
            local relX = input.Position.X - trackX
            local pct = math.clamp((relX - WELD_KNOB_W/2) / WELD_RANGE, 0, 1)
            local newOn = pct > 0.5
            if newOn ~= CONFIG.WELD_ENABLED then
                toggleWeldAll()
            end
        end
    end
end)

-- Init sell slider
task.defer(function()
    updateSellSliderFromX(sellSliderBg.AbsoluteSize.X * 0.4)
end)

updateWeldVisual(false)

-- ===== MINIMIZE LOGIC =====
local isMinimized = false

minBtn.MouseButton1Click:Connect(function()
    isMinimized = not isMinimized

    if isMinimized then
        body.Visible = false
        main.Size = UDim2.new(0, 200, 0, MINI_HEIGHT)
        minBtn.Text = "+"
    else
        body.Visible = true
        main.Size = UDim2.new(0, 200, 0, FULL_HEIGHT)
        minBtn.Text = "—"
    end
end)

-- ============ SCAN (HANYA PLOT SENDIRI) ============

local function getAllFruits()
    local out = {}

    local plot = getMyPlot()
    if not plot then return out end

    local plants = plot:FindFirstChild("Plants")
    if not plants then return out end

    for _, plant in ipairs(plants:GetChildren()) do
        local skip = false
        if CONFIG.ONLY_MY_PLOTS then
            if getOwnerId(plant) ~= LocalPlayer.UserId then
                skip = true
            end
        end

        if not skip then
            local fruits = plant:FindFirstChild("Fruits")
            if fruits then
                for _, fruit in ipairs(fruits:GetChildren()) do
                    table.insert(out, {
                        fruit    = fruit,
                        plant    = plant,
                        weight   = getFruitWeight(fruit),
                        mutation = getMutation(fruit),
                    })
                end
            end
        end
    end
    return out
end

-- ============ AUTO HARVEST LOOP ============

task.spawn(function()
    while ALIVE do
        task.wait(CONFIG.AUTO_DELAY)
        if not ALIVE then break end

        if CONFIG.AUTO_ENABLED then
            if getMyPlot() then
                local entries = getAllFruits()

                for _, e in ipairs(entries) do
                    if not ALIVE then break end

                    local shouldHarvest = false

                    -- PRIORITAS: mutasi tertentu → langsung panen
                    if e.mutation and PRIORITY_MUTATIONS[e.mutation] then
                        shouldHarvest = true
                    end

                    -- Normal: cek berat
                    if not shouldHarvest and e.weight and e.weight <= CONFIG.MAX_WEIGHT then
                        shouldHarvest = true
                    end

                    if shouldHarvest then
                        harvest(e.plant, e.fruit)
                        task.wait(0.08)
                    end
                end
            end
        end
    end
    print("🛑 Harvest loop berhenti")
end)

-- ============ AUTO SELL LOOP ============

task.spawn(function()
    while ALIVE do
        task.wait(CONFIG.AUTO_SELL_INTERVAL)
        if not ALIVE then break end

        if CONFIG.AUTO_SELL_ENABLED then
            sellBackpack()
        end
    end
    print("🛑 Sell loop berhenti")
end)

-- ============ START ANTI-AFK ============
startAntiAfk()

-- ============ CLEANUP ============

gui.Destroying:Connect(function()
    shutdown("GUI Destroying event")
end)

Players.PlayerRemoving:Connect(function(p)
    if p == LocalPlayer then
        shutdown("Player keluar game")
    end
end)

LocalPlayer.CharacterAdded:Connect(function()
    if isWeldOn then
        isWeldOn = false
        CONFIG.WELD_ENABLED = false
        updateWeldVisual(false)
    end
end)

-- ============ INIT LOG ============

if MY_PLOT_NAME then
    print("✅ Harvest + Weld loaded. Plot:", MY_PLOT_NAME)
else
    warn("⚠️ Plot belum terdeteksi. Akan dicoba lagi saat AUTO ON.")
end
