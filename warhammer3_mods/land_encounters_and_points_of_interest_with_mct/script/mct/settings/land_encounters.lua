--- MCT anchor file for the Land Encounters and Points of Interest mod. Auto-discovered by MCT,
--- this declares every settings option, the layout of pages/sections, and the listeners that
--- enforce inter-option constraints (at-least-one rules, master/child checkbox locking).
--- Option keys never change, so players keep their saved settings. Labels, sections and pages are free to move.

require("script/land_encounters/core/mct")

local archetypes = require("script/land_encounters/configs/archetypes")
local smithy_data = require("script/land_encounters/configs/smithy_data")
local tower_data = require("script/land_encounters/configs/tower_data")
local mct_guides = require("script/land_encounters/core/mct_guides")

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
--- Helpers

--- Runs a lock recompute again once MCT has loaded the saved settings and whenever the panel opens. Loading the saved settings resets every
--- option's lock, so locks set while this file loads do not survive on their own.
--- @param listener_name string A unique prefix for the MCT listeners.
--- @param recompute function Sets the locks from the current settings.
local function reapply_after_mct_load(listener_name, recompute)
    for _, event in ipairs({ "MctInitialized", "MctPanelOpened" }) do
        core:add_listener(listener_name .. "_" .. event, event, true, function() recompute() end, true)
    end
end

--- Keeps at least one checkbox of a group enabled by locking whichever one is the last checked. Recomputes after any toggle in the group.
--- @param option_keys table The checkbox option keys in the group.
--- @param listener_name string A unique name for the MCT listener.
local function lock_last_enabled_option(option_keys, listener_name)
    local function recompute_locks()
        local enabled_count = 0
        for _, key in ipairs(option_keys) do
            if mct_mod:get_option_by_key(key):get_selected_setting() then
                enabled_count = enabled_count + 1
            end
        end
        for _, key in ipairs(option_keys) do
            local option = mct_mod:get_option_by_key(key)
            option:set_locked(enabled_count == 1 and option:get_selected_setting())
        end
    end

    recompute_locks()
    reapply_after_mct_load(listener_name, recompute_locks)

    core:add_listener(
        listener_name,
        "MctOptionSelectedSettingSet",
        function(context)
            local key = context:option():get_key()
            for _, option_key in ipairs(option_keys) do
                if key == option_key then return true end
            end
            return false
        end,
        function(_)
            recompute_locks()
        end,
        true
    )
end

--- Locks a set of options whenever a controlling option's value makes them do nothing. Applies on load, once MCT has loaded the saved settings,
--- when the panel opens and after every change to the controller.
--- @param option_keys table The option keys to lock.
--- @param controller_key string The option key whose value decides the lock.
--- @param is_locked function Takes the controller's value and returns true when the options should be locked.
--- @param listener_name string A unique name for the MCT listener.
local function lock_options_by(option_keys, controller_key, is_locked, listener_name)
    local function apply(value)
        for _, key in ipairs(option_keys) do
            mct_mod:get_option_by_key(key):set_locked(is_locked(value))
        end
    end

    local function apply_current()
        apply(mct_mod:get_option_by_key(controller_key):get_selected_setting())
    end

    apply_current()
    reapply_after_mct_load(listener_name, apply_current)

    core:add_listener(
        listener_name,
        "MctOptionSelectedSettingSet",
        function(context)
            return context:option():get_key() == controller_key
        end,
        function(context)
            --- Read the live UI value via context:setting(). get_finalized_setting() is not updated until the UI is closed.
            apply(context:setting())
        end,
        true
    )
end

--- Adds a section to a page.
--- @param key string The section key.
--- @param title string The section title.
--- @param page table The MCT settings page.
--- @param description string|nil Optional text shown under the title.
--- @param collapsed boolean|nil True for a collapsible section that starts closed, false for one that starts open, nil for a fixed one.
--- @returns table The MCT section.
local function add_section(key, title, page, description, collapsed)
    local section = mct_mod:add_new_section(key)
    section:set_localised_text(title, true)
    if description then section:set_description(description) end
    section:assign_to_page(page)
    if collapsed ~= nil then
        section:set_is_collapsible(true)
        section:set_visibility(not collapsed)
    end
    return section
end

--- Adds a collapsible, read-only guide section to a page. MCT skips a section with no options, so each guide holds one hidden dummy option.
--- @param key string The guide key. The section is "guide_<key>_section" and its dummy option "guide_<key>".
--- @param title string The section title.
--- @param page table The MCT settings page.
--- @param text string The guide text.
--- @param is_open boolean True to start the section open.
local function add_guide_section(key, title, page, text, is_open)
    local section_key = "guide_" .. key .. "_section"
    add_section(section_key, title, page, text, not is_open)
    local dummy = mct_mod:add_new_option("guide_" .. key, "dummy")
    dummy:set_assigned_section(section_key)
    dummy:set_uic_visibility(false, false)
end

--- Adds a global checkbox to a section.
--- @param key string The option key.
--- @param section_key string The section it sits in.
--- @param text string The label.
--- @param tooltip string The tooltip.
--- @param default boolean The default value.
--- @returns table The MCT option.
local function add_checkbox(key, section_key, text, tooltip, default)
    local checkbox = mct_mod:add_new_option(key, "checkbox")
    checkbox:set_text(text, true)
    checkbox:set_tooltip_text(tooltip, true)
    checkbox:set_is_global(true)
    checkbox:set_default_value(default)
    checkbox:set_assigned_section(section_key)
    return checkbox
end

--- Adds a global slider to a section.
--- @param key string The option key.
--- @param section_key string The section it sits in.
--- @param text string The label.
--- @param tooltip string The tooltip.
--- @param range table { min, max, step, precision }.
--- @param default number The default value.
--- @returns table The MCT option.
local function add_slider(key, section_key, text, tooltip, range, default)
    local slider = mct_mod:add_new_option(key, "slider")
    slider:set_text(text, true)
    slider:set_tooltip_text(tooltip, true)
    slider:set_is_global(true)
    slider:slider_set_min_max(range[1], range[2])
    slider:slider_set_precision(range[4])
    slider:slider_set_step_size(range[3], range[4])
    slider:set_default_value(default)
    slider:set_assigned_section(section_key)
    return slider
end

--- Locks every child checkbox while its "enable all" master checkbox is on.
--- @param master_key string The master checkbox key.
--- @param prefix string The child option key prefix, e.g. "faction_".
--- @param ids table The child ids appended to `prefix`.
--- @param listener_name string A unique name for the MCT listener.
local function lock_children_of_master(master_key, prefix, ids, listener_name)
    local child_keys = {}
    for _, id in ipairs(ids) do child_keys[#child_keys + 1] = prefix .. id end
    lock_options_by(child_keys, master_key, function(value) return value end, listener_name)
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Pages

--- Pages in menu order. MCT's own default "Settings" page is replaced by General, so new sections land there unless assigned elsewhere.
local mct_default_page = mct_mod:get_default_settings_page()
local general_page = mct_mod:create_settings_page("General", 1)
local encounters_page = mct_mod:create_settings_page("Encounters", 1)
local forces_page = mct_mod:create_settings_page("Enemy Forces", 2)
local towers_page = mct_mod:create_settings_page("Towers", 1)
local smithies_page = mct_mod:create_settings_page("Smithies", 1)
if mct_default_page then
    mct_mod:set_default_settings_page(general_page)
    mct_default_page:remove()
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- General page

add_section("configuration_section", "General", general_page)

add_slider("spawn_percentage", "configuration_section", "Active encounter share",
    "Share of all points on the map that can hold an active encounter at once. Default is 0.75 (75%).", { 0.10, 1.00, 0.05, 2 }, 0.75)
add_slider("battle_chance", "configuration_section", "Battle chance %",
    "Chance that an encounter spot starts a battle. The rest give treasure. Default is 70.", { 0, 100, 5, 0 }, get_mct_settings().battle_chance)
add_checkbox("ready_notices", "configuration_section", "Ready notices",
    "Tells you when a Smithy you hold, or a Tower you last delved, is ready again. The notice names the region.", get_mct_settings().ready_notices)

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Encounters page

add_section("battle_engagement_section", "Battle Engagement", encounters_page,
    "Which battle types encounter battles can use. At least one stays on.")

add_checkbox("intervention_ambush", "battle_engagement_section", "Ambush battles",
    "Some encounter battles are ambushes: the enemy army is hidden and the battle cannot be retreated from before it starts. Harder. Nascent "
    .. "Rebellion and Surprise Attack battles always use it when it is enabled.", false)
add_checkbox("intervention_interception", "battle_engagement_section", "Interception battles",
    "Encounter battles are interceptions: the enemy army is visible and the battle cannot be declined from the dilemma, but standard battle "
    .. "mechanics apply. This is the default.", true)
add_checkbox("intervention_allied_reinforcements", "battle_engagement_section", "Allied reinforcement battles",
    "Some encounter battles let you attack with allied reinforcements available. Easier. Battlefield battles always use it when it is enabled.", false)

--- At-least-one enforcement so the user cannot turn every battle type off.
lock_last_enabled_option({ "intervention_ambush", "intervention_interception", "intervention_allied_reinforcements" }, "leapoi_intervention_at_least_one_enforcer")

add_section("encounter_skins_section", "Encounter Skins", encounters_page,
    "Each encounter skin can be left in or out of the random rotation. Takes effect the next time the locations spawn.", true)

add_checkbox("enable_all_encounter_skins", "encounter_skins_section", "Enable all encounter skins",
    "Uses every encounter skin and locks the checkboxes below.", true)

--- Individual encounter skin checkboxes.
local encounter_checkbox_ids = get_encounter_checkbox_ids()
for _, encounter in ipairs(get_encounter_data()) do
    add_checkbox("encounter_" .. encounter.id, "encounter_skins_section", encounter.text, "Enable this encounter skin.", true)
    table.insert(encounter_checkbox_ids, encounter.id)
end
lock_children_of_master("enable_all_encounter_skins", "encounter_", encounter_checkbox_ids, "lock_all_encounter_checkboxes")

add_section("battle_events_section", "Battle Events", encounters_page, "Extra choices around encounter battles. Set a chance to 0 to turn it off.")

add_slider("pre_battle_chance", "battle_events_section", "Pre-battle event chance %",
    "Chance that a battle's dilemma also offers ways to tip the battle for gold, and missions that pay out if met. Default is "
    .. get_mct_settings().pre_battle_chance .. ".", { 0, 100, 5, 0 }, get_mct_settings().pre_battle_chance)
add_slider("spoils_chance", "battle_events_section", "Spoils event chance %",
    "Chance that winning an encounter battle opens a pick of spoils. Default is " .. get_mct_settings().spoils_chance .. ".", { 0, 100, 5, 0 },
    get_mct_settings().spoils_chance)

add_guide_section("battle_spots", "Guide: Battle Spots", encounters_page, mct_guides.battle_spots_text(), false)
add_guide_section("treasure_spots", "Guide: Treasure Sites", encounters_page, mct_guides.treasure_spots_text(), false)
for _, offer_section in ipairs(mct_guides.spot_offer_sections()) do
    add_guide_section("spot_" .. offer_section.key, "Offers: " .. offer_section.title, encounters_page, offer_section.text, false)
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Enemy Forces page

add_section("randomized_encounter_force_generation_section", "Enemy Forces", forces_page,
    "How encounter armies are built. Changes apply without loading the save again.")

add_checkbox("enable_compatibility_with_supported_mods", "randomized_encounter_force_generation_section", "Use supported mods' units",
    "Encounter armies can use units from the supported mods you have loaded. See the Steam Workshop page for the list.", false)
add_checkbox("use_only_modded_units", "randomized_encounter_force_generation_section", "Only modded units",
    "Encounter armies use only units from the supported mods (vanilla units may still appear where a supported mod overrides them). Needs "
    .. "Use supported mods' units.", false)
lock_options_by({ "use_only_modded_units" }, "enable_compatibility_with_supported_mods", function(value) return not value end, "leapoi_modded_units_lock")

--- Dropdown for the encounter difficulty. Progressive steps up by turn number.
local difficulty_dropdown = mct_mod:add_new_option("difficulty_dropdown", "dropdown")
difficulty_dropdown:set_text("Difficulty", true)
difficulty_dropdown:set_tooltip_text("Difficulty of encounter armies. Progressive starts on Easy and steps up at the turns set below.", true)
difficulty_dropdown:add_dropdown_values({
    {key = "easy", text = "Easy"},
    {key = "medium", text = "Medium"},
    {key = "hard", text = "Hard"},
    {key = "progressive", text = "Progressive"},
})
difficulty_dropdown:set_is_global(true)
difficulty_dropdown:set_default_value("easy")
difficulty_dropdown:set_assigned_section("randomized_encounter_force_generation_section")

add_slider("turn_number_from_easy_to_medium_slider", "randomized_encounter_force_generation_section", "Medium from turn",
    "With Progressive difficulty, the turn encounters step up from Easy to Medium.", { 2, 50, 1, 0 }, get_mct_settings().turn_number_from_easy_to_medium)
add_slider("turn_number_from_medium_to_hard_slider", "randomized_encounter_force_generation_section", "Hard from turn",
    "With Progressive difficulty, the turn encounters step up from Medium to Hard.", { 3, 100, 1, 0 }, get_mct_settings().turn_number_from_medium_to_hard)
lock_options_by({ "turn_number_from_easy_to_medium_slider", "turn_number_from_medium_to_hard_slider" }, "difficulty_dropdown",
    function(value) return value ~= "progressive" end, "leapoi_progressive_turns_lock")

add_slider("max_unit_copies", "randomized_encounter_force_generation_section", "Max copies of one unit",
    "Caps how many copies of the same unit an encounter army can have. Regiments of Renown are always limited to one.", { 1, 6, 1, 0 },
    get_mct_settings().max_unit_copies)

local archetypes_section = add_section("army_archetypes_section", "Army Archetypes", forces_page,
    "Each encounter army rolls one enabled archetype that its faction can field. Every archetype keeps a frontline and a ranged or support "
    .. "unit.\n\nFactions that cannot field any enabled archetype use Battle line.")

--- Tooltip for each archetype checkbox, keyed by archetype key.
local archetype_tooltips = {
    battle_line = "A balanced line of infantry, missile units, cavalry, monsters and artillery.",
    raiders = "Mostly cavalry and missile cavalry. Needs a faction with at least 3 cavalry-type units.",
    horde = "Many cheap infantry and missile units, aiming to fill the army.",
    elite = "Fewer, pricier units drawn from the top half of each role's prices.",
    monster_hunt = "Mostly monsters behind a small frontline. Needs a faction with at least 3 monster-type units.",
    siege = "Artillery and missile units behind a frontline. Needs a faction with at least 3 artillery units.",
}

local archetype_option_keys = {}
for _, archetype in ipairs(archetypes.list) do
    local key = "archetype_" .. archetype.key
    add_checkbox(key, "army_archetypes_section", archetype.text, archetype_tooltips[archetype.key], true)
    table.insert(archetype_option_keys, key)
end
archetypes_section:set_option_sort_function("index_sort")
lock_last_enabled_option(archetype_option_keys, "leapoi_archetype_at_least_one_enforcer")

add_section("faction_overrides_section", "Faction Overrides", forces_page,
    "Which factions encounter armies can come from. Modded factions can stay enabled: they are skipped when their mods are not loaded.", true)

add_checkbox("enable_all_faction_checkboxes", "faction_overrides_section", "Enable all factions",
    "Allows every faction and locks the checkboxes below.", true)

--- Per-faction checkboxes.
local faction_checkbox_ids = get_faction_checkbox_ids()
for _, faction in ipairs(get_faction_mapping()) do
    add_checkbox("faction_" .. faction.key, "faction_overrides_section", faction.text, "Allow this faction for encounter armies.", true)
    table.insert(faction_checkbox_ids, faction.key)
end
lock_children_of_master("enable_all_faction_checkboxes", "faction_", faction_checkbox_ids, "lock_all_faction_checkboxes")

--- Per-difficulty slider pairs. Each template makes a min and a max slider keyed "min_<field>_<difficulty>" / "max_<field>_<difficulty>".
--- `field` "limit_hero" keeps the older hero count keys so existing MCT settings carry over.
local difficulty_slider_templates = {
    {
        field = "budget",
        title = "gold budget",
        tooltip = "The encounter army spends a random amount of gold between the min and max on its units. The lord and heroes are free. A bigger budget buys more and pricier units, up to the 20 unit army cap.",
        min = 0,
        max = 40000,
        step = 500,
    },
    {
        field = "unit_experience_amount",
        title = "unit rank",
        tooltip = "The rank of each unit in the encounter army, picked randomly between the min and max.",
        min = 1,
        max = 9,
        step = 1,
    },
    {
        field = "lord_level_range",
        title = "lord level",
        tooltip = "The level of the encounter army's lord, picked randomly between the min and max.",
        min = 1,
        max = 30,
        step = 1,
    },
    {
        field = "limit_hero",
        title = "number of heroes",
        tooltip = "How many heroes join the encounter army. Heroes count toward the 20 unit army cap.",
        min = 0,
        max = 10,
        step = 1,
    },
}

--- One collapsed section per difficulty, holding the min and max slider of every template in template order.
for _, difficulty in ipairs(DIFFICULTY_KEYS) do
    local section_key = "difficulty_" .. difficulty .. "_section"
    local difficulty_section = add_section(section_key, "Difficulty: " .. difficulty:sub(1, 1):upper() .. difficulty:sub(2), forces_page,
        "Army settings for this difficulty. Changes apply without loading the save again.", true)

    local settings = get_mct_settings().difficulties[difficulty]
    for _, template in ipairs(difficulty_slider_templates) do
        local defaults = template.field == "limit_hero" and settings.limits.hero or settings[template.field]
        for bound_index, bound in ipairs({"min", "max"}) do
            add_slider(bound .. "_" .. template.field .. "_" .. difficulty, section_key, (bound == "min" and "Min " or "Max ") .. template.title,
                template.tooltip, { template.min, template.max, template.step, 0 }, defaults[bound_index])
        end
    end
    difficulty_section:set_option_sort_function("index_sort")
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Towers page

add_section("towers_section", "Towers", towers_page)

add_checkbox("enable_towers", "towers_section", "Enable Towers",
    "Places one tower per map zone that a lord can delve for gold, items and sworn units. Requires loading the save again to take effect.",
    get_mct_settings().enable_towers)
add_slider("tower_cooldown", "towers_section", "Tower cooldown (turns)",
    "Turns a tower stays closed after a delve ends, whether you left, cleared it or lost. Default is 5.", { 1, tower_data.longest_cooldown_message, 1, 0 },
    get_mct_settings().tower_cooldown)

add_guide_section("towers", "Guide: How Towers Work", towers_page, mct_guides.towers_text(), true)
for _, offer_section in ipairs(mct_guides.tower_offer_sections()) do
    add_guide_section("tower_" .. offer_section.key, "Offers: " .. offer_section.title, towers_page, offer_section.text, false)
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Smithies page

add_section("smithies_section", "Smithies", smithies_page)

add_checkbox("disable_smithies", "smithies_section", "Remove Smithies from the map",
    "Removes every Smithy from the map and pauses their tributes, takeovers and sieges. Takes effect the next time a save is loaded.", false)
add_slider("smithy_cooldown", "smithies_section", "Smithy cooldown (turns)",
    "Turns a level 3 forge cools after a free pick. Level 2 adds " .. smithy_data.levels[2].cooldown_offset .. " turns and level 1 adds "
    .. smithy_data.levels[1].cooldown_offset .. ". Default is " .. get_mct_settings().smithy_cooldown .. ".", { 1, smithy_data.cooldown_slider_max, 1, 0 },
    get_mct_settings().smithy_cooldown)

add_guide_section("smithy", "Guide: The Smithy", smithies_page, mct_guides.smithy_text(), true)

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
