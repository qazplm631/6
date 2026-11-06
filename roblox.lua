-- 自动加载脚本
local scripts = {
    "https://raw.githubusercontent.com/qazplm631/6/main/f.lua",
    "https://raw.githubusercontent.com/qazplm631/6/main/ffffff.lua",
    "https://raw.githubusercontent.com/qazplm631/6/main/787878.lua"

"https://raw.githubusercontent.com/qazplm631/6/main/ssss.lua"

"https://raw.githubusercontent.com/qazplm631/6/main/aaa.lua"
}

for _, url in ipairs(scripts) do
    local success, err = pcall(function()
        loadstring(game:HttpGet(url))()
    end)

    if not success then
        warn("脚本加载失败: " .. tostring(err))
    end
end

-- 全屏弹窗
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local function showFullscreenPopup(message, duration)
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "EmergencyNotification"
    screenGui.IgnoreGuiInset = true
    screenGui.ResetOnSpawn = false
    screenGui.DisplayOrder = 999999
    screenGui.Parent = playerGui

    local background = Instance.new("Frame")
    background.Size = UDim2.fromScale(1, 1)
    background.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    background.BorderSizePixel = 0
    background.Parent = screenGui

    local title = Instance.new("TextLabel")
    title.Size = UDim2.fromScale(0.9, 0.2)
    title.Position = UDim2.fromScale(0.05, 0.4)
    title.BackgroundTransparency = 1
    title.Text = message
    title.TextColor3 = Color3.fromRGB(255, 255, 255)
    title.TextScaled = true
    title.Font = Enum.Font.GothamBold
    title.Parent = background

    task.wait(duration)
    screenGui:Destroy()
end

-- 弹窗流程
showFullscreenPopup("你已成功加载紧急情况", 5)
showFullscreenPopup("已开启透视罪犯和自动手铐和微加速+汽车加速", 5)