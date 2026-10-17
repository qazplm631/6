-- Generic direct-completion callback for hacking minigames in the authorized sandbox.
-- 注入成功后顶部弹出「功能已开启」提示,3 秒自动关闭。

local env = getgenv()
if env.ATM_DIRECT_STOP then env.ATM_DIRECT_STOP() end
if not hookfunction or not getcallbackvalue then return "MISSING_EXECUTOR_API" end

local remote = game.ReplicatedStorage.Remote.PlayerFunc
local ok, callback = pcall(getcallbackvalue, remote, "OnClientInvoke")
if not ok or type(callback) ~= "function" then return "NO_CALLBACK" end

local triggerDelay = 0.5 -- 可通过界面动态修改，单位：秒

local active = true
local original
original = hookfunction(callback, function(name, ...)
    if active and name == "hackingMinigame" then
        if triggerDelay > 0 then
            task.wait(triggerDelay)
        end
        return true
    end
    return original(name, ...)
end)

env.__ATM_DIRECT_STOP = function()
    active = false
end

-- ===== 常驻设置 UI：自定义触发延迟 + 缩小/展开 =====
do
    local Players = game:GetService("Players")
    local TweenService = game:GetService("TweenService")
    local player = Players.LocalPlayer

    if env.__ATM_DELAY_GUI then
        pcall(function() env.__ATM_DELAY_GUI:Destroy() end)
    end

    local delayGui = Instance.new("ScreenGui")
    delayGui.Name = "ATM_DELAY_CONFIG"
    delayGui.ResetOnSpawn = false
    delayGui.IgnoreGuiInset = true
    delayGui.DisplayOrder = 999998
    delayGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

    local parentOk = pcall(function()
        if gethui then
            delayGui.Parent = gethui()
        else
            delayGui.Parent = player:WaitForChild("PlayerGui")
        end
    end)
    if not parentOk then
        pcall(function() delayGui.Parent = player:WaitForChild("PlayerGui") end)
    end
    env.__ATM_DELAY_GUI = delayGui

    local panel = Instance.new("Frame")
    panel.Name = "Panel"
    panel.Position = UDim2.new(1, -272, 0, 145)
    panel.Size = UDim2.new(0, 256, 0, 150)
    panel.BackgroundColor3 = Color3.fromRGB(22, 25, 32)
    panel.BackgroundTransparency = 0.04
    panel.BorderSizePixel = 0
    panel.Parent = delayGui

    local panelCorner = Instance.new("UICorner")
    panelCorner.CornerRadius = UDim.new(0, 10)
    panelCorner.Parent = panel

    local panelStroke = Instance.new("UIStroke")
    panelStroke.Color = Color3.fromRGB(0, 220, 140)
    panelStroke.Thickness = 1.2
    panelStroke.Transparency = 0.18
    panelStroke.Parent = panel

    local header = Instance.new("Frame")
    header.Size = UDim2.new(1, 0, 0, 36)
    header.BackgroundColor3 = Color3.fromRGB(31, 36, 45)
    header.BorderSizePixel = 0
    header.Parent = panel
    local headerCorner = Instance.new("UICorner")
    headerCorner.CornerRadius = UDim.new(0, 10)
    headerCorner.Parent = header

    local title = Instance.new("TextLabel")
    title.BackgroundTransparency = 1
    title.Position = UDim2.new(0, 12, 0, 0)
    title.Size = UDim2.new(1, -55, 1, 0)
    title.Font = Enum.Font.GothamBold
    title.Text = "触发延迟设置"
    title.TextColor3 = Color3.fromRGB(0, 235, 150)
    title.TextSize = 15
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = header

    local minimizeButton = Instance.new("TextButton")
    minimizeButton.Name = "MinimizeToggle"
    minimizeButton.Position = UDim2.new(1, -34, 0, 5)
    minimizeButton.Size = UDim2.new(0, 27, 0, 26)
    minimizeButton.BackgroundColor3 = Color3.fromRGB(48, 56, 67)
    minimizeButton.BorderSizePixel = 0
    minimizeButton.Font = Enum.Font.GothamBold
    minimizeButton.Text = "−"
    minimizeButton.TextColor3 = Color3.fromRGB(240, 243, 248)
    minimizeButton.TextSize = 19
    minimizeButton.Parent = header
    local minCorner = Instance.new("UICorner")
    minCorner.CornerRadius = UDim.new(0, 6)
    minCorner.Parent = minimizeButton

    local body = Instance.new("Frame")
    body.Name = "Body"
    body.Position = UDim2.new(0, 0, 0, 36)
    body.Size = UDim2.new(1, 0, 1, -36)
    body.BackgroundTransparency = 1
    body.Parent = panel

    local delayLabel = Instance.new("TextLabel")
    delayLabel.BackgroundTransparency = 1
    delayLabel.Position = UDim2.new(0, 12, 0, 8)
    delayLabel.Size = UDim2.new(1, -24, 0, 20)
    delayLabel.Font = Enum.Font.Gotham
    delayLabel.Text = "执行触发延迟（秒，0–60）"
    delayLabel.TextColor3 = Color3.fromRGB(220, 225, 233)
    delayLabel.TextSize = 13
    delayLabel.TextXAlignment = Enum.TextXAlignment.Left
    delayLabel.Parent = body

    local delayInput = Instance.new("TextBox")
    delayInput.Name = "DelayInput"
    delayInput.Position = UDim2.new(0, 12, 0, 34)
    delayInput.Size = UDim2.new(0, 112, 0, 32)
    delayInput.BackgroundColor3 = Color3.fromRGB(39, 45, 56)
    delayInput.BorderSizePixel = 0
    delayInput.ClearTextOnFocus = false
    delayInput.Font = Enum.Font.Gotham
    delayInput.PlaceholderText = "秒数，例如 0.5"
    delayInput.Text = tostring(triggerDelay)
    delayInput.TextColor3 = Color3.fromRGB(255, 255, 255)
    delayInput.PlaceholderColor3 = Color3.fromRGB(145, 153, 166)
    delayInput.TextSize = 13
    delayInput.Parent = body
    local inputCorner = Instance.new("UICorner")
    inputCorner.CornerRadius = UDim.new(0, 6)
    inputCorner.Parent = delayInput

    local applyButton = Instance.new("TextButton")
    applyButton.Name = "ApplyDelay"
    applyButton.Position = UDim2.new(0, 132, 0, 34)
    applyButton.Size = UDim2.new(0, 112, 0, 32)
    applyButton.BackgroundColor3 = Color3.fromRGB(0, 170, 110)
    applyButton.BorderSizePixel = 0
    applyButton.Font = Enum.Font.GothamBold
    applyButton.Text = "应用延迟"
    applyButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    applyButton.TextSize = 13
    applyButton.Parent = body
    local applyCorner = Instance.new("UICorner")
    applyCorner.CornerRadius = UDim.new(0, 6)
    applyCorner.Parent = applyButton

    local status = Instance.new("TextLabel")
    status.Name = "Status"
    status.BackgroundTransparency = 1
    status.Position = UDim2.new(0, 12, 0, 75)
    status.Size = UDim2.new(1, -24, 0, 22)
    status.Font = Enum.Font.Gotham
    status.Text = string.format("当前延迟：%.2f 秒", triggerDelay)
    status.TextColor3 = Color3.fromRGB(165, 220, 195)
    status.TextSize = 12
    status.TextXAlignment = Enum.TextXAlignment.Left
    status.Parent = body

    local function applyDelay()
        local value = tonumber(delayInput.Text)
        if not value or value < 0 or value > 60 then
            status.Text = "请输入 0 到 60 之间的数字"
            status.TextColor3 = Color3.fromRGB(255, 130, 130)
            return
        end
        triggerDelay = value
        status.Text = string.format("已应用：%.2f 秒", triggerDelay)
        status.TextColor3 = Color3.fromRGB(165, 220, 195)
    end
    applyButton.MouseButton1Click:Connect(applyDelay)
    delayInput.FocusLost:Connect(function(enterPressed)
        if enterPressed then applyDelay() end
    end)

    local minimized = false
    minimizeButton.MouseButton1Click:Connect(function()
        minimized = not minimized
        body.Visible = not minimized
        minimizeButton.Text = minimized and "+" or "−"
        TweenService:Create(panel, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            Size = minimized and UDim2.new(0, 256, 0, 36) or UDim2.new(0, 256, 0, 150)
        }):Play()
    end)
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
