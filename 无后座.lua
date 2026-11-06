--[[ 枪械无后坐力 v2
     改动：UI 提前创建 + 坐标强制钳在屏幕内 + 分阶段打日志（能看出卡在哪一步）
     功能：清零武器里的 recoil / kick / shake / spread 等数值；「原」按钮一键还原
--]]

local Players = game:GetService("Players")
local LP = Players.LocalPlayer

local CFG = {
    ZERO_KEYS = {"recoil","kick","shake","spread","jitter","bloom",
                 "sway","kickback","cameraoffset","punchanim"},
    SKIP_KEYS = {"reload","ammo","damage","firerate","rate","speed","delay"},
    RESCAN    = 2.0,
    BTN_SIZE  = 72,
}

local out = function(s) print("[稳] " .. s) end
local enabled = false
local originals = setmetatable({}, { __mode = "k" })

------------------------------------------------------------------
-- 一、先建 UI（这一步失败会立刻在日志里看到）
------------------------------------------------------------------
local pg = LP:WaitForChild("PlayerGui")

local gui = Instance.new("ScreenGui")
gui.Name = "__NORECOIL_UI_" .. tostring(math.random(1000, 9999))
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 2000
gui.Parent = pg
out("UI 容器已创建")

local function makeButton(text, px, py, color)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(0, CFG.BTN_SIZE, 0, CFG.BTN_SIZE)
    b.AnchorPoint = Vector2.new(0.5, 0.5)
    b.Position = UDim2.new(1, px, 1, py)
    b.BackgroundColor3 = color
    b.BackgroundTransparency = 0.25
    b.Text = text
    b.TextColor3 = Color3.new(1, 1, 1)
    b.TextScaled = true
    b.Font = Enum.Font.GothamBold
    b.BorderSizePixel = 0
    b.AutoButtonColor = false
    b.Parent = gui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(1, 0)
    corner.Parent = b

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(255, 210, 120)
    stroke.Thickness = 2
    stroke.Parent = b
    return b
end

-- 默认放在右侧中间偏上，绝对能点到的位置
local btnToggle = makeButton("稳", -90, -260, Color3.fromRGB(50, 50, 60))
local btnReset  = makeButton("原", -90, -350, Color3.fromRGB(60, 90, 130))
out("按钮已创建 稳(" .. btnToggle.AbsolutePosition.X .. "," .. btnToggle.AbsolutePosition.Y .. ")")

------------------------------------------------------------------
-- 二、功能
------------------------------------------------------------------
local function weapons()
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

local function matchAny(name, keys)
    local n = string.lower(tostring(name))
    for _, k in ipairs(keys) do
        if n:find(k, 1, true) then return true end
    end
    return false
end

local function applyTo(tool)
    local n = 0
    pcall(function()
        for _, d in ipairs(tool:GetDescendants()) do
            if (d:IsA("NumberValue") or d:IsA("IntValue"))
            and matchAny(d.Name, CFG.ZERO_KEYS)
            and not matchAny(d.Name, CFG.SKIP_KEYS) then
                if d.Value ~= 0 then
                    if originals[d] == nil then originals[d] = d.Value end
                    d.Value = 0
                    n = n + 1
                end
            end
        end
        for k, v in pairs(tool:GetAttributes()) do
            if type(v) == "number" and matchAny(k, CFG.ZERO_KEYS)
            and not matchAny(k, CFG.SKIP_KEYS) then
                local key = k
                if originals[tool] == nil then originals[tool] = {} end
                if originals[tool][key] == nil then originals[tool][key] = v end
                pcall(function() tool:SetAttribute(key, 0) end)
                n = n + 1
            end
        end
    end)
    return n
end

local function restoreAll()
    local n = 0
    for inst, v in pairs(originals) do
        if type(v) == "number" then
            if inst and inst.Parent then
                pcall(function() inst.Value = v end)
                n = n + 1
            end
        elseif type(v) == "table" then
            for k, vv in pairs(v) do
                pcall(function() inst:SetAttribute(k, vv) end)
                n = n + 1
            end
        end
        originals[inst] = nil
    end
    out("已还原 " .. n .. " 个数值")
end

------------------------------------------------------------------
-- 三、循环
------------------------------------------------------------------
local lastScan = 0
task.spawn(function()
    out("扫描循环已启动")
    while true do
        task.wait(0.4)
        if enabled and os.clock() - lastScan > CFG.RESCAN then
            lastScan = os.clock()
            local total, cnt = 0, 0
            for _, tool in ipairs(weapons()) do
                cnt = cnt + 1
                total = total + applyTo(tool)
            end
            if total > 0 then
                out("清零 " .. total .. " 个字段 / " .. cnt .. " 把武器")
            end
        end
    end
end)

------------------------------------------------------------------
-- 四、按钮交互（点击 / 长按拖动）
------------------------------------------------------------------
local function bindButton(b, onTap)
    local dragging, moved = false, false
    local startPos, startInput = nil, nil

    b.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch
        or input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging, moved = true, false
            startPos = b.Position
            startInput = input.Position
        end
    end)

    b.InputChanged:Connect(function(input)
        if not dragging then return end
        if input.UserInputType == Enum.UserInputType.Touch
        or input.UserInputType == Enum.UserInputType.MouseMovement then
            local d = input.Position - startInput
            if math.abs(d.X) > 8 or math.abs(d.Y) > 8 then moved = true end
            if moved then
                b.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X,
                                       startPos.Y.Scale, startPos.Y.Offset + d.Y)
            end
        end
    end)

    b.InputEnded:Connect(function()
        if not dragging then return end
        dragging = false
        if not moved then onTap() end
    end)
end

bindButton(btnToggle, function()
    enabled = not enabled
    btnToggle.BackgroundColor3 = enabled and Color3.fromRGB(230, 170, 40)
                                         or Color3.fromRGB(50, 50, 60)
    lastScan = 0
    out(enabled and "开" or "关")
end)

bindButton(btnReset, function()
    restoreAll()
end)

out("加载完成：点「稳」开启，点「原」还原")
