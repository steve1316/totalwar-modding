--- Battle modifiers (configs/battle_modifiers.lua): rolls them onto a fight, writes their dilemma lines, and turns them into what the battle
--- needs: bundles per army, notices for the battle script, offers kept out of the draw, and the victory gold change.

require("script/land_encounters/utils/common")
require("script/land_encounters/utils/random")
require("script/land_encounters/core/mct")

local data = require("script/land_encounters/configs/battle_modifiers")
local debug_config = require("script/land_encounters/configs/debug")
local army_generator = require("script/land_encounters/core/army_generator")
local alliances = require("script/land_encounters/configs/alliances")

local M = {}

--- True when a modifier can roll for a fight: its `faction` and `difficulties` gates hold, and an army composition without a faction of its
--- own (a generic theme) has an enemy faction that can field it.
--- @param modifier table The modifier record.
--- @param fight table|nil The fight: `faction`, the enemy's 3-letter faction shorthand, and `difficulty`.
--- @returns boolean True when it can roll.
local function eligible(modifier, fight)
    if not (modifier.army or modifier.faction or modifier.difficulties) then return true end
    if fight == nil or fight.faction == nil then return false end
    if modifier.faction and modifier.faction ~= fight.faction then return false end
    if modifier.difficulties and not modifier.difficulties[fight.difficulty] then return false end
    if modifier.army and not modifier.faction then return army_generator.can_field_theme(fight.faction, modifier.army) end
    return true
end

--- Rolls a fight's modifiers: none unless the MCT chance hits (no random number is drawn at 0), else 1-3 by `count_weights`, never one
--- twice, never two of one group, and only those `eligible` for the fight. The debug `force_battle_modifiers` switch picks them instead.
--- @param fight table|nil The fight: `faction`, the enemy's 3-letter faction shorthand, and `difficulty`. Without it no army composition
--- rolls.
--- @returns table The modifier keys, possibly empty.
function M.roll(fight)
    if debug_config.force_battle_modifiers[1] then
        local forced = {}
        for _, key in ipairs(debug_config.force_battle_modifiers) do
            if data.by_key[key] then forced[#forced + 1] = key end
        end
        log("battle modifiers: debug force_battle_modifiers picks " .. table.concat(forced, ", "))
        return forced
    end
    local chance = get_mct_settings()[data.chance_setting] or 0
    if chance <= 0 or not random_chance(chance) then return {} end
    local count = pick_weighted(data.count_weights)
    local pool, picked, groups = {}, {}, {}
    for _, modifier in ipairs(data.list) do
        if eligible(modifier, fight) then pool[#pool + 1] = modifier end
    end
    while #picked < count and #pool > 0 do
        local modifier = table.remove(pool, random_number(#pool))
        if not (modifier.group and groups[modifier.group]) then
            picked[#picked + 1] = modifier.key
            if modifier.group then groups[modifier.group] = true end
        end
    end
    log("battle modifiers: rolled " .. table.concat(picked, ", "))
    return picked
end

--- The dilemma lines of a fight's modifiers.
--- @param keys table|nil The modifier keys.
--- @returns table The lines.
function M.lines(keys)
    local lines = {}
    for _, key in ipairs(keys or {}) do lines[#lines + 1] = common.get_localised_string(data.line_prefix .. key) end
    return lines
end

--- The offers a fight's modifiers keep out of its draw.
--- @param keys table|nil The modifier keys.
--- @returns table Offer key -> true.
function M.keeps_out(keys)
    local kept = {}
    for _, key in ipairs(keys or {}) do
        for _, offer_key in ipairs(data.by_key[key].keeps_out or {}) do kept[offer_key] = true end
    end
    return kept
end

--- The bundles a fight's modifiers put on one side for the battle.
--- @param keys table|nil The modifier keys.
--- @param side string "ours", "enemy" or "allies".
--- @returns table The bundle keys.
function M.bundles(keys, side)
    local bundles = {}
    for _, key in ipairs(keys or {}) do
        local modifier = data.by_key[key]
        if modifier.bundle and modifier.hits[side] then bundles[#bundles + 1] = data.bundle_prefix .. key .. "_" .. side end
    end
    return bundles
end

--- The battle notice names of a fight's modifiers, which the battle script shows as objectives and banners.
--- @param keys table|nil The modifier keys.
--- @returns table The notice names.
function M.notices(keys)
    local names = {}
    for _, key in ipairs(keys or {}) do names[#names + 1] = data.notice_prefix .. key end
    return names
end

--- The army theme a fight's modifiers build the enemy army from, for the army generator's `composition` option.
--- @param keys table|nil The modifier keys.
--- @returns table|nil The composition's `army` record (configs/battle_modifiers.lua), or nil when no composition rolled.
function M.composition(keys)
    for _, key in ipairs(keys or {}) do
        local army = data.by_key[key].army
        if army then return army end
    end
    return nil
end

--- Rolls the theme a hired allied army (Allies in the Dark) marches as: an ally faction for our subculture, never the enemy's, and one of
--- the generic army compositions it can field. Its choice names the theme, so it is rolled when the offer is drawn.
--- @param player_subculture string Our subculture key.
--- @param enemy_faction string|nil The enemy's 3-letter faction shorthand.
--- @returns table|nil { faction = the ally's shorthand, key = the composition key }, or nil when no ally or theme fits.
function M.roll_ally_theme(player_subculture, enemy_faction)
    local ally = alliances.pick_for_subculture(player_subculture, enemy_faction)
    if not ally then return nil end
    local themes = {}
    for _, modifier in ipairs(data.list) do
        if modifier.army and not modifier.faction and eligible(modifier, { faction = ally }) then themes[#themes + 1] = modifier.key end
    end
    if #themes == 0 then return nil end
    local theme = { faction = ally, key = themes[random_number(#themes)] }
    log("battle modifiers: the hired allies would be " .. ally .. " as " .. theme.key)
    return theme
end

--- A hired allied army's generator options (Allies in the Dark): its lord and `units` regular units, built from its theme's faction and
--- composition when one rolled.
--- @param units number The regular units.
--- @param theme table|nil The theme from `roll_ally_theme`.
--- @returns table The options, with `faction` (read by the army builder) and `composition` when themed.
function M.ally_options(units, theme)
    local options = army_generator.ally_options(units)
    if theme then options.faction, options.composition = theme.faction, data.by_key[theme.key].army end
    return options
end

--- An Allies in the Dark line key, in its version naming the theme its allied army rolled.
--- @param line string The offer's line key.
--- @param theme table|nil The theme, nil for the plain line.
--- @returns string The line key.
function M.ally_line(line, theme)
    return theme and line .. "_" .. theme.key or line
end

--- Names a hired allied army's theme for the log.
--- @param theme table|nil The theme.
--- @returns string ", <faction> as <key>", or "" without a theme.
function M.ally_theme_log(theme)
    return theme and ", " .. theme.faction .. " as " .. theme.key or ""
end

--- What a fight's modifiers multiply its victory gold by: each harmful one adds, each helpful one takes away, by `harm_gold`.
--- @param keys table|nil The modifier keys.
--- @returns number The multiplier, 1 for none.
function M.gold_multiplier(keys)
    local multiplier = 1
    for _, key in ipairs(keys or {}) do multiplier = multiplier + data.harm_gold[data.by_key[key].harm] end
    return multiplier
end

return M
