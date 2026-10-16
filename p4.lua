-- ============================================
-- AUTO HARVEST + PRIORITY FARM
-- + AUTO MAIL TRIGGER (15 Bloodlit >150kg fav → send Andri21649)
-- Filter:
--   - ≤ 80 kg → panen + jual
--   - > 80 + mutasi cheap → panen + jual
--   - > 80 + mutasi mahal + ≤ 150 kg → panen + jual
--   - > 150 kg + mutasi mahal → panen + SAVE (favorite)
--   - > 80 tanpa mutasi → SKIP (nunggu mutasi)
-- ============================================

local CoreGui           = game:GetService("CoreGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")
local UserInputService  = game:GetService("UserInputService")
local HttpService       = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer

local Packet = ReplicatedStorage:WaitForChild("SharedModules")
    :WaitForChild("Packet"):WaitForChild("RemoteEvent")

local ROOT = workspace:WaitForChild("Gardens", 30)
if not ROOT then
    warn("❌ Folder 'Gardens' tidak ditemukan.")
    return
end

-- ============ CONFIG ============

local CONFIG = {
    MAX_WEIGHT          = 80,
    SAVE_WEIGHT         = 150,
    AUTO_ENABLED        = false,
    AUTO_SELL_ENABLED   = false,
    AUTO_SELL_INTERVAL  = 3,
    AUTO_DELAY          = 0.25,
    ONLY_MY_PLOTS       = true,

    -- === AUTO MAIL ===
    MAIL_ENABLED        = true,
    MAIL_TARGET_USER    = "Andri21649",
    MAIL_TARGET_ID      = nil,           -- di-resolve otomatis
    MAIL_TRIGGER_MUT    = "Bloodlit",
    MAIL_TRIGGER_WEIGHT = 150,
    MAIL_TRIGGER_COUNT  = 15,
    MAIL_CATEGORY       = "HarvestedFruits",
    MAIL_CHECK_INTERVAL = 5,
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
local isMailBusy     = false

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

local function unfavoriteFruit(uuid)
    if not ALIVE or not uuid then return false end
    local payload = UNFAV_PREFIX .. uuid .. "\000"
    local ok = pcall(function()
        Packet:FireServer(buffer.fromstring(payload))
    end)
    return ok
end

-- ============ MAIL BUILDER (dari v9) ============

local function resolveUsername(username)
    local ok, userId = pcall(function()
        return Players:GetUserIdFromNameAsync(username)
    end)
    if ok and userId then return userId end

    local ok2, response = pcall(function()
        return request({
            Url = "https://users.roblox.com/v1/usernames/users",
            Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = HttpService:JSONEncode({
                usernames = { username },
                excludeBannedUsers = false
            })
        })
    end)
    if ok2 and response and response.Body then
        local data = HttpService:JSONDecode(response.Body)
        if data.data and data.data[1] then
            return data.data[1].id
        end
    end
    return nil
end

local function buildMultiEntryPayload(targetUserId, entries)
    local CATEGORY = CONFIG.MAIL_CATEGORY

    local needed = 16
    for _, e in ipairs(entries) do
        needed = needed + 3
            + (2 + #"ItemKey") + (2 + #e.uuid)
            + (2 + #"Count")   + 3
            + (2 + #"Category")+ (2 + #CATEGORY)
            + 1
    end
    needed = needed + 4

    local buf = buffer.create(needed)
    local pos = 0

    buffer.writeu8(buf, pos, 0x8C); pos += 1
    buffer.writeu8(buf, pos, 0x01); pos += 1
    buffer.writeu8(buf, pos, 0x69); pos += 1
    buffer.writef64(buf, pos, targetUserId); pos += 8
    buffer.writeu8(buf, pos, 0x1C); pos += 1

    local function writeString(s)
        buffer.writeu8(buf, pos, 0x0B); pos += 1
        buffer.writeu8(buf, pos, #s);  pos += 1
        for i = 1, #s do
            buffer.writeu8(buf, pos, string.byte(s, i)); pos += 1
        end
    end
    local function writeInt(n)
        buffer.writeu8(buf, pos, 0x05); pos += 1
        buffer.writeu8(buf, pos, n % 256); pos += 1
    end

    for i, entry in ipairs(entries) do
        buffer.writeu8(buf, pos, 0x05); pos += 1
        buffer.writeu8(buf, pos, i % 256); pos += 1
        buffer.writeu8(buf, pos, 0x1C); pos += 1
        writeString("ItemKey");  writeString(entry.uuid)
        writeString("Count");    writeInt(entry.count or 1)
        writeString("Category"); writeString(CATEGORY)
        buffer.writeu8(buf, pos, 0x00); pos += 1
    end
    buffer.writeu8(buf, pos, 0x00); pos += 1
    buffer.writeu8(buf, pos, 0x00); pos += 1
    buffer.writeu8(buf, pos, 0x00); pos += 1

    local final = buffer.create(pos)
    buffer.copy(final, 0, buf, 0, pos)
    return final
end

local function sendMail(targetUserId, entries)
    if not ALIVE or not targetUserId or #entries == 0 then return false end
    local payload = buildMultiEntryPayload(targetUserId, entries)
    local ok = pcall(function()
        Packet:FireServer(payload)
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
        if id then uuids[id] = item end
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
                tool     = item,
                uuid     = id,
                name     = item.Name,
                weight   = item:GetAttribute("Weight"),
                mutation = item:GetAttribute("Mutation"),
            })
        end
    end
    return newTools
end

-- cari buah fav yang match kriteria mail
local function getMailCandidates()
    local list = {}
    local backpack = LocalPlayer:FindFirstChild("Backpack")
    if not backpack then return list end

    local targetMut = CONFIG.MAIL_TRIGGER_MUT:lower()

    for _, item in ipairs(backpack:GetChildren()) do
        local uuid = item:GetAttribute("Id")
        local isFav = item:GetAttribute("IsFavorite")
        local w = item:GetAttribute("Weight")
        local mut = item:GetAttribute("Mutation")

        if uuid and isFav == true and w and mut then
            if w > CONFIG.MAIL_TRIGGER_WEIGHT
               and tostring(mut):lower() == targetMut then
                table.insert(list, {
                    tool     = item,
                    uuid     = uuid,
                    name     = item.Name,
                    weight   = w,
                    mutation = mut,
                })
            end
        end
    end
    return list
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
    CONFIG.MAIL_ENABLED = false

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

local FULL_H  = 130
local MINI_H  = 28

local main = Instance.new("Frame")
main.Size = UDim2.new(0, 180, 0, FULL_H)
main.Position = UDim2.new(0, 20, 0, 60)
main.BackgroundColor3 = Color3.fromRGB(24, 24, 30)
main.BorderSizePixel = 0
main.Active = true
main.Draggable = true
main.Parent = gui

local mc = Instance.new("UICorner"); mc.CornerRadius = UDim.new(0, 10); mc.Parent = main

local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 28)
header.BackgroundColor3 = Color3.fromRGB(40, 40, 52)
header.BorderSizePixel = 0
header.Parent = main

local hc = Instance.new("UICorner"); hc.CornerRadius = UDim.new(0, 10); hc.Parent = header

local headerFix = Instance.new("Frame")
headerFix.Size = UDim2.new(1, 0, 0, 10)
headerFix.Position = UDim2.new(0, 0, 1, -10)
headerFix.BackgroundColor3 = Color3.fromRGB(40, 40, 52)
headerFix.BorderSizePixel = 0
headerFix.Parent = header

local minBtn = Instance.new("TextButton")
minBtn.Size = UDim2.new(0, 20, 0, 20)
minBtn.Position = UDim2.new(0, 4, 0, 4)
minBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 75)
minBtn.Text = "—"
minBtn.TextColor3 = Color3.fromRGB(230, 230, 240)
minBtn.Font = Enum.Font.GothamBold
minBtn.TextSize = 12
minBtn.Parent = header

local minc = Instance.new("UICorner"); minc.CornerRadius = UDim.new(0, 5); minc.Parent = minBtn

local titleLbl = Instance.new("TextLabel")
titleLbl.Size = UDim2.new(1, -50, 1, 0)
titleLbl.Position = UDim2.new(0, 26, 0, 0)
titleLbl.BackgroundTransparency = 1
titleLbl.Text = "🌾 Farm + Mail"
titleLbl.TextColor3 = Color3.fromRGB(230, 230, 240)
titleLbl.TextXAlignment = Enum.TextXAlignment.Left
titleLbl.Font = Enum.Font.GothamBold
titleLbl.TextSize = 11
titleLbl.Parent = header

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

local body = Instance.new("Frame")
body.Name = "Body"
body.Size = UDim2.new(1, 0, 1, -28)
body.Position = UDim2.new(0, 0, 0, 28)
body.BackgroundTransparency = 1
body.Parent = main

-- ============ SLIDER TOGGLE BUILDER ============

local function makeSliderToggle(parent, labelText, yPos, getState, setState)
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(0, 80, 0, 16)
    lbl.Position = UDim2.new(0, 10, 0, yPos)
    lbl.BackgroundTransparency = 1
    lbl.Text = labelText
    lbl.TextColor3 = Color3.fromRGB(200, 200, 220)
    lbl.Font = Enum.Font.GothamBold
    lbl.TextSize = 10
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = parent

    local TRACK_W = 40
    local KNOB_W  = 16
    local RANGE   = TRACK_W - KNOB_W

    local track = Instance.new("Frame")
    track.Size = UDim2.new(0, TRACK_W, 0, 16)
    track.Position = UDim2.new(1, -TRACK_W - 10, 0, yPos)
    track.BackgroundColor3 = Color3.fromRGB(50, 50, 62)
    track.BorderSizePixel = 0
    track.Parent = parent

    local tc = Instance.new("UICorner"); tc.CornerRadius = UDim.new(0, 8); tc.Parent = track

    local knob = Instance.new("Frame")
    knob.Size = UDim2.new(0, KNOB_W, 0, 16)
    knob.Position = UDim2.new(0, 0, 0, 0)
    knob.BackgroundColor3 = Color3.fromRGB(230, 230, 240)
    knob.BorderSizePixel = 0
    knob.Parent = track

    local kc = Instance.new("UICorner"); kc.CornerRadius = UDim.new(0, 8); kc.Parent = knob

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

    track.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
           or input.UserInputType == Enum.UserInputType.Touch then
            setState(not getState())
            updateVisual()
        end
    end)

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

makeSliderToggle(body, "🌾 Auto Panen", 8,
    function() return CONFIG.AUTO_ENABLED end,
    function(v)
        CONFIG.AUTO_ENABLED = v
        print("🌾 AUTO PANEN " .. (v and "ON" or "OFF"))
        if v and not MY_PLOT_NAME then detectMyPlot() end
    end
)

makeSliderToggle(body, "💰 Auto Sell", 32,
    function() return CONFIG.AUTO_SELL_ENABLED end,
    function(v)
        CONFIG.AUTO_SELL_ENABLED = v
        print("💰 AUTO SELL " .. (v and "ON" or "OFF"))
    end
)

makeSliderToggle(body, "📬 Auto Mail", 56,
    function() return CONFIG.MAIL_ENABLED end,
    function(v)
        CONFIG.MAIL_ENABLED = v
        print("📬 AUTO MAIL " .. (v and "ON" or "OFF"))
    end
)

-- Mail status
local mailStatusLbl = Instance.new("TextLabel")
mailStatusLbl.Size = UDim2.new(1, -20, 0, 14)
mailStatusLbl.Position = UDim2.new(0, 10, 0, 82)
mailStatusLbl.BackgroundTransparency = 1
mailStatusLbl.Text = "📬 target: -"
mailStatusLbl.TextColor3 = Color3.fromRGB(180, 200, 255)
mailStatusLbl.Font = Enum.Font.Gotham
mailStatusLbl.TextSize = 9
mailStatusLbl.TextXAlignment = Enum.TextXAlignment.Left
mailStatusLbl.TextTruncate = Enum.TextTruncate.AtEnd
mailStatusLbl.Parent = body

-- ============ MINIMIZE LOGIC ============

local isMinimized = false
minBtn.MouseButton1Click:Connect(function()
    isMinimized = not isMinimized
    if isMinimized then
        body.Visible = false
        main.Size = UDim2.new(0, 180, 0, MINI_H)
        minBtn.Text = "+"
    else
        body.Visible = true
        main.Size = UDim2.new(0, 180, 0, FULL_H)
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
    if isPriorityBusy or isMailBusy then return end
    isPriorityBusy = true

    print("")
    print("🌟 ═══ PRIORITY FARM ═══")

    local prevSell = CONFIG.AUTO_SELL_ENABLED
    CONFIG.AUTO_SELL_ENABLED = false

    task.wait(0.3)

    local totalSaved = 0
    local totalSold = 0
    local round = 0

    while ALIVE and not isMailBusy and round < 10 do
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
            if not ALIVE or isMailBusy then break end
            harvest(t.plant, t.fruit)
            task.wait(0.15)
        end

        task.wait(0.8)

        local newTools = getNewBackpackTools(beforeUUIDs)
        for _, t in ipairs(newTools) do
            if not ALIVE or isMailBusy then break end
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

        if #newTools > 0 and not isMailBusy then
            task.wait(0.5)
            sellBackpack()
        end

        task.wait(0.3)
    end

    print(string.format("🌟 Total: %d saved, %d sold", totalSaved, totalSold))

    if prevSell and not isMailBusy then
        CONFIG.AUTO_SELL_ENABLED = true
    end

    print("🌟 ═══════════════════════")
    print("")
    isPriorityBusy = false
end

-- ============ MAIL MODE ============

local function doMailMode()
    if isMailBusy then return end
    isMailBusy = true

    print("")
    print("📬 ═══════════════════════════════════════")
    print("📬 AUTO MAIL MODE dimulai!")
    print("📬 ═══════════════════════════════════════")

    -- 1) Simpan state & matikan auto
    local prevAuto = CONFIG.AUTO_ENABLED
    local prevSell = CONFIG.AUTO_SELL_ENABLED
    CONFIG.AUTO_ENABLED      = false
    CONFIG.AUTO_SELL_ENABLED = false

    -- 2) Resolve target (kalau belum)
    if not CONFIG.MAIL_TARGET_ID then
        print("📬 Resolving target:", CONFIG.MAIL_TARGET_USER)
        local id = resolveUsername(CONFIG.MAIL_TARGET_USER)
        if id then
            CONFIG.MAIL_TARGET_ID = id
            print("📬 ✅ Target ID:", id)
        else
            print("📬 ❌ Gagal resolve target. Mail dibatalkan.")
            CONFIG.AUTO_ENABLED      = prevAuto
            CONFIG.AUTO_SELL_ENABLED = prevSell
            isMailBusy = false
            return
        end
    end

    if mailStatusLbl then
        mailStatusLbl.Text = string.format("📬 target: %s (%d)",
            CONFIG.MAIL_TARGET_USER, CONFIG.MAIL_TARGET_ID)
    end

    task.wait(0.3)

    -- 3) Kumpulkan kandidat
    local candidates = getMailCandidates()
    print(string.format("📬 Kandidat: %d (butuh %d)",
        #candidates, CONFIG.MAIL_TRIGGER_COUNT))

    if #candidates < CONFIG.MAIL_TRIGGER_COUNT then
        print("📬 ❌ Kandidat kurang. Mail dibatalkan.")
        CONFIG.AUTO_ENABLED      = prevAuto
        CONFIG.AUTO_SELL_ENABLED = prevSell
        isMailBusy = false
        return
    end

    -- 4) Ambil 15 (paling berat dulu)
    table.sort(candidates, function(a, b)
        return (a.weight or 0) > (b.weight or 0)
    end)

    local picked = {}
    for i = 1, CONFIG.MAIL_TRIGGER_COUNT do
        table.insert(picked, candidates[i])
    end

    -- 5) Unfav 15 buah itu
    print("📬 Unfavorite 15 buah...")
    local unfavOk = 0
    for _, t in ipairs(picked) do
        if not ALIVE then break end
        if unfavoriteFruit(t.uuid) then
            unfavOk = unfavOk + 1
            print(string.format("  📬 unfav %d/%d: %s [%s] %.1fkg",
                unfavOk, #picked, t.name, t.mutation or "-", t.weight or 0))
        end
        task.wait(0.15)
    end
    print(string.format("📬 Unfav selesai: %d/%d", unfavOk, #picked))

    task.wait(1)

    -- 6) Susun entries untuk payload mail
    local mailEntries = {}
    for _, t in ipairs(picked) do
        table.insert(mailEntries, {
            uuid  = t.uuid,
            count = 1,
            name  = t.name,
        })
    end

    -- 7) Kirim
    print(string.format("📬 Mengirim %d item ke %s (ID %d)...",
        #mailEntries, CONFIG.MAIL_TARGET_USER, CONFIG.MAIL_TARGET_ID))

    local ok = sendMail(CONFIG.MAIL_TARGET_ID, mailEntries)
    if ok then
        print("📬 ✅ Mail terkirim!")
        if mailStatusLbl then
            mailStatusLbl.Text = string.format("📬 ✅ sent %d → %s",
                #mailEntries, CONFIG.MAIL_TARGET_USER)
            mailStatusLbl.TextColor3 = Color3.fromRGB(150, 255, 150)
        end
    else
        print("📬 ❌ Gagal kirim mail.")
        if mailStatusLbl then
            mailStatusLbl.Text = "📬 ❌ send failed"
            mailStatusLbl.TextColor3 = Color3.fromRGB(255, 100, 100)
        end
    end

    task.wait(1)

    -- 8) Kembalikan auto
    CONFIG.AUTO_ENABLED      = prevAuto
    CONFIG.AUTO_SELL_ENABLED = prevSell

    print("📬 ═══════════════════════════════════════")
    print("📬 MAIL MODE selesai!")
    print("📬 ═══════════════════════════════════════")
    print("")

    isMailBusy = false
end

-- ============ AUTO HARVEST LOOP ============

task.spawn(function()
    while ALIVE do
        task.wait(CONFIG.AUTO_DELAY)
        if not ALIVE then break end
        if isPriorityBusy or isMailBusy then continue end

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
                        if not ALIVE or isPriorityBusy or isMailBusy then break end
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
        if isPriorityBusy or isMailBusy then continue end
        if CONFIG.AUTO_SELL_ENABLED then
            sellBackpack()
        end
    end
    print("🛑 Sell loop berhenti")
end)

-- ============ MAIL CHECK LOOP ============

task.spawn(function()
    while ALIVE do
        task.wait(CONFIG.MAIL_CHECK_INTERVAL)
        if not ALIVE then break end
        if isMailBusy or isPriorityBusy then continue end
        if not CONFIG.MAIL_ENABLED then continue end

        local candidates = getMailCandidates()
        local n = #candidates

        if mailStatusLbl then
            mailStatusLbl.Text = string.format("📬 %d/%d Bloodlit >150kg fav",
                n, CONFIG.MAIL_TRIGGER_COUNT)
            mailStatusLbl.TextColor3 = (n >= CONFIG.MAIL_TRIGGER_COUNT)
                and Color3.fromRGB(150, 255, 150)
                or Color3.fromRGB(180, 200, 255)
        end

        if n >= CONFIG.MAIL_TRIGGER_COUNT then
            print(string.format("📬 Trigger! %d Bloodlit >150kg fav", n))
            task.spawn(doMailMode)
        end
    end
    print("🛑 Mail check loop berhenti")
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
    print("✅ Harvest + Priority + Mail loaded. Plot:", MY_PLOT_NAME)
    print("🎯 MAX_WEIGHT:", CONFIG.MAX_WEIGHT, "kg")
    print("💾 SAVE_WEIGHT:", CONFIG.SAVE_WEIGHT, "kg")
    print("📬 Mail trigger:", CONFIG.MAIL_TRIGGER_COUNT,
        CONFIG.MAIL_TRIGGER_MUT, ">", CONFIG.MAIL_TRIGGER_WEIGHT, "kg",
        "→", CONFIG.MAIL_TARGET_USER)
else
    warn("⚠️ Plot belum terdeteksi.")
end

-- Auto resolve target mail di background
task.spawn(function()
    local id = resolveUsername(CONFIG.MAIL_TARGET_USER)
    if id then
        CONFIG.MAIL_TARGET_ID = id
        if mailStatusLbl then
            mailStatusLbl.Text = string.format("📬 target: %s (%d)",
                CONFIG.MAIL_TARGET_USER, id)
        end
        print("📬 Target ID resolved:", id)
    end
end)
