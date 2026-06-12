--[[
    ███████╗ ██████╗ ██████╗ ███████╗ █████╗ ██╗  ██╗███████╗███╗   ██╗
    ██╔════╝██╔═══██╗██╔══██╗██╔════╝██╔══██╗██║ ██╔╝██╔════╝████╗  ██║
    ███████╗██║   ██║██████╔╝█████╗  ███████║█████╔╝ █████╗  ██╔██╗ ██║
    ╚════██║██║   ██║██╔══██╗██╔══╝  ██╔══██║██╔═██╗ ██╔══╝  ██║╚██╗██║
    ███████║╚██████╔╝██║  ██║██║     ██║  ██║██║  ██╗███████╗██║ ╚████║
    ╚══════╝ ╚═════╝ ╚═╝  ╚═╝╚═╝     ╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝╚═╝  ╚═══╝

    ULTIMATE FORSAKEN AI - STABLE EDITION
    + getgenv() LoadTime delay
    + No crashing (pcall safety)
    + Mouse drag for minigame (click & drag dots)
    + Rejoin button + Cool GUI
--]]

-- // GETGENV SETTINGS (safe) //
if getgenv then
    getgenv().LoadTime = getgenv().LoadTime or "5"      -- Delay before loading
    getgenv().DiscordWebhook = getgenv().DiscordWebhook or ""
    getgenv().GeneratorTime = getgenv().GeneratorTime or "2.5"  -- Hold time
end

local loadTime = tonumber(getgenv and getgenv().LoadTime or 5) or 5
if loadTime > 0 then
    print("Waiting " .. loadTime .. " seconds before loading...")
    wait(loadTime)
end

-- // SERVICES // --
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local VirtualInput = game:GetService("VirtualInput")
local TeleportService = game:GetService("TeleportService")
local TweenService = game:GetService("TweenService")
local LP = Players.LocalPlayer

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
local HOLD_TIME = tonumber(getgenv and getgenv().GeneratorTime or 2.5) or 2.5

-- // KILLER NAMES // --
local KILLER_NAMES = {
    "slasher", "c00lkidd", "john doe", "1x1x1x1", "noli", "guest 666", "nosferatu",
    "subject 0", "pursuer", "killer kyle", "stitchhare", "mafioso", "bluudud",
    "divadayo", "gasharpoon", "annihilation", "aberrant", "admin romeo", "narrator"
}

-- // SAFE PRINT (prevents crashes) //
local function DebugLog(msg)
    pcall(function() print("[AI] " .. msg) end)
end

-- // UPDATE CHARACTER // --
local function updateChar()
    pcall(function()
        PlayerChar = LP.Character
        if PlayerChar then
            Humanoid = PlayerChar:FindFirstChildOfClass("Humanoid")
            RootPart = PlayerChar:FindFirstChild("HumanoidRootPart")
            if Humanoid and Humanoid.WalkSpeed < WALK_SPEED then
                Humanoid.WalkSpeed = WALK_SPEED
            end
        end
    end)
end

-- // KILLER DETECTION // --
local function getNearestKiller()
    if not RootPart then return nil, math.huge end
    local nearestObj = nil
    local nearestDist = math.huge
    for _, plr in pairs(Players:GetPlayers()) do
        if plr ~= LP and plr.Character then
            local hrp = plr.Character:FindFirstChild("HumanoidRootPart")
            if hrp then
                local name = plr.Name:lower()
                local isKiller = false
                for _, k in pairs(KILLER_NAMES) do
                    if name:find(k) then isKiller = true; break end
                end
                if not isKiller and plr.Team and plr.Team.Name:lower():find("killer") then isKiller = true end
                if not isKiller and plr.Character:FindFirstChild("KillerTag") then isKiller = true end
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
    pcall(function()
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
    end)
    Generators = newGens
    DebugLog("Found " .. #Generators .. " generators")
    return #Generators
end

-- // MOUSE DRAG FUNCTION (for minigame) // --
local function dragMouse(fromPos, toPos)
    pcall(function()
        VirtualInput:SendMouseButtonEvent(fromPos.X, fromPos.Y, 0, true, game, 0)
        wait(0.05)
        -- Smooth drag
        for t = 0, 1, 0.1 do
            local x = fromPos.X + (toPos.X - fromPos.X) * t
            local y = fromPos.Y + (toPos.Y - fromPos.Y) * t
            VirtualInput:SendMouseMoveEvent(x, y, game, 0)
            wait(0.02)
        end
        VirtualInput:SendMouseButtonEvent(toPos.X, toPos.Y, 0, false, game, 0)
    end)
end

-- // MINIGAME SOLVER (with drag) // --
local function solveMinigame()
    local playerGui = LP:FindFirstChild("PlayerGui")
    if not playerGui then return false end
    local minigameFrame = nil
    for _, gui in pairs(playerGui:GetDescendants()) do
        if gui:IsA("Frame") and (gui.Name:lower():find("repair") or gui.Name:lower():find("generator")) then
            minigameFrame = gui
            break
        end
    end
    if not minigameFrame then return false end

    -- Find all numbered elements (dots)
    local dots = {}
    for _, child in pairs(minigameFrame:GetDescendants()) do
        if child.Visible then
            local num = nil
            if child:IsA("TextLabel") or child:IsA("TextButton") then
                num = tonumber(child.Text)
            elseif child:IsA("ImageLabel") then
                num = tonumber(child.Name:match("%d+"))
            end
            if num then
                table.insert(dots, {
                    obj = child,
                    number = num,
                    color = child.BackgroundColor3,
                    pos = child.AbsolutePosition + Vector2.new(child.AbsoluteSize.X/2, child.AbsoluteSize.Y/2)
                })
            end
        end
    end
    if #dots < 2 then
        -- Fallback: click all buttons in order without drag
        local buttons = {}
        for _, child in pairs(minigameFrame:GetDescendants()) do
            if (child:IsA("ImageButton") or child:IsA("TextButton")) and child.Visible then
                table.insert(buttons, child)
            end
        end
        if #buttons < 2 then return false end
        table.sort(buttons, function(a,b)
            if math.abs(a.AbsolutePosition.Y - b.AbsolutePosition.Y) < 50 then
                return a.AbsolutePosition.X < b.AbsolutePosition.X
            else
                return a.AbsolutePosition.Y < b.AbsolutePosition.Y
            end
        end)
        for _, btn in ipairs(buttons) do
            local pos = btn.AbsolutePosition + Vector2.new(btn.AbsoluteSize.X/2, btn.AbsoluteSize.Y/2)
            pcall(function()
                VirtualInput:SendMouseButtonEvent(pos.X, pos.Y, 0, true, game, 0)
                wait(0.05)
                VirtualInput:SendMouseButtonEvent(pos.X, pos.Y, 0, false, game, 0)
            end)
            wait(0.1)
        end
        return true
    end

    -- Group by color, then sort by number, then drag connect
    local colorGroups = {}
    for _, dot in pairs(dots) do
        local key = tostring(dot.color)
        if not colorGroups[key] then colorGroups[key] = {} end
        table.insert(colorGroups[key], dot)
    end

    for _, group in pairs(colorGroups) do
        table.sort(group, function(a,b) return a.number < b.number end)
        for i = 1, #group - 1 do
            local start = group[i]
            local target = group[i+1]
            if start.number == target.number then
                dragMouse(start.pos, target.pos)
                wait(0.2)
            end
        end
    end
    return true
end

-- // INTERACT WITH GENERATOR (Hold F) // --
local function interactWithGenerator(gen)
    if IsInteracting then return false end
    IsInteracting = true
    DebugLog("Interacting with generator: " .. gen.Name)

    -- Try ProximityPrompt:Prompt()
    local prompt = gen:FindFirstChildWhichIsA("ProximityPrompt")
    if prompt then
        pcall(function() prompt:Prompt() end)
        wait(0.5)
    end

    -- Hold F key
    pcall(function() VirtualInput:SendKeyEvent(true, Enum.KeyCode.F, false, game) end)
    wait(HOLD_TIME)
    pcall(function() VirtualInput:SendKeyEvent(false, Enum.KeyCode.F, false, game) end)

    -- Check for minigame UI
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
        DebugLog("Minigame opened – solving with drag")
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
                    DebugLog("Generator completed!")
                    CompletedGenerators[gen] = true
                    IsInteracting = false
                    return true
                end
            end
        else
            DebugLog("Minigame solver failed")
        end
    else
        DebugLog("Minigame UI did not open")
    end

    IsInteracting = false
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

-- // INFINITE STAMINA (safe) // --
local function applyStamina()
    if not Humanoid then return end
    if Humanoid.WalkSpeed < WALK_SPEED then
        Humanoid.WalkSpeed = WALK_SPEED
    end
    pcall(function() Humanoid:SetAttribute("Sprinting", true) end)
    for _, effect in pairs(game:GetService("Lighting"):GetChildren()) do
        if effect:IsA("BlurEffect") then effect.Enabled = false end
    end
end

-- // MAIN AI LOOP // --
local function aiTick()
    if not AIEnabled then return end
    if not PlayerChar or not Humanoid or not RootPart then
        updateChar()
        return
    end

    -- Killer avoidance
    local killerObj, killerDist = getNearestKiller()
    if killerObj and killerDist <= SliderValue then
        CurrentAction = "Fleeing"
        fleeFromKiller(killerObj.Position)
        wait(0.5)
        return
    end

    -- Generator farming
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

-- // BACKGROUND LOOPS (with pcall for safety) // --
spawn(function()
    while ScriptActive do
        wait(0.5)
        pcall(aiTick)
    end
end)

spawn(function()
    while ScriptActive do
        wait(0.5)
        if AIEnabled then pcall(applyStamina) end
    end
end)

spawn(function()
    while ScriptActive do
        wait(5)
        if AIEnabled then pcall(scanGenerators) end
    end
end)

-- // COOL GUI // --
local function createHub()
    local sg = Instance.new("ScreenGui")
    sg.Name = "ForsakenAI_Stable"
    sg.Parent = game.CoreGui
    sg.ResetOnSpawn = false

    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, 330, 0, 290)
    frame.Position = UDim2.new(0.5, -165, 0.5, -145)
    frame.BackgroundColor3 = Color3.fromRGB(5, 5, 20)
    frame.BackgroundTransparency = 0.1
    frame.BorderSizePixel = 0
    frame.Parent = sg
    Instance.new("UICorner").CornerRadius = UDim.new(0, 14)
    local glow = Instance.new("UIStroke")
    glow.Color = Color3.fromRGB(0, 255, 200)
    glow.Thickness = 2
    glow.Transparency = 0.3
    glow.Parent = frame

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
    Instance.new("UICorner").CornerRadius = UDim.new(0, 8)

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
        DebugLog("Script closed")
    end)

    toggle.MouseButton1Click:Connect(function()
        AIEnabled = not AIEnabled
        if AIEnabled then
            toggle.Text = "🟢 AI ON"
            toggle.BackgroundColor3 = Color3.fromRGB(0, 180, 80)
            updateChar()
            scanGenerators()
            status.Text = "AI ACTIVE"
            DebugLog("AI enabled")
        else
            toggle.Text = "🔴 AI OFF"
            toggle.BackgroundColor3 = Color3.fromRGB(0, 100, 180)
            status.Text = "AI OFF"
            DebugLog("AI disabled")
        end
    end)

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
        end
    end)
end

-- // START // --
updateChar()
createHub()
DebugLog("Stable AI loaded (no crashes). Use the GUI to toggle on/off. Console spam from ActorNetwork is from the game, not this script.")
