-- !!!phy_runic_units.pack
local caps = {
    -- Dwarfs
    {"phy_dwf_rune_guardian", "rare", 1},
    {"phy_dwf_rune_guardian_ror", "rare", 1},
    {"phy_dwf_rune_golem_shield", "rare", 3},
    {"phy_dwf_rune_golem_ror", "rare", 3},
    {"phy_dwf_clockwork_thunderers", "special", 2},
    {"phy_dwf_clockwork_thunderers_ror", "special", 2},
    {"phy_dwf_shard_dragon_ror", "rare", 3},
    {"phy_dwf_shard_dragon_collar", "rare", 3},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end