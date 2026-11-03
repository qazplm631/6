--[[ 汽车加速 v11 · 探测法判断「你有没有踩油门」
     之前几版都卡在拿不到油门输入上（Throttle 恒 0、GUI 也认不出来）
     这版不读输入，改「听发动机」：
       推 0.45 秒 → 松 0.20 秒（探测）
       在松的那段时间里，如果车还在自己加速 → 说明你在踩油门
       如果车在减速/滑行 → 说明你松了
     探测期间我们的推力是 0，所以测到的加速度一定是游戏引擎给的
--]]

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS        = game:GetService("UserInputService")
local LP = Players.LocalPlayer

local CFG = {
    ACCEL        = 80,
    ACCEL_MAX    = 120,
    ACCEL_MIN    = 20,
    MAX_SPEED    = 200,

    MIN_SPEED    = 3,
    LATERAL_GRIP = 0.4,

    -- 探测节奏
    PROBE_PUSH   = 0.45,   -- 推多久
    PROBE_COAST  = 0.20,   -- 松多久测一次
    PROBE_ACCEL  = 3,      -- 探测期加速度超过这个就算踩油门

    -- 刹车
    BRAKE_GUARD  = true,
    DECEL_LIMIT  = 12,
    DECEL_SMOOTH = 0.35,
    SUSPEND_TIME = 0.35,

    HARSH_SPEED  = 90,
    RAMP_RATE    = 60,
    VEL_FORCE_K  = 400,

    BOOST_GAME_PARAMS = true,
    MODEL_MAXSPEED    = 260,

    GATE_INPUT   = true,   -- 关掉=常推（点「恒」切换）
    MODE         = "force",

    BTN_SIZE     = 68,
    POS          = { X = -86, Y = -230 },
    SAVE_FILE    = "gen4_ui_pos.txt",
}

local out = function(s) print("[车] " .. s) end
local enabled = false

local positions = _G.__gen4UIPos or {}
_G.__gen4UIPos = positions

local function loadPos()
    pcall(function()
        if type(isfile) == "function" and type(readfile) == "function"
        and isfile(CFG.SAVE_FILE) then
            for line in string.gmatch(readfile(CFG.SAVE_FILE), "[^\n]+") do
                local n, x, y = string.match(line, "([^|]+)|(%-?%d+)|(%-?%d+)")
                if n then positions[n] = { X = tonumber(x), Y = tonumber(y) } end
            end
        end
    end)
end
local function savePos()
    local lines = {}
    for k, v in pairs(positions) do lines[#lines + 1] = string.format("%s|%d|%d", k, v.X, v.Y) end
    pcall(function()
        if type(writefile) == "function" then writefile(CFG.SAVE_FILE, table.concat(lines, "\n")) end
    end)
end
loadPos()

local function currentSeat()
    local hum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
    return hum and hum.SeatPart
end

local function chassisPart(seat)
    local model = seat:FindFirstAncestorOfClass("Model")
    if model and model.PrimaryPart then return model.PrimaryPart end
    return seat
end

local lastParamScan = 0
local function boostGameParams(model)
    if not CFG.BOOST_GAME_PARAMS or os.clock() - lastParamScan < 1.5 then return end
    lastParamScan = os.clock()
    pcall(function()
        for _, d in ipairs(model:GetDescendants()) do
            if d:IsA("NumberValue") or d:IsA("IntValue") then
                local n = string.lower(d.Name)
                if n:find("maxspeed") or n:find("speedlimit") or n:find("topspeed") then
                    if type(d.Value) == "number" and d.Value < CFG.MODEL_MAXSPEED then
                        d.Value = CFG.MODEL_MAXSPEED
                    end
                end
            end
        end
    end)
end

local rig
local function clearRig()
    if rig then
        pcall(function() rig.force:Destroy() end)
        pcall(function() rig.att:Destroy() end)
        pcall(function() rig.bv:Destroy() end)
    end
    rig = nil
end

local function ensureRig(part)
    if rig and rig.part == part and rig.force.Parent == part then return rig end
    clearRig()
    local att = Instance.new("Attachment"); att.Parent = part
    local vf = Instance.new("VectorForce")
    vf.Attachment0 = att
    vf.RelativeTo = Enum.ActuatorRelativeTo.World
    vf.ApplyAtCenterOfMass = true
    vf.Force = Vector3.zero
    vf.Parent = part
    local bv = Instance.new("BodyVelocity")
    bv.MaxForce = Vector3.new(0, 0, 0)
    bv.Velocity = Vector3.zero
    bv.Parent = part
    rig = { part = part, force = vf, att = att, bv = bv }
    return rig
end

-- ===== HUD =====
local pg = LP:WaitForChild("PlayerGui")
local gui = Instance.new("ScreenGui")
gui.Name = "__CAR_HUD"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 995
gui.Parent = pg

local panel = Instance.new("Frame")
panel.Size = UDim2.new(0, 216, 0, 118)
panel.Position = UDim2.new(0, 14, 1, -300)   -- 往上挪一点：负数越大越靠上
panel.BackgroundColor3 = Color3.fromRGB(20, 20, 26)
panel.BackgroundTransparency = 0.35
panel.BorderSizePixel = 0
panel.Parent = gui
local pc = Instance.new("UICorner"); pc.CornerRadius = UDim.new(0, 10); pc.Parent = panel

local info = Instance.new("TextLabel")
info.Size = UDim2.new(1, -12, 0, 72)
info.Position = UDim2.new(0, 6, 0, 4)
info.BackgroundTransparency = 1
info.Font = Enum.Font.Code
info.TextSize = 13
info.TextXAlignment = Enum.TextXAlignment.Left
info.TextColor3 = Color3.fromRGB(230, 230, 240)
info.Text = "车速 --"
info.Parent = panel

local function mkSmall(text, x, onClick)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(0, 38, 0, 32)
    b.Position = UDim2.new(0, x, 1, -38)
    b.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
    b.TextColor3 = Color3.new(1, 1, 1)
    b.Text = text
    b.TextSize = 15
    b.Font = Enum.Font.GothamBold
    b.BorderSizePixel = 0
    b.Parent = panel
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 8); c.Parent = b
    b.MouseButton1Click:Connect(onClick)
    return b
end

mkSmall("+", 4, function()
    CFG.ACCEL = math.min(CFG.ACCEL_MAX, math.floor(CFG.ACCEL * 1.2)); out("系数 " .. CFG.ACCEL)
end)
mkSmall("-", 44, function()
    CFG.ACCEL = math.max(CFG.ACCEL_MIN, math.floor(CFG.ACCEL / 1.2)); out("系数 " .. CFG.ACCEL)
end)
local modeBtn = mkSmall("推", 84, function()
    CFG.MODE = (CFG.MODE == "force") and "velocity" or "force"; out("模式 " .. CFG.MODE)
end)
mkSmall("限", 124, function()
    if CFG.MAX_SPEED < 400 then CFG.MAX_SPEED = 400
    elseif CFG.MAX_SPEED < 800 then CFG.MAX_SPEED = 800
    else CFG.MAX_SPEED = 200 end
    out("上限 " .. CFG.MAX_SPEED)
end)
local gateBtn = mkSmall("恒", 164, function()
    CFG.GATE_INPUT = not CFG.GATE_INPUT
    gateBtn.BackgroundColor3 = CFG.GATE_INPUT and Color3.fromRGB(45, 45, 55)
                                             or Color3.fromRGB(30, 140, 220)
    out(CFG.GATE_INPUT and "探测模式: 按住油门才加速" or "常推模式")
end)

local btn = Instance.new("TextButton")
btn.Size = UDim2.new(0, CFG.BTN_SIZE, 0, CFG.BTN_SIZE)
btn.AnchorPoint = Vector2.new(0.5, 0.5)
btn.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
btn.BackgroundTransparency = 0.3
btn.TextColor3 = Color3.new(1, 1, 1)
btn.Text = "速"
btn.TextScaled = true
btn.Font = Enum.Font.GothamBold
btn.BorderSizePixel = 0
btn.AutoButtonColor = false
btn.Parent = gui
local bc = Instance.new("UICorner"); bc.CornerRadius = UDim.new(1, 0); bc.Parent = btn
local bs = Instance.new("UIStroke"); bs.Color = Color3.fromRGB(120, 200, 255); bs.Thickness = 2; bs.Parent = btn

if positions.car then
    btn.Position = UDim2.new(1, positions.car.X, 1, positions.car.Y)
else
    positions.car = { X = CFG.POS.X, Y = CFG.POS.Y }
    btn.Position = UDim2.new(1, CFG.POS.X, 1, CFG.POS.Y)
end

local dragging, moved, startPos, startInput = false, false, nil, nil
btn.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Touch
    or input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging, moved = true, false
        startPos, startInput = btn.Position, input.Position
        bs.Color = Color3.fromRGB(120, 255, 120)
    end
end)
btn.InputChanged:Connect(function(input)
    if not dragging then return end
    if input.UserInputType == Enum.UserInputType.Touch
    or input.UserInputType == Enum.UserInputType.MouseMovement then
        local d = input.Position - startInput
        if math.abs(d.X) > 6 or math.abs(d.Y) > 6 then moved = true end
        if moved then
            btn.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X,
                                     startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end
end)
btn.InputEnded:Connect(function()
    if not dragging then return end
    dragging = false
    bs.Color = Color3.fromRGB(120, 200, 255)
    if moved then
        local vp = workspace.CurrentCamera.ViewportSize
        local ap, sz = btn.AbsolutePosition, btn.AbsoluteSize
        positions.car = { X = math.floor(ap.X + sz.X / 2 - vp.X),
                          Y = math.floor(ap.Y + sz.Y / 2 - vp.Y) }
        btn.Position = UDim2.new(1, positions.car.X, 1, positions.car.Y)
        savePos()
    else
        enabled = not enabled
        btn.BackgroundColor3 = enabled and Color3.fromRGB(30, 140, 220)
                                       or Color3.fromRGB(50, 50, 60)
        if not enabled then clearRig() end
        out(enabled and "加速 开" or "加速 关")
    end
end)

-- ===== 主循环 =====
local prevSpeed, decelSmooth = 0, 0
local suspendedUntil, vTarget, lastForce, reason = 0, 0, 0, "-"
local phase, phaseT, coastSpeed, pedal, pedalAccel = "coast", 0, 0, false, 0

RunService.Heartbeat:Connect(function(dt)
    local seat = currentSeat()
    if not enabled or not seat then
        if rig then clearRig() end
        prevSpeed, decelSmooth, vTarget = 0, 0, 0
        phase, phaseT, pedal = "coast", 0, false
        reason = "未上车"
        return
    end

    pcall(function()
        if seat:IsA("VehicleSeat") then
            seat.MaxSpeed = 250
            seat.Torque = 100000
        end
    end)

    local part = chassisPart(seat)
    local model = seat:FindFirstAncestorOfClass("Model") or part
    boostGameParams(model)

    local r = ensureRig(part)
    local mass = (part.AssemblyMass and part.AssemblyMass > 0) and part.AssemblyMass or 1
    local vel = part.AssemblyLinearVelocity
    local speed = vel.Magnitude

    -- 刹车识别
    local instDecel = (prevSpeed - speed) / math.max(dt, 0.001)
    local k = math.clamp(dt / math.max(CFG.DECEL_SMOOTH, 0.01), 0, 1)
    decelSmooth = decelSmooth + (instDecel - decelSmooth) * k
    prevSpeed = speed
    if CFG.BRAKE_GUARD and decelSmooth > CFG.DECEL_LIMIT then
        suspendedUntil = os.clock() + CFG.SUSPEND_TIME
        pedal = false
    end
    local braking = os.clock() < suspendedUntil

    -- 探测状态机：推 → 松（测加速度）→ 推
    phaseT = phaseT + dt
    if phase == "push" then
        if phaseT >= CFG.PROBE_PUSH then
            phase, phaseT, coastSpeed = "coast", 0, speed
        end
    else
        if phaseT >= CFG.PROBE_COAST then
            pedalAccel = (speed - coastSpeed) / math.max(phaseT, 0.01)
            pedal = pedalAccel > CFG.PROBE_ACCEL
            phase, phaseT = "push", 0
        end
    end

    local dir = (speed > 0.5) and vel.Unit or Vector3.zero
    local wantPush = CFG.GATE_INPUT and pedal or not CFG.GATE_INPUT
    if braking or speed < CFG.MIN_SPEED or speed >= CFG.MAX_SPEED then
        wantPush = false
    end
    -- 探测相位期间不给力（否则测到的加速度是我们自己造成的）
    if CFG.GATE_INPUT and phase == "coast" then wantPush = false end

    reason = "-"
    if braking then reason = "刹"
    elseif speed < CFG.MIN_SPEED then reason = "静"
    elseif speed >= CFG.MAX_SPEED then reason = "顶"
    elseif CFG.GATE_INPUT and phase == "coast" then reason = "测"
    elseif CFG.GATE_INPUT and not pedal then reason = "松"
    end

    if CFG.MODE == "force" then
        r.bv.MaxForce = Vector3.new(0, 0, 0)
        if wantPush and dir.Magnitude > 0.1 then
            local f = dir * (mass * CFG.ACCEL)
            if CFG.LATERAL_GRIP > 0 then
                local lateral = vel - dir * vel:Dot(dir)
                if lateral.Magnitude > 0.8 then
                    f = f - lateral * (mass * CFG.LATERAL_GRIP)
                end
            end
            r.force.Force = f
            lastForce = mass * CFG.ACCEL
        else
            r.force.Force = Vector3.zero
            lastForce = 0
        end
    else
        r.force.Force = Vector3.zero
        lastForce = 0
        if wantPush and dir.Magnitude > 0.1 then
            vTarget = math.min(CFG.HARSH_SPEED, math.max(vTarget, speed) + CFG.RAMP_RATE * dt)
            if speed < vTarget then
                r.bv.MaxForce = Vector3.new(mass * CFG.VEL_FORCE_K, 0, mass * CFG.VEL_FORCE_K)
                r.bv.Velocity = dir * vTarget
            end
        else
            r.bv.MaxForce = Vector3.new(0, 0, 0)
            vTarget = speed
        end
    end

    info.Text = string.format("车速 %3d %s %s\n油 %s 测 %d\n系数 %d 上限 %d",
        math.floor(speed), CFG.MODE, reason,
        pedal and "踩" or "松", math.floor(pedalAccel), CFG.ACCEL, CFG.MAX_SPEED)
    modeBtn.Text = CFG.MODE == "force" and "推" or "速"
end)

out("已加载：自动探测你是否在踩油门（推 0.45s / 测 0.2s 循环）")
