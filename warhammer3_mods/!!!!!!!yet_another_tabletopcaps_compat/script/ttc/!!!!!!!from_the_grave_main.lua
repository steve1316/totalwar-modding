-- from_the_grave_main
local caps = {
    -- Vampire Counts
    {"kys_und_necro_zombie", "core", 1},
    {"kys_und_brood_horror_rider", "special", 2},
    {"kys_und_behemoth", "special", 2},
    {"kys_und_void_revenants", "special", 1},
    {"kys_und_shield_revenants", "special", 1},
    {"kys_und_basic_infantry", "special", 1},
    {"kys_und_bk_cav", "special", 2},
    {"kys_und_crossbow", "core", 1},
    {"kys_und_bk_foot", "special", 2},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end