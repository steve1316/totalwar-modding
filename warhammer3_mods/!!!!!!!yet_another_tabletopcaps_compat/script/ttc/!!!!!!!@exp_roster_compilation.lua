-- @exp_roster_compilation
local caps = {
    -- Chaos Dwarfs
    {"deco_chd_gnoblar_slaves", "core"},
    {"deco_chd_ogre_slaves", "core"},
    {"deco_chd_zealots", "special", 1},
    {"deco_chd_acolytes", "special", 1},
    {"deco_chd_quarrellers", "core"},
    {"deco_chd_naphtha", "special", 1},
    {"deco_chd_annihilators", "special", 2},
    {"deco_chd_ravagers", "special", 1},
    {"deco_chd_lava_trolls", "special", 2},
    -- Beastmen
    {"dec_bestigor_dual_axe", "special", 1},
    {"dec_gouge_horns", "special", 2},
    {"dec_gor_great_axe", "special", 1},
    -- Dark Elves
    {"dec_tower_masters", "rare", 1},
    {"dec_hunters_anath_raema", "special", 1},
    {"dec_lords_oblivion", "special", 2},
    {"dec_magma_dragon", "rare", 3},
    -- Dwarfs
    {"deco_prospectors", "core"},
    {"deco_old_guard", "special", 2},
    {"deco_hammerers_dual", "special", 2},
    {"deco_irondrakes_drakefire", "special", 1},
    {"deco_bugman_thrower", "rare", 1},
    {"dwf_kou_dreadnaught", "rare", 3},
    -- Greenskins
    {"deco_snotlings", "core"},
    {"deco_forest_goblin_swords", "core"},
    {"deco_forest_goblin_spears", "core"},
    {"deco_night_goblin_spears", "core"},
    {"deco_hill_goblins", "core"},
    {"deco_savage_orc_spears", "core"},
    {"deco_big_uns_shields", "core"},
    {"deco_savage_big_uns_gw", "core"},
    {"deco_black_orc_dual", "special", 2},
    {"str_urgat_wolf_chariot", "special", 1},
    {"deco_savage_giant", "rare", 2},
    {"deco_armored_colossal_squig", "rare", 2},
    {"grn_poop", "core"},
    -- High Elves
    {"deco_avelorn_maidens", "core"},
    {"deco_high_helms", "special", 2},
    {"deco_griffon_knights", "rare", 2},
    {"deco_skywardens", "special", 2},
    {"deco_bladelords", "rare", 1},
    -- Norsca
    {"deco_nor_pit", "special", 1},
    {"deco_nor_bondsmen", "core"},
    {"deco_nor_reavers", "special", 1},
    {"deco_nor_valkyrie", "special", 2},
    {"deco_nor_hydra", "rare", 2},
    {"deco_nor_wolf", "special", 2},
    -- Ogre Kingdoms
    {"dec_ogre_bulls_gw", "core"},
    {"dec_giantbreakers", "special", 2},
    {"dec_rhinox_bull", "special", 2},
    {"dec_ember_drake", "special", 3},
    {"dec_ice_mammoth", "special", 2},
    -- Empire
    {"deco_doom_prophets", "special", 1},
    {"deco_ironsides", "special", 1},
    {"deco_knights_lynx", "special", 1},
    {"deco_roadwardens", "core"},
    -- Vampire Counts
    {"dec_reapers", "core"},
    {"dec_lahmian", "special", 2},
    {"dec_drakenhof", "special", 2},
    {"dec_hell_knights", "special", 2},
    {"dec_kastellans", "rare", 2},
    -- Wood Elves
    {"deco_handmaidens_torothal", "core"},
    {"deco_dryads_willow", "core"},
    {"deco_wildwood_wardens", "special", 2},
    {"deco_meadow_chariots", "special", 1},
    {"deco_glade_knights", "special", 2},
    {"deco_wind_riders", "special", 1},
    -- Other
    {"deco_dryads_willow_malicious", "core"},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end