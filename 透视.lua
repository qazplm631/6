--[[ 透视 · 只显示 通缉犯 与 警察
     红 = 通缉
     蓝 = 警察
     其他人一律不画
--]]

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local LP = Players.LocalPlayer

local CFG = {
    SCAN_INTERVAL = 0.8,

    WANTED_COLOR  = Color3.fromRGB(255, 60, 60),
    POLICE_COLOR  = Color3.fromRGB(60, 150, 255),

    -- 队伍名里出现这些词 → 判定为警察
    POLICE_KEYS   = {"police","cop","officer","sheriff","警察","警","公安","巡警"},
    -- 直接点名（队伍名不完全匹配时用）
    POLICE_TEAMS  = {},
    POLICE_NAMES  = {},

    SHOW_TEAMNAME = true,
    HEIGHT_OFFSET = 2.6,

    -- 人物高亮
    USE_HIGHLIGHT     = true,   -- false = 完全不要高亮，只留头顶文字
    HIGHLIGHT_OUTLINE = false,  -- false = 去掉人物描边（只留淡淡的填充）
    FILL_TRANSPARENCY = 0.8,    -- 填充透明度，1 等于完全看不见

}

local out = function(s) print("[透视] " .. s) end

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
    if plr == LP then return false end
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
        for _, d in ipairs(char:GetDescendants()) do
            if d:IsA("TextLabel") and matchName(d.Text) then return true end
        end
    end
    return false
end

-- ===== 警察 =====
local function hitAny(text, keys)
    local s = string.lower(tostring(text))
    for _, k in ipairs(keys) do
        if s:find(k, 1, true) then return true end
    end
    return false
end

local function isPolice(plr)
    if plr == LP then return false end
    for _, n in ipairs(CFG.POLICE_NAMES) do
        if plr.Name == n then return true end
    end
    if plr.Team and plr.Team.Name then
        for _, tn in ipairs(CFG.POLICE_TEAMS) do
            if plr.Team.Name == tn then return true end
        end
        if hitAny(plr.Team.Name, CFG.POLICE_KEYS) then return true end
    end
    -- 角色/玩家上的身份字段
    local function checkFields(obj)
        for k, v in pairs(obj:GetAttributes()) do
            if hitAny(k, CFG.POLICE_KEYS) and truthy(v) then return true end
            if type(v) == "string" and hitAny(v, CFG.POLICE_KEYS) then return true end
        end
        for _, c in ipairs({"PlayerData","Stats","Values","Data"}) do
            local cc = obj:FindFirstChild(c)
            if cc then
                for _, v in ipairs(cc:GetDescendants()) do
                    local nm = string.lower(v.Name)
                    if (nm:find("role") or nm:find("job") or nm:find("team")
                        or nm:find("occupation") or nm:find("class")) then
                        local val
                        if v:IsA("StringValue") then val = v.Value
                        elseif v:IsA("BoolValue") then val = v.Value and v.Name or nil
                        elseif v:IsA("NumberValue") or v:IsA("IntValue") then val = tostring(v.Value) end
                        if val and hitAny(val, CFG.POLICE_KEYS) then return true end
                        if val and (v:IsA("BoolValue") and v.Value and hitAny(v.Name, CFG.POLICE_KEYS)) then
                            return true
                        end
                    end
                end
            end
        end
        return false
    end

    if checkFields(plr) then return true end
    if plr.Character and checkFields(plr.Character) then return true end
    return false
end

local function teamLabel(plr)
    local t = plr.Team
    if t and t.Name and t.Name ~= "" then return t.Name end
    return "无队伍"
end

-- ===== 绘制 =====
local tracked = setmetatable({}, { __mode = "k" })

local function clearESP(plr)
    local data = tracked[plr]
    if not data then return end
    if data.highlight and data.highlight.Parent then data.highlight:Destroy() end
    if data.billboard and data.billboard.Parent then data.billboard:Destroy() end
    tracked[plr] = nil
end

local function applyESP(plr, kind, color)
    local char = plr.Character
    local head = char and char:FindFirstChild("Head")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not (char and head and hum) then return end

    local data = tracked[plr]
    if not data then
        data = {}
        tracked[plr] = data
    end

    if not CFG.USE_HIGHLIGHT then
        if data.highlight and data.highlight.Parent then
            data.highlight:Destroy()
            data.highlight = nil
        end
    elseif not data.highlight or data.highlight.Parent ~= char then
        if data.highlight then data.highlight:Destroy() end
        local hl = Instance.new("Highlight")
        hl.Name = "__ESP_HL"
        hl.Adornee = char
        hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        hl.FillColor = color
        hl.FillTransparency = CFG.FILL_TRANSPARENCY
        hl.OutlineColor = color
        -- 关键：不要描边
        hl.OutlineTransparency = CFG.HIGHLIGHT_OUTLINE and 0.05 or 1
        hl.Parent = char
        data.highlight = hl
    else
        data.highlight.FillColor = color
        data.highlight.FillTransparency = CFG.FILL_TRANSPARENCY
        data.highlight.OutlineColor = color
        data.highlight.OutlineTransparency = CFG.HIGHLIGHT_OUTLINE and 0.05 or 1
    end

    if not data.billboard or data.billboard.Parent ~= head then
        if data.billboard then data.billboard:Destroy() end
        local bb = Instance.new("BillboardGui")
        bb.Name = "__ESP_BB"
        bb.Size = UDim2.new(0, 220, 0, 54)
        bb.StudsOffset = Vector3.new(0, CFG.HEIGHT_OFFSET, 0)
        bb.AlwaysOnTop = true
        bb.Adornee = head
        bb.Parent = head

        local nameLbl = Instance.new("TextLabel")
        nameLbl.Size = UDim2.new(1, 0, 0, 28)
        nameLbl.BackgroundTransparency = 1
        nameLbl.Font = Enum.Font.GothamBold
        nameLbl.TextSize = 16
        nameLbl.TextColor3 = color
        nameLbl.TextStrokeTransparency = 0.35
        nameLbl.Text = plr.Name
        nameLbl.Parent = bb

        local tagLbl = Instance.new("TextLabel")
        tagLbl.Size = UDim2.new(1, 0, 0, 24)
        tagLbl.Position = UDim2.new(0, 0, 0, 26)
        tagLbl.BackgroundTransparency = 1
        tagLbl.Font = Enum.Font.Gotham
        tagLbl.TextSize = 13
        tagLbl.TextColor3 = color
        tagLbl.TextStrokeTransparency = 0.5
        tagLbl.Text = ""
        tagLbl.Visible = CFG.SHOW_TEAMNAME
        tagLbl.Parent = bb

        data.billboard = bb
        data.nameLbl = nameLbl
        data.tagLbl = tagLbl
    else
        if data.nameLbl then data.nameLbl.TextColor3 = color end
        if data.tagLbl then data.tagLbl.TextColor3 = color end
    end

    data.kind = kind
end

-- 距离刷新
RunService.Heartbeat:Connect(function()
    local myRoot = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
    for plr, data in pairs(tracked) do
        local root = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
        if data.nameLbl and myRoot and root then
            local d = math.floor((root.Position - myRoot.Position).Magnitude)
            data.nameLbl.Text = string.format("%s  [%d]", plr.Name, d)
            if data.tagLbl and CFG.SHOW_TEAMNAME then
                local tag = (data.kind == "wanted") and "通缉" or "警察"
                data.tagLbl.Text = tag .. " · " .. teamLabel(plr)
            end
        end
    end
end)

-- 扫描
task.spawn(function()
    out("开始扫描：只显示 通缉(红) 与 警察(蓝)")
    while true do
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LP then
                local char = plr.Character
                local head = char and char:FindFirstChild("Head")
                local hum = char and char:FindFirstChildOfClass("Humanoid")
                if head and hum and hum.Health > 0 then
                    if isWanted(plr) then
                        applyESP(plr, "wanted", CFG.WANTED_COLOR)
                    elseif isPolice(plr) then
                        applyESP(plr, "police", CFG.POLICE_COLOR)
                    else
                        clearESP(plr)
                    end
                else
                    clearESP(plr)
                end
            end
        end
        task.wait(CFG.SCAN_INTERVAL)
    end
end)

Players.PlayerRemoving:Connect(function(p) clearESP(p) end)

out("已启动：红=通缉  蓝=警察  其余不显示")
