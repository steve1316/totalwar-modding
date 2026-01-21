-- This script is meant to be tested locally with the factions_data.json file in the same directory.

-- Read the JSON file.
require("script/land_encounters/utils/random")
local factions_data = require("script/land_encounters/constants/battles/factions_data")
require("script/shared/mct_settings")
local difficulties = get_mct_settings().difficulties
-- print("Reading factions_data.json...")
-- local factions_data = require("factions_data")
-- local enable_compatibility_with_supported_mods = true
-- SUPPORTED_MODS = {
--     "vanilla"
-- }

-- Determine the randomized unit force makeup per difficulty. The first section is the guaranteed units while the second section is the random units.
-- If a specific land_unit is selected, there is a 50% chance that it will multiple copies up to the allowed amount and only if the total size has not been reached.
-- Ignore the recruitment_cost for now.

---------------------------------------------------------
---------------------------------------------------------
---------------------------------------------------------
-- The following random functions from script/land_encounters/utils/random were provided as is and may or may not work with what this script is going to be doing.

-- math.randomseed(os.time()) -- random initialize
-- math.random(); math.random(); math.random() -- warming up

-- --- @function randomic_length_shuffle
-- --- @desc Given a length creates an array with the elements of that length and and shuffles them
-- --- @return table random a disordered table
-- function randomic_length_shuffle(length_of_an_array)
--     local arr = {}
--     for i=1, length_of_an_array do
--         table.insert(arr, i)
--     end
--     return randomic_shuffle(arr)
-- end


-- -- Fisher-Yates shuffle
-- -- Randomly shuffles an array so that its members are disordered
-- -- https://gist.github.com/Uradamus/10323382
-- -- param tbl: Array
-- function randomic_shuffle(tbl)
--     for i = #tbl, 2, -1 do
--         local j = math.random(i)
--         tbl[i], tbl[j] = tbl[j], tbl[i]
--     end
--     return tbl
-- end

---------------------------------------------------------
---------------------------------------------------------
---------------------------------------------------------

local faction_shorthand_key_to_full_key = {
    tmb = "wh2_dlc09_tmb_tombking_qb1",
    cst = "wh2_dlc11_cst_vampire_coast_qb1",
    def = "wh2_main_def_dark_elves_qb1",
    hef = "wh2_main_hef_high_elves_qb1",
    lzd = "wh2_main_lzd_lizardmen_qb1",
    skv = "wh2_main_skv_skaven_qb1",
    chd = "wh3_dlc23_chd_chaos_dwarfs_qb1",
    kho = "wh3_main_kho_khorne_qb1",
    ksl = "wh3_main_ksl_kislev_qb1",
    tze = "wh3_main_tze_tzeentch_qb1",
    cth = "wh3_main_cth_cathay_qb1",
    nur = "wh3_main_nur_nurgle_qb1",
    ogr = "wh3_main_ogr_ogre_kingdoms_qb1",
    sla = "wh3_main_sla_slaanesh_qb1",
    bst = "wh_dlc03_bst_beastmen_qb1",
    wef = "wh_dlc05_wef_wood_elves_qb1",
    nor = "wh2_dlc11_nor_norsca_qb4",
    brt = "wh_main_brt_bretonnia_qb1",
    chs = "wh_main_chs_chaos_qb1",
    dwf = "wh_main_dwf_dwarfs_qb1",
    emp = "wh_main_emp_empire_qb1",
    grn = "wh_main_grn_greenskins_qb1",
    vmp = "wh_main_vmp_vampire_counts_qb1",
    -- teb = "wh_main_teb_border_princes_rebels",
    -- mar = "wh_main_emp_marienburg_rebels",
    -- dmd = "wh3_dlc21_vmp_jiangshi_rebels",
    -- jbv = "mixer_vmp_the_curse_of_nongchang_rebels", -- This is custom for Land Encounters.
    -- nag = "mixer_nag_nagash_rebels", -- This is custom for Land Encounters.
    -- alb = "ovn_alb_rebel",
    -- arb = "ovn_arb_araby_rebels",
    -- dk = "ovn_tmb_dread_king_rebels", -- This is custom for Land Encounters.
    -- fim = "ovn_fim_fimir_rebel",
}

-- This is locally defined here for testing this file by itself.
-- local difficulties = {
--     easy = {
--         tiers = {1, 2},
--         min_units = 10,
--         max_units = 13,
--         unit_experience_amount = {1, 3},
--         lord_level_range = {5, 10},
--         limits = {
--             hero = {0, 0},
--             melee_infantry = {3, 6},
--             missile_infantry = {0, 3},
--             melee_cavalry = {0, 2},
--             missile_cavalry = {0, 2},
--             monstrous_infantry = {0, 2},
--             monstrous_cavalry = {0, 2},
--             war_beast = {0, 2},
--             chariot = {0, 0},
--             warmachine = {0, 0},
--             monster = {0, 0},
--             generic = {0, 0},
--         }
--     },
--     medium = {
--         tiers = {1, 3},
--         min_units = 14,
--         max_units = 16,
--         unit_experience_amount = {3, 5},
--         lord_level_range = {10, 15},
--         limits = {
--             hero = {0, 1},
--             melee_infantry = {3, 5},
--             missile_infantry = {0, 3},
--             melee_cavalry = {0, 2},
--             missile_cavalry = {0, 2},
--             monstrous_infantry = {0, 2},
--             monstrous_cavalry = {0, 2},
--             war_beast = {0, 2},
--             chariot = {0, 1},
--             warmachine = {0, 1},
--             monster = {0, 1},
--             generic = {0, 1},
--         }
--     },
--     hard = {
--         tiers = {1, 5},
--         min_units = 17,
--         max_units = 20,
--         unit_experience_amount = {5, 7},
--         lord_level_range = {15, 20},
--         limits = {
--             hero = {0, 2},
--             melee_infantry = {4, 6},
--             missile_infantry = {2, 4},
--             melee_cavalry = {0, 2},
--             missile_cavalry = {0, 2},
--             monstrous_infantry = {0, 2},
--             monstrous_cavalry = {0, 2},
--             war_beast = {0, 2},
--             chariot = {0, 1},
--             warmachine = {0, 1},
--             monster = {0, 1},
--             generic = {0, 1},
--         }
--     }
-- }

-- -- This is locally defined here for testing this file by itself.
-- local difficulties = {
--     easy = {
--         tiers = {1, 2},
--         min_units = 10,
--         max_units = 13,
--         unit_experience_amount = {1, 3},
--         lord_level_range = {5, 10},
--         limits = {
--             hero = {0, 0},
--             melee_infantry = {3, 6},
--             missile_infantry = {0, 3},
--             melee_cavalry = {0, 2},
--             missile_cavalry = {0, 2},
--             monstrous_infantry = {0, 2},
--             monstrous_cavalry = {0, 2},
--             war_beast = {0, 2},
--             chariot = {0, 0},
--             warmachine = {0, 0},
--             monster = {0, 0},
--             generic = {0, 0},
--         }
--     },
--     medium = {
--         tiers = {1, 3},
--         min_units = 14,
--         max_units = 16,
--         unit_experience_amount = {3, 5},
--         lord_level_range = {10, 15},
--         limits = {
--             hero = {0, 1},
--             melee_infantry = {3, 5},
--             missile_infantry = {0, 3},
--             melee_cavalry = {0, 2},
--             missile_cavalry = {0, 2},
--             monstrous_infantry = {0, 2},
--             monstrous_cavalry = {0, 2},
--             war_beast = {0, 2},
--             chariot = {0, 1},
--             warmachine = {0, 1},
--             monster = {0, 1},
--             generic = {0, 1},
--         }
--     },
--     hard = {
--         tiers = {1, 5},
--         min_units = 17,
--         max_units = 20,
--         unit_experience_amount = {5, 7},
--         lord_level_range = {15, 20},
--         limits = {
--             hero = {0, 2},
--             melee_infantry = {4, 6},
--             missile_infantry = {2, 4},
--             melee_cavalry = {0, 2},
--             missile_cavalry = {0, 2},
--             monstrous_infantry = {0, 2},
--             monstrous_cavalry = {0, 2},
--             war_beast = {0, 2},
--             chariot = {0, 1},
--             warmachine = {0, 1},
--             monster = {0, 1},
--             generic = {0, 1},
--         }
--     }
-- }

local force_makeup_weights = {
    melee_infantry = 0.40,
    missile_infantry = 0.40,
    melee_cavalry = 0.15,
    missile_cavalry = 0.15,
    monstrous_infantry = 0.40,
    monstrous_cavalry = 0.20,
    war_beast = 0.40,
    chariot = 0.20,
    warmachine = 0.20,
    monster = 0.20,
    generic = 0.10,
}

local unit_type_weight_overrides = {
    ogr = {
        melee_infantry = 0.05,
        missile_infantry = 0.05,
        monstrous_infantry = 0.80,
    },
}

-- Function to print any table.
function print_table(tbl, indent)
    indent = indent or 0
    local indent_str = string.rep("  ", indent)

    if type(tbl) ~= "table" then
        out(indent_str .. tostring(tbl))
        return
    end

    for key, value in pairs(tbl) do
        if type(value) == "table" then
            out(indent_str .. tostring(key) .. ":")
            print_table(value, indent + 1)
        else
            out(indent_str .. tostring(key) .. ": " .. tostring(value))
        end
    end
end

--- Function to check if a unit's origin is enabled.
local function is_origin_enabled(origin)
    -- Check if we should only use modded units. If so, exclude vanilla units.
    if get_mct_settings().enable_compatibility_with_supported_mods and get_mct_settings().use_only_modded_units then
        if origin == "vanilla" then
            return false
        end
    elseif origin == "vanilla" then
        return true
    end

    -- Check if the origin is in the list of supported mods that are currently enabled.
    if get_mct_settings().enable_compatibility_with_supported_mods then
    -- if enable_compatibility_with_supported_mods then
        for _, mod in ipairs(get_mct_settings().enabled_mods) do
        -- for _, mod in ipairs(SUPPORTED_MODS) do
            if origin == mod then
                return true
            end
        end
    end
    return false
end

-- From the available factions, select a random faction.
function get_random_faction()
    local faction_keys = {}

    if get_mct_settings().enable_all_factions then
        out("DEBUG - get_random_faction Enabling all factions.")
        for key, _ in pairs(faction_shorthand_key_to_full_key) do
            table.insert(faction_keys, key)
        end
    else
        out("DEBUG - get_random_faction Enabling selected factions.")
        for _, key in ipairs(get_mct_settings().enabled_faction_keys) do
            table.insert(faction_keys, key)
        end

        -- If no factions are enabled, enable all factions.
        if #faction_keys == 0 then
            out("DEBUG - get_random_faction No factions are enabled, enabling all factions.")
            for key, _ in pairs(faction_shorthand_key_to_full_key) do
                table.insert(faction_keys, key)
            end
        end
    end

    out("DEBUG - get_random_faction Faction keys:")
    print_table(faction_keys)

    local modded_factions = {
        teb = "!ak_teb3",
        mar = "!scm_marienburg",
        dmd = "AAA_dynasty_of_the_damned",
        jbv = "jade_vamp_pol",
        nag = "nag_nagash",
        alb = "ovn_albion",
        arb = "ovn_araby",
        dk = "ovn_dread_king",
        fim = "ovn_fimir",
    }

    -- Filter faction_keys based on enabled mods
    local enabled_mods = get_mct_settings().enabled_mods
    local filtered_faction_keys = {}

    for _, key in ipairs(faction_keys) do
        local mod = modded_factions[key]
        if not mod or contains(enabled_mods, mod, false) then
            table.insert(filtered_faction_keys, key)
        end
    end

    local random_faction = filtered_faction_keys[math.random(1, #filtered_faction_keys)]
    return random_faction
end

-- Count the total number of units in the force makeup.
local function count_total_units(force_makeup)
    -- The lord is counted as well.
    local total = 1
    for _, units in pairs(force_makeup.units) do
        total = total + #units
    end
    -- Count the heroes if there are any.
    if #force_makeup.heroes > 0 then
        total = total + #force_makeup.heroes
    end
    return total
end

-- Function to select a unit type based on weights.
local function select_weighted_random_unit_type(weights, faction_shorthand_key)
    -- Create a copy of the default unit type weights.
    local faction_weights = {}
    for unit_type, weight in pairs(weights) do
        faction_weights[unit_type] = weight
    end

    -- Override with specific faction unit type weights if available.
    if unit_type_weight_overrides[faction_shorthand_key] then
        for unit_type, weight in pairs(unit_type_weight_overrides[faction_shorthand_key]) do
            print("DEBUG - Overriding unit type " .. unit_type .. " with weight " .. weight .. " for faction " .. faction_shorthand_key .. ".")
            faction_weights[unit_type] = weight
        end
    end

    local total_weight = 0
    for _, weight in pairs(faction_weights) do
        total_weight = total_weight + weight
    end

    local random_weight = math.random() * total_weight
    local cumulative_weight = 0

    for unit_type, weight in pairs(faction_weights) do
        cumulative_weight = cumulative_weight + weight
        if random_weight <= cumulative_weight then
            return unit_type
        end
    end
end

-- Check if a table contains an element.
function contains(tbl, element, key_first)
    if tbl == nil then
        return false
    end
    for k, v in pairs(tbl) do
        if key_first and k == element then
            return true
        elseif not key_first and v == element then
            return true
        end
    end
    return false
end

-- Function to count the number of keys.
function Count_keys(tbl)
    local count = 0
    for _ in pairs(tbl) do
        count = count + 1
    end
    return count
end

-- Function to randomly select a key.
local function select_random_key(tbl)
    local keys = {}
    for key in pairs(tbl) do
        table.insert(keys, key)
    end
    local random_index = math.random(1, #keys)
    return keys[random_index]
end

-- Function to select a random value from a table.
local function select_random_value(tbl)
    local values = {}
    for _, value in pairs(tbl) do
        table.insert(values, value)
    end
    local random_index = math.random(1, #values)
    return values[random_index]
end

-- Function to remove a key from a table
local function remove_key(tbl, key_to_remove)
    local new_tbl = {}
    for key, value in pairs(tbl) do
        if key ~= key_to_remove then
            new_tbl[key] = value
        end
    end
    return new_tbl
end

-- Function to get a random unit of the given unit type for the given faction and difficulty.
local function get_random_units(difficulty_key, faction_shorthand_key, force_makeup, unit_type, empty_unit_types)
    local tiers = difficulties[difficulty_key].tiers
    local unit_limits = difficulties[difficulty_key].limits
    local add_single_copy = false

    print("INFO - Processing original unit_type: " .. unit_type .. " units.")

    -- Function to collect units from the given tiers.
    local function collect_units_from_tiers(tiers, faction_shorthand_key, unit_type)
        local enabled_faction_units = {}
        local min_tier = tiers[1]
        local max_tier = tiers[2]

        print("DEBUG - Collecting units from tiers " .. min_tier .. " to " .. max_tier .. " for unit type " .. unit_type .. ".")
        print("DEBUG - Faction " .. faction_shorthand_key .. ".")

        -- If the list is empty after collection, decrease the tiers by 1 and try again until the minimum tier hits 1 and/or the maximum tier hits 5.
        local iteration_limit = 5
        while iteration_limit > 0 and #enabled_faction_units == 0 do
            for tier = min_tier, max_tier do
                local tier_name = "tier_" .. tier
                -- print("DEBUG - Collecting units from tier " .. tier_name .. ".")
                local units = factions_data[faction_shorthand_key].units[tier_name][unit_type]
                if #units ~= 0 then
                    for _, unit in pairs(units) do
                        if is_origin_enabled(unit.origin) and not contains(enabled_faction_units, unit.land_unit) then
                            table.insert(enabled_faction_units, unit.land_unit)
                        end
                    end
                end
            end

            -- Tiers should not go more than 1 above or below the given tiers.
            -- Similarly, tier 2 should stay at tier 2 for the max constraint, otherwise you will cross over to some tough units for tier 3 if easy difficulty was selected.
            min_tier = math.max(min_tier - 1, tiers[1] - 1 >= 1 and tiers[1] - 1 or 1)
            max_tier = math.min(max_tier + 1, tiers[2] == 2 and 2 or tiers[2] + 1 <= 5 and tiers[2] + 1 or 5)
            iteration_limit = iteration_limit - 1
        end
        print("DEBUG - Returning " .. #enabled_faction_units .. " units.")
        return enabled_faction_units, empty_unit_types
    end

    -- Collect all units of enabled origins for the given unit type and for the chosen tiers.
    local enabled_faction_units = collect_units_from_tiers(tiers, faction_shorthand_key, unit_type)
    if #enabled_faction_units == 0 then
        -- If no units are found, fallback and bypass the unit type limit.
        -- In addition, set the copies to 1 for this fallback to allow for other potential unit types to be filled.
        unit_type = select_weighted_random_unit_type(force_makeup_weights, faction_shorthand_key)
        print("WARNING - No units found for the given tiers and unit type. Falling back to " .. unit_type .. " by random selection and setting the copies added to 1.")
        enabled_faction_units = collect_units_from_tiers(tiers, faction_shorthand_key, unit_type)
        add_single_copy = true
    end

    if #enabled_faction_units == 0 then
        print("WARNING - No " .. unit_type .. " units found for the given tiers and unit type. Skipping.")
        table.insert(empty_unit_types, unit_type)
        return force_makeup, empty_unit_types
    end

    print("Collected a list of " .. #enabled_faction_units .. " " .. unit_type .. " units.")

    -- Loop until either the minimum or maximum number of units for the unit type is reached.
    if unit_type == "warmachine" or unit_type == "monster" then
        -- Add only up to 1 of either warmachine or monster unit type.
        -- Randomize the list of enabled units first before selection.
        local randomized_enabled_faction_units = randomic_shuffle(enabled_faction_units)

        -- Select the first unit in the randomized list.
        local selected_land_unit = randomized_enabled_faction_units[1]

        -- If the selected unit is a Regiment of Renown unit, add it to the force makeup only if it is not already in the force makeup.
        if selected_land_unit:find("_ror") then
            if not contains(force_makeup.units[unit_type], selected_land_unit) then
                table.insert(force_makeup.units[unit_type], selected_land_unit)
            end
        else
            table.insert(force_makeup.units[unit_type], selected_land_unit)
        end
    else
        -- For every other unit type, begin adding units to the force makeup.
        -- First, determine if copies should be added and cap it at 3.
        local copies = 1
        if not add_single_copy and math.random() < 0.25 then
            copies = math.min(math.random(unit_limits[unit_type][1], unit_limits[unit_type][2]), 3)
        end

        -- Randomize the list of enabled units first before selection.
        local randomized_enabled_faction_units = randomic_shuffle(enabled_faction_units)

        -- Now randomly select the unit to be added.
        local selected_land_unit = randomized_enabled_faction_units[1]

        -- If the selected unit is a Regiment of Renown unit, add it to the force makeup only if it is not already in the force makeup.
        if selected_land_unit:find("_ror") then
            if not contains(force_makeup.units[unit_type], selected_land_unit) then
                table.insert(force_makeup.units[unit_type], selected_land_unit)
            end
        else
            print("INFO - Selected a " .. unit_type .. " unit: " .. selected_land_unit .. " up to " .. copies .. " copies.")
            -- Add the selected unit to the force makeup up.
            for _ = 1, copies do
                table.insert(force_makeup.units[unit_type], selected_land_unit)
            end
        end
    end

    return force_makeup, empty_unit_types
end

-- Generate a random force makeup for the given faction and difficulty.
local function generate_random_force_makeup(difficulty_key, faction_shorthand_key)
    local max_units = math.random(difficulties[difficulty_key].min_units, difficulties[difficulty_key].max_units)
    local list_of_allowed_lord_objects = factions_data[faction_shorthand_key].allowed_lords or {}
    local list_of_allowed_hero_objects = factions_data[faction_shorthand_key].allowed_heroes or {}
    local force_makeup = {}
    local empty_unit_types = {}

    -- Create the initial structure of the force makeup.
    force_makeup.units = {
        melee_infantry = {},
        missile_infantry = {},
        melee_cavalry = {},
        missile_cavalry = {},
        monstrous_infantry = {},
        monstrous_cavalry = {},
        war_beast = {},
        chariot = {},
        warmachine = {},
        monster = {},
        generic = {},
    }
    force_makeup.lord = nil
    force_makeup.heroes = {}

    -- Select a random allowed lord if their origin is enabled. Save the skill overrides for the lord.
    for _, lord in pairs(randomic_shuffle(list_of_allowed_lord_objects)) do
        if is_origin_enabled(lord.origin) then
            force_makeup.lord = lord
            break
        end
    end

    -- If a lord was not able to be selected, then select a random vanilla lord instead.
    if not force_makeup.lord then
        out("DEBUG - A lord was not able to be selected. Selecting a random vanilla lord instead.")
        force_makeup.lord = select_random_value(list_of_allowed_lord_objects)
    end

    -- Select a random amount of heroes if their origin is enabled. Save the skill overrides for the heroes.
    local randomly_selected_heroes = {}
    local number_of_heroes_to_select = math.random(difficulties[difficulty_key].limits.hero[1], difficulties[difficulty_key].limits.hero[2])
    for _, hero in pairs(randomic_shuffle(list_of_allowed_hero_objects)) do
        if #randomly_selected_heroes >= number_of_heroes_to_select then
            break
        end
        if is_origin_enabled(hero.origin) then
            table.insert(randomly_selected_heroes, hero)
        end
    end
    force_makeup.heroes = randomly_selected_heroes

    -- Get the override limit for melee_infantry and missile_infantry.
    local override_limit_melee_infantry = math.random(difficulties[difficulty_key].limits.melee_infantry[1], difficulties[difficulty_key].limits.melee_infantry[2])
    local override_limit_missile_infantry = math.random(difficulties[difficulty_key].limits.missile_infantry[1], difficulties[difficulty_key].limits.missile_infantry[2])

    -- First, randomly select the melee_infantry and missile_infantry units up to the minimum limits.
    -- Also check if the unit type has available units to select from. If not, then fallback to the other.
    local initial_count = 0
    while (#force_makeup.units.melee_infantry < override_limit_melee_infantry) do
        initial_count = #force_makeup.units.melee_infantry
        force_makeup, empty_unit_types = get_random_units(difficulty_key, faction_shorthand_key, force_makeup, "melee_infantry", empty_unit_types)
        if #force_makeup.units.melee_infantry == initial_count then
            break
        end
    end
    while (#force_makeup.units.missile_infantry < override_limit_missile_infantry) do
        initial_count = #force_makeup.units.missile_infantry
        force_makeup, empty_unit_types = get_random_units(difficulty_key, faction_shorthand_key, force_makeup, "missile_infantry", empty_unit_types)
        -- Some factions like vanilla Nurgle have no missile_infantry units at the lower tiers.
        if #force_makeup.units.missile_infantry == initial_count then
            print("WARNING - No available units for missile_infantry. Falling back to melee_infantry.")
            force_makeup, empty_unit_types = get_random_units(difficulty_key, faction_shorthand_key, force_makeup, "melee_infantry", empty_unit_types)
            break
        end
    end

    -- Loop until either the minimum or maximum number of units is reached.
    while count_total_units(force_makeup) < max_units do
        -- Randomly select a unit type to add from the weights.
        local unit_type = select_weighted_random_unit_type(force_makeup_weights, faction_shorthand_key)
        force_makeup, empty_unit_types = get_random_units(difficulty_key, faction_shorthand_key, force_makeup, unit_type, empty_unit_types)
    end

    return force_makeup
end

-- Start the force makeup generation process.
function start_force_makeup_generation(difficulty_key, faction_shorthand_key)
    -- For the chosen difficulty, construct a random force makeup for the chosen faction based on the enabled origins.
    local force_makeup = {}
    if difficulty_key == "easy" then
        print("Easy difficulty for random force makeup selected.")
        force_makeup = generate_random_force_makeup(difficulty_key, faction_shorthand_key)
    elseif difficulty_key == "medium" then
        print("Medium difficulty for random force makeup selected.")
        force_makeup = generate_random_force_makeup(difficulty_key, faction_shorthand_key)
    else
        print("Hard difficulty for random force makeup selected.")
        force_makeup = generate_random_force_makeup(difficulty_key, faction_shorthand_key)
    end

    return force_makeup
end

-- Convert the force makeup to the usable format for the mod.
function convert_force_makeup_to_usable_format(difficulty, force_makeup, faction_key, identifier, invasion_identifier, intervention_type)
    local converted_force = {
        faction = faction_shorthand_key_to_full_key[faction_key],
        identifier = identifier,
        invasion_identifier = invasion_identifier,
        intervention_type = intervention_type,
        lord = {
            possible_subtypes = { force_makeup.lord.agent_subtype },
            level_ranges = {difficulties[difficulty].lord_level_range[1], difficulties[difficulty].lord_level_range[2]},
            possible_forenames = {},
            possible_clan_names = {},
            possible_family_names = {},
            ancillaries = {},
            traits = {},
        },
        heroes = {},
        unit_experience_amount = math.random(difficulties[difficulty].unit_experience_amount[1], difficulties[difficulty].unit_experience_amount[2]),
        units = {},
        reinforcing_ally_armies = false,
        reinforcing_enemy_armies = false,
        skill_overrides = {},
    }

    -- Save the skill overrides for the lord if available.
    if contains(force_makeup.lord, "skill_overrides", true) and #force_makeup.lord.skill_overrides > 0 then
        converted_force.skill_overrides[force_makeup.lord.agent_subtype] = {}
        for _, skill in ipairs(force_makeup.lord.skill_overrides) do
            table.insert(converted_force.skill_overrides[force_makeup.lord.agent_subtype], skill)
        end
    end

    -- Add the heroes if there are any and the skill overrides for them.
    if #force_makeup.heroes > 0 then
        for _, hero in ipairs(force_makeup.heroes) do
            table.insert(converted_force.heroes, {
                -- Create a copy of the hero without skill_overrides.
                land_unit = hero.land_unit,
                agent_subtype = hero.agent_subtype,
                agent_type = hero.agent_type,
                origin = hero.origin
            })

            if contains(hero, "skill_overrides", true) and #hero.skill_overrides > 0 then
                converted_force.skill_overrides[hero.agent_subtype] = {}
                for _, skill in ipairs(hero.skill_overrides) do
                    table.insert(converted_force.skill_overrides[hero.agent_subtype], skill)
                end
            end
        end
    end

    -- Insert the units into the table in the specified format.
    for unit_type, units in pairs(force_makeup.units) do
        for _, unit in ipairs(units) do
            table.insert(converted_force.units, {unit, 1, 100, 0, nil})
        end
    end

    return converted_force
end

---------------------------------------------------------
---------------------------------------------------------
---------------------------------------------------------
-- Used for debugging the script locally.

-- -- local random_faction = get_random_faction()
-- local random_faction = "ogr"
-- print("INFO - Selected faction: " .. random_faction)

-- local force_makeup = start_force_makeup_generation("hard", random_faction)

-- print_table(force_makeup)
-- print("INFO - Total units: " .. count_total_units(force_makeup))

-- local converted_force_makeup = convert_force_makeup_to_usable_format("hard", force_makeup, random_faction)
-- print_table(converted_force_makeup)

-- -- Loop until 10 force makeups have been generated.
-- local force_makeup_count = 0
-- while force_makeup_count < 10 do
--     -- local easy_force_makeup = start_force_makeup_generation("easy", random_faction)
--     -- local medium_force_makeup = start_force_makeup_generation("medium", random_faction)
--     local hard_force_makeup = start_force_makeup_generation("hard", random_faction)
--     print_table(hard_force_makeup)
--     -- local converted_force_makeup = convert_force_makeup_to_usable_format("hard", hard_force_makeup, random_faction)
--     -- print("This is the final force makeup:")
--     -- print_table(converted_force_makeup)
--     print("--------------------------------")
--     force_makeup_count = force_makeup_count + 1
-- end
