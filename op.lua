-- ============================================
-- ULTIMATE BOT OPTIMIZER v3 (FINAL)
-- Tanpa fog, hapus semua decal/texture
-- Gabungan: Clear Map + Extreme Nuke + Fix Plot
-- ============================================

local Players      = game:GetService("Players")
local Workspace    = game:GetService("Workspace")
local Lighting     = game:GetService("Lighting")
local SoundService = game:GetService("SoundService")

local LocalPlayer  = Players.LocalPlayer

-- ============================================
-- CONFIG
-- ============================================
local CONFIG = {
    -- ====== PROTEKSI ======
    ProtectBot        = true,
    ProtectMyPlot     = true,

    -- ====== CLEAR MAP ======
    DELETE_CHILDREN = {
        "Workspace.Map.Middle",
    },
    ALWAYS_CLEAR_CHILDREN = {
        "Workspace.Map.WildPetSpawns",
    },
    DISABLE_COLLIDER = {
        "Workspace.WitchCauldron",
    },
    DELETE_OTHER_PLOTS     = true,
    PLOT_CHECK_INTERVAL    = 1,     -- dari 5 jadi 1 detik
    ALWAYS_CLEAR_INTERVAL  = 1,
    COLLIDER_INTERVAL      = 2,
    DETECT_RETRY_INTERVAL  = 1,

    -- ====== VISUAL NUKE ======
    DestroyDecals      = true,
    DestroyTextures    = true,
    DestroyParticles   = true,
    DestroyTrails      = true,
    DestroyBeams       = true,
    DestroyLights      = true,
    DestroySounds      = true,
    DestroyHighlights  = true,
    DestroySmoke       = true,
    DestroyBillboards  = true,
    DestroySurfaceGui  = false,   -- false, biar plot detection tetap jalan

    -- ====== PART ======
    StripShadows       = true,
    FlattenMaterial    = true,
    StripReflectance   = true,

    -- ====== LIGHTING ======
    KillAllPostEffects = true,
    KillSky            = true,
    KillAtmosphere     = true,
    KillClouds         = true,
    KillTerrainDetail  = true,
    GlobalShadowsOff   = true,

    -- ====== FOG DIHAPUS TOTAL ======
    FogEnabled         = false,            -- ← TIDAK ADA FOG
    Ambient            = Color3.fromRGB(90, 90, 90),
    OutdoorAmbient     = Color3.fromRGB(90, 90, 90),
    Brightness         = 2,
    ClockTime          = 14,

    -- ====== AUTO-HAPUS PART JAUH (opsional) ======
    AutoDeleteFarParts = false,
    FarPartDistance    = 500,
    FarPartInterval    = 3,

    -- ====== RENDER ======
    LowerQuality       = true,
}

-- ============================================
-- STATE
-- ============================================
local ALIVE = true
local MY_PLOT_NAME = nil

-- ============================================
-- HELPER
-- ============================================
local function isBotOwned(obj)
    if not CONFIG.ProtectBot then return false end
    local char = LocalPlayer.Character
    if not char then return false end
    return obj:IsDescendantOf(char)
end

local function resolvePath(path)
    local parts = path:split(".")
    local current = game
    for _, part in ipairs(parts) do
        if not current then return nil end
        current = current:FindFirstChild(part)
    end
    return current
end

-- ============================================
-- PLOT DETECTION (4 METODE)
-- ============================================
local function detectMyPlot()
    local ROOT = Workspace:FindFirstChild("Gardens")
    if not ROOT then return nil end

    local candidates = {
        LocalPlayer.DisplayName .. "'s Garden",
        LocalPlayer.Name .. "'s Garden",
        LocalPlayer.DisplayName,
        LocalPlayer.Name,
    }

    for _, plot in ipairs(ROOT:GetChildren()) do
        -- Metode 1: via Signs
        local signs = plot:FindFirstChild("Signs")
        if signs then
            local garden = signs:FindFirstChild("Garden")
            local core = garden and garden:FindFirstChild("CorePart")
            local sg = core and core:FindFirstChild("SurfaceGui")
            if sg then
                for _, d in ipairs(sg:GetDescendants()) do
                    if d:IsA("TextLabel") then
                        for _, cand in ipairs(candidates) do
                            if d.Text == cand then
                                MY_PLOT_NAME = plot.Name
                                print("✅ Plot terdeteksi (Sign):", MY_PLOT_NAME)
                                return MY_PLOT_NAME
                            end
                        end
                    end
                end
            end
        end

        -- Metode 2: via Owner Value
        local owner = plot:FindFirstChild("Owner")
        if owner then
            local val = nil
            if owner:IsA("StringValue") then val = owner.Value
            elseif owner:IsA("ObjectValue") then val = owner.Value end
            if val == LocalPlayer or val == LocalPlayer.Name
               or val == LocalPlayer.DisplayName then
                MY_PLOT_NAME = plot.Name
                print("✅ Plot terdeteksi (Owner):", MY_PLOT_NAME)
                return MY_PLOT_NAME
            end
        end

        -- Metode 3: via Attribute
        local attrOwner = plot:GetAttribute("Owner")
        if attrOwner then
            if attrOwner == LocalPlayer.UserId
               or attrOwner == LocalPlayer.Name
               or attrOwner == LocalPlayer.DisplayName then
                MY_PLOT_NAME = plot.Name
                print("✅ Plot terdeteksi (Attribute):", MY_PLOT_NAME)
                return MY_PLOT_NAME
            end
        end

        -- Metode 4: nama plot mengandung nama player
        if plot.Name:find(LocalPlayer.Name)
           or plot.Name:find(LocalPlayer.DisplayName) then
            MY_PLOT_NAME = plot.Name
            print("✅ Plot terdeteksi (Nama):", MY_PLOT_NAME)
            return MY_PLOT_NAME
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

-- ============================================
-- VISUAL NUKE
-- ============================================
local function nukeObject(obj)
    if isBotOwned(obj) then return end

    -- Gambar (HAPUS SEMUA)
    if CONFIG.DestroyDecals and obj:IsA("Decal") then
        obj:Destroy() return
    end
    if CONFIG.DestroyTextures and obj:IsA("Texture") then
        obj:Destroy() return
    end

    -- Partikel
    if CONFIG.DestroyParticles and obj:IsA("ParticleEmitter") then
        obj:Destroy() return
    end
    if CONFIG.DestroySmoke and (obj:IsA("Smoke") or obj:IsA("Fire") or obj:IsA("Sparkles")) then
        obj:Destroy() return
    end

    -- Trail & Beam
    if CONFIG.DestroyTrails and obj:IsA("Trail") then
        obj:Destroy() return
    end
    if CONFIG.DestroyBeams and obj:IsA("Beam") then
        obj:Destroy() return
    end

    -- Cahaya
    if CONFIG.DestroyLights and (obj:IsA("PointLight") or obj:IsA("SpotLight") or obj:IsA("SurfaceLight")) then
        obj:Destroy() return
    end

    -- Suara
    if CONFIG.DestroySounds and obj:IsA("Sound") then
        obj:Destroy() return
    end

    -- Highlight
    if CONFIG.DestroyHighlights and obj:IsA("Highlight") then
        obj:Destroy() return
    end

    -- BillboardGui
    if CONFIG.DestroyBillboards and obj:IsA("BillboardGui") then
        obj:Destroy() return
    end

    -- SurfaceGui (opsional)
    if CONFIG.DestroySurfaceGui and obj:IsA("SurfaceGui") then
        obj:Destroy() return
    end

    -- Part
    if obj:IsA("BasePart") then
        if CONFIG.StripShadows then
            pcall(function() obj.CastShadow = false end)
        end
        if CONFIG.FlattenMaterial then
            pcall(function() obj.Material = Enum.Material.SmoothPlastic end)
        end
        if CONFIG.StripReflectance then
            pcall(function() obj.Reflectance = 0 end)
        end
    end
end

-- ============================================
-- LIGHTING (TANPA FOG)
-- ============================================
local function nukeLighting()
    for _, obj in ipairs(Lighting:GetChildren()) do
        if CONFIG.KillAllPostEffects and obj:IsA("PostEffect") then
            obj:Destroy()
        elseif CONFIG.KillSky and obj:IsA("Sky") then
            obj:Destroy()
        elseif CONFIG.KillAtmosphere and obj:IsA("Atmosphere") then
            obj:Destroy()
        elseif CONFIG.KillClouds and obj:IsA("Clouds") then
            obj:Destroy()
        end
    end

    pcall(function()
        if CONFIG.GlobalShadowsOff then
            Lighting.GlobalShadows = false
        end

        -- FOG DIHAPUS TOTAL
        Lighting.FogEnd   = 100000
        Lighting.FogStart = 100000
        Lighting.FogColor = Color3.fromRGB(255, 255, 255)

        Lighting.Ambient         = CONFIG.Ambient
        Lighting.OutdoorAmbient  = CONFIG.OutdoorAmbient
        Lighting.Brightness      = CONFIG.Brightness
        Lighting.ClockTime       = CONFIG.ClockTime
    end)
end

local function nukeTerrain()
    if not CONFIG.KillTerrainDetail then return end
    local terrain = Workspace:FindFirstChildOfClass("Terrain")
    if not terrain then return end
    pcall(function()
        terrain.Decoration = false
        terrain.WaterWaveSize = 0
        terrain.WaterWaveSpeed = 0
        terrain.WaterReflectance = 0
        terrain.WaterTransparency = 1
    end)
end

local function nukeSound()
    if not CONFIG.DestroySounds then return end
    for _, s in ipairs(SoundService:GetDescendants()) do
        if s:IsA("Sound") then
            pcall(function() s:Destroy() end)
        end
    end
    pcall(function() SoundService.AmbientReverb = Enum.ReverbType.NoReverb end)
end

-- ============================================
-- CLEAR MAP
-- ============================================
local function deleteOtherPlots()
    if not CONFIG.DELETE_OTHER_PLOTS then return 0 end
    local ROOT = Workspace:FindFirstChild("Gardens")
    if not ROOT then return 0 end

    local myPlotName = getMyPlot()
    if not myPlotName then return 0 end

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
-- AUTO-DELETE FAR PARTS
-- ============================================
local function deleteFarParts()
    if not CONFIG.AutoDeleteFarParts then return 0 end
    local char = LocalPlayer.Character
    if not char then return 0 end

    local pos = char:GetPivot().Position
    local deleted = 0

    for _, obj in ipairs(Workspace:GetDescendants()) do
        if obj:IsA("BasePart") and not isBotOwned(obj) then
            if (obj.Position - pos).Magnitude > CONFIG.FarPartDistance then
                pcall(function()
                    obj:Destroy()
                    deleted = deleted + 1
                end)
            end
        end
    end
    return deleted
end

-- ============================================
-- RENDER QUALITY
-- ============================================
local function lowerResolution()
    if not CONFIG.LowerQuality then return end
    pcall(function()
        settings().Rendering.QualityLevel = Enum.QualityLevel.Level01
    end)
    pcall(function()
        game:GetService("UserGameSettings").SavedQualityLevel =
            Enum.SavedQualitySetting.QualityLevel1
    end)
end

-- ============================================
-- INITIAL RUN
-- ============================================
local function runInitial()
    print("🧹 [ULTIMATE v3] Mulai optimasi...")
    local t0 = tick()

    -- Retry deteksi plot sampai 10x
    local tries = 0
    while not getMyPlot() and tries < 10 do
        tries = tries + 1
        print("   ⏳ Menunggu plot terdeteksi... (" .. tries .. "/10)")
        task.wait(1)
    end

    if not getMyPlot() then
        warn("⚠️ Plot sendiri tidak terdeteksi. Plot lain TIDAK dihapus (aman).")
    end

    -- Clear map
    if CONFIG.DELETE_OTHER_PLOTS and getMyPlot() then
        local n = deleteOtherPlots()
        print("   • Plot lain dihapus:", n)
    end
    for _, path in ipairs(CONFIG.DELETE_CHILDREN) do
        local n = clearChildrenOf(path)
        print("   • Clear", path, ":", n, "child")
    end
    for _, path in ipairs(CONFIG.ALWAYS_CLEAR_CHILDREN) do
        local n = clearChildrenOf(path)
        print("   • Clear (init)", path, ":", n, "child")
    end
    for _, path in ipairs(CONFIG.DISABLE_COLLIDER) do
        disableCollider(path)
    end

    -- Nuke visual
    local count = 0
    for _, obj in ipairs(Workspace:GetDescendants()) do
        local ok = pcall(nukeObject, obj)
        if ok then count += 1 end
    end
    print("   • Objek diproses:", count)

    nukeLighting()
    nukeTerrain()
    nukeSound()
    lowerResolution()

    print(string.format("✅ [ULTIMATE v3] Selesai dalam %.2fs", tick() - t0))
end

-- ============================================
-- WATCH OBJEK BARU
-- ============================================
local function watchNew()
    Workspace.DescendantAdded:Connect(function(obj)
        task.defer(function() pcall(nukeObject, obj) end)
    end)

    Lighting.DescendantAdded:Connect(function(obj)
        task.defer(function()
            if obj:IsA("PostEffect") or obj:IsA("Sky")
               or obj:IsA("Atmosphere") or obj:IsA("Clouds") then
                pcall(function() obj:Destroy() end)
            end
        end)
    end)

    SoundService.DescendantAdded:Connect(function(obj)
        if obj:IsA("Sound") and CONFIG.DestroySounds then
            task.defer(function() pcall(function() obj:Destroy() end) end)
        end
    end)
end

-- ============================================
-- WATCH PLOT BARU (INSTANT DELETE)
-- ============================================
local function watchNewPlots()
    local ROOT = Workspace:FindFirstChild("Gardens")
    if not ROOT then
        task.spawn(function()
            while ALIVE and not ROOT do
                task.wait(1)
                ROOT = Workspace:FindFirstChild("Gardens")
            end
            if ROOT then watchNewPlots() end
        end)
        return
    end

    ROOT.ChildAdded:Connect(function(plot)
        task.defer(function()
            local myPlotName = getMyPlot()
            if not myPlotName then return end
            if plot.Name ~= myPlotName then
                task.wait(0.2)
                pcall(function()
                    plot:Destroy()
                    print("⚡ Plot baru langsung dihapus:", plot.Name)
                end)
            end
        end)
    end)
end

-- ============================================
-- MAIN LOOP
-- ============================================
local function mainLoop()
    task.spawn(function()
        local lastPlotCheck     = 0
        local lastColliderCheck = 0
        local lastAlwaysClear   = 0
        local lastFarDelete     = 0
        local lastDetectRetry   = 0

        while ALIVE do
            task.wait(0.5)
            if not ALIVE then break end
            local now = tick()

            -- Retry deteksi plot
            if not MY_PLOT_NAME and now - lastDetectRetry >= CONFIG.DETECT_RETRY_INTERVAL then
                lastDetectRetry = now
                detectMyPlot()
            end

            -- Always clear children
            if now - lastAlwaysClear >= CONFIG.ALWAYS_CLEAR_INTERVAL then
                lastAlwaysClear = now
                for _, path in ipairs(CONFIG.ALWAYS_CLEAR_CHILDREN) do
                    clearChildrenOf(path)
                end
            end

            -- Plot lain
            if now - lastPlotCheck >= CONFIG.PLOT_CHECK_INTERVAL then
                lastPlotCheck = now
                if CONFIG.DELETE_OTHER_PLOTS then
                    local n = deleteOtherPlots()
                    if n > 0 then
                        print("🧹 Plot lain dihapus:", n)
                    end
                end
            end

            -- Collider
            if now - lastColliderCheck >= CONFIG.COLLIDER_INTERVAL then
                lastColliderCheck = now
                for _, path in ipairs(CONFIG.DISABLE_COLLIDER) do
                    disableCollider(path)
                end
            end

            -- Far parts
            if CONFIG.AutoDeleteFarParts
               and now - lastFarDelete >= CONFIG.FarPartInterval then
                lastFarDelete = now
                local n = deleteFarParts()
                if n > 0 then
                    print("🗑️ Part jauh dihapus:", n)
                end
            end
        end
        print("🛑 Main loop berhenti")
    end)
end

-- ============================================
-- SHUTDOWN
-- ============================================
local function shutdown(reason)
    if not ALIVE then return end
    ALIVE = false
    print("🛑 [ULTIMATE v3] Dimatikan:", reason or "-")
end

Players.PlayerRemoving:Connect(function(p)
    if p == LocalPlayer then
        shutdown("Player keluar")
    end
end)

-- ============================================
-- EXECUTE
-- ============================================
runInitial()
watchNew()
watchNewPlots()
mainLoop()

print("============================================")
print("✅ ULTIMATE OPTIMIZER v3 AKTIF")
print("   • Fog                : NONAKTIF (dihapus)")
print("   • Decal/Texture      : DIHAPUS SEMUA")
print("   • Delete other plots :", CONFIG.DELETE_OTHER_PLOTS)
print("   • Plot check interval:", CONFIG.PLOT_CHECK_INTERVAL .. "s")
print("   • Watch new plots    : AKTIF (instant delete)")
print("   • Auto-delete far    :", CONFIG.AutoDeleteFarParts)
print("============================================")
