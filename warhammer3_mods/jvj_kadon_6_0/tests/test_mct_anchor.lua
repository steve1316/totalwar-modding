--- Loads the MCT anchor against a fake MCT and checks the page, defaults, tooltips and lock rules.

local h = require("tests/helpers")
local creatures = require("script/jvj_kadon/creatures")
local settings = require("script/jvj_kadon/settings")

--- Builds a fake MCT whose `register_mod` returns a mod that records sections and options.
--- @returns table Fake MCT manager, with the registered mod at `.mod` after the anchor runs.
local function fake_mct()
    local mct = {}
    mct.register_mod = function(_, key)
        local mod = { key = key, options = {}, sections = {}, order = {} }
        function mod:set_title(text, is_localised) self.title = text end
        function mod:set_author(text) self.author = text end
        function mod:set_description(text, is_localised) self.description = text end
        function mod:set_workshop_id(id) self.workshop_id = id end
        function mod:get_key() return self.key end
        function mod:add_new_section(section_key)
            local section = { key = section_key }
            function section:set_localised_text(text, is_localised) self.text = text end
            function section:set_description(text) self.description = text end
            self.sections[section_key] = section
            return section
        end
        function mod:add_new_option(option_key, option_type)
            local option = { key = option_key, type = option_type, locked = false }
            function option:set_text(text, is_localised) self.text = text end
            function option:set_tooltip_text(text, is_localised) self.tooltip = text end
            function option:set_is_global(value) self.global = value end
            function option:set_default_value(value) self.default = value; self.selected = value end
            function option:set_assigned_section(section_key) self.section = section_key end
            function option:slider_set_min_max(min, max) self.min = min; self.max = max end
            function option:slider_set_precision(precision) self.precision = precision end
            function option:slider_set_step_size(step, precision) self.step = step end
            --- Real MCT's `set_read_only` just calls `set_locked`, so it locks the option everywhere, main menu included.
            function option:set_read_only(value, reason) self:set_locked(value) end
            function option:set_locked(value) self.locked = value end
            function option:get_selected_setting() return self.selected end
            function option:get_key() return self.key end
            function option:get_mod() return mod end
            self.options[option_key] = option
            table.insert(self.order, option_key)
            return option
        end
        function mod:get_option_by_key(option_key) return self.options[option_key] end
        mct.mod = mod
        return mod
    end
    return mct
end

--- Loads the anchor with fresh stubs and a fresh fake MCT.
--- @returns table, table The fake mod and the stub recorder.
local function load_anchor()
    local stubs = h.install_game_stubs()
    local mct = fake_mct()
    _G.get_mct = function() return mct end
    dofile("script/mct/settings/jvj_kadon.lua")
    return mct.mod, stubs
end

--- Changes an option's live value and fires the `MctOptionSelectedSettingSet` listeners that match it.
--- @param stubs table Stub recorder.
--- @param option table Fake option.
--- @param value any New live value.
local function select_setting(stubs, option, value)
    option.selected = value
    local context = { option = function() return option end, setting = function() return value end }
    for _, listener in ipairs(stubs.listeners) do
        if listener.event == "MctOptionSelectedSettingSet" and listener.condition(context) then
            listener.callback(context)
        end
    end
end

--- Fires the `MctPanelOpened` listeners.
--- @param stubs table Stub recorder.
local function open_panel(stubs)
    for _, listener in ipairs(stubs.listeners) do
        if listener.event == "MctPanelOpened" then listener.callback({}) end
    end
end

h.test("registers the jvj_kadon mod", function()
    local mod = load_anchor()
    h.eq(mod.key, "jvj_kadon", "mod key")
    h.eq(mod.workshop_id, "3398096688", "workshop id")
    h.truthy(mod.title, "title")
    h.truthy(mod.description:find("Scrolls of Kin", 1, true), "description explains Kin")
    h.truthy(mod.description:find("Scrolls of Binding", 1, true), "description explains Binding")
    h.truthy(mod.description:find("Beautiful & the Beastly", 1, true), "description credits the mod jam")
end)

h.test("option keys and defaults match the settings module", function()
    local mod = load_anchor()
    local expected = 0
    for key, default in pairs(settings.DEFAULTS) do
        h.truthy(mod.options[key], key .. " exists")
        h.eq(mod.options[key].default, default, key .. " default")
        expected = expected + 1
    end
    for _, creature in ipairs(creatures.list) do
        local option = mod.options[settings.creature_option_key(creature.id)]
        h.truthy(option, creature.id .. " toggle exists")
        h.eq(option.default, true, creature.id .. " default")
        h.eq(option.text, creature.name, creature.id .. " text")
        expected = expected + 1
    end
    h.eq(#mod.order, expected + 1, "no extra options besides the spacer")
end)

h.test("settings are global with tooltips, creature toggles have none", function()
    local mod = load_anchor()
    local creature_keys = {}
    for _, creature in ipairs(creatures.list) do creature_keys[settings.creature_option_key(creature.id)] = true end
    for key, option in pairs(mod.options) do
        h.truthy(mod.sections[option.section], key .. " section " .. tostring(option.section))
        if option.type ~= "dummy" then
            h.eq(option.global, true, key .. " global")
            if creature_keys[key] then
                h.eq(option.tooltip, nil, key .. " has no tooltip")
            else
                h.truthy(option.tooltip and option.tooltip ~= "", key .. " tooltip")
            end
        end
    end
end)

h.test("scroll types section ends with a blank spacer row", function()
    local mod = load_anchor()
    local last
    for _, key in ipairs(mod.order) do
        if mod.options[key].section == "scroll_types_section" then last = mod.options[key] end
    end
    h.eq(last.type, "dummy", "last row type")
    h.eq(last.text, " ", "blank label")
    h.eq(last.default, nil, "no default")
    h.eq(last.tooltip, nil, "no tooltip")
end)

h.test("sliders, read-only and tooltip wording", function()
    local mod = load_anchor()
    for _, key in ipairs({ "battle_drop_chance", "mission_drop_chance" }) do
        h.eq(mod.options[key].type, "slider", key .. " type")
        h.eq(mod.options[key].min, 0, key .. " min")
        h.eq(mod.options[key].max, 100, key .. " max")
        h.eq(mod.options[key].step, 1, key .. " step")
    end
    h.eq(mod.options.starting_scroll.locked, false, "starting scroll stays editable")
    h.eq(mod.options.starting_scroll.tooltip, "On a new campaign, each human faction leader starts with one random allowed scroll. Changing it mid-campaign has no effect.", "starting scroll tooltip")
    h.eq(mod.options.allow_kin.tooltip, "Kin summons stay on the battlefield until they are killed.", "kin tooltip")
    h.eq(mod.options.allow_bind.tooltip, "Binding summons suffer from Unbinding, a negative status effect that gives them a time limit before they die.", "bind tooltip")
    h.eq(mod.sections.scroll_types_section.description, "Each drop is randomly Kin or Binding. At least one type must stay on.", "types description")
end)

h.test("scroll type lock follows toggles", function()
    local mod, stubs = load_anchor()
    h.eq(mod.options.allow_kin.locked, false, "kin starts unlocked")
    h.eq(mod.options.allow_bind.locked, false, "bind starts unlocked")
    select_setting(stubs, mod.options.allow_kin, false)
    h.eq(mod.options.allow_bind.locked, true, "bind locked when alone")
    h.eq(mod.options.allow_kin.locked, false, "unchecked kin stays unlocked")
    select_setting(stubs, mod.options.allow_kin, true)
    h.eq(mod.options.allow_bind.locked, false, "bind unlocked again")
end)

h.test("creature toggles lock while enable all is on", function()
    local mod, stubs = load_anchor()
    local giant = mod.options[settings.creature_option_key("giant")]
    h.eq(giant.locked, true, "locked by default")
    select_setting(stubs, mod.options.enable_all_creatures, false)
    h.eq(giant.locked, false, "unlocked when master off")
    select_setting(stubs, mod.options.enable_all_creatures, true)
    h.eq(giant.locked, true, "locked again")
end)

h.test("panel open resyncs creature locks", function()
    local mod, stubs = load_anchor()
    local giant = mod.options[settings.creature_option_key("giant")]
    mod.options.enable_all_creatures.selected = false
    open_panel(stubs)
    h.eq(giant.locked, false, "unlocked after reopening with master off")
    mod.options.allow_bind.selected = false
    open_panel(stubs)
    h.eq(mod.options.allow_kin.locked, true, "kin locked after reopening with bind off")
end)

h.test("lock listeners ignore other mods' options", function()
    local mod, stubs = load_anchor()
    local foreign = { get_key = function() return "allow_kin" end, get_mod = function() return { get_key = function() return "other_mod" end } end }
    local context = { option = function() return foreign end, setting = function() return false end }
    for _, listener in ipairs(stubs.listeners) do
        if listener.event == "MctOptionSelectedSettingSet" then
            h.eq(listener.condition(context), false, listener.name .. " ignores other mods")
        end
    end
end)

h.run()
