-- Cleanup
pcall(function()
    getgenv().Aimbot.Functions:Exit()
end)

-- Environment
getgenv().Aimbot = {}
local Environment = getgenv().Aimbot

-- Services
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local StarterGui = game:GetService("StarterGui")
local Players = game:GetService("Players")
local Camera = workspace.CurrentCamera
local Stats = game:GetService("Stats")

-- Variables
local LocalPlayer = Players.LocalPlayer
local Typing, Running, ServiceConnections = false, false, {}
local LastFrameTime, LastTargetUpdate, LastPredictionUpdate = 0, 0, 0
local ValidTargets, CachedPrediction = {}, 0
local mousemoverel = mousemoverel or (Input and Input.MouseMove)

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

-- Initialize
Environment.FOVCircle = Drawing.new("Circle")
Environment.Locked = nil

-- Utils
local function Encode(Table)
    return Table and type(Table) == "table" and HttpService:JSONEncode(Table)
end

local function Decode(String)
    return String and type(String) == "string" and HttpService:JSONDecode(String)
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

-- Smoothing
local function GetSmoothingFactor(sensitivity, deltaTime)
    if sensitivity == 0 then return 1 end
    
    local baseFactor = math.clamp(sensitivity, 1, 10)
    
    if Environment.Settings.SmoothingType == "Exponential" then
        return 1 - math.pow(math.pow(0.1, 1 / baseFactor), deltaTime * 60)
    elseif Environment.Settings.SmoothingType == "Bezier" then
        local t = math.clamp(1 / baseFactor, 0.1, 1)
        t = t * t * (3 - 2 * t)
        return t * deltaTime * 60
    else
        return math.clamp((1 / baseFactor) * deltaTime * 60, 0.01, 1)
    end
end

-- File System
local function SaveSettings()
    if not Environment.Settings.SaveSettings then return end
    
    if isfile("Exunys Developer/Aimbot/Configuration.json") then
        writefile("Exunys Developer/Aimbot/Configuration.json", Encode(Environment.Settings))
    end
    if isfile("Exunys Developer/Aimbot/Drawing.json") then
        writefile("Exunys Developer/Aimbot/Drawing.json", Encode(Environment.FOVSettings))
    end
    if isfile("Exunys Developer/Aimbot/Prediction.json") then
        writefile("Exunys Developer/Aimbot/Prediction.json", Encode(Environment.PredictionSettings))
    end
end

-- Prediction
local function GetPredictionValue()
    if not Environment.PredictionSettings.Enabled then return 0 end
    
    if tick() - LastPredictionUpdate >= 0.2 then
        LastPredictionUpdate = tick()
        
        if Environment.PredictionSettings.PredictionMode == "Default" then
            CachedPrediction = Environment.PredictionSettings.DefaultPrediction
        elseif Environment.PredictionSettings.PredictionMode == "ping" then
            CachedPrediction = (Stats.Network.ServerStatsItem["Data Ping"]:GetValue() / 1000) * Environment.PredictionSettings.PingBasedMultiplier
        elseif Environment.PredictionSettings.PredictionMode == "Custom" then
            CachedPrediction = Environment.PredictionSettings.CustomPrediction
        end
    end
    
    return CachedPrediction
end

-- Team Validation
local function IsPlayerInTeamCategory(player, category)
    if not player or not player.Team then return false end
    
    if category == "Prisoner" then
        return player.Team.Name == "Booking" or player.Team.Name == "Escapee" or 
               player.Team.Name == "Maximum Security" or player.Team.Name == "Medium Security" or 
               player.Team.Name == "Minimum Security"
    elseif category == "Cop" then
        return player.Team.Name == "Civilian" or player.Team.Name == "Department of Corrections" or 
               player.Team.Name == "Sheriff's Office" or player.Team.Name == "State Police" or 
               player.Team.Name == "VCSO-SWAT" or player.Team.Name == "WeaponsTester"
    end
    
    return false
end

-- Wall Check
local function IsTargetVisible(targetPart)
    if not Environment.Settings.WallCheck then return true end
    
    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Blacklist
    rayParams.FilterDescendantsInstances = {LocalPlayer.Character, Camera}
    
    local result = workspace:Raycast(Camera.CFrame.Position, 
        (targetPart.Position - Camera.CFrame.Position).Unit * (targetPart.Position - Camera.CFrame.Position).Magnitude, 
        rayParams)
    
    return not result or (result.Instance and result.Instance:IsDescendantOf(targetPart.Parent))
end

-- Target Validation
local function IsValidTarget(player)
    if not player or not player.Parent or player == LocalPlayer then return false end
    
    local character = player.Character
    if not character or not character.Parent then return false end
    
    local targetPart = character:FindFirstChild(Environment.Settings.LockPart)
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    
    if not targetPart or not humanoid then return false end
    
    if Environment.Settings.CopMode and not IsPlayerInTeamCategory(player, "Prisoner") then return false end
    if Environment.Settings.PrisonerMode and not IsPlayerInTeamCategory(player, "Cop") then return false end
    if Environment.Settings.TeamCheck and player.Team == LocalPlayer.Team then return false end
    if Environment.Settings.AliveCheck and humanoid.Health <= 0 then return false end
    if not IsTargetVisible(targetPart) then return false end
    
    return true, targetPart
end

-- Target Finding
local function UpdateValidTargets()
    if tick() - LastTargetUpdate < 0.15 then return end
    LastTargetUpdate = tick()
    
    ValidTargets = {}
    
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Parent then
            local isValid, targetPart = IsValidTarget(player)
            if isValid then
                ValidTargets[player] = {
                    part = targetPart,
                    character = player.Character,
                    distance = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") and 
                              (LocalPlayer.Character.HumanoidRootPart.Position - targetPart.Position).Magnitude or math.huge
                }
            end
        end
    end
end

local function GetClosestTarget()
    if not LocalPlayer.Character or not LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
        return nil
    end
    
    UpdateValidTargets()
    
    if Environment.Settings.AutoLock then
        local closestPlayer, shortestDistance = nil, math.huge
        
        for player, data in pairs(ValidTargets) do
            if data.distance < shortestDistance then
                shortestDistance = data.distance
                closestPlayer = player
            end
        end
        
        return closestPlayer
    else
        local mousePos = UserInputService:GetMouseLocation()
        local closestPlayer, shortestDistance = nil, Environment.FOVSettings.Amount
        
        for player, data in pairs(ValidTargets) do
            local vector, onScreen = Camera:WorldToViewportPoint(data.part.Position)
            if onScreen then
                local screenDistance = (Vector2.new(mousePos.X, mousePos.Y) - Vector2.new(vector.X, vector.Y)).Magnitude
                if screenDistance < shortestDistance then
                    shortestDistance = screenDistance
                    closestPlayer = player
                end
            end
        end
        
        return closestPlayer
    end
end

-- TriggerBot
local function SetupTriggerBot()
    if Environment.TriggerBot.Connection then
        Environment.TriggerBot.Connection:Disconnect()
        Environment.TriggerBot.Connection = nil
    end
    
    if not Environment.TriggerBot.Enabled then return end
    
    Environment.TriggerBot.Connection = RunService.Heartbeat:Connect(function()
        if Environment.TriggerBot.Debounce then return end
        
        local Target = LocalPlayer:GetMouse().Target
        if not Target or not Target.Parent then return end
        
        local Player = Players:GetPlayerFromCharacter(Target.Parent)
        if not Player or not IsValidTarget(Player) then return end
        
        if Player.Character:FindFirstChildOfClass("ForceField") then return end
        
        Environment.TriggerBot.Debounce = true
        
        task.spawn(function()
            mouse1press()
            
            repeat
                RunService.Heartbeat:Wait()
                local CurrentTarget = LocalPlayer:GetMouse().Target
                local CurrentPlayer = CurrentTarget and CurrentTarget.Parent and Players:GetPlayerFromCharacter(CurrentTarget.Parent)
            until not CurrentPlayer or CurrentPlayer ~= Player or not Environment.TriggerBot.Enabled
            
            mouse1release()
            Environment.TriggerBot.Debounce = false
        end)
    end)
end

-- Input
ServiceConnections.TypingStartedConnection = UserInputService.TextBoxFocused:Connect(function()
    Typing = true
end)

ServiceConnections.TypingEndedConnection = UserInputService.TextBoxFocusReleased:Connect(function()
    Typing = false
end)

-- File Setup
if Environment.Settings.SaveSettings then
    if not isfolder("Exunys Developer") then
        makefolder("Exunys Developer")
    end
    if not isfolder("Exunys Developer/Aimbot") then
        makefolder("Exunys Developer/Aimbot")
    end
    
    if not isfile("Exunys Developer/Aimbot/Configuration.json") then
        writefile("Exunys Developer/Aimbot/Configuration.json", Encode(Environment.Settings))
    else
        Environment.Settings = Decode(readfile("Exunys Developer/Aimbot/Configuration.json"))
    end
    
    if not isfile("Exunys Developer/Aimbot/Drawing.json") then
        writefile("Exunys Developer/Aimbot/Drawing.json", Encode(Environment.FOVSettings))
    else
        Environment.FOVSettings = Decode(readfile("Exunys Developer/Aimbot/Drawing.json"))
    end
    
    if not isfile("Exunys Developer/Aimbot/Prediction.json") then
        writefile("Exunys Developer/Aimbot/Prediction.json", Encode(Environment.PredictionSettings))
    else
        Environment.PredictionSettings = Decode(readfile("Exunys Developer/Aimbot/Prediction.json"))
    end
    
    task.spawn(function()
        while task.wait(10) do
            if not Environment.Settings or not Environment.Settings.SaveSettings then break end
            SaveSettings()
        end
    end)
end

-- Main Loop
local function Load()
    ServiceConnections.RenderSteppedConnection = RunService.RenderStepped:Connect(function()
        local deltaTime = tick() - LastFrameTime
        LastFrameTime = tick()
        
        -- FOV Circle
        if Environment.FOVSettings.Enabled and Environment.Settings.Enabled then
            Environment.FOVCircle.Radius = Environment.FOVSettings.Amount
            Environment.FOVCircle.Thickness = Environment.FOVSettings.Thickness
            Environment.FOVCircle.Filled = Environment.FOVSettings.Filled
            Environment.FOVCircle.NumSides = Environment.FOVSettings.Sides
            Environment.FOVCircle.Transparency = Environment.FOVSettings.Transparency
            Environment.FOVCircle.Visible = Environment.FOVSettings.Visible
            Environment.FOVCircle.Position = UserInputService:GetMouseLocation()
        else
            Environment.FOVCircle.Visible = false
        end

        -- Targeting
        if Environment.Settings.Enabled then
            if Environment.Settings.AutoLock or Running then
                Environment.Locked = GetClosestTarget()
            else
                Environment.Locked = nil
            end
            
            -- Aiming
            if Environment.Locked and ValidTargets[Environment.Locked] then
                local targetData = ValidTargets[Environment.Locked]
                local predictedPosition = targetData.part.Position + (targetData.part.Velocity * GetPredictionValue())
                
                if Environment.Settings.ThirdPerson and mousemoverel then
                    local Vector = Camera:WorldToViewportPoint(predictedPosition)
                    local mousePos = UserInputService:GetMouseLocation()
                    
                    local deltaX = (Vector.X - mousePos.X) * GetSmoothingFactor(Environment.Settings.ThirdPersonSensitivity, deltaTime)
                    local deltaY = (Vector.Y - mousePos.Y) * GetSmoothingFactor(Environment.Settings.ThirdPersonSensitivity, deltaTime)
                    
                    mousemoverel(math.clamp(deltaX, -150, 150), math.clamp(deltaY, -150, 150))
                else
                    local lerpFactor = GetSmoothingFactor(Environment.Settings.Sensitivity, deltaTime)
                    Camera.CFrame = Environment.Settings.Sensitivity == 0 and 
                        CFrame.new(Camera.CFrame.Position, predictedPosition) or
                        Camera.CFrame:Lerp(CFrame.new(Camera.CFrame.Position, predictedPosition), lerpFactor)
                end
            
                Environment.FOVCircle.Color = GetColor(Environment.FOVSettings.LockedColor)
            else
                Environment.FOVCircle.Color = GetColor(Environment.FOVSettings.Color)
            end
        else
            Environment.FOVCircle.Color = GetColor(Environment.FOVSettings.Color)
        end
    end)

    -- Input Handling
    local function HandleTriggerInput(active)
        if Environment.Settings.AutoLock then return end
        
        if Environment.Settings.Toggle then
            if active then
                Running = not Running
                if not Running then
                    Environment.Locked = nil
                    Environment.FOVCircle.Color = GetColor(Environment.FOVSettings.Color)
                end
            end
        else
            Running = active
            if not Running then
                Environment.Locked = nil
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
end

-- API
Environment.Functions = {}

function Environment.Functions:Exit()
    SaveSettings()
    for _, connection in pairs(ServiceConnections) do
        connection:Disconnect()
    end
    
    if Environment.TriggerBot.Connection then
        Environment.TriggerBot.Connection:Disconnect()
    end
    
    if Environment.FOVCircle.Remove then
        Environment.FOVCircle:Remove()
    end
    
    getgenv().Aimbot = nil
end

function Environment.Functions:Restart()
    self:Exit()
    Load()
end

function Environment.Functions:ResetSettings()
    Environment.Settings = {
        SendNotifications = true,
        SaveSettings = true, 
        ReloadOnTeleport = true,
        Enabled = false,
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
end

function Environment.Functions:ToggleTriggerBot(state)
    Environment.TriggerBot.Enabled = state == nil and not Environment.TriggerBot.Enabled or state
    SetupTriggerBot()
    return Environment.TriggerBot.Enabled
end

function Environment.Functions:ToggleAutoLock(state)
    Environment.Settings.AutoLock = state == nil and not Environment.Settings.AutoLock or state
    
    if not Environment.Settings.AutoLock then
        Running = false
        Environment.Locked = nil
        Environment.FOVCircle.Color = GetColor(Environment.FOVSettings.Color)
    end
    
    return Environment.Settings.AutoLock
end

-- Support Check
if not Drawing or not getgenv then
    print("Error: Missing required functions. Your exploit may not be supported.")
    return
end

-- Teleport Handler
if Environment.Settings.ReloadOnTeleport and (queue_on_teleport or syn.queue_on_teleport) then
    (queue_on_teleport or syn.queue_on_teleport)(game:HttpGet("https://raw.githubusercontent.com/Exunys/Aimbot-V2/main/Resources/Scripts/Main.lua"))
end

Load()
