-- PLAYER ONLY. Each mission gives a set or one of the useful racial items given certain conditions are met. Only X (1/2/3) missions can be active given smithy level at a time per faction.
local smithy_missions_by_subculture = {
    -- WH1
    -- Dwarfs
    ["wh_main_sc_dwf_dwarfs"] = {
    },
    -- Greenskins
    ["wh_main_sc_grn_greenskins"] = {
    },
    -- The Empire
    ["wh_main_sc_emp_empire"] = {

    },
    -- Vampire Counts
    ["wh_main_sc_vmp_vampire_counts"] = {
    },
    -- Warriors of Chaos
    ["wh_main_sc_chs_chaos"] = {

    },
    -- Beastmen
    ["wh_dlc03_sc_bst_beastmen"] = {

    },
    -- Bretonnia
    ["wh_main_sc_brt_bretonnia"] = {

    },
    -- Wood Elves
    ["wh_dlc05_sc_wef_wood_elves"] = {

    },
    -- Norsca
    ["wh_dlc08_sc_nor_norsca"] = {

    },

    -- WH2
    -- Dark Elves
    ["wh2_main_sc_def_dark_elves"] = {
        [1] = {
            mission = "land_enc_mission_smithy_dark_elves_armour_of_living_death",
            ancillaries = { "wh2_main_anc_armour_armour_of_living_death" }
        },
                                      
        [2] = {
            mission = "land_enc_mission_smithy_dark_elves_armour_armour_of_eternal_servitude",
            ancillaries = { "wh2_main_anc_armour_armour_of_eternal_servitude" }
        },
                                      
        [3] = {
            mission = "land_enc_mission_smithy_dark_elves_anc_weapon_chillblade",
            ancillaries = { "wh2_main_anc_weapon_chillblade" }
        }
    },
    -- High Elves
    ["wh2_main_sc_hef_high_elves"] = {

    },
    -- Lizardmen
    ["wh2_main_sc_lzd_lizardmen"] = {
    },
    -- Skaven
    ["wh2_main_sc_skv_skaven"] = {

    },
    -- Tomb Kings
    ["wh2_dlc09_sc_tmb_tomb_kings"] = {
    },
    -- Vampire Coast
    ["wh2_dlc11_sc_cst_vampire_coast"] = {
    },

    -- WH3
    -- Kislev
    ["wh3_main_sc_ksl_kislev"] = {
        --[1] = {
        --    mission = "land_enc_mission_smithy_kislev_ursire",
        --    ancillaries = { "wh3_main_anc_armour_great_bear_pelt", "wh3_main_anc_weapon_ursuns_claws" }
        --},
                                  
        --[2] = {
        --    mission = "land_enc_mission_smithy_kislev_wyrm_hunter",
        --    ancillaries = { "wh3_main_anc_armour_wyrm_harness", "wh3_main_anc_weapon_wyrmspike" }
        --},
        
        --[3] = {
        --    mission = "land_enc_mission_smithy_kislev_dazhs_brazier",
        --   ancillaries = { "wh3_main_anc_weapon_dazhs_brazier" }
        --},
    },

    -- Daemons
    ["wh3_main_sc_dae_daemons"] = {
    },

    -- Cathay
    ["wh3_main_sc_cth_cathay"] = {
    },
    
    -- Ogre Kingdoms
    ["wh3_main_sc_ogr_ogre_kingdoms"] = {
    },
    
    -- Nurgle
    ["wh3_main_sc_nur_nurgle"] = {
    },

    -- Khorne
    ["wh3_main_sc_kho_khorne"] = {
    },
    
    -- Slaanesh
    ["wh3_main_sc_sla_slaanesh"] = {

    },
    
    -- Tzeentch
    ["wh3_main_sc_tze_tzeentch"] = {

    }

}

return smithy_missions_by_subculture