--[[=====================================================================
    ZAKA  ·  杀戒光环   KILL AURA — REMOTE PACKET EDITION   v2.0
    ---------------------------------------------------------------
    手机端适配版(PC 同样能用,自动判断运行环境)

    原理(没变):
      1) 钩住 game 元表的 __namecall,监听「本机攻击动作」发生后马上
         发往服务器的 Remote 包(FireServer / InvokeServer)
      2) 把这个包连它当时带的全部参数一起存成"模板"
      3) 光环循环里,把模板参数中所有指向"自己"的引用
         (Character / Humanoid / HumanoidRootPart / LocalPlayer)
         替换成射程内的敌人,再原样重发
      4) 服务端走的还是它自己的正常攻击逻辑 → 判定命中

    v2.0 手机端改动:
      · 触摸 UI 重做:按钮 40~46px、可滚动、可收起
      · 悬浮球:单击开关光环,长按收起/展开面板(手机没键盘)
      · 学习模式改成「限时收集 + 打分统一挑」,手机上更准
      · 手机端取消「触摸泛打点」(拖屏幕会灌垃圾包进池子)
      · 无钩子兜底:「扫描包列表」手动选攻击包
      · 低配自动降级:光环段数减半、刷新降频

    使用(手机):
      1) 注入执行器 → 左上角出现面板,右侧出现悬浮球
      2) 点面板上的「学习攻击包(12秒)」
      3) 立刻去点游戏里的攻击键 / 挥一刀
      4) 等 12 秒,状态栏显示「已学习攻击包: XXX」就成了
      5) 点悬浮球开关光环(或点面板上的大开关)

    使用(PC):
      同上,另外 RightShift 可以直接开关光环
=====================================================================]]

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInput  = game:GetService("UserInputService")

local LP     = Players.LocalPlayer
local unpack = table.unpack or unpack
local tn     = (type(typeof) == "function") and typeof or type
local clk    = tick
local cos, sin, rad, random, pi2 = math.cos, math.sin, math.rad, math.random, math.pi * 2

----------------------------------------------------------------------
-- 环境判断
----------------------------------------------------------------------
local IS_TOUCH  = UserInput.TouchEnabled == true
-- 只要屏幕能触摸,一律按手机端给适配(就算插了蓝牙键盘,按钮也得好点)
local IS_MOBILE = IS_TOUCH

----------------------------------------------------------------------
-- 配置
----------------------------------------------------------------------
local CFG = {
    Enabled   = true,
    Range     = IS_MOBILE and 22 or 26,   -- 光环半径(格)
    Delay     = IS_MOBILE and 0.12 or 0.09,
    Jitter    = 0.04,
    TeamCheck = true,                     -- 不打队友
    AimShift  = true,
    Visual    = true,
    Lunge     = false,
    LowFX     = IS_MOBILE,                -- 低配模式(自动降段数/降频)
    Color     = Color3.fromRGB(0, 205, 255),
    Keybind   = Enum.KeyCode.RightShift,
    LearnSecs = 12,                       -- 手机手慢,给够时间
    LearnWindow = IS_MOBILE and 0.9 or 0.5,
    RingSeg   = IS_MOBILE and 16 or 32,   -- 光环段数
}

local ST = {
    pool      = {},
    primary   = nil,
    sending   = false,
    learnUntil= nil,
    learnId   = 0,
    lastInput = 0,
    ring      = {},
    aura      = nil,
    hl        = {},
    hookOK    = false,
    status    = "等待学习攻击包…",
}

-- 攻击包常见命名特征
local ATK_WORDS = {"attack","hit","damage","dmg","combat","m1","slash","punch","skill","ability","strike","swing","shoot","fire","weapon","melee","click"}
local BAD_WORDS = {"move","walk","jump","chat","ping","setting","anim","equip","reload","camera","tool","shop","vote","buy","sell","trade","friend","party","join","leave","spawn","respawn","music","sound","voice"}

----------------------------------------------------------------------
-- 基础工具
----------------------------------------------------------------------
local function root()
    local c = LP.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end

local function hum()
    local c = LP.Character
    return c and c:FindFirstChildOfClass("Humanoid")
end

local function isAlive(p)
    local c = p.Character
    if not c then return false end
    local h = c:FindFirstChildOfClass("Humanoid")
    return h ~= nil and h.Health > 0
end

local function refsLocal(args)
    local c = LP.Character
    for i = 1, #args do
        local v = args[i]
        if tn(v) == "Instance" then
            if v == LP or v == c or (c and v:IsDescendantOf(c)) then return true end
        elseif tn(v) == "table" then
            for _, vv in pairs(v) do
                if tn(vv) == "Instance" then
                    if vv == LP or vv == c or (c and vv:IsDescendantOf(c)) then return true end
                end
            end
        end
    end
    return false
end

local function getTargets()
    local out = {}
    local myRoot = root()
    if not myRoot then return out end
    local myPos = myRoot.Position
    local myTeam = LP.Team

    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LP and isAlive(p) then
            local pc = p.Character
            local pr = pc and pc:FindFirstChild("HumanoidRootPart")
            local ph = pc and pc:FindFirstChildOfClass("Humanoid")
            if pr and ph then
                local blocked = CFG.TeamCheck and myTeam ~= nil and p.Team == myTeam
                if not blocked then
                    local d = (pr.Position - myPos).Magnitude
                    if d <= CFG.Range then
                        out[#out + 1] = { plr = p, char = pc, hum = ph, root = pr, dist = d }
                    end
                end
            end
        end
    end
    table.sort(out, function(a, b) return a.dist < b.dist end)
    return out
end

local function vpSize()
    local cam = workspace.CurrentCamera
    if cam then return cam.ViewportSize end
    return Vector2.new(1280, 720)
end

----------------------------------------------------------------------
-- UI 状态
----------------------------------------------------------------------
local ui = {}

local function setStatus(s)
    ST.status = s
    if ui.status then ui.status.Text = s end
end

local function refreshUI()
    if ui.info then
        if ST.primary then
            ui.info.Text = string.format("攻击包: %s   (%d 次)", ST.primary.remote.Name, ST.primary.count)
            ui.info.TextColor3 = Color3.fromRGB(0, 220, 130)
        else
            ui.info.Text = ST.hookOK and "攻击包: 未捕获" or "钩子不可用 · 去『扫描包列表』手动选"
            ui.info.TextColor3 = Color3.fromRGB(255, 180, 60)
        end
    end
    if ui.bigBtn then
        if CFG.Enabled then
            ui.bigBtn.Text = "● 光环运行中 · 点此关闭"
            ui.bigBtn.BackgroundColor3 = Color3.fromRGB(0, 120, 88)
        else
            ui.bigBtn.Text = "○ 光环已停止 · 点此开启"
            ui.bigBtn.BackgroundColor3 = Color3.fromRGB(44, 50, 62)
        end
    end
    if ui.fab then
        ui.fab.BackgroundColor3 = CFG.Enabled and Color3.fromRGB(0, 120, 88) or Color3.fromRGB(34, 38, 48)
        if ui.fabTxt then ui.fabTxt.Text = CFG.Enabled and "ON" or "OFF" end
        if ui.fabStroke then
            ui.fabStroke.Color = CFG.Enabled and CFG.Color or Color3.fromRGB(90, 96, 108)
        end
    end
end

----------------------------------------------------------------------
-- 攻击包学习
----------------------------------------------------------------------
local function pickPrimary()
    local best, bestS = nil, -1e9
    for _, e in pairs(ST.pool) do
        local s = e.score + (e.learnHit and 8 or 0)
        if s > bestS then best, bestS = e, s end
    end
    ST.primary = best
end

local function onRemote(self, method, args)
    if tn(self) ~= "Instance" then return end
    local okIs = pcall(function() return self:IsA("RemoteEvent") or self:IsA("RemoteFunction") end)
    if not okIs then return end

    local learning = ST.learnUntil ~= nil and clk() <= ST.learnUntil
    if not learning and (clk() - ST.lastInput) > CFG.LearnWindow then return end

    local e = ST.pool[self]
    if not e then
        e = { remote = self, method = method, args = args, count = 0, score = 0 }
        ST.pool[self] = e
    end
    e.count  = e.count + 1
    e.args   = args
    e.method = method

    if learning then
        e.learnHit = true
        e.score = e.score + 3
    end
    if refsLocal(args) then e.score = e.score + 3 end
    if #args > 0 then e.score = e.score + 1 end

    local n = string.lower(self.Name)
    for _, w in ipairs(ATK_WORDS) do
        if string.find(n, w, 1, true) then e.score = e.score + 4 break end
    end
    for _, w in ipairs(BAD_WORDS) do
        if string.find(n, w, 1, true) then e.score = e.score - 6 break end
    end

    if learning then
        refreshUI()
        return
    end
    pickPrimary()
    refreshUI()
end

-- 学习:限时收集,结束时统一挑最高分(手机上比"第一个发包的"准得多)
local function startLearn(secs)
    secs = secs or CFG.LearnSecs
    local id = (ST.learnId or 0) + 1
    ST.learnId   = id
    ST.learnUntil= clk() + secs
    ST.lastInput = clk()
    for _, e in pairs(ST.pool) do e.learnHit = nil end
    setStatus(string.format("学习中(%d秒):去点游戏里的攻击键 / 挥一刀…", secs))

    task.spawn(function()
        while ST.learnId == id and clk() < ST.learnUntil do task.wait(0.2) end
        if ST.learnId ~= id then return end
        ST.learnUntil = nil
        pickPrimary()
        if ST.primary and ST.primary.learnHit then
            setStatus("已学习攻击包: " .. ST.primary.remote.Name)
        elseif ST.primary then
            setStatus("抓到「" .. ST.primary.remote.Name .. "」,拿不准就点『重新学习』")
        else
            setStatus("没抓到,再来一次(点『重新学习』)")
        end
        refreshUI()
    end)
end

-- 攻击输入打点(PC 鼠标 / 手柄 / 工具激活)
-- 手机端故意不认 Touch:拖屏幕会不停触发,把垃圾包灌进池子
local function markAttack()
    ST.lastInput = clk()
end

UserInput.InputBegan:Connect(function(input, processed)
    if processed then return end
    local t = input.UserInputType
    if t == Enum.UserInputType.MouseButton1
    or t == Enum.UserInputType.Gamepad1
    or t == Enum.UserInputType.Gamepad2
    or (t == Enum.UserInputType.Keyboard and not IS_MOBILE) then
        markAttack()
    end
end)

----------------------------------------------------------------------
-- 钩子
----------------------------------------------------------------------
local function installHook()
    local gnm = getnamecallmethod
    if not gnm then return false, "这个执行器没有 getnamecallmethod" end
    local mt = getrawmetatable and getrawmetatable(game)
    if not mt then return false, "这个执行器的元表被锁了" end

    local cc  = checkcaller or function() return false end
    local ncc = newcclosure or function(f) return f end

    local ok, err = pcall(function()
        if setreadonly then setreadonly(mt, false) end
        local old = mt.__namecall

        mt.__namecall = ncc(function(self, ...)
            local method = gnm()
            if not cc() then
                if method == "Activate" and tn(self) == "Instance" and self:IsA("Tool") then
                    markAttack()
                elseif (method == "FireServer" or method == "InvokeServer") and not ST.sending then
                    local a = {...}
                    pcall(onRemote, self, method, a)
                end
            end
            return old(self, ...)
        end)

        if setreadonly then setreadonly(mt, true) end
    end)

    if not ok then return false, tostring(err) end
    return true
end

----------------------------------------------------------------------
-- 参数重写:把"自己"换成目标
----------------------------------------------------------------------
local function retarget(v, t)
    local myChar = LP.Character
    if not myChar then return v end
    local k = tn(v)

    if k == "Instance" then
        if v == myChar then return t.char end
        if v == LP then return t.plr end
        if v:IsDescendantOf(myChar) then
            local alt = t.char:FindFirstChild(v.Name, true)
            if alt then return alt end
        end
        return v

    elseif k == "Vector3" then
        if CFG.AimShift and t.root then
            local myRoot = myChar:FindFirstChild("HumanoidRootPart")
            if myRoot then return v + (t.root.Position - myRoot.Position) end
        end
        return v

    elseif k == "CFrame" then
        if CFG.AimShift and t.root then
            return CFrame.new(t.root.Position) * (v - v.Position)
        end
        return v

    elseif k == "table" then
        local out = {}
        for kk, vv in pairs(v) do out[kk] = retarget(vv, t) end
        return out
    end

    return v
end

----------------------------------------------------------------------
-- 出包
----------------------------------------------------------------------
local function sendAttack(t)
    local e = ST.primary
    if not e then return end
    if not e.remote or not e.remote.Parent then
        ST.primary = nil
        setStatus("那个包失效了(换了地图?),点『重新学习』")
        return
    end

    local args = {}
    for i = 1, #e.args do args[i] = retarget(e.args[i], t) end

    ST.sending = true
    local ok = pcall(function()
        if e.method == "InvokeServer" then
            if #args > 0 then e.remote:InvokeServer(unpack(args)) else e.remote:InvokeServer() end
        else
            if #args > 0 then e.remote:FireServer(unpack(args)) else e.remote:FireServer() end
        end
    end)
    ST.sending = false

    if not ok then
        setStatus("出包失败,点『重新学习』再挥一刀")
        ST.primary = nil
        refreshUI()
    end
end

-- 突进:服务端自算距离的游戏用
local function lunge(t)
    local r = root()
    if not r or not t.root then return end
    local d = t.root.Position - r.Position
    if d.Magnitude < 0.1 then return end
    pcall(function()
        r.CFrame = CFrame.new(t.root.Position - d.Unit * 2.5 + Vector3.new(0, 1, 0), t.root.Position)
        r.AssemblyLinearVelocity = Vector3.zero
    end)
end

----------------------------------------------------------------------
-- 光环视觉
----------------------------------------------------------------------
local function clearRing()
    for _, p in ipairs(ST.ring) do pcall(function() p:Destroy() end) end
    ST.ring = {}
    if ST.aura then pcall(function() ST.aura:Destroy() end) ST.aura = nil end
end

local function buildRing()
    clearRing()
    local folder = Instance.new("Folder")
    folder.Name = "ZakaAuraVisual"
    for i = 1, CFG.RingSeg do
        local p = Instance.new("Part")
        p.Anchored     = true
        p.CanCollide   = false
        p.CanQuery     = false
        p.CanTouch     = false
        p.CastShadow   = false
        p.Material     = Enum.Material.Neon
        p.Color        = CFG.Color
        p.Transparency = 1
        p.Size         = Vector3.new(1, 0.06, 0.4)
        p.Parent       = folder
        ST.ring[i] = p
    end
    folder.Parent = workspace
    ST.aura = folder
end

local function setAuraVisible(v)
    if v then
        if not ST.aura then buildRing() end
    else
        for _, p in ipairs(ST.ring) do p.Transparency = 1 end
    end
end

local function updateHighlights(list)
    local seen = {}
    for _, t in ipairs(list) do
        seen[t.plr] = true
        if not ST.hl[t.plr] and t.char then
            local h = Instance.new("Highlight")
            h.Name                = "ZakaAuraHL"
            h.FillColor           = CFG.Color
            h.OutlineColor        = CFG.Color
            h.FillTransparency    = 0.6
            h.OutlineTransparency = 0.2
            h.DepthMode           = Enum.HighlightDepthMode.AlwaysOnTop
            h.Parent              = t.char
            ST.hl[t.plr] = h
        end
    end
    for p, h in pairs(ST.hl) do
        if not seen[p] or not CFG.Enabled then
            pcall(function() h:Destroy() end)
            ST.hl[p] = nil
        end
    end
end

local ringTick = 0
RunService.RenderStepped:Connect(function()
    if not ST.aura then return end
    if CFG.LowFX then
        ringTick = ringTick + 1
        if ringTick % 2 == 0 then return end
    end

    local show = CFG.Visual and CFG.Enabled
    local myRoot = root()
    if not show or not myRoot then
        for _, p in ipairs(ST.ring) do p.Transparency = 1 end
        return
    end

    local center = myRoot.Position - Vector3.new(0, 2.6, 0)
    local radius = CFG.Range
    local spin   = clk() * 1.8
    local n      = #ST.ring
    local seg    = (pi2 * radius) / n * 1.3
    local col    = CFG.Color

    for i, p in ipairs(ST.ring) do
        local a   = (i / n) * pi2 + spin
        local pos = center + Vector3.new(cos(a) * radius, 0, sin(a) * radius)
        p.Size         = Vector3.new(seg, 0.06, 0.4)
        p.CFrame       = CFrame.new(pos) * CFrame.Angles(0, -a - math.pi / 2, 0)
        p.Transparency = 0.2
        p.Color        = col
    end
end)

----------------------------------------------------------------------
-- 扫描器(无钩子时的兜底:手动挑攻击包)
----------------------------------------------------------------------
local scanTemplate = 1   -- 1=空 2=角色 3=根部件
local function tmplArgs()
    if scanTemplate == 3 then
        local r = root()
        return r and { r } or {}
    elseif scanTemplate == 2 then
        local c = LP.Character
        return c and { c } or {}
    end
    return {}
end

local function scanRemotes()
    local out = {}
    local roots = {}
    local ok1, rs = pcall(function() return game:GetService("ReplicatedStorage") end)
    if ok1 and rs then roots[#roots + 1] = rs end
    local ok2, rf = pcall(function() return game:GetService("ReplicatedFirst") end)
    if ok2 and rf then roots[#roots + 1] = rf end

    local seen, count = {}, 0
    for _, r in ipairs(roots) do
        local ok3, kids = pcall(function() return r:GetDescendants() end)
        if ok3 and kids then
            for _, d in ipairs(kids) do
                count = count + 1
                if count > 40000 then break end
                if not seen[d] then
                    seen[d] = true
                    local isR = pcall(function() return d:IsA("RemoteEvent") or d:IsA("RemoteFunction") end)
                    if isR then
                        local n = string.lower(d.Name)
                        local sc = 0
                        for _, w in ipairs(ATK_WORDS) do
                            if string.find(n, w, 1, true) then sc = sc + 4 break end
                        end
                        for _, w in ipairs(BAD_WORDS) do
                            if string.find(n, w, 1, true) then sc = sc - 6 break end
                        end
                        out[#out + 1] = { remote = d, score = sc }
                    end
                end
            end
        end
    end
    table.sort(out, function(a, b) return a.score > b.score end)
    return out
end

local function forcePrimary(remote)
    local m = "FireServer"
    pcall(function() if remote:IsA("RemoteFunction") then m = "InvokeServer" end end)
    local e = {
        remote = remote, method = m, args = tmplArgs(),
        count = 0, score = 999, learnHit = true, manual = true,
    }
    ST.pool[remote] = e
    ST.primary = e
    setStatus("已手动指定: " .. remote.Name)
    refreshUI()
end

----------------------------------------------------------------------
-- 面板
----------------------------------------------------------------------
local function getGuiParent()
    if type(gethui) == "function" then
        local ok, r = pcall(gethui)
        if ok and r then
            local ok2 = pcall(function() local f = Instance.new("Folder"); f.Parent = r; f:Destroy() end)
            if ok2 then return r end
        end
    end
    local ok3, cg = pcall(function() return game:GetService("CoreGui") end)
    if ok3 and cg then
        local ok4 = pcall(function() local f = Instance.new("Folder"); f.Parent = cg; f:Destroy() end)
        if ok4 then return cg end
    end
    return LP:WaitForChild("PlayerGui")
end

local function makeCorner(o, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, r or 8)
    c.Parent = o
    return c
end

local function isPress(i)
    local t = i.UserInputType
    return t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch
end

local function clampToViewport(frame, pos)
    local vp = vpSize()
    local sz = frame.AbsoluteSize
    local w  = (sz and sz.X > 0) and sz.X or 260
    local h  = (sz and sz.Y > 0) and sz.Y or 60
    local x  = math.clamp(pos.X.Offset, 40 - w, vp.X - 40)
    local y  = math.clamp(pos.Y.Offset, 0, vp.Y - 44)
    return UDim2.new(0, x, 0, y)
end

local function dragMoveOf(active, i)
    if active == nil then return false end
    local at, it = active.UserInputType, i.UserInputType
    if at == Enum.UserInputType.MouseButton1 then
        return it == Enum.UserInputType.MouseMovement
    elseif at == Enum.UserInputType.Touch then
        return it == Enum.UserInputType.Touch
    end
    return false
end

local function dragEndOf(active, i)
    if active == nil then return false end
    return active.UserInputType == i.UserInputType
end

-- 拖动 + 点按/长按识别
local function makeDraggable(frame, handle, onTap, onLong)
    local dragging, dragStart, startPos, active, moved, t0 = false, nil, nil, nil, false, 0

    handle.InputBegan:Connect(function(i, processed)
        if processed then return end
        if not isPress(i) then return end
        dragging  = true
        dragStart = i.Position
        startPos  = frame.Position
        active    = i
        moved     = false
        t0        = clk()
    end)

    UserInput.InputChanged:Connect(function(i)
        if not dragging then return end
        if not dragMoveOf(active, i) then return end
        local d = i.Position - dragStart
        if not moved and d.Magnitude > 8 then moved = true end
        if moved then
            frame.Position = clampToViewport(frame, UDim2.new(
                0, startPos.X.Offset + d.X,
                0, startPos.Y.Offset + d.Y))
        end
    end)

    UserInput.InputEnded:Connect(function(i)
        if not dragging then return end
        if not dragEndOf(active, i) then return end
        local dt = clk() - t0
        dragging, active = false, nil
        if moved then return end
        if dt >= 0.45 then
            if onLong then onLong() end
        elseif onTap then
            onTap()
        end
    end)
end

local function buildUI()
    -- 清掉上次注入残留
    if getgenv then
        local ok, old = pcall(function() return getgenv().ZAKA_KILLAURA end)
        if ok and old then pcall(function() old:Destroy() end) end
    end

    local parent = getGuiParent()
    local vp     = vpSize()

    local gui = Instance.new("ScreenGui")
    gui.Name           = "ZakaKillAuraUI"
    gui.ResetOnSpawn   = false
    gui.IgnoreGuiInset = true
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.DisplayOrder   = 999
    local pok = pcall(function() gui.Parent = parent end)
    if not pok then gui.Parent = LP:WaitForChild("PlayerGui") end
    if getgenv then pcall(function() getgenv().ZAKA_KILLAURA = gui end) end

    local C_BG   = Color3.fromRGB(16, 18, 24)
    local C_ROW  = Color3.fromRGB(30, 34, 44)
    local C_TXT  = Color3.fromRGB(226, 230, 238)
    local C_DIM  = Color3.fromRGB(150, 156, 168)
    local C_ACC  = CFG.Color
    local C_GRN  = Color3.fromRGB(0, 220, 130)

    local ROW_H  = IS_MOBILE and 42 or 34
    local BTN_H  = IS_MOBILE and 46 or 34
    local STEP_W = IS_MOBILE and 42 or 32

    ------------------------------------------------------------------
    -- 悬浮球
    ------------------------------------------------------------------
    local fab = Instance.new("TextButton")
    fab.Name               = "ZakaFab"
    fab.Size               = UDim2.new(0, 62, 0, 62)
    fab.Position           = UDim2.new(0, vp.X - 78, 0, vp.Y * 0.5)
    fab.BackgroundColor3   = Color3.fromRGB(0, 120, 88)
    fab.BorderSizePixel    = 0
    fab.AutoButtonColor    = false
    fab.Text               = ""
    fab.Active             = true
    fab.Parent             = gui
    makeCorner(fab, 31)
    local fabStroke = Instance.new("UIStroke")
    fabStroke.Color        = CFG.Color
    fabStroke.Thickness    = 2
    fabStroke.Parent       = fab
    local fabTxt = Instance.new("TextLabel")
    fabTxt.Size               = UDim2.new(1, 0, 0.55, 0)
    fabTxt.Position           = UDim2.new(0, 0, 0.08, 0)
    fabTxt.BackgroundTransparency = 1
    fabTxt.Font               = Enum.Font.GothamBold
    fabTxt.TextSize           = 17
    fabTxt.TextColor3         = Color3.fromRGB(255, 255, 255)
    fabTxt.Text               = "杀戒"
    fabTxt.Parent             = fab
    local fabSub = Instance.new("TextLabel")
    fabSub.Size               = UDim2.new(1, 0, 0.32, 0)
    fabSub.Position           = UDim2.new(0, 0, 0.6, 0)
    fabSub.BackgroundTransparency = 1
    fabSub.Font               = Enum.Font.GothamBold
    fabSub.TextSize           = 12
    fabSub.TextColor3         = Color3.fromRGB(230, 240, 255)
    fabSub.Text               = "ON"
    fabSub.Parent             = fab
    ui.fab      = fab
    ui.fabStroke= fabStroke
    ui.fabTxt   = fabSub

    ------------------------------------------------------------------
    -- 面板
    ------------------------------------------------------------------
    local W = math.clamp(vp.X - 32, 250, 320)
    local H = math.clamp(vp.Y - 130, 300, 560)

    local panel = Instance.new("Frame")
    panel.Name                   = "Panel"
    panel.Size                   = UDim2.new(0, W, 0, H)
    panel.Position               = UDim2.new(0, 14, 0, IS_MOBILE and 62 or 90)
    panel.BackgroundColor3       = C_BG
    panel.BackgroundTransparency = 0.05
    panel.BorderSizePixel        = 0
    panel.Active                 = true
    panel.Parent                 = gui
    makeCorner(panel, 12)
    local pStroke = Instance.new("UIStroke")
    pStroke.Color        = C_ACC
    pStroke.Transparency = 0.55
    pStroke.Parent       = panel

    -- 标题栏
    local title = Instance.new("TextButton")
    title.Size               = UDim2.new(1, 0, 0, 42)
    title.BackgroundColor3   = Color3.fromRGB(23, 27, 36)
    title.BorderSizePixel    = 0
    title.AutoButtonColor    = false
    title.Text               = ""
    title.Active             = true
    title.Parent             = panel
    makeCorner(title, 12)
    local titleTxt = Instance.new("TextLabel")
    titleTxt.Size               = UDim2.new(1, -60, 1, 0)
    titleTxt.Position           = UDim2.new(0, 14, 0, 0)
    titleTxt.BackgroundTransparency = 1
    titleTxt.Font               = Enum.Font.GothamBold
    titleTxt.TextSize           = IS_MOBILE and 15 or 14
    titleTxt.TextColor3         = C_ACC
    titleTxt.TextXAlignment     = Enum.TextXAlignment.Left
    titleTxt.Text               = "ZAKA · 杀戒光环 v2.0"
    titleTxt.Parent             = title

    local hideBtn = Instance.new("TextButton")
    hideBtn.Size             = UDim2.new(0, 40, 0, 40)
    hideBtn.Position         = UDim2.new(1, -44, 0, 1)
    hideBtn.BackgroundTransparency = 0.8
    hideBtn.BackgroundColor3 = Color3.fromRGB(40, 45, 58)
    hideBtn.BorderSizePixel  = 0
    hideBtn.Font             = Enum.Font.GothamBold
    hideBtn.TextSize         = 18
    hideBtn.TextColor3       = C_DIM
    hideBtn.Text             = "—"
    hideBtn.Parent           = title
    makeCorner(hideBtn, 8)

    -- 内容滚动区
    local scroll = Instance.new("ScrollingFrame")
    scroll.Size                = UDim2.new(1, 0, 1, -(42 + 46))
    scroll.Position            = UDim2.new(0, 0, 0, 42)
    scroll.BackgroundTransparency = 1
    scroll.BorderSizePixel     = 0
    scroll.ScrollBarThickness  = 4
    scroll.ScrollBarImageColor3= C_ACC
    scroll.ScrollingDirection  = Enum.ScrollingDirection.Y
    scroll.CanvasSize          = UDim2.new(0, 0, 0, 0)
    scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    scroll.Parent              = panel

    local inner = Instance.new("Frame")
    inner.Size               = UDim2.new(1, -6, 0, 0)
    inner.BackgroundTransparency = 1
    inner.AutomaticSize      = Enum.AutomaticSize.Y
    inner.Parent             = scroll

    local innerList = Instance.new("UIListLayout")
    innerList.Padding    = UDim.new(0, 8)
    innerList.SortOrder  = Enum.SortOrder.LayoutOrder
    innerList.Parent     = inner

    local innerPad = Instance.new("UIPadding")
    innerPad.PaddingTop    = UDim.new(0, 4)
    innerPad.PaddingBottom = UDim.new(0, 10)
    innerPad.PaddingLeft   = UDim.new(0, 8)
    innerPad.PaddingRight  = UDim.new(0, 4)
    innerPad.Parent        = inner

    -- 底部状态区
    local statusBox = Instance.new("Frame")
    statusBox.Size               = UDim2.new(1, 0, 0, 46)
    statusBox.Position           = UDim2.new(0, 0, 1, -46)
    statusBox.BackgroundColor3   = Color3.fromRGB(22, 25, 33)
    statusBox.BackgroundTransparency = 0.25
    statusBox.BorderSizePixel    = 0
    statusBox.Parent             = panel
    makeCorner(statusBox, 10)

    local info = Instance.new("TextLabel")
    info.Size               = UDim2.new(1, -20, 0, 18)
    info.Position           = UDim2.new(0, 10, 0, 4)
    info.BackgroundTransparency = 1
    info.Font               = Enum.Font.GothamBold
    info.TextSize           = 12
    info.TextXAlignment     = Enum.TextXAlignment.Left
    info.TextTruncate       = Enum.TextTruncate.AtEnd
    info.Text               = "攻击包: 未捕获"
    info.TextColor3         = Color3.fromRGB(255, 180, 60)
    info.Parent             = statusBox
    ui.info = info

    local status = Instance.new("TextLabel")
    status.Size             = UDim2.new(1, -20, 0, 18)
    status.Position         = UDim2.new(0, 10, 0, 23)
    status.BackgroundTransparency = 1
    status.Font             = Enum.Font.Gotham
    status.TextSize         = 11
    status.TextXAlignment   = Enum.TextXAlignment.Left
    status.TextTruncate     = Enum.TextTruncate.AtEnd
    status.TextColor3       = C_DIM
    status.Text             = ST.status
    status.Parent           = statusBox
    ui.status = status

    ------------------------------------------------------------------
    -- 行构建器
    ------------------------------------------------------------------
    local function mkRowHolder(ord, p)
        local f = Instance.new("Frame")
        f.Size               = UDim2.new(1, 0, 0, ROW_H)
        f.BackgroundColor3   = C_ROW
        f.BackgroundTransparency = 0.3
        f.BorderSizePixel    = 0
        f.LayoutOrder        = ord
        f.Parent             = p or inner
        makeCorner(f, 8)
        return f
    end

    local function mkToggle(ord, text, key, cb, p)
        local f = mkRowHolder(ord, p)
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(1, 0, 1, 0)
        btn.BackgroundTransparency = 1
        btn.Text = ""
        btn.Parent = f

        local l = Instance.new("TextLabel")
        l.Size               = UDim2.new(1, -90, 1, 0)
        l.Position           = UDim2.new(0, 14, 0, 0)
        l.BackgroundTransparency = 1
        l.Font               = Enum.Font.Gotham
        l.TextSize           = IS_MOBILE and 14 or 13
        l.TextColor3         = C_TXT
        l.TextXAlignment     = Enum.TextXAlignment.Left
        l.Text               = text
        l.Parent             = btn

        local chip = Instance.new("TextLabel")
        chip.Size             = UDim2.new(0, 58, 0, IS_MOBILE and 28 or 22)
        chip.Position         = UDim2.new(1, -70, 0.5, -(IS_MOBILE and 14 or 11))
        chip.BackgroundColor3 = Color3.fromRGB(44, 50, 62)
        chip.BorderSizePixel  = 0
        chip.Font             = Enum.Font.GothamBold
        chip.TextSize         = 12
        chip.TextColor3       = C_DIM
        chip.Text             = "OFF"
        chip.Parent           = btn
        makeCorner(chip, 6)

        local function sync()
            chip.Text = CFG[key] and "ON" or "OFF"
            chip.TextColor3 = CFG[key] and C_GRN or C_DIM
        end
        btn.Activated:Connect(function()
            CFG[key] = not CFG[key]
            sync()
            if cb then cb() end
            refreshUI()
        end)
        sync()
        return btn
    end

    local function mkNum(ord, text, key, step, minv, maxv, fmt, p)
        local f = mkRowHolder(ord, p)

        local l = Instance.new("TextLabel")
        l.Size               = UDim2.new(0.32, 0, 1, 0)
        l.Position           = UDim2.new(0, 12, 0, 0)
        l.BackgroundTransparency = 1
        l.Font               = Enum.Font.Gotham
        l.TextSize           = IS_MOBILE and 14 or 13
        l.TextColor3         = C_TXT
        l.TextXAlignment     = Enum.TextXAlignment.Left
        l.TextTruncate       = Enum.TextTruncate.AtEnd
        l.Text               = text
        l.Parent             = f

        local val = Instance.new("TextLabel")
        val.Size             = UDim2.new(0, 46, 1, 0)
        val.Position         = UDim2.new(0.32, 8, 0, 0)
        val.BackgroundTransparency = 1
        val.Font             = Enum.Font.GothamBold
        val.TextSize         = IS_MOBILE and 14 or 13
        val.TextColor3       = Color3.fromRGB(255, 255, 255)
        val.TextXAlignment   = Enum.TextXAlignment.Center
        val.Text             = fmt(CFG[key])
        val.Parent           = f

        local function mkBtn(txt, xa, fn)
            local b = Instance.new("TextButton")
            b.Size             = UDim2.new(0, STEP_W, 0, IS_MOBILE and 34 or 26)
            b.Position         = UDim2.new(1, xa, 0.5, -(IS_MOBILE and 17 or 13))
            b.BackgroundColor3 = Color3.fromRGB(40, 46, 60)
            b.BorderSizePixel  = 0
            b.Font             = Enum.Font.GothamBold
            b.TextSize         = IS_MOBILE and 18 or 15
            b.TextColor3       = C_ACC
            b.Text             = txt
            b.Parent           = f
            makeCorner(b, 6)
            b.Activated:Connect(fn)
            return b
        end

        mkBtn("-", -(STEP_W * 2 + 18), function()
            CFG[key] = math.max(minv, CFG[key] - step)
            val.Text = fmt(CFG[key])
        end)
        mkBtn("+", -(STEP_W + 10), function()
            CFG[key] = math.min(maxv, CFG[key] + step)
            val.Text = fmt(CFG[key])
        end)

        return f
    end

    local function mkButton(ord, text, color, fn, p)
        local b = Instance.new("TextButton")
        b.Size             = UDim2.new(1, 0, 0, BTN_H)
        b.BackgroundColor3 = color
        b.BorderSizePixel  = 0
        b.Font             = Enum.Font.GothamBold
        b.TextSize         = IS_MOBILE and 14 or 13
        b.TextColor3       = Color3.fromRGB(255, 255, 255)
        b.Text             = text
        b.LayoutOrder      = ord
        b.Parent           = p or inner
        makeCorner(b, 8)
        b.Activated:Connect(fn)
        return b
    end

    ------------------------------------------------------------------
    -- 主页面
    ------------------------------------------------------------------
    local showMain, gotoList

    local pageMain = Instance.new("Frame")
    pageMain.Size               = UDim2.new(1, 0, 0, 0)
    pageMain.BackgroundTransparency = 1
    pageMain.AutomaticSize      = Enum.AutomaticSize.Y
    pageMain.LayoutOrder        = 1
    pageMain.Parent             = inner
    local pml = Instance.new("UIListLayout")
    pml.Padding   = UDim.new(0, 8)
    pml.SortOrder = Enum.SortOrder.LayoutOrder
    pml.Parent    = pageMain

    local ord = 0
    local function nextOrd() ord = ord + 1 return ord end

    local bigBtn = Instance.new("TextButton")
    bigBtn.Size             = UDim2.new(1, 0, 0, IS_MOBILE and 54 or 42)
    bigBtn.BackgroundColor3 = Color3.fromRGB(0, 120, 88)
    bigBtn.BorderSizePixel  = 0
    bigBtn.Font             = Enum.Font.GothamBold
    bigBtn.TextSize         = IS_MOBILE and 15 or 14
    bigBtn.TextColor3       = Color3.fromRGB(255, 255, 255)
    bigBtn.Text             = "● 光环运行中 · 点此关闭"
    bigBtn.LayoutOrder      = nextOrd()
    bigBtn.Parent           = pageMain
    makeCorner(bigBtn, 10)
    bigBtn.Activated:Connect(function()
        CFG.Enabled = not CFG.Enabled
        if not CFG.Enabled then updateHighlights({}) end
        setStatus(CFG.Enabled and "光环: 开" or "光环: 关")
        if CFG.Enabled and not ST.primary then startLearn() end
        refreshUI()
    end)
    ui.bigBtn = bigBtn

    mkButton(nextOrd(), "🎯 学习攻击包(" .. CFG.LearnSecs .. "秒)", Color3.fromRGB(0, 140, 190), function()
        startLearn()
    end, pageMain)

    mkButton(nextOrd(), "🔍 扫描包列表(钩子挂了用这个)", Color3.fromRGB(58, 66, 84), function()
        gotoList()
    end, pageMain)

    mkToggle(nextOrd(), "队伍检测(不打队友)", "TeamCheck", nil, pageMain)
    mkToggle(nextOrd(), "瞄点偏移(包里带坐标时)", "AimShift", nil, pageMain)
    mkToggle(nextOrd(), "光环显示", "Visual", function() setAuraVisible(CFG.Visual) end, pageMain)
    mkToggle(nextOrd(), "突进模式(服务端自算距离)", "Lunge", nil, pageMain)
    mkToggle(nextOrd(), "低配模式(省电/省帧)", "LowFX", nil, pageMain)
    mkNum(nextOrd(), "半径", "Range", 2, 4, 120, function(v) return tostring(v) end, pageMain)
    mkNum(nextOrd(), "出包间隔", "Delay", 0.01, 0.03, 0.5, function(v) return string.format("%.2f", v) end, pageMain)

    mkButton(nextOrd(), "📋 复制配置到剪贴板", Color3.fromRGB(58, 66, 84), function()
        local s = string.format(
            "{Range=%d, Delay=%.3f, TeamCheck=%s, AimShift=%s, Visual=%s, Lunge=%s, LowFX=%s}",
            CFG.Range, CFG.Delay, tostring(CFG.TeamCheck), tostring(CFG.AimShift),
            tostring(CFG.Visual), tostring(CFG.Lunge), tostring(CFG.LowFX))
        if setclipboard then
            pcall(setclipboard, s)
            setStatus("配置已复制到剪贴板")
        else
            setStatus("这个执行器没有剪贴板权限")
        end
    end, pageMain)

    ------------------------------------------------------------------
    -- 包列表页面
    ------------------------------------------------------------------
    local pageList = Instance.new("Frame")
    pageList.Size               = UDim2.new(1, 0, 0, 0)
    pageList.BackgroundTransparency = 1
    pageList.AutomaticSize      = Enum.AutomaticSize.Y
    pageList.LayoutOrder        = 2
    pageList.Visible            = false
    pageList.Parent             = inner
    local pll = Instance.new("UIListLayout")
    pll.Padding   = UDim.new(0, 8)
    pll.SortOrder = Enum.SortOrder.LayoutOrder
    pll.Parent    = pageList

    local lOrd = 0
    local function nextLOrd() lOrd = lOrd + 1 return lOrd end

    local tmplBtn
    local function syncTmpl()
        local names = {"空", "角色(Character)", "根部件(HumanoidRootPart)"}
        tmplBtn.Text = "参数模板: " .. names[scanTemplate] .. " ▸ 点这里切换"
    end

    tmplBtn = mkButton(nextLOrd(), "", Color3.fromRGB(58, 66, 84), function()
        scanTemplate = scanTemplate % 3 + 1
        syncTmpl()
    end, pageList)
    syncTmpl()

    local listHolder = Instance.new("Frame")
    listHolder.Size               = UDim2.new(1, 0, 0, 0)
    listHolder.BackgroundTransparency = 1
    listHolder.AutomaticSize      = Enum.AutomaticSize.Y
    listHolder.LayoutOrder        = nextLOrd()
    listHolder.Parent             = pageList
    local lhl = Instance.new("UIListLayout")
    lhl.Padding   = UDim.new(0, 6)
    lhl.SortOrder = Enum.SortOrder.LayoutOrder
    lhl.Parent    = listHolder

    local function fillList()
        for _, c in ipairs(listHolder:GetChildren()) do
            if c:IsA("TextButton") then c:Destroy() end
        end
        local found = scanRemotes()
        if #found == 0 then
            mkButton(1, "(一个 Remote 都没扫到)", Color3.fromRGB(50, 54, 66), function() end, listHolder)
            return
        end
        local n = math.min(#found, 24)
        for i = 1, n do
            local item = found[i]
            local nm = item.remote.Name
            if #nm > 26 then nm = string.sub(nm, 1, 26) .. "…" end
            mkButton(i, string.format("%s   [%+d]", nm, item.score), Color3.fromRGB(46, 54, 70), function()
                forcePrimary(item.remote)
                showMain()
            end, listHolder)
        end
    end

    mkButton(nextLOrd(), "🔄 重新扫描", Color3.fromRGB(0, 140, 190), fillList, pageList)
    mkButton(nextLOrd(), "◂ 返回", Color3.fromRGB(58, 66, 84), function() showMain() end, pageList)

    ------------------------------------------------------------------
    -- 页面切换 / 显隐
    ------------------------------------------------------------------
    showMain = function()
        pageList.Visible = false
        pageMain.Visible = true
        scroll.CanvasPosition = Vector2.new(0, 0)
    end

    gotoList = function()
        pageMain.Visible = false
        pageList.Visible = true
        scroll.CanvasPosition = Vector2.new(0, 0)
        fillList()
    end
    local function setPanelVisible(v)
        panel.Visible = v
        if v then panel.Size = UDim2.new(0, W, 0, H) end
    end

    hideBtn.Activated:Connect(function()
        setPanelVisible(false)
        setStatus("面板已收起 · 长按悬浮球再打开")
    end)

    ------------------------------------------------------------------
    -- 拖动绑定
    ------------------------------------------------------------------
    makeDraggable(panel, title, nil, nil)
    makeDraggable(fab, fab, function()
        CFG.Enabled = not CFG.Enabled
        if not CFG.Enabled then updateHighlights({}) end
        if CFG.Enabled and not ST.primary then startLearn() end
        setStatus(CFG.Enabled and "光环: 开" or "光环: 关")
        refreshUI()
    end, function()
        setPanelVisible(not panel.Visible)
    end)

    ------------------------------------------------------------------
    -- 屏幕旋转 / 尺寸变化时重新贴边
    ------------------------------------------------------------------
    local cam = workspace.CurrentCamera
    if cam then
        cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
            local nvp = cam.ViewportSize
            panel.Size = UDim2.new(0, math.clamp(nvp.X - 32, 250, 320), 0,
                                       math.clamp(nvp.Y - 130, 300, 560))
            panel.Position = clampToViewport(panel, UDim2.new(0, panel.Position.X.Offset, 0, panel.Position.Y.Offset))
            fab.Position = clampToViewport(fab, UDim2.new(0, fab.Position.X.Offset, 0, fab.Position.Y.Offset))
        end)
    end

    refreshUI()
end

----------------------------------------------------------------------
-- 快捷键(PC)
----------------------------------------------------------------------
UserInput.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.KeyCode == CFG.Keybind then
        CFG.Enabled = not CFG.Enabled
        if not CFG.Enabled then updateHighlights({}) end
        setStatus(CFG.Enabled and "光环: 开" or "光环: 关")
        if CFG.Enabled and not ST.primary then startLearn() end
        refreshUI()
    end
end)

----------------------------------------------------------------------
-- 主循环
----------------------------------------------------------------------
task.spawn(function()
    while true do
        if CFG.Enabled and ST.primary then
            local list = getTargets()
            updateHighlights(list)
            for i = 1, #list do
                if not CFG.Enabled then break end
                local t = list[i]
                if CFG.Lunge then lunge(t) end
                sendAttack(t)
                task.wait(CFG.Delay + random() * CFG.Jitter)
            end
        elseif not CFG.Enabled then
            updateHighlights({})
        end
        task.wait(0.05)
    end
end)

-- 换角色时重建光环
LP.CharacterAdded:Connect(function()
    task.wait(1)
    if CFG.Visual then buildRing() end
end)

----------------------------------------------------------------------
-- 启动
----------------------------------------------------------------------
-- 清掉上次注入残留的光环
pcall(function()
    local old = workspace:FindFirstChild("ZakaAuraVisual")
    if old then old:Destroy() end
end)

local hookOK, hookErr = installHook()
ST.hookOK = hookOK

buildUI()
if CFG.Visual then buildRing() end

if hookOK then
    setStatus(IS_MOBILE and "已就绪 · 点『学习攻击包』再去点游戏攻击键" or "已就绪 · 挥一刀学习攻击包")
    print("[ZAKA] 杀戒光环 v2.0 已加载 (手机端适配)")
else
    setStatus("钩子装不上(" .. tostring(hookErr) .. ") · 用『扫描包列表』手选")
    warn("[ZAKA] 钩子失败: " .. tostring(hookErr))
end
refreshUI()
