-- Character ESP: character coloring + Highlight + black 2D box
-- 修复：只识别具有标准角色骨架的模型；方框仅根据身体部件投影，忽略工具/配件/地图零件。

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
    warn("[CharacterESP] LocalPlayer is unavailable. Run this from the client.")
    return
end

-- =========================
-- Settings
-- =========================

local CHARACTER_COLOR = Color3.fromRGB(255, 0, 0)
local BOX_COLOR = Color3.fromRGB(0, 0, 0)
local REFRESH_TIME = 1
local BOX_THICKNESS = 2
local FILL_TRANSPARENCY = 0.2
local MAX_BODY_PART_DISTANCE = 8 -- 忽略离身体中心过远的异常部件
local SHOW_OFFSCREEN_WARNING = true
local WARNING_RING_RADIUS = 145 -- 预警图标距离屏幕中心的半径（像素）
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
-- Create / recreate ScreenGui
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
-- Get valid body parts only
-- =========================

local function GetBodyParts(model)
    local parts = {}
    if not model then
        return parts
    end

    for _, object in ipairs(model:GetDescendants()) do
        if object:IsA("BasePart") and BODY_PART_NAMES[object.Name] then
            table.insert(parts, object)
        end
    end
    return parts
end

-- =========================
-- Check target model
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

    -- 要求标准根部件、头部和躯干，避免把带 Humanoid 的地图模型当成人物。
    local root = model:FindFirstChild("HumanoidRootPart")
    local head = model:FindFirstChild("Head")
    local torso = model:FindFirstChild("UpperTorso") or model:FindFirstChild("Torso") or model:FindFirstChild("LowerTorso")

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
    if #parts < 5 then
        return false
    end

    return true
end

-- =========================
-- Apply body color and Highlight
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
-- Create black 2D box
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

    -- 屏幕外方向箭头：固定分布在屏幕中心周围，并显示目标距离。
    local warningHolder = Instance.new("Frame")
    warningHolder.Name = "ESP_Warning"
    warningHolder.AnchorPoint = Vector2.new(0.5, 0.5)
    warningHolder.Size = UDim2.fromOffset(76, 48)
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
    distanceLabel.Size = UDim2.fromOffset(76, 18)
    distanceLabel.Font = Enum.Font.GothamBold
    distanceLabel.Text = ""
    distanceLabel.TextSize = 11
    distanceLabel.TextColor3 = WARNING_TEXT_COLOR
    distanceLabel.TextStrokeTransparency = 0.5
    distanceLabel.Parent = warningHolder

    local distanceCorner = Instance.new("UICorner")
    distanceCorner.CornerRadius = UDim.new(0, 5)
    distanceCorner.Parent = distanceLabel

    Boxes[model] = {
        Frame = frame,
        Parts = GetBodyParts(model),
        Warning = warningHolder,
        Arrow = arrow,
        Distance = distanceLabel,
    }
end

-- =========================
-- Update off-screen direction warning
-- =========================

local function IsEnemyForWarning(model)
    local targetPlayer = Players:GetPlayerFromCharacter(model)
    if targetPlayer and LocalPlayer.Team and targetPlayer.Team then
        return targetPlayer.Team ~= LocalPlayer.Team
    end
    -- NPC 或没有 Team 信息的角色按可疑目标处理。
    return true
end

local function UpdateOffscreenWarning(model, record)
    local holder = record and record.Warning
    local arrow = record and record.Arrow
    local distanceLabel = record and record.Distance

    if not holder or not arrow or not distanceLabel then
        return
    end

    if not SHOW_OFFSCREEN_WARNING or not IsTarget(model) or not IsEnemyForWarning(model) then
        holder.Visible = false
        return
    end

    Camera = Workspace.CurrentCamera
    local root = model:FindFirstChild("HumanoidRootPart")
    if not Camera or not root or not root:IsA("BasePart") then
        holder.Visible = false
        return
    end

    local projected, onScreen = Camera:WorldToViewportPoint(root.Position)
    local viewport = Camera.ViewportSize
    local isOffscreen = projected.Z <= 0
        or not onScreen
        or projected.X < 0 or projected.X > viewport.X
        or projected.Y < 0 or projected.Y > viewport.Y

    if not isOffscreen then
        holder.Visible = false
        return
    end

    -- 使用摄像机本地坐标计算方向；目标在摄像机后方时反转方向，
    -- 使箭头仍指向目标所在的屏幕方向，而不是指向错误一侧。
    local localPosition = Camera.CFrame:PointToObjectSpace(root.Position)
    local dx = localPosition.X
    local dy = -localPosition.Y

    if localPosition.Z > 0 then
        dx = -dx
        dy = -dy
    end

    local magnitude = math.sqrt(dx * dx + dy * dy)
    if magnitude < 0.001 then
        -- 目标正好位于摄像机正后方时，默认从屏幕下方提示。
        dx, dy = 0, 1
        magnitude = 1
    end

    dx = dx / magnitude
    dy = dy / magnitude

    local center = viewport / 2
    local radius = math.min(WARNING_RING_RADIUS, math.min(viewport.X, viewport.Y) * 0.32)
    local screenX = center.X + dx * radius
    local screenY = center.Y + dy * radius

    holder.Position = UDim2.fromOffset(screenX, screenY)
    arrow.Rotation = math.deg(math.atan2(dy, dx))

    local distance = (root.Position - Camera.CFrame.Position).Magnitude
    distanceLabel.Text = string.format("%.0f studs", distance)
    holder.Visible = true
end

-- =========================
-- Update projected box position
-- =========================

local function UpdateBox(model, record)
    local frame = record and record.Frame
    if not frame then
        return
    end

    if not IsTarget(model) then
        frame.Visible = false
        if record.Warning then
            record.Warning.Visible = false
        end
        return
    end

    Camera = Workspace.CurrentCamera
    if not Camera then
        frame.Visible = false
        return
    end

    local root = model:FindFirstChild("HumanoidRootPart")
    if not root or not root:IsA("BasePart") then
        frame.Visible = false
        return
    end

    -- 根部件在摄像机后方时，不绘制漂浮方框。
    local rootScreen, rootOnScreen = Camera:WorldToViewportPoint(root.Position)
    if rootScreen.Z <= 0 then
        frame.Visible = false
        return
    end

    local minX, minY = math.huge, math.huge
    local maxX, maxY = -math.huge, -math.huge
    local projectedCount = 0
    local validParts = 0

    -- 只投影身体骨骼部件，不使用 Model:GetBoundingBox()，避免工具和配件拉大方框。
    for _, part in ipairs(record.Parts) do
        if part and part.Parent and part:IsA("BasePart")
            and (part.Position - root.Position).Magnitude <= MAX_BODY_PART_DISTANCE then
            validParts += 1
            local half = part.Size / 2

            for x = -1, 1, 2 do
                for y = -1, 1, 2 do
                    for z = -1, 1, 2 do
                        local worldPosition = part.CFrame:PointToWorldSpace(Vector3.new(
                            half.X * x,
                            half.Y * y,
                            half.Z * z
                        ))
                        local screenPosition = Camera:WorldToViewportPoint(worldPosition)

                        -- 忽略摄像机后方的角点，避免单个角点导致整个人物方框消失。
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
        frame.Visible = false
        return
    end

    local viewport = Camera.ViewportSize
    minX = math.clamp(minX, 0, viewport.X)
    minY = math.clamp(minY, 0, viewport.Y)
    maxX = math.clamp(maxX, 0, viewport.X)
    maxY = math.clamp(maxY, 0, viewport.Y)

    if maxX - minX < 2 or maxY - minY < 2 then
        frame.Visible = false
        return
    end

    frame.Position = UDim2.fromOffset(minX, minY)
    frame.Size = UDim2.fromOffset(maxX - minX, maxY - minY)

    local stroke = frame:FindFirstChildOfClass("UIStroke")
    if stroke then
        stroke.Color = BOX_COLOR
        stroke.Thickness = BOX_THICKNESS
        stroke.Transparency = 0
    end

    frame.Visible = true
end

-- =========================
-- Scan Workspace for valid characters / NPCs
-- =========================

local function ScanAll()
    for _, object in ipairs(Workspace:GetDescendants()) do
        if object:IsA("Model") and IsTarget(object) then
            PaintCharacter(object)

            if not Boxes[object] then
                CreateBox(object)
            else
                -- 角色部件重载后更新缓存，避免继续使用旧部件列表。
                Boxes[object].Parts = GetBodyParts(object)
            end
        end
    end
end

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
            Boxes[model] = nil
        end
    end
end)

print("[CharacterESP] Character filtering, black boxes, and off-screen direction warnings enabled.")
