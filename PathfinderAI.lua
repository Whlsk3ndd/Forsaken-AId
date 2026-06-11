--[[
    ███████╗ ██████╗ ██████╗ ███████╗ █████╗ ██╗  ██╗███████╗███╗   ██╗
    ██╔════╝██╔═══██╗██╔══██╗██╔════╝██╔══██╗██║ ██╔╝██╔════╝████╗  ██║
    ███████╗██║   ██║██████╔╝█████╗  ███████║█████╔╝ █████╗  ██╔██╗ ██║
    ╚════██║██║   ██║██╔══██╗██╔══╝  ██╔══██║██╔═██╗ ██╔══╝  ██║╚██╗██║
    ███████║╚██████╔╝██║  ██║██║     ██║  ██║██║  ██╗███████╗██║ ╚████║
    ╚══════╝ ╚═════╝ ╚═╝  ╚═╝╚═╝     ╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝╚═╝  ╚═══╝

    ULTIMATE FORSAKEN AI: AUTONOMOUS SURVIVOR SUITE
    [+] Dynamic Map & Hazard Detection   [+] Dual-Threshold Killer Avoidance
    [+] Smart Generator Repair           [+] Role-Based Ability Usage
    [+] Enhanced Infinite Stamina        [+] Auto GUI Interaction
--]]

-- // SERVICES & PRELOAD //
local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local VirtualUser = game:GetService("VirtualUser")

local LP = Players.LocalPlayer
local Mouse = LP:GetMouse()

-- // STATE & CONSTANTS //
local ScriptActive = true
local AIDisabled = false
local AIEnabled = false
local MovingToTarget = false
local IsFleeing = false
local LastPathTime = 0
local PATH_REGEN_DELAY = 1.5
local SliderValue = 40
local SafeRadius = SliderValue + 20
local OriginalWalkSpeed = 16
local PlayerChar, Humanoid, RootPart
local Generators = {}
local CurrentMap = nil
local Killer = nil

-- Killer name list for advanced detection
local KILLER_NAMES = {
    "Slasher", "c00lkidd", "John Doe", "Jason", "1x1x1x1", "Noli", "Guest 666", "Nosferatu",
    "c00l_kidd", "john_doe", "1x1x1x1", "noli", "guest_666", "nosferatu"
}

-- Map-specific hazard zones and escape points
local MapDatabase = {
    ["Yorick's Resting Place"] = {
        hazards = {"PoisonRiver", "ToxicWater", "Poison"},
        escape_points = {"House", "Graveyard", "Temple"},
        pathfinding_avoid = true
    },
    ["Glass Houses"] = {
        hazards = {"Poison", "ToxicWater"}, -- Assuming similar hazards
        escape_points = {"JailMountain", "GlassHouse", "BigMountain", "SmallMountain"},
        pathfinding_avoid = true
    },
    ["Brandon6875935's Place"] = {
        hazards = {}, -- No known environmental hazards
        escape_points = {"Castle", "CaveSlope", "BrandonWorld"},
        pathfinding_avoid = false
    },
    ["Planet Voss"] = {
        hazards = {}, -- No known environmental hazards
        escape_points = {},
        pathfinding_avoid = false
    },
    ["Horror Hotel"] = {
        hazards = {},
        escape_points = {"GiftShop", "PlayArea", "OutdoorField", "TheaterRoom"},
        pathfinding_avoid = false
    }
}

-- Pre-defined hazard cost for pathfinding
local HAZARD_COST = 100000

-- Survivor ability logic
local SurvivorAbilities = {
    Shedletsky = {
        type = "Sentinel",
        ability = "Slash",
        condition = function(killerDist) return killerDist < 15 end,
        action = function() -- Simulate ability usage
            local key = Enum.KeyCode.Q -- Assuming ability bound to Q
            VirtualUser:PressKey(key, 2)
        end
    },
    Noob = {
        type = "Survivalist",
        ability = "Bloxy Cola",
        condition = function(isChased) return isChased end,
        action = function()
            local key = Enum.KeyCode.E -- Assuming ability bound to E
            VirtualUser:PressKey(key, 2)
        end
    }
}

-- // UTILITIES //
local function updateChar()
    PlayerChar = LP.Character
    if PlayerChar then
        Humanoid = PlayerChar:FindFirstChildOfClass("Humanoid")
        RootPart = PlayerChar:FindFirstChild("HumanoidRootPart")
        if Humanoid and OriginalWalkSpeed == 16 then
            OriginalWalkSpeed = Humanoid.WalkSpeed
        end
    end
end

local function isAlive()
    return PlayerChar and Humanoid and Humanoid.Health > 0
end

local function isInLobby()
    local lobbyPart = workspace:FindFirstChild("Lobby") or workspace:FindFirstChild("LobbyArea")
    if lobbyPart and RootPart and (RootPart.Position - lobbyPart.Position).magnitude < 100 then
        return true
    end
    local playerGui = LP:FindFirstChild("PlayerGui")
    if playerGui then
        for _, gui in pairs(playerGui:GetChildren()) do
            if gui:IsA("ScreenGui") and (gui.Name:lower():find("lobby") or gui.Name:lower():find("menu")) then
                if gui.Enabled then return true end
            end
        end
    end
    return false
end

-- // ENHANCED INFINITE STAMINA //
local function applyInfiniteStamina()
    if not Humanoid then return end
    -- Directly manipulate walk speed and sprinting state
    local sprintSpeed = 24
    if Humanoid.WalkSpeed < sprintSpeed then
        Humanoid.WalkSpeed = sprintSpeed
    end
    if not Humanoid.Sprint then
        Humanoid.Sprint = true
    end
    -- Override any local stamina value
    local staminaVal = Humanoid:FindFirstChild("Stamina")
    if staminaVal and staminaVal:IsA("NumberValue") then
        setreadonly(staminaVal, false)
        staminaVal.Value = 100
        setreadonly(staminaVal, true)
    end
    Humanoid:SetAttribute("Sprinting", true)
    local sprintBool = PlayerChar and PlayerChar:FindFirstChild("IsSprinting")
    if sprintBool then sprintBool.Value = true end
    -- Disable stamina blur effect
    for _, effect in pairs(game:GetService("Lighting"):GetChildren()) do
        if effect:IsA("BlurEffect") then effect.Enabled = false end
    end
end

-- // MAP & HAZARD DETECTION //
local function detectCurrentMap()
    local mapName = nil
    for name, data in pairs(MapDatabase) do
        for _, partName in pairs(data.escape_points) do
            if workspace:FindFirstChild(partName, true) then
                mapName = name
                break
            end
        end
        if mapName then break end
    end
    -- Fallback detection based on unique parts
    if not mapName then
        if workspace:FindFirstChild("Castle", true) then mapName = "Brandon6875935's Place"
        elseif workspace:FindFirstChild("Yorick's House", true) then mapName = "Yorick's Resting Place"
        elseif workspace:FindFirstChild("JailMountain", true) then mapName = "Glass Houses"
        elseif workspace:FindFirstChild("PlanetVoss", true) then mapName = "Planet Voss"
        elseif workspace:FindFirstChild("HorrorHotel", true) then mapName = "Horror Hotel"
        else mapName = "Unknown"
        end
    end
    return mapName, MapDatabase[mapName] or {}
end

local function setupMapHazards()
    if not CurrentMapData.pathfinding_avoid then return end
    for _, hazardName in pairs(CurrentMapData.hazards) do
        local hazardParts = workspace:GetDescendants()
        for _, part in pairs(hazardParts) do
            if part.Name:find(hazardName) and part:IsA("BasePart") then
                -- Tag part for pathfinding avoidance
                part:SetAttribute("IsHazard", true)
            end
        end
    end
end

-- // ENHANCED KILLER DETECTION //
local function findKiller()
    for _, plr in pairs(Players:GetPlayers()) do
        if plr ~= LP and plr.Character and plr.Character:FindFirstChild("HumanoidRootPart") then
            local char = plr.Character
            local isKiller = false
            -- Check by name
            for _, name in pairs(KILLER_NAMES) do
                if plr.Name:find(name) or (char and char.Name:find(name)) then
                    isKiller = true
                    break
                end
            end
            -- Check by team, tag, or attribute
            if not isKiller then
                isKiller = (plr.Team and plr.Team.Name:lower():find("killer")) or
                           (plr.Character:FindFirstChild("KillerTag")) or
                           (plr.Character:GetAttribute("IsKiller"))
            end
            if isKiller then return char end
        end
    end
    return nil
end

-- // ADVANCED PATHFINDING //
local function moveToPosition(targetPos)
    if not RootPart or not Humanoid or MovingToTarget then return false end
    local path = PathfindingService:CreatePath({
        AgentRadius = 2.5,
        AgentHeight = 5,
        AgentCanJump = true,
        AgentMaxSlope = 60,
        WaypointSpacing = 3,
        Costs = { Water = 100, Dangerous = HAZARD_COST }
    })
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
    for _, wp in ipairs(waypoints) do
        if not AIEnabled or AIDisabled then break end
        if not RootPart or not Humanoid then break end
        if wp.Action == Enum.PathWaypointAction.Jump then
            Humanoid.Jump = true
            task.wait(0.1)
        end
        Humanoid:MoveTo(wp.Position)
        local startTime = tick()
        while (RootPart.Position - wp.Position).magnitude > 3 do
            if tick() - startTime > 2 then break end
            if not AIEnabled or AIDisabled then break end
            task.wait(0.05)
        end
    end
    MovingToTarget = false
    return true
end

-- // SMART FLEE WITH DUAL THRESHOLD //
local function getRandomFleePosition()
    local angle = math.rad(math.random(-90, 90))
    local randomDir = Vector3.new(math.cos(angle), 0, math.sin(angle)).unit
    local fleePos = RootPart.Position + randomDir * 30 + randomDir * math.random(10, 30)
    fleePos = Vector3.new(math.clamp(fleePos.X, -500, 500), fleePos.Y, math.clamp(fleePos.Z, -500, 500))
    return fleePos
end

local function getSafeEscapePoint()
    if #CurrentMapData.escape_points > 0 then
        local escapePointName = CurrentMapData.escape_points[math.random(1, #CurrentMapData.escape_points)]
        local escapeObject = workspace:FindFirstChild(escapePointName, true)
        if escapeObject and escapeObject:IsA("BasePart") then
            return escapeObject.Position
        end
    end
    return nil
end

local function fleeFromKiller()
    local killerRoot = Killer:FindFirstChild("HumanoidRootPart")
    if not killerRoot then return end
    local killerDist = (RootPart.Position - killerRoot.Position).magnitude
    local fleeTarget = nil
    if killerDist <= SliderValue then
        fleeTarget = getRandomFleePosition()
    elseif killerDist <= SafeRadius then
        fleeTarget = getSafeEscapePoint()
    end
    if fleeTarget then
        moveToPosition(fleeTarget)
    end
end

-- // GENERATOR & MINIGAME DETECTION //
local function scanGenerators()
    local newGens = {}
    for _, prompt in pairs(workspace:GetDescendants()) do
        if prompt:IsA("ProximityPrompt") and prompt.Parent then
            local part = prompt.Parent:IsA("BasePart") and prompt.Parent or prompt.Parent:FindFirstChildWhichIsA("BasePart")
            if part then table.insert(newGens, part) end
        end
    end
    for _, part in pairs(workspace:GetDescendants()) do
        if part:IsA("BasePart") and part.Name:lower():find("generator") then
            if not table.find(newGens, part) then table.insert(newGens, part) end
        end
    end
    Generators = newGens
    return #Generators
end

local function openGeneratorGUI(gen)
    local prompt = gen:FindFirstChildWhichIsA("ProximityPrompt")
    if prompt then
        pcall(function()
            prompt:Prompt()
        end)
        return true
    end
    return false
end

-- // ABILITY USAGE //
local function useSurvivorAbility()
    local playerName = LP.Name
    local charData = SurvivorAbilities[playerName]
    if charData and charData.condition then
        local isChased = Killer and RootPart and Killer:FindFirstChild("HumanoidRootPart") and
                         (RootPart.Position - Killer.HumanoidRootPart.Position).magnitude < 30
        if charData.condition(isChased) then
            charData.action()
        end
    end
end

-- // MAIN AI TICK //
local function aiTick()
    if not AIEnabled or AIDisabled then return end
    if not isAlive() or isInLobby() then
        if Humanoid then Humanoid:MoveTo(Vector3.new(0,0,0)) end
        return
    end
    if not PlayerChar or not Humanoid or not RootPart then
        updateChar()
        return
    end
    -- Killer avoidance (dual-threshold)
    Killer = findKiller()
    if Killer and RootPart then
        fleeFromKiller()
        useSurvivorAbility()
        return
    end
    -- Generator detection
    if #Generators == 0 then
        scanGenerators()
        return
    end
    local nearestGen, nearestDist = nil, math.huge
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
            openGeneratorGUI(nearestGen)
            task.wait(0.5)
        end
    end
end

-- // BACKGROUND LOOPS //
local function startLoops()
    task.spawn(function()
        while ScriptActive do
            task.wait(0.25)
            aiTick()
        end
    end)
    task.spawn(function()
        while ScriptActive do
            task.wait(0.3)
            if AIEnabled then applyInfiniteStamina() end
        end
    end)
    task.spawn(function()
        while ScriptActive do
            task.wait(5)
            if AIEnabled then
                CurrentMap, CurrentMapData = detectCurrentMap()
                setupMapHazards()
                scanGenerators()
            end
        end
    end)
end

-- // GUI HUB //
local function createHub()
    local sg = Instance.new("ScreenGui")
    sg.Name = "UltimateForsakenAI"
    sg.Parent = game.CoreGui
    sg.ResetOnSpawn = false
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, 360, 0, 280)
    frame.Position = UDim2.new(0.5, -180, 0.5, -140)
    frame.BackgroundColor3 = Color3.fromRGB(10, 10, 20)
    frame.BackgroundTransparency = 0.15
    frame.Parent = sg
    Instance.new("UICorner").CornerRadius = UDim.new(0, 12); Instance.new("UICorner").Parent = frame
    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, 0, 0, 35)
    title.BackgroundTransparency = 1
    title.Text = "🔪 ULTIMATE FORSAKEN AI 🔪"
    title.TextColor3 = Color3.fromRGB(255, 80, 120)
    title.Font = Enum.Font.GothamBold
    title.TextSize = 15
    title.Parent = frame
    -- Toggle
    local toggle = Instance.new("TextButton")
    toggle.Size = UDim2.new(0, 200, 0, 45)
    toggle.Position = UDim2.new(0.5, -100, 0, 50)
    toggle.BackgroundColor3 = Color3.fromRGB(0, 120, 200)
    toggle.Text = "🔴 AI OFF"
    toggle.TextColor3 = Color3.new(1, 1, 1)
    toggle.Font = Enum.Font.GothamBold
    toggle.TextSize = 18
    toggle.Parent = frame
    Instance.new("UICorner").CornerRadius = UDim.new(0, 8); Instance.new("UICorner").Parent = toggle
    -- Slider
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
    knob.BackgroundColor3 = Color3.new(1, 1, 1)
    knob.Text = ""
    knob.AutoButtonColor = false
    knob.Parent = sliderFrame
    Instance.new("UICorner").CornerRadius = UDim.new(1,0); Instance.new("UICorner").Parent = knob
    local function setSlider(val)
        val = math.clamp(val, 0, 100)
        SliderValue = val
        SafeRadius = val + 20
        fill.Size = UDim2.new(val/100, 0, 1, 0)
        knob.Position = UDim2.new(val/100, -7, 0, -4)
        sliderLabel.Text = string.format("Alert: %d (safe: %d)", SliderValue, SafeRadius)
    end
    setSlider(40)
    knob.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            local move, release
            move = UserInputService.InputChanged:Connect(function(io)
                if io.UserInputType == Enum.UserInputType.MouseMovement then
                    local x = math.clamp(io.Position.X - sliderBg.AbsolutePosition.X, 0, sliderBg.AbsoluteSize.X)
                    setSlider(math.floor((x/sliderBg.AbsoluteSize.X)*100))
                end
            end)
            release = UserInputService.InputEnded:Connect(function(io)
                if io.UserInputType == Enum.UserInputType.MouseButton1 then
                    move:Disconnect(); release:Disconnect()
                end
            end)
        end
    end)
    -- Status
    local status = Instance.new("TextLabel")
    status.Size = UDim2.new(1, -20, 0, 35)
    status.Position = UDim2.new(0, 10, 0, 180)
    status.BackgroundTransparency = 1
    status.Text = "Initializing..."
    status.TextColor3 = Color3.fromRGB(200, 200, 230)
    status.Font = Enum.Font.Gotham
    status.TextSize = 12
    status.TextXAlignment = Enum.TextXAlignment.Left
    status.Parent = frame
    -- Buttons
    local hideBtn = Instance.new("TextButton")
    hideBtn.Size = UDim2.new(0, 100, 0, 35)
    hideBtn.Position = UDim2.new(0.05, 0, 0, 230)
    hideBtn.BackgroundColor3 = Color3.fromRGB(80, 80, 100)
    hideBtn.Text = "⛔ HIDE"
    hideBtn.TextColor3 = Color3.new(1, 1, 1)
    hideBtn.Font = Enum.Font.GothamBold
    hideBtn.TextSize = 14
    hideBtn.Parent = frame
    Instance.new("UICorner").CornerRadius = UDim.new(0, 6); Instance.new("UICorner").Parent = hideBtn
    local disableBtn = Instance.new("TextButton")
    disableBtn.Size = UDim2.new(0, 130, 0, 35)
    disableBtn.Position = UDim2.new(0.5, -65, 0, 230)
    disableBtn.BackgroundColor3 = Color3.fromRGB(180, 40, 60)
    disableBtn.Text = "🔴 CLOSE & DISABLE"
    disableBtn.TextColor3 = Color3.new(1, 1, 1)
    disableBtn.Font = Enum.Font.GothamBold
    disableBtn.TextSize = 13
    disableBtn.Parent = frame
    Instance.new("UICorner").CornerRadius = UDim.new(0, 6); Instance.new("UICorner").Parent = disableBtn
    local showBtn = nil
    hideBtn.MouseButton1Click:Connect(function()
        frame.Visible = false
        if not showBtn then
            showBtn = Instance.new("TextButton")
            showBtn.Size = UDim2.new(0, 100, 0, 30)
            showBtn.Position = UDim2.new(0.02, 0, 0.9, 0)
            showBtn.BackgroundColor3 = Color3.fromRGB(0, 180, 200)
            showBtn.Text = "🔽 SHOW MENU"
            showBtn.TextColor3 = Color3.new(1, 1, 1)
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
    disableBtn.MouseButton1Click:Connect(function()
        AIEnabled = false
        AIDisabled = true
        if Humanoid and OriginalWalkSpeed then Humanoid.WalkSpeed = OriginalWalkSpeed end
        sg:Destroy()
        print("🔴 AI and script fully disabled. Menu closed.")
    end)
    toggle.MouseButton1Click:Connect(function()
        if not AIDisabled then
            AIEnabled = not AIEnabled
            if AIEnabled then
                toggle.Text = "🟢 AI ON"
                toggle.BackgroundColor3 = Color3.fromRGB(0, 180, 80)
                updateChar()
                CurrentMap, CurrentMapData = detectCurrentMap()
                setupMapHazards()
                scanGenerators()
                status.Text = string.format("ACTIVE | Map: %s | %d generators", CurrentMap, #Generators)
            else
                toggle.Text = "🔴 AI OFF"
                toggle.BackgroundColor3 = Color3.fromRGB(0, 120, 200)
                status.Text = "AI OFF"
            end
        else
            status.Text = "Script is disabled. Re-execute to enable."
        end
    end)
    -- Status updater
    task.spawn(function()
        while ScriptActive and sg do
            task.wait(1)
            if AIEnabled and not AIDisabled then
                local killer = findKiller()
                local killerInfo = ""
                if killer and RootPart and killer:FindFirstChild("HumanoidRootPart") then
                    local dist = (RootPart.Position - killer.HumanoidRootPart.Position).magnitude
                    killerInfo = string.format(" | Killer: %.0f studs", dist)
                else
                    killerInfo = " | Killer: none"
                end
                status.Text = string.format("ACTIVE | Map: %s | %d generators%s", CurrentMap or "Unknown", #Generators, killerInfo)
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

-- // INIT //
updateChar()
LP.CharacterAdded:Connect(function()
    task.wait(0.5)
    updateChar()
    if AIEnabled then
        CurrentMap, CurrentMapData = detectCurrentMap()
        setupMapHazards()
        scanGenerators()
    end
end)
startLoops()
createHub()
print("✅ ULTIMATE FORSAKEN AI LOADED: Map detection, hazard avoidance, dual-threshold flee, ability usage, and stamina hack active.")
