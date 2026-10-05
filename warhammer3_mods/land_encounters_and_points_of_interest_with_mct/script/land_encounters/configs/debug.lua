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

--- Battle category keys drawn first on every battle spot while they can fire, e.g. { "bandits" }.
M.force_battle_categories = {}

--- Battle modifier keys (configs/battle_modifiers.lua) every fight carries instead of rolling its own, e.g. { "blood_moon" }.
M.force_battle_modifiers = {}

--- Faction shorthand every battle spot's enemy is instead of its own, e.g. { "brt" } for an army with plenty of cavalry.
M.force_battle_faction = {}

--- Difficulty key every battle spot uses instead of the current one, e.g. { "hard" }.
M.battle_difficulty = {}

--- Smithy free-pick cooldown in turns instead of the MCT slider and forge level, e.g. { 1 }.
M.smithy_cooldown = {}

--- Forge level every Smithy acts as instead of its own, e.g. { 3 }.
M.smithy_level = {}

--- Spot offer keys drawn first on every treasure site after its signature offer, while they are eligible, e.g. { "send_gifts", "roll_the_bones" }.
M.force_spot_offers = {}

--- Treasure site key every treasure spot opens instead of a random one, e.g. { "witchs_hut" }.
M.force_treasure_site = {}

--- Battle spot event rolls that always hit, e.g. { "before" } for the pre-battle offers.
M.battle_event_rolls = {}

--- Gold every paid site and battle offer costs instead of its own, e.g. { 10000 } to see them unaffordable. Their lines still name their own cost.
M.spot_cost = {}

--- Allied-army test battle every battle spot starts instead of its dilemma, with results in the script log, e.g. { "relief_column" }.
--- "side_by_side": we attack, and the allied army spawned beside us is not called onto the field early, to see whether it deploys with us or
--- marches in from the map edge. "relief_column": the allied army attacks the enemy while our lord stands a few hexes off, to see whether we
--- get the battle and where each army starts. Both start the ally at 50% strength with War Rites on it, to see whether ally changes carry over.
--- "relief_column_bundle": the relief column with a reinforcement-time bundle (-100%) on the ally instead of the scripted arrival call.
--- "side_by_side_bundle": side by side with the same bundle on our army, so the ally arrives at once without the scripted call.
--- "ambush_ally": the enemy ambushes us with the allied escort beside us and the same bundle on our army, to see whether an ally joins a
--- battle we defend.
--- Listed modes take turns, one per battle spot entered. The turns start over each time the game loads.
M.ally_test = {}

return M
