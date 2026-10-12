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
    {"wh3_main_pro_tze_inf_blue_horrors_0_", "special", 1},
    {"wh3_main_pro_tze_inf_pink_horrors_0_", "special", 2},
    {"wh3_main_pro_tze_cav_chaos_knights_0_", "special", 2},
    {"wh3_main_pro_tze_mon_screamers_0_", "special", 1},
    -- Grand Cathay
    {"4crane", "special", 2},
    {"1rocket", "special", 1},
    {"1rocket_", "special", 1},
    {"6jadewarr", "special", 1},
    {"3longma", "special", 2},
    {"2lancers", "special", 2},
    {"8skyjunk", "special", 3},
    {"5dragoncross", "special", 2},
    {"9jadegun", "special", 1},
    {"7terra", "rare", 2},
    -- Kislev
    {"wh3_main_pro_ksl_inf_tzar_guard_0__", "special", 2},
    {"wh3_main_pro_ksl_inf_ice_guard_ror_1_", "rare", 1},
    {"wh3_main_pro_ksl_inf_ice_guard_ror_0_", "rare", 1},
    {"wh3_main_pro_ksl_cav_horse_raiders_0_", "core"},
    {"wh3_main_pro_ksl_veh_light_war_sled_ror_0_", "special", 2},
    {"wh3_main_pro_ksl_veh_heavy_war_sled_ror_0_", "special", 3},
    {"wh3_main_pro_ksl_cav_gryphon_legion_ror_0_", "special", 2},
    {"wh3_main_pro_ksl_mon_snow_leopard_ror_0_", "rare", 1},
    {"wh3_main_pro_ksl_inf_armoured_kossars_0_", "special", 1},
    {"wh3_main_pro_ksl_inf_armoured_kossars_1_", "special", 1},
    {"wh3_main_pro_ksl_inf_tzar_guard_0_", "special", 2},
    {"wh3_main_pro_ksl_cav_winged_lancers_0_", "special", 2},
    {"wh3_main_pro_ksl_cav_war_bear_riders_1_", "special", 3},
    {"wh3_main_pro_ksl_mon_elemental_bear_ror_0_", "rare", 3},
    {"wh3_main_pro_ksl_veh_little_grom_0_", "rare", 2},
    {"wh3_main_pro_ksl_inf_kossars_1_", "special", 1},
    {"wh3_main_pro_ksl_inf_kossars_0_", "special", 1},
    {"wh3_main_pro_ksl_inf_streltsi_0_", "special", 1},
    -- Khorne
    {"wh3_main_pro_kho_inf_bloodletters_0_", "special", 1},
    {"wh3_main_pro_kho_inf_chaos_warriors_0_", "special", 1},
    {"wh3_main_pro_kho_inf_chaos_warhounds_0_", "special", 1},
    {"wh3_main_pro_kho_inf_chaos_furies_0_", "special", 1},
    {"wh3_main_pro_kho_inf_flesh_hounds_of_khorne_0_", "special", 2},
    {"wh3_main_kho_veh_skullcannon_0_", "rare", 2},
    -- Greenskins
    {"grn_brutes1", "special", 1},
    {"grn_brutes2", "special", 2},
    {"grn_brutes3", "special", 1},
    {"grn_brutes4", "special", 3},
    {"grn_brutes7", "special", 2},
    {"grn_brutes6", "special", 2},
    {"grn_brutes3_maneaters", "special", 2},
    {"grn_brutes9_maneaters", "special", 2},
    {"grn_brutes2_ironguts", "special", 2},
    {"grn_brutes2_irongutss", "special", 2},
    {"grn_brutes6_crushers", "special", 3},
    {"grn_brutes5_ironblaster", "rare", 2},
    {"grn_brutes1_gnoblars", "special", 1},
    {"grn_brutes8_leadbelchers", "special", 2},
    {"grn_brutes4_gorgers", "special", 2},
    {"grn_brutes7_giant", "rare", 3},
    -- Daemons of Chaos
    {"3chariot", "rare", 2},
    -- Warriors of Chaos
    {"1blood", "rare", 2},
    {"2lord", "rare", 3},
    {"wh3_main_chs_art_hellcannon_prologue_", "rare", 1},
    -- Tomb Kings
    {"wh2_dlc09_tmb_inf_tomb_guard_1_", "special", 1},
    {"wh2_dlc09_tmb_mon_ushabti_0_", "special", 2},
    {"wh2_dlc09_tmb_mon_heirotitan_0_", "rare", 3},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end