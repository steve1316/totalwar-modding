--- Smith's Commissions: a player faction that owns a Smithy is now and then offered a commission by its highest-level Smithy, tracked as a
--- mission in the vanilla missions panel. Blood the Steel asks for a kill count, Test the Steel for beaten armies of the nearest enemy, and
--- Fetch Star-Metal for a won battle at a marked spot near the Smithy (core/marked_spots.lua). The reward is rolled when it is issued and paid
--- by the mission itself, and failing costs nothing. A faction holds one at a time. features/smithy.lua saves them with the Smithies and
--- routes their events here. Functions that act on the map take the SmithyEventDelegate, to find a Smithy and reach the mission and invasion
--- battle managers.

require("script/land_encounters/utils/common")
require("script/land_encounters/utils/random")

local smithy_data = require("script/land_encounters/configs/smithy_data")
local debug_config = require("script/land_encounters/configs/debug")
local item_pool = require("script/land_encounters/core/item_pool")
local realm_effects = require("script/land_encounters/core/realm_effects")
local marked_spots = require("script/land_encounters/core/marked_spots")
local battle_modifiers = require("script/land_encounters/features/battle_modifiers")
local Army = require("script/land_encounters/core/army")

local M = {
    --- Faction key -> its commission: { key, kind, zone, index, level, item, target, battle_event }. `target` is Test the Steel's enemy
    --- faction, and `battle_event` the Fetch Star-Metal army's event while its battle is being fought.
    held_by_faction = {},
}

--- Event a Fetch Star-Metal mark fires when a lord walks onto it.
M.MARK_ENTERED_EVENT = "ScriptEventLeapoiSmithyMarkEntered"

--- Event that steps a mark to its next marker. Nothing listens for it: the mission's own deadline fails the commission.
local MARK_COUNTDOWN_EVENT = "ScriptEventLeapoiSmithyMarkCountdown"

--- Marker key prefix of a Fetch Star-Metal mark, followed by the faction.
local MARK_PREFIX = "leapoi_smithy_mark_"

--- Objective text of Fetch Star-Metal's scripted objective.
local MARK_TEXT = "mission_text_text_land_enc_smithy_star_metal"

--- The commissions config.
local data = smithy_data.commissions

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Helpers

--- True for a mission key a Smithy issues.
--- @param key string The mission key.
--- @returns boolean True for a commission.
function M.is_commission(key)
    return key:sub(1, #data.mission_prefix) == data.mission_prefix
end

--- A faction's Fetch Star-Metal mark key.
--- @param faction_name string The faction key.
--- @returns string The mark, e.g. leapoi_smithy_mark_<faction>.
local function mark_of(faction_name)
    return MARK_PREFIX .. faction_name
end

--- The reward rolled for a commission: a legendary item at the level's `legendary_chance`, otherwise an item of its `reward_rarities`.
--- @param faction_name string The faction it is for.
--- @param level number The issuing Smithy's level.
--- @returns string|nil The item's key, or nil when none is left for the faction.
local function roll_reward(faction_name, level)
    local entry = data.levels[level]
    local item = entry.legendary_chance > 0 and random_chance(entry.legendary_chance) and item_pool.pick_legendary_item(faction_name)
    return item or item_pool.pick_items(faction_name, entry.reward_rarities, 1)[1]
end

--- The army a Fetch Star-Metal battle is fought against: a random faction's, at the issuing Smithy's level, with no battle modifiers.
--- @param faction_name string The faction that holds the commission.
--- @param held table The commission.
--- @returns table The `Army:new_from_event` event, kept so the army can be built again after a load.
local function army_event(faction_name, held)
    local identifier = "smithy_" .. held.key .. "_" .. faction_name
    return { dilemma = "smithy_commission", faction = get_random_faction(), difficulty = DIFFICULTY_KEYS[held.level], intervention = INTERCEPTION_TYPE,
        force_identifier = identifier .. "_force", invasion_identifier = identifier, modifiers = {}, composition = battle_modifiers.composition({}),
        enemy_bundles = battle_modifiers.bundles({}, "enemy") }
end

--- Clears a faction's Fetch Star-Metal mark, when its commission has one.
--- @param faction_name string The faction key.
--- @param held table The commission.
local function clear_mark(faction_name, held)
    if held.kind == "fetch_star_metal" then marked_spots.clear(mark_of(faction_name)) end
end

--- Waits for a Fetch Star-Metal battle and hands its result to `on_mark_battle`. Used when the battle starts and again after a load.
--- @param delegate SmithyEventDelegate The Smithy delegate.
--- @param faction_name string The faction fighting.
--- @param key string The commission's mission key.
--- @param army Army The army fought.
local function await_battle(delegate, faction_name, key, army)
    delegate.invasion_battle_manager:await_battle({ trigger_event_given_battle_result = function(_, won) M.on_mark_battle(delegate, faction_name, key, won) end },
        "SmithySpot", nil, army)
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Issuing

--- Issues a commission's mission: its objective, the rolled reward, its deadline and the Smithy's position to zoom to.
--- @param delegate SmithyEventDelegate The Smithy delegate.
--- @param faction_name string The faction it is for.
--- @param smithy SmithyState The issuing Smithy.
--- @param kind table The kind, from `data.kinds`.
--- @param held table The commission, with its `key` and `item`.
--- @param objective string The objective type, e.g. "KILL_X_ENTITIES", or "SCRIPTED" for Fetch Star-Metal.
--- @param conditions table The objective's conditions, e.g. { "total 2500" }.
local function issue(delegate, faction_name, smithy, kind, held, objective, conditions)
    local mm = delegate.mission_manager:new(faction_name, held.key)
    mm:set_mission_issuer(data.issuer)
    if objective == "SCRIPTED" then
        --- The objective never completes by itself: winning the mark's battle completes it (see `M.on_mark_battle`).
        mm:add_new_scripted_objective(MARK_TEXT, M.MARK_ENTERED_EVENT, function() return false end, held.key)
    else
        mm:add_new_objective(objective)
        for _, condition in ipairs(conditions) do mm:add_condition(condition) end
    end
    mm:add_payload("add_ancillary_to_faction_pool{ancillary_key " .. held.item .. ";}")
    mm:set_turn_limit(kind.turns)
    mm:set_position(smithy.coordinates[1], smithy.coordinates[2])
    mm:set_should_whitelist(false)
    mm:trigger()
    M.held_by_faction[faction_name] = held
    log("smithy: " .. faction_name .. " gets the commission " .. held.key .. " (" .. objective .. " " .. table.concat(conditions, ", ") .. ") from the "
        .. smithy:describe() .. ", reward " .. held.item .. ", " .. kind.turns .. " turns")
end

--- Kind key -> its start: checks the kind can run for this faction and Smithy, and returns its objective and conditions, or nil when it
--- cannot. Blood the Steel always can, and pays a named item on its own mission to a subculture that has them. Test the Steel needs an enemy
--- at war with the faction. Fetch Star-Metal needs room for its mark, kept on `mark_at` until it is placed.
--- @param faction faction The faction it is for.
--- @param smithy SmithyState The issuing Smithy.
--- @param level table The Smithy level's entry in `data.levels`.
--- @param held table The commission being built, which the start fills in.
--- @returns string|nil, table The objective type and its conditions.
local STARTS = {
    blood_the_steel = function(faction, smithy, level, held)
        local named = data.named[faction:subculture()]
        local pick = named and named[random_number(#named)]
        if pick then held.key, held.item = pick.mission, pick.ancillary end
        return "KILL_X_ENTITIES", { "total " .. level.kills }
    end,
    test_the_steel = function(faction, smithy, level, held)
        local enemy = realm_effects.nearest_enemy(faction, smithy.coordinates[1], smithy.coordinates[2])
        if not enemy then return nil end
        held.target = enemy:name()
        return "DEFEAT_N_ARMIES_OF_FACTION", { "total " .. level.armies, "faction " .. held.target }
    end,
    fetch_star_metal = function(faction, smithy, level, held)
        local x, y, region_key = marked_spots.spawn_point(smithy.coordinates, faction:name(), data.spawn_regions_away, data.spawn_distance)
        if not x then return nil end
        held.mark_at = { x, y, region_key }
        return "SCRIPTED", {}
    end,
}

--- Tries to start one kind of commission: its start's checks, then the reward (unless it pays a named item), then Fetch Star-Metal's mark.
--- @param delegate SmithyEventDelegate The Smithy delegate.
--- @param faction faction The faction it is for.
--- @param smithy SmithyState The issuing Smithy.
--- @param kind table The kind, from `data.kinds`.
--- @returns boolean True when it was issued.
local function try_kind(delegate, faction, smithy, kind)
    local faction_name = faction:name()
    local held = { key = data.mission_prefix .. kind.key, kind = kind.key, zone = smithy.zone_name, index = smithy.index_in_zone, level = smithy.level }
    local objective, conditions = STARTS[kind.key](faction, smithy, data.levels[smithy.level], held)
    if not objective then return false end
    held.item = held.item or roll_reward(faction_name, smithy.level)
    if not held.item then return false end
    local mark_at = held.mark_at
    held.mark_at = nil
    if mark_at then
        marked_spots.place(mark_of(faction_name), faction_name, mark_at[1], mark_at[2], kind.turns, M.MARK_ENTERED_EVENT, MARK_COUNTDOWN_EVENT)
        log("smithy: " .. faction_name .. "'s Fetch Star-Metal mark is in " .. mark_at[3] .. " at (" .. mark_at[1] .. ", " .. mark_at[2] .. ")")
    end
    issue(delegate, faction_name, smithy, kind, held, objective, conditions)
    if mark_at then show_located_message(faction_name, "smithy_star_metal_spotted", { mark_at[1], mark_at[2] }) end
    return true
end

--- Offers a faction a commission from a Smithy: the kind in the debug `smithy_commission_kind` switch, else a random kind that can start.
--- @param delegate SmithyEventDelegate The Smithy delegate.
--- @param faction_name string The faction it is for.
--- @param smithy SmithyState The issuing Smithy.
--- @returns boolean True when one was issued.
function M.offer(delegate, faction_name, smithy)
    local faction = cm:get_faction(faction_name)
    local forced = debug_config.smithy_commission_kind[1]
    local kinds = {}
    for _, kind in ipairs(data.kinds) do
        if forced == nil or kind.key == forced then kinds[#kinds + 1] = kind end
    end
    for _, kind in ipairs(randomic_shuffle(kinds)) do
        if try_kind(delegate, faction, smithy, kind) then return true end
    end
    log("smithy: no commission could start for " .. faction_name .. " at the " .. smithy:describe())
    return false
end

--- Offers a commission to each human faction that holds none, from its highest-level Smithy, on turns that are a multiple of the MCT
--- `smithy_mission_interval`, or on every round while the debug `smithy_commission_now` switch is on. Runs once per round.
--- @param delegate SmithyEventDelegate The Smithy delegate.
function M.tick(delegate)
    local now = debug_config.smithy_commission_now[1]
    if not now and cm:turn_number() % get_mct_settings().smithy_mission_interval ~= 0 then return end
    for _, faction_name in ipairs(cm:get_human_factions()) do
        if not M.held_by_faction[faction_name] then
            local best = nil
            for _, smithy in ipairs(delegate.smithies_state) do
                if not smithy.disabled and smithy:is_occupied_by_same_faction(faction_name) and (best == nil or smithy.level > best.level) then best = smithy end
            end
            if best then M.offer(delegate, faction_name, best) end
        end
    end
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Fetch Star-Metal battles

--- A lord walked onto a Fetch Star-Metal mark: when it is their faction's, the battle starts there against an army at the Smithy's level.
--- @param delegate SmithyEventDelegate The Smithy delegate.
--- @param character character The lord.
--- @param marker_ref string The marker type's key, e.g. leapoi_smithy_mark_<faction>_2.
--- @param instance_ref string The marker's instance, to find where it stands.
function M.on_mark_entered(delegate, character, marker_ref, instance_ref)
    local faction_name = character:faction():name()
    local prefix = mark_of(faction_name) .. "_"
    local held = M.held_by_faction[faction_name]
    if marker_ref:sub(1, #prefix) ~= prefix or not held or held.kind ~= "fetch_star_metal" or held.battle_event then return end
    local x, y = Interactive_Marker_Manager:get_coords_from_instance_ref(instance_ref)
    local ibm = delegate.invasion_battle_manager
    local event = army_event(faction_name, held)
    local army = Army:new_from_event(event, character:faction():subculture())
    if not ibm:can_generate_battle(army, { x, y }) then
        log("smithy: no room for the battle at " .. faction_name .. "'s Fetch Star-Metal mark")
        return
    end
    held.battle_event = event
    log("smithy: " .. faction_name .. " fights for the star-metal against a " .. event.difficulty .. " army of " .. event.faction)
    ibm:generate_battle(army, character, { x, y })
    await_battle(delegate, faction_name, held.key, army)
end

--- Settles a Fetch Star-Metal battle: a win completes the mission's objective (whose success event then pays it out) and clears the mark. A
--- loss leaves the mark in place to try again before the deadline.
--- @param delegate SmithyEventDelegate The Smithy delegate.
--- @param faction_name string The faction that fought.
--- @param key string The commission's mission key.
--- @param won boolean True when the faction won.
function M.on_mark_battle(delegate, faction_name, key, won)
    --- A battle no longer awaited (backed out of, and cleared at turn start) is someone else's.
    local held = M.held_by_faction[faction_name]
    if not held or held.key ~= key or not held.battle_event then return end
    held.battle_event = nil
    log("smithy: the Fetch Star-Metal battle of " .. faction_name .. " was " .. (won and "won" or "lost"))
    if not won then
        local index = delegate:find_index(held.zone, held.index)
        if index then delegate.smithies_state[index]:show_message(faction_name, "smithy_star_metal_repelled") end
        return
    end
    clear_mark(faction_name, held)
    cm:complete_scripted_mission_objective(faction_name, key, key, true)
end

--- After a load, waits again for any Fetch Star-Metal battle that was in flight when the game was saved.
--- @param delegate SmithyEventDelegate The Smithy delegate.
function M.rearm_battles(delegate)
    for faction_name, held in pairs(M.held_by_faction) do
        if held.battle_event then
            local army = Army:new_from_event(held.battle_event, nil)
            delegate.invasion_battle_manager:set_auxiliary_army_for_reset(army)
            await_battle(delegate, faction_name, held.key, army)
            log("smithy: waiting again for " .. faction_name .. "'s Fetch Star-Metal battle")
        end
    end
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Ending

--- Forgets a faction's commission whose mission ended, and clears its mark. The mission's payload already paid the reward on success.
--- @param faction_name string The faction whose mission ended.
--- @param key string The mission key.
--- @param outcome string "succeeded", "failed" or "cancelled".
function M.on_mission_ended(faction_name, key, outcome)
    local held = M.held_by_faction[faction_name]
    if not held or held.key ~= key then return end
    M.held_by_faction[faction_name] = nil
    clear_mark(faction_name, held)
    log("smithy: " .. faction_name .. "'s commission " .. key .. " " .. outcome)
end

--- At a faction's turn start, a Fetch Star-Metal battle backed out of no longer blocks the mark, and a commission that can no longer be met
--- (its mission is not active, or Test the Steel's enemy is gone) is dropped, so a new one can be offered.
--- @param faction_name string The faction whose turn starts.
function M.on_faction_turn_start(faction_name)
    local held = M.held_by_faction[faction_name]
    if not held then return end
    held.battle_event = nil
    local active = cm:mission_is_active_for_faction(cm:get_faction(faction_name), held.key)
    local target_gone = false
    if held.target then
        local target = cm:get_faction(held.target)
        target_gone = not target or target:is_dead()
    end
    if active and not target_gone then return end
    log("smithy: " .. faction_name .. "'s commission " .. held.key .. (active and " lost its enemy " .. held.target or " has no active mission") .. ", so it is dropped")
    M.held_by_faction[faction_name] = nil
    clear_mark(faction_name, held)
    if active then cm:cancel_custom_mission(faction_name, held.key) end
end

--- Exports the commissions held for the save file.
--- @returns table { held_by_faction }.
function M.export_state()
    return { held_by_faction = M.held_by_faction }
end

--- Restores the commissions held from the save file. A save from before commissions restores none.
--- @param saved table|nil The saved state.
function M.restore_state(saved)
    saved = saved or {}
    M.held_by_faction = saved.held_by_faction or {}
end

return M
