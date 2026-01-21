-- derpy_emp_tanks
local caps = {
    -- Empire
    {"derpy_emp_tank_bulwark", "rare", 3},
    {"derpy_emp_tank_helblaze", "rare", 3},
    {"derpy_emp_tank_heldenhammer", "rare", 3},
    {"derpy_emp_tank_jagdpanzer", "rare", 3},
    {"derpy_emp_tank_griffon", "rare", 3},
    {"derpy_emp_tank_sigmars_fury_ror", "rare", 3},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end