-- derpy_ksl_tanks
local caps = {
    -- Kislev
    {"derpy_ksl_warshed_cannon", "rare", 2},
    {"derpy_ksl_warshed_infantry", "rare", 2},
    {"derpy_ksl_strelezka", "rare", 3},
    {"derpy_ksl_frostfathers_judgement_ror", "rare", 3},
    {"derpy_ksl_vorpalov", "rare", 3},
    {"derpy_ksl_tzargrad", "rare", 3}
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end