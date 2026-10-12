-- OvN Lost Factions: Grudgebringers
local caps = {
    -- Grudgebringers
    {"wh_main_emp_inf_handgunners_ovn_gru", "special", 1},
    -- Empire
    {"wh_main_emp_inf_swordsmen_ovn_gru", "core"},
    {"wh_main_emp_inf_halberdiers_ovn_gru", "core"},
    {"wh_dlc04_emp_inf_flagellants_0_ovn_gru", "core"},
    {"wh_main_emp_inf_greatswords_ovn_gru", "special", 1},
    {"wh_dlc04_emp_inf_free_company_militia_0_ovn_gru", "core"},
    {"wh_main_emp_inf_crossbowmen_ovn_gru", "core"},
    {"wh_main_emp_cav_pistoliers_1_ovn_gru", "special", 1},
    {"wh_main_emp_cav_empire_knights_ovn_gru", "special", 1},
    {"wh_main_emp_art_mortar_ovn_gru", "special", 2},
    {"wh_main_emp_art_great_cannon_ovn_gru", "special", 2},
    -- Other
    {"black_avangers", "core"},
    {"jurgen_muntz_outlaw_infantry", "core"},
    {"carlsson_guard", "core"},
    {"azguz_bloodfist_dwarf_warriors", "core"},
    {"dargrimm_firebeard_dwarf_warriors", "core"},
    {"elrod_wood_elf_glade_guards", "core"},
    {"boris_von_raukov_4th_nuln_halberdiers", "core"},
    {"flagellants_eusebio_the_bleak", "special", 1},
    {"countess_guard", "special", 1},
    {"grudgebringer_infantry", "special", 1},
    {"dwarf_envoy_dwarf_warriors", "special", 1},
    {"dieter_schaeffer_carroburg_greatswords", "special", 1},
    {"helmgart_bowmen", "core"},
    {"keelers_longbows", "special", 1},
    {"leitdorf_9th_crossbows", "special", 1},
    {"grudgebringer_crossbow", "special", 1},
    {"galed_elf_archers", "special", 1},
    {"stephan_weiss_outlaw_pistoliers", "special", 1},
    {"grudgebringers_wagon", "special", 2},
    {"carlsson_cavalry", "special", 1},
    {"ragnar_wolves", "special", 1},
    {"grudgebringer_cavalry", "special", 2},
    {"knights_of_the_realm_bertrand_le_grande", "special", 2},
    {"reiksguard_knights_todbringer", "special", 2},
    {"vannheim_75th", "special", 2},
    {"grail_knights_tristan_de_la_tourtristan_de_la_tour", "rare", 2},
    {"uter_blomkwist_imperial_mortar", "special", 2},
    {"imperial_cannon_darius_flugenheim", "rare", 2},
    {"grudgebringer_cannon", "rare", 2},
    {"emperors_hellblaster_volley_gun", "rare", 2},
    {"urblab_rotgut_mercenary_ogres", "special", 2},
    {"treeman_gnarl_fist", "rare", 3},
    {"treeman_knarlroot", "rare", 3},
    {"ragnar_wolves_upgrade", "special", 2},
    -- Dwarfs
    {"wh_main_dwf_inf_dwarf_warrior_0_ovn_gru", "core"},
    {"wh_main_dwf_inf_dwarf_warrior_1_ovn_gru", "core"},
    {"wh_main_dwf_inf_slayers_ovn_gru", "special", 1},
    -- Ogre Kingdoms
    {"wh3_main_ogr_inf_maneaters_0_ovn_gru", "special", 2},
    {"wh3_main_ogr_inf_maneaters_1_ovn_gru", "special", 2},
    {"wh3_main_ogr_inf_maneaters_2_ovn_gru", "special", 2},
    {"wh3_main_ogr_inf_maneaters_3_ovn_gru", "special", 2},
    {"wh3_main_ogr_inf_ogres_0_ovn_gru", "core"},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end