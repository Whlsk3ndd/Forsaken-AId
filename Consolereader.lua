--[[
    Console Logger & Copier for Xeno Executor
    - Captures all print(), warn(), error() output
    - Includes server/client errors, game bugs, and script logs
    - Saves to "ConsoleLog.txt" in executor workspace
    - One-click copy to clipboard
--]]

-- // SERVICES //
local Players = game:GetService("Players")
local LP = Players.LocalPlayer

-- // SETTINGS //
local LogFileName = "ConsoleLog.txt"  -- Saves in your executor's workspace folder

-- // CREATE LOG FILE IF NOT EXISTS //
if not isfile(LogFileName) then
    writefile(LogFileName, "-- Console Log Started --\n\n")
end

-- // CAPTURE ALL CONSOLE OUTPUT //
local OriginalPrint = print
local OriginalWarn = warn
local OriginalError = error

-- Helper to write to file and optional to clipboard buffer
local LogBuffer = {}

local function WriteToLog(message, type)
    local timestamp = os.date("[%H:%M:%S]")
    local formatted = string.format("%s [%s] %s", timestamp, type, message)
    table.insert(LogBuffer, formatted)
    appendfile(LogFileName, formatted .. "\n")
end

-- Override print()
print = function(...)
    local args = {...}
    local message = table.concat(args, " ")
    WriteToLog(message, "PRINT")
    OriginalPrint(...)  -- Keep original console output
end

-- Override warn()
warn = function(...)
    local args = {...}
    local message = table.concat(args, " ")
    WriteToLog(message, "WARN")
    OriginalWarn(...)
end

-- Override error()
error = function(msg, level)
    WriteToLog(msg, "ERROR")
    OriginalError(msg, level or 1)
end

-- // CATCH ROBLOX ENGINE MESSAGES (F9 console) //
local function HookEngineOutput()
    -- Hook LogService to capture engine logs
    local LogService = game:GetService("LogService")
    if LogService then
        LogService.MessageOut:Connect(function(message, type)
            WriteToLog(message, tostring(type))
        end)
    end
end

-- // FLUSH BUFFER TO CLIPBOARD //
local function CopyBufferToClipboard()
    local fullLog = table.concat(LogBuffer, "\n")
    if setclipboard then
        setclipboard(fullLog)
        print("[Copied] Console log copied to clipboard!")
        return true
    elseif syn and syn.setclipboard then
        syn.setclipboard(fullLog)
        print("[Copied] Console log copied to clipboard!")
        return true
    else
        warn("[Failed] Your executor doesn't support setclipboard")
        return false
    end
end

-- // SAVE BUFFER TO FILE //
local function SaveBufferToFile()
    local fullLog = table.concat(LogBuffer, "\n")
    writefile(LogFileName, fullLog)
    print(string.format("[Saved] Console log saved to %s", LogFileName))
end

-- // GUI WITH COPY BUTTON //
local function CreateLoggerGUI()
    local sg = Instance.new("ScreenGui")
    sg.Name = "ConsoleLoggerGUI"
    sg.Parent = game.CoreGui
    sg.ResetOnSpawn = false

    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, 320, 0, 120)
    frame.Position = UDim2.new(0.5, -160, 0.5, -60)
    frame.BackgroundColor3 = Color3.fromRGB(10, 10, 20)
    frame.BackgroundTransparency = 0.15
    frame.Parent = sg
    Instance.new("UICorner").CornerRadius = UDim.new(0, 12)
    Instance.new("UICorner").Parent = frame

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, 0, 0, 30)
    title.BackgroundTransparency = 1
    title.Text = "📋 Console Logger"
    title.TextColor3 = Color3.fromRGB(0, 200, 255)
    title.Font = Enum.Font.GothamBold
    title.TextSize = 16
    title.Parent = frame

    local copyBtn = Instance.new("TextButton")
    copyBtn.Size = UDim2.new(0, 130, 0, 40)
    copyBtn.Position = UDim2.new(0.5, -140, 0, 45)
    copyBtn.BackgroundColor3 = Color3.fromRGB(0, 120, 200)
    copyBtn.Text = "📋 COPY LOG"
    copyBtn.TextColor3 = Color3.new(1, 1, 1)
    copyBtn.Font = Enum.Font.GothamBold
    copyBtn.TextSize = 14
    copyBtn.Parent = frame
    Instance.new("UICorner").CornerRadius = UDim.new(0, 8)
    Instance.new("UICorner").Parent = copyBtn

    local saveBtn = Instance.new("TextButton")
    saveBtn.Size = UDim2.new(0, 130, 0, 40)
    saveBtn.Position = UDim2.new(0.5, 10, 0, 45)
    saveBtn.BackgroundColor3 = Color3.fromRGB(80, 80, 120)
    saveBtn.Text = "💾 SAVE TO FILE"
    saveBtn.TextColor3 = Color3.new(1, 1, 1)
    saveBtn.Font = Enum.Font.GothamBold
    saveBtn.TextSize = 13
    saveBtn.Parent = frame
    Instance.new("UICorner").CornerRadius = UDim.new(0, 8)
    Instance.new("UICorner").Parent = saveBtn

    copyBtn.MouseButton1Click:Connect(function()
        CopyBufferToClipboard()
    end)

    saveBtn.MouseButton1Click:Connect(function()
        SaveBufferToFile()
    end)

    -- Draggable
    local dragStart, dragPos, dragging = nil
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
    game:GetService("UserInputService").InputChanged:Connect(function(inp)
        if dragging and inp.UserInputType == Enum.UserInputType.MouseMovement then
            local delta = inp.Position - dragStart
            frame.Position = UDim2.new(dragPos.X.Scale, dragPos.X.Offset + delta.X, dragPos.Y.Scale, dragPos.Y.Offset + delta.Y)
        end
    end)
end

-- // START EVERYTHING //
HookEngineOutput()
CreateLoggerGUI()
print("[Console Logger] Ready! All print/warn/error are being logged to " .. LogFileName)
print("[Console Logger] Click the GUI buttons to copy or save the log.")
