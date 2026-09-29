--- Tower tuning. Each floor record sets the difficulty and army budget of that floor's battle, in delve order.

local M = {}

--- One record per floor. The last floor is the Master of the Tower.
M.floors = {
    { difficulty = "easy", budget_multiplier = 1.0 },
    { difficulty = "medium", budget_multiplier = 1.0 },
    { difficulty = "medium", budget_multiplier = 1.15 },
    { difficulty = "medium", budget_multiplier = 1.3 },
    { difficulty = "hard", budget_multiplier = 1.5 },
}

--- Longest cooldown with its own message (the MCT slider maximum). Longer cooldowns show this message.
M.longest_cooldown_message = 30

return M
