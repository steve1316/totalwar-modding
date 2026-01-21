-- str_cw_slaanesh
local caps = {
    -- Slaanesh
    {"str_cw_slaanesh_shield", "core"},
    {"str_cw_slaanesh_gw", "core"},
    {"str_cw_slaanesh_halberd", "core"},
    {"str_cw_slaanesh_gw_ror", "special", 1},
    {"str_cw_slaanesh_halberd_ror", "special", 1},
    {"str_cw_slaanesh_shield_ror", "special", 1},
    {"str_cw_slaanesh_knight", "special", 2},
    {"str_cw_slaanesh_knight_ror", "special", 2},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end