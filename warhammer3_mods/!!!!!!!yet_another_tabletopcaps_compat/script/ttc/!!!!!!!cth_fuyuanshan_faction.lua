-- cth_fuyuanshan_faction
local caps = {
    -- Grand Cathay
    {"cth_fys_peasant_firelancer", "core"},
    {"cth_fys_jade_warrior_lancer", "special", 1}
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end