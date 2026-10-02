--- Manual-testing switches for LEAPOI, kept in one place so an in-game check can be set up again with a one-line edit. Every switch ships
--- off (an empty table). Turn one on for a test, and put it back before committing: a harness test fails while any switch is on.

local M = {}

--- Tower offer keys drawn first on every go-deeper dilemma while they are eligible, e.g. { "blood_price", "veterans_oath" }.
M.force_offers = {}

--- Tower floor number -> difficulty key fought instead of the floor's own, e.g. { [1] = "easy", [2] = "easy", [3] = "easy", [4] = "easy" }.
M.floor_difficulty = {}

--- Enemy gold budget { min, max } for every tower floor instead of its difficulty's range, e.g. { 7000, 10000 }.
M.floor_budget = {}

--- Tower floor number -> sworn units instead of the floor's own, e.g. { [1] = 2, [2] = 2 }.
M.floor_sworn_units = {}

--- Tower floor number -> how many of the delving army's weakest regular units are removed after that floor is won, to free slots for offers
--- that need room, e.g. { [1] = 1, [2] = 1, [3] = 1, [4] = 1 }.
M.floor_kill_units = {}

--- Spot kind every encounter spot becomes instead of rolling the MCT battle chance, either { "battle" } or { "treasure" }.
M.spot_kind = {}

--- Treasure incident keys drawn first on every treasure spot, e.g. { "land_enc_incident_hidden_temple" }.
M.force_treasure_events = {}

--- Battle category keys drawn first on every battle spot while they can fire, e.g. { "bandits" }.
M.force_battle_categories = {}

--- Difficulty key every battle spot uses instead of the current one, e.g. { "hard" }.
M.battle_difficulty = {}

--- Smithy free-pick cooldown in turns instead of the MCT slider and forge level, e.g. { 1 }.
M.smithy_cooldown = {}

--- Forge level every Smithy acts as instead of its own, e.g. { 3 }.
M.smithy_level = {}

return M
