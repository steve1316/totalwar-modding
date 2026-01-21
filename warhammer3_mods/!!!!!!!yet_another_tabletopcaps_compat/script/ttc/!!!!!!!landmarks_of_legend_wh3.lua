-- !landmarks_of_legend_wh3
local caps = {
    -- Bretonnia
    {"braconniers", "core"},
    {"le_grande_knights", "special", 2},
    {"jacometta_knights", "special", 2},
    {"braconnier_horsemen", "special", 1},
    -- Lizardmen
    {"tlax_spears_1", "core"},
    {"tlax_warriors_1", "core"},
    -- Dwarfs
    {"ulthers_dragon_company", "core"},
    {"greybeard_mining_drill", "rare", 1},
    -- Chaos Dwarfs
    {"chd_skaven_labourers", "core"},
    -- Orcs
    {"top_knotz_savages", "special", 1},
    -- Khorne
    {"axe_brothers", "special", 1},
    {"bst_khornataurs_0", "special", 2},
    {"bst_khornataurs_1", "special", 2},
    -- Nurgle
    {"nur_pox_bowmen", "core"},
    -- Tomb Kings
    {"tmb_saurus_warriors_aux_0", "core"},
    {"tmb_saurus_warriors_aux_1", "core"},
    {"tmb_cold_one_chariots", "special", 2},
    {"tmb_undead_bolt_thrower", "special", 1},
    -- Empire
    {"gleaming_shield_knights", "special", 3},
    -- Vampire Coast
    {"cst_undead_ogre", "special", 2},
    {"ethereal_saurus_spearmen_1", "core"},
    {"ethereal_saurus_warriors_1", "core"},
    {"nightmare_legion", "core"},
    {"sartosan_handgunners", "special", 1},
    {"damned_knights_errant_2", "special", 1},
    {"damned_questing_knights_0", "special", 1},
    -- Beastmen
    {"soul_eater_1", "rare", 3},
    {"soul_eater_2", "rare", 3},
    -- Vampire Counts
    {"hanged_men", "special", 1},
    {"green_skulls", "special", 1},
    {"dwarf_skeletons_1", "core"},
    {"the_arisen", "core"},
    {"the_wretches", "core"},
    {"the_hungry", "core"},
    {"helmuts_own", "special", 1},
    {"rackspire_dead", "special", 1},
    {"stonewraith_wights", "special", 1},
    {"no_name_legion", "special", 2},
    {"doomed_legion", "special", 2},
    {"red_death_knights", "special", 2},
    {"vmp_imperial_dragon", "rare", 3},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end