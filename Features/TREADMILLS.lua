-- ==================================================
-- YOKUDO HUB | FEATURE | Auto Treadmill
-- ==================================================
-- Priority:
--   1. Spawn Egg -> FarmingManager handles it
--   2. No Egg + Day -> FarmingManager starts Drone
--   3. No Egg + no Drone -> Treadmill
--
-- TREADMILL remains a wrapper around AFKSystem.
-- It does NOT duplicate the farming logic.
-- ==================================================

-- ==================================================
-- KILL PREVIOUS INSTANCE
-- ==================================================

if _G.YOKUDO_AutoTreadmill and _G.YOKUDO_AutoTreadmill.Destroy then
    pcall(_G.YOKUDO_AutoTreadmill.Destroy)
end

local Alive = true

-- ==================================================
-- SETTINGS
-- ==================================================

local CHECK_INTERVAL    = 0.5
local RESUME_DELAY      = 2
local START_RETRY_DELAY = 5

-- ==================================================
-- STATE
-- ==================================================

local TreadmillEnabled = false
local DisableWhenFarming = true

local Paused = false
local IdleSince = nil
local NextStartTry = 0

-- IMPORTANT:
-- This tells us whether Treadmill itself started
-- FarmingManager.
--
-- If the user had FarmingManager enabled manually,
-- Treadmill will NOT take ownership of it and will
-- NOT disable it when Treadmill is turned off.
local StartedFarmingManager = false

-- ==================================================
-- SAFE CALL
-- ==================================================

local function Safe(Fn, ...)
    if type(Fn) ~= "function" then
        return nil
    end

    local Ok, Result = pcall(Fn, ...)

    if Ok then
        return Result
    end

    return nil
end

-- ==================================================
-- CHECK FEATURE STATE
-- ==================================================

local function FeatureOn(GlobalName)
    local Feature = _G[GlobalName]

    if Feature and type(Feature.IsEnabled) == "function" then
        return Safe(Feature.IsEnabled) and true or false
    end

    return false
end

-- ==================================================
-- GET FARMING MANAGER
-- ==================================================

local function GetFarmingManager()
    local FM = _G.YOKUDO_FarmingManager

    if FM and type(FM.Enable) == "function" then
        return FM
    end

    return nil
end

-- ==================================================
-- START FARMING MANAGER IF NEEDED
-- ==================================================

local function EnsureFarmingManager()
    if not TreadmillEnabled then
        return false
    end

    local FM = GetFarmingManager()

    -- FarmingManager has not loaded yet.
    -- Loader loads TREADMILL before FarmingManager,
    -- so this is expected during startup.
    if not FM then
        return false
    end

    -- Already running.
    if FeatureOn("YOKUDO_FarmingManager") then
        return true
    end

    -- Start FarmingManager.
    local Result = Safe(FM.Enable)

    if FeatureOn("YOKUDO_FarmingManager") then
        StartedFarmingManager = true
        print("[AutoTreadmill] FarmingManager: ON")
        return true
    end

    if Result == false then
        warn("[AutoTreadmill] Failed to enable FarmingManager")
    end

    return false
end

-- ==================================================
-- STOP FARMING MANAGER IF WE OWNED IT
-- ==================================================

local function ReleaseFarmingManager()
    if not StartedFarmingManager then
        return
    end

    local FM = GetFarmingManager()

    if FM and FeatureOn("YOKUDO_FarmingManager") then
        Safe(FM.Disable)
        print("[AutoTreadmill] FarmingManager: OFF")
    end

    StartedFarmingManager = false
end

-- ==================================================
-- IS FARMING BUSY?
-- ==================================================
-- FarmingManager itself is the priority controller.
--
-- We consider the player busy when:
--
--   - Drone is running
--   - VIPTP is running
--   - TeleportSystem is running
--   - FarmingManager found an egg
--
-- IMPORTANT:
-- FarmingManager being enabled by itself does NOT
-- automatically mean the treadmill must stay off.
-- It can be enabled and simply waiting for an egg.
-- ==================================================

local function IsFarmBusy()

    -- --------------------------------------------------
    -- 1. Drone
    -- --------------------------------------------------

    if FeatureOn("YOKUDO_AttackDrone") then
        return true
    end

    -- --------------------------------------------------
    -- 2. Egg teleport / farming
    -- --------------------------------------------------

    if FeatureOn("YOKUDO_VIPTP") then
        return true
    end

    -- --------------------------------------------------
    -- 3. Other teleport system
    -- --------------------------------------------------

    if FeatureOn("YOKUDO_TeleportSystem") then
        return true
    end

    -- --------------------------------------------------
    -- 4. FarmingManager currently has an egg
    -- --------------------------------------------------

    local FM = GetFarmingManager()

    if FM and FeatureOn("YOKUDO_FarmingManager") then

        if type(FM.FindBestEgg) == "function" then
            local BestEgg = Safe(FM.FindBestEgg)

            if BestEgg then
                return true
            end
        end
    end

    return false
end

-- ==================================================
-- AFK / TREADMILL WRAPPERS
-- ==================================================

local function StartTreadmill()

    local AFK = _G.YOKUDO_AFKSystem

    if not AFK then
        warn("[AutoTreadmill] AFKSystem not loaded!")
        return false
    end

    if type(AFK.IsEnabled) == "function" and AFK.IsEnabled() then
        return true
    end

    if type(AFK.Enable) ~= "function" then
        warn("[AutoTreadmill] AFKSystem.Enable() not found!")
        return false
    end

    Safe(AFK.Enable)

    -- AFKSystem can disable itself if it cannot
    -- find the treadmill.
    if type(AFK.IsEnabled) == "function" and AFK.IsEnabled() then
        print("[AutoTreadmill] Treadmill: ON")
        return true
    end

    NextStartTry = os.clock() + START_RETRY_DELAY

    return false
end

local function StopTreadmill()

    local AFK = _G.YOKUDO_AFKSystem

    if not AFK then
        return
    end

    if type(AFK.IsEnabled) == "function"
        and AFK.IsEnabled()
        and type(AFK.Disable) == "function" then

        Safe(AFK.Disable)

        print("[AutoTreadmill] Treadmill: OFF")
    end
end

-- ==================================================
-- UI CALLBACKS
-- ==================================================

local function NotifyPause()

    if type(_G.YOKUDO_AutoTreadmill_OnPause) == "function" then
        pcall(_G.YOKUDO_AutoTreadmill_OnPause)
    end
end

local function NotifyRestore()

    if type(_G.YOKUDO_AutoTreadmill_OnRestore) == "function" then
        pcall(_G.YOKUDO_AutoTreadmill_OnRestore)
    end
end

-- ==================================================
-- CORE REFRESH
-- ==================================================
--
-- This is now the important flow:
--
-- Treadmill ON
--       ↓
-- Ensure FarmingManager is ON
--       ↓
-- Is egg/drone/farming active?
--       │
--       ├── YES → treadmill OFF
--       │
--       └── NO  → treadmill ON
--
-- Therefore the treadmill becomes the fallback.
-- ==================================================

local function Refresh()

    if not TreadmillEnabled then
        return
    end

    local AFK = _G.YOKUDO_AFKSystem

    if not AFK then
        return
    end

    -- --------------------------------------------------
    -- Make sure FarmingManager is running.
    --
    -- This is intentionally called from Refresh because
    -- Loader loads TREADMILL before FarmingManager.
    -- Once FarmingManager becomes available, the watcher
    -- can start it automatically.
    -- --------------------------------------------------

    EnsureFarmingManager()

    local Busy = false

    if DisableWhenFarming then
        Busy = IsFarmBusy()
    end

    local Now = os.clock()

    -- ==================================================
    -- FARMING HAS PRIORITY
    -- ==================================================

    if Busy then

        IdleSince = nil

        StopTreadmill()

        if not Paused then
            Paused = true

            NotifyPause()

            print("[AutoTreadmill] Paused — farming has priority")
        end

        return
    end

    -- ==================================================
    -- NOTHING TO FARM
    -- ==================================================
    --
    -- Give the system a small delay before starting the
    -- treadmill. This prevents rapid ON/OFF switching
    -- when an egg disappears and another one is about
    -- to be detected.
    -- ==================================================

    IdleSince = IdleSince or Now

    if Now - IdleSince < RESUME_DELAY then
        return
    end

    -- ==================================================
    -- START TREADMILL
    -- ==================================================

    if not AFK.IsEnabled() and Now >= NextStartTry then

        StartTreadmill()

    end

    -- ==================================================
    -- UPDATE PAUSE STATE
    -- ==================================================

    if Paused and AFK.IsEnabled() then

        Paused = false

        NotifyRestore()

        print("[AutoTreadmill] Resumed — no higher priority farming")
    end
end

-- ==================================================
-- PUBLIC API
-- ==================================================

local function Enable()

    if TreadmillEnabled then
        return true
    end

    if not _G.YOKUDO_AFKSystem then
        warn("[AutoTreadmill] AFKSystem not loaded!")
        return false
    end

    TreadmillEnabled = true

    Paused = false

    NextStartTry = 0

    IdleSince = os.clock() - RESUME_DELAY

    -- Reset ownership every time this feature is
    -- manually enabled.
    StartedFarmingManager = false

    -- First refresh immediately.
    --
    -- FarmingManager may not exist yet because Loader
    -- loads it after TREADMILL. The watcher below will
    -- catch it once it is loaded.
    Refresh()

    return true
end

local function Disable()

    local WasPaused = Paused

    TreadmillEnabled = false

    Paused = false

    IdleSince = nil

    -- Stop actual treadmill.
    StopTreadmill()

    -- Only disable FarmingManager if Treadmill itself
    -- started it.
    ReleaseFarmingManager()

    if WasPaused then
        NotifyRestore()
    end
end

local function IsEnabled()
    return TreadmillEnabled
end

local function SetDisableWhenFarming(Value)

    DisableWhenFarming = Value and true or false

    IdleSince = os.clock() - RESUME_DELAY

    print(
        "[AutoTreadmill] DisableWhenFarming: "
        .. tostring(DisableWhenFarming)
    )

    Refresh()
end

local function GetDisableWhenFarming()
    return DisableWhenFarming
end

-- ==================================================
-- WATCHER
-- ==================================================

task.spawn(function()

    while Alive do

        task.wait(CHECK_INTERVAL)

        pcall(Refresh)

    end

end)

-- ==================================================
-- EXPORT
-- ==================================================

_G.YOKUDO_AutoTreadmill = {

    Enable = Enable,

    Disable = Disable,

    IsEnabled = IsEnabled,

    IsPaused = function()
        return Paused
    end,

    Refresh = Refresh,

    SetDisableWhenFarming = SetDisableWhenFarming,

    GetDisableWhenFarming = GetDisableWhenFarming,

    Destroy = function()

        Alive = false

        if TreadmillEnabled then
            Disable()
        end

    end,
}

-- ==================================================
-- REGISTER WITH CHARACTER SYSTEM
-- ==================================================

if _G.YOKUDO_CharacterSystem then

    _G.YOKUDO_CharacterSystem:RegisterFeature({

        Name = "AutoTreadmill",

        Enable = Enable,

        Disable = Disable,

        IsEnabled = IsEnabled,

    })

else

    warn(
        "[AutoTreadmill] CharacterSystem not loaded — "
        .. "feature not registered"
    )

end

-- ==================================================
-- LOADED
-- ==================================================

print("✅ AutoTreadmill Feature Loaded")
