--- Army archetype recipes for the encounter army generator. Pure data - no runtime logic.
--- Each archetype splits the gold budget left after the spine across the five roles by `shares` (percentages).
--- A role the faction has no units for gives its share to the other roles in proportion.

local M = {}

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Roles

--- Maps every factions_data unit-type bucket to the army role it fills.
M.role_by_unit_type = {
    melee_infantry = "frontline",
    monstrous_infantry = "frontline",
    generic = "frontline",
    missile_infantry = "missile",
    melee_cavalry = "cavalry",
    missile_cavalry = "cavalry",
    chariot = "cavalry",
    war_beast = "cavalry",
    monster = "monsters",
    monstrous_cavalry = "monsters",
    warmachine = "artillery",
}

--- Unit types that can fill the ranged / support slot of the spine, in order of preference.
M.spine_support_unit_types = { "missile_infantry", "missile_cavalry", "warmachine" }

--- How many frontline units every army buys before the archetype shares are applied.
M.spine_frontline_count = 2

--- The archetype used when no enabled archetype is eligible for a faction.
M.fallback_archetype = "battle_line"

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Archetypes

--[[
Fields per archetype:
- key: the MCT checkbox suffix and the value stored on the generated army.
- text: the name shown in MCT.
- shares: percentage of the post-spine budget per role.
- price_mode: "normal" skips units far below the target price, "cheap" takes any affordable unit, "elite" only buys units at or above the role's median price.
- requires: a role that must have at least `requires_count` distinct units for the faction to roll this archetype. nil means always eligible.
- preferred_unit_type: optional unit type picked first within its role when affordable.
--]]
M.list = {
    {
        key = "battle_line",
        text = "Battle line",
        shares = { frontline = 40, missile = 25, cavalry = 15, monsters = 10, artillery = 10 },
        price_mode = "normal",
    },
    {
        key = "raiders",
        text = "Raiders",
        shares = { frontline = 15, missile = 20, cavalry = 65 },
        price_mode = "normal",
        requires = "cavalry",
        requires_count = 3,
        preferred_unit_type = "missile_cavalry",
    },
    {
        key = "horde",
        text = "Horde",
        shares = { frontline = 60, missile = 25, monsters = 15 },
        price_mode = "cheap",
    },
    {
        key = "elite",
        text = "Elite guard",
        shares = { frontline = 40, cavalry = 30, monsters = 30 },
        price_mode = "elite",
    },
    {
        key = "monster_hunt",
        text = "Monster hunt",
        shares = { frontline = 25, missile = 15, monsters = 60 },
        price_mode = "normal",
        requires = "monsters",
        requires_count = 3,
    },
    {
        key = "siege",
        text = "Siege train",
        shares = { frontline = 30, missile = 35, artillery = 35 },
        price_mode = "normal",
        requires = "artillery",
        requires_count = 3,
    },
}

--- Archetype records keyed by their `key`, built from `list`.
M.by_key = {}
for _, archetype in ipairs(M.list) do
    M.by_key[archetype.key] = archetype
end

return M
