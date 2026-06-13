-- Run this when the minigame is open
local playerGui = game.Players.LocalPlayer:FindFirstChild("PlayerGui")
if playerGui then
    for _, gui in pairs(playerGui:GetDescendants()) do
        if gui:IsA("Frame") and gui.Name == "SetupGenerators_-7005" then
            print("Found minigame frame:", gui.Name)
            local function dump(obj, indent)
                indent = indent or 0
                local prefix = string.rep("  ", indent)
                for _, child in pairs(obj:GetChildren()) do
                    print(prefix .. child.ClassName .. ": " .. child.Name)
                    if child:IsA("ImageLabel") or child:IsA("TextLabel") or child:IsA("TextButton") or child:IsA("ImageButton") then
                        print(prefix .. "  Text: " .. (child.Text or "none"))
                        print(prefix .. "  BackgroundColor: " .. tostring(child.BackgroundColor3))
                    end
                    if #child:GetChildren() > 0 then
                        dump(child, indent + 1)
                    end
                end
            end
            dump(gui)
            break
        end
    end
end
