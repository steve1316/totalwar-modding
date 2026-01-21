-- doggo
local caps = {
    -- Vampire Coast
    {"cst_baby_bess_rocket", "rare", 2},
    {"cst_baby_bess_rocket_real", "rare", 2},
    {"cst_princess_bess_cannon", "rare", 2},
    {"cst_jericho_cannon", "rare", 2},
    {"cst_super_mortar_sartosa", "special", 2},
    {"cst_sartosa_mortar_triple_cannons", "special", 2},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end