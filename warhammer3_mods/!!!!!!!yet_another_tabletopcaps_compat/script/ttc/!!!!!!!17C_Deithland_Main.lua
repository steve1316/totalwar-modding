-- 17C_Deithland_Main
local caps = {
    -- Empire
    {"emp_deithguard_axelocks", "special", 1},
    {"emp_deithguard_blasterkeys", "special", 1},
    {"emp_cinderwind_arbalests", "core", 1},
    {"emp_chemlancers_lances", "core", 1},
    {"emp_tillerguns", "special", 1},
    {"emp_danzigers", "special", 1},
    {"emp_mortar_muskets", "special", 1},
    {"emp_gallowdogs", "core", 1},
    {"emp_pyrehulks_volley", "special", 2},
    {"emp_chemlancers_drilling_guns", "special", 2},
    {"emp_pyrehulks_fusilaxe", "special", 2},
    {"emp_hellbores", "special", 1},
    {"emp_fumecorps_bayos", "core", 1},
    {"emp_deithguard_shields", "special", 1},
    {"emp_cinderbell", "rare", 2},
    {"emp_vinderbane_armored", "special", 3},
    {"emp_vinderbane", "special", 2},
    {"emp_engelspeers", "special", 1},
    {"emp_gottzorn", "rare", 3},
    {"emp_drakebiter", "special", 2},
    {"emp_knellgun", "special", 2},
    {"emp_culverin", "special", 2},
    {"emp_autofalcon_armored", "special", 3},
    {"emp_gottzorn_knellgun", "rare", 3},
    {"emp_mountain_gun", "special", 2},
    {"emp_gottzorn_flame", "rare", 3},
    {"emp_cofferglare", "rare", 2},
    {"emp_autofalcon", "special", 3},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end