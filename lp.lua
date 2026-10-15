-- ============================================
-- SIMPLE GARDEN PROTECTION & AUTO-RETURN GUI
-- ============================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer

-- Variabel Status & Konfigurasi
local savedCFrame = nil
local activeWeld = nil
local isRunning = false
local isReturning = false

-- Remote Event payload kamu
local remoteArgs = {
    buffer.fromstring("\020\000\006Garden~\000\192\151\200C\006\129\018C\b\172\003\195")
}
local remoteEvent = ReplicatedStorage:WaitForChild("SharedModules"):WaitForChild("Packet"):WaitForChild("RemoteEvent")

-- Fungsi membuat Weld ke lantai
local function weldToFloor(rootPart)
    if activeWeld then
        activeWeld:Destroy()
        activeWeld = nil
    end

    local raycastParams = RaycastParams.new()
    raycastParams.FilterDescendantsInstances = {LocalPlayer.Character}
    raycastParams.FilterType = Enum.RaycastFilterType.Exclude

    local raycastResult = workspace:Raycast(rootPart.Position, Vector3.new(0, -10, 0), raycastParams)
    
    if raycastResult and raycastResult.Instance then
        local floorPart = raycastResult.Instance
        local weld = Instance.new("WeldConstraint")
        weld.Part0 = rootPart
        weld.Part1 = floorPart
        weld.Parent = rootPart
        activeWeld = weld
    else
        rootPart.Anchored = true
    end
end

local function removeWeld(rootPart)
    if activeWeld then
        activeWeld:Destroy()
        activeWeld = nil
    end
    rootPart.Anchored = false
end

-- ============ PEMBUATAN GUI (MINIMALIS + TOGGLE & MINIMIZE) ============
local oldGui = CoreGui:FindFirstChild("GardenProtectGui")
if oldGui then oldGui:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "GardenProtectGui"
gui.ResetOnSpawn = false
gui.Parent = CoreGui

local mainFrame = Instance.new("Frame")
mainFrame.Size = UDim2.new(0, 160, 0, 65)
mainFrame.Position = UDim2.new(0, 50, 0, 50)
mainFrame.BackgroundColor3 = Color3.fromRGB(22, 22, 28)
mainFrame.BorderSizePixel = 0
mainFrame.Active = true
mainFrame.Draggable = true
mainFrame.Parent = gui
Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0, 8)

-- Header (Minimize & Title)
local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 22)
header.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
header.BorderSizePixel = 0
header.Parent = mainFrame
Instance.new("UICorner", header).CornerRadius = UDim.new(0, 8)

local titleLbl = Instance.new("TextLabel")
titleLbl.Size = UDim2.new(1, -30, 1, 0)
titleLbl.Position = UDim2.new(0, 8, 0, 0)
titleLbl.BackgroundTransparency = 1
titleLbl.Text = "🛡️ Garden Shield"
titleLbl.TextColor3 = Color3.fromRGB(220, 220, 230)
titleLbl.Font = Enum.Font.GothamBold
titleLbl.TextSize = 10
titleLbl.TextXAlignment = Enum.TextXAlignment.Left
titleLbl.Parent = header

local minBtn = Instance.new("TextButton")
minBtn.Size = UDim2.new(0, 18, 0, 18)
minBtn.Position = UDim2.new(1, -20, 0, 2)
minBtn.BackgroundColor3 = Color3.fromRGB(55, 55, 70)
minBtn.Text = "—"
minBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
minBtn.Font = Enum.Font.GothamBold
minBtn.TextSize = 10
minBtn.Parent = header
Instance.new("UICorner", minBtn).CornerRadius = UDim.new(0, 4)

-- Body (Toggle Button)
local body = Instance.new("Frame")
body.Size = UDim2.new(1, 0, 1, -22)
body.Position = UDim2.new(0, 0, 0, 22)
body.BackgroundTransparency = 1
body.Parent = mainFrame

local toggleBtn = Instance.new("TextButton")
toggleBtn.Size = UDim2.new(1, -12, 0, 32)
toggleBtn.Position = UDim2.new(0, 6, 0, 5)
toggleBtn.BackgroundColor3 = Color3.fromRGB(160, 50, 50)
toggleBtn.Text = "Status: OFF"
toggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
toggleBtn.Font = Enum.Font.GothamBold
toggleBtn.TextSize = 11
toggleBtn.Parent = body
Instance.new("UICorner", toggleBtn).CornerRadius = UDim.new(0, 6)

-- Logika Minimize
local isMinimized = false
minBtn.MouseButton1Click:Connect(function()
    isMinimized = not isMinimized
    body.Visible = not isMinimized
    mainFrame.Size = isMinimized and UDim2.new(0, 160, 0, 22) or UDim2.new(0, 160, 0, 65)
    minBtn.Text = isMinimized and "+" or "—"
end)

-- ============ LOGIKA UTAMA & PROTEKSI ============
toggleBtn.MouseButton1Click:Connect(function()
    isRunning = not isRunning
    
    local char = LocalPlayer.Character
    local rootPart = char and char:FindFirstChild("HumanoidRootPart")
    
    if isRunning then
        if rootPart then
            savedCFrame = rootPart.CFrame
            weldToFloor(rootPart)
            toggleBtn.Text = "Status: ON"
            toggleBtn.BackgroundColor3 = Color3.fromRGB(50, 140, 70)
            print("🛡️ Proteksi Garden Aktif & Welded.")
        end
    else
        if rootPart then
            removeWeld(rootPart)
        end
        savedCFrame = nil
        isReturning = false
        toggleBtn.Text = "Status: OFF"
        toggleBtn.BackgroundColor3 = Color3.fromRGB(160, 50, 50)
        print("🛑 Proteksi Dimatikan.")
    end
end)

-- Loop Utama (Anti-Sit, Paksa Weld, Cek Jarak, & Auto Return)
task.spawn(function()
    while task.wait(0.2) do
        if isRunning and savedCFrame then
            local char = LocalPlayer.Character
            if char then
                local rootPart = char:FindFirstChild("HumanoidRootPart")
                local humanoid = char:FindFirstChildOfClass("Humanoid")
                
                if rootPart and humanoid then
                    -- 1. Selalu paksa anti-sit & pastikan weld aktif jika tidak sedang kembali
                    humanoid.Sit = false
                    if not isReturning and not activeWeld then
                        weldToFloor(rootPart)
                    end
                    
                    -- 2. Cek jarak (apabila bergeser / ditarik lebih dari 5 stud)
                    local distance = (rootPart.Position - savedCFrame.Position).Magnitude
                    
                    if distance > 5 and not isReturning then
                        isReturning = true
                        print("⚠️ Terdeteksi geser (" .. math.floor(distance) .. " stud)! Memulai proses pulang ke garden...")
                        
                        -- Lepas weld agar bisa bergerak
                        removeWeld(rootPart)
                        humanoid.Sit = false
                        
                        -- Fire remote event garden
                        pcall(function()
                            remoteEvent:FireServer(unpack(remoteArgs))
                        end)
                        task.wait(0.2)
                        
                        -- Set speed ke 30 dan jalan kaki pulang
                        local originalSpeed = humanoid.WalkSpeed
                        humanoid.WalkSpeed = 30
                        local targetPos = savedCFrame.Position
                        
                        while true do
                            if not LocalPlayer.Character or not LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then break end
                            
                            local currRoot = LocalPlayer.Character.HumanoidRootPart
                            local currHumanoid = LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
                            
                            if currHumanoid then
                                currHumanoid.Sit = false
                                currHumanoid:MoveTo(targetPos)
                            end
                            
                            if (currRoot.Position - targetPos).Magnitude < 2.5 then
                                break
                            end
                            
                            task.wait(0.1)
                        end
                        
                        -- Set posisi pas ke awal, kembalikan speed, dan weld kembali ke lantai
                        rootPart.CFrame = savedCFrame
                        humanoid.WalkSpeed = originalSpeed
                        weldToFloor(rootPart)
                        
                        print("✅ Berhasil kembali ke garden dan di-weld ulang.")
                        isReturning = false
                    end
                end
            end
        end
    end
end)
