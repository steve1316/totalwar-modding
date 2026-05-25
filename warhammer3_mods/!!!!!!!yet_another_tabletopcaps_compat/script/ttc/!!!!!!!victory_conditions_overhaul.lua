-- victory_conditions_overhaul
local caps = {
    -- Vampire Coast
    {"vco_unit_sartosa_exile_knight", "core", 1},
    {"vco_unit_sartosa_maneater_ironfist", "special", 2},
    {"vco_unit_sartosa_dragonlord", "special", 2},
    {"vco_unit_sartosa_golgfags_maneaters", "special", 2},
    {"vco_unit_sartosa_slayer_pirate", "rare", 1},
    {"vco_unit_sartosa_cathayan_buccaneer", "core", 1},
    {"vco_unit_sartosa_maneaters_great_weapon", "special", 2},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end