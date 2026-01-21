require("script/land_encounters/utils/logger")
require("script/land_encounters/utils/random")

local Spot = require("script/land_encounters/models/spots/abstract_classes/spot")
local EventSpot = require("script/land_encounters/models/spots/event_spot")

-------------------------
--- Constant values of the class [DO NOT CHANGE]
-------------------------
local SPOT_TURN_ACTIVATION_COOLDOWN = 5
local ERASE_SPOT_FLAG = nil


-------------------------
--- Properties definition
-------------------------
local SpotDelegate = {
    spots = {},

    active_spots = {},
    prohibited_spots = {},
    
    max_active_spots_count = 0
}


function SpotDelegate:can_add_land_encounters()
    return self.max_active_spots_count > #self.active_spots
end

function SpotDelegate:try_add_land_encounters(zone_name)
    local disordered_indexes = randomic_length_shuffle(#self.spots)
    for i= 1, #disordered_indexes do
        -- after every land encounter added we should check that the total count does not surpass 
        -- the total amount of encounters permitted
        if not self:can_add_land_encounters() then
            log("Cannot add more land encounter")
            break
        end
        
        -- check if the current index is not registered as a treasure or battle spot
        local candidate_spot_to_activate_index = disordered_indexes[i]
        if self.prohibited_spots[candidate_spot_to_activate_index] == nil and self.active_spots[candidate_spot_to_activate_index] == nil then
            log("Adding land encounter in " .. zone_name .. "[" .. tostring(candidate_spot_to_activate_index) .. "]")
            self.active_spots[candidate_spot_to_activate_index] = true
            self.spots[candidate_spot_to_activate_index] = EventSpot:newFrom(self.spots[candidate_spot_to_activate_index])
            self.spots[candidate_spot_to_activate_index]:activate(zone_name)
            log("Land encounter was supposedly activated")
        end
    end
end

function SpotDelegate:update_occupied_and_prohibited_spot_states(zone_name)
    self:release_prohibited_spots_if_able()
    self:try_deactivate_spots_due_to_life_expiration(zone_name)
end


function SpotDelegate:release_prohibited_spots_if_able()
    for spot_index, cooldown in pairs(self.prohibited_spots) do
        self.prohibited_spots[spot_index] = cooldown - 1
        if self.prohibited_spots[spot_index] <= 0 then
            self.prohibited_spots[spot_index] = ERASE_SPOT_FLAG
        end 
    end
end


function SpotDelegate:try_deactivate_spots_due_to_life_expiration(zone_name)
    for spot_index, state in pairs(self.active_spots) do
        if self.spots[spot_index]:check_if_active_and_countdown_reached() then
            self.active_spots[spot_index] = nil
            self:deactivate_spot_in_zone(zone_name, spot_index)
        end
    end
end


-- DESTRUCTION RELATED METHODS
function SpotDelegate:deactivate_spot_in_zone(zone_name, spot_index)
    self.prohibited_spots[spot_index] = SPOT_TURN_ACTIVATION_COOLDOWN -- entering cooldown till 0 and can be reselected
    self.active_spots[spot_index] = ERASE_SPOT_FLAG

    self.spots[spot_index]:deactivate(zone_name, spot_index)
end


function SpotDelegate:reinstate_from_previous_state(zone_name, previous_state)
    for i=1, #self.spots do
        local flattened_key = zone_name .. "_" .. tostring(self.spots[i].coordinates[1]) .. "_" .. tostring(self.spots[i].coordinates[2])
        local spot_type = previous_state[flattened_key .. "_type"]
        if spot_type ~= nil then
            if spot_type == "EventSpot" and previous_state[flattened_key .. "_active"] then
                self.spots[i] = EventSpot:newFrom(self.spots[i])
                self.spots[i]:reinstate(previous_state, flattened_key)
            end
            
            self.active_spots[i] = previous_state[flattened_key .. "_active_spot_flag"]
            self.prohibited_spots[i] = previous_state[flattened_key .. "_prohibited_spot_flag"]
        end
    end
end


-------------------------
--- Constructors
-------------------------
function SpotDelegate:new(zone_coordinates, active_spot_percentage)
    local zone_spots = {}
    for i = 1, #zone_coordinates do
        local spot = Spot:new()
        spot:initialize_from_coordinates(i, zone_coordinates[i])
        table.insert(zone_spots, spot)
    end

    local t = { 
        spots = zone_spots, 
        active_spots = {},
        prohibited_spots = {},
        max_active_spots_count = active_spot_percentage * #zone_coordinates
    }
    setmetatable(t, self)
    self.__index = self
    return t
end

return SpotDelegate