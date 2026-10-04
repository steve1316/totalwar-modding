--- Announces the tower buffs on the delving army when a tower floor battle starts: one banner per buff above the army panel, and one entry per
--- buff in the objectives panel for the rest of the battle. It also does the in-battle tricks bought between floors, tracks the missions taken
--- for the floor, and counts kills against Rival delvers, reporting both back to the campaign. The campaign saves the buff list under
--- `land_enc_tower_battle_buffs` just before a floor battle and clears it once the floor resolves, so other battles see an empty list. A
--- battle spot hands over its pre-battle offers, tricks and missions the same way.

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Config

--- svr key holding the comma-separated buff names. Mirrored in script/land_encounters/features/tower_offers.lua.
local BUFFS_SVR_KEY = "land_enc_tower_battle_buffs"
--- svr key holding Night terrors' comma-separated target unit keys. Mirrored in script/land_encounters/features/tower_offers.lua.
local NIGHT_TERRORS_SVR_KEY = "land_enc_tower_night_terrors"
--- svr key holding each mission's target, "key=value" pairs. Mirrored in script/land_encounters/features/tower_missions.lua.
local MISSION_TARGETS_SVR_KEY = "land_enc_tower_mission_targets"
--- svr key this script reports each mission's outcome to, "key=open|met|failed" pairs. Mirrored in tower_missions.lua.
local MISSION_RESULTS_SVR_KEY = "land_enc_tower_mission_results"
--- svr key this script reports Rival delvers' kills to, "ours,theirs". Mirrored in tower_missions.lua.
local RIVAL_SVR_KEY = "land_enc_tower_rival_kills"
--- svr key holding the allied army's faction key. Mirrored in script/land_encounters/core/managers.lua.
local ALLY_SVR_KEY = "land_enc_ally_arrives_now"
--- Prefix of each buff's scripted objective key. The buff name follows, e.g. "land_enc_tower_buff_iron_resolve".
local OBJECTIVE_PREFIX = "land_enc_tower_buff_"
--- Suffix of each buff's banner line, a plain version of its panel entry that reads well on the red banner.
local MESSAGE_SUFFIX = "_message"
--- How long each banner stays on screen, in ms.
local MESSAGE_MS = 6000
--- How long each banner takes to fade in and out, in ms.
local FADE_MS = 1000
--- How often Bottomless quivers tops up ammunition, in ms.
local QUIVERS_REFILL_MS = 5000
--- How long Divine shield keeps our lord from harm when the campaign hands over no value, in seconds.
local DIVINE_SHIELD_SECONDS = 300
--- Difficulties a buff name may end with, e.g. "night_terrors_hard". Mirrored from utils/steps.lua in the campaign scripts.
local DIFFICULTIES = { "easy", "medium", "hard" }
--- How long Night terrors waits before the enemy units flee, in ms. The notice text says 1 minute.
local NIGHT_TERRORS_MS = 60000
--- How often the missions and the rival kill count are checked, in ms. Mission time limits count these ticks as seconds.
local MISSION_TICK_MS = 1000
--- Name of the repeating mission check, so it can be stopped when the battle is decided.
local MISSION_PROCESS = "land_enc_tower_missions"

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Helpers

--- Writes a line to the battle log.
--- @param text string The line.
local function log(text)
    bm:out("[LEAPOI] " .. text)
end

--- Splits a comma-separated svr string.
--- @param key string The svr key.
--- @returns table The names, empty when the key holds nothing.
local function svr_list(key)
    local list = {}
    for name in (core:svr_load_string(key) or ""):gmatch("[^,]+") do
        list[#list + 1] = name
    end
    return list
end

--- Strips the difficulty a buff name may end with, e.g. "divine_shield_medium" to "divine_shield".
--- @param name string The buff name.
--- @returns string The base name.
local function base_name(name)
    for _, difficulty in ipairs(DIFFICULTIES) do
        local base = name:match("^(.+)_" .. difficulty .. "$")
        if base then return base end
    end
    return name
end

--- Reads the mission targets and trick values the campaign handed over.
--- @returns table Key -> value, a number where it reads as one.
local function load_targets()
    local targets = {}
    for key, value in (core:svr_load_string(MISSION_TARGETS_SVR_KEY) or ""):gmatch("([%w_]+)=([^,]*)") do targets[key] = tonumber(value) or value end
    return targets
end

--- Wraps the units of an alliance's armies in script units, army by army.
--- @param alliance userdata The battle alliance.
--- @param keep function|nil Takes a battle army and returns true to include it. nil includes every army.
--- @returns table The script units.
local function script_units_of(alliance, keep)
    local sunits = {}
    local armies = alliance:armies()
    for a = 1, armies:count() do
        local army = armies:item(a)
        if not keep or keep(army) then
            local units = army:units()
            for u = 1, units:count() do
                sunits[#sunits + 1] = script_unit:new(units:item(u))
            end
        end
    end
    return sunits
end

--- Finds the first commanding unit, the army's lord.
--- @param sunits table Script units.
--- @returns table|nil The lord's script unit.
local function lord_of(sunits)
    for _, sunit in ipairs(sunits) do
        if sunit.unit:is_commanding_unit() then return sunit end
    end
    return nil
end

--- Makes our lord unable to die until told otherwise.
--- @param ours table Our script units.
--- @param label string The trick's name, for the log.
--- @returns table|nil The lord's script unit, nil when there is none.
local function make_lord_invincible(ours, label)
    local lord = lord_of(ours)
    if not lord then
        log(label .. ": no lord found")
        return nil
    end
    lord:set_invincible(true)
    lord:release_control()
    return lord
end

--- Marks a mission's unit for the whole battle: a ping icon above it and a pulsing unit card, so the player can tell which it is. UI only, so a
--- failure is logged and the mission goes on.
--- @param sunit table The script unit.
--- @param why string What the unit is, for the log.
local function mark_unit(sunit, why)
    local ok, err = pcall(function()
        sunit:add_ping_icon()
        sunit:highlight_unit_card(true, nil, true)
    end)
    log(why .. " " .. sunit.unit:type() .. (ok and " is marked" or " could not be marked: " .. tostring(err)))
end

--- True when a unit is out of the fight for good: every soldier dead, or shattered.
--- @param sunit table The script unit.
--- @returns boolean True when it is lost.
local function is_lost(sunit)
    return sunit.unit:number_of_men_alive() == 0 or sunit.unit:is_shattered()
end

--- Sums a number over script units.
--- @param sunits table Script units.
--- @param value function Takes a battle unit and returns a number.
--- @returns number The total.
local function sum(sunits, value)
    local total = 0
    for _, sunit in ipairs(sunits) do total = total + value(sunit.unit) end
    return total
end

--- Soldiers a unit has killed, for the Rival delvers kill counts.
--- @param unit userdata The battle unit.
--- @returns number Its kills.
local function kills(unit)
    return unit:number_of_enemies_killed()
end

--- A mission spec that hunts every enemy unit a test picks: met once each is lost (or, with `routing_counts`, has routed), and failed
--- once `value` seconds pass when the mission has a time limit, or at the start when there is nothing to hunt. A routed unit stays beaten
--- even if it rallies.
--- @param hunted function Takes a battle unit and returns true for one to hunt.
--- @param routing_counts boolean True when a routing unit counts as beaten.
--- @returns table The mission spec.
local function hunt(hunted, routing_counts)
    return {
        start = function(m, ctx)
            m.hunted, m.beaten = {}, {}
            for _, sunit in ipairs(ctx.theirs) do
                if hunted(sunit.unit) then m.hunted[#m.hunted + 1] = sunit end
            end
            if #m.hunted == 0 then m.state = "failed" end
        end,
        tick = function(m, ctx)
            local left = 0
            for _, sunit in ipairs(m.hunted) do
                if is_lost(sunit) or (routing_counts and sunit.unit:is_routing()) then m.beaten[sunit] = true end
                if not m.beaten[sunit] then left = left + 1 end
            end
            if left == 0 then m.state = "met" elseif type(m.value) == "number" and ctx.elapsed > m.value then m.state = "failed" end
            return left
        end,
    }
end

--- Soldiers of the enemy army killed so far.
--- @param theirs table The enemy's script units.
--- @returns number The soldiers dead.
local function enemy_dead(theirs)
    return sum(theirs, function(unit) return unit:initial_number_of_men() - unit:number_of_men_alive() end)
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Tricks

--- What each in-battle trick does once the battle starts, given our script units, the enemy's and the value the campaign handed over for it.
--- Control is handed back after each change to our units, so the player can still command them.
local TRICKS = {
    --- Our units cannot rout.
    oath_of_no_retreat = function(ours)
        for _, sunit in ipairs(ours) do
            sunit:morale_behavior_fearless()
            sunit:release_control()
        end
        log("Oath of no retreat: " .. #ours .. " units cannot rout")
    end,
    --- Our units that carry ammunition are topped up for the whole battle.
    bottomless_quivers = function(ours)
        local shooters = {}
        for _, sunit in ipairs(ours) do
            if sunit.unit:starting_ammo() > 0 then shooters[#shooters + 1] = sunit.unit end
        end
        bm:repeat_callback(function()
            for _, unit in ipairs(shooters) do unit:set_current_ammo_unary(1) end
        end, QUIVERS_REFILL_MS, "land_enc_tower_bottomless_quivers")
        log("Bottomless quivers: " .. #shooters .. " units never run out of ammo")
    end,
    --- Our lord cannot be harmed for the opening minutes.
    divine_shield = function(ours, _, seconds)
        local shield_ms = (seconds or DIVINE_SHIELD_SECONDS) * 1000
        local lord = make_lord_invincible(ours, "Divine shield")
        if not lord then return end
        bm:callback(function()
            lord:set_invincible(false)
            lord:release_control()
            log("Divine shield: the lord can be harmed again")
        end, shield_ms, "land_enc_tower_divine_shield")
        log("Divine shield: the lord " .. lord.unit:type() .. " cannot be harmed for " .. shield_ms / 1000 .. " s")
    end,
    --- After a while, the enemy units the campaign picked flee. Each target key routs one unit of that type that is not already fleeing.
    night_terrors = function(_, theirs)
        local targets = svr_list(NIGHT_TERRORS_SVR_KEY)
        bm:callback(function()
            local routed = {}
            for _, key in ipairs(targets) do
                for _, sunit in ipairs(theirs) do
                    if not routed[sunit] and not sunit.unit:is_commanding_unit() and sunit.unit:type() == key and not sunit.unit:is_routing() then
                        sunit:morale_behavior_rout()
                        routed[sunit] = true
                        log("Night terrors: " .. key .. " flees, routing now: " .. tostring(sunit.unit:is_routing()))
                        break
                    end
                end
            end
        end, NIGHT_TERRORS_MS, "land_enc_tower_night_terrors")
        log("Night terrors: " .. table.concat(targets, ", ") .. " will flee after " .. NIGHT_TERRORS_MS / 1000 .. " s")
    end,
    --- Last ditch oath: our lord cannot die for the whole battle.
    last_ditch_oath = function(ours)
        local lord = make_lord_invincible(ours, "Last ditch oath")
        if not lord then return end
        log("Last ditch oath: the lord " .. lord.unit:type() .. " cannot die this battle")
    end,
    --- The enemy lord is slain as the battle starts.
    assassinate = function(_, theirs)
        local lord = lord_of(theirs)
        if not lord then
            log("Assassinate: no enemy lord found")
            return
        end
        lord:kill()
        log("Assassinate: the enemy lord " .. lord.unit:type() .. " is slain")
    end,
}

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Missions

--- How each mission is tracked. `start` runs once the battle starts, `tick` once a second until the battle is decided, and `finish` when it
--- is. Each gets the mission (`state` "open", "met", "failed" or "void" for one that cannot apply, `value` its target from the campaign) and the battle context (`ours`, `theirs`,
--- `elapsed` seconds). `tick` may settle the mission and returns the objective's counters. `finish` settles a mission still open. Each hook
--- is optional.
local MISSIONS = {
    blood_tally = {
        start = function(m, ctx) m.target = math.ceil(m.value * sum(ctx.theirs, function(unit) return unit:initial_number_of_men() end)) end,
        tick = function(m, ctx)
            local dead = enemy_dead(ctx.theirs)
            if dead >= m.target then m.state = "met" end
            return dead, m.target
        end,
    },
    headhunt = {
        tick = function(m, ctx)
            if ctx.their_lord and is_lost(ctx.their_lord) then m.state = "met" elseif ctx.elapsed > m.value then m.state = "failed" end
            return math.max(0, m.value - ctx.elapsed)
        end,
    },
    duelists_challenge = {
        tick = function(m, ctx)
            if ctx.their_lord and is_lost(ctx.their_lord) then m.state = "met" end
        end,
    },
    hold_the_line = {
        tick = function(m, ctx)
            local lost = 0
            for _, sunit in ipairs(ctx.ours) do if is_lost(sunit) then lost = lost + 1 end end
            if lost > m.value then m.state = "failed" end
            return lost, m.value
        end,
        finish = function(m) m.state = "met" end,
    },
    swift_victory = {
        tick = function(m, ctx)
            if ctx.elapsed > m.value then m.state = "failed" end
            return math.max(0, m.value - ctx.elapsed)
        end,
        finish = function(m) m.state = "met" end,
    },
    guard_the_standard = {
        start = function(m, ctx)
            local key, nth = m.value:match("^(.+)#(%d+)$")
            local seen = 0
            for _, sunit in ipairs(ctx.ours) do
                if not sunit.unit:is_commanding_unit() and sunit.unit:type() == key then
                    seen = seen + 1
                    if seen == tonumber(nth) then m.unit = sunit end
                end
            end
            if m.unit then mark_unit(m.unit, "Guard the standard:") else m.state = "failed" end
        end,
        tick = function(m)
            if is_lost(m.unit) then m.state = "failed" end
        end,
        finish = function(m) m.state = "met" end,
    },
    break_them = {
        start = function(m) m.routed = {} end,
        tick = function(m, ctx)
            local count = 0
            for _, sunit in ipairs(ctx.theirs) do
                if sunit.unit:is_routing() or is_lost(sunit) then m.routed[sunit] = true end
                if m.routed[sunit] then count = count + 1 end
            end
            if count >= m.value then m.state = "met" end
            return count, m.value
        end,
    },
    trophy_hunt = {
        start = function(m, ctx)
            for _, sunit in ipairs(ctx.theirs) do
                if not m.unit and not sunit.unit:is_commanding_unit() and sunit.unit:type() == m.value then m.unit = sunit end
            end
            if m.unit then mark_unit(m.unit, "Trophy hunt:") else m.state = "failed" end
        end,
        tick = function(m)
            if is_lost(m.unit) then m.state = "met" end
        end,
    },
    --- Every enemy unit that shoots is destroyed within the time limit.
    silence_the_guns = hunt(function(unit) return not unit:is_commanding_unit() and unit:starting_ammo() > 0 end, false),
    --- Every enemy monster is destroyed.
    monster_slayer = hunt(function(unit) return unit:unit_class() == "mon" or unit:unit_class() == "minf" end, false),
    --- The enemy lord and every hero fall.
    decapitate = hunt(function(unit) return unit:is_commanding_unit() or unit:unit_class() == "com" end, false),
    --- Every enemy rider (cavalry, chariots and monstrous cavalry) routs or falls within the time limit.
    rout_the_riders = hunt(function(unit)
        return not unit:is_commanding_unit() and (unit:is_cavalry() or unit:is_chariot() or unit:unit_class() == "mcav")
    end, true),
    --- Our lord kills the given number of enemy soldiers.
    lords_glory = {
        tick = function(m, ctx)
            local slain = ctx.our_lord and kills(ctx.our_lord.unit) or 0
            if slain >= m.value then m.state = "met" end
            return slain, m.value
        end,
    },
    --- No unit of ours routs.
    steadfast = {
        tick = function(m, ctx)
            for _, sunit in ipairs(ctx.ours) do
                if sunit.unit:is_routing() then
                    m.state = "failed"
                    return
                end
            end
        end,
        finish = function(m) m.state = "met" end,
    },
    --- We win while the enemy fielded more units than us when the battle started. When it did not, the mission is void: no reward, no failure.
    against_the_odds = {
        start = function(m, ctx)
            if #ctx.ours >= #ctx.theirs then m.state = "void" end
        end,
        finish = function(m) m.state = "met" end,
    },
    untouchable = {
        tick = function(_, ctx)
            return ctx.our_lord and math.floor(ctx.our_lord.unit:unary_hitpoints() * 100) or 0
        end,
        finish = function(m, ctx)
            m.state = (ctx.our_lord and ctx.our_lord.unit:unary_hitpoints() > m.value) and "met" or "failed"
        end,
    },
}
MISSIONS.bloodbath_wager = MISSIONS.blood_tally
--- A battle spot's Flawless victory is Hold the line with a limit of 0, which the campaign hands over as its target.
MISSIONS.flawless_victory = MISSIONS.hold_the_line
--- A battle spot's Spare the captain: fails once the enemy lord falls, and is met when the battle is decided with that lord still standing.
MISSIONS.spare_the_captain = {
    tick = function(m, ctx)
        if ctx.their_lord and is_lost(ctx.their_lord) then m.state = "failed" end
    end,
    finish = function(m) m.state = "met" end,
}

--- Runs one step of a mission. A mission that errors, e.g. one whose target never reached the battle, fails on its own so the others go on.
--- @param m table The mission.
--- @param fn function The spec's start, tick or finish.
--- @param ctx table The battle context.
--- @returns any The step's objective counters, if it gives any.
local function step(m, fn, ctx)
    local ok, a, b = pcall(fn, m, ctx)
    if ok then return a, b end
    m.state = "failed"
    log("mission " .. m.key .. " failed on an error: " .. tostring(a))
end

--- Saves every mission's state for the campaign.
--- @param missions table The missions being tracked.
local function report(missions)
    local pairs_text = {}
    for _, m in ipairs(missions) do pairs_text[#pairs_text + 1] = m.key .. "=" .. m.state end
    core:svr_save_string(MISSION_RESULTS_SVR_KEY, table.concat(pairs_text, ","))
end

--- Shows a mission that has just been settled as completed or failed.
--- @param m table The mission.
local function show_settled(m)
    if m.state == "met" then
        bm:complete_objective(OBJECTIVE_PREFIX .. m.key)
    elseif m.state == "void" then
        bm:remove_objective(OBJECTIVE_PREFIX .. m.key)
    else
        bm:fail_objective(OBJECTIVE_PREFIX .. m.key)
    end
    log("mission " .. m.key .. " " .. m.state)
end

--- Tracks the missions and Rival delvers from the battle's start: checks each once a second, shows live counters, reports every change, and
--- settles what is still open when the battle is decided.
--- @param names table The buff names handed to the battle.
--- @param ours table Our script units.
--- @param theirs table The enemy's script units.
local function track_missions(names, ours, theirs)
    local targets = load_targets()
    local missions, rival = {}, false
    for _, name in ipairs(names) do
        if MISSIONS[name] then
            missions[#missions + 1] = { key = name, value = targets[name], state = "open", spec = MISSIONS[name] }
        end
        rival = rival or name == "rival_delvers"
    end
    if #missions == 0 and not rival then return end
    local ally_faction = core:svr_load_string(ALLY_SVR_KEY) or ""
    local rivals = rival and script_units_of(bm:get_player_alliance(), function(army)
        return not army:is_player_controlled() and army:faction_key() == ally_faction
    end) or {}
    local ctx = { ours = ours, theirs = theirs, elapsed = 0, our_lord = lord_of(ours), their_lord = lord_of(theirs) }
    for _, m in ipairs(missions) do
        if m.spec.start then step(m, m.spec.start, ctx) end
        if m.state ~= "open" then show_settled(m) end
    end
    report(missions)
    log("tracking missions: " .. #missions .. (rival and ", and kills against " .. #rivals .. " rival units" or ""))
    --- The kill counts last sent, so an unchanged count is not saved and shown again.
    local shown_kills = {}

    bm:repeat_callback(function()
        ctx.elapsed = ctx.elapsed + MISSION_TICK_MS / 1000
        local changed = false
        for _, m in ipairs(missions) do
            if m.state == "open" and m.spec.tick then
                local a, b = step(m, m.spec.tick, ctx)
                if m.state ~= "open" then
                    show_settled(m)
                    changed = true
                elseif a and (a ~= m.shown_a or b ~= m.shown_b) then
                    m.shown_a, m.shown_b = a, b
                    bm:set_objective(OBJECTIVE_PREFIX .. m.key, a, b)
                end
            end
        end
        if changed then report(missions) end
        if rival then
            local our_kills, their_kills = sum(ours, kills), sum(rivals, kills)
            if our_kills ~= shown_kills[1] or their_kills ~= shown_kills[2] then
                shown_kills = { our_kills, their_kills }
                core:svr_save_string(RIVAL_SVR_KEY, our_kills .. "," .. their_kills)
                bm:set_objective(OBJECTIVE_PREFIX .. "rival_delvers", our_kills, their_kills)
            end
        end
    end, MISSION_TICK_MS, MISSION_PROCESS)

    bm:register_phase_change_callback("VictoryCountdown", function()
        bm:remove_process(MISSION_PROCESS)
        for _, m in ipairs(missions) do
            if m.state == "open" then
                if m.spec.finish then step(m, m.spec.finish, ctx) else m.state = "failed" end
                show_settled(m)
            end
        end
        report(missions)
        log("battle decided after " .. ctx.elapsed .. " s, missions reported")
    end)
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Entry

local buffs = svr_list(BUFFS_SVR_KEY)
if #buffs > 0 then
    bm:out("[LEAPOI] tower floor battle with buffs: " .. table.concat(buffs, ", "))
    --- Banners queued during deployment would play before the fight, so the announcement, the tricks and the missions wait for the battle
    --- to start. Our units are the player's own armies, not an allied army.
    bm:register_phase_change_callback("Deployed", function()
        local ours = script_units_of(bm:get_player_alliance(), function(army) return army:is_player_controlled() end)
        local theirs = script_units_of(bm:get_non_player_alliance())
        local targets = load_targets()
        for _, name in ipairs(buffs) do
            bm:set_objective(OBJECTIVE_PREFIX .. name)
            bm:queue_help_message(OBJECTIVE_PREFIX .. name .. MESSAGE_SUFFIX, MESSAGE_MS, FADE_MS)
            local trick = base_name(name)
            if TRICKS[trick] then TRICKS[trick](ours, theirs, targets[trick]) end
        end
        track_missions(buffs, ours, theirs)
    end)
end
