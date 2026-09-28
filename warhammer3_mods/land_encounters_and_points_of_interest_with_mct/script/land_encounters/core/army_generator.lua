--- Encounter army generator. Builds a force makeup (lord, heroes, units) for a faction and difficulty by spending a gold budget
--- across unit roles according to a randomly rolled archetype. Every army buys a spine first (frontline plus one ranged or support unit).

require("script/land_encounters/utils/common")
require("script/land_encounters/utils/random")
require("script/land_encounters/core/mct")

local factions_data = require("script/land_encounters/configs/factions_data")
local archetypes = require("script/land_encounters/configs/archetypes")

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Constants

--- The game's hard cap on units in one army, lord and heroes included.
local ARMY_UNIT_CAP = 20

--- Percent chance that a pick adds 2-3 copies of the unit instead of one.
local EXTRA_COPIES_CHANCE = 25

--- In "normal" price mode, units cheaper than this fraction of the target price are skipped when pricier ones are affordable.
local NORMAL_PRICE_FLOOR = 0.5

--- Percent chance that an archetype with a preferred unit type picks only from that type when it can.
local PREFERRED_UNIT_TYPE_CHANCE = 50

--- The army roles in a fixed order, so role quotas are built the same way on every multiplayer client.
local ROLES = { "frontline", "missile", "cavalry", "monsters", "artillery" }

--- Tier keys in factions_data, lowest first.
local TIER_NAMES = { "tier_0", "tier_1", "tier_2", "tier_3", "tier_4", "tier_5" }

--- Every unit-type bucket a force makeup holds.
local UNIT_TYPES = {
    "melee_infantry",
    "missile_infantry",
    "melee_cavalry",
    "missile_cavalry",
    "monstrous_infantry",
    "monstrous_cavalry",
    "war_beast",
    "chariot",
    "warmachine",
    "monster",
    "generic",
}

local M = {}

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Helpers

--- Returns true if a unit's origin pack is enabled under the user's MCT mod-compatibility settings.
--- @param origin string The origin tag on a unit ("vanilla" or a mod pack key).
--- @returns boolean True when the origin is allowed by the current MCT settings.
local function is_origin_enabled(origin)
    local settings = get_mct_settings()
    --- If "only modded units" is on, vanilla is excluded. Otherwise vanilla is always enabled.
    if settings.enable_compatibility_with_supported_mods and settings.use_only_modded_units then
        if origin == "vanilla" then
            return false
        end
    elseif origin == "vanilla" then
        return true
    end

    --- Origin must appear in the enabled-mods list.
    if settings.enable_compatibility_with_supported_mods then
        for _, mod in ipairs(settings.enabled_mods) do
            if origin == mod then
                return true
            end
        end
    end
    return false
end

--- Returns the gold price used for budgeting a unit. Units with no campaign cost (Tomb Kings, most Beastmen) use their multiplayer cost.
--- @param unit table A factions_data unit record.
--- @returns number The unit's price, or 0 when it has none.
local function unit_price(unit)
    if unit.recruitment_cost and unit.recruitment_cost > 0 then
        return unit.recruitment_cost
    end
    return unit.multiplayer_cost or 0
end

--- Builds per-role pools of the faction's buyable units across every tier. Each unit appears once, from its first enabled listing.
--- Tiers and unit types are walked in a fixed order so every multiplayer client builds identical pools.
--- @param faction_shorthand_key string A 3-letter faction shorthand.
--- @returns table A role -> array of { land_unit, unit_type, price, is_renown } map, each array sorted by price, with a `median` price field.
local function build_role_pools(faction_shorthand_key)
    local pools = { frontline = {}, missile = {}, cavalry = {}, monsters = {}, artillery = {} }
    local seen = {}
    local units_by_tier = factions_data[faction_shorthand_key].units
    for _, tier_name in ipairs(TIER_NAMES) do
        for _, unit_type in ipairs(UNIT_TYPES) do
            local role = archetypes.role_by_unit_type[unit_type]
            for _, unit in ipairs(units_by_tier[tier_name] and units_by_tier[tier_name][unit_type] or {}) do
                local price = unit_price(unit)
                if price > 0 and not seen[unit.land_unit] and is_origin_enabled(unit.origin) then
                    seen[unit.land_unit] = true
                    table.insert(pools[role], { land_unit = unit.land_unit, unit_type = unit_type, price = price, is_renown = unit.is_renown == true })
                end
            end
        end
    end
    for _, pool in pairs(pools) do
        table.sort(pool, function(a, b) return a.price < b.price or (a.price == b.price and a.land_unit < b.land_unit) end)
        pool.median = #pool > 0 and pool[math.ceil(#pool / 2)].price or 0
    end
    return pools
end

--- Picks a random archetype that is enabled in MCT and that the faction's roster can field. Falls back to the default archetype.
--- @param pools table The faction's role pools from `build_role_pools`.
--- @returns table The chosen archetype record from configs/archetypes.lua.
local function pick_archetype(pools)
    local enabled = {}
    for _, key in ipairs(get_mct_settings().enabled_archetypes) do
        enabled[key] = true
    end
    local candidates = {}
    for _, archetype in ipairs(archetypes.list) do
        if enabled[archetype.key] and (archetype.requires == nil or #pools[archetype.requires] >= archetype.requires_count) then
            table.insert(candidates, archetype)
        end
    end
    if #candidates == 0 then
        return archetypes.by_key[archetypes.fallback_archetype]
    end
    return candidates[random_number(#candidates)]
end

--- Lists the units in `pool` the army can buy right now, filtered by the archetype's price mode.
--- "normal" skips units far below the target price, and falls back to the pool's top half when the target is above every price.
--- "elite" only takes the top half, and "cheap" takes anything affordable.
--- @param pool table A role pool from `build_role_pools`.
--- @param army table The army being built (copies).
--- @param spend_limit number The most gold this pick may spend.
--- @param price_mode string "normal", "cheap" or "elite".
--- @param target_price number The gold each remaining slot should cost to spend the budget evenly.
--- @returns table An array of pool entries, empty when nothing fits.
local function buyable_units(pool, army, spend_limit, price_mode, target_price)
    local max_copies = get_mct_settings().max_unit_copies
    local affordable, above_floor, top_half = {}, {}, {}
    for _, unit in ipairs(pool) do
        local owned = army.copies[unit.land_unit] or 0
        if unit.price <= spend_limit and owned < max_copies and not (unit.is_renown and owned > 0) then
            table.insert(affordable, unit)
            if unit.price >= NORMAL_PRICE_FLOOR * target_price then table.insert(above_floor, unit) end
            if unit.price >= pool.median then table.insert(top_half, unit) end
        end
    end
    if price_mode == "cheap" then
        return affordable
    elseif price_mode == "normal" and #above_floor > 0 then
        return above_floor
    elseif #top_half > 0 then
        return top_half
    end
    return affordable
end

--- Adds `copies` of `unit` to the army and charges their price against its budget and slots.
--- @param army table The army being built. Mutated.
--- @param unit table A pool entry from `build_role_pools`.
--- @param copies number How many copies to add.
--- @returns number The gold spent.
local function add_unit(army, unit, copies)
    for _ = 1, copies do
        table.insert(army.units[unit.unit_type], unit.land_unit)
    end
    local cost = unit.price * copies
    army.copies[unit.land_unit] = (army.copies[unit.land_unit] or 0) + copies
    army.slots_left = army.slots_left - copies
    army.budget_left = army.budget_left - cost
    return cost
end

--- Buys one pick from `candidates`: one unit, or sometimes 2-3 copies of it within the copy cap, slot limit and spend limit.
--- @param army table The army being built. Mutated.
--- @param candidates table A non-empty array of pool entries.
--- @param spend_limit number The most gold this pick may spend.
--- @param max_count number The most units this pick may add.
--- @param preferred_unit_type string An optional unit type to favor when present among the candidates.
--- @returns number The gold spent.
--- @returns number The number of units added.
local function buy_from(army, candidates, spend_limit, max_count, preferred_unit_type)
    if preferred_unit_type and random_chance(PREFERRED_UNIT_TYPE_CHANCE) then
        local preferred = {}
        for _, unit in ipairs(candidates) do
            if unit.unit_type == preferred_unit_type then table.insert(preferred, unit) end
        end
        if #preferred > 0 then candidates = preferred end
    end

    local unit = candidates[random_number(#candidates)]
    local copies = 1
    if not unit.is_renown and random_chance(EXTRA_COPIES_CHANCE) then
        local room = math.min(get_mct_settings().max_unit_copies - (army.copies[unit.land_unit] or 0), max_count, math.floor(spend_limit / unit.price))
        copies = math.max(1, math.min(random_range(2, 3), room))
    end
    return add_unit(army, unit, copies), copies
end

--- Picks the lord and heroes the same way as before the budget rework: an enabled-origin lord (else a vanilla one) and a random hero count.
--- @param difficulty_key string The difficulty key.
--- @param faction_shorthand_key string A 3-letter faction shorthand.
--- @returns table The lord record.
--- @returns table An array of hero records.
local function pick_lord_and_heroes(difficulty_key, faction_shorthand_key)
    local lords = factions_data[faction_shorthand_key].allowed_lords or {}
    local heroes = factions_data[faction_shorthand_key].allowed_heroes or {}

    --- Remember the first vanilla lord seen as a fallback, since vanilla is always loaded and its lords are always valid.
    local lord, fallback_vanilla_lord = nil, nil
    for _, candidate in ipairs(randomic_shuffle(lords)) do
        if is_origin_enabled(candidate.origin) then
            lord = candidate
            break
        end
        if fallback_vanilla_lord == nil and candidate.origin == "vanilla" then
            fallback_vanilla_lord = candidate
        end
    end
    if not lord then
        out("DEBUG - A lord was not able to be selected. Selecting a random vanilla lord instead.")
        lord = fallback_vanilla_lord
    end

    local hero_range = get_mct_settings().difficulties[difficulty_key].limits.hero
    local number_of_heroes = random_range(hero_range[1], hero_range[2])
    local selected_heroes = {}
    for _, hero in ipairs(randomic_shuffle(heroes)) do
        if #selected_heroes >= number_of_heroes then
            break
        end
        if is_origin_enabled(hero.origin) then
            table.insert(selected_heroes, hero)
        end
    end
    return lord, selected_heroes
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Generation

--- Builds a force makeup for the faction and difficulty by spending a rolled gold budget on a spine and then on the archetype's roles.
--- @param difficulty_key string The difficulty key ("easy", "medium" or "hard").
--- @param faction_shorthand_key string A 3-letter faction shorthand.
--- @returns table A force_makeup with lord, heroes, units (unit_type -> array of unit keys), archetype, budget and spent fields.
function M.generate(difficulty_key, faction_shorthand_key)
    local settings = get_mct_settings()
    local budget_range = settings.difficulties[difficulty_key].budget
    local lord, heroes = pick_lord_and_heroes(difficulty_key, faction_shorthand_key)
    local pools = build_role_pools(faction_shorthand_key)
    local archetype = pick_archetype(pools)

    local army = { units = {}, copies = {}, budget_left = random_range(budget_range[1], budget_range[2]), slots_left = ARMY_UNIT_CAP - 1 - #heroes }
    for _, unit_type in ipairs(UNIT_TYPES) do
        army.units[unit_type] = {}
    end
    local budget = army.budget_left

    --- Spine: single copies of a minimum frontline, then the first ranged or support unit type the roster has.
    local spine_target_price = army.budget_left / math.max(army.slots_left, 1)
    for _ = 1, archetypes.spine_frontline_count do
        local candidates = buyable_units(pools.frontline, army, army.budget_left, archetype.price_mode, spine_target_price)
        if #candidates == 0 or army.slots_left <= 0 then break end
        add_unit(army, candidates[random_number(#candidates)], 1)
    end
    for _, unit_type in ipairs(archetypes.spine_support_unit_types) do
        local pool = pools[archetypes.role_by_unit_type[unit_type]]
        local of_type = {}
        for _, unit in ipairs(buyable_units(pool, army, army.budget_left, archetype.price_mode, spine_target_price)) do
            if unit.unit_type == unit_type then table.insert(of_type, unit) end
        end
        if #of_type > 0 and army.slots_left > 0 then
            add_unit(army, of_type[random_number(#of_type)], 1)
            break
        end
    end

    --- Split the remaining gold and slots by the archetype's shares, giving the share of any role the faction cannot field to the others.
    --- A slot quota per role stops a role full of cheap units from filling the army before the others buy anything.
    local total_share = 0
    for role, share in pairs(archetype.shares) do
        if #pools[role] > 0 then total_share = total_share + share end
    end
    local allowances = {}
    for _, role in ipairs(ROLES) do
        local share = archetype.shares[role]
        if share and #pools[role] > 0 then
            table.insert(allowances, { role = role, gold = army.budget_left * share / total_share, slots = math.floor(army.slots_left * share / total_share + 0.5) })
        end
    end
    table.sort(allowances, function(a, b) return a.gold > b.gold end)

    --- Fill each role within its gold and slot quota, biggest first.
    for _, allowance in ipairs(allowances) do
        while allowance.slots > 0 and army.slots_left > 0 do
            local spend_limit = math.min(allowance.gold, army.budget_left)
            local candidates = buyable_units(pools[allowance.role], army, spend_limit, archetype.price_mode, allowance.gold / allowance.slots)
            if #candidates == 0 then break end
            local cost, count = buy_from(army, candidates, spend_limit, math.min(allowance.slots, army.slots_left), archetype.preferred_unit_type)
            allowance.gold = allowance.gold - cost
            allowance.slots = allowance.slots - count
        end
    end

    --- Spend any leftover gold on the archetype's roles until nothing is affordable or the army is full.
    while army.slots_left > 0 do
        local target_price = army.budget_left / army.slots_left
        local candidates = {}
        for _, allowance in ipairs(allowances) do
            for _, unit in ipairs(buyable_units(pools[allowance.role], army, army.budget_left, archetype.price_mode, target_price)) do
                table.insert(candidates, unit)
            end
        end
        if #candidates == 0 then break end
        buy_from(army, candidates, army.budget_left, army.slots_left, archetype.preferred_unit_type)
    end

    local spent = budget - army.budget_left
    out("INFO - Generated a " .. archetype.key .. " army for " .. faction_shorthand_key .. " (" .. difficulty_key .. "): spent " .. spent .. " of " .. budget .. " gold on " .. (ARMY_UNIT_CAP - 1 - #heroes - army.slots_left) .. " units.")
    return { lord = lord, heroes = heroes, units = army.units, archetype = archetype.key, budget = budget, spent = spent }
end

return M
