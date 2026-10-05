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

--- True when a modifier can roll for a fight. An army composition needs an enemy faction that can field its theme, and a lore army
--- its own faction on a difficulty in `lore_difficulties`.
--- @param modifier table The modifier record.
--- @param fight table|nil The fight: `faction`, the enemy's 3-letter faction shorthand, and `difficulty`.
--- @returns boolean True when it can roll.
local function eligible(modifier, fight)
    local army = modifier.army
    if not army then return true end
    if fight == nil or fight.faction == nil then return false end
    if army.faction then return army.faction == fight.faction and data.lore_difficulties[fight.difficulty] == true end
    return army_generator.can_field_theme(fight.faction, army)
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
--- @returns table|nil The theme with its modifier key as `key`, or nil when no composition rolled. A lore army's also has `units` (a set of
--- its lore unit keys), `share` (the share of the army's unit slots they fill), `budget` (its budget multiplier), and `rank_share` and
--- `max_ranks` (the extra ranks its unspent gold buys its lore units).
function M.composition(keys)
    for _, key in ipairs(keys or {}) do
        local army = data.by_key[key].army
        if army then
            local theme = { key = key, shares = army.shares, price_mode = army.price_mode }
            if army.units then
                theme.units, theme.share, theme.budget = {}, data.lore_share, data.lore_budget
                theme.rank_share, theme.max_ranks = data.lore_rank_share, data.lore_max_ranks
                for _, unit_key in ipairs(army.units) do theme.units[unit_key] = true end
            end
            return theme
        end
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
        local army = modifier.army
        if army and not army.faction and army_generator.can_field_theme(ally, army) then themes[#themes + 1] = modifier.key end
    end
    if #themes == 0 then return nil end
    local theme = { faction = ally, key = themes[random_number(#themes)] }
    log("battle modifiers: the hired allies would be " .. ally .. " as " .. theme.key)
    return theme
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
