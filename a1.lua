-- ============================================
-- AUTO FARM MINIMALIS + TIME LOGIC (18:00 - 06:00 NIGHT)
-- ============================================

local CoreGui           = game:GetService("CoreGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")
local Lighting          = game:GetService("Lighting")

local LocalPlayer = Players.LocalPlayer
local Packet = ReplicatedStorage:WaitForChild("SharedModules")
    :WaitForChild("Packet"):WaitForChild("RemoteEvent")

local ROOT = workspace:WaitForChild("Gardens")

-- ============ CONFIG ============
local WATER_TOOL_NAME    = "Cider Watering Can"
local SPRINKLE_TOOL_NAME = "Rare Cider Sprinkler"

local WATER_PREFIX    = "j"
local SPRINKLE_PREFIX = "8"

local CHECK_INTERVAL  = 8
local SPRINKLE_SETTLE = 1.0

-- ============ GUARD ============
local ALIVE = true

-- ============ STATE ============
local state = {
    recordingWater    = false,
    recordingSprinkle = false,

    waterPayload      = nil,
    sprinklePayload   = nil,

    hasWater    = false,
    hasSprinkle = false,

    wateringOn   = false,
    sprinkleOn   = false,
    busySprinkle = false,
}

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
                return MY_PLOT_NAME
            end
        end
    end
    return nil
end

local function getMyPlot()
    if not MY_PLOT_NAME or not ROOT:FindFirstChild(MY_PLOT_NAME) then
        MY_PLOT_NAME = nil
        detectMyPlot()
    end
    return MY_PLOT_NAME and ROOT:FindFirstChild(MY_PLOT_NAME) or nil
end

detectMyPlot()

-- ============ TOOL EQUIP (SMART) ============
local function ensureToolEquipped(toolName)
    local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    if not char then return nil end

    local equipped = char:FindFirstChild(toolName)
    if equipped then return equipped end

    local backpack = LocalPlayer:FindFirstChild("Backpack")
    if not backpack then return nil end
    local tool = backpack:FindFirstChild(toolName)
    if not tool then return nil end

    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if not humanoid then return nil end

    pcall(function() humanoid:EquipTool(tool) end)
    
    local t0 = tick()
    while tick() - t0 < 0.5 do
        task.wait(0.05)
        local eq = char:FindFirstChild(toolName)
        if eq then return eq end
    end
    return char:FindFirstChild(toolName)
end

-- ============ CHECK SPRINKLERS ============
local function hasActiveSprinkler()
    local plot = getMyPlot()
    if not plot then return false, 0 end
    local sprinklers = plot:FindFirstChild("Sprinklers")
    if sprinklers then
        local n = #sprinklers:GetChildren()
        return n > 0, n
    end
    return false, 0
end

-- ============ HOOK ============
local hookActive = false
local originalNamecall = nil
local hookedMeta = nil

local function installHook()
    if hookActive then return end
    pcall(function()
        hookedMeta = getrawmetatable(game)
        originalNamecall = hookedMeta.__namecall
        setreadonly(hookedMeta, false)

        hookedMeta.__namecall = newcclosure(function(self, ...)
            local method = getnamecallmethod()
            if method == "FireServer" and typeof(self) == "Instance" and self.ClassName == "RemoteEvent" then
                local args = {...}
                for _, v in ipairs(args) do
                    if typeof(v) == "buffer" then
                        local str = buffer.tostring(v)
                        local prefix = str:sub(1, 1)

                        if prefix == WATER_PREFIX and state.recordingWater then
                            state.waterPayload = v
                            state.hasWater = true
                            state.recordingWater = false
                            _G.__waterRecorded = true
                        end

                        if prefix == SPRINKLE_PREFIX and state.recordingSprinkle then
                            state.sprinklePayload = v
                            state.hasSprinkle = true
                            state.recordingSprinkle = false
                            _G.__sprinkleRecorded = true
                        end
                    end
                end
            end
            return originalNamecall(self, ...)
        end)
        setreadonly(hookedMeta, true)
        hookActive = true
    end)
end

local function uninstallHook()
    if not hookActive then return end
    pcall(function()
        setreadonly(hookedMeta, false)
        hookedMeta.__namecall = originalNamecall
        setreadonly(hookedMeta, true)
    end)
    hookActive = false
end

-- ============ FIRE PAYLOAD ============
local function fireWater()
    if not ALIVE or not state.waterPayload then return false end
    local char = LocalPlayer.Character
    if not char then return false end
    local equipped = char:FindFirstChild(WATER_TOOL_NAME) or ensureToolEquipped(WATER_TOOL_NAME)
    if not equipped then return false end
    
    local ok = pcall(function() Packet:FireServer(state.waterPayload, {equipped}) end)
    return ok
end

local function fireSprinkle()
    if not ALIVE or not state.sprinklePayload then return false end
    local char = LocalPlayer.Character
    if not char then return false end
    local equipped = char:FindFirstChild(SPRINKLE_TOOL_NAME) or ensureToolEquipped(SPRINKLE_TOOL_NAME)
    if not equipped then return false end

    local ok = pcall(function() Packet:FireServer(state.sprinklePayload, {equipped}) end)
    return ok
end

-- ============ SHUTDOWN ============
local function shutdown(reason)
    if not ALIVE then return end
    ALIVE = false
    state.wateringOn = false
    state.sprinkleOn = false
    uninstallHook()
end

-- ============ GUI (KECIL & KOMPAK) ============
local old = CoreGui:FindFirstChild("AutoFarmMinimal")
if old then old:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "AutoFarmMinimal"
gui.ResetOnSpawn = false
gui.Parent = CoreGui

local main = Instance.new("Frame")
main.Size = UDim2.new(0, 150, 0, 115)
main.Position = UDim2.new(0, 20, 0, 60)
main.BackgroundColor3 = Color3.fromRGB(22, 22, 28)
main.BorderSizePixel = 0
main.Active = true
main.Draggable = true
main.Parent = gui

local mc = Instance.new("UICorner")
mc.CornerRadius = UDim.new(0, 8)
mc.Parent = main

-- Header
local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 22)
header.BackgroundColor3 = Color3.fromRGB(36, 36, 46)
header.BorderSizePixel = 0
header.Parent = main

local hc = Instance.new("UICorner")
hc.CornerRadius = UDim.new(0, 8)
hc.Parent = header

local titleLbl = Instance.new("TextLabel")
titleLbl.Size = UDim2.new(1, -25, 1, 0)
titleLbl.Position = UDim2.new(0, 6, 0, 0)
titleLbl.BackgroundTransparency = 1
titleLbl.Text = "💧 Auto Farm (Time)"
titleLbl.TextColor3 = Color3.fromRGB(200, 200, 210)
titleLbl.TextXAlignment = Enum.TextXAlignment.Left
titleLbl.Font = Enum.Font.GothamBold
titleLbl.TextSize = 10
titleLbl.Parent = header

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 18, 0, 18)
closeBtn.Position = UDim2.new(1, -20, 0, 2)
closeBtn.BackgroundTransparency = 1
closeBtn.Text = "✕"
closeBtn.TextColor3 = Color3.fromRGB(255, 100, 100)
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 11
closeBtn.Parent = header

closeBtn.MouseButton1Click:Connect(function()
    shutdown("GUI ditutup")
    gui:Destroy()
end)

-- Body Container
local body = Instance.new("Frame")
body.Size = UDim2.new(1, 0, 1, -22)
body.Position = UDim2.new(0, 0, 0, 22)
body.BackgroundTransparency = 1
body.Parent = main

-- Button 1: REC Water
local waterBtn = Instance.new("TextButton")
waterBtn.Size = UDim2.new(1, -12, 0, 24)
waterBtn.Position = UDim2.new(0, 6, 0, 6)
waterBtn.BackgroundColor3 = Color3.fromRGB(50, 80, 120)
waterBtn.Text = "⏺️ REC Water"
waterBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
waterBtn.Font = Enum.Font.GothamBold
waterBtn.TextSize = 10
waterBtn.Parent = body
Instance.new("UICorner", waterBtn).CornerRadius = UDim.new(0, 6)

-- Button 2: REC Sprinkle
local sprBtn = Instance.new("TextButton")
sprBtn.Size = UDim2.new(1, -12, 0, 24)
sprBtn.Position = UDim2.new(0, 6, 0, 34)
sprBtn.BackgroundColor3 = Color3.fromRGB(50, 100, 60)
sprBtn.Text = "⏺️ REC Sprinkle"
sprBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
sprBtn.Font = Enum.Font.GothamBold
sprBtn.TextSize = 10
sprBtn.Parent = body
Instance.new("UICorner", sprBtn).CornerRadius = UDim.new(0, 6)

-- Button 3: STOP ALL / Status
local stopBtn = Instance.new("TextButton")
stopBtn.Size = UDim2.new(1, -12, 0, 24)
stopBtn.Position = UDim2.new(0, 6, 0, 62)
stopBtn.BackgroundColor3 = Color3.fromRGB(90, 45, 45)
stopBtn.Text = "⏹️ STOP ALL"
stopBtn.TextColor3 = Color3.fromRGB(255, 230, 230)
stopBtn.Font = Enum.Font.GothamBold
stopBtn.TextSize = 10
stopBtn.Parent = body
Instance.new("UICorner", stopBtn).CornerRadius = UDim.new(0, 6)

-- Label Jam / Status Waktu di Bawah
local timeLbl = Instance.new("TextLabel")
timeLbl.Size = UDim2.new(1, -12, 0, 15)
timeLbl.Position = UDim2.new(0, 6, 0, 90)
timeLbl.BackgroundTransparency = 1
timeLbl.Text = "Time: 00:00 (Siang)"
timeLbl.TextColor3 = Color3.fromRGB(150, 150, 160)
timeLbl.Font = Enum.Font.Gotham
timeLbl.TextSize = 9
timeLbl.TextXAlignment = Enum.TextXAlignment.Center
timeLbl.Parent = body

-- ============ EVENT BUTTONS ============
waterBtn.MouseButton1Click:Connect(function()
    if not ALIVE then return end
    if state.recordingWater then
        state.recordingWater = false
        waterBtn.Text = "⏺️ REC Water"
        waterBtn.BackgroundColor3 = Color3.fromRGB(50, 80, 120)
        return
    end
    if state.hasWater then
        state.wateringOn = not state.wateringOn
        waterBtn.Text = state.wateringOn and "💧 WATER: ON" or "💧 WATER: OFF"
        waterBtn.BackgroundColor3 = state.wateringOn and Color3.fromRGB(40, 120, 60) or Color3.fromRGB(45, 60, 90)
        return
    end
    if not ensureToolEquipped(WATER_TOOL_NAME) then return end
    state.recordingWater = true
    waterBtn.Text = "🔴 REC Water..."
    waterBtn.BackgroundColor3 = Color3.fromRGB(150, 40, 40)
    installHook()
end)

sprBtn.MouseButton1Click:Connect(function()
    if not ALIVE then return end
    if state.recordingSprinkle then
        state.recordingSprinkle = false
        sprBtn.Text = "⏺️ REC Sprinkle"
        sprBtn.BackgroundColor3 = Color3.fromRGB(50, 100, 60)
        return
    end
    if state.hasSprinkle then
        state.sprinkleOn = not state.sprinkleOn
        sprBtn.Text = state.sprinkleOn and "🌱 SPRINKLE: ON" or "🌱 SPRINKLE: OFF"
        sprBtn.BackgroundColor3 = state.sprinkleOn and Color3.fromRGB(40, 120, 60) or Color3.fromRGB(50, 70, 55)
        return
    end
    if not ensureToolEquipped(SPRINKLE_TOOL_NAME) then return end
    state.recordingSprinkle = true
    sprBtn.Text = "🔴 REC Sprinkle..."
    sprBtn.BackgroundColor3 = Color3.fromRGB(150, 40, 40)
    installHook()
end)

stopBtn.MouseButton1Click:Connect(function()
    state.wateringOn = false
    state.sprinkleOn = false
    state.busySprinkle = false
    waterBtn.Text = state.hasWater and "💧 WATER: OFF" or "⏺️ REC Water"
    sprBtn.Text = state.hasSprinkle and "🌱 SPRINKLE: OFF" or "⏺️ REC Sprinkle"
end)

-- ============ AUTO TIME CHECK & LOOPS ============
task.spawn(function()
    while ALIVE and gui.Parent do
        task.wait(0.5)
        
        -- Ambil jam in-game dari Lighting
        local clockTime = Lighting.ClockTime
        local hour = math.floor(clockTime)
        local minute = math.floor((clockTime - hour) * 60)
        
        -- Logika Fleksibel: Malam = di atas/sama dengan jam 18 ATAU di bawah jam 6 pagi
        local isNight = (clockTime >= 18.0 or clockTime < 6.0)
        
        if isNight then
            timeLbl.Text = string.format("⏰ %02d:%02d (Malam - START)", hour, minute)
            timeLbl.TextColor3 = Color3.fromRGB(100, 255, 100)
            
            -- Otomatis aktifkan jika payload sudah ada
            if state.hasWater then state.wateringOn = true end
            if state.hasSprinkle then state.sprinkleOn = true end
        else
            timeLbl.Text = string.format("⏰ %02d:%02d (Siang - STOP)", hour, minute)
            timeLbl.TextColor3 = Color3.fromRGB(255, 100, 100)
            
            -- Otomatis matikan saat siang
            state.wateringOn = false
            state.sprinkleOn = false
        end

        if _G.__waterRecorded then
            _G.__waterRecorded = nil
            state.wateringOn = true
            waterBtn.Text = "💧 WATER: ON"
            waterBtn.BackgroundColor3 = Color3.fromRGB(40, 120, 60)
        end

        if _G.__sprinkleRecorded then
            _G.__sprinkleRecorded = nil
            state.sprinkleOn = true
            sprBtn.Text = "🌱 SPRINKLE: ON"
            sprBtn.BackgroundColor3 = Color3.fromRGB(40, 120, 60)
        end
    end
end)

-- Main Loop untuk jalankan fitur saat aktif
task.spawn(function()
    while ALIVE and gui.Parent do
        task.wait(CHECK_INTERVAL)
        if not ALIVE then break end

        local has, _ = hasActiveSprinkler()

        if state.sprinkleOn and state.hasSprinkle and not has and not state.busySprinkle then
            state.busySprinkle = true
            if fireSprinkle() then
                task.wait(SPRINKLE_SETTLE)
                hasActiveSprinkler()
            end
            state.busySprinkle = false
        end

        if state.wateringOn and state.hasWater and not state.busySprinkle then
            if has then
                fireWater()
            end
        end
    end
end)

gui.Destroying:Connect(function() shutdown("GUI Destroying") end)
installHook()
print("✅ Auto Farm Time Minimal Loaded")
