-- ==================================================
-- YOKUDO HUB | FEATURE | Auto Treadmill
-- ✅ Wrapper over AFKSystem — does NOT replace it
-- ✅ Treadmill runs while you are idle
-- ✅ Farm / Drone starts working -> treadmill steps aside
-- ✅ Work is done -> treadmill comes back by itself
-- ✅ Level-based watcher: fixes itself if something else
--    (ManagerDrone, respawn) turns AFKSystem off
-- ==================================================

-- Kill previous instance (prevents duplicate watchers on re-execute)
if _G.YOKUDO_AutoTreadmill and _G.YOKUDO_AutoTreadmill.Destroy then
    pcall(_G.YOKUDO_AutoTreadmill.Destroy)
end

local Alive = true

-- ==================================================
-- SETTINGS
-- ==================================================
local CHECK_INTERVAL    = 0.5 -- watcher tick
local RESUME_DELAY      = 2   -- idle this long before treadmill returns
                              -- (covers the gap ManagerDrone leaves between
                              --  "AFK off" and "Drone start")
local START_RETRY_DELAY = 5   -- wait before retrying a failed start

-- ==================================================
-- STATE
-- ==================================================
local TreadmillEnabled   = false -- user's intent (the checkbox)
local DisableWhenFarming = true  -- ON by default
local Paused             = false -- true = we stepped aside for farming
local IdleSince          = nil
local NextStartTry       = 0

-- ==================================================
-- IS THE PLAYER BUSY FARMING?
-- NOTE: FarmingManager.IsEnabled() alone is NOT "busy" — it stays
-- true while it idles waiting for an egg. It only counts as busy
-- when an egg is actually there to go and farm.
-- ==================================================
local function Safe(Fn, ...)
    local Ok, Result = pcall(Fn, ...)
    if Ok then return Result end
    return nil
end

local function FeatureOn(GlobalName)
    local Feature = _G[GlobalName]
    if Feature and Feature.IsEnabled then
        return Safe(Feature.IsEnabled) and true or false
    end
    return false
end

local function IsFarmBusy()
    if FeatureOn("YOKUDO_AttackDrone")     then return true end -- drone (event / day farm)
    if FeatureOn("YOKUDO_VIPTP")           then return true end -- egg teleport running
    if FeatureOn("YOKUDO_TeleportSystem")  then return true end -- Auto Farming tab

    -- FarmingManager is ON and an egg exists -> it is about to
    -- (or already) flying to safe zone / waiting for day / VIPTP
    local FM = _G.YOKUDO_FarmingManager
    if FM and FeatureOn("YOKUDO_FarmingManager") and FM.FindBestEgg then
        if Safe(FM.FindBestEgg) then return true end
    end

    return false
end

-- ==================================================
-- AFK SYSTEM WRAPPERS
-- ==================================================
local function StartTreadmill()
    local AFK = _G.YOKUDO_AFKSystem
    if not AFK then
        warn("[AutoTreadmill] AFKSystem not loaded!")
        return false
    end
    if AFK.IsEnabled() then return true end

    AFK.Enable()

    -- AFKSystem.Enable() turns itself back off if it can't find the treadmill
    if AFK.IsEnabled() then
        print("[AutoTreadmill] Treadmill: ON")
        return true
    end

    NextStartTry = os.clock() + START_RETRY_DELAY
    return false
end

local function StopTreadmill()
    local AFK = _G.YOKUDO_AFKSystem
    if AFK and AFK.IsEnabled() then
        AFK.Disable()
        print("[AutoTreadmill] Treadmill: OFF")
    end
end

-- ==================================================
-- UI CALLBACKS (set by the Farming tab)
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
-- CORE — one function decides everything
-- ==================================================
local function Refresh()
    if not TreadmillEnabled then return end

    local AFK = _G.YOKUDO_AFKSystem
    if not AFK then return end

    local Busy = DisableWhenFarming and IsFarmBusy()
    local Now  = os.clock()

    if Busy then
        -- Farming: treadmill steps aside immediately
        IdleSince = nil
        StopTreadmill()
        if not Paused then
            Paused = true
            NotifyPause()
            print("[AutoTreadmill] Paused — farming")
        end
        return
    end

    -- Idle: wait RESUME_DELAY before coming back (avoids flicker)
    IdleSince = IdleSince or Now
    if Now - IdleSince < RESUME_DELAY then return end

    if not AFK.IsEnabled() and Now >= NextStartTry then
        StartTreadmill()
    end

    if Paused and AFK.IsEnabled() then
        Paused = false
        NotifyRestore()
        print("[AutoTreadmill] Resumed — farming finished")
    end
end

-- ==================================================
-- PUBLIC API
-- ==================================================
local function Enable()
    if not _G.YOKUDO_AFKSystem then
        warn("[AutoTreadmill] AFKSystem not loaded!")
        return false
    end

    TreadmillEnabled = true
    Paused           = false
    NextStartTry     = 0
    IdleSince        = os.clock() - RESUME_DELAY -- no delay on manual enable

    Refresh() -- starts now if idle, or pauses now if farming
    return true
end

local function Disable()
    local WasPaused = Paused
    TreadmillEnabled = false
    Paused           = false
    IdleSince        = nil
    StopTreadmill()
    if WasPaused then NotifyRestore() end -- reset the UI's "paused" label
end

local function IsEnabled()
    return TreadmillEnabled
end

local function SetDisableWhenFarming(Value)
    DisableWhenFarming = Value and true or false
    IdleSince = os.clock() - RESUME_DELAY -- apply right away
    print("[AutoTreadmill] DisableWhenFarming: " .. tostring(DisableWhenFarming))
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
    Enable                = Enable,
    Disable               = Disable,
    IsEnabled             = IsEnabled,
    IsPaused              = function() return Paused end,
    Refresh               = Refresh,
    SetDisableWhenFarming = SetDisableWhenFarming,
    GetDisableWhenFarming = GetDisableWhenFarming,
    Destroy               = function()
        Alive = false
        if TreadmillEnabled then Disable() end
    end,
}

-- ==================================================
-- REGISTER WITH CHARACTER SYSTEM
-- No OnCharacterAdded needed: on respawn CharacterSystem already calls
-- Disable() -> Enable() on every enabled feature, and Enable() re-checks
-- whether farming is running. The watcher heals any race with AFKSystem's
-- own restart.
-- ==================================================
if _G.YOKUDO_CharacterSystem then
    _G.YOKUDO_CharacterSystem:RegisterFeature({
        Name      = "AutoTreadmill",
        Enable    = Enable,
        Disable   = Disable,
        IsEnabled = IsEnabled,
    })
else
    warn("[AutoTreadmill] CharacterSystem not loaded — feature not registered")
end

print("✅ AutoTreadmill Feature Loaded")
