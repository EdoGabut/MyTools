-- ============================================
-- AUTO HARVEST + PRIORITY FARM + WELD
-- + AUTO CLEAR saat favorite capai 50
-- Plot detection UNIVERSAL (semua player)
-- MAX_WEIGHT = 80
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
    MAX_WEIGHT          = 80,
    AUTO_ENABLED        = false,
    AUTO_SELL_ENABLED   = false,
    AUTO_SELL_INTERVAL  = 5,
    AUTO_DELAY          = 0.25,
    ONLY_MY_PLOTS       = true,
    WELD_ENABLED        = false,
    PRIORITY_RESUME_DELAY = 3,
    FAVORITE_CAP        = 10,
    CAP_CHECK_INTERVAL  = 5,
}

local WEIGHT_K = 9

local CHEAP_MUTATIONS = {
    Electric    = true,
    Gold        = true,
    Frozen      = true,
    Rainbow     = true,
    Starstruck  = true,
}

local SELL_PAYLOAD = "\015\001\018"
local FAV_PREFIX   = "\179\0004$"
local UNFAV_PREFIX = "\179\0006$"

-- ============ STATE ============

local ALIVE          = true
local isWeldOn       = false
local isPriorityBusy = false
local isClearing     = false

-- ============ PLOT DETECTION (UNIVERSAL) ============

local MY_PLOT_NAME = nil

local function isMyPlot(plot)
    local plants = plot:FindFirstChild("Plants")
    if plants then
        for _, plant in ipairs(plants:GetChildren()) do
            local ownerId = plant.Name:match("^(%d+)_")
            if ownerId and tonumber(ownerId) == LocalPlayer.UserId then
                return true
            end
        end
    end

    local signs = plot:FindFirstChild("Signs")
    if signs then
        local garden = signs:FindFirstChild("Garden")
        local core   = garden and garden:FindFirstChild("CorePart")
        local sg     = core and core:FindFirstChild("SurfaceGui")
        local playerLbl = sg and sg:FindFirstChild("Player")
        local textLbl   = playerLbl and playerLbl:FindFirstChild("TextLabel")

        if textLbl then
            local txt = textLbl.Text
            if txt:find(LocalPlayer.DisplayName, 1, true) 
               or txt:find(LocalPlayer.Name, 1, true) then
                return true
            end
        end
    end

    return false
end

local function detectMyPlot()
    for _, plot in ipairs(ROOT:GetChildren()) do
        if isMyPlot(plot) then
            MY_PLOT_NAME = plot.Name
            print("✅ Plot terdeteksi:", MY_PLOT_NAME)
            return MY_PLOT_NAME
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

local function isCheapMutation(mutation)
    if not mutation then return false end
    return CHEAP_MUTATIONS[mutation] == true
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

local function favoriteFruit(uuid)
    if not ALIVE or not uuid then return false end
    local payload = FAV_PREFIX .. uuid .. "\001"
    local ok = pcall(function()
        Packet:FireServer(buffer.fromstring(payload))
    end)
    return ok
end

local function unfavoriteFruit(uuid)
    if not ALIVE or not uuid then return false end
    local payload = UNFAV_PREFIX .. uuid .. "\000"
    local ok = pcall(function()
        Packet:FireServer(buffer.fromstring(payload))
    end)
    return ok
end

-- ============ BACKPACK UUID ============

local function getBackpackUUIDs()
    local uuids = {}
    local backpack = LocalPlayer:FindFirstChild("Backpack")
    if not backpack then return uuids end

    for _, item in ipairs(backpack:GetChildren()) do
        local id = item:GetAttribute("Id")
        if id then
            uuids[id] = item
        end
    end
    return uuids
end

local function getNewBackpackTools(beforeUUIDs)
    local newTools = {}
    local backpack = LocalPlayer:FindFirstChild("Backpack")
    if not backpack then return newTools end

    for _, item in ipairs(backpack:GetChildren()) do
        local id = item:GetAttribute("Id")
        if id and not beforeUUIDs[id] then
            table.insert(newTools, {
                tool = item,
                uuid = id,
                name = item.Name,
                weight = item:GetAttribute("Weight"),
                mutation = item:GetAttribute("Mutation"),
            })
        end
    end
    return newTools
end

local function countFavorites()
    local count = 0
    local backpack = LocalPlayer:FindFirstChild("Backpack")
    if not backpack then return 0 end

    for _, item in ipairs(backpack:GetChildren()) do
        local uuid = item:GetAttribute("Id")
        local isFav = item:GetAttribute("IsFavorite")
        if uuid and isFav == true then
            count = count + 1
        end
    end
    return count
end

-- ============ LOGIKA FILTER ============

local function isNormalHarvest(e)
    if not e.weight then return false end
    if e.weight <= CONFIG.MAX_WEIGHT then return true end
    if e.mutation and isCheapMutation(e.mutation) then return true end
    return false
end

local function isPriorityTarget(e)
    if not e.weight then return false end
    if e.weight <= CONFIG.MAX_WEIGHT then return false end
    if not e.mutation then return false end
    if isCheapMutation(e.mutation) then return false end
    return true
end

-- ============ WELD ============

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

    return true
end

local function unweldCharacter()
    local char = LocalPlayer.Character
    if not char then return false end

    local humanoid = char:FindFirstChildOfClass("Humanoid")

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

-- ============ SHUTDOWN ============

local function shutdown(reason)
    if not ALIVE then return end
    ALIVE = false
    CONFIG.AUTO_ENABLED = false
    CONFIG.AUTO_SELL_ENABLED = false
    CONFIG.WELD_ENABLED = false

    if isWeldOn then
        pcall(unweldCharacter)
        isWeldOn = false
    end

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

local FULL_HEIGHT = 290
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

-- Header
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
titleLbl.Text = "🌾 Harvest + Priority"
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

local body = Instance.new("Frame")
body.Name = "Body"
body.Size = UDim2.new(1, 0, 1, -28)
body.Position = UDim2.new(0, 0, 0, 28)
body.BackgroundTransparency = 1
body.Parent = main

-- Preset
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

-- AUTO PANEN
local autoBtn = Instance.new("TextButton")
autoBtn.Size = UDim2.new(1, -20, 0, 40)
autoBtn.Position = UDim2.new(0, 10, 0, 54)
autoBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 75)
autoBtn.Text = "🌾 AUTO PANEN: OFF"
autoBtn.TextColor3 = Color3.fromRGB(230, 230, 240)
autoBtn.Font = Enum.Font.GothamBold
autoBtn.TextSize = 13
autoBtn.Parent = body

local ac = Instance.new("UICorner")
ac.CornerRadius = UDim.new(0, 8)
ac.Parent = autoBtn

autoBtn.MouseButton1Click:Connect(function()
    CONFIG.AUTO_ENABLED = not CONFIG.AUTO_ENABLED
    if CONFIG.AUTO_ENABLED then
        autoBtn.Text = "🌾 AUTO PANEN: ON"
        autoBtn.BackgroundColor3 = Color3.fromRGB(40, 130, 70)
        print("🌾 AUTO PANEN ON")
        if not MY_PLOT_NAME then
            detectMyPlot()
        end
    else
        autoBtn.Text = "🌾 AUTO PANEN: OFF"
        autoBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 75)
        print("🌾 AUTO PANEN OFF")
    end
end)

-- AUTO SELL
local sellToggle = Instance.new("TextButton")
sellToggle.Size = UDim2.new(1, -20, 0, 32)
sellToggle.Position = UDim2.new(0, 10, 0, 102)
sellToggle.BackgroundColor3 = Color3.fromRGB(60, 60, 75)
sellToggle.Text = "💰 AUTO SELL: OFF"
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
        sellToggle.Text = "💰 AUTO SELL: ON"
        sellToggle.BackgroundColor3 = Color3.fromRGB(40, 130, 70)
        print("💰 AUTO SELL ON")
    else
        sellToggle.Text = "💰 AUTO SELL: OFF"
        sellToggle.BackgroundColor3 = Color3.fromRGB(60, 60, 75)
        print("💰 AUTO SELL OFF")
    end
end)

-- Sell slider
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

-- Unfav All
local unfavAllBtn = Instance.new("TextButton")
unfavAllBtn.Size = UDim2.new(1, -20, 0, 32)
unfavAllBtn.Position = UDim2.new(0, 10, 0, 168)
unfavAllBtn.BackgroundColor3 = Color3.fromRGB(150, 60, 60)
unfavAllBtn.Text = "🧹 UNFAV ALL (kategori)"
unfavAllBtn.TextColor3 = Color3.fromRGB(255, 240, 240)
unfavAllBtn.Font = Enum.Font.GothamBold
unfavAllBtn.TextSize = 11
unfavAllBtn.Parent = body

local ubc = Instance.new("UICorner")
ubc.CornerRadius = UDim.new(0, 6)
ubc.Parent = unfavAllBtn

-- Weld
local weldRow = Instance.new("Frame")
weldRow.Size = UDim2.new(1, -20, 0, 40)
weldRow.Position = UDim2.new(0, 10, 0, 208)
weldRow.BackgroundTransparency = 1
weldRow.Parent = body

local weldLabel = Instance.new("TextLabel")
weldLabel.Size = UDim2.new(1, 0, 0, 14)
weldLabel.Position = UDim2.new(0, 0, 0, 0)
weldLabel.BackgroundTransparency = 1
weldLabel.Text = "🔒 Weld"
weldLabel.TextColor3 = Color3.fromRGB(200, 200, 220)
weldLabel.Font = Enum.Font.GothamBold
weldLabel.TextSize = 11
weldLabel.TextXAlignment = Enum.TextXAlignment.Left
weldLabel.Parent = weldRow

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
        if isWeldOn then pcall(unweldCharacter) end
        isWeldOn = false
        CONFIG.WELD_ENABLED = false
        updateWeldVisual(false)
        print("🔓 Weld OFF")
    else
        if weldCharacter() then
            isWeldOn = true
            CONFIG.WELD_ENABLED = true
            updateWeldVisual(true)
            print("🔒 Weld ON")
        else
            warn("❌ Gagal weld")
        end
    end
end

weldTrack.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
       or input.UserInputType == Enum.UserInputType.Touch then
        toggleWeldAll()
    end
end)

local weldDragging = false

weldKnob.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
       or input.UserInputType == Enum.UserInputType.Touch then
        weldDragging = true
    end
end)

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

        if sellSliderDragging then
            local relX = input.Position.X - sellSliderBg.AbsolutePosition.X
            updateSellSliderFromX(relX)
        end

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

task.defer(function()
    updateSellSliderFromX(sellSliderBg.AbsoluteSize.X * 0.4)
end)

updateWeldVisual(false)

-- Minimize
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

-- ============ SCAN ============

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

-- ============ PRIORITY FARM ============

local function doPriorityFarm()
    if isPriorityBusy or isClearing then return end
    isPriorityBusy = true

    print("")
    print("🌟 ═══ PRIORITY FARM ═══")

    local prevSell = CONFIG.AUTO_SELL_ENABLED

    CONFIG.AUTO_SELL_ENABLED = false
    if sellToggle then
        sellToggle.Text = "💰 AUTO SELL: OFF"
        sellToggle.BackgroundColor3 = Color3.fromRGB(60, 60, 75)
    end

    task.wait(0.3)

    local totalHarvested = 0
    local totalFavorited = 0
    local round = 0

    while ALIVE and round < 10 do
        if isClearing then break end

        round = round + 1

        local entries = getAllFruits()
        local targets = {}

        for _, e in ipairs(entries) do
            if isPriorityTarget(e) then
                table.insert(targets, e)
            end
        end

        if #targets == 0 then
            print(string.format("🌟 Round %d: no target", round))
            break
        end

        print(string.format("🌟 Round %d: %d target", round, #targets))

        local beforeUUIDs = getBackpackUUIDs()

        for _, t in ipairs(targets) do
            if not ALIVE or isClearing then break end
            harvest(t.plant, t.fruit)
            totalHarvested = totalHarvested + 1
            task.wait(0.15)
        end

        task.wait(0.8)

        local newTools = getNewBackpackTools(beforeUUIDs)
        for _, t in ipairs(newTools) do
            if not ALIVE or isClearing then break end
            if favoriteFruit(t.uuid) then
                totalFavorited = totalFavorited + 1
                print(string.format("🌟 ⭐ %s [%s] %.2fkg",
                    t.name, t.mutation or "-", t.weight or 0))
            end            task.wait(0.15)
        end

        task.wait(0.3)
    end

    print(string.format("🌟 Total: %d harvested, %d favorited",
        totalHarvested, totalFavorited))

    if prevSell and not isClearing then
        CONFIG.AUTO_SELL_ENABLED = true
        if sellToggle then
            sellToggle.Text = "💰 AUTO SELL: ON"
            sellToggle.BackgroundColor3 = Color3.fromRGB(40, 130, 70)
        end
    end

    print("🌟 ═══════════════════════")
    print("")

    isPriorityBusy = false
end

-- ============ 🧹 AUTO CLEAR MODE ============

local function doClearMode()
    if isClearing then return end
    isClearing = true
    isPriorityBusy = true

    print("")
    print("🧹 ═══════════════════════════════════════")
    print("🧹 AUTO CLEAR MODE dimulai!")
    print("🧹 ═══════════════════════════════════════")

    local prevAuto = CONFIG.AUTO_ENABLED
    local prevSell = CONFIG.AUTO_SELL_ENABLED

    CONFIG.AUTO_ENABLED      = false
    CONFIG.AUTO_SELL_ENABLED = false

    if autoBtn then
        autoBtn.Text = "🌾 AUTO PANEN: OFF"
        autoBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 75)
    end
    if sellToggle then
        sellToggle.Text = "💰 AUTO SELL: OFF"
        sellToggle.BackgroundColor3 = Color3.fromRGB(60, 60, 75)
    end

    task.wait(0.5)

    print("🧹 Unfavorite semua buah...")
    local backpack = LocalPlayer:FindFirstChild("Backpack")
    local unfavedCount = 0
    local favedCount = 0

    if backpack then
        for _, item in ipairs(backpack:GetChildren()) do
            local uuid = item:GetAttribute("Id")
            local isFav = item:GetAttribute("IsFavorite")

            if uuid and isFav == true then
                favedCount = favedCount + 1
                local ok = unfavoriteFruit(uuid)
                if ok then
                    unfavedCount = unfavedCount + 1
                end
                task.wait(0.1)
            end
        end
    end

    print(string.format("🧹 Favorited: %d | Unfavorited: %d",
        favedCount, unfavedCount))

    task.wait(2)

    print("💰 Sell semua buah...")
    sellBackpack()
    task.wait(1)

    CONFIG.AUTO_ENABLED      = prevAuto
    CONFIG.AUTO_SELL_ENABLED = prevSell

    if prevAuto and autoBtn then
        autoBtn.Text = "🌾 AUTO PANEN: ON"
        autoBtn.BackgroundColor3 = Color3.fromRGB(40, 130, 70)
    end
    if prevSell and sellToggle then
        sellToggle.Text = "💰 AUTO SELL: ON"
        sellToggle.BackgroundColor3 = Color3.fromRGB(40, 130, 70)
    end

    print("🧹 ═══════════════════════════════════════")
    print("🧹 CLEAR MODE selesai!")
    print("🧹 ═══════════════════════════════════════")
    print("")

    isClearing = false
    isPriorityBusy = false
end

-- ============ AUTO HARVEST LOOP ============

task.spawn(function()
    while ALIVE do
        task.wait(CONFIG.AUTO_DELAY)
        if not ALIVE then break end
        if isPriorityBusy or isClearing then continue end

        if CONFIG.AUTO_ENABLED then
            if getMyPlot() then
                local entries = getAllFruits()

                local hasPriority = false
                for _, e in ipairs(entries) do
                    if isPriorityTarget(e) then
                        hasPriority = true
                        break
                    end
                end

                if hasPriority then
                    task.spawn(doPriorityFarm)
                else
                    for _, e in ipairs(entries) do
                        if not ALIVE or isPriorityBusy or isClearing then break end
                        if not CONFIG.AUTO_ENABLED then break end

                        if isNormalHarvest(e) then
                            harvest(e.plant, e.fruit)
                            task.wait(0.08)
                        end
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
        if isPriorityBusy or isClearing then continue end

        if CONFIG.AUTO_SELL_ENABLED then
            sellBackpack()
        end
    end
    print("🛑 Sell loop berhenti")
end)

-- ============ 🧹 FAVORITE CAP CHECK LOOP ============

task.spawn(function()
    while ALIVE do
        task.wait(CONFIG.CAP_CHECK_INTERVAL)
        if not ALIVE then break end
        if isClearing or isPriorityBusy then continue end

        local favCount = countFavorites()

        if favCount >= CONFIG.FAVORITE_CAP then
            print(string.format("🧹 Favorite cap reached: %d/%d",
                favCount, CONFIG.FAVORITE_CAP))
            task.spawn(doClearMode)
        end
    end
    print("🛑 Favorite check loop berhenti")
end)

-- ============ UNFAV ALL ============

unfavAllBtn.MouseButton1Click:Connect(function()
    unfavAllBtn.Text = "🧹 Working..."
    unfavAllBtn.BackgroundColor3 = Color3.fromRGB(200, 130, 40)

    print("")
    print("🧹 ═══ UNFAV ALL (kategori) ═══")

    local backpack = LocalPlayer:FindFirstChild("Backpack")
    local count = 0
    local total = 0

    if backpack then
        for _, item in ipairs(backpack:GetChildren()) do
            local uuid = item:GetAttribute("Id")
            local isFav = item:GetAttribute("IsFavorite")
            local w = item:GetAttribute("Weight")
            local mut = item:GetAttribute("Mutation")

            if uuid and isFav == true and w and mut then
                total = total + 1

                local isHigh = (w > CONFIG.MAX_WEIGHT) and not isCheapMutation(mut)

                if isHigh then
                    local ok = unfavoriteFruit(uuid)
                    if ok then
                        count = count + 1
                        print(string.format("  🧹 [%d] %.2fkg [%s]",
                            count, w, mut))
                    end
                    task.wait(0.15)
                end
            end
        end
    end

    print(string.format("🧹 Total %d difavorite, %d di-unfavorite",
        total, count))
    print("🧹 ═══════════════════════════")
    print("")

    if count > 0 then
        unfavAllBtn.Text = "✅ Unfav " .. count
        unfavAllBtn.BackgroundColor3 = Color3.fromRGB(40, 130, 70)
    else
        unfavAllBtn.Text = "ℹ️ Nggak ada"
        unfavAllBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 75)
    end

    task.delay(2, function()
        if unfavAllBtn and unfavAllBtn.Parent then
            unfavAllBtn.Text = "🧹 UNFAV ALL (kategori)"
            unfavAllBtn.BackgroundColor3 = Color3.fromRGB(150, 60, 60)
        end
    end)
end)

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
    print("✅ Harvest + Priority + Unfav All + Auto Clear loaded. Plot:", MY_PLOT_NAME)
    print("🎯 MAX_WEIGHT: " .. CONFIG.MAX_WEIGHT .. " kg")
    print("🧹 FAVORITE_CAP: " .. CONFIG.FAVORITE_CAP)
else
    warn("⚠️ Plot belum terdeteksi.")
end
