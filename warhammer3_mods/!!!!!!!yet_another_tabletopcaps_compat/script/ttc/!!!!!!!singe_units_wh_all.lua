-- singe_units_wh_all
local caps = {
    -- Bretonnia
    {"brt_questing_wardens", "special", 2},
    {"brt_foot_knight", "special", 1},
    {"brt_truffle_hounds", "core", 1},
    {"brt_guardians_realm", "special", 1},
    {"brt_hermit_knights", "special", 2},
    {"brt_ranger", "special", 1},
    {"brt_squire_polearm", "special", 1},
    {"brt_squire_longbow", "special", 1},
    {"brt_fire_trebuchet", "rare", 2},
    {"brt_flaming_trebuchet", "rare", 1},
    {"brt_brigand", "core", 1},
    {"brt_siege_trebuchet", "rare", 1},
    {"brt_squire_shield", "special", 1},
    {"great_falcons", "core", 1},
    -- Dark Elves
    {"singe_def_harridan", "special", 1},
    -- Grand Cathay
    {"singe_cth_celestial_ox", "special", 1},
    -- Khorne
    {"singe_kho_blood_throne", "rare", 1},
    -- Kislev
    {"singe_ksl_warriors_shields", "core", 1},
    -- Slaanesh
    {"singe_sla_hellseekers", "rare", 2},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end