-- ovn_grudgebringers
local caps = {
    -- Grudgebringers
    {"wh_main_emp_inf_handgunners_ovn_gru", "special", 1},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end