-- derpy_dwf_burloks_patents
local caps = {
    -- Dwarfs
    {"derpy_gyro_gunship_rifle", "special", 2},
    {"derpy_gyro_gunship_shotgun", "special", 2},
    {"derpy_gyro_gunship_cranklow", "special", 2},
    {"derpy_gyro_gunship_crankgun", "special", 2},
    {"derpy_gyro_gunship_rocket", "special", 2},
    {"derpy_gyro_gunship_napalm", "special", 2},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end