--// SAE Speed Tracker (realtime + auto session)
--// Reads game.Players.LocalPlayer.leaderstats.Speed and updates instantly on change.
--// Session auto-starts when your Speed starts rising (you walk on the treadmill)
--// and auto-resets when you jump off it (or stop gaining for a while).

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

--------------------------------------------------------------------
-- Config
--------------------------------------------------------------------
local AUTO_SESSION = true  -- auto start/stop the session
local STOP_ON_JUMP = true  -- reset session when you jump (leave the treadmill)
local IDLE_TIMEOUT = 8     -- seconds without any Speed gain before the session ends (0 = disable)
local WINDOW = 10          -- seconds used for the live Speed/s rate
local LEAVE_DISTANCE = 12  -- studs you can move from where the session started before it ends (0 = disable)
local LEAVE_LOCKOUT = 2    -- seconds after leaving/jumping during which Speed gains can't restart a session
local DEBUG = false        -- true = print why a session was stopped

-- Remove any previous instance (safe to re-execute)
local old = PlayerGui:FindFirstChild("SpeedGainTracker")
if old then old:Destroy() end

--------------------------------------------------------------------
-- Stat lookup
--------------------------------------------------------------------
local leaderstats = LocalPlayer:WaitForChild("leaderstats", 15)
local speedStat = leaderstats and leaderstats:WaitForChild("Speed", 15)
if not speedStat then
    warn("[SpeedTracker] leaderstats.Speed not found")
    return
end

--------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------
local SUFFIXES = {"", "k", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc"}
local SUFFIX_LOOKUP = {}
for i, s in ipairs(SUFFIXES) do
    if s ~= "" then SUFFIX_LOOKUP[s:lower()] = 1000 ^ (i - 1) end
end

-- Works whether Speed is a NumberValue/IntValue or a formatted StringValue ("1.5k")
local function readStat(stat)
    local v = stat.Value
    if type(v) == "number" then return v end
    if type(v) == "string" then
        local clean = v:gsub(",", ""):gsub("%s", "")
        local num, suf = clean:match("^(%-?[%d%.]+)(%a*)$")
        if num then
            return (tonumber(num) or 0) * (SUFFIX_LOOKUP[suf:lower()] or 1)
        end
    end
    return tonumber(v) or 0
end

local function formatCompact(value, decimals)
    value = tonumber(value) or 0
    local sign = value < 0 and "-" or ""
    value = math.abs(value)

    local i = 1
    while value >= 1000 and i < #SUFFIXES do
        value /= 1000
        i += 1
    end

    if i == 1 then
        if value < 100 and value % 1 ~= 0 then
            return sign .. string.format("%.1f", value)
        end
        return sign .. tostring(math.floor(value))
    end
    return sign .. string.format("%." .. (decimals or 1) .. "f%s", value, SUFFIXES[i])
end

local function formatTime(seconds)
    seconds = math.floor(seconds)
    local h = seconds // 3600
    local m = (seconds % 3600) // 60
    local s = seconds % 60
    if h > 0 then
        return string.format("%02d:%02d:%02d", h, m, s)
    end
    return string.format("%02d:%02d", m, s)
end

--------------------------------------------------------------------
-- Plot detection (throttled, only runs occasionally)
--------------------------------------------------------------------
local function getMyPlotFolder()
    local character = LocalPlayer.Character
    local hrp = character and character:FindFirstChild("HumanoidRootPart")
    local plotsFolder = Workspace:FindFirstChild("Plots")
    if not (hrp and plotsFolder) then return nil end

    local closest, shortest = nil, math.huge
    for _, plot in ipairs(plotsFolder:GetChildren()) do
        local part = plot:FindFirstChild("TreadmillBottom")
            or plot:FindFirstChild("TreadmillUpgrade")
            or plot:FindFirstChildWhichIsA("BasePart", true)
        if part then
            local dist = (part.Position - hrp.Position).Magnitude
            if dist < shortest then
                shortest, closest = dist, plot
            end
        end
    end
    return closest
end

--------------------------------------------------------------------
-- Treadmill level (cached, never yields the update loop)
--------------------------------------------------------------------
local treadmillLevel = "?"
local requestRefresh -- forward declaration

task.spawn(function()
    local ok, Save = pcall(function()
        return require(ReplicatedStorage:WaitForChild("Shared", 10):WaitForChild("Save", 10))
    end)
    if not (ok and Save) then return end

    local okData, data = pcall(Save.Await)
    if okData and data and data.TreadmillUpgradeLevel then
        treadmillLevel = tostring(data.TreadmillUpgradeLevel)
        if requestRefresh then requestRefresh() end
    end

    pcall(function()
        Save.Watch("TreadmillUpgradeLevel"):Connect(function(newLevel)
            if newLevel ~= nil then
                treadmillLevel = tostring(newLevel)
            else
                local d = Save.Await()
                if d and d.TreadmillUpgradeLevel then
                    treadmillLevel = tostring(d.TreadmillUpgradeLevel)
                end
            end
            if requestRefresh then requestRefresh() end
        end)
    end)
end)

--------------------------------------------------------------------
-- GUI
--------------------------------------------------------------------
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "SpeedGainTracker"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = PlayerGui

local Frame = Instance.new("Frame")
Frame.Size = UDim2.new(0, 250, 0, 260)
Frame.Position = UDim2.new(0.02, 0, 0.65, 0)
Frame.BackgroundColor3 = Color3.fromRGB(25, 25, 28)
Frame.BorderSizePixel = 0
Frame.Active = true
Frame.Parent = ScreenGui
Instance.new("UICorner", Frame).CornerRadius = UDim.new(0, 8)

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, 0, 0, 28)
Title.BackgroundTransparency = 1
Title.Text = "Speed & Treadmill Tracker"
Title.TextColor3 = Color3.new(1, 1, 1)
Title.TextSize = 14
Title.Font = Enum.Font.GothamBold
Title.Parent = Frame

local StatusLabel = Instance.new("TextLabel")
StatusLabel.Size = UDim2.new(1, -20, 0, 190)
StatusLabel.Position = UDim2.new(0, 10, 0, 30)
StatusLabel.BackgroundTransparency = 1
StatusLabel.TextColor3 = Color3.fromRGB(0, 255, 128)
StatusLabel.TextSize = 13
StatusLabel.Font = Enum.Font.Gotham
StatusLabel.TextXAlignment = Enum.TextXAlignment.Left
StatusLabel.TextYAlignment = Enum.TextYAlignment.Top
StatusLabel.Parent = Frame

local ResetButton = Instance.new("TextButton")
ResetButton.Size = UDim2.new(1, -20, 0, 28)
ResetButton.Position = UDim2.new(0, 10, 1, -36)
ResetButton.BackgroundColor3 = Color3.fromRGB(50, 50, 56)
ResetButton.BorderSizePixel = 0
ResetButton.Text = "Reset Session"
ResetButton.TextColor3 = Color3.new(1, 1, 1)
ResetButton.TextSize = 13
ResetButton.Font = Enum.Font.GothamBold
ResetButton.Parent = Frame
Instance.new("UICorner", ResetButton).CornerRadius = UDim.new(0, 6)

--------------------------------------------------------------------
-- Dragging (connection to InputChanged only lives while dragging)
--------------------------------------------------------------------
do
    local dragInput, dragStart, startPos, moveConn

    Frame.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
            dragStart = input.Position
            startPos = Frame.Position

            if moveConn then moveConn:Disconnect() end
            moveConn = UserInputService.InputChanged:Connect(function(changed)
                if changed.UserInputType == Enum.UserInputType.MouseMovement
                    or changed == dragInput then
                    local d = changed.Position - dragStart
                    Frame.Position = UDim2.new(
                        startPos.X.Scale, startPos.X.Offset + d.X,
                        startPos.Y.Scale, startPos.Y.Offset + d.Y
                    )
                end
            end)

            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End and moveConn then
                    moveConn:Disconnect()
                    moveConn = nil
                end
            end)
        end
    end)
end

--------------------------------------------------------------------
-- Session state
--------------------------------------------------------------------
local currentSpeed = readStat(speedStat)
local initialSpeed = currentSpeed
local active = not AUTO_SESSION -- with auto mode we wait for you to start walking
local startClock = os.clock()
local lastGainClock = os.clock()
local lastSession = nil -- {gain, duration}
local myPlot = getMyPlotFolder()

local samples = {{t = startClock, v = currentSpeed}}

local function pushSample(now, value)
    samples[#samples + 1] = {t = now, v = value}
    while #samples > 2 and now - samples[2].t > WINDOW do
        table.remove(samples, 1)
    end
end

local function getRate(now)
    if not active then return 0 end
    local first = samples[1]
    local dt = now - first.t
    if dt < 0.25 then return 0 end
    return (currentSpeed - first.v) / dt
end

local function render()
    local now = os.clock()
    local elapsed = active and (now - startClock) or 0
    local gain = active and (currentSpeed - initialSpeed) or 0
    local rate = getRate(now)
    local perHour = elapsed > 1 and (gain / elapsed) * 3600 or 0

    local statusText = active and "ACTIVE" or "IDLE (walk on treadmill)"
    if not AUTO_SESSION then statusText = "MANUAL" end

    local lastText = "-"
    if lastSession then
        lastText = string.format("+%s in %s", formatCompact(lastSession.gain, 2), formatTime(lastSession.duration))
    end

    StatusLabel.TextColor3 = active and Color3.fromRGB(0, 255, 128) or Color3.fromRGB(255, 200, 80)
    StatusLabel.Text = string.format(
        "Status: %s\nPlot: %s\nCurrent: %s\nInitial: %s\nGain: %s%s\nSpeed/s (10s): %s\nAvg/hr: %s\nTreadmill Lvl: %s\nTime: %s\nLast session: %s",
        statusText,
        myPlot and myPlot.Name or "Unknown",
        formatCompact(currentSpeed, 3),
        formatCompact(active and initialSpeed or currentSpeed, 1),
        gain >= 0 and "+" or "", formatCompact(gain, 2),
        formatCompact(rate, 2),
        formatCompact(perHour, 2),
        treadmillLevel,
        formatTime(elapsed),
        lastText
    )
end

requestRefresh = render

local anchorPos = nil     -- where you were standing when the session started
local lockoutUntil = 0    -- Speed gains can't start a session before this time

local function getHRP()
    local character = LocalPlayer.Character
    return character and character:FindFirstChild("HumanoidRootPart")
end

local function startSession(baseline)
    active = true
    initialSpeed = baseline or currentSpeed
    startClock = os.clock()
    lastGainClock = startClock
    local hrp = getHRP()
    anchorPos = hrp and hrp.Position or nil
    samples = {{t = startClock, v = initialSpeed}}
    render()
end

local function stopSession(reason, lockout)
    -- Even if the session is already idle, still apply the lockout so a
    -- jump immediately followed by a Speed tick doesn't restart it.
    if lockout then
        lockoutUntil = os.clock() + lockout
    end
    if not active then return end
    if DEBUG then print("[SpeedTracker] session stopped:", tostring(reason)) end
    local now = os.clock()
    local gain = currentSpeed - initialSpeed
    if gain > 0 then
        lastSession = {gain = gain, duration = now - startClock}
    end
    active = false
    initialSpeed = currentSpeed
    startClock = now
    samples = {{t = now, v = currentSpeed}}
    render()
end

--------------------------------------------------------------------
-- Realtime hooks
--------------------------------------------------------------------
local function onSpeedChanged()
    local newSpeed = readStat(speedStat)
    local previous = currentSpeed
    currentSpeed = newSpeed
    local now = os.clock()

    if newSpeed > previous then
        -- Speed started rising -> you're on the treadmill -> start session
        if AUTO_SESSION and not active then
            if now >= lockoutUntil then
                startSession(previous)
            end
        end
        lastGainClock = now
    end

    if active then
        pushSample(now, newSpeed)
    end
    render()
end

local function hookSpeedStat(stat)
    stat:GetPropertyChangedSignal("Value"):Connect(onSpeedChanged)
end
hookSpeedStat(speedStat)

-- Jump (or death) = you left the treadmill -> end/reset the session
local humanoidConns = {}
local function hookCharacter(character)
    for _, c in ipairs(humanoidConns) do c:Disconnect() end
    table.clear(humanoidConns)

    local humanoid = character:WaitForChild("Humanoid", 10)
    if not humanoid then return end

    if STOP_ON_JUMP and AUTO_SESSION then
        -- Several independent signals, because games often override one of them
        table.insert(humanoidConns, humanoid.StateChanged:Connect(function(_, new)
            if new == Enum.HumanoidStateType.Jumping then
                stopSession("humanoid state: Jumping", LEAVE_LOCKOUT)
            end
        end))
        table.insert(humanoidConns, humanoid.Jumping:Connect(function(isJumping)
            if isJumping then
                stopSession("humanoid.Jumping event", LEAVE_LOCKOUT)
            end
        end))
        table.insert(humanoidConns, humanoid:GetPropertyChangedSignal("Jump"):Connect(function()
            if humanoid.Jump then
                stopSession("humanoid.Jump property", LEAVE_LOCKOUT)
            end
        end))
    end
    table.insert(humanoidConns, humanoid.Died:Connect(function()
        stopSession("died", LEAVE_LOCKOUT)
    end))
end

if LocalPlayer.Character then task.spawn(hookCharacter, LocalPlayer.Character) end
LocalPlayer.CharacterAdded:Connect(hookCharacter)

-- Fires whenever you press the jump key/button, even if the game blocks the
-- actual jump or overrides the Humanoid's jump state.
if STOP_ON_JUMP and AUTO_SESSION then
    UserInputService.JumpRequest:Connect(function()
        stopSession("jump input", LEAVE_LOCKOUT)
    end)
end

-- Timer / rate refresh + idle timeout + plot re-check
local acc, plotAcc = 0, 0
RunService.Heartbeat:Connect(function(dt)
    acc += dt
    plotAcc += dt

    if plotAcc >= 2 then
        plotAcc = 0
        local found = getMyPlotFolder()
        if found then myPlot = found end
    end

    if acc >= 0.1 then
        acc = 0
        local now = os.clock()

        if active and AUTO_SESSION then
            if IDLE_TIMEOUT > 0 and now - lastGainClock >= IDLE_TIMEOUT then
                stopSession("idle timeout")
            elseif LEAVE_DISTANCE > 0 and anchorPos then
                local hrp = getHRP()
                if hrp and (hrp.Position - anchorPos).Magnitude > LEAVE_DISTANCE then
                    stopSession("moved away from treadmill", LEAVE_LOCKOUT)
                end
            end
        end

        while #samples > 1 and now - samples[1].t > WINDOW do
            table.remove(samples, 1)
        end
        render()
    end
end)

ResetButton.MouseButton1Click:Connect(function()
    currentSpeed = readStat(speedStat)
    if AUTO_SESSION then
        stopSession()
        lastSession = nil
        render()
    else
        startSession(currentSpeed)
    end
end)

-- Re-hook if the Speed object is ever replaced
leaderstats.ChildAdded:Connect(function(child)
    if child.Name == "Speed" and child ~= speedStat then
        speedStat = child
        currentSpeed = readStat(speedStat)
        hookSpeedStat(speedStat)
        render()
    end
end)

render()
print("[SpeedTracker] Initialized (realtime, auto session)")
