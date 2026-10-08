--- Army spells: rolls a spell from a pool (configs/army_spells.lua) and names its bundle and payload line. A spell's bundle grants it as an
--- army ability for the battle it is on the army, cast at no Winds of Magic cost.

require("script/land_encounters/utils/common")
require("script/land_encounters/utils/random")

local data = require("script/land_encounters/configs/army_spells")

local M = {}

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Constants

--- Prefix of each spell's bundle and payload line. The spell's id follows.
local BUNDLE_PREFIX = "land_enc_effect_tower_spell_"
local LINE_PREFIX = "dummy_land_enc_spot_spell_"

--- Every spell, lore then bound then army, for the "all" pool.
local ALL = {}
--- Spell id -> its name, for the log.
local NAMES = {}
for _, pool in ipairs({ "lore", "bound", "army" }) do
    for _, spell in ipairs(data.pools[pool]) do
        ALL[#ALL + 1] = spell
        NAMES[spell.id] = spell.name
    end
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Spells

--- Rolls a spell from a pool with `random_number`, so every multiplayer client rolls the same one.
--- @param pool string "lore", "bound", "army" or "all".
--- @returns string The spell's id.
function M.roll(pool)
    local list = pool == "all" and ALL or data.pools[pool]
    local spell = list[random_number(#list)]
    log("army spells: rolled " .. spell.id .. " (" .. spell.name .. ") from the " .. pool .. " pool")
    return spell.id
end

--- A spell's bundle.
--- @param id string The spell's id.
--- @returns string The bundle key.
function M.bundle(id)
    return BUNDLE_PREFIX .. id
end

--- A spell's payload line, which names it and its uses.
--- @param id string The spell's id.
--- @returns string The line key.
function M.line(id)
    return LINE_PREFIX .. id
end

--- Puts a spell's payload line second on a choice, under the offer's own line. Does nothing without a spell.
--- @param lines table The choice's line keys.
--- @param id string|nil The spell's id.
function M.add_line(lines, id)
    if id then table.insert(lines, 2, M.line(id)) end
end

--- A spell's name, for the log.
--- @param id string The spell's id.
--- @returns string The name, or the id when unknown.
function M.name(id)
    return NAMES[id] or id
end

return M
