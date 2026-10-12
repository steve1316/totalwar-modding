-- Guns of the Empire
local caps = {
    -- Empire
    {"snek_emp_gote_inf_juggernauts", "special", 3},
    {"snek_emp_gote_cav_pegasus_pistolkorps", "special", 1},
    {"snek_emp_art_landship", "rare", 3},
    {"snek_emp_gote_inf_rocketeers", "special", 2},
    {"snek_emp_gote_art_swivel_guns", "special", 2},
    {"snek_emp_gote_art_grand_cannon", "special", 2},
    {"snek_emp_gote_art_incendiary_guns", "rare", 2},
    {"snek_emp_gote_art_clockwork_missile", "rare", 2},
    {"snek_emp_gote_art_hellhammer", "rare", 2},
    {"snek_emp_gote_art_steamcopter", "special", 2},
    {"snek_emp_gote_art_war_baloon", "special", 2},
    {"snek_emp_gote_cav_thricepistols", "special", 1},
    {"snek_emp_gote_veh_munitions_wagon", "rare", 1},
    {"snek_emp_gote_veh_hellblaster_wagon", "rare", 2},
    {"snek_emp_gote_inf_ersatzsolder", "core"},
    {"snek_emp_gote_inf_bergjaeger", "core"},
    {"snek_emp_gote_inf_jaegerkorps", "core"},
    {"snek_emp_gote_inf_field_engineers", "core"},
    {"snek_emp_gote_inf_hakbutschutzen", "core"},
    {"snek_emp_gote_inf_dwarf_crank_gunners", "special", 1},
    {"snek_emp_gote_inf_eisenbombers", "special", 1},
    {"snek_emp_gote_inf_leadbelchers", "special", 2},
    {"snek_emp_gote_inf_ironsides", "special", 1},
    {"snek_emp_gote_inf_longrifles", "special", 1},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end