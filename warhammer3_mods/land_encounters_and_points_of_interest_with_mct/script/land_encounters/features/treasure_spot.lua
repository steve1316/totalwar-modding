--- TreasureEventDelegate. Fires the treasure-type incident when a player enters a spot, or grants
--- balancing buffs / loot to AI factions that hit the same spot.

require("script/land_encounters/core/managers")


local treasure_events = require("script/land_encounters/configs/events").treasure_type

local elligible_items = require("script/land_encounters/configs/items").balancing

local TreasureEventDelegate = {}

--- Picks a random treasure incident for the entered spot. Humans see the incident directly,
--- AI factions are funnelled through trigger_balancing_benefit_for_ai (events do not fire for AI).
--- @param area_and_character_info table The AreaEntered context with area_key and family_member.
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

--- Grants buffs and items to an AI faction that hit a treasure spot, since events do not fire for AI.
--- Always gives a random ancillary + 4000 treasury, and applies the random_event's effect bundle if applicable.
--- @param triggering_ai_character character The AI character that entered the spot.
--- @param triggering_faction faction The AI character's faction.
--- @param random_event table The selected treasure event record (incident, targets, effect).
function TreasureEventDelegate:trigger_balancing_benefit_for_ai(triggering_ai_character, triggering_faction, random_event)
    local trigger_event_feed_for_faction = false
    --- Add a random ancillary to an ai faction
    cm:add_ancillary_to_faction(triggering_faction, elligible_items[random_number(#elligible_items)], trigger_event_feed_for_faction)
    --- Add an amount to a treasury of an ai faction
    cm:treasury_mod(triggering_faction:name(), 4000)
    --- Apply a random buff to the army if abble
    if random_event ~= nil and random_event.effect ~= false and random_event.targets.force and cm:char_is_general_with_army(triggering_ai_character) then
        local militar_force_cqi = triggering_ai_character:military_force():command_queue_index()
        cm:apply_effect_bundle_to_force(random_event.effect, militar_force_cqi, 5)
    end
end


--- Constructs an empty TreasureEventDelegate.
--- @returns TreasureEventDelegate A new empty delegate.
function TreasureEventDelegate:new()
    local t = { }
    setmetatable(t, self)
    self.__index = self
    return t
end

return TreasureEventDelegate
