require("script/land_encounters/utils/logger")
require("script/land_encounters/utils/random")

-------------------------
--- Constant values of the class [DO NOT CHANGE]
-------------------------
local AUTOMATIC_DEACTIVATION_COOLDOWN = 10

-------------------------
--- Properties definition
-------------------------
local Spot = {
    -- logic properties
    index = 0, -- its almost hardcoded given that 
    coordinates = {0, 0},
    is_active = false,
    automatic_deactivation_countdown = 0, -- Should automatically dissapear after X turn
    -- marker properties
    marker_id = ""
}

-------------------------
--- Class Methods
-------------------------
function Spot:get_class()
    return "Spot. You shouldn't be using this class but it's children!"
end

function Spot:initialize_from_coordinates(index, lat_lng)
    self.index = index
    self.coordinates = lat_lng
    self.is_active = false
    self.automatic_deactivation_countdown = 0
end

function Spot:activate(zone_name)
    self:set_logical_data()

    local mct_settings = get_mct_settings()
    local marker_id = "land_enc_marker_" .. zone_name .. "_" .. self.index
    local available_skins = {}
    for i = 33, 44 do
        if mct_settings.enable_all_encounter_skins or table.contains(mct_settings.enabled_encounter_skin_ids, i) then
            table.insert(available_skins, i)
        end
    end

    local marker_number
    if #available_skins == 0 then
        marker_number = 42
    else
        local random_index = random_number(#available_skins, 1)
        marker_number = available_skins[random_index]
    end

    local marker_key = "encounter_marker_"..tostring(marker_number)
    local interaction_radius = 4
    self:set_marker_on_map(marker_id, marker_key, interaction_radius)
end

function Spot:flatten_info(state_info, flattened_key)
    state_info[flattened_key .. "_type"] = self:get_class()
    state_info[flattened_key .. "_marker"] = self.marker_id
    state_info[flattened_key .. "_coordinates"] = self.coordinates
    state_info[flattened_key .. "_deactivation"] = self.automatic_deactivation_countdown
    state_info[flattened_key .. "_active"] = self.is_active
end

function Spot:reinstate(state_info, flattened_key)
    self.marker_id = state_info[flattened_key .. "_marker"]
    self.coordinates = state_info[flattened_key .. "_coordinates"] 
    self.automatic_deactivation_countdown = state_info[flattened_key .. "_deactivation"]
end

function Spot:set_logical_data()
    self.is_active = true
    self.automatic_deactivation_countdown = AUTOMATIC_DEACTIVATION_COOLDOWN
end

function Spot:set_marker_on_map(marker_id, marker_key, interaction_radius)
    self.marker_id = marker_id
    -- from campaign_interactable_marker_infos table
    -- there are 12 possible skins for the markers. From number 33 to 44 up
    local radius = interaction_radius
    local faction_key = "" -- anyone can activate the marker
    local subculture_key = "" -- anyone can activate the marker
    cm:add_interactable_campaign_marker(self.marker_id, marker_key, self.coordinates[1], self.coordinates[2], radius, faction_key, subculture_key)
    log("Added landmark marker_id=" .. tostring(self.marker_id) .. ", marker_key=" .. tostring(marker_key) .. ", coordinates_x=" .. tostring(self.coordinates[1]) .. ", coordinates_y=" .. tostring(self.coordinates[2]) .. ", radius=" .. tostring(radius) .. ".")
end

function Spot:check_if_active_and_countdown_reached()
    if self.is_active == true and self.automatic_deactivation_countdown == 0 then
        return true
    elseif self.is_active == true then
        self.automatic_deactivation_countdown = self.automatic_deactivation_countdown - 1        
    end
    return false
end

function Spot:deactivate(zone_name, spot_index)
    if self.marker_id == "" then
        self.marker_id = "land_enc_marker_" .. zone_name .. "_" .. spot_index
    end
    cm:remove_interactable_campaign_marker(self.marker_id)

    self.is_active = false
    self.automatic_deactivation_countdown = 0
    self.marker_id = ""
end

-------------------------
--- Constructors
-------------------------
function Spot:new()
    local t = { index = 0, coordinates = {0, 0}, is_active = false, automatic_deactivation_countdown = 0, marker_id = "", event = nil }
    setmetatable(t, self)
    self.__index = self
    return t
end

return Spot