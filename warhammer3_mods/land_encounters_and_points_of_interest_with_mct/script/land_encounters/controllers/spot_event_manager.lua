require("script/land_encounters/utils/random")

local TreasureEventDelegate = require("script/land_encounters/delegates/spots/events/treasure_event_delegate")
local BattleEventDelegate = require("script/land_encounters/delegates/spots/events/battle_event_delegate")

-------------------------
--- Constant values of the class [DO NOT CHANGE]
-------------------------
local CHANCES_OF_BATTLE_EVENT = 90

-------------------------
--- Properties definition
-------------------------

local SpotEventManager = {
    -- Delegates
    treasure_event_delegate = {},
    battle_event_delegate = {},
    -- Physically destroy spot callback
    current_spot_info = {}
}

-------------------------
--- Class Methods
-------------------------

function SpotEventManager:set_current_spot_info(spot_info)
    self.current_spot_info = spot_info
end


function SpotEventManager:trigger_spot_event(area_and_character_info, turn_number)
    if cm:random_number(100) > CHANCES_OF_BATTLE_EVENT then
        self.treasure_event_delegate:trigger_event(area_and_character_info)
        return true
    else
        return self.battle_event_delegate:trigger_pre_battle_dilemma(area_and_character_info, self.current_spot_info, turn_number)
    end
end


function SpotEventManager:trigger_dilemma_event_given_choice(dilemma_choice_and_faction_info)
    self.battle_event_delegate:trigger_dilemma_event_given_choice(dilemma_choice_and_faction_info, self.current_spot_info)
end


function SpotEventManager:export_state_as_a_table()
    return self.battle_event_delegate:export_state_as_a_table(self.current_spot_info)
end

function SpotEventManager:reinstate_event_if_able(previou_state)
    self.battle_event_delegate:reinstate_event_if_able(previou_state)
end

-------------------------
--- Constructors
-------------------------
function SpotEventManager:new(invasion_battle_manager)
    local t = { 
        treasure_event_delegate = TreasureEventDelegate:new(),
        battle_event_delegate = BattleEventDelegate:new(invasion_battle_manager)
    }
    setmetatable(t, self)
    self.__index = self
    return t
end

return SpotEventManager