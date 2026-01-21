-- snek_guns_of_the_empire
local caps = {
    -- Empire
    {"snek_emp_gote_inf_juggernauts", "special", 3},
    {"snek_emp_gote_cav_pegasus_pistolkorps", "special", 1},
    {"snek_emp_art_landship", "rare", 3},
    {"snek_emp_gote_inf_rocketeers", "special", 2},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end