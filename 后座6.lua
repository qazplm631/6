--[[============================================================
  Roblox 无后坐力 —— 手机执行器版
  思路：游戏的枪口后坐几乎都体现在相机 pitch（上下视角）上。
        开火窗口内拒绝"向上抬"的相机旋转，向下压枪仍然有效；
        另一种 Smart 模式则在没有任何视角输入时锁死 pitch，
        连镜头抖动、走路晃动一起吃掉。
  适配：Delta / Fluxus / Hydrogen / Cryptic / Ronix / Krnl
  用法：执行后右下 "NR" 悬浮球，点开面板切模式/窗口
  卸载：getgenv().NoRecoil_Unload()
============================================================]]--

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS        = game:GetService("UserInputService")
local LP         = Players.LocalPlayer

if getgenv and getgenv().NoRecoil_Unload then pcall(getgenv().NoRecoil_Unload) end

--============================== 配置 ==============================
local CFG = {
    Enabled    = true,
    Mode       = "Fire",     -- "Fire"：开火窗口内吃掉上抬 | "Smart"：无视角输入时锁 pitch
    Method     = "Hook",     -- "Hook"：拦截相机 CFrame 写入（最准） | "Render"：每帧修正（兼容最好）
    FireWindow = 0.18,       -- 开火后多久仍视为开火中
    InputEps   = 0.35,       -- Smart 模式判定"玩家在转视角"的输入阈值
    MaxReject  = 0.06,       -- 只吃小幅上抬（弧度，约 3.4°）；更大的上抬视为玩家自己甩视角
    ZeroOffset = false,      -- 顺便把 Humanoid.CameraOffset 清零（蹲伏/镜头抖动用它的游戏）
    OnlyCustom = true,       -- 只在 CameraType=Custom 时干预，放过过场动画
    Debug      = false,
}

--=========================== 相机数学 ============================
local function clamp1(v)
    if v < -1 then return -1 end
    if v > 1 then return 1 end
    return v
end

-- 拆出 yaw / pitch：look = (-cos(p)sin(y), sin(p), -cos(p)cos(y))
local function splitCF(cf)
    local look = cf.LookVector
    local pitch = math.asin(clamp1(look.Y))
    local yaw = math.atan2(-look.X, -look.Z)
    return yaw, pitch
end

local function buildCF(pos, yaw, pitch)
    return CFrame.new(pos) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0)
end

--=========================== 运行状态 ============================
local camRef = workspace.CurrentCamera
local acceptedPitch = nil
local viewInput = 0
local fireUntil = 0
local busy = false

local function resetState()
    acceptedPitch = nil
    viewInput = 0
end

local function markFire()
    fireUntil = math.max(fireUntil, os.clock() + CFG.FireWindow)
end

--=========================== 核心过滤 ============================
local function process(cf)
    local yaw, pitch = splitCF(cf)
    if acceptedPitch == nil then acceptedPitch = pitch end
    if math.abs(pitch - acceptedPitch) > 1.2 then
        -- 相机被瞬移（重生/切镜头），重新同步基准，别硬拉
        acceptedPitch = pitch
        return cf
    end

    local newPitch = pitch

    if CFG.Mode == "Fire" then
        if os.clock() < fireUntil then
            local up = pitch - acceptedPitch
            if up > 0 and up <= CFG.MaxReject then
                newPitch = acceptedPitch          -- 小幅上抬 = 后坐，吃掉
            else
                acceptedPitch = pitch             -- 往下压枪 / 玩家大幅甩视角，放行
            end
        else
            acceptedPitch = pitch
        end
    else                                   -- Smart
        if viewInput < CFG.InputEps then
            newPitch = acceptedPitch          -- 没在转视角，相机自己动的一律不认
        else
            acceptedPitch = pitch
        end
    end

    if math.abs(newPitch - pitch) < 1e-6 then
        return cf
    end
    return buildCF(cf.Position, yaw, newPitch)
end

--=========================== 输入 / 开火检测 ======================
UIS.InputChanged:Connect(function(input)
    local t = input.UserInputType
    if t == Enum.UserInputType.MouseMovement or t == Enum.UserInputType.Touch then
        local d = input.Delta
        if d and math.abs(d.Y) > 0 then
            viewInput = viewInput + math.abs(d.Y)
        end
    end
end)

local function readMouseDelta()
    local ok, md = pcall(function() return UIS:GetMouseDelta() end)
    if ok and md and math.abs(md.Y) > 0 then
        viewInput = math.max(viewInput, math.abs(md.Y))
    end
end

UIS.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        markFire()
    end
end)

local function bindTool(tool)
    if tool and tool:IsA("Tool") then
        tool.Activated:Connect(markFire)
    end
end

local function scanTools()
    local ch = LP.Character
    if not ch then return end
    for _, t in ipairs(ch:GetChildren()) do
        bindTool(t)
    end
end

LP.CharacterAdded:Connect(function()
    resetState()
    task.wait(0.4)
    scanTools()
end)
if LP.Character then scanTools() end

--=========================== 相机更换 ============================
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
    camRef = workspace.CurrentCamera
    resetState()
end)

--=========================== 模式一：hook =========================
local Hooks = {}

local function installHook()
    if Hooks.old then return true end
    local NC = newcclosure or function(f) return f end
    local hm = hookmetamethod or (syn and syn.hookmetamethod)
    if not hm then return false end
    local ok = pcall(function()
        local old
        old = hm(game, "__newindex", NC(function(self, key, value)
            if key == "CFrame" and not busy and CFG.Enabled and self == camRef then
                busy = true
                local okk, res = pcall(process, value)
                busy = false
                if okk then value = res end
            end
            return old(self, key, value)
        end))
        Hooks.old = old
    end)
    return ok and Hooks.old ~= nil
end

local function removeHook()
    if not Hooks.old then return end
    local hm = hookmetamethod or (syn and syn.hookmetamethod)
    pcall(function()
        if hm then hm(game, "__newindex", Hooks.old) end
    end)
    Hooks.old = nil
end

--=========================== 模式二：每帧修正 ====================
RunService.RenderStepped:Connect(function()
    local cam = camRef
    if CFG.Enabled and CFG.Method == "Render" and cam then
        if (not CFG.OnlyCustom) or cam.CameraType == Enum.CameraType.Custom then
            local ok, res = pcall(process, cam.CFrame)
            if ok and res ~= cam.CFrame then
                cam.CFrame = res
            end
        end
    end

    if CFG.Enabled and CFG.ZeroOffset then
        local ch = LP.Character
        local hum = ch and ch:FindFirstChildOfClass("Humanoid")
        if hum then
            pcall(function()
                local o = hum.CameraOffset
                if o.Magnitude > 0.001 then
                    hum.CameraOffset = Vector3.new(0, 0, 0)
                end
            end)
        end
    end

    readMouseDelta()
    viewInput = 0
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
    gui.Name = "r_" .. tostring(math.random(100000, 999999))
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 999997
    pcall(function()
        if syn and syn.protect_gui then syn.protect_gui(gui) end
        if protectgui then protectgui(gui) end
    end)
    gui.Parent = parent

    local C_ON  = Color3.fromRGB(0, 110, 130)
    local C_OFF = Color3.fromRGB(42, 44, 52)
    local C_ACC = Color3.fromRGB(0, 210, 230)

    local btn = Instance.new("TextButton")
    btn.Size = UDim2.fromOffset(54, 54)
    btn.Position = UDim2.new(0, 10, 0.82, 0)
    btn.BackgroundColor3 = Color3.fromRGB(20, 22, 26)
    btn.BackgroundTransparency = 0.1
    btn.Text = "NR"
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 15
    btn.TextColor3 = C_ACC
    btn.AutoButtonColor = false
    btn.BorderSizePixel = 0
    btn.Parent = gui
    local uc = Instance.new("UICorner"); uc.CornerRadius = UDim.new(1, 0); uc.Parent = btn
    local us = Instance.new("UIStroke"); us.Color = C_ACC; us.Thickness = 1.5; us.Transparency = 0.25; us.Parent = btn

    local panel = Instance.new("Frame")
    panel.Size = UDim2.fromOffset(196, 230)
    panel.Position = UDim2.new(0.28, 0, 0.55, 0)
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
    title.Text = "无后坐力"
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
        resetState()
    end)
    rowOn.BackgroundColor3 = C_ON

    local rowMode
    rowMode = makeRow("模式  Fire", 2, function()
        CFG.Mode = (CFG.Mode == "Fire") and "Smart" or "Fire"
        rowMode.Text = "  模式  " .. CFG.Mode
        resetState()
    end)

    local rowMethod
    rowMethod = makeRow("方式  Hook", 3, function()
        if CFG.Method == "Hook" then
            CFG.Method = "Render"
            removeHook()
        else
            CFG.Method = "Hook"
            if not installHook() then
                CFG.Method = "Render"
                rowMethod.Text = "  方式  Render（Hook 不可用）"
                resetState()
                return
            end
        end
        rowMethod.Text = "  方式  " .. CFG.Method
        resetState()
    end)

    local wins = { 0.12, 0.18, 0.25, 0.4 }
    local wi = 2
    local rowWin
    rowWin = makeRow("开火窗口  0.18s", 4, function()
        wi = wi % #wins + 1
        CFG.FireWindow = wins[wi]
        rowWin.Text = "  开火窗口  " .. string.format("%.2f", CFG.FireWindow) .. "s"
    end)

    local rowOffset
    rowOffset = makeRow("相机偏移清零", 5, function()
        CFG.ZeroOffset = not CFG.ZeroOffset
        rowOffset.BackgroundColor3 = CFG.ZeroOffset and C_ON or C_OFF
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
            local m = math.abs(d.X) + math.abs(d.Y)
            if m > moved then moved = m end
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
    UI.rowMethod = rowMethod
end

pcall(buildUI)

if CFG.Method == "Hook" then
    if not installHook() then
        CFG.Method = "Render"
        if UI.rowMethod then UI.rowMethod.Text = "  方式  Render（Hook 不可用）" end
    end
end

--============================ 卸载 ================================
local function unload()
    removeHook()
    if UI.gui then pcall(function() UI.gui:Destroy() end) end
    if getgenv then getgenv().NoRecoil_Unload = nil end
end

if getgenv then getgenv().NoRecoil_Unload = unload end

print("[NR] 加载完成 | 模式 " .. CFG.Mode .. " | 方式 " .. CFG.Method
    .. " | 窗口 " .. string.format("%.2f", CFG.FireWindow) .. "s")
