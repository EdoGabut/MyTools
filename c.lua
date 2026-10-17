-- ============================================
-- CLEANER UTILITY (ALL-IN-ONE)
-- Optimasi + Nuke + Clear Map
-- Tanpa GUI, langsung jalan saat execute
-- ============================================
-- FITUR:
--   🗑️  Hapus object spesifik (Stands, NPCS, dll)
--   🗺️  Hapus plot lain (selain plot sendiri)
--   🧹  Clear Map.Middle
--   📦  Always clear WildPetSpawns (loop 1s)
--   🔓  Disable collider WitchCauldron (loop 2s)
--   🖼️  Nuke Decal & Texture
--   💥  Kill ParticleEmitter / Trail / Beam
--   🌑  Remove shadows
--   ✨  Smooth material
-- ============================================

local Players   = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer

-- ============================================
-- CONFIG
-- ============================================
local CONFIG = {
    ProtectBot      = true,   -- jangan sentuh karakter sendiri

    -- Nuke
    NukeDecals      = true,
    NukeTextures    = true,

    -- Effect killer
    KillParticles   = true,
    KillTrails      = true,
    KillBeams       = true,
    RemoveShadows   = true,
    SmoothMaterial  = true,

    -- Clear map
    DELETE_OTHER_PLOTS    = true,
    PLOT_CHECK_INTERVAL   = 5,
    ALWAYS_CLEAR_INTERVAL = 1,
    COLLIDER_INTERVAL     = 2,

    -- Hapus sekali di awal
    DELETE_CHILDREN = {
        "Workspace.Map.Middle",
    },

    -- Hapus terus-menerus (loop)
    ALWAYS_CLEAR_CHILDREN = {
        "Workspace.Map.WildPetSpawns",
    },

    -- Matikan collider (re-apply tiap 2s)
    DISABLE_COLLIDER = {
        "Workspace.WitchCauldron",
    },

    -- Hapus total object (sekali + watch)
    NUKE_OBJECTS = {
        "Workspace.Map.Stands",
        "Workspace.NPCS",
        "Workspace.WitchCauldron",
        "Workspace.ExplorerStand",
        "Workspace.AuctionStand",
    },

    -- Material yang dipertahankan (tidak di-Smooth)
    KEEP_MATERIALS = {
        [Enum.Material.Neon]        = true,
        [Enum.Material.ForceField]  = true,
    },
}

-- ============================================
-- STATE
-- ============================================
local ALIVE = true
local MY_PLOT_NAME = nil

local stats = {
    particles = 0,
    trails    = 0,
    beams     = 0,
    shadows   = 0,
    materials = 0,
    decals    = 0,
    textures  = 0,
    nuked     = 0,
    plots     = 0,
    cleared   = 0,
}

-- ============================================
-- HELPERS
-- ============================================
local function resolvePath(path)
    local parts = path:split(".")
    local current = game
    for _, part in ipairs(parts) do
        if not current then return nil end
        if part == "Workspace" then
            current = workspace
        else
            current = current:FindFirstChild(part)
        end
    end
    return current
end

local function isBotOwned(obj)
    if not CONFIG.ProtectBot then return false end
    local char = LocalPlayer.Character
    if not char then return true end  -- kalau char nil, anggap milik bot (aman)
    return obj:IsDescendantOf(char)
end

-- ============================================
-- PLOT DETECTION
-- ============================================
local function detectMyPlot()
    local ROOT = workspace:FindFirstChild("Gardens")
    if not ROOT then return nil end
    local mySign = LocalPlayer.DisplayName .. "'s Garden"
    for _, plot in ipairs(ROOT:GetChildren()) do
        local signs = plot:FindFirstChild("Signs")
        if signs then
            local garden = signs:FindFirstChild("Garden")
            local core   = garden and garden:FindFirstChild("CorePart")
            local sg     = core and core:FindFirstChild("SurfaceGui")
            local playerLbl = sg and sg:FindFirstChild("Player")
            local textLbl   = playerLbl and playerLbl:FindFirstChild("TextLabel")
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
    if not MY_PLOT_NAME then detectMyPlot() end
    return MY_PLOT_NAME
end

detectMyPlot()

-- ============================================
-- OPTIMIZE OBJECT (per objek)
-- ============================================
local function optimizeObject(obj)
    if isBotOwned(obj) then return end

    -- Nuke decal/texture
    if CONFIG.NukeDecals and obj:IsA("Decal") then
        obj:Destroy()
        stats.decals += 1
        return
    end
    if CONFIG.NukeTextures and obj:IsA("Texture") then
        obj:Destroy()
        stats.textures += 1
        return
    end

    -- Kill particles
    if CONFIG.KillParticles and obj:IsA("ParticleEmitter") then
        obj:Destroy()
        stats.particles += 1
        return
    end

    -- Kill trails
    if CONFIG.KillTrails and obj:IsA("Trail") then
        obj:Destroy()
        stats.trails += 1
        return
    end

    -- Kill beams
    if CONFIG.KillBeams and obj:IsA("Beam") then
        obj:Destroy()
        stats.beams += 1
        return
    end

    -- BasePart: shadow + material
    if obj:IsA("BasePart") then
        if CONFIG.RemoveShadows and obj.CastShadow then
            pcall(function()
                obj.CastShadow = false
                stats.shadows += 1
            end)
        end
        if CONFIG.SmoothMaterial
            and obj.Material ~= Enum.Material.SmoothPlastic
            and not CONFIG.KEEP_MATERIALS[obj.Material] then
            pcall(function()
                obj.Material = Enum.Material.SmoothPlastic
                stats.materials += 1
            end)
        end
    end
end

-- ============================================
-- NUKE OBJECTS (hapus folder/stand total)
-- ============================================
local function nukeObjects()
    for _, path in ipairs(CONFIG.NUKE_OBJECTS) do
        local inst = resolvePath(path)
        if inst then
            local name = inst.Name
            pcall(function()
                inst:Destroy()
                stats.nuked += 1
                print("   🗑️  Nuked:", name)
            end)
        end
    end
end

-- ============================================
-- CLEAR CHILDREN
-- ============================================
local function clearChildrenOf(path)
    local inst = resolvePath(path)
    if not inst then return 0 end
    local children = inst:GetChildren()
    if #children == 0 then return 0 end
    local count = 0
    for _, child in ipairs(children) do
        pcall(function()
            child:Destroy()
            count += 1
        end)
    end
    stats.cleared += count
    return count
end

-- ============================================
-- DISABLE COLLIDER
-- ============================================
local function disableCollider(path)
    local inst = resolvePath(path)
    if not inst then return end
    if inst:IsA("BasePart") then
        pcall(function()
            inst.CanCollide = false
            inst.CanTouch   = false
            inst.CanQuery   = false
        end)
    end
    for _, d in ipairs(inst:GetDescendants()) do
        if d:IsA("BasePart") then
            pcall(function()
                d.CanCollide = false
                d.CanTouch   = false
                d.CanQuery   = false
            end)
        end
    end
end

-- ============================================
-- DELETE OTHER PLOTS
-- ============================================
local function deleteOtherPlots()
    if not CONFIG.DELETE_OTHER_PLOTS then return 0 end
    local ROOT = workspace:FindFirstChild("Gardens")
    if not ROOT then return 0 end
    local myPlotName = getMyPlot()
    if not myPlotName then return 0 end
    local deleted = 0
    for _, plot in ipairs(ROOT:GetChildren()) do
        if plot.Name ~= myPlotName then
            pcall(function()
                plot:Destroy()
                deleted += 1
            end)
        end
    end
    stats.plots += deleted
    return deleted
end

-- ============================================
-- INITIAL SCAN (sekali jalan)
-- ============================================
local function runInitialClear()
    print("🧹 Cleaner Utility dimulai...")
    local t0 = os.clock()

    -- 1. Nuke object spesifik
    if #CONFIG.NUKE_OBJECTS > 0 then
        print("   🗑️  Nuke objects...")
        nukeObjects()
    end

    -- 2. Delete other plots
    if CONFIG.DELETE_OTHER_PLOTS then
        local n = deleteOtherPlots()
        print("   • Plot lain dihapus:", n)
    end

    -- 3. Clear children (sekali)
    for _, path in ipairs(CONFIG.DELETE_CHILDREN) do
        local n = clearChildrenOf(path)
        print("   • Clear", path, ":", n, "child")
    end

    -- 4. Clear children (init, akan di-loop lagi)
    for _, path in ipairs(CONFIG.ALWAYS_CLEAR_CHILDREN) do
        local n = clearChildrenOf(path)
        print("   • Clear (init)", path, ":", n, "child")
    end

    -- 5. Disable collider (init)
    for _, path in ipairs(CONFIG.DISABLE_COLLIDER) do
        disableCollider(path)
        print("   • Disable collider:", path)
    end

    -- 6. Scan + optimize semua descendant Workspace
    print("   🔍 Scan & optimize Workspace...")
    for _, obj in ipairs(Workspace:GetDescendants()) do
        pcall(optimizeObject, obj)
    end

    local elapsed = os.clock() - t0
    print(string.format("✅ Initial scan selesai dalam %.2fs", elapsed))
    print("   • Decal dihapus     :", stats.decals)
    print("   • Texture dihapus   :", stats.textures)
    print("   • Particle dihapus  :", stats.particles)
    print("   • Trail dihapus     :", stats.trails)
    print("   • Beam dihapus      :", stats.beams)
    print("   • Shadow dimatikan  :", stats.shadows)
    print("   • Material di-Smooth:", stats.materials)
    print("   • Object di-nuke    :", stats.nuked)
    print("   • Plot lain dihapus :", stats.plots)
    print("   • Child di-clear    :", stats.cleared)
end

-- ============================================
-- SHUTDOWN
-- ============================================
local function shutdown(reason)
    if not ALIVE then return end
    ALIVE = false
    if reason then
        print("🛑 Cleaner Utility dimatikan:", reason)
    end
end

-- ============================================
-- WATCH: object baru langsung diproses
-- ============================================
Workspace.DescendantAdded:Connect(function(obj)
    if not ALIVE then return end
    task.defer(function()
        if not ALIVE then return end
        pcall(optimizeObject, obj)
        -- Kalau objek baru adalah bagian dari NUKE_OBJECTS, langsung hapus parent-nya
        for _, path in ipairs(CONFIG.NUKE_OBJECTS) do
            local target = resolvePath(path)
            if target and obj:IsDescendantOf(target) then
                pcall(function()
                    target:Destroy()
                    stats.nuked += 1
                    print("   🗑️  Re-nuked:", target.Name)
                end)
                break
            end
        end
    end)
end)

-- ============================================
-- MAIN LOOP
-- ============================================
task.spawn(function()
    local lastPlotCheck     = 0
    local lastColliderCheck = 0
    local lastAlwaysClear   = 0

    while ALIVE do
        task.wait(0.5)
        if not ALIVE then break end

        local now = os.clock()

        -- Always clear children
        if now - lastAlwaysClear >= CONFIG.ALWAYS_CLEAR_INTERVAL then
            lastAlwaysClear = now
            for _, path in ipairs(CONFIG.ALWAYS_CLEAR_CHILDREN) do
                clearChildrenOf(path)
            end
        end

        -- Re-check plot lain
        if now - lastPlotCheck >= CONFIG.PLOT_CHECK_INTERVAL then
            lastPlotCheck = now
            if CONFIG.DELETE_OTHER_PLOTS then
                local n = deleteOtherPlots()
                if n > 0 then
                    print("🧹 Plot lain dihapus lagi:", n)
                end
            end
        end

        -- Re-apply disable collider
        if now - lastColliderCheck >= CONFIG.COLLIDER_INTERVAL then
            lastColliderCheck = now
            for _, path in ipairs(CONFIG.DISABLE_COLLIDER) do
                disableCollider(path)
            end
        end

        -- Re-nuke object spesifik (kalau respawn)
        for _, path in ipairs(CONFIG.NUKE_OBJECTS) do
            local inst = resolvePath(path)
            if inst then
                pcall(function()
                    inst:Destroy()
                    stats.nuked += 1
                    print("   🗑️  Re-nuked:", path)
                end)
            end
        end
    end
    print("🛑 Cleaner Utility loop berhenti")
end)

-- ============================================
-- CLEANUP HANDLER
-- ============================================
Players.PlayerRemoving:Connect(function(p)
    if p == LocalPlayer then
        shutdown("Player keluar game")
    end
end)

-- ============================================
-- RUN
-- ============================================
runInitialClear()
