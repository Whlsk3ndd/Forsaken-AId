--[[
    ██████╗ ██████╗ █████╗ ██████╗ ██╗ ██╗ █████╗ ███╗ ██╗ ██████╗███████╗██████╗ 
    ██╔══██╗██╔══██╗██╔══██╗██╔══██╗██║ ██║██╔══██╗████╗ ██║██╔════╝██╔════╝██╔══██╗
    ██████╔╝██████╔╝███████║██║ ██║██║ ██║███████║██╔██╗ ██║██║ █████╗ ██║ ██║
    ██╔═══╝ ██╔══██╗██╔══██║██║ ██║╚██╗ ██╔╝██╔══██║██║╚██╗██║██║ ██╔══╝ ██║ ██║
    ██║ ██║ ██║██║ ██║██████╔╝ ╚████╔╝ ██║ ██║██║ ╚████║╚██████╗███████╗██████╔╝
    ╚═╝ ╚═╝ ╚═╝╚═╝ ╚═╝╚═════╝ ╚═══╝ ╚═╝ ╚═╝╚═╝ ╚═══╝ ╚═════╝╚══════╝╚═════╝ 
    
    KILLER RADIUS BASED ON SLIDER | TRUE PATHFINDING AROUND WALLS | XENO READY
--]]

-- // SERVICES // --
local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local UserInputService = game:GetService("UserInputService")
local LP = Players.LocalPlayer

-- // STATE // --
local AIEnabled = false
local AISliderValue = 40 -- 0 = flee only when killer is right on you, 100 = flee within 100 studs
local MovingToTarget = false
local CurrentPath = nil
local LastPathTime = 0
local Fleeing = false

-- // REFERENCES // --
local PlayerChar, Humanoid, RootPart
local Generators = {}
local KillerModel = nil

-- // PATHFINDING CONFIG // --
local PATH_OPTIONS = {
    AgentRadius = 2.5, -- slightly wider to avoid tight corners
    AgentHeight = 5,
    AgentCanJump = true,
    AgentMaxSlope = 60,
    WaypointSpacing = 3,
    Costs = { Water = 100, Dangerous = math.huge }
}

-- // UTILITIES // --
local function updateChar()
    PlayerChar = LP.Character
    if PlayerChar then
        Humanoid = PlayerChar:FindFirstChildOfClass("Humanoid")
        RootPart = PlayerChar:FindFirstChild("HumanoidRootPart")
    end
end

-- // REAL KILLER DETECTION (with team/name check) // --
local function findKiller()
    for _, plr in pairs(Players:GetPlayers()) do
        if plr ~= LP and plr.Character then
            local char = plr.Character
            if char:FindFirstChild("HumanoidRootPart") then
                -- Check team or name
                if (plr.Team and (plr.Team.Name:lower():find("killer") or plr.Team.Name:lower():find("monster"))) or
                   (plr.Name:lower():find("killer") or plr.DisplayName:lower():find("killer")) then
                    return char
                end
            end
        end
    end
    -- Fallback: scan workspace for NPC killers
    for _, obj in pairs(workspace:GetDescendants()) do
        if obj:IsA("Model") and obj:FindFirstChild("Humanoid") and obj:FindFirstChild("HumanoidRootPart") then
            local name = obj.Name:lower()
            if name:find("killer") or name:find("monster") or name:find("slender") then
                return obj
            end
        end
    end
    return nil
end

-- // SMART FLEE: find a point away from killer that is reachable via pathfinding // --
local function getFleePosition(killerPos, myPos)
    local direction = (myPos - killerPos).unit
    -- Try multiple angles to find a safe point (in case straight back is blocked)
    for angle = 0, 360, 45 do
        local rad = math.rad(angle)
        local testDir = Vector3.new(
            direction.X * math.cos(rad) - direction.Z * math.sin(rad),
            0,
            direction.X * math.sin(rad) + direction.Z * math.cos(rad)
        ).unit
        local fleePos = myPos + testDir * 40 -- flee 40 studs away
        -- Clamp to map bounds (assume -500 to 500 range)
        fleePos = Vector3.new(math.clamp(fleePos.X, -500, 500), fleePos.Y, math.clamp(fleePos.Z, -500, 500))
        
        -- Quick check if this point is reachable using a cheap path test
        local testPath = PathfindingService:CreatePath(PATH_OPTIONS)
        local success = pcall(function()
            testPath:ComputeAsync(myPos, fleePos)
        end)
        if success and testPath.Status == Enum.PathStatus.Success then
            return fleePos
        end
    end
    -- Fallback: just move straight back
    return myPos + direction * 40
end

-- // PATHFINDING MOVE (with waypoint following, jumps, and dynamic re-pathing) // --
local function moveToPosition(targetPos)
    if not RootPart or not Humanoid or MovingToTarget then return false end
    local path = PathfindingService:CreatePath(PATH_OPTIONS)
    local success = pcall(function()
        path:ComputeAsync(RootPart.Position, targetPos)
    end)
    if not success or path.Status ~= Enum.PathStatus.Success then
        -- No path found – fallback to straight line (rare)
        Humanoid:MoveTo(targetPos)
        return false
    end
    
    local waypoints = path:GetWaypoints()
    if #waypoints == 0 then return false end
    
    MovingToTarget = true
    for i, waypoint in ipairs(waypoints) do
        if not AIEnabled then break end
        if not RootPart or not Humanoid then break end
        
        -- Jump if needed
        if waypoint.Action == Enum.PathWaypointAction.Jump then
            Humanoid.Jump = true
            task.wait(0.1)
        end
        
        Humanoid:MoveTo(waypoint.Position)
        -- Wait until we reach the waypoint or timeout
        local startTime = tick()
        while (RootPart.Position - waypoint.Position).magnitude > 3 do
            if tick() - startTime > 2 then break end -- stuck, abort this path
            if not AIEnabled then break end
            task.wait(0.05)
        end
    end
    MovingToTarget = false
    return true
end

-- // GENERATOR SCANNER (auto-detect any interactive object) // --
local function scanGenerators()
    local newGens = {}
    for _, prompt in pairs(workspace:GetDescendants()) do
        if prompt:IsA("ProximityPrompt") and prompt.Parent then
            local part = prompt.Parent:IsA("BasePart") and prompt.Parent or prompt.Parent:FindFirstChildWhichIsA("BasePart")
            if part then
                table.insert(newGens, part)
            end
        end
    end
    -- Also include any part named generator
    for _, part in pairs(workspace:GetDescendants()) do
        if part:IsA("BasePart") and part.Name:lower():find("generator") then
            if not table.find(newGens, part) then
                table.insert(newGens, part)
            end
        end
    end
    Generators = newGens
    return #Generators
end

-- // INTERACT WITH GENERATOR // --
local function interactWithGenerator(gen)
    local prompt = gen:FindFirstChildWhichIsA("ProximityPrompt")
    if prompt then
        prompt:InputHoldStart()
        task.wait(0.2)
        prompt:InputHoldEnd()
    else
        local click = gen:FindFirstChildWhichIsA("ClickDetector")
        if click then click:FireClick(RootPart) end
    end
end

-- // INFINITE STAMINA HACK (Xeno) // --
local function applyStaminaHack()
    if not Humanoid then return end
    -- Method 1: Override Humanoid.Stamina property if exists
    local staminaProp = Humanoid:FindFirstChild("Stamina")
    if staminaProp and staminaProp:IsA("NumberValue") then
        setreadonly(staminaProp, false)
        staminaProp.Value = 100
        setreadonly(staminaProp, true)
    end
    -- Method 2: Force sprint attribute
    if Humanoid.Sprint then
        Humanoid.Sprint = true
    end
    -- Method 3: Hook the stamina deduction function (advanced)
    pcall(function()
        local mt = getrawmetatable(Humanoid)
        if mt and mt.__index then
            local old = mt.__index
            mt.__index = function(self, k)
                if k == "Stamina" then return 100 end
                return old(self, k)
            end
        end
    end)
end

-- // MAIN AI DECISION (called every 0.25s) // --
local function aiTick()
    if not AIEnabled then return end
    if not PlayerChar or not Humanoid or not RootPart then
        updateChar()
        if not PlayerChar then return end
    end
    
    -- 1. Check killer distance (using slider value as radius)
    KillerModel = findKiller()
    local killerDist = nil
    if KillerModel and RootPart then
        local killerRoot = KillerModel:FindFirstChild("HumanoidRootPart")
        if killerRoot then
            killerDist = (RootPart.Position - killerRoot.Position).magnitude
            -- If killer is within slider radius -> FLEE
            if killerDist <= AISliderValue then
                if not Fleeing then
                    local fleePos = getFleePosition(killerRoot.Position, RootPart.Position)
                    moveToPosition(fleePos)
                    Fleeing = true
                else
                    -- Already fleeing, continue moving to the last flee target
                    -- We'll let the movement continue
                end
                return -- flee is highest priority
            else
                Fleeing = false
            end
        end
    else
        Fleeing = false
    end
    
    -- 2. No killer nearby -> go to nearest generator (with pathfinding)
    if #Generators == 0 then
        scanGenerators()
        return
    end
    
    local nearestGen = nil
    local nearestDist = math.huge
    for _, gen in pairs(Generators) do
        if gen and gen.Parent then
            local d = (RootPart.Position - gen.Position).magnitude
            if d < nearestDist then
                nearestDist = d
                nearestGen = gen
            end
        end
    end
    
    if nearestGen then
        if nearestDist > 4 then
            moveToPosition(nearestGen.Position)
        else
            interactWithGenerator(nearestGen)
            task.wait(0.3)
        end
    end
end

-- // BACKGROUND LOOPS (THROTTLED FOR PERFORMANCE) // --
task.spawn(function()
    while true do
        task.wait(0.25) -- AI decision every 250ms
        aiTick()
    end
end)

task.spawn(function()
    while true do
        task.wait(0.3)
        if AIEnabled then
            applyStaminaHack()
        end
    end
end)

task.spawn(function()
    while true do
        task.wait(4)
        if AIEnabled then
            scanGenerators()
        end
    end
end)

-- // COOL GUI HUB (WITH SLIDER) // --
local function createHub()
    local sg = Instance.new("ScreenGui")
    sg.Name = "AdvancedAIHub"
    sg.Parent = game.CoreGui
    sg.ResetOnSpawn = false
    
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, 340, 0, 260)
    frame.Position = UDim2.new(0.5, -170, 0.5, -130)
    frame.BackgroundColor3 = Color3.fromRGB(8, 8, 18)
    frame.BackgroundTransparency = 0.2
    frame.BorderSizePixel = 0
    frame.Parent = sg
    Instance.new("UICorner").CornerRadius = UDim.new(0, 12); Instance.new("UICorner").Parent = frame
    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(255, 50, 100)
    stroke.Thickness = 1.5
    stroke.Parent = frame
    
    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, 0, 0, 35)
    title.BackgroundTransparency = 1
    title.Text = "🔪 ADVANCED AI PATHFINDER 🔪"
    title.TextColor3 = Color3.fromRGB(255, 80, 120)
    title.Font = Enum.Font.GothamBold
    title.TextSize = 15
    title.Parent = frame
    
    local toggle = Instance.new("TextButton")
    toggle.Size = UDim2.new(0, 200, 0, 45)
    toggle.Position = UDim2.new(0.5, -100, 0, 55)
    toggle.BackgroundColor3 = Color3.fromRGB(0, 120, 200)
    toggle.Text = "🔴 AI OFF"
    toggle.TextColor3 = Color3.new(1,1,1)
    toggle.Font = Enum.Font.GothamBold
    toggle.TextSize = 18
    toggle.Parent = frame
    Instance.new("UICorner").CornerRadius = UDim.new(0, 8); Instance.new("UICorner").Parent = toggle
    
    local sliderFrame = Instance.new("Frame")
    sliderFrame.Size = UDim2.new(0, 280, 0, 50)
    sliderFrame.Position = UDim2.new(0.5, -140, 0, 115)
    sliderFrame.BackgroundTransparency = 1
    sliderFrame.Parent = frame
    
    local sliderLabel = Instance.new("TextLabel")
    sliderLabel.Size = UDim2.new(0, 140, 0, 20)
    sliderLabel.Position = UDim2.new(0, 0, 0, 0)
    sliderLabel.BackgroundTransparency = 1
    sliderLabel.Text = "Killer Alert Radius: 40"
    sliderLabel.TextColor3 = Color3.fromRGB(255, 180, 180)
    sliderLabel.Font = Enum.Font.Gotham
    sliderLabel.TextSize = 12
    sliderLabel.Parent = sliderFrame
    
    local sliderBg = Instance.new("Frame")
    sliderBg.Size = UDim2.new(0, 220, 0, 6)
    sliderBg.Position = UDim2.new(0, 0, 0, 22)
    sliderBg.BackgroundColor3 = Color3.fromRGB(50, 50, 70)
    sliderBg.BorderSizePixel = 0
    sliderBg.Parent = sliderFrame
    local fill = Instance.new("Frame")
    fill.Size = UDim2.new(0.4, 0, 1, 0)
    fill.BackgroundColor3 = Color3.fromRGB(255, 80, 120)
    fill.BorderSizePixel = 0
    fill.Parent = sliderBg
    local knob = Instance.new("TextButton")
    knob.Size = UDim2.new(0, 14, 0, 14)
    knob.Position = UDim2.new(0.4, -7, 0, -4)
    knob.BackgroundColor3 = Color3.new(1,1,1)
    knob.Text = ""
    knob.AutoButtonColor = false
    knob.Parent = sliderFrame
    Instance.new("UICorner").CornerRadius = UDim.new(1,0); Instance.new("UICorner").Parent = knob
    
    local status = Instance.new("TextLabel")
    status.Size = UDim2.new(1, -20, 0, 35)
    status.Position = UDim2.new(0, 10, 0, 190)
    status.BackgroundTransparency = 1
    status.Text = "Ready"
    status.TextColor3 = Color3.fromRGB(200, 200, 230)
    status.Font = Enum.Font.Gotham
    status.TextSize = 12
    status.TextXAlignment = Enum.TextXAlignment.Left
    status.Parent = frame
    
    local function setSliderValue(val)
        val = math.clamp(val, 0, 100)
        AISliderValue = val
        local percent = val / 100
        fill.Size = UDim2.new(percent, 0, 1, 0)
        knob.Position = UDim2.new(percent, -7, 0, -4)
        sliderLabel.Text = "Killer Alert Radius: " .. math.floor(val)
    end
    setSliderValue(40)
    
    knob.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            local moveConn, endConn
            moveConn = UserInputService.InputChanged:Connect(function(io)
                if io.UserInputType == Enum.UserInputType.MouseMovement then
                    local relX = math.clamp(io.Position.X - sliderBg.AbsolutePosition.X, 0, sliderBg.AbsoluteSize.X)
                    local newVal = math.floor((relX / sliderBg.AbsoluteSize.X) * 100)
                    setSliderValue(newVal)
                end
            end)
            endConn = UserInputService.InputEnded:Connect(function(io)
                if io.UserInputType == Enum.UserInputType.MouseButton1 then
                    moveConn:Disconnect()
                    endConn:Disconnect()
                end
            end)
        end
    end)
    
    toggle.MouseButton1Click:Connect(function()
        AIEnabled = not AIEnabled
        if AIEnabled then
            toggle.Text = "🟢 AI ON"
            toggle.BackgroundColor3 = Color3.fromRGB(0, 180, 80)
            updateChar()
            scanGenerators()
            status.Text = "AI ACTIVE | Pathfinding around walls | Stamina hacked"
        else
            toggle.Text = "🔴 AI OFF"
            toggle.BackgroundColor3 = Color3.fromRGB(0, 120, 200)
            status.Text = "AI OFF"
        end
    end)
    
    -- Status updater
    task.spawn(function()
        while true do
            task.wait(1.5)
            if AIEnabled then
                local killer = findKiller()
                local distText = ""
                if killer and RootPart then
                    local kr = killer:FindFirstChild("HumanoidRootPart")
                    if kr then
                        local d = (RootPart.Position - kr.Position).magnitude
                        distText = string.format(" | Killer: %.1f studs", d)
                    else
                        distText = " | Killer: near"
                    end
                else
                    distText = " | Killer: none"
                end
                status.Text = string.format("Gens: %d%s | Alert: %d", #Generators, distText, AISliderValue)
            end
        end
    end)
    
    -- Dragging
    local dragStart, dragPos, dragging = nil
    title.InputBegan:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            dragStart = inp.Position
            dragPos = frame.Position
            inp.Changed:Connect(function()
                if inp.UserInputState == Enum.UserInputState.End then dragging = false end
            end)
        end
    end)
    UserInputService.InputChanged:Connect(function(inp)
        if dragging and inp.UserInputType == Enum.UserInputType.MouseMovement then
            local delta = inp.Position - dragStart
            frame.Position = UDim2.new(dragPos.X.Scale, dragPos.X.Offset + delta.X, dragPos.Y.Scale, dragPos.Y.Offset + delta.Y)
        end
    end)
end

-- // INIT // --
updateChar()
LP.CharacterAdded:Connect(function(char)
    task.wait(0.3)
    updateChar()
    if AIEnabled then scanGenerators() end
end)
createHub()
print("🔥 Advanced AI Pathfinder loaded. Killer radius = slider value. Pathfinding goes around walls. Xeno ready.")
