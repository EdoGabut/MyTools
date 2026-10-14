-- ============================================
-- SIMPLE COUNTER — Buah Kategori di Pohon
-- Cuma nampilin jumlah, nggak ada list
-- ============================================

local CoreGui = game:GetService("CoreGui")
local Players = game:GetService("Players")

local LocalPlayer = Players.LocalPlayer
local ROOT = workspace:WaitForChild("Gardens")

-- ============ CONFIG ============

local MIN_WEIGHT = 80    -- berat minimal buat masuk kategori
local WEIGHT_K = 9

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

local function getMyPlot()
    if MY_PLOT_NAME and ROOT:FindFirstChild(MY_PLOT_NAME) then
        return ROOT:FindFirstChild(MY_PLOT_NAME)
    end
    for _, plot in ipairs(ROOT:GetChildren()) do
        if isMyPlot(plot) then
            MY_PLOT_NAME = plot.Name
            return plot
        end
    end
    return nil
end

-- ============ UTIL ============

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

-- ============ COUNT ============

local function countCategoryFruits()
    local count = 0

    local plot = getMyPlot()
    if not plot then return 0 end

    local plants = plot:FindFirstChild("Plants")
    if not plants then return 0 end

    for _, plant in ipairs(plants:GetChildren()) do
        local ownerId = plant.Name:match("^(%d+)_")
        if not ownerId or tonumber(ownerId) == LocalPlayer.UserId then
            local fruits = plant:FindFirstChild("Fruits")
            if fruits then
                for _, fruit in ipairs(fruits:GetChildren()) do
                    local weight = getFruitWeight(fruit)
                    local mutation = getMutation(fruit)

                    -- Masuk kategori: berat > MIN_WEIGHT + BELUM ada mutasi
                    if weight and weight > MIN_WEIGHT and not mutation then
                        count = count + 1
                    end
                end
            end
        end
    end

    return count
end

-- ============ GUI ============

local old = CoreGui:FindFirstChild("CategoryCounter")
if old then old:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "CategoryCounter"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = CoreGui

local main = Instance.new("Frame")
main.Size = UDim2.new(0, 160, 0, 70)
main.Position = UDim2.new(0, 20, 0, 60)
main.BackgroundColor3 = Color3.fromRGB(24, 24, 30)
main.BorderSizePixel = 0
main.Active = true
main.Draggable = true
main.Parent = gui

local mc = Instance.new("UICorner")
mc.CornerRadius = UDim.new(0, 10)
mc.Parent = main

-- Title
local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 0, 22)
title.BackgroundColor3 = Color3.fromRGB(40, 40, 52)
title.BorderSizePixel = 0
title.Text = "  🌳 Kategori di Pohon"
title.TextColor3 = Color3.fromRGB(230, 230, 240)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Font = Enum.Font.GothamBold
title.TextSize = 11
title.Parent = main

local tc = Instance.new("UICorner")
tc.CornerRadius = UDim.new(0, 10)
tc.Parent = title

-- Close button
local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 22, 0, 22)
closeBtn.Position = UDim2.new(1, -22, 0, 0)
closeBtn.BackgroundTransparency = 1
closeBtn.Text = "✕"
closeBtn.TextColor3 = Color3.fromRGB(255, 100, 100)
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 13
closeBtn.Parent = title
closeBtn.MouseButton1Click:Connect(function() gui:Destroy() end)

-- Count label (besar)
local countLbl = Instance.new("TextLabel")
countLbl.Size = UDim2.new(1, -20, 0, 34)
countLbl.Position = UDim2.new(0, 10, 0, 26)
countLbl.BackgroundTransparency = 1
countLbl.Text = "0"
countLbl.TextColor3 = Color3.fromRGB(255, 220, 100)
countLbl.Font = Enum.Font.GothamBold
countLbl.TextSize = 26
countLbl.TextXAlignment = Enum.TextXAlignment.Center
countLbl.Parent = main

-- Info bawah
local infoLbl = Instance.new("TextLabel")
infoLbl.Size = UDim2.new(1, -20, 0, 12)
infoLbl.Position = UDim2.new(0, 10, 0, 58)
infoLbl.BackgroundTransparency = 1
infoLbl.Text = string.format(">%d kg, belum ada mutasi", MIN_WEIGHT)
infoLbl.TextColor3 = Color3.fromRGB(150, 150, 170)
infoLbl.Font = Enum.Font.Code
infoLbl.TextSize = 8
infoLbl.TextXAlignment = Enum.TextXAlignment.Center
infoLbl.Parent = main

-- ============ UPDATE LOOP ============

task.spawn(function()
    while gui.Parent do
        local count = countCategoryFruits()

        countLbl.Text = tostring(count)

        -- Warna berdasarkan jumlah
        if count >= 5 then
            countLbl.TextColor3 = Color3.fromRGB(255, 100, 100)  -- merah
        elseif count >= 3 then
            countLbl.TextColor3 = Color3.fromRGB(255, 200, 100)  -- kuning
        elseif count >= 1 then
            countLbl.TextColor3 = Color3.fromRGB(150, 255, 150)  -- hijau
        else
            countLbl.TextColor3 = Color3.fromRGB(200, 200, 200)  -- abu
        end

        task.wait(2)
    end
end)

print("✅ Category Counter loaded")
print("Ngitung buah > " .. MIN_WEIGHT .. " kg yang belum ada mutasi")
