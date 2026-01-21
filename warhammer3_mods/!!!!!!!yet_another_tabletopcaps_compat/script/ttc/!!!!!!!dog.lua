-- dog
local caps = {
    -- Vampire Coast
    {"cst_corsairs", "special", 1},
    {"cst_deathship", "special", 2},
    {"cst_medium_ship", "special", 3},
    {"cst_medium_ship_2", "special", 3},
    {"cst_medium_ship_1", "special", 3},
    {"cst_ghostship", "rare", 3},
    {"cst_harkonship_third", "rare", 3},
    {"harkonship_test_jericho", "rare", 3},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end