local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer

-- Wait for leaderstats and Speed stat safely
local leaderstats = LocalPlayer:WaitForChild("leaderstats", 10)
local speedStat = leaderstats and leaderstats:WaitForChild("Speed", 10)

if not speedStat then
    warn("leaderstats.Speed could not be found!")
    return
end

-- Compact number formatter with custom decimal places
local function formatCompact(value, decimals)
    if type(value) ~= "number" then
        value = tonumber(value) or 0
    end
    
    local suffixes = {"", "k", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc"}
    local i = 1
    
    while value >= 1000 and i < #suffixes do
        value = value / 1000
        i += 1
    end
    
    if i == 1 then
        return tostring(math.floor(value))
    else
        local fmt = string.format("%%.%df%%s", decimals or 1)
        return string.format(fmt, value, suffixes[i])
    end
end

-- Format elapsed seconds into HH:MM:SS or MM:SS
local function formatTime(seconds)
    seconds = math.floor(seconds)
    local hrs = math.floor(seconds / 3600)
    local mins = math.floor((seconds % 3600) / 60)
    local secs = seconds % 60
    
    if hrs > 0 then
        return string.format("%02d:%02d:%02d", hrs, mins, secs)
    else
        return string.format("%02d:%02d", mins, secs)
    end
end

-- Create clean tracking GUI overlay (height increased to 115 to fit time)
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "SpeedGainTracker"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")

local Frame = Instance.new("Frame")
Frame.Size = UDim2.new(0, 220, 0, 115)
Frame.Position = UDim2.new(0.02, 0, 0.8, 0)
Frame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
Frame.BorderSizePixel = 0
Frame.Active = true
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
StatusLabel.Size = UDim2.new(1, 0, 0, 75)
StatusLabel.Position = UDim2.new(0, 0, 0, 30)
StatusLabel.BackgroundTransparency = 1
StatusLabel.TextColor3 = Color3.fromRGB(0, 255, 128)
StatusLabel.TextSize = 13
StatusLabel.Font = Enum.Font.Gotham
StatusLabel.TextWrapped = true
StatusLabel.Parent = Frame

-- Dragging functionality implementation
local dragging, dragInput, dragStart, startPos

Frame.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = Frame.Position
        
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                dragging = false
            end
        end)
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = input.Position - dragStart
        Frame.Position = UDim2.new(
            startPos.X.Scale, 
            startPos.X.Offset + delta.X, 
            startPos.Y.Scale, 
            startPos.Y.Offset + delta.Y
        )
    end
end)

local initialSpeed = speedStat.Value
local startTime = os.time()

-- Update display function
local function updateDisplay()
    local currentSpeed = speedStat.Value
    local gain = currentSpeed - initialSpeed
    local elapsedTime = os.time() - startTime
    
    -- Current shows 3 decimal places (6 total significant digits like 254.321B), others show 1 decimal place
    StatusLabel.Text = string.format("Current: %s\nInitial: %s\nGain: +%s\nTime: %s", 
        formatCompact(currentSpeed, 3), 
        formatCompact(initialSpeed, 1), 
        formatCompact(gain, 1),
        formatTime(elapsedTime)
    )
end

-- Listen for changes on the Speed stat value
speedStat.Changed:Connect(updateDisplay)

-- Background loop to update the timer every second
task.spawn(function()
    while true do
        updateDisplay()
        task.wait(1)
    end
end)

updateDisplay()
print("Speed Gain Tracker updated successfully!")