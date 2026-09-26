--- Central manager module. Bundles: spillover_balancer_algorithm,
--- random_encounter_force_generation_system, EventStack, IncidentManager (free-function globals),
--- InvasionBattleManager (spawn + invasion lifecycle), BattleGenerator, SpotEventManager,
--- and PointOfInterestEventManager.

require("script/land_encounters/utils/common")
require("script/land_encounters/utils/random")
require("script/land_encounters/core/mct")

local factions_data = require("script/land_encounters/configs/factions_data")
local battle_events_by_level = require("script/land_encounters/configs/events").battle_spot

--- Feature delegates are lazy-loaded inside the manager constructors below to avoid a circular
--- require (the delegates pull core/managers back in for the incident globals).
local BattleEventDelegate
local TreasureEventDelegate
local SmithyEventDelegate

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- spillover_balancer_algorithm
--- (from algorithms/spillover_balancer_algorithm.lua)

local CHANCES_INDEX = 1

local STABILIZING_TURN = 120

--- Builds the per-level chance buckets for a turn. Early turns concentrate chance on the lowest level
--- and progressively spill probability into higher levels until the STABILIZING_TURN equalizes them.
--- @param number_of_levels number How many event-difficulty levels exist.
--- @param turn_number number Current campaign turn (1-based).
--- @returns table An array of per-level chance values (length number_of_levels).
local function calculate_filled_buckets_given_turn_number(number_of_levels, turn_number)
    local buckets = {}
    local total_chances_to_distribute = 100
    local equal_chance_of_event_happening = 100/number_of_levels
    local spillover_delta = (100 - equal_chance_of_event_happening) / STABILIZING_TURN

    --- Sample distribution over the first several turns (5 levels, spillover_delta=4):
    ---  turn 1: [100][0][0][0][0]
    ---  turn 2: [96][4][0][0][0]
    ---  turn 3: [92][8][0][0][0]
    ---  turn 7: [76][20][4][0][0]
    local guiding_bucket_chances = total_chances_to_distribute - (turn_number - 1) * spillover_delta
    guiding_bucket_chances = math.max(equal_chance_of_event_happening, guiding_bucket_chances)
    buckets[1] = guiding_bucket_chances
    total_chances_to_distribute = total_chances_to_distribute - guiding_bucket_chances

    for bucket_index = 2, number_of_levels do
        local spilled_chances = math.min(equal_chance_of_event_happening, total_chances_to_distribute)
        buckets[bucket_index] = spilled_chances
        total_chances_to_distribute = total_chances_to_distribute - spilled_chances
    end

    return buckets
end

--- Comparator for table.sort that orders chance pairs by descending chance.
--- @param a table A {chance, level} pair.
--- @param b table A {chance, level} pair.
--- @returns boolean True when a's chance is greater than b's chance.
local function compare_chances_of_event_happening(a,b)
    return a[CHANCES_INDEX] > b[CHANCES_INDEX]
end


--- Uses a spillover algorithm to slowly enable more complex events as turns pass. Returns a list
--- of {chance, level} pairs sorted in descending chance.
--- @param number_of_levels number How many event-difficulty levels exist.
--- @param turn_number number Current campaign turn (1-based).
--- @returns table An array of {chance number, level number} pairs sorted by descending chance.
function randomize_chances_of_event_happening_considering_spillover_given_turn(number_of_levels, turn_number)
    local chance_of_event_of_level_happening = calculate_filled_buckets_given_turn_number(number_of_levels, turn_number)
    for i = 1, number_of_levels do
        local random_multiplier = cm:random_number()
        chance_of_event_of_level_happening[i] = { chance_of_event_of_level_happening[i] * random_multiplier, i }
    end
    table.sort(chance_of_event_of_level_happening, compare_chances_of_event_happening)
    return chance_of_event_of_level_happening
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- random_encounter_force_generation_system
--- (from algorithms/random_encounter_force_generation_system.lua)

--- Pulls the MCT-configured difficulty definitions into a local for hot-path access.
local difficulties = get_mct_settings().difficulties

--- Maps the 3-letter faction shorthand used internally to the qb1 quick-battle faction key the engine expects.
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
    --- teb = "wh_main_teb_border_princes_rebels",
    --- mar = "wh_main_emp_marienburg_rebels",
    --- dmd = "wh3_dlc21_vmp_jiangshi_rebels",
    --- jbv = "mixer_vmp_the_curse_of_nongchang_rebels", -- This is custom for Land Encounters.
    --- nag = "mixer_nag_nagash_rebels", -- This is custom for Land Encounters.
    --- alb = "ovn_alb_rebel",
    --- arb = "ovn_arb_araby_rebels",
    --- dk = "ovn_tmb_dread_king_rebels", -- This is custom for Land Encounters.
    --- fim = "ovn_fim_fimir_rebel",
}

--- Default per-unit-type weights used when picking which unit category to roll for next.
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

--- Per-faction overrides for the default unit-type weights above.
local unit_type_weight_overrides = {
    ogr = {
        melee_infantry = 0.05,
        missile_infantry = 0.05,
        monstrous_infantry = 0.80,
    },
}

--- Recursively prints any Lua value to `out()` for debugging.
--- @param tbl any The value to print. Non-tables are stringified directly.
--- @param indent number Current indent depth. Defaults to 0 when nil.
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

--- Returns true if a unit's origin pack is enabled under the user's MCT mod-compatibility settings.
--- @param origin string The origin tag on a unit ("vanilla" or a mod pack key).
--- @returns boolean True when the origin is allowed by the current MCT settings.
local function is_origin_enabled(origin)
    --- If "only modded units" is on, vanilla is excluded; otherwise vanilla is always enabled.
    if get_mct_settings().enable_compatibility_with_supported_mods and get_mct_settings().use_only_modded_units then
        if origin == "vanilla" then
            return false
        end
    elseif origin == "vanilla" then
        return true
    end

    --- Origin must appear in the enabled-mods list.
    if get_mct_settings().enable_compatibility_with_supported_mods then
        for _, mod in ipairs(get_mct_settings().enabled_mods) do
            if origin == mod then
                return true
            end
        end
    end
    return false
end

--- Picks a random faction shorthand from the MCT-enabled set (falling back to all factions if the set is empty).
--- @returns string A 3-letter faction shorthand key (e.g. "emp", "grn").
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

        if #faction_keys == 0 then
            out("DEBUG - get_random_faction No factions are enabled, enabling all factions.")
            for key, _ in pairs(faction_shorthand_key_to_full_key) do
                table.insert(faction_keys, key)
            end
        end
    end

    out("DEBUG - get_random_faction Faction keys:")
    print_table(faction_keys)

    --- Modded factions are only eligible if their parent mod is in the enabled-mods list.
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

    --- Drop modded factions whose parent mod is not loaded.
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

--- Counts the total number of units in a force_makeup (lord + heroes + every unit-type bucket).
--- @param force_makeup table A force_makeup with a units table (unit_type -> array) and a heroes array.
--- @returns number Total entries including the lord (1), every unit bucket, and every hero.
local function count_total_units(force_makeup)
    local total = 1
    for _, units in pairs(force_makeup.units) do
        total = total + #units
    end
    if #force_makeup.heroes > 0 then
        total = total + #force_makeup.heroes
    end
    return total
end

--- Picks a unit type randomly weighted by the per-type weights, with optional per-faction overrides.
--- @param weights table A unit_type -> weight map (the defaults from force_makeup_weights).
--- @param faction_shorthand_key string A 3-letter faction shorthand used to look up overrides.
--- @returns string The chosen unit-type key (e.g. "melee_infantry", "warmachine").
local function select_weighted_random_unit_type(weights, faction_shorthand_key)
    local faction_weights = {}
    for unit_type, weight in pairs(weights) do
        faction_weights[unit_type] = weight
    end

    --- Override with specific faction unit type weights if available.
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

--- Returns true if `tbl` contains `element`. If `key_first` is true, checks keys; otherwise checks values.
--- @param tbl table The table to search. nil is treated as empty.
--- @param element any The value or key to search for.
--- @param key_first boolean When true, matches against keys instead of values.
--- @returns boolean True when the element is found.
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

--- Picks a uniformly random key from the table.
--- @param tbl table The table to draw from.
--- @returns any A randomly chosen key from tbl.
local function select_random_key(tbl)
    local keys = {}
    for key in pairs(tbl) do
        table.insert(keys, key)
    end
    local random_index = math.random(1, #keys)
    return keys[random_index]
end

--- Picks a uniformly random value from the table.
--- @param tbl table The table to draw from.
--- @returns any A randomly chosen value from tbl.
local function select_random_value(tbl)
    local values = {}
    for _, value in pairs(tbl) do
        table.insert(values, value)
    end
    local random_index = math.random(1, #values)
    return values[random_index]
end

--- Returns a shallow copy of `tbl` with `key_to_remove` omitted.
--- @param tbl table The source table.
--- @param key_to_remove any The key to drop from the copy.
--- @returns table A new table containing every pair from tbl except the one keyed by key_to_remove.
local function remove_key(tbl, key_to_remove)
    local new_tbl = {}
    for key, value in pairs(tbl) do
        if key ~= key_to_remove then
            new_tbl[key] = value
        end
    end
    return new_tbl
end

--- Adds one or more units of the given `unit_type` to `force_makeup` for the given faction and difficulty.
--- Walks the configured tier range and falls back to other unit types when no eligible units exist.
--- @param difficulty_key string The difficulty key (e.g. "easy", "medium", "hard").
--- @param faction_shorthand_key string A 3-letter faction shorthand.
--- @param force_makeup table The accumulating force_makeup table to mutate.
--- @param unit_type string The unit-type bucket key to fill (e.g. "melee_infantry").
--- @param empty_unit_types table Set of unit types already exhausted, mutated when this one is exhausted too.
--- @param max_units number The army's size cap (lord and heroes included). Never adds more units than the room left under it.
local function get_random_units(difficulty_key, faction_shorthand_key, force_makeup, unit_type, empty_unit_types, max_units)
    local tiers = difficulties[difficulty_key].tiers
    local unit_limits = difficulties[difficulty_key].limits
    local add_single_copy = false

    --- Stop once the army is full, so a batch of copies can never push it past its size cap.
    local room_left = max_units - count_total_units(force_makeup)
    if room_left <= 0 then
        return force_makeup, empty_unit_types
    end

    print("INFO - Processing original unit_type: " .. unit_type .. " units.")

    --- Function to collect units from the given tiers.
    local function collect_units_from_tiers(tiers, faction_shorthand_key, unit_type)
        local enabled_faction_units = {}
        local min_tier = tiers[1]
        local max_tier = tiers[2]

        print("DEBUG - Collecting units from tiers " .. min_tier .. " to " .. max_tier .. " for unit type " .. unit_type .. ".")
        print("DEBUG - Faction " .. faction_shorthand_key .. ".")

        --- If the list is empty after collection, decrease the tiers by 1 and try again until the minimum tier hits 1 and/or the maximum tier hits 5.
        local iteration_limit = 5
        while iteration_limit > 0 and #enabled_faction_units == 0 do
            for tier = min_tier, max_tier do
                local tier_name = "tier_" .. tier
                --- print("DEBUG - Collecting units from tier " .. tier_name .. ".")
                local units = factions_data[faction_shorthand_key].units[tier_name][unit_type]
                if #units ~= 0 then
                    for _, unit in pairs(units) do
                        if is_origin_enabled(unit.origin) and not contains(enabled_faction_units, unit.land_unit) then
                            table.insert(enabled_faction_units, unit.land_unit)
                        end
                    end
                end
            end

            --- Tiers should not go more than 1 above or below the given tiers.
            --- Similarly, tier 2 should stay at tier 2 for the max constraint, otherwise you will cross over to some tough units for tier 3 if easy difficulty was selected.
            min_tier = math.max(min_tier - 1, tiers[1] - 1 >= 1 and tiers[1] - 1 or 1)
            max_tier = math.min(max_tier + 1, tiers[2] == 2 and 2 or tiers[2] + 1 <= 5 and tiers[2] + 1 or 5)
            iteration_limit = iteration_limit - 1
        end
        print("DEBUG - Returning " .. #enabled_faction_units .. " units.")
        return enabled_faction_units, empty_unit_types
    end

    --- Collect all units of enabled origins for the given unit type and for the chosen tiers.
    local enabled_faction_units = collect_units_from_tiers(tiers, faction_shorthand_key, unit_type)
    if #enabled_faction_units == 0 then
        --- If no units are found, fallback and bypass the unit type limit.
        --- In addition, set the copies to 1 for this fallback to allow for other potential unit types to be filled.
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

    --- Loop until either the minimum or maximum number of units for the unit type is reached.
    if unit_type == "warmachine" or unit_type == "monster" then
        --- Add only up to 1 of either warmachine or monster unit type.
        --- Randomize the list of enabled units first before selection.
        local randomized_enabled_faction_units = randomic_shuffle(enabled_faction_units)

        --- Select the first unit in the randomized list.
        local selected_land_unit = randomized_enabled_faction_units[1]

        --- If the selected unit is a Regiment of Renown unit, add it to the force makeup only if it is not already in the force makeup.
        if selected_land_unit:find("_ror") then
            if not contains(force_makeup.units[unit_type], selected_land_unit) then
                table.insert(force_makeup.units[unit_type], selected_land_unit)
            end
        else
            table.insert(force_makeup.units[unit_type], selected_land_unit)
        end
    else
        --- For every other unit type, begin adding units to the force makeup.
        --- First, determine if copies should be added and cap it at 3.
        local copies = 1
        if not add_single_copy and math.random() < 0.25 then
            copies = math.min(math.random(unit_limits[unit_type][1], unit_limits[unit_type][2]), 3, room_left)
        end

        --- Randomize the list of enabled units first before selection.
        local randomized_enabled_faction_units = randomic_shuffle(enabled_faction_units)

        --- Now randomly select the unit to be added.
        local selected_land_unit = randomized_enabled_faction_units[1]

        --- If the selected unit is a Regiment of Renown unit, add it to the force makeup only if it is not already in the force makeup.
        if selected_land_unit:find("_ror") then
            if not contains(force_makeup.units[unit_type], selected_land_unit) then
                table.insert(force_makeup.units[unit_type], selected_land_unit)
            end
        else
            print("INFO - Selected a " .. unit_type .. " unit: " .. selected_land_unit .. " up to " .. copies .. " copies.")
            --- Add the selected unit to the force makeup up.
            for _ = 1, copies do
                table.insert(force_makeup.units[unit_type], selected_land_unit)
            end
        end
    end

    return force_makeup, empty_unit_types
end

--- Generates a random force makeup (lord + heroes + units) for the given faction and difficulty.
--- @param difficulty_key string The difficulty key (e.g. "easy", "medium", "hard").
--- @param faction_shorthand_key string A 3-letter faction shorthand.
--- @returns table A force_makeup with lord, heroes, and per-type units arrays populated.
local function generate_random_force_makeup(difficulty_key, faction_shorthand_key)
    local max_units = math.random(difficulties[difficulty_key].min_units, difficulties[difficulty_key].max_units)
    local list_of_allowed_lord_objects = factions_data[faction_shorthand_key].allowed_lords or {}
    local list_of_allowed_hero_objects = factions_data[faction_shorthand_key].allowed_heroes or {}
    local force_makeup = {}
    local empty_unit_types = {}

    --- Create the initial structure of the force makeup.
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

    --- Select a random allowed lord if their origin is enabled. Save the skill overrides for the lord.
    for _, lord in pairs(randomic_shuffle(list_of_allowed_lord_objects)) do
        if is_origin_enabled(lord.origin) then
            force_makeup.lord = lord
            break
        end
    end

    --- If a lord was not able to be selected, then select a random vanilla lord instead.
    if not force_makeup.lord then
        out("DEBUG - A lord was not able to be selected. Selecting a random vanilla lord instead.")
        force_makeup.lord = select_random_value(list_of_allowed_lord_objects)
    end

    --- Select a random amount of heroes if their origin is enabled. Save the skill overrides for the heroes.
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

    --- Get the override limit for melee_infantry and missile_infantry.
    local override_limit_melee_infantry = math.random(difficulties[difficulty_key].limits.melee_infantry[1], difficulties[difficulty_key].limits.melee_infantry[2])
    local override_limit_missile_infantry = math.random(difficulties[difficulty_key].limits.missile_infantry[1], difficulties[difficulty_key].limits.missile_infantry[2])

    --- First, randomly select the melee_infantry and missile_infantry units up to the minimum limits.
    --- Also check if the unit type has available units to select from. If not, then fallback to the other.
    local initial_count = 0
    while (#force_makeup.units.melee_infantry < override_limit_melee_infantry) do
        initial_count = #force_makeup.units.melee_infantry
        force_makeup, empty_unit_types = get_random_units(difficulty_key, faction_shorthand_key, force_makeup, "melee_infantry", empty_unit_types, max_units)
        if #force_makeup.units.melee_infantry == initial_count then
            break
        end
    end
    while (#force_makeup.units.missile_infantry < override_limit_missile_infantry) do
        initial_count = #force_makeup.units.missile_infantry
        force_makeup, empty_unit_types = get_random_units(difficulty_key, faction_shorthand_key, force_makeup, "missile_infantry", empty_unit_types, max_units)
        --- Some factions like vanilla Nurgle have no missile_infantry units at the lower tiers.
        if #force_makeup.units.missile_infantry == initial_count then
            print("WARNING - No available units for missile_infantry. Falling back to melee_infantry.")
            force_makeup, empty_unit_types = get_random_units(difficulty_key, faction_shorthand_key, force_makeup, "melee_infantry", empty_unit_types, max_units)
            break
        end
    end

    --- Loop until either the minimum or maximum number of units is reached.
    while count_total_units(force_makeup) < max_units do
        --- Randomly select a unit type to add from the weights.
        local unit_type = select_weighted_random_unit_type(force_makeup_weights, faction_shorthand_key)
        force_makeup, empty_unit_types = get_random_units(difficulty_key, faction_shorthand_key, force_makeup, unit_type, empty_unit_types, max_units)
    end

    return force_makeup
end

--- Entry point for the force-makeup pipeline. Picks the difficulty branch and returns the generated force makeup.
--- Returns the current encounter difficulty as one of "easy", "medium", or "hard". Uses the MCT
--- dropdown unless progressive scaling is enabled, in which case difficulty ramps up by turn.
--- @returns string The current difficulty key.
function get_current_difficulty()
    local mct = get_mct_settings()
    if not mct.enable_basic_progressive_difficulty then
        return mct.randomized_encounter_force_generation_difficulty
    end
    if cm:turn_number() < mct.turn_number_from_easy_to_medium then
        return "easy"
    elseif cm:turn_number() < mct.turn_number_from_medium_to_hard then
        return "medium"
    else
        return "hard"
    end
end


--- @param difficulty_key string The difficulty key ("easy", "medium", or "hard").
--- @param faction_shorthand_key string A 3-letter faction shorthand.
--- @returns table A force_makeup with lord, heroes, and per-type units arrays populated.
function start_force_makeup_generation(difficulty_key, faction_shorthand_key)
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

--- Converts the raw force makeup into the flat record the InvasionBattleManager + Army constructors expect.
--- @param difficulty string The difficulty key (used to read level + experience ranges).
--- @param force_makeup table The output of generate_random_force_makeup.
--- @param faction_key string A 3-letter faction shorthand.
--- @param identifier string A unique force identifier (e.g. "encounter_force").
--- @param invasion_identifier string A unique invasion identifier (e.g. "encounter_invasion").
--- @param intervention_type number One of AMBUSH_TYPE, INTERCEPTION_TYPE, ALLIED_REINFORCEMENTS_PERMITTED_TYPE.
--- @returns table A flat converted_force record ready for Army:create_from.
function convert_force_makeup_to_usable_format(difficulty, force_makeup, faction_key, identifier, invasion_identifier, intervention_type)
    local converted_force = {
        faction = faction_shorthand_key_to_full_key[faction_key],
        identifier = identifier,
        invasion_identifier = invasion_identifier,
        intervention_type = intervention_type,
        --- The lord pool is now a flat record. The randomization-only pipeline picks a single
        --- agent_subtype up front and a level within the difficulty's lord_level_range. Names,
        --- ancillaries, and traits are not generated for randomized lords - they default to
        --- empty strings / empty tables in Army:create_from.
        lord = {
            agent_subtype = force_makeup.lord.agent_subtype,
            level_range = { difficulties[difficulty].lord_level_range[1], difficulties[difficulty].lord_level_range[2] },
        },
        heroes = {},
        unit_experience_amount = math.random(difficulties[difficulty].unit_experience_amount[1], difficulties[difficulty].unit_experience_amount[2]),
        units = {},
        reinforcing_ally_armies = false,
        reinforcing_enemy_armies = false,
        skill_overrides = {},
    }

    --- Save the skill overrides for the lord if available.
    if contains(force_makeup.lord, "skill_overrides", true) and #force_makeup.lord.skill_overrides > 0 then
        converted_force.skill_overrides[force_makeup.lord.agent_subtype] = {}
        for _, skill in ipairs(force_makeup.lord.skill_overrides) do
            table.insert(converted_force.skill_overrides[force_makeup.lord.agent_subtype], skill)
        end
    end

    --- Add the heroes if there are any and the skill overrides for them.
    if #force_makeup.heroes > 0 then
        for _, hero in ipairs(force_makeup.heroes) do
            table.insert(converted_force.heroes, {
                --- Create a copy of the hero without skill_overrides.
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

    --- Insert the units into the table as flat { id, count } records.
    for unit_type, units in pairs(force_makeup.units) do
        for _, unit in ipairs(units) do
            table.insert(converted_force.units, { id = unit, count = 1 })
        end
    end

    return converted_force
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- event_stack
--- (from models/events/event_stack.lua)

local EventStack = {
    --- Event level held by this stack.
    level = 0,
    --- Disordered event identifiers of this level.
    randomized_event_identifiers = {}
}

--- Sets the stack's level and shuffles 1..number_of_events into the identifiers list.
--- @param event_level number The event-difficulty level this stack represents.
--- @param number_of_events number Count of events to populate the stack with.
function EventStack:set_level_and_randomize_events(event_level, number_of_events)
    self.level = event_level
    self.randomized_event_identifiers = randomic_length_shuffle(number_of_events)
end

--- Pops and returns the first event identifier, or nil if the stack is empty.
--- @returns number The next event identifier, or nil when the stack is empty.
function EventStack:pop_event()
    return table.remove(self.randomized_event_identifiers, 1)
end


--- Flattens the stack's level + identifier list into a plain table for the save/load callbacks.
--- @returns table A serializable record with level and randomized_event_identifiers fields.
function EventStack:export_state_as_a_table()
    local event_stack_data = {}
    event_stack_data["level"] = self.level
    event_stack_data["randomized_event_identifiers"] = self.randomized_event_identifiers
    return event_stack_data
end

--- Restores level + identifier list from a previously exported state table.
--- @param previous_state table A record previously produced by export_state_as_a_table.
function EventStack:reinstate_if_able(previous_state)
    self.level = previous_state["level"]
    self.randomized_event_identifiers = previous_state["randomized_event_identifiers"]
end

--- Creates a new empty stack of level 0.
--- @returns EventStack A new EventStack instance.
function EventStack:new()
    local t = { level = 0, randomized_event_identifiers = {} }
    setmetatable(t, self)
    self.__index = self
    return t
end

--- Alias so battle_generator's lowercased binding still resolves.
local event_stack = EventStack

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- IncidentManager
--- (from controllers/incident_manager.lua)

local IGNORE_INCIDENT_PARAMETER_FLAG = 0

--- Fires an incident for the given player character, populating only the CQI slots indicated by `targets`.
--- @param incident_key string The incident key from the db.
--- @param targets table A flag map with optional faction, character, force, and region booleans.
--- @param player_character character The player character to receive the incident.
function trigger_incident_for_character(incident_key, targets, player_character)
    local faction_cqi = player_character:faction():command_queue_index()

    local target_faction_cqi = IGNORE_INCIDENT_PARAMETER_FLAG
    if targets.faction then
        target_faction_cqi = faction_cqi
    end

    local secondary_faction_cqi = IGNORE_INCIDENT_PARAMETER_FLAG

    local character_cqi = IGNORE_INCIDENT_PARAMETER_FLAG
    if targets.character then
        character_cqi = player_character:command_queue_index()
    end

    local military_force_cqi = IGNORE_INCIDENT_PARAMETER_FLAG
    if targets.force then
        military_force_cqi = player_character:military_force():command_queue_index()
    end

    local region_cqi = IGNORE_INCIDENT_PARAMETER_FLAG
    if targets.region then
    end

    local settlement_cqi = IGNORE_INCIDENT_PARAMETER_FLAG
    cm:trigger_incident_with_targets(faction_cqi, incident_key, target_faction_cqi, secondary_faction_cqi, character_cqi, military_force_cqi, region_cqi, settlement_cqi)
end

--- True if the faction is human-controlled and the human turn is currently active.
--- @param faction faction The faction object to check.
--- @returns boolean True when the faction is human and its turn is active.
function is_human_and_it_is_its_turn(faction)
    return faction:is_human() and cm:is_human_factions_turn()
end

--- Returns the player general closest to the given spot's coordinates.
--- @param spot_info table A spot_info record with a coordinates {x, y} field.
--- @returns character The closest player general, or nil when none is found.
function get_player_faction_character_closest_to_spot(spot_info)
    local faction_name = cm:get_local_faction_name()
    local only_general = true
    local is_garrison_commander = false
    local local_character, distance = cm:get_closest_character_to_position_from_faction(faction_name, spot_info.coordinates[1], spot_info.coordinates[2], only_general, is_garrison_commander)
    return local_character
end

--- Resolves the player character (falling back to closest-to-spot after a post-battle reload) and fires the incident, but only for humans on their turn.
--- @param incident_key string The incident key from the db.
--- @param targets table A flag map with optional faction, character, force, and region booleans.
--- @param spot_info table A spot_info record used as a fallback location for character lookup.
--- @param player_character character The triggering player character. May be nil after a reload.
function trigger_incident(incident_key, targets, spot_info, player_character)
    --- If the campaign was reloaded from a battle, the live player_character may be missing.
    --- Use the closest player general to the spot as a best-effort substitute. The rewards still
    --- go to the right faction even if the specific character is wrong.
    if player_character == nil or (type(player_character) == "table" and next(player_character) == nil) then
        player_character = get_player_faction_character_closest_to_spot(spot_info)
    end

    if is_human_and_it_is_its_turn(player_character:faction()) then
        trigger_incident_for_character(incident_key, targets, player_character)
    end
end

--- IncidentManager is a free-functions module. Expose an empty marker table so the return statement
--- at the end of this merged file can publish a stable handle.
local IncidentManager = {}

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- InvasionBattleManager
--- (from controllers/invasion_battle_manager.lua)

local IS_NOT_PERSISTENT_LISTENER = false

local InvasionBattleManager = {
    --- Main listener manager.
    core = false,
    --- Engine managers used to spawn random armies and run invasions.
    random_army_manager = false,
    invasion_manager = false,
    --- The army currently engaging the player.
    event_army = false
}

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Class methods

--- Generates a defense battle where the defender army holds the spot and the enemy character attacks it.
--- Preconditions: defender_army is the smithy/POI defender, enemy_character is at war with that faction
--- (or vice versa), and spot_coordinates is the defender's spawning point.
--- @param defender_army Army The Army instance that defends the spot.
--- @param enemy_character character The attacking character.
--- @param spot_coordinates table A {x, y} table for the defender spawn location.
function InvasionBattleManager:generate_defense_battle(defender_army, enemy_character, spot_coordinates)
    local x, y = self:find_location_for_character_to_spawn(defender_army.faction, spot_coordinates)
    --- we try to correct the problem if we cannot find another place to spawn the enemy armies
    local force_cqi = enemy_character:military_force():command_queue_index()

    self.event_army = defender_army
    self.event_army:randomize_units(self.random_army_manager)

    local defender_force = self.random_army_manager:generate_force(defender_army.force_identifier)
    local defence = self:setup_invasion(defender_army, enemy_character, defender_force, {x, y})
    defence:start_invasion(
        function(created_defender_force)
            cm:force_attack_of_opportunity(created_defender_force:get_general():military_force():command_queue_index(), force_cqi, false)
        end,
        false,
        false,
        false
    )
end


--- True if a valid spawn location exists for the offensive army near the spot.
--- @param offensive_army Army The attacking Army instance.
--- @param spot_coordinates table A {x, y} table for the spot center.
--- @returns boolean True when find_location_for_character_to_spawn returns valid coordinates.
function InvasionBattleManager:can_generate_battle(offensive_army, spot_coordinates)
    if offensive_army then
        out("DEBUG - can_generate_battle checking if we can find a location to spawn the army")
        local x, y = self:find_location_for_character_to_spawn(offensive_army.faction, spot_coordinates)
        if x ~= -1 and y ~= -1 then
            return true
        end
    end
    out("DEBUG - can_generate_battle could not find a location to spawn the army")
    return false
end


--- Generates an offensive battle. Routes through enemy reinforcement / ally reinforcement / direct attack
--- paths depending on which reinforcement data the encounter carries.
--- @param offensive_army Army The attacking Army instance.
--- @param player_character character The player character being attacked.
--- @param spot_coordinates table A {x, y} table for the spot center.
function InvasionBattleManager:generate_battle(offensive_army, player_character, spot_coordinates)
    self.event_army = offensive_army
    out("DEBUG - testing randomize_units")
    self.event_army:randomize_units(self.random_army_manager)
    out("DEBUG - event army randomized in generate_battle")

    local force_cqi = player_character:military_force():command_queue_index()
    local player_faction_name = player_character:faction():name()

    --- Dispatch based on which reinforcement data the encounter carries.
    if self.event_army:has_offensive_reinforcements() then
        --- Enemy reinforcement path also chains into ally spawning inside the recursive callback
        --- (create_enemy_reinforcements_before_attack -> create_allied_reinforcements_before_attack).
        self:create_enemy_reinforcements_before_attack(player_character, player_faction_name, force_cqi, spot_coordinates, 1)
    elseif self.event_army:has_ally_reinforcements() then
        --- Ally-only path. No enemy reinforcements exist yet, so we pass player_character as the
        --- ally's objective_character. set_target("CHARACTER", ...) is a movement target, not a
        --- hostility marker - no war is declared between ally and player. The ally just moves toward
        --- the player to be in range. The ally-vs-main-enemy war is declared later by
        --- declare_war_on_ally_reinforcement_if_available inside main_attacker_attacks_player_and_allies.
        self:create_allied_reinforcements_before_attack(player_character, player_faction_name, force_cqi, spot_coordinates, player_character)
    else
        self:main_attacker_attacks_player_and_allies(player_character, player_faction_name, force_cqi, spot_coordinates)
    end
end


--- Spawns enemy reinforcement armies first. The main attacker is launched after the last
--- reinforcement is in place (and any ally reinforcements are spawned in between if present).
--- @param player_character character The player character being attacked.
--- @param player_faction_name string The player faction key.
--- @param force_cqi number The player force CQI.
--- @param spot_coordinates table A {x, y} table for the spot center.
--- @param army_number number 1-based index of the reinforcement army being spawned.
function InvasionBattleManager:create_enemy_reinforcements_before_attack(player_character, player_faction_name, force_cqi, spot_coordinates, army_number)
    local reinforcing_army = self.event_army.reinforcing_enemy_armies[army_number]
    reinforcing_army:randomize_units(self.random_army_manager)
    local x, y = self:find_location_for_character_to_spawn(reinforcing_army.faction, spot_coordinates)
    local invader_force = self.random_army_manager:generate_force(reinforcing_army.force_identifier)
    local invasion = self:setup_invasion(reinforcing_army, player_character, invader_force, {x, y})

    invasion:start_invasion(
        function(invasion_force)
            --- Force war with this faction for the player.
            local call_player_allies_to_war = false
            local call_faction_allies_to_war = false
            cm:force_declare_war(reinforcing_army.faction, player_faction_name, call_player_allies_to_war, call_faction_allies_to_war)
            if army_number == #self.event_army.reinforcing_enemy_armies then
                --- All enemy reinforcements have been spawned.
                if self.event_army:has_ally_reinforcements() then
                    local enemy_character = cm:get_closest_character_to_position_from_faction(reinforcing_army.faction, spot_coordinates[1], spot_coordinates[2])
                    self:create_allied_reinforcements_before_attack(player_character, player_faction_name, force_cqi, spot_coordinates, enemy_character)
                else
                    self:main_attacker_attacks_player_and_allies(player_character, player_faction_name, force_cqi, spot_coordinates)
                end
            else
                local next_army_number = army_number + 1
                self:create_enemy_reinforcements_before_attack(player_character, player_faction_name, force_cqi, spot_coordinates, next_army_number)
            end
        end,
        false,
        false,
        false
    )
end


--- Spawns the allied reinforcement army (if any) and then launches the main attacker.
--- @param player_character character The player character being attacked.
--- @param player_faction_name string The player faction key.
--- @param force_cqi number The player force CQI.
--- @param spot_coordinates table A {x, y} table for the spot center.
--- @param enemy_character character The enemy whose army the ally targets for movement.
function InvasionBattleManager:create_allied_reinforcements_before_attack(player_character, player_faction_name, force_cqi, spot_coordinates, enemy_character)
    local reinforcing_army = self.event_army.reinforcing_ally_armies[1]
    reinforcing_army:randomize_units(self.random_army_manager)
    local x, y = self:find_location_for_character_to_spawn(reinforcing_army.faction, spot_coordinates)
    local invader_force = self.random_army_manager:generate_force(reinforcing_army.force_identifier)
    local invasion = self:setup_invasion(reinforcing_army, enemy_character, invader_force, {x, y})
    invasion:start_invasion(
        function(invasion_force)
            --- Force war with the enemy reinforcement armies.
            self:ally_reinforcement_declares_war_to_enemy_reinforcements_if_available(reinforcing_army.faction)
            self:main_attacker_attacks_player_and_allies(player_character, player_faction_name, force_cqi, spot_coordinates)
        end,
        false,
        false,
        false
    )
end


--- Declares war from `allied_faction` against every enemy reinforcement army on the encounter, if any.
--- @param allied_faction string The faction key of the allied reinforcement army.
function InvasionBattleManager:ally_reinforcement_declares_war_to_enemy_reinforcements_if_available(allied_faction)
    if self.event_army:has_offensive_reinforcements() then
        local call_player_allies_to_war = false
        local call_faction_allies_to_war = false
        for i=1, #self.event_army.reinforcing_enemy_armies do
            cm:force_declare_war(allied_faction, self.event_army.reinforcing_enemy_armies[i].faction, call_player_allies_to_war, call_faction_allies_to_war)
        end
    end
end


--- Spawns the main attacker, embeds heroes + skill overrides, declares war on the player and any
--- allied reinforcements, then dispatches the engagement (ambush, interception, or allied reinforcements).
--- @param player_character character The player character being attacked.
--- @param player_faction_name string The player faction key.
--- @param player_force_cqi number The player force CQI.
--- @param spot_coordinates table A {x, y} table for the spot center.
function InvasionBattleManager:main_attacker_attacks_player_and_allies(player_character, player_faction_name, player_force_cqi, spot_coordinates)
    local x, y = self:find_location_for_character_to_spawn(self.event_army.faction, spot_coordinates)
    local invader_force = self.random_army_manager:generate_force(self.event_army.force_identifier)
    local invasion = self:setup_invasion(self.event_army, player_character, invader_force, {x, y})

    out("DEBUG - invasion setup complete. Now starting invasion")

    invasion:start_invasion(
        function(invasion_force)
            self.core:add_listener(
                "land_enc_and_poi_encounter_engage_invader",
                "FactionLeaderDeclaresWar",
                true,
                function(local_context)
                    --- Force-declare war on any reinforcement allies of the player.
                    self:declare_war_on_ally_reinforcement_if_available()

                    --- Spawn any heroes and embed them into the invasion army.
                    local skill_overrides = self.event_army:get_skill_overrides()
                    local heroes = self.event_army:get_heroes()
                    for _, hero_object in ipairs(heroes) do
                        out("DEBUG - spawning invasion hero " .. hero_object.agent_subtype .. ".")
                        --- A valid spawn location is required or the agent creation call fails.
                        local agent_x, agent_y = cm:find_valid_spawn_location_for_character_from_settlement(self.event_army.faction, "wh3_main_combi_region_ubersreik", false, true, 10)
                        out("DEBUG - agent_x: " .. agent_x .. " agent_y: " .. agent_y)
                        out("DEBUG - faction: " .. self.event_army.faction)
                        out("DEBUG - hero_object.agent_subtype: " .. hero_object.agent_subtype)
                        out("DEBUG - hero_object.agent_type: " .. hero_object.agent_type)
                        local new_invasion_hero_agent = cm:create_agent(self.event_army.faction, hero_object.agent_type, hero_object.agent_subtype, agent_x, agent_y)

                        out("DEBUG - new_invasion_hero_agent spawned with cqi: " .. new_invasion_hero_agent:command_queue_index())
                        for temp_hero_agent_subtype, skill_override in pairs(skill_overrides) do
                            if hero_object.agent_subtype == temp_hero_agent_subtype then
                                out("DEBUG - adding skills to invasion force hero " .. temp_hero_agent_subtype .. " of cqi " .. new_invasion_hero_agent:command_queue_index())
                                for _, skill in ipairs(skill_override) do
                                    cm:add_skill(new_invasion_hero_agent, skill, true, true)
                                end
                            end
                        end

                        cm:embed_agent_in_force(new_invasion_hero_agent, invasion_force:get_general():military_force())
                    end

                    --- Apply skill overrides to the invasion force lord.
                    out("DEBUG - invasion force lord cqi: " .. invasion_force:get_general():command_queue_index())
                    for lord_agent_subtype, skill_override in pairs(skill_overrides) do
                        if self.event_army.lord.subtype == lord_agent_subtype then
                            out("DEBUG - adding skills to invasion force lord of cqi " .. invasion_force:get_general():command_queue_index())
                            for _, skill in ipairs(skill_override) do
                                cm:add_skill(invasion_force:get_general(), skill, true, true)
                            end
                            break
                        end
                    end

                    local faction_being_declared_war_to = local_context:character():faction():name()
                    if faction_being_declared_war_to == self.event_army.faction then
                        if self.event_army.intervention_type == AMBUSH_TYPE then
                            out("DEBUG - AMBUSH_TYPE called.")
                            cm:force_attack_of_opportunity(invasion_force:get_general():military_force():command_queue_index(), player_force_cqi, true)
                        elseif self.event_army.intervention_type == INTERCEPTION_TYPE then
                            out("DEBUG - INTERCEPTION_TYPE called.")

                            cm:force_attack_of_opportunity(invasion_force:get_general():military_force():command_queue_index(), player_force_cqi, false)
                        else -- ALLIED_REINFORCEMENTS_PERMITTED_TYPE
                            out("DEBUG - ALLIED_REINFORCEMENTS_PERMITTED_TYPE called.")
                            cm:force_attack_of_opportunity(player_force_cqi, invasion_force:get_general():military_force():command_queue_index(), false)
                        end
                    end

                    out("DEBUG - attack initiated")
                end,
                IS_NOT_PERSISTENT_LISTENER
            )

            --- Apply lord trait + ancillaries on a short delay so the general object exists.
            cm:callback(
                function()
                    self:try_add_trait_to_invading_lord(invasion_force:get_general())
                    self:try_add_ancillaries_to_invading_lord(invasion_force:get_general())
                end,
            0.1)

            --- Force-declare war between the encounter faction and the player on a slightly longer delay.
            cm:callback(
                function()
                    local call_player_allies_to_war = false
                    local call_faction_allies_to_war = false
                    cm:force_declare_war(self.event_army.faction, player_faction_name, call_player_allies_to_war, call_faction_allies_to_war)
    			end,
			0.5)
        end,
        false,
        false,
        false
    )
end

--- Applies the encounter lord's trait (if any) to the invasion general.
--- @param invasion_general character The newly spawned invasion general.
function InvasionBattleManager:try_add_trait_to_invading_lord(invasion_general)
    local lord_lookup = cm:char_lookup_str(invasion_general)
    local lord_trait = self.event_army.lord.trait
    if lord_trait ~= nil then
        cm:force_add_trait(lord_lookup, lord_trait, false , 1)
    end
end

--- Applies all of the encounter lord's ancillaries to the invasion general.
--- @param invasion_general character The newly spawned invasion general.
function InvasionBattleManager:try_add_ancillaries_to_invading_lord(invasion_general)
    for i = 1, #self.event_army.lord.ancillaries do
        cm:force_add_ancillary(invasion_general, self.event_army.lord.ancillaries[i], true, true)
    end
end

--- Force-declares war from the encounter faction onto the first allied reinforcement (player allies max out at 1 for now).
function InvasionBattleManager:declare_war_on_ally_reinforcement_if_available()
    if self.event_army:has_ally_reinforcements() then
        local call_player_allies_to_war = false
        local call_faction_allies_to_war = false
        cm:force_declare_war(self.event_army.faction, self.event_army.reinforcing_ally_armies[1].faction, call_player_allies_to_war, call_faction_allies_to_war)
    end
end


--- Builds a new invasion for the given army, sets its target, creates the general, and applies
--- experience + the upkeep-free effect. See invasion_manager docs at
--- https://chadvandy.github.io/tw_modding_resources/WH3/campaign/invasion_manager.html.
--- @param army Army The Army instance whose data populates the invasion.
--- @param objective_character character The character the new invasion targets for movement.
--- @param force table The random-army-manager force descriptor (output of generate_force).
--- @param force_lat_lng table A {x, y} table where the invasion spawns.
--- @returns table The new invasion handle returned by invasion_manager:new_invasion.
function InvasionBattleManager:setup_invasion(army, objective_character, force, force_lat_lng)
    if self.invasion_manager:get_invasion(army.invasion_identifier) then
        self.invasion_manager:remove_invasion(army.invasion_identifier)
    end

    local new_invasion = self.invasion_manager:new_invasion(army.invasion_identifier, army.faction, force, force_lat_lng)

    new_invasion:apply_effect("wh_main_bundle_military_upkeep_free_force", -1)

    new_invasion:set_target("CHARACTER", objective_character:command_queue_index(), objective_character:faction():name())

    --- Agent subtypes come from the agent_subtypes_tables.
    out("DEBUG - creating general for invasion with the following data: " .. army.lord.subtype .. " " .. army.lord.forename .. " " .. army.lord.clan_name .. " " .. army.lord.family_name .. " " .. army.lord.other_name)
    new_invasion:create_general(false, army.lord.subtype, army.lord.forename, army.lord.clan_name, army.lord.family_name, army.lord.other_name)

    local by_level = true
    new_invasion:add_character_experience(army.lord.level, by_level)
    new_invasion:add_unit_experience(army.unit_experience_amount)

    return new_invasion
end

--- Queues a one-off FactionTurnStart listener that removes the invasion's forces next turn.
--- @param army Army The Army whose invasion forces should be removed at next turn start.
function InvasionBattleManager:mark_battle_forces_for_removal(army)
    self.core:add_listener(
        "land_enc_and_poi_encounter_removal",
        "FactionTurnStart",
        true,
        function(context)
            self:remove_invasion_forces(army)
        end,
        IS_NOT_PERSISTENT_LISTENER
	)
end


--- Stashes `army` as the manager's current event_army so a later reset_state_post_battle can clean it up.
--- @param army Army The Army to remember for cleanup.
function InvasionBattleManager:set_auxiliary_army_for_reset(army)
    self.event_army = army
end


--- Registers a one-off BattleCompleted listener that cleans up the invasion forces and routes the result to the delegate.
--- @param delegate table The delegate (BattleSpotEventDelegate or SmithyEventDelegate) that receives the battle outcome.
--- @param spot_type string Either "BattleSpot" or "SmithySpot" - controls how the result is forwarded.
--- @param spot_info table A spot_info record for the spot that triggered the battle.
--- @param army Army The encounter Army whose invasion forces will be cleaned up.
function InvasionBattleManager:reset_state_post_battle(delegate, spot_type, spot_info, army)
	self.core:add_listener(
        "land_enc_and_poi_encounter_post_battle",
        "BattleCompleted",
        true,
        function(context)
            local found_encounter_faction = false
            local player_won_battle = false

            local attacker_was_victorious = cm:pending_battle_cache_attacker_victory()
            local defender_was_victorious = cm:pending_battle_cache_defender_victory()

            local player_faction_name = cm:get_local_faction_name()
            local encounter_invasion = self.invasion_manager:get_invasion(army.invasion_identifier)
            --- Defensive-type battles cannot be tracked easily, so we only branch on player attacker/defender.
            if cm:pending_battle_cache_faction_is_attacker(player_faction_name) then
                found_encounter_faction = true
                if attacker_was_victorious then
                    player_won_battle = true
                end
                if encounter_invasion then
                    self:remove_invasion_forces(army)
                end
            elseif cm:pending_battle_cache_faction_is_defender(player_faction_name) then
                found_encounter_faction = true
                if defender_was_victorious then
                    player_won_battle = true
                end
                if encounter_invasion then
                    self:remove_invasion_forces(army)
                end
            end

            if found_encounter_faction == true then
                if spot_type == "BattleSpot" then
                    delegate:trigger_event_given_battle_result(player_won_battle, spot_info)
                elseif spot_type == "SmithySpot" then
                    delegate:trigger_event_given_battle_result(player_won_battle)
                end
            end
        end,
        IS_NOT_PERSISTENT_LISTENER
	)
end


--- Kills the main encounter invasion force plus any enemy + ally reinforcement forces.
--- @param army Army The encounter Army to clean up.
function InvasionBattleManager:remove_invasion_forces(army)
    self:remove_invasion_force_by_identifier(army.invasion_identifier)
    if army:has_offensive_reinforcements() then
        for i=1, #army.reinforcing_enemy_armies do
            self:remove_invasion_force_by_identifier(army.reinforcing_enemy_armies[i].invasion_identifier)
        end
    end

    if army:has_ally_reinforcements() then
        for i=1, #army.reinforcing_ally_armies do
            self:remove_invasion_force_by_identifier(army.reinforcing_ally_armies[i].invasion_identifier)
        end
    end
end


--- Kills a single invasion force by id, temporarily suppressing the related event-feed entries.
--- @param invasion_identifier string The invasion identifier registered with invasion_manager.
function InvasionBattleManager:remove_invasion_force_by_identifier(invasion_identifier)
    local force = self.invasion_manager:get_invasion(invasion_identifier)
    if force then
        cm:disable_event_feed_events(true, "", "", "diplomacy_faction_destroyed")
        cm:disable_event_feed_events(true, "wh_event_category_character", "", "")
        force:kill()
        cm:callback(function() cm:disable_event_feed_events(false, "", "", "diplomacy_faction_destroyed") end, 1)
        cm:callback(function() cm:disable_event_feed_events(false, "wh_event_category_character", "", "") end, 1)
    end
end


--- Finds a valid spawn location near `center_coordinates`. Walks outward in 2-meter steps up to 4 iterations,
--- alternating between same-region and other-region checks. Returns (-1, -1) on failure - the battle will not trigger.
--- @param faction_name string The faction key that needs a spawn location.
--- @param center_coordinates table A {x, y} table around which to search.
--- @returns number, number The found x, y coordinates. Returns (-1, -1) when no valid spot exists.
function InvasionBattleManager:find_location_for_character_to_spawn(faction_name, center_coordinates)
    local x, y = cm:find_valid_spawn_location_for_character_from_position(faction_name, center_coordinates[1], center_coordinates[2], false)
    for i = 0, 4 do
        --- Same-region check.
        if x == -1 and y == -1 then
            x, y = cm:find_valid_spawn_location_for_character_from_position(faction_name, center_coordinates[1], center_coordinates[2], true, i*2)
        else
            break
        end

        --- Other-region check.
        if x == -1 and y == -1 then
            x, y = cm:find_valid_spawn_location_for_character_from_position(faction_name, center_coordinates[1], center_coordinates[2], false, i*2)
        else
            break
        end
    end

    return x, y
end


--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Constructors

--- Constructs a new InvasionBattleManager wired to the given engine managers.
--- @param core table The CA core listener-manager handle.
--- @param random_army_manager table The CA random_army_manager handle.
--- @param invasion_manager table The CA invasion_manager handle.
--- @returns InvasionBattleManager A new instance with the supplied managers wired in.
function InvasionBattleManager:newFrom(core, random_army_manager, invasion_manager)
    local t = {
        core = core,
        random_army_manager = random_army_manager,
        invasion_manager = invasion_manager
    }
    setmetatable(t, self)
    self.__index = self
    return t
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- BattleGenerator
--- (from generators/battle_generator.lua)

local LEVEL_KEY = 2

local BattleGenerator = {
    event_stacks = {}
}

--- Returns a battle event for the given turn, refilling the per-level stacks if they have been exhausted.
--- @param turn_number number The current campaign turn.
--- @returns table The selected battle event entry from battle_events_by_level.
function BattleGenerator:get_randomized_event_given_turn_number(turn_number)
    local event = self:try_get_randomized_event_given_turn_number(turn_number)

    if next(event) == nil then
        self:reset_stacks()
        event = self:try_get_randomized_event_given_turn_number(turn_number)
    end

    return battle_events_by_level[event.current_level][event.event_of_level]
end

--- Picks an event by querying the spillover algorithm and popping from the highest-chance non-empty stack.
--- Returns an empty table when every per-level stack is empty.
--- @param turn_number number The current campaign turn.
--- @returns table A { current_level number, event_of_level number } record, or {} when stacks are empty.
function BattleGenerator:try_get_randomized_event_given_turn_number(turn_number)
    --- Levels are returned sorted by chance of happening (descending).
    local ordered_levels_by_chances_of_happening = randomize_chances_of_event_happening_considering_spillover_given_turn(#battle_events_by_level, turn_number)

    for prioritized_order = 1, #ordered_levels_by_chances_of_happening do
        local current_chance = ordered_levels_by_chances_of_happening[prioritized_order][1]
        local current_level = ordered_levels_by_chances_of_happening[prioritized_order][LEVEL_KEY]

        local event_of_level = nil
        if current_chance > 0 and next(self.event_stacks) ~= nil then
            event_of_level = self.event_stacks[current_level]:pop_event()
        end

        if event_of_level ~= nil then
            return { current_level = current_level, event_of_level = event_of_level }
        end
    end

    return {}
end

--- Re-randomizes every per-level event stack. Called when every stack has been exhausted.
--- Reads battle_events_by_level so newly added events show up automatically on the next refresh.
function BattleGenerator:reset_stacks()
    for level = 1, #battle_events_by_level do
        local number_of_events_of_level = #(battle_events_by_level[level])
        if self.event_stacks[level] == nil then
            self.event_stacks[level] = event_stack:new()
        end
        self.event_stacks[level]:set_level_and_randomize_events(level, number_of_events_of_level)
    end
end

--- Exports every event stack's state into a flat array for the save/load callbacks.
--- @returns table An array of EventStack export records, one per level.
function BattleGenerator:export_state_as_a_table()
    local battle_generator_data = {}
    for i=1, #self.event_stacks do
        table.insert(battle_generator_data, self.event_stacks[i]:export_state_as_a_table())
    end
    return battle_generator_data
end

--- Restores all event stacks from a previously exported state.
--- @param previous_state table An array of EventStack export records.
function BattleGenerator:reinstate_if_able(previous_state)
    for i=1, #previous_state do
        local new_event_stack = event_stack:new()
        new_event_stack:reinstate_if_able(previous_state[i])
        table.insert(self.event_stacks, new_event_stack)
    end
end

--- Creates a new BattleGenerator with empty event stacks.
--- @returns BattleGenerator A new generator with empty event stacks.
function BattleGenerator:new()
    local t = { event_stacks = {} }
    setmetatable(t, self)
    self.__index = self
    return t
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- SpotEventManager
--- (from controllers/spot_event_manager.lua)

--- Out of 100, this many rolls go to the battle delegate (the rest go to the treasure delegate).
local CHANCES_OF_BATTLE_EVENT = 90

local SpotEventManager = {
    treasure_event_delegate = {},
    battle_event_delegate = {},
    current_spot_info = {}
}

--- Stores the live spot info so subsequent dilemma-choice callbacks know which spot to use.
--- @param spot_info table A spot_info record for the spot currently being triggered.
function SpotEventManager:set_current_spot_info(spot_info)
    self.current_spot_info = spot_info
end


--- Rolls battle vs treasure for the current spot and dispatches to the matching delegate.
--- Returns true when the spot should be removed from the map.
--- @param area_and_character_info table The AreaEntered context with area_key and family_member.
--- @param turn_number number The current campaign turn.
--- @returns boolean True when the spot should be deactivated after dispatch.
function SpotEventManager:trigger_spot_event(area_and_character_info, turn_number)
    if cm:random_number(100) > CHANCES_OF_BATTLE_EVENT then
        self.treasure_event_delegate:trigger_event(area_and_character_info)
        return true
    else
        return self.battle_event_delegate:trigger_pre_battle_dilemma(area_and_character_info, self.current_spot_info, turn_number)
    end
end


--- Forwards a dilemma-choice event to the battle delegate with the stored spot info.
--- @param dilemma_choice_and_faction_info table The DilemmaChoiceMadeEvent context.
function SpotEventManager:trigger_dilemma_event_given_choice(dilemma_choice_and_faction_info)
    self.battle_event_delegate:trigger_dilemma_event_given_choice(dilemma_choice_and_faction_info, self.current_spot_info)
end


--- Exports the battle delegate's in-flight event for save/load.
--- @returns table A flat record describing the active battle event, suitable for the save state.
function SpotEventManager:export_state_as_a_table()
    return self.battle_event_delegate:export_state_as_a_table(self.current_spot_info)
end

--- Restores an in-flight battle delegate event from previously saved state.
--- @param previou_state table Previously exported battle delegate state.
function SpotEventManager:reinstate_event_if_able(previou_state)
    self.battle_event_delegate:reinstate_event_if_able(previou_state)
end

--- Lazy-loads the battle + treasure delegate modules (avoiding the circular require) and builds the manager.
--- @param invasion_battle_manager InvasionBattleManager The shared invasion battle manager.
--- @returns SpotEventManager A new manager with battle + treasure delegates wired in.
function SpotEventManager:new(invasion_battle_manager)
    TreasureEventDelegate = TreasureEventDelegate or require("script/land_encounters/features/treasure_spot")
    BattleEventDelegate = BattleEventDelegate or require("script/land_encounters/features/battle_spot")
    local t = {
        treasure_event_delegate = TreasureEventDelegate:new(),
        battle_event_delegate = BattleEventDelegate:new(invasion_battle_manager)
    }
    setmetatable(t, self)
    self.__index = self
    return t
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- PointOfInterestEventManager
--- (from controllers/point_of_interest_event_manager.lua)

local PointOfInterestEventManager = {
    smithy_event_delegate = {}
}


--- Asks each POI delegate to bootstrap its per-zone state from the configured coordinates.
--- @param points_of_interest_by_zone table Region-keyed table of POI coordinate data.
function PointOfInterestEventManager:generate_points_of_interests_states(points_of_interest_by_zone)
    for zone_name, coordinates in pairs(points_of_interest_by_zone) do
        self.smithy_event_delegate:generate_states(zone_name, coordinates["smithies"])
    end
end


--- Forwards per-turn state updates to each POI delegate.
function PointOfInterestEventManager:update_state_given_turn_passing()
    self.smithy_event_delegate:update_state_given_turn_passing()
end


--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Event management

--- Dispatches a POI event to the matching delegate.
--- @param poi_type string The POI type tag (e.g. "SmithySpot").
--- @param area_and_character_info table The AreaEntered context.
--- @param spot_info table The spot_info record for the triggered POI.
function PointOfInterestEventManager:trigger_poi_event(poi_type, area_and_character_info, spot_info)
    if poi_type == "SmithySpot" then
        self.smithy_event_delegate:trigger_event(area_and_character_info, spot_info)
    end
end

--- Forwards a dilemma-choice event to the smithy POI delegate.
--- @param dilemma_choice_and_faction_info table The DilemmaChoiceMadeEvent context.
--- @param spot_info table The spot_info record for the triggered POI.
function PointOfInterestEventManager:trigger_dilemma_event_given_choice(dilemma_choice_and_faction_info, spot_info)
    self.smithy_event_delegate:trigger_dilemma_event_given_choice(dilemma_choice_and_faction_info, spot_info)
end


--- Exports the smithy delegate's per-zone POI state for save/load.
--- @returns table A table keyed by POI type whose values are delegate-specific save records.
function PointOfInterestEventManager:export_state_as_table()
    local points_of_interests_data = {}
    points_of_interests_data["smithies"] = self.smithy_event_delegate:export_state_as_table()
    return points_of_interests_data
end


--- Restores the smithy delegate's per-zone POI state from previously saved data.
--- @param previous_state table The keyed save record previously produced by export_state_as_table.
function PointOfInterestEventManager:reinstate_event_if_able(previous_state)
    self.smithy_event_delegate:reinstate_event_if_able(previous_state["smithies"])
end


--- Lazy-loads the smithy delegate module (avoiding the circular require) and builds the manager.
--- @param mission_manager table The CA mission_manager handle.
--- @param invasion_battle_manager InvasionBattleManager The shared invasion battle manager.
--- @returns PointOfInterestEventManager A new manager with the smithy delegate wired in.
function PointOfInterestEventManager:new(mission_manager, invasion_battle_manager)
    SmithyEventDelegate = SmithyEventDelegate or require("script/land_encounters/features/smithy")
    local t = {
        smithy_event_delegate = SmithyEventDelegate:new(mission_manager, invasion_battle_manager)
    }
    setmetatable(t, self)
    self.__index = self
    return t
end

return {
    IncidentManager = IncidentManager,
    InvasionBattleManager = InvasionBattleManager,
    BattleGenerator = BattleGenerator,
    SpotEventManager = SpotEventManager,
    PointOfInterestEventManager = PointOfInterestEventManager,
    EventStack = EventStack,
}
