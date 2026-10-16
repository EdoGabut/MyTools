-- ============================================
-- GAME OPTIMIZER — Bikin Ringan
-- Target: FPS boost, RAM turun, GPU less load
-- ============================================

local CoreGui = game:GetService("CoreGui")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer

-- ============ CONFIG ============

local CONFIG = {
    -- Visual
    DISABLE_SHADOWS   = true,   -- Matikan shadow (GPU)
    DISABLE_FOG       = true,   -- Matikan fog
    DISABLE_BLOOM     = true,   -- Matikan bloom
    DISABLE_BLUR      = true,   -- Matikan blur
    DISABLE_SUNRAYS   = true,   -- Matikan sun rays
    DISABLE_ATMOS     = true,   -- Matikan atmosphere
    
    -- Objects
    DISABLE_PARTICLES = true,   -- Matikan particle emitters
    DISABLE_BEAMS     = true,   -- Matikan beams
    DISABLE_TRAILS    = true,   -- Matikan trails
    DISABLE_DECALS    = false,  -- Decal (hati-hati, visual game bisa rusak)
    DISABLE_TEXTURES  = false,  -- Texture (hati-hati)
    
    -- Terrain
    DISABLE_TERRAIN   = true,   -- Sembunyikan terrain (kalau ada)
    
    -- Audio
    DISABLE_SOUNDS    = false,  -- Matikan semua suara (kecuali penting)
    
    -- Performance
    FPS_CAP           = 120,    -- Cap FPS
    RENDER_DISTANCE   = 500,    -- Batasi render distance (stud)
}

-- ============ STORAGE ============

local originals = {
    lighting = {},
    effects = {},     -- [effect] = {class, original}
    particles = {},   -- [particle] = {original}
    decals = {},      -- [decal] = {original transparency}
    sounds = {},      -- [sound] = {original volume}
    terrain = nil,
}

-- ============ LIGHTING OPTIMIZATION ============

local function optimizeLighting()
    if CONFIG.DISABLE_SHADOWS then
        originals.lighting.GlobalShadows = Lighting.GlobalShadows
        Lighting.GlobalShadows = false
    end

    if CONFIG.DISABLE_FOG then
        originals.lighting.FogEnd = Lighting.FogEnd
        originals.lighting.FogStart = Lighting.FogStart
        Lighting.FogEnd = 100000
        Lighting.FogStart = 100000
    end

    -- Hapus efek post-processing
    for _, effect in ipairs(Lighting:GetChildren()) do
        if effect:IsA("BloomEffect") and CONFIG.DISABLE_BLOOM then
            table.insert(originals.effects, {effect = effect, class = effect.ClassName})
            effect.Enabled = false
        elseif effect:IsA("BlurEffect") and CONFIG.DISABLE_BLUR then
            table.insert(originals.effects, {effect = effect, class = effect.ClassName})
            effect.Enabled = false
        elseif effect:IsA("SunRaysEffect") and CONFIG.DISABLE_SUNRAYS then
            table.insert(originals.effects, {effect = effect, class = effect.ClassName})
            effect.Enabled = false
        elseif effect:IsA("Atmosphere") and CONFIG.DISABLE_ATMOS then
            table.insert(originals.effects, {effect = effect, class = effect.ClassName})
            effect.Density = 0
        elseif effect:IsA("ColorCorrectionEffect") then
            -- Keep color correction
        end
    end

    -- Hapus effect baru yang muncul
    Lighting.ChildAdded:Connect(function(child)
        task.wait(0.1)
        if child:IsA("BloomEffect") and CONFIG.DISABLE_BLOOM then
            child.Enabled = false
        elseif child:IsA("BlurEffect") and CONFIG.DISABLE_BLUR then
            child.Enabled = false
        elseif child:IsA("SunRaysEffect") and CONFIG.DISABLE_SUNRAYS then
            child.Enabled = false
        elseif child:IsA("Atmosphere") and CONFIG.DISABLE_ATMOS then
            child.Density = 0
        end
    end)
end

-- ============ WORKSPACE OPTIMIZATION ============

local function optimizeWorkspace()
    -- Terrain
    if CONFIG.DISABLE_TERRAIN then
        local terrain = Workspace:FindFirstChildOfClass("Terrain")
        if terrain then
            originals.terrain = terrain
            terrain.WaterWaveSize = 0
            terrain.WaterWaveSpeed = 0
            terrain.WaterReflectance = 0
            terrain.WaterTransparency = 1
            terrain.Decoration = false
        end
    end

    -- Particles, beams, trails
    local function scanObject(obj)
        if obj:IsA("ParticleEmitter") and CONFIG.DISABLE_PARTICLES then
            table.insert(originals.particles, {p = obj, enabled = obj.Enabled})
            obj.Enabled = false
        elseif obj:IsA("Beam") and CONFIG.DISABLE_BEAMS then
            table.insert(originals.particles, {p = obj, enabled = obj.Enabled})
            obj.Enabled = false
        elseif obj:IsA("Trail") and CONFIG.DISABLE_TRAILS then
            table.insert(originals.particles, {p = obj, enabled = obj.Enabled})
            obj.Enabled = false
        elseif (obj:IsA("Decal") or obj:IsA("Texture")) and CONFIG.DISABLE_DECALS then
            table.insert(originals.decals, {d = obj, transparency = obj.Transparency})
            obj.Transparency = 1
        elseif obj:IsA("Sound") and CONFIG.DISABLE_SOUNDS then
            if obj.SoundId ~= "" then
                table.insert(originals.sounds, {s = obj, volume = obj.Volume})
                obj.Volume = 0
            end
        end
    end

    for _, obj in ipairs(Workspace:GetDescendants()) do
        scanObject(obj)
    end

    -- Handle object baru
    Workspace.DescendantAdded:Connect(function(obj)
        task.wait(0.05)
        scanObject(obj)
    end)
end

-- ============ FPS OPTIMIZATION ============

local function optimizeFPS()
    if CONFIG.FPS_CAP then
        pcall(function()
            setfpscap(CONFIG.FPS_CAP)
        end)
    end
end

-- ============ RENDER DISTANCE ============

local function limitRenderDistance()
    if not CONFIG.RENDER_DISTANCE then return end
    
    -- Cek Camera
    local camera = Workspace.CurrentCamera
    if not camera then return end
    
    -- Set Focus
    pcall(function()
        camera.Focus = camera.CFrame
    end)
    
    -- Loop: hapus objek jauh dari camera (visual only)
    task.spawn(function()
        while task.wait(1) do
            local camPos = camera.CFrame.Position
            for _, obj in ipairs(Workspace:GetChildren()) do
                if obj:IsA("Model") or obj:IsA("BasePart") then
                    local pos = obj:GetPivot().Position
                    local dist = (pos - camPos).Magnitude
                    
                    if dist > CONFIG.RENDER_DISTANCE then
                        if not obj:GetAttribute("_OptimizerHidden") then
                            obj:SetAttribute("_OptimizerHidden", true)
                            -- Hati-hati: jangan hapus, cuma hide
                        end
                    end
                end
            end
        end
    end)
end

-- ============ APPLY ============

optimizeLighting()
optimizeWorkspace()
optimizeFPS()
-- limitRenderDistance()  -- optional, hati-hati

print("")
print("⚡ ═══════════════════════════════════════")
print("⚡ GAME OPTIMIZER LOADED")
print("⚡ ═══════════════════════════════════════")
print(string.format("🌑 Shadows: %s", CONFIG.DISABLE_SHADOWS and "OFF" or "ON"))
print(string.format("🌫️  Fog: %s", CONFIG.DISABLE_FOG and "OFF" or "ON"))
print(string.format("✨ Bloom: %s", CONFIG.DISABLE_BLOOM and "OFF" or "ON"))
print(string.format("🌫️  Blur: %s", CONFIG.DISABLE_BLUR and "OFF" or "ON"))
print(string.format("☀️  SunRays: %s", CONFIG.DISABLE_SUNRAYS and "OFF" or "ON"))
print(string.format("🌌 Atmosphere: %s", CONFIG.DISABLE_ATMOS and "OFF" or "ON"))
print(string.format("💥 Particles: %s", CONFIG.DISABLE_PARTICLES and "OFF" or "ON"))
print(string.format("🔦 Beams: %s", CONFIG.DISABLE_BEAMS and "OFF" or "ON"))
print(string.format("🌊 Trails: %s", CONFIG.DISABLE_TRAILS and "OFF" or "ON"))
print(string.format("🎯 FPS cap: %d", CONFIG.FPS_CAP))
print("⚡ ═══════════════════════════════════════")
print("")

-- ============ RESTORE FUNCTION (Manual) ============

_G.RestoreOptimizer = function()
    print("🔄 Restoring...")

    -- Restore lighting
    if originals.lighting.GlobalShadows ~= nil then
        Lighting.GlobalShadows = originals.lighting.GlobalShadows
    end
    if originals.lighting.FogEnd then
        Lighting.FogEnd = originals.lighting.FogEnd
        Lighting.FogStart = originals.lighting.FogStart
    end

    -- Restore effects
    for _, data in ipairs(originals.effects) do
        if data.effect and data.effect.Parent then
            if data.class == "Atmosphere" then
                data.effect.Density = 0.3
            else
                data.effect.Enabled = true
            end
        end
    end

    -- Restore particles
    for _, data in ipairs(originals.particles) do
        if data.p and data.p.Parent then
            data.p.Enabled = data.enabled
        end
    end

    -- Restore decals
    for _, data in ipairs(originals.decals) do
        if data.d and data.d.Parent then
            data.d.Transparency = data.transparency
        end
    end

    -- Restore sounds
    for _, data in ipairs(originals.sounds) do
        if data.s and data.s.Parent then
            data.s.Volume = data.volume
        end
    end

    -- Clear
    originals.effects = {}
    originals.particles = {}
    originals.decals = {}
    originals.sounds = {}

    print("✅ Restored")
end

print("💡 Ketik _G.RestoreOptimizer() di console buat restore")
