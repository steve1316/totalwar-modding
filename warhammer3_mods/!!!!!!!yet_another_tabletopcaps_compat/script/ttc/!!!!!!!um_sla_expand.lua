-- um_sla_expand and sla_beast_expand
local caps = {
    -- Slaanesh
    {"sla_slaangor", "core"},
    {"sla_serpent", "special", 2},
    {"sla_glutos", "special", 2},
    {"sla_mutant", "rare", 1},
    {"sla_steed_dragon", "rare", 2},
    {"sla_steed_dragon_ror", "rare", 2},
    {"sla_mez_ror", "rare", 3},
    {"sla_goz_ror", "rare", 3},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end