--- Side-effect module that publishes the MCT-related globals (get/set_mct_settings,
--- get_supported_mods, get_encounter_data, etc.) and holds the in-memory mct_settings table
--- that the rest of the mod reads from at runtime.

--- common.lua publishes AMBUSH_TYPE, INTERCEPTION_TYPE, ALLIED_REINFORCEMENTS_PERMITTED_TYPE.
--- Ensure they are in _G before the table literal below is evaluated.
require("script/land_encounters/utils/common")

local archetypes = require("script/land_encounters/configs/archetypes")

--- Default settings. The MctInitialized listener overwrites these at first_tick with the user's
--- finalized MCT option values via set_mct_settings.
local mct_settings = {
    disable_smithies = false,
    --- Towers are on the map and can be delved.
    enable_towers = true,
    --- Turns a tower stays closed after a delve ends.
    tower_cooldown = 5,
    --- Turns a level 3 Smithy cools after a free pick. Lower forge levels add their `cooldown_offset`.
    smithy_cooldown = 5,
    --- Tell the player when a Smithy or Tower is ready again.
    ready_notices = true,
    spawn_percentage = 0.75,
    --- Percent chance that a battle spot starts a battle instead of giving treasure.
    battle_chance = 70,
    --- Percent chance a battle spot's dilemma also shows pre-battle offers and missions.
    pre_battle_chance = 30,
    --- Percent chance a won battle spot opens the spoils pick.
    spoils_chance = 30,
    --- Default to interception only - matches the pre-MCT-toggle behavior the user established.
    enabled_intervention_types = { INTERCEPTION_TYPE },
    enabled_encounter_skin_ids = {},
    enabled_mods = {},
    enable_all_encounter_skins = true,
    use_only_modded_units = false,
    enable_compatibility_with_supported_mods = false,
    --- "easy", "medium", "hard", or "progressive" to step up by turn number.
    randomized_encounter_force_generation_difficulty = "easy",
    turn_number_from_easy_to_medium = 15,
    turn_number_from_medium_to_hard = 25,
    enable_all_factions = true,
    enabled_faction_keys = {},
    --- faction_overrides = {
    ---     "tmb",
    ---     "cst",
    ---     "def",
    ---     "hef",
    ---     "lzd",
    ---     "skv",
    ---     "chd",
    ---     "kho",
    ---     "ksl",
    ---     "tze",
    ---     "cth",
    ---     "nur",
    ---     "ogr",
    ---     "sla",
    ---     "bst",
    ---     "wef",
    ---     "nor",
    ---     "brt",
    ---     "chs",
    ---     "dwf",
    ---     "emp",
    ---     "grn",
    ---     "vmp",
    --- },
    --- Army archetype keys the generator may roll. Filled with every archetype below the table.
    enabled_archetypes = {},
    max_unit_copies = 3,
    difficulties = {
        easy = {
            budget = {6000, 10000},
            unit_experience_amount = {1, 3},
            lord_level_range = {5, 10},
            limits = {
                hero = {0, 0},
            }
        },
        medium = {
            budget = {13000, 18000},
            unit_experience_amount = {3, 5},
            lord_level_range = {10, 15},
            limits = {
                hero = {0, 1},
            }
        },
        hard = {
            budget = {20000, 30000},
            unit_experience_amount = {5, 7},
            lord_level_range = {15, 20},
            limits = {
                hero = {0, 2},
            }
        }
    },
    ordered_slider_keys = {
        "hero",
    }
}

--- Enable every army archetype by default.
for _, archetype in ipairs(archetypes.list) do
    table.insert(mct_settings.enabled_archetypes, archetype.key)
end

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

--- TODO: This needs to be periodically updated whenever new mods are added/removed.
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
    --- { key = "teb", text = "Southern Realms (requires mod)" },
    --- { key = "mar", text = "Marienburg (requires mod)" },
    --- { key = "dmd", text = "Dynasty of the Damned (requires mod)" },
    --- { key = "jbv", text = "Jade-Blooded Vampires (requires mod)" },
    --- { key = "nag", text = "Undead Legions (requires mod)" },
    --- { key = "alb", text = "Albion (requires mod)" },
    --- { key = "arb", text = "Araby (requires mod)" },
    --- { key = "dk", text = "Dread King Legions (requires mod)" },
    --- { key = "fim", text = "Fimir (requires mod)" },
}

local encounter_checkbox_ids = {}
local faction_checkbox_ids = {}

--- Returns the in-memory MCT settings table read by the rest of the mod at runtime.
--- @returns table The mod-wide mct_settings table.
function get_mct_settings()
    return mct_settings
end

--- Returns the encounter-skin descriptors used by the MCT anchor to build the per-skin checkboxes.
--- @returns table The encounter_data array.
function get_encounter_data()
    return encounter_data
end

--- Returns the (mutable) list of registered encounter checkbox ids. Populated by the MCT anchor as it creates checkboxes.
--- @returns table The encounter_checkbox_ids array.
function get_encounter_checkbox_ids()
    return encounter_checkbox_ids
end

--- Returns the (mutable) list of registered faction checkbox ids. Populated by the MCT anchor as it creates checkboxes.
--- @returns table The faction_checkbox_ids array.
function get_faction_checkbox_ids()
    return faction_checkbox_ids
end

--- Returns the list of pack-names whose units are eligible when "enable compatibility with supported mods" is on.
--- @returns table An array of mod pack-name strings.
function get_supported_mods()
    return supported_mods
end

--- Returns the ordered { key, text } faction list rendered by the MCT anchor's faction-overrides section.
--- @returns table An ordered array of { key string, text string } pairs.
function get_faction_mapping()
    return faction_mapping
end

--- Picks the battle type for an encounter from the user's MCT toggles. A `preferred_type` that is enabled wins, then Interception when it is
--- enabled, then a random enabled type. An empty list (save-load race or MCT bypass) falls back to Interception.
--- @param preferred_type number An optional battle-type tag a battle category asks for.
--- @returns number One of AMBUSH_TYPE, INTERCEPTION_TYPE, or ALLIED_REINFORCEMENTS_PERMITTED_TYPE.
function pick_intervention_type(preferred_type)
    local enabled = mct_settings.enabled_intervention_types or {}
    local function is_enabled(type_tag)
        for _, enabled_tag in ipairs(enabled) do
            if enabled_tag == type_tag then return true end
        end
        return false
    end
    if preferred_type ~= nil then
        if is_enabled(preferred_type) then return preferred_type end
        if is_enabled(INTERCEPTION_TYPE) then return INTERCEPTION_TYPE end
    end
    if #enabled == 0 then
        return INTERCEPTION_TYPE
    end
    return enabled[random_number(#enabled)]
end

--- Pulls the user's finalized MCT option values into the in-memory mct_settings table.
--- @param mct_mod table The MCT mod handle returned by mct:get_mod_by_key.
function set_mct_settings(mct_mod)
    mct_settings.disable_smithies = mct_mod:get_option_by_key("disable_smithies"):get_finalized_setting()
    mct_settings.enable_towers = mct_mod:get_option_by_key("enable_towers"):get_finalized_setting()
    mct_settings.tower_cooldown = mct_mod:get_option_by_key("tower_cooldown"):get_finalized_setting()
    mct_settings.smithy_cooldown = mct_mod:get_option_by_key("smithy_cooldown"):get_finalized_setting()
    mct_settings.ready_notices = mct_mod:get_option_by_key("ready_notices"):get_finalized_setting()
    mct_settings.spawn_percentage = mct_mod:get_option_by_key("spawn_percentage"):get_finalized_setting()
    mct_settings.battle_chance = mct_mod:get_option_by_key("battle_chance"):get_finalized_setting()
    mct_settings.pre_battle_chance = mct_mod:get_option_by_key("pre_battle_chance"):get_finalized_setting()
    mct_settings.spoils_chance = mct_mod:get_option_by_key("spoils_chance"):get_finalized_setting()

    --- Read the three intervention toggles and build the enabled set. The MCT anchor enforces
    --- at-least-one via set_locked, so this list should never be empty, but `pick_intervention_type`
    --- has a defensive fallback to INTERCEPTION_TYPE just in case.
    local enabled_intervention_types = {}
    if mct_mod:get_option_by_key("intervention_ambush"):get_finalized_setting() then
        table.insert(enabled_intervention_types, AMBUSH_TYPE)
    end
    if mct_mod:get_option_by_key("intervention_interception"):get_finalized_setting() then
        table.insert(enabled_intervention_types, INTERCEPTION_TYPE)
    end
    if mct_mod:get_option_by_key("intervention_allied_reinforcements"):get_finalized_setting() then
        table.insert(enabled_intervention_types, ALLIED_REINFORCEMENTS_PERMITTED_TYPE)
    end
    mct_settings.enabled_intervention_types = enabled_intervention_types
    mct_settings.enable_all_encounter_skins = mct_mod:get_option_by_key("enable_all_encounter_skins"):get_finalized_setting()
    mct_settings.use_only_modded_units = mct_mod:get_option_by_key("use_only_modded_units"):get_finalized_setting()
    mct_settings.enable_compatibility_with_supported_mods = mct_mod:get_option_by_key("enable_compatibility_with_supported_mods"):get_finalized_setting()
    mct_settings.randomized_encounter_force_generation_difficulty = mct_mod:get_option_by_key("difficulty_dropdown"):get_finalized_setting()

    mct_settings.turn_number_from_easy_to_medium = mct_mod:get_option_by_key("turn_number_from_easy_to_medium_slider"):get_finalized_setting()
    mct_settings.turn_number_from_medium_to_hard = mct_mod:get_option_by_key("turn_number_from_medium_to_hard_slider"):get_finalized_setting()

    mct_settings.enable_all_factions = mct_mod:get_option_by_key("enable_all_faction_checkboxes"):get_finalized_setting()

    out("DEBUG - mct_settings.disable_smithies: " .. tostring(mct_settings.disable_smithies))
    out("DEBUG - mct_settings.enable_towers: " .. tostring(mct_settings.enable_towers) .. ", tower_cooldown: " .. tostring(mct_settings.tower_cooldown))
    out("DEBUG - mct_settings.smithy_cooldown: " .. tostring(mct_settings.smithy_cooldown) .. ", ready_notices: " .. tostring(mct_settings.ready_notices))
    out("DEBUG - mct_settings.spawn_percentage: " .. tostring(mct_settings.spawn_percentage))
    out("DEBUG - mct_settings.battle_chance: " .. tostring(mct_settings.battle_chance) .. ", pre_battle_chance: " .. tostring(mct_settings.pre_battle_chance)
        .. ", spoils_chance: " .. tostring(mct_settings.spoils_chance))
    out("DEBUG - mct_settings.enable_all_encounter_skins: " .. tostring(mct_settings.enable_all_encounter_skins))
    out("DEBUG - mct_settings.use_only_modded_units: " .. tostring(mct_settings.use_only_modded_units))
    out("DEBUG - mct_settings.enable_compatibility_with_supported_mods: " .. tostring(mct_settings.enable_compatibility_with_supported_mods))
    out("DEBUG - mct_settings.randomized_encounter_force_generation_difficulty: " .. tostring(mct_settings.randomized_encounter_force_generation_difficulty))
    out("DEBUG - mct_settings.turn_number_from_easy_to_medium: " .. tostring(mct_settings.turn_number_from_easy_to_medium))
    out("DEBUG - mct_settings.turn_number_from_medium_to_hard: " .. tostring(mct_settings.turn_number_from_medium_to_hard))
    out("DEBUG - mct_settings.enable_all_factions: " .. tostring(mct_settings.enable_all_factions))

    --- Read each difficulty's min/max sliders into its ranges. Hero count sliders keep their older min_limit_/max_limit_ keys.
    for _, difficulty in ipairs(DIFFICULTY_KEYS) do
        local settings = mct_settings.difficulties[difficulty]
        for _, field in ipairs({"budget", "unit_experience_amount", "lord_level_range"}) do
            settings[field][1] = mct_mod:get_option_by_key("min_" .. field .. "_" .. difficulty):get_finalized_setting()
            settings[field][2] = mct_mod:get_option_by_key("max_" .. field .. "_" .. difficulty):get_finalized_setting()
        end
        for _, limit_key in ipairs(mct_settings.ordered_slider_keys) do
            settings.limits[limit_key][1] = mct_mod:get_option_by_key("min_limit_" .. limit_key .. "_" .. difficulty):get_finalized_setting()
            settings.limits[limit_key][2] = mct_mod:get_option_by_key("max_limit_" .. limit_key .. "_" .. difficulty):get_finalized_setting()
        end
    end

    --- Swap any min/max pair the player set backwards, since a reversed range breaks the random rolls.
    for _, settings in pairs(mct_settings.difficulties) do
        local ranges = { settings.budget, settings.unit_experience_amount, settings.lord_level_range }
        for _, limit in pairs(settings.limits) do
            table.insert(ranges, limit)
        end
        for _, range in ipairs(ranges) do
            if range[1] > range[2] then
                range[1], range[2] = range[2], range[1]
            end
        end
    end

    --- Collect every enabled army archetype. The generator falls back to Battle line if none are enabled.
    mct_settings.enabled_archetypes = {}
    for _, archetype in ipairs(archetypes.list) do
        if mct_mod:get_option_by_key("archetype_" .. archetype.key):get_finalized_setting() then
            table.insert(mct_settings.enabled_archetypes, archetype.key)
        end
    end
    mct_settings.max_unit_copies = mct_mod:get_option_by_key("max_unit_copies"):get_finalized_setting()

    --- Collect every encounter skin id whose checkbox is enabled.
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

    --- Collect every faction key whose checkbox is enabled.
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
