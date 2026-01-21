-- UD_Deithland_Machines
local caps = {
    -- Empire
    {"emp_steamsuits_volley", "special", 2},
    {"emp_steamsuits_great", "special", 2},
    {"emp_steamsuits_swords", "special", 2},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end