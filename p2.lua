-- ============================================
-- AUTO HARVEST + PRIORITY FARM + WELD
-- + AUTO CLEAR saat favorite capai 50
-- Plot detection UNIVERSAL (semua player)
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
    MAX_WEIGHT          = 90,
    AUTO_ENABLED        = false,
    AUTO_SELL_ENABLED   = false,
    AUTO_SELL_INTERVAL  = 5,
    AUTO_DELAY          = 0.25,
    ONLY_MY_PLOTS       = true,
    WELD_ENABLED        = false,
    PRIORITY_RESUME_DELAY = 3,
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

-- 🔥 Count favorite
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
-- (sama kayak sebelumnya — skip di sini biar fokus)

-- [COPY GUI DARI SCRIPT ASLI DI SINI]

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
            end
            task.wait(0.15)
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

    -- 1. Matikan auto-panen & auto-sell
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

    -- 2. Unfavorite semua buah di backpack
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

    -- 3. Tunggu sync
    task.wait(2)

    -- 4. Auto-sell semua
    print("💰 Sell semua buah...")
    sellBackpack()
    task.wait(1)

    -- 5. Resume
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
-- (sama kayak sebelumnya)

-- ============ CLEANUP ============
-- (sama kayak sebelumnya)
