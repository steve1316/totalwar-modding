--- Offer effects shared by tower offers and spot offers: checks and changes on a lord's army (damage, room, recruits, ranks, unit removal)
--- and on a faction (bundles, treasury, unique items). Each takes the lord's command queue index or the faction key, never a delve.

require("script/land_encounters/utils/random")

local tower_army = require("script/land_encounters/features/tower_army")
local tower_lords = require("script/land_encounters/features/tower_lords")
local item_pool = require("script/land_encounters/core/item_pool")
local army_generator = require("script/land_encounters/core/army_generator")
local Army = require("script/land_encounters/core/army")

local M = {}

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Army checks

--- True when a lord's army has lost any strength.
--- @param general_cqi number The lord's command queue index.
--- @returns boolean True when the army is below full strength.
function M.army_damaged(general_cqi)
    local strength = tower_army.army_strength(general_cqi)
    return strength ~= nil and strength < 100
end

--- True when a lord's army has room for `count` more units.
--- @param general_cqi number The lord's command queue index.
--- @param count number The units an offer adds.
--- @returns boolean True with at least `count` free slots.
function M.has_room(general_cqi, count)
    local force = tower_army.delving_force(general_cqi)
    return force ~= nil and tower_army.free_slots(force) >= count
end

--- True when a lord's army has missile units or artillery.
--- @param general_cqi number The lord's command queue index.
--- @returns boolean True when a regular unit shoots.
function M.army_shoots(general_cqi)
    for _, entry in ipairs(tower_army.regular_units(general_cqi)) do
        local class = entry.unit:unit_class()
        if class:find("_mis$") or class:find("^art") then return true end
    end
    return false
end

--- The regular units that can still take `ranks` more ranks without passing `max_rank`.
--- @param general_cqi number The lord's command queue index.
--- @param ranks number The ranks an offer adds.
--- @param max_rank number The highest rank a unit may reach.
--- @returns table The `tower_army.regular_units` entries at or below `max_rank - ranks`.
function M.rankable_units(general_cqi, ranks, max_rank)
    local list = {}
    for _, entry in ipairs(tower_army.regular_units(general_cqi)) do
        if entry.unit:experience_level() <= max_rank - ranks then list[#list + 1] = entry end
    end
    return list
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Unit picks

--- Finds the faction shorthand of a faction's culture.
--- @param faction_name string The faction key.
--- @returns string|nil The shorthand, or nil when its culture has no army data.
function M.culture_shorthand(faction_name)
    local faction = cm:get_faction(faction_name)
    return faction and Army.faction_shorthand_for_subculture(faction:subculture()) or nil
end

--- Picks a recruit offer's units: `offer.count` units of `offer.tiers` and `offer.unit_types` from a faction's army data, when the army has
--- room for them.
--- @param general_cqi number The lord's command queue index.
--- @param shorthand string|nil The faction shorthand to recruit from.
--- @param offer table The offer record: `count`, `tiers` and `unit_types`.
--- @returns table The picked unit keys, empty without room or a shorthand.
function M.pick_recruits(general_cqi, shorthand, offer)
    if not M.has_room(general_cqi, offer.count) or not shorthand then return {} end
    return army_generator.pick_units(shorthand, offer.tiers, offer.unit_types, offer.count)
end

--- Picks Regiments of Renown of a faction's culture that the army does not field, when the army has room for them.
--- @param general_cqi number The lord's command queue index.
--- @param faction_name string The lord's faction key.
--- @param count number How many to pick.
--- @returns table The picked unit keys, empty without room.
function M.pick_renown(general_cqi, faction_name, count)
    if not M.has_room(general_cqi, count) then return {} end
    local shorthand = M.culture_shorthand(faction_name)
    local fielded = {}
    for _, entry in ipairs(tower_army.unit_strengths(general_cqi)) do fielded[entry.unit:unit_key()] = true end
    return shorthand and army_generator.pick_units(shorthand, { 0, 1, 2, 3, 4, 5 }, nil, count, { renown = true, exclude = fielded }) or {}
end

--- Picks distinct legendary items for a faction.
--- @param faction_name string The faction key.
--- @param count number How many items to pick.
--- @returns table The picked item keys, fewer than `count` when the pool runs dry.
function M.pick_unique_items(faction_name, count)
    local items, tries = {}, 0
    while #items < count and tries < count * 5 do
        tries = tries + 1
        local item = item_pool.pick_legendary_item(faction_name)
        if item == nil then break end
        local fresh = true
        for _, held in ipairs(items) do fresh = fresh and held ~= item end
        if fresh then items[#items + 1] = item end
    end
    return items
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Army changes

--- Logs a lord's army now and again half a second later, once the game has applied an offer's changes, so they can be checked.
--- @param general_cqi number The lord's command queue index.
--- @param offer_key string The offer's key for the log.
function M.log_army_change(general_cqi, offer_key)
    tower_army.log_army(general_cqi, "before " .. offer_key)
    cm:callback(function() tower_army.log_army(general_cqi, "after " .. offer_key) end, 0.5)
end

--- Removes one unit from a lord's army. The game only removes by unit key, taking a copy of its own choosing, so when the army has other
--- copies the ones left are given the strengths they had beside this unit, strongest to strongest. The result matches removing this one.
--- @param general_cqi number The lord's command queue index.
--- @param entry table The unit's `tower_army.unit_strengths` entry.
function M.remove_unit(general_cqi, entry)
    local key = entry.unit:unit_key()
    local kept = {}
    for _, other in ipairs(tower_army.regular_units(general_cqi)) do
        if other.index ~= entry.index and other.unit:unit_key() == key then kept[#kept + 1] = other.strength end
    end
    local lookup = cm:char_lookup_str(cm:get_character_by_cqi(general_cqi))
    log("offer: removing unit " .. key .. " at " .. entry.index .. " (" .. math.floor(entry.strength + 0.5) .. "%) from " .. lookup)
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

--- Gives `offer.ranks` ranks to `offer.count` random units that can take them.
--- @param general_cqi number The lord's command queue index.
--- @param offer table The offer record: `count`, `ranks` and `max_rank`.
function M.add_ranks(general_cqi, offer)
    local pool = M.rankable_units(general_cqi, offer.ranks, offer.max_rank)
    for _ = 1, math.min(offer.count, #pool) do
        local entry = table.remove(pool, random_number(#pool))
        log("offer: +" .. offer.ranks .. " ranks to " .. entry.unit:unit_key() .. " at " .. entry.index)
        cm:add_experience_to_unit(entry.unit, offer.ranks)
    end
end

--- Removes the weakest regular unit and heals every other unit by `heal_share` of its missing strength.
--- @param general_cqi number The lord's command queue index.
--- @param heal_share number The share of missing strength healed, e.g. 0.5.
function M.blood_price(general_cqi, heal_share)
    local weakest = tower_army.weakest_regular_unit(general_cqi)
    for _, entry in ipairs(tower_army.unit_strengths(general_cqi)) do
        if entry.index ~= weakest.index then tower_army.set_strength(entry.unit, entry.strength + heal_share * (100 - entry.strength)) end
    end
    M.remove_unit(general_cqi, weakest)
end

--- Gives a lord a dark bargain: its trait and its army bundle.
--- @param general_cqi number The lord's command queue index.
--- @param offer table The offer record: `trait` and `effect_bundle`.
function M.dark_bargain(general_cqi, offer)
    tower_lords.add_trait(general_cqi, offer.trait, 1, true)
    tower_army.apply_bundle(general_cqi, offer.effect_bundle)
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Faction changes

--- Puts a bundle on a faction.
--- @param faction_name string The faction key.
--- @param bundle string The effect bundle key.
--- @param turns number How many turns it lasts.
function M.faction_bundle(faction_name, bundle, turns)
    cm:apply_effect_bundle(bundle, faction_name, turns)
    log("offer: " .. bundle .. " on faction " .. faction_name .. " for " .. turns .. " turns")
end

--- Reads a faction's treasury.
--- @param faction_name string The faction key.
--- @returns number The treasury gold, or 0 when the faction is missing.
function M.treasury(faction_name)
    local faction = cm:get_faction(faction_name)
    return faction and faction:treasury() or 0
end

return M
