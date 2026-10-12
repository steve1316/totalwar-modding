-- Nanu's Pirates of Sartosa Overhaul
local caps = {
    -- Other
    {"cathay_pirate_bombard", "special", 2},
    {"cathay_pirate_crossbows", "core"},
    {"cathay_pirate_dual_swords", "core"},
    {"cathay_pirate_fire_rain_rocket_battery", "rare", 2},
    -- Vampire Coast
    {"sartosa_buccaneer_deck_gun_weapon_team", "special", 2},
    {"sartosa_buccaneer_deck_gun_weapon_team_ror", "special", 3},
    {"sartosa_buccaneer_drakefire_cannon", "rare", 2},
    {"sartosa_buccaneer_drakegun_weapon_team", "special", 1},
    {"sartosa_buccaneer_mortar_ror", "rare", 1},
    {"sartosa_buccaneer_torpedo_weapon_team", "special", 2},
    {"sartosa_buccaneers_axe_and_pistol", "core"},
    {"sartosa_buccaneers_blunderbuss", "special", 1},
    {"sartosa_buccaneers_dual_axes", "core"},
    {"sartosa_depth_guard_jenny_ror", "special", 2},
    {"sartosa_leviathan", "rare", 3},
    {"sartosa_norscan_raider_great_weapons", "core"},
    {"sartosa_norscan_raiders", "core"},
    {"sartosa_norscan_raiders_ror", "special", 1},
    {"sartosa_norscan_reaver_axe_and_shield", "core"},
    {"sartosa_norscan_reaver_captain_chariot", "special", 2},
    {"sartosa_norscan_reaver_dual_axes", "special", 1},
    {"sartosa_norscan_reaver_halberds", "special", 1},
    {"sartosa_norscan_reaver_ror", "special", 2},
    {"sartosa_norscan_warhounds", "core"},
    {"sartosa_norscan_whalers", "core"},
    {"sartosa_pirate_artillery_cannon", "special", 2},
    {"sartosa_pirate_artillery_mortar", "special", 2},
    {"sartosa_pirate_halberds", "core"},
    {"sartosa_pirate_halberds_ror", "special", 1},
    {"sartosa_pirate_handguns", "special", 1},
    {"sartosa_pirate_handguns_ror", "special", 1},
    {"sartosa_privateers", "special", 1},
    {"sartosa_privateers_dual_swords", "core"},
    {"sartosa_privateers_halberds", "core"},
    {"sartosa_privateers_james_ror", "special", 1},
    {"sartosa_privateers_ror", "special", 1},
    {"sartosa_privateers_roth_ror", "special", 1},
    {"sartosa_promethean_riders", "special", 2},
    {"sartosa_promethean_riders_davey_ror", "special", 2},
    {"sartosa_prometheans", "special", 2},
    {"sartosa_prometheans_ror", "rare", 1},
    {"sartosa_saboteurs", "special", 2},
    {"sartosa_smugglers", "core"},
    {"sartosa_smugglers_ror", "special", 1},
    {"sartosa_smugglers_sammy_ror", "special", 2},
    {"sartosa_zombie_carnosaur", "rare", 2},
    {"sartosa_zombie_dragon", "rare", 2},
    {"sartosa_zombie_dread_saurian", "rare", 2},
    {"sartosa_zombie_kharibdyss", "rare", 3},
    {"sartosa_zombie_mammoth", "rare", 2},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end
