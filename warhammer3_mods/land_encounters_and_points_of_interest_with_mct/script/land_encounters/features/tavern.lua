--- TavernState + TavernEventDelegate. A Tavern is a fixed place any lord can visit: its owner gets the full hub, an allied or neutral visitor
--- the hub with a choice to seize it in place of the upgrade, and an enemy of the owner a capture battle. Any visitor can make the Guild a
--- Generous Donation (features/guild_patron.lua). An unowned Tavern is claimed by the first player lord to walk in, and an AI army at war
--- with an AI owner can take it. An AI army at war with a player owner besieges it instead (core/owned_point.lua), and the owner fights it
--- with a garrison or surrenders. The mercenary hall lives in features/tavern_hall.lua, the contract board in features/tavern_contracts.lua,
--- and the bar is a spot offer site (features/spot_offers.lua).
--- TavernEventDelegate builds the Taverns from configs/coordinates.lua and routes events to them.

require("script/land_encounters/utils/common")
require("script/land_encounters/core/managers")

local tavern_data = require("script/land_encounters/configs/tavern_data")
local debug_config = require("script/land_encounters/configs/debug")
local dilemmas = require("script/land_encounters/core/dilemmas")
local spot_offers = require("script/land_encounters/features/spot_offers")
local offers_data = require("script/land_encounters/configs/spot_offers")
local tower_army = require("script/land_encounters/features/tower_army")
local tavern_hall = require("script/land_encounters/features/tavern_hall")
local tavern_contracts = require("script/land_encounters/features/tavern_contracts")
local guild_patron = require("script/land_encounters/features/guild_patron")
local boons_data = require("script/land_encounters/configs/boons")
local boons = require("script/land_encounters/features/boons")
local boon_services = require("script/land_encounters/features/boon_services")
local TavernSpot = require("script/land_encounters/core/spot").TavernSpot

local Army = require("script/land_encounters/core/army")
local OwnedPoint = require("script/land_encounters/core/owned_point")

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Constants

local FIRST_OPTION = 0

--- The hub dilemma, one per level so its description can state the level.
local EVENT_HUB_BY_LEVEL = { "land_enc_dilemma_tavern_hub_level_1", "land_enc_dilemma_tavern_hub_level_2", "land_enc_dilemma_tavern_hub_level_3" }
--- The fight-or-leave dilemma offered to a player lord entering a Tavern held by an enemy.
local EVENT_CAPTURE = "land_enc_dilemma_tavern_capture"
--- The fight-or-surrender dilemma offered to a besieged owner.
local EVENT_DEFENSE = "land_enc_dilemma_tavern_defense"

--- Choice keys of the hub, in the order the DB shows them. A guest sees Seize where the owner sees the upgrade.
local HALL_CHOICE = "FIRST"
local BOARD_CHOICE = "SECOND"
local BAR_CHOICE = "THIRD"
local UPGRADE_CHOICE = "FOURTH"
local SEIZE_CHOICE = "LEAPOI_TVN_SEIZE"
local DONATION_CHOICE = "FIFTH"
local LEAVE_CHOICE = "LEAPOI_TVN_LEAVE"

--- Payload text (campaign_payload_ui_details key) of the contract board.
local PAYLOAD_TEXT_BOARD = "dummy_land_enc_tavern_board_open"
--- Payload text of the mercenary hall.
local PAYLOAD_TEXT_HALL = "dummy_land_enc_tavern_hall_open"
--- Payload text prefix of the hall while it is closed to the visitor. The turns left are appended.
local PAYLOAD_TEXT_HALL_CLOSED = "dummy_land_enc_tavern_hall_closed_"
--- Payload text of the bar while it serves the visitor.
local PAYLOAD_TEXT_BAR_OPEN = "dummy_land_enc_tavern_bar_open"
--- Payload text prefix of the bar while it is closed to the visitor. The turns left are appended.
local PAYLOAD_TEXT_BAR_CLOSED = "dummy_land_enc_tavern_bar_closed_"
--- Payload text prefix describing the upgrade from the appended level to the next.
local PAYLOAD_TEXT_UPGRADE = "dummy_land_enc_tavern_upgrade_"
--- Payload text for the upgrade at the top level.
local PAYLOAD_TEXT_FULLY_UPGRADED = "dummy_land_enc_tavern_fully_upgraded"
--- Script context values the hub's description opens with: the scene picked for this visit, then the keeper's greeting.
local SCENE_CONTEXT = "land_enc_tavern_scene"
local GREETING_CONTEXT = "land_enc_tavern_greeting"
--- Loc key prefix of the hub's scenes, tonight's moments and the keeper's replies, e.g. ..scene_2_3, ..moment_5, ..greeting_owner_1.
local FLAVOUR_PREFIX = "campaign_localised_strings_string_land_enc_tavern_"

--- Payload text of the leave choice.
local PAYLOAD_TEXT_LEAVE = "dummy_land_enc_tavern_leave"
--- Payload text of the choice to seize the Tavern from its owner.
local PAYLOAD_TEXT_SEIZE = "dummy_land_enc_tavern_seize"
--- Payload text under an upgrade or a donation the treasury cannot pay, shared with the spot offers.
local PAYLOAD_TEXT_UNAFFORDABLE = offers_data.unaffordable_line

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Properties definition

--- Inherits the ownership helpers, war and stance checks, messages and sieges of OwnedPoint (core/owned_point.lua).
local TavernState = OwnedPoint.extend({
    --- What the Tavern's sieges use (see OwnedPoint `SIEGE`).
    SIEGE = {
        defense_event = EVENT_DEFENSE,
        messages = { besieged = "tavern_besieged", raided = "tavern_raided", defended = "tavern_successfully_defended", lost = "tavern_lost",
            surrendered = "tavern_unconditional_surrender" },
        listener_prefix = "land_enc_tavern_defense_",
        kind = "tavern",
    },
    --- Zone (region key) hosting the Tavern.
    zone_name = "",
    --- 1-based slot of the Tavern in its zone's `taverns` list. Matches the marker id suffix.
    index_in_zone = 0,
    --- {x, y} map position, read from the config on every load.
    coordinates = {},
    --- Culture shorthand of a racial Tavern (e.g. "dwf"), or "" for a neutral one. Read from the config on every load.
    culture = "",
    --- Level, 1 to 3. Survives ownership changes.
    level = 1,
    --- Owning faction key, or "" when unowned.
    controlling_faction_name = "",
    --- Owning faction subculture, used to build its capture army.
    controlling_faction_subculture = "",
    --- True when its coordinates.lua entry is marked `disabled = true`: no marker and no per-turn upkeep. Read from the config on every load.
    disabled = false,
    --- True while a capture battle (a player attacking a Tavern held by another faction) is in flight.
    is_capture_triggered = false,
    --- True while the capture dilemma a guest opened from the hub (Seize) is open, so its choice is routed back here.
    pending_capture = false,
    --- The character that opened the capture dilemma, or nil (not saved).
    visiting_enemy_character = nil,
    --- Faction of the player capturing the Tavern, kept so a reloaded battle can find them, or nil.
    visiting_enemy_faction_name = nil,
    --- What the open hub offered: the `level` it was opened at, `upgrade` when the upgrade is paid, `bar` when the bar serves the visitor, and
    --- the visiting lord's `general_cqi`. Nil when no hub is open.
    pending_hub = nil,
    --- Faction key -> the turn the bar serves that faction again, after it took an offer there.
    bar_closed_until = {},
    --- Faction key -> { turn, keys }: the offers the bar last showed that faction, shown again for the rest of that turn.
    bar_draws = {},
    --- Faction key -> the turn the mercenary hall serves that faction again, after it hired there.
    hall_closed_until = {},
    --- The mercenary hall's shared stock (see features/tavern_hall.lua), or nil until the hall first opens.
    hall_stock = nil,
    --- The open hall: the visiting lord's `general_cqi`, the visitor's `own` slots and the `slots` it showed. Nil when no hall is open.
    pending_hall = nil,
    --- The contract board's posted contracts (see features/tavern_contracts.lua), or nil until the board first opens.
    board = nil,
    --- The open board: the visiting lord's `general_cqi` and the `slots` it showed. Nil when no board is open.
    pending_board = nil,
    --- The open hedge-witch (see features/boon_services.lua), or nil when none is open.
    pending_room = nil,
    --- Lord command queue index (as a string) -> the turn that lord may gamble at the hedge-witch here again.
    gamble_until = {},

})

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Turn passing

--- Runs the once-per-round update: frees the Tavern when its owner has died, and lets an AI owner upgrade it when it can afford to.
function TavernState:update_state_given_turn_passing()
    if not self:is_occupied() then return end
    local owner = self.controlling_faction_name
    local owner_faction = self:check_if_owner_is_alive_and_return_faction()
    if not owner_faction then
        log("tavern: " .. self:describe() .. " is unowned, its owner " .. owner .. " is gone")
        self:set_controlling_faction(nil)
        return
    end
    if not owner_faction:is_human() then self:try_ai_upgrade(owner_faction, tavern_data.levels[self.level].upgrade_price) end
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Entering the Tavern

--- Routes a general entering this Tavern's marker: the hub for its owner and for allied or neutral player lords, the claim for an unowned
--- one, the capture dilemma for an enemy, a siege by an AI army at war with a player owner, and a takeover roll for an AI army at war with
--- an AI owner.
--- @param area_and_character_info table The AreaEntered context with family_member.
--- @returns string|nil The visiting faction when a Tavern dilemma was opened for it, else nil.
function TavernState:trigger_event(area_and_character_info)
    local visiting_character = area_and_character_info:family_member():character()
    local visiting_faction = visiting_character:faction()
    local visitor = visiting_faction:name()

    if is_human_and_it_is_its_turn(visiting_faction) then
        if self:is_occupied_by_same_faction(visitor) then
            log("tavern: " .. visitor .. " visits its own " .. self:describe())
            self:open_hub(visiting_faction, visiting_character:command_queue_index())
            return visitor
        elseif not self:is_occupied() then
            log("tavern: " .. visitor .. " claims the unowned " .. self:describe())
            self:show_message(visitor, "tavern_claimed")
            self:set_controlling_faction(visitor)
        elseif self:is_faction_at_war_with_owner(visiting_faction) then
            if self:character_can_trigger_dilemma(visiting_character) then
                self:offer_capture(visiting_faction, visiting_character)
                return visitor
            end
            self:show_message(visitor, "tavern_encountered")
        else
            log("tavern: " .. visitor .. " visits the " .. self:describe() .. " as a guest")
            self:open_hub(visiting_faction, visiting_character:command_queue_index())
            return visitor
        end
    elseif self:is_occupied() then
        self:on_ai_army_entered(visiting_character, visiting_faction)
    end
    return nil
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Hub

--- Turns until a room (the bar or the hall) serves a faction again.
--- @param closed_until table The room's faction key -> turn map, e.g. `bar_closed_until`.
--- @param faction_name string The faction key.
--- @returns number 0 when the room serves it now.
local function turns_left(closed_until, faction_name)
    return math.max(0, (closed_until[faction_name] or 0) - cm:turn_number())
end

--- What the Tavern's prices are multiplied by for a faction: 1, or more while the Guild still holds a failed or dropped contract against it.
--- @param faction_name string The faction key.
--- @returns number The multiplier.
function TavernState:price_factor(faction_name)
    return tavern_contracts.penalty_turns_left(faction_name) > 0 and 1 + get_mct_settings().tavern_penalty_percent / 100 or 1
end

--- A price at this Tavern for a faction: the base price times `price_factor`, to the nearest gold.
--- @param base number The price before any surcharge.
--- @param faction_name string The faction paying.
--- @returns number The gold it costs.
function TavernState:charge(base, faction_name)
    return math.floor(base * self:price_factor(faction_name) + 0.5)
end

--- Picks the hub's opening scene and the keeper's greeting for this visit (see `tavern_data.flavour`) and hands them to the description. The
--- keeper answers tonight's moment when there is one, greets the owner as the boss, and otherwise answers the scene, so the line never
--- mentions anything the scene has not set up.
--- @param is_owner boolean True when the visitor owns the Tavern.
function TavernState:show_scene(is_owner)
    local flavour = tavern_data.flavour
    local scene = self.level .. "_" .. random_number(flavour.scenes_per_level)
    local moment = random_chance(flavour.moment_chance) and random_number(flavour.moments) or nil
    if moment and (flavour.clashes[scene] or {})[moment] then moment = nil end
    local keys = { FLAVOUR_PREFIX .. "scene_" .. scene }
    if moment then keys[#keys + 1] = FLAVOUR_PREFIX .. "moment_" .. moment end
    local parts = {}
    for _, key in ipairs(keys) do
        local text = common.get_localised_string(key)
        if text ~= "" then parts[#parts + 1] = text end
    end
    common.set_context_value(SCENE_CONTEXT, table.concat(parts, " "))
    local greeting = FLAVOUR_PREFIX .. "greeting_"
        .. (moment and "moment_" .. moment or is_owner and "owner_" .. random_number(flavour.owner_greetings) or "scene_" .. scene)
    common.set_context_value(GREETING_CONTEXT, common.get_localised_string(greeting))
    log("tavern: the hub of the " .. self:describe() .. " opens with " .. table.concat(keys, ", ") .. ", then " .. greeting)
end

--- Builds and opens the hub: the mercenary hall, the contract board, the bar, the upgrade for the owner or Seize for a guest, the Generous
--- Donation, and leaving. A hall or bar closed to the visitor says for how long. An upgrade or a donation the visitor cannot afford still
--- shows its price, says why and is greyed out, and a click on it anyway is refunded.
--- @param faction faction The visiting player faction.
--- @param general_cqi number The visiting lord's command queue index.
function TavernState:open_hub(faction, general_cqi)
    self.pending_hall, self.pending_board, self.pending_room = nil, nil, nil
    local is_owner = self:is_occupied_by_same_faction(faction:name())
    local price = tavern_data.levels[self.level].upgrade_price
    local treasury = dilemmas.treasury(faction:name())
    local hall_turns = turns_left(self.hall_closed_until, faction:name())
    local bar_turns = turns_left(self.bar_closed_until, faction:name())
    local upgrade = { key = UPGRADE_CHOICE }
    if not is_owner then
        upgrade = { key = SEIZE_CHOICE, lines = { PAYLOAD_TEXT_SEIZE } }
    elseif price == nil then
        upgrade.lines = { PAYLOAD_TEXT_FULLY_UPGRADED }
        upgrade.closed = true
    else
        upgrade.lines = { PAYLOAD_TEXT_UPGRADE .. self.level }
        upgrade.gold = -price
        if treasury < price then
            upgrade.lines[2] = PAYLOAD_TEXT_UNAFFORDABLE
            upgrade.unaffordable = true
        end
    end
    local donation_offer = guild_patron.donation_offer("tavern", faction:name(), treasury)
    local donation = { key = DONATION_CHOICE, lines = { donation_offer.line }, closed = not donation_offer.price }
    if donation_offer.price then
        donation.gold = -donation_offer.price
        if not donation_offer.affordable then
            donation.lines[2] = PAYLOAD_TEXT_UNAFFORDABLE
            donation.unaffordable = true
        end
    end
    local choices = {
        { key = HALL_CHOICE, lines = { hall_turns == 0 and PAYLOAD_TEXT_HALL or PAYLOAD_TEXT_HALL_CLOSED .. hall_turns }, closed = hall_turns > 0 },
        { key = BOARD_CHOICE, lines = { PAYLOAD_TEXT_BOARD } },
        { key = BAR_CHOICE, lines = { bar_turns == 0 and PAYLOAD_TEXT_BAR_OPEN or PAYLOAD_TEXT_BAR_CLOSED .. bar_turns }, closed = bar_turns > 0 },
        upgrade,
        donation,
        { key = LEAVE_CHOICE, lines = { PAYLOAD_TEXT_LEAVE } },
    }
    --- The hedge-witch, while boons and curses are on. Closed for a lord with no curse to lift.
    local witch = false
    if boons.enabled() then
        witch = boon_services.has_curse(tower_army.character(general_cqi))
        choices[#choices + 1] = { key = boons_data.witch_room.open_choice, lines = { boon_services.line(witch and "witch_room" or "witch_nothing") },
            closed = not witch }
    end
    self.pending_hub = { level = self.level, upgrade = upgrade.gold ~= nil and not upgrade.unaffordable, seize = not is_owner,
        donation = donation_offer.affordable == true, hall = hall_turns == 0, bar = bar_turns == 0, witch = witch, general_cqi = general_cqi }
    log("tavern: hub of the " .. self:describe() .. " for " .. faction:name() .. " (owner " .. tostring(is_owner) .. ", treasury " .. treasury
        .. ", upgrade " .. (self.pending_hub.upgrade and ("for " .. price .. " gold") or "unavailable") .. ", hall " .. (hall_turns == 0 and "open" or "closed for " .. hall_turns
        .. " turns") .. ", bar " .. (bar_turns == 0 and "open" or "closed for " .. bar_turns .. " turns") .. ", donation "
        .. (self.pending_hub.donation and ("for " .. donation_offer.price .. " gold") or "unavailable") .. ")")
    self:show_owner_in_dilemmas()
    self:show_scene(is_owner)
    dilemmas.launch(EVENT_HUB_BY_LEVEL[self.level], choices, faction:name())
end

--- Opens the bar for a lord: 3 offers acting at the Tavern's level, priced at the campaign difficulty, a quarter less for the owner, and
--- more while the faction has failed one of the Tavern's contracts.
--- @param faction_name string The visiting faction.
--- @param general_cqi number The visiting lord's command queue index.
--- @returns boolean True when the bar opened, false when the lord is gone.
function TavernState:open_bar(faction_name, general_cqi)
    local character = tower_army.character(general_cqi)
    if not character then
        log("tavern: lord " .. tostring(general_cqi) .. " of " .. faction_name .. " is gone, so the bar does not open")
        return false
    end
    local share = (self:is_occupied_by_same_faction(faction_name) and tavern_data.owner_price_share or 1) * self:price_factor(faction_name)
    log("tavern: " .. faction_name .. " opens the bar of the " .. self:describe() .. " at price share " .. share)
    --- The bar shows a faction the same offers for the rest of the turn, so going back to the hub and in again does not draw new ones.
    local draw = self.bar_draws[faction_name]
    local keys = draw and draw.turn == cm:turn_number() and draw.keys or nil
    local shown = spot_offers.open_site(character, character:faction(), offers_data.tavern, nil, { zone = self.zone_name, index = self.index_in_zone,
        difficulty = DIFFICULTY_KEYS[self.level], price_difficulty = get_current_difficulty(), price_share = share, keys = keys })
    self.bar_draws[faction_name] = { turn = cm:turn_number(), keys = shown }
    return true
end

--- Applies a hub choice: the mercenary hall, the contract board or the bar opens, the upgrade raises the level, which the dilemma payload
--- already charged, or a guest's Seize offers the capture battle. A paid donation is handed back to the delegate, which raises every Tavern.
--- @param choice_key string The chosen choice key.
--- @param faction_name string The faction that chose.
--- @returns boolean True when the faction paid for a Generous Donation.
function TavernState:resolve_hub_choice(choice_key, faction_name)
    local hub = self.pending_hub
    self.pending_hub = nil
    log("tavern: " .. faction_name .. " chose " .. tostring(choice_key) .. " in the hub of the " .. self:describe())
    if not hub then return false end
    --- A greyed-out paid choice clicked anyway was charged by its payload, so the gold goes back.
    dilemmas.refund(faction_name, EVENT_HUB_BY_LEVEL[hub.level], choice_key)
    if choice_key == HALL_CHOICE and hub.hall then
        tavern_hall.open(self, cm:get_faction(faction_name), hub.general_cqi)
    elseif choice_key == BOARD_CHOICE then
        tavern_contracts.open(self, cm:get_faction(faction_name), hub.general_cqi)
    elseif choice_key == BAR_CHOICE and hub.bar then
        self:open_bar(faction_name, hub.general_cqi)
    elseif choice_key == boons_data.witch_room.open_choice and hub.witch then
        self:open_witch(faction_name, hub.general_cqi)
    elseif choice_key == SEIZE_CHOICE and hub.seize then
        self:offer_capture(cm:get_faction(faction_name), tower_army.character(hub.general_cqi))
    elseif choice_key == DONATION_CHOICE and hub.donation then
        return true
    elseif choice_key == UPGRADE_CHOICE and hub.upgrade then
        local before = self.level
        self:set_level(self.level + 1)
        log("tavern: " .. self:describe() .. " upgraded from level " .. before .. " to " .. self.level)
        self:show_message(self.controlling_faction_name, "tavern_levelled_up_level_" .. self.level)
    end
    return false
end

--- Opens the hedge-witch for a lord: a quarter off for the owner, more while the faction has failed one of the Guild's contracts.
--- @param faction_name string The visiting faction.
--- @param general_cqi number The visiting lord's command queue index.
function TavernState:open_witch(faction_name, general_cqi)
    local character = tower_army.character(general_cqi)
    if not character then return end
    local share = self:is_occupied_by_same_faction(faction_name) and boons_data.owner_price_share or 1
    local gamble_turns = turns_left(self.gamble_until, tostring(general_cqi))
    --- A cooldown that has run out is forgotten, so the save does not keep it.
    if gamble_turns == 0 then self.gamble_until[tostring(general_cqi)] = nil end
    self.pending_room = boon_services.open_witch(character, faction_name, function(base) return self:charge(base * share, faction_name) end, gamble_turns)
end

--- Applies a hedge-witch choice. A gamble closes the gambles to that lord here for the room's cooldown. The room then opens again for the
--- same lord while they carry a curse, and Back, or a lord with no curse left, goes back to the hub.
--- @param choice_key string The chosen choice key.
--- @param faction_name string The faction that chose.
function TavernState:resolve_witch_choice(choice_key, faction_name)
    local open_room = self.pending_room
    self.pending_room = nil
    if not open_room then return end
    local action, slot, character = boon_services.resolve(open_room, faction_name, boons_data.witch_room.dilemma, choice_key)
    if slot and slot.kind == "gamble" then
        local key = tostring(open_room.cqi)
        self.gamble_until[key] = cm:turn_number() + boons_data.witch_room.gamble_cooldown
        log("tavern: lord " .. key .. " may gamble at the " .. self:describe() .. " again on turn " .. self.gamble_until[key])
    end
    character = character or tower_army.character(open_room.cqi)
    if action == "reopen" and boon_services.has_curse(character) then
        self:open_witch(faction_name, open_room.cqi)
    elseif character then
        self:open_hub(cm:get_faction(faction_name), open_room.cqi)
    end
end

--- Opens the fight-or-leave capture dilemma for a lord of another faction (an enemy walking in, or a guest choosing Seize), saying what
--- taking the Tavern would cost.
--- @param faction faction The lord's faction.
--- @param character character|nil The lord.
function TavernState:offer_capture(faction, character)
    self.visiting_enemy_character = character
    self.visiting_enemy_faction_name = faction:name()
    self.pending_capture = true
    self:show_capture_terms(faction)
    log("tavern: " .. faction:name() .. " may seize the " .. self:describe() .. " from " .. self.controlling_faction_name)
    cm:trigger_dilemma(faction:name(), EVENT_CAPTURE)
end

--- Sets the level (clamped to 1-3) and swaps the map marker to that level's skin.
--- @param level number The new level.
function TavernState:set_level(level)
    level = math.max(1, math.min(#tavern_data.levels, level))
    if level == self.level then return end
    self.level = level
    self:sync_marker()
end

--- Shows the marker at the current level, or removes it when Taverns are removed in MCT or this one is disabled in the config.
function TavernState:sync_marker()
    if not get_mct_settings().enable_taverns or self.disabled then
        TavernSpot.remove_marker(self.zone_name, self.index_in_zone)
    else
        TavernSpot.replace_marker(self.zone_name, self.index_in_zone, self.coordinates, self.level)
    end
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Capture

--- Applies the player's capture choice: fight the owner's army for the Tavern, or leave it.
--- @param choice number The 0-based choice index.
--- @param invasion_battle_manager InvasionBattleManager The shared invasion battle manager.
function TavernState:resolve_capture_choice(choice, invasion_battle_manager)
    self.pending_capture = false
    log("tavern: " .. tostring(self.visiting_enemy_faction_name) .. " chose " .. (choice == FIRST_OPTION and "to attack" or "to leave") .. " the " .. self:describe())
    if choice ~= FIRST_OPTION then
        self.visiting_enemy_character = nil
        self.visiting_enemy_faction_name = nil
        return
    end
    self.is_capture_triggered = true
    local defender_army = self:get_defensive_army()
    if not self.visiting_enemy_character then
        self.visiting_enemy_character = cm:get_closest_character_to_position_from_faction(self.visiting_enemy_faction_name, self.coordinates[1], self.coordinates[2], true, false, false)
    end
    if invasion_battle_manager:can_generate_battle(defender_army, self.coordinates) then
        log("tavern: capture battle at level " .. self.level .. " difficulty against " .. self.controlling_faction_name)
        invasion_battle_manager:generate_battle(defender_army, self.visiting_enemy_character, self.coordinates)
        invasion_battle_manager:await_battle(self, "TavernSpot", nil, defender_army)
    else
        --- No spawn point for the defenders, so the Tavern is taken without a fight.
        log("tavern: no room for the defenders, so the Tavern is taken without a battle")
        self:trigger_event_given_battle_result(true)
    end
end

--- Resolves a capture battle: the player takes the Tavern on a win, and is repelled on a loss.
--- @param player_won_battle boolean True when the player was victorious.
function TavernState:trigger_event_given_battle_result(player_won_battle)
    if self.is_capture_triggered then
        local attacker = self.visiting_enemy_faction_name
        log("tavern: capture battle for the " .. self:describe() .. " " .. (player_won_battle and "won" or "lost") .. " by " .. tostring(attacker))
        if player_won_battle then
            self:show_message(attacker, "tavern_captured")
            self:charge_capture_relations(attacker)
            self:set_controlling_faction(attacker)
        else
            self:show_message(attacker, "tavern_capture_repelled")
        end
    end
    self.is_capture_triggered = false
    self.visiting_enemy_character = nil
    self.visiting_enemy_faction_name = nil
end

--- Builds the army that holds the Tavern against a capturing player: the owner's subculture at the difficulty of the Tavern's level.
--- @returns Army A new Army for the defender, or an empty table when the Tavern is unowned.
function TavernState:get_defensive_army()
    if not self:is_occupied() then return {} end
    return Army:new_from_subculture_and_level(self.controlling_faction_subculture, self.level, "tavern")
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Dilemma choices

--- Routes a Tavern dilemma choice (hub, hall, board, capture or defense).
--- @param dilemma_choice_and_faction_info table The DilemmaChoiceMadeEvent context.
--- @param invasion_battle_manager InvasionBattleManager The shared invasion battle manager.
--- @returns boolean True when the faction paid for a Generous Donation in the hub.
function TavernState:trigger_dilemma_event_given_choice(dilemma_choice_and_faction_info, invasion_battle_manager)
    local dilemma, faction_name = dilemma_choice_and_faction_info:dilemma(), dilemma_choice_and_faction_info:faction():name()
    if dilemma == EVENT_CAPTURE then
        self:resolve_capture_choice(dilemma_choice_and_faction_info:choice(), invasion_battle_manager)
    elseif dilemma == EVENT_DEFENSE then
        self:resolve_defense_choice(dilemma_choice_and_faction_info:choice(), invasion_battle_manager)
    elseif dilemma == tavern_hall.DILEMMA then
        tavern_hall.resolve(self, faction_name, dilemma_choice_and_faction_info:choice_key())
    elseif dilemma == boons_data.witch_room.dilemma then
        self:resolve_witch_choice(dilemma_choice_and_faction_info:choice_key(), faction_name)
    elseif dilemma == tavern_contracts.DILEMMA then
        tavern_contracts.resolve(self, faction_name, dilemma_choice_and_faction_info:choice_key(), invasion_battle_manager)
    else
        return self:resolve_hub_choice(dilemma_choice_and_faction_info:choice_key(), faction_name)
    end
    return false
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Helpers

--- A short name for the log, e.g. "level 2 dwf Tavern empire 1".
--- @returns string The description.
function TavernState:describe()
    return "level " .. self.level .. " " .. (self.culture ~= "" and self.culture or "neutral") .. " Tavern " .. self.zone_name .. " " .. self.index_in_zone
end

--- The key a Tavern is found by in the delegate and in a save: its zone and slot.
--- @param zone_name string The zone's region key.
--- @param index number The 1-based slot in the zone.
--- @returns string The key, e.g. "empire|1".
local function slot_key(zone_name, index)
    return zone_name .. "|" .. tostring(index)
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Memory Management

--- Exports the Tavern's state into a flat table for save/load. Position, culture and the disabled flag come from the config on load instead.
--- @returns table A flat state record.
function TavernState:export_state_as_table()
    return {
        zone_name = self.zone_name,
        index_in_zone = self.index_in_zone,
        level = self.level,
        controlling_faction_name = self.controlling_faction_name,
        controlling_faction_subculture = self.controlling_faction_subculture,
        is_capture_triggered = self.is_capture_triggered,
        visiting_enemy_faction_name = self.visiting_enemy_faction_name or false,
        besieging_force_cqi = self.besieging_force_cqi or false,
        besieging_character_cqi = self.besieging_character_cqi or false,
        besieging_faction_name = self.besieging_faction_name or false,
        garrison_force_cqi = self.garrison_force_cqi or false,
        garrison_character_cqi = self.garrison_character_cqi or false,
        pending_hub = self.pending_hub or false,
        bar_closed_until = self.bar_closed_until,
        bar_draws = self.bar_draws,
        hall_closed_until = self.hall_closed_until,
        hall_stock = self.hall_stock or false,
        pending_hall = self.pending_hall or false,
        board = self.board or false,
        pending_board = self.pending_board or false,
        pending_room = self.pending_room or false,
        gamble_until = self.gamble_until,
    }
end

--- Restores the Tavern's saved state on top of its config. Records from before Tavern sieges have no siege or garrison fields, so they load
--- without a siege or a defense in flight.
--- @param previous_state table A record previously produced by export_state_as_table.
function TavernState:reinstate(previous_state)
    self.level = previous_state.level or 1
    self.controlling_faction_name = previous_state.controlling_faction_name or ""
    self.controlling_faction_subculture = previous_state.controlling_faction_subculture or ""
    self.is_capture_triggered = previous_state.is_capture_triggered == true
    self.visiting_enemy_faction_name = previous_state.visiting_enemy_faction_name or nil
    self.besieging_force_cqi = previous_state.besieging_force_cqi or nil
    self.besieging_character_cqi = previous_state.besieging_character_cqi or nil
    self.besieging_faction_name = previous_state.besieging_faction_name or nil
    self.garrison_force_cqi = previous_state.garrison_force_cqi or nil
    self.garrison_character_cqi = previous_state.garrison_character_cqi or nil
    self.pending_hub = previous_state.pending_hub or nil
    self.bar_closed_until = previous_state.bar_closed_until or {}
    self.bar_draws = previous_state.bar_draws or {}
    self.hall_closed_until = previous_state.hall_closed_until or {}
    self.hall_stock = previous_state.hall_stock or nil
    self.pending_hall = previous_state.pending_hall or nil
    self.board = previous_state.board or nil
    self.pending_board = previous_state.pending_board or nil
    self.pending_room = previous_state.pending_room or nil
    self.gamble_until = previous_state.gamble_until or {}
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Constructors

--- Constructs a Tavern from its config entry: its position, culture and disabled flag, at level 1 and unowned.
--- @param zone_name string The region key for the zone hosting the Tavern.
--- @param index_in_zone number 1-based slot in the zone's `taverns` list.
--- @param entry table The config entry: { coordinates, culture, initial_owner, owner_if_player, disabled }.
--- @returns TavernState A new TavernState.
function TavernState:new(zone_name, index_in_zone, entry)
    local t = {
        zone_name = zone_name,
        index_in_zone = index_in_zone,
        coordinates = entry.coordinates,
        culture = entry.culture or "",
        disabled = entry.disabled == true,
        level = 1,
        controlling_faction_name = "",
        controlling_faction_subculture = "",
        is_capture_triggered = false,
        bar_closed_until = {},
        bar_draws = {},
        hall_closed_until = {},
        gamble_until = {},
    }
    setmetatable(t, self)
    self.__index = self
    return t
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- TavernEventDelegate

local TavernEventDelegate = {
    --- Every TavernState, in zone-name and slot order.
    taverns_state = {},
    --- `slot_key` -> TavernState, for lookups by zone and slot.
    taverns_by_slot = {},
    --- Shared invasion battle manager for capture battles.
    invasion_battle_manager = {},
    --- Faction key -> { zone, index } of the Tavern whose dilemma that faction has open.
    pending_dilemma_by_faction = {},
}

--- Builds every Tavern from the config and restores the saved ones. A Tavern in the config but not in the save (a new campaign, a save from
--- before Taverns, or a Tavern added since) starts at level 1 with its config owner. A capture or defense battle in flight in the save is
--- awaited again.
--- Then every marker is shown or removed.
--- @param points_of_interest table The campaign's points of interest by zone, from configs/coordinates.lua.
--- @param saved table|nil A record previously produced by export_state_as_table, or nil.
function TavernEventDelegate:initialize(points_of_interest, saved)
    local saved_by_slot = {}
    for _, record in ipairs((saved and saved.taverns) or {}) do
        saved_by_slot[slot_key(record.zone_name, record.index_in_zone)] = record
    end
    local zone_names = {}
    for zone_name, zone in pairs(points_of_interest or {}) do
        if zone.taverns and #zone.taverns > 0 then zone_names[#zone_names + 1] = zone_name end
    end
    table.sort(zone_names)

    self.taverns_state, self.taverns_by_slot = {}, {}
    local restored = 0
    for _, zone_name in ipairs(zone_names) do
        for i, entry in ipairs(points_of_interest[zone_name].taverns) do
            local tavern = TavernState:new(zone_name, i, entry)
            local record = saved_by_slot[slot_key(zone_name, i)]
            if record then
                tavern:reinstate(record)
                restored = restored + 1
            else
                tavern:set_controlling_faction(OwnedPoint.initial_owner(entry))
            end
            self.taverns_state[#self.taverns_state + 1] = tavern
            self.taverns_by_slot[slot_key(zone_name, i)] = tavern
            if tavern:has_garrison() then
                tavern:listen_for_defense_result()
            elseif tavern.is_capture_triggered then
                local defensive_army = tavern:get_defensive_army()
                self.invasion_battle_manager:set_auxiliary_army_for_reset(defensive_army)
                self.invasion_battle_manager:await_battle(tavern, "TavernSpot", nil, defensive_army)
            end
        end
    end
    self.pending_dilemma_by_faction = (saved and saved.pending_dilemma_by_faction) or {}
    tavern_contracts.restore_state(saved and saved.contracts)
    guild_patron.restore_state("tavern", saved and saved.patrons)
    tavern_contracts.rearm_battles(self)
    tavern_contracts.watch_hunt_battles()
    log("tavern: " .. #self.taverns_state .. " Taverns in " .. #zone_names .. " zones (" .. restored .. " restored, "
        .. (#self.taverns_state - restored) .. " new)")
    self:sync_markers()
end

--- Shows every Tavern marker at its level when Taverns are enabled in MCT, and removes them when they are removed. Runs on every load, so
--- changing the setting takes effect the next time a save is loaded. The debug `tavern_level` switch (configs/debug.lua) sets every Tavern to
--- that level first.
function TavernEventDelegate:sync_markers()
    local forced_level = debug_config.tavern_level[1]
    for _, tavern in ipairs(self.taverns_state) do
        if forced_level then
            log("tavern: debug tavern_level sets the " .. tavern:describe() .. " to level " .. forced_level)
            tavern.level = math.max(1, math.min(#tavern_data.levels, forced_level))
        end
        tavern:sync_marker()
    end
end

--- Ticks every Tavern. The FactionTurnStart listener calls this once per round. Removed or disabled Taverns do not tick.
function TavernEventDelegate:update_state_given_turn_passing()
    if not get_mct_settings().enable_taverns then return end
    for _, tavern in ipairs(self.taverns_state) do
        if not tavern.disabled then tavern:update_state_given_turn_passing() end
    end
end

--- Finds a Tavern by its zone and slot.
--- @param zone_name string The zone's region key.
--- @param index number The 1-based slot in the zone.
--- @returns TavernState The Tavern, or nil when none matches.
function TavernEventDelegate:find(zone_name, index)
    return self.taverns_by_slot[slot_key(zone_name, index)]
end

--- Dispatches the Tavern-entered event to the matching Tavern and remembers it when a dilemma opens.
--- @param area_and_character_info table The AreaEntered context with family_member.
--- @param spot_info table The spot_info record for the triggered Tavern.
function TavernEventDelegate:trigger_event(area_and_character_info, spot_info)
    if not get_mct_settings().enable_taverns then return end
    local tavern = self:find(spot_info.zone.name, spot_info.spot_index)
    local visitor = tavern and not tavern.disabled and tavern:trigger_event(area_and_character_info)
    if visitor then
        self.pending_dilemma_by_faction[visitor] = { zone = tavern.zone_name, index = tavern.index_in_zone }
    end
end

--- Keeps routing a faction's Tavern dilemma choices to a Tavern while it has its hub, hall or board open, and stops once none is.
--- @param faction_name string The visiting faction.
--- @param tavern TavernState The Tavern it visits.
function TavernEventDelegate:keep_route(faction_name, tavern)
    local open = tavern.pending_hub ~= nil or tavern.pending_hall ~= nil or tavern.pending_board ~= nil or tavern.pending_room ~= nil or tavern.pending_capture
    self.pending_dilemma_by_faction[faction_name] = open and { zone = tavern.zone_name, index = tavern.index_in_zone } or nil
end

--- Dispatches a Tavern dilemma choice to the Tavern that opened the choosing faction's dilemma, and keeps routing to it while that Tavern
--- has the hub, the hall or the board open again.
--- @param dilemma_choice_and_faction_info table The DilemmaChoiceMadeEvent context.
function TavernEventDelegate:trigger_dilemma_event_given_choice(dilemma_choice_and_faction_info)
    local faction_name = dilemma_choice_and_faction_info:faction():name()
    local pending = self.pending_dilemma_by_faction[faction_name]
    self.pending_dilemma_by_faction[faction_name] = nil
    local tavern = pending and self:find(pending.zone, pending.index)
    if tavern then
        if tavern:trigger_dilemma_event_given_choice(dilemma_choice_and_faction_info, self.invasion_battle_manager) then
            guild_patron.donate("tavern", faction_name, self.taverns_state, tavern.coordinates)
        end
        self:keep_route(faction_name, tavern)
    end
end

--- Handles a faction leaving a Tavern's bar. Taking an offer closes the bar to that faction for the MCT `tavern_cooldown` turns. Going back reopens the
--- hub for the same lord.
--- @param faction_name string The faction that left the bar.
--- @param site table The closed spot offer site, with its `tavern` { zone, index } and `general_cqi`.
--- @param took boolean True when an offer was taken.
function TavernEventDelegate:bar_closed(faction_name, site, took)
    local tavern = self:find(site.tavern.zone, site.tavern.index)
    if not tavern then return end
    if took then
        tavern.bar_closed_until[faction_name] = cm:turn_number() + get_mct_settings().tavern_cooldown
        log("tavern: the bar of the " .. tavern:describe() .. " is closed to " .. faction_name .. " until turn " .. tavern.bar_closed_until[faction_name])
        return
    end
    log("tavern: " .. faction_name .. " goes back to the hub of the " .. tavern:describe())
    tavern:open_hub(cm:get_faction(faction_name), site.general_cqi)
    self:keep_route(faction_name, tavern)
end

--- Settles a faction's contract whose mission ended (see features/tavern_contracts.lua).
--- @param faction_name string The faction whose mission ended.
--- @param mission_key string The mission key.
--- @param outcome string "succeeded", "failed" or "cancelled".
function TavernEventDelegate:on_contract_ended(faction_name, mission_key, outcome)
    tavern_contracts.on_mission_ended(self, faction_name, mission_key, outcome)
end

--- A lord walked onto a marked spot's marker (see features/tavern_contracts.lua).
--- @param character character The lord.
--- @param marker_ref string The marker type's key.
--- @param instance_ref string The marker's instance.
function TavernEventDelegate:on_mark_entered(character, marker_ref, instance_ref)
    tavern_contracts.on_mark_entered(self, character, marker_ref, instance_ref)
end

--- At a faction's turn start, voids its contracts that can no longer be met and keeps its bounty lords at war with it alone, then checks the
--- sieges on its Taverns. Opens at most one defense dilemma per turn. While Taverns are removed in MCT, or for a disabled Tavern, a siege is
--- lifted instead, so the besiegers are not held for good.
--- @param faction_name string The faction whose turn starts.
function TavernEventDelegate:on_faction_turn_start(faction_name)
    tavern_contracts.on_faction_turn_start(self, faction_name)
    local enabled = get_mct_settings().enable_taverns
    for _, tavern in ipairs(self.taverns_state) do
        if not enabled or tavern.disabled then
            if tavern.besieging_force_cqi and tavern:is_occupied_by_same_faction(faction_name) then tavern:clear_siege_and_garrison() end
        elseif tavern:check_siege_at_turn_start(faction_name) then
            self.pending_dilemma_by_faction[faction_name] = { zone = tavern.zone_name, index = tavern.index_in_zone }
            return
        end
    end
end

--- Exports every Tavern plus the delegate's own state for the save/load callbacks.
--- @returns table A record with `taverns` (array of state records), `pending_dilemma_by_faction`, the `contracts` held and the `patrons`.
function TavernEventDelegate:export_state_as_table()
    local records = {}
    for _, tavern in ipairs(self.taverns_state) do
        records[#records + 1] = tavern:export_state_as_table()
    end
    return { taverns = records, pending_dilemma_by_faction = self.pending_dilemma_by_faction, contracts = tavern_contracts.export_state(),
        patrons = guild_patron.export_state("tavern") }
end

--- Constructs a fresh TavernEventDelegate wired to the given InvasionBattleManager. Taverns are built by `initialize` at first tick.
--- @param invasion_battle_manager InvasionBattleManager The shared invasion battle manager.
--- @returns TavernEventDelegate A new delegate with no Taverns yet.
function TavernEventDelegate:new(invasion_battle_manager)
    local t = {
        taverns_state = {},
        taverns_by_slot = {},
        pending_dilemma_by_faction = {},
        invasion_battle_manager = invasion_battle_manager,
    }
    setmetatable(t, self)
    self.__index = self
    return t
end

return TavernEventDelegate
