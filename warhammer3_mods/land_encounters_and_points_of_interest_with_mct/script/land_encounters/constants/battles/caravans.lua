require("script/land_encounters/constants/utils/common")

return {

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