require("script/land_encounters/utils/logger")

local SmithyState = require("script/land_encounters/models/points_of_interest/smithies/smithy_state")

-------------------------
--- Properties definition
-------------------------
local SmithyEventDelegate = {
    smithies_state = {},
    -- Mission delegate
    smithy_mission_delegate = {},
    -- CA Managers
    mission_manager = {},
    -- Delegates
    invasion_battle_manager = {}
}

-------------------------------------
--- Generation and automatic updates
-------------------------------------

function SmithyEventDelegate:generate_states(zone_name, smithies_initial_state)
    local player_faction_name = cm:get_local_faction_name()
    
    for i = 1, #smithies_initial_state do
        local smithy_state = SmithyState:new(zone_name, i, smithies_initial_state[i].coordinates)

        if player_faction_name == smithies_initial_state[i].initial_owner then
            smithy_state:set_controlling_faction(smithies_initial_state[i].owner_if_player)
        else
            smithy_state:set_controlling_faction(smithies_initial_state[i].initial_owner)
        end

        table.insert(self.smithies_state, smithy_state)
    end
end


function SmithyEventDelegate:update_state_given_turn_passing()
    for i=1, #self.smithies_state do
        self.smithies_state[i]:update_state_given_turn_passing(self.mission_manager)
    end 
end

-------------------------------------
--- Event Management
-------------------------------------

function SmithyEventDelegate:trigger_event(area_and_character_info, spot_info)
    for i=1, #self.smithies_state do
        if self.smithies_state[i].zone_name == spot_info.zone.name and self.smithies_state[i].index_in_zone == spot_info.spot_index then
            self.smithies_state[i]:trigger_event(area_and_character_info, self.invasion_battle_manager)
            break
        end
    end
end

function SmithyEventDelegate:trigger_dilemma_event_given_choice(dilemma_choice_and_faction_info, spot_info)
    for i=1, #self.smithies_state do
        if self.smithies_state[i].zone_name == spot_info.zone.name and self.smithies_state[i].index_in_zone == spot_info.spot_index then
            self.smithies_state[i]:trigger_dilemma_event_given_choice(dilemma_choice_and_faction_info, self.invasion_battle_manager)
            break
        end
    end
end


-------------------------
--- Memory Management
-------------------------

function SmithyEventDelegate:export_state_as_table()
    local smithies_data = {}
    for i = 1, #self.smithies_state do
        table.insert(smithies_data, self.smithies_state[i]:export_state_as_table())
    end
    return smithies_data
end

function SmithyEventDelegate:reinstate_event_if_able(previous_state)
    for i = 1, #previous_state do
        self.smithies_state[i] = SmithyState:new("", 0, {})
        local active_poi_spot_index = self.smithies_state[i]:reinstate(previous_state[i])
        if active_poi_spot_index ~= nil then
            local defensive_army = self.smithies_state[i]:get_defensive_army()
            self.invasion_battle_manager:set_auxiliary_army_for_reset(defensive_army)
            self.invasion_battle_manager:mark_battle_forces_for_removal(defensive_army)
            self.invasion_battle_manager:reset_state_post_battle(self.smithies_state[i], "SmithySpot", nil, defensive_army)
        end
    end
end


-------------------------
--- Constructors
-------------------------
function SmithyEventDelegate:new(mission_manager, invasion_battle_manager)
    local t = { 
        mission_manager = mission_manager,
        invasion_battle_manager = invasion_battle_manager 
    }
    setmetatable(t, self)
    self.__index = self
    return t
end

return SmithyEventDelegate