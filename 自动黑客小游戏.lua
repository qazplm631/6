-- ═══════════════════════════════════════════════════════════════
--  ATM · hackingMinigame 直接完成 + UI 开关
--  注入后右上角出现控制面板:点击按钮/按 RightShift 即时启停
--  面板可拖动,重复注入会自动清理上一版
-- ═══════════════════════════════════════════════════════════════
local env = getgenv()

-- 清理上一版(重复注入时不叠加)
if env.__ATM_DIRECT_STOP then pcall(env.__ATM_DIRECT_STOP) end
if env.__ATM_UI_DESTROY  then pcall(env.__ATM_UI_DESTROY)  end

if not hookfunction or not getcallbackvalue then return "MISSING_EXECUTOR_API" end

local Players = game:GetService("Players")
local UIS     = game:GetService("UserInputService")
local PLR     = Players.LocalPlayer

-- ── 要拦截的调用名(想扩别的功能往这里加) ─────────────────────
local TARGETS = { hackingMinigame = true }

-- ── 拿目标回调 ──────────────────────────────────────────────
local remote = game.ReplicatedStorage:WaitForChild("Remote"):WaitForChild("PlayerFunc")
local ok, callback = pcall(getcallbackvalue, remote, "OnClientInvoke")
if not ok or type(callback) ~= "function" then return "NO_CALLBACK" end

local active = true
local hits   = 0

-- ── UI 挂载点 ───────────────────────────────────────────────
local function uiParent()
    if type(gethui) == "function" then
        local s, h = pcall(gethui)
        if s and h then return h end
    end
    local s, cg = pcall(function() return game:GetService("CoreGui") end)
    if s and cg and cg.Parent then return cg end
    return PLR:WaitForChild("PlayerGui")
end

local parent = uiParent()
local stale  = parent:FindFirstChild("ATM_DirectStop")
if stale then stale:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name          = "ATM_DirectStop"
gui.ResetOnSpawn  = false
gui.IgnoreGuiInset = true
gui.DisplayOrder  = 999
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent        = parent

-- ── 主面板 ──────────────────────────────────────────────────
local panel = Instance.new("Frame")
panel.Name              = "Panel"
panel.AnchorPoint       = Vector2.new(1, 0)
panel.Position          = UDim2.new(1, -18, 0, 92)
panel.Size              = UDim2.fromOffset(234, 128)
panel.BackgroundColor3  = Color3.fromRGB(18, 20, 26)
panel.BorderSizePixel   = 0
panel.Active            = true
panel.Parent            = gui

local corner = Instance.new("UICorner", panel)
corner.CornerRadius = UDim.new(0, 12)

local stroke = Instance.new("UIStroke", panel)
stroke.Color        = Color3.fromRGB(58, 64, 82)
stroke.Thickness    = 1
stroke.Transparency = 0.25

local grad = Instance.new("UIGradient", panel)
grad.Rotation   = 90
grad.Color      = Color3.new(0, 0, 0)
grad.Transparency = NumberSequence.new({
    NumberSequenceKeypoint.new(0, 0.55),
    NumberSequenceKeypoint.new(1, 0.9),
})

-- 标题
local title = Instance.new("TextLabel")
title.Size                   = UDim2.new(1, -20, 0, 24)
title.Position               = UDim2.new(0, 12, 0, 8)
title.BackgroundTransparency = 1
title.Font                   = Enum.Font.GothamBold
title.TextSize               = 13
title.TextXAlignment         = Enum.TextXAlignment.Left
title.TextColor3             = Color3.fromRGB(235, 238, 245)
title.Text                   = "ATM · Direct Stop"
title.Parent                 = panel

-- 状态圆点
local dot = Instance.new("Frame")
dot.Name             = "Dot"
dot.Size             = UDim2.fromOffset(9, 9)
dot.Position         = UDim2.new(0, 12, 0, 42)
dot.BackgroundColor3 = Color3.fromRGB(64, 214, 130)
dot.BorderSizePixel  = 0
dot.Parent           = panel

local dotCorner = Instance.new("UICorner", dot)
dotCorner.CornerRadius = UDim.new(1, 0)

-- 状态文字
local status = Instance.new("TextLabel")
status.Size                   = UDim2.new(1, -40, 0, 16)
status.Position               = UDim2.new(0, 30, 0, 37)
status.BackgroundTransparency = 1
status.Font                   = Enum.Font.GothamMedium
status.TextSize               = 12
status.TextXAlignment         = Enum.TextXAlignment.Left
status.TextColor3             = Color3.fromRGB(120, 226, 168)
status.Text                   = "已启用 · ARMED"
status.Parent                 = panel

-- 开关按钮
local btn = Instance.new("TextButton")
btn.Size             = UDim2.new(1, -24, 0, 34)
btn.Position         = UDim2.new(0, 12, 0, 62)
btn.BackgroundColor3 = Color3.fromRGB(38, 158, 94)
btn.BorderSizePixel  = 0
btn.AutoButtonColor  = false
btn.Font             = Enum.Font.GothamBold
btn.TextSize         = 13
btn.TextColor3       = Color3.fromRGB(255, 255, 255)
btn.Text             = "开关已打开  点我停用"
btn.Parent           = panel

local btnCorner = Instance.new("UICorner", btn)
btnCorner.CornerRadius = UDim.new(0, 8)

-- 底部统计
local foot = Instance.new("TextLabel")
foot.Size                   = UDim2.new(1, -24, 0, 16)
foot.Position               = UDim2.new(0, 12, 0, 102)
foot.BackgroundTransparency = 1
foot.Font                   = Enum.Font.Gotham
foot.TextSize               = 11
foot.TextXAlignment         = Enum.TextXAlignment.Left
foot.TextColor3             = Color3.fromRGB(130, 138, 155)
foot.Text                   = "命中 0 次 · 可拖动 · RightShift 快捷键"
foot.Parent                 = panel

-- ── 状态同步 ────────────────────────────────────────────────
local function setActive(on)
    active = on
    if on then
        dot.BackgroundColor3    = Color3.fromRGB(64, 214, 130)
        status.Text             = "已启用 · ARMED"
        status.TextColor3       = Color3.fromRGB(120, 226, 168)
        btn.BackgroundColor3    = Color3.fromRGB(38, 158, 94)
        btn.Text                = "开关已打开  点我停用"
        stroke.Color            = Color3.fromRGB(58, 64, 82)
    else
        dot.BackgroundColor3    = Color3.fromRGB(96, 102, 118)
        status.Text             = "已关闭 · PAUSED"
        status.TextColor3       = Color3.fromRGB(150, 156, 170)
        btn.BackgroundColor3    = Color3.fromRGB(92, 96, 108)
        btn.Text                = "开关已关闭  点我启用"
        stroke.Color            = Color3.fromRGB(96, 102, 118)
    end
    foot.Text = string.format("命中 %d 次 · 可拖动 · RightShift 快捷键", hits)
end

local function refresh()
    foot.Text = string.format("命中 %d 次 · 可拖动 · RightShift 快捷键", hits)
end

-- ── 交互 ────────────────────────────────────────────────────
btn.MouseButton1Click:Connect(function()
    setActive(not active)
end)

btn.MouseEnter:Connect(function()
    btn.BackgroundColor3 = active and Color3.fromRGB(46, 182, 108) or Color3.fromRGB(108, 112, 126)
end)
btn.MouseLeave:Connect(function()
    btn.BackgroundColor3 = active and Color3.fromRGB(38, 158, 94) or Color3.fromRGB(92, 96, 108)
end)

UIS.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.KeyCode == Enum.KeyCode.RightShift then
        setActive(not active)
    end
end)

-- 拖动
do
    local dragging, dragStart, startPos
    panel.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            dragging  = true
            dragStart = input.Position
            startPos  = panel.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)
    UIS.InputChanged:Connect(function(input)
        if not dragging then return end
        if input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch then
            local d = input.Position - dragStart
            panel.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + d.X,
                startPos.Y.Scale, startPos.Y.Offset + d.Y
            )
        end
    end)
end

-- ── 核心 Hook ──────────────────────────────────────────────
local original
original = hookfunction(callback, function(name, ...)
    if active and TARGETS[name] then
        hits += 1
        task.spawn(refresh)
        return true
    end
    return original(name, ...)
end)

env.__ATM_DIRECT_STOP = function()
    active = false
    setActive(false)
end

env.__ATM_DIRECT_SET  = setActive

env.__ATM_UI_DESTROY = function()
    pcall(function() gui:Destroy() end)
    env.__ATM_UI_DESTROY = nil
end

setActive(true)
return "ATM_DIRECT_ARMED"
