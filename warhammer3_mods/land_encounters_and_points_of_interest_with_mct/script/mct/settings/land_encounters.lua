--- MCT anchor file for the Land Encounters and Points of Interest mod. Auto-discovered by MCT,
--- this declares every settings option, the layout of pages/sections, and the listeners that
--- enforce inter-option constraints (at-least-one rules, master/child checkbox locking).
--- Option keys never change, so players keep their saved settings. Labels, sections and pages are free to move.

require("script/land_encounters/core/mct")

local archetypes = require("script/land_encounters/configs/archetypes")
local smithy_data = require("script/land_encounters/configs/smithy_data")
local tavern_data = require("script/land_encounters/configs/tavern_data")
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

--- Adds a global slider whose default is the matching `mct_settings` field, with "Default is N." added to its tooltip.
--- @param key string The option key, also the `mct_settings` field it fills.
--- @param section_key string The section it sits in.
--- @param text string The label.
--- @param tooltip string The tooltip, without the default.
--- @param range table { min, max, step, precision }.
--- @returns table The MCT option.
local function add_setting_slider(key, section_key, text, tooltip, range)
    local default = get_mct_settings()[key]
    --- A slider whose label ends in % holds a percentage, so its default says so.
    local unit = text:find("%%$") and "%" or ""
    return add_slider(key, section_key, text, tooltip .. " Default is " .. default .. unit .. ".", range, default)
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
local taverns_page = mct_mod:create_settings_page("Taverns", 1)
local boons_page = mct_mod:create_settings_page("Boons and Curses", 1)
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
    "Some encounter battles let you attack with allied reinforcements available. Easier. Battlefield battles always use it when it is enabled.", true)

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
add_slider("battle_modifier_chance", "battle_events_section", "Battle modifier chance %",
    "Chance that a fight (a battle spot or a Tower floor) carries 1 to 3 battle modifiers, shown on its dilemma. Harmful ones raise the "
    .. "victory gold, helpful ones lower it. Default is " .. get_mct_settings().battle_modifier_chance .. ".", { 0, 25, 1, 0 },
    get_mct_settings().battle_modifier_chance)

add_guide_section("battle_spots", "Guide: Battle Spots", encounters_page, mct_guides.battle_spots_text(), true)
add_guide_section("treasure_spots", "Guide: Treasure Sites", encounters_page, mct_guides.treasure_spots_text(), true)
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
difficulty_dropdown:set_default_value("progressive")
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
add_setting_slider("tower_gold_percent", "towers_section", "Floor gold %", "Scales the gold each won floor adds to the haul.", { 25, 300, 5, 0 })
add_setting_slider("tower_enemy_percent", "towers_section", "Floor enemy strength %",
    "Scales the gold each floor's enemy army is bought with. Higher means stronger armies.", { 25, 300, 5, 0 })
add_setting_slider("tower_offers_per_floor", "towers_section", "Offers per floor",
    "Most offers shown after each won floor, beside Climb and Leave. Capped so the dilemma fits the screen.", { 1, 6, 1, 0 })
add_setting_slider("tower_hidden_floor_chance", "towers_section", "Hidden Floor offer chance %",
    "Chance the Hidden Floor offer can show up after a floor. At 0 it never does.", { 0, 100, 5, 0 })

add_guide_section("towers", "Guide: How Towers Work", towers_page, mct_guides.towers_text(), true)
for _, offer_section in ipairs(mct_guides.tower_offer_sections()) do
    add_guide_section("tower_" .. offer_section.key, "Offers: " .. offer_section.title, towers_page, offer_section.text, false)
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Smithies page

add_section("smithies_section", "Smithies", smithies_page)

add_checkbox("enable_smithies", "smithies_section", "Enable Smithies",
    "Places Smithies on the map. A lord can claim one for free items and a steady tribute. When off, every Smithy is removed and nothing "
    .. "happens at them until they return. Requires loading the save again to take effect.", get_mct_settings().enable_smithies)
add_slider("smithy_cooldown", "smithies_section", "Smithy cooldown (turns)",
    "Turns a level 3 forge cools after a free pick. Level 2 adds " .. smithy_data.levels[2].cooldown_offset .. " turns and level 1 adds "
    .. smithy_data.levels[1].cooldown_offset .. ". Default is " .. get_mct_settings().smithy_cooldown .. ".", { 1, smithy_data.cooldown_slider_max, 1, 0 },
    get_mct_settings().smithy_cooldown)
add_setting_slider("smithy_price_percent", "smithies_section", "Smithy prices %",
    "Scales the price of commissions, legendary commissions and forge upgrades. Generous Donations keep their price.", { 25, 300, 5, 0 })
add_setting_slider("smithy_tribute_percent", "smithies_section", "Tribute interval %",
    "Scales the turns between tribute items for a player's Smithy. At 100, tribute comes every " .. smithy_data.levels[1].tribute_interval
    .. " turns at forge level 1, " .. smithy_data.levels[2].tribute_interval .. " at level 2 and " .. smithy_data.levels[3].tribute_interval
    .. " at level 3. Higher means rarer tribute.", { 25, 300, 5, 0 })
add_setting_slider("smithy_ai_takeover_chance", "smithies_section", "AI takeover chance %",
    "Chance an AI army at war with a Smithy's AI owner takes it when it walks onto it.", { 0, 100, 1, 0 })
add_setting_slider("smithy_ai_upgrade_chance", "smithies_section", "AI upgrade chance %",
    "Chance each round that an AI owner upgrades its Smithy, rolled only while it holds twice the price.", { 0, 20, 1, 0 })

add_guide_section("smithy", "Guide: The Smithy", smithies_page, mct_guides.smithy_text(), true)

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Taverns page

add_section("taverns_section", "Taverns", taverns_page)

add_checkbox("enable_taverns", "taverns_section", "Enable Taverns",
    "Places Taverns on the map with a mercenary hall, a contract board and a bar. When off, every Tavern is removed and its takeovers pause. "
    .. "Requires loading the save again to take effect.", get_mct_settings().enable_taverns)
add_setting_slider("tavern_contract_turns", "taverns_section", "Contract deadline (turns)",
    "Turns to finish a bounty or marked spot contract before it fails. Culls get " .. tavern_data.contracts.cull_extra_turns .. " more turns and "
    .. "each quest step " .. tavern_data.contracts.chain.step_extra_turns .. " more.", { 3, 30, 1, 0 })
add_setting_slider("tavern_hall_restock", "taverns_section", "Mercenary restock (turns)",
    "Turns between new stock in a Tavern's mercenary hall. A Tavern that levels up restocks at once.", { 1, 20, 1, 0 })
add_setting_slider("tavern_hire_markup", "taverns_section", "Mercenary markup (gold)",
    "Gold a hire costs over its recruitment cost. A Regiment of Renown costs " .. tavern_data.hall.renown_extra .. " more on top.", { 0, 5000, 100, 0 })
add_setting_slider("tavern_hires_per_visit", "taverns_section", "Hires per visit", "How many units a faction can hire in the mercenary hall per visit.",
    { 1, 5, 1, 0 })
add_setting_slider("tavern_cooldown", "taverns_section", "Bar and hall cooldown (turns)",
    "Turns the bar stays closed to a faction after it takes an offer there, and the hall after it hires.", { 1, 15, 1, 0 })
add_setting_slider("tavern_penalty_percent", "taverns_section", "Failed contract surcharge %",
    "How much more every Guild Tavern charges a faction after it fails or drops a contract. 0 turns the surcharge off.", { 0, 100, 5, 0 })
add_setting_slider("tavern_penalty_turns", "taverns_section", "Failed contract surcharge (turns)", "How long the Guild's surcharge lasts.", { 1, 30, 1, 0 })
add_setting_slider("tavern_ai_takeover_chance", "taverns_section", "AI takeover chance %",
    "Chance an AI army at war with a Tavern's AI owner takes it when it walks onto it.", { 0, 100, 1, 0 })
add_setting_slider("tavern_ai_upgrade_chance", "taverns_section", "AI upgrade chance %",
    "Chance each round that an AI owner upgrades its Tavern, rolled only while it holds twice the price.", { 0, 20, 1, 0 })

add_guide_section("taverns", "Guide: The Tavern", taverns_page, mct_guides.taverns_text(), true)

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Boons and Curses page

add_section("boons_section", "Boons and Curses", boons_page)

add_checkbox("enable_boons", "boons_section", "Enable boons and curses",
    "Lords gain lasting boons, which grow as they win battles, and curses, which get worse every few turns until they are cleansed. When off, "
    .. "no lord gains a new one, and the ones already carried stay as they are.", get_mct_settings().enable_boons)
add_setting_slider("boon_slots", "boons_section", "Boon slots", "How many boons a lord can carry. A lord with every slot full chooses which "
    .. "boon to give up for a new one.", { 1, 5, 1, 0 })
add_setting_slider("boon_win_chance", "boons_section", "Boon after a hard win %", "Chance a lord who wins a hard LEAPOI fight, or one with "
    .. "battle modifiers, gains a boon.", { 0, 100, 1, 0 })
add_setting_slider("curse_loss_chance", "boons_section", "Curse after a loss %", "Chance a lord who loses a LEAPOI fight, or fails a Tavern "
    .. "contract, gains a curse.", { 0, 100, 1, 0 })
add_setting_slider("linger_chance", "boons_section", "Lingering modifier %", "Chance each battle modifier of a fight leaves its own boon or "
    .. "curse on the lord, e.g. Blood Moon leaving Bloodsworn.", { 0, 100, 1, 0 })
add_setting_slider("curse_slots", "boons_section", "Curse slots", "How many curses a lord can carry. A new curse on a lord with every slot "
    .. "full makes their mildest curse worse instead.", { 1, 5, 1, 0 })

add_guide_section("boons", "Guide: Boons and Curses", boons_page, mct_guides.boons_text(), true)

--- Builds every guide's text again and puts it on its section. The guides read game text, which a campaign does not have ready when this
--- file first runs, so they are rebuilt once MCT has started and each time its panel opens, before a page is drawn.
local function refresh_guides()
    local texts = {
        battle_spots = mct_guides.battle_spots_text(),
        treasure_spots = mct_guides.treasure_spots_text(),
        towers = mct_guides.towers_text(),
        smithy = mct_guides.smithy_text(),
        taverns = mct_guides.taverns_text(),
        boons = mct_guides.boons_text(),
    }
    for _, offer_section in ipairs(mct_guides.spot_offer_sections()) do texts["spot_" .. offer_section.key] = offer_section.text end
    for _, offer_section in ipairs(mct_guides.tower_offer_sections()) do texts["tower_" .. offer_section.key] = offer_section.text end
    for key, text in pairs(texts) do
        local section = mct_mod:get_section_by_key("guide_" .. key .. "_section")
        if section then section:set_description(text) end
    end
end
for _, event in ipairs({ "MctInitialized", "MctPanelOpened" }) do
    core:add_listener("leapoi_refresh_guides_" .. event, event, true, refresh_guides, true)
end

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
