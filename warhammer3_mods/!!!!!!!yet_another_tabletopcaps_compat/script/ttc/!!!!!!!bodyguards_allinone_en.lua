-- Ruo's Bodyguards & Mounts All-In-One
local caps = {
    -- Empire
    {"emp_engineer_retinue_1", "special", 1},
    {"emp_engineer_retinue_2", "special", 1},
    {"emp_engineer_retinue_3", "special", 2},
    {"emp_engineer_retinue_4", "special", 2},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end
