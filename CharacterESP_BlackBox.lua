-- Character ESP: character coloring + Highlight + black 2D box
-- Local visual effect only. Intended for use in a Roblox client environment
-- where LocalPlayer and PlayerGui are available.

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

local CHARACTER_COLOR = Color3.fromRGB(255, 0, 0) -- body and glow color
local BOX_COLOR = Color3.fromRGB(0, 0, 0)         -- black box color
local REFRESH_TIME = 1
local BOX_THICKNESS = 2
local FILL_TRANSPARENCY = 0.2

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
-- Check target model
-- =========================

local function IsTarget(model)
    if not model or not model:IsA("Model") then
        return false
    end

    -- Never draw a box around the local character.
    if model == LocalPlayer.Character then
        return false
    end

    local humanoid = model:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.Health <= 0 then
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

    for _, object in ipairs(model:GetDescendants()) do
        if object:IsA("BasePart") and object.Name ~= "HumanoidRootPart" then
            object.Color = CHARACTER_COLOR
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

    Boxes[model] = frame
end

-- =========================
-- Update projected box position
-- =========================

local function UpdateBox(model, frame)
    if not IsTarget(model) then
        frame.Visible = false
        return
    end

    Camera = Workspace.CurrentCamera
    if not Camera then
        frame.Visible = false
        return
    end

    local success, boundingCFrame, boundingSize = pcall(function()
        return model:GetBoundingBox()
    end)

    if not success then
        frame.Visible = false
        return
    end

    local halfSize = boundingSize / 2
    local corners = {
        Vector3.new(-halfSize.X, -halfSize.Y, -halfSize.Z),
        Vector3.new(-halfSize.X, -halfSize.Y,  halfSize.Z),
        Vector3.new(-halfSize.X,  halfSize.Y, -halfSize.Z),
        Vector3.new(-halfSize.X,  halfSize.Y,  halfSize.Z),
        Vector3.new( halfSize.X, -halfSize.Y, -halfSize.Z),
        Vector3.new( halfSize.X, -halfSize.Y,  halfSize.Z),
        Vector3.new( halfSize.X,  halfSize.Y, -halfSize.Z),
        Vector3.new( halfSize.X,  halfSize.Y,  halfSize.Z),
    }

    local minX, minY = math.huge, math.huge
    local maxX, maxY = -math.huge, -math.huge

    for _, corner in ipairs(corners) do
        local worldPosition = (boundingCFrame * CFrame.new(corner)).Position
        local screenPosition = Camera:WorldToViewportPoint(worldPosition)

        -- Hide the box if any corner is behind the camera.
        if screenPosition.Z <= 0 then
            frame.Visible = false
            return
        end

        minX = math.min(minX, screenPosition.X)
        minY = math.min(minY, screenPosition.Y)
        maxX = math.max(maxX, screenPosition.X)
        maxY = math.max(maxY, screenPosition.Y)
    end

    local viewport = Camera.ViewportSize
    minX = math.clamp(minX, 0, viewport.X)
    minY = math.clamp(minY, 0, viewport.Y)
    maxX = math.clamp(maxX, 0, viewport.X)
    maxY = math.clamp(maxY, 0, viewport.Y)

    if maxX <= minX or maxY <= minY then
        frame.Visible = false
        return
    end

    frame.Position = UDim2.fromOffset(minX, minY)
    frame.Size = UDim2.fromOffset(maxX - minX, maxY - minY)

    -- Reapply black so the box remains black.
    local stroke = frame:FindFirstChildOfClass("UIStroke")
    if stroke then
        stroke.Color = BOX_COLOR
        stroke.Thickness = BOX_THICKNESS
        stroke.Transparency = 0
    end

    frame.Visible = true
end

-- =========================
-- Scan Workspace for characters / NPCs
-- =========================

local function ScanAll()
    for _, object in ipairs(Workspace:GetDescendants()) do
        if object:IsA("Model") and IsTarget(object) then
            PaintCharacter(object)
            CreateBox(object)
        end
    end
end

-- Initial scan
ScanAll()

-- Periodic scan finds newly spawned characters and NPCs.
task.spawn(function()
    while GUI and GUI.Parent do
        task.wait(REFRESH_TIME)
        ScanAll()
    end
end)

-- Update boxes every rendered frame.
RunService.RenderStepped:Connect(function()
    Camera = Workspace.CurrentCamera

    for model, frame in pairs(Boxes) do
        if model and model.Parent and frame and frame.Parent then
            UpdateBox(model, frame)
        else
            if frame then
                frame:Destroy()
            end
            Boxes[model] = nil
        end
    end
end)

print("[CharacterESP] Character coloring, Highlight, and black boxes enabled.")
