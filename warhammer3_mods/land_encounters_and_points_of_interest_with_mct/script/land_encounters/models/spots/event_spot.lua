local base_spot = require("script/land_encounters/models/spots/abstract_classes/spot")

------------------------------------------------
--- Constant values of the class
------------------------------------------------


-------------------------
--- Properties definition
-------------------------
local EventSpot = {
    -- logic properties
    index = 0,
    coordinates = {0, 0},
    is_active = false,
    automatic_deactivation_countdown = 0, -- Should automatically dissapear after X turn
    -- marker properties
    marker_id = ""
}

-------------------------
--- Class Methods
-------------------------
-- Overriden Methods
function EventSpot:get_class()
    return "EventSpot"
end

function EventSpot:flatten_info(state_info, flattened_key)
    state_info[flattened_key .. "_type"] = self:get_class()
    state_info[flattened_key .. "_coordinates"] = self.coordinates
    state_info[flattened_key .. "_active"] = self.is_active
    state_info[flattened_key .. "_deactivation"] = self.automatic_deactivation_countdown
    state_info[flattened_key .. "_marker"] = self.marker_id
end

function EventSpot:reinstate(state_info, flattened_key)
    self.coordinates = state_info[flattened_key .. "_coordinates"] 
    self.is_active = state_info[flattened_key .. "_active"]
    self.automatic_deactivation_countdown = state_info[flattened_key .. "_deactivation"]
    self.marker_id = state_info[flattened_key .. "_marker"]
end

-------------------------
--- Constructors
-------------------------
-- https://stackoverflow.com/questions/65961478/how-to-mimic-simple-inheritance-with-base-and-child-class-constructors-in-lua-t
function EventSpot:newFrom(old_spot)
    EventSpot.__index = EventSpot
    setmetatable(EventSpot, {__index = base_spot})
    setmetatable(old_spot, EventSpot)
    return old_spot
end

return EventSpot