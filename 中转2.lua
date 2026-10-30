-- Roblox server relay loader with a mobile-friendly floating status window
-- Matching PlaceId: executes vvv.lua
-- Non-matching PlaceId: executes roblox通用.lua

local TARGET_PLACE_ID = 104841616983113

local TARGET_SCRIPT_URL =
    "https://raw.githubusercontent.com/qazplm631/6/main/vvv.lua"

local FALLBACK_SCRIPT_URL =
    "https://raw.githubusercontent.com/qazplm631/6/main/roblox%E9%80%9A%E7%94%A8.lua"

local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")

local function notify(title, message)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = title,
            Text = message,
            Duration = 5
        })
    end)
end

local function createStatusWindow(isTargetServer)
    local player = Players.LocalPlayer
    if not player then
        return
    end

    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "ServerRelayStatus"
    screenGui.ResetOnSpawn = false
    screenGui.DisplayOrder = 9999
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

    local parented = pcall(function()
        screenGui.Parent = CoreGui
    end)

    if not parented or not screenGui.Parent then
        local playerGui = player:WaitForChild("PlayerGui", 10)
        if not playerGui then
            screenGui:Destroy()
            return
        end
        screenGui.Parent = playerGui
    end

    -- Remove an older copy, if this loader was run more than once.
    for _, child in ipairs(screenGui.Parent:GetChildren()) do
        if child ~= screenGui and child.Name == "ServerRelayStatus" then
            child:Destroy()
        end
    end

    local frame = Instance.new("Frame")
    frame.Name = "StatusPanel"
    frame.Size = UDim2.fromOffset(270, isTargetServer and 98 or 76)
    frame.Position = UDim2.new(0.5, -135, 0, 24)
    frame.BackgroundColor3 = Color3.fromRGB(20, 24, 34)
    frame.BackgroundTransparency = 0.08
    frame.BorderSizePixel = 0
    frame.Active = true
    frame.Parent = screenGui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 12)
    corner.Parent = frame

    local stroke = Instance.new("UIStroke")
    stroke.Thickness = 1.5
    stroke.Color = isTargetServer
        and Color3.fromRGB(45, 220, 150)
        or Color3.fromRGB(235, 165, 65)
    stroke.Transparency = 0.1
    stroke.Parent = frame

    local title = Instance.new("TextLabel")
    title.Name = "Title"
    title.Position = UDim2.fromOffset(12, 7)
    title.Size = UDim2.new(1, -48, 0, 20)
    title.BackgroundTransparency = 1
    title.Font = Enum.Font.GothamBold
    title.Text = "SERVER CHECK"
    title.TextColor3 = Color3.fromRGB(220, 230, 245)
    title.TextSize = 12
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = frame

    local status = Instance.new("TextLabel")
    status.Name = "Status"
    status.Position = UDim2.fromOffset(12, 29)
    status.Size = UDim2.new(1, -24, 0, 24)
    status.BackgroundTransparency = 1
    status.Font = Enum.Font.GothamSemibold
    status.Text = isTargetServer
        and "当前服务器：圣奥里"
        or "当前服务器：不是圣奥里"
    status.TextColor3 = isTargetServer
        and Color3.fromRGB(70, 235, 165)
        or Color3.fromRGB(255, 190, 95)
    status.TextSize = 15
    status.TextXAlignment = Enum.TextXAlignment.Left
    status.Parent = frame

    if isTargetServer then
        local detail = Instance.new("TextLabel")
        detail.Name = "AutoSkipNotice"
        detail.Position = UDim2.fromOffset(12, 55)
        detail.Size = UDim2.new(1, -24, 0, 32)
        detail.BackgroundTransparency = 1
        detail.Font = Enum.Font.Gotham
        detail.Text = "已自动执行圣奥里脚本，将自动跳过黑客小游戏"
        detail.TextColor3 = Color3.fromRGB(190, 205, 225)
        detail.TextSize = 11
        detail.TextWrapped = true
        detail.TextXAlignment = Enum.TextXAlignment.Left
        detail.TextYAlignment = Enum.TextYAlignment.Center
        detail.Parent = frame
    end

    local closeButton = Instance.new("TextButton")
    closeButton.Name = "Close"
    closeButton.Position = UDim2.new(1, -31, 0, 7)
    closeButton.Size = UDim2.fromOffset(24, 24)
    closeButton.BackgroundColor3 = Color3.fromRGB(55, 62, 78)
    closeButton.BorderSizePixel = 0
    closeButton.Font = Enum.Font.GothamBold
    closeButton.Text = "×"
    closeButton.TextColor3 = Color3.fromRGB(240, 245, 255)
    closeButton.TextSize = 18
    closeButton.Parent = frame

    local closeCorner = Instance.new("UICorner")
    closeCorner.CornerRadius = UDim.new(0, 7)
    closeCorner.Parent = closeButton

    local destroyed = false
    local inputChangedConnection
    local inputEndedConnection

    local function closePopup()
        if destroyed then
            return
        end
        destroyed = true

        if inputChangedConnection then
            inputChangedConnection:Disconnect()
        end
        if inputEndedConnection then
            inputEndedConnection:Disconnect()
        end

        if screenGui and screenGui.Parent then
            screenGui:Destroy()
        end
    end

    closeButton.Activated:Connect(closePopup)

    -- Drag with either mouse or touch while the 5-second popup is visible.
    local dragging = false
    local dragInput
    local dragStart
    local startPosition

    frame.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPosition = frame.Position
            dragInput = input
        end
    end)

    frame.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end)

    inputChangedConnection = UserInputService.InputChanged:Connect(function(input)
        if not destroyed and dragging and (input == dragInput
            or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            frame.Position = UDim2.new(
                startPosition.X.Scale,
                startPosition.X.Offset + delta.X,
                startPosition.Y.Scale,
                startPosition.Y.Offset + delta.Y
            )
        end
    end)

    inputEndedConnection = UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)

    -- Automatically dismiss the status popup after five seconds.
    task.delay(5, closePopup)
end

local isTargetServer = (game.PlaceId == TARGET_PLACE_ID)
local selectedUrl

if isTargetServer then
    selectedUrl = TARGET_SCRIPT_URL
    notify("服务器检测", "当前服务器为圣奥里，正在加载专用脚本")
else
    selectedUrl = FALLBACK_SCRIPT_URL
    notify("服务器检测", "未匹配圣奥里，正在加载通用脚本")
end

createStatusWindow(isTargetServer)

local function executeRemote(url)
    assert(type(loadstring) == "function", "Executor does not support loadstring")

    local source = game:HttpGet(url)
    assert(type(source) == "string" and #source > 0, "Remote script is empty")

    local chunk, compileError = loadstring(source)
    assert(chunk, compileError or "Remote script compilation failed")

    return chunk()
end

local success, err = pcall(function()
    executeRemote(selectedUrl)
end)

if not success then
    warn("[Server Relay] " .. tostring(err))
    notify("脚本加载失败", tostring(err))
end
