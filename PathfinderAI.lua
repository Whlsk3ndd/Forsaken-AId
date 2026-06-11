--[[
    ███████╗ ██████╗ ██████╗ ███████╗ █████╗ ██╗  ██╗███████╗███╗   ██╗
    ██╔════╝██╔═══██╗██╔══██╗██╔════╝██╔══██╗██║ ██╔╝██╔════╝████╗  ██║
    ███████╗██║   ██║██████╔╝█████╗  ███████║█████╔╝ █████╗  ██╔██╗ ██║
    ╚════██║██║   ██║██╔══██╗██╔══╝  ██╔══██║██╔═██╗ ██╔══╝  ██║╚██╗██║
    ███████║╚██████╔╝██║  ██║██║     ██║  ██║██║  ██╗███████╗██║ ╚████║
    ╚══════╝ ╚═════╝ ╚═╝  ╚═╝╚═╝     ╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝╚═╝  ╚═══╝

    FORSAKEN AI - ULTIMATE EDITION
    + Customizable GUI (Neon Theme)
    + Advanced Map Detection (18 maps)
    + Infinite Stamina & Sprint
    + Auto Generator Repair (with Minigame Solver)
    + Smart Killer Evasion (Distance Slider)
    + Obstacle Avoidance (Raycast-based)
    + Completed Generator Blacklist
--]]

-- // SERVICES // --
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local TeleportService = game:GetService("TeleportService")
local VirtualInput = game:GetService("VirtualInput")
local Lighting = game:GetService("Lighting")

local LP = Players.LocalPlayer
local Mouse = LP:GetMouse()

-- // SCRIPT STATE // --
local AIEnabled = false
local ScriptActive = true
local SliderValue = 40
local PlayerChar, Humanoid, RootPart
local Generators = {}
local CompletedGenerators = {}  -- table of generator parts that are done
local CurrentAction = "Idle"
local LastGenScan = 0
local LastMove = 0
local CurrentMap = "Unknown"

-- // CONSTANTS // --
local WALK_SPEED = 24
local GEN_SCAN_INTERVAL = 5
local MOVEMENT_INTERVAL = 0.3
local FLEE_COOLDOWN = 0.8

-- // MAP DATABASE (with unique identifiers) // --
local MapDatabase = {
    ["Brandon6875935's Place"] = { identifiers = {"Castle", "CaveSlope"}, hazards = {} },
    ["Yorick's Resting Place"] = { identifiers = {"YorickHouse", "Graveyard"}, hazards = {"PoisonRiver"} },
    ["Glass Houses"] = { identifiers = {"JailMountain", "GlassHouse"}, hazards = {} },
    ["Horror Hotel"] = { identifiers = {"GiftShop", "TheaterRoom"}, hazards = {} },
    ["Planet Voss"] = { identifiers = {"PlanetVoss"}, hazards = {} },
    ["Ultimate Assassin Grounds"] = { identifiers = {"AssassinBase"}, hazards = {} },
    ["Pirate Bay"] = { identifiers = {"PirateShip", "BayWater"}, hazards = {"Water"} },
    ["Underground War"] = { identifiers = {"BunkerEntrance"}, hazards = {} },
    ["C00l Carnival"] = { identifiers = {"FerrisWheel", "CarnivalTent"}, hazards = {} },
    ["The Tempest"] = { identifiers = {"StormEye"}, hazards = {} },
    ["Work at a Pizza Place"] = { identifiers = {"PizzaShop"}, hazards = {} },
    ["Classic Battlegrounds"] = { identifiers = {"ClassicSpawn"}, hazards = {} },
    ["Cake Factory"] = { identifiers = {"CakeMachine"}, hazards = {} },
    ["Beach House Paradise"] = { identifiers = {"BeachHouse"}, hazards = {"Water"} },
    ["Bloodfell Manor"] = { identifiers = {"ManorGate"}, hazards = {} },
    ["Familiar Ruins"] = { identifiers = {"RuinsPillar"}, hazards = {} },
    ["Natural Disaster Island"] = { identifiers = {"Volcano", "TsunamiTrigger"}, hazards = {"Lava", "Water"} }
}

-- // KILLER & SURVIVOR LISTS // --
local KillerNames = {
    "slasher", "c00lkidd", "john doe", "1x1x1x1", "noli", "guest 666", "nosferatu",
    "subject 0", "pursuer", "killer kyle", "stitchhare", "mafioso", "bluudud",
    "divadayo", "gasharpoon", "annihilation", "aberrant", "admin romeo", "narrator",
    "apollyon", "photoshop", "azure", "doombringer", "phosphorus"
}
local SurvivorNames = {
    "noob", "shedletsky", "guest 1337", "elliot", "builderman", "dusekkar",
    "veeronica", "jane doe", "007n7", "chance", "two-time", "taph"
}

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

-- // MAP DETECTION (Improved) // --
local function detectMap()
    for mapName, data in pairs(MapDatabase) do
        for _, identifier in pairs(data.identifiers) do
            if workspace:FindFirstChild(identifier, true) then
                CurrentMap = mapName
                return mapName, data
            end
        end
    end
    CurrentMap = "Unknown"
    return "Unknown", { hazards = {} }
end

-- // KILLER DETECTION (Any player not in survivor list, plus distance) // --
local function getNearestKillerDistance()
    if not RootPart then return math.huge end
    local nearest = math.huge
    for _, plr in pairs(Players:GetPlayers()) do
        if plr ~= LP and plr.Character then
            local hrp = plr.Character:FindFirstChild("HumanoidRootPart")
            if hrp then
                local name = plr.Name:lower()
                local isKiller = false
                for _, k in pairs(KillerNames) do
                    if name:find(k) then isKiller = true; break end
                end
                if not isKiller then
                    for _, s in pairs(SurvivorNames) do
                        if name:find(s) then isKiller = false; break end
                    end
                    isKiller = true -- any other player is considered threat
                end
                if plr.Team and plr.Team.Name:lower():find("killer") then isKiller = true end
                if isKiller then
                    local dist = (RootPart.Position - hrp.Position).magnitude
                    if dist < nearest then nearest = dist end
                end
            end
        end
    end
    return nearest
end

-- // GENERATOR SCANNING (Only real generators with ProximityPrompt) // --
local function scanGenerators()
    local now = tick()
    if now - LastGenScan < GEN_SCAN_INTERVAL then return #Generators end
    LastGenScan = now
    local newGens = {}
    for _, prompt in pairs(workspace:GetDescendants()) do
        if prompt:IsA("ProximityPrompt") and prompt.Enabled and prompt.Parent then
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
    return #Generators
end

-- // MINIGAME SOLVER (Clicks all numbered buttons or any clickable in the repair frame) // --
local function solveMinigame()
    local minigameFrame = nil
    for i = 1, 30 do
        task.wait(0.1)
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
    if not minigameFrame then return false end

    -- Find all clickable elements (ImageButton, TextButton, or any object with a number)
    local clickables = {}
    for _, child in pairs(minigameFrame:GetDescendants()) do
        if child.Visible then
            if child:IsA("ImageButton") or child:IsA("TextButton") then
                table.insert(clickables, child)
            elseif child:IsA("TextLabel") and tonumber(child.Text) then
                -- If it's a TextLabel with a number, we can simulate click by using its position
                table.insert(clickables, child)
            end
        end
    end
    if #clickables < 2 then
        -- Fallback: click any button inside the frame
        for _, child in pairs(minigameFrame:GetDescendants()) do
            if child:IsA("ImageButton") or child:IsA("TextButton") then
                table.insert(clickables, child)
            end
        end
    end
    if #clickables < 2 then return false end

    -- Sort by position (left to right, top to bottom)
    table.sort(clickables, function(a,b)
        if math.abs(a.AbsolutePosition.Y - b.AbsolutePosition.Y) < 50 then
            return a.AbsolutePosition.X < b.AbsolutePosition.X
        else
            return a.AbsolutePosition.Y < b.AbsolutePosition.Y
        end
    end)

    -- Click each clickable in sequence
    for _, btn in ipairs(clickables) do
        local pos = btn.AbsolutePosition + Vector2.new(btn.AbsoluteSize.X/2, btn.AbsoluteSize.Y/2)
        pcall(function()
            VirtualInput:SendMouseButtonEvent(pos.X, pos.Y, 0, true, game, 0)
            task.wait(0.05)
            VirtualInput:SendMouseButtonEvent(pos.X, pos.Y, 0, false, game, 0)
        end)
        task.wait(0.1)
    end
    return true
end

-- // INTERACT WITH GENERATOR (Hold F, then solve minigame) // --
local function interactWithGenerator(gen)
    -- Hold F key
    pcall(function()
        VirtualInput:SendKeyEvent(true, Enum.KeyCode.F, false, game)
    end)
    local uiOpened = false
    for i = 1, 40 do
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
        local solved = solveMinigame()
        if solved then
            -- Wait for UI to close
            for i = 1, 40 do
                task.wait(0.2)
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
                    CompletedGenerators[gen] = true
                    return true
                end
            end
        end
    end
    return false
end

-- // OBSTACLE AVOIDANCE (Raycast, throttled) // --
local function getAvoidedPosition(targetPos)
    if not RootPart then return targetPos end
    local direction = (targetPos - RootPart.Position).unit
    local ray = Ray.new(RootPart.Position, direction * 4)
    local hit = workspace:FindPartOnRay(ray, PlayerChar)
    if not hit then return targetPos end
    -- Try left and right
    local right = direction:Cross(Vector3.new(0,1,0)).unit
    local left = -right
    for _, dir in ipairs({right, left}) do
        local testPos = RootPart.Position + dir * 3
        local testRay = Ray.new(RootPart.Position, dir * 3)
        if not workspace:FindPartOnRay(testRay, PlayerChar) then
            return testPos
        end
    end
    return RootPart.Position + direction * 4 -- just keep moving
end

-- // SMART MOVEMENT // --
local function moveToGenerator(gen)
    if not RootPart or not Humanoid then return end
    local now = tick()
    if now - LastMove < MOVEMENT_INTERVAL then return end
    LastMove = now
    local targetPos = getAvoidedPosition(gen.Position)
    Humanoid:MoveTo(targetPos)
end

-- // MAIN AI LOOP // --
local function aiTick()
    if not AIEnabled or not ScriptActive then return end
    if not PlayerChar or not Humanoid or not RootPart then
        updateChar()
        return
    end

    -- 1. Killer avoidance
    local killerDist = getNearestKillerDistance()
    if killerDist <= SliderValue then
        CurrentAction = "Fleeing"
        local fleeDir = (RootPart.Position - (RootPart.Position + Vector3.new(1,0,1))).unit
        Humanoid:MoveTo(RootPart.Position + fleeDir * 35)
        task.wait(FLEE_COOLDOWN)
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
            CurrentAction = string.format("Moving to generator (%d studs)", nearestDist)
            moveToGenerator(nearestGen)
        else
            CurrentAction = "Repairing"
            local success = interactWithGenerator(nearestGen)
            if success then
                -- Remove from active list
                for i, g in pairs(Generators) do
                    if g == nearestGen then table.remove(Generators, i); break end
                end
            end
            task.wait(1)
        end
    end
end

-- // INFINITE STAMINA & BLUR REMOVAL // --
local function applyStamina()
    if not Humanoid then return end
    if Humanoid.WalkSpeed < WALK_SPEED then
        Humanoid.WalkSpeed = WALK_SPEED
    end
    local staminaVal = Humanoid:FindFirstChild("Stamina")
    if staminaVal and staminaVal:IsA("NumberValue") then
        setreadonly(staminaVal, false)
        staminaVal.Value = 100
        setreadonly(staminaVal, true)
    end
    Humanoid:SetAttribute("Sprinting", true)
    for _, effect in pairs(Lighting:GetChildren()) do
        if effect:IsA("BlurEffect") then effect.Enabled = false end
    end
end

-- // BACKGROUND LOOPS (Throttled) // --
task.spawn(function()
    while ScriptActive do
        task.wait(MOVEMENT_INTERVAL)
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
        task.wait(GEN_SCAN_INTERVAL)
        if AIEnabled then scanGenerators() end
    end
end)

task.spawn(function()
    while ScriptActive do
        task.wait(3)
        detectMap()
    end
end)

-- // GUI HUB (Neon Theme) // --
local function createHub()
    local sg = Instance.new("ScreenGui")
    sg.Name = "ForsakenAI_Neon"
    sg.Parent = game.CoreGui
    sg.ResetOnSpawn = false

    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, 400, 0, 360)
    frame.Position = UDim2.new(0.5, -200, 0.5, -180)
    frame.BackgroundColor3 = Color3.fromRGB(5, 5, 15)
    frame.BackgroundTransparency = 0.15
    frame.BorderSizePixel = 0
    frame.Parent = sg
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 16)
    corner.Parent = frame

    local glow = Instance.new("UIStroke")
    glow.Color = Color3.fromRGB(0, 200, 255)
    glow.Thickness = 1.5
    glow.Transparency = 0.5
    glow.Parent = frame

    local gradient = Instance.new("UIGradient")
    gradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(15, 15, 30)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(5, 5, 15))
    })
    gradient.Parent = frame

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, 0, 0, 45)
    title.BackgroundTransparency = 1
    title.Text = "⚡ FORSAKEN AI PATHFINDER ⚡"
    title.TextColor3 = Color3.fromRGB(0, 230, 255)
    title.Font = Enum.Font.GothamBold
    title.TextSize = 18
    title.Parent = frame

    local mapDisplay = Instance.new("TextLabel")
    mapDisplay.Size = UDim2.new(1, -20, 0, 22)
    mapDisplay.Position = UDim2.new(0, 10, 0, 50)
    mapDisplay.BackgroundTransparency = 1
    mapDisplay.Text = "Map: " .. CurrentMap
    mapDisplay.TextColor3 = Color3.fromRGB(180, 180, 220)
    mapDisplay.Font = Enum.Font.Gotham
    mapDisplay.TextSize = 12
    mapDisplay.TextXAlignment = Enum.TextXAlignment.Left
    mapDisplay.Parent = frame

    local toggle = Instance.new("TextButton")
    toggle.Size = UDim2.new(0, 220, 0, 45)
    toggle.Position = UDim2.new(0.5, -110, 0, 85)
    toggle.BackgroundColor3 = Color3.fromRGB(0, 100, 180)
    toggle.Text = "🔴 AI OFF"
    toggle.TextColor3 = Color3.new(1, 1, 1)
    toggle.Font = Enum.Font.GothamBold
    toggle.TextSize = 18
    toggle.Parent = frame
    local btnCorner = Instance.new("UICorner")
    btnCorner.CornerRadius = UDim.new(0, 8)
    btnCorner.Parent = toggle

    -- Slider
    local sliderFrame = Instance.new("Frame")
    sliderFrame.Size = UDim2.new(0, 280, 0, 50)
    sliderFrame.Position = UDim2.new(0.5, -140, 0, 145)
    sliderFrame.BackgroundTransparency = 1
    sliderFrame.Parent = frame

    local sliderLabel = Instance.new("TextLabel")
    sliderLabel.Size = UDim2.new(0, 140, 0, 20)
    sliderLabel.Position = UDim2.new(0, 0, 0, 0)
    sliderLabel.BackgroundTransparency = 1
    sliderLabel.Text = "Killer Alert Radius: 40"
    sliderLabel.TextColor3 = Color3.fromRGB(255, 160, 160)
    sliderLabel.Font = Enum.Font.Gotham
    sliderLabel.TextSize = 12
    sliderLabel.Parent = sliderFrame

    local sliderBg = Instance.new("Frame")
    sliderBg.Size = UDim2.new(0, 220, 0, 6)
    sliderBg.Position = UDim2.new(0, 0, 0, 22)
    sliderBg.BackgroundColor3 = Color3.fromRGB(40, 40, 60)
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
        sliderLabel.Text = "Killer Alert Radius: " .. math.floor(val)
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
                    move:Disconnect(); rel:Disconnect()
                end
            end)
        end
    end)

    local status = Instance.new("TextLabel")
    status.Size = UDim2.new(1, -20, 0, 35)
    status.Position = UDim2.new(0, 10, 0, 210)
    status.BackgroundTransparency = 1
    status.Text = "Ready"
    status.TextColor3 = Color3.fromRGB(200, 200, 230)
    status.Font = Enum.Font.Gotham
    status.TextSize = 12
    status.TextXAlignment = Enum.TextXAlignment.Left
    status.Parent = frame

    local actionDisplay = Instance.new("TextLabel")
    actionDisplay.Size = UDim2.new(1, -20, 0, 22)
    actionDisplay.Position = UDim2.new(0, 10, 0, 245)
    actionDisplay.BackgroundTransparency = 1
    actionDisplay.Text = "Action: Idle"
    actionDisplay.TextColor3 = Color3.fromRGB(150, 150, 200)
    actionDisplay.Font = Enum.Font.Gotham
    actionDisplay.TextSize = 11
    actionDisplay.TextXAlignment = Enum.TextXAlignment.Left
    actionDisplay.Parent = frame

    -- Buttons
    local hideBtn = Instance.new("TextButton")
    hideBtn.Size = UDim2.new(0, 100, 0, 35)
    hideBtn.Position = UDim2.new(0.05, 0, 0, 285)
    hideBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 80)
    hideBtn.Text = "⛔ HIDE"
    hideBtn.TextColor3 = Color3.new(1, 1, 1)
    hideBtn.Font = Enum.Font.GothamBold
    hideBtn.TextSize = 14
    hideBtn.Parent = frame
    Instance.new("UICorner").CornerRadius = UDim.new(0, 6)

    local rejoinBtn = Instance.new("TextButton")
    rejoinBtn.Size = UDim2.new(0, 100, 0, 35)
    rejoinBtn.Position = UDim2.new(0.35, 0, 0, 285)
    rejoinBtn.BackgroundColor3 = Color3.fromRGB(80, 50, 100)
    rejoinBtn.Text = "🔄 REJOIN"
    rejoinBtn.TextColor3 = Color3.new(1, 1, 1)
    rejoinBtn.Font = Enum.Font.GothamBold
    rejoinBtn.TextSize = 14
    rejoinBtn.Parent = frame
    Instance.new("UICorner").CornerRadius = UDim.new(0, 6)

    local closeBtn = Instance.new("TextButton")
    closeBtn.Size = UDim2.new(0, 100, 0, 35)
    closeBtn.Position = UDim2.new(0.65, 0, 0, 285)
    closeBtn.BackgroundColor3 = Color3.fromRGB(150, 40, 60)
    closeBtn.Text = "❌ CLOSE"
    closeBtn.TextColor3 = Color3.new(1, 1, 1)
    closeBtn.Font = Enum.Font.GothamBold
    closeBtn.TextSize = 14
    closeBtn.Parent = frame
    Instance.new("UICorner").CornerRadius = UDim.new(0, 6)

    local showBtn = nil
    hideBtn.MouseButton1Click:Connect(function()
        frame.Visible = false
        if not showBtn then
            showBtn = Instance.new("TextButton")
            showBtn.Size = UDim2.new(0, 90, 0, 30)
            showBtn.Position = UDim2.new(0.02, 0, 0.9, 0)
            showBtn.BackgroundColor3 = Color3.fromRGB(0, 150, 200)
            showBtn.Text = "🔽 SHOW"
            showBtn.TextColor3 = Color3.new(1, 1, 1)
            showBtn.Font = Enum.Font.GothamBold
            showBtn.TextSize = 12
            showBtn.Parent = sg
            Instance.new("UICorner").CornerRadius = UDim.new(0, 8)
            showBtn.MouseButton1Click:Connect(function()
                frame.Visible = true
                showBtn:Destroy()
                showBtn = nil
            end)
        end
    end)

    rejoinBtn.MouseButton1Click:Connect(function()
        TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LP)
    end)

    closeBtn.MouseButton1Click:Connect(function()
        AIEnabled = false
        ScriptActive = false
        sg:Destroy()
        print("AI script fully unloaded.")
    end)

    toggle.MouseButton1Click:Connect(function()
        AIEnabled = not AIEnabled
        if AIEnabled then
            toggle.Text = "🟢 AI ON"
            toggle.BackgroundColor3 = Color3.fromRGB(0, 160, 80)
            updateChar()
            scanGenerators()
            detectMap()
            mapDisplay.Text = "Map: " .. CurrentMap
        else
            toggle.Text = "🔴 AI OFF"
            toggle.BackgroundColor3 = Color3.fromRGB(0, 100, 180)
        end
    end)

    -- Live status updater
    task.spawn(function()
        while ScriptActive and sg do
            task.wait(1)
            if AIEnabled then
                local kd = getNearestKillerDistance()
                status.Text = string.format("Generators: %d | Killer: %.0f studs | Alert: %d", #Generators, kd, SliderValue)
                actionDisplay.Text = "Action: " .. CurrentAction
                mapDisplay.Text = "Map: " .. CurrentMap
            else
                status.Text = "AI OFF"
            end
        end
    end)

    -- Draggable title bar
    local dragging = false
    local dragStart, dragPos
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

-- // INITIALIZATION // --
updateChar()
detectMap()
createHub()
print("Forsaken AI Ultimate Edition loaded. Map detection ready. Killer evasion active.")
