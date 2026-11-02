--[[ 自瞄 v2 · 手机版（修抖动 + 修锁不住）
     抖动根因：游戏摄像机脚本每帧也在写 Camera.CFrame，和我们抢写 → 来回跳
     锁不住根因：用「屏幕像素距离 + onScreen」选目标，镜头一转目标就跑出判定
     修法：① 瞄准期间拦截游戏对 Camera.CFrame 的写入
           ② 恒定角速度转向（不 lerp 到不收敛）
           ③ 目标改用「视线夹角」判定，与屏幕分辨率无关
--]]

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS        = game:GetService("UserInputService")
local Camera     = workspace.CurrentCamera
local LP = Players.LocalPlayer

local CONFIG = {
    -- 手感
    TURN_SPEED   = 900,        -- 度/秒：300 很慢 / 900 平衡 / 1800 硬锁
    FOV_ANGLE    = 12,         -- 视线夹角多少度内的目标可选（不依赖分辨率）
    AIM_PART     = "Head",
    MAX_DIST     = 500,
    STICKY_TIME  = 0.6,        -- 目标粘滞，防跳靶
    HYSTERESIS   = 4,          -- 换目标需要的额外角度优势，防两个目标来回切

    -- 防抖
    BLOCK_CAMERA_WRITES = true,   -- 瞄准时拦截游戏写 Camera.CFrame
    SCRIPTABLE_WHILE_AIM = false, -- 仍抖就改 true（强制接管摄像机）

    -- 目标
    ONLY_WANTED  = true,
    TEAM_CHECK   = true,
    FRIENDLY_TEAMS = {},
    FRIENDLY_NAMES = {},

    -- 按钮
    BTN_TEXT     = "瞄",
    BTN_SIZE     = 90,
    BTN_POS      = UDim2.new(1, -130, 0.62, 0),
}

local out = function(s) print("[AIM2] " .. s) end
local aiming = false

-- ===== 通缉判定 =====
local KEYS = {"wanted","criminal","bounty","suspect","suspicious",
              "heat","stars","通缉","悬赏","罪犯","嫌疑","红名"}
local function matchName(n)
    n = string.lower(tostring(n))
    for _, k in ipairs(KEYS) do if n:find(k, 1, true) then return true end end
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
local function scanContainer(c)
    for _, v in ipairs(c:GetDescendants()) do
        if matchName(v.Name) and (v:IsA("BoolValue") or v:IsA("NumberValue")
           or v:IsA("IntValue") or v:IsA("StringValue")) and truthy(v.Value) then
            return true
        end
    end
    return false
end
local function isWantedModel(model)
    for k, v in pairs(model:GetAttributes()) do
        if matchName(k) and truthy(v) then return true end
    end
    if scanContainer(model) then return true end
    local plr = Players:GetPlayerFromCharacter(model)
    if plr then
        for k, v in pairs(plr:GetAttributes()) do
            if matchName(k) and truthy(v) then return true end
        end
        for _, c in ipairs({"PlayerData","leaderstats","Stats","Values","Data"}) do
            local cc = plr:FindFirstChild(c)
            if cc and scanContainer(cc) then return true end
        end
    end
    return false
end

local function isFriendly(plr)
    if not plr then return false end
    for _, n in ipairs(CONFIG.FRIENDLY_NAMES) do
        if plr.Name == n then return true end
    end
    if plr.Team then
        for _, tn in ipairs(CONFIG.FRIENDLY_TEAMS) do
            if plr.Team.Name == tn then return true end
        end
    end
    if CONFIG.TEAM_CHECK and LP.Team and plr.Team == LP.Team then return true end
    return false
end

-- ===== 候选 =====
local npcCache = {}
task.spawn(function()
    while true do
        local list = {}
        pcall(function()
            for _, m in ipairs(workspace:GetDescendants()) do
                if #list >= 400 then break end
                if m:IsA("Model") and m:FindFirstChildOfClass("Humanoid") then
                    list[#list + 1] = m
                end
            end
        end)
        npcCache = list
        task.wait(1.5)
    end
end)

local function candidates()
    local res = {}
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LP and plr.Character then res[#res + 1] = plr.Character end
    end
    for _, m in ipairs(npcCache) do
        if m ~= LP.Character then res[#res + 1] = m end
    end
    return res
end

-- ===== 角度判定（不依赖屏幕像素）=====
local function angleTo(pos)
    local camCF = Camera.CFrame
    local dir = pos - camCF.Position
    if dir.Magnitude < 0.5 then return 180 end
    local d = camCF.LookVector:Dot(dir.Unit)
    d = math.clamp(d, -1, 1)
    return math.deg(math.acos(d))
end

local function scoreTarget()
    local myRoot = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
    if not myRoot then return nil, nil end
    local best, bestAngle, bestDist = nil, math.huge, math.huge
    for _, model in ipairs(candidates()) do
        local hum = model:FindFirstChildOfClass("Humanoid")
        if hum and hum.Health > 0 then
            local plr = Players:GetPlayerFromCharacter(model)
            if not isFriendly(plr) then
                local wantOk = (not CONFIG.ONLY_WANTED) or isWantedModel(model)
                if wantOk then
                    local part = model:FindFirstChild(CONFIG.AIM_PART)
                        or model:FindFirstChild("Head")
                        or model:FindFirstChild("HumanoidRootPart")
                    if part then
                        local dist = (part.Position - myRoot.Position).Magnitude
                        if dist <= CONFIG.MAX_DIST then
                            local ang = angleTo(part.Position)
                            if ang <= CONFIG.FOV_ANGLE and ang < bestAngle then
                                best, bestAngle, bestDist = part, ang, dist
                            end
                        end
                    end
                end
            end
        end
    end
    return best, bestAngle
end

-- ===== 拦截游戏写 Camera.CFrame =====
if CONFIG.BLOCK_CAMERA_WRITES then
    pcall(function()
        local mt = getrawmetatable(game)
        local oldIndex = mt.__newindex
        setreadonly(mt, false)
        mt.__newindex = newcclosure(function(self, key, value)
            if aiming and not checkcaller()
            and key == "CFrame" and self == workspace.CurrentCamera then
                return            -- 瞄准时摄像机只归我们写
            end
            return oldIndex(self, key, value)
        end)
        setreadonly(mt, true)
        out("摄像机写入拦截已装")
    end)
end

-- ===== UI 按钮 =====
local pg = LP:WaitForChild("PlayerGui")
local gui = Instance.new("ScreenGui")
gui.Name = "__AIMBTN2"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 999
gui.Parent = pg

local btn = Instance.new("TextButton")
btn.Size = UDim2.new(0, CONFIG.BTN_SIZE, 0, CONFIG.BTN_SIZE)
btn.Position = CONFIG.BTN_POS
btn.AnchorPoint = Vector2.new(0.5, 0.5)
btn.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
btn.BackgroundTransparency = 0.35
btn.TextColor3 = Color3.fromRGB(255, 255, 255)
btn.Text = CONFIG.BTN_TEXT
btn.TextScaled = true
btn.Font = Enum.Font.GothamBold
btn.BorderSizePixel = 0
btn.AutoButtonColor = false
btn.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(1, 0)
corner.Parent = btn

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(255, 80, 80)
stroke.Thickness = 2
stroke.Parent = btn

local prevCameraType = nil
local function setAiming(v)
    aiming = v
    btn.BackgroundColor3 = v and Color3.fromRGB(200, 40, 40) or Color3.fromRGB(30, 30, 40)
    if CONFIG.SCRIPTABLE_WHILE_AIM then
        if v then
            prevCameraType = Camera.CameraType
            pcall(function() Camera.CameraType = Enum.CameraType.Scriptable end)
        elseif prevCameraType then
            pcall(function() Camera.CameraType = prevCameraType end)
        end
    end
end

local dragging, dragStart, startPos, moved = false, nil, nil, false

btn.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Touch
    or input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging, moved = true, false
        dragStart = input.Position
        startPos = btn.Position
    end
end)

UIS.InputChanged:Connect(function(input)
    if dragging and input.UserInputType == Enum.UserInputType.Touch then
        local delta = input.Position - dragStart
        if math.abs(delta.X) > 12 or math.abs(delta.Y) > 12 then
            moved = true
            btn.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end
end)

UIS.InputEnded:Connect(function(input)
    if dragging and (input.UserInputType == Enum.UserInputType.Touch
    or input.UserInputType == Enum.UserInputType.MouseButton1) then
        dragging = false
        if not moved then setAiming(not aiming) end
    end
end)

-- ===== 瞄准循环：恒定角速度 =====
local lockedPart, lockedAt, lockedAngle = nil, 0, 180

RunService.RenderStepped:Connect(function(dt)
    if not aiming then return end

    local now = os.clock()
    local needNew = (not lockedPart) or (not lockedPart.Parent)
                    or (now - lockedAt) > CONFIG.STICKY_TIME

    if needNew then
        local newPart, newAngle = scoreTarget()
        -- 粘滞期间换目标需要明显优势，避免来回跳
        if newPart and (not lockedPart or not lockedPart.Parent
        or (newAngle + CONFIG.HYSTERESIS) < lockedAngle) then
            lockedPart, lockedAngle = newPart, newAngle
        end
        lockedAt = now
    end

    if not lockedPart or not lockedPart.Parent then return end

    local camPos = Camera.CFrame.Position
    local toTarget = lockedPart.Position - camPos
    if toTarget.Magnitude < 0.5 then return end
    local targetDir = toTarget.Unit
    local look = Camera.CFrame.LookVector

    local dot = math.clamp(look:Dot(targetDir), -1, 1)
    local angle = math.acos(dot)
    local maxStep = math.rad(CONFIG.TURN_SPEED) * dt
    local t = angle > 1e-4 and math.min(1, maxStep / angle) or 1

    local newDir = look:Lerp(targetDir, t)
    if newDir.Magnitude < 1e-3 then return end
    newDir = newDir.Unit

    pcall(function()
        Camera.CFrame = CFrame.lookAt(camPos, camPos + newDir * 100)
    end)
end)

out("手机版 v2 已加载：点按钮开关")
if CONFIG.SCRIPTABLE_WHILE_AIM then out("摄像机接管模式: 开") end
