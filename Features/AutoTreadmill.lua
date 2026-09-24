-- ==================================================
-- YOKUDO HUB | FEATURE | Auto Treadmill
-- ✅ Manages AFKSystem (treadmill) enable/disable
-- ✅ Auto-pauses when FarmingManager OR AttackDrone
--    is active (disable-when-farming mode)
-- ✅ Restores when BOTH are off
-- ✅ Register ជាមួយ CharacterSystem
-- ==================================================

-- ==================================================
-- STATE
-- ==================================================
local TreadmillEnabled     = false   -- user's intent (toggle)
local DisableWhenFarming   = false   -- user's setting
local PausedByActivity     = false   -- true = WE paused it due to farm/drone

-- ==================================================
-- HELPERS
-- ==================================================
local function IsAnyActivityRunning()
    local farm  = _G.YOKUDO_FarmingManager  and _G.YOKUDO_FarmingManager.IsEnabled()
    local drone = _G.YOKUDO_AttackDrone     and _G.YOKUDO_AttackDrone.IsEnabled()
    return farm or drone
end

local function StartTreadmill()
    if not _G.YOKUDO_AFKSystem then
        warn("[AutoTreadmill] AFKSystem not loaded!")
        return false
    end
    _G.YOKUDO_AFKSystem.Enable()
    print("[AutoTreadmill] Treadmill: ON")
    return true
end

local function StopTreadmill()
    if not _G.YOKUDO_AFKSystem then return end
    _G.YOKUDO_AFKSystem.Disable()
    print("[AutoTreadmill] Treadmill: OFF")
end

-- ==================================================
-- NOTIFY UI (set by Farming tab after load)
-- ==================================================
local function NotifyPause()
    if _G.YOKUDO_AutoTreadmill_OnPause then
        _G.YOKUDO_AutoTreadmill_OnPause()
    end
end

local function NotifyRestore()
    if _G.YOKUDO_AutoTreadmill_OnRestore then
        _G.YOKUDO_AutoTreadmill_OnRestore()
    end
end

-- ==================================================
-- PUBLIC API
-- ==================================================
local function Enable()
    TreadmillEnabled = true
    PausedByActivity = false

    -- If disable-when-farming is on and activity is already running, don't start yet
    if DisableWhenFarming and IsAnyActivityRunning() then
        PausedByActivity = true
        print("[AutoTreadmill] Treadmill queued — activity running, will start when done")
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
-- WATCHER: auto-pause / restore around farm + drone
-- Checks every 0.5s:
--   activity starts → pause treadmill
--   activity stops  → restore treadmill (if user still wants it on)
-- ==================================================
task.spawn(function()
    local WasActive = false

    while task.wait(0.5) do
        if not DisableWhenFarming then
            WasActive = IsAnyActivityRunning()
            continue
        end

        local IsActive = IsAnyActivityRunning()

        if IsActive and not WasActive then
            -- Activity just started
            if TreadmillEnabled and _G.YOKUDO_AFKSystem and _G.YOKUDO_AFKSystem.IsEnabled() then
                StopTreadmill()
                PausedByActivity = true
                NotifyPause()
                print("[AutoTreadmill] Treadmill paused (farm/drone started)")
            end

        elseif not IsActive and WasActive then
            -- Activity just stopped
            if TreadmillEnabled and PausedByActivity then
                PausedByActivity = false
                StartTreadmill()
                NotifyRestore()
                print("[AutoTreadmill] Treadmill restored (farm/drone stopped)")
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
            -- AFKSystem handles its own re-init; just make sure
            -- we restart if the user still wants treadmill on
            -- and no blocking activity is running
            if TreadmillEnabled and not PausedByActivity then
                task.wait(1)
                pcall(function()
                    if _G.YOKUDO_AFKSystem and not _G.YOKUDO_AFKSystem.IsEnabled() then
                        StartTreadmill()
                    end
                end)
            end
        end
    })
end

print("✅ AutoTreadmill Feature Loaded")
