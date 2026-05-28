--- MCT anchor file for the Land Encounters and Points of Interest mod. Auto-discovered by MCT,
--- this declares every settings option, the layout of pages/sections, and the listeners that
--- enforce inter-option constraints (at-least-one rules, master/child checkbox locking).

require("script/land_encounters/core/mct")

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Initial MCT setup

local mct = get_mct()
local mct_mod = mct:register_mod("land_encounters_and_points_of_interest")
if is_function(mct_mod.set_workshop_id) then
    mct_mod:set_workshop_id("3397481450");
end;
if is_function(mct_mod.set_main_image) then
    mct_mod:set_main_image("ui/images/mct_main_image.png", 300, 300);
end;

--- Set title, author and description.
mct_mod:set_title("!!!land_encounters_and_points_of_interest_mct_title", true)
mct_mod:set_author("!!!land_encounters_and_points_of_interest_mct_author")
mct_mod:set_description("!!!land_encounters_and_points_of_interest_mct_description", true)

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Configuration section and the first page

local section = mct_mod:add_new_section("configuration_section")
section:set_localised_text("Configuration", true)

local disable_smithies_checkbox = mct_mod:add_new_option("disable_smithies", "checkbox")
disable_smithies_checkbox:set_text("Remove Smithies from the map", true)
disable_smithies_checkbox:set_tooltip_text("Will need to load the save again to take effect.", true)
disable_smithies_checkbox:set_is_global(true)
disable_smithies_checkbox:set_default_value(false)
disable_smithies_checkbox:set_assigned_section("configuration_section")

--- Slider for what percentage of the possible total spots can have an event spawned into the world.
local spawn_percentage_slider = mct_mod:add_new_option("spawn_percentage", "slider")
spawn_percentage_slider:set_text("Controls the % of total points on the map that can have an encounter spawn", true)
spawn_percentage_slider:set_tooltip_text("Default is 0.75 or 75% of total points on the map can be active at once.", true)
spawn_percentage_slider:set_is_global(true)
spawn_percentage_slider:slider_set_min_max(0.10, 1.00)
spawn_percentage_slider:slider_set_precision(2)
spawn_percentage_slider:slider_set_step_size(0.05, 2)
spawn_percentage_slider:set_default_value(0.75)
spawn_percentage_slider:set_assigned_section("configuration_section")

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Battle Engagement Behavior

local battle_engagement_section = mct_mod:add_new_section("battle_engagement_section")
battle_engagement_section:set_localised_text("Battle Engagement Behavior", true)

local intervention_ambush_checkbox = mct_mod:add_new_option("intervention_ambush", "checkbox")
intervention_ambush_checkbox:set_text("Allow Ambush encounters", true)
intervention_ambush_checkbox:set_tooltip_text("When enabled, some land-encounter battles will be set up as ambushes - enemy composition will be hidden and the battle cannot be retreated from before it starts. Higher difficulty.", true)
intervention_ambush_checkbox:set_is_global(true)
intervention_ambush_checkbox:set_default_value(false)
intervention_ambush_checkbox:set_assigned_section("battle_engagement_section")

local intervention_interception_checkbox = mct_mod:add_new_option("intervention_interception", "checkbox")
intervention_interception_checkbox:set_text("Allow Interception encounters", true)
intervention_interception_checkbox:set_tooltip_text("When enabled, land-encounter battles will be set up as interceptions - enemy composition visible, no retreat from the dilemma but standard battle mechanics. This is the default behavior.", true)
intervention_interception_checkbox:set_is_global(true)
intervention_interception_checkbox:set_default_value(true)
intervention_interception_checkbox:set_assigned_section("battle_engagement_section")

local intervention_allied_checkbox = mct_mod:add_new_option("intervention_allied_reinforcements", "checkbox")
intervention_allied_checkbox:set_text("Allow Allied-Reinforcement encounters", true)
intervention_allied_checkbox:set_tooltip_text("When enabled, some land-encounter battles will let the player attack the encounter with allied reinforcements available. Easier difficulty.", true)
intervention_allied_checkbox:set_is_global(true)
intervention_allied_checkbox:set_default_value(false)
intervention_allied_checkbox:set_assigned_section("battle_engagement_section")

--- At-least-one enforcement: lock whichever option is the last one currently checked, so the user
--- cannot reach an all-off state. Recompute after every toggle of any of the three.
local intervention_option_keys = {
    "intervention_ambush",
    "intervention_interception",
    "intervention_allied_reinforcements",
}

--- Locks whichever intervention option is the last one currently checked so the user cannot reach an all-off state.
local function recompute_intervention_locks()
    local enabled = {}
    for _, key in ipairs(intervention_option_keys) do
        if mct_mod:get_option_by_key(key):get_selected_setting() then
            table.insert(enabled, key)
        end
    end
    local lock_last_only = (#enabled == 1)
    for _, key in ipairs(intervention_option_keys) do
        local option = mct_mod:get_option_by_key(key)
        local is_only_enabled = lock_last_only and option:get_selected_setting()
        option:set_locked(is_only_enabled)
    end
end

recompute_intervention_locks()

core:add_listener(
    "leapoi_intervention_at_least_one_enforcer",
    "MctOptionSelectedSettingSet",
    function(context)
        local key = context:option():get_key()
        for _, intervention_key in ipairs(intervention_option_keys) do
            if key == intervention_key then return true end
        end
        return false
    end,
    function(_)
        recompute_intervention_locks()
    end,
    true
)

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Encounter skin configuration

local encounters_section = mct_mod:add_new_section("encounter_skins_section")
encounters_section:set_localised_text("Encounter Skin Configuration", true)
encounters_section:set_description("Checkboxes are provided for each encounter skin to show up in the randomized rotation. They are enabled by default.\n\nTakes effect the next time the locations are spawned in again.")

--- Master checkbox to lock all encounter skin checkboxes.
local enable_all_encounter_skins_checkbox = mct_mod:add_new_option("enable_all_encounter_skins", "checkbox")
enable_all_encounter_skins_checkbox:set_text("Enable all encounter skins", true)
enable_all_encounter_skins_checkbox:set_tooltip_text("When enabled, all encounter skins will be activated and individual checkboxes will be disabled.", true)
enable_all_encounter_skins_checkbox:set_is_global(true)
enable_all_encounter_skins_checkbox:set_default_value(true)
enable_all_encounter_skins_checkbox:set_assigned_section("encounter_skins_section")

--- Individual encounter skin checkboxes.
local encounter_checkbox_ids = get_encounter_checkbox_ids()
for _, encounter in ipairs(get_encounter_data()) do
    local key = "encounter_" .. encounter.id
    local checkbox = mct_mod:add_new_option(key, "checkbox")
    checkbox:set_text(encounter.text, true)
    checkbox:set_tooltip_text("Enable this encounter skin.", true)
    checkbox:set_is_global(true)
    checkbox:set_default_value(true)
    checkbox:set_assigned_section("encounter_skins_section")
    table.insert(encounter_checkbox_ids, encounter.id)
end

--- When the master "enable all encounter skins" checkbox is toggled, lock/unlock every individual skin checkbox to match.
core:add_listener(
    "lock_all_encounter_checkboxes",
    "MctOptionSelectedSettingSet",
    function(context)
        return context:option():get_key() == "enable_all_encounter_skins"
    end,
    function(context)
        local option = context:option()
        local mct_mod = option:get_mod()

        --- Read the live UI value via context:setting(). get_finalized_setting() is not updated until the UI is closed.
        local new_checkbox_val = context:setting()

        for i = 1, #encounter_checkbox_ids do
            local i_option_key = encounter_checkbox_ids[i]
            local key = "encounter_" .. i_option_key
            local i_option = mct_mod:get_option_by_key(key)
            i_option:set_locked(new_checkbox_val)
        end
    end,
    true
)

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Randomized encounter force generation section

--- Sections for the new randomized encounter force generation, assigned to their own page.
local randomized_encounter_force_generation_section = mct_mod:add_new_section("randomized_encounter_force_generation_section")
randomized_encounter_force_generation_section:set_localised_text("Randomized Encounter Force Configuration (Beta)", true)
randomized_encounter_force_generation_section:set_description("This section contains options to enable and customize the new randomized encounter force generation system. This also includes enabling compatibility with many mods.\n\nYou do not need to load the save again for the changes to take effect.")
local second_page = mct_mod:create_settings_page("Randomized Encounter Force Configuration (Beta)", 2)
randomized_encounter_force_generation_section:assign_to_page(second_page)

--- Checkbox to enable compatibility with supported mods defined in shared/mct_settings.lua.
local enable_compatibility_with_supported_mods_checkbox = mct_mod:add_new_option("enable_compatibility_with_supported_mods", "checkbox")
enable_compatibility_with_supported_mods_checkbox:set_text("Enable compatibility with supported mods", true)
enable_compatibility_with_supported_mods_checkbox:set_tooltip_text("When enabled, the new randomized encounter force generation will use the supported mods. Refer to the Steam Workshop page for the list of supported mods.", true)
enable_compatibility_with_supported_mods_checkbox:set_is_global(true)
enable_compatibility_with_supported_mods_checkbox:set_default_value(false)
enable_compatibility_with_supported_mods_checkbox:set_assigned_section("randomized_encounter_force_generation_section")

--- Checkbox to restrict encounter force generation to only use modded units.
local use_only_modded_units_checkbox = mct_mod:add_new_option("use_only_modded_units", "checkbox")
use_only_modded_units_checkbox:set_text("Use only modded units for encounter forces", true)
use_only_modded_units_checkbox:set_tooltip_text("When enabled, the new randomized encounter force generation will only use modded units (vanilla units may be added if any of the supported mods overrode them).", true)
use_only_modded_units_checkbox:set_is_global(true)
use_only_modded_units_checkbox:set_default_value(false)
use_only_modded_units_checkbox:set_assigned_section("randomized_encounter_force_generation_section")

--- Dropdown to pick one of the three randomization difficulties.
local difficulty_dropdown = mct_mod:add_new_option("difficulty_dropdown", "dropdown")
difficulty_dropdown:set_text("Select randomization difficulty", true)
difficulty_dropdown:set_tooltip_text("Select the difficulty for the randomized encounter force generation. Note that this will be overridden by the basic progressive difficulty if enabled.", true)
difficulty_dropdown:add_dropdown_values({
    {key = "easy", text = "Easy"},
    {key = "medium", text = "Medium"},
    {key = "hard", text = "Hard"},
})
difficulty_dropdown:set_assigned_section("randomized_encounter_force_generation_section")

--- Basic progressive difficulty option (turn-based scaling).
local enable_basic_progressive_difficulty_checkbox = mct_mod:add_new_option("enable_basic_progressive_difficulty", "checkbox")
enable_basic_progressive_difficulty_checkbox:set_text("Enable basic progressive difficulty using turn numbers", true)
enable_basic_progressive_difficulty_checkbox:set_tooltip_text("When enabled, the difficulty will increase based on the turn number starting from easy to hard.", true)
enable_basic_progressive_difficulty_checkbox:set_is_global(true)
enable_basic_progressive_difficulty_checkbox:set_default_value(false)
enable_basic_progressive_difficulty_checkbox:set_assigned_section("randomized_encounter_force_generation_section")

--- Sliders for the turn-number thresholds at which the progressive difficulty steps up.
local turn_number_from_easy_to_medium_slider = mct_mod:add_new_option("turn_number_from_easy_to_medium_slider", "slider")
turn_number_from_easy_to_medium_slider:set_text("Turn number at which difficulty increases from easy to medium", true)
turn_number_from_easy_to_medium_slider:set_tooltip_text("Set the turn number at which the difficulty increase from easy to medium.", true)
turn_number_from_easy_to_medium_slider:set_is_global(true)
turn_number_from_easy_to_medium_slider:slider_set_min_max(2, 50)
turn_number_from_easy_to_medium_slider:slider_set_precision(1)
turn_number_from_easy_to_medium_slider:slider_set_step_size(1, 1)
turn_number_from_easy_to_medium_slider:set_default_value(15)
turn_number_from_easy_to_medium_slider:set_assigned_section("randomized_encounter_force_generation_section")
local turn_number_from_medium_to_hard_slider = mct_mod:add_new_option("turn_number_from_medium_to_hard_slider", "slider")
turn_number_from_medium_to_hard_slider:set_text("Turn number at which difficulty increases from medium to hard", true)
turn_number_from_medium_to_hard_slider:set_tooltip_text("Set the turn number at which the difficulty increase from medium to hard.", true)
turn_number_from_medium_to_hard_slider:set_is_global(true)
turn_number_from_medium_to_hard_slider:slider_set_min_max(3, 100)
turn_number_from_medium_to_hard_slider:slider_set_precision(1)
turn_number_from_medium_to_hard_slider:slider_set_step_size(1, 1)
turn_number_from_medium_to_hard_slider:set_default_value(25)
turn_number_from_medium_to_hard_slider:set_assigned_section("randomized_encounter_force_generation_section")

local slider_data = {
    {
        key = "min_tier_easy",
        title = "Min unit tier",
        tooltip = "Set the minimum unit tier allowed for the generated encounter force. Note that this can be reduced by 1 to the minimum of 1 by the system if there were no eligible units for that tier.",
        min = 1,
        max = 5,
        default_value = get_mct_settings().difficulties.easy.tiers[1],
    },
    {
        key = "max_tier_easy",
        title = "Max unit tier",
        tooltip = "Set the maximum unit tier allowed for the generated encounter force. Note that this can be increased by 1 to the maximum of 5 by the system if there were no eligible units for that tier.",
        min = 1,
        max = 5,
        default_value = get_mct_settings().difficulties.easy.tiers[2],
    },
    {
        key = "min_units_easy",
        title = "Min number of units in force",
        tooltip = "Set the minimum number of units for the generated encounter force.",
        min = 1,
        max = 20,
        default_value = get_mct_settings().difficulties.easy.min_units,
    },
    {
        key = "max_units_easy",
        title = "Max number of units in force",
        tooltip = "Set the maximum number of units for the generated encounter force.",
        min = 1,
        max = 20,
        default_value = get_mct_settings().difficulties.easy.max_units,
    },
    {
        key = "min_unit_experience_amount_easy",
        title = "Min unit rank",
        tooltip = "Set the minimum rank of each unit in the generated encounter force.",
        min = 1,
        max = 9,
        default_value = get_mct_settings().difficulties.easy.unit_experience_amount[1],
    },
    {
        key = "max_unit_experience_amount_easy",
        title = "Max unit rank",
        tooltip = "Set the maximum rank of each unit in the generated encounter force.",
        min = 1,
        max = 9,
        default_value = get_mct_settings().difficulties.easy.unit_experience_amount[2],
    },
    {
        key = "min_lord_level_range_easy",
        title = "Min lord level range",
        tooltip = "Set the minimum level of the lord for the generated encounter force.",
        min = 1,
        max = 30,
        default_value = get_mct_settings().difficulties.easy.lord_level_range[1],
    },
    {
        key = "max_lord_level_range_easy",
        title = "Max lord level range",
        tooltip = "Set the maximum level of the lord for the generated encounter force.",
        min = 1,
        max = 30,
        default_value = get_mct_settings().difficulties.easy.lord_level_range[2],
    },
    {
        key = "min_tier_medium",
        title = "Min unit tier",
        tooltip = "Set the minimum unit tier allowed for the generated encounter force. Note that this can be reduced by 1 to the minimum of 1 by the system if there were no eligible units for that tier.",
        min = 1,
        max = 5,
        default_value = get_mct_settings().difficulties.medium.tiers[1],
    },
    {
        key = "max_tier_medium",
        title = "Max unit tier",
        tooltip = "Set the maximum unit tier allowed for the generated encounter force. Note that this can be increased by 1 to the maximum of 5 by the system if there were no eligible units for that tier.",
        min = 1,
        max = 5,
        default_value = get_mct_settings().difficulties.medium.tiers[2],
    },
    {
        key = "min_units_medium",
        title = "Min number of units in force",
        tooltip = "Set the minimum number of units for the generated encounter force.",
        min = 1,
        max = 20,
        default_value = get_mct_settings().difficulties.medium.min_units,
    },
    {
        key = "max_units_medium",
        title = "Max number of units in force",
        tooltip = "Set the maximum number of units for the generated encounter force.",
        min = 1,
        max = 20,
        default_value = get_mct_settings().difficulties.medium.max_units,
    },
    {
        key = "min_unit_experience_amount_medium",
        title = "Min unit rank",
        tooltip = "Set the minimum rank of each unit in the generated encounter force.",
        min = 1,
        max = 9,
        default_value = get_mct_settings().difficulties.medium.unit_experience_amount[1],
    },
    {
        key = "max_unit_experience_amount_medium",
        title = "Max unit rank",
        tooltip = "Set the maximum rank of each unit in the generated encounter force.",
        min = 1,
        max = 9,
        default_value = get_mct_settings().difficulties.medium.unit_experience_amount[2],
    },
    {
        key = "min_lord_level_range_medium",
        title = "Min lord level range",
        tooltip = "Set the minimum level of the lord for the generated encounter force.",
        min = 1,
        max = 30,
        default_value = get_mct_settings().difficulties.medium.lord_level_range[1],
    },
    {
        key = "max_lord_level_range_medium",
        title = "Max lord level range",
        tooltip = "Set the maximum level of the lord for the generated encounter force.",
        min = 1,
        max = 30,
        default_value = get_mct_settings().difficulties.medium.lord_level_range[2],
    },
    {
        key = "min_tier_hard",
        title = "Min unit tier",
        tooltip = "Set the minimum unit tier allowed for the generated encounter force. Note that this can be reduced by 1 to the minimum of 1 by the system if there were no eligible units for that tier.",
        min = 1,
        max = 5,
        default_value = get_mct_settings().difficulties.hard.tiers[1],
    },
    {
        key = "max_tier_hard",
        title = "Max unit tier",
        tooltip = "Set the maximum unit tier allowed for the generated encounter force. Note that this can be increased by 1 to the maximum of 5 by the system if there were no eligible units for that tier.",
        min = 1,
        max = 5,
        default_value = get_mct_settings().difficulties.hard.tiers[2],
    },
    {
        key = "min_units_hard",
        title = "Min number of units in force",
        tooltip = "Set the minimum number of units for the generated encounter force.",
        min = 1,
        max = 20,
        default_value = get_mct_settings().difficulties.hard.min_units,
    },
    {
        key = "max_units_hard",
        title = "Max number of units in force",
        tooltip = "Set the maximum number of units for the generated encounter force.",
        min = 1,
        max = 20,
        default_value = get_mct_settings().difficulties.hard.max_units,
    },
    {
        key = "min_unit_experience_amount_hard",
        title = "Min unit rank",
        tooltip = "Set the minimum rank of each unit in the generated encounter force.",
        min = 1,
        max = 9,
        default_value = get_mct_settings().difficulties.hard.unit_experience_amount[1],
    },
    {
        key = "max_unit_experience_amount_hard",
        title = "Max unit rank",
        tooltip = "Set the maximum rank of each unit in the generated encounter force.",
        min = 1,
        max = 9,
        default_value = get_mct_settings().difficulties.hard.unit_experience_amount[2],
    },
    {
        key = "min_lord_level_range_hard",
        title = "Min lord level range",
        tooltip = "Set the minimum level of the lord for the generated encounter force.",
        min = 1,
        max = 30,
        default_value = get_mct_settings().difficulties.hard.lord_level_range[1],
    },
    {
        key = "max_lord_level_range_hard",
        title = "Max lord level range",
        tooltip = "Set the maximum level of the lord for the generated encounter force.",
        min = 1,
        max = 30,
        default_value = get_mct_settings().difficulties.hard.lord_level_range[2],
    },
}

--- Create one collapsible section per difficulty.
for _, difficulty in ipairs({"easy", "medium", "hard"}) do
    local difficulty_section = mct_mod:add_new_section("difficulty_" .. difficulty .. "_section")
    difficulty_section:set_localised_text("Randomization Difficulty Settings: " .. difficulty, true)
    difficulty_section:set_description("This section contains options for the random generation difficulty.\n\nYou do not need to load the save again for the changes to take effect.", true)
    difficulty_section:set_is_collapsible(true)
    difficulty_section:set_visibility(false)
    difficulty_section:assign_to_page(second_page)
end

--- Append per-difficulty min/max limit slider entries to slider_data for each ordered limit key.
for _, difficulty in ipairs({"easy", "medium", "hard"}) do
    for _, limit_key in ipairs(get_mct_settings().ordered_slider_keys) do
        table.insert(slider_data, {
            key = "min_limit_" .. limit_key .. "_" .. difficulty,
            title = "Min random value for " .. limit_key .. " copies",
            tooltip = "Set the minimum value of the number generation to determine how many copies of a unit is added to the force per iteration. Note the amount is randomly selected from the range of the min and max.",
            min = 0,
            max = 10,
            default_value = get_mct_settings().difficulties[difficulty].limits[limit_key][1],
        })

        table.insert(slider_data, {
            key = "max_limit_" .. limit_key .. "_" .. difficulty,
            title = "Max random value for " .. limit_key .. " copies",
            tooltip = "Set the maximum value of the number generation to determine how many copies of a unit is added to the force per iteration. Note the amount is randomly selected from the range of the min and max.",
            min = 0,
            max = 10,
            default_value = get_mct_settings().difficulties[difficulty].limits[limit_key][2],
        })
    end
end

--- Materialize the actual slider options from slider_data, scoped per difficulty section.
--- ipairs is required here so the sliders appear in the order they were inserted.
for _, difficulty in ipairs({"easy", "medium", "hard"}) do
    out("DEBUG - creating slider options for difficulty: " .. difficulty)
    for _, data in ipairs(slider_data) do
        if data.key:find("_" .. difficulty) then
            out("DEBUG - creating slider option: " .. data.key)
            local slider = mct_mod:add_new_option(data.key, "slider")
            slider:set_text(data.title, true)
            slider:set_tooltip_text(data.tooltip, true)
            slider:set_is_global(true)
            slider:slider_set_min_max(data.min, data.max)
            slider:slider_set_precision(0)
            slider:slider_set_step_size(1, 0)
            slider:set_default_value(data.default_value)
            slider:set_assigned_section("difficulty_" .. difficulty .. "_section")
        end
    end
end

--- Tell each difficulty section to sort options by insertion index now that all sliders are created.
for _, difficulty in ipairs({"easy", "medium", "hard"}) do
    local difficulty_section = mct_mod:get_section_by_key("difficulty_" .. difficulty .. "_section")
    difficulty_section:set_option_sort_function("index_sort")
end

--- Section + checkboxes for enabling/disabling individual factions in the randomized encounter force generation.
local faction_overrides_section = mct_mod:add_new_section("faction_overrides_section")
faction_overrides_section:set_localised_text("Faction Overrides", true)
faction_overrides_section:set_description("This section contains options to override the faction for the randomized encounter force generation.\n\nIt is okay to leave the modded factions enabled as they will not be included in the randomized encounter force generation if their respective mods are not loaded as well.")
faction_overrides_section:assign_to_page(second_page)

--- Master checkbox to enable/disable every faction at once.
local enable_all_faction_checkboxes = mct_mod:add_new_option("enable_all_faction_checkboxes", "checkbox")
enable_all_faction_checkboxes:set_text("Enable all factions", true)
enable_all_faction_checkboxes:set_tooltip_text("When enabled, all factions will be allowed for the randomized encounter force generation.", true)
enable_all_faction_checkboxes:set_is_global(true)
enable_all_faction_checkboxes:set_default_value(true)
enable_all_faction_checkboxes:set_assigned_section("faction_overrides_section")

--- Per-faction checkboxes.
local faction_checkbox_ids = get_faction_checkbox_ids()
for _, faction in ipairs(get_faction_mapping()) do
    local key = "faction_" .. faction.key
    local checkbox = mct_mod:add_new_option(key, "checkbox")
    checkbox:set_text(faction.text, true)
    checkbox:set_tooltip_text("Enable this faction for the randomized encounter force generation.", true)
    checkbox:set_is_global(true)
    checkbox:set_default_value(true)
    checkbox:set_assigned_section("faction_overrides_section")
    table.insert(faction_checkbox_ids, faction.key)
end

--- When the master "enable all factions" checkbox is toggled, lock/unlock every individual faction checkbox to match.
core:add_listener(
    "lock_all_faction_checkboxes",
    "MctOptionSelectedSettingSet",
    function(context)
        return context:option():get_key() == "enable_all_faction_checkboxes"
    end,
    function(context)
        local option = context:option()
        local mct_mod = option:get_mod()

        --- Read the live UI value via context:setting(). get_finalized_setting() is not updated until the UI is closed.
        local new_checkbox_val = context:setting()

        for i = 1, #faction_checkbox_ids do
            local i_option_key = faction_checkbox_ids[i]
            local key = "faction_" .. i_option_key
            local i_option = mct_mod:get_option_by_key(key)
            i_option:set_locked(new_checkbox_val)
        end
    end,
    true
)

out("DEBUG - UI elements creation completed.")

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Check which supported mods are loaded

out("DEBUG - Checking enabled supported mods...")

--- Parse used_mods.txt to discover which of the supported mods are present in the user's load order.
local used_mods = io.open("used_mods.txt", "r")
if used_mods then
    for line in used_mods:lines() do
        local mod_name = line:match('mod%s+"([^"]+)%.pack"')
        if mod_name then
            for _, supported_mod in ipairs(get_supported_mods()) do
                if mod_name == supported_mod then
                    table.insert(get_mct_settings().enabled_mods, mod_name)
                end
            end
        end
    end
    used_mods:close()
end

out("DEBUG - enabled supported mods: ")
for _, mod in ipairs(get_mct_settings().enabled_mods) do
    out("DEBUG - " .. mod)
end

--- TODO: If a MCT List is ever implemented, we can uncomment this. For now, it would display some of the items but it will put everything else into a tooltip when it gets too long and the tooltip itself will overflow vertically past the screen.
--- local enabled_supported_mods_section = mct_mod:add_new_section("enabled_supported_mods_section")
--- enabled_supported_mods_section:set_localised_text("Enabled Mods that are Supported", true)
--- enabled_supported_mods_section:set_description("This section lists all the mods that are currently enabled in your load order and supported by the new randomized encounter force generation system.")
--- enabled_supported_mods_section:assign_to_page(second_page)

--- -- Create the list of enabled mods that are supported.
--- out("DEBUG - enabled_mods: " .. table.concat(get_mct_settings().enabled_mods, ", "))
--- local key = "dummy_enabled_mod_compatibility_list"
--- local dummy_option = mct_mod:add_new_option(key, "dummy")
--- local text = "Enabled Mods that are Supported:\n"
--- if get_mct_settings().enabled_mods and #get_mct_settings().enabled_mods > 0 then
---     -- Add a new line for each mod.
---     for _, mod in ipairs(get_mct_settings().enabled_mods) do
---         text = text .. "\n" .. mod
---     end
--- else
---     text = text .. "\n" .. "None of the currently enabled mods are supported by this system."
--- end
--- dummy_option:set_text(text, true)
--- dummy_option:set_assigned_section("enabled_supported_mods_section")
