--[[ 玩家传送（传送到对方头顶）
     点「人」打开玩家列表 → 点名字 → 你瞬移到该玩家头顶上方
     列表每秒刷新一次，显示在线玩家与距离
--]]

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local LP = Players.LocalPlayer

local CFG = {
    OFFSET   = Vector3.new(0, 4, 0),  -- 头顶上方多少
    MAX_LIST = 12,                    -- 最多显示多少个
    REFRESH  = 1.0,
    COOLDOWN = 0.6,
    BTN_SIZE = 64,
    BTN_POS  = { X = -80, Y = -180 },
}

local out = function(s) print("[传人] " .. s) end
local lastUse = 0
local selected = nil

local function myRoot()
    local c = LP.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end

local function targetPart(plr)
    local c = plr.Character
    if not c then return nil end
    return c:FindFirstChild("Head")
        or c:FindFirstChild("HumanoidRootPart")
        or c:FindFirstChildWhichIsA("BasePart")
end

local function teleportTo(plr)
    if os.clock() - lastUse < CFG.COOLDOWN then return end
    lastUse = os.clock()

    local r = myRoot()
    if not r then out("无角色") return end

    local part = targetPart(plr)
    if not part then out(plr.Name .. " 没有角色") return end

    local dest = CFrame.new(part.Position + CFG.OFFSET)
    local ok = pcall(function()
        r.CFrame = dest
        r.AssemblyLinearVelocity = Vector3.zero
    end)

    if ok then
        out(string.format("→ %s 头顶 (%.0f, %.0f, %.0f)",
            plr.Name, dest.X, dest.Y, dest.Z))
    else
        out("传送失败: " .. plr.Name)
    end
end

-- ===== UI =====
local pg = LP:WaitForChild("PlayerGui")
local gui = Instance.new("ScreenGui")
gui.Name = "__TP_PLAYER"
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
openBtn.Text = "人"
openBtn.TextSize = 24
openBtn.TextColor3 = Color3.new(1, 1, 1)
openBtn.Font = Enum.Font.GothamBold
openBtn.BorderSizePixel = 0
openBtn.AutoButtonColor = false
openBtn.Parent = gui

local obc = Instance.new("UICorner"); obc.CornerRadius = UDim.new(1, 0); obc.Parent = openBtn
local obs = Instance.new("UIStroke")
obs.Color = Color3.fromRGB(150, 220, 255); obs.Thickness = 2; obs.Parent = openBtn

-- 列表面板
local panel = Instance.new("Frame")
panel.Size = UDim2.new(0, 200, 0, 372)
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.new(0.5, 0, 0.5, 0)
panel.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
panel.BackgroundTransparency = 0.08
panel.BorderSizePixel = 0
panel.Visible = false
panel.Parent = gui

local pc = Instance.new("UICorner"); pc.CornerRadius = UDim.new(0, 14); pc.Parent = panel
local ps = Instance.new("UIStroke")
ps.Color = Color3.fromRGB(120, 180, 255); ps.Thickness = 2; ps.Transparency = 0.3; ps.Parent = panel

local titleBar = Instance.new("Frame")
titleBar.Size = UDim2.new(1, 0, 0, 40)
titleBar.BackgroundColor3 = Color3.fromRGB(28, 28, 38)
titleBar.BorderSizePixel = 0
titleBar.Parent = panel

local tbc = Instance.new("UICorner"); tbc.CornerRadius = UDim.new(0, 14); tbc.Parent = titleBar

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -46, 1, 0)
title.Position = UDim2.new(0, 12, 0, 0)
title.BackgroundTransparency = 1
title.Text = "传送到玩家"
title.TextSize = 15
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

local cbc = Instance.new("UICorner"); cbc.CornerRadius = UDim.new(0, 8); cbc.Parent = closeBtn

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

layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    list.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 8)
end)

-- 刷新列表
local function refresh()
    for _, child in ipairs(list:GetChildren()) do
        if child:IsA("TextButton") then child:Destroy() end
    end

    local me = myRoot()
    local entries = {}
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LP then
            local part = targetPart(plr)
            local d = (part and me) and (part.Position - me.Position).Magnitude or 9999
            entries[#entries + 1] = { plr = plr, dist = d }
        end
    end
    table.sort(entries, function(a, b) return a.dist < b.dist end)

    local count = 0
    for _, e in ipairs(entries) do
        count = count + 1
        if count > CFG.MAX_LIST then break end

        local b = Instance.new("TextButton")
        b.Size = UDim2.new(1, -8, 0, 40)
        b.LayoutOrder = count
        b.BackgroundColor3 = Color3.fromRGB(34, 40, 56)
        b.BackgroundTransparency = 0.1
        b.Text = string.format("%s   %dm", e.plr.Name, math.floor(e.dist / 1))
        b.TextSize = 15
        b.TextColor3 = Color3.fromRGB(235, 240, 255)
        b.Font = Enum.Font.GothamBold
        b.BorderSizePixel = 0
        b.AutoButtonColor = false
        b.Parent = list

        local bc = Instance.new("UICorner")
        bc.CornerRadius = UDim.new(0, 10)
        bc.Parent = b

        b.MouseButton1Click:Connect(function()
            selected = e.plr
            pcall(function() teleportTo(e.plr) end)
        end)
    end

    if count == 0 then
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(1, -8, 0, 40)
        b.LayoutOrder = 1
        b.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
        b.Text = "没有其他玩家"
        b.TextSize = 14
        b.TextColor3 = Color3.fromRGB(180, 190, 210)
        b.Font = Enum.Font.Gotham
        b.BorderSizePixel = 0
        b.Parent = list
    end
end

task.spawn(function()
    while true do
        task.wait(CFG.REFRESH)
        if panel.Visible then
            pcall(refresh)
        end
    end
end)

-- 拖动
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
titleBar.InputEnded:Connect(function() dragging = false end)

-- 开合按钮拖动状态
local bDrag, bMoved, bStartPos, bStartInput = false, false, nil, nil

openBtn.MouseButton1Click:Connect(function()
    if bMoved then return end
    panel.Visible = not panel.Visible
    openBtn.BackgroundColor3 = panel.Visible and Color3.fromRGB(200, 130, 50)
                                            or Color3.fromRGB(60, 90, 150)
    if panel.Visible then pcall(refresh) end
end)

closeBtn.MouseButton1Click:Connect(function()
    panel.Visible = false
    openBtn.BackgroundColor3 = Color3.fromRGB(60, 90, 150)
end)

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

out("已加载：点「人」选择玩家，传送到其头顶")
