--- Checks settings defaults and MCT loading.

local h = require("tests/helpers")
local stubs = h.install_game_stubs()
local creatures = require("script/jvj_kadon/creatures")
local settings = require("script/jvj_kadon/settings")

--- Builds a fake `mct_mod` whose options return the given finalized values. Keys missing from `values` return no option.
--- @param values table Option key to finalized value.
--- @returns table Fake `mct_mod`.
local function fake_mct_mod(values)
    return {
        get_option_by_key = function(_, key)
            if values[key] == nil then return nil end
            return { get_finalized_setting = function() return values[key] end }
        end,
    }
end

h.test("defaults after reset", function()
    settings.reset()
    h.eq(settings.MCT_MOD_KEY, "jvj_kadon", "mod key")
    h.eq(settings.values.battle_drop_chance, 5, "battle chance")
    h.eq(settings.values.mission_drop_chance, 10, "mission chance")
    h.eq(settings.values.ai_can_find_scrolls, true, "ai")
    h.eq(settings.values.no_duplicate_scrolls, false, "no dupes")
    h.eq(settings.values.starting_scroll, false, "starting scroll")
    h.eq(settings.values.starting_scroll_creature, "random", "starting scroll creature")
    h.eq(settings.values.allow_kin, true, "allow kin")
    h.eq(settings.values.allow_bind, true, "allow bind")
    h.eq(settings.values.enable_all_creatures, true, "enable all original")
    h.eq(settings.values.enable_all_vanilla_creatures, true, "enable all vanilla")
    for _, creature in ipairs(creatures.list) do
        h.eq(settings.values.enabled_creatures[creature.id], true, creature.id)
    end
end)

h.test("creature option key", function()
    h.eq(settings.creature_option_key("giant"), "creature_giant", "key")
end)

h.test("enable all key splits Original from vanilla and DLC", function()
    h.eq(settings.enable_all_key("Original"), "enable_all_creatures", "original")
    for _, game in ipairs({ "WH1", "WH2", "WH3" }) do
        h.eq(settings.enable_all_key(game), "enable_all_vanilla_creatures", game)
    end
end)

h.test("load_from_mct copies finalized values", function()
    settings.reset()
    local values = {
        battle_drop_chance = 25, mission_drop_chance = 0, ai_can_find_scrolls = false, no_duplicate_scrolls = true,
        starting_scroll = true, allow_kin = false, allow_bind = true, enable_all_creatures = false,
        enable_all_vanilla_creatures = false,
    }
    for _, creature in ipairs(creatures.list) do
        values[settings.creature_option_key(creature.id)] = creature.id ~= "giant"
    end
    settings.load_from_mct(fake_mct_mod(values))
    h.eq(settings.values.battle_drop_chance, 25, "battle chance")
    h.eq(settings.values.mission_drop_chance, 0, "mission chance")
    h.eq(settings.values.ai_can_find_scrolls, false, "ai")
    h.eq(settings.values.allow_kin, false, "allow kin")
    h.eq(settings.values.enable_all_creatures, false, "enable all original")
    h.eq(settings.values.enable_all_vanilla_creatures, false, "enable all vanilla")
    h.eq(settings.values.enabled_creatures.giant, false, "giant")
    h.eq(settings.values.enabled_creatures.carnosaur, true, "carnosaur")
end)

h.test("load_from_mct keeps values for missing options", function()
    settings.reset()
    settings.load_from_mct(fake_mct_mod({ battle_drop_chance = 50 }))
    h.eq(settings.values.battle_drop_chance, 50, "battle chance")
    h.eq(settings.values.mission_drop_chance, 10, "mission chance kept")
    h.eq(settings.values.enabled_creatures.giant, true, "giant kept")
end)

h.test("MCT listeners reload settings and ignore a missing mod", function()
    settings.reset()
    settings.register_listeners()
    local events = {}
    for _, listener in ipairs(stubs.listeners) do
        events[listener.event] = listener
        h.eq(listener.persistent, true, listener.name .. " persistent")
    end
    h.truthy(events.MctInitialized, "MctInitialized listener")
    h.truthy(events.MctFinalized, "MctFinalized listener")

    local mod = fake_mct_mod({ battle_drop_chance = 40 })
    local context = { mct = function() return { get_mod_by_key = function(_, key) return key == "jvj_kadon" and mod or nil end } end }
    events.MctFinalized.callback(context)
    h.eq(settings.values.battle_drop_chance, 40, "reloaded on finalize")

    local empty_context = { mct = function() return { get_mod_by_key = function() return nil end } end }
    events.MctInitialized.callback(empty_context)
    h.eq(settings.values.battle_drop_chance, 40, "unchanged without mod")
end)

h.run()
