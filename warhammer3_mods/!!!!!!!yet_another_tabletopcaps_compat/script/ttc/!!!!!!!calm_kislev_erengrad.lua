-- calm_kislev_erengrad
local caps = {
    -- Kislev
    {"calm_hajduks", "core", 1},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end