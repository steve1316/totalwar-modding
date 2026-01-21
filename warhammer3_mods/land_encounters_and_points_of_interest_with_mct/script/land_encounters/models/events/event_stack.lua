require("script/land_encounters/utils/random")

local EventStack = {
    -- the level of the event being hold here
    level = 0,
    -- disordered event identifiers of this level
    randomized_event_identifiers = {}
}

--- @function initialize_by_randomizing_events_of_level
--- @description gives a level and disorder the events given the number of events that this event level has
--- @param event_level number the event level 
--- @param number_of_events number the amount of events that this event_level has determines the randomic number order 
function EventStack:set_level_and_randomize_events(event_level, number_of_events)
    self.level = event_level
    self.randomized_event_identifiers = randomic_length_shuffle(number_of_events)
end

--- @function pop_event
--- @description Gets the first event from the event stack removing it from the top 
--- @return number event_id an event id or nil if the stack is empty
function EventStack:pop_event()
    return table.remove(self.randomized_event_identifiers, 1)
end


-------------------------
--- Memory management
-------------------------
function EventStack:export_state_as_a_table()
    local event_stack_data = {}
    event_stack_data["level"] = self.level
    event_stack_data["randomized_event_identifiers"] = self.randomized_event_identifiers
    return event_stack_data
end
    
function EventStack:reinstate_if_able(previous_state)
    self.level = previous_state["level"]
    self.randomized_event_identifiers = previous_state["randomized_event_identifiers"]
end

-------------------------
--- Constructors
-------------------------

--- @function new
--- @description creates a new empty stack of level 0 
--- @return table EventStack an object of type stack
function EventStack:new()
    local t = { level = 0, randomized_event_identifiers = {} }
    setmetatable(t, self)
    self.__index = self
    return t
end

return EventStack