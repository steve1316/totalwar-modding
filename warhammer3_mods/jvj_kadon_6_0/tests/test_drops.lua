--- Checks the scroll picker, the battle / mission / turn-1 hooks, and the campaign entry point.

local h = require("tests/helpers")
h.install_game_stubs()
local creatures = require("script/jvj_kadon/creatures")
local settings = require("script/jvj_kadon/settings")
local drops = require("script/jvj_kadon/drops")

--- Returns the 1-based position of a creature id in `creatures.list`.
--- @param id string Creature id.
--- @returns number Position.
local function creature_index(id)
    for i, creature in ipairs(creatures.list) do
        if creature.id == id then return i end
    end
    error("unknown creature " .. id)
end

--- Returns every key held by a `candidates` result.
--- @param pool table Result of `drops.candidates`.
--- @returns table Set of keys.
local function pool_keys(pool)
    local keys = {}
    for _, types in ipairs(pool) do
        for _, list in ipairs(types) do
            for _, key in ipairs(list) do keys[key] = true end
        end
    end
    return keys
end

--- Returns the first listener registered for an event.
--- @param stubs table Recorder from `install_game_stubs`.
--- @param event string Event name.
--- @returns table Listener record.
local function listener_for(stubs, event)
    for _, listener in ipairs(stubs.listeners) do
        if listener.event == event then return listener end
    end
    error("no listener for " .. event)
end

--- Builds a fake character for `CharacterCompletedBattle`.
--- @param faction table Fake faction.
--- @param cqi number Command queue index.
--- @param won boolean|nil Whether the character won. Defaults to true.
--- @returns table Fake character.
local function fake_character(faction, cqi, won)
    return {
        faction = function() return faction end,
        command_queue_index = function() return cqi end,
        won_battle = function() return won ~= false end,
    }
end

h.test("all creatures and both types by default", function()
    h.install_game_stubs()
    settings.reset()
    local pool = drops.candidates(h.fake_faction())
    h.eq(#pool, #creatures.list, "creatures in pool")
    h.eq(#pool[creature_index("giant")], 2, "giant has kin and bind")
end)

h.test("disabled creature is never a candidate", function()
    h.install_game_stubs()
    settings.reset()
    settings.values.enable_all_vanilla_creatures = false
    settings.values.enabled_creatures.carnosaur = false
    local keys = pool_keys(drops.candidates(h.fake_faction()))
    h.eq(#drops.candidates(h.fake_faction()), #creatures.list - 1, "creatures in pool")
    h.eq(keys.kadon_kin_carnosaur, nil, "kin carnosaur")
    h.eq(keys.kadon_bind_carnosaur, nil, "bind carnosaur")
end)

h.test("enable all creatures overrides individual toggles", function()
    h.install_game_stubs()
    settings.reset()
    settings.values.enabled_creatures.carnosaur = false
    settings.values.enabled_creatures.unicorn = false
    h.eq(#drops.candidates(h.fake_faction()), #creatures.list, "creatures in pool")
end)

h.test("each enable all toggle only covers its own creatures", function()
    h.install_game_stubs()
    local originals = 0
    for _, creature in ipairs(creatures.list) do
        if creature.game == "Original" then originals = originals + 1 end
    end
    settings.reset()
    for id in pairs(settings.values.enabled_creatures) do settings.values.enabled_creatures[id] = false end
    settings.values.enable_all_creatures = false
    h.eq(#drops.candidates(h.fake_faction()), #creatures.list - originals, "only vanilla and DLC with the Original toggle off")
    settings.values.enable_all_creatures = true
    settings.values.enable_all_vanilla_creatures = false
    h.eq(#drops.candidates(h.fake_faction()), originals, "only Original with the vanilla toggle off")
end)

h.test("humans only get DLC scrolls they own, AI gets every scroll", function()
    local stubs = h.install_game_stubs()
    settings.reset()
    local scroll_dlc = require("script/jvj_kadon/scroll_dlc")
    stubs.owned_dlc = {}
    local human = h.fake_faction({ name = "p1" })
    stubs.factions.p1 = human
    local keys = pool_keys(drops.candidates(human))
    for key in pairs(keys) do h.eq(scroll_dlc[key], nil, key .. " needs no DLC") end
    h.truthy(keys.kadon_kin_giant and keys.kadon_bind_giant, "free giant scrolls stay")
    h.eq(keys.kadon_kin_bst_giant, nil, "beastmen giant needs its DLC")
    h.eq(keys.kadon_kin_ancient_salamander, nil, "ancient salamander needs its DLC")

    stubs.owned_dlc = { TW_WH2_DLC12_PROPHET = true }
    keys = pool_keys(drops.candidates(human))
    h.truthy(keys.kadon_kin_ancient_salamander and keys.kadon_bind_ancient_salamander, "owned DLC scrolls drop")

    local ai = h.fake_faction({ name = "ai1", human = false })
    stubs.factions.ai1 = ai
    h.eq(#drops.candidates(ai), #creatures.list, "AI gets every creature")
end)

h.test("chosen starting creature from unowned DLC falls back to a random owned scroll", function()
    local stubs = h.install_game_stubs()
    settings.reset()
    local scroll_dlc = require("script/jvj_kadon/scroll_dlc")
    settings.values.starting_scroll_creature = "ancient_salamander"
    stubs.owned_dlc = {}
    stubs.factions.p1 = h.fake_faction({ name = "p1" })
    local key = drops.pick_starting_scroll(stubs.factions.p1)
    h.truthy(key, "a scroll is picked")
    h.eq(scroll_dlc[key], nil, key .. " needs no DLC")
    stubs.owned_dlc = { TW_WH2_DLC12_PROPHET = true }
    h.truthy(drops.pick_starting_scroll(stubs.factions.p1):find("ancient_salamander", 1, true), "owned choice is kept")
end)

h.test("kin only and bind only", function()
    h.install_game_stubs()
    settings.reset()
    settings.values.allow_bind = false
    for key in pairs(pool_keys(drops.candidates(h.fake_faction()))) do
        h.truthy(key:find("^kadon_kin_"), key .. " is kin")
    end
    settings.reset()
    settings.values.allow_kin = false
    for key in pairs(pool_keys(drops.candidates(h.fake_faction()))) do
        h.truthy(key:find("^kadon_bind_"), key .. " is bind")
    end
end)

h.test("no duplicates skips owned scrolls", function()
    h.install_game_stubs()
    settings.reset()
    settings.values.no_duplicate_scrolls = true
    local faction = h.fake_faction({ owned = { "kadon_bind_carnosaur" } })
    local pool = drops.candidates(faction)
    h.eq(#pool, #creatures.list, "carnosaur still has kin")
    h.eq(#pool[creature_index("carnosaur")], 1, "carnosaur types")
    h.eq(pool_keys(pool).kadon_bind_carnosaur, nil, "owned bind removed")
    settings.values.allow_kin = false
    h.eq(#drops.candidates(faction), #creatures.list - 1, "carnosaur gone when only bind allowed")
end)

h.test("owned scrolls stay pickable when no duplicates is off", function()
    h.install_game_stubs()
    settings.reset()
    local faction = h.fake_faction({ owned = { "kadon_bind_carnosaur" } })
    h.truthy(pool_keys(drops.candidates(faction)).kadon_bind_carnosaur, "owned bind kept")
end)

h.test("pick is creature first, then type, then key", function()
    h.install_game_stubs({ creature_index("giant"), 1, 2 })
    settings.reset()
    settings.values.allow_bind = false
    h.eq(drops.pick_scroll(h.fake_faction()), "kadon_kin_bst_giant", "picked key")
end)

h.test("award adds the picked scroll to the faction pool", function()
    local stubs = h.install_game_stubs({ creature_index("wyvern"), 2, 1 })
    settings.reset()
    local key = drops.award_scroll(h.fake_faction({ name = "wh2_main_lzd_hexoatl" }), "battle")
    h.eq(key, "kadon_bind_wyvern", "returned key")
    h.eq(#stubs.added, 1, "added count")
    h.eq(stubs.added[1].key, "kadon_bind_wyvern", "added key")
    h.eq(stubs.added[1].faction, "wh2_main_lzd_hexoatl", "added faction")
end)

h.test("award skips cleanly when nothing is allowed", function()
    local stubs = h.install_game_stubs()
    settings.reset()
    settings.values.enable_all_creatures = false
    settings.values.enable_all_vanilla_creatures = false
    for id in pairs(settings.values.enabled_creatures) do settings.values.enabled_creatures[id] = false end
    h.eq(drops.award_scroll(h.fake_faction(), "battle"), nil, "nothing picked")
    h.eq(#stubs.added, 0, "nothing added")
    h.truthy(#stubs.logs > 0, "skip is logged")
end)

h.test("roll respects 0 and 100", function()
    h.install_game_stubs({ 1 })
    h.eq(drops.roll(0), false, "0 never passes")
    h.install_game_stubs({ 100 })
    h.eq(drops.roll(100), true, "100 always passes")
    h.install_game_stubs({ 6 })
    h.eq(drops.roll(5), false, "6 fails at 5")
end)

h.test("AI and rebel filter", function()
    h.install_game_stubs()
    settings.reset()
    h.eq(drops.faction_allowed(h.fake_faction({ human = false })), true, "AI allowed by default")
    settings.values.ai_can_find_scrolls = false
    h.eq(drops.faction_allowed(h.fake_faction({ human = false })), false, "AI blocked")
    h.eq(drops.faction_allowed(h.fake_faction()), true, "human allowed")
    settings.reset()
    h.eq(drops.faction_allowed(h.fake_faction({ rebel = true, human = false })), false, "rebels never")
end)

h.test("battle hook rolls for the winning primary general", function()
    local stubs = h.install_game_stubs({ 5, creature_index("hydra"), 1, 1 })
    settings.reset()
    drops.register_listeners()
    local faction = h.fake_faction({ name = "attacker" })
    stubs.factions.attacker = faction
    stubs.factions.defender = h.fake_faction({ name = "defender", human = false })
    local listener = listener_for(stubs, "CharacterCompletedBattle")
    local context = { character = function() return fake_character(faction, 1) end }
    h.eq(listener.condition(context), true, "condition")
    listener.callback(context)
    h.eq(#stubs.added, 1, "scroll added")
    h.eq(stubs.added[1].key, "kadon_kin_hydra", "added key")
end)

h.test("battle hook ignores secondary generals", function()
    local stubs = h.install_game_stubs()
    settings.reset()
    drops.register_listeners()
    local faction = h.fake_faction({ name = "attacker" })
    stubs.factions.attacker = faction
    local listener = listener_for(stubs, "CharacterCompletedBattle")
    h.eq(listener.condition({ character = function() return fake_character(faction, 99) end }), false, "secondary general")
    h.eq(listener.condition({ character = function() return fake_character(faction, 1, false) end }), false, "loser")
end)

h.test("battle hook skips quest battles", function()
    local stubs = h.install_game_stubs()
    settings.reset()
    drops.register_listeners()
    local faction = h.fake_faction({ name = "attacker" })
    stubs.factions.attacker = faction
    stubs.factions.defender = h.fake_faction({ name = "defender", quest = true })
    local listener = listener_for(stubs, "CharacterCompletedBattle")
    h.eq(listener.condition({ character = function() return fake_character(faction, 1) end }), false, "quest battle")
end)

h.test("battle hook does not award when the roll fails", function()
    local stubs = h.install_game_stubs({ 6 })
    settings.reset()
    drops.register_listeners()
    local faction = h.fake_faction({ name = "attacker" })
    stubs.factions.attacker = faction
    listener_for(stubs, "CharacterCompletedBattle").callback({ character = function() return fake_character(faction, 1) end })
    h.eq(#stubs.added, 0, "nothing added")
end)

h.test("mission hook awards on a passing roll", function()
    local stubs = h.install_game_stubs({ 10, creature_index("griffon"), 2, 1 })
    settings.reset()
    drops.register_listeners()
    local faction = h.fake_faction()
    local listener = listener_for(stubs, "MissionSucceeded")
    local context = { faction = function() return faction end }
    h.eq(listener.condition(context), true, "condition")
    listener.callback(context)
    h.eq(stubs.added[1].key, "kadon_bind_griffon", "added key")
end)

h.test("starting scroll off gives nothing", function()
    local stubs = h.install_game_stubs()
    settings.reset()
    stubs.human = { "p1" }
    stubs.factions.p1 = h.fake_faction({ leader = "leader1" })
    drops.give_starting_scrolls()
    h.eq(#stubs.forced, 0, "nothing forced")
end)

h.test("starting scroll equips each human leader and skips leaderless factions", function()
    local stubs = h.install_game_stubs({ creature_index("unicorn"), 1, 1 })
    settings.reset()
    settings.values.starting_scroll = true
    stubs.human = { "p1", "p2" }
    stubs.factions.p1 = h.fake_faction({ leader = "leader1" })
    stubs.factions.p2 = h.fake_faction()
    drops.give_starting_scrolls()
    h.eq(#stubs.forced, 1, "one scroll forced")
    h.eq(stubs.forced[1].character, "leader1", "leader")
    h.eq(stubs.forced[1].key, "kadon_kin_unicorn", "key")
    h.eq(stubs.forced[1].force_equip, true, "equipped")
end)

h.test("starting scroll uses the chosen creature", function()
    local stubs = h.install_game_stubs({ 2, 1 })
    settings.reset()
    settings.values.starting_scroll = true
    settings.values.starting_scroll_creature = "carnosaur"
    stubs.human = { "p1" }
    stubs.factions.p1 = h.fake_faction({ leader = "leader1" })
    drops.give_starting_scrolls()
    h.eq(stubs.forced[1].key, "kadon_bind_carnosaur", "key")
end)

h.test("chosen starting creature ignores creature toggles but keeps type toggles", function()
    local stubs = h.install_game_stubs({ 1, 3 })
    settings.reset()
    settings.values.starting_scroll = true
    settings.values.starting_scroll_creature = "giant"
    settings.values.enable_all_vanilla_creatures = false
    settings.values.enabled_creatures.giant = false
    settings.values.allow_bind = false
    stubs.human = { "p1" }
    stubs.factions.p1 = h.fake_faction({ leader = "leader1" })
    drops.give_starting_scrolls()
    h.eq(stubs.forced[1].key, "kadon_kin_chs_giant", "key")
end)

h.test("unknown starting creature falls back to a random pick", function()
    local stubs = h.install_game_stubs({ creature_index("wyvern"), 1, 1 })
    settings.reset()
    settings.values.starting_scroll = true
    settings.values.starting_scroll_creature = "no_such_creature"
    stubs.human = { "p1" }
    stubs.factions.p1 = h.fake_faction({ leader = "leader1" })
    drops.give_starting_scrolls()
    h.eq(stubs.forced[1].key, "kadon_kin_wyvern", "key")
end)

h.test("entry point registers every listener", function()
    local stubs = h.install_game_stubs()
    dofile("script/campaign/mod/jvj_kadon.lua")
    local events = {}
    for _, listener in ipairs(stubs.listeners) do events[listener.event] = true end
    h.truthy(events.MctInitialized and events.MctFinalized, "MCT listeners")
    h.truthy(events.CharacterCompletedBattle and events.MissionSucceeded, "drop listeners")
    h.eq(#stubs.first_tick, 1, "first tick callback")
end)

h.run()
