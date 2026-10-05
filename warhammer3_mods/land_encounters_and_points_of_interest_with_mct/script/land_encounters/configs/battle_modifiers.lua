--- Battle modifiers: rare twists rolled onto a fight LEAPOI offers (a battle spot or a tower floor), shown as lines at the top of its dilemma
--- and played in the battle. Pure data. Their text and the effects of their bundles are written by the generator
--- (helper_scripts/generators/leapoi_battle_modifiers.py), keyed the same.

local M = {}

--- Every army in the battle: ours, the enemy and any allies.
local ALL = { "ours", "enemy", "allies" }

--- Offers an army composition keeps out, as they replace the enemy army it describes (a mirror of ours, a hidden floor's other faction).
local COMPOSITION_KEEPS_OUT = { "mirror_curse", "hidden_floor" }

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Rolling

--- MCT setting holding the percent chance a fight rolls modifiers.
M.chance_setting = "battle_modifier_chance"

--- How many modifiers a fight that rolls gets, as { count, weight }.
M.count_weights = { { 1, 80 }, { 2, 15 }, { 3, 5 } }

--- The share of the enemy army's unit slots a lore army fills with its lore units (configs/lore_armies.lua). The spine and the other slots
--- come from the whole roster.
M.lore_share = 0.7

--- What a lore army's gold budget is multiplied by.
M.lore_budget = 1.5

--- A lore army often fills its 20 units before it spends its budget. Each share of the budget it leaves unspent gives its lore units one
--- extra rank, up to `lore_max_ranks`.
M.lore_rank_share = 0.1
M.lore_max_ranks = 4

--- The difficulties a lore army can roll on.
M.lore_difficulties = { medium = true, hard = true }

--- Victory gold change per modifier by its harm: "-" hurts us, "+" helps us, "~" cuts both ways.
M.harm_gold = { ["-"] = 0.25, ["+"] = -0.15, ["~"] = 0 }

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Naming

--- Prefix of each modifier's battle notice name, whose objective and banner rows the generator writes.
M.notice_prefix = "modifier_"

--- Prefix of each modifier bundle. The key and the side follow, e.g. land_enc_effect_spot_modifier_blood_moon_enemy.
M.bundle_prefix = "land_enc_effect_spot_modifier_"

--- Loc key prefix of each modifier's dilemma line.
M.line_prefix = "campaign_localised_strings_string_land_enc_spot_modifier_"

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Modifiers

--[[
Fields of each modifier:
- key: its name, shared with its text and bundles in the generator.
- harm: "-" hurts us, "+" helps us, "~" cuts both ways. See `harm_gold`.
- sides: the armies it hits, any of "ours", "enemy" and "allies". A bundle modifier puts a bundle on each. For a script modifier it only
  describes them, since the battle script picks its own units.
- group: modifiers sharing a group (opposites) never roll together, or nil.
- keeps_out: offer keys (spot and tower) not drawn for the battle, as they would do the same or cancel it out, or nil.
- bundle: true when it is a bundle on each of its sides for the battle, named `bundle_prefix` .. key .. "_" .. side. Without it the
  battle script (script/battle/mod/land_enc_tower_buffs.lua) plays it under its key, and its numbers live there.
- army: for an army composition, the theme the enemy army is built from instead of a random archetype, with the archetype fields of
  configs/archetypes.lua (`shares`, `price_mode`, `requires`, `requires_count`). It only rolls when the enemy faction can field it. A lore
  army's also has `faction` (the only faction it rolls for) and `units` (its lore units), and the record carries its `name` and `effect`.
- hits: its sides as a set, built from `sides`.
--]]
M.list = {
    --- Stat changes.
    { key = "hallowed", harm = "+", sides = { "ours" }, group = "our_leadership", bundle = true },
    { key = "cursed_earth", harm = "-", sides = { "ours" }, group = "our_leadership", bundle = true },
    { key = "blood_moon", harm = "~", sides = ALL, bundle = true },
    { key = "iron_hides", harm = "~", sides = ALL, bundle = true },
    { key = "swift_winds", harm = "~", sides = ALL, group = "speed", bundle = true },
    { key = "heavy_ground", harm = "~", sides = ALL, group = "speed", bundle = true },
    { key = "thunder_charge", harm = "~", sides = ALL, bundle = true },
    { key = "brittle", harm = "+", sides = { "enemy" }, bundle = true },
    { key = "wards", harm = "-", sides = { "enemy" }, bundle = true },
    { key = "gale", harm = "~", sides = ALL, bundle = true },
    { key = "winds_surge", harm = "~", sides = ALL, group = "winds", keeps_out = { "call_the_winds" }, bundle = true },
    { key = "exhausting", harm = "~", sides = ALL, bundle = true },

    --- Abilities granted for the battle.
    { key = "frenzy", harm = "-", sides = { "enemy" }, bundle = true },
    { key = "berserkers", harm = "~", sides = { "ours" }, bundle = true },
    { key = "regen_enemy", harm = "-", sides = { "enemy" }, group = "regeneration", bundle = true },
    { key = "regen_ours", harm = "+", sides = { "ours" }, group = "regeneration", bundle = true },
    { key = "killing_blow", harm = "+", sides = { "ours" }, bundle = true },
    { key = "strength_numbers", harm = "-", sides = { "enemy" }, bundle = true },
    { key = "feasting", harm = "+", sides = { "ours" }, bundle = true },
    { key = "flies", harm = "~", sides = ALL, bundle = true },
    { key = "immolation", harm = "-", sides = { "enemy" }, bundle = true },
    { key = "too_horrible", harm = "-", sides = { "enemy" }, bundle = true },
    { key = "pleasure_pain", harm = "~", sides = ALL, bundle = true },
    { key = "gorefeast", harm = "-", sides = { "enemy" }, bundle = true },
    { key = "unholy_vigour", harm = "+", sides = { "ours" }, bundle = true },

    --- Over time in battle.
    { key = "bleeding_field", harm = "~", sides = ALL, group = "drain" },
    { key = "miasma", harm = "+", sides = { "enemy" }, group = "drain" },
    { key = "rot", harm = "-", sides = { "ours" }, group = "drain" },
    { key = "second_wind", harm = "+", sides = { "ours" }, keeps_out = { "sacred_ground" } },
    { key = "lord_vigil", harm = "+", sides = { "ours" } },
    { key = "short_shot", harm = "~", sides = ALL, group = "ammo", keeps_out = { "quartermasters_cache" } },
    { key = "plenty_shot", harm = "~", sides = ALL, group = "ammo", keeps_out = { "bottomless_quivers" } },

    --- Morale and control.
    { key = "panic", harm = "+", sides = { "enemy" }, keeps_out = { "night_terrors" } },
    { key = "cowards", harm = "-", sides = { "ours" } },
    { key = "duel_lords", harm = "~", sides = ALL, keeps_out = { "divine_shield", "last_ditch_oath" } },
    { key = "hold_fast", harm = "~", sides = ALL, group = "rout_lock", keeps_out = { "oath_of_no_retreat" } },

    --- Attributes switched on for the battle.
    { key = "terror_field", harm = "-", sides = { "enemy" } },
    { key = "grim_resolve", harm = "+", sides = { "ours" }, group = "rout_lock", keeps_out = { "oath_of_no_retreat" } },
    { key = "ambush_country", harm = "~", sides = ALL, group = "sight" },
    { key = "silence_enemy", harm = "+", sides = { "enemy" }, group = "winds", bundle = true },
    { key = "silence_all", harm = "~", sides = ALL, group = "winds", keeps_out = { "call_the_winds" }, bundle = true },
    { key = "mud", harm = "~", sides = ALL, group = "speed" },
    { key = "fire_moving", harm = "+", sides = { "ours" } },
    { key = "strider", harm = "+", sides = { "ours" } },
    { key = "disarmed", harm = "+", sides = { "enemy" }, group = "ammo" },
    { key = "glorious", harm = "+", sides = { "ours" }, bundle = true },
    { key = "expendable", harm = "-", sides = { "enemy" } },
    { key = "tireless_enemy", harm = "-", sides = { "enemy" } },
    { key = "run_amok", harm = "~", sides = ALL },

    --- Over time in battle, continued.
    { key = "grim_presence", harm = "+", sides = { "enemy" } },
    { key = "storm_magic", harm = "~", sides = ALL, group = "winds", keeps_out = { "call_the_winds" } },
    { key = "winds_drained", harm = "+", sides = { "enemy" }, group = "winds" },

    --- Tzeentchian chaos.
    { key = "warp_shift", harm = "~", sides = ALL, group = "teleport" },
    { key = "jest", harm = "~", sides = ALL, group = "teleport" },
    { key = "blink", harm = "+", sides = { "ours" }, group = "teleport" },
    { key = "lost_warp", harm = "-", sides = { "ours" }, group = "teleport" },
    { key = "scatter", harm = "+", sides = { "enemy" }, group = "teleport" },
    { key = "revealed", harm = "~", sides = ALL, group = "sight" },

    --- Free spells, which belong to no army.
    { key = "wild_winds", harm = "~", sides = ALL },

    --- Morale and respawns, continued.
    { key = "enemy_last_stand", harm = "-", sides = { "enemy" }, group = "rout_lock" },
    { key = "dead_rise", harm = "+", sides = { "ours" } },
    { key = "undying", harm = "-", sides = { "enemy" } },

    --- Army compositions.
    { key = "comp_monsters", harm = "-", sides = { "enemy" }, group = "composition", keeps_out = COMPOSITION_KEEPS_OUT,
      army = { shares = { monsters = 65, cavalry = 15, frontline = 20 }, price_mode = "normal", requires = "monsters", requires_count = 3 } },
    { key = "comp_riders", harm = "~", sides = { "enemy" }, group = "composition", keeps_out = COMPOSITION_KEEPS_OUT,
      army = { shares = { cavalry = 80, frontline = 20 }, price_mode = "normal", requires = "cavalry", requires_count = 3 } },
    { key = "comp_shieldwall", harm = "~", sides = { "enemy" }, group = "composition", keeps_out = COMPOSITION_KEEPS_OUT,
      army = { shares = { frontline = 75, missile = 25 }, price_mode = "normal" } },
    { key = "comp_gunline", harm = "~", sides = { "enemy" }, group = "composition", keeps_out = COMPOSITION_KEEPS_OUT,
      army = { shares = { missile = 55, artillery = 30, frontline = 15 }, price_mode = "normal", requires = "missile", requires_count = 3 } },
}

--- The lore armies join the list as army compositions.
for _, lore in ipairs(require("script/land_encounters/configs/lore_armies")) do
    --- With its bigger budget a lore army is always the harder fight, so it pays like any harmful modifier.
    M.list[#M.list + 1] = { key = lore.key, harm = "-", sides = { "enemy" }, group = "composition", keeps_out = COMPOSITION_KEEPS_OUT,
        name = lore.name, effect = lore.effect, army = { faction = lore.faction, shares = lore.shares, units = lore.units, price_mode = "normal" } }
end

--- Each modifier by its key, built from `list`.
M.by_key = {}

for _, modifier in ipairs(M.list) do
    M.by_key[modifier.key] = modifier
    modifier.hits = {}
    for _, side in ipairs(modifier.sides) do modifier.hits[side] = true end
end

return M
