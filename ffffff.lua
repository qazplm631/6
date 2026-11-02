--[[ 自动铐人 v6 · 手机版（按钮可自由拖动，松手立即保存位置）
     操作：
       轻点「铐」   = 立即尝试铐最近目标（不会自己动）
       轻点「自」   = 开/关自动模式
       长按按钮拖动 = 换位置，松手马上写入，不用重开脚本
     时序完全复刻真人：InputHoldBegin → 等官方读条 → InputHoldEnd
--]]

local Players = game:GetService("Players")
local UIS     = game:GetService("UserInputService")
local LP = Players.LocalPlayer

local CONFIG = {
    AUTO_START    = false,       -- 进图是否直接开自动
    DIST          = 8,
    HOLD_EXTRA    = 0.10,
    COOLDOWN      = 0.5,        -- 统一冷却 0.5 秒
    MAX_ATTEMPTS  = nil,        -- nil = 无限次；填数字则封顶
    ONLY_WANTED   = false,
    PROMPT_KEYS   = {"arrest","cuff","handcuff","restrain","铐","逮捕"},
    VERBOSE       = true,

    BTN_SIZE      = 68,
    POS_A         = { X = -86, Y = -150 },   -- 相对屏幕右下角的偏移
    POS_B         = { X = -86, Y = -70 },
    SAVE_FILE     = "gen4_ui_pos.txt",
}

local out = function(s) print("[铐] " .. s) end
local autoMode = CONFIG.AUTO_START

-- ===== 位置存储 =====
local positions = _G.__gen4UIPos or {}
_G.__gen4UIPos = positions

local function loadPositions()
    pcall(function()
        if type(isfile) == "function" and type(readfile) == "function"
        and isfile(CONFIG.SAVE_FILE) then
            for line in string.gmatch(readfile(CONFIG.SAVE_FILE), "[^\n]+") do
                local name, x, y = string.match(line, "([^|]+)|(%-?%d+)|(%-?%d+)")
                if name and x and y then
                    positions[name] = { X = tonumber(x), Y = tonumber(y) }
                end
            end
        end
    end)
end

local function savePositions()
    local lines = {}
    for k, v in pairs(positions) do
        lines[#lines + 1] = string.format("%s|%d|%d", k, v.X, v.Y)
    end
    pcall(function()
        if type(writefile) == "function" then
            writefile(CONFIG.SAVE_FILE, table.concat(lines, "\n"))
        end
    end)
end

-- 把坐标钳在屏幕内，避免拖丢
local function clampOffset(key, size)
    local vp = workspace.CurrentCamera.ViewportSize
    local half = (size or CONFIG.BTN_SIZE) / 2
    local p = positions[key]
    if not p then return end
    local minX = math.floor(half + 4 - vp.X)
    local maxX = math.floor(-half - 4)
    local minY = math.floor(half + 4 - vp.Y)
    local maxY = math.floor(-half - 4)
    p.X = math.clamp(p.X, minX, maxX)
    p.Y = math.clamp(p.Y, minY, maxY)
end

loadPositions()

-- ===== 提示条 =====
local function isArrestPrompt(p)
    local n = string.lower(p.Name)
    for _, k in ipairs(CONFIG.PROMPT_KEYS) do
        if n:find(k, 1, true) then return true end
    end
    return false
end

local function collect()
    local list = {}
    pcall(function()
        for _, d in ipairs(workspace:GetDescendants()) do
            if d:IsA("ProximityPrompt") and isArrestPrompt(d) then
                local model = d:FindFirstAncestorOfClass("Model")
                if model and model:FindFirstChildOfClass("Humanoid") and model ~= LP.Character then
                    list[#list + 1] = { prompt = d, model = model }
                end
            end
        end
    end)
    return list
end

-- ===== 通缉 =====
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
local function isWanted(plr)
    if not plr or plr == LP then return false end
    for k, v in pairs(plr:GetAttributes()) do
        if matchName(k) and truthy(v) then return true end
    end
    for _, c in ipairs({"PlayerData","leaderstats","Stats","Values","Data"}) do
        local cc = plr:FindFirstChild(c)
        if cc and scanContainer(cc) then return true end
    end
    local char = plr.Character
    if char then
        for k, v in pairs(char:GetAttributes()) do
            if matchName(k) and truthy(v) then return true end
        end
        if scanContainer(char) then return true end
    end
    return false
end

-- ===== 快照 =====
local function snapshot(model)
    local t = {}
    for k, v in pairs(model:GetAttributes()) do t[k] = v end
    local hum = model:FindFirstChildOfClass("Humanoid")
    if hum then t.__ws, t.__ps, t.__hp = hum.WalkSpeed, hum.PlatformStand, hum.Health end
    if model.Parent then t.__parent = model.Parent.Name end
    return t
end
local function diff(a, b)
    for k, v in pairs(a) do if b[k] ~= v then return k end end
    for k, v in pairs(b) do if a[k] ~= v then return k end end
    return nil
end

local attempts, lastTry, busy = 0, 0, false

local function describePrompt(p, dist)
    local hold, en, maxd, los = "?", "?", "?", "?"
    pcall(function() hold = tostring(p.HoldDuration) end)
    pcall(function() en   = tostring(p.Enabled) end)
    pcall(function() maxd = tostring(p.MaxActivationDistance) end)
    pcall(function() los  = tostring(p.RequiresLineOfSight) end)
    return string.format("Hold=%s Enabled=%s MaxDist=%s LOS=%s 实距=%.1f",
        hold, en, maxd, los, dist or -1)
end

local function tryOnce(fromAuto)
    if busy then return end
    local myRoot = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
    if not myRoot then out("无角色") return end
    if fromAuto and os.clock() - lastTry < CONFIG.COOLDOWN then return end
    if not fromAuto and os.clock() - lastTry < CONFIG.COOLDOWN then return end
    if CONFIG.MAX_ATTEMPTS and attempts >= CONFIG.MAX_ATTEMPTS then
        out("已达上限 " .. CONFIG.MAX_ATTEMPTS .. "，请重开脚本")
        return
    end

    local best, bd = nil, math.huge
    for _, item in ipairs(collect()) do
        local root = item.model:FindFirstChild("HumanoidRootPart")
        if root then
            local d = (root.Position - myRoot.Position).Magnitude
            if d <= CONFIG.DIST and d < bd then
                local plr = Players:GetPlayerFromCharacter(item.model)
                if (not CONFIG.ONLY_WANTED) or isWanted(plr) then
                    best, bd = item, d
                end
            end
        end
    end

    if not best then out("附近没有可铐目标（" .. CONFIG.DIST .. " 内）") return end

    busy, lastTry = true, os.clock()
    attempts = attempts + 1

    local p = best.prompt
    if CONFIG.VERBOSE then
        out("目标 " .. best.model.Name .. " | " .. describePrompt(p, bd))
    end

    local hold = 0
    pcall(function()
        if type(p.HoldDuration) == "number" then hold = p.HoldDuration end
    end)

    local before = snapshot(best.model)
    local okBegin = pcall(function() p:InputHoldBegin() end)
    task.wait(math.max(hold, 0) + CONFIG.HOLD_EXTRA)
    local okEnd = pcall(function() p:InputHoldEnd() end)
    busy = false

    out(string.format("按住 %.2fs (begin=%s end=%s)", hold, tostring(okBegin), tostring(okEnd)))

    task.delay(1.0, function()
        local after = snapshot(best.model)
        local k = diff(before, after)
        if k then out("成功：变化 " .. tostring(k)) else out("无变化（服务端未接受）") end
    end)
end

-- ===== UI =====
local pg = LP:WaitForChild("PlayerGui")
local gui = Instance.new("ScreenGui")
gui.Name = "__ARREST_BTN"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 997
gui.Parent = pg

-- 可拖动按钮：长按拖动、松手立即保存、点击触发回调
local function makeButton(key, text, defaultPos, color, onClick)
    local b = Instance.new("TextButton")
    b.Name = key
    b.Size = UDim2.new(0, CONFIG.BTN_SIZE, 0, CONFIG.BTN_SIZE)
    b.AnchorPoint = Vector2.new(0.5, 0.5)
    b.BackgroundColor3 = color
    b.BackgroundTransparency = 0.3
    b.TextColor3 = Color3.new(1, 1, 1)
    b.Text = text
    b.TextScaled = true
    b.Font = Enum.Font.GothamBold
    b.BorderSizePixel = 0
    b.AutoButtonColor = false
    b.Parent = gui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(1, 0)
    corner.Parent = b

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(255, 90, 90)
    stroke.Thickness = 2
    stroke.Parent = b

    -- 位置：有存档用存档，否则用默认；都按右下角为基准
    clampOffset(key, CONFIG.BTN_SIZE)
    if positions[key] then
        b.Position = UDim2.new(1, positions[key].X, 1, positions[key].Y)
    else
        positions[key] = { X = defaultPos.X, Y = defaultPos.Y }
        b.Position = UDim2.new(1, defaultPos.X, 1, defaultPos.Y)
    end

    local dragging, moved = false, false
    local startPos, startInput = nil, nil

    b.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch
        or input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging, moved = true, false
            startPos = b.Position
            startInput = input.Position
            stroke.Color = Color3.fromRGB(120, 255, 120)   -- 按下变绿：可拖
        end
    end)

    b.InputChanged:Connect(function(input)
        if not dragging then return end
        if input.UserInputType == Enum.UserInputType.Touch
        or input.UserInputType == Enum.UserInputType.MouseMovement then
            local delta = input.Position - startInput
            if math.abs(delta.X) > 6 or math.abs(delta.Y) > 6 then moved = true end
            if moved then
                b.Position = UDim2.new(
                    startPos.X.Scale, startPos.X.Offset + delta.X,
                    startPos.Y.Scale, startPos.Y.Offset + delta.Y)
            end
        end
    end)

    b.InputEnded:Connect(function()
        if not dragging then return end
        dragging = false
        stroke.Color = Color3.fromRGB(255, 90, 90)

        if moved then
            -- 松手立即换算成「右下角偏移」并写入，不用重开脚本
            local vp = workspace.CurrentCamera.ViewportSize
            local ap = b.AbsolutePosition
            local sz = b.AbsoluteSize
            positions[key] = {
                X = math.floor(ap.X + sz.X / 2 - vp.X),
                Y = math.floor(ap.Y + sz.Y / 2 - vp.Y),
            }
            clampOffset(key, CONFIG.BTN_SIZE)
            b.Position = UDim2.new(1, positions[key].X, 1, positions[key].Y)
            savePositions()
            out("位置已保存 " .. key .. " (" .. positions[key].X .. ", " .. positions[key].Y .. ")")
        else
            onClick()
        end
    end)

    return b
end

local btnCuff = makeButton("cuff", "铐", CONFIG.POS_A,
    Color3.fromRGB(200, 40, 40), function() tryOnce(false) end)

local btnAuto = makeButton("auto", "自", CONFIG.POS_B,
    autoMode and Color3.fromRGB(200, 40, 40) or Color3.fromRGB(50, 50, 60),
    function()
        autoMode = not autoMode
        btnAuto.BackgroundColor3 = autoMode and Color3.fromRGB(200, 40, 40)
                                            or Color3.fromRGB(50, 50, 60)
        out(autoMode and "自动模式: 开" or "自动模式: 关")
    end)

-- ===== 自动循环 =====
task.spawn(function()
    while true do
        task.wait(0.2)          -- 轮询更密，实际节奏由 COOLDOWN 决定
        if autoMode then tryOnce(true) end
    end
end)

-- 键盘备用
UIS.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.KeyCode == Enum.KeyCode.H then tryOnce(false) end
end)

-- ===== 状态 =====
task.spawn(function()
    task.wait(6)
    while true do
        local cap = CONFIG.MAX_ATTEMPTS and tostring(CONFIG.MAX_ATTEMPTS) or "∞"
        out(string.format("提示条 %d 个 | 已尝试 %d/%s | 自动 %s",
            #collect(), attempts, cap, autoMode and "开" or "关"))
        task.wait(15)
    end
end)

out("长按按钮可拖动，松手立即保存位置")
