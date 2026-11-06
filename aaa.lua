--[[ 射速 v3 · 严格关键词 + 一键还原
     v2 仍然影响换弹，原因是改了通用名（cooldown / delay / interval）
     很多游戏用同一个值同时控制开火间隔和换弹间隔 → 一改全乱
     v3：
       1) 只改名字里明确带 fire/shoot/shot/rpm 的字段，通用名一律不碰
       2) 改之前先记下原值，点「原」按钮一键还原，换弹立刻恢复
--]]

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local LP = Players.LocalPlayer

local CFG = {
    MODE         = "config",     -- config / hold / toggle
    RPS          = 12,
    RPS_MAX      = 30,

    APPLY_CONFIG = true,
    COOLDOWN_MUL = 0.2,
    FIRERATE_MUL = 4,
    CONFIG_MAX   = 1200,

    -- 只认这些（必须带开火语义）
    COOLDOWN_KEYS = {"firedelay","firerate_delay","shotdelay","shootdelay",
                     "fireinterval","shotinterval","firecooldown","shotcooldown"},
    RATE_KEYS     = {"firerate","fire_rate","rateoffire","rounds","rps","rpm"},

    FIRE_KEYS     = {"fire","shoot","开火","射击","attack","trigger"},
    REMOTE_KEYS   = {"shoot","fire","bullet","gun","shot","attack","weapon"},

    BTN_SIZE      = 68,
    POS           = { X = -86, Y = -310 },
    RESET_POS     = { X = -86, Y = -390 },
    SAVE_FILE     = "gen4_ui_pos.txt",
}

local out = function(s) print("[射速] " .. s) end
local enabled = false
local firing = false

-- ===== 位置存档 =====
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

local pg = LP:WaitForChild("PlayerGui")

local function equippedTool()
    local char = LP.Character
    if not char then return nil end
    for _, t in ipairs(char:GetChildren()) do
        if t:IsA("Tool") then return t end
    end
    return nil
end

-- ===== 原值快照 =====
local originals = setmetatable({}, { __mode = "k" })
local modifiedNames = {}

local function setNumber(inst, newVal, label)
    local ok, old = pcall(function() return inst.Value end)
    if not ok then return false end
    if originals[inst] == nil then originals[inst] = old end
    pcall(function() inst.Value = newVal end)
    if label and not modifiedNames[label] then
        modifiedNames[label] = true
        out("改: " .. label .. "  " .. tostring(math.floor(old * 100) / 100) ..
            " → " .. tostring(math.floor(newVal * 100) / 100))
    end
    return true
end

local function matchAny(name, keys)
    local n = string.lower(tostring(name))
    for _, k in ipairs(keys) do
        if n:find(k, 1, true) then return true end
    end
    return false
end

local function applyConfig(tool)
    if not CFG.APPLY_CONFIG or not tool then return 0 end
    local cnt = 0
    pcall(function()
        for _, d in ipairs(tool:GetDescendants()) do
            if d:IsA("NumberValue") then
                local nm = d.Name
                if not string.lower(nm):find("reload", 1, true) then
                    if matchAny(nm, CFG.COOLDOWN_KEYS) and d.Value > 0 then
                        if setNumber(d, math.max(0.01, d.Value * CFG.COOLDOWN_MUL), d:GetFullName()) then
                            cnt = cnt + 1
                        end
                    elseif matchAny(nm, CFG.RATE_KEYS) and d.Value > 0 then
                        if setNumber(d, math.min(CFG.CONFIG_MAX, d.Value * CFG.FIRERATE_MUL), d:GetFullName()) then
                            cnt = cnt + 1
                        end
                    end
                end
            end
        end
    end)
    return cnt
end

-- 一键还原
local function restoreAll()
    local n = 0
    for inst, v in pairs(originals) do
        if inst and inst.Parent then
            if pcall(function() inst.Value = v end) then n = n + 1 end
        end
        originals[inst] = nil
    end
    modifiedNames = {}
    out("已还原 " .. n .. " 个数值，换弹应恢复")
end

-- ===== 按住检测 =====
local function objectsAt(pos)
    local list = {}
    pcall(function()
        for _, o in ipairs(pg:GetGuiObjectsAtPosition(pos.X, pos.Y)) do
            list[#list + 1] = o
        end
    end)
    return list
end

local function matchFire(obj)
    local text = string.lower(tostring(obj.Name or ""))
    if obj:IsA("TextButton") or obj:IsA("ImageButton") then
        pcall(function() text = text .. " " .. string.lower(tostring(obj.Text or "")) end)
    end
    return matchAny(text, CFG.FIRE_KEYS)
end

local UIS = game:GetService("UserInputService")
local heldInput = nil

UIS.InputBegan:Connect(function(input, processed)
    if not (input.UserInputType == Enum.UserInputType.Touch
    or input.UserInputType == Enum.UserInputType.MouseButton1) then return end
    if processed then
        for _, o in ipairs(objectsAt(input.Position)) do
            if matchFire(o) then firing, heldInput = true, input; return end
        end
    else
        firing, heldInput = true, input
    end
end)

UIS.InputEnded:Connect(function(input)
    if heldInput and input == heldInput then firing, heldInput = false, nil end
end)

-- ===== 主循环 =====
local lastCfg = 0
task.spawn(function()
    while true do
        local step = 1 / math.clamp(CFG.RPS, 1, CFG.RPS_MAX)
        if enabled then
            local tool = equippedTool()
            if tool then
                if os.clock() - lastCfg > 3 then
                    lastCfg = os.clock()
                    applyConfig(tool)
                end
                local shouldFire = false
                if CFG.MODE == "toggle" then shouldFire = true
                elseif CFG.MODE == "hold" then
                    shouldFire = firing or UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
                end
                if shouldFire then pcall(function() tool:Activate() end) end
            end
        end
        task.wait(step)
    end
end)

-- ===== UI =====
local gui = Instance.new("ScreenGui")
gui.Name = "__FIRE_BTN"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 996
gui.Parent = pg

local function makeCircle(key, text, defaultPos, color, onTap)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(0, CFG.BTN_SIZE, 0, CFG.BTN_SIZE)
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

    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1, 0); c.Parent = b
    local s = Instance.new("UIStroke"); s.Color = Color3.fromRGB(255, 200, 90); s.Thickness = 2; s.Parent = b

    if positions[key] then
        b.Position = UDim2.new(1, positions[key].X, 1, positions[key].Y)
    else
        positions[key] = { X = defaultPos.X, Y = defaultPos.Y }
        b.Position = UDim2.new(1, defaultPos.X, 1, defaultPos.Y)
    end

    local dragging, moved, startPos, startInput = false, false, nil, nil

    b.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch
        or input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging, moved = true, false
            startPos, startInput = b.Position, input.Position
            s.Color = Color3.fromRGB(120, 255, 120)
        end
    end)
    b.InputChanged:Connect(function(input)
        if not dragging then return end
        if input.UserInputType == Enum.UserInputType.Touch
        or input.UserInputType == Enum.UserInputType.MouseMovement then
            local d = input.Position - startInput
            if math.abs(d.X) > 6 or math.abs(d.Y) > 6 then moved = true end
            if moved then
                b.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X,
                                       startPos.Y.Scale, startPos.Y.Offset + d.Y)
            end
        end
    end)
    b.InputEnded:Connect(function()
        if not dragging then return end
        dragging = false
        s.Color = Color3.fromRGB(255, 200, 90)
        if moved then
            local vp = workspace.CurrentCamera.ViewportSize
            local ap, sz = b.AbsolutePosition, b.AbsoluteSize
            positions[key] = { X = math.floor(ap.X + sz.X / 2 - vp.X),
                               Y = math.floor(ap.Y + sz.Y / 2 - vp.Y) }
            b.Position = UDim2.new(1, positions[key].X, 1, positions[key].Y)
            savePos()
        else
            onTap(b)
        end
    end)
    return b
end

local fireBtn = makeCircle("fire", "射", CFG.POS, Color3.fromRGB(50, 50, 60), function(b)
    enabled = not enabled
    b.BackgroundColor3 = enabled and Color3.fromRGB(230, 140, 30) or Color3.fromRGB(50, 50, 60)
    if enabled then
        local tool = equippedTool()
        local n = tool and applyConfig(tool) or 0
        out("开启 模式=" .. CFG.MODE .. " 修改=" .. n)
    else
        out("关闭")
    end
end)

makeCircle("fireReset", "原", CFG.RESET_POS, Color3.fromRGB(60, 90, 130), function()
    restoreAll()
end)

out("已加载：点「射」开，点「原」还原所有改过的数值")
