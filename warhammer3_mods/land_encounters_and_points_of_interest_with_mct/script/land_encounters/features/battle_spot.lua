--- BattleEventDelegate. Handles the full battle-spot lifecycle: pre-battle dilemma, encounter
--- Army generation, invasion firing, and the victory/avoidance/cleanup incidents.

require("script/land_encounters/utils/common")
require("script/land_encounters/core/managers")

local complex_continuity_events = require("script/land_encounters/configs/events").complex_continuity
local item_pool = require("script/land_encounters/core/item_pool")
local battle_categories = require("script/land_encounters/configs/battle_categories")
local offer_effects = require("script/land_encounters/core/offer_effects")
local realm_effects = require("script/land_encounters/core/realm_effects")

local battle_picker = require("script/land_encounters/core/battle_picker")
local debug_config = require("script/land_encounters/configs/debug")
local army_generator = require("script/land_encounters/core/army_generator")
local spot_battles = require("script/land_encounters/features/spot_battles")
local spot_offers = require("script/land_encounters/features/spot_offers")
local battle_modifiers = require("script/land_encounters/features/battle_modifiers")
local victory_gold = require("script/land_encounters/configs/victory_gold")
local round_gold = require("script/land_encounters/configs/tower_data").round_gold
local spoils_site = require("script/land_encounters/configs/spot_offers").spoils

local Army = require("script/land_encounters/core/army")

local BattleEventDelegate = {
    invasion_battle_manager = {},

    --- Variables cached for the duration of an in-flight event.
    cached_player_character = {},
    cached_event = {},
    is_triggered = false
}

local FIRST_OPTION = 0

--- Units in the allied army of an allied-army test battle.
local ALLY_TEST_UNITS = 8
local ERROR_BATTLE_CLEAN_UP_EVENT = {
    incident = "land_enc_incident_battle_clean_up_event",
    targets = {
        character = true,
        force = false,
        faction = false,
        region = false
    }
}

--- Returns the player character cached when the current dilemma was triggered.
--- @returns character The cached player character, or nil when no dilemma is in flight.
function BattleEventDelegate:get_cached_player_character()
    return self.cached_player_character
end

--- Routes a freshly entered battle spot to the right code path: human-general -> dilemma, AI ->
--- silent loot, human-non-general -> show-only event-feed message. Returns whether the spot should be removed. A human general's dilemma
--- is built in script (features/spot_battles.lua), with pre-battle offers when the pre-battle roll hits, else as plain Fight or Avoid.
--- @param area_and_character_info table The AreaEntered context with area_key and family_member.
--- @param spot_info table A spot_info record for the spot being entered.
--- @returns boolean True when the spot should be deactivated after dispatch.
function BattleEventDelegate:trigger_pre_battle_dilemma(area_and_character_info, spot_info)
    self.cached_player_character = area_and_character_info:family_member():character()
    local triggering_faction = self.cached_player_character:faction()
    local triggering_faction_name = triggering_faction:name()

    if is_human_and_it_is_its_turn(triggering_faction) and self:character_is_general_and_can_trigger_dilemma(self.cached_player_character) then
        if debug_config.ally_test[1] then
            --- Listed modes take turns, one per battle spot entered.
            self.ally_test_runs = (self.ally_test_runs or 0) + 1
            self:start_ally_test(self.cached_player_character, spot_info, debug_config.ally_test[(self.ally_test_runs - 1) % #debug_config.ally_test + 1])
            return true
        end
        self.cached_event = battle_picker.pick()
        spot_battles.open(self.cached_event, self.cached_player_character, triggering_faction, spot_battles.roll())
        return true
    elseif not triggering_faction:is_human() then
        --- AI: silently grants a small loot.
        local trigger_event_feed = false
        if random_chance(10) then
            local ancillary = item_pool.pick_item_for_difficulty(triggering_faction_name)
            if ancillary ~= nil then
                cm:add_ancillary_to_faction(triggering_faction, ancillary, trigger_event_feed)
            end
        end
        cm:treasury_mod(triggering_faction_name, 500)
        return true
    else
        --- Human but cannot trigger the dilemma. Show an event-feed message only.
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

--- Starts an allied-army test battle (configs/debug.lua `ally_test`) instead of the spot's dilemma: the encounter gets an allied army of
--- `ALLY_TEST_UNITS` units, and the invasion manager runs the test's setup when it spawns the armies. Results go to the script log.
--- @param character character The lord who entered the spot.
--- @param spot_info table A spot_info record for the spot.
--- @param mode string "side_by_side" or "relief_column".
function BattleEventDelegate:start_ally_test(character, spot_info, mode)
    self.cached_player_character = character
    self.cached_event = battle_picker.pick(nil, { no_allies = true })
    self.cached_event.intervention = ALLIED_REINFORCEMENTS_PERMITTED_TYPE
    self.cached_event.ally_options = army_generator.ally_options(ALLY_TEST_UNITS)
    self.invasion_battle_manager.ally_test = { mode = mode, player_cqi = character:command_queue_index() }
    log("ally test: " .. mode .. " with a " .. self.cached_event.category .. " battle for lord " .. character:command_queue_index() .. " at ("
        .. spot_info.coordinates[1] .. ", " .. spot_info.coordinates[2] .. ")")
    self:start_battle(spot_info)
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Dilemmas

--- Handles the player's dilemma choice: Fight spawns + fires the battle, anything else triggers the avoidance incident. A dilemma with
--- pre-battle offers is routed by choice key, and a taken offer fights with its changes on the battle event.
--- @param dilemma_choice_and_faction_info table The DilemmaChoiceMadeEvent context.
--- @param spot_info table A spot_info record for the triggering spot.
function BattleEventDelegate:trigger_dilemma_event_given_choice(dilemma_choice_and_faction_info, spot_info)
    local choice = dilemma_choice_and_faction_info:choice()
    local action = spot_battles.take(dilemma_choice_and_faction_info:faction():name(), dilemma_choice_and_faction_info:choice_key(), self.cached_event)
    --- A mission was taken: the same dilemma is already open again.
    if action == "reopen" then return end
    if action == "fight" or (action == nil and choice == FIRST_OPTION) then
        out("DEBUG - trigger_dilemma_event_given_choice dilemma: " .. dilemma_choice_and_faction_info:dilemma())
        out("DEBUG - trigger_dilemma_event_given_choice choice: " .. dilemma_choice_and_faction_info:choice())
        self:start_battle(spot_info)
    else
        self:trigger_battle_avoidance_incident(spot_info)
    end
end


--- Starts the battle the cached event describes at a spot: generates the army, readies ours with any pre-battle offers, fires the battle and
--- routes its result. With no valid spawn location the default removal incident fires instead.
--- @param spot_info table A spot_info record with the battle's coordinates.
function BattleEventDelegate:start_battle(spot_info)
    local offensive_army = self:get_offensive_army()
    out("DEBUG - offensive_army generated")
    if not self.invasion_battle_manager:can_generate_battle(offensive_army, spot_info.coordinates) then
        self:trigger_battle_removal_incident(spot_info)
        return
    end
    self.is_triggered = true
    --- Kept on the event, so the ally's culture is known after a load, when the army is built again with another ally.
    local ally = offensive_army.reinforcing_ally_armies[1]
    self.cached_event.ally_faction = ally and ally.faction or nil
    spot_battles.prepare_battle(self.cached_event, self.cached_player_character:command_queue_index())
    self.invasion_battle_manager:generate_battle(offensive_army, self.cached_player_character, spot_info.coordinates)
    --- Handed over once the army is generated, since Night terrors and the missions pick targets from its units.
    spot_battles.hand_to_battle(self.cached_event, offensive_army)
    self.invasion_battle_manager:mark_battle_forces_for_removal(offensive_army)
    self.invasion_battle_manager:reset_state_post_battle(self, "BattleSpot", spot_info, offensive_army)
end

--- Starts a guardian battle at a treasure site (features/spot_offers.lua: Wake the Guardian, Oath at the Altar): a battle picked as for a battle spot, whose army attacks
--- the lord at once. Its result is a battle spot's: the victory reward and the spoils roll.
--- @param character character The lord the guardian attacks.
--- @param spot_info table A spot_info record with the site's coordinates.
--- @param difficulty string|nil The battle's difficulty, or nil for the current one.
function BattleEventDelegate:start_guardian_battle(character, spot_info, difficulty)
    self.cached_player_character = character
    self.cached_event = battle_picker.pick(difficulty, { no_allies = true })
    self.cached_event.intervention = INTERCEPTION_TYPE
    log("spot: the guardian wakes and attacks lord " .. character:command_queue_index() .. " with a " .. self.cached_event.category .. " battle at ("
        .. spot_info.coordinates[1] .. ", " .. spot_info.coordinates[2] .. ")")
    self:start_battle(spot_info)
end

--- Fires the generic clean-up incident when a battle could not be spawned (no valid spawn location).
--- @param spot_info table A spot_info record for the triggering spot.
function BattleEventDelegate:trigger_battle_removal_incident(spot_info)
    trigger_incident(ERROR_BATTLE_CLEAN_UP_EVENT.incident, ERROR_BATTLE_CLEAN_UP_EVENT.targets, spot_info, self.cached_player_character)
end


--- Fires the cached dilemma's avoidance incident (player chose to skip the battle).
--- @param spot_info table A spot_info record for the triggering spot.
function BattleEventDelegate:trigger_battle_avoidance_incident(spot_info)
    trigger_incident(self.cached_event.avoidance_incident, self.cached_event.avoidance_targets, spot_info, self.cached_player_character)
end

--- Called by InvasionBattleManager after BattleCompleted. On player win, pays the missions met and fires the victory incident. Either way
--- the pre-battle offers' one-battle bundles come off and everything handed to the battle script is cleared.
--- @param player_won_battle boolean True when the player was victorious.
--- @param spot_info table A spot_info record for the triggering spot.
function BattleEventDelegate:trigger_event_given_battle_result(player_won_battle, spot_info)
    local character = self.cached_player_character
    local general_cqi = character and character.command_queue_index and character:command_queue_index() or nil
    if player_won_battle and general_cqi then spot_battles.settle_missions(self.cached_event, character:faction():name(), general_cqi) end
    spot_battles.end_battle(self.cached_event, general_cqi)
    if player_won_battle then
        self:trigger_victory_incident(spot_info)
    end
    self.is_triggered = false
end


--- Fires the victory incident, grants the victory items, may open the spoils pick, then runs any continuity follow-up and AI balancing.
--- @param spot_info table A spot_info record for the triggering spot.
function BattleEventDelegate:trigger_victory_incident(spot_info)
    --- The cached player can be cleared by a battle reload, so resolve it here too.
    if self.cached_player_character == nil or (type(self.cached_player_character) == "table" and next(self.cached_player_character) == nil) then
        self.cached_player_character = get_player_faction_character_closest_to_spot(spot_info)
    end

    local gift = self:pick_ally_gift(self.cached_player_character)
    if gift then
        self:trigger_victory_with_gift(self.cached_player_character, gift, spot_info)
    else
        trigger_incident(self.cached_event.victory_incident, self.cached_event.victory_targets, spot_info, self.cached_player_character)
    end
    self:grant_victory_items(self.cached_player_character:faction())
    self:grant_ally_rewards(self.cached_player_character, spot_info)
    self:pay_modifier_gold(self.cached_player_character:faction())
    --- The spoils pick (features/spot_offers.lua) follows the victory reward when its roll hits.
    if self.cached_player_character:faction():is_human() and spot_battles.roll_spoils() then
        spot_offers.open_site(self.cached_player_character, self.cached_player_character:faction(), spoils_site, self.cached_event)
    end
    --- Complex events trigger a balancing act on enemy AI factions.
    local continuity = self:check_if_incident_has_continuity(self.cached_event.victory_incident, self.cached_player_character:faction())
    if continuity ~= nil then
        trigger_incident(continuity.incident, continuity.targets, spot_info, self.cached_player_character)
        if continuity.balance ~= false then
            self:trigger_incident_for_ai_due_to_balance(continuity.balance, self.cached_player_character:faction())
        end
    end
end

--- Grants the battle category's victory item, and on hard difficulty a small chance of a legendary item. Events saved before these rewards
--- existed carry neither field and grant nothing extra.
--- @param faction faction The victorious player faction.
function BattleEventDelegate:grant_victory_items(faction)
    local rewards = {}
    local victory_items = self.cached_event.victory_items
    if victory_items then
        rewards = item_pool.pick_items(faction:name(), victory_items.rarities, victory_items.count)
    end
    if self.cached_event.difficulty == "hard" and random_chance(battle_categories.hard_legendary_chance) then
        table.insert(rewards, item_pool.pick_legendary_item(faction:name()))
    end
    for _, ancillary in ipairs(rewards) do
        cm:add_ancillary_to_faction(faction, ancillary, false)
    end
end

--- Finds the nearest real faction of the Ally in Peril battle's ally culture that is not at war with us. The ally itself fights under a
--- stand-in faction that only exists for the battle.
--- @param faction faction Our faction.
--- @param spot_info table A spot_info record for the battle's spot.
--- @returns faction|nil The faction, or nil when the ally is unknown or none is found.
function BattleEventDelegate:ally_kin(faction, spot_info)
    local stand_in = self.cached_event.ally_faction and cm:get_faction(self.cached_event.ally_faction)
    if not stand_in or stand_in:is_null_interface() then return nil end
    local culture = stand_in:culture()
    return realm_effects.nearest_factions(faction, spot_info.coordinates[1], spot_info.coordinates[2], 1,
        function(other) return other:culture() == culture and not other:at_war_with(faction) end)[1]
end

--- Picks the surviving allied unit that joins us on an `ally.gift_unit` win, when our army has room.
--- @param character character Our lord.
--- @returns string|nil The unit key, or nil for none.
function BattleEventDelegate:pick_ally_gift(character)
    local ally = self.cached_event.ally
    if not ally or not ally.gift_unit or not self.cached_event.ally_faction then return nil end
    local survivors = self.invasion_battle_manager.ally_survivors or {}
    if #survivors == 0 then
        log("spot battle: no allied unit survived to join us")
        return nil
    end
    if not offer_effects.has_room(character:command_queue_index(), 1) then
        log("spot battle: our army has no room for an allied unit")
        return nil
    end
    return survivors[random_number(#survivors)]
end

--- Fires the victory incident built in script, so the allied unit joining us shows as a card beside the incident's own gold. When it cannot
--- be built, the plain incident fires and the unit joins in script.
--- @param character character Our lord.
--- @param gift string The joining unit's key.
--- @param spot_info table A spot_info record for the battle's spot.
function BattleEventDelegate:trigger_victory_with_gift(character, gift, spot_info)
    local event = self.cached_event
    local ok, err = pcall(function()
        local builder = cm:create_incident_builder(event.victory_incident)
        local payload = cm:create_payload()
        payload:treasury_adjustment(victory_gold[event.victory_incident] or 0)
        payload:add_unit(character:military_force(), gift, 1, 0)
        builder:set_payload(payload)
        builder:add_target("default", character)
        cm:launch_custom_incident_from_builder(builder, character:faction())
    end)
    if ok then
        log("spot battle: the surviving ally " .. gift .. " joins our army, shown on " .. event.victory_incident)
        return
    end
    log("spot battle: " .. event.victory_incident .. " could not be built (" .. tostring(err) .. "), the ally " .. gift .. " joins in script")
    trigger_incident(event.victory_incident, event.victory_targets, spot_info, character)
    cm:grant_unit_to_character(cm:char_lookup_str(character), gift)
end

--- Pays the change the battle's modifiers make to its victory gold: more for harmful ones, less for helpful ones, rounded to 50.
--- @param faction faction Our faction.
function BattleEventDelegate:pay_modifier_gold(faction)
    local modifiers = self.cached_event.modifiers
    if not modifiers or #modifiers == 0 then return end
    local base = victory_gold[self.cached_event.victory_incident] or 0
    local change = round_gold(base * (battle_modifiers.gold_multiplier(modifiers) - 1))
    if change ~= 0 then cm:treasury_mod(faction:name(), change) end
    log("spot battle: modifiers " .. table.concat(modifiers, ", ") .. " change the victory gold " .. base .. " by " .. change)
end

--- Rewards an Ally in Peril win with `ally.relations` with the ally's kin, or gold when there is none. A battle whose ally never spawned
--- rewards nothing extra.
--- @param character character Our lord.
--- @param spot_info table A spot_info record for the battle's spot.
function BattleEventDelegate:grant_ally_rewards(character, spot_info)
    local ally = self.cached_event.ally
    if not ally or not self.cached_event.ally_faction then return end
    local faction = character:faction()
    if ally.relations then
        local kin = self:ally_kin(faction, spot_info)
        if kin then
            realm_effects.change_relations(faction:name(), kin:name(), ally.relations)
        else
            local gold = ally.relations * battle_categories.ally_relations_gold
            cm:treasury_mod(faction:name(), gold)
            log("spot battle: no kin of the ally " .. self.cached_event.ally_faction .. " is near and at peace, " .. gold .. " gold instead")
        end
    end
end

--- True if the character is a general in a stance that permits the dilemma to trigger (default/channeling/ambush).
--- @param character character The character to check.
--- @returns boolean True when the character is a general in an eligible stance.
function BattleEventDelegate:character_is_general_and_can_trigger_dilemma(character)
    if cm:char_is_general_with_army(character) then
        local active_stance = character:military_force():active_stance()
        return (active_stance == "MILITARY_FORCE_ACTIVE_STANCE_TYPE_DEFAULT") or (active_stance == "MILITARY_FORCE_ACTIVE_STANCE_TYPE_CHANNELING") or (active_stance == "MILITARY_FORCE_ACTIVE_STANCE_TYPE_AMBUSH")
    else
        return false
    end
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Balance for AI

--- Returns the matching continuity result for an incident if its conditions are met, or nil otherwise.
--- @param incident_key string The incident key to look up in complex_continuity_events.
--- @param faction faction The faction whose state is evaluated against the conditions.
--- @returns table The matching result record (incident, targets, balance), or nil when no match.
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


--- Evaluates a continuity option's conditions table against the faction and returns true if all conditions hold.
--- @param faction faction The faction to evaluate.
--- @param conditions table A condition_key -> value map (e.g. does_not_have_ancillary).
--- @returns boolean True when every condition holds for the faction.
function BattleEventDelegate:check_if_conditions_of_option_are_fulfilled(faction, conditions)
    local conditions_are_met = true
    for condition_key, variable in pairs(conditions) do
        if condition_key == "does_not_have_ancillary" then
            conditions_are_met = not faction:ancillary_exists(variable)
        end
    end
    return conditions_are_met
end

--- Sort comparator: orders { imperium_level, faction } pairs by descending imperium level.
--- @param a table A {imperium_level number, faction faction} pair.
--- @param b table A {imperium_level number, faction faction} pair.
--- @returns boolean True when a's imperium level is greater than b's.
local function compare_imperium_levels(a,b)
    return a[1] > b[1]
end

--- Distributes the balancing ancillary to enemy factions of the player (and likely-future enemies).
--- @param balance table A condition_key -> options map (currently only "give_ancillary").
--- @param player_faction faction The player faction whose enemies receive the ancillary.
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

--- Grants the ancillary to the top-N feuding factions sorted by imperium level (most powerful first).
--- @param feuding_factions table A CA faction_list of factions at war.
--- @param number_of_factions number How many top-imperium factions to grant the ancillary to.
--- @param ancillary string The ancillary key to grant.
function BattleEventDelegate:add_ancillary_to_feuding_factions(feuding_factions, number_of_factions, ancillary)
    local feuding_factions_by_imperium_level = {}
    for i = 0, feuding_factions:num_items() - 1 do
        local known_enemy_faction = feuding_factions:item_at(i)
        feuding_factions_by_imperium_level[i] = { known_enemy_faction:imperium_level(), known_enemy_faction }
        table.sort(feuding_factions_by_imperium_level, compare_imperium_levels)
    end
    for i=1, number_of_factions do
        cm:add_ancillary_to_faction(feuding_factions_by_imperium_level[i][2], ancillary, false)
    end
end

--- Builds the encounter Army from the cached battle event, with any pre-battle sabotage taken. Allies are picked from the triggering
--- player's subculture when it is known.
--- @returns Army A new Army instance built from the cached event.
function BattleEventDelegate:get_offensive_army()
    out("DEBUG - get_offensive_army Beginning process to generate the encounter force.")
    local player_subculture = nil
    if self.cached_player_character and self.cached_player_character.faction then
        player_subculture = self.cached_player_character:faction():subculture()
    end
    local army = Army:new_from_event(self.cached_event, player_subculture)
    --- The battle manager puts the pre-battle offers' sabotage on the army once it spawns.
    army.sabotage = self.cached_event
    return army
end


--- Exports any in-flight battle (event + spot info) for save/load.
--- @param spot_info table A spot_info record for any in-flight spot.
--- @returns table A record with cached_event + spot_info when a battle is in flight, else an empty table.
function BattleEventDelegate:export_state_as_a_table(spot_info)
    local current_battle_delegate_state = {}
    if self.is_triggered then
        current_battle_delegate_state["battle_event_delegate_is_triggered"] = true
        current_battle_delegate_state["battle_event_delegate_cached_event"] = self.cached_event
        current_battle_delegate_state["battle_event_delegate_spot_info"] = spot_info
    end
    return current_battle_delegate_state
end


--- Restores any in-flight battle from a saved campaign state. Older saves also hold a "battle_generator" entry, which is ignored, and a
--- cached event without the picker's fields, which gets the current difficulty, a random faction and the MCT battle-type pick.
--- @param previous_state table A record previously produced by export_state_as_a_table.
function BattleEventDelegate:reinstate_event_if_able(previous_state)
    self.is_triggered = previous_state["battle_event_delegate_is_triggered"]
    if self.is_triggered ~= nil and self.is_triggered == true then
        self.cached_event = previous_state["battle_event_delegate_cached_event"]
        if self.cached_event.category == nil then
            self.cached_event.difficulty = get_current_difficulty()
            self.cached_event.faction = get_random_faction()
            self.cached_event.intervention = pick_intervention_type()
        end
        local spot_info = previous_state["battle_event_delegate_spot_info"]

        local offensive_army = self:get_offensive_army()
        self.invasion_battle_manager:set_auxiliary_army_for_reset(offensive_army)
        self.invasion_battle_manager:mark_battle_forces_for_removal(offensive_army)
        self.invasion_battle_manager:reset_state_post_battle(self, "BattleSpot", spot_info, offensive_army)
        --- What the battle script was handed is not in the save, so it is handed over again.
        spot_battles.hand_to_battle(self.cached_event, nil)
    end
end

--- Constructs a fresh BattleEventDelegate wired to the given InvasionBattleManager.
--- @param invasion_battle_manager InvasionBattleManager The shared invasion battle manager.
--- @returns BattleEventDelegate A new delegate.
function BattleEventDelegate:new(invasion_battle_manager)
    local t = {
        invasion_battle_manager = invasion_battle_manager,
    }
    setmetatable(t, self)
    self.__index = self
    return t
end

return BattleEventDelegate
