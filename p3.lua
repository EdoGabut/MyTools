-- ============================================
-- AUTO HARVEST + PRIORITY FARM + AUTO CLEAR
-- Filter:
--   - ≤ 80 kg → panen + jual
--   - > 80 + mutasi cheap → panen + jual
--   - > 80 + mutasi mahal + ≤ 200 kg → panen + jual
--   - > 200 kg + mutasi mahal → panen + SAVE (favorite)
--   - > 80 tanpa mutasi → SKIP (nunggu mutasi)
-- ============================================

local CoreGui           = game:GetService("CoreGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")

local LocalPlayer = Players.LocalPlayer

local Packet = ReplicatedStorage:WaitForChild("SharedModules")
    :WaitForChild("Packet"):WaitForChild("RemoteEvent")

local ROOT = workspace:WaitForChild("Gardens")

-- ============ CONFIG ============

local CONFIG = {
    MAX_WEIGHT          = 80,
    SAVE_WEIGHT         = 200,
    AUTO_ENABLED        = false,
    AUTO_SELL_ENABLED   = false,
    AUTO_SELL_INTERVAL  = 3,
    AUTO_DELAY          = 0.25,
    ONLY_MY_PLOTS       = true,
    FAVORITE_CAP        = 50,
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

-- Panen normal: ≤ 80 kg, ATAU > 80 + mutasi cheap
local function isNormalHarvest(e)
    if not e.weight then return false end
    if e.weight <= CONFIG.MAX_WEIGHT then return true end
    if e.mutation and isCheapMutation(e.mutation) then return true end
    return false
end

-- Priority target: > MAX_WEIGHT + mutasi MAHAL
local function isPriorityTarget(e)
    if not e.weight then return false end
    if e.weight <= CONFIG.MAX_WEIGHT then return false end
    if not e.mutation then return false end
    if isCheapMutation(e.mutation) then return false end
    return true
end

-- SAVE target: > 200 kg + mutasi MAHAL
local function isSaveTarget(e)
    if not e.weight then return false end
    if e.weight <= CONFIG.SAVE_WEIGHT then return false end
    if not e.mutation then return false end
    if isCheapMutation(e.mutation) then return false end
    return true
end

-- JUAL target (dari priority): > 80 + mutasi MAHAL + ≤ 200 kg
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

-- ============ GUI (MINIMALIS) ============

local old = CoreGui:FindFirstChild("AutoHarvestMini")
if old then old:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "AutoHarvestMini"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = CoreGui

local main = Instance.new("Frame")
main.Size = UDim2.new(0, 180, 0, 118)
main.Position = UDim2.new(0, 20, 0, 60)
main.BackgroundColor3 = Color3.fromRGB(24, 24, 30)
main.BorderSizePixel = 0
main.Active = true
main.Draggable = true
main.Parent = gui

local mc = Instance.new("UICorner")
mc.CornerRadius = UDim.new(0, 10)
mc.Parent = main

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

local titleLbl = Instance.new("TextLabel")
titleLbl.Size = UDim2.new(1, -30, 1, 0)
titleLbl.Position = UDim2.new(0, 10, 0, 0)
titleLbl.BackgroundTransparency = 1
titleLbl.Text = "🌾 Auto Farm"
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

local autoBtn = Instance.new("TextButton")
autoBtn.Size = UDim2.new(1, -20, 0, 36)
autoBtn.Position = UDim2.new(0, 10, 0, 12)
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
        if not MY_PLOT_NAME then detectMyPlot() end
    else
        autoBtn.Text = "🌾 AUTO PANEN: OFF"
        autoBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 75)
        print("🌾 AUTO PANEN OFF")
    end
end)

local sellBtn = Instance.new("TextButton")
sellBtn.Size = UDim2.new(1, -20, 0, 36)
sellBtn.Position = UDim2.new(0, 10, 0, 54)
sellBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 75)
sellBtn.Text = "💰 AUTO SELL: OFF"
sellBtn.TextColor3 = Color3.fromRGB(230, 230, 240)
sellBtn.Font = Enum.Font.GothamBold
sellBtn.TextSize = 13
sellBtn.Parent = body

local stc = Instance.new("UICorner")
stc.CornerRadius = UDim.new(0, 8)
stc.Parent = sellBtn

sellBtn.MouseButton1Click:Connect(function()
    CONFIG.AUTO_SELL_ENABLED = not CONFIG.AUTO_SELL_ENABLED
    if CONFIG.AUTO_SELL_ENABLED then
        sellBtn.Text = "💰 AUTO SELL: ON"
        sellBtn.BackgroundColor3 = Color3.fromRGB(40, 130, 70)
        print("💰 AUTO SELL ON")
    else
        sellBtn.Text = "💰 AUTO SELL: OFF"
        sellBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 75)
        print("💰 AUTO SELL OFF")
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
    if sellBtn then
        sellBtn.Text = "💰 AUTO SELL: OFF"
        sellBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 75)
    end

    task.wait(0.3)

    local totalSaved = 0
    local totalSold = 0
    local round = 0

    while ALIVE and round < 10 do
        if isClearing then break end
        round = round + 1

        local entries = getAllFruits()
        local saveTargets = {}   -- > 200 + mutasi mahal
        local sellTargets = {}   -- > 80 + mutasi mahal + ≤ 200

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

        print(string.format("🌟 Round %d: %d save (≥200), %d jual (<200)",
            round, #saveTargets, #sellTargets))

        local beforeUUIDs = getBackpackUUIDs()
        local allTargets = {}

        for _, t in ipairs(saveTargets) do table.insert(allTargets, t) end
        for _, t in ipairs(sellTargets) do table.insert(allTargets, t) end

        -- Panen semua
        for _, t in ipairs(allTargets) do
            if not ALIVE or isClearing then break end
            harvest(t.plant, t.fruit)
            task.wait(0.15)
        end

        task.wait(0.8)

        -- Proses setelah masuk backpack
        local newTools = getNewBackpackTools(beforeUUIDs)

        for _, t in ipairs(newTools) do
            if not ALIVE or isClearing then break end

            local w = t.weight or 0
            local mut = t.mutation
            local isCheap = isCheapMutation(mut)

            -- 🔥 LOGIKA SAVE:
            -- Save cuma kalau > 200kg DAN mutasi MAHAL
            if w > CONFIG.SAVE_WEIGHT and not isCheap then
                -- 💾 SAVE (favorite)
                if favoriteFruit(t.uuid) then
                    totalSaved = totalSaved + 1
                    print(string.format("🌟 💾 SAVE: %s [%s] %.2fkg",
                        t.name, mut or "-", w))
                end
            else
                -- 💰 JUAL (semua sisanya)
                totalSold = totalSold + 1
                print(string.format("🌟 💰 JUAL: %s [%s] %.2fkg %s",
                    t.name, mut or "-", w,
                    isCheap and "(cheap mut)" or ""))
            end
            task.wait(0.15)
        end

        -- Jual semua yang gak di-save
        if #newTools > 0 then
            task.wait(0.5)
            sellBackpack()
        end

        task.wait(0.3)
    end

    print(string.format("🌟 Total: %d saved, %d sold",
        totalSaved, totalSold))

    if prevSell and not isClearing then
        CONFIG.AUTO_SELL_ENABLED = true
        if sellBtn then
            sellBtn.Text = "💰 AUTO SELL: ON"
            sellBtn.BackgroundColor3 = Color3.fromRGB(40, 130, 70)
        end
    end

    print("🌟 ═══════════════════════")
    print("")

    isPriorityBusy = false
end

-- ============ AUTO CLEAR MODE ============

local function doClearMode()
    if isClearing then return end
    isClearing = true
    isPriorityBusy = true

    print("")
    print("🧹 ═══ AUTO CLEAR MODE ═══")

    local prevAuto = CONFIG.AUTO_ENABLED
    local prevSell = CONFIG.AUTO_SELL_ENABLED

    CONFIG.AUTO_ENABLED      = false
    CONFIG.AUTO_SELL_ENABLED = false

    if autoBtn then
        autoBtn.Text = "🌾 AUTO PANEN: OFF"
        autoBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 75)
    end
    if sellBtn then
        sellBtn.Text = "💰 AUTO SELL: OFF"
        sellBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 75)
    end

    task.wait(0.5)

    print("🧹 Unfavorite semua...")
    local backpack = LocalPlayer:FindFirstChild("Backpack")
    local unfavedCount = 0

    if backpack then
        for _, item in ipairs(backpack:GetChildren()) do
            local uuid = item:GetAttribute("Id")
            local isFav = item:GetAttribute("IsFavorite")

            if uuid and isFav == true then
                if unfavoriteFruit(uuid) then
                    unfavedCount = unfavedCount + 1
                end
                task.wait(0.1)
            end
        end
    end

    print(string.format("🧹 Unfavorited: %d", unfavedCount))

    task.wait(2)
    print("💰 Sell semua...")
    sellBackpack()
    task.wait(1)

    CONFIG.AUTO_ENABLED      = prevAuto
    CONFIG.AUTO_SELL_ENABLED = prevSell

    if prevAuto and autoBtn then
        autoBtn.Text = "🌾 AUTO PANEN: ON"
        autoBtn.BackgroundColor3 = Color3.fromRGB(40, 130, 70)
    end
    if prevSell and sellBtn then
        sellBtn.Text = "💰 AUTO SELL: ON"
        sellBtn.BackgroundColor3 = Color3.fromRGB(40, 130, 70)
    end

    print("🧹 CLEAR MODE selesai!")
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

-- ============ AUTO SELL LOOP (3 detik) ============

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

-- ============ FAVORITE CAP CHECK ============

task.spawn(function()
    while ALIVE do
        task.wait(CONFIG.CAP_CHECK_INTERVAL)
        if not ALIVE then break end
        if isClearing or isPriorityBusy then continue end

        local favCount = countFavorites()

        if favCount >= CONFIG.FAVORITE_CAP then
            print(string.format("🧹 Favorite cap: %d/%d",
                favCount, CONFIG.FAVORITE_CAP))
            task.spawn(doClearMode)
        end
    end
    print("🛑 Favorite check loop berhenti")
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
    print("💰 Jual: semua sisanya (termasuk > 200 + cheap mut)")
    print("🧹 Favorite cap: " .. CONFIG.FAVORITE_CAP)
else
    warn("⚠️ Plot belum terdeteksi.")
end
