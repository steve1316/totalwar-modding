-- 1a_glf_unit_expansion
local caps = {
    -- Bretonnia
    {"glf_brt_royal_knights_of_the_realm", "special", 2},
    {"glf_brt_sir_dagobert_ror", "special", 2},
    {"glf_brt_errant_brigade_ror", "special", 1},
    {"glf_brt_knights_of_the_realm_walk_great_weapon", "special", 1},
    {"glf_brt_knights_of_the_realm_walk", "special", 1},
    {"glf_brt_herrimault", "core"},
    {"glf_brt_crossbowmen", "core"},
    {"glf_brt_longbowmen", "core"},
    {"glf_brt_bolt_thrower", "rare", 1},
    {"glf_brt_cattle_trebuchet", "rare", 1},
    {"glf_brt_hippogryph_subspecies_knights_ror", "rare", 2},
    {"glf_brt_fastrics_skylance_ror", "special", 2},
    {"glf_brt_knights_of_the_realm_sword", "special", 1},
    -- Skaven
    {"glf_skv_black_arrow_ror", "core", 1},
    {"glf_skv_clanrats_crossbow", "core", 1},
    {"glf_skv_poison_wind_blast", "core"},
    {"glf_skv_handgunners", "core"},
    -- Ogre Kingdoms
    {"glf_ogr_ogres_crossbow", "special", 1},
    -- Slaanesh
    {"glf_sla_seekers_of_slaanesh_archers", "special", 2},
    {"glf_sla_daemonette_archers", "core"},
    {"glf_sla_daemonette_exalted_archers", "special", 2},
    -- Mercenaries
    {"glf_sp_mercenary_dwarf_warrior", "core", 1},
    {"glf_sp_mercenary_handgunners", "core", 1},
    {"glf_sp_war_elephants", "rare", 1},
    {"glf_sp_mercenary_greatswords", "special", 1},
    {"glf_sp_mercenary_crossbowmen", "core", 1},
    {"glf_sp_mercenary_port_guard", "core", 1},
    {"glf_sp_mercenary_rangers", "core", 1},
    {"glf_sp_mercenary_crossbow_cavalry", "special", 1},
    {"glf_sp_black_archers", "special", 1},
    {"glf_sp_mercenary_eshin_maneater", "special", 1},
    {"glf_cth_jade_chariot_crossbow", "special", 1},
    {"glf_sp_mercenary_halberdiers", "core", 1},
    -- Grand Cathay
    {"glf_cth_vermillion_warbirds", "special", 2},
    {"glf_cth_jade_riders_crossbow", "special", 1},
    {"glf_cth_dragon_guard_greatswords", "special", 1},
    {"glf_cth_great_bastion_guard", "core"},
    {"glf_cth_tiger_warriors_axe_and_shield", "core"},
    {"glf_cth_tiger_stalkers_dual_kataras", "special", 1},
    {"glf_cth_jade_warriors_guandao", "core"},
    {"glf_cth_jade_warriors_javelin", "core"},
    {"glf_cth_jade_warriors_spear", "core"},
    {"glf_cth_jade_fire_lancers", "special", 1},
    {"glf_cth_terracotta_sentinel_giant_bow", "rare", 3},
    {"glf_cth_mortar", "special", 2},
    {"glf_cth_western_provinces_blademaster", "special", 2},
    -- Khorne
    {"glf_chs_chosen_mkho_halberds", "special", 2},
    -- Lizardmen
    {"glf_lzd_teeth_of_stotek_ror", "special", 2},
    {"glf_lzd_serpent_riders", "special", 2},
    -- Empire
    {"glf_sp_knights_of_the_raging_bull", "special", 2},
    {"glf_emp_halberdiers_shield", "core"},
    {"glf_emp_reiksguard_walk", "special", 1},
    {"glf_emp_knights_of_the_vengeful_sun_ror", "special", 3},
    -- Chaos Dwarfs
    {"glf_chd_infernal_guard_flamethrower", "special", 2},
    {"glf_chd_infernal_guard_machinegun", "special", 2},
    -- Dark Elves
    {"glf_def_the_iceblades_ror", "special", 1},
    {"glf_def_the_voiceless_ones_ror", "special", 1},
    {"glf_def_the_soulskulls_ror", "special", 1},
    {"glf_def_the_krakensides_ror", "special", 1},
    {"glf_def_black_knights", "special", 1},
    {"glf_def_cold_one_fear_knights_lance", "special", 2},
    {"glf_def_the_ravenspears_ror", "special", 1},
    {"glf_def_dread_knights_ror", "special", 2},
    {"glf_def_shades_handbow", "special", 1},
    {"glf_def_rimeshards_ror", "special", 1},
    {"glf_def_human_slaves", "core"},
    {"glf_def_orc_slaves", "core"},
    {"glf_def_dwarf_slaves", "core"},
    {"glf_def_elf_slaves", "core"},
    -- Dwarfs
    {"glf_dwf_raiders", "core"},
    {"glf_dwf_sniper", "rare", 2},
    {"glf_dwf_machine_gunner", "rare", 2},
    {"glf_dwf_the_zhufbar_firebores_ror", "special", 1},
    -- High Elves
    {"glf_hef_silver_helms_greatsword", "special", 1},
    {"glf_hef_revenants_of_khaine_ror", "special", 1},
    {"glf_hef_spears_of_dabbarloc_ror", "special", 1},
    {"glf_hef_avelorn_reavers", "rare", 1},
    {"glf_hef_white_lion_riders", "special", 2},
    {"glf_hef_the_knights_of_dusk_ror", "special", 2},
    {"glf_hef_griffon", "rare", 1},
    {"glf_hef_caledor_sentinel", "special", 1},
    -- Kislev
    {"glf_ksl_shield_maiden", "special", 2},
    {"glf_ksl_monk_riders", "core"},
    -- Tomb Kings
    {"glf_tmb_nehekhara_killer", "core"},
    {"glf_tmb_nehekhara_scout", "special", 1},
    {"glf_tmb_blessed_arrow_of_ptra_ror", "special", 1},
    {"glf_tmb_ushabti_2handed_axe", "special", 2},
    {"glf_tmb_lion_head_ushabti_ror", "special", 2},
    -- Vampire Counts
    {"glf_vmp_zombie_knights", "core"},
    {"glf_vmp_zombie_halberd", "core"},
    {"glf_vmp_skeleton_archers", "core"},
    {"glf_vmp_zombie_handgunners", "special", 1},
    -- Wood Elves
    {"glf_wef_torgovann_guard", "special", 2},
    {"glf_wef_wildwood_sentry", "special", 1},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end