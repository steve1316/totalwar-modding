--- Calls an encounter's allied army onto the field as soon as the battle starts, instead of after its reinforcement timer, then sends it at the enemy.
--- The campaign saves the ally's faction key under `land_enc_ally_arrives_now` just before an encounter battle that has an ally, and clears it after
--- the battle. Only AI armies of that faction are touched, so a key left over from an unfought battle cannot pick up another ally.
--- Units are called in small groups, each once the previous group is on the field. Calling them all at once makes units outside the
--- game's current entry group jump to the map centre and back.

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Config

--- svr key holding the encounter ally's faction key. Mirrored in script/land_encounters/core/managers.lua.
local ALLY_ARRIVES_NOW_SVR_KEY = "land_enc_ally_arrives_now"
--- How many ally units are called in at a time. The game brings forced units in about five at a time, so this stays below that.
local GROUP_SIZE = 4
--- How often the current group is checked for arrival, in ms.
local POLL_MS = 500
--- How long to wait for a group before calling the next one anyway, in ms.
local GROUP_TIMEOUT_MS = 15000
--- Wait after the last group is called before the first attack order, so the game's reinforcement entry does not replace it, in ms.
local ATTACK_DELAY_MS = 5000
--- How often each ally unit picks the closest enemy again, and contact is checked, in ms.
local REORDER_MS = 5000
--- How long the attack order is repeated before the ally goes back to the battle AI even without contact, in ms.
local ENGAGE_TIMEOUT_MS = 180000

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Helpers

--- Writes one line to the battle script log.
--- @param msg string The line to write.
local function log(msg)
    bm:out("[LEAPOI] " .. tostring(msg))
end

--- Collects every unit of the AI armies in one alliance, including their reinforcement sets. Player-controlled armies are left out.
--- @param alliance_id number The alliance to collect from.
--- @param faction_key string|nil Only collect armies of this faction. nil collects every AI army.
--- @returns table Flat list of script units.
local function collect_ai_units(alliance_id, faction_key)
    local units = {}
    local armies = bm:alliances():item(alliance_id):armies()
    for army_id = 1, bm:num_armies_in_alliance(alliance_id) do
        local army = armies:item(army_id)
        if not army:is_player_controlled() and (faction_key == nil or army:faction_key() == faction_key) then
            local sets = { bm:get_scriptunits_for_army(alliance_id, army_id) }
            for r = 1, bm:num_reinforcing_armies_for_army_in_alliance(alliance_id, army_id) or 0 do
                sets[#sets + 1] = bm:get_scriptunits_for_army(alliance_id, army_id, r)
            end
            for _, sunits in ipairs(sets) do
                if sunits then
                    for i = 1, sunits:count() do units[#units + 1] = sunits:item(i) end
                end
            end
        end
    end
    return units
end

--- True once a unit has entered the battlefield. CA's `has_deployed` is not used because it turns false while a unit is hidden in cover.
--- @param sunit table The script unit.
--- @returns boolean True when the unit is on the field or already out of the fight.
local function is_on_field(sunit)
    return sunit.unit:is_deployed() or is_routing_or_dead(sunit)
end

--- Returns the units in a flat list that are on the field and still fighting.
--- @param list table Flat list of script units.
--- @returns table The units that have deployed and are not routing or dead.
local function fighting_units(list)
    local fighting = {}
    for _, sunit in ipairs(list) do
        if sunit.unit:is_deployed() and not is_routing_or_dead(sunit) then fighting[#fighting + 1] = sunit end
    end
    return fighting
end

--- Checks whether any unit in a flat list is fighting in melee. CA's `num_units_engaged` is not used because it counts 0 for a plain list of script units.
--- @param list table Flat list of script units.
--- @returns boolean True when at least one unit is in melee.
local function any_in_melee(list)
    for _, sunit in ipairs(list) do
        if sunit.unit:is_in_melee() then return true end
    end
    return false
end

--- Sends the ally straight at the enemy army: every ally unit attacks the closest enemy unit, re-picking its target every `REORDER_MS`, until
--- any ally unit is in melee or `ENGAGE_TIMEOUT_MS` passes. The ally then goes back to the battle AI. CA's attack planner is not used, since it
--- led the ally off to the side of the enemy line to wait in cover.
--- @param ally table Flat list of the ally's script units.
local function send_ally_at_enemy(ally)
    local enemy = collect_ai_units(bm:get_non_player_alliance_num())
    local waited_ms, attacking = 0, false

    --- Stops the attack orders and gives the ally back to the battle AI.
    --- @param reason string Why, for the log.
    local function hand_back(reason)
        for _, sunit in ipairs(ally) do
            sunit:stop_attack_closest_enemy()
            sunit:release_control()
        end
        log(string.format("ally handed back to the battle AI after %d s: %s", waited_ms / 1000, reason))
    end

    --- Starts the attack orders once, then checks for contact until the ally engages or the timeout passes.
    local function check_contact()
        local attackers, targets = fighting_units(ally), fighting_units(enemy)
        local engaged = any_in_melee(attackers)
        if engaged or waited_ms >= ENGAGE_TIMEOUT_MS or #attackers == 0 or #targets == 0 then
            hand_back(engaged and "in contact with the enemy" or waited_ms >= ENGAGE_TIMEOUT_MS and "no contact" or "one side has no units left")
            return
        end
        if not attacking then
            for _, sunit in ipairs(attackers) do sunit:start_attack_closest_enemy(REORDER_MS) end
            attacking = true
        end
        local gap = centre_point_table(attackers):distance(centre_point_table(targets))
        log(string.format("t+%ds: ally attacking the closest enemies, %d units against %d, %.0f m apart", waited_ms / 1000, #attackers, #targets, gap))
        waited_ms = waited_ms + REORDER_MS
        bm:callback(check_contact, REORDER_MS)
    end
    bm:callback(check_contact, ATTACK_DELAY_MS)
end

--- Calls the ally in one group at a time. Each group is called once the previous one is on the field, or after `GROUP_TIMEOUT_MS`.
--- @param ally table Flat list of the ally's script units.
local function call_ally_in_groups(ally)
    local waiting = {}
    for _, sunit in ipairs(ally) do
        if not is_on_field(sunit) then waiting[#waiting + 1] = sunit end
    end
    log(string.format("calling %d of %d ally units in, %d at a time", #waiting, #ally, GROUP_SIZE))

    local next_index, group, waited_ms = 1

    --- Calls the next group in.
    --- @returns boolean False when every unit has already been called.
    local function call_next_group()
        if next_index > #waiting then return false end
        group, waited_ms = {}, 0
        for i = next_index, math.min(next_index + GROUP_SIZE - 1, #waiting) do
            waiting[i]:deploy_reinforcement(true)
            group[#group + 1] = waiting[i]
        end
        log(string.format("called ally units %d-%d", next_index, next_index + #group - 1))
        next_index = next_index + #group
        return true
    end

    --- Checks whether the current group has entered the field.
    --- @returns boolean True once every unit in the current group is on the field.
    local function group_arrived()
        for _, sunit in ipairs(group) do
            if not is_on_field(sunit) then return false end
        end
        return true
    end

    --- Polls the current group and moves on to the next one once it has arrived.
    local function poll()
        waited_ms = waited_ms + POLL_MS
        local arrived = group_arrived()
        if arrived or waited_ms >= GROUP_TIMEOUT_MS then
            if not arrived then log("group timed out, calling the next one") end
            if not call_next_group() then
                log("all ally units called in")
                send_ally_at_enemy(ally)
                return
            end
        end
        bm:callback(poll, POLL_MS)
    end

    if call_next_group() then
        bm:callback(poll, POLL_MS)
    else
        --- Every ally unit is already on the field.
        send_ally_at_enemy(ally)
    end
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Entry

local ally_faction_key = core:svr_load_string(ALLY_ARRIVES_NOW_SVR_KEY)
if ally_faction_key and ally_faction_key ~= "" then
    local ally = collect_ai_units(bm:get_player_alliance_num(), ally_faction_key)
    log("encounter battle with " .. #ally .. " units of ally " .. ally_faction_key .. ", skipping their reinforcement timer")
    if #ally > 0 then
        --- Reinforcements cannot enter while the deployment clock is paused, so the call waits for the battle to start.
        bm:register_phase_change_callback("Deployed", function() call_ally_in_groups(ally) end)
    end
end
