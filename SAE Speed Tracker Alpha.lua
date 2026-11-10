local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

-- Wait for leaderstats and Speed stat safely
local leaderstats = LocalPlayer:WaitForChild("leaderstats", 10)
local speedStat = leaderstats and leaderstats:WaitForChild("Speed", 10)

if not speedStat then
    warn("leaderstats.Speed could not be found!")
    return
end

-- Create clean tracking GUI overlay
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "SpeedGainTracker"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")

local Frame = Instance.new("Frame")
Frame.Size = UDim2.new(0, 220, 0, 90)
Frame.Position = UDim2.new(0.02, 0, 0.8, 0)
Frame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
Frame.BorderSizePixel = 0
Frame.Parent = ScreenGui

local UICorner = Instance.new("UICorner")
UICorner.CornerRadius = UDim.new(0, 8)
UICorner.Parent = Frame

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, 0, 0, 30)
Title.BackgroundTransparency = 1
Title.Text = "Speed Gain Tracker"
Title.TextColor3 = Color3.fromRGB(255, 255, 255)
Title.TextSize = 14
Title.Font = Enum.Font.GothamBold
Title.Parent = Frame

local StatusLabel = Instance.new("TextLabel")
StatusLabel.Size = UDim2.new(1, 0, 0, 50)
StatusLabel.Position = UDim2.new(0, 0, 0, 30)
StatusLabel.BackgroundTransparency = 1
StatusLabel.TextColor3 = Color3.fromRGB(0, 255, 128)
StatusLabel.TextSize = 13
StatusLabel.Font = Enum.Font.Gotham
StatusLabel.TextWrapped = true
StatusLabel.Parent = Frame

local initialSpeed = speedStat.Value
local peakSpeed = initialSpeed

-- Update display function
local function updateDisplay()
    local currentSpeed = speedStat.Value
    if currentSpeed > peakSpeed then
        peakSpeed = currentSpeed
    end
    local gain = currentSpeed - initialSpeed
    StatusLabel.Text = string.format("Current: %s\nInitial: %s\nGain: +%s", tostring(currentSpeed), tostring(initialSpeed), tostring(gain))
end

-- Listen for changes on the Speed stat value
speedStat.Changed:Connect(updateDisplay)
updateDisplay()

print("Speed Gain Tracker successfully initialized!")