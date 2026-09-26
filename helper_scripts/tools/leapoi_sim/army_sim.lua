--- Offline LEAPOI army simulator. Loads the mod's real army generator with the game's globals stubbed out and prints rolled armies as JSON lines.
---
--- Usage: lua army_sim.lua <leapoi_root> [faction=all|wef,emp] [difficulty=easy,medium,hard] [count=N] [seed=N] [mods=none|all]
---
--- Output lines, one JSON object each:
---   {"type":"config", "difficulties":{...}}  - each difficulty's settings, including its tiers and min/max unit limits.
---   {"type":"pool", "faction":..., "units":{...}} - every unit the faction can draw from, with each tier, category and origin it is listed under.
---   {"type":"army", "faction":..., "difficulty":..., "lord":..., "heroes":[...], "units":[{"category":..., "land_unit":...}]}

-- //////////////////////////////////////////////////////////////////////////////////////////////////
-- //////////////////////////////////////////////////////////////////////////////////////////////////
-- Setup

--- Folder of this script, so the shared stubs load no matter where Lua is started from.
local SCRIPT_DIR = arg[0]:match("^(.*)[/\\]") or "."
local write_line, options, to_json = dofile(SCRIPT_DIR .. "/game_stubs.lua")(arg, {
    faction = "all", difficulty = "easy,medium,hard", count = "1", seed = tostring(os.time()), mods = "none",
})

require("script/land_encounters/core/managers")
local factions_data = require("script/land_encounters/configs/factions_data")

-- //////////////////////////////////////////////////////////////////////////////////////////////////
-- //////////////////////////////////////////////////////////////////////////////////////////////////
-- Simulation

--- Every faction's unit pool, and every mod origin seen, collected in one pass over the unit data.
local pools, mod_origins = {}, {}
for faction, data in pairs(factions_data) do
    local pool = {}
    for tier_name, tier in pairs(data.units) do
        for category, units in pairs(tier) do
            for _, unit in ipairs(units) do
                pool[unit.land_unit] = pool[unit.land_unit] or {}
                table.insert(pool[unit.land_unit], { tier = tonumber(tier_name:match("%d+")), category = category, origin = unit.origin })
                if unit.origin ~= "vanilla" then mod_origins[unit.origin] = true end
            end
        end
    end
    pools[faction] = pool
end

local settings = get_mct_settings()
if options.mods == "all" then
    --- Enable every mod origin in the unit data, like ticking every mod in MCT.
    settings.enable_compatibility_with_supported_mods = true
    settings.enabled_mods = {}
    for origin in pairs(mod_origins) do settings.enabled_mods[#settings.enabled_mods + 1] = origin end
end

local factions = split_by_regex(options.faction, ",")
if options.faction == "all" then
    factions = {}
    for key in pairs(factions_data) do factions[#factions + 1] = key end
    table.sort(factions)
end

write_line(to_json({ type = "config", difficulties = settings.difficulties }))
for _, faction in ipairs(factions) do
    write_line(to_json({ type = "pool", faction = faction, units = pools[faction] }))
end

math.randomseed(tonumber(options.seed))
for _, faction in ipairs(factions) do
    for _, difficulty in ipairs(split_by_regex(options.difficulty, ",")) do
        for _ = 1, tonumber(options.count) do
            local army = start_force_makeup_generation(difficulty, faction)
            local units = {}
            for category, keys in pairs(army.units) do
                for _, key in ipairs(keys) do units[#units + 1] = { category = category, land_unit = key } end
            end
            local heroes = {}
            for _, hero in ipairs(army.heroes) do heroes[#heroes + 1] = hero.agent_subtype end
            write_line(to_json({
                type = "army",
                faction = faction,
                difficulty = difficulty,
                lord = army.lord and army.lord.agent_subtype or false,
                heroes = heroes,
                units = units,
            }))
        end
    end
end
