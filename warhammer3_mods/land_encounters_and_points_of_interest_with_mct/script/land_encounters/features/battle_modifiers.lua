--- Battle modifiers (configs/battle_modifiers.lua): rolls them onto a fight, writes their dilemma lines, and turns them into what the battle
--- needs: bundles per army, notices for the battle script, offers kept out of the draw, and the victory gold change.

require("script/land_encounters/utils/common")
require("script/land_encounters/utils/random")
require("script/land_encounters/core/mct")

local data = require("script/land_encounters/configs/battle_modifiers")
local debug_config = require("script/land_encounters/configs/debug")

local M = {}

--- Rolls a fight's modifiers: none unless the MCT chance hits (no random number is drawn at 0), else 1-3 by `count_weights`, never one
--- twice and never two of one group. The debug `force_battle_modifiers` switch picks them instead.
--- @returns table The modifier keys, possibly empty.
function M.roll()
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
    for _, modifier in ipairs(data.list) do pool[#pool + 1] = modifier end
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

--- The dilemma lines of a fight's modifiers, one per line, ending in a blank line, or "" for none.
--- @param keys table|nil The modifier keys.
--- @returns string The text.
function M.lines(keys)
    local lines = {}
    for _, key in ipairs(keys or {}) do lines[#lines + 1] = common.get_localised_string(data.line_prefix .. key) end
    return #lines > 0 and table.concat(lines, "\n") .. "\n\n" or ""
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
        if modifier.bundle then
            for _, hit in ipairs(modifier.sides) do
                if hit == side then bundles[#bundles + 1] = data.bundle_prefix .. key .. "_" .. side end
            end
        end
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

--- What a fight's modifiers multiply its victory gold by: each harmful one adds, each helpful one takes away, by `harm_gold`.
--- @param keys table|nil The modifier keys.
--- @returns number The multiplier, 1 for none.
function M.gold_multiplier(keys)
    local multiplier = 1
    for _, key in ipairs(keys or {}) do multiplier = multiplier + data.harm_gold[data.by_key[key].harm] end
    return multiplier
end

return M
