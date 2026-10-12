-- Imperial Elite || Empire Late Game Unit Mod
local caps = {
    -- Empire
    {"mod_emp_guard", "special", 1},
    {"mod_emp_priest", "special", 2},
    {"mod_emp_soldier", "special", 2},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end
