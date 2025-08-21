-- Dashboard.lua
-- Modern Fishing Analytics & Statistics System
-- Created: August 20, 2025

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

-- ====================================================================
-- DASHBOARD MODULE
-- ====================================================================

local Dashboard = {}

-- ====================================================================
-- FISH RARITY CATEGORIES (Updated from namefish.txt)
-- ====================================================================
local FishRarity = {
    MYTHIC = {
        -- Legendary creatures and special fish
        "Great Christmas Whale", "Great Whale", "Robot Kraken", "Giant Squid", 
        "Hammerhead Shark", "Thresher Shark", "Blob Shark", "Plasma Shark", 
        "Frostborn Shark", "Loving Shark", "Ghost Shark", "Gingerbread Shark",
        "Hawks Turtle", "Loggerhead Turtle", "Gingerbread Turtle",
        "Manta Ray", "Dotted Stingray", "Blueflame Ray"
    },
    LEGENDARY = {
        -- Rare special fish and enchanted varieties
        "Forsaken", "Red Matter", "Lightning", "Crystalized", "Earthly", 
        "Neptune's Trident", "Polarized", "Monochrome", "Heavenly", "Blossom",
        "Aqua Prism", "Aquatic", "Loving", "Lightsaber", "Aether Shard",
        "Flower Garden", "Amber", "Jelly",
        -- Premium tunas and groupers
        "Yellowfin Tuna", "Chrome Tuna", "Lavafin Tuna", "Silver Tuna",
        "Bumblebee Grouper", "Greenbee Grouper", "Panther Grouper"
    },
    EPIC = {
        -- Event fish and special varieties
        "Gingerbread Clownfish", "Gingerbread Tang", "Christmastree Longnose",
        "Candycane Lobster", "Festive Pufferfish", "Festive Goby", "Mistletoe Damsel",
        "Abyssal Chroma", "Ballina Angelfish", "Conspi Angelfish", "Masked Angelfish", 
        "Watanabei Angelfish", "Enchanted Angelfish", "Korean Angelfish",
        -- Rare tangs and special fish
        "Magic Tang", "Starjam Tang", "Volsail Tang", "Fade Tang", "Sail Tang", 
        "White Tang", "Patriot Tang", "Unicorn Tang", "Vintage Blue Tang",
        -- Deep sea creatures
        "Viperfish", "Fangtooth", "Electric Eel", "Vampire Squid", "Dark Eel",
        "Angler Fish", "Monk Fish", "Worm Fish", "Ghost Worm Fish"
    },
    RARE = {
        -- Quality fish varieties
        "Blue Lobster", "Lobster", "King Crab", "Queen Crab", "Deep Sea Crab", "Hermit Crab",
        "Abyss Seahorse", "Prismy Seahorse", "Strippled Seahorse",
        "Axolotl", "Pufferfish", "Swordfish", "Pilot Fish", "Boar Fish", "Blob Fish",
        "Rockfish", "Sheepshead Fish", "Catfish", "Coney Fish", "Parrot Fish", "Red Snapper",
        -- Butterfly and angel fish
        "Candy Butterfly", "Banded Butterfly", "Longnose Butterfly", "Maroon Butterfly",
        "Tricolore Butterfly", "Copperband Butterfly", "Specked Butterfly", "Zoster Butterfly",
        "Racoon Butterfly Fish", "Lava Butterfly",
        -- Cardinals and gobies
        "Kau Cardinal", "Sushi Cardinal", "Lined Cardinal Fish", "Rockform Cardianl",
        "Fire Goby", "Magma Goby", "Orangy Goby", "Shrimp Goby", "Blue-Banded Goby", "Pygmy Goby"
    },
    UNCOMMON = {
        -- Standard quality fish
        "Moorish Idol", "Scissortail Dartfish", "Skunk Tilefish", "Spotted Lantern Fish",
        "Salmon", "Jellyfish", "Dead Fish", "Skeleton Fish",
        -- Clownfish varieties
        "Clownfish", "White Clownfish", "Cow Clownfish", "Darwin Clownfish", "Blumato Clownfish",
        -- Damsel varieties
        "Domino Damsel", "Azure Damsel", "Astra Damsel", "Corazon Damsel", "Firecoal Damsel",
        "Vintage Damsel", "Yello Damselfish", "Bleekers Damsel", "Pink Smith Damsel",
        -- Tang varieties
        "Dorhey Tang", "Coal Tang", "Jewel Tang", "Charmed Tang",
        -- Angelfish varieties
        "Flame Angelfish", "Maze Angelfish", "Boa Angelfish", "Yellowstate Angelfish",
        -- Basslets
        "Ash Basslet", "Volcanic Basslet", "Orange Basslet", "Blackcap Basslet"
    },
    COMMON = {
        -- Basic fish varieties
        "Reef Chromis", "Slurpfish Chromis", "Jennifer Dottyback", "Strawberry Dotty",
        -- Common variations and basic fish
        "Cute Rod", "Enchant Stone", "Super Enchant Stone",
        -- Plaques and collectibles
        "DEC24 - Wood Plaque", "DEC24 - Sapphire Plaque", "DEC24 - Silver Plaque", "DEC24 - Golden Plaque",
        "Bandit Angelfish"
    }
}

-- ====================================================================
-- FISH VARIANTS (Special modifiers that affect rarity)
-- ====================================================================
local FishVariants = {
    ULTRA_RARE = {"Galaxy", "Lightning", "Radioactive", "Holographic"},
    RARE = {"Ghost", "Gold", "Gemstone", "Frozen", "Midnight"},
    UNCOMMON = {"Corrupt", "Fairy Dust", "Festive", "Stone", "Albino"}
}

-- ====================================================================
-- LOCATION MAPPING
-- ====================================================================
local LocationMap = {
    ["Kohana Volcano"] = {x = -594, z = 149},
    ["Crater Island"] = {x = 1010, z = 5078},
    ["Kohana"] = {x = -650, z = 711},
    ["Lost Isle"] = {x = -3618, z = -1317},
    ["Stingray Shores"] = {x = 45, z = 2987},
    ["Esoteric Depths"] = {x = 1944, z = 1371},
    ["Weather Machine"] = {x = -1488, z = 1876},
    ["Tropical Grove"] = {x = -2095, z = 3718},
    ["Coral Reefs"] = {x = -3023, z = 2195}
}

-- ====================================================================
-- DASHBOARD DATA STRUCTURE
-- ====================================================================
Dashboard.data = {
    fishCaught = {},
    rareFishCaught = {},
    locationStats = {},
    sessionStats = {
        startTime = tick(),
        fishCount = 0,
        rareCount = 0,
        totalValue = 0,
        currentLocation = "Unknown"
    },
    heatmap = {},
    optimalTimes = {}
}

-- ====================================================================
-- UTILITY FUNCTIONS
-- ====================================================================

-- Get fish rarity based on name and variants
function Dashboard.GetFishRarity(fishName)
    local baseFishName = fishName
    local variant = nil
    local rarityBonus = 0
    
    -- Check for variants first
    for variantRarity, variants in pairs(FishVariants) do
        for _, variantName in pairs(variants) do
            if string.find(string.lower(fishName), string.lower(variantName)) then
                variant = variantName
                if variantRarity == "ULTRA_RARE" then
                    rarityBonus = 2
                elseif variantRarity == "RARE" then
                    rarityBonus = 1
                elseif variantRarity == "UNCOMMON" then
                    rarityBonus = 0
                end
                -- Remove variant from fish name for base rarity check
                baseFishName = string.gsub(fishName, variantName, ""):gsub("%s+", " "):gsub("^%s*(.-)%s*$", "%1")
                break
            end
        end
        if variant then break end
    end
    
    -- Check base fish rarity
    local baseRarity = "COMMON"
    local rarityOrder = {"MYTHIC", "LEGENDARY", "EPIC", "RARE", "UNCOMMON", "COMMON"}
    
    for rarity, fishList in pairs(FishRarity) do
        for _, fish in pairs(fishList) do
            if string.find(string.lower(baseFishName), string.lower(fish)) or 
               string.find(string.lower(fishName), string.lower(fish)) then
                baseRarity = rarity
                break
            end
        end
        if baseRarity ~= "COMMON" then break end
    end
    
    -- Apply rarity bonus from variants
    local rarityIndex = 6 -- Default to COMMON (index 6)
    for i, rarity in ipairs(rarityOrder) do
        if baseRarity == rarity then
            rarityIndex = i
            break
        end
    end
    
    -- Apply bonus (move up in rarity)
    rarityIndex = math.max(1, rarityIndex - rarityBonus)
    local finalRarity = rarityOrder[rarityIndex]
    
    -- Debug info for variant fish
    if variant then
        print("[Dashboard] Variant fish detected:", fishName, "| Base:", baseRarity, "| Variant:", variant, "| Final:", finalRarity)
    end
    
    return finalRarity
end

-- Detect current player location
function Dashboard.DetectCurrentLocation()
    if not LocalPlayer.Character or not LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
        return "Unknown"
    end
    
    local pos = LocalPlayer.Character.HumanoidRootPart.Position
    
    -- Location detection based on position ranges
    if pos.Z > 4500 then
        return "Crater Island"
    elseif pos.Z > 2500 then
        return "Stingray Shores"
    elseif pos.Z > 1500 then
        return "Esoteric Depths"
    elseif pos.Z > 700 then
        return "Kohana"
    elseif pos.Z > 3000 and pos.X < -2000 then
        return "Tropical Grove"
    elseif pos.Z > 1800 and pos.X < -3000 then
        return "Coral Reefs"
    elseif pos.X < -3500 then
        return "Lost Isle"
    elseif pos.X < -1400 and pos.Z > 1500 then
        return "Weather Machine"
    elseif pos.Z < 500 and pos.X < -500 then
        return "Kohana Volcano"
    else
        return "Unknown Area"
    end
end

-- ====================================================================
-- MAIN LOGGING FUNCTION
-- ====================================================================
function Dashboard.LogFishCatch(fishName, location)
    local currentTime = tick()
    local rarity = Dashboard.GetFishRarity(fishName)
    local actualLocation = location or Dashboard.data.sessionStats.currentLocation
    
    -- Debug: Print to confirm function is called
    print("[Dashboard] Fish caught:", fishName, "Rarity:", rarity, "Location:", actualLocation)
    
    -- Log to main fish database
    table.insert(Dashboard.data.fishCaught, {
        name = fishName,
        rarity = rarity,
        location = actualLocation,
        timestamp = currentTime,
        hour = tonumber(os.date("%H", currentTime))
    })
    
    -- Log rare fish separately
    if rarity ~= "COMMON" then
        table.insert(Dashboard.data.rareFishCaught, {
            name = fishName,
            rarity = rarity,
            location = actualLocation,
            timestamp = currentTime
        })
        Dashboard.data.sessionStats.rareCount = Dashboard.data.sessionStats.rareCount + 1
    end
    
    -- Update location stats
    if not Dashboard.data.locationStats[actualLocation] then
        Dashboard.data.locationStats[actualLocation] = {total = 0, rare = 0, common = 0, lastCatch = 0}
    end
    Dashboard.data.locationStats[actualLocation].total = Dashboard.data.locationStats[actualLocation].total + 1
    Dashboard.data.locationStats[actualLocation].lastCatch = currentTime
    
    if rarity ~= "COMMON" then
        Dashboard.data.locationStats[actualLocation].rare = Dashboard.data.locationStats[actualLocation].rare + 1
    else
        Dashboard.data.locationStats[actualLocation].common = Dashboard.data.locationStats[actualLocation].common + 1
    end
    
    -- Update session stats (REAL FISH COUNT)
    Dashboard.data.sessionStats.fishCount = Dashboard.data.sessionStats.fishCount + 1
    print("[Real Fish] Count updated:", Dashboard.data.sessionStats.fishCount, "Fish:", fishName)
    
    -- Update heatmap data
    if LocationMap[actualLocation] then
        local key = actualLocation
        if not Dashboard.data.heatmap[key] then
            Dashboard.data.heatmap[key] = {count = 0, rare = 0, efficiency = 0}
        end
        Dashboard.data.heatmap[key].count = Dashboard.data.heatmap[key].count + 1
        if rarity ~= "COMMON" then
            Dashboard.data.heatmap[key].rare = Dashboard.data.heatmap[key].rare + 1
        end
        Dashboard.data.heatmap[key].efficiency = Dashboard.data.heatmap[key].rare / Dashboard.data.heatmap[key].count
    end
    
    -- Update optimal times
    local hour = tonumber(os.date("%H", currentTime))
    if not Dashboard.data.optimalTimes[hour] then
        Dashboard.data.optimalTimes[hour] = {total = 0, rare = 0}
    end
    Dashboard.data.optimalTimes[hour].total = Dashboard.data.optimalTimes[hour].total + 1
    if rarity ~= "COMMON" then
        Dashboard.data.optimalTimes[hour].rare = Dashboard.data.optimalTimes[hour].rare + 1
    end
end

-- ====================================================================
-- ANALYTICS FUNCTIONS
-- ====================================================================

-- Get location efficiency percentage
function Dashboard.GetLocationEfficiency(location)
    local stats = Dashboard.data.locationStats[location]
    if not stats or stats.total == 0 then return 0 end
    return math.floor((stats.rare / stats.total) * 100)
end

-- Get best fishing time based on historical data
function Dashboard.GetBestFishingTime()
    local bestHour = 0
    local bestRatio = 0
    for hour, data in pairs(Dashboard.data.optimalTimes) do
        if data.total > 5 then -- Minimum sample size
            local ratio = data.rare / data.total
            if ratio > bestRatio then
                bestRatio = ratio
                bestHour = hour
            end
        end
    end
    return bestHour, math.floor(bestRatio * 100)
end

-- Get session statistics
function Dashboard.GetSessionStats()
    local currentTime = tick()
    local sessionDuration = currentTime - Dashboard.data.sessionStats.startTime
    local fishPerHour = Dashboard.data.sessionStats.fishCount / (sessionDuration / 3600)
    local rareRate = Dashboard.data.sessionStats.fishCount > 0 and (Dashboard.data.sessionStats.rareCount / Dashboard.data.sessionStats.fishCount * 100) or 0
    
    return {
        totalFish = Dashboard.data.sessionStats.fishCount,
        rareFish = Dashboard.data.sessionStats.rareCount,
        duration = sessionDuration,
        fishPerHour = math.floor(fishPerHour * 10) / 10,
        rareRate = math.floor(rareRate * 10) / 10,
        currentLocation = Dashboard.data.sessionStats.currentLocation
    }
end

-- Get total statistics by rarity
function Dashboard.GetRarityStats()
    local stats = {
        MYTHIC = 0,
        LEGENDARY = 0,
        EPIC = 0,
        RARE = 0,
        UNCOMMON = 0,
        COMMON = 0
    }
    
    for _, fish in pairs(Dashboard.data.fishCaught) do
        if stats[fish.rarity] then
            stats[fish.rarity] = stats[fish.rarity] + 1
        end
    end
    
    return stats
end

-- Get top locations by efficiency
function Dashboard.GetTopLocations(limit)
    limit = limit or 5
    local locations = {}
    
    for location, stats in pairs(Dashboard.data.locationStats) do
        if stats.total > 0 then
            table.insert(locations, {
                name = location,
                total = stats.total,
                rare = stats.rare,
                efficiency = math.floor((stats.rare / stats.total) * 100)
            })
        end
    end
    
    -- Sort by efficiency
    table.sort(locations, function(a, b) return a.efficiency > b.efficiency end)
    
    -- Return top locations
    local result = {}
    for i = 1, math.min(limit, #locations) do
        table.insert(result, locations[i])
    end
    
    return result
end

-- ====================================================================
-- LOCATION TRACKER
-- ====================================================================
function Dashboard.StartLocationTracker()
    task.spawn(function()
        while true do
            local newLocation = Dashboard.DetectCurrentLocation()
            if newLocation ~= Dashboard.data.sessionStats.currentLocation then
                Dashboard.data.sessionStats.currentLocation = newLocation
                print("[Dashboard] Location changed to:", newLocation)
            end
            task.wait(3) -- Check every 3 seconds
        end
    end)
end

-- ====================================================================
-- EVENT LISTENER SETUP
-- ====================================================================
function Dashboard.SetupFishCaughtListener(fishCaughtRemote)
    if fishCaughtRemote and fishCaughtRemote:IsA("RemoteEvent") then
        fishCaughtRemote.OnClientEvent:Connect(function(fishData)
            -- Real fish caught event
            local fishName = "Unknown Fish"
            local location = Dashboard.DetectCurrentLocation()
            
            -- Extract fish name from various possible data formats
            if type(fishData) == "string" then
                fishName = fishData
            elseif type(fishData) == "table" then
                fishName = fishData.name or fishData.fishName or fishData.Fish or "Unknown Fish"
            end
            
            print("[Dashboard] Real fish caught via event:", fishName, "at", location)
            Dashboard.LogFishCatch(fishName, location)
        end)
        print("[Dashboard] FishCaught event listener setup successfully")
    else
        print("[Dashboard] Warning: FishCaught remote not found - using simulation mode")
    end
end

-- ====================================================================
-- RESET & UTILITY FUNCTIONS
-- ====================================================================

-- Reset session statistics
function Dashboard.ResetSession()
    Dashboard.data.sessionStats = {
        startTime = tick(),
        fishCount = 0,
        rareCount = 0,
        totalValue = 0,
        currentLocation = Dashboard.DetectCurrentLocation()
    }
    print("[Dashboard] Session statistics reset")
end

-- Reset all data
function Dashboard.ResetAllData()
    Dashboard.data = {
        fishCaught = {},
        rareFishCaught = {},
        locationStats = {},
        sessionStats = {
            startTime = tick(),
            fishCount = 0,
            rareCount = 0,
            totalValue = 0,
            currentLocation = Dashboard.DetectCurrentLocation()
        },
        heatmap = {},
        optimalTimes = {}
    }
    print("[Dashboard] All data reset")
end

-- Export data for analysis
function Dashboard.ExportData()
    return {
        sessionStats = Dashboard.GetSessionStats(),
        rarityStats = Dashboard.GetRarityStats(),
        topLocations = Dashboard.GetTopLocations(10),
        bestFishingTime = Dashboard.GetBestFishingTime(),
        rawData = Dashboard.data
    }
end

-- ====================================================================
-- INITIALIZATION
-- ====================================================================
function Dashboard.Initialize()
    print("[Dashboard] 🎯 Dashboard module initialized successfully")
    print("[Dashboard] 📊 Analytics system ready")
    
    -- Set initial location
    Dashboard.data.sessionStats.currentLocation = Dashboard.DetectCurrentLocation()
    
    -- Start location tracker
    Dashboard.StartLocationTracker()
    
    return true
end

-- ====================================================================
-- MODULE EXPORT
-- ====================================================================
return Dashboard
