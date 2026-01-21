
local PointOfInterestDelegate = require("script/land_encounters/delegates/points_of_interests/physical/point_of_interest_delegate")
local SpotDelegate = require("script/land_encounters/delegates/spots/physical/spot_delegate")

-------------------------
--- Properties definition
-------------------------
local Zone = {
    name = "Unknown",
    point_of_interest_delegate = {},
    spot_delegate = {}
}

-------------------------
--- Class Methods
-------------------------

--
-- EVENT SPOTS (DYNAMIC SPOT)
-- 

function Zone:update_occupied_and_prohibited_spot_states()
    self.spot_delegate:update_occupied_and_prohibited_spot_states(self.name)
end


function Zone:try_add_land_encounters()
    self.spot_delegate:try_add_land_encounters(self.name)
end


function Zone:reinstate_from_previous_state(previous_state)
    self.spot_delegate:reinstate_from_previous_state(self.name, previous_state)
end


-- DESTRUCTION RELATED METHODS
function Zone:deactivate_spot_in_zone(spot_index)
    self.spot_delegate:deactivate_spot_in_zone(self.name, spot_index)
end


--
-- POINTS OF INTEREST (PERMANENT CONTROL SPOT)
-- 
function Zone:initialize_points_of_interest(points_of_interest_data, mctSettings)
    self.point_of_interest_delegate:initialize(points_of_interest_data, mctSettings)
end


function Zone:update_points_of_interest_by_turn(mission_manager)
    self.point_of_interest_delegate:update_points_of_interest_by_turn(mission_manager)
end


function Zone:activate_points_of_interest()
    self.point_of_interest_delegate:activate_points_of_interest(self.name)
end


function Zone:reinstate_points_of_interest(previous_state)
    self.point_of_interest_delegate:reinstate_points_of_interest(self.name, previous_state)
end


-------------------------
--- Constructors
-------------------------
function Zone:new(zone_name, zone_coordinates, active_spot_percentage)
    local t = { 
        name = zone_name, 
        spot_delegate = SpotDelegate:new(zone_coordinates, active_spot_percentage),
        point_of_interest_delegate = PointOfInterestDelegate:new()
    }
    setmetatable(t, self)
    self.__index = self
    return t
end

return Zone