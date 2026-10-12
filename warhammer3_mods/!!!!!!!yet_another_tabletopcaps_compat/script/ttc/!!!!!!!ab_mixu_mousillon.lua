-- Mixu's Mousillon
local caps = {
    -- Other
    {"mixu_msl_art_trebuchet", "rare", 2},
    {"mixu_msl_art_trebuchet_balefire", "rare", 2},
    {"mixu_msl_cav_black_grail_knights", "rare", 2},
    {"mixu_msl_cav_black_knights_lance", "special", 1},
    {"mixu_msl_cav_black_knights_sword", "special", 1},
    {"mixu_msl_cav_hellsteed_knights", "rare", 2},
    {"mixu_msl_inf_bowmen_balefire", "core"},
    {"mixu_msl_inf_brigands", "special", 2},
    {"mixu_msl_inf_grave_guard_great_weapons", "special", 1},
    {"mixu_msl_inf_grave_guard_halberds", "special", 1},
    {"mixu_msl_inf_grave_guard_sword", "special", 1},
    {"mixu_msl_inf_men_at_arms_polearms", "core"},
    {"mixu_msl_inf_mounted_brigands", "special", 1},
    {"mixu_msl_mon_dracoleech", "rare", 1},
    {"mixu_msl_mon_giant_snail", "special", 1},
    {"mixu_msl_mon_the_grey_men", "special", 1},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end
