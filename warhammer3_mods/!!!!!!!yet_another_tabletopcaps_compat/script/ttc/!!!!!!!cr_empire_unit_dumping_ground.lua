-- Celestial Hurricanum
local caps = {
    -- Empire
    {"cr_emp_veh_hurricanum_0", "rare", 3},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end
