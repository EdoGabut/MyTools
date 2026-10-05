--[[
    MERGED SCRIPT — Anti-Ragdoll + Anti-Stun + Anti-Seat
    - Anti-Ragdoll + Anti-Stun (langsung aktif, persist respawn)
    - Anti-Seat (deteksi Sit → fire remote stand-up)
    - Anti-Knockdown (deteksi tidur di tanah → fire remote)
    - NO WalkSpeed lock, NO JumpPower fix, NO Health lock
    - NO Noclip, NO Prompt auto
--]]

if not game:IsLoaded() then
    game.Loaded:Wait()
end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer

-- ====== CONFIG ======
local ENABLE_ANTI_RAGDOLL    = true
local ENABLE_ANTI_STUN       = true
local ENABLE_FREEZE          = true
local ENABLE_ANTI_SEAT       = true
local ENABLE_ANTI_KNOCKDOWN  = true
local ANTI_SEAT_COOLDOWN     = 0.4
local LOG_ENABLED            = true

-- ====== STATE ======
local Frozen = false

-- Anti-Seat state
local SEAT_REMOTE_ARGS = {
    buffer.fromstring("\020\000\006Garden~\000\192\151\200C\006\129\018C\b\172\003\195")
}
local seatRemote = nil
local lastSeatFire = 0
local wasSitting = false
local wasDown = false
local seatFireCount = 0

local BlockedStates = {
    [Enum.HumanoidStateType.Ragdoll] = true,
    [Enum.HumanoidStateType.FallingDown] = true,
    [Enum.HumanoidStateType.Physics] = true,
    [Enum.HumanoidStateType.Dead] = true
}

-- ====== FUNGSI ANTI-RAGDOLL / STUN ======
local function ForceNormal(character)
    local hum = character:FindFirstChildOfClass("Humanoid")
    local hrp = character:FindFirstChild("HumanoidRootPart")
    if not hum or not hrp then return end

    pcall(function()
        hum:ChangeState(Enum.HumanoidStateType.RunningNoPhysics)
    end)

    if ENABLE_FREEZE and not Frozen then
        Frozen = true
        hrp.Anchored = true
        hrp.AssemblyLinearVelocity = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
        hrp.CFrame += Vector3.new(0, 1.5, 0)
    end
end

local function Release(character)
    local hrp = character:FindFirstChild("HumanoidRootPart")
    if hrp and Frozen then
        hrp.Anchored = false
        Frozen = false
    end
end

local function RestoreMotors(character)
    for _, v in ipairs(character:GetDescendants()) do
        if v:IsA("Motor6D") and not v.Enabled then
            pcall(function() v.Enabled = true end)
        end
    end
end

local function AntiStun(character)
    local hum = character:FindFirstChildOfClass("Humanoid")
    local hrp = character:FindFirstChild("HumanoidRootPart")
    if not hum or not hrp then return end

    local isMovingInput = false
    pcall(function()
        isMovingInput = hum.MoveDirection.Magnitude > 0.1
    end)

    local velocity = hrp.AssemblyLinearVelocity
    local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude

    local isStunned = isMovingInput and speed < 1

    if isStunned then
        pcall(function()
            hum:ChangeState(Enum.HumanoidStateType.Running)
            hum.PlatformStand = false
            hum.Sit = false
            hum:SetStateEnabled(Enum.HumanoidStateType.Physics, false)
            hum:SetStateEnabled(Enum.HumanoidStateType.PlatformStanding, false)
        end)

        RestoreMotors(character)

        if hrp.Anchored and not Frozen then
            pcall(function() hrp.Anchored = false end)
        end
    end
end

local function InitAntiRagdoll(character)
    local hum = character:WaitForChild("Humanoid", 10)
    if not hum then return end

    for state in pairs(BlockedStates) do
        pcall(function() hum:SetStateEnabled(state, false) end)
    end

    hum.StateChanged:Connect(function(_, new)
        if ENABLE_ANTI_RAGDOLL and BlockedStates[new] then
            ForceNormal(character)
            RestoreMotors(character)
        end
    end)

    RunService.Stepped:Connect(function()
        if not ENABLE_ANTI_RAGDOLL and not ENABLE_ANTI_STUN then
            Release(character)
            return
        end

        if ENABLE_ANTI_RAGDOLL then
            if BlockedStates[hum:GetState()] then
                ForceNormal(character)
            else
                Release(character)
            end
        end

        if ENABLE_ANTI_STUN then
            AntiStun(character)
        end
    end)
end

LocalPlayer.CharacterAdded:Connect(function(char)
    task.wait(0.4)
    InitAntiRagdoll(char)
end)

if LocalPlayer.Character then
    InitAntiRagdoll(LocalPlayer.Character)
end

-- ============================================================
-- ====== ANTI-SEAT + ANTI-KNOCKDOWN ======
-- ============================================================
local function getSeatRemote()
    if seatRemote and seatRemote.Parent then return seatRemote end
    local ok, rem = pcall(function()
        return ReplicatedStorage:WaitForChild("SharedModules", 5)
            :WaitForChild("Packet", 5)
            :WaitForChild("RemoteEvent", 5)
    end)
    if ok and rem then
        seatRemote = rem
        return rem
    end
    return nil
end

local function fireSeatRecovery(reason)
    local now = tick()
    if now - lastSeatFire < ANTI_SEAT_COOLDOWN then return false end
    lastSeatFire = now

    local rem = getSeatRemote()
    if not rem then
        if LOG_ENABLED then
            warn("[AntiSeat] RemoteEvent tidak ditemukan")
        end
        return false
    end

    local ok, err = pcall(function()
        rem:FireServer(unpack(SEAT_REMOTE_ARGS))
    end)

    if ok then
        seatFireCount += 1
        if LOG_ENABLED then
            print(string.format("[AntiSeat] ✈️ Fire #%d — %s", seatFireCount, reason or ""))
        end
    else
        if LOG_ENABLED then
            warn("[AntiSeat] Gagal fire: " .. tostring(err))
        end
    end
    return ok
end

local function isKnockedDown(hum, root)
    if not hum or not root then return false end
    if hum.PlatformStand then return true end
    local state = hum:GetState()
    if state == Enum.HumanoidStateType.Physics
        or state == Enum.HumanoidStateType.FallingDown
        or state == Enum.HumanoidStateType.PlatformStanding then
        return true
    end
    -- cek ketinggian: root part mepet tanah (< 1.5 stud) → kemungkinan knockdown
    local pos = root.Position
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { LocalPlayer.Character }
    local result = workspace:Raycast(pos + Vector3.new(0, 5, 0), Vector3.new(0, -20, 0), params)
    if result then
        if (pos.Y - result.Position.Y) < 1.5 then
            return true
        end
    end
    return false
end

local function checkSeatAndRecovery()
    if not ENABLE_ANTI_SEAT and not ENABLE_ANTI_KNOCKDOWN then return end

    local char = LocalPlayer.Character
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    local root = char:FindFirstChild("HumanoidRootPart")
    if not hum or not root then return end

    -- ==== 1) Kursi trap ====
    if ENABLE_ANTI_SEAT and hum.Sit then
        if not wasSitting then
            wasSitting = true
            if LOG_ENABLED then
                local seat = hum.SeatPart
                print(string.format("[AntiSeat] 🪑 Duduk di: %s — fire remote",
                    seat and seat.Name or "unknown"))
            end
        end
        fireSeatRecovery("seat-trap")
        -- fallback lokal
        pcall(function() hum.Sit = false end)
        return
    else
        if wasSitting then
            wasSitting = false
            if LOG_ENABLED then
                print("[AntiSeat] ✅ Berdiri dari kursi")
            end
        end
    end

    -- ==== 2) Knockdown ====
    if ENABLE_ANTI_KNOCKDOWN and isKnockedDown(hum, root) then
        if not wasDown then
            wasDown = true
            if LOG_ENABLED then
                print("[AntiSeat] 😴 Knockdown — fire remote")
            end
        end
        fireSeatRecovery("knockdown")
        -- fallback lokal
        pcall(function()
            hum.PlatformStand = false
            hum:ChangeState(Enum.HumanoidStateType.Running)
        end)
    else
        wasDown = false
    end
end

-- Loop anti-seat (throttled)
local lastSeatCheck = 0
RunService.Heartbeat:Connect(function()
    if not ENABLE_ANTI_SEAT and not ENABLE_ANTI_KNOCKDOWN then return end
    local now = tick()
    if now - lastSeatCheck >= 0.08 then
        lastSeatCheck = now
        pcall(checkSeatAndRecovery)
    end
end)

-- Reset state pas respawn
LocalPlayer.CharacterAdded:Connect(function()
    wasSitting = false
    wasDown = false
end)

-- ============================================================
-- ====== GUI MINI STATUS ======
-- ============================================================
local COLORS = {
    bg      = Color3.fromRGB(22, 22, 28),
    header  = Color3.fromRGB(16, 16, 20),
    text    = Color3.fromRGB(235, 235, 240),
    dim     = Color3.fromRGB(150, 150, 160),
    green   = Color3.fromRGB(80, 200, 120),
    red     = Color3.fromRGB(200, 70, 70),
    orange  = Color3.fromRGB(230, 140, 60),
    stroke  = Color3.fromRGB(60, 60, 72),
    blue    = Color3.fromRGB(60, 130, 200),
}

local function corner(p, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, r or 8)
    c.Parent = p
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "AntiRecoveryUI"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")

local frame = Instance.new("Frame")
frame.Size = UDim2.fromOffset(220, 90)
frame.Position = UDim2.fromOffset(30, 320)
frame.BackgroundColor3 = COLORS.bg
frame.BorderSizePixel = 0
frame.Active = true
frame.Parent = screenGui
corner(frame, 10)

local stroke = Instance.new("UIStroke")
stroke.Color = COLORS.green
stroke.Transparency = 0.4
stroke.Parent = frame

-- Header
local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 22)
header.BackgroundColor3 = COLORS.header
header.BorderSizePixel = 0
header.Parent = frame
corner(header, 10)

local headerFix = Instance.new("Frame")
headerFix.Size = UDim2.new(1, 0, 0, 8)
headerFix.Position = UDim2.new(0, 0, 1, -8)
headerFix.BackgroundColor3 = COLORS.header
headerFix.BorderSizePixel = 0
headerFix.Parent = header

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -12, 1, 0)
title.Position = UDim2.fromOffset(8, 0)
title.BackgroundTransparency = 1
title.Text = "🛡️ Anti Recovery"
title.TextColor3 = COLORS.text
title.Font = Enum.Font.GothamBold
title.TextSize = 11
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = header

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.fromOffset(16, 16)
closeBtn.Position = UDim2.new(1, -20, 0, 3)
closeBtn.BackgroundColor3 = COLORS.red
closeBtn.Text = "×"
closeBtn.TextColor3 = COLORS.text
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 11
closeBtn.BorderSizePixel = 0
closeBtn.Parent = header
corner(closeBtn, 4)
closeBtn.MouseButton1Click:Connect(function()
    screenGui:Destroy()
end)

local statusLbl = Instance.new("TextLabel")
statusLbl.Size = UDim2.new(1, -16, 0, 14)
statusLbl.Position = UDim2.fromOffset(8, 26)
statusLbl.BackgroundTransparency = 1
statusLbl.Text = "Monitoring..."
statusLbl.TextColor3 = COLORS.green
statusLbl.Font = Enum.Font.Code
statusLbl.TextSize = 10
statusLbl.TextXAlignment = Enum.TextXAlignment.Left
statusLbl.Parent = frame

local stateLbl = Instance.new("TextLabel")
stateLbl.Size = UDim2.new(1, -16, 0, 14)
stateLbl.Position = UDim2.fromOffset(8, 42)
stateLbl.BackgroundTransparency = 1
stateLbl.Text = "State: --"
stateLbl.TextColor3 = COLORS.dim
stateLbl.Font = Enum.Font.Code
stateLbl.TextSize = 9
stateLbl.TextXAlignment = Enum.TextXAlignment.Left
stateLbl.Parent = frame

local infoLbl = Instance.new("TextLabel")
infoLbl.Size = UDim2.new(1, -16, 0, 14)
infoLbl.Position = UDim2.fromOffset(8, 56)
infoLbl.BackgroundTransparency = 1
infoLbl.Text = "Seat fires: 0"
infoLbl.TextColor3 = COLORS.dim
infoLbl.Font = Enum.Font.Code
infoLbl.TextSize = 9
infoLbl.TextXAlignment = Enum.TextXAlignment.Left
infoLbl.Parent = frame

local ragdollLbl = Instance.new("TextLabel")
ragdollLbl.Size = UDim2.new(1, -16, 0, 14)
ragdollLbl.Position = UDim2.fromOffset(8, 70)
ragdollLbl.BackgroundTransparency = 1
ragdollLbl.Text = "Anti-Ragdoll: ON | Anti-Stun: ON | Anti-Seat: ON"
ragdollLbl.TextColor3 = COLORS.blue
ragdollLbl.Font = Enum.Font.Code
ragdollLbl.TextSize = 9
ragdollLbl.TextXAlignment = Enum.TextXAlignment.Left
ragdollLbl.Parent = frame

-- Real-time updater
task.spawn(function()
    while screenGui.Parent do
        local char = LocalPlayer.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if hum then
            local stateName = tostring(hum:GetState()):gsub("Enum.HumanoidStateType%.", "")
            stateLbl.Text = string.format("State: %s | Sit: %s | PS: %s",
                stateName, tostring(hum.Sit), tostring(hum.PlatformStand))
            infoLbl.Text = string.format("Seat fires: %d", seatFireCount)
        end
        task.wait(0.3)
    end
end)

print("✅ MERGED SCRIPT LOADED! (Anti-Ragdoll + Anti-Stun + Anti-Seat)")
print(string.format("   Anti-Seat: %s | Anti-Knockdown: %s",
    tostring(ENABLE_ANTI_SEAT), tostring(ENABLE_ANTI_KNOCKDOWN)))
