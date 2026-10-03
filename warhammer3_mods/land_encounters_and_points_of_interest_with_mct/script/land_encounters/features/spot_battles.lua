--- Spot battle offers: when a battle spot's pre-battle roll hits, its dilemma opens with Fight, offers drawn from the pre-battle pool, and
--- Avoid. An offer is paid from the treasury and the battle starts with it, as the tower's climb offers start the next floor. It changes the
--- enemy army (a smaller budget, fewer units, no heroes, lower tiers, weakened or cursed units, a traitor), puts a one-battle bundle on our
--- army, or hires allies. The battle script announces each of them, the way it does for a tower floor. Offer records live in
--- configs/spot_offers.lua.

require("script/land_encounters/utils/random")

local offers_data = require("script/land_encounters/configs/spot_offers")
local debug_config = require("script/land_encounters/configs/debug")
local offer_effects = require("script/land_encounters/core/offer_effects")
local dilemmas = require("script/land_encounters/core/dilemmas")
local tower_army = require("script/land_encounters/features/tower_army")
local spot_offers = require("script/land_encounters/features/spot_offers")

--- svr key holding the battle's comma-separated buff and notice names. Mirrored in script/battle/mod/land_enc_tower_buffs.lua.
local BATTLE_BUFFS_SVR_KEY = "land_enc_tower_battle_buffs"

--- Prefix the battle script strips from a one-battle bundle to find its notice, as for the tower's bundles.
local TOWER_BUNDLE_PREFIX = "land_enc_effect_tower_"

--- Line on Fight and on every offer that can be bought, since each of them starts the battle, from the vanilla dilemmas the battle spots
--- already use.
local FIGHT_LINE = "dummy_wh2_dlc11_neo_counter_fight_chance"

--- Line on Avoid, as the battle dilemmas already use.
local AVOID_LINE = "dummy_do_nothing"

--- Second line on Avoid: avoiding fires the category's avoidance incident.
local AVOID_CONSEQUENCES_LINE = "dummy_land_enc_spot_avoid_consequences"

local M = {
    --- Faction key -> its open pre-battle dilemma: { dilemma, offers, general_cqi, difficulty, cards, shown_affordable }. `cards` maps an
    --- offer's key to the { units } it shows.
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

--- True when a pre-battle offer would do something for this battle. A traitor's units are picked here and kept on `ctx.cards`.
--- @param offer table The offer record.
--- @param ctx table { faction_name, general_cqi, event, cards }.
--- @returns boolean True when the offer can be drawn.
local function eligible(offer, ctx)
    if offer.allies and ctx.event.intervention == ALLIED_REINFORCEMENTS_PERMITTED_TYPE then return false end
    if offer.no_heroes and ctx.event.no_heroes then return false end
    if offer.traitor then
        local units = offer_effects.pick_recruits(ctx.general_cqi, ctx.event.faction, offer.traitor)
        if #units < offer.traitor.count then return false end
        ctx.cards[offer.key] = { units = units }
    end
    return true
end

--- Draws `offers_per_battle` pre-battle offers with `random_number`, eligible offers in the debug `force_spot_offers` list first.
--- @param ctx table The draw context, see `eligible`.
--- @returns table Offer keys in popup order.
function M.draw(ctx)
    local pool = {}
    for _, offer in ipairs(offers_data.offers) do
        if offer.pool == "pre_battle" and eligible(offer, ctx) then pool[#pool + 1] = offer.key end
    end
    local keys, forced = {}, 0
    for _, forced_key in ipairs(debug_config.force_spot_offers) do
        for i, key in ipairs(pool) do
            if key == forced_key and #keys < offers_data.offers_per_battle then
                keys[#keys + 1] = table.remove(pool, i)
                forced = forced + 1
                break
            end
        end
    end
    while #keys < offers_data.offers_per_battle and #pool > 0 do
        keys[#keys + 1] = table.remove(pool, random_number(#pool))
    end
    log("spot battle: drew for " .. ctx.faction_name .. " on " .. ctx.event.dilemma .. ": " .. table.concat(keys, ", ") .. " (" .. #pool .. " more eligible, "
        .. forced .. " forced)")
    return keys
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Dilemma

--- Shows a faction's open pre-battle dilemma: Fight, the offers, then Avoid. Fight and every offer that can be bought end with the vanilla
--- line that a battle may follow. An offer the treasury cannot pay shows its line with the not-enough-gold line under it, no cards, and is
--- greyed out once the panel opens. Which way each offer was shown is kept on `pending.shown_affordable`.
--- @param faction_name string The faction key.
function M.launch(faction_name)
    local pending = M.pending_by_faction[faction_name]
    pending.shown_affordable = {}
    local choices = { { key = offers_data.fight_choice_key, lines = { FIGHT_LINE } } }
    for _, key in ipairs(pending.offers) do
        local offer = offers_data.by_key[key]
        local line = offers_data.line_prefix .. key .. "_" .. pending.difficulty
        local affordable = not offer.cost or offer_effects.treasury(faction_name) >= spot_offers.offer_cost(offer, pending.difficulty)
        pending.shown_affordable[key] = affordable
        local choice = { key = spot_offers.choice_key(key), lines = affordable and { line, FIGHT_LINE } or { line, offers_data.unaffordable_line } }
        local cards = pending.cards[key]
        local force = affordable and cards and cards.units and tower_army.delving_force(pending.general_cqi)
        if force then choice.units = { force = force, keys = cards.units } end
        choices[#choices + 1] = choice
    end
    choices[#choices + 1] = { key = offers_data.avoid_choice_key, lines = { AVOID_LINE, AVOID_CONSEQUENCES_LINE } }
    dilemmas.launch(pending.dilemma, choices, faction_name)
end

--- Opens a battle spot's dilemma with pre-battle offers for a human lord.
--- @param event table The battle event from `battle_picker.pick`.
--- @param character character The lord who entered the spot.
--- @param faction faction The lord's faction.
function M.open(event, character, faction)
    local faction_name = faction:name()
    local ctx = { faction_name = faction_name, general_cqi = character:command_queue_index(), event = event, cards = {} }
    local keys = M.draw(ctx)
    M.pending_by_faction[faction_name] = { dilemma = event.dilemma, offers = keys, general_cqi = ctx.general_cqi, difficulty = event.difficulty,
        cards = ctx.cards }
    log("spot battle: " .. faction_name .. " opens " .. event.dilemma .. " with offers, lord " .. ctx.general_cqi .. ", treasury "
        .. offer_effects.treasury(faction_name))
    M.launch(faction_name)
end

--- Greys out the offers on a faction's open pre-battle dilemma that the treasury could not pay when it was shown. UI only: one clicked
--- anyway starts the battle as it is.
--- @param faction_name string The local faction key.
function M.grey_out_unaffordable(faction_name)
    local pending = M.pending_by_faction[faction_name]
    if pending == nil or pending.shown_affordable == nil then return end
    local keys = {}
    for _, key in ipairs(pending.offers) do
        if pending.shown_affordable[key] == false then keys[#keys + 1] = spot_offers.choice_key(key) end
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

--- Takes a choice from a faction's open pre-battle dilemma. Fight and Avoid pass through. An offer is paid and added to the battle event,
--- then the battle starts. An offer shown as unaffordable starts the battle as it is, as a tower climb offer does.
--- @param faction_name string The faction that chose.
--- @param choice_key string The chosen choice key.
--- @param event table The battle event the army will be built from.
--- @returns string|nil "fight" or "avoid", or nil when the faction has no pre-battle dilemma open.
function M.take(faction_name, choice_key, event)
    local pending = M.pending_by_faction[faction_name]
    if pending == nil then return nil end
    M.pending_by_faction[faction_name] = nil
    if choice_key == offers_data.avoid_choice_key then
        log("spot battle: " .. faction_name .. " avoids " .. pending.dilemma)
        return "avoid"
    end
    local offer = nil
    for _, key in ipairs(pending.offers) do
        if spot_offers.choice_key(key) == choice_key then offer = offers_data.by_key[key] end
    end
    if offer == nil then
        log("spot battle: " .. faction_name .. " fights " .. pending.dilemma .. " as it is")
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
        --- A one-battle bundle is announced under its tower name, so only the other offers need their own notice.
        add_notice(event, offer.key)
    end
    log("spot battle: " .. faction_name .. " took " .. offer.key .. ", treasury " .. before .. " -> " .. offer_effects.treasury(faction_name)
        .. ", event budget x" .. tostring(event.budget_multiplier) .. ", fewer units " .. tostring(event.fewer_units) .. ", no heroes "
        .. tostring(event.no_heroes) .. ", max tier " .. tostring(event.max_tier) .. ", enemy strength " .. tostring(event.enemy_strength))
    return "fight"
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- The battle

--- Hands the battle event's notices to the battle script: the one-battle bundles under their tower names, then each offer's notice.
--- @param event table The battle event.
function M.hand_to_battle(event)
    local names = {}
    for _, bundle in ipairs(event.battle_bundles or {}) do names[#names + 1] = bundle:sub(#TOWER_BUNDLE_PREFIX + 1) end
    for _, notice in ipairs(event.notices or {}) do names[#names + 1] = notice end
    log("spot battle: battle notices: " .. (#names > 0 and table.concat(names, ", ") or "none"))
    core:svr_save_string(BATTLE_BUFFS_SVR_KEY, table.concat(names, ","))
end

--- Readies our army for the battle the event describes: puts its one-battle bundles on, starts our units at `own_strength`, and hands the
--- notices to the battle script.
--- @param event table The battle event.
--- @param general_cqi number Our lord's command queue index.
function M.prepare_battle(event, general_cqi)
    for _, bundle in ipairs(event.battle_bundles or {}) do tower_army.apply_bundle(general_cqi, bundle) end
    if event.own_strength then
        for _, entry in ipairs(tower_army.unit_strengths(general_cqi)) do tower_army.set_strength(entry.unit, entry.strength * event.own_strength) end
        log("spot battle: our units start at " .. math.floor(event.own_strength * 100 + 0.5) .. "% of their strength")
    end
    offer_effects.log_army_change(general_cqi, "spot battle")
    M.hand_to_battle(event)
end

--- Takes the one-battle bundles off our army once the battle is over, and clears the battle script's notices.
--- @param event table The battle event.
--- @param general_cqi number|nil Our lord's command queue index.
function M.end_battle(event, general_cqi)
    core:svr_save_string(BATTLE_BUFFS_SVR_KEY, "")
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
