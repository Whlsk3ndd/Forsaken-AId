--[[
    ███████╗ ██████╗ ██████╗ ███████╗ █████╗ ██╗  ██╗███████╗███╗   ██╗
    ██╔════╝██╔═══██╗██╔══██╗██╔════╝██╔══██╗██║ ██╔╝██╔════╝████╗  ██║
    ███████╗██║   ██║██████╔╝█████╗  ███████║█████╔╝ █████╗  ██╔██╗ ██║
    ╚════██║██║   ██║██╔══██╗██╔══╝  ██╔══██║██╔═██╗ ██╔══╝  ██║╚██╗██║
    ███████║╚██████╔╝██║  ██║██║     ██║  ██║██║  ██╗███████╗██║ ╚████║
    ╚══════╝ ╚═════╝ ╚═╝  ╚═╝╚═╝     ╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝╚═╝  ╚═══╝

    FINAL AI – WALL AVOIDANCE, RANDOM FLEE, MINIGAME SOLVER, GENERATOR BLACKLIST
--]]

-- // SERVICES // --
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local VirtualInput = game:GetService("VirtualInput")
local LP = Players.LocalPlayer

-- // STATE // --
local AIEnabled = false
local ScriptActive = true
local SliderValue = 60                -- killer alert radius
local MovingToTarget = false
local PlayerChar, Humanoid, RootPart
local Generators = {}                 -- list of generator parts (all)
local CompletedGenerators = {}        -- blacklist of finished generator parts
local CurrentAction = "Idle"
local Killer = nil
local LastFleeTime = 0
local RoundActive = false

-- // CONSTANTS // --
local WALK_SPEED = 24
local CARDINAL_DIRECTIONS = {
    Vector3.new(1,0,0),   -- East
    Vector3.new(0.707,0,0.707), -- NE
    Vector3.new(0,0,1),   -- North
    Vector3.new(-0.707,0,0.707), -- NW
    Vector3.new(-1,0,0),  -- West
    Vector3.new(-0.707,0,-0.707), -- SW
    Vector3.new(0,0,-1),  -- South
    Vector3.new(0.707,0,-0.707)  -- SE
}

-- // HAZARD PART NAMES // --
local HAZARD_NAMES = {"Poison", "Toxic", "Lava", "Fire", "Trap", "Spike"}

-- // DEBUG ON-SCREEN OVERLAY // --
local DebugFrame, DebugLabel
local function createOverlay()
    local sg = Instance.new("ScreenGui")
    sg.Name = "AIDebugOverlay"
    sg.Parent = game.CoreGui
    sg.ResetOnSpawn = false
    DebugFrame = Instance.new("Frame")
    DebugFrame.Size = UDim2.new(0, 350, 0, 120)
    DebugFrame.Position = UDim2.new(0, 10, 0, 10)
    DebugFrame.BackgroundColor3 = Color3.fromRGB(0,0,0)
    DebugFrame.BackgroundTransparency = 0.6
    DebugFrame.BorderSizePixel = 0
    DebugFrame.Parent = sg
    Instance.new("UICorner").CornerRadius = UDim.new(0, 8); Instance.new("UICorner").Parent = DebugFrame
    DebugLabel = Instance.new("TextLabel")
    DebugLabel.Size = UDim2.new(1, -10, 1, -10)
    DebugLabel.Position = UDim2.new(0, 5, 0, 5)
    DebugLabel.BackgroundTransparency = 1
    DebugLabel.Text = "Initializing..."
    DebugLabel.TextColor3 = Color3.fromRGB(255,255,0)
    DebugLabel.Font = Enum.Font.Gotham
    DebugLabel.TextSize = 12
    DebugLabel.TextXAlignment = Enum.TextXAlignment.Left
    DebugLabel.TextWrapped = true
    DebugLabel.Parent = DebugFrame
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
    if PlayerChar and Humanoid and Humanoid.Health > 0 then return true end
    return false
end

-- // KILLER DETECTION (distance to any other player) // --
local function getNearestKiller()
    if not RootPart then return nil, math.huge end
    local nearest = nil
    local nearestDist = math.huge
    for _, plr in pairs(Players:GetPlayers()) do
        if plr ~= LP and plr.Character then
            local hrp = plr.Character:FindFirstChild("HumanoidRootPart")
            if hrp then
                local d = (RootPart.Position - hrp.Position).magnitude
                if d < nearestDist then
                    nearestDist = d
                    nearest = hrp
                end
            end
        end
    end
    return nearest, nearestDist
end

-- // WALL AVOIDANCE (raycast forward, left, right) // --
local function isWallInFront(distance)
    if not RootPart then return false end
    local forward = RootPart.CFrame.LookVector * distance
    local ray = Ray.new(RootPart.Position, forward)
    local hit = workspace:FindPartOnRay(ray, PlayerChar)
    return hit ~= nil
end

local function getSteerDirection()
    local forwardDist = 4
    local leftDist = 3
    local rightDist = 3
    local forwardBlocked = isWallInFront(forwardDist)
    if not forwardBlocked then return nil end
    -- check left
    local leftRay = Ray.new(RootPart.Position, RootPart.CFrame.RightVector * -1 * leftDist)
    local leftHit = workspace:FindPartOnRay(leftRay, PlayerChar)
    -- check right
    local rightRay = Ray.new(RootPart.Position, RootPart.CFrame.RightVector * rightDist)
    local rightHit = workspace:FindPartOnRay(rightRay, PlayerChar)
    if not leftHit then
        return RootPart.CFrame.RightVector * -1  -- go left
    elseif not rightHit then
        return RootPart.CFrame.RightVector       -- go right
    end
    return RootPart.CFrame.LookVector * -1       -- backup
end

-- // HAZARD DETECTION (avoid poison water, traps) // --
local function isHazardNearby(radius)
    if not RootPart then return false end
    for _, hazardName in pairs(HAZARD_NAMES) do
        local parts = workspace:GetDescendants()
        for _, part in pairs(parts) do
            if part:IsA("BasePart") and part.Name:find(hazardName) then
                local dist = (RootPart.Position - part.Position).magnitude
                if dist < radius then
                    return true, part.Position
                end
            end
        end
    end
    return false
end

-- // RANDOM FLEE DIRECTION (cardinal) // --
local function getRandomFleeDirection(killerPos)
    if not RootPart then return Vector3.new(1,0,0) end
    local away = (RootPart.Position - killerPos).unit
    -- Find the cardinal direction closest to "away"
    local bestDir = away
    local bestDot = -1
    for _, dir in pairs(CARDINAL_DIRECTIONS) do
        local dot = away:Dot(dir)
        if dot > bestDot then
            bestDot = dot
            bestDir = dir
        end
    end
    -- Add randomness: choose a direction within 45 degrees of bestDir
    local randomOffset = math.rad(math.random(-45, 45))
    local randomDir = Vector3.new(
        bestDir.X * math.cos(randomOffset) - bestDir.Z * math.sin(randomOffset),
        0,
        bestDir.X * math.sin(randomOffset) + bestDir.Z * math.cos(randomOffset)
    ).unit
    return randomDir
end

-- // MOVE WITH WALL/HITBOX AVOIDANCE // --
local function smartMoveTo(targetPos)
    if not RootPart or not Humanoid then return end
    -- First, check for hazard nearby
    local hazardNear, hazardPos = isHazardNearby(15)
    if hazardNear then
        local awayFromHazard = (RootPart.Position - hazardPos).unit
        Humanoid:MoveTo(RootPart.Position + awayFromHazard * 20)
        return
    end
    -- Check for wall in front
    local steer = getSteerDirection()
    if steer then
        Humanoid:MoveTo(RootPart.Position + steer * 10)
    else
        Humanoid:MoveTo(targetPos)
    end
end

-- // GENERATOR SCANNING (with filtering) // --
local function scanGenerators()
    local newGens = {}
    for _, prompt in pairs(workspace:GetDescendants()) do
        if prompt:IsA("ProximityPrompt") then
            local parent = prompt.Parent
            local part = parent:IsA("BasePart") and parent or parent:FindFirstChildWhichIsA("BasePart")
            if part and not table.find(CompletedGenerators, part) then
                table.insert(newGens, part)
            end
        end
    end
    -- Also find parts named "Generator"
    for _, part in pairs(workspace:GetDescendants()) do
        if part:IsA("BasePart") and part.Name:lower():find("generator") then
            if not table.find(newGens, part) and not table.find(CompletedGenerators, part) then
                table.insert(newGens, part)
            end
        end
    end
    Generators = newGens
    updateDebug(string.format("Scanned %d generators", #Generators))
    return #Generators
end

-- // MINIGAME SOLVER // --
local function solveMinigame()
    -- Wait for minigame UI to appear
    local minigameFrame = nil
    for i = 1, 30 do
        task.wait(0.2)
        local playerGui = LP:FindFirstChild("PlayerGui")
        if playerGui then
            for _, gui in pairs(playerGui:GetDescendants()) do
                if gui:IsA("Frame") and (gui.Name:lower():find("minigame") or gui.Name:lower():find("repair")) then
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
    
    -- Find all clickable dots (ImageButtons or TextButtons with a number)
    local dots = {}
    for _, child in pairs(minigameFrame:GetDescendants()) do
        if (child:IsA("ImageButton") or child:IsA("TextButton")) and child.Visible then
            local number = tonumber(child.Text)
            if number then
                table.insert(dots, {
                    obj = child,
                    color = child.BackgroundColor3,
                    number = number,
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
    
    -- For each color group, connect dots in order of number
    for _, group in pairs(colorGroups) do
        table.sort(group, function(a,b) return a.number < b.number end)
        for i = 1, #group - 1 do
            local start = group[i]
            local target = group[i+1]
            if start.number == target.number then
                local startPos = start.obj.AbsolutePosition + Vector2.new(start.obj.AbsoluteSize.X/2, start.obj.AbsoluteSize.Y/2)
                local targetPos = target.obj.AbsolutePosition + Vector2.new(target.obj.AbsoluteSize.X/2, target.obj.AbsoluteSize.Y/2)
                -- Simulate drag
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

-- // INTERACT WITH GENERATOR (hold F until minigame appears) // --
local function interactWithGenerator(gen)
    updateDebug("Interacting with generator: " .. gen.Name)
    local prompt = gen:FindFirstChildWhichIsA("ProximityPrompt")
    if not prompt then
        updateDebug("No proximity prompt on generator")
        return false
    end
    -- Hold F (keycode 70) until minigame UI appears
    pcall(function()
        VirtualInput:SendKeyEvent(true, Enum.KeyCode.F, false, game)
    end)
    local startTime = tick()
    local minigameOpened = false
    while tick() - startTime < 3 do
        task.wait(0.1)
        local playerGui = LP:FindFirstChild("PlayerGui")
        if playerGui then
            for _, gui in pairs(playerGui:GetDescendants()) do
                if gui:IsA("Frame") and (gui.Name:lower():find("minigame") or gui.Name:lower():find("repair")) then
                    minigameOpened = true
                    break
                end
            end
        end
        if minigameOpened then break end
    end
    pcall(function()
        VirtualInput:SendKeyEvent(false, Enum.KeyCode.F, false, game)
    end)
    
    if minigameOpened then
        updateDebug("Minigame opened, solving...")
        local solved = solveMinigame()
        if solved then
            -- Wait for minigame to close
            local closed = false
            for i = 1, 30 do
                task.wait(0.5)
                local playerGui = LP:FindFirstChild("PlayerGui")
                if playerGui then
                    local found = false
                    for _, gui in pairs(playerGui:GetDescendants()) do
                        if gui:IsA("Frame") and (gui.Name:lower():find("minigame") or gui.Name:lower():find("repair")) then
                            found = true
                            break
                        end
                    end
                    if not found then
                        closed = true
                        break
                    end
                end
            end
            if closed then
                updateDebug("Generator completed!")
                table.insert(CompletedGenerators, gen)
                -- Remove from active Generators list
                for i, g in pairs(Generators) do
                    if g == gen then table.remove(Generators, i) break end
                end
                return true
            end
        end
    else
        updateDebug("Minigame did not open")
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
    
    -- Killer detection & flee
    local killerObj, killerDist = getNearestKiller()
    if killerObj and killerDist <= SliderValue then
        CurrentAction = string.format("Fleeing (killer %.0f studs)", killerDist)
        local fleeDir = getRandomFleeDirection(killerObj.Position)
        local fleePos = RootPart.Position + fleeDir * 35
        fleePos = Vector3.new(math.clamp(fleePos.X, -500, 500), fleePos.Y, math.clamp(fleePos.Z, -500, 500))
        smartMoveTo(fleePos)
        return
    end
    
    -- Generator farming
    if #Generators == 0 then
        if #CompletedGenerators > 0 then
            updateDebug("All known generators completed")
        else
            scanGenerators()
        end
        return
    end
    
    -- Find nearest non-completed generator
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
            smartMoveTo(nearestGen.Position)
        else
            CurrentAction = "Interacting with generator"
            interactWithGenerator(nearestGen)
            task.wait(0.5)
        end
    end
end

-- // INFINITE STAMINA & BLUR REMOVAL // --
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
        task.wait(0.3)
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
        task.wait(5)
        if AIEnabled then scanGenerators() end
    end
end)

-- // DEBUG STATUS UPDATER // --
task.spawn(function()
    while ScriptActive do
        task.wait(1)
        if AIEnabled then
            local _, kd = getNearestKiller()
            local genCount = #Generators
            local compCount = #CompletedGenerators
            updateDebug(string.format("Gens: %d (done %d) | Killer: %.0f | Action: %s", genCount, compCount, kd, CurrentAction))
        end
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
    Instance.new("UICorner").CornerRadius = UDim.new(0,12); Instance.new("UICorner").Parent = frame
    
    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1,0,0,35)
    title.BackgroundTransparency = 1
    title.Text = "🔪 FORSAKEN AI (FINAL) 🔪"
    title.TextColor3 = Color3.fromRGB(255,80,120)
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
    Instance.new("UICorner").CornerRadius = UDim.new(0,8); Instance.new("UICorner").Parent = toggle
    
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
    sliderLabel.Text = "Killer Alert Radius: 60"
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
    fill.Size = UDim2.new(0.6,0,1,0)
    fill.BackgroundColor3 = Color3.fromRGB(255,80,120)
    fill.BorderSizePixel = 0
    fill.Parent = sliderBg
    local knob = Instance.new("TextButton")
    knob.Size = UDim2.new(0,14,0,14)
    knob.Position = UDim2.new(0.6,-7,0,-4)
    knob.BackgroundColor3 = Color3.new(1,1,1)
    knob.Text = ""
    knob.AutoButtonColor = false
    knob.Parent = sliderFrame
    Instance.new("UICorner").CornerRadius = UDim.new(1,0); Instance.new("UICorner").Parent = knob
    
    local function setSlider(val)
        val = math.clamp(val, 0, 100)
        SliderValue = val
        fill.Size = UDim2.new(val/100,0,1,0)
        knob.Position = UDim2.new(val/100,-7,0,-4)
        sliderLabel.Text = "Killer Alert Radius: " .. math.floor(val)
    end
    setSlider(60)
    
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
    Instance.new("UICorner").CornerRadius = UDim.new(0,6); Instance.new("UICorner").Parent = hideBtn
    
    local rejoinBtn = Instance.new("TextButton")
    rejoinBtn.Size = UDim2.new(0, 90, 0, 35)
    rejoinBtn.Position = UDim2.new(0.35, 0, 0, 235)
    rejoinBtn.BackgroundColor3 = Color3.fromRGB(100,80,120)
    rejoinBtn.Text = "🔄 REJOIN"
    rejoinBtn.TextColor3 = Color3.new(1,1,1)
    rejoinBtn.Font = Enum.Font.GothamBold
    rejoinBtn.TextSize = 13
    rejoinBtn.Parent = frame
    Instance.new("UICorner").CornerRadius = UDim.new(0,6); Instance.new("UICorner").Parent = rejoinBtn
    
    local closeBtn = Instance.new("TextButton")
    closeBtn.Size = UDim2.new(0, 90, 0, 35)
    closeBtn.Position = UDim2.new(0.65, 0, 0, 235)
    closeBtn.BackgroundColor3 = Color3.fromRGB(180,40,60)
    closeBtn.Text = "❌ CLOSE"
    closeBtn.TextColor3 = Color3.new(1,1,1)
    closeBtn.Font = Enum.Font.GothamBold
    closeBtn.TextSize = 13
    closeBtn.Parent = frame
    Instance.new("UICorner").CornerRadius = UDim.new(0,6); Instance.new("UICorner").Parent = closeBtn
    
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
            Instance.new("UICorner").CornerRadius = UDim.new(0,8); Instance.new("UICorner").Parent = showBtn
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
        -- Script will be destroyed; re-execute manually or set auto-execute in executor
    end)
    
    closeBtn.MouseButton1Click:Connect(function()
        AIEnabled = false
        ScriptActive = false
        if DebugFrame and DebugFrame.Parent then DebugFrame.Parent:Destroy() end
        sg:Destroy()
        print("AI script closed.")
    end)
    
    toggle.MouseButton1Click:Connect(function()
        AIEnabled = not AIEnabled
        if AIEnabled then
            toggle.Text = "🟢 AI ON"
            toggle.BackgroundColor3 = Color3.fromRGB(0,180,80)
            updateChar()
            scanGenerators()
            updateDebug("AI enabled")
        else
            toggle.Text = "🔴 AI OFF"
            toggle.BackgroundColor3 = Color3.fromRGB(0,120,200)
            updateDebug("AI disabled")
        end
    end)
    
    -- Status updater
    task.spawn(function()
        while ScriptActive and sg do
            task.wait(1)
            if AIEnabled then
                local _, kd = getNearestKiller()
                status.Text = string.format("Gens: %d | Killer: %.0f | Alert: %d", #Generators, kd, SliderValue)
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
updateDebug("Final AI loaded. Toggle ON. Wall avoidance, hazard detection, minigame solver active.")
