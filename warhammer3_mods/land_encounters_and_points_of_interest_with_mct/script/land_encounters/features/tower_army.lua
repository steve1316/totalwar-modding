--- Helpers that read and change the delving lord's army, shared by the tower delve and its offers.

local army_generator = require("script/land_encounters/core/army_generator")

local M = {}

--- Finds a living character by command queue index.
--- @param cqi number The character's command queue index.
--- @returns userdata|nil The character, or nil when gone.
function M.character(cqi)
    local found = cm:get_character_by_cqi(cqi)
    if not found or found:is_null_interface() then return nil end
    return found
end

--- Finds the delving lord's army.
--- @param general_cqi number The delving lord's command queue index.
--- @returns military_force|nil The army, or nil when the lord is gone or no longer leads one.
function M.delving_force(general_cqi)
    local general = M.character(general_cqi)
    if not general or not general:has_military_force() then return nil end
    return general:military_force()
end

--- Puts an effect bundle on the delving army.
--- @param general_cqi number The delving lord's command queue index.
--- @param bundle string The effect bundle key.
--- @param turns number|nil How many turns it lasts. nil or 0 keeps it until removed.
--- @returns boolean True when the army was found.
function M.apply_bundle(general_cqi, bundle, turns)
    local force = M.delving_force(general_cqi)
    if not force then return false end
    cm:apply_effect_bundle_to_force(bundle, force:command_queue_index(), turns or 0)
    log("tower: " .. bundle .. " on force " .. force:command_queue_index() .. (turns and turns > 0 and " for " .. turns .. " turns" or "") .. ", present: "
        .. tostring(force:has_effect_bundle(bundle)))
    return true
end

--- Takes an effect bundle off the delving army, if it still leads one.
--- @param general_cqi number The delving lord's command queue index.
--- @param bundle string The effect bundle key.
function M.remove_bundle(general_cqi, bundle)
    local force = M.delving_force(general_cqi)
    if force then cm:remove_effect_bundle_from_force(bundle, force:command_queue_index()) end
end

--- The most expensive of a floor army's units. Ties keep the army's order.
--- @param unit_keys table The floor army's unit keys, one per unit.
--- @param count number How many units to pick.
--- @returns table Unit keys, most expensive first. A key appears once per unit picked.
function M.most_expensive(unit_keys, count)
    local units = {}
    for i, key in ipairs(unit_keys) do units[i] = { key = key, price = army_generator.unit_price_by_key(key), index = i } end
    table.sort(units, function(a, b) return a.price > b.price or (a.price == b.price and a.index < b.index) end)
    local picked = {}
    for i = 1, math.min(count, #units) do picked[i] = units[i].key end
    return picked
end

--- Reads the delving lord's army strength, or nil when the lord no longer leads an army.
--- @param general_cqi number The delving lord's command queue index.
--- @returns number|nil The army's average unit strength (0-100).
function M.army_strength(general_cqi)
    local force = M.delving_force(general_cqi)
    return force and cm:military_force_average_strength(force)
end

--- Counts the free unit slots in an army.
--- @param force military_force The army.
--- @returns number Slots left under its unit limit.
function M.free_slots(force)
    return math.max(0, force:unit_count_limit() - force:unit_list():num_items())
end

--- Lists the delving army's units with their strength.
--- @param general_cqi number The delving lord's command queue index.
--- @returns table An array of { unit = unit interface, strength = 0-100, index = 0-based position, character = true for the lord and heroes } in
--- army order, empty when the lord leads no army.
function M.unit_strengths(general_cqi)
    local force = M.delving_force(general_cqi)
    local list = {}
    if not force then return list end
    local units = force:unit_list()
    for i = 0, units:num_items() - 1 do
        local unit = units:item_at(i)
        list[#list + 1] = { unit = unit, strength = unit:percentage_proportion_of_full_strength(), index = i, character = unit:unit_class() == "com" }
    end
    return list
end

--- Lists the delving army's regular units, leaving out the lord and heroes.
--- @param general_cqi number The delving lord's command queue index.
--- @returns table The `unit_strengths` entries that are not characters.
function M.regular_units(general_cqi)
    local list = {}
    for _, entry in ipairs(M.unit_strengths(general_cqi)) do
        if not entry.character then list[#list + 1] = entry end
    end
    return list
end

--- Finds the delving army's weakest regular unit, the first one on a tie.
--- @param general_cqi number The delving lord's command queue index.
--- @returns table|nil Its `unit_strengths` entry, or nil when the army has no regular unit.
function M.weakest_regular_unit(general_cqi)
    local weakest = nil
    for _, entry in ipairs(M.regular_units(general_cqi)) do
        if not weakest or entry.strength < weakest.strength then weakest = entry end
    end
    return weakest
end

--- Writes the delving army's units to the log, one "position:unit key strength% rRank" entry each, so an offer's change can be checked.
--- @param general_cqi number The delving lord's command queue index.
--- @param label string What the snapshot is, e.g. "before Swap the chaff".
function M.log_army(general_cqi, label)
    local parts = {}
    for _, entry in ipairs(M.unit_strengths(general_cqi)) do
        parts[#parts + 1] = entry.index .. ":" .. entry.unit:unit_key() .. " " .. math.floor(entry.strength + 0.5) .. "% r" .. entry.unit:experience_level()
            .. (entry.character and " (character)" or "")
    end
    log("tower army " .. label .. " (" .. #parts .. " units): " .. table.concat(parts, ", "))
end

--- Sets one unit's strength.
--- @param unit unit The unit interface.
--- @param strength number The new strength in points (0-100).
function M.set_strength(unit, strength)
    cm:set_unit_hp_to_unary_of_maximum(unit, math.max(1, math.min(100, strength)) / 100)
end

--- Heals a share of each unit's missing strength in the delving army.
--- @param general_cqi number The delving lord's command queue index.
--- @param share number Share of the missing strength to restore (0-1).
function M.heal_army(general_cqi, share)
    for _, entry in ipairs(M.unit_strengths(general_cqi)) do
        M.set_strength(entry.unit, entry.strength + share * (100 - entry.strength))
    end
end

return M
