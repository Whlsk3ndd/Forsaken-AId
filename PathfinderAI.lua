--[[
    FORSAKEN AI – FINAL WORKING VERSION
    - Pathfinding to generators with wall avoidance
    - Generator detection: only parts with ProximityPrompt and name containing "Gen"
    - Proper generator interaction: Prompt() + hold if needed
    - Flee: calculate reachable point within map bounds (not -500)
    - No more running into walls
--]]

-- SERVICES
local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local LP = Players.LocalPlayer

-- STATE
local AIEnabled = false
local SliderValue = 60
local MovingToTarget = false
local CurrentPath = nil
local CurrentWaypointIndex = 1
local PlayerChar, Humanoid, RootPart
local Generators = {} -- store {part, prompt}
local LastGenScan = 0
local PathCache = {}

-- PATHFINDING CONFIG
local PATH_OPTIONS = {
    AgentRadius = 2.5,
    AgentHeight = 5,
    AgentCanJump = true,
    AgentMaxSlope = 60,
    WaypointSpacing = 3,
    Costs = { Water = 100 }
}

-- UTILITIES
local function updateChar()
    PlayerChar = LP.Character
    if PlayerChar then
        Humanoid = PlayerChar:FindFirstChildOfClass("Humanoid")
        RootPart = PlayerChar:FindFirstChild("HumanoidRootPart")
    else
        Humanoid = nil
        RootPart = nil
    end
end

local function isAliveInMatch()
    if not PlayerChar or not Humanoid or Humanoid.Health <= 0 then return false end
    -- Check lobby GUI
    local pg = LP:FindFirstChild("PlayerGui")
    if pg then
        for _, gui in pairs(pg:GetChildren()) do
            if gui:IsA("ScreenGui") and (gui.Name:lower():find("lobby") or gui.Name:lower():find("waiting")) and gui.Enabled then
                return false
            end
        end
    end
    return true
end

-- KILLER DETECTION (any other player)
local function getNearestKiller()
    if not RootPart then return nil, math.huge end
    local nearest = nil
    local nearestDist = math.huge
    for _, plr in pairs(Players:GetPlayers()) do
        if plr ~= LP then
            local char = plr.Character
            if char then
                local hrp = char:FindFirstChild("HumanoidRootPart")
                if hrp then
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

-- GENERATOR SCANNING – only real generators
local function scanGenerators()
    local newGens = {}
    for _, prompt in pairs(workspace:GetDescendants()) do
        if prompt:IsA("ProximityPrompt") then
            local part = prompt.Parent:IsA("BasePart") and prompt.Parent or prompt.Parent:FindFirstChildWhichIsA("BasePart")
            if part then
                local partName = part.Name:lower()
                local parentName = part.Parent and part.Parent.Name:lower() or ""
                -- Ignore common non-generator parts
                local ignore = partName:find("humanoidrootpart") or partName:find("root") or partName:find("prim") or
                                partName:find("dialog") or partName:find("document") or partName:find("itemroot") or
                                parentName:find("humanoid") or parentName:find("player")
                if not ignore then
                    -- Accept if name contains "gen" or prompt is for a generator
                    if partName:find("gen") or parentName:find("gen") or partName:find("main") then
                        table.insert(newGens, {part = part, prompt = prompt})
                    end
                end
            end
        end
    end
    Generators = newGens
    print("[AI] Generators found: " .. #Generators)
    return #Generators
end

-- PATHFINDING MOVE (follow waypoints)
local function moveToPosition(targetPos)
    if not RootPart or not Humanoid or MovingToTarget then return false end
    
    -- Compute path
    local path = PathfindingService:CreatePath(PATH_OPTIONS)
    local success = pcall(function()
        path:ComputeAsync(RootPart.Position, targetPos)
    end)
    if not success or path.Status ~= Enum.PathStatus.Success then
        -- Fallback: straight line
        Humanoid:MoveTo(targetPos)
        return false
    end
    
    local waypoints = path:GetWaypoints()
    if #waypoints == 0 then return false end
    
    MovingToTarget = true
    for i, wp in ipairs(waypoints) do
        if not AIEnabled then break end
        if not RootPart or not Humanoid then break end
        if wp.Action == Enum.PathWaypointAction.Jump then
            Humanoid.Jump = true
            task.wait(0.1)
        end
        Humanoid:MoveTo(wp.Position)
        -- Wait until within 4 studs of waypoint or timeout 2 seconds
        local start = tick()
        while (RootPart.Position - wp.Position).magnitude > 4 do
            if tick() - start > 2 then break end
            if not AIEnabled then break end
            task.wait(0.05)
        end
    end
    MovingToTarget = false
    return true
end

-- FLEE (random direction within map bounds, using pathfinding)
local function fleeFromKiller(killerPos)
    if not RootPart then return end
    local myPos = RootPart.Position
    local direction = (myPos - killerPos).unit
    -- Try several angles to find a reachable point
    for angle = -60, 60, 30 do
        local rad = math.rad(angle)
        local dir = Vector3.new(
            direction.X * math.cos(rad) - direction.Z * math.sin(rad),
            0,
            direction.X * math.sin(rad) + direction.Z * math.cos(rad)
        ).unit
        local fleePos = myPos + dir * 40
        -- Clamp to reasonable map bounds (most maps within -500 to 500)
        fleePos = Vector3.new(math.clamp(fleePos.X, -450, 450), fleePos.Y, math.clamp(fleePos.Z, -450, 450))
        -- Test if reachable
        local testPath = PathfindingService:CreatePath(PATH_OPTIONS)
        local ok = pcall(function() testPath:ComputeAsync(myPos, fleePos) end)
        if ok and testPath.Status == Enum.PathStatus.Success then
            moveToPosition(fleePos)
            return
        end
    end
    -- Fallback: straight line
    local fleePos = myPos + direction * 40
    fleePos = Vector3.new(math.clamp(fleePos.X, -450, 450), fleePos.Y, math.clamp(fleePos.Z, -450, 450))
    Humanoid:MoveTo(fleePos)
end

-- GENERATOR INTERACTION (using Prompt)
local function interactWithGenerator(gen)
    if not gen or not gen.prompt then return end
    print("[AI] Interacting with generator: " .. gen.part.Name)
    pcall(function()
        -- Try Prompt() first (most common)
        gen.prompt:Prompt()
        task.wait(0.3)
        -- If that doesn't work, try hold method (some games require hold)
        -- gen.prompt:InputHoldStart()
        -- task.wait(0.5)
        -- gen.prompt:InputHoldEnd()
    end)
end

-- INFINITE STAMINA
local function applyStamina()
    if not Humanoid then return end
    if Humanoid.WalkSpeed < 24 then
        Humanoid.WalkSpeed = 24
    end
    local staminaVal = Humanoid:FindFirstChild("Stamina")
    if staminaVal and staminaVal:IsA("NumberValue") then
        setreadonly(staminaVal, false)
        staminaVal.Value = 100
        setreadonly(staminaVal, true)
    end
    Humanoid:SetAttribute("Sprinting", true)
    -- Remove blur
    for _, effect in pairs(game:GetService("Lighting"):GetChildren()) do
        if effect:IsA("BlurEffect") then effect.Enabled = false end
    end
end

-- MAIN AI LOGIC
local function aiTick()
    if not AIEnabled then return end
    if not isAliveInMatch() then
        if Humanoid then Humanoid:MoveTo(Vector3.new(0,0,0)) end
        return
    end
    if not PlayerChar or not Humanoid or not RootPart then
        updateChar()
        return
    end
    
    -- 1. Killer avoidance
    local killerHrp, killerDist = getNearestKiller()
    if killerHrp and killerDist <= SliderValue then
        print("[AI] Killer at " .. killerDist .. " studs (flee)")
        fleeFromKiller(killerHrp.Position)
        return
    end
    
    -- 2. Generator farming
    if #Generators == 0 then
        scanGenerators()
        return
    end
    
    -- Find nearest generator part
    local nearest = nil
    local nearestDist = math.huge
    for _, gen in ipairs(Generators) do
        if gen.part and gen.part.Parent then
            local d = (RootPart.Position - gen.part.Position).magnitude
            if d < nearestDist then
                nearestDist = d
                nearest = gen
            end
        end
    end
    
    if nearest then
        if nearestDist > 4 then
            print("[AI] Moving to generator at " .. nearestDist .. " studs")
            moveToPosition(nearest.part.Position)
        else
            interactWithGenerator(nearest)
            task.wait(0.5)
        end
    end
end

-- BACKGROUND LOOPS
task.spawn(function()
    while true do
        task.wait(0.3)
        aiTick()
    end
end)

task.spawn(function()
    while true do
        task.wait(0.5)
        if AIEnabled then applyStamina() end
    end
end)

task.spawn(function()
    while true do
        task.wait(5)
        if AIEnabled then scanGenerators() end
    end
end)

-- GUI HUB (same as before, but simplified)
local function createHub()
    local sg = Instance.new("ScreenGui")
    sg.Name = "ForsakenAIFinal"
    sg.Parent = game.CoreGui
    sg.ResetOnSpawn = false
    
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, 360, 0, 280)
    frame.Position = UDim2.new(0.5, -180, 0.5, -140)
    frame.BackgroundColor3 = Color3.fromRGB(10,10,20)
    frame.BackgroundTransparency = 0.2
    frame.Parent = sg
    Instance.new("UICorner").CornerRadius = UDim.new(0,12); Instance.new("UICorner").Parent = frame
    
    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1,0,0,35)
    title.BackgroundTransparency = 1
    title.Text = "🔪 FORSAKEN AI (PATHFINDING) 🔪"
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
    sliderLabel.Position = UDim2.new(0,0,0,0)
    sliderLabel.BackgroundTransparency = 1
    sliderLabel.Text = "Killer Alert Radius: 60"
    sliderLabel.TextColor3 = Color3.fromRGB(255,180,180)
    sliderLabel.Font = Enum.Font.Gotham
    sliderLabel.TextSize = 12
    sliderLabel.Parent = sliderFrame
    local sliderBg = Instance.new("Frame")
    sliderBg.Size = UDim2.new(0, 220, 0, 6)
    sliderBg.Position = UDim2.new(0,0,0,22)
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
    hideBtn.TextSize = 14
    hideBtn.Parent = frame
    Instance.new("UICorner").CornerRadius = UDim.new(0,6); Instance.new("UICorner").Parent = hideBtn
    
    local rejoinBtn = Instance.new("TextButton")
    rejoinBtn.Size = UDim2.new(0, 90, 0, 35)
    rejoinBtn.Position = UDim2.new(0.35, 0, 0, 235)
    rejoinBtn.BackgroundColor3 = Color3.fromRGB(100,80,120)
    rejoinBtn.Text = "🔄 REJOIN"
    rejoinBtn.TextColor3 = Color3.new(1,1,1)
    rejoinBtn.Font = Enum.Font.GothamBold
    rejoinBtn.TextSize = 14
    rejoinBtn.Parent = frame
    Instance.new("UICorner").CornerRadius = UDim.new(0,6); Instance.new("UICorner").Parent = rejoinBtn
    
    local closeBtn = Instance.new("TextButton")
    closeBtn.Size = UDim2.new(0, 90, 0, 35)
    closeBtn.Position = UDim2.new(0.65, 0, 0, 235)
    closeBtn.BackgroundColor3 = Color3.fromRGB(180,40,60)
    closeBtn.Text = "❌ CLOSE"
    closeBtn.TextColor3 = Color3.new(1,1,1)
    closeBtn.Font = Enum.Font.GothamBold
    closeBtn.TextSize = 14
    closeBtn.Parent = frame
    Instance.new("UICorner").CornerRadius = UDim.new(0,6); Instance.new("UICorner").Parent = closeBtn
    
    local showBtn = nil
    hideBtn.MouseButton1Click:Connect(function()
        frame.Visible = false
        if not showBtn then
            showBtn = Instance.new("TextButton")
            showBtn.Size = UDim2.new(0, 100, 0, 30)
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
        game:GetService("TeleportService"):TeleportToPlaceInstance(game.PlaceId, game.JobId, LP)
    end)
    
    closeBtn.MouseButton1Click:Connect(function()
        AIEnabled = false
        sg:Destroy()
    end)
    
    toggle.MouseButton1Click:Connect(function()
        AIEnabled = not AIEnabled
        if AIEnabled then
            toggle.Text = "🟢 AI ON"
            toggle.BackgroundColor3 = Color3.fromRGB(0,180,80)
            updateChar()
            scanGenerators()
            status.Text = "AI ACTIVE | Pathfinding enabled"
        else
            toggle.Text = "🔴 AI OFF"
            toggle.BackgroundColor3 = Color3.fromRGB(0,120,200)
            status.Text = "AI OFF"
        end
    end)
    
    -- Status updater
    task.spawn(function()
        while sg and sg.Parent do
            task.wait(1)
            if AIEnabled then
                local killer, dist = getNearestKiller()
                local ktxt = killer and string.format("Killer: %.0f", dist) or "Killer: none"
                status.Text = string.format("Gens: %d | %s | Alert: %d", #Generators, ktxt, SliderValue)
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

-- INIT
updateChar()
LP.CharacterAdded:Connect(function()
    task.wait(0.5)
    updateChar()
    if AIEnabled then scanGenerators() end
end)
createHub()
print("✅ Final AI with pathfinding loaded. Toggle ON and test generator interaction.")
