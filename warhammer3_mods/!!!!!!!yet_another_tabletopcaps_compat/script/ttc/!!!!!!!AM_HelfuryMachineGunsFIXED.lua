-- AM_HelfuryMachineGunsFIXED
local caps = {
    -- Empire
    {"wh_main_emp_art_machine_gun", "special", 3},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end