-- ============================================
-- CLEAR MAP + DELETE OTHER PLOTS (NO GUI)
-- - Langsung aktif saat di-execute
-- - Hapus folder plot lain (selain plot sendiri)
-- - Clear children di path tertentu
-- - Always-clear (loop, buat spawner)
-- - Disable collider
-- ============================================

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

-- ============ CONFIG ============
local CLEAR_MAP = {
    -- Hapus sekali di awal
    DELETE_CHILDREN = {
        "Workspace.Map.Middle",
    },

    -- Hapus terus-menerus (loop tiap 1s) karena suka respawn
    ALWAYS_CLEAR_CHILDREN = {
        "Workspace.Map.WildPetSpawns",
    },

    -- Matikan collider (re-apply tiap 2s)
    DISABLE_COLLIDER = {
        "Workspace.WitchCauldron",
    },
}

local DELETE_OTHER_PLOTS     = true
local PLOT_CHECK_INTERVAL    = 5   -- detik
local ALWAYS_CLEAR_INTERVAL  = 1   -- detik
local COLLIDER_INTERVAL      = 2   -- detik

-- ============ STATE ============
local ALIVE = true

-- ============ HELPERS ============
local function resolvePath(path)
    local parts = path:split(".")
    local current = game

    for _, part in ipairs(parts) do
        if not current then return nil end
        current = current:FindFirstChild(part)
    end

    return current
end

-- ============ PLOT DETECTION ============
local MY_PLOT_NAME = nil

local function detectMyPlot()
    local ROOT = workspace:FindFirstChild("Gardens")
    if not ROOT then return nil end

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
    if not MY_PLOT_NAME then
        detectMyPlot()
    end
    return MY_PLOT_NAME
end

-- ============ CLEAR FUNCTIONS ============
local function deleteOtherPlots()
    if not DELETE_OTHER_PLOTS then return 0 end

    local ROOT = workspace:FindFirstChild("Gardens")
    if not ROOT then return 0 end

    local myPlotName = getMyPlot()
    if not myPlotName then
        return 0
    end

    local deleted = 0
    for _, plot in ipairs(ROOT:GetChildren()) do
        if plot.Name ~= myPlotName then
            pcall(function()
                plot:Destroy()
                deleted = deleted + 1
            end)
        end
    end
    return deleted
end

local function clearChildrenOf(path)
    local inst = resolvePath(path)
    if not inst then return 0 end

    local count = 0
    for _, child in ipairs(inst:GetChildren()) do
        pcall(function()
            child:Destroy()
            count = count + 1
        end)
    end
    return count
end

local function disableCollider(path)
    local inst = resolvePath(path)
    if not inst then return end

    if inst:IsA("BasePart") then
        pcall(function()
            inst.CanCollide = false
            inst.CanTouch = false
            inst.CanQuery = false
        end)
    end

    for _, d in ipairs(inst:GetDescendants()) do
        if d:IsA("BasePart") then
            pcall(function()
                d.CanCollide = false
                d.CanTouch = false
                d.CanQuery = false
            end)
        end
    end
end

-- ============ INITIAL CLEAR ============
local function runInitialClear()
    print("🧹 Clear map dimulai...")

    if DELETE_OTHER_PLOTS then
        local n = deleteOtherPlots()
        print("   • Plot lain dihapus:", n)
    end

    for _, path in ipairs(CLEAR_MAP.DELETE_CHILDREN) do
        local n = clearChildrenOf(path)
        print("   • Clear", path, ":", n, "child")
    end

    for _, path in ipairs(CLEAR_MAP.ALWAYS_CLEAR_CHILDREN) do
        local n = clearChildrenOf(path)
        print("   • Clear (init)", path, ":", n, "child")
    end

    for _, path in ipairs(CLEAR_MAP.DISABLE_COLLIDER) do
        disableCollider(path)
        print("   • Disable collider:", path)
    end

    print("✅ Clear map selesai (loop tetap jalan di background)")
end

-- ============ SHUTDOWN ============
local function shutdown(reason)
    if not ALIVE then return end
    ALIVE = false
    if reason then
        print("🛑 Clear Map dimatikan:", reason)
    end
end

-- ============ MAIN LOOP ============
task.spawn(function()
    local lastPlotCheck = 0
    local lastColliderCheck = 0
    local lastAlwaysClear = 0

    while ALIVE do
        task.wait(0.5)
        if not ALIVE then break end

        local now = tick()

        -- Always clear children
        if now - lastAlwaysClear >= ALWAYS_CLEAR_INTERVAL then
            lastAlwaysClear = now
            for _, path in ipairs(CLEAR_MAP.ALWAYS_CLEAR_CHILDREN) do
                clearChildrenOf(path)
            end
        end

        -- Re-check plot lain
        if now - lastPlotCheck >= PLOT_CHECK_INTERVAL then
            lastPlotCheck = now
            if DELETE_OTHER_PLOTS then
                local n = deleteOtherPlots()
                if n > 0 then
                    print("🧹 Plot lain dihapus lagi:", n)
                end
            end
        end

        -- Re-apply disable collider
        if now - lastColliderCheck >= COLLIDER_INTERVAL then
            lastColliderCheck = now
            for _, path in ipairs(CLEAR_MAP.DISABLE_COLLIDER) do
                disableCollider(path)
            end
        end
    end
    print("🛑 Clear Map loop berhenti")
end)

-- ============ CLEANUP HANDLER ============
Players.PlayerRemoving:Connect(function(p)
    if p == LocalPlayer then
        shutdown("Player keluar game")
    end
end)

-- ============ RUN ============
runInitialClear()

print("✅ Clear Map aktif — running di background")
print("   • Delete other plots:", DELETE_OTHER_PLOTS)
print("   • Always clear interval:", ALWAYS_CLEAR_INTERVAL .. "s")
print("   • Plot check interval:", PLOT_CHECK_INTERVAL .. "s")
print("   • Collider interval:", COLLIDER_INTERVAL .. "s")
