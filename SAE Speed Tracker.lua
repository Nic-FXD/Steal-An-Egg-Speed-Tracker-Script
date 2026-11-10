local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer

-- Wait for leaderstats and Speed stat safely
local leaderstats = LocalPlayer:WaitForChild("leaderstats", 10)
local speedStat = leaderstats and leaderstats:WaitForChild("Speed", 10)

if not speedStat then
    warn("leaderstats.Speed could not be found!")
    return
end

-- Automatically find the user's plot based on character position proximity
local function getMyPlotFolder()
    local character = LocalPlayer.Character
    local hrp = character and character:FindFirstChild("HumanoidRootPart")
    local plotsFolder = Workspace:FindFirstChild("Plots")
    
    if not plotsFolder then return nil end
    
    local closestPlot = nil
    local shortestDistance = math.huge
    
    for _, plot in ipairs(plotsFolder:GetChildren()) do
        local modelPart = plot:FindFirstChildWhichIsA("BasePart") or plot:FindFirstChild("TreadmillBottom") or plot:FindFirstChild("TreadmillUpgrade")
        if modelPart and hrp then
            local dist = (modelPart.Position - hrp.Position).Magnitude
            if dist < shortestDistance then
                shortestDistance = dist
                closestPlot = plot
            end
        end
    end
    
    return closestPlot
end

-- Safely load the Save module to track treadmill upgrade levels[cite: 6]
local success, Save = pcall(function()
    return require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Save"))
end)

local function getTreadmillLevel()
    if success and Save then
        local data = Save.Await()
        if data and data.TreadmillUpgradeLevel then
            return tostring(data.TreadmillUpgradeLevel)
        end
    end
    return "?"
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

-- Create clean tracking GUI overlay
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "SpeedGainTracker"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")

local Frame = Instance.new("Frame")
Frame.Size = UDim2.new(0, 240, 0, 150)
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
Title.Text = "Speed & Treadmill Tracker"
Title.TextColor3 = Color3.fromRGB(255, 255, 255)
Title.TextSize = 14
Title.Font = Enum.Font.GothamBold
Title.Parent = Frame

local StatusLabel = Instance.new("TextLabel")
StatusLabel.Size = UDim2.new(1, 0, 0, 110)
StatusLabel.Position = UDim2.new(0, 0, 0, 30)
StatusLabel.BackgroundTransparency = 1
StatusLabel.TextColor3 = Color3.fromRGB(0, 255, 128)
StatusLabel.TextSize = 13
StatusLabel.Font = Enum.Font.Gotham
StatusLabel.TextWrapped = true
StatusLabel.Parent = Frame

-- Dragging functionality implementation
local dragging, dragStart, startPos

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
local myPlot = getMyPlotFolder()
if myPlot then
    print("Successfully targeted your plot:", myPlot.Name)
end

-- Update display function
local function updateDisplay()
    local currentSpeed = speedStat.Value
    local gain = currentSpeed - initialSpeed
    local elapsedTime = os.time() - startTime
    local currentLevel = getTreadmillLevel()
    local plotName = myPlot and myPlot.Name or "Unknown"
    
    StatusLabel.Text = string.format("Plot: %s\nCurrent: %s\nInitial: %s\nGain: +%s\nTreadmill Lvl: %s\nTime: %s", 
        plotName,
        formatCompact(currentSpeed, 3), 
        formatCompact(initialSpeed, 1), 
        formatCompact(gain, 1),
        currentLevel,
        formatTime(elapsedTime)
    )
end

-- Listen for changes on the Speed stat value
speedStat.Changed:Connect(updateDisplay)

if success and Save then
    pcall(function()
        Save.Watch("TreadmillUpgradeLevel"):Connect(updateDisplay)
    end)
end

-- Background loop to update the timer every second
task.spawn(function()
    while true do
        if not myPlot then
            myPlot = getMyPlotFolder() -- Re-check if plot wasn't loaded initially
        end
        updateDisplay()
        task.wait(1)
    end
end)

updateDisplay()
print("Tracker initialized with auto-plot detection!")