-- jvj_kadon
local caps = {
    -- Misc
    {"kadon_kin_chaos_dragon", "rare", 3},
    {"kadon_kin_spiders", "special", 1},
    {"kadon_kin_unicorn", "special", 1},
    {"kadon_kin_great_cave_squigs", "rare", 2},
    {"kadon_kin_griffon", "special", 1},
    {"kadon_kin_terradons", "special", 1},
    {"kadon_kin_ripperdactyls", "special", 1},
    {"kadon_kin_stag", "special", 1},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end