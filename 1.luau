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
local Camera = game:GetService("Workspace").CurrentCamera
local Stats = game:GetService("Stats")

--// Variables
local LocalPlayer = Players.LocalPlayer
local Title = "Exunys Developer"
local FileNames = {"Aimbot", "Configuration.json", "Drawing.json", "Prediction.json", "TeamConfig.json"}
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
	WallCheck = false, -- Laggy
	Sensitivity = 0, -- Animation length (in seconds) before fully locking onto target
	ThirdPerson = false, -- Uses mousemoverel instead of CFrame to support locking in third person (could be choppy)
	ThirdPersonSensitivity = 3, -- Boundary: 0.1 - 5
	TriggerKey = "MouseButton2",
	Toggle = false,
	LockPart = "Head", -- Body part to lock on
	UseTeamConfig = false, -- Enable team-based targeting
	PlayerRole = "Cop" -- "Cop" or "Prisoner"
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

-- New prediction settings
Environment.PredictionSettings = {
	Enabled = false,
	PredictionMode = "Default", -- "Default", "Ping", "Custom"
	DefaultPrediction = 0.165,
	PingBasedMultiplier = 0.001, -- Multiplier for ping-based prediction
	CustomPrediction = 0.2
}

Environment.FOVCircle = Drawing.new("Circle")
Environment.Locked = nil

--// Core Functions
local function Encode(Table)
	if Table and type(Table) == "table" then
		local EncodedTable = HttpService:JSONEncode(Table)
		return EncodedTable
	end
end

local function Decode(String)
	if String and type(String) == "string" then
		local DecodedTable = HttpService:JSONDecode(String)
		return DecodedTable
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

local function IsValidTarget(player)
    if not player.Team then
        return true -- No team assigned, allow targeting
    end
    
    local playerTeamName = player.Team.Name
    
    -- If team check is enabled, don't target same team
    if getgenv().AimbotSettings and getgenv().AimbotSettings.TeamCheck and player.Team == LocalPlayer.Team then
        return false
    end
    
    -- If cop config is enabled, only target cop target teams
    if getgenv().AimbotSettings and getgenv().AimbotSettings.CopConfig and getgenv().CopTargetTeams then
        for _, targetTeam in pairs(getgenv().CopTargetTeams) do
            if playerTeamName == targetTeam then
                return true
            end
        end
        return false
    end
    
    -- If prisoner config is enabled, only target prisoner target teams
    if getgenv().AimbotSettings and getgenv().AimbotSettings.PrisonerConfig and getgenv().PrisonerTargetTeams then
        for _, targetTeam in pairs(getgenv().PrisonerTargetTeams) do
            if playerTeamName == targetTeam then
                return true
            end
        end
        return false
    end
    
    -- If no special configs are enabled, allow all targets (except team check)
    return true
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
		if isfile(Title.."/"..FileNames[1].."/"..FileNames[5]) then
			writefile(Title.."/"..FileNames[1].."/"..FileNames[5], Encode(Environment.TeamConfig))
		end
	end
end

-- Function to get current prediction value based on settings
local function GetPredictionValue()
	if not Environment.PredictionSettings.Enabled then
		return 0
	end
	
	if Environment.PredictionSettings.PredictionMode == "Default" then
		return Environment.PredictionSettings.DefaultPrediction
	elseif Environment.PredictionSettings.PredictionMode == "Ping" then
		local ping = Stats.Network.ServerStatsItem["Data Ping"]:GetValue()
		return ping * Environment.PredictionSettings.PingBasedMultiplier
	elseif Environment.PredictionSettings.PredictionMode == "Custom" then
		return Environment.PredictionSettings.CustomPrediction
	end
	
	return Environment.PredictionSettings.DefaultPrediction
end

local function GetClosestPlayer()
    if not Environment.Locked then
        if Environment.FOVSettings.Enabled then
            RequiredDistance = Environment.FOVSettings.Amount
        else
            RequiredDistance = 2000
        end
        for _, v in next, Players:GetPlayers() do
            if v ~= LocalPlayer then
                if v.Character and v.Character:FindFirstChild(Environment.Settings.LockPart) and v.Character:FindFirstChildOfClass("Humanoid") then
                    if Environment.Settings.TeamCheck and v.Team == LocalPlayer.Team then continue end
                    if Environment.Settings.AliveCheck and v.Character:FindFirstChildOfClass("Humanoid").Health <= 0 then continue end
                    if Environment.Settings.WallCheck and #(Camera:GetPartsObscuringTarget({v.Character[Environment.Settings.LockPart].Position}, v.Character:GetDescendants())) > 0 then continue end
                    
                    -- Team configuration check
                    if not IsValidTarget(v) then continue end
                    
                    local Vector, OnScreen = Camera:WorldToViewportPoint(v.Character[Environment.Settings.LockPart].Position)
                    local Distance = (Vector2.new(UserInputService:GetMouseLocation().X, UserInputService:GetMouseLocation().Y) - Vector2.new(Vector.X, Vector.Y)).Magnitude
                    
                    if Distance < RequiredDistance and OnScreen then
                        RequiredDistance = Distance
                        Environment.Locked = v
                    end
                end
            end
        end
    elseif (Vector2.new(UserInputService:GetMouseLocation().X, UserInputService:GetMouseLocation().Y) - Vector2.new(Camera:WorldToViewportPoint(Environment.Locked.Character[Environment.Settings.LockPart].Position).X, Camera:WorldToViewportPoint(Environment.Locked.Character[Environment.Settings.LockPart].Position).Y)).Magnitude > RequiredDistance then
        Environment.Locked = nil
        if Animation then  -- Add this nil check
            Animation:Cancel()
        end
        Environment.FOVCircle.Color = GetColor(Environment.FOVSettings.Color)
    end
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
		Environment.Visuals = Decode(readfile(Title.."/"..FileNames[1].."/"..FileNames[3]))
	end
	if not isfile(Title.."/"..FileNames[1].."/"..FileNames[4]) then
		writefile(Title.."/"..FileNames[1].."/"..FileNames[4], Encode(Environment.PredictionSettings))
	else
		Environment.PredictionSettings = Decode(readfile(Title.."/"..FileNames[1].."/"..FileNames[4]))
	end
	if not isfile(Title.."/"..FileNames[1].."/"..FileNames[5]) then
		writefile(Title.."/"..FileNames[1].."/"..FileNames[5], Encode(Environment.TeamConfig))
	else
		Environment.TeamConfig = Decode(readfile(Title.."/"..FileNames[1].."/"..FileNames[5]))
	end
	coroutine.wrap(function()
		while wait(10) and Environment.Settings.SaveSettings do
			SaveSettings()
		end
	end)()
else
	if isfolder(Title) then
		delfolder(Title)
	end
end

local function Load()
	ServiceConnections.RenderSteppedConnection = RunService.RenderStepped:Connect(function()
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

		if Running and Environment.Settings.Enabled then
			GetClosestPlayer()
			if Environment.Locked and Environment.Locked.Character and Environment.Locked.Character:FindFirstChild(Environment.Settings.LockPart) then
				local targetPart = Environment.Locked.Character[Environment.Settings.LockPart]
				local predictionValue = GetPredictionValue()
				local predictedPosition = targetPart.Position + (targetPart.Velocity * predictionValue)
				
				if Environment.Settings.ThirdPerson then
					Environment.Settings.ThirdPersonSensitivity = math.clamp(Environment.Settings.ThirdPersonSensitivity, 0.1, 5)
					local Vector = Camera:WorldToViewportPoint(predictedPosition)
					mousemoverel((Vector.X - UserInputService:GetMouseLocation().X) * Environment.Settings.ThirdPersonSensitivity, (Vector.Y - UserInputService:GetMouseLocation().Y) * Environment.Settings.ThirdPersonSensitivity)
				else
					if Environment.Settings.Sensitivity > 0 then
						Animation = TweenService:Create(Camera, TweenInfo.new(Environment.Settings.Sensitivity, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {CFrame = CFrame.new(Camera.CFrame.Position, predictedPosition)})
						Animation:Play()
					else
						Camera.CFrame = CFrame.new(Camera.CFrame.Position, predictedPosition)
					end
				end
				Environment.FOVCircle.Color = GetColor(Environment.FOVSettings.LockedColor)
			end
		end
	end)

		ServiceConnections.InputBeganConnection = UserInputService.InputBegan:Connect(function(Input)
	    if not Typing then
	        pcall(function()
	            if Input.KeyCode == Enum.KeyCode[Environment.Settings.TriggerKey] then
	                if Environment.Settings.Toggle then
	                    Running = not Running
	                    if not Running then
	                        Environment.Locked = nil
	                        if Animation then  -- Add this nil check
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
	                        if Animation then  -- Add this nil check
	                            Animation:Cancel()
	                        end
	                        Environment.FOVCircle.Color = GetColor(Environment.FOVSettings.Color)
	                    end
	                else
	                    Running = true
	                end
	            end
	        end)
	    end  -- This end was missing
	end)

	ServiceConnections.InputEndedConnection = UserInputService.InputEnded:Connect(function(Input)
		if not Typing then
			pcall(function()
				if Input.KeyCode == Enum.KeyCode[Environment.Settings.TriggerKey] then
					if not Environment.Settings.Toggle then
					    Running = false
					    Environment.Locked = nil
					    if Animation then  -- Add this nil check
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
					    if Animation then  -- Add this nil check
					        Animation:Cancel()
					    end
					    Environment.FOVCircle.Color = GetColor(Environment.FOVSettings.Color)
					end
				end
			end)
		end
	end)
end

--// Functions
Environment.Functions = {}

function Environment.Functions:Exit()
	SaveSettings()
	for _, v in next, ServiceConnections do
		v:Disconnect()
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
	Load()
end

function Environment.Functions:ResetSettings()
	Environment.Settings = {
		SendNotifications = true,
		SaveSettings = true, -- Re-execute upon changing
		ReloadOnTeleport = true,
		Enabled = true,
		TeamCheck = false,
		AliveCheck = true,
		WallCheck = false,
		Sensitivity = 0, -- Animation length (in seconds) before fully locking onto target
		ThirdPerson = false,
		ThirdPersonSensitivity = 3,
		TriggerKey = "MouseButton2",
		Toggle = false,
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
	
	Environment.PredictionSettings = {
		Enabled = false,
		PredictionMode = "Default", -- "Default", "Ping", "Custom"
		DefaultPrediction = 0.165,
		PingBasedMultiplier = 0.001, -- Multiplier for ping-based prediction
		CustomPrediction = 0.2
	}

	Environment.TeamConfig = {
		CopConfig = {
			TargetTeams = {
				"Booking",
				"Escapee",
				"Maxium Security",
				"Medium Secruity",
				"Minimum Secruity"
			}
		},
		PrisonerConfig = {
			TargetTeams = {
				"Civilan",
				"Department of Corrections",
				"Sheriff's Office",
				"State Police",
				"VCSO-SWAT",
				"Weapons",
				"Tester"
			}
		}
	}
end

--// Team Configuration Helper Functions (for easy reference in other scripts)
function Environment.Functions:SetPlayerRole(role)
	if role == "Cop" or role == "Prisoner" then
		Environment.Settings.PlayerRole = role
		Environment.Settings.UseTeamConfig = true
		SaveSettings()
		return true
	else
		return false
	end
end

function Environment.Functions:GetTargetTeams()
	if Environment.Settings.PlayerRole == "Cop" then
		return Environment.TeamConfig.CopConfig.TargetTeams
	elseif Environment.Settings.PlayerRole == "Prisoner" then
		return Environment.TeamConfig.PrisonerConfig.TargetTeams
	else
		return {}
	end
end

function Environment.Functions:AddTargetTeam(teamName)
	local targetTeams = {}
	if Environment.Settings.PlayerRole == "Cop" then
		targetTeams = Environment.TeamConfig.CopConfig.TargetTeams
	elseif Environment.Settings.PlayerRole == "Prisoner" then
		targetTeams = Environment.TeamConfig.PrisonerConfig.TargetTeams
	else
		return false
	end
	
	-- Check if team already exists
	for _, team in pairs(targetTeams) do
		if team == teamName then
			return false -- Team already exists
		end
	end
	
	table.insert(targetTeams, teamName)
	SaveSettings()
	return true
end

function Environment.Functions:RemoveTargetTeam(teamName)
	local targetTeams = {}
	if Environment.Settings.PlayerRole == "Cop" then
		targetTeams = Environment.TeamConfig.CopConfig.TargetTeams
	elseif Environment.Settings.PlayerRole == "Prisoner" then
		targetTeams = Environment.TeamConfig.PrisonerConfig.TargetTeams
	else
		return false
	end
	
	for i, team in pairs(targetTeams) do
		if team == teamName then
			table.remove(targetTeams, i)
			SaveSettings()
			return true
		end
	end
	
	return false -- Team not found
end

function Environment.Functions:ToggleTeamConfig(enabled)
	Environment.Settings.UseTeamConfig = enabled
	SaveSettings()
end

--// Support Check
if not Drawing or not getgenv then
	print("Error")
end

--// Reload On Teleport
if Environment.Settings.ReloadOnTeleport then
	if queueonteleport then
		queueonteleport(game:HttpGet("https://raw.githubusercontent.com/Exunys/Aimbot-V2/main/Resources/Scripts/Main.lua"))
	else
		print("ZING")
	end
end

--// Load
Load();
