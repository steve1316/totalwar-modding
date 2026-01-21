require("script/land_encounters/constants/utils/common")
------------------------------------------------------------------------------------
-- Daemonic Gifts: Thematic daemonic armies that gives an ancillary to your faction and an enemy faction or a huge give given you win. Marks the one that obtained the stuff with something and at the same time.
------------------------------------------------------------------------------------
return {
    -- Chainsword
    ["land_enc_dilemma_daemonic_gift_chainsword"] = {
        faction = "wh3_main_kho_khorne_qb1",
        identifier = "encounter_force",
        invasion_identifier = "encounter_invasion",
        intervention_type = INTERCEPTION_TYPE,
        lord = { 
            possible_subtypes = { 
                "wh3_main_kho_skarbrand",
            }, 
            level_ranges = {45, 50}, 
            possible_forenames = {},
            possible_clan_names = {}, 
            possible_family_names = {}, 
            ancillaries = {
                ["wh3_main_kho_skarbrand"] = {
                    { "wh3_main_anc_weapon_slaughter_and_carnage", 100 },
                    { "wh_main_anc_armour_tricksters_helm", 100 }
                }
            },
            traits = {
                ["wh3_main_kho_skarbrand"] = "land_encounters_trait_daemonic_gifts_skar_kho"
            }
        },
        unit_experience_amount = 9,
        units = { -- 19 units
            -- unit{id, quantity, appeareance_chance, alternative_chance, alternative}
            { "wh3_dlc20_kho_cha_cultist_mkho_warshrine", 1, 100, 0, nil }, -- 2
            { "wh3_main_kho_bloodreaper", 1, 100, 0, nil }, -- 3
            { "wh3_main_kho_mon_bloodthirster_0", 17, 100, 20, "wh3_main_kho_mon_soul_grinder_0" } -- 20
        },
        reinforcing_ally_armies = false,
        reinforcing_enemy_armies = {
            {
                faction = "wh3_main_kho_khorne_qb1",
                identifier = "encounter_force_reinforcement_first",
                invasion_identifier = "encounter_invasion_reinforcement_first",
                lord = { 
                    possible_subtypes = { 
                        "wh3_dlc20_chs_daemon_prince_khorne",
                        "wh3_main_kho_exalted_bloodthirster"
                    },
                    level_ranges = {15, 20}, 
                    possible_forenames = {},
                    possible_clan_names = {}, 
                    possible_family_names = {}, 
                    ancillaries = {},
                    traits = {}
                },
                unit_experience_amount = 1,
                units = {
                    -- unit{id, quantity, appeareance_chance, alternative_chance, alternative}
                    { "wh3_main_kho_mon_bloodthirster_0", 2, 100, 19, "wh3_main_kho_mon_soul_grinder_0" }, -- 4
                }
            }
        }
    },    
    -- The Bane Spear	
    ["land_enc_dilemma_daemonic_gift_the_bane_spear"] = {
        faction = "wh3_main_kho_khorne_qb1",
        identifier = "encounter_force",
        invasion_identifier = "encounter_invasion",
        intervention_type = INTERCEPTION_TYPE,
        lord = { 
            possible_subtypes = { 
                "wh3_dlc20_kho_valkia",
            }, 
            level_ranges = {45, 50}, 
            possible_forenames = {},
            possible_clan_names = {}, 
            possible_family_names = {}, 
            ancillaries = {
                ["wh3_dlc20_kho_valkia"] = {
                    { "wh3_dlc20_anc_weapon_the_spear_slaupnir", 100 },
                    { "wh3_dlc20_anc_armour_the_scarlet_armour", 100 },
                    { "wh3_dlc20_anc_enchanted_item_daemonshield", 100 },
                    { "wh_main_anc_talisman_talisman_of_preservation", 100 }
                }
            },
            traits = {
                ["wh3_dlc20_kho_valkia"] = "land_encounters_trait_daemonic_gifts_valk_kho"
            }
        },
        unit_experience_amount = 9,
        units = { -- 19 units
            -- unit{id, quantity, appeareance_chance, alternative_chance, alternative}
            { "wh3_dlc20_chs_exalted_hero_mkho", 2, 100, 0, nil }, -- 3
            { "wh3_dlc20_chs_mon_warshrine_mkho", 1, 100, 0, nil }, -- 4
            { "wh3_dlc20_kho_cav_skullcrushers_mkho_ror", 1, 100, 0, nil }, -- 8
            { "wh3_dlc20_kho_cav_skullcrushers_mkho_ror", 3, 100, 20, "wh3_main_kho_inf_bloodletters_1" }, -- 8
            { "wh3_twa06_kho_inf_bloodletters_ror_0", 1, 100, 0, nil }, -- 12
            { "wh3_main_kho_inf_bloodletters_1", 3, 100, 20, "wh3_dlc20_kho_cav_skullcrushers_mkho_ror" }, -- 12
            { "wh3_dlc20_chs_inf_chosen_mkho", 6, 100, 20, "wh_dlc06_chs_inf_aspiring_champions_0" }, -- 18
            { "wh_dlc06_chs_inf_aspiring_champions_0", 2, 100, 20, "wh3_dlc20_chs_inf_chosen_mkho" } -- 20
        },
        reinforcing_ally_armies = false,
        reinforcing_enemy_armies = {
            {
                faction = "wh3_main_kho_khorne_qb1",
                identifier = "encounter_force_reinforcement_first",
                invasion_identifier = "encounter_invasion_reinforcement_first",
                lord = { 
                    possible_subtypes = { 
                        "wh3_main_kho_exalted_bloodthirster"
                    },
                    level_ranges = {15, 20}, 
                    possible_forenames = {},
                    possible_clan_names = {}, 
                    possible_family_names = {}, 
                    ancillaries = {},
                    traits = {}
                },
                unit_experience_amount = 1,
                units = { 
                    -- unit{id, quantity, appeareance_chance, alternative_chance, alternative}
                    { "wh3_main_kho_veh_skullcannon_0", 2, 100, 10, "wh3_main_kho_mon_soul_grinder_0" }, -- 4
                    { "wh3_main_kho_veh_blood_shrine_0", 1, 100, 9, "wh3_main_kho_mon_bloodthirster_0" }
                }
            }
        }
    },
    -- Skar's Kraken-Killer	
    ["land_enc_dilemma_daemonic_gift_skars_kraken_killer"] = {
        faction = "wh3_main_kho_khorne_qb1",
        identifier = "encounter_force",
        invasion_identifier = "encounter_invasion",
        intervention_type = INTERCEPTION_TYPE,
        lord = { 
            possible_subtypes = { 
                "wh3_dlc20_chs_daemon_prince_khorne",
            }, 
            level_ranges = {45, 50}, 
            possible_forenames = {},
            possible_clan_names = {}, 
            possible_family_names = {}, 
            ancillaries = {
                ["wh3_dlc20_chs_daemon_prince_khorne"] = {
                    { "wh3_main_anc_armour_weird_plate", 100 },
                    { "wh_main_anc_weapon_obsidian_blade", 25 }
                }
            },
            traits = {
                ["wh3_dlc20_chs_daemon_prince_khorne"] = "land_encounters_trait_daemonic_gifts_dapk_kho"
            }
        },
        unit_experience_amount = 9,
        units = { -- 19 units
            -- unit{id, quantity, appeareance_chance, alternative_chance, alternative}
            { "wh3_main_kho_bloodreaper", 3, 100, 0, nil }, -- 4
            { "wh3_dlc20_chs_exalted_hero_mkho", 1, 100, 0, nil }, -- 5
            { "wh3_main_kho_mon_soul_grinder_0", 15, 100, 10, "wh3_main_kho_mon_bloodthirster_0" } -- 20
        },
        reinforcing_ally_armies = false,
        reinforcing_enemy_armies = {
            {
                faction = "wh3_main_kho_khorne_qb1",
                identifier = "encounter_force_reinforcement_first",
                invasion_identifier = "encounter_invasion_reinforcement_first",
                lord = { 
                    possible_subtypes = { 
                        "wh3_main_kho_exalted_bloodthirster"
                    },
                    level_ranges = {15, 20}, 
                    possible_forenames = {},
                    possible_clan_names = {}, 
                    possible_family_names = {}, 
                    ancillaries = {},
                    traits = {}
                },
                unit_experience_amount = 1,
                units = { 
                    -- unit{id, quantity, appeareance_chance, alternative_chance, alternative}
                    { "wh3_main_kho_inf_flesh_hounds_of_khorne_0", 2, 100, 10, "wh3_main_kho_mon_soul_grinder_0" }, -- 4
                    { "wh3_main_kho_inf_bloodletters_1", 2, 100, 10, "wh3_main_kho_mon_bloodthirster_0" }
                }
            }
        }
    },
    -- Gilellion's Soulnetter	
    ["land_enc_dilemma_daemonic_gift_gilellions_soulnetter"] = {
        faction = "wh_main_vmp_vampire_counts_qb1",
        identifier = "encounter_force",
        invasion_identifier = "encounter_invasion",
        intervention_type = ALLIED_REINFORCEMENTS_PERMITTED_TYPE,
        lord = { 
            possible_subtypes = { 
                "wh2_dlc11_vmp_bloodline_lahmian"
            }, 
            level_ranges = {45, 50}, 
            possible_forenames = {},
            possible_clan_names = {}, 
            possible_family_names = {}, 
            ancillaries = {
                ["wh2_dlc11_vmp_bloodline_lahmian"] = {
                    { "wh_main_anc_talisman_talisman_of_preservation", 100 },
                    { "wh_main_anc_armour_armour_of_destiny", 100 },
                    { "wh_main_anc_arcane_item_forbidden_rod", 100 }
                }
            },
            traits = {
                ["wh2_dlc11_vmp_bloodline_lahmian"] = "land_encounters_trait_daemonic_gifts_bldl_kho"
            }
        },
        unit_experience_amount = 9,
        units = { -- 19 units
            -- unit{id, quantity, appeareance_chance, alternative_chance, alternative}
            { "wh_dlc05_vmp_vampire_shadow", 1, 100, 0, nil }, -- 2
            { "wh_main_vmp_inf_grave_guard_1", 4, 100, 0, nil }, -- 6
            { "wh_main_vmp_mon_vargheists", 4, 100, 0, nil }, -- 10
            { "wh_dlc04_vmp_mon_devils_swartzhafen_0", 1, 100, 0, nil }, -- 11
            { "wh_main_vmp_mon_crypt_horrors", 4, 100, 0, nil }, -- 15
            { "wh_main_vmp_mon_varghulf", 3, 100, 0, nil }, -- 18
            { "wh_dlc02_vmp_cav_blood_knights_0", 2, 100, 0, nil } -- 20
        },
        reinforcing_ally_armies = {
            -- azzazel army
            {
                faction = "wh3_main_sla_slaanesh_qb1",
                identifier = "defender_force_reinforcement_first",
                invasion_identifier = "defender_invasion_reinforcement_first",
                lord = {
                    possible_subtypes = { 
                        "wh3_dlc20_sla_azazel",
                    }, 
                    level_ranges = {19, 20},
                    possible_forenames = {},
                    possible_clan_names = {}, 
                    possible_family_names = {}, 
                    ancillaries = {},
                    traits = {}
                },
                unit_experience_amount = 2,
                units = { -- 19 units
                    -- unit{id, quantity, appeareance_chance, alternative_chance, alternative}
                    { "wh3_dlc20_chs_sorcerer_slaanesh_msla", 1, 100, 0, nil }, -- 2
                    { "wh3_dlc20_chs_inf_chosen_msla", 3, 100, 0, nil }, -- 5
                    { "wh3_main_sla_inf_daemonette_1", 3, 100, 0, nil } -- 8
                }
            }
        },
        reinforcing_enemy_armies = {
            -- khorne army
            {
                faction = "wh3_main_kho_khorne_qb1",
                identifier = "encounter_force_reinforcement_first",
                invasion_identifier = "encounter_invasion_reinforcement_first",
                lord = { 
                    possible_subtypes = { 
                        "wh3_main_kho_exalted_bloodthirster",
                    },
                    level_ranges = {15, 20},
                    possible_forenames = {},
                    possible_clan_names = {}, 
                    possible_family_names = {}, 
                    ancillaries = {},
                    traits = {}
                },
                unit_experience_amount = 1,
                units = {
                    -- unit{id, quantity, appeareance_chance, alternative_chance, alternative}
                    { "wh3_dlc20_chs_exalted_hero_mkho", 2, 100, 0, nil }, -- 3
                    { "wh3_dlc20_chs_mon_warshrine_mkho", 1, 100, 0, nil }, -- 4
                    { "wh3_twa06_kho_inf_bloodletters_ror_0", 1, 100, 0, nil }, -- 7
                    { "wh3_dlc20_chs_inf_chosen_mkho", 2, 100, 0, nil }
                }
            }
        }
    },
    -- Slaanesh's Blade	
    ["land_enc_dilemma_daemonic_gift_slaaneshs_blade"] = {
        faction = "wh3_main_sla_slaanesh_qb1",
        identifier = "encounter_force",
        invasion_identifier = "encounter_invasion",
        intervention_type = INTERCEPTION_TYPE,
        lord = { 
            possible_subtypes = { 
                "wh_dlc01_chs_prince_sigvald",
            }, 
            level_ranges = {45, 50}, 
            possible_forenames = {},
            possible_clan_names = {}, 
            possible_family_names = {}, 
            ancillaries = {
                ["wh_dlc01_chs_prince_sigvald"] = {
                    { "wh_main_anc_weapon_sliverslash", 100 },
                    { "wh_main_anc_armour_auric_armour", 100 },
                    { "wh_main_anc_enchanted_item_the_other_tricksters_shard", 100 }
                }
            },
            traits = {
                ["wh_dlc01_chs_prince_sigvald"] = "land_encounters_trait_daemonic_gifts_sigv_sla"
            }
        },
        unit_experience_amount = 9,
        units = { -- 19 units
            -- unit{id, quantity, appeareance_chance, alternative_chance, alternative}
            { "wh3_dlc20_chs_sorcerer_shadows_msla", 1, 100, 0, nil }, -- 2
            { "wh3_main_sla_alluress_slaanesh", 1, 100, 0, nil }, -- 3
            { "wh3_main_sla_inf_daemonette_1", 4, 100, 0, nil }, -- 7
            { "wh3_dlc20_chs_inf_chosen_msla", 4, 100, 0, nil }, -- 11
            { "wh3_main_sla_veh_exalted_seeker_chariot_0", 2, 100, 0, nil }, -- 13
            { "wh3_main_sla_cav_heartseekers_of_slaanesh_0", 3, 100, 0, nil }, -- 17
            { "wh3_twa07_sla_cav_heartseekers_of_slaanesh_ror_0", 1, 100, 0, nil }, -- 18
            { "wh3_dlc20_chs_cav_chaos_chariot_msla_ror", 2, 100, 0, nil } -- 20
        },
        reinforcing_ally_armies = false,
        reinforcing_enemy_armies = {
            {
                faction = "wh3_main_sla_slaanesh_qb1",
                identifier = "encounter_force_reinforcement_first",
                invasion_identifier = "encounter_invasion_reinforcement_first",
                lord = { 
                    possible_subtypes = { 
                        "wh3_main_sla_exalted_keeper_of_secrets_slaanesh"
                    },
                    level_ranges = {15, 20},
                    possible_forenames = {},
                    possible_clan_names = {}, 
                    possible_family_names = {}, 
                    ancillaries = {},
                    traits = {}
                },
                unit_experience_amount = 1,
                units = { 
                    -- unit{id, quantity, appeareance_chance, alternative_chance, alternative}
                    { "wh3_main_sla_inf_daemonette_1", 2, 100, 10, "" }, -- 5
                    { "wh3_main_sla_veh_hellflayer_0", 2, 100, 10, "" }, -- 9
                }
            }
        }
    },
    -- Personal Sycophant
    ["land_enc_dilemma_daemonic_gift_personal_sycophant"] = {
        faction = "wh3_main_sla_slaanesh_qb1",
        identifier = "encounter_force",
        invasion_identifier = "encounter_invasion",
        intervention_type = INTERCEPTION_TYPE,
        lord = { 
            possible_subtypes = { 
                "wh3_main_sla_nkari",
            }, 
            level_ranges = {45, 50}, 
            possible_forenames = {},
            possible_clan_names = {}, 
            possible_family_names = {}, 
            ancillaries = {
                ["wh3_main_sla_nkari"] = {
                    { "wh3_main_anc_weapon_witstealer_sword", 100 },
                    { "wh_main_anc_talisman_talisman_of_preservation", 100 }
                }
            },
            traits = {
                ["wh3_main_sla_nkari"] = "land_encounters_trait_daemonic_gifts_nka_sla"
            }
        },
        unit_experience_amount = 9,
        units = { -- 19 units
            -- unit{id, quantity, appeareance_chance, alternative_chance, alternative}
            { "wh3_main_sla_alluress_slaanesh", 1, 100, 0, nil }, -- 2
            { "wh3_main_sla_alluress_shadow", 1, 100, 0, nil }, -- 3
            { "wh3_main_sla_mon_keeper_of_secrets_0", 17, 100, 0, nil }, -- 20
        },
        reinforcing_ally_armies = false,
        reinforcing_enemy_armies = {
            {
                faction = "wh3_main_sla_slaanesh_qb1",
                identifier = "encounter_force_reinforcement_first",
                invasion_identifier = "encounter_invasion_reinforcement_first",
                lord = { 
                    possible_subtypes = { 
                        "wh3_main_sla_exalted_keeper_of_secrets_shadow"
                    },
                    level_ranges = {15, 20}, 
                    possible_forenames = {},
                    possible_clan_names = {}, 
                    possible_family_names = {}, 
                    ancillaries = {},
                    traits = {}
                },
                unit_experience_amount = 1,
                units = { 
                    -- unit{id, quantity, appeareance_chance, alternative_chance, alternative}
                    { "wh2_dlc10_def_inf_sisters_of_slaughter", 2, 100, 10, "wh3_main_sla_mon_soul_grinder_0" }, -- 4
                    { "wh3_main_sla_inf_daemonette_1", 1, 100, 10, "wh3_main_sla_mon_keeper_of_secrets_0" } -- 6
                }
            }
        }
    },
    -- The Dark Prince's Paramour
    ["land_enc_dilemma_daemonic_gift_dark_princes_paramour"] = {
        faction = "wh3_main_sla_slaanesh_qb1",
        identifier = "encounter_force",
        invasion_identifier = "encounter_invasion",
        intervention_type = INTERCEPTION_TYPE,
        lord = { 
            possible_subtypes = { 
                "wh2_main_def_morathi",
            },
            level_ranges = {45, 50}, 
            possible_forenames = {},
            possible_clan_names = {},
            possible_family_names = {}, 
            ancillaries = {
                ["wh2_main_def_morathi"] = {
                    { "wh2_main_anc_weapon_heartrender_and_the_darksword", 100 },
                    { "wh2_main_anc_talisman_amber_amulet", 100 },
                    { "wh2_main_anc_arcane_item_wand_of_the_kharaidon", 100 },
                    { "wh_main_anc_armour_tricksters_helm", 100 }
                }
            },
            traits = {
                ["wh2_main_def_morathi"] = "land_encounters_trait_daemonic_gifts_mor_def"
            }
        },
        unit_experience_amount = 9,
        units = { -- 19 units
            -- unit{id, quantity, appeareance_chance, alternative_chance, alternative}
            { "wh3_main_sla_alluress_shadow", 1, 100, 0, nil }, -- 2
            { "wh2_main_def_sorceress_fire", 1, 100, 0, nil }, -- 3
            { "wh2_dlc10_def_cav_slaanesh_harvesters_ror_0", 2, 100, 0, nil }, -- 5
            { "wh2_dlc10_def_inf_sisters_of_the_singing_doom_ror_0", 1, 100, 0, nil }, -- 6
            { "wh2_dlc10_def_inf_sisters_of_slaughter", 3, 100, 0, nil }, -- 9
            { "wh2_dlc14_def_mon_bloodwrack_medusa_ror_0", 1, 100, 0, nil }, -- 10
            { "wh2_dlc14_def_veh_bloodwrack_shrine_0", 1, 100, 0, nil }, -- 11
            { "wh3_main_sla_inf_daemonette_1", 5, 100, 0, nil }, -- 16
            { "wh3_twa06_sla_inf_daemonette_ror_0", 1, 100, 0, nil }, -- 17
            { "wh3_main_sla_mon_keeper_of_secrets_0", 3, 100, 0, nil } -- 20
        },
        reinforcing_ally_armies = false,
        reinforcing_enemy_armies = {
            {
                faction = "wh3_main_sla_slaanesh_qb1",
                identifier = "encounter_force_reinforcement_first",
                invasion_identifier = "encounter_invasion_reinforcement_first",
                lord = { 
                    possible_subtypes = { 
                        "wh3_main_sla_exalted_keeper_of_secrets_slaanesh"
                    },
                    level_ranges = {15, 20}, 
                    possible_forenames = {},
                    possible_clan_names = {}, 
                    possible_family_names = {}, 
                    ancillaries = {},
                    traits = {}
                },
                unit_experience_amount = 1,
                units = { 
                    -- unit{id, quantity, appeareance_chance, alternative_chance, alternative}
                    { "wh3_main_sla_mon_fiends_of_slaanesh_0", 3, 100, 10, "wh3_main_sla_mon_keeper_of_secrets_0" },
                }
            }
        }
    }
}