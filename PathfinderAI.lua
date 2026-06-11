--[[
    ULTIMATE FORSAKEN AI - DEBUG VERSION
    Fixed: Humanoid.Sprint error, movement not triggering
    Added: Rejoin button, console logging for every step
--]]

-- // SERVICES //
local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local UserInputService = game:GetService("UserInputService")
local TeleportService = game:GetService("TeleportService")
local LP = Players.LocalPlayer

-- // STATE //
local AIEnabled = false
local SliderValue = 40
local SafeRadius = SliderValue + 20
local MovingToTarget = false
local ScriptActive = true
local OriginalWalkSpeed = 16
local PlayerChar, Humanoid, RootPart
local Generators = {}
local Killer = nil

-- // DEBUG FUNCTION //
local function log(msg)
    print("[AI DEBUG] " .. msg)
end

-- // UPDATE CHARACTER //
local function updateChar()
    PlayerChar = LP.Character
    if PlayerChar then
        Humanoid = PlayerChar:FindFirstChildOfClass("Humanoid")
        RootPart = PlayerChar:FindFirstChild("HumanoidRootPart")
        if Humanoid and OriginalWalkSpeed == 16 then
            OriginalWalkSpeed = Humanoid.WalkSpeed
            log("Character updated, original walk speed: " .. OriginalWalkSpeed)
        end
    else
        log("No character found")
    end
end

-- // FIXED INFINITE STAMINA (no Sprint property) //
local function applyInfiniteStamina()
    if not Humanoid then return end
    -- Set walk speed to sprint speed (24)
    if Humanoid.WalkSpeed < 24 then
        Humanoid.WalkSpeed = 24
        log("Set walkspeed to 24")
    end
    -- Override any stamina value
    local staminaVal = Humanoid:FindFirstChild("Stamina")
    if staminaVal and staminaVal:IsA("NumberValue") then
        setreadonly(staminaVal, false)
        staminaVal.Value = 100
        setreadonly(staminaVal, true)
    end
    -- Set sprinting attribute (if game uses it)
    Humanoid:SetAttribute("Sprinting", true)
    local sprintBool = PlayerChar and PlayerChar:FindFirstChild("IsSprinting")
    if sprintBool then sprintBool.Value = true end
    -- Remove blur
    for _, effect in pairs(game:GetService("Lighting"):GetChildren()) do
        if effect:IsA("BlurEffect") then effect.Enabled = false end
    end
end

-- // KILLER DETECTION //
local function findKiller()
    for _, plr in pairs(Players:GetPlayers()) do
        if plr ~= LP and plr.Character then
            local char = plr.Character
            if char and char:FindFirstChild("HumanoidRootPart") then
                -- Check team, name, tag
                if (plr.Team and plr.Team.Name:lower():find("killer")) or
                   (plr.Name:lower():find("killer")) or
                   char:FindFirstChild("KillerTag") then
                    return char
                end
            end
        end
    end
    return nil
end

-- // LOBBY DETECTION //
local function isAliveAndInMatch()
    if not PlayerChar or not Humanoid or Humanoid.Health <= 0 then return false end
    local lobby = workspace:FindFirstChild("Lobby") or workspace:FindFirstChild("LobbyArea")
    if lobby and RootPart and (RootPart.Position - lobby.Position).magnitude < 100 then return false end
    return true
end

-- // GENERATOR SCANNER (limit to actual generators) //
local function scanGenerators()
    local newGens = {}
    for _, prompt in pairs(workspace:GetDescendants()) do
        if prompt:IsA("ProximityPrompt") and prompt.Parent then
            local part = prompt.Parent:IsA("BasePart") and prompt.Parent or prompt.Parent:FindFirstChildWhichIsA("BasePart")
            if part and not table.find(newGens, part) then
                -- Only include prompts that are likely generators (name contains "gen" or parent named generator)
                local name = part.Name:lower()
                if name:find("gen") or (prompt.Parent.Name and prompt.Parent.Name:lower():find("gen")) then
                    table.insert(newGens, part)
                end
            end
        end
    end
    Generators = newGens
    log("Scanned generators: " .. #Generators)
    return #Generators
end

-- // SIMPLE MOVE (straight line, guaranteed to work) //
local function moveToPosition(targetPos)
    if not RootPart or not Humanoid then
        log("Cannot move: no RootPart or Humanoid")
        return false
    end
    if MovingToTarget then
        log("Already moving, skipping")
        return false
    end
    MovingToTarget = true
    log("Moving to position: " .. tostring(targetPos))
    Humanoid:MoveTo(targetPos)
    -- Wait a bit to let movement start
    task.wait(0.5)
    MovingToTarget = false
    return true
end

-- // INTERACT WITH GENERATOR //
local function interactWithGenerator(gen)
    log("Attempting to interact with generator: " .. gen.Name)
    local prompt = gen:FindFirstChildWhichIsA("ProximityPrompt")
    if prompt then
        pcall(function()
            prompt:InputHoldStart()
            task.wait(0.3)
            prompt:InputHoldEnd()
            log("Generator interaction sent")
        end)
    else
        log("No proximity prompt found on generator")
    end
end

-- // FLEE FROM KILLER (simple straight line flee) //
local function fleeFromKiller()
    if not Killer or not RootPart then return end
    local killerRoot = Killer:FindFirstChild("HumanoidRootPart")
    if not killerRoot then return end
    local myPos = RootPart.Position
    local killerPos = killerRoot.Position
    local dist = (myPos - killerPos).magnitude
    if dist <= SliderValue then
        local direction = (myPos - killerPos).unit
        local fleePos = myPos + direction * 40
        fleePos = Vector3.new(math.clamp(fleePos.X, -500, 500), fleePos.Y, math.clamp(fleePos.Z, -500, 500))
        log("Fleeing from killer at distance " .. dist .. " to " .. tostring(fleePos))
        moveToPosition(fleePos)
    end
end

-- // MAIN AI LOOP //
local function aiTick()
    if not AIEnabled then return end
    if not isAliveAndInMatch() then
        log("Not alive or in lobby, skipping AI")
        return
    end
    if not PlayerChar or not Humanoid or not RootPart then
        updateChar()
        if not PlayerChar then
            log("Waiting for character...")
            return
        end
    end

    -- Check killer
    Killer = findKiller()
    if Killer then
        local killerRoot = Killer:FindFirstChild("HumanoidRootPart")
        if killerRoot then
            local dist = (RootPart.Position - killerRoot.Position).magnitude
            log("Killer detected at " .. dist .. " studs (alert: " .. SliderValue .. ")")
            if dist <= SliderValue then
                fleeFromKiller()
                return
            end
        end
    else
        log("No killer detected")
    end

    -- Generator farming
    if #Generators == 0 then
        log("No generators, scanning...")
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
        end
    else
        log("No valid generator found")
    end
end

-- // BACKGROUND LOOP //
task.spawn(function()
    while ScriptActive do
        task.wait(0.5)  -- slower for debugging
        aiTick()
    end
end)

task.spawn(function()
    while ScriptActive do
        task.wait(0.5)
        if AIEnabled then
            applyInfiniteStamina()
        end
    end
end)

task.spawn(function()
    while ScriptActive do
        task.wait(5)
        if AIEnabled then
            scanGenerators()
        end
    end
end)

-- // REJOIN FUNCTION //
local function rejoinServer()
    log("Rejoining server...")
    local placeId = game.PlaceId
    local jobId = game.JobId
    TeleportService:TeleportToPlaceInstance(placeId, jobId, LP)
end

-- // GUI HUB //
local function createHub()
    local sg = Instance.new("ScreenGui")
    sg.Name = "ForsakenAIDebug"
    sg.Parent = game.CoreGui
    sg.ResetOnSpawn = false

    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, 380, 0, 320)
    frame.Position = UDim2.new(0.5, -190, 0.5, -160)
    frame.BackgroundColor3 = Color3.fromRGB(10,10,20)
    frame.BackgroundTransparency = 0.2
    frame.Parent = sg
    Instance.new("UICorner").CornerRadius = UDim.new(0, 12); Instance.new("UICorner").Parent = frame

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1,0,0,35)
    title.BackgroundTransparency = 1
    title.Text = "🔪 FORSAKEN AI (DEBUG) 🔪"
    title.TextColor3 = Color3.fromRGB(255,80,120)
    title.Font = Enum.Font.GothamBold
    title.TextSize = 14
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
    Instance.new("UICorner").CornerRadius = UDim.new(1,0); Instance.new("UICorner").Parent = knob

    local function setSlider(val)
        val = math.clamp(val, 0, 100)
        SliderValue = val
        SafeRadius = val + 20
        fill.Size = UDim2.new(val/100,0,1,0)
        knob.Position = UDim2.new(val/100,-7,0,-4)
        sliderLabel.Text = string.format("Alert: %d (safe: %d)", SliderValue, SafeRadius)
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

    -- Buttons
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

    local disableBtn = Instance.new("TextButton")
    disableBtn.Size = UDim2.new(0, 90, 0, 35)
    disableBtn.Position = UDim2.new(0.65, 0, 0, 235)
    disableBtn.BackgroundColor3 = Color3.fromRGB(180,40,60)
    disableBtn.Text = "❌ CLOSE"
    disableBtn.TextColor3 = Color3.new(1,1,1)
    disableBtn.Font = Enum.Font.GothamBold
    disableBtn.TextSize = 14
    disableBtn.Parent = frame
    Instance.new("UICorner").CornerRadius = UDim.new(0,6); Instance.new("UICorner").Parent = disableBtn

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
        rejoinServer()
    end)

    disableBtn.MouseButton1Click:Connect(function()
        AIEnabled = false
        ScriptActive = false
        sg:Destroy()
        print("🔴 AI script closed. Re-execute to restart.")
    end)

    toggle.MouseButton1Click:Connect(function()
        AIEnabled = not AIEnabled
        if AIEnabled then
            toggle.Text = "🟢 AI ON"
            toggle.BackgroundColor3 = Color3.fromRGB(0,180,80)
            updateChar()
            scanGenerators()
            status.Text = "AI ACTIVE - Check console for movement logs"
            log("AI turned ON")
        else
            toggle.Text = "🔴 AI OFF"
            toggle.BackgroundColor3 = Color3.fromRGB(0,120,200)
            status.Text = "AI OFF"
            log("AI turned OFF")
        end
    end)

    -- Status updater
    task.spawn(function()
        while ScriptActive and sg do
            task.wait(1)
            if AIEnabled then
                local killer = findKiller()
                local kdist = ""
                if killer and RootPart and killer:FindFirstChild("HumanoidRootPart") then
                    local d = (RootPart.Position - killer.HumanoidRootPart.Position).magnitude
                    kdist = string.format(" | Killer: %.0f", d)
                end
                status.Text = string.format("Gens: %d%s | Alert: %d", #Generators, kdist, SliderValue)
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

-- // INIT //
updateChar()
LP.CharacterAdded:Connect(function()
    task.wait(0.5)
    updateChar()
    if AIEnabled then scanGenerators() end
end)
createHub()
log("Script loaded. Toggle AI ON and watch console for movement logs.")
