--- Offline LEAPOI encounter spawn simulator. Builds every zone of a campaign from the mod's real spot code and fills it like a new campaign does.
---
--- Usage: lua spawn_sim.lua <leapoi_root> [campaign=immortal_empires] [percentage=0.1,0.75] [seed=N]
---
--- Output: one JSON line per percentage and zone: {"percentage":..., "zone":..., "spots":..., "active":...}

--- Folder of this script, so the shared stubs load no matter where Lua is started from.
local SCRIPT_DIR = arg[0]:match("^(.*)[/\\]") or "."
local write_line, options, to_json = dofile(SCRIPT_DIR .. "/game_stubs.lua")(arg, { campaign = "immortal_empires", percentage = "0.1,0.75", seed = "1" })

local Zone = require("script/land_encounters/core/spot").Zone
local coordinates_by_zone = require("script/land_encounters/configs/coordinates")[options.campaign].treasures_and_spots

local zone_names = {}
for name in pairs(coordinates_by_zone) do zone_names[#zone_names + 1] = name end
table.sort(zone_names)

math.randomseed(tonumber(options.seed))
for _, percentage in ipairs(split_by_regex(options.percentage, ",")) do
    for _, name in ipairs(zone_names) do
        local zone = Zone:new(name, coordinates_by_zone[name], tonumber(percentage))
        zone:try_add_land_encounters()
        write_line(to_json({
            percentage = tonumber(percentage),
            zone = name,
            spots = #coordinates_by_zone[name],
            active = Count_keys(zone.spot_delegate.active_spots),
        }))
    end
end
