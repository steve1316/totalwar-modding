-- derpy_gunpowder_units
local caps = {
    -- Dwarfs
    {"derpy_gp_8mm_turret", "special", 3},
    {"derpy_gp_20mm_turret", "special", 3},
    {"derpy_gp_drakkfire_turret", "special", 3},
    {"derpy_gp_gatling_turret", "special", 3},
    {"derpy_gp_rocket_turret", "rare", 1},
    {"derpy_gp_triplecannon_turret", "rare", 1},
    {"derpy_gp_tankette_tracks", "special", 3},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end