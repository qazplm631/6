--[[============================================================
  Roblox 自定义速度 —— 手机执行器版
  两种模式：
    WalkSpeed —— 直接改 Humanoid.WalkSpeed（最简单，绝大多数游戏有效）
    Velocity  —— 不动 WalkSpeed，用 BodyVelocity 推着跑（绕过"检查 WalkSpeed"的反作弊）
  带守护：游戏把速度重置回去时自动写回来
  附带跳跃力度自定义、恢复默认

  适配：Delta / Fluxus / Hydrogen / Cryptic / Ronix / Krnl
  用法：执行后 "SP" 悬浮球；卸载 getgenv().Speed_Unload()
============================================================]]--

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS        = game:GetService("UserInputService")
local LP         = Players.LocalPlayer

if getgenv and getgenv().Speed_Unload then pcall(getgenv().Speed_Unload) end

--============================== 配置 ==============================
local CFG = {
    Enabled  = true,
    Speed    = 60,
    Mode     = "WalkSpeed",  -- WalkSpeed | Velocity
    Lock     = true,         -- 游戏重置时写回来
    JumpOn   = false,        -- 是否改跳跃
    Jump     = 60,
}

--=========================== 运行状态 ============================
local S = {
    hum = nil,
    origWalk = nil,
    origJump = nil,
    bv = nil,
    applying = false,
    conns = {},
}

local function dropConns(key)
    local list = S.conns[key]
    if not list then return end
    for _, c in ipairs(list) do
        pcall(function() c:Disconnect() end)
    end
    S.conns[key] = nil
end

local function addConn(key, c)
    S.conns[key] = S.conns[key] or {}
    table.insert(S.conns[key], c)
end

--=========================== 速度应用 ============================
local function clearVelocity()
    if S.bv then
        pcall(function() S.bv:Destroy() end)
        S.bv = nil
    end
end

local function applyWalkSpeed()
    local hum = S.hum
    if not hum then return end
    if CFG.Mode ~= "WalkSpeed" then return end
    S.applying = true
    pcall(function()
        if S.origWalk == nil then S.origWalk = hum.WalkSpeed end
        hum.WalkSpeed = CFG.Speed
    end)
    S.applying = false
end

local function applyVelocity()
    local hum = S.hum
    local ch = LP.Character
    local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
    if not (hum and hrp) then return end
    if not S.bv then
        local ok = pcall(function()
            local bv = Instance.new("BodyVelocity")
            bv.Name = "spd"
            bv.MaxForce = Vector3.new(100000, 0, 100000)   -- 纵向 0：不影响跳跃和重力
            bv.P = 1250
            bv.Velocity = Vector3.new(0, 0, 0)
            bv.Parent = hrp
            S.bv = bv
        end)
        if not ok then
            -- 老版本没有 BodyVelocity 时退回 LinearVelocity
            pcall(function()
                local att = Instance.new("Attachment")
                att.Name = "spd_att"
                att.Parent = hrp
                local lv = Instance.new("LinearVelocity")
                lv.Name = "spd"
                lv.Attachment0 = att
                lv.MaxForce = 100000
                lv.VectorVelocity = Vector3.new(0, 0, 0)
                lv.Parent = hrp
                S.bv = lv
            end)
        end
    end
    -- WalkSpeed 归零，避免两套推力叠加
    S.applying = true
    pcall(function()
        if S.origWalk == nil then S.origWalk = hum.WalkSpeed end
        hum.WalkSpeed = 0
    end)
    S.applying = false
end

local function applyJump()
    local hum = S.hum
    if not hum then return end
    if not CFG.JumpOn then return end
    pcall(function()
        if S.origJump == nil then S.origJump = hum.JumpPower end
        hum.UseJumpPower = true
        hum.JumpPower = CFG.Jump
    end)
end

local function applyAll()
    if not CFG.Enabled then return end
    if CFG.Mode == "WalkSpeed" then
        clearVelocity()
        applyWalkSpeed()
    else
        applyVelocity()
    end
    applyJump()
end

--=========================== 恢复默认 ============================
local function restoreAll()
    clearVelocity()
    local hum = S.hum
    if hum then
        pcall(function()
            if S.origWalk ~= nil then hum.WalkSpeed = S.origWalk end
        end)
        pcall(function()
            if S.origJump ~= nil then hum.JumpPower = S.origJump end
        end)
    end
end

--=========================== 绑定角色 ============================
local function onCharacter(ch)
    dropConns("char")
    S.hum = ch and ch:FindFirstChildOfClass("Humanoid")
    S.origWalk = nil
    S.origJump = nil
    clearVelocity()
    if not S.hum then return end

    -- 游戏偷偷把 WalkSpeed 改回去 → 写回来
    addConn("char", S.hum:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
        if not CFG.Enabled or not CFG.Lock then return end
        if S.applying then return end
        if CFG.Mode ~= "WalkSpeed" then return end
        if math.abs(S.hum.WalkSpeed - CFG.Speed) > 0.05 then
            applyWalkSpeed()
        end
    end))

    addConn("char", S.hum.Died:Connect(function()
        clearVelocity()
    end))

    applyAll()
end

LP.CharacterAdded:Connect(function(ch)
    task.wait(0.2)
    onCharacter(ch)
end)

if LP.Character then
    onCharacter(LP.Character)
end

--=========================== 每帧维护 ============================
RunService.RenderStepped:Connect(function()
    if not CFG.Enabled then
        if S.bv then clearVelocity() end
        return
    end
    if CFG.Mode ~= "Velocity" then return end

    local ch = LP.Character
    local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
    local hum = S.hum
    if not (hrp and hum and S.bv) then return end

    local md = hum.MoveDirection
    local speed = CFG.Speed
    pcall(function()
        S.bv.Velocity = Vector3.new(md.X, 0, md.Z) * speed
        S.bv.VectorVelocity = Vector3.new(md.X, 0, md.Z) * speed
    end)
end)

--============================== UI ================================
local UI = {}

local function buildUI()
    local parent = nil
    pcall(function() parent = gethui() end)
    if not parent then
        local ok, cg = pcall(function() return game:GetService("CoreGui") end)
        parent = (ok and cg) or LP:WaitForChild("PlayerGui")
    end

    local gui = Instance.new("ScreenGui")
    gui.Name = "p_" .. tostring(math.random(100000, 999999))
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 999991
    pcall(function()
        if syn and syn.protect_gui then syn.protect_gui(gui) end
        if protectgui then protectgui(gui) end
    end)
    gui.Parent = parent

    local C_ON  = Color3.fromRGB(30, 100, 60)
    local C_OFF = Color3.fromRGB(42, 44, 52)
    local C_ACC = Color3.fromRGB(80, 230, 140)

    local btn = Instance.new("TextButton")
    btn.Size = UDim2.fromOffset(54, 54)
    btn.Position = UDim2.new(0, 10, 0.18, 0)
    btn.BackgroundColor3 = Color3.fromRGB(20, 22, 26)
    btn.BackgroundTransparency = 0.1
    btn.Text = "SP"
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 15
    btn.TextColor3 = C_ACC
    btn.AutoButtonColor = false
    btn.BorderSizePixel = 0
    btn.Parent = gui
    local uc = Instance.new("UICorner"); uc.CornerRadius = UDim.new(1, 0); uc.Parent = btn
    local us = Instance.new("UIStroke"); us.Color = C_ACC; us.Thickness = 1.5; us.Transparency = 0.25; us.Parent = btn

    local panel = Instance.new("Frame")
    panel.Size = UDim2.fromOffset(196, 320)
    panel.Position = UDim2.new(0, 74, 0.12, 0)
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
    title.Text = "人物速度"
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

    -- 速度输入框
    local box = Instance.new("TextBox")
    box.Size = UDim2.new(1, -6, 0, 34)
    box.LayoutOrder = 0
    box.BackgroundColor3 = C_OFF
    box.BorderSizePixel = 0
    box.Font = Enum.Font.GothamBold
    box.TextSize = 15
    box.TextColor3 = Color3.fromRGB(255, 255, 255)
    box.PlaceholderText = "输入速度"
    box.Text = tostring(CFG.Speed)
    box.ClearTextOnFocus = false
    box.Parent = list
    local bc = Instance.new("UICorner"); bc.CornerRadius = UDim.new(0, 6); bc.Parent = box
    box.FocusLost:Connect(function()
        local n = tonumber(box.Text)
        if n and n >= 1 and n <= 1000 then
            CFG.Speed = math.floor(n)
            applyAll()
        end
        box.Text = tostring(CFG.Speed)
    end)

    local rowOn
    rowOn = makeRow("总开关", 1, function()
        CFG.Enabled = not CFG.Enabled
        rowOn.BackgroundColor3 = CFG.Enabled and C_ON or C_OFF
        btn.TextColor3 = CFG.Enabled and C_ACC or Color3.fromRGB(130, 130, 140)
        us.Color = btn.TextColor3
        if CFG.Enabled then applyAll() else restoreAll() end
    end)
    rowOn.BackgroundColor3 = C_ON

    local rowMinus = makeRow("− 5", 2, function()
        CFG.Speed = math.max(1, CFG.Speed - 5)
        box.Text = tostring(CFG.Speed)
        applyAll()
    end)
    rowMinus.TextXAlignment = Enum.TextXAlignment.Center

    local rowPlus = makeRow("+ 5", 3, function()
        CFG.Speed = math.min(1000, CFG.Speed + 5)
        box.Text = tostring(CFG.Speed)
        applyAll()
    end)
    rowPlus.TextXAlignment = Enum.TextXAlignment.Center

    local presets = { 16, 32, 60, 100, 150, 250 }
    local pi = 3
    local rowPreset
    rowPreset = makeRow("预设  60", 4, function()
        pi = pi % #presets + 1
        CFG.Speed = presets[pi]
        box.Text = tostring(CFG.Speed)
        rowPreset.Text = "  预设  " .. CFG.Speed
        applyAll()
    end)

    local rowMode
    rowMode = makeRow("模式  WalkSpeed", 5, function()
        CFG.Mode = (CFG.Mode == "WalkSpeed") and "Velocity" or "WalkSpeed"
        rowMode.Text = "  模式  " .. CFG.Mode
        clearVelocity()
        applyAll()
    end)

    local rowLock
    rowLock = makeRow("锁定速度", 6, function()
        CFG.Lock = not CFG.Lock
        rowLock.BackgroundColor3 = CFG.Lock and C_ON or C_OFF
    end)
    rowLock.BackgroundColor3 = C_ON

    local rowJump
    rowJump = makeRow("跳跃  关", 7, function()
        CFG.JumpOn = not CFG.JumpOn
        rowJump.BackgroundColor3 = CFG.JumpOn and C_ON or C_OFF
        rowJump.Text = "  跳跃  " .. (CFG.JumpOn and CFG.Jump or "关")
        if CFG.JumpOn then applyJump() end
    end)

    local rowReset = makeRow("恢复默认", 8, function()
        restoreAll()
        CFG.Enabled = false
        rowOn.BackgroundColor3 = C_OFF
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

    UI.gui, UI.btn, UI.panel, UI.box = gui, btn, panel, box
end

pcall(buildUI)

--============================ 卸载 ================================
local function unload()
    restoreAll()
    for k in pairs(S.conns) do dropConns(k) end
    CFG.Enabled = false
    if UI.gui then pcall(function() UI.gui:Destroy() end) end
    if getgenv then getgenv().Speed_Unload = nil end
end

if getgenv then getgenv().Speed_Unload = unload end

print("[SP] 加载完成 | 速度 " .. CFG.Speed .. " | 模式 " .. CFG.Mode)