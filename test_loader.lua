-- Test loading script
print("🎣 ExploFish Loading Test Started...")

-- Test basic loadstring
local testCode = [[
    print("✅ Basic loadstring test passed!")
    return true
]]

local success, result = pcall(function()
    return loadstring(testCode)()
end)

if success then
    print("✅ Loadstring functionality works!")
else
    warn("❌ Loadstring test failed:", result)
end

-- Test HTTP loading
local httpSuccess = false
pcall(function()
    game:GetService("HttpService").HttpEnabled = true
    httpSuccess = true
end)

if httpSuccess then
    print("✅ HttpService available")
else
    warn("❌ HttpService not available")
end

-- Test main script loading
print("🚀 Loading main ExploFish script...")
local mainScriptUrl = "https://raw.githubusercontent.com/yohansevta/ExploFish/refs/heads/main/main.lua"

local loadSuccess, loadResult = pcall(function()
    return loadstring(game:HttpGet(mainScriptUrl))()
end)

if loadSuccess then
    print("✅ ExploFish loaded successfully!")
else
    warn("❌ ExploFish loading failed:", loadResult)
    -- Try alternative method
    print("🔄 Trying alternative loading method...")
    pcall(function()
        local code = game:HttpGet(mainScriptUrl, true)
        print("📄 Script length:", #code, "characters")
        if #code > 0 then
            loadstring(code)()
        else
            error("Empty script received")
        end
    end)
end
