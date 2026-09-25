--- Entry point for the Land Encounters and Points of Interest mod. Wires up managers,
--- registers listeners and save/load callbacks, and runs campaign detection at first_tick.

--- Publish CA engine globals into _G BEFORE any require call. With the user's mod loadout
--- (mixer framework + pj_error_wrapping), script/campaign/mod/*.lua files execute inside a
--- custom environment that exposes `cm`, `core`, `out` etc. directly to this file but does NOT
--- put them in _G. Required modules (core/save_load, core/listeners, etc.) run with the
--- standard `_ENV = _G`, so without these explicit assignments they crash on `cm:add_*`,
--- `core:add_listener`, and similar calls at module-load time.
_G.core                = core
_G.cm                  = cm
_G.out                 = out
_G.script_error        = script_error
_G.random_army_manager = random_army_manager
_G.invasion_manager    = invasion_manager
_G.mission_manager     = mission_manager
_G.get_mct             = get_mct

require("script/land_encounters/utils/common")
require("script/land_encounters/core/mct")

--- This file only contains module wiring - manager instantiation, listener registration,
--- and the first_tick campaign-detection callback. The runtime logic lives in
--- script/land_encounters/{core,features,configs,utils}.

local coordinates = require("script/land_encounters/configs/coordinates")
local ie_land_encounters = coordinates.immortal_empires.treasures_and_spots
local ie_points_of_interest = coordinates.immortal_empires.points_of_interest
local roc_encounters = coordinates.realm_of_chaos.treasures_and_spots
local roc_points_of_interest = coordinates.realm_of_chaos.points_of_interest
local ieee_land_encounters = coordinates.immortal_empires_expanded.treasures_and_spots
local ieee_points_of_interest = coordinates.immortal_empires_expanded.points_of_interest

local LandEncounterManager = require("script/land_encounters/core/bootstrap")
local managers = require("script/land_encounters/core/managers")
local InvasionBattleManager = managers.InvasionBattleManager
local PointOfInterestEventManager = managers.PointOfInterestEventManager
local SpotEventManager = managers.SpotEventManager

local listeners = require("script/land_encounters/core/listeners")
local save_load = require("script/land_encounters/core/save_load")

--- Save/load callbacks must register at module-load (BEFORE CA's LoadingGame fires).
save_load.register()

--- Listeners register at module-load (persistent listeners survive campaign-to-battle context restart).
listeners.register()

--- Returns true if `mod_name` appears in MCT's enabled_mods list.
--- @param mod_name string The MCT mod key to look up.
--- @returns boolean True when the mod is present in MCT's enabled_mods array.
local function is_mod_enabled(mod_name)
    local enabled_mods = get_mct_settings().enabled_mods
    for _, enabled_mod in ipairs(enabled_mods) do
        if enabled_mod == mod_name then
            return true
        end
    end
    return false
end

--- Merges IE and IEEE coordinate tables by region key. IEEE adds entirely new regions, so there are no conflicts.
--- @param ie_coordinates table Region-keyed coordinate table for Immortal Empires.
--- @param ieee_coordinates table Region-keyed coordinate table for Immortal Empires Expanded.
--- @returns table A new region-keyed table containing entries from both inputs.
local function concatenate_encounters(ie_coordinates, ieee_coordinates)
    local combined_coordinates = {}

    for region, coordinates in pairs(ie_coordinates) do
        combined_coordinates[region] = coordinates
    end

    for region, coordinates in pairs(ieee_coordinates) do
        combined_coordinates[region] = coordinates
    end

    return combined_coordinates
end

--- Instantiates the runtime managers and hands references to listeners + save_load so they can read from them.
cm:add_pre_first_tick_callback(
    function()
        if listeners.invasion_battle_manager == nil then
            listeners.invasion_battle_manager = InvasionBattleManager:newFrom(core, random_army_manager, invasion_manager)
        end

        if listeners.land_manager == nil then
            listeners.land_manager = LandEncounterManager:new()
        end

        if listeners.point_of_interest_event_manager == nil then
            listeners.point_of_interest_event_manager = PointOfInterestEventManager:new(mission_manager, listeners.invasion_battle_manager)
        end

        if listeners.spot_event_manager == nil then
            listeners.spot_event_manager = SpotEventManager:new(listeners.invasion_battle_manager)
        end

        --- save_load needs the same manager instances for its save/load callbacks.
        save_load.land_manager = listeners.land_manager
        save_load.point_of_interest_event_manager = listeners.point_of_interest_event_manager
        save_load.spot_event_manager = listeners.spot_event_manager
    end
)

--- The three init_* functions below are globals on purpose (the original mod defined them as globals via missing
--- `local` keyword - preserve that). They read from save_load.* to decide restore vs fresh bootstrap.

--- Restores land encounters from saved state, or generates fresh ones if no save data exists.
--- @param encounters table Region-keyed coordinate set for land encounter spots.
--- @param points_of_interest table Region-keyed coordinate set for POI markers.
function initialize_land_encounters_state(encounters, points_of_interest)
    if next(save_load.saved_land_encounters_state) ~= nil then
        listeners.land_manager:restore_from_previous_state(encounters, points_of_interest, save_load.saved_land_encounters_state)
    else
        listeners.land_manager:generate_land_encounters(encounters, points_of_interest)
    end
end


--- Restores any in-flight spot event from saved state. No-op when there's no pending event.
function initialize_spot_event_manager_state()
    if next(save_load.saved_spot_event_state) ~= nil then
        listeners.spot_event_manager:reinstate_event_if_able(save_load.saved_spot_event_state)
    end
end


--- Restores any in-flight POI event from saved state, or generates fresh POI states.
--- @param points_of_interest table Region-keyed coordinate set for POI markers.
function initialize_poi_event_manager_state(points_of_interest)
    if next(save_load.saved_poi_event_state) ~= nil then
        listeners.point_of_interest_event_manager:reinstate_event_if_able(save_load.saved_poi_event_state)
    else
        listeners.point_of_interest_event_manager:generate_points_of_interests_states(points_of_interest)
    end
end

--- Detects the active campaign at first_tick and bootstraps the land encounters + POI managers with that campaign's coordinate set.
cm:add_first_tick_callback(
    function()
        if is_mod_enabled("!cr_immortal_empires_expanded") then
            out("DEBUG - Current Campaign is Immortal Empires Expanded.")
            local ieee_combined_coordinates = concatenate_encounters(ie_land_encounters, ieee_land_encounters)
            local ieee_combined_points_of_interest = concatenate_encounters(ie_points_of_interest, ieee_points_of_interest)

            initialize_land_encounters_state(ieee_combined_coordinates, ieee_combined_points_of_interest)
            initialize_poi_event_manager_state(ieee_combined_points_of_interest)
        elseif cm:get_campaign_name() == "wh3_main_chaos" then
            out("DEBUG - Current Campaign is Realm of Chaos.")
            initialize_land_encounters_state(roc_encounters, roc_points_of_interest)
            initialize_poi_event_manager_state(roc_points_of_interest)
        elseif cm:get_campaign_name() == "main_warhammer" then
            out("DEBUG - Current Campaign is Immortal Empires.")
            initialize_land_encounters_state(ie_land_encounters, ie_points_of_interest)
            initialize_poi_event_manager_state(ie_points_of_interest)
        end
        initialize_spot_event_manager_state()
    end
)
