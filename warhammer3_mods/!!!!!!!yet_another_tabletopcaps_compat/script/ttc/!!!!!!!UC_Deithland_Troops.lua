-- UC_Deithland_Troops
local caps = {
    -- Empire
    {"emp_reiksmarines_shotguns", "special", 1},
    {"emp_reiksmarines_great", "special", 1},
    {"emp_reiksmarines_sawedoff", "special", 1},
    {"emp_reiksmarines_spellshields", "special", 1},
    {"emp_reiksmarines_axelocks", "special", 1},
    {"emp_reiksmarines_hatchetlocks", "special", 1},
    {"emp_reiksmarines", "special", 1},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end