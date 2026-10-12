-- Regiments of Renown Compilation
local caps = {
    -- Beastmen
    {"ror_beast_gibberkin", "special", 2},
    {"ror_beast_gulmoth", "special", 2},
    {"ror_beast_inmates", "special", 1},
    {"ror_beast_nashara", "special", 1},
    {"ror_beast_redmaw", "special", 1},
    {"ror_beast_shadowg", "special", 1},
    {"ror_beast_toxote", "special", 1},
    {"ror_beast_ungrol", "special", 1},
    {"ror_beast_ymgir", "rare", 1},
    -- Bretonnia
    {"ror_bret_dason", "rare", 2},
    {"ror_bret_elcyd", "special", 2},
    {"ror_bret_ennar", "special", 1},
    {"ror_bret_fastric", "rare", 2},
    {"ror_bret_flame", "special", 2},
    {"ror_bret_fracasse", "special", 2},
    {"ror_bret_mayonne", "special", 1},
    {"ror_bret_mob", "special", 1},
    {"ror_bret_rapscallards", "special", 1},
    {"ror_bret_salles", "rare", 2},
    -- Chaos Dwarfs
    {"deco_backstabbers", "special", 1},
    {"deco_bahal_guardians", "special", 2},
    {"deco_doombringer", "rare", 2},
    {"deco_kinslayers", "special", 2},
    {"deco_magma_beasts", "special", 2},
    {"deco_warriors_horde", "special", 1},
    -- Dark Elves
    {"deco_burning_dark", "special", 2},
    {"deco_ravenspears", "special", 1},
    {"deco_rimeshards", "special", 1},
    {"deco_soulskulls", "special", 1},
    {"deco_voiceless", "special", 1},
    {"deco_witchguard", "special", 2},
    -- Empire
    {"deco_crimson_defiants", "special", 1},
    {"deco_forest_patrol", "special", 1},
    {"deco_grof_riders", "special", 2},
    {"deco_von_kragsburg", "special", 1},
    {"deco_white_reavers", "special", 1},
    -- Greenskins
    {"deco_bonebreakers", "special", 2},
    {"deco_bouncers", "special", 2},
    {"deco_drillaz", "special", 2},
    {"deco_frik", "special", 1},
    {"deco_grokkamobs", "special", 2},
    {"deco_harboth", "special", 1},
    -- Kislev
    {"wh3_main_ksl_cav_bolgasgrad_ror", "special", 2},
    {"wh3_main_ksl_cav_dawn_ror", "special", 2},
    {"wh3_main_ksl_inf_alexandronov_ror", "special", 2},
    {"wh3_main_ksl_inf_stalgrad_ror", "special", 1},
    -- Tomb Kings
    {"deco_bhagar", "rare", 3},
    {"deco_emerald", "special", 2},
    {"deco_royal_chariot", "special", 2},
    {"deco_underworld", "rare", 1},
    {"deco_wight", "special", 1},
    {"deco_zandri", "special", 1},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end
