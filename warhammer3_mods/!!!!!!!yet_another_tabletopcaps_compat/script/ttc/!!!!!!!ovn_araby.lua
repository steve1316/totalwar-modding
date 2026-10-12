-- ovn_araby
local caps = {
    -- Araby
    {"ovn_arb_mon_book_djinn", "core", 1},
    {"ovn_arb_mon_tempest_djinn_summoned", "rare", 3},
    {"ovn_arb_mon_enchanted_rope_summoned", "special", 2},
    {"ovn_arb_mon_genie_summoned", "special", 3},
    {"ovn_arb_mon_desert_spirit_summoned", "rare", 2},
    {"ovn_arb_mon_fire_efreet_summoned", "rare", 2},
    {"ovn_arb_mon_sea_nymph_summoned", "rare", 2},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end