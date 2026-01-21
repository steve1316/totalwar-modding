require("script/land_encounters/utils/logger")
require("script/land_encounters/constants/utils/common")
require("script/land_encounters/controllers/incident_manager")

local complex_continuity_events = require("script/land_encounters/constants/events/complex_continuity_events")
local elligible_items = require("script/land_encounters/constants/items/balancing_items")

local BattleGenerator = require("script/land_encounters/generators/battle_generator")

local Army = require("script/land_encounters/models/battle/army")

-------------------------
--- Properties definition
-------------------------
local BattleEventDelegate = {
    -- Delegates
    invasion_battle_manager = {},

    -- Generators
    battle_generator = {},

    -- Cached variables during event
    cached_player_character = {},
    cached_event = {},
    is_triggered = false
}

local EVENT_IMAGE_ID_LOCATION_OF_INTEREST = 1017
local FIRST_OPTION = 0
local ERROR_BATTLE_CLEAN_UP_EVENT = { 
    incident = "land_enc_incident_battle_clean_up_event",
    targets = { 
        character = true, 
        force = false, 
        faction = false, 
        region = false
    }
}

function BattleEventDelegate:get_cached_player_character()
    return self.cached_player_character
end

function BattleEventDelegate:trigger_pre_battle_dilemma(area_and_character_info, spot_info, turn_number)
    self.cached_player_character = area_and_character_info:family_member():character()
    local triggering_faction = self.cached_player_character:faction()
    local triggering_faction_name = triggering_faction:name()
    
    if is_human_and_it_is_its_turn(triggering_faction) and self:character_is_general_and_can_trigger_dilemma(self.cached_player_character) then
        self.cached_event = self.battle_generator:get_randomized_event_given_turn_number(turn_number)
        cm:trigger_dilemma(triggering_faction_name, self.cached_event.dilemma)
        return true
    -- Event is triggered by the AI
    elseif not triggering_faction:is_human() then
        local trigger_event_feed = false
        if math.random() < 0.10 then
            cm:add_ancillary_to_faction(triggering_faction, elligible_items[random_number(#elligible_items)], trigger_event_feed)
        end
        cm:treasury_mod(triggering_faction_name, 500)
        return true
    else 
    -- Event can't be triggered by human
        cm:show_message_event_located(triggering_faction_name,
        "event_feed_strings_text_title_event_land_enc_and_poi_encountered",
        "event_feed_strings_text_subtitle_event_land_enc_and_poi_encountered",
        "event_feed_strings_text_description_event_land_enc_and_poi_encountered",
            spot_info.coordinates[1], 
            spot_info.coordinates[2],
            false,
            EVENT_IMAGE_ID_LOCATION_OF_INTEREST
        )
        return false
    end
end

---------------------------
-- DILEMMAS
---------------------------
function BattleEventDelegate:trigger_dilemma_event_given_choice(dilemma_choice_and_faction_info, spot_info)
    local choice = dilemma_choice_and_faction_info:choice()
    if choice == FIRST_OPTION then
        out("DEBUG - trigger_dilemma_event_given_choice dilemma: " .. dilemma_choice_and_faction_info:dilemma())
        out("DEBUG - trigger_dilemma_event_given_choice choice: " .. dilemma_choice_and_faction_info:choice())
        -- we check that the army will be able to spawn and fight
        local offensive_army = self:get_offensive_army()
        out("DEBUG - offensive_army generated")
        if self.invasion_battle_manager:can_generate_battle(offensive_army, spot_info.coordinates) then
            self.is_triggered = true

            self.invasion_battle_manager:generate_battle(offensive_army, self.cached_player_character, spot_info.coordinates)
            self.invasion_battle_manager:mark_battle_forces_for_removal(offensive_army)
            self.invasion_battle_manager:reset_state_post_battle(self, "BattleSpot", spot_info, offensive_army)
        -- we trigger the default removal incident
        else
            self:trigger_battle_removal_incident(spot_info)
        end
    else
        self:trigger_battle_avoidance_incident(spot_info)
    end
end


function BattleEventDelegate:trigger_battle_removal_incident(spot_info)
    trigger_incident(ERROR_BATTLE_CLEAN_UP_EVENT.incident, ERROR_BATTLE_CLEAN_UP_EVENT.targets, spot_info, self.cached_player_character)
end


function BattleEventDelegate:trigger_battle_avoidance_incident(spot_info)
    trigger_incident(self.cached_event.avoidance_incident, self.cached_event.avoidance_targets, spot_info, self.cached_player_character)
end

---trigger_event_given_battle_result(spot_type, spot_index, player_won_battle)
--- @desc Triggered from the InvasionBattleManager 
--- @param player_won_battle boolean if the player won the battle or not
function BattleEventDelegate:trigger_event_given_battle_result(player_won_battle, spot_info)
    if player_won_battle then
        self:trigger_victory_incident(spot_info)
    end
    self.is_triggered = false
end


function BattleEventDelegate:trigger_victory_incident(spot_info)
    -- due to the continuity we have to guarantee that the cached player is always previously retrieved 
    if self.cached_player_character == nil or (type(self.cached_player_character) == "table" and next(self.cached_player_character) == nil) then
        self.cached_player_character = get_player_faction_character_closest_to_spot(spot_info)
    end

    trigger_incident(self.cached_event.victory_incident, self.cached_event.victory_targets, spot_info, self.cached_player_character)
    -- complex events trigger a balancing act
    local continuity = self:check_if_incident_has_continuity(self.cached_event.victory_incident, self.cached_player_character:faction())
    if continuity ~= nil then
        trigger_incident(continuity.incident, continuity.targets, spot_info, self.cached_player_character)
        if continuity.balance ~= false then
            self:trigger_incident_for_ai_due_to_balance(continuity.balance, self.cached_player_character:faction())
        end
    end
end

------------------------------------------------
--- COMMON
------------------------------------------------
function BattleEventDelegate:character_is_general_and_can_trigger_dilemma(character)
    if cm:char_is_general_with_army(character) then
        local active_stance = character:military_force():active_stance()
        return (active_stance == "MILITARY_FORCE_ACTIVE_STANCE_TYPE_DEFAULT") or (active_stance == "MILITARY_FORCE_ACTIVE_STANCE_TYPE_CHANNELING") or (active_stance == "MILITARY_FORCE_ACTIVE_STANCE_TYPE_AMBUSH")
    else
        return false
    end
end

------------------------------------------------
--- BALANCE FOR AI
------------------------------------------------

function BattleEventDelegate:check_if_incident_has_continuity(incident_key, faction)
    local continuity_incident_logic = complex_continuity_events[incident_key]
    if continuity_incident_logic ~= nil then 
        for i=1, #continuity_incident_logic do
            if self:check_if_conditions_of_option_are_fulfilled(faction, continuity_incident_logic[i].conditions) then
                return continuity_incident_logic[i].result
            end
        end
    end
    return nil
end


function BattleEventDelegate:check_if_conditions_of_option_are_fulfilled(faction, conditions)
    local conditions_are_met = true
    for condition_key, variable in pairs(conditions) do
        if condition_key == "does_not_have_ancillary" then
            conditions_are_met = not faction:ancillary_exists(variable)
        -- elseif condition_key == "" then
        end
    end
    return conditions_are_met
end

local function compare_imperium_levels(a,b)
    return a[1] > b[1]
end

function BattleEventDelegate:trigger_incident_for_ai_due_to_balance(balance, player_faction)
    for condition_key, logical_variable in pairs(balance) do
        if condition_key == "give_ancillary" then
            if logical_variable.faction == "random" then
                local factions_at_war_with = player_faction:factions_at_war_with()
                if factions_at_war_with:num_items() < 5 then
                    self.add_ancillary_to_feuding_factions(factions_at_war_with, 5 - factions_at_war_with:num_items(), logical_variable.ancillary)

                    local possible_future_enemy_factions = {}
                    local factions_met = player_faction:factions_met()
                    for i = 0, factions_met:num_items() - 1 do
                        local met_faction = factions_at_war_with:item_at(i)
                        local relations = met_faction:diplomatic_attitude_towards(player_faction:name())
                        if(relations < -100) then
                            possible_future_enemy_factions[i] = { met_faction:imperium_level(), met_faction }                             
                        end
                        table.sort(possible_future_enemy_factions, compare_imperium_levels)
                    end
                    local number_of_blessed_possible_future_enemies = math.min(5 - factions_at_war_with:num_items(), #possible_future_enemy_factions)
                    for i=1, number_of_blessed_possible_future_enemies do
                        cm:add_ancillary_to_faction(possible_future_enemy_factions[i][2], logical_variable.ancillary, false) 
                    end
                else
                    self.add_ancillary_to_feuding_factions(factions_at_war_with, 5, logical_variable.ancillary)
                end
            end
        end
    end
end

function BattleEventDelegate:add_ancillary_to_feuding_factions(feuding_factions, number_of_factions, ancillary)
    -- get most powerful enemies
    local feuding_factions_by_imperium_level = {}
    for i = 0, feuding_factions:num_items() - 1 do
        local known_enemy_faction = feuding_factions:item_at(i)
        feuding_factions_by_imperium_level[i] = { known_enemy_faction:imperium_level(), known_enemy_faction } 
        table.sort(feuding_factions_by_imperium_level, compare_imperium_levels)
    end
    -- and bless them
    for i=1, number_of_factions do
        cm:add_ancillary_to_faction(feuding_factions_by_imperium_level[i][2], ancillary, false) 
    end
end

function BattleEventDelegate:get_offensive_army()
    out("DEBUG - get_offensive_army Beginning process to generate the encounter force.")
    -- self.cached_player_character:military_force():command_queue_index()
    return Army:new_from_event(self.cached_event.dilemma)
end


-------------------------
--- Memory management
-------------------------

function BattleEventDelegate:export_state_as_a_table(spot_info)
    local current_battle_delegate_state = {}
    current_battle_delegate_state["battle_generator"] = self.battle_generator:export_state_as_a_table()
    if self.is_triggered then
        current_battle_delegate_state["battle_event_delegate_is_triggered"] = true
        current_battle_delegate_state["battle_event_delegate_cached_event"] = self.cached_event
        current_battle_delegate_state["battle_event_delegate_spot_info"] = spot_info
    end
    return current_battle_delegate_state
end


function BattleEventDelegate:reinstate_event_if_able(previous_state)
    self.battle_generator:reinstate_if_able(previous_state["battle_generator"])
    -- check that event is triggered
    self.is_triggered = previous_state["battle_event_delegate_is_triggered"]
    if self.is_triggered ~= nil and self.is_triggered == true then
        self.cached_event = previous_state["battle_event_delegate_cached_event"]
        local spot_info = previous_state["battle_event_delegate_spot_info"]

        local offensive_army = self:get_offensive_army()
        self.invasion_battle_manager:set_auxiliary_army_for_reset(offensive_army)
        self.invasion_battle_manager:mark_battle_forces_for_removal(offensive_army)
        self.invasion_battle_manager:reset_state_post_battle(self, "BattleSpot", spot_info, offensive_army)
    end
end

-------------------------
--- Constructors
-------------------------
function BattleEventDelegate:new(invasion_battle_manager)
    local t = { 
        invasion_battle_manager = invasion_battle_manager, 
        battle_generator = BattleGenerator:new() 
    }
    setmetatable(t, self)
    self.__index = self
    return t
end

return BattleEventDelegate