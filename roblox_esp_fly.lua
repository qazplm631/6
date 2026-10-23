-- Roblox ESP + Fly UI (mobile-friendly)
-- 仅建议在自建或获准测试的体验中使用。

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then return end

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

local parented = pcall(function()
    gui.Parent = game:GetService("CoreGui")
end)
if not parented or not gui.Parent then
    gui.Parent = LocalPlayer:WaitForChild("PlayerGui")
end

local frame = Instance.new("Frame")
frame.Name = "Main"
frame.Size = UDim2.fromOffset(270, 280)
frame.Position = UDim2.new(0, 12, 0.22, 0)
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
    scale.Scale = math.clamp(math.min(viewport.X / 330, viewport.Y / 620), 0.72, 1.05)
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

local espButton = makeButton("透视：关闭", 12, 52, 246, 40)
local flyButton = makeButton("飞天：关闭", 12, 100, 246, 40)
local upButton = makeButton("按住上升 ▲", 12, 148, 118, 40)
local downButton = makeButton("按住下降 ▼", 140, 148, 118, 40)

local status = Instance.new("TextLabel")
status.Size = UDim2.new(1, -24, 0, 32)
status.Position = UDim2.fromOffset(12, 193)
status.BackgroundTransparency = 1
status.Text = "飞行方向：使用游戏左侧摇杆"
status.TextColor3 = Color3.fromRGB(210, 215, 230)
status.TextSize = 12
status.TextWrapped = true
status.Font = Enum.Font.Gotham
status.Parent = frame

local closeButton = makeButton("关闭脚本", 12, 235, 246, 34)
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
local flying = false
local closed = false
local vertical = 0
local flySpeed = 55
local espObjects = {}
local playerConnections = {}
local flyVelocity, flyGyro, flyConnection
local playerAddedConnection, playerRemovingConnection, respawnConnection
local verticalInput

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

espButton.Activated:Connect(function()
    espEnabled = not espEnabled
    refreshESP()
    refreshButtons()
end)

flyButton.Activated:Connect(function()
    if flying then stopFly() else startFly() end
    refreshButtons()
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

closeButton.Activated:Connect(function()
    closed = true
    espEnabled = false
    stopFly()
    refreshESP()
    if playerAddedConnection then playerAddedConnection:Disconnect() end
    if playerRemovingConnection then playerRemovingConnection:Disconnect() end
    if respawnConnection then respawnConnection:Disconnect() end
    for _, connection in pairs(playerConnections) do connection:Disconnect() end
    gui:Destroy()
end)

refreshButtons()
