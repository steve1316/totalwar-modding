--- MCT anchor for Kadon's Scrolls of Binding. MCT discovers this file and builds the settings page from it. The option keys here must
--- match `settings.DEFAULTS` and `settings.creature_option_key`, because the settings module reads them back.

local creatures = require("script/jvj_kadon/creatures")
local settings = require("script/jvj_kadon/settings")

--- Scroll type option keys. At least one must stay checked.
local SCROLL_TYPE_KEYS = { "allow_kin", "allow_bind" }

--- Mod description shown on the MCT mod page, adapted from the original WH2 Workshop description.
local MOD_DESCRIPTION = table.concat({
    "Each scroll is a magic item that lets its bearer summon a creature in battle. Over 40 creatures are available, giving factions"
        .. " access to beasts they could never recruit.",
    "Scrolls of Kin summon a creature that stays on the battlefield until it is killed. Scrolls of Binding summon a creature that suffers from"
        .. " Unbinding and dies after a time limit.",
    "Scrolls are found after won battles and completed missions. The settings here control how often they drop, who can find them, and which"
        .. " creatures appear.",
    "Original mod by JvJ.",
}, "\n\n")

--- The registered MCT mod.
local mct_mod = get_mct():register_mod(settings.MCT_MOD_KEY)

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Helpers

--- Adds a section with a title and an optional description.
--- @param key string Section key.
--- @param title string Section title.
--- @param description string|nil Section description.
local function add_section(key, title, description)
    local section = mct_mod:add_new_section(key)
    section:set_localised_text(title, true)
    if description then
        section:set_description(description)
    end
end

--- Adds a global checkbox to a section.
--- @param key string Option key.
--- @param section string Section key.
--- @param text string Label.
--- @param tooltip string|nil Hover text. MCT shows no tooltip icon when nil.
--- @param default boolean|nil Default value. Falls back to `settings.DEFAULTS[key]` when nil.
--- @returns table The created option.
local function add_checkbox(key, section, text, tooltip, default)
    local option = mct_mod:add_new_option(key, "checkbox")
    option:set_text(text, true)
    if tooltip then
        option:set_tooltip_text(tooltip, true)
    end
    option:set_is_global(true)
    if default == nil then
        default = settings.DEFAULTS[key]
    end
    option:set_default_value(default)
    option:set_assigned_section(section)
    return option
end

--- Adds a global 0-100 percent slider to the drops section.
--- @param key string Option key. Its default comes from `settings.DEFAULTS`.
--- @param text string Label.
--- @param tooltip string Hover text.
--- @returns table The created option.
local function add_percent_slider(key, text, tooltip)
    local option = mct_mod:add_new_option(key, "slider")
    option:set_text(text, true)
    option:set_tooltip_text(tooltip, true)
    option:set_is_global(true)
    option:slider_set_min_max(0, 100)
    option:slider_set_precision(0)
    option:slider_set_step_size(1, 0)
    option:set_default_value(settings.DEFAULTS[key])
    option:set_assigned_section("drops_section")
    return option
end

--- Adds the starting-scroll creature dropdown to the drops section: "(Random)" first, then every creature sorted by display name.
local function add_starting_creature_dropdown()
    local option = mct_mod:add_new_option("starting_scroll_creature", "dropdown")
    option:set_text("Starting scroll creature", true)
    option:set_tooltip_text("Which creature the faction leader's starting scroll summons. (Random) picks any enabled creature.", true)
    option:set_is_global(true)
    option:add_dropdown_value("random", "(Random)", "", true)
    local sorted = {}
    for _, creature in ipairs(creatures.list) do
        table.insert(sorted, creature)
    end
    table.sort(sorted, function(a, b) return a.name < b.name end)
    for _, creature in ipairs(sorted) do
        option:add_dropdown_value(creature.id, creatures.label(creature), "")
    end
    option:set_assigned_section("drops_section")
end

--- Adds a blank, control-less row to a section. MCT cuts off the bottom of a column's last row, so this pads the row above it.
--- @param key string Option key.
--- @param section string Section key.
local function add_spacer(key, section)
    local option = mct_mod:add_new_option(key, "dummy")
    option:set_text(" ", true)
    option:set_assigned_section(section)
end

--- Returns true when the context's option belongs to this mod and its key is in `keys`.
--- @param context table `MctOptionSelectedSettingSet` context.
--- @param keys table Option keys to match.
--- @returns boolean Whether the option matches.
local function is_own_option(context, keys)
    local option = context:option()
    if option:get_mod():get_key() ~= settings.MCT_MOD_KEY then
        return false
    end
    for _, key in ipairs(keys) do
        if option:get_key() == key then return true end
    end
    return false
end

--- Locks whichever scroll type is the only one still checked, so the player can never turn both off.
local function sync_scroll_type_locks()
    local checked = 0
    for _, key in ipairs(SCROLL_TYPE_KEYS) do
        if mct_mod:get_option_by_key(key):get_selected_setting() then checked = checked + 1 end
    end
    for _, key in ipairs(SCROLL_TYPE_KEYS) do
        local option = mct_mod:get_option_by_key(key)
        option:set_locked(checked == 1 and option:get_selected_setting() == true)
    end
end

--- Locks every creature checkbox while "Enable all creatures" is checked.
--- @param enable_all boolean Live value of the `enable_all_creatures` checkbox.
local function sync_creature_locks(enable_all)
    for _, creature in ipairs(creatures.list) do
        mct_mod:get_option_by_key(settings.creature_option_key(creature.id)):set_locked(enable_all == true)
    end
end

--- Locks the starting-scroll creature dropdown while "Starting scroll for faction leader" is unchecked.
--- @param starting_scroll boolean Live value of the `starting_scroll` checkbox.
local function sync_starting_creature_lock(starting_scroll)
    mct_mod:get_option_by_key("starting_scroll_creature"):set_locked(starting_scroll ~= true)
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Mod info

mct_mod:set_title("Kadon's Scrolls of Binding", true)
mct_mod:set_description(MOD_DESCRIPTION, true)
if type(mct_mod.set_workshop_id) == "function" then
    mct_mod:set_workshop_id("3398096688")
end
--- Kadon-specific file name, because every pack shares one virtual file tree and LEAPOI already ships `ui/images/mct_main_image.png`.
if type(mct_mod.set_main_image) == "function" then
    mct_mod:set_main_image("ui/images/jvj_kadon_mct.png", 300, 300)
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Drops

add_section("drops_section", "Drops")
add_percent_slider("battle_drop_chance", "Scroll chance after a won battle (%)", "Chance for the winning side's general to find a Kadon scroll. Quest battles never drop scrolls.")
add_percent_slider("mission_drop_chance", "Scroll chance on completing a mission (%)", "Chance to find a Kadon scroll on top of the mission's normal reward.")
add_checkbox("ai_can_find_scrolls", "drops_section", "AI factions can find scrolls", "When off, only human players get scrolls from battles and missions.")
add_checkbox("no_duplicate_scrolls", "drops_section", "No duplicate scrolls per faction", "A faction never receives a scroll it already owns, equipped or in its item pool.")
--- Not read-only: MCT's `set_read_only` locks the option in the main menu too. The scroll is only granted on a new campaign anyway.
add_checkbox("starting_scroll", "drops_section", "Starting scroll for faction leader",
    "On a new campaign, each human faction leader starts with one allowed scroll. Changing it mid-campaign has no effect.")
add_starting_creature_dropdown()
add_spacer("drops_spacer", "drops_section")

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Scroll types

add_section("scroll_types_section", "Scroll Types", "Each drop is randomly Kin or Binding. At least one type must stay on.")
add_checkbox("allow_kin", "scroll_types_section", "Allow Scrolls of Kin", "Kin summons stay on the battlefield until they are killed.")
add_checkbox("allow_bind", "scroll_types_section", "Allow Scrolls of Binding",
    "Binding summons suffer from Unbinding, a negative status effect that gives them a time limit before they die.")
add_spacer("scroll_types_spacer", "scroll_types_section")

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Creatures

add_section("creatures_section", "Creatures", "Disabled creatures never drop. Takes effect on the next drop.")
add_checkbox("enable_all_creatures", "creatures_section", "Enable all creatures", "When on, every creature can drop and the individual toggles below are locked.")
for _, creature in ipairs(creatures.list) do
    add_checkbox(settings.creature_option_key(creature.id), "creatures_section", creatures.label(creature), nil, true)
end
add_spacer("creatures_spacer", "creatures_section")

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Lock listeners

core:add_listener(
    "jvj_kadon_scroll_type_locks",
    "MctOptionSelectedSettingSet",
    function(context)
        return is_own_option(context, SCROLL_TYPE_KEYS)
    end,
    function()
        sync_scroll_type_locks()
    end,
    true
)

--- Reads the live UI value via `context:setting()`, because `get_finalized_setting()` is not updated until the panel closes.
core:add_listener(
    "jvj_kadon_creature_locks",
    "MctOptionSelectedSettingSet",
    function(context)
        return is_own_option(context, { "enable_all_creatures" })
    end,
    function(context)
        sync_creature_locks(context:setting())
    end,
    true
)

core:add_listener(
    "jvj_kadon_starting_creature_lock",
    "MctOptionSelectedSettingSet",
    function(context)
        return is_own_option(context, { "starting_scroll" })
    end,
    function(context)
        sync_starting_creature_lock(context:setting())
    end,
    true
)

--- Saved settings can differ from the defaults the page was built with, so resync every lock rule whenever the panel opens.
core:add_listener(
    "jvj_kadon_panel_opened_locks",
    "MctPanelOpened",
    true,
    function()
        sync_scroll_type_locks()
        sync_creature_locks(mct_mod:get_option_by_key("enable_all_creatures"):get_selected_setting())
        sync_starting_creature_lock(mct_mod:get_option_by_key("starting_scroll"):get_selected_setting())
    end,
    true
)

sync_scroll_type_locks()
sync_creature_locks(mct_mod:get_option_by_key("enable_all_creatures"):get_selected_setting())
sync_starting_creature_lock(mct_mod:get_option_by_key("starting_scroll"):get_selected_setting())
