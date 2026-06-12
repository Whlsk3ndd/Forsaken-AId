--[[
    ███████╗ ██████╗ ██████╗ ███████╗ █████╗ ██╗  ██╗███████╗███╗   ██╗
    ██╔════╝██╔═══██╗██╔══██╗██╔════╝██╔══██╗██║ ██╔╝██╔════╝████╗  ██║
    ███████╗██║   ██║██████╔╝█████╗  ███████║█████╔╝ █████╗  ██╔██╗ ██║
    ╚════██║██║   ██║██╔══██╗██╔══╝  ██╔══██║██╔═██╗ ██╔══╝  ██║╚██╗██║
    ███████║╚██████╔╝██║  ██║██║     ██║  ██║██║  ██╗███████╗██║ ╚████║
    ╚══════╝ ╚═════╝ ╚═╝  ╚═╝╚═╝     ╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝╚═╝  ╚═══╝

    ULTIMATE FORSAKEN AI
    + Advanced Debug Logging
    + Rejoin Button
    + Cool Neon GUI
    + Multi-method Generator Interaction (Prompt, Key, Remote)
    + Stamina Module Override
--]]

-- // SERVICES // --
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local VirtualInput = game:GetService("VirtualInput")
local TeleportService = game:GetService("TeleportService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local LP = Players.LocalPlayer

-- // DEBUG LOGGING (enhanced) // --
local function DebugLog(msg, level)
    level = level or "INFO"
    print(string.format("[%s] %s", level, msg))
end

-- // STATE // --
local AIEnabled = false
local ScriptActive = true
local SliderValue = 40
local PlayerChar, Humanoid, RootPart
local Generators = {}
local CompletedGenerators = {}
local CurrentAction = "Idle"
local IsInteracting = false

-- // CONSTANTS // --
local WALK_SPEED = 24

-- // KILLER NAMES // --
local KILLER_NAMES = {
    "slasher", "c00lkidd", "john doe", "1x1x1x1", "noli", "guest 666", "nosferatu",
    "subject 0", "pursuer", "killer kyle", "stitchhare", "mafioso", "bluudud",
    "divadayo", "gasharpoon", "annihilation", "aberrant", "admin romeo", "narrator",
    "apollyon", "photoshop", "azure", "doombringer", "phosphorus"
}

-- // STAMINA MODULE OVERRIDE (from your example) // --
local function overrideStamina()
    local success, sprintModule = pcall(function()
        return require(ReplicatedStorage:WaitForChild("Systems").Character.Game.Sprinting)
    end)
    if success and sprintModule then
        sprintModule.MaxStamina = 100
        sprintModule.MinStamina = -20
        sprintModule.StaminaGain = 100
        sprintModule.StaminaLoss = 5
        sprintModule.SprintSpeed = 40
        sprintModule.StaminaLossDisabled = true
        DebugLog("Stamina module overridden successfully", "SUCCESS")
    else
        DebugLog("Stamina module not found – falling back to walk speed increase", "WARN")
        if Humanoid then Humanoid.WalkSpeed = WALK_SPEED end
    end
end

-- // UPDATE CHARACTER // --
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

-- // KILLER DETECTION // --
local function getNearestKiller()
    if not RootPart then return nil, math.huge end
    local nearestObj = nil
    local nearestDist = math.huge
    for _, plr in pairs(Players:GetPlayers()) do
        if plr ~= LP and plr.Character then
            local char = plr.Character
            local hrp = char:FindFirstChild("HumanoidRootPart")
            if hrp then
                local name = plr.Name:lower()
                local isKiller = false
                for _, k in pairs(KILLER_NAMES) do
                    if name:find(k) then isKiller = true; break end
                end
                if not isKiller and plr.Team and plr.Team.Name:lower():find("killer") then isKiller = true end
                if not isKiller and char:FindFirstChild("KillerTag") then isKiller = true end
                if isKiller then
                    local dist = (RootPart.Position - hrp.Position).magnitude
                    if dist < nearestDist then
                        nearestDist = dist
                        nearestObj = hrp
                    end
                end
            end
        end
    end
    return nearestObj, nearestDist
end

-- // GENERATOR SCANNING // --
local function scanGenerators()
    local newGens = {}
    for _, prompt in pairs(workspace:GetDescendants()) do
        if prompt:IsA("ProximityPrompt") and prompt.Parent then
            local part = prompt.Parent:IsA("BasePart") and prompt.Parent or prompt.Parent:FindFirstChildWhichIsA("BasePart")
            if part and not CompletedGenerators[part] then
                local name = part.Name:lower()
                local parentName = part.Parent and part.Parent.Name:lower() or ""
                if name:find("generator") or parentName:find("generator") then
                    table.insert(newGens, part)
                end
            end
        end
    end
    Generators = newGens
    DebugLog(string.format("Found %d generators", #Generators))
    return #Generators
end

-- // ATTEMPT TO FIND GENERATOR REMOTE EVENT // --
local GeneratorRemote = nil
local function findGeneratorRemote()
    if GeneratorRemote then return true end
    -- Look for common remote names
    local possibleNames = {"Generate", "CompleteGenerator", "FinishGenerator", "GeneratorDone"}
    for _, name in pairs(possibleNames) do
        local remote = ReplicatedStorage:FindFirstChild(name)
        if remote and remote:IsA("RemoteEvent") then
            GeneratorRemote = remote
            DebugLog("Found generator remote: " .. name, "SUCCESS")
            return true
        end
    end
    -- Search deeper
    for _, obj in pairs(ReplicatedStorage:GetDescendants()) do
        if obj:IsA("RemoteEvent") and (obj.Name:lower():find("generator") or obj.Name:lower():find("gen")) then
            GeneratorRemote = obj
            DebugLog("Found generator remote: " .. obj.Name, "SUCCESS")
            return true
        end
    end
    DebugLog("No generator remote found – will use minigame solver", "WARN")
    return false
end

-- // MINIGAME SOLVER (ENHANCED) // --
local function solveMinigame()
    local playerGui = LP:FindFirstChild("PlayerGui")
    if not playerGui then 
        DebugLog("No PlayerGui found", "ERROR")
        return false 
    end
    local minigameFrame = nil
    for _, gui in pairs(playerGui:GetDescendants()) do
        if gui:IsA("Frame") and (gui.Name:lower():find("repair") or gui.Name:lower():find("generator")) then
            minigameFrame = gui
            break
        end
    end
    if not minigameFrame then 
        DebugLog("Minigame frame not found", "ERROR")
        return false 
    end
    DebugLog("Minigame frame found: " .. minigameFrame.Name)

    -- Collect all clickable elements (any object with a number or that looks like a dot)
    local clickables = {}
    for _, child in pairs(minigameFrame:GetDescendants()) do
        if child.Visible then
            if child:IsA("ImageButton") or child:IsA("TextButton") then
                table.insert(clickables, child)
            elseif child:IsA("TextLabel") and tonumber(child.Text) then
                table.insert(clickables, child)
            elseif child:IsA("ImageLabel") and child.Name:match("%d") then
                table.insert(clickables, child)
            end
        end
    end
    if #clickables < 2 then
        DebugLog(string.format("Only %d clickables found (need at least 2)", #clickables), "WARN")
        return false
    end
    DebugLog(string.format("Found %d clickable elements", #clickables))

    -- Sort by position (left to right, top to bottom)
    table.sort(clickables, function(a,b)
        if math.abs(a.AbsolutePosition.Y - b.AbsolutePosition.Y) < 50 then
            return a.AbsolutePosition.X < b.AbsolutePosition.X
        else
            return a.AbsolutePosition.Y < b.AbsolutePosition.Y
        end
    end)

    -- Click each element
    for idx, btn in ipairs(clickables) do
        local pos = btn.AbsolutePosition + Vector2.new(btn.AbsoluteSize.X/2, btn.AbsoluteSize.Y/2)
        local success = pcall(function()
            VirtualInput:SendMouseButtonEvent(pos.X, pos.Y, 0, true, game, 0)
            wait(0.05)
            VirtualInput:SendMouseButtonEvent(pos.X, pos.Y, 0, false, game, 0)
        end)
        if success then
            DebugLog(string.format("Clicked element %d/%d", idx, #clickables))
        else
            DebugLog(string.format("Failed to click element %d", idx), "ERROR")
        end
        wait(0.1)
    end
    return true
end

-- // INTERACT WITH GENERATOR (MULTI-METHOD) // --
local function interactWithGenerator(gen)
    if IsInteracting then 
        DebugLog("Already interacting, skipping", "WARN")
        return false 
    end
    IsInteracting = true
    DebugLog("Starting generator interaction: " .. gen.Name)

    -- Method 1: Try ProximityPrompt:Prompt()
    local prompt = gen:FindFirstChildWhichIsA("ProximityPrompt")
    if prompt then
        DebugLog("Method 1: Using ProximityPrompt:Prompt()")
        pcall(function() prompt:Prompt() end)
        wait(0.5)
        if findGeneratorRemote() and GeneratorRemote then
            DebugLog("Method 1b: Firing generator remote")
            pcall(function() GeneratorRemote:FireServer(gen) end)
        end
    else
        DebugLog("No ProximityPrompt found on generator", "WARN")
    end

    -- Method 2: Hold F key for 2 seconds
    DebugLog("Method 2: Holding F key for 2 seconds")
    pcall(function() VirtualInput:SendKeyEvent(true, Enum.KeyCode.F, false, game) end)
    wait(2)
    pcall(function() VirtualInput:SendKeyEvent(false, Enum.KeyCode.F, false, game) end)

    -- Check if minigame opened
    local uiOpened = false
    for i = 1, 20 do
        wait(0.1)
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

    if uiOpened then
        DebugLog("Minigame UI detected – attempting to solve")
        local solved = solveMinigame()
        if solved then
            -- Wait for UI to close
            for i = 1, 30 do
                wait(0.3)
                local stillOpen = false
                local playerGui = LP:FindFirstChild("PlayerGui")
                if playerGui then
                    for _, gui in pairs(playerGui:GetDescendants()) do
                        if gui:IsA("Frame") and (gui.Name:lower():find("repair") or gui.Name:lower():find("generator")) then
                            stillOpen = true
                            break
                        end
                    end
                end
                if not stillOpen then
                    DebugLog("Generator completed successfully!", "SUCCESS")
                    CompletedGenerators[gen] = true
                    IsInteracting = false
                    return true
                end
            end
            DebugLog("Minigame UI did not close after solving", "WARN")
        else
            DebugLog("Minigame solver failed – no clickable elements", "ERROR")
        end
    else
        DebugLog("Minigame UI did not open after F key hold", "ERROR")
        -- Method 3: Try clicking the generator part directly as last resort
        DebugLog("Method 3: Attempting to click generator part")
        local screenPos, onScreen = workspace.CurrentCamera:WorldToScreenPoint(gen.Position)
        if onScreen then
            pcall(function()
                VirtualInput:SendMouseButtonEvent(screenPos.X, screenPos.Y, 0, true, game, 0)
                wait(0.2)
                VirtualInput:SendMouseButtonEvent(screenPos.X, screenPos.Y, 0, false, game, 0)
            end)
            DebugLog("Mouse click sent to generator part")
        else
            DebugLog("Generator part not on screen", "WARN")
        end
    end

    IsInteracting = false
    DebugLog("Generator interaction completed – no success", "ERROR")
    return false
end

-- // SIMPLE MOVEMENT // --
local function moveToGenerator(gen)
    if not RootPart or not Humanoid then return end
    Humanoid:MoveTo(gen.Position)
end

-- // FLEE // --
local function fleeFromKiller(killerPos)
    if not RootPart or not Humanoid then return end
    local direction = (RootPart.Position - killerPos).unit
    local fleePos = RootPart.Position + direction * 40
    fleePos = Vector3.new(math.clamp(fleePos.X, -500, 500), fleePos.Y, math.clamp(fleePos.Z, -500, 500))
    Humanoid:MoveTo(fleePos)
end

-- // MAIN AI LOOP // --
local function aiTick()
    if not AIEnabled then return end
    if not PlayerChar or not Humanoid or not RootPart then
        updateChar()
        return
    end

    -- 1. Killer avoidance
    local killerObj, killerDist = getNearestKiller()
    if killerObj and killerDist <= SliderValue then
        CurrentAction = "Fleeing"
        fleeFromKiller(killerObj.Position)
        wait(0.5)
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
            CurrentAction = "Moving to generator"
            moveToGenerator(nearestGen)
        else
            CurrentAction = "Repairing"
            local success = interactWithGenerator(nearestGen)
            if success then
                for i, g in pairs(Generators) do
                    if g == nearestGen then table.remove(Generators, i); break end
                end
            end
            wait(1)
        end
    end
end

-- // BACKGROUND LOOPS // --
spawn(function()
    while ScriptActive do
        wait(0.5)
        aiTick()
    end
end)

spawn(function()
    wait(2) -- wait for character
    overrideStamina()
end)

spawn(function()
    while ScriptActive do
        wait(5)
        if AIEnabled then scanGenerators() end
    end
end)

-- // COOL NEON GUI // --
local function createHub()
    local sg = Instance.new("ScreenGui")
    sg.Name = "ForsakenAI_Neon"
    sg.Parent = game.CoreGui
    sg.ResetOnSpawn = false

    -- Shadow effect
    local shadow = Instance.new("Frame")
    shadow.Size = UDim2.new(0, 340, 0, 300)
    shadow.Position = UDim2.new(0.5, -170, 0.5, -150)
    shadow.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    shadow.BackgroundTransparency = 0.6
    shadow.BorderSizePixel = 0
    shadow.Parent = sg
    Instance.new("UICorner").CornerRadius = UDim.new(0, 16)

    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, 330, 0, 290)
    frame.Position = UDim2.new(0.5, -165, 0.5, -145)
    frame.BackgroundColor3 = Color3.fromRGB(5, 5, 20)
    frame.BackgroundTransparency = 0.1
    frame.BorderSizePixel = 0
    frame.Parent = sg
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 14)
    corner.Parent = frame

    local glow = Instance.new("UIStroke")
    glow.Color = Color3.fromRGB(0, 255, 200)
    glow.Thickness = 2
    glow.Transparency = 0.3
    glow.Parent = frame

    local gradient = Instance.new("UIGradient")
    gradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(15, 15, 35)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(5, 5, 20))
    })
    gradient.Parent = frame

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, 0, 0, 40)
    title.BackgroundTransparency = 1
    title.Text = "⚡ FORSAKEN AI ⚡"
    title.TextColor3 = Color3.fromRGB(0, 255, 200)
    title.Font = Enum.Font.GothamBold
    title.TextSize = 18
    title.Parent = frame

    local toggle = Instance.new("TextButton")
    toggle.Size = UDim2.new(0, 200, 0, 45)
    toggle.Position = UDim2.new(0.5, -100, 0, 55)
    toggle.BackgroundColor3 = Color3.fromRGB(0, 100, 180)
    toggle.Text = "🔴 AI OFF"
    toggle.TextColor3 = Color3.new(1, 1, 1)
    toggle.Font = Enum.Font.GothamBold
    toggle.TextSize = 18
    toggle.Parent = frame
    local btnCorner = Instance.new("UICorner")
    btnCorner.CornerRadius = UDim.new(0, 8)
    btnCorner.Parent = toggle
    -- Button hover animation
    toggle.MouseEnter:Connect(function()
        TweenService:Create(toggle, TweenInfo.new(0.2), {BackgroundColor3 = Color3.fromRGB(0, 140, 220)}):Play()
    end)
    toggle.MouseLeave:Connect(function()
        TweenService:Create(toggle, TweenInfo.new(0.2), {BackgroundColor3 = Color3.fromRGB(0, 100, 180)}):Play()
    end)

    -- Slider
    local sliderFrame = Instance.new("Frame")
    sliderFrame.Size = UDim2.new(0, 260, 0, 50)
    sliderFrame.Position = UDim2.new(0.5, -130, 0, 115)
    sliderFrame.BackgroundTransparency = 1
    sliderFrame.Parent = frame

    local sliderLabel = Instance.new("TextLabel")
    sliderLabel.Size = UDim2.new(0, 140, 0, 20)
    sliderLabel.Position = UDim2.new(0, 0, 0, 0)
    sliderLabel.BackgroundTransparency = 1
    sliderLabel.Text = "Killer Alert: 40"
    sliderLabel.TextColor3 = Color3.fromRGB(255, 180, 180)
    sliderLabel.Font = Enum.Font.Gotham
    sliderLabel.TextSize = 12
    sliderLabel.Parent = sliderFrame

    local sliderBg = Instance.new("Frame")
    sliderBg.Size = UDim2.new(0, 200, 0, 6)
    sliderBg.Position = UDim2.new(0, 0, 0, 22)
    sliderBg.BackgroundColor3 = Color3.fromRGB(50, 50, 70)
    sliderBg.BorderSizePixel = 0
    sliderBg.Parent = sliderFrame
    local fill = Instance.new("Frame")
    fill.Size = UDim2.new(0.4, 0, 1, 0)
    fill.BackgroundColor3 = Color3.fromRGB(0, 200, 255)
    fill.BorderSizePixel = 0
    fill.Parent = sliderBg
    local knob = Instance.new("TextButton")
    knob.Size = UDim2.new(0, 14, 0, 14)
    knob.Position = UDim2.new(0.4, -7, 0, -4)
    knob.BackgroundColor3 = Color3.new(1, 1, 1)
    knob.Text = ""
    knob.AutoButtonColor = false
    knob.Parent = sliderFrame
    local knobCorner = Instance.new("UICorner")
    knobCorner.CornerRadius = UDim.new(1, 0)
    knobCorner.Parent = knob

    local function setSlider(val)
        val = math.clamp(val, 0, 100)
        SliderValue = val
        fill.Size = UDim2.new(val / 100, 0, 1, 0)
        knob.Position = UDim2.new(val / 100, -7, 0, -4)
        sliderLabel.Text = "Killer Alert: " .. math.floor(val)
    end
    setSlider(40)

    knob.InputBegan:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 then
            local move, rel
            move = UserInputService.InputChanged:Connect(function(io)
                if io.UserInputType == Enum.UserInputType.MouseMovement then
                    local x = math.clamp(io.Position.X - sliderBg.AbsolutePosition.X, 0, sliderBg.AbsoluteSize.X)
                    setSlider(math.floor((x / sliderBg.AbsoluteSize.X) * 100))
                end
            end)
            rel = UserInputService.InputEnded:Connect(function(io)
                if io.UserInputType == Enum.UserInputType.MouseButton1 then
                    move:Disconnect()
                    rel:Disconnect()
                end
            end)
        end
    end)

    local status = Instance.new("TextLabel")
    status.Size = UDim2.new(1, -20, 0, 35)
    status.Position = UDim2.new(0, 10, 0, 180)
    status.BackgroundTransparency = 1
    status.Text = "Ready"
    status.TextColor3 = Color3.fromRGB(200, 200, 230)
    status.Font = Enum.Font.Gotham
    status.TextSize = 12
    status.TextXAlignment = Enum.TextXAlignment.Left
    status.Parent = frame

    local actionLabel = Instance.new("TextLabel")
    actionLabel.Size = UDim2.new(1, -20, 0, 20)
    actionLabel.Position = UDim2.new(0, 10, 0, 215)
    actionLabel.BackgroundTransparency = 1
    actionLabel.Text = "Action: Idle"
    actionLabel.TextColor3 = Color3.fromRGB(150, 150, 200)
    actionLabel.Font = Enum.Font.Gotham
    actionLabel.TextSize = 11
    actionLabel.TextXAlignment = Enum.TextXAlignment.Left
    actionLabel.Parent = frame

    -- Buttons row
    local hideBtn = Instance.new("TextButton")
    hideBtn.Size = UDim2.new(0, 90, 0, 35)
    hideBtn.Position = UDim2.new(0.05, 0, 0, 245)
    hideBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 90)
    hideBtn.Text = "⛔ HIDE"
    hideBtn.TextColor3 = Color3.new(1, 1, 1)
    hideBtn.Font = Enum.Font.GothamBold
    hideBtn.TextSize = 13
    hideBtn.Parent = frame
    Instance.new("UICorner").CornerRadius = UDim.new(0, 6)

    local rejoinBtn = Instance.new("TextButton")
    rejoinBtn.Size = UDim2.new(0, 90, 0, 35)
    rejoinBtn.Position = UDim2.new(0.35, 0, 0, 245)
    rejoinBtn.BackgroundColor3 = Color3.fromRGB(100, 70, 120)
    rejoinBtn.Text = "🔄 REJOIN"
    rejoinBtn.TextColor3 = Color3.new(1, 1, 1)
    rejoinBtn.Font = Enum.Font.GothamBold
    rejoinBtn.TextSize = 13
    rejoinBtn.Parent = frame
    Instance.new("UICorner").CornerRadius = UDim.new(0, 6)

    local closeBtn = Instance.new("TextButton")
    closeBtn.Size = UDim2.new(0, 90, 0, 35)
    closeBtn.Position = UDim2.new(0.65, 0, 0, 245)
    closeBtn.BackgroundColor3 = Color3.fromRGB(180, 50, 70)
    closeBtn.Text = "❌ CLOSE"
    closeBtn.TextColor3 = Color3.new(1, 1, 1)
    closeBtn.Font = Enum.Font.GothamBold
    closeBtn.TextSize = 13
    closeBtn.Parent = frame
    Instance.new("UICorner").CornerRadius = UDim.new(0, 6)

    local showBtn = nil
    hideBtn.MouseButton1Click:Connect(function()
        frame.Visible = false
        shadow.Visible = false
        if not showBtn then
            showBtn = Instance.new("TextButton")
            showBtn.Size = UDim2.new(0, 90, 0, 30)
            showBtn.Position = UDim2.new(0.02, 0, 0.9, 0)
            showBtn.BackgroundColor3 = Color3.fromRGB(0, 180, 200)
            showBtn.Text = "🔽 SHOW"
            showBtn.TextColor3 = Color3.new(1, 1, 1)
            showBtn.Font = Enum.Font.GothamBold
            showBtn.TextSize = 12
            showBtn.Parent = sg
            Instance.new("UICorner").CornerRadius = UDim.new(0, 8)
            showBtn.MouseButton1Click:Connect(function()
                frame.Visible = true
                shadow.Visible = true
                showBtn:Destroy()
                showBtn = nil
            end)
        end
    end)

    rejoinBtn.MouseButton1Click:Connect(function()
        DebugLog("Rejoining server...")
        TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LP)
    end)

    closeBtn.MouseButton1Click:Connect(function()
        AIEnabled = false
        ScriptActive = false
        sg:Destroy()
        DebugLog("AI script closed.", "INFO")
    end)

    toggle.MouseButton1Click:Connect(function()
        AIEnabled = not AIEnabled
        if AIEnabled then
            toggle.Text = "🟢 AI ON"
            toggle.BackgroundColor3 = Color3.fromRGB(0, 180, 80)
            updateChar()
            scanGenerators()
            findGeneratorRemote()
            status.Text = "AI ACTIVE"
            DebugLog("AI enabled", "SUCCESS")
        else
            toggle.Text = "🔴 AI OFF"
            toggle.BackgroundColor3 = Color3.fromRGB(0, 100, 180)
            status.Text = "AI OFF"
            DebugLog("AI disabled", "INFO")
        end
    end)

    -- Status updater
    spawn(function()
        while ScriptActive and sg do
            wait(1)
            if AIEnabled then
                local _, kd = getNearestKiller()
                status.Text = string.format("Gens: %d | Killer: %.0f studs | Alert: %d", #Generators, kd, SliderValue)
                actionLabel.Text = "Action: " .. CurrentAction
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
            shadow.Position = UDim2.new(dragPos.X.Scale, dragPos.X.Offset + delta.X - 5, dragPos.Y.Scale, dragPos.Y.Offset + delta.Y - 5)
        end
    end)
end

-- // INIT // --
updateChar()
overrideStamina()
findGeneratorRemote()
createHub()
DebugLog("Ultimate Forsaken AI loaded. Toggle ON to start. Check console for detailed logs.", "SUCCESS")
