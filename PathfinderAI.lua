--[[
    ███████╗ ██████╗ ██████╗ ███████╗ █████╗ ██╗  ██╗███████╗███╗   ██╗
    ██╔════╝██╔═══██╗██╔══██╗██╔════╝██╔══██╗██║ ██╔╝██╔════╝████╗  ██║
    ███████╗██║   ██║██████╔╝█████╗  ███████║█████╔╝ █████╗  ██╔██╗ ██║
    ╚════██║██║   ██║██╔══██╗██╔══╝  ██╔══██║██╔═██╗ ██╔══╝  ██║╚██╗██║
    ███████║╚██████╔╝██║  ██║██║     ██║  ██║██║  ██╗███████╗██║ ╚████║
    ╚══════╝ ╚═════╝ ╚═╝  ╚═╝╚═╝     ╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝╚═╝  ╚═══╝

    FORSAKEN AI - COMPLETE OVERHAUL
    + Map Detection (17+ maps) | Pathfinding | Infinite Stamina | Auto-Minigame
    + Killer Evasion (distance-based) | Smooth GUI | No Freezing
--]]

-- // SERVICES AND GLOBALS // --
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local TeleportService = game:GetService("TeleportService")
local VirtualInput = game:GetService("VirtualInput")
local LP = Players.LocalPlayer
local Mouse = LP:GetMouse()

-- // SCRIPT STATE // --
local AIEnabled = false
local ScriptActive = true
local SliderValue = 40
local PlayerChar, Humanoid, RootPart
local Generators = {}
local CompletedGenerators = {}
local CurrentAction = "Idle"
local LastMoveTime = 0
local LastGenScan = 0
local LastKillerCheck = 0

-- // CONSTANTS // --
local WALK_SPEED = 24
local GEN_SCAN_INTERVAL = 5
local KILLER_CHECK_INTERVAL = 0.5
local MOVEMENT_INTERVAL = 0.5

-- // KILLER & SURVIVOR LISTS (for detection) // --
local KILLER_NAMES = {
    "slasher", "c00lkidd", "john doe", "1x1x1x1", "noli", "guest 666", "nosferatu",
    "subject 0", "pursuer", "killer kyle", "stitchhare", "mafioso", "bluudud",
    "divadayo", "gasharpoon", "annihilation", "aberrant", "admin romeo", "narrator",
    "apollyon", "photoshop", "azure", "doombringer", "phosphorus"
}

local SURVIVOR_NAMES = {
    "noob", "shedletsky", "guest 1337", "elliot", "builderman", "dusekkar",
    "veeronica", "jane doe", "007n7", "chance", "two-time", "taph"
}

-- // MAP DETECTION SYSTEM (17+ maps) // --
local MapDatabase = {
    ["Brandon6875935's Place"] = { hazards = {}, escape_points = {"Castle", "CaveSlope"} },
    ["Yorick's Resting Place"] = { hazards = {"PoisonRiver", "ToxicWater"}, escape_points = {"YorickHouse", "Graveyard"} },
    ["Glass Houses"] = { hazards = {}, escape_points = {"JailMountain", "GlassHouse"} },
    ["Horror Hotel"] = { hazards = {}, escape_points = {"GiftShop", "TheaterRoom"} },
    ["Planet Voss"] = { hazards = {}, escape_points = {} },
    ["Ultimate Assassin Grounds"] = { hazards = {}, escape_points = {} },
    ["Pirate Bay"] = { hazards = {"Water"}, escape_points = {} },
    ["Underground War"] = { hazards = {}, escape_points = {} },
    ["C00l Carnival"] = { hazards = {}, escape_points = {} },
    ["The Tempest"] = { hazards = {}, escape_points = {} },
    ["Work at a Pizza Place"] = { hazards = {}, escape_points = {} },
    ["Classic Battlegrounds"] = { hazards = {}, escape_points = {} },
    ["Cake Factory"] = { hazards = {}, escape_points = {} },
    ["Beach House Paradise"] = { hazards = {"Water"}, escape_points = {} },
    ["Bloodfell Manor"] = { hazards = {}, escape_points = {} },
    ["Familiar Ruins"] = { hazards = {}, escape_points = {} },
    ["Natural Disaster Island"] = { hazards = {"Lava", "Water"}, escape_points = {} }
}

local CurrentMap = nil
local function detectMap()
    for mapName, data in pairs(MapDatabase) do
        for _, point in pairs(data.escape_points) do
            if workspace:FindFirstChild(point, true) then
                CurrentMap = mapName
                return CurrentMap, data
            end
        end
    end
    CurrentMap = "Unknown"
    return CurrentMap, MapDatabase["Unknown"] or { hazards = {}, escape_points = {} }
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

-- // KILLER DETECTION (using names + teams) // --
local function getNearestKillerDistance()
    if not RootPart then return math.huge end
    local nearestDist = math.huge
    for _, plr in pairs(Players:GetPlayers()) do
        if plr ~= LP and plr.Character then
            local char = plr.Character
            local hrp = char:FindFirstChild("HumanoidRootPart")
            if hrp then
                local nameLower = plr.Name:lower()
                local isKiller = false
                for _, killerName in pairs(KILLER_NAMES) do
                    if nameLower:find(killerName) then
                        isKiller = true
                        break
                    end
                end
                if plr.Team and plr.Team.Name:lower():find("killer") then isKiller = true end
                if char:FindFirstChild("KillerTag") then isKiller = true end
                if isKiller then
                    local dist = (RootPart.Position - hrp.Position).magnitude
                    if dist < nearestDist then nearestDist = dist end
                end
            end
        end
    end
    return nearestDist
end

-- // GENERATOR SCANNING (only real generators) // --
local function scanGenerators()
    local now = tick()
    if now - LastGenScan < GEN_SCAN_INTERVAL then return #Generators end
    LastGenScan = now
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
    return #Generators
end

-- // MINIGAME SOLVER (connect the dots) // --
local function solveMinigame()
    local minigameFrame = nil
    for i = 1, 20 do
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

    -- Collect all dots (ImageButtons or TextButtons with numbers)
    local dots = {}
    for _, child in pairs(minigameFrame:GetDescendants()) do
        if (child:IsA("ImageButton") or child:IsA("TextButton")) and child.Visible then
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
    if #dots < 2 then return false end

    -- Group by color, then sort by number
    local colorGroups = {}
    for _, dot in pairs(dots) do
        local key = tostring(dot.color)
        if not colorGroups[key] then colorGroups[key] = {} end
        table.insert(colorGroups[key], dot)
    end

    for _, group in pairs(colorGroups) do
        table.sort(group, function(a, b) return a.number < b.number end)
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

-- // INTERACT WITH GENERATOR (HOLD F) // --
local function interactWithGenerator(gen)
    -- Simulate holding F key
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
            for i = 1, 30 do
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

-- // SMART MOVEMENT TO GENERATOR // --
local function moveToGenerator(gen)
    if not RootPart or not Humanoid then return end
    local direction = (gen.Position - RootPart.Position).unit
    local movePos = RootPart.Position + direction * 5
    Humanoid:MoveTo(movePos)
end

-- // MAIN AI LOOP (throttled) // --
local function aiTick()
    if not AIEnabled or not ScriptActive then return end
    if not PlayerChar or not Humanoid or not RootPart then
        updateChar()
        return
    end

    -- 1. KILLER AVOIDANCE
    local killerDist = getNearestKillerDistance()
    if killerDist <= SliderValue then
        CurrentAction = "Fleeing"
        local fleeDir = (RootPart.Position - (RootPart.Position + Vector3.new(1,0,1))).unit
        Humanoid:MoveTo(RootPart.Position + fleeDir * 30)
        return
    end

    -- 2. GENERATOR FARMING
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
            interactWithGenerator(nearestGen)
            task.wait(1)
        end
    end
end

-- // INFINITE STAMINA // --
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
    for _, effect in pairs(game:GetService("Lighting"):GetChildren()) do
        if effect:IsA("BlurEffect") then effect.Enabled = false end
    end
end

-- // BACKGROUND LOOPS // --
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
        task.wait(2)
        detectMap()
    end
end)

-- // GUI HUB (ENHANCED) // --
local function createHub()
    local sg = Instance.new("ScreenGui")
    sg.Name = "ForsakenAIHub"
    sg.Parent = game.CoreGui
    sg.ResetOnSpawn = false

    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, 400, 0, 350)
    frame.Position = UDim2.new(0.5, -200, 0.5, -175)
    frame.BackgroundColor3 = Color3.fromRGB(15, 15, 25)
    frame.BackgroundTransparency = 0.15
    frame.BorderSizePixel = 0
    frame.Parent = sg
    Instance.new("UICorner").CornerRadius = UDim.new(0, 12)

    local gradient = Instance.new("UIGradient")
    gradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(20, 20, 40)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(10, 10, 20))
    })
    gradient.Parent = frame

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, 0, 0, 40)
    title.BackgroundTransparency = 1
    title.Text = "⚡ FORSAKEN AI PATHFINDER ⚡"
    title.TextColor3 = Color3.fromRGB(0, 200, 255)
    title.Font = Enum.Font.GothamBold
    title.TextSize = 18
    title.Parent = frame

    local mapLabel = Instance.new("TextLabel")
    mapLabel.Size = UDim2.new(1, -20, 0, 20)
    mapLabel.Position = UDim2.new(0, 10, 0, 45)
    mapLabel.BackgroundTransparency = 1
    mapLabel.Text = "Map: " .. (CurrentMap or "Unknown")
    mapLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
    mapLabel.Font = Enum.Font.Gotham
    mapLabel.TextSize = 12
    mapLabel.TextXAlignment = Enum.TextXAlignment.Left
    mapLabel.Parent = frame

    local toggle = Instance.new("TextButton")
    toggle.Size = UDim2.new(0, 200, 0, 45)
    toggle.Position = UDim2.new(0.5, -100, 0, 80)
    toggle.BackgroundColor3 = Color3.fromRGB(0, 120, 200)
    toggle.Text = "🔴 AI OFF"
    toggle.TextColor3 = Color3.new(1, 1, 1)
    toggle.Font = Enum.Font.GothamBold
    toggle.TextSize = 18
    toggle.Parent = frame
    Instance.new("UICorner").CornerRadius = UDim.new(0, 8)

    -- Slider
    local sliderFrame = Instance.new("Frame")
    sliderFrame.Size = UDim2.new(0, 280, 0, 50)
    sliderFrame.Position = UDim2.new(0.5, -140, 0, 140)
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
    knob.BackgroundColor3 = Color3.new(1, 1, 1)
    knob.Text = ""
    knob.AutoButtonColor = false
    knob.Parent = sliderFrame
    Instance.new("UICorner").CornerRadius = UDim.new(1, 0)

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

    local actionLabel = Instance.new("TextLabel")
    actionLabel.Size = UDim2.new(1, -20, 0, 20)
    actionLabel.Position = UDim2.new(0, 10, 0, 245)
    actionLabel.BackgroundTransparency = 1
    actionLabel.Text = "Action: Idle"
    actionLabel.TextColor3 = Color3.fromRGB(150, 150, 200)
    actionLabel.Font = Enum.Font.Gotham
    actionLabel.TextSize = 11
    actionLabel.TextXAlignment = Enum.TextXAlignment.Left
    actionLabel.Parent = frame

    -- Buttons
    local hideBtn = Instance.new("TextButton")
    hideBtn.Size = UDim2.new(0, 100, 0, 35)
    hideBtn.Position = UDim2.new(0.05, 0, 0, 280)
    hideBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
    hideBtn.Text = "⛔ HIDE"
    hideBtn.TextColor3 = Color3.new(1, 1, 1)
    hideBtn.Font = Enum.Font.GothamBold
    hideBtn.TextSize = 14
    hideBtn.Parent = frame
    Instance.new("UICorner").CornerRadius = UDim.new(0, 6)

    local rejoinBtn = Instance.new("TextButton")
    rejoinBtn.Size = UDim2.new(0, 100, 0, 35)
    rejoinBtn.Position = UDim2.new(0.35, 0, 0, 280)
    rejoinBtn.BackgroundColor3 = Color3.fromRGB(80, 60, 100)
    rejoinBtn.Text = "🔄 REJOIN"
    rejoinBtn.TextColor3 = Color3.new(1, 1, 1)
    rejoinBtn.Font = Enum.Font.GothamBold
    rejoinBtn.TextSize = 14
    rejoinBtn.Parent = frame
    Instance.new("UICorner").CornerRadius = UDim.new(0, 6)

    local closeBtn = Instance.new("TextButton")
    closeBtn.Size = UDim2.new(0, 100, 0, 35)
    closeBtn.Position = UDim2.new(0.65, 0, 0, 280)
    closeBtn.BackgroundColor3 = Color3.fromRGB(150, 40, 50)
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
            showBtn.Size = UDim2.new(0, 80, 0, 30)
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
            mapLabel.Text = "Map: " .. CurrentMap
        else
            toggle.Text = "🔴 AI OFF"
            toggle.BackgroundColor3 = Color3.fromRGB(0, 120, 200)
        end
    end)

    -- Live status updater
    task.spawn(function()
        while ScriptActive and sg do
            task.wait(1)
            if AIEnabled then
                local kd = getNearestKillerDistance()
                status.Text = string.format("Generators: %d | Killer: %.0f studs | Alert: %d", #Generators, kd, SliderValue)
                actionLabel.Text = "Action: " .. CurrentAction
                mapLabel.Text = "Map: " .. CurrentMap
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
                if inp.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
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
print("Forsaken AI Overhauled loaded. Map detection ready. Killer evasion active.")
