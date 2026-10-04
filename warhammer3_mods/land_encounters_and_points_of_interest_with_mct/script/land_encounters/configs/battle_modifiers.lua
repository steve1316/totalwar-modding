--- Battle modifiers: rare twists rolled onto a fight LEAPOI offers (a battle spot or a tower floor), shown as lines at the top of its dilemma
--- and played in the battle. Pure data. Their text and the effects of their bundles are written by the generator
--- (helper_scripts/generators/leapoi_battle_modifiers.py), keyed the same.

local M = {}

--- Every army in the battle: ours, the enemy and any allies.
local ALL = { "ours", "enemy", "allies" }

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Rolling

--- MCT setting holding the percent chance a fight rolls modifiers.
M.chance_setting = "battle_modifier_chance"

--- How many modifiers a fight that rolls gets, as { count, weight }.
M.count_weights = { { 1, 80 }, { 2, 15 }, { 3, 5 } }

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
- sides: the armies it hits, any of "ours", "enemy" and "allies".
- group: modifiers sharing a group (opposites) never roll together, or nil.
- keeps_out: offer keys (spot and tower) not drawn for the battle, as they would do the same or cancel it out, or nil.
- bundle: true when it is a bundle on each of its sides for the battle, named `bundle_prefix` .. key .. "_" .. side. Without it the
  battle script (script/battle/mod/land_enc_tower_buffs.lua) plays it under its key, and its numbers live there.
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
    { key = "winds_surge", harm = "~", sides = ALL, keeps_out = { "call_the_winds" }, bundle = true },
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
    { key = "hold_fast", harm = "~", sides = ALL, keeps_out = { "oath_of_no_retreat" } },
}

--- Each modifier by its key, built from `list`.
M.by_key = {}

for _, modifier in ipairs(M.list) do
    M.by_key[modifier.key] = modifier
    modifier.hits = {}
    for _, side in ipairs(modifier.sides) do modifier.hits[side] = true end
end

return M
