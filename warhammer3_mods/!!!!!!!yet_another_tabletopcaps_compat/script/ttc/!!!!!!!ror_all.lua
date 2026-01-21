-- ror_all
-- Warning: This mod does not keep the same key name between land_units_tables and main_units_tables db and the keys from the main_units_tables db needs to be used.
local caps = {
    -- Nurgle
    {"nurglings_ror", "special", 1},
    {"forsaken_ror", "special", 1},
    {"plague_ror", "special", 1},
    {"plague_rors", "special", 2},
    {"beasts_ror", "special", 2},
    {"spawns_ror", "rare", 1},
    {"toads_ror", "special", 2},
    {"drones_ror", "rare", 2},
    {"hulk_ror", "rare", 2},
    {"unclean_ror", "rare", 3},
    -- Slaanesh
    {"grn_brutes5", "special", 2},
    -- Tzeentch
    {"wh3_main_pro_tze_inf_forsaken_0_", "special", 1},
    {"wh3_main_pro_tze_mon_flamers_0__", "special", 3},
    {"wh3_main_pro_tze_mon_flamers_0_", "rare", 3},
    {"hulk_rors", "rare", 3},
    -- Grand Cathay
    {"4crane", "special", 2},
    -- Kislev
    {"wh3_main_pro_ksl_inf_tzar_guard_0__", "special", 2},
    {"wh3_main_pro_ksl_inf_ice_guard_ror_1_", "rare", 1},
    {"wh3_main_pro_ksl_inf_ice_guard_ror_0_", "rare", 1},
    {"wh3_main_pro_ksl_cav_horse_raiders_0_", "core"},
    {"wh3_main_pro_ksl_veh_light_war_sled_ror_0_", "special", 2},
    {"wh3_main_pro_ksl_veh_heavy_war_sled_ror_0_", "special", 3},
    {"wh3_main_pro_ksl_cav_gryphon_legion_ror_0_", "special", 2},
    {"wh3_main_pro_ksl_mon_snow_leopard_ror_0_", "rare", 1},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end