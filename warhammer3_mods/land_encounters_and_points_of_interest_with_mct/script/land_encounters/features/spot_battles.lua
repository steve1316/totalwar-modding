--- Spot battle offers: when a battle spot's pre-battle roll hits, its dilemma opens with Fight, offers drawn from the pre-battle pool,
--- missions, and Avoid. An offer is paid from the treasury and the battle starts with it, as the tower's climb offers start the next floor. It
--- changes the enemy army (a smaller budget, fewer units, no heroes, lower tiers, weakened or cursed units, a traitor), puts a one-battle
--- bundle on our army, hires allies, or plays a trick in battle. A mission is a stay offer: taking it reopens the dilemma, so missions stack
--- before the battle, and a won battle pays each one met. The battle script announces, plays and tracks all of them under the tower's names.
--- Offer records live in configs/spot_offers.lua.

require("script/land_encounters/utils/random")

local offers_data = require("script/land_encounters/configs/spot_offers")
local steps = require("script/land_encounters/utils/steps")
local debug_config = require("script/land_encounters/configs/debug")
local offer_effects = require("script/land_encounters/core/offer_effects")
local army_generator = require("script/land_encounters/core/army_generator")
local item_pool = require("script/land_encounters/core/item_pool")
local dilemmas = require("script/land_encounters/core/dilemmas")
local tower_army = require("script/land_encounters/features/tower_army")
local tower_missions = require("script/land_encounters/features/tower_missions")
local tower_offers = require("script/land_encounters/features/tower_offers")
local spot_offers = require("script/land_encounters/features/spot_offers")
local battle_modifiers = require("script/land_encounters/features/battle_modifiers")

--- svr keys the battle script reads the buff, notice, trick and mission names, Night terrors' targets and the mission targets from, and the
--- prefix it strips from a one-battle bundle to find its notice. The tower owns them, since the battle script plays both under its names.
local BATTLE_BUFFS_SVR_KEY = tower_offers.BATTLE_BUFFS_SVR_KEY
local NIGHT_TERRORS_SVR_KEY = tower_offers.NIGHT_TERRORS_SVR_KEY
local MISSION_TARGETS_SVR_KEY = tower_missions.TARGETS_SVR_KEY
local TOWER_BUNDLE_PREFIX = tower_offers.BUNDLE_PREFIX

--- Line on Fight and on every offer that can be bought, since each of them starts the battle.
local FIGHT_LINE = offers_data.fight_line

--- Line on Avoid, as the battle dilemmas already use.
local AVOID_LINE = "dummy_do_nothing"

--- Second line on Avoid: avoiding fires the category's avoidance incident.
local AVOID_CONSEQUENCES_LINE = "dummy_land_enc_spot_avoid_consequences"

local M = {
    --- Faction key -> its open pre-battle dilemma: { dilemma, offers, missions, general_cqi, difficulty, cards, shown_affordable, taken,
    --- battle }. `cards` maps an offer's key to the { units } it shows, `taken` the missions taken so far, and `battle` is the record the
    --- tower's mission helpers fill: { general_cqi, missions, standard }.
    pending_by_faction = {},
}

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Drawing

--- Rolls one of the battle events: its MCT chance, or always while the debug `battle_event_rolls` holds its name.
--- @param name string "before" or "after".
--- @param setting string The MCT setting holding its percent chance.
--- @returns boolean True when the event happens.
local function roll_event(name, setting)
    for _, roll in ipairs(debug_config.battle_event_rolls) do
        if roll == name then
            log("spot battle: debug battle_event_rolls forces the " .. name .. " event")
            return true
        end
    end
    return random_chance(get_mct_settings()[setting])
end

--- True when a battle spot should open with offers: the MCT `pre_battle_chance` roll, or the debug "before" roll.
--- @returns boolean True to show offers.
function M.roll()
    return roll_event("before", "pre_battle_chance")
end

--- True when a won battle spot should open the spoils pick: the MCT `spoils_chance` roll, or the debug "after" roll.
--- @returns boolean True to open the spoils pick.
function M.roll_spoils()
    return roll_event("after", "spoils_chance")
end

--- True when a pre-battle offer or mission would do something for this battle. A traitor's units are picked here and kept on `ctx.cards`.
--- @param offer table The offer record at the battle's difficulty.
--- @param ctx table { faction_name, general_cqi, event, cards, keeps_out }. `keeps_out` holds the offers the battle's modifiers keep out.
--- @returns boolean True when the offer can be drawn.
local function eligible(offer, ctx)
    if ctx.keeps_out[offer.key] then return false end
    if offer.allies and ctx.event.intervention == ALLIED_REINFORCEMENTS_PERMITTED_TYPE then return false end
    if offer.for_ally then
        if ctx.event.intervention ~= ALLIED_REINFORCEMENTS_PERMITTED_TYPE then return false end
        local sized = ctx.event.ally_options ~= nil and ctx.event.ally_options.unit_count ~= nil
        if offer.for_ally ~= true and (offer.for_ally == "sized") ~= sized then return false end
    end
    if offer.no_heroes and ctx.event.no_heroes then return false end
    if not offer_effects.army_fits(offer, ctx.event.faction, ctx.general_cqi) then return false end
    if offer.unit_ranks and #tower_army.regular_units(ctx.general_cqi) == 0 then return false end
    if offer.traitor then
        local units = offer_effects.pick_recruits(ctx.general_cqi, ctx.event.faction, offer.traitor, ctx.shown_units)
        if #units < offer.traitor.count then return false end
        ctx.cards[offer.key] = { units = units }
        for _, key in ipairs(units) do ctx.shown_units[key] = true end
    end
    return true
end

--- Draws `count` eligible offers from a pool with `random_number`, eligible offers in the debug `force_spot_offers` list first. Offers that
--- share a `group` (the allied army sizes) go in as one, picked at random as the tower draws them, or the group's forced offer.
--- @param pool_name string "pre_battle" or "mission".
--- @param count number How many to draw.
--- @param ctx table The draw context, see `eligible`.
--- @returns table Offer keys in popup order.
local function draw_pool(pool_name, count, ctx)
    local pool, groups, group_names = {}, {}, {}
    for _, offer in ipairs(offers_data.all_at(ctx.event.difficulty)) do
        if offer.pool == pool_name and eligible(offer, ctx) then
            if offer.group and not groups[offer.group] then
                groups[offer.group] = {}
                group_names[#group_names + 1] = offer.group
            end
            table.insert(offer.group and groups[offer.group] or pool, offer.key)
        end
    end
    local forced_keys = {}
    for _, key in ipairs(debug_config.force_spot_offers) do forced_keys[key] = true end
    for _, name in ipairs(group_names) do
        local picked = groups[name][random_number(#groups[name])]
        for _, key in ipairs(groups[name]) do
            if forced_keys[key] then picked = key end
        end
        pool[#pool + 1] = picked
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

--- Lists the battle's modifiers, then the missions taken, at the top of the open dilemma's description, one line each with a blank line after
--- each block, as the tower lists a floor's results. Empty when there are neither.
--- @param pending table The open dilemma.
function M.show_missions(pending)
    local lines = {}
    for _, key in ipairs(pending.battle.missions) do
        lines[#lines + 1] = common.get_localised_string(offers_data.mission_set_loc_prefix .. key .. "_" .. pending.difficulty)
    end
    common.set_context_value(offers_data.missions_context, text_block(battle_modifiers.lines(pending.modifiers)) .. text_block(lines))
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
        local offer = offers_data.at(key, pending.difficulty)
        local line = offers_data.line_prefix .. key .. "_" .. pending.difficulty .. (offer.allies and pending.ally_theme and "_" .. pending.ally_theme.key or "")
        local can_pay = spot_offers.affordable(offer, faction_name)
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
            local can_pay = spot_offers.affordable(offers_data.at(key, pending.difficulty), faction_name)
            pending.shown_affordable[key] = can_pay
            lines = can_pay and { line, offers_data.returns_line } or { line, offers_data.unaffordable_line }
        end
        choices[#choices + 1] = { key = spot_offers.choice_key(key), lines = lines }
    end
    choices[#choices + 1] = { key = offers_data.avoid_choice_key, lines = { AVOID_LINE, AVOID_CONSEQUENCES_LINE } }
    M.show_missions(pending)
    dilemmas.launch(pending.dilemma, choices, faction_name)
end

--- Opens a battle spot's dilemma for a human lord, built in script so it only shows the choices given a payload. Every battle dilemma has
--- the offers and missions registered as choices, which a dilemma fired from the DB would all show. Without offers it is Fight and Avoid.
--- @param event table The battle event from `battle_picker.pick`.
--- @param character character The lord who entered the spot.
--- @param faction faction The lord's faction.
--- @param with_offers boolean True to draw pre-battle offers and missions, see `M.roll`.
function M.open(event, character, faction, with_offers)
    local faction_name = faction:name()
    local ctx = { faction_name = faction_name, general_cqi = character:command_queue_index(), event = event, cards = {}, shown_units = {},
        keeps_out = battle_modifiers.keeps_out(event.modifiers) }
    local offers, missions = {}, {}
    if with_offers then offers, missions = M.draw(ctx) end
    --- Allies in the Dark names the theme its allied army marches as, so it is rolled once the offer is drawn.
    for _, key in ipairs(offers) do
        if offers_data.by_key[key].allies and not event.ally_theme then event.ally_theme = battle_modifiers.roll_ally_theme(faction:subculture(), event.faction) end
    end
    M.pending_by_faction[faction_name] = { dilemma = event.dilemma, offers = offers, missions = missions, general_cqi = ctx.general_cqi,
        difficulty = event.difficulty, cards = ctx.cards, taken = {}, battle = { general_cqi = ctx.general_cqi, missions = {} }, modifiers = event.modifiers,
        ally_theme = event.ally_theme }
    log("spot battle: " .. faction_name .. " opens " .. event.dilemma .. (with_offers and " with offers" or " plain") .. ", lord " .. ctx.general_cqi
        .. ", treasury " .. offer_effects.treasury(faction_name))
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
    offer_effects.merge_sabotage(event, fields)
    if fields.traitor then event.fewer_units = (event.fewer_units or 0) + fields.traitor.count end
    if fields.battle_bundle then
        event.battle_bundles = event.battle_bundles or {}
        event.battle_bundles[#event.battle_bundles + 1] = fields.battle_bundle
    end
    if fields.own_strength then event.own_strength = fields.own_strength end
    if fields.ally_bundle then
        event.ally_bundles = event.ally_bundles or {}
        event.ally_bundles[#event.ally_bundles + 1] = fields.ally_bundle
    end
    if fields.ally_ranks then event.ally_ranks = fields.ally_ranks end
    if fields.extra_ally_units then event.ally_options = army_generator.ally_options(event.ally_options.unit_count + fields.extra_ally_units) end
    if fields.ally_budget then
        event.ally_options = event.ally_options or {}
        event.ally_options.budget_multiplier = (event.ally_options.budget_multiplier or 1) * fields.ally_budget
    end
    if fields.allies then
        local units = random_number(fields.allies[2], fields.allies[1]) - 1
        event.intervention = ALLIED_REINFORCEMENTS_PERMITTED_TYPE
        event.ally_options = army_generator.ally_options(units)
        if event.ally_theme then
            event.ally_options.composition = battle_modifiers.composition({ event.ally_theme.key })
            event.ally_shorthand = event.ally_theme.faction
        end
        log("spot battle: the hired allied army fields its lord and " .. units .. " units"
            .. (event.ally_theme and ", " .. event.ally_theme.faction .. " as " .. event.ally_theme.key or ""))
    end
end

--- Takes a mission on the open dilemma: pays its cost, marks it taken (Guard the standard marks one of our units) and reopens the dilemma.
--- A mission already taken or shown as unaffordable just reopens it.
--- @param faction_name string The faction key.
--- @param pending table The open dilemma.
--- @param offer table The mission's offer record at the battle's difficulty.
local function take_mission(faction_name, pending, offer)
    if pending.taken[offer.key] or pending.shown_affordable[offer.key] == false then
        log("spot battle: mission " .. offer.key .. " is taken or was shown as unaffordable, nothing happens")
    else
        if offer.cost then cm:treasury_mod(faction_name, -spot_offers.offer_cost(offer)) end
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
            take_mission(faction_name, pending, offers_data.at(key, pending.difficulty))
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
        if spot_offers.choice_key(key) == choice_key then offer = offers_data.at(key, pending.difficulty) end
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
    if offer.cost then cm:treasury_mod(faction_name, -spot_offers.offer_cost(offer)) end
    apply_to_event(offer, event)
    if offer.gamble then
        local outcome = spot_offers.roll_outcome(offer.gamble)
        log("spot battle: " .. offer.key .. " rolls " .. outcome[2])
        apply_to_event(outcome, event)
        local raw_outcome = nil
        for _, entry in ipairs(offers_data.by_key[offer.key].gamble) do
            if entry[2] == outcome[2] then
                raw_outcome = entry
                break
            end
        end
        add_notice(event, steps.notice(offer.key .. "_" .. outcome[2], raw_outcome, pending.difficulty))
    elseif not offer.battle_bundle then
        --- A one-battle bundle is announced under its tower name, so only the other offers need their own notice. A trick's notice is its
        --- tower name too, which tells the battle script to play it.
        add_notice(event, steps.notice(offer.notice or offer.key, offers_data.by_key[offer.key], pending.difficulty))
    end
    log("spot battle: " .. faction_name .. " took " .. offer.key .. ", treasury " .. before .. " -> " .. offer_effects.treasury(faction_name)
        .. ", event budget x" .. tostring(event.budget_multiplier) .. ", fewer units " .. tostring(event.fewer_units) .. ", no heroes "
        .. tostring(event.no_heroes) .. ", max tier " .. tostring(event.max_tier) .. ", enemy strength " .. tostring(event.enemy_strength)
        .. ", champion strength " .. tostring(event.champion_strength) .. ", enemy bundles " .. table.concat(event.enemy_bundles or {}, ", ")
        .. ", stripped types " .. table.concat(sorted_keys(event.strip_types or {}), ", ") .. ", missions " .. table.concat(event.missions, ", "))
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
    for _, bundle in ipairs(battle_modifiers.bundles(event.modifiers, "ours")) do tower_army.apply_bundle(general_cqi, bundle) end
    if event.own_strength then
        for _, entry in ipairs(tower_army.unit_strengths(general_cqi)) do tower_army.set_strength(entry.unit, entry.strength * event.own_strength) end
        log("spot battle: our units start at " .. math.floor(event.own_strength * 100 + 0.5) .. "% of their strength")
    end
    offer_effects.log_army_change(general_cqi, "spot battle")
end

--- Hands the battle to the battle script: the one-battle bundles under their tower names, each offer's notice or trick, the missions and
--- the battle modifiers, with Night terrors' and the missions' targets. The enemy's units are read from the spawned army the first time
--- and kept on the event, so a battle re-armed after a load hands over the same targets.
--- @param event table The battle event.
--- @param army table|nil The spawned enemy Army, or nil when re-arming after a load.
function M.hand_to_battle(event, army)
    if army and not event.enemy_units then
        event.enemy_units = {}
        for _, row in ipairs(army.units or {}) do
            for _ = 1, row.count or 1 do event.enemy_units[#event.enemy_units + 1] = row.id end
        end
        event.trophy = tower_army.most_expensive(event.enemy_units, 1)[1]
        if event.ally_strength and army.reinforcing_ally_armies[1] then add_notice(event, "ally_relief_" .. math.floor(event.ally_strength * 100 + 0.5)) end
    end
    local names, targets, terrors = {}, {}, {}
    for _, bundle in ipairs(event.battle_bundles or {}) do names[#names + 1] = bundle:sub(#TOWER_BUNDLE_PREFIX + 1) end
    for _, notice in ipairs(event.notices or {}) do
        names[#names + 1] = notice
        local trick = offers_data.at(steps.split(notice), event.difficulty)
        if trick and trick.targets then
            event.night_terrors_targets = event.night_terrors_targets or tower_army.most_expensive(event.enemy_units or {}, trick.targets)
            terrors = event.night_terrors_targets
        end
        if trick and trick.trick and trick.battle_value then targets[#targets + 1] = trick.key .. "=" .. trick.battle_value end
    end
    for _, key in ipairs(event.missions or {}) do
        names[#names + 1] = key
        local offer = offers_data.at(key, event.difficulty)
        local value = offer.battle_value
        if offer.trophy then value = event.trophy end
        if offer.unit_ranks and event.standard then value = event.standard.key .. "#" .. event.standard.nth end
        if value then targets[#targets + 1] = key .. "=" .. value end
    end
    for _, name in ipairs(battle_modifiers.notices(event.modifiers)) do names[#names + 1] = name end
    log("spot battle: battle names: " .. (#names > 0 and table.concat(names, ", ") or "none") .. ", mission targets: " .. table.concat(targets, ", ")
        .. ", night terrors: " .. table.concat(terrors, ", "))
    tower_missions.clear_reports()
    core:svr_save_string(BATTLE_BUFFS_SVR_KEY, table.concat(names, ","))
    core:svr_save_string(MISSION_TARGETS_SVR_KEY, table.concat(targets, ","))
    core:svr_save_string(NIGHT_TERRORS_SVR_KEY, table.concat(terrors, ","))
end

--- Works out one mission met's rewards: gold, items, or a copy of the enemy's most expensive unit, which its result grants. Ranks for the
--- marked unit and our lord's experience are given here.
--- @param offer table The mission's offer record at the battle's difficulty.
--- @param event table The battle event.
--- @param faction_name string Our faction key.
--- @param general_cqi number Our lord's command queue index.
--- @returns table The rewards { gold, items, units } for the mission's result.
local function pay_mission(offer, event, faction_name, general_cqi)
    local gold = offer.gold
    local items = {}
    if offer.items then items = item_pool.pick_items(faction_name, offer.items.rarities, offer.items.count) end
    if offer.unique then items = offer_effects.pick_unique_items(faction_name, offer.unique) end
    if offer.battle_item then items = item_pool.pick_items(faction_name, (event.victory_items or {}).rarities or offers_data.default_battle_rarities, 1) end
    if offer.unit_ranks then
        local entry = event.standard and tower_missions.standard_unit({ general_cqi = general_cqi }, event.standard)
        if entry then cm:add_experience_to_unit(entry.unit, offer.unit_ranks) else log("spot battle: guard the standard found no marked unit") end
    end
    if offer.lord_xp then offer_effects.add_lord_xp(general_cqi, offer.lord_xp) end
    local units = offer.trophy and event.trophy and { event.trophy } or {}
    log("spot battle: mission " .. offer.key .. " pays" .. (gold and " " .. gold .. " gold" or "") .. (#items > 0 and ", items " .. table.concat(items, ", ") or "")
        .. (#units > 0 and ", trophy " .. units[1] or ""))
    return { gold = gold, items = items, units = units }
end

--- Settles a won battle's missions from what the battle script reported, with a result for each met or failed that grants its rewards. After
--- an auto-resolved battle nothing was counted: one result says so and gives back the paid missions' stakes.
--- @param event table The battle event.
--- @param faction_name string Our faction key.
--- @param general_cqi number Our lord's command queue index.
function M.settle_missions(event, faction_name, general_cqi)
    if not event.missions or #event.missions == 0 then return end
    local outcomes = tower_missions.read_outcomes({ missions = event.missions, standard = event.standard, trophy = event.trophy })
    local general = tower_army.character(general_cqi)
    local position = general and { general:logical_position_x(), general:logical_position_y() } or { 0, 0 }
    if outcomes.untracked then
        local refund = 0
        for _, key in ipairs(event.missions) do
            local offer = offers_data.at(key, event.difficulty)
            if offer.cost then refund = refund + spot_offers.offer_cost(offer) end
        end
        log("spot battle: the battle was auto-resolved, so no mission was counted and " .. refund .. " gold of stakes comes back")
        spot_offers.show_result(faction_name, "missions_untracked", { gold = refund, character = general, difficulty = event.difficulty }, position)
        return
    end
    for _, mission in ipairs(outcomes.missions) do
        local offer = offers_data.at(mission.key, event.difficulty)
        log("spot battle: mission " .. mission.key .. " " .. (mission.void and "void" or mission.met and "met" or "failed"))
        if not mission.void then
            local rewards = mission.met and pay_mission(offer, event, faction_name, general_cqi) or { items = {} }
            rewards.character = general
            rewards.difficulty = event.difficulty
            spot_offers.show_result(faction_name, "mission_" .. mission.key .. (mission.met and "_met" or "_failed"), rewards, position,
                rewards.items[1] and "ancillaries_onscreen_name_" .. rewards.items[1] or nil)
        end
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
    local bundles = {}
    for _, bundle in ipairs(event.battle_bundles or {}) do bundles[#bundles + 1] = bundle end
    for _, bundle in ipairs(battle_modifiers.bundles(event.modifiers, "ours")) do bundles[#bundles + 1] = bundle end
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
