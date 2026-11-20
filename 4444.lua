--[[
  RBX BULLET TRACK v1.0 —— 子弹追踪（真实弹道提前量 + 平滑锁定 + 弹道可视化）

  为什么单开一版，而不是继续改 v3~v7：
    v3~v6 去改写游戏的 Raycast / remote 参数，被 ACS 的参数校验打回来；
    v7 只换 Damage 里的 Humanoid，能打中但那是"静默瞄准"，不是弹道追踪。
    子弹追踪本身只需要「读目标速度 + 算弹道 + 转相机」，完全不用碰游戏 remote，
    所以这一版零钩子、零 remote 改写，卸载就是干净卸载。

  枪械参数不再写死（游戏换过枪械系统，旧结论作废）：
    弹速、重力、hitscan 与否全部**在运行时实测**，来源有三条，优先级从高到低：
      1) gun_probe.lua 探到的 profile（GunProfile），启动自动套用
      2) 运行中扫 workspace 的子弹部件：速度取中位、重力取速度 Y 的衰减率
      3) 都测不到 → 当 hitscan 处理（不做提前量，避免打空）
    想重新摸一遍枪械系统：先跑 gun_probe.lua，开 3~5 枪，抄报告最后一行；
    懒得抄就注入本脚本后执行 Bullet.learn(10)，边打边学。

  用法：
    注入后右上角出现悬浮按钮
      点一下        = 开 / 关
      长按 0.45 秒  = 切模式  AUTO → TRACK → LEAD → TRACE
      拖动          = 挪位置
    PC 键位：RightShift 开关 / RightAlt 切模式 / RightControl 重新测弹速
    控制台：Bullet.dump() 统计 / Bullet.calibrate() 重测 / Bullet.learn(10) 边打边学
            Bullet.profile() 看当前参数 / Bullet.resetLearning() 清样本 / unload
]]

--== 0. 执行器环境 ===============================================
local function envList()
  local list = {}
  local function add(t)
    if type(t) ~= "table" then return end
    for i = 1, #list do if list[i] == t then return end end
    table.insert(list, t)
  end
  pcall(function() add(getgenv()) end)
  pcall(function() add(getfenv and getfenv(0)) end)
  pcall(function() add(_ENV) end)
  pcall(function() add(_G) end)
  return list
end
local ENVS = envList()
local ENV = ENVS[1] or _G

local function pick(...)
  local names = { ... }
  for i = 1, #names do
    for j = 1, #ENVS do
      local ok, v = pcall(function() return ENVS[j][names[i]] end)
      if ok and type(v) == "function" then return v end
    end
  end
  return nil
end

local CAP = {
  gethui   = pick("gethui", "get_hidden_gui"),
  execName = pick("getexecutorname", "identifyexecutor"),
  setclip  = pick("setclipboard"),
}

-- 重复注入时先清掉上一份，避免两个 render 循环一起改相机
pcall(function()
  local old = (_G.Bullet or (getgenv and getgenv().Bullet))
  if old and type(old) == "table" and type(old.unload) == "function" then old.unload() end
end)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local WS = workspace
local LP = Players.LocalPlayer
local Camera = WS.CurrentCamera

--== 1. 配置 =====================================================
local CFG = {
  enabled   = true,
  mode      = "auto",   -- auto / track / lead / trace
  fov       = 240,      -- 屏幕像素半径
  teamCheck = true,
  part      = "Head",
  fallback  = "HumanoidRootPart",
  visCheck  = false,    -- true = 只锁没被墙挡住的目标（每帧多几次射线）

  -- 弹道
  speed     = 0,        -- 0=自动采样   >0=固定弹速（手动锁死）   <0=强制 hitscan
  speedHint = 0,        -- 初始猜测（来自 gun_probe）；学到真实弹速后自动让位
  minSpeed  = 40,       -- 采样下限，低于这个的部件当垃圾/碎片
  gravity   = 196.2,    -- 兜底重力；无下坠游戏设 0
  gravityAuto = true,   -- 有 2 条以上子弹样本时，用实测重力覆盖兜底值
  maxFlight = 2.5,      -- 飞行时间上限，防极端参数把准心甩上天
  pingComp  = true,     -- 用 GetNetworkPing 补网络延迟

  -- 相机
  smooth    = 14,       -- 收敛速度，越大跟得越紧
  maxTurn   = 720,      -- 最大角速度（度/秒），防瞬移式锁头
  keepFov   = 1.35,     -- 目标粘滞范围倍数

  -- 显示
  showFov     = true,
  showPath    = true,
  showMarker  = true,
  pathSegments = 10,
  pathColor   = Color3.fromRGB(0, 255, 140),
  pathLife    = 0.07,
  markerColor = Color3.fromRGB(255, 70, 70),
}

local S = {
  target = nil, aim = nil, tof = 0, mode = "track",
  speed = 0, locks = 0, frames = 0, errors = 0,
  lastUI = 0, pathAt = 0, startedAt = 0,
}

--== 1.1 枪械框架识别（只认名字，不 require 任何模块） =============
local FRAME_KEYS = {
  { "acs_engine", "ACS" }, { "acs_client", "ACS" }, { "acs_framework", "ACS" },
  { "acs_damage", "ACS" },
  { "xsf", "XSF" }, { "carbon", "Carbon" }, { "fe_gunkit", "FE Gun Kit" },
  { "qperfectionweld", "QPerfectionWeld" },
}

local function detectFramework()
  local names = {}
  local function take(root)
    if not root then return end
    local ok, kids = pcall(function() return root:GetChildren() end)
    if not ok or type(kids) ~= "table" then return end
    for i = 1, math.min(#kids, 300) do
      local okn, n = pcall(function() return kids[i].Name end)
      if okn and type(n) == "string" then names[#names + 1] = string.lower(n) end
    end
  end
  pcall(function() take(game:GetService("ReplicatedStorage")) end)
  pcall(function() take(WS) end)
  for i = 1, #names do
    for j = 1, #FRAME_KEYS do
      if string.find(names[i], FRAME_KEYS[j][1], 1, true) then return FRAME_KEYS[j][2] end
    end
  end
  return "未知"
end

local function now() return os.clock() end
local function clamp(x, a, b)
  if x < a then return a elseif x > b then return b end
  return x
end

--== 2. 玩家列表 =================================================
local plist = {}
local function refreshPlayers()
  local ok, l = pcall(Players.GetPlayers, Players)
  if ok and type(l) == "table" then plist = l end
end
pcall(function()
  Players.PlayerAdded:Connect(refreshPlayers)
  Players.PlayerRemoving:Connect(refreshPlayers)
end)
refreshPlayers()

local function alive(plr)
  if plr == LP then return false end
  if CFG.teamCheck then
    local ok, tm = pcall(function() return plr.Team end)
    if ok and tm ~= nil and LP.Team ~= nil and tm == LP.Team then return false end
  end
  local ch = plr.Character
  if not ch then return false end
  local hum = ch:FindFirstChildOfClass("Humanoid")
  if not hum or hum.Health <= 0 then return false end
  return true
end

local function partOf(plr)
  local ch = plr.Character
  if not ch then return nil end
  local part = ch:FindFirstChild(CFG.part) or ch:FindFirstChild(CFG.fallback)
  return part, ch
end

--== 3. 弹速采样 =================================================
-- 子弹在这类游戏里就是 workspace 里的一个/tracer Part：名字带 bullet，速度几十~几千
local SPEED = { value = 0, at = -1e9, source = "none", samples = {} }
local GRAV = { value = 0, samples = {}, measured = false }  -- 子弹实测重力
local lastVel = setmetatable({}, { __mode = "k" })    -- 同一条子弹的上一帧速度
local SPEED_KEYS = { "bullet", "tracer", "projectile", "round", "rocket", "shell", "弹" }
-- 上一版把 BaseProjectileImpact 当成了子弹：这类是弹孔/特效，速度恒 0，必须先排掉
local SKIP_KEYS = { "impact", "decal", "hole", "mark", "smoke", "flash", "spark",
                    "debris", "effect", "muzzle", "splash",
                    "casing", "shell", "brass", "mag", "clip" }

local function isBulletName(n)
  local ln = string.lower(tostring(n))
  for i = 1, #SKIP_KEYS do
    if string.find(ln, SKIP_KEYS[i], 1, true) then return false end
  end
  for i = 1, #SPEED_KEYS do
    if string.find(ln, SPEED_KEYS[i], 1, true) then return true end
  end
  return false
end

local function median(t)
  local n = #t
  if n == 0 then return 0 end
  local c = {}
  for i = 1, n do c[i] = t[i] end
  table.sort(c)
  if n % 2 == 1 then return c[(n + 1) / 2] end
  return (c[n / 2] + c[n / 2 + 1]) * 0.5
end

local function sampleBulletPart(p)
  local vel, pos
  pcall(function() vel = p.AssemblyLinearVelocity end)
  pcall(function() pos = p.Position end)
  if typeof(pos) ~= "Vector3" then return end

  local t = now()
  local prev = lastVel[p]
  local dt = prev and (t - prev.t) or nil

  -- 速度优先用引擎速度；锚定/CFrame 驱动的子弹速度恒 0，就用两次位置差反推
  local v = (typeof(vel) == "Vector3") and vel.Magnitude or 0
  local vy
  if typeof(vel) == "Vector3" and v >= CFG.minSpeed then
    vy = vel.Y
  elseif prev and dt and dt > 0.02 then
    vy = (pos.Y - prev.pos.Y) / dt
  end
  if prev and dt and dt > 0.02 then
    local inferred = (pos - prev.pos).Magnitude / dt
    if inferred > v then v = inferred end
  end

  lastVel[p] = { t = t, pos = pos, vy = vy }

  if type(v) ~= "number" or v < CFG.minSpeed or v > 40000 then return end

  table.insert(SPEED.samples, v)
  if #SPEED.samples > 24 then table.remove(SPEED.samples, 1) end
  SPEED.value = median(SPEED.samples)
  SPEED.at = t
  SPEED.source = "part:" .. tostring(p.Name)

  -- 同一条子弹前后两次采样，Y 速度掉得多快 = 这游戏的重力
  if prev and prev.vy and vy and dt and dt > 0.02 then
    local g = (prev.vy - vy) / dt
    if g > -20 and g < 800 then
      table.insert(GRAV.samples, g)
      if #GRAV.samples > 12 then table.remove(GRAV.samples, 1) end
      GRAV.value = math.max(0, median(GRAV.samples))
      GRAV.measured = true
    end
  end
end

--== 3.1 逐帧跟踪 ================================================
-- 这游戏的 Bullet 是 anchored，引擎速度恒 0，只活 0.1~0.4 秒。
-- 延迟 0.06/0.20 秒采样会错过它，所以出现即入表，每帧记位置，消失时结算。
local watching = {}

local function startWatch(p)
  if watching[p] then return end
  local ok, n = pcall(function() return p.Name end)
  watching[p] = { t0 = now(), samples = {}, name = ok and tostring(n) or "?" }
end

local function recordGravity(g)
  if g > -20 and g < 800 then
    table.insert(GRAV.samples, g)
    if #GRAV.samples > 12 then table.remove(GRAV.samples, 1) end
    GRAV.value = math.max(0, median(GRAV.samples))
    GRAV.measured = true
  end
end

local function finishWatch(p, w)
  local n = #w.samples
  if n >= 2 then
    local speeds = {}
    for i = 2, n do
      local a, b = w.samples[i - 1], w.samples[i]
      local dt = b.t - a.t
      if dt > 0.004 then
        table.insert(speeds, (b.pos - a.pos).Magnitude / dt)
      end
    end
    -- 用最快的一段而不是中位：子弹打到东西后会停住/留在原地，
    -- 后面的 0 速度会把中位数拉低，最大值才是飞行速度
    local sp = 0
    for i = 1, #speeds do if speeds[i] > sp then sp = speeds[i] end end
    if sp >= CFG.minSpeed and sp <= 40000 then
      table.insert(SPEED.samples, sp)
      if #SPEED.samples > 24 then table.remove(SPEED.samples, 1) end
      SPEED.value = median(SPEED.samples)
      SPEED.at = now()
      SPEED.source = "watch:" .. tostring(w.name)
    end

    -- 位置二阶差分算重力，样本太短就跳过（别学出 1455 那种假值）
    if n >= 3 then
      local a, b, c = w.samples[n - 2], w.samples[n - 1], w.samples[n]
      local dt1, dt2 = b.t - a.t, c.t - b.t
      if dt1 > 0.004 and dt2 > 0.004 then
        local vy1 = (b.pos.Y - a.pos.Y) / dt1
        local vy2 = (c.pos.Y - b.pos.Y) / dt2
        local g = (vy1 - vy2) / ((dt1 + dt2) * 0.5)
        recordGravity(g)
      end
    end
  end
  watching[p] = nil
end

local function updateWatches()
  for p, w in pairs(watching) do
    local ok, pos = pcall(function() return p.Position end)
    if ok and typeof(pos) == "Vector3" then
      table.insert(w.samples, { t = now(), pos = pos })
      if #w.samples > 40 then table.remove(w.samples, 1) end
    end
    if p.Parent == nil or now() - w.t0 > 2 then
      finishWatch(p, w)
    end
  end
end

-- 浅层扫描：只走 workspace 的 1~2 层，避免手机上 GetDescendants 卡帧
local function scanBullets(budget)
  budget = budget or 1200
  local visited = 0
  local function walk(node, depth)
    local kids
    local ok, c = pcall(function() return node:GetChildren() end)
    if not ok or type(c) ~= "table" then return end
    kids = c
    for i = 1, #kids do
      visited = visited + 1
      if visited > budget then return end
      local o = kids[i]
      local isPart = false
      pcall(function() isPart = o:IsA("BasePart") end)
      if isPart then
        if isBulletName(o.Name) then
          sampleBulletPart(o)
          startWatch(o)
        end
      elseif depth < 2 then
        walk(o, depth + 1)
      end
    end
  end
  walk(WS, 0)
end

local function bulletGravity()
  if CFG.gravityAuto and GRAV.measured and #GRAV.samples >= 2 then return GRAV.value end
  return CFG.gravity
end

local function bulletSpeed()
  if CFG.speed < 0 then return 0 end
  -- 实测优先：只要样本还新鲜，就不管手动值和猜测值
  if SPEED.value > 0 and now() - SPEED.at < 60 then return SPEED.value end
  if CFG.speed > 0 then return CFG.speed end
  if CFG.speedHint > 0 then return CFG.speedHint end
  return 0
end

-- 新子弹出现时补采样：比每帧扫 workspace 便宜得多
pcall(function()
  WS.DescendantAdded:Connect(function(o)
    local ok, isPart = pcall(function() return o:IsA("BasePart") end)
    if ok and isPart and isBulletName(o.Name) then
      startWatch(o)
      task.delay(0.10, function() sampleBulletPart(o) end)
    end
  end)
end)

--== 4. 弹道解算 =================================================
-- 目标做匀速直线运动 + 子弹有重力下坠：
--   求 t，使 |p + v·t + ½g t²·ŷ − o| = s·t
-- 用牛顿迭代（带数值导数），比"水平面二次方程"更准，比纯迭代更稳。
local function solveIntercept(o, p, v, s, g, maxT)
  if not s or s <= 0 then return p, 0 end          -- hitscan
  maxT = maxT or 2.5
  local d = p - o
  local t = clamp(d.Magnitude / s, 0, maxT)
  local half = Vector3.new(0, 0.5 * (g or 0), 0)

  for _ = 1, 6 do
    local q = p + v * t + half * (t * t)
    local f = (q - o).Magnitude - s * t
    local e = 0.01
    local q2 = p + v * (t + e) + half * ((t + e) * (t + e))
    local f2 = (q2 - o).Magnitude - s * (t + e)
    local der = (f2 - f) / e
    if math.abs(der) < 1e-4 then break end
    local nt = t - f / der
    if nt ~= nt or nt < 0 then nt = t * 0.5 end
    nt = clamp(nt, 0, maxT)
    if math.abs(nt - t) < 1e-4 then t = nt break end
    t = nt
  end

  local aim = p + v * t + half * (t * t)
  if (aim - o).Magnitude < 1e-3 then aim = p end

  -- 追不上就别硬追：目标横移速度接近/超过弹速时方程无解，
  -- 迭代会被 maxFlight 截断，算出来的点能偏出几百 studs。此时退回目标当前位置。
  local residual = (aim - o).Magnitude - s * t
  if math.abs(residual) > 1 then
    return p, 0
  end
  return aim, t
end

local function pingSeconds()
  local ok, p = pcall(function() return LP:GetNetworkPing() end)
  if ok and type(p) == "number" then return p end
  return 0
end

local function resolveMode()
  if CFG.mode == "auto" then
    return bulletSpeed() > 0 and "lead" or "track"
  end
  return CFG.mode
end

local MUZZLE_KEYS = { "muzzle", "barrel", "firepoint", "nozzle", "tip" }
local muzzleCache = { tool = nil, part = nil, at = 0 }
-- 枪口每帧都要用，但 GetDescendants 很贵：按工具缓存 1 秒
local function muzzleOrigin()
  local ch = LP.Character
  local tool = ch and ch:FindFirstChildOfClass("Tool")
  if tool then
    local c = muzzleCache
    if c.tool == tool and c.part and c.part.Parent and now() - c.at < 1 then
      return c.part.Position
    end
    local found = nil
    local ok, kids = pcall(function() return tool:GetDescendants() end)
    if ok and type(kids) == "table" then
      for i = 1, math.min(#kids, 220) do
        local o = kids[i]
        if not found then
          local isPart = false
          pcall(function() isPart = o:IsA("BasePart") end)
          if isPart then
            local ln = string.lower(o.Name)
            for k = 1, #MUZZLE_KEYS do
              if string.find(ln, MUZZLE_KEYS[k], 1, true) then found = o break end
            end
          end
        end
      end
    end
    c.tool, c.part, c.at = tool, found, now()
    if found then return found.Position end
  end
  if Camera then return Camera.CFrame.Position end
  return Vector3.new(0, 0, 0)
end

--== 5. 目标选择 =================================================
local cur = nil
local fxFolder            -- 前向声明：visible() 里要用

local function screenPos(pos)
  local cam = Camera
  if not cam then return nil end
  local ok, sp, on = pcall(function() return cam:WorldToViewportPoint(pos) end)
  if not ok or type(sp) ~= "table" then return nil end
  return sp, on
end

local function visible(part)
  if not CFG.visCheck then return true end
  local cam = Camera
  if not cam then return true end
  local ok, blocked = pcall(function()
    local rp = RaycastParams.new()
    rp.FilterType = Enum.RaycastFilterType.Exclude
    local ignore = { part }
    if LP.Character then table.insert(ignore, LP.Character) end
    if fxFolder then table.insert(ignore, fxFolder) end
    rp.FilterDescendantsInstances = ignore
    local dir = part.Position - cam.CFrame.Position
    return WS:Raycast(cam.CFrame.Position, dir, rp)
  end)
  if not ok then return true end
  return blocked == nil
end

local function pickTarget()
  local cam = Camera
  if not cam then return nil end
  local vp = cam.ViewportSize
  local center = Vector2.new(vp.X * 0.5, vp.Y * 0.5)

  -- 先确认老目标还活着
  if cur then
    if not (cur.part and cur.part.Parent and alive(cur.plr)) then
      cur = nil
    else
      local sp, on = screenPos(cur.part.Position)
      if sp and on and sp.Z > 0 then
        cur.dist = (Vector2.new(sp.X, sp.Y) - center).Magnitude
      else
        cur.dist = nil
      end
    end
  end

  local best, bestD = nil, math.huge
  for i = 1, #plist do
    local plr = plist[i]
    if alive(plr) then
      local part, ch = partOf(plr)
      if part then
        local sp, on = screenPos(part.Position)
        if sp and on and sp.Z > 0 then
          local d = (Vector2.new(sp.X, sp.Y) - center).Magnitude
          if d <= CFG.fov and visible(part) then
            if d < bestD then
              bestD = d
              best = { plr = plr, part = part, dist = d, hum = ch:FindFirstChildOfClass("Humanoid") }
            end
          end
        end
      end
    end
  end

  -- 粘滞：老目标还在扩大后的 FOV 里，就别被边缘的更近目标抢走
  if cur and cur.dist and cur.dist <= CFG.fov * CFG.keepFov then
    if not best or best.plr ~= cur.plr then
      if not best or best.dist > cur.dist * 0.55 then
        best = cur
      end
    end
  end

  if best and best ~= cur then S.locks = S.locks + 1 end
  cur = best
  S.target = (best and best.part and best.part.Parent) and best or nil
  return best
end

--== 6. 画面 =====================================================
local pathParts, marker, fovRing, btn = {}, nil, nil, nil
local MARKER_SIZE = 18

local function getFxFolder()
  if fxFolder and fxFolder.Parent then return fxFolder end
  local f = Instance.new("Folder")
  f.Name = "BulletTrackFx"
  f.Parent = WS
  fxFolder = f
  return f
end

local function getPathPart(i)
  local p = pathParts[i]
  if p and p.Parent then return p end
  p = Instance.new("Part")
  p.Name = "bt"
  p.Anchored = true
  p.CanCollide = false
  p.CanQuery = false
  p.CanTouch = false
  p.CastShadow = false
  p.Material = Enum.Material.Neon
  p.Color = CFG.pathColor
  p.Size = Vector3.new(0.07, 0.07, 0.07)
  p.Transparency = 0.35
  p.Parent = getFxFolder()
  pathParts[i] = p
  return p
end

-- 画出真正的抛物线：起点 → 每段按 v·t + ½g t² 采样
local segA, segB = {}, {}
local function drawPath(origin, aim, tof, speed, gravity)
  local n = CFG.pathSegments
  local dist = (aim - origin).Magnitude
  if dist < 1 then return end

  if speed > 0 and tof > 0.001 then
    local u = (aim - origin).Unit
    local half = 0.5 * (gravity or CFG.gravity or 0)
    local prev = origin
    for i = 1, n do
      local tt = tof * i / n
      local pos = origin + u * (speed * tt) + Vector3.new(0, -half * tt * tt, 0)
      segA[i], segB[i] = prev, pos
      prev = pos
    end
  else
    local u = (aim - origin).Unit
    local step = dist / n
    for i = 1, n do
      segA[i] = origin + u * (step * (i - 1))
      segB[i] = origin + u * (step * i)
    end
  end

  for i = 1, n do
    local p = getPathPart(i)
    local a, b = segA[i], segB[i]
    local len = (b - a).Magnitude
    if len > 0.02 then
      p.Size = Vector3.new(0.07, 0.07, len)
      p.CFrame = CFrame.lookAt((a + b) * 0.5, b)
      p.Transparency = 0.25 + 0.55 * (i / n)
    else
      p.Transparency = 1
    end
  end
  for i = n + 1, #pathParts do
    if pathParts[i] and pathParts[i].Parent then pathParts[i].Transparency = 1 end
  end
  S.pathAt = now()
end

local function hidePath()
  for i = 1, #pathParts do
    if pathParts[i] and pathParts[i].Parent then pathParts[i].Transparency = 1 end
  end
end

local function aimCamera(at, dt)
  local cam = Camera
  if not cam then return end
  local pos = cam.CFrame.Position
  local d = at - pos
  if d.Magnitude < 0.1 then return end

  local look = cam.CFrame.LookVector
  local want = d.Unit
  local ang = math.acos(clamp(look:Dot(want), -1, 1))

  local alpha = 1 - math.exp(-CFG.smooth * dt)
  if ang > 1e-5 then
    local maxA = math.rad(CFG.maxTurn) * dt / ang
    if alpha > maxA then alpha = maxA end
  end
  local goal = CFrame.lookAt(pos, at)
  local ok = pcall(function() cam.CFrame = cam.CFrame:Lerp(goal, alpha) end)
  if ok then S.camWrites = (S.camWrites or 0) + 1 end
end

local function updateMarker(at)
  if not marker then return end
  local sp, on = screenPos(at)
  if sp and on and sp.Z > 0 then
    marker.Visible = true
    marker.Position = UDim2.fromOffset(sp.X - MARKER_SIZE * 0.5, sp.Y - MARKER_SIZE * 0.5)
  else
    marker.Visible = false
  end
end

--== 7. 悬浮 UI ==================================================
local ui = { gui = nil, dragging = false, moved = false, pressAt = 0, startPos = nil, startInput = nil }
local MODE_TEXT = { auto = "AUTO", track = "TRACK", lead = "LEAD", trace = "TRACE" }
local MODE_ORDER = { "auto", "track", "lead", "trace" }

local function guiParent()
  if CAP.gethui then
    local ok, h = pcall(CAP.gethui)
    if ok and h then return h end
  end
  local ok, cg = pcall(function() return game:GetService("CoreGui") end)
  if ok and cg then return cg end
  local ok2, pg = pcall(function() return LP:WaitForChild("PlayerGui", 5) end)
  if ok2 then return pg end
  return nil
end

local function refreshUI()
  if btn then
    local sp = bulletSpeed()
    local spTxt = sp > 0 and string.format("%d", math.floor(sp + 0.5)) or "HITSCAN"
    pcall(function()
      btn.Text = string.format("%s %s\n%s\n%d", MODE_TEXT[CFG.mode] or "?",
        CFG.enabled and "ON" or "OFF", spTxt, S.locks)
      btn.TextColor3 = CFG.enabled and Color3.fromRGB(0, 255, 140) or Color3.fromRGB(140, 140, 140)
    end)
  end
  if fovRing then
    pcall(function()
      fovRing.Size = UDim2.fromOffset(CFG.fov * 2, CFG.fov * 2)
      fovRing.Visible = CFG.enabled and CFG.showFov
    end)
  end
  if marker and not CFG.showMarker then marker.Visible = false end
end

local function cycleMode()
  for i = 1, #MODE_ORDER do
    if MODE_ORDER[i] == CFG.mode then
      CFG.mode = MODE_ORDER[(i % #MODE_ORDER) + 1]
      break
    end
  end
  S.locks = 0
  print("[bullet] mode -> " .. CFG.mode .. "（实际=" .. resolveMode() .. "）")
  refreshUI()
end

local function buildUI()
  local parent = guiParent()
  if not parent then return end
  pcall(function()
    local gui = Instance.new("ScreenGui")
    gui.Name = "RbxBulletTrack"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 998
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.Parent = parent
    ui.gui = gui

    local ring = Instance.new("Frame")
    ring.AnchorPoint = Vector2.new(0.5, 0.5)
    ring.Position = UDim2.fromScale(0.5, 0.5)
    ring.Size = UDim2.fromOffset(CFG.fov * 2, CFG.fov * 2)
    ring.BackgroundTransparency = 1
    ring.BorderSizePixel = 0
    ring.ZIndex = 1
    local rc = Instance.new("UICorner")
    rc.CornerRadius = UDim.new(1, 0)
    rc.Parent = ring
    local rs = Instance.new("UIStroke")
    rs.Thickness = 1
    rs.Color = Color3.fromRGB(0, 255, 140)
    rs.Transparency = 0.75
    rs.Parent = ring
    ring.Parent = gui
    fovRing = ring

    local mk = Instance.new("Frame")
    mk.Size = UDim2.fromOffset(MARKER_SIZE, MARKER_SIZE)
    mk.BackgroundTransparency = 1
    mk.BorderSizePixel = 0
    mk.Visible = false
    mk.ZIndex = 5
    local mc = Instance.new("UICorner")
    mc.CornerRadius = UDim.new(1, 0)
    mc.Parent = mk
    local ms = Instance.new("UIStroke")
    ms.Thickness = 2
    ms.Color = CFG.markerColor
    ms.Transparency = 0.1
    ms.Parent = mk
    mk.Parent = gui
    marker = mk

    local b = Instance.new("TextButton")
    b.Size = UDim2.fromOffset(92, 66)
    b.Position = UDim2.new(1, -190, 0, 120)
    b.BackgroundColor3 = Color3.fromRGB(18, 22, 28)
    b.BackgroundTransparency = 0.25
    b.AutoButtonColor = false
    b.TextSize = 12
    b.Font = Enum.Font.GothamBold
    b.TextColor3 = Color3.fromRGB(0, 255, 140)
    b.Text = "AUTO ON\nHITSCAN\n0"
    b.BorderSizePixel = 0
    b.ZIndex = 10
    local bc = Instance.new("UICorner")
    bc.CornerRadius = UDim.new(0, 14)
    bc.Parent = b
    local bs = Instance.new("UIStroke")
    bs.Thickness = 1
    bs.Color = Color3.fromRGB(0, 255, 140)
    bs.Transparency = 0.35
    bs.Parent = b
    b.Parent = gui
    btn = b

    b.InputBegan:Connect(function(input)
      if input.UserInputType ~= Enum.UserInputType.Touch
        and input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
      ui.dragging, ui.moved = true, false
      ui.pressAt = now()
      ui.startPos = b.Position
      ui.startInput = input.Position
      input.Changed:Connect(function()
        if input.UserInputState ~= Enum.UserInputState.End then return end
        ui.dragging = false
        if ui.moved then return end
        if now() - ui.pressAt > 0.45 then
          cycleMode()
        else
          CFG.enabled = not CFG.enabled
          print("[bullet] " .. (CFG.enabled and "on" or "off"))
          if not CFG.enabled then hidePath() end
          refreshUI()
        end
      end)
    end)

    b.InputChanged:Connect(function(input)
      if not ui.dragging then return end
      if input.UserInputType ~= Enum.UserInputType.Touch
        and input.UserInputType ~= Enum.UserInputType.MouseMovement then return end
      local d = input.Position - ui.startInput
      if d.Magnitude > 6 then ui.moved = true end
      b.Position = UDim2.new(
        ui.startPos.X.Scale, ui.startPos.X.Offset + d.X,
        ui.startPos.Y.Scale, ui.startPos.Y.Offset + d.Y)
    end)
  end)
  refreshUI()
end

--== 8. 主循环 ===================================================
local loopConn, loopBound = nil, false

local function step(dt)
  S.frames = S.frames + 1
  pcall(updateWatches)
  if not Camera then return end
  if not CFG.enabled then
    if marker then marker.Visible = false end
    if now() - S.pathAt > CFG.pathLife then hidePath() end
    return
  end

  if now() - S.lastUI > 0.15 then
    S.lastUI = now()
    refreshUI()
  end

  if SPEED.value == 0 and now() - S.lastScan > 1.5 then
    S.lastScan = now()
    pcall(scanBullets, 600)
  end

  local t = pickTarget()
  if not t or not t.part or not t.part.Parent then
    S.aim = nil
    if marker then marker.Visible = false end
    if now() - S.pathAt > CFG.pathLife then hidePath() end
    return
  end

  local mode = resolveMode()
  S.mode = mode

  local origin = muzzleOrigin()
  local pos = t.part.Position
  local vel = Vector3.new(0, 0, 0)
  pcall(function() vel = t.part.AssemblyLinearVelocity end)

  local speed = bulletSpeed()
  local aim, tof = pos, 0
  if mode == "lead" and speed > 0 then
    local lag = CFG.pingComp and pingSeconds() or 0
    local p0 = pos + vel * lag
    aim, tof = solveIntercept(origin, p0, vel, speed, bulletGravity(), CFG.maxFlight)
  end

  S.aim, S.tof, S.speed, S.gravity = aim, tof, speed, bulletGravity()

  if mode ~= "trace" then aimCamera(aim, dt) end
  if CFG.showMarker then updateMarker(aim) elseif marker then marker.Visible = false end
  if CFG.showPath then drawPath(origin, aim, tof, speed, bulletGravity()) end
end

local function guardedStep(dt)
  local ok, err = pcall(step, dt)
  if not ok then
    S.errors = S.errors + 1
    if S.errors <= 2 then warn("[bullet] step error: " .. tostring(err)) end
  end
end

local function startLoop()
  if loopConn then return end
  local BIND = "RbxBulletTrackStep"
  local bound = pcall(function()
    RunService:BindToRenderStep(BIND, Enum.RenderPriority.Camera.Value + 1, guardedStep)
  end)
  if bound then
    loopConn, loopBound = BIND, true
  else
    loopConn = RunService.RenderStepped:Connect(guardedStep)
  end
end

pcall(function()
  WS:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
    local c = WS.CurrentCamera
    if c then Camera = c end
  end)
end)

--== 9. 键盘（PC 端顺手） ========================================
pcall(function()
  UIS.InputBegan:Connect(function(input, processed)
    if processed then return end
    local k = input.KeyCode
    if k == Enum.KeyCode.RightShift then
      CFG.enabled = not CFG.enabled
      if not CFG.enabled then hidePath() end
      refreshUI()
    elseif k == Enum.KeyCode.RightAlt then
      cycleMode()
    elseif k == Enum.KeyCode.RightControl then
      if table.clear then table.clear(SPEED.samples) else SPEED.samples = {} end
      SPEED.value, SPEED.source = 0, "none"
      scanBullets(2000)
      print(string.format("[bullet] 重新测速: %.0f (%s)", SPEED.value, SPEED.source))
      refreshUI()
    end
  end)
end)

--== 10. API / 卸载 ==============================================
local function calibrate()
  if table.clear then table.clear(SPEED.samples) else SPEED.samples = {} end
  SPEED.value, SPEED.source = 0, "none"
  scanBullets(2000)
  print(string.format("[bullet] 弹速采样: %.0f studs/s（%s，样本 %d）",
    SPEED.value, SPEED.source, #SPEED.samples))
  return SPEED.value
end

local API = {
  CFG = CFG, state = S, modes = MODE_ORDER,
  on = function() CFG.enabled = true; refreshUI() end,
  off = function() CFG.enabled = false; hidePath(); refreshUI() end,
  toggle = function() CFG.enabled = not CFG.enabled; refreshUI() end,
  setMode = function(m) CFG.mode = m; refreshUI() end,
  calibrate = calibrate,
  speed = bulletSpeed,
  gravity = bulletGravity,
  sample = sampleBulletPart,
  resetLearning = function()
    if table.clear then table.clear(SPEED.samples) else SPEED.samples = {} end
    if table.clear then table.clear(GRAV.samples) else GRAV.samples = {} end
    for k in pairs(lastVel) do lastVel[k] = nil end
    SPEED.value, SPEED.source, SPEED.at = 0, "none", -1e9
    GRAV.value, GRAV.measured = 0, false
    print("[bullet] 已清空弹速/重力样本")
  end,
  framework = function() return S.framework end,
  profile = function()
    return {
      framework = S.framework, mode = S.mode,
      speed = bulletSpeed(), speedHint = CFG.speedHint, gravity = bulletGravity(),
      speedSamples = #SPEED.samples, gravitySamples = #GRAV.samples,
    }
  end,
  applyProfile = function(t)
    if type(t) ~= "table" then return false end
    if type(t.speed) == "number" then
      if t.speed < 0 then
        CFG.speed = -1                 -- 明确 hitscan，锁死
      else
        CFG.speedHint = t.speed        -- 只当初始猜测，实测会覆盖
      end
    end
    if type(t.gravity) == "number" then CFG.gravity = t.gravity end
    if type(t.mode) == "string" and MODE_TEXT[t.mode] then CFG.mode = t.mode end
    refreshUI()
    print(string.format("[bullet] 套用 profile: 弹速=%s 重力=%.0f（实测会覆盖猜测）",
      CFG.speed ~= 0 and tostring(CFG.speed) or ("猜测 " .. tostring(CFG.speedHint)), CFG.gravity))
    return true
  end,
  -- 边打边学：开枪 3~5 次，脚本从真实子弹里量弹速和重力
  learn = function(sec)
    sec = tonumber(sec) or 10
    print(string.format("[bullet] 开始学习枪械参数 %d 秒：现在开 3~5 枪（打地面也算）", sec))
    local function done()
      print(string.format("[bullet] 学到 弹速=%.0f 重力=%.0f（样本 %d/%d）",
        bulletSpeed(), bulletGravity(), #SPEED.samples, #GRAV.samples))
      refreshUI()
    end
    if task and task.spawn then
      task.spawn(function()
        local t0 = now()
        while now() - t0 < sec do task.wait(0.2) end
        done()
      end)
    else
      done()
    end
    return sec
  end,
  solve = solveIntercept,
  aim = function() return S.aim, S.tof end,
  dump = function()
    print(string.format(
      "[bullet] 框架=%s 模式=%s(实际=%s) 目标=%s 弹速=%s 重力=%.0f 飞行=%.3fs 锁定=%d 帧=%d 错误=%d",
      S.framework, CFG.mode, S.mode, S.target and S.target.plr.Name or "无",
      bulletSpeed() > 0 and string.format("%.0f", bulletSpeed()) or "hitscan",
      bulletGravity(), S.tof, S.locks, S.frames, S.errors))
    if S.target and S.aim then
      local d = (S.aim - S.target.part.Position).Magnitude
      print(string.format("[bullet] 目标位置与提前点相差 %.1f studs（下坠补偿 %.1f）",
        d, math.abs(S.aim.Y - S.target.part.Position.Y)))
    end
    return { mode = S.mode, speed = bulletSpeed(), tof = S.tof, locks = S.locks }
  end,
}

API.unload = function()
  if loopConn then
    if loopBound then
      pcall(function() RunService:UnbindFromRenderStep("RbxBulletTrackStep") end)
    else
      pcall(function() loopConn:Disconnect() end)
    end
    loopConn, loopBound = nil, false
  end
  hidePath()
  for i = 1, #pathParts do
    if pathParts[i] then pcall(function() pathParts[i]:Destroy() end); pathParts[i] = nil end
  end
  if fxFolder then pcall(function() fxFolder:Destroy() end); fxFolder = nil end
  if ui.gui then pcall(function() ui.gui:Destroy() end); ui.gui = nil end
  marker, fovRing, btn = nil, nil, nil
  cur, S.target, S.aim = nil, nil, nil
  for k in pairs(watching) do watching[k] = nil end
  print("[bullet] 已卸载")
end

ENV.Bullet = API
_G.Bullet = API

--== 11. 启动 ====================================================
S.lastScan = -1e9
S.framework = detectFramework()
if type(ENV.GunProfile) == "table" then
  API.applyProfile(ENV.GunProfile)
end
buildUI()
startLoop()
pcall(scanBullets, 1200)
refreshUI()

do
  local ex = "unknown"
  if CAP.execName then
    local ok, v = pcall(CAP.execName)
    if ok and type(v) == "string" then ex = v end
  end
  print(string.format("[bullet] 已加载 | %s | 框架=%s | 模式=%s | 弹速=%s | 无钩子/无 remote 改写",
    ex, S.framework, CFG.mode,
    bulletSpeed() > 0 and string.format("%.0f", bulletSpeed()) or "未采到(按 hitscan)"))
  print("[bullet] 弹速/重力不准就跑 gun_probe.lua，或 Bullet.learn(10) 边打边学")
  print("[bullet] 点按钮=开关 / 长按=切模式 / Bullet.calibrate() 采样 / Bullet.unload() 卸载")
end
