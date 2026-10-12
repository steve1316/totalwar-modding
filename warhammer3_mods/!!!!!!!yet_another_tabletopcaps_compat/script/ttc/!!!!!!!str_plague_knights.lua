-- Mortal Warriors of Nurgle
local caps = {
    -- Nurgle
    {"nrg_jabber", "rare", 3},
    {"pk_plague_brethren", "core"},
    {"pk_plague_halberds", "core"},
    {"pk_plague_halberds_ror", "special", 1},
    {"pk_plague_scythe", "core"},
    {"pk_plague_scythe_ror", "special", 1},
    {"pk_plague_warriors", "core"},
    {"pk_plague_warriors_ror", "special", 1},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end
