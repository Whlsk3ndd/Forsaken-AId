--[[
    ███████╗ ██████╗ ██████╗ ███████╗███╗   ██╗
    ██╔════╝██╔═══██╗██╔══██╗██╔════╝████╗  ██║
    ███████╗██║   ██║██████╔╝█████╗  ██╔██╗ ██║
    ╚════██║██║   ██║██╔══██╗██╔══╝  ██║╚██╗██║
    ███████║╚██████╔╝██║  ██║███████╗██║ ╚████║
    ╚══════╝ ╚═════╝ ╚═╝  ╚═╝╚══════╝╚═╝  ╚═══╝
    
    AUTO MINIGAME SOLVER (connect same color/number dots)
    SMART FLEE: random zig‑zag + two‑tier distance (slider + 20)
    XENO READY | INFINITE SPRINT | BLUR REMOVAL
--]]

-- // SERVICES // --
local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local VirtualInput = game:GetService("VirtualInput")
local LP = Players.LocalPlayer
local Mouse = LP:GetMouse()

-- // STATE // --
local AIEnabled = false
local UserRadius = 40                -- slider value
local SafetyRadius = UserRadius + 20 -- background radius
local MovingToTarget = false
local ScriptActive = true
local OriginalWalkSpeed = 16
local IsFleeing = false
local CurrentGeneratorTarget = nil

-- // REFERENCES // --
local PlayerChar, Humanoid, RootPart
local Generators = {}
local KillerModel = nil

-- // MINIGAME DETECTION // --
local MinigameFrame = nil
local Dots = {}   -- {guiObject, color, number, position}
local SolvingInProgress = false

-- // PATHFINDING // --
local PATH_OPTIONS = {
    AgentRadius = 2.5,
    AgentHeight = 5,
    AgentCanJump = true,
    AgentMaxSlope = 60,
    WaypointSpacing = 3
}

-- // UTILITIES // --
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

-- // INFINITE SPRINT + BLUR REMOVAL // --
local function applyStaminaHack()
    if not Humanoid then return end
    if Humanoid.WalkSpeed < 24 then Humanoid.WalkSpeed = 24 end
    local staminaProp = Humanoid:FindFirstChild("Stamina")
    if staminaProp and staminaProp:IsA("NumberValue") then
        setreadonly(staminaProp, false)
        staminaProp.Value = 100
        setreadonly(staminaProp, true)
    end
    Humanoid:SetAttribute("Sprinting", true)
    local sprintBool = PlayerChar and PlayerChar:FindFirstChild("IsSprinting")
    if sprintBool then sprintBool.Value = true end
    for _, effect in pairs(game:GetService("Lighting"):GetChildren()) do
        if effect:IsA("BlurEffect") then effect.Enabled = false end
    end
end

-- // KILLER DETECTION (tag + appearance) // --
local function findKiller()
    -- Method 1: Player team/name
    for _, plr in pairs(Players:GetPlayers()) do
        if plr ~= LP and plr.Character and plr.Character:FindFirstChild("HumanoidRootPart") then
            if (plr.Team and (plr.Team.Name:lower():find("killer") or plr.Team.Name:lower():find("monster"))) or
               (plr.Name:lower():find("killer") or plr.DisplayName:lower():find("killer")) or
               (plr.Character:FindFirstChild("KillerTag")) then
                return plr.Character
            end
        end
    end
    -- Method 2: NPC models
    for _, obj in pairs(workspace:GetDescendants()) do
        if obj:IsA("Model") and obj:FindFirstChild("Humanoid") and obj:FindFirstChild("HumanoidRootPart") then
            local name = obj.Name:lower()
            if name:find("killer") or name:find("slasher") or name:find("monster") or obj:FindFirstChild("KillerTag") then
                return obj
            end
        end
    end
    return nil
end

-- // LOBBY DETECTION // --
local function isAliveInMatch()
    if not PlayerChar or not Humanoid or Humanoid.Health <= 0 then return false end
    local lobby = workspace:FindFirstChild("Lobby") or workspace:FindFirstChild("LobbyArea")
    if lobby and RootPart and (RootPart.Position - lobby.Position).magnitude < 100 then return false end
    return true
end

-- // SMART FLEE (non‑straight line, zig‑zag) // --
local function fleeFromKiller(killerPos, myPos)
    local direction = (myPos - killerPos).unit
    -- Random offset angle between -60 and +60 degrees (dodge throws)
    local angle = math.rad(math.random(-60, 60))
    local newDir = Vector3.new(
        direction.X * math.cos(angle) - direction.Z * math.sin(angle),
        0,
        direction.X * math.sin(angle) + direction.Z * math.cos(angle)
    ).unit
    local fleePos = myPos + newDir * 35   -- flee 35 studs
    fleePos = Vector3.new(math.clamp(fleePos.X, -500, 500), fleePos.Y, math.clamp(fleePos.Z, -500, 500))
    
    -- Use pathfinding if possible, else straight line
    local path = PathfindingService:CreatePath(PATH_OPTIONS)
    local success = pcall(function() path:ComputeAsync(myPos, fleePos) end)
    if success and path.Status == Enum.PathStatus.Success then
        local waypoints = path:GetWaypoints()
        for _, wp in ipairs(waypoints) do
            if not AIEnabled then break end
            if wp.Action == Enum.PathWaypointAction.Jump then Humanoid.Jump = true end
            Humanoid:MoveTo(wp.Position)
            task.wait(0.2)
        end
    else
        Humanoid:MoveTo(fleePos)
    end
    return true
end

-- // GENERATOR SCANNER // --
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

-- // AUTO MINIGAME SOLVER (scans UI for dots) // --
local function findMinigameUI()
    -- Search player's screen for a Frame with dots
    local playerGui = LP:FindFirstChild("PlayerGui")
    if not playerGui then return nil end
    for _, gui in pairs(playerGui:GetDescendants()) do
        if gui:IsA("Frame") and (gui.Name:lower():find("generator") or gui.Name:lower():find("minigame") or gui.Name:lower():find("repair")) then
            -- Look for children that are ImageButtons or TextButtons with specific colors
            local dotsFound = {}
            for _, child in pairs(gui:GetDescendants()) do
                if (child:IsA("ImageButton") or child:IsA("TextButton")) and child.BackgroundColor3 ~= Color3.new(0,0,0) then
                    -- Attempt to extract number from text
                    local number = tonumber(child.Text)
                    if number then
                        table.insert(dotsFound, {
                            obj = child,
                            color = child.BackgroundColor3,
                            number = number,
                            pos = child.AbsolutePosition
                        })
                    end
                end
            end
            if #dotsFound >= 2 then
                return gui, dotsFound
            end
        end
    end
    return nil, {}
end

local function solveMinigame()
    local frame, dots = findMinigameUI()
    if not frame or #dots < 2 then return false end
    
    -- Group by same color
    local colorGroups = {}
    for _, dot in pairs(dots) do
        local key = tostring(dot.color)
        if not colorGroups[key] then colorGroups[key] = {} end
        table.insert(colorGroups[key], dot)
    end
    
    -- For each color, connect dots with same number
    for _, group in pairs(colorGroups) do
        -- Sort by number
        table.sort(group, function(a,b) return a.number < b.number end)
        for i = 1, #group - 1 do
            local start = group[i]
            local target = group[i+1]
            if start.number == target.number then
                -- Simulate mouse drag from start to target
                local startPos = start.obj.AbsolutePosition + Vector2.new(start.obj.AbsoluteSize.X/2, start.obj.AbsoluteSize.Y/2)
                local targetPos = target.obj.AbsolutePosition + Vector2.new(target.obj.AbsoluteSize.X/2, target.obj.AbsoluteSize.Y/2)
                -- Use VirtualInput to simulate mouse movement and click
                pcall(function()
                    VirtualInput:SendMouseButtonEvent(startPos.X, startPos.Y, 0, true, game, 0)
                    task.wait(0.05)
                    -- Move smoothly (tween)
                    for t = 0, 1, 0.1 do
                        local x = startPos.X + (targetPos.X - startPos.X) * t
                        local y = startPos.Y + (targetPos.Y - startPos.Y) * t
                        VirtualInput:SendMouseMoveEvent(x, y, game, 0)
                        task.wait(0.02)
                    end
                    VirtualInput:SendMouseButtonEvent(targetPos.X, targetPos.Y, 0, false, game, 0)
                end)
                task.wait(0.1)
            end
        end
    end
    return true
end

-- // MINIGAME MONITOR // --
local function monitorMinigame()
    if SolvingInProgress then return end
    SolvingInProgress = true
    while AIEnabled and ScriptActive do
        local frame, _ = findMinigameUI()
        if frame then
            solveMinigame()
            -- Wait for minigame to close (frame removed)
            while frame.Parent do
                task.wait(0.5)
                if not AIEnabled then break end
            end
        end
        task.wait(0.5)
    end
    SolvingInProgress = false
end

-- // MAIN AI LOOP (with two‑tier killer detection) // --
local function aiTick()
    if not AIEnabled or not ScriptActive then return end
    if not isAliveInMatch() then
        if Humanoid then Humanoid:MoveTo(Vector3.new(0,0,0)) end
        return
    end
    if not PlayerChar or not Humanoid or not RootPart then
        updateChar()
        return
    end
    
    -- KILLER DETECTION (two radii)
    local killer = findKiller()
    local killerDist = nil
    local shouldFlee = false
    if killer and RootPart then
        local killerRoot = killer:FindFirstChild("HumanoidRootPart")
        if killerRoot then
            killerDist = (RootPart.Position - killerRoot.Position).magnitude
            -- User radius (slider) OR safety radius (slider+20)
            if killerDist <= UserRadius then
                shouldFlee = true
            elseif killerDist <= SafetyRadius then
                -- still in outer radius, but maybe less aggressive
                shouldFlee = true
            end
        end
    end
    
    if shouldFlee and killer then
        if not IsFleeing then
            fleeFromKiller(killer.HumanoidRootPart.Position, RootPart.Position)
            IsFleeing = true
        else
            -- continue fleeing by re‑triggering
            fleeFromKiller(killer.HumanoidRootPart.Position, RootPart.Position)
        end
        return
    else
        IsFleeing = false
    end
    
    -- No immediate threat -> go to generator
    if #Generators == 0 then
        scanGenerators()
        return
    end
    
    -- Find nearest generator
    local bestGen, bestDist = nil, math.huge
    for _, gen in pairs(Generators) do
        if gen and gen.Parent then
            local d = (RootPart.Position - gen.Position).magnitude
            if d < bestDist then
                bestDist = d
                bestGen = gen
            end
        end
    end
    
    if bestGen then
        if bestDist > 5 then
            -- Move to generator using pathfinding
            local path = PathfindingService:CreatePath(PATH_OPTIONS)
            local ok = pcall(function() path:ComputeAsync(RootPart.Position, bestGen.Position) end)
            if ok and path.Status == Enum.PathStatus.Success then
                MovingToTarget = true
                local waypoints = path:GetWaypoints()
                for _, wp in ipairs(waypoints) do
                    if not AIEnabled then break end
                    if wp.Action == Enum.PathWaypointAction.Jump then Humanoid.Jump = true end
                    Humanoid:MoveTo(wp.Position)
                    task.wait(0.2)
                end
                MovingToTarget = false
            else
                Humanoid:MoveTo(bestGen.Position)
            end
        else
            -- At generator: trigger interaction (open minigame)
            local prompt = bestGen:FindFirstChildWhichIsA("ProximityPrompt")
            if prompt then
                pcall(function() prompt:InputHoldStart(); task.wait(0.2); prompt:InputHoldEnd() end)
            else
                local click = bestGen:FindFirstChildWhichIsA("ClickDetector")
                if click then pcall(function() click:FireClick(RootPart) end) end
            end
            -- Start minigame solver in background
            task.spawn(monitorMinigame)
            task.wait(0.5)
        end
    end
end

-- // BACKGROUND LOOPS // --
task.spawn(function()
    while ScriptActive do
        task.wait(0.25)
        aiTick()
    end
end)

task.spawn(function()
    while ScriptActive do
        task.wait(0.3)
        if AIEnabled then applyStaminaHack() end
    end
end)

task.spawn(function()
    while ScriptActive do
        task.wait(3)
        if AIEnabled then scanGenerators() end
    end
end)

-- // GUI HUB (with slider) // --
local function createHub()
    local sg = Instance.new("ScreenGui")
    sg.Name = "UltimateAIForsaken"
    sg.Parent = game.CoreGui
    sg.ResetOnSpawn = false
    
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, 360, 0, 260)
    frame.Position = UDim2.new(0.5, -180, 0.5, -130)
    frame.BackgroundColor3 = Color3.fromRGB(8,8,18)
    frame.BackgroundTransparency = 0.2
    frame.Parent = sg
    Instance.new("UICorner").CornerRadius = UDim.new(0,12); Instance.new("UICorner").Parent = frame
    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(255,50,100)
    stroke.Thickness = 1.5
    stroke.Parent = frame
    
    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1,0,0,35)
    title.BackgroundTransparency = 1
    title.Text = "🔪 ULTIMATE AI (MINIGAME SOLVER) 🔪"
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
        UserRadius = val
        SafetyRadius = UserRadius + 20   -- automatic +20
        fill.Size = UDim2.new(val/100,0,1,0)
        knob.Position = UDim2.new(val/100,-7,0,-4)
        sliderLabel.Text = string.format("Alert: %d (safe: %d)", UserRadius, SafetyRadius)
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
    status.Position = UDim2.new(0, 10, 0, 190)
    status.BackgroundTransparency = 1
    status.Text = "Ready"
    status.TextColor3 = Color3.fromRGB(200,200,230)
    status.Font = Enum.Font.Gotham
    status.TextSize = 11
    status.TextXAlignment = Enum.TextXAlignment.Left
    status.Parent = frame
    
    toggle.MouseButton1Click:Connect(function()
        AIEnabled = not AIEnabled
        if AIEnabled then
            toggle.Text = "🟢 AI ON"
            toggle.BackgroundColor3 = Color3.fromRGB(0,180,80)
            updateChar()
            scanGenerators()
            status.Text = "AI ON | Minigame solver ready | Two‑tier flee"
        else
            toggle.Text = "🔴 AI OFF"
            toggle.BackgroundColor3 = Color3.fromRGB(0,120,200)
            status.Text = "AI OFF"
            if Humanoid and OriginalWalkSpeed then Humanoid.WalkSpeed = OriginalWalkSpeed end
        end
    end)
    
    -- status updater
    task.spawn(function()
        while ScriptActive and sg do
            task.wait(1)
            if AIEnabled then
                local alive = isAliveInMatch()
                local killer = findKiller()
                local distText = ""
                if killer and RootPart and killer:FindFirstChild("HumanoidRootPart") then
                    local d = (RootPart.Position - killer.HumanoidRootPart.Position).magnitude
                    distText = string.format(" | Killer: %.0f", d)
                end
                status.Text = string.format("Gens: %d | %s | Alert: %d(+20)%s", #Generators, alive and "ALIVE" or "LOBBY", UserRadius, distText)
            end
        end
    end)
    
    -- drag
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
updateChar()
LP.CharacterAdded:Connect(function()
    task.wait(0.5)
    updateChar()
    if AIEnabled then scanGenerators() end
end)
createHub()
print("✅ ULTIMATE FORSAKEN AI LOADED: Minigame solver + two‑tier killer avoidance + non‑linear flee. Xeno ready.")
