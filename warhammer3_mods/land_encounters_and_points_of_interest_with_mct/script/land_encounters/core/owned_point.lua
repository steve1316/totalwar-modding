--- OwnedPoint: what a point of interest owned by a faction shares, Smithies and Taverns alike. It holds the owner fields' helpers, the war and
--- stance checks, the rules for AI takeovers, the owner a config entry starts with, and sieges: an AI army at war with a player owner holds
--- the point until the owner fights it with a garrison or surrenders. SmithyState and TavernState inherit from it and keep their own fields,
--- battles and dilemmas.

require("script/land_encounters/utils/common")

local realm_effects = require("script/land_encounters/core/realm_effects")
local Army = require("script/land_encounters/core/army")

local FIRST_OPTION = 0

local OwnedPoint = {
    --- Owning faction key, or "" when unowned.
    controlling_faction_name = "",
    --- Owning faction subculture, used to build its armies.
    controlling_faction_subculture = "",
    --- {x, y} map position.
    coordinates = {},
    --- Force cqi of the army besieging a player-owned point, or nil when there is no siege.
    besieging_force_cqi = nil,
    --- Character cqi of the besieging army's general, used to hold and release it.
    besieging_character_cqi = nil,
    --- Faction of the besieging army, which takes the point if the defense fails.
    besieging_faction_name = nil,
    --- Force cqi of the temporary garrison fighting a defense battle, or nil.
    garrison_force_cqi = nil,
    --- Character cqi of the garrison's general, used to remove the garrison after the battle.
    garrison_character_cqi = nil,
    --- What a class's sieges use, set by each class: the fight-or-surrender `defense_event` dilemma, the `messages` suffixes (besieged,
    --- raided, defended, lost, surrendered), the `listener_prefix` of its defense-battle listeners, and the `kind` ("smithy" or "tavern")
    --- its log lines and garrison army ids use.
    SIEGE = nil,
}

--- Relations change, in the game's dilemma steps of 10, with an owner we are not at war with when we take its point from it.
OwnedPoint.CAPTURE_RELATIONS_STEPS = -2

--- Script context value a point's dilemma text reads its owner's name from.
OwnedPoint.OWNER_CONTEXT = "land_enc_point_owner"

--- Script context value a point's capture dilemma ends with: the relations it costs to take it from an owner we are not at war with, or
--- nothing.
OwnedPoint.RELATIONS_CONTEXT = "land_enc_point_relations"

--- Loc key of that relations note.
OwnedPoint.RELATIONS_TEXT = "campaign_localised_strings_string_land_enc_point_relations_cost"

--- Subcultures that never take a point: rogue armies, savage orcs and the Border Princes.
OwnedPoint.PROHIBITED_SUBCULTURES = {
    ["wh2_main_rogue"] = true,
    ["wh_main_sc_grn_savage_orcs"] = true,
    ["wh_main_sc_teb_teb"] = true,
}

--- The owner a config entry starts with: `initial_owner`, or `owner_if_player` when a player leads the initial owner.
--- @param entry table A config entry with initial_owner and owner_if_player.
--- @returns string|nil The starting owner's faction key, or nil when the entry names none.
function OwnedPoint.initial_owner(entry)
    if entry.initial_owner and is_human_faction_name(entry.initial_owner) then return entry.owner_if_player end
    return entry.initial_owner
end

--- Returns true when any faction currently controls the point.
--- @returns boolean True when controlling_faction_name is non-empty.
function OwnedPoint:is_occupied()
    return self.controlling_faction_name ~= ""
end

--- Returns true when a human faction currently controls the point.
--- @returns boolean True when controlling_faction_name belongs to a human player.
function OwnedPoint:is_occupied_by_player()
    return is_human_faction_name(self.controlling_faction_name)
end

--- Returns true when the point is controlled by the given faction.
--- @param faction_name string The faction key to compare against.
--- @returns boolean True when controlling_faction_name equals faction_name.
function OwnedPoint:is_occupied_by_same_faction(faction_name)
    return self.controlling_faction_name == faction_name
end

--- Returns true when the visiting faction's subculture never takes points (see `PROHIBITED_SUBCULTURES`).
--- @param visiting_faction faction The visiting faction.
--- @returns boolean True when the subculture is prohibited.
function OwnedPoint:is_prohibited_subculture(visiting_faction)
    return OwnedPoint.PROHIBITED_SUBCULTURES[visiting_faction:subculture()] == true
end

--- Returns true when the visiting faction is at war with the point's owner.
--- @param visiting_faction faction The visiting faction.
--- @returns boolean True when the two factions are at war, false when the point is unowned.
function OwnedPoint:is_faction_at_war_with_owner(visiting_faction)
    local owner = cm:get_faction(self.controlling_faction_name)
    if not owner then return false end
    return owner:at_war_with(visiting_faction)
end

--- Resolves the owner, or clears ownership when the owner is dead or missing.
--- @returns faction The living owner, or nil when ownership was cleared.
function OwnedPoint:check_if_owner_is_alive_and_return_faction()
    local owner = cm:get_faction(self.controlling_faction_name)
    if not owner or not cm:faction_is_alive(owner) then
        self.controlling_faction_name = ""
        return nil
    end
    return owner
end

--- Sets the owner. Accepts a faction object or faction key. Any siege or garrison of the previous owner ends.
--- @param faction faction|string|nil The new owner. Nil, "" or a faction this campaign does not have clears ownership.
function OwnedPoint:set_controlling_faction(faction)
    self:clear_siege_and_garrison()
    if type(faction) == "string" and faction ~= "" then
        faction = cm:get_faction(faction)
    end
    if not faction or faction == "" then
        self.controlling_faction_name = ""
        self.controlling_faction_subculture = ""
    else
        self.controlling_faction_name = faction:name()
        self.controlling_faction_subculture = faction:subculture()
    end
end

--- True if the character is a general in a stance that permits the point's dilemma to trigger.
--- @param character character The character to check.
--- @returns boolean True when the character is a general in an eligible stance.
function OwnedPoint:character_can_trigger_dilemma(character)
    if not cm:char_is_general_with_army(character) then return false end
    local active_stance = character:military_force():active_stance()
    return active_stance == "MILITARY_FORCE_ACTIVE_STANCE_TYPE_DEFAULT" or active_stance == "MILITARY_FORCE_ACTIVE_STANCE_TYPE_CHANNELING" or active_stance == "MILITARY_FORCE_ACTIVE_STANCE_TYPE_AMBUSH"
end

--- Sets the owner's name for the point's next dilemma to show: its faction's screen name, or its key when it has none.
function OwnedPoint:show_owner_in_dilemmas()
    local key = self.controlling_faction_name
    local name = key ~= "" and common.get_localised_string("factions_screen_name_" .. key) or ""
    common.set_context_value(OwnedPoint.OWNER_CONTEXT, name ~= "" and name or key)
end

--- Readies the point's next capture dilemma: its owner's name, and the note it ends with, the relations it costs when the visitor is not
--- at war with the owner.
--- @param visiting_faction faction The faction that may take the point.
function OwnedPoint:show_capture_terms(visiting_faction)
    self:show_owner_in_dilemmas()
    local at_war = self:is_faction_at_war_with_owner(visiting_faction)
    common.set_context_value(OwnedPoint.RELATIONS_CONTEXT, at_war and "" or common.get_localised_string(OwnedPoint.RELATIONS_TEXT))
end

--- Takes the relations cost of a capture: an owner the taker is not at war with thinks less of it. Called before the point changes hands.
--- @param taker_name string The faction taking the point.
function OwnedPoint:charge_capture_relations(taker_name)
    local owner, taker = self:check_if_owner_is_alive_and_return_faction(), cm:get_faction(taker_name)
    if not owner or not taker or owner:at_war_with(taker) then return end
    log("point: " .. taker_name .. " takes a point from " .. self.controlling_faction_name .. " without a war")
    realm_effects.change_relations(self.controlling_faction_name, taker_name, OwnedPoint.CAPTURE_RELATIONS_STEPS)
end

--- Lets an AI owner upgrade the point: when there is a next level, the owner would keep at least the price in its treasury after paying,
--- and the kind's MCT `<kind>_ai_upgrade_chance` hits. The chance is only rolled when the owner can afford it.
--- @param owner faction The point's living AI owner.
--- @param upgrade_price number|nil The gold to reach the next level, or nil at the top level.
--- @returns boolean True when the point was upgraded.
function OwnedPoint:try_ai_upgrade(owner, upgrade_price)
    if upgrade_price == nil or owner:treasury() < upgrade_price * 2 then return false end
    if not random_chance(get_mct_settings()[self.SIEGE.kind .. "_ai_upgrade_chance"]) then return false end
    cm:treasury_mod(self.controlling_faction_name, -upgrade_price)
    self:set_level(self.level + 1)
    log("point: " .. self.controlling_faction_name .. " pays " .. upgrade_price .. " gold to raise its point in " .. self.zone_name .. " to level " .. self.level)
    return true
end

--- Shows one of the point's event-feed messages at its position.
--- @param faction_name string The faction that sees the message.
--- @param message string The message suffix, e.g. "smithy_lost" for event_feed_strings_text_title_event_land_enc_smithy_lost.
function OwnedPoint:show_message(faction_name, message)
    show_located_message(faction_name, message, self.coordinates)
end

--- Returns the region under the point.
--- @returns region The region interface, or nil when the position has none.
function OwnedPoint:region()
    return region_at(self.coordinates)
end

--- A short name for the log, e.g. "level 2 smithy zone 1". Classes with more to say override it.
--- @returns string The description.
function OwnedPoint:describe()
    return "level " .. self.level .. " " .. self.SIEGE.kind .. " " .. tostring(self.zone_name) .. " " .. tostring(self.index_in_zone)
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Sieges and defense

--- Writes a siege line to the log under the class's kind.
--- @param text string The line.
function OwnedPoint:log_siege(text)
    log(self.SIEGE.kind .. ": " .. text)
end

--- Starts a siege of this player-owned point: the besieging army is held in place until the owner decides at their next turn start. A point
--- can only be besieged by one army at a time, and only by a general at the head of an army.
--- @param character character The general of the besieging AI army.
function OwnedPoint:begin_siege(character)
    if self.besieging_force_cqi or not cm:char_is_general_with_army(character) then return end
    self.besieging_force_cqi = character:military_force():command_queue_index()
    self.besieging_character_cqi = character:command_queue_index()
    self.besieging_faction_name = character:faction():name()
    cm:disable_movement_for_character(cm:char_lookup_str(self.besieging_character_cqi))
    self:log_siege(self.besieging_faction_name .. " besieges the " .. self:describe() .. " of " .. self.controlling_faction_name .. " with force "
        .. tostring(self.besieging_force_cqi) .. ", which is held in place")
    self:show_message(self.controlling_faction_name, self.SIEGE.messages.besieged)
end

--- At the owner's turn start, lifts a siege whose army is gone, or asks the owner to fight or surrender.
--- @param faction_name string The human faction whose turn is starting.
--- @returns boolean True when the defense dilemma was opened.
function OwnedPoint:check_siege_at_turn_start(faction_name)
    if not self.besieging_force_cqi or self:has_garrison() or not self:is_occupied_by_same_faction(faction_name) then return false end
    if not force_exists(self.besieging_force_cqi) then
        self:log_siege("the army besieging the " .. self:describe() .. " is gone, so the siege is lifted")
        self:end_siege()
        return false
    end
    self:log_siege(faction_name .. " must fight for or surrender the " .. self:describe() .. " besieged by " .. tostring(self.besieging_faction_name))
    cm:trigger_dilemma(faction_name, self.SIEGE.defense_event)
    return true
end

--- Applies the owner's defense choice: fight with a garrison, or surrender the point.
--- @param choice number The 0-based choice index.
--- @param invasion_battle_manager InvasionBattleManager The shared invasion battle manager, used to build and place the garrison.
function OwnedPoint:resolve_defense_choice(choice, invasion_battle_manager)
    if not self.besieging_force_cqi then return end
    if not force_exists(self.besieging_force_cqi) then
        --- The besiegers died or were removed after the dilemma opened.
        self:log_siege("the army besieging the " .. self:describe() .. " left before the owner chose, so the siege is lifted")
        self:end_siege()
        return
    end
    self:log_siege(self.controlling_faction_name .. " chose to " .. (choice == FIRST_OPTION and "fight for" or "surrender") .. " the " .. self:describe())
    if choice == FIRST_OPTION then
        self:fight_with_garrison(invasion_battle_manager)
    else
        self:release_besieger()
        self:lose_to_besieger(self.SIEGE.messages.surrendered)
    end
end

--- Spawns a temporary garrison for the owner beside the point, built like a capture army at the point's level, and has it attack the
--- besiegers. When the owner has no army data or there is no room to spawn, the siege becomes a raid: the point loses a level and the owner
--- keeps it.
--- @param invasion_battle_manager InvasionBattleManager The shared invasion battle manager, used to build and place the garrison.
function OwnedPoint:fight_with_garrison(invasion_battle_manager)
    local owner = self.controlling_faction_name
    local region = self:region()
    local x, y = invasion_battle_manager:find_location_for_character_to_spawn(owner, self.coordinates)
    if Army.faction_shorthand_for_subculture(self.controlling_faction_subculture) == nil or not region or x == -1 then
        self:show_message(owner, self.SIEGE.messages.raided)
        self:release_besieger()
        local before = self.level
        self:set_level(self.level - 1)
        self:log_siege("no garrison can defend the " .. self:describe() .. ", so it is raided from level " .. before .. " to " .. self.level)
        self:end_siege()
        return
    end

    local garrison = Army:new_from_subculture_and_level(self.controlling_faction_subculture, self.level, self.SIEGE.kind)
    local unit_list = invasion_battle_manager:build_unit_list(garrison)
    self:log_siege("a level " .. self.level .. " garrison of " .. owner .. " attacks the army besieging the " .. self:describe())
    cm:create_force(owner, unit_list, region:name(), x, y, true, function(character_cqi, force_cqi)
        self.garrison_character_cqi = character_cqi
        self.garrison_force_cqi = force_cqi
        self:listen_for_defense_result()
        cm:force_attack_of_opportunity(force_cqi, self.besieging_force_cqi, false)
    end)
end

--- Waits for the garrison's battle and resolves the defense from its result. Other battles in the meantime are ignored.
function OwnedPoint:listen_for_defense_result()
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

--- Removes the garrison, frees the besiegers, and keeps or loses the point by the battle result.
--- @param player_won boolean True when the owner's garrison won.
function OwnedPoint:resolve_defense_battle(player_won)
    self:log_siege("the garrison of the " .. self:describe() .. " " .. (player_won and "won" or "lost") .. " its battle against " .. tostring(self.besieging_faction_name))
    if force_exists(self.garrison_force_cqi) then
        kill_character_quietly(self.garrison_character_cqi)
    end
    self.garrison_force_cqi = nil
    self.garrison_character_cqi = nil
    self:release_besieger()
    if player_won then
        self:show_message(self.controlling_faction_name, self.SIEGE.messages.defended)
        self:end_siege()
    else
        self:lose_to_besieger(self.SIEGE.messages.lost)
    end
end

--- Hands the point to the besieging faction and drops it one level.
--- @param message string The event-feed message suffix shown to the old owner.
function OwnedPoint:lose_to_besieger(message)
    self:show_message(self.controlling_faction_name, message)
    local old_owner, new_owner, before = self.controlling_faction_name, self.besieging_faction_name, self.level
    self:end_siege()
    self:set_level(self.level - 1)
    self:set_controlling_faction(new_owner)
    self:log_siege(tostring(new_owner) .. " takes the " .. self:describe() .. " from " .. old_owner .. ", which drops from level " .. before .. " to " .. self.level)
end

--- Returns the name of this point's defense-battle listener.
--- @returns string The listener name.
function OwnedPoint:defense_listener_name()
    return self.SIEGE.listener_prefix .. self.zone_name .. "_" .. tostring(self.index_in_zone)
end

--- Drops any siege or garrison when the point changes hands another way (for example its owner died): frees the besiegers, removes a
--- garrison that is still on the map, and stops waiting for its battle.
function OwnedPoint:clear_siege_and_garrison()
    if self.besieging_force_cqi then self:log_siege("the siege of the " .. self:describe() .. " ends as it changes hands") end
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
function OwnedPoint:has_garrison()
    return self.garrison_force_cqi ~= nil
end

--- Lets the besieging army move again, when it still exists.
function OwnedPoint:release_besieger()
    if self.besieging_character_cqi and force_exists(self.besieging_force_cqi) then
        cm:enable_movement_for_character(cm:char_lookup_str(self.besieging_character_cqi))
    end
end

--- Clears the siege fields.
function OwnedPoint:end_siege()
    self.besieging_force_cqi = nil
    self.besieging_character_cqi = nil
    self.besieging_faction_name = nil
end

--- Handles an AI army walking onto an owned point: an army at war with a player owner begins a siege, and one at war with an AI owner takes
--- the point on the kind's MCT `<kind>_ai_takeover_chance` roll. Prohibited subcultures and armies at peace with the owner do nothing.
--- @param character character The AI army's general.
--- @param faction faction The AI army's faction.
function OwnedPoint:on_ai_army_entered(character, faction)
    if self:is_prohibited_subculture(faction) or not self:is_faction_at_war_with_owner(faction) then return end
    if self:is_occupied_by_player() then
        self:begin_siege(character)
    elseif random_chance(get_mct_settings()[self.SIEGE.kind .. "_ai_takeover_chance"]) then
        log(self.SIEGE.kind .. ": " .. faction:name() .. " takes the " .. self:describe() .. " from " .. self.controlling_faction_name)
        self:set_controlling_faction(faction:name())
    end
end

--- Makes `class` inherit OwnedPoint, so its instances fall back to it for anything the class does not define.
--- @param class table A state class whose instances use `class` as their metatable.
--- @returns table The class.
function OwnedPoint.extend(class)
    return setmetatable(class, { __index = OwnedPoint })
end

return OwnedPoint
