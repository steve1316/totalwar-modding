--- Tower offers: draws the roguelite offers onto each go-deeper dilemma, builds their choices and applies the one the player takes. The
--- offer records live in configs/tower_offers.lua. This file holds when each offer can be drawn and what it does.

require("script/land_encounters/utils/random")

local offers_data = require("script/land_encounters/configs/tower_offers")
local tower_data = require("script/land_encounters/configs/tower_data")
local tower_army = require("script/land_encounters/features/tower_army")
local item_pool = require("script/land_encounters/core/item_pool")
local debug_config = require("script/land_encounters/configs/debug")
local tower_champions = require("script/land_encounters/configs/tower_champions")
local offer_effects = require("script/land_encounters/core/offer_effects")
local realm_effects = require("script/land_encounters/core/realm_effects")
local Army = require("script/land_encounters/core/army")
local army_spells = require("script/land_encounters/core/army_spells")
local battle_modifiers = require("script/land_encounters/features/battle_modifiers")
local tower_lords = require("script/land_encounters/features/tower_lords")
local tower_missions = require("script/land_encounters/features/tower_missions")
local steps = require("script/land_encounters/utils/steps")
local spot_config = require("script/land_encounters/configs/spot_offers")
local boons = require("script/land_encounters/features/boons")

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Constants

--- Prefix of every offer's choice key. The rest is the offer's key in capitals.
--- Payload line telling the player a stay offer brings them back to the same choice.
local RETURNS_HERE_LINE = "dummy_land_enc_tower_returns_here"
--- Script context value shown at the top of every per-floor go-deeper description through `ScriptObjectContext`.
local RESULT_CONTEXT_KEY = "land_enc_tower_result"
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
--- svr key the floor battle's script reads Night terrors' target unit keys from. Mirrored in script/battle/mod/land_enc_tower_buffs.lua.
local NIGHT_TERRORS_SVR_KEY = "land_enc_tower_night_terrors"

local M = {
    --- Choice key of Leave on the per-floor go-deeper dilemmas.
    LEAVE = offers_data.leave_choice_key,
    --- Battle script hand-over keys and the bundle prefix, shared with the battle spot offers.
    BUNDLE_PREFIX = BUNDLE_PREFIX,
    BATTLE_BUFFS_SVR_KEY = BATTLE_BUFFS_SVR_KEY,
    NIGHT_TERRORS_SVR_KEY = NIGHT_TERRORS_SVR_KEY,
}

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Helpers

--- Rounds gold to the tower's gold step.
local round_gold = tower_data.round_gold

--- Writes gold with thousands separators, e.g. 3000 as "3,000".
local gold_text = tower_data.gold_text

--- True when the haul holds enough gold for a gold offer to change it.
--- @param ctx table The offer context.
--- @returns boolean True with at least two gold steps in the haul.
local function has_gold(ctx)
    return ctx.delve.haul.gold >= 2 * tower_data.gold_step
end

--- Finds an offer record by its key, as configured. Use `at` for the numbers a delve pays and gets.
--- @param key string The offer key, e.g. "war_rites".
--- @returns table|nil The offer record.
local function find(key)
    return offers_data.by_key[key]
end

--- The difficulty the next floor is fought at, a champion floor counting as Hard. `M.draw` keeps it on the delve as `offer_difficulty`, so
--- its offers are priced and sized at it and a reopened dilemma shows and charges the same.
--- @param delve table The delve record.
--- @returns string "easy", "medium" or "hard".
local function next_floor_difficulty(delve)
    if delve.next_floor and delve.next_floor.champion then return "hard" end
    local _, difficulty = tower_data.floor_difficulty(delve.next_floor, delve.floor + 1, debug_config)
    return difficulty
end
M.next_floor_difficulty = next_floor_difficulty

--- The difficulty a delve's offers were drawn at, Easy for a delve saved before offers had steps.
--- @param delve table The delve record.
--- @returns string "easy", "medium" or "hard".
local function offer_difficulty(delve)
    return delve.offer_difficulty or "easy"
end

--- An offer at the delve's offer difficulty.
--- @param key string The offer key.
--- @param delve table The delve record.
--- @returns table|nil The offer record for that difficulty.
local function at(key, delve)
    return offers_data.at(key, offer_difficulty(delve))
end

--- True when the delving army has lost any strength. Kept on the context, since the army does not change while offers are drawn.
--- @param ctx table The offer context: { delve, faction_name, dividends }.
--- @returns boolean True when the army is below full strength.
local function army_damaged(ctx)
    if ctx.damaged == nil then
        ctx.damaged = offer_effects.army_damaged(ctx.delve.general_cqi)
    end
    return ctx.damaged
end

--- Heals the army by the offer's `heal_share`.
--- @param offer table The offer record.
--- @param ctx table The offer context.
local function heal(offer, ctx)
    tower_army.heal_army(ctx.delve.general_cqi, offer.heal_share)
end

--- Adds changes to the next floor on the delve. Budget and gold multipliers stack, `sabotage` offer keys add up in the order taken, and any
--- other field replaces what was there: `record` (a floor record fought instead), `faction` (the army's faction), `rarity_shift`,
--- `double_or_nothing` (the loss limit), `bonus` (a hidden floor), `scouted` (the army's units, built ahead) and `ally` (an allied army joins).
--- Any other change makes a scouting report stale.
--- @param delve table The delve record.
--- @param changes table The changes: { budget, gold, sabotage, record, faction, rarity_shift, double_or_nothing, bonus, scouted, ally }.
local function change_next_floor(delve, changes)
    local next_floor = delve.next_floor or {}
    if next_floor.scouted and changes.scouted == nil then
        next_floor.scouted = nil
        log("tower: the next floor changed, so the scouting report is stale")
    end
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

--- Puts a bundle on the delving army for the next floor's battle only. `M.end_battle_effects` takes it off when that floor resolves.
--- @param delve table The delve record.
--- @param bundle string The effect bundle key.
local function add_battle_bundle(delve, bundle)
    if not tower_army.apply_bundle(delve.general_cqi, bundle) then return end
    delve.battle_bundles = delve.battle_bundles or {}
    delve.battle_bundles[#delve.battle_bundles + 1] = bundle
end

--- Applies a battle buff: its bundle, or with `per_floor` this floor's version of it.
--- @param offer table The offer record at the delve's offer difficulty.
--- @param ctx table The offer context.
local function battle_buff(offer, ctx)
    add_battle_bundle(ctx.delve, offer.effect_bundle .. (offer.per_floor and "_" .. ctx.delve.floor or ""))
end

--- Applies an in-battle trick: the battle script does it in the next floor's battle, see `M.hand_buffs_to_battle`. Its name carries the
--- difficulty when its effect differs by it (`steps.notice`).
--- @param offer table The offer record at the delve's offer difficulty.
--- @param ctx table The offer context.
local function battle_trick(offer, ctx)
    ctx.delve.battle_tricks = ctx.delve.battle_tricks or {}
    ctx.delve.battle_tricks[#ctx.delve.battle_tricks + 1] = steps.notice(offer.notice or offer.key, find(offer.key), offer_difficulty(ctx.delve))
    log("tower: " .. offer.key .. " will act in the next battle")
end

--- Applies an Allies in the dark offer: an allied army of the offer's `ally_units` joins the next floor's battle.
--- @param offer table The offer record.
--- @param ctx table The offer context.
local function allies(offer, ctx)
    change_next_floor(ctx.delve, { ally = offer.ally_units, ally_theme = ctx.delve.ally_theme })
    battle_trick(offer, ctx)
end

--- Applies a sabotage offer: the next floor's army is built and marked with it, see `M.sabotage_options`, and its budget multiplied by any
--- `next_budget`. It is kept under its notice name, which carries the difficulty when its effect differs by it.
--- @param offer table The offer record at the delve's offer difficulty.
--- @param ctx table The offer context.
local function sabotage(offer, ctx)
    change_next_floor(ctx.delve, { sabotage = steps.notice(offer.key, find(offer.key), offer_difficulty(ctx.delve)), budget = offer.next_budget })
end

--- An offer's gold cost from the haul: its fixed `cost`, or its `cost_share` of the haul's gold.
--- @param offer table The offer record.
--- @param delve table The delve record.
--- @returns number The cost, 0 for a free offer.
local function offer_cost(offer, delve)
    local share = offer.cost_share_by_floor and offer.cost_share_by_floor[delve.floor] or offer.cost_share
    if share then return round_gold(delve.haul.gold * share) end
    return offer.cost or 0
end

--- True when an offer on the current dilemma was already taken there, so its slot only says so. A repeatable offer is never used up.
--- @param offer table The offer record.
--- @param delve table The delve record.
--- @returns boolean True when the offer is used up.
local function spent(offer, delve)
    return delve.taken[offer.key] and not offer.repeatable
end

--- What an offer's climb line says about the floor it climbs to: its `climb_difficulty` ("lower" is one step below that floor's own), or nil
--- for the floor's own difficulty.
--- @param offer table The offer record.
--- @param floor number The floor the offer climbs to.
--- @returns string|nil "easy", "medium", "hard" or "champion", or nil.
local function climb_difficulty(offer, floor)
    if offer.climb_difficulty ~= "lower" then return offer.climb_difficulty end
    for i, difficulty in ipairs(DIFFICULTY_KEYS) do
        if difficulty == tower_data.floors[floor].difficulty then return DIFFICULTY_KEYS[math.max(1, i - 1)] end
    end
    return nil
end

--- Skips floors past the next one, marking each as skipped in the climb list.
--- @param delve table The delve record.
--- @param count number How many floors to skip.
local function skip_floors(delve, count)
    if delve.next_floor and delve.next_floor.scouted then
        delve.next_floor.scouted = nil
        log("tower: the scouted floor is skipped, so the scouting report is stale")
    end
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
    local shorthand = nil
    if offer.from_tower then
        shorthand = ctx.tower and ctx.tower.faction
    else
        shorthand = offer_effects.culture_shorthand(ctx.faction_name)
    end
    return hold_units(offer, ctx, offer_effects.pick_recruits(ctx.delve.general_cqi, shorthand, offer))
end

--- Draw condition of Regiment of renown: room in the army, and a Regiment of Renown of the delving faction's culture that it does not field.
--- @param ctx table The offer context.
--- @param offer table The offer record.
--- @returns boolean True when one was picked.
local function regiment_of_renown(ctx, offer)
    return hold_units(offer, ctx, offer_effects.pick_renown(ctx.delve.general_cqi, ctx.faction_name, offer.count))
end

--- Puts a faction offer's bundle on the delving faction.
--- @param offer table The offer record: `effect_bundle` and `turns`.
--- @param ctx table The offer context.
--- @returns string The result outcome, the offer's key.
local function faction_bundle(offer, ctx)
    offer_effects.faction_bundle(ctx.faction_name, offer.effect_bundle, offer.turns)
    return offer.key
end

--- What a pact or another offer granting a boon or curse does: it is drawn while boons and curses are on, and gives the delving lord what it
--- grants.
local GRANT_HANDLER = {
    eligible = function() return boons.enabled() end,
    apply = function(offer, ctx) boons.grant_fields(tower_army.character(ctx.delve.general_cqi), offer) end,
}

--- The nearest faction of the tower's race, which a composed offer's `relations` changes relations with. Looked up once per offer context,
--- since it walks every region on the map.
--- @param ctx table The offer context.
--- @returns string|nil The faction key, or nil when none is near.
local function tower_kin(ctx)
    if ctx.kin == nil then
        local faction = ctx.tower and ctx.tower.coordinates and cm:get_faction(ctx.faction_name)
        local found = faction and realm_effects.nearest_factions(faction, ctx.tower.coordinates[1], ctx.tower.coordinates[2], 1, function(other)
            return Army.faction_shorthand_for_subculture(other:subculture()) == ctx.tower.faction
        end) or {}
        ctx.kin = found[1] and found[1]:name() or false
    end
    return ctx.kin or nil
end

--- Applies a composed offer's parts in order: a next-battle `effect_bundle` (kept for `battle_floors` floors), `bleed` (strength points every
--- unit loses now), `next_budget`, the `boon` or `curse` it grants, `wound_turns` (our lord is wounded for that many turns when the delve
--- ends), `faction_bundle` and `army_bundle` for `turns`, `lord_xp`, `haul_item` (an item of that rarity into the haul), `relations`
--- (with the nearest faction of the tower's race, in steps of 10) and `sabotage` (the next floor's army carries its notice and `enemy_bundle`). A
--- stay offer reports its result: the faction its relations changed with, or the item it put in the haul.
--- @param offer table The offer record at the delve's offer difficulty.
--- @param ctx table The offer context.
--- @returns string|nil, table|nil The result outcome (the offer's key) and its line's values, for a stay offer.
local function compose(offer, ctx)
    local delve = ctx.delve
    local values = {}
    if offer.spell_pool then add_battle_bundle(delve, army_spells.bundle((delve.offer_spells or {})[offer.key])) end
    if offer.effect_bundle then
        battle_buff(offer, ctx)
        if offer.battle_floors then
            delve.lasting_bundles = delve.lasting_bundles or {}
            delve.lasting_bundles[offer.effect_bundle] = offer.battle_floors - 1
        end
    end
    if offer.bleed then
        tower_army.bleed_army(delve.general_cqi, offer.bleed)
        log("tower: " .. offer.key .. " costs every unit " .. offer.bleed .. " strength")
    end
    if offer.sabotage then
        sabotage(offer, ctx)
    elseif offer.next_budget then
        change_next_floor(delve, { budget = offer.next_budget })
    end
    if boons.grants(offer) then GRANT_HANDLER.apply(offer, ctx) end
    if offer.wound_turns then delve.dark_bargain = math.max(delve.dark_bargain or 0, offer.wound_turns) end
    if offer.faction_bundle then offer_effects.faction_bundle(ctx.faction_name, offer.faction_bundle, offer.turns) end
    if offer.army_bundle then tower_army.apply_bundle(delve.general_cqi, offer.army_bundle, offer.turns) end
    if offer.lord_xp then offer_effects.add_lord_xp(delve.general_cqi, offer.lord_xp) end
    if offer.haul_item then
        local items = item_pool.pick_items(ctx.faction_name, { offer.haul_item }, 1)
        tower_data.add_items(delve.haul, items)
        log("tower: " .. offer.key .. " puts " .. (items[1] or "no item") .. " in the haul")
        local name = items[1] and common.get_localised_string("ancillaries_onscreen_name_" .. items[1]) or ""
        values[#values + 1] = name ~= "" and name or (items[1] or "nothing")
    end
    local kin = offer.relations and tower_kin(ctx)
    if kin then
        realm_effects.change_relations(ctx.faction_name, kin, offer.relations)
        local name = common.get_localised_string("factions_screen_name_" .. kin)
        values[#values + 1] = name ~= "" and name or kin
    end
    if offer.stay then return offer.key, values end
end

--- What a composed offer does: drawn while what it grants can be given, applied by `compose`.
local COMPOSED_HANDLER = {
    eligible = function(ctx, offer)
        if boons.grants(offer) and not boons.enabled() then return false end
        if offer.no_champion and ctx.delve.next_floor and ctx.delve.next_floor.champion then return false end
        if offer.relations and not tower_kin(ctx) then return false end
        if offer.spell_pool then
            ctx.delve.offer_spells = ctx.delve.offer_spells or {}
            ctx.delve.offer_spells[offer.key] = army_spells.roll(offer.spell_pool)
        end
        return offer.count == nil or recruit(ctx, offer)
    end,
    apply = compose,
}

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
            if healthiest then tower_army.set_strength(healthiest.unit, healthiest.strength * (1 - offer.penalty_share)) end
        end,
    },
    blood_transfusion = {
        eligible = army_damaged,
        apply = function(offer, ctx)
            heal(offer, ctx)
            tower_army.apply_bundle(ctx.delve.general_cqi, offer.effect_bundle, offer.turns)
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
        eligible = function(ctx, offer)
            for _, entry in ipairs(tower_army.unit_strengths(ctx.delve.general_cqi)) do
                if entry.strength < offer.below then return true end
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
    fire_kissed_blades = { apply = battle_buff },
    enchanted_steel = { apply = battle_buff },
    iron_resolve = { apply = battle_buff },
    scaling_blessing = { eligible = has_gold, apply = battle_buff },
    loaded_dice = {
        eligible = has_gold,
        apply = function(_, ctx)
            local haul = ctx.delve.haul
            local won = random_number(2) == 1
            haul.gold = won and haul.gold * 2 or round_gold(haul.gold / 2)
            return won and "loaded_dice_won" or "loaded_dice_lost", { gold_text(haul.gold) }
        end,
    },
    send_a_runner = {
        eligible = has_gold,
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
            tower_data.add_items(ctx.delve.haul, { item })
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
    strip_monsters = { apply = sabotage },
    strip_cavalry = { apply = sabotage },
    strip_missile = { apply = sabotage },
    strip_artillery = { apply = sabotage },
    lower_tiers_only = { apply = sabotage },
    break_their_spirit = { apply = sabotage },
    curse_their_blades = { apply = sabotage },
    cripple_their_champion = { apply = sabotage },
    spike_the_guns = { apply = sabotage },
    lame_their_mounts = { apply = sabotage },
    hunters_snares = { apply = sabotage },
    bait_and_switch = { apply = sabotage },
    last_ditch_oath = { apply = battle_buff },
    assassinate = { eligible = function(ctx) return not (ctx.delve.next_floor and ctx.delve.next_floor.champion) end, apply = sabotage },
    turn_a_traitor = { eligible = recruit, apply = sabotage },
    freed_prisoner = {
        eligible = function(ctx) return offer_effects.has_room(ctx.delve.general_cqi, 1) end,
        apply = function(offer, ctx)
            tower_lords.free_hero(ctx.delve.general_cqi, ctx.faction_name, { ctx.tower and ctx.tower.faction, offer_effects.culture_shorthand(ctx.faction_name) }, offer.rank)
        end,
    },
    dark_bargain = {
        apply = function(offer, ctx)
            offer_effects.dark_bargain(ctx.delve.general_cqi, offer)
            ctx.delve.dark_bargain = offer.wound_turns
        end,
    },
    epithet = {
        eligible = function(ctx, offer) return not tower_lords.has_trait(ctx.delve.general_cqi, offer.trait) end,
        apply = function(_, ctx) ctx.delve.epithet = true end,
    },
    scout_the_floor = {
        apply = function(_, ctx)
            local rows = ctx.scout and ctx.scout() or {}
            change_next_floor(ctx.delve, { scouted = rows })
            local names = {}
            for _, row in ipairs(rows) do
                local name = common.get_localised_string("land_units_onscreen_name_" .. row.id)
                names[#names + 1] = (row.count or 1) .. "x " .. (name ~= "" and name or row.id)
            end
            log("tower: scouted the next floor: " .. table.concat(names, ", "))
            return "scout_the_floor", { table.concat(names, ", ") }
        end,
    },
    camp_in_the_tower = {
        apply = function(offer, ctx)
            ctx.delve.camping = true
            tower_army.apply_bundle(ctx.delve.general_cqi, offer.effect_bundle)
            local general = tower_army.character(ctx.delve.general_cqi)
            if general then cm:disable_movement_for_character(cm:char_lookup_str(general)) end
            log("tower: the army camps in the tower until next turn")
        end,
    },
    allies_in_the_dark_small = { apply = allies },
    allies_in_the_dark_medium = { apply = allies },
    allies_in_the_dark_large = { apply = allies },
    rival_delvers = {
        apply = function(offer, ctx)
            change_next_floor(ctx.delve, { ally = true })
            ctx.delve.rival = true
            battle_trick(offer, ctx)
        end,
    },
    guard_the_standard = { eligible = function(ctx) return tower_missions.has_standard(ctx.delve) end },
    tower_artillery = { apply = battle_buff },
    call_the_winds = { apply = battle_buff },
    vortex_scroll = {
        apply = function(offer, ctx)
            add_battle_bundle(ctx.delve, offer.effect_bundles[random_number(#offer.effect_bundles)])
        end,
    },
    bottomless_quivers = { apply = battle_trick },
    oath_of_no_retreat = { apply = battle_trick },
    divine_shield = { apply = battle_trick },
    sacred_ground = { apply = battle_trick },
    night_terrors = { apply = battle_trick },
    regiment_of_renown = { eligible = regiment_of_renown },
    veterans_oath = {
        eligible = function(ctx, offer) return #tower_army.rankable_units(ctx.delve.general_cqi, offer.ranks, offer.max_rank) >= offer.count end,
        apply = function(offer, ctx) offer_effects.add_ranks(ctx.delve.general_cqi, offer) end,
    },
    swap_the_chaff = {
        eligible = function(ctx) return #(ctx.delve.floor_units or {}) > 0 and tower_army.weakest_regular_unit(ctx.delve.general_cqi) ~= nil end,
        apply = function(_, ctx)
            local captives = ctx.delve.floor_units
            offer_effects.remove_unit(ctx.delve.general_cqi, tower_army.weakest_regular_unit(ctx.delve.general_cqi))
            local captive = table.remove(captives, random_number(#captives))
            log("tower: granting captive " .. captive)
            cm:grant_unit_to_character(cm:char_lookup_str(cm:get_character_by_cqi(ctx.delve.general_cqi)), captive)
        end,
    },
    blood_price = {
        eligible = function(ctx) return army_damaged(ctx) and #tower_army.regular_units(ctx.delve.general_cqi) >= 2 end,
        apply = function(offer, ctx) offer_effects.blood_price(ctx.delve.general_cqi, offer.heal_share) end,
    },
    lessons_in_blood = {
        apply = function(offer, ctx)
            offer_effects.add_lord_xp(ctx.delve.general_cqi, offer.lord_xp)
        end,
    },
    research_scrolls = { apply = faction_bundle },
    --- The unit offers' payloads add their units, so taking them only needs the gold paid.
    ransom_a_captive = {
        eligible = function(ctx, offer)
            local captives = ctx.delve.floor_units or {}
            return offer_effects.has_room(ctx.delve.general_cqi, offer.count) and #captives > 0 and hold_units(offer, ctx, { captives[random_number(#captives)] })
        end,
    },
    elite_recruit = { eligible = recruit },
    conscripts = { eligible = recruit },
    captured_war_machine = { eligible = recruit },
    tower_dividends = {
        apply = function(offer, ctx)
            ctx.dividends[#ctx.dividends + 1] = { faction = ctx.faction_name, amount = offer.per_turn, turns = offer.turns }
            cm:apply_effect_bundle(spot_config.dividends_bundle_prefix .. offer.per_turn, ctx.faction_name, offer.turns)
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
        eligible = function(ctx, offer) return offer_effects.treasury(ctx.faction_name) >= offer.min_treasury end,
        apply = function(offer, ctx)
            local paid = round_gold(offer_effects.treasury(ctx.faction_name) * offer.share)
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
            if tower_army.apply_bundle(ctx.delve.general_cqi, offer.effect_bundle) then ctx.delve.hellforge = true end
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
                add_battle_bundle(ctx.delve, at("war_rites", ctx.delve).effect_bundle)
                return "roll_the_bones_rites"
            elseif roll == 2 then
                ctx.delve.haul.gold = ctx.delve.haul.gold + offer.gold
                return "roll_the_bones_gold", { gold_text(offer.gold) }
            elseif roll == 3 then
                change_next_floor(ctx.delve, { budget = offer.next_budget })
                return "roll_the_bones_foe"
            end
            tower_army.bleed_army(ctx.delve.general_cqi, offer.bleed)
            return "roll_the_bones_bleed", { offer.bleed }
        end,
    },
    tempt_fate = {
        eligible = next_is_not_master,
        apply = function(offer, ctx)
            local delve = ctx.delve
            local skipped = tower_data.floors[delve.floor + 1]
            delve.haul.gold = delve.haul.gold + tower_data.floor_gold(skipped.gold, offer.reward_share)
            for _, item in ipairs(item_pool.pick_items(ctx.faction_name, skipped.item_rarities, math.floor(skipped.item_count * offer.reward_share))) do
                tower_data.add_items(delve.haul, { item })
            end
            skip_floors(delve, offer.skips)
            local after = copy_floor(tower_data.floors[delve.floor + 1])
            after.difficulty = DIFFICULTY_KEYS[#DIFFICULTY_KEYS]
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
        --- Drawn only on the MCT `tower_hidden_floor_chance` roll.
        eligible = function() return random_chance(get_mct_settings().tower_hidden_floor_chance) end,
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
            return next_floor ~= nil and next_floor.difficulty ~= DIFFICULTY_KEYS[1]
        end,
        apply = function(offer, ctx)
            local record = copy_floor(tower_data.floors[ctx.delve.floor + 1])
            for i, difficulty in ipairs(DIFFICULTY_KEYS) do
                if difficulty == record.difficulty then record.difficulty = DIFFICULTY_KEYS[math.max(1, i - 1)] break end
            end
            record.gold = record.gold * offer.reward_share
            if record.item_count then record.item_count = math.floor(record.item_count * offer.reward_share) end
            if record.legendary_count then record.legendary_count = math.floor(record.legendary_count * offer.reward_share) end
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
            tower_army.apply_bundle(ctx.delve.general_cqi, offer.effect_bundle, offer.turns)
        end,
    },
    mirror_curse = { apply = function(offer, ctx) change_next_floor(ctx.delve, { mirror = true, sabotage = offer.key }) end },
    daemons_deal = {
        --- The unique items are picked when the offer is considered, so it only shows when enough qualify.
        eligible = function(ctx, offer)
            ctx.delve.deal_items = offer_effects.pick_unique_items(ctx.faction_name, offer.items)
            return #ctx.delve.deal_items == offer.items
        end,
        apply = function(offer, ctx)
            tower_data.add_items(ctx.delve.haul, ctx.delve.deal_items or {})
            ctx.delve.daemons_deal = offer.armies
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

--- True when an offer can be drawn: not already taken this delve (unless repeatable), it fits the army (`offer_effects.army_fits`), and its
--- condition holds.
--- @param offer table The offer record at the delve's offer difficulty.
--- @param ctx table The offer context.
--- @returns boolean True when the offer can be drawn.
--- The handler of an offer: its own, the composed one, the shared one of an offer granting a boon or curse, or nil.
--- @param offer table The offer record.
--- @returns table|nil The handler.
local function handler_of(offer)
    return HANDLERS[offer.key] or (offer.compose and COMPOSED_HANDLER) or (boons.grants(offer) and GRANT_HANDLER or nil)
end

local function eligible(offer, ctx)
    if spent(offer, ctx.delve) then return false end
    if ctx.keeps_out[offer.key] then return false end
    if not offer_effects.army_fits(offer, ctx.tower and ctx.tower.faction, ctx.delve.general_cqi) then return false end
    local handler = handler_of(offer)
    return not (handler and handler.eligible) or handler.eligible(ctx, offer)
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Offers


--- Builds an offer's choice key.
--- @param offer table The offer record.
--- @returns string The choice key, e.g. "LEAPOI_TWR_WAR_RITES".
function M.choice_key(offer)
    return offers_data.choice_key_prefix .. offer.key:upper()
end

--- Draws up to the MCT `tower_offers_per_floor` eligible offers with `random_number`, so every multiplayer client draws the same ones. Eligible offers in
--- the debug `force_offers` list (configs/debug.lua) are drawn first. The offers are priced and sized at the next floor's difficulty, which
--- the delve keeps until the next draw.
--- @param delve table The delve record.
--- @param faction_name string The delving faction.
--- @param tower TowerState|nil The delve's tower. Offers about the tower itself are not drawn without it.
--- @returns table Offer keys in popup order.
function M.draw(delve, faction_name, tower)
    local ctx = { delve = delve, faction_name = faction_name, tower = tower, keeps_out = battle_modifiers.keeps_out(delve.modifiers) }
    delve.offer_difficulty = next_floor_difficulty(delve)
    local pool = {}
    local groups = {}
    for _, record in ipairs(offers_data.offers) do
        local offer = steps.resolve(record, delve.offer_difficulty)
        if eligible(offer, ctx) then
            if offer.group then
                groups[offer.group] = groups[offer.group] or {}
                table.insert(groups[offer.group], offer.key)
            else
                pool[#pool + 1] = offer.key
            end
        end
    end
    --- Offers that share a `group` (the sizes of Allies in the dark) go in as one, picked at random. Groups are walked in a fixed order.
    local group_names = {}
    for name in pairs(groups) do group_names[#group_names + 1] = name end
    table.sort(group_names)
    for _, name in ipairs(group_names) do pool[#pool + 1] = groups[name][random_number(#groups[name])] end
    local limit = get_mct_settings().tower_offers_per_floor
    local picked, count = {}, 0
    for _, key in ipairs(debug_config.force_offers) do
        for i, pooled in ipairs(pool) do
            if pooled == key and count < limit then
                picked[table.remove(pool, i)] = true
                count = count + 1
                break
            end
        end
    end
    for _ = 1, math.min(limit - count, #pool) do
        picked[table.remove(pool, random_number(#pool))] = true
    end
    local keys = {}
    for _, offer in ipairs(offers_data.offers) do
        if picked[offer.key] then keys[#keys + 1] = offer.key end
    end
    log("tower: drew for " .. faction_name .. " on floor " .. delve.floor .. " at " .. delve.offer_difficulty .. ": " .. table.concat(keys, ", ") .. " ("
        .. #keys + #pool .. " eligible, " .. count .. " forced)")
    --- Allies in the dark names the theme its allied army marches as, so it is rolled once the offer is drawn.
    delve.ally_theme = nil
    for _, key in ipairs(keys) do
        if offers_data.by_key[key].ally_units then
            delve.ally_theme = battle_modifiers.roll_ally_theme(cm:get_faction(faction_name):subculture(), tower and tower.faction)
            break
        end
    end
    return keys
end

--- Writes a delve's next-floor changes for the log, e.g. "{budget=1.2, gold=2}".
--- @param next_floor table|nil The delve's next-floor changes.
--- @returns string The changes in key order, "{}" for none.
function M.describe_next_floor(next_floor)
    local keys = sorted_keys(next_floor or {})
    local parts = {}
    for _, key in ipairs(keys) do
        local value = next_floor[key]
        if key == "record" then
            value = value.difficulty .. " floor"
        elseif key == "scouted" then
            value = #value .. " unit rows"
        elseif type(value) == "table" then
            value = table.concat(value, "+")
        end
        parts[#parts + 1] = key .. "=" .. tostring(value)
    end
    return "{" .. table.concat(parts, ", ") .. "}"
end

--- Builds an offer's go-deeper choice: its line (or its not-enough-gold line when the haul cannot pay), then where it leads. A skip leads
--- past the next floor, and a bonus floor's own line already says where it leads. A stay offer taken on this floor says so and is greyed out.
--- A unit offer the haul can pay for shows its units as cards, and its payload adds them to the army.
--- @param offer_key string The offer key.
--- @param delve table The delve record.
--- @param next_floor number The floor a climbing offer leads to.
--- @returns table A choice record for `launch_dilemma`.
function M.choice(offer_key, delve, next_floor)
    local offer = at(offer_key, delve)
    if spent(offer, delve) then return { key = M.choice_key(offer), lines = { TAKEN_LINE }, closed = true } end
    local affordable = delve.haul.gold >= offer_cost(offer, delve)
    local line = battle_modifiers.ally_line(offers_data.line(offer.key, offer_difficulty(delve), delve.floor), offer.ally_units and delve.ally_theme)
    local lines = { line .. (affordable and "" or offers_data.unaffordable_suffix) }
    if offer.stay then
        lines[2] = RETURNS_HERE_LINE
    elseif not offer.bonus_floor then
        local floor = next_floor + (offer.skips or 0)
        local difficulty = climb_difficulty(offer, floor)
        lines[2] = "dummy_land_enc_tower_descend_floor_" .. floor .. (difficulty and "_" .. difficulty or "")
    end
    local spell = offer.spell_pool and (delve.offer_spells or {})[offer.key]
    if spell then table.insert(lines, 2, army_spells.line(spell)) end
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
--- @param extras table { dividends = the tower delegate's dividend list, tower = the delve's TowerState, scout = builds the next floor's army and
--- returns its unit rows }.
--- @returns table|nil The offer record, or nil when the choice is not an offer on the dilemma.
--- @returns string|nil The offer's result line for the reopened dilemma, or nil when it has none.
function M.take(choice_key, delve, faction_name, extras)
    extras = extras or {}
    local offer = nil
    for _, key in ipairs(delve.offers or {}) do
        if M.choice_key({ key = key }) == choice_key then
            offer = at(key, delve)
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
    offer_effects.log_army_change(delve.general_cqi, offer.key)
    delve.haul.gold = delve.haul.gold - cost
    delve.taken[offer.key] = true
    local handler = handler_of(offer)
    local outcome, values = nil, nil
    if offer.mission then tower_missions.take(offer, delve) end
    if handler and handler.apply then
        outcome, values = handler.apply(offer, { delve = delve, faction_name = faction_name, dividends = extras.dividends, tower = extras.tower,
            scout = extras.scout })
    end
    --- A stay mission lists itself on the reopened dilemma.
    if offer.mission and offer.stay and not outcome then outcome = "mission_set_" .. offer.key end
    log("tower: " .. offer.key .. " done: haul " .. gold_before .. " -> " .. delve.haul.gold .. " gold, " .. items_before .. " -> " .. #delve.haul.items
        .. " items, next floor " .. M.describe_next_floor(delve.next_floor) .. ", outcome " .. (outcome or "none"))
    if not outcome then return offer end
    values = values or {}
    return offer, tower_missions.result_line(outcome, values[1], values[2])
end

--- Sets a script context value both under its key and under the floor's own key, which that floor's dilemma reads. An older floor's event
--- then still shows that floor rather than the latest one.
--- @param key string The context key.
--- @param floor number The floor the value belongs to.
--- @param value string The value.
local function set_floor_context(key, floor, value)
    common.set_context_value(key, value)
    common.set_context_value(key .. "_floor_" .. floor, value)
end

--- Shows the next floor's battle modifiers, then the floor's results, at the top of its go-deeper description, one line each in the order they
--- came, with a blank line after each block. Empty when there are neither.
--- @param delve table The delve record. `delve.results` holds this floor's result lines and `delve.modifiers` the next floor's modifiers.
function M.show_results(delve)
    local results = delve.results
    set_floor_context(RESULT_CONTEXT_KEY, delve.floor, text_block(battle_modifiers.lines(delve.modifiers)) .. text_block(results))
end

--- Shows the climb list in the per-floor go-deeper descriptions: each floor so far as cleared or skipped at the difficulty it had, any hidden
--- floor where it was fought, then the next floor and the ones ahead.
--- @param delve table The delve record. `delve.climb` holds the floors so far, in order.
function M.show_climb(delve)
    local lines = {}
    for _, entry in ipairs(delve.climb) do
        lines[#lines + 1] = string.format(climb_text(entry.state), floor_name(entry.floor, entry.difficulty, entry.bonus))
    end
    for floor = delve.floor + 1, #tower_data.floors do
        lines[#lines + 1] = string.format(climb_text(floor == delve.floor + 1 and "next" or "ahead"), floor_name(floor, tower_data.floors[floor].difficulty))
    end
    set_floor_context(CLIMB_CONTEXT_KEY, delve.floor, table.concat(lines, "\n"))
end

--- Turns the sabotage taken for the next floor into what its army needs: generator options (`no_heroes`, `fewer_units`, `max_tier`, `min_tier`,
--- `strip_types`)
--- and what is put on it once it spawns (`enemy_strength`, `champion_strength` and `enemy_bundles`), see `offer_effects.merge_sabotage`.
--- @param next_floor table|nil The delve's next-floor changes.
--- @returns table The options, with `enemy_bundles` nil when no bundle was taken.
function M.sabotage_options(next_floor)
    local options = {}
    for _, name in ipairs(next_floor and next_floor.sabotage or {}) do
        local key, difficulty = steps.split(name)
        offer_effects.merge_sabotage(options, offers_data.at(key, difficulty or "easy"))
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
        local general = tower_army.character(general_cqi)
        if not general then
            log("tower: Last stand lost, but lord " .. general_cqi .. " is gone")
            return
        end
        tower_army.log_army(general_cqi, "Last stand falls")
        cm:kill_character_and_commanded_unit(cm:char_lookup_str(general), true)
        log("tower: Last stand lost, the army of lord " .. general_cqi .. " is destroyed")
    end, false)
end

--- Ends a camp: the army may move again.
--- @param delve table The delve record.
function M.end_camp(delve)
    delve.camping = nil
    tower_army.remove_bundle(delve.general_cqi, find("camp_in_the_tower").effect_bundle)
    local general = tower_army.character(delve.general_cqi)
    if general then cm:enable_movement_for_character(cm:char_lookup_str(general)) end
end


--- Hands the buffs on the delving army to the next battle's script, which announces them: the one-battle buffs, the Hellforge pact, Drained,
--- then the in-battle tricks, the missions, the sabotage on the enemy, then the battle modifiers. The list is comma-separated bundle names
--- without `BUNDLE_PREFIX`, then trick, mission, sabotage and modifier notice keys. Night terrors' and the missions' targets go under their own keys.
--- @param delve table The delve record.
function M.hand_buffs_to_battle(delve)
    local names, seen = {}, {}
    local bundles = {}
    for _, bundle in ipairs(delve.battle_bundles or {}) do bundles[#bundles + 1] = bundle end
    if delve.hellforge then bundles[#bundles + 1] = find("hellforge_pact").effect_bundle end
    --- Drained lasts turns, not a delve, so it is announced while the army still carries it.
    local force = tower_army.delving_force(delve.general_cqi)
    local drained = find("blood_transfusion").effect_bundle
    if force and force:has_effect_bundle(drained) then bundles[#bundles + 1] = drained end
    if delve.last_stand then bundles[#bundles + 1] = BUNDLE_PREFIX .. "last_stand" end
    for _, bundle in ipairs(bundles) do
        if not seen[bundle] then
            seen[bundle] = true
            names[#names + 1] = bundle:sub(#BUNDLE_PREFIX + 1)
        end
    end
    local targets, values = {}, {}
    for _, name in ipairs(delve.battle_tricks or {}) do
        names[#names + 1] = name
        local key, difficulty = steps.split(name)
        local trick = offers_data.at(key, difficulty or "easy")
        if trick and trick.targets then targets = tower_army.most_expensive(delve.floor_units or {}, trick.targets) end
        if trick and trick.battle_value then values[#values + 1] = key .. "=" .. trick.battle_value end
    end
    for _, key in ipairs(delve.missions or {}) do names[#names + 1] = key end
    for _, key in ipairs(delve.enemy_notices or {}) do names[#names + 1] = key end
    for _, name in ipairs(battle_modifiers.notices(delve.modifiers)) do names[#names + 1] = name end
    tower_missions.hand_to_battle(delve, values)
    log("tower: battle notices for the next floor: " .. (#names > 0 and table.concat(names, ", ") or "none"))
    if #targets > 0 then log("tower: night terrors will rout " .. table.concat(targets, ", ")) end
    core:svr_save_string(BATTLE_BUFFS_SVR_KEY, table.concat(names, ","))
    core:svr_save_string(NIGHT_TERRORS_SVR_KEY, table.concat(targets, ","))
end

--- Takes the one-battle effects off the delving army once the floor they were bought for is over, and clears the battle's buff list. A
--- bundle bought for more floors (`lasting_bundles`) stays on for its next floor, unless the delve is over.
--- @param delve table The delve record.
--- @param delve_over boolean|nil True when the delve ends, so every bundle comes off.
function M.end_battle_effects(delve, delve_over)
    core:svr_save_string(BATTLE_BUFFS_SVR_KEY, "")
    core:svr_save_string(NIGHT_TERRORS_SVR_KEY, "")
    delve.enemy_notices = nil
    delve.battle_tricks = nil
    tower_missions.end_battle(delve)
    local bundles, kept, lasting = {}, {}, delve.lasting_bundles or {}
    for _, bundle in ipairs(delve.battle_bundles or {}) do
        if not delve_over and (lasting[bundle] or 0) > 0 then
            lasting[bundle] = lasting[bundle] - 1
            kept[#kept + 1] = bundle
            log("tower: " .. bundle .. " stays on for another floor")
        else
            lasting[bundle] = nil
            bundles[#bundles + 1] = bundle
        end
    end
    for _, bundle in ipairs(delve.modifier_bundles or {}) do bundles[#bundles + 1] = bundle end
    delve.battle_bundles, delve.modifier_bundles = #kept > 0 and kept or nil, nil
    delve.lasting_bundles = next(lasting) and lasting or nil
    if #bundles > 0 then log("tower: removing one-battle bundles: " .. table.concat(bundles, ", ")) end
    for _, bundle in ipairs(bundles) do tower_army.remove_bundle(delve.general_cqi, bundle) end
end

--- Takes the delve-long effects off the delving army when the delve ends, however it ends.
--- @param delve table The delve record.
function M.end_delve_effects(delve)
    M.end_battle_effects(delve, true)
    if not delve.hellforge then return end
    delve.hellforge = nil
    log("tower: removing the Hellforge pact")
    tower_army.remove_bundle(delve.general_cqi, find("hellforge_pact").effect_bundle)
end

return M
