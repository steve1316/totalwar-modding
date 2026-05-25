-- Zayli_Cathay_DE
local caps = {
    -- Grand Cathay
    {"zayli_cth_peasants", "core", 1}
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end