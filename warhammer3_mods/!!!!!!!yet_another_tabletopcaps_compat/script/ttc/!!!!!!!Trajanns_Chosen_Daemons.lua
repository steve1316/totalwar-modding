-- Trajann's Chosen Daemons
local caps = {
    -- Nurgle
    {"nrg_plaguebearer_chosen", "special", 2},
    {"nrg_plaguebearer_chosen_ror", "rare", 1},
    -- Slaanesh
    {"sla_daemonette_chosen", "rare", 2},
    {"sla_daemonette_chosen_ror", "rare", 1},
    -- Tzeentch
    {"tze_horror_chosen", "rare", 3},
    {"tze_horror_chosen_ror", "rare", 3},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end
