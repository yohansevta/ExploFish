-- ExploFish Minimal Loader
-- Test version untuk debugging loading issues

print("🎣 [ExploFish] Starting minimal loader...")

-- Basic services test
local function getService(name)
    local success, service = pcall(function()
        return game:GetService(name)
    end)
    if success then
        print("✅ [Service]", name, "available")
        return service
    else
        warn("❌ [Service]", name, "failed:", service)
        return nil
    end
end

local Players = getService("Players")
local RunService = getService("RunService")
local HttpService = getService("HttpService")

if not Players or not RunService then
    error("❌ [ExploFish] Critical services missing!")
end

-- Enable HTTP
if HttpService then
    pcall(function()
        HttpService.HttpEnabled = true
        print("✅ [HTTP] HttpService enabled")
    end)
end

-- Check client
if not RunService:IsClient() then
    error("❌ [ExploFish] Must run as LocalScript!")
end

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
    error("❌ [ExploFish] LocalPlayer missing!")
end

print("✅ [ExploFish] Player:", LocalPlayer.Name)

-- Test simple UI creation
local success, ui = pcall(function()
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "ExploFishTest"
    screenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")
    
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, 200, 0, 100)
    frame.Position = UDim2.new(0.5, -100, 0.5, -50)
    frame.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
    frame.Parent = screenGui
    
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, 0, 1, 0)
    label.Text = "ExploFish Test UI"
    label.TextColor3 = Color3.fromRGB(255, 255, 255)
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.GothamBold
    label.TextSize = 14
    label.Parent = frame
    
    return screenGui
end)

if success then
    print("✅ [UI] Test UI created successfully!")
    
    -- Auto-close after 5 seconds
    task.wait(5)
    if ui then
        ui:Destroy()
        print("✅ [UI] Test UI cleaned up")
    end
else
    warn("❌ [UI] Failed to create test UI:", ui)
end

print("🎯 [ExploFish] Minimal loader test completed!")
print("📋 [ExploFish] If you see this, basic functionality works!")
print("🚀 [ExploFish] Ready to load full script!")
