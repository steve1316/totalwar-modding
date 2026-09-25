--- LandEncounterManager. Sets up spots and POIs at first_tick based on the detected campaign's
--- coordinate data, and provides marker-trigger lookup, restore-from-save, and export-to-save helpers.

require("script/land_encounters/utils/common")
require("script/land_encounters/core/mct")

local Zone = require("script/land_encounters/core/spot").Zone

--- Fraction of all map points that are active in a campaign. 0.75 means 75% active. Overridable via MCT.
local DEFAULT_ACTIVE_SPOT_PERCENTAGE = 0.75

local LandEncounterManager = {
    zones = {},
    active_spot_percentage = DEFAULT_ACTIVE_SPOT_PERCENTAGE,
}

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Class methods

--- Bootstraps fresh land encounters and points of interest for a new campaign.
--- @param coordinates_by_zone table Region-keyed table of raw encounter coordinates.
--- @param perpetual_coordinates_with_types table Region-keyed table of POI coordinates with type info.
function LandEncounterManager:generate_land_encounters(coordinates_by_zone, perpetual_coordinates_with_types)
    self:initialize_spots_by_zone(coordinates_by_zone)
    self:populate_land_encounters()
    self:initialize_points_of_interest_by_zone(perpetual_coordinates_with_types)
    self:activate_points_of_interest_by_zone()
end

--- Restores zones and POIs from a previously saved campaign state instead of generating fresh ones.
--- @param coordinates_by_zone table Region-keyed table of raw encounter coordinates.
--- @param perpetual_coordinates_with_types table Region-keyed table of POI coordinates with type info.
--- @param previous_state table Flattened save state previously produced by export_state_as_a_table.
function LandEncounterManager:restore_from_previous_state(coordinates_by_zone, perpetual_coordinates_with_types, previous_state)
    self:initialize_spots_by_zone(coordinates_by_zone)
    self:reinstate_zone_land_encounters(previous_state)

    self:initialize_points_of_interest_by_zone(perpetual_coordinates_with_types)
    self:reinstate_zone_points_of_interest(previous_state)
end

--- Initializes one Zone per region from the map coordinate table.
--- @param coordinates_by_zone table Region-keyed table of raw encounter coordinates.
function LandEncounterManager:initialize_spots_by_zone(coordinates_by_zone)
    self.active_spot_percentage = get_mct_settings().spawn_percentage
    self.zones = {}
    for zone_name, zone_coordinates in pairs(coordinates_by_zone) do
        local zone = Zone:new(zone_name, zone_coordinates, self.active_spot_percentage)
        table.insert(self.zones, zone)
    end
end

--- Hands each zone its slice of the perpetual POI coordinate table.
--- @param perpetual_coordinates_with_types table Region-keyed table of POI coordinates with type info.
function LandEncounterManager:initialize_points_of_interest_by_zone(perpetual_coordinates_with_types)
    for i = 1, #self.zones do
        local zone = self.zones[i]
        zone:initialize_points_of_interest(perpetual_coordinates_with_types[zone.name])
    end
end

--- Walks each zone and promotes some of its raw spots into active land encounters.
function LandEncounterManager:populate_land_encounters()
    for i = 1, #self.zones do
        self:populate_zone(self.zones[i])
    end
end

--- Activates the POI markers in every zone (after they have been initialized).
function LandEncounterManager:activate_points_of_interest_by_zone()
    for i = 1, #self.zones do
        self.zones[i]:activate_points_of_interest()
    end
end

--- Updates each zone's spot-state book-keeping, then refills it with new land encounters.
function LandEncounterManager:update_land_encounters()
    for i = 1, #self.zones do
        local current_zone = self.zones[i]
        current_zone:update_occupied_and_prohibited_spot_states()
        --- TODO add POI controller logic
        self:populate_zone(current_zone)
    end
end

--- Promotes spots in the given zone into active land encounters (up to the spawn-percentage cap).
--- @param zone Zone The zone whose spots should be promoted.
function LandEncounterManager:populate_zone(zone)
    zone:try_add_land_encounters()
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Triggering related methods (incidents)

--- True when the marker is a land-encounter marker and the triggering character is eligible.
--- @param triggering_character character The character that crossed the marker.
--- @param marker_id string The marker key that fired the event.
--- @returns boolean True when both checks pass.
function LandEncounterManager:check_if_is_triggerable_marker(triggering_character, marker_id)
    return self:check_if_is_land_encounter_marker(marker_id) and self:check_triggering_character(triggering_character)
end


--- Filters out non-generals and Hertz's patrol mod patrol armies.
--- @param character character The character to validate.
--- @returns boolean True when the character is a general with a non-patrol army.
function LandEncounterManager:check_triggering_character(character)
    return cm:char_is_general_with_army(character) and character:military_force():force_type():key() ~= "PATROL_ARMY"
end


--- True only for markers placed by this mod (prefix "land_enc_marker_").
--- @param marker_id string The marker key that fired the event.
--- @returns boolean True when the prefix matches, false otherwise.
function LandEncounterManager:check_if_is_land_encounter_marker(marker_id)
    return string.find(marker_id, "land_enc_marker_")
end


--- Alias for find_spot_info kept for caller readability at trigger sites.
--- @param marker_id string The marker key that fired the event.
--- @returns table The spot_info record from find_spot_info, or an empty table on miss.
function LandEncounterManager:find_triggering_spot_info(marker_id)
    return self:find_spot_info(marker_id)
end

--- Deactivates the zone slot referenced by the spot_info record so the spot can be replaced.
--- @param current_spot_info table A spot_info record with zone and spot_index fields.
function LandEncounterManager:delete_land_encounter_given_marker_id(current_spot_info)
    current_spot_info.zone:deactivate_spot_in_zone(current_spot_info.spot_index)
end


--- Resolves a marker id to its zone + spot index + spot type + coordinates. Returns an empty table when no match.
--- @param marker_id string The marker key to resolve.
--- @returns table { zone Zone, spot_index number, spot_type number, coordinates table }, or empty table on miss.
function LandEncounterManager:find_spot_info(marker_id)
    local zone_name_and_spot_index = process_marker_id(marker_id)
    for i=1, #self.zones do
        if self.zones[i].name == zone_name_and_spot_index[1] then
            local spot_type = zone_name_and_spot_index[3]
            local coordinates = {}
            if spot_type == 0 then
                coordinates = self.zones[i].spot_delegate.spots[zone_name_and_spot_index[2]].coordinates
            else
                coordinates = self.zones[i].point_of_interest_delegate.points_of_interest[zone_name_and_spot_index[2]].coordinates
            end
            return {
                zone = self.zones[i],
                spot_index = zone_name_and_spot_index[2],
                spot_type = spot_type,
                coordinates = coordinates
            }
        end
    end
    return {}
end


--- Restores per-zone land-encounter spot state from a previous save.
--- @param previous_state table Flattened save state previously produced by export_state_as_a_table.
function LandEncounterManager:reinstate_zone_land_encounters(previous_state)
    for i = 1, #self.zones do
        self.zones[i]:reinstate_from_previous_state(previous_state)
    end
end


--- Restores per-zone POI state from a previous save.
--- @param previous_state table Flattened save state previously produced by export_state_as_a_table.
function LandEncounterManager:reinstate_zone_points_of_interest(previous_state)
    for i = 1, #self.zones do
        self.zones[i]:reinstate_points_of_interest(previous_state)
    end
end


--- Flattens every zone's spot and POI data into a single key/value table for CA's save-state manager.
--- @returns table A flat key/value table suitable for the save state.
function LandEncounterManager:export_state_as_a_table()
    local land_encounter_state = {}
    for i=1, #self.zones do

        local current_zone_spot_delegate = self.zones[i].spot_delegate
        for j=1, #current_zone_spot_delegate.spots do
            local event_spot = current_zone_spot_delegate.spots[j]
            local flattened_spot_key = self.zones[i].name .. "_" .. tostring(event_spot.coordinates[1]) .. "_" .. tostring(event_spot.coordinates[2])
            event_spot:flatten_info(land_encounter_state, flattened_spot_key)

            --- Record whether the spot is prohibited or active.
            land_encounter_state[flattened_spot_key .. "_active_spot_flag"] = current_zone_spot_delegate.active_spots[event_spot.index]
            land_encounter_state[flattened_spot_key .. "_prohibited_spot_flag"] = current_zone_spot_delegate.prohibited_spots[event_spot.index]
        end

        local current_zone_poi_delegate = self.zones[i].point_of_interest_delegate
        for j=1, #current_zone_poi_delegate.points_of_interest do
            local current_spot = current_zone_poi_delegate.points_of_interest[j]
            current_spot:flatten_info(land_encounter_state, self.zones[i].name)
        end
    end
    return land_encounter_state
end



--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Constructors

--- Constructs a fresh LandEncounterManager with empty zone state and the default spawn percentage.
--- @returns LandEncounterManager A new manager instance ready for bootstrap.
function LandEncounterManager:new()
    local t = {
        zones = {},
        active_spot_percentage = DEFAULT_ACTIVE_SPOT_PERCENTAGE,
    }
    setmetatable(t, self)
    self.__index = self
    return t
end

return LandEncounterManager
