--[[ 无限子弹 Infinite Ammo
     做法：锁住武器里的弹药数值（当前弹匣 / 备弹），打了立刻回满
     不碰任何 reload / time 相关字段，避免影响换弹流程
     手机：右下角「弹」按钮开关，长按可拖动
--]]

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local LP = Players.LocalPlayer

local CFG = {
    AMMO_KEYS = {"ammo","bullet","magazine","mag","clip","reserve","rounds","count"},
    SKIP_KEYS = {"reload","time","delay","speed","rate","damage"},
    FALLBACK  = 999,       -- 找不到上限时填这个
    POLL      = 0.5,       -- 重新扫描武器的间隔
    BTN_SIZE  = 68,
    POS       = { X = -86, Y = -310 },
    SAVE_FILE = "gen4_ui_pos.txt",
}

local out = function(s) print("[弹] " .. s) end
local enabled = false

-- ===== 位置 =====
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

-- ===== 工具 =====
local function equippedTool()
    local char = LP.Character
    if not char then return nil end
    for _, t in ipairs(char:GetChildren()) do
        if t:IsA("Tool") then return t end
    end
    return nil
end

local function hit(name, keys)
    local n = string.lower(tostring(name))
    for _, k in ipairs(keys) do
        if n:find(k, 1, true) then return true end
    end
    return false
end

-- ===== 锁定表 =====
local locks = {}   -- { {inst=?, max=number} }
local scannedTool = nil
local lastScan = 0

local function guessMax(inst)
    -- 1) 属性
    for _, k in ipairs({"Max","MaxAmmo","AmmoMax","Capacity","MagSize"}) do
        local ok, v = pcall(function() return inst:GetAttribute(k) end)
        if ok and type(v) == "number" and v > 0 then return v end
    end
    -- 2) 兄弟节点同名 + Max
    local parent = inst.Parent
    if parent then
        for _, cand in ipairs({inst.Name .. "Max", inst.Name .. "_Max", "Max" .. inst.Name,
                               "MaxAmmo", "Max", "Capacity"}) do
            local sib = parent:FindFirstChild(cand)
            if sib and (sib:IsA("NumberValue") or sib:IsA("IntValue")) then
                if sib.Value > 0 then return sib.Value end
            end
        end
    end
    -- 3) 记住历史最大值
    return math.max(inst.Value, CFG.FALLBACK)
end

local function scan(tool)
    locks = {}
    if not tool then return 0 end
    local n = 0
    pcall(function()
        for _, d in ipairs(tool:GetDescendants()) do
            if (d:IsA("NumberValue") or d:IsA("IntValue"))
            and hit(d.Name, CFG.AMMO_KEYS) and not hit(d.Name, CFG.SKIP_KEYS) then
                locks[#locks + 1] = { inst = d, max = guessMax(d) }
                n = n + 1
            end
        end
        -- 属性形式的弹药
        for k, v in pairs(tool:GetAttributes()) do
            if type(v) == "number" and hit(k, CFG.AMMO_KEYS) and not hit(k, CFG.SKIP_KEYS) then
                local key = k
                locks[#locks + 1] = { attr = tool, name = key, max = math.max(v, CFG.FALLBACK) }
                n = n + 1
            end
        end
    end)
    return n
end

-- ===== 锁定循环 =====
RunService.Heartbeat:Connect(function()
    if not enabled then return end
    local tool = equippedTool()

    if tool ~= scannedTool or os.clock() - lastScan > CFG.POLL then
        scannedTool = tool
        lastScan = os.clock()
        local n = scan(tool)
        if n > 0 then out("锁定 " .. n .. " 个弹药数值") end
    end

    for _, L in ipairs(locks) do
        if L.inst then
            if L.inst.Parent and L.inst.Value < L.max then
                pcall(function() L.inst.Value = L.max end)
            end
        elseif L.attr then
            local ok, cur = pcall(function() return L.attr:GetAttribute(L.name) end)
            if ok and type(cur) == "number" and cur < L.max then
                pcall(function() L.attr:SetAttribute(L.name, L.max) end)
            end
        end
    end
end)

-- ===== UI =====
local pg = LP:WaitForChild("PlayerGui")
local gui = Instance.new("ScreenGui")
gui.Name = "__AMMO_BTN"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 996
gui.Parent = pg

local btn = Instance.new("TextButton")
btn.Size = UDim2.new(0, CFG.BTN_SIZE, 0, CFG.BTN_SIZE)
btn.AnchorPoint = Vector2.new(0.5, 0.5)
btn.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
btn.BackgroundTransparency = 0.3
btn.TextColor3 = Color3.new(1, 1, 1)
btn.Text = "弹"
btn.TextScaled = true
btn.Font = Enum.Font.GothamBold
btn.BorderSizePixel = 0
btn.AutoButtonColor = false
btn.Parent = gui

local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1, 0); c.Parent = btn
local s = Instance.new("UIStroke"); s.Color = Color3.fromRGB(120, 220, 160); s.Thickness = 2; s.Parent = btn

if positions.ammo then
    btn.Position = UDim2.new(1, positions.ammo.X, 1, positions.ammo.Y)
else
    positions.ammo = { X = CFG.POS.X, Y = CFG.POS.Y }
    btn.Position = UDim2.new(1, CFG.POS.X, 1, CFG.POS.Y)
end

local dragging, moved, startPos, startInput = false, false, nil, nil

btn.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Touch
    or input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging, moved = true, false
        startPos, startInput = btn.Position, input.Position
        s.Color = Color3.fromRGB(120, 255, 120)
    end
end)
btn.InputChanged:Connect(function(input)
    if not dragging then return end
    if input.UserInputType == Enum.UserInputType.Touch
    or input.UserInputType == Enum.UserInputType.MouseMovement then
        local d = input.Position - startInput
        if math.abs(d.X) > 6 or math.abs(d.Y) > 6 then moved = true end
        if moved then
            btn.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X,
                                     startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end
end)
btn.InputEnded:Connect(function()
    if not dragging then return end
    dragging = false
    s.Color = Color3.fromRGB(120, 220, 160)
    if moved then
        local vp = workspace.CurrentCamera.ViewportSize
        local ap, sz = btn.AbsolutePosition, btn.AbsoluteSize
        positions.ammo = { X = math.floor(ap.X + sz.X / 2 - vp.X),
                           Y = math.floor(ap.Y + sz.Y / 2 - vp.Y) }
        btn.Position = UDim2.new(1, positions.ammo.X, 1, positions.ammo.Y)
        savePos()
    else
        enabled = not enabled
        btn.BackgroundColor3 = enabled and Color3.fromRGB(40, 160, 110)
                                       or Color3.fromRGB(50, 50, 60)
        if enabled then
            scannedTool = nil
            out("开启")
        else
            out("关闭")
        end
    end
end)

out("已加载：装备武器后点「弹」开启无限弹药")
