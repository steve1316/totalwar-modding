-- !!kuresh_mercs1
local caps = {
    -- Kuresh Mercenaries
    {"kou_ace_km_pyrenaga", "rare", 2},
    {"kou_ace_km_spittin_naja", "special", 2},
    {"kou_ace_km_dread_maw", "rare", 2},
    {"kou_ace_km_orobagor", "special", 1},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end