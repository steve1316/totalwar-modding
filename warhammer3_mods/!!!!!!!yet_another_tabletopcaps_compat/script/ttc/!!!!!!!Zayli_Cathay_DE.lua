-- Lily's Cathay DE Overhaul + Unit Pack
local caps = {
    -- Grand Cathay
    {"zayli_cth_peasants", "core", 1},
    {"zayli_cth_executors", "core"},
    {"zayli_cth_militia", "core"},
    {"zayli_cth_nan_gau_archer", "core"},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end