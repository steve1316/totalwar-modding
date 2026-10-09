--- Registers every core:add_listener used by the mod: FactionTurnStart, AreaEntered, the DilemmaChoiceMadeEvent listeners (registered
--- greyed-out choices, battle, smithy, treasure site, tower and Tavern), the dilemma panel's grey-out, and the MctInitialized hook. Manager
--- instances are populated by the entry point's pre_first_tick_callback.

require("script/land_encounters/utils/common")
require("script/land_encounters/core/mct")

local IS_PERSISTENT_LISTENER = true

local events = require("script/land_encounters/configs/events")
local battle_dilemma_keys = require("script/land_encounters/configs/battle_categories").dilemma_keys
local smithy_events = events.smithy
local dilemmas = require("script/land_encounters/core/dilemmas")
local spot_offers = require("script/land_encounters/features/spot_offers")
local effect_library = require("script/land_encounters/features/effect_library")
local boons = require("script/land_encounters/features/boons")
local tavern_contracts = require("script/land_encounters/features/tavern_contracts")
local smithy_commissions = require("script/land_encounters/features/smithy_commissions")

--- Tavern dilemma key -> true, for the Tavern choice listener.
local tavern_dilemma_keys = {}
for _, key in ipairs(events.tavern) do
    tavern_dilemma_keys[key] = true
end

--- Tower dilemma key -> true, for the tower choice listener.
local tower_dilemma_keys = {}
for _, key in ipairs(events.tower_spot) do
    tower_dilemma_keys[key] = true
end

local M = {}

--- Populated by the entry point's pre_first_tick_callback after the manager instances are created.
M.invasion_battle_manager = nil
M.land_manager = nil
M.point_of_interest_event_manager = nil
M.spot_event_manager = nil
M.current_spot_info = {}
--- Turn number of the last once-per-round update, so several human factions in one round tick encounters and smithies once. Not saved: a
--- load mid-round in multiplayer can tick that round once more.
M.last_round_update_turn = nil

--- Registers every persistent listener. Called once at module load by the entry point.
function M.register()
    --- Registered first, so every other choice listener reads the treasury with the chosen price already counted as spent.
    core:add_listener(
        "land_enc_dilemma_charges",
        "DilemmaChoiceMadeEvent",
        true,
        function(context) dilemmas.settle(context:faction():name(), context:dilemma(), context:choice_key()) end,
        IS_PERSISTENT_LISTENER
    )

    boons.register()

    --- Once per round (on the first human turn), expire stale encounters, refill them, and update POI states. Every human turn, check that
    --- faction's smithy sieges.
    core:add_listener(
        "land_enc_and_poi_faction_turn_start_update",
        "FactionTurnStart",
        function(context)
            return context:faction():is_human()
        end,
        function(context)
            local turn = cm:turn_number()
            if M.last_round_update_turn ~= turn then
                M.last_round_update_turn = turn
                M.land_manager:update_land_encounters()
                M.point_of_interest_event_manager:update_state_given_turn_passing()
            end
            M.point_of_interest_event_manager:on_faction_turn_start(context:faction():name())
            spot_offers.on_faction_turn_start(context:faction():name())
            effect_library.apply_test_bundles(context:faction())
            boons.on_faction_turn_start(context:faction():name())
        end,
        IS_PERSISTENT_LISTENER
    )


    --- AreaEntered: when a character enters a mod marker, route to the right spot/POI handler.
    --- See https://chadvandy.github.io/tw_modding_resources/WH3/scripting_doc.html#AreaEntered.
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
            if M.current_spot_info.spot_type == 0 then
                --- Event spot (random encounter).
                M.spot_event_manager:set_current_spot_info(M.current_spot_info)
                can_delete_land_encounter = M.spot_event_manager:trigger_spot_event(area_and_character_info)
            elseif M.current_spot_info.spot_type == 1 then
                --- Smithy spot.
                M.point_of_interest_event_manager:trigger_poi_event("SmithySpot", area_and_character_info, M.current_spot_info)
            elseif M.current_spot_info.spot_type == 2 then
                --- Tower.
                M.point_of_interest_event_manager:trigger_poi_event("TowerSpot", area_and_character_info, M.current_spot_info)
            elseif M.current_spot_info.spot_type == 3 then
                --- Tavern.
                M.point_of_interest_event_manager:trigger_poi_event("TavernSpot", area_and_character_info, M.current_spot_info)
            end

            if can_delete_land_encounter then
                M.land_manager:delete_land_encounter_given_marker_id(M.current_spot_info)
            end
        end,
        IS_PERSISTENT_LISTENER
    )


    --- Battle-spot dilemma choice. Fires when the player picks an option on a battle-spot dilemma,
    --- e.g. wh2_dlc11_cst_vampire_coast_encounters. Context fields (dilemma, choice, faction, etc.)
    --- are documented at https://chadvandy.github.io/tw_modding_resources/WH3/scripting_doc.html#DilemmaChoiceMadeEvent.
    core:add_listener(
        "land_enc_battle_dilemma_choice",
        "DilemmaChoiceMadeEvent",
        function(dilemma_choice_and_faction_info)
            local dilemma = dilemma_choice_and_faction_info:dilemma()
            --- Match against any registered battle-spot dilemma.
            return battle_dilemma_keys[dilemma] == true
        end,
        function(dilemma_choice_and_faction_info)
            out("DEBUG - DilemmaChoiceMadeEvent dilemma: " .. dilemma_choice_and_faction_info:dilemma())
            out("DEBUG - DilemmaChoiceMadeEvent choice: " .. dilemma_choice_and_faction_info:choice())
            M.spot_event_manager:trigger_dilemma_event_given_choice(dilemma_choice_and_faction_info)
        end,
        IS_PERSISTENT_LISTENER
    )


    --- POI (smithy) dilemma choice.
    core:add_listener(
        "poi_battle_dilemma_choice",
        "DilemmaChoiceMadeEvent",
        function(dilemma_choice_and_faction_info)
            local dilemma = dilemma_choice_and_faction_info:dilemma()
            --- Match against any registered smithy dilemma.
            for i=1, #smithy_events do
                if dilemma == smithy_events[i] then
                    return true
                end
            end
            return false
        end,
        function(dilemma_choice_and_faction_info)
            M.point_of_interest_event_manager:trigger_dilemma_event_given_choice(dilemma_choice_and_faction_info)
        end,
        IS_PERSISTENT_LISTENER
    )


    --- Treasure site dilemma choice (an offer or Walk away).
    core:add_listener(
        "land_enc_site_dilemma_choice",
        "DilemmaChoiceMadeEvent",
        function(dilemma_choice_and_faction_info)
            return spot_offers.is_site_dilemma(dilemma_choice_and_faction_info:dilemma())
        end,
        function(dilemma_choice_and_faction_info)
            spot_offers.take(dilemma_choice_and_faction_info:faction():name(), dilemma_choice_and_faction_info:choice_key())
        end,
        IS_PERSISTENT_LISTENER
    )


    --- Tower dilemma choice (enter, go deeper or leave).
    core:add_listener(
        "land_enc_tower_dilemma_choice",
        "DilemmaChoiceMadeEvent",
        function(dilemma_choice_and_faction_info)
            return tower_dilemma_keys[dilemma_choice_and_faction_info:dilemma()] == true
        end,
        function(dilemma_choice_and_faction_info)
            M.point_of_interest_event_manager:trigger_tower_dilemma_event_given_choice(dilemma_choice_and_faction_info)
        end,
        IS_PERSISTENT_LISTENER
    )


    --- Tavern dilemma choice (the hub or the capture dilemma).
    core:add_listener(
        "land_enc_tavern_dilemma_choice",
        "DilemmaChoiceMadeEvent",
        function(dilemma_choice_and_faction_info)
            return tavern_dilemma_keys[dilemma_choice_and_faction_info:dilemma()] == true
        end,
        function(dilemma_choice_and_faction_info)
            M.point_of_interest_event_manager:trigger_tavern_dilemma_event_given_choice(dilemma_choice_and_faction_info)
        end,
        IS_PERSISTENT_LISTENER
    )


    --- The features that issue missions and place marked spots: Tavern contracts settle when their missions succeed, fail or are dropped
    --- from the missions panel, and Smith's Commissions are forgotten so the faction can be offered another. A lord walking onto either's
    --- mark starts its battle. CA's marker manager fires the mark's event with the lord and the marker.
    local mission_features = {
        { name = "tavern_contract", owns = tavern_contracts.is_contract_mission, mark_event = tavern_contracts.MARK_ENTERED_EVENT,
            ended = function(...) M.point_of_interest_event_manager:on_tavern_contract_ended(...) end,
            entered = function(...) M.point_of_interest_event_manager:on_tavern_mark_entered(...) end },
        { name = "smithy_commission", owns = smithy_commissions.is_commission, mark_event = smithy_commissions.MARK_ENTERED_EVENT,
            ended = function(...) M.point_of_interest_event_manager:on_smithy_commission_ended(...) end,
            entered = function(...) M.point_of_interest_event_manager:on_smithy_mark_entered(...) end },
    }
    for _, feature in ipairs(mission_features) do
        for event, outcome in pairs({ MissionSucceeded = "succeeded", MissionFailed = "failed", MissionCancelled = "cancelled" }) do
            core:add_listener(
                "land_enc_" .. feature.name .. "_" .. outcome,
                event,
                function(context) return feature.owns(context:mission():mission_record_key()) end,
                function(context) feature.ended(context:faction():name(), context:mission():mission_record_key(), outcome) end,
                IS_PERSISTENT_LISTENER
            )
        end
        core:add_listener(
            "land_enc_" .. feature.name .. "_mark_entered",
            feature.mark_event,
            true,
            function(context) feature.entered(context:character(), context.stored_table.marker_ref, context.stored_table.instance_ref) end,
            IS_PERSISTENT_LISTENER
        )
    end


    --- The choices each open dilemma registered as closed when it was launched (taken tower offers, Tavern and forge choices that cannot be
    --- taken, site or battle offers the treasury cannot pay) get greyed-out buttons once the dilemma panel has built them. The panel is the
    --- local player's, so this UI-only step reads the local faction.
    core:add_listener(
        "land_enc_grey_out_closed_choices",
        "PanelOpenedCampaign",
        function(context) return context.string == "events" end,
        function()
            cm:callback(function()
                dilemmas.grey_out_open(cm:get_local_faction_name(true))
                dilemmas.cap_choices()
            end, 0.1)
        end,
        IS_PERSISTENT_LISTENER
    )

    --- Puts a scrolled dilemma's choice grid back when the events panel closes, so the next dilemma lays out as the game made it.
    core:add_listener(
        "land_enc_release_dilemma_scroll",
        "PanelClosedCampaign",
        function(context) return context.string == "events" end,
        function() dilemmas.release_scroll() end,
        IS_PERSISTENT_LISTENER
    )


    --- MCT initial setup. Caches the live MCT option values into the mod's settings table.
    core:add_listener(
        "mct_initial_setup",
        "MctInitialized",
        true,
        function(context)
            out("DEBUG - mct_initial_setup")
            local mctMod = context:mct():get_mod_by_key("land_encounters_and_points_of_interest")
            if not mctMod then return end
            set_mct_settings(mctMod)
        end,
        true
    )
end

return M
