--[[
    FORSAKEN AI – FINAL CORRECTIONS
    - Killer detection (only real killers, not survivors)
    - Generator interaction using screen click (not just FireClick)
    - Flee with wall avoidance (raycasts to avoid walls)
--]]

-- // SERVICES // --
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local VirtualInput = game:GetService("VirtualInput")
local RunService = game:GetService("RunService")
local LP = Players.LocalPlayer

-- // KILLER NAMES (case-insensitive) //
local KILLER_NAMES = {
    "noli", "slasher", "c00lkidd", "john doe", "1x1x1x1", "guest 666", "nosferatu"
}

-- // STATE // --
local AIEnabled = false
local ScriptActive = true
local SliderValue = 40
local MovingToTarget = false
local PlayerChar, Humanoid, RootPart
local Generators = {}               -- only real generators (with ProximityPrompt or ClickDetector)
local CompletedGenerators = {}
local CurrentAction = "Idle"
local LastFleeTime = 0
local RoundActive = false

-- // CONSTANTS // --
local WALK_SPEED = 24

-- // DEBUG OVERLAY // --
local DebugLabel
local function createOverlay()
    local sg = Instance.new("ScreenGui")
    sg.Name = "AIDebug"
    sg.Parent = game.CoreGui
    sg.ResetOnSpawn = false
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, 350, 0, 90)
    frame.Position = UDim2.new(0, 10, 0, 10)
    frame.BackgroundColor3 = Color3.fromRGB(0,0,0)
    frame.BackgroundTransparency = 0.6
    frame.Parent = sg
    Instance.new("UICorner").CornerRadius = UDim.new(0,8)
    DebugLabel = Instance.new("TextLabel")
    DebugLabel.Size = UDim2.new(1, -10, 1, -10)
    DebugLabel.Position = UDim2.new(0,5,0,5)
    DebugLabel.BackgroundTransparency = 1
    DebugLabel.Text = "Initializing..."
    DebugLabel.TextColor3 = Color3.fromRGB(255,255,0)
    DebugLabel.Font = Enum.Font.Gotham
    DebugLabel.TextSize = 12
    DebugLabel.TextXAlignment = Enum.TextXAlignment.Left
    DebugLabel.TextWrapped = true
    DebugLabel.Parent = frame
end

local function updateDebug(text)
    if DebugLabel then DebugLabel.Text = text end
    print("[AI] " .. text)
end

-- // UTILITIES // --
local function updateChar()
    PlayerChar = LP.Character
    if PlayerChar then
        Humanoid = PlayerChar:FindFirstChildOfClass("Humanoid")
        RootPart = PlayerChar:FindFirstChild("HumanoidRootPart")
        if Humanoid and Humanoid.WalkSpeed < WALK_SPEED then
            Humanoid.WalkSpeed = WALK_SPEED
        end
    end
end

-- // ROUND DETECTION // --
local function isRoundActive()
    local playerGui = LP:FindFirstChild("PlayerGui")
    if playerGui then
        for _, gui in pairs(playerGui:GetChildren()) do
            if gui:IsA("ScreenGui") and (gui.Name:lower():find("lobby") or gui.Name:lower():find("waiting")) then
                if gui.Enabled then return false end
            end
        end
    end
    return (PlayerChar and Humanoid and Humanoid.Health > 0)
end

-- // REAL KILLER DETECTION (filters survivors) // --
local function getNearestKiller()
    if not RootPart then return nil, math.huge end
    local nearest = nil
    local nearestDist = math.huge
    for _, plr in pairs(Players:GetPlayers()) do
        if plr ~= LP and plr.Character then
            local char = plr.Character
            local hrp = char:FindFirstChild("HumanoidRootPart")
            if hrp then
                -- Check if this player is a killer
                local isKiller = false
                -- 1. Team check
                if plr.Team and plr.Team.Name:lower():find("killer") then
                    isKiller = true
                end
                -- 2. Name check (killers have specific names)
                if not isKiller then
                    local name = plr.Name:lower()
                    for _, kname in pairs(KILLER_NAMES) do
                        if name:find(kname) then
                            isKiller = true
                            break
                        end
                    end
                end
                -- 3. Attribute or tag
                if not isKiller then
                    if char:FindFirstChild("KillerTag") or char:GetAttribute("IsKiller") then
                        isKiller = true
                    end
                end
                if isKiller then
                    local d = (RootPart.Position - hrp.Position).magnitude
                    if d < nearestDist then
                        nearestDist = d
                        nearest = hrp
                    end
                end
            end
        end
    end
    return nearest, nearestDist
end

-- // GENERATOR SCANNING (only parts with ProximityPrompt) // --
local function scanGenerators()
    local newGens = {}
    for _, prompt in pairs(workspace:GetDescendants()) do
        if prompt:IsA("ProximityPrompt") and prompt.Parent then
            local part = prompt.Parent:IsA("BasePart") and prompt.Parent or prompt.Parent:FindFirstChildWhichIsA("BasePart")
            if part and not table.find(CompletedGenerators, part) then
                table.insert(newGens, part)
            end
        end
    end
    -- Also include ClickDetectors if they have parent part
    for _, detector in pairs(workspace:GetDescendants()) do
        if detector:IsA("ClickDetector") and detector.Parent and detector.Parent:IsA("BasePart") then
            local part = detector.Parent
            if not table.find(newGens, part) and not table.find(CompletedGenerators, part) then
                table.insert(newGens, part)
            end
        end
    end
    Generators = newGens
    updateDebug(string.format("Scanned %d generators (only with ProximityPrompt/ClickDetector)", #Generators))
    return #Generators
end

-- // FLEE WITH WALL AVOIDANCE // --
local function getSafeFleePosition(killerPos)
    if not RootPart then return nil end
    local awayDir = (RootPart.Position - killerPos).unit
    -- Try multiple angles (0°, ±45°, ±90°)
    local angles = {0, 45, -45, 90, -90}
    for _, angle in ipairs(angles) do
        local rad = math.rad(angle)
        local dir = Vector3.new(
            awayDir.X * math.cos(rad) - awayDir.Z * math.sin(rad),
            0,
            awayDir.X * math.sin(rad) + awayDir.Z * math.cos(rad)
        ).unit
        local testPos = RootPart.Position + dir * 25
        testPos = Vector3.new(math.clamp(testPos.X, -500, 500), testPos.Y, math.clamp(testPos.Z, -500, 500))
        -- Raycast to see if there's a wall between current position and testPos
        local ray = Ray.new(RootPart.Position, (testPos - RootPart.Position).unit * 25)
        local hit = workspace:FindPartOnRay(ray, PlayerChar)
        if not hit then
            return testPos  -- clear path
        end
    end
    -- Fallback: just move away in original direction
    return RootPart.Position + awayDir * 25
end

-- // MINIGAME SOLVER (based on your UI numbers) // --
local function solveMinigame()
    local minigameFrame = nil
    for i = 1, 30 do
        task.wait(0.2)
        local playerGui = LP:FindFirstChild("PlayerGui")
        if playerGui then
            for _, gui in pairs(playerGui:GetDescendants()) do
                if gui:IsA("Frame") and (gui.Name:lower():find("repair") or gui.Name:lower():find("generator")) then
                    minigameFrame = gui
                    break
                end
            end
        end
        if minigameFrame then break end
    end
    if not minigameFrame then
        updateDebug("Minigame UI not found")
        return false
    end

    -- Find all buttons with numbers
    local dots = {}
    for _, child in pairs(minigameFrame:GetDescendants()) do
        if (child:IsA("TextButton") or child:IsA("ImageButton")) and child.Visible then
            local num = tonumber(child.Text)
            if num then
                table.insert(dots, {
                    obj = child,
                    number = num,
                    color = child.BackgroundColor3,
                    position = child.AbsolutePosition
                })
            end
        end
    end
    if #dots < 2 then
        updateDebug("Not enough dots found")
        return false
    end

    -- Group by color, then sort by number
    local colorGroups = {}
    for _, dot in pairs(dots) do
        local key = tostring(dot.color)
        if not colorGroups[key] then colorGroups[key] = {} end
        table.insert(colorGroups[key], dot)
    end

    for _, group in pairs(colorGroups) do
        table.sort(group, function(a,b) return a.number < b.number end)
        for i = 1, #group - 1 do
            local start = group[i]
            local target = group[i+1]
            if start.number == target.number then
                local startPos = start.obj.AbsolutePosition + Vector2.new(start.obj.AbsoluteSize.X/2, start.obj.AbsoluteSize.Y/2)
                local targetPos = target.obj.AbsolutePosition + Vector2.new(target.obj.AbsoluteSize.X/2, target.obj.AbsoluteSize.Y/2)
                pcall(function()
                    VirtualInput:SendMouseButtonEvent(startPos.X, startPos.Y, 0, true, game, 0)
                    task.wait(0.05)
                    for t = 0, 1, 0.1 do
                        local x = startPos.X + (targetPos.X - startPos.X) * t
                        local y = startPos.Y + (targetPos.Y - startPos.Y) * t
                        VirtualInput:SendMouseMoveEvent(x, y, game, 0)
                        task.wait(0.02)
                    end
                    VirtualInput:SendMouseButtonEvent(targetPos.X, targetPos.Y, 0, false, game, 0)
                end)
                task.wait(0.2)
            end
        end
    end
    return true
end

-- // INTERACT WITH GENERATOR (screen click + hold) // --
local function interactWithGenerator(gen)
    updateDebug("Interacting with generator: " .. gen.Name)
    -- Try ProximityPrompt first
    local prompt = gen:FindFirstChildWhichIsA("ProximityPrompt")
    if prompt then
        pcall(function()
            VirtualInput:SendKeyEvent(true, Enum.KeyCode.F, false, game)
            task.wait(0.5)
            VirtualInput:SendKeyEvent(false, Enum.KeyCode.F, false, game)
        end)
        -- Wait for minigame UI
        for i = 1, 30 do
            task.wait(0.1)
            local playerGui = LP:FindFirstChild("PlayerGui")
            if playerGui then
                for _, gui in pairs(playerGui:GetDescendants()) do
                    if gui:IsA("Frame") and (gui.Name:lower():find("repair") or gui.Name:lower():find("generator")) then
                        updateDebug("Minigame opened via ProximityPrompt")
                        local solved = solveMinigame()
                        if solved then
                            table.insert(CompletedGenerators, gen)
                            for i, g in pairs(Generators) do
                                if g == gen then table.remove(Generators, i) break end
                            end
                            return true
                        end
                    end
                end
            end
        end
        return false
    end
    
    -- No ProximityPrompt → use ClickDetector via screen click
    local click = gen:FindFirstChildWhichIsA("ClickDetector")
    if click and RootPart then
        -- Get screen position of the generator part
        local screenPos, onScreen = workspace.CurrentCamera:WorldToScreenPoint(gen.Position)
        if onScreen then
            pcall(function()
                VirtualInput:SendMouseButtonEvent(screenPos.X, screenPos.Y, 0, true, game, 0)
                task.wait(0.3)
                VirtualInput:SendMouseButtonEvent(screenPos.X, screenPos.Y, 0, false, game, 0)
            end)
            updateDebug("Clicked generator at screen position")
            -- Wait for minigame UI
            for i = 1, 30 do
                task.wait(0.2)
                local playerGui = LP:FindFirstChild("PlayerGui")
                if playerGui then
                    for _, gui in pairs(playerGui:GetDescendants()) do
                        if gui:IsA("Frame") and (gui.Name:lower():find("repair") or gui.Name:lower():find("generator")) then
                            updateDebug("Minigame opened via click")
                            local solved = solveMinigame()
                            if solved then
                                table.insert(CompletedGenerators, gen)
                                for i, g in pairs(Generators) do
                                    if g == gen then table.remove(Generators, i) break end
                                end
                                return true
                            end
                        end
                    end
                end
            end
        else
            updateDebug("Generator not on screen")
        end
    else
        updateDebug("No interaction method found")
    end
    return false
end

-- // MAIN AI LOOP // --
local function aiTick()
    if not AIEnabled or not ScriptActive then return end
    if not PlayerChar or not Humanoid or not RootPart then
        updateChar()
        return
    end
    RoundActive = isRoundActive()
    if not RoundActive then
        CurrentAction = "Waiting for round"
        return
    end

    -- Killer detection (only real killers)
    local killerObj, killerDist = getNearestKiller()
    if killerObj and killerDist <= SliderValue then
        CurrentAction = string.format("Fleeing (killer %.0f studs)", killerDist)
        local now = tick()
        if now - LastFleeTime > 0.8 then
            LastFleeTime = now
            local fleePos = getSafeFleePosition(killerObj.Position)
            if fleePos then
                Humanoid:MoveTo(fleePos)
            end
        end
        return
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
        if nearestDist > 5 then
            CurrentAction = string.format("Moving to generator (%.0f studs)", nearestDist)
            Humanoid:MoveTo(nearestGen.Position)
        else
            CurrentAction = "Interacting"
            interactWithGenerator(nearestGen)
            task.wait(0.5)
        end
    end
end

-- // INFINITE STAMINA // --
local function applyStamina()
    if not Humanoid then return end
    if Humanoid.WalkSpeed < WALK_SPEED then Humanoid.WalkSpeed = WALK_SPEED end
    local staminaProp = Humanoid:FindFirstChild("Stamina")
    if staminaProp and staminaProp:IsA("NumberValue") then
        setreadonly(staminaProp, false)
        staminaProp.Value = 100
        setreadonly(staminaProp, true)
    end
    Humanoid:SetAttribute("Sprinting", true)
    for _, effect in pairs(game:GetService("Lighting"):GetChildren()) do
        if effect:IsA("BlurEffect") then effect.Enabled = false end
    end
end

-- // BACKGROUND LOOPS // --
task.spawn(function()
    while ScriptActive do
        task.wait(0.5)
        aiTick()
    end
end)

task.spawn(function()
    while ScriptActive do
        task.wait(0.5)
        if AIEnabled then applyStamina() end
    end
end)

task.spawn(function()
    while ScriptActive do
        task.wait(6)
        if AIEnabled then scanGenerators() end
    end
end)

-- // DEBUG STATUS UPDATER // --
task.spawn(function()
    while ScriptActive do
        task.wait(1)
        if AIEnabled then
            local _, kd = getNearestKiller()
            updateDebug(string.format("Gens: %d (done %d) | Killer: %.0f | Action: %s", #Generators, #CompletedGenerators, kd, CurrentAction))
        end
    end
end)

-- // GUI HUB // --
local function createHub()
    local sg = Instance.new("ScreenGui")
    sg.Name = "ForsakenAIFinalFixed"
    sg.Parent = game.CoreGui
    sg.ResetOnSpawn = false

    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, 380, 0, 330)
    frame.Position = UDim2.new(0.5, -190, 0.5, -165)
    frame.BackgroundColor3 = Color3.fromRGB(10,10,20)
    frame.BackgroundTransparency = 0.2
    frame.Parent = sg
    Instance.new("UICorner").CornerRadius = UDim.new(0,12)

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1,0,0,35)
    title.BackgroundTransparency = 1
    title.Text = "🔪 FORSAKEN AI (FINAL FIXES) 🔪"
    title.TextColor3 = Color3.fromRGB(0,200,255)
    title.Font = Enum.Font.GothamBold
    title.TextSize = 15
    title.Parent = frame

    local toggle = Instance.new("TextButton")
    toggle.Size = UDim2.new(0, 200, 0, 45)
    toggle.Position = UDim2.new(0.5, -100, 0, 50)
    toggle.BackgroundColor3 = Color3.fromRGB(0,120,200)
    toggle.Text = "🔴 AI OFF"
    toggle.TextColor3 = Color3.new(1,1,1)
    toggle.Font = Enum.Font.GothamBold
    toggle.TextSize = 18
    toggle.Parent = frame
    Instance.new("UICorner").CornerRadius = UDim.new(0,8)

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
    sliderLabel.TextColor3 = Color3.fromRGB(255,180,180)
    sliderLabel.Font = Enum.Font.Gotham
    sliderLabel.TextSize = 12
    sliderLabel.Parent = sliderFrame

    local sliderBg = Instance.new("Frame")
    sliderBg.Size = UDim2.new(0, 220, 0, 6)
    sliderBg.Position = UDim2.new(0, 0, 0, 22)
    sliderBg.BackgroundColor3 = Color3.fromRGB(50,50,70)
    sliderBg.BorderSizePixel = 0
    sliderBg.Parent = sliderFrame
    local fill = Instance.new("Frame")
    fill.Size = UDim2.new(0.4,0,1,0)
    fill.BackgroundColor3 = Color3.fromRGB(255,80,120)
    fill.BorderSizePixel = 0
    fill.Parent = sliderBg
    local knob = Instance.new("TextButton")
    knob.Size = UDim2.new(0,14,0,14)
    knob.Position = UDim2.new(0.4,-7,0,-4)
    knob.BackgroundColor3 = Color3.new(1,1,1)
    knob.Text = ""
    knob.AutoButtonColor = false
    knob.Parent = sliderFrame
    Instance.new("UICorner").CornerRadius = UDim.new(1,0)

    local function setSlider(val)
        val = math.clamp(val, 0, 100)
        SliderValue = val
        fill.Size = UDim2.new(val/100,0,1,0)
        knob.Position = UDim2.new(val/100,-7,0,-4)
        sliderLabel.Text = "Killer Alert Radius: " .. math.floor(val)
    end
    setSlider(40)

    knob.InputBegan:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 then
            local move, rel
            move = UserInputService.InputChanged:Connect(function(io)
                if io.UserInputType == Enum.UserInputType.MouseMovement then
                    local x = math.clamp(io.Position.X - sliderBg.AbsolutePosition.X, 0, sliderBg.AbsoluteSize.X)
                    setSlider(math.floor((x/sliderBg.AbsoluteSize.X)*100))
                end
            end)
            rel = UserInputService.InputEnded:Connect(function(io)
                if io.UserInputType == Enum.UserInputType.MouseButton1 then
                    move:Disconnect(); rel:Disconnect()
                end
            end)
        end
    end)

    local status = Instance.new("TextLabel")
    status.Size = UDim2.new(1, -20, 0, 35)
    status.Position = UDim2.new(0, 10, 0, 180)
    status.BackgroundTransparency = 1
    status.Text = "Ready"
    status.TextColor3 = Color3.fromRGB(200,200,230)
    status.Font = Enum.Font.Gotham
    status.TextSize = 12
    status.TextXAlignment = Enum.TextXAlignment.Left
    status.Parent = frame

    local hideBtn = Instance.new("TextButton")
    hideBtn.Size = UDim2.new(0, 90, 0, 35)
    hideBtn.Position = UDim2.new(0.05, 0, 0, 235)
    hideBtn.BackgroundColor3 = Color3.fromRGB(80,80,100)
    hideBtn.Text = "⛔ HIDE"
    hideBtn.TextColor3 = Color3.new(1,1,1)
    hideBtn.Font = Enum.Font.GothamBold
    hideBtn.TextSize = 13
    hideBtn.Parent = frame
    Instance.new("UICorner").CornerRadius = UDim.new(0,6)

    local rejoinBtn = Instance.new("TextButton")
    rejoinBtn.Size = UDim2.new(0, 90, 0, 35)
    rejoinBtn.Position = UDim2.new(0.35, 0, 0, 235)
    rejoinBtn.BackgroundColor3 = Color3.fromRGB(100,80,120)
    rejoinBtn.Text = "🔄 REJOIN"
    rejoinBtn.TextColor3 = Color3.new(1,1,1)
    rejoinBtn.Font = Enum.Font.GothamBold
    rejoinBtn.TextSize = 13
    rejoinBtn.Parent = frame
    Instance.new("UICorner").CornerRadius = UDim.new(0,6)

    local closeBtn = Instance.new("TextButton")
    closeBtn.Size = UDim2.new(0, 90, 0, 35)
    closeBtn.Position = UDim2.new(0.65, 0, 0, 235)
    closeBtn.BackgroundColor3 = Color3.fromRGB(180,40,60)
    closeBtn.Text = "❌ CLOSE"
    closeBtn.TextColor3 = Color3.new(1,1,1)
    closeBtn.Font = Enum.Font.GothamBold
    closeBtn.TextSize = 13
    closeBtn.Parent = frame
    Instance.new("UICorner").CornerRadius = UDim.new(0,6)

    local showBtn = nil
    hideBtn.MouseButton1Click:Connect(function()
        frame.Visible = false
        if not showBtn then
            showBtn = Instance.new("TextButton")
            showBtn.Size = UDim2.new(0, 90, 0, 30)
            showBtn.Position = UDim2.new(0.02, 0, 0.9, 0)
            showBtn.BackgroundColor3 = Color3.fromRGB(0,180,200)
            showBtn.Text = "🔽 SHOW"
            showBtn.TextColor3 = Color3.new(1,1,1)
            showBtn.Font = Enum.Font.GothamBold
            showBtn.TextSize = 12
            showBtn.Parent = sg
            Instance.new("UICorner").CornerRadius = UDim.new(0,8)
            showBtn.MouseButton1Click:Connect(function()
                frame.Visible = true
                showBtn:Destroy()
                showBtn = nil
            end)
        end
    end)

    rejoinBtn.MouseButton1Click:Connect(function()
        local TeleportService = game:GetService("TeleportService")
        TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LP)
    end)

    closeBtn.MouseButton1Click:Connect(function()
        AIEnabled = false
        ScriptActive = false
        sg:Destroy()
        if DebugLabel and DebugLabel.Parent and DebugLabel.Parent.Parent then
            DebugLabel.Parent.Parent:Destroy()
        end
    end)

    toggle.MouseButton1Click:Connect(function()
        AIEnabled = not AIEnabled
        if AIEnabled then
            toggle.Text = "🟢 AI ON"
            toggle.BackgroundColor3 = Color3.fromRGB(0,180,80)
            updateChar()
            scanGenerators()
            updateDebug("AI enabled – final fixes active")
        else
            toggle.Text = "🔴 AI OFF"
            toggle.BackgroundColor3 = Color3.fromRGB(0,120,200)
            updateDebug("AI disabled")
        end
    end)

    -- Status updater for GUI
    task.spawn(function()
        while ScriptActive and sg do
            task.wait(1)
            if AIEnabled then
                local _, kd = getNearestKiller()
                status.Text = string.format("Gens: %d (done %d) | Killer: %.0f | Alert: %d", #Generators, #CompletedGenerators, kd, SliderValue)
            else
                status.Text = "AI OFF"
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
createOverlay()
updateChar()
LP.CharacterAdded:Connect(function()
    task.wait(0.5)
    updateChar()
    if AIEnabled then scanGenerators() end
end)
createHub()
updateDebug("Final fixes loaded: real killers only, screen-click generators, wall-aware flee.")
