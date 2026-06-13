--[[
    FORSAKEN AI – ULTIMATE GENERATOR FIX
    - Handles info panel, then forces real minigame
    - Clicks ANY visible button inside the real minigame
    - Throttled movement, rejoin, cool GUI
--]]

if getgenv then
    getgenv().LoadTime = getgenv().LoadTime or "3"
    getgenv().GeneratorTime = getgenv().GeneratorTime or "3"
end
wait(tonumber(getgenv and getgenv().LoadTime or 3) or 3)

-- Services
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local VirtualInput = game:GetService("VirtualInput")
local TeleportService = game:GetService("TeleportService")
local LP = Players.LocalPlayer

-- State
local AIEnabled = false
local ScriptActive = true
local SliderValue = 40
local PlayerChar, Humanoid, RootPart
local Generators = {}
local CompletedGenerators = {}
local CurrentAction = "Idle"
local IsInteracting = false
local LastMoveTime = 0
local HOLD_TIME = tonumber(getgenv and getgenv().GeneratorTime or 3) or 3

-- Constants
local WALK_SPEED = 24
local KILLER_NAMES = {"slasher","c00lkidd","john doe","1x1x1x1","noli","guest 666","nosferatu"}

local function DebugLog(msg) print("[AI] " .. msg) end

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

local function getNearestKiller()
    if not RootPart then return nil, math.huge end
    local nearest, nearestDist = nil, math.huge
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
                        nearestDist, nearest = dist, hrp
                    end
                end
            end
        end
    end
    return nearest, nearestDist
end

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

-- REAL MINIGAME DETECTION (look for frames that contain numbered buttons)
local function findRealMinigameFrame()
    local playerGui = LP:FindFirstChild("PlayerGui")
    if not playerGui then return nil end
    for _, gui in pairs(playerGui:GetDescendants()) do
        if gui:IsA("Frame") and gui.Visible then
            for _, child in pairs(gui:GetDescendants()) do
                if child:IsA("TextButton") or child:IsA("ImageButton") or child:IsA("TextLabel") then
                    if tonumber(child.Text) or child.Name:match("%d+") then
                        DebugLog("Real minigame frame found: " .. gui.Name)
                        return gui
                    end
                end
            end
        end
    end
    return nil
end

-- BRUTE-FORCE SOLVER FOR REAL MINIGAME
local function solveRealMinigame(frame)
    local clickables = {}
    for _, child in pairs(frame:GetDescendants()) do
        if child.Visible and (child:IsA("ImageButton") or child:IsA("TextButton") or child:IsA("TextLabel")) then
            if child.AbsoluteSize.X > 10 and child.AbsoluteSize.Y > 10 then
                table.insert(clickables, child)
            end
        end
    end
    if #clickables == 0 then return false end
    table.sort(clickables, function(a,b)
        if math.abs(a.AbsolutePosition.Y - b.AbsolutePosition.Y) < 50 then
            return a.AbsolutePosition.X < b.AbsolutePosition.X
        else
            return a.AbsolutePosition.Y < b.AbsolutePosition.Y
        end
    end)
    for _, btn in ipairs(clickables) do
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

-- INTERACT WITH GENERATOR (handles info panel)
local function interactWithGenerator(gen)
    if IsInteracting then return false end
    IsInteracting = true
    DebugLog("Interacting with generator: " .. gen.Name)

    -- 1. Try ProximityPrompt
    local prompt = gen:FindFirstChildWhichIsA("ProximityPrompt")
    if prompt then pcall(function() prompt:Prompt() end) end
    wait(0.5)

    -- 2. Hold F for HOLD_TIME seconds
    pcall(function() VirtualInput:SendKeyEvent(true, Enum.KeyCode.F, false, game) end)
    wait(HOLD_TIME)
    pcall(function() VirtualInput:SendKeyEvent(false, Enum.KeyCode.F, false, game) end)

    -- 3. If info panel appeared, press F again (or click "OK" if exists)
    local infoPanel = nil
    for i = 1, 10 do
        wait(0.2)
        local playerGui = LP:FindFirstChild("PlayerGui")
        if playerGui then
            for _, gui in pairs(playerGui:GetDescendants()) do
                if gui:IsA("Frame") and gui.Name:lower():find("setup") then
                    infoPanel = gui
                    break
                end
            end
        end
        if infoPanel then break end
    end
    if infoPanel then
        DebugLog("Info panel detected – closing it")
        -- Try to find a close button or just press F again
        local closeBtn = nil
        for _, btn in pairs(infoPanel:GetDescendants()) do
            if btn:IsA("TextButton") and (btn.Text:lower():find("ok") or btn.Text:lower():find("close")) then
                closeBtn = btn; break
            end
        end
        if closeBtn then
            local pos = closeBtn.AbsolutePosition + Vector2.new(closeBtn.AbsoluteSize.X/2, closeBtn.AbsoluteSize.Y/2)
            pcall(function() VirtualInput:SendMouseButtonEvent(pos.X, pos.Y, 0, true, game, 0); wait(0.05); VirtualInput:SendMouseButtonEvent(pos.X, pos.Y, 0, false, game, 0) end)
        else
            pcall(function() VirtualInput:SendKeyEvent(true, Enum.KeyCode.F, false, game); wait(0.5); VirtualInput:SendKeyEvent(false, Enum.KeyCode.F, false, game) end)
        end
        wait(0.5)
    end

    -- 4. Now wait for the real minigame to appear (up to 5 seconds)
    local realFrame = nil
    for i = 1, 50 do
        wait(0.1)
        realFrame = findRealMinigameFrame()
        if realFrame then break end
    end

    if realFrame then
        DebugLog("Real minigame opened – solving")
        local solved = solveRealMinigame(realFrame)
        if solved then
            -- Wait for UI to close
            for i = 1, 40 do
                wait(0.2)
                if not findRealMinigameFrame() and not infoPanel then
                    DebugLog("Generator completed!", "SUCCESS")
                    CompletedGenerators[gen] = true
                    IsInteracting = false
                    return true
                end
            end
        else
            DebugLog("Minigame solver found no clickables", "ERROR")
        end
    else
        DebugLog("Real minigame never appeared", "ERROR")
        -- Fallback: click the generator part directly as a last resort
        local screenPos, onScreen = workspace.CurrentCamera:WorldToScreenPoint(gen.Position)
        if onScreen then
            pcall(function()
                VirtualInput:SendMouseButtonEvent(screenPos.X, screenPos.Y, 0, true, game, 0)
                wait(0.2)
                VirtualInput:SendMouseButtonEvent(screenPos.X, screenPos.Y, 0, false, game, 0)
            end)
        end
    end

    IsInteracting = false
    return false
end

-- Movement and AI loops (throttled)
local function moveToGenerator(gen)
    if not RootPart or not Humanoid then return end
    local now = tick()
    if now - LastMoveTime < 0.3 then return end
    LastMoveTime = now
    Humanoid:MoveTo(gen.Position)
end

local function fleeFromKiller(killerPos)
    if not RootPart or not Humanoid then return end
    local direction = (RootPart.Position - killerPos).unit
    local fleePos = RootPart.Position + direction * 40
    fleePos = Vector3.new(math.clamp(fleePos.X, -500, 500), fleePos.Y, math.clamp(fleePos.Z, -500, 500))
    Humanoid:MoveTo(fleePos)
end

local function applyStamina()
    if not Humanoid then return end
    if Humanoid.WalkSpeed < WALK_SPEED then
        Humanoid.WalkSpeed = WALK_SPEED
    end
    for _, effect in pairs(game:GetService("Lighting"):GetChildren()) do
        if effect:IsA("BlurEffect") then effect.Enabled = false end
    end
end

local function aiTick()
    if not AIEnabled then return end
    if not PlayerChar or not Humanoid or not RootPart then
        updateChar()
        return
    end
    local killerObj, killerDist = getNearestKiller()
    if killerObj and killerDist <= SliderValue then
        CurrentAction = "Fleeing"
        fleeFromKiller(killerObj.Position)
        wait(0.5)
        return
    end
    if #Generators == 0 then
        scanGenerators()
        return
    end
    local nearestGen, nearestDist = nil, math.huge
    for _, gen in pairs(Generators) do
        if gen and gen.Parent then
            local d = (RootPart.Position - gen.Position).magnitude
            if d < nearestDist then
                nearestDist, nearestGen = d, gen
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

-- Background loops
spawn(function() while ScriptActive do wait(0.5); pcall(aiTick) end end)
spawn(function() while ScriptActive do wait(0.5); if AIEnabled then pcall(applyStamina) end end end)
spawn(function() while ScriptActive do wait(5); if AIEnabled then pcall(scanGenerators) end end end)

-- GUI (same as before, simplified)
local function createHub()
    local sg = Instance.new("ScreenGui")
    sg.Name = "ForsakenAI_Final"
    sg.Parent = game.CoreGui
    sg.ResetOnSpawn = false
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, 330, 0, 290)
    frame.Position = UDim2.new(0.5, -165, 0.5, -145)
    frame.BackgroundColor3 = Color3.fromRGB(5,5,20)
    frame.BackgroundTransparency = 0.1
    frame.Parent = sg
    Instance.new("UICorner").CornerRadius = UDim.new(0,14)
    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1,0,0,40)
    title.BackgroundTransparency = 1
    title.Text = "⚡ FORSAKEN AI ⚡"
    title.TextColor3 = Color3.fromRGB(0,255,200)
    title.Font = Enum.Font.GothamBold
    title.TextSize = 18
    title.Parent = frame
    local toggle = Instance.new("TextButton")
    toggle.Size = UDim2.new(0,200,0,45)
    toggle.Position = UDim2.new(0.5,-100,0,55)
    toggle.BackgroundColor3 = Color3.fromRGB(0,100,180)
    toggle.Text = "🔴 AI OFF"
    toggle.TextColor3 = Color3.new(1,1,1)
    toggle.Font = Enum.Font.GothamBold
    toggle.TextSize = 18
    toggle.Parent = frame
    Instance.new("UICorner").CornerRadius = UDim.new(0,8)

    local sliderFrame = Instance.new("Frame")
    sliderFrame.Size = UDim2.new(0,260,0,50)
    sliderFrame.Position = UDim2.new(0.5,-130,0,115)
    sliderFrame.BackgroundTransparency = 1
    sliderFrame.Parent = frame
    local sliderLabel = Instance.new("TextLabel")
    sliderLabel.Size = UDim2.new(0,140,0,20)
    sliderLabel.Position = UDim2.new(0,0,0,0)
    sliderLabel.BackgroundTransparency = 1
    sliderLabel.Text = "Killer Alert: 40"
    sliderLabel.TextColor3 = Color3.fromRGB(255,180,180)
    sliderLabel.Font = Enum.Font.Gotham
    sliderLabel.TextSize = 12
    sliderLabel.Parent = sliderFrame
    local sliderBg = Instance.new("Frame")
    sliderBg.Size = UDim2.new(0,200,0,6)
    sliderBg.Position = UDim2.new(0,0,0,22)
    sliderBg.BackgroundColor3 = Color3.fromRGB(50,50,70)
    sliderBg.BorderSizePixel = 0
    sliderBg.Parent = sliderFrame
    local fill = Instance.new("Frame")
    fill.Size = UDim2.new(0.4,0,1,0)
    fill.BackgroundColor3 = Color3.fromRGB(0,200,255)
    fill.BorderSizePixel = 0
    fill.Parent = sliderBg
    local knob = Instance.new("TextButton")
    knob.Size = UDim2.new(0,14,0,14)
    knob.Position = UDim2.new(0.4,-7,0,-4)
    knob.BackgroundColor3 = Color3.new(1,1,1)
    knob.Text = ""
    knob.AutoButtonColor = false
    knob.Parent = sliderFrame
    Instance.new("UICorner").CornerRadius = UDim.new(1,0)
    local function setSlider(val)
        val = math.clamp(val,0,100)
        SliderValue = val
        fill.Size = UDim2.new(val/100,0,1,0)
        knob.Position = UDim2.new(val/100,-7,0,-4)
        sliderLabel.Text = "Killer Alert: " .. math.floor(val)
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
                if io.UserInputType == Enum.UserInputType.MouseButton1 then move:Disconnect(); rel:Disconnect() end
            end)
        end
    end)
    local status = Instance.new("TextLabel")
    status.Size = UDim2.new(1,-20,0,35)
    status.Position = UDim2.new(0,10,0,180)
    status.BackgroundTransparency = 1
    status.Text = "Ready"
    status.TextColor3 = Color3.fromRGB(200,200,230)
    status.Font = Enum.Font.Gotham
    status.TextSize = 12
    status.TextXAlignment = Enum.TextXAlignment.Left
    status.Parent = frame
    local actionLabel = Instance.new("TextLabel")
    actionLabel.Size = UDim2.new(1,-20,0,20)
    actionLabel.Position = UDim2.new(0,10,0,215)
    actionLabel.BackgroundTransparency = 1
    actionLabel.Text = "Action: Idle"
    actionLabel.TextColor3 = Color3.fromRGB(150,150,200)
    actionLabel.Font = Enum.Font.Gotham
    actionLabel.TextSize = 11
    actionLabel.TextXAlignment = Enum.TextXAlignment.Left
    actionLabel.Parent = frame
    local hideBtn = Instance.new("TextButton")
    hideBtn.Size = UDim2.new(0,90,0,35)
    hideBtn.Position = UDim2.new(0.05,0,0,245)
    hideBtn.BackgroundColor3 = Color3.fromRGB(60,60,90)
    hideBtn.Text = "⛔ HIDE"
    hideBtn.TextColor3 = Color3.new(1,1,1)
    hideBtn.Font = Enum.Font.GothamBold
    hideBtn.TextSize = 13
    hideBtn.Parent = frame
    Instance.new("UICorner").CornerRadius = UDim.new(0,6)
    local rejoinBtn = Instance.new("TextButton")
    rejoinBtn.Size = UDim2.new(0,90,0,35)
    rejoinBtn.Position = UDim2.new(0.35,0,0,245)
    rejoinBtn.BackgroundColor3 = Color3.fromRGB(100,70,120)
    rejoinBtn.Text = "🔄 REJOIN"
    rejoinBtn.TextColor3 = Color3.new(1,1,1)
    rejoinBtn.Font = Enum.Font.GothamBold
    rejoinBtn.TextSize = 13
    rejoinBtn.Parent = frame
    Instance.new("UICorner").CornerRadius = UDim.new(0,6)
    local closeBtn = Instance.new("TextButton")
    closeBtn.Size = UDim2.new(0,90,0,35)
    closeBtn.Position = UDim2.new(0.65,0,0,245)
    closeBtn.BackgroundColor3 = Color3.fromRGB(180,50,70)
    closeBtn.Text = "❌ CLOSE"
    closeBtn.TextColor3 = Color3.new(1,1,1)
    closeBtn.Font = Enum.Font.GothamBold
    closeBtn.TextSize = 13
    closeBtn.Parent = frame
    Instance.new("UICorner").CornerRadius = UDim.new(0,6)
    local showBtn = nil
    hideBtn.MouseButton1Click:Connect(function()
        frame.Visible = false
        if not showBtn then
            showBtn = Instance.new("TextButton")
            showBtn.Size = UDim2.new(0,90,0,30)
            showBtn.Position = UDim2.new(0.02,0,0.9,0)
            showBtn.BackgroundColor3 = Color3.fromRGB(0,180,200)
            showBtn.Text = "🔽 SHOW"
            showBtn.TextColor3 = Color3.new(1,1,1)
            showBtn.Font = Enum.Font.GothamBold
            showBtn.TextSize = 12
            showBtn.Parent = sg
            Instance.new("UICorner").CornerRadius = UDim.new(0,8)
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
        AIEnabled = false; ScriptActive = false; sg:Destroy()
    end)
    toggle.MouseButton1Click:Connect(function()
        AIEnabled = not AIEnabled
        if AIEnabled then
            toggle.Text = "🟢 AI ON"
            toggle.BackgroundColor3 = Color3.fromRGB(0,180,80)
            updateChar(); scanGenerators()
            status.Text = "AI ACTIVE"
        else
            toggle.Text = "🔴 AI OFF"
            toggle.BackgroundColor3 = Color3.fromRGB(0,100,180)
            status.Text = "AI OFF"
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

updateChar()
createHub()
DebugLog("Ultimate generator script loaded. Will attempt to close info panel and find real minigame.")
