--------------------------------------------------------------------------------
--  Bullet Fire Logic Detector  (Roblox)
--  四层检测: ①子弹实例生成  ②远程发射调用参数  ③射线/命中判定  ④飞行轨迹采样
--
--  用法:
--    1) 全选粘进执行器 -> Execute
--    2) 运行时改配置:  getgenv().BD.CFG.visualize = false
--    3) 导出统计:      getgenv().BD.dump()
--    4) 停止:          getgenv().BD.stop()
--------------------------------------------------------------------------------

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")
local LocalPlayer       = Players.LocalPlayer

local ENV = (typeof(getgenv) == "function" and getgenv()) or _G

--------------------------------------------------------------------------------
-- 配置
--------------------------------------------------------------------------------
local CFG = {
    enabled     = true,   -- 总开关
    visualize   = true,   -- 用 Drawing 画速度方向线 + 速度标签
    hud         = true,   -- 左上角统计面板
    logRemotes  = true,   -- 打印远程发射调用
    logRaycast  = true,   -- 打印射线检测(命中判定逻辑)
    verbose     = false,  -- true = 不按关键字过滤,全部打印
    maxTrack    = 48,     -- 同时采样上限
    visLifetime = 1.2,    -- 轨迹线残留秒数
    trackTimeout= 6,      -- 单颗子弹最长采样秒数
}

--------------------------------------------------------------------------------
-- 关键字表
--------------------------------------------------------------------------------
local BULLET_KEYS = {
    "bullet", "projectile", "proj", "shot", "rocket", "arrow", "grenade",
    "missile", "dart", "kunai", "shuriken", "pellet", "tracer", "fireball",
    "orb", "beam", "needle", "bomb", "cannon", "blast", "spell", "kunai",
}

local FIRE_KEYS = {
    "shoot", "fire", "bullet", "proj", "shot", "damage", "hit", "attack",
    "weapon", "gun", "kunai", "throw", "arrow", "spell", "skill", "cast",
}

local RAY_METHODS = {
    ["Raycast"]                    = true,
    ["FindPartOnRay"]              = true,
    ["FindPartOnRayWithIgnoreList"]= true,
    ["FindPartOnRayWithWhitelist"] = true,
    ["Blockcast"]                  = true,
    ["Spherecast"]                 = true,
}

local FIRE_METHODS = {
    ["FireServer"]       = true,
    ["InvokeServer"]     = true,
}

--------------------------------------------------------------------------------
-- 工具函数
--------------------------------------------------------------------------------
local function fmtNum(n)
    return string.format("%.2f", n)
end

local function fmtVec(v)
    if typeof(v) ~= "Vector3" then return tostring(v) end
    return string.format("(%.1f, %.1f, %.1f)", v.X, v.Y, v.Z)
end

local function describe(v, depth)
    depth = depth or 0
    local t = typeof(v)
    if t == "Vector3" then
        return fmtVec(v)
    elseif t == "Vector2" then
        return string.format("V2(%.1f, %.1f)", v.X, v.Y)
    elseif t == "CFrame" then
        return "CFrame" .. fmtVec(v.Position)
    elseif t == "Instance" then
        return string.format("%s<%s>", v.Name, v.ClassName)
    elseif t == "Color3" then
        return string.format("Color3(%d,%d,%d)", math.floor(v.R * 255), math.floor(v.G * 255), math.floor(v.B * 255))
    elseif t == "table" and depth < 2 then
        local out = {}
        local n = 0
        for k, val in pairs(v) do
            n = n + 1
            if n > 8 then
                out[#out + 1] = "..."
                break
            end
            out[#out + 1] = tostring(k) .. "=" .. describe(val, depth + 1)
        end
        return "{" .. table.concat(out, ", ") .. "}"
    end
    return tostring(v)
end

local function nameMatches(name, keys)
    local n = string.lower(tostring(name or ""))
    for i = 1, #keys do
        if string.find(n, keys[i], 1, true) then
            return keys[i]
        end
    end
    return nil
end

local function dlog(tag, msg)
    print(string.format("[BD][%s] %s", tag, msg))
end

local function safeCall(fn, ...)
    local ok, res = pcall(fn, ...)
    if ok then return res end
    return nil
end

--------------------------------------------------------------------------------
-- 状态
--------------------------------------------------------------------------------
local BD = {
    CFG     = CFG,
    stats   = { spawned = 0, fired = 0, remotes = 0, raycasts = 0, finished = 0 },
    events  = {},
    tracked = {},
}
ENV.BD = BD

local function record(line)
    BD.events[#BD.events + 1] = line
    if #BD.events > 10 then
        table.remove(BD.events, 1)
    end
end

--------------------------------------------------------------------------------
-- Drawing 兼容探测(执行器不支持就自动降级为只打印)
--------------------------------------------------------------------------------
local DRAWING = nil
do
    local ok, d = pcall(function() return Drawing end)
    if ok and d ~= nil then
        local usable = pcall(function()
            local l = d.new("Line")
            l:Remove()
        end)
        if usable then DRAWING = d end
    end
end

--------------------------------------------------------------------------------
-- HUD
--------------------------------------------------------------------------------
local HUD = nil

local function buildHud()
    if HUD or not CFG.hud then return end
    local ok, res = pcall(function()
        local gui = Instance.new("ScreenGui")
        gui.Name = "BulletDetectorHUD"
        gui.ResetOnSpawn = false
        gui.IgnoreGuiInset = true
        gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

        local frame = Instance.new("Frame")
        frame.Name = "Panel"
        frame.Size = UDim2.fromOffset(280, 158)
        frame.Position = UDim2.fromOffset(12, 12)
        frame.BackgroundColor3 = Color3.fromRGB(14, 14, 18)
        frame.BackgroundTransparency = 0.2
        frame.BorderSizePixel = 0
        frame.Active = true
        frame.Parent = gui

        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 6)
        corner.Parent = frame

        local stroke = Instance.new("UIStroke")
        stroke.Color = Color3.fromRGB(255, 170, 40)
        stroke.Thickness = 1
        stroke.Transparency = 0.45
        stroke.Parent = frame

        local title = Instance.new("TextLabel")
        title.Size = UDim2.new(1, -16, 0, 16)
        title.Position = UDim2.fromOffset(8, 5)
        title.BackgroundTransparency = 1
        title.Font = Enum.Font.Code
        title.TextSize = 13
        title.TextXAlignment = Enum.TextXAlignment.Left
        title.TextColor3 = Color3.fromRGB(255, 190, 60)
        title.Text = "BULLET DETECTOR"
        title.Parent = frame

        local body = Instance.new("TextLabel")
        body.Size = UDim2.new(1, -16, 1, -28)
        body.Position = UDim2.fromOffset(8, 23)
        body.BackgroundTransparency = 1
        body.Font = Enum.Font.Code
        body.TextSize = 12
        body.TextXAlignment = Enum.TextXAlignment.Left
        body.TextYAlignment = Enum.TextYAlignment.Top
        body.TextColor3 = Color3.fromRGB(222, 222, 228)
        body.Text = ""
        body.Parent = frame

        local parent = LocalPlayer:FindFirstChild("PlayerGui")
        if not parent then
            local okc, cg = pcall(function() return game:GetService("CoreGui") end)
            if okc then parent = cg end
        end
        if parent then gui.Parent = parent end

        return { gui = gui, body = body }
    end)
    if ok then HUD = res end
end

local function refreshHud()
    if not HUD then return end
    local lines = {}
    lines[#lines + 1] = string.format("弹体生成 %d  发射调用 %d", BD.stats.spawned, BD.stats.fired)
    lines[#lines + 1] = string.format("远程命中 %d  射线检测 %d", BD.stats.remotes, BD.stats.raycasts)
    lines[#lines + 1] = string.format("采样中 %d    已结算 %d", #BD.tracked, BD.stats.finished)
    lines[#lines + 1] = "----------------------"
    local startIdx = math.max(1, #BD.events - 4)
    for i = #BD.events, startIdx, -1 do
        lines[#lines + 1] = BD.events[i]
    end
    HUD.body.Text = table.concat(lines, "\n")
end

--------------------------------------------------------------------------------
-- 实例取值助手
--------------------------------------------------------------------------------
local function getPos(inst)
    if inst:IsA("BasePart") then
        return inst.Position
    elseif inst:IsA("Model") then
        local ok, cf = pcall(function() return inst:GetPivot() end)
        if ok and cf then return cf.Position end
    end
    return nil
end

local function getVel(inst)
    if inst:IsA("BasePart") then
        return inst.AssemblyLinearVelocity
    elseif inst:IsA("Model") then
        local part = inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart")
        if part then return part.AssemblyLinearVelocity end
    end
    return Vector3.new(0, 0, 0)
end

--------------------------------------------------------------------------------
-- 子弹判定
--------------------------------------------------------------------------------
local function looksLikeBullet(inst)
    local isPart  = inst:IsA("BasePart")
    local isModel = inst:IsA("Model")
    local isFx    = inst:IsA("Beam") or inst:IsA("Trail") or inst:IsA("ParticleEmitter")
    if not (isPart or isModel or isFx) then return false end

    local ch = LocalPlayer.Character
    if ch and inst:IsDescendantOf(ch) then return false end

    local hit = nameMatches(inst.Name, BULLET_KEYS)
    if hit then return true, "name:" .. hit end

    if isPart then
        if inst.Anchored then return false end
        local s = inst.Size
        local biggest  = math.max(s.X, s.Y, s.Z)
        local smallest = math.min(s.X, s.Y, s.Z)
        local v = inst.AssemblyLinearVelocity.Magnitude
        if biggest <= 4 and smallest <= 1.5 and v >= 30 then
            return true, "size+vel"
        end
        if v >= 150 then
            return true, "fast"
        end
    end
    return false
end

--------------------------------------------------------------------------------
-- 轨迹可视化对象
--------------------------------------------------------------------------------
local function visCreate()
    if not CFG.visualize or not DRAWING then return nil end
    local ok, obj = pcall(function()
        local line = DRAWING.new("Line")
        line.Thickness = 1.6
        line.Transparency = 0.35
        line.Color = Color3.fromRGB(255, 196, 0)

        local dot = DRAWING.new("Circle")
        dot.Thickness = 1
        dot.NumSides = 10
        dot.Radius = 3.5
        dot.Filled = true
        dot.Color = Color3.fromRGB(255, 90, 60)

        local txt = DRAWING.new("Text")
        txt.Size = 13
        txt.Center = false
        txt.Outline = true
        txt.Color = Color3.fromRGB(255, 226, 120)

        return { line = line, dot = dot, txt = txt }
    end)
    if ok then return obj end
    return nil
end

local function visDestroy(obj)
    if not obj then return end
    pcall(function()
        obj.line:Remove()
        obj.dot:Remove()
        obj.txt:Remove()
    end)
end

local function visUpdate(entry, pos, speed)
    local obj = entry.vis
    if not obj then return end
    local dir = entry.dir
    if dir.Magnitude < 0.01 then
        obj.line.Visible = false
        obj.dot.Visible = false
        obj.txt.Visible = false
        return
    end
    pcall(function()
        obj.line.From = pos
        obj.line.To = pos + dir * 9
        obj.line.Visible = true
        obj.line.Color = entry.incoming and Color3.fromRGB(255, 70, 70) or Color3.fromRGB(255, 196, 0)

        local cam = Workspace.CurrentCamera
        if cam then
            local sp, onScreen = cam:WorldToViewportPoint(pos)
            obj.dot.Position = Vector2.new(sp.X, sp.Y)
            obj.dot.Visible = onScreen
            obj.txt.Position = Vector2.new(sp.X + 10, sp.Y - 8)
            obj.txt.Text = string.format("%s  %.0f", entry.label, speed)
            obj.txt.Visible = onScreen
            obj.txt.Color = entry.incoming and Color3.fromRGB(255, 110, 110) or Color3.fromRGB(255, 226, 120)
        end
    end)
end

--------------------------------------------------------------------------------
-- 追踪核心
--------------------------------------------------------------------------------
local tracked = BD.tracked
local seq = 0

local function removeEntry(entry)
    for i = #tracked, 1, -1 do
        if tracked[i] == entry then
            table.remove(tracked, i)
            break
        end
    end
end

local function finishEntry(entry, reason)
    if entry.done then return end
    entry.done = true
    visDestroy(entry.vis)
    removeEntry(entry)
    BD.stats.finished = BD.stats.finished + 1

    local flight = os.clock() - entry.t0
    local line = string.format(
        "%s %s | 初速 %.0f 峰值 %.0f | 方向 %s | 飞行 %ss 路径 %.0f%s",
        entry.label,
        string.format("(%s)", reason),
        entry.speed0,
        entry.speedMax,
        fmtVec(entry.dir),
        fmtNum(flight),
        entry.travel,
        entry.incoming and "  <<朝你飞来" or ""
    )
    dlog("HIT", line)
end

local function updateIncoming(entry, pos)
    local ch = LocalPlayer.Character
    local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
    if not hrp or entry.dir.Magnitude < 0.01 then return end
    local toMe = hrp.Position - pos
    local dist = toMe.Magnitude
    if dist < 2 or dist > 500 then
        entry.incoming = false
        return
    end
    entry.incoming = (toMe.Unit:Dot(entry.dir) > 0.93)
end

local function trackPart(inst, source)
    if not CFG.enabled then return end
    if typeof(inst) ~= "Instance" then return end
    if #tracked >= CFG.maxTrack then return end
    if not inst:IsDescendantOf(Workspace) then return end

    local matched, kind = looksLikeBullet(inst)
    if not matched then return end

    seq = seq + 1
    local pos = getPos(inst)
    local vel = getVel(inst)
    local entry = {
        id      = seq,
        part    = inst,
        t0      = os.clock(),
        lastPos = pos,
        travel  = 0,
        speed0  = vel.Magnitude >= 5 and vel.Magnitude or 0,
        speedMax= vel.Magnitude,
        dir     = vel.Magnitude > 1 and vel.Unit or Vector3.new(0, 0, 0),
        incoming= false,
        done    = false,
        label   = string.format("#%d %s", seq, string.sub(tostring(inst.Name), 1, 14)),
        vis     = visCreate(),
    }
    tracked[#tracked + 1] = entry

    BD.stats.spawned = BD.stats.spawned + 1
    record(string.format("#%d %s [%s]", seq, string.sub(inst.Name, 1, 14), kind))
    local parentName = inst.Parent and inst.Parent:GetFullName() or "nil"
    dlog("SPAWN", string.format("#%d %s<%s> 来源=%s 父级=%s 位置=%s 初速=%.0f 判定=%s",
        seq, inst.Name, inst.ClassName, source, parentName,
        pos and fmtVec(pos) or "nil", entry.speed0, kind))

    return entry
end

--------------------------------------------------------------------------------
-- ① 实例生成: workspace 内新增对象
--------------------------------------------------------------------------------
Workspace.DescendantAdded:Connect(function(inst)
    if not CFG.enabled then return end
    task.defer(function()
        if inst and inst.Parent then
            trackPart(inst, "DescendantAdded")
        end
    end)
end)

--------------------------------------------------------------------------------
-- ② 远程发射参数 / ③ 射线命中判定  (__namecall hook)
--------------------------------------------------------------------------------
local function onRemoteCall(self, method, ...)
    if not CFG.logRemotes then return end
    if typeof(self) ~= "Instance" then return end

    local isRemote = safeCall(function()
        return self:IsA("RemoteEvent")
            or self:IsA("RemoteFunction")
            or self:IsA("UnreliableRemoteEvent")
            or self:IsA("BindableEvent")
    end)
    if not isRemote then return end

    local isFire = nameMatches(self.Name, FIRE_KEYS)
    if not (isFire or CFG.verbose) then return end

    BD.stats.remotes = BD.stats.remotes + 1

    local args = table.pack(...)
    local pieces = {}
    for i = 1, math.min(args.n, 8) do
        pieces[#pieces + 1] = describe(args[i])
    end
    dlog("REMOTE", string.format("%s:%s(%s)", tostring(self.Name), method, table.concat(pieces, ", ")))
    record("R " .. string.sub(self.Name, 1, 16))

    for i = 1, args.n do
        local v = args[i]
        if typeof(v) == "Vector3" and v.Magnitude > 30 then
            BD.stats.fired = BD.stats.fired + 1
            dlog("SHOT", string.format("速度/方向向量 %s 模长 %.0f", fmtVec(v), v.Magnitude))
        elseif typeof(v) == "CFrame" then
            dlog("SHOT", "发射起点 CFrame " .. fmtVec(v.Position))
        elseif typeof(v) == "Instance" and v:IsA("BasePart") then
            dlog("SHOT", "发射部件 " .. v.Name .. " 位置 " .. fmtVec(v.Position))
        end
    end
end

local function onRayCall(self, method, ...)
    if not CFG.logRaycast then return end
    local args = table.pack(...)
    local origin, dir
    if typeof(args[1]) == "Vector3" then origin = args[1] end
    if typeof(args[2]) == "Vector3" then dir = args[2] end
    if not origin or not dir then return end

    BD.stats.raycasts = BD.stats.raycasts + 1
    if not CFG.verbose and dir.Magnitude < 40 then return end

    dlog("RAY", string.format("%s origin=%s dir=%s len=%.0f",
        method, fmtVec(origin), fmtVec(dir), dir.Magnitude))
end

local function installNamecallHook()
    local ok, err = pcall(function()
        if typeof(hookmetamethod) ~= "function" then
            error("hookmetamethod unavailable")
        end
        if typeof(getnamecallmethod) ~= "function" then
            error("getnamecallmethod unavailable")
        end

        local old
        local wrapper = function(self, ...)
            local method = getnamecallmethod()
            if method == "Instance.new" then
                local ret = old(self, ...)
                if CFG.enabled then
                    task.defer(function()
                        if typeof(ret) == "Instance" and ret.Parent then
                            trackPart(ret, "Instance.new")
                        end
                    end)
                end
                return ret
            end

            if CFG.enabled and method then
                if FIRE_METHODS[method] then
                    pcall(onRemoteCall, self, method, ...)
                elseif RAY_METHODS[method] then
                    pcall(onRayCall, self, method, ...)
                end
            end
            return old(self, ...)
        end

        if typeof(newcclosure) == "function" then
            wrapper = newcclosure(wrapper)
        end

        old = hookmetamethod(game, "__namecall", wrapper)
    end)

    if not ok then
        -- 兜底: 直接改元表
        local ok2 = pcall(function()
            local mt = getrawmetatable(game)
            local oldNamecall = mt.__namecall
            setreadonly(mt, false)
            mt.__namecall = function(self, ...)
                local method = getnamecallmethod and getnamecallmethod() or nil
                if CFG.enabled and method then
                    if FIRE_METHODS[method] then
                        pcall(onRemoteCall, self, method, ...)
                    elseif RAY_METHODS[method] then
                        pcall(onRayCall, self, method, ...)
                    end
                end
                return oldNamecall(self, ...)
            end
            setreadonly(mt, true)
        end)
        if not ok2 then
            dlog("WARN", "本执行器不支持 namecall hook,已降级为仅检测实例生成")
        end
    end
end

--------------------------------------------------------------------------------
-- ④ 飞行轨迹采样
--------------------------------------------------------------------------------
RunService.Heartbeat:Connect(function()
    if not CFG.enabled then return end
    local now = os.clock()

    for i = #tracked, 1, -1 do
        local entry = tracked[i]
        local part = entry.part

        if not part or not part.Parent then
            finishEntry(entry, "消失")
        elseif now - entry.t0 > CFG.trackTimeout then
            finishEntry(entry, "超时")
        else
            local pos = getPos(part)
            local vel = getVel(part)
            local speed = vel.Magnitude

            if pos then
                if entry.lastPos then
                    entry.travel = entry.travel + (pos - entry.lastPos).Magnitude
                end
                entry.lastPos = pos

                if entry.speed0 < 5 and speed > 5 then
                    entry.speed0 = speed
                end
                if entry.dir.Magnitude < 0.01 and speed > 1 then
                    entry.dir = vel.Unit
                end
                if speed > entry.speedMax then
                    entry.speedMax = speed
                end

                updateIncoming(entry, pos)
                visUpdate(entry, pos, speed)
            end
        end
    end
end)

--------------------------------------------------------------------------------
-- HUD 刷新
--------------------------------------------------------------------------------
task.spawn(function()
    buildHud()
    while true do
        task.wait(0.25)
        refreshHud()
    end
end)

--------------------------------------------------------------------------------
-- 对外接口
--------------------------------------------------------------------------------
BD.dump = function()
    local out = {}
    out[#out + 1] = "===== Bullet Fire Logic Dump ====="
    out[#out + 1] = string.format("弹体生成   : %d", BD.stats.spawned)
    out[#out + 1] = string.format("发射调用   : %d", BD.stats.fired)
    out[#out + 1] = string.format("远程命中   : %d", BD.stats.remotes)
    out[#out + 1] = string.format("射线检测   : %d", BD.stats.raycasts)
    out[#out + 1] = string.format("已结算弹体 : %d", BD.stats.finished)
    out[#out + 1] = "--- 采样中 ---"
    for i = 1, #tracked do
        local e = tracked[i]
        out[#out + 1] = string.format("%s 初速%.0f 峰值%.0f 方向%s 路径%.0f%s",
            e.label, e.speed0, e.speedMax, fmtVec(e.dir), e.travel,
            e.incoming and " 朝你飞来" or "")
    end
    local text = table.concat(out, "\n")
    print(text)
    if typeof(setclipboard) == "function" then
        pcall(setclipboard, text)
        dlog("DUMP", "统计已复制到剪贴板")
    end
    return text
end

BD.stop = function()
    CFG.enabled = false
    for i = #tracked, 1, -1 do
        visDestroy(tracked[i].vis)
    end
    for i = #tracked, 1, -1 do
        table.remove(tracked, i)
    end
    if HUD then
        pcall(function() HUD.gui:Destroy() end)
        HUD = nil
    end
    dlog("STOP", "已停止检测")
end

BD.start = function()
    CFG.enabled = true
    dlog("START", "已恢复检测")
end

--------------------------------------------------------------------------------
-- 启动
--------------------------------------------------------------------------------
installNamecallHook()

task.spawn(function()
    task.wait(0.4)
    buildHud()
end)

dlog("READY", "子弹逻辑检测已启动")
dlog("READY", string.format("可视化=%s 远程日志=%s 射线日志=%s",
    tostring(CFG.visualize and DRAWING ~= nil), tostring(CFG.logRemotes), tostring(CFG.logRaycast)))
