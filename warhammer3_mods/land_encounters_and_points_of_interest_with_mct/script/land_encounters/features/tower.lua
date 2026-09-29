--- TowerState + TowerEventDelegate. One tower stands in every zone, on one of that zone's encounter spots, and is held by one enemy
--- faction for the whole campaign. TowerEventDelegate places the towers, keeps their markers in line with MCT, ticks their cooldowns
--- and saves them.

require("script/land_encounters/utils/common")
require("script/land_encounters/utils/random")
require("script/land_encounters/core/mct")
require("script/land_encounters/core/managers")

local TowerSpot = require("script/land_encounters/core/spot").TowerSpot

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- TowerState

local TowerState = {
    --- Zone the tower stands in.
    zone_name = "",
    --- Index of the encounter spot the tower occupies in its zone.
    spot_index = 0,
    --- The tower's {x, y} position.
    coordinates = {0, 0},
    --- Shorthand of the faction holding the tower, such as "skv".
    faction = "",
    --- Turns left before the tower can be entered again. 0 means open.
    cooldown = 0,
}

--- Builds a tower record.
--- @param zone_name string Zone the tower stands in.
--- @param spot_index number Index of the encounter spot the tower occupies.
--- @param coordinates table The tower's {x, y} position.
--- @param faction string Shorthand of the faction holding the tower.
--- @param cooldown number Turns left before the tower opens.
--- @returns TowerState The new tower.
function TowerState:new(zone_name, spot_index, coordinates, faction, cooldown)
    local t = { zone_name = zone_name, spot_index = spot_index, coordinates = coordinates, faction = faction, cooldown = cooldown or 0 }
    setmetatable(t, self)
    self.__index = self
    return t
end

--- Exports the tower as a plain table for the save file.
--- @returns table The tower's saved fields.
function TowerState:export()
    return { zone_name = self.zone_name, spot_index = self.spot_index, coordinates = self.coordinates, faction = self.faction, cooldown = self.cooldown }
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Helpers

--- Returns a picker that hands out the enabled faction shorthands in a shuffled order, skipping ones already taken, and starts over once
--- every faction is used. The shorthands are sorted before the shuffle so every multiplayer client sees the same order.
--- @param taken table Shorthand -> true set of factions restored towers already hold.
--- @returns function A function that returns the next faction shorthand.
local function faction_picker(taken)
    local keys = get_enabled_faction_keys()
    table.sort(keys)
    local queue = {}
    for _, key in ipairs(keys) do
        if not taken[key] then queue[#queue + 1] = key end
    end
    randomic_shuffle(queue)
    local next_index = 1
    return function()
        if next_index > #queue then
            queue = randomic_shuffle(keys)
            next_index = 1
        end
        next_index = next_index + 1
        return queue[next_index - 1]
    end
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- TowerEventDelegate

local TowerEventDelegate = {
    --- Every tower on the map, one per zone, in zone-name order.
    towers = {},
    --- Shared invasion battle manager, used by delves.
    invasion_battle_manager = nil,
}

--- Places a tower in every zone that does not have one yet, restores the rest from the save, reserves their spots and shows their markers.
--- Zones are walked in name order so every multiplayer client places the same towers.
--- @param zones table The land manager's zones.
--- @param saved table|nil The `towers` list from `export_state_as_table`, or nil for a new campaign or an older save.
function TowerEventDelegate:initialize(zones, saved)
    local saved_by_zone, taken = {}, {}
    for _, record in ipairs(saved or {}) do
        saved_by_zone[record.zone_name] = record
    end

    local zone_by_name, names = {}, {}
    for _, zone in ipairs(zones) do
        zone_by_name[zone.name] = zone
        names[#names + 1] = zone.name
    end
    table.sort(names)

    self.towers = {}
    local pending = {}
    for _, name in ipairs(names) do
        local spots = zone_by_name[name].spot_delegate.spots
        local record = saved_by_zone[name]
        if record and spots[record.spot_index] then
            self.towers[#self.towers + 1] = TowerState:new(name, record.spot_index, spots[record.spot_index].coordinates, record.faction, record.cooldown)
            taken[record.faction] = true
        elseif #spots > 0 then
            pending[#pending + 1] = name
        end
    end

    local next_faction = faction_picker(taken)
    for _, name in ipairs(pending) do
        local spots = zone_by_name[name].spot_delegate.spots
        local spot_index = random_number(#spots)
        self.towers[#self.towers + 1] = TowerState:new(name, spot_index, spots[spot_index].coordinates, next_faction())
        log("Placed a tower in " .. name .. " at spot " .. spot_index .. " held by " .. tostring(self.towers[#self.towers].faction))
    end
    table.sort(self.towers, function(a, b) return a.zone_name < b.zone_name end)

    for _, tower in ipairs(self.towers) do
        zone_by_name[tower.zone_name].spot_delegate:reserve_spot(tower.zone_name, tower.spot_index)
    end
    self:sync_markers()
end

--- Shows every tower marker when towers are enabled in MCT, and removes them otherwise.
function TowerEventDelegate:sync_markers()
    local enabled = get_mct_settings().enable_towers
    for _, tower in ipairs(self.towers) do
        if enabled then
            TowerSpot.place_marker(tower.zone_name, tower.spot_index, tower.coordinates)
        else
            TowerSpot.remove_marker(tower.zone_name, tower.spot_index)
        end
    end
end

--- Ticks every tower's cooldown down by one turn. Runs once per round and does nothing while towers are disabled.
function TowerEventDelegate:update_state_given_turn_passing()
    if not get_mct_settings().enable_towers then return end
    for _, tower in ipairs(self.towers) do
        if tower.cooldown > 0 then
            tower.cooldown = tower.cooldown - 1
        end
    end
end

--- Exports every tower for the save file.
--- @returns table A list of saved tower records.
function TowerEventDelegate:export_state_as_table()
    local saved = {}
    for i, tower in ipairs(self.towers) do
        saved[i] = tower:export()
    end
    return saved
end

--- Builds an empty delegate. `initialize` places or restores the towers once the zones exist.
--- @param invasion_battle_manager InvasionBattleManager The shared invasion battle manager.
--- @returns TowerEventDelegate The new delegate.
function TowerEventDelegate:new(invasion_battle_manager)
    local t = { towers = {}, invasion_battle_manager = invasion_battle_manager }
    setmetatable(t, self)
    self.__index = self
    return t
end

return TowerEventDelegate
