--[[ Specification
V1.0 in 1.3
For the player:
The player has to visit it at least once every 3 turns to unlock it for the turn it visits it
- Should be upgradeable by giving it money (Up to three times selling greys in the first tier, green, blue etc...)
- If an enemy faction crosses through it given the level it will trigger a defensive battle.

For the AI:
- Gives a random ancillary every 5 turns if under control of the AI

V1.1 in 2.X
- Region aware. Region AI owner auto attacks the smithy if owned by the player.
- Quest given by the smithy itself. Should give legendary items or blue sets if they are completed in time.
]]--
local elligible_items = require("script/land_encounters/constants/items/balancing_items")

require("script/land_encounters/utils/logger")
require("script/land_encounters/controllers/incident_manager")

local smithy_missions_by_subculture = require("script/land_encounters/constants/missions/smithy_missions_by_subculture")
local special_items_by_subculture = require("script/land_encounters/constants/items/item_sets_or_special_items_by_subculture")

local Army = require("script/land_encounters/models/battle/army")

------------------------------------------------
--- Constant values of the class [DO NOT CHANGE]
------------------------------------------------
local FIRST_OPTION = 0
local SECOND_OPTION = 1

local EVENT_IMAGE_ID_LOCATION_OF_INTEREST = 1017

-- Heavily reused events
local EVENT_RECLAMATION = "land_enc_dilemma_smithy_reclamation" 
local EVENT_DEFENSE = "land_enc_dilemma_smithy_defense" 
local EVENT_VISIT_BY_LEVEL = {
    "land_enc_dilemma_smithy_visit_level_1", 
    "land_enc_dilemma_smithy_visit_level_2",
    "land_enc_dilemma_smithy_visit_level_3"
}
local EVENT_VISIT_TARGETS = { character = true, force = true, faction = false, region = false }
local TRIBUTE_INCIDENT_EVENT = "land_enc_incident_smithy_tribute"


-------------------------
--- Properties definition
-------------------------
local SmithyState = {
    -- Marker id that identifies if this smithy should change its state
    zone_name = "",
    index_in_zone = "",
    coordinates = {},
    -- smithy defense (from player or AI) variables
    is_defense_triggered = false,    
    is_reclamation_triggered = false,
        
    visiting_enemy_character = false,
    -- in case the player does not finish the battle in the same game session we save its faction to find him later                
    visiting_enemy_faction_name = false,
        
    level = 1,
    controlling_faction_name = "",
    controlling_faction_subculture = "",
    turns_under_control = 0,
    visit_cooldown = 0
}

-------------------------
--- Turn passing
-------------------------
function SmithyState:update_state_given_turn_passing(mission_manager)
    local controlling_faction = self:check_if_owner_is_alive_and_return_faction()
    if controlling_faction ~= nil and self:is_occupied() then
        self:reward_owner_faction(controlling_faction)
        self:update_visit_cooldown(controlling_faction:name())
        self:issue_mission_if_possible(controlling_faction, mission_manager)
        self.turns_under_control = self.turns_under_control + 1
    else
        self:try_to_automatically_occupy_smithy_by_region_ownership_when_abandoned()
    end
end

function SmithyState:reward_owner_faction(controlling_faction)
    local turns_till_reward = 9999
    if self:is_occupied_by_player() then
        -- if the smith is under player control, give an ancillary every [ancillary_reward_turn] configurable through MCT and the smithing level
        turns_till_reward = self.turns_under_control % self:reward_turn_given_level()
    elseif self:is_occupied() then
        -- if the smith is under AI control. Every 4 levels give an ancillary to their faction (flat)
        turns_till_reward = self.turns_under_control % 4
    end
    if turns_till_reward == 0 then
        -- if its an ai filter the event
        local representative_character = cm:get_highest_ranked_general_for_faction(controlling_faction)
        -- Guarantees that an ancillary is given to the faction and no crashing occurss
        if representative_character ~= false then
            trigger_incident(TRIBUTE_INCIDENT_EVENT, EVENT_VISIT_TARGETS, self:get_spot_info(), representative_character)
        else
            cm:add_ancillary_to_faction(controlling_faction, elligible_items[random_number(#elligible_items)], false)
        end
    end
end

function SmithyState:reward_turn_given_level()
    return (4 - self.level) * 5 -- [ancillary_reward_turn]
end

function SmithyState:update_visit_cooldown(controlling_faction)
    if self:is_occupied_by_player() and self.visit_cooldown > 0 then
        self.visit_cooldown = self.visit_cooldown - 1
        -- you can visit now
        if self.visit_cooldown == 0 then
            cm:show_message_event_located(controlling_faction,
                "event_feed_strings_text_title_event_land_enc_smithy_visit_available",
                "event_feed_strings_text_subtitle_event_land_enc_smithy_visit_available",
                "event_feed_strings_text_description_event_land_enc_smithy_visit_available",
                self.coordinates[1],
                self.coordinates[2],
                false,
                EVENT_IMAGE_ID_LOCATION_OF_INTEREST
            )
        end
    end
end

function SmithyState:issue_mission_if_possible(controlling_faction, mission_manager)
    -- if is occupied by player and the smithy has been under control for 20 turns
    if self:is_occupied_by_player() and self.turns_under_control % 30 == 0 then
        -- issue a subculture mission for the player so that they can win an ancillary by completing a mission
        local subculture_missions = smithy_missions_by_subculture[self.controlling_faction_subculture]
        if not (subculture_missions == nil) and #subculture_missions > 0 then
            local smithy_mission = subculture_missions[random_number(#subculture_missions)]
            local mm = mission_manager:new(controlling_faction:name(), smithy_mission.mission)
            mm:set_mission_issuer("CLAN_ELDERS")
            mm:add_new_objective("KILL_X_ENTITIES")
            mm:add_condition("total 7500")
            mm:set_turn_limit(15)
            mm:set_should_whitelist(false)
            for i = 1, #smithy_mission.ancillaries do
                mm:add_payload("add_ancillary_to_faction_pool{ancillary_key ".. smithy_mission.ancillaries[i] ..";}")
            end
            mm:trigger()
        end
    elseif not self:is_occupied_by_player() and self:is_occupied() and self.turns_under_control % 12 == 0 then
        -- give a set or a special subculture item directly to the ai
        local subculture_items = special_items_by_subculture[self.controlling_faction_subculture]
        if not (subculture_items == nil) and #subculture_items > 0 then
            local set_or_special_ancillaries = subculture_items[random_number(#subculture_items)]
            local trigger_event_feed = false
            for i=1, #set_or_special_ancillaries do
                cm:add_ancillary_to_faction(controlling_faction, set_or_special_ancillaries[i], trigger_event_feed)
            end
        end
    end
end

function SmithyState:try_to_automatically_occupy_smithy_by_region_ownership_when_abandoned()
    local region_data = cm:get_region_data_at_position(self.coordinates[1], self.coordinates[2])
    if region_data and not region_data:is_null_interface() and region_data:region() ~= nil then
        local new_owner_by_region_occupation = region_data:region():owning_faction()
        if not new_owner_by_region_occupation:is_null_interface() then
            -- Auto occupy the smithy using the owner's name
            self:set_controlling_faction(new_owner_by_region_occupation)
        end
    end
end

-------------------------
--- On event happening
-------------------------

--- @param area_and_character_info table: interactable marker context
--- @param invasion_battle_manager table: The manager to trigger invasions like offensive and defensive battles 
function SmithyState:trigger_event(area_and_character_info, invasion_battle_manager)
    local visiting_character = area_and_character_info:family_member():character()
    local visiting_faction = visiting_character:faction()
        
    -- is human
    if is_human_and_it_is_its_turn(visiting_faction) then
        -- and is occupied by said human
        if self:is_occupied_by_same_faction(visiting_faction:name()) then
            -- the master blacksmith can't receive you
            if self:is_on_cooldown() then
                cm:show_message_event_located(visiting_faction:name(),
                    "event_feed_strings_text_title_event_land_enc_smithy_visit_on_cooldown",
                    "event_feed_strings_text_subtitle_event_land_enc_smithy_visit_on_cooldown",
                    "event_feed_strings_text_description_event_land_enc_smithy_visit_on_cooldown",
                    self.coordinates[1],
                    self.coordinates[2],
                    false,
                    EVENT_IMAGE_ID_LOCATION_OF_INTEREST
                )
            else
            -- he can receive you
                cm:trigger_dilemma(visiting_faction:name(), EVENT_VISIT_BY_LEVEL[self.level])
            end
        else
        -- if it's not occupied by the player
            if not self:is_occupied() then
            -- and its not ocuppied by anyone
                cm:show_message_event_located(visiting_faction:name(),
                    "event_feed_strings_text_title_event_land_enc_smithy_default_occupation",
                    "event_feed_strings_text_subtitle_event_land_enc_smithy_default_occupation",
                    "event_feed_strings_text_description_event_land_enc_smithy_default_occupation",
                    self.coordinates[1],
                    self.coordinates[2],
                    false,
                    EVENT_IMAGE_ID_LOCATION_OF_INTEREST
                )
                self:change_owner_through_occupation(visiting_faction:name())
            elseif self:is_faction_at_war_with_owner(visiting_faction) then
            -- and its occupied by an enemy
                -- Character is in accepted stance and can trigger the event
                if self:character_is_general_and_can_trigger_dilemma(visiting_character) then
                    -- then we can avoid it or battle for it
                    self.visiting_enemy_character = visiting_character
                    self.visiting_enemy_faction_name = visiting_faction:name()
                    cm:trigger_dilemma(visiting_faction:name(), EVENT_RECLAMATION) 
                else
                    cm:show_message_event_located(visiting_faction:name(),
                        "event_feed_strings_text_title_event_land_enc_smithy_encountered",
                        "event_feed_strings_text_subtitle_event_land_enc_smithy_encountered",
                        "event_feed_strings_text_description_event_land_enc_smithy_encountered",
                        self.coordinates[1],
                        self.coordinates[2],
                        false,
                        EVENT_IMAGE_ID_LOCATION_OF_INTEREST
                    )
                end
            else
            -- and its occupied by an ally or a neutral faction so we tell the player they need to be at war or have this faction dissapear to take the smithy
                cm:show_message_event_located(visiting_faction:name(),
                    "event_feed_strings_text_title_event_land_enc_smithy_ally_or_neutrally_controlled",
                    "event_feed_strings_text_subtitle_event_land_enc_smithy_ally_or_neutrally_controlled",
                    "event_feed_strings_text_description_event_land_enc_smithy_ally_or_neutrally_controlled",
                    self.coordinates[1],
                    self.coordinates[2],
                    false,
                    EVENT_IMAGE_ID_LOCATION_OF_INTEREST
                )
            end
        end
    elseif not self:is_prohibited_subculture(visiting_faction) and self:is_faction_at_war_with_owner(visiting_faction) then 
    -- is not an AI faction that has too random armies and is an AI enemy faction so the faction attacks the point
        if self:is_occupied_by_player() then
            -- the smithy is attacked, triger related event
            self.visiting_enemy_character = visiting_character
            self.visiting_enemy_faction_name = visiting_faction:name()
            -- given that the player cannot answer dilemmas during AI turn we autotrigger the defense
            self.is_defense_triggered = true
            self:trigger_forced_interception_defense(invasion_battle_manager)
        else
            -- the smithy changes hands randomly automatically to the enemy faction
            if random_number(100) >= 75 then
                local is_player = false
                self:change_owner_through_conquest(visiting_faction:name(), is_player, visiting_character)
            end
        end
    end    
end

function SmithyState:change_owner_through_occupation(faction)
    self:set_controlling_faction(faction)
end

function SmithyState:change_owner_through_conquest(faction, is_player, representative_character)
    self:set_controlling_faction(faction)
    
    if is_player then
        trigger_incident(EVENT_RECLAMATION, EVENT_VISIT_TARGETS, self:get_spot_info(), representative_character)
    end
end

function SmithyState:trigger_dilemma_event_given_choice(dilemma_choice_and_faction_info, invasion_battle_manager)
    local choice = dilemma_choice_and_faction_info:choice()
    local dilemma = dilemma_choice_and_faction_info:dilemma()
        
    if (dilemma == EVENT_VISIT_BY_LEVEL[1] or dilemma == EVENT_VISIT_BY_LEVEL[2]) and choice == FIRST_OPTION then
        self.level = self.level + 1
        self.visit_cooldown = 3
        cm:show_message_event_located(
            self.controlling_faction_name,
            "event_feed_strings_text_title_event_land_enc_smithy_levelled_up",
            "event_feed_strings_text_subtitle_event_land_enc_smithy_levelled_up",
            "event_feed_strings_text_description_event_land_enc_smithy_levelled_up",
            self.coordinates[1],
            self.coordinates[2],
            false,
            EVENT_IMAGE_ID_LOCATION_OF_INTEREST
        )
    elseif dilemma == EVENT_VISIT_BY_LEVEL[1] or dilemma == EVENT_VISIT_BY_LEVEL[2] or dilemma == EVENT_VISIT_BY_LEVEL[3] then 
        self.visit_cooldown = 10
    end

    
    if dilemma == EVENT_RECLAMATION and choice == FIRST_OPTION then
        -- If the AI controls the point. The point will be heavily defended. Only the player has to level it up correctly as the player benefits more from it
        -- up in the other logic
        self.is_reclamation_triggered = true
        self:trigger_reclamation_battle(invasion_battle_manager)
    -- when the smithy is controlled by an enemy faction
    elseif dilemma == EVENT_DEFENSE and choice == FIRST_OPTION then
        -- If the AI controls the point. The point will be heavily defended. Only the player has to level it up correctly as the player benefits more from it
        -- up in the other logic
        self.is_defense_triggered = true
        self:trigger_forced_interception_defense(invasion_battle_manager)
    elseif dilemma == EVENT_DEFENSE and choice == SECOND_OPTION then
        self:trigger_unconditional_surrender_incident()
        
        cm:show_message_event_located(self.controlling_faction_name,
            "event_feed_strings_text_title_event_land_enc_smithy_unconditional_surrender",
            "event_feed_strings_text_subtitle_event_land_enc_smithy_unconditional_surrender",
            "event_feed_strings_text_description_event_land_enc_smithy_unconditional_surrender",
            self.coordinates[1],
            self.coordinates[2],
            false,
            EVENT_IMAGE_ID_LOCATION_OF_INTEREST
        )
    end
end

function SmithyState:trigger_event_given_battle_result(player_won_battle)
    if player_won_battle then
        self:trigger_victory_event_given_battle_type()
    else
        self:trigger_defeat_event_given_battle_type()
    end
end

function SmithyState:trigger_reclamation_battle(invasion_battle_manager)
    local offensive_army = self:get_defensive_army()

    if not self.visiting_enemy_character then
        self.visiting_enemy_character = cm:get_closest_character_to_position_from_faction(self.visiting_enemy_faction_name, self.coordinates[1], self.coordinates[2], true, false, false)
    end

    if invasion_battle_manager:can_generate_battle(offensive_army, self.coordinates) then    
        invasion_battle_manager:generate_battle(offensive_army, self.visiting_enemy_character, self.coordinates)
        invasion_battle_manager:mark_battle_forces_for_removal(offensive_army)
        invasion_battle_manager:reset_state_post_battle(self, "SmithySpot", nil, offensive_army)
    else
        self:trigger_successful_reclamation()
        self:reset_defense_flags()
    end
end

function SmithyState:trigger_forced_interception_defense(invasion_battle_manager)
    local defender_army = self:get_defensive_army()
    -- Given that people tend to install mods that break the smithies (like having custom factions and the like)
    -- we need to check that an army is created. If not we simply delete the flags and ignore the activation.
    if next(defender_army) == nil then
        self:reset_defense_flags()
        return
    end

    if not self.visiting_enemy_character then
        self.visiting_enemy_character = cm:get_closest_character_to_position_from_faction(self.visiting_enemy_faction_name, self.coordinates[1], self.coordinates[2], true, false, false)
    end
    
    invasion_battle_manager:generate_defense_battle(defender_army, self.visiting_enemy_character, self.coordinates)
    invasion_battle_manager:mark_battle_forces_for_removal(defender_army)
    invasion_battle_manager:reset_state_post_battle(self, "SmithySpot", nil, defender_army)
end

function SmithyState:trigger_victory_event_given_battle_type()
    -- the player is reclaiming the smithy and won
    if self.is_reclamation_triggered then
        self:trigger_successful_reclamation()
    -- the player defends its smithy and won
    elseif self.is_defense_triggered then
        self:trigger_successful_defense()
    end
    self:reset_defense_flags()
end

function SmithyState:trigger_defeat_event_given_battle_type()
    if self.is_reclamation_triggered then
        self:trigger_failed_reclamation()
    elseif self.is_defense_triggered then
        self:trigger_failed_defense()
    end
    self:reset_defense_flags()
end


function SmithyState:trigger_successful_reclamation()
    cm:show_message_event_located(self.visiting_enemy_faction_name,
        "event_feed_strings_text_title_event_land_enc_smithy_successfully_reclaimed",
        "event_feed_strings_text_subtitle_event_land_enc_smithy_successfully_reclaimed",
        "event_feed_strings_text_description_event_land_enc_smithy_successfully_reclaimed",
        self.coordinates[1],
        self.coordinates[2],
        false,
        EVENT_IMAGE_ID_LOCATION_OF_INTEREST
    )
    
    self:change_owner_through_occupation(self.visiting_enemy_faction_name)
end


function SmithyState:trigger_successful_defense()
    cm:show_message_event_located(
        self.controlling_faction_name,
        "event_feed_strings_text_title_event_land_enc_smithy_successfully_defended",
        "event_feed_strings_text_subtitle_event_land_enc_smithy_successfully_defended",
        "event_feed_strings_text_description_event_land_enc_smithy_successfully_defended",
        self.coordinates[1],
        self.coordinates[2],
        false,
        EVENT_IMAGE_ID_LOCATION_OF_INTEREST
    )
end


function SmithyState:trigger_failed_reclamation()
    cm:show_message_event_located(
        self.visiting_enemy_faction_name,
        "event_feed_strings_text_title_event_land_enc_smithy_reclaimed_repelled",
        "event_feed_strings_text_subtitle_event_land_enc_smithy_reclaimed_repelled",
        "event_feed_strings_text_description_event_land_enc_smithy_reclaimed_repelled",
        self.coordinates[1],
        self.coordinates[2],
        false,
        EVENT_IMAGE_ID_LOCATION_OF_INTEREST
    )
end

function SmithyState:trigger_failed_defense()
    self:lose_by_conquest()
end

function SmithyState:trigger_unconditional_surrender_incident()
    self:lose_by_conquest()
end

function SmithyState:lose_by_conquest()
    cm:show_message_event_located(self.controlling_faction_name,
        "event_feed_strings_text_title_event_land_enc_smithy_lost",
        "event_feed_strings_text_subtitle_event_land_enc_smithy_lost",
        "event_feed_strings_text_description_event_land_enc_smithy_lost",
        self.coordinates[1],
        self.coordinates[2],
        false,
        EVENT_IMAGE_ID_LOCATION_OF_INTEREST
    )
    self:change_owner_through_occupation(self.visiting_enemy_faction_name)
    self:reset_defense_flags()
end

-------------------------
--- Helpers
-------------------------
function SmithyState:check_if_owner_is_alive_and_return_faction()
    local controlling_faction = cm:get_faction(self.controlling_faction_name)
    if not controlling_faction then
        self.controlling_faction_name = ""
        return nil
    end
    
    if not cm:faction_is_alive(controlling_faction) then
        self.controlling_faction_name = ""
        return nil
    end
    return controlling_faction
end

function SmithyState:is_occupied()
    return self.controlling_faction_name ~= ""
end

function SmithyState:is_on_cooldown()
    return self.visit_cooldown > 0
end

function SmithyState:is_occupied_by_player()
    local player_faction_name = cm:get_local_faction_name()
    return self.controlling_faction_name == player_faction_name
end

function SmithyState:is_occupied_by_same_faction(faction_name)
    return self.controlling_faction_name == faction_name
end

function SmithyState:is_prohibited_subculture(visiting_faction)
    local visiting_subculture = visiting_faction:subculture()
    return visiting_subculture == "wh2_main_rogue" or visiting_subculture == "wh_main_sc_grn_savage_orcs" or visiting_subculture == "wh_main_sc_teb_teb"
end

function SmithyState:is_faction_at_war_with_owner(visiting_faction)
    local controlling_faction = cm:get_faction(self.controlling_faction_name)
    if controlling_faction == false then
        return false
    end
    return controlling_faction:at_war_with(visiting_faction)
end

function SmithyState:set_controlling_faction(faction)
    if type(faction) == "string" then
        faction = cm:get_faction(faction)
    end
        
    -- The faction has been destroyed and the smithy has been abandoned or the faction cannot occupy
    if not faction or faction == "" then
        self.controlling_faction_name = ""
        self.controlling_faction_subculture = ""
    else
        self.controlling_faction_name = faction:name()
        self.controlling_faction_subculture = faction:subculture()        
    end
    
    self.turns_under_control = 0
end

function SmithyState:reset_defense_flags()
    self.is_reclamation_triggered = false
    self.is_defense_triggered = false
    self.visiting_enemy_character = false
    self.visiting_enemy_faction_name = false    
end

function SmithyState:get_spot_info()
    return { 
        zone = self.zone_name, 
        spot_index = self.index_in_zone, 
        spot_type = "SmithySpot", 
        coordinates = self.coordinates
    }
end

function SmithyState:character_is_general_and_can_trigger_dilemma(character)
    if cm:char_is_general_with_army(character) then
        local active_stance = character:military_force():active_stance()
        return (active_stance == "MILITARY_FORCE_ACTIVE_STANCE_TYPE_DEFAULT") or (active_stance == "MILITARY_FORCE_ACTIVE_STANCE_TYPE_CHANNELING") or (active_stance == "MILITARY_FORCE_ACTIVE_STANCE_TYPE_AMBUSH")
    else
        return false
    end
end

--- 
--- 
---
function SmithyState:get_defensive_army() 
    local battle_level = 3
    if self:is_occupied_by_player() then
        battle_level = self.level
    end

    if self:is_occupied() then
        return Army:new_from_faction_and_subculture_and_level(self.controlling_faction_name, self.controlling_faction_subculture, battle_level)
    else
        return {} 
    end
end

-------------------------
--- Memory Management
-------------------------
function SmithyState:export_state_as_table()
    local state_info = {}
    state_info["zone_name"] = self.zone_name
    state_info["index_in_zone"] = self.index_in_zone
    state_info["coordinates"] = self.coordinates
    state_info["is_defense_triggered"] = self.is_defense_triggered
    state_info["is_reclamation_triggered"] = self.is_reclamation_triggered    
    state_info["visiting_enemy_faction_name"] = self.visiting_enemy_faction_name
    state_info["level"] = self.level
    state_info["controlling_faction_name"] = self.controlling_faction_name
    state_info["controlling_faction_subculture"] = self.controlling_faction_subculture
    state_info["turns_under_control"] = self.turns_under_control
    state_info["visit_cooldown"] = self.visit_cooldown
    return state_info
end

function SmithyState:reinstate(previous_state)
    self.zone_name = previous_state["zone_name"]
    self.index_in_zone = previous_state["index_in_zone"]
    self.coordinates = previous_state["coordinates"]
    self.is_defense_triggered = previous_state["is_defense_triggered"]
    self.is_reclamation_triggered = previous_state["is_reclamation_triggered"]
    self.visiting_enemy_faction_name = previous_state["visiting_enemy_faction_name"]
    self.level = previous_state["level"]
    self.controlling_faction_name = previous_state["controlling_faction_name"]
    self.controlling_faction_subculture = previous_state["controlling_faction_subculture"]
    self.turns_under_control = previous_state["turns_under_control"]
    self.visit_cooldown = previous_state["visit_cooldown"]
    return self.is_defense_triggered or self.is_reclamation_triggered
end

-------------------------
--- Constructors
-------------------------
function SmithyState:new(zone_name, index_in_zone, coordinates)
    local t = {
        zone_name = zone_name,
        index_in_zone = index_in_zone,
        coordinates = coordinates,

        is_defense_triggered = false,    
        is_reclamation_triggered = false,
            
        visiting_enemy_character = false,
        visiting_enemy_faction_name = false,
            
        level = 1,
        controlling_faction_name = "",
        controlling_faction_subculture = "",
        turns_under_control = 0,
        visit_cooldown = 0
    }
    setmetatable(t, self)
    self.__index = self    
    return t
end

return SmithyState