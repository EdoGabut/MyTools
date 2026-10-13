-- ============================================
-- AUTO WATERING + SPRINKLE (MINIMALIS)
-- - 3 tombol: REC Water, REC Sprinkle, STOP ALL
-- - Begitu payload terekam, langsung auto-start
-- - Sprinkle cek tiap 3s, water interval 3s
-- - Plot detect via nickname di Signs
-- - Smart equip (no re-equip spam)
-- - Minimize button (collapse ke header)
-- - Guard: semua loop mati saat GUI ditutup / STOP
-- ============================================

local CoreGui           = game:GetService("CoreGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")

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

    local ok = pcall(function()
        humanoid:EquipTool(tool)
    end)
    if not ok then return nil end

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

    local ok = pcall(function()
        hookedMeta = getrawmetatable(game)
        originalNamecall = hookedMeta.__namecall
        setreadonly(hookedMeta, false)

        hookedMeta.__namecall = newcclosure(function(self, ...)
            local method = getnamecallmethod()

            if method == "FireServer"
               and typeof(self) == "Instance"
               and self.ClassName == "RemoteEvent" then
                local args = {...}

                for _, v in ipairs(args) do
                    if typeof(v) == "buffer" then
                        local str = buffer.tostring(v)
                        local prefix = str:sub(1, 1)

                        if prefix == WATER_PREFIX and state.recordingWater then
                            state.waterPayload   = v
                            state.hasWater       = true
                            state.recordingWater = false
                            _G.__waterRecorded   = true
                        end

                        if prefix == SPRINKLE_PREFIX and state.recordingSprinkle then
                            state.sprinklePayload   = v
                            state.hasSprinkle       = true
                            state.recordingSprinkle = false
                            _G.__sprinkleRecorded   = true
                        end
                    end
                end
            end

            return originalNamecall(self, ...)
        end)

        setreadonly(hookedMeta, true)
        hookActive = true
    end)

    if not ok then
        warn("❌ Hook gagal install")
    end
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
    if not ALIVE then return false end
    if not state.waterPayload then return false end

    local char = LocalPlayer.Character
    if not char then return false end

    local equipped = char:FindFirstChild(WATER_TOOL_NAME)
    if not equipped then
        equipped = ensureToolEquipped(WATER_TOOL_NAME)
        if not equipped then return false end
        task.wait(0.1)
    end

    local ok = pcall(function()
        Packet:FireServer(state.waterPayload, {equipped})
    end)
    return ok
end

local function fireSprinkle()
    if not ALIVE then return false end
    if not state.sprinklePayload then return false end

    local char = LocalPlayer.Character
    if not char then return false end

    local equipped = char:FindFirstChild(SPRINKLE_TOOL_NAME)
    if not equipped then
        equipped = ensureToolEquipped(SPRINKLE_TOOL_NAME)
        if not equipped then return false end
        task.wait(0.15)
    end

    local ok = pcall(function()
        Packet:FireServer(state.sprinklePayload, {equipped})
    end)
    return ok
end

-- ============ SHUTDOWN ============
local function shutdown(reason)
    if not ALIVE then return end
    ALIVE = false
    state.wateringOn = false
    state.sprinkleOn = false
    uninstallHook()
    if reason then
        print("🛑 Script dimatikan:", reason)
    end
end

-- ============ GUI (MINIMALIS — 3 BUTTON + HEADER) ============
local old = CoreGui:FindFirstChild("AutoFarmMinimal")
if old then old:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "AutoFarmMinimal"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = CoreGui

-- Layout constants
local FULL_HEIGHT = 168
local MINI_HEIGHT = 28

local main = Instance.new("Frame")
main.Size = UDim2.new(0, 200, 0, FULL_HEIGHT)
main.Position = UDim2.new(0, 20, 0, 60)
main.BackgroundColor3 = Color3.fromRGB(22, 22, 28)
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
header.BackgroundColor3 = Color3.fromRGB(36, 36, 46)
header.BorderSizePixel = 0
header.Parent = main

local hc = Instance.new("UICorner")
hc.CornerRadius = UDim.new(0, 10)
hc.Parent = header

-- Fix sudut bawah header (biar nggak rounded)
local headerFix = Instance.new("Frame")
headerFix.Size = UDim2.new(1, 0, 0, 10)
headerFix.Position = UDim2.new(0, 0, 1, -10)
headerFix.BackgroundColor3 = Color3.fromRGB(36, 36, 46)
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
titleLbl.Text = "💧🌱 Auto Farm"
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

-- ===== BODY =====
local body = Instance.new("Frame")
body.Name = "Body"
body.Size = UDim2.new(1, 0, 1, -28)
body.Position = UDim2.new(0, 0, 0, 28)
body.BackgroundTransparency = 1
body.Parent = main

-- ===== BUTTON 1: REC / AUTO Water =====
local waterBtn = Instance.new("TextButton")
waterBtn.Size = UDim2.new(1, -20, 0, 36)
waterBtn.Position = UDim2.new(0, 10, 0, 10)
waterBtn.BackgroundColor3 = Color3.fromRGB(60, 90, 140)
waterBtn.Text = "⏺️ REC Water"
waterBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
waterBtn.Font = Enum.Font.GothamBold
waterBtn.TextSize = 13
waterBtn.Parent = body

local wbc = Instance.new("UICorner")
wbc.CornerRadius = UDim.new(0, 8)
wbc.Parent = waterBtn

-- ===== BUTTON 2: REC / AUTO Sprinkle =====
local sprBtn = Instance.new("TextButton")
sprBtn.Size = UDim2.new(1, -20, 0, 36)
sprBtn.Position = UDim2.new(0, 10, 0, 54)
sprBtn.BackgroundColor3 = Color3.fromRGB(60, 120, 70)
sprBtn.Text = "⏺️ REC Sprinkle"
sprBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
sprBtn.Font = Enum.Font.GothamBold
sprBtn.TextSize = 13
sprBtn.Parent = body

local sbc = Instance.new("UICorner")
sbc.CornerRadius = UDim.new(0, 8)
sbc.Parent = sprBtn

-- ===== BUTTON 3: STOP ALL =====
local stopBtn = Instance.new("TextButton")
stopBtn.Size = UDim2.new(1, -20, 0, 36)
stopBtn.Position = UDim2.new(0, 10, 0, 98)
stopBtn.BackgroundColor3 = Color3.fromRGB(90, 45, 45)
stopBtn.Text = "⏹️ STOP ALL"
stopBtn.TextColor3 = Color3.fromRGB(255, 230, 230)
stopBtn.Font = Enum.Font.GothamBold
stopBtn.TextSize = 13
stopBtn.Parent = body

local stbc = Instance.new("UICorner")
stbc.CornerRadius = UDim.new(0, 8)
stbc.Parent = stopBtn

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

-- ============ BUTTON STATE HELPERS ============
local function setWaterBtnRecording()
    waterBtn.Text = "🔴 REC Water..."
    waterBtn.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
end

local function setWaterBtnActive()
    waterBtn.Text = "💧 WATER: ON"
    waterBtn.BackgroundColor3 = Color3.fromRGB(40, 130, 70)
end

local function setWaterBtnIdle()
    waterBtn.Text = "⏺️ REC Water"
    waterBtn.BackgroundColor3 = Color3.fromRGB(60, 90, 140)
end

local function setSprBtnRecording()
    sprBtn.Text = "🔴 REC Sprinkle..."
    sprBtn.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
end

local function setSprBtnActive()
    sprBtn.Text = "🌱 SPRINKLE: ON"
    sprBtn.BackgroundColor3 = Color3.fromRGB(40, 130, 70)
end

local function setSprBtnIdle()
    sprBtn.Text = "⏺️ REC Sprinkle"
    sprBtn.BackgroundColor3 = Color3.fromRGB(60, 120, 70)
end

-- ============ BUTTON 1: WATER (REC → AUTO) ============
waterBtn.MouseButton1Click:Connect(function()
    if not ALIVE then return end

    if state.recordingWater then
        state.recordingWater = false
        setWaterBtnIdle()
        return
    end

    if state.hasWater then
        state.wateringOn = not state.wateringOn
        if state.wateringOn then
            setWaterBtnActive()
        else
            waterBtn.Text = "💧 WATER: OFF"
            waterBtn.BackgroundColor3 = Color3.fromRGB(45, 60, 90)
        end
        return
    end

    local tool = ensureToolEquipped(WATER_TOOL_NAME)
    if not tool then
        waterBtn.Text = "❌ No Tool"
        task.wait(1.0)
        if ALIVE then setWaterBtnIdle() end
        return
    end

    state.recordingWater = true
    setWaterBtnRecording()
    installHook()
end)

-- ============ BUTTON 2: SPRINKLE (REC → AUTO) ============
sprBtn.MouseButton1Click:Connect(function()
    if not ALIVE then return end

    if state.recordingSprinkle then
        state.recordingSprinkle = false
        setSprBtnIdle()
        return
    end

    if state.hasSprinkle then
        state.sprinkleOn = not state.sprinkleOn
        if state.sprinkleOn then
            setSprBtnActive()
        else
            sprBtn.Text = "🌱 SPRINKLE: OFF"
            sprBtn.BackgroundColor3 = Color3.fromRGB(50, 70, 55)
        end
        return
    end

    local tool = ensureToolEquipped(SPRINKLE_TOOL_NAME)
    if not tool then
        sprBtn.Text = "❌ No Tool"
        task.wait(1.0)
        if ALIVE then setSprBtnIdle() end
        return
    end

    state.recordingSprinkle = true
    setSprBtnRecording()
    installHook()
end)

-- ============ BUTTON 3: STOP ALL ============
stopBtn.MouseButton1Click:Connect(function()
    if not ALIVE then return end

    state.wateringOn = false
    state.sprinkleOn = false
    state.busySprinkle = false

    if state.hasWater then
        waterBtn.Text = "💧 WATER: OFF"
        waterBtn.BackgroundColor3 = Color3.fromRGB(45, 60, 90)
    else
        setWaterBtnIdle()
    end

    if state.hasSprinkle then
        sprBtn.Text = "🌱 SPRINKLE: OFF"
        sprBtn.BackgroundColor3 = Color3.fromRGB(50, 70, 55)
    else
        setSprBtnIdle()
    end

    print("⏹️ STOP ALL — semua fitur OFF")
end)

-- ============ UI UPDATE LOOP (auto-start setelah record) ============
task.spawn(function()
    while ALIVE and gui.Parent do
        task.wait(0.1)
        if not ALIVE then break end

        if _G.__waterRecorded then
            _G.__waterRecorded = nil
            state.wateringOn = true
            setWaterBtnActive()
            print("✅ Water payload recorded → AUTO ON")
        end

        if _G.__sprinkleRecorded then
            _G.__sprinkleRecorded = nil
            state.sprinkleOn = true
            setSprBtnActive()
            print("✅ Sprinkle payload recorded → AUTO ON")
        end
    end
    print("🛑 UI update loop berhenti")
end)

-- ============ MAIN LOOP ============
task.spawn(function()
    while ALIVE and gui.Parent do
        task.wait(CHECK_INTERVAL)
        if not ALIVE then break end

        local has, count = hasActiveSprinkler()

        -- ==== Prioritas: pasang sprinkle kalau kosong ====
        if state.sprinkleOn and state.hasSprinkle
           and not has and not state.busySprinkle then

            state.busySprinkle = true
            local ok = fireSprinkle()
            if ok then
                task.wait(SPRINKLE_SETTLE)
                if not ALIVE then break end
                hasActiveSprinkler()
            end
            state.busySprinkle = false
        end

        -- ==== Watering ====
        if state.wateringOn and state.hasWater and not state.busySprinkle then
            if has then
                fireWater()
            end
        end
    end
    print("🛑 Main loop berhenti")
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

-- ============ INIT ============
installHook()

print("✅ Auto Farm Minimal loaded")
if MY_PLOT_NAME then
    print("📍 Plot:", MY_PLOT_NAME)
else
    warn("⚠️ Plot belum terdeteksi, akan retry saat loop jalan")
end
