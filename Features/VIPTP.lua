-- ==================================================
-- YOKUDO HUB | FEATURE | VIPTP (AFK Farm Only)
-- ដាច់ដោយឡែកសម្រាប់ AFK Farm
-- Speed កំណត់ក្នុង file ខ្លួនឯង
-- Fly Speed: 1000 | Return Speed: 800 | Fly Offset: 15
-- Lock Above: 2 | Distance Threshold: 5
-- ✅ Thread ដាច់ដោយឡែក + Flag ការពារ
-- ✅ Register ជាមួយ CharacterSystem
-- ✅ Auto Callback ទៅ FarmingManager ពេល AutoStop
-- ==================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Player = Players.LocalPlayer
local Container = workspace:WaitForChild("AreaEggSlotsClient")

-- ==================================================
-- REMOTES
-- ==================================================
local CollectEvent = nil
local ForestStrike = nil

pcall(function()
    CollectEvent = ReplicatedStorage.Packages.Networking["RF/EggWorld/AskFieldEggCarry"]
end)

pcall(function()
    ForestStrike = ReplicatedStorage.Packages.Networking["RE/GuardPatrol/ForestStrike"]
end)

if not CollectEvent then
    warn("[VIPTP] CollectEvent not found")
    return
end

print("[VIPTP] CollectEvent OK")

-- ==================================================
-- SETTINGS (កំណត់ក្នុង file ខ្លួនឯង)
-- ==================================================
local TARGET_UID = nil
local SAFE_ZONE = Vector3.new(533, 70, -366)

local FLY_SPEED = 1000
local RETURN_SPEED = 800
local FLY_OFFSET = 15
local LOCK_ABOVE = 2

local SHOT_DISTANCE = 15
local ARRIVE_DISTANCE = 2
local SAFE_LOCK_DISTANCE = 3
local TIMEOUT_SECONDS = 30

local COLLECT_INTERVAL = 0.2
local SEARCH_PREFIX = "FirstAreaEgg"
local DISTANCE_THRESHOLD = 5
local Y_CHANGE_THRESHOLD = 1

local LOCK_POSITION = Vector3.new(
    607.6259155273438,
    70.57420349121094,
    -326.8830261230469
)

-- ==================================================
-- RAGDOLL BYPASS
-- ==================================================
local RagdollEnabled = false
local RagdollConnection = nil
local ForceUpConnection = nil

-- ==================================================
-- STATE
-- ==================================================
local Running = false
local CurrentStep = "idle"

local FlyConnection = nil
local BodyVelocity = nil
local BodyGyro = nil
local ActiveHeartbeat = nil
local LockConnection = nil

local FirstEggList = {}
local FirstEggUid = nil
local FirstEggSlotKey = nil

local CollectAttempts = 0
local CollectTime = 0

local FlyTargetStarted = false
local CollectDone = false
local RemotesFired = false

-- ✅ Flag ការពារកុំឲ្យជាន់គ្នា
local IsFlyToSafeRunning = false
local IsFlyBackRunning = false
local IsCollectTargetRunning = false

local SavedWalkSpeed = nil
local SavedJumpPower = nil
local SavedJumpHeight = nil
local SavedUseJumpPower = nil

local SavedTargetY = nil

-- ==================================================
-- GET HUMANOID
-- ==================================================
local function GetHumanoid()
    local Char = Player.Character
    if not Char then return nil, nil end
    local Hum = Char:FindFirstChildOfClass("Humanoid")
    local Root = Char:FindFirstChild("HumanoidRootPart")
    return Hum, Root
end

-- ==================================================
-- RAGDOLL BYPASS
-- ==================================================
local function ForceUp()
    local Hum, Root = GetHumanoid()
    if not Hum or not Root then return end

    pcall(function()
        if Hum:GetState() == Enum.HumanoidStateType.Physics then
            Hum:ChangeState(Enum.HumanoidStateType.GettingUp)
        end

        Hum:SetStateEnabled(Enum.HumanoidStateType.Physics, false)
        Hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
        Hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
        Hum:SetStateEnabled(Enum.HumanoidStateType.Dead, false)

        Hum.PlatformStand = false
        Hum.Sit = false

        Root.AssemblyLinearVelocity = Vector3.zero
        Root.AssemblyAngularVelocity = Vector3.zero
        Root.CanCollide = true

        Hum.BreakJointsOnDeath = false
        Hum.RequiresNeck = false
    end)
end

local function CleanupRagdollConstraints()
    local Char = Player.Character
    if not Char then return end

    pcall(function()
        for _, descendant in ipairs(Char:GetDescendants()) do
            if descendant.Name:find("RagdollConstraint") then
                descendant:Destroy()
            end
            if descendant.Name:find("RagdollAttachment") then
                descendant:Destroy()
            end
        end

        for _, descendant in ipairs(Char:GetDescendants()) do
            if descendant:IsA("Motor6D") then
                descendant.Enabled = true
            end
        end
    end)
end

local function EnableRagdollBypass()
    if RagdollEnabled then return end
    RagdollEnabled = true

    RagdollConnection = RunService.Heartbeat:Connect(function()
        if not RagdollEnabled then return end
        ForceUp()
    end)

    ForceUpConnection = task.spawn(function()
        while RagdollEnabled do
            task.wait(0.1)
            ForceUp()
            CleanupRagdollConstraints()
        end
    end)

    print("[VIPTP] Ragdoll Bypass: ON")
end

local function DisableRagdollBypass()
    if not RagdollEnabled then return end
    RagdollEnabled = false

    if RagdollConnection then
        RagdollConnection:Disconnect()
        RagdollConnection = nil
    end

    print("[VIPTP] Ragdoll Bypass: OFF")
end

-- ==================================================
-- SAVE / RESTORE STATS
-- ==================================================
local function SaveStats()
    local Hum = GetHumanoid()
    if not Hum then return end

    if SavedWalkSpeed == nil then SavedWalkSpeed = Hum.WalkSpeed end
    if SavedJumpPower == nil then SavedJumpPower = Hum.JumpPower end
    if SavedJumpHeight == nil then SavedJumpHeight = Hum.JumpHeight end
    if SavedUseJumpPower == nil then SavedUseJumpPower = Hum.UseJumpPower end
end

local function RestoreStats()
    local Hum = GetHumanoid()
    if not Hum then return end

    if SavedWalkSpeed ~= nil then pcall(function() Hum.WalkSpeed = SavedWalkSpeed end) end
    if SavedJumpPower ~= nil then pcall(function() Hum.JumpPower = SavedJumpPower end) end
    if SavedJumpHeight ~= nil then pcall(function() Hum.JumpHeight = SavedJumpHeight end) end
    if SavedUseJumpPower ~= nil then pcall(function() Hum.UseJumpPower = SavedUseJumpPower end) end
end

-- ==================================================
-- CLEANUP
-- ==================================================
local function CleanupMovers()
    if FlyConnection then
        FlyConnection:Disconnect()
        FlyConnection = nil
    end
    if LockConnection then
        LockConnection:Disconnect()
        LockConnection = nil
    end
    if BodyVelocity then
        pcall(function()
            BodyVelocity.Velocity = Vector3.zero
            BodyVelocity.MaxForce = Vector3.zero
        end)
        BodyVelocity:Destroy()
        BodyVelocity = nil
    end
    if BodyGyro then
        pcall(function() BodyGyro.MaxTorque = Vector3.zero end)
        BodyGyro:Destroy()
        BodyGyro = nil
    end

    local Hum, Root = GetHumanoid()
    if Root then
        for _, Child in ipairs(Root:GetChildren()) do
            if Child.Name == "YokudoBV" or Child.Name == "YokudoBG" then
                pcall(function() Child:Destroy() end)
            end
        end
    end

    if Hum then
        pcall(function()
            Hum.PlatformStand = false
            Hum.Sit = false
        end)
    end

    if Root then
        pcall(function()
            Root.AssemblyLinearVelocity = Vector3.zero
            Root.AssemblyAngularVelocity = Vector3.zero
        end)
    end
end

-- ==================================================
-- LOCK AT TARGET (Y + LOCK_ABOVE)
-- ==================================================
local function StartLock(TargetPosition)
    local TargetLockedCFrame = CFrame.new(TargetPosition + Vector3.new(0, LOCK_ABOVE, 0))

    if LockConnection then
        LockConnection:Disconnect()
    end

    LockConnection = RunService.Heartbeat:Connect(function()
        if not Running then
            if LockConnection then LockConnection:Disconnect() LockConnection = nil end
            return
        end

        local Hum, Root = GetHumanoid()
        if not Root then return end

        Root.CFrame = TargetLockedCFrame
        Root.AssemblyLinearVelocity = Vector3.zero
        Root.AssemblyAngularVelocity = Vector3.zero
    end)
end

-- ==================================================
-- GET POSITION
-- ==================================================
local function GetPosition(Object)
    if not Object then return nil end
    if Object:IsA("Model") then
        if Object.PrimaryPart then return Object.PrimaryPart.Position end
        local Part = Object:FindFirstChildWhichIsA("BasePart")
        if Part then return Part.Position end
        for _, Desc in ipairs(Object:GetDescendants()) do
            if Desc:IsA("BasePart") then return Desc.Position end
        end
    elseif Object:IsA("BasePart") then
        return Object.Position
    end
    return nil
end

-- ==================================================
-- GET TARGET EGG OBJECT
-- ==================================================
local function GetTargetEggObject()
    if not TARGET_UID then return nil end

    local EggInContainer = Container and Container:FindFirstChild(TARGET_UID)
    if EggInContainer then return EggInContainer end

    local EggInWS = workspace:FindFirstChild(TARGET_UID)
    if EggInWS then return EggInWS end

    return nil
end

-- ==================================================
-- SEARCH FIRST EGGS
-- ==================================================
local function SearchFirstEggs()
    FirstEggList = {}
    if not Container then return end

    for _, Slot in ipairs(Container:GetChildren()) do
        if string.find(Slot.Name, SEARCH_PREFIX) then
            local SlotNum = string.match(Slot.Name, "Slot_(%d+)")
            if SlotNum then
                table.insert(FirstEggList, {
                    Slot = Slot,
                    Uid = Slot.Name,
                    SlotKey = "Forest:Slot_" .. SlotNum,
                    SlotNum = tonumber(SlotNum)
                })
            end
        end
    end
end

local function FindClosestEgg()
    local Hum, Root = GetHumanoid()
    if not Root then return nil end

    local Closest = nil
    local ClosestDistance = 9999

    for _, Egg in ipairs(FirstEggList) do
        local Pos = GetPosition(Egg.Slot)
        if Pos then
            local Dist = (Pos - Root.Position).Magnitude
            if Dist < ClosestDistance then
                ClosestDistance = Dist
                Closest = Egg
            end
        end
    end

    if Closest then
        FirstEggUid = Closest.Uid
        FirstEggSlotKey = Closest.SlotKey
    end

    return Closest
end

-- ==================================================
-- FLY TP
-- ==================================================
local function FlyTP(Destination, Speed, UseShotTP, IsSafeZone, Callback)
    CleanupMovers()

    local Hum, Root = GetHumanoid()
    if not Hum or not Root then return end
    if Hum.Health <= 0 then return end

    local FlyPos = Vector3.new(Destination.X, Destination.Y + FLY_OFFSET, Destination.Z)
    local LockCFrame = CFrame.new(Destination + Vector3.new(0, LOCK_ABOVE, 0))

    Hum.PlatformStand = true

    BodyVelocity = Instance.new("BodyVelocity")
    BodyVelocity.Name = "YokudoBV"
    BodyVelocity.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
    BodyVelocity.P = 1250
    BodyVelocity.Velocity = Vector3.zero
    BodyVelocity.Parent = Root

    BodyGyro = Instance.new("BodyGyro")
    BodyGyro.Name = "YokudoBG"
    BodyGyro.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
    BodyGyro.P = 3000
    BodyGyro.D = 500
    BodyGyro.CFrame = Root.CFrame
    BodyGyro.Parent = Root

    local StartTime = tick()
    local ShotDone = false

    FlyConnection = RunService.Heartbeat:Connect(function()
        if not Running then
            CleanupMovers()
            return
        end

        local Hum2, Root2 = GetHumanoid()
        if not Hum2 or not Root2 then
            CleanupMovers()
            return
        end
        if Hum2.Health <= 0 then return end

        if not BodyVelocity or not BodyGyro then
            CleanupMovers()
            return
        end

        local CurrentPos = Root2.Position
        local Direction = (FlyPos - CurrentPos)
        local HorizDist = Vector3.new(Direction.X, 0, Direction.Z).Magnitude
        local VertDist = math.abs(Direction.Y)
        local TotalDist = Direction.Magnitude

        if IsSafeZone then
            if HorizDist <= SAFE_LOCK_DISTANCE then
                CleanupMovers()
                Root2.CFrame = LockCFrame
                Root2.AssemblyLinearVelocity = Vector3.zero
                Root2.AssemblyAngularVelocity = Vector3.zero
                StartLock(Destination)
                if Callback then Callback() end
                return
            end
        end

        if not IsSafeZone and UseShotTP and not ShotDone and HorizDist <= SHOT_DISTANCE then
            ShotDone = true
            CleanupMovers()
            Root2.CFrame = LockCFrame
            Root2.AssemblyLinearVelocity = Vector3.zero
            Root2.AssemblyAngularVelocity = Vector3.zero
            StartLock(Destination)
            if Callback then Callback() end
            return
        end

        if HorizDist <= ARRIVE_DISTANCE and VertDist <= 2 then
            CleanupMovers()
            Root2.CFrame = LockCFrame
            Root2.AssemblyLinearVelocity = Vector3.zero
            Root2.AssemblyAngularVelocity = Vector3.zero
            StartLock(Destination)
            if Callback then Callback() end
            return
        end

        if tick() - StartTime > TIMEOUT_SECONDS then
            CleanupMovers()
            if Callback then Callback() end
            return
        end

        if TotalDist > 1 then
            BodyVelocity.Velocity = Direction.Unit * Speed
        else
            BodyVelocity.Velocity = Vector3.zero
        end

        BodyGyro.CFrame = CFrame.new(CurrentPos, CurrentPos + Vector3.new(Direction.X, 0, Direction.Z))
    end)
end

-- ==================================================
-- INSTANT FLY TP
-- ==================================================
local function InstantFlyTP(Destination, Callback)
    CleanupMovers()

    local Hum, Root = GetHumanoid()
    if not Hum or not Root then return end
    if Hum.Health <= 0 then return end

    local LockCFrame = CFrame.new(Destination + Vector3.new(0, LOCK_ABOVE, 0))

    Root.CFrame = LockCFrame
    Root.AssemblyLinearVelocity = Vector3.zero
    Root.AssemblyAngularVelocity = Vector3.zero

    StartLock(Destination)

    if Callback then Callback() end
end

-- ==================================================
-- REMOTE COLLECT
-- ==================================================
local function RemoteCollectFirst()
    if not CollectEvent or not FirstEggSlotKey or not FirstEggUid then return false end
    local success = pcall(function()
        return CollectEvent:InvokeServer({
            FirstAreaSlotKey = FirstEggSlotKey,
            Uid = FirstEggUid
        })
    end)
    return success
end

local function RemoteCollectTarget()
    if not CollectEvent or not TARGET_UID then return false end
    local success = pcall(function()
        return CollectEvent:InvokeServer({
            Uid = TARGET_UID
        })
    end)
    return success
end

-- ==================================================
-- FIRE FOREST STRIKE
-- ==================================================
local function FireForestStrike()
    if RemotesFired then return end
    RemotesFired = true

    EnableRagdollBypass()

    pcall(function()
        ForestStrike:FireServer({
            EggUid = FirstEggUid,
            GuardCFrame = CFrame.new(LOCK_POSITION)
        })
    end)

    task.spawn(function()
        for i = 1, 10 do
            task.wait(0.05)
            ForceUp()
            CleanupRagdollConstraints()
        end
    end)

    print("[VIPTP] ForestStrike Fired")
end

-- ==================================================
-- CHECK EGG
-- ==================================================
local function IsFirstEggInWorkspace()
    if not FirstEggUid then return false end
    return workspace:FindFirstChild(FirstEggUid) ~= nil
end

local function IsFirstEggInContainer()
    if not FirstEggUid then return false end
    if not Container then return false end
    return Container:FindFirstChild(FirstEggUid) ~= nil
end

local function IsTargetInContainer()
    if not TARGET_UID or not Container then return false end
    return Container:FindFirstChild(TARGET_UID) ~= nil
end

local function IsTargetInWorkspace()
    if not TARGET_UID then return false end
    return workspace:FindFirstChild(TARGET_UID) ~= nil
end

-- ==================================================
-- AUTO STOP (Callback ទៅ FarmingManager)
-- ==================================================
local function AutoStop()
    Running = false
    CurrentStep = "done"

    IsFlyToSafeRunning = false
    IsFlyBackRunning = false
    IsCollectTargetRunning = false

    CleanupMovers()
    DisableRagdollBypass()
    StopActiveHeartbeat()
    RestoreStats()

    print("[VIPTP] Auto Stop")

    if _G.YOKUDO_FarmingManager and _G.YOKUDO_FarmingManager.OnVIPTPComplete then
        task.spawn(function()
            task.wait(0.5)
            _G.YOKUDO_FarmingManager.OnVIPTPComplete()
        end)
    end
end

-- ==================================================
-- FLY TO SAFE ZONE (Thread ដាច់ដោយឡែក)
-- ==================================================
local function FlyToSafeZoneThread()
    if IsFlyToSafeRunning then return end
    IsFlyToSafeRunning = true

    task.spawn(function()
        CurrentStep = "to_safe"
        print("[VIPTP] FlyTP to Safe Zone (Speed 800)")

        FlyTP(SAFE_ZONE, RETURN_SPEED, false, true, function()
            -- ពេលដល់ Safe Zone → Check TARGET_UID ម្តងទៀត
            task.spawn(function()
                task.wait(1)

                if not Running then
                    IsFlyToSafeRunning = false
                    return
                end

                local EggInSpawn = IsTargetInContainer()
                local EggInWS = IsTargetInWorkspace()

                if EggInSpawn or EggInWS then
                    print("[VIPTP] Target Found Again → Restart Task")
                    IsFlyToSafeRunning = false
                    FullReset()
                    StartProcess()
                else
                    print("[VIPTP] Target Gone → Done")
                    IsFlyToSafeRunning = false
                    AutoStop()
                end
            end)
        end)

        -- រង់ចាំ FlyTP ចប់
        while Running and IsFlyToSafeRunning do
            task.wait(0.1)
        end
        IsFlyToSafeRunning = false
    end)
end

-- ==================================================
-- FLY BACK (Thread ដាច់ដោយឡែក) — Check Distance
-- ==================================================
local function FlyBackThread()
    if IsFlyBackRunning then return end
    IsFlyBackRunning = true

    task.spawn(function()
        print("[VIPTP] Fly Back Started (Auto Check Distance)")

        -- រង់ចាំ Egg ចូល workspace
        local WaitTime = 0
        while Running and IsFlyBackRunning and WaitTime < 10 do
            if IsTargetInWorkspace() then
                break
            end
            task.wait(0.1)
            WaitTime = WaitTime + 0.1
        end

        if not Running or not IsFlyBackRunning then
            IsFlyBackRunning = false
            return
        end

        -- Check Distance ជាប់ៗ
        while Running and IsFlyBackRunning do
            local Hum, Root = GetHumanoid()
            if not Root then break end

            local EggObj = GetTargetEggObject()
            if not EggObj then
                -- Egg អត់មាន → Done
                print("[VIPTP] Fly Back: Egg Gone")
                IsFlyBackRunning = false
                return
            end

            local EggPos = GetPosition(EggObj)
            if EggPos then
                local Distance = (EggPos - Root.Position).Magnitude

                if Distance > DISTANCE_THRESHOLD then
                    -- Drop → FlyTP ទៅ Egg
                    print("[VIPTP] Fly Back: Egg Drop (Dist: " .. math.floor(Distance) .. ") → Fly to Egg")

                    IsFlyBackRunning = false
                    CurrentStep = "fly_back_collect"

                    -- FlyTP ទៅ Egg (Speed 1000)
                    FlyTP(EggPos, FLY_SPEED, true, false, function()
                        -- ពេលដល់ Egg → Lock Y + 2
                        local CurrentEggPos = GetPosition(GetTargetEggObject())
                        if not CurrentEggPos then return end

                        StartLock(CurrentEggPos)

                        -- Save Y មុន Collect
                        SavedTargetY = CurrentEggPos.Y
                        print("[VIPTP] Saved Y: " .. tostring(SavedTargetY))

                        -- Auto Collect + Check Y Change
                        task.spawn(function()
                            local CollectStart = tick()

                            while Running and (tick() - CollectStart) < 60 do
                                task.wait(COLLECT_INTERVAL)

                                -- Collect
                                RemoteCollectTarget()

                                -- Check Y Change
                                local EggNow = GetTargetEggObject()
                                if not EggNow then
                                    -- Egg បាត់ → Collect បាន
                                    print("[VIPTP] Egg Gone → Collect Success")
                                    break
                                end

                                local NewPos = GetPosition(EggNow)
                                if NewPos then
                                    local YDiff = math.abs(NewPos.Y - SavedTargetY)
                                    if YDiff >= Y_CHANGE_THRESHOLD then
                                        print("[VIPTP] Y Change: " .. tostring(SavedTargetY) .. " → " .. tostring(NewPos.Y))
                                        break
                                    end
                                end
                            end

                            -- Y Change → FlyTP ទៅ Safe Zone វិញ
                            print("[VIPTP] Collect Done → Fly to Safe Zone")
                            FlyToSafeZoneThread()
                        end)
                    end)

                    return
                end
            end

            task.wait(0.1)
        end

        IsFlyBackRunning = false
    end)
end

-- ==================================================
-- HEARTBEAT (Main Logic)
-- ==================================================
local function StartActiveHeartbeat()
    if ActiveHeartbeat then
        ActiveHeartbeat:Disconnect()
        ActiveHeartbeat = nil
    end

    ActiveHeartbeat = RunService.Heartbeat:Connect(function()
        if not Running then return end

        local Hum, Root = GetHumanoid()
        if not Hum or not Root then return end
        if Hum.Health <= 0 then return end

        -- ដំណាក់កាល Collect First Egg
        if CurrentStep == "collect_first" and not CollectDone then
            if IsFirstEggInWorkspace() then
                CollectDone = true
                FireForestStrike()
                CurrentStep = "wait_spawn_back"
                return
            end

            if tick() - CollectTime > COLLECT_INTERVAL then
                CollectTime = tick()

                if IsFirstEggInContainer() then
                    RemoteCollectFirst()
                    CollectAttempts = CollectAttempts + 1
                else
                    if IsFirstEggInWorkspace() then
                        CollectDone = true
                        FireForestStrike()
                        CurrentStep = "wait_spawn_back"
                    end
                end
            end
        end

        -- រង់ចាំ First Egg ចូល Spawn វិញ → Instant TP ទៅ Target Egg
        if CurrentStep == "wait_spawn_back" and not FlyTargetStarted then
            if IsFirstEggInContainer() then
                FlyTargetStarted = true

                local TargetEgg = Container and Container:FindFirstChild(TARGET_UID)
                local TargetPos = nil

                if TargetEgg then
                    TargetPos = GetPosition(TargetEgg)
                elseif IsTargetInWorkspace() then
                    local WSEgg = workspace:FindFirstChild(TARGET_UID)
                    if WSEgg then
                        TargetPos = GetPosition(WSEgg)
                    end
                end

                if TargetPos then
                    print("[VIPTP] Instant TP to Target Egg")
                    InstantFlyTP(TargetPos, function()
                        CurrentStep = "collect_target"
                    end)
                else
                    AutoStop()
                end
            end
        end

        -- ដំណាក់កាល Collect Target Egg
        if CurrentStep == "collect_target" and not IsCollectTargetRunning then
            IsCollectTargetRunning = true

            task.spawn(function()
                -- Auto Collect
                while Running and IsCollectTargetRunning do
                    task.wait(COLLECT_INTERVAL)
                    RemoteCollectTarget()

                    -- ពេល Egg ចូល workspace → FlyTP ទៅ Safe Zone + Fly Back
                    if IsTargetInWorkspace() then
                        print("[VIPTP] Target Egg Entered Workspace → Fly to Safe Zone + Start Fly Back")
                        IsCollectTargetRunning = false

                        -- ចាប់ផ្តើម FlyTP ទៅ Safe Zone (Thread ដាច់ដោយឡែក)
                        FlyToSafeZoneThread()

                        -- ចាប់ផ្តើម Fly Back (Thread ដាច់ដោយឡែក)
                        FlyBackThread()

                        return
                    end

                    -- Egg អត់មានទាំងពីរ → Done
                    if not IsTargetInContainer() and not IsTargetInWorkspace() then
                        print("[VIPTP] Target Egg Gone → Fly to Safe Zone")
                        IsCollectTargetRunning = false
                        FlyToSafeZoneThread()
                        return
                    end
                end
            end)
        end
    end)
end

local function StopActiveHeartbeat()
    if ActiveHeartbeat then
        ActiveHeartbeat:Disconnect()
        ActiveHeartbeat = nil
    end
end

-- ==================================================
-- MAIN PROCESS
-- ==================================================
function StartProcess()
    Running = true
    CurrentStep = "search"

    CollectAttempts = 0
    CollectTime = 0
    FlyTargetStarted = false
    CollectDone = false
    RemotesFired = false

    IsFlyToSafeRunning = false
    IsFlyBackRunning = false
    IsCollectTargetRunning = false

    SavedTargetY = nil

    SaveStats()
    EnableRagdollBypass()

    SearchFirstEggs()

    if #FirstEggList == 0 then
        AutoStop()
        return
    end

    local Closest = FindClosestEgg()

    if not Closest then
        AutoStop()
        return
    end

    local EggPos = GetPosition(Closest.Slot)
    if not EggPos then
        AutoStop()
        return
    end

    CurrentStep = "fly_first"

    StartActiveHeartbeat()

    print("[VIPTP] FlyTP to First Egg (Shot TP, Speed 1000)")
    FlyTP(EggPos, FLY_SPEED, true, false, function()
        CurrentStep = "collect_first"
    end)
end

-- ==================================================
-- FULL RESET
-- ==================================================
function FullReset()
    Running = false
    CurrentStep = "idle"

    IsFlyToSafeRunning = false
    IsFlyBackRunning = false
    IsCollectTargetRunning = false

    FirstEggList = {}
    FirstEggUid = nil
    FirstEggSlotKey = nil
    CollectAttempts = 0
    CollectTime = 0
    FlyTargetStarted = false
    CollectDone = false
    RemotesFired = false
    SavedTargetY = nil

    CleanupMovers()
    DisableRagdollBypass()
    StopActiveHeartbeat()
    RestoreStats()

    print("[VIPTP] Full Reset")
end

-- ==================================================
-- ENABLE / DISABLE / SET
-- ==================================================
local function Enable()
    if Running then return end
    if not CollectEvent then warn("[VIPTP] CollectEvent not found") return end
    if not TARGET_UID then warn("[VIPTP] No Target ID") return end

    FullReset()
    StartProcess()

    print("[VIPTP] ON | Target: " .. tostring(TARGET_UID))
end

local function Disable()
    FullReset()
    print("[VIPTP] OFF")
end

local function SetTargetId(Id)
    TARGET_UID = Id
    print("[VIPTP] Target ID: " .. tostring(Id))
end

-- ==================================================
-- EXPORT
-- ==================================================
_G.YOKUDO_VIPTP = {
    Enable = Enable,
    Disable = Disable,
    SetTargetId = SetTargetId,
    IsEnabled = function() return Running end,
    GetTargetId = function() return TARGET_UID end,
    FLY_SPEED = FLY_SPEED,
    RETURN_SPEED = RETURN_SPEED,
    FLY_OFFSET = FLY_OFFSET,
    LOCK_ABOVE = LOCK_ABOVE,
    DISTANCE_THRESHOLD = DISTANCE_THRESHOLD,
    SAFE_ZONE = SAFE_ZONE,
}

-- ==================================================
-- REGISTER WITH CHARACTER SYSTEM
-- ==================================================
if _G.YOKUDO_CharacterSystem then
    _G.YOKUDO_CharacterSystem:RegisterFeature({
        Name = "VIPTP",
        Enable = Enable,
        Disable = Disable,
        IsEnabled = function() return Running end,
        OnCharacterAdded = function(Char, Hum, Root)
            if Running then
                task.wait(1)
                pcall(function()
                    local TargetId = TARGET_UID
                    Disable()
                    task.wait(0.5)
                    if TargetId then
                        SetTargetId(TargetId)
                    end
                    Enable()
                end)
            end
        end
    })
end

print("✅ VIPTP Loaded (AFK Farm | Thread Separated | Fly Back | Callback)")
