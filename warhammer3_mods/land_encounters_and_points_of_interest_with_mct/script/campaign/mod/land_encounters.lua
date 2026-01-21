require("script/land_encounters/utils/logger")
require("script/shared/mct_settings")

------------------------------------------------
--- Constant values of the class [DO NOT CHANGE]
------------------------------------------------
local IS_PERSISTENT_LISTENER = true

--[[
    This file only contains the logic related to the game functions. 
    The mod logic is in scripts/land_encounters for order and maintainability.
--]]
--[[ Coordinates of the warhammer 3 maps --]]
local ie_land_encounters = require("script/land_encounters/constants/coordinates/inmortal_empires/treasures_and_spots")
local ie_points_of_interest = require("script/land_encounters/constants/coordinates/inmortal_empires/points_of_interest")

local roc_encounters = require("script/land_encounters/constants/coordinates/realm_of_chaos/treasures_and_spots")
local roc_points_of_interest = require("script/land_encounters/constants/coordinates/realm_of_chaos/points_of_interest")

local ieee_land_encounters = require("script/land_encounters/constants/coordinates/immortal_empires_expanded/treasures_and_spots")
local ieee_points_of_interest = require("script/land_encounters/constants/coordinates/immortal_empires_expanded/points_of_interest")

--[[ Dilemma Events created for this script --]]
local battle_events = require("script/land_encounters/constants/events/battle_spot_events")
local smithy_events = require("script/land_encounters/constants/events/smithy_events")

--[[ Managers --]]
local InvasionBattleManager = require("script/land_encounters/controllers/invasion_battle_manager")
local LandEncounterManager = require("script/land_encounters/controllers/land_encounter_manager")
local PointOfInterestEventManager = require("script/land_encounters/controllers/point_of_interest_event_manager")
local SpotEventManager = require("script/land_encounters/controllers/spot_event_manager")

--[[ Instance of the Model of the the land encounters functionality --]]
local invasion_battle_manager = nil
local land_manager = nil
local point_of_interest_event_manager = nil
local spot_event_manager = nil

local saved_land_encounters_state = {}
local saved_spot_event_state = {}
local saved_poi_event_state = {}
local current_spot_info = {}

cm:add_pre_first_tick_callback(
    function()
        if invasion_battle_manager == nil then
            invasion_battle_manager = InvasionBattleManager:newFrom(core, random_army_manager, invasion_manager)                    
        end
        
        if land_manager == nil then
            land_manager = LandEncounterManager:new()        
        end
        
        if point_of_interest_event_manager == nil then
            point_of_interest_event_manager = PointOfInterestEventManager:new(mission_manager, invasion_battle_manager)
        end 

        if spot_event_manager == nil then
            spot_event_manager = SpotEventManager:new(invasion_battle_manager)
        end
    end
)

-- Helper function to check if a mod is enabled
local function is_mod_enabled(mod_name)
    local enabled_mods = get_mct_settings().enabled_mods
    for _, enabled_mod in ipairs(enabled_mods) do
        if enabled_mod == mod_name then
            return true
        end
    end
    return false
end

-- Concatenate IE and IEEE land encounters
local function concatenate_encounters(ie_coordinates, ieee_coordinates)
    local combined_coordinates = {}
    
    -- Copy all IE encounters.
    for region, coordinates in pairs(ie_coordinates) do
        combined_coordinates[region] = coordinates
    end
    
    -- Add IEEE encounters (no conflicts since they're for entirely new regions).
    for region, coordinates in pairs(ieee_coordinates) do
        combined_coordinates[region] = coordinates
    end
    
    return combined_coordinates
end

--[[ Triggered on campaign first tick.
Initializes the land encounters by instantiating a LandEncounterModel
--]]
cm:add_first_tick_callback(
    function()
        -- Immortal Empires Expanded
        if is_mod_enabled("!cr_immortal_empires_expanded") then
            out("DEBUG - Current Campaign is Immortal Empires Expanded.")
            -- Concatenate IE and IEEE encounters.
            local ieee_combined_coordinates = concatenate_encounters(ie_land_encounters, ieee_land_encounters)
            local ieee_combined_points_of_interest = concatenate_encounters(ie_points_of_interest, ieee_points_of_interest)

            -- Reuse the Points of Interests from the Immortal Empires campaign.
            initialize_land_encounters_state(ieee_combined_coordinates, ieee_combined_points_of_interest)
            initialize_poi_event_manager_state(ieee_combined_points_of_interest)
        -- Realm of Chaos
        elseif cm:get_campaign_name() == "wh3_main_chaos" then
            out("DEBUG - Current Campaign is Realm of Chaos.")
            initialize_land_encounters_state(roc_encounters, roc_points_of_interest)
            initialize_poi_event_manager_state(roc_points_of_interest)
        -- Immortal Empires
        elseif cm:get_campaign_name() == "main_warhammer" then
            out("DEBUG - Current Campaign is Immortal Empires.")
            initialize_land_encounters_state(ie_land_encounters, ie_points_of_interest)
            initialize_poi_event_manager_state(ie_points_of_interest)
        end
        initialize_spot_event_manager_state()
    end
)


function initialize_land_encounters_state(encounters, points_of_interest)
    if next(saved_land_encounters_state) ~= nil then
        land_manager:restore_from_previous_state(encounters, points_of_interest, saved_land_encounters_state)
    else
        land_manager:generate_land_encounters(encounters, points_of_interest)
    end
end


function initialize_spot_event_manager_state()
    if next(saved_spot_event_state) ~= nil then
        spot_event_manager:reinstate_event_if_able(saved_spot_event_state)
    end
end


function initialize_poi_event_manager_state(points_of_interest)
    if next(saved_poi_event_state) ~= nil then
        point_of_interest_event_manager:reinstate_event_if_able(saved_poi_event_state)
    else
        point_of_interest_event_manager:generate_points_of_interests_states(points_of_interest)
    end
end

--[[ Triggered every player turn
Updates the land_encounters so that some are automatically disposed if their time has run up. Adds more encounters when this happens
--]]
core:add_listener(
	"land_enc_and_poi_faction_turn_start_update",
	"FactionTurnStart",
    function(context)
        return context:faction():is_human()
    end,
	function(context)
        -- update physical spot states
        land_manager:update_land_encounters()
        point_of_interest_event_manager:update_state_given_turn_passing() 
	end,
	IS_PERSISTENT_LISTENER
)


--[[ Triggered every time someone enters any area. 
To just treat the land encounters, we use the first function that checks wether the area id contains the library special marker.
triggers an encounter
areaAndCharacterInfo is: https://chadvandy.github.io/tw_modding_resources/WH3/scripting_doc.html#AreaEntered
--]]
core:add_listener(
	"land_enc_and_poi_area_entered_trigger_event",
	"AreaEntered",
	function(area_and_character_info)
        local triggering_character = area_and_character_info:family_member():character()
        local marker_id = area_and_character_info:area_key()
        return land_manager:check_if_is_triggerable_marker(triggering_character, marker_id)
	end,
	function(area_and_character_info)
        local marker_id = area_and_character_info:area_key()
        current_spot_info = land_manager:find_triggering_spot_info(marker_id)
        local can_delete_land_encounter = false
        if current_spot_info.spot_type == 0 then -- event_spot
            spot_event_manager:set_current_spot_info(current_spot_info)
            can_delete_land_encounter = spot_event_manager:trigger_spot_event(area_and_character_info, cm:turn_number())
        elseif current_spot_info.spot_type == 1 then -- smithy spot type
            point_of_interest_event_manager:trigger_poi_event("SmithySpot", area_and_character_info, current_spot_info)
        end

        if can_delete_land_encounter then
            land_manager:delete_land_encounter_given_marker_id(current_spot_info) 
        end
	end,
	IS_PERSISTENT_LISTENER
)


--[[ Triggered when the event triggered by the marker is a dilemma. 
If it's a battle spot: Triggers a battle. Example: wh2_dlc11_cst_vampire_coast_encounters
If it's a smith spot: Several dilemmas exist. We send to the poi itself to trigger what it needs
If it's a tavern spot (TODO): Gives an option to recruit an unit at a low price if the cooldown has expired
If it's a resource spot (TODO): (Don't know yet but should be a fight for control of such resource: Permanent buffs like nagash books that the player and the AI should vie for as well as a zone around the marker if possible)

Context is: https://chadvandy.github.io/tw_modding_resources/WH3/scripting_doc.html#DilemmaChoiceMadeEvent

DilemmaChoiceMadeEvent
Function Name: choice_key
Interface: NONE
Description: Access the choice made for the dilemma in the event

Function Name: choice
Interface: NONE
Description: Index of the choice made for the dilemma in the event

Function Name: faction
Interface: FACTION_SCRIPT_INTERFACE
Description: Access the faction in the event

Function Name: campaign_model
Interface: MODEL_SCRIPT_INTERFACE
Description: Access the model in the event

Function Name: dilemma
Interface: NONE
Description: Access the key of the dilemma in the event
--]]
core:add_listener(
	"land_enc_battle_dilemma_choice",
	"DilemmaChoiceMadeEvent",
    function(dilemma_choice_and_faction_info)
        local dilemma = dilemma_choice_and_faction_info:dilemma()
        --Check all dilemmas starting with the POI dilemmas.
        -- battles dilemmas
        for i=1, #battle_events do
            for j=1, #battle_events[i] do
                if dilemma == battle_events[i][j].dilemma then
                    return true
                end
            end
        end
        return false
    end,
	function(dilemma_choice_and_faction_info)
        out("DEBUG - DilemmaChoiceMadeEvent dilemma: " .. dilemma_choice_and_faction_info:dilemma())
        out("DEBUG - DilemmaChoiceMadeEvent choice: " .. dilemma_choice_and_faction_info:choice())
        spot_event_manager:trigger_dilemma_event_given_choice(dilemma_choice_and_faction_info)
	end,
	IS_PERSISTENT_LISTENER
)


core:add_listener(
	"poi_battle_dilemma_choice",
	"DilemmaChoiceMadeEvent",
    function(dilemma_choice_and_faction_info)
        local dilemma = dilemma_choice_and_faction_info:dilemma()
        --Check all dilemmas starting with the POI dilemmas.
        -- smithy dilemmas
        for i=1, #smithy_events do
            if dilemma == smithy_events[i] then
                return true
            end
        end
        return false
    end,
	function(dilemma_choice_and_faction_info)
        if get_mct_settings().enable_randomized_encounter_force_generation then
            point_of_interest_event_manager:trigger_dilemma_event_given_choice(dilemma_choice_and_faction_info, current_spot_info)
        else
            point_of_interest_event_manager:trigger_dilemma_event_given_choice(dilemma_choice_and_faction_info, current_spot_info)
        end
	end,
	IS_PERSISTENT_LISTENER
)


--[[ STATE MANAGEMENT --]]
local FLATTENED_LAND_MANAGER_LAND_STATE = "flattened_land_encounters_land_manager_state"
local FLATTENED_POI_EVENT_STATE = "flattened_land_encounters_poi_event_manager_state"
local FLATTENED_SPOT_EVENT_STATE = "flattened_land_encounters_spot_event_manager_state"
local DEFAULT_FLATTENED_SPOTS_VALUE = {}
-- Saves the land_encounters state variables when the game is about to close
cm:add_saving_game_callback(
	function(context)
        cm:save_named_value(FLATTENED_LAND_MANAGER_LAND_STATE, land_manager:export_state_as_a_table(), context)
        cm:save_named_value(FLATTENED_POI_EVENT_STATE, point_of_interest_event_manager:export_state_as_table(), context)
        cm:save_named_value(FLATTENED_SPOT_EVENT_STATE, spot_event_manager:export_state_as_a_table(), context)
	end
)

-- Loads the land_encounters state variables when the game is 
cm:add_loading_game_callback(
	function(context)
        saved_land_encounters_state = cm:load_named_value(FLATTENED_LAND_MANAGER_LAND_STATE, DEFAULT_FLATTENED_SPOTS_VALUE, context)
        saved_poi_event_state = cm:load_named_value(FLATTENED_POI_EVENT_STATE, DEFAULT_FLATTENED_SPOTS_VALUE, context)
        saved_spot_event_state = cm:load_named_value(FLATTENED_SPOT_EVENT_STATE, DEFAULT_FLATTENED_SPOTS_VALUE, context)
	end
)


core:add_listener(
    "mct_initial_setup",
    "MctInitialized",
    true,
    function(context)
        out("DEBUG - mct_initial_setup")
        local mctMod = context:mct():get_mod_by_key("land_encounters_and_points_of_interest")
        if not mctMod then return end
        set_mct_settings(mctMod)

        -- -- Check which of the supported mods are loaded.
        -- local used_mods = io.open("used_mods.txt", "r")
        -- if used_mods then
        --     for line in used_mods:lines() do
        --         -- Extract the mod name from the line
        --         local mod_name = line:match('mod "(.-)%.pack"')
        --         if mod_name then
        --             -- Check if the mod is supported and loaded
        --             for _, supported_mod in ipairs(get_supported_mods()) do
        --                 if mod_name == supported_mod then
        --                     table.insert(get_mct_settings().enabled_mods, mod_name)
        --                 end
        --             end
        --         end
        --     end
        --     used_mods:close()
        -- end

        -- out("DEBUG - enabled_mods: " .. table.concat(get_mct_settings().enabled_mods, ", "))
    end,
    true
)


--[[ LINK TO OTHER MODS --]]
--[[
    TODO: MCT related logic. Uncomment when ready
--]]
--[[
core:add_listener(
	"land_encounter_mct_options",
	"MctInitialized",
	true,
	function(context)
		local mct = context:mct()
		local mct_mod = mct:get_mod_by_key("land_encounters")

		local encounter_start_option = mct_mod:get_option_by_key("encounter_start")
		local start_num = encounter_start_option:get_finalized_setting()

		encounter_start_option:set_uic_locked(true, "Can only change this option before starting a new campaign.")

		encounter_number_start = start_num
	end,
	true
)
--]]

-- FOR DEBUGGING PURPOSES ONLY
--core:add_listener(
--	"land_enc_and_poi_incident_occured_event",
--	"IncidentOccuredEvent",
--    function(context)
--        out("LEAPOI - land_enc_and_poi_incident_occured_event current incident=" .. context:dilemma() .. ", for faction=" .. context:faction():name())
--        return false
--    end,
--	function(context)
        --cm:force_winds_of_magic_change(province:key(), "wom_strength_4")
--	end,
--	IS_PERSISTENT_LISTENER
--)

-- FOR DEBUGGING PURPOSES ONLY
-- core:add_listener(
--     "land_enc_and_poi_faction_gained_ancillary",
--     "FactionGainedAncillary",
--     function(context)
--         out("LEAPOI - land_enc_and_poi_faction_gained_ancillary ancillary:" .. context:ancillary() .. " for faction:" .. context:faction():name())

--         return false
--     end,
--     function(context)
        -- Has to check if twice
--        context:faction():ancillary_exists(context:ancillary())
--    end,
--    IS_PERSISTENT_LISTENER
--)
