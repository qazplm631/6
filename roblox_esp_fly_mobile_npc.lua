-- Roblox ESP + Fly UI (mobile-friendly)
-- 仅建议在自建或获准测试的体验中使用。

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
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

local frame = Instance.new("Frame")
frame.Name = "Main"
frame.Size = UDim2.fromOffset(300, 640)
frame.Position = UDim2.new(0, 12, 0.08, 0)
frame.BackgroundColor3 = Color3.fromRGB(26, 29, 39)
frame.BorderSizePixel = 0
frame.Active = true
frame.Parent = gui

local frameCorner = Instance.new("UICorner")
frameCorner.CornerRadius = UDim.new(0, 12)
frameCorner.Parent = frame

local scale = Instance.new("UIScale")
scale.Parent = frame

local function updateScale()
    local camera = workspace.CurrentCamera
    if not camera then return end
    local viewport = camera.ViewportSize
    -- Fit narrow phones while keeping touch targets reasonably large.
    scale.Scale = math.clamp(math.min(viewport.X / 340, viewport.Y / 700), 0.65, 1.0)
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
title.Text = "Ninja | 透视 + 飞天  ·  拖这里移动"
title.TextColor3 = Color3.new(1, 1, 1)
title.TextSize = 14
title.Font = Enum.Font.GothamBold
title.AutoButtonColor = false
title.Active = true
title.Parent = frame
local titleCorner = Instance.new("UICorner")
titleCorner.CornerRadius = UDim.new(0, 12)
titleCorner.Parent = title

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

local espButton = makeButton("透视：关闭", 12, 52, 276, 38)
local flyButton = makeButton("飞天：关闭", 12, 96, 276, 38)
local upButton = makeButton("按住上升 ▲", 12, 140, 132, 38)
local downButton = makeButton("按住下降 ▼", 156, 140, 132, 38)

local speedDownButton = makeButton("−", 12, 185, 50, 36)
local speedLabel = Instance.new("TextLabel")
speedLabel.Size = UDim2.fromOffset(164, 36)
speedLabel.Position = UDim2.fromOffset(68, 185)
speedLabel.BackgroundColor3 = Color3.fromRGB(42, 46, 60)
speedLabel.TextColor3 = Color3.new(1, 1, 1)
speedLabel.TextSize = 14
speedLabel.Font = Enum.Font.GothamSemibold
speedLabel.Text = "飞行速度：55"
speedLabel.Parent = frame
local speedLabelCorner = Instance.new("UICorner")
speedLabelCorner.CornerRadius = UDim.new(0, 8)
speedLabelCorner.Parent = speedLabel
local speedUpButton = makeButton("+", 230, 185, 58, 36)

local teleportTitle = Instance.new("TextLabel")
teleportTitle.Size = UDim2.new(1, -24, 0, 22)
teleportTitle.Position = UDim2.fromOffset(12, 225)
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
    box.Position = UDim2.fromOffset(x, 250)
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
local teleportButton = makeButton("传送到坐标", 12, 296, 276, 36)

local currentPositionButton = makeButton("查看当前坐标", 12, 338, 132, 36)
local savePositionButton = makeButton("保存当前位置", 156, 338, 132, 36)

local savedPositionLabel = Instance.new("TextLabel")
savedPositionLabel.Size = UDim2.new(1, -24, 0, 38)
savedPositionLabel.Position = UDim2.fromOffset(12, 378)
savedPositionLabel.BackgroundColor3 = Color3.fromRGB(42, 46, 60)
savedPositionLabel.TextColor3 = Color3.fromRGB(225, 230, 245)
savedPositionLabel.TextSize = 12
savedPositionLabel.TextWrapped = true
savedPositionLabel.Font = Enum.Font.Gotham
savedPositionLabel.Text = "已保存坐标：无"
savedPositionLabel.Parent = frame
local savedPositionCorner = Instance.new("UICorner")
savedPositionCorner.CornerRadius = UDim.new(0, 8)
savedPositionCorner.Parent = savedPositionLabel

local teleportSavedButton = makeButton("传送到保存坐标", 12, 420, 276, 36)

local npcESPButton = makeButton("NPC绘制：关闭", 12, 460, 276, 36)
local npcTrackButton = makeButton("NPC子弹追踪：关闭", 12, 502, 276, 36)

local status = Instance.new("TextLabel")
status.Size = UDim2.new(1, -24, 0, 42)
status.Position = UDim2.fromOffset(12, 544)
status.BackgroundTransparency = 1
status.Text = "摇杆控制方向；NPC追踪为镜头辅助"
status.TextColor3 = Color3.fromRGB(210, 215, 230)
status.TextSize = 12
status.TextWrapped = true
status.Font = Enum.Font.Gotham
status.Parent = frame

local closeButton = makeButton("关闭脚本", 12, 594, 276, 32)
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
local savedPosition = nil
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

local function persistPosition(position)
    if type(writefile) ~= "function" then
        return false
    end
    local payload = string.format("%.6f,%.6f,%.6f", position.X, position.Y, position.Z)
    local ok = pcall(function()
        writefile(SAVE_FILE, payload)
    end)
    return ok
end

local function loadSavedPosition()
    if type(isfile) ~= "function" or type(readfile) ~= "function" then
        return
    end
    local ok, payload = pcall(function()
        if isfile(SAVE_FILE) then
            return readfile(SAVE_FILE)
        end
        return nil
    end)
    if not ok or type(payload) ~= "string" then
        return
    end

    local sx, sy, sz = payload:match("^%s*([^,]+),([^,]+),([^,]+)%s*$")
    local x, y, z = tonumber(sx), tonumber(sy), tonumber(sz)
    local function valid(v)
        return v ~= nil and v == v and math.abs(v) < 1000000
    end
    if valid(x) and valid(y) and valid(z) then
        savedPosition = Vector3.new(x, y, z)
        savedPositionLabel.Text = "已保存坐标：" .. formatPosition(savedPosition)
    end
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
    savedPosition = root.Position
    fillCoordinateBoxes(savedPosition)
    savedPositionLabel.Text = "已保存坐标：" .. formatPosition(savedPosition)
    local persisted = persistPosition(savedPosition)
    if persisted then
        status.Text = "坐标已保存，并写入执行器文件"
    else
        status.Text = "坐标已保存（本次运行有效；执行器可能不支持文件保存）"
    end
end)

bindButton(teleportSavedButton, function()
    if not savedPosition then
        status.Text = "还没有保存坐标，请先点击“保存当前位置”"
        return
    end
    local root = getLocalRoot()
    local humanoid = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
    if not root or not humanoid or humanoid.Health <= 0 then
        status.Text = "角色尚未准备好，暂时无法传送"
        return
    end
    root.CFrame = CFrame.new(savedPosition)
    root.AssemblyLinearVelocity = Vector3.zero
    root.AssemblyAngularVelocity = Vector3.zero
    if flyVelocity then flyVelocity.Velocity = Vector3.zero end
    vertical = 0
    fillCoordinateBoxes(savedPosition)
    status.Text = "已请求传送至保存坐标：" .. formatPosition(savedPosition)
end)

bindButton(teleportButton, function()
    local x = tonumber(xBox.Text)
    local y = tonumber(yBox.Text)
    local z = tonumber(zBox.Text)

    local function validCoordinate(value)
        return value ~= nil and value == value and math.abs(value) < 1000000
    end

    if not (validCoordinate(x) and validCoordinate(y) and validCoordinate(z)) then
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

local function getBestNPCTarget()
    local camera = workspace.CurrentCamera
    if not camera then return nil end
    local viewport = camera.ViewportSize
    local center = Vector2.new(viewport.X * 0.5, viewport.Y * 0.5)
    local bestPart, bestScore = nil, math.huge

    for model in pairs(npcModels) do
        if isNPCModel(model) then
            local part = getNPCPart(model)
            if part then
                local screenPoint, onScreen = camera:WorldToViewportPoint(part.Position)
                if onScreen and screenPoint.Z > 0 then
                    local delta = Vector2.new(screenPoint.X, screenPoint.Y) - center
                    local score = delta.Magnitude
                    if score < bestScore then
                        bestScore = score
                        bestPart = part
                    end
                end
            end
        elseif not model.Parent or not model:IsDescendantOf(workspace) then
            npcModels[model] = nil
            clearNPCESP(model)
        end
    end
    return bestPart
end

local function refreshESP()
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            if espEnabled then applyESP(player) else clearESP(player) end
        end
    end
end

local function refreshButtons()
    espButton.Text = espEnabled and "透视：开启" or "透视：关闭"
    flyButton.Text = flying and "飞天：开启" or "飞天：关闭"
    npcESPButton.Text = npcESPEnabled and "NPC绘制：开启" or "NPC绘制：关闭"
    npcTrackButton.Text = npcTrackingEnabled and "NPC子弹追踪：开启" or "NPC子弹追踪：关闭"
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

npcRegistryConnection = workspace.DescendantAdded:Connect(function(instance)
    if instance:IsA("Humanoid") then
        task.defer(registerNPCFromHumanoid, instance)
    end
end)

npcTrackingConnection = RunService.RenderStepped:Connect(function(deltaTime)
    if not npcTrackingEnabled or closed then return end
    local camera = workspace.CurrentCamera
    local targetPart = getBestNPCTarget()
    if not camera or not targetPart or not targetPart.Parent then return end

    -- Camera-based aim assistance: it can help games whose firing direction
    -- follows the camera, but it does not rewrite server-side projectile logic.
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

loadSavedPosition()
refreshButtons()
refreshSpeedLabel()
