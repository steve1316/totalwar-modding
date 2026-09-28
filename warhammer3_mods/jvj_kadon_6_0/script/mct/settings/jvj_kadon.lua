--- MCT anchor for Kadon's Scrolls of Binding. MCT discovers this file and builds the settings page from it. The option keys here must
--- match `settings.DEFAULTS` and `settings.creature_option_key`, because the settings module reads them back.

local creatures = require("script/jvj_kadon/creatures")
local settings = require("script/jvj_kadon/settings")

--- Scroll type option keys. At least one must stay checked.
local SCROLL_TYPE_KEYS = { "allow_kin", "allow_bind" }

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
--- @param tooltip string Hover text.
--- @param default boolean Default value.
--- @returns table The created option.
local function add_checkbox(key, section, text, tooltip, default)
    local option = mct_mod:add_new_option(key, "checkbox")
    option:set_text(text, true)
    option:set_tooltip_text(tooltip, true)
    option:set_is_global(true)
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

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Mod info

mct_mod:set_title("Kadon's Scrolls of Binding", true)
mct_mod:set_description("Kadon's Scrolls summon a bound creature in battle. These settings control how often scrolls drop, who can find them, and which creatures appear.", true)
if type(mct_mod.set_workshop_id) == "function" then
    mct_mod:set_workshop_id("3398096688")
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Drops

add_section("drops_section", "Drops")
add_percent_slider("battle_drop_chance", "Scroll chance after a won battle (%)", "Chance for the winning side's general to find a Kadon scroll. Quest battles never drop scrolls.")
add_percent_slider("mission_drop_chance", "Scroll chance on completing a mission (%)", "Chance to find a Kadon scroll on top of the mission's normal reward.")
add_checkbox("ai_can_find_scrolls", "drops_section", "AI factions can find scrolls", "When off, only human players get scrolls from battles and missions.", settings.DEFAULTS.ai_can_find_scrolls)
add_checkbox("no_duplicate_scrolls", "drops_section", "No duplicate scrolls per faction", "A faction never receives a scroll it already owns, equipped or in its item pool.", settings.DEFAULTS.no_duplicate_scrolls)
--- Not read-only: MCT's `set_read_only` locks the option in the main menu too. The scroll is only granted on a new campaign anyway.
add_checkbox("starting_scroll", "drops_section", "Starting scroll for faction leader", "On a new campaign, each human faction leader starts with one random allowed scroll. Changing it mid-campaign has no effect.", settings.DEFAULTS.starting_scroll)

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Scroll types

add_section("scroll_types_section", "Scroll Types", "Each drop is randomly Kin or Binding, from the types allowed here. At least one type must stay on.")
add_checkbox("allow_kin", "scroll_types_section", "Allow Scrolls of Kin", "Kin summons stay on the battlefield until they are killed.", settings.DEFAULTS.allow_kin)
add_checkbox("allow_bind", "scroll_types_section", "Allow Scrolls of Binding", "Binding summons are identical to Kin, but they fade. After about 90 seconds they start losing health, and they're gone soon after.", settings.DEFAULTS.allow_bind)

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Creatures

add_section("creatures_section", "Creatures", "Disabled creatures never drop. Takes effect on the next drop.")
add_checkbox("enable_all_creatures", "creatures_section", "Enable all creatures", "When on, every creature can drop and the individual toggles below are locked.", settings.DEFAULTS.enable_all_creatures)
for _, creature in ipairs(creatures.list) do
    add_checkbox(settings.creature_option_key(creature.id), "creatures_section", creature.name, "Allow " .. creature.name .. " scrolls to drop.", true)
end

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

--- Saved settings can differ from the defaults the page was built with, so resync both lock rules whenever the panel opens.
core:add_listener(
    "jvj_kadon_panel_opened_locks",
    "MctPanelOpened",
    true,
    function()
        sync_scroll_type_locks()
        sync_creature_locks(mct_mod:get_option_by_key("enable_all_creatures"):get_selected_setting())
    end,
    true
)

sync_scroll_type_locks()
sync_creature_locks(mct_mod:get_option_by_key("enable_all_creatures"):get_selected_setting())
