-- Nurgle_Chargers
local caps = {
    -- Nurgle
    {"pox_walker", "core"},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end