-- derpy_chd_aeromachines
local caps = {
    -- Chaos Dwarfs
    {"derpy_chd_gyro_05_rocket", "special", 2},
    {"derpy_chd_gyro_01_cannon", "special", 2},
    {"derpy_chd_gyro_02_multi_cannon", "special", 2},
    {"derpy_chd_gyro_03_flame", "special", 2},
    {"derpy_chd_gyro_04_bomber", "special", 2}
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end