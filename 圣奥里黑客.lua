-- Generic direct-completion callback for hacking minigames in the authorized sandbox.
-- 注入成功后顶部弹出「功能已开启」提示,3 秒自动关闭。

local env = getgenv()
if env.ATM_DIRECT_STOP then env.ATM_DIRECT_STOP() end
if not hookfunction or not getcallbackvalue then return "MISSING_EXECUTOR_API" end

local remote = game.ReplicatedStorage.Remote.PlayerFunc
local ok, callback = pcall(getcallbackvalue, remote, "OnClientInvoke")
if not ok or type(callback) ~= "function" then return "NO_CALLBACK" end

local active = true
local original
original = hookfunction(callback, function(name, ...)
    if active and name == "hackingMinigame" then
        return true
    end
    return original(name, ...)
end)

env.__ATM_DIRECT_STOP = function()
    active = false
end

-- ===== 注入成功提示:功能已开启,3 秒后自动关闭 =====
do
    local Players      = game:GetService("Players")
    local TweenService = game:GetService("TweenService")
    local player       = Players.LocalPlayer

    -- 先清掉上一轮的提示框,避免重复注入叠框
    if env.__ATM_TOAST_CLOSE then
        pcall(env.__ATM_TOAST_CLOSE)
    end

    local gui = Instance.new("ScreenGui")
    gui.Name           = "ATM_TOAST"
    gui.ResetOnSpawn   = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder   = 999999
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

    local parentOk = pcall(function()
        if gethui then
            gui.Parent = gethui()
        elseif player:FindFirstChildOfClass("PlayerGui") then
            gui.Parent = player:WaitForChild("PlayerGui")
        else
            gui.Parent = game:GetService("CoreGui")
        end
    end)
    if not parentOk then
        pcall(function() gui.Parent = player:WaitForChild("PlayerGui") end)
    end

    local frame = Instance.new("Frame")
    frame.AnchorPoint            = Vector2.new(0.5, 0)
    frame.Position               = UDim2.new(0.5, 0, 0, 90)
    frame.Size                   = UDim2.new(0, 320, 0, 88)
    frame.BackgroundColor3       = Color3.fromRGB(20, 22, 28)
    frame.BackgroundTransparency = 0.06
    frame.BorderSizePixel        = 0
    frame.Parent                 = gui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 12)
    corner.Parent = frame

    local stroke = Instance.new("UIStroke")
    stroke.Color        = Color3.fromRGB(0, 220, 140)
    stroke.Thickness    = 1.5
    stroke.Transparency = 0.2
    stroke.Parent       = frame

    local accent = Instance.new("Frame")
    accent.Size             = UDim2.new(0, 4, 1, -20)
    accent.Position         = UDim2.new(0, 10, 0, 10)
    accent.BackgroundColor3 = Color3.fromRGB(0, 220, 140)
    accent.BorderSizePixel  = 0
    accent.Parent           = frame
    local accentCorner = Instance.new("UICorner")
    accentCorner.CornerRadius = UDim.new(1, 0)
    accentCorner.Parent = accent

    local title = Instance.new("TextLabel")
    title.BackgroundTransparency = 1
    title.Position               = UDim2.new(0, 24, 0, 14)
    title.Size                   = UDim2.new(1, -36, 0, 26)
    title.Font                   = Enum.Font.GothamBold
    title.Text                   = "✅ 功能已开启"
    title.TextColor3             = Color3.fromRGB(0, 235, 150)
    title.TextSize               = 20
    title.TextXAlignment         = Enum.TextXAlignment.Left
    title.Parent                 = frame

    local sub = Instance.new("TextLabel")
    sub.BackgroundTransparency = 1
    sub.Position               = UDim2.new(0, 24, 0, 42)
    sub.Size                   = UDim2.new(1, -36, 0, 20)
    sub.Font                   = Enum.Font.Gotham
    sub.Text                   = "没效果就再注入一次"
    sub.TextColor3             = Color3.fromRGB(200, 205, 215)
    sub.TextSize               = 15
    sub.TextXAlignment         = Enum.TextXAlignment.Left
    sub.Parent                 = frame

    local bar = Instance.new("Frame")
    bar.AnchorPoint        = Vector2.new(0, 1)
    bar.Position           = UDim2.new(0, 12, 1, -8)
    bar.Size               = UDim2.new(1, -24, 0, 3)
    bar.BackgroundColor3   = Color3.fromRGB(45, 50, 60)
    bar.BorderSizePixel    = 0
    bar.Parent             = frame
    local barCorner = Instance.new("UICorner")
    barCorner.CornerRadius = UDim.new(1, 0)
    barCorner.Parent = bar

    local fill = Instance.new("Frame")
    fill.Size             = UDim2.new(1, 0, 1, 0)
    fill.BackgroundColor3 = Color3.fromRGB(0, 220, 140)
    fill.BorderSizePixel  = 0
    fill.Parent           = bar
    local fillCorner = Instance.new("UICorner")
    fillCorner.CornerRadius = UDim.new(1, 0)
    fillCorner.Parent = fill

    -- 入场动画
    frame.Position               = UDim2.new(0.5, 0, 0, 40)
    frame.BackgroundTransparency = 1
    title.TextTransparency       = 1
    sub.TextTransparency         = 1
    TweenService:Create(frame, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        Position = UDim2.new(0.5, 0, 0, 90),
        BackgroundTransparency = 0.06,
    }):Play()
    TweenService:Create(title, TweenInfo.new(0.25), { TextTransparency = 0 }):Play()
    TweenService:Create(sub, TweenInfo.new(0.25), { TextTransparency = 0 }):Play()

    -- 3 秒倒计时条
    TweenService:Create(fill, TweenInfo.new(3, Enum.EasingStyle.Linear), {
        Size = UDim2.new(0, 0, 1, 0),
    }):Play()

    local closed = false
    local function closeToast()
        if closed then return end
        closed = true
        if gui.Parent then
            TweenService:Create(frame, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
                Position = UDim2.new(0.5, 0, 0, 40),
                BackgroundTransparency = 1,
            }):Play()
            TweenService:Create(title, TweenInfo.new(0.35), { TextTransparency = 1 }):Play()
            TweenService:Create(sub, TweenInfo.new(0.35), { TextTransparency = 1 }):Play()
            task.delay(0.4, function()
                pcall(function() gui:Destroy() end)
            end)
        end
    end

    env.__ATM_TOAST_CLOSE = closeToast
    task.delay(3, closeToast)   -- 3 秒后自动关闭
end

return "ATM_DIRECT_ARMED"
