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
---------------------------------------------------------------------------
-- (Easiest) Skirmishes: A friendly battle between lords to help them prepare for true wars
---------------------------------------------------------------------------

return {
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