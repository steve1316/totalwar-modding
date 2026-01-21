-- werebeastspol
local caps = {
    -- Wood Elves
    {"celebrant_wef01", "core"},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end