-- loupi_twelve_realms_IE
local caps = {
    -- Misc
    {"loupi_wildkin", "special", 2},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end