-- !barney_bearhero
local caps = {
    -- Kislev
    {"hef_frost_phoenix_guard", "special", 2},
    {"hef_sisters_of_frost", "rare", 1},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end