--- Battle event picker. Rolls a battle category by tier weight, then a flavoured or neutral dilemma and the enemy faction, and returns one
--- event record for the battle flow. `Army:new_from_event` builds the encounter army from that record.

require("script/land_encounters/utils/common")
require("script/land_encounters/utils/random")
require("script/land_encounters/core/mct")

local battle_categories = require("script/land_encounters/configs/battle_categories")

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Constants

--- Difficulty keys from easiest to hardest, used to raise a battle to its category's minimum difficulty.
local DIFFICULTY_ORDER = { "easy", "medium", "hard" }

--- Maps a category's forced battle type to the battle-type tag from common.lua.
local INTERVENTION_BY_KEY = {
    ambush = AMBUSH_TYPE,
    interception = INTERCEPTION_TYPE,
    allied = ALLIED_REINFORCEMENTS_PERMITTED_TYPE,
}

local M = {}

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Helpers

--- Builds the set of faction shorthands encounters may use right now.
--- @returns table A shorthand -> true set from `get_enabled_faction_keys`.
local function enabled_faction_set()
    local enabled = {}
    for _, key in ipairs(get_enabled_faction_keys()) do
        enabled[key] = true
    end
    return enabled
end

--- Lists the category's flavoured dilemmas whose faction is enabled, in config order.
--- @param category table A category record from configs/battle_categories.lua.
--- @param enabled_factions table A shorthand -> true set from `enabled_faction_set`.
--- @returns table An array of flavoured entries.
local function enabled_flavoured_entries(category, enabled_factions)
    local entries = {}
    for _, entry in ipairs(category.flavoured) do
        if enabled_factions[entry.faction] then table.insert(entries, entry) end
    end
    return entries
end

--- Returns the harder of two difficulty keys.
--- @param difficulty string The current difficulty key.
--- @param minimum string The category's minimum difficulty key, or nil.
--- @returns string The difficulty key to use.
local function raise_difficulty(difficulty, minimum)
    if minimum == nil then return difficulty end
    local rank = {}
    for index, key in ipairs(DIFFICULTY_ORDER) do rank[key] = index end
    return rank[minimum] > rank[difficulty] and minimum or difficulty
end

--- Resolves a category's forced battle type against the MCT toggles: the forced type when enabled, else Interception when enabled, else the
--- normal MCT pick. Categories without a forced type use the normal MCT pick.
--- @param forced_key string "ambush", "interception", "allied", or nil.
--- @returns number One of AMBUSH_TYPE, INTERCEPTION_TYPE, or ALLIED_REINFORCEMENTS_PERMITTED_TYPE.
local function resolve_intervention_type(forced_key)
    if forced_key == nil then return pick_intervention_type() end
    local enabled = {}
    for _, type_tag in ipairs(get_mct_settings().enabled_intervention_types or {}) do enabled[type_tag] = true end
    if enabled[INTERVENTION_BY_KEY[forced_key]] then return INTERVENTION_BY_KEY[forced_key] end
    if enabled[INTERCEPTION_TYPE] then return INTERCEPTION_TYPE end
    return pick_intervention_type()
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Picking

--- Builds a battle event for one category: a flavoured dilemma for an enabled faction, or the neutral dilemma for a random enabled faction.
--- The category must have a neutral dilemma or at least one enabled flavoured entry.
--- @param category table A category record from configs/battle_categories.lua.
--- @param difficulty string The current difficulty key. Defaults to `get_current_difficulty()`.
--- @param enabled_factions table An optional shorthand -> true set. Defaults to the current MCT factions.
--- @returns table The event record: category, dilemma, incidents and targets, faction, difficulty, archetype_keys, budget_multiplier, intervention.
function M.pick_event(category, difficulty, enabled_factions)
    difficulty = difficulty or get_current_difficulty()
    local entries = enabled_flavoured_entries(category, enabled_factions or enabled_faction_set())
    local use_flavoured = #entries > 0 and (category.neutral == nil or random_chance(battle_categories.flavoured_chance))

    local event = {
        category = category.key,
        victory_incident = category.victory_incident,
        avoidance_incident = category.avoidance_incident,
        victory_targets = category.victory_targets,
        avoidance_targets = category.avoidance_targets,
        difficulty = raise_difficulty(difficulty, category.min_difficulty),
        archetype_keys = category.archetypes,
        budget_multiplier = category.budget_multiplier,
        intervention = resolve_intervention_type(category.intervention),
    }
    if use_flavoured then
        local entry = entries[random_number(#entries)]
        event.dilemma = entry.dilemma
        event.faction = entry.faction
        event.victory_incident = entry.victory_incident or event.victory_incident
        event.avoidance_incident = entry.avoidance_incident or event.avoidance_incident
    else
        event.dilemma = category.neutral.dilemma
        event.faction = get_random_faction()
    end
    out("DEBUG - battle_picker picked " .. event.category .. " (" .. event.dilemma .. ") for faction " .. tostring(event.faction) .. " on " .. event.difficulty)
    return event
end

--- Picks a battle event: a tier by the difficulty's tier weights, a category in that tier, then the event. Categories that cannot fire with
--- the enabled factions (Daemonic Gift without Khorne or Slaanesh) are left out.
--- @param difficulty string The current difficulty key. Defaults to `get_current_difficulty()`.
--- @returns table The event record from `pick_event`.
function M.pick(difficulty)
    difficulty = difficulty or get_current_difficulty()
    local enabled_factions = enabled_faction_set()
    local categories_by_tier = {}
    for _, category in ipairs(battle_categories.list) do
        if category.neutral ~= nil or #enabled_flavoured_entries(category, enabled_factions) > 0 then
            categories_by_tier[category.tier] = categories_by_tier[category.tier] or {}
            table.insert(categories_by_tier[category.tier], category)
        end
    end

    local tier_entries = {}
    for tier, weight in ipairs(battle_categories.tier_weights[difficulty]) do
        if categories_by_tier[tier] then table.insert(tier_entries, { tier, weight }) end
    end
    local tier_categories = categories_by_tier[pick_weighted(tier_entries)]
    return M.pick_event(tier_categories[random_number(#tier_categories)], difficulty, enabled_factions)
end

return M
