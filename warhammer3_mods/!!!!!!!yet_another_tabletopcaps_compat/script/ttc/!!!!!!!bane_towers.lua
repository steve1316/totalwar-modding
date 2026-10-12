-- Tzeentch's Bane Towers
local caps = {
    -- Warriors of Chaos
    {"tz_bane_tower", "rare", 3},
    {"tz_bane_tower_ror", "rare", 3},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end
