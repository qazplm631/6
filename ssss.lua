--[[ 无限子弹 · 独立版
     关键：弹匣和备弹分开处理
       备弹（reserve/spare/total...）默认锁满 → 换弹永远有货
       弹匣默认不动（AMMO_MAG_MODE = "off"）→ 保留游戏正常扣弹逻辑，伤害不受影响
     想连射不换弹再改成 "low"（打空才补）或 "lock"（每帧锁满，可能吞伤害）
--]]

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local LP = Players.LocalPlayer

local CFG = {
    AMMO_MAG_MODE = "off",   -- off / low / lock
    AMMO_RESERVE  = true,    -- 备弹锁满
    AMMO_LOW_MARK = 5,       -- low 模式：低于这个值才补
    OFF_RESERVE   = false,   -- true = 备弹也不动，只处理弹匣

    BTN_SIZE  = 68,
    POS       = { X = -86, Y = -310 },
    SAVE_FILE = "gen4_ui_pos.txt",
}

local out = function(s) print("[弹] " .. s) end
local enabled = false

local RESERVE_KEYS = {"reserve","spare","backup","total","pool","storage","carry"}
local MAG_KEYS     = {"mag","magazine","clip","ammo","bullet","rounds","current","inmag"}
local SKIP_KEYS    = {"reload","time","delay","speed","rate","damage","max"}

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

local function matchAny(name, keys)
    local n = string.lower(tostring(name))
    for _, k in ipairs(keys) do
        if n:find(k, 1, true) then return true end
    end
    return false
end

local function equippedTool()
    local char = LP.Character
    if not char then return nil end
    for _, t in ipairs(char:GetChildren()) do
        if t:IsA("Tool") then return t end
    end
    return nil
end

local function guessMax(d)
    local mx = math.max(d.Value, 30)
    pcall(function()
        local a = d:GetAttribute("Max") or d:GetAttribute("MaxAmmo")
        if type(a) == "number" and a > 0 then mx = a end
        local parent = d.Parent
        if parent then
            for _, cand in ipairs({d.Name .. "Max", "Max" .. d.Name, "Capacity", "MaxAmmo"}) do
                local sib = parent:FindFirstChild(cand)
                if sib and (sib:IsA("NumberValue") or sib:IsA("IntValue")) and sib.Value > 0 then
                    mx = sib.Value
                end
            end
        end
    end)
    return mx
end

local mod = { mag = {}, res = {}, scanned = nil, lastScan = 0 }

local function scan(tool)
    mod.mag, mod.res = {}, {}
    if not tool then return 0, 0 end
    local nm, nr = 0, 0
    pcall(function()
        for _, d in ipairs(tool:GetDescendants()) do
            if (d:IsA("NumberValue") or d:IsA("IntValue")) and not matchAny(d.Name, SKIP_KEYS) then
                local mx = guessMax(d)
                if matchAny(d.Name, RESERVE_KEYS) then
                    mod.res[#mod.res + 1] = { inst = d, max = mx }
                    nr = nr + 1
                elseif matchAny(d.Name, MAG_KEYS) then
                    mod.mag[#mod.mag + 1] = { inst = d, max = mx }
                    nm = nm + 1
                end
            end
        end
    end)
    return nm, nr
end

RunService.Heartbeat:Connect(function()
    if not enabled then return end
    local tool = equippedTool()
    if tool ~= mod.scanned or os.clock() - mod.lastScan > 1 then
        mod.scanned = tool
        mod.lastScan = os.clock()
        scan(tool)
    end

    if CFG.AMMO_RESERVE and not CFG.OFF_RESERVE then
        for _, L in ipairs(mod.res) do
            if L.inst.Parent and L.inst.Value < L.max then
                pcall(function() L.inst.Value = L.max end)
            end
        end
    end

    if CFG.AMMO_MAG_MODE == "lock" then
        for _, L in ipairs(mod.mag) do
            if L.inst.Parent and L.inst.Value < L.max then
                pcall(function() L.inst.Value = L.max end)
            end
        end
    elseif CFG.AMMO_MAG_MODE == "low" then
        for _, L in ipairs(mod.mag) do
            if L.inst.Parent and L.inst.Value <= CFG.AMMO_LOW_MARK then
                pcall(function() L.inst.Value = L.max end)
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
            mod.scanned = nil
            local tool = equippedTool()
            local a, b = 0, 0
            if tool then a, b = scan(tool) end
            out("开 弹匣=" .. CFG.AMMO_MAG_MODE .. " 备弹=" .. tostring(CFG.AMMO_RESERVE) ..
                " (弹匣" .. a .. " 备弹" .. b .. ")")
        else
            out("关")
        end
    end
end)

out("已加载：默认只锁备弹，弹匣不动（保证伤害正常）")
