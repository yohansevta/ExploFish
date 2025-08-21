
--[[
    Zayros FISHIT - Roblox Fishing Game GUI
    
    Features:
    - Auto Fishing with AFK support
    - Teleportation system
    - Boat spawning
    - Player modifications
    
    @author: Doovy
    @version: 1.1 (Improved)
--]]

	-- Constants
	local CONSTANTS = {
		FISHING_DELAY = 0.4,
		DEFAULT_WALKSPEED = 16,
		MAX_WALKSPEED = 100,
		GUI_NAME = "ZayrosFISHIT",
		BUTTON_UPDATE_DELAY = 0.1,
		ANTI_KICK_INTERVAL = 30, -- seconds
		AUTO_SELL_THRESHOLD = 0.8, -- 80% inventory full
		FISHING_SPOT_ROTATE_TIME = 300, -- 5 minutes
		-- Security Constants
		MIN_FISHING_DELAY = 0.3,
		MAX_FISHING_DELAY = 0.8,
		MIN_ANTI_KICK_INTERVAL = 25,
		MAX_ANTI_KICK_INTERVAL = 45,
		MAX_ACTIONS_PER_MINUTE = 120,
		DETECTION_COOLDOWN = 5
	}

	-- Services
	local RunService = game:GetService("RunService")
	local TweenService = game:GetService("TweenService")
	local Players = game:GetService("Players")
	local UserInputService = game:GetService("UserInputService")

	-- Core variables
	local player = Players.LocalPlayer
	local workspace = game:GetService("Workspace")

	-- State Management (moved up to fix undefined global)
	local State = {
		autoFishing = false,
		noOxygen = false,
		currentPage = "Main",
		walkSpeed = CONSTANTS.DEFAULT_WALKSPEED,
		isMinimized = false,
		-- Auto Fishing AFK Features
		antiKick = false,
		autoSell = false,
		smartLocation = false,
		-- Statistics
		fishCaught = 0,
		startTime = 0,
		totalProfit = 0,
		lastAntiKickTime = 0,
		lastLocationSwitch = 0,
		-- Security Features
		lastActionTime = 0,
		actionsThisMinute = 0,
		lastMinuteReset = 0,
		suspicionLevel = 0,
		isInCooldown = false,
		randomSeed = math.random(1000, 9999)
	}

	-- Cleanup existing GUI
	if game.Players.LocalPlayer.PlayerGui:FindFirstChild(CONSTANTS.GUI_NAME) ~= nil then
		game.Players.LocalPlayer.PlayerGui[CONSTANTS.GUI_NAME]:Destroy()
	end

	-- Global connections table for cleanup
	local connections = {}
	local threads = {}

	-- Remote Events Organization (moved up)
	local character = player.Character or player.CharacterAdded:Wait()
	local playerGui = player:WaitForChild("PlayerGui")
	local Rs = game:GetService("ReplicatedStorage")

	local Remotes = {
		EquipRod = Rs.Packages._Index["sleitnick_net@0.2.0"].net["RE/EquipToolFromHotbar"],
		UnEquipRod = Rs.Packages._Index["sleitnick_net@0.2.0"].net["RE/UnequipToolFromHotbar"],
		RequestFishing = Rs.Packages._Index["sleitnick_net@0.2.0"].net["RF/RequestFishingMinigameStarted"],
		ChargeRod = Rs.Packages._Index["sleitnick_net@0.2.0"].net["RF/ChargeFishingRod"],
		FishingComplete = Rs.Packages._Index["sleitnick_net@0.2.0"].net["RE/FishingCompleted"],
		CancelFishing = Rs.Packages._Index["sleitnick_net@0.2.0"].net["RF/CancelFishingInputs"],
		SpawnBoat = Rs.Packages._Index["sleitnick_net@0.2.0"].net["RF/SpawnBoat"],
		DespawnBoat = Rs.Packages._Index["sleitnick_net@0.2.0"].net["RF/DespawnBoat"],
		FishingRadar = Rs.Packages._Index["sleitnick_net@0.2.0"].net["RF/UpdateFishingRadar"],
		SellAll = Rs.Packages._Index["sleitnick_net@0.2.0"].net["RF/SellAllItems"]
	}

	local noOxygen = loadstring(game:HttpGet("https://pastebin.com/raw/JS7LaJsa"))()
	local tpFolder = workspace["!!!! ISLAND LOCATIONS !!!!"]
	local charFolder = workspace.Characters

	-- Error handling utility
	local function safeInvoke(remoteFunction, ...)
		local success, result = pcall(remoteFunction.InvokeServer, remoteFunction, ...)
		if not success then
			warn("Failed to invoke remote:", result)
		end
		return success, result
	end

	-- Security Functions
	local function getRandomDelay(min, max)
		math.randomseed(tick() + State.randomSeed)
		return min + (math.random() * (max - min))
	end

	local function isActionSafe()
		local currentTime = tick()
		
		-- Reset actions counter every minute
		if currentTime - State.lastMinuteReset > 60 then
			State.actionsThisMinute = 0
			State.lastMinuteReset = currentTime
		end
		
		-- Check if we're exceeding action limit
		if State.actionsThisMinute >= CONSTANTS.MAX_ACTIONS_PER_MINUTE then
			State.isInCooldown = true
			return false
		end
		
		-- Check minimum delay between actions
		if currentTime - State.lastActionTime < 0.1 then
			return false
		end
		
		return true
	end

	local function incrementSuspicion(amount)
		State.suspicionLevel = State.suspicionLevel + (amount or 1)
		if State.suspicionLevel > 10 then
			State.isInCooldown = true
			-- Force cooldown
			task.wait(CONSTANTS.DETECTION_COOLDOWN)
			State.suspicionLevel = 0
			State.isInCooldown = false
		end
	end

	local function safeInvokeWithSecurity(remoteFunction, ...)
		if not isActionSafe() or State.isInCooldown then
			return false, "Action blocked for security"
		end
		
		local currentTime = tick()
		State.lastActionTime = currentTime
		State.actionsThisMinute = State.actionsThisMinute + 1
		
		-- Add random micro-delay to humanize
		local microDelay = getRandomDelay(0.01, 0.05)
		task.wait(microDelay)
		
		local success, result = pcall(remoteFunction.InvokeServer, remoteFunction, ...)
		if not success then
			incrementSuspicion(2)
			warn("Failed to invoke remote:", result)
		end
		return success, result
	end

	-- Humanized Mouse Movement Simulation
	local function simulateHumanInput()
		if not player.Character then return end
		
		-- Simulate random mouse movements by slightly adjusting camera
		local camera = workspace.CurrentCamera
		if camera then
			local randomX = getRandomDelay(-0.1, 0.1)
			local randomY = getRandomDelay(-0.05, 0.05)
			
			-- Very subtle camera adjustments
			pcall(function()
				camera.CFrame = camera.CFrame * CFrame.Angles(math.rad(randomY), math.rad(randomX), 0)
			end)
		end
	end

	local function safeConnect(instance, event, callback)
		local connection = instance[event]:Connect(callback)
		table.insert(connections, connection)
		return connection
	end

-- Zayros FISHIT GUI - Fixed Version with reduced local variables

-- Constants
local CONSTANTS = {
	GUI_NAME = "ZayrosFISHIT",
	FISH_VALUE = 1,
	BOAT_PRICE = 100,
	CHECK_INTERVAL = 0.5,
	ANTI_KICK_INTERVAL = 30,
	MAX_SUSPICION = 100,
	SUSPICION_DECAY = 5
}

-- State management
local State = {
	isAutoFishing = false,
	isAntiKickActive = false,
	isAutoSellActive = false,
	isMinimized = false,
	originalWalkSpeed = 16,
	fishCount = 0,
	totalProfit = 0,
	startTime = tick(),
	suspicionLevel = 0,
	lastActionTime = 0,
	actionCount = 0
}

-- Services
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService") 
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer

-- Store all UI elements in a table to reduce local variable count
local gui = {}

-- Create UI elements
gui.screenGui = Instance.new("ScreenGui")
gui.mainFrame = Instance.new("Frame")
gui.exitBtn = Instance.new("TextButton")
gui.minimizeBtn = Instance.new("TextButton")
gui.floatingIcon = Instance.new("ImageButton")

-- Bulk create UI components
for i = 1, 20 do
	gui["corner" .. i] = Instance.new("UICorner")
	gui["constraint" .. i] = Instance.new("UITextSizeConstraint")
end

-- Setup main GUI
gui.screenGui.Name = CONSTANTS.GUI_NAME
gui.screenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")
gui.screenGui.ResetOnSpawn = false

gui.mainFrame.Name = "MainFrame"
gui.mainFrame.Parent = gui.screenGui
gui.mainFrame.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
gui.mainFrame.BorderSizePixel = 0
gui.mainFrame.Position = UDim2.new(0.3, 0, 0.2, 0)
gui.mainFrame.Size = UDim2.new(0.4, 0, 0.6, 0)
gui.mainFrame.Active = true
gui.mainFrame.Draggable = true

-- Exit button
gui.exitBtn.Name = "ExitBtn"
gui.exitBtn.Parent = gui.mainFrame
gui.exitBtn.BackgroundColor3 = Color3.fromRGB(255, 80, 80)
gui.exitBtn.Position = UDim2.new(0.9, 0, 0, 0)
gui.exitBtn.Size = UDim2.new(0.1, 0, 0.08, 0)
gui.exitBtn.Font = Enum.Font.SourceSansBold
gui.exitBtn.Text = "X"
gui.exitBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
gui.exitBtn.TextScaled = true

-- Minimize button  
gui.minimizeBtn.Name = "MinimizeBtn"
gui.minimizeBtn.Parent = gui.mainFrame
gui.minimizeBtn.BackgroundColor3 = Color3.fromRGB(255, 200, 80)
gui.minimizeBtn.Position = UDim2.new(0.8, 0, 0, 0)
gui.minimizeBtn.Size = UDim2.new(0.1, 0, 0.08, 0)
gui.minimizeBtn.Font = Enum.Font.SourceSansBold
gui.minimizeBtn.Text = "_"
gui.minimizeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
gui.minimizeBtn.TextScaled = true

-- Floating icon
gui.floatingIcon.Name = "FloatingIcon"
gui.floatingIcon.Parent = gui.screenGui
gui.floatingIcon.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
gui.floatingIcon.Position = UDim2.new(0, 10, 0.5, -25)
gui.floatingIcon.Size = UDim2.new(0, 50, 0, 50)
gui.floatingIcon.Image = "rbxassetid://136555589792977"
gui.floatingIcon.Visible = false
gui.floatingIcon.Active = true
gui.floatingIcon.Draggable = true

-- Apply corners
gui.corner1.CornerRadius = UDim.new(0, 8)
gui.corner1.Parent = gui.mainFrame
gui.corner2.CornerRadius = UDim.new(0, 4)
gui.corner2.Parent = gui.exitBtn
gui.corner3.CornerRadius = UDim.new(0, 4)
gui.corner3.Parent = gui.minimizeBtn
gui.corner4.CornerRadius = UDim.new(0, 25)
gui.corner4.Parent = gui.floatingIcon

-- Create main content area
gui.contentFrame = Instance.new("ScrollingFrame")
gui.contentFrame.Name = "ContentFrame"
gui.contentFrame.Parent = gui.mainFrame
gui.contentFrame.BackgroundTransparency = 1
gui.contentFrame.Position = UDim2.new(0, 10, 0.1, 0)
gui.contentFrame.Size = UDim2.new(1, -20, 0.9, 0)
gui.contentFrame.ScrollBarThickness = 4

-- Auto fishing feature
gui.autoFishFrame = Instance.new("Frame")
gui.autoFishFrame.Name = "AutoFishFrame"
gui.autoFishFrame.Parent = gui.contentFrame
gui.autoFishFrame.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
gui.autoFishFrame.Position = UDim2.new(0, 0, 0, 0)
gui.autoFishFrame.Size = UDim2.new(1, 0, 0, 80)

gui.autoFishLabel = Instance.new("TextLabel")
gui.autoFishLabel.Name = "AutoFishLabel"
gui.autoFishLabel.Parent = gui.autoFishFrame
gui.autoFishLabel.BackgroundTransparency = 1
gui.autoFishLabel.Position = UDim2.new(0, 10, 0, 0)
gui.autoFishLabel.Size = UDim2.new(0.6, 0, 1, 0)
gui.autoFishLabel.Font = Enum.Font.SourceSans
gui.autoFishLabel.Text = "Auto Fish"
gui.autoFishLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
gui.autoFishLabel.TextScaled = true
gui.autoFishLabel.TextXAlignment = Enum.TextXAlignment.Left

gui.autoFishBtn = Instance.new("TextButton")
gui.autoFishBtn.Name = "AutoFishBtn"
gui.autoFishBtn.Parent = gui.autoFishFrame
gui.autoFishBtn.BackgroundColor3 = Color3.fromRGB(255, 80, 80)
gui.autoFishBtn.Position = UDim2.new(0.7, 0, 0.25, 0)
gui.autoFishBtn.Size = UDim2.new(0.25, 0, 0.5, 0)
gui.autoFishBtn.Font = Enum.Font.SourceSansBold
gui.autoFishBtn.Text = "OFF"
gui.autoFishBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
gui.autoFishBtn.TextScaled = true

gui.corner5.CornerRadius = UDim.new(0, 6)
gui.corner5.Parent = gui.autoFishFrame
gui.corner6.CornerRadius = UDim.new(0, 4)
gui.corner6.Parent = gui.autoFishBtn

-- Anti-kick feature
gui.antiKickFrame = Instance.new("Frame")
gui.antiKickFrame.Name = "AntiKickFrame"
gui.antiKickFrame.Parent = gui.contentFrame
gui.antiKickFrame.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
gui.antiKickFrame.Position = UDim2.new(0, 0, 0, 90)
gui.antiKickFrame.Size = UDim2.new(1, 0, 0, 80)

gui.antiKickLabel = Instance.new("TextLabel")
gui.antiKickLabel.Name = "AntiKickLabel"
gui.antiKickLabel.Parent = gui.antiKickFrame
gui.antiKickLabel.BackgroundTransparency = 1
gui.antiKickLabel.Position = UDim2.new(0, 10, 0, 0)
gui.antiKickLabel.Size = UDim2.new(0.6, 0, 1, 0)
gui.antiKickLabel.Font = Enum.Font.SourceSans
gui.antiKickLabel.Text = "Anti-Kick"
gui.antiKickLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
gui.antiKickLabel.TextScaled = true
gui.antiKickLabel.TextXAlignment = Enum.TextXAlignment.Left

gui.antiKickBtn = Instance.new("TextButton")
gui.antiKickBtn.Name = "AntiKickBtn"
gui.antiKickBtn.Parent = gui.antiKickFrame
gui.antiKickBtn.BackgroundColor3 = Color3.fromRGB(255, 80, 80)
gui.antiKickBtn.Position = UDim2.new(0.7, 0, 0.25, 0)
gui.antiKickBtn.Size = UDim2.new(0.25, 0, 0.5, 0)
gui.antiKickBtn.Font = Enum.Font.SourceSansBold
gui.antiKickBtn.Text = "OFF"
gui.antiKickBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
gui.antiKickBtn.TextScaled = true

gui.corner7.CornerRadius = UDim.new(0, 6)
gui.corner7.Parent = gui.antiKickFrame
gui.corner8.CornerRadius = UDim.new(0, 4)
gui.corner8.Parent = gui.antiKickBtn

-- Statistics display
gui.statsFrame = Instance.new("Frame")
gui.statsFrame.Name = "StatsFrame"
gui.statsFrame.Parent = gui.contentFrame
gui.statsFrame.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
gui.statsFrame.Position = UDim2.new(0, 0, 0, 180)
gui.statsFrame.Size = UDim2.new(1, 0, 0, 120)

gui.statsTitle = Instance.new("TextLabel")
gui.statsTitle.Name = "StatsTitle"
gui.statsTitle.Parent = gui.statsFrame
gui.statsTitle.BackgroundTransparency = 1
gui.statsTitle.Position = UDim2.new(0, 10, 0, 5)
gui.statsTitle.Size = UDim2.new(1, -20, 0, 25)
gui.statsTitle.Font = Enum.Font.SourceSansBold
gui.statsTitle.Text = "Statistics"
gui.statsTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
gui.statsTitle.TextScaled = true
gui.statsTitle.TextXAlignment = Enum.TextXAlignment.Left

gui.fishCountLabel = Instance.new("TextLabel")
gui.fishCountLabel.Name = "FishCountLabel"
gui.fishCountLabel.Parent = gui.statsFrame
gui.fishCountLabel.BackgroundTransparency = 1
gui.fishCountLabel.Position = UDim2.new(0, 10, 0, 35)
gui.fishCountLabel.Size = UDim2.new(1, -20, 0, 25)
gui.fishCountLabel.Font = Enum.Font.SourceSans
gui.fishCountLabel.Text = "Fish Caught: 0"
gui.fishCountLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
gui.fishCountLabel.TextScaled = true
gui.fishCountLabel.TextXAlignment = Enum.TextXAlignment.Left

gui.timeLabel = Instance.new("TextLabel")
gui.timeLabel.Name = "TimeLabel"
gui.timeLabel.Parent = gui.statsFrame
gui.timeLabel.BackgroundTransparency = 1
gui.timeLabel.Position = UDim2.new(0, 10, 0, 65)
gui.timeLabel.Size = UDim2.new(1, -20, 0, 25)
gui.timeLabel.Font = Enum.Font.SourceSans
gui.timeLabel.Text = "Time: 0s"
gui.timeLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
gui.timeLabel.TextScaled = true
gui.timeLabel.TextXAlignment = Enum.TextXAlignment.Left

gui.profitLabel = Instance.new("TextLabel")
gui.profitLabel.Name = "ProfitLabel"
gui.profitLabel.Parent = gui.statsFrame
gui.profitLabel.BackgroundTransparency = 1
gui.profitLabel.Position = UDim2.new(0, 10, 0, 95)
gui.profitLabel.Size = UDim2.new(1, -20, 0, 25)
gui.profitLabel.Font = Enum.Font.SourceSans
gui.profitLabel.Text = "Profit: $0"
gui.profitLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
gui.profitLabel.TextScaled = true
gui.profitLabel.TextXAlignment = Enum.TextXAlignment.Left

gui.corner9.CornerRadius = UDim.new(0, 6)
gui.corner9.Parent = gui.statsFrame

-- Helper functions
local function updateStats()
	gui.fishCountLabel.Text = "Fish Caught: " .. State.fishCount
	gui.timeLabel.Text = "Time: " .. math.floor(tick() - State.startTime) .. "s"
	gui.profitLabel.Text = "Profit: $" .. State.totalProfit
end

local function safeRemoteCall(remoteName, ...)
	local success, result = pcall(function(...)
		local remote = ReplicatedStorage:FindFirstChild("events")
		if remote then
			remote = remote:FindFirstChild(remoteName)
			if remote then
				remote:FireServer(...)
				return true
			end
		end
		return false
	end, ...)
	return success and result
end

-- Core functions
local function autoFish()
	if not State.isAutoFishing then return end
	
	local character = LocalPlayer.Character
	if not character then return end
	
	if safeRemoteCall("fishing") then
		State.fishCount = State.fishCount + 1
		State.totalProfit = State.totalProfit + CONSTANTS.FISH_VALUE
		updateStats()
	end
end

local function antiKick()
	if not State.isAntiKickActive then return end
	
	local character = LocalPlayer.Character
	if character and character:FindFirstChild("Humanoid") then
		character.Humanoid:Move(Vector3.new(0, 0, 0), true)
	end
end

-- Event connections
gui.exitBtn.MouseButton1Click:Connect(function()
	gui.screenGui:Destroy()
end)

gui.minimizeBtn.MouseButton1Click:Connect(function()
	State.isMinimized = not State.isMinimized
	gui.mainFrame.Visible = not State.isMinimized
	gui.floatingIcon.Visible = State.isMinimized
end)

gui.floatingIcon.MouseButton1Click:Connect(function()
	State.isMinimized = false
	gui.mainFrame.Visible = true
	gui.floatingIcon.Visible = false
end)

gui.autoFishBtn.MouseButton1Click:Connect(function()
	State.isAutoFishing = not State.isAutoFishing
	gui.autoFishBtn.Text = State.isAutoFishing and "ON" or "OFF"
	gui.autoFishBtn.BackgroundColor3 = State.isAutoFishing and Color3.fromRGB(80, 255, 80) or Color3.fromRGB(255, 80, 80)
end)

gui.antiKickBtn.MouseButton1Click:Connect(function()
	State.isAntiKickActive = not State.isAntiKickActive
	gui.antiKickBtn.Text = State.isAntiKickActive and "ON" or "OFF"
	gui.antiKickBtn.BackgroundColor3 = State.isAntiKickActive and Color3.fromRGB(80, 255, 80) or Color3.fromRGB(255, 80, 80)
end)

-- Main loops
spawn(function()
	while gui.screenGui and gui.screenGui.Parent do
		autoFish()
		wait(CONSTANTS.CHECK_INTERVAL)
	end
end)

spawn(function()
	while gui.screenGui and gui.screenGui.Parent do
		antiKick()
		wait(CONSTANTS.ANTI_KICK_INTERVAL)
	end
end)

spawn(function()
	while gui.screenGui and gui.screenGui.Parent do
		updateStats()
		wait(1)
	end
end)

print("Zayros FISHIT GUI loaded successfully! (Fixed Version)")

	SideBar.Name = "SideBar"
	SideBar.Parent = FrameUtama
	SideBar.BackgroundColor3 = Color3.fromRGB(83, 83, 83)
	SideBar.BorderColor3 = Color3.fromRGB(0, 0, 0)
	SideBar.BorderSizePixel = 0
	SideBar.Size = UDim2.new(0.376050383, 0, 1, 0)
	SideBar.ZIndex = 2

	Logo.Name = "Logo"
	Logo.Parent = SideBar
	Logo.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	Logo.BorderColor3 = Color3.fromRGB(0, 0, 0)
	Logo.BorderSizePixel = 0
	Logo.Position = UDim2.new(0.0729603693, 0, 0.0375426523, 0)
	Logo.Size = UDim2.new(0.167597771, 0, 0.0884955749, 0)
	Logo.ZIndex = 2
	Logo.Image = "rbxassetid://136555589792977"

	UICorner_3.CornerRadius = UDim.new(0, 10)
	UICorner_3.Parent = Logo

	TittleSideBar.Name = "TittleSideBar"
	TittleSideBar.Parent = SideBar
	TittleSideBar.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	TittleSideBar.BackgroundTransparency = 1.000
	TittleSideBar.BorderColor3 = Color3.fromRGB(0, 0, 0)
	TittleSideBar.BorderSizePixel = 0
	TittleSideBar.Position = UDim2.new(0.309023052, 0, 0.0375426523, 0)
	TittleSideBar.Size = UDim2.new(0.65363127, 0, 0.0884955749, 0)
	TittleSideBar.ZIndex = 2
	TittleSideBar.Font = Enum.Font.SourceSansBold
	TittleSideBar.Text = "Zayros FISHIT"
	TittleSideBar.TextColor3 = Color3.fromRGB(255, 255, 255)
	TittleSideBar.TextScaled = true
	TittleSideBar.TextSize = 20.000
	TittleSideBar.TextWrapped = true
	TittleSideBar.TextXAlignment = Enum.TextXAlignment.Left

	UITextSizeConstraint_2.Parent = TittleSideBar
	UITextSizeConstraint_2.MaxTextSize = 20

	MainMenuSaidBar.Name = "MainMenuSaidBar"
	MainMenuSaidBar.Parent = SideBar
	MainMenuSaidBar.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	MainMenuSaidBar.BackgroundTransparency = 1.000
	MainMenuSaidBar.BorderColor3 = Color3.fromRGB(0, 0, 0)
	MainMenuSaidBar.BorderSizePixel = 0
	MainMenuSaidBar.Position = UDim2.new(0, 0, 0.16519174, 0)
	MainMenuSaidBar.Size = UDim2.new(1, 0, 0.781710923, 0)

	UIListLayout.Parent = MainMenuSaidBar
	UIListLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	UIListLayout.SortOrder = Enum.SortOrder.LayoutOrder
	UIListLayout.Padding = UDim.new(0.0500000007, 0)

	MAIN.Name = "MAIN"
	MAIN.Parent = MainMenuSaidBar
	MAIN.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	MAIN.BorderColor3 = Color3.fromRGB(0, 0, 0)
	MAIN.BorderSizePixel = 0
	MAIN.Size = UDim2.new(0.916201115, 0, 0.113207549, 0)
	MAIN.Font = Enum.Font.SourceSansBold
	MAIN.Text = "MAIN"
	MAIN.TextColor3 = Color3.fromRGB(255, 255, 255)
	MAIN.TextScaled = true
	MAIN.TextSize = 14.000
	MAIN.TextWrapped = true

	UICorner_4.Parent = MAIN

	UITextSizeConstraint_3.Parent = MAIN
	UITextSizeConstraint_3.MaxTextSize = 14

	Player.Name = "Player"
	Player.Parent = MainMenuSaidBar
	Player.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	Player.BorderColor3 = Color3.fromRGB(0, 0, 0)
	Player.BorderSizePixel = 0
	Player.Size = UDim2.new(0.916201115, 0, 0.113207549, 0)
	Player.Font = Enum.Font.SourceSansBold
	Player.Text = "PLAYER"
	Player.TextColor3 = Color3.fromRGB(255, 255, 255)
	Player.TextScaled = true
	Player.TextSize = 14.000
	Player.TextWrapped = true

	UICorner_5.Parent = Player

	UITextSizeConstraint_4.Parent = Player
	UITextSizeConstraint_4.MaxTextSize = 14

	SpawnBoat.Name = "SpawnBoat"
	SpawnBoat.Parent = MainMenuSaidBar
	SpawnBoat.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	SpawnBoat.BorderColor3 = Color3.fromRGB(0, 0, 0)
	SpawnBoat.BorderSizePixel = 0
	SpawnBoat.Size = UDim2.new(0.916201115, 0, 0.113207549, 0)
	SpawnBoat.Font = Enum.Font.SourceSansBold
	SpawnBoat.Text = "SPAWN BOAT"
	SpawnBoat.TextColor3 = Color3.fromRGB(255, 255, 255)
	SpawnBoat.TextScaled = true
	SpawnBoat.TextSize = 14.000
	SpawnBoat.TextWrapped = true

	UICorner_6.Parent = SpawnBoat

	UITextSizeConstraint_5.Parent = SpawnBoat
	UITextSizeConstraint_5.MaxTextSize = 14

	TELEPORT.Name = "TELEPORT"
	TELEPORT.Parent = MainMenuSaidBar
	TELEPORT.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	TELEPORT.BorderColor3 = Color3.fromRGB(0, 0, 0)
	TELEPORT.BorderSizePixel = 0
	TELEPORT.Size = UDim2.new(0.916201115, 0, 0.113207549, 0)
	TELEPORT.Font = Enum.Font.SourceSansBold
	TELEPORT.Text = "TELEPORT"
	TELEPORT.TextColor3 = Color3.fromRGB(255, 255, 255)
	TELEPORT.TextScaled = true
	TELEPORT.TextSize = 14.000
	TELEPORT.TextWrapped = true

	UICorner_7.Parent = TELEPORT

	UITextSizeConstraint_6.Parent = TELEPORT
	UITextSizeConstraint_6.MaxTextSize = 14

	Settings.Name = "Settings"
	Settings.Parent = MainMenuSaidBar
	Settings.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	Settings.BorderColor3 = Color3.fromRGB(0, 0, 0)
	Settings.BorderSizePixel = 0
	Settings.Position = UDim2.new(0.0418994427, 0, 0.71981132, 0)
	Settings.Size = UDim2.new(0.916201115, 0, 0.113207549, 0)
	Settings.Font = Enum.Font.SourceSansBold
	Settings.Text = "SETTINGS"
	Settings.TextColor3 = Color3.fromRGB(255, 255, 255)
	Settings.TextScaled = true
	Settings.TextSize = 14.000
	Settings.TextWrapped = true

	UICorner_8.Parent = Settings

	UITextSizeConstraint_7.Parent = Settings
	UITextSizeConstraint_7.MaxTextSize = 14

	Line.Name = "Line"
	Line.Parent = SideBar
	Line.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	Line.BorderColor3 = Color3.fromRGB(0, 0, 0)
	Line.BorderSizePixel = 0
	Line.Position = UDim2.new(0, 0, 0.144542769, 0)
	Line.Size = UDim2.new(1, 0, 0.0029498525, 0)
	Line.ZIndex = 2

	Credit.Name = "Credit"
	Credit.Parent = SideBar
	Credit.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	Credit.BackgroundTransparency = 1.000
	Credit.BorderColor3 = Color3.fromRGB(0, 0, 0)
	Credit.BorderSizePixel = 0
	Credit.Position = UDim2.new(0, 0, 0.874947131, 0)
	Credit.Size = UDim2.new(0.997643113, 0, 0.122885838, 0)
	Credit.Font = Enum.Font.SourceSansBold
	Credit.Text = "Made by Doovy :D"
	Credit.TextColor3 = Color3.fromRGB(255, 255, 255)
	Credit.TextScaled = true
	Credit.TextSize = 14.000
	Credit.TextWrapped = true

	UITextSizeConstraint_8.Parent = Credit
	UITextSizeConstraint_8.MaxTextSize = 14

	Line_2.Name = "Line"
	Line_2.Parent = FrameUtama
	Line_2.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	Line_2.BorderColor3 = Color3.fromRGB(0, 0, 0)
	Line_2.BorderSizePixel = 0
	Line_2.Position = UDim2.new(0.376050383, 0, 0.144542769, 0)
	Line_2.Size = UDim2.new(0.623949528, 0, 0.0029498525, 0)
	Line_2.ZIndex = 2

	Tittle.Name = "Tittle"
	Tittle.Parent = FrameUtama
	Tittle.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	Tittle.BackgroundTransparency = 1.000
	Tittle.BorderColor3 = Color3.fromRGB(0, 0, 0)
	Tittle.BorderSizePixel = 0
	Tittle.Position = UDim2.new(0.420367569, 0, 0.0375426523, 0)
	Tittle.Size = UDim2.new(0.443547368, 0, 0.0884955749, 0)
	Tittle.ZIndex = 2
	Tittle.Font = Enum.Font.SourceSansBold
	Tittle.Text = "PLAYER"
	Tittle.TextColor3 = Color3.fromRGB(255, 255, 255)
	Tittle.TextScaled = true
	Tittle.TextSize = 20.000
	Tittle.TextWrapped = true

	UITextSizeConstraint_9.Parent = Tittle
	UITextSizeConstraint_9.MaxTextSize = 20

	MainFrame.Name = "MainFrame"
	MainFrame.Parent = FrameUtama
	MainFrame.Active = true
	MainFrame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	MainFrame.BackgroundTransparency = 1.000
	MainFrame.BorderColor3 = Color3.fromRGB(0, 0, 0)
	MainFrame.BorderSizePixel = 0
	MainFrame.Position = UDim2.new(0.376050383, 0, 0.147492602, 0)
	MainFrame.Size = UDim2.new(0.623949468, 0, 0.852507353, 0)
	MainFrame.Visible = false
	MainFrame.ZIndex = 2
	MainFrame.ScrollBarThickness = 6

	MainListLayoutFrame.Name = "MainListLayoutFrame"
	MainListLayoutFrame.Parent = MainFrame
	MainListLayoutFrame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	MainListLayoutFrame.BackgroundTransparency = 1.000
	MainListLayoutFrame.BorderColor3 = Color3.fromRGB(0, 0, 0)
	MainListLayoutFrame.BorderSizePixel = 0
	MainListLayoutFrame.Position = UDim2.new(0, 0, 0.0219183583, 0)
	MainListLayoutFrame.Size = UDim2.new(1, 0, 1, 0)

	ListLayoutMain.Name = "ListLayoutMain"
	ListLayoutMain.Parent = MainListLayoutFrame
	ListLayoutMain.HorizontalAlignment = Enum.HorizontalAlignment.Center
	ListLayoutMain.SortOrder = Enum.SortOrder.LayoutOrder
	ListLayoutMain.Padding = UDim.new(0, 8)

	AutoFishFrame.Name = "AutoFishFrame"
	AutoFishFrame.Parent = MainListLayoutFrame
	AutoFishFrame.BackgroundColor3 = Color3.fromRGB(47, 47, 47)
	AutoFishFrame.BorderColor3 = Color3.fromRGB(0, 0, 0)
	AutoFishFrame.BorderSizePixel = 0
	AutoFishFrame.Position = UDim2.new(0.0437708385, 0, 0.0418279432, 0)
	AutoFishFrame.Size = UDim2.new(0.898138702, 0, 0.106191501, 0)

	UICorner_9.Parent = AutoFishFrame

	AutoFishText.Name = "AutoFishText"
	AutoFishText.Parent = AutoFishFrame
	AutoFishText.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	AutoFishText.BackgroundTransparency = 1.000
	AutoFishText.BorderColor3 = Color3.fromRGB(0, 0, 0)
	AutoFishText.BorderSizePixel = 0
	AutoFishText.Position = UDim2.new(0.0296296291, 0, 0.216216221, 0)
	AutoFishText.Size = UDim2.new(0.4148148, 0, 0.567567587, 0)
	AutoFishText.Font = Enum.Font.SourceSansBold
	AutoFishText.Text = "Auto Fish (AFK) :"
	AutoFishText.TextColor3 = Color3.fromRGB(255, 255, 255)
	AutoFishText.TextScaled = true
	AutoFishText.TextSize = 14.000
	AutoFishText.TextWrapped = true
	AutoFishText.TextXAlignment = Enum.TextXAlignment.Left

	UITextSizeConstraint_10.Parent = AutoFishText
	UITextSizeConstraint_10.MaxTextSize = 14

	AutoFishButton.Name = "AutoFishButton"
	AutoFishButton.Parent = AutoFishFrame
	AutoFishButton.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	AutoFishButton.BackgroundTransparency = 1.000
	AutoFishButton.BorderColor3 = Color3.fromRGB(0, 0, 0)
	AutoFishButton.BorderSizePixel = 0
	AutoFishButton.Position = UDim2.new(0.75555557, 0, 0.108108111, 0)
	AutoFishButton.Size = UDim2.new(0.2074074, 0, 0.783783793, 0)
	AutoFishButton.ZIndex = 2
	AutoFishButton.Font = Enum.Font.SourceSansBold
	AutoFishButton.Text = "OFF"
	AutoFishButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	AutoFishButton.TextScaled = true
	AutoFishButton.TextSize = 14.000
	AutoFishButton.TextWrapped = true

	UITextSizeConstraint_11.Parent = AutoFishButton
	UITextSizeConstraint_11.MaxTextSize = 14

	AutoFishWarna.Name = "AutoFishWarna"
	AutoFishWarna.Parent = AutoFishFrame
	AutoFishWarna.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	AutoFishWarna.BorderColor3 = Color3.fromRGB(0, 0, 0)
	AutoFishWarna.BorderSizePixel = 0
	AutoFishWarna.Position = UDim2.new(0.75555557, 0, 0.135135129, 0)
	AutoFishWarna.Size = UDim2.new(0.203703701, 0, 0.729729712, 0)

	UICorner_10.Parent = AutoFishWarna

	SellAllFrame.Name = "SellAllFrame"
	SellAllFrame.Parent = MainListLayoutFrame
	SellAllFrame.BackgroundColor3 = Color3.fromRGB(47, 47, 47)
	SellAllFrame.BorderColor3 = Color3.fromRGB(0, 0, 0)
	SellAllFrame.BorderSizePixel = 0
	SellAllFrame.Position = UDim2.new(0.0437710434, 0, 0.209508449, 0)
	SellAllFrame.Size = UDim2.new(0.898000002, 0, 0.105999999, 0)

	UICorner_11.Parent = SellAllFrame

	SellAllButton.Name = "SellAllButton"
	SellAllButton.Parent = SellAllFrame
	SellAllButton.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	SellAllButton.BackgroundTransparency = 1.000
	SellAllButton.BorderColor3 = Color3.fromRGB(0, 0, 0)
	SellAllButton.BorderSizePixel = 0
	SellAllButton.Size = UDim2.new(1, 0, 1, 0)
	SellAllButton.ZIndex = 2
	SellAllButton.Font = Enum.Font.SourceSansBold
	SellAllButton.Text = ""
	SellAllButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	SellAllButton.TextSize = 14.000

	SellAllText.Name = "SellAllText"
	SellAllText.Parent = SellAllFrame
	SellAllText.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	SellAllText.BackgroundTransparency = 1.000
	SellAllText.BorderColor3 = Color3.fromRGB(0, 0, 0)
	SellAllText.BorderSizePixel = 0
	SellAllText.Position = UDim2.new(0.290409207, 0, 0.216216132, 0)
	SellAllText.Size = UDim2.new(0.4148148, 0, 0.567567587, 0)
	SellAllText.Font = Enum.Font.SourceSansBold
	SellAllText.Text = "Sell All"
	SellAllText.TextColor3 = Color3.fromRGB(255, 255, 255)
	SellAllText.TextScaled = true
	SellAllText.TextSize = 14.000
	SellAllText.TextWrapped = true

	-- Anti-Kick Frame Properties
	AntiKickFrame.Name = "AntiKickFrame"
	AntiKickFrame.Parent = MainListLayoutFrame
	AntiKickFrame.BackgroundColor3 = Color3.fromRGB(47, 47, 47)
	AntiKickFrame.BorderColor3 = Color3.fromRGB(0, 0, 0)
	AntiKickFrame.BorderSizePixel = 0
	AntiKickFrame.Size = UDim2.new(0.898000002, 0, 0.105999999, 0)

	UICorner_AK.Parent = AntiKickFrame

	AntiKickText.Name = "AntiKickText"
	AntiKickText.Parent = AntiKickFrame
	AntiKickText.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	AntiKickText.BackgroundTransparency = 1.000
	AntiKickText.BorderColor3 = Color3.fromRGB(0, 0, 0)
	AntiKickText.BorderSizePixel = 0
	AntiKickText.Position = UDim2.new(0.0296296291, 0, 0.216216221, 0)
	AntiKickText.Size = UDim2.new(0.4148148, 0, 0.567567587, 0)
	AntiKickText.Font = Enum.Font.SourceSansBold
	AntiKickText.Text = "Anti-Kick (AFK) :"
	AntiKickText.TextColor3 = Color3.fromRGB(255, 255, 255)
	AntiKickText.TextScaled = true
	AntiKickText.TextSize = 14.000
	AntiKickText.TextWrapped = true
	AntiKickText.TextXAlignment = Enum.TextXAlignment.Left

	AntiKickButton.Name = "AntiKickButton"
	AntiKickButton.Parent = AntiKickFrame
	AntiKickButton.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	AntiKickButton.BackgroundTransparency = 1.000
	AntiKickButton.BorderColor3 = Color3.fromRGB(0, 0, 0)
	AntiKickButton.BorderSizePixel = 0
	AntiKickButton.Position = UDim2.new(0.75555557, 0, 0.108108111, 0)
	AntiKickButton.Size = UDim2.new(0.2074074, 0, 0.783783793, 0)
	AntiKickButton.ZIndex = 2
	AntiKickButton.Font = Enum.Font.SourceSansBold
	AntiKickButton.Text = "OFF"
	AntiKickButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	AntiKickButton.TextScaled = true
	AntiKickButton.TextSize = 14.000
	AntiKickButton.TextWrapped = true

	AntiKickWarna.Name = "AntiKickWarna"
	AntiKickWarna.Parent = AntiKickFrame
	AntiKickWarna.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	AntiKickWarna.BorderColor3 = Color3.fromRGB(0, 0, 0)
	AntiKickWarna.BorderSizePixel = 0
	AntiKickWarna.Position = UDim2.new(0.75555557, 0, 0.135135129, 0)
	AntiKickWarna.Size = UDim2.new(0.203703701, 0, 0.729729712, 0)

	UICorner_AKW.Parent = AntiKickWarna

	-- Auto Sell Frame Properties
	AutoSellFrame.Name = "AutoSellFrame"
	AutoSellFrame.Parent = MainListLayoutFrame
	AutoSellFrame.BackgroundColor3 = Color3.fromRGB(47, 47, 47)
	AutoSellFrame.BorderColor3 = Color3.fromRGB(0, 0, 0)
	AutoSellFrame.BorderSizePixel = 0
	AutoSellFrame.Size = UDim2.new(0.898000002, 0, 0.105999999, 0)

	UICorner_AS.Parent = AutoSellFrame

	AutoSellText.Name = "AutoSellText"
	AutoSellText.Parent = AutoSellFrame
	AutoSellText.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	AutoSellText.BackgroundTransparency = 1.000
	AutoSellText.BorderColor3 = Color3.fromRGB(0, 0, 0)
	AutoSellText.BorderSizePixel = 0
	AutoSellText.Position = UDim2.new(0.0296296291, 0, 0.216216221, 0)
	AutoSellText.Size = UDim2.new(0.4148148, 0, 0.567567587, 0)
	AutoSellText.Font = Enum.Font.SourceSansBold
	AutoSellText.Text = "Auto Sell (80%) :"
	AutoSellText.TextColor3 = Color3.fromRGB(255, 255, 255)
	AutoSellText.TextScaled = true
	AutoSellText.TextSize = 14.000
	AutoSellText.TextWrapped = true
	AutoSellText.TextXAlignment = Enum.TextXAlignment.Left

	AutoSellButton.Name = "AutoSellButton"
	AutoSellButton.Parent = AutoSellFrame
	AutoSellButton.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	AutoSellButton.BackgroundTransparency = 1.000
	AutoSellButton.BorderColor3 = Color3.fromRGB(0, 0, 0)
	AutoSellButton.BorderSizePixel = 0
	AutoSellButton.Position = UDim2.new(0.75555557, 0, 0.108108111, 0)
	AutoSellButton.Size = UDim2.new(0.2074074, 0, 0.783783793, 0)
	AutoSellButton.ZIndex = 2
	AutoSellButton.Font = Enum.Font.SourceSansBold
	AutoSellButton.Text = "OFF"
	AutoSellButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	AutoSellButton.TextScaled = true
	AutoSellButton.TextSize = 14.000
	AutoSellButton.TextWrapped = true

	AutoSellWarna.Name = "AutoSellWarna"
	AutoSellWarna.Parent = AutoSellFrame
	AutoSellWarna.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	AutoSellWarna.BorderColor3 = Color3.fromRGB(0, 0, 0)
	AutoSellWarna.BorderSizePixel = 0
	AutoSellWarna.Position = UDim2.new(0.75555557, 0, 0.135135129, 0)
	AutoSellWarna.Size = UDim2.new(0.203703701, 0, 0.729729712, 0)

	UICorner_ASW.Parent = AutoSellWarna

	-- Statistics Frame Properties
	StatsFrame.Name = "StatsFrame"
	StatsFrame.Parent = MainListLayoutFrame
	StatsFrame.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
	StatsFrame.BorderColor3 = Color3.fromRGB(0, 0, 0)
	StatsFrame.BorderSizePixel = 0
	StatsFrame.Size = UDim2.new(0.898000002, 0, 0.15, 0)

	UICorner_Stats.Parent = StatsFrame

	StatsTitle.Name = "StatsTitle"
	StatsTitle.Parent = StatsFrame
	StatsTitle.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	StatsTitle.BackgroundTransparency = 1.000
	StatsTitle.BorderColor3 = Color3.fromRGB(0, 0, 0)
	StatsTitle.BorderSizePixel = 0
	StatsTitle.Position = UDim2.new(0.0296296291, 0, 0.05, 0)
	StatsTitle.Size = UDim2.new(0.94, 0, 0.25, 0)
	StatsTitle.Font = Enum.Font.SourceSansBold
	StatsTitle.Text = "📊 FISHING STATISTICS"
	StatsTitle.TextColor3 = Color3.fromRGB(255, 215, 0)
	StatsTitle.TextScaled = true
	StatsTitle.TextSize = 16.000
	StatsTitle.TextWrapped = true

	FishCountLabel.Name = "FishCountLabel"
	FishCountLabel.Parent = StatsFrame
	FishCountLabel.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	FishCountLabel.BackgroundTransparency = 1.000
	FishCountLabel.BorderColor3 = Color3.fromRGB(0, 0, 0)
	FishCountLabel.BorderSizePixel = 0
	FishCountLabel.Position = UDim2.new(0.0296296291, 0, 0.35, 0)
	FishCountLabel.Size = UDim2.new(0.94, 0, 0.2, 0)
	FishCountLabel.Font = Enum.Font.SourceSans
	FishCountLabel.Text = "🐟 Fish Caught: 0"
	FishCountLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	FishCountLabel.TextScaled = true
	FishCountLabel.TextSize = 12.000
	FishCountLabel.TextWrapped = true
	FishCountLabel.TextXAlignment = Enum.TextXAlignment.Left

	TimeLabel.Name = "TimeLabel"
	TimeLabel.Parent = StatsFrame
	TimeLabel.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	TimeLabel.BackgroundTransparency = 1.000
	TimeLabel.BorderColor3 = Color3.fromRGB(0, 0, 0)
	TimeLabel.BorderSizePixel = 0
	TimeLabel.Position = UDim2.new(0.0296296291, 0, 0.57, 0)
	TimeLabel.Size = UDim2.new(0.94, 0, 0.2, 0)
	TimeLabel.Font = Enum.Font.SourceSans
	TimeLabel.Text = "⏱️ Time: 00:00:00"
	TimeLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	TimeLabel.TextScaled = true
	TimeLabel.TextSize = 12.000
	TimeLabel.TextWrapped = true
	TimeLabel.TextXAlignment = Enum.TextXAlignment.Left

	ProfitLabel.Name = "ProfitLabel"
	ProfitLabel.Parent = StatsFrame
	ProfitLabel.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	ProfitLabel.BackgroundTransparency = 1.000
	ProfitLabel.BorderColor3 = Color3.fromRGB(0, 0, 0)
	ProfitLabel.BorderSizePixel = 0
	ProfitLabel.Position = UDim2.new(0.0296296291, 0, 0.79, 0)
	ProfitLabel.Size = UDim2.new(0.94, 0, 0.2, 0)
	ProfitLabel.Font = Enum.Font.SourceSans
	ProfitLabel.Text = "💰 Rate: 0 fish/hour"
	ProfitLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	ProfitLabel.TextScaled = true
	ProfitLabel.TextSize = 12.000
	ProfitLabel.TextWrapped = true
	ProfitLabel.TextXAlignment = Enum.TextXAlignment.Left

	-- Security Status Frame
	local SecurityFrame = Instance.new("Frame")
	local UICorner_Sec = Instance.new("UICorner")
	local SecurityTitle = Instance.new("TextLabel")
	local SecurityStatus = Instance.new("TextLabel")
	local SuspicionMeter = Instance.new("Frame")
	local SuspicionBar = Instance.new("Frame")
	local UICorner_SuspBar = Instance.new("UICorner")

	SecurityFrame.Name = "SecurityFrame"
	SecurityFrame.Parent = MainListLayoutFrame
	SecurityFrame.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
	SecurityFrame.BorderColor3 = Color3.fromRGB(0, 0, 0)
	SecurityFrame.BorderSizePixel = 0
	SecurityFrame.Size = UDim2.new(0.898000002, 0, 0.12, 0)

	UICorner_Sec.Parent = SecurityFrame

	SecurityTitle.Name = "SecurityTitle"
	SecurityTitle.Parent = SecurityFrame
	SecurityTitle.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	SecurityTitle.BackgroundTransparency = 1.000
	SecurityTitle.BorderColor3 = Color3.fromRGB(0, 0, 0)
	SecurityTitle.BorderSizePixel = 0
	SecurityTitle.Position = UDim2.new(0.0296296291, 0, 0.05, 0)
	SecurityTitle.Size = UDim2.new(0.94, 0, 0.3, 0)
	SecurityTitle.Font = Enum.Font.SourceSansBold
	SecurityTitle.Text = "🔐 SECURITY STATUS"
	SecurityTitle.TextColor3 = Color3.fromRGB(0, 255, 0)
	SecurityTitle.TextScaled = true
	SecurityTitle.TextSize = 14.000
	SecurityTitle.TextWrapped = true

	SecurityStatus.Name = "SecurityStatus"
	SecurityStatus.Parent = SecurityFrame
	SecurityStatus.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	SecurityStatus.BackgroundTransparency = 1.000
	SecurityStatus.BorderColor3 = Color3.fromRGB(0, 0, 0)
	SecurityStatus.BorderSizePixel = 0
	SecurityStatus.Position = UDim2.new(0.0296296291, 0, 0.4, 0)
	SecurityStatus.Size = UDim2.new(0.94, 0, 0.25, 0)
	SecurityStatus.Font = Enum.Font.SourceSans
	SecurityStatus.Text = "✅ Safe - All systems normal"
	SecurityStatus.TextColor3 = Color3.fromRGB(0, 255, 0)
	SecurityStatus.TextScaled = true
	SecurityStatus.TextSize = 11.000
	SecurityStatus.TextWrapped = true
	SecurityStatus.TextXAlignment = Enum.TextXAlignment.Left

	SuspicionMeter.Name = "SuspicionMeter"
	SuspicionMeter.Parent = SecurityFrame
	SuspicionMeter.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
	SuspicionMeter.BorderColor3 = Color3.fromRGB(0, 0, 0)
	SuspicionMeter.BorderSizePixel = 0
	SuspicionMeter.Position = UDim2.new(0.0296296291, 0, 0.75, 0)
	SuspicionMeter.Size = UDim2.new(0.94, 0, 0.15, 0)

	SuspicionBar.Name = "SuspicionBar"
	SuspicionBar.Parent = SuspicionMeter
	SuspicionBar.BackgroundColor3 = Color3.fromRGB(0, 255, 0)
	SuspicionBar.BorderColor3 = Color3.fromRGB(0, 0, 0)
	SuspicionBar.BorderSizePixel = 0
	SuspicionBar.Size = UDim2.new(0, 0, 1, 0)

	UICorner_SuspBar.Parent = SuspicionBar

	PlayerFrame.Name = "PlayerFrame"
	PlayerFrame.Parent = FrameUtama
	PlayerFrame.Active = true
	PlayerFrame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	PlayerFrame.BackgroundTransparency = 1.000
	PlayerFrame.BorderColor3 = Color3.fromRGB(0, 0, 0)
	PlayerFrame.BorderSizePixel = 0
	PlayerFrame.Position = UDim2.new(0.376050383, 0, 0.147492632, 0)
	PlayerFrame.Size = UDim2.new(0.623949528, 0, 0.852507353, 0)
	PlayerFrame.ScrollBarThickness = 6

	ListLayoutPlayerFrame.Name = "ListLayoutPlayerFrame"
	ListLayoutPlayerFrame.Parent = PlayerFrame
	ListLayoutPlayerFrame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	ListLayoutPlayerFrame.BackgroundTransparency = 1.000
	ListLayoutPlayerFrame.BorderColor3 = Color3.fromRGB(0, 0, 0)
	ListLayoutPlayerFrame.BorderSizePixel = 0
	ListLayoutPlayerFrame.Position = UDim2.new(0, 0, 0.0219183583, 0)
	ListLayoutPlayerFrame.Size = UDim2.new(1, 0, 1, 0)

	ListLayoutPlayer.Name = "ListLayoutPlayer"
	ListLayoutPlayer.Parent = ListLayoutPlayerFrame
	ListLayoutPlayer.HorizontalAlignment = Enum.HorizontalAlignment.Center
	ListLayoutPlayer.SortOrder = Enum.SortOrder.LayoutOrder
	ListLayoutPlayer.Padding = UDim.new(0, 8)

	NoOxygenDamageFrame.Name = "NoOxygenDamageFrame"
	NoOxygenDamageFrame.Parent = ListLayoutPlayerFrame
	NoOxygenDamageFrame.BackgroundColor3 = Color3.fromRGB(47, 47, 47)
	NoOxygenDamageFrame.BorderColor3 = Color3.fromRGB(0, 0, 0)
	NoOxygenDamageFrame.BorderSizePixel = 0
	NoOxygenDamageFrame.Position = UDim2.new(0.0404040329, 0, 0.272833079, 0)
	NoOxygenDamageFrame.Size = UDim2.new(0.898000002, 0, 0.105999999, 0)

	UICorner_12.Parent = NoOxygenDamageFrame

	NoOxygenText.Name = "NoOxygenText"
	NoOxygenText.Parent = NoOxygenDamageFrame
	NoOxygenText.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	NoOxygenText.BackgroundTransparency = 1.000
	NoOxygenText.BorderColor3 = Color3.fromRGB(0, 0, 0)
	NoOxygenText.BorderSizePixel = 0
	NoOxygenText.Position = UDim2.new(0.0296296291, 0, 0.216216221, 0)
	NoOxygenText.Size = UDim2.new(0, 112, 0, 21)
	NoOxygenText.Font = Enum.Font.SourceSansBold
	NoOxygenText.Text = "NO OXYGEN DAMAGE :"
	NoOxygenText.TextColor3 = Color3.fromRGB(255, 255, 255)
	NoOxygenText.TextSize = 14.000
	NoOxygenText.TextXAlignment = Enum.TextXAlignment.Left

	NoOxygenWarna.Name = "NoOxygenWarna"
	NoOxygenWarna.Parent = NoOxygenDamageFrame
	NoOxygenWarna.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	NoOxygenWarna.BorderColor3 = Color3.fromRGB(0, 0, 0)
	NoOxygenWarna.BorderSizePixel = 0
	NoOxygenWarna.Position = UDim2.new(0.718999982, 0, 0.135000005, 0)
	NoOxygenWarna.Size = UDim2.new(0.256999999, 0, 0.730000019, 0)

	UICorner_13.Parent = NoOxygenWarna

	NoOxygenButton.Name = "NoOxygenButton"
	NoOxygenButton.Parent = NoOxygenDamageFrame
	NoOxygenButton.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	NoOxygenButton.BackgroundTransparency = 1.000
	NoOxygenButton.BorderColor3 = Color3.fromRGB(0, 0, 0)
	NoOxygenButton.BorderSizePixel = 0
	NoOxygenButton.Position = UDim2.new(0.73773706, 0, 0.108108483, 0)
	NoOxygenButton.Size = UDim2.new(0.2074074, 0, 0.783783793, 0)
	NoOxygenButton.ZIndex = 2
	NoOxygenButton.Font = Enum.Font.SourceSansBold
	NoOxygenButton.Text = "OFF"
	NoOxygenButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	NoOxygenButton.TextScaled = true
	NoOxygenButton.TextSize = 14.000
	NoOxygenButton.TextWrapped = true

	UITextSizeConstraint_12.Parent = NoOxygenButton
	UITextSizeConstraint_12.MaxTextSize = 14

	UnlimitedJump.Name = "UnlimitedJump"
	UnlimitedJump.Parent = ListLayoutPlayerFrame
	UnlimitedJump.BackgroundColor3 = Color3.fromRGB(47, 47, 47)
	UnlimitedJump.BorderColor3 = Color3.fromRGB(0, 0, 0)
	UnlimitedJump.BorderSizePixel = 0
	UnlimitedJump.Position = UDim2.new(0.0404040329, 0, 0.272833079, 0)
	UnlimitedJump.Size = UDim2.new(0.898000002, 0, 0.105999999, 0)

	UICorner_14.Parent = UnlimitedJump

	UnlimitedJumpText.Name = "UnlimitedJumpText"
	UnlimitedJumpText.Parent = UnlimitedJump
	UnlimitedJumpText.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	UnlimitedJumpText.BackgroundTransparency = 1.000
	UnlimitedJumpText.BorderColor3 = Color3.fromRGB(0, 0, 0)
	UnlimitedJumpText.BorderSizePixel = 0
	UnlimitedJumpText.Position = UDim2.new(0.0296296291, 0, 0.216216221, 0)
	UnlimitedJumpText.Size = UDim2.new(0, 112, 0, 21)
	UnlimitedJumpText.Font = Enum.Font.SourceSansBold
	UnlimitedJumpText.Text = "Unlimited Jump :"
	UnlimitedJumpText.TextColor3 = Color3.fromRGB(255, 255, 255)
	UnlimitedJumpText.TextSize = 14.000
	UnlimitedJumpText.TextXAlignment = Enum.TextXAlignment.Left

	UnlimitedJumpWarna.Name = "UnlimitedJumpWarna"
	UnlimitedJumpWarna.Parent = UnlimitedJump
	UnlimitedJumpWarna.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	UnlimitedJumpWarna.BorderColor3 = Color3.fromRGB(0, 0, 0)
	UnlimitedJumpWarna.BorderSizePixel = 0
	UnlimitedJumpWarna.Position = UDim2.new(0.718999982, 0, 0.135000005, 0)
	UnlimitedJumpWarna.Size = UDim2.new(0.256999999, 0, 0.730000019, 0)

	UICorner_15.Parent = UnlimitedJumpWarna

	UnlimitedJumpButton.Name = "UnlimitedJumpButton"
	UnlimitedJumpButton.Parent = UnlimitedJump
	UnlimitedJumpButton.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	UnlimitedJumpButton.BackgroundTransparency = 1.000
	UnlimitedJumpButton.BorderColor3 = Color3.fromRGB(0, 0, 0)
	UnlimitedJumpButton.BorderSizePixel = 0
	UnlimitedJumpButton.Position = UDim2.new(0.73773706, 0, 0.108108483, 0)
	UnlimitedJumpButton.Size = UDim2.new(0.2074074, 0, 0.783783793, 0)
	UnlimitedJumpButton.ZIndex = 2
	UnlimitedJumpButton.Font = Enum.Font.SourceSansBold
	UnlimitedJumpButton.Text = "OFF"
	UnlimitedJumpButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	UnlimitedJumpButton.TextScaled = true
	UnlimitedJumpButton.TextSize = 14.000
	UnlimitedJumpButton.TextWrapped = true

	UITextSizeConstraint_13.Parent = UnlimitedJumpButton
	UITextSizeConstraint_13.MaxTextSize = 14

	WalkSpeedFrame.Name = "WalkSpeedFrame"
	WalkSpeedFrame.Parent = ListLayoutPlayerFrame
	WalkSpeedFrame.BackgroundColor3 = Color3.fromRGB(47, 47, 47)
	WalkSpeedFrame.BorderColor3 = Color3.fromRGB(0, 0, 0)
	WalkSpeedFrame.BorderSizePixel = 0
	WalkSpeedFrame.Position = UDim2.new(0.0437710434, 0, 0.0202609263, 0)
	WalkSpeedFrame.Size = UDim2.new(0.898000002, 0, 0.105999999, 0)

	UICorner_16.Parent = WalkSpeedFrame

	WalkSpeedText.Name = "WalkSpeedText"
	WalkSpeedText.Parent = WalkSpeedFrame
	WalkSpeedText.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	WalkSpeedText.BackgroundTransparency = 1.000
	WalkSpeedText.BorderColor3 = Color3.fromRGB(0, 0, 0)
	WalkSpeedText.BorderSizePixel = 0
	WalkSpeedText.Position = UDim2.new(0.0296296291, 0, 0.216216221, 0)
	WalkSpeedText.Size = UDim2.new(0.4148148, 0, 0.567567587, 0)
	WalkSpeedText.Font = Enum.Font.SourceSansBold
	WalkSpeedText.Text = "WALK SPEED:"
	WalkSpeedText.TextColor3 = Color3.fromRGB(255, 255, 255)
	WalkSpeedText.TextScaled = true
	WalkSpeedText.TextSize = 14.000
	WalkSpeedText.TextWrapped = true
	WalkSpeedText.TextXAlignment = Enum.TextXAlignment.Left

	UITextSizeConstraint_14.Parent = WalkSpeedText
	UITextSizeConstraint_14.MaxTextSize = 14

	WalkSpeedWarna.Name = "WalkSpeedWarna"
	WalkSpeedWarna.Parent = WalkSpeedFrame
	WalkSpeedWarna.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	WalkSpeedWarna.BorderColor3 = Color3.fromRGB(0, 0, 0)
	WalkSpeedWarna.BorderSizePixel = 0
	WalkSpeedWarna.Position = UDim2.new(0.718999982, 0, 0.135000005, 0)
	WalkSpeedWarna.Size = UDim2.new(0.256999999, 0, 0.730000019, 0)

	UICorner_17.Parent = WalkSpeedWarna

	WalkSpeedTextBox.Name = "WalkSpeedTextBox"
	WalkSpeedTextBox.Parent = WalkSpeedFrame
	WalkSpeedTextBox.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	WalkSpeedTextBox.BackgroundTransparency = 1.000
	WalkSpeedTextBox.BorderColor3 = Color3.fromRGB(0, 0, 0)
	WalkSpeedTextBox.BorderSizePixel = 0
	WalkSpeedTextBox.Position = UDim2.new(0.718999982, 0, 0.135000005, 0)
	WalkSpeedTextBox.Size = UDim2.new(0.256999999, 0, 0.730000019, 0)
	WalkSpeedTextBox.ZIndex = 3
	WalkSpeedTextBox.Font = Enum.Font.SourceSansBold
	WalkSpeedTextBox.PlaceholderColor3 = Color3.fromRGB(108, 108, 108)
	WalkSpeedTextBox.PlaceholderText = "18"
	WalkSpeedTextBox.Text = ""
	WalkSpeedTextBox.TextColor3 = Color3.fromRGB(253, 253, 253)
	WalkSpeedTextBox.TextScaled = true
	WalkSpeedTextBox.TextSize = 18.000
	WalkSpeedTextBox.TextWrapped = true

	UICorner_18.Parent = WalkSpeedTextBox

	UITextSizeConstraint_15.Parent = WalkSpeedTextBox
	UITextSizeConstraint_15.MaxTextSize = 18

	WalkSpeedFrameButton.Name = "WalkSpeedFrameButton"
	WalkSpeedFrameButton.Parent = ListLayoutPlayerFrame
	WalkSpeedFrameButton.BackgroundColor3 = Color3.fromRGB(47, 47, 47)
	WalkSpeedFrameButton.BorderColor3 = Color3.fromRGB(0, 0, 0)
	WalkSpeedFrameButton.BorderSizePixel = 0
	WalkSpeedFrameButton.Position = UDim2.new(0.658801138, 0, 0.249478042, 0)
	WalkSpeedFrameButton.Size = UDim2.new(0.289999992, 0, 0.0680000037, 0)

	UICorner_19.Parent = WalkSpeedFrameButton

	WalkSpeedAcceptText.Name = "WalkSpeedAcceptText"
	WalkSpeedAcceptText.Parent = WalkSpeedFrameButton
	WalkSpeedAcceptText.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	WalkSpeedAcceptText.BackgroundTransparency = 1.000
	WalkSpeedAcceptText.BorderColor3 = Color3.fromRGB(0, 0, 0)
	WalkSpeedAcceptText.BorderSizePixel = 0
	WalkSpeedAcceptText.Position = UDim2.new(0.0368366279, 0, -0.0509649925, 0)
	WalkSpeedAcceptText.Size = UDim2.new(0.967370987, 0, 0.943781316, 0)
	WalkSpeedAcceptText.Font = Enum.Font.SourceSansBold
	WalkSpeedAcceptText.Text = "SET WALKSPEED"
	WalkSpeedAcceptText.TextColor3 = Color3.fromRGB(255, 255, 255)
	WalkSpeedAcceptText.TextScaled = true
	WalkSpeedAcceptText.TextWrapped = true

	SetWalkSpeedButton.Name = "SetWalkSpeedButton"
	SetWalkSpeedButton.Parent = WalkSpeedFrameButton
	SetWalkSpeedButton.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	SetWalkSpeedButton.BackgroundTransparency = 1.000
	SetWalkSpeedButton.BorderColor3 = Color3.fromRGB(0, 0, 0)
	SetWalkSpeedButton.BorderSizePixel = 0
	SetWalkSpeedButton.Position = UDim2.new(0.111111112, 0, 0, 0)
	SetWalkSpeedButton.Size = UDim2.new(0.888888896, 0, 1, 0)
	SetWalkSpeedButton.Font = Enum.Font.SourceSans
	SetWalkSpeedButton.Text = ""
	SetWalkSpeedButton.TextColor3 = Color3.fromRGB(0, 0, 0)
	SetWalkSpeedButton.TextSize = 14.000

	UICorner_20.Parent = SetWalkSpeedButton

	UIAspectRatioConstraint.Parent = FrameUtama
	UIAspectRatioConstraint.AspectRatio = 1.245

	Teleport.Name = "Teleport"
	Teleport.Parent = FrameUtama
	Teleport.Active = true
	Teleport.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	Teleport.BackgroundTransparency = 1.000
	Teleport.BorderColor3 = Color3.fromRGB(0, 0, 0)
	Teleport.BorderSizePixel = 0
	Teleport.Position = UDim2.new(0.376050383, 0, 0.147492602, 0)
	Teleport.Size = UDim2.new(0.623949468, 0, 0.852507353, 0)
	Teleport.Visible = false
	Teleport.ZIndex = 2
	Teleport.ScrollBarThickness = 6

	TPEvent.Name = "TPEvent"
	TPEvent.Parent = Teleport
	TPEvent.BackgroundColor3 = Color3.fromRGB(47, 47, 47)
	TPEvent.BorderColor3 = Color3.fromRGB(0, 0, 0)
	TPEvent.BorderSizePixel = 0
	TPEvent.Position = UDim2.new(0.0437710434, 0, 0.209508449, 0)
	TPEvent.Size = UDim2.new(0.898000002, 0, 0.105999999, 0)

	UICorner_21.Parent = TPEvent

	TPEventText.Name = "TPEventText"
	TPEventText.Parent = TPEvent
	TPEventText.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	TPEventText.BackgroundTransparency = 1.000
	TPEventText.BorderColor3 = Color3.fromRGB(0, 0, 0)
	TPEventText.BorderSizePixel = 0
	TPEventText.Position = UDim2.new(0.0296296291, 0, 0.216216221, 0)
	TPEventText.Size = UDim2.new(0.4148148, 0, 0.567567587, 0)
	TPEventText.Font = Enum.Font.SourceSansBold
	TPEventText.Text = "TP EVENT :"
	TPEventText.TextColor3 = Color3.fromRGB(255, 255, 255)
	TPEventText.TextScaled = true
	TPEventText.TextSize = 14.000
	TPEventText.TextWrapped = true
	TPEventText.TextXAlignment = Enum.TextXAlignment.Left

	UIAspectRatioConstraint_2.Parent = TPEventText
	UIAspectRatioConstraint_2.AspectRatio = 5.641

	TPEventButton.Name = "TPEventButton"
	TPEventButton.Parent = TPEvent
	TPEventButton.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	TPEventButton.BackgroundTransparency = 1.000
	TPEventButton.BorderColor3 = Color3.fromRGB(0, 0, 0)
	TPEventButton.BorderSizePixel = 0
	TPEventButton.Position = UDim2.new(0.75555557, 0, 0.108108111, 0)
	TPEventButton.Size = UDim2.new(0.2074074, 0, 0.783783793, 0)
	TPEventButton.ZIndex = 2
	TPEventButton.Font = Enum.Font.SourceSansBold
	TPEventButton.Text = "V"
	TPEventButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	TPEventButton.TextScaled = true
	TPEventButton.TextSize = 14.000
	TPEventButton.TextWrapped = true

	UITextSizeConstraint_16.Parent = TPEventButton
	UITextSizeConstraint_16.MaxTextSize = 14

	TPEventButtonWarna.Name = "TPEventButtonWarna"
	TPEventButtonWarna.Parent = TPEvent
	TPEventButtonWarna.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	TPEventButtonWarna.BorderColor3 = Color3.fromRGB(0, 0, 0)
	TPEventButtonWarna.BorderSizePixel = 0
	TPEventButtonWarna.Position = UDim2.new(0.75555557, 0, 0.135135129, 0)
	TPEventButtonWarna.Size = UDim2.new(0.203703701, 0, 0.729729712, 0)

	UICorner_22.Parent = TPEventButtonWarna

	TPIsland.Name = "TPIsland"
	TPIsland.Parent = Teleport
	TPIsland.BackgroundColor3 = Color3.fromRGB(47, 47, 47)
	TPIsland.BorderColor3 = Color3.fromRGB(0, 0, 0)
	TPIsland.BorderSizePixel = 0
	TPIsland.Position = UDim2.new(0.0437708385, 0, 0.0418279432, 0)
	TPIsland.Size = UDim2.new(0.898138702, 0, 0.106191501, 0)

	UICorner_23.Parent = TPIsland

	TPIslandText.Name = "TPIslandText"
	TPIslandText.Parent = TPIsland
	TPIslandText.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	TPIslandText.BackgroundTransparency = 1.000
	TPIslandText.BorderColor3 = Color3.fromRGB(0, 0, 0)
	TPIslandText.BorderSizePixel = 0
	TPIslandText.Position = UDim2.new(0.0296296291, 0, 0.216216221, 0)
	TPIslandText.Size = UDim2.new(0.4148148, 0, 0.567567587, 0)
	TPIslandText.Font = Enum.Font.SourceSansBold
	TPIslandText.Text = "TP ISLAND :"
	TPIslandText.TextColor3 = Color3.fromRGB(255, 255, 255)
	TPIslandText.TextScaled = true
	TPIslandText.TextSize = 14.000
	TPIslandText.TextWrapped = true
	TPIslandText.TextXAlignment = Enum.TextXAlignment.Left

	UITextSizeConstraint_17.Parent = TPIslandText
	UITextSizeConstraint_17.MaxTextSize = 14

	TPIslandButton.Name = "TPIslandButton"
	TPIslandButton.Parent = TPIsland
	TPIslandButton.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	TPIslandButton.BackgroundTransparency = 1.000
	TPIslandButton.BorderColor3 = Color3.fromRGB(0, 0, 0)
	TPIslandButton.BorderSizePixel = 0
	TPIslandButton.Position = UDim2.new(0.75555557, 0, 0.108108111, 0)
	TPIslandButton.Size = UDim2.new(0.2074074, 0, 0.783783793, 0)
	TPIslandButton.ZIndex = 2
	TPIslandButton.Font = Enum.Font.SourceSansBold
	TPIslandButton.Text = "V"
	TPIslandButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	TPIslandButton.TextScaled = true
	TPIslandButton.TextSize = 14.000
	TPIslandButton.TextWrapped = true

	UITextSizeConstraint_18.Parent = TPIslandButton
	UITextSizeConstraint_18.MaxTextSize = 14

	TPIslandButtonWarna.Name = "TPIslandButtonWarna"
	TPIslandButtonWarna.Parent = TPIsland
	TPIslandButtonWarna.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	TPIslandButtonWarna.BorderColor3 = Color3.fromRGB(0, 0, 0)
	TPIslandButtonWarna.BorderSizePixel = 0
	TPIslandButtonWarna.Position = UDim2.new(0.75555557, 0, 0.135135129, 0)
	TPIslandButtonWarna.Size = UDim2.new(0.203703701, 0, 0.729729712, 0)

	UICorner_24.Parent = TPIslandButtonWarna

	ListOfTPIsland.Name = "ListOfTPIsland"
	ListOfTPIsland.Parent = Teleport
	ListOfTPIsland.Active = true
	ListOfTPIsland.BackgroundColor3 = Color3.fromRGB(34, 34, 34)
	ListOfTPIsland.BackgroundTransparency = 0.700
	ListOfTPIsland.BorderColor3 = Color3.fromRGB(0, 0, 0)
	ListOfTPIsland.BorderSizePixel = 0
	ListOfTPIsland.Position = UDim2.new(0.590924203, 0, 0.147147402, 0)
	ListOfTPIsland.Size = UDim2.new(0, 100, 0, 143)
	ListOfTPIsland.ZIndex = 3
	ListOfTPIsland.Visible = false
	ListOfTPIsland.AutomaticCanvasSize = Enum.AutomaticSize.Y

	TPPlayer.Name = "TPPlayer"
	TPPlayer.Parent = Teleport
	TPPlayer.BackgroundColor3 = Color3.fromRGB(47, 47, 47)
	TPPlayer.BorderColor3 = Color3.fromRGB(0, 0, 0)
	TPPlayer.BorderSizePixel = 0
	TPPlayer.Position = UDim2.new(0.0397706926, 0, 0.391719788, 0)
	TPPlayer.Size = UDim2.new(0.898000002, 0, 0.105999999, 0)

	UICorner_25.Parent = TPPlayer

	TPPlayerText.Name = "TPPlayerText"
	TPPlayerText.Parent = TPPlayer
	TPPlayerText.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	TPPlayerText.BackgroundTransparency = 1.000
	TPPlayerText.BorderColor3 = Color3.fromRGB(0, 0, 0)
	TPPlayerText.BorderSizePixel = 0
	TPPlayerText.Position = UDim2.new(0.0296296291, 0, 0.216216221, 0)
	TPPlayerText.Size = UDim2.new(0.4148148, 0, 0.567567587, 0)
	TPPlayerText.Font = Enum.Font.SourceSansBold
	TPPlayerText.Text = "TP PLAYER:"
	TPPlayerText.TextColor3 = Color3.fromRGB(255, 255, 255)
	TPPlayerText.TextScaled = true
	TPPlayerText.TextSize = 14.000
	TPPlayerText.TextWrapped = true
	TPPlayerText.TextXAlignment = Enum.TextXAlignment.Left

	UIAspectRatioConstraint_3.Parent = TPPlayerText
	UIAspectRatioConstraint_3.AspectRatio = 5.641

	TPPlayerButtonWarna.Name = "TPPlayerButtonWarna"
	TPPlayerButtonWarna.Parent = TPPlayer
	TPPlayerButtonWarna.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	TPPlayerButtonWarna.BorderColor3 = Color3.fromRGB(0, 0, 0)
	TPPlayerButtonWarna.BorderSizePixel = 0
	TPPlayerButtonWarna.Position = UDim2.new(0.75555557, 0, 0.135135129, 0)
	TPPlayerButtonWarna.Size = UDim2.new(0.203703701, 0, 0.729729712, 0)

	UICorner_26.Parent = TPPlayerButtonWarna

	TPPlayerButton.Name = "TPPlayerButton"
	TPPlayerButton.Parent = TPPlayer
	TPPlayerButton.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	TPPlayerButton.BackgroundTransparency = 1.000
	TPPlayerButton.BorderColor3 = Color3.fromRGB(0, 0, 0)
	TPPlayerButton.BorderSizePixel = 0
	TPPlayerButton.Position = UDim2.new(0.75555557, 0, 0.108108111, 0)
	TPPlayerButton.Size = UDim2.new(0.2074074, 0, 0.783783793, 0)
	TPPlayerButton.ZIndex = 2
	TPPlayerButton.Font = Enum.Font.SourceSansBold
	TPPlayerButton.Text = "V"
	TPPlayerButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	TPPlayerButton.TextScaled = true
	TPPlayerButton.TextSize = 14.000
	TPPlayerButton.TextWrapped = true

	UITextSizeConstraint_19.Parent = TPPlayerButton
	UITextSizeConstraint_19.MaxTextSize = 14

	ListOfTPEvent.Name = "ListOfTPEvent"
	ListOfTPEvent.Parent = Teleport
	ListOfTPEvent.Active = true
	ListOfTPEvent.BackgroundColor3 = Color3.fromRGB(34, 34, 34)
	ListOfTPEvent.BackgroundTransparency = 0.700
	ListOfTPEvent.BorderColor3 = Color3.fromRGB(0, 0, 0)
	ListOfTPEvent.BorderSizePixel = 0
	ListOfTPEvent.Position = UDim2.new(0.590924203, 0, 0.317240119, 0)
	ListOfTPEvent.Size = UDim2.new(0, 100, 0, 143)
	ListOfTPEvent.Visible = false
	ListOfTPEvent.AutomaticCanvasSize = Enum.AutomaticSize.Y

	ListOfTpPlayer.Name = "ListOfTpPlayer"
	ListOfTpPlayer.Parent = Teleport
	ListOfTpPlayer.Active = true
	ListOfTpPlayer.BackgroundColor3 = Color3.fromRGB(34, 34, 34)
	ListOfTpPlayer.BackgroundTransparency = 0.700
	ListOfTpPlayer.BorderColor3 = Color3.fromRGB(0, 0, 0)
	ListOfTpPlayer.BorderSizePixel = 0
	ListOfTpPlayer.Position = UDim2.new(0.584594965, 0, 0.495981604, 0)
	ListOfTpPlayer.Size = UDim2.new(0, 100, 0, 143)
	ListOfTpPlayer.Visible = false
	ListOfTpPlayer.AutomaticCanvasSize = Enum.AutomaticSize.Y

	SpawnBoatFrame.Name = "SpawnBoatFrame"
	SpawnBoatFrame.Parent = FrameUtama
	SpawnBoatFrame.Active = true
	SpawnBoatFrame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	SpawnBoatFrame.BackgroundTransparency = 1.000
	SpawnBoatFrame.BorderColor3 = Color3.fromRGB(0, 0, 0)
	SpawnBoatFrame.BorderSizePixel = 0
	SpawnBoatFrame.Position = UDim2.new(0.376050383, 0, 0.147492602, 0)
	SpawnBoatFrame.Size = UDim2.new(0.623949468, 0, 0.852507353, 0)
	SpawnBoatFrame.Visible = false
	SpawnBoatFrame.ZIndex = 2
	SpawnBoatFrame.ScrollBarThickness = 6
	SpawnBoatFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y

	ListLayoutBoatFrame.Name = "ListLayoutBoatFrame"
	ListLayoutBoatFrame.Parent = SpawnBoatFrame
	ListLayoutBoatFrame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	ListLayoutBoatFrame.BackgroundTransparency = 1.000
	ListLayoutBoatFrame.BorderColor3 = Color3.fromRGB(0, 0, 0)
	ListLayoutBoatFrame.BorderSizePixel = 0
	ListLayoutBoatFrame.Position = UDim2.new(0, 0, 0.0219183583, 0)
	ListLayoutBoatFrame.Size = UDim2.new(1, 0, 1, 0)

	ListLayoutBoat.Name = "ListLayoutBoat"
	ListLayoutBoat.Parent = ListLayoutBoatFrame
	ListLayoutBoat.HorizontalAlignment = Enum.HorizontalAlignment.Center
	ListLayoutBoat.SortOrder = Enum.SortOrder.LayoutOrder
	ListLayoutBoat.Padding = UDim.new(0, 8)

	DespawnBoat.Name = "DespawnBoat"
	DespawnBoat.Parent = ListLayoutBoatFrame
	DespawnBoat.BackgroundColor3 = Color3.fromRGB(47, 47, 47)
	DespawnBoat.BorderColor3 = Color3.fromRGB(0, 0, 0)
	DespawnBoat.BorderSizePixel = 0
	DespawnBoat.Position = UDim2.new(0.0437708385, 0, 0.0418279432, 0)
	DespawnBoat.Size = UDim2.new(0.898138702, 0, 0.106191501, 0)

	UICorner_27.Parent = DespawnBoat

	DespawnBoatText.Name = "DespawnBoatText"
	DespawnBoatText.Parent = DespawnBoat
	DespawnBoatText.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	DespawnBoatText.BackgroundTransparency = 1.000
	DespawnBoatText.BorderColor3 = Color3.fromRGB(0, 0, 0)
	DespawnBoatText.BorderSizePixel = 0
	DespawnBoatText.Position = UDim2.new(0.0120122591, 0, 0.216216043, 0)
	DespawnBoatText.Size = UDim2.new(0.970370531, 0, 0.567567527, 0)
	DespawnBoatText.Font = Enum.Font.SourceSansBold
	DespawnBoatText.Text = "Despawn Boat"
	DespawnBoatText.TextColor3 = Color3.fromRGB(255, 255, 255)
	DespawnBoatText.TextScaled = true
	DespawnBoatText.TextSize = 14.000
	DespawnBoatText.TextWrapped = true

	UITextSizeConstraint_20.Parent = DespawnBoatText
	UITextSizeConstraint_20.MaxTextSize = 14

	DespawnBoatButton.Name = "DespawnBoatButton"
	DespawnBoatButton.Parent = DespawnBoat
	DespawnBoatButton.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	DespawnBoatButton.BackgroundTransparency = 1.000
	DespawnBoatButton.BorderColor3 = Color3.fromRGB(0, 0, 0)
	DespawnBoatButton.BorderSizePixel = 0
	DespawnBoatButton.Size = UDim2.new(1, 0, 1, 0)
	DespawnBoatButton.ZIndex = 2
	DespawnBoatButton.Font = Enum.Font.SourceSansBold
	DespawnBoatButton.Text = ""
	DespawnBoatButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	DespawnBoatButton.TextScaled = true
	DespawnBoatButton.TextSize = 14.000
	DespawnBoatButton.TextWrapped = true

	UITextSizeConstraint_21.Parent = DespawnBoatButton
	UITextSizeConstraint_21.MaxTextSize = 14

	SmallBoat.Name = "SmallBoat"
	SmallBoat.Parent = ListLayoutBoatFrame
	SmallBoat.BackgroundColor3 = Color3.fromRGB(47, 47, 47)
	SmallBoat.BorderColor3 = Color3.fromRGB(0, 0, 0)
	SmallBoat.BorderSizePixel = 0
	SmallBoat.Position = UDim2.new(0.0437710434, 0, 0.209508449, 0)
	SmallBoat.Size = UDim2.new(0.898000002, 0, 0.105999999, 0)

	UICorner_28.Parent = SmallBoat

	SmallBoatButton.Name = "SmallBoatButton"
	SmallBoatButton.Parent = SmallBoat
	SmallBoatButton.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	SmallBoatButton.BackgroundTransparency = 1.000
	SmallBoatButton.BorderColor3 = Color3.fromRGB(0, 0, 0)
	SmallBoatButton.BorderSizePixel = 0
	SmallBoatButton.Size = UDim2.new(1, 0, 1, 0)
	SmallBoatButton.ZIndex = 2
	SmallBoatButton.Font = Enum.Font.SourceSansBold
	SmallBoatButton.Text = ""
	SmallBoatButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	SmallBoatButton.TextSize = 14.000

	SmallBoatText.Name = "SmallBoatText"
	SmallBoatText.Parent = SmallBoat
	SmallBoatText.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	SmallBoatText.BackgroundTransparency = 1.000
	SmallBoatText.BorderColor3 = Color3.fromRGB(0, 0, 0)
	SmallBoatText.BorderSizePixel = 0
	SmallBoatText.Position = UDim2.new(0.286885142, 0, 0.216216132, 0)
	SmallBoatText.Size = UDim2.new(0.4148148, 0, 0.567567587, 0)
	SmallBoatText.Font = Enum.Font.SourceSansBold
	SmallBoatText.Text = "Small Boat"
	SmallBoatText.TextColor3 = Color3.fromRGB(255, 255, 255)
	SmallBoatText.TextScaled = true
	SmallBoatText.TextSize = 14.000
	SmallBoatText.TextWrapped = true

	KayakBoat.Name = "KayakBoat"
	KayakBoat.Parent = ListLayoutBoatFrame
	KayakBoat.BackgroundColor3 = Color3.fromRGB(47, 47, 47)
	KayakBoat.BorderColor3 = Color3.fromRGB(0, 0, 0)
	KayakBoat.BorderSizePixel = 0
	KayakBoat.Position = UDim2.new(0.0437710434, 0, 0.209508449, 0)
	KayakBoat.Size = UDim2.new(0.898000002, 0, 0.105999999, 0)

	UICorner_29.Parent = KayakBoat

	KayakBoatButton.Name = "KayakBoatButton"
	KayakBoatButton.Parent = KayakBoat
	KayakBoatButton.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	KayakBoatButton.BackgroundTransparency = 1.000
	KayakBoatButton.BorderColor3 = Color3.fromRGB(0, 0, 0)
	KayakBoatButton.BorderSizePixel = 0
	KayakBoatButton.Size = UDim2.new(1, 0, 1, 0)
	KayakBoatButton.ZIndex = 2
	KayakBoatButton.Font = Enum.Font.SourceSansBold
	KayakBoatButton.Text = ""
	KayakBoatButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	KayakBoatButton.TextSize = 14.000

	KayakBoatText.Name = "KayakBoatText"
	KayakBoatText.Parent = KayakBoat
	KayakBoatText.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	KayakBoatText.BackgroundTransparency = 1.000
	KayakBoatText.BorderColor3 = Color3.fromRGB(0, 0, 0)
	KayakBoatText.BorderSizePixel = 0
	KayakBoatText.Position = UDim2.new(0.286885142, 0, 0.216216132, 0)
	KayakBoatText.Size = UDim2.new(0.4148148, 0, 0.567567587, 0)
	KayakBoatText.Font = Enum.Font.SourceSansBold
	KayakBoatText.Text = "Kayak"
	KayakBoatText.TextColor3 = Color3.fromRGB(255, 255, 255)
	KayakBoatText.TextScaled = true
	KayakBoatText.TextSize = 14.000
	KayakBoatText.TextWrapped = true

	JetskiBoat.Name = "JetskiBoat"
	JetskiBoat.Parent = ListLayoutBoatFrame
	JetskiBoat.BackgroundColor3 = Color3.fromRGB(47, 47, 47)
	JetskiBoat.BorderColor3 = Color3.fromRGB(0, 0, 0)
	JetskiBoat.BorderSizePixel = 0
	JetskiBoat.Position = UDim2.new(0.0437710434, 0, 0.209508449, 0)
	JetskiBoat.Size = UDim2.new(0.898000002, 0, 0.105999999, 0)

	UICorner_30.Parent = JetskiBoat

	JetskiBoatButton.Name = "JetskiBoatButton"
	JetskiBoatButton.Parent = JetskiBoat
	JetskiBoatButton.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	JetskiBoatButton.BackgroundTransparency = 1.000
	JetskiBoatButton.BorderColor3 = Color3.fromRGB(0, 0, 0)
	JetskiBoatButton.BorderSizePixel = 0
	JetskiBoatButton.Size = UDim2.new(1, 0, 1, 0)
	JetskiBoatButton.ZIndex = 2
	JetskiBoatButton.Font = Enum.Font.SourceSansBold
	JetskiBoatButton.Text = ""
	JetskiBoatButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	JetskiBoatButton.TextSize = 14.000

	JetskiBoatText.Name = "JetskiBoatText"
	JetskiBoatText.Parent = JetskiBoat
	JetskiBoatText.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	JetskiBoatText.BackgroundTransparency = 1.000
	JetskiBoatText.BorderColor3 = Color3.fromRGB(0, 0, 0)
	JetskiBoatText.BorderSizePixel = 0
	JetskiBoatText.Position = UDim2.new(0.286885142, 0, 0.216216132, 0)
	JetskiBoatText.Size = UDim2.new(0.4148148, 0, 0.567567587, 0)
	JetskiBoatText.Font = Enum.Font.SourceSansBold
	JetskiBoatText.Text = "Jetski"
	JetskiBoatText.TextColor3 = Color3.fromRGB(255, 255, 255)
	JetskiBoatText.TextScaled = true
	JetskiBoatText.TextSize = 14.000
	JetskiBoatText.TextWrapped = true

	HighfieldBoat.Name = "HighfieldBoat"
	HighfieldBoat.Parent = ListLayoutBoatFrame
	HighfieldBoat.BackgroundColor3 = Color3.fromRGB(47, 47, 47)
	HighfieldBoat.BorderColor3 = Color3.fromRGB(0, 0, 0)
	HighfieldBoat.BorderSizePixel = 0
	HighfieldBoat.Position = UDim2.new(0.0437710434, 0, 0.209508449, 0)
	HighfieldBoat.Size = UDim2.new(0.898000002, 0, 0.105999999, 0)

	UICorner_31.Parent = HighfieldBoat

	HighfieldBoatButton.Name = "HighfieldBoatButton"
	HighfieldBoatButton.Parent = HighfieldBoat
	HighfieldBoatButton.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	HighfieldBoatButton.BackgroundTransparency = 1.000
	HighfieldBoatButton.BorderColor3 = Color3.fromRGB(0, 0, 0)
	HighfieldBoatButton.BorderSizePixel = 0
	HighfieldBoatButton.Size = UDim2.new(1, 0, 1, 0)
	HighfieldBoatButton.ZIndex = 2
	HighfieldBoatButton.Font = Enum.Font.SourceSansBold
	HighfieldBoatButton.Text = ""
	HighfieldBoatButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	HighfieldBoatButton.TextSize = 14.000

	HighfieldBoatText.Name = "HighfieldBoatText"
	HighfieldBoatText.Parent = HighfieldBoat
	HighfieldBoatText.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	HighfieldBoatText.BackgroundTransparency = 1.000
	HighfieldBoatText.BorderColor3 = Color3.fromRGB(0, 0, 0)
	HighfieldBoatText.BorderSizePixel = 0
	HighfieldBoatText.Position = UDim2.new(0.286885142, 0, 0.216216132, 0)
	HighfieldBoatText.Size = UDim2.new(0.4148148, 0, 0.567567587, 0)
	HighfieldBoatText.Font = Enum.Font.SourceSansBold
	HighfieldBoatText.Text = "Highfield Boat"
	HighfieldBoatText.TextColor3 = Color3.fromRGB(255, 255, 255)
	HighfieldBoatText.TextScaled = true
	HighfieldBoatText.TextSize = 14.000
	HighfieldBoatText.TextWrapped = true

	SpeedBoat.Name = "SpeedBoat"
	SpeedBoat.Parent = ListLayoutBoatFrame
	SpeedBoat.BackgroundColor3 = Color3.fromRGB(47, 47, 47)
	SpeedBoat.BorderColor3 = Color3.fromRGB(0, 0, 0)
	SpeedBoat.BorderSizePixel = 0
	SpeedBoat.Position = UDim2.new(0.0437710434, 0, 0.209508449, 0)
	SpeedBoat.Size = UDim2.new(0.898000002, 0, 0.105999999, 0)

	UICorner_32.Parent = SpeedBoat

	SpeedBoatButton.Name = "SpeedBoatButton"
	SpeedBoatButton.Parent = SpeedBoat
	SpeedBoatButton.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	SpeedBoatButton.BackgroundTransparency = 1.000
	SpeedBoatButton.BorderColor3 = Color3.fromRGB(0, 0, 0)
	SpeedBoatButton.BorderSizePixel = 0
	SpeedBoatButton.Size = UDim2.new(1, 0, 1, 0)
	SpeedBoatButton.ZIndex = 2
	SpeedBoatButton.Font = Enum.Font.SourceSansBold
	SpeedBoatButton.Text = ""
	SpeedBoatButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	SpeedBoatButton.TextSize = 14.000

	SpeedBoatText.Name = "SpeedBoatText"
	SpeedBoatText.Parent = SpeedBoat
	SpeedBoatText.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	SpeedBoatText.BackgroundTransparency = 1.000
	SpeedBoatText.BorderColor3 = Color3.fromRGB(0, 0, 0)
	SpeedBoatText.BorderSizePixel = 0
	SpeedBoatText.Position = UDim2.new(0.286885142, 0, 0.216216132, 0)
	SpeedBoatText.Size = UDim2.new(0.4148148, 0, 0.567567587, 0)
	SpeedBoatText.Font = Enum.Font.SourceSansBold
	SpeedBoatText.Text = "Speed Boat"
	SpeedBoatText.TextColor3 = Color3.fromRGB(255, 255, 255)
	SpeedBoatText.TextScaled = true
	SpeedBoatText.TextSize = 14.000
	SpeedBoatText.TextWrapped = true

	FishingBoat.Name = "FishingBoat"
	FishingBoat.Parent = ListLayoutBoatFrame
	FishingBoat.BackgroundColor3 = Color3.fromRGB(47, 47, 47)
	FishingBoat.BorderColor3 = Color3.fromRGB(0, 0, 0)
	FishingBoat.BorderSizePixel = 0
	FishingBoat.Position = UDim2.new(0.0437710434, 0, 0.209508449, 0)
	FishingBoat.Size = UDim2.new(0.898000002, 0, 0.105999999, 0)

	UICorner_33.Parent = FishingBoat

	FishingBoatButton.Name = "FishingBoatButton"
	FishingBoatButton.Parent = FishingBoat
	FishingBoatButton.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	FishingBoatButton.BackgroundTransparency = 1.000
	FishingBoatButton.BorderColor3 = Color3.fromRGB(0, 0, 0)
	FishingBoatButton.BorderSizePixel = 0
	FishingBoatButton.Size = UDim2.new(1, 0, 1, 0)
	FishingBoatButton.ZIndex = 2
	FishingBoatButton.Font = Enum.Font.SourceSansBold
	FishingBoatButton.Text = ""
	FishingBoatButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	FishingBoatButton.TextSize = 14.000

	FishingBoatText.Name = "FishingBoatText"
	FishingBoatText.Parent = FishingBoat
	FishingBoatText.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	FishingBoatText.BackgroundTransparency = 1.000
	FishingBoatText.BorderColor3 = Color3.fromRGB(0, 0, 0)
	FishingBoatText.BorderSizePixel = 0
	FishingBoatText.Position = UDim2.new(0.286885142, 0, 0.216216132, 0)
	FishingBoatText.Size = UDim2.new(0.4148148, 0, 0.567567587, 0)
	FishingBoatText.Font = Enum.Font.SourceSansBold
	FishingBoatText.Text = "Fishing Boat"
	FishingBoatText.TextColor3 = Color3.fromRGB(255, 255, 255)
	FishingBoatText.TextScaled = true
	FishingBoatText.TextSize = 14.000
	FishingBoatText.TextWrapped = true

	MiniYacht.Name = "MiniYacht"
	MiniYacht.Parent = ListLayoutBoatFrame
	MiniYacht.BackgroundColor3 = Color3.fromRGB(47, 47, 47)
	MiniYacht.BorderColor3 = Color3.fromRGB(0, 0, 0)
	MiniYacht.BorderSizePixel = 0
	MiniYacht.Position = UDim2.new(0.0437710434, 0, 0.209508449, 0)
	MiniYacht.Size = UDim2.new(0.898000002, 0, 0.105999999, 0)

	UICorner_34.Parent = MiniYacht

	MiniYachtButton.Name = "MiniYachtButton"
	MiniYachtButton.Parent = MiniYacht
	MiniYachtButton.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	MiniYachtButton.BackgroundTransparency = 1.000
	MiniYachtButton.BorderColor3 = Color3.fromRGB(0, 0, 0)
	MiniYachtButton.BorderSizePixel = 0
	MiniYachtButton.Size = UDim2.new(1, 0, 1, 0)
	MiniYachtButton.ZIndex = 2
	MiniYachtButton.Font = Enum.Font.SourceSansBold
	MiniYachtButton.Text = ""
	MiniYachtButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	MiniYachtButton.TextSize = 14.000

	MiniYachtText.Name = "MiniYachtText"
	MiniYachtText.Parent = MiniYacht
	MiniYachtText.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	MiniYachtText.BackgroundTransparency = 1.000
	MiniYachtText.BorderColor3 = Color3.fromRGB(0, 0, 0)
	MiniYachtText.BorderSizePixel = 0
	MiniYachtText.Position = UDim2.new(0.286885142, 0, 0.216216132, 0)
	MiniYachtText.Size = UDim2.new(0.4148148, 0, 0.567567587, 0)
	MiniYachtText.Font = Enum.Font.SourceSansBold
	MiniYachtText.Text = "Mini Yacht"
	MiniYachtText.TextColor3 = Color3.fromRGB(255, 255, 255)
	MiniYachtText.TextScaled = true
	MiniYachtText.TextSize = 14.000
	MiniYachtText.TextWrapped = true

	HyperBoat.Name = "HyperBoat"
	HyperBoat.Parent = ListLayoutBoatFrame
	HyperBoat.BackgroundColor3 = Color3.fromRGB(47, 47, 47)
	HyperBoat.BorderColor3 = Color3.fromRGB(0, 0, 0)
	HyperBoat.BorderSizePixel = 0
	HyperBoat.Position = UDim2.new(0.0437710434, 0, 0.209508449, 0)
	HyperBoat.Size = UDim2.new(0.898000002, 0, 0.105999999, 0)

	UICorner_35.Parent = HyperBoat

	HyperBoatButton.Name = "HyperBoatButton"
	HyperBoatButton.Parent = HyperBoat
	HyperBoatButton.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	HyperBoatButton.BackgroundTransparency = 1.000
	HyperBoatButton.BorderColor3 = Color3.fromRGB(0, 0, 0)
	HyperBoatButton.BorderSizePixel = 0
	HyperBoatButton.Size = UDim2.new(1, 0, 1, 0)
	HyperBoatButton.ZIndex = 2
	HyperBoatButton.Font = Enum.Font.SourceSansBold
	HyperBoatButton.Text = ""
	HyperBoatButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	HyperBoatButton.TextSize = 14.000

	HyperBoatText.Name = "HyperBoatText"
	HyperBoatText.Parent = HyperBoat
	HyperBoatText.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	HyperBoatText.BackgroundTransparency = 1.000
	HyperBoatText.BorderColor3 = Color3.fromRGB(0, 0, 0)
	HyperBoatText.BorderSizePixel = 0
	HyperBoatText.Position = UDim2.new(0.286885142, 0, 0.216216132, 0)
	HyperBoatText.Size = UDim2.new(0.4148148, 0, 0.567567587, 0)
	HyperBoatText.Font = Enum.Font.SourceSansBold
	HyperBoatText.Text = "Hyper Boat"
	HyperBoatText.TextColor3 = Color3.fromRGB(255, 255, 255)
	HyperBoatText.TextScaled = true
	HyperBoatText.TextSize = 14.000
	HyperBoatText.TextWrapped = true

	FrozenBoat.Name = "FrozenBoat"
	FrozenBoat.Parent = ListLayoutBoatFrame
	FrozenBoat.BackgroundColor3 = Color3.fromRGB(47, 47, 47)
	FrozenBoat.BorderColor3 = Color3.fromRGB(0, 0, 0)
	FrozenBoat.BorderSizePixel = 0
	FrozenBoat.Position = UDim2.new(0.0437710434, 0, 0.209508449, 0)
	FrozenBoat.Size = UDim2.new(0.898000002, 0, 0.105999999, 0)

	UICorner_36.Parent = FrozenBoat

	FrozenBoatButton.Name = "FrozenBoatButton"
	FrozenBoatButton.Parent = FrozenBoat
	FrozenBoatButton.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	FrozenBoatButton.BackgroundTransparency = 1.000
	FrozenBoatButton.BorderColor3 = Color3.fromRGB(0, 0, 0)
	FrozenBoatButton.BorderSizePixel = 0
	FrozenBoatButton.Size = UDim2.new(1, 0, 1, 0)
	FrozenBoatButton.ZIndex = 2
	FrozenBoatButton.Font = Enum.Font.SourceSansBold
	FrozenBoatButton.Text = ""
	FrozenBoatButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	FrozenBoatButton.TextSize = 14.000

	FrozenBoatText.Name = "FrozenBoatText"
	FrozenBoatText.Parent = FrozenBoat
	FrozenBoatText.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	FrozenBoatText.BackgroundTransparency = 1.000
	FrozenBoatText.BorderColor3 = Color3.fromRGB(0, 0, 0)
	FrozenBoatText.BorderSizePixel = 0
	FrozenBoatText.Position = UDim2.new(0.286885142, 0, 0.216216132, 0)
	FrozenBoatText.Size = UDim2.new(0.4148148, 0, 0.567567587, 0)
	FrozenBoatText.Font = Enum.Font.SourceSansBold
	FrozenBoatText.Text = "Frozen Boat"
	FrozenBoatText.TextColor3 = Color3.fromRGB(255, 255, 255)
	FrozenBoatText.TextScaled = true
	FrozenBoatText.TextSize = 14.000
	FrozenBoatText.TextWrapped = true

	CruiserBoat.Name = "CruiserBoat"
	CruiserBoat.Parent = ListLayoutBoatFrame
	CruiserBoat.BackgroundColor3 = Color3.fromRGB(47, 47, 47)
	CruiserBoat.BorderColor3 = Color3.fromRGB(0, 0, 0)
	CruiserBoat.BorderSizePixel = 0
	CruiserBoat.Position = UDim2.new(0.0437710434, 0, 0.209508449, 0)
	CruiserBoat.Size = UDim2.new(0.898000002, 0, 0.105999999, 0)

	UICorner_37.Parent = CruiserBoat

	CruiserBoatButton.Name = "CruiserBoatButton"
	CruiserBoatButton.Parent = CruiserBoat
	CruiserBoatButton.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	CruiserBoatButton.BackgroundTransparency = 1.000
	CruiserBoatButton.BorderColor3 = Color3.fromRGB(0, 0, 0)
	CruiserBoatButton.BorderSizePixel = 0
	CruiserBoatButton.Size = UDim2.new(1, 0, 1, 0)
	CruiserBoatButton.ZIndex = 2
	CruiserBoatButton.Font = Enum.Font.SourceSansBold
	CruiserBoatButton.Text = ""
	CruiserBoatButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	CruiserBoatButton.TextSize = 14.000

	CruiserBoatText.Name = "CruiserBoatText"
	CruiserBoatText.Parent = CruiserBoat
	CruiserBoatText.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	CruiserBoatText.BackgroundTransparency = 1.000
	CruiserBoatText.BorderColor3 = Color3.fromRGB(0, 0, 0)
	CruiserBoatText.BorderSizePixel = 0
	CruiserBoatText.Position = UDim2.new(0.286885142, 0, 0.216216132, 0)
	CruiserBoatText.Size = UDim2.new(0.4148148, 0, 0.567567587, 0)
	CruiserBoatText.Font = Enum.Font.SourceSansBold
	CruiserBoatText.Text = "Cruiser Boat"
	CruiserBoatText.TextColor3 = Color3.fromRGB(255, 255, 255)
	CruiserBoatText.TextScaled = true
	CruiserBoatText.TextSize = 14.000
	CruiserBoatText.TextWrapped = true

	AlphaFloaty.Name = "AlphaFloaty"
	AlphaFloaty.Parent = ListLayoutBoatFrame
	AlphaFloaty.BackgroundColor3 = Color3.fromRGB(47, 47, 47)
	AlphaFloaty.BorderColor3 = Color3.fromRGB(0, 0, 0)
	AlphaFloaty.BorderSizePixel = 0
	AlphaFloaty.Position = UDim2.new(0.0437710434, 0, 0.209508449, 0)
	AlphaFloaty.Size = UDim2.new(0.898000002, 0, 0.105999999, 0)

	UICorner_38.Parent = AlphaFloaty

	AlphaFloatyButton.Name = "AlphaFloatyButton"
	AlphaFloatyButton.Parent = AlphaFloaty
	AlphaFloatyButton.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	AlphaFloatyButton.BackgroundTransparency = 1.000
	AlphaFloatyButton.BorderColor3 = Color3.fromRGB(0, 0, 0)
	AlphaFloatyButton.BorderSizePixel = 0
	AlphaFloatyButton.Size = UDim2.new(1, 0, 1, 0)
	AlphaFloatyButton.ZIndex = 2
	AlphaFloatyButton.Font = Enum.Font.SourceSansBold
	AlphaFloatyButton.Text = ""
	AlphaFloatyButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	AlphaFloatyButton.TextSize = 14.000

	AlphaFloatyText.Name = "AlphaFloatyText"
	AlphaFloatyText.Parent = AlphaFloaty
	AlphaFloatyText.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	AlphaFloatyText.BackgroundTransparency = 1.000
	AlphaFloatyText.BorderColor3 = Color3.fromRGB(0, 0, 0)
	AlphaFloatyText.BorderSizePixel = 0
	AlphaFloatyText.Position = UDim2.new(0.286885142, 0, 0.216216132, 0)
	AlphaFloatyText.Size = UDim2.new(0.4148148, 0, 0.567567587, 0)
	AlphaFloatyText.Font = Enum.Font.SourceSansBold
	AlphaFloatyText.Text = "Alpha Floaty"
	AlphaFloatyText.TextColor3 = Color3.fromRGB(255, 255, 255)
	AlphaFloatyText.TextScaled = true
	AlphaFloatyText.TextSize = 14.000
	AlphaFloatyText.TextWrapped = true

	EvilDuck.Name = "EvilDuck"
	EvilDuck.Parent = ListLayoutBoatFrame
	EvilDuck.BackgroundColor3 = Color3.fromRGB(47, 47, 47)
	EvilDuck.BorderColor3 = Color3.fromRGB(0, 0, 0)
	EvilDuck.BorderSizePixel = 0
	EvilDuck.Position = UDim2.new(0.0437710434, 0, 0.209508449, 0)
	EvilDuck.Size = UDim2.new(0.898000002, 0, 0.105999999, 0)

	UICorner_39.Parent = EvilDuck

	EvilDuckButton.Name = "EvilDuckButton"
	EvilDuckButton.Parent = EvilDuck
	EvilDuckButton.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	EvilDuckButton.BackgroundTransparency = 1.000
	EvilDuckButton.BorderColor3 = Color3.fromRGB(0, 0, 0)
	EvilDuckButton.BorderSizePixel = 0
	EvilDuckButton.Size = UDim2.new(1, 0, 1, 0)
	EvilDuckButton.ZIndex = 2
	EvilDuckButton.Font = Enum.Font.SourceSansBold
	EvilDuckButton.Text = ""
	EvilDuckButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	EvilDuckButton.TextSize = 14.000

	EvilDuckText.Name = "EvilDuckText"
	EvilDuckText.Parent = EvilDuck
	EvilDuckText.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	EvilDuckText.BackgroundTransparency = 1.000
	EvilDuckText.BorderColor3 = Color3.fromRGB(0, 0, 0)
	EvilDuckText.BorderSizePixel = 0
	EvilDuckText.Position = UDim2.new(0.286885142, 0, 0.216216132, 0)
	EvilDuckText.Size = UDim2.new(0.4148148, 0, 0.567567587, 0)
	EvilDuckText.Font = Enum.Font.SourceSansBold
	EvilDuckText.Text = "DEV Evil Duck 9000"
	EvilDuckText.TextColor3 = Color3.fromRGB(255, 255, 255)
	EvilDuckText.TextScaled = true
	EvilDuckText.TextSize = 14.000
	EvilDuckText.TextWrapped = true

	FestiveDuck.Name = "FestiveDuck"
	FestiveDuck.Parent = ListLayoutBoatFrame
	FestiveDuck.BackgroundColor3 = Color3.fromRGB(47, 47, 47)
	FestiveDuck.BorderColor3 = Color3.fromRGB(0, 0, 0)
	FestiveDuck.BorderSizePixel = 0
	FestiveDuck.Position = UDim2.new(0.0437710434, 0, 0.209508449, 0)
	FestiveDuck.Size = UDim2.new(0.898000002, 0, 0.105999999, 0)

	UICorner_40.Parent = FestiveDuck

	FestiveDuckButton.Name = "FestiveDuckButton"
	FestiveDuckButton.Parent = FestiveDuck
	FestiveDuckButton.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	FestiveDuckButton.BackgroundTransparency = 1.000
	FestiveDuckButton.BorderColor3 = Color3.fromRGB(0, 0, 0)
	FestiveDuckButton.BorderSizePixel = 0
	FestiveDuckButton.Size = UDim2.new(1, 0, 1, 0)
	FestiveDuckButton.ZIndex = 2
	FestiveDuckButton.Font = Enum.Font.SourceSansBold
	FestiveDuckButton.Text = ""
	FestiveDuckButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	FestiveDuckButton.TextSize = 14.000

	FestiveDuckText.Name = "FestiveDuckText"
	FestiveDuckText.Parent = FestiveDuck
	FestiveDuckText.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	FestiveDuckText.BackgroundTransparency = 1.000
	FestiveDuckText.BorderColor3 = Color3.fromRGB(0, 0, 0)
	FestiveDuckText.BorderSizePixel = 0
	FestiveDuckText.Position = UDim2.new(0.286885142, 0, 0.216216132, 0)
	FestiveDuckText.Size = UDim2.new(0.4148148, 0, 0.567567587, 0)
	FestiveDuckText.Font = Enum.Font.SourceSansBold
	FestiveDuckText.Text = "Festive Duck"
	FestiveDuckText.TextColor3 = Color3.fromRGB(255, 255, 255)
	FestiveDuckText.TextScaled = true
	FestiveDuckText.TextSize = 14.000
	FestiveDuckText.TextWrapped = true

	SantaSleigh.Name = "SantaSleigh"
	SantaSleigh.Parent = ListLayoutBoatFrame
	SantaSleigh.BackgroundColor3 = Color3.fromRGB(47, 47, 47)
	SantaSleigh.BorderColor3 = Color3.fromRGB(0, 0, 0)
	SantaSleigh.BorderSizePixel = 0
	SantaSleigh.Position = UDim2.new(0.0437710434, 0, 0.209508449, 0)
	SantaSleigh.Size = UDim2.new(0.898000002, 0, 0.105999999, 0)

	UICorner_41.Parent = SantaSleigh

	SantaSleighButton.Name = "SantaSleighButton"
	SantaSleighButton.Parent = SantaSleigh
	SantaSleighButton.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	SantaSleighButton.BackgroundTransparency = 1.000
	SantaSleighButton.BorderColor3 = Color3.fromRGB(0, 0, 0)
	SantaSleighButton.BorderSizePixel = 0
	SantaSleighButton.Size = UDim2.new(1, 0, 1, 0)
	SantaSleighButton.ZIndex = 2
	SantaSleighButton.Font = Enum.Font.SourceSansBold
	SantaSleighButton.Text = ""
	SantaSleighButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	SantaSleighButton.TextSize = 14.000

	SantaSleighText.Name = "SantaSleighText"
	SantaSleighText.Parent = SantaSleigh
	SantaSleighText.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	SantaSleighText.BackgroundTransparency = 1.000
	SantaSleighText.BorderColor3 = Color3.fromRGB(0, 0, 0)
	SantaSleighText.BorderSizePixel = 0
	SantaSleighText.Position = UDim2.new(0.286885142, 0, 0.216216132, 0)
	SantaSleighText.Size = UDim2.new(0.4148148, 0, 0.567567587, 0)
	SantaSleighText.Font = Enum.Font.SourceSansBold
	SantaSleighText.Text = "Santa Sleigh"
	SantaSleighText.TextColor3 = Color3.fromRGB(255, 255, 255)
	SantaSleighText.TextScaled = true
	SantaSleighText.TextSize = 14.000
	SantaSleighText.TextWrapped = true

	-- All variables already defined above, continuing with functions...

	-- UI State Management
	local isOpen = {
		Island = false,
		Player = false,
		Event = false,
	}
	
	-- Cleanup function
	local function cleanup()
		for _, connection in pairs(connections) do
			if connection then
				connection:Disconnect()
			end
		end
		
		for _, thread in pairs(threads) do
			if thread then
				task.cancel(thread)
			end
		end
		
		connections = {}
		threads = {}
	end

	-- Minimize/Maximize Functions
	local function minimizeGUI()
		State.isMinimized = true
		FrameUtama.Visible = false
		FloatingIcon.Visible = true
		
		-- Add floating animation
		local tweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		local tween = TweenService:Create(FloatingIcon, tweenInfo, {
			Size = UDim2.new(0, 60, 0, 60),
			BackgroundTransparency = 0.1
		})
		tween:Play()

		-- Start pulsing effect
		local pulseThread = task.spawn(function()
			while State.isMinimized do
				local pulseIn = TweenService:Create(FloatingStroke, 
					TweenInfo.new(1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), 
					{Thickness = 4}
				)
				local pulseOut = TweenService:Create(FloatingStroke, 
					TweenInfo.new(1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), 
					{Thickness = 2}
				)
				
				pulseIn:Play()
				pulseIn.Completed:Wait()
				if not State.isMinimized then break end
				pulseOut:Play()
				pulseOut.Completed:Wait()
			end
		end)
		table.insert(threads, pulseThread)
	end

	local function maximizeGUI()
		State.isMinimized = false
		FloatingIcon.Visible = false
		FloatingTooltip.Visible = false
		FrameUtama.Visible = true
		
		-- Add restore animation
		local tweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		local tween = TweenService:Create(FrameUtama, tweenInfo, {
			Size = UDim2.new(0.541569591, 0, 0.64997077, 0)
		})
		tween:Play()
	end
	
	local function CloseAll()
		isOpen.Island = false
		isOpen.Player = false
		isOpen.Event = false
		
		ListOfTPIsland.Visible = false
		ListOfTpPlayer.Visible = false
		ListOfTPEvent.Visible = false
	end
	
	local function ToggleList(name)
		if not isOpen[name] then
			CloseAll()
			
			isOpen[name] = true
			if name == "Island" then
				ListOfTPIsland.Visible = true
			elseif name == "Player" then
				ListOfTpPlayer.Visible = true
			elseif name == "Event" then
				ListOfTPEvent.Visible = true
			end
		else
			isOpen[name] = false
			if name == "Island" then
				ListOfTPIsland.Visible = false
			elseif name == "Player" then
				ListOfTpPlayer.Visible = false
			elseif name == "Event" then
				ListOfTPEvent.Visible = false
			end
		end
	end

	-- Create Island Teleport Buttons
	local function createIslandButtons()
		local islandIndex = 0
		for _, island in ipairs(tpFolder:GetChildren()) do
			if island:IsA("BasePart") then
				local btn = Instance.new("TextButton")
				btn.Name = island.Name
				btn.Size = UDim2.new(1, 0, 0.1, 0)
				btn.Position = UDim2.new(0, 0, (0.1 + 0.02) * islandIndex, 0)
				btn.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
				btn.Text = island.Name
				btn.TextScaled = true
				btn.TextColor3 = Color3.fromRGB(255, 255, 255)
				btn.Font = Enum.Font.GothamBold
				btn.Parent = ListOfTPIsland
				
				safeConnect(btn, "MouseButton1Click", function()
					if game.Players.LocalPlayer.Character and game.Players.LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
						game.Players.LocalPlayer.Character.HumanoidRootPart.CFrame = island.CFrame
					end
				end)
				islandIndex = islandIndex + 1
			end
		end
	end
	
	-- Create Player Teleport Buttons
	local function createPlayerButtons()
		local playerIndex = 0
		for _, playerChar in ipairs(charFolder:GetChildren()) do
			if playerChar:IsA("Model") and playerChar.Name ~= game.Players.LocalPlayer.Name then
				local btn = Instance.new("TextButton")
				btn.Name = playerChar.Name
				btn.Parent = ListOfTpPlayer
				btn.TextColor3 = Color3.fromRGB(255, 255, 255)
				btn.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
				btn.Text = playerChar.Name
				btn.Size = UDim2.new(1, 0, 0.1, 0)
				btn.Position = UDim2.new(0, 0, (0.1 + 0.02) * playerIndex, 0)
				
				safeConnect(btn, "MouseButton1Click", function()
					if game.Players.LocalPlayer.Character and game.Players.LocalPlayer.Character:FindFirstChild("HumanoidRootPart") and playerChar:FindFirstChild("HumanoidRootPart") then
						game.Players.LocalPlayer.Character.HumanoidRootPart.CFrame = playerChar.HumanoidRootPart.CFrame
					end
				end)
				playerIndex = playerIndex + 1
			end
		end
	end
	-- Page Management
	local pages = {
		Main = MainFrame,
		Player = PlayerFrame,
		Teleport = Teleport,
		Boat = SpawnBoatFrame,
	}

	-- Enhanced Auto Fishing Function with Security
	local function toggleFishing(state)
		State.autoFishing = state
		
		if state then
			-- Initialize statistics
			State.startTime = tick()
			State.fishCaught = 0
			State.totalProfit = 0
			State.suspicionLevel = 0
			
			-- Create auto fishing thread
			local fishingThread = task.spawn(function()
				while State.autoFishing do
					local success = pcall(function()
						-- Security cooldown check
						if State.isInCooldown then
							task.wait(1)
							return
						end
						
						-- Ensure character exists
						local char = player.Character
						if not char then
							return
						end
						
						-- Pre-fishing security checks
						if not isActionSafe() then
							task.wait(getRandomDelay(0.5, 2))
							return
						end
						
						local equippedTool = char:FindFirstChild("!!!EQUIPPED_TOOL!!!")
						if not equippedTool then
							-- Reset and equip rod with security
							safeInvokeWithSecurity(Remotes.CancelFishing)
							task.wait(getRandomDelay(0.1, 0.3))
							safeInvokeWithSecurity(Remotes.EquipRod, 1)
						end

						-- Humanized fishing process
						local chargeDelay = getRandomDelay(0.05, 0.15)
						task.wait(chargeDelay)
						
						safeInvokeWithSecurity(Remotes.ChargeRod, workspace:GetServerTimeNow())
						
						local castDelay = getRandomDelay(0.1, 0.2)
						task.wait(castDelay)
						
						safeInvokeWithSecurity(Remotes.RequestFishing, -1.2379989624023438, 0.9800224985802423)
						
						-- Variable fishing delay to seem human
						local fishingDelay = getRandomDelay(CONSTANTS.MIN_FISHING_DELAY, CONSTANTS.MAX_FISHING_DELAY)
						task.wait(fishingDelay)
						
						-- Complete fishing with slight delay
						Remotes.FishingComplete:FireServer()
						
						-- Update fish count (simplified)
						State.fishCaught = State.fishCaught + 1
						
						-- Occasional human-like pauses
						if math.random(1, 10) == 1 then
							local humanPause = getRandomDelay(1, 3)
							task.wait(humanPause)
						end
						
						-- Perform anti-kick actions
						performAntiKick()
						
						-- Check for auto sell
						checkAndAutoSell()
						
						-- Update statistics
						updateStatistics()
					end)
					
					if not success then
						incrementSuspicion(3)
						warn("Auto fishing error occurred")
						task.wait(getRandomDelay(2, 5)) -- Longer wait after errors
					end
					
					-- Random delay between fishing cycles
					local cycleDelay = getRandomDelay(0.1, 0.3)
					task.wait(cycleDelay)
				end
			end)
			
			table.insert(threads, fishingThread)
			
			-- Statistics update thread
			local statsThread = task.spawn(function()
				while State.autoFishing do
					updateStatistics()
					updateSecurityStatus()
					task.wait(1) -- Update every second
				end
			end)
			
			table.insert(threads, statsThread)
		else
			-- Stop fishing and cleanup
			pcall(function()
				safeInvokeWithSecurity(Remotes.CancelFishing)
				safeInvokeWithSecurity(Remotes.UnEquipRod)
			end)
			
			-- Reset statistics display
			if State.startTime == 0 then
				FishCountLabel.Text = "🐟 Fish Caught: 0"
				TimeLabel.Text = "⏱️ Time: 00:00:00"
				ProfitLabel.Text = "💰 Rate: 0 fish/hour"
			end
		end
	end

	-- Walk Speed Function with Validation
	local function setWalkSpeed(speed)
		local numSpeed = tonumber(speed)
		if numSpeed and numSpeed > 0 and numSpeed <= CONSTANTS.MAX_WALKSPEED then
			if player.Character and player.Character:FindFirstChild("Humanoid") then
				player.Character.Humanoid.WalkSpeed = numSpeed
				State.walkSpeed = numSpeed
			end
		else
			warn("Invalid walk speed value. Must be between 1 and " .. CONSTANTS.MAX_WALKSPEED)
		end
	end

	-- Enhanced Anti-Kick System with Security
	local function performAntiKick()
		if not State.antiKick then return end
		
		local currentTime = tick()
		local randomInterval = getRandomDelay(CONSTANTS.MIN_ANTI_KICK_INTERVAL, CONSTANTS.MAX_ANTI_KICK_INTERVAL)
		
		if currentTime - State.lastAntiKickTime < randomInterval then
			return
		end
		
		State.lastAntiKickTime = currentTime
		
		if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
			local humanoidRootPart = player.Character.HumanoidRootPart
			local humanoid = player.Character:FindFirstChild("Humanoid")
			
			-- More realistic movement patterns
			local movementType = math.random(1, 4)
			
			if movementType == 1 then
				-- Small circular movement
				local angle = getRandomDelay(0, math.pi * 2)
				local radius = getRandomDelay(0.5, 2)
				local offset = Vector3.new(
					math.cos(angle) * radius,
					0,
					math.sin(angle) * radius
				)
				humanoidRootPart.CFrame = humanoidRootPart.CFrame + offset
				
			elseif movementType == 2 then
				-- Random direction with realistic speed
				local randomDirection = Vector3.new(
					getRandomDelay(-1, 1),
					0,
					getRandomDelay(-1, 1)
				).Unit * getRandomDelay(1, 3)
				
				humanoidRootPart.CFrame = humanoidRootPart.CFrame + randomDirection
				
			elseif movementType == 3 then
				-- Simulate looking around (camera movement)
				simulateHumanInput()
				
			else
				-- Random jump with realistic timing
				if humanoid and getRandomDelay(0, 1) > 0.7 then
					humanoid.Jump = true
				end
			end
			
			-- Random micro-pause to seem more human
			local pauseTime = getRandomDelay(0.1, 0.5)
			task.wait(pauseTime)
		end
	end

	-- Auto Sell Function
	local function checkAndAutoSell()
		if not State.autoSell then return end
		
		-- This would need to be adapted based on the specific game's inventory system
		-- For now, we'll use a simple approach
		local backpack = player:FindFirstChild("Backpack")
		if backpack then
			local items = backpack:GetChildren()
			local maxSlots = 50 -- Adjust based on game
			local usedSlots = #items
			local fillPercentage = usedSlots / maxSlots
			
			if fillPercentage >= CONSTANTS.AUTO_SELL_THRESHOLD then
				safeInvoke(Remotes.SellAll)
				State.totalProfit = State.totalProfit + (usedSlots * 10) -- Estimated profit
			end
		end
	end

	-- Statistics Update Function
	local function updateStatistics()
		if State.autoFishing and State.startTime > 0 then
			local currentTime = tick()
			local elapsedTime = currentTime - State.startTime
			
			-- Format time
			local hours = math.floor(elapsedTime / 3600)
			local minutes = math.floor((elapsedTime % 3600) / 60)
			local seconds = math.floor(elapsedTime % 60)
			local timeString = string.format("%02d:%02d:%02d", hours, minutes, seconds)
			
			-- Calculate rate
			local fishPerHour = 0
			if elapsedTime > 0 then
				fishPerHour = math.floor((State.fishCaught / elapsedTime) * 3600)
			end
			
			-- Update UI
			FishCountLabel.Text = "🐟 Fish Caught: " .. State.fishCaught
			TimeLabel.Text = "⏱️ Time: " .. timeString
			ProfitLabel.Text = "💰 Rate: " .. fishPerHour .. " fish/hour"
		end
	end

	-- Security Status Update Function
	local function updateSecurityStatus()
		local suspicionPercentage = math.min(State.suspicionLevel / 10, 1)
		
		-- Update suspicion meter
		SuspicionBar.Size = UDim2.new(suspicionPercentage, 0, 1, 0)
		
		-- Update colors and status text based on suspicion level
		if State.suspicionLevel <= 2 then
			SecurityTitle.TextColor3 = Color3.fromRGB(0, 255, 0)
			SecurityStatus.Text = "✅ Safe - All systems normal"
			SecurityStatus.TextColor3 = Color3.fromRGB(0, 255, 0)
			SuspicionBar.BackgroundColor3 = Color3.fromRGB(0, 255, 0)
		elseif State.suspicionLevel <= 5 then
			SecurityTitle.TextColor3 = Color3.fromRGB(255, 255, 0)
			SecurityStatus.Text = "⚠️ Caution - Slightly elevated activity"
			SecurityStatus.TextColor3 = Color3.fromRGB(255, 255, 0)
			SuspicionBar.BackgroundColor3 = Color3.fromRGB(255, 255, 0)
		elseif State.suspicionLevel <= 8 then
			SecurityTitle.TextColor3 = Color3.fromRGB(255, 165, 0)
			SecurityStatus.Text = "⚡ Warning - High activity detected"
			SecurityStatus.TextColor3 = Color3.fromRGB(255, 165, 0)
			SuspicionBar.BackgroundColor3 = Color3.fromRGB(255, 165, 0)
		else
			SecurityTitle.TextColor3 = Color3.fromRGB(255, 0, 0)
			SecurityStatus.Text = "🚨 Critical - Entering cooldown mode"
			SecurityStatus.TextColor3 = Color3.fromRGB(255, 0, 0)
			SuspicionBar.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
		end
		
		-- Show cooldown status
		if State.isInCooldown then
			SecurityStatus.Text = "❄️ Cooldown - Waiting for safety"
			SecurityStatus.TextColor3 = Color3.fromRGB(0, 150, 255)
		end
		
		-- Show actions per minute
		local actionsText = "Actions/min: " .. State.actionsThisMinute .. "/" .. CONSTANTS.MAX_ACTIONS_PER_MINUTE
		if State.actionsThisMinute > CONSTANTS.MAX_ACTIONS_PER_MINUTE * 0.8 then
			SecurityStatus.Text = SecurityStatus.Text .. " | " .. actionsText
		end
	end

	-- Panel Display Function
	function showPanel(pageName)
		-- Hide all panels
		for _, panel in pairs(pages) do
			panel.Visible = false
		end

		-- Show selected panel
		local selectedPanel = pages[pageName]
		if selectedPanel then
			selectedPanel.Visible = true
			Tittle.Text = pageName:upper()
			State.currentPage = pageName
		end
	end

	-- Button Event Connections
	local function setupEventConnections()
		-- Auto Fish Button
		safeConnect(AutoFishButton, "MouseButton1Click", function()
			if State.autoFishing then
				toggleFishing(false)
				AutoFishButton.Text = "OFF"
				AutoFishWarna.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
			else
				toggleFishing(true)
				AutoFishButton.Text = "ON"
				AutoFishWarna.BackgroundColor3 = Color3.fromRGB(0, 255, 0)
			end
		end)

		-- Exit Button
		safeConnect(ExitBtn, "MouseButton1Click", function()
			cleanup()
			gui:Destroy()
		end)

		-- Minimize Button
		safeConnect(MinimizeBtn, "MouseButton1Click", function()
			minimizeGUI()
		end)

		-- Floating Icon Click (Maximize)
		safeConnect(FloatingIcon, "MouseButton1Click", function()
			maximizeGUI()
		end)

		-- Floating Icon Hover Effects
		safeConnect(FloatingIcon, "MouseEnter", function()
			local tweenInfo = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			local tween = TweenService:Create(FloatingIcon, tweenInfo, {
				Size = UDim2.new(0, 70, 0, 70),
				BackgroundTransparency = 0.05
			})
			tween:Play()
			
			-- Show tooltip
			FloatingTooltip.Visible = true
			local tooltipTween = TweenService:Create(FloatingTooltip, tweenInfo, {
				BackgroundTransparency = 0.1
			})
			tooltipTween:Play()
		end)

		safeConnect(FloatingIcon, "MouseLeave", function()
			local tweenInfo = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			local tween = TweenService:Create(FloatingIcon, tweenInfo, {
				Size = UDim2.new(0, 60, 0, 60),
				BackgroundTransparency = 0.1
			})
			tween:Play()
			
			-- Hide tooltip
			local tooltipTween = TweenService:Create(FloatingTooltip, tweenInfo, {
				BackgroundTransparency = 1
			})
			tooltipTween:Play()
			tooltipTween.Completed:Connect(function()
				FloatingTooltip.Visible = false
			end)
		end)

		-- Navigation Buttons
		safeConnect(MAIN, "MouseButton1Click", function()
			showPanel("Main")
		end)

		safeConnect(Player, "MouseButton1Click", function()
			showPanel("Player")
		end)

		safeConnect(TELEPORT, "MouseButton1Click", function()
			showPanel("Teleport")
		end)

		safeConnect(SpawnBoat, "MouseButton1Click", function()
			showPanel("Boat")
		end)

		-- No Oxygen Button
		safeConnect(NoOxygenButton, "MouseButton1Click", function()
			local state = noOxygen.toggle()
			NoOxygenButton.Text = state and "ON" or "OFF"
			NoOxygenWarna.BackgroundColor3 = state and Color3.fromRGB(0, 255, 0) or Color3.fromRGB(0, 0, 0)
			State.noOxygen = state
		end)

		-- Unlimited Jump Button
		safeConnect(UnlimitedJumpButton, "MouseButton1Click", function()
			if player.Character and player.Character:FindFirstChild("Humanoid") then
				local humanoid = player.Character.Humanoid
				if humanoid.JumpHeight == 7.2 then -- Default jump height
					humanoid.JumpHeight = 50
					UnlimitedJumpButton.Text = "ON"
					UnlimitedJumpWarna.BackgroundColor3 = Color3.fromRGB(0, 255, 0)
				else
					humanoid.JumpHeight = 7.2
					UnlimitedJumpButton.Text = "OFF"
					UnlimitedJumpWarna.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
				end
			end
		end)
		
		-- Teleport List Buttons
		safeConnect(TPIslandButton, "MouseButton1Click", function()
			ToggleList("Island")
		end)
		
		safeConnect(TPPlayerButton, "MouseButton1Click", function()
			ToggleList("Player")
		end)

		-- Sell All Button
		safeConnect(SellAllButton, "MouseButton1Click", function()
			safeInvoke(Remotes.SellAll)
		end)

		-- Anti-Kick Button
		safeConnect(AntiKickButton, "MouseButton1Click", function()
			State.antiKick = not State.antiKick
			AntiKickButton.Text = State.antiKick and "ON" or "OFF"
			AntiKickWarna.BackgroundColor3 = State.antiKick and Color3.fromRGB(0, 255, 0) or Color3.fromRGB(0, 0, 0)
		end)

		-- Auto Sell Button
		safeConnect(AutoSellButton, "MouseButton1Click", function()
			State.autoSell = not State.autoSell
			AutoSellButton.Text = State.autoSell and "ON" or "OFF"
			AutoSellWarna.BackgroundColor3 = State.autoSell and Color3.fromRGB(0, 255, 0) or Color3.fromRGB(0, 0, 0)
		end)

		-- Walk Speed Button
		safeConnect(SetWalkSpeedButton, "MouseButton1Click", function()
			local speedText = WalkSpeedTextBox.Text
			if speedText and speedText ~= "" then
				setWalkSpeed(speedText)
				WalkSpeedTextBox.Text = ""
			end
		end)

		-- Boat Spawn Buttons
		local boatButtons = {
			{button = DespawnBoatButton, action = function() safeInvoke(Remotes.DespawnBoat) end},
			{button = SmallBoatButton, action = function() safeInvoke(Remotes.SpawnBoat, "SmallBoat") end},
			{button = KayakBoatButton, action = function() safeInvoke(Remotes.SpawnBoat, "Kayak") end},
			{button = JetskiBoatButton, action = function() safeInvoke(Remotes.SpawnBoat, "Jetski") end},
			{button = HighfieldBoatButton, action = function() safeInvoke(Remotes.SpawnBoat, "HighfieldBoat") end},
			{button = SpeedBoatButton, action = function() safeInvoke(Remotes.SpawnBoat, "SpeedBoat") end},
			{button = FishingBoatButton, action = function() safeInvoke(Remotes.SpawnBoat, "FishingBoat") end},
			{button = MiniYachtButton, action = function() safeInvoke(Remotes.SpawnBoat, "MiniYacht") end},
			{button = HyperBoatButton, action = function() safeInvoke(Remotes.SpawnBoat, "HyperBoat") end},
			{button = FrozenBoatButton, action = function() safeInvoke(Remotes.SpawnBoat, "FrozenBoat") end},
			{button = CruiserBoatButton, action = function() safeInvoke(Remotes.SpawnBoat, "CruiserBoat") end},
			{button = AlphaFloatyButton, action = function() safeInvoke(Remotes.SpawnBoat, "AlphaFloaty") end},
			{button = EvilDuckButton, action = function() safeInvoke(Remotes.SpawnBoat, "EvilDuck") end},
			{button = FestiveDuckButton, action = function() safeInvoke(Remotes.SpawnBoat, "FestiveDuck") end},
			{button = SantaSleighButton, action = function() safeInvoke(Remotes.SpawnBoat, "SantaSleigh") end}
		}

		for _, boat in ipairs(boatButtons) do
			safeConnect(boat.button, "MouseButton1Click", boat.action)
		end
	end

	-- Initialize everything
	local function initialize()
		-- Setup initial UI state
		AutoFishButton.Text = "OFF"
		AutoFishWarna.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		NoOxygenButton.Text = "OFF"
		NoOxygenWarna.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		UnlimitedJumpButton.Text = "OFF"
		UnlimitedJumpWarna.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		
		-- Initialize new AFK features
		AntiKickButton.Text = "OFF"
		AntiKickWarna.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		AutoSellButton.Text = "OFF"
		AutoSellWarna.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		
		-- Initialize statistics
		FishCountLabel.Text = "🐟 Fish Caught: 0"
		TimeLabel.Text = "⏱️ Time: 00:00:00"
		ProfitLabel.Text = "💰 Rate: 0 fish/hour"
		
		-- Initialize security status
		SecurityStatus.Text = "✅ Safe - All systems normal"
		SecurityStatus.TextColor3 = Color3.fromRGB(0, 255, 0)
		SuspicionBar.Size = UDim2.new(0, 0, 1, 0)
		SuspicionBar.BackgroundColor3 = Color3.fromRGB(0, 255, 0)
		
		-- Initialize floating icon tooltip
		FloatingTooltip.BackgroundTransparency = 1
		
		createIslandButtons()
		createPlayerButtons()
		setupEventConnections()
		showPanel("Main")
		
		-- Character respawn handling
		safeConnect(player, "CharacterAdded", function(newCharacter)
			character = newCharacter
			-- Reset states when character respawns
			if State.autoFishing then
				toggleFishing(false)
				AutoFishButton.Text = "OFF"
				AutoFishWarna.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
			end
		end)

		-- Keyboard shortcut for minimize/maximize (Right Ctrl + M)
		local UserInputService = game:GetService("UserInputService")
		safeConnect(UserInputService, "InputBegan", function(input, gameProcessed)
			if gameProcessed then return end
			
			if input.KeyCode == Enum.KeyCode.M and UserInputService:IsKeyDown(Enum.KeyCode.RightControl) then
				if State.isMinimized then
					maximizeGUI()
				else
					minimizeGUI()
				end
			end
		end)
	end

	-- Start the script
	initialize()

