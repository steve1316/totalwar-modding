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
-- Incursions: Small invasions of stronger races with better armies
------------------------------------------------------------------------------------
return {
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