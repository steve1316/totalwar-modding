--- Tower tuning. Each floor record sets that floor's battle and what winning it adds to the haul, in delve order.

local M = {}

--- Enemy army gold per difficulty. Floors are fought back to back with no way to heal, so these sit below the regular encounter ranges and
--- replace them (and any MCT change to them) for tower armies.
M.budget_by_difficulty = {
    easy = { 4000, 6000 },
    medium = { 7000, 12000 },
    hard = { 18000, 25000 },
}

--- One record per floor. The last floor is the Master of the Tower. `difficulty` picks the floor army's budget, lord level and experience.
--- `gold` is the base gold before the performance multiplier. `item_rarities` and `item_count` pick items from CA's pool, and `legendary_count`
--- picks legendary items instead (each one that cannot be found becomes a rare). `sworn_units` is how many of the floor army's units join.
M.floors = {
    { difficulty = "easy", gold = 1000, item_rarities = { "common" }, item_count = 2, sworn_units = 0 },
    { difficulty = "medium", gold = 2000, item_rarities = { "uncommon", "rare" }, item_count = 2, sworn_units = 0 },
    { difficulty = "medium", gold = 2000, item_rarities = { "uncommon", "rare" }, item_count = 2, sworn_units = 2 },
    { difficulty = "medium", gold = 2000, item_rarities = { "uncommon", "rare" }, item_count = 2, sworn_units = 2 },
    { difficulty = "hard", gold = 5000, legendary_count = 3, sworn_units = 2 },
}

--- Gold multiplier by the share of the delving army's strength lost on the floor, checked in order. `max_loss` is in strength points (0-100).
M.performance = {
    { max_loss = 10, multiplier = 1.5 },
    { max_loss = 25, multiplier = 1.25 },
    { max_loss = 50, multiplier = 1.0 },
    { max_loss = 100, multiplier = 0.75 },
}

--- Floor gold is rounded to a multiple of this.
M.gold_step = 50

--- Rarity that stands in for a legendary item the pool cannot supply.
M.legendary_fallback_rarity = "rare"

--- Gold paid for each sworn unit that does not fit in the delving army.
M.unit_overflow_gold = 500

--- Longest cooldown with its own message (the MCT slider maximum). Longer cooldowns show this message.
M.longest_cooldown_message = 30

return M
