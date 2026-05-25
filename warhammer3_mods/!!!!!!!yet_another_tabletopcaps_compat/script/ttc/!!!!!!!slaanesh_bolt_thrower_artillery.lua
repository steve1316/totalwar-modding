-- slaanesh_bolt_thrower_artillery
local caps = {
    -- Slaanesh
    {"gow_new_sla_art_reaper_bolt_thrower_0", "rare", 1},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end