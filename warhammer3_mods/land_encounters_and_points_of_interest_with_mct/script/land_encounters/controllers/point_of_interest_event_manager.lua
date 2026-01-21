local SmithyEventDelegate = require("script/land_encounters/delegates/points_of_interests/events/smithy_event_delegate")

-------------------------
--- Properties definition
-------------------------

local PointOfInterestEventManager = {
    -- Delegates
    smithy_event_delegate = {}
}


function PointOfInterestEventManager:generate_points_of_interests_states(points_of_interest_by_zone)
    for zone_name, coordinates in pairs(points_of_interest_by_zone) do
        self.smithy_event_delegate:generate_states(zone_name, coordinates["smithies"])
    end
end


function PointOfInterestEventManager:update_state_given_turn_passing()
    self.smithy_event_delegate:update_state_given_turn_passing()
end


-------------------------
--- Event Management
-------------------------
function PointOfInterestEventManager:trigger_poi_event(poi_type, area_and_character_info, spot_info)
    if poi_type == "SmithySpot" then
        self.smithy_event_delegate:trigger_event(area_and_character_info, spot_info)
    -- elseif poi_type == ""
    end
end

function PointOfInterestEventManager:trigger_dilemma_event_given_choice(dilemma_choice_and_faction_info, spot_info)
    self.smithy_event_delegate:trigger_dilemma_event_given_choice(dilemma_choice_and_faction_info, spot_info)
end


-- STATE SAVING AND REINSTATION
function PointOfInterestEventManager:export_state_as_table()
    local points_of_interests_data = {}
    points_of_interests_data["smithies"] = self.smithy_event_delegate:export_state_as_table()
    return points_of_interests_data
end


function PointOfInterestEventManager:reinstate_event_if_able(previous_state)
    self.smithy_event_delegate:reinstate_event_if_able(previous_state["smithies"])
end


-------------------------
--- Constructors
-------------------------
function PointOfInterestEventManager:new(mission_manager, invasion_battle_manager)
    local t = { 
        smithy_event_delegate = SmithyEventDelegate:new(mission_manager, invasion_battle_manager)
    }
    setmetatable(t, self)
    self.__index = self
    return t
end

return PointOfInterestEventManager