-- GMD_NURGLE_TANK
local caps = {
    -- Nurgle
    {"gmd_nur_tank", "rare", 3},
    {"gmd_nur_veh_steam_tank_volley_gun", "rare", 3},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end