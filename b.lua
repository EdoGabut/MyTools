-- ============================================================
-- AUTO FIRE BRIAR — MALAM SAJA (Auto-start, no GUI)
-- ============================================================
local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting          = game:GetService("Lighting")

local player = Players.LocalPlayer

-- ===== CONFIG =====
local CONFIG = {
    NIGHT_START     = 18,   -- jam 18:00 dianggap malam
    NIGHT_END       = 6,    -- jam 06:00 dianggap pagi
    PACKET_BRIAR    = "\195\0009\nBriar Rose",
    FIRE_COUNT      = 2,    -- fire briar berapa kali
    FIRE_GAP        = 1.5,  -- jeda antar fire
    FIRE_ON_LOAD_IF_NIGHT = true,  -- kalau load saat sudah malam, langsung fire
}

-- ===== STATE =====
local running = true
local lastPhase = nil
local sequenceRunning = false

-- ===== HELPERS =====
local function log(msg)
    print(string.format("[Briar %s] %s", os.date("%H:%M:%S"), msg))
end

local function isNight()
    local h = (Lighting.ClockTime or 12) % 24
    return h >= CONFIG.NIGHT_START or h < CONFIG.NIGHT_END
end

local function fireBriar()
    local ok, err = pcall(function()
        local args = { buffer.fromstring(CONFIG.PACKET_BRIAR) }
        ReplicatedStorage
            :WaitForChild("SharedModules")
            :WaitForChild("Packet")
            :WaitForChild("RemoteEvent")
            :FireServer(unpack(args))
    end)
    if ok then log("📦 Briar fired")
    else log("❌ Fire gagal: " .. tostring(err)) end
    return ok
end

-- ===== NIGHT ACTION =====
local function doNightAction()
    if sequenceRunning then return end
    sequenceRunning = true
    log("🌙 MALAM → fire Briar x" .. CONFIG.FIRE_COUNT)

    for i = 1, CONFIG.FIRE_COUNT do
        if not running then break end
        if fireBriar() then
            log("✓ Briar #" .. i)
        end
        if i < CONFIG.FIRE_COUNT then
            task.wait(CONFIG.FIRE_GAP)
        end
    end

    log("=== NIGHT DONE ===")
    sequenceRunning = false
end

-- ===== PHASE WATCHER =====
local function startPhaseWatcher()
    lastPhase = isNight() and "night" or "day"
    log("Initial phase: " .. lastPhase)

    -- Kalau load saat sudah malam → langsung fire
    if CONFIG.FIRE_ON_LOAD_IF_NIGHT and lastPhase == "night" then
        task.spawn(doNightAction)
    end

    RunService.Heartbeat:Connect(function()
        if not running then return end
        local now = isNight() and "night" or "day"
        if now ~= lastPhase then
            lastPhase = now
            if now == "night" then
                task.spawn(doNightAction)
            else
                log("☀️ Siang — idle")
            end
        end
    end)
end

-- ===== EXECUTE =====
startPhaseWatcher()
log("▶ Aktif — nunggu malam (18:00)")
