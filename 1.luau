--// Preventing Multiple Processes
pcall(function()
	getgenv().Aimbot.Functions:Exit()
end)

--// Environment
getgenv().Aimbot = {}
local Environment = getgenv().Aimbot

--// Services
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")
local StarterGui = game:GetService("StarterGui")
local Players = game:GetService("Players")
local Camera = workspace.CurrentCamera
local Stats = game:GetService("Stats")

--// Variables
local LocalPlayer = Players.LocalPlayer
local Title = "Exunys Developer"
local FileNames = {"Aimbot", "Configuration.json", "Drawing.json", "Prediction.json"}
local Typing, Running, Animation, RequiredDistance, ServiceConnections = false, false, nil, 2000, {}

if isfolder(Title) then
    delfolder(Title)
end

--// Support Functions
local mousemoverel = mousemoverel or (Input and Input.MouseMove)
local queueonteleport = queue_on_teleport or syn.queue_on_teleport

--// Script Settings
Environment.Settings = {
	SendNotifications = false,
	SaveSettings = true, -- Re-execute upon changing
	ReloadOnTeleport = false,
	Enabled = false,
	TeamCheck = false,
	AliveCheck = true,
	WallCheck = false, -- Optimized in this version
	Sensitivity = 0, -- Animation length (in seconds) before fully locking onto target
	ThirdPerson = false, -- Uses mousemoverel instead of CFrame to support locking in third person
	ThirdPersonSensitivity = 3, -- Boundary: 0.1 - 5
	TriggerKey = "MouseButton2",
	Toggle = false,
	CopMode = false,
	PrisonerMode = false,
	LockPart = "Head" -- Body part to lock on
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

-- Improved prediction settings
Environment.PredictionSettings = {
	Enabled = true,
	PredictionMode = "ping", -- "Default", "Ping", "Custom"
	DefaultPrediction = 0.165,
	PingBasedMultiplier = 0.00075, -- Adjusted for better accuracy
	CustomPrediction = 0.2
}

-- TriggerBot settings
Environment.TriggerBot = {
    Enabled = false,
    Debounce = false,
    Connection = nil
}

Environment.FOVCircle = Drawing.new("Circle")
Environment.Locked = nil
Environment.LastPing = 0
Environment.LastPrediction = 0

--// Core Functions
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

--// Functions
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

-- Optimized prediction calculation
local function GetPredictionValue()
	if not Environment.PredictionSettings.Enabled then
		return 0
	end
	
	local prediction = 0
	
	if Environment.PredictionSettings.PredictionMode == "Default" then
		prediction = Environment.PredictionSettings.DefaultPrediction
	elseif Environment.PredictionSettings.PredictionMode == "Ping" then
		-- Only update ping every few frames to reduce performance impact
		if tick() - Environment.LastPing > 0.5 then
			Environment.LastPing = tick()
			local ping = Stats.Network.ServerStatsItem["Data Ping"]:GetValue() / 1000
			prediction = ping * Environment.PredictionSettings.PingBasedMultiplier
			Environment.LastPrediction = prediction
		else
			prediction = Environment.LastPrediction
		end
	elseif Environment.PredictionSettings.PredictionMode == "Custom" then
		prediction = Environment.PredictionSettings.CustomPrediction
	end
	
	return prediction
end

-- Optimized wall check function
local function IsTargetVisible(target, targetPart)
    if not Environment.Settings.WallCheck then return true end
    
    -- Use a raycast for better performance
    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Blacklist
    rayParams.FilterDescendantsInstances = {LocalPlayer.Character, Camera}
    
    local targetPosition = targetPart.Position
    local cameraPosition = Camera.CFrame.Position
    local direction = (targetPosition - cameraPosition).Unit
    
    -- Single raycast for best performance
    local result = workspace:Raycast(cameraPosition, direction * 1000, rayParams)
    return result and result.Instance:IsDescendantOf(target.Character)
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

-- Optimized GetClosestPlayer function
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
            if player ~= LocalPlayer then
                local character = player.Character
                if character then
                    local targetPart = character:FindFirstChild(Environment.Settings.LockPart)
                    local humanoid = character:FindFirstChildOfClass("Humanoid")
                    
                    if targetPart and humanoid then
                        -- Team and mode checks
                        if Environment.Settings.CopMode and not IsPlayerInTeamCategory(player, "Prisoner") then
                            continue
                        end
                        if Environment.Settings.PrisonerMode and not IsPlayerInTeamCategory(player, "Cop") then
                            continue
                        end
                        if Environment.Settings.TeamCheck and player.Team == LocalPlayer.Team then 
                            continue 
                        end
                        if Environment.Settings.AliveCheck and humanoid.Health <= 0 then 
                            continue 
                        end
                        
                        -- Check if target is on screen
                        local vector, onScreen = Camera:WorldToViewportPoint(targetPart.Position)
                        if not onScreen then continue end
                        
                        -- Calculate distance from mouse
                        local distance = (Vector2.new(mousePos.X, mousePos.Y) - Vector2.new(vector.X, vector.Y)).Magnitude
                        
                        -- Check if within FOV and closer than previous targets
                        if distance < RequiredDistance then
                            -- Only perform wall check if needed (it's expensive)
                            if not Environment.Settings.WallCheck or IsTargetVisible(player, targetPart) then
                                RequiredDistance = distance
                                closestPlayer = player
                            end
                        end
                    end
                end
            end
        end
        
        Environment.Locked = closestPlayer
    elseif Environment.Locked and Environment.Locked.Character then
        local targetPart = Environment.Locked.Character:FindFirstChild(Environment.Settings.LockPart)
        if not targetPart then
            Environment.Locked = nil
            if Animation then Animation:Cancel() end
            Environment.FOVCircle.Color = GetColor(Environment.FOVSettings.Color)
            return
        end
        
        local vector, onScreen = Camera:WorldToViewportPoint(targetPart.Position)
        if not onScreen then
            Environment.Locked = nil
            if Animation then Animation:Cancel() end
            Environment.FOVCircle.Color = GetColor(Environment.FOVSettings.Color)
            return
        end
        
        local mousePos = UserInputService:GetMouseLocation()
        local distance = (Vector2.new(mousePos.X, mousePos.Y) - Vector2.new(vector.X, vector.Y)).Magnitude
        
        if distance > RequiredDistance or (Environment.Settings.WallCheck and not IsTargetVisible(Environment.Locked, targetPart)) then
            Environment.Locked = nil
            if Animation then Animation:Cancel() end
            Environment.FOVCircle.Color = GetColor(Environment.FOVSettings.Color)
        end
    else
        Environment.Locked = nil
        if Animation then Animation:Cancel() end
        Environment.FOVCircle.Color = GetColor(Environment.FOVSettings.Color)
    end
end

-- TriggerBot implementation
local function SetupTriggerBot()
    if Environment.TriggerBot.Connection then
        Environment.TriggerBot.Connection:Disconnect()
        Environment.TriggerBot.Connection = nil
    end
    
    Environment.TriggerBot.Connection = RunService.RenderStepped:Connect(function()
        if not Environment.TriggerBot.Enabled then return end
        if Environment.TriggerBot.Debounce then return end
        
        local Mouse = LocalPlayer:GetMouse()
        local Target = Mouse.Target
        
        if not Target or not Target.Parent then return end
        
        local Player = Players:GetPlayerFromCharacter(Target.Parent)
        if not Player then return end
        
        -- Apply the same filters as the aimbot
        if Environment.Settings.TeamCheck and Player.Team == LocalPlayer.Team then return end
        
        if Environment.Settings.CopMode and not IsPlayerInTeamCategory(Player, "Prisoner") then
            return
        end
        
        if Environment.Settings.PrisonerMode and not IsPlayerInTeamCategory(Player, "Cop") then
            return
        end
        
        local Character = Player.Character
        if not Character then return end
        
        local Humanoid = Character:FindFirstChildOfClass("Humanoid")
        if Environment.Settings.AliveCheck and (not Humanoid or Humanoid.Health <= 0) then return end
        
        if Character:FindFirstChildOfClass("ForceField") then return end
        
        if Environment.Settings.WallCheck and not IsTargetVisible(Player, Target) then
            return
        end
        
        -- All checks passed, fire the trigger
        Environment.TriggerBot.Debounce = true
        
        task.spawn(function()
            mouse1press()
            
            -- Wait until no longer targeting the player or until disabled
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

--// Typing Check
ServiceConnections.TypingStartedConnection = UserInputService.TextBoxFocused:Connect(function()
    Typing = true
end)

ServiceConnections.TypingEndedConnection = UserInputService.TextBoxFocusReleased:Connect(function()
    Typing = false
end)

--// Create, Save & Load Settings
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
    
        -- Auto-save settings periodically
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
    -- Update FOV circle in a separate connection for better performance
    ServiceConnections.FOVUpdateConnection = RunService.RenderStepped:Connect(function()
        if Environment.FOVSettings.Enabled and Environment.Settings.Enabled then
            Environment.FOVCircle.Radius = Environment.FOVSettings.Amount
            Environment.FOVCircle.Thickness = Environment.FOVSettings.Thickness
            Environment.FOVCircle.Filled = Environment.FOVSettings.Filled
            Environment.FOVCircle.NumSides = Environment.FOVSettings.Sides
            Environment.FOVCircle.Color = GetColor(Environment.FOVSettings.Color)
            Environment.FOVCircle.Transparency = Environment.FOVSettings.Transparency
            Environment.FOVCircle.Visible = Environment.FOVSettings.Visible
            Environment.FOVCircle.Position = Vector2.new(UserInputService:GetMouseLocation().X, UserInputService:GetMouseLocation().Y)
        else
            Environment.FOVCircle.Visible = false
        end
    end)

    -- Main aimbot logic
    ServiceConnections.RenderSteppedConnection = RunService.RenderStepped:Connect(function()
        if Running and Environment.Settings.Enabled then
            GetClosestPlayer()
            if Environment.Locked and Environment.Locked.Character and Environment.Locked.Character:FindFirstChild(Environment.Settings.LockPart) then
                local targetPart = Environment.Locked.Character[Environment.Settings.LockPart]
                local predictionValue = GetPredictionValue()
                local predictedPosition = targetPart.Position + (targetPart.Velocity * predictionValue)
                
                if Environment.Settings.ThirdPerson then
                    Environment.Settings.ThirdPersonSensitivity = math.clamp(Environment.Settings.ThirdPersonSensitivity, 0.1, 5)
                    local Vector = Camera:WorldToViewportPoint(predictedPosition)
                    mousemoverel(
                        (Vector.X - UserInputService:GetMouseLocation().X) * Environment.Settings.ThirdPersonSensitivity, 
                        (Vector.Y - UserInputService:GetMouseLocation().Y) * Environment.Settings.ThirdPersonSensitivity
                    )
                else
                    if Environment.Settings.Sensitivity > 0 then
                        -- Cancel previous animation if it exists
                        if Animation then
                            Animation:Cancel()
                        end
                        Animation = TweenService:Create(Camera, TweenInfo.new(Environment.Settings.Sensitivity, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {CFrame = CFrame.new(Camera.CFrame.Position, predictedPosition)})
                        Animation:Play()
                    else
                        Camera.CFrame = CFrame.new(Camera.CFrame.Position, predictedPosition)
                    end
                end
                
                -- Set FOV color to locked color
                Environment.FOVCircle.Color = GetColor(Environment.FOVSettings.LockedColor)
            else
                -- Reset FOV color when not locked
                Environment.FOVCircle.Color = GetColor(Environment.FOVSettings.Color)
            end
        end
    end)

    -- Input handling
    ServiceConnections.InputBeganConnection = UserInputService.InputBegan:Connect(function(Input)
        if not Typing then
            pcall(function()
                if Input.KeyCode == Enum.KeyCode[Environment.Settings.TriggerKey] then
                    if Environment.Settings.Toggle then
                        Running = not Running
                        if not Running then
                            Environment.Locked = nil
                            if Animation then
                                Animation:Cancel()
                            end
                            Environment.FOVCircle.Color = GetColor(Environment.FOVSettings.Color)
                        end
                    else
                        Running = true
                    end
                end
            end)
            pcall(function()
                if Input.UserInputType == Enum.UserInputType[Environment.Settings.TriggerKey] then
                    if Environment.Settings.Toggle then
                        Running = not Running
                        if not Running then
                            Environment.Locked = nil
                            if Animation then
                                Animation:Cancel()
                            end
                            Environment.FOVCircle.Color = GetColor(Environment.FOVSettings.Color)
                        end
                    else
                        Running = true
                    end
                end
            end)
        end
    end)

    ServiceConnections.InputEndedConnection = UserInputService.InputEnded:Connect(function(Input)
        if not Typing then
            pcall(function()
                if Input.KeyCode == Enum.KeyCode[Environment.Settings.TriggerKey] then
                    if not Environment.Settings.Toggle then
                        Running = false
                        Environment.Locked = nil
                        if Animation then
                            Animation:Cancel()
                        end
                        Environment.FOVCircle.Color = GetColor(Environment.FOVSettings.Color)
                    end
                end
            end)
            pcall(function()
                if Input.UserInputType == Enum.UserInputType[Environment.Settings.TriggerKey] then
                    if not Environment.Settings.Toggle then
                        Running = false
                        Environment.Locked = nil
                        if Animation then
                            Animation:Cancel()
                        end
                        Environment.FOVCircle.Color = GetColor(Environment.FOVSettings.Color)
                    end
                end
            end)
        end
    end)
    
    -- Initialize TriggerBot
    SetupTriggerBot()
end

--// Functions
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
        PrisonerMode = false
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
end

-- TriggerBot specific functions
function Environment.Functions:ToggleTriggerBot(state)
    Environment.TriggerBot.Enabled = state or not Environment.TriggerBot.Enabled
    return Environment.TriggerBot.Enabled
end

--// Support Check
if not Drawing or not getgenv then
    print("Error: Missing required functions. Your exploit may not be supported.")
end

--// Reload On Teleport
if Environment.Settings.ReloadOnTeleport then
    if queueonteleport then
        queueonteleport(game:HttpGet("https://raw.githubusercontent.com/Exunys/Aimbot-V2/main/Resources/Scripts/Main.lua"))
    else
        print("Queue on teleport not supported by your exploit")
    end
end

--// Load
Load()
