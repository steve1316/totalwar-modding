--- SmithyState + SmithyEventDelegate. SmithyState owns the per-smithy lifecycle (visits, upgrades,
--- defense battles, reclamation, AI auto-occupation, missions, and rewards). SmithyEventDelegate is
--- the per-zone manager that routes events to the right SmithyState instance.

--- Specification notes:
---   V1.0: Player must visit a smithy every 3 turns to claim that turn's reward. Smithies are
---   upgradeable up to 3 levels. Enemy generals trigger a defensive battle. AI owners get a random
---   ancillary every 4 turns.
---   V1.1 (planned): Region-aware auto-attack by region owners. Smithy-issued missions that reward
---   legendary items or blue sets when completed in time.

require("script/land_encounters/utils/common")
require("script/land_encounters/core/managers")

local elligible_items = require("script/land_encounters/configs/items").balancing
local special_items_by_subculture = require("script/land_encounters/configs/items").special_by_subculture
local smithy_missions_by_subculture = require("script/land_encounters/configs/smithy_data").missions_by_subculture

local Army = require("script/land_encounters/core/army")

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Constants

local FIRST_OPTION = 0
local SECOND_OPTION = 1

local EVENT_IMAGE_ID_LOCATION_OF_INTEREST = 1017

--- Heavily reused events
local EVENT_RECLAMATION = "land_enc_dilemma_smithy_reclamation"
local EVENT_DEFENSE = "land_enc_dilemma_smithy_defense"
local EVENT_VISIT_BY_LEVEL = {
    "land_enc_dilemma_smithy_visit_level_1",
    "land_enc_dilemma_smithy_visit_level_2",
    "land_enc_dilemma_smithy_visit_level_3"
}
local EVENT_VISIT_TARGETS = { character = true, force = true, faction = false, region = false }
local TRIBUTE_INCIDENT_EVENT = "land_enc_incident_smithy_tribute"


--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Properties definition
local SmithyState = {
    --- Marker id that identifies if this smithy should change its state
    zone_name = "",
    index_in_zone = "",
    coordinates = {},
    --- smithy defense (from player or AI) variables
    is_defense_triggered = false,
    is_reclamation_triggered = false,

    visiting_enemy_character = false,
    --- in case the player does not finish the battle in the same game session we save its faction to find him later
    visiting_enemy_faction_name = false,

    level = 1,
    controlling_faction_name = "",
    controlling_faction_subculture = "",
    turns_under_control = 0,
    visit_cooldown = 0
}

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Turn passing

--- Runs the per-turn smithy update: rewards, cooldowns, missions, and auto-occupation when abandoned.
--- @param mission_manager table The CA mission_manager handle used to issue missions.
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

--- Rewards the controlling faction with periodic ancillaries based on smithy level and ownership.
--- @param controlling_faction faction The faction currently controlling this smithy.
function SmithyState:reward_owner_faction(controlling_faction)
    local turns_till_reward = 9999
    if self:is_occupied_by_player() then
        --- if the smith is under player control, give an ancillary every [ancillary_reward_turn] configurable through MCT and the smithing level
        turns_till_reward = self.turns_under_control % self:reward_turn_given_level()
    elseif self:is_occupied() then
        --- if the smith is under AI control. Every 4 levels give an ancillary to their faction (flat)
        turns_till_reward = self.turns_under_control % 4
    end
    if turns_till_reward == 0 then
        --- if its an ai filter the event
        local representative_character = cm:get_highest_ranked_general_for_faction(controlling_faction)
        --- Guarantees that an ancillary is given to the faction and no crashing occurss
        if representative_character ~= false then
            trigger_incident(TRIBUTE_INCIDENT_EVENT, EVENT_VISIT_TARGETS, self:get_spot_info(), representative_character)
        else
            cm:add_ancillary_to_faction(controlling_faction, elligible_items[random_number(#elligible_items)], false)
        end
    end
end

--- Returns how many turns must elapse between ancillary rewards for the player at the current smithy level.
--- @returns number Turns between rewards (15 at L1, 10 at L2, 5 at L3).
function SmithyState:reward_turn_given_level()
    return (4 - self.level) * 5 -- [ancillary_reward_turn]
end

--- Decrements the visit cooldown each turn and fires an event-feed notification when it hits zero.
--- @param controlling_faction string The faction key currently controlling this smithy.
function SmithyState:update_visit_cooldown(controlling_faction)
    if self:is_occupied_by_player() and self.visit_cooldown > 0 then
        self.visit_cooldown = self.visit_cooldown - 1
        --- you can visit now
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

--- Issues a periodic smithy mission to the player (every 30 turns) or grants set/special items to the AI (every 12 turns).
--- @param controlling_faction faction The faction currently controlling this smithy.
--- @param mission_manager table The CA mission_manager handle used to issue missions.
function SmithyState:issue_mission_if_possible(controlling_faction, mission_manager)
    --- if is occupied by player and the smithy has been under control for 20 turns
    if self:is_occupied_by_player() and self.turns_under_control % 30 == 0 then
        --- issue a subculture mission for the player so that they can win an ancillary by completing a mission
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
        --- give a set or a special subculture item directly to the ai
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

--- When the smithy is abandoned, assigns the owning faction of the underlying region as the new controller.
function SmithyState:try_to_automatically_occupy_smithy_by_region_ownership_when_abandoned()
    local region_data = cm:get_region_data_at_position(self.coordinates[1], self.coordinates[2])
    if region_data and not region_data:is_null_interface() and region_data:region() ~= nil then
        local new_owner_by_region_occupation = region_data:region():owning_faction()
        if not new_owner_by_region_occupation:is_null_interface() then
            --- Auto occupy the smithy using the owner's name
            self:set_controlling_faction(new_owner_by_region_occupation)
        end
    end
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- On event happening

--- Routes a character entering this smithy's marker to the right handler: dilemma for the owning player,
--- defense battle for an enemy general, owner-default message otherwise. `invasion_battle_manager` is
--- used to spawn the defending army when an enemy general attacks.
--- @param area_and_character_info table The AreaEntered context with area_key and family_member.
--- @param invasion_battle_manager InvasionBattleManager The shared invasion battle manager.
function SmithyState:trigger_event(area_and_character_info, invasion_battle_manager)
    local visiting_character = area_and_character_info:family_member():character()
    local visiting_faction = visiting_character:faction()

    --- is human
    if is_human_and_it_is_its_turn(visiting_faction) then
        --- and is occupied by said human
        if self:is_occupied_by_same_faction(visiting_faction:name()) then
            --- the master blacksmith can't receive you
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
            --- he can receive you
                cm:trigger_dilemma(visiting_faction:name(), EVENT_VISIT_BY_LEVEL[self.level])
            end
        else
        --- if it's not occupied by the player
            if not self:is_occupied() then
            --- and its not ocuppied by anyone
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
            --- and its occupied by an enemy
                --- Character is in accepted stance and can trigger the event
                if self:character_is_general_and_can_trigger_dilemma(visiting_character) then
                    --- then we can avoid it or battle for it
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
            --- and its occupied by an ally or a neutral faction so we tell the player they need to be at war or have this faction dissapear to take the smithy
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
    --- is not an AI faction that has too random armies and is an AI enemy faction so the faction attacks the point
        if self:is_occupied_by_player() then
            --- the smithy is attacked, triger related event
            self.visiting_enemy_character = visiting_character
            self.visiting_enemy_faction_name = visiting_faction:name()
            --- given that the player cannot answer dilemmas during AI turn we autotrigger the defense
            self.is_defense_triggered = true
            self:trigger_forced_interception_defense(invasion_battle_manager)
        else
            --- the smithy changes hands randomly automatically to the enemy faction
            if random_number(100) >= 75 then
                local is_player = false
                self:change_owner_through_conquest(visiting_faction:name(), is_player, visiting_character)
            end
        end
    end
end

--- Transfers control of the smithy via region occupation (no battle).
--- @param faction faction The new controlling faction.
function SmithyState:change_owner_through_occupation(faction)
    self:set_controlling_faction(faction)
end

--- Transfers control of the smithy via battle victory. Fires the reclamation incident for the player.
--- @param faction faction The new controlling faction.
--- @param is_player boolean True when the player is the new owner.
--- @param representative_character character The player character whose victory caused the transfer.
function SmithyState:change_owner_through_conquest(faction, is_player, representative_character)
    self:set_controlling_faction(faction)

    if is_player then
        trigger_incident(EVENT_RECLAMATION, EVENT_VISIT_TARGETS, self:get_spot_info(), representative_character)
    end
end

--- Handles the player's choice in any of the smithy dilemmas (visit, reclamation, defense).
--- @param dilemma_choice_and_faction_info table The DilemmaChoiceMadeEvent context.
--- @param invasion_battle_manager InvasionBattleManager The shared invasion battle manager.
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
        --- If the AI controls the point. The point will be heavily defended. Only the player has to level it up correctly as the player benefits more from it
        --- up in the other logic
        self.is_reclamation_triggered = true
        self:trigger_reclamation_battle(invasion_battle_manager)
    --- when the smithy is controlled by an enemy faction
    elseif dilemma == EVENT_DEFENSE and choice == FIRST_OPTION then
        --- If the AI controls the point. The point will be heavily defended. Only the player has to level it up correctly as the player benefits more from it
        --- up in the other logic
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

--- Routes the post-battle outcome to the matching victory or defeat handler.
--- @param player_won_battle boolean True when the player was victorious.
function SmithyState:trigger_event_given_battle_result(player_won_battle)
    if player_won_battle then
        self:trigger_victory_event_given_battle_type()
    else
        self:trigger_defeat_event_given_battle_type()
    end
end

--- Spawns a defender army and starts the reclamation battle against the visiting player.
--- @param invasion_battle_manager InvasionBattleManager The shared invasion battle manager.
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

--- Spawns the defender army and starts a forced interception when an enemy AI attacks the player's smithy.
--- @param invasion_battle_manager InvasionBattleManager The shared invasion battle manager.
function SmithyState:trigger_forced_interception_defense(invasion_battle_manager)
    local defender_army = self:get_defensive_army()
    --- Given that people tend to install mods that break the smithies (like having custom factions and the like)
    --- we need to check that an army is created. If not we simply delete the flags and ignore the activation.
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

--- Routes a victory outcome to the matching follow-up (successful reclamation or successful defense).
function SmithyState:trigger_victory_event_given_battle_type()
    --- the player is reclaiming the smithy and won
    if self.is_reclamation_triggered then
        self:trigger_successful_reclamation()
    --- the player defends its smithy and won
    elseif self.is_defense_triggered then
        self:trigger_successful_defense()
    end
    self:reset_defense_flags()
end

--- Routes a defeat outcome to the matching follow-up (failed reclamation or failed defense).
function SmithyState:trigger_defeat_event_given_battle_type()
    if self.is_reclamation_triggered then
        self:trigger_failed_reclamation()
    elseif self.is_defense_triggered then
        self:trigger_failed_defense()
    end
    self:reset_defense_flags()
end


--- Shows the successful-reclamation event-feed message and transfers ownership to the visiting faction.
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


--- Shows the successful-defense event-feed message. Ownership stays with the controlling faction.
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


--- Shows the failed-reclamation event-feed message for the visiting faction.
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

--- Routes a failed-defense outcome through the standard lose-by-conquest path.
function SmithyState:trigger_failed_defense()
    self:lose_by_conquest()
end

--- Routes an unconditional-surrender choice through the standard lose-by-conquest path.
function SmithyState:trigger_unconditional_surrender_incident()
    self:lose_by_conquest()
end

--- Shows the lost-smithy event-feed message, transfers ownership to the visitor, and clears defense flags.
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

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Helpers
--- Resolves the controlling faction or clears ownership if the faction is dead or missing.
--- @returns faction The live controlling faction, or nil when ownership was cleared.
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

--- Returns true when any faction currently controls the smithy.
--- @returns boolean True when controlling_faction_name is non-empty.
function SmithyState:is_occupied()
    return self.controlling_faction_name ~= ""
end

--- Returns true when the smithy is in its post-visit cooldown window.
--- @returns boolean True when visit_cooldown is positive.
function SmithyState:is_on_cooldown()
    return self.visit_cooldown > 0
end

--- Returns true when the local player faction currently controls the smithy.
--- @returns boolean True when controlling_faction_name matches the local faction.
function SmithyState:is_occupied_by_player()
    local player_faction_name = cm:get_local_faction_name()
    return self.controlling_faction_name == player_faction_name
end

--- Returns true when the smithy is controlled by the given faction.
--- @param faction_name string The faction key to compare against.
--- @returns boolean True when controlling_faction_name equals faction_name.
function SmithyState:is_occupied_by_same_faction(faction_name)
    return self.controlling_faction_name == faction_name
end

--- Returns true when the visiting faction's subculture is one of the locked-out groups (rogues, savage orcs, border princes).
--- @param visiting_faction faction The visiting faction.
--- @returns boolean True when the subculture is in the prohibited list.
function SmithyState:is_prohibited_subculture(visiting_faction)
    local visiting_subculture = visiting_faction:subculture()
    return visiting_subculture == "wh2_main_rogue" or visiting_subculture == "wh_main_sc_grn_savage_orcs" or visiting_subculture == "wh_main_sc_teb_teb"
end

--- Returns true when the visiting faction is at war with the smithy's controlling faction.
--- @param visiting_faction faction The visiting faction.
--- @returns boolean True when the two factions are at war, false if no controller exists.
function SmithyState:is_faction_at_war_with_owner(visiting_faction)
    local controlling_faction = cm:get_faction(self.controlling_faction_name)
    if controlling_faction == false then
        return false
    end
    return controlling_faction:at_war_with(visiting_faction)
end

--- Sets the new controlling faction and resets turns_under_control. Accepts a faction object or faction key.
--- @param faction faction The new owner. May be a faction handle or a faction key string. Empty/nil clears ownership.
function SmithyState:set_controlling_faction(faction)
    if type(faction) == "string" then
        faction = cm:get_faction(faction)
    end

    --- The faction has been destroyed and the smithy has been abandoned or the faction cannot occupy
    if not faction or faction == "" then
        self.controlling_faction_name = ""
        self.controlling_faction_subculture = ""
    else
        self.controlling_faction_name = faction:name()
        self.controlling_faction_subculture = faction:subculture()
    end

    self.turns_under_control = 0
end

--- Clears the per-battle reclamation/defense flags after a battle resolves.
function SmithyState:reset_defense_flags()
    self.is_reclamation_triggered = false
    self.is_defense_triggered = false
    self.visiting_enemy_character = false
    self.visiting_enemy_faction_name = false
end

--- Builds and returns a spot_info record describing this smithy.
--- @returns table { zone string, spot_index number, spot_type string, coordinates table }.
function SmithyState:get_spot_info()
    return {
        zone = self.zone_name,
        spot_index = self.index_in_zone,
        spot_type = "SmithySpot",
        coordinates = self.coordinates
    }
end

--- True if the character is a general in a stance that permits the smithy dilemma to trigger.
--- @param character character The character to check.
--- @returns boolean True when the character is a general in an eligible stance.
function SmithyState:character_is_general_and_can_trigger_dilemma(character)
    if cm:char_is_general_with_army(character) then
        local active_stance = character:military_force():active_stance()
        return (active_stance == "MILITARY_FORCE_ACTIVE_STANCE_TYPE_DEFAULT") or (active_stance == "MILITARY_FORCE_ACTIVE_STANCE_TYPE_CHANNELING") or (active_stance == "MILITARY_FORCE_ACTIVE_STANCE_TYPE_AMBUSH")
    else
        return false
    end
end

--- Builds the smithy defender army by running the randomization pipeline with the controlling faction's
--- subculture and the smithy's level (1..3 maps to easy/medium/hard difficulty). Used by the defense battle.
--- @returns Army A new Army for the defender, or an empty table when the smithy is abandoned.
function SmithyState:get_defensive_army()
    local battle_level = 3
    if self:is_occupied_by_player() then
        battle_level = self.level
    end

    if self:is_occupied() then
        return Army:new_from_subculture_and_level(self.controlling_faction_subculture, battle_level)
    else
        return {}
    end
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Memory Management
--- Exports the smithy's per-instance state into a flat table for save/load.
--- @returns table A flat state_info record suitable for the save state.
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

--- Restores per-instance state from a previously exported state_info record.
--- @param previous_state table A record previously produced by export_state_as_table.
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

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Constructors
--- Constructs a fresh SmithyState at the given zone + index + coordinates. Defaults to level 1, unowned, no in-flight battle.
--- @param zone_name string The region key for the zone hosting the smithy.
--- @param index_in_zone number 1-based smithy slot index inside the zone.
--- @param coordinates table A {x, y} coordinate pair for the smithy's location.
--- @returns SmithyState A new SmithyState with default values.
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


--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Properties definition
local SmithyEventDelegate = {
    smithies_state = {},
    --- CA Managers
    mission_manager = {},
    --- Delegates
    invasion_battle_manager = {}
}

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Generation and automatic updates

--- Bootstraps a SmithyState for each smithy in the zone's initial state, mapping initial-owner to owner_if_player when the player matches.
--- @param zone_name string The region key for the zone hosting the smithies.
--- @param smithies_initial_state table An array of initial-state records (coordinates, initial_owner, owner_if_player).
function SmithyEventDelegate:generate_states(zone_name, smithies_initial_state)
    local player_faction_name = cm:get_local_faction_name()

    for i = 1, #smithies_initial_state do
        local smithy_state = SmithyState:new(zone_name, i, smithies_initial_state[i].coordinates)

        if player_faction_name == smithies_initial_state[i].initial_owner then
            smithy_state:set_controlling_faction(smithies_initial_state[i].owner_if_player)
        else
            smithy_state:set_controlling_faction(smithies_initial_state[i].initial_owner)
        end

        table.insert(self.smithies_state, smithy_state)
    end
end


--- Ticks per-turn updates on every SmithyState (visits, rewards, missions, AI auto-occupy).
function SmithyEventDelegate:update_state_given_turn_passing()
    for i=1, #self.smithies_state do
        self.smithies_state[i]:update_state_given_turn_passing(self.mission_manager)
    end
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Event Management

--- Dispatches the smithy-entered event to the matching SmithyState (by zone + index).
--- @param area_and_character_info table The AreaEntered context with area_key and family_member.
--- @param spot_info table The spot_info record for the triggered smithy.
function SmithyEventDelegate:trigger_event(area_and_character_info, spot_info)
    for i=1, #self.smithies_state do
        if self.smithies_state[i].zone_name == spot_info.zone.name and self.smithies_state[i].index_in_zone == spot_info.spot_index then
            self.smithies_state[i]:trigger_event(area_and_character_info, self.invasion_battle_manager)
            break
        end
    end
end

--- Dispatches a smithy dilemma choice to the matching SmithyState (by zone + index).
--- @param dilemma_choice_and_faction_info table The DilemmaChoiceMadeEvent context.
--- @param spot_info table The spot_info record for the triggered smithy.
function SmithyEventDelegate:trigger_dilemma_event_given_choice(dilemma_choice_and_faction_info, spot_info)
    for i=1, #self.smithies_state do
        if self.smithies_state[i].zone_name == spot_info.zone.name and self.smithies_state[i].index_in_zone == spot_info.spot_index then
            self.smithies_state[i]:trigger_dilemma_event_given_choice(dilemma_choice_and_faction_info, self.invasion_battle_manager)
            break
        end
    end
end


--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Memory Management

--- Flattens every SmithyState into an array of state tables for the save/load callbacks.
--- @returns table An array of per-smithy state_info records.
function SmithyEventDelegate:export_state_as_table()
    local smithies_data = {}
    for i = 1, #self.smithies_state do
        table.insert(smithies_data, self.smithies_state[i]:export_state_as_table())
    end
    return smithies_data
end

--- Restores every SmithyState from a previously saved state array. Re-arms in-flight defense battles
--- so the post-battle cleanup wiring continues to fire after a campaign reload.
--- @param previous_state table An array of per-smithy state_info records previously produced by export_state_as_table.
function SmithyEventDelegate:reinstate_event_if_able(previous_state)
    for i = 1, #previous_state do
        self.smithies_state[i] = SmithyState:new("", 0, {})
        local active_poi_spot_index = self.smithies_state[i]:reinstate(previous_state[i])
        if active_poi_spot_index ~= nil then
            local defensive_army = self.smithies_state[i]:get_defensive_army()
            self.invasion_battle_manager:set_auxiliary_army_for_reset(defensive_army)
            self.invasion_battle_manager:mark_battle_forces_for_removal(defensive_army)
            self.invasion_battle_manager:reset_state_post_battle(self.smithies_state[i], "SmithySpot", nil, defensive_army)
        end
    end
end


--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Constructors
--- Constructs a fresh SmithyEventDelegate wired to the given CA mission_manager and InvasionBattleManager.
--- @param mission_manager table The CA mission_manager handle.
--- @param invasion_battle_manager InvasionBattleManager The shared invasion battle manager.
--- @returns SmithyEventDelegate A new delegate with no smithies yet attached.
function SmithyEventDelegate:new(mission_manager, invasion_battle_manager)
    local t = {
        mission_manager = mission_manager,
        invasion_battle_manager = invasion_battle_manager
    }
    setmetatable(t, self)
    self.__index = self
    return t
end

return SmithyEventDelegate
