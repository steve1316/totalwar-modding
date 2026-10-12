-- Mixu's Legendary Lords
local caps = {
    -- Empire
    {"mixu_emp_mon_promethean_riders", "special", 3},
    {"mixu_emp_inf_pirate_deckhands_swords", "core"},
    {"mixu_emp_inf_grog_carriers", "special", 1},
    {"mixu_emp_inf_pirate_deckhands_polearms", "core"},
    {"mixu_emp_inf_buccaneers_great_axe", "core"},
    {"mixu_emp_inf_buccaneers_sword_and_bombs", "core"},
    {"mixu_emp_inf_norscan_reavers", "core"},
    {"mixu_emp_inf_norscan_reavers_great_weapons", "core"},
    {"mixu_emp_mon_leviathan", "rare", 3},
    {"mixu_emp_mon_prometheans", "special", 2},
    {"mixu_emp_art_mortar", "special", 2},
    {"mixu_emp_art_carronade", "special", 2},
    {"mixu_emp_inf_gunnery_mob_blunderbuss", "core"},
    {"mixu_emp_inf_gunnery_mob_handguns", "core"},
    {"mixu_emp_inf_celebrants", "core"},
    {"mixu_emp_inf_horned_hunters", "special", 1},
    {"mixu_emp_cav_daughters_of_rhya", "special", 1},
    -- Tzeentch
    {"mixu_tze_inf_cultists", "core"},
    {"mixu_tze_inf_cultist_acolytes", "special", 1},
    {"mixu_tze_mon_chaos_dragon", "rare", 2},
    {"mixu_tze_mon_trolls", "special", 2},
    {"mixu_tze_mon_warhound", "core"},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end