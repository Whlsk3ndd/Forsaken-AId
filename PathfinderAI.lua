--[[
    ██████╗ ██████╗  █████╗ ██████╗ ██╗   ██╗ █████╗ ███╗   ██╗ ██████╗███████╗██████╗ 
    ██╔══██╗██╔══██╗██╔══██╗██╔══██╗██║   ██║██╔══██╗████╗  ██║██╔════╝██╔════╝██╔══██╗
    ██████╔╝██████╔╝███████║██║  ██║██║   ██║███████║██╔██╗ ██║██║     █████╗  ██║  ██║
    ██╔═══╝ ██╔══██╗██╔══██║██║  ██║╚██╗ ██╔╝██╔══██║██║╚██╗██║██║     ██╔══╝  ██║  ██║
    ██║     ██║  ██║██║  ██║██████╔╝ ╚████╔╝ ██║  ██║██║ ╚████║╚██████╗███████╗██████╔╝
    ╚═╝     ╚═╝  ╚═╝╚═╝  ╚═╝╚═════╝   ╚═══╝  ╚═╝  ╚═╝╚═╝  ╚═══╝ ╚═════╝╚══════╝╚═════╝ 
    
    FIXED: Generator hold interaction | Real infinite sprint | Blur removal | Killer flee
--]]

-- // SERVICES // --
local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")
local LP = Players.LocalPlayer

-- // STATE // --
local AIEnabled = false
local AISliderValue = 40
local MovingToTarget = false
local Fleeing = false
local ScriptActive = true
local OriginalWalkSpeed = 16  -- will be set later

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
        if Humanoid and OriginalWalkSpeed == 16 then
            OriginalWalkSpeed = Humanoid.WalkSpeed
        end
    else
        Humanoid = nil
        RootPart = nil
    end
end

-- // REMOVE BLUR EFFECTS (stamina blur) // --
local function removeBlurEffects()
    -- Disable all BlurEffect in Lighting
    for _, effect in pairs(Lighting:GetChildren()) do
        if effect:IsA("BlurEffect") then
            effect.Enabled = false
        end
    end
    -- Also check the player's camera (some games attach blur there)
    local camera = workspace.CurrentCamera
    if camera then
        for _, effect in pairs(camera:GetChildren()) do
            if effect:IsA("BlurEffect") then
                effect.Enabled = false
            end
        end
    end
    -- Check for PostProcessing effects
    for _, effect in pairs(Lighting:GetChildren()) do
        if effect:IsA("BloomEffect") or effect:IsA("ColorCorrectionEffect") then
            -- optional: you can disable these too if they cause blur-like effect
        end
    end
end

-- // REAL INFINITE SPRINT (speed + animation + no blur) // --
local function applyInfiniteStamina()
    if not Humanoid then return end
    -- Force walk speed to max (typically 24 for sprint)
    local maxSpeed = 24
    if Humanoid.WalkSpeed < maxSpeed then
        Humanoid.WalkSpeed = maxSpeed
    end
    -- Override stamina value if exists
    local staminaProp = Humanoid:FindFirstChild("Stamina")
    if staminaProp and staminaProp:IsA("NumberValue") then
        setreadonly(staminaProp, false)
        staminaProp.Value = 100
        setreadonly(staminaProp, true)
    end
    -- Force sprint attribute (if game uses it)
    if Humanoid:GetAttribute("Sprinting") ~= true then
        Humanoid:SetAttribute("Sprinting", true)
    end
    -- Some games use a bool value in the character
    local sprintBool = PlayerChar:FindFirstChild("IsSprinting")
    if sprintBool and sprintBool:IsA("BoolValue") then
        sprintBool.Value = true
    end
    -- Remove blur every frame to be sure
    removeBlurEffects()
end

-- // LOBBY/DEAD DETECTION // --
local function isPlayerAliveAndInMatch()
    if not PlayerChar or not Humanoid then return false end
    if Humanoid.Health <= 0 then return false end
    -- Check for lobby parts
    local lobbyPart = workspace:FindFirstChild("Lobby") or workspace:FindFirstChild("LobbyArea")
    if lobbyPart and RootPart then
        if (RootPart.Position - lobbyPart.Position).magnitude < 100 then
            return false
        end
    end
    -- Check for lobby GUI
    local playerGui = LP:FindFirstChild("PlayerGui")
    if playerGui then
        for _, gui in pairs(playerGui:GetChildren()) do
            if gui:IsA("ScreenGui") and (gui.Name:lower():find("lobby") or gui.Name:lower():find("menu")) then
                if gui.Enabled then return false end
            end
        end
    end
    return true
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

-- // SMART FLEE (with fallback) // --
local function getFleePosition(killerPos, myPos)
    local direction = (myPos - killerPos).unit
    local fleeDist = 50
    -- Try straight back first
    local fleePos = myPos + direction * fleeDist
    fleePos = Vector3.new(math.clamp(fleePos.X, -500, 500), fleePos.Y, math.clamp(fleePos.Z, -500, 500))
    
    -- Quick path check
    local testPath = PathfindingService:CreatePath(PATH_OPTIONS)
    local success = pcall(function()
        testPath:ComputeAsync(myPos, fleePos)
    end)
    if success and testPath.Status == Enum.PathStatus.Success then
        return fleePos
    end
    
    -- Fallback: try multiple angles
    for angle = 45, 315, 45 do
        local rad = math.rad(angle)
        local testDir = Vector3.new(
            direction.X * math.cos(rad) - direction.Z * math.sin(rad),
            0,
            direction.X * math.sin(rad) + direction.Z * math.cos(rad)
        ).unit
        local pos = myPos + testDir * fleeDist
        pos = Vector3.new(math.clamp(pos.X, -500, 500), pos.Y, math.clamp(pos.Z, -500, 500))
        local p2 = PathfindingService:CreatePath(PATH_OPTIONS)
        local ok = pcall(function() p2:ComputeAsync(myPos, pos) end)
        if ok and p2.Status == Enum.PathStatus.Success then
            return pos
        end
    end
    -- Last resort: just run straight back (no pathfinding)
    return myPos + direction * fleeDist
end

-- // PATHFINDING MOVE (with timeout) // --
local function moveToPosition(targetPos)
    if not RootPart or not Humanoid or MovingToTarget then return false end
    local path = PathfindingService:CreatePath(PATH_OPTIONS)
    local success = pcall(function()
        path:ComputeAsync(RootPart.Position, targetPos)
    end)
    if not success or path.Status ~= Enum.PathStatus.Success then
        -- No path: just move in straight line
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
        while (RootPart.Position - waypoint.Position).magnitude > 4 do
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

-- // FIXED GENERATOR INTERACTION (HOLD FOR 0.5 SEC) // --
local function interactWithGenerator(gen)
    local prompt = gen:FindFirstChildWhichIsA("ProximityPrompt")
    if prompt then
        -- Simulate holding the prompt (many games require hold)
        pcall(function()
            prompt:InputHoldStart()
            task.wait(0.5)   -- hold for half a second
            prompt:InputHoldEnd()
        end)
        return
    end
    -- Fallback: ClickDetector
    local click = gen:FindFirstChildWhichIsA("ClickDetector")
    if click and RootPart then
        pcall(function()
            click:FireClick(RootPart)
        end)
        return
    end
    -- Fallback: Remote event
    local remote = gen.Parent:FindFirstChild("GenerateRemote") or 
                   game:GetService("ReplicatedStorage"):FindFirstChild("Generate")
    if remote and remote:IsA("RemoteEvent") then
        pcall(function()
            remote:FireServer(gen)
        end)
    end
end

-- // MAIN AI TICK // --
local function aiTick()
    if not AIEnabled or not ScriptActive then return end
    if not isPlayerAliveAndInMatch() then
        if Humanoid then Humanoid:MoveTo(Vector3.new(0,0,0)) end
        return
    end
    if not PlayerChar or not Humanoid or not RootPart then
        updateChar()
        if not PlayerChar then return end
    end
    
    -- 1. Killer avoidance
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
    
    -- 2. Generator farming
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
        if nearestDist > 5 then
            moveToPosition(nearestGen.Position)
        else
            interactWithGenerator(nearestGen)
            task.wait(0.5)  -- wait after interaction
        end
    end
end

-- // BACKGROUND LOOPS // --
task.spawn(function()
    while ScriptActive do
        task.wait(0.25)
        aiTick()
    end
end)

task.spawn(function()
    while ScriptActive do
        task.wait(0.2)
        if AIEnabled then
            applyInfiniteStamina()
        end
    end
end)

task.spawn(function()
    while ScriptActive do
        task.wait(4)
        if AIEnabled then
            scanGenerators()
            removeBlurEffects()
        end
    end
end)

-- // SUPPRESS GAME'S "Touched" SPAM (optional) // --
local oldWarn = warn
warn = function(...)
    local msg = tostring(...)
    if msg:find("ontouched") or msg:find("Touched") then
        return
    end
    oldWarn(...)
end

-- // GUI HUB (with HIDE and CLOSE) // --
local function createHub()
    local sg = Instance.new("ScreenGui")
    sg.Name = "AdvancedAIHub"
    sg.Parent = game.CoreGui
    sg.ResetOnSpawn = false
    
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, 400, 0, 300)
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
    
    -- HIDE button
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
    
    -- CLOSE & DISABLE button
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
    
    local showBtn = nil
    
    hideBtn.MouseButton1Click:Connect(function()
        frame.Visible = false
        if not showBtn then
            showBtn = Instance.new("TextButton")
            showBtn.Size = UDim2.new(0, 100, 0, 30)
            showBtn.Position = UDim2.new(0.02, 0, 0.9, 0)
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
    
    closeBtn.MouseButton1Click:Connect(function()
        AIEnabled = false
        ScriptActive = false
        -- Restore original walk speed if possible
        if Humanoid and OriginalWalkSpeed then
            Humanoid.WalkSpeed = OriginalWalkSpeed
        end
        sg:Destroy()
        print("🔴 AI and script fully disabled. Menu closed.")
    end)
    
    toggle.MouseButton1Click:Connect(function()
        AIEnabled = not AIEnabled
        if AIEnabled then
            toggle.Text = "🟢 AI ON"
            toggle.BackgroundColor3 = Color3.fromRGB(0, 180, 80)
            updateChar()
            scanGenerators()
            removeBlurEffects()
            status.Text = "AI ACTIVE | Infinite sprint + blur removed"
        else
            toggle.Text = "🔴 AI OFF"
            toggle.BackgroundColor3 = Color3.fromRGB(0, 120, 200)
            status.Text = "AI OFF"
            -- restore original walk speed
            if Humanoid and OriginalWalkSpeed then
                Humanoid.WalkSpeed = OriginalWalkSpeed
            end
        end
    end)
    
    -- Status updater
    task.spawn(function()
        while ScriptActive and sg and sg.Parent do
            task.wait(1)
            if AIEnabled then
                local alive = isPlayerAliveAndInMatch()
                local stateText = alive and "🔵 ALIVE" or "⚫ LOBBY/DEAD"
                local killerInfo = ""
                if alive then
                    local killer = findKiller()
                    if killer and RootPart then
                        local kr = killer:FindFirstChild("HumanoidRootPart")
                        if kr then
                            local d = (RootPart.Position - kr.Position).magnitude
                            killerInfo = string.format(" | Killer: %.1f", d)
                        else
                            killerInfo = " | Killer: near"
                        end
                    else
                        killerInfo = " | Killer: none"
                    end
                end
                status.Text = string.format("Gens: %d %s%s | Alert: %d", #Generators, stateText, killerInfo, AISliderValue)
            end
        end
    end)
    
    -- Draggable
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
    if AIEnabled then
        scanGenerators()
        removeBlurEffects()
    end
end)
createHub()
print("✅ FULLY FIXED AI: Generator hold interaction, real sprint speed, blur removed, killer flee. Xeno ready.")
