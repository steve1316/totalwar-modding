-- @xou_high_elves
local caps = {
    -- High Elves
    {"cot_hef_inf_wardancers", "core", 1},
    {"cot_hef_mon_rocriders_lance", "core", 1},
    {"cot_hef_inf_marines", "special", 1},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end