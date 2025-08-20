-- ModuleLoader.lua
-- GitHub Raw Module Loading System
-- Created: August 20, 2025

local HttpService = game:GetService("HttpService")

local ModuleLoader = {}

-- ====================================================================
-- CONFIGURATION
-- ====================================================================
ModuleLoader.config = {
    githubUser = "yohansevta",
    repository = "ExploFish",
    branch = "main",
    baseUrl = "https://raw.githubusercontent.com",
    timeout = 10,
    retryAttempts = 3,
    useLocal = false -- Set to true for local development
}

-- ====================================================================
-- CACHE SYSTEM
-- ====================================================================
ModuleLoader.cache = {}
ModuleLoader.loadedModules = {}

-- ====================================================================
-- UTILITY FUNCTIONS
-- ====================================================================

-- Build GitHub Raw URL
function ModuleLoader.buildUrl(modulePath)
    return string.format("%s/%s/%s/%s/%s", 
        ModuleLoader.config.baseUrl,
        ModuleLoader.config.githubUser,
        ModuleLoader.config.repository,
        ModuleLoader.config.branch,
        modulePath
    )
end

-- Safe HTTP request with retry
function ModuleLoader.safeRequest(url, retries)
    retries = retries or ModuleLoader.config.retryAttempts
    
    for attempt = 1, retries do
        local success, result = pcall(function()
            return HttpService:GetAsync(url, false)
        end)
        
        if success then
            print("[ModuleLoader] ✅ Successfully loaded:", url)
            return result
        else
            print("[ModuleLoader] ❌ Attempt", attempt, "failed for:", url)
            if attempt < retries then
                task.wait(1) -- Wait 1 second before retry
            end
        end
    end
    
    warn("[ModuleLoader] Failed to load after", retries, "attempts:", url)
    return nil
end

-- ====================================================================
-- MODULE LOADING FUNCTIONS
-- ====================================================================

-- Load module from GitHub Raw
function ModuleLoader.loadModule(moduleName, forceReload)
    forceReload = forceReload or false
    
    -- Check cache first
    if not forceReload and ModuleLoader.cache[moduleName] then
        print("[ModuleLoader] 📦 Using cached module:", moduleName)
        return ModuleLoader.cache[moduleName]
    end
    
    -- Build module path
    local modulePath = "modules/" .. moduleName .. ".lua"
    
    -- Try to load from GitHub Raw first
    if not ModuleLoader.config.useLocal then
        local url = ModuleLoader.buildUrl(modulePath)
        print("[ModuleLoader] 🌐 Loading from GitHub Raw:", moduleName)
        
        local moduleCode = ModuleLoader.safeRequest(url)
        if moduleCode then
            -- Execute and cache the module
            local success, moduleResult = pcall(function()
                return loadstring(moduleCode)()
            end)
            
            if success and moduleResult then
                ModuleLoader.cache[moduleName] = moduleResult
                ModuleLoader.loadedModules[moduleName] = {
                    source = "github",
                    loadTime = tick(),
                    version = "latest"
                }
                print("[ModuleLoader] ✅ Module loaded successfully:", moduleName)
                return moduleResult
            else
                warn("[ModuleLoader] ❌ Failed to execute module:", moduleName)
            end
        end
    end
    
    -- Fallback to local if GitHub fails or useLocal is true
    print("[ModuleLoader] 📁 Trying local fallback for:", moduleName)
    local localPath = "modules/" .. moduleName .. ".lua"
    
    -- Try to require local module (this won't work in Roblox, but good for testing)
    local success, localModule = pcall(function()
        return require(game.ReplicatedStorage:FindFirstChild(moduleName))
    end)
    
    if success then
        ModuleLoader.cache[moduleName] = localModule
        ModuleLoader.loadedModules[moduleName] = {
            source = "local",
            loadTime = tick(),
            version = "local"
        }
        print("[ModuleLoader] ✅ Local module loaded:", moduleName)
        return localModule
    end
    
    warn("[ModuleLoader] ❌ Failed to load module:", moduleName)
    return nil
end

-- Load multiple modules
function ModuleLoader.loadModules(moduleList)
    local results = {}
    local loadTasks = {}
    
    for _, moduleName in pairs(moduleList) do
        table.insert(loadTasks, task.spawn(function()
            results[moduleName] = ModuleLoader.loadModule(moduleName)
        end))
    end
    
    -- Wait for all modules to load
    for _, taskThread in pairs(loadTasks) do
        task.wait() -- Allow other tasks to run
    end
    
    return results
end

-- ====================================================================
-- MANAGEMENT FUNCTIONS
-- ====================================================================

-- Check if module is loaded
function ModuleLoader.isLoaded(moduleName)
    return ModuleLoader.cache[moduleName] ~= nil
end

-- Reload a specific module
function ModuleLoader.reloadModule(moduleName)
    print("[ModuleLoader] 🔄 Reloading module:", moduleName)
    ModuleLoader.cache[moduleName] = nil
    return ModuleLoader.loadModule(moduleName, true)
end

-- Get module info
function ModuleLoader.getModuleInfo(moduleName)
    return ModuleLoader.loadedModules[moduleName]
end

-- List all loaded modules
function ModuleLoader.listLoadedModules()
    local modules = {}
    for name, info in pairs(ModuleLoader.loadedModules) do
        table.insert(modules, {
            name = name,
            source = info.source,
            loadTime = info.loadTime,
            version = info.version
        })
    end
    return modules
end

-- Clear cache
function ModuleLoader.clearCache()
    ModuleLoader.cache = {}
    ModuleLoader.loadedModules = {}
    print("[ModuleLoader] 🗑️ Cache cleared")
end

-- ====================================================================
-- CONFIGURATION FUNCTIONS
-- ====================================================================

-- Set GitHub repository info
function ModuleLoader.setRepository(user, repo, branch)
    ModuleLoader.config.githubUser = user or ModuleLoader.config.githubUser
    ModuleLoader.config.repository = repo or ModuleLoader.config.repository
    ModuleLoader.config.branch = branch or ModuleLoader.config.branch
    
    print("[ModuleLoader] 📝 Repository updated:", 
        ModuleLoader.config.githubUser .. "/" .. ModuleLoader.config.repository .. "@" .. ModuleLoader.config.branch)
end

-- Toggle local mode
function ModuleLoader.setLocalMode(useLocal)
    ModuleLoader.config.useLocal = useLocal
    print("[ModuleLoader] 🏠 Local mode:", useLocal and "ENABLED" or "DISABLED")
end

-- ====================================================================
-- INITIALIZATION
-- ====================================================================
function ModuleLoader.initialize()
    print("[ModuleLoader] 🚀 ModuleLoader initialized")
    print("[ModuleLoader] 📍 Repository:", ModuleLoader.config.githubUser .. "/" .. ModuleLoader.config.repository)
    print("[ModuleLoader] 🌿 Branch:", ModuleLoader.config.branch)
    return true
end

-- ====================================================================
-- MODULE EXPORT
-- ====================================================================
return ModuleLoader
