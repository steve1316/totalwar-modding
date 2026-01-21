-- Sets by subculture that are given to the AI whenever they control a smithy every 20 turns. 
-- Can be found on ancillary_set_ancillary_junction_tables
local item_sets_or_special_items_by_subculture = {
    -- WH1
    -- Dwarfs
    ["wh_main_sc_dwf_dwarfs"] = {
        -- Sets 
        [1] = { -- ironwarden?
            "wh2_dlc10_dwf_anc_armour_ironwardens_shield",
            "wh2_dlc10_dwf_anc_enchanted_item_ironwardens_tankard",
            "wh2_dlc10_dwf_anc_talisman_ironwardens_wardstone",
            "wh2_dlc10_dwf_anc_weapon_ironwardens_hammer"
        },
        -- Special items

    },
    -- Greenskins
    ["wh_main_sc_grn_greenskins"] = {
        -- Sets 
        -- Special items
    },
    -- The Empire
    ["wh_main_sc_emp_empire"] = {
        -- Sets 
        -- Special items
    },
    -- Vampire Counts
    ["wh_main_sc_vmp_vampire_counts"] = {
        -- Sets 
        -- Special items
    },
    -- Warriors of Chaos
    ["wh_main_sc_chs_chaos"] = {
        -- Sets 
        -- Special items
    },
    -- Beastmen
    ["wh_dlc03_sc_bst_beastmen"] = {
        -- Sets 
        -- Special items
    },
    -- Bretonnia
    ["wh_main_sc_brt_bretonnia"] = {
        -- Sets 
        -- Special items
    },
    -- Wood Elves
    ["wh_dlc05_sc_wef_wood_elves"] = {
        -- Sets 
        -- Special items
    },
    -- Norsca
    ["wh_dlc08_sc_nor_norsca"] = {
        -- Sets 
        -- Special items
    },

    -- WH2
    -- Dark Elves
    ["wh2_main_sc_def_dark_elves"] = {
        -- Sets 
        -- Special items
    },
    -- High Elves
    ["wh2_main_sc_hef_high_elves"] = {
        -- Sets 
        -- Special items
    },
    -- Lizardmen
    ["wh2_main_sc_lzd_lizardmen"] = {
        -- Sets 
        -- Special items
    },
    -- Skaven
    ["wh2_main_sc_skv_skaven"] = {
        -- Sets 
        -- Special items
    },
    -- Tomb Kings
    ["wh2_dlc09_sc_tmb_tomb_kings"] = {
        -- Sets 
        -- Special items
    },
    -- Vampire Coast
    ["wh2_dlc11_sc_cst_vampire_coast"] = {
        -- Sets 
        -- Special items
    },

    -- WH3
    -- Kislev
    ["wh3_main_sc_ksl_kislev"] = {
        -- Sets 
        [1] = { -- wh3_main_ancillary_set_ksl_druzhina_of_ice
            "wh3_main_anc_armour_iron_ice_armour",
            "wh3_main_anc_talisman_blizzard_broach",
            "wh3_main_anc_weapon_frost_shard_glaive"
        },
        [2] = { -- wh3_main_ancillary_set_ksl_ursire
            "wh3_main_anc_armour_great_bear_pelt",
            "wh3_main_anc_weapon_ursuns_claws"
        },
        [3] = { -- wh3_main_ancillary_set_ksl_wyrmhunter
            "wh3_main_anc_armour_wyrm_harness",
            "wh3_main_anc_weapon_wyrmspike"
        },
        -- Special items
        [4] = {
            "wh3_main_anc_arcane_item_mirror_of_the_ice_queen"
        },
        [5] = {
            "wh3_main_anc_enchanted_item_balalaika_of_the_arari"
        },
        [6] = {
            "wh3_main_anc_weapon_dazhs_brazier"
        },
        [7] = {
            "wh_main_anc_talisman_the_white_cloak_of_ulric"
        }
    },

    -- Daemons
    ["wh3_main_sc_dae_daemons"] = {
        -- Sets 
        -- Special items
        [1] = {
            "wh3_main_anc_armour_weird_plate"
        },
        [2] = {
            "wh3_main_anc_enchanted_item_the_chromatic_tome"
        },
        [3] = {
            "wh3_main_anc_talisman_vile_seed"
        },
        [4] = {
            "wh3_main_anc_talisman_spore_censer"
        },
        [5] = {
            "wh3_main_anc_talisman_jewel_of_denial"
        },
        [6] = {
            "wh3_main_anc_talisman_crystal_pendant"
        },
        [7] = {
            "wh3_main_anc_arcane_item_sceptre_of_entropy"
        }
    },

    -- Cathay
    ["wh3_main_sc_cth_cathay"] = {
        -- Sets 
        [1] = { -- wh3_main_ancillary_set_cth_shang_yang_elementalist
            "wh3_main_anc_armour_robes_of_shang_yang", 
            "wh3_main_anc_magic_standard_standard_of_shang_yang" 
        },
        [2] = { -- wh3_main_ancillary_set_cth_nan_gau_sentinel 
            "wh3_main_anc_armour_shield_of_the_nan_gau", 
            "wh3_main_anc_magic_standard_standard_of_nan_gau" 
        },
        [3] = { -- wh3_main_ancillary_set_cth_the_celestial_champion
            "wh3_main_anc_armour_ascendant_celestial_armour",
            "wh3_main_anc_enchanted_item_celestial_silk_robe",
            "wh3_main_anc_weapon_ascendant_celestial_blade" 
        },
        [4] = { -- wh3_main_ancillary_set_cth_tools_of_astromancy
            "wh3_main_anc_arcane_item_scrolls_of_astromancy",
            "wh3_main_anc_enchanted_item_astromancers_spyglass"
        },
        -- Special items
        [5] = {
            "wh3_main_anc_enchanted_item_catalytic_kiln"
        },
        [6] = {
            "wh3_main_anc_enchanted_item_cleansing_water"
        },
        [7] = {
            "wh3_main_anc_talisman_crystal_of_kunlan"
        }
    },
    
    -- Ogre Kingdoms
    ["wh3_main_sc_ogr_ogre_kingdoms"] = {
        -- Sets 
        [1] = { -- wh3_main_ancillary_set_ogr_bull_balls
            "wh3_main_anc_armour_bullgut",
            "wh3_main_anc_magic_standard_bull_standard"
        },
        [2] = { -- wh3_main_ancillary_set_ogr_halfling_meat
            "wh3_main_anc_arcane_item_halfling_cookbook",
            "wh3_main_anc_weapon_the_tenderiser"
        },
        [3] = { -- wh3_main_ancillary_set_ogr_skull_collecta
            "wh3_main_anc_arcane_item_skullmantle",
            "wh3_main_anc_armour_greatskull",
            "wh3_main_anc_weapon_skull_plucker"
        },
        [4] = { -- wh3_main_ancillary_set_ogr_the_scarred
            "wh3_main_anc_enchanted_item_daemon_killer_scars",
            "wh3_main_anc_weapon_blood_cleaver"
        },  
        -- Special items
        [5] = {
            "wh3_main_anc_weapon_siegebreaker"
        },
        [6] = {
            "wh3_main_anc_weapon_thundermace"
        }
    },
    
    -- Nurgle
    ["wh3_main_sc_nur_nurgle"] = {
        -- Sets 
        [1] = { -- wh3_main_ancillary_set_nur_impedimenta_of_plague
            "wh3_main_anc_magic_standard_standard_of_seeping_decay",
            "wh3_main_anc_weapon_staff_of_nurgle"
        },
        -- Special items
        [2] = {
            "wh3_main_anc_armour_weird_plate"
        },
        [3] = {
            "wh3_main_anc_enchanted_item_the_chromatic_tome"
        },
        [4] = {
            "wh3_main_anc_talisman_vile_seed"
        },
        [5] = {
            "wh3_main_anc_talisman_spore_censer"
        }
    },

    -- Khorne
    ["wh3_main_sc_kho_khorne"] = {
        -- Sets 
        [1] = { -- wh3_main_ancillary_set_kho_trappings_of_blood
            "wh3_main_anc_armour_armour_of_khorne",
            "wh3_main_anc_weapon_axe_of_khorne"
        },
        -- Special items
        [2] = {
            "wh3_main_anc_armour_weird_plate"
        },
        [3] = {
            "wh3_main_anc_enchanted_item_the_chromatic_tome"
        }
    },
    
    -- Slaanesh
    ["wh3_main_sc_sla_slaanesh"] = {
        -- Sets 
        [1] = { -- wh3_main_ancillary_set_sla_accoutrements_of_desire
            "wh3_main_anc_magic_standard_banner_of_ecstacy",
            "wh3_main_anc_weapon_lash_of_despair"
        },
        -- Special items
        [2] = {
            "wh3_main_anc_armour_weird_plate"
        },
        [3] = {
            "wh3_main_anc_enchanted_item_the_chromatic_tome"
        },
        [4] = {
            "wh3_main_anc_talisman_jewel_of_denial"
        }
    },
    
    -- Tzeentch
    ["wh3_main_sc_tze_tzeentch"] = {
        -- Sets 
        [1] = { -- wh3_main_ancillary_set_tze_raiment_of_change
            "wh3_main_anc_magic_standard_icon_of_sorcery",
            "wh3_main_anc_weapon_staff_of_change"
        },
        -- Special items
        [2] = {
            "wh3_main_anc_armour_weird_plate"
        },
        [3] = {
            "wh3_main_anc_enchanted_item_the_chromatic_tome"
        },
        [4] = {
            "wh3_main_anc_talisman_crystal_pendant"
        },
        [5] = {
            "wh3_main_anc_arcane_item_sceptre_of_entropy"
        }
    }

}

return item_sets_or_special_items_by_subculture