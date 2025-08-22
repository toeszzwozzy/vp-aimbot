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
    ReloadOnTeleport = false,
    Enabled = false,
    TeamCheck = false,
    AliveCheck = false,
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

local function GetColor(Color)
    local R = tonumber(string.match(Color, "([%d]+)[%s]*,[%s]*[%d]+[%s]*,[%s]*[%d]+"))
    local G = tonumber(string.match(Color, "[%d]+[%s]*,[%s]*([%d]+)[%s]*,[%s]*[%d]+"))
    local B = tonumber(string.match(Color, "[%d]+[%s]*,[%s]*[%d]+[%s]*,[%s]*([%d]+)"))
    return Color3.fromRGB(R, G, B)
end

-- Smoothing
local function GetSmoothingFactor(sensitivity, deltaTime)
    if sensitivity == 0 then return 1 end -- 0 = instant/no smoothing
    
    -- Convert sensitivity (0-1) to smoothing factor
    -- Lower sensitivity = stronger aim = higher smoothing factor
    -- Higher sensitivity = smoother aim = lower smoothing factor
    local smoothingStrength = math.clamp(sensitivity * 10, 0.1, 10)
    
    if Environment.Settings.SmoothingType == "Exponential" then
        local factor = 1 - math.exp(-smoothingStrength * deltaTime * 60)
        return math.clamp(factor, 0.01, 1)
    elseif Environment.Settings.SmoothingType == "Bezier" then
        local t = math.clamp(smoothingStrength * deltaTime * 60, 0, 1)
        t = t * t * (3 - 2 * t)
        return math.clamp(t, 0.01, 1)
    else
        -- Linear smoothing
        return math.clamp(smoothingStrength * deltaTime * 60, 0.01, 1)
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

-- Enhanced target existence validation
local function IsTargetStillValid(player)
    if not player or not player.Parent then return false end
    if not ValidTargets[player] then return false end
    
    local character = player.Character
    if not character or not character.Parent then return false end
    
    local targetPart = ValidTargets[player].part
    if not targetPart or not targetPart.Parent then return false end
    return IsValidTarget(player)
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


-- Main Loop
local function Load()
    ServiceConnections.RenderSteppedConnection = RunService.RenderStepped:Connect(function()
        local deltaTime = tick() - LastFrameTime
        LastFrameTime = tick()

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

        if Environment.Settings.Enabled then
            if Environment.Locked and not IsTargetStillValid(Environment.Locked) then
                Environment.Locked = nil
            end
            
            if Environment.Settings.AutoLock or Running then
                if not Environment.Locked then
                    Environment.Locked = GetClosestTarget()
                end
            else
                Environment.Locked = nil
            end
            
            if Environment.Locked and ValidTargets[Environment.Locked] then
                local targetData = ValidTargets[Environment.Locked]
                local targetPart = targetData.part
 
                if not targetPart or not targetPart.Parent then
                    Environment.Locked = nil
                    Environment.FOVCircle.Color = GetColor(Environment.FOVSettings.Color)
                else
                    local predictedPosition = targetPart.Position + (targetPart.Velocity * GetPredictionValue())
                    
                    if Environment.Settings.ThirdPerson and mousemoverel then
                        local Vector, onScreen = Camera:WorldToViewportPoint(predictedPosition)
                        
                        if onScreen then
                            local mousePos = UserInputService:GetMouseLocation()
                            local screenSize = Camera.ViewportSize
                            
                            local deltaX = (Vector.X - mousePos.X) * GetSmoothingFactor(Environment.Settings.ThirdPersonSensitivity, deltaTime)
                            local deltaY = (Vector.Y - mousePos.Y) * GetSmoothingFactor(Environment.Settings.ThirdPersonSensitivity, deltaTime)
                            
                            local newMouseX = mousePos.X + deltaX
                            local newMouseY = mousePos.Y + deltaY
                            
                            local padding = 10
                            if newMouseX < padding or newMouseX > screenSize.X - padding then
                                deltaX = 0
                            end
                            if newMouseY < padding or newMouseY > screenSize.Y - padding then
                                deltaY = 0
                            end
                            
                            deltaX = math.clamp(deltaX, -100, 100)
                            deltaY = math.clamp(deltaY, -100, 100)
                            
                            if math.abs(deltaX) > 1 or math.abs(deltaY) > 1 then
                                mousemoverel(deltaX, deltaY)
                            end
                        end
                    else
                        local currentCFrame = Camera.CFrame
                        local targetDirection = (predictedPosition - currentCFrame.Position).Unit
                        local currentDirection = currentCFrame.LookVector

                        local angle = math.acos(math.clamp(currentDirection:Dot(targetDirection), -1, 1))
                        
                        if angle > math.rad(90) then
                            local rightVector = currentCFrame.RightVector
                            local targetCross = currentDirection:Cross(targetDirection)
                            local rightDot = rightVector:Dot(targetCross)
                            
                            local turnMultiplier = rightDot > 0 and 1 or -1
                            local maxTurnSpeed = math.rad(120)
                            local turnSpeed = math.min(angle, maxTurnSpeed * deltaTime) * turnMultiplier
                            
                            local rotationAxis = Vector3.new(0, 1, 0) 
                            local intermediateDirection = currentDirection * math.cos(turnSpeed) + rightVector * math.sin(turnSpeed)
                            local intermediateTarget = currentCFrame.Position + intermediateDirection * 100
                            
                            local newCFrame = CFrame.new(currentCFrame.Position, intermediateTarget)
                            Camera.CFrame = newCFrame
                        else
                            local lerpFactor = GetSmoothingFactor(Environment.Settings.Sensitivity, deltaTime)
                            
                            if angle < math.rad(30) then
                                lerpFactor = math.min(lerpFactor * 1.5, 1)
                            end
                            
                            local targetCFrame = CFrame.new(currentCFrame.Position, predictedPosition)
                            Camera.CFrame = Environment.Settings.Sensitivity == 0 and targetCFrame or
                                currentCFrame:Lerp(targetCFrame, lerpFactor)
                        end
                    end
                
                    Environment.FOVCircle.Color = GetColor(Environment.FOVSettings.LockedColor)
                end
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
        SendNotifications = false,
        ReloadOnTeleport = false,
        Enabled = false,
        TeamCheck = false,
        AliveCheck = false,
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

Load()
