require("script/land_encounters/controllers/incident_manager")


local treasure_events = require("script/land_encounters/constants/events/treasure_type_events")

local elligible_items = require("script/land_encounters/constants/items/balancing_items")

-------------------------
--- Properties definition
-------------------------
local TreasureEventDelegate = {}

-------------------------
--- Class Methods
-------------------------

function TreasureEventDelegate:trigger_event(area_and_character_info)
    local character = area_and_character_info:family_member():character()
    local triggering_faction = character:faction()
    local random_event = treasure_events[random_number(#treasure_events)]

    if is_human_and_it_is_its_turn(triggering_faction) then
        trigger_incident_for_character(random_event.incident, random_event.targets, character)
    elseif not triggering_faction:is_human() then
        self:trigger_balancing_benefit_for_ai(character, triggering_faction, random_event)
    end
end

--- @function trigger_balancing_benefit_for_ai
--- @desc [INTERNAL] gives buffs and items to the AI as they cannot experience events directly.
--- @param triggering_ai_character table CA variable. The triggering Ai character. 
--- @param triggering_faction table CA variable. A faction that has triggered this event
--- @param random_event table An event that has 
function TreasureEventDelegate:trigger_balancing_benefit_for_ai(triggering_ai_character, triggering_faction, random_event)
    local trigger_event_feed_for_faction = false
    -- Add a random ancillary to an ai faction
    cm:add_ancillary_to_faction(triggering_faction, elligible_items[random_number(#elligible_items)], trigger_event_feed_for_faction)
    -- Add an amount to a treasury of an ai faction
    cm:treasury_mod(triggering_faction:name(), 4000)
    -- Apply a random buff to the army if abble
    if random_event ~= nil and random_event.effect ~= false and random_event.targets.force and cm:char_is_general_with_army(triggering_ai_character) then
        local militar_force_cqi = triggering_ai_character:military_force():command_queue_index()
        cm:apply_effect_bundle_to_force(random_event.effect, militar_force_cqi, 5)
    end
end


-------------------------
--- Constructors
-------------------------
function TreasureEventDelegate:new()
    local t = { }
    setmetatable(t, self)
    self.__index = self
    return t
end

return TreasureEventDelegate