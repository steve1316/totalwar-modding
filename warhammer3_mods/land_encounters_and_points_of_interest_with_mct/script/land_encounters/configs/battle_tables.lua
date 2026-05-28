-- battle_tables.lua references globals (e.g. faction constants, weapon constants) published by common.lua. Keep the require at the top so globals are in _G when the table literals below are evaluated.
require("script/land_encounters/utils/common")

local M = {}

--[[
Creates the battle forces to fight in the battles

Every force needs:
==================
BATTLE FORCE
==================
== DB
faction_agent_permitted_subtypes_tables (declares the hero units the faction can use [Reuse old factions in this case])
faction_rebellion_units_junctions_tables (declares the common units the faction can use)
(get names from campaign_rogue_army_leaders_table)
== LOC
None

--]]

------------------------------------------------------------------------------------
-- Bandits: The weakest forces, withouth heroes and low chances on dangerous units
------------------------------------------------------------------------------------
M.bandits = {

    -- Empire
    ["land_enc_dilemma_bandits_emp"] = {
        faction = "wh_main_emp_empire_qb1",
        identifier = "encounter_force",
        invasion_identifier = "encounter_invasion",
        intervention_type = INTERCEPTION_TYPE,
        lord = {
            possible_subtypes = {
                "wh_main_emp_lord",
                "wh2_dlc13_emp_cha_huntsmarshal"
            },
            level_ranges = {5, 20},
            possible_forenames = { "2048091270", "350864146", "1904032251", "2147357032", "2147344111", "2147357145", "2147357030", "2147357011", "2147355314" }, -- or names
            possible_clan_names = {},
            possible_family_names = { "2147356839", "2147356736", "2147356796", "2147356888", "2147354914" },
            ancillaries = {
                ["wh_main_emp_lord"] = {},
                ["wh2_dlc13_emp_cha_huntsmarshal"] = {}
            },
            traits = {
                ["wh_main_emp_lord"] = "land_encounters_trait_bandit_lord_emp",
                ["wh2_dlc13_emp_cha_huntsmarshal"] = "land_encounters_trait_bandit_hunt_emp"
            }
        },
        unit_experience_amount = 2,
        units = { -- 19 units
            -- unit{id, quantity, appeareance_chance, alternative_chance, alternative}
            { "wh_main_emp_inf_halberdiers", 4, 100, 0, nil }, -- 5
            { "wh_main_emp_inf_crossbowmen", 4, 100, 0, nil }, -- 9
            { "wh_main_emp_art_mortar", 2, 100, 0, nil }, -- 11 basic army (if lucky this will be the only army the player will need to beat for the reward
            { "wh2_dlc13_emp_inf_huntsmen_0", 2, 70, 30, "wh_main_emp_inf_greatswords" }, -- 13
            { "wh_main_emp_inf_handgunners", 2, 20, 20, "wh_main_emp_inf_crossbowmen" }, -- 15
            { "wh_main_emp_art_helstorm_rocket_battery", 2, 10, 20, "wh_main_emp_veh_steam_tank" }, -- 17
            { "wh_main_emp_cav_outriders_0", 1, 5, 5, "wh_main_emp_veh_steam_tank" }, -- 18
            { "wh_main_emp_art_great_cannon", 1, 5, 5, "wh_main_emp_art_helstorm_rocket_battery" }, -- 19
            { "wh_main_emp_art_helblaster_volley_gun", 1, 5, 5, "wh_main_emp_cav_demigryph_knights_0" } -- 20
        },
        reinforcing_ally_armies = false,
        reinforcing_enemy_armies = false
    },

    -- Wood Elves
    ["land_enc_dilemma_bandits_wef"] = {
        faction = "wh_dlc05_wef_wood_elves_qb1",
        identifier = "encounter_force",
        invasion_identifier = "encounter_invasion",
        intervention_type = INTERCEPTION_TYPE,
        lord = {
            possible_subtypes = {
                "wh_dlc05_wef_glade_lord",
                "wh2_dlc16_wef_spellweaver_life"
            },
            level_ranges = {5, 20},
            possible_forenames = { "2048091270" },
            possible_clan_names = {},
            possible_family_names = { "2147356839" },
            ancillaries = {
                ["wh_dlc05_wef_glade_lord"] = {},
                ["wh2_dlc16_wef_spellweaver_life"] = {}
            },
            traits = {
                ["wh_dlc05_wef_glade_lord"] = "land_encounters_trait_bandit_lord_wef",
                ["wh2_dlc16_wef_spellweaver_life"] = "land_encounters_trait_bandit_spell_wef"
            }
        },
        unit_experience_amount = 2,
        units = {
            { "wh_dlc05_wef_inf_glade_guard_0", 6, 100, 0, nil }, -- 7
            { "wh_dlc05_wef_inf_eternal_guard_0", 2, 100, 0, nil }, -- 9
            { "wh_dlc05_wef_cav_wild_riders_1", 2, 100, 0, nil }, -- 11 basic army
            { "wh_dlc05_wef_inf_dryads_0", 2, 20, 0, nil }, --  13
            { "wh_dlc05_wef_inf_deepwood_scouts_1", 2, 10, 50, "wh_dlc05_wef_cav_wild_riders_0" }, -- 15
            { "wh_dlc05_wef_inf_wardancers_0", 2, 5, 0, nil }, -- 17
            { "wh_dlc05_wef_inf_waywatchers_0", 2, 5, 60, "wh_dlc05_wef_inf_deepwood_scouts_0" },  -- 19
            { "wh_dlc05_wef_forest_dragon_0", 1, 1, 50, "wh_dlc05_wef_cha_ancient_treeman_0" } -- 20
        },
        reinforcing_ally_armies = false,
        reinforcing_enemy_armies = false
    },

    -- Norsca
    ["land_enc_dilemma_bandits_nor"] = {
        faction = "wh_main_nor_norsca_qb1",
        identifier = "encounter_force",
        invasion_identifier = "encounter_invasion",
        intervention_type = INTERCEPTION_TYPE,
        lord = {
            possible_subtypes = {
                "wh_main_nor_marauder_chieftain"
            },
            level_ranges = {5, 20},
            possible_forenames = {}, -- or names
            possible_clan_names = {},
            possible_family_names = {},
            skills = {},
            ancillaries = {
                ["wh_main_nor_marauder_chieftain"] = {}
            },
            traits = {
                ["wh_main_nor_marauder_chieftain"] = "land_encounters_trait_bandit_chief_nor"
            }
        },
        unit_experience_amount = 2,
        units = {
            { "wh_main_nor_cav_marauder_horsemen_0", 6, 100, 0, nil }, -- 7
            { "wh_dlc08_nor_inf_marauder_hunters_0", 4, 100, 0, nil}, -- 11 basic army
            { "wh_dlc08_nor_inf_marauder_berserkers_0", 2, 100, 2, "wh_dlc08_nor_mon_norscan_giant_0" }, -- 13
            { "wh_main_nor_cav_chaos_chariot", 2, 10, 0, nil  }, -- 15
            { "wh_dlc08_nor_mon_skinwolves_1", 2, 5, 50, "wh_main_nor_mon_chaos_warhounds_1" }, -- 17
            { "wh_dlc08_nor_mon_fimir_1", 2, 2, 0, nil }, -- 19
            { "wh_dlc08_nor_mon_war_mammoth_0", 1, 1, 0, nil } -- 20
        },
        reinforcing_ally_armies = false,
        reinforcing_enemy_armies = false
     },

    -- Chaos dwarfs
    ["land_enc_dilemma_bandits_chads"] = {
        faction = "wh3_dlc23_chd_chaos_dwarfs_qb1",
        identifier = "encounter_force",
        invasion_identifier = "encounter_invasion",
        intervention_type = INTERCEPTION_TYPE,
        lord = {
            possible_subtypes = {
                "wh3_dlc23_chd_overseer"
            },
            level_ranges = {5, 20},
            possible_forenames = {}, -- or names
            possible_clan_names = {},
            possible_family_names = {},
            skills = {},
            ancillaries = {
                ["wh3_dlc23_chd_overseer"] = {}
            },
            traits = {
                ["wh3_dlc23_chd_overseer"] = "land_encounters_trait_bandit_lord_chads"
            }
        },
        unit_experience_amount = 2,
        units = {
            -- unit{id, quantity, appeareance_chance, alternative_chance, alternative}
            { "wh3_dlc23_chd_cav_hobgoblin_wolf_raiders_bows", 6, 100, 0, nil }, -- 7
            { "wh3_dlc23_chd_inf_hobgoblin_archers", 4, 100, 0, nil}, -- 11 basic army
            { "wh3_dlc23_chd_inf_hobgoblin_cutthroats", 4, 40, 30, "wh3_dlc23_chd_inf_goblin_labourers" }, -- 15
            { "wh3_dlc23_chd_inf_hobgoblin_sneaky_gits", 4, 10, 3, nil  }, -- 19
        },
        reinforcing_ally_armies = false,
        reinforcing_enemy_armies = false
     },
}

------------------------------------------------------------------------------------
-- Battlefields: Thematic mid strength armies that can have legendary lords
------------------------------------------------------------------------------------
M.battlefields = {
    -- Greenskins
    ["land_enc_dilemma_battlefield_grn"] = {
        faction = "wh_main_grn_greenskins_qb1",
        identifier = "encounter_force",
        invasion_identifier = "encounter_invasion",
        intervention_type = INTERCEPTION_TYPE,
        lord = {
            possible_subtypes = {
                "wh_main_grn_goblin_great_shaman",
                "wh_dlc06_grn_skarsnik",
                "wh_dlc06_grn_wurrzag_da_great_prophet"
            },
            level_ranges = {25, 30},
            possible_forenames = {},
            possible_clan_names = {},
            possible_family_names = {},
            ancillaries = {
                ["wh_main_grn_goblin_great_shaman"] = {
                    { "wh_main_anc_weapon_battleaxe_of_the_last_waaagh", 100 },
                    { "wh_main_anc_talisman_talisman_of_preservation", 25 },
                },
                ["wh_dlc06_grn_skarsnik"] = {
                    { "wh_dlc06_anc_weapon_skarsniks_prodder", 100 },
                    { "wh_main_anc_enchanted_item_the_other_tricksters_shard", 100 },
                },
                ["wh_dlc06_grn_wurrzag_da_great_prophet"] = {
                    { "wh_dlc06_anc_weapon_bonewood_staff", 100 },
                    { "wh_dlc06_anc_enchanted_item_baleful_mask", 100 },
                    { "wh_dlc06_anc_arcane_item_squiggly_beast", 100 },
                    { "wh_main_anc_armour_armour_of_destiny", 100 },
                }
            },
            traits = {
                ["wh_main_grn_goblin_great_shaman"] = "land_encounters_trait_battlefield_ggs_grn",
                ["wh_dlc06_grn_skarsnik"] = "land_encounters_trait_battlefield_ska_grn",
                ["wh_dlc06_grn_wurrzag_da_great_prophet"] = "land_encounters_trait_battlefield_wur_grn"
            }
        },
        unit_experience_amount = 5,
        units = {
            { "wh2_dlc15_grn_mon_river_trolls_ror_0", 1, 100, 0, nil }, -- 2
            { "wh2_dlc15_grn_mon_river_trolls_0", 5, 100, 0, nil }, -- 10
            { "wh2_dlc15_grn_mon_stone_trolls_0", 4, 100, 0, nil }, -- 6
            { "wh2_dlc15_grn_veh_snotling_pump_wagon_ror_0", 2, 100, 0, nil}, -- 11
            { "wh2_dlc15_grn_veh_snotling_pump_wagon_roller_0", 2, 100, 0, nil}, -- 13
            { "wh_main_grn_mon_arachnarok_spider_0", 3, 90, 0, nil}, -- 19
            { "wh_dlc15_grn_mon_arachnarok_spider_waaagh_0", 1, 80, 0, nil } -- 20 Should be one. Testing with 5 if it generates 2 armies
        },
        reinforcing_ally_armies = false,
        reinforcing_enemy_armies = false
    },

    -- Dark Elves (W)
    ["land_enc_dilemma_battlefield_def"] = {
        faction = "wh2_main_def_dark_elves_qb1",
        identifier = "encounter_force",
        invasion_identifier = "encounter_invasion",
        intervention_type = INTERCEPTION_TYPE,
        lord = {
            possible_subtypes = {
                "wh2_dlc10_def_supreme_sorceress_fire",
                "wh2_main_def_malekith",
                "wh2_dlc14_def_malus_darkblade",
                -- lokhir fellheart
                -- crone hellebron
            },
            level_ranges = {40, 50},
            possible_forenames = {},
            possible_clan_names = {},
            possible_family_names = {},
            ancillaries = {
                ["wh2_dlc10_def_supreme_sorceress_fire"] = {
                    { "wh2_main_anc_armour_armour_of_living_death", 100 },
                    { "wh2_dlc15_anc_arcane_item_black_dragon_special", 50 }
                },
                ["wh2_main_def_malekith"] = {
                    { "wh2_main_anc_armour_armour_of_midnight", 100 },
                    { "wh2_main_anc_arcane_item_circlet_of_iron", 100 },
                    { "wh2_main_anc_weapon_destroyer", 100 },
                    { "wh2_main_anc_enchanted_item_supreme_spellshield", 100 },
                    { "wh_main_anc_talisman_talisman_of_preservation", 100 },
                },
                ["wh2_dlc14_def_malus_darkblade"] = {
                    { "wh2_dlc14_anc_weapon_warpsword_of_khaine", 100 },
                    { "wh_main_anc_armour_armour_of_destiny", 100 },
                    { "wh2_dlc14_anc_enchanted_item_malus_octagon_medallion", 100 },
                    { "wh2_dlc14_anc_talisman_malus_idol_of_darkness", 100 }
                }
            },
            traits = {
                ["wh2_dlc10_def_supreme_sorceress_fire"] = "land_encounters_trait_battlefield_ssf_def",
                ["wh2_main_def_malekith"] = "land_encounters_trait_battlefield_mal_def",
                ["wh2_dlc14_def_malus_darkblade"] = "land_encounters_trait_battlefield_mdb_def"
            }
        },
        unit_experience_amount = 5,
        units = {
            { "wh2_main_def_inf_shades_2", 4, 100, 0, nil }, -- 7
            { "wh2_main_def_inf_black_guard_0", 2, 100, 0, nil }, -- 9
            { "wh2_dlc14_def_cav_scourgerunner_chariot_ror_0", 2, 100, 0, nil}, -- 11 basic army
            { "wh2_main_def_inf_shades_0", 2, 100, 10, "wh2_main_def_inf_shades_2" }, -- 14
            { "wh2_main_def_inf_shades_1", 2, 100, 10, "wh2_dlc10_def_inf_sisters_of_slaughter" }, -- 16
            { "wh2_main_def_cav_cold_one_knights_1", 2, 90, 0, nil }, -- 18
            { "wh2_main_def_mon_war_hydra", 2, 80, 30, "wh2_main_def_mon_black_dragon" } -- 20 Used to be 2
        },
        reinforcing_ally_armies = false,
        reinforcing_enemy_armies = false
    },

    -- Vampires
    ["land_enc_dilemma_battlefield_vmp"] = {
        faction = "wh_main_vmp_vampire_counts_qb1",
        identifier = "encounter_force",
        invasion_identifier = "encounter_invasion",
        intervention_type = INTERCEPTION_TYPE,
        lord = {
            possible_subtypes = {
                "wh_dlc04_vmp_helman_ghorst",
                "wh_dlc04_vmp_vlad_con_carstein",
                "wh_pro02_vmp_isabella_von_carstein",
                "wh_main_vmp_heinrich_kemmler",
                "wh2_dlc11_vmp_bloodline_necrarch"
            },
            level_ranges = {40, 50},
            possible_forenames = {},
            possible_clan_names = {},
            possible_family_names = {},
            ancillaries = {
                ["wh_dlc04_vmp_helman_ghorst"] = {
                    { "wh_dlc04_anc_arcane_item_the_liber_noctus", 100 },
                    { "wh_main_anc_talisman_talisman_of_preservation", 100 },
                },
                ["wh_dlc04_vmp_vlad_con_carstein"] = {
                    { "wh_dlc04_anc_weapon_blood_drinker", 100 },
                    { "wh_dlc04_anc_talisman_the_carstein_ring", 100 },
                    { "wh_main_anc_enchanted_item_the_other_tricksters_shard", 100 },

                },
                ["wh_pro02_vmp_isabella_von_carstein"] = {
                    { "wh_pro02_anc_enchanted_item_blood_chalice_of_bathori", 100 },
                    { "wh_main_anc_weapon_obsidian_blade", 100 },
                },
                ["wh_main_vmp_heinrich_kemmler"] = {
                    { "wh_main_anc_weapon_chaos_tomb_blade", 100 },
                    { "wh_main_anc_enchanted_item_cloak_of_mists_and_shadows", 100 },
                    { "wh_main_anc_arcane_item_skull_staff", 100 },
                    { "wh_main_anc_armour_armour_of_destiny", 100 },

                },
                ["wh2_dlc11_vmp_bloodline_necrarch"] = {
                    { "wh_main_anc_arcane_item_forbidden_rod", 100 },
                    { "wh_main_anc_armour_armour_of_destiny", 25 },
                }
            },
            traits = {
                ["wh_dlc04_vmp_helman_ghorst"] = "land_encounters_trait_battlefield_hel_vmp",
                ["wh_dlc04_vmp_vlad_con_carstein"] = "land_encounters_trait_battlefield_vlad_vmp",
                ["wh_pro02_vmp_isabella_von_carstein"] = "land_encounters_trait_battlefield_isa_vmp",
                ["wh_main_vmp_heinrich_kemmler"] = "land_encounters_trait_battlefield_hei_vmp",
                ["wh2_dlc11_vmp_bloodline_necrarch"] = "land_encounters_trait_battlefield_nec_vmp"
            }
        },
        unit_experience_amount = 5,
        units = { -- 19 units
            { "wh_main_vmp_mon_crypt_horrors", 4, 100, 0, nil }, -- 5
            { "wh2_dlc11_vmp_inf_handgunners", 4, 100, 0, nil }, -- 9
            { "wh_dlc02_vmp_cav_blood_knights_0", 2, 100, 0, nil }, -- 11 basic army (if lucky this will be the only army the player will need to beat for the reward
            { "wh_main_vmp_mon_varghulf", 2, 100, 20, "wh_main_vmp_mon_vargheists" }, -- 13
            { "wh_main_vmp_mon_vargheists", 2, 100, 30, "wh_dlc02_vmp_cav_blood_knights_0" }, -- 15
            { "wh_dlc02_vmp_cav_blood_knights_0", 1, 100, 20, "wh_main_vmp_mon_vargheists" }, -- 17
            { "wh_dlc04_vmp_mon_devils_swartzhafen_0", 1, 100, 5, "wh_main_vmp_mon_varghulf" }, -- 18
            { "wh_main_vmp_cav_hexwraiths", 1, 90, 5, "wh_dlc02_vmp_cav_blood_knights_0" }, -- 19
            { "wh_dlc04_vmp_cav_chillgheists_0", 1, 80, 5, "wh_main_vmp_cav_hexwraiths" } -- 20
        },
        reinforcing_ally_armies = false,
        reinforcing_enemy_armies = false
    },

    -- Tomb Kings
    ["land_enc_dilemma_battlefield_tmb"] = {
        faction = "wh2_dlc09_tmb_tombking_qb1",
        identifier = "encounter_force",
        invasion_identifier = "encounter_invasion",
        intervention_type = INTERCEPTION_TYPE,
        lord = {
            possible_subtypes = {
                "wh2_dlc09_tmb_tomb_king",
                "wh2_dlc09_tmb_khatep"
            },
            level_ranges = {40, 50},
            possible_forenames = {},
            possible_clan_names = {},
            possible_family_names = {},
            ancillaries = {
                ["wh2_dlc09_tmb_tomb_king"] = {
                    { "wh2_dlc09_anc_armour_armour_of_eternity", 100 },
                    { "wh_main_anc_talisman_talisman_of_preservation", 25 }
                },
                ["wh2_dlc09_tmb_khatep"] = {
                    { "wh2_dlc09_anc_arcane_item_the_liche_staff", 100 },
                    { "wh_main_anc_talisman_talisman_of_preservation", 100 }
                }
            },
            traits = {
                ["wh2_dlc09_tmb_tomb_king"] = "land_encounters_trait_battlefield_tok_tmb",
                ["wh2_dlc09_tmb_khatep"] = "land_encounters_trait_battlefield_kha_tmb"
            }
        },
        unit_experience_amount = 5,
        units = { -- 19 units
            -- unit{id, quantity, appeareance_chance, alternative_chance, alternative}
            { "wh2_dlc09_tmb_inf_tomb_guard_0", 2, 100, 0, nil }, -- 3
            { "wh2_dlc09_tmb_inf_tomb_guard_1", 2, 100, 30, "wh2_dlc09_tmb_inf_skeleton_archers_0" }, -- 5
            { "wh2_dlc09_tmb_inf_skeleton_archers_0", 2, 100, 0, nil }, -- 7
            { "wh2_dlc09_tmb_inf_skeleton_archers_ror", 1, 100, 1, "wh2_dlc09_tmb_art_casket_of_souls_0" }, -- 8
            { "wh2_dlc09_tmb_art_casket_of_souls_0", 2, 100, 0, nil }, -- 10
            { "wh2_dlc09_tmb_mon_necrosphinx_0", 2, 100, 20, "wh2_dlc09_tmb_inf_tomb_guard_1" }, -- 12
            { "wh2_dlc09_tmb_mon_tomb_scorpion_0", 4, 100, 20, "wh2_dlc09_tmb_mon_necrosphinx_0" }, -- 16
            { "wh2_dlc09_tmb_veh_khemrian_warsphinx_0", 1, 90, 5, "wh2_dlc09_tmb_mon_tomb_scorpion_0" }, -- 18
            { "wh2_dlc09_tmb_mon_necrosphinx_ror", 1, 80, 5, "wh2_dlc09_tmb_veh_khemrian_warsphinx_0" } -- 20
        },
        reinforcing_ally_armies = false,
        reinforcing_enemy_armies = false
    },

    -- Dwarfs
    ["land_enc_dilemma_battlefield_dwf"] = {
        faction = "wh_main_dwf_dwarfs_qb1",
        identifier = "encounter_force",
        invasion_identifier = "encounter_invasion",
        intervention_type = INTERCEPTION_TYPE,
        lord = {
            possible_subtypes = {
                "wh2_pro08_neu_gotrek"
            },
            level_ranges = {20, 30},
            possible_forenames = {},
            possible_clan_names = {},
            possible_family_names = {},
            ancillaries = {
                ["wh2_pro08_neu_gotrek"] = {
                    { "wh2_pro08_anc_weapon_gotrek_axe", 100 },
                    { "wh_main_anc_enchanted_item_healing_potion", 100 }
                }
            },
            traits = {
                ["wh2_pro08_neu_gotrek"] = "land_encounters_trait_battlefield_got_dwf"
            }
        },
        unit_experience_amount = 5,
        units = { -- 19 units
            -- unit{id, quantity, appeareance_chance, alternative_chance, alternative}
            { "wh2_pro08_neu_felix", 1, 100, 0, nil }, -- 2
            { "wh2_dlc10_dwf_inf_giant_slayers", 4, 100, 30, "wh_main_dwf_inf_slayers" }, -- 5
            { "wh2_dlc10_dwf_inf_giant_slayers", 4, 100, 30, "wh_main_dwf_inf_slayers" }, -- 9 basic army (if lucky this will be
            { "wh2_dlc10_dwf_inf_giant_slayers", 4, 100, 30, "wh_main_dwf_inf_slayers" }, -- 13
            { "wh2_dlc10_dwf_inf_giant_slayers", 4, 100, 30, "wh_main_dwf_inf_slayers" }, -- 17
        },
        reinforcing_ally_armies = false,
        reinforcing_enemy_armies = false
    },

    -- a Bretonnia battle
    -- repanse
    -- the fay

}

M.caravans = {

    -- Cathay
    ["land_enc_dilemma_caravans_cathay"] = {
        faction = "wh3_main_cth_cathay_qb1",
        identifier = "encounter_force",
        invasion_identifier = "encounter_invasion",
        intervention_type = INTERCEPTION_TYPE,
        lord = {
            possible_subtypes = {
                "wh3_dlc24_cth_celestial_general_yin",
                "wh3_main_cth_lord_magistrate_yin",
                "wh3_main_cth_zhao_ming"
            },
            level_ranges = {40, 50},
            possible_forenames = { "2048091270", "350864146", "1904032251", "2147357032", "2147344111", "2147357145", "2147357030", "2147357011", "2147355314" }, -- or names
            possible_clan_names = {},
            possible_family_names = { "2147356839", "2147356736", "2147356796", "2147356888", "2147354914" },
            ancillaries = {
                ["wh3_dlc24_cth_celestial_general_yin"] = {},
                ["wh3_main_cth_lord_magistrate_yin"] = {},
                ["wh3_main_cth_zhao_ming"] = {}
            },
            traits = {
                ["wh3_dlc24_cth_celestial_general_yin"] = "",
                ["wh3_main_cth_lord_magistrate_yin"] = "",
                ["wh3_main_cth_zhao_ming"] = ""
            }
        },
        unit_experience_amount = 2,
        units = { -- 19 units
            -- unit{id, quantity, appeareance_chance, alternative_chance, alternative}
            { "wh3_main_cth_inf_dragon_guard_0", 4, 100, 0, nil }, -- 5
            { "wh3_main_cth_inf_dragon_guard_crossbowmen_0", 4, 100, 0, nil }, -- 9
            { "", 2, 100, 0, nil }, -- 11 basic army (if lucky this will be the only army the player will need to beat for the reward
            { "", 2, 70, 30, "" }, -- 13
            { "", 2, 20, 20, "" }, -- 15
            { "", 2, 10, 20, "" }, -- 17
            { "wh3_main_cth_art_fire_rain_rocket_battery_0", 1, 5, 5, "" }, -- 18
            { "wh3_main_cth_art_grand_cannon_0", 1, 5, 5, "" }, -- 19
            { "wh3_main_cth_veh_sky_junk_0", 1, 5, 5, "" } -- 20
        },
        reinforcing_ally_armies = false,
        reinforcing_enemy_armies = false
    },

    -- Chaos dwarfs
    ["land_enc_dilemma_caravans_chads"] = {
        faction = "wh3_dlc23_chd_chaos_dwarfs_qb1",
        identifier = "encounter_force",
        invasion_identifier = "encounter_invasion",
        intervention_type = INTERCEPTION_TYPE,
        lord = {
            possible_subtypes = {
                "wh3_dlc23_chd_overseer",
            },
            level_ranges = {5, 20},
            possible_forenames = { "2048091270" },
            possible_clan_names = {},
            possible_family_names = { "2147356839" },
            ancillaries = {
                ["wh3_dlc23_chd_overseer"] = {},
            },
            traits = {
                ["wh3_dlc23_chd_overseer"] = "",
            }
        },
        unit_experience_amount = 2,
        units = {
            { "", 6, 100, 0, nil }, -- 7
            { "", 2, 100, 0, nil }, -- 9
            { "", 2, 100, 0, nil }, -- 11 basic army
            { "", 2, 20, 0, nil }, --  13
            { "", 2, 10, 50, "" }, -- 15
            { "", 2, 5, 0, nil }, -- 17
            { "", 2, 5, 60, "" },  -- 19
            { "", 1, 1, 50, "" } -- 20
        },
        reinforcing_ally_armies = false,
        reinforcing_enemy_armies = false
    },

    -- Empire

    -- Kislev
}

------------------------------------------------------------------------------------
-- Daemonic Gifts: Thematic daemonic armies that gives an ancillary to your faction and an enemy faction or a huge give given you win. Marks the one that obtained the stuff with something and at the same time.
------------------------------------------------------------------------------------
M.daemonic_gifts = {
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

------------------------------------------------------------------------------------
-- Incursions: Small invasions of stronger races with better armies
------------------------------------------------------------------------------------
M.incursions = {
    -- High Elves
    ["land_enc_dilemma_incursion_army_hef"] = {
        faction = "wh2_main_hef_high_elves_qb1",
        identifier = "encounter_force",
        invasion_identifier = "encounter_invasion",
        intervention_type = INTERCEPTION_TYPE,
        lord = {
            possible_subtypes = {
                "wh2_dlc15_hef_archmage_life",
                "wh2_dlc15_hef_eltharion"
            },
            level_ranges = {20, 30},
            possible_forenames = {}, -- or names
            possible_clan_names = {},
            possible_family_names = {},
            ancillaries = {
                ["wh2_dlc15_hef_archmage_life"] = {
                    { "wh2_main_anc_arcane_item_the_gem_of_sunfire", 100 },
                    { "wh_main_anc_armour_armour_of_destiny", 25 },
                },
                ["wh2_dlc15_hef_eltharion"] = {
                    { "wh2_dlc15_anc_weapon_fangsword_of_eltharion", 100 },
                    { "wh2_dlc15_anc_armour_helm_of_yvresse", 100 },
                    { "wh2_dlc15_anc_talisman_talisman_of_hoeth", 100 },
                    { "wh_main_anc_enchanted_item_the_other_tricksters_shard", 100 }
                }
            },
            traits = {
                ["wh2_dlc15_hef_archmage_life"] = "land_encounters_trait_incursion_arch_hef",
                ["wh2_dlc15_hef_eltharion"] = "land_encounters_trait_incursion_elt_hef"
            }
        },
        unit_experience_amount = 3,
        units = {
            { "wh2_main_hef_inf_lothern_sea_guard_0", 6, 100, 0, nil }, -- 7
            { "wh2_main_hef_inf_white_lions_of_chrace_0", 4, 100, 0, nil}, -- 11 basic army
            { "wh2_main_hef_art_eagle_claw_bolt_thrower", 2, 100, 50, "wh2_main_hef_cav_tiranoc_chariot" }, -- 13

            { "wh2_main_hef_inf_swordmasters_of_hoeth_0", 2, 50, 10, "wh2_main_hef_inf_lothern_sea_guard_1" }, -- 15
            { "wh2_main_hef_cav_ithilmar_chariot", 1, 40, 30, "wh2_main_hef_mon_moon_dragon" }, -- 17
            { "wh2_main_hef_mon_phoenix_flamespyre", 1, 30, 50, "wh2_main_hef_mon_phoenix_frostheart" }, -- 19
            { "wh2_main_hef_mon_star_dragon", 1, 20, 0, nil } -- 18
        },
        reinforcing_ally_armies = false,
        reinforcing_enemy_armies = false
    },

    -- Lizardmen
    ["land_enc_dilemma_incursion_army_lzd"] = {
        faction = "wh2_main_lzd_lizardmen_qb1",
        identifier = "encounter_force",
        invasion_identifier = "encounter_invasion",
        intervention_type = INTERCEPTION_TYPE,
        lord = {
            possible_subtypes = {
                "wh2_main_lzd_saurus_old_blood",
                "wh2_dlc12_lzd_tiktaqto",
                "wh2_dlc13_lzd_nakai"
            },
            level_ranges = {20, 30},
            possible_forenames = {},
            possible_clan_names = {},
            possible_family_names = {},
            ancillaries = {
                ["wh2_main_lzd_saurus_old_blood"] = {
                    { "wh2_main_anc_enchanted_item_divine_plaque_of_protection", 100 },
                    { "wh_main_anc_talisman_talisman_of_preservation", 25 }
                },
                ["wh2_dlc12_lzd_tiktaqto"] = {
                    { "wh2_dlc12_anc_weapon_the_blade_of_ancient_skies", 100 },
                    { "wh2_dlc12_anc_enchanted_item_mask_of_heavens", 100 },
                    { "wh_main_anc_talisman_talisman_of_preservation", 100 }
                },
                ["wh2_dlc13_lzd_nakai"] = {
                    { "wh_main_anc_armour_tricksters_helm", 100 },
                    { "wh2_dlc13_anc_enchanted_item_golden_tributes", 100 },
                    { "wh2_dlc13_talisman_the_ogham_shard", 100 }
                }
            },
            traits = {
                ["wh2_main_lzd_saurus_old_blood"] = "land_encounters_trait_incursion_sau_lzd",
                ["wh2_dlc12_lzd_tiktaqto"] = "land_encounters_trait_incursion_tik_lzd",
                ["wh2_dlc13_lzd_nakai"] = "land_encounters_trait_incursion_nak_lzd"
            }
        },
        unit_experience_amount = 3,
        units = { -- 19 units
            -- unit{id, quantity, appeareance_chance, alternative_chance, alternative}
            { "wh2_main_lzd_inf_skink_skirmishers_0", 4, 100, 0, nil }, -- 5
            { "wh2_main_lzd_inf_temple_guards", 4, 100, 0, nil }, -- 9
            { "wh2_main_lzd_mon_kroxigors", 2, 100, 0, nil }, -- 11 basic army (if lucky this will be the only army the player will need to beat for the reward
            { "wh2_dlc12_lzd_mon_ancient_stegadon_1", 2, 100, 30, "wh2_dlc12_lzd_inf_skink_red_crested_0" }, -- 13

            { "wh2_dlc17_lzd_inf_chameleon_stalkers_0", 2, 50, 20, "wh2_dlc13_lzd_mon_razordon_pack_0" }, -- 15
            { "wh2_main_lzd_inf_saurus_spearmen_1", 2, 40, 40, "wh2_dlc12_lzd_cav_ripperdactyl_riders_0" }, -- 17
            { "wh2_main_lzd_mon_ancient_stegadon", 1, 30, 5, "wh2_main_lzd_mon_stegadon_blessed_1" }, -- 18
            { "wh2_dlc17_lzd_mon_coatl_0", 1, 20, 5, "wh2_dlc12_lzd_cav_ripperdactyl_riders_ror_0" }, -- 19
            { "wh2_dlc13_lzd_mon_dread_saurian_1", 1, 10, 0, nil } -- 20
        },
        reinforcing_ally_armies = false,
        reinforcing_enemy_armies = false
    },

    -- Vampire Coast
    ["land_enc_dilemma_incursion_army_vco"] = {
        faction = "wh2_dlc11_cst_vampire_coast_qb1",
        identifier = "encounter_force",
        invasion_identifier = "encounter_invasion",
        intervention_type = INTERCEPTION_TYPE,
        lord = {
            possible_subtypes = {
                "wh2_dlc11_cst_admiral_fem_deep",
                "wh2_dlc11_cst_cylostra"
            },
            level_ranges = {20, 30},
            possible_forenames = { "names_name_242277685" },
            possible_clan_names = {},
            possible_family_names = { "names_name_2147345188" },
            ancillaries = {
                ["wh2_dlc11_cst_admiral_fem_deep"] = {
                    { "wh2_dlc11_anc_enchanted_item_black_buckthorns_treasure_map", 100 },
                    { "wh_main_anc_weapon_giant_blade", 25}
                },
                ["wh2_dlc11_cst_cylostra"] = {
                    { "wh2_dlc11_anc_arcane_item_the_bordeleaux_flabellum", 100 },
                    { "wh_main_anc_enchanted_item_the_other_tricksters_shard", 25 }
                }
            },
            traits = {
                ["wh2_dlc11_cst_admiral_fem_deep"] = "land_encounters_trait_incursion_adm_vco",
                ["wh2_dlc11_cst_cylostra"] = "land_encounters_trait_incursion_cyl_vco"
            }
        },
        unit_experience_amount = 3,
        units = { -- 19 units
            -- unit{id, quantity, appeareance_chance, alternative_chance, alternative}
            { "wh2_dlc11_cst_inf_depth_guard_0", 4, 100, 0, nil }, -- 5
            { "wh2_dlc11_cst_inf_syreens", 4, 100, 0, nil }, -- 9
            { "wh2_dlc11_cst_inf_deck_gunners_0", 2, 100, 0, nil }, -- 11 basic army (if lucky this will be the only army the player will need to beat for the reward
            { "wh2_dlc11_cst_mon_bloated_corpse_0", 2, 100, 0, nil }, -- 13

            { "wh2_dlc11_cst_inf_zombie_deckhands_mob_1", 2, 50, 20, "wh2_dlc11_cst_mon_animated_hulks_0" }, -- 15
            { "wh2_dlc11_cst_mon_scurvy_dogs", 2, 40, 20, "wh2_dlc11_cst_cav_deck_droppers_ror_0" }, -- 17
            { "wh2_dlc11_cst_art_carronade", 1, 30, 20, "wh2_dlc11_cst_mon_terrorgheist" }, -- 18
            { "wh2_dlc11_cst_mon_mournguls_0", 1, 20, 20, "wh2_dlc11_cst_mon_necrofex_colossus_0" }, -- 19
            { "wh2_dlc11_cst_mon_necrofex_colossus_0", 1, 10, 5, "wh2_dlc11_cst_art_queen_bess" } -- 20
        },
        reinforcing_ally_armies = false,
        reinforcing_enemy_armies = false
    }

}

M.nascent_rebellions = {
    -- Cathay
    ["land_enc_dilemma_underground_cth"] = {
        faction = "wh3_main_cth_cathay_qb1",
        identifier = "encounter_force",
        invasion_identifier = "encounter_invasion",
        intervention_type = INTERCEPTION_TYPE,
        lord = {
            possible_subtypes = {
                "wh3_main_cth_dragon_blooded_shugengan_yang",
            },
            level_ranges = {9, 11},
            possible_forenames = { },
            possible_clan_names = { },
            possible_family_names = { },
            ancillaries = {
                ["wh3_main_cth_dragon_blooded_shugengan_yang"] = {
                    { "wh3_main_anc_enchanted_item_cleansing_water", 100 },
                    { "wh_main_anc_armour_armour_of_destiny", 25 }
                }
            },
            traits = {
                ["wh3_main_cth_dragon_blooded_shugengan_yang"] = "land_encounters_trait_underground_cth"
            }
        },
        unit_experience_amount = 1,
        units = { -- 19 units
            -- unit{id, quantity, appeareance_chance, alternative_chance, alternative}
            { "wh3_main_cth_inf_peasant_spearmen_1", 4, 100, 0, nil }, -- 5
            { "wh3_main_cth_inf_peasant_archers_0", 4, 100, 0, nil }, -- 9
            { "wh3_main_cth_cav_peasant_horsemen_0", 2, 100, 0, nil }, -- 13
            { "wh3_main_cth_inf_iron_hail_gunners_0", 1, 75, 0, nil } -- 16
        },
        reinforcing_ally_armies = false,
        reinforcing_enemy_armies = false
    },

    -- Kislev
    ["land_enc_dilemma_underground_kis"] = {
        faction = "wh3_main_ksl_kislev_qb1",
        identifier = "encounter_force",
        invasion_identifier = "encounter_invasion",
        intervention_type = INTERCEPTION_TYPE,
        lord = {
            possible_subtypes = {
                "wh3_main_ksl_boyar",
            },
            level_ranges = {7, 9},
            possible_forenames = { },
            possible_clan_names = { },
            possible_family_names = { },
            ancillaries = {
                ["wh3_main_ksl_boyar"] = {
                    { "wh3_main_anc_weapon_dazhs_brazier", 100 },
                    { "wh_main_anc_talisman_talisman_of_preservation", 25}
                }
            },
            traits = {
                ["wh3_main_ksl_boyar"] = "land_encounters_trait_underground_kis"
            }
        },
        unit_experience_amount = 1,
        units = { -- 19 units
            -- unit{id, quantity, appeareance_chance, alternative_chance, alternative}
            { "wh3_main_ksl_inf_armoured_kossars_1", 4, 100, 0, nil }, -- 5
            { "wh3_main_ksl_inf_kossars_0", 4, 100, 0, nil }, -- 9
            { "wh3_main_ksl_cav_horse_archers_0", 2, 100, 0, nil }, -- 13 basic army (if lucky this will be the only army the player will need to beat for the reward
            { "wh3_main_ksl_inf_streltsi_0", 1, 75, 0, nil }
        },
        reinforcing_ally_armies = false,
        reinforcing_enemy_armies = false
    },

    -- Ogre Kingdoms
    ["land_enc_dilemma_underground_ogr"] = {
        faction = "wh3_main_ogr_ogre_kingdoms_qb1",
        identifier = "encounter_force",
        invasion_identifier = "encounter_invasion",
        intervention_type = INTERCEPTION_TYPE,
        lord = {
            possible_subtypes = {
                "wh3_main_ogr_tyrant"
            },
            level_ranges = {4, 6},
            possible_forenames = { },
            possible_clan_names = { },
            possible_family_names = { },
            ancillaries = {
                ["wh3_main_ogr_tyrant"] = {
                    { "wh3_main_anc_weapon_thundermace", 100 },
                    { "wh_main_anc_enchanted_item_healing_potion", 25 }
                }
            },
            traits = {
                ["wh3_main_ogr_tyrant"] = "land_encounters_trait_underground_ogr"
            }
        },
        unit_experience_amount = 1,
        units = { -- 19 units
            -- unit{id, quantity, appeareance_chance, alternative_chance, alternative}
            { "wh3_main_ogr_inf_gnoblars_0", 6, 100, 0, nil },
            { "wh3_main_ogr_inf_ogres_0", 3, 100, 0, nil },
            { "wh3_main_ogr_inf_maneaters_0", 1, 100, 0, nil },
            { "wh3_main_ogr_mon_gorgers_0", 1, 75, 0, nil }
        },
        reinforcing_ally_armies = false,
        reinforcing_enemy_armies = false
    },

    -- Tzeencth
    ["land_enc_dilemma_underground_tze"] = {
        faction = "wh3_main_tze_tzeentch_qb1",
        identifier = "encounter_force",
        invasion_identifier = "encounter_invasion",
        intervention_type = INTERCEPTION_TYPE,
        lord = {
            possible_subtypes = {
                "wh3_main_tze_herald_of_tzeentch_tzeentch",
            },
            level_ranges = {4, 6},
            possible_forenames = { },
            possible_clan_names = { },
            possible_family_names = { },
            ancillaries = {
                ["wh3_main_tze_herald_of_tzeentch_tzeentch"] = {
                    { "wh3_main_anc_enchanted_item_the_chromatic_tome", 100 },
                    { "wh_main_anc_arcane_item_forbidden_rod", 30 }
                }
            },
            traits = {
                ["wh3_main_tze_herald_of_tzeentch_tzeentch"] = "land_encounters_trait_underground_tze"
            }
        },
        unit_experience_amount = 1,
        units = { -- 19 units
            -- unit{id, quantity, appeareance_chance, alternative_chance, alternative}
            { "wh3_main_tze_inf_forsaken_0", 4, 100, 0, nil }, -- 5
            { "wh3_main_tze_inf_blue_horrors_0", 4, 100, 0, nil }, -- 9
            { "wh3_main_tze_mon_screamers_0", 2, 100, 0, nil }, -- 13 basic army (if lucky this will be the only army the player will need to beat for the reward
            { "wh3_main_tze_mon_flamers_0", 1, 75, 0, nil }
        },
        reinforcing_ally_armies = false,
        reinforcing_enemy_armies = false
    },

}

-- Cathay
-- Miao Ying -> But gives frostbite attacks to whole army
--> Use this to avoid breaking the game -> wh3_main_trait_blessed_by_ind_blades

-- Lizardmen
-- Kroggaar
-- gorrok

-- Empire
-- Volkmar
M.relic_defenses = {}

---------------------------------------------------------------------------
-- (Easiest) Skirmishes: A friendly battle between lords to help them prepare for true wars
---------------------------------------------------------------------------

M.skirmishes = {
    -- Cathay
    ["land_enc_dilemma_skirmish_cth"] = {
        faction = "wh3_main_cth_cathay_qb1",
        identifier = "encounter_force",
        invasion_identifier = "encounter_invasion",
        intervention_type = INTERCEPTION_TYPE,
        lord = {
            possible_subtypes = {
                "wh3_main_cth_lord_magistrate_yang",
                "wh3_main_cth_dragon_blooded_shugengan_yin",
            },
            level_ranges = {3, 6},
            possible_forenames = { },
            possible_clan_names = { },
            possible_family_names = { },
            ancillaries = {
                ["wh3_main_cth_lord_magistrate_yang"] = {
                    { "wh3_main_anc_enchanted_item_cleansing_water", 100 },
                    { "wh_main_anc_armour_armour_of_destiny", 25 }
                },
                ["wh3_main_cth_dragon_blooded_shugengan_yin"] = {
                    { "wh3_main_anc_enchanted_item_cleansing_water", 100 },
                    { "wh_main_anc_enchanted_item_the_other_tricksters_shard", 25 }
                }
            },
            traits = {
                ["wh3_main_cth_lord_magistrate_yang"] = "land_encounters_trait_skirmisher_cth_mag_yang",
                ["wh3_main_cth_dragon_blooded_shugengan_yin"] = "land_encounters_trait_skirmisher_cth_shu_yin"
            }
        },
        unit_experience_amount = 1,
        units = { -- 19 units
            -- unit{id, quantity, appeareance_chance, alternative_chance, alternative}
            { "wh3_main_cth_inf_peasant_spearmen_1", 4, 100, 0, nil }, -- 5
            { "wh3_main_cth_inf_peasant_archers_0", 4, 100, 0, nil }, -- 9
            { "wh3_main_cth_cav_peasant_horsemen_0", 2, 70, 0, nil }, -- 13 basic army (if lucky this will be the only army the player will need to beat for the reward
        },
        reinforcing_ally_armies = false,
        reinforcing_enemy_armies = false
    },

    -- Kislev
    ["land_enc_dilemma_skirmish_kis"] = {
        faction = "wh3_main_ksl_kislev_qb1",
        identifier = "encounter_force",
        invasion_identifier = "encounter_invasion",
        intervention_type = INTERCEPTION_TYPE,
        lord = {
            possible_subtypes = {
                "wh3_main_ksl_boyar",
            },
            level_ranges = {3, 6},
            possible_forenames = { },
            possible_clan_names = { },
            possible_family_names = { },
            ancillaries = {
                ["wh3_main_ksl_boyar"] = {
                    { "wh3_main_anc_arcane_item_mirror_of_the_ice_queen", 100 },
                    { "wh_main_anc_talisman_talisman_of_preservation", 25 }
                }
            },
            traits = {
                ["wh3_main_ksl_boyar"] = "land_encounters_trait_skirmisher_kis"
            }
        },
        unit_experience_amount = 1,
        units = { -- 19 units
            -- unit{id, quantity, appeareance_chance, alternative_chance, alternative}
            { "wh3_main_ksl_inf_armoured_kossars_1", 4, 100, 0, nil }, -- 5
            { "wh3_main_ksl_inf_kossars_0", 4, 100, 0, nil }, -- 9
            { "wh3_main_ksl_cav_horse_archers_0", 2, 70, 0, nil }, -- 13 basic army (if lucky this will be the only army the player will need to beat for the reward
        },
        reinforcing_ally_armies = false,
        reinforcing_enemy_armies = false
    },

    -- Ogre Kingdoms
    ["land_enc_dilemma_skirmish_ogr"] = {
        faction = "wh3_main_ogr_ogre_kingdoms_qb1",
        identifier = "encounter_force",
        invasion_identifier = "encounter_invasion",
        intervention_type = INTERCEPTION_TYPE,
        lord = {
            possible_subtypes = {
                "wh3_main_ogr_tyrant",
                "wh3_main_ogr_slaughtermaster_beasts",
            },
            level_ranges = {4, 6},
            possible_forenames = { },
            possible_clan_names = { },
            possible_family_names = { },
            ancillaries = {
                ["wh3_main_ogr_tyrant"] = {
                    { "wh_main_anc_armour_tricksters_helm", 50 }
                },
                ["wh3_main_ogr_slaughtermaster_beasts"] = {
                    { "wh_main_anc_arcane_item_book_of_ashur", 50 }
                }
            },
            traits = {
                ["wh3_main_ogr_tyrant"] = "land_encounters_trait_skirmisher_ogr_tyr",
                ["wh3_main_ogr_slaughtermaster_beasts"] = "land_encounters_trait_skirmisher_ogr_sla"
            }
        },
        unit_experience_amount = 1,
        units = { -- 19 units
            -- unit{id, quantity, appeareance_chance, alternative_chance, alternative}
            { "wh3_main_ogr_inf_gnoblars_0", 4, 100, 0, nil }, -- 5
            { "wh3_main_ogr_inf_ogres_0", 4, 100, 0, nil }, -- 9
            { "wh3_main_ogr_inf_maneaters_0", 2, 70, 0, nil }, -- 13 basic army (if lucky this will be the only army the player will need to beat for the reward
        },
        reinforcing_ally_armies = false,
        reinforcing_enemy_armies = false
    },

    -- Nurgle
    ["land_enc_dilemma_skirmish_nur"] = {
        faction = "wh3_main_nur_nurgle_qb1",
        identifier = "encounter_force",
        invasion_identifier = "encounter_invasion",
        intervention_type = INTERCEPTION_TYPE,
        lord = {
            possible_subtypes = {
                "wh3_main_nur_herald_of_nurgle_nurgle",
            },
            level_ranges = {3, 5},
            possible_forenames = { },
            possible_clan_names = { },
            possible_family_names = { },
            ancillaries = {
                ["wh3_main_nur_herald_of_nurgle_nurgle"] = {
                    { "wh3_main_anc_talisman_spore_censer", 100 },
                    { "wh_main_anc_weapon_obsidian_blade", 25 }
                }
            },
            traits = {
                ["wh3_main_nur_herald_of_nurgle_nurgle"] = "land_encounters_trait_skirmisher_nur"
            }
        },
        unit_experience_amount = 1,
        units = { -- 19 units
            -- unit{id, quantity, appeareance_chance, alternative_chance, alternative}
            { "wh3_main_nur_inf_nurglings_0", 4, 100, 0, nil }, -- 5
            { "wh3_main_nur_inf_forsaken_0", 4, 100, 0, nil }, -- 9
            { "wh3_main_nur_inf_chaos_furies_0", 2, 70, 0, nil }, -- 13 basic army (if lucky this will be the only army the player will need to beat for the reward
        },
        reinforcing_ally_armies = false,
        reinforcing_enemy_armies = false
    },

    -- Tzeencth
    ["land_enc_dilemma_skirmish_tze"] = {
        faction = "wh3_main_tze_tzeentch_qb1",
        identifier = "encounter_force",
        invasion_identifier = "encounter_invasion",
        intervention_type = INTERCEPTION_TYPE,
        lord = {
            possible_subtypes = {
                "wh3_main_tze_herald_of_tzeentch_tzeentch",
            },
            level_ranges = {4, 6},
            possible_forenames = { },
            possible_clan_names = { },
            possible_family_names = { },
            ancillaries = {
                ["wh3_main_tze_herald_of_tzeentch_tzeentch"] = {
                    { "wh3_main_anc_enchanted_item_the_chromatic_tome", 100 },
                    { "wh_main_anc_arcane_item_forbidden_rod", 25 }
                }
            },
            traits = {
                ["wh3_main_tze_herald_of_tzeentch_tzeentch"] = "land_encounters_trait_skirmisher_tze"
            }
        },
        unit_experience_amount = 1,
        units = { -- 19 units
            -- unit{id, quantity, appeareance_chance, alternative_chance, alternative}
            { "wh3_main_tze_inf_forsaken_0", 4, 100, 0, nil }, -- 5
            { "wh3_main_tze_inf_blue_horrors_0", 4, 100, 0, nil }, -- 9
            { "wh3_main_tze_mon_screamers_0", 2, 80, 0, nil }, -- 13 basic army (if lucky this will be the only army the player will need to beat for the reward
        },
        reinforcing_ally_armies = false,
        reinforcing_enemy_armies = false
    },

}

------------------------------------------------------------------------------------
-- Surprise Attack: Killer armies
------------------------------------------------------------------------------------
M.surprise_attacks = {
    -- Beastmen
    ["land_enc_dilemma_surprise_attack_bst"] = {
        faction = "wh_dlc03_bst_beastmen_qb1",
        identifier = "encounter_force",
        invasion_identifier = "encounter_invasion",
        intervention_type = INTERCEPTION_TYPE,
        lord = {
            possible_subtypes = {
                "wh_dlc03_bst_beastlord",
                "wh_dlc05_bst_morghur",
                "wh_dlc03_bst_khazrak",
                -- TAUROX
            },
            level_ranges = {10, 20},
            possible_forenames = {},
            possible_clan_names = {},
            possible_family_names = {},
            ancillaries = {
                ["wh_dlc03_bst_beastlord"] = {
                    { "wh_dlc03_anc_armour_trollhide", 100 },
                    { "wh_main_anc_weapon_ogre_blade", 25 }
                },
                ["wh_dlc05_bst_morghur"] = {
                    { "wh_main_anc_weapon_stave_of_ruinous_corruption", 100 },
                    { "wh_main_anc_arcane_item_book_of_ashur", 25 }
                },
                ["wh_dlc03_bst_khazrak"] = {
                    { "wh_dlc03_anc_weapon_scourge", 100 },
                    { "wh_dlc03_anc_armour_the_dark_mail", 100 },
                    { "wh_main_anc_armour_helm_of_discord", 50 }
                }
            },
            traits = {
                ["wh_dlc03_bst_beastlord"] = "land_encounters_trait_surprise_bea_bst",
                ["wh_dlc05_bst_morghur"] = "land_encounters_trait_surprise_mor_bst",
                ["wh_dlc03_bst_khazrak"] = "land_encounters_trait_surprise_kha_bst"
            }
        },
        unit_experience_amount = 3,
        units = {
            -- unit{id, quantity, appeareance_chance, alternative_chance, alternative}
            { "wh_pro04_bst_inf_bestigor_herd_ror_0", 1, 100, 0, nil },
            { "wh_dlc03_bst_inf_bestigor_herd_0", 3, 100, 0, nil },
            { "wh_dlc03_bst_inf_ungor_raiders_0", 6, 100, 0, nil  }, -- 11 basic army
            { "wh_dlc03_bst_inf_cygor_0", 3, 80, 50, "wh2_dlc17_bst_mon_ghorgon_0" }, -- 14
            { "wh_dlc03_bst_inf_ungor_herd_1", 2, 30, 30, "wh2_dlc17_bst_cha_wargor_2"}, -- 16
            { "wh_dlc03_bst_inf_chaos_warhounds_1", 1, 20, 50, "wh2_dlc17_bst_mon_ghorgon_0" }, -- 18
            { "wh_dlc03_bst_cav_razorgor_chariot_0", 1, 10, 50, "wh2_dlc17_bst_mon_jabberslythe_0" } -- 20
        },
        reinforcing_ally_armies = false,
        reinforcing_enemy_armies = false
    },

    -- Skaven
    ["land_enc_dilemma_surprise_attack_skv"] = {
        faction = "wh2_main_skv_skaven_qb1",
        identifier = "encounter_force",
        invasion_identifier = "encounter_invasion",
        intervention_type = INTERCEPTION_TYPE,
        lord = {
            possible_subtypes = {
                "wh2_dlc14_skv_master_assassin",
                "wh2_dlc09_skv_tretch_craventail",
                "wh2_dlc12_skv_ikit_claw"
            },
            level_ranges = {10, 20},
            possible_forenames = {},
            possible_clan_names = {},
            possible_family_names = {},
            ancillaries = {
                ["wh2_dlc14_skv_master_assassin"] = {
                    { "wh2_main_anc_armour_warpstone_armour", 100 },
                    { "wh2_dlc15_anc_arcane_item_black_dragon_special", 25}
                },
                ["wh2_dlc09_skv_tretch_craventail"] = {
                    { "wh2_dlc09_anc_enchanted_item_lucky_skullhelm", 100 },
                    { "wh_main_anc_talisman_talisman_of_preservation", 100 }
                },
                ["wh2_dlc12_skv_ikit_claw"] = {
                    { "wh2_dlc12_anc_weapon_storm_daemon", 100 },
                    { "wh2_dlc12_anc_armour_iron_frame", 100 },
                    { "wh_main_anc_arcane_item_book_of_ashur", 100 }
                }
            },
            traits = {
                ["wh2_dlc14_skv_master_assassin"] = "land_encounters_trait_surprise_msa_skv",
                ["wh2_dlc09_skv_tretch_craventail"] = "land_encounters_trait_surprise_cra_skv",
                ["wh2_dlc12_skv_ikit_claw"] = "land_encounters_trait_surprise_iki_skv"
            }
        },
        unit_experience_amount = 3,
        units = {
            { "wh2_main_skv_inf_stormvermin_0", 4, 100, 10, "wh2_main_skv_inf_clanrat_spearmen_1" },
            { "wh2_dlc14_skv_inf_eshin_triads_0", 6, 100, 10, "wh2_dlc12_skv_veh_doom_flayer_0" }, -- 11 basic army
            { "wh2_dlc12_skv_inf_warplock_jezzails_0", 3, 80, 50, "wh2_dlc14_skv_inf_poison_wind_mortar_0" }, -- 14
            { "wh2_main_skv_mon_hell_pit_abomination", 1, 30, 30, "wh2_main_skv_mon_rat_ogres"}, -- 16
            { "wh2_main_skv_veh_doomwheel", 1, 20, 50, "wh2_main_skv_inf_gutter_runners_1" }, -- 18
            { "wh2_main_skv_inf_night_runners_1", 2, 10, 50, "wh2_main_skv_inf_plague_monks" } -- 20
        },
        reinforcing_ally_armies = false,
        reinforcing_enemy_armies = false
    },

}

-- Dwarfs
-- Mainly thorek. throgrim and ungrim (relics from the chaos dwarfs, runes)

-- Cathay
-- zhao ming as well (the dagger)

-- Ogres
-- Greasus
-- Skrag

-- Skaven
-- Skrolk
-- Throt the Unclean
M.treasure_seekers = {}

M.waystones = {
    ["land_enc_dilemma_waystone_defense_hef"] = {
        faction = "wh2_main_hef_high_elves_qb1",
        identifier = "encounter_force",
        invasion_identifier = "encounter_invasion",
        lord = {
            possible_subtypes = {
                "wh2_main_hef_princess",
                "wh2_dlc15_hef_eltharion",
                -- tyrion
                -- allarielle
                -- imrik
            },
            level_ranges = {20, 30},
            possible_forenames = {}, -- or names
            possible_clan_names = {},
            possible_family_names = {},
            ancillaries = {
                ["wh2_main_hef_princess"] = {},
                ["wh2_dlc15_hef_eltharion"] = {}
            },
            traits = {
                ["wh2_main_hef_princess"] = nil,
                ["wh2_dlc15_hef_eltharion"] = nil
            }
        },
        unit_experience_amount = 4,
        units = {
            { "wh2_main_hef_inf_lothern_sea_guard_0", 6, 100, 0, nil }, -- 7
            { "wh2_main_hef_inf_white_lions_of_chrace_0", 4, 100, 0, nil}, -- 11 basic army
            { "wh2_main_hef_art_eagle_claw_bolt_thrower", 2, 100, 50, "wh2_main_hef_cav_tiranoc_chariot" }, -- 13

            { "wh2_main_hef_inf_swordmasters_of_hoeth_0", 2, 50, 10, "wh2_main_hef_inf_lothern_sea_guard_1" }, -- 15
            { "wh2_main_hef_cav_ithilmar_chariot", 2, 30, 30, "wh2_main_hef_mon_moon_dragon" }, -- 17
            { "wh2_main_hef_mon_phoenix_flamespyre", 2, 20, 50, "wh2_main_hef_mon_phoenix_frostheart" }, -- 19
            { "wh2_main_hef_mon_star_dragon", 1, 5, 0, nil } -- 20
        },
        reinforcing_ally_armies = false,
        reinforcing_enemy_armies = false
    }
}

return M
