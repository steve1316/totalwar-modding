-- shun_cth_unitpack
local caps = {
    -- Grand Cathay
    {"shun_jade_warriors_ror", "core", 1},
    {"shun_art_grand_cannon_0", "special", 2},
    {"shun_jade_lancers_ror", "special", 1},
    {"shun_veh_sky_junk_moonfire_ror", "special", 3},
    {"cth_samurai_shun", "core", 1},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end