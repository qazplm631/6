-- Character ESP: Compact Advanced UI
-- 人物颜色 / 方框颜色 / 距离显示 / 屏幕外预警

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
    warn("[CharacterESP] LocalPlayer unavailable")
    return
end

-- =========================
-- Settings
-- =========================

local CHARACTER_COLOR = Color3.fromRGB(255, 0, 0)
local BOX_COLOR = Color3.fromRGB(0, 0, 0)
local REFRESH_TIME = 1
local BOX_THICKNESS = 2
local BOX_DISTANCE_TEXT_SIZE = 13
local FILL_TRANSPARENCY = 0.2
local MAX_BODY_PART_DISTANCE = 8
local SHOW_OFFSCREEN_WARNING = true
local WARNING_RING_RADIUS = 145
local WARNING_DISTANCE_TEXT_SIZE = 11
local WARNING_ARROW_COLOR = Color3.fromRGB(255, 75, 65)
local WARNING_TEXT_COLOR = Color3.fromRGB(255, 255, 255)

local BODY_PART_NAMES = {
    Head = true,
    HumanoidRootPart = true,
    UpperTorso = true,
    LowerTorso = true,
    Torso = true,
    ["Left Arm"] = true,
    ["Right Arm"] = true,
    ["Left Leg"] = true,
    ["Right Leg"] = true,
    LeftUpperArm = true,
    LeftLowerArm = true,
    LeftHand = true,
    RightUpperArm = true,
    RightLowerArm = true,
    RightHand = true,
    LeftUpperLeg = true,
    LeftLowerLeg = true,
    LeftFoot = true,
    RightUpperLeg = true,
    RightLowerLeg = true,
    RightFoot = true,
}

local Boxes = {}
local Camera = Workspace.CurrentCamera
local GUI

-- =========================
-- Create GUI
-- =========================

local function CreateGUI()
    local playerGui = LocalPlayer:WaitForChild("PlayerGui")
    local oldGui = playerGui:FindFirstChild("CharacterESP")

    if oldGui then
        oldGui:Destroy()
    end

    GUI = Instance.new("ScreenGui")
    GUI.Name = "CharacterESP"
    GUI.IgnoreGuiInset = true
    GUI.ResetOnSpawn = false
    GUI.DisplayOrder = 999
    GUI.Parent = playerGui
end

CreateGUI()

-- =========================
-- Get body parts
-- =========================

local function GetBodyParts(model)
    local parts = {}

    if not model then
        return parts
    end

    for _, object in ipairs(model:GetDescendants()) do
        if object:IsA("BasePart")
            and BODY_PART_NAMES[object.Name] then
            table.insert(parts, object)
        end
    end

    return parts
end

-- =========================
-- Check target
-- =========================

local function IsTarget(model)
    if not model or not model:IsA("Model") then
        return false
    end

    if not model:IsDescendantOf(Workspace) then
        return false
    end

    if model == LocalPlayer.Character then
        return false
    end

    local humanoid = model:FindFirstChildOfClass("Humanoid")

    if not humanoid or humanoid.Health <= 0 then
        return false
    end

    local root = model:FindFirstChild("HumanoidRootPart")
    local head = model:FindFirstChild("Head")

    local torso =
        model:FindFirstChild("UpperTorso")
        or model:FindFirstChild("Torso")
        or model:FindFirstChild("LowerTorso")

    if not root or not root:IsA("BasePart") then
        return false
    end

    if not head or not head:IsA("BasePart") then
        return false
    end

    if not torso or not torso:IsA("BasePart") then
        return false
    end

    local parts = GetBodyParts(model)

    return #parts >= 5
end

-- =========================
-- Character coloring
-- =========================

local function PaintCharacter(model)
    if not IsTarget(model) then
        return
    end

    for _, part in ipairs(GetBodyParts(model)) do
        if part.Name ~= "HumanoidRootPart" then
            part.Color = CHARACTER_COLOR
        end
    end

    local bodyColors = model:FindFirstChildOfClass("BodyColors")

    if bodyColors then
        bodyColors.HeadColor3 = CHARACTER_COLOR
        bodyColors.TorsoColor3 = CHARACTER_COLOR
        bodyColors.LeftArmColor3 = CHARACTER_COLOR
        bodyColors.RightArmColor3 = CHARACTER_COLOR
        bodyColors.LeftLegColor3 = CHARACTER_COLOR
        bodyColors.RightLegColor3 = CHARACTER_COLOR
    end

    local highlight = model:FindFirstChild("LocalColorHighlight")

    if not highlight or not highlight:IsA("Highlight") then
        if highlight then
            highlight:Destroy()
        end

        highlight = Instance.new("Highlight")
        highlight.Name = "LocalColorHighlight"
        highlight.Parent = model
    end

    highlight.Adornee = model
    highlight.FillColor = CHARACTER_COLOR
    highlight.OutlineColor = CHARACTER_COLOR
    highlight.FillTransparency = FILL_TRANSPARENCY
    highlight.OutlineTransparency = 0
    highlight.DepthMode = Enum.HighlightDepthMode.Occluded
end

-- =========================
-- Color controls
-- =========================

local function ColorToHex(color)
    return string.format(
        "#%02X%02X%02X",
        math.floor(color.R * 255 + 0.5),
        math.floor(color.G * 255 + 0.5),
        math.floor(color.B * 255 + 0.5)
    )
end

local function ApplyCurrentColors()
    for model, record in pairs(Boxes) do
        if model and model.Parent and IsTarget(model) then
            PaintCharacter(model)
        end

        local frame = record and record.Frame
        local stroke = frame and frame:FindFirstChildOfClass("UIStroke")

        if stroke then
            stroke.Color = BOX_COLOR
        end
    end
end

-- =========================
-- Compact UI
-- =========================

local function CreateColorUI()

    local BG = Color3.fromRGB(20, 22, 29)
    local CARD = Color3.fromRGB(29, 32, 41)
    local FIELD = Color3.fromRGB(39, 43, 54)
    local TEXT = Color3.fromRGB(238, 240, 245)
    local MUTED = Color3.fromRGB(153, 160, 174)
    local ACCENT = Color3.fromRGB(76, 116, 176)

    local function corner(object, radius)
        local item = Instance.new("UICorner")
        item.CornerRadius = UDim.new(0, radius or 7)
        item.Parent = object
    end

    local function addStroke(object, color, transparency)
        local item = Instance.new("UIStroke")
        item.Color = color or Color3.fromRGB(65, 71, 86)
        item.Transparency = transparency or 0.4
        item.Thickness = 1
        item.Parent = object
    end

    local function label(parent, text, position, size, textSize, color)
        local item = Instance.new("TextLabel")
        item.BackgroundTransparency = 1
        item.Position = position
        item.Size = size
        item.Font = Enum.Font.GothamMedium
        item.Text = text
        item.TextColor3 = color or TEXT
        item.TextSize = textSize or 11
        item.TextXAlignment = Enum.TextXAlignment.Left
        item.TextYAlignment = Enum.TextYAlignment.Center
        item.Parent = parent
        return item
    end

    local function button(parent, text, position, size, color)
        local item = Instance.new("TextButton")
        item.Position = position
        item.Size = size
        item.BackgroundColor3 = color or FIELD
        item.BorderSizePixel = 0
        item.Font = Enum.Font.GothamSemibold
        item.Text = text
        item.TextColor3 = TEXT
        item.TextSize = 11
        item.AutoButtonColor = true
        item.Parent = parent
        corner(item, 6)
        return item
    end

    local function textBox(parent, name, value, position, size, placeholder)
        local item = Instance.new("TextBox")
        item.Name = name
        item.Position = position
        item.Size = size
        item.BackgroundColor3 = FIELD
        item.BorderSizePixel = 0
        item.ClearTextOnFocus = false
        item.Font = Enum.Font.GothamMedium
        item.Text = tostring(value)
        item.PlaceholderText = placeholder or "输入数值"
        item.TextColor3 = TEXT
        item.PlaceholderColor3 = MUTED
        item.TextSize = 11
        item.TextXAlignment = Enum.TextXAlignment.Center
        item.Parent = parent
        corner(item, 6)
        return item
    end

    local toggle = button(
        GUI,
        "ESP 设置",
        UDim2.fromOffset(12, 96),
        UDim2.fromOffset(88, 30),
        Color3.fromRGB(32, 37, 48)
    )

    toggle.Name = "ESP_SettingsToggle"

    local panel = Instance.new("Frame")
    panel.Name = "ESP_SettingsPanel"
    panel.Position = UDim2.fromOffset(12, 132)
    panel.Size = UDim2.fromOffset(270, 432)
    panel.BackgroundColor3 = BG
    panel.BorderSizePixel = 0
    panel.Visible = false
    panel.Active = true
    panel.ClipsDescendants = true
    panel.Parent = GUI

    corner(panel, 10)
    addStroke(panel, Color3.fromRGB(91, 103, 126), 0.25)

    local header = Instance.new("Frame")
    header.Name = "DragHeader"
    header.Size = UDim2.new(1, 0, 0, 34)
    header.BackgroundColor3 = Color3.fromRGB(34, 38, 49)
    header.BorderSizePixel = 0
    header.Active = true
    header.Parent = panel

    corner(header, 9)

    label(
        header,
        "ESP SETTINGS",
        UDim2.fromOffset(11, 0),
        UDim2.new(1, -52, 1, 0),
        12,
        TEXT
    )

    local closeButton = button(
        header,
        "×",
        UDim2.new(1, -30, 0, 4),
        UDim2.fromOffset(24, 24),
        Color3.fromRGB(65, 48, 55)
    )

    closeButton.TextSize = 16

    local function makeCard(name, y, height, title)
        local card = Instance.new("Frame")
        card.Name = name
        card.Position = UDim2.fromOffset(8, y)
        card.Size = UDim2.new(1, -16, 0, height)
        card.BackgroundColor3 = CARD
        card.BorderSizePixel = 0
        card.Parent = panel

        corner(card, 8)
        addStroke(card, Color3.fromRGB(65, 72, 88), 0.6)

        label(
            card,
            title,
            UDim2.fromOffset(10, 3),
            UDim2.new(1, -20, 0, 18),
            11,
            TEXT
        )

        return card
    end

    -- 人物颜色

    local characterCard = makeCard(
        "CharacterColorSection",
        42,
        86,
        "人物颜色"
    )

    local characterHex = textBox(
        characterCard,
        "CharacterColorHex",
        ColorToHex(CHARACTER_COLOR),
        UDim2.fromOffset(10, 24),
        UDim2.fromOffset(150, 24),
        "#RRGGBB"
    )

    local applyCharacter = button(
        characterCard,
        "应用",
        UDim2.fromOffset(166, 24),
        UDim2.fromOffset(76, 24),
        ACCENT
    )

    -- 方框颜色

    local boxCard = makeCard(
        "BoxColorSection",
        134,
        86,
        "方框颜色"
    )

    local boxHex = textBox(
        boxCard,
        "BoxColorHex",
        ColorToHex(BOX_COLOR),
        UDim2.fromOffset(10, 24),
        UDim2.fromOffset(150, 24),
        "#RRGGBB"
    )

    local applyBox = button(
        boxCard,
        "应用",
        UDim2.fromOffset(166, 24),
        UDim2.fromOffset(76, 24),
        ACCENT
    )

    local characterPresets = {
        Color3.fromRGB(255, 65, 65),
        Color3.fromRGB(60, 220, 125),
        Color3.fromRGB(65, 155, 255),
        Color3.fromRGB(255, 210, 65),
        Color3.fromRGB(190, 105, 255),
        Color3.fromRGB(245, 245, 245),
    }

    local boxPresets = {
        Color3.fromRGB(0, 0, 0),
        Color3.fromRGB(245, 245, 245),
        Color3.fromRGB(255, 80, 80),
        Color3.fromRGB(60, 220, 125),
        Color3.fromRGB(65, 180, 255),
        Color3.fromRGB(255, 210, 65),
    }

    local status = label(
        panel,
        "就绪 · 修改后点击应用",
        UDim2.fromOffset(10, 405),
        UDim2.fromOffset(250, 18),
        9,
        MUTED
    )

    local function setStatus(message, isError)
        status.Text = message
        status.TextColor3 = isError
            and Color3.fromRGB(255, 135, 125)
            or MUTED
    end

    local function setColor(which, color)
        if which == "character" then
            CHARACTER_COLOR = color
            characterHex.Text = ColorToHex(color)
            setStatus("人物颜色已应用")
        else
            BOX_COLOR = color
            boxHex.Text = ColorToHex(color)
            setStatus("方框颜色已应用")
        end

        ApplyCurrentColors()
    end

    local function applyHex(which, input)
        local hex = (input.Text or "")
            :gsub("%s", "")
            :gsub("^#", "")

        if #hex ~= 6 or not hex:match("^%x%x%x%x%x%x$") then
            setStatus("HEX 格式错误，请输入 #RRGGBB", true)
            return
        end

        local r = tonumber(hex:sub(1, 2), 16)
        local g = tonumber(hex:sub(3, 4), 16)
        local b = tonumber(hex:sub(5, 6), 16)

        setColor(which, Color3.fromRGB(r, g, b))
    end

    local function makeSwatches(parent, colors, which)
        for index, color in ipairs(colors) do
            local swatch = Instance.new("TextButton")

            swatch.Name = which .. "Preset" .. index
            swatch.Position = UDim2.fromOffset(
                10 + (index - 1) * 38,
                55
            )

            swatch.Size = UDim2.fromOffset(30, 21)
            swatch.BackgroundColor3 = color
            swatch.BorderSizePixel = 0
            swatch.Text = ""
            swatch.AutoButtonColor = true
            swatch.Parent = parent

            corner(swatch, 5)
            addStroke(swatch, Color3.fromRGB(220, 225, 235), 0.6)

            local selectedColor = color

            swatch.Activated:Connect(function()
                setColor(which, selectedColor)
            end)
        end
    end

    makeSwatches(characterCard, characterPresets, "character")
    makeSwatches(boxCard, boxPresets, "box")

    -- 数值设置

    local settingsCard = makeCard(
        "WarningAndTextSection",
        226,
        174,
        "显示参数"
    )

    local function makeNumberRow(
        y,
        title,
        currentValue,
        placeholder,
        callback
    )
        label(
            settingsCard,
            title,
            UDim2.fromOffset(10, y),
            UDim2.fromOffset(104, 24),
            10,
            MUTED
        )

        local input = textBox(
            settingsCard,
            "ValueInput",
            currentValue,
            UDim2.fromOffset(116, y),
            UDim2.fromOffset(70, 24),
            placeholder
        )

        local apply = button(
            settingsCard,
            "应用",
            UDim2.fromOffset(192, y),
            UDim2.fromOffset(50, 24),
            ACCENT
        )

        apply.Activated:Connect(function()
            local value = tonumber(input.Text)
            local ok, message = callback(value)

            setStatus(message, not ok)

            if ok then
                input.Text = tostring(value)
            end
        end)

        return input
    end

    -- 方框距离字号

    makeNumberRow(
        27,
        "方框距离字号",
        BOX_DISTANCE_TEXT_SIZE,
        "6-30",
        function(value)

            if not value
                or value ~= math.floor(value)
                or value < 6
                or value > 30 then

                return false, "方框距离字号范围：6-30"
            end

            BOX_DISTANCE_TEXT_SIZE = value

            for _, record in pairs(Boxes) do
                if record.BoxDistance then
                    record.BoxDistance.TextSize = value
                    record.BoxDistance.Size = UDim2.fromOffset(
                        84,
                        math.max(16, value + 7)
                    )
                end
            end

            return true, "方框距离字号已更新：" .. value
        end
    )

    -- 预警距屏幕中心

    makeNumberRow(
        65,
        "预警中心距离",
        WARNING_RING_RADIUS,
        "40-600",
        function(value)

            if not value
                or value ~= math.floor(value)
                or value < 40
                or value > 600 then

                return false, "预警中心距离范围：40-600 px"
            end

            WARNING_RING_RADIUS = value

            return true, "预警位置已更新：" .. value .. "px"
        end
    )

    -- 箭头距离字号

    makeNumberRow(
        103,
        "箭头距离字号",
        WARNING_DISTANCE_TEXT_SIZE,
        "8-24",
        function(value)

            if not value
                or value ~= math.floor(value)
                or value < 8
                or value > 24 then

                return false, "箭头距离字号范围：8-24"
            end

            WARNING_DISTANCE_TEXT_SIZE = value

            for _, record in pairs(Boxes) do
                if record.Distance then
                    record.Distance.TextSize = value
                    record.Distance.Size = UDim2.fromOffset(
                        76,
                        math.max(18, value + 7)
                    )
                end

                if record.Warning then
                    record.Warning.Size = UDim2.fromOffset(
                        76,
                        29 + math.max(18, value + 7)
                    )
                end
            end

            return true, "箭头距离字号已更新：" .. value
        end
    )

    label(
        settingsCard,
        "预警位置会受屏幕边缘限制",
        UDim2.fromOffset(10, 142),
        UDim2.new(1, -20, 0, 18),
        9,
        MUTED
    )

    applyCharacter.Activated:Connect(function()
        applyHex("character", characterHex)
    end)

    applyBox.Activated:Connect(function()
        applyHex("box", boxHex)
    end)

    toggle.Activated:Connect(function()
        panel.Visible = not panel.Visible
    end)

    closeButton.Activated:Connect(function()
        panel.Visible = false
    end)

    -- 手机触屏拖动

    local dragging = false
    local dragStart
    local startPosition

    header.InputBegan:Connect(function(input)

        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then

            dragging = true
            dragStart = input.Position
            startPosition = panel.Position

            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)

    UserInputService.InputChanged:Connect(function(input)

        if dragging
            and (
                input.UserInputType == Enum.UserInputType.MouseMovement
                or input.UserInputType == Enum.UserInputType.Touch
            ) then

            local delta = input.Position - dragStart

            panel.Position = UDim2.new(
                startPosition.X.Scale,
                startPosition.X.Offset + delta.X,
                startPosition.Y.Scale,
                startPosition.Y.Offset + delta.Y
            )
        end
    end)
end

-- =========================
-- Create 2D box
-- =========================

local function CreateBox(model)

    if Boxes[model] or not GUI then
        return
    end

    local frame = Instance.new("Frame")

    frame.Name = "ESP_Box"
    frame.BackgroundTransparency = 1
    frame.BorderSizePixel = 0
    frame.Visible = false
    frame.Parent = GUI

    local stroke = Instance.new("UIStroke")

    stroke.Color = BOX_COLOR
    stroke.Thickness = BOX_THICKNESS
    stroke.Transparency = 0
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Parent = frame

    -- 方框下方距离

    local boxDistanceLabel = Instance.new("TextLabel")

    boxDistanceLabel.Name = "ESP_BoxDistance"
    boxDistanceLabel.AnchorPoint = Vector2.new(0.5, 0)
    boxDistanceLabel.Size = UDim2.fromOffset(
        84,
        math.max(16, BOX_DISTANCE_TEXT_SIZE + 7)
    )

    boxDistanceLabel.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
    boxDistanceLabel.BackgroundTransparency = 0.2
    boxDistanceLabel.BorderSizePixel = 0
    boxDistanceLabel.Font = Enum.Font.GothamBold
    boxDistanceLabel.Text = ""
    boxDistanceLabel.TextSize = BOX_DISTANCE_TEXT_SIZE
    boxDistanceLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    boxDistanceLabel.TextStrokeTransparency = 0.5
    boxDistanceLabel.Visible = false
    boxDistanceLabel.Parent = GUI

    local boxDistanceCorner = Instance.new("UICorner")
    boxDistanceCorner.CornerRadius = UDim.new(0, 5)
    boxDistanceCorner.Parent = boxDistanceLabel

    -- 屏幕外箭头

    local warningHolder = Instance.new("Frame")

    warningHolder.Name = "ESP_Warning"
    warningHolder.AnchorPoint = Vector2.new(0.5, 0.5)
    warningHolder.Size = UDim2.fromOffset(
        76,
        29 + math.max(18, WARNING_DISTANCE_TEXT_SIZE + 7)
    )

    warningHolder.BackgroundTransparency = 1
    warningHolder.Visible = false
    warningHolder.Parent = GUI

    local arrow = Instance.new("TextLabel")

    arrow.Name = "Arrow"
    arrow.BackgroundTransparency = 1
    arrow.Position = UDim2.fromOffset(18, 0)
    arrow.Size = UDim2.fromOffset(40, 30)
    arrow.Font = Enum.Font.GothamBlack
    arrow.Text = "▶"
    arrow.TextSize = 30
    arrow.TextColor3 = WARNING_ARROW_COLOR
    arrow.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    arrow.TextStrokeTransparency = 0.15
    arrow.Parent = warningHolder

    local distanceLabel = Instance.new("TextLabel")

    distanceLabel.Name = "Distance"
    distanceLabel.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
    distanceLabel.BackgroundTransparency = 0.2
    distanceLabel.BorderSizePixel = 0
    distanceLabel.Position = UDim2.fromOffset(0, 29)
    distanceLabel.Size = UDim2.fromOffset(
        76,
        math.max(18, WARNING_DISTANCE_TEXT_SIZE + 7)
    )

    distanceLabel.Font = Enum.Font.GothamBold
    distanceLabel.Text = ""
    distanceLabel.TextSize = WARNING_DISTANCE_TEXT_SIZE
    distanceLabel.TextColor3 = WARNING_TEXT_COLOR
    distanceLabel.TextStrokeTransparency = 0.5
    distanceLabel.Parent = warningHolder

    local distanceCorner = Instance.new("UICorner")
    distanceCorner.CornerRadius = UDim.new(0, 5)
    distanceCorner.Parent = distanceLabel

    Boxes[model] = {
        Frame = frame,
        BoxDistance = boxDistanceLabel,
        Parts = GetBodyParts(model),
        Warning = warningHolder,
        Arrow = arrow,
        Distance = distanceLabel,
    }
end

-- =========================
-- Enemy check
-- =========================

local function IsEnemyForWarning(model)

    local targetPlayer = Players:GetPlayerFromCharacter(model)

    if targetPlayer and LocalPlayer.Team and targetPlayer.Team then
        return targetPlayer.Team ~= LocalPlayer.Team
    end

    return true
end

-- =========================
-- Offscreen warning
-- =========================

local function UpdateOffscreenWarning(model, record)

    local holder = record and record.Warning
    local arrow = record and record.Arrow
    local distanceLabel = record and record.Distance

    if not holder or not arrow or not distanceLabel then
        return
    end

    if not SHOW_OFFSCREEN_WARNING
        or not IsTarget(model)
        or not IsEnemyForWarning(model) then

        holder.Visible = false
        return
    end

    Camera = Workspace.CurrentCamera

    local root = model:FindFirstChild("HumanoidRootPart")

    if not Camera or not root or not root:IsA("BasePart") then
        holder.Visible = false
        return
    end

    local projected, onScreen =
        Camera:WorldToViewportPoint(root.Position)

    local viewport = Camera.ViewportSize

    local isOffscreen =
        projected.Z <= 0
        or not onScreen
        or projected.X < 0
        or projected.X > viewport.X
        or projected.Y < 0
        or projected.Y > viewport.Y

    if not isOffscreen then
        holder.Visible = false
        return
    end

    local localPosition =
        Camera.CFrame:PointToObjectSpace(root.Position)

    local dx = localPosition.X
    local dy = -localPosition.Y

    if localPosition.Z > 0 then
        dx = -dx
        dy = -dy
    end

    local magnitude = math.sqrt(dx * dx + dy * dy)

    if magnitude < 0.001 then
        dx, dy = 0, 1
        magnitude = 1
    end

    dx = dx / magnitude
    dy = dy / magnitude

    local center = viewport / 2

    local holderHalfX = holder.AbsoluteSize.X / 2
    local holderHalfY = holder.AbsoluteSize.Y / 2

    local maxRadius = math.max(
        0,
        math.min(
            viewport.X / 2 - holderHalfX - 4,
            viewport.Y / 2 - holderHalfY - 4
        )
    )

    local radius = math.min(
        WARNING_RING_RADIUS,
        maxRadius
    )

    local screenX = center.X + dx * radius
    local screenY = center.Y + dy * radius

    holder.Position = UDim2.fromOffset(screenX, screenY)

    arrow.Rotation = math.deg(math.atan2(dy, dx))

    local distance =
        (root.Position - Camera.CFrame.Position).Magnitude

    distanceLabel.Text = string.format("%.0f", distance)

    holder.Visible = true
end

-- =========================
-- Update box
-- =========================

local function UpdateBox(model, record)

    local frame = record and record.Frame
    local distanceLabel = record and record.BoxDistance

    if not frame or not distanceLabel then
        return
    end

    local function HideBox()
        frame.Visible = false
        distanceLabel.Visible = false
    end

    if not IsTarget(model) then
        HideBox()

        if record.Warning then
            record.Warning.Visible = false
        end

        return
    end

    Camera = Workspace.CurrentCamera

    if not Camera then
        HideBox()
        return
    end

    local root = model:FindFirstChild("HumanoidRootPart")

    if not root or not root:IsA("BasePart") then
        HideBox()
        return
    end

    local rootScreen, rootOnScreen =
        Camera:WorldToViewportPoint(root.Position)

    if rootScreen.Z <= 0 then
        HideBox()
        return
    end

    local minX, minY = math.huge, math.huge
    local maxX, maxY = -math.huge, -math.huge

    local projectedCount = 0
    local validParts = 0

    for _, part in ipairs(record.Parts) do

        if part
            and part.Parent
            and part:IsA("BasePart")
            and (part.Position - root.Position).Magnitude <= MAX_BODY_PART_DISTANCE then

            validParts += 1

            local half = part.Size / 2

            for x = -1, 1, 2 do
                for y = -1, 1, 2 do
                    for z = -1, 1, 2 do

                        local worldPosition =
                            part.CFrame:PointToWorldSpace(
                                Vector3.new(
                                    half.X * x,
                                    half.Y * y,
                                    half.Z * z
                                )
                            )

                        local screenPosition =
                            Camera:WorldToViewportPoint(worldPosition)

                        if screenPosition.Z > 0 then

                            projectedCount += 1

                            minX = math.min(minX, screenPosition.X)
                            minY = math.min(minY, screenPosition.Y)

                            maxX = math.max(maxX, screenPosition.X)
                            maxY = math.max(maxY, screenPosition.Y)
                        end
                    end
                end
            end
        end
    end

    if validParts < 4 or projectedCount < 4 then
        HideBox()
        return
    end

    local viewport = Camera.ViewportSize

    minX = math.clamp(minX, 0, viewport.X)
    minY = math.clamp(minY, 0, viewport.Y)

    maxX = math.clamp(maxX, 0, viewport.X)
    maxY = math.clamp(maxY, 0, viewport.Y)

    if maxX - minX < 2 or maxY - minY < 2 then
        HideBox()
        return
    end

    frame.Position = UDim2.fromOffset(minX, minY)

    frame.Size = UDim2.fromOffset(
        maxX - minX,
        maxY - minY
    )

    local stroke = frame:FindFirstChildOfClass("UIStroke")

    if stroke then
        stroke.Color = BOX_COLOR
        stroke.Thickness = BOX_THICKNESS
        stroke.Transparency = 0
    end

    local distance =
        (root.Position - Camera.CFrame.Position).Magnitude

    distanceLabel.Text = string.format("%.0f", distance)

    local labelHalfWidth = distanceLabel.Size.X.Offset / 2

    local labelX = math.clamp(
        (minX + maxX) / 2,
        labelHalfWidth,
        math.max(labelHalfWidth, viewport.X - labelHalfWidth)
    )

    local labelY = math.clamp(
        maxY + 4,
        0,
        math.max(0, viewport.Y - distanceLabel.Size.Y.Offset)
    )

    distanceLabel.Position = UDim2.fromOffset(labelX, labelY)

    frame.Visible = true
    distanceLabel.Visible = true
end

-- =========================
-- Scan workspace
-- =========================

local function ScanAll()

    for _, object in ipairs(Workspace:GetDescendants()) do

        if object:IsA("Model") and IsTarget(object) then

            PaintCharacter(object)

            if not Boxes[object] then
                CreateBox(object)
            else
                Boxes[object].Parts = GetBodyParts(object)
            end
        end
    end
end

-- =========================
-- Start
-- =========================

CreateColorUI()

ScanAll()

task.spawn(function()

    while GUI and GUI.Parent do

        task.wait(REFRESH_TIME)

        ScanAll()
    end
end)

RunService.RenderStepped:Connect(function()

    Camera = Workspace.CurrentCamera

    for model, record in pairs(Boxes) do

        local frame = record and record.Frame

        if model and model.Parent and frame and frame.Parent then

            UpdateBox(model, record)
            UpdateOffscreenWarning(model, record)

        else

            if frame then
                frame:Destroy()
            end

            if record and record.Warning then
                record.Warning:Destroy()
            end

            if record and record.BoxDistance then
                record.BoxDistance:Destroy()
            end

            Boxes[model] = nil
        end
    end
end)

print("[CharacterESP] Compact Advanced UI loaded.")