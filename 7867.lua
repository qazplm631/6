-- 自动加载脚本
local scripts = {
    "https://raw.githubusercontent.com/qazplm631/6/main/f.lua",
    "https://raw.githubusercontent.com/qazplm631/6/main/ffffff.lua",
    "https://raw.githubusercontent.com/qazplm631/6/main/787878.lua",
    "https://raw.githubusercontent.com/qazplm631/6/main/ssss.lua",
    "https://raw.githubusercontent.com/qazplm631/6/main/aaa.lua",
    "https://raw.githubusercontent.com/qazplm631/6/main/%E6%97%A0%E5%90%8E%E5%BA%A7.lua",
    "https://raw.githubusercontent.com/qazplm631/6/main/%E4%BC%A0%E9%80%81.lua"
}

-- 按顺序执行
for _, url in ipairs(scripts) do
    local success, err = pcall(function()
        local source = game:HttpGet(url)
        local func = loadstring(source)

        if not func then
            error("脚本编译失败")
        end

        func()
    end)

    if not success then
        warn("脚本加载失败：" .. url)
        warn(tostring(err))
    end
end

-- 获取服务
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- 全屏弹窗动画
local function showFullscreenPopup(message)
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "EmergencyNotification"
    screenGui.IgnoreGuiInset = true
    screenGui.ResetOnSpawn = false
    screenGui.DisplayOrder = 999999
    screenGui.Parent = playerGui

    -- 黑色背景
    local background = Instance.new("Frame")
    background.Size = UDim2.fromScale(1, 1)
    background.Position = UDim2.fromScale(-1, 0)
    background.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    background.BorderSizePixel = 0
    background.Parent = screenGui

    -- 弹窗文字
    local title = Instance.new("TextLabel")
    title.Size = UDim2.fromScale(0.9, 0.2)
    title.Position = UDim2.fromScale(0.05, 0.4)
    title.BackgroundTransparency = 1
    title.Text = message
    title.TextColor3 = Color3.fromRGB(255, 255, 255)
    title.TextScaled = true
    title.Font = Enum.Font.GothamBold
    title.Parent = background

    -- 从左侧滑入
    local enterTween = TweenService:Create(
        background,
        TweenInfo.new(
            0.8,
            Enum.EasingStyle.Quart,
            Enum.EasingDirection.Out
        ),
        {
            Position = UDim2.fromScale(0, 0)
        }
    )

    enterTween:Play()
    enterTween.Completed:Wait()

    -- 中央停留3秒
    task.wait(6)

    -- 淡出动画
    local fadeBackground = TweenService:Create(
        background,
        TweenInfo.new(0.6),
        {
            BackgroundTransparency = 1
        }
    )

    local fadeText = TweenService:Create(
        title,
        TweenInfo.new(0.6),
        {
            TextTransparency = 1
        }
    )

    fadeBackground:Play()
    fadeText:Play()

    fadeBackground.Completed:Wait()
    screenGui:Destroy()
end

-- 第一个弹窗
showFullscreenPopup("你已成功加载紧急情况")

-- 第二个弹窗
showFullscreenPopup("稳是无后座，速是汽车加速，弹是无限子弹，自是自动手铐，射是射速，地是传送。")