--- Script-owned scroll drops for Kadon's Scrolls. The DB sets `randomly_dropped = false` on every scroll, so these hooks are the only way a
--- scroll enters a faction's item pool.

local creatures = require("script/jvj_kadon/creatures")
local settings = require("script/jvj_kadon/settings")

local M = {}

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Picking

--- Returns the keys from `keys` the faction may receive. Owned keys are skipped when `no_duplicate_scrolls` is on.
--- @param faction table Faction interface.
--- @param keys table Scroll keys of one creature and type.
--- @returns table The allowed keys, possibly empty.
local function available_keys(faction, keys)
    local result = {}
    for _, key in ipairs(keys) do
        if not (settings.values.no_duplicate_scrolls and faction:ancillary_exists(key)) then
            table.insert(result, key)
        end
    end
    return result
end

--- Builds the pickable pool for a faction. Each entry is one creature, holding one key list per allowed type that still has keys.
--- @param faction table Faction interface.
--- @returns table List of creatures, each a list of key lists.
function M.candidates(faction)
    local values = settings.values
    local pool = {}
    for _, creature in ipairs(creatures.list) do
        if values.enable_all_creatures or values.enabled_creatures[creature.id] then
            local types = {}
            if values.allow_kin then
                local keys = available_keys(faction, creature.kin)
                if #keys > 0 then table.insert(types, keys) end
            end
            if values.allow_bind then
                local keys = available_keys(faction, creature.bind)
                if #keys > 0 then table.insert(types, keys) end
            end
            if #types > 0 then table.insert(pool, types) end
        end
    end
    return pool
end

--- Picks one scroll: a creature first, then a type, then a key, each uniformly. Creature-first keeps every creature at equal odds.
--- @param faction table Faction interface.
--- @returns string|nil The scroll key, or nil when nothing is allowed.
function M.pick_scroll(faction)
    local pool = M.candidates(faction)
    if #pool == 0 then
        return nil
    end
    local types = pool[cm:random_number(#pool)]
    local keys = types[cm:random_number(#types)]
    return keys[cm:random_number(#keys)]
end

--- Picks a scroll and adds it to the faction's item pool.
--- @param faction table Faction interface.
--- @param source string Where the drop came from, for the log.
--- @returns string|nil The awarded key, or nil when nothing was allowed.
function M.award_scroll(faction, source)
    local key = M.pick_scroll(faction)
    if not key then
        out("jvj_kadon: no allowed scroll for " .. faction:name() .. " (" .. source .. "), skipping")
        return nil
    end
    cm:add_ancillary_to_faction(faction, key, false)
    out("jvj_kadon: " .. faction:name() .. " received " .. key .. " (" .. source .. ")")
    return key
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Conditions

--- Returns true when the faction may receive scrolls. Rebels never do. AI factions only when `ai_can_find_scrolls` is on.
--- @param faction table Faction interface.
--- @returns boolean Whether the faction may receive scrolls.
function M.faction_allowed(faction)
    if faction:is_rebel() then
        return false
    end
    return settings.values.ai_can_find_scrolls or faction:is_human()
end

--- Rolls a percent chance. A chance of 0 never rolls.
--- @param chance number Percent from 0 to 100.
--- @returns boolean Whether the roll passed.
function M.roll(chance)
    return chance > 0 and cm:random_number(100) <= chance
end

--- Returns true when `character` is the battle's primary attacker or defender general and neither side is a quest battle faction.
--- @param character table Character interface from `CharacterCompletedBattle`.
--- @returns boolean Whether this character's win can drop a scroll.
function M.is_scroll_battle(character)
    local attacker_cqi, _, attacker_name = cm:pending_battle_cache_get_attacker(1)
    local defender_cqi, _, defender_name = cm:pending_battle_cache_get_defender(1)
    local attacker = attacker_name and cm:get_faction(attacker_name)
    local defender = defender_name and cm:get_faction(defender_name)
    if (attacker and attacker:is_quest_battle_faction()) or (defender and defender:is_quest_battle_faction()) then
        return false
    end
    local cqi = character:command_queue_index()
    return cqi == attacker_cqi or cqi == defender_cqi
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Hooks

--- Picks the starting scroll. A creature chosen in `starting_scroll_creature` wins over the creature toggles, but the Kin / Binding toggles
--- still apply. "random", or an id no creature has, falls back to a normal random pick.
--- @param faction table Faction interface.
--- @returns string|nil The scroll key, or nil when nothing is allowed.
function M.pick_starting_scroll(faction)
    local chosen = creatures.find(settings.values.starting_scroll_creature)
    if not chosen then
        return M.pick_scroll(faction)
    end
    local types = {}
    if settings.values.allow_kin then table.insert(types, chosen.kin) end
    if settings.values.allow_bind then table.insert(types, chosen.bind) end
    if #types == 0 then
        return nil
    end
    local keys = types[cm:random_number(#types)]
    return keys[cm:random_number(#keys)]
end

--- Gives each human faction leader one allowed scroll, equipped. Does nothing unless `starting_scroll` is on.
function M.give_starting_scrolls()
    if not settings.values.starting_scroll then
        return
    end
    for _, faction_key in ipairs(cm:get_human_factions()) do
        local faction = cm:get_faction(faction_key)
        if faction and faction:has_faction_leader() then
            local key = M.pick_starting_scroll(faction)
            if key then
                cm:force_add_ancillary(faction:faction_leader(), key, true, false)
                out("jvj_kadon: " .. faction_key .. " leader starts with " .. key)
            end
        end
    end
end

--- Registers the battle and mission drop listeners and the new-campaign starting-scroll callback.
function M.register_listeners()
    core:add_listener(
        "jvj_kadon_battle_drop",
        "CharacterCompletedBattle",
        function(context)
            local character = context:character()
            return character:won_battle() and M.faction_allowed(character:faction()) and M.is_scroll_battle(character)
        end,
        function(context)
            if M.roll(settings.values.battle_drop_chance) then
                M.award_scroll(context:character():faction(), "battle")
            end
        end,
        true
    )

    core:add_listener(
        "jvj_kadon_mission_drop",
        "MissionSucceeded",
        function(context)
            return M.faction_allowed(context:faction())
        end,
        function(context)
            if M.roll(settings.values.mission_drop_chance) then
                M.award_scroll(context:faction(), "mission")
            end
        end,
        true
    )

    cm:add_first_tick_callback_new(M.give_starting_scrolls)
end

return M
