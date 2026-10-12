-- Eustace's Cathay Artillery Pack
local caps = {
    -- Grand Cathay
    {"veh_cth_monitor", "special", 3},
    {"veh_cth_tank_ror", "special", 3},
    {"veh_cth_tank", "special", 3},
    {"cathay_bolt_thrower", "special", 2},
    {"cathay_mortar", "special", 2},
    {"cathay_mortar_alchemy", "special", 2},
    {"three_dragons", "rare", 2},
    {"bastion_cannon", "rare", 2},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end