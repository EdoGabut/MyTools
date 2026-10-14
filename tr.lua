-- ============================================
-- TREE TRANSPARENCY — Simple
-- Cuma pohon transparan. Buah & HarvestPart tetap keliatan.
-- No refresh, no auto-apply. Sekali klik, selesai.
-- ============================================

local CoreGui = game:GetService("CoreGui")
local Players = game:GetService("Players")

local LocalPlayer = Players.LocalPlayer
local ROOT = workspace:WaitForChild("Gardens")

-- ============ CONFIG ============

local TRANSPARENCY_LEVEL = 0.9   -- 0.9 = 90% transparan

-- ============ STATE ============

local isTransparent = false

-- ============ PLOT DETECTION ============

local MY_PLOT_NAME = nil

local function isMyPlot(plot)
    -- Cara 1: cek userId di nama plant
    local plants = plot:FindFirstChild("Plants")
    if plants then
        for _, plant in ipairs(plants:GetChildren()) do
            local ownerId = plant.Name:match("^(%d+)_")
            if ownerId and tonumber(ownerId) == LocalPlayer.UserId then
                return true
            end
        end
    end

    -- Cara 2: cek sign
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
    for _, plot in ipairs(ROOT:GetChildren()) do
        if isMyPlot(plot) then
            return plot
        end
    end
    return nil
end

-- ============ TRANSPARENCY ============

local originalValues = {}   -- [instance] = original transparency

local function setTreeTransparent()
    local plot = getMyPlot()
    if not plot then
        warn("⚠️ Plot nggak ketemu")
        return 0
    end

    local plants = plot:FindFirstChild("Plants")
    if not plants then
        warn("⚠️ Plants folder nggak ketemu")
        return 0
    end

    local count = 0

    for _, d in ipairs(plants:GetDescendants()) do
        -- Skip HarvestPart (biar bisa panen)
        if d.Name == "HarvestPart" then
            -- skip
        elseif d:IsA("BasePart") then
            -- Simpan original
            if originalValues[d] == nil then
                originalValues[d] = d.Transparency
            end
            -- Set transparan
            d.Transparency = TRANSPARENCY_LEVEL
            count = count + 1
        elseif d:IsA("Decal") or d:IsA("Texture") then
            if originalValues[d] == nil then
                originalValues[d] = d.Transparency
            end
            d.Transparency = TRANSPARENCY_LEVEL
            count = count + 1
        end
    end

    return count
end

local function restoreTree()
    local count = 0
    for inst, orig in pairs(originalValues) do
        if inst and inst.Parent then
            inst.Transparency = orig
            count = count + 1
        end
    end
    originalValues = {}
    return count
end

-- ============ GUI ============

local old = CoreGui:FindFirstChild("TreeTransparency")
if old then old:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "TreeTransparency"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = CoreGui

local main = Instance.new("Frame")
main.Size = UDim2.new(0, 200, 0, 100)
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
title.Size = UDim2.new(1, 0, 0, 28)
title.BackgroundColor3 = Color3.fromRGB(40, 40, 52)
title.BorderSizePixel = 0
title.Text = "  🌳 Tree Transparency"
title.TextColor3 = Color3.fromRGB(230, 230, 240)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Font = Enum.Font.GothamBold
title.TextSize = 12
title.Parent = main

local tc = Instance.new("UICorner")
tc.CornerRadius = UDim.new(0, 10)
tc.Parent = title

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 28, 0, 28)
closeBtn.Position = UDim2.new(1, -28, 0, 0)
closeBtn.BackgroundTransparency = 1
closeBtn.Text = "✕"
closeBtn.TextColor3 = Color3.fromRGB(255, 100, 100)
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 15
closeBtn.Parent = title
closeBtn.MouseButton1Click:Connect(function()
    if isTransparent then
        pcall(restoreTree)
    end
    gui:Destroy()
end)

-- Toggle button
local toggleBtn = Instance.new("TextButton")
toggleBtn.Size = UDim2.new(1, -20, 0, 56)
toggleBtn.Position = UDim2.new(0, 10, 0, 36)
toggleBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 75)
toggleBtn.Text = "🌳 TRANSPARENT: OFF"
toggleBtn.TextColor3 = Color3.fromRGB(230, 230, 240)
toggleBtn.Font = Enum.Font.GothamBold
toggleBtn.TextSize = 14
toggleBtn.Parent = main

local tbc = Instance.new("UICorner")
tbc.CornerRadius = UDim.new(0, 8)
tbc.Parent = toggleBtn

-- ============ TOGGLE LOGIC ============

toggleBtn.MouseButton1Click:Connect(function()
    if isTransparent then
        -- OFF → restore
        local count = restoreTree()
        isTransparent = false
        toggleBtn.Text = "🌳 TRANSPARENT: OFF"
        toggleBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 75)
        print("🌳 Restored: " .. count .. " parts")
    else
        -- ON → make transparent
        local count = setTreeTransparent()
        if count > 0 then
            isTransparent = true
            toggleBtn.Text = "🌳 TRANSPARENT: ON"
            toggleBtn.BackgroundColor3 = Color3.fromRGB(40, 130, 70)
            print("🌳 Transparent: " .. count .. " parts")
        else
            print("⚠️ Plot / Plants nggak ketemu")
        end
    end
end)

-- ============ INIT ============

print("✅ Tree Transparency loaded")
print("Klik 🌳 TRANSPARENT buat ON/OFF")
