local function IsValidTargetAutoLock(player)
    if not player or not player.Parent or player == LocalPlayer then return false end
    
    local character = player.Character
    if not character or not character.Parent then return false end
    
    local targetPart = character:FindFirstChild(Environment.Settings.LockPart)
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
    
    if not targetPart or not targetPart.Parent or not humanoid or not humanoidRootPart or not humanoidRootPart.Parent then return false end
    
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
    
    return true, targetPart
end-- Process Prevention
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

local LastFrameTime = 0
local LastPredictionUpdate = 0
local PredictionUpdateInterval = 0.1
local LastTargetingUpdate = 0
local TargetingUpdateInterval = 0.05
local CachedPlayers = {}
local PlayerCacheTime = 0
local PlayerCacheInterval = 1

if isfolder(Title) then
    delfolder(Title)
end

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
	Sensitivity = 1,
	ThirdPerson = false,
	ThirdPersonSensitivity = 3,
	TriggerKey = "MouseButton2",
	Toggle = false,
	CopMode = false,
	PrisonerMode = false,
	LockPart = "Head",
	AutoLock = false,
	SmoothingType = "Linear"
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

Environment.TriggerBot = {
    Enabled = false,
    Debounce = false,
    Connection = nil
}

Environment.AutoLock = {
    Enabled = false,
    Connection = nil,
    LastUpdate = 0,
    UpdateInterval = 0.25
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

local function GetSmoothingFactor(sensitivity, deltaTime)
    if sensitivity == 0 then return 1 end
    
    local baseFactor = math.clamp(sensitivity, 1, 10)
    
    if Environment.Settings.SmoothingType == "Exponential" then
        local factor = math.pow(0.1, 1 / baseFactor) 
        return 1 - math.pow(factor, deltaTime * 60)
    elseif Environment.Settings.SmoothingType == "Bezier" then
        local t = math.clamp(1 / baseFactor, 0.1, 1)
        t = t * t * (3 - 2 * t)
        return t * deltaTime * 60
    else
        return math.clamp((1 / baseFactor) * deltaTime * 60, 0.01, 1)
    end
end

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

local function GetPredictionValue()
	if not Environment.PredictionSettings.Enabled then
		return 0
	end
	
	local currentTime = tick()
	
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

local function GetCachedPlayers()
    local currentTime = tick()
    if currentTime - PlayerCacheTime >= PlayerCacheInterval then
        PlayerCacheTime = currentTime
        local players = Players:GetPlayers()
        CachedPlayers = {}
        for i, player in ipairs(players) do
            if player ~= LocalPlayer and player.Parent then
                table.insert(CachedPlayers, player)
            end
        end
    end
    
    local validPlayers = {}
    for _, player in ipairs(CachedPlayers) do
        if player.Parent and player.Character and player.Character.Parent then
            table.insert(validPlayers, player)
        end
    end
    return validPlayers
end

local function IsTargetVisible(target, targetPart)
    if not Environment.Settings.WallCheck then return true end
    if not target or not target.Character or not targetPart or not targetPart.Parent then return false end
    
    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Blacklist
    rayParams.FilterDescendantsInstances = {LocalPlayer.Character, Camera}
    
    local targetPosition = targetPart.Position
    local cameraPosition = Camera.CFrame.Position
    local direction = (targetPosition - cameraPosition)
    
    if direction.Magnitude < 1 then return false end
    direction = direction.Unit
    
    local result = workspace:Raycast(cameraPosition, direction * (targetPosition - cameraPosition).Magnitude, rayParams)
    if not result then
        return true
    end
    return result.Instance and result.Instance:IsDescendantOf(target.Character)
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

local function IsValidTarget(player)
    if not player or not player.Parent or player == LocalPlayer then return false end
    
    local character = player.Character
    if not character or not character.Parent then return false end
    
    local targetPart = character:FindFirstChild(Environment.Settings.LockPart)
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
    
    if not targetPart or not targetPart.Parent or not humanoid or not humanoidRootPart or not humanoidRootPart.Parent then return false end
    
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
    
    if Environment.Settings.WallCheck then
        local visible = IsTargetVisible(player, targetPart)
        if not visible then return false end
    end
    
    return true, targetPart
end

local function GetClosestPlayer()
    local currentTime = tick()
    
    if currentTime - LastTargetingUpdate < TargetingUpdateInterval then
        return
    end
    LastTargetingUpdate = currentTime
    
    if not Environment.Locked then
        if Environment.FOVSettings.Enabled then
            RequiredDistance = Environment.FOVSettings.Amount
        else
            RequiredDistance = 2000
        end
        
        local closestPlayer = nil
        local mousePos = UserInputService:GetMouseLocation()
        
        for _, player in next, GetCachedPlayers() do
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
    elseif Environment.Locked then
        local isValid, targetPart = IsValidTarget(Environment.Locked)
        if not isValid or not targetPart then
            Environment.Locked = nil
            Animation = nil
            Environment.FOVCircle.Color = GetColor(Environment.FOVSettings.Color)
            return
        end
        
        local vector, onScreen = Camera:WorldToViewportPoint(targetPart.Position)
        if not onScreen then
            Environment.Locked = nil
            Animation = nil
            Environment.FOVCircle.Color = GetColor(Environment.FOVSettings.Color)
            return
        end
        
        local mousePos = UserInputService:GetMouseLocation()
        local distance = (Vector2.new(mousePos.X, mousePos.Y) - Vector2.new(vector.X, vector.Y)).Magnitude
        
        if Environment.FOVSettings.Enabled and distance > Environment.FOVSettings.Amount then
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

local function GetClosestPlayerByDistance()
    local currentTime = tick()
    
    if currentTime - Environment.AutoLock.LastUpdate < Environment.AutoLock.UpdateInterval then
        if Environment.Locked and Environment.Locked.Parent then
            local isValid, targetPart = IsValidTargetAutoLock(Environment.Locked)
            if not isValid then
                Environment.Locked = nil
            end
        end
        return Environment.Locked
    end
    Environment.AutoLock.LastUpdate = currentTime
    
    if not LocalPlayer.Character or not LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
        if Environment.Locked then
            Environment.Locked = nil
        end
        return nil
    end
    
    local localPosition = LocalPlayer.Character.HumanoidRootPart.Position
    local closestPlayer = nil
    local shortestDistance = math.huge
    
    if Environment.Locked then
        if not Environment.Locked.Parent then
            Environment.Locked = nil
        else
            local isValid, targetPart = IsValidTargetAutoLock(Environment.Locked)
            if isValid and targetPart and Environment.Locked.Character and Environment.Locked.Character:FindFirstChild("HumanoidRootPart") then
                local humanoidRootPart = Environment.Locked.Character.HumanoidRootPart
                if humanoidRootPart and humanoidRootPart.Parent then
                    local currentDistance = (localPosition - humanoidRootPart.Position).Magnitude
                    shortestDistance = currentDistance
                    closestPlayer = Environment.Locked
                end
            else
                Environment.Locked = nil
            end
        end
    end
    
    for _, player in next, GetCachedPlayers() do
        if player.Parent and player.Character and player.Character.Parent then
            local isValid, targetPart = IsValidTargetAutoLock(player)
            if isValid and targetPart then
                local humanoidRootPart = player.Character:FindFirstChild("HumanoidRootPart")
                if humanoidRootPart and humanoidRootPart.Parent then
                    local distance = (localPosition - humanoidRootPart.Position).Magnitude
                    if distance < shortestDistance - 25 then
                        shortestDistance = distance
                        closestPlayer = player
                    end
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
    
    Environment.AutoLock.Enabled = Environment.Settings.AutoLock
    
    if not Environment.AutoLock.Enabled then 
        if Running and Environment.Settings.AutoLock == false then
            Running = false
            Environment.Locked = nil
        end
        return 
    end
    
    Environment.AutoLock.Connection = RunService.Heartbeat:Connect(function()
        if not Environment.AutoLock.Enabled or not Environment.Settings.AutoLock then return end
        
        if not Running then
            Running = true
        end
        
        Environment.Locked = GetClosestPlayerByDistance()
    end)
end

local function SetupTriggerBot()
    if Environment.TriggerBot.Connection then
        Environment.TriggerBot.Connection:Disconnect()
        Environment.TriggerBot.Connection = nil
    end
    
    if not Environment.TriggerBot.Enabled then return end
    
    Environment.TriggerBot.Connection = RunService.Heartbeat:Connect(function()
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
                RunService.Heartbeat:Wait()
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
        local currentTime = tick()
        local deltaTime = currentTime - LastFrameTime
        LastFrameTime = currentTime
        
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

        if Environment.Settings.Enabled and (Running or Environment.Settings.AutoLock) then
            if not Environment.Settings.AutoLock then
                if Running then
                    GetClosestPlayer()
                end
            end
            
            if Environment.Locked and Environment.Locked.Parent and Environment.Locked.Character and Environment.Locked.Character.Parent and Environment.Locked.Character:FindFirstChild(Environment.Settings.LockPart) then
                local targetPart = Environment.Locked.Character[Environment.Settings.LockPart]
                if targetPart and targetPart.Parent then
                    local predictionValue = GetPredictionValue()
                    local predictedPosition = targetPart.Position + (targetPart.Velocity * predictionValue)
                    
                    if Environment.Settings.ThirdPerson then
                        local Vector = Camera:WorldToViewportPoint(predictedPosition)
                        local mousePos = UserInputService:GetMouseLocation()
                        
                        local deltaX = Vector.X - mousePos.X
                        local deltaY = Vector.Y - mousePos.Y
                        
                        local smoothFactor = GetSmoothingFactor(Environment.Settings.ThirdPersonSensitivity, deltaTime)
                        
                        deltaX = deltaX * smoothFactor
                        deltaY = deltaY * smoothFactor
                        
                        deltaX = math.clamp(deltaX, -150, 150)
                        deltaY = math.clamp(deltaY, -150, 150)
                        
                        mousemoverel(deltaX, deltaY)
                    else
                        local current = Camera.CFrame
                        local targetCFrame = CFrame.new(current.Position, predictedPosition)
                        
                        local lerpFactor = GetSmoothingFactor(Environment.Settings.Sensitivity, deltaTime)
                        
                        if Environment.Settings.Sensitivity == 0 then
                            Camera.CFrame = targetCFrame
                        else
                            Camera.CFrame = current:Lerp(targetCFrame, lerpFactor)
                        end
                    end
                
                    Environment.FOVCircle.Color = GetColor(Environment.FOVSettings.LockedColor)
                else
                    Environment.Locked = nil
                    Environment.FOVCircle.Color = GetColor(Environment.FOVSettings.Color)
                end
            else
                if Environment.Locked then
                    Environment.Locked = nil
                end
                Environment.FOVCircle.Color = GetColor(Environment.FOVSettings.Color)
            end
        else
            Environment.FOVCircle.Color = GetColor(Environment.FOVSettings.Color)
        end
    end)

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
        Sensitivity = 1,
        ThirdPerson = false,
        ThirdPersonSensitivity = 3,
        TriggerKey = "MouseButton2",
        Toggle = false,
        LockPart = "Head",
        CopMode = false,
        PrisonerMode = false,
        AutoLock = false,
        SmoothingType = "Linear"
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
        Connection = nil,
        LastUpdate = 0,
        UpdateInterval = 0.1
    }
end

function Environment.Functions:ToggleTriggerBot(state)
    if state == nil then
        Environment.TriggerBot.Enabled = not Environment.TriggerBot.Enabled
    else
        Environment.TriggerBot.Enabled = state
    end
    SetupTriggerBot()
    return Environment.TriggerBot.Enabled
end

function Environment.Functions:ToggleAutoLock(state)
    if state == nil then
        Environment.Settings.AutoLock = not Environment.Settings.AutoLock
    else
        Environment.Settings.AutoLock = state
    end
    
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

Load()
