require("script.land_encounters.algorithms.spillover_balancer_algorithm")

local battle_events_by_level = require("script/land_encounters/constants/events/battle_spot_events")

local event_stack = require("script/land_encounters/models/events/event_stack")

local LEVEL_KEY = 2

local BattleGenerator = {
    event_stacks = {}
}

--- @function get_randomized_event_given_turn_number
--- @description always return an event given a turn number
--- @return table BattleGenerator an object of type BattleOrTreasureGenerator 
function BattleGenerator:get_randomized_event_given_turn_number(turn_number)
    local event = self:try_get_randomized_event_given_turn_number(turn_number)
    
    if next(event) == nil then
        self:reset_stacks()
        event = self:try_get_randomized_event_given_turn_number(turn_number)
    end

    return battle_events_by_level[event.current_level][event.event_of_level]
end

--- @function try_get_randomized_event_given_turn_number
--- @description finds an event following the result of an spillover algorithm, that favors low level events first until a turn where all events have the same chance to happen 
--- @param turn_number number the current turn number in the user game
--- @return table Event or empty table if no valid event could be found
function BattleGenerator:try_get_randomized_event_given_turn_number(turn_number) 
    -- Using the spillover_balancer algorithm check the chances of every event happening
    -- The levels are ordered in chances of happening like: [5, 3, 2, 1]
    local ordered_levels_by_chances_of_happening = randomize_chances_of_event_happening_considering_spillover_given_turn(#battle_events_by_level, turn_number)

    for prioritized_order = 1, #ordered_levels_by_chances_of_happening do
        local current_chance = ordered_levels_by_chances_of_happening[prioritized_order][1]
        local current_level = ordered_levels_by_chances_of_happening[prioritized_order][LEVEL_KEY]

        local event_of_level = nil
        if current_chance > 0 and next(self.event_stacks) ~= nil then
            event_of_level = self.event_stacks[current_level]:pop_event()            
        end

        if event_of_level ~= nil then
            return { current_level = current_level, event_of_level = event_of_level }
        end
    end

    return {}
end

--- @function reset_stacks
--- @description reset all stacks randomizing all events of every level again. Should only happen when there are no more events in the stacks 
function BattleGenerator:reset_stacks()
    -- As this uses the battle_events_by_level table even if an update happen adding events this
    -- will refresh the events adding the new ones in withouth errors
    for level = 1, #battle_events_by_level do
        local number_of_events_of_level = #(battle_events_by_level[level])
        if self.event_stacks[level] == nil then
            self.event_stacks[level] = event_stack:new()
        end
        self.event_stacks[level]:set_level_and_randomize_events(level, number_of_events_of_level)
    end 
end

-------------------------
--- Memory management
-------------------------

function BattleGenerator:export_state_as_a_table()
    local battle_generator_data = {} 
    for i=1, #self.event_stacks do
        table.insert(battle_generator_data, self.event_stacks[i]:export_state_as_a_table())
    end
    return battle_generator_data
end

function BattleGenerator:reinstate_if_able(previous_state)
    for i=1, #previous_state do 
        local new_event_stack = event_stack:new()
        new_event_stack:reinstate_if_able(previous_state[i])
        table.insert(self.event_stacks, new_event_stack)
    end
end

-------------------------
--- Constructors
-------------------------

--- @function new
--- @description creates a battle or treasure generator manager 
--- @return table BattleGenerator an object of type BattleOrTreasureGenerator 
function BattleGenerator:new()
    local t = { event_stacks = {} }
    setmetatable(t, self)
    self.__index = self
    return t
end

return BattleGenerator