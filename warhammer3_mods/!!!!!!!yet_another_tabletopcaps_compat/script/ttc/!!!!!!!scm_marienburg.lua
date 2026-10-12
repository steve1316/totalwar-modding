-- SCM Marienburg
local caps = {
    -- Empire
    {"hkrul_carriers", "special", 2},
    {"hkrul_carriers_ror", "special", 2},
    {"hkrul_klumpf", "special", 1},
    {"hkrul_manann_flagellant", "core"},
    {"hkrul_mar_art_paixhan_ror", "special", 2},
    {"hkrul_mar_art_scheepskanon", "special", 2},
    {"hkrul_mar_black_caps", "core"},
    {"hkrul_mar_bordermen_ror", "special", 2},
    {"hkrul_mar_cav_rijders", "core"},
    {"hkrul_mar_cav_rijders_crossbow", "core"},
    {"hkrul_mar_cleansing_flame", "special", 2},
    {"hkrul_mar_culverin", "special", 2},
    {"hkrul_mar_defenders", "special", 1},
    {"hkrul_mar_handguns", "core"},
    {"hkrul_mar_hellblaster", "rare", 2},
    {"hkrul_mar_hellstorm", "rare", 2},
    {"hkrul_mar_inf_crossbow", "core"},
    {"hkrul_mar_inf_goedendagers", "core"},
    {"hkrul_mar_inf_greatsword", "special", 1},
    {"hkrul_mar_inf_swords", "core"},
    {"hkrul_mar_knights_griffon", "rare", 2},
    {"hkrul_mar_knights_mariner", "core"},
    {"hkrul_mar_knights_mariner_fmc", "special", 1},
    {"hkrul_mar_mananns_blades_ror", "special", 1},
    {"hkrul_mar_mortar", "special", 2},
    {"hkrul_mar_naval_paixhan", "rare", 2},
    {"hkrul_mar_qual", "core"},
    {"hkrul_mar_qual_great", "core"},
    {"hkrul_mar_riverwarden", "core"},
    {"hkrul_mar_riverwarden_ror", "special", 1},
    {"hkrul_mar_sons_of_manann", "special", 2},
    {"hkrul_mar_teuling", "special", 1},
    {"hkrul_pion", "special", 1},
    {"hkrul_privateers", "core"},
    {"hkrul_privateers_dual_swords", "core"},
    {"ovn_mar_inf_knights_mariner_0", "special", 1},
    -- Other
    {"hkrul_fooger_ror", "special", 1},
    {"hkrul_mar_talons", "special", 1},
    -- Vampire Coast
    {"rhox_mar_cst_inf_sartosa_free_company_0", "core"},
    {"rhox_mar_cst_inf_sartosa_militia_0", "core"},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end
