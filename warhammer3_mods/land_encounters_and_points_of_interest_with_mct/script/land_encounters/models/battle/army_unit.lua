require("script/land_encounters/utils/random")

-------------------------
--- Properties definition
-------------------------
local ArmyUnit = {
    id = "none",
    quantity = 0,
    chance = 0,
    alternative_chance = 0,
    alternative_id = nil
}


-------------------------
--- Class Methods
-------------------------
function ArmyUnit:generate_winner_unit()
    if self.chance >= random_number(100) then
        return { id = self.id, count = self.quantity }
    elseif self.alternative_chance >= random_number(100) then
        return { id = self.alternative_id, count = self.quantity }
    end
    return nil
end

-------------------------
--- Constructors
-------------------------
function ArmyUnit:newFrom(unit_data)
    local t = { 
        id= unit_data[1], 
        quantity= unit_data[2], 
        chance= unit_data[3], 
        alternative_chance= unit_data[4], 
        alternative_id= unit_data[5] 
    }    
    setmetatable(t, self)
    self.__index = self
    return t
end

return ArmyUnit