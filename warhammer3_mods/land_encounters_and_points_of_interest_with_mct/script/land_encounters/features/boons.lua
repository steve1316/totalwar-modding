--- Boons and curses (configs/boons.lua): lasting effects a human faction's lords carry. A boon grows a level every few battles the lord wins,
--- a curse gets worse every few turns until it is cleansed, and a few curses endured at their worst turn into a boon. Each boon or curse
--- level is a bundle on the lord. Rare faction-wide ones are plain faction bundles that run out by themselves. AI lords get none.

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
    --- worst level) }.
    lords = {},
    --- Faction key -> the boon waiting on the full-slots dilemma: { cqi, entry }.
    pending = {},
    --- Faction key -> the boons offered on the pick dilemma: { cqi, keys }.
    picks = {},
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

--- The name of one boon or curse at its level without a prefix, e.g. bane_dwarfs_3. Its bundle and its payload line are built from it.
--- @param entry table The entry.
--- @returns string The stem.
local function stem(entry)
    return entry.key .. (entry.race and "_" .. entry.race or "") .. "_" .. entry.level
end

--- The bundle of one boon or curse at its level, e.g. land_enc_effect_boon_bane_dwarfs_3.
--- @param kind string "boon" or "curse".
--- @param entry table The entry.
--- @returns string The bundle key.
function M.bundle(kind, entry)
    return data.bundle_prefix[kind] .. stem(entry)
end

--- The payload line that names one boon or curse at its level, e.g. dummy_land_enc_boon_bloodsworn_3.
--- @param kind string "boon" or "curse".
--- @param entry table The entry.
--- @returns string The payload line key.
function M.line(kind, entry)
    return data.line_prefix .. kind .. "_" .. stem(entry)
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
        payload:text_display(line)
        builder:set_payload(payload)
        cm:launch_custom_incident_from_builder(builder, faction)
    end)
    if not ok then log("boons: incident " .. incident .. " failed: " .. tostring(err)) end
    return ok
end

--- Tells the player about one of a lord's boons or curses with an incident that shows its line and names the lord.
--- @param event string The incident's event, e.g. "boon_grew".
--- @param character userdata The lord.
--- @param kind string "boon" or "curse".
--- @param entry table The entry.
local function notify(event, character, kind, entry)
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

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Changes

--- Raises a boon or worsens a curse one level, up to the top, and says so: the old level's bundle comes off and the new one goes on.
--- @param character userdata The lord.
--- @param kind string "boon" or "curse".
--- @param entry table The entry.
--- @returns boolean True when it rose.
function M.raise(character, kind, entry)
    if entry.level >= data.max_level or entry.charges then return false end
    cm:remove_effect_bundle_from_character(M.bundle(kind, entry), character)
    entry.level, entry.wins, entry.turns = entry.level + 1, 0, 0
    cm:apply_effect_bundle_to_character(M.bundle(kind, entry), character, 0)
    notify(kind == "boon" and "boon_grew" or "curse_worse", character, kind, entry)
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
    cm:remove_effect_bundle_from_character(M.bundle(kind, entry), character)
    if event then notify(event, character, kind, entry) end
end

--- Puts a new entry in a lord's free slot and says so.
--- @param character userdata The lord.
--- @param kind string "boon" or "curse".
--- @param entry table The entry.
local function add(character, kind, entry)
    local list = record_of(character)[kind]
    list[#list + 1] = entry
    cm:apply_effect_bundle_to_character(M.bundle(kind, entry), character, 0)
    notify(kind .. "_gained", character, kind, entry)
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
--- @returns boolean True when the lord gained or raised something.
function M.gain(character, kind, key, level, race)
    local config = data.by_key[kind][key]
    if not (config and M.enabled() and character:faction():is_human()) then return false end
    race = config.race and (race or data.races[random_number(#data.races)]) or nil
    local list = record_of(character)[kind]
    local carried = find(list, key, race)
    if carried and config.charges then
        carried.charges = config.charges
        log("boons: lord " .. character:command_queue_index() .. " refreshes " .. key .. " to " .. config.charges .. " battles")
        return true
    end
    if carried then return M.raise(character, kind, carried) end
    local entry = { key = key, level = math.min(level or 1, data.max_level), race = race, wins = 0, turns = 0, charges = config.charges }
    if #list < M.slots(kind) then
        add(character, kind, entry)
        return true
    end
    if kind == "boon" then
        ask_full(character, entry)
        return true
    end
    local mildest = nil
    for _, curse in ipairs(list) do
        if curse.level < data.max_level and (mildest == nil or curse.level < mildest.level) then mildest = curse end
    end
    return mildest ~= nil and M.raise(character, kind, mildest)
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
    cm:apply_effect_bundle(data.realm_prefix .. key, faction_name, data.realm_turns)
    launch_line_incident(data.incident_prefix .. (config.good and "realm_boon" or "realm_curse"), data.line_prefix .. "realm_" .. key, cm:get_faction(faction_name))
    log("boons: " .. faction_name .. " gains " .. data.realm_prefix .. key .. " for " .. data.realm_turns .. " turns")
end

--- A random boon or curse that can drop from a source.
--- @param kind string "boon" or "curse".
--- @param source string A `drops` source, e.g. "treasure".
--- @returns string|nil The key, or nil when none drops there.
function M.pick(kind, source)
    local pool = DROP_POOLS[kind][source]
    return pool and pool[random_number(#pool)] or nil
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

--- Gives a lord what an offer grants: `boon` and `curse` as { key, level } or { from = a drop source } for a random one.
--- @param character userdata|nil The lord.
--- @param fields table The offer or outcome record.
function M.grant_fields(character, fields)
    for _, kind in ipairs(KINDS) do
        local grant = fields[kind]
        if grant and character then
            if grant.from then M.gain_from(character, kind, grant.from) else M.gain(character, kind, grant[1], grant[2] or 1) end
        end
    end
end

--- True when an offer grants a boon or a curse, so it is only drawn while boons and curses are on.
--- @param offer table The offer record.
--- @returns boolean True for such an offer.
function M.grants(offer)
    return offer.boon ~= nil or offer.curse ~= nil
end

--- Lets a lord choose one of a few different boons that drop from a source, on the pick dilemma.
--- @param character userdata The lord.
--- @param source string A `drops` source, e.g. "tower".
--- @param count number How many boons to offer, at most one per pick choice.
function M.offer_pick(character, source, count)
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
    for i, key in ipairs(keys) do choices[i] = { key = data.pick_choices[i], lines = { M.line("boon", { key = key, level = 1 }) } } end
    M.picks[faction_name] = { cqi = tostring(character:command_queue_index()), keys = keys }
    common.set_context_value(data.lord_context, lord_name(character))
    log("boons: lord " .. character:command_queue_index() .. " chooses one of " .. table.concat(keys, ", "))
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
    if key then M.gain(character, "boon", key) end
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
    local hard = difficulty == "hard" or next(modifiers or {}) ~= nil
    log("boons: lord " .. cqi .. " " .. (won and "won" or "lost") .. " a " .. tostring(difficulty) .. " LEAPOI fight with modifiers "
        .. table.concat(modifiers or {}, ", ") .. " (chances: win " .. settings[data.chance_settings.win] .. "%, loss " .. settings[data.chance_settings.loss]
        .. "%, linger " .. settings[data.chance_settings.linger] .. "%)")
    --- Rolls one chance and logs it.
    --- @param what string What the roll is for.
    --- @param chance number The percent chance.
    --- @returns boolean True on a hit.
    local function roll(what, chance)
        local hit = random_chance(chance)
        log("boons: " .. what .. " roll at " .. chance .. "% " .. (hit and "hits" or "misses"))
        return hit
    end
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

--- After a Tavern contract ends: a finished quest chain gives a Tavern boon at `chain_boon_level`, a bounty gives Bane of the hunted
--- army's race, and a failed or dropped contract may give a Tavern curse at the loss chance. A lost contract battle has already rolled its
--- own curse, so this only rolls when the contract itself ends.
--- @param character userdata|nil The lord who took the contract.
--- @param kind string The contract kind, e.g. "bounty" or "chain".
--- @param enemy string|nil The hunted army's faction shorthand.
--- @param succeeded boolean True when the contract was completed.
function M.on_contract_ended(character, kind, enemy, succeeded)
    if not (character and M.enabled()) then return end
    if succeeded and kind == "chain" then
        M.gain_from(character, "boon", "tavern", data.chain_boon_level)
    elseif succeeded and kind == "bounty" then
        M.gain(character, "boon", "bane", 1, data.race_of_shorthand[enemy or ""])
    elseif not succeeded and random_chance(get_mct_settings()[data.chance_settings.loss]) then
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
    local wins_per_level = debug_config.boon_wins_per_level[1] or data.wins_per_level
    for i = #record.boon, 1, -1 do
        local boon = record.boon[i]
        if boon.charges then
            boon.charges = boon.charges - 1
            if boon.charges <= 0 then M.remove(character, "boon", i, "boon_lost") end
        elseif won then
            boon.wins = boon.wins + 1
            if boon.wins >= wins_per_level then M.raise(character, "boon", boon) end
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

--- At a human faction's turn start: forgets lords who are gone, puts back any bundle a lord lost, and moves every curse on a turn.
--- @param faction_name string The faction whose turn starts.
function M.on_faction_turn_start(faction_name)
    local turns_per_level = debug_config.curse_turns_per_level[1] or data.turns_per_level
    for cqi, record in pairs(M.lords) do
        if record.faction == faction_name then
            local character = tower_army.character(tonumber(cqi))
            if not character or character:faction():name() ~= faction_name then
                log("boons: lord " .. cqi .. " is gone, dropping " .. #record.boon .. " boons and " .. #record.curse .. " curses")
                M.lords[cqi] = nil
            else
                for _, kind in ipairs(KINDS) do
                    for _, entry in ipairs(record[kind]) do
                        local bundle = M.bundle(kind, entry)
                        if not character:has_effect_bundle(bundle) then cm:apply_effect_bundle_to_character(bundle, character, 0) end
                    end
                end
                for i = #record.curse, 1, -1 do
                    local curse = record.curse[i]
                    curse.turns = curse.turns + 1
                    if curse.level < data.max_level then
                        if curse.turns >= turns_per_level then M.raise(character, "curse", curse) end
                    elseif data.by_key.curse[curse.key].turns_into and curse.turns >= data.turns_to_turn then
                        turn_curse(character, i)
                    end
                end
            end
        end
    end
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

--- Exports the lords' boons and curses and any open full-slots or pick question for the save file.
--- @returns table The state.
function M.export_state()
    return { lords = M.lords, pending = M.pending, picks = M.picks }
end

--- Restores the lords' boons and curses from the save file. A save from before boons restores none.
--- @param saved table|nil The saved state.
function M.restore_state(saved)
    saved = saved or {}
    M.lords = saved.lords or {}
    M.pending = saved.pending or {}
    M.picks = saved.picks or {}
end

return M
