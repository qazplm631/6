--[[
================================================================================
  ZakaBulletTracker   v1.3   (PC / 移动端 一体完整版)
  静默瞄准 (Silent Aim) + 子弹飞行向量追踪 (Bullet Tracking)
--------------------------------------------------------------------------------
  两套机制:
    ① Silent   —— hook 弹道类方法 (Raycast / RaycastAll / FindPartOnRay*)，
                   把本次射线的方向掰向目标。不改镜头、不动鼠标、不抢视角。
    ② Velocity —— 子弹出膛后逐帧修正它的速度向量，让弹道拐向目标。

  相对上一版的改动:
    - 砍掉全局 __index hook (拦全场属性读取，风险最大收益最小)，
      改成主循环轮询 mouse.Hit —— 顺带解掉 "lacking capability Plugin" 警告
    - __namecall 窄化: 查表命中才处理，其余调用原样透传，不做任何附带方法调用
    - 穿墙检测的内部调用守卫 (inInternalCall)，防止自己的 hook 拦自己
    - 移动端: 触摸按键内建 / FOV 按屏幕短边自适应 / 性能自动降档 / 禁 Camera 模式

  用法:
    进对局 → 执行脚本 → 顶部弹「已加载」
    PC : E = 开关     Q = 锁定当前目标     F = 按住才瞄 (HoldToAim 打开时生效)
    手机: 右侧竖排三个触摸键「追踪 / 锁定 / 按住」
    卸载: getgenv().zakaBulletTracker.unload()
================================================================================
--]]

--==============================================================================
-- 0. 服务与基础环境
--==============================================================================
local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace        = game:GetService("Workspace")
local StarterGui       = game:GetService("StarterGui")

local LP     = Players.LocalPlayer
local Camera = Workspace.CurrentCamera
local mouse  = LP:GetMouse()

local unpack = table.unpack or unpack

-- 移动端判定: 有触摸输入且没有实体鼠标 => 手机 / 平板
local IS_MOBILE = UserInputService.TouchEnabled and not UserInputService.MouseEnabled

--==============================================================================
-- 1. 配置
--==============================================================================
local Config = {
    Enabled   = true,
    Mode      = "All",          -- All(=Silent+Velocity) / Silent / Velocity / Camera
    HoldToAim = false,          -- true = 按住 HoldKey / 屏幕「按住」键才瞄

    -- 键位 (PC)
    ToggleKey = Enum.KeyCode.E,
    LockKey   = Enum.KeyCode.Q,
    HoldKey   = Enum.KeyCode.F,

    -- 弹道
    Prediction  = 0.12,         -- 提前量(秒)。打飘就 0.15~0.20
    BulletSpeed = 900,          -- 仅参考用，实际取子弹自身速度
    SpeedBoost  = 1.0,          -- >1 = 子弹提速

    -- 索敌
    FOV        = 250,           -- PC 像素；手机会被 updateFov() 覆盖
    MaxDistance = 2000,
    TeamCheck   = true,
    WallCheck   = false,        -- 每人一次射线，人一多就掉帧，手机默认关

    -- 过滤 / 识别
    IgnoreNames = {             -- 角色里出现这些零件名就当无效目标
        BulletTrail = true, Effect = true, Smoke = true, Highlight = true,
    },
    BulletNames = {             -- 子弹零件名关键字(按你玩的游戏对一下)
        "Bullet", "Projectile", "Shell", "Arrow", "Bolt", "Throwable", "Shoot",
    },

    -- 性能
    MaxBullets = 8,
    UpdateRate = 0.05,          -- 索敌刷新间隔(秒)

    -- 其它
    CameraSmooth     = 0.25,    -- Camera 模式跟枪平滑度
    UseMouseHitAim   = false,   -- 用 mouse.Hit 落点当补充准星(老式脚本思路)
    HookMouseIndex   = false,   -- 保持关。全局 __index hook 已废弃，勿开
}

-- 手机自动降档: 砍掉两个掉帧大头 —— 逐子弹修正的数量 + 穿墙射线
if IS_MOBILE then
    Config.MaxBullets = 4
    Config.UpdateRate = 0.08
    Config.WallCheck  = false
    Config.Mode       = (Config.Mode == "Camera") and "All" or Config.Mode
end

--==============================================================================
-- 2. 状态
--==============================================================================
local currentTarget, currentPart, lockedPlayer = nil, nil, nil
local connections  = {}
local hud
local mobileHold   = false
local oldNamecall
local hookedByMeta = false
local inInternalCall = false
local mouseHit     = nil

--==============================================================================
-- 3. 小工具
--==============================================================================
local function notify(text)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = "ZakaBulletTracker", Text = text, Duration = 2,
        })
    end)
end

local function getSelfCharacter()
    local c = LP.Character
    if not c or not c.Parent then return nil end
    local hum = c:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return nil end
    return c, hum
end

local function isAlive(plr)
    local c = plr.Character
    if not c or not c.Parent then return false end
    local hum = c:FindFirstChildOfClass("Humanoid")
    return hum ~= nil and hum.Health > 0
end

local HIT_PRIORITY = {
    "Head", "UpperTorso", "Torso", "HumanoidRootPart", "LowerTorso",
    "RightUpperArm", "LeftUpperArm", "RightLowerArm", "LeftLowerArm",
}

local function pickHitPart(char)
    if not char then return nil end
    for _, name in ipairs(HIT_PRIORITY) do
        local p = char:FindFirstChild(name)
        if p and p:IsA("BasePart") then return p end
    end
    return char:FindFirstChildWhichIsA("BasePart")
end

-- FOV 自适应: 手机分辨率一换，写死的像素值等于全屏乱锁，必须按屏幕短边算
local function updateFov()
    local vp = Camera.ViewportSize
    Config.FOV = math.floor(math.min(vp.X, vp.Y) * 0.40)
end
if IS_MOBILE then updateFov() end

--==============================================================================
-- 4. 目标筛选
--==============================================================================
local function passesFilter(plr, char)
    if plr == LP then return false end
    if not isAlive(plr) then return false end
    if Config.TeamCheck and LP.Team and plr.Team == LP.Team then return false end
    for _, name in pairs(Config.IgnoreNames) do
        if name and char:FindFirstChild(name) then return false end
    end
    return true
end

-- 穿墙检测。注意: Workspace:Raycast 也算 namecall，会被自己的 hook 拐一遍，
-- 所以这里必须先立 inInternalCall 守卫，否则"永远可见"。
local function visible(part)
    if not Config.WallCheck then return true end
    local origin = Camera.CFrame.Position
    local params = RaycastParams.new()
    local ok = pcall(function()
        params.FilterType = Enum.RaycastFilterType.Exclude
    end)
    if not ok then
        pcall(function() params.FilterType = Enum.RaycastFilterType.Blacklist end)
    end
    params.FilterDescendantsInstances = { LP.Character, Camera }

    inInternalCall = true
    local hit = Workspace:Raycast(origin, part.Position - origin, params)
    inInternalCall = false

    return hit == nil or hit.Instance:IsDescendantOf(part.Parent)
end

local function findTarget()
    -- 已锁定: 只要目标还活着就一直用他，不换人
    if lockedPlayer then
        if isAlive(lockedPlayer) then
            currentTarget = lockedPlayer
            currentPart   = pickHitPart(lockedPlayer.Character)
            return currentTarget, currentPart
        end
        lockedPlayer = nil
    end

    local selfChar = getSelfCharacter()
    if not selfChar then
        currentTarget, currentPart = nil, nil
        return nil
    end

    local aimPoint = UserInputService:GetMouseLocation()
    local camPos   = Camera.CFrame.Position
    local best, bestPart, bestScore = nil, nil, math.huge

    for _, plr in ipairs(Players:GetPlayers()) do
        local char = plr.Character
        if char and passesFilter(plr, char) then
            local part = pickHitPart(char)
            if part then
                local dist = (camPos - part.Position).Magnitude
                if dist <= Config.MaxDistance then
                    local sp, onScreen = Camera:WorldToViewportPoint(part.Position)
                    if sp.Z > 0 and onScreen then
                        local score = (Vector2.new(sp.X, sp.Y) - aimPoint).Magnitude
                        if score <= Config.FOV and score < bestScore then
                            if visible(part) then
                                best, bestPart, bestScore = plr, part, score
                            end
                        end
                    end
                end
            end
        end
    end

    -- 补充准星: 老式脚本靠 mouse.Hit 取方向的思路，这里轮询读一次，
    -- 拿落点零件反查是谁的，不用挂全局 __index hook
    if not best and Config.UseMouseHitAim and mouseHit and mouseHit.Parent then
        local model = mouseHit:FindFirstAncestorOfClass("Model")
        if model then
            local plr = Players:GetPlayerFromCharacter(model)
            if plr and passesFilter(plr, model) then
                best, bestPart = plr, mouseHit
            end
        end
    end

    currentTarget, currentPart = best, bestPart
    return best, bestPart
end

local function getAimPosition()
    if not currentPart or not currentPart.Parent then return nil end
    local pos = currentPart.Position
    if Config.Prediction > 0 then
        pos = pos + currentPart.AssemblyLinearVelocity * Config.Prediction
    end
    return pos
end

--==============================================================================
-- 5. Silent —— 弹道 hook (窄化版 __namecall)
--==============================================================================
local HOOK_METHODS = {
    Raycast = true,
    RaycastAll = true,
    FindPartOnRay = true,
    FindPartOnRayWithIgnoreList = true,
    FindPartOnRayWithWhitelist = true,
}

-- 只对弹道方法动手，其余调用一次查表直接透传
local function buildRay(self, method, ...)
    if not Config.Enabled then return nil end
    if Config.Mode ~= "All" and Config.Mode ~= "Silent" then return nil end

    local aimPos = getAimPosition()
    if not aimPos then return nil end

    local args = { ... }

    if method == "Raycast" or method == "RaycastAll" then
        local origin, direction = args[1], args[2]
        if typeof(origin) ~= "Vector3" or typeof(direction) ~= "Vector3" then return nil end
        if direction.Magnitude < 0.001 then return nil end
        args[2] = (aimPos - origin).Unit * direction.Magnitude
        return oldNamecall(self, unpack(args))
    end

    -- 老接口传的是 Ray 对象
    local ray = args[1]
    if typeof(ray) ~= "Ray" then return nil end
    if ray.Direction.Magnitude < 0.001 then return nil end
    args[1] = Ray.new(ray.Origin, (aimPos - ray.Origin).Unit * ray.Direction.Magnitude)
    return oldNamecall(self, unpack(args))
end

if hookmetamethod and getnamecallmethod and newcclosure then
    pcall(function()
        oldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
            if inInternalCall then
                return oldNamecall(self, ...)
            end

            local method = getnamecallmethod()
            if not HOOK_METHODS[method] then
                return oldNamecall(self, ...)     -- 全场其它调用: 原样过，不碰
            end

            inInternalCall = true
            local result = buildRay(self, method, ...)
            inInternalCall = false

            if result ~= nil then return result end
            return oldNamecall(self, ...)
        end))
        hookedByMeta = true
    end)
end

if not hookedByMeta then
    warn("[Zaka] 执行器不支持 hookmetamethod, 走 Velocity 模式")
    Config.Mode = "Velocity"
end

--==============================================================================
-- 6. Velocity —— 子弹飞行向量追踪
--==============================================================================
local function isBulletLike(part)
    local name = part.Name
    for _, pat in ipairs(Config.BulletNames) do
        if name == pat or string.find(name, pat, 1, true) then return true end
    end
    -- 尺寸/速度启发式兜底: 小、细长、速度高、未锚定
    if not part.Anchored and part:IsA("BasePart") then
        local v = part.AssemblyLinearVelocity
        if v.Magnitude > 60 then
            local s = part.Size
            if math.max(s.X, s.Y, s.Z) <= 4 and math.min(s.X, s.Y, s.Z) <= 2 then
                return true
            end
        end
    end
    return false
end

local function collectBullets(out, container, depth)
    if depth > 3 or #out >= Config.MaxBullets then return end
    local children = container:GetChildren()
    for i = 1, #children do
        if #out >= Config.MaxBullets then return end
        local inst = children[i]
        if inst:IsA("BasePart") then
            if isBulletLike(inst) then
                out[#out + 1] = inst
            end
        elseif inst:IsA("Folder") or inst:IsA("Model") then
            if not inst:FindFirstChildOfClass("Humanoid") then   -- 别往角色里钻
                collectBullets(out, inst, depth + 1)
            end
        end
    end
end

local function trackBullets()
    local aimPos = getAimPosition()
    if not aimPos then return end

    local list = {}
    collectBullets(list, Workspace, 0)

    for i = 1, #list do
        local b = list[i]
        if b and b.Parent then
            local vel = b.AssemblyLinearVelocity
            local spd = vel.Magnitude
            if spd >= 10 then
                local dir = aimPos - b.Position
                if dir.Magnitude > 0.01 then
                    local newVel = dir.Unit * (spd * Config.SpeedBoost)
                    local lv = b:FindFirstChildWhichIsA("LinearVelocity")
                    if lv then
                        lv.VectorVelocity = newVel            -- 走约束的就改约束
                    else
                        b.AssemblyLinearVelocity = newVel     -- 否则直接喂速度
                    end
                end
            end
        end
    end
end

local function untrack()
    currentTarget, currentPart = nil, nil
end

--==============================================================================
-- 7. 输入 (PC 键位 + 手机触摸)
--==============================================================================
connections[#connections + 1] = UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.KeyCode == Config.ToggleKey then
        Config.Enabled = not Config.Enabled
        if not Config.Enabled then untrack() end
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

-- 手机虚拟按键 (PC 上自动隐藏)
local function buildHud()
    local existing = LP:FindFirstChild("PlayerGui") and LP.PlayerGui:FindFirstChild("ZakaTrackerHUD")
    if existing then existing:Destroy() end

    hud = Instance.new("ScreenGui")
    hud.Name = "ZakaTrackerHUD"
    hud.ResetOnSpawn = false
    hud.IgnoreGuiInset = true
    hud.Enabled = IS_MOBILE
    hud.Parent = (gethui and gethui()) or LP:WaitForChild("PlayerGui")

    local function mkBtn(label, y)
        local b = Instance.new("TextButton")
        b.Size = UDim2.fromOffset(58, 58)
        b.Position = UDim2.new(1, -74, 0.5, y)     -- 右侧竖排，挡手就改这个偏移
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

    connections[#connections + 1] = btnToggle.MouseButton1Click:Connect(function()
        Config.Enabled = not Config.Enabled
        if not Config.Enabled then untrack() end
        notify(Config.Enabled and "追踪: 开启" or "追踪: 关闭")
    end)

    connections[#connections + 1] = btnLock.MouseButton1Click:Connect(function()
        if lockedPlayer then
            lockedPlayer = nil
            notify("已解锁目标")
        else
            lockedPlayer = currentTarget
            notify(lockedPlayer and ("已锁定: " .. lockedPlayer.Name) or "没找到可锁目标")
        end
    end)

    connections[#connections + 1] = btnHold.MouseButton1Down:Connect(function() mobileHold = true  end)
    connections[#connections + 1] = btnHold.MouseButton1Up:Connect(  function() mobileHold = false end)
    connections[#connections + 1] = btnHold.MouseLeave:Connect(     function() mobileHold = false end)

    -- 手指滑出按钮再松手时上面那俩不一定触发，这里兜底
    connections[#connections + 1] = UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch then mobileHold = false end
    end)
end
buildHud()

--==============================================================================
-- 8. 主循环
--==============================================================================
local accum = 0

connections[#connections + 1] = RunService.Heartbeat:Connect(function(dt)
    -- 轮询 mouse.Hit 代替全局 __index hook (读一次，零副作用)
    if Config.UseMouseHitAim then
        pcall(function() mouseHit = mouse.Hit end)
    end

    accum = accum + dt
    if accum < Config.UpdateRate then
        -- 高频段: 子弹修正跟着物理帧走
        if Config.Enabled and (Config.Mode == "All" or Config.Mode == "Velocity") then
            trackBullets()
        end
        return
    end
    accum = 0

    if IS_MOBILE then updateFov() end

    local aimHeld = Config.Enabled
        and (not Config.HoldToAim or mobileHold or UserInputService:IsKeyDown(Config.HoldKey))

    if not aimHeld then
        untrack()
        return
    end

    findTarget()

    -- Camera 模式: 平滑跟枪(手机禁用，会跟触摸转视角打架)
    if Config.Mode == "Camera" and not IS_MOBILE and currentPart then
        local aimPos = getAimPosition()
        if aimPos then
            local desired = CFrame.new(Camera.CFrame.Position, aimPos)
            Camera.CFrame = Camera.CFrame:Lerp(desired, Config.CameraSmooth)
        end
    end
end)

--==============================================================================
-- 9. 卸载
--==============================================================================
local function unload()
    Config.Enabled = false
    untrack()

    for _, c in ipairs(connections) do
        pcall(function() c:Disconnect() end)
    end
    connections = {}

    -- 还原 hook，否则你永远分不清警告是谁的锅
    if hookedByMeta and oldNamecall and hookmetamethod then
        pcall(function() hookmetamethod(game, "__namecall", oldNamecall) end)
        hookedByMeta = false
    end

    if hud then pcall(function() hud:Destroy() end) hud = nil end

    notify("已卸载")
end

local genv = getgenv or function() return _G end
genv().zakaBulletTracker = { unload = unload, config = Config }

notify("已加载" .. (IS_MOBILE and " [手机模式]" or ""))
warn("[Zaka] BulletTracker v1.3 loaded | mode=" .. tostring(Config.Mode)
    .. " | mobile=" .. tostring(IS_MOBILE))

--[[
================================================================================
  调参速查
--------------------------------------------------------------------------------
  打不中 / 太飘        → Prediction 0.15~0.20，BulletSpeed 按游戏实际弹速对一下
  完全不改视角         → Mode = "All" 或 "Silent" (Silent 两个都不动镜头)
  老执行器没 hook      → 脚本会自己 warn 并切 "Velocity"，靠改子弹向量兜底
  想看子弹拐弯         → Mode = "Camera" + CameraSmooth 调小 (手机别开)
  乱锁人(锁到特效/队友)→ TeamCheck = true, IgnoreNames 里加那游戏的零件名
  手机卡               → Config.UpdateRate 放宽到 0.1，MaxBullets 降到 2~3
  子弹改不动           → 游戏用的是 LinearVelocity 约束不是直接设速度，
                          脚本已优先改约束；还没有就说明子弹在服务端模拟
  卸载                 → getgenv().zakaBulletTracker.unload()

  实话: 命中判定在服务端跑的游戏，客户端只能改自己发出去的射线和飞行向量。
  游戏要是对上报数据做校验，效果会打折 —— Silent + Velocity 双开已经是
  客户端能做到的极限。游戏更新后零件命名/结构变了，对一下 BulletNames /
  IgnoreNames 就行。
================================================================================
--]]
