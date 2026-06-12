-- SUPER MINIMAL TEST – just GUI, nothing else
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local LP = Players.LocalPlayer

print("Minimal test script loaded. Creating GUI...")

local sg = Instance.new("ScreenGui")
sg.Name = "TestGUI"
sg.Parent = game.CoreGui

local frame = Instance.new("Frame")
frame.Size = UDim2.new(0, 300, 0, 200)
frame.Position = UDim2.new(0.5, -150, 0.5, -100)
frame.BackgroundColor3 = Color3.fromRGB(20,20,40)
frame.Parent = sg
Instance.new("UICorner").CornerRadius = UDim.new(0,12)

local label = Instance.new("TextLabel")
label.Size = UDim2.new(1,0,0,30)
label.BackgroundTransparency = 1
label.Text = "TEST GUI LOADED"
label.TextColor3 = Color3.fromRGB(0,255,0)
label.Font = Enum.Font.GothamBold
label.TextSize = 18
label.Parent = frame

local btn = Instance.new("TextButton")
btn.Size = UDim2.new(0,150,0,40)
btn.Position = UDim2.new(0.5,-75,0,80)
btn.Text = "CLOSE"
btn.Parent = frame
btn.MouseButton1Click:Connect(function()
    sg:Destroy()
    print("GUI closed")
end)

print("GUI should be visible now.")
