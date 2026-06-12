--[[
    FORSAKEN AI – XENO COMPATIBLE
    Uses only standard Roblox APIs – no VirtualInput, no TeleportService
--]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local LP = Players.LocalPlayer

-- State
local AIEnabled = false
local ScriptActive = true
local SliderValue = 40
local PlayerChar, Humanoid, RootPart
local Generators = {}
local CompletedGenerators = {}
local CurrentAction = "Idle"

-- Constants
local WALK_SPEED = 24

-- Helper: update character reference
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

-- Killer detection: any other player with HumanoidRootPart
local function getNearestKillerDistance()
    if not RootPart then return math.huge end
    local nearest = math.huge
    for _, plr in pairs(Players:GetPlayers()) do
        if plr ~= LP and plr.Character then
            local hrp = plr.Character:FindFirstChild("HumanoidRootPart")
            if hrp then
                local dist = (RootPart.Position - hrp.Position).magnitude
                if dist < nearest then nearest = dist end
            end
        end
    end
    return nearest
end

-- Generator scanning – look for ProximityPrompt with "Generator" in name
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
    print("Found " .. #Generators .. " generators")
    return #Generators
end

-- Interact with generator using Prompt() – no key holding needed
local function interactWithGenerator(gen)
    print("Interacting with generator: " .. gen.Name)
    local prompt = gen:FindFirstChildWhichIsA("ProximityPrompt")
    if prompt then
        pcall(function()
            prompt:Prompt()
        end)
        wait(0.5)
        return true
    end
    return false
end

-- Simple movement
local function moveToGenerator(gen)
    if not RootPart or not Humanoid then return end
    Humanoid:MoveTo(gen.Position)
end

-- Flee from killer (straight line)
local function fleeFromKiller()
    if not RootPart or not Humanoid then return end
    local nearestDist = math.huge
    local killerPos = nil
    for _, plr in pairs(Players:GetPlayers()) do
        if plr ~= LP and plr.Character then
            local hrp = plr.Character:FindFirstChild("HumanoidRootPart")
            if hrp then
                local dist = (RootPart.Position - hrp.Position).magnitude
                if dist < nearestDist then
                    nearestDist = dist
                    killerPos = hrp.Position
                end
            end
        end
    end
    if killerPos then
        local direction = (RootPart.Position - killerPos).unit
        local fleePos = RootPart.Position + direction * 40
        Humanoid:MoveTo(fleePos)
    end
end

-- Infinite stamina – only walk speed increase (safe)
local function applyStamina()
    if not Humanoid then return end
    if Humanoid.WalkSpeed < WALK_SPEED then
        Humanoid.WalkSpeed = WALK_SPEED
    end
    -- Try to set attribute (safe)
    pcall(function()
        Humanoid:SetAttribute("Sprinting", true)
    end)
    -- Remove blur effect if possible
    for _, effect in pairs(game:GetService("Lighting"):GetChildren()) do
        if effect:IsA("BlurEffect") then
            pcall(function() effect.Enabled = false end)
        end
    end
end

-- Main AI loop
local function aiTick()
    if not AIEnabled then return end
    if not PlayerChar or not Humanoid or not RootPart then
        updateChar()
        return
    end

    -- 1. Killer avoidance
    local killerDist = getNearestKillerDistance()
    if killerDist <= SliderValue then
        CurrentAction = "Fleeing"
        fleeFromKiller()
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
                CompletedGenerators[nearestGen] = true
                for i, g in pairs(Generators) do
                    if g == nearestGen then table.remove(Generators, i); break end
                end
            end
            wait(1)
        end
    end
end

-- Background loops
spawn(function()
    while ScriptActive do
        wait(0.5)
        aiTick()
    end
end)

spawn(function()
    while ScriptActive do
        wait(0.5)
        if AIEnabled then applyStamina() end
    end
end)

spawn(function()
    while ScriptActive do
        wait(5)
        if AIEnabled then scanGenerators() end
    end
end)

-- GUI (same as minimal test, but with AI controls)
local function createHub()
    local sg = Instance.new("ScreenGui")
    sg.Name = "ForsakenAI"
    sg.Parent = game.CoreGui
    sg.ResetOnSpawn = false

    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, 320, 0, 280)
    frame.Position = UDim2.new(0.5, -160, 0.5, -140)
    frame.BackgroundColor3 = Color3.fromRGB(10, 10, 20)
    frame.BackgroundTransparency = 0.2
    frame.Parent = sg
    Instance.new("UICorner").CornerRadius = UDim.new(0, 12)

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, 0, 0, 35)
    title.BackgroundTransparency = 1
    title.Text = "⚡ FORSAKEN AI ⚡"
    title.TextColor3 = Color3.fromRGB(0, 200, 255)
    title.Font = Enum.Font.GothamBold
    title.TextSize = 16
    title.Parent = frame

    local toggle = Instance.new("TextButton")
    toggle.Size = UDim2.new(0, 200, 0, 45)
    toggle.Position = UDim2.new(0.5, -100, 0, 50)
    toggle.BackgroundColor3 = Color3.fromRGB(0, 120, 200)
    toggle.Text = "🔴 AI OFF"
    toggle.TextColor3 = Color3.new(1, 1, 1)
    toggle.Font = Enum.Font.GothamBold
    toggle.TextSize = 18
    toggle.Parent = frame
    Instance.new("UICorner").CornerRadius = UDim.new(0, 8)

    -- Slider
    local sliderFrame = Instance.new("Frame")
    sliderFrame.Size = UDim2.new(0, 260, 0, 50)
    sliderFrame.Position = UDim2.new(0.5, -130, 0, 110)
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

    local hideBtn = Instance.new("TextButton")
    hideBtn.Size = UDim2.new(0, 90, 0, 35)
    hideBtn.Position = UDim2.new(0.05, 0, 0, 240)
    hideBtn.BackgroundColor3 = Color3.fromRGB(80, 80, 100)
    hideBtn.Text = "⛔ HIDE"
    hideBtn.TextColor3 = Color3.new(1, 1, 1)
    hideBtn.Font = Enum.Font.GothamBold
    hideBtn.TextSize = 13
    hideBtn.Parent = frame
    Instance.new("UICorner").CornerRadius = UDim.new(0, 6)

    local closeBtn = Instance.new("TextButton")
    closeBtn.Size = UDim2.new(0, 90, 0, 35)
    closeBtn.Position = UDim2.new(0.65, 0, 0, 240)
    closeBtn.BackgroundColor3 = Color3.fromRGB(180, 40, 60)
    closeBtn.Text = "❌ CLOSE"
    closeBtn.TextColor3 = Color3.new(1, 1, 1)
    closeBtn.Font = Enum.Font.GothamBold
    closeBtn.TextSize = 13
    closeBtn.Parent = frame
    Instance.new("UICorner").CornerRadius = UDim.new(0, 6)

    local showBtn = nil
    hideBtn.MouseButton1Click:Connect(function()
        frame.Visible = false
        if not showBtn then
            showBtn = Instance.new("TextButton")
            showBtn.Size = UDim2.new(0, 80, 0, 30)
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
                showBtn:Destroy()
                showBtn = nil
            end)
        end
    end)

    closeBtn.MouseButton1Click:Connect(function()
        AIEnabled = false
        ScriptActive = false
        sg:Destroy()
        print("AI script closed.")
    end)

    toggle.MouseButton1Click:Connect(function()
        AIEnabled = not AIEnabled
        if AIEnabled then
            toggle.Text = "🟢 AI ON"
            toggle.BackgroundColor3 = Color3.fromRGB(0, 180, 80)
            updateChar()
            scanGenerators()
            status.Text = "AI ACTIVE"
        else
            toggle.Text = "🔴 AI OFF"
            toggle.BackgroundColor3 = Color3.fromRGB(0, 120, 200)
            status.Text = "AI OFF"
        end
    end)

    -- Update status every second
    spawn(function()
        while ScriptActive and sg do
            wait(1)
            if AIEnabled then
                local kd = getNearestKillerDistance()
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
        end
    end)
end

-- Start
updateChar()
createHub()
print("Forsaken AI loaded. Toggle ON to start.")
