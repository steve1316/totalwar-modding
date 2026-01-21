-- Cathay_helblaster
local caps = {
    -- Grand Cathay
    {"veh_cth_monitor", "special", 3},
    {"veh_cth_tank_ror", "special", 3},
    {"veh_cth_tank", "special", 3},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end