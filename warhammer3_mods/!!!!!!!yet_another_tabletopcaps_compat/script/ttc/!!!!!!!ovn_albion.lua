-- ovn_albion
local caps = {
    -- Albion
    {"calm_alb_crow", "core", 1},
    {"calm_alb_raven", "core", 1},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end