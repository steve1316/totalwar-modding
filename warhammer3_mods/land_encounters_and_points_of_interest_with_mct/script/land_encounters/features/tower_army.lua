--- Helpers that read and change the delving lord's army, shared by the tower delve and its offers.

local M = {}

--- Finds the delving lord's army.
--- @param general_cqi number The delving lord's command queue index.
--- @returns military_force|nil The army, or nil when the lord is gone or no longer leads one.
function M.delving_force(general_cqi)
    local general = cm:get_character_by_cqi(general_cqi)
    if not general or general:is_null_interface() or not general:has_military_force() then return nil end
    return general:military_force()
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
--- @returns table An array of { unit = unit interface, strength = 0-100 } in army order, empty when the lord leads no army.
function M.unit_strengths(general_cqi)
    local force = M.delving_force(general_cqi)
    local list = {}
    if not force then return list end
    local units = force:unit_list()
    for i = 0, units:num_items() - 1 do
        local unit = units:item_at(i)
        list[#list + 1] = { unit = unit, strength = unit:percentage_proportion_of_full_strength() }
    end
    return list
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
