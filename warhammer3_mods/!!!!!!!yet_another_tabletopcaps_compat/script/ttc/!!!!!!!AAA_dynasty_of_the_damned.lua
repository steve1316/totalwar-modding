-- Dynasty of the Damned
local caps = {
    -- Grand Cathay
    {"bm_theak_moloch_monks", "special", 1},
    -- Other
    {"jiang_copsewight", "rare", 2},
    {"jiang_damned_cannon", "rare", 2},
    {"jiang_dracolith", "rare", 3},
    {"jiang_grave_guard_crossbow", "core"},
    {"jiang_grave_guard_crossbow_balefireshaft", "core"},
    {"jiang_grave_guard_halberd", "core"},
    {"jiang_longma_undead", "special", 2},
    {"jiang_necro_mortar", "rare", 1},
    {"jiang_shadow_lantern", "special", 2},
    {"jiang_shuimu", "special", 1},
    -- Vampire Counts
    {"vmp_jiang_veh_war_compass_0", "rare", 2},
    {"wh_dlc02_vmp_cav_blood_knights_0_jiang", "rare", 2},
    {"wh_dlc04_vmp_veh_corpse_cart_0_jiang", "special", 2},
    {"wh_dlc04_vmp_veh_corpse_cart_1_jiang", "special", 2},
    {"wh_dlc04_vmp_veh_corpse_cart_2_jiang", "special", 2},
    {"wh_main_vmp_cav_black_knights_0_jiang", "special", 1},
    {"wh_main_vmp_cav_black_knights_3_jiang", "special", 1},
    {"wh_main_vmp_cav_hexwraiths_jiang", "special", 2},
    {"wh_main_vmp_inf_cairn_wraiths_jiang", "special", 1},
    {"wh_main_vmp_inf_crypt_ghouls_jiang", "core"},
    {"wh_main_vmp_inf_grave_guard_0_jiang", "core"},
    {"wh_main_vmp_inf_grave_guard_1_jiang", "core"},
    {"wh_main_vmp_mon_crypt_horrors_jiang", "special", 2},
    {"wh_main_vmp_veh_black_coach_jiang", "special", 2},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end
