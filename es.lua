-- ESP untuk NPC di game.Workspace.NPCS dengan jarak

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer

local npcFolder = game.Workspace:WaitForChild("NPCS")

-- Bersihkan ESP lama kalau ada
for _, obj in pairs(game.CoreGui:GetDescendants()) do
    if obj:IsA("BillboardGui") and obj.Name == "NPC_ESP" then
        obj:Destroy()
    end
end

-- Fungsi buat ESP
local function createESP(npc)
    if not npc:IsA("Model") then return end
    local head = npc:FindFirstChild("Head") or npc:FindFirstChildWhichIsA("BasePart")
    if not head then return end

    local billboard = Instance.new("BillboardGui")
    billboard.Name = "NPC_ESP"
    billboard.Size = UDim2.new(0, 200, 0, 50)
    billboard.StudsOffset = Vector3.new(0, 3, 0)
    billboard.AlwaysOnTop = true
    billboard.Adornee = head
    billboard.Parent = game.CoreGui

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, 0, 1, 0)
    label.BackgroundTransparency = 1
    label.TextColor3 = Color3.fromRGB(255, 255, 0)
    label.TextStrokeTransparency = 0
    label.TextScaled = true
    label.Font = Enum.Font.SourceSansBold
    label.Text = npc.Name .. " | 0 studs"
    label.Parent = billboard

    return billboard, label, head
end

-- Simpan ESP per NPC
local espData = {}

local function setupNPC(npc)
    if espData[npc] then return end
    local billboard, label, head = createESP(npc)
    if billboard then
        espData[npc] = {billboard = billboard, label = label, head = head}
    end
end

-- Pasang ESP ke semua NPC yang ada
for _, npc in pairs(npcFolder:GetChildren()) do
    setupNPC(npc)
end

-- Pantau NPC baru
npcFolder.ChildAdded:Connect(setupNPC)

-- Update jarak tiap frame
RunService.RenderStepped:Connect(function()
    local char = LocalPlayer.Character
    if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    for npc, data in pairs(espData) do
        if not npc.Parent or not data.head or not data.head.Parent then
            if data.billboard then data.billboard:Destroy() end
            espData[npc] = nil
        else
            local dist = (hrp.Position - data.head.Position).Magnitude
            data.label.Text = string.format("%s | %d studs", npc.Name, math.floor(dist))
        end
    end
end)
