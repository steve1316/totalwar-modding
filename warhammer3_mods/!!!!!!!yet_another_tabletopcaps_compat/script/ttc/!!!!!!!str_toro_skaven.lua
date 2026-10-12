-- Skaven Esoterica
local caps = {
    -- Skaven
    {"krakback_kill_squad", "special", 2},
    {"krakback_kill_squad_spears", "special", 2},
    {"poxigors", "special", 2},
    {"skaven_cav", "special", 2},
    {"skaven_mech", "rare", 3},
    {"skaven_mech_at", "rare", 3},
    {"skaven_mech_gat", "rare", 3},
    {"warp_bomber", "special", 2},
    {"warp_forged", "special", 2},
    {"warp_gunship", "special", 2},
    {"warp_runners", "special", 1},
    {"warp_zeppelin", "rare", 3},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end
