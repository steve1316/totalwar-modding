require("script/land_encounters/constants/utils/common")
-- Defenders by culture and level given the faction that has control of the defensive spot
local smithy_defenders = {
    --WH1
    --Dwarfs
    ["wh_main_sc_dwf_dwarfs"] = {
        identifier = "defender_force",
        invasion_identifier = "defender_invasion",
        intervention_type = ALLIED_REINFORCEMENTS_PERMITTED_TYPE,
        lord = { 
            possible_subtypes = { 
                "wh_dlc06_dwf_cha_runelord"
            },
            level_ranges = { 20, 30 }, 
            possible_forenames = { },
            possible_clan_names = { }, 
            possible_family_names = { }, 
            skills = {
                ["wh_dlc06_dwf_cha_runelord"] = {
                    { name = "wh_main_skill_all_lord_battle_inspiring_presence", level = 1 },
                    { name = "wh2_dlc11_skill_dwf_army_buff_axe_lord", level = 3 },
                    { name = "wh2_dlc11_skill_dwf_army_buff_tactician", level = 3 },
                    { name = "wh2_dlc11_skill_dwf_army_buff_tradition_and_innovation", level = 3 },
                    { name = "wh2_dlc11_skill_dwf_army_buff_fire_and_fury", level = 3 },
                    { name = "wh2_dlc11_skill_dwf_army_buff_grimnirs_heirs", level = 3 },
                    { name = "wh2_dlc11_skill_dwf_army_buff_thunderer", level = 3 },
                    { name = "wh2_dlc11_skill_dwf_army_buff_blessed_by_grungni", level = 1 },
                    { name = "wh2_dlc11_skill_dwf_army_buff_dawi_firepower", level = 1 },
                    { name = "wh2_dlc11_skill_dwf_army_buff_honoured_by_grimnir", level = 1 },
                    { name = "wh2_dlc11_skill_dwf_army_buff_morgrims_favoured", level = 1 },
                    { name = "wh_main_skill_all_lord_battle_stand_your_ground", level = 1 },
                    { name = "wh2_main_skill_innate_all_disciplined", level = 1 },
                    { name = "wh2_dlc17_skill_dwf_runelord_self_rune_of_speed", level = 1 },
                    { name = "wh_dlc06_skill_dwf_runesmith_self_master_rune_of_wrath_&_ruin", level = 1 },
                    { name = "wh_dlc06_skill_dwf_runesmith_self_master_rune_of_oath_&_steel", level = 1 },
                    { name = "wh_main_skill_dwf_runesmith_self_damping", level = 1 },
                    { name = "wh2_dlc17_skill_dwf_runelord_self_rune_of_slowness", level = 1 },
                    { name = "wh_main_skill_dwf_runesmith_self_forgefire", level = 1 },
                    { name = "wh2_dlc17_skill_dwf_runelord_self_rune_of_breaking", level = 2 },
                    { name = "wh_dlc06_skill_dwf_runelord_self_master_rune_of_negation", level = 1 },
                    { name = "wh_dlc06_skill_dwf_runelord_self_rune_of_hearth_&_home", level = 1 },
                    { name = "wh2_dlc17_skill_dwf_runesmith_self_wardbreaker", level = 1 },
                    { name = "wh_dlc06_skill_dwf_runesmith_self_strike_the_runes_lord", level = 1 },
                    { name = "wh_dlc06_skill_dwf_runelord_anvil_of_doom", level = 1 },
                    { name = "wh_main_skill_dwf_lord_unique_lord_obdurate", level = 1 },
                    { name = "wh_main_skill_dwf_all_unique_rune_of_grimnir", level = 1 },
                    { name = "wh_dlc06_skill_dwf_runelord_self_ancestral_grudge", level = 1 },
                    { name = "wh2_dlc10_skill_dwf_runesmith_generic_master_of_the_forge", level = 1 },
                    { name = "wh_main_skill_dwf_lord_battle_lord_of_the_deeps", level = 1 },
                    { name = "wh_main_skill_all_lord_battle_brass-lunged", level = 1 },
                    { name = "wh_main_skill_dwf_lord_battle_obstinacy", level = 1 }
                },
            },
            ancillaries = {},
            traits = {}
        },
        armies_by_level = {
            [1] = {
                unit_experience_amount = 2,
                units = {
                    { "wh_main_dwf_inf_longbeards", 4, 100, 0, nil },
                    { "wh_main_dwf_inf_quarrellers_1", 4, 100, 0, nil },
                    { "wh_main_dwf_art_grudge_thrower", 4, 100, 0, nil }
                }
            },
            [2] = {
                unit_experience_amount = 5,
                units = {
                    { "wh_main_dwf_inf_longbeards_1", 4, 100, 0, nil },
                    { "wh_main_dwf_inf_thunderers_0", 8, 100, 0, nil },
                    { "wh_main_dwf_art_cannon", 4, 100, 0, nil }
                }
            },
            [3] = {
                unit_experience_amount = 7,
                units = {
                    { "wh_main_dwf_inf_ironbreakers", 4, 100, 0, nil },
                    { "wh_main_dwf_inf_thunderers_0", 8, 100, 0, nil },
                    { "wh_main_dwf_art_organ_gun", 4, 100, 0, nil },
                    { "wh_main_dwf_veh_gyrocopter_1", 2, 100, 0, nil },
                    { "wh_main_dwf_veh_gyrobomber", 1, 100, 0, nil }
                }
            }
        }
    },
    --Greenskins
    ["wh_main_sc_grn_greenskins"] = {
        identifier = "defender_force",
        invasion_identifier = "defender_invasion",
        intervention_type = ALLIED_REINFORCEMENTS_PERMITTED_TYPE,
        lord = { 
            possible_subtypes = { 
                "wh_main_grn_goblin_great_shaman"
            },
            level_ranges = { 20, 30 }, 
            possible_forenames = { },
            possible_clan_names = { }, 
            possible_family_names = { }, 
            skills = {
                ["wh_main_grn_goblin_great_shaman"] = {
                    { name = "wh2_main_skill_innate_all_fleet_footed", level = 1 },
                    { name = "wh_main_skill_grn_magic_little_waaagh_01_sneaky_stabbin", level = 1 },
                    { name = "wh_main_skill_grn_magic_little_waaagh_03_sneaky_stealin", level = 1 },
                    { name = "wh2_main_skill_grn_magic_little_waaagh_02_vindictive_glare_lord", level = 2 },
                    { name = "wh2_main_skill_grn_magic_little_waaagh_04_itchy_nuisance_lord", level = 1 },
                    { name = "wh2_main_skill_grn_magic_little_waaagh_05_gorkll_fix_it_lord", level = 1 },
                    { name = "wh_main_skill_all_magic_all_06_evasion", level = 1 },
                    { name = "wh_main_skill_all_magic_all_07_earthing", level = 1 },
                    { name = "wh_main_skill_all_magic_all_08_power_drain", level = 1 },
                    { name = "wh2_main_skill_grn_magic_little_waaagh_09_night_shroud_lord", level = 1 },
                    { name = "wh2_main_skill_grn_magic_little_waaagh_10_curse_of_da_bad_moon_lord", level = 2 },
                    { name = "wh_main_skill_all_magic_all_11_arcane_conduit", level = 1 },
                    { name = "wh_main_skill_grn_all_unique_dodgy_geezer", level = 1 },
                    { name = "wh_dlc06_skill_grn_lord_battle_riderz", level = 1 },
                    { name = "wh2_dlc15_skill_grn_lord_battle_goblintide", level = 1 },
                    { name = "wh_main_skill_grn_lord_battle_tunnel_boss", level = 1 },
                    { name = "wh_main_skill_grn_lord_battle_bellower", level = 1 },
                    { name = "wh2_dlc15_skill_grn_dont_even_try_it", level = 1 }
                },
            },
            ancillaries = {},
            traits = {}
        },
        armies_by_level = {
            [1] = {
                unit_experience_amount = 2,
                units = {
                    { "wh_dlc06_grn_inf_nasty_skulkers_0", 4, 100, 0, nil },
                    { "wh_main_grn_inf_goblin_archers", 6, 100, 0, nil },
                    { "wh_main_grn_art_goblin_rock_lobber", 2, 100, 0, nil }
                }
            },
            [2] = {
                unit_experience_amount = 5,
                units = {
                    { "wh_main_grn_inf_orc_big_uns", 4, 100, 0, nil },
                    { "wh_main_grn_inf_night_goblin_fanatics_1", 4, 100, 0, nil },
                    { "wh_main_grn_mon_arachnarok_spider_0", 4, 100, 0, nil },
                    { "wh_main_grn_art_doom_diver_catapult", 3, 100, 0, nil }
                }
            },
            [3] = {
                unit_experience_amount = 7,
                units = {
                    { "wh_main_grn_inf_black_orcs", 8, 100, 0, nil },
                    { "wh_main_grn_mon_arachnarok_spider_0", 8, 100, 0, nil }, --wh2_dlc15_grn_mon_stone_trolls_0 DLC check needed
                    { "wh_main_grn_art_doom_diver_catapult", 3, 100, 0, nil }, --wh2_dlc15_grn_mon_river_trolls_0 DLC check needed
                    --{ "wh_main_grn_mon_arachnarok_spider_0", 5, 100, 0, nil } DLC check needed
                }
            }
        }
    },
    --The Empire
    ["wh_main_sc_emp_empire"] = {
        identifier = "defender_force",
        invasion_identifier = "defender_invasion",
        intervention_type = ALLIED_REINFORCEMENTS_PERMITTED_TYPE,
        lord = { 
            possible_subtypes = { 
                "wh_main_emp_lord"
            },
            level_ranges = { 20, 30 }, 
            possible_forenames = { },
            possible_clan_names = { }, 
            possible_family_names = { }, 
            skills = {
                ["wh_main_emp_lord"] = {
                    { name = "wh2_main_skill_innate_all_disciplined", level = 1 },
                    { name = "wh_main_skill_all_lord_battle_inspiring_presence", level = 1 },
                    { name = "wh2_dlc11_skill_emp_army_buff_emperors_finest", level = 3 },
                    { name = "wh2_dlc11_skill_emp_army_buff_speed_of_horse", level = 3 },
                    { name = "wh2_dlc11_skill_emp_army_buff_pistolkorps", level = 3 },
                    { name = "wh2_dlc11_skill_emp_army_buff_honest_steel", level = 3 },
                    { name = "wh2_dlc11_skill_emp_army_buff_mighty_forge", level = 3 },
                    { name = "wh2_dlc11_skill_emp_army_buff_imperial_gunnery", level = 3 },
                    { name = "wh2_dlc11_skill_emp_army_buff_strength_of_hardship", level = 1 },
                    { name = "wh2_dlc11_skill_emp_army_buff_sharpshooter", level = 1 },
                    { name = "wh2_dlc11_skill_emp_army_buff_taste_for_battle", level = 1 },
                    { name = "wh2_dlc11_skill_emp_army_buff_artillery_master", level = 1 },
                    { name = "wh_main_skill_all_lord_battle_stand_your_ground", level = 1 },
                    { name = "wh_main_skill_all_all_self_hard_to_hit_starter", level = 2 },
                    { name = "wh2_dlc11_skill_all_lord_self_devastating_charge", level = 2 },
                    { name = "wh2_dlc11_skill_all_lord_self_full_plate_armour", level = 2 },
                    { name = "wh2_dlc11_skill_all_lord_self_scarred_veteran", level = 2 },
                    { name = "wh2_dlc11_skill_all_lord_self_deadly_blade", level = 2 },
                    { name = "wh_main_skill_all_all_self_foe-seeker", level = 1 },
                    { name = "wh2_dlc11_skill_all_lord_self_wound-maker", level = 2 },
                    { name = "wh2_dlc11_skill_all_lord_self_blade_master", level = 2 },
                    { name = "wh2_dlc11_skill_all_lord_self_self_indomitable", level = 2 },
                    { name = "wh2_dlc11_skill_all_lord_self_blade_shield", level = 2 },
                    { name = "wh_main_skill_all_all_self_deadly_onslaught", level = 1 },
                    { name = "wh_main_skill_emp_lord_unique_general_imperial_griffon", level = 1 },
                    { name = "wh_main_skill_emp_all_unique_sigmars_ward", level = 1 },
                    { name = "wh_main_skill_all_lord_battle_brass-lunged", level = 1 },
                    { name = "wh_main_skill_emp_lord_battle_hold_the_line", level = 1 }
                },
            },
            ancillaries = {},
            traits = {}
        },
        armies_by_level = {
            [1] = {
                unit_experience_amount = 2,
                units = {
                    { "wh_dlc04_emp_inf_free_company_militia_0", 4, 100, 0, nil },
                    { "wh_main_emp_inf_crossbowmen", 6, 100, 0, nil },
                    { "wh_main_emp_art_mortar", 2, 100, 0, nil }
                }
            },
            [2] = {
                unit_experience_amount = 5,
                units = {
                    { "wh_main_emp_inf_halberdiers", 4, 100, 0, nil },
                    { "wh_main_emp_inf_crossbowmen", 4, 100, 0, nil },
                    { "wh_main_emp_inf_handgunners", 4, 100, 0, nil },
                    { "wh_main_emp_art_helstorm_rocket_battery", 3, 100, 0, nil }
                }
            },
            [3] = {
                unit_experience_amount = 7,
                units = {
                    { "wh_main_emp_inf_greatswords", 6, 100, 0, nil },
                    --{ "wh2_dlc13_emp_inf_huntsmen_0", 4, 100, 0, nil }, DLC check needed
                    { "wh_main_emp_inf_handgunners", 6, 100, 0, nil },
                    { "wh_main_emp_art_helstorm_rocket_battery", 4, 100, 0, nil },
                    { "wh_main_emp_art_helblaster_volley_gun", 3, 100, 0, nil }
                }
            }
        }
    },
    --Vampire Counts
    ["wh_main_sc_vmp_vampire_counts"] = {
        identifier = "defender_force",
        invasion_identifier = "defender_invasion",
        intervention_type = ALLIED_REINFORCEMENTS_PERMITTED_TYPE,
        lord = { 
            possible_subtypes = { 
                "wh2_dlc11_vmp_bloodline_necrarch"
            },
            level_ranges = { 20, 30 }, 
            possible_forenames = { },
            possible_clan_names = { }, 
            possible_family_names = { }, 
            skills = {
                ["wh2_dlc11_vmp_bloodline_necrarch"] = {
                    { name = "wh_main_skill_vmp_lord_battle_aura_of_supremacy", level = 1 },
                    { name = "wh2_dlc11_skill_vmp_bloodline_all_battle_the_unliving_host", level = 3 },
                    { name = "wh2_dlc11_skill_vmp_bloodline_all_battle_call_of_the_night", level = 3 },
                    { name = "wh2_dlc11_skill_vmp_bloodline_all_battle_evil_souls", level = 3 },
                    { name = "wh2_dlc11_skill_vmp_bloodline_all_battle_creatures_of_the_night", level = 3 },
                    { name = "wh2_dlc11_skill_vmp_bloodline_all_battle_waking_dead", level = 3 },
                    { name = "wh2_dlc11_skill_vmp_bloodline_all_battle_carriages_of_death", level = 3 },
                    { name = "wh2_dlc11_skill_vmp_bloodline_all_battle_legions_of_dead", level = 1 },
                    { name = "wh2_dlc11_skill_vmp_bloodline_all_battle_dread_knights", level = 1 },
                    { name = "wh2_dlc11_skill_vmp_bloodline_all_battle_deadly_power", level = 1 },
                    { name = "wh2_dlc11_skill_vmp_bloodline_all_battle_flying_horrors", level = 1 },
                    { name = "wh_main_skill_vmp_lord_battle_undeath_resurgent", level = 1 },
                    { name = "wh2_main_skill_innate_all_disciplined", level = 1 },
                    { name = "wh2_dlc11_skill_vmp_bloodline_necrarch_magic_invocation_of_nehek", level = 2 },
                    { name = "wh2_dlc11_skill_vmp_bloodline_necrarch_magic_curse_of_undeath", level = 1 },
                    { name = "wh2_dlc11_skill_vmp_bloodline_necrarch_magic_spirit_leech", level = 2 },
                    { name = "wh2_dlc11_skill_vmp_bloodline_necrarch_magic_panns_pelt", level = 2 },
                    { name = "wh2_dlc11_skill_vmp_bloodline_necrarch_magic_raise_dead", level = 2 },
                    { name = "wh_main_skill_all_magic_all_06_evasion", level = 1 },
                    { name = "wh_main_skill_all_magic_all_07_earthing", level = 1 },
                    { name = "wh_main_skill_all_magic_all_08_power_drain", level = 1 },
                    { name = "wh2_dlc11_skill_vmp_bloodline_necrarch_magic_curse_of_anraheir", level = 1 },
                    { name = "wh2_dlc11_skill_vmp_bloodline_necrarch_magic_purple_sun", level = 2 },
                    { name = "wh2_dlc11_skill_vmp_bloodline_necrarch_magic_greater_arcane_conduit", level = 1 },
                    { name = "wh_main_skill_vmp_lord_self_the_hunger", level = 1 },
                    { name = "wh_main_skill_vmp_lord_self_beguile", level = 1 },
                    { name = "wh_main_skill_vmp_lord_self_quickblood", level = 1 },
                    { name = "wh_main_skill_vmp_lord_self_curse_of_the_revenant", level = 1 },
                    { name = "wh_main_skill_vmp_lord_self_supernatural_horror", level = 1 },
                    { name = "wh2_dlc11_skill_vmp_bloodline_necrarch_self_dark_protection", level = 1 },
                    { name = "wh2_dlc11_skill_vmp_bloodline_necrarch_unique_cynosure", level = 1 },
                    { name = "wh2_dlc11_skill_vmp_bloodline_necrarch_unique_wild_heart", level = 1 },
                    { name = "wh2_dlc11_skill_vmp_bloodline_necrarch_unique_life_leeching", level = 1 },
                    { name = "wh2_dlc11_skill_vmp_bloodline_necrarch_unique_nehekharas_noble_blood", level = 1 },
                    { name = "wh2_dlc11_skill_vmp_bloodline_necrarch_unique_zombie_dragon", level = 1 },
                    { name = "wh_main_skill_vmp_all_unique_grave_ward", level = 1 },
                    { name = "wh_main_skill_vmp_lord_battle_aura_of_dark_majesty", level = 1 },
                    { name = "wh_main_skill_vmp_lord_battle_dark_pact", level = 1 }
                },
            },
            ancillaries = {},
            traits = {}
        },
        armies_by_level = {
            [1] = {
                unit_experience_amount = 2,
                units = {
                    { "wh_main_vmp_inf_skeleton_warriors_1", 4, 100, 0, nil },
                    { "wh_main_vmp_mon_vargheists", 4, 100, 0, nil },
                    { "wh2_dlc11_vmp_inf_crossbowmen", 4, 100, 0, nil }
                }
            },
            [2] = {
                unit_experience_amount = 5,
                units = {
                    { "wh_main_vmp_inf_grave_guard_0", 6, 100, 0, nil },
                    { "wh_main_vmp_mon_vargheists", 4, 100, 0, nil },
                    { "wh_main_vmp_mon_varghulf", 2, 100, 0, nil },
                    { "wh2_dlc11_vmp_inf_handgunners", 4, 100, 0, nil }
                }
            },
            [3] = {
                unit_experience_amount = 7,
                units = {
                    { "wh_main_vmp_inf_grave_guard_1", 8, 100, 0, nil },
                    { "wh_main_vmp_inf_cairn_wraiths", 3, 100, 0, nil },
                    { "wh2_dlc11_vmp_inf_handgunners", 4, 100, 0, nil },
                    --{ "wh_dlc04_vmp_veh_mortis_engine_0", 1, 100, 0, nil }, DLC check needed
                    { "wh_main_vmp_mon_varghulf", 4, 100, 0, nil }
                }
            }
        }
    },
    --Warriors of Chaos
    ["wh_main_sc_chs_chaos"] = {
        identifier = "defender_force",
        invasion_identifier = "defender_invasion",
        intervention_type = ALLIED_REINFORCEMENTS_PERMITTED_TYPE,
        lord = { 
            possible_subtypes = { 
                "wh_main_chs_lord"
            },
            level_ranges = { 20, 30 }, 
            possible_forenames = { },
            possible_clan_names = { }, 
            possible_family_names = { }, 
            skills = {
                ["wh_main_chs_lord"] = {
                    { name = "wh_main_skill_chs_lord_battle_dominating_presence", level = 1 },
                    { name = "wh2_dlc11_skill_chs_army_buff_chaos_vanguard", level = 3 },
                    { name = "wh2_dlc11_skill_chs_army_buff_savage_bloodlust", level = 3 },
                    { name = "wh3_dlc20_skill_chs_army_buff_warpfire", level = 3 },
                    { name = "wh2_dlc11_skill_chs_army_buff_hammer_to_the_anvil", level = 3 },
                    { name = "wh2_dlc11_skill_chs_army_buff_monstrous_strength", level = 3 },
                    { name = "wh2_dlc11_skill_chs_army_buff_doomfire", level = 3 },
                    { name = "wh2_dlc11_skill_chs_army_buff_legion_of_doom", level = 1 },
                    { name = "wh2_dlc11_skill_chs_army_buff_speed_and_malice", level = 1 },
                    { name = "wh2_dlc11_skill_chs_army_buff_freakish_mutations", level = 1 },
                    { name = "wh2_dlc11_skill_chs_army_buff_guided_by_tzeentch", level = 1 },
                    { name = "wh_main_skill_chs_lord_battle_stand_or_die", level = 1 },
                    { name = "wh3_dlc20_skill_innate_chs_brass_collar", level = 1 },
                    { name = "wh_main_skill_chs_lord_self_eye_of_the_gods", level = 1 },
                    { name = "wh2_dlc11_skill_all_lord_self_devastating_charge", level = 2 },
                    { name = "wh2_dlc11_skill_all_lord_self_thick-skinned", level = 2 },
                    { name = "wh2_dlc11_skill_all_lord_self_hard_to_hit", level = 2 },
                    { name = "wh2_dlc11_skill_all_lord_self_deadly_blade", level =2 },
                    { name = "wh_main_skill_all_all_self_foe-seeker", level = 1 },
                    { name = "wh2_dlc11_skill_all_lord_self_wound-maker", level = 2 },
                    { name = "wh2_dlc11_skill_all_lord_self_scarred_veteran", level = 2 },
                    { name = "wh2_dlc11_skill_all_lord_self_self_indomitable", level = 2 },
                    { name = "wh2_dlc11_skill_all_lord_self_blade_shield", level = 2 },
                    { name = "wh_main_skill_all_all_self_deadly_onslaught", level = 1 },
                    { name = "wh3_dlc20_skill_chs_lord_generic_1", level = 1 },
                    { name = "wh3_dlc20_skill_chs_lord_generic_2", level = 1 },
                    { name = "wh3_dlc20_skill_chs_lord_generic_3", level = 1 },
                    { name = "wh3_dlc20_skill_chs_undivided_unique_1", level = 1 },
                    { name = "wh3_dlc20_skill_chs_undivided_unique_2", level = 1 },
                    { name = "wh3_dlc20_skill_chs_undivided_unique_3", level = 1 },
                    { name = "wh_main_skill_chs_lord_unique_chaos_lord_chaos_dragon", level = 1 },
                    { name = "wh_main_skill_chs_all_unique_aura_of_chaos", level = 1 },
                    { name = "wh_main_skill_chs_lord_battle_hearts_of_iron", level = 1 },
                    { name = "wh_main_skill_chs_lord_battle_voice_of_the_dark_gods", level = 1 }
                },
            },
            ancillaries = {},
            traits = {}
        },
        armies_by_level = {
            [1] = {
                unit_experience_amount = 2,
                units = {
                    { "wh_main_chs_inf_chaos_warriors_0", 4, 100, 0, nil },
                    { "wh_dlc01_chs_inf_chosen_2", 4, 100, 0, nil },
                    { "wh_dlc01_chs_inf_forsaken_0", 2, 100, 0, nil },
                    { "wh_main_chs_art_hellcannon", 2, 100, 0, nil }
                }
            },
            [2] = {
                unit_experience_amount = 5,
                units = {
                    { "wh_dlc01_chs_inf_chosen_2", 5, 100, 0, nil },
                    { "wh_dlc01_chs_inf_forsaken_0", 5, 100, 0, nil },
                    { "wh_dlc06_chs_inf_aspiring_champions_0", 3, 100, 0, nil },
                    { "wh_main_chs_art_hellcannon", 3, 100, 0, nil }
                }
            },
            [3] = {
                unit_experience_amount = 7,
                units = {
                    { "wh_dlc06_chs_inf_aspiring_champions_0", 4, 100, 0, nil },
                    { "wh_dlc01_chs_inf_chosen_2", 6, 100, 0, nil },
                    { "wh_dlc01_chs_mon_dragon_ogre_shaggoth", 6, 100, 0, nil },
                    { "wh_main_chs_art_hellcannon", 3, 100, 0, nil }
                }
            }
        }
    },
    --Beastmen
    ["wh_dlc03_sc_bst_beastmen"] = {
        identifier = "defender_force",
        invasion_identifier = "defender_invasion",
        intervention_type = ALLIED_REINFORCEMENTS_PERMITTED_TYPE,
        lord = { 
            possible_subtypes = { 
                "wh_dlc03_bst_beastlord"
            },
            level_ranges = { 20, 30 }, 
            possible_forenames = { },
            possible_clan_names = { }, 
            possible_family_names = { }, 
            skills = {
                ["wh_dlc03_bst_beastlord"] = {
                    { name = "wh_dlc03_skill_bst_lord_presence_of_morrslieb", level = 1 },
                    { name = "wh2_dlc11_skill_bst_army_buff_fury_of_the_herd", level = 1 },
                    { name = "wh2_dlc11_skill_bst_army_buff_leader_of_the_raucous_host", level = 1 },
                    { name = "wh2_dlc11_skill_bst_army_buff_beastlords_spite", level = 1 },
                    { name = "wh2_dlc11_skill_bst_army_buff_beastlords_lash", level = 1 },
                    { name = "wh_dlc03_skill_bst_lord_blessed_by_evil", level = 1 },
                    { name = "wh2_main_skill_innate_bst_nurgles_foul_stink", level = 1 },
                    { name = "wh2_main_skill_innate_all_tough", level = 1 },
                    { name = "wh_dlc03_skill_bst_all_self_deadly_onslaught", level = 1 },
                    { name = "wh_dlc03_skill_bst_beastlord_unique_razorgor", level = 1 }
                },
            },
            ancillaries = {},
            traits = {}
        },
        armies_by_level = {
            [1] = {
                unit_experience_amount = 2,
                units = {
                    { "wh_dlc03_bst_inf_ungor_spearmen_1", 4, 100, 0, nil },
                    { "wh_dlc03_bst_inf_ungor_raiders_0", 4, 100, 0, nil },
                    { "wh_dlc03_bst_inf_minotaurs_0", 2, 100, 0, nil },
                    { "wh_dlc03_bst_inf_cygor_0", 2, 100, 0, nil }
                }
            },
            [2] = {
                unit_experience_amount = 5,
                units = {
                    { "wh_dlc03_bst_inf_bestigor_herd_0", 4, 100, 0, nil },
                    { "wh_dlc03_bst_inf_ungor_raiders_0", 4, 100, 0, nil },
                    { "wh_dlc03_bst_inf_minotaurs_2", 4, 100, 0, nil },
                    { "wh_dlc03_bst_inf_cygor_0", 4, 100, 0, nil }
                }
            },
            [3] = {
                unit_experience_amount = 7,
                units = {
                    { "wh_dlc03_bst_inf_bestigor_herd_0", 6, 100, 0, nil },
                    { "wh_dlc03_bst_inf_minotaurs_2", 4, 100, 0, nil },
                    { "wh_dlc03_bst_inf_cygor_0", 4, 100, 0, nil },
                    { "wh_dlc03_bst_feral_manticore", 2, 100, 0, nil },
                    { "wh2_dlc17_bst_mon_ghorgon_0", 2, 0, 100, "wh_dlc03_bst_inf_minotaurs_2" }, -- DLC check needed
                    { "wh2_dlc17_bst_mon_jabberslythe_0", 1, 0, 100, "wh_dlc03_bst_feral_manticore" } -- DLC check needed
                }
            }
        }
    },
    --Bretonnia
    ["wh_main_sc_brt_bretonnia"] = {
        identifier = "defender_force",
        invasion_identifier = "defender_invasion",
        intervention_type = ALLIED_REINFORCEMENTS_PERMITTED_TYPE,
        lord = { 
            possible_subtypes = { 
                "wh_main_brt_lord"
            },
            level_ranges = { 20, 30 }, 
            possible_forenames = { },
            possible_clan_names = { }, 
            possible_family_names = { }, 
            skills = {
                ["wh_main_brt_lord"] = {
                    { name = "wh_main_skill_all_lord_battle_inspiring_presence", level = 1 },
                    { name = "wh2_dlc11_skill_brt_army_buff_low_born_militia", level = 1 },
                    { name = "wh2_dlc11_skill_brt_army_buff_proficiency_of_peasants", level = 1 },
                    { name = "wh2_dlc11_skill_brt_army_buff_worshippers_of_the_grail", level = 3 },
                    { name = "wh2_dlc11_skill_brt_army_buff_glorfinials_progeny", level = 3 },
                    { name = "wh2_dlc11_skill_brt_army_buff_guardians_of_the_lady", level = 3 },
                    { name = "wh2_dlc11_skill_brt_army_buff_engines_of_war", level = 3 },
                    { name = "wh2_dlc11_skill_brt_army_buff_the_peasants_duty", level = 1 },
                    { name = "wh2_dlc11_skill_brt_army_buff_protectors_of_the_realm", level = 1 },
                    { name = "wh2_dlc11_skill_brt_army_buff_chivalric_code", level = 1 },
                    { name = "wh2_dlc11_skill_brt_army_buff_guided_by_the_lady", level = 1 },
                    { name = "wh_main_skill_all_lord_battle_stand_your_ground", level = 1 },
                    { name = "wh_main_skill_innate_brt_virtue_impetuous_knight", level = 1 },
                    { name = "wh_main_skill_all_all_self_blade_master_starter", level = 1 },
                    { name = "wh2_dlc11_skill_all_lord_self_devastating_charge", level = 2 },
                    { name = "wh2_dlc11_skill_all_lord_self_full_plate_armour", level = 2 },
                    { name = "wh2_dlc11_skill_all_lord_self_scarred_veteran", level = 2 },
                    { name = "wh2_dlc11_skill_all_lord_self_hard_to_hit", level = 2 },
                    { name = "wh_main_skill_all_all_self_foe-seeker", level = 1 },
                    { name = "wh2_dlc11_skill_all_lord_self_blade_shield", level = 2 },
                    { name = "wh_main_skill_all_all_self_deadly_onslaught", level = 1 },
                    { name = "wh_main_skill_brt_lord_unique_general_hippogryph", level = 1 },
                    { name = "wh_main_skill_brt_all_unique_ladys_mantle", level = 1 },
                    { name = "wh_main_skill_brt_lord_unique_the_blessing_of_the_lady", level = 1 },
                    { name = "wh_main_skill_brt_lord_battle_virtue_of_empathy", level = 1 },
                    { name = "wh_main_skill_brt_lord_battle_lionhearted", level = 1 },
                    { name = "wh_main_skill_brt_lord_battle_basic_training", level = 1 }
                },
            },
            ancillaries = {},
            traits = {}
        },
        armies_by_level = {
            [1] = {
                unit_experience_amount = 2,
                units = {
                    { "wh_dlc07_brt_inf_foot_squires_0", 4, 100, 0, nil },
                    { "wh_dlc07_brt_inf_peasant_bowmen_2", 6, 100, 0, nil },
                    { "wh_main_brt_art_field_trebuchet", 2, 100, 0, nil }
                }
            },
            [2] = {
                unit_experience_amount = 5,
                units = {
                    { "wh_dlc07_brt_inf_foot_squires_0", 4, 100, 0, nil },
                    { "wh_dlc07_brt_cav_questing_knights_0", 4, 100, 0, nil },
                    { "wh_dlc07_brt_inf_peasant_bowmen_2", 6, 100, 0, nil },
                    { "wh_main_brt_art_field_trebuchet", 2, 100, 0, nil },
                    { "wh_dlc07_brt_art_blessed_field_trebuchet_0", 1, 100, 0, nil }
                }
            },
            [3] = {
                unit_experience_amount = 7,
                units = {
                    { "wh_dlc07_brt_cav_grail_guardians_0", 7, 100, 0, nil },
                    { "wh_dlc07_brt_cav_questing_knights_0", 7, 100, 0, nil },
                    { "wh_dlc07_brt_cav_royal_hippogryph_knights_0", 5, 100, 0, nil }
                }
            }
        }
    },
    --Wood Elves
    ["wh_dlc05_sc_wef_wood_elves"] = {
        identifier = "defender_force",
        invasion_identifier = "defender_invasion",
        intervention_type = ALLIED_REINFORCEMENTS_PERMITTED_TYPE,
        lord = { 
            possible_subtypes = { 
                "wh_dlc05_wef_glade_lord"
            },
            level_ranges = { 20, 30 }, 
            possible_forenames = { },
            possible_clan_names = { }, 
            possible_family_names = { }, 
            skills = {
                ["wh_dlc05_wef_glade_lord"] = {
                    { name = "", level = 1 },
                },
            },
            ancillaries = {},
            traits = {}
        },
        armies_by_level = {
            [1] = {
                unit_experience_amount = 2,
                units = {
                    { "wh_dlc05_wef_inf_glade_guard_0", 12, 100, 0, nil }
                }
            },
            [2] = {
                unit_experience_amount = 5,
                units = {
                    { "wh_dlc05_wef_inf_wardancers_0", 4, 100, 0, nil },
                    { "wh_dlc05_wef_mon_treekin_0", 4, 100, 0, nil },
                    { "wh_dlc05_wef_inf_deepwood_scouts_1", 8, 100, 0, nil }
                }
            },
            [3] = {
                unit_experience_amount = 7,
                units = {
                    { "wh2_dlc16_wef_inf_bladesingers_0", 6, 0, 100, "wh_dlc05_wef_inf_waywatchers_0" }, -- DLC Check needed
                    { "wh_dlc05_wef_inf_waywatchers_0", 10, 100, 0, nil },
                    { "wh_dlc05_wef_cha_ancient_treeman_0", 3, 100, 0, nil }
                }
            }
        }
    },
    --Norsca
    ["wh_dlc08_sc_nor_norsca"] = {
        identifier = "defender_force",
        invasion_identifier = "defender_invasion",
        intervention_type = ALLIED_REINFORCEMENTS_PERMITTED_TYPE,
        lord = { 
            possible_subtypes = { 
                "wh_main_nor_marauder_chieftain"
            },
            level_ranges = { 20, 30 }, 
            possible_forenames = { },
            possible_clan_names = { }, 
            possible_family_names = { }, 
            skills = {
                ["wh_main_nor_marauder_chieftain"] = {
                    { name = "wh_main_skill_chs_lord_battle_dominating_presence", level = 1 },
                    { name = "wh2_dlc11_skill_nor_army_buff_fearsome_warriors", level = 3 },
                    { name = "wh2_dlc11_skill_nor_army_buff_beast_slayers", level = 3 },
                    { name = "wh2_dlc11_skill_nor_army_buff_unnatural_selection", level = 3 },
                    { name = "wh2_dlc11_skill_nor_army_buff_frostbitten", level = 3 },
                    { name = "wh2_dlc11_skill_nor_army_buff_hail_of_teeth", level = 3 },
                    { name = "wh2_dlc11_skill_nor_army_buff_monsters_of_the_north", level = 3 },
                    { name = "wh2_dlc11_skill_nor_army_buff_champions_of_the_north", level = 1 },
                    { name = "wh2_dlc11_skill_nor_army_buff_hardened_hunters", level = 1 },
                    { name = "wh2_dlc11_skill_nor_army_buff_icy_wrath", level = 1 },
                    { name = "wh2_dlc11_skill_nor_army_buff_hulks_of_death", level = 1 },
                    { name = "wh_dlc08_skill_nor_lord_battle_stand_or_die", level = 1 },
                    { name = "wh_dlc08_skill_nor_lords_battle_fight_or_die", level = 1 },
                    { name = "wh3_main_skill_agent_action_success_scaling", level = 1 },
                    { name = "wh_main_skill_all_lord_campaign_route_marcher", level = 1 },
                    { name = "wh_dlc08_skill_nor_lord_self_drinker_of_blood", level = 1 },
                    { name = "wh_dlc08_skill_nor_lord_self_spirit_wanderer", level = 1 },
                    { name = "wh_dlc08_skill_nor_lord_self_dark_deceiver", level = 1 },
                    { name = "wh_dlc08_skill_nor_lord_self_sorcery_of_the_eagle", level = 1 },
                    { name = "wh_dlc08_skill_nor_chieftain_unique_war_mammoth", level = 1 },
                    { name = "wh_dlc08_skill_nor_lords_unique_eye_of_the_gods", level = 1 },
                    { name = "wh_main_skill_chs_lord_battle_voice_of_the_dark_gods", level = 1 },
                    { name = "wh2_main_skill_innate_all_disciplined", level = 1 },
                    { name = "wh_dlc08_skill_nor_chieftain_enable_rage", level = 1 }
                },
            },
            ancillaries = {},
            traits = {}
        },
        armies_by_level = {
            [1] = {
                unit_experience_amount = 2,
                units = {
                    { "wh_main_nor_inf_chaos_marauders_1", 4, 100, 0, nil },
                    { "wh_dlc08_nor_inf_marauder_hunters_0", 4, 100, 0, nil },
                    { "wh_main_nor_cav_marauder_horsemen_1", 3, 100, 0, nil }
                }
            },
            [2] = {
                unit_experience_amount = 5,
                units = {
                    { "wh_dlc08_nor_inf_marauder_berserkers_0", 4, 100, 0, nil },
                    { "wh_dlc08_nor_inf_marauder_hunters_0", 4, 100, 0, nil },
                    { "wh_dlc08_nor_mon_skinwolves_0", 4, 100, 0, nil },
                    { "wh_main_nor_cav_chaos_chariot", 2, 100, 0, nil },
                    { "wh_dlc08_nor_mon_war_mammoth_1", 1, 100, 0, nil }
                }
            },
            [3] = {
                unit_experience_amount = 7,
                units = {
                    { "wh_dlc08_nor_inf_marauder_champions_1", 4, 100, 0, nil },
                    { "wh_dlc08_nor_mon_fimir_1", 4, 100, 0, nil },
                    { "wh_dlc08_nor_mon_skinwolves_0", 4, 100, 0, nil },
                    { "wh_dlc08_nor_mon_war_mammoth_2", 2, 100, 0, nil },
                    { "wh_dlc08_nor_mon_frost_wyrm_0", 1, 100, 0, nil }
                }
            }
        }
    },

    --WH2
    --Dark Elves
    ["wh2_main_sc_def_dark_elves"] = {
        identifier = "defender_force",
        invasion_identifier = "defender_invasion",
        intervention_type = ALLIED_REINFORCEMENTS_PERMITTED_TYPE,
        lord = { 
            possible_subtypes = { 
                "wh2_main_def_dreadlord_fem"
            },
            level_ranges = { 20, 30 }, 
            possible_forenames = { },
            possible_clan_names = { }, 
            possible_family_names = { }, 
            skills = {
                ["wh2_main_def_dreadlord_fem"] = {
                    { name = "wh_main_skill_all_lord_battle_inspiring_presence", level = 1 },
                    { name = "wh2_main_skill_def_army_buff_basic_infantry", level = 3 },
                    { name = "wh2_main_skill_def_army_buff_missile", level = 3 },
                    { name = "wh2_main_skill_def_army_buff_shades_riders", level = 3 },
                    { name = "wh2_main_skill_def_army_buff_beasts", level = 3 },
                    { name = "wh2_main_skill_def_army_buff_coldones", level = 3 },
                    { name = "wh2_main_skill_def_army_buff_elites", level = 3 },
                    { name = "wh2_main_skill_def_army_buff_cull_the_unworthy", level = 1 },
                    { name = "wh2_main_skill_def_army_buff_rewards_for_ravagers", level = 1 },
                    { name = "wh2_main_skill_def_army_buff_favour_the_fortunate", level = 1 },
                    { name = "wh2_main_skill_def_army_buff_confer_bloodlust", level = 1 },
                    { name = "wh2_main_skill_def_kindle_the_fury", level = 1 },
                    { name = "wh2_main_skill_def_combat_sea_dragon_cloak", level = 1 },
                    { name = "wh2_dlc11_skill_all_lord_self_devastating_charge", level = 2 },
                    { name = "wh2_dlc11_skill_all_lord_self_blade_master", level = 2 },
                    { name = "wh2_dlc11_skill_all_lord_self_self_indomitable", level = 2 },
                    { name = "wh_main_skill_all_all_self_foe-seeker", level = 1 },
                    { name = "wh2_dlc11_skill_all_lord_self_wound-maker", level = 2 },
                    { name = "wh2_dlc11_skill_wef_lord_self_expeditious_endeavour", level = 1 },
                    { name = "wh_main_skill_all_all_self_deadly_onslaught", level = 1 },
                    { name = "wh2_main_skill_def_generic_sadistic", level = 1 },
                    { name = "wh2_main_skill_def_generic_eternal_hatred", level = 1 },
                    { name = "wh2_main_skill_def_generic_ward_of_khaine", level = 1 },
                    { name = "wh2_main_skill_def_generic_ward_of_hekarti", level = 1 },
                    { name = "wh2_main_skill_innate_def_spiteful", level = 1 },
                    { name = "wh2_main_skill_def_names_of_power_1", level = 1 },
                },
            },
            ancillaries = {},
            traits = {}
        },
        armies_by_level = {
            [1] = {
                unit_experience_amount = 2,
                units = {
                    { "wh2_main_def_inf_black_ark_corsairs_1", 4, 100, 0, nil },
                    { "wh2_main_def_inf_darkshards_1", 4, 100, 0, nil },
                    { "wh2_main_def_inf_shades_0", 2, 100, 0, nil },
                    { "wh2_main_def_art_reaper_bolt_thrower", 2, 100, 0, nil }
                }
            },
            [2] = {
                unit_experience_amount = 5,
                units = {
                    { "wh2_main_def_inf_black_guard_0", 3, 100, 0, nil },                         
                    { "wh2_main_def_inf_har_ganeth_executioners_0", 3, 100, 0, nil },
                    { "wh2_main_def_inf_shades_1", 6, 100, 0, nil },
                    { "wh2_main_def_art_reaper_bolt_thrower", 3, 100, 0, nil }
                }
            },
            [3] = {
                unit_experience_amount = 7,
                units = {
                    { "wh2_main_def_mon_war_hydra", 4, 100, 0, nil },
                    { "wh2_main_def_inf_black_guard_0", 4, 100, 0, nil },
                    { "wh2_main_def_inf_shades_2", 11, 100, 0, nil }
                }
            }
        }
    },
    --High Elves
    ["wh2_main_sc_hef_high_elves"] = {
        identifier = "defender_force",
        invasion_identifier = "defender_invasion",
        intervention_type = ALLIED_REINFORCEMENTS_PERMITTED_TYPE,
        lord = { 
            possible_subtypes = { 
                "wh2_main_hef_princess"
            },
            level_ranges = { 20, 30 }, 
            possible_forenames = { },
            possible_clan_names = { }, 
            possible_family_names = { }, 
            skills = {
                ["wh2_main_hef_princess"] = {
                    { name = "wh_main_skill_all_lord_battle_inspiring_presence", level = 1 },
                    { name = "wh2_main_skill_hef_army_buff_basic_infantry", level = 3 },
                    { name = "wh2_main_skill_hef_army_buff_missile", level = 3 },
                    { name = "wh2_main_skill_hef_army_buff_cavalry", level = 3 },
                    { name = "wh2_main_skill_hef_army_buff_elite_cav", level = 3 },
                    { name = "wh2_main_skill_hef_army_buff_flyers", level = 3 },
                    { name = "wh2_main_skill_hef_army_buff_elite_inf", level = 3 },
                    { name = "wh2_main_skill_hef_def_fire_at_will", level = 1 },
                    { name = "wh2_main_skill_hef_army_buff_avalanche_of_granite", level = 1 },
                    { name = "wh2_main_skill_hef_army_buff_favourable_winds", level = 1 },
                    { name = "wh2_main_skill_hef_army_buff_silver_torrent", level = 1 },
                    { name = "wh2_main_skill_hef_army_buff_heart_of_the_flame", level = 1 },
                    { name = "wh2_main_skill_hef_def_darken_the_skies", level = 1 },
                    { name = "wh2_main_skill_hef_seeking_arrows", level = 1 },
                    { name = "wh2_main_skill_hef_combat_valour_of_ages", level = 1 },
                    { name = "wh2_dlc11_skill_all_lord_self_deadeye", level = 2 },
                    { name = "wh2_dlc11_skill_all_lord_self_blade_master", level = 2 },
                    { name = "wh_main_skill_all_all_self_foe-seeker", level = 1 },
                    { name = "wh2_dlc11_skill_all_lord_self_wound-maker", level = 2 },
                    { name = "wh2_dlc11_skill_wef_lord_self_piercing_shots", level = 2 },
                    { name = "wh2_dlc11_skill_wef_lord_self_expeditious_endeavour", level = 1 },
                    { name = "wh2_main_skill_hef_def_volley_of_arrows", level = 1 },
                    { name = "wh2_main_skill_hef_dedication_asuryan", level = 1 },
                    { name = "wh2_main_skill_hef_generic_speed_of_asuryan", level = 1 },
                    { name = "wh2_main_skill_hef_generic_warding_of_loec", level = 1 },
                    { name = "wh2_main_skill_hef_generic_warding_of_hoeth", level = 1 },
                    { name = "wh2_main_skill_innate_hef_princess_campaign_7_vigilant", level = 1 }
                },
            },
            ancillaries = {},
            traits = {}
        },
        armies_by_level = {
            [1] = {
                unit_experience_amount = 2,
                units = {
                    { "wh2_dlc15_hef_inf_rangers_0", 4, 100, 0, nil },
                    { "wh2_main_hef_inf_archers_1", 6, 100, 0, nil },
                    { "wh2_main_hef_art_eagle_claw_bolt_thrower", 2, 100, 0, nil }
                }
            },
            [2] = {
                unit_experience_amount = 5,
                units = {
                    { "wh2_dlc15_hef_inf_silverin_guard_0", 4, 100, 0, nil },
                    { "wh2_main_hef_inf_lothern_sea_guard_1", 8, 100, 0, nil },
                    { "wh2_main_hef_mon_phoenix_flamespyre", 4, 100, 0, nil },
                    { "wh2_main_hef_art_eagle_claw_bolt_thrower", 3, 100, 0, nil }
                }
            },
            [3] = {
                unit_experience_amount = 7,
                units = {
                    { "wh2_main_hef_inf_swordmasters_of_hoeth_0", 3, 100, 0, nil },
                    { "wh2_main_hef_inf_phoenix_guard", 3, 100, 0, nil },
                    { "wh2_dlc10_hef_inf_sisters_of_avelorn_0", 10, 0, 100, "wh2_dlc10_hef_infantry_shadow_walker" }, -- dlc check required
                    { "wh2_main_hef_mon_star_dragon", 2, 100, 0, nil },
                    { "wh2_dlc15_hef_mon_arcane_phoenix_0", 1, 0, 100, "wh2_main_hef_mon_phoenix_flamespyre" } -- dlc check required
                }
            }
        }
    },
    --Lizardmen
    ["wh2_main_sc_lzd_lizardmen"] = {
        identifier = "defender_force",
        invasion_identifier = "defender_invasion",
        intervention_type = ALLIED_REINFORCEMENTS_PERMITTED_TYPE,
        lord = { 
            possible_subtypes = { 
                "wh2_main_lzd_saurus_old_blood"
            },
            level_ranges = { 20, 30 }, 
            possible_forenames = { },
            possible_clan_names = { }, 
            possible_family_names = { }, 
            skills = {
                ["wh2_main_lzd_saurus_old_blood"] = {
                    { name = "wh_main_skill_all_lord_battle_inspiring_presence", level = 1 },
                    { name = "wh2_main_skill_lzd_army_buff_saurus", level = 3 },
                    { name = "wh2_main_skill_lzd_army_buff_skinks", level = 3 },
                    { name = "wh2_main_skill_lzd_army_buff_riders", level = 3 },
                    { name = "wh2_main_skill_lzd_army_buff_guardians", level = 3 },
                    { name = "wh2_main_skill_lzd_army_buff_hunters", level = 3 },
                    { name = "wh2_main_skill_lzd_army_buff_dinos", level = 3 },
                    { name = "wh2_main_skill_lzd_army_buff_jungle_dominion", level = 1 },
                    { name = "wh2_main_skill_lzd_army_buff_spawn_kin", level = 1 },
                    { name = "wh2_main_skill_lzd_army_buff_soul_bound", level = 1 },
                    { name = "wh2_main_skill_lzd_army_buff_epicentre", level = 1 },
                    { name = "wh_main_skill_all_lord_battle_stand_your_ground", level = 1 },
                    { name = "wh2_main_skill_lzd_predatory_fighter", level = 1 },
                    { name = "wh2_main_skill_lzd_enforcer_of_order", level = 1 },
                    { name = "wh2_dlc11_skill_all_lord_self_thick-skinned", level = 2 },
                    { name = "wh2_dlc11_skill_all_lord_self_self_indomitable", level = 2 },
                    { name = "wh_main_skill_all_all_self_foe-seeker", level = 1 },
                    { name = "wh2_dlc11_skill_all_lord_self_scarred_veteran", level = 2 },
                    { name = "wh2_dlc11_skill_all_lord_self_blade_shield", level = 2 },
                    { name = "wh2_dlc11_skill_wef_lord_self_expeditious_endeavour", level = 2 },
                    { name = "wh_main_skill_all_all_self_deadly_onslaught", level = 1 },
                    { name = "wh2_main_skill_lzd_blessing_itzl", level = 1 },
                    { name = "wh2_main_skill_lzd_lizardmen_agility", level = 1 },
                    { name = "wh2_main_skill_lzd_protection_of_the_old_ones", level = 1 },
                    { name = "wh2_main_skill_lzd_generic_honoured_elder_lord", level = 1 },
                    { name = "wh2_main_skill_innate_lzd_pompous", level = 1 },
                    { name = "wh2_main_skill_lzd_saurus_old_blood_carnosaur", level = 1 }

                },
            },
            ancillaries = {},
            traits = {}
        },
        armies_by_level = {
            [1] = {
                unit_experience_amount = 2,
                units = {
                    { "wh2_main_lzd_inf_saurus_spearmen_1", 2, 100, 0, nil },
                    { "wh2_main_lzd_inf_temple_guards", 2, 100, 0, nil },
                    { "wh2_dlc17_lzd_inf_chameleon_stalkers_0", 8, 0, 100, "wh2_main_lzd_inf_chameleon_skinks_0" } -- Dlc check required
                }
            },
            [2] = {
                unit_experience_amount = 5,
                units = {
                    { "wh2_main_lzd_inf_temple_guards", 5, 100, 0, nil },
                    { "wh2_main_lzd_mon_kroxigors", 3, 100, 0, nil },
                    { "wh2_dlc17_lzd_inf_chameleon_stalkers_0", 5, 0, 100, "wh2_main_lzd_inf_chameleon_skinks_blessed_0" }, -- Dlc check required
                    { "wh2_main_lzd_mon_stegadon_1", 3, 100, 0, nil }
                }
            },
            [3] = {
                unit_experience_amount = 7,
                units = {
                    { "wh2_main_lzd_mon_carnosaur_0", 4, 100, 0, nil },
                    { "wh2_dlc12_lzd_mon_ancient_stegadon_1", 4, 0, 100, "wh2_main_lzd_mon_stegadon_1" }, -- DLC check required
                    { "wh2_dlc17_lzd_mon_troglodon_0", 2, 0, 100, "wh2_main_lzd_mon_stegadon_1" }, -- Dlc check required
                    { "wh2_main_lzd_mon_stegadon_1", 6, 100, 0, nil }, 
                    { "wh2_dlc17_lzd_mon_coatl_0", 2, 0, 0, nil },
                    { "wh2_dlc13_lzd_mon_dread_saurian_1", 1, 0, 100, "wh2_main_lzd_mon_stegadon_1" } -- Dlc check required
                }
            }
        }
    },
    --Skaven
    ["wh2_main_sc_skv_skaven"] = {
        identifier = "defender_force",
        invasion_identifier = "defender_invasion",
        intervention_type = ALLIED_REINFORCEMENTS_PERMITTED_TYPE,
        lord = { 
            possible_subtypes = { 
                "wh2_dlc12_skv_warlock_master"
            },
            level_ranges = { 20, 30 }, 
            possible_forenames = { },
            possible_clan_names = { }, 
            possible_family_names = { }, 
            skills = {
                ["wh2_dlc12_skv_warlock_master"] = {
                    { name = "wh_main_skill_all_lord_battle_inspiring_presence", level = 1 },
                    { name = "wh2_main_skill_skv_army_buff_clanrats", level = 3 },
                    { name = "wh2_main_skill_skv_army_buff_runners", level = 3 },
                    { name = "wh2_main_skill_skv_army_buff_weaponteams", level = 3 },
                    { name = "wh2_main_skill_skv_army_buff_eliteinf", level = 3 },
                    { name = "wh2_main_skill_skv_army_buff_monsters", level = 3 },
                    { name = "wh2_main_skill_skv_army_buff_artillery", level = 3 },
                    { name = "wh2_main_skill_skv_army_buff_straight_to_the_point", level = 1 },
                    { name = "wh2_main_skill_skv_army_buff_gutter_wise", level = 1 },
                    { name = "wh2_main_skill_skv_army_buff_warped_workshops", level = 1 },
                    { name = "wh2_main_skill_skv_army_buff_mutagenic_elixirs", level = 1 },
                    { name = "wh_main_skill_chs_lord_battle_stand_or_die", level = 1 },
                    { name = "wh2_main_skill_skv_generic_missile_ward", level = 1 },
                    { name = "wh2_main_skill_skv_generic_magic_ward", level = 1 },
                    { name = "wh2_main_skill_all_magic_ruin_01_warp_lightning", level = 2 },
                    { name = "wh2_main_skill_all_magic_ruin_02_howling_warpgale_lord", level = 1 },
                    { name = "wh2_main_skill_all_magic_ruin_05_skaven_scorch_lord", level = 2 },
                    { name = "wh2_main_skill_all_magic_ruin_03_lore_attribute", level = 1 },
                    { name = "wh_main_skill_all_magic_all_06_evasion", level = 1 },
                    { name = "wh2_main_skill_all_magic_ruin_09_cracks_call_lord", level = 2 },
                    { name = "wh2_main_skill_all_magic_ruin_10_flensing_ruin_lord", level = 2 },
                    { name = "wh_main_skill_all_magic_all_07_earthing", level = 1 },
                    { name = "wh_main_skill_all_magic_all_08_power_drain", level = 1 },
                    { name = "wh_main_skill_all_magic_all_11_arcane_conduit", level = 1 },
                    { name = "wh2_main_skill_skv_combat_tail_weapon", level = 1 },
                    { name = "wh2_main_skill_skv_engineer_warlock_augmented_weapon", level = 1 },
                    { name = "wh2_dlc11_skill_all_lord_self_scarred_veteran", level = 1 },
                    { name = "wh2_main_skill_skv_engineer_warpforged_armour", level = 1 },
                    { name = "wh2_dlc12_skill_skv_engineer_personal_0", level = 1 },
                    { name = "wh2_dlc12_skill_skv_engineer_unique_0", level = 1 },
                    { name = "wh2_dlc12_skill_skv_engineer_unique_1", level = 1 },
                    { name = "wh2_dlc12_skill_skv_engineer_unique_2", level = 1 },
                    { name = "wh2_dlc12_skill_warlock_master_brass_orb", level = 1 },
                    { name = "wh2_main_skill_innate_all_disciplined", level = 1 }
                }
            },
            ancillaries = {},
            traits = {}
        },
        armies_by_level = {
            [1] = {
                unit_experience_amount = 2,
                units = {
                    { "wh2_dlc14_skv_inf_eshin_triads_0", 4, 0, 100, "wh2_main_skv_inf_night_runners_1" },
                    { "wh2_main_skv_inf_night_runners_1", 4, 100, 0, nil },
                    { "wh2_dlc12_skv_inf_ratling_gun_0", 2, 0, 100, "wh2_main_skv_inf_night_runners_1" },
                    { "wh2_main_skv_art_plagueclaw_catapult", 2, 100, 0, nil }
                }
            },
            [2] = {
                unit_experience_amount = 5,
                units = {
                    { "wh2_main_skv_inf_stormvermin_0", 4, 100, 0, nil },
                    { "wh2_dlc14_skv_inf_eshin_triads_0", 2, 0, 100, "wh2_main_skv_inf_stormvermin_1" },
                    { "wh2_main_skv_inf_night_runners_1", 2, 100, 0, nil },
                    { "wh2_dlc12_skv_inf_warplock_jezzails_0", 2, 0, 100, "wh2_main_skv_inf_gutter_runner_slingers_1" },
                    { "wh2_dlc12_skv_inf_ratling_gun_0", 2, 0, 100, "wh2_main_skv_art_plagueclaw_catapult" },
                    { "wh2_main_skv_art_plagueclaw_catapult", 3, 100, 0, nil }
                }
            },
            [3] = {
                unit_experience_amount = 7,
                units = {
                    { "wh2_main_skv_inf_stormvermin_1", 5, 100, 0, nil },
                    { "wh2_dlc12_skv_inf_warplock_jezzails_0", 3, 0, 100, "wh2_main_skv_inf_gutter_runner_slingers_1" },
                    { "wh2_dlc12_skv_inf_ratling_gun_0", 5, 0, 100, "wh2_main_skv_inf_gutter_runner_slingers_1" },
                    { "wh2_dlc14_skv_inf_poison_wind_mortar_0", 2, 0, 100, "wh2_main_skv_art_plagueclaw_catapult" },
                    { "wh2_main_skv_art_plagueclaw_catapult", 2, 100, 0, nil  },
                    { "wh2_main_skv_art_warp_lightning_cannon", 2, 100, 0, nil }
                }
            }
        }
    },
    --Tomb Kings
    ["wh2_dlc09_sc_tmb_tomb_kings"] = {
        identifier = "defender_force",
        invasion_identifier = "defender_invasion",
        intervention_type = ALLIED_REINFORCEMENTS_PERMITTED_TYPE,
        lord = { 
            possible_subtypes = { 
                "wh2_dlc09_tmb_tomb_king"
            },
            level_ranges = { 20, 30 }, 
            possible_forenames = { },
            possible_clan_names = { }, 
            possible_family_names = { }, 
            skills = {
                ["wh2_dlc09_tmb_tomb_king"] = {
                    { name = "wh2_dlc09_skill_tmb_lord_army_base", level = 1 },
                    { name = "wh2_dlc09_skill_tmb_army_buff_basic_archers", level = 3 },
                    { name = "wh2_dlc09_skill_tmb_army_buff_basic_infantry", level = 3 },
                    { name = "wh2_dlc09_skill_tmb_army_buff_cav", level = 3 },
                    { name = "wh2_dlc09_skill_tmb_army_buff_chariot", level = 3 },
                    { name = "wh2_dlc09_skill_tmb_army_buff_structure_infantry", level = 3 },
                    { name = "wh2_dlc09_skill_tmb_army_buff_elite_structure", level = 3 },
                    { name = "wh2_dlc09_skill_tmb_army_buff_vet_infantry", level = 1 },
                    { name = "wh2_dlc09_skill_tmb_army_buff_vet_structure", level = 1 },
                    { name = "wh2_dlc09_skill_tmb_army_buff_vet_archer", level = 1 },
                    { name = "wh2_dlc09_skill_tmb_army_buff_vet_cav", level = 1 },
                    { name = "wh2_dlc09_skill_tmb_lord_rally_upgraded", level = 1 },
                    { name = "wh2_dlc09_skill_tmb_god_blessing_0", level = 1 },
                    { name = "wh2_main_skill_innate_all_disciplined", level = 1 },
                    { name = "wh2_dlc09_skill_tmb_tomb_king_returned_in_madness", level = 1 },
                    { name = "wh2_dlc09_skill_tmb_tomb_king_ancient_tyrant", level = 1 },
                    { name = "wh2_dlc09_skill_tmb_tomb_king_embalmed_in_elixir", level = 1 },
                    { name = "wh2_dlc09_skill_tmb_tomb_king_ceremonial_bandages", level = 1 },
                    { name = "wh2_dlc09_skill_tmb_lord_unique_tomb_king_khemrian_warsphinx", level = 1 },
                    { name = "wh2_dlc09_skill_tmb_personal_base", level = 1 },
                    { name = "wh2_dlc09_skill_tmb_personal_conqueror", level = 1 },
                    { name = "wh2_dlc09_skill_tmb_personal_10", level = 1 },
                    { name = "wh2_dlc11_skill_all_lord_self_blade_master", level = 2 },
                    { name = "wh2_dlc11_skill_all_lord_self_hard_to_hit", level = 2 },
                    { name = "wh2_dlc11_skill_all_lord_self_self_indomitable", level = 2 },
                    { name = "wh2_dlc09_skill_tmb_personal_5", level = 1 },
                    { name = "wh2_dlc11_skill_all_lord_self_wound-maker", level = 2 },
                    { name = "wh2_dlc11_skill_all_lord_self_full_plate_armour", level = 2 },
                    { name = "wh2_dlc11_skill_all_lord_self_devastating_charge", level = 2 },
                    { name = "wh2_dlc09_skill_tmb_personal_9", level = 1 }
                }
            },
            ancillaries = {},
            traits = {}
        },
        armies_by_level = {
            [1] = {
                unit_experience_amount = 2,
                units = {
                    { "wh2_dlc09_tmb_inf_nehekhara_warriors_0", 2, 100, 0, nil },
                    { "wh2_dlc09_tmb_mon_ushabti_0", 2, 100, 0, nil },
                    { "wh2_dlc09_tmb_inf_skeleton_archers_0", 7, 100, 0, nil },
                    { "wh2_dlc09_tmb_art_screaming_skull_catapult_0", 2, 100, 0, nil }
                }
            },
            [2] = {
                unit_experience_amount = 5,
                units = {
                    { "wh2_dlc09_tmb_inf_tomb_guard_0", 4, 100, 0, nil },
                    { "wh2_dlc09_tmb_inf_skeleton_archers_0", 4, 100, 0, nil },
                    { "wh2_dlc09_tmb_mon_ushabti_1", 4, 100, 0, nil },
                    { "wh2_dlc09_tmb_mon_tomb_scorpion_0", 2, 100, 0, nil },
                    { "wh2_dlc09_tmb_art_casket_of_souls_0", 1, 100, 0, nil }
                }
            },
            [3] = {
                unit_experience_amount = 7,
                units = {
                    { "wh2_dlc09_tmb_mon_tomb_scorpion_0", 6, 100, 0, nil },
                    { "wh2_dlc09_tmb_mon_necrosphinx_0", 4, 100, 0, nil },
                    { "wh2_dlc09_tmb_veh_khemrian_warsphinx_0", 4, 100, 0, nil },
                    { "wh2_dlc09_tmb_mon_heirotitan_0", 2, 100, 0, nil },
                    { "wh2_dlc09_tmb_mon_ushabti_1", 3, 100, 0, nil }
                }
            }
        }
    },
    --Vampire Coast
    ["wh2_dlc11_sc_cst_vampire_coast"] = {
        identifier = "defender_force",
        invasion_identifier = "defender_invasion",
        intervention_type = ALLIED_REINFORCEMENTS_PERMITTED_TYPE,
        lord = { 
            possible_subtypes = { 
                "wh2_dlc11_cst_admiral_fem_vampires"
            },
            level_ranges = { 20, 30 }, 
            possible_forenames = { },
            possible_clan_names = { }, 
            possible_family_names = { }, 
            skills = {
                ["wh2_dlc11_cst_admiral_fem_vampires"] = {
                    { name = "wh_main_skill_all_lord_battle_inspiring_presence", level = 1 },
                    { name = "wh2_dlc11_skill_cst_army_1", level = 3 },
                    { name = "wh2_dlc11_skill_cst_army_2", level = 3 },
                    { name = "wh2_dlc11_skill_cst_army_3", level = 3 },
                    { name = "wh2_dlc11_skill_cst_army_4", level = 3 },
                    { name = "wh2_dlc11_skill_cst_army_5", level = 3 },
                    { name = "wh2_dlc11_skill_cst_army_6", level = 3 },
                    { name = "wh2_dlc11_skill_cst_army_8", level = 1 },
                    { name = "wh2_dlc11_skill_cst_army_9", level = 1 },
                    { name = "wh2_dlc11_skill_cst_army_10", level = 1 },
                    { name = "wh2_dlc11_skill_cst_army_11", level = 1 },
                    { name = "wh2_dlc11_skill_cst_army_12_all_hands_hoay", level = 1 },
                    { name = "wh_main_skill_vmp_lord_self_the_hunger", level = 1 },
                    { name = "wh_dlc11_skill_cst_lord_self_supernatural_horror", level = 1 },
                    { name = "wh2_dlc11_skill_cst_lord_crime_0", level = 1 },
                    { name = "wh2_dlc11_skill_cst_lord_crime_1", level = 1 },
                    { name = "wh2_dlc11_skill_cst_lord_crime_2_sword", level = 1 },
                    { name = "wh2_dlc11_skill_cst_lord_crime_3", level = 1 },
                    { name = "wh2_dlc11_skill_cst_personal_0_monkey_jacket", level = 1 },
                    { name = "wh2_dlc11_skill_all_lord_self_swashbuckler", level = 1 },
                    { name = "wh2_dlc11_skill_vmp_lord_self_master_strike", level = 2 },
                    { name = "wh2_dlc11_skill_all_lord_self_scarred_veteran", level = 2 },
                    { name = "wh2_dlc11_skill_cst_personal_5_taunt", level = 1 },
                    { name = "wh2_dlc11_skill_cst_ranged_0", level = 1 },
                    { name = "wh2_dlc11_skill_cst_ranged_1_fem_admiral", level = 1 },
                    { name = "wh2_dlc11_skill_cst_ranged_2_fem_admiral", level = 1 },
                    { name = "wh2_dlc11_skill_cst_ranged_3_fem_admiral", level = 1 },
                    { name = "wh2_dlc11_skill_cst_ranged_4_fem_admiral", level = 1 },
                    { name = "wh2_dlc11_skill_cst_ranged_5_pyromaniac", level = 1 },
                    { name = "wh2_dlc11_skill_cst_misc_1", level = 1 },
                    { name = "wh2_dlc11_skill_cst_misc_2", level = 1 },
                    { name = "wh2_dlc11_skill_innate_cst_ringleader", level = 1 },
                    { name = "wh_main_skill_vmp_magic_vampires_01_invocation_of_nehek", level = 2 },
                    { name = "wh_main_skill_vmp_magic_vampires_03_the_curse_of_undeath", level = 1 },
                    { name = "wh2_main_skill_vmp_magic_vampires_02_vanhels_danse_macabre_lord", level = 2 },
                    { name = "wh2_main_skill_vmp_magic_vampires_04_gaze_of_nagash_lord", level = 2 },
                    { name = "wh2_dlc11_skill_cst_magic_vampires_05_drowned_dead_lord", level = 2 },
                    { name = "wh_main_skill_all_magic_all_06_evasion", level = 1 },
                    { name = "wh_main_skill_all_magic_all_07_earthing", level = 1 },
                    { name = "wh_main_skill_all_magic_all_08_power_drain", level = 1 },
                    { name = "wh2_main_skill_vmp_magic_vampires_09_curse_of_years_lord", level = 1 },
                    { name = "wh2_main_skill_vmp_magic_vampires_10_wind_of_death_lord", level = 2 },
                    { name = "wh_main_skill_all_magic_all_11_arcane_conduit", level = 1 }
                },
            },
            ancillaries = {},
            traits = {}
        },
        armies_by_level = {
            [1] = {
                unit_experience_amount = 2,
                units = {
                    { "wh2_dlc11_cst_inf_zombie_gunnery_mob_3", 4, 100, 0, nil },
                    { "wh2_dlc11_cst_mon_bloated_corpse_0", 2, 100, 0, nil },
                    { "wh2_dlc11_cst_inf_deck_gunners_0", 2, 100, 0, nil },
                    { "wh2_dlc11_cst_art_mortar", 4, 100, 0, nil }
                }
            },
            [2] = {
                unit_experience_amount = 5,
                units = {
                    { "wh2_dlc11_cst_inf_depth_guard_1", 4, 100, 0, nil },
                    { "wh2_dlc11_cst_inf_zombie_gunnery_mob_3", 4, 100, 0, nil },
                    { "wh2_dlc11_cst_inf_deck_gunners_0", 2, 100, 0, nil },
                    { "wh2_dlc11_cst_art_carronade", 2, 100, 0, nil },
                    { "wh2_dlc11_cst_mon_rotting_leviathan_0", 2, 100, 0, nil },
                    { "wh2_dlc11_cst_mon_necrofex_colossus_0", 1, 100, 0, nil }
                }
            },
            [3] = {
                unit_experience_amount = 7,
                units = {
                    { "wh2_dlc11_cst_inf_depth_guard_1", 8, 100, 0, nil },
                    { "wh2_dlc11_cst_inf_zombie_gunnery_mob_3", 2, 100, 0, nil },
                    { "wh2_dlc11_cst_inf_deck_gunners_0", 2, 100, 0, nil },
                    { "wh2_dlc11_cst_mon_rotting_leviathan_0", 4, 100, 0, nil },
                    { "wh2_dlc11_cst_mon_necrofex_colossus_0", 3, 100, 0, nil }
                }
            }
        }
    },

    --WH3
    ["wh3_main_sc_ksl_kislev"] = {
        identifier = "defender_force",
        invasion_identifier = "defender_invasion",
        intervention_type = ALLIED_REINFORCEMENTS_PERMITTED_TYPE,
        lord = { 
            possible_subtypes = { 
                "wh3_main_ksl_ataman"
            },
            level_ranges = { 20, 30 }, 
            possible_forenames = { },
            possible_clan_names = { }, 
            possible_family_names = { }, 
            skills = {
                ["wh3_main_ksl_ataman"] = {
                    { name = "wh_main_skill_all_lord_battle_inspiring_presence", level = 1 },
                    { name = "wh3_main_skill_ksl_army_buff_kossars_streltsi", level = 3 },
                    { name = "wh3_main_skill_ksl_army_buff_elite_infantry", level = 3 },
                    { name = "wh3_main_skill_ksl_army_buff_heavy_cavalry", level = 3 },
                    { name = "wh3_main_skill_ksl_army_buff_monsters", level = 3 },
                    { name = "wh3_main_skill_ksl_army_buff_war_machines", level = 3 },
                    { name = "wh3_main_skill_ksl_army_buff_kossars_streltsi_ice_guard_rank_7", level = 1 },
                    { name = "wh3_main_skill_ksl_army_buff_cavalry_rank_7", level = 1 },
                    { name = "wh3_main_skill_ksl_army_buff_bears_tsar_guard_rank_7", level = 1 },
                    { name = "wh3_main_skill_ksl_army_buff_war_machines_rank_7", level = 1 },
                    { name = "wh_main_skill_all_lord_battle_stand_your_ground", level = 1 },
                    { name = "wh_main_skill_all_all_self_hard_to_hit_starter", level = 1 },
                    { name = "wh2_dlc11_skill_all_lord_self_full_plate_armour", level = 2 },
                    { name = "wh2_dlc11_skill_all_lord_self_scarred_veteran", level = 2 },
                    { name = "wh_main_skill_all_all_self_foe-seeker", level = 1 },
                    { name = "wh2_dlc11_skill_all_lord_self_blade_shield", level = 2 },
                    { name = "wh_main_skill_all_all_self_deadly_onslaught", level = 1 },
                    { name = "wh3_main_skill_innate_ksl_ataman_1", level = 1 },
                    { name = "wh3_main_skill_ksl_boyar_unique_war_bear", level = 1 },
                    { name = "wh3_main_skill_ksl_all_unique_missile_resist", level = 1 },
                    { name = "wh_main_skill_all_lord_battle_brass-lunged", level = 1 },
                    { name = "wh3_main_skill_ksl_generic_heroic_resilience", level = 1 }
                },
            },
            ancillaries = {},
            traits = {}
        },
        
        armies_by_level = {
            [1] = {
                unit_experience_amount = 2,
                units = { 
                    { "wh3_main_ksl_inf_armoured_kossars_0", 4, 100, 0, nil },
                    { "wh3_main_ksl_inf_kossars_1", 4, 100, 0, nil },
                    { "wh3_main_ksl_cav_horse_archers_0", 4, 100, 0, nil },
                }
            },
            [2] = {
                unit_experience_amount = 5,
                units = { 
                    { "wh3_main_ksl_inf_tzar_guard_0", 2, 100, 0, nil },
                    { "wh3_main_ksl_inf_armoured_kossars_0", 2, 100, 0, nil },
                    { "wh3_main_ksl_inf_kossars_1", 2, 100, 0, nil },
                    { "wh3_main_ksl_inf_ice_guard_0", 2, 100, 0, nil },
                    { "wh3_main_ksl_veh_light_war_sled_0", 3, 100, 0, nil },
                    { "wh3_main_ksl_inf_streltsi_0", 4, 100, nil }
                }
            },
            [3] = {
                unit_experience_amount = 7,
                units = {
                    { "wh3_main_ksl_inf_tzar_guard_0", 2, 100, 0, nil },
                    { "wh3_main_ksl_cav_war_bear_riders_1", 4, 100, 0, nil },
                    { "wh3_main_ksl_inf_streltsi_0", 3, 100, 0, nil },
                    { "wh3_main_ksl_inf_ice_guard_1", 8, 100, 0, nil },
                    { "wh3_main_ksl_veh_little_grom_0", 2, 100, nil }
                }
            }            
        }

    },

    ["wh3_main_sc_dae_daemons"] = {
        identifier = "defender_force",
        invasion_identifier = "defender_invasion",
        intervention_type = ALLIED_REINFORCEMENTS_PERMITTED_TYPE,
        lord = { 
            possible_subtypes = { 
                "wh3_main_tze_herald_of_tzeentch_metal"
            },
            level_ranges = { 20, 30 }, 
            possible_forenames = { },
            possible_clan_names = { }, 
            possible_family_names = { }, 
            skills = {
                ["wh3_main_tze_herald_of_tzeentch_metal"] = {
                    { name = "wh_main_skill_all_lord_battle_inspiring_presence", level = 1 },
                    { name = "wh3_main_skill_tze_lord_army_buff_1_1", level = 3 },
                    { name = "wh3_main_skill_tze_lord_army_buff_1_2", level = 3 },
                    { name = "wh3_main_skill_tze_lord_army_buff_1_3", level = 3 },
                    { name = "wh3_main_skill_tze_lord_army_buff_1_4", level = 3 },
                    { name = "wh3_main_skill_tze_lord_army_buff_1_5", level = 3 },
                    { name = "wh3_main_skill_tze_lord_army_buff_3_1", level = 1 },
                    { name = "wh3_main_skill_tze_lord_army_buff_3_2", level = 1 },
                    { name = "wh3_main_skill_tze_lord_army_buff_3_3", level = 1 },
                    { name = "wh3_main_skill_tze_lord_army_buff_3_4", level = 1 },
                    { name = "wh3_main_skill_tze_lord_army_master_of_fates", level = 1 },
                    { name = "wh2_main_skill_innate_all_disciplined", level = 1 },
                    { name = "wh_main_skill_all_magic_metal_01_searing_doom", level = 2 },
                    { name = "wh_main_skill_all_magic_metal_03_metalshifting", level = 1 },
                    { name = "wh2_main_skill_all_magic_metal_02_plague_of_rust_lord", level = 2 },
                    { name = "wh2_main_skill_all_magic_metal_04_glittering_robe_lord", level = 2 },
                    { name = "wh2_main_skill_all_magic_metal_05_gehennas_golden_hounds_lord", level = 2 },
                    { name = "wh3_main_skill_tze_all_magic_prismatic_plurality", level = 1 },
                    { name = "wh_main_skill_all_magic_all_07_earthing", level = 1 },
                    { name = "wh_main_skill_all_magic_all_08_power_drain", level = 1 },
                    { name = "wh2_main_skill_all_magic_metal_09_transmutation_of_lead_lord", level = 1 },
                    { name = "wh2_main_skill_all_magic_metal_10_final_transmutation_lord", level = 2 },
                    { name = "wh_main_skill_all_magic_all_11_arcane_conduit", level = 1 },
                    { name = "wh3_main_skill_tze_locus_of_change", level = 1 },
                    { name = "wh3_main_skill_tze_locus_of_conjuration", level = 1 },
                    { name = "wh3_main_skill_tze_locus_of_transmogrification", level = 1 },
                    { name = "wh3_main_skill_tze_all_unique_missile_resist", level = 1 },
                    { name = "wh3_main_skill_tze_generic_hates_nurgle", level = 1 }
                },
            },
            ancillaries = {},
            traits = {}
        },
        armies_by_level = {
            [1] = {
                unit_experience_amount = 2,
                units = {
                    { "wh3_main_nur_inf_plaguebearers_0", 4, 100, 0, nil },
                    { "wh3_main_kho_inf_bloodletters_0", 4, 100, 0, nil },
                    { "wh3_main_sla_inf_daemonette_0", 4, 100, 0, nil }
                }
            },
            [2] = {
                unit_experience_amount = 5,
                units = {
                    { "wh3_main_nur_inf_plaguebearers_0", 4, 100, 0, nil },
                    { "wh3_main_kho_inf_bloodletters_0", 4, 100, 0, nil },
                    { "wh3_main_sla_inf_daemonette_0", 4, 100, 0, nil },
                    { "wh3_main_tze_inf_pink_horrors_0", 3, 100, 0, nil }
                }
            },
            [3] = {
                unit_experience_amount = 7,
                units = {
                    { "wh3_main_nur_inf_plaguebearers_1", 4, 100, 0, nil },
                    { "wh3_main_kho_inf_bloodletters_1", 4, 100, 0, nil },
                    { "wh3_main_sla_inf_daemonette_1", 4, 100, 0, nil },
                    { "wh3_main_tze_inf_pink_horrors_0", 4, 100, 0, nil },
                    { "wh3_main_kho_mon_soul_grinder_0", 1, 100, 0, nil },
                    { "wh3_main_sla_mon_soul_grinder_0", 1, 100, 0, nil },
                    { "wh3_main_tze_mon_soul_grinder_0", 1, 100, 0, nil }
                }
            }
        }
    },

    ["wh3_main_sc_cth_cathay"] = {
        identifier = "defender_force",
        invasion_identifier = "defender_invasion",
        intervention_type = ALLIED_REINFORCEMENTS_PERMITTED_TYPE,
        lord = { 
            possible_subtypes = { 
                "wh3_main_cth_dragon_blooded_shugengan_yang"
            },
            level_ranges = { 20, 30 }, 
            possible_forenames = { },
            possible_clan_names = { }, 
            possible_family_names = { }, 
            skills = {
                ["wh3_main_cth_dragon_blooded_shugengan_yang"] = {
                    { name = "wh_main_skill_all_lord_battle_inspiring_presence", level = 1 },
                    { name = "wh3_main_skill_cth_lord_army_buff_1_1", level = 3 },
                    { name = "wh3_main_skill_cth_lord_army_buff_1_2", level = 3 },
                    { name = "wh3_main_skill_cth_lord_army_buff_1_3", level = 3 },
                    { name = "wh3_main_skill_cth_lord_army_buff_1_4", level = 3 },
                    { name = "wh3_main_skill_cth_lord_army_buff_1_5", level = 3 },
                    { name = "wh3_main_skill_cth_lord_army_buff_1_6", level = 3 },
                    { name = "wh3_main_skill_cth_lord_army_buff_3_1", level = 1 },
                    { name = "wh3_main_skill_cth_lord_army_buff_3_2", level = 1 },
                    { name = "wh3_main_skill_cth_lord_army_buff_3_3", level = 1 },
                    { name = "wh3_main_skill_cth_lord_army_buff_3_4", level = 1 },
                    { name = "wh_main_skill_all_lord_battle_stand_your_ground", level = 1 },
                    { name = "wh3_main_skill_cth_all_self_will_of_the_dragons", level = 1 },
                    { name = "wh3_main_skill_cth_all_unique_magic_resist", level = 1 },
                    { name = "wh3_main_skill_cth_all_unique_missile_resist", level = 1 },
                    { name = "wh3_main_skill_innate_cathay_3", level = 1 },
                    { name = "wh3_main_skill_cth_magic_yang_01_dragons_breath_lord", level = 2 },
                    { name = "wh3_main_skill_cth_magic_yang_02_jade_shield_lord", level = 2 },
                    { name = "wh3_main_skill_cth_magic_yang_03_wall_of_wind_and_fire_lord", level = 2 },
                    { name = "wh3_main_skill_cth_magic_yang_04_stone_ground_stance_lord", level = 1 },
                    { name = "wh3_main_skill_cth_magic_yang_05_strength_of_yang", level = 1 },
                    { name = "wh_main_skill_all_magic_all_06_evasion", level = 1 },
                    { name = "wh3_main_skill_cth_magic_yang_07_might_of_heaven_and_earth_lord", level = 2 },
                    { name = "wh3_main_skill_cth_magic_yang_08_constellation_of_the_dragon_lord", level = 2 },
                    { name = "wh_main_skill_all_magic_all_07_earthing", level = 1 },
                    { name = "wh_main_skill_all_magic_all_08_power_drain", level = 1 },
                    { name = "wh_main_skill_all_magic_all_11_arcane_conduit", level = 1 },
                    { name = "wh3_main_skill_cth_dragon_blooded_shugengan_self_life", level = 1 }
                },
            },
            ancillaries = {},
            traits = {}
        },
        armies_by_level = {
            [1] = {
                unit_experience_amount = 2,
                units = {
                    { "wh3_main_cth_inf_jade_warriors_0", 4, 100, 0, nil },
                    { "wh3_main_cth_inf_iron_hail_gunners_0", 4, 100, 0, nil },
                    { "wh3_main_cth_inf_peasant_archers_0", 4, 100, 0, nil }
                }
            },
            [2] = {
                unit_experience_amount = 5,
                units = {
                    { "wh3_main_cth_inf_jade_warriors_0", 4, 100, 0, nil },
                    { "wh3_main_cth_inf_jade_warrior_crossbowmen_1", 4, 100, 0, nil },
                    { "wh3_main_cth_inf_crane_gunners_0", 2, 100, 0, nil },
                    { "wh3_main_cth_art_grand_cannon_0", 3, 100, 0, nil },
                    { "wh3_main_cth_veh_war_compass_0", 1, 100, 0, nil },
                    { "wh3_main_cth_veh_sky_junk_0", 1, 100, 0, nil }
                }
            },
            [3] = {
                unit_experience_amount = 7,
                units = {
                    { "wh3_main_cth_inf_dragon_guard_0", 5, 100, 0, nil },
                    { "wh3_main_cth_mon_terracotta_sentinel_0", 2, 100, 0, nil },
                    { "wh3_main_cth_inf_crane_gunners_0", 2, 100, 0, nil },
                    { "wh3_main_cth_inf_dragon_guard_crossbowmen_0", 5, 100, 0, nil },
                    { "wh3_main_cth_art_grand_cannon_0", 3, 100, 0, nil },
                    { "wh3_main_cth_veh_sky_junk_0", 2, 100, 0, nil }
                }
            }
        }
    },
    
    ["wh3_main_sc_ogr_ogre_kingdoms"] = {
        identifier = "defender_force",
        invasion_identifier = "defender_invasion",
        intervention_type = ALLIED_REINFORCEMENTS_PERMITTED_TYPE,
        lord = { 
            possible_subtypes = { 
                "wh3_main_ogr_tyrant"
            },
            level_ranges = { 20, 30 }, 
            possible_forenames = { },
            possible_clan_names = { }, 
            possible_family_names = { }, 
            skills = {
                ["wh3_main_ogr_tyrant"] = {
                    { name = "wh_main_skill_all_lord_battle_inspiring_presence", level = 1 },
                    { name = "wh3_main_skill_ogr_army_buff_ogre_warriors", level = 3 },
                    { name = "wh3_main_skill_ogr_army_buff_gnoblars", level = 3 },
                    { name = "wh3_main_skill_ogr_army_buff_ogre_cavalry", level = 3 },
                    { name = "wh3_main_skill_ogr_army_buff_missiles", level = 3 },
                    { name = "wh3_main_skill_ogr_army_buff_elite_infantry", level = 3 },
                    { name = "wh3_main_skill_ogr_army_buff_monsters", level = 3 },
                    { name = "wh3_main_skill_ogr_army_buff_rank7_warriors_ironguts_gnoblars", level = 1 },
                    { name = "wh3_main_skill_ogr_army_buff_rank7_missiles", level = 1 },
                    { name = "wh3_main_skill_ogr_army_buff_rank7_ogre_cavalry", level = 1 },
                    { name = "wh3_main_skill_ogr_army_buff_rank7_ogre_monsters", level = 1 },
                    { name = "wh_main_skill_all_lord_battle_stand_your_ground", level = 1 },
                    { name = "wh3_main_skill_ogr_self_unstoppable_force", level = 1 },
                    { name = "wh2_dlc11_skill_all_lord_self_blade_master", level = 2 },
                    { name = "wh3_main_skill_ogr_self_healthy_appetite", level = 2 },
                    { name = "wh2_dlc11_skill_all_lord_self_wound-maker", level = 2 },
                    { name = "wh_main_skill_all_all_self_foe-seeker", level = 1 },
                    { name = "wh3_main_skill_ogr_self_dominant", level = 1 },
                    { name = "wh2_dlc11_skill_all_lord_self_devastating_charge", level = 2 },
                    { name = "wh3_main_skill_ogr_self_snacks", level = 1 },
                    { name = "wh3_main_skill_ogr_tyrant_unique_greater_girth", level = 1 },
                    { name = "wh3_main_skill_ogr_generic_melee_attack", level = 1 },
                    { name = "wh3_main_skill_ogr_all_unique_missile_resist", level = 1 },
                    { name = "wh3_main_skill_ogr_generic_physical_ward", level = 1 },
                    { name = "wh3_main_skill_ogr_generic_magic_ward", level = 1 },
                    { name = "wh3_main_skill_ogr_lord_battle_bellower", level = 1 },
                    { name = "wh2_main_skill_innate_all_disciplined", level = 1 },
                    { name = "wh3_main_skill_ogr_tyrant_unique_devour_challengers", level = 1 },
                    { name = "wh3_main_skill_ogr_tyrant_unique_absolute_violence", level = 1 },
                    { name = "wh3_main_skill_ogr_tyrant_unique_iron_discipline", level = 1 }
                },
            },
            ancillaries = {},
            traits = {}
        },
        armies_by_level = {
            [1] = {
                unit_experience_amount = 2,
                units = {
                    { "wh3_main_ogr_inf_ogres_1", 4, 100, 0, nil },
                    { "wh3_main_ogr_cav_mournfang_cavalry_0", 4, 100, 0, nil },
                    { "wh3_main_ogr_inf_maneaters_3", 4, 100, 0, nil }
                }
            },
            [2] = {
                unit_experience_amount = 5,
                units = {
                    { "wh3_main_ogr_inf_maneaters_2", 3, 100, 0, nil },
                    { "wh3_main_ogr_inf_maneaters_3", 3, 100, 0, nil },
                    { "wh3_main_ogr_cav_mournfang_cavalry_0", 4, 100, 0, nil },
                    { "wh3_main_ogr_inf_leadbelchers_0", 3, 100, 0, nil },
                    { "wh3_main_ogr_mon_stonehorn_0", 1, 100, 0, nil },
                    { "wh3_main_ogr_veh_gnoblar_scraplauncher_0", 1, 100, 0, nil }
                }                
            },
            [3] = {
                unit_experience_amount = 7,
                units = {
                    { "wh3_main_ogr_inf_ironguts_0", 4, 100, 0, nil },
                    { "wh3_main_ogr_inf_maneaters_3", 4, 100, 0, nil },
                    { "wh3_main_ogr_inf_leadbelchers_0", 4, 100, 0, nil },
                    { "wh3_main_ogr_mon_stonehorn_1", 4, 100, 0, nil },
                    { "wh3_main_ogr_veh_gnoblar_scraplauncher_0", 3, 100, 0, nil }
                }
            }
        }
    },
    
    ["wh3_main_sc_nur_nurgle"] = {
        identifier = "defender_force",
        invasion_identifier = "defender_invasion",
        intervention_type = ALLIED_REINFORCEMENTS_PERMITTED_TYPE,
        lord = { 
            possible_subtypes = { 
                "wh3_main_nur_exalted_great_unclean_one_nurgle"
            },
            level_ranges = { 20, 30 }, 
            possible_forenames = { },
            possible_clan_names = { }, 
            possible_family_names = { }, 
            skills = {
                ["wh3_main_nur_exalted_great_unclean_one_nurgle"] = {
                    { name = "wh_main_skill_all_lord_battle_inspiring_presence", level = 1 },
                    { name = "wh3_main_skill_nur_lord_army_buff_1_1", level = 3 },
                    { name = "wh3_main_skill_nur_lord_army_buff_1_2", level = 3 },
                    { name = "wh3_main_skill_nur_lord_army_buff_1_3", level = 3 },
                    { name = "wh3_main_skill_nur_lord_army_buff_1_4", level = 3 },
                    { name = "wh3_main_skill_nur_lord_army_buff_1_5", level = 3 },
                    { name = "wh3_main_skill_nur_lord_army_buff_3_1", level = 1 },
                    { name = "wh3_main_skill_nur_lord_army_buff_3_2", level = 1 },
                    { name = "wh3_main_skill_nur_lord_army_buff_3_3", level = 1 },
                    { name = "wh3_main_skill_nur_lord_army_buff_3_4", level = 1 },
                    { name = "wh3_main_skill_nur_lord_army_virulent_contagion", level = 1 },
                    { name = "wh2_dlc11_skill_all_lord_self_thick-skinned", level = 2 },
                    { name = "wh2_dlc11_skill_all_lord_self_hard_to_hit", level = 2 },
                    { name = "wh3_main_skill_nur_all_combat_fetid_stench", level = 1 },
                    { name = "wh2_dlc11_skill_all_lord_self_scarred_veteran", level = 2 },
                    { name = "wh2_dlc11_skill_all_lord_self_blade_shield", level = 2 },
                    { name = "wh3_main_skill_nur_all_combat_pestilent_decay", level = 1 },
                    { name = "wh2_main_skill_innate_all_disciplined", level = 1 },
                    { name = "wh3_main_skill_nur_magic_nurgle_01_miasma_of_pestilence_lord", level = 1 },
                    { name = "wh3_main_skill_nur_magic_nurgle_05_children_of_nurgle", level = 1 },
                    { name = "wh3_main_skill_nur_magic_nurgle_02_stream_of_corruption_lord", level = 1 },
                    { name = "wh3_main_skill_nur_magic_nurgle_03_curse_of_the_leper_lord", level = 2 },
                    { name = "wh3_main_skill_nur_magic_nurgle_04_rancid_visitations_lord", level = 2 },
                    { name = "wh_main_skill_all_magic_all_06_evasion", level = 1 },
                    { name = "wh_main_skill_all_magic_all_07_earthing", level = 1 },
                    { name = "wh_main_skill_all_magic_all_08_power_drain", level = 1 },
                    { name = "wh3_main_skill_nur_magic_nurgle_06_fleshy_abundance_lord", level = 2 },
                    { name = "wh3_main_skill_nur_magic_nurgle_07_blight_boil_lord", level = 2 },
                    { name = "wh_main_skill_all_magic_all_11_arcane_conduit", level = 1 },
                    { name = "wh3_main_skill_nur_generic_hates_tzeentch", level = 1 },
                    { name = "wh3_main_skill_nur_all_unique_missile_resist", level = 1 }
                },
            },
            ancillaries = {},
            traits = {}
        },
        armies_by_level = {
            [1] = {                
                unit_experience_amount = 2,
                units = {
                    { "wh3_main_nur_inf_nurglings_0", 4, 100, 0, nil },
                    { "wh3_main_nur_inf_plaguebearers_0", 4, 100, 0, nil },
                    { "wh3_main_nur_mon_plague_toads_0", 4, 100, 0, nil }
                }
            },
            [2] = {
                unit_experience_amount = 5,
                units = {
                    { "wh3_main_nur_inf_plaguebearers_0", 2, 100, 0, nil },
                    { "wh3_main_nur_inf_plaguebearers_1", 2, 100, 0, nil },
                    { "wh3_main_nur_inf_forsaken_0", 4, 100, 0, nil },
                    { "wh3_main_nur_mon_spawn_of_nurgle_0", 3, 100, 0, nil },
                    { "wh3_main_nur_mon_beast_of_nurgle_0", 3, 100, 0, nil },
                    { "wh3_main_nur_mon_soul_grinder_0", 1, 100, 0, nil }
                }                
            },
            [3] = {
                unit_experience_amount = 7,
                units = {
                    { "wh3_main_nur_inf_plaguebearers_1", 2, 100, 0, nil },
                    { "wh3_main_nur_cav_pox_riders_of_nurgle_0", 2, 100, 0, nil },
                    { "wh3_main_nur_cav_plague_drones_1", 2, 100, 0, nil },
                    { "wh3_main_nur_mon_great_unclean_one_0", 4, 100, 0, nil },
                    { "wh3_main_nur_mon_soul_grinder_0", 2, 100, 0, nil }                    
                }
            }
        }
    },

    ["wh3_main_sc_kho_khorne"] = {
        identifier = "defender_force",
        invasion_identifier = "defender_invasion",
        intervention_type = ALLIED_REINFORCEMENTS_PERMITTED_TYPE,
        lord = { 
            possible_subtypes = { 
                "wh3_main_kho_exalted_bloodthirster"
            },
            level_ranges = { 20, 30 }, 
            possible_forenames = { },
            possible_clan_names = { }, 
            possible_family_names = { }, 
            skills = {
                ["wh3_main_kho_exalted_bloodthirster"] = {
                    { name = "wh_main_skill_all_lord_battle_inspiring_presence", level = 1 },
                    { name = "wh3_main_skill_kho_lord_army_buff_1_1", level = 3 },
                    { name = "wh3_main_skill_kho_lord_army_buff_1_2", level = 3 },
                    { name = "wh3_main_skill_kho_lord_army_buff_1_3", level = 3 },
                    { name = "wh3_main_skill_kho_lord_army_buff_1_5", level = 3 },
                    { name = "wh3_main_skill_kho_lord_army_buff_1_6", level = 3 },
                    { name = "wh3_main_skill_kho_lord_army_buff_3_1", level = 1 },
                    { name = "wh3_main_skill_kho_lord_army_buff_3_2", level = 1 },
                    { name = "wh3_main_skill_kho_lord_army_buff_3_3", level = 1 },
                    { name = "wh3_main_skill_kho_lord_army_buff_3_4", level = 1 },
                    { name = "wh3_main_skill_kho_lord_army_revel_in_slaughter", level = 1 },
                    { name = "wh3_main_skill_kho_all_unique_magic_resist", level = 1 },
                    { name = "wh3_main_skill_kho_all_unique_missile_resist", level = 1 },
                    { name = "wh3_main_skill_kho_generic_hates_slaanesh", level = 1 },
                    { name = "wh2_main_skill_innate_all_disciplined", level = 1 },
                    { name = "wh3_main_skill_kho_all_self_brutal_charge", level = 1 },
                    { name = "wh3_main_skill_kho_lord_self_1_1", level = 1 },
                    { name = "wh3_main_skill_kho_lord_self_1_2", level = 2 },
                    { name = "wh3_main_skill_kho_exalted_bloodthirster_self_bloodthirst", level = 1 },
                    { name = "wh3_main_skill_kho_lord_self_3_1", level = 2 },
                    { name = "wh3_main_skill_kho_lord_self_3_2", level = 1 },
                    { name = "wh3_main_skill_kho_exalted_bloodthirster_self_deathbringer", level = 1 },
                    { name = "wh3_main_skill_kho_exalted_bloodthirster_self_unique_wrath", level = 1 },
                    { name = "wh3_main_skill_kho_exalted_bloodthirster_self_unique_fury", level = 1 },
                    { name = "wh3_main_skill_kho_exalted_bloodthirster_self_unique_rage", level = 1 }
                },
            },
            ancillaries = {},
            traits = {}
        },
        armies_by_level = {
            [1] = {
                unit_experience_amount = 2,
                units = {
                    { "wh3_main_kho_inf_bloodletters_0", 4, 100, 0, nil },
                    { "wh3_main_kho_inf_chaos_warriors_0", 4, 100, 0, nil },
                    { "wh3_main_kho_inf_chaos_warriors_1", 2, 100, 0, nil },
                    { "wh3_main_kho_inf_chaos_warriors_2", 2, 100, 0, nil }
                }
            },
            [2] = {
                unit_experience_amount = 5,
                units = {
                    { "wh3_main_kho_inf_bloodletters_0", 2, 100, 0, nil },
                    { "wh3_main_kho_inf_bloodletters_1", 4, 100, 0, nil },
                    { "wh3_main_kho_inf_flesh_hounds_of_khorne_0", 2, 100, 0, nil },
                    { "wh3_main_kho_mon_khornataurs_0", 2, 100, 0, nil },
                    { "wh3_main_kho_veh_skullcannon_0", 2, 100, 0, nil },
                    { "wh3_main_kho_cav_bloodcrushers_0", 3, 100, 0, nil },
                    { "wh3_main_kho_mon_soul_grinder_0", 1, 100, 0, nil }
                }
            },
            [3] = {
                unit_experience_amount = 7,
                units = {
                    { "wh3_main_kho_inf_bloodletters_1", 8, 100, 0, nil },
                    { "wh3_main_kho_veh_blood_shrine_0", 2, 100, 0, nil },
                    { "wh3_main_kho_veh_skullcannon_0", 2, 100, 0, nil },
                    { "wh3_main_kho_cav_skullcrushers_0", 2, 100, 0, nil },
                    { "wh3_main_kho_cav_gorebeast_chariot", 2, 100, 0, nil },
                    { "wh3_main_kho_mon_bloodthirster_0", 2, 100, 0, nil },
                    { "wh3_main_kho_mon_soul_grinder_0", 2, 100, 0, nil }
                }
            }
        }
    },

    ["wh3_main_sc_sla_slaanesh"] = {
        identifier = "defender_force",
        invasion_identifier = "defender_invasion",
        intervention_type = ALLIED_REINFORCEMENTS_PERMITTED_TYPE,
        lord = { 
            possible_subtypes = { 
                "wh3_main_sla_exalted_keeper_of_secrets_shadow"
            },
            level_ranges = { 20, 30 }, 
            possible_forenames = { },
            possible_clan_names = { }, 
            possible_family_names = { }, 
            skills = {
                ["wh3_main_sla_exalted_keeper_of_secrets_shadow"] = {
                    { name = "wh_main_skill_all_lord_battle_inspiring_presence", level = 1 },
                    { name = "wh3_main_skill_sla_lord_army_buff_1_1", level = 3 },
                    { name = "wh3_main_skill_sla_lord_army_buff_1_2", level = 3 },
                    { name = "wh3_main_skill_sla_lord_army_buff_1_3", level = 3 },
                    { name = "wh3_main_skill_sla_lord_army_buff_1_4", level = 3 },
                    { name = "wh3_main_skill_sla_lord_army_buff_1_5", level = 3 },
                    { name = "wh3_main_skill_sla_lord_army_buff_1_6", level = 3 },
                    { name = "wh3_main_skill_sla_lord_army_buff_3_1", level = 1 },
                    { name = "wh3_main_skill_sla_lord_army_buff_3_2", level = 1 },
                    { name = "wh3_main_skill_sla_lord_army_buff_3_3", level = 1 },
                    { name = "wh3_main_skill_sla_lord_army_buff_3_4", level = 1 },
                    { name = "wh3_main_skill_sla_lord_army_allure_of_slaanesh", level = 1 },
                    { name = "wh3_main_skill_sla_all_combat_speed", level = 1 },
                    { name = "wh2_dlc11_skill_all_lord_self_devastating_charge", level = 2 },
                    { name = "wh2_dlc11_skill_all_lord_self_deadly_blade", level = 2 },
                    { name = "wh_main_skill_all_all_self_foe-seeker", level = 1 },
                    { name = "wh2_dlc11_skill_all_lord_self_wound-maker", level = 2 },
                    { name = "wh2_dlc11_skill_all_lord_self_self_indomitable", level = 2 },
                    { name = "wh_main_skill_all_all_self_deadly_onslaught", level = 1 },
                    { name = "wh2_main_skill_innate_all_disciplined", level = 1 },
                    { name = "wh_dlc05_skill_magic_shadow_mystifying_miasma", level = 2 },
                    { name = "wh_dlc05_skill_magic_shadow_smoke_and_mirrors", level = 1 },
                    { name = "wh2_main_skill_magic_shadow_enfeebling_foe_lord", level = 2 },
                    { name = "wh2_main_skill_magic_shadow_the_withering_lord", level = 2 },
                    { name = "wh2_main_skill_magic_shadow_penumbral_pendulum_lord", level = 2 },
                    { name = "wh_main_skill_all_magic_all_06_evasion", level = 1 },
                    { name = "wh_main_skill_all_magic_all_07_earthing", level = 1 },
                    { name = "wh_main_skill_all_magic_all_08_power_drain", level = 1 },
                    { name = "wh2_main_skill_magic_shadow_pit_of_shades_lord", level = 2 },
                    { name = "wh2_main_skill_magic_shadow_okkams_mindrazor_lord", level = 2 },
                    { name = "wh_main_skill_all_magic_all_11_arcane_conduit", level = 1 },
                    { name = "wh3_main_skill_sla_exalted_keeper_of_secrets_unique_feasting_on_fear", level = 1 },
                    { name = "wh3_main_skill_sla_exalted_keeper_of_secrets_self_ballet_of_blows", level = 1 },
                    { name = "wh3_main_skill_sla_exalted_keeper_of_secrets_self_seductive_glory", level = 1 },
                    { name = "wh3_main_skill_sla_all_unique_missile_resist", level = 1 },
                    { name = "wh3_main_skill_sla_generic_hates_khorne", level = 1 }
                },
            },
            ancillaries = {},
            traits = {}
        },
        armies_by_level = {
            [1] = {
                unit_experience_amount = 2,
                units = {
                    { "wh3_main_sla_inf_marauders_0", 4, 100, 0, nil },
                    { "wh3_main_sla_cav_hellstriders_0", 4, 100, 0, nil },
                    { "wh3_main_sla_inf_daemonette_0", 4, 100, 0, nil }
                }
            },
            [2] = {
                unit_experience_amount = 5,
                units = {
                    { "wh3_main_sla_inf_marauders_2", 2, 100, 0, nil },
                    { "wh3_main_sla_inf_daemonette_0", 4, 100, 0, nil },
                    { "wh3_main_sla_inf_daemonette_1", 2, 100, 0, nil },
                    { "wh3_main_sla_cav_seekers_of_slaanesh_0", 4, 100, 0, nil },
                    { "wh3_main_sla_mon_fiends_of_slaanesh_0", 3, 100, 0, nil },
                    { "wh3_main_sla_mon_soul_grinder_0", 1, 100, 0, nil }
                }
            },
            [3] = {
                unit_experience_amount = 7,
                units = {
                    { "wh3_main_sla_inf_daemonette_1", 8, 100, 0, nil },
                    { "wh3_main_sla_mon_fiends_of_slaanesh_0", 4, 100, 0, nil },
                    { "wh3_main_sla_veh_exalted_seeker_chariot_0", 4, 100, 0, nil },
                    { "wh3_main_sla_mon_soul_grinder_0", 2, 100, 0, nil },
                    { "wh3_main_sla_mon_keeper_of_secrets_0", 2, 100, 0, nil }
                }
            }
        }
    },
    
    ["wh3_main_sc_tze_tzeentch"] = {
        identifier = "defender_force",
        invasion_identifier = "defender_invasion",
        intervention_type = ALLIED_REINFORCEMENTS_PERMITTED_TYPE,
        lord = { 
            possible_subtypes = { 
                "wh3_main_tze_exalted_lord_of_change_tzeentch"
            },
            level_ranges = { 20, 30 }, 
            possible_forenames = { },
            possible_clan_names = { }, 
            possible_family_names = { }, 
            skills = {
                ["wh3_main_tze_exalted_lord_of_change_tzeentch"] = {
                    { name = "wh_main_skill_all_lord_battle_inspiring_presence", level = 1 },
                    { name = "wh3_main_skill_tze_lord_army_buff_1_1", level = 3 },
                    { name = "wh3_main_skill_tze_lord_army_buff_1_2", level = 3 },
                    { name = "wh3_main_skill_tze_lord_army_buff_1_3", level = 3 },
                    { name = "wh3_main_skill_tze_lord_army_buff_1_4", level = 3 },
                    { name = "wh3_main_skill_tze_lord_army_buff_1_5", level = 3 },
                    { name = "wh3_main_skill_tze_lord_army_buff_3_1", level = 1 },
                    { name = "wh3_main_skill_tze_lord_army_buff_3_2", level = 1 },
                    { name = "wh3_main_skill_tze_lord_army_buff_3_3", level = 1 },
                    { name = "wh3_main_skill_tze_lord_army_buff_3_4", level = 1 },
                    { name = "wh3_main_skill_tze_lord_army_master_of_fates", level = 1 },
                    { name = "wh2_main_skill_innate_all_disciplined", level = 1 },
                    { name = "wh3_main_skill_tze_magic_tzeentch_01_blue_fire_of_tzeentch_lord", level = 2 },
                    { name = "wh3_main_skill_tze_magic_tzeentch_02_pink_fire_of_tzeentch_lord", level = 2 },
                    { name = "wh3_main_skill_tze_magic_tzeentch_03_glean_magic_lord", level = 1 },
                    { name = "wh3_main_skill_tze_magic_tzeentch_04_treason_of_tzeentch_lord", level = 1 },
                    { name = "wh3_main_skill_tze_magic_tzeentch_05_fires_of_change", level = 1 },
                    { name = "wh3_main_skill_tze_all_magic_prismatic_plurality", level = 1 },
                    { name = "wh_main_skill_all_magic_all_07_earthing", level = 1 },
                    { name = "wh_main_skill_all_magic_all_08_power_drain", level = 1 },
                    { name = "wh3_main_skill_tze_magic_tzeentch_06_tzeentchs_firestorm_lord", level = 2 },
                    { name = "wh3_main_skill_tze_magic_tzeentch_07_infernal_gateway_lord", level = 2 },
                    { name = "wh2_dlc14_skilll_all_magic_all_greater_arcane_conduit", level = 1 },
                    { name = "wh3_main_skill_tze_lord_unique_gaze_of_fate", level = 1 },
                    { name = "wh3_main_skill_tze_lord_unique_hidden_in_time", level = 1 },
                    { name = "wh3_main_skill_tze_all_unique_missile_resist", level = 1 },
                    { name = "wh3_main_skill_tze_generic_hates_nurgle", level = 1 }
                },
            },
            ancillaries = {},
            traits = {}
        },
        armies_by_level = {
            [1] = {
                unit_experience_amount = 2,
                units = {
                    { "wh3_main_tze_inf_forsaken_0", 2, 100, 0, nil },
                    { "wh3_main_tze_inf_blue_horrors_0", 6, 100, 0, nil },
                    { "wh3_main_tze_inf_pink_horrors_0", 2, 100, 0, nil },
                    { "wh3_main_tze_mon_flamers_0", 2, 100, 0, nil }
                }
            },
            [2] = {
                unit_experience_amount = 5,
                units = {
                    { "wh3_main_tze_inf_pink_horrors_0", 6, 100, 0, nil },
                    { "wh3_main_tze_mon_flamers_0", 2, 100, 0, nil },
                    { "wh3_main_tze_cav_doom_knights_0", 4, 100, 0, nil },
                    { "wh3_main_tze_cav_doom_knights_0", 3, 100, 0, nil },
                    { "wh3_main_tze_mon_soul_grinder_0", 1, 100, 0, nil }
                }
            },
            [3] = {
                unit_experience_amount = 7,
                units = {
                    { "wh3_main_tze_inf_pink_horrors_0", 8, 100, 0, nil },
                    { "wh3_main_tze_mon_flamers_0", 2, 100, 0, nil },
                    { "wh3_main_tze_veh_burning_chariot_0", 2, 100, 0, nil },
                    { "wh3_main_tze_cav_doom_knights_0", 4, 100, 0, nil },
                    { "wh3_main_tze_mon_soul_grinder_0", 2, 100, 0, nil },
                    { "wh3_main_tze_mon_lord_of_change_0", 2, 100, 0, nil }
                }
            }
        }
    },

    ["wh3_dlc23_chd_chaos_dwarfs"] = {
        identifier = "defender_force",
        invasion_identifier = "defender_invasion",
        intervention_type = ALLIED_REINFORCEMENTS_PERMITTED_TYPE,
        lord = { 
            possible_subtypes = { 
                "wh3_dlc23_chd_sorcerer_prophet_hashut"
            },
            level_ranges = { 20, 30 }, 
            possible_forenames = { },
            possible_clan_names = { }, 
            possible_family_names = { }, 
            skills = {
                ["wh3_dlc23_chd_sorcerer_prophet_hashut"] = {
                    { name = "wh_main_skill_all_lord_battle_inspiring_presence", level = 1 },
                    { name = "wh3_dlc23_skill_chd_army_buff_melee_labourer_hobgoblin", level = 3 },
                    { name = "wh3_dlc23_skill_chd_army_buff_melee_chaos_dwarfs", level = 3 },
                    { name = "wh3_dlc23_skill_chd_army_buff_missiles", level = 3 },
                    { name = "wh3_dlc23_skill_chd_army_buff_artillery", level = 3 },
                    { name = "wh3_dlc23_skill_chd_army_buff_bull_centaurs", level = 3 },
                    { name = "wh3_dlc23_skill_chd_army_buff_monsters_kdaai_skullcracker", level = 3 },
                    { name = "wh3_dlc23_skill_chd_army_buff_labourer_hobgoblin_rank7", level = 1 },
                    { name = "wh3_dlc23_skill_chd_army_buff_melee_chaos_dwarfs_rank7", level = 1 },
                    { name = "wh3_dlc23_skill_chd_army_buff_artillery_chaos_dwarf_missiles_rank7", level = 1 },
                    { name = "wh3_dlc23_skill_chd_army_buff_monsters_kdaai_skullcracker_bull_centaurs_rank7", level = 1 },
                    { name = "wh_main_skill_chs_lord_battle_stand_or_die", level = 1 },
                    { name = "wh3_dlc23_skill_chd_unyielding_command", level = 1 },
                    { name = "wh3_dlc23_skill_chd_sorcerer_prophet_careful_casting", level = 1 },
                    { name = "wh3_dlc23_skill_chd_hashuts_scales", level = 1 },
                    { name = "wh3_dlc23_skill_chd_headdress_of_zharr", level = 1 },
                    { name = "wh3_dlc23_skill_chd_lord_self_always_ready", level = 2 },
                    { name = "wh3_dlc23_skill_chd_lord_self_bandolier", level = 1 },
                    { name = "wh2_dlc11_skill_wef_lord_self_expeditious_endeavour", level = 2 },
                    { name = "wh3_dlc23_skill_chd_lord_self_piercing_shots", level = 2 },
                    { name = "wh_main_skill_all_all_self_foe-seeker", level = 1 },
                    { name = "wh3_dlc23_skill_innate_chd_lord_hero_shared_5_greedy", level = 1 },
                    { name = "wh3_dlc23_skill_chd_magic_hashut_01_burning_wrath_lord", level = 2 },
                    { name = "wh3_dlc23_skill_chd_magic_hashut_02_dark_subjugation_lord", level = 2 },
                    { name = "wh3_dlc23_skill_chd_magic_hashut_03_killing_fire", level = 1 },
                    { name = "wh3_dlc23_skill_chd_magic_hashut_04_ash_storm_lord", level = 2 },
                    { name = "wh3_dlc23_skill_chd_magic_hashut_05_curse_of_hashut_lord", level = 1 },
                    { name = "wh_main_skill_all_magic_all_06_evasion", level = 1 },
                    { name = "wh_main_skill_all_magic_all_07_earthing", level = 1 },
                    { name = "wh_main_skill_all_magic_all_08_power_drain", level = 1 },
                    { name = "wh3_dlc23_skill_chd_magic_hashut_06_hell_hammer_lord", level = 2 },
                    { name = "wh3_dlc23_skill_chd_magic_hashut_07_flames_of_azgorh_lord", level = 2 },
                    { name = "wh_main_skill_all_magic_all_11_arcane_conduit", level = 1 },
                    { name = "wh3_dlc23_skill_chd_sorcerer_prophet_thirsty_for_magic", level = 1 },
                    { name = "wh3_dlc23_skill_chd_sorcerer_prophet_flesh_sacrifice", level = 1 },
                    { name = "wh3_dlc23_skill_chd_sorcerer_prophet_voice_of_hashut", level = 1 }
                },
            },
            ancillaries = {},
            traits = {}
        },
        armies_by_level = {
            [1] = {
                unit_experience_amount = 2,
                units = {
                    { "wh3_dlc23_chd_inf_chaos_dwarf_warriors", 2, 100, 0, nil },
                    { "wh3_dlc23_chd_inf_hobgoblin_cutthroats", 6, 100, 0, nil },
                    { "wh3_dlc23_chd_inf_chaos_dwarf_blunderbusses", 2, 100, 0, nil },
                    { "wh3_dlc23_chd_cav_bull_centaurs_axe", 2, 100, 0, nil }
                }
            },
            [2] = {
                unit_experience_amount = 5,
                units = {
                    { "wh3_dlc23_chd_inf_hobgoblin_sneaky_gits", 3, 100, 0, nil },
                    { "wh3_dlc23_chd_cav_bull_centaurs_greatweapons", 2, 100, 0, nil },
                    { "wh3_dlc23_chd_mon_kdaai_fireborn", 2, 100, 0, nil },
                    { "wh3_dlc23_chd_inf_chaos_dwarf_warriors", 4, 100, 0, nil },
                    { "wh3_dlc23_chd_inf_chaos_dwarf_blunderbusses", 3, 100, 0, nil },
                    { "wh3_dlc23_chd_inf_infernal_guard_fireglaives", 2, 100, 0, nil }
                }
            },
            [3] = {
                unit_experience_amount = 7,
                units = {
                    { "wh3_dlc23_chd_inf_infernal_guard", 3, 100, 0, nil },
                    { "wh3_dlc23_chd_inf_infernal_ironsworn", 2, 100, 0, nil },
                    { "wh3_dlc23_chd_mon_kdaai_fireborn", 2, 100, 0, nil },
                    { "wh3_dlc23_chd_mon_kdaai_destroyer", 1, 100, 0, nil },
                    { "wh3_dlc23_chd_inf_chaos_dwarf_blunderbusses", 4, 100, 0, nil },
                    { "wh3_dlc23_chd_inf_infernal_guard_fireglaives", 4, 100, 0, nil },
                    { "wh3_dlc23_chd_veh_dreadquake_mortar", 2, 100, 0, nil },
                    { "wh_main_chs_art_hellcannon", 1, 100, 0, nil }
                }
            }
        }
    }

}

return smithy_defenders