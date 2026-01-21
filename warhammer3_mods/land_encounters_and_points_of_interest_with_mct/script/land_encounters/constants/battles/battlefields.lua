require("script/land_encounters/constants/utils/common")
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
-- Battlefields: Thematic mid strength armies that can have legendary lords
------------------------------------------------------------------------------------
return {
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