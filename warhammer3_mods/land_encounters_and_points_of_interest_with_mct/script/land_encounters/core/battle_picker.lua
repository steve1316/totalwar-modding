--- Battle event picker. Rolls a battle category by tier weight, then a flavoured or neutral dilemma and the enemy faction, and returns one
--- event record for the battle flow. `Army:new_from_event` builds the encounter army from that record.

require("script/land_encounters/utils/common")
require("script/land_encounters/utils/random")
require("script/land_encounters/core/mct")

local battle_categories = require("script/land_encounters/configs/battle_categories")
local debug_config = require("script/land_encounters/configs/debug")
local army_generator = require("script/land_encounters/core/army_generator")
local battle_modifiers = require("script/land_encounters/features/battle_modifiers")

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Constants

--- Position of each difficulty key in `DIFFICULTY_KEYS`, used to raise a battle to its category's minimum difficulty.
local DIFFICULTY_RANK = {}
for rank, key in ipairs(DIFFICULTY_KEYS) do
    DIFFICULTY_RANK[key] = rank
end

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

--- Reads the faction shorthands encounters may use right now.
--- @returns table The array from `get_enabled_faction_keys`.
--- @returns table The same shorthands as a shorthand -> true set.
local function enabled_factions()
    local keys = get_enabled_faction_keys()
    local set = {}
    for _, key in ipairs(keys) do
        set[key] = true
    end
    return keys, set
end

--- Lists the category's flavoured dilemmas whose faction is enabled, in config order.
--- @param category table A category record from configs/battle_categories.lua.
--- @param faction_set table A shorthand -> true set from `enabled_factions`.
--- @returns table An array of flavoured entries.
local function enabled_flavoured_entries(category, faction_set)
    local entries = {}
    for _, entry in ipairs(category.flavoured) do
        if faction_set[entry.faction] then table.insert(entries, entry) end
    end
    return entries
end

--- Readies an Ally in Peril battle's ally: sized when `ally.units` is set, and starting at one of `ally.strengths`.
--- @param event table The event record.
--- @param ally table The category's `ally` record.
local function add_ally(event, ally)
    event.ally = ally
    if ally.units then event.ally_options = army_generator.ally_options(ally.units - 1) end
    if ally.strengths then event.ally_strength = ally.strengths[random_number(#ally.strengths)] end
end

--- Builds the event record for a category. Uses a flavoured entry (and its faction) when the category has no neutral dilemma or the
--- flavoured roll succeeds, else the neutral dilemma with a random enabled faction.
--- @param category table A category record from configs/battle_categories.lua.
--- @param entries table The category's enabled flavoured entries. Must be non-empty when the category has no neutral dilemma.
--- @param faction_keys table The enabled faction shorthands, for the neutral faction roll.
--- @param difficulty string The current difficulty key.
--- @returns table The event record: category, dilemma, incidents and targets, faction, difficulty, archetype_keys, budget_multiplier, intervention,
--- and for an Ally in Peril battle `ally`, `ally_options` and `ally_strength`, then the battle `modifiers` with their `enemy_bundles` and
--- `ally_bundles`.
local function build_event(category, entries, faction_keys, difficulty)
    local minimum = category.min_difficulty
    local event = {
        category = category.key,
        victory_incident = category.victory_incident,
        avoidance_incident = category.avoidance_incident,
        victory_targets = category.victory_targets,
        avoidance_targets = category.avoidance_targets,
        difficulty = (minimum and DIFFICULTY_RANK[minimum] > DIFFICULTY_RANK[difficulty]) and minimum or difficulty,
        archetype_keys = category.archetypes,
        budget_multiplier = category.budget_multiplier,
        victory_items = category.victory_items,
        intervention = pick_intervention_type(INTERVENTION_BY_KEY[category.intervention]),
    }
    if #entries > 0 and (category.neutral == nil or random_chance(battle_categories.flavoured_chance)) then
        local entry = entries[random_number(#entries)]
        event.dilemma = entry.dilemma
        event.faction = entry.faction
        event.victory_incident = entry.victory_incident or event.victory_incident
        event.avoidance_incident = entry.avoidance_incident or event.avoidance_incident
    else
        event.dilemma = category.neutral.dilemma
        event.faction = faction_keys[random_number(#faction_keys)]
    end
    if debug_config.force_battle_faction[1] then
        event.faction = debug_config.force_battle_faction[1]
        log("battle_picker: debug force_battle_faction makes the enemy " .. event.faction)
    end
    if category.ally then add_ally(event, category.ally) end
    --- Battle modifiers: the enemy's and the allies' bundles go on with the sabotage and the ally, ours when the battle starts.
    event.modifiers = battle_modifiers.roll()
    event.enemy_bundles = battle_modifiers.bundles(event.modifiers, "enemy")
    event.ally_bundles = battle_modifiers.bundles(event.modifiers, "allies")
    out("DEBUG - battle_picker picked " .. event.category .. " (" .. event.dilemma .. ") for faction " .. tostring(event.faction) .. " on " .. event.difficulty)
    return event
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Picking

--- Builds a battle event for one given category, for the current MCT factions.
--- @param category table A category record from configs/battle_categories.lua.
--- @param difficulty string The current difficulty key.
--- @returns table The event record from `build_event`.
function M.pick_event(category, difficulty)
    local faction_keys, faction_set = enabled_factions()
    return build_event(category, enabled_flavoured_entries(category, faction_set), faction_keys, difficulty)
end

--- Picks a battle event: a tier by the current difficulty's tier weights, a category in that tier, then the event. Categories that cannot
--- fire with the enabled factions (Daemonic Gift without Khorne or Slaanesh), or Ally in Peril ones while the MCT turns allied battles off,
--- are left out, as they are when `options.no_allies` is set for a battle that forces its own type. The debug `battle_difficulty` and
--- `force_battle_categories` switches (configs/debug.lua) override the difficulty and the first category that can fire.
--- @param difficulty string The difficulty key. Defaults to `get_current_difficulty()`.
--- @param options table|nil { no_allies } to leave out the Ally in Peril categories.
--- @returns table The event record from `build_event`.
function M.pick(difficulty, options)
    if debug_config.battle_difficulty[1] then log("battle_picker: debug battle_difficulty forces " .. debug_config.battle_difficulty[1]) end
    difficulty = debug_config.battle_difficulty[1] or difficulty or get_current_difficulty()
    local faction_keys, faction_set = enabled_factions()
    local choices_by_tier = {}
    local choice_by_key = {}
    local allies_allowed = is_intervention_type_enabled(ALLIED_REINFORCEMENTS_PERMITTED_TYPE) and not (options and options.no_allies)
    for _, category in ipairs(battle_categories.list) do
        local entries = (allies_allowed or not category.ally) and enabled_flavoured_entries(category, faction_set) or {}
        if category.neutral ~= nil and (allies_allowed or not category.ally) or #entries > 0 then
            choices_by_tier[category.tier] = choices_by_tier[category.tier] or {}
            local choice = { category = category, entries = entries }
            table.insert(choices_by_tier[category.tier], choice)
            choice_by_key[category.key] = choice
        end
    end

    for _, forced_key in ipairs(debug_config.force_battle_categories) do
        local forced = choice_by_key[forced_key]
        if forced then
            log("battle_picker: debug force_battle_categories picks " .. forced_key)
            return build_event(forced.category, forced.entries, faction_keys, difficulty)
        end
    end

    local tier_entries = {}
    for tier, weight in ipairs(battle_categories.tier_weights[difficulty]) do
        if choices_by_tier[tier] then table.insert(tier_entries, { tier, weight }) end
    end
    local tier_choices = choices_by_tier[pick_weighted(tier_entries)]
    local choice = tier_choices[random_number(#tier_choices)]
    return build_event(choice.category, choice.entries, faction_keys, difficulty)
end

return M
