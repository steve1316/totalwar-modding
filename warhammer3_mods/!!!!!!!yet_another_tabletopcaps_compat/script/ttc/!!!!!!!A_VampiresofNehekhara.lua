-- Vampires of Nehekhara
local caps = {
    -- Tomb Kings
    {"lsh_nehekvamp_mummy_zombie_arkhan", "core"},
    {"lsh_nehekvamp_scarab_bat2", "core"},
    {"lsh_nehekwight_guard_arkhan", "special", 1},
    {"lsh_nehekwight_guard_great_weapons_arkhan", "special", 1},
    {"lsh_nehekwight_knight_arkhan", "special", 1},
    {"lsh_nehekwight_knight_lance_arkhan", "special", 2},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end
