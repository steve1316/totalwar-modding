-- Initialize the settings with default values.
local mct_settings = {
    disable_smithies = false,
    spawn_percentage = 0.75,
    enabled_encounter_skin_ids = {},
    enabled_mods = {},
    enable_all_encounter_skins = true,
    enable_randomized_encounter_force_generation = false,
    use_only_modded_units = false,
    enable_compatibility_with_supported_mods = false,
    randomized_encounter_force_generation_difficulty = "easy",
    enable_basic_progressive_difficulty = false,
    turn_number_from_easy_to_medium = 10,
    turn_number_from_medium_to_hard = 20,
    enable_all_factions = true,
    enabled_faction_keys = {},
    -- faction_overrides = {
    --     "tmb",
    --     "cst",
    --     "def",
    --     "hef",
    --     "lzd",
    --     "skv",
    --     "chd",
    --     "kho",
    --     "ksl",
    --     "tze",
    --     "cth",
    --     "nur",
    --     "ogr",
    --     "sla",
    --     "bst",
    --     "wef",
    --     "nor",
    --     "brt",
    --     "chs",
    --     "dwf",
    --     "emp",
    --     "grn",
    --     "vmp",
    -- },
    difficulties = {
        easy = {
            tiers = {1, 2},
            min_units = 10,
            max_units = 13,
            unit_experience_amount = {1, 3},
            lord_level_range = {5, 10},
            limits = {
                hero = {0, 0},
                melee_infantry = {3, 6},
                missile_infantry = {0, 3},
                melee_cavalry = {0, 2},
                missile_cavalry = {0, 2},
                monstrous_infantry = {0, 2},
                monstrous_cavalry = {0, 2},
                war_beast = {0, 2},
                chariot = {0, 0},
                warmachine = {0, 0},
                monster = {0, 0},
                generic = {0, 0},
            }
        },
        medium = {
            tiers = {1, 3},
            min_units = 14,
            max_units = 16,
            unit_experience_amount = {3, 5},
            lord_level_range = {10, 15},
            limits = {
                hero = {0, 1},
                melee_infantry = {3, 5},
                missile_infantry = {0, 3},
                melee_cavalry = {0, 2},
                missile_cavalry = {0, 2},
                monstrous_infantry = {0, 2},
                monstrous_cavalry = {0, 2},
                war_beast = {0, 2},
                chariot = {0, 1},
                warmachine = {0, 1},
                monster = {0, 1},
                generic = {0, 1},
            }
        },
        hard = {
            tiers = {1, 5},
            min_units = 17,
            max_units = 20,
            unit_experience_amount = {5, 7},
            lord_level_range = {15, 20},
            limits = {
                hero = {0, 2},
                melee_infantry = {4, 6},
                missile_infantry = {2, 4},
                melee_cavalry = {0, 2},
                missile_cavalry = {0, 2},
                monstrous_infantry = {0, 2},
                monstrous_cavalry = {0, 2},
                war_beast = {0, 2},
                chariot = {0, 1},
                warmachine = {0, 1},
                monster = {0, 1},
                generic = {0, 1},
            }
        }
    },
    ordered_slider_keys = {
        "hero",
        "melee_infantry",
        "missile_infantry",
        "melee_cavalry",
        "missile_cavalry",
        "monstrous_infantry",
        "monstrous_cavalry",
        "war_beast",
        "chariot",
        "warmachine",
        "monster",
        "generic",
    }
}

local encounter_data = {
    {id = 33, text = "Skeleton with treasure on a cliffside 1"},
    {id = 34, text = "Skeleton with treasure on a cliffside 2"},
    {id = 38, text = "Giant Skull"},
    {id = 36, text = "Totem"},
    {id = 42, text = "Obelisk"},
    {id = 35, text = "Shipwreck 1"},
    {id = 37, text = "Shipwreck 2"},
    {id = 39, text = "Shipwreck 3"},
    {id = 40, text = "Shipwreck 4"},
    {id = 41, text = "Shipwreck 5"},
    {id = 43, text = "Shipwreck 6"},
    {id = 44, text = "Shipwreck 7"},
}

-- TODO: This needs to be periodically updated whenever new mods are added/removed.
local supported_mods = {
    "!cr_immortal_empires_expanded", -- Immortal Empires Expanded
    "vanilla",
    "!!!!!!champions_of_undeath_bloodline_agents",
    "!!!!!!Champions_of_undeath_merged_fun_tyme",
    "!!!bruiser_careers",
    "!!!calm_animals_for_wood_elves",
    "!!!cou_blood_knight_heretics_live_build",
    "!!!d3rpyVersaEng",
    "!!!laf_dwarfs",
    "!!!lost_calm_jurassic_normal",
    "!!!lost_calm_nakai_normal",
    "!!!phy_runic_units",
    "!!_sartosa_overhaul",
    "!!YL_binzhong",
    "!ak_kraka3",
    "!cody_dwf_various_things",
    "!cr_beastman_unit_dumping_ground",
    "!cr_daemon_unit_dumping_ground",
    "!cr_elf_unit_dumping_ground",
    "!cr_empire_unit_dumping_ground",
    "!cr_skaven_unit_dumping_ground",
    "!derpy_noinruneguardian",
    "!kislev",
    "!uber_zoat_lord",
    "!xou_age_TKExtended",
    "!zfcr_unique_steam_tanks",
    "@Deer24batuoniya",
    "@Deer24diguochuanqi",
    "@Deer24HEF",
    "@DEERKSL",
    "@LOW_Dragon_Princes_Legion",
    "@whc_cth_unit_wuh_7",
    "@xou_high_elves",
    "A_VampiresofNehekhara",
    "ab_mixu_legendary_lords",
    "ab_unwashed_masses",
    "archer_fuyuanshan_faction",
    "bane_towers",
    "bastilean_bloodwrack_hero_whiii",
    "Blood_Rager_Main_Shadowman",
    "Bretonnia_Royal_Lake_Guard",
    "chaos_champions",
    "chd_chaos_dwarfs_airship",
    "Chosen_Archers_of_Tzeentch",
    "cipher_wef_units",
    "cth_yinyin_pol",
    "dead_jade_army_pack",
    "DEER24Cathay",
    "derpy_chd_aeromachines",
    "derpy_dwf_burloks_patents",
    "derpy_dwf_polearms",
    "derpy_emp_tanks",
    "derpy_grn_looted",
    "derpy_gunpowder_units",
    "derpy_gunpowder_units_add",
    "derpy_hashuts_polearm",
    "derpy_ksl_tanks",
    "derpy_um_mecha_dogs",
    "dog",
    "doggo",
    "drg_gr_khorne_spawn",
    "drg_gr_nrg_spawn_5_2",
    "Drg_gr_tztch_spawn",
    "Dwarf_Land_Ship",
    "Elven_Artillery",
    "froeb_bonepillar_champions",
    "GMD_NURGLE_TANK",
    "gorilla_warcastle_final",
    "ghs_great_harmony",
    "Guns_of_Bretonnia_III",
    "IronScorpion",
    "KslUni",
    "laf_hag_mothers",
    "laf_ostankya_chicken_hut",
    "loupi_ten_kingdoms_IE",
    "MikeyWickermen_5_2",
    "Nurgle_Abomination",
    "Nurgle_Chargers",
    "pol_sla_ind",
    "possibly a verminlord",
    "scm_beasts_most_foul",
    "str_skaven_clans",
    "str_toro_skaven",
    "seggs_cst_expansion",
    "sla_beast_expand",
    "snek_guns_of_the_empire",
    "str_cw_slaanesh",
    "str_plague_knights",
    "sug_flying_sword_tze_chosen",
    "Trajanns_Chosen_Daemons",
    "Trajanns_Khorne_Compilation",
    "Trajanns_Sentinels",
    "trojan_archer",
    "17C_Deithland_Main",
    "Um_verminlord",
    "unitsofnaggarothsamarai",
    "werebeastspol",
    "Zerooz_All_Units",
    "cf-Ksl-units",
    "thm_gnomes",
    "fairlight_beta",
    "!kitties",
    "!alshua_go_squig_or_go_home",
    "Mf_Bertrand_Thieves_Honor",
    "!!from_the_grave_main",
    "!!scm_motm",
    "stg_unq_mutants",
    "psgo_brinewight",
    "AAA_Theak_Patron_Gods",
    "!obsidian_lustria_rises",
    "!uber_red_host_additional_units",
    "UD_Deithland_Troops",
    "UD_Deithland_Machines",
    "The Gunpowder Road2.0",
    "shun_cth_unitpack",
    "Kossar_Riflemen_Unit",
    "gra_knightly_orders",
    "gra_holy_orders",
    "froeb_dark_land_orcs",
    "dead_cathay_units",
    "cow_trebuchet_three",
    "Cathay_helblaster",
    "@xou_emp",
    "@xou_cth_stonedogs",
    "!Zayli_Cathay_DE",
    "!TW_Millennium_Public",
    "!!snek_dawi_thunder",
    "!!khuresh_mercs1",
    "!!AM_HelfuryMachinegunsFIXED",
    "!!!!!Zayli_Complete_Mod_Compilation",
    "CF-Chaos_Dragon",
    "singe_units_wh_all",
    "!!!!calm_kislev_erengrad",
    "!!!pwner1_wh3_ete_unit_pack",
}

local faction_mapping = {
    { key = "bst", text = "Beastmen" },
    { key = "brt", text = "Bretonnia" },
    { key = "chd", text = "Chaos Dwarfs" },
    { key = "def", text = "Dark Elves" },
    { key = "dwf", text = "Dwarfs" },
    { key = "emp", text = "Empire" },
    { key = "cth", text = "Grand Cathay" },
    { key = "grn", text = "Greenskins" },
    { key = "hef", text = "High Elves" },
    { key = "kho", text = "Khorne" },
    { key = "ksl", text = "Kislev" },
    { key = "lzd", text = "Lizardmen" },
    { key = "nor", text = "Norsca" },
    { key = "nur", text = "Nurgle" },
    { key = "ogr", text = "Ogre Kingdoms" },
    { key = "skv", text = "Skaven" },
    { key = "sla", text = "Slaanesh" },
    { key = "tmb", text = "Tomb Kings" },
    { key = "tze", text = "Tzeentch" },
    { key = "cst", text = "Vampire Coast" },
    { key = "vmp", text = "Vampire Counts" },
    { key = "chs", text = "Warriors of Chaos" },
    { key = "wef", text = "Wood Elves" },
    -- { key = "teb", text = "Southern Realms (requires mod)" },
    -- { key = "mar", text = "Marienburg (requires mod)" },
    -- { key = "dmd", text = "Dynasty of the Damned (requires mod)" },
    -- { key = "jbv", text = "Jade-Blooded Vampires (requires mod)" },
    -- { key = "nag", text = "Undead Legions (requires mod)" },
    -- { key = "alb", text = "Albion (requires mod)" },
    -- { key = "arb", text = "Araby (requires mod)" },
    -- { key = "dk", text = "Dread King Legions (requires mod)" },
    -- { key = "fim", text = "Fimir (requires mod)" },
}

local encounter_checkbox_ids = {}
local faction_checkbox_ids = {}

function get_mct_settings()
    return mct_settings
end

function get_encounter_data()
    return encounter_data
end

function get_encounter_checkbox_ids()
    return encounter_checkbox_ids
end

function get_faction_checkbox_ids()
    return faction_checkbox_ids
end

function get_supported_mods()
    return supported_mods
end

function get_faction_mapping()
    return faction_mapping
end

function set_mct_settings(mct_mod)
    mct_settings.disable_smithies = mct_mod:get_option_by_key("disable_smithies"):get_finalized_setting()
    mct_settings.spawn_percentage = mct_mod:get_option_by_key("spawn_percentage"):get_finalized_setting()
    mct_settings.enable_all_encounter_skins = mct_mod:get_option_by_key("enable_all_encounter_skins"):get_finalized_setting()
    mct_settings.enable_randomized_encounter_force_generation = mct_mod:get_option_by_key("enable_randomized_encounter_force_generation"):get_finalized_setting()
    mct_settings.use_only_modded_units = mct_mod:get_option_by_key("use_only_modded_units"):get_finalized_setting()
    mct_settings.enable_compatibility_with_supported_mods = mct_mod:get_option_by_key("enable_compatibility_with_supported_mods"):get_finalized_setting()
    mct_settings.randomized_encounter_force_generation_difficulty = mct_mod:get_option_by_key("difficulty_dropdown"):get_finalized_setting()

    mct_settings.enable_basic_progressive_difficulty = mct_mod:get_option_by_key("enable_basic_progressive_difficulty"):get_finalized_setting()
    mct_settings.turn_number_from_easy_to_medium = mct_mod:get_option_by_key("turn_number_from_easy_to_medium_slider"):get_finalized_setting()
    mct_settings.turn_number_from_medium_to_hard = mct_mod:get_option_by_key("turn_number_from_medium_to_hard_slider"):get_finalized_setting()

    mct_settings.enable_all_factions = mct_mod:get_option_by_key("enable_all_faction_checkboxes"):get_finalized_setting()

    out("DEBUG - mct_settings.disable_smithies: " .. tostring(mct_settings.disable_smithies))
    out("DEBUG - mct_settings.spawn_percentage: " .. tostring(mct_settings.spawn_percentage))
    out("DEBUG - mct_settings.enable_all_encounter_skins: " .. tostring(mct_settings.enable_all_encounter_skins))
    out("DEBUG - mct_settings.enable_randomized_encounter_force_generation: " .. tostring(mct_settings.enable_randomized_encounter_force_generation))
    out("DEBUG - mct_settings.use_only_modded_units: " .. tostring(mct_settings.use_only_modded_units))
    out("DEBUG - mct_settings.enable_compatibility_with_supported_mods: " .. tostring(mct_settings.enable_compatibility_with_supported_mods))
    out("DEBUG - mct_settings.randomized_encounter_force_generation_difficulty: " .. tostring(mct_settings.randomized_encounter_force_generation_difficulty))
    out("DEBUG - mct_settings.enable_basic_progressive_difficulty: " .. tostring(mct_settings.enable_basic_progressive_difficulty))
    out("DEBUG - mct_settings.turn_number_from_easy_to_medium: " .. tostring(mct_settings.turn_number_from_easy_to_medium))
    out("DEBUG - mct_settings.turn_number_from_medium_to_hard: " .. tostring(mct_settings.turn_number_from_medium_to_hard))
    out("DEBUG - mct_settings.enable_all_factions: " .. tostring(mct_settings.enable_all_factions))

    local starting_difficulty_keys = {
        "min_tier_easy",
        "max_tier_easy",
        "min_units_easy",
        "max_units_easy",
        "min_limit_hero_easy",
        "max_limit_hero_easy",
        "min_unit_experience_amount_easy",
        "max_unit_experience_amount_easy",
        "min_lord_level_range_easy",
        "max_lord_level_range_easy",
        "min_tier_medium",
        "max_tier_medium",
        "min_units_medium",
        "max_units_medium",
        "min_limit_hero_medium",
        "max_limit_hero_medium",
        "min_unit_experience_amount_medium",
        "max_unit_experience_amount_medium",
        "min_lord_level_range_medium",
        "max_lord_level_range_medium",
        "min_tier_hard",
        "max_tier_hard",
        "min_units_hard",
        "max_units_hard",
        "min_limit_hero_hard",
        "max_limit_hero_hard",
        "min_unit_experience_amount_hard",
        "max_unit_experience_amount_hard",
        "min_lord_level_range_hard",
        "max_lord_level_range_hard",
    }

    -- Add the limit keys for each difficulty to the table.
    for _, difficulty in ipairs({"easy", "medium", "hard"}) do
        for _, key in ipairs(mct_settings.ordered_slider_keys) do
            table.insert(starting_difficulty_keys, "min_limit_" .. key .. "_" .. difficulty)
            table.insert(starting_difficulty_keys, "max_limit_" .. key .. "_" .. difficulty)
        end
    end

    -- Start saving all the slider values into the difficulties table.
    for _, limit_key in ipairs(starting_difficulty_keys) do
        -- Get the difficulty from the key and then get just the key by itself.
        local difficulty = limit_key:match("_(%a+)$")
        local key = limit_key:match("^(.-)_" .. difficulty .. "$")
        -- Get the value from the option.
        local value = mct_mod:get_option_by_key(limit_key):get_finalized_setting()
        if key == "min_tier" then
            mct_settings.difficulties[difficulty].tiers[1] = value
        elseif key == "max_tier" then
            mct_settings.difficulties[difficulty].tiers[2] = value
        elseif key == "min_units" then
            mct_settings.difficulties[difficulty].min_units = value
        elseif key == "max_units" then
            mct_settings.difficulties[difficulty].max_units = value
        elseif key == "min_unit_experience_amount" then
            mct_settings.difficulties[difficulty].unit_experience_amount[1] = value
        elseif key == "max_unit_experience_amount" then
            mct_settings.difficulties[difficulty].unit_experience_amount[2] = value
        elseif key == "min_lord_level_range" then
            mct_settings.difficulties[difficulty].lord_level_range[1] = value
        elseif key == "max_lord_level_range" then
            mct_settings.difficulties[difficulty].lord_level_range[2] = value
        else
            local new_key = key:gsub("^(min_limit_|max_limit_)", "")
            if key:find("^min_limit_") then
                mct_settings.difficulties[difficulty].limits[new_key][1] = value
            elseif key:find("^max_limit_") then
                mct_settings.difficulties[difficulty].limits[new_key][2] = value
            end
        end
    end

    -- Iterate over each encounter checkbox key.
    mct_settings.enabled_encounter_skin_ids = {}
    for _, id in ipairs(encounter_checkbox_ids) do
        local key = "encounter_" .. id
        local option = mct_mod:get_option_by_key(key)
        if option:get_finalized_setting() then
            table.insert(mct_settings.enabled_encounter_skin_ids, id)
        end
    end

    out("DEBUG - mct_settings.enabled_encounter_skin_ids:")
    print_table(mct_settings.enabled_encounter_skin_ids)

    -- Iterate over each faction checkbox key.
    mct_settings.enabled_faction_keys = {}
    for _, id in ipairs(faction_checkbox_ids) do
        local key = "faction_" .. id
        local option = mct_mod:get_option_by_key(key)
        if option:get_finalized_setting() then
            table.insert(mct_settings.enabled_faction_keys, id)
        end
    end

    out("DEBUG - mct_settings.enabled_faction_keys:")
    print_table(mct_settings.enabled_faction_keys)
end
