if not getgenv().CursedsakenLoaded then getgenv().CursedsakenLoaded = true else
    local old = game:GetService("CoreGui"):FindFirstChild("CursedsakenHub")
        or game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui"):FindFirstChild("CursedsakenHub")
    if old then old:Destroy() end
end

local PathfindingService = game:GetService("PathfindingService")
local Players           = game:GetService("Players")
local Teams             = game:GetService("Teams")
local UserInputService  = game:GetService("UserInputService")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")

local localPlayer = Players.LocalPlayer
local character   = localPlayer.Character or localPlayer.CharacterAdded:Wait()
local humanoid    = character:WaitForChild("Humanoid")
local rootPart    = character:WaitForChild("HumanoidRootPart")

local CONTROLS = {
    Enable_AI_Play            = false,
    Avoidance_Distance        = 70,
    Disable_Charge_Generators = false,
    Disable_Auto_Reset        = true,
    Draw_Paths                = false,
}

local FORSAKEN_KILLERS = {
    ["Slasher"]   = true,
    ["Jason"]     = true,
    ["John Doe"]  = true,
    ["Noli"]      = true,
    ["1x1x1x1"]  = true,
    ["c00lkidd"]  = true,
    ["Guest 666"] = true,
    ["Slenderman"]= true,
    ["Sixer"]     = true,
}

-- PATHFINDING STATE VARIABLES
local isComputingPath    = false
local activeTargetPosition = nil

-- ========================================================
-- 1. BASE SYSTEM PANEL CONVERGER
-- ========================================================
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name             = "CursedsakenHub"
ScreenGui.ResetOnSpawn     = false
ScreenGui.ZIndexBehavior   = Enum.ZIndexBehavior.Global
if gethui then ScreenGui.Parent = gethui() end
if not ScreenGui.Parent then pcall(function() ScreenGui.Parent = game:GetService("CoreGui") end) end
if not ScreenGui.Parent then ScreenGui.Parent = localPlayer:WaitForChild("PlayerGui") end

local MainFrame = Instance.new("Frame")
MainFrame.Size              = UDim2.new(0, 310, 0, 260)
MainFrame.Position          = UDim2.new(0.35, 0, 0.25, 0)
MainFrame.BackgroundColor3  = Color3.fromRGB(24, 23, 34)
MainFrame.BorderSizePixel   = 0
MainFrame.Active            = true
MainFrame.Draggable         = true
MainFrame.Parent            = ScreenGui

local UICorner_Main = Instance.new("UICorner")
UICorner_Main.CornerRadius = UDim.new(0, 8)
UICorner_Main.Parent       = MainFrame

local Header = Instance.new("Frame")
Header.Size             = UDim2.new(1, 0, 0, 35)
Header.BackgroundColor3 = Color3.fromRGB(30, 29, 43)
Header.BorderSizePixel  = 0
Header.Parent           = MainFrame

local UICorner_Header = Instance.new("UICorner")
UICorner_Header.CornerRadius = UDim.new(0, 8)
UICorner_Header.Parent       = Header

local Title = Instance.new("TextLabel")
Title.Size               = UDim2.new(1, -15, 1, 0)
Title.Position           = UDim2.new(0, 12, 0, 0)
Title.Text               = "Cursedsaken — AI Play"
Title.TextColor3         = Color3.fromRGB(245, 245, 255)
Title.Font               = Enum.Font.SourceSansBold
Title.TextSize           = 15
Title.TextXAlignment     = Enum.TextXAlignment.Left
Title.BackgroundTransparency = 1
Title.Parent             = Header

local ContentList = Instance.new("Frame")
ContentList.Name                 = "ContentList"
ContentList.Size                 = UDim2.new(1, -20, 1, -50)
ContentList.Position             = UDim2.new(0, 10, 0, 45)
ContentList.BackgroundTransparency = 1
ContentList.Parent               = MainFrame

local function createToggle(label, sub, index, key, def)
    local Row = Instance.new("Frame")
    Row.Size            = UDim2.new(1, 0, 0, 38)
    Row.Position        = UDim2.new(0, 0, 0, (index - 1) * 44)
    Row.BackgroundColor3 = Color3.fromRGB(34, 33, 49)
    Row.BorderSizePixel = 0
    Row.ZIndex          = 5
    Row.Parent          = ContentList

    local UICorner_Row = Instance.new("UICorner")
    UICorner_Row.CornerRadius = UDim.new(0, 6)
    UICorner_Row.Parent       = Row

    local L = Instance.new("TextLabel")
    L.Size               = UDim2.new(0.75, 0, 0, 18)
    L.Position           = UDim2.new(0, 10, 0, 2)
    L.Text               = label
    L.TextColor3         = Color3.fromRGB(255, 255, 255)
    L.Font               = Enum.Font.SourceSansBold
    L.TextSize           = 13
    L.TextXAlignment     = Enum.TextXAlignment.Left
    L.BackgroundTransparency = 1
    L.ZIndex             = 6
    L.Parent             = Row

    local S = Instance.new("TextLabel")
    S.Size               = UDim2.new(0.75, 0, 0, 14)
    S.Position           = UDim2.new(0, 10, 0, 18)
    S.Text               = sub
    S.TextColor3         = Color3.fromRGB(150, 148, 170)
    S.Font               = Enum.Font.SourceSans
    S.TextSize           = 11
    S.TextXAlignment     = Enum.TextXAlignment.Left
    S.BackgroundTransparency = 1
    S.ZIndex             = 6
    S.Parent             = Row

    local Btn = Instance.new("TextButton")
    Btn.Size             = UDim2.new(0, 38, 0, 18)
    Btn.Position         = UDim2.new(1, -48, 0, 10)
    Btn.BackgroundColor3 = def and Color3.fromRGB(80, 75, 145) or Color3.fromRGB(50, 48, 68)
    Btn.Text             = ""
    Btn.AutoButtonColor  = false
    Btn.ZIndex           = 7
    Btn.Parent           = Row

    local UICorner_Sw = Instance.new("UICorner")
    UICorner_Sw.CornerRadius = UDim.new(1, 0)
    UICorner_Sw.Parent       = Btn

    local Ball = Instance.new("Frame")
    local ballCorner = Instance.new("UICorner")
    ballCorner.CornerRadius = UDim.new(1, 0)
    ballCorner.Parent       = Ball
    Ball.Size               = UDim2.new(0, 14, 0, 14)
    Ball.Position           = def and UDim2.new(1, -16, 0, 2) or UDim2.new(0, 2, 0, 2)
    Ball.BackgroundColor3   = Color3.fromRGB(255, 255, 255)
    Ball.BorderSizePixel    = 0
    Ball.ZIndex             = 8
    Ball.Parent             = Btn

    Btn.MouseButton1Click:Connect(function()
        CONTROLS[key] = not CONTROLS[key]
        local tPos = CONTROLS[key] and UDim2.new(1, -16, 0, 2) or UDim2.new(0, 2, 0, 2)
        local tCol = CONTROLS[key] and Color3.fromRGB(80, 75, 145) or Color3.fromRGB(50, 48, 68)
        TweenService:Create(Ball, TweenInfo.new(0.1), {Position = tPos}):Play()
        TweenService:Create(Btn,  TweenInfo.new(0.1), {BackgroundColor3 = tCol}):Play()
        if not CONTROLS.Enable_AI_Play and humanoid then
            humanoid:Move(Vector3.new(0, 0, 0))
            activeTargetPosition = nil
        end
    end)
end

createToggle("Enable AI Play",              "Stupid AI with pathfinding and killer avoidance", 1, "Enable_AI_Play",            false)

-- Killer Avoidance Distance slider (Row 2)
local Row2 = Instance.new("Frame")
Row2.Size            = UDim2.new(1, 0, 0, 38)
Row2.Position        = UDim2.new(0, 0, 0, 44)
Row2.BackgroundColor3 = Color3.fromRGB(34, 33, 49)
Row2.BorderSizePixel = 0
Row2.ZIndex          = 5
Row2.Parent          = ContentList

local UICorner_R2 = Instance.new("UICorner")
UICorner_R2.CornerRadius = UDim.new(0, 6)
UICorner_R2.Parent       = Row2

local L2 = Instance.new("TextLabel")
L2.Size               = UDim2.new(0.5, 0, 1, 0)
L2.Position           = UDim2.new(0, 10, 0, 0)
L2.Text               = "Killer Avoidance Distance"
L2.TextColor3         = Color3.fromRGB(255, 255, 255)
L2.Font               = Enum.Font.SourceSansBold
L2.TextSize           = 13
L2.TextXAlignment     = Enum.TextXAlignment.Left
L2.BackgroundTransparency = 1
L2.ZIndex             = 6
L2.Parent             = Row2

local Disp2 = Instance.new("TextLabel")
Disp2.Size               = UDim2.new(0, 30, 1, 0)
Disp2.Position           = UDim2.new(0, 150, 0, 0)
Disp2.Text               = "70"
Disp2.TextColor3         = Color3.fromRGB(240, 240, 255)
Disp2.Font               = Enum.Font.SourceSansBold
Disp2.TextSize           = 12
Disp2.BackgroundTransparency = 1
Disp2.ZIndex             = 6
Disp2.Parent             = Row2

local Track2 = Instance.new("TextButton")
Track2.Size             = UDim2.new(0, 95, 0, 4)
Track2.Position         = UDim2.new(1, -110, 0, 17)
Track2.BackgroundColor3 = Color3.fromRGB(55, 53, 75)
Track2.Text             = ""
Track2.AutoButtonColor  = false
Track2.ZIndex           = 7
Track2.Parent           = Row2

local Fill2 = Instance.new("Frame")
Fill2.Size            = UDim2.new(0.42, 0, 1, 0)
Fill2.BackgroundColor3 = Color3.fromRGB(100, 95, 185)
Fill2.BorderSizePixel = 0
Fill2.ZIndex          = 8
Fill2.Parent          = Track2

local SldBall2 = Instance.new("Frame")
SldBall2.Size            = UDim2.new(0, 10, 0, 10)
SldBall2.Position        = UDim2.new(0.42, -5, 0, -3)
SldBall2.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
SldBall2.BorderSizePixel = 0
SldBall2.ZIndex          = 9
SldBall2.Parent          = Track2

local UICorner_Sb2 = Instance.new("UICorner")
UICorner_Sb2.CornerRadius = UDim.new(1, 0)
UICorner_Sb2.Parent       = SldBall2

local drag2 = false

local function updateSlider2(input)
    local posX = math.clamp(
        (input.Position.X - Track2.AbsolutePosition.X) / Track2.AbsoluteSize.X,
        0, 1
    )
    Fill2.Size        = UDim2.new(posX, 0, 1, 0)
    SldBall2.Position = UDim2.new(posX, -5, 0, -3)
    local fVal = math.floor(10 + (posX * 140))
    Disp2.Text                 = tostring(fVal)
    CONTROLS.Avoidance_Distance = fVal
end

Track2.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        drag2 = true
        updateSlider2(input)
    end
end)
UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        drag2 = false
    end
end)
UserInputService.InputChanged:Connect(function(input)
    if drag2 and input.UserInputType == Enum.UserInputType.MouseMovement then
        updateSlider2(input)
    end
end)

createToggle("Disable Charge Generators",   "Stops the AI from holding generator prompts",    3, "Disable_Charge_Generators", false)
createToggle("Disable Auto Reset If Killer", "Prevents bot from resetting character matches",  4, "Disable_Auto_Reset",        true)
createToggle("Draw Paths",                   "Enable to draw AI paths",                        5, "Draw_Paths",                false)

-- ========================================================
-- 2. AUTOMATION ENVIRONMENT DETECTION (Only target active items)
-- ========================================================
local function getClosestGenerator()
    if CONTROLS.Disable_Charge_Generators then return nil end
    local closestGen, shortestDistance = nil, math.huge

    for _, object in ipairs(workspace:GetDescendants()) do
        if object:IsA("BasePart") then
            local name = string.lower(object.Name)
            if string.find(name, "generator")
            or string.find(name, "engine")
            or string.find(name, "genpart") then

                -- CHECK FOR STATE INDICES: Ignores fully repaired objects
                local parentModel = object:FindFirstAncestorOfClass("Model")
                local isFixed     = false

                if parentModel then
                    -- Checks standard status values typical to Forsaken frameworks
                    local statusValue = parentModel:FindFirstChild("Fixed")
                        or parentModel:FindFirstChild("Completed")
                        or parentModel:FindFirstChild("Repaired")

                    if statusValue and (statusValue.Value == true or statusValue.Value == 100) then
                        isFixed = true
                    end
                end

                if not isFixed then
                    local dist = (rootPart.Position - object.Position).Magnitude
                    if dist < shortestDistance then
                        shortestDistance = dist
                        closestGen       = object
                    end
                end
            end
        end
    end

    return closestGen
end

local function getKillerPosition()
    -- Check team-based killer detection first
    for _, team in ipairs(Teams:GetTeams()) do
        if string.find(string.lower(team.Name), "killer")
        or string.find(string.lower(team.Name), "slasher") then
            for _, player in ipairs(team:GetPlayers()) do
                if player ~= localPlayer
                and player.Character
                and player.Character:FindFirstChild("HumanoidRootPart") then
                    return player.Character.HumanoidRootPart.Position
                end
            end
        end
    end

    -- Fallback: scan workspace for known killer model names
    for _, obj in ipairs(workspace:GetChildren()) do
        if obj:IsA("Model")
        and obj.Name ~= localPlayer.Name
        and (FORSAKEN_KILLERS[obj.Name] or Players:GetPlayerFromCharacter(obj)) then
            if obj:FindFirstChild("HumanoidRootPart") then
                return obj.HumanoidRootPart.Position
            end
        end
    end

    return nil
end

-- ========================================================
-- 3. OPTIMIZED LATCHED NAVIGATION MOTOR (0 Lag Override)
-- ========================================================
local currentVisualBeam = nil

local function walkTo(targetPosition)
    -- LATCH CHECK: Only recalculates if destination shifts more than 4 studs (prevents FPS lag)
    if activeTargetPosition and (activeTargetPosition - targetPosition).Magnitude < 4 then return end
    if isComputingPath then return end

    isComputingPath      = true
    activeTargetPosition = targetPosition

    local path = PathfindingService:CreatePath({
        AgentRadius   = 2.5,
        AgentHeight   = 5,
        AgentCanJump  = true,
        AgentCanClimb = false,
    })

    task.spawn(function()
        local success, _ = pcall(function()
            path:ComputeAsync(rootPart.Position, targetPosition)
        end)
        isComputingPath = false

        if success and path.Status == Enum.PathStatus.Success then
            local waypoints = path:GetWaypoints()

            if CONTROLS.Draw_Paths and #waypoints > 1 then
                if not currentVisualBeam then
                    local att0 = Instance.new("Attachment", rootPart)
                    local att1 = Instance.new("Attachment", workspace.Terrain)
                    currentVisualBeam             = Instance.new("Beam", rootPart)
                    currentVisualBeam.Attachment0 = att0
                    currentVisualBeam.Attachment1 = att1
                    currentVisualBeam.Color        = ColorSequence.new(Color3.fromRGB(140, 130, 240))
                    currentVisualBeam.Width0       = 0.4
                    currentVisualBeam.Width1       = 0.4
                end
                currentVisualBeam.Attachment1.Position = waypoints[#waypoints].Position
            elseif currentVisualBeam then
                currentVisualBeam:Destroy()
                currentVisualBeam = nil
            end

            -- WALL BUG FIX: Step to next waypoint to prevent pathing through structural meshes
            if #waypoints > 1 then
                humanoid:MoveTo(waypoints[2].Position)
            end
        else
            -- Direct move fallback if pathfinding fails
            humanoid:MoveTo(targetPosition)
        end
    end)
end

-- ========================================================
-- CHARACTER SYNC
-- ========================================================
local function syncCharacter(char)
    character = char
    humanoid  = char:WaitForChild("Humanoid")
    rootPart  = char:WaitForChild("HumanoidRootPart")
end

localPlayer.CharacterAdded:Connect(syncCharacter)
if localPlayer.Character then syncCharacter(localPlayer.Character) end

-- ========================================================
-- REGULATED GAME TICK CHASSIS
-- ========================================================
task.spawn(function()
    while true do
        task.wait(0.2)

        if CONTROLS.Enable_AI_Play and humanoid and humanoid.Health > 0 and rootPart then
            local killerPos = getKillerPosition()
            local targetGen = getClosestGenerator()

            if killerPos and (rootPart.Position - killerPos).Magnitude < CONTROLS.Avoidance_Distance then
                -- Killer is within avoidance range
                if not CONTROLS.Disable_Auto_Reset then
                    humanoid.Health = 0
                else
                    local runDir = (rootPart.Position - killerPos).Unit
                    walkTo(rootPart.Position + (runDir * 40))
                end
            elseif targetGen then
                walkTo(targetGen.Position)
            else
                -- No target: clear any lingering movement input
                if activeTargetPosition then
                    humanoid:Move(Vector3.new(0, 0, 0))
                    activeTargetPosition = nil
                end
            end
        end
    end
end)
