--[[============================================================
  GEN4 HUB v2 · 六合一整合面板（单文件 · 手机触屏适配）
  ------------------------------------------------------------
  整合来源与去向：
    f.lua            透视通缉 + 速度锁 + 开启弹窗   → 「透视」「设置」
    ffffff.lua       自动铐人（ProximityPrompt）    → 「战斗」
    无后座.lua       枪械无后坐力清零              → 「战斗」
    787878.lua       汽车加速（推力/速度双模式）    → 「车辆」
    传送.lua         9 个预设地点                  → 「传送」
    玩家传送V2.lua   人物传送 + 车辆飞悬           → 「传送」
  ------------------------------------------------------------
  形态：右下角一个悬浮球 → 点开一个可拖动面板 → 5 个分页
  保存：gen4_hub.cfg（悬浮球位置、面板位置、各项参数、自定义地点）
  重载：再次执行本脚本会自动清理上一轮（按钮/面板/线程）
============================================================]]

local Players      = game:GetService("Players")
local RunService   = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UIS          = game:GetService("UserInputService")
local LP           = Players.LocalPlayer
local PG           = LP:WaitForChild("PlayerGui")

-- 上一轮清理
if type(_G.__gen4HubCleanup) == "function" then pcall(_G.__gen4HubCleanup) end
do
    local killNames = {"__GEN4_HUB", "__GEN4_POPUP", "__ARREST_BTN", "__CAR_HUD", "__TP_LOC", "__TP_HUB"}
    for _, obj in ipairs(PG:GetChildren()) do
        local n = tostring(obj.Name)
        local hit = false
        for _, k in ipairs(killNames) do if n == k then hit = true end end
        if n:find("__NORECOIL_UI", 1, true) then hit = true end
        if hit then pcall(function() obj:Destroy() end) end
    end
end

-- ============================================================
-- 配色
-- ============================================================
local C = {
    bg      = Color3.fromRGB(16, 17, 22),
    bg2     = Color3.fromRGB(26, 28, 36),
    card    = Color3.fromRGB(34, 37, 48),
    off     = Color3.fromRGB(44, 46, 58),
    text    = Color3.fromRGB(228, 232, 242),
    sub     = Color3.fromRGB(148, 156, 176),
    accent  = Color3.fromRGB(66, 128, 240),
    green   = Color3.fromRGB(44, 158, 104),
    red     = Color3.fromRGB(198, 64, 64),
    orange  = Color3.fromRGB(212, 140, 54),
    purple  = Color3.fromRGB(150, 96, 220),
}

-- ============================================================
-- 持久化配置
-- ============================================================
local CFG_FILE = "gen4_hub.cfg"

local P = {
    btnX = -86, btnY = -150,
    panelX = 0, panelY = 0,
    speed = 28, espFilter = "all", espRange = 0, espInterval = 0.6, espColor = 1,
    arrestDist = 8, arrestCd = 0.5,
    carAccel = 80, carMax = 200, carMode = "force", carAlways = false,
    presets = "",
}

local function enc(v)
    local t = type(v)
    if t == "number" then return "n|" .. tostring(v) end
    if t == "boolean" then return "b|" .. tostring(v) end
    return "s|" .. tostring(v):gsub("[\r\n]+", " ")
end

local function dec(s)
    local t, v = s:sub(1, 1), s:sub(3)
    if t == "n" then return tonumber(v) end
    if t == "b" then return v == "true" end
    return v
end

local function loadCfg()
    pcall(function()
        if type(isfile) ~= "function" or type(readfile) ~= "function" then return end
        if not isfile(CFG_FILE) then return end
        for line in string.gmatch(readfile(CFG_FILE), "[^\r\n]+") do
            local k, v = string.match(line, "^([^|]+)|(.+)$")
            if k and v then
                local isKey = P[k] ~= nil
                if isKey then P[k] = dec(v) end
            end
        end
    end)
end

local function saveCfg()
    pcall(function()
        if type(writefile) ~= "function" then return end
        local lines = {}
        for k, v in pairs(P) do lines[#lines + 1] = k .. "|" .. enc(v) end
        table.sort(lines)
        writefile(CFG_FILE, table.concat(lines, "\n"))
    end)
end

loadCfg()

-- ============================================================
-- 运行时状态（默认值取自持久化）
-- ============================================================
local S = {
    -- 移动
    speedLock = false, speed = P.speed or 28, blockLower = true,
    -- 透视
    esp = false, espFilter = P.espFilter, espRange = P.espRange,
    espInterval = P.espInterval, espColor = P.espColor,
    -- 战斗
    arrestAuto = false, arrestDist = P.arrestDist, arrestCd = P.arrestCd,
    arrestOnlyWanted = false, noRecoil = false,
    -- 车辆
    carBoost = false, carAccel = P.carAccel, carMax = P.carMax,
    carMode = P.carMode, carAlways = P.carAlways, carParams = true,
    -- 传送
    playerTp = true, carFly = true, voidGuard = true,
}

-- ============================================================
-- 日志
-- ============================================================
local uiRefs = {}
local logs = {}

local function stamp()
    local ok, s = pcall(function() return os.date("%H:%M:%S") end)
    if ok and s then return s end
    return string.format("%.0fs", os.clock())
end

local function out(msg)
    msg = tostring(msg)
    print("[GEN4] " .. msg)
    logs[#logs + 1] = stamp() .. "  " .. msg
    while #logs > 80 do table.remove(logs, 1) end
    if uiRefs.logLabel then
        pcall(function() uiRefs.logLabel.Text = table.concat(logs, "\n") end)
    end
end

-- ============================================================
-- 通用工具
-- ============================================================
local function el(class, props, parent)
    local inst = Instance.new(class)
    for k, v in pairs(props or {}) do inst[k] = v end
    inst.Parent = parent
    return inst
end

local function deco(inst, radius, strokeColor, thickness)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, radius)
    c.Parent = inst
    if strokeColor then
        local s = Instance.new("UIStroke")
        s.Color = strokeColor
        s.Thickness = thickness or 1.5
        s.Transparency = 0.25
        s.Parent = inst
        return s
    end
end

-- 触屏按压反馈：按下时底色变亮，松手淡出（纯视觉，不影响点击逻辑）
local function touchify(inst)
    local base = inst.BackgroundTransparency or 0
    if base >= 1 then return end
    -- 不透明按钮按下变淡，半透明按钮按下变实，保证两种底色都有反馈
    local pressed = (base < 0.5) and math.min(1, base + 0.18) or math.max(0, base - 0.25)
    inst.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch
        or input.UserInputType == Enum.UserInputType.MouseButton1 then
            pcall(function()
                TweenService:Create(inst, TweenInfo.new(0.08), {
                    BackgroundTransparency = pressed,
                }):Play()
            end)
        end
    end)
    inst.InputEnded:Connect(function()
        pcall(function()
            TweenService:Create(inst, TweenInfo.new(0.15), {
                BackgroundTransparency = base,
            }):Play()
        end)
    end)
    inst.InputChanged:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.Touch then return end
        local outside = false
        pcall(function()
            local ap, asz = inst.AbsolutePosition, inst.AbsoluteSize
            local px, py = input.Position.X, input.Position.Y
            outside = px < ap.X or px > ap.X + asz.X or py < ap.Y or py > ap.Y + asz.Y
        end)
        if outside then
            pcall(function()
                TweenService:Create(inst, TweenInfo.new(0.15), {BackgroundTransparency = base}):Play()
            end)
        end
    end)
end

local function matchAny(name, keys)
    local n = string.lower(tostring(name))
    for _, k in ipairs(keys) do if n:find(k, 1, true) then return true end end
    return false
end

local function hrp()
    local c = LP.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end

local function hum()
    local c = LP.Character
    return c and c:FindFirstChildOfClass("Humanoid")
end

local function seatPart()
    local h = hum()
    return h and h.SeatPart
end

local function chassis(seat)
    local model = seat and seat:FindFirstAncestorOfClass("Model")
    if model and model.PrimaryPart then return model.PrimaryPart end
    return seat
end

local function viewport()
    local cam = workspace.CurrentCamera
    return cam and cam.ViewportSize or Vector2.new(1280, 720)
end

-- ============================================================
-- 一、速度锁（f.lua · 无限体力）
-- ============================================================
local speedConn = nil

local function setSpeedLock(on)
    S.speedLock = on
    if not on then
        if speedConn then pcall(function() speedConn:Disconnect() end) end
        speedConn = nil
        out("速度锁 关")
        return
    end
    if S.blockLower and not _G.__gen4Hook then
        local ok = pcall(function()
            local old
            old = hookmetamethod(game, "__newindex", function(self, key, value)
                if key == "WalkSpeed" and not checkcaller() then
                    if type(value) == "number" and value < (S.speed or 16) then return end
                end
                return old(self, key, value)
            end)
            _G.__gen4Hook = true
        end)
        out(ok and "降速拦截已安装" or "降速拦截安装失败")
    end
    if speedConn then pcall(function() speedConn:Disconnect() end) end
    speedConn = RunService.Heartbeat:Connect(function()
        local h = hum()
        if h and h.WalkSpeed < S.speed then
            pcall(function() h.WalkSpeed = S.speed end)
        end
    end)
    out("速度锁 开 · " .. tostring(S.speed))
end

-- ============================================================
-- 二、透视（f.lua · 通缉标记）
-- ============================================================
local WANT_KEYS = {"wanted", "criminal", "bounty", "suspect", "suspicious",
                   "heat", "stars", "通缉", "悬赏", "罪犯", "嫌疑", "红名"}

local ESP_STYLES = {
    {Color3.fromRGB(255, 60, 60), Color3.fromRGB(255, 210, 210), "红"},
    {Color3.fromRGB(255, 200, 50), Color3.fromRGB(255, 244, 205), "黄"},
    {Color3.fromRGB(70, 230, 120), Color3.fromRGB(205, 255, 222), "绿"},
    {Color3.fromRGB(80, 160, 255), Color3.fromRGB(212, 232, 255), "蓝"},
    {Color3.fromRGB(190, 110, 255), Color3.fromRGB(236, 216, 255), "紫"},
}

local function matchWant(n)
    n = string.lower(tostring(n))
    for _, k in ipairs(WANT_KEYS) do
        if n:find(k, 1, true) then return true end
    end
    return false
end

local function truthy(v)
    if type(v) == "boolean" then return v end
    if type(v) == "number" then return v > 0 end
    if type(v) == "string" then
        local s = string.lower(v)
        return s ~= "" and s ~= "0" and s ~= "false" and s ~= "none"
    end
    return false
end

local function scanContainer(container)
    for _, v in ipairs(container:GetDescendants()) do
        if matchWant(v.Name)
        and (v:IsA("BoolValue") or v:IsA("NumberValue")
            or v:IsA("IntValue") or v:IsA("StringValue"))
        and truthy(v.Value) then
            return true
        end
    end
    return false
end

local function isWanted(plr)
    if not plr or plr == LP then return false end
    for k, v in pairs(plr:GetAttributes()) do
        if matchWant(k) and truthy(v) then return true end
    end
    for _, cname in ipairs({"PlayerData", "leaderstats", "Stats", "Values", "Data"}) do
        local c = plr:FindFirstChild(cname)
        if c and scanContainer(c) then return true end
    end
    local char = plr.Character
    if char then
        for k, v in pairs(char:GetAttributes()) do
            if matchWant(k) and truthy(v) then return true end
        end
        if scanContainer(char) then return true end
        for _, d in ipairs(char:GetDescendants()) do
            if d:IsA("TextLabel") and matchWant(d.Text) then return true end
        end
    end
    return false
end

local tracked = setmetatable({}, {__mode = "k"})
local espThread = nil
local espCount = 0

local function clearESP(plr)
    local d = tracked[plr]
    if not d then return end
    if d.highlight and d.highlight.Parent then d.highlight:Destroy() end
    if d.tag and d.tag.Parent then d.tag:Destroy() end
    tracked[plr] = nil
end

local function applyESP(plr, wanted)
    local char = plr.Character
    local head = char and char:FindFirstChild("Head")
    local h = char and char:FindFirstChildOfClass("Humanoid")
    if not (char and head and h) then return end

    local style = ESP_STYLES[math.clamp(S.espColor, 1, #ESP_STYLES)]
    local data = tracked[plr]
    if not data then
        data = {}
        tracked[plr] = data
    end

    if not data.highlight or data.highlight.Parent ~= char then
        if data.highlight then pcall(function() data.highlight:Destroy() end) end
        local hl = Instance.new("Highlight")
        hl.Name = "__GEN4_HL"
        hl.Adornee = char
        hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        hl.FillColor = style[1]
        hl.FillTransparency = 0.55
        hl.OutlineColor = style[2]
        hl.OutlineTransparency = 0
        hl.Parent = char
        data.highlight = hl
    end
    data.highlight.FillColor = style[1]
    data.highlight.OutlineColor = style[2]

    if not data.tag or data.tag.Parent ~= head then
        if data.tag then pcall(function() data.tag:Destroy() end) end
        local bb = Instance.new("BillboardGui")
        bb.Name = "__GEN4_TAG"
        bb.Size = UDim2.new(0, 220, 0, 44)
        bb.StudsOffset = Vector3.new(0, 2.6, 0)
        bb.AlwaysOnTop = true
        bb.Adornee = head
        bb.Parent = head

        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(1, 0, 1, 0)
        label.BackgroundTransparency = 1
        label.Font = Enum.Font.GothamBold
        label.TextSize = 16
        label.TextColor3 = style[2]
        label.TextStrokeTransparency = 0.4
        label.Text = plr.Name
        label.Parent = bb

        data.tag = bb
        data.label = label
    end
    data.label.TextColor3 = style[2]
    data.wanted = wanted
end

local function espTick()
    local myRoot = hrp()
    local n = 0
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LP then
            local wanted = isWanted(plr)
            local show = (S.espFilter == "all") or wanted
            local root = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
            if show and S.espRange > 0 and myRoot and root then
                if (root.Position - myRoot.Position).Magnitude > S.espRange then show = false end
            end
            if show then
                applyESP(plr, wanted)
                n = n + 1
                local d = tracked[plr]
                if d and d.label and myRoot and root then
                    local dist = math.floor((root.Position - myRoot.Position).Magnitude)
                    d.label.Text = string.format("%s%s  [%dm]", wanted and "通缉 " or "", plr.Name, dist)
                end
            else
                clearESP(plr)
            end
        end
    end
    espCount = n
end

local function startESP()
    if espThread then return end
    espThread = task.spawn(function()
        while S.esp do
            pcall(espTick)
            task.wait(S.espInterval)
        end
        espThread = nil
    end)
    out("透视 开 · " .. (S.espFilter == "all" and "全部" or "仅通缉"))
end

local function stopESP()
    S.esp = false
    espThread = nil
    for plr in pairs(tracked) do clearESP(plr) end
    espCount = 0
    out("透视 关")
end

-- ============================================================
-- 三、自动铐人（ffffff.lua）
-- ============================================================
local CUFF_KEYS = {"arrest", "cuff", "handcuff", "restrain", "铐", "逮捕"}
local arrestAttempts, lastArrest, arrestBusy = 0, 0, false

local function cuffPrompts()
    local list = {}
    pcall(function()
        for _, d in ipairs(workspace:GetDescendants()) do
            if d:IsA("ProximityPrompt") and matchAny(d.Name, CUFF_KEYS) then
                local model = d:FindFirstAncestorOfClass("Model")
                if model and model:FindFirstChildOfClass("Humanoid") and model ~= LP.Character then
                    list[#list + 1] = {prompt = d, model = model}
                end
            end
        end
    end)
    return list
end

local function snapshot(model)
    local t = {}
    for k, v in pairs(model:GetAttributes()) do t[k] = v end
    local h = model:FindFirstChildOfClass("Humanoid")
    if h then t.__ws, t.__hp = h.WalkSpeed, h.Health end
    if model.Parent then t.__parent = model.Parent.Name end
    return t
end

local function tryArrest()
    if arrestBusy then return end
    local myRoot = hrp()
    if not myRoot then out("无角色") return end
    if os.clock() - lastArrest < S.arrestCd then return end

    local best, bd = nil, math.huge
    for _, item in ipairs(cuffPrompts()) do
        local root = item.model:FindFirstChild("HumanoidRootPart")
        if root then
            local d = (root.Position - myRoot.Position).Magnitude
            if d <= S.arrestDist and d < bd then
                local plr = Players:GetPlayerFromCharacter(item.model)
                if (not S.arrestOnlyWanted) or isWanted(plr) then
                    best, bd = item, d
                end
            end
        end
    end
    if not best then
        out("附近没有可铐目标（" .. S.arrestDist .. " 内）")
        return
    end

    arrestBusy, lastArrest = true, os.clock()
    arrestAttempts = arrestAttempts + 1

    local p = best.prompt
    local hold = 0
    pcall(function()
        if type(p.HoldDuration) == "number" then hold = p.HoldDuration end
    end)
    local before = snapshot(best.model)
    local okB = pcall(function() p:InputHoldBegin() end)
    task.wait(math.max(hold, 0) + 0.10)
    local okE = pcall(function() p:InputHoldEnd() end)
    arrestBusy = false
    out(string.format("铐 %s · 按住 %.2fs (begin=%s end=%s)",
        best.model.Name, hold, tostring(okB), tostring(okE)))

    task.delay(1.0, function()
        local after = snapshot(best.model)
        local changed = nil
        for k, v in pairs(before) do if after[k] ~= v then changed = k end end
        if not changed then
            for k, v in pairs(after) do if before[k] ~= v then changed = k end end
        end
        out(changed and ("成功 · 变化 " .. tostring(changed)) or "无变化（服务端未接受）")
    end)
end

-- ============================================================
-- 四、无后坐力（无后座.lua）
-- ============================================================
local NO_RECOIL_KEYS = {"recoil", "kick", "shake", "spread", "jitter", "bloom",
                        "sway", "kickback", "cameraoffset", "punchanim"}
local NO_RECOIL_SKIP = {"reload", "ammo", "damage", "firerate", "rate", "speed", "delay"}
local recoilOriginals = setmetatable({}, {__mode = "k"})
local recoilLastScan = 0

local function tools()
    local list = {}
    local char = LP.Character
    if char then
        for _, t in ipairs(char:GetChildren()) do
            if t:IsA("Tool") then list[#list + 1] = t end
        end
    end
    local bp = LP:FindFirstChildOfClass("Backpack")
    if bp then
        for _, t in ipairs(bp:GetChildren()) do
            if t:IsA("Tool") then list[#list + 1] = t end
        end
    end
    return list
end

local function applyRecoilZero(tool)
    local n = 0
    pcall(function()
        for _, d in ipairs(tool:GetDescendants()) do
            if (d:IsA("NumberValue") or d:IsA("IntValue"))
            and matchAny(d.Name, NO_RECOIL_KEYS)
            and not matchAny(d.Name, NO_RECOIL_SKIP) then
                if d.Value ~= 0 then
                    if recoilOriginals[d] == nil then recoilOriginals[d] = d.Value end
                    d.Value = 0
                    n = n + 1
                end
            end
        end
        for k, v in pairs(tool:GetAttributes()) do
            if type(v) == "number" and matchAny(k, NO_RECOIL_KEYS)
            and not matchAny(k, NO_RECOIL_SKIP) then
                if recoilOriginals[tool] == nil then recoilOriginals[tool] = {} end
                if recoilOriginals[tool][k] == nil then recoilOriginals[tool][k] = v end
                pcall(function() tool:SetAttribute(k, 0) end)
                n = n + 1
            end
        end
    end)
    return n
end

local function restoreRecoil()
    local n = 0
    for inst, v in pairs(recoilOriginals) do
        if type(v) == "number" then
            if inst and inst.Parent then
                pcall(function() inst.Value = v end)
                n = n + 1
            end
        else
            for k, vv in pairs(v) do
                pcall(function() inst:SetAttribute(k, vv) end)
                n = n + 1
            end
        end
        recoilOriginals[inst] = nil
    end
    out("已还原 " .. n .. " 个后坐力字段")
end

-- ============================================================
-- 五、汽车加速（787878.lua）
-- ============================================================
local carRig = nil
local carPrev, carDecel, carSusp = 0, 0, 0
local carTarget, carPhase, carPhaseT, carCoast, carPedal, carPedAccel = 0, "coast", 0, 0, false, 0
local carLastParam = 0
local carReason = "-"

local function clearCarRig()
    if carRig then
        pcall(function() carRig.force:Destroy() end)
        pcall(function() carRig.att:Destroy() end)
        pcall(function() carRig.bv:Destroy() end)
    end
    carRig = nil
end

local function ensureCarRig(part)
    if carRig and carRig.part == part and carRig.force.Parent == part then return carRig end
    clearCarRig()
    local att = Instance.new("Attachment")
    att.Parent = part
    local vf = Instance.new("VectorForce")
    vf.Attachment0 = att
    vf.RelativeTo = Enum.ActuatorRelativeTo.World
    vf.ApplyAtCenterOfMass = true
    vf.Force = Vector3.zero
    vf.Parent = part
    local bv = Instance.new("BodyVelocity")
    bv.MaxForce = Vector3.zero
    bv.Velocity = Vector3.zero
    bv.Parent = part
    carRig = {part = part, force = vf, att = att, bv = bv}
    return carRig
end

local function boostCarParams(model)
    if not S.carParams then return end
    if os.clock() - carLastParam < 1.5 then return end
    carLastParam = os.clock()
    pcall(function()
        for _, d in ipairs(model:GetDescendants()) do
            if d:IsA("NumberValue") or d:IsA("IntValue") then
                local n = string.lower(d.Name)
                if n:find("maxspeed") or n:find("speedlimit") or n:find("topspeed") then
                    if type(d.Value) == "number" and d.Value < 260 then d.Value = 260 end
                end
            end
        end
    end)
end

local function carTick(dt)
    local seat = seatPart()
    if not seat then
        if carRig then clearCarRig() end
        carPrev, carDecel, carTarget = 0, 0, 0
        carPhase, carPhaseT, carPedal = "coast", 0, false
        carReason = "未上车"
        if uiRefs.carInfo then uiRefs.carInfo.Text = "车辆：未上车" end
        return
    end

    pcall(function()
        if seat:IsA("VehicleSeat") then
            seat.MaxSpeed = 250
            seat.Torque = 100000
        end
    end)

    local part = chassis(seat)
    local model = seat:FindFirstAncestorOfClass("Model") or part
    boostCarParams(model)

    local r = ensureCarRig(part)
    local mass = (part.AssemblyMass and part.AssemblyMass > 0) and part.AssemblyMass or 1
    local vel = part.AssemblyLinearVelocity
    local speed = vel.Magnitude

    local instDecel = (carPrev - speed) / math.max(dt, 0.001)
    local k = math.clamp(dt / 0.35, 0, 1)
    carDecel = carDecel + (instDecel - carDecel) * k
    carPrev = speed
    if carDecel > 12 then
        carSusp = os.clock() + 0.35
        carPedal = false
    end
    local braking = os.clock() < carSusp

    carPhaseT = carPhaseT + dt
    if carPhase == "push" then
        if carPhaseT >= 0.45 then
            carPhase, carPhaseT, carCoast = "coast", 0, speed
        end
    else
        if carPhaseT >= 0.20 then
            carPedAccel = (speed - carCoast) / math.max(carPhaseT, 0.01)
            carPedal = carPedAccel > 3
            carPhase, carPhaseT = "push", 0
        end
    end

    local dir = (speed > 0.5) and vel.Unit or Vector3.zero
    local wantPush = (not S.carAlways) and carPedal or S.carAlways
    if braking or speed < 3 or speed >= S.carMax then wantPush = false end
    if (not S.carAlways) and carPhase == "coast" then wantPush = false end

    carReason = "-"
    if braking then carReason = "刹"
    elseif speed < 3 then carReason = "静"
    elseif speed >= S.carMax then carReason = "顶"
    elseif (not S.carAlways) and carPhase == "coast" then carReason = "测"
    elseif (not S.carAlways) and not carPedal then carReason = "松" end

    if S.carMode == "force" then
        r.bv.MaxForce = Vector3.zero
        if wantPush and dir.Magnitude > 0.1 then
            local f = dir * (mass * S.carAccel)
            local lateral = vel - dir * vel:Dot(dir)
            if lateral.Magnitude > 0.8 then
                f = f - lateral * (mass * 0.4)
            end
            r.force.Force = f
        else
            r.force.Force = Vector3.zero
        end
    else
        r.force.Force = Vector3.zero
        if wantPush and dir.Magnitude > 0.1 then
            carTarget = math.min(90, math.max(carTarget, speed) + 60 * dt)
            if speed < carTarget then
                r.bv.MaxForce = Vector3.new(mass * 400, 0, mass * 400)
                r.bv.Velocity = dir * carTarget
            end
        else
            r.bv.MaxForce = Vector3.zero
            carTarget = speed
        end
    end

    if uiRefs.carInfo then
        uiRefs.carInfo.Text = string.format(
            "车速 %d  %s  模式 %s\n油门 %s  探测 %d\n系数 %d  上限 %d",
            math.floor(speed), carReason, S.carMode,
            carPedal and "踩" or "松", math.floor(carPedAccel),
            S.carAccel, S.carMax)
    end
end

-- ============================================================
-- 六、玩家传送 / 车辆飞悬（玩家传送V2.lua）
-- ============================================================
local flying, holdingFlight, flightTarget = false, false, nil
local flyRig = nil
local lastTP, lastDiag = 0, 0

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

local function teleportToPlayer(plr)
    if os.clock() - lastTP < 0.8 then return end
    lastTP = os.clock()
    local r = hrp()
    local p = targetPart(plr)
    if not r then out("无角色") return end
    if not p then out(plr.Name .. " 没有角色") return end
    local ok = pcall(function()
        r.CFrame = CFrame.new(p.Position + Vector3.new(0, 5, 0))
        r.AssemblyLinearVelocity = Vector3.zero
    end)
    out(ok and ("人物 → " .. plr.Name .. " 头顶") or "人物传送失败")
end

local function groundY(pos)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    local list = {}
    if LP.Character then list[#list + 1] = LP.Character end
    local seat = seatPart()
    if seat then
        local m = seat:FindFirstAncestorOfClass("Model")
        if m then list[#list + 1] = m end
    end
    params.FilterDescendantsInstances = list
    local ok, hit = pcall(function()
        return workspace:Raycast(pos, Vector3.new(0, -600, 0), params)
    end)
    if ok and hit then return hit.Position.Y end
    return nil
end

local function obstacleAhead(part, dir)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    local list = {}
    if LP.Character then list[#list + 1] = LP.Character end
    local seat = seatPart()
    if seat then
        local m = seat:FindFirstAncestorOfClass("Model")
        if m then list[#list + 1] = m end
    end
    params.FilterDescendantsInstances = list
    local ok, hit = pcall(function()
        return workspace:Raycast(part.Position + Vector3.new(0, 1.5, 0), dir * 22, params)
    end)
    if ok and hit then return hit end
    return nil
end

local function clearFlyRig()
    if flyRig then
        pcall(function() flyRig.force:Destroy() end)
        pcall(function() flyRig.att:Destroy() end)
    end
    flyRig = nil
end

local function ensureFlyRig(part)
    if flyRig and flyRig.part == part and flyRig.force.Parent == part then return flyRig end
    clearFlyRig()
    local att = Instance.new("Attachment")
    att.Parent = part
    local vf = Instance.new("VectorForce")
    vf.Attachment0 = att
    vf.RelativeTo = Enum.ActuatorRelativeTo.World
    vf.ApplyAtCenterOfMass = true
    vf.Force = Vector3.zero
    vf.Parent = part
    flyRig = {part = part, force = vf, att = att}
    return flyRig
end

local function stopFlight()
    flying, holdingFlight = false, false
    clearFlyRig()
    if uiRefs.flyInfo then uiRefs.flyInfo.Text = "飞行：空闲" end
end

local function startFlight(plr)
    if not seatPart() then
        out("没坐在车里，改为人物传送")
        teleportToPlayer(plr)
        return
    end
    flightTarget = plr
    flying, holdingFlight = true, false
    out("车飞 → " .. plr.Name)
end

local function flyTick(dt)
    if not flying then return end
    local seat = seatPart()
    if not seat then
        out("已下车，停止飞行")
        stopFlight()
        return
    end
    local part = chassis(seat)
    local r = ensureFlyRig(part)
    local mass = (part.AssemblyMass and part.AssemblyMass > 0) and part.AssemblyMass or 1
    local vel = part.AssemblyLinearVelocity
    local tp = targetPos(flightTarget)
    if not tp then
        out("目标丢失")
        stopFlight()
        return
    end

    local delta = tp - part.Position
    local dist = delta.Magnitude
    local horiz = Vector3.new(delta.X, 0, delta.Z).Magnitude

    if dist > 1000 then
        out(string.format("目标太远（%.0f），停止", dist))
        stopFlight()
        return
    end

    local gy = groundY(part.Position + Vector3.new(0, 4, 0))
    local floorLimit = gy and (gy + 8) or nil
    local targetY = tp.Y + 10
    if floorLimit and targetY < floorLimit then targetY = floorLimit end

    if S.voidGuard and part.Position.Y < -40 then
        out("掉入虚空，停止飞行")
        stopFlight()
        return
    end

    local hDir = Vector3.new(delta.X, 0, delta.Z)
    if horiz <= 18 then
        if not holdingFlight then
            holdingFlight = true
            out("已到目标附近，悬停")
        end
        r.force.Force = -Vector3.new(vel.X, 0, vel.Z) * (mass * 6)
        if uiRefs.flyInfo then
            uiRefs.flyInfo.Text = string.format("飞行：悬停 距 %dm", math.floor(horiz))
        end
        return
    end

    holdingFlight = false
    local f = Vector3.zero
    if hDir.Magnitude > 0.5 then f = hDir.Unit * (mass * 160) end
    local hit = (hDir.Magnitude > 0.5) and obstacleAhead(part, hDir.Unit) or nil
    local stuck = vel.Magnitude < 1.5
    local nearCeil = part.Position.Y > tp.Y + 140
    if (hit or stuck) and not nearCeil and vel.Y < 55 then
        f = f + Vector3.new(0, mass * 800, 0)
        if stuck then f = f + Vector3.new(0, mass * 320, 0) end
    end
    r.force.Force = f

    if os.clock() - lastDiag > 0.7 then
        lastDiag = os.clock()
        if uiRefs.flyInfo then
            uiRefs.flyInfo.Text = string.format("飞行：追 %s  距 %dm  速度 %d  障碍 %s",
                flightTarget and flightTarget.Name or "-",
                math.floor(horiz), math.floor(vel.Magnitude),
                hit and hit.Instance.Name:sub(1, 8) or "无")
        end
    end
end

-- ============================================================
-- 七、地点传送（传送.lua）+ 自定义地点
-- ============================================================
local BASE_PRESETS = {
    {name = "银行",       x = -265,  y = 5, z = -313},
    {name = "医院",       x = -1126, y = 5, z = 1047},
    {name = "车店",       x = -340,  y = 4, z = 980},
    {name = "农村加油站", x = -18,   y = 4, z = 1110},
    {name = "黑市",       x = 1088,  y = 4, z = 463},
    {name = "消防站",     x = -421,  y = 5, z = -1122},
    {name = "警察局",     x = 109,   y = 5, z = -1087},
    {name = "城市加油站", x = -1129, y = 5, z = -1031},
    {name = "消星地点",   x = -513,  y = 5, z = -518},
}

local customPresets = {}
local lastTPUse = 0

local function decodePresets()
    customPresets = {}
    local raw = tostring(P.presets or "")
    for chunk in string.gmatch(raw, "[^;]+") do
        local n, x, y, z = string.match(chunk, "^([^,]+),([^,]+),([^,]+),([^,]+)$")
        if n then
            customPresets[#customPresets + 1] = {
                name = n, x = tonumber(x) or 0, y = tonumber(y) or 5, z = tonumber(z) or 0,
            }
        end
    end
end

local function encodePresets()
    local parts = {}
    for _, p in ipairs(customPresets) do
        parts[#parts + 1] = string.format("%s,%d,%d,%d", p.name, p.x, p.y, p.z)
    end
    P.presets = table.concat(parts, ";")
    saveCfg()
end

decodePresets()

local function teleportTo(preset)
    if os.clock() - lastTPUse < 0.35 then return end
    lastTPUse = os.clock()
    local r = hrp()
    if not r then out("无角色") return end
    local ok = pcall(function()
        r.CFrame = CFrame.new(preset.x, preset.y, preset.z)
        r.AssemblyLinearVelocity = Vector3.zero
    end)
    if ok then
        out(string.format("→ %s (%.0f, %.0f, %.0f)", preset.name, preset.x, preset.y, preset.z))
        pcall(function()
            local h = hum()
            if h then h:ChangeState(Enum.HumanoidStateType.GettingUp) end
        end)
    else
        out("传送失败: " .. preset.name)
    end
end

local function addCurrentPreset()
    local r = hrp()
    if not r then out("无角色") return end
    local p = r.Position
    local name = "自定" .. tostring(#customPresets + 1)
    customPresets[#customPresets + 1] = {
        name = name, x = math.floor(p.X), y = math.floor(p.Y), z = math.floor(p.Z),
    }
    encodePresets()
    out(string.format("已记录 %s (%d, %d, %d)", name, p.X, p.Y, p.Z))
end

-- ============================================================
-- 八、UI 构建
-- ============================================================
local gui = el("ScreenGui", {
    Name = "__GEN4_HUB",
    ResetOnSpawn = false,
    IgnoreGuiInset = true,
    DisplayOrder = 2000,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, PG)

-- 手机安全区：避开刘海 / 圆角 / 手势条（旧版客户端不支持则忽略）
pcall(function() gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets end)
pcall(function() gui.ClipToDeviceSafeArea = true end)

-- 悬浮球
local ball = el("TextButton", {
    Name = "Ball",
    Size = UDim2.new(0, 62, 0, 62),
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.new(1, P.btnX, 1, P.btnY),
    BackgroundColor3 = Color3.fromRGB(24, 26, 34),
    BackgroundTransparency = 0.08,
    Text = "刀",
    TextSize = 24,
    Font = Enum.Font.GothamBold,
    TextColor3 = Color3.fromRGB(190, 220, 255),
    BorderSizePixel = 0,
    AutoButtonColor = false,
}, gui)
deco(ball, 31, Color3.fromRGB(90, 170, 255), 2)
touchify(ball)

-- 主面板尺寸：竖屏=底部抽屉，横屏=居中卡片（触屏尺寸单位）
local vp = viewport()
local BASE_W, BASE_H = 334, 460
local PANEL_W, PANEL_H = BASE_W, BASE_H
local isPortrait = vp.Y > vp.X

local function calcPanel()
    local v = viewport()
    local portrait = v.Y > v.X
    local w, h
    if portrait then
        w = math.min(v.X - 16, 430)
        h = v.Y * 0.62
    else
        w = math.min(v.X - 20, BASE_W)
        h = math.min(v.Y - 16, BASE_H)
    end
    return math.max(math.floor(w), 252), math.max(math.floor(h), 262), portrait
end
PANEL_W, PANEL_H, isPortrait = calcPanel()
local applyLayout   -- 前向声明：屏幕旋转/尺寸变化时重排

local panel = el("Frame", {
    Name = "Panel",
    Size = UDim2.new(0, PANEL_W, 0, PANEL_H),
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = (P.panelX ~= 0 or P.panelY ~= 0)
        and UDim2.new(0.5, P.panelX, 0.5, P.panelY)
        or UDim2.new(0.5, 0, 0.5, 0),
    BackgroundColor3 = C.bg,
    BackgroundTransparency = 0.04,
    BorderSizePixel = 0,
    Visible = false,
    ClipsDescendants = true,
}, gui)
deco(panel, 16, Color3.fromRGB(70, 130, 240), 2)

-- 标题栏
local titleBar = el("Frame", {
    Size = UDim2.new(1, 0, 0, 46),
    BackgroundColor3 = C.bg2,
    BorderSizePixel = 0,
}, panel)
deco(titleBar, 16)

local title = el("TextLabel", {
    Size = UDim2.new(1, -96, 1, 0),
    Position = UDim2.new(0, 14, 0, 0),
    BackgroundTransparency = 1,
    Font = Enum.Font.GothamBold,
    TextSize = 16,
    TextColor3 = C.text,
    TextXAlignment = Enum.TextXAlignment.Left,
    Text = "GEN4 整合面板",
}, titleBar)

local statusDot = el("TextLabel", {
    Size = UDim2.new(0, 66, 0, 18),
    Position = UDim2.new(1, -156, 0.5, -9),
    BackgroundTransparency = 1,
    Font = Enum.Font.Gotham,
    TextSize = 11,
    TextColor3 = C.sub,
    TextXAlignment = Enum.TextXAlignment.Right,
    Text = "待命",
}, titleBar)

local function smallBtn(text, x, color, onClick)
    local b = el("TextButton", {
        Size = UDim2.new(0, 36, 0, 36),
        Position = UDim2.new(1, x, 0.5, -18),
        BackgroundColor3 = color or C.off,
        Text = text,
        TextSize = 16,
        Font = Enum.Font.GothamBold,
        TextColor3 = C.text,
        BorderSizePixel = 0,
        AutoButtonColor = false,
    }, titleBar)
    deco(b, 10)
    touchify(b)
    b.MouseButton1Click:Connect(onClick or function() end)
    return b
end

local collapsed = false
local minBtn = smallBtn("–", -84, C.off, nil)
local closeBtn = smallBtn("×", -44, C.red, nil)

-- 分页容器
local body = el("Frame", {
    Size = UDim2.new(1, 0, 1, -46),
    Position = UDim2.new(0, 0, 0, 46),
    BackgroundTransparency = 1,
}, panel)

-- 分页标签栏
local tabBar = el("Frame", {
    Size = UDim2.new(1, -16, 0, 38),
    Position = UDim2.new(0, 8, 0, 8),
    BackgroundTransparency = 1,
}, body)

local tabLayout = el("UIListLayout", {
    FillDirection = Enum.FillDirection.Horizontal,
    Padding = UDim.new(0, 4),
    SortOrder = Enum.SortOrder.LayoutOrder,
}, tabBar)

local TABS = {"透视", "传送", "战斗", "车辆", "设置"}
local tabButtons, pages = {}, {}
local currentTab = 1

local pagesHolder = el("Frame", {
    Size = UDim2.new(1, 0, 1, -52),
    Position = UDim2.new(0, 0, 0, 52),
    BackgroundTransparency = 1,
}, body)

local function newPage()
    local sc = el("ScrollingFrame", {
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 5,
        ScrollBarImageColor3 = Color3.fromRGB(96, 108, 140),
        ScrollingDirection = Enum.ScrollingDirection.Y,
        ElasticBehavior = Enum.ElasticBehavior.WhenScrollable,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        Visible = false,
    }, pagesHolder)
    local layout = el("UIListLayout", {
        Padding = UDim.new(0, 6),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, sc)
    el("UIPadding", {
        PaddingTop = UDim.new(0, 4),
        PaddingBottom = UDim.new(0, 10),
        PaddingLeft = UDim.new(0, 8),
        PaddingRight = UDim.new(0, 8),
    }, sc)
    layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        sc.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 14)
    end)
    return sc
end

local function selectTab(i)
    if not pages[i] then return end
    currentTab = i
    pcall(function() pages[i].CanvasPosition = Vector2.new(0, 0) end)
    for j, other in ipairs(pages) do
        other.Visible = (j == i)
        if tabButtons[j] then
            tabButtons[j].BackgroundColor3 = (j == i) and C.accent or C.card
            tabButtons[j].TextColor3 = (j == i) and Color3.new(1, 1, 1) or C.sub
        end
    end
    if i == 2 then
        pcall(function() uiRefs.refreshPlayers() end)
        pcall(function() uiRefs.refreshPresets() end)
    end
end

for i, name in ipairs(TABS) do
    local b = el("TextButton", {
        Size = UDim2.new(1 / #TABS, -4, 1, 0),
        LayoutOrder = i,
        BackgroundColor3 = C.card,
        Text = name,
        TextSize = 13,
        Font = Enum.Font.GothamBold,
        TextColor3 = C.sub,
        BorderSizePixel = 0,
        AutoButtonColor = false,
    }, tabBar)
    deco(b, 9)
    touchify(b)
    tabButtons[i] = b
    pages[i] = newPage()
    b.MouseButton1Click:Connect(function() selectTab(i) end)
end

-- 默认选中第一页
tabButtons[1].BackgroundColor3 = C.accent
tabButtons[1].TextColor3 = Color3.new(1, 1, 1)
pages[1].Visible = true

-- 手机：在内容区左右滑动切换分页
do
    local swipeFrom = nil
    local function bindSwipe(obj)
        obj.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.Touch then
                swipeFrom = input.Position
            end
        end)
        obj.InputChanged:Connect(function(input)
            if not swipeFrom then return end
            if input.UserInputType ~= Enum.UserInputType.Touch then return end
            local d = input.Position - swipeFrom
            if math.abs(d.X) > 90 and math.abs(d.X) > math.abs(d.Y) * 1.8 then
                local dir = (d.X < 0) and 1 or -1
                local target = math.clamp(currentTab + dir, 1, #TABS)
                if target ~= currentTab then selectTab(target) end
                swipeFrom = nil
            end
        end)
        obj.InputEnded:Connect(function() swipeFrom = nil end)
    end
    bindSwipe(pagesHolder)
    for _, pg in ipairs(pages) do bindSwipe(pg) end
end

-- 控件工厂
local function section(parent, text)
    return el("TextLabel", {
        Size = UDim2.new(1, 0, 0, 28),
        BackgroundTransparency = 1,
        Font = Enum.Font.GothamBold,
        TextSize = 14,
        TextColor3 = Color3.fromRGB(120, 180, 255),
        TextXAlignment = Enum.TextXAlignment.Left,
        Text = "· " .. text,
    }, parent)
end

local function makeSwitch(parent, label, value, onColor, onChange)
    local row = el("Frame", {Size = UDim2.new(1, 0, 0, 44), BackgroundTransparency = 1}, parent)
    el("TextLabel", {
        Size = UDim2.new(1, -104, 1, 0),
        BackgroundTransparency = 1,
        Font = Enum.Font.Gotham,
        TextSize = 13,
        TextColor3 = C.text,
        TextXAlignment = Enum.TextXAlignment.Left,
        Text = label,
    }, row)
    local btn = el("TextButton", {
        Size = UDim2.new(0, 96, 0, 38),
        Position = UDim2.new(1, -96, 0.5, -19),
        BackgroundColor3 = value and onColor or C.off,
        Text = value and "已开启" or "已关闭",
        TextSize = 13,
        Font = Enum.Font.GothamBold,
        TextColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0,
        AutoButtonColor = false,
    }, row)
    deco(btn, 12)
    touchify(btn)
    local state = value
    local function paint()
        btn.BackgroundColor3 = state and onColor or C.off
        btn.Text = state and "已开启" or "已关闭"
        btn.TextTransparency = state and 0 or 0.15
    end
    paint()
    btn.MouseButton1Click:Connect(function()
        state = not state
        paint()
        onChange(state)
    end)
    return {
        get = function() return state end,
        set = function(v)
            if v ~= state then
                state = v
                paint()
            end
        end,
    }
end

local function makeSeg(parent, label, options, index, onChange)
    local row = el("Frame", {Size = UDim2.new(1, 0, 0, 44), BackgroundTransparency = 1}, parent)
    el("TextLabel", {
        Size = UDim2.new(1, -150, 1, 0),
        BackgroundTransparency = 1,
        Font = Enum.Font.Gotham,
        TextSize = 13,
        TextColor3 = C.text,
        TextXAlignment = Enum.TextXAlignment.Left,
        Text = label,
    }, row)
    local holder = el("Frame", {
        Size = UDim2.new(0, 146, 0, 38),
        Position = UDim2.new(1, -146, 0.5, -19),
        BackgroundColor3 = C.bg2,
        BorderSizePixel = 0,
    }, row)
    deco(holder, 8)
    local btns = {}
    local w = 146 / #options
    local function paint()
        for i, b in ipairs(btns) do
            local on = (i == index)
            b.BackgroundColor3 = on and C.accent or C.off
            b.TextColor3 = on and Color3.new(1, 1, 1) or C.sub
        end
    end
    for i, opt in ipairs(options) do
        local b = el("TextButton", {
            Size = UDim2.new(0, w - 4, 0, 34),
            Position = UDim2.new(0, (i - 1) * w + 2, 0, 2),
            BackgroundColor3 = C.off,
            Text = opt,
            TextSize = 12,
            Font = Enum.Font.GothamBold,
            BorderColor3 = Color3.new(0, 0, 0),
            TextColor3 = C.sub,
            BorderSizePixel = 0,
            AutoButtonColor = false,
        }, holder)
        deco(b, 8)
        touchify(b)
        b.MouseButton1Click:Connect(function()
            index = i
            paint()
            onChange(i, opt)
        end)
        btns[i] = b
    end
    paint()
    return {
        get = function() return index end,
        set = function(i)
            index = i
            paint()
        end,
    }
end

local function makeStepper(parent, label, value, min, max, step, fmt, onChange)
    local row = el("Frame", {Size = UDim2.new(1, 0, 0, 44), BackgroundTransparency = 1}, parent)
    el("TextLabel", {
        Size = UDim2.new(1, -150, 1, 0),
        BackgroundTransparency = 1,
        Font = Enum.Font.Gotham,
        TextSize = 13,
        TextColor3 = C.text,
        TextXAlignment = Enum.TextXAlignment.Left,
        Text = label,
    }, row)
    local val = el("TextLabel", {
        Size = UDim2.new(0, 66, 1, 0),
        Position = UDim2.new(1, -136, 0, 0),
        BackgroundTransparency = 1,
        Font = Enum.Font.Code,
        TextSize = 13,
        TextColor3 = Color3.fromRGB(150, 210, 255),
        Text = fmt(value),
    }, row)
    local function stepBtn(text, x, dir)
        local b = el("TextButton", {
            Size = UDim2.new(0, 40, 0, 38),
            Position = UDim2.new(1, x, 0.5, -19),
            BackgroundColor3 = C.card,
            Text = text,
            TextSize = 16,
            Font = Enum.Font.GothamBold,
            TextColor3 = C.text,
            BorderSizePixel = 0,
            AutoButtonColor = false,
        }, row)
        deco(b, 11)
        touchify(b)
        b.MouseButton1Click:Connect(function()
            value = math.clamp(value + dir * step, min, max)
            val.Text = fmt(value)
            onChange(value)
        end)
    end
    stepBtn("–", -100, -1)
    stepBtn("+", -34, 1)
    return {
        get = function() return value end,
        set = function(v)
            value = math.clamp(v, min, max)
            val.Text = fmt(value)
        end,
    }
end

local function makeActions(parent, actions)
    local row = el("Frame", {Size = UDim2.new(1, 0, 0, 40), BackgroundTransparency = 1}, parent)
    local n = #actions
    local layout = el("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        Padding = UDim.new(0, 6),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, row)
    for i, a in ipairs(actions) do
        local b = el("TextButton", {
            Size = UDim2.new(1 / n, -(6 * (n - 1)) / n, 1, 0),
            LayoutOrder = i,
            BackgroundColor3 = a.color or C.card,
            Text = a.text,
            TextSize = 13,
            Font = Enum.Font.GothamBold,
            TextColor3 = a.textColor or C.text,
            BorderSizePixel = 0,
            AutoButtonColor = false,
        }, row)
        deco(b, 10)
        touchify(b)
        b.MouseButton1Click:Connect(function()
            local ok, err = pcall(a.onClick)
            if not ok then out("按钮出错: " .. tostring(err)) end
        end)
    end
    return row
end

local function makeInfo(parent, text, height)
    local holder = el("Frame", {
        Size = UDim2.new(1, 0, 0, height or 44),
        BackgroundColor3 = Color3.fromRGB(22, 24, 30),
        BackgroundTransparency = 0.2,
        BorderSizePixel = 0,
    }, parent)
    deco(holder, 8, Color3.fromRGB(60, 80, 120), 1)
    local lbl = el("TextLabel", {
        Size = UDim2.new(1, -12, 1, -8),
        Position = UDim2.new(0, 6, 0, 4),
        BackgroundTransparency = 1,
        Font = Enum.Font.Code,
        TextSize = 12,
        TextWrapped = true,
        TextYAlignment = Enum.TextYAlignment.Top,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextColor3 = Color3.fromRGB(170, 205, 240),
        Text = text,
    }, holder)
    return lbl
end

-- ============================================================
-- 九、各分页内容
-- ============================================================
local espPage, tpPage, fightPage, carPage, setPage = pages[1], pages[2], pages[3], pages[4], pages[5]

-- ---------- 透视 ----------
section(espPage, "透视标记")
makeSwitch(espPage, "ESP 透视", S.esp, C.green, function(v)
    S.esp = v
    if v then startESP() else stopESP() end
    if uiRefs.dot then uiRefs.dot.Text = v and "透视中" or "待命" end
end)
makeSeg(espPage, "显示对象", {"全部", "仅通缉"}, (S.espFilter == "wanted") and 2 or 1, function(i)
    S.espFilter = (i == 2) and "wanted" or "all"
    P.espFilter = S.espFilter
    saveCfg()
    out("显示对象: " .. ((i == 2) and "仅通缉" or "全部"))
end)
makeSeg(espPage, "配色", {"红", "黄", "绿", "蓝", "紫"}, math.clamp(S.espColor, 1, 5), function(i)
    S.espColor = i
    P.espColor = i
    saveCfg()
end)
makeStepper(espPage, "刷新间隔 (s)", S.espInterval, 0.2, 2.0, 0.1,
    function(v) return string.format("%.1f", v) end,
    function(v) S.espInterval = v; P.espInterval = v; saveCfg() end)
makeStepper(espPage, "渲染距离 (m)", S.espRange, 0, 2000, 100,
    function(v) return (v <= 0) and "不限" or tostring(math.floor(v)) end,
    function(v) S.espRange = v; P.espRange = v; saveCfg() end)
uiRefs.espInfo = makeInfo(espPage, "标记人数 0", 30)

-- ---------- 传送 ----------
section(tpPage, "地点传送")
local presetHolder = el("Frame", {
    Size = UDim2.new(1, 0, 0, 0),
    BackgroundTransparency = 1,
    AutomaticSize = Enum.AutomaticSize.Y,
}, tpPage)
local presetLayout = el("UIListLayout", {
    Padding = UDim.new(0, 4),
    SortOrder = Enum.SortOrder.LayoutOrder,
}, presetHolder)

local function refreshPresets()
    for _, ch in ipairs(presetHolder:GetChildren()) do
        if ch:IsA("TextButton") then ch:Destroy() end
    end
    local order = 0
    local function addBtn(label, preset, custom)
        order = order + 1
        local row = el("Frame", {
            Size = UDim2.new(1, 0, 0, 44),
            LayoutOrder = order,
            BackgroundTransparency = 1,
        }, presetHolder)
        local b = el("TextButton", {
            Size = UDim2.new(1, custom and -46 or 0, 1, 0),
            BackgroundColor3 = C.card,
            Text = label,
            TextSize = 13,
            Font = Enum.Font.GothamBold,
            TextColor3 = C.text,
            BorderSizePixel = 0,
            AutoButtonColor = false,
        }, row)
        deco(b, 10)
        touchify(b)
        b.MouseButton1Click:Connect(function() pcall(teleportTo, preset) end)
        if custom then
            local del = el("TextButton", {
                Size = UDim2.new(0, 40, 1, 0),
                Position = UDim2.new(1, -40, 0, 0),
                BackgroundColor3 = Color3.fromRGB(80, 44, 44),
                Text = "×",
                TextSize = 14,
                Font = Enum.Font.GothamBold,
                TextColor3 = Color3.fromRGB(255, 200, 200),
                BorderSizePixel = 0,
                AutoButtonColor = false,
            }, row)
            deco(del, 10)
            touchify(del)
            del.MouseButton1Click:Connect(function()
                for i, p in ipairs(customPresets) do
                    if p == preset then
                        table.remove(customPresets, i)
                        break
                    end
                end
                encodePresets()
                refreshPresets()
                out("已删除自定义地点")
            end)
        end
    end
    for _, p in ipairs(BASE_PRESETS) do addBtn(p.name, p, false) end
    for _, p in ipairs(customPresets) do
        addBtn(string.format("%s (%d,%d,%d)", p.name, p.x, p.y, p.z), p, true)
    end
end
uiRefs.refreshPresets = refreshPresets
refreshPresets()

makeActions(tpPage, {
    {text = "记录当前位置", color = C.green, onClick = function()
        addCurrentPreset()
        refreshPresets()
    end},
    {text = "清空自定义", color = C.off, onClick = function()
        customPresets = {}
        encodePresets()
        refreshPresets()
        out("自定义地点已清空")
    end},
})

section(tpPage, "玩家传送")
makeSwitch(tpPage, "人物传送（点名字瞬移）", S.playerTp, C.green, function(v)
    S.playerTp = v
end)
makeSwitch(tpPage, "车辆飞悬（点名字飞过去）", S.carFly, C.blue or C.accent, function(v)
    S.carFly = v
    if not v then stopFlight() end
end)
makeSwitch(tpPage, "防掉虚空保护", S.voidGuard, C.green, function(v) S.voidGuard = v end)
makeActions(tpPage, {
    {text = "传送到最近玩家", color = C.accent, onClick = function()
        local me = hrp()
        if not me then out("无角色") return end
        local best, bd = nil, math.huge
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LP then
                local p = targetPos(plr)
                if p then
                    local d = (p - me.Position).Magnitude
                    if d < bd then best, bd = plr, d end
                end
            end
        end
        if best then teleportToPlayer(best) else out("没有其他玩家") end
    end},
    {text = "停止车辆飞行", color = C.red, onClick = function()
        stopFlight()
        out("已停止飞行")
    end},
})
uiRefs.flyInfo = makeInfo(tpPage, "飞行：空闲", 34)

local playerBox = el("ScrollingFrame", {
    Size = UDim2.new(1, 0, 0, 176),
    BackgroundColor3 = Color3.fromRGB(18, 19, 25),
    BackgroundTransparency = 0.25,
    BorderSizePixel = 0,
    ScrollBarThickness = 3,
    CanvasSize = UDim2.new(0, 0, 0, 0),
}, tpPage)
deco(playerBox, 8)
local playerLayout = el("UIListLayout", {
    Padding = UDim.new(0, 4),
    SortOrder = Enum.SortOrder.LayoutOrder,
}, playerBox)
el("UIPadding", {
    PaddingTop = UDim.new(0, 4),
    PaddingBottom = UDim.new(0, 4),
    PaddingLeft = UDim.new(0, 4),
    PaddingRight = UDim.new(0, 4),
}, playerBox)
playerLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    playerBox.CanvasSize = UDim2.new(0, 0, 0, playerLayout.AbsoluteContentSize.Y + 10)
end)

local function refreshPlayers()
    for _, ch in ipairs(playerBox:GetChildren()) do
        if ch:IsA("TextButton") then ch:Destroy() end
    end
    local me = hrp()
    local entries = {}
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LP then
            local p = targetPos(plr)
            entries[#entries + 1] = {plr = plr, dist = (p and me) and (p - me.Position).Magnitude or 9999}
        end
    end
    table.sort(entries, function(a, b) return a.dist < b.dist end)

    local n = 0
    for _, e in ipairs(entries) do
        n = n + 1
        if n > 12 then break end
        local b = el("TextButton", {
            Size = UDim2.new(1, -6, 0, 44),
            LayoutOrder = n,
            BackgroundColor3 = C.card,
            Text = string.format("%s   %dm", e.plr.Name, math.floor(e.dist)),
            TextSize = 13,
            Font = Enum.Font.GothamBold,
            TextColor3 = C.text,
            BorderSizePixel = 0,
            AutoButtonColor = false,
        }, playerBox)
        deco(b, 10)
        touchify(b)
        b.MouseButton1Click:Connect(function()
            if S.carFly and seatPart() then
                startFlight(e.plr)
            elseif S.playerTp then
                teleportToPlayer(e.plr)
            elseif S.carFly then
                startFlight(e.plr)
            else
                out("两个传送开关都关着")
            end
        end)
    end
    if n == 0 then
        el("TextLabel", {
            Size = UDim2.new(1, -6, 0, 44),
            BackgroundTransparency = 1,
            Font = Enum.Font.Gotham,
            TextSize = 13,
            TextColor3 = C.sub,
            Text = "没有其他玩家",
        }, playerBox)
    end
end
uiRefs.refreshPlayers = refreshPlayers
refreshPlayers()

-- ---------- 战斗 ----------
section(fightPage, "自动铐人")
makeSwitch(fightPage, "自动铐人（自动锁最近目标）", S.arrestAuto, C.green, function(v)
    S.arrestAuto = v
    out("自动铐人 " .. (v and "开" or "关"))
end)
makeStepper(fightPage, "铐人距离 (m)", S.arrestDist, 3, 30, 1,
    function(v) return tostring(math.floor(v)) end,
    function(v) S.arrestDist = v; P.arrestDist = v; saveCfg() end)
makeStepper(fightPage, "冷却 (s)", S.arrestCd, 0.2, 3.0, 0.1,
    function(v) return string.format("%.1f", v) end,
    function(v) S.arrestCd = v; P.arrestCd = v; saveCfg() end)
makeSwitch(fightPage, "只铐通缉对象", S.arrestOnlyWanted, C.orange, function(v)
    S.arrestOnlyWanted = v
end)
makeActions(fightPage, {
    {text = "手动铐一次 (H)", color = C.red, onClick = function() tryArrest() end},
    {text = "重置计数", color = C.off, onClick = function()
        arrestAttempts = 0
        out("铐人计数已重置")
    end},
})
uiRefs.arrestInfo = makeInfo(fightPage, "铐人：待命", 34)

section(fightPage, "无后坐力")
makeSwitch(fightPage, "清零 recoil / spread", S.noRecoil, C.orange, function(v)
    S.noRecoil = v
    if not v then restoreRecoil() end
    out("无后坐力 " .. (v and "开" or "关"))
end)
makeActions(fightPage, {
    {text = "还原武器数值", color = C.off, onClick = function() restoreRecoil() end},
    {text = "立即扫描一次", color = C.card, onClick = function()
        local total = 0
        for _, t in ipairs(tools()) do total = total + applyRecoilZero(t) end
        out("清零 " .. total .. " 个字段")
    end},
})

-- ---------- 车辆 ----------
section(carPage, "汽车加速")
makeSwitch(carPage, "车辆加速", S.carBoost, C.accent, function(v)
    S.carBoost = v
    if not v then clearCarRig() end
    out("车辆加速 " .. (v and "开" or "关"))
end)
makeStepper(carPage, "推力系数", S.carAccel, 20, 200, 10,
    function(v) return tostring(math.floor(v)) end,
    function(v) S.carAccel = v; P.carAccel = v; saveCfg() end)
makeStepper(carPage, "速度上限", S.carMax, 60, 800, 20,
    function(v) return tostring(math.floor(v)) end,
    function(v) S.carMax = v; P.carMax = v; saveCfg() end)
makeSeg(carPage, "加速模式", {"推力", "速度"}, (S.carMode == "velocity") and 2 or 1, function(i)
    S.carMode = (i == 2) and "velocity" or "force"
    P.carMode = S.carMode
    saveCfg()
    out("加速模式: " .. S.carMode)
end)
makeSwitch(carPage, "恒定推力（不探测油门）", S.carAlways, C.orange, function(v)
    S.carAlways = v
    P.carAlways = v
    saveCfg()
    out(v and "常推模式" or "探测模式：踩油门才加速")
end)
makeSwitch(carPage, "车辆参数增强（MaxSpeed）", S.carParams, C.green, function(v)
    S.carParams = v
end)
uiRefs.carInfo = makeInfo(carPage, "车辆：未上车", 56)

-- ---------- 设置 ----------
section(setPage, "移动")
makeSwitch(setPage, "速度锁（无限体力）", S.speedLock, C.green, function(v) setSpeedLock(v) end)
makeStepper(setPage, "速度值", S.speed, 16, 120, 2,
    function(v) return tostring(math.floor(v)) end,
    function(v)
        S.speed = v
        P.speed = v
        saveCfg()
        if S.speedLock then setSpeedLock(true) end
    end)
makeSwitch(setPage, "拦截游戏降速", S.blockLower, C.green, function(v)
    S.blockLower = v
    out(v and "会拦截降速" or "不拦截降速")
end)

section(setPage, "面板")
makeActions(setPage, {
    {text = "回到屏幕中央", color = C.card, onClick = function()
        P.panelX, P.panelY = 0, 0
        panel.Position = UDim2.new(0.5, 0, 0.5, 0)
        panel.AnchorPoint = Vector2.new(0.5, 0.5)
        saveCfg()
        if applyLayout then applyLayout() end
    end},
    {text = "重置悬浮球", color = C.card, onClick = function()
        P.btnX, P.btnY = -92, -170
        if applyLayout then applyLayout() end
        saveCfg()
    end},
})
makeActions(setPage, {
    {text = "全部关闭", color = C.red, onClick = function()
        S.esp = false
        stopESP()
        setSpeedLock(false)
        S.noRecoil = false
        restoreRecoil()
        S.carBoost = false
        clearCarRig()
        S.arrestAuto = false
        stopFlight()
        out("已关闭全部功能")
    end},
    {text = "卸载面板", color = C.off, onClick = function()
        if type(_G.__gen4HubCleanup) == "function" then pcall(_G.__gen4HubCleanup) end
    end},
})

section(setPage, "日志")
local logBox = el("ScrollingFrame", {
    Size = UDim2.new(1, 0, 0, 168),
    BackgroundColor3 = Color3.fromRGB(12, 13, 17),
    BorderSizePixel = 0,
    ScrollBarThickness = 3,
    CanvasSize = UDim2.new(0, 0, 0, 0),
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
}, setPage)
deco(logBox, 8, Color3.fromRGB(50, 60, 90), 1)
local logLabel = el("TextLabel", {
    Size = UDim2.new(1, -10, 0, 0),
    Position = UDim2.new(0, 5, 0, 4),
    BackgroundTransparency = 1,
    Font = Enum.Font.Code,
    TextSize = 11,
    TextWrapped = true,
    TextYAlignment = Enum.TextYAlignment.Top,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextColor3 = Color3.fromRGB(180, 192, 214),
    AutomaticSize = Enum.AutomaticSize.Y,
    Text = "",
}, logBox)
uiRefs.logLabel = logLabel
logLabel:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
    logBox.CanvasSize = UDim2.new(0, 0, 0, logLabel.AbsoluteSize.Y + 12)
end)

-- ============================================================
-- 十、面板交互（拖动 / 收起 / 开关）
-- ============================================================
local function dragify(handle, target, onEnd, threshold)
    local dragging, moved, startPos, startInput = false, false, nil, nil
    threshold = threshold or 8
    handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch
        or input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging, moved = true, false
            startPos = target.Position
            startInput = input.Position
        end
    end)
    handle.InputChanged:Connect(function(input)
        if not dragging then return end
        if input.UserInputType == Enum.UserInputType.Touch
        or input.UserInputType == Enum.UserInputType.MouseMovement then
            local d = input.Position - startInput
            if math.abs(d.X) > threshold or math.abs(d.Y) > threshold then moved = true end
            if moved then
                target.Position = UDim2.new(
                    startPos.X.Scale, startPos.X.Offset + d.X,
                    startPos.Y.Scale, startPos.Y.Offset + d.Y)
            end
        end
    end)
    handle.InputEnded:Connect(function()
        if not dragging then return end
        dragging = false
        if onEnd then onEnd(moved) end
    end)
    return function() return moved end
end

-- 标题栏拖动面板（横屏限制在屏幕内；竖屏松手自动贴回底部）
dragify(titleBar, panel, function(moved)
    if not moved then return end
    local v = viewport()
    if isPortrait then
        P.panelX, P.panelY = 0, 0
        if applyLayout then applyLayout() end
        return
    end
    local pos = panel.AbsolutePosition
    local size = panel.AbsoluteSize
    local cx = math.clamp(pos.X + size.X / 2, size.X / 2 + 4, v.X - size.X / 2 - 4)
    local cy = math.clamp(pos.Y + size.Y / 2, size.Y / 2 + 4, v.Y - size.Y / 2 - 4)
    panel.Position = UDim2.new(0.5, math.floor(cx - v.X / 2), 0.5, math.floor(cy - v.Y / 2))
    P.panelX = math.floor(cx - v.X / 2)
    P.panelY = math.floor(cy - v.Y / 2)
    saveCfg()
end, 8)

-- 收起 / 展开
local function setCollapsed(on)
    collapsed = on
    body.Visible = not on
    panel.Size = on and UDim2.new(0, PANEL_W, 0, 46) or UDim2.new(0, PANEL_W, 0, PANEL_H)
    minBtn.Text = on and "+" or "–"
end

-- 屏幕自适应：竖屏底部抽屉 / 横屏居中卡片；旋转时重新排版
function applyLayout()
    local v = viewport()
    local w, h, portrait = calcPanel()
    PANEL_W, PANEL_H = w, h
    isPortrait = portrait

    if portrait then
        panel.AnchorPoint = Vector2.new(0.5, 1)
        panel.Position = UDim2.new(0.5, 0, 1, -12)
    else
        panel.AnchorPoint = Vector2.new(0.5, 0.5)
        if P.panelX ~= 0 or P.panelY ~= 0 then
            panel.Position = UDim2.new(0.5, P.panelX, 0.5, P.panelY)
        else
            panel.Position = UDim2.new(0.5, 0, 0.5, 0)
        end
    end
    panel.Size = UDim2.new(0, w, 0, collapsed and 46 or h)

    -- 横屏时把面板夹回屏幕内（AbsolutePosition 还没算出来时跳过，避免首帧误判）
    if not portrait then
        local ap, asz = panel.AbsolutePosition, panel.AbsoluteSize
        if (ap.X + ap.Y) > 1 and asz.X > 1 then
            local cx = math.clamp(ap.X + asz.X / 2, asz.X / 2 + 6, v.X - asz.X / 2 - 6)
            local cy = math.clamp(ap.Y + asz.Y / 2, asz.Y / 2 + 6, v.Y - asz.Y / 2 - 6)
            P.panelX = math.floor(cx - v.X / 2)
            P.panelY = math.floor(cy - v.Y / 2)
            panel.Position = UDim2.new(0.5, P.panelX, 0.5, P.panelY)
        end
    end

    -- 悬浮球夹回屏幕
    local bsz = ball.AbsoluteSize
    local bx = math.clamp(v.X + P.btnX, bsz.X / 2 + 8, v.X - bsz.X / 2 - 8)
    local by = math.clamp(v.Y + P.btnY, bsz.Y / 2 + 8, v.Y - bsz.Y / 2 - 8)
    P.btnX = math.floor(bx - v.X)
    P.btnY = math.floor(by - v.Y)
    ball.Position = UDim2.new(1, P.btnX, 1, P.btnY)
end

minBtn.MouseButton1Click:Connect(function() setCollapsed(not collapsed) end)
closeBtn.MouseButton1Click:Connect(function()
    panel.Visible = false
    ball.Text = "刀"
end)

-- 悬浮球：点击开合面板，拖动移动位置
local ballMoved = false
local ballDragAt = 0
dragify(ball, ball, function(moved)
    ballMoved = moved
    ballDragAt = os.clock()
    if moved then
        local v = viewport()
        local pos = ball.AbsolutePosition
        local size = ball.AbsoluteSize
        local cx = math.clamp(pos.X + size.X / 2, size.X / 2 + 4, v.X - size.X / 2 - 4)
        local cy = math.clamp(pos.Y + size.Y / 2, size.Y / 2 + 4, v.Y - size.Y / 2 - 4)
        local half = size.X / 2
        local snapLeft = math.floor(half + 12 - v.X)
        local snapRight = math.floor(-half - 12)
        local targetX = (cx < v.X / 2) and snapLeft or snapRight
        P.btnX = targetX
        P.btnY = math.floor(cy - v.Y)
        pcall(function()
            TweenService:Create(ball,
                TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
                {Position = UDim2.new(1, targetX, 1, P.btnY)}):Play()
        end)
        ball.Position = UDim2.new(1, targetX, 1, P.btnY)
        saveCfg()
    end
end, 16)
ball.MouseButton1Click:Connect(function()
    -- 拖动刚结束的点击不算点击
    if ballMoved or (os.clock() - ballDragAt < 0.25) then
        ballMoved = false
        return
    end
    panel.Visible = not panel.Visible
    ball.Text = panel.Visible and "收" or "刀"
    if panel.Visible then
        if applyLayout then pcall(applyLayout) end
        if currentTab == 2 then
            pcall(refreshPlayers)
            pcall(refreshPresets)
        end
    end
end)

-- ============================================================
-- 十一、后台线程
-- ============================================================
local conns = {}

local function track(c)
    conns[#conns + 1] = c
    return c
end

-- 主物理循环：车辆加速 + 飞行
track(RunService.Heartbeat:Connect(function(dt)
    if S.carBoost then pcall(carTick, dt) end
    if flying then pcall(flyTick, dt) end
end))

-- 自动铐人
task.spawn(function()
    while true do
        task.wait(0.2)
        if S.arrestAuto then
            local ok = pcall(tryArrest)
            if not ok then out("铐人出错") end
        end
    end
end)

-- 无后坐力扫描
task.spawn(function()
    while true do
        task.wait(0.4)
        if S.noRecoil then
            if os.clock() - recoilLastScan > 2.0 then
                recoilLastScan = os.clock()
                local total = 0
                for _, t in ipairs(tools()) do total = total + applyRecoilZero(t) end
                if total > 0 then out("清零 " .. total .. " 个后坐力字段") end
            end
        end
    end
end)

-- 信息刷新
task.spawn(function()
    while true do
        task.wait(0.5)
        if uiRefs.espInfo then
            uiRefs.espInfo.Text = string.format("标记 %d 人 · 间隔 %.1fs · 距离 %s",
                espCount, S.espInterval,
                (S.espRange <= 0) and "不限" or (math.floor(S.espRange) .. "m"))
        end
        if uiRefs.arrestInfo then
            uiRefs.arrestInfo.Text = string.format("铐人：%s · 尝试 %d 次 · 距离 %dm",
                S.arrestAuto and "自动" or "手动", arrestAttempts, math.floor(S.arrestDist))
        end
        if uiRefs.dot then
            local active = 0
            if S.esp then active = active + 1 end
            if S.speedLock then active = active + 1 end
            if S.noRecoil then active = active + 1 end
            if S.carBoost then active = active + 1 end
            if S.arrestAuto then active = active + 1 end
            uiRefs.dot.Text = active > 0 and (active .. " 项运行") or "待命"
            uiRefs.dot.TextColor3 = active > 0 and Color3.fromRGB(120, 220, 160) or C.sub
        end
        if panel.Visible and currentTab == 2 then pcall(refreshPlayers) end
    end
end)

-- 键盘
track(UIS.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.KeyCode == Enum.KeyCode.RightShift then
        panel.Visible = not panel.Visible
        ball.Text = panel.Visible and "收" or "刀"
    elseif input.KeyCode == Enum.KeyCode.H then
        pcall(tryArrest)
    end
end))

-- 玩家离开清理
track(Players.PlayerRemoving:Connect(function(p) clearESP(p) end))

-- 屏幕旋转 / 分辨率变化：重排面板
pcall(function()
    local cam = workspace.CurrentCamera
    if cam then
        track(cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
            pcall(applyLayout)
        end))
    end
end)

pcall(function() workspace.FallenPartsDestroyHeight = -5000 end)

-- ============================================================
-- 十二、卸载 & 启动
-- ============================================================
_G.__gen4HubCleanup = function()
    for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    conns = {}
    S.esp = false
    espThread = nil
    for plr in pairs(tracked) do pcall(function() clearESP(plr) end) end
    if speedConn then pcall(function() speedConn:Disconnect() end) end
    speedConn = nil
    pcall(clearCarRig)
    pcall(stopFlight)
    pcall(restoreRecoil)
    saveCfg()
    if gui then pcall(function() gui:Destroy() end) end
    _G.__gen4HubCleanup = nil
end

-- 开场提示
task.spawn(function()
    pcall(function()
        local toast = el("ScreenGui", {
            Name = "__GEN4_POPUP",
            ResetOnSpawn = false,
            IgnoreGuiInset = true,
            DisplayOrder = 2100,
        }, PG)
        local frame = el("Frame", {
            Size = UDim2.new(0, 250, 0, 74),
            AnchorPoint = Vector2.new(0.5, 0),
            Position = UDim2.new(0.5, 0, 0, 40),
            BackgroundColor3 = C.bg,
            BackgroundTransparency = 0.08,
            BorderSizePixel = 0,
        }, toast)
        deco(frame, 14, Color3.fromRGB(90, 170, 255), 2)
        el("TextLabel", {
            Size = UDim2.new(1, 0, 0, 40),
            Position = UDim2.new(0, 0, 0, 8),
            BackgroundTransparency = 1,
            Font = Enum.Font.GothamBold,
            TextSize = 19,
            TextColor3 = Color3.fromRGB(210, 235, 255),
            Text = "GEN4 整合面板",
        }, frame)
        el("TextLabel", {
            Size = UDim2.new(1, 0, 0, 22),
            Position = UDim2.new(0, 0, 0, 46),
            BackgroundTransparency = 1,
            Font = Enum.Font.Gotham,
            TextSize = 12,
            TextColor3 = C.sub,
            Text = "点悬浮球展开 · 左右滑动切页",
        }, frame)

        task.delay(3, function()
            local info = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
            for _, d in ipairs(frame:GetDescendants()) do
                if d:IsA("TextLabel") then
                    pcall(function() TweenService:Create(d, info, {TextTransparency = 1}):Play() end)
                end
            end
            pcall(function()
                TweenService:Create(frame, info, {BackgroundTransparency = 1}):Play()
            end)
            task.wait(0.5)
            pcall(function() toast:Destroy() end)
        end)
    end)
end)

-- 首帧先排一次，等布局稳定后再排一次（防止 AbsolutePosition 尚未计算）
task.delay(0, function()
    pcall(applyLayout)
    task.wait(0.2)
    pcall(applyLayout)
end)

out("GEN4 HUB 已加载 · 6 个脚本已合并为 5 个分页")
out("悬浮球=开合面板  右Shift=开合  H=手动铐人")
