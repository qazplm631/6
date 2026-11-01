-- Roblox server relay with two selectable general scripts.
-- Target PlaceId: automatically runs the Saint Ori script.
-- Other PlaceIds: prompts the user to choose General 1 or General 2.

local TARGET_PLACE_ID = 104841616983113

local TARGET_SCRIPT_URL =
    "https://raw.githubusercontent.com/qazplm631/6/main/vvv.lua"

-- 通用一：原通用脚本
local GENERAL_ONE_URL =
    "https://raw.githubusercontent.com/qazplm631/6/main/roblox%E9%80%9A%E7%94%A8.lua"

-- 通用二：CharacterESP_BlackBox.lua
local GENERAL_TWO_URL =
    "https://raw.githubusercontent.com/qazplm631/6/main/CharacterESP_BlackBox.lua"

local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local StarterGui = game:GetService("StarterGui")

local function notify(title, message)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = title,
            Text = message,
            Duration = 5
        })
    end)
end

local function executeRemote(url)
    assert(type(loadstring) == "function", "当前执行器不支持 loadstring")

    local source = game:HttpGet(url)
    assert(type(source) == "string" and #source > 0, "远程脚本为空")

    local chunk, compileError = loadstring(source)
    assert(chunk, compileError or "远程脚本编译失败")

    return chunk()
end

local function loadSelectedScript(url, label, gui, statusLabel, button)
    if gui:GetAttribute("Loading") then
        return
    end

    gui:SetAttribute("Loading", true)
    button:SetAttribute("Loading", true)
    button.Text = "正在加载 " .. label .. "..."
    statusLabel.Text = "正在加载，请稍候"

    task.spawn(function()
        local ok, err = pcall(function()
            executeRemote(url)
        end)

        if ok then
            if gui and gui.Parent then
                gui:Destroy()
            end
        else
            warn("[Server Relay] " .. tostring(err))
            statusLabel.Text = "加载失败：" .. tostring(err)
            gui:SetAttribute("Loading", false)
            button:SetAttribute("Loading", false)
            button.Text = label .. "（重试）"
        end
    end)
end

local function createChoiceWindow()
    local player = Players.LocalPlayer or Players.PlayerAdded:Wait()
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "ServerRelayChoice"
    screenGui.ResetOnSpawn = false
    screenGui.IgnoreGuiInset = true
    screenGui.DisplayOrder = 99999
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

    local parented = pcall(function()
        screenGui.Parent = CoreGui
    end)

    if not parented or not screenGui.Parent then
        local playerGui = player:WaitForChild("PlayerGui", 10)
        if not playerGui then
            warn("[Server Relay] 找不到 PlayerGui，无法显示选择窗口")
            return
        end
        screenGui.Parent = playerGui
    end

    -- 清理重复运行时留下的旧窗口。
    local oldGui = screenGui.Parent:FindFirstChild("ServerRelayChoice")
    if oldGui and oldGui ~= screenGui then
        oldGui:Destroy()
    end

    local frame = Instance.new("Frame")
    frame.Name = "Main"
    frame.AnchorPoint = Vector2.new(0.5, 0.5)
    frame.Position = UDim2.fromScale(0.5, 0.5)
    frame.Size = UDim2.fromOffset(310, 224)
    frame.BackgroundColor3 = Color3.fromRGB(20, 24, 34)
    frame.BorderSizePixel = 0
    frame.Parent = screenGui

    local frameCorner = Instance.new("UICorner")
    frameCorner.CornerRadius = UDim.new(0, 14)
    frameCorner.Parent = frame

    local frameStroke = Instance.new("UIStroke")
    frameStroke.Color = Color3.fromRGB(235, 165, 65)
    frameStroke.Thickness = 1.5
    frameStroke.Parent = frame

    local title = Instance.new("TextLabel")
    title.BackgroundTransparency = 1
    title.Position = UDim2.fromOffset(16, 12)
    title.Size = UDim2.new(1, -32, 0, 28)
    title.Font = Enum.Font.GothamBold
    title.Text = "服务器检测"
    title.TextColor3 = Color3.fromRGB(240, 245, 255)
    title.TextSize = 19
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = frame

    local description = Instance.new("TextLabel")
    description.BackgroundTransparency = 1
    description.Position = UDim2.fromOffset(16, 43)
    description.Size = UDim2.new(1, -32, 0, 38)
    description.Font = Enum.Font.Gotham
    description.Text = "当前服务器不是圣奥里\n请选择要执行的通用脚本"
    description.TextColor3 = Color3.fromRGB(190, 201, 218)
    description.TextSize = 13
    description.TextWrapped = true
    description.TextXAlignment = Enum.TextXAlignment.Left
    description.Parent = frame

    local function makeButton(name, text, y, color)
        local button = Instance.new("TextButton")
        button.Name = name
        button.Position = UDim2.fromOffset(16, y)
        button.Size = UDim2.new(1, -32, 0, 42)
        button.BackgroundColor3 = color
        button.BorderSizePixel = 0
        button.AutoButtonColor = true
        button.Font = Enum.Font.GothamBold
        button.Text = text
        button.TextColor3 = Color3.fromRGB(255, 255, 255)
        button.TextSize = 15
        button.Parent = frame

        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 9)
        corner.Parent = button
        return button
    end

    local generalOneButton = makeButton(
        "GeneralOne",
        "通用一",
        92,
        Color3.fromRGB(55, 112, 190)
    )

    local generalTwoButton = makeButton(
        "GeneralTwo",
        "通用二",
        142,
        Color3.fromRGB(115, 82, 180)
    )

    local statusLabel = Instance.new("TextLabel")
    statusLabel.BackgroundTransparency = 1
    statusLabel.Position = UDim2.fromOffset(16, 190)
    statusLabel.Size = UDim2.new(1, -32, 0, 22)
    statusLabel.Font = Enum.Font.Gotham
    statusLabel.Text = "请选择一个脚本"
    statusLabel.TextColor3 = Color3.fromRGB(170, 185, 205)
    statusLabel.TextSize = 11
    statusLabel.TextXAlignment = Enum.TextXAlignment.Left
    statusLabel.TextTruncate = Enum.TextTruncate.AtEnd
    statusLabel.Parent = frame

    generalOneButton.Activated:Connect(function()
        loadSelectedScript(
            GENERAL_ONE_URL,
            "通用一",
            screenGui,
            statusLabel,
            generalOneButton
        )
    end)

    generalTwoButton.Activated:Connect(function()
        loadSelectedScript(
            GENERAL_TWO_URL,
            "通用二",
            screenGui,
            statusLabel,
            generalTwoButton
        )
    end)
end

if game.PlaceId == TARGET_PLACE_ID then
    notify("服务器检测", "当前服务器为圣奥里，正在加载专用脚本")

    local ok, err = pcall(function()
        executeRemote(TARGET_SCRIPT_URL)
    end)

    if not ok then
        warn("[Server Relay] " .. tostring(err))
        notify("脚本加载失败", tostring(err))
    end
else
    notify("服务器检测", "当前服务器不是圣奥里，请选择通用脚本")
    createChoiceWindow()
end
