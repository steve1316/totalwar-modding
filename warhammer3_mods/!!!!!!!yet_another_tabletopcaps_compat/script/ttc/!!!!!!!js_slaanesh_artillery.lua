-- js_slaanesh_artillery
local caps = {
    -- Slaanesh
    {"js_sla_soul_bombers", "core", 1},
    {"js_sla_pleasure_harvester", "special", 2},
    {"js_sla_soul_runner", "rare", 2},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end