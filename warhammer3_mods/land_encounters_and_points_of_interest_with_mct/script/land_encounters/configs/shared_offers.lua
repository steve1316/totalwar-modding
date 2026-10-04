--- Numbers shared by the spot offers (configs/spot_offers.lua) and the tower offers (configs/tower_offers.lua): the cost bands every paid
--- offer prices on, and the cost and effect of each offer both features carry under one name, so a mirrored offer can never drift apart.
--- Values per difficulty use utils/steps.lua. A tower offer takes the step of the floor it leads to. Pure data.

local steps = require("script/land_encounters/utils/steps")

--- A value per difficulty.
local S = steps.of

--- A bundle with one version per difficulty.
local tiered = steps.tiered

--- Key prefix of the tower's effect bundles, which the battle script announces by the name after it.
local TOWER_BUNDLE = "land_enc_effect_tower_"

local M = {}

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Cost bands (Easy, Medium, Hard)

M.STANDARD = S(1500, 2000, 2500)
M.STRONG = S(2000, 2500, 3000)
M.PREMIUM = S(2500, 3000, 3500)
M.STRUCTURAL = S(3000, 4000, 5000)
M.UNIQUE = S(2000, 3000, 4000)

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Mirrored offers, by their shared key

--- Battle buffs: a bundle on our army for the next battle.
M.war_rites = { cost = M.STANDARD, bundle = tiered(TOWER_BUNDLE .. "war_rites") }
M.whetstones_and_oil = { cost = M.STANDARD, bundle = tiered(TOWER_BUNDLE .. "whetstones_and_oil") }
M.warding_sigils = { cost = M.STANDARD, bundle = tiered(TOWER_BUNDLE .. "warding_sigils") }
M.iron_resolve = { cost = M.STANDARD, bundle = tiered(TOWER_BUNDLE .. "iron_resolve") }
M.drill_sergeant = { cost = M.STANDARD, bundle = tiered(TOWER_BUNDLE .. "drill_sergeant") }
M.quartermasters_cache = { cost = M.STANDARD, bundle = tiered(TOWER_BUNDLE .. "quartermasters_cache") }
M.call_the_winds = { cost = M.STANDARD, bundle = tiered(TOWER_BUNDLE .. "call_the_winds") }
M.fire_kissed_blades = { cost = 2000, bundle = TOWER_BUNDLE .. "fire_kissed_blades" }
M.tower_artillery = { cost = 1500, bundle = TOWER_BUNDLE .. "tower_artillery" }

--- Sabotage on the enemy army of the next battle.
M.bribe_the_guards = { cost = M.STRONG, budget = S(0.85, 0.75, 0.65) }
M.thin_the_ranks = { cost = M.STRONG, fewer_units = S(2, 3, 4) }
M.poison_the_stores = { cost = M.STRONG, enemy_strength = S(0.85, 0.75, 0.65) }
M.kill_the_captain = { cost = 2000, no_heroes = true }
M.lower_tiers_only = { cost = M.PREMIUM, max_tier = 2 }
M.break_their_spirit = { cost = M.STANDARD, enemy_bundle = tiered(TOWER_BUNDLE .. "break_their_spirit") }
M.curse_their_blades = { cost = M.STANDARD, enemy_bundle = tiered(TOWER_BUNDLE .. "curse_their_blades") }
M.turn_a_traitor = { cost = M.STRONG, tiers = S({ 2, 3 }, { 3, 4 }, { 4, 5 }) }

--- Tricks the battle script plays. A `battle_value` is handed to the battle with the mission targets: Divine shield's seconds.
M.bottomless_quivers = { cost = M.STANDARD }
M.oath_of_no_retreat = { cost = M.STANDARD }
M.divine_shield = { cost = M.STANDARD, battle_value = S(300, 420, 600) }
M.night_terrors = { cost = M.STRONG, targets = S(1, 2, 3) }
M.assassinate = { cost = M.PREMIUM }

--- Allied armies by size: the units in the army, its lord included.
M.allies_in_the_dark_small = { cost = 5000, ally_units = { 7, 9 } }
M.allies_in_the_dark_medium = { cost = 7500, ally_units = { 11, 15 } }
M.allies_in_the_dark_large = { cost = 10000, ally_units = { 17, 20 } }

--- Missions.
M.lords_glory = { battle_value = S(100, 150, 200) }
M.monster_slayer = { roster = { "monster", "monstrous_infantry" } }
M.rout_the_riders = { battle_value = 360, roster = { "melee_cavalry", "missile_cavalry", "chariot", "monstrous_cavalry" } }
M.against_the_odds = { max_units = 14 }
M.untouchable = { battle_value = 0.5, lord_xp = 2000 }
M.spare_the_captain = { gold = S(2500, 3000, 3500) }
M.flawless_victory = { battle_value = 0 }
M.bloodbath_wager = { cost = 1000, battle_value = 0.75, gold = 2000 }

--- Treasure, units and the realm.
M.stoneskin = { cost = M.STANDARD }
M.enchanted_steel = { cost = M.STANDARD }
M.plague_bearer = { gold = S(4000, 5000, 6000), turns = S(5, 6, 7), bundle = TOWER_BUNDLE .. "plague_bearer" }
M.daemons_deal = { unique = S(2, 2, 3), armies = S(1, 1, 2) }
M.salvage_a_war_machine = { cost = M.STANDARD, tiers = S({ 1, 2, 3 }, { 2, 3, 4 }, { 3, 4, 5 }) }
M.conscripts = { count = 2, tiers = { 1, 2 } }
M.regiment_of_renown = { cost = M.STRONG }
M.recruitment_cache = { cost = M.STANDARD, bundle = tiered("land_enc_effect_spot_recruitment_cache"), turns = 5 }
M.tower_dividends = { cost = M.STANDARD, per_turn = S(250, 350, 450), turns = 10 }
M.strip_the_dead = { per_unit = 250 }

return M
