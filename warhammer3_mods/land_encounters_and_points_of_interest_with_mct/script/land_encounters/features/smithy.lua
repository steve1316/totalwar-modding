--- SmithyState + SmithyEventDelegate. SmithyState owns the per-smithy lifecycle: the forge (free picks, paid commissions, upgrades),
--- tribute and AI items, sieges and player-fought defenses, reclamation battles, AI takeovers, and missions. SmithyEventDelegate is the
--- manager that routes events to the right SmithyState.

require("script/land_encounters/utils/common")
require("script/land_encounters/core/managers")

local smithy_data = require("script/land_encounters/configs/smithy_data")
local item_pool = require("script/land_encounters/core/item_pool")
local SmithySpot = require("script/land_encounters/core/spot").SmithySpot

local Army = require("script/land_encounters/core/army")

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Constants

local FIRST_OPTION = 0

local EVENT_IMAGE_ID_LOCATION_OF_INTEREST = 1017

--- The forge dilemma opened when the owner visits, one per forge level so the description can state the level.
local EVENT_FORGE_BY_LEVEL = { "land_enc_dilemma_smithy_forge_level_1", "land_enc_dilemma_smithy_forge_level_2", "land_enc_dilemma_smithy_forge_level_3" }

--- Every forge dilemma key, including the level-less one a dilemma opened by an earlier build of the forge may still use.
local FORGE_EVENTS = {
    ["land_enc_dilemma_smithy_forge"] = true,
    ["land_enc_dilemma_smithy_forge_level_1"] = true,
    ["land_enc_dilemma_smithy_forge_level_2"] = true,
    ["land_enc_dilemma_smithy_forge_level_3"] = true,
}
--- The dilemma offered to a player entering an enemy-owned smithy.
local EVENT_RECLAMATION = "land_enc_dilemma_smithy_reclamation"
--- The fight-or-surrender dilemma offered to a besieged owner.
local EVENT_DEFENSE = "land_enc_dilemma_smithy_defense"

--- Visit dilemmas from before the forge rework. Only resolved when one is still open in an older save.
local LEGACY_VISIT_EVENTS = {
    ["land_enc_dilemma_smithy_visit_level_1"] = 1,
    ["land_enc_dilemma_smithy_visit_level_2"] = 2,
    ["land_enc_dilemma_smithy_visit_level_3"] = 3,
}

--- Choice keys of the forge dilemma: three free picks, the commission and the upgrade.
local FORGE_CHOICE_KEYS = { "FIRST", "SECOND", "THIRD", "FOURTH", "FIFTH" }
--- Number of free picks, which take the first choices.
local FREE_PICK_COUNT = 3
--- 1-based position of the commission choice.
local COMMISSION_CHOICE = 4
--- 1-based position of the upgrade choice.
local UPGRADE_CHOICE = 5

--- Payload text (campaign_payload_ui_details key) for a free pick while the forge cools down.
local PAYLOAD_TEXT_COOLING = "dummy_land_enc_smithy_forge_cooling"
--- Payload text for a choice that does nothing.
local PAYLOAD_TEXT_LEAVE = "dummy_land_enc_smithy_leave"
--- Payload text prefix for a commission the faction cannot afford. The forge level is appended, since the text states that level's price.
local PAYLOAD_TEXT_CANNOT_AFFORD_COMMISSION = "dummy_land_enc_smithy_cannot_afford_commission_"
--- Payload text prefix for an upgrade the faction cannot afford. The forge level is appended, since the text states that level's price.
local PAYLOAD_TEXT_CANNOT_AFFORD_UPGRADE = "dummy_land_enc_smithy_cannot_afford_upgrade_"
--- Payload text prefix describing the upgrade from the appended level to the next.
local PAYLOAD_TEXT_UPGRADE = "dummy_land_enc_smithy_upgrade_"

--- Turns between Dark Elf smithy missions for a player owner.
local MISSION_INTERVAL = 30

--- Percent chance that an AI army at war with an AI owner takes the smithy by walking onto it.
local AI_TAKEOVER_CHANCE = 26

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Properties definition

local SmithyState = {
    --- Zone (region key) hosting the smithy.
    zone_name = "",
    --- 1-based slot of the smithy inside its zone. Matches the marker id suffix.
    index_in_zone = "",
    --- {x, y} map position.
    coordinates = {},
    --- True while a reclamation battle (player attacking an enemy-owned smithy) is in flight.
    is_reclamation_triggered = false,
    --- The character that started a reclamation dilemma, or nil (not saved).
    visiting_enemy_character = nil,
    --- Faction of the player reclaiming the smithy, kept so a reloaded battle can find them, or nil.
    visiting_enemy_faction_name = nil,
    --- Force cqi of the army besieging a player-owned smithy, or nil when there is no siege.
    besieging_force_cqi = nil,
    --- Character cqi of the besieging army's general, used to hold and release it.
    besieging_character_cqi = nil,
    --- Faction of the besieging army, which takes the smithy if the defense fails.
    besieging_faction_name = nil,
    --- Force cqi of the temporary garrison fighting a defense battle, or nil.
    garrison_force_cqi = nil,
    --- Character cqi of the garrison's general, used to remove the garrison after the battle.
    garrison_character_cqi = nil,
    --- What the open forge dilemma offered: `free_picks[i]` is true for choices that give an item, `upgrade` for a paid upgrade.
    pending_forge_offer = nil,
    --- Forge level, 1 to 3. Survives ownership changes.
    level = 1,
    --- Owning faction key, or "" when unowned.
    controlling_faction_name = "",
    --- Owning faction subculture, used to build armies.
    controlling_faction_subculture = "",
    --- Turns the current owner has held the smithy.
    turns_under_control = 0,
    --- Turns left before the next free pick.
    visit_cooldown = 0
}

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Turn passing

--- Runs the once-per-round smithy update: tribute or AI items, cooldowns, missions, and auto-occupation when abandoned.
--- @param mission_manager table The CA mission_manager handle used to issue missions.
function SmithyState:update_state_given_turn_passing(mission_manager)
    local controlling_faction = self:check_if_owner_is_alive_and_return_faction()
    if controlling_faction ~= nil and self:is_occupied() then
        --- Count this turn first so periodic rewards wait a full interval instead of firing on the turn the smithy is taken.
        self.turns_under_control = self.turns_under_control + 1
        local is_player = controlling_faction:is_human()
        self:reward_owner_faction(controlling_faction, is_player)
        if is_player then
            self:update_visit_cooldown(controlling_faction:name())
            self:issue_mission_if_possible(controlling_faction, mission_manager)
        end
    else
        self:try_to_automatically_occupy_smithy_by_region_ownership_when_abandoned()
    end
end

--- Gives the owner one item from the level's free-pick rarities: every tribute interval for a player, every `ai_item_interval` for the AI.
--- AI items are offset by the smithy's slot so the AI-owned smithies do not all pay out on the same round.
--- @param controlling_faction faction The faction currently controlling this smithy.
--- @param is_player boolean True when the owner is a human faction.
function SmithyState:reward_owner_faction(controlling_faction, is_player)
    local interval = is_player and self:level_data().tribute_interval or smithy_data.ai_item_interval
    local offset = is_player and 0 or self.index_in_zone
    if (self.turns_under_control + offset) % interval ~= 0 then return end
    local ancillary = item_pool.pick_items(controlling_faction:name(), self:level_data().free_pick_rarities, 1)[1]
    if ancillary ~= nil then
        cm:add_ancillary_to_faction(controlling_faction, ancillary, false)
    end
end

--- Decrements the free-pick cooldown each turn and tells the player owner when the forge is ready again.
--- @param controlling_faction string The player faction key controlling this smithy.
function SmithyState:update_visit_cooldown(controlling_faction)
    if self.visit_cooldown > 0 then
        self.visit_cooldown = self.visit_cooldown - 1
        if self.visit_cooldown == 0 then
            self:show_message(controlling_faction, "smithy_visit_available")
        end
    end
end

--- Issues a Dark Elf smithy mission to the player owner every `MISSION_INTERVAL` turns. Other subcultures have no missions yet.
--- @param controlling_faction faction The player faction controlling this smithy.
--- @param mission_manager table The CA mission_manager handle used to issue missions.
function SmithyState:issue_mission_if_possible(controlling_faction, mission_manager)
    if self.turns_under_control % MISSION_INTERVAL ~= 0 then return end
    local subculture_missions = smithy_data.missions_by_subculture[self.controlling_faction_subculture]
    if subculture_missions == nil or #subculture_missions == 0 then return end
    local smithy_mission = subculture_missions[random_number(#subculture_missions)]
    local mm = mission_manager:new(controlling_faction:name(), smithy_mission.mission)
    mm:set_mission_issuer("CLAN_ELDERS")
    mm:add_new_objective("KILL_X_ENTITIES")
    mm:add_condition("total 7500")
    mm:set_turn_limit(15)
    mm:set_should_whitelist(false)
    for i = 1, #smithy_mission.ancillaries do
        mm:add_payload("add_ancillary_to_faction_pool{ancillary_key " .. smithy_mission.ancillaries[i] .. ";}")
    end
    mm:trigger()
end

--- When the smithy is abandoned, assigns the owning faction of the underlying region as the new controller.
function SmithyState:try_to_automatically_occupy_smithy_by_region_ownership_when_abandoned()
    local region = self:region()
    if region then
        local new_owner_by_region_occupation = region:owning_faction()
        if not new_owner_by_region_occupation:is_null_interface() then
            self:set_controlling_faction(new_owner_by_region_occupation)
        end
    end
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Entering the smithy

--- Routes a general entering this smithy's marker: the forge for its player owner, occupation or reclamation for other players, and a
--- siege or takeover for AI armies at war with the owner.
--- @param area_and_character_info table The AreaEntered context with area_key and family_member.
--- @returns boolean True when a smithy dilemma was opened.
function SmithyState:trigger_event(area_and_character_info)
    local visiting_character = area_and_character_info:family_member():character()
    local visiting_faction = visiting_character:faction()

    if is_human_and_it_is_its_turn(visiting_faction) then
        if self:is_occupied_by_same_faction(visiting_faction:name()) then
            self:open_forge(visiting_faction)
            return true
        elseif not self:is_occupied() then
            self:show_message(visiting_faction:name(), "smithy_default_occupation_level_" .. self.level)
            self:set_controlling_faction(visiting_faction:name())
        elseif self:is_faction_at_war_with_owner(visiting_faction) then
            if self:character_is_general_and_can_trigger_dilemma(visiting_character) then
                self.visiting_enemy_character = visiting_character
                self.visiting_enemy_faction_name = visiting_faction:name()
                cm:trigger_dilemma(visiting_faction:name(), EVENT_RECLAMATION)
                return true
            end
            self:show_message(visiting_faction:name(), "smithy_encountered")
        else
            --- Owned by an ally or a neutral faction: the player must be at war with the owner, or wait for it to die.
            self:show_message(visiting_faction:name(), "smithy_ally_or_neutrally_controlled")
        end
    elseif not self:is_prohibited_subculture(visiting_faction) and self:is_faction_at_war_with_owner(visiting_faction) then
        if self:is_occupied_by_player() then
            self:begin_siege(visiting_character)
        elseif random_number(100) <= AI_TAKEOVER_CHANCE then
            self:set_controlling_faction(visiting_faction:name())
        end
    end
    return false
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Forge

--- Returns the level table entry for the current forge level.
--- @returns table An entry of `smithy_data.levels`.
function SmithyState:level_data()
    return smithy_data.levels[self.level]
end

--- Builds and opens the forge dilemma for the owner: three free picks (or "cooling"), a paid commission and a paid upgrade. Choices the
--- faction cannot afford show a text line and cost nothing.
--- @param faction faction The owning player faction.
function SmithyState:open_forge(faction)
    local level = self:level_data()
    local faction_key = faction:name()
    local treasury = faction:treasury()
    local cooling = self:is_on_cooldown()
    local can_afford_commission = treasury >= level.commission.price
    local builder = cm:create_dilemma_builder(EVENT_FORGE_BY_LEVEL[self.level])
    local payload = cm:create_payload()
    local offer = { free_picks = {}, upgrade = false }

    --- Hands the payload built so far to the choice at `index` and starts a fresh one.
    local function add_choice(index)
        builder:add_choice_payload(FORGE_CHOICE_KEYS[index], payload)
        payload:clear()
    end

    local picks = cooling and {} or item_pool.pick_items(faction_key, level.free_pick_rarities, FREE_PICK_COUNT)
    for i = 1, FREE_PICK_COUNT do
        if picks[i] then
            payload:faction_ancillary_gain(faction, picks[i])
            offer.free_picks[i] = true
        else
            payload:text_display(cooling and PAYLOAD_TEXT_COOLING or PAYLOAD_TEXT_LEAVE)
        end
        add_choice(i)
    end

    local commission_items = can_afford_commission and item_pool.pick_items(faction_key, level.commission.rarities, level.commission.count) or {}
    if #commission_items > 0 then
        payload:treasury_adjustment(-level.commission.price)
        for _, ancillary in ipairs(commission_items) do
            payload:faction_ancillary_gain(faction, ancillary)
        end
    else
        payload:text_display(can_afford_commission and PAYLOAD_TEXT_LEAVE or PAYLOAD_TEXT_CANNOT_AFFORD_COMMISSION .. self.level)
    end
    add_choice(COMMISSION_CHOICE)

    if level.upgrade_price and treasury >= level.upgrade_price then
        payload:treasury_adjustment(-level.upgrade_price)
        payload:text_display(PAYLOAD_TEXT_UPGRADE .. self.level)
        offer.upgrade = true
    else
        payload:text_display(level.upgrade_price and PAYLOAD_TEXT_CANNOT_AFFORD_UPGRADE .. self.level or PAYLOAD_TEXT_LEAVE)
    end
    add_choice(UPGRADE_CHOICE)

    self.pending_forge_offer = offer
    cm:launch_custom_dilemma_from_builder(builder, faction)
end

--- Applies a forge choice. The dilemma payload already granted the items and charged the gold, so only the cooldown and level change here.
--- @param choice number The 0-based choice index.
function SmithyState:resolve_forge_choice(choice)
    local offer = self.pending_forge_offer or { free_picks = {} }
    local index = choice + 1
    if offer.free_picks[index] then
        self.visit_cooldown = self:level_data().cooldown
    elseif index == UPGRADE_CHOICE and offer.upgrade then
        self:set_level(self.level + 1)
        self:show_message(self.controlling_faction_name, "smithy_levelled_up_level_" .. self.level)
    end
    self.pending_forge_offer = nil
end

--- Sets the forge level (clamped to 1-3) and swaps the map marker to that level's skin.
--- @param level number The new level.
function SmithyState:set_level(level)
    level = math.max(1, math.min(#smithy_data.levels, level))
    if level == self.level then return end
    self.level = level
    SmithySpot.replace_marker(self.zone_name, self.index_in_zone, self.coordinates, level)
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Sieges and defense

--- Starts a siege of this player-owned smithy: the besieging army is held in place until the owner decides at their next turn start.
--- A smithy can only be besieged by one army at a time.
--- @param character character The general of the besieging AI army.
function SmithyState:begin_siege(character)
    if self.besieging_force_cqi then return end
    self.besieging_force_cqi = character:military_force():command_queue_index()
    self.besieging_character_cqi = character:command_queue_index()
    self.besieging_faction_name = character:faction():name()
    cm:disable_movement_for_character(cm:char_lookup_str(self.besieging_character_cqi))
    self:show_message(self.controlling_faction_name, "smithy_besieged")
end

--- At the owner's turn start, lifts a siege whose army is gone, or asks the owner to fight or surrender.
--- @param faction_name string The human faction whose turn is starting.
--- @returns boolean True when the defense dilemma was opened.
function SmithyState:check_siege_at_turn_start(faction_name)
    if not self.besieging_force_cqi or self:has_garrison() or not self:is_occupied_by_same_faction(faction_name) then return false end
    if not force_exists(self.besieging_force_cqi) then
        self:end_siege()
        return false
    end
    cm:trigger_dilemma(faction_name, EVENT_DEFENSE)
    return true
end

--- Applies the owner's defense choice: fight with a garrison, or surrender the smithy.
--- @param choice number The 0-based choice index.
--- @param invasion_battle_manager InvasionBattleManager The shared invasion battle manager, used to build and place the garrison.
function SmithyState:resolve_defense_choice(choice, invasion_battle_manager)
    if not self.besieging_force_cqi then return end
    if not force_exists(self.besieging_force_cqi) then
        --- The besiegers died or were removed after the dilemma opened.
        self:end_siege()
        return
    end
    if choice == FIRST_OPTION then
        self:fight_with_garrison(invasion_battle_manager)
    else
        self:release_besieger()
        self:lose_to_besieger("smithy_unconditional_surrender")
    end
end

--- Spawns a temporary garrison for the owner beside the smithy, built like a capture army at the forge level, and has it attack the besiegers.
--- When the owner has no army data or there is no room to spawn, the siege becomes a raid: the forge loses a level and the smithy stays.
--- @param invasion_battle_manager InvasionBattleManager The shared invasion battle manager, used to build and place the garrison.
function SmithyState:fight_with_garrison(invasion_battle_manager)
    local owner = self.controlling_faction_name
    local region = self:region()
    local x, y = invasion_battle_manager:find_location_for_character_to_spawn(owner, self.coordinates)
    if Army.faction_shorthand_for_subculture(self.controlling_faction_subculture) == nil or not region or x == -1 then
        self:show_message(owner, "smithy_raided")
        self:release_besieger()
        self:set_level(self.level - 1)
        self:end_siege()
        return
    end

    local garrison = Army:new_from_subculture_and_level(self.controlling_faction_subculture, self.level)
    local unit_list = invasion_battle_manager:build_unit_list(garrison)
    cm:create_force(owner, unit_list, region:name(), x, y, true, function(character_cqi, force_cqi)
        self.garrison_character_cqi = character_cqi
        self.garrison_force_cqi = force_cqi
        self:listen_for_defense_result()
        cm:force_attack_of_opportunity(force_cqi, self.besieging_force_cqi, false)
    end)
end

--- Waits for the garrison's battle and resolves the defense from its result. Other battles in the meantime are ignored.
function SmithyState:listen_for_defense_result()
    local listener_name = self:defense_listener_name()
    core:add_listener(
        listener_name,
        "BattleCompleted",
        true,
        function()
            local fought, player_won = pending_battle_result_for_faction(self.controlling_faction_name)
            if not fought then return end
            core:remove_listener(listener_name)
            self:resolve_defense_battle(player_won)
        end,
        true
    )
end

--- Removes the garrison, frees the besiegers, and keeps or loses the smithy by the battle result.
--- @param player_won boolean True when the owner's garrison won.
function SmithyState:resolve_defense_battle(player_won)
    if force_exists(self.garrison_force_cqi) then
        kill_character_quietly(self.garrison_character_cqi)
    end
    self.garrison_force_cqi = nil
    self.garrison_character_cqi = nil
    self:release_besieger()
    if player_won then
        self:show_message(self.controlling_faction_name, "smithy_successfully_defended")
        self:end_siege()
    else
        self:lose_to_besieger("smithy_lost")
    end
end

--- Hands the smithy to the besieging faction and drops the forge one level.
--- @param message string The event-feed message suffix shown to the old owner.
function SmithyState:lose_to_besieger(message)
    self:show_message(self.controlling_faction_name, message)
    local new_owner = self.besieging_faction_name
    self:end_siege()
    self:set_level(self.level - 1)
    self:set_controlling_faction(new_owner)
end

--- Returns the name of this smithy's defense-battle listener.
--- @returns string The listener name.
function SmithyState:defense_listener_name()
    return "land_enc_smithy_defense_" .. self.zone_name .. "_" .. tostring(self.index_in_zone)
end

--- Drops any siege or garrison when the smithy changes hands another way (for example its owner died): frees the besiegers, removes a
--- garrison that is still on the map, and stops waiting for its battle.
function SmithyState:clear_siege_and_garrison()
    self:release_besieger()
    self:end_siege()
    if self:has_garrison() then
        if force_exists(self.garrison_force_cqi) then
            kill_character_quietly(self.garrison_character_cqi)
        end
        core:remove_listener(self:defense_listener_name())
        self.garrison_force_cqi = nil
        self.garrison_character_cqi = nil
    end
end

--- True while a garrison defense battle is in flight.
--- @returns boolean True when a garrison is on record.
function SmithyState:has_garrison()
    return self.garrison_force_cqi ~= nil
end

--- Lets the besieging army move again, when it still exists.
function SmithyState:release_besieger()
    if self.besieging_character_cqi and force_exists(self.besieging_force_cqi) then
        cm:enable_movement_for_character(cm:char_lookup_str(self.besieging_character_cqi))
    end
end

--- Clears the siege fields.
function SmithyState:end_siege()
    self.besieging_force_cqi = nil
    self.besieging_character_cqi = nil
    self.besieging_faction_name = nil
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Reclamation

--- Applies the player's reclamation choice: fight for an enemy-owned smithy, or leave it.
--- @param choice number The 0-based choice index.
--- @param invasion_battle_manager InvasionBattleManager The shared invasion battle manager.
function SmithyState:resolve_reclamation_choice(choice, invasion_battle_manager)
    if choice ~= FIRST_OPTION then return end
    self.is_reclamation_triggered = true
    local defender_army = self:get_defensive_army()
    if not self.visiting_enemy_character then
        self.visiting_enemy_character = cm:get_closest_character_to_position_from_faction(self.visiting_enemy_faction_name, self.coordinates[1], self.coordinates[2], true, false, false)
    end
    if invasion_battle_manager:can_generate_battle(defender_army, self.coordinates) then
        invasion_battle_manager:generate_battle(defender_army, self.visiting_enemy_character, self.coordinates)
        invasion_battle_manager:mark_battle_forces_for_removal(defender_army)
        invasion_battle_manager:reset_state_post_battle(self, "SmithySpot", nil, defender_army)
    else
        --- No spawn point for the defenders, so the smithy is taken without a fight.
        self:trigger_event_given_battle_result(true)
    end
end

--- Resolves a reclamation battle: the player takes the smithy on a win, and is repelled on a loss.
--- @param player_won_battle boolean True when the player was victorious.
function SmithyState:trigger_event_given_battle_result(player_won_battle)
    if self.is_reclamation_triggered then
        if player_won_battle then
            self:show_message(self.visiting_enemy_faction_name, "smithy_successfully_reclaimed_level_" .. self.level)
            self:set_controlling_faction(self.visiting_enemy_faction_name)
        else
            self:show_message(self.visiting_enemy_faction_name, "smithy_reclaimed_repelled")
        end
    end
    self.is_reclamation_triggered = false
    self.visiting_enemy_character = nil
    self.visiting_enemy_faction_name = nil
end

--- Builds the army that holds the smithy against a reclaiming player: the owner's subculture at the difficulty of the forge level.
--- @returns Army A new Army for the defender, or an empty table when the smithy is abandoned.
function SmithyState:get_defensive_army()
    if not self:is_occupied() then return {} end
    return Army:new_from_subculture_and_level(self.controlling_faction_subculture, self.level)
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Dilemma choices

--- Routes a smithy dilemma choice (forge, reclamation, defense, or a pre-rework visit dilemma from an older save).
--- @param dilemma_choice_and_faction_info table The DilemmaChoiceMadeEvent context.
--- @param invasion_battle_manager InvasionBattleManager The shared invasion battle manager.
function SmithyState:trigger_dilemma_event_given_choice(dilemma_choice_and_faction_info, invasion_battle_manager)
    local choice = dilemma_choice_and_faction_info:choice()
    local dilemma = dilemma_choice_and_faction_info:dilemma()
    if FORGE_EVENTS[dilemma] then
        self:resolve_forge_choice(choice)
    elseif dilemma == EVENT_DEFENSE then
        self:resolve_defense_choice(choice, invasion_battle_manager)
    elseif dilemma == EVENT_RECLAMATION then
        self:resolve_reclamation_choice(choice, invasion_battle_manager)
    elseif LEGACY_VISIT_EVENTS[dilemma] then
        --- The old level 1 and 2 visits charged the upgrade through their DB payload on the first choice.
        if choice == FIRST_OPTION and LEGACY_VISIT_EVENTS[dilemma] < 3 then
            self:set_level(self.level + 1)
        else
            self.visit_cooldown = self:level_data().cooldown
        end
    end
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Helpers

--- Shows one of the smithy event-feed messages at the smithy's position.
--- @param faction_name string The faction that sees the message.
--- @param message string The message suffix, e.g. "smithy_lost" for event_feed_strings_text_title_event_land_enc_smithy_lost.
function SmithyState:show_message(faction_name, message)
    cm:show_message_event_located(faction_name,
        "event_feed_strings_text_title_event_land_enc_" .. message,
        "event_feed_strings_text_subtitle_event_land_enc_" .. message,
        "event_feed_strings_text_description_event_land_enc_" .. message,
        self.coordinates[1],
        self.coordinates[2],
        false,
        EVENT_IMAGE_ID_LOCATION_OF_INTEREST
    )
end

--- Returns the region under the smithy.
--- @returns region The region interface, or nil when the position has none.
function SmithyState:region()
    local region_data = cm:get_region_data_at_position(self.coordinates[1], self.coordinates[2])
    if region_data and not region_data:is_null_interface() and region_data:region() ~= nil then
        return region_data:region()
    end
    return nil
end

--- Resolves the controlling faction or clears ownership if the faction is dead or missing.
--- @returns faction The live controlling faction, or nil when ownership was cleared.
function SmithyState:check_if_owner_is_alive_and_return_faction()
    local controlling_faction = cm:get_faction(self.controlling_faction_name)
    if not controlling_faction or not cm:faction_is_alive(controlling_faction) then
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

--- Returns true while the free picks are cooling down.
--- @returns boolean True when visit_cooldown is positive.
function SmithyState:is_on_cooldown()
    return self.visit_cooldown > 0
end

--- Returns true when a human faction currently controls the smithy.
--- @returns boolean True when controlling_faction_name belongs to a human player.
function SmithyState:is_occupied_by_player()
    return is_human_faction_name(self.controlling_faction_name)
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

--- Sets the new controlling faction and resets turns_under_control. Any siege or garrison of the previous owner ends. Accepts a faction
--- object or faction key.
--- @param faction faction The new owner. May be a faction handle or a faction key string. Empty/nil clears ownership.
function SmithyState:set_controlling_faction(faction)
    self:clear_siege_and_garrison()
    if type(faction) == "string" then
        faction = cm:get_faction(faction)
    end
    if not faction or faction == "" then
        self.controlling_faction_name = ""
        self.controlling_faction_subculture = ""
    else
        self.controlling_faction_name = faction:name()
        self.controlling_faction_subculture = faction:subculture()
    end
    self.turns_under_control = 0
end

--- True if the character is a general in a stance that permits the smithy dilemma to trigger.
--- @param character character The character to check.
--- @returns boolean True when the character is a general in an eligible stance.
function SmithyState:character_is_general_and_can_trigger_dilemma(character)
    if not cm:char_is_general_with_army(character) then return false end
    local active_stance = character:military_force():active_stance()
    return active_stance == "MILITARY_FORCE_ACTIVE_STANCE_TYPE_DEFAULT" or active_stance == "MILITARY_FORCE_ACTIVE_STANCE_TYPE_CHANNELING" or active_stance == "MILITARY_FORCE_ACTIVE_STANCE_TYPE_AMBUSH"
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Memory Management

--- Exports the smithy's state into a flat table for save/load. Missing values are saved as false.
--- @returns table A flat state_info record suitable for the save state.
function SmithyState:export_state_as_table()
    return {
        zone_name = self.zone_name,
        index_in_zone = self.index_in_zone,
        coordinates = self.coordinates,
        is_reclamation_triggered = self.is_reclamation_triggered,
        visiting_enemy_faction_name = self.visiting_enemy_faction_name or false,
        besieging_force_cqi = self.besieging_force_cqi or false,
        besieging_character_cqi = self.besieging_character_cqi or false,
        besieging_faction_name = self.besieging_faction_name or false,
        garrison_force_cqi = self.garrison_force_cqi or false,
        garrison_character_cqi = self.garrison_character_cqi or false,
        pending_forge_offer = self.pending_forge_offer or false,
        level = self.level,
        controlling_faction_name = self.controlling_faction_name,
        controlling_faction_subculture = self.controlling_faction_subculture,
        turns_under_control = self.turns_under_control,
        visit_cooldown = self.visit_cooldown,
    }
end

--- Restores the smithy from a saved record. Records from before the forge rework have no siege or garrison fields, so they load without a
--- siege or a defense in flight.
--- @param previous_state table A record previously produced by export_state_as_table.
function SmithyState:reinstate(previous_state)
    local function value(key) return previous_state[key] or nil end
    self.zone_name = previous_state.zone_name
    self.index_in_zone = previous_state.index_in_zone
    self.coordinates = previous_state.coordinates
    self.is_reclamation_triggered = previous_state.is_reclamation_triggered == true
    self.visiting_enemy_faction_name = value("visiting_enemy_faction_name")
    self.besieging_force_cqi = value("besieging_force_cqi")
    self.besieging_character_cqi = value("besieging_character_cqi")
    self.besieging_faction_name = value("besieging_faction_name")
    self.garrison_force_cqi = value("garrison_force_cqi")
    self.garrison_character_cqi = value("garrison_character_cqi")
    self.pending_forge_offer = value("pending_forge_offer")
    self.level = previous_state.level or 1
    self.controlling_faction_name = previous_state.controlling_faction_name
    self.controlling_faction_subculture = previous_state.controlling_faction_subculture
    self.turns_under_control = previous_state.turns_under_control or 0
    self.visit_cooldown = previous_state.visit_cooldown or 0
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Constructors

--- Constructs a fresh SmithyState at the given zone + index + coordinates. Defaults to level 1, unowned, no siege or battle.
--- @param zone_name string The region key for the zone hosting the smithy.
--- @param index_in_zone number 1-based smithy slot index inside the zone.
--- @param coordinates table A {x, y} coordinate pair for the smithy's location.
--- @returns SmithyState A new SmithyState with default values.
function SmithyState:new(zone_name, index_in_zone, coordinates)
    local t = {
        zone_name = zone_name,
        index_in_zone = index_in_zone,
        coordinates = coordinates,
        is_reclamation_triggered = false,
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
--- SmithyEventDelegate

local SmithyEventDelegate = {
    --- Every SmithyState, in zone and slot order.
    smithies_state = {},
    --- CA mission_manager handle.
    mission_manager = {},
    --- Shared invasion battle manager for reclamation battles.
    invasion_battle_manager = {},
    --- Faction key -> index in `smithies_state` of the smithy whose dilemma that faction has open.
    pending_dilemma_by_faction = {}
}

--- Bootstraps a SmithyState for each smithy in the zone's initial state, mapping initial-owner to owner_if_player when the player matches.
--- @param zone_name string The region key for the zone hosting the smithies.
--- @param smithies_initial_state table An array of initial-state records (coordinates, initial_owner, owner_if_player).
function SmithyEventDelegate:generate_states(zone_name, smithies_initial_state)
    for i = 1, #smithies_initial_state do
        local smithy_state = SmithyState:new(zone_name, i, smithies_initial_state[i].coordinates)
        if is_human_faction_name(smithies_initial_state[i].initial_owner) then
            smithy_state:set_controlling_faction(smithies_initial_state[i].owner_if_player)
        else
            smithy_state:set_controlling_faction(smithies_initial_state[i].initial_owner)
        end
        table.insert(self.smithies_state, smithy_state)
    end
end

--- Ticks every SmithyState. The FactionTurnStart listener calls this once per round.
function SmithyEventDelegate:update_state_given_turn_passing()
    for i = 1, #self.smithies_state do
        self.smithies_state[i]:update_state_given_turn_passing(self.mission_manager)
    end
end

--- Checks the sieges on a human faction's smithies at its turn start. Opens at most one defense dilemma per turn.
--- @param faction_name string The human faction whose turn is starting.
function SmithyEventDelegate:on_faction_turn_start(faction_name)
    for i = 1, #self.smithies_state do
        if self.smithies_state[i]:check_siege_at_turn_start(faction_name) then
            self.pending_dilemma_by_faction[faction_name] = i
            return
        end
    end
end

--- Finds the SmithyState for a spot_info record.
--- @param spot_info table The spot_info record for a smithy marker.
--- @returns number The index in `smithies_state`, or nil when no smithy matches.
function SmithyEventDelegate:find_smithy_index(spot_info)
    for i = 1, #self.smithies_state do
        if self.smithies_state[i].zone_name == spot_info.zone.name and self.smithies_state[i].index_in_zone == spot_info.spot_index then
            return i
        end
    end
    return nil
end

--- Dispatches the smithy-entered event to the matching SmithyState and remembers it when a dilemma opens.
--- @param area_and_character_info table The AreaEntered context with area_key and family_member.
--- @param spot_info table The spot_info record for the triggered smithy.
function SmithyEventDelegate:trigger_event(area_and_character_info, spot_info)
    local index = self:find_smithy_index(spot_info)
    if index and self.smithies_state[index]:trigger_event(area_and_character_info) then
        self.pending_dilemma_by_faction[area_and_character_info:family_member():character():faction():name()] = index
    end
end

--- Dispatches a smithy dilemma choice to the smithy that opened the choosing faction's dilemma.
--- @param dilemma_choice_and_faction_info table The DilemmaChoiceMadeEvent context.
function SmithyEventDelegate:trigger_dilemma_event_given_choice(dilemma_choice_and_faction_info)
    local faction_name = dilemma_choice_and_faction_info:faction():name()
    local index = self.pending_dilemma_by_faction[faction_name]
    self.pending_dilemma_by_faction[faction_name] = nil
    if index and self.smithies_state[index] then
        self.smithies_state[index]:trigger_dilemma_event_given_choice(dilemma_choice_and_faction_info, self.invasion_battle_manager)
    end
end

--- Exports every SmithyState plus the delegate's own state for the save/load callbacks.
--- @returns table A record with `smithies` (array of state records) and `pending_dilemma_by_faction`.
function SmithyEventDelegate:export_state_as_table()
    local smithies_data = {}
    for i = 1, #self.smithies_state do
        table.insert(smithies_data, self.smithies_state[i]:export_state_as_table())
    end
    return { smithies = smithies_data, pending_dilemma_by_faction = self.pending_dilemma_by_faction }
end

--- Restores every SmithyState from a saved state and re-arms battles in flight. Saves from before the forge rework hold the smithy array
--- directly.
--- @param previous_state table A record previously produced by export_state_as_table, or an older save's smithy array.
function SmithyEventDelegate:reinstate_event_if_able(previous_state)
    local records = previous_state.smithies or previous_state
    for i = 1, #records do
        local smithy = SmithyState:new("", 0, {})
        smithy:reinstate(records[i])
        self.smithies_state[i] = smithy
        if smithy:has_garrison() then
            smithy:listen_for_defense_result()
        elseif smithy.is_reclamation_triggered then
            local defensive_army = smithy:get_defensive_army()
            self.invasion_battle_manager:set_auxiliary_army_for_reset(defensive_army)
            self.invasion_battle_manager:mark_battle_forces_for_removal(defensive_army)
            self.invasion_battle_manager:reset_state_post_battle(smithy, "SmithySpot", nil, defensive_army)
        end
    end
    self.pending_dilemma_by_faction = previous_state.pending_dilemma_by_faction or {}
end

--- Constructs a fresh SmithyEventDelegate wired to the given CA mission_manager and InvasionBattleManager.
--- @param mission_manager table The CA mission_manager handle.
--- @param invasion_battle_manager InvasionBattleManager The shared invasion battle manager.
--- @returns SmithyEventDelegate A new delegate with no smithies yet attached.
function SmithyEventDelegate:new(mission_manager, invasion_battle_manager)
    local t = {
        smithies_state = {},
        pending_dilemma_by_faction = {},
        mission_manager = mission_manager,
        invasion_battle_manager = invasion_battle_manager
    }
    setmetatable(t, self)
    self.__index = self
    return t
end

return SmithyEventDelegate
