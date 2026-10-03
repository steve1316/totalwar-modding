--- Spot battle offers: when a battle spot's pre-battle roll hits, its dilemma opens with Fight, offers drawn from the pre-battle pool,
--- missions, and Avoid. An offer is paid from the treasury and the battle starts with it, as the tower's climb offers start the next floor. It
--- changes the enemy army (a smaller budget, fewer units, no heroes, lower tiers, weakened or cursed units, a traitor), puts a one-battle
--- bundle on our army, hires allies, or plays a trick in battle. A mission is a stay offer: taking it reopens the dilemma, so missions stack
--- before the battle, and a won battle pays each one met. The battle script announces, plays and tracks all of them under the tower's names.
--- Offer records live in configs/spot_offers.lua.

require("script/land_encounters/utils/random")

local offers_data = require("script/land_encounters/configs/spot_offers")
local debug_config = require("script/land_encounters/configs/debug")
local offer_effects = require("script/land_encounters/core/offer_effects")
local item_pool = require("script/land_encounters/core/item_pool")
local dilemmas = require("script/land_encounters/core/dilemmas")
local tower_army = require("script/land_encounters/features/tower_army")
local tower_missions = require("script/land_encounters/features/tower_missions")
local spot_offers = require("script/land_encounters/features/spot_offers")

--- svr key holding the battle's comma-separated buff, notice, trick and mission names. Mirrored in script/battle/mod/land_enc_tower_buffs.lua.
local BATTLE_BUFFS_SVR_KEY = "land_enc_tower_battle_buffs"

--- svr key holding Night terrors' comma-separated target unit keys. Mirrored in the battle script.
local NIGHT_TERRORS_SVR_KEY = "land_enc_tower_night_terrors"

--- svr key holding each mission's target, "key=value" pairs. Mirrored in the battle script and features/tower_missions.lua.
local MISSION_TARGETS_SVR_KEY = "land_enc_tower_mission_targets"

--- Prefix the battle script strips from a one-battle bundle to find its notice, as for the tower's bundles.
local TOWER_BUNDLE_PREFIX = "land_enc_effect_tower_"

--- Line on Fight and on every offer that can be bought, since each of them starts the battle, from the vanilla dilemmas the battle spots
--- already use.
local FIGHT_LINE = "dummy_wh2_dlc11_neo_counter_fight_chance"

--- Line on Avoid, as the battle dilemmas already use.
local AVOID_LINE = "dummy_do_nothing"

--- Second line on Avoid: avoiding fires the category's avoidance incident.
local AVOID_CONSEQUENCES_LINE = "dummy_land_enc_spot_avoid_consequences"

--- Rarities of the item Swift victory pays when the battle category grants no victory item.
local DEFAULT_BATTLE_RARITIES = { "uncommon", "rare" }

local M = {
    --- Faction key -> its open pre-battle dilemma: { dilemma, offers, missions, general_cqi, difficulty, cards, shown_affordable, taken,
    --- battle }. `cards` maps an offer's key to the { units } it shows, `taken` the missions taken so far, and `battle` is the record the
    --- tower's mission helpers fill: { general_cqi, missions, standard }.
    pending_by_faction = {},
}

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Drawing

--- True when a battle spot should open with offers: the `pre_battle_chance` roll, or always while the debug `battle_event_rolls` holds
--- "before".
--- @returns boolean True to show offers.
function M.roll()
    for _, roll in ipairs(debug_config.battle_event_rolls) do
        if roll == "before" then
            log("spot battle: debug battle_event_rolls forces the pre-battle offers")
            return true
        end
    end
    return random_chance(offers_data.pre_battle_chance)
end

--- True when a pre-battle offer or mission would do something for this battle. A traitor's units are picked here and kept on `ctx.cards`.
--- @param offer table The offer record.
--- @param ctx table { faction_name, general_cqi, event, cards }.
--- @returns boolean True when the offer can be drawn.
local function eligible(offer, ctx)
    if offer.allies and ctx.event.intervention == ALLIED_REINFORCEMENTS_PERMITTED_TYPE then return false end
    if offer.no_heroes and ctx.event.no_heroes then return false end
    if offer.shoots and not offer_effects.army_shoots(ctx.general_cqi) then return false end
    if offer.unit_ranks and #tower_army.regular_units(ctx.general_cqi) == 0 then return false end
    if offer.traitor then
        local units = offer_effects.pick_recruits(ctx.general_cqi, ctx.event.faction, offer.traitor)
        if #units < offer.traitor.count then return false end
        ctx.cards[offer.key] = { units = units }
    end
    return true
end

--- Draws `count` eligible offers from a pool with `random_number`, eligible offers in the debug `force_spot_offers` list first.
--- @param pool_name string "pre_battle" or "mission".
--- @param count number How many to draw.
--- @param ctx table The draw context, see `eligible`.
--- @returns table Offer keys in popup order.
local function draw_pool(pool_name, count, ctx)
    local pool = {}
    for _, offer in ipairs(offers_data.offers) do
        if offer.pool == pool_name and eligible(offer, ctx) then pool[#pool + 1] = offer.key end
    end
    local keys, forced = {}, 0
    for _, forced_key in ipairs(debug_config.force_spot_offers) do
        for i, key in ipairs(pool) do
            if key == forced_key and #keys < count then
                keys[#keys + 1] = table.remove(pool, i)
                forced = forced + 1
                break
            end
        end
    end
    while #keys < count and #pool > 0 do
        keys[#keys + 1] = table.remove(pool, random_number(#pool))
    end
    log("spot battle: drew " .. pool_name .. " for " .. ctx.faction_name .. " on " .. ctx.event.dilemma .. ": " .. table.concat(keys, ", ") .. " ("
        .. #pool .. " more eligible, " .. forced .. " forced)")
    return keys
end

--- Draws a battle's pre-battle offers and missions.
--- @param ctx table The draw context, see `eligible`.
--- @returns table The offer keys.
--- @returns table The mission keys.
function M.draw(ctx)
    return draw_pool("pre_battle", offers_data.offers_per_battle, ctx), draw_pool("mission", offers_data.missions_per_battle, ctx)
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Dilemma

--- True when the faction's treasury covers an offer's cost.
--- @param offer table The offer record.
--- @param pending table The open dilemma.
--- @param faction_name string The faction key.
--- @returns boolean True for a free offer or one the treasury can pay.
local function affordable(offer, pending, faction_name)
    return not offer.cost or offer_effects.treasury(faction_name) >= spot_offers.offer_cost(offer, pending.difficulty)
end

--- Lists the missions taken on the open dilemma at the top of its description, one line each with a blank line after them, as the tower
--- lists a floor's results. No missions taken clears it, which a plain battle dilemma also needs.
--- @param pending table|nil The open dilemma, or nil to clear the list.
function M.show_missions(pending)
    local lines = {}
    for _, key in ipairs(pending and pending.battle.missions or {}) do
        lines[#lines + 1] = common.get_localised_string(offers_data.mission_set_loc_prefix .. key .. "_" .. pending.difficulty)
    end
    common.set_context_value(offers_data.missions_context, #lines > 0 and table.concat(lines, "\n") .. "\n\n" or "")
end

--- Shows a faction's open pre-battle dilemma: Fight, the offers, the missions, then Avoid. Fight and every offer that can be bought end with
--- the vanilla line that a battle may follow, and every mission with the line that we return to this choice. An offer the treasury cannot pay
--- shows its line with the not-enough-gold line under it and no cards, and a mission already taken says so. Both are greyed out once the
--- panel opens. Which way each was shown is kept on `pending.shown_affordable`. The missions taken are listed at the top of the description.
--- @param faction_name string The faction key.
function M.launch(faction_name)
    local pending = M.pending_by_faction[faction_name]
    pending.shown_affordable = {}
    local choices = { { key = offers_data.fight_choice_key, lines = { FIGHT_LINE } } }
    for _, key in ipairs(pending.offers) do
        local offer = offers_data.by_key[key]
        local line = offers_data.line_prefix .. key .. "_" .. pending.difficulty
        local can_pay = affordable(offer, pending, faction_name)
        pending.shown_affordable[key] = can_pay
        local choice = { key = spot_offers.choice_key(key), lines = can_pay and { line, FIGHT_LINE } or { line, offers_data.unaffordable_line } }
        local cards = pending.cards[key]
        local force = can_pay and cards and cards.units and tower_army.delving_force(pending.general_cqi)
        if force then choice.units = { force = force, keys = cards.units } end
        choices[#choices + 1] = choice
    end
    for _, key in ipairs(pending.missions) do
        local line = offers_data.line_prefix .. key .. "_" .. pending.difficulty
        local lines = { offers_data.taken_line }
        if not pending.taken[key] then
            local can_pay = affordable(offers_data.by_key[key], pending, faction_name)
            pending.shown_affordable[key] = can_pay
            lines = can_pay and { line, offers_data.returns_line } or { line, offers_data.unaffordable_line }
        end
        choices[#choices + 1] = { key = spot_offers.choice_key(key), lines = lines }
    end
    choices[#choices + 1] = { key = offers_data.avoid_choice_key, lines = { AVOID_LINE, AVOID_CONSEQUENCES_LINE } }
    M.show_missions(pending)
    dilemmas.launch(pending.dilemma, choices, faction_name)
end

--- Opens a battle spot's dilemma with pre-battle offers and missions for a human lord.
--- @param event table The battle event from `battle_picker.pick`.
--- @param character character The lord who entered the spot.
--- @param faction faction The lord's faction.
function M.open(event, character, faction)
    local faction_name = faction:name()
    local ctx = { faction_name = faction_name, general_cqi = character:command_queue_index(), event = event, cards = {} }
    local offers, missions = M.draw(ctx)
    M.pending_by_faction[faction_name] = { dilemma = event.dilemma, offers = offers, missions = missions, general_cqi = ctx.general_cqi,
        difficulty = event.difficulty, cards = ctx.cards, taken = {}, battle = { general_cqi = ctx.general_cqi, missions = {} } }
    log("spot battle: " .. faction_name .. " opens " .. event.dilemma .. " with offers, lord " .. ctx.general_cqi .. ", treasury "
        .. offer_effects.treasury(faction_name))
    M.launch(faction_name)
end

--- Greys out what cannot be taken on a faction's open pre-battle dilemma: the offers and missions the treasury could not pay when it was
--- shown, and the missions already taken. UI only: an offer clicked anyway starts the battle as it is, and a mission just reopens.
--- @param faction_name string The local faction key.
function M.grey_out_unaffordable(faction_name)
    local pending = M.pending_by_faction[faction_name]
    if pending == nil or pending.shown_affordable == nil then return end
    local keys = {}
    for _, list in ipairs({ pending.offers, pending.missions or {} }) do
        for _, key in ipairs(list) do
            if pending.shown_affordable[key] == false or (pending.taken or {})[key] then keys[#keys + 1] = spot_offers.choice_key(key) end
        end
    end
    dilemmas.grey_out(pending.dilemma, keys)
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Taking an offer

--- Adds a notice name for the battle script to announce.
--- @param event table The battle event.
--- @param notice string The notice name after the objective prefix.
local function add_notice(event, notice)
    event.notices = event.notices or {}
    event.notices[#event.notices + 1] = notice
end

--- Adds an offer's (or a gamble outcome's) changes to the battle event the army is built from.
--- @param fields table The offer record or a gamble outcome.
--- @param event table The battle event.
local function apply_to_event(fields, event)
    if fields.budget then event.budget_multiplier = (event.budget_multiplier or 1) * fields.budget end
    if fields.fewer_units then event.fewer_units = (event.fewer_units or 0) + fields.fewer_units end
    if fields.traitor then event.fewer_units = (event.fewer_units or 0) + fields.traitor.count end
    if fields.no_heroes then event.no_heroes = true end
    if fields.max_tier then event.max_tier = math.min(event.max_tier or fields.max_tier, fields.max_tier) end
    if fields.enemy_strength then event.enemy_strength = math.min(event.enemy_strength or 1, fields.enemy_strength) end
    if fields.enemy_bundle then
        event.enemy_bundles = event.enemy_bundles or {}
        event.enemy_bundles[#event.enemy_bundles + 1] = fields.enemy_bundle
    end
    if fields.battle_bundle then
        event.battle_bundles = event.battle_bundles or {}
        event.battle_bundles[#event.battle_bundles + 1] = fields.battle_bundle
    end
    if fields.own_strength then event.own_strength = fields.own_strength end
    if fields.allies then
        local units = random_number(fields.allies[2], fields.allies[1]) - 1
        local per_unit = offers_data.ally_gold_per_unit
        event.intervention = ALLIED_REINFORCEMENTS_PERMITTED_TYPE
        event.ally_options = { no_heroes = true, unit_count = units, budget_range = { units * per_unit[1], units * per_unit[2] } }
        log("spot battle: the hired allied army fields its lord and " .. units .. " units")
    end
end

--- Takes a mission on the open dilemma: pays its cost, marks it taken (Guard the standard marks one of our units) and reopens the dilemma.
--- A mission already taken or shown as unaffordable just reopens it.
--- @param faction_name string The faction key.
--- @param pending table The open dilemma.
--- @param offer table The mission's offer record.
local function take_mission(faction_name, pending, offer)
    if pending.taken[offer.key] or pending.shown_affordable[offer.key] == false then
        log("spot battle: mission " .. offer.key .. " is taken or was shown as unaffordable, nothing happens")
    else
        if offer.cost then cm:treasury_mod(faction_name, -spot_offers.offer_cost(offer, pending.difficulty)) end
        pending.taken[offer.key] = true
        tower_missions.take(offer, pending.battle)
        log("spot battle: " .. faction_name .. " takes mission " .. offer.key .. ", treasury " .. offer_effects.treasury(faction_name))
    end
    M.launch(faction_name)
end

--- Takes a choice from a faction's open pre-battle dilemma. A mission stays: it reopens the dilemma. Fight, Avoid and offers close it. An offer
--- is paid and added to the battle event, then the battle starts with the missions taken. An offer shown as unaffordable starts the battle as
--- it is, as a tower climb offer does.
--- @param faction_name string The faction that chose.
--- @param choice_key string The chosen choice key.
--- @param event table The battle event the army will be built from.
--- @returns string|nil "fight", "avoid" or "reopen", or nil when the faction has no pre-battle dilemma open.
function M.take(faction_name, choice_key, event)
    local pending = M.pending_by_faction[faction_name]
    if pending == nil then return nil end
    for _, key in ipairs(pending.missions or {}) do
        if spot_offers.choice_key(key) == choice_key then
            take_mission(faction_name, pending, offers_data.by_key[key])
            return "reopen"
        end
    end
    M.pending_by_faction[faction_name] = nil
    if choice_key == offers_data.avoid_choice_key then
        log("spot battle: " .. faction_name .. " avoids " .. pending.dilemma)
        return "avoid"
    end
    event.missions = (pending.battle or {}).missions or {}
    event.standard = (pending.battle or {}).standard
    local offer = nil
    for _, key in ipairs(pending.offers) do
        if spot_offers.choice_key(key) == choice_key then offer = offers_data.by_key[key] end
    end
    if offer == nil then
        log("spot battle: " .. faction_name .. " fights " .. pending.dilemma .. " as it is, missions " .. table.concat(event.missions, ", "))
        return "fight"
    end
    if pending.shown_affordable and pending.shown_affordable[offer.key] == false then
        log("spot battle: " .. offer.key .. " was shown as unaffordable, so the battle starts as it is")
        return "fight"
    end
    local before = offer_effects.treasury(faction_name)
    if offer.cost then cm:treasury_mod(faction_name, -spot_offers.offer_cost(offer, pending.difficulty)) end
    apply_to_event(offer, event)
    if offer.gamble then
        local outcome = spot_offers.roll_outcome(offer.gamble)
        log("spot battle: " .. offer.key .. " rolls " .. outcome[2])
        apply_to_event(outcome, event)
        add_notice(event, offer.key .. "_" .. outcome[2])
    elseif not offer.battle_bundle then
        --- A one-battle bundle is announced under its tower name, so only the other offers need their own notice. A trick's notice is its
        --- tower name too, which tells the battle script to play it.
        add_notice(event, offer.key)
    end
    log("spot battle: " .. faction_name .. " took " .. offer.key .. ", treasury " .. before .. " -> " .. offer_effects.treasury(faction_name)
        .. ", event budget x" .. tostring(event.budget_multiplier) .. ", fewer units " .. tostring(event.fewer_units) .. ", no heroes "
        .. tostring(event.no_heroes) .. ", max tier " .. tostring(event.max_tier) .. ", enemy strength " .. tostring(event.enemy_strength)
        .. ", missions " .. table.concat(event.missions, ", "))
    return "fight"
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- The battle

--- Readies our army for the battle the event describes: puts its one-battle bundles on and starts our units at `own_strength`.
--- @param event table The battle event.
--- @param general_cqi number Our lord's command queue index.
function M.prepare_battle(event, general_cqi)
    for _, bundle in ipairs(event.battle_bundles or {}) do tower_army.apply_bundle(general_cqi, bundle) end
    if event.own_strength then
        for _, entry in ipairs(tower_army.unit_strengths(general_cqi)) do tower_army.set_strength(entry.unit, entry.strength * event.own_strength) end
        log("spot battle: our units start at " .. math.floor(event.own_strength * 100 + 0.5) .. "% of their strength")
    end
    offer_effects.log_army_change(general_cqi, "spot battle")
end

--- Hands the battle to the battle script: the one-battle bundles under their tower names, each offer's notice or trick, and the missions,
--- with Night terrors' and the missions' targets. The enemy's units are read from the spawned army the first time and kept on the event, so
--- a battle re-armed after a load hands over the same targets.
--- @param event table The battle event.
--- @param army table|nil The spawned enemy Army, or nil when re-arming after a load.
function M.hand_to_battle(event, army)
    if army and not event.enemy_units then
        event.enemy_units = {}
        for _, row in ipairs(army.units or {}) do
            for _ = 1, row.count or 1 do event.enemy_units[#event.enemy_units + 1] = row.id end
        end
        event.trophy = tower_army.most_expensive(event.enemy_units, 1)[1]
        event.night_terrors_targets = tower_army.most_expensive(event.enemy_units, offers_data.night_terrors_targets)
    end
    local names, targets = {}, {}
    for _, bundle in ipairs(event.battle_bundles or {}) do names[#names + 1] = bundle:sub(#TOWER_BUNDLE_PREFIX + 1) end
    for _, notice in ipairs(event.notices or {}) do names[#names + 1] = notice end
    for _, key in ipairs(event.missions or {}) do
        names[#names + 1] = key
        local offer = offers_data.by_key[key]
        local value = offer.battle_value
        if offer.trophy then value = event.trophy end
        if offer.unit_ranks and event.standard then value = event.standard.key .. "#" .. event.standard.nth end
        if value then targets[#targets + 1] = key .. "=" .. value end
    end
    local terrors = {}
    for _, notice in ipairs(event.notices or {}) do
        if notice == "night_terrors" then terrors = event.night_terrors_targets or {} end
    end
    log("spot battle: battle names: " .. (#names > 0 and table.concat(names, ", ") or "none") .. ", mission targets: " .. table.concat(targets, ", ")
        .. ", night terrors: " .. table.concat(terrors, ", "))
    tower_missions.clear_reports()
    core:svr_save_string(BATTLE_BUFFS_SVR_KEY, table.concat(names, ","))
    core:svr_save_string(MISSION_TARGETS_SVR_KEY, table.concat(targets, ","))
    core:svr_save_string(NIGHT_TERRORS_SVR_KEY, table.concat(terrors, ","))
end

--- Finds the unit Guard the standard marked: the `nth` regular unit with its key.
--- @param general_cqi number Our lord's command queue index.
--- @param standard table { key, nth }.
--- @returns table|nil Its `tower_army.regular_units` entry.
local function standard_unit(general_cqi, standard)
    local seen = 0
    for _, entry in ipairs(tower_army.regular_units(general_cqi)) do
        if entry.unit:unit_key() == standard.key then
            seen = seen + 1
            if seen == standard.nth then return entry end
        end
    end
    return nil
end

--- Pays one mission met: gold, items, ranks for the marked unit, or a copy of the enemy's most expensive unit.
--- @param offer table The mission's offer record.
--- @param event table The battle event.
--- @param faction_name string Our faction key.
--- @param general_cqi number Our lord's command queue index.
local function pay_mission(offer, event, faction_name, general_cqi)
    local gold = offer.gold and spot_offers.scale_gold(offer.gold, event.difficulty, offer) or nil
    if gold then cm:treasury_mod(faction_name, gold) end
    local items = {}
    if offer.items then items = item_pool.pick_items(faction_name, offer.items.rarities, offer.items.count) end
    if offer.unique then items = offer_effects.pick_unique_items(faction_name, offer.unique) end
    if offer.battle_item then items = item_pool.pick_items(faction_name, (event.victory_items or {}).rarities or DEFAULT_BATTLE_RARITIES, 1) end
    for _, item in ipairs(items) do cm:add_ancillary_to_faction(cm:get_faction(faction_name), item, false) end
    if offer.unit_ranks then
        local entry = event.standard and standard_unit(general_cqi, event.standard)
        if entry then cm:add_experience_to_unit(entry.unit, offer.unit_ranks) else log("spot battle: guard the standard found no marked unit") end
    end
    local general = tower_army.character(general_cqi)
    if offer.trophy and event.trophy and general then cm:grant_unit_to_character(cm:char_lookup_str(general), event.trophy) end
    log("spot battle: mission " .. offer.key .. " pays" .. (gold and " " .. gold .. " gold" or "") .. (#items > 0 and ", items " .. table.concat(items, ", ") or "")
        .. (offer.trophy and ", trophy " .. tostring(event.trophy) or ""))
end

--- Settles a won battle's missions from what the battle script reported, with a message for each met or failed. After an auto-resolved
--- battle nothing was counted: a paid mission's cost comes back and one message says so.
--- @param event table The battle event.
--- @param faction_name string Our faction key.
--- @param general_cqi number Our lord's command queue index.
function M.settle_missions(event, faction_name, general_cqi)
    if not event.missions or #event.missions == 0 then return end
    local outcomes = tower_missions.read_outcomes({ missions = event.missions, standard = event.standard, trophy = event.trophy })
    local general = tower_army.character(general_cqi)
    local position = general and { general:logical_position_x(), general:logical_position_y() } or { 0, 0 }
    if outcomes.untracked then
        for _, key in ipairs(event.missions) do
            local offer = offers_data.by_key[key]
            if offer.cost then cm:treasury_mod(faction_name, spot_offers.offer_cost(offer, event.difficulty)) end
        end
        log("spot battle: the battle was auto-resolved, so no mission was counted and their stakes come back")
        show_located_message(faction_name, offers_data.message_prefix .. "missions_untracked", position)
        return
    end
    for _, mission in ipairs(outcomes.missions) do
        local offer = offers_data.by_key[mission.key]
        log("spot battle: mission " .. mission.key .. " " .. (mission.met and "met" or "failed"))
        if mission.met then pay_mission(offer, event, faction_name, general_cqi) end
        show_located_message(faction_name, offers_data.message_prefix .. "mission_" .. mission.key .. (mission.met and "_met" or "_failed"), position)
    end
end

--- Takes the one-battle bundles off our army once the battle is over, and clears everything handed to the battle script.
--- @param event table The battle event.
--- @param general_cqi number|nil Our lord's command queue index.
function M.end_battle(event, general_cqi)
    core:svr_save_string(BATTLE_BUFFS_SVR_KEY, "")
    core:svr_save_string(MISSION_TARGETS_SVR_KEY, "")
    core:svr_save_string(NIGHT_TERRORS_SVR_KEY, "")
    tower_missions.clear_reports()
    local bundles = event.battle_bundles or {}
    if #bundles > 0 then log("spot battle: removing one-battle bundles: " .. table.concat(bundles, ", ")) end
    if general_cqi then
        for _, bundle in ipairs(bundles) do tower_army.remove_bundle(general_cqi, bundle) end
    end
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Saves

--- Exports the open pre-battle dilemmas for the save file.
--- @returns table { pending_by_faction }.
function M.export_state()
    return { pending_by_faction = M.pending_by_faction }
end

--- Restores the state saved by `M.export_state`. A save from before battle offers restores nothing.
--- @param saved table|nil The saved state.
function M.restore_state(saved)
    M.pending_by_faction = (saved or {}).pending_by_faction or {}
end

return M
