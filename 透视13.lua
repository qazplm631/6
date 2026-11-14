--[[============================================================
  Roblox 透视 / ESP —— 手机执行器版
  适配：Delta / Arceus X / Fluxus / Hydrogen / Cryptic / Ronix
        (Android、iOS 越狱；PC 端 Krnl / Fluxus 同样可用)
  渲染：优先 Drawing API（不创建任何 Instance，最难被扫到）
        无 Drawing 时自动降级 ScreenGui + Frame
  UI  ：左下悬浮球，可拖动；轻点展开设置面板
  纯客户端渲染，不写角色、不发远程，服务端无法从状态上分辨
============================================================]]--

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UIS              = game:GetService("UserInputService")
local LP               = Players.LocalPlayer

-- 重复执行先卸载旧实例
if getgenv and getgenv().ESP_Unload then pcall(getgenv().ESP_Unload) end

--============================== 配置 ==============================
local CFG = {
    Enabled     = true,    -- 总开关
    Box         = true,    -- 方框
    Name        = true,    -- 名字
    Health      = true,    -- 血条
    Distance    = true,    -- 距离
    Tracer      = false,   -- 屏幕底部到目标的射线
    Skeleton    = false,   -- 骨骼
    TeamCheck   = true,    -- 过滤队友
    VisCheck    = false,   -- 可见性射线（穿墙变色，开销大）
    MaxDistance = 1500,    -- 最大距离（studs）
    FPS         = 30,      -- 刷新率，手机建议 20~30
}

local C_VIS      = Color3.fromRGB(0, 255, 140)    -- 可见 / 默认
local C_HID      = Color3.fromRGB(255, 60, 60)    -- 不可见
local C_OUTLINE  = Color3.fromRGB(0, 0, 0)
local C_WHITE    = Color3.fromRGB(255, 255, 255)

local BONES_R15 = {
    {"Head","UpperTorso"},{"UpperTorso","LowerTorso"},
    {"UpperTorso","LeftUpperArm"},{"LeftUpperArm","LeftLowerArm"},{"LeftLowerArm","LeftHand"},
    {"UpperTorso","RightUpperArm"},{"RightUpperArm","RightLowerArm"},{"RightLowerArm","RightHand"},
    {"LowerTorso","LeftUpperLeg"},{"LeftUpperLeg","LeftLowerLeg"},{"LeftLowerLeg","LeftFoot"},
    {"LowerTorso","RightUpperLeg"},{"RightUpperLeg","RightLowerLeg"},{"RightLowerLeg","RightFoot"},
}
local BONES_R6 = {
    {"Head","Torso"},{"Torso","Left Arm"},{"Torso","Right Arm"},
    {"Torso","Left Leg"},{"Torso","Right Leg"},
}

--========================== 渲染适配层 ============================
local HAS_DRAWING = false
pcall(function()
    local s = Drawing.new("Square")
    s:Remove()
    HAS_DRAWING = true
end)

local Canvas = nil   -- 无 Drawing 时的父容器
if not HAS_DRAWING then
    local parent = nil
    pcall(function() parent = gethui() end)
    if not parent then
        local ok, cg = pcall(function() return game:GetService("CoreGui") end)
        parent = (ok and cg) or LP:WaitForChild("PlayerGui")
    end
    local sg = Instance.new("ScreenGui")
    sg.Name = "c_" .. tostring(math.random(100000, 999999))
    sg.ResetOnSpawn = false
    sg.IgnoreGuiInset = true
    sg.DisplayOrder = 999998
    pcall(function()
        if syn and syn.protect_gui then syn.protect_gui(sg) end
        if protectgui then protectgui(sg) end
    end)
    sg.Parent = parent
    Canvas = sg
end

-- 矩形：filled=false 为空心框
local function makeRect(filled, thickness)
    if HAS_DRAWING then
        local d = Drawing.new("Square")
        d.Thickness = thickness or 1
        d.Filled = filled
        d.Transparency = 1
        d.Visible = false
        return {
            set = function(x, y, w, h, color, vis, trans)
                d.Position = Vector2.new(x, y)
                d.Size = Vector2.new(w, h)
                d.Color = color
                d.Transparency = trans or 1
                d.Visible = vis
            end,
            remove = function() pcall(function() d:Remove() end) end,
        }
    end
    local f = Instance.new("Frame")
    f.BorderSizePixel = 0
    f.BackgroundColor3 = C_WHITE
    f.BackgroundTransparency = filled and 0.6 or 1
    f.Visible = false
    local stroke = nil
    if not filled then
        stroke = Instance.new("UIStroke")
        stroke.Thickness = thickness or 1
        stroke.Color = C_WHITE
        stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        stroke.Parent = f
    end
    f.Parent = Canvas
    return {
        set = function(x, y, w, h, color, vis, trans)
            f.Position = UDim2.fromOffset(math.floor(x), math.floor(y))
            f.Size = UDim2.fromOffset(math.max(0, math.floor(w)), math.max(0, math.floor(h)))
            if filled then
                f.BackgroundColor3 = color
                f.BackgroundTransparency = trans or 0.6
            else
                stroke.Color = color
            end
            f.Visible = vis
        end,
        remove = function() f:Destroy() end,
    }
end

-- 文字：x 传入的是水平中心
local function makeText(size)
    if HAS_DRAWING then
        local t = Drawing.new("Text")
        t.Size = size
        -- 不同执行器的 Text 属性支持有差异，逐个 pcall 赋值
        pcall(function() t.Center = true end)
        pcall(function() t.Outline = true end)
        pcall(function() t.OutlineColor = C_OUTLINE end)
        t.Visible = false
        return {
            set = function(text, x, y, color, vis)
                t.Text = text
                t.Position = Vector2.new(x, y)
                t.Color = color
                t.Visible = vis
            end,
            remove = function() pcall(function() t:Remove() end) end,
        }
    end
    local l = Instance.new("TextLabel")
    l.BackgroundTransparency = 1
    l.Font = Enum.Font.GothamBold
    l.TextSize = size
    l.TextColor3 = C_WHITE
    l.TextStrokeTransparency = 0
    l.TextStrokeColor3 = C_OUTLINE
    l.AnchorPoint = Vector2.new(0.5, 0)
    l.Size = UDim2.fromOffset(220, size + 6)
    l.TextXAlignment = Enum.TextXAlignment.Center
    l.Visible = false
    l.Parent = Canvas
    return {
        set = function(text, x, y, color, vis)
            l.Text = text
            l.Position = UDim2.fromOffset(math.floor(x), math.floor(y))
            l.TextColor3 = color
            l.Visible = vis
        end,
        remove = function() l:Destroy() end,
    }
end

local function makeLine(thickness)
    if HAS_DRAWING then
        local d = Drawing.new("Line")
        d.Thickness = thickness or 1
        d.Transparency = 0.85
        d.Visible = false
        return {
            set = function(x1, y1, x2, y2, color, vis)
                d.From = Vector2.new(x1, y1)
                d.To = Vector2.new(x2, y2)
                d.Color = color
                d.Visible = vis
            end,
            remove = function() pcall(function() d:Remove() end) end,
        }
    end
    local f = Instance.new("Frame")
    f.BorderSizePixel = 0
    f.BackgroundColor3 = C_WHITE
    f.Visible = false
    f.Parent = Canvas
    return {
        set = function(x1, y1, x2, y2, color, vis)
            local dx, dy = x2 - x1, y2 - y1
            local len = math.sqrt(dx * dx + dy * dy)
            f.AnchorPoint = Vector2.new(0, 0.5)
            f.Position = UDim2.fromOffset(math.floor(x1), math.floor(y1))
            f.Size = UDim2.fromOffset(math.floor(len), thickness or 1)
            f.Rotation = math.deg(math.atan2(dy, dx))
            f.BackgroundColor3 = color
            f.Visible = vis
        end,
        remove = function() f:Destroy() end,
    }
end

--============================ 对象池 =============================
local OBJ = {}

local function newObj()
    local o = {
        boxo = makeRect(false, 3),   -- 黑色描边：必须先创建，才排在彩色框下层
        box  = makeRect(false, 1),   -- 彩色细框
        name = makeText(13),
        hpBg = makeRect(true, 1),
        hp   = makeRect(true, 1),
        dist = makeText(12),
        ray  = makeLine(1),
        bone = {},
    }
    for i = 1, 20 do o.bone[i] = makeLine(1) end
    return o
end

local function hideObj(o)
    o.box.set(0, 0, 0, 0, C_WHITE, false)
    o.boxo.set(0, 0, 0, 0, C_WHITE, false)
    o.name.set("", 0, 0, C_WHITE, false)
    o.hpBg.set(0, 0, 0, 0, C_WHITE, false)
    o.hp.set(0, 0, 0, 0, C_WHITE, false)
    o.dist.set("", 0, 0, C_WHITE, false)
    o.ray.set(0, 0, 0, 0, C_WHITE, false)
    for i = 1, #o.bone do o.bone[i].set(0, 0, 0, 0, C_WHITE, false) end
end

local function dropObj(o)
    o.box.remove(); o.boxo.remove(); o.name.remove()
    o.hpBg.remove(); o.hp.remove(); o.dist.remove(); o.ray.remove()
    for i = 1, #o.bone do o.bone[i].remove() end
end

--============================ 工具函数 ============================
local function hpColor(r)
    if r > 0.6 then return Color3.fromRGB(0, 255, 120) end
    if r > 0.3 then return Color3.fromRGB(255, 200, 0) end
    return Color3.fromRGB(255, 60, 60)
end

local function clamp01(x)
    if x < 0 then return 0 end
    if x > 1 then return 1 end
    return x
end

local RAY_PARAMS = RaycastParams.new()
pcall(function() RAY_PARAMS.FilterType = Enum.RaycastFilterType.Exclude end)
pcall(function() RAY_PARAMS.FilterType = Enum.RaycastFilterType.Blacklist end)
local RAY_IGNORE = {}

local function isVisible(cam, char, pos)
    local list = {}
    if LP.Character then list[#list + 1] = LP.Character end
    list[#list + 1] = cam
    RAY_PARAMS.FilterDescendantsInstances = list
    local dir = pos - cam.CFrame.Position
    local ok, hit = pcall(function()
        return workspace:Raycast(cam.CFrame.Position, dir, RAY_PARAMS)
    end)
    if not ok or not hit then return true end
    return hit.Instance:IsDescendantOf(char)
end

--============================ 渲染主循环 ==========================
local lastTime = 0
local vpCenter = Vector2.new(0, 0)

local function render()
    local cam = workspace.CurrentCamera
    if not cam then return end
    local vp = cam.ViewportSize
    vpCenter = Vector2.new(vp.X * 0.5, vp.Y)

    local myChar = LP.Character
    local myTeam = LP.Team

    for _, plr in ipairs(Players:GetPlayers()) do
        local o = OBJ[plr]
        if not o then
            o = newObj()
            OBJ[plr] = o
        end

        local skip = (plr == LP)
            or (CFG.TeamCheck and myTeam ~= nil and plr.Team == myTeam)

        local char = plr.Character
        local hum  = char and char:FindFirstChildOfClass("Humanoid")
        local hrp  = char and char:FindFirstChild("HumanoidRootPart")

        if (not CFG.Enabled) or skip or (not hum) or (not hrp) or hum.Health <= 0 then
            hideObj(o)
        else
            local head = char:FindFirstChild("Head")
            local topPos = (head and head.Position or hrp.Position) + Vector3.new(0, 0.7, 0)
            local botPos = hrp.Position - Vector3.new(0, 3, 0)
            local sp1, on1 = cam:WorldToViewportPoint(topPos)
            local sp2, on2 = cam:WorldToViewportPoint(botPos)
            local dist = (hrp.Position - cam.CFrame.Position).Magnitude

            if (not (on1 or on2)) or sp1.Z <= 0 or sp2.Z <= 0 or dist > CFG.MaxDistance then
                hideObj(o)
            else
                local h = math.abs(sp2.Y - sp1.Y)
                if h < 6 then h = 6 end
                local w = h * 0.55
                local bx = sp1.X - w * 0.5
                local by = sp1.Y
                local cx = sp1.X

                local color = C_VIS
                if CFG.VisCheck then
                    color = isVisible(cam, char, hrp.Position) and C_VIS or C_HID
                end

                -- 方框
                o.boxo.set(bx, by, w, h, C_OUTLINE, CFG.Box)
                o.box.set(bx, by, w, h, color, CFG.Box)

                -- 名字
                o.name.set(plr.Name, cx, by - 16, C_WHITE, CFG.Name)

                -- 血条
                local ratio = clamp01(hum.Health / math.max(hum.MaxHealth, 1))
                local barW = 2
                local barX = bx - barW - 2
                o.hpBg.set(barX, by, barW, h, C_OUTLINE, CFG.Health, 0.35)
                o.hp.set(barX, by + h * (1 - ratio), barW, h * ratio, hpColor(ratio), CFG.Health, 0.15)

                -- 距离
                o.dist.set(string.format("%d m", math.floor(dist)), cx, by + h + 2, color, CFG.Distance)

                -- 射线
                o.ray.set(vpCenter.X, vpCenter.Y, cx, by + h, color, CFG.Tracer)

                -- 骨骼
                local idx = 0
                if CFG.Skeleton then
                    local list = char:FindFirstChild("UpperTorso") and BONES_R15 or BONES_R6
                    for _, pair in ipairs(list) do
                        idx = idx + 1
                        local a = char:FindFirstChild(pair[1])
                        local b = char:FindFirstChild(pair[2])
                        local ln = o.bone[idx]
                        if a and b and ln then
                            local pa, oa = cam:WorldToViewportPoint(a.Position)
                            local pb, ob = cam:WorldToViewportPoint(b.Position)
                            if oa and ob and pa.Z > 0 and pb.Z > 0 then
                                ln.set(pa.X, pa.Y, pb.X, pb.Y, color, true)
                            else
                                ln.set(0, 0, 0, 0, color, false)
                            end
                        elseif ln then
                            ln.set(0, 0, 0, 0, color, false)
                        end
                    end
                end
                for i = idx + 1, #o.bone do o.bone[i].set(0, 0, 0, 0, color, false) end
            end
        end
    end
end

local renderWarned = false
local conn = RunService.RenderStepped:Connect(function()
    local t = os.clock()
    local interval = 1 / math.max(CFG.FPS, 5)
    if t - lastTime < interval then return end
    lastTime = t
    local ok, err = pcall(render)
    if not ok and not renderWarned then
        renderWarned = true
        warn("[ESP] render error: " .. tostring(err))
    end
end)

Players.PlayerRemoving:Connect(function(plr)
    local o = OBJ[plr]
    if o then
        dropObj(o)
        OBJ[plr] = nil
    end
end)

--============================== UI ================================
local UI = {}

local function buildUI()
    local parent = nil
    pcall(function() parent = gethui() end)
    if not parent then
        local ok, cg = pcall(function() return game:GetService("CoreGui") end)
        parent = (ok and cg) or LP:WaitForChild("PlayerGui")
    end

    local gui = Instance.new("ScreenGui")
    gui.Name = "u_" .. tostring(math.random(100000, 999999))
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 999999
    pcall(function()
        if syn and syn.protect_gui then syn.protect_gui(gui) end
        if protectgui then protectgui(gui) end
    end)
    gui.Parent = parent

    -- 悬浮球
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.fromOffset(54, 54)
    btn.Position = UDim2.new(0, 10, 0.35, 0)
    btn.BackgroundColor3 = Color3.fromRGB(20, 22, 26)
    btn.BackgroundTransparency = 0.1
    btn.Text = "ESP"
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 15
    btn.TextColor3 = C_VIS
    btn.AutoButtonColor = false
    btn.BorderSizePixel = 0
    btn.Parent = gui
    local uc = Instance.new("UICorner")
    uc.CornerRadius = UDim.new(1, 0)
    uc.Parent = btn
    local us = Instance.new("UIStroke")
    us.Color = C_VIS
    us.Thickness = 1.5
    us.Transparency = 0.25
    us.Parent = btn

    -- 面板
    local panel = Instance.new("Frame")
    panel.Size = UDim2.fromOffset(196, 306)
    panel.Position = UDim2.new(0, 74, 0.2, 0)
    panel.BackgroundColor3 = Color3.fromRGB(16, 17, 21)
    panel.BackgroundTransparency = 0.06
    panel.BorderSizePixel = 0
    panel.Visible = false
    panel.Parent = gui
    local pc = Instance.new("UICorner")
    pc.CornerRadius = UDim.new(0, 10)
    pc.Parent = panel
    local ps = Instance.new("UIStroke")
    ps.Color = Color3.fromRGB(60, 65, 78)
    ps.Thickness = 1
    ps.Parent = panel

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -12, 0, 28)
    title.Position = UDim2.fromOffset(8, 4)
    title.BackgroundTransparency = 1
    title.Text = "ESP 设置"
    title.Font = Enum.Font.GothamBold
    title.TextSize = 13
    title.TextColor3 = Color3.fromRGB(200, 205, 215)
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = panel

    local list = Instance.new("ScrollingFrame")
    list.Size = UDim2.new(1, -12, 1, -38)
    list.Position = UDim2.fromOffset(6, 32)
    list.BackgroundTransparency = 1
    list.BorderSizePixel = 0
    list.ScrollBarThickness = 3
    list.CanvasSize = UDim2.fromOffset(0, 0)
    list.AutomaticCanvasSize = Enum.AutomaticSize.Y
    list.Parent = panel

    local lay = Instance.new("UIListLayout")
    lay.Padding = UDim.new(0, 5)
    lay.SortOrder = Enum.SortOrder.LayoutOrder
    lay.Parent = list

    local items = {
        {"Enabled", "总开关"},
        {"Box", "方框"},
        {"Name", "名字"},
        {"Health", "血条"},
        {"Distance", "距离"},
        {"Tracer", "射线"},
        {"Skeleton", "骨骼"},
        {"TeamCheck", "队友过滤"},
        {"VisCheck", "可见性检测"},
    }

    local COLOR_ON  = Color3.fromRGB(0, 110, 70)
    local COLOR_OFF = Color3.fromRGB(42, 44, 52)

    local function makeRow(text, order, onClick)
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(1, -6, 0, 30)
        b.BackgroundColor3 = COLOR_OFF
        b.BorderSizePixel = 0
        b.Text = "  " .. text
        b.Font = Enum.Font.GothamMedium
        b.TextSize = 13
        b.TextColor3 = C_WHITE
        b.TextXAlignment = Enum.TextXAlignment.Left
        b.AutoButtonColor = false
        b.LayoutOrder = order
        b.Parent = list
        local c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(0, 6)
        c.Parent = b
        b.MouseButton1Click:Connect(onClick)
        return b
    end

    for i, it in ipairs(items) do
        local key, label = it[1], it[2]
        local row
        row = makeRow(label, i, function()
            CFG[key] = not CFG[key]
            row.BackgroundColor3 = CFG[key] and COLOR_ON or COLOR_OFF
            if key == "Enabled" then
                btn.TextColor3 = CFG[key] and C_VIS or Color3.fromRGB(130, 130, 140)
                us.Color = btn.TextColor3
            end
        end)
        row.BackgroundColor3 = CFG[key] and COLOR_ON or COLOR_OFF
    end

    -- 距离档位
    local steps = {500, 1000, 1500, 2500, 5000}
    local di = 3
    local dRow
    dRow = makeRow("距离上限  1500m", 20, function()
        di = di % #steps + 1
        CFG.MaxDistance = steps[di]
        dRow.Text = "  距离上限  " .. steps[di] .. "m"
    end)

    -- 拖动 / 轻点
    local dragging, dragStart, startPos, moved = false, nil, nil, 0
    btn.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch
            or input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            moved = 0
            dragStart = input.Position
            startPos = btn.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)

    UIS.InputChanged:Connect(function(input)
        if not dragging or not dragStart then return end
        if input.UserInputType == Enum.UserInputType.Touch
            or input.UserInputType == Enum.UserInputType.MouseMovement then
            local d = input.Position - dragStart
            moved = math.max(moved, math.abs(d.X) + math.abs(d.Y))
            btn.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + d.X,
                startPos.Y.Scale, startPos.Y.Offset + d.Y
            )
        end
    end)

    btn.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch
            or input.UserInputType == Enum.UserInputType.MouseButton1 then
            if moved < 12 then panel.Visible = not panel.Visible end
            dragging = false
            dragStart = nil
        end
    end)

    -- 手指在按钮外抬起时也结束拖动，避免"粘手"
    UIS.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch
            or input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
            dragStart = nil
        end
    end)

    UI.gui = gui
    UI.btn = btn
    UI.panel = panel
end

pcall(buildUI)

--============================ 卸载 ================================
local function unload()
    if conn then pcall(function() conn:Disconnect() end) end
    for plr, o in pairs(OBJ) do
        pcall(dropObj, o)
        OBJ[plr] = nil
    end
    if Canvas then pcall(function() Canvas:Destroy() end) end
    if UI.gui then pcall(function() UI.gui:Destroy() end) end
    if getgenv then getgenv().ESP_Unload = nil end
end

if getgenv then getgenv().ESP_Unload = unload end

print("[ESP] 加载完成 | Drawing: " .. tostring(HAS_DRAWING)
    .. " | 悬浮球点一下开面板 | 卸载: getgenv().ESP_Unload()")
