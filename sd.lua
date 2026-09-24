-- ==================================================
-- YOKUDO HUB | FEATURE | Auto Treadmill
-- ✅ Wrapper over AFKSystem — does NOT replace it
-- ✅ DisableWhenFarming: pauses treadmill when
--    FarmingManager OR AttackDrone is active,
--    restores when BOTH stop
-- ✅ Register ជាមួយ CharacterSystem
-- ==================================================

-- ==================================================
-- STATE
-- ==================================================
local TreadmillEnabled   = false  -- user's intent
local DisableWhenFarming = false  -- user's setting
local PausedByActivity   = false  -- true = we paused it, not the user

-- ==================================================
-- HELPERS
-- ==================================================
local function IsAnyActivityRunning()
    local farm  = _G.YOKUDO_FarmingManager and _G.YOKUDO_FarmingManager.IsEnabled()
    local drone = _G.YOKUDO_AttackDrone    and _G.YOKUDO_AttackDrone.IsEnabled()
    return farm or drone
end

local function StartTreadmill()
    if not _G.YOKUDO_AFKSystem then
        warn("[AutoTreadmill] AFKSystem not loaded!")
        return false
    end
    -- Avoid double-enable if AFKSystem is already running
    if _G.YOKUDO_AFKSystem.IsEnabled() then
        return true
    end
    _G.YOKUDO_AFKSystem.Enable()
    print("[AutoTreadmill] Treadmill: ON")
    return true
end

local function StopTreadmill()
    if not _G.YOKUDO_AFKSystem then return end
    if not _G.YOKUDO_AFKSystem.IsEnabled() then return end
    _G.YOKUDO_AFKSystem.Disable()
    print("[AutoTreadmill] Treadmill: OFF")
end

-- ==================================================
-- UI NOTIFY (callbacks set by the Tab after load)
-- _G.YOKUDO_AutoTreadmill_OnPause   = function() end
-- _G.YOKUDO_AutoTreadmill_OnRestore = function() end
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
-- PUBLIC API
-- ==================================================
local function Enable()
    TreadmillEnabled = true
    PausedByActivity = false

    -- If DisableWhenFarming is on and activity is already running,
    -- queue it — watcher will start it when activity stops
    if DisableWhenFarming and IsAnyActivityRunning() then
        PausedByActivity = true
        print("[AutoTreadmill] Treadmill queued — activity running")
        return
    end

    StartTreadmill()
end

local function Disable()
    TreadmillEnabled = false
    PausedByActivity = false
    StopTreadmill()
end

local function SetDisableWhenFarming(Value)
    DisableWhenFarming = Value
    print("[AutoTreadmill] DisableWhenFarming: " .. tostring(Value))
end

local function GetDisableWhenFarming()
    return DisableWhenFarming
end

local function IsEnabled()
    return TreadmillEnabled
end

-- ==================================================
-- WATCHER — checks every 0.5s
-- activity starts → pause treadmill (if setting on)
-- activity stops  → restore treadmill (if we paused it)
-- ==================================================
task.spawn(function()
    local WasActive = IsAnyActivityRunning()

    while task.wait(0.5) do
        -- Keep WasActive current when the feature is off
        -- so there's no false-trigger when the user turns it on
        if not DisableWhenFarming then
            WasActive = IsAnyActivityRunning()
            continue
        end

        local IsActive = IsAnyActivityRunning()

        -- Activity just STARTED
        if IsActive and not WasActive then
            if TreadmillEnabled and _G.YOKUDO_AFKSystem and _G.YOKUDO_AFKSystem.IsEnabled() then
                StopTreadmill()
                PausedByActivity = true
                NotifyPause()
                print("[AutoTreadmill] Paused — farm/drone started")
            end

        -- Activity just STOPPED
        elseif not IsActive and WasActive then
            if TreadmillEnabled and PausedByActivity then
                PausedByActivity = false
                StartTreadmill()
                NotifyRestore()
                print("[AutoTreadmill] Restored — farm/drone stopped")
            end
        end

        WasActive = IsActive
    end
end)

-- ==================================================
-- EXPORT
-- ==================================================
_G.YOKUDO_AutoTreadmill = {
    Enable                = Enable,
    Disable               = Disable,
    IsEnabled             = IsEnabled,
    SetDisableWhenFarming = SetDisableWhenFarming,
    GetDisableWhenFarming = GetDisableWhenFarming,
}

-- ==================================================
-- REGISTER WITH CHARACTER SYSTEM
-- ==================================================
if _G.YOKUDO_CharacterSystem then
    _G.YOKUDO_CharacterSystem:RegisterFeature({
        Name      = "AutoTreadmill",
        Enable    = Enable,
        Disable   = Disable,
        IsEnabled = IsEnabled,
        OnCharacterAdded = function(Char, Hum, Root)
            -- AFKSystem has its own OnCharacterAdded that restarts
            -- its distance-check loop. We wait 2s so it finishes
            -- its own restart before we check whether to re-enable.
            if TreadmillEnabled and not PausedByActivity then
                task.wait(2)
                pcall(function()
                    -- Only call Enable if AFKSystem didn't restart on its own
                    if _G.YOKUDO_AFKSystem and not _G.YOKUDO_AFKSystem.IsEnabled() then
                        StartTreadmill()
                    end
                end)
            end
        end
    })
end

print("✅ AutoTreadmill Feature Loaded")
