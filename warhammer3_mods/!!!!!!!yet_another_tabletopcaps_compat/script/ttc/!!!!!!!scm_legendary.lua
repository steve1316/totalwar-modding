-- Legendary Characters
local caps = {
    -- Dwarfs
    {"hunt_dwf_riggers_0", "special", 1},
    {"hunt_dwf_slayer_pirates_0", "special", 2},
    -- Empire
    {"str_chronos_knights", "special", 2},
    -- Greenskins
    {"hunt_boyz_mob", "core"},
    {"hunt_goblin_mob", "core"},
    {"hunt_savage_mob", "core"},
    -- Khorne
    {"kho_skullreaper_kys", "special", 2},
    {"kys_kho_wrathmonger", "rare", 1},
    {"kys_kho_wrathmonger_ror", "rare", 1},
    -- Kislev
    {"bear_dead_baron", "special", 1},
    {"werebear_werebearus", "special", 2},
    -- Other
    {"dust_gutrot_blight_kings", "special", 2},
    -- Skaven
    {"wh2_skv_mors_redguard_ror", "special", 2},
    -- Vampire Counts
    {"camera_skelly_bones", "special", 1},
    -- Wood Elves
    {"kou_bowmen_units", "rare", 1},
    {"kou_elf_wolf_rider", "special", 2},
    {"kou_eonir_explorers", "special", 1},
    {"kou_laddrielle_wolves", "special", 1},
    {"kou_meadow_chariot_ror", "special", 2},
    {"kou_queen_ror_treekin", "special", 2},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end
