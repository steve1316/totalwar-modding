-- Trajanns_Sentinels
local caps = {
    -- Tomb Kings
    {"traj_malarok_necroserpent", "special", 2},
    {"traj_gurrash_ushabti", "special", 2},
    {"traj_nyrask_ror", "rare", 1},
    {"traj_malarok_stalkers", "special", 2},
    {"traj_barthuum_ror", "rare", 2},
    {"traj_inathma_ror", "rare", 2},
    {"traj_talimar_ror", "rare", 3},
    {"traj_rhakaan_ror", "rare", 3},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end