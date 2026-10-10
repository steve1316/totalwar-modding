--- Boons and curses (configs/boons.lua): lasting effects a human faction's lords carry. A boon grows a level every few battles the lord wins,
--- a curse gets worse every few turns until it is cleansed, and a few curses endured at their worst turn into a boon. Each boon or curse is a
--- trait on the lord whose levels carry its effects, and a countdown bundle in the army's effects saying how long it lasts or when it
--- changes. Rare faction-wide ones are faction bundles, one per turn left, that the script counts down and takes off. AI lords get none.

require("script/land_encounters/utils/common")
require("script/land_encounters/utils/random")
require("script/land_encounters/core/mct")

local data = require("script/land_encounters/configs/boons")
local debug_config = require("script/land_encounters/configs/debug")
local dilemmas = require("script/land_encounters/core/dilemmas")
local tower_army = require("script/land_encounters/features/tower_army")

--- Both kinds a lord carries, in the order they are walked.
local KINDS = { "boon", "curse" }

--- Kind -> drop source -> the keys that drop there, built once from the config.
local DROP_POOLS = { boon = {}, curse = {} }
for kind, list in pairs({ boon = data.boons, curse = data.curses }) do
    for _, config in ipairs(list) do
        for _, source in ipairs(config.drops or {}) do
            DROP_POOLS[kind][source] = DROP_POOLS[kind][source] or {}
            table.insert(DROP_POOLS[kind][source], config.key)
        end
    end
end

--- Choice key -> its slot number, for the full-slots and pick dilemmas.
local CHOICE_SLOT = {}
for i, key in ipairs(data.full_choices) do CHOICE_SLOT[key] = i end
for i, key in ipairs(data.pick_choices) do CHOICE_SLOT[key] = i end

local M = {
    --- Character command queue index (as a string) -> { faction, boon = { entry }, curse = { entry } }. An entry is { key, level, race,
    --- wins (battles won toward the next level), charges (battles left on a charged boon), turns (turns toward the next level, or at the
    --- worst level), trait_level (the level its trait was last set to), shown (its countdown bundle on the lord) }.
    lords = {},
    --- Faction key -> the boon waiting on the full-slots dilemma: { cqi, entry }.
    pending = {},
    --- Faction key -> the boons offered on the pick dilemma: { cqi, keys }.
    picks = {},
    --- Faction key -> faction-wide key -> the turn its bundle comes off.
    realms = {},
}

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Helpers

--- True while the MCT switch has boons and curses on.
--- @returns boolean True when enabled.
function M.enabled()
    return get_mct_settings()[data.enable_setting] ~= false
end

--- How many boons or curses a lord can carry.
--- @param kind string "boon" or "curse".
--- @returns number The slots, at most one per full-slots choice.
function M.slots(kind)
    return math.max(1, math.min(#data.full_choices, get_mct_settings()[data.slot_settings[kind]]))
end

--- The name of one boon or curse without its level or a prefix, e.g. bane_dwarfs. Its trait and countdown bundles are built from it.
--- @param entry table The entry.
--- @returns string The base name.
local function base(entry)
    return entry.key .. (entry.race and "_" .. entry.race or "")
end

--- The name of one boon or curse at its level without a prefix, e.g. bane_dwarfs_3. Its payload line is built from it.
--- @param entry table The entry.
--- @returns string The stem.
local function stem(entry)
    return base(entry) .. "_" .. entry.level
end

--- The trait of one boon or curse, e.g. land_enc_trait_boon_bane_dwarfs. Its level is the boon's or curse's level.
--- @param kind string "boon" or "curse".
--- @param entry table The entry.
--- @returns string The trait key.
function M.trait(kind, entry)
    return data.trait_prefix[kind] .. base(entry)
end

--- The payload line that names one boon or curse at its level, e.g. dummy_land_enc_boon_bloodsworn_3.
--- @param kind string "boon" or "curse".
--- @param entry table The entry.
--- @returns string The payload line key.
function M.line(kind, entry)
    return data.line_prefix .. kind .. "_" .. stem(entry)
end

--- Battles the lord must win to raise a boon one level.
--- @returns number The wins.
local function wins_per_level()
    return debug_config.boon_wins_per_level[1] or data.wins_per_level
end

--- Turns that make a curse one level worse.
--- @returns number The turns.
local function turns_per_level()
    return debug_config.curse_turns_per_level[1] or data.turns_per_level
end

--- The clock a boon or curse shows in its countdown bundle.
--- @param kind string "boon" or "curse".
--- @param entry table The entry.
--- @returns string, number|nil The clock's name, and its count for a counted clock, kept within the countdown bundles that exist.
local function clock(kind, entry)
    local name, count
    if kind == "boon" then
        if entry.charges then name, count = "lasts", entry.charges
        elseif entry.level < data.max_level then name, count = "upgrades", wins_per_level() - entry.wins
        else return "strongest" end
    elseif entry.level < data.max_level then name, count = "worsens", turns_per_level() - entry.turns
    elseif data.by_key.curse[entry.key].turns_into then name, count = "becomes", data.turns_to_turn - entry.turns
    else return "worst" end
    return name, math.max(1, math.min(count, data.clock_counts[name]))
end

--- The countdown bundle of one boon or curse at its level for its clock, e.g. land_enc_effect_boon_bane_dwarfs_2_upgrades_3. It names the level's effects.
--- @param kind string "boon" or "curse".
--- @param entry table The entry.
--- @returns string The bundle key.
function M.bundle(kind, entry)
    local name, count = clock(kind, entry)
    return data.bundle_prefix[kind] .. stem(entry) .. "_" .. name .. (count and "_" .. count or "")
end

--- Shows one of a lord's boons or curses: its trait at the entry's level, set again only when the level changed, and the countdown bundle for
--- its clock in the army's effects. The countdown shown last comes off when the clock moves on. The entry keeps the trait level and bundle
--- it shows in `trait_level` and `shown`.
--- @param character userdata The lord.
--- @param kind string "boon" or "curse".
--- @param entry table The entry.
local function show(character, kind, entry)
    if entry.trait_level ~= entry.level then
        local lookup, trait = cm:char_lookup_str(character), M.trait(kind, entry)
        cm:force_remove_trait(lookup, trait)
        cm:force_add_trait(lookup, trait, false, entry.level)
        entry.trait_level = entry.level
    end
    local bundle = M.bundle(kind, entry)
    if entry.shown and entry.shown ~= bundle then cm:remove_effect_bundle_from_character(entry.shown, character) end
    cm:apply_effect_bundle_to_character(bundle, character, 0)
    entry.shown = bundle
end

--- Takes one of a lord's boons or curses off the lord: its trait and its countdown bundle.
--- @param character userdata The lord.
--- @param kind string "boon" or "curse".
--- @param entry table The entry.
local function hide(character, kind, entry)
    cm:force_remove_trait(cm:char_lookup_str(character), M.trait(kind, entry))
    if entry.shown then cm:remove_effect_bundle_from_character(entry.shown, character) end
end

--- The faction-wide bundle of one key with some turns left, e.g. land_enc_effect_realm_pariah_7.
--- @param key string The faction-wide key.
--- @param turns number The turns it has left.
--- @returns string The bundle key.
function M.realm_bundle(key, turns)
    return data.realm_prefix .. key .. "_" .. math.max(1, math.min(turns, data.realm_turns))
end

--- Puts a faction-wide bundle on a faction for its turns left, taking off the ones for every other count.
--- @param faction_name string The faction.
--- @param key string The faction-wide key.
--- @param turns number|nil The turns it has left, or nil to take it off.
local function show_realm(faction_name, key, turns)
    local shown = turns and M.realm_bundle(key, turns)
    for left = 1, data.realm_turns do
        local bundle = M.realm_bundle(key, left)
        if bundle ~= shown then cm:remove_effect_bundle(bundle, faction_name) end
    end
    if shown then cm:apply_effect_bundle(shown, faction_name, 0) end
end

--- The entry for a key (and race) in a list, with its slot.
--- @param list table The entries.
--- @param key string The boon or curse key.
--- @param race string|nil The race of a rolled one.
--- @returns table|nil, number|nil The entry and its slot, or nil.
local function find(list, key, race)
    for i, entry in ipairs(list) do
        if entry.key == key and entry.race == race then return entry, i end
    end
    return nil
end

--- Launches an incident that shows one payload line. Falls back to a log line when it cannot be built.
--- @param incident string The incident key.
--- @param line string The payload line key.
--- @param faction userdata The faction to show it to.
--- @returns boolean True when it launched.
local function launch_line_incident(incident, line, faction)
    local ok, err = pcall(function()
        local builder = cm:create_incident_builder(incident)
        local payload = cm:create_payload()
        for _, shown in ipairs(type(line) == "table" and line or { line }) do payload:text_display(shown) end
        builder:set_payload(payload)
        cm:launch_custom_incident_from_builder(builder, faction)
    end)
    if not ok then log("boons: incident " .. incident .. " failed: " .. tostring(err)) end
    return ok
end

--- Tells the player about one of a lord's boons or curses with an incident that shows its line and names the lord.
--- @param event string|boolean The incident's event, e.g. "boon_grew", or false to say nothing.
--- @param character userdata The lord.
--- @param kind string "boon" or "curse".
--- @param entry table The entry.
local function notify(event, character, kind, entry)
    if not event then return end
    common.set_context_value(data.lord_context, lord_name(character))
    launch_line_incident(data.incident_prefix .. event, M.line(kind, entry), character:faction())
    log("boons: " .. event .. " " .. M.bundle(kind, entry) .. " on lord " .. character:command_queue_index())
end

--- The record of a lord, made on first use.
--- @param character userdata The lord.
--- @returns table The record.
local function record_of(character)
    local cqi = tostring(character:command_queue_index())
    M.lords[cqi] = M.lords[cqi] or { faction = character:faction():name(), boon = {}, curse = {} }
    return M.lords[cqi]
end

--- A lord's boons and curses without making a record for them, for the Smithy and Tavern services.
--- @param character userdata The lord.
--- @returns table { boon = { entry }, curse = { entry } }, empty lists when the lord carries nothing.
function M.find_record(character)
    return M.lords[tostring(character:command_queue_index())] or { boon = {}, curse = {} }
end

--- A new entry for a boon or curse, rolling its race when it has one and none is given.
--- @param config table The boon or curse record of configs/boons.lua.
--- @param level number|nil Its level, 1 when nil.
--- @param race string|nil Its race.
--- @returns table The entry.
local function new_entry(config, level, race)
    return { key = config.key, level = math.min(level or 1, data.max_level), race = config.race and (race or data.races[random_number(#data.races)]) or nil,
        wins = 0, turns = 0, charges = config.charges }
end

--- Tells the player about a change to a lord with an incident that shows several lines and names the lord, e.g. Rust for Iron's boon and
--- curse together.
--- @param event string The incident's event.
--- @param character userdata The lord.
--- @param lines table The payload line keys.
function M.announce(event, character, lines)
    common.set_context_value(data.lord_context, lord_name(character))
    launch_line_incident(data.incident_prefix .. event, lines, character:faction())
    log("boons: " .. event .. " " .. table.concat(lines, ", ") .. " on lord " .. character:command_queue_index())
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Changes

--- Raises a boon or worsens a curse one level, up to the top, and says so: the old level's bundle comes off and the new one goes on.
--- @param character userdata The lord.
--- @param kind string "boon" or "curse".
--- @param entry table The entry.
--- @param event string|boolean|nil The incident to show instead of the usual one, or false for none.
--- @returns boolean True when it rose.
function M.raise(character, kind, entry, event)
    if entry.level >= data.max_level or entry.charges then return false end
    entry.level, entry.wins, entry.turns = entry.level + 1, 0, 0
    show(character, kind, entry)
    if event == nil then event = kind == "boon" and "boon_grew" or "curse_worse" end
    notify(event, character, kind, entry)
    return true
end

--- Takes one of a lord's boons or curses away and says so.
--- @param character userdata The lord.
--- @param kind string "boon" or "curse".
--- @param index number The entry's slot.
--- @param event string|nil The incident to show, or nil for none.
function M.remove(character, kind, index, event)
    local entry = table.remove(record_of(character)[kind], index)
    if not entry then return end
    hide(character, kind, entry)
    if event then notify(event, character, kind, entry) end
end

--- Turns one of a lord's boons or curses into a random other one they do not carry (never a charged boon), at the same level and with its
--- clock started again, and says so. Used by a lost gamble or reweave at the hedge-witch.
--- @param character userdata The lord.
--- @param kind string "boon" or "curse".
--- @param index number The entry's slot.
--- @param event string The incident that says so.
--- @returns string|nil The new key, or nil when no other one is left to become.
function M.shift(character, kind, index, event)
    local list = record_of(character)[kind]
    local old = list[index]
    if not old then return nil end
    local carried, pool = {}, {}
    for _, entry in ipairs(list) do carried[entry.key] = true end
    for _, config in ipairs(kind == "boon" and data.boons or data.curses) do
        if not carried[config.key] and not config.charges then pool[#pool + 1] = config end
    end
    if #pool == 0 then return nil end
    local config = pool[random_number(#pool)]
    local entry = new_entry(config, old.level)
    hide(character, kind, old)
    list[index] = entry
    show(character, kind, entry)
    log("boons: lord " .. character:command_queue_index() .. "'s " .. M.bundle(kind, old) .. " shifts into " .. M.bundle(kind, entry))
    notify(event, character, kind, entry)
    return config.key
end

--- True when a boon can still grow: it is not charged and not at its highest level.
--- @param entry table The boon.
--- @returns boolean True when it can grow.
function M.can_grow(entry)
    return not entry.charges and entry.level < data.max_level
end

--- Adds won battles to one of a lord's boons, after a won battle or the hedge-witch's Feed a Boon. It rises a level once it has enough, and
--- says so.
--- @param character userdata The lord.
--- @param entry table The boon.
--- @param wins number The wins added.
--- @param event string|nil The incident a rise shows, the usual "boon_grew" when nil.
--- @returns boolean True when the boon rose a level.
function M.add_wins(character, entry, wins, event)
    if not M.can_grow(entry) then return false end
    entry.wins = entry.wins + wins
    log("boons: lord " .. character:command_queue_index() .. "'s " .. M.bundle("boon", entry) .. " gains " .. wins .. " wins (" .. entry.wins .. " of "
        .. wins_per_level() .. ")")
    if entry.wins >= wins_per_level() then return M.raise(character, "boon", entry, event) end
    show(character, "boon", entry)
    return false
end

--- Puts a new entry in a lord's free slot and says so.
--- @param character userdata The lord.
--- @param kind string "boon" or "curse".
--- @param entry table The entry.
--- @param event string|boolean|nil The incident to show instead of the usual one, or false for none.
local function add(character, kind, entry, event)
    local list = record_of(character)[kind]
    list[#list + 1] = entry
    show(character, kind, entry)
    if event == nil then event = kind .. "_gained" end
    notify(event, character, kind, entry)
end

--- Asks which boon a lord with full slots gives up for a new one: one choice per boon they carry, then the new one.
--- @param character userdata The lord.
--- @param entry table The new boon's entry.
local function ask_full(character, entry)
    local faction_name = character:faction():name()
    local choices = {}
    for i, boon in ipairs(record_of(character).boon) do choices[#choices + 1] = { key = data.full_choices[i], lines = { M.line("boon", boon) } } end
    choices[#choices + 1] = { key = data.full_new_choice, lines = { M.line("boon", entry) } }
    M.pending[faction_name] = { cqi = tostring(character:command_queue_index()), entry = entry }
    common.set_context_value(data.lord_context, lord_name(character))
    log("boons: lord " .. character:command_queue_index() .. " has full boon slots, asking which to give up for " .. M.bundle("boon", entry))
    dilemmas.launch(data.full_dilemma, choices, faction_name)
end

--- Gives a lord a boon or curse. One they already carry rises a level instead (a charged boon gets its battles back). A new boon with full
--- slots asks which to give up. A new curse with full slots worsens the lord's mildest curse instead.
--- @param character userdata The lord.
--- @param kind string "boon" or "curse".
--- @param key string The boon or curse key.
--- @param level number|nil Its level, 1 when nil.
--- @param race string|nil Its race, for a rolled one. A random race when nil.
--- @param event string|boolean|nil The incident to show instead of the usual one, or false for none.
--- @returns boolean, table|nil True when the lord gained or raised something, and the entry that changed (nil while the full-slots dilemma asks).
function M.gain(character, kind, key, level, race, event)
    local config = data.by_key[kind][key]
    if not (config and M.enabled() and character:faction():is_human()) then return false end
    local entry = new_entry(config, level, race)
    local list = record_of(character)[kind]
    local carried = find(list, key, entry.race)
    if carried and config.charges then
        carried.charges = config.charges
        show(character, kind, carried)
        log("boons: lord " .. character:command_queue_index() .. " refreshes " .. key .. " to " .. config.charges .. " battles")
        return true, carried
    end
    if carried then return M.raise(character, kind, carried, event), carried end
    if #list < M.slots(kind) then
        add(character, kind, entry, event)
        return true, entry
    end
    if kind == "boon" then
        ask_full(character, entry)
        return true
    end
    local mildest = nil
    for _, curse in ipairs(list) do
        if curse.level < data.max_level and (mildest == nil or curse.level < mildest.level) then mildest = curse end
    end
    return mildest ~= nil and M.raise(character, kind, mildest, event), mildest
end

--- Resolves the full-slots dilemma: the chosen boon goes and the new one takes its slot, or the new one is refused.
--- @param faction_name string The faction that answered.
--- @param choice_key string The choice key.
function M.on_full_choice(faction_name, choice_key)
    local pending = M.pending[faction_name]
    M.pending[faction_name] = nil
    local character = pending and tower_army.character(tonumber(pending.cqi))
    if not character then return end
    if choice_key == data.full_new_choice then
        log("boons: lord " .. pending.cqi .. " refuses " .. M.bundle("boon", pending.entry))
        return
    end
    local slot = CHOICE_SLOT[choice_key]
    if slot then
        M.remove(character, "boon", slot, "boon_lost")
        add(character, "boon", pending.entry)
    end
end

--- Gives a faction a faction-wide boon or curse for `realm_turns` turns and says so.
--- @param faction_name string The faction.
--- @param key string The faction-wide key.
function M.gain_realm(faction_name, key)
    local config = data.realm_by_key[key]
    if not (config and M.enabled()) then return end
    M.realms[faction_name] = M.realms[faction_name] or {}
    M.realms[faction_name][key] = cm:turn_number() + data.realm_turns
    show_realm(faction_name, key, data.realm_turns)
    launch_line_incident(data.incident_prefix .. (config.good and "realm_boon" or "realm_curse"), data.line_prefix .. "realm_" .. key, cm:get_faction(faction_name))
    log("boons: " .. faction_name .. " gains " .. data.realm_prefix .. key .. " for " .. data.realm_turns .. " turns")
end

--- A random boon or curse that can drop from a source.
--- @param kind string "boon" or "curse".
--- @param source string A `drops` source, e.g. "treasure".
--- @param exclude table|nil Keys -> true that are not picked, e.g. one already given.
--- @returns string|nil The key, or nil when none drops there.
function M.pick(kind, source, exclude)
    local pool = {}
    for _, key in ipairs(DROP_POOLS[kind][source] or {}) do
        if not (exclude and exclude[key]) then pool[#pool + 1] = key end
    end
    return pool[1] and pool[random_number(#pool)] or nil
end

--- Gives a lord a random boon or curse that drops from a source.
--- @param character userdata The lord.
--- @param kind string "boon" or "curse".
--- @param source string A `drops` source.
--- @param level number|nil Its level, 1 when nil.
--- @returns boolean True when the lord gained or raised something.
function M.gain_from(character, kind, source, level)
    local key = M.pick(kind, source)
    return key ~= nil and M.gain(character, kind, key, level)
end

--- Gives a lord what an offer grants: `boon` and `curse` as { key, level }, or { from = a drop source, level, count } for `count` (1 when
--- nil) different random ones. A race boon or
--- curse (Bane, Grudge) is about the enemy's race when it is known, else a random one.
--- @param character userdata|nil The lord.
--- @param fields table The offer or outcome record.
--- @param enemy string|nil The enemy's faction shorthand, e.g. "emp".
function M.grant_fields(character, fields, enemy)
    local race = data.race_of_shorthand[enemy or ""]
    for _, kind in ipairs(KINDS) do
        local grant = fields[kind]
        if grant and character then
            if grant.from then
                local given = {}
                for _ = 1, grant.count or 1 do
                    local key = M.pick(kind, grant.from, given)
                    if key then
                        given[key] = true
                        M.gain(character, kind, key, grant.level or 1)
                    end
                end
            else
                M.gain(character, kind, grant[1], grant[2] or 1, race)
            end
        end
    end
end

--- Lifts a lord's worst curse, the one at the highest level, and says so.
--- @param character userdata The lord.
--- @returns boolean True when a curse was lifted.
function M.lift_worst_curse(character)
    local curses, worst = M.find_record(character).curse, nil
    for i, curse in ipairs(curses) do
        if worst == nil or curse.level > curses[worst].level then worst = i end
    end
    if worst == nil then return false end
    M.remove(character, "curse", worst, "curse_lifted")
    return true
end

--- True when an offer that touches boons and curses can be drawn: they are on, and one that lifts a curse finds the lord with one.
--- @param offer table The offer record: `boon`, `curse`, `fail_curse`, `lift_curse` or `cleanse`.
--- @param character userdata|nil The lord, for `lift_curse`.
--- @returns boolean True when it can be drawn.
function M.drawable(offer, character)
    if not (M.grants(offer) or offer.fail_curse or offer.lift_curse or offer.cleanse) then return true end
    if not M.enabled() then return false end
    return not offer.lift_curse or (character ~= nil and #M.find_record(character).curse > 0)
end

--- True when an offer grants a boon or a curse, so it is only drawn while boons and curses are on.
--- @param offer table The offer record.
--- @returns boolean True for such an offer.
function M.grants(offer)
    return offer.boon ~= nil or offer.curse ~= nil
end

--- Rolls one percent chance and logs it.
--- @param what string What the roll is for.
--- @param chance number The percent chance.
--- @returns boolean True on a hit.
local function roll(what, chance)
    local hit = random_chance(chance)
    log("boons: " .. what .. " roll at " .. chance .. "% " .. (hit and "hits" or "misses"))
    return hit
end

--- Lets a lord choose one of a few different boons that drop from a source, on the pick dilemma.
--- @param character userdata The lord.
--- @param source string A `drops` source, e.g. "tower".
--- @param count number How many boons to offer, at most one per pick choice.
--- @param level number|nil The level the chosen boon starts at, 1 when nil.
function M.offer_pick(character, source, count, level)
    level = level or 1
    if not (M.enabled() and character:faction():is_human()) then return end
    local pool = {}
    for i, key in ipairs(DROP_POOLS.boon[source] or {}) do pool[i] = key end
    local keys = {}
    for i, key in ipairs(randomic_shuffle(pool)) do
        if i <= math.min(count, #data.pick_choices) then keys[i] = key end
    end
    if #keys == 0 then return end
    local faction_name = character:faction():name()
    local choices = {}
    for i, key in ipairs(keys) do choices[i] = { key = data.pick_choices[i], lines = { M.line("boon", { key = key, level = level }) } } end
    M.picks[faction_name] = { cqi = tostring(character:command_queue_index()), keys = keys, level = level }
    common.set_context_value(data.lord_context, lord_name(character))
    log("boons: lord " .. character:command_queue_index() .. " chooses one of " .. table.concat(keys, ", ") .. " at level " .. level)
    dilemmas.launch(data.pick_dilemma, choices, faction_name)
end

--- Resolves the pick dilemma: the lord gains the chosen boon.
--- @param faction_name string The faction that answered.
--- @param choice_key string The choice key.
function M.on_pick_choice(faction_name, choice_key)
    local pick = M.picks[faction_name]
    M.picks[faction_name] = nil
    local character = pick and tower_army.character(tonumber(pick.cqi))
    local key = character and pick.keys[CHOICE_SLOT[choice_key] or 0]
    if key then M.gain(character, "boon", key, pick.level) end
end

--- After a LEAPOI fight: a hard or modified win may give the lord a boon, a loss may give a curse, and each of the fight's battle modifiers
--- may leave its boon or curse on the lord, each at its MCT chance.
--- @param character userdata|nil The human lord who fought.
--- @param won boolean True when the lord's side won.
--- @param difficulty string|nil The fight's difficulty.
--- @param modifiers table|nil The fight's battle modifier keys.
function M.on_leapoi_fight(character, won, difficulty, modifiers)
    if not M.enabled() then return end
    if not character then
        log("boons: no human lord found in the fight's record, so its result rolls nothing")
        return
    end
    local settings = get_mct_settings()
    local cqi = character:command_queue_index()
    local hard = difficulty == "hard" or #(modifiers or {}) > 0
    log("boons: lord " .. cqi .. " " .. (won and "won" or "lost") .. " a " .. tostring(difficulty) .. " LEAPOI fight with modifiers "
        .. table.concat(modifiers or {}, ", ") .. " (chances: win " .. settings[data.chance_settings.win] .. "%, loss " .. settings[data.chance_settings.loss]
        .. "%, linger " .. settings[data.chance_settings.linger] .. "%)")
    if won and hard and roll("win boon", settings[data.chance_settings.win]) then
        M.gain_from(character, "boon", "battle")
    elseif not won and roll("loss curse", settings[data.chance_settings.loss]) then
        M.gain_from(character, "curse", "battle")
    end
    for _, modifier in ipairs(modifiers or {}) do
        local linger = data.lingers[modifier]
        if linger and roll(modifier .. " linger", settings[data.chance_settings.linger]) then M.gain(character, linger[1], linger[2]) end
    end
end

--- After a won tower champion floor: a rare faction-wide blessing, or else a choice of tower boons for the delving lord.
--- @param character userdata The delving lord.
function M.on_champion_won(character)
    if not M.enabled() then return end
    if random_chance(data.champion_realm_chance) then
        M.gain_realm(character:faction():name(), data.blessings[random_number(#data.blessings)])
        return
    end
    M.offer_pick(character, "tower", data.champion_choices)
end

--- After a lost tower champion floor: a rare faction-wide curse on the delving faction.
--- @param faction_name string The delving faction.
function M.on_champion_lost(faction_name)
    if not M.enabled() then return end
    local hit = random_chance(data.champion_realm_chance)
    log("boons: " .. faction_name .. " lost to a tower champion, faction-wide curse roll at " .. data.champion_realm_chance .. "% " .. (hit and "hits" or "misses"))
    if hit then M.gain_realm(faction_name, data.realm_curses[random_number(#data.realm_curses)]) end
end

--- After a Tavern contract ends: a finished quest chain lets the lord choose a Tavern boon at `chain_boon_level`, a bounty gives Bane of the
--- hunted army's race, a cull may give a Tavern boon at the win chance, and a failed or dropped contract may give a Tavern curse at the loss
--- chance. A lost contract battle has already rolled its
--- own curse, so this only rolls when the contract itself ends.
--- @param character userdata|nil The lord who took the contract.
--- @param kind string The contract kind, e.g. "bounty" or "chain".
--- @param enemy string|nil The hunted army's faction shorthand.
--- @param succeeded boolean True when the contract was completed.
function M.on_contract_ended(character, kind, enemy, succeeded)
    if not (character and M.enabled()) then return end
    local settings = get_mct_settings()
    if succeeded and kind == "chain" then
        M.offer_pick(character, "tavern", #data.pick_choices, data.chain_boon_level)
    elseif succeeded and kind == "bounty" then
        M.gain(character, "boon", "bane", 1, data.race_of_shorthand[enemy or ""])
    elseif succeeded and kind == "cull" then
        if roll("cull boon", settings[data.chance_settings.win]) then M.gain_from(character, "boon", "tavern") end
    elseif not succeeded and random_chance(settings[data.chance_settings.loss]) then
        M.gain_from(character, "curse", "tavern")
    end
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Time and battles

--- After a lord's battle: each charged boon spends a battle and ends on its last, and on a win every other boon counts it, rising a level
--- every `wins_per_level` wins.
--- @param character userdata The lord.
--- @param won boolean True when the lord won.
function M.on_battle_completed(character, won)
    local record = M.lords[tostring(character:command_queue_index())]
    if not record then return end
    for i = #record.boon, 1, -1 do
        local boon = record.boon[i]
        if boon.charges then
            boon.charges = boon.charges - 1
            if boon.charges <= 0 then M.remove(character, "boon", i, "boon_lost") else show(character, "boon", boon) end
        elseif won then
            M.add_wins(character, boon, 1)
        end
    end
end

--- Turns one curse that has been at its worst long enough into its boon, keeping its race.
--- @param character userdata The lord.
--- @param index number The curse's slot.
local function turn_curse(character, index)
    local curse = record_of(character).curse[index]
    notify("curse_turned", character, "curse", curse)
    M.remove(character, "curse", index, nil)
    M.gain(character, "boon", data.by_key.curse[curse.key].turns_into, 1, curse.race)
end

--- Counts down a faction's faction-wide boons and curses: each one with turns left gets its clock moved on, and a finished one comes off.
--- @param faction_name string The faction whose turn starts.
local function tick_realms(faction_name)
    local turn = cm:turn_number()
    for key, ends in pairs(M.realms[faction_name] or {}) do
        local left = ends - turn
        if left > 0 then
            show_realm(faction_name, key, left)
            log("boons: " .. faction_name .. "'s " .. data.realm_prefix .. key .. " has " .. left .. " turns left")
        else
            show_realm(faction_name, key, nil)
            M.realms[faction_name][key] = nil
            log("boons: " .. faction_name .. "'s " .. data.realm_prefix .. key .. " has run out")
        end
    end
end

--- At a human faction's turn start: forgets lords who are gone, moves every curse on a turn, puts every bundle back on with its clock moved
--- on (and any a lord lost), and counts down the faction-wide ones.
--- @param faction_name string The faction whose turn starts.
function M.on_faction_turn_start(faction_name)
    local needed = turns_per_level()
    for cqi, record in pairs(M.lords) do
        if record.faction == faction_name then
            local character = tower_army.character(tonumber(cqi))
            if not character or character:faction():name() ~= faction_name then
                log("boons: lord " .. cqi .. " is gone, dropping " .. #record.boon .. " boons and " .. #record.curse .. " curses")
                M.lords[cqi] = nil
            else
                for i = #record.curse, 1, -1 do
                    local curse = record.curse[i]
                    curse.turns = curse.turns + 1
                    if curse.level < data.max_level then
                        if curse.turns >= needed then M.raise(character, "curse", curse) end
                    elseif data.by_key.curse[curse.key].turns_into and curse.turns >= data.turns_to_turn then
                        turn_curse(character, i)
                    end
                end
                local clocks = {}
                for _, kind in ipairs(KINDS) do
                    for _, entry in ipairs(record[kind]) do
                        show(character, kind, entry)
                        clocks[#clocks + 1] = entry.shown
                    end
                end
                if #clocks > 0 then log("boons: lord " .. cqi .. " clocks: " .. table.concat(clocks, ", ")) end
            end
        end
    end
    tick_realms(faction_name)
end

--- Gives every lord of the human factions the debug `grant_boons` and `grant_curses` they do not carry yet.
local function grant_debug()
    for _, faction_name in ipairs(cm:get_human_factions()) do
        each_army(cm:get_faction(faction_name), function(force)
            local general = force:general_character()
            for kind, keys in pairs({ boon = debug_config.grant_boons, curse = debug_config.grant_curses }) do
                for _, key in ipairs(keys) do
                    local carried = false
                    for _, entry in ipairs(record_of(general)[kind]) do carried = carried or entry.key == key end
                    if not carried then M.gain(general, kind, key, 1) end
                end
            end
        end)
    end
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Listeners and saving

--- Registers the battle, full-slots and pick dilemma listeners, and the debug grants on load. Only lords with a record count their battles.
function M.register()
    core:add_listener("land_enc_boons_battle_completed", "CharacterCompletedBattle",
        function(context) return M.lords[tostring(context:character():command_queue_index())] ~= nil end,
        function(context) M.on_battle_completed(context:character(), context:character():won_battle()) end, true)
    core:add_listener("land_enc_boons_pick_choice", "DilemmaChoiceMadeEvent",
        function(context) return context:dilemma() == data.pick_dilemma end,
        function(context) M.on_pick_choice(context:faction():name(), context:choice_key()) end, true)
    core:add_listener("land_enc_boons_full_choice", "DilemmaChoiceMadeEvent",
        function(context) return context:dilemma() == data.full_dilemma end,
        function(context) M.on_full_choice(context:faction():name(), context:choice_key()) end, true)
    if debug_config.grant_boons[1] or debug_config.grant_curses[1] then cm:add_first_tick_callback(grant_debug) end
end

--- Exports the lords' boons and curses, the faction-wide ones' end turns, and any open full-slots or pick question for the save file.
--- @returns table The state.
function M.export_state()
    return { lords = M.lords, pending = M.pending, picks = M.picks, realms = M.realms }
end

--- Restores the lords' boons and curses from the save file. A save from before boons restores none.
--- @param saved table|nil The saved state.
function M.restore_state(saved)
    saved = saved or {}
    M.lords = saved.lords or {}
    M.pending = saved.pending or {}
    M.picks = saved.picks or {}
    M.realms = saved.realms or {}
end

return M
