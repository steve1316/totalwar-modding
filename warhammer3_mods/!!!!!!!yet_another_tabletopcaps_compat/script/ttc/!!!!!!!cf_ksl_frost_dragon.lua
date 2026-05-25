-- cf_ksl_frost_dragon
local caps = {
    -- Kislev
    {"cf_ksl_frost_dragon", "rare", 3},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end