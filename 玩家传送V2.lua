--[[ 传送总控
     一个面板，两个独立开关：
       人物传送：点玩家名 → 你瞬移到对方头顶
       车辆飞悬：点玩家名 → 车飞过去，到对方上方悬停
     两个都开时：坐在车里走「车飞」，没坐车自动走「人物传送」
--]]

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local LP = Players.LocalPlayer

local CFG = {
    -- 人物传送
    TP_OFFSET   = Vector3.new(0, 5, 0),
    TP_COOLDOWN = 0.8,

    -- 车辆飞行
    ACCEL       = 160,
    MAX_SPEED   = 90,
    HOVER_K     = 4.0,     -- 高度控制比例（越大爬升越快）
    HOVER_D     = 10.0,    -- 高度控制阻尼
    ALT_OFFSET  = 10,
    STOP_DIST   = 18,
    VERT_TOL    = 6,        -- 悬停/到达的垂直容差
    HOLD_K      = 6,
    FOLLOW      = false,
    NO_CLIP     = false,    -- 贴地模式不需要关闭碰撞
    RESTORE_CLIP = true,
    VOID_GUARD  = true,
    MIN_Y       = -40,
    MAX_RISE    = 45,     -- 向上速度上限（爬升别太猛）
    DESCEND_MAX = 18,     -- 下降速度上限（越小越不会穿透地面）
    GROUND_CLEAR = 8,     -- 保持在地面上方多少
    GROUND_SCAN = 600,    -- 向下探地的最大距离
    MICRO_LIFT  = true,   -- 低于地面时小幅抬升（不触发位置校验）
    LIFT_STEP   = 2,      -- 每次最多抬多少 studs
    LIFT_HZ     = 0.05,   -- 抬升间隔
    DIAG        = true,   -- 每 0.7 秒打印一次高度/速度/力
    MAX_FALL    = 90,
    MAX_DIST    = 4000,
    MAX_FLIGHT_DIST = 1000,   -- 飞行距离上限，超过就停止（太远容易被清理）
    VERT_MODE   = "ground",  -- ground 贴地跑 / servo 坐标伺服 / force 推力悬浮
    STUCK_SPEED = 1.5,       -- 低于这个速度判定被卡住
    HOP_FORCE   = 320,       -- 卡住时向上的起跳力
    CLIMB_FORCE = 800,       -- 前方有障碍时的爬升力
    CLIMB_SPEED = 55,        -- 爬升速度上限
    CLIMB_MAX   = 140,       -- 相对目标最多升多高
    OBSTACLE_RAY = 22,       -- 前方探测距离
    VERT_SERVO  = true,      -- 兼容旧字段
    SERVO_RATE  = 0.35,      -- 伺服跟随比例
    SERVO_MAX   = 0.9,       -- 每帧最多调整多少 studs

    -- 界面
    BTN_SIZE    = 64,
    BTN_POS     = { X = -80, Y = -180 },
    MAX_LIST    = 10,
    REFRESH     = 1.0,
}

local out = function(s) print("[传送] " .. s) end

local modeTP, modeCar = true, true
local flying, holding = false, false
local targetPlr = nil
local rig = nil
local clipSaved = {}
local lastTP = 0
local lastNoClip = 0
local lastLift = 0
local lastDiag = 0

-- ===== 基础 =====
local function char() return LP.Character end
local function hrp()
    local c = char()
    return c and c:FindFirstChild("HumanoidRootPart")
end
local function seatPart()
    local c = char()
    local hum = c and c:FindFirstChildOfClass("Humanoid")
    return hum and hum.SeatPart
end
local function chassis(seat)
    local model = seat:FindFirstAncestorOfClass("Model")
    if model and model.PrimaryPart then return model.PrimaryPart end
    return seat
end
local function targetPos(plr)
    local c = plr and plr.Character
    if not c then return nil end
    local p = c:FindFirstChild("HumanoidRootPart") or c:FindFirstChild("Head")
    return p and p.Position
end
local function targetPart(plr)
    local c = plr and plr.Character
    if not c then return nil end
    return c:FindFirstChild("Head") or c:FindFirstChild("HumanoidRootPart")
end

-- ===== 人物传送 =====
local function teleportToPlayer(plr)
    if os.clock() - lastTP < CFG.TP_COOLDOWN then return end
    lastTP = os.clock()

    local r = hrp()
    local p = targetPart(plr)
    if not r then out("无角色") return end
    if not p then out(plr.Name .. " 没有角色") return end

    local dest = CFrame.new(p.Position + CFG.TP_OFFSET)
    local ok = pcall(function()
        r.CFrame = dest
        r.AssemblyLinearVelocity = Vector3.zero
    end)
    if ok then
        out(string.format("人物 → %s 头顶", plr.Name))
    else
        out("人物传送失败")
    end
end

-- ===== 无碰撞 =====
local function collectParts()
    local list = {}
    local seat = seatPart()
    if seat then
        local model = seat:FindFirstAncestorOfClass("Model")
        if model then
            for _, d in ipairs(model:GetDescendants()) do
                if d:IsA("BasePart") then list[#list + 1] = d end
            end
        end
    end
    local c = char()
    if c then
        for _, d in ipairs(c:GetDescendants()) do
            if d:IsA("BasePart") then list[#list + 1] = d end
        end
    end
    return list
end

local function setNoClip(on)
    if on then
        clipSaved = {}
        for _, part in ipairs(collectParts()) do
            local ok, cur = pcall(function() return part.CanCollide end)
            if ok then
                clipSaved[part] = cur
                pcall(function() part.CanCollide = false end)
            end
        end
    else
        for part, v in pairs(clipSaved) do
            if part and part.Parent then
                pcall(function() part.CanCollide = v end)
            end
        end
        clipSaved = {}
    end
end

-- 探测地面高度（用于避免穿进地下）
local function groundY(pos)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    local list = {}
    local c = char()
    if c then list[#list + 1] = c end
    local seat = seatPart()
    if seat then
        local m = seat:FindFirstAncestorOfClass("Model")
        if m then list[#list + 1] = m end
    end
    params.FilterDescendantsInstances = list
    local ok, hit = pcall(function()
        return workspace:Raycast(pos, Vector3.new(0, -CFG.GROUND_SCAN, 0), params)
    end)
    if ok and hit then return hit.Position.Y end
    return nil
end

-- 前方障碍探测
local function obstacleAhead(part, dir)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    local list = {}
    local c = char()
    if c then list[#list + 1] = c end
    local seat = seatPart()
    if seat then
        local m = seat:FindFirstAncestorOfClass("Model")
        if m then list[#list + 1] = m end
    end
    params.FilterDescendantsInstances = list
    local origin = part.Position + Vector3.new(0, 1.5, 0)
    local ok, hit = pcall(function()
        return workspace:Raycast(origin, dir * CFG.OBSTACLE_RAY, params)
    end)
    if ok and hit then return hit end
    return nil
end

-- ===== 车飞 =====
local function clearRig()
    if rig then
        pcall(function() rig.force:Destroy() end)
        pcall(function() rig.att:Destroy() end)
    end
    rig = nil
end

local function ensureRig(part)
    if rig and rig.part == part and rig.force.Parent == part then return rig end
    clearRig()
    local att = Instance.new("Attachment")
    att.Parent = part
    local vf = Instance.new("VectorForce")
    vf.Attachment0 = att
    vf.RelativeTo = Enum.ActuatorRelativeTo.World
    vf.ApplyAtCenterOfMass = true
    vf.Force = Vector3.zero
    vf.Parent = part
    rig = { part = part, force = vf, att = att }
    return rig
end

local function stopFlight()
    flying = false
    holding = false
    clearRig()
    if CFG.NO_CLIP and CFG.RESTORE_CLIP then setNoClip(false) end
end

local function startFlight(plr)
    if not seatPart() then
        out("没坐在车里，改为人物传送")
        teleportToPlayer(plr)
        return
    end
    targetPlr = plr
    flying = true
    holding = false
    if CFG.NO_CLIP then setNoClip(true) end
    out("车飞 → " .. plr.Name)
end

RunService.Heartbeat:Connect(function(dt)
    if not flying then return end

    if CFG.NO_CLIP and os.clock() - lastNoClip > 0.25 then
        lastNoClip = os.clock()
        for p in pairs(clipSaved) do
            if p and p.Parent then
                pcall(function()
                    if p.CanCollide then p.CanCollide = false end
                end)
            end
        end
    end

    local seat = seatPart()
    if not seat then
        out("已下车，停止飞行")
        stopFlight()
        return
    end

    local part = chassis(seat)
    local r = ensureRig(part)
    local mass = (part.AssemblyMass and part.AssemblyMass > 0) and part.AssemblyMass or 1
    local vel = part.AssemblyLinearVelocity
    local tp = targetPlr and targetPos(targetPlr)

    if not tp then
        out("目标丢失")
        stopFlight()
        return
    end

    local delta = tp - part.Position
    local dist = delta.Magnitude
    local horiz = Vector3.new(delta.X, 0, delta.Z).Magnitude

    if dist > CFG.MAX_FLIGHT_DIST then
        out(string.format("目标太远（%.0f > %d），停止", dist, CFG.MAX_FLIGHT_DIST))
        stopFlight()
        return
    end

    local gy = groundY(part.Position + Vector3.new(0, 4, 0))
    local floorLimit = gy and (gy + CFG.GROUND_CLEAR) or nil
    local targetY = tp.Y + CFG.ALT_OFFSET
    if floorLimit and targetY < floorLimit then targetY = floorLimit end

    -- ============ 贴地模式：物理落地 + 遇障碍爬升 ============
    if CFG.VERT_MODE == "ground" then
        local hDir = Vector3.new(delta.X, 0, delta.Z)

        if horiz <= CFG.STOP_DIST then
            if not holding then
                holding = true
                out("已到达目标附近，停止推进")
            end
            r.force.Force = Vector3.zero
            return
        end

        holding = false

        local f = Vector3.zero
        if hDir.Magnitude > 0.5 then
            f = hDir.Unit * (mass * CFG.ACCEL)
        end

        -- 前方障碍探测
        local blocked = false
        local hit = nil
        if hDir.Magnitude > 0.5 then
            hit = obstacleAhead(part, hDir.Unit)
            blocked = hit ~= nil
        end

        local stuck = vel.Magnitude < CFG.STUCK_SPEED
        local nearCeil = (part.Position.Y > tp.Y + CFG.CLIMB_MAX)

        if (blocked or stuck) and not nearCeil then
            -- 往上爬：先保证竖直速度不超过上限
            if vel.Y < CFG.CLIMB_SPEED then
                f = f + Vector3.new(0, mass * CFG.CLIMB_FORCE, 0)
            end
            -- 卡死的情况下补一点起跳
            if stuck then
                f = f + Vector3.new(0, mass * CFG.HOP_FORCE, 0)
            end
        end

        r.force.Force = f

        if CFG.DIAG and os.clock() - lastDiag > 0.7 then
            lastDiag = os.clock()
            out(string.format("贴地 Y=%.0f 地面=%s 距=%.0f 速度=%.0f 障碍=%s%s",
                part.Position.Y, gy and string.format("%.0f", gy) or "无",
                horiz, vel.Magnitude,
                hit and (hit.Instance.Name:sub(1, 10)) or "无",
                nearCeil and " 顶高" or ""))
        end
        return
    end

    -- ============ 悬浮模式（servo / force） ============
    local arrived = (horiz <= CFG.STOP_DIST)
        and (math.abs(part.Position.Y - targetY) <= CFG.VERT_TOL)

    if CFG.VERT_MODE == "servo" then
        local dy = targetY - part.Position.Y
        if math.abs(dy) > 0.15 then
            local stepY = math.clamp(dy * CFG.SERVO_RATE, -CFG.SERVO_MAX, CFG.SERVO_MAX)
            pcall(function()
                part.CFrame = part.CFrame + Vector3.new(0, stepY, 0)
                local v2 = part.AssemblyLinearVelocity
                part.AssemblyLinearVelocity = Vector3.new(v2.X, 0, v2.Z)
            end)
        end
        vel = part.AssemblyLinearVelocity
    end

    if CFG.VOID_GUARD and part.Position.Y < CFG.MIN_Y then
        out("掉入虚空，停止飞行")
        stopFlight()
        return
    end

    if CFG.DIAG and os.clock() - lastDiag > 0.7 then
        lastDiag = os.clock()
        out(string.format("悬浮 Y=%.0f 目标Y=%.0f vy=%.1f 距=%.0f 到=%s",
            part.Position.Y, targetY, vel.Y, dist, tostring(arrived)))
    end

    if arrived then
        if not holding then
            holding = true
            out("已到上方，悬停中")
        end
        local hv = Vector3.new(vel.X, 0, vel.Z)
        r.force.Force = -hv * (mass * CFG.HOLD_K)
        return
    end

    holding = false

    if CFG.VERT_MODE == "servo" then
        local hDir = Vector3.new(delta.X, 0, delta.Z)
        r.force.Force = (hDir.Magnitude > 0.5)
            and hDir.Unit * (mass * CFG.ACCEL) or Vector3.zero
    else
        local f = delta.Unit * (mass * CFG.ACCEL)
        local desiredVy = math.clamp((targetY - part.Position.Y) * CFG.HOVER_K,
            -CFG.DESCEND_MAX, CFG.MAX_RISE)
        local ay = (desiredVy - vel.Y) * CFG.HOVER_D
        f = f + Vector3.new(0, mass * (ay + workspace.Gravity), 0)
        r.force.Force = f
    end
end)

-- ===== UI =====
local pg = LP:WaitForChild("PlayerGui")
local gui = Instance.new("ScreenGui")
gui.Name = "__TP_HUB"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 2000
gui.Parent = pg

local openBtn = Instance.new("TextButton")
openBtn.Size = UDim2.new(0, CFG.BTN_SIZE, 0, CFG.BTN_SIZE)
openBtn.AnchorPoint = Vector2.new(0.5, 0.5)
openBtn.Position = UDim2.new(1, CFG.BTN_POS.X, 1, CFG.BTN_POS.Y)
openBtn.BackgroundColor3 = Color3.fromRGB(60, 90, 150)
openBtn.BackgroundTransparency = 0.2
openBtn.Text = "传"
openBtn.TextSize = 24
openBtn.TextColor3 = Color3.new(1, 1, 1)
openBtn.Font = Enum.Font.GothamBold
openBtn.BorderSizePixel = 0
openBtn.AutoButtonColor = false
openBtn.Parent = gui

local obc = Instance.new("UICorner"); obc.CornerRadius = UDim.new(1, 0); obc.Parent = openBtn
local obs = Instance.new("UIStroke")
obs.Color = Color3.fromRGB(150, 220, 255); obs.Thickness = 2; obs.Parent = openBtn

local panel = Instance.new("Frame")
panel.Size = UDim2.new(0, 216, 0, 400)
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
title.Size = UDim2.new(1, -50, 1, 0)
title.Position = UDim2.new(0, 12, 0, 0)
title.BackgroundTransparency = 1
title.Text = "传送总控"
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
local cbc = Instance.new("UICorner"); cbc.CornerRadius = UDim.new(0, 8); cbc.Parent = closeBtn

-- 两个独立开关
local function makeSwitch(text, y, initial, onColor, onChange)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(0, 96, 0, 32)
    b.Position = UDim2.new(0, 10, 0, y)
    b.BackgroundColor3 = initial and onColor or Color3.fromRGB(50, 50, 62)
    b.Text = text .. (initial and ": 开" or ": 关")
    b.TextSize = 13
    b.TextColor3 = Color3.new(1, 1, 1)
    b.Font = Enum.Font.GothamBold
    b.BorderSizePixel = 0
    b.Parent = panel
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 9); c.Parent = b

    local state = initial
    b.MouseButton1Click:Connect(function()
        state = not state
        b.BackgroundColor3 = state and onColor or Color3.fromRGB(50, 50, 62)
        b.Text = text .. (state and ": 开" or ": 关")
        onChange(state)
    end)
    return b
end

makeSwitch("人物传送", 46, true, Color3.fromRGB(40, 140, 100), function(v)
    modeTP = v
    out("人物传送 " .. (v and "开" or "关"))
end)

makeSwitch("车辆飞悬", 46, true, Color3.fromRGB(40, 110, 190), function(v)
    modeCar = v
    out("车辆飞悬 " .. (v and "开" or "关"))
end)

-- 第二个开关位置右移
for _, ch in ipairs(panel:GetChildren()) do
    if ch:IsA("TextButton") and ch.Text and ch.Text:find("车辆飞悬") then
        ch.Position = UDim2.new(0, 112, 0, 46)
    end
end

local stopBtn = Instance.new("TextButton")
stopBtn.Size = UDim2.new(1, -20, 0, 30)
stopBtn.Position = UDim2.new(0, 10, 0, 84)
stopBtn.BackgroundColor3 = Color3.fromRGB(150, 60, 60)
stopBtn.Text = "停止车辆飞行"
stopBtn.TextSize = 13
stopBtn.TextColor3 = Color3.new(1, 1, 1)
stopBtn.Font = Enum.Font.GothamBold
stopBtn.BorderSizePixel = 0
stopBtn.Parent = panel
local sbc = Instance.new("UICorner"); sbc.CornerRadius = UDim.new(0, 9); sbc.Parent = stopBtn

stopBtn.MouseButton1Click:Connect(function()
    stopFlight()
    out("已停止车辆飞行")
end)

local list = Instance.new("ScrollingFrame")
list.Size = UDim2.new(1, -20, 1, -130)
list.Position = UDim2.new(0, 10, 0, 122)
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

local function refresh()
    for _, ch in ipairs(list:GetChildren()) do
        if ch:IsA("TextButton") then ch:Destroy() end
    end

    local me = hrp()
    local entries = {}
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LP then
            local tp = targetPos(plr)
            local d = (tp and me) and (tp - me.Position).Magnitude or 9999
            entries[#entries + 1] = { plr = plr, dist = d }
        end
    end
    table.sort(entries, function(a, b) return a.dist < b.dist end)

    local n = 0
    for _, e in ipairs(entries) do
        n = n + 1
        if n > CFG.MAX_LIST then break end
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(1, -8, 0, 40)
        b.LayoutOrder = n
        b.BackgroundColor3 = Color3.fromRGB(34, 40, 56)
        b.BackgroundTransparency = 0.1
        b.Text = string.format("%s  %dm", e.plr.Name, math.floor(e.dist))
        b.TextSize = 15
        b.TextColor3 = Color3.fromRGB(235, 240, 255)
        b.Font = Enum.Font.GothamBold
        b.BorderSizePixel = 0
        b.AutoButtonColor = false
        b.Parent = list
        local bc = Instance.new("UICorner"); bc.CornerRadius = UDim.new(0, 10); bc.Parent = b

        b.MouseButton1Click:Connect(function()
            if modeCar and seatPart() then
                startFlight(e.plr)
            elseif modeTP then
                teleportToPlayer(e.plr)
            elseif modeCar then
                startFlight(e.plr)   -- 没坐车会回退成人物传送
            else
                out("两个开关都关着")
            end
        end)
    end

    if n == 0 then
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(1, -8, 0, 40)
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
        if panel.Visible then pcall(refresh) end
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

-- 开合
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

pcall(function()
    workspace.FallenPartsDestroyHeight = -5000
end)

out("已加载：人物传送 + 车辆飞悬，两个开关独立")
