--- SmithyState + SmithyEventDelegate. SmithyState owns the per-smithy lifecycle: the forge (free picks, paid commissions, upgrades),
--- tribute and AI items, reclamation battles, AI takeovers, and missions. Sieges and player-fought defenses are shared with Taverns in
--- core/owned_point.lua. SmithyEventDelegate is the manager that routes events to the right SmithyState.

require("script/land_encounters/utils/common")
require("script/land_encounters/core/managers")

local smithy_data = require("script/land_encounters/configs/smithy_data")
local round_gold = require("script/land_encounters/configs/tower_data").round_gold
local debug_config = require("script/land_encounters/configs/debug")
local item_pool = require("script/land_encounters/core/item_pool")
local SmithySpot = require("script/land_encounters/core/spot").SmithySpot
local guild_patron = require("script/land_encounters/features/guild_patron")
local dilemmas = require("script/land_encounters/core/dilemmas")
local offers_data = require("script/land_encounters/configs/spot_offers")
local boons_data = require("script/land_encounters/configs/boons")
local boons = require("script/land_encounters/features/boons")
local boon_services = require("script/land_encounters/features/boon_services")
local tower_army = require("script/land_encounters/features/tower_army")
local spot_offers = require("script/land_encounters/features/spot_offers")

local Army = require("script/land_encounters/core/army")
local OwnedPoint = require("script/land_encounters/core/owned_point")

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Constants

local FIRST_OPTION = 0

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

--- Choice keys of the forge's free picks.
local FREE_PICK_KEYS = { "FIRST", "SECOND" }
--- Choice key of Work Orders.
local ORDERS_KEY = "LEAPOI_SMT_ORDERS"
--- Choice key of the commission.
local COMMISSION_KEY = "FOURTH"
--- Choice key of the upgrade, or the legendary commission at the top level.
local UPGRADE_KEY = "FIFTH"
--- Choice key of the Generous Donation to the Smiths' Association.
local DONATION_KEY = "SIXTH"
--- Choice key of Leave, for a lord that walked onto the Smithy by accident. It does nothing.
local LEAVE_KEY = "LEAPOI_SMT_LEAVE"
--- Choice key of Rush the Forge, shown in place of the commission, the upgrade and the donation while the free picks cool.
local RUSH_KEY = "LEAPOI_SMT_RUSH"

--- Payload text (campaign_payload_ui_details key) for a choice that does nothing.
local PAYLOAD_TEXT_LEAVE = "dummy_land_enc_smithy_leave"
--- Payload text prefix of the commission, followed by the forge level, since a level 3 forge makes a pair of masterworks.
local PAYLOAD_TEXT_COMMISSION = "dummy_land_enc_smithy_commission_"
--- Payload text of the legendary commission at the top level.
local PAYLOAD_TEXT_LEGENDARY = "dummy_land_enc_smithy_legendary"
--- Payload text for a legendary commission when no legendary item suits the faction.
local PAYLOAD_TEXT_NO_LEGENDARY = "dummy_land_enc_smithy_no_legendary"
--- Payload text prefix describing the upgrade from the appended level to the next.
local PAYLOAD_TEXT_UPGRADE = "dummy_land_enc_smithy_upgrade_"
--- Payload text of Work Orders while it serves the faction.
local PAYLOAD_TEXT_ORDERS = "dummy_land_enc_smithy_orders_open"
--- Payload text prefix of Work Orders while it is closed to the faction, followed by the turns left.
local PAYLOAD_TEXT_ORDERS_CLOSED = "dummy_land_enc_smithy_orders_closed_"
--- Payload text prefix of a free pick while the forge cools, followed by the turns left.
local PAYLOAD_TEXT_COOLING = "dummy_land_enc_smithy_cooling_"
--- Payload text of Rush the Forge.
local PAYLOAD_TEXT_RUSH = "dummy_land_enc_smithy_rush"
--- Payload text under a donation the treasury cannot pay, shared with the spot offers.
local PAYLOAD_TEXT_UNAFFORDABLE = offers_data.unaffordable_line

--- The longest free-pick cooldown: the slider maximum plus the largest level offset. There is one cooling message per possible number of turns left, up to this.
local LONGEST_COOLDOWN = smithy_data.cooldown_slider_max
for _, level in ipairs(smithy_data.levels) do
    LONGEST_COOLDOWN = math.max(LONGEST_COOLDOWN, smithy_data.cooldown_slider_max + level.cooldown_offset)
end

--- Turns between Dark Elf smithy missions for a player owner.
local MISSION_INTERVAL = 30

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Properties definition

--- Inherits the ownership helpers, war and stance checks, messages and sieges of OwnedPoint (core/owned_point.lua).
local SmithyState = OwnedPoint.extend({
    --- What the smithy's sieges use (see OwnedPoint `SIEGE`).
    SIEGE = {
        defense_event = EVENT_DEFENSE,
        messages = { besieged = "smithy_besieged", raided = "smithy_raided", defended = "smithy_successfully_defended", lost = "smithy_lost",
            surrendered = "smithy_unconditional_surrender" },
        listener_prefix = "land_enc_smithy_defense_",
        kind = "smithy",
    },
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
    --- What the open forge dilemma offered: `free_picks[key]` is true for choice keys that give an item, `upgrade`, `donation`, `orders` and
    --- `rush` for the choices that do something, and the visiting lord's `general_cqi`.
    pending_forge_offer = nil,
    --- The open Temper and Break room (see features/boon_services.lua), or nil when none is open.
    pending_room = nil,
    --- Faction key -> the turn its Work Orders counter serves it again, after it took an order.
    orders_closed_until = {},
    --- Faction key -> { turn, keys }: the orders the counter showed it this turn, shown again when it comes back the same turn.
    orders_draws = {},
    --- Forge level, 1 to 3. Survives ownership changes.
    level = 1,
    --- Owning faction key, or "" when unowned.
    controlling_faction_name = "",
    --- Owning faction subculture, used to build armies.
    controlling_faction_subculture = "",
    --- Turns the current owner has held the smithy.
    turns_under_control = 0,
    --- Turns left before the next free pick.
    visit_cooldown = 0,
    --- True when its coordinates.lua entry is marked `disabled = true`: no marker and no per-turn upkeep. Read from the config on every load.
    disabled = false
})

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Turn passing

--- Returns a Smithy price scaled by the MCT `smithy_price_percent`, rounded to the gold step.
--- @param base number|nil The config price, or nil when there is none.
--- @returns number|nil The price charged, or nil.
local function smithy_price(base)
    if base == nil then return nil end
    return round_gold(base * get_mct_settings().smithy_price_percent / 100)
end

--- Returns what the Temper and Break room charges for a service: its Smithy price at the owner's share, since only the owner uses the forge.
--- @param base number The service's base gold.
--- @returns number The gold charged.
local function room_price(base)
    return round_gold(smithy_price(base) * boons_data.owner_price_share)
end

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
        else
            self:try_ai_upgrade(controlling_faction, smithy_price(self:level_data().upgrade_price))
        end
    else
        self:try_to_automatically_occupy_smithy_by_region_ownership_when_abandoned()
    end
end

--- Gives the owner one item from the level's free-pick rarities: every tribute interval (scaled by the MCT `smithy_tribute_percent`) for a
--- player, every `ai_item_interval` for the AI.
--- AI items are offset by the smithy's slot so the AI-owned smithies do not all pay out on the same round.
--- @param controlling_faction faction The faction currently controlling this smithy.
--- @param is_player boolean True when the owner is a human faction.
function SmithyState:reward_owner_faction(controlling_faction, is_player)
    local interval = smithy_data.ai_item_interval
    if is_player then interval = math.max(1, math.floor(self:level_data().tribute_interval * get_mct_settings().smithy_tribute_percent / 100 + 0.5)) end
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
            show_ready_notice(controlling_faction, "smithy_visit_available", self.coordinates)
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
            --- A cooling forge opens too, with its free picks greyed out (see `open_forge`).
            self:open_forge(visiting_faction, visiting_character)
            return true
        elseif not self:is_occupied() then
            self:show_message(visiting_faction:name(), "smithy_default_occupation_level_" .. self.level)
            self:set_controlling_faction(visiting_faction:name())
        else
            --- Owned by anyone else: the lord may fight its garrison for it. Taking it from an owner we are not at war with costs relations.
            if self:character_can_trigger_dilemma(visiting_character) then
                self.visiting_enemy_character = visiting_character
                self.visiting_enemy_faction_name = visiting_faction:name()
                self:show_capture_terms(visiting_faction)
                cm:trigger_dilemma(visiting_faction:name(), EVENT_RECLAMATION)
                return true
            end
            self:show_message(visiting_faction:name(), "smithy_encountered")
        end
    else
        self:on_ai_army_entered(visiting_character, visiting_faction)
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

--- Returns the turns the forge cools for after a free pick: the MCT `smithy_cooldown` slider plus the forge level's offset. The debug
--- `smithy_cooldown` switch (configs/debug.lua) replaces both.
--- @returns number The cooldown in turns.
function SmithyState:free_pick_cooldown()
    local forced = debug_config.smithy_cooldown[1]
    if forced then
        log("smithy: debug smithy_cooldown sets the free-pick cooldown to " .. forced)
        return forced
    end
    local slider, offset = get_mct_settings().smithy_cooldown, self:level_data().cooldown_offset
    log("smithy: free-pick cooldown " .. (slider + offset) .. " turns (slider " .. slider .. " + level offset " .. offset .. ")")
    return slider + offset
end

--- The gold Rush the Forge costs now: `rush_price_per_turn` per turn left on the free picks, times the forge level, at the Smithy's prices.
--- @returns number The gold.
function SmithyState:rush_price()
    return smithy_price(smithy_data.rush_price_per_turn * self.visit_cooldown * self.level)
end

--- Builds and opens the forge dilemma for the owner: two free picks, Work Orders, a paid commission, a paid upgrade, the Generous Donation
--- to the Smiths' Association, the Temper and Break room while boons and curses are on, and Leave. While the forge cools, the free picks are
--- greyed out with the turns left, and Rush the Forge takes the place of the commission, the upgrade and the donation. Each paid choice shows
--- its price. One the faction cannot afford says so and is greyed out, as is one with nothing to give, and Work Orders while it is closed to
--- the faction. The free picks, the room and Leave never are.
--- @param faction faction The owning player faction.
--- @param character character The visiting lord.
function SmithyState:open_forge(faction, character)
    local level = self:level_data()
    local faction_key = faction:name()
    local treasury = dilemmas.treasury(faction_key)
    local cooling = self:is_on_cooldown()
    local offer = { free_picks = {}, upgrade = false, donation = false, orders = false, rush = false, general_cqi = character:command_queue_index() }
    local choices = {}

    --- Adds a paid choice: its price card and `line`, then the `items` it gives when the treasury can pay. One the treasury cannot pay also
    --- says so and is greyed out, and is marked unaffordable so a click on it anyway is refunded.
    --- @param key string The choice key.
    --- @param price number The gold it costs.
    --- @param line string Its payload text.
    --- @param items table|nil The ancillary keys it gives.
    --- @returns boolean True when the treasury can pay.
    local function add_paid(key, price, line, items)
        local affordable = treasury >= price
        local choice = { key = key, gold = -price, lines = { line }, lines_first = true }
        if affordable then
            choice.items = items
        else
            choice.lines[2] = PAYLOAD_TEXT_UNAFFORDABLE
            choice.unaffordable = true
        end
        choices[#choices + 1] = choice
        return affordable
    end

    --- Adds a choice that does nothing, greyed out, saying why.
    --- @param key string The choice key.
    --- @param line string Its payload text.
    local function add_closed(key, line)
        choices[#choices + 1] = { key = key, lines = { line }, closed = true }
    end

    if cooling then
        for _, key in ipairs(FREE_PICK_KEYS) do add_closed(key, PAYLOAD_TEXT_COOLING .. math.min(self.visit_cooldown, LONGEST_COOLDOWN)) end
    else
        local picks = item_pool.pick_items(faction_key, level.free_pick_rarities, #FREE_PICK_KEYS)
        for i, key in ipairs(FREE_PICK_KEYS) do
            if picks[i] then
                choices[#choices + 1] = { key = key, items = { picks[i] } }
                offer.free_picks[key] = true
            else
                choices[#choices + 1] = { key = key, lines = { PAYLOAD_TEXT_LEAVE } }
            end
        end
    end

    local orders_turns = self:turns_left(self.orders_closed_until, faction_key)
    if orders_turns > 0 then
        add_closed(ORDERS_KEY, PAYLOAD_TEXT_ORDERS_CLOSED .. orders_turns)
    else
        choices[#choices + 1] = { key = ORDERS_KEY, lines = { PAYLOAD_TEXT_ORDERS } }
        offer.orders = true
    end

    local rush_price = cooling and self:rush_price() or 0
    if cooling then
        offer.rush = add_paid(RUSH_KEY, rush_price, PAYLOAD_TEXT_RUSH)
    else
        local commission = level.commission
        local commission_price = smithy_price(commission.price)
        local commission_items = treasury >= commission_price and item_pool.pick_items(faction_key, commission.rarities, commission.count) or {}
        if treasury >= commission_price and #commission_items == 0 then
            add_closed(COMMISSION_KEY, PAYLOAD_TEXT_LEAVE)
        else
            add_paid(COMMISSION_KEY, commission_price, PAYLOAD_TEXT_COMMISSION .. self.level, commission_items)
        end

        --- The fifth choice upgrades the forge, or at the top level commissions a legendary piece instead.
        if level.upgrade_price then
            offer.upgrade = add_paid(UPGRADE_KEY, smithy_price(level.upgrade_price), PAYLOAD_TEXT_UPGRADE .. self.level)
        elseif level.legendary_commission then
            local price = smithy_price(level.legendary_commission.price)
            local legendary = treasury >= price and item_pool.pick_legendary_item(faction_key)
            if treasury >= price and not legendary then
                add_closed(UPGRADE_KEY, PAYLOAD_TEXT_NO_LEGENDARY)
            else
                add_paid(UPGRADE_KEY, price, PAYLOAD_TEXT_LEGENDARY, legendary and { legendary } or nil)
            end
        else
            add_closed(UPGRADE_KEY, PAYLOAD_TEXT_LEAVE)
        end

        local donation = guild_patron.donation_offer("smithy", faction_key, treasury)
        if donation.price then
            offer.donation = add_paid(DONATION_KEY, donation.price, donation.line)
        else
            add_closed(DONATION_KEY, donation.line)
        end
    end

    if boons.enabled() then
        choices[#choices + 1] = { key = boons_data.smithy_room.open_choice, lines = { boon_services.line("smithy_room") } }
    end
    --- The panel lists choices in the order they are added, so Leave goes last.
    choices[#choices + 1] = { key = LEAVE_KEY, lines = { PAYLOAD_TEXT_LEAVE } }

    log("smithy: forge of the " .. self:describe() .. " opens for " .. faction_key .. " with lord " .. offer.general_cqi .. " (level " .. self.level
        .. ", treasury " .. treasury .. ", " .. (cooling and ("cooling for " .. self.visit_cooldown .. " turns, rush " .. rush_price .. " gold")
        or "free picks ready") .. ", work orders " .. (orders_turns > 0 and ("closed for " .. orders_turns .. " turns") or "open") .. ")")
    self.pending_forge_offer = offer
    dilemmas.launch(EVENT_FORGE_BY_LEVEL[self.level], choices, faction_key)
end

--- Opens the Work Orders counter for a lord: 3 offers acting at the forge level, priced at the campaign difficulty and the Smithy prices.
--- @param faction_name string The owning faction.
--- @param general_cqi number The visiting lord's command queue index.
--- @returns boolean True when the counter opened, false when the lord is gone.
function SmithyState:open_orders(faction_name, general_cqi)
    local character = tower_army.character(general_cqi)
    if not character then
        log("smithy: lord " .. tostring(general_cqi) .. " of " .. faction_name .. " is gone, so the Work Orders do not open")
        return false
    end
    local share = get_mct_settings().smithy_price_percent / 100
    log("smithy: " .. faction_name .. " opens the Work Orders of the " .. self:describe() .. " at level " .. self.level .. ", price share " .. share)
    --- The counter shows a faction the same orders for the rest of the turn, so going back to the forge and in again does not draw new ones.
    spot_offers.open_site(character, character:faction(), offers_data.smithy, nil, { kind = "smithy", zone = self.zone_name, index = self.index_in_zone,
        difficulty = DIFFICULTY_KEYS[self.level], price_difficulty = get_current_difficulty(), price_share = share, draws = self.orders_draws })
    return true
end

--- Applies a forge choice. The dilemma payload already granted the items and charged the gold, so only the cooldown and level change here.
--- Work Orders and the Temper and Break room open their own dilemmas, and Rush the Forge ends the cooldown and opens the full forge again. A
--- paid donation is handed back to the delegate, which raises every Smithy.
--- @param dilemma_key string The forge dilemma's key.
--- @param choice_key string The chosen choice key.
--- @returns boolean True when the faction paid for a Generous Donation.
function SmithyState:resolve_forge_choice(dilemma_key, choice_key)
    local offer = self.pending_forge_offer or { free_picks = {} }
    self.pending_forge_offer = nil
    local faction_name = self.controlling_faction_name
    log("smithy: " .. faction_name .. " chose " .. tostring(choice_key) .. " at the forge of the " .. self:describe())
    --- A greyed-out paid choice clicked anyway was charged by its payload, so the gold goes back.
    dilemmas.refund(faction_name, dilemma_key, choice_key)
    if choice_key == boons_data.smithy_room.open_choice then
        local character = tower_army.character(offer.general_cqi)
        if character then self:open_room(character, false) end
    elseif choice_key == RUSH_KEY and offer.rush then
        log("smithy: " .. faction_name .. " rushes the forge of the " .. self:describe() .. ", " .. self.visit_cooldown .. " turns early")
        self.visit_cooldown = 0
        local character = tower_army.character(offer.general_cqi)
        if character then self:open_forge(cm:get_faction(faction_name), character) end
    elseif choice_key == ORDERS_KEY and offer.orders then
        self:open_orders(faction_name, offer.general_cqi)
    elseif offer.free_picks[choice_key] then
        self.visit_cooldown = self:free_pick_cooldown()
    elseif choice_key == UPGRADE_KEY and offer.upgrade then
        self:set_level(self.level + 1)
        self:show_message(faction_name, "smithy_levelled_up_level_" .. self.level)
    end
    return choice_key == DONATION_KEY and offer.donation == true
end

--- Opens the Temper and Break room for a lord at the owner's prices.
--- @param character character The visiting lord.
--- @param rust_taken boolean True when the lord took Rust for Iron on this visit already.
function SmithyState:open_room(character, rust_taken)
    self.pending_room = boon_services.open_smithy(character, self.controlling_faction_name, room_price, rust_taken, PAYLOAD_TEXT_LEAVE)
end

--- Applies a Temper and Break choice, then opens the room again for the same lord, or closes it on Leave.
--- @param choice_key string The chosen choice key.
function SmithyState:resolve_room_choice(choice_key)
    local open_room = self.pending_room
    self.pending_room = nil
    if not open_room then return end
    local action, _, character = boon_services.resolve(open_room, self.controlling_faction_name, boons_data.smithy_room.dilemma, choice_key)
    if action == "reopen" then self:open_room(character, open_room.rust_taken) end
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
            self:charge_capture_relations(self.visiting_enemy_faction_name)
            self:set_controlling_faction(self.visiting_enemy_faction_name)
        else
            self:show_message(self.visiting_enemy_faction_name, "smithy_reclaimed_repelled")
        end
    end
    self.is_reclamation_triggered = false
    self.visiting_enemy_character = nil
    self.visiting_enemy_faction_name = nil
end

--- Builds the army that holds the smithy against a reclaiming player: the owner's subculture at the difficulty of the forge level, or of the
--- debug `smithy_fight_level` switch while it is set.
--- @returns Army A new Army for the defender, or an empty table when the smithy is abandoned.
function SmithyState:get_defensive_army()
    if not self:is_occupied() then return {} end
    local level = debug_config.smithy_fight_level[1] or self.level
    if level ~= self.level then log("smithy: debug smithy_fight_level makes the garrison fight at level " .. level) end
    return Army:new_from_subculture_and_level(self.controlling_faction_subculture, level)
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
        return self:resolve_forge_choice(dilemma, dilemma_choice_and_faction_info:choice_key())
    elseif dilemma == boons_data.smithy_room.dilemma then
        self:resolve_room_choice(dilemma_choice_and_faction_info:choice_key())
    elseif dilemma == EVENT_DEFENSE then
        self:resolve_defense_choice(choice, invasion_battle_manager)
    elseif dilemma == EVENT_RECLAMATION then
        self:resolve_reclamation_choice(choice, invasion_battle_manager)
    elseif LEGACY_VISIT_EVENTS[dilemma] then
        --- The old level 1 and 2 visits charged the upgrade through their DB payload on the first choice.
        if choice == FIRST_OPTION and LEGACY_VISIT_EVENTS[dilemma] < 3 then
            self:set_level(self.level + 1)
        else
            self.visit_cooldown = self:free_pick_cooldown()
        end
    end
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Helpers

--- Returns true while the free picks are cooling down.
--- @returns boolean True when visit_cooldown is positive.
function SmithyState:is_on_cooldown()
    return self.visit_cooldown > 0
end

--- Sets the new controlling faction and resets turns_under_control. Any siege or garrison of the previous owner ends (see OwnedPoint). Only
--- the owner uses the Work Orders, so their closures and draws are forgotten.
--- @param faction faction|string|nil The new owner, as a faction handle or key. Empty or nil clears ownership.
function SmithyState:set_controlling_faction(faction)
    OwnedPoint.set_controlling_faction(self, faction)
    self.turns_under_control = 0
    self.orders_closed_until, self.orders_draws = {}, {}
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
        pending_room = self.pending_room or false,
        orders_closed_until = self.orders_closed_until,
        orders_draws = self.orders_draws,
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
    self.pending_room = value("pending_room")
    --- A save from before Work Orders has no closures or draws.
    self.orders_closed_until = previous_state.orders_closed_until or {}
    self.orders_draws = previous_state.orders_draws or {}
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
        visit_cooldown = 0,
        orders_closed_until = {},
        orders_draws = {},
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
        smithy_state:set_controlling_faction(OwnedPoint.initial_owner(smithies_initial_state[i]))
        table.insert(self.smithies_state, smithy_state)
    end
end

--- Shows every smithy marker at its forge level when smithies are enabled in MCT, and removes them when they are removed. Runs on every
--- load, so changing the setting takes effect the next time a save is loaded. The debug `smithy_level` switch (configs/debug.lua) sets every
--- smithy to that level first. A smithy whose config entry is marked `disabled = true` loses its marker; it keeps its index and save record.
--- @param points_of_interest table The campaign's points of interest by zone, from configs/coordinates.lua.
function SmithyEventDelegate:sync_markers(points_of_interest)
    local enabled = get_mct_settings().enable_smithies
    local forced_level = debug_config.smithy_level[1]
    for _, smithy in ipairs(self.smithies_state) do
        if forced_level then
            log("smithy: debug smithy_level sets the " .. smithy.zone_name .. " smithy from level " .. smithy.level .. " to " .. forced_level)
            smithy.level = forced_level
        end
        local zone = points_of_interest[smithy.zone_name]
        local entry = zone and zone.smithies and zone.smithies[smithy.index_in_zone]
        smithy.disabled = entry ~= nil and entry.disabled == true
        if smithy.disabled then log("smithy: " .. smithy.zone_name .. " smithy " .. smithy.index_in_zone .. " is disabled in coordinates.lua") end
        if enabled and not smithy.disabled then
            SmithySpot.replace_marker(smithy.zone_name, smithy.index_in_zone, smithy.coordinates, smithy.level)
        else
            cm:remove_interactable_campaign_marker(SmithySpot.marker_id(smithy.zone_name, smithy.index_in_zone))
        end
    end
end

--- Ticks every SmithyState. The FactionTurnStart listener calls this once per round.
function SmithyEventDelegate:update_state_given_turn_passing()
    for i = 1, #self.smithies_state do
        if not self.smithies_state[i].disabled then self.smithies_state[i]:update_state_given_turn_passing(self.mission_manager) end
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
    return self:find_index(spot_info.zone.name, spot_info.spot_index)
end

--- Finds a SmithyState by its zone and slot.
--- @param zone_name string The zone's region key.
--- @param index_in_zone number The Smithy's 1-based slot in its zone.
--- @returns number The index in `smithies_state`, or nil when no smithy matches.
function SmithyEventDelegate:find_index(zone_name, index_in_zone)
    for i = 1, #self.smithies_state do
        if self.smithies_state[i].zone_name == zone_name and self.smithies_state[i].index_in_zone == index_in_zone then return i end
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
    local smithy = index and self.smithies_state[index]
    if smithy and smithy:trigger_dilemma_event_given_choice(dilemma_choice_and_faction_info, self.invasion_battle_manager) then
        guild_patron.donate("smithy", faction_name, self.smithies_state, smithy.coordinates)
    end
    --- The Temper and Break room reopens after each service, and Rush the Forge reopens the forge, so the next choice comes back to the same
    --- Smithy.
    if smithy and (smithy.pending_room or smithy.pending_forge_offer) then self.pending_dilemma_by_faction[faction_name] = index end
end

--- Handles a faction leaving a Smithy's Work Orders. Taking an order closes the counter to that faction for `orders_cooldown` turns. Going
--- back reopens the forge for the same lord.
--- @param faction_name string The faction that left the counter.
--- @param site table The closed spot offer site, with its `venue` { kind, zone, index } and `general_cqi`.
--- @param took boolean True when an order was taken.
function SmithyEventDelegate:orders_closed(faction_name, site, took)
    local index = self:find_index(site.venue.zone, site.venue.index)
    local smithy = index and self.smithies_state[index]
    if not smithy then return end
    if took then
        smithy.orders_closed_until[faction_name] = cm:turn_number() + smithy_data.orders_cooldown
        log("smithy: the Work Orders of the " .. smithy:describe() .. " are closed to " .. faction_name .. " until turn " .. smithy.orders_closed_until[faction_name])
        return
    end
    local character = tower_army.character(site.general_cqi)
    log("smithy: " .. faction_name .. " goes back to the forge of the " .. smithy:describe() .. " (lord " .. tostring(site.general_cqi) .. ")")
    if character and smithy:is_occupied_by_same_faction(faction_name) then
        smithy:open_forge(cm:get_faction(faction_name), character)
        self.pending_dilemma_by_faction[faction_name] = index
    end
end

--- Exports every SmithyState plus the delegate's own state for the save/load callbacks.
--- @returns table A record with `smithies` (array of state records), `pending_dilemma_by_faction` and the Association's `patrons`.
function SmithyEventDelegate:export_state_as_table()
    local smithies_data = {}
    for i = 1, #self.smithies_state do
        table.insert(smithies_data, self.smithies_state[i]:export_state_as_table())
    end
    return { smithies = smithies_data, pending_dilemma_by_faction = self.pending_dilemma_by_faction, patrons = guild_patron.export_state("smithy") }
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
