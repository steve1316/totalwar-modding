-- Guns_of_Bretonnia_III
local caps = {
    -- Bretonnia
    {"bret_pavisiers", "special", 2},
    {"bret_arquebusiers", "core", 1},
    {"bret_levy_bowmen", "core", 1},
    {"bret_mounted_body_guards", "special", 3},
    {"bret_noble_swordsmen", "special", 2},
    {"bret_melee_elite", "special", 2},
    {"bret_halberdiers", "core", 1},
    {"bret_swordsmen", "core", 1},
    {"bret_milicia", "core", 1},
    {"bret_art_mortar", "special", 2},
    {"bret_acolytes", "special", 1},
    {"bret_crossbowmen", "core", 1},
    {"bret_art_helstorm_rocket_battery", "rare", 2},
    {"bret_art_great_cannon", "special", 2},
    {"bret_mounted_cuirassiers", "special", 2},
    {"bret_armored_halberdiers", "special", 2},
    {"bret_noble_halberdiers", "special", 1},
    {"bret_mounted_conquistadors", "special", 2},
    {"bret_armored_fusiliers", "special", 2},
    {"bret_musketeers", "special", 1},
    {"bret_mounted_pistoliers", "special", 2},
    {"bret_longbowmen", "special", 2},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end