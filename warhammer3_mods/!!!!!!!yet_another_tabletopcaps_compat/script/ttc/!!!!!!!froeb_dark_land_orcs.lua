-- Dark Land Orcs
local caps = {
    -- Greenskins
    {"frb_dark_land_bulwarks_ror", "rare", 2},
    {"frb_scrap_shooters_ror", "special", 2},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end
