-- ============================================
-- AUTO HARVEST + PRIORITY FARM
-- Filter:
--   - ≤ 80 kg → panen + jual
--   - > 80 + mutasi cheap → panen + jual
--   - > 80 + mutasi mahal + ≤ 150 kg → panen + jual
--   - > 150 kg + mutasi mahal → panen + SAVE (favorite)
--   - > 80 tanpa mutasi → SKIP (nunggu mutasi)
-- ULTRA Minimalis
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
    SAVE_WEIGHT         = 150,
    AUTO_ENABLED        = false,
    AUTO_SELL_ENABLED   = false,
    AUTO_SELL_INTERVAL  = 3,
    AUTO_DELAY          = 0.25,
    ONLY_MY_PLOTS       = true,
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

-- ============ STATE ============

local ALIVE          = true
local isPriorityBusy = false

-- ============ PLOT DETECTION ============

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

local function isSaveTarget(e)
    if not e.weight then return false end
    if e.weight <= CONFIG.SAVE_WEIGHT then return false end
    if not e.mutation then return false end
    if isCheapMutation(e.mutation) then return false end
    return true
end

local function isSellTarget(e)
    if not e.weight then return false end
    if e.weight <= CONFIG.MAX_WEIGHT then return false end
    if e.weight > CONFIG.SAVE_WEIGHT then return false end
    if not e.mutation then return false end
    if isCheapMutation(e.mutation) then return false end
    return true
end

-- ============ SHUTDOWN ============

local function shutdown(reason)
    if not ALIVE then return end
    ALIVE = false
    CONFIG.AUTO_ENABLED = false
    CONFIG.AUTO_SELL_ENABLED = false

    if reason then
        print("🛑 Script dimatikan:", reason)
    end
end

-- ============ GUI (ULTRA MINIMALIS) ============

local old = CoreGui:FindFirstChild("AutoHarvestMini")
if old then old:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "AutoHarvestMini"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = CoreGui

local FULL_H  = 90
local MINI_H  = 28

local main = Instance.new("Frame")
main.Size = UDim2.new(0, 150, 0, FULL_H)
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

-- Minimize button
local minBtn = Instance.new("TextButton")
minBtn.Size = UDim2.new(0, 20, 0, 20)
minBtn.Position = UDim2.new(0, 4, 0, 4)
minBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 75)
minBtn.Text = "—"
minBtn.TextColor3 = Color3.fromRGB(230, 230, 240)
minBtn.Font = Enum.Font.GothamBold
minBtn.TextSize = 12
minBtn.Parent = header

local minc = Instance.new("UICorner")
minc.CornerRadius = UDim.new(0, 5)
minc.Parent = minBtn

-- Title
local titleLbl = Instance.new("TextLabel")
titleLbl.Size = UDim2.new(1, -50, 1, 0)
titleLbl.Position = UDim2.new(0, 26, 0, 0)
titleLbl.BackgroundTransparency = 1
titleLbl.Text = "🌾 Farm"
titleLbl.TextColor3 = Color3.fromRGB(230, 230, 240)
titleLbl.TextXAlignment = Enum.TextXAlignment.Left
titleLbl.Font = Enum.Font.GothamBold
titleLbl.TextSize = 11
titleLbl.Parent = header

-- Close button
local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 20, 0, 20)
closeBtn.Position = UDim2.new(1, -24, 0, 4)
closeBtn.BackgroundTransparency = 1
closeBtn.Text = "✕"
closeBtn.TextColor3 = Color3.fromRGB(255, 100, 100)
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 12
closeBtn.Parent = header

closeBtn.MouseButton1Click:Connect(function()
    shutdown("GUI ditutup")
    if gui then gui:Destroy() end
end)

-- Body
local body = Instance.new("Frame")
body.Name = "Body"
body.Size = UDim2.new(1, 0, 1, -28)
body.Position = UDim2.new(0, 0, 0, 28)
body.BackgroundTransparency = 1
body.Parent = main

-- ============ SLIDER TOGGLE BUILDER ============

local function makeSliderToggle(parent, labelText, yPos, getState, setState)
    -- Label
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(0, 60, 0, 16)
    lbl.Position = UDim2.new(0, 10, 0, yPos)
    lbl.BackgroundTransparency = 1
    lbl.Text = labelText
    lbl.TextColor3 = Color3.fromRGB(200, 200, 220)
    lbl.Font = Enum.Font.GothamBold
    lbl.TextSize = 10
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = parent

    -- Track
    local TRACK_W = 40
    local KNOB_W  = 16
    local RANGE   = TRACK_W - KNOB_W

    local track = Instance.new("Frame")
    track.Size = UDim2.new(0, TRACK_W, 0, 16)
    track.Position = UDim2.new(1, -TRACK_W - 10, 0, yPos)
    track.BackgroundColor3 = Color3.fromRGB(50, 50, 62)
    track.BorderSizePixel = 0
    track.Parent = parent

    local tc = Instance.new("UICorner")
    tc.CornerRadius = UDim.new(0, 8)
    tc.Parent = track

    local knob = Instance.new("Frame")
    knob.Size = UDim2.new(0, KNOB_W, 0, 16)
    knob.Position = UDim2.new(0, 0, 0, 0)
    knob.BackgroundColor3 = Color3.fromRGB(230, 230, 240)
    knob.BorderSizePixel = 0
    knob.Parent = track

    local kc = Instance.new("UICorner")
    kc.CornerRadius = UDim.new(0, 8)
    kc.Parent = knob

    local function updateVisual()
        local on = getState()
        if on then
            knob.Position = UDim2.new(0, RANGE, 0, 0)
            track.BackgroundColor3 = Color3.fromRGB(40, 130, 70)
        else
            knob.Position = UDim2.new(0, 0, 0, 0)
            track.BackgroundColor3 = Color3.fromRGB(50, 50, 62)
        end
    end

    -- Click handler
    track.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
           or input.UserInputType == Enum.UserInputType.Touch then
            setState(not getState())
            updateVisual()
        end
    end)

    -- Drag handler
    local dragging = false

    knob.InputBegan:Connect(function(input)
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
        if not dragging then return end
        if input.UserInputType == Enum.UserInputType.MouseMovement
           or input.UserInputType == Enum.UserInputType.Touch then
            local trackX = track.AbsolutePosition.X
            local relX = input.Position.X - trackX
            local pct = math.clamp((relX - KNOB_W/2) / RANGE, 0, 1)
            local newOn = pct > 0.5
            if newOn ~= getState() then
                setState(newOn)
                updateVisual()
            end
        end
    end)

    updateVisual()
    return { updateVisual = updateVisual }
end

-- AUTO PANEN slider
makeSliderToggle(body, "🌾 Auto Panen", 8,
    function() return CONFIG.AUTO_ENABLED end,
    function(v)
        CONFIG.AUTO_ENABLED = v
        print("🌾 AUTO PANEN " .. (v and "ON" or "OFF"))
        if v and not MY_PLOT_NAME then detectMyPlot() end
    end
)

-- AUTO SELL slider
makeSliderToggle(body, "💰 Auto Sell", 36,
    function() return CONFIG.AUTO_SELL_ENABLED end,
    function(v)
        CONFIG.AUTO_SELL_ENABLED = v
        print("💰 AUTO SELL " .. (v and "ON" or "OFF"))
    end
)

-- ============ MINIMIZE LOGIC ============

local isMinimized = false

minBtn.MouseButton1Click:Connect(function()
    isMinimized = not isMinimized

    if isMinimized then
        body.Visible = false
        main.Size = UDim2.new(0, 150, 0, MINI_H)
        minBtn.Text = "+"
    else
        body.Visible = true
        main.Size = UDim2.new(0, 150, 0, FULL_H)
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
    if isPriorityBusy then return end
    isPriorityBusy = true

    print("")
    print("🌟 ═══ PRIORITY FARM ═══")

    local prevSell = CONFIG.AUTO_SELL_ENABLED

    CONFIG.AUTO_SELL_ENABLED = false

    task.wait(0.3)

    local totalSaved = 0
    local totalSold = 0
    local round = 0

    while ALIVE and round < 10 do
        round = round + 1

        local entries = getAllFruits()
        local saveTargets = {}
        local sellTargets = {}

        for _, e in ipairs(entries) do
            if isPriorityTarget(e) then
                if isSaveTarget(e) then
                    table.insert(saveTargets, e)
                elseif isSellTarget(e) then
                    table.insert(sellTargets, e)
                end
            end
        end

        if #saveTargets == 0 and #sellTargets == 0 then
            print(string.format("🌟 Round %d: no target", round))
            break
        end

        print(string.format("🌟 Round %d: %d save, %d jual",
            round, #saveTargets, #sellTargets))

        local beforeUUIDs = getBackpackUUIDs()
        local allTargets = {}

        for _, t in ipairs(saveTargets) do table.insert(allTargets, t) end
        for _, t in ipairs(sellTargets) do table.insert(allTargets, t) end

        for _, t in ipairs(allTargets) do
            if not ALIVE then break end
            harvest(t.plant, t.fruit)
            task.wait(0.15)
        end

        task.wait(0.8)

        local newTools = getNewBackpackTools(beforeUUIDs)

        for _, t in ipairs(newTools) do
            if not ALIVE then break end

            local w = t.weight or 0
            local mut = t.mutation
            local isCheap = isCheapMutation(mut)

            if w > CONFIG.SAVE_WEIGHT and not isCheap then
                if favoriteFruit(t.uuid) then
                    totalSaved = totalSaved + 1
                    print(string.format("🌟 💾 SAVE: %s [%s] %.2fkg",
                        t.name, mut or "-", w))
                end
            else
                totalSold = totalSold + 1
                print(string.format("🌟 💰 JUAL: %s [%s] %.2fkg",
                    t.name, mut or "-", w))
            end
            task.wait(0.15)
        end

        if #newTools > 0 then
            task.wait(0.5)
            sellBackpack()
        end

        task.wait(0.3)
    end

    print(string.format("🌟 Total: %d saved, %d sold",
        totalSaved, totalSold))

    if prevSell then
        CONFIG.AUTO_SELL_ENABLED = true
    end

    print("🌟 ═══════════════════════")
    print("")

    isPriorityBusy = false
end

-- ============ AUTO HARVEST LOOP ============

task.spawn(function()
    while ALIVE do
        task.wait(CONFIG.AUTO_DELAY)
        if not ALIVE then break end
        if isPriorityBusy then continue end

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
                        if not ALIVE or isPriorityBusy then break end
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

-- ============ AUTO SELL LOOP (3 detik) ============

task.spawn(function()
    while ALIVE do
        task.wait(CONFIG.AUTO_SELL_INTERVAL)
        if not ALIVE then break end
        if isPriorityBusy then continue end

        if CONFIG.AUTO_SELL_ENABLED then
            sellBackpack()
        end
    end
    print("🛑 Sell loop berhenti")
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

-- ============ INIT ============

if MY_PLOT_NAME then
    print("✅ Auto Farm loaded. Plot:", MY_PLOT_NAME)
    print("🎯 Kategori: > " .. CONFIG.MAX_WEIGHT .. " kg")
    print("💾 Save: > " .. CONFIG.SAVE_WEIGHT .. " kg + mutasi MAHAL")
    print("💰 Jual: semua sisanya")
else
    warn("⚠️ Plot belum terdeteksi.")
end
