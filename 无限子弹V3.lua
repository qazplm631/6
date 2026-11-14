--[[============================================================
  Roblox 无限子弹 —— 手机执行器版
  Roblox 的弹药一般挂在这几种地方：
    · Tool / Backpack / PlayerGui 里的 IntValue、NumberValue（最常见）
    · Tool 的 Attribute（Ammo / Clip 之类）
    · 客户端脚本里的局部变量（这种从外面碰不到，见文末说明）
  脚本做两件事：
    扫描 —— 把所有名字像弹药的数值对象找出来
    冻结/拦截 —— 不让它掉下去（定时写回，或直接吞掉写入）
  适配：Delta / Fluxus / Hydrogen / Cryptic / Ronix / Krnl
  用法：执行后 "AM" 悬浮球；卸载 getgenv().Ammo_Unload()
============================================================]]--

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS        = game:GetService("UserInputService")
local LP         = Players.LocalPlayer

if getgenv and getgenv().Ammo_Unload then pcall(getgenv().Ammo_Unload) end

--============================== 配置 ==============================
local CFG = {
    Enabled   = true,
    Mode      = "Freeze",   -- Freeze（定时写回） | Hook（吞掉写入）
    Full      = true,       -- true = 锁在观察到的满弹值；false = 锁在 Fixed 值
    Fixed     = 999,
    UseAttr   = true,       -- 同时处理 Attribute 形式的弹药
    Debug     = false,
}

local KEYS = {
    "ammo", "clip", "mag", "magazine", "bullet", "rounds", "round",
    "shots", "muni", "reserve", "ammocount", "ammoleft",
    "弹药", "子弹", "弹夹", "弹匣",
}

--=========================== 识别 ================================
local function isAmmoName(name)
    if not name then return false end
    local n = string.lower(name)
    for _, k in ipairs(KEYS) do
        if string.find(n, k, 1, true) then return true end
    end
    return false
end

local targets = {}      -- [instance] = { max = number }
local attrMax = {}      -- 属性形式弹药观察到的最大值

local function countTargets()
    local n = 0
    for _ in pairs(targets) do n = n + 1 end
    return n
end

local function addTarget(obj)
    local ok, v = pcall(function() return obj.Value end)
    if not ok or type(v) ~= "number" then return end
    local t = targets[obj]
    if t then
        if v > t.max then t.max = v end
        return
    end
    targets[obj] = { max = v }
    if CFG.Debug then
        print("[AM] 发现 " .. obj:GetFullName() .. " = " .. tostring(v))
    end
end

local function scanContainer(root, depth)
    if not root or depth > 5 then return end
    local ok, kids = pcall(function() return root:GetChildren() end)
    if not ok or not kids then return end
    for _, ch in ipairs(kids) do
        local cls = ch.ClassName
        if cls == "IntValue" or cls == "NumberValue" then
            if isAmmoName(ch.Name) then addTarget(ch) end
        else
            scanContainer(ch, depth + 1)
        end
    end
end

local function scan()
    local ch = LP.Character
    if ch then scanContainer(ch, 0) end
    local bp = LP:FindFirstChildOfClass("Backpack")
    if bp then scanContainer(bp, 0) end
    local pg = LP:FindFirstChildOfClass("PlayerGui")
    if pg then scanContainer(pg, 0) end
    return countTargets()
end

--=========================== 取值 / 写值 =========================
local function targetValue(t)
    if CFG.Full then return t.max end
    return CFG.Fixed
end

local function bumpMax()
    for obj, t in pairs(targets) do
        local ok, v = pcall(function() return obj.Value end)
        if ok and type(v) == "number" and v > t.max then
            t.max = v
        end
    end
end

local function currentTool()
    local ch = LP.Character
    return ch and ch:FindFirstChildOfClass("Tool")
end

local function freezeAll()
    for obj, t in pairs(targets) do
        local want = targetValue(t)
        local ok, cur = pcall(function() return obj.Value end)
        if ok and type(cur) == "number" and cur < want then
            pcall(function() obj.Value = want end)
        end
    end

    if not CFG.UseAttr then return end
    local tool = currentTool()
    if not tool then return end
    local ok, attrs = pcall(function() return tool:GetAttributes() end)
    if not ok or not attrs then return end
    for k, v in pairs(attrs) do
        if type(v) == "number" and isAmmoName(k) then
            if CFG.Full then
                if not attrMax[k] or v > attrMax[k] then attrMax[k] = v end
                if v < attrMax[k] then
                    pcall(function() tool:SetAttribute(k, attrMax[k]) end)
                end
            elseif v < CFG.Fixed then
                pcall(function() tool:SetAttribute(k, CFG.Fixed) end)
            end
        end
    end
end

--=========================== hook ================================
local Hooks = {}
local busy = false

local function installHook()
    if Hooks.newindex then return true end
    local NC = newcclosure or function(f) return f end
    local hm = hookmetamethod or (syn and syn.hookmetamethod)
    if not hm then return false end

    -- 先写满，再上锁
    bumpMax()
    for obj, t in pairs(targets) do
        pcall(function() obj.Value = targetValue(t) end)
    end

    local ok = pcall(function()
        local old
        old = hm(game, "__newindex", NC(function(self, key, value)
            if key == "Value" and not busy and CFG.Enabled
                and CFG.Mode == "Hook" and targets[self] then
                return          -- 直接吞掉这次写入
            end
            return old(self, key, value)
        end))
        Hooks.newindex = old
    end)
    if not ok then return false end

    local ok2 = pcall(function()
        local old
        old = hm(game, "__namecall", NC(function(self, ...)
            local m = getnamecallmethod()
            if m == "SetAttribute" and CFG.Enabled and CFG.Mode == "Hook" and CFG.UseAttr then
                local k = ...
                local isTool = false
                pcall(function() isTool = self:IsA("Tool") end)
                if isTool and isAmmoName(k) then return end
            end
            return old(self, ...)
        end))
        Hooks.namecall = old
    end)

    return ok
end

local function removeHook()
    local hm = hookmetamethod or (syn and syn.hookmetamethod)
    pcall(function()
        if hm and Hooks.newindex then hm(game, "__newindex", Hooks.newindex) end
    end)
    pcall(function()
        if hm and Hooks.namecall then hm(game, "__namecall", Hooks.namecall) end
    end)
    Hooks.newindex, Hooks.namecall = nil, nil
end

--=========================== 主循环 ==============================
local UI = {}
local lastTick = 0
local lastScan = 0

RunService.RenderStepped:Connect(function()
    if not CFG.Enabled then return end
    local now = os.clock()

    if now - lastScan > 1 then
        lastScan = now
        scan()
        if UI.rowScan then
            UI.rowScan.Text = "  扫描  " .. countTargets() .. " 个"
        end
        if CFG.Mode == "Hook" and countTargets() > 0 and not Hooks.newindex then
            installHook()
        end
    end

    if CFG.Mode == "Freeze" and now - lastTick > 0.1 then
        lastTick = now
        bumpMax()
        freezeAll()
    end
end)

-- 第一次扫描
scan()
if CFG.Mode == "Hook" then installHook() end

--============================== UI ================================

local function buildUI()
    local parent = nil
    pcall(function() parent = gethui() end)
    if not parent then
        local ok, cg = pcall(function() return game:GetService("CoreGui") end)
        parent = (ok and cg) or LP:WaitForChild("PlayerGui")
    end

    local gui = Instance.new("ScreenGui")
    gui.Name = "m_" .. tostring(math.random(100000, 999999))
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 999990
    pcall(function()
        if syn and syn.protect_gui then syn.protect_gui(gui) end
        if protectgui then protectgui(gui) end
    end)
    gui.Parent = parent

    local C_ON  = Color3.fromRGB(90, 70, 20)
    local C_OFF = Color3.fromRGB(42, 44, 52)
    local C_ACC = Color3.fromRGB(255, 230, 100)

    local btn = Instance.new("TextButton")
    btn.Size = UDim2.fromOffset(54, 54)
    btn.Position = UDim2.new(1, -64, 0.16, 0)
    btn.BackgroundColor3 = Color3.fromRGB(20, 22, 26)
    btn.BackgroundTransparency = 0.1
    btn.Text = "AM"
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 15
    btn.TextColor3 = C_ACC
    btn.AutoButtonColor = false
    btn.BorderSizePixel = 0
    btn.Parent = gui
    local uc = Instance.new("UICorner"); uc.CornerRadius = UDim.new(1, 0); uc.Parent = btn
    local us = Instance.new("UIStroke"); us.Color = C_ACC; us.Thickness = 1.5; us.Transparency = 0.25; us.Parent = btn

    local panel = Instance.new("Frame")
    panel.Size = UDim2.fromOffset(196, 250)
    panel.Position = UDim2.new(1, -206, 0.16, 64)
    panel.BackgroundColor3 = Color3.fromRGB(16, 17, 21)
    panel.BackgroundTransparency = 0.06
    panel.BorderSizePixel = 0
    panel.Visible = false
    panel.Parent = gui
    local pc = Instance.new("UICorner"); pc.CornerRadius = UDim.new(0, 10); pc.Parent = panel
    local ps = Instance.new("UIStroke"); ps.Color = Color3.fromRGB(60, 65, 78); ps.Thickness = 1; ps.Parent = panel

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -12, 0, 28)
    title.Position = UDim2.fromOffset(8, 4)
    title.BackgroundTransparency = 1
    title.Text = "无限子弹"
    title.Font = Enum.Font.GothamBold
    title.TextSize = 13
    title.TextColor3 = Color3.fromRGB(200, 205, 215)
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = panel

    local list = Instance.new("ScrollingFrame")
    list.Size = UDim2.new(1, -12, 1, -38)
    list.Position = UDim2.fromOffset(6, 32)
    list.BackgroundTransparency = 1
    list.BorderSizePixel = 0
    list.ScrollBarThickness = 3
    list.CanvasSize = UDim2.fromOffset(0, 0)
    list.AutomaticCanvasSize = Enum.AutomaticSize.Y
    list.Parent = panel

    local lay = Instance.new("UIListLayout")
    lay.Padding = UDim.new(0, 5)
    lay.SortOrder = Enum.SortOrder.LayoutOrder
    lay.Parent = list

    local function makeRow(text, order, onClick)
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(1, -6, 0, 30)
        b.BackgroundColor3 = C_OFF
        b.BorderSizePixel = 0
        b.Text = "  " .. text
        b.Font = Enum.Font.GothamMedium
        b.TextSize = 13
        b.TextColor3 = Color3.fromRGB(255, 255, 255)
        b.TextXAlignment = Enum.TextXAlignment.Left
        b.AutoButtonColor = false
        b.LayoutOrder = order
        b.Parent = list
        local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 6); c.Parent = b
        b.MouseButton1Click:Connect(onClick)
        return b
    end

    local rowOn
    rowOn = makeRow("总开关", 1, function()
        CFG.Enabled = not CFG.Enabled
        rowOn.BackgroundColor3 = CFG.Enabled and C_ON or C_OFF
        btn.TextColor3 = CFG.Enabled and C_ACC or Color3.fromRGB(130, 130, 140)
        us.Color = btn.TextColor3
    end)
    rowOn.BackgroundColor3 = C_ON

    local rowScan
    rowScan = makeRow("扫描  0 个", 2, function()
        local n = scan()
        rowScan.Text = "  扫描  " .. n .. " 个"
        if n == 0 then
            rowScan.Text = "  扫描  0 个（换枪后再点）"
        end
    end)

    local rowMode
    rowMode = makeRow("模式  Freeze", 3, function()
        removeHook()
        CFG.Mode = (CFG.Mode == "Freeze") and "Hook" or "Freeze"
        rowMode.Text = "  模式  " .. CFG.Mode
        if CFG.Mode == "Hook" then
            if not installHook() then
                CFG.Mode = "Freeze"
                rowMode.Text = "  模式  Freeze（Hook 不可用）"
            end
        end
    end)

    local rowFull
    rowFull = makeRow("数值  满弹", 4, function()
        CFG.Full = not CFG.Full
        rowFull.Text = "  数值  " .. (CFG.Full and "满弹" or tostring(CFG.Fixed))
    end)

    local rowAttr
    rowAttr = makeRow("属性拦截", 5, function()
        CFG.UseAttr = not CFG.UseAttr
        rowAttr.BackgroundColor3 = CFG.UseAttr and C_ON or C_OFF
    end)
    rowAttr.BackgroundColor3 = C_ON

    local rowDbg
    rowDbg = makeRow("日志  关", 6, function()
        CFG.Debug = not CFG.Debug
        rowDbg.BackgroundColor3 = CFG.Debug and C_ON or C_OFF
        rowDbg.Text = "  日志  " .. (CFG.Debug and "开" or "关")
    end)

    -- 拖动 / 轻点
    local dragging, dragStart, startPos, moved = false, nil, nil, 0
    btn.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch
            or input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            moved = 0
            dragStart = input.Position
            startPos = btn.Position
        end
    end)
    UIS.InputChanged:Connect(function(input)
        if not dragging or not dragStart then return end
        if input.UserInputType == Enum.UserInputType.Touch
            or input.UserInputType == Enum.UserInputType.MouseMovement then
            local d = input.Position - dragStart
            local m2 = math.abs(d.X) + math.abs(d.Y)
            if m2 > moved then moved = m2 end
            btn.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + d.X,
                startPos.Y.Scale, startPos.Y.Offset + d.Y
            )
        end
    end)
    btn.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch
            or input.UserInputType == Enum.UserInputType.MouseButton1 then
            if moved < 12 then panel.Visible = not panel.Visible end
            dragging = false
            dragStart = nil
        end
    end)
    UIS.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch
            or input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
            dragStart = nil
        end
    end)

    UI.gui, UI.btn, UI.panel = gui, btn, panel
    UI.rowScan = rowScan
end

pcall(buildUI)
if UI.rowScan then
    UI.rowScan.Text = "  扫描  " .. countTargets() .. " 个"
end

--============================ 卸载 ================================
local function unload()
    removeHook()
    CFG.Enabled = false
    if UI.gui then pcall(function() UI.gui:Destroy() end) end
    if getgenv then getgenv().Ammo_Unload = nil end
end

if getgenv then getgenv().Ammo_Unload = unload end

print("[AM] 加载完成 | 找到 " .. countTargets() .. " 个弹药数值 | 模式 " .. CFG.Mode)