--- Logs where every army starts in an allied-army test battle (configs/debug.lua `ally_test` in the campaign): which armies deploy and which
--- march in from the map edge, whether each is player-controlled, and how strong its units are. Does nothing in any other battle.

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Config

--- svr key holding the test's mode. Mirrored in script/land_encounters/core/managers.lua.
local ALLY_TEST_SVR_KEY = "land_enc_ally_test"
--- How often the armies are logged after deployment, in ms, and how many times.
local LOG_EVERY_MS = 15000
local LOG_TIMES = 12
--- How long after the battle starts the enemy charges the ally in the relief column test, in ms.
local CHARGE_DELAY_MS = 3000
--- How often each charging enemy unit picks the closest target again, and contact is checked, in ms.
local CHARGE_REORDER_MS = 5000
--- How long the charge orders last before the enemy goes back to the battle AI even without contact, in ms.
local CHARGE_TIMEOUT_MS = 120000
--- How long after the enemy reaches the ally our army is called onto the field, in ms.
local ARRIVAL_AFTER_CONTACT_MS = 20000
--- When our army is called in anyway if the enemy never reaches the ally, in ms after the battle starts.
local ARRIVAL_LATEST_MS = 90000
--- How many of our units are called in at a time. The game brings forced units in about five at a time, so this stays below that.
local ARRIVAL_GROUP_SIZE = 4
--- How often the current group is checked for arrival, in ms, and how long to wait before calling the next group anyway.
local ARRIVAL_POLL_MS = 500
local ARRIVAL_GROUP_TIMEOUT_MS = 15000

local mode = core:svr_load_string(ALLY_TEST_SVR_KEY)
if mode == nil or mode == "" then return end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Logging

--- Writes one line to the battle script log.
--- @param msg string The line to write.
local function log(msg)
    bm:out("[LEAPOI ally test] " .. tostring(msg))
end

--- Logs every army in both alliances: faction, player control, units on the field, men alive against the battle's start, and how many
--- reinforcement sets it has.
--- @param moment string When this is, for the log.
local function log_armies(moment)
    for alliance_id = 1, 2 do
        local ok, problem = pcall(function()
            local armies = bm:alliances():item(alliance_id):armies()
            for army_id = 1, bm:num_armies_in_alliance(alliance_id) do
                local army = armies:item(army_id)
                local sunits = bm:get_scriptunits_for_army(alliance_id, army_id)
                local count, on_field, alive, start = 0, 0, 0, 0
                if sunits then
                    for i = 1, sunits:count() do
                        local unit = sunits:item(i).unit
                        count = count + 1
                        if unit:is_deployed() then on_field = on_field + 1 end
                        alive = alive + unit:number_of_men_alive()
                        start = start + unit:initial_number_of_men()
                    end
                end
                log(moment .. ": alliance " .. alliance_id .. " army " .. army_id .. " " .. army:faction_key() .. (army:is_player_controlled() and " (player)" or " (AI)")
                    .. ", units " .. count .. ", on the field " .. on_field .. ", men " .. alive .. "/" .. start .. ", reinforcement sets "
                    .. tostring(bm:num_reinforcing_armies_for_army_in_alliance(alliance_id, army_id)))
            end
        end)
        if not ok then log(moment .. ": alliance " .. alliance_id .. " could not be read: " .. tostring(problem)) end
    end
end

--- Collects the script units of the AI armies in one alliance.
--- @param alliance_id number The alliance.
--- @returns table Flat list of script units.
local function ai_units(alliance_id)
    local units = {}
    local armies = bm:alliances():item(alliance_id):armies()
    for army_id = 1, bm:num_armies_in_alliance(alliance_id) do
        if not armies:item(army_id):is_player_controlled() then
            local sunits = bm:get_scriptunits_for_army(alliance_id, army_id)
            if sunits then
                for i = 1, sunits:count() do units[#units + 1] = sunits:item(i) end
            end
        end
    end
    return units
end

--- Collects the script units of the player's own armies.
--- @returns table Flat list of script units.
local function our_units()
    local units = {}
    local alliance_id = bm:get_player_alliance_num()
    local armies = bm:alliances():item(alliance_id):armies()
    for army_id = 1, bm:num_armies_in_alliance(alliance_id) do
        if armies:item(army_id):is_player_controlled() then
            local sunits = bm:get_scriptunits_for_army(alliance_id, army_id)
            if sunits then
                for i = 1, sunits:count() do units[#units + 1] = sunits:item(i) end
            end
        end
    end
    return units
end

local arrival_called = false

--- Calls our army onto the field instead of waiting out its reinforcement timer, one group at a time. Each group is called once the previous
--- one is on the field, or after `ARRIVAL_GROUP_TIMEOUT_MS`. Calling them all at once makes units outside the game's current entry group jump.
--- @param reason string Why now, for the log.
local function call_our_army_in(reason)
    if arrival_called then return end
    arrival_called = true
    local waiting = {}
    for _, sunit in ipairs(our_units()) do
        if not sunit.unit:is_deployed() then waiting[#waiting + 1] = sunit end
    end
    log("calling our army in (" .. reason .. "): " .. #waiting .. " units, " .. ARRIVAL_GROUP_SIZE .. " at a time")
    local next_index, group, waited_ms = 1, {}, 0
    local function call_next_group()
        if next_index > #waiting then return false end
        group, waited_ms = {}, 0
        for i = next_index, math.min(next_index + ARRIVAL_GROUP_SIZE - 1, #waiting) do
            waiting[i]:deploy_reinforcement(true)
            group[#group + 1] = waiting[i]
        end
        log(string.format("called our units %d-%d", next_index, next_index + #group - 1))
        next_index = next_index + #group
        return true
    end
    local function poll()
        waited_ms = waited_ms + ARRIVAL_POLL_MS
        local arrived = true
        for _, sunit in ipairs(group) do arrived = arrived and sunit.unit:is_deployed() end
        if arrived or waited_ms >= ARRIVAL_GROUP_TIMEOUT_MS then
            if not arrived then log("our group timed out, calling the next one") end
            if not call_next_group() then
                log("all our units called in")
                return
            end
        end
        bm:callback(poll, ARRIVAL_POLL_MS)
    end
    if call_next_group() then bm:callback(poll, ARRIVAL_POLL_MS) end
end

--- Sends the enemy straight at the ally in the relief column test: while our army is still marching in, the ally is the closest target for
--- every enemy unit. Each enemy unit attacks its closest foe, re-picking every `CHARGE_REORDER_MS`, until one is in melee or
--- `CHARGE_TIMEOUT_MS` passes. The enemy then goes back to the battle AI.
local function enemy_charges_ally()
    local enemy = ai_units(bm:get_non_player_alliance_num())
    local waited_ms, charging = 0, false

    --- Stops the charge orders and gives the enemy back to the battle AI.
    --- @param reason string Why, for the log.
    local function hand_back(reason)
        for _, sunit in ipairs(enemy) do
            sunit:stop_attack_closest_enemy()
            sunit:release_control()
        end
        log(string.format("enemy handed back to the battle AI after %d s: %s", waited_ms / 1000, reason))
    end

    --- Starts the charge once, then checks for contact until the enemy engages or the timeout passes.
    local function check_contact()
        local engaged = false
        for _, sunit in ipairs(enemy) do engaged = engaged or sunit.unit:is_in_melee() end
        if engaged or waited_ms >= CHARGE_TIMEOUT_MS then
            hand_back(engaged and "in contact with the ally" or "no contact")
            if engaged and mode == "relief_column" then bm:callback(function() call_our_army_in("the enemy reached the ally") end, ARRIVAL_AFTER_CONTACT_MS) end
            return
        end
        if not charging then
            for _, sunit in ipairs(enemy) do sunit:start_attack_closest_enemy(CHARGE_REORDER_MS) end
            charging = true
            log("enemy charges the ally with " .. #enemy .. " units")
        end
        waited_ms = waited_ms + CHARGE_REORDER_MS
        bm:callback(check_contact, CHARGE_REORDER_MS)
    end
    bm:callback(check_contact, CHARGE_DELAY_MS)
end

log("mode " .. mode)
bm:register_phase_change_callback("Deployment", function() log_armies("deployment") end)
bm:register_phase_change_callback("Deployed", function()
    log_armies("battle start")
    if mode == "relief_column" then
        enemy_charges_ally()
        bm:callback(function() call_our_army_in("the latest arrival time") end, ARRIVAL_LATEST_MS)
    elseif mode == "relief_column_bundle" then
        --- No scripted arrival: the reinforcement-time bundle on the ally alone decides when we arrive.
        enemy_charges_ally()
    end
    local times = 0
    bm:repeat_callback(function()
        times = times + 1
        log_armies("after " .. (times * LOG_EVERY_MS / 1000) .. "s")
        if times >= LOG_TIMES then bm:remove_process("land_enc_ally_test_log") end
    end, LOG_EVERY_MS, "land_enc_ally_test_log")
end)
