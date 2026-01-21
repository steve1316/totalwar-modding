-- ab_mixu_legendary_lords
local caps = {
    -- Empire
    {"mixu_emp_mon_promethean_riders", "special", 3},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end