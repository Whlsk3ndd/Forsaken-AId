--[[
    FORSAKEN AI – FINAL RELIABLE VERSION
    - Only real generators (name contains "Generator")
    - Killer detection by name/team (fallback any player)
    - Simple straight movement (no wall avoidance to prevent freeze)
    - Minigame solver clicks all buttons in order
--]]

-- // SERVICES // --
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local VirtualInput = game:GetService("VirtualInput")
local LP = Players.LocalPlayer

-- // STATE // --
local AIEnabled = false
local ScriptActive = true
local SliderValue = 40
local PlayerChar, Humanoid, RootPart
local Generators = {}
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
    frame.Size = UDim2.new(0, 400, 0, 90)
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
    return sg
end

local debugSG = createOverlay()
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

-- // LOBBY DETECTION // --
local function isRoundActive()
    local playerGui = LP:FindFirstChild("PlayerGui")
    if playerGui then
        for _, label in pairs(playerGui:GetDescendants()) do
            if label:IsA("TextLabel") and label.Text:find("Round begins") then
                return true
            end
        end
    end
    return (PlayerChar and Humanoid and Humanoid.Health > 0)
end

-- // KILLER DETECTION (prioritize real killers) // --
local function getNearestKiller()
    if not RootPart then return nil, math.huge end
    local nearest = nil
    local nearestDist = math.huge
    local anyPlayerDist = math.huge
    local anyPlayer = nil

    for _, plr in pairs(Players:GetPlayers()) do
        if plr ~= LP and plr.Character then
            local hrp = plr.Character:FindFirstChild("HumanoidRootPart")
            if hrp then
                local dist = (RootPart.Position - hrp.Position).magnitude
                -- Keep track of any other player as fallback
                if dist < anyPlayerDist then
                    anyPlayerDist = dist
                    anyPlayer = hrp
                end
                -- Check if this is a killer
                local isKiller = false
                if plr.Team and plr.Team.Name:lower():find("killer") then isKiller = true end
                if not isKiller and plr.Name:lower():find("killer") then isKiller = true end
                if not isKiller and plr.Character:FindFirstChild("KillerTag") then isKiller = true end
                if isKiller and dist < nearestDist then
                    nearestDist = dist
                    nearest = hrp
                end
            end
        end
    end
    -- If no killer found, fallback to any other player (so you at least run from survivors)
    if not nearest and anyPlayer then
        return anyPlayer, anyPlayerDist
    end
    return nearest, nearestDist
end

-- // GENERATOR SCANNING (only parts with "Generator" in name or parent name) // --
local function scanGenerators()
    local newGens = {}
    for _, prompt in pairs(workspace:GetDescendants()) do
        if prompt:IsA("ProximityPrompt") and prompt.Parent then
            local part = prompt.Parent:IsA("BasePart") and prompt.Parent or prompt.Parent:FindFirstChildWhichIsA("BasePart")
            if part then
                local name = part.Name:lower()
                local parentName = part.Parent and part.Parent.Name:lower() or ""
                if (name:find("generator") or parentName:find("generator")) and not table.find(CompletedGenerators, part) then
                    table.insert(newGens, part)
                end
            end
        end
    end
    Generators = newGens
    updateDebug(string.format("Found %d real generators", #Generators))
    return #Generators
end

-- // MINIGAME SOLVER (clicks every button in the minigame frame) // --
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

    -- Collect all clickable elements (ImageButton, TextButton)
    local clickables = {}
    for _, child in pairs(minigameFrame:GetDescendants()) do
        if (child:IsA("ImageButton") or child:IsA("TextButton")) and child.Visible then
            table.insert(clickables, child)
        end
    end
    if #clickables == 0 then
        updateDebug("No clickables found in minigame")
        return false
    end

    -- Sort by position (left to right, then top to bottom)
    table.sort(clickables, function(a,b)
        if math.abs(a.AbsolutePosition.Y - b.AbsolutePosition.Y) < 50 then
            return a.AbsolutePosition.X < b.AbsolutePosition.X
        else
            return a.AbsolutePosition.Y < b.AbsolutePosition.Y
        end
    end)

    -- Click each button in sequence
    for _, btn in ipairs(clickables) do
        local pos = btn.AbsolutePosition + Vector2.new(btn.AbsoluteSize.X/2, btn.AbsoluteSize.Y/2)
        pcall(function()
            VirtualInput:SendMouseButtonEvent(pos.X, pos.Y, 0, true, game, 0)
            task.wait(0.05)
            VirtualInput:SendMouseButtonEvent(pos.X, pos.Y, 0, false, game, 0)
        end)
        task.wait(0.1)
    end
    updateDebug("Minigame solved (" .. #clickables .. " buttons clicked)")
    return true
end

-- // INTERACT WITH GENERATOR (hold F until minigame appears) // --
local function interactWithGenerator(gen)
    updateDebug("Interacting with generator: " .. gen.Name)
    pcall(function()
        VirtualInput:SendKeyEvent(true, Enum.KeyCode.F, false, game)
    end)
    local uiOpened = false
    for i = 1, 30 do
        task.wait(0.1)
        local playerGui = LP:FindFirstChild("PlayerGui")
        if playerGui then
            for _, gui in pairs(playerGui:GetDescendants()) do
                if gui:IsA("Frame") and (gui.Name:lower():find("repair") or gui.Name:lower():find("generator")) then
                    uiOpened = true
                    break
                end
            end
        end
        if uiOpened then break end
    end
    pcall(function()
        VirtualInput:SendKeyEvent(false, Enum.KeyCode.F, false, game)
    end)

    if uiOpened then
        updateDebug("Minigame opened – solving")
        local solved = solveMinigame()
        if solved then
            -- Wait for UI to close
            for i = 1, 30 do
                task.wait(0.3)
                local found = false
                local playerGui = LP:FindFirstChild("PlayerGui")
                if playerGui then
                    for _, gui in pairs(playerGui:GetDescendants()) do
                        if gui:IsA("Frame") and (gui.Name:lower():find("repair") or gui.Name:lower():find("generator")) then
                            found = true
                            break
                        end
                    end
                end
                if not found then
                    updateDebug("Generator completed!")
                    table.insert(CompletedGenerators, gen)
                    return true
                end
            end
        end
    else
        updateDebug("Minigame did not open")
    end
    return false
end

-- // SIMPLE MOVE (no wall avoidance, just straight line with timeout) // --
local function moveToPosition(targetPos)
    if not RootPart or not Humanoid then return end
    Humanoid:MoveTo(targetPos)
    -- Wait up to 2 seconds to see if we're stuck
    local start = tick()
    while tick() - start < 2 do
        task.wait(0.2)
        if (RootPart.Position - targetPos).magnitude < 4 then
            break
        end
    end
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
        if CurrentAction ~= "Lobby" then
            CurrentAction = "Lobby"
            updateDebug("In lobby – waiting")
        end
        return
    end

    -- 1. Killer avoidance
    local killerObj, killerDist = getNearestKiller()
    if killerObj and killerDist <= SliderValue then
        CurrentAction = string.format("Fleeing (killer %.0f studs)", killerDist)
        local now = tick()
        if now - LastFleeTime > 0.8 then
            LastFleeTime = now
            local away = (RootPart.Position - killerObj.Position).unit
            local fleePos = RootPart.Position + away * 40
            moveToPosition(fleePos)
        end
        return
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
            CurrentAction = string.format("Moving to generator (%.0f studs)", nearestDist)
            moveToPosition(nearestGen.Position)
        else
            CurrentAction = "Interacting"
            interactWithGenerator(nearestGen)
            task.wait(1)
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
        task.wait(10)
        if AIEnabled then scanGenerators() end
    end
end)

-- // GUI HUB // --
local function createHub()
    local sg = Instance.new("ScreenGui")
    sg.Name = "ForsakenAIFinal"
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
    title.Text = "⚡ FORSAKEN AI (FINAL) ⚡"
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
        if debugSG then debugSG:Destroy() end
        print("AI script fully unloaded.")
    end)

    toggle.MouseButton1Click:Connect(function()
        AIEnabled = not AIEnabled
        if AIEnabled then
            toggle.Text = "🟢 AI ON"
            toggle.BackgroundColor3 = Color3.fromRGB(0,180,80)
            updateChar()
            scanGenerators()
            updateDebug("AI enabled – final reliable version")
        else
            toggle.Text = "🔴 AI OFF"
            toggle.BackgroundColor3 = Color3.fromRGB(0,120,200)
            updateDebug("AI disabled")
        end
    end)

    task.spawn(function()
        while ScriptActive and sg do
            task.wait(2)
            if AIEnabled then
                local _, kd = getNearestKiller()
                status.Text = string.format("Gens: %d | Killer: %.0f studs | Alert: %d", #Generators, kd, SliderValue)
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
updateChar()
LP.CharacterAdded:Connect(function()
    task.wait(0.5)
    updateChar()
    if AIEnabled then scanGenerators() end
end)
createHub()
updateDebug("Final AI loaded. Only generators with 'Generator' in name. Killer detection by name/team (fallback any player).")
