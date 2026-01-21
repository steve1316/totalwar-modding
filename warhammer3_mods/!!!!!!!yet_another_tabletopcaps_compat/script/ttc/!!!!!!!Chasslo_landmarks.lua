-- Chasslo_landmarks
local caps = {
    -- Wood Elves
    {"CLE_Oreon_Warband", "rare", 1},
    {"CLE_Hallowed_Oak", "rare", 3},
    -- Bretonnia
    {"Chasslo_First_Trebuchet", "rare", 2},
    {"CLE_Righteous_mob", "core", 1},
    {"CLE_Fay_stags_knight", "rare", 2},
    {"CLE_Lady_lion", "special", 2},
    {"CLE_Ksl_Snowhorn", "rare", 3},
    {"CLE_Ostankya_Arachnarok", "rare", 3},
    -- Dwarfs
    {"Chasslo_Redmane_Forgehands", "special", 1},
    {"Chasslo_Karag_Ironsmiths", "special", 2},
    {"Chasslo_Berserker_Slayers", "special", 1},
    {"Chasslo_IronBrotherhood", "special", 2},
    {"Chasslo_Iron_Guard", "special", 2},
    {"Chasslo_Grimnir_Sons", "special", 1},
    {"Chasslo_BlackWater_Squadron", "special", 2},
    {"Chasslo_Black_Bolt_Throwers", "special", 1},
    -- Orcs
    {"Chasslo_Stompin_Cobb", "rare", 3},
    {"Chasslo_Brood_Queen", "rare", 3},
    -- Khorne
    {"CLE_Tchar_Destroyers", "special", 2},
    {"CLE_Blood_Shriekers", "special", 2},
    -- Kislev
    {"CLE_Jormungandr", "rare", 3},
    -- Lizardmen
    {"CLE_Sotek_Scion", "rare", 3},
    {"CLE_double_bastiladon", "special", 2},
    -- Nurgle
    {"CLE_Patient_Zero", "special", 1},
    {"CLE_Blight_Dragon", "rare", 2},
    -- Norsca
    {"CLE_Wintergors", "special", 1},
    {"Chasslo_Ragnars_Wolves", "special", 2},
    {"Chasslo_Mutated_Trolls", "special", 2},
    -- Ogres
    {"CLE_Silver_Guts", "special", 2},
    {"CLE_Maw_Deep_Jaws", "special", 2},
    {"CLE_Gorger_Matron", "special", 2},
    -- Slaanesh
    {"CLE_Ghrond_Librarian", "rare", 2},
    -- Empire
    {"Chasslo_Chamon_Destroyer", "rare", 3},
    -- Vampire Coast
    {"CLE_Jaego_Faithful", "special", 2},
    {"CLE_Carcassone_Damned_Knight", "special", 1},
    {"CLE_Manann_Leviathan", "rare", 2},
    -- Vampire Counts
    {"Chasslo_Knights_Iranna", "special", 2},
    {"CLE_Lurking_Penumbra", "rare", 2},
    {"CLE_Tian_Bei", "rare", 3},
    {"CLE_Mannfred_heirotitan", "rare", 3},
    -- Warriors of Chaos
    {"Chasslo_Vashtorrs_Opus", "rare", 2},
    {"Chasslo_Azazel_Flagellants", "core"},
    {"Chasslo_Great_Oak_Mordheim", "rare", 3},
    {"Chasslo_Doomspeakers", "special", 2},
}

local ttc = core:get_static_object("tabletopcaps")
if ttc then
    ttc.add_setup_callback(function()
        ttc.add_unit_list(caps, true)
    end)
end