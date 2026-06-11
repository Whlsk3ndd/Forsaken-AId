--[[
    ██████╗ ██████╗  █████╗ ██████╗ ██╗   ██╗ █████╗ ███╗   ██╗ ██████╗███████╗██████╗ 
    ██╔══██╗██╔══██╗██╔══██╗██╔══██╗██║   ██║██╔══██╗████╗  ██║██╔════╝██╔════╝██╔══██╗
    ██████╔╝██████╔╝███████║██║  ██║██║   ██║███████║██╔██╗ ██║██║     █████╗  ██║  ██║
    ██╔═══╝ ██╔══██╗██╔══██║██║  ██║╚██╗ ██╔╝██╔══██║██║╚██╗██║██║     ██╔══╝  ██║  ██║
    ██║     ██║  ██║██║  ██║██████╔╝ ╚████╔╝ ██║  ██║██║ ╚████║╚██████╗███████╗██████╔╝
    ╚═╝     ╚═╝  ╚═╝╚═╝  ╚═╝╚═════╝   ╚═══╝  ╚═╝  ╚═╝╚═╝  ╚═══╝ ╚═════╝╚══════╝╚═════╝ 
    
    ADDED: CLOSE & DISABLE button + HIDE button (with show button)
    XENO READY | MAP AUTO-DETECT | WALL AVOIDANCE
--]]

-- // SERVICES // --
local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local UserInputService = game:GetService("UserInputService")
local LP = Players.LocalPlayer

-- // STATE // --
local AIEnabled = false
local AISliderValue = 40
local MovingToTarget = false
local Fleeing = false
local ScriptActive = true          -- if false, all loops exit

-- // REFERENCES // --
local PlayerChar, Humanoid, RootPart
local Generators = {}
local KillerModel = nil

-- // PATHFINDING CONFIG // --
local PATH_OPTIONS = {
    AgentRadius = 2.5,
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

-- // KILLER DETECTION // --
local function findKiller()
    for _, plr in pairs(Players:GetPlayers()) do
        if plr ~= LP and plr.Character then
            local char = plr.Character
            if char:FindFirstChild("HumanoidRootPart") then
                if (plr.Team and (plr.Team.Name:lower():find("killer") or plr.Team.Name:lower():find("monster"))) or
                   (plr.Name:lower():find("killer") or plr.DisplayName:lower():find("killer")) then
                    return char
                end
            end
        end
    end
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

-- // SMART FLEE POSITION // --
local function getFleePosition(killerPos, myPos)
    local direction = (myPos - killerPos).unit
    for angle = 0, 360, 45 do
        local rad = math.rad(angle)
        local testDir = Vector3.new(
            direction.X * math.cos(rad) - direction.Z * math.sin(rad),
            0,
            direction.X * math.sin(rad) + direction.Z * math.cos(rad)
        ).unit
        local fleePos = myPos + testDir * 40
        fleePos = Vector3.new(math.clamp(fleePos.X, -500, 500), fleePos.Y, math.clamp(fleePos.Z, -500, 500))
        local testPath = PathfindingService:CreatePath(PATH_OPTIONS)
        local success = pcall(function()
            testPath:ComputeAsync(myPos, fleePos)
        end)
        if success and testPath.Status == Enum.PathStatus.Success then
            return fleePos
        end
    end
    return myPos + direction * 40
end

-- // PATHFINDING MOVE // --
local function moveToPosition(targetPos)
    if not RootPart or not Humanoid or MovingToTarget then return false end
    local path = PathfindingService:CreatePath(PATH_OPTIONS)
    local success = pcall(function()
        path:ComputeAsync(RootPart.Position, targetPos)
    end)
    if not success or path.Status ~= Enum.PathStatus.Success then
        Humanoid:MoveTo(targetPos)
        return false
    end
    
    local waypoints = path:GetWaypoints()
    if #waypoints == 0 then return false end
    
    MovingToTarget = true
    for _, waypoint in ipairs(waypoints) do
        if not AIEnabled or not ScriptActive then break end
        if not RootPart or not Humanoid then break end
        if waypoint.Action == Enum.PathWaypointAction.Jump then
            Humanoid.Jump = true
            task.wait(0.1)
        end
        Humanoid:MoveTo(waypoint.Position)
        local startTime = tick()
        while (RootPart.Position - waypoint.Position).magnitude > 3 do
            if tick() - startTime > 2 then break end
            if not AIEnabled or not ScriptActive then break end
            task.wait(0.05)
        end
    end
    MovingToTarget = false
    return true
end

-- // GENERATOR SCANNER // --
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

-- // CORRECT GENERATOR INTERACTION // --
local function interactWithGenerator(gen)
    local prompt = gen:FindFirstChildWhichIsA("ProximityPrompt")
    if prompt then
        pcall(function()
            prompt:Prompt()
        end)
        return
    end
    local click = gen:FindFirstChildWhichIsA("ClickDetector")
    if click and RootPart then
        pcall(function()
            click:FireClick(RootPart)
        end)
        return
    end
    local remote = gen.Parent:FindFirstChild("GenerateRemote") or 
                   game:GetService("ReplicatedStorage"):FindFirstChild("Generate")
    if remote and remote:IsA("RemoteEvent") then
        pcall(function()
            remote:FireServer(gen)
        end)
    end
end

-- // STAMINA HACK (XENO) // --
local function applyStaminaHack()
    if not Humanoid then return end
    local staminaProp = Humanoid:FindFirstChild("Stamina")
    if staminaProp and staminaProp:IsA("NumberValue") then
        setreadonly(staminaProp, false)
        staminaProp.Value = 100
        setreadonly(staminaProp, true)
    end
    if Humanoid.Sprint then
        Humanoid.Sprint = true
    end
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

-- // MAIN AI TICK // --
local function aiTick()
    if not AIEnabled or not ScriptActive then return end
    if not PlayerChar or not Humanoid or not RootPart then
        updateChar()
        if not PlayerChar then return end
    end
    
    -- Killer avoidance
    KillerModel = findKiller()
    if KillerModel and RootPart then
        local killerRoot = KillerModel:FindFirstChild("HumanoidRootPart")
        if killerRoot then
            local dist = (RootPart.Position - killerRoot.Position).magnitude
            if dist <= AISliderValue then
                if not Fleeing then
                    local fleePos = getFleePosition(killerRoot.Position, RootPart.Position)
                    moveToPosition(fleePos)
                    Fleeing = true
                end
                return
            else
                Fleeing = false
            end
        end
    else
        Fleeing = false
    end
    
    -- Generator farming
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

-- // BACKGROUND LOOPS (with exit condition) // --
task.spawn(function()
    while ScriptActive do
        task.wait(0.25)
        aiTick()
    end
end)

task.spawn(function()
    while ScriptActive do
        task.wait(0.3)
        if AIEnabled then applyStaminaHack() end
    end
end)

task.spawn(function()
    while ScriptActive do
        task.wait(4)
        if AIEnabled then scanGenerators() end
    end
end)

-- // GUI HUB (with new buttons) // --
local function createHub()
    local sg = Instance.new("ScreenGui")
    sg.Name = "AdvancedAIHub"
    sg.Parent = game.CoreGui
    sg.ResetOnSpawn = false
    
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, 400, 0, 300)  -- made a bit taller for extra buttons
    frame.Position = UDim2.new(0.5, -200, 0.5, -150)
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
    toggle.Position = UDim2.new(0.5, -100, 0, 50)
    toggle.BackgroundColor3 = Color3.fromRGB(0, 120, 200)
    toggle.Text = "🔴 AI OFF"
    toggle.TextColor3 = Color3.new(1,1,1)
    toggle.Font = Enum.Font.GothamBold
    toggle.TextSize = 18
    toggle.Parent = frame
    Instance.new("UICorner").CornerRadius = UDim.new(0, 8); Instance.new("UICorner").Parent = toggle
    
    -- Slider
    local sliderFrame = Instance.new("Frame")
    sliderFrame.Size = UDim2.new(0, 280, 0, 50)
    sliderFrame.Position = UDim2.new(0.5, -140, 0, 110)
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
    
    -- Status label
    local status = Instance.new("TextLabel")
    status.Size = UDim2.new(1, -20, 0, 35)
    status.Position = UDim2.new(0, 10, 0, 175)
    status.BackgroundTransparency = 1
    status.Text = "Ready"
    status.TextColor3 = Color3.fromRGB(200, 200, 230)
    status.Font = Enum.Font.Gotham
    status.TextSize = 12
    status.TextXAlignment = Enum.TextXAlignment.Left
    status.Parent = frame
    
    -- NEW BUTTONS: HIDE and CLOSE & DISABLE
    local hideBtn = Instance.new("TextButton")
    hideBtn.Size = UDim2.new(0, 90, 0, 35)
    hideBtn.Position = UDim2.new(0.05, 0, 0, 235)
    hideBtn.BackgroundColor3 = Color3.fromRGB(80, 80, 100)
    hideBtn.Text = "⛔ HIDE"
    hideBtn.TextColor3 = Color3.new(1,1,1)
    hideBtn.Font = Enum.Font.GothamBold
    hideBtn.TextSize = 14
    hideBtn.Parent = frame
    Instance.new("UICorner").CornerRadius = UDim.new(0, 6); Instance.new("UICorner").Parent = hideBtn
    
    local closeBtn = Instance.new("TextButton")
    closeBtn.Size = UDim2.new(0, 130, 0, 35)
    closeBtn.Position = UDim2.new(0.5, -65, 0, 235)
    closeBtn.BackgroundColor3 = Color3.fromRGB(180, 40, 60)
    closeBtn.Text = "🔴 CLOSE & DISABLE"
    closeBtn.TextColor3 = Color3.new(1,1,1)
    closeBtn.Font = Enum.Font.GothamBold
    closeBtn.TextSize = 13
    closeBtn.Parent = frame
    Instance.new("UICorner").CornerRadius = UDim.new(0, 6); Instance.new("UICorner").Parent = closeBtn
    
    -- Show button (initially hidden) - appears when HIDE is pressed
    local showBtn = nil
    
    -- HIDE functionality
    hideBtn.MouseButton1Click:Connect(function()
        frame.Visible = false
        -- Create a small floating "Show" button if not already present
        if not showBtn then
            showBtn = Instance.new("TextButton")
            showBtn.Size = UDim2.new(0, 100, 0, 30)
            showBtn.Position = UDim2.new(0.02, 0, 0.9, 0)   -- bottom left corner
            showBtn.BackgroundColor3 = Color3.fromRGB(0, 180, 200)
            showBtn.Text = "🔽 SHOW MENU"
            showBtn.TextColor3 = Color3.new(1,1,1)
            showBtn.Font = Enum.Font.GothamBold
            showBtn.TextSize = 12
            showBtn.Parent = sg
            Instance.new("UICorner").CornerRadius = UDim.new(0, 8); Instance.new("UICorner").Parent = showBtn
            
            showBtn.MouseButton1Click:Connect(function()
                frame.Visible = true
                showBtn:Destroy()
                showBtn = nil
            end)
        end
    end)
    
    -- CLOSE & DISABLE: stops AI, kills loops, destroys GUI
    closeBtn.MouseButton1Click:Connect(function()
        AIEnabled = false
        ScriptActive = false   -- this will break all background loops
        -- Destroy the entire GUI (including any show button)
        sg:Destroy()
        -- Optionally print a message
        print("🔴 AI and script fully disabled. Menu closed.")
    end)
    
    -- Slider drag logic (same as before)
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
        while ScriptActive and sg and sg.Parent do
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
    
    -- Draggable title
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
LP.CharacterAdded:Connect(function()
    task.wait(0.3)
    updateChar()
    if AIEnabled then scanGenerators() end
end)
createHub()
print("✅ Advanced AI Pathfinder (with HIDE and CLOSE buttons) loaded. Xeno ready.")
