local Spot = require("script/land_encounters/models/spots/abstract_classes/spot")
local SmithySpot = require("script/land_encounters/models/spots/smithy_spot")
require("script/shared/mct_settings")

-------------------------
--- Properties definition
-------------------------
local PointOfInterestDelegate = {
    points_of_interest = {}, -- Smithy / Resource / Tavern    
}

function PointOfInterestDelegate:initialize(points_of_interest_data)
    if not get_mct_settings().disable_smithies then
        self:initialize_smithies(points_of_interest_data["smithies"])
    end
    self:initialize_taverns(points_of_interest_data["taverns"])
    self:initialize_resources(points_of_interest_data["resources"])
end

function PointOfInterestDelegate:initialize_smithies(smithies_data)
    self.points_of_interest = {}
    -- we get the player faction so that we never give him the smithy or any other poi initially
    local player_faction_name = cm:get_local_faction_name()
    if #smithies_data > 0 then
        for i=1, #smithies_data do
            local spot = Spot:new()
            spot:initialize_from_coordinates(i, smithies_data[i].coordinates)
            
            local initial_owner = ""
            if player_faction_name == smithies_data[i].initial_owner then
                initial_owner = smithies_data[i].owner_if_player
            else
                initial_owner = smithies_data[i].initial_owner
            end
            
            local smithy = SmithySpot:new_from_coordinates(spot, i, initial_owner)
            table.insert(self.points_of_interest, smithy)
        end
    end
end
    

function PointOfInterestDelegate:initialize_taverns(taverns_data)
    if #taverns_data > 0 then
        for i=1, #taverns_data do
            --TODO table.insert(self.points_of_interest, TavernSpot:newFrom(taverns_data[i]))
        end
    end
end


function PointOfInterestDelegate:initialize_resources(resources_data)
    if #resources_data > 0 then
        for i=1, #resources_data do
            --TODO table.insert(self.points_of_interest, ResourceSpot:newFrom(resources_data[i]))
        end
    end
end


function PointOfInterestDelegate:activate_points_of_interest(zone_name)
    for i=1, #self.points_of_interest do
        self.points_of_interest[i]:activate(zone_name)
    end
end


function PointOfInterestDelegate:update_points_of_interest_by_turn(mission_manager)
    for i=1, #self.points_of_interest do
        self.points_of_interest[i]:update_state_through_turn_passing(mission_manager)
    end
end


function PointOfInterestDelegate:reinstate_points_of_interest(zone_name, previous_state)
    local poi_index_triggered = nil
    for i=1, #self.points_of_interest do
        local poi_type = self.points_of_interest[i]:get_class()
        if poi_type == "SmithySpot" then
            local flattened_key = zone_name .. "_smithy_" .. tostring(self.points_of_interest[i].index)            
            -- it could be that we have added a new poi. So we need to check wether if it previously existed.
            local is_battle_triggered = false
            if previous_state[flattened_key .. "_active"] ~= nil then
                is_battle_triggered = self.points_of_interest[i]:reinstate(flattened_key, previous_state)
            end
            -- the battle type is irrelevant as we will delegate to the poi its logic    
            if is_battle_triggered then
                poi_index_triggered = i
            end
        end
    end
    return poi_index_triggered
end

-------------------------
--- Constructors
-------------------------
function PointOfInterestDelegate:new()
    local t = { }
    setmetatable(t, self)
    self.__index = self
    return t
end

return PointOfInterestDelegate