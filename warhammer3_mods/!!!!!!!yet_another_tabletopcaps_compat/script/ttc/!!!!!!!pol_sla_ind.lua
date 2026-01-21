-- pol_sla_ind
local caps = {
    -- Slaanesh
    {"sla_rajput_1", "core"},
    {"sla_rajput_0", "core"},
    {"sla_rajput_parvatadar", "special", 1},
    {"sla_yaksha_parvatadar", "special", 2},
    {"sla_rakshasa", "special", 2},
    {"sla_daemonette_parvatadar", "special", 3},
    {"sla_sura_parvatadar", "rare", 3},
    -- Empire
    {"ind_sepoy_01", "special", 1},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end