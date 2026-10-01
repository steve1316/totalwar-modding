--- Tower battlefields: each floor is fought somewhere else on the map. The game picks a battle's map from where it is fought, so fighting every
--- floor at the tower lands each one on the same map. The delving lord is moved beside a random encounter spot before the floor starts, and
--- back to the tower when the delve ends. Encounter spots are known land, spread over the whole map.

require("script/land_encounters/utils/random")

local tower_data = require("script/land_encounters/configs/tower_data")
local tower_army = require("script/land_encounters/features/tower_army")

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Constants

--- How far beside an encounter spot the lord is put, outside its marker so the encounter there does not open.
local SPOT_OFFSET = 8

--- How far from the tower the lord is put back, just outside its marker so the tower does not open again.
local RETURN_DISTANCE = 4

--- How many random spots are tried for a battlefield before the floor is fought where the lord stands.
local TRIES = 4

local M = {}

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Battlefields

--- Distance between two map points.
--- @param a table An {x, y}.
--- @param b table An {x, y}.
--- @returns number The distance in campaign map units.
local function apart(a, b)
    return math.sqrt((a[1] - b[1]) ^ 2 + (a[2] - b[2]) ^ 2)
end

--- Picks a floor's battlefield: a valid spot beside a random encounter spot at least `tower_data.battlefield_min_distance` from the last battle.
--- Tries `TRIES` spots, since the ground beside one can be taken. Picks with `random_number`.
--- @param faction_name string The delving faction.
--- @param spots table Every encounter spot's {x, y}, in a fixed order.
--- @param last table The last battle's {x, y}.
--- @returns table|nil The battlefield's {x, y}, or nil when no spot tried had valid ground far enough away.
function M.pick(faction_name, spots, last)
    local least = tower_data.battlefield_min_distance
    local far = {}
    for _, spot in ipairs(spots) do
        if apart(spot, last) >= least then far[#far + 1] = spot end
    end
    for _ = 1, math.min(TRIES, #far) do
        local spot = table.remove(far, random_number(#far))
        local x, y = cm:find_valid_spawn_location_for_character_from_position(faction_name, spot[1], spot[2], false, SPOT_OFFSET)
        if (x ~= -1 or y ~= -1) and apart({ x, y }, last) >= least then return { x, y } end
        log("tower: no valid battlefield beside " .. spot[1] .. ", " .. spot[2])
    end
    if #spots > 0 and #far == 0 then log("tower: no encounter spot lies " .. least .. " from the last battle") end
    return nil
end

--- Moves the delving lord to a floor's battlefield.
--- @param general userdata The delving lord.
--- @param spot table The battlefield's {x, y}.
function M.move_lord(general, spot)
    cm:teleport_to(cm:char_lookup_str(general), spot[1], spot[2])
end

--- Puts the delving lord back beside the tower once the delve ends, if the lord still leads an army.
--- @param general_cqi number The delving lord's command queue index.
--- @param faction_name string The delving faction.
--- @param coordinates table The tower's {x, y}.
function M.return_lord(general_cqi, faction_name, coordinates)
    local general = tower_army.character(general_cqi)
    if not general or not general:has_military_force() then return end
    local x, y = cm:find_valid_spawn_location_for_character_from_position(faction_name, coordinates[1], coordinates[2], false, RETURN_DISTANCE)
    if x == -1 and y == -1 then
        log("tower: no spot beside the tower to bring lord " .. general_cqi .. " back to")
        return
    end
    cm:teleport_to(cm:char_lookup_str(general), x, y)
    log("tower: lord " .. general_cqi .. " is back beside the tower at " .. x .. ", " .. y)
end

return M
