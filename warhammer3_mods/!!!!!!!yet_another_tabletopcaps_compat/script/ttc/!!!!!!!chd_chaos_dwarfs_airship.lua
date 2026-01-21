-- chd_chaos_dwarfs_airship
local caps = {
    -- Chaos Dwarfs
    {"wh3_main_cth_veh_sky_junk_0_chd", "special", 2},
    {"wh3_main_cth_veh_sky_junk_0_chd_ror", "special", 3},
    {"wh3_dlc25_dwf_veh_thunderbarge_chd", "rare", 3},
    {"wh3_dlc25_dwf_veh_thunderbarge_chd_ror", "rare", 3},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end