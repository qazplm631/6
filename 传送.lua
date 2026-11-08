--[[ 地点传送（只保留这一个功能）
     8 个预设地点，点名字即传送
     右上「地」按钮开合列表面板，面板标题可拖动
--]]

local Players = game:GetService("Players")
local LP = Players.LocalPlayer

local CFG = {
    COOLDOWN = 0.35,
    SNAP     = false,   -- true = 传送后向下找地面贴合；false = 用精确坐标
    SAFE_Y   = 4,
    BTN_SIZE = 64,
    BTN_POS  = { X = -80, Y = -180 },
}

-- ===== 预设地点 =====
local PRESETS = {
    { name = "银行",       x = -265,  y = 5, z = -313  },
    { name = "医院",       x = -1126, y = 5, z = 1047  },
    { name = "车店",       x = -340,  y = 4, z = 980   },
    { name = "农村加油站", x = -18,   y = 4, z = 1110  },
    { name = "黑市",       x = 1088,  y = 4, z = 463   },
    { name = "消防站",     x = -421,  y = 5, z = -1122 },
    { name = "警察局",     x = 109,   y = 5, z = -1087 },
    { name = "城市加油站", x = -1129, y = 5, z = -1031 },
    { name = "消星地点",   x = -513,  y = 5, z = -518  },
}

local out = function(s) print("[地点] " .. s) end
local lastUse = 0

local function char()
    return LP.Character
end

local function root()
    local c = char()
    return c and c:FindFirstChild("HumanoidRootPart")
end

local function snapCF(cf)
    if not CFG.SNAP then return cf end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    local c = char()
    params.FilterDescendantsInstances = c and {c} or {}
    local ok, hit = pcall(function()
        return workspace:Raycast(cf.Position, Vector3.new(0, -300, 0), params)
    end)
    if ok and hit then
        return CFrame.new(hit.Position + Vector3.new(0, CFG.SAFE_Y, 0))
    end
    return cf
end

local function teleportTo(preset)
    if os.clock() - lastUse < CFG.COOLDOWN then return end
    lastUse = os.clock()

    local r = root()
    if not r then out("无角色") return end

    local dest = snapCF(CFrame.new(preset.x, preset.y, preset.z))
    local ok = pcall(function()
        r.CFrame = dest
        r.AssemblyLinearVelocity = Vector3.zero
    end)

    if ok then
        out(string.format("→ %s (%.0f, %.0f, %.0f)",
            preset.name, dest.X, dest.Y, dest.Z))
        pcall(function()
            local hum = r.Parent:FindFirstChildOfClass("Humanoid")
            if hum then hum:ChangeState(Enum.HumanoidStateType.GettingUp) end
        end)
    else
        out("传送失败: " .. preset.name)
    end
end

-- ===== UI =====
local pg = LP:WaitForChild("PlayerGui")
local gui = Instance.new("ScreenGui")
gui.Name = "__TP_LOC"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 2000
gui.Parent = pg

-- 开合按钮
local openBtn = Instance.new("TextButton")
openBtn.Size = UDim2.new(0, CFG.BTN_SIZE, 0, CFG.BTN_SIZE)
openBtn.AnchorPoint = Vector2.new(0.5, 0.5)
openBtn.Position = UDim2.new(1, CFG.BTN_POS.X, 1, CFG.BTN_POS.Y)
openBtn.BackgroundColor3 = Color3.fromRGB(60, 90, 150)
openBtn.BackgroundTransparency = 0.2
openBtn.Text = "地"
openBtn.TextSize = 24
openBtn.TextColor3 = Color3.new(1, 1, 1)
openBtn.Font = Enum.Font.GothamBold
openBtn.BorderSizePixel = 0
openBtn.AutoButtonColor = false
openBtn.Parent = gui

local obc = Instance.new("UICorner")
obc.CornerRadius = UDim.new(1, 0)
obc.Parent = openBtn

local obs = Instance.new("UIStroke")
obs.Color = Color3.fromRGB(140, 200, 255)
obs.Thickness = 2
obs.Parent = openBtn

-- 地点面板
local panel = Instance.new("Frame")
panel.Size = UDim2.new(0, 156, 0, 386)
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.new(0.5, 0, 0.5, 0)
panel.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
panel.BackgroundTransparency = 0.08
panel.BorderSizePixel = 0
panel.Visible = false
panel.Parent = gui

local pc = Instance.new("UICorner")
pc.CornerRadius = UDim.new(0, 14)
pc.Parent = panel

local ps = Instance.new("UIStroke")
ps.Color = Color3.fromRGB(120, 180, 255)
ps.Thickness = 2
ps.Transparency = 0.3
ps.Parent = panel

-- 标题栏（拖动 + 关闭）
local titleBar = Instance.new("Frame")
titleBar.Size = UDim2.new(1, 0, 0, 40)
titleBar.BackgroundColor3 = Color3.fromRGB(28, 28, 38)
titleBar.BorderSizePixel = 0
titleBar.Parent = panel

local tbc = Instance.new("UICorner")
tbc.CornerRadius = UDim.new(0, 14)
tbc.Parent = titleBar

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -46, 1, 0)
title.Position = UDim2.new(0, 12, 0, 0)
title.BackgroundTransparency = 1
title.Text = "地点传送"
title.TextSize = 16
title.Font = Enum.Font.GothamBold
title.TextColor3 = Color3.fromRGB(230, 238, 255)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = titleBar

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 30, 0, 30)
closeBtn.Position = UDim2.new(1, -38, 0, 5)
closeBtn.BackgroundColor3 = Color3.fromRGB(190, 60, 60)
closeBtn.Text = "×"
closeBtn.TextSize = 18
closeBtn.TextColor3 = Color3.new(1, 1, 1)
closeBtn.Font = Enum.Font.GothamBold
closeBtn.BorderSizePixel = 0
closeBtn.Parent = titleBar

local cbc = Instance.new("UICorner")
cbc.CornerRadius = UDim.new(0, 8)
cbc.Parent = closeBtn

-- 地点按钮列表（可滚动）
local list = Instance.new("ScrollingFrame")
list.Size = UDim2.new(1, -20, 1, -52)
list.Position = UDim2.new(0, 10, 0, 46)
list.BackgroundTransparency = 1
list.BorderSizePixel = 0
list.ScrollBarThickness = 4
list.CanvasSize = UDim2.new(0, 0, 0, 0)
list.Parent = panel

local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 6)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = list

local order = 0
for _, preset in ipairs(PRESETS) do
    order = order + 1
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1, -8, 0, 40)
    b.LayoutOrder = order
    b.BackgroundColor3 = Color3.fromRGB(34, 40, 56)
    b.BackgroundTransparency = 0.1
    b.Text = preset.name
    b.TextSize = 16
    b.TextColor3 = Color3.fromRGB(235, 240, 255)
    b.Font = Enum.Font.GothamBold
    b.BorderSizePixel = 0
    b.AutoButtonColor = false
    b.Parent = list

    local bc = Instance.new("UICorner")
    bc.CornerRadius = UDim.new(0, 10)
    bc.Parent = b

    b.MouseButton1Click:Connect(function()
        pcall(function() teleportTo(preset) end)
    end)
end

layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    list.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 8)
end)

-- 面板拖动
local dragging, startPos, startInput = false, nil, nil

titleBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Touch
    or input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = true
        startPos = panel.Position
        startInput = input.Position
    end
end)
titleBar.InputChanged:Connect(function(input)
    if not dragging then return end
    if input.UserInputType == Enum.UserInputType.Touch
    or input.UserInputType == Enum.UserInputType.MouseMovement then
        local d = input.Position - startInput
        panel.Position = UDim2.new(
            startPos.X.Scale, startPos.X.Offset + d.X,
            startPos.Y.Scale, startPos.Y.Offset + d.Y)
    end
end)
titleBar.InputEnded:Connect(function()
    dragging = false
end)

-- 开合按钮的拖动状态（先声明，点击回调要读）
local bDrag, bMoved, bStartPos, bStartInput = false, false, nil, nil

-- 开合
openBtn.MouseButton1Click:Connect(function()
    if bMoved then return end

    panel.Visible = not panel.Visible
    openBtn.BackgroundColor3 = panel.Visible and Color3.fromRGB(200, 130, 50)
                                            or Color3.fromRGB(60, 90, 150)
end)

closeBtn.MouseButton1Click:Connect(function()
    panel.Visible = false
    openBtn.BackgroundColor3 = Color3.fromRGB(60, 90, 150)
end)

-- 开合按钮拖动

openBtn.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Touch
    or input.UserInputType == Enum.UserInputType.MouseButton1 then
        bDrag, bMoved = true, false
        bStartPos = openBtn.Position
        bStartInput = input.Position
    end
end)
openBtn.InputChanged:Connect(function(input)
    if not bDrag then return end
    if input.UserInputType == Enum.UserInputType.Touch
    or input.UserInputType == Enum.UserInputType.MouseMovement then
        local d = input.Position - bStartInput
        if math.abs(d.X) > 8 or math.abs(d.Y) > 8 then bMoved = true end
        if bMoved then
            openBtn.Position = UDim2.new(
                bStartPos.X.Scale, bStartPos.X.Offset + d.X,
                bStartPos.Y.Scale, bStartPos.Y.Offset + d.Y)
        end
    end
end)
openBtn.InputEnded:Connect(function()
    bDrag = false
    task.delay(0.15, function() bMoved = false end)
end)

out("已加载：9 个地点，点「地」打开列表")
