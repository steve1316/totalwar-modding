-- scm_skaven_clans
local caps = {
    -- Skaven
    {"str_gnaw_giant_rats", "core"},
    {"str_gnaw_savage_slave", "core"},
    {"str_gnaw_wolves", "core"},
    {"str_gnaw_boar_wranglers", "special", 1},
    {"str_gnaw_slave", "core"},
    {"str_gnaw_giant_scorpion", "special", 2},
    {"str_gnaw_rock_lobber", "special", 1},
    {"str_gnaw_manticore", "special", 1},
    {"str_gnaw_clanrat_sword_shield", "core"},
    {"str_gnaw_dagger_flinger", "core"},
    {"str_gnaw_clanrat_spear_shield", "core"},
    {"str_gnaw_orc_slave", "core"},
    {"str_gnaw_spear_chukka", "special", 1},
    {"str_gnaw_slave_sling", "core"},
    {"str_gnaw_wyvern", "special", 2},
    {"str_gnaw_rats", "core"},
    {"str_gnaw_clanrat_sword", "core"},
    {"str_gnaw_clanrat_spear", "core"},
    {"str_gnaw_boar_wranglers_ror", "special", 1},
    {"str_gnaw_goblin_slave", "core"},
    {"str_gnaw_harpooner", "core"},
    {"str_gnaw_slave_spear", "core"},
    {"str_gnaw_scorpions", "special", 2},
    {"str_inq_gnaw_blood_vultures", "core"},
    {"str_ror_burrow_crackers", "core"},
    {"wh2_main_skv_inf_handguns_ror", "special", 2},
    {"liger_skurvy_skv_inf_clanrats_0", "core", 1},
    {"liger_skv_inf_deck_runners", "special", 1},
    {"liger_skv_inf_skavenslavebombers", "core", 1},
    {"wh2_main_skv_art_skurvymortar", "rare", 2},
    {"rhd_land_skv_inf_plague_monk_warpstone_0", "special", 2},
    {"liger_skv_inf_clanrats_bombers", "core", 1},
    {"liger_skv_veh_gyrobomber", "special", 2},
    {"liger_skurvy_skv_inf_clanrat_spearmen_1", "core", 1},
    {"liger_skurvy_skv_inf_clanrat_spearmen_0", "core", 1},
    {"liger_skv_art_helstorm_rocket_battery", "rare", 2},
    {"mcr_skv_veh_skurvy_warpcannon", "rare", 2},
    {"liger_skv_veh_gyrocopter", "special", 2},
    {"liger_skurvy_skv_art_warp_lightning_cannon", "rare", 3},
    {"wh2_main_skv_inf_handguns", "special", 2},
    {"liger_skurvy_skv_inf_clanrats_1", "core", 1},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end