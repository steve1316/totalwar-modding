-- The Jade-Blooded Vampires: Curse of Nongchang
local caps = {
    -- Jade-Blooded Vampires
    {"jbv_nugui_01", "special", 2},
    {"jbv_darkwater_ghost", "core", 1},
    -- Grand Cathay
    {"cth_jiangshi_summoned", "special", 2},
    -- Vampire Counts
    {"jbv_faithfuls_ancient_summoned", "core"},
    {"jbv_newbloods_summoned", "special", 2},
    {"jbv_warriors_1", "special", 2},
    {"jbv_ghost_host_summoned", "core"},
    {"jbv_gateguardian_summoned", "rare", 2},
    {"jbv_mogwai", "special", 2},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end