-- laf_hag_mothers
local caps = {
    -- Kislev
    {"laf_ksl_mon_treeman_0", "rare", 3},
    {"laf_ksl_mon_arachnarok_spider_0", "rare", 3},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end