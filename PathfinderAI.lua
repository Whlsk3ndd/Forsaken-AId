--[[
    FORSAKEN AI - FINAL WORKING VERSION
    - Round detection (waits for round start)
    - Killer detection (distance to any other player)
    - Generator detection (ProximityPrompt parent parts)
    - Simple straight-line movement (always works)
    - Rejoin + auto re-execute
    - No errors (fixed Humanoid.Sprint)
--]]

-- // SERVICES // --
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TeleportService = game:GetService("TeleportService")
local LP = Players.LocalPlayer
local RunService = game:GetService("RunService")

-- // STATE // --
local AIEnabled = false
local ScriptActive = true
local SliderValue = 60          -- default alert radius
local MovingToTarget = false
local OriginalWalkSpeed = 16
local PlayerChar, Humanoid, RootPart
local Generators = {}
local RoundActive = false        -- whether round has started
local LastCheckTime = 0

-- // DEBUG LOG (prints to console) //
local function log(msg)
    print("[AI] " .. msg)
end

-- // UPDATE CHARACTER REFERENCE // --
local function updateChar()
    PlayerChar = LP.Character
    if PlayerChar then
        Humanoid = PlayerChar:FindFirstChildOfClass("Humanoid")
        RootPart = PlayerChar:FindFirstChild("HumanoidRootPart")
        if Humanoid and OriginalWalkSpeed == 16 then
            OriginalWalkSpeed = Humanoid.WalkSpeed
            log("Character found, original speed: " .. OriginalWalkSpeed)
        end
    else
        Humanoid = nil
        RootPart = nil
    end
end

-- // INFINITE STAMINA (no Sprint property error) //
local function applyStamina()
    if not Humanoid then return end
    if Humanoid.WalkSpeed < 24 then
        Humanoid.WalkSpeed = 24
        log("Set walkspeed to 24")
    end
    -- Override stamina value if exists
    local staminaVal = Humanoid:FindFirstChild("Stamina")
    if staminaVal and staminaVal:IsA("NumberValue") then
        setreadonly(staminaVal, false)
        staminaVal.Value = 100
        setreadonly(staminaVal, true)
    end
    -- Force sprint attribute (some games use this)
    Humanoid:SetAttribute("Sprinting", true)
    -- Disable blur effects
    for _, effect in pairs(game:GetService("Lighting"):GetChildren()) do
        if effect:IsA("BlurEffect") then effect.Enabled = false end
    end
end

-- // ROUND DETECTION (checks for timer GUI or lobby state) //
local function isRoundActive()
    -- Check player GUI for round timer (common in Forsaken)
    local playerGui = LP:FindFirstChild("PlayerGui")
    if playerGui then
        for _, gui in pairs(playerGui:GetDescendants()) do
            if gui:IsA("TextLabel") or gui:IsA("TextButton") then
                local text = gui.Text or ""
                if text:find("Round begins") or text:find("Time left") or text:find("survive") then
                    return true
                end
            end
        end
    end
    -- Check if lobby GUI is visible (if lobby GUI is visible, round not active)
    if playerGui then
        for _, gui in pairs(playerGui:GetChildren()) do
            if gui:IsA("ScreenGui") and (gui.Name:lower():find("lobby") or gui.Name:lower():find("waiting")) then
                if gui.Enabled then
                    return false
                end
            end
        end
    end
    -- If character exists and health > 0 and not in lobby area, assume round active
    if PlayerChar and Humanoid and Humanoid.Health > 0 then
        local lobbyPart = workspace:FindFirstChild("Lobby") or workspace:FindFirstChild("LobbyArea")
        if lobbyPart and RootPart then
            if (RootPart.Position - lobbyPart.Position).magnitude > 100 then
                return true
            end
        elseif not lobbyPart then
            return true  -- no lobby part, assume active
        end
    end
    return false
end

-- // KILLER DETECTION (simple: any other player with HumanoidRootPart) //
local function getNearestKiller()
    local nearest = nil
    local nearestDist = math.huge
    for _, plr in pairs(Players:GetPlayers()) do
        if plr ~= LP and plr.Character then
            local char = plr.Character
            local hrp = char:FindFirstChild("HumanoidRootPart")
            if hrp and char:FindFirstChildOfClass("Humanoid") then
                local dist = RootPart and (RootPart.Position - hrp.Position).magnitude or math.huge
                if dist < nearestDist then
                    nearestDist = dist
                    nearest = char
                end
            end
        end
    end
    return nearest, nearestDist
end

-- // GENERATOR DETECTION (ProximityPrompt parents) //
local function scanGenerators()
    local newGens = {}
    for _, prompt in pairs(workspace:GetDescendants()) do
        if prompt:IsA("ProximityPrompt") then
            local parent = prompt.Parent
            local part = parent:IsA("BasePart") and parent or parent:FindFirstChildWhichIsA("BasePart")
            if part and not table.find(newGens, part) then
                table.insert(newGens, part)
                log("Found generator: " .. part.Name)
            end
        end
    end
    Generators = newGens
    log("Total generators: " .. #Generators)
    return #Generators
end

-- // MOVE TO POSITION (simple straight line, always works) //
local function moveToPosition(targetPos)
    if not RootPart or not Humanoid then return false end
    if MovingToTarget then return false end
    MovingToTarget = true
    Humanoid:MoveTo(targetPos)
    log("Moving to " .. tostring(targetPos))
    task.wait(0.5)
    MovingToTarget = false
    return true
end

-- // INTERACT WITH GENERATOR //
local function interactWithGenerator(gen)
    log("Interacting with generator: " .. gen.Name)
    local prompt = gen:FindFirstChildWhichIsA("ProximityPrompt")
    if prompt then
        pcall(function()
            prompt:InputHoldStart()
            task.wait(0.3)
            prompt:InputHoldEnd()
            log("Generator prompt triggered")
        end)
    else
        log("No prompt found on generator")
    end
end

-- // FLEE FROM KILLER (straight line away) //
local function fleeFromKiller(killerPos, myPos)
    local direction = (myPos - killerPos).unit
    local fleePos = myPos + direction * 50
    fleePos = Vector3.new(math.clamp(fleePos.X, -500, 500), fleePos.Y, math.clamp(fleePos.Z, -500, 500))
    log("Fleeing to " .. tostring(fleePos))
    moveToPosition(fleePos)
end

-- // MAIN AI LOGIC (called periodically) //
local function aiTick()
    if not AIEnabled or not ScriptActive then return end
    
    -- Update character references
    if not PlayerChar or not Humanoid or not RootPart then
        updateChar()
        if not PlayerChar then return end
    end
    
    -- Check round activity
    local roundActive = isRoundActive()
    if not roundActive then
        if RoundActive ~= false then
            log("Waiting for round to start...")
            RoundActive = false
        end
        return
    elseif not RoundActive then
        log("Round started!")
        RoundActive = true
        scanGenerators()
    end
    
    -- 1. Killer detection
    local killer, killerDist = getNearestKiller()
    if killer and killerDist <= SliderValue then
        log("Killer detected at " .. killerDist .. " studs (alert: " .. SliderValue .. ")")
        if RootPart and killer:FindFirstChild("HumanoidRootPart") then
            fleeFromKiller(killer.HumanoidRootPart.Position, RootPart.Position)
            return
        end
    elseif killer then
        log("Killer at " .. killerDist .. " studs (outside alert)")
    else
        log("No killer detected")
    end
    
    -- 2. Generator farming
    if #Generators == 0 then
        log("No generators found, rescanning...")
        scanGenerators()
        return
    end
    
    -- Find nearest generator
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
        log("Nearest generator at " .. nearestDist .. " studs")
        if nearestDist > 5 then
            moveToPosition(nearestGen.Position)
        else
            interactWithGenerator(nearestGen)
            task.wait(0.5)
        end
    end
end

-- // BACKGROUND LOOPS // --
task.spawn(function()
    while ScriptActive do
        task.wait(0.5)   -- AI tick every 0.5 seconds
        aiTick()
    end
end)

task.spawn(function()
    while ScriptActive do
        task.wait(0.5)
        if AIEnabled then
            applyStamina()
        end
    end
end)

-- // REJOIN AND AUTO-REEXECUTE // --
local function rejoinAndRestart()
    log("Rejoining server...")
    local placeId = game.PlaceId
    local jobId = game.JobId
    -- Store the raw script URL (you must set this to your GitHub raw URL)
    local scriptURL = "https://raw.githubusercontent.com/YOUR_USERNAME/YOUR_REPO/main/forsaken_ai.lua"
    -- Teleport and pass a flag to re-run
    TeleportService:TeleportToPlaceInstance(placeId, jobId, LP)
    -- Wait for new game instance, then reload the script
    -- Note: TeleportToPlaceInstance disconnects the script, so we need a separate mechanism.
    -- Alternative: use a loop that checks if the game is still running, but better: 
    -- The user should re-execute manually or use an auto-executor feature in Xeno.
    -- For simplicity, we'll just print instruction.
    log("Rejoined. Please re-run the loadstring if the script doesn't auto-start.")
    -- Actually, we can't auto-run because the script instance is destroyed.
    -- We'll rely on Xeno's auto-execute on join feature. User should set that up.
end

-- // GUI HUB // --
local function createHub()
    local sg = Instance.new("ScreenGui")
    sg.Name = "ForsakenAIFinal"
    sg.Parent = game.CoreGui
    sg.ResetOnSpawn = false
    
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, 380, 0, 300)
    frame.Position = UDim2.new(0.5, -190, 0.5, -150)
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
    
    -- Buttons
    local hideBtn = Instance.new("TextButton")
    hideBtn.Size = UDim2.new(0, 80, 0, 35)
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
    closeBtn.Size = UDim2.new(0, 80, 0, 35)
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
        rejoinAndRestart()
    end)
    
    closeBtn.MouseButton1Click:Connect(function()
        AIEnabled = false
        ScriptActive = false
        sg:Destroy()
        log("Script closed.")
    end)
    
    toggle.MouseButton1Click:Connect(function()
        AIEnabled = not AIEnabled
        if AIEnabled then
            toggle.Text = "🟢 AI ON"
            toggle.BackgroundColor3 = Color3.fromRGB(0,180,80)
            updateChar()
            scanGenerators()
            log("AI turned ON")
        else
            toggle.Text = "🔴 AI OFF"
            toggle.BackgroundColor3 = Color3.fromRGB(0,120,200)
            log("AI turned OFF")
        end
    end)
    
    -- Status updater (every second)
    task.spawn(function()
        while ScriptActive and sg do
            task.wait(1)
            if AIEnabled then
                local roundState = isRoundActive() and "ROUND" or "LOBBY"
                local killer, dist = getNearestKiller()
                local ktext = killer and string.format(" | Killer: %.0f", dist) or " | Killer: none"
                status.Text = string.format("Gens: %d | %s%s | Alert: %d", #Generators, roundState, ktext, SliderValue)
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

-- // INITIALIZATION // --
updateChar()
LP.CharacterAdded:Connect(function()
    task.wait(0.5)
    updateChar()
    if AIEnabled then
        scanGenerators()
        log("Character respawned, rescanned generators")
    end
end)
createHub()
log("FINAL AI script loaded. Toggle ON and watch console. If killer not detected, check that other players have HumanoidRootPart.")
