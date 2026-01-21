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

return {
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