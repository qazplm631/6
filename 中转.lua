-- Roblox server relay loader
-- Matching PlaceId: executes vvv.lua
-- Non-matching PlaceId: executes 5555.lua

local TARGET_PLACE_ID = 104841616983113

local TARGET_SCRIPT_URL =
    "https://raw.githubusercontent.com/qazplm631/6/main/vvv.lua"

local FALLBACK_SCRIPT_URL =
    "https://raw.githubusercontent.com/qazplm631/6/main/5555.lua"

local StarterGui = game:GetService("StarterGui")

local function notify(title, message)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = title,
            Text = message,
            Duration = 5
        })
    end)
end

local function executeRemote(url)
    assert(type(loadstring) == "function", "Executor does not support loadstring")

    local source = game:HttpGet(url)
    assert(type(source) == "string" and #source > 0, "Remote script is empty")

    local chunk, compileError = loadstring(source)
    assert(chunk, compileError or "Remote script compilation failed")

    return chunk()
end

local isTargetServer = (game.PlaceId == TARGET_PLACE_ID)
local selectedUrl

if isTargetServer then
    selectedUrl = TARGET_SCRIPT_URL
    notify("服务器检测", "当前服务器为圣奥里，正在加载专用脚本")
else
    selectedUrl = FALLBACK_SCRIPT_URL
    notify("服务器检测", "未匹配目标服务器，正在加载通用脚本")
end

local success, err = pcall(function()
    executeRemote(selectedUrl)
end)

if not success then
    warn("[Server Relay] " .. tostring(err))
    notify("脚本加载失败", tostring(err))
end
