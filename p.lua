-- ============================================
-- AUTO HARVEST + AUTO-SELL (FINAL)
-- Payload Harvest: )\001$uuid[flag][index]
-- Payload Sell: \015\001\018
-- Rumus: weight = SizeMulti × 9
-- Preset: 80 / 100 kg
-- Mutasi murah (Gold/Frozen/Lightning) = panen langsung
-- Plot terdeteksi via nickname di Signs
-- Guard: semua loop mati saat GUI ditutup
-- ============================================

local CoreGui           = game:GetService("CoreGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")
local UserInputService  = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer

local Packet = ReplicatedStorage:WaitForChild("SharedModules")
    :WaitForChild("Packet"):WaitForChild("RemoteEvent")

local ROOT = workspace:WaitForChild("Gardens")

-- ============ CONFIG ============

local CONFIG = {
    MAX_WEIGHT = 80,
    AUTO_ENABLED = false,
    AUTO_SELL_ENABLED = false,
    AUTO_SELL_INTERVAL = 5,
    AUTO_DELAY = 0.25,
    ONLY_MY_PLOTS = true,
}

local WEIGHT_K = 9

local CHEAP_MUTATIONS = {
    Gold = true,
    Frozen = true,
    Lightning = true,
}

local SELL_PAYLOAD = "\015\001\018"

-- ============ GUARD ============

local ALIVE = true

local function shutdown(reason)
    if not ALIVE then return end
    ALIVE = false
    CONFIG.AUTO_ENABLED = false
    CONFIG.AUTO_SELL_ENABLED = false
    if reason then
        print("🛑 Script dimatikan:", reason)
    end
end

-- ============ PLOT DETECTION ============

local MY_PLOT_NAME = nil

local function detectMyPlot()
    local mySign = LocalPlayer.DisplayName .. "'s Garden"

    for _, plot in ipairs(ROOT:GetChildren()) do
        local signs = plot:FindFirstChild("Signs")
        if signs then
            local garden = signs:FindFirstChild("Garden")
            local core = garden and garden:FindFirstChild("CorePart")
            local sg = core and core:FindFirstChild("SurfaceGui")
            local playerLbl = sg and sg:FindFirstChild("Player")
            local textLbl = playerLbl and playerLbl:FindFirstChild("TextLabel")

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
    local uuid = getPlantUuid(plant)
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

-- ============ GUI ============

local old = CoreGui:FindFirstChild("AutoHarvestMini")
if old then old:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "AutoHarvestMini"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = CoreGui

-- Layout constants
local FULL_HEIGHT   = 200
local MINI_HEIGHT   = 28

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

-- Tutup bagian bawah header (biar cuma atas yang rounded)
local headerFix = Instance.new("Frame")
headerFix.Size = UDim2.new(1, 0, 0, 10)
headerFix.Position = UDim2.new(0, 0, 1, -10)
headerFix.BackgroundColor3 = Color3.fromRGB(40, 40, 52)
headerFix.BorderSizePixel = 0
headerFix.Parent = header

-- Minimize button (kiri)
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

-- Title (tengah)
local titleLbl = Instance.new("TextLabel")
titleLbl.Size = UDim2.new(1, -60, 1, 0)
titleLbl.Position = UDim2.new(0, 30, 0, 0)
titleLbl.BackgroundTransparency = 1
titleLbl.Text = "🌾 Auto Harvest"
titleLbl.TextColor3 = Color3.fromRGB(230, 230, 240)
titleLbl.TextXAlignment = Enum.TextXAlignment.Left
titleLbl.Font = Enum.Font.GothamBold
titleLbl.TextSize = 12
titleLbl.Parent = header

-- Close button (kanan)
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

-- ===== BODY (semua kontrol di bawah header) =====
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

-- ===== SLIDER (auto-sell interval) =====
local sliderFrame = Instance.new("Frame")
sliderFrame.Size = UDim2.new(1, -20, 0, 22)
sliderFrame.Position = UDim2.new(0, 10, 0, 140)
sliderFrame.BackgroundTransparency = 1
sliderFrame.Parent = body

local sliderBg = Instance.new("Frame")
sliderBg.Size = UDim2.new(1, -44, 0, 8)
sliderBg.Position = UDim2.new(0, 0, 0, 7)
sliderBg.BackgroundColor3 = Color3.fromRGB(45, 45, 58)
sliderBg.BorderSizePixel = 0
sliderBg.Parent = sliderFrame

local sliderBgCorner = Instance.new("UICorner")
sliderBgCorner.CornerRadius = UDim.new(0, 4)
sliderBgCorner.Parent = sliderBg

local sliderFill = Instance.new("Frame")
sliderFill.Size = UDim2.new(0.4, 0, 1, 0)
sliderFill.BackgroundColor3 = Color3.fromRGB(40, 130, 70)
sliderFill.BorderSizePixel = 0
sliderFill.Parent = sliderBg

local sliderFillCorner = Instance.new("UICorner")
sliderFillCorner.CornerRadius = UDim.new(0, 4)
sliderFillCorner.Parent = sliderFill

local sliderKnob = Instance.new("Frame")
sliderKnob.Size = UDim2.new(0, 16, 0, 16)
sliderKnob.Position = UDim2.new(0.4, -8, 0, 3)
sliderKnob.BackgroundColor3 = Color3.fromRGB(230, 230, 240)
sliderKnob.BorderSizePixel = 0
sliderKnob.Parent = sliderFrame

local sliderKnobCorner = Instance.new("UICorner")
sliderKnobCorner.CornerRadius = UDim.new(0, 8)
sliderKnobCorner.Parent = sliderKnob

local sliderLabel = Instance.new("TextLabel")
sliderLabel.Size = UDim2.new(0, 40, 1, 0)
sliderLabel.Position = UDim2.new(1, -40, 0, 0)
sliderLabel.BackgroundTransparency = 1
sliderLabel.Text = CONFIG.AUTO_SELL_INTERVAL .. "s"
sliderLabel.TextColor3 = Color3.fromRGB(180, 200, 255)
sliderLabel.Font = Enum.Font.Code
sliderLabel.TextSize = 11
sliderLabel.TextXAlignment = Enum.TextXAlignment.Right
sliderLabel.Parent = sliderFrame

local SLIDER_MIN = 1
local SLIDER_MAX = 10
local sliderDragging = false

local function updateSliderFromX(x)
    local relX = math.clamp(x, 0, sliderBg.AbsoluteSize.X)
    local pct = relX / sliderBg.AbsoluteSize.X
    local val = math.floor(SLIDER_MIN + pct * (SLIDER_MAX - SLIDER_MIN) + 0.5)
    val = math.clamp(val, SLIDER_MIN, SLIDER_MAX)
    CONFIG.AUTO_SELL_INTERVAL = val

    local newPct = (val - SLIDER_MIN) / (SLIDER_MAX - SLIDER_MIN)
    sliderFill.Size = UDim2.new(newPct, 0, 1, 0)
    sliderKnob.Position = UDim2.new(newPct, -8, 0, 3)
    sliderLabel.Text = val .. "s"
end

sliderKnob.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
       or input.UserInputType == Enum.UserInputType.Touch then
        sliderDragging = true
    end
end)

sliderKnob.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
       or input.UserInputType == Enum.UserInputType.Touch then
        sliderDragging = false
    end
end)

sliderBg.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
       or input.UserInputType == Enum.UserInputType.Touch then
        local relX = input.Position.X - sliderBg.AbsolutePosition.X
        updateSliderFromX(relX)
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if not ALIVE then return end
    if sliderDragging then
        if input.UserInputType == Enum.UserInputType.MouseMovement
           or input.UserInputType == Enum.UserInputType.Touch then
            local relX = input.Position.X - sliderBg.AbsolutePosition.X
            updateSliderFromX(relX)
        end
    end
end)

updateSliderFromX(sliderBg.AbsoluteSize.X * 0.4)

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
                        fruit = fruit,
                        plant = plant,
                        weight = getFruitWeight(fruit),
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

                    if e.mutation and CHEAP_MUTATIONS[e.mutation] then
                        shouldHarvest = true
                    end

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

-- ============ CLEANUP HANDLER ============

gui.Destroying:Connect(function()
    shutdown("GUI Destroying event")
end)

Players.PlayerRemoving:Connect(function(p)
    if p == LocalPlayer then
        shutdown("Player keluar game")
    end
end)

-- ============ INIT LOG ============

if MY_PLOT_NAME then
    print("✅ Auto Harvest loaded. Plot:", MY_PLOT_NAME)
else
    warn("⚠️ Plot belum terdeteksi. Akan dicoba lagi saat AUTO ON.")
end
