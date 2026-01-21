local Spot = require("script/land_encounters/models/spots/abstract_classes/spot")

-------------------------
--- Properties definition
-------------------------
local SmithySpot = {
    -- logic properties
    index = 0,
    coordinates = {0, 0},
    -- marker properties
    -- they are fixed
    marker_id = ""
}

-------------------------
--- Class Methods
-------------------------
-- Overriden Methods
function SmithySpot:get_class()
    return "SmithySpot"
end

function SmithySpot:activate(zone_name)    
    local marker_id = "land_enc_marker_" .. zone_name .. "_smithy_" .. self.index
    local marker_key = "encounter_marker_smithy"
    local interaction_radius = 8
    self:set_marker_on_map(marker_id, marker_key, interaction_radius)
end

function SmithySpot:flatten_info(state_info, zone_name)
    local flattened_key = zone_name .. "_smithy_" .. tostring(self.index)
    state_info[flattened_key .. "_type"] = self:get_class()
    state_info[flattened_key .. "_coordinates"] = self.coordinates
    state_info[flattened_key .. "_marker"] = self.marker_id
end

function SmithySpot:reinstate(flattened_key, previous_state)
    self.coordinates = previous_state[flattened_key .. "_coordinates"] 
    self.marker_id = previous_state[flattened_key .. "_marker"]
end

-------------------------
--- Constructors
-------------------------
function SmithySpot:new_from_coordinates(old_spot, index, initial_owning_faction)   
    SmithySpot.__index = SmithySpot
    setmetatable(SmithySpot, {__index = Spot})
    local t = old_spot
    -- initalize variables related only to smithy spot
    setmetatable(t, SmithySpot)
    return t
end
                            
return SmithySpot