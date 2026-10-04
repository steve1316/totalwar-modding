--- Runs an encounter's allied army in battle. Two cases, each switched on by an svr key the campaign saves just before the battle and clears
--- after it:
--- `land_enc_ally_arrives_now` holds the ally's faction key: the ally is called onto the field as soon as the battle starts, instead of after its
--- reinforcement timer, then sent at the enemy. Only AI armies of that faction are touched, so a key left over from an unfought battle cannot
--- pick up another ally.
--- `land_enc_relief_column` holds a relief column's mode: the ally holds the field, the enemy charges it, and our army marches in as its
--- reinforcement. "scripted" calls our army in once the enemy reaches the ally (or at the latest arrival time), "charge_only" leaves our
--- arrival to the game.
--- Units are called in small groups, each once the previous group is on the field. Calling them all at once makes units outside the game's
--- current entry group jump to the map centre and back.

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Config

--- svr key holding the encounter ally's faction key. Mirrored in script/land_encounters/core/managers.lua.
local ALLY_ARRIVES_NOW_SVR_KEY = "land_enc_ally_arrives_now"
--- svr key holding a relief column's mode. Mirrored in script/land_encounters/core/managers.lua.
local RELIEF_COLUMN_SVR_KEY = "land_enc_relief_column"
--- How many units are called in at a time. The game brings forced units in about five at a time, so this stays below that.
local GROUP_SIZE = 4
--- How often the current group is checked for arrival, in ms.
local POLL_MS = 500
--- How long to wait for a group before calling the next one anyway, in ms.
local GROUP_TIMEOUT_MS = 15000
--- Wait after the ally's last group is called before its first attack order, so the game's reinforcement entry does not replace it, in ms.
local ATTACK_DELAY_MS = 5000
--- How often each attacking unit picks the closest foe again, and contact is checked, in ms.
local REORDER_MS = 5000
--- How long the ally's attack order is repeated before it goes back to the battle AI even without contact, in ms.
local ENGAGE_TIMEOUT_MS = 180000
--- How long after a relief column battle starts the enemy charges the ally, in ms.
local CHARGE_DELAY_MS = 3000
--- When our army is called into a relief column anyway if the enemy never reaches the ally, in ms after the battle starts. The enemy's charge
--- orders end then too.
local ARRIVAL_LATEST_MS = 90000
--- How long after the enemy reaches the ally our army is called onto the field, in ms.
local ARRIVAL_AFTER_CONTACT_MS = 20000

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Helpers

--- Writes one line to the battle script log.
--- @param msg string The line to write.
local function log(msg)
    bm:out("[LEAPOI] " .. tostring(msg))
end

--- Collects every unit of the armies in one alliance that the player does or does not control, including their reinforcement sets.
--- @param alliance_id number The alliance to collect from.
--- @param player_controlled boolean True for the player's own armies, false for the AI's.
--- @param faction_key string|nil Only collect armies of this faction. nil collects every army.
--- @returns table Flat list of script units.
local function collect_units(alliance_id, player_controlled, faction_key)
    local units = {}
    local armies = bm:alliances():item(alliance_id):armies()
    for army_id = 1, bm:num_armies_in_alliance(alliance_id) do
        local army = armies:item(army_id)
        if army:is_player_controlled() == player_controlled and (faction_key == nil or army:faction_key() == faction_key) then
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

--- Sends one side straight at the other: every attacking unit attacks the closest foe, re-picking its target every `REORDER_MS`, until any
--- attacker is in melee, `timeout_ms` passes or one side has no units left. The attackers then go back to the battle AI. CA's attack planner
--- is not used, since it led units off to the side of the enemy line to wait in cover.
--- @param name string Who attacks, for the log.
--- @param attackers table Flat list of the attacking script units.
--- @param targets table Flat list of the script units they go for.
--- @param delay_ms number Wait before the first order, in ms.
--- @param timeout_ms number How long the orders last at most, in ms.
--- @param on_contact function|nil Called once the attackers reach melee.
local function attack_until_contact(name, attackers, targets, delay_ms, timeout_ms, on_contact)
    local waited_ms, attacking = 0, false

    --- Stops the attack orders and gives the attackers back to the battle AI.
    --- @param reason string Why, for the log.
    local function hand_back(reason)
        for _, sunit in ipairs(attackers) do
            sunit:stop_attack_closest_enemy()
            sunit:release_control()
        end
        log(string.format("%s handed back to the battle AI after %d s: %s", name, waited_ms / 1000, reason))
    end

    --- Starts the attack orders once, then checks for contact until the attackers engage or the timeout passes.
    local function check_contact()
        local fighting, foes = fighting_units(attackers), fighting_units(targets)
        local engaged = any_in_melee(fighting)
        if engaged or waited_ms >= timeout_ms or #fighting == 0 or #foes == 0 then
            hand_back(engaged and "in contact" or waited_ms >= timeout_ms and "no contact" or "one side has no units left")
            if engaged and on_contact then on_contact() end
            return
        end
        if not attacking then
            for _, sunit in ipairs(fighting) do sunit:start_attack_closest_enemy(REORDER_MS) end
            attacking = true
        end
        local gap = centre_point_table(fighting):distance(centre_point_table(foes))
        log(string.format("t+%ds: %s attacking the closest foes, %d units against %d, %.0f m apart", waited_ms / 1000, name, #fighting, #foes, gap))
        waited_ms = waited_ms + REORDER_MS
        bm:callback(check_contact, REORDER_MS)
    end
    bm:callback(check_contact, delay_ms)
end

--- Calls units in one group at a time. Each group is called once the previous one is on the field, or after `GROUP_TIMEOUT_MS`.
--- @param name string Whose units, for the log.
--- @param units table Flat list of script units.
--- @param on_done function|nil Called once every unit has been called in.
local function call_in_groups(name, units, on_done)
    local waiting = {}
    for _, sunit in ipairs(units) do
        if not is_on_field(sunit) then waiting[#waiting + 1] = sunit end
    end
    log(string.format("calling %d of %d %s units in, %d at a time", #waiting, #units, name, GROUP_SIZE))

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
        log(string.format("called %s units %d-%d", name, next_index, next_index + #group - 1))
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
                log("all " .. name .. " units called in")
                if on_done then on_done() end
                return
            end
        end
        bm:callback(poll, POLL_MS)
    end

    if call_next_group() then
        bm:callback(poll, POLL_MS)
    elseif on_done then
        --- Every unit is already on the field.
        on_done()
    end
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Entry

local ally_faction_key = core:svr_load_string(ALLY_ARRIVES_NOW_SVR_KEY)
if ally_faction_key and ally_faction_key ~= "" then
    local ally = collect_units(bm:get_player_alliance_num(), false, ally_faction_key)
    log("encounter battle with " .. #ally .. " units of ally " .. ally_faction_key .. ", skipping their reinforcement timer")
    if #ally > 0 then
        --- Reinforcements cannot enter while the deployment clock is paused, so the call waits for the battle to start.
        bm:register_phase_change_callback("Deployed", function()
            call_in_groups("ally", ally, function()
                attack_until_contact("ally", ally, collect_units(bm:get_non_player_alliance_num(), false), ATTACK_DELAY_MS, ENGAGE_TIMEOUT_MS)
            end)
        end)
    end
end

local relief_mode = core:svr_load_string(RELIEF_COLUMN_SVR_KEY)
if relief_mode and relief_mode ~= "" then
    log("relief column (" .. relief_mode .. ")")
    bm:register_phase_change_callback("Deployed", function()
        local ours, arrived = collect_units(bm:get_player_alliance_num(), true), false

        --- Calls our army in once, whichever comes first: the enemy reaching the ally or the latest arrival time.
        --- @param reason string Why now, for the log.
        local function arrive(reason)
            if arrived then return end
            arrived = true
            log("our army marches in: " .. reason)
            call_in_groups("our", ours)
        end

        local enemy, ally = collect_units(bm:get_non_player_alliance_num(), false), collect_units(bm:get_player_alliance_num(), false)
        attack_until_contact("enemy", enemy, ally, CHARGE_DELAY_MS, ARRIVAL_LATEST_MS - CHARGE_DELAY_MS, relief_mode == "scripted" and function()
            bm:callback(function() arrive("the enemy reached the ally") end, ARRIVAL_AFTER_CONTACT_MS)
        end or nil)
        if relief_mode == "scripted" then bm:callback(function() arrive("the latest arrival time") end, ARRIVAL_LATEST_MS) end
    end)
end
