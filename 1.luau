-- Process Prevention
pcall(function()
	getgenv().Aimbot.Functions:Exit()
end)

-- Environment Setup
getgenv().Aimbot = {}
local Environment = getgenv().Aimbot

-- Services
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")
local StarterGui = game:GetService("StarterGui")
local Players = game:GetService("Players")
local Camera = workspace.CurrentCamera
local Stats = game:GetService("Stats")

-- Variables
local LocalPlayer = Players.LocalPlayer
local Title = "Exunys Developer"
local FileNames = {"Aimbot", "Configuration.json", "Drawing.json", "Prediction.json"}
local Typing, Running, Animation, RequiredDistance, ServiceConnections = false, false, nil, 2000, {}

-- Performance optimization variables
local LastFrameTime = 0
local LastPredictionUpdate = 0
local PredictionUpdateInterval = 0.1

if isfolder(Title) then
    delfolder(Title)
end

-- Support Functions
local mousemoverel = mousemoverel or (Input and Input.MouseMove)
local queueonteleport = queue_on_teleport or syn.queue_on_teleport

-- Settings
Environment.Settings = {
	SendNotifications = false,
	SaveSettings = true,
	ReloadOnTeleport = false,
	Enabled = false,
	TeamCheck = false,
	AliveCheck = true,
	WallCheck = false,
	Sensitivity = 0, -- 0 = instant, higher = smoother
	ThirdPerson = false,
	ThirdPersonSensitivity = 3,
	TriggerKey = "MouseButton2",
	Toggle = false,
	CopMode = false,
	PrisonerMode = false,
	LockPart = "Head",
	AutoLock = false -- Added AutoLock to settings
}

Environment.FOVSettings = {
	Enabled = true,
	Visible = true,
	Amount = 90,
	Color = "255, 255, 255",
	LockedColor = "255, 70, 70",
	Transparency = 0.5,
	Sides = 60,
	Thickness = 1,
	Filled = false
}

Environment.PredictionSettings = {
	Enabled = true,
	PredictionMode = "ping",
	DefaultPrediction = 0.165,
	PingBasedMultiplier = 0.00075,
	CustomPrediction = 0.2
}

-- TriggerBot Settings
Environment.TriggerBot = {
    Enabled = false,
    Debounce = false,
    Connection = nil
}

-- AutoLock Settings
Environment.AutoLock = {
    Enabled = false,
    Connection = nil
}

Environment.FOVCircle = Drawing.new("Circle")
Environment.Locked = nil
Environment.LastPing = 0
Environment.LastPrediction = 0
Environment.CachedPrediction = 0

-- Core Functions
local function Encode(Table)
	if Table and type(Table) == "table" then
		return HttpService:JSONEncode(Table)
	end
end

local function Decode(String)
	if String and type(String) == "string" then
		return HttpService:JSONDecode(String)
	end
end

local function GetColor(Color)
	local R = tonumber(string.match(Color, "([%d]+)[%s]*,[%s]*[%d]+[%s]*,[%s]*[%d]+"))
	local G = tonumber(string.match(Color, "[%d]+[%s]*,[%s]*([%d]+)[%s]*,[%s]*[%d]+"))
	local B = tonumber(string.match(Color, "[%d]+[%s]*,[%s]*[%d]+[%s]*,[%s]*([%d]+)"))
	return Color3.fromRGB(R, G, B)
end

local function SendNotification(TitleArg, DescriptionArg, DurationArg)
	if Environment.Settings.SendNotifications then
		StarterGui:SetCore("SendNotification", {
			Title = TitleArg,
			Text = DescriptionArg,
			Duration = DurationArg
		})
	end
end

-- Settings Management
local function SaveSettings()
	if Environment.Settings.SaveSettings then
		if isfile(Title.."/"..FileNames[1].."/"..FileNames[2]) then
			writefile(Title.."/"..FileNames[1].."/"..FileNames[2], Encode(Environment.Settings))
		end
		if isfile(Title.."/"..FileNames[1].."/"..FileNames[3]) then
			writefile(Title.."/"..FileNames[1].."/"..FileNames[3], Encode(Environment.FOVSettings))
		end
		if isfile(Title.."/"..FileNames[1].."/"..FileNames[4]) then
			writefile(Title.."/"..FileNames[1].."/"..FileNames[4], Encode(Environment.PredictionSettings))
		end
	end
end

-- Optimized Prediction System
local function GetPredictionValue()
	if not Environment.PredictionSettings.Enabled then
		return 0
	end
	
	local currentTime = tick()
	
	-- Only update prediction periodically for performance
	if currentTime - LastPredictionUpdate >= PredictionUpdateInterval then
		LastPredictionUpdate = currentTime
		
		if Environment.PredictionSettings.PredictionMode == "Default" then
			Environment.CachedPrediction = Environment.PredictionSettings.DefaultPrediction
		elseif Environment.PredictionSettings.PredictionMode == "ping" then
			local ping = Stats.Network.ServerStatsItem["Data Ping"]:GetValue() / 1000
			Environment.CachedPrediction = ping * Environment.PredictionSettings.PingBasedMultiplier
		elseif Environment.PredictionSettings.PredictionMode == "Custom" then
			Environment.CachedPrediction = Environment.PredictionSettings.CustomPrediction
		end
	end
	
	return Environment.CachedPrediction
end

-- Wall Check
local function IsTargetVisible(target, targetPart)
    if not Environment.Settings.WallCheck then return true end
    
    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Blacklist
    rayParams.FilterDescendantsInstances = {LocalPlayer.Character, Camera}
    
    local targetPosition = targetPart.Position
    local cameraPosition = Camera.CFrame.Position
    local direction = (targetPosition - cameraPosition).Unit
    
    local result = workspace:Raycast(cameraPosition, direction * 1000, rayParams)
    if not result then
        return true
    end
    return result.Instance:IsDescendantOf(target.Character)
end

function IsPlayerInTeamCategory(player, category)
    if not player or not player.Team then return false end
    
    local teamName = player.Team.Name
    if category == "Prisoner" then
        local prisonerTeams = {
            "Booking",
            "Escapee",
            "Maximum Security",
            "Medium Security",
            "Minimum Security"
        }
        
        for _, team in ipairs(prisonerTeams) do
            if teamName == team then
                return true
            end
        end
    elseif category == "Cop" then
        local copTeams = {
            "Civilian",
            "Department of Corrections",
            "Sheriff's Office",
            "State Police",
            "VCSO-SWAT",
            "WeaponsTester"
        }
        
        for _, team in ipairs(copTeams) do
            if teamName == team then
                return true
            end
        end
    end
    
    return false
end

-- Player validation function for both regular and autolock
local function IsValidTarget(player)
    if player == LocalPlayer then return false end
    
    local character = player.Character
    if not character then return false end
    
    local targetPart = character:FindFirstChild(Environment.Settings.LockPart)
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    
    if not targetPart or not humanoid then return false end
    
    -- Team mode checks
    if Environment.Settings.CopMode and not IsPlayerInTeamCategory(player, "Prisoner") then
        return false
    end
    if Environment.Settings.PrisonerMode and not IsPlayerInTeamCategory(player, "Cop") then
        return false
    end
    if Environment.Settings.TeamCheck and player.Team == LocalPlayer.Team then 
        return false 
    end
    if Environment.Settings.AliveCheck and humanoid.Health <= 0 then 
        return false 
    end
    if Environment.Settings.WallCheck and not IsTargetVisible(player, targetPart) then
        return false
    end
    
    return true, targetPart
end

-- Target Selection (Regular aimbot - closest to crosshair)
local function GetClosestPlayer()
    if not Environment.Locked then
        if Environment.FOVSettings.Enabled then
            RequiredDistance = Environment.FOVSettings.Amount
        else
            RequiredDistance = 2000
        end
        
        local closestPlayer = nil
        local mousePos = UserInputService:GetMouseLocation()
        
        for _, player in next, Players:GetPlayers() do
            local isValid, targetPart = IsValidTarget(player)
            if isValid then
                local vector, onScreen = Camera:WorldToViewportPoint(targetPart.Position)
                if onScreen then
                    local distance = (Vector2.new(mousePos.X, mousePos.Y) - Vector2.new(vector.X, vector.Y)).Magnitude
                    
                    if distance < RequiredDistance then
                        RequiredDistance = distance
                        closestPlayer = player
                    end
                end
            end
        end
        
        Environment.Locked = closestPlayer
    elseif Environment.Locked and Environment.Locked.Character then
        local isValid = IsValidTarget(Environment.Locked)
        if not isValid then
            Environment.Locked = nil
            Animation = nil
            Environment.FOVCircle.Color = GetColor(Environment.FOVSettings.Color)
            return
        end
        
        local targetPart = Environment.Locked.Character:FindFirstChild(Environment.Settings.LockPart)
        local vector, onScreen = Camera:WorldToViewportPoint(targetPart.Position)
        if not onScreen then
            Environment.Locked = nil
            Animation = nil
            Environment.FOVCircle.Color = GetColor(Environment.FOVSettings.Color)
            return
        end
        
        local mousePos = UserInputService:GetMouseLocation()
        local distance = (Vector2.new(mousePos.X, mousePos.Y) - Vector2.new(vector.X, vector.Y)).Magnitude
        
        if distance > RequiredDistance then
            Environment.Locked = nil
            Animation = nil
            Environment.FOVCircle.Color = GetColor(Environment.FOVSettings.Color)
        end
    else
        Environment.Locked = nil
        Animation = nil
        Environment.FOVCircle.Color = GetColor(Environment.FOVSettings.Color)
    end
end

-- AutoLock - Locks onto closest player by distance to LocalPlayer
local function GetClosestPlayerByDistance()
    local closestPlayer = nil
    local shortestDistance = math.huge
    
    if not LocalPlayer.Character or not LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
        return nil
    end
    
    local localPosition = LocalPlayer.Character.HumanoidRootPart.Position
    
    for _, player in next, Players:GetPlayers() do
        local isValid, targetPart = IsValidTarget(player)
        if isValid then
            local humanoidRootPart = player.Character:FindFirstChild("HumanoidRootPart")
            if humanoidRootPart then
                local distance = (localPosition - humanoidRootPart.Position).Magnitude
                if distance < shortestDistance then
                    shortestDistance = distance
                    closestPlayer = player
                end
            end
        end
    end
    
    return closestPlayer
end

local function SetupAutoLock()
    if Environment.AutoLock.Connection then
        Environment.AutoLock.Connection:Disconnect()
        Environment.AutoLock.Connection = nil
    end
    
    -- Sync AutoLock.Enabled with Settings.AutoLock
    Environment.AutoLock.Enabled = Environment.Settings.AutoLock
    
    if not Environment.AutoLock.Enabled then 
        -- If AutoLock is disabled, reset Running state
        if Running and Environment.Settings.AutoLock == false then
            Running = false
            Environment.Locked = nil
        end
        return 
    end
    
    Environment.AutoLock.Connection = RunService.RenderStepped:Connect(function()
        if not Environment.AutoLock.Enabled or not Environment.Settings.AutoLock then return end
        
        -- AutoLock automatically enables the aimbot (like holding trigger key)
        if not Running then
            Running = true
        end
        
        -- Check if current target is still valid
        if Environment.Locked then
            local isValid = IsValidTarget(Environment.Locked)
            if not isValid then
                Environment.Locked = nil
            end
        end
        
        -- If no valid target, find closest player by distance
        if not Environment.Locked then
            Environment.Locked = GetClosestPlayerByDistance()
        end
    end)
end

-- TriggerBot Loop
local function SetupTriggerBot()
    if Environment.TriggerBot.Connection then
        Environment.TriggerBot.Connection:Disconnect()
        Environment.TriggerBot.Connection = nil
    end
    
    if not Environment.TriggerBot.Enabled then return end
    
    Environment.TriggerBot.Connection = RunService.RenderStepped:Connect(function()
        if not Environment.TriggerBot.Enabled then return end
        if Environment.TriggerBot.Debounce then return end
        
        local Mouse = LocalPlayer:GetMouse()
        local Target = Mouse.Target
        
        if not Target or not Target.Parent then return end
        
        local Player = Players:GetPlayerFromCharacter(Target.Parent)
        if not Player then return end
        
        local isValid = IsValidTarget(Player)
        if not isValid then return end
        
        local Character = Player.Character
        if Character:FindFirstChildOfClass("ForceField") then return end
        
        Environment.TriggerBot.Debounce = true
        
        task.spawn(function()
            mouse1press()
            
            repeat
                RunService.RenderStepped:Wait()
                local CurrentTarget = Mouse.Target
                local CurrentPlayer = CurrentTarget and CurrentTarget.Parent and Players:GetPlayerFromCharacter(CurrentTarget.Parent)
                
                if not CurrentTarget or not CurrentPlayer or CurrentPlayer ~= Player then
                    break
                end
            until not Environment.TriggerBot.Enabled
            
            mouse1release()
            Environment.TriggerBot.Debounce = false
        end)
    end)
end

-- Input Detection
ServiceConnections.TypingStartedConnection = UserInputService.TextBoxFocused:Connect(function()
    Typing = true
end)

ServiceConnections.TypingEndedConnection = UserInputService.TextBoxFocusReleased:Connect(function()
    Typing = false
end)

-- File System
if Environment.Settings.SaveSettings then
    if not isfolder(Title) then
        makefolder(Title)
    end
    if not isfolder(Title.."/"..FileNames[1]) then
        makefolder(Title.."/"..FileNames[1])
    end
    if not isfile(Title.."/"..FileNames[1].."/"..FileNames[2]) then
        writefile(Title.."/"..FileNames[1].."/"..FileNames[2], Encode(Environment.Settings))
    else
        Environment.Settings = Decode(readfile(Title.."/"..FileNames[1].."/"..FileNames[2]))
    end
    if not isfile(Title.."/"..FileNames[1].."/"..FileNames[3]) then
        writefile(Title.."/"..FileNames[1].."/"..FileNames[3], Encode(Environment.FOVSettings))
    else
        Environment.FOVSettings = Decode(readfile(Title.."/"..FileNames[1].."/"..FileNames[3]))
    end
    if not isfile(Title.."/"..FileNames[1].."/"..FileNames[4]) then
        writefile(Title.."/"..FileNames[1].."/"..FileNames[4], Encode(Environment.PredictionSettings))
    else
        Environment.PredictionSettings = Decode(readfile(Title.."/"..FileNames[1].."/"..FileNames[4]))
    end
    
    task.spawn(function()
        while task.wait(10) do
            if not Environment.Settings or not Environment.Settings.SaveSettings then break end
            SaveSettings()
        end
    end)
else
    if isfolder(Title) then
        delfolder(Title)
    end
end

local function Load()
    ServiceConnections.RenderSteppedConnection = RunService.RenderStepped:Connect(function()
        
        -- FOV Circle updates (optimized - only update when needed)
        if Environment.FOVSettings.Enabled and Environment.Settings.Enabled then
            Environment.FOVCircle.Radius = Environment.FOVSettings.Amount
            Environment.FOVCircle.Thickness = Environment.FOVSettings.Thickness
            Environment.FOVCircle.Filled = Environment.FOVSettings.Filled
            Environment.FOVCircle.NumSides = Environment.FOVSettings.Sides
            Environment.FOVCircle.Transparency = Environment.FOVSettings.Transparency
            Environment.FOVCircle.Visible = Environment.FOVSettings.Visible
            local mousePos = UserInputService:GetMouseLocation()
            Environment.FOVCircle.Position = Vector2.new(mousePos.X, mousePos.Y)
        else
            Environment.FOVCircle.Visible = false
        end

        -- Main aimbot logic
        if Environment.Settings.Enabled and (Running or Environment.Settings.AutoLock) then
            -- Use AutoLock if enabled, otherwise use regular targeting
            if not Environment.Settings.AutoLock then
                -- Regular aimbot targeting (closest to crosshair) - only when Running
                if Running then
                    GetClosestPlayer()
                end
            end
            -- Note: AutoLock targeting is handled in SetupAutoLock() connection
            
            if Environment.Locked and Environment.Locked.Character and Environment.Locked.Character:FindFirstChild(Environment.Settings.LockPart) then
                local targetPart = Environment.Locked.Character[Environment.Settings.LockPart]
                local predictionValue = GetPredictionValue()
                local predictedPosition = targetPart.Position + (targetPart.Velocity * predictionValue)
                
                if Environment.Settings.ThirdPerson then
                    -- Fixed smoothing logic for third person (consistent with first person)
                    local sensitivity = math.clamp(Environment.Settings.ThirdPersonSensitivity, 0.1, 10)
                    local Vector = Camera:WorldToViewportPoint(predictedPosition)
                    local mousePos = UserInputService:GetMouseLocation()
                    
                    local deltaX = Vector.X - mousePos.X
                    local deltaY = Vector.Y - mousePos.Y
                    
                    -- Consistent smoothing logic: higher sensitivity = smoother/weaker
                    local smoothFactor = 1 / (sensitivity * 10) -- Adjusted multiplier for consistency
                    
                    deltaX = deltaX * smoothFactor
                    deltaY = deltaY * smoothFactor
                    
                    -- Clamp movement to prevent overshooting
                    deltaX = math.clamp(deltaX, -100, 100)
                    deltaY = math.clamp(deltaY, -100, 100)
                    
                    mousemoverel(deltaX, deltaY)
                else
                    -- First person smoothing
                    local current = Camera.CFrame
                    local targetCFrame = CFrame.new(current.Position, predictedPosition)
                    
                    if Environment.Settings.Sensitivity > 0 then
                        -- Higher sensitivity = smoother/weaker
                        local lerpFactor = math.clamp(1 / (Environment.Settings.Sensitivity * 10), 0.01, 1.0)
                        Camera.CFrame = current:Lerp(targetCFrame, lerpFactor)
                    else
                        -- 0 sensitivity = instant aim
                        Camera.CFrame = targetCFrame
                    end
                end
            
                Environment.FOVCircle.Color = GetColor(Environment.FOVSettings.LockedColor)
            else
                Environment.FOVCircle.Color = GetColor(Environment.FOVSettings.Color)
            end
        else
            Environment.FOVCircle.Color = GetColor(Environment.FOVSettings.Color)
        end
    end)

    -- Input handling (Simplified and optimized)
    local function HandleTriggerInput(active)
        if Environment.Settings.Toggle then
            if active then
                Running = not Running
                if not Running then
                    Environment.Locked = nil
                    Animation = nil
                    Environment.FOVCircle.Color = GetColor(Environment.FOVSettings.Color)
                end
            end
        else
            Running = active
            if not Running then
                Environment.Locked = nil
                Animation = nil
                Environment.FOVCircle.Color = GetColor(Environment.FOVSettings.Color)
            end
        end
    end
    
    local function IsInputTriggerKey(input)
        return (input.KeyCode and input.KeyCode.Name == Environment.Settings.TriggerKey) or
               (input.UserInputType and input.UserInputType.Name == Environment.Settings.TriggerKey)
    end
    
    ServiceConnections.InputBeganConnection = UserInputService.InputBegan:Connect(function(Input)
        if not Typing and IsInputTriggerKey(Input) then
            HandleTriggerInput(true)
        end
    end)

    ServiceConnections.InputEndedConnection = UserInputService.InputEnded:Connect(function(Input)
        if not Typing and IsInputTriggerKey(Input) then
            HandleTriggerInput(false)
        end
    end)
    
    SetupTriggerBot()
    SetupAutoLock()
end

-- API Functions
Environment.Functions = {}

function Environment.Functions:Exit()
    SaveSettings()
    for _, v in next, ServiceConnections do
        v:Disconnect()
    end
    
    if Environment.TriggerBot.Connection then
        Environment.TriggerBot.Connection:Disconnect()
        Environment.TriggerBot.Connection = nil
    end
    
    if Environment.AutoLock.Connection then
        Environment.AutoLock.Connection:Disconnect()
        Environment.AutoLock.Connection = nil
    end
    
    if Environment.FOVCircle.Remove then Environment.FOVCircle:Remove() end
    getgenv().Aimbot.Functions = nil
    getgenv().Aimbot = nil
end

function Environment.Functions:Restart()
    SaveSettings()
    for _, v in next, ServiceConnections do
        v:Disconnect()
    end
    
    if Environment.TriggerBot.Connection then
        Environment.TriggerBot.Connection:Disconnect()
        Environment.TriggerBot.Connection = nil
    end
    
    if Environment.AutoLock.Connection then
        Environment.AutoLock.Connection:Disconnect()
        Environment.AutoLock.Connection = nil
    end
    
    Load()
end

function Environment.Functions:ResetSettings()
    Environment.Settings = {
        SendNotifications = true,
        SaveSettings = true,
        ReloadOnTeleport = true,
        Enabled = true,
        TeamCheck = false,
        AliveCheck = true,
        WallCheck = false,
        Sensitivity = 0,
        ThirdPerson = false,
        ThirdPersonSensitivity = 3,
        TriggerKey = "MouseButton2",
        Toggle = false,
        LockPart = "Head",
        CopMode = false,
        PrisonerMode = false,
        AutoLock = false
    }
    
    Environment.FOVSettings = {
        Enabled = true,
        Visible = true,
        Amount = 90,
        Color = "255, 255, 255",
        LockedColor = "255, 70, 70",
        Transparency = 0.5,
        Sides = 60,
        Thickness = 1,
        Filled = false
    }
    
    Environment.PredictionSettings = {
        Enabled = true,
        PredictionMode = "Ping",
        DefaultPrediction = 0.165,
        PingBasedMultiplier = 0.00075,
        CustomPrediction = 0.2
    }
    
    Environment.TriggerBot = {
        Enabled = false,
        Debounce = false,
        Connection = nil
    }
    
    Environment.AutoLock = {
        Enabled = false,
        Connection = nil
    }
end

-- TriggerBot specific functions
function Environment.Functions:ToggleTriggerBot(state)
    if state == nil then
        Environment.TriggerBot.Enabled = not Environment.TriggerBot.Enabled
    else
        Environment.TriggerBot.Enabled = state
    end
    SetupTriggerBot()
    return Environment.TriggerBot.Enabled
end

-- AutoLock specific functions
function Environment.Functions:ToggleAutoLock(state)
    if state == nil then
        Environment.Settings.AutoLock = not Environment.Settings.AutoLock
    else
        Environment.Settings.AutoLock = state
    end
    
    -- When disabling AutoLock, stop the aimbot
    if not Environment.Settings.AutoLock then
        Running = false
        Environment.Locked = nil
        Animation = nil
        Environment.FOVCircle.Color = GetColor(Environment.FOVSettings.Color)
    end
    
    SetupAutoLock()
    return Environment.Settings.AutoLock
end

-- Support Check
if not Drawing or not getgenv then
    print("Error: Missing required functions. Your exploit may not be supported.")
end

-- Teleport Handler
if Environment.Settings.ReloadOnTeleport then
    if queueonteleport then
        queueonteleport(game:HttpGet("https://raw.githubusercontent.com/Exunys/Aimbot-V2/main/Resources/Scripts/Main.lua"))
    else
        print("Queue on teleport not supported by your exploit")
    end
end

-- Initialize
Load()
