--- Encounter army generator. Builds a force makeup (lord, heroes, units) for a faction and difficulty by spending a gold budget
--- across unit roles according to a randomly rolled archetype. Every army buys a spine first (frontline plus one ranged or support unit).

require("script/land_encounters/utils/common")
require("script/land_encounters/utils/random")
require("script/land_encounters/core/mct")

local factions_data = require("script/land_encounters/configs/factions_data")
local archetypes = require("script/land_encounters/configs/archetypes")
local ally_gold_per_unit = require("script/land_encounters/configs/shared_offers").ally_gold_per_unit

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

--- Unit key -> price over every faction's units, built on first use by `M.unit_price_by_key`.
local price_by_key = nil

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Helpers

--- Builds the set of unit origins the user's MCT mod-compatibility settings allow. Vanilla is in it unless "only modded units" is on.
--- @returns table An origin -> true set ("vanilla" or mod pack keys).
local function enabled_origins()
    local settings = get_mct_settings()
    local origins = {}
    if settings.enable_compatibility_with_supported_mods then
        for _, mod in ipairs(settings.enabled_mods) do
            origins[mod] = true
        end
    end
    origins.vanilla = not (settings.enable_compatibility_with_supported_mods and settings.use_only_modded_units) or nil
    return origins
end

--- Returns the entries of `records` whose origin passes `accept`, in their original order.
--- @param records table An array of factions_data lord or hero records.
--- @param accept function A predicate taking an origin string.
--- @returns table A new array of the matching records.
local function filter_by_origin(records, accept)
    local matches = {}
    for _, record in ipairs(records) do
        if accept(record.origin) then table.insert(matches, record) end
    end
    return matches
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

--- True when the generator can field a unit: it has a price and comes from an origin the MCT settings allow.
--- @param unit table A factions_data unit record.
--- @param origins table The allowed-origin set from `enabled_origins`.
--- @returns boolean True when it can be bought.
local function buyable(unit, origins)
    return unit_price(unit) > 0 and origins[unit.origin] ~= nil
end

--- Builds per-role pools of the faction's buyable units across the tiers from `min_tier` to `max_tier`. Each unit appears once, from its first
--- enabled listing. Tiers and unit types are walked in a fixed order so every multiplayer client builds identical pools.
--- @param faction_shorthand_key string A 3-letter faction shorthand.
--- @param origins table The allowed-origin set from `enabled_origins`.
--- @param max_tier number|nil The highest tier to take units from, or nil for every tier.
--- @param min_tier number|nil The lowest tier to take units from, or nil for every tier.
--- @returns table A role -> array of { land_unit, unit_type, price, is_renown } map, each array sorted by price, with a `median` price field.
local function build_role_pools(faction_shorthand_key, origins, max_tier, min_tier)
    local pools = { frontline = {}, missile = {}, cavalry = {}, monsters = {}, artillery = {} }
    local seen = {}
    local units_by_tier = factions_data[faction_shorthand_key].units
    for tier, tier_name in ipairs(TIER_NAMES) do
        if max_tier and tier - 1 > max_tier then break end
        local tier_units = (not min_tier or tier - 1 >= min_tier) and units_by_tier[tier_name] or {}
        for _, unit_type in ipairs(UNIT_TYPES) do
            local role = archetypes.role_by_unit_type[unit_type]
            for _, unit in ipairs(tier_units[unit_type] or {}) do
                local price = unit_price(unit)
                if price > 0 and not seen[unit.land_unit] and origins[unit.origin] then
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

--- True for a Regiment of Renown: flagged in factions_data, or named like one (some mod RoRs carry no flag).
--- @param unit table A factions_data unit record.
--- @returns boolean True for a Regiment of Renown.
local function is_renown(unit)
    return unit.is_renown == true or unit.land_unit:find("_ror") ~= nil
end

--- Picks a random archetype that is enabled in MCT and that the faction's roster can field. When `requested_keys` is given, only those
--- archetypes are considered first. If none of them qualify, any qualifying archetype is used, and then the default archetype.
--- @param pools table The faction's role pools from `build_role_pools`.
--- @param requested_keys table An optional array of archetype keys a battle category asks for.
--- @returns table The chosen archetype record from configs/archetypes.lua.
local function pick_archetype(pools, requested_keys)
    local enabled = {}
    for _, key in ipairs(get_mct_settings().enabled_archetypes) do
        enabled[key] = true
    end
    local requested = {}
    for _, key in ipairs(requested_keys or {}) do
        requested[key] = true
    end
    local candidates, requested_candidates = {}, {}
    for _, archetype in ipairs(archetypes.list) do
        if enabled[archetype.key] and (archetype.requires == nil or #pools[archetype.requires] >= archetype.requires_count) then
            table.insert(candidates, archetype)
            if requested[archetype.key] then table.insert(requested_candidates, archetype) end
        end
    end
    if #requested_candidates > 0 then
        return requested_candidates[random_number(#requested_candidates)]
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

--- Picks an enabled-origin lord (else a random vanilla one) and a random number of enabled-origin heroes. Only rolls on filtered
--- copies, so the shared lord and hero lists in factions_data keep their order.
--- @param difficulty_key string The difficulty key.
--- @param faction_shorthand_key string A 3-letter faction shorthand.
--- @param origins table The allowed-origin set from `enabled_origins`.
--- @returns table The lord record.
--- @returns table An array of hero records.
local function pick_lord_and_heroes(difficulty_key, faction_shorthand_key, origins)
    local faction = factions_data[faction_shorthand_key]
    local lords = filter_by_origin(faction.allowed_lords or {}, function(origin) return origins[origin] end)
    if #lords == 0 then
        out("DEBUG - A lord was not able to be selected. Selecting a random vanilla lord instead.")
        lords = filter_by_origin(faction.allowed_lords or {}, function(origin) return origin == "vanilla" end)
    end
    local lord = lords[random_number(#lords)]

    --- Partial Fisher-Yates: only the first `number_of_heroes` positions get shuffled into place.
    local heroes = filter_by_origin(faction.allowed_heroes or {}, function(origin) return origins[origin] end)
    local hero_range = get_mct_settings().difficulties[difficulty_key].limits.hero
    local number_of_heroes = math.min(random_range(hero_range[1], hero_range[2]), #heroes)
    local selected_heroes = {}
    for i = 1, number_of_heroes do
        local j = random_number(#heroes, i)
        heroes[i], heroes[j] = heroes[j], heroes[i]
        table.insert(selected_heroes, heroes[i])
    end
    return lord, selected_heroes
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Generation

--- Builds a force makeup for the faction and difficulty by spending a rolled gold budget on a spine and then on the archetype's roles.
--- @param difficulty_key string The difficulty key ("easy", "medium" or "hard").
--- @param faction_shorthand_key string A 3-letter faction shorthand.
--- @param options table Optional overrides: `archetype_keys` (preferred archetypes), `budget_multiplier` (scales the budget), the tower's
--- sabotage and champion (`no_heroes`, `fewer_units` taken off the unit cap, `max_tier` and `min_tier` for the unit tiers, and `lord_subtype`
--- for the lord), `unit_count` (an exact number of regular units, for a sized allied army) and `budget_range` ({min, max} gold that replaces the
--- difficulty's MCT range), and `composition` (a battle modifier's army theme, an archetype-like record with `key`, `shares` and `price_mode`,
--- which replaces the rolled archetype).
--- @returns table A force_makeup with lord, heroes, units (unit_type -> array of unit keys), archetype, budget and spent fields.
function M.generate(difficulty_key, faction_shorthand_key, options)
    options = options or {}
    local settings = get_mct_settings()
    local budget_range = options.budget_range or settings.difficulties[difficulty_key].budget
    local origins = enabled_origins()
    local lord, heroes = pick_lord_and_heroes(difficulty_key, faction_shorthand_key, origins)
    if options.no_heroes then heroes = {} end
    if options.lord_subtype then lord = { agent_subtype = options.lord_subtype, legendary = true } end
    local pools = build_role_pools(faction_shorthand_key, origins, options.max_tier, options.min_tier)
    local archetype = options.composition or pick_archetype(pools, options.archetype_keys)
    local budget_roll = math.floor(random_range(budget_range[1], budget_range[2]) * (options.budget_multiplier or 1))

    local unit_slots = options.unit_count or (ARMY_UNIT_CAP - 1 - #heroes - (options.fewer_units or 0))
    local army = { units = {}, copies = {}, budget_left = budget_roll, slots_left = unit_slots }
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
    local bought = unit_slots - army.slots_left
    out("INFO - Generated a " .. archetype.key .. " army for " .. faction_shorthand_key .. " (" .. difficulty_key .. "): spent " .. spent .. " of " .. budget .. " gold on " .. bought .. " units.")
    return { lord = lord, heroes = heroes, units = army.units, archetype = archetype.key, budget = budget, spent = spent }
end

--- True when a faction can field a buyable unit of one of the given types, at any tier.
--- @param faction_shorthand_key string|nil A 3-letter faction shorthand.
--- @param unit_types table Unit-type buckets, e.g. { "monster", "monstrous_infantry" }.
--- @returns boolean True when the generator could buy one.
function M.can_field(faction_shorthand_key, unit_types)
    local data = faction_shorthand_key and factions_data[faction_shorthand_key]
    if data == nil then return false end
    local origins = enabled_origins()
    for _, tier_name in ipairs(TIER_NAMES) do
        local units = data.units[tier_name] or {}
        for _, unit_type in ipairs(unit_types) do
            for _, unit in ipairs(units[unit_type] or {}) do
                if buyable(unit, origins) then return true end
            end
        end
    end
    return false
end

--- True when a faction can field an army theme: it has at least `requires_count` distinct buyable units of the `requires` role, or the
--- theme requires nothing.
--- @param faction_shorthand_key string A 3-letter faction shorthand.
--- @param theme table An archetype-like record with optional `requires` and `requires_count`.
--- @returns boolean True when the faction can field it.
function M.can_field_theme(faction_shorthand_key, theme)
    if factions_data[faction_shorthand_key] == nil then return false end
    if theme.requires == nil then return true end
    return #build_role_pools(faction_shorthand_key, enabled_origins())[theme.requires] >= theme.requires_count
end

--- The price of any unit in factions_data, by its key. A unit listed by several factions takes its highest price, so every client agrees.
--- @param unit_key string The land unit key.
--- @returns number The unit's price, or 0 when factions_data does not list it.
function M.unit_price_by_key(unit_key)
    if not price_by_key then
        price_by_key = {}
        for _, faction in pairs(factions_data) do
            for _, by_type in pairs(faction.units or {}) do
                for _, units in pairs(by_type) do
                    for _, unit in ipairs(units) do
                        price_by_key[unit.land_unit] = math.max(price_by_key[unit.land_unit] or 0, unit_price(unit))
                    end
                end
            end
        end
    end
    return price_by_key[unit_key] or 0
end

--- Picks random units of a faction for the tower's unit offers: buyable units of the given tiers and unit types from enabled origins,
--- never Regiments of Renown unless `options.renown` asks for only them. A unit can be picked more than once.
--- @param faction_shorthand_key string A 3-letter faction shorthand.
--- @param tiers table Tier numbers to pick from, e.g. { 4, 5 }.
--- @param unit_types table|nil Unit-type buckets to pick from, or nil for every type.
--- @param count number How many units to pick.
--- @param options table|nil { renown = true to pick only Regiments of Renown, exclude = a unit key -> true set to leave out }.
--- @returns table Unit keys, empty when the faction has no data or no unit qualifies.
function M.pick_units(faction_shorthand_key, tiers, unit_types, count, options)
    options = options or {}
    local exclude = options.exclude or {}
    local data = factions_data[faction_shorthand_key]
    local pool, seen, picked = {}, {}, {}
    if data == nil then return picked end
    local origins = enabled_origins()
    for _, tier in ipairs(tiers) do
        local units = data.units["tier_" .. tier] or {}
        for _, unit_type in ipairs(unit_types or UNIT_TYPES) do
            for _, unit in ipairs(units[unit_type] or {}) do
                if buyable(unit, origins) and is_renown(unit) == (options.renown == true) and not exclude[unit.land_unit] and not seen[unit.land_unit] then
                    seen[unit.land_unit] = true
                    pool[#pool + 1] = unit.land_unit
                end
            end
        end
    end
    if #pool == 0 then return picked end
    for i = 1, count do picked[i] = pool[random_number(#pool)] end
    return picked
end

--- Generator options for a sized allied army: its lord, `units` regular units and no heroes, with gold to buy them all.
--- @param units number The regular units.
--- @returns table The options, see `M.generate`.
function M.ally_options(units)
    return { no_heroes = true, unit_count = units, budget_range = { units * ally_gold_per_unit[1], units * ally_gold_per_unit[2] } }
end

return M
