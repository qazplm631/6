--[[
=====================================================================
   Zaka Bullet Tracker  ·  Roblox 子弹追踪 / Silent Aim
   版本: 2.0  (PC + 手机 通用完整版)
   适配: 忍者注入器 / Arceus X / Hydrogen / Fluxus / Delta / Cryptic
        以及任何支持 getgenv + hookmetamethod 的执行器

   用法: 先进游戏 -> 进对局 -> 再执行本脚本(顺序反了读不到角色)
   按键: E = 开关追踪 | Q = 按住瞄准(可选) | F = 锁定 / 解锁目标
   手机: 右侧竖排三个虚拟按键(追踪 / 锁定 / 按住), 没键盘也能操作

   模式说明(Config.Mode):
     "All"      = 静默射线 + 子弹速度 一起上(默认, 最强)
     "Silent"   = 只改射线方向, 完全不动镜头
     "Velocity" = 只改子弹飞行向量, 老执行器不支持 hook 时用这个
     "Camera"   = 镜头平滑跟枪 + 子弹速度
=====================================================================
]]

--===========================================================
-- 0. 防重复注入
--===========================================================
if getgenv and getgenv().zakaBulletTracker then
    return warn("[Zaka] 脚本已在运行, 先执行 getgenv().zakaBulletTracker.unload() 再重新注入")
end

--===========================================================
-- 1. 执行器兼容层(老执行器缺函数一律给兜底, 不在这里报错)
--===========================================================
local nc        = newcclosure or function(f) return f end
local gnm       = getnamecallmethod or function() return nil end
local isCaller  = checkcaller or function() return false end
local unpack    = table.unpack or unpack
local hasMetaHook = (hookmetamethod ~= nil)
local hasRawMeta  = (getrawmetatable ~= nil and setreadonly ~= nil)

--===========================================================
-- 2. 服务 & 环境
--===========================================================
local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local Workspace        = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local StarterGui       = game:GetService("StarterGui")
local Stats            = game:GetService("Stats")

local LP = Players.LocalPlayer
while not LP do task.wait(0.1); LP = Players.LocalPlayer end

local Camera = Workspace.CurrentCamera
while not Camera do task.wait(0.1); Camera = Workspace.CurrentCamera end

local Mouse = LP:GetMouse()

-- 手机判定: 有触摸且没键盘, 就当手机端处理
local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

--===========================================================
-- 3. 配置区
--===========================================================
local Config = {
    Enabled          = true,          -- 脚本启动时是否开启
    Mode             = "All",         -- "All" / "Silent" / "Velocity" / "Camera"

    HoldToAim        = false,         -- true = 必须按住 Q(手机: 按住按钮)才瞄准
    AimKey           = Enum.KeyCode.Q,
    ToggleKey        = Enum.KeyCode.E,
    LockKey          = Enum.KeyCode.F,

    FOV              = 250,           -- 锁定范围(屏幕像素), 手机端自动按屏幕短边算
    UpdateRate       = isMobile and 0.08 or 0.05,  -- 目标刷新间隔(秒)
    Smoothness       = 0.25,          -- Camera 模式跟枪平滑度

    TeamCheck        = true,          -- 不打队友
    WallCheck        = not isMobile,  -- 穿墙检测(每目标一次射线, 手机默认关)
    HealthCheck      = true,          -- 跳过尸体
    HookMouse        = true,          -- 接管 mouse.Hit(老脚本用 mouse.Hit 取方向的兼容)

    MaxBullets       = isMobile and 4 or 8,   -- 同时修正的子弹数上限
    VelocityFrames   = 6,             -- 子弹出生后修正的帧数
    BulletSpeed      = 800,           -- 弹速估计(studs/s), 用于计算飞行时间
    Prediction       = 0.10,          -- 额外提前量(秒), 飘就加大
    HitParts         = {"Head", "UpperTorso", "Torso", "LowerTorso", "HumanoidRootPart"},
    IgnoreNames      = {"BulletTrail", "Trail", "Beam", "Effect", "Visual", "Marker", "Decal"},
    BulletNamePatterns = {"Bullet", "Projectile", "Pellet", "Shell", "Missile", "Arrow", "Bolt", "Shot"},
}

--===========================================================
-- 4. 运行时状态
--===========================================================
local running       = true
local inInternalCall = false          -- 内部调用守卫: 防止自己的射线被自己 hook 掉
local currentTarget = nil
local currentPart   = nil
local lockedPlayer  = nil
local mobileHold    = false
local oldNamecall   = nil
local oldIndex      = nil
local hookedByMeta  = false
local connections   = {}
local bullets       = {}              -- 待修正的子弹列表

--===========================================================
-- 5. 工具函数
--===========================================================
local function notify(text)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = "Zaka Bullet Tracker",
            Text = text,
            Duration = 3,
        })
    end)
end

local function isAlive(plr)
    if not plr or not plr.Parent then return false end
    local char = plr.Character
    if not char then return false end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return false end
    if Config.HealthCheck and hum.Health <= 0 then return false end
    return char:FindFirstChild("HumanoidRootPart") ~= nil
end

local function getAimPartOf(plr)
    local char = plr and plr.Character
    if not char then return nil end
    for i = 1, #Config.HitParts do
        local part = char:FindFirstChild(Config.HitParts[i])
        if part and part:IsA("BasePart") then return part end
    end
    return nil
end

local function getPing()
    local ok, ping = pcall(function()
        return Stats.Network.ServerStatsItem["Data Ping"]:GetValue()
    end)
    if ok and type(ping) == "number" then return ping end
    return 60
end

-- 弹道预测: 目标位置 + 速度 * (基础提前 + 飞行时间 + 半个 ping)
local function predictPosition(targetPart, origin)
    if not targetPart or not targetPart.Parent then return nil end
    local pos  = targetPart.Position
    local vel  = targetPart.AssemblyLinearVelocity
    local dist = (pos - origin).Magnitude
    local speed = Config.BulletSpeed
    if speed < 100 then speed = 100 end
    local travel = dist / speed
    local lead = Config.Prediction + travel + (getPing() / 1000) * 0.5
    return pos + vel * lead
end

-- 带守卫的射线(防止穿墙检测被自己的 hook 拦截掉)
local function safeRaycast(origin, direction, params)
    inInternalCall = true
    local ok, hit = pcall(function()
        return Workspace:Raycast(origin, direction, params)
    end)
    inInternalCall = false
    if ok then return hit end
    return nil
end

local function isVisible(part)
    if not Config.WallCheck then return true end
    local origin = Camera.CFrame.Position
    local dir = part.Position - origin
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { LP.Character }
    local hit = safeRaycast(origin, dir, params)
    if not hit then return true end
    return hit.Instance and hit.Instance:IsDescendantOf(part.Parent)
end

-- FOV 自适应: 手机分辨率一换, 写死的像素值等于全屏乱锁
local function updateFov()
    if not isMobile then return end
    local vp = Camera.ViewportSize
    Config.FOV = math.floor(math.min(vp.X, vp.Y) * 0.40)
end
updateFov()

--===========================================================
-- 6. 目标选择
--===========================================================
local function pickTarget()
    local best, bestScore = nil, math.huge
    local center = Camera.ViewportSize / 2
    local players = Players:GetPlayers()

    for i = 1, #players do
        local plr = players[i]
        if plr ~= LP and isAlive(plr) then
            local skip = false
            if Config.TeamCheck and LP.Team and plr.Team == LP.Team then skip = true end

            if not skip then
                local part = getAimPartOf(plr)
                if part and isVisible(part) then
                    local pos, onScreen = Camera:WorldToViewportPoint(part.Position)
                    if onScreen or Config.Mode == "Silent" then
                        local d = (Vector2.new(pos.X, pos.Y) - center).Magnitude
                        if d <= Config.FOV and d < bestScore then
                            best, bestScore = plr, d
                        end
                    end
                end
            end
        end
    end
    return best
end

--===========================================================
-- 7. __namecall hook —— 静默瞄准核心
--    游戏自己算弹道那一刻把射线方向换成目标位置
--===========================================================
local function namecallHandler(self, ...)
    -- 快路径: 不满足条件直接透传, 零开销
    if inInternalCall or not running or not Config.Enabled or currentPart == nil then
        return oldNamecall(self, ...)
    end
    if self ~= game and self ~= Workspace then
        return oldNamecall(self, ...)
    end
    if isCaller() then
        return oldNamecall(self, ...)
    end
    local mode = Config.Mode
    if mode ~= "All" and mode ~= "Silent" then
        return oldNamecall(self, ...)
    end

    local method = gnm()
    if method == "Raycast" or method == "RaycastAll" then
        local origin, direction, params = ...
        if typeof(origin) == "Vector3" and typeof(direction) == "Vector3" then
            local aim = predictPosition(currentPart, origin)
            if aim then
                return oldNamecall(self, origin, aim - origin, params)
            end
        end
    elseif method == "FindPartOnRay" then
        local args = { ... }
        local ray = args[1]
        if typeof(ray) == "Ray" then
            local origin = ray.Origin
            local aim = predictPosition(currentPart, origin)
            if aim then
                args[1] = Ray.new(origin, aim - origin)
                return oldNamecall(self, unpack(args))
            end
        end
    elseif method == "FindPartOnRayWithIgnoreList" or method == "FindPartOnRayWithWhitelist" then
        local args = { ... }
        local ray = args[1]
        if typeof(ray) == "Ray" then
            local origin = ray.Origin
            local aim = predictPosition(currentPart, origin)
            if aim then
                args[1] = Ray.new(origin, aim - origin)
                return oldNamecall(self, unpack(args))
            end
        end
    end

    return oldNamecall(self, ...)
end

local function applyNamecallHook()
    local handler = nc(namecallHandler)
    if hasMetaHook then
        oldNamecall = hookmetamethod(game, "__namecall", handler)
        hookedByMeta = true
        return true
    elseif hasRawMeta then
        local mt = getrawmetatable(game)
        setreadonly(mt, false)
        oldNamecall = mt.__namecall
        mt.__namecall = handler
        setreadonly(mt, true)
        hookedByMeta = false
        return true
    end
    return false
end

--===========================================================
-- 8. __index hook —— 接管 mouse.Hit
--    很多老脚本是用 mouse.Hit 取方向的, 给它也挂上追踪
--===========================================================
local function applyMouseHook()
    if not Config.HookMouse then return false end
    if not hasRawMeta then return false end
    local ok, err = pcall(function()
        local mt = getrawmetatable(game)
        setreadonly(mt, false)
        oldIndex = mt.__index
        mt.__index = nc(function(self, key)
            if (not inInternalCall) and running and Config.Enabled
               and self == Mouse and key == "Hit" and currentPart ~= nil then
                local mode = Config.Mode
                if mode == "All" or mode == "Silent" then
                    local unitRay = oldIndex(self, "UnitRay")
                    if unitRay then
                        local origin = unitRay.Origin
                        local aim = predictPosition(currentPart, origin)
                        if aim then
                            local dir = aim - origin
                            if dir.Magnitude > 0.1 then
                                return CFrame.lookAt(aim, aim + dir.Unit)
                            end
                        end
                    end
                end
            end
            return oldIndex(self, key)
        end)
        setreadonly(mt, true)
    end)
    if not ok then warn("[Zaka] mouse.Hit 接管失败: " .. tostring(err)) end
    return ok
end

--===========================================================
-- 9. 子弹速度拦截 —— Velocity 模式核心
--    子弹一出生就把飞行向量改成打预测位置
--===========================================================
local function nameMatches(name, list)
    for i = 1, #list do
        if string.find(name, list[i], 1, true) then return true end
    end
    return false
end

local function onDescendantAdded(inst)
    if not running or not Config.Enabled then return end
    local mode = Config.Mode
    if mode == "Silent" then return end
    if #bullets >= Config.MaxBullets then return end
    if not inst:IsA("BasePart") then return end
    if not nameMatches(inst.Name, Config.BulletNamePatterns) then return end
    if nameMatches(inst.Name, Config.IgnoreNames) then return end
    if inst:IsDescendantOf(LP.Character) then return end

    bullets[#bullets + 1] = {
        part   = inst,
        frames = Config.VelocityFrames,
        speed  = inst.AssemblyLinearVelocity.Magnitude,
    }
end

local function updateBullets()
    if not running or #bullets == 0 then return end
    local target = currentPart
    for i = #bullets, 1, -1 do
        local b = bullets[i]
        local part = b.part
        if (not part) or (not part.Parent) or b.frames <= 0 or target == nil or target.Parent == nil then
            table.remove(bullets, i)
        else
            local origin = part.Position
            local aim = predictPosition(target, origin)
            if aim then
                local dir = aim - origin
                if dir.Magnitude > 0.1 then
                    pcall(function()
                        part.CFrame = CFrame.lookAt(origin, aim)
                        local spd = b.speed
                        if spd < 50 then spd = 50 end
                        part.AssemblyLinearVelocity = dir.Unit * spd
                    end)
                end
            end
            b.frames = b.frames - 1
        end
    end
end

--===========================================================
-- 10. 主循环
--===========================================================
local accum = 0
local tickCount = 0

connections[#connections + 1] = Workspace.DescendantAdded:Connect(onDescendantAdded)

connections[#connections + 1] = RunService.Heartbeat:Connect(function(dt)
    if not running then return end
    tickCount = tickCount + 1
    Camera = Workspace.CurrentCamera or Camera

    -- 子弹修正每帧都跑, 不跟着目标刷新节流
    updateBullets()

    if isMobile and tickCount % 20 == 1 then updateFov() end

    accum = accum + dt
    if accum < Config.UpdateRate then return end
    accum = 0

    local aiming = Config.Enabled
        and ((not Config.HoldToAim) or mobileHold or UserInputService:IsKeyDown(Config.AimKey))

    if aiming then
        if lockedPlayer and isAlive(lockedPlayer) then
            currentTarget = lockedPlayer
            currentPart = getAimPartOf(lockedPlayer)
        else
            if lockedPlayer then lockedPlayer = nil end
            currentTarget = pickTarget()
            currentPart = currentTarget and getAimPartOf(currentTarget) or nil
        end
    else
        currentTarget, currentPart = nil, nil
    end

    -- Camera 模式: 平滑跟枪
    if Config.Mode == "Camera" and currentPart and currentPart.Parent then
        pcall(function()
            local goal = CFrame.lookAt(Camera.CFrame.Position, currentPart.Position)
            Camera.CFrame = Camera.CFrame:Lerp(goal, Config.Smoothness)
        end)
    end
end)

--===========================================================
-- 11. 键鼠按键(PC)
--===========================================================
connections[#connections + 1] = UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if input.KeyCode == Config.ToggleKey then
        Config.Enabled = not Config.Enabled
        if not Config.Enabled then
            currentTarget, currentPart, lockedPlayer = nil, nil, nil
        end
        notify(Config.Enabled and "追踪: 开启" or "追踪: 关闭")
    elseif input.KeyCode == Config.LockKey then
        if lockedPlayer then
            lockedPlayer = nil
            notify("已解锁目标")
        else
            lockedPlayer = currentTarget
            notify(lockedPlayer and ("已锁定: " .. lockedPlayer.Name) or "没找到可锁目标")
        end
    end
end)

-- 手指滑出按钮再松手时 MouseButton1Up 不一定触发, 这里兜底
connections[#connections + 1] = UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Touch then
        mobileHold = false
    end
end)

--===========================================================
-- 12. 手机虚拟按键(PC 上也能显示, 不想要就把 EnableHud 关掉)
--===========================================================
local EnableHud = isMobile

if EnableHud then
    local hud = Instance.new("ScreenGui")
    hud.Name = "ZakaTrackerHUD"
    hud.ResetOnSpawn = false
    hud.IgnoreGuiInset = true
    hud.Parent = (gethui and gethui()) or LP:WaitForChild("PlayerGui")

    local function mkBtn(label, y)
        local b = Instance.new("TextButton")
        b.Size = UDim2.fromOffset(58, 58)
        b.Position = UDim2.new(1, -74, 0.5, y)   -- 右侧竖排, 嫌挡手改这里
        b.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
        b.BackgroundTransparency = 0.2
        b.Text = label
        b.TextSize = 16
        b.Font = Enum.Font.GothamBold
        b.TextColor3 = Color3.fromRGB(0, 255, 170)
        b.BorderSizePixel = 0
        b.Parent = hud
        local c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(0, 12)
        c.Parent = b
        return b
    end

    local btnToggle = mkBtn("追踪", -100)
    local btnLock   = mkBtn("锁定", -34)
    local btnHold   = mkBtn("按住", 32)

    btnToggle.MouseButton1Click:Connect(function()
        Config.Enabled = not Config.Enabled
        if not Config.Enabled then
            currentTarget, currentPart, lockedPlayer = nil, nil, nil
        end
        notify(Config.Enabled and "追踪: 开启" or "追踪: 关闭")
    end)

    btnLock.MouseButton1Click:Connect(function()
        if lockedPlayer then
            lockedPlayer = nil
            notify("已解锁目标")
        else
            lockedPlayer = currentTarget
            notify(lockedPlayer and ("已锁定: " .. lockedPlayer.Name) or "没找到可锁目标")
        end
    end)

    btnHold.MouseButton1Down:Connect(function() mobileHold = true  end)
    btnHold.MouseButton1Up:Connect(function()   mobileHold = false end)
    btnHold.MouseLeave:Connect(function()       mobileHold = false end)
end

--===========================================================
-- 13. 卸载
--===========================================================
local function unload()
    running = false
    Config.Enabled = false
    currentTarget, currentPart, lockedPlayer = nil, nil, nil
    bullets = {}

    for i = 1, #connections do
        pcall(function() connections[i]:Disconnect() end)
    end

    if oldNamecall then
        pcall(function()
            if hookedByMeta and hasMetaHook then
                hookmetamethod(game, "__namecall", oldNamecall)
            elseif hasRawMeta then
                local mt = getrawmetatable(game)
                setreadonly(mt, false)
                mt.__namecall = oldNamecall
                setreadonly(mt, true)
            end
        end)
    end

    if oldIndex then
        pcall(function()
            if hasRawMeta then
                local mt = getrawmetatable(game)
                setreadonly(mt, false)
                mt.__index = oldIndex
                setreadonly(mt, true)
            end
        end)
    end

    if gethui then
        local ok, hui = pcall(gethui)
        local gui = (ok and hui or LP:FindFirstChild("PlayerGui"))
        if gui then
            local h = gui:FindFirstChild("ZakaTrackerHUD")
            if h then h:Destroy() end
        end
    end

    if getgenv then getgenv().zakaBulletTracker = nil end
    notify("Bullet Tracker 已卸载")
end

--===========================================================
-- 14. 启动
--===========================================================
local namecallOk = applyNamecallHook()
applyMouseHook()

if getgenv then
    getgenv().zakaBulletTracker = {
        unload = unload,
        Config = Config,
    }
end

if namecallOk then
    notify("Bullet Tracker 已加载 | " .. (isMobile and "手机: 用右侧按键" or "E=开关 Q=按住 F=锁定"))
else
    warn("[Zaka] 当前执行器不支持 hook __namecall, Silent 模式失效, 已自动改用 Config.Mode = \"Velocity\"")
    Config.Mode = "Velocity"
    notify("执行器不支持静默, 已切换 Velocity 模式")
end
