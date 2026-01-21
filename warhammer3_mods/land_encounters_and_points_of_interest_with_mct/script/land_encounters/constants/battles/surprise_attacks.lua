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
-- Surprise Attack: Killer armies
------------------------------------------------------------------------------------
return {
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