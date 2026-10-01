--- Tower offers: draws the roguelite offers onto each go-deeper dilemma, builds their choices and applies the one the player takes. The
--- offer records live in configs/tower_offers.lua. This file holds when each offer can be drawn and what it does.

require("script/land_encounters/utils/random")

local offers_data = require("script/land_encounters/configs/tower_offers")
local tower_data = require("script/land_encounters/configs/tower_data")
local tower_army = require("script/land_encounters/features/tower_army")
local item_pool = require("script/land_encounters/core/item_pool")
local debug_config = require("script/land_encounters/configs/debug")
local tower_champions = require("script/land_encounters/configs/tower_champions")
local army_generator = require("script/land_encounters/core/army_generator")
local Army = require("script/land_encounters/core/army")

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Constants

--- Prefix of every offer's choice key. The rest is the offer's key in capitals.
local CHOICE_KEY_PREFIX = "LEAPOI_TWR_"
--- Prefix of every offer's payload line. The rest is the offer's key.
local LINE_PREFIX = "dummy_land_enc_tower_"
--- Payload line telling the player a stay offer brings them back to the same choice.
local RETURNS_HERE_LINE = "dummy_land_enc_tower_returns_here"
--- Script context value shown at the top of every per-floor go-deeper description through `ScriptObjectContext`.
local RESULT_CONTEXT_KEY = "land_enc_tower_result"
--- Prefix of the loc keys holding each stay offer's result line. The rest is the outcome, e.g. "loaded_dice_won".
local RESULT_LOC_PREFIX = "campaign_localised_strings_string_land_enc_tower_result_"
--- Payload line a taken stay offer shows in its slot for the rest of the floor.
local TAKEN_LINE = "dummy_land_enc_tower_taken"
--- Script context value holding the climb list in every per-floor go-deeper description.
local CLIMB_CONTEXT_KEY = "land_enc_tower_climb"
--- Prefix of the loc keys holding the climb list templates. The rest is the template, e.g. "cleared" or "difficulty_hard".
local CLIMB_LOC_PREFIX = "campaign_localised_strings_string_land_enc_tower_climb_"
--- Prefix of every tower effect bundle key. The rest names the buff in the floor battle's notice.
local BUNDLE_PREFIX = "land_enc_effect_tower_"
--- svr key the floor battle's script reads the active buffs from. Mirrored in script/battle/mod/land_enc_tower_buffs.lua.
local BATTLE_BUFFS_SVR_KEY = "land_enc_tower_battle_buffs"
--- Prefix of each choice row's id in the dilemma panel's list. The dilemma key and the choice key follow.
local CHOICE_ROW_PREFIX = "CcoCdirEventsDilemmaChoiceDetailRecord"

local M = {
    --- Choice key of Leave on the per-floor go-deeper dilemmas.
    LEAVE = offers_data.leave_choice_key,
}

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Helpers

--- Rounds gold to the tower's gold step.
--- @param gold number The gold amount.
--- @returns number The amount rounded to a multiple of `tower_data.gold_step`.
local function round_gold(gold)
    return math.floor(gold / tower_data.gold_step + 0.5) * tower_data.gold_step
end

--- Writes gold with thousands separators, e.g. 3000 as "3,000".
--- @param gold number The gold amount.
--- @returns string The formatted amount.
local function gold_text(gold)
    local text = tostring(math.floor(gold)):reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return (text:gsub("^,", ""))
end

--- True when the haul holds enough gold for a gold offer to change it.
--- @param delve table The delve record.
--- @returns boolean True with at least two gold steps in the haul.
local function has_gold(delve)
    return delve.haul.gold >= 2 * tower_data.gold_step
end

--- Finds an offer record by its key.
--- @param key string The offer key, e.g. "war_rites".
--- @returns table|nil The offer record.
local function find(key)
    for _, offer in ipairs(offers_data.offers) do
        if offer.key == key then return offer end
    end
    return nil
end

--- True when the delving army has lost any strength.
--- @param ctx table The offer context: { delve, faction_name, dividends }.
--- @returns boolean True when the army is below full strength.
local function army_damaged(ctx)
    local strength = tower_army.army_strength(ctx.delve.general_cqi)
    return strength ~= nil and strength < 100
end

--- Heals the army by the offer's `heal_share`.
--- @param offer table The offer record.
--- @param ctx table The offer context.
local function heal(offer, ctx)
    tower_army.heal_army(ctx.delve.general_cqi, offer.heal_share)
end

--- Adds changes to the next floor on the delve. Budget and gold multipliers stack, `sabotage` offer keys add up in the order taken, and any
--- other field replaces what was there: `record` (a floor record fought instead), `faction` (the army's faction), `rarity_shift`,
--- `double_or_nothing` (the loss limit) and `bonus` (a hidden floor).
--- @param delve table The delve record.
--- @param changes table The changes: { budget, gold, sabotage, record, faction, rarity_shift, double_or_nothing, bonus }.
local function change_next_floor(delve, changes)
    local next_floor = delve.next_floor or {}
    for key, value in pairs(changes) do
        if key == "budget" or key == "gold" then
            next_floor[key] = (next_floor[key] or 1) * value
        elseif key == "sabotage" then
            next_floor.sabotage = next_floor.sabotage or {}
            next_floor.sabotage[#next_floor.sabotage + 1] = value
        else
            next_floor[key] = value
        end
    end
    delve.next_floor = next_floor
end

--- Copies a floor record, so an offer can change one floor without touching the config.
--- @param record table A floor record from `tower_data.floors`.
--- @returns table The copy.
local function copy_floor(record)
    local copy = {}
    for key, value in pairs(record) do copy[key] = value end
    return copy
end

--- True when a floor follows the next one, so the next floor is not the Master's.
--- @param ctx table The offer context.
--- @returns boolean True when the next floor is not the last.
local function next_is_not_master(ctx)
    return ctx.delve.floor + 1 < #tower_data.floors
end

--- Puts a bundle on the delving army until removed.
--- @param delve table The delve record.
--- @param bundle string The effect bundle key.
--- @returns boolean True when the army was found.
local function apply_army_bundle(delve, bundle)
    local force = tower_army.delving_force(delve.general_cqi)
    if not force then return false end
    cm:apply_effect_bundle_to_force(bundle, force:command_queue_index(), 0)
    log("tower: " .. bundle .. " on force " .. force:command_queue_index() .. ", present: " .. tostring(force:has_effect_bundle(bundle)))
    return true
end

--- Puts a bundle on the delving army for the next floor's battle only. `M.end_battle_effects` takes it off when that floor resolves.
--- @param delve table The delve record.
--- @param bundle string The effect bundle key.
local function add_battle_bundle(delve, bundle)
    if not apply_army_bundle(delve, bundle) then return end
    delve.battle_bundles = delve.battle_bundles or {}
    delve.battle_bundles[#delve.battle_bundles + 1] = bundle
end

--- Applies a battle buff: its bundle, or with `per_floor` this floor's version of it.
--- @param offer table The offer record.
--- @param ctx table The offer context.
local function battle_buff(offer, ctx)
    add_battle_bundle(ctx.delve, offer.effect_bundle .. (offer.per_floor and "_" .. ctx.delve.floor or ""))
end

--- Applies a sabotage offer: the next floor's army is built and marked with it, see `M.sabotage_options`.
--- @param offer table The offer record.
--- @param ctx table The offer context.
local function sabotage(offer, ctx)
    change_next_floor(ctx.delve, { sabotage = offer.key })
end

--- An offer's gold cost from the haul: its fixed `cost`, or its `cost_share` of the haul's gold.
--- @param offer table The offer record.
--- @param delve table The delve record.
--- @returns number The cost, 0 for a free offer.
local function offer_cost(offer, delve)
    if offer.cost_share then return round_gold(delve.haul.gold * offer.cost_share) end
    return offer.cost or 0
end

--- Adds an item to the haul unless it already holds it.
--- @param haul table The delve's haul.
--- @param item string The ancillary key.
local function add_item(haul, item)
    for _, held in ipairs(haul.items) do
        if held == item then return end
    end
    haul.items[#haul.items + 1] = item
end

--- True when an offer on the current dilemma was already taken there, so its slot only says so. A repeatable offer is never used up.
--- @param offer table The offer record.
--- @param delve table The delve record.
--- @returns boolean True when the offer is used up.
local function spent(offer, delve)
    return delve.taken[offer.key] and not offer.repeatable
end

--- Skips floors past the next one, marking each as skipped in the climb list.
--- @param delve table The delve record.
--- @param count number How many floors to skip.
local function skip_floors(delve, count)
    delve.climb = delve.climb or {}
    for _ = 1, count do
        delve.floor = delve.floor + 1
        delve.climb[#delve.climb + 1] = { floor = delve.floor, difficulty = tower_data.floors[delve.floor].difficulty, state = "skipped" }
    end
end

--- Reads a climb list template.
--- @param key string The template, e.g. "cleared".
--- @returns string The template text.
local function climb_text(key)
    return common.get_localised_string(CLIMB_LOC_PREFIX .. key)
end

--- Names a floor for the climb list, e.g. "Floor 2 (medium)", with the Master's and the hidden floor named as such.
--- @param floor number The floor number.
--- @param difficulty string The difficulty it was or will be fought at.
--- @param bonus boolean|nil True for a hidden floor.
--- @returns string The floor's name.
local function floor_name(floor, difficulty, bonus)
    local shown = climb_text("difficulty_" .. difficulty)
    if shown == "" then shown = difficulty end
    if bonus then return string.format(climb_text("hidden"), shown) end
    return string.format(climb_text(floor == #tower_data.floors and "master" or "floor"), floor, shown)
end

--- True when the delving army has room for `count` more units.
--- @param ctx table The offer context.
--- @param count number The units an offer adds.
--- @returns boolean True with at least `count` free slots.
local function has_room(ctx, count)
    local force = tower_army.delving_force(ctx.delve.general_cqi)
    return force ~= nil and tower_army.free_slots(force) >= count
end

--- Keeps a unit offer's picked units on the delve, so its choice shows them as cards and its payload adds them to the army.
--- @param offer table The offer record.
--- @param ctx table The offer context.
--- @param units table The picked unit keys.
--- @returns boolean True when all `offer.count` units were found.
local function hold_units(offer, ctx, units)
    ctx.delve.offer_units = ctx.delve.offer_units or {}
    ctx.delve.offer_units[offer.key] = units
    return #units == offer.count
end

--- Finds the faction shorthand of the delving faction's culture.
--- @param faction_name string The faction key.
--- @returns string|nil The shorthand, or nil when its culture has no army data.
local function culture_shorthand(faction_name)
    local faction = cm:get_faction(faction_name)
    return faction and Army.faction_shorthand_for_subculture(faction:subculture()) or nil
end

--- Collects the agent subtypes every human faction's characters have, so a Tower champion never copies a legendary lord a player holds.
--- @returns table A subtype -> true set.
local function human_held_subtypes()
    local held = {}
    for _, name in ipairs(cm:get_human_factions()) do
        local faction = cm:get_faction(name)
        local characters = faction and faction.character_list and faction:character_list()
        for i = 0, characters and characters:num_items() - 1 or -1 do
            held[characters:item_at(i):character_subtype_key()] = true
        end
    end
    return held
end

--- Draw condition of the recruit offers: room in the army, and `offer.count` units of `offer.tiers` and `offer.unit_types` from the
--- tower's faction (`offer.from_tower`) or the delving faction's culture.
--- @param ctx table The offer context.
--- @param offer table The offer record.
--- @returns boolean True when the units were picked.
local function recruit(ctx, offer)
    if not has_room(ctx, offer.count) then return false end
    local shorthand = nil
    if offer.from_tower then
        shorthand = ctx.tower and ctx.tower.faction
    else
        shorthand = culture_shorthand(ctx.faction_name)
    end
    return hold_units(offer, ctx, shorthand and army_generator.pick_units(shorthand, offer.tiers, offer.unit_types, offer.count) or {})
end

--- Draw condition of Regiment of renown: room in the army, and a Regiment of Renown of the delving faction's culture that it does not field.
--- @param ctx table The offer context.
--- @param offer table The offer record.
--- @returns boolean True when one was picked.
local function regiment_of_renown(ctx, offer)
    if not has_room(ctx, offer.count) then return false end
    local shorthand = culture_shorthand(ctx.faction_name)
    local fielded = {}
    for _, entry in ipairs(tower_army.unit_strengths(ctx.delve.general_cqi)) do fielded[entry.unit:unit_key()] = true end
    local units = shorthand and army_generator.pick_units(shorthand, { 0, 1, 2, 3, 4, 5 }, nil, offer.count, { renown = true, exclude = fielded }) or {}
    return hold_units(offer, ctx, units)
end

--- The regular units that can still take an offer's ranks.
--- @param ctx table The offer context.
--- @param offer table The offer record: `ranks` and `max_rank`.
--- @returns table The `tower_army.regular_units` entries below `max_rank - ranks`, plus one.
local function rankable_units(ctx, offer)
    local list = {}
    for _, entry in ipairs(tower_army.regular_units(ctx.delve.general_cqi)) do
        if entry.unit:experience_level() <= offer.max_rank - offer.ranks then list[#list + 1] = entry end
    end
    return list
end

--- Removes one unit from the delving army. The game only removes by unit key, taking a copy of its own choosing, so when the army has other
--- copies the ones left are given the strengths they had beside this unit, strongest to strongest. The result matches removing this one.
--- @param ctx table The offer context.
--- @param entry table The unit's `tower_army.unit_strengths` entry.
local function remove_unit(ctx, entry)
    local general_cqi = ctx.delve.general_cqi
    local key = entry.unit:unit_key()
    local kept = {}
    for _, other in ipairs(tower_army.regular_units(general_cqi)) do
        if other.index ~= entry.index and other.unit:unit_key() == key then kept[#kept + 1] = other.strength end
    end
    local lookup = cm:char_lookup_str(cm:get_character_by_cqi(general_cqi))
    log("tower: removing unit " .. key .. " at " .. entry.index .. " (" .. math.floor(entry.strength + 0.5) .. "%) from " .. lookup)
    cm:remove_unit_from_character(lookup, key)
    if #kept == 0 then return end
    local copies = {}
    for _, other in ipairs(tower_army.regular_units(general_cqi)) do
        if other.unit:unit_key() == key then copies[#copies + 1] = other end
    end
    table.sort(kept, function(a, b) return a > b end)
    table.sort(copies, function(a, b) return a.strength > b.strength end)
    for i, copy in ipairs(copies) do
        if kept[i] then tower_army.set_strength(copy.unit, kept[i]) end
    end
end

--- Logs the delving army now and again half a second later, once the game has applied an offer's changes, so they can be checked.
--- @param general_cqi number The delving lord's command queue index.
--- @param offer_key string The offer's key for the log.
local function log_army_change(general_cqi, offer_key)
    tower_army.log_army(general_cqi, "before " .. offer_key)
    cm:callback(function() tower_army.log_army(general_cqi, "after " .. offer_key) end, 0.5)
end

--- Puts a faction offer's bundle on the delving faction.
--- @param offer table The offer record: `effect_bundle` and `turns`.
--- @param ctx table The offer context.
--- @returns string The result outcome, the offer's key.
local function faction_bundle(offer, ctx)
    cm:apply_effect_bundle(offer.effect_bundle, ctx.faction_name, offer.turns)
    log("tower: " .. offer.effect_bundle .. " on faction " .. ctx.faction_name .. " for " .. offer.turns .. " turns")
    return offer.key
end

--- Reads the faction's treasury.
--- @param faction_name string The faction key.
--- @returns number The treasury gold, or 0 when the faction is missing.
local function treasury(faction_name)
    local faction = cm:get_faction(faction_name)
    return faction and faction:treasury() or 0
end

--- When each offer can be drawn and what it does. `eligible(ctx)` returns true when the offer would do something. `apply(offer, ctx)` runs
--- after its cost is paid. A stay offer's `apply` returns its outcome (the result loc key suffix) and the values for that line's
--- placeholders. `ctx` is { delve, faction_name, dividends }. An offer with no entry is always eligible and does nothing.
local HANDLERS = {
    tend_wounded = { eligible = army_damaged, apply = heal },
    field_surgeons = { eligible = army_damaged, apply = heal },
    forgotten_shrine = { eligible = army_damaged, apply = heal },
    triage = {
        eligible = army_damaged,
        apply = function(offer, ctx)
            local units = tower_army.unit_strengths(ctx.delve.general_cqi)
            local battered = {}
            for _, entry in ipairs(units) do
                if entry.strength < 100 then battered[#battered + 1] = entry end
            end
            table.sort(battered, function(a, b) return a.strength < b.strength end)
            local healed = {}
            for i = 1, math.min(offer.count, #battered) do
                tower_army.set_strength(battered[i].unit, 100)
                healed[battered[i]] = true
            end
            local healthiest = nil
            for _, entry in ipairs(units) do
                if not healed[entry] and (healthiest == nil or entry.strength > healthiest.strength) then healthiest = entry end
            end
            if healthiest then tower_army.set_strength(healthiest.unit, healthiest.strength - offer.penalty) end
        end,
    },
    blood_transfusion = {
        eligible = army_damaged,
        apply = function(offer, ctx)
            heal(offer, ctx)
            local force = tower_army.delving_force(ctx.delve.general_cqi)
            if force then
                cm:apply_effect_bundle_to_force(offer.effect_bundle, force:command_queue_index(), offer.turns)
                log("tower: " .. offer.effect_bundle .. " on force " .. force:command_queue_index() .. " for " .. offer.turns .. " turns")
            end
        end,
    },
    rest_by_the_fire = {
        eligible = army_damaged,
        apply = function(offer, ctx)
            heal(offer, ctx)
            change_next_floor(ctx.delve, { budget = offer.next_budget })
        end,
    },
    reforge_the_fallen = {
        eligible = function(ctx)
            for _, entry in ipairs(tower_army.unit_strengths(ctx.delve.general_cqi)) do
                if entry.strength < find("reforge_the_fallen").below then return true end
            end
            return false
        end,
        apply = function(_, ctx)
            local weakest = nil
            for _, entry in ipairs(tower_army.unit_strengths(ctx.delve.general_cqi)) do
                if weakest == nil or entry.strength < weakest.strength then weakest = entry end
            end
            if weakest then tower_army.set_strength(weakest.unit, 100) end
        end,
    },
    war_rites = { apply = battle_buff },
    whetstones_and_oil = { apply = battle_buff },
    warding_sigils = { apply = battle_buff },
    fire_kissed_blades = { apply = battle_buff },
    enchanted_steel = { apply = battle_buff },
    quartermasters_cache = { apply = battle_buff },
    drill_sergeant = { apply = battle_buff },
    iron_resolve = { apply = battle_buff },
    stoneskin = { apply = battle_buff },
    scaling_blessing = { eligible = function(ctx) return has_gold(ctx.delve) end, apply = battle_buff },
    loaded_dice = {
        eligible = function(ctx) return has_gold(ctx.delve) end,
        apply = function(_, ctx)
            local haul = ctx.delve.haul
            local won = random_number(2) == 1
            haul.gold = won and haul.gold * 2 or round_gold(haul.gold / 2)
            return won and "loaded_dice_won" or "loaded_dice_lost", { gold_text(haul.gold) }
        end,
    },
    send_a_runner = {
        eligible = function(ctx) return has_gold(ctx.delve) end,
        apply = function(offer, ctx)
            local haul = ctx.delve.haul
            local sent = round_gold(haul.gold * offer.share)
            local banked = round_gold(sent * (1 - offer.fee))
            haul.gold = haul.gold - sent
            cm:treasury_mod(ctx.faction_name, banked)
            return "send_a_runner", { gold_text(banked), gold_text(haul.gold) }
        end,
    },
    tower_vault = {
        --- The legendary is picked once per delve when the vault is first considered, so the offer only shows when one qualifies.
        eligible = function(ctx)
            ctx.delve.vault_item = ctx.delve.vault_item or item_pool.pick_legendary_item(ctx.faction_name)
            return ctx.delve.vault_item ~= nil
        end,
        apply = function(_, ctx)
            local item = ctx.delve.vault_item or item_pool.pick_legendary_item(ctx.faction_name)
            ctx.delve.vault_item = nil
            if not item then return end
            add_item(ctx.delve.haul, item)
            local name = common.get_localised_string("ancillaries_onscreen_name_" .. item)
            return "tower_vault", { name ~= "" and name or item }
        end,
    },
    treasure_map = {
        eligible = function(ctx)
            local next_floor = tower_data.floors[ctx.delve.floor + 1]
            return next_floor ~= nil and next_floor.item_rarities ~= nil
        end,
        apply = function(_, ctx) change_next_floor(ctx.delve, { rarity_shift = 1 }) end,
    },
    greedy_climb = { apply = function(offer, ctx) change_next_floor(ctx.delve, { budget = offer.next_budget, gold = offer.next_gold }) end },
    bribe_the_guards = { apply = function(offer, ctx) change_next_floor(ctx.delve, { budget = offer.next_budget }) end },
    poison_the_stores = { apply = sabotage },
    kill_the_captain = { apply = sabotage },
    thin_the_ranks = { apply = sabotage },
    lower_tiers_only = { apply = sabotage },
    break_their_spirit = { apply = sabotage },
    curse_their_blades = { apply = sabotage },
    regiment_of_renown = { eligible = regiment_of_renown },
    veterans_oath = {
        eligible = function(ctx, offer) return #rankable_units(ctx, offer) >= offer.count end,
        apply = function(offer, ctx)
            local pool = rankable_units(ctx, offer)
            for _ = 1, math.min(offer.count, #pool) do
                local entry = table.remove(pool, random_number(#pool))
                log("tower: +" .. offer.ranks .. " ranks to " .. entry.unit:unit_key() .. " at " .. entry.index)
                cm:add_experience_to_unit(entry.unit, offer.ranks)
            end
        end,
    },
    swap_the_chaff = {
        eligible = function(ctx) return #(ctx.delve.floor_units or {}) > 0 and tower_army.weakest_regular_unit(ctx.delve.general_cqi) ~= nil end,
        apply = function(_, ctx)
            local captives = ctx.delve.floor_units
            remove_unit(ctx, tower_army.weakest_regular_unit(ctx.delve.general_cqi))
            local captive = table.remove(captives, random_number(#captives))
            log("tower: granting captive " .. captive)
            cm:grant_unit_to_character(cm:char_lookup_str(cm:get_character_by_cqi(ctx.delve.general_cqi)), captive)
        end,
    },
    blood_price = {
        eligible = function(ctx) return army_damaged(ctx) and #tower_army.regular_units(ctx.delve.general_cqi) >= 2 end,
        apply = function(_, ctx)
            local weakest = tower_army.weakest_regular_unit(ctx.delve.general_cqi)
            for _, entry in ipairs(tower_army.unit_strengths(ctx.delve.general_cqi)) do
                if entry.index ~= weakest.index then tower_army.set_strength(entry.unit, 100) end
            end
            remove_unit(ctx, weakest)
        end,
    },
    lessons_in_blood = {
        apply = function(offer, ctx)
            cm:add_agent_experience(cm:char_lookup_str(cm:get_character_by_cqi(ctx.delve.general_cqi)), offer.ranks, true)
        end,
    },
    rousing_speech = { apply = battle_buff },
    towers_favour = { apply = faction_bundle },
    research_scrolls = { apply = faction_bundle },
    recruitment_cache = { apply = faction_bundle },
    --- The unit offers' payloads add their units, so taking them only needs the gold paid.
    ransom_a_captive = {
        eligible = function(ctx, offer)
            local captives = ctx.delve.floor_units or {}
            return has_room(ctx, offer.count) and #captives > 0 and hold_units(offer, ctx, { captives[random_number(#captives)] })
        end,
    },
    elite_recruit = { eligible = recruit },
    conscripts = { eligible = recruit },
    captured_war_machine = { eligible = recruit },
    tower_dividends = {
        apply = function(offer, ctx)
            ctx.dividends[#ctx.dividends + 1] = { faction = ctx.faction_name, amount = offer.per_turn, turns = offer.turns }
            cm:apply_effect_bundle(offer.effect_bundle, ctx.faction_name, offer.turns)
            return "tower_dividends", { gold_text(offer.per_turn), offer.turns }
        end,
    },
    strip_the_dead = {
        eligible = function(ctx) return (ctx.delve.floor_army_size or 0) > 0 end,
        apply = function(offer, ctx)
            local gold = ctx.delve.floor_army_size * offer.per_unit
            ctx.delve.haul.gold = ctx.delve.haul.gold + gold
            return "strip_the_dead", { gold_text(gold), gold_text(ctx.delve.haul.gold) }
        end,
    },
    tithe = {
        eligible = function(ctx) return treasury(ctx.faction_name) >= find("tithe").min_treasury end,
        apply = function(offer, ctx)
            local paid = round_gold(treasury(ctx.faction_name) * offer.share)
            cm:treasury_mod(ctx.faction_name, -paid)
            ctx.delve.haul.gold = ctx.delve.haul.gold + paid * offer.multiplier
            return "tithe", { gold_text(paid), gold_text(paid * offer.multiplier) }
        end,
    },
    cursed_idol = {
        apply = function(offer, ctx)
            ctx.delve.haul.gold = ctx.delve.haul.gold + offer.gold
            change_next_floor(ctx.delve, { budget = offer.next_budget })
        end,
    },
    double_or_nothing = { apply = function(offer, ctx) change_next_floor(ctx.delve, { double_or_nothing = offer.max_loss }) end },
    hellforge_pact = {
        apply = function(offer, ctx)
            if apply_army_bundle(ctx.delve, offer.effect_bundle) then ctx.delve.hellforge = true end
        end,
    },
    blood_moon = {
        eligible = next_is_not_master,
        apply = function(_, ctx) change_next_floor(ctx.delve, { record = tower_data.floors[#tower_data.floors] }) end,
    },
    roll_the_bones = {
        apply = function(offer, ctx)
            local roll = random_number(4)
            if roll == 1 then
                add_battle_bundle(ctx.delve, find("war_rites").effect_bundle)
                return "roll_the_bones_rites"
            elseif roll == 2 then
                ctx.delve.haul.gold = ctx.delve.haul.gold + offer.gold
                return "roll_the_bones_gold", { gold_text(offer.gold) }
            elseif roll == 3 then
                change_next_floor(ctx.delve, { budget = offer.next_budget })
                return "roll_the_bones_foe"
            end
            for _, entry in ipairs(tower_army.unit_strengths(ctx.delve.general_cqi)) do
                tower_army.set_strength(entry.unit, entry.strength - offer.bleed)
            end
            return "roll_the_bones_bleed", { offer.bleed }
        end,
    },
    tempt_fate = {
        eligible = next_is_not_master,
        apply = function(offer, ctx)
            local delve = ctx.delve
            local skipped = tower_data.floors[delve.floor + 1]
            delve.haul.gold = delve.haul.gold + round_gold(skipped.gold * offer.reward_share)
            for _, item in ipairs(item_pool.pick_items(ctx.faction_name, skipped.item_rarities, math.floor(skipped.item_count * offer.reward_share))) do
                add_item(delve.haul, item)
            end
            skip_floors(delve, offer.skips)
            local after = copy_floor(tower_data.floors[delve.floor + 1])
            after.difficulty = tower_data.difficulty_order[#tower_data.difficulty_order]
            change_next_floor(delve, { record = after })
        end,
    },
    reroll = {
        apply = function(_, ctx)
            ctx.delve.offers = M.draw(ctx.delve, ctx.faction_name, ctx.tower)
            return "reroll"
        end,
    },
    secret_stair = {
        eligible = next_is_not_master,
        apply = function(offer, ctx) skip_floors(ctx.delve, offer.skips) end,
    },
    hidden_floor = {
        apply = function(_, ctx)
            --- A few tries at a faction other than the tower's. With a single enabled faction the bonus floor uses it too.
            local faction = get_random_faction()
            for _ = 1, 5 do
                if not ctx.tower or faction ~= ctx.tower.faction then break end
                faction = get_random_faction()
            end
            change_next_floor(ctx.delve, { record = tower_data.hidden_floor, faction = faction, bonus = true })
            ctx.delve.bonus_floor = true
        end,
    },
    soft_landing = {
        eligible = function(ctx)
            local next_floor = tower_data.floors[ctx.delve.floor + 1]
            return next_floor ~= nil and next_floor.difficulty ~= tower_data.difficulty_order[1]
        end,
        apply = function(offer, ctx)
            local record = copy_floor(tower_data.floors[ctx.delve.floor + 1])
            for i, difficulty in ipairs(tower_data.difficulty_order) do
                if difficulty == record.difficulty then record.difficulty = tower_data.difficulty_order[math.max(1, i - 1)] break end
            end
            record.gold = record.gold * offer.reward_share
            change_next_floor(ctx.delve, { record = record })
        end,
    },
    glass_cannon = { apply = battle_buff },
    last_stand = {
        eligible = army_damaged,
        apply = function(offer, ctx)
            heal(offer, ctx)
            ctx.delve.last_stand = true
        end,
    },
    plague_bearer = {
        apply = function(offer, ctx)
            ctx.delve.haul.gold = ctx.delve.haul.gold + offer.gold
            local force = tower_army.delving_force(ctx.delve.general_cqi)
            if force then
                cm:apply_effect_bundle_to_force(offer.effect_bundle, force:command_queue_index(), offer.turns)
                log("tower: " .. offer.effect_bundle .. " on force " .. force:command_queue_index() .. " for " .. offer.turns .. " turns")
            end
        end,
    },
    mirror_curse = { apply = function(offer, ctx) change_next_floor(ctx.delve, { mirror = true, sabotage = offer.key }) end },
    daemons_deal = {
        --- The unique items are picked when the offer is considered, so it only shows when enough qualify.
        eligible = function(ctx, offer)
            local items, tries = {}, 0
            while #items < offer.items and tries < offer.items * 5 do
                tries = tries + 1
                local item = item_pool.pick_legendary_item(ctx.faction_name)
                local fresh = item ~= nil
                for _, held in ipairs(items) do fresh = fresh and held ~= item end
                if fresh then items[#items + 1] = item end
            end
            ctx.delve.deal_items = items
            return #items == offer.items
        end,
        apply = function(_, ctx)
            for _, item in ipairs(ctx.delve.deal_items or {}) do add_item(ctx.delve.haul, item) end
            ctx.delve.daemons_deal = true
            return "daemons_deal", { #(ctx.delve.deal_items or {}) }
        end,
    },
    tower_champion = {
        --- The legendary lord is picked when the offer is considered, from those of the tower's faction that no human holds.
        eligible = function(ctx)
            if not ctx.tower or not next_is_not_master(ctx) then return false end
            local held, pool = human_held_subtypes(), {}
            for _, subtype in ipairs(tower_champions[ctx.tower.faction] or {}) do
                if not held[subtype] then pool[#pool + 1] = subtype end
            end
            ctx.delve.champion = #pool > 0 and pool[random_number(#pool)] or nil
            return ctx.delve.champion ~= nil
        end,
        apply = function(offer, ctx)
            change_next_floor(ctx.delve, { champion = ctx.delve.champion, gold = offer.next_gold, sabotage = offer.key })
        end,
    },
    echoes_of_the_climb = {
        eligible = function(ctx) return ctx.tower ~= nil and not (ctx.tower.echoes or {})[ctx.faction_name] end,
        apply = function(_, ctx)
            ctx.tower.echoes = ctx.tower.echoes or {}
            ctx.tower.echoes[ctx.faction_name] = true
        end,
    },
}

--- True when an offer can be drawn: not already taken this delve (unless repeatable) and its condition holds.
--- @param offer table The offer record.
--- @param ctx table The offer context.
--- @returns boolean True when the offer can be drawn.
local function eligible(offer, ctx)
    if ctx.delve.taken[offer.key] and not offer.repeatable then return false end
    local handler = HANDLERS[offer.key]
    return not (handler and handler.eligible) or handler.eligible(ctx, offer)
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Offers

--- Builds an offer's choice key.
--- @param offer table The offer record.
--- @returns string The choice key, e.g. "LEAPOI_TWR_WAR_RITES".
function M.choice_key(offer)
    return CHOICE_KEY_PREFIX .. offer.key:upper()
end

--- Draws up to `offers_per_floor` eligible offers with `random_number`, so every multiplayer client draws the same ones. Eligible offers in
--- the debug `force_offers` list (configs/debug.lua) are drawn first.
--- @param delve table The delve record.
--- @param faction_name string The delving faction.
--- @param tower TowerState|nil The delve's tower. Offers about the tower itself are not drawn without it.
--- @returns table Offer keys in popup order.
function M.draw(delve, faction_name, tower)
    delve.taken = delve.taken or {}
    local ctx = { delve = delve, faction_name = faction_name, tower = tower }
    local pool = {}
    for _, offer in ipairs(offers_data.offers) do
        if eligible(offer, ctx) then pool[#pool + 1] = offer.key end
    end
    local picked, count = {}, 0
    for _, key in ipairs(debug_config.force_offers) do
        for i, pooled in ipairs(pool) do
            if pooled == key and count < offers_data.offers_per_floor then
                picked[table.remove(pool, i)] = true
                count = count + 1
                break
            end
        end
    end
    for _ = 1, math.min(offers_data.offers_per_floor - count, #pool) do
        picked[table.remove(pool, random_number(#pool))] = true
    end
    local keys = {}
    for _, offer in ipairs(offers_data.offers) do
        if picked[offer.key] then keys[#keys + 1] = offer.key end
    end
    log("tower: drew for " .. faction_name .. " on floor " .. delve.floor .. ": " .. table.concat(keys, ", ") .. " (" .. #keys + #pool .. " eligible, "
        .. count .. " forced)")
    return keys
end

--- Writes a delve's next-floor changes for the log, e.g. "{budget=1.2, gold=2}".
--- @param next_floor table|nil The delve's next-floor changes.
--- @returns string The changes in key order, "{}" for none.
function M.describe_next_floor(next_floor)
    local keys = {}
    for key in pairs(next_floor or {}) do keys[#keys + 1] = key end
    table.sort(keys)
    local parts = {}
    for _, key in ipairs(keys) do
        local value = next_floor[key]
        if key == "record" then
            value = value.difficulty .. " floor"
        elseif type(value) == "table" then
            value = table.concat(value, "+")
        end
        parts[#parts + 1] = key .. "=" .. tostring(value)
    end
    return "{" .. table.concat(parts, ", ") .. "}"
end

--- Builds an offer's go-deeper choice: its line (or its not-enough-gold line when the haul cannot pay), then where it leads. A skip leads
--- past the next floor, and a bonus floor's own line already says where it leads. A stay offer taken on this floor only says it was taken.
--- A unit offer the haul can pay for shows its units as cards, and its payload adds them to the army.
--- @param offer_key string The offer key.
--- @param delve table The delve record.
--- @param next_floor number The floor a climbing offer leads to.
--- @returns table A choice record for `launch_dilemma`.
function M.choice(offer_key, delve, next_floor)
    local offer = find(offer_key)
    if spent(offer, delve) then return { key = M.choice_key(offer), lines = { TAKEN_LINE } } end
    local affordable = delve.haul.gold >= offer_cost(offer, delve)
    local line = LINE_PREFIX .. offer.key .. (offer.per_floor and "_" .. delve.floor or "")
    local lines = { line .. (affordable and "" or "_unaffordable") }
    if offer.stay then
        lines[2] = RETURNS_HERE_LINE
    elseif not offer.bonus_floor then
        lines[2] = "dummy_land_enc_tower_descend_floor_" .. (next_floor + (offer.skips or 0))
    end
    local choice = { key = M.choice_key(offer), lines = lines }
    local units = (delve.offer_units or {})[offer.key]
    local force = units and affordable and tower_army.delving_force(delve.general_cqi)
    if force then choice.units = { force = force, keys = units } end
    return choice
end

--- Takes an offer from the delve's dilemma. When the haul can pay its cost it is paid, marked taken and applied. It keeps its slot, so a
--- stay offer taken again (its button greyed out or not) changes nothing.
--- @param choice_key string The chosen choice key.
--- @param delve table The delve record.
--- @param faction_name string The delving faction.
--- @param extras table { dividends = the tower delegate's dividend list, tower = the delve's TowerState }.
--- @returns table|nil The offer record, or nil when the choice is not an offer on the dilemma.
--- @returns string|nil The offer's result line for the reopened dilemma, or nil when it has none.
function M.take(choice_key, delve, faction_name, extras)
    extras = extras or {}
    local offer = nil
    delve.taken = delve.taken or {}
    for _, key in ipairs(delve.offers or {}) do
        if CHOICE_KEY_PREFIX .. key:upper() == choice_key then
            offer = find(key)
            break
        end
    end
    if offer == nil then
        log("tower: " .. tostring(choice_key) .. " is not an offer on this dilemma")
        return nil
    end
    local cost = offer_cost(offer, delve)
    if spent(offer, delve) then
        log("tower: " .. offer.key .. " was already taken on this floor, nothing happens")
        return offer
    end
    if delve.haul.gold < cost then
        log("tower: " .. offer.key .. " costs " .. cost .. " but the haul holds " .. delve.haul.gold .. ", nothing is bought")
        return offer
    end
    local gold_before, items_before = delve.haul.gold, #delve.haul.items
    log("tower: " .. faction_name .. " takes " .. offer.key .. " for " .. cost .. " gold (haul " .. gold_before .. " gold, " .. items_before .. " items)")
    log_army_change(delve.general_cqi, offer.key)
    delve.haul.gold = delve.haul.gold - cost
    delve.taken[offer.key] = true
    local handler = HANDLERS[offer.key]
    local outcome, values = nil, nil
    if handler and handler.apply then
        outcome, values = handler.apply(offer, { delve = delve, faction_name = faction_name, dividends = extras.dividends, tower = extras.tower })
    end
    log("tower: " .. offer.key .. " done: haul " .. gold_before .. " -> " .. delve.haul.gold .. " gold, " .. items_before .. " -> " .. #delve.haul.items
        .. " items, next floor " .. M.describe_next_floor(delve.next_floor) .. ", outcome " .. (outcome or "none"))
    if not outcome then return offer end
    local template = outcome and common.get_localised_string(RESULT_LOC_PREFIX .. outcome) or ""
    if template == "" then return offer end
    values = values or {}
    return offer, string.format(template, values[1], values[2])
end

--- Shows the floor's stay-offer results at the top of the per-floor go-deeper descriptions, one line each in the order taken, then a blank
--- line before the description. No results clears it.
--- @param delve table The delve record. `delve.results` holds this floor's result lines.
function M.show_results(delve)
    local results = delve.results or {}
    common.set_context_value(RESULT_CONTEXT_KEY, #results > 0 and table.concat(results, "\n") .. "\n\n" or "")
end

--- Shows the climb list in the per-floor go-deeper descriptions: each floor so far as cleared or skipped at the difficulty it had, any hidden
--- floor where it was fought, then the next floor and the ones ahead.
--- @param delve table The delve record. `delve.climb` holds the floors so far, in order.
function M.show_climb(delve)
    local lines = {}
    for _, entry in ipairs(delve.climb or {}) do
        lines[#lines + 1] = string.format(climb_text(entry.state), floor_name(entry.floor, entry.difficulty, entry.bonus))
    end
    for floor = delve.floor + 1, #tower_data.floors do
        lines[#lines + 1] = string.format(climb_text(floor == delve.floor + 1 and "next" or "ahead"), floor_name(floor, tower_data.floors[floor].difficulty))
    end
    common.set_context_value(CLIMB_CONTEXT_KEY, table.concat(lines, "\n"))
end

--- Greys out the buttons of the stay offers already taken on the open go-deeper dilemma, so each keeps its slot but cannot be clicked. Each
--- choice's row in the panel's list is named after its choice record. UI only: a taken slot that is clicked anyway just reopens.
--- @param delve table The delve record.
--- @param dilemma_key string The open go-deeper dilemma's key.
function M.grey_out_taken(delve, dilemma_key)
    local taken = {}
    for _, key in ipairs(delve.offers or {}) do
        local offer = find(key)
        if spent(offer, delve) then taken[CHOICE_ROW_PREFIX .. dilemma_key .. M.choice_key(offer)] = true end
    end
    if next(taken) == nil then return end
    --- The game's UI helpers live in the script environment, not in a required module's globals.
    local env = core:get_env()
    local list = env.find_uicomponent(core:get_ui_root(), "events", "event_layouts", "dilemma_active", "dilemma", "background", "dilemma_list")
    if not list then return end
    for i = 0, list:ChildCount() - 1 do
        local row = env.UIComponent(list:Find(i))
        local button = taken[row:Id()] and env.find_uicomponent(row, "choice_button")
        if button then
            button:SetState("inactive")
            button:SetDisabled(true)
        end
    end
end

--- Turns the sabotage taken for the next floor into what its army needs: generator options (`no_heroes`, `fewer_units`, `max_tier`) and what is
--- put on it once it spawns (`enemy_strength`, the lowest taken, and `enemy_bundles`).
--- @param next_floor table|nil The delve's next-floor changes.
--- @returns table The options, with `enemy_bundles` nil when no bundle was taken.
function M.sabotage_options(next_floor)
    local options = {}
    for _, key in ipairs(next_floor and next_floor.sabotage or {}) do
        local offer = find(key)
        options.no_heroes = options.no_heroes or offer.no_heroes
        options.fewer_units = offer.fewer_units and (options.fewer_units or 0) + offer.fewer_units or options.fewer_units
        options.max_tier = offer.max_tier and math.min(options.max_tier or offer.max_tier, offer.max_tier) or options.max_tier
        options.min_tier = offer.min_tier and math.max(options.min_tier or offer.min_tier, offer.min_tier) or options.min_tier
        options.enemy_strength = offer.enemy_strength and math.min(options.enemy_strength or 1, offer.enemy_strength) or options.enemy_strength
        if offer.enemy_bundle then
            options.enemy_bundles = options.enemy_bundles or {}
            options.enemy_bundles[#options.enemy_bundles + 1] = offer.enemy_bundle
        end
    end
    options.lord_subtype = next_floor and next_floor.champion
    return options
end

--- Copies the delving army's regular units for a Mirror curse army, one { id, count } row per unit key in army order.
--- @param delve table The delve record.
--- @returns table The rows.
--- @returns number How many units were copied.
function M.mirror_units(delve)
    local rows, by_key, total = {}, {}, 0
    for _, entry in ipairs(tower_army.regular_units(delve.general_cqi)) do
        local key = entry.unit:unit_key()
        if not by_key[key] then
            by_key[key] = { id = key, count = 0 }
            rows[#rows + 1] = by_key[key]
        end
        by_key[key].count = by_key[key].count + 1
        total = total + 1
    end
    return rows, total
end

--- The haul gold a won Mirror curse floor adds for the number of units it copied.
--- @param copied number How many units the mirror army copied.
--- @returns number The bonus gold, 0 below the smallest step.
function M.mirror_bonus(copied)
    for _, step in ipairs(find("mirror_curse").bonus) do
        if copied >= step.units then return step.gold end
    end
    return 0
end

--- Settles a floor's Last stand: a loss destroys the whole delving army, lord included, and either way the stake ends. The army falls once
--- the battle sequence ends, since touching the lord mid-sequence leaves the game stuck on a stale pre-battle screen. An immortal lord is
--- wounded by the game instead of dying.
--- @param delve table The delve record.
--- @param won boolean True when the floor was won.
function M.settle_last_stand(delve, won)
    local staked, general_cqi = delve.last_stand, delve.general_cqi
    delve.last_stand = nil
    if not staked or won then return end
    log("tower: Last stand lost, the army of lord " .. general_cqi .. " falls once the battle sequence ends")
    core:add_listener("land_enc_tower_last_stand_" .. general_cqi, "ScriptEventPlayerBattleSequenceCompleted", true, function()
        local general = cm:get_character_by_cqi(general_cqi)
        if not general or general:is_null_interface() then
            log("tower: Last stand lost, but lord " .. general_cqi .. " is gone")
            return
        end
        tower_army.log_army(general_cqi, "Last stand falls")
        cm:kill_character_and_commanded_unit(cm:char_lookup_str(general), true)
        log("tower: Last stand lost, the army of lord " .. general_cqi .. " is destroyed")
    end, false)
end

--- What a Daemon's deal sends at the delving faction's capital once the delve ends.
--- @returns table { difficulty, factions, spawn_distance }.
function M.daemon_army()
    local offer = find("daemons_deal")
    return { difficulty = offer.difficulty, factions = offer.factions, spawn_distance = offer.spawn_distance }
end

--- Hands the buffs on the delving army to the next battle's script, which announces them: the one-battle buffs, the Hellforge pact, Drained,
--- then the sabotage on the enemy. The list is comma-separated bundle names without `BUNDLE_PREFIX`, then sabotage offer keys. No delve hands over an
--- empty list.
--- @param delve table|nil The delve record.
function M.hand_buffs_to_battle(delve)
    local names, seen = {}, {}
    local bundles = {}
    for _, bundle in ipairs(delve and delve.battle_bundles or {}) do bundles[#bundles + 1] = bundle end
    if delve and delve.hellforge then bundles[#bundles + 1] = find("hellforge_pact").effect_bundle end
    --- Drained lasts turns, not a delve, so it is announced while the army still carries it.
    local force = delve and tower_army.delving_force(delve.general_cqi)
    local drained = find("blood_transfusion").effect_bundle
    if force and force:has_effect_bundle(drained) then bundles[#bundles + 1] = drained end
    if delve and delve.last_stand then bundles[#bundles + 1] = BUNDLE_PREFIX .. "last_stand" end
    for _, bundle in ipairs(bundles) do
        if not seen[bundle] then
            seen[bundle] = true
            names[#names + 1] = bundle:sub(#BUNDLE_PREFIX + 1)
        end
    end
    for _, key in ipairs(delve and delve.enemy_notices or {}) do names[#names + 1] = key end
    if delve then log("tower: battle notices for the next floor: " .. (#names > 0 and table.concat(names, ", ") or "none")) end
    core:svr_save_string(BATTLE_BUFFS_SVR_KEY, table.concat(names, ","))
end

--- Takes the one-battle effects off the delving army once the floor they were bought for is over, and clears the battle's buff list.
--- @param delve table The delve record.
function M.end_battle_effects(delve)
    M.hand_buffs_to_battle(nil)
    delve.enemy_notices = nil
    local bundles = delve.battle_bundles or {}
    delve.battle_bundles = nil
    local force = tower_army.delving_force(delve.general_cqi)
    if not force then return end
    if #bundles > 0 then log("tower: removing one-battle bundles: " .. table.concat(bundles, ", ")) end
    for _, bundle in ipairs(bundles) do cm:remove_effect_bundle_from_force(bundle, force:command_queue_index()) end
end

--- Takes the delve-long effects off the delving army when the delve ends, however it ends.
--- @param delve table The delve record.
function M.end_delve_effects(delve)
    M.end_battle_effects(delve)
    if not delve.hellforge then return end
    delve.hellforge = nil
    log("tower: removing the Hellforge pact")
    local force = tower_army.delving_force(delve.general_cqi)
    if force then cm:remove_effect_bundle_from_force(find("hellforge_pact").effect_bundle, force:command_queue_index()) end
end

return M
