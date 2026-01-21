require("script/land_encounters/utils/logger")
require("script/land_encounters/utils/strings")
require("script/shared/mct_settings")

local Zone = require("script/land_encounters/models/zone")

-------------------------
--- Constant values of the class [DO NOT CHANGE]
-------------------------
-- Should be 0.75 by default. This means that 75% of all points are active during a campaign. Modify to make it more.
local DEFAULT_ACTIVE_SPOT_PERCENTAGE = 0.75

--=======================
--- Properties definition
--=======================
local LandEncounterManager = {
    zones = {},
    active_spot_percentage = DEFAULT_ACTIVE_SPOT_PERCENTAGE, -- should be changed through MCT. 1.0 for debugging. 0.75 normally. Should be configurable through MCT
}

--=======================
--- Class Methods
--=======================
-------------------------
function LandEncounterManager:generate_land_encounters(coordinates_by_zone, perpetual_coordinates_with_types)
    -- Create new land encounters given the map coordinates from whatever map was selected
    self:initialize_spots_by_zone(coordinates_by_zone)
    -- Show those encounters in the map with their respective events
    self:populate_land_encounters()
    -- Initialize the points of interest
    self:initialize_points_of_interest_by_zone(perpetual_coordinates_with_types)
    -- Activate the points of interest
    self:activate_points_of_interest_by_zone()
end

-- Restores the data from a previous saved spot
function LandEncounterManager:restore_from_previous_state(coordinates_by_zone, perpetual_coordinates_with_types, previous_state)
    -- Create new land encounters given the map coordinates from whatever map was selected
    self:initialize_spots_by_zone(coordinates_by_zone)
    -- Restore the data inside each encounter
    self:reinstate_zone_land_encounters(previous_state)
    
    self:initialize_points_of_interest_by_zone(perpetual_coordinates_with_types)
    -- Reinstates the state of the points of interest
    self:reinstate_zone_points_of_interest(previous_state)
end

-- Initialize the spots from the map coordinates given, through iterating from them. 
function LandEncounterManager:initialize_spots_by_zone(coordinates_by_zone)
    self.active_spot_percentage = get_mct_settings().spawn_percentage
    self.zones = {}
    for zone_name, zone_coordinates in pairs(coordinates_by_zone) do
        local zone = Zone:new(zone_name, zone_coordinates, self.active_spot_percentage)
        table.insert(self.zones, zone)
    end
end

function LandEncounterManager:initialize_points_of_interest_by_zone(perpetual_coordinates_with_types)
    for i = 1, #self.zones do
        local zone = self.zones[i]
        zone:initialize_points_of_interest(perpetual_coordinates_with_types[zone.name])
    end
end

-- Given the [spots] are initialized, initialize some of the spots to become land encounters that can give events or battles
function LandEncounterManager:populate_land_encounters()
    for i = 1, #self.zones do
        self:populate_zone(self.zones[i])
    end
end

function LandEncounterManager:activate_points_of_interest_by_zone()
    for i = 1, #self.zones do
        self.zones[i]:activate_points_of_interest()
    end
end

function LandEncounterManager:update_land_encounters()
    for i = 1, #self.zones do
        local current_zone = self.zones[i]
        current_zone:update_occupied_and_prohibited_spot_states()
        -- TODO add POI controller logic
        self:populate_zone(current_zone)
    end    
end

function LandEncounterManager:populate_zone(zone)
    zone:try_add_land_encounters()
end

---------------------------
-- TRIGGERING RELATED METHODS
---------------------------
-- INCIDENTS
---------------------------
-- Checks wether an event should be triggered for the character entering a marker
function LandEncounterManager:check_if_is_triggerable_marker(triggering_character, marker_id)
    return self:check_if_is_land_encounter_marker(marker_id) and self:check_triggering_character(triggering_character)
end


-- prevent triggering if it's not a general, or if it's a patrol army from Hertz's patrol mod
function LandEncounterManager:check_triggering_character(character)
    return cm:char_is_general_with_army(character) and character:military_force():force_type():key() ~= "PATROL_ARMY"
end


-- prevent triggering if it's not a land_encounter
function LandEncounterManager:check_if_is_land_encounter_marker(marker_id)
    return string.find(marker_id, "land_enc_marker_")
end


function LandEncounterManager:find_triggering_spot_info(marker_id)
    return self:find_spot_info(marker_id)
end

function LandEncounterManager:delete_land_encounter_given_marker_id(current_spot_info)
    current_spot_info.zone:deactivate_spot_in_zone(current_spot_info.spot_index)
end


--- try_find_spot_info
--- @desc process the area_key entered in the marker and finds the relevant information to trigger a related event
--- @param marker_id string CA variable contains obtained from area_key()  
--- @return table spot_info or empty table that contains the spot index on the zone and the spot type for triggering the event
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


function LandEncounterManager:reinstate_zone_land_encounters(previous_state)
    for i = 1, #self.zones do
        self.zones[i]:reinstate_from_previous_state(previous_state)
    end
end


function LandEncounterManager:reinstate_zone_points_of_interest(previous_state)
    for i = 1, #self.zones do
        self.zones[i]:reinstate_points_of_interest(previous_state)
    end
end


-- exports the entirety of the data of the land battles for saving it in a flattened table as expected by the save state manager of
-- creative assembly
function LandEncounterManager:export_state_as_a_table()
    local land_encounter_state = {}
    for i=1, #self.zones do

        local current_zone_spot_delegate = self.zones[i].spot_delegate
        for j=1, #current_zone_spot_delegate.spots do
            -- save state of event spots
            local event_spot = current_zone_spot_delegate.spots[j]
            local flattened_spot_key = self.zones[i].name .. "_" .. tostring(event_spot.coordinates[1]) .. "_" .. tostring(event_spot.coordinates[2])
            event_spot:flatten_info(land_encounter_state, flattened_spot_key)

            --save state of zone delegates
            -- should the spot be prohibited or active we also record it 
            land_encounter_state[flattened_spot_key .. "_active_spot_flag"] = current_zone_spot_delegate.active_spots[event_spot.index]
            land_encounter_state[flattened_spot_key .. "_prohibited_spot_flag"] = current_zone_spot_delegate.prohibited_spots[event_spot.index]
        end

        --save state of points of interest
        local current_zone_poi_delegate = self.zones[i].point_of_interest_delegate
        for j=1, #current_zone_poi_delegate.points_of_interest do
            local current_spot = current_zone_poi_delegate.points_of_interest[j]
            current_spot:flatten_info(land_encounter_state, self.zones[i].name)
        end
    end
    return land_encounter_state
end



--=======================
--- Constructors
--=======================
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