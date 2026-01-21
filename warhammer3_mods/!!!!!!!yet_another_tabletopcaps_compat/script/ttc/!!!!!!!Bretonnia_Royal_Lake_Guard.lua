-- Bretonnia_Royal_Lake_Guard
local caps = {
    -- Bretonnia
    {"driblex_brt_royal_lake_guard_trebuchet_starbreaker", "rare", 2},
    {"driblex_brt_royal_lake_guard_lion_sorcha", "rare", 3},
    {"driblex_brt_royal_lake_guard_lion_sarrosh", "rare", 3},
    {"driblex_brt_royal_lake_guard_javelin", "special", 2},
    {"driblex_brt_royal_lake_guard_halberd", "rare", 1},
    {"driblex_brt_royal_lake_guard_longbow", "special", 2},
    {"driblex_brt_royal_lake_guard_thunderlancers", "rare", 2},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end