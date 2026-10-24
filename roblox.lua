-- Roblox ESP + Fly UI (mobile-friendly)
-- 仅建议在自建或获准测试的体验中使用。

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then return end

local flySpeed = 55

-- Remove a previous copy.
for _, parent in ipairs({game:GetService("CoreGui"), LocalPlayer:FindFirstChildOfClass("PlayerGui")}) do
    if parent then
        local old = parent:FindFirstChild("NinjaESPFlyMobile")
        if old then pcall(function() old:Destroy() end) end
    end
end

local gui = Instance.new("ScreenGui")
gui.Name = "NinjaESPFlyMobile"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.DisplayOrder = 999
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

-- Prefer PlayerGui: some mobile injectors render CoreGui overlays but do not
-- route touch input to them reliably. Fall back to CoreGui only if needed.
local playerGui = LocalPlayer:WaitForChild("PlayerGui")
local parented = pcall(function()
    gui.Parent = playerGui
end)
if not parented or not gui.Parent then
    pcall(function() gui.Parent = game:GetService("CoreGui") end)
end

-- Animated mobile loading splash. This is a visual intro only; it does not
-- block the script from creating the main controls underneath it.
local loadingOverlay = Instance.new("Frame")
loadingOverlay.Name = "LoadingOverlay"
loadingOverlay.Size = UDim2.fromScale(1, 1)
loadingOverlay.Position = UDim2.fromScale(0, 0)
loadingOverlay.BackgroundColor3 = Color3.fromRGB(9, 12, 24)
loadingOverlay.BackgroundTransparency = 0.04
loadingOverlay.BorderSizePixel = 0
loadingOverlay.ZIndex = 100
loadingOverlay.Parent = gui

local overlayGradient = Instance.new("UIGradient")
overlayGradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(10, 15, 34)),
    ColorSequenceKeypoint.new(0.55, Color3.fromRGB(25, 18, 51)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(6, 28, 39)),
})
overlayGradient.Rotation = 25
overlayGradient.Parent = loadingOverlay

local loadingCard = Instance.new("Frame")
loadingCard.Name = "LoadingCard"
loadingCard.AnchorPoint = Vector2.new(0.5, 0.5)
loadingCard.Position = UDim2.fromScale(0.5, 0.5)
loadingCard.Size = UDim2.fromOffset(292, 282)
loadingCard.BackgroundColor3 = Color3.fromRGB(19, 23, 41)
loadingCard.BorderSizePixel = 0
loadingCard.ZIndex = 101
loadingCard.Parent = loadingOverlay
local loadingCardCorner = Instance.new("UICorner")
loadingCardCorner.CornerRadius = UDim.new(0, 20)
loadingCardCorner.Parent = loadingCard
local loadingCardStroke = Instance.new("UIStroke")
loadingCardStroke.Color = Color3.fromRGB(74, 231, 220)
loadingCardStroke.Thickness = 1.5
loadingCardStroke.Transparency = 0.18
loadingCardStroke.Parent = loadingCard
local cardGradient = Instance.new("UIGradient")
cardGradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(27, 35, 62)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(17, 25, 38)),
})
cardGradient.Rotation = 90
cardGradient.Parent = loadingCard

local loadingEyebrow = Instance.new("TextLabel")
loadingEyebrow.BackgroundTransparency = 1
loadingEyebrow.Position = UDim2.fromOffset(18, 15)
loadingEyebrow.Size = UDim2.new(1, -36, 0, 18)
loadingEyebrow.Font = Enum.Font.GothamSemibold
loadingEyebrow.Text = "MOBILE EDITION  /  INITIALIZING"
loadingEyebrow.TextColor3 = Color3.fromRGB(100, 224, 219)
loadingEyebrow.TextSize = 10
loadingEyebrow.ZIndex = 102
loadingEyebrow.Parent = loadingCard

local ringOuter = Instance.new("Frame")
ringOuter.Name = "OuterEnergyRing"
ringOuter.AnchorPoint = Vector2.new(0.5, 0.5)
ringOuter.Position = UDim2.new(0.5, 0, 0, 100)
ringOuter.Size = UDim2.fromOffset(82, 82)
ringOuter.BackgroundTransparency = 1
ringOuter.BorderSizePixel = 0
ringOuter.ZIndex = 102
ringOuter.Parent = loadingCard
local ringOuterCorner = Instance.new("UICorner")
ringOuterCorner.CornerRadius = UDim.new(1, 0)
ringOuterCorner.Parent = ringOuter
local ringOuterStroke = Instance.new("UIStroke")
ringOuterStroke.Color = Color3.fromRGB(75, 235, 218)
ringOuterStroke.Thickness = 3
ringOuterStroke.Transparency = 0.08
ringOuterStroke.Parent = ringOuter

local ringInner = Instance.new("Frame")
ringInner.Name = "InnerEnergyRing"
ringInner.AnchorPoint = Vector2.new(0.5, 0.5)
ringInner.Position = UDim2.new(0.5, 0, 0.5, 0)
ringInner.Size = UDim2.fromOffset(61, 61)
ringInner.BackgroundTransparency = 1
ringInner.BorderSizePixel = 0
ringInner.ZIndex = 103
ringInner.Parent = ringOuter
local ringInnerCorner = Instance.new("UICorner")
ringInnerCorner.CornerRadius = UDim.new(1, 0)
ringInnerCorner.Parent = ringInner
local ringInnerStroke = Instance.new("UIStroke")
ringInnerStroke.Color = Color3.fromRGB(150, 103, 255)
ringInnerStroke.Thickness = 2
ringInnerStroke.Transparency = 0.12
ringInnerStroke.Parent = ringInner

local loadingLogo = Instance.new("TextLabel")
loadingLogo.AnchorPoint = Vector2.new(0.5, 0.5)
loadingLogo.Position = UDim2.fromScale(0.5, 0.5)
loadingLogo.Size = UDim2.fromOffset(48, 48)
loadingLogo.BackgroundTransparency = 1
loadingLogo.Font = Enum.Font.GothamBlack
loadingLogo.Text = "N"
loadingLogo.TextColor3 = Color3.fromRGB(255, 255, 255)
loadingLogo.TextSize = 34
loadingLogo.ZIndex = 104
loadingLogo.Parent = ringOuter

local loadingTitle = Instance.new("TextLabel")
loadingTitle.BackgroundTransparency = 1
loadingTitle.Position = UDim2.fromOffset(14, 151)
loadingTitle.Size = UDim2.new(1, -28, 0, 34)
loadingTitle.Font = Enum.Font.GothamBlack
loadingTitle.Text = "NINJA HUB"
loadingTitle.TextColor3 = Color3.fromRGB(245, 248, 255)
loadingTitle.TextSize = 25
loadingTitle.ZIndex = 102
loadingTitle.Parent = loadingCard

local loadingSubtitle = Instance.new("TextLabel")
loadingSubtitle.BackgroundTransparency = 1
loadingSubtitle.Position = UDim2.fromOffset(16, 187)
loadingSubtitle.Size = UDim2.new(1, -32, 0, 20)
loadingSubtitle.Font = Enum.Font.Gotham
loadingSubtitle.Text = "正在初始化手机界面..."
loadingSubtitle.TextColor3 = Color3.fromRGB(173, 185, 211)
loadingSubtitle.TextSize = 12
loadingSubtitle.ZIndex = 102
loadingSubtitle.Parent = loadingCard

local progressTrack = Instance.new("Frame")
progressTrack.Position = UDim2.fromOffset(24, 221)
progressTrack.Size = UDim2.new(1, -48, 0, 7)
progressTrack.BackgroundColor3 = Color3.fromRGB(43, 51, 74)
progressTrack.BorderSizePixel = 0
progressTrack.ZIndex = 102
progressTrack.Parent = loadingCard
local progressTrackCorner = Instance.new("UICorner")
progressTrackCorner.CornerRadius = UDim.new(1, 0)
progressTrackCorner.Parent = progressTrack

local progressFill = Instance.new("Frame")
progressFill.Name = "ProgressFill"
progressFill.Size = UDim2.new(0, 0, 1, 0)
progressFill.BackgroundColor3 = Color3.fromRGB(74, 231, 220)
progressFill.BorderSizePixel = 0
progressFill.ZIndex = 103
progressFill.Parent = progressTrack
local progressFillCorner = Instance.new("UICorner")
progressFillCorner.CornerRadius = UDim.new(1, 0)
progressFillCorner.Parent = progressFill
local progressGradient = Instance.new("UIGradient")
progressGradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(68, 231, 215)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(163, 104, 255)),
})
progressGradient.Parent = progressFill

local loadingHint = Instance.new("TextLabel")
loadingHint.BackgroundTransparency = 1
loadingHint.Position = UDim2.fromOffset(20, 238)
loadingHint.Size = UDim2.new(1, -40, 0, 20)
loadingHint.Font = Enum.Font.GothamSemibold
loadingHint.Text = "LOADING  0%"
loadingHint.TextColor3 = Color3.fromRGB(120, 228, 220)
loadingHint.TextSize = 10
loadingHint.ZIndex = 102
loadingHint.Parent = loadingCard

local outerSpinTween = TweenService:Create(
    ringOuter,
    TweenInfo.new(2.4, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, -1),
    {Rotation = 360}
)
local innerSpinTween = TweenService:Create(
    ringInner,
    TweenInfo.new(1.6, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, -1),
    {Rotation = -360}
)
local progressTween = TweenService:Create(
    progressFill,
    TweenInfo.new(2.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
    {Size = UDim2.new(1, 0, 1, 0)}
)
local logoPulseTween = TweenService:Create(
    loadingLogo,
    TweenInfo.new(0.55, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
    {TextSize = 38, TextColor3 = Color3.fromRGB(117, 255, 239)}
)
outerSpinTween:Play()
innerSpinTween:Play()
progressTween:Play()
logoPulseTween:Play()

task.spawn(function()
    for percent = 1, 100 do
        if not loadingOverlay.Parent then return end
        loadingHint.Text = "LOADING  " .. tostring(percent) .. "%"
        if percent == 34 then
            loadingSubtitle.Text = "正在加载界面组件..."
        elseif percent == 68 then
            loadingSubtitle.Text = "正在准备触控按钮..."
        end
        task.wait(2.25 / 100)
    end

    loadingSubtitle.Text = "初始化完成"
    task.wait(0.22)
    outerSpinTween:Cancel()
    innerSpinTween:Cancel()
    logoPulseTween:Cancel()

    local fadeInfo = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    local fadeTasks = {
        TweenService:Create(loadingOverlay, fadeInfo, {BackgroundTransparency = 1}),
    }
    for _, object in ipairs(loadingOverlay:GetDescendants()) do
        if object:IsA("GuiObject") then
            local properties = {BackgroundTransparency = 1}
            if object:IsA("TextLabel") or object:IsA("TextButton") or object:IsA("TextBox") then
                properties.TextTransparency = 1
                properties.TextStrokeTransparency = 1
            elseif object:IsA("ImageLabel") or object:IsA("ImageButton") then
                properties.ImageTransparency = 1
            end
            fadeTasks[#fadeTasks + 1] = TweenService:Create(object, fadeInfo, properties)
        elseif object:IsA("UIStroke") then
            fadeTasks[#fadeTasks + 1] = TweenService:Create(object, fadeInfo, {Transparency = 1})
        end
    end
    for _, tween in ipairs(fadeTasks) do tween:Play() end
    task.wait(0.4)
    if loadingOverlay.Parent then loadingOverlay:Destroy() end
end)

local frame = Instance.new("Frame")
frame.Name = "Main"
frame.Size = UDim2.fromOffset(300, 622)
frame.Position = UDim2.new(0, 12, 0.08, 0)
frame.BackgroundColor3 = Color3.fromRGB(26, 29, 39)
frame.BorderSizePixel = 0
frame.Active = true
frame.ClipsDescendants = true
frame.Parent = gui

local frameCorner = Instance.new("UICorner")
frameCorner.CornerRadius = UDim.new(0, 12)
frameCorner.Parent = frame

-- Rectangular feature-list container. All existing controls are laid out
-- inside this panel; it is created before the controls so they render above it.
local featurePanel = Instance.new("Frame")
featurePanel.Name = "FeatureListPanel"
featurePanel.Position = UDim2.fromOffset(6, 46)
featurePanel.Size = UDim2.fromOffset(288, 570)
featurePanel.BackgroundColor3 = Color3.fromRGB(18, 22, 32)
featurePanel.BackgroundTransparency = 0.06
featurePanel.BorderSizePixel = 0
featurePanel.Active = false
featurePanel.ZIndex = 1
featurePanel.Parent = frame

local featurePanelCorner = Instance.new("UICorner")
featurePanelCorner.CornerRadius = UDim.new(0, 10)
featurePanelCorner.Parent = featurePanel

local featurePanelStroke = Instance.new("UIStroke")
featurePanelStroke.Color = Color3.fromRGB(74, 231, 220)
featurePanelStroke.Thickness = 1.25
featurePanelStroke.Transparency = 0.28
featurePanelStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
featurePanelStroke.Parent = featurePanel

local featurePanelGradient = Instance.new("UIGradient")
featurePanelGradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(22, 28, 42)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(17, 20, 31)),
})
featurePanelGradient.Rotation = 90
featurePanelGradient.Parent = featurePanel

local scale = Instance.new("UIScale")
scale.Parent = frame

local function updateScale()
    local camera = workspace.CurrentCamera
    if not camera then return end
    local viewport = camera.ViewportSize
    -- Fit narrow phones while keeping touch targets reasonably large.
    scale.Scale = math.clamp(math.min(viewport.X / 340, viewport.Y / 650), 0.65, 1.0)
end
updateScale()
if workspace.CurrentCamera then
    workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
end
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(updateScale)

local title = Instance.new("TextButton")
title.Name = "TitleDragHandle"
title.Size = UDim2.new(1, 0, 0, 42)
title.BackgroundColor3 = Color3.fromRGB(55, 67, 102)
title.BorderSizePixel = 0
title.Text = "  Ninja | ESP + Fly"
title.TextXAlignment = Enum.TextXAlignment.Left
title.TextColor3 = Color3.new(1, 1, 1)
title.TextSize = 14
title.Font = Enum.Font.GothamBold
title.AutoButtonColor = false
title.Active = true
title.Parent = frame
local titleCorner = Instance.new("UICorner")
titleCorner.CornerRadius = UDim.new(0, 12)
titleCorner.Parent = title

-- A compact toggle that keeps the title bar visible while the panel is folded.
local expandedFrameSize = frame.Size
local minimized = false
local minimizeButton = Instance.new("TextButton")
minimizeButton.Name = "MinimizeToggle"
minimizeButton.Size = UDim2.fromOffset(34, 30)
minimizeButton.Position = UDim2.new(1, -40, 0, 6)
minimizeButton.BackgroundColor3 = Color3.fromRGB(76, 89, 126)
minimizeButton.BorderSizePixel = 0
minimizeButton.Text = "−"
minimizeButton.TextColor3 = Color3.new(1, 1, 1)
minimizeButton.TextSize = 22
minimizeButton.Font = Enum.Font.GothamBold
minimizeButton.AutoButtonColor = true
minimizeButton.Active = true
minimizeButton.ZIndex = 3
minimizeButton.Parent = frame
local minimizeCorner = Instance.new("UICorner")
minimizeCorner.CornerRadius = UDim.new(0, 7)
minimizeCorner.Parent = minimizeButton

local function toggleMinimized()
    minimized = not minimized
    if minimized then
        frame.Size = UDim2.new(expandedFrameSize.X.Scale, expandedFrameSize.X.Offset, 0, 42)
        minimizeButton.Text = "+"
        title.Text = "  Ninja | ESP + Fly (已缩小)"
    else
        frame.Size = expandedFrameSize
        minimizeButton.Text = "−"
        title.Text = "  Ninja | ESP + Fly"
    end
end

-- InputBegan is used for compatibility with mobile injectors that may not fire Activated.
minimizeButton.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Touch
        or input.UserInputType == Enum.UserInputType.MouseButton1 then
        toggleMinimized()
    end
end)

local function makeButton(text, x, y, w, h)
    local button = Instance.new("TextButton")
    button.Size = UDim2.fromOffset(w, h)
    button.Position = UDim2.fromOffset(x, y)
    button.BackgroundColor3 = Color3.fromRGB(65, 77, 110)
    button.TextColor3 = Color3.new(1, 1, 1)
    button.TextSize = 15
    button.Font = Enum.Font.GothamSemibold
    button.Text = text
    button.AutoButtonColor = true
    button.Active = true
    button.Parent = frame
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = button
    return button
end

local espButton = makeButton("透视：关闭", 12, 52, 132, 38)
local flyButton = makeButton("飞天：关闭", 156, 52, 132, 38)
local upButton = makeButton("按住上升 ▲", 12, 96, 132, 38)
local downButton = makeButton("按住下降 ▼", 156, 96, 132, 38)

local speedDownButton = makeButton("−", 12, 140, 50, 36)
local speedLabel = Instance.new("TextLabel")
speedLabel.Size = UDim2.fromOffset(164, 36)
speedLabel.Position = UDim2.fromOffset(68, 140)
speedLabel.BackgroundColor3 = Color3.fromRGB(42, 46, 60)
speedLabel.TextColor3 = Color3.new(1, 1, 1)
speedLabel.TextSize = 14
speedLabel.Font = Enum.Font.GothamSemibold
speedLabel.Text = "飞行速度：55"
speedLabel.Parent = frame
local speedLabelCorner = Instance.new("UICorner")
speedLabelCorner.CornerRadius = UDim.new(0, 8)
speedLabelCorner.Parent = speedLabel
local speedUpButton = makeButton("+", 230, 140, 58, 36)

local teleportTitle = Instance.new("TextLabel")
teleportTitle.Size = UDim2.new(1, -24, 0, 22)
teleportTitle.Position = UDim2.fromOffset(12, 180)
teleportTitle.BackgroundTransparency = 1
teleportTitle.Text = "坐标传送（X / Y / Z）"
teleportTitle.TextColor3 = Color3.fromRGB(225, 230, 245)
teleportTitle.TextSize = 13
teleportTitle.Font = Enum.Font.GothamSemibold
teleportTitle.TextXAlignment = Enum.TextXAlignment.Left
teleportTitle.Parent = frame

local function makeCoordinateBox(placeholder, x)
    local box = Instance.new("TextBox")
    box.Size = UDim2.fromOffset(88, 38)
    box.Position = UDim2.fromOffset(x, 205)
    box.BackgroundColor3 = Color3.fromRGB(42, 46, 60)
    box.TextColor3 = Color3.new(1, 1, 1)
    box.PlaceholderColor3 = Color3.fromRGB(175, 180, 195)
    box.PlaceholderText = placeholder
    box.Text = ""
    box.ClearTextOnFocus = false
    box.TextSize = 15
    box.Font = Enum.Font.Gotham
    box.TextXAlignment = Enum.TextXAlignment.Center
    -- TextBox 没有 KeyboardType 属性；手机键盘会在 TextBox 获得焦点时由 Roblox 自动弹出。
    box.Parent = frame
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = box
    return box
end

local xBox = makeCoordinateBox("X", 12)
local yBox = makeCoordinateBox("Y", 106)
local zBox = makeCoordinateBox("Z", 200)
local teleportButton = makeButton("传送到坐标", 12, 247, 276, 36)

local currentPositionButton = makeButton("查看当前坐标", 12, 289, 132, 36)
local savePositionButton = makeButton("保存当前位置", 156, 289, 132, 36)

local savedPositionLabel = Instance.new("TextLabel")
savedPositionLabel.Size = UDim2.new(1, -24, 0, 38)
savedPositionLabel.Position = UDim2.fromOffset(12, 329)
savedPositionLabel.BackgroundColor3 = Color3.fromRGB(42, 46, 60)
savedPositionLabel.TextColor3 = Color3.fromRGB(225, 230, 245)
savedPositionLabel.TextSize = 12
savedPositionLabel.TextWrapped = true
savedPositionLabel.Font = Enum.Font.Gotham
savedPositionLabel.Text = "已保存：0 个坐标\n先点击“保存当前位置”"
savedPositionLabel.Parent = frame
local savedPositionCorner = Instance.new("UICorner")
savedPositionCorner.CornerRadius = UDim.new(0, 8)
savedPositionCorner.Parent = savedPositionLabel

local previousSavedButton = makeButton("◀ 上一个", 12, 369, 84, 34)
local nextSavedButton = makeButton("下一个 ▶", 102, 369, 84, 34)
local deleteSavedButton = makeButton("删除选中", 192, 369, 96, 34)
local teleportSavedButton = makeButton("传送到选中坐标", 12, 407, 276, 36)

local npcESPButton = makeButton("NPC绘制：关闭", 12, 449, 132, 36)
local npcTrackButton = makeButton("NPC镜头追踪：关闭", 156, 449, 132, 36)
local noclipButton = makeButton("穿墙：关闭", 12, 491, 276, 36)

local status = Instance.new("TextLabel")
status.Size = UDim2.new(1, -24, 0, 42)
status.Position = UDim2.fromOffset(12, 533)
status.BackgroundTransparency = 1
status.Text = "摇杆控制方向；NPC追踪为镜头辅助"
status.TextColor3 = Color3.fromRGB(210, 215, 230)
status.TextSize = 12
status.TextWrapped = true
status.Font = Enum.Font.Gotham
status.Parent = frame

local closeButton = makeButton("关闭脚本", 12, 580, 276, 32)
closeButton.BackgroundColor3 = Color3.fromRGB(125, 58, 65)

-- Make the panel draggable with a finger or mouse.
do
    local dragging = false
    local dragInput
    local dragStart
    local startPosition

    title.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch
            or input.UserInputType == Enum.UserInputType.MouseButton1 then
            -- Do not start moving the window when the minimize toggle is pressed.
            local insideMinimize = input.Position.X >= minimizeButton.AbsolutePosition.X
                and input.Position.X <= minimizeButton.AbsolutePosition.X + minimizeButton.AbsoluteSize.X
                and input.Position.Y >= minimizeButton.AbsolutePosition.Y
                and input.Position.Y <= minimizeButton.AbsolutePosition.Y + minimizeButton.AbsoluteSize.Y
            if insideMinimize then return end

            dragging = true
            dragStart = input.Position
            startPosition = frame.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)

    title.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch
            or input.UserInputType == Enum.UserInputType.MouseMovement then
            dragInput = input
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if dragging and input == dragInput then
            local delta = input.Position - dragStart
            frame.Position = UDim2.new(
                startPosition.X.Scale,
                startPosition.X.Offset + delta.X,
                startPosition.Y.Scale,
                startPosition.Y.Offset + delta.Y
            )
        end
    end)
end

local espEnabled = false
local npcESPEnabled = false
local npcTrackingEnabled = false
local noclipEnabled = false
local noclipOriginalCanCollide = {}
local noclipConnection = nil
local flying = false
local closed = false
local vertical = 0
local espObjects = {}
local npcESPObjects = {}
local npcModels = {}
local playerConnections = {}
local npcRegistryConnection, npcTrackingConnection = nil, nil
local flyVelocity, flyGyro, flyConnection
local playerAddedConnection, playerRemovingConnection, respawnConnection
local verticalInput
local savedPositions = {}
local selectedPositionIndex = 0
local SAVE_FILE = "NinjaESPFlyMobile_savedcoords.txt"

local function getLocalRoot()
    local character = LocalPlayer.Character
    return character and character:FindFirstChild("HumanoidRootPart")
end

local function formatPosition(position)
    return string.format("X %.2f | Y %.2f | Z %.2f", position.X, position.Y, position.Z)
end

local function fillCoordinateBoxes(position)
    xBox.Text = string.format("%.2f", position.X)
    yBox.Text = string.format("%.2f", position.Y)
    zBox.Text = string.format("%.2f", position.Z)
end

local function isValidCoordinate(value)
    return value ~= nil and value == value and math.abs(value) < 1000000
end

local function persistPositions()
    if type(writefile) ~= "function" then
        return false
    end
    local lines = {}
    for _, position in ipairs(savedPositions) do
        lines[#lines + 1] = string.format("%.6f,%.6f,%.6f", position.X, position.Y, position.Z)
    end
    local ok = pcall(function()
        writefile(SAVE_FILE, table.concat(lines, "\n"))
    end)
    return ok
end

local function refreshSavedPositionUI()
    local count = #savedPositions
    if count == 0 then
        selectedPositionIndex = 0
        savedPositionLabel.Text = "已保存：0 个坐标\n先点击“保存当前位置”"
        previousSavedButton.Text = "◀ 上一个"
        nextSavedButton.Text = "下一个 ▶"
        return
    end

    selectedPositionIndex = math.clamp(selectedPositionIndex, 1, count)
    local position = savedPositions[selectedPositionIndex]
    savedPositionLabel.Text = string.format(
        "坐标 %d/%d  |  X %.2f  Y %.2f  Z %.2f",
        selectedPositionIndex, count, position.X, position.Y, position.Z
    )
end

local function loadSavedPositions()
    if type(isfile) ~= "function" or type(readfile) ~= "function" then
        refreshSavedPositionUI()
        return
    end

    local ok, payload = pcall(function()
        if isfile(SAVE_FILE) then
            return readfile(SAVE_FILE)
        end
        return nil
    end)
    if not ok or type(payload) ~= "string" then
        refreshSavedPositionUI()
        return
    end

    -- Each line is X,Y,Z. A previous single-coordinate file is also compatible.
    for line in payload:gmatch("[^\r\n]+") do
        local sx, sy, sz = line:match("^%s*([^,]+),([^,]+),([^,]+)%s*$")
        local x, y, z = tonumber(sx), tonumber(sy), tonumber(sz)
        if isValidCoordinate(x) and isValidCoordinate(y) and isValidCoordinate(z) then
            savedPositions[#savedPositions + 1] = Vector3.new(x, y, z)
            if #savedPositions >= 100 then break end
        end
    end

    selectedPositionIndex = #savedPositions > 0 and #savedPositions or 0
    refreshSavedPositionUI()
end

local function refreshSpeedLabel()
    speedLabel.Text = "飞行速度：" .. tostring(flySpeed)
end

-- Use InputBegan for touch and mouse rather than relying only on Activated;
-- this is more reliable in some injected mobile UI environments.
local function bindButton(button, callback)
    button.Active = true
    button.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch
            or input.UserInputType == Enum.UserInputType.MouseButton1 then
            callback()
        end
    end)
end

bindButton(speedDownButton, function()
    flySpeed = math.clamp(flySpeed - 5, 10, 150)
    refreshSpeedLabel()
end)

bindButton(speedUpButton, function()
    flySpeed = math.clamp(flySpeed + 5, 10, 150)
    refreshSpeedLabel()
end)

bindButton(currentPositionButton, function()
    local root = getLocalRoot()
    if not root then
        status.Text = "角色尚未准备好，无法读取当前坐标"
        return
    end
    local position = root.Position
    fillCoordinateBoxes(position)
    status.Text = "当前位置：" .. formatPosition(position)
end)

bindButton(savePositionButton, function()
    local root = getLocalRoot()
    if not root then
        status.Text = "角色尚未准备好，无法保存坐标"
        return
    end
    if #savedPositions >= 100 then
        status.Text = "最多保存 100 个坐标，请先删除不需要的条目"
        return
    end

    local position = root.Position
    savedPositions[#savedPositions + 1] = position
    selectedPositionIndex = #savedPositions
    fillCoordinateBoxes(position)
    refreshSavedPositionUI()
    local persisted = persistPositions()
    if persisted then
        status.Text = string.format("已保存第 %d 个坐标，共 %d 个（已写入文件）", selectedPositionIndex, #savedPositions)
    else
        status.Text = string.format("已保存第 %d 个坐标，共 %d 个（本次运行有效）", selectedPositionIndex, #savedPositions)
    end
end)

bindButton(previousSavedButton, function()
    local count = #savedPositions
    if count == 0 then
        status.Text = "还没有保存坐标"
        return
    end
    selectedPositionIndex = ((selectedPositionIndex - 2) % count) + 1
    refreshSavedPositionUI()
    fillCoordinateBoxes(savedPositions[selectedPositionIndex])
    status.Text = string.format("已选中坐标 %d/%d", selectedPositionIndex, count)
end)

bindButton(nextSavedButton, function()
    local count = #savedPositions
    if count == 0 then
        status.Text = "还没有保存坐标"
        return
    end
    selectedPositionIndex = (selectedPositionIndex % count) + 1
    refreshSavedPositionUI()
    fillCoordinateBoxes(savedPositions[selectedPositionIndex])
    status.Text = string.format("已选中坐标 %d/%d", selectedPositionIndex, count)
end)

bindButton(deleteSavedButton, function()
    local count = #savedPositions
    if count == 0 or selectedPositionIndex < 1 then
        status.Text = "没有可删除的坐标"
        return
    end
    table.remove(savedPositions, selectedPositionIndex)
    if #savedPositions == 0 then
        selectedPositionIndex = 0
    else
        selectedPositionIndex = math.min(selectedPositionIndex, #savedPositions)
    end
    refreshSavedPositionUI()
    local persisted = persistPositions()
    status.Text = persisted and "已删除选中坐标并更新文件" or "已删除选中坐标（本次运行有效）"
end)

bindButton(teleportSavedButton, function()
    local position = savedPositions[selectedPositionIndex]
    if not position then
        status.Text = "还没有保存坐标，请先点击“保存当前位置”"
        return
    end
    local root = getLocalRoot()
    local humanoid = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
    if not root or not humanoid or humanoid.Health <= 0 then
        status.Text = "角色尚未准备好，暂时无法传送"
        return
    end
    root.CFrame = CFrame.new(position)
    root.AssemblyLinearVelocity = Vector3.zero
    root.AssemblyAngularVelocity = Vector3.zero
    if flyVelocity then flyVelocity.Velocity = Vector3.zero end
    vertical = 0
    fillCoordinateBoxes(position)
    status.Text = string.format("已请求传送至坐标 %d/%d：%s", selectedPositionIndex, #savedPositions, formatPosition(position))
end)

bindButton(teleportButton, function()
    local x = tonumber(xBox.Text)
    local y = tonumber(yBox.Text)
    local z = tonumber(zBox.Text)

    if not (isValidCoordinate(x) and isValidCoordinate(y) and isValidCoordinate(z)) then
        status.Text = "坐标无效：请分别输入有效的 X、Y、Z 数值"
        return
    end

    local character = LocalPlayer.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not root or not humanoid or humanoid.Health <= 0 then
        status.Text = "角色尚未准备好，暂时无法传送"
        return
    end

    root.CFrame = CFrame.new(x, y, z)
    root.AssemblyLinearVelocity = Vector3.zero
    root.AssemblyAngularVelocity = Vector3.zero
    if flyVelocity then flyVelocity.Velocity = Vector3.zero end
    vertical = 0
    status.Text = string.format("已请求传送至 X %.1f / Y %.1f / Z %.1f", x, y, z)
end)

local function clearESP(player)
    local objects = espObjects[player]
    if not objects then return end
    for _, object in ipairs(objects) do
        pcall(function() object:Destroy() end)
    end
    espObjects[player] = nil
end

local function applyESP(player)
    if not espEnabled or player == LocalPlayer then return end
    local character = player.Character
    if not character then return end
    local head = character:FindFirstChild("Head")
    if not head then return end

    clearESP(player)
    local highlight = Instance.new("Highlight")
    highlight.Name = "NinjaPlayerHighlight"
    highlight.Adornee = character
    highlight.FillColor = Color3.fromRGB(255, 65, 65)
    highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
    highlight.FillTransparency = 0.55
    highlight.OutlineTransparency = 0
    highlight.Parent = character

    local billboard = Instance.new("BillboardGui")
    billboard.Name = "NinjaPlayerName"
    billboard.Adornee = head
    billboard.Size = UDim2.fromOffset(170, 30)
    billboard.StudsOffset = Vector3.new(0, 2.5, 0)
    billboard.AlwaysOnTop = true
    billboard.Parent = character

    local label = Instance.new("TextLabel")
    label.Size = UDim2.fromScale(1, 1)
    label.BackgroundTransparency = 1
    label.Text = player.DisplayName
    label.TextColor3 = Color3.fromRGB(255, 110, 110)
    label.TextStrokeTransparency = 0.2
    label.TextScaled = true
    label.Font = Enum.Font.GothamBold
    label.Parent = billboard
    espObjects[player] = {highlight, billboard}
end

local function clearNPCESP(model)
    local objects = npcESPObjects[model]
    if not objects then return end
    for _, object in ipairs(objects) do
        pcall(function() object:Destroy() end)
    end
    npcESPObjects[model] = nil
end

local function getNPCPart(model)
    if not model then return nil end
    local head = model:FindFirstChild("Head")
    if head and head:IsA("BasePart") then return head end
    local root = model:FindFirstChild("HumanoidRootPart")
    if root and root:IsA("BasePart") then return root end
    local primary = model.PrimaryPart
    if primary and primary:IsA("BasePart") then return primary end
    return nil
end

local function isNPCModel(model)
    if not model or not model:IsA("Model") then return false end
    if not model:IsDescendantOf(workspace) then return false end
    if Players:GetPlayerFromCharacter(model) then return false end
    local humanoid = model:FindFirstChildOfClass("Humanoid")
    return humanoid ~= nil and humanoid.Health > 0 and getNPCPart(model) ~= nil
end

local function applyNPCESP(model)
    if not npcESPEnabled or not isNPCModel(model) then
        clearNPCESP(model)
        return
    end

    local current = npcESPObjects[model]
    if current and current[1] and current[1].Parent then return end
    clearNPCESP(model)

    local targetPart = getNPCPart(model)
    if not targetPart then return end

    local highlight = Instance.new("Highlight")
    highlight.Name = "NinjaNPCSeeingHighlight"
    highlight.Adornee = model
    highlight.FillColor = Color3.fromRGB(255, 175, 55)
    highlight.OutlineColor = Color3.fromRGB(255, 245, 190)
    highlight.FillTransparency = 0.58
    highlight.OutlineTransparency = 0
    highlight.Parent = model

    local billboard = Instance.new("BillboardGui")
    billboard.Name = "NinjaNPCLabel"
    billboard.Adornee = targetPart
    billboard.Size = UDim2.fromOffset(150, 26)
    billboard.StudsOffset = Vector3.new(0, 2.2, 0)
    billboard.AlwaysOnTop = true
    billboard.Parent = model

    local label = Instance.new("TextLabel")
    label.Size = UDim2.fromScale(1, 1)
    label.BackgroundTransparency = 1
    label.Text = "NPC · " .. model.Name
    label.TextColor3 = Color3.fromRGB(255, 195, 95)
    label.TextStrokeTransparency = 0.2
    label.TextScaled = true
    label.Font = Enum.Font.GothamBold
    label.Parent = billboard

    npcESPObjects[model] = {highlight, billboard}
end

local function registerNPCFromHumanoid(instance)
    if not instance or not instance:IsA("Humanoid") then return end
    local model = instance.Parent
    if not model or not model:IsA("Model") then return end
    if Players:GetPlayerFromCharacter(model) then return end
    npcModels[model] = true
    if npcESPEnabled then applyNPCESP(model) end
end

local function scanNPCs()
    for _, instance in ipairs(workspace:GetDescendants()) do
        if instance:IsA("Humanoid") then
            registerNPCFromHumanoid(instance)
        end
    end
end

local function refreshNPCESP()
    if not npcESPEnabled then
        for model in pairs(npcESPObjects) do clearNPCESP(model) end
        return
    end
    for model in pairs(npcModels) do
        if isNPCModel(model) then
            applyNPCESP(model)
        else
            clearNPCESP(model)
            if not model.Parent or not model:IsDescendantOf(workspace) then
                npcModels[model] = nil
            end
        end
    end
end

-- Returns true when the camera has an unobstructed ray to the NPC part.
-- Parts belonging to the local character and camera are excluded from the ray.
local function hasLineOfSight(targetModel, targetPart, camera)
    if not targetModel or not targetPart or not camera then return false end
    local origin = camera.CFrame.Position
    local direction = targetPart.Position - origin
    if direction.Magnitude <= 0.001 then return true end

    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Exclude
    rayParams.FilterDescendantsInstances = {LocalPlayer.Character, camera}
    rayParams.IgnoreWater = true

    local result = workspace:Raycast(origin, direction, rayParams)
    -- No hit means the ray is clear. A hit on the target itself also counts as visible.
    return result == nil or result.Instance:IsDescendantOf(targetModel)
end

local function getBestNPCTarget()
    local camera = workspace.CurrentCamera
    if not camera then return nil, false end
    local viewport = camera.ViewportSize
    local center = Vector2.new(viewport.X * 0.5, viewport.Y * 0.5)
    local bestPart, bestScore = nil, math.huge
    local bestOccludedScore = math.huge

    for model in pairs(npcModels) do
        if isNPCModel(model) then
            local part = getNPCPart(model)
            if part then
                local screenPoint, onScreen = camera:WorldToViewportPoint(part.Position)
                if onScreen and screenPoint.Z > 0 then
                    local delta = Vector2.new(screenPoint.X, screenPoint.Y) - center
                    local score = delta.Magnitude
                    if hasLineOfSight(model, part, camera) then
                        if score < bestScore then
                            bestScore = score
                            bestPart = part
                        end
                    elseif score < bestOccludedScore then
                        bestOccludedScore = score
                    end
                end
            end
        elseif not model.Parent or not model:IsDescendantOf(workspace) then
            npcModels[model] = nil
            clearNPCESP(model)
        end
    end

    -- The second return value distinguishes a blocked on-screen NPC from no target.
    return bestPart, bestPart == nil and bestOccludedScore < math.huge
end

local function refreshESP()
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            if espEnabled then applyESP(player) else clearESP(player) end
        end
    end
end

local function restoreNoclip()
    noclipEnabled = false
    if noclipConnection then
        noclipConnection:Disconnect()
        noclipConnection = nil
    end
    for part, originalValue in pairs(noclipOriginalCanCollide) do
        if part and part.Parent then
            pcall(function()
                part.CanCollide = originalValue
            end)
        end
    end
    noclipOriginalCanCollide = {}
end

local function applyNoclipToCharacter()
    local character = LocalPlayer.Character
    if not character then return end
    for _, instance in ipairs(character:GetDescendants()) do
        if instance:IsA("BasePart") then
            if noclipOriginalCanCollide[instance] == nil then
                noclipOriginalCanCollide[instance] = instance.CanCollide
            end
            instance.CanCollide = false
        end
    end
end

local function refreshButtons()
    espButton.Text = espEnabled and "透视：开启" or "透视：关闭"
    flyButton.Text = flying and "飞天：开启" or "飞天：关闭"
    npcESPButton.Text = npcESPEnabled and "NPC绘制：开启" or "NPC绘制：关闭"
    npcTrackButton.Text = npcTrackingEnabled and "NPC镜头追踪：开启" or "NPC镜头追踪：关闭"
    noclipButton.Text = noclipEnabled and "穿墙：开启" or "穿墙：关闭"
end

local function stopFly()
    flying = false
    vertical = 0
    verticalInput = nil
    if flyConnection then flyConnection:Disconnect(); flyConnection = nil end
    if flyVelocity then pcall(function() flyVelocity:Destroy() end); flyVelocity = nil end
    if flyGyro then pcall(function() flyGyro:Destroy() end); flyGyro = nil end
end

local function startFly()
    local character = LocalPlayer.Character
    if not character then status.Text = "角色尚未加载"; return end
    local root = character:FindFirstChild("HumanoidRootPart")
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not root or not humanoid or humanoid.Health <= 0 then
        status.Text = "角色尚未准备好"
        return
    end

    stopFly()
    flying = true
    flyVelocity = Instance.new("BodyVelocity")
    flyVelocity.MaxForce = Vector3.new(1e9, 1e9, 1e9)
    flyVelocity.P = 1e4
    flyVelocity.Velocity = Vector3.zero
    flyVelocity.Parent = root

    flyGyro = Instance.new("BodyGyro")
    flyGyro.MaxTorque = Vector3.new(1e9, 1e9, 1e9)
    flyGyro.P = 1e5
    flyGyro.CFrame = root.CFrame
    flyGyro.Parent = root

    flyConnection = RunService.RenderStepped:Connect(function()
        if not flying or not root.Parent or humanoid.Health <= 0 then
            stopFly()
            refreshButtons()
            return
        end
        -- MoveDirection follows the Roblox mobile thumbstick as well as keyboard input.
        local move = humanoid.MoveDirection
        flyVelocity.Velocity = Vector3.new(move.X, 0, move.Z) * flySpeed
            + Vector3.new(0, vertical * flySpeed, 0)
        local camera = workspace.CurrentCamera
        if camera then
            local look = camera.CFrame.LookVector
            local flatLook = Vector3.new(look.X, 0, look.Z)
            if flatLook.Magnitude > 0.001 then
                flyGyro.CFrame = CFrame.lookAt(root.Position, root.Position + flatLook.Unit)
            end
        end
    end)
    status.Text = "已开启：摇杆移动，按住升降按钮"
end

bindButton(espButton, function()
    espEnabled = not espEnabled
    refreshESP()
    refreshButtons()
end)

bindButton(flyButton, function()
    if flying then stopFly() else startFly() end
    refreshButtons()
end)

bindButton(npcESPButton, function()
    npcESPEnabled = not npcESPEnabled
    if npcESPEnabled then scanNPCs() end
    refreshNPCESP()
    status.Text = npcESPEnabled and "NPC绘制已开启（橙色标记）" or "NPC绘制已关闭"
    refreshButtons()
end)

bindButton(npcTrackButton, function()
    npcTrackingEnabled = not npcTrackingEnabled
    if npcTrackingEnabled then
        scanNPCs()
        status.Text = "NPC镜头追踪已开启；实际子弹行为由游戏决定"
    else
        status.Text = "NPC镜头追踪已关闭"
    end
    refreshButtons()
end)

bindButton(noclipButton, function()
    if noclipEnabled then
        restoreNoclip()
        status.Text = "穿墙已关闭，已恢复角色部件原碰撞状态"
    else
        noclipEnabled = true
        applyNoclipToCharacter()
        if noclipConnection then noclipConnection:Disconnect() end
        -- Reapply every frame so newly added character parts are covered too.
        noclipConnection = RunService.Stepped:Connect(function()
            if noclipEnabled and not closed then
                applyNoclipToCharacter()
            end
        end)
        status.Text = "穿墙已开启；效果受游戏服务器校验影响"
    end
    refreshButtons()
end)

npcRegistryConnection = workspace.DescendantAdded:Connect(function(instance)
    if instance:IsA("Humanoid") then
        task.defer(registerNPCFromHumanoid, instance)
    end
end)

npcTrackingConnection = RunService.RenderStepped:Connect(function(deltaTime)
    if not npcTrackingEnabled or closed then return end
    local camera = workspace.CurrentCamera
    if not camera then return end

    local targetPart, coverBlocked = getBestNPCTarget()
    if not targetPart or not targetPart.Parent then
        local message = coverBlocked
            and "掩体判断：NPC 被墙体/障碍物遮挡，已跳过追踪"
            or "掩体判断：当前没有视野内的可见 NPC"
        if status.Text ~= message then status.Text = message end
        return
    end

    if status.Text ~= "掩体判断：目标无遮挡，镜头辅助中" then
        status.Text = "掩体判断：目标无遮挡，镜头辅助中"
    end

    -- Only adjust the camera when a direct ray to the target is clear.
    -- This does not change server-side hit detection or projectile behavior.
    local desired = CFrame.lookAt(camera.CFrame.Position, targetPart.Position)
    local blend = math.clamp(deltaTime * 7, 0, 0.22)
    camera.CFrame = camera.CFrame:Lerp(desired, blend)
end)

local function bindVertical(button, value)
    button.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch
            or input.UserInputType == Enum.UserInputType.MouseButton1 then
            vertical = value
            verticalInput = input
        end
    end)
end
bindVertical(upButton, 1)
bindVertical(downButton, -1)
UserInputService.InputEnded:Connect(function(input)
    if input == verticalInput then
        vertical = 0
        verticalInput = nil
    end
end)

local function bindPlayer(player)
    if player == LocalPlayer or playerConnections[player] then return end
    playerConnections[player] = player.CharacterAdded:Connect(function()
        task.wait(0.5)
        if espEnabled and not closed then applyESP(player) end
    end)
end
for _, player in ipairs(Players:GetPlayers()) do bindPlayer(player) end

playerAddedConnection = Players.PlayerAdded:Connect(bindPlayer)
playerRemovingConnection = Players.PlayerRemoving:Connect(function(player)
    clearESP(player)
    if playerConnections[player] then
        playerConnections[player]:Disconnect()
        playerConnections[player] = nil
    end
end)

respawnConnection = LocalPlayer.CharacterAdded:Connect(function()
    if flying and not closed then
        task.wait(0.8)
        if not closed and LocalPlayer.Character then
            stopFly()
            startFly()
            refreshButtons()
        end
    end
end)

bindButton(closeButton, function()
    closed = true
    espEnabled = false
    npcESPEnabled = false
    npcTrackingEnabled = false
    restoreNoclip()
    stopFly()
    refreshESP()
    refreshNPCESP()
    if npcRegistryConnection then npcRegistryConnection:Disconnect() end
    if npcTrackingConnection then npcTrackingConnection:Disconnect() end
    if playerAddedConnection then playerAddedConnection:Disconnect() end
    if playerRemovingConnection then playerRemovingConnection:Disconnect() end
    if respawnConnection then respawnConnection:Disconnect() end
    for _, connection in pairs(playerConnections) do connection:Disconnect() end
    gui:Destroy()
end)

loadSavedPositions()
refreshButtons()
refreshSpeedLabel()
