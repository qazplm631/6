--[[ ============================================================
     合并版：透视通缉 + 无限体力（速度锁）+ 3 秒开启弹窗
     执行后顶部弹出「已开启」，3 秒后自动淡出
     两部分互不干扰：ESP 只读不写，速度锁只管 WalkSpeed
     ============================================================ ]]

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local LP = Players.LocalPlayer

local CONFIG = {
    -- ==== 体力 / 速度 ====
    SPEED         = 28,          -- 24 / 28 / 32，6 是游戏基础走速
    BLOCK_LOWER   = true,        -- 拦截游戏把速度调低

    -- ==== 透视 ====
    ESP_INTERVAL  = 0.8,
    FILL_COLOR    = Color3.fromRGB(255, 60, 60),
    OUTLINE_COLOR = Color3.fromRGB(255, 210, 210),
    FORCE_ALL_ESP = false,       -- true = 所有人标红（验证绘制用）
    MANUAL_WANTED = {},          -- 写死名字 {"Player1"}

    -- ==== 弹窗 ====
    POPUP_SECONDS = 3,
    TITLE         = "已开启",
    SUBTITLE      = "透视通缉 · 无限体力",
}

local out = function(s) print("[GEN4] " .. s) end

-- ============================================================
-- 一、3 秒开启弹窗
-- ============================================================
local function showPopup()
    local ok = pcall(function()
        local pg = LP:WaitForChild("PlayerGui")

        local gui = Instance.new("ScreenGui")
        gui.Name          = "__GEN4_POPUP"
        gui.ResetOnSpawn  = false
        gui.IgnoreGuiInset = true
        gui.DisplayOrder  = 999
        gui.Parent        = pg

        local frame = Instance.new("Frame")
        frame.AnchorPoint          = Vector2.new(0.5, 0)
        frame.Position             = UDim2.new(0.5, 0, 0, 44)
        frame.Size                 = UDim2.new(0, 300, 0, 92)
        frame.BackgroundColor3     = Color3.fromRGB(18, 18, 24)
        frame.BackgroundTransparency = 0.12
        frame.BorderSizePixel      = 0
        frame.Parent               = gui

        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 14)
        corner.Parent = frame

        local stroke = Instance.new("UIStroke")
        stroke.Color     = Color3.fromRGB(255, 70, 70)
        stroke.Thickness = 2
        stroke.Transparency = 0.2
        stroke.Parent = frame

        local title = Instance.new("TextLabel")
        title.Size                   = UDim2.new(1, 0, 0, 48)
        title.Position               = UDim2.new(0, 0, 0, 8)
        title.BackgroundTransparency = 1
        title.Font                   = Enum.Font.GothamBold
        title.TextSize               = 26
        title.TextColor3             = Color3.fromRGB(255, 235, 235)
        title.Text                   = CONFIG.TITLE
        title.Parent                 = frame

        local sub = Instance.new("TextLabel")
        sub.Size                   = UDim2.new(1, 0, 0, 26)
        sub.Position               = UDim2.new(0, 0, 0, 54)
        sub.BackgroundTransparency = 1
        sub.Font                   = Enum.Font.Gotham
        sub.TextSize               = 15
        sub.TextColor3             = Color3.fromRGB(200, 200, 210)
        sub.Text                   = CONFIG.SUBTITLE
        sub.Parent                 = frame

        -- 3 秒后淡出
        task.delay(CONFIG.POPUP_SECONDS, function()
            local info = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
            TweenService:Create(frame, info, { BackgroundTransparency = 1 }):Play()
            TweenService:Create(stroke, info, { Transparency = 1 }):Play()
            TweenService:Create(title, info, { TextTransparency = 1 }):Play()
            TweenService:Create(sub, info, { TextTransparency = 1 }):Play()
            task.wait(0.5)
            if gui and gui.Parent then gui:Destroy() end
        end)
    end)
    if not ok then out("弹窗创建失败") end
end

-- ============================================================
-- 二、无限体力（速度锁）
-- ============================================================
local function setupSpeed()
    local SPEED = CONFIG.SPEED

    -- 只装一次 hook
    if CONFIG.BLOCK_LOWER and not _G.__gen4Hook then
        pcall(function()
            local oldIndex
            oldIndex = hookmetamethod(game, "__newindex", function(self, key, value)
                if key == "WalkSpeed" and not checkcaller() then
                    if type(value) == "number" and value < (_G.__gen4Speed or SPEED) then
                        return
                    end
                end
                return oldIndex(self, key, value)
            end)
            _G.__gen4Hook = true
        end)
    end

    _G.__gen4Speed = SPEED

    if _G.__gen4Loop then
        pcall(function() _G.__gen4Loop:Disconnect() end)
    end

    _G.__gen4Loop = RunService.Heartbeat:Connect(function()
        local hum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
        if hum and hum.WalkSpeed < (_G.__gen4Speed or SPEED) then
            pcall(function() hum.WalkSpeed = _G.__gen4Speed or SPEED end)
        end
    end)

    out("速度锁: " .. SPEED)
end

-- ============================================================
-- 三、透视通缉
-- ============================================================
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

local function scanContainer(container)
    for _, v in ipairs(container:GetDescendants()) do
        if matchName(v.Name)
        and (v:IsA("BoolValue") or v:IsA("NumberValue")
             or v:IsA("IntValue") or v:IsA("StringValue"))
        and truthy(v.Value) then
            return true
        end
    end
    return false
end

local function isWanted(plr)
    if plr == LP then return false end
    if CONFIG.FORCE_ALL_ESP then return true end
    for _, n in ipairs(CONFIG.MANUAL_WANTED) do
        if plr.Name == n then return true end
    end
    for k, v in pairs(plr:GetAttributes()) do
        if matchName(k) and truthy(v) then return true end
    end
    for _, cname in ipairs({"PlayerData","leaderstats","Stats","Values","Data"}) do
        local c = plr:FindFirstChild(cname)
        if c and scanContainer(c) then return true end
    end
    local char = plr.Character
    if char then
        for k, v in pairs(char:GetAttributes()) do
            if matchName(k) and truthy(v) then return true end
        end
        if scanContainer(char) then return true end
        for _, d in ipairs(char:GetDescendants()) do
            if d:IsA("TextLabel") and matchName(d.Text) then return true end
        end
    end
    return false
end

local tracked = setmetatable({}, { __mode = "k" })

local function clearESP(plr)
    local data = tracked[plr]
    if not data then return end
    if data.highlight and data.highlight.Parent then data.highlight:Destroy() end
    if data.billboard and data.billboard.Parent then data.billboard:Destroy() end
    tracked[plr] = nil
end

local function applyESP(plr)
    local char = plr.Character
    local head = char and char:FindFirstChild("Head")
    local hum  = char and char:FindFirstChildOfClass("Humanoid")
    if not (char and head and hum) then return end

    local data = tracked[plr]
    if not data then
        data = {}
        tracked[plr] = data
    end

    if not data.highlight or data.highlight.Parent ~= char then
        if data.highlight then data.highlight:Destroy() end
        local hl = Instance.new("Highlight")
        hl.Name                = "__WANTED_HL"
        hl.Adornee             = char
        hl.DepthMode           = Enum.HighlightDepthMode.AlwaysOnTop
        hl.FillColor           = CONFIG.FILL_COLOR
        hl.FillTransparency    = 0.55
        hl.OutlineColor        = CONFIG.OUTLINE_COLOR
        hl.OutlineTransparency = 0
        hl.Parent              = char
        data.highlight         = hl
    end

    if not data.billboard or data.billboard.Parent ~= head then
        if data.billboard then data.billboard:Destroy() end
        local bb = Instance.new("BillboardGui")
        bb.Name        = "__WANTED_BB"
        bb.Size        = UDim2.new(0, 200, 0, 42)
        bb.StudsOffset = Vector3.new(0, 2.6, 0)
        bb.AlwaysOnTop = true
        bb.Adornee     = head
        bb.Parent      = head

        local label = Instance.new("TextLabel")
        label.Size                   = UDim2.new(1, 0, 1, 0)
        label.BackgroundTransparency = 1
        label.Font                   = Enum.Font.GothamBold
        label.TextSize               = 16
        label.TextColor3             = CONFIG.OUTLINE_COLOR
        label.TextStrokeTransparency = 0.4
        label.Text                   = plr.Name
        label.Parent                 = bb

        data.billboard = bb
        data.label     = label
    end
end

local function setupESP()
    RunService.Heartbeat:Connect(function()
        local myRoot = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
        for plr, data in pairs(tracked) do
            local root = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
            if data.label and myRoot and root then
                local d = math.floor((root.Position - myRoot.Position).Magnitude)
                data.label.Text = string.format("%s  [%d]", plr.Name, d)
            end
        end
    end)

    task.spawn(function()
        while true do
            for _, plr in ipairs(Players:GetPlayers()) do
                if plr ~= LP then
                    if isWanted(plr) then
                        applyESP(plr)
                    else
                        clearESP(plr)
                    end
                end
            end
            task.wait(CONFIG.ESP_INTERVAL)
        end
    end)

    Players.PlayerRemoving:Connect(function(p) clearESP(p) end)
    out("透视: 已启动")
end

-- ============================================================
-- 启动
-- ============================================================
showPopup()
setupSpeed()
setupESP()

out("合并版已加载，按模块状态查看上两行日志")
