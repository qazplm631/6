--[[============================================================
  Roblox Hitbox Expander —— 手机执行器版
  作用：放大敌人身体部件的命中体积（碰撞箱/范围），队友不生效
  适配：Delta / Fluxus / Hydrogen / Cryptic / Ronix / Krnl
  纯客户端：只改本地可见的 Part 尺寸或生成本地代理盒，不写属性到服务端

  两种模式
    Resize —— 直接放大真实身体部件的 Size（最直接，命中判定必吃）
    Proxy  —— 不改真实尺寸，在角色下生成不可见大碰撞盒（更隐蔽）
  用法：执行后左下 "HB" 悬浮球，点开面板调倍率/模式/距离
  卸载：getgenv().Hitbox_Unload()
============================================================]]--

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local LP         = Players.LocalPlayer

if getgenv and getgenv().Hitbox_Unload then pcall(getgenv().Hitbox_Unload) end

--============================== 配置 ==============================
local CFG = {
    Enabled     = true,
    Mode        = "Resize",   -- "Resize" | "Proxy"
    Scale       = 2.0,        -- 放大倍率
    Pad         = 0.4,        -- Proxy 额外厚度
    TeamCheck   = true,       -- 队友不生效
    MaxDistance = 400,        -- 只处理这个距离内的敌人
    ForceQuery  = true,       -- 顺便把 CanQuery 打开（有些游戏关掉就点不到）
    ResizeRoot  = true,       -- 是否连 HumanoidRootPart 一起放大（关掉可减少物理抖动）
    HookRaycast = false,      -- Proxy 模式把射线命中映射回真实部件（需 hookmetamethod）
    Watch       = 0.35,       -- 守护间隔，游戏自动还原尺寸时会被重新应用
}

--=========================== 部件识别 ============================
local BODY_NAMES = {
    Head = true, Torso = true, UpperTorso = true, LowerTorso = true,
    HumanoidRootPart = true,
    LeftUpperArm = true, LeftLowerArm = true, LeftHand = true,
    RightUpperArm = true, RightLowerArm = true, RightHand = true,
    LeftUpperLeg = true, LeftLowerLeg = true, LeftFoot = true,
    RightUpperLeg = true, RightLowerLeg = true, RightFoot = true,
    ["Left Arm"] = true, ["Right Arm"] = true,
    ["Left Leg"] = true, ["Right Leg"] = true,
}

local function isBodyPart(p)
    local ok, res = pcall(function() return p:IsA("BasePart") end)
    if not ok or not res then return false end
    if BODY_NAMES[p.Name] then return true end
    return p.Name:match("Arm$") ~= nil
        or p.Name:match("Leg$") ~= nil
        or p.Name:match("Hand$") ~= nil
        or p.Name:match("Foot$") ~= nil
end

local function collect(ch)
    local out = {}
    local ok, kids = pcall(function() return ch:GetChildren() end)
    if not ok or not kids then return out end
    for _, p in ipairs(kids) do
        if isBodyPart(p) then
            if p.Name ~= "HumanoidRootPart" or CFG.ResizeRoot then
                out[#out + 1] = p
            end
        end
    end
    return out
end

--=========================== 状态管理 ============================
local STATE = {}                                   -- [character] = 记录
local PROXY_MAP = setmetatable({}, { __mode = "k" }) -- proxy part -> 真实部件

local function clearChar(ch)
    local st = STATE[ch]
    if not st then return end
    if st.mode == "Resize" then
        for part, info in pairs(st.orig) do
            pcall(function()
                part.Size = info.size
                if info.query ~= nil then part.CanQuery = info.query end
            end)
        end
    else
        for _, pr in ipairs(st.proxies) do
            pcall(function() pr:Destroy() end)
            PROXY_MAP[pr] = nil
        end
    end
    STATE[ch] = nil
end

local function applyResize(ch, parts)
    local orig = {}
    for _, p in ipairs(parts) do
        local size = p.Size
        local query
        if CFG.ForceQuery then
            pcall(function()
                query = p.CanQuery
                p.CanQuery = true
            end)
        end
        pcall(function() p.Size = size * CFG.Scale end)
        orig[p] = { size = size, query = query }
    end
    STATE[ch] = { mode = "Resize", scale = CFG.Scale, orig = orig }
end

local function applyProxy(ch, parts)
    local proxies, map = {}, {}
    for _, p in ipairs(parts) do
        local pr = Instance.new("Part")
        pr.Name = p.Name                      -- 同名，按名字取部件的游戏也能认
        pr.Size = p.Size * CFG.Scale + Vector3.new(0, CFG.Pad, 0)
        pr.CFrame = p.CFrame
        pr.Transparency = 1
        pr.CanCollide = false
        pr.CanTouch = false
        pr.Anchored = true
        pr.Massless = true
        pr.CastShadow = false
        pcall(function() pr.CanQuery = true end)
        pr.Parent = ch
        proxies[#proxies + 1] = pr
        map[pr] = p
        PROXY_MAP[pr] = p
    end
    STATE[ch] = { mode = "Proxy", scale = CFG.Scale, proxies = proxies, map = map }
end

local function applyChar(ch)
    local parts = collect(ch)
    if #parts == 0 then return end
    if CFG.Mode == "Resize" then
        applyResize(ch, parts)
    else
        applyProxy(ch, parts)
    end
end

--=========================== 目标过滤 ============================
local function wantPlayer(plr)
    if plr == LP then return false end
    local ch = plr.Character
    if not ch then return false end
    local hum = ch:FindFirstChildOfClass("Humanoid")
    local root = ch:FindFirstChild("HumanoidRootPart")
    if not hum or not root or hum.Health <= 0 then return false end

    -- 队友不生效：队伍存在且相同就跳过
    if CFG.TeamCheck and LP.Team ~= nil and plr.Team == LP.Team then return false end

    local cam = workspace.CurrentCamera
    if cam then
        local d = (root.Position - cam.CFrame.Position).Magnitude
        if d > CFG.MaxDistance then return false end
    end
    return true
end

local function refresh()
    for _, plr in ipairs(Players:GetPlayers()) do
        local ch = plr.Character
        if ch then
            local want = CFG.Enabled and wantPlayer(plr)
            local st = STATE[ch]
            if want then
                if (not st) or st.scale ~= CFG.Scale or st.mode ~= CFG.Mode then
                    clearChar(ch)
                    applyChar(ch)
                end
            elseif st then
                clearChar(ch)
            end
        end
    end
    -- 角色被销毁的残留在表里
    for ch in pairs(STATE) do
        if not ch.Parent then clearChar(ch) end
    end
end

--=========================== 守护 / 同步 ==========================
local lastWatch, lastSync = 0, 0

RunService.Heartbeat:Connect(function()
    local t = os.clock()
    if t - lastWatch < CFG.Watch then return end
    lastWatch = t
    local ok, err = pcall(refresh)
    if not ok then warn("[HB] refresh: " .. tostring(err)) end
end)

RunService.RenderStepped:Connect(function()
    local t = os.clock()
    if t - lastSync < 1 / 30 then return end
    lastSync = t
    if CFG.Enabled and CFG.Mode == "Proxy" then
        for _, st in pairs(STATE) do
            if st.mode == "Proxy" then
                for pr, real in pairs(st.map) do
                    if real.Parent and pr.Parent then
                        pr.CFrame = real.CFrame
                        pr.Size = real.Size * st.scale + Vector3.new(0, CFG.Pad, 0)
                    end
                end
            end
        end
    end
end)

--====================== 可选：射线命中映射 ========================
local Hooks = {}

local function installHook()
    local NC = newcclosure or function(f) return f end
    local hook = hookmetamethod or (syn and syn.hookmetamethod)
    if not hook then return false end
    local ok = pcall(function()
        local old
        old = hook(game, "__namecall", NC(function(self, ...)
            local m = getnamecallmethod()
            local args = { ... }
            -- 把代理盒参数从忽略列表里去掉，避免打不到
            if m == "Raycast" then
                local res = old(self, table.unpack(args))
                if res then
                    local real = PROXY_MAP[res.Instance]
                    if real then
                        return {
                            Instance = real,
                            Position = res.Position,
                            Normal = res.Normal,
                            Material = res.Material,
                            Distance = res.Distance,
                        }
                    end
                end
                return res
            end
            return old(self, ...)
        end))
        Hooks.namecall = old
    end)
    return ok
end

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
    gui.Name = "h_" .. tostring(math.random(100000, 999999))
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 999998
    pcall(function()
        if syn and syn.protect_gui then syn.protect_gui(gui) end
        if protectgui then protectgui(gui) end
    end)
    gui.Parent = parent

    local C_ON  = Color3.fromRGB(120, 60, 200)
    local C_OFF = Color3.fromRGB(42, 44, 52)
    local C_ACC = Color3.fromRGB(180, 120, 255)

    local btn = Instance.new("TextButton")
    btn.Size = UDim2.fromOffset(54, 54)
    btn.Position = UDim2.new(0, 10, 0.62, 0)
    btn.BackgroundColor3 = Color3.fromRGB(20, 22, 26)
    btn.BackgroundTransparency = 0.1
    btn.Text = "HB"
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 15
    btn.TextColor3 = C_ACC
    btn.AutoButtonColor = false
    btn.BorderSizePixel = 0
    btn.Parent = gui
    local uc = Instance.new("UICorner"); uc.CornerRadius = UDim.new(1, 0); uc.Parent = btn
    local us = Instance.new("UIStroke"); us.Color = C_ACC; us.Thickness = 1.5; us.Transparency = 0.25; us.Parent = btn

    local panel = Instance.new("Frame")
    panel.Size = UDim2.fromOffset(196, 240)
    panel.Position = UDim2.new(0, 74, 0.42, 0)
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
    title.Text = "碰撞箱放大"
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

    local rowEnabled
    rowEnabled = makeRow("总开关", 1, function()
        CFG.Enabled = not CFG.Enabled
        rowEnabled.BackgroundColor3 = CFG.Enabled and C_ON or C_OFF
        btn.TextColor3 = CFG.Enabled and C_ACC or Color3.fromRGB(130, 130, 140)
        us.Color = btn.TextColor3
        if not CFG.Enabled then
            for ch in pairs(STATE) do clearChar(ch) end
        end
    end)
    rowEnabled.BackgroundColor3 = C_ON

    local rowMode
    rowMode = makeRow("模式  Resize", 2, function()
        CFG.Mode = (CFG.Mode == "Resize") and "Proxy" or "Resize"
        rowMode.Text = "  模式  " .. CFG.Mode
        for ch in pairs(STATE) do clearChar(ch) end
    end)

    local scales = { 1.5, 2.0, 2.5, 3.0, 4.0 }
    local si = 2
    local rowScale
    rowScale = makeRow("倍率  2.0x", 3, function()
        si = si % #scales + 1
        CFG.Scale = scales[si]
        rowScale.Text = string.format("  倍率  %.1fx", CFG.Scale)
    end)

    local rowTeam
    rowTeam = makeRow("队友过滤", 4, function()
        CFG.TeamCheck = not CFG.TeamCheck
        rowTeam.BackgroundColor3 = CFG.TeamCheck and C_ON or C_OFF
    end)
    rowTeam.BackgroundColor3 = C_ON

    local dists = { 100, 200, 400, 800 }
    local di = 3
    local rowDist
    rowDist = makeRow("距离  400", 5, function()
        di = di % #dists + 1
        CFG.MaxDistance = dists[di]
        rowDist.Text = "  距离  " .. dists[di]
    end)

    local rowHook
    rowHook = makeRow("射线映射  关", 6, function()
        CFG.HookRaycast = not CFG.HookRaycast
        rowHook.BackgroundColor3 = CFG.HookRaycast and C_ON or C_OFF
        if CFG.HookRaycast and not Hooks.namecall then
            CFG.HookRaycast = installHook()
            rowHook.Text = "  射线映射  " .. (CFG.HookRaycast and "开" or "失败")
        end
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
    game:GetService("UserInputService").InputChanged:Connect(function(input)
        if not dragging or not dragStart then return end
        if input.UserInputType == Enum.UserInputType.Touch
            or input.UserInputType == Enum.UserInputType.MouseMovement then
            local d = input.Position - dragStart
            if math.abs(d.X) + math.abs(d.Y) > moved then
                moved = math.abs(d.X) + math.abs(d.Y)
            end
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
    game:GetService("UserInputService").InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch
            or input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
            dragStart = nil
        end
    end)

    UI.gui, UI.btn, UI.panel = gui, btn, panel
end

pcall(buildUI)

--============================ 卸载 ================================
local function unload()
    for ch in pairs(STATE) do clearChar(ch) end
    if Hooks.namecall then
        pcall(function() hookmetamethod(game, "__namecall", Hooks.namecall) end)
        Hooks.namecall = nil
    end
    if UI.gui then pcall(function() UI.gui:Destroy() end) end
    if getgenv then getgenv().Hitbox_Unload = nil end
end

if getgenv then getgenv().Hitbox_Unload = unload end

print("[HB] 加载完成 | 模式 " .. CFG.Mode .. " | " .. string.format("%.1fx", CFG.Scale)
    .. " | 队友过滤 " .. tostring(CFG.TeamCheck))
