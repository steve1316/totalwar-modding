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

--- How far from the tower the lord is put back, tried in turn: just outside its marker so the tower does not open again, then further out
--- when the ground there is taken.
local RETURN_DISTANCES = { 4, 8, 16, 32 }

--- How far from the lord a hero may stand and still go back to the tower with it. A freed hero is placed 5 away.
local FOLLOW_DISTANCE = 10

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

--- Finds valid ground for a character of a faction within `distance` of a map point.
--- @param faction_name string The faction.
--- @param point table The {x, y} to search around.
--- @param distance number How far out to search.
--- @returns table|nil The spot's {x, y}, or nil when there is none.
local function spot_near(faction_name, point, distance)
    local x, y = cm:find_valid_spawn_location_for_character_from_position(faction_name, point[1], point[2], false, distance)
    if x == -1 and y == -1 then return nil end
    return { x, y }
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
        local battlefield = spot_near(faction_name, spot, SPOT_OFFSET)
        if battlefield and apart(battlefield, last) >= least then return battlefield end
        log("tower: no valid battlefield beside " .. spot[1] .. ", " .. spot[2])
    end
    if #spots > 0 and #far == 0 then log("tower: no encounter spot lies " .. least .. " from the last battle") end
    return nil
end

--- The faction's heroes, as a set of command queue indexes (strings, so it saves), so heroes that arrive later can be told apart.
--- @param faction_name string The faction key.
--- @returns table Command queue index -> true.
function M.hero_set(faction_name)
    local set = {}
    local characters = cm:get_faction(faction_name):character_list()
    for i = 0, characters:num_items() - 1 do
        local character = characters:item_at(i)
        if cm:char_is_agent(character) then set[tostring(character:command_queue_index())] = true end
    end
    return set
end

--- Sends the faction's heroes that arrived during the delve and stand on the map near where the lord stood to the tower, each to the first
--- free ground of `distances` out. Heroes it had before the delve, in an army, in a settlement or far away stay put.
--- @param general userdata The delving lord.
--- @param faction_name string The delving faction.
--- @param from table Where the lord stood, as {x, y}.
--- @param coordinates table The tower's {x, y}.
--- @param distances table How far from the tower to look, in turn.
--- @param known table|nil The heroes the faction had when the delve started, see `M.hero_set`. Nil (an older save) leaves none out.
local function send_heroes_to_tower(general, faction_name, from, coordinates, distances, known)
    local characters = general:faction():character_list()
    for i = 0, characters:num_items() - 1 do
        local hero = characters:item_at(i)
        if cm:char_is_agent(hero) and not (known or {})[tostring(hero:command_queue_index())] and not hero:is_embedded_in_military_force() and hero:has_region()
            and apart(from, { hero:logical_position_x(), hero:logical_position_y() }) <= FOLLOW_DISTANCE then
            local spot = nil
            for _, distance in ipairs(distances) do
                spot = spot or spot_near(faction_name, coordinates, distance)
            end
            if spot then
                cm:teleport_to(cm:char_lookup_str(hero), spot[1], spot[2])
                log("tower: hero " .. hero:command_queue_index() .. " beside lord " .. general:command_queue_index() .. " goes to the tower, at " .. spot[1] .. ", "
                    .. spot[2])
            else
                log("tower: no spot near the tower for hero " .. hero:command_queue_index() .. ", it stays at " .. hero:logical_position_x() .. ", "
                    .. hero:logical_position_y())
            end
        end
    end
end

--- Moves the delving lord to a floor's battlefield. Heroes standing beside it (one a quest put there mid-delve) are sent to the tower once to
--- wait, rather than being left on the last battlefield.
--- @param general userdata The delving lord.
--- @param spot table The battlefield's {x, y}.
--- @param faction_name string The delving faction.
--- @param coordinates table The tower's {x, y}.
--- @param known table|nil The heroes the faction had when the delve started, which stay put.
function M.move_lord(general, spot, faction_name, coordinates, known)
    local from = { general:logical_position_x(), general:logical_position_y() }
    cm:teleport_to(cm:char_lookup_str(general), spot[1], spot[2])
    send_heroes_to_tower(general, faction_name, from, coordinates, RETURN_DISTANCES, known)
end

--- Puts the delving lord back beside the tower once the delve ends, if the lord still leads an army, and brings the heroes standing beside it.
--- @param general_cqi number The delving lord's command queue index.
--- @param faction_name string The delving faction.
--- @param coordinates table The tower's {x, y}.
--- @param known table|nil The heroes the faction had when the delve started, which stay put.
function M.return_lord(general_cqi, faction_name, coordinates, known)
    local general = tower_army.character(general_cqi)
    if not general or not general:has_military_force() then return end
    for _, distance in ipairs(RETURN_DISTANCES) do
        local spot = spot_near(faction_name, coordinates, distance)
        if spot then
            local from = { general:logical_position_x(), general:logical_position_y() }
            cm:teleport_to(cm:char_lookup_str(general), spot[1], spot[2])
            log("tower: lord " .. general_cqi .. " is sent back beside the tower at " .. spot[1] .. ", " .. spot[2] .. " (within " .. distance .. ")")
            --- The move lands a moment later, so where the lord ended up is read back then.
            cm:callback(function()
                local moved = tower_army.character(general_cqi)
                if moved then log("tower: lord " .. general_cqi .. " now stands at " .. moved:logical_position_x() .. ", " .. moved:logical_position_y()) end
            end, 0.5)
            send_heroes_to_tower(general, faction_name, from, coordinates, { distance }, known)
            return
        end
    end
    log("tower: no spot near the tower to bring lord " .. general_cqi .. " back to")
end

return M
