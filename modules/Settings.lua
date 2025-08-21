-- Settings.lua
-- Game Performance & Server Management Module
-- Created: August 21, 2025

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer

-- ====================================================================
-- SETTINGS MODULE
-- ====================================================================

local Settings = {}

-- ====================================================================
-- CONFIGURATION
-- ====================================================================
Settings.config = {
    boostFPS = false,
    hdrShader = false,
    originalSettings = {},
    serverHopEnabled = true,
    preferredPlayerCount = 10 -- For "Server Small" feature
}

-- ====================================================================
-- FPS BOOST SYSTEM
-- ====================================================================

-- Store original graphics settings
local function StoreOriginalSettings()
    if next(Settings.config.originalSettings) == nil then
        Settings.config.originalSettings = {
            -- Lighting settings
            Technology = Lighting.Technology,
            Brightness = Lighting.Brightness,
            GlobalShadows = Lighting.GlobalShadows,
            ShadowSoftness = Lighting.ShadowSoftness,
            EnvironmentDiffuseScale = Lighting.EnvironmentDiffuseScale,
            EnvironmentSpecularScale = Lighting.EnvironmentSpecularScale,
            
            -- Workspace settings
            StreamingEnabled = Workspace.StreamingEnabled,
            
            -- Render settings
            QualityLevel = settings().Rendering.QualityLevel,
            
            -- Terrain details
            TerrainWaterWaveSize = if Workspace.Terrain then Workspace.Terrain.WaterWaveSize else 0.05,
            TerrainWaterWaveSpeed = if Workspace.Terrain then Workspace.Terrain.WaterWaveSpeed else 10,
            TerrainWaterTransparency = if Workspace.Terrain then Workspace.Terrain.WaterTransparency else 0.3
        }
        print("[Settings] Original graphics settings stored")
    end
end

-- Apply FPS boost settings
function Settings.EnableFPSBoost()
    StoreOriginalSettings()
    
    -- Reduce lighting quality
    Lighting.Technology = Enum.Technology.Compatibility
    Lighting.GlobalShadows = false
    Lighting.ShadowSoftness = 0
    Lighting.EnvironmentDiffuseScale = 0
    Lighting.EnvironmentSpecularScale = 0
    
    -- Reduce render quality
    settings().Rendering.QualityLevel = Enum.QualityLevel.Level01
    
    -- Optimize terrain
    if Workspace.Terrain then
        Workspace.Terrain.WaterWaveSize = 0
        Workspace.Terrain.WaterWaveSpeed = 0
        Workspace.Terrain.WaterTransparency = 1
    end
    
    -- Remove unnecessary effects
    for _, obj in pairs(Workspace:GetDescendants()) do
        if obj:IsA("ParticleEmitter") or obj:IsA("Fire") or obj:IsA("Smoke") or obj:IsA("Sparkles") then
            obj.Enabled = false
        elseif obj:IsA("PointLight") or obj:IsA("SpotLight") or obj:IsA("SurfaceLight") then
            obj.Enabled = false
        elseif obj:IsA("BloomEffect") or obj:IsA("BlurEffect") or obj:IsA("ColorCorrectionEffect") then
            obj.Enabled = false
        end
    end
    
    Settings.config.boostFPS = true
    print("[Settings] ⚡ FPS Boost enabled - Graphics quality reduced for better performance")
    return true
end

-- Restore original graphics settings
function Settings.DisableFPSBoost()
    if next(Settings.config.originalSettings) == nil then
        print("[Settings] ⚠️ No original settings to restore")
        return false
    end
    
    -- Restore lighting
    Lighting.Technology = Settings.config.originalSettings.Technology
    Lighting.Brightness = Settings.config.originalSettings.Brightness
    Lighting.GlobalShadows = Settings.config.originalSettings.GlobalShadows
    Lighting.ShadowSoftness = Settings.config.originalSettings.ShadowSoftness
    Lighting.EnvironmentDiffuseScale = Settings.config.originalSettings.EnvironmentDiffuseScale
    Lighting.EnvironmentSpecularScale = Settings.config.originalSettings.EnvironmentSpecularScale
    
    -- Restore render quality
    settings().Rendering.QualityLevel = Settings.config.originalSettings.QualityLevel
    
    -- Restore terrain
    if Workspace.Terrain then
        Workspace.Terrain.WaterWaveSize = Settings.config.originalSettings.TerrainWaterWaveSize
        Workspace.Terrain.WaterWaveSpeed = Settings.config.originalSettings.TerrainWaterWaveSpeed
        Workspace.Terrain.WaterTransparency = Settings.config.originalSettings.TerrainWaterTransparency
    end
    
    Settings.config.boostFPS = false
    print("[Settings] ✨ FPS Boost disabled - Graphics quality restored")
    return true
end

-- ====================================================================
-- HDR SHADER SYSTEM
-- ====================================================================

-- Enable HDR visual effects
function Settings.EnableHDRShader()
    -- Create HDR effects
    local hdrFolder = Instance.new("Folder", Lighting)
    hdrFolder.Name = "HDREffects"
    
    -- Bloom effect for HDR
    local bloom = Instance.new("BloomEffect", hdrFolder)
    bloom.Intensity = 2
    bloom.Size = 32
    bloom.Threshold = 0.8
    
    -- Color correction for HDR
    local colorCorrection = Instance.new("ColorCorrectionEffect", hdrFolder)
    colorCorrection.Brightness = 0.1
    colorCorrection.Contrast = 0.3
    colorCorrection.Saturation = 0.2
    colorCorrection.TintColor = Color3.fromRGB(255, 245, 225)
    
    -- Sunrays effect
    local sunRays = Instance.new("SunRaysEffect", hdrFolder)
    sunRays.Intensity = 0.25
    sunRays.Spread = 0.2
    
    -- Enhanced lighting
    Lighting.Technology = Enum.Technology.Future
    Lighting.Brightness = 2.5
    Lighting.EnvironmentDiffuseScale = 1
    Lighting.EnvironmentSpecularScale = 1
    Lighting.GlobalShadows = true
    Lighting.ShadowSoftness = 0.5
    
    Settings.config.hdrShader = true
    print("[Settings] 🌈 HDR Shader enabled - Enhanced visual effects applied")
    return true
end

-- Disable HDR effects
function Settings.DisableHDRShader()
    -- Remove HDR effects
    local hdrFolder = Lighting:FindFirstChild("HDREffects")
    if hdrFolder then
        hdrFolder:Destroy()
    end
    
    -- Restore normal lighting if original settings exist
    if next(Settings.config.originalSettings) ~= nil then
        Lighting.Technology = Settings.config.originalSettings.Technology
        Lighting.Brightness = Settings.config.originalSettings.Brightness
        Lighting.EnvironmentDiffuseScale = Settings.config.originalSettings.EnvironmentDiffuseScale
        Lighting.EnvironmentSpecularScale = Settings.config.originalSettings.EnvironmentSpecularScale
        Lighting.GlobalShadows = Settings.config.originalSettings.GlobalShadows
        Lighting.ShadowSoftness = Settings.config.originalSettings.ShadowSoftness
    end
    
    Settings.config.hdrShader = false
    print("[Settings] 🔄 HDR Shader disabled - Normal lighting restored")
    return true
end

-- ====================================================================
-- SERVER MANAGEMENT SYSTEM
-- ====================================================================

-- Rejoin current server
function Settings.RejoinServer()
    print("[Settings] 🔄 Rejoining current server...")
    TeleportService:Teleport(game.PlaceId, LocalPlayer)
    return true
end

-- Server hop to different server
function Settings.ServerHop()
    if not Settings.config.serverHopEnabled then
        print("[Settings] ❌ Server hop is disabled")
        return false
    end
    
    print("[Settings] 🏃 Hopping to different server...")
    
    local success, result = pcall(function()
        local servers = TeleportService:GetServers(game.PlaceId, "", 100)
        local availableServers = {}
        
        for _, server in pairs(servers) do
            if server.Playing < server.MaxPlayers and server.Id ~= game.JobId then
                table.insert(availableServers, server)
            end
        end
        
        if #availableServers > 0 then
            local randomServer = availableServers[math.random(1, #availableServers)]
            TeleportService:TeleportToPlaceInstance(game.PlaceId, randomServer.Id, LocalPlayer)
            return true
        else
            print("[Settings] ⚠️ No available servers found")
            return false
        end
    end)
    
    if not success then
        print("[Settings] ❌ Server hop failed:", result)
        -- Fallback to regular teleport
        TeleportService:Teleport(game.PlaceId, LocalPlayer)
    end
    
    return success
end

-- Find server with fewer players
function Settings.ServerSmall()
    print("[Settings] 🔍 Finding server with fewer players...")
    
    local success, result = pcall(function()
        local servers = TeleportService:GetServers(game.PlaceId, "", 100)
        local smallServers = {}
        
        for _, server in pairs(servers) do
            if server.Playing <= Settings.config.preferredPlayerCount and 
               server.Playing > 0 and 
               server.Id ~= game.JobId then
                table.insert(smallServers, {
                    server = server,
                    playerCount = server.Playing
                })
            end
        end
        
        if #smallServers > 0 then
            -- Sort by player count (ascending)
            table.sort(smallServers, function(a, b) 
                return a.playerCount < b.playerCount 
            end)
            
            local targetServer = smallServers[1].server
            print("[Settings] 📍 Found small server with", targetServer.Playing, "players")
            TeleportService:TeleportToPlaceInstance(game.PlaceId, targetServer.Id, LocalPlayer)
            return true
        else
            print("[Settings] ⚠️ No small servers found, using regular server hop")
            return Settings.ServerHop()
        end
    end)
    
    if not success then
        print("[Settings] ❌ Server small search failed:", result)
        return Settings.ServerHop()
    end
    
    return success
end

-- ====================================================================
-- UTILITY FUNCTIONS
-- ====================================================================

-- Get current FPS
function Settings.GetCurrentFPS()
    local lastTime = tick()
    local frameCount = 0
    
    local connection
    connection = RunService.Heartbeat:Connect(function()
        frameCount = frameCount + 1
        local currentTime = tick()
        
        if currentTime - lastTime >= 1 then
            local fps = frameCount / (currentTime - lastTime)
            connection:Disconnect()
            return math.floor(fps)
        end
    end)
end

-- Get server info
function Settings.GetServerInfo()
    return {
        players = #Players:GetPlayers(),
        maxPlayers = Players.MaxPlayers,
        jobId = game.JobId,
        placeId = game.PlaceId,
        ping = LocalPlayer:GetNetworkPing() * 1000
    }
end

-- Toggle FPS boost
function Settings.ToggleFPSBoost()
    if Settings.config.boostFPS then
        return Settings.DisableFPSBoost()
    else
        return Settings.EnableFPSBoost()
    end
end

-- Toggle HDR shader
function Settings.ToggleHDRShader()
    if Settings.config.hdrShader then
        return Settings.DisableHDRShader()
    else
        return Settings.EnableHDRShader()
    end
end

-- ====================================================================
-- STATUS FUNCTIONS
-- ====================================================================

-- Get current settings status
function Settings.GetStatus()
    local serverInfo = Settings.GetServerInfo()
    
    return {
        fpsBoost = Settings.config.boostFPS,
        hdrShader = Settings.config.hdrShader,
        serverInfo = serverInfo,
        hasOriginalSettings = next(Settings.config.originalSettings) ~= nil
    }
end

-- Export current configuration
function Settings.ExportConfig()
    return {
        config = Settings.config,
        serverInfo = Settings.GetServerInfo(),
        timestamp = tick()
    }
end

-- ====================================================================
-- INITIALIZATION
-- ====================================================================
function Settings.Initialize()
    print("[Settings] ⚙️ Settings module initialized successfully")
    print("[Settings] 🎮 Game performance and server management ready")
    
    -- Store original settings on initialization
    StoreOriginalSettings()
    
    return true
end

-- ====================================================================
-- MODULE EXPORT
-- ====================================================================
return Settings
