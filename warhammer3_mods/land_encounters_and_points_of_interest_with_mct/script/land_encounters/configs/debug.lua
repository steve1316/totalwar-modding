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
--- Level every Smithy's garrison fights at when a lord tries to seize it, instead of the forge's own, e.g. { 1 } for an easy fight.
M.smithy_fight_level = {}
--- Offers a Smith's Commission on every round to each player faction that holds none, instead of every MCT interval, e.g. { true }.
M.smithy_commission_now = {}
--- Commission kind every Smithy offers instead of a random one, e.g. { "fetch_star_metal" }.
M.smithy_commission_kind = {}
--- Level every Tavern is set to on load instead of its own, e.g. { 3 }.
M.tavern_level = {}
--- Contracts every Tavern board posts when it is next rolled, instead of random ones, e.g. { "marked", "chain" }.
M.tavern_board = {}
--- Puts hazard pay on every bounty and marked contract of a board rolled while it is set, e.g. { true }.
M.tavern_hazard = {}
--- Battle missions every bounty and marked contract of a board rolled while it is set carries as contract terms, the first one, e.g. { "headhunt" }.
M.tavern_contract_mission = {}

--- Spot offer keys drawn first on every treasure site after its signature offer, while they are eligible, e.g. { "send_gifts", "roll_the_bones" }.
M.force_spot_offers = {}

--- Treasure site key every treasure spot opens instead of a random one, e.g. { "witchs_hut" }.
M.force_treasure_site = {}

--- Battle spot event rolls that always hit, e.g. { "before" } for the pre-battle offers.
M.battle_event_rolls = {}

--- Gold every paid site and battle offer costs instead of its own, e.g. { 10000 } to see them unaffordable. Their lines still name their own cost.
M.spot_cost = {}

--- Effect library bundle keys (helper_scripts/generators/leapoi_effect_library.py) put on every army of the human faction at each turn start
--- and on load, for 2 turns, e.g. { "land_enc_effect_lib_ctx_attacking", "land_enc_effect_lib_lore" }.
M.test_bundles = {}

--- Effect library bundle keys put on every LEAPOI enemy army as it spawns: battle spots, tower floors and Tavern contracts, e.g.
--- { "land_enc_effect_lib_onhit_blinded" }.
M.test_bundles_enemy = {}

--- Boon keys (configs/boons.lua) every lord of the human factions gains at level 1 when a game loads, once each, e.g. { "bloodsworn" }.
M.grant_boons = {}

--- Curse keys every lord of the human factions gains at level 1 when a game loads, once each, e.g. { "haunted" }.
M.grant_curses = {}

--- Shows the LEAPOI intro message to every human faction when a game loads, not only on a new campaign's first turn, e.g. { true }.
M.intro_now = {}

--- Battles won that raise a boon a level, instead of the config's, e.g. { 1 }.
M.boon_wins_per_level = {}

--- Turns that make a curse a level worse, instead of the config's, e.g. { 1 }.
M.curse_turns_per_level = {}

return M
