require("script/land_encounters/utils/common")
require("script/land_encounters/core/mct")

local IS_PERSISTENT_LISTENER = true

local events = require("script/land_encounters/configs/events")
local battle_events = events.battle_spot
local smithy_events = events.smithy

local M = {}

-- Populated by the entry point's pre_first_tick_callback after the manager instances are created.
M.invasion_battle_manager = nil
M.land_manager = nil
M.point_of_interest_event_manager = nil
M.spot_event_manager = nil
M.current_spot_info = {}

function M.register()
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
            M.land_manager:update_land_encounters()
            M.point_of_interest_event_manager:update_state_given_turn_passing()
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
            return M.land_manager:check_if_is_triggerable_marker(triggering_character, marker_id)
        end,
        function(area_and_character_info)
            local marker_id = area_and_character_info:area_key()
            M.current_spot_info = M.land_manager:find_triggering_spot_info(marker_id)
            local can_delete_land_encounter = false
            if M.current_spot_info.spot_type == 0 then -- event_spot
                M.spot_event_manager:set_current_spot_info(M.current_spot_info)
                can_delete_land_encounter = M.spot_event_manager:trigger_spot_event(area_and_character_info, cm:turn_number())
            elseif M.current_spot_info.spot_type == 1 then -- smithy spot type
                M.point_of_interest_event_manager:trigger_poi_event("SmithySpot", area_and_character_info, M.current_spot_info)
            end

            if can_delete_land_encounter then
                M.land_manager:delete_land_encounter_given_marker_id(M.current_spot_info)
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
            M.spot_event_manager:trigger_dilemma_event_given_choice(dilemma_choice_and_faction_info)
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
            M.point_of_interest_event_manager:trigger_dilemma_event_given_choice(dilemma_choice_and_faction_info, M.current_spot_info)
        end,
        IS_PERSISTENT_LISTENER
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
    -- )
end

return M
