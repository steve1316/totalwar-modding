--- Announces the tower buffs on the delving army when a tower floor battle starts: one banner per buff above the army panel, and one entry per
--- buff in the objectives panel for the rest of the battle. It also does the in-battle tricks bought between floors, tracks the missions taken
--- for the floor, and counts kills against Rival delvers, reporting both back to the campaign. The campaign saves the buff list under
--- `land_enc_tower_battle_buffs` just before a floor battle and clears it once the floor resolves, so other battles see an empty list. A
--- battle spot hands over its pre-battle offers, tricks and missions the same way. It also plays the battle modifiers a fight rolled
--- (script/land_encounters/configs/battle_modifiers.lua), handed over as "modifier_<key>" notices.

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
--- How long each banner stays on screen, in ms. Kept short since a battle with several offers and modifiers queues one after another.
local MESSAGE_MS = 2000
--- How long each banner takes to fade in and out, in ms.
local FADE_MS = 1000
--- How often Bottomless quivers tops up ammunition, in ms.
local QUIVERS_REFILL_MS = 5000
--- How long Divine shield keeps our lord from harm when the campaign hands over no value, in seconds.
local DIVINE_SHIELD_SECONDS = 300
--- How long Sacred ground waits before our units regain strength, in ms, and the share they regain when the campaign hands none over, in
--- percent. The notice text says 3 minutes.
local SACRED_GROUND_MS = 180000
local SACRED_GROUND_PERCENT = 10
--- Difficulties a buff name may end with, e.g. "night_terrors_hard". Mirrored from utils/steps.lua in the campaign scripts.
local DIFFICULTIES = { "easy", "medium", "hard" }
--- How long Night terrors waits before the enemy units flee, in ms. The notice text says 1 minute.
local NIGHT_TERRORS_MS = 60000
--- How often the missions and the rival kill count are checked, in ms. Mission time limits count these ticks as seconds.
local MISSION_TICK_MS = 1000
--- Name of the repeating mission check, so it can be stopped when the battle is decided.
local MISSION_PROCESS = "land_enc_tower_missions"
--- Prefix of a battle modifier's notice name. Mirrored in script/land_encounters/configs/battle_modifiers.lua.
local MODIFIER_PREFIX = "modifier_"
--- How often a draining modifier takes its share, in ms, and the share of full strength it takes.
local DRAIN_EVERY_MS = 15000
local DRAIN_SHARE = 0.01
--- When Second Wind heals our units, in ms after the battle starts, and the share of full strength each regains.
local SECOND_WIND_AT_MS = { 120000, 240000 }
local SECOND_WIND_SHARE = 0.05
--- How often Lord's Vigil heals our lord, in ms, and the share of full strength each time.
local LORD_VIGIL_EVERY_MS = 30000
local LORD_VIGIL_SHARE = 0.01
--- The ammunition every missile unit starts with under Short of Shot, as a share of its own.
local SHORT_SHOT_AMMO = 0.5
--- When Panic routs the enemy's weakest units, in ms after the battle starts, and how many.
local PANIC_AT_MS = 180000
local PANIC_UNITS = 2
--- When Cowards' Ground routs our weakest unit, in ms after the battle starts.
local COWARDS_AT_MS = 180000
--- How long Fated Lords keeps both lords invincible, and Hold Fast every unit from routing, in ms.
local FATED_LORDS_MS = 180000
local HOLD_FAST_MS = 180000
--- When Grim Resolve's unbreakable and Wet Powder's empty quivers end, in ms after the battle starts.
local GRIM_RESOLVE_MS = 180000
local WET_POWDER_MS = 180000
--- Grim Presence: how close to our lord an enemy unit must be, in m, how often it bites, in ms, and the share of full strength each bite takes.
local GRIM_PRESENCE_RANGE = 25
local GRIM_PRESENCE_EVERY_MS = 10000
local GRIM_PRESENCE_SHARE = 0.005
--- How often Storm of Magic gives every army Winds of Magic, in ms, and how much.
local STORM_MAGIC_EVERY_MS = 60000
local STORM_MAGIC_WINDS = 20
--- When Drained Winds empties the enemy's Winds of Magic, in ms after the battle starts so their pool is set up first, and how much it takes.
local WINDS_DRAINED_AT_MS = 2000
local WINDS_DRAINED_AMOUNT = 1000
--- How often Warp Shift flings a unit, in ms, and how far, in m.
local WARP_SHIFT_EVERY_MS = 120000
local WARP_SHIFT_RANGE = { 30, 80 }
--- How often Tzeentch's Jest swaps two units, in ms.
local JEST_EVERY_MS = 120000
--- How far a swapped unit lands from the other unit's spot, back toward its own army, in m, so it has room to move.
local JEST_PUSH_BACK = { 15, 30 }
--- How long a teleported unit stays hidden before it shows at its new spot, and how long its ping marker shows after, in ms.
local WARP_HIDDEN_MS = 1000
local WARP_PING_MS = 3000
--- Units Warp Shift and Tzeentch's Jest moved this round, by battle unit. Each unit is moved once before any is again.
local warped = {}
--- Units no teleport may move, by battle unit: those a mission marks (Guard the Standard, Trophy Hunt), so the player can find them, and
--- one Lost in the Warp holds while it is gone.
local marked = {}
--- Names of the repeating modifier timers started this battle, stopped once the battle is decided.
local processes = {}
--- Blink Strike: when our riders are flung, in ms after the battle starts, how far behind the enemy's centre they land, and how far apart, in m.
local BLINK_AT_MS = 120000
local BLINK_BEHIND = 80
local BLINK_SPREAD = 40
--- Lost in the Warp: when one of our units vanishes, in ms after the battle starts, for how long, and how far from where it vanished it returns.
local LOST_WARP_AT_MS = 120000
local LOST_WARP_MS = 30000
local LOST_WARP_RANGE = { 30, 80 }
--- How far from the enemy's centre Scattered Ranks flings each enemy unit, in m.
local SCATTER_RANGE = { 20, 150 }
--- How often Wild Winds spawns a vortex, in ms, and how far from its unit, in m, so it lands near the fighting rather than on top of a unit.
local WILD_WINDS_EVERY_MS = 180000
local WILD_WINDS_RANGE = { 60, 120 }
--- The vortexes Wild Winds picks from. The spawn call takes the Storm of Magic vortex keys (as in CA's benchmarks), not the spell vortex keys.
local WILD_WINDS_VORTEXES = { "tornado_base", "supernova_base" }
--- The strength below which Last Stand lets an enemy unit rout, and how often it checks, in ms.
local LAST_STAND_SHARE = 0.5
local LAST_STAND_POLL_MS = 1000
--- When The Dead Rise and Undying Foe bring units back, in ms after the battle starts, the strength each one's units return at, and how many
--- enemy units Undying Foe brings back.
local RISE_AT_MS = 300000
local DEAD_RISE_STRENGTH = 0.25
local UNDYING_STRENGTH = 0.5
local UNDYING_UNITS = 2

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Helpers

--- Writes a line to the battle log.
--- @param text string The line.
local function log(text)
    bm:out("[LEAPOI] " .. text)
end

--- Wraps a timed step so an error is logged and the battle carries on.
--- @param label string The modifier's name, for the log.
--- @param fn function The step.
--- @returns function The wrapped step.
local function safe(label, fn)
    return function()
        local ok, err = pcall(fn)
        if not ok then log(label .. " failed: " .. tostring(err)) end
    end
end

--- Runs a step once after a delay. An error is logged and the battle carries on.
--- @param label string The modifier's name, for the log.
--- @param ms number The delay, in ms.
--- @param fn function The step.
local function after(label, ms, fn)
    bm:callback(safe(label, fn), ms)
end

--- Runs a step every `ms` until the battle is decided. An error is logged and the battle carries on.
--- @param label string The modifier's name, for the log and the timer's name.
--- @param ms number How often, in ms.
--- @param fn function The step.
--- @returns string The timer's name, to stop it early with `bm:remove_process`.
local function every(label, ms, fn)
    local process = "land_enc_modifier_" .. label
    processes[#processes + 1] = process
    bm:repeat_callback(safe(label, fn), ms, process)
    return process
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

--- Lists the armies of one or more alliances.
--- @param ... userdata The battle alliances.
--- @returns table The battle armies.
local function armies_of(...)
    local list = {}
    for _, alliance in ipairs({ ... }) do
        local armies = alliance:armies()
        for a = 1, armies:count() do list[#list + 1] = armies:item(a) end
    end
    return list
end

--- Wraps the units of an alliance's armies in script units, army by army.
--- @param alliance userdata The battle alliance.
--- @param keep function|nil Takes a battle army and returns true to include it. nil includes every army.
--- @returns table The script units.
local function script_units_of(alliance, keep)
    local sunits = {}
    for _, army in ipairs(armies_of(alliance)) do
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

--- Holds units in the fight: they cannot rout.
--- @param sunits table The script units.
--- @param label string The trick's name, for the log.
local function make_fearless(sunits, label)
    for _, sunit in ipairs(sunits) do
        sunit:morale_behavior_fearless()
        sunit:release_control()
    end
    log(label .. ": " .. #sunits .. " units cannot rout")
end

--- Marks a mission's unit for the whole battle: a ping icon above it and a pulsing unit card, so the player can tell which it is. UI only, so a
--- failure is logged and the mission goes on.
--- @param sunit table The script unit.
--- @param why string What the unit is, for the log.
local function mark_unit(sunit, why)
    marked[sunit.unit] = true
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

--- True when a lord or hero has died on the field: no soldiers left. One that breaks and flees still lives, so it is not slain.
--- @param sunit table The script unit.
--- @returns boolean True when it is slain.
local function slain(sunit)
    return sunit.unit:number_of_men_alive() == 0
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
--- @param lost function|nil Takes a script unit and returns true once it is beaten, `is_lost` when nil.
--- @returns table The mission spec.
local function hunt(hunted, routing_counts, lost)
    lost = lost or is_lost
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
                if lost(sunit) or (routing_counts and sunit.unit:is_routing()) then m.beaten[sunit] = true end
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

--- True while a unit is still in the fight: not routing and not lost.
--- @param sunit table The script unit.
--- @returns boolean True when it still fights.
local function fighting(sunit)
    return not sunit.unit:is_routing() and not is_lost(sunit)
end

--- Lists the units still fighting, without the lords unless `with_lords` is set.
--- @param sunits table Script units.
--- @param with_lords boolean|nil True to keep the commanding units.
--- @returns table The script units.
local function fighters(sunits, with_lords)
    local kept = {}
    for _, sunit in ipairs(sunits) do
        if fighting(sunit) and (with_lords or not sunit.unit:is_commanding_unit()) then kept[#kept + 1] = sunit end
    end
    return kept
end

--- Lists the units whose battle unit passes a test.
--- @param sunits table Script units.
--- @param test function Takes a battle unit and returns true to keep it.
--- @returns table The script units.
local function units_where(sunits, test)
    local kept = {}
    for _, sunit in ipairs(sunits) do
        if test(sunit.unit) then kept[#kept + 1] = sunit end
    end
    return kept
end

--- Lists the units that carry ammunition.
--- @param sunits table Script units.
--- @returns table The script units.
local function shooters(sunits)
    return units_where(sunits, function(unit) return unit:starting_ammo() > 0 end)
end

--- Lists the cavalry and chariots.
--- @param sunits table Script units.
--- @returns table The script units.
local function riders(sunits)
    return units_where(sunits, function(unit) return unit:is_cavalry() or unit:is_chariot() end)
end

--- The `count` weakest units of a list by the game's strategic value, weakest first.
--- @param sunits table Script units.
--- @param count number How many.
--- @returns table The script units.
local function weakest(sunits, count)
    local sorted = {}
    for i, sunit in ipairs(sunits) do sorted[i] = { sunit = sunit, value = sunit.unit:strategic_value(), index = i } end
    table.sort(sorted, function(a, b) return a.value < b.value or (a.value == b.value and a.index < b.index) end)
    local picked = {}
    for i = 1, math.min(count, #sorted) do picked[i] = sorted[i].sunit end
    return picked
end

--- Heals each unit still fighting and below full strength by `share` of its full strength, fallen men included. The game's call heals a
--- unit to a level, so the target is the unit's strength plus the share. The heal lands a moment later, so the log shows the target.
--- @param sunits table Script units.
--- @param share number The share of full strength.
--- @param label string The trick or modifier's name, for the log.
--- @returns number How many units were healed.
local function heal_by(sunits, share, label)
    local healed = 0
    for _, sunit in ipairs(sunits) do
        local before = sunit.unit:unary_hitpoints()
        if fighting(sunit) and before < 1 then
            local target = math.min(1, before + share)
            sunit.unit:heal_hitpoints_unary(target, true)
            log(label .. ": " .. sunit.unit:type() .. " " .. math.floor(before * 100 + 0.5) .. "% -> " .. math.floor(target * 100 + 0.5) .. "%")
            healed = healed + 1
        end
    end
    return healed
end

--- Takes `DRAIN_SHARE` of full strength from each unit still fighting every `DRAIN_EVERY_MS`, for the whole battle. The first tick logs
--- each unit's strength before the drain, which lands a moment later, so the next ticks show it falling.
--- @param sunits table Script units.
--- @param label string The modifier's name, for the log and the callback.
local function drain(sunits, label)
    local ticks = 0
    every(label, DRAIN_EVERY_MS, function()
        ticks = ticks + 1
        local drained = 0
        for _, sunit in ipairs(sunits) do
            if fighting(sunit) then
                if ticks == 1 then log(string.format("%s: %s at %.3f", label, sunit.unit:type(), sunit.unit:unary_hitpoints())) end
                sunit.unit:reduce_hitpoints_unary(DRAIN_SHARE)
                drained = drained + 1
            end
        end
        log(label .. ": tick " .. ticks .. " drained " .. drained .. " units")
    end)
end

--- Picks a random entry of a list.
--- @param list table The list.
--- @returns any A random entry, nil when the list is empty.
local function pick(list)
    if #list == 0 then return nil end
    return list[bm:random_number(#list)]
end

--- Lists the units a teleport may move: all but those a mission marks.
--- @param sunits table Script units.
--- @returns table The script units.
local function teleportable(sunits)
    return units_where(sunits, function(unit) return not marked[unit] end)
end

--- Picks a random unit of a list for Warp Shift or Tzeentch's Jest: one a teleport may move and that has not been moved this round. Once
--- every such unit has been, the round starts over for them.
--- @param sunits table Script units.
--- @returns table|nil The script unit, nil when none may move.
local function pick_fresh(sunits)
    sunits = teleportable(sunits)
    local fresh = {}
    for _, sunit in ipairs(sunits) do
        if not warped[sunit.unit] then fresh[#fresh + 1] = sunit end
    end
    if #fresh == 0 then
        for _, sunit in ipairs(sunits) do warped[sunit.unit] = nil end
        fresh = sunits
    end
    local picked = pick(fresh)
    if picked then warped[picked.unit] = true end
    return picked
end

--- Switches an attribute on for each unit that lacks it. Reading it back straight after says no, as the change lands a moment later,
--- so the log only counts the units.
--- @param sunits table Script units.
--- @param key string The attribute key.
--- @param label string The modifier's name, for the log.
--- @returns table The units it was switched on for, to switch it off again later.
local function grant_attribute(sunits, key, label)
    local granted = {}
    for _, sunit in ipairs(sunits) do
        if not sunit.unit:has_attribute(key) then
            sunit:set_stat_attribute(key, true)
            granted[#granted + 1] = sunit
        end
    end
    log(label .. ": " .. key .. " set on " .. #granted .. " units")
    return granted
end

--- Switches an attribute off again.
--- @param sunits table Script units, as `grant_attribute` returned them.
--- @param key string The attribute key.
--- @param label string The modifier's name, for the log.
local function revoke_attribute(sunits, key, label)
    for _, sunit in ipairs(sunits) do sunit:set_stat_attribute(key, false) end
    log(label .. ": " .. key .. " taken off " .. #sunits .. " units")
end

--- Writes a position for the log.
--- @param pos userdata The battle vector.
--- @returns string The x and z.
local function at_text(pos)
    return string.format("%.0f, %.0f", pos:get_x(), pos:get_z())
end

--- Moves a unit to a position facing a bearing, and hands control back so the player can still command it. It vanishes, then shows at
--- its new spot after `WARP_HIDDEN_MS` under a ping marker, so the jump reads as a blink rather than a snap.
--- @param sunit table The script unit.
--- @param pos userdata Where it lands.
--- @param bearing number The bearing it faces, in degrees.
--- @param label string The modifier's name, for the log.
local function warp(sunit, pos, bearing, label)
    local from = sunit.unit:position()
    sunit:set_invisible_to_all(true, false)
    sunit:teleport_to_location(pos, bearing, sunit.unit:ordered_width())
    sunit:release_control()
    after(label, WARP_HIDDEN_MS, function()
        sunit:set_invisible_to_all(false, false)
        --- The marker is UI only, so a failure leaves the teleport alone.
        pcall(function() sunit:add_ping_icon(nil, WARP_PING_MS) end)
    end)
    log(label .. ": " .. sunit.unit:type() .. " flung from " .. at_text(from) .. " to " .. at_text(pos))
end

--- Finds a random spot within a range of a position that a unit can reach.
--- @param sunit table The script unit.
--- @param pos userdata The position.
--- @param range table The { least, most } distance, in m.
--- @returns userdata|nil The spot, nil when a few tries find none.
local function spot_near(sunit, pos, range)
    for _ = 1, 5 do
        local spot = get_position_near_target(pos, range[1], range[2])
        if sunit.unit:can_reach_position(spot) then return spot end
    end
    return nil
end

--- The centre of the units of a list still fighting, lords included.
--- @param sunits table Script units.
--- @returns userdata|nil The centre, nil when none fight.
local function centre_of(sunits)
    local list = fighters(sunits, true)
    if #list == 0 then return nil end
    return centre_point_table(list)
end

--- An army's Winds of Magic for the log.
--- @param army userdata The battle army.
--- @returns string The current winds, or "?" when the game will not say.
local function winds_text(army)
    local ok, current = pcall(function() return army:winds_of_magic_current() end)
    return ok and tostring(current) or "?"
end

--- True when a unit is out of the battle for good: no men left, or routed or shattered off the field. The game's own respawn checks the same.
--- @param sunit table The script unit.
--- @returns boolean True when it is gone.
local function gone(sunit)
    local unit = sunit.unit
    return unit:number_of_men_alive() == 0 or ((unit:is_routing() or unit:is_shattered()) and not unit:is_valid_target())
end

--- Notes where each unit but the lord stands as the battle starts, for `raise`.
--- @param sunits table Script units.
--- @returns table Each unit's { sunit, pos, bearing, width }.
local function starts_of(sunits)
    local starts = {}
    for _, sunit in ipairs(sunits) do
        if not sunit.unit:is_commanding_unit() then
            starts[#starts + 1] = { sunit = sunit, pos = sunit.unit:position(), bearing = sunit.unit:bearing(), width = sunit.unit:ordered_width() }
        end
    end
    return starts
end

--- Brings up to `count` gone units back where they stood as the battle started, at a share of their full strength.
--- @param starts table The units' starts, from `starts_of`.
--- @param count number How many may return.
--- @param strength number The share of full strength they return at.
--- @param label string The modifier's name, for the log.
local function raise(starts, count, strength, label)
    local raised = 0
    for _, start in ipairs(starts) do
        if raised < count and gone(start.sunit) then
            start.sunit.unit:respawn(start.pos, start.bearing, start.width)
            start.sunit.unit:reduce_hitpoints_unary(1 - strength)
            start.sunit:release_control()
            raised = raised + 1
            log(label .. ": " .. start.sunit.unit:type() .. " returns at " .. at_text(start.pos))
        end
    end
    log(label .. ": " .. raised .. " units return")
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Tricks

--- What each in-battle trick does once the battle starts, given our script units, the enemy's and the value the campaign handed over for it.
--- Control is handed back after each change to our units, so the player can still command them.
local TRICKS = {
    --- Our units cannot rout.
    oath_of_no_retreat = function(ours) make_fearless(ours, "Oath of no retreat") end,
    --- Rally their line: the allied units cannot rout.
    rally_their_line = function()
        make_fearless(script_units_of(bm:get_player_alliance(), function(army) return not army:is_player_controlled() end), "Rally their line")
    end,
    --- Our units that carry ammunition are topped up for the whole battle.
    bottomless_quivers = function(ours)
        local refilled = shooters(ours)
        bm:repeat_callback(function()
            for _, sunit in ipairs(refilled) do sunit.unit:set_current_ammo_unary(1) end
        end, QUIVERS_REFILL_MS, "land_enc_tower_bottomless_quivers")
        log("Bottomless quivers: " .. #refilled .. " units never run out of ammo")
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
    --- Lame their mounts: the slow is a bundle on the enemy army. This logs each enemy rider's run speed, to check it landed.
    lame_their_mounts = function(_, theirs)
        for _, sunit in ipairs(riders(theirs)) do
            log("Lame their mounts: " .. sunit.unit:type() .. " runs at " .. string.format("%.1f", sunit.unit:fast_speed()) .. " m/s")
        end
    end,
    --- Sacred ground: after `SACRED_GROUND_MS`, each of our units still fighting and below full strength regains `percent` of its full strength,
    --- fallen men included.
    sacred_ground = function(ours, _, percent, name)
        local share = (tonumber(percent) or SACRED_GROUND_PERCENT) / 100
        bm:callback(function()
            local healed = heal_by(ours, share, "Sacred ground")
            log("Sacred ground: " .. healed .. " units regain " .. share * 100 .. "% of their strength")
            --- The objective ticks off, and a banner says the blessing took hold, under the notice's difficulty.
            bm:complete_objective(OBJECTIVE_PREFIX .. name)
            bm:queue_help_message(OBJECTIVE_PREFIX .. "sacred_ground_now" .. name:sub(#"sacred_ground" + 1) .. MESSAGE_SUFFIX, MESSAGE_MS, FADE_MS)
        end, SACRED_GROUND_MS, "land_enc_tower_sacred_ground")
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
--- Modifiers

--- What each battle modifier does, by its key. Each gets the script units of every side: `ours`, `theirs`, `allies` and `all`.
local MODIFIERS = {
    bleeding_field = function(ctx) drain(ctx.all, "Bleeding field") end,
    miasma = function(ctx) drain(ctx.theirs, "Plague miasma") end,
    rot = function(ctx) drain(ctx.ours, "Rot of Nurgle") end,
    second_wind = function(ctx)
        for _, at_ms in ipairs(SECOND_WIND_AT_MS) do after("Second wind", at_ms, function() heal_by(ctx.ours, SECOND_WIND_SHARE, "Second wind") end) end
    end,
    lord_vigil = function(ctx)
        local lord = lord_of(ctx.ours)
        if not lord then
            log("Lord's vigil: no lord found")
            return
        end
        every("Lord's vigil", LORD_VIGIL_EVERY_MS, function() heal_by({ lord }, LORD_VIGIL_SHARE, "Lord's vigil") end)
    end,
    short_shot = function(ctx)
        local list = shooters(ctx.all)
        for _, sunit in ipairs(list) do sunit.unit:set_current_ammo_unary(SHORT_SHOT_AMMO) end
        log("Short of shot: " .. #list .. " missile units start at " .. SHORT_SHOT_AMMO * 100 .. "% ammunition")
    end,
    plenty_shot = function(ctx)
        local list = shooters(ctx.all)
        for _, sunit in ipairs(list) do sunit:grant_infinite_ammo() end
        log("Endless quivers: " .. #list .. " missile units never run out")
    end,
    panic = function(ctx)
        after("Panic", PANIC_AT_MS, function()
            for _, sunit in ipairs(weakest(fighters(ctx.theirs), PANIC_UNITS)) do
                sunit:morale_behavior_rout()
                log("Panic: the enemy's " .. sunit.unit:type() .. " routs")
            end
        end)
    end,
    cowards = function(ctx)
        after("Cowards' ground", COWARDS_AT_MS, function()
            local sunit = weakest(fighters(ctx.ours), 1)[1]
            if not sunit then return end
            sunit:morale_behavior_rout()
            log("Cowards' ground: our " .. sunit.unit:type() .. " routs")
        end)
    end,
    duel_lords = function(ctx)
        local lords = {}
        for _, side in ipairs({ ctx.ours, ctx.theirs }) do lords[#lords + 1] = make_lord_invincible(side, "Fated lords") end
        log("Fated lords: " .. #lords .. " lords cannot be harmed for " .. FATED_LORDS_MS / 1000 .. " s")
        after("Fated lords", FATED_LORDS_MS, function()
            for _, lord in ipairs(lords) do
                lord:set_invincible(false)
                lord:release_control()
            end
            log("Fated lords: the lords can be harmed again")
        end)
    end,
    hold_fast = function(ctx)
        make_fearless(ctx.all, "Hold fast")
        after("Hold fast", HOLD_FAST_MS, function()
            for _, sunit in ipairs(ctx.all) do
                sunit:morale_behavior_default()
                sunit:release_control()
            end
            log("Hold fast: units can rout again")
        end)
    end,

    --- Attributes.
    terror_field = function(ctx) grant_attribute(ctx.theirs, "causes_terror", "Field of dread") end,
    grim_resolve = function(ctx)
        local granted = grant_attribute(ctx.ours, "unbreakable", "Grim resolve")
        after("Grim resolve", GRIM_RESOLVE_MS, function() revoke_attribute(granted, "unbreakable", "Grim resolve") end)
    end,
    ambush_country = function(ctx)
        grant_attribute(ctx.all, "stalk", "Ambush country")
        grant_attribute(ctx.all, "hide_forest", "Ambush country")
    end,
    mud = function(ctx) grant_attribute(ctx.all, "cant_run", "Sucking mud") end,
    fire_moving = function(ctx) grant_attribute(shooters(ctx.ours), "mounted_fire_move", "Skirmish drill") end,
    strider = function(ctx) grant_attribute(ctx.ours, "strider", "Sure footing") end,
    disarmed = function(ctx)
        local list, saved = shooters(ctx.theirs), {}
        for i, sunit in ipairs(list) do
            saved[i] = sunit.unit:ammo_left() / sunit.unit:starting_ammo()
            sunit.unit:set_current_ammo_unary(0)
        end
        log("Wet powder: " .. #list .. " enemy missile units cannot shoot for " .. WET_POWDER_MS / 1000 .. " s")
        after("Wet powder", WET_POWDER_MS, function()
            for i, sunit in ipairs(list) do sunit.unit:set_current_ammo_unary(saved[i]) end
            log("Wet powder: the enemy's ammunition is back")
        end)
    end,
    expendable = function(ctx) grant_attribute(ctx.theirs, "expendable", "Callous ranks") end,
    tireless_enemy = function(ctx) grant_attribute(ctx.theirs, "fatigue_immune", "Tireless foe") end,
    run_amok = function(ctx) grant_attribute(units_where(ctx.all, function(unit) return unit:is_war_beasts() end), "rampage", "Maddened beasts") end,

    --- Over time.
    grim_presence = function(ctx)
        local lord = lord_of(ctx.ours)
        if not lord then
            log("Grim presence: no lord found")
            return
        end
        local bites, logged, process = 0, 0, nil
        process = every("Grim presence", GRIM_PRESENCE_EVERY_MS, function()
            if is_lost(lord) then
                log("Grim presence: our lord has fallen after " .. bites .. " bites")
                bm:remove_process(process)
                return
            end
            if lord.unit:is_routing() then return end
            local centre = lord.unit:position()
            --- Distance first, so only the few units near the lord are checked further.
            for _, sunit in ipairs(ctx.theirs) do
                if sunit.unit:position():distance(centre) < GRIM_PRESENCE_RANGE and fighting(sunit) then
                    sunit.unit:reduce_hitpoints_unary(GRIM_PRESENCE_SHARE)
                    bites = bites + 1
                end
            end
            if bites - logged >= 15 then
                log("Grim presence: " .. bites .. " bites on enemy units so far")
                logged = bites
            end
        end)
    end,
    storm_magic = function()
        local armies = armies_of(bm:get_player_alliance(), bm:get_non_player_alliance())
        every("Storm of magic", STORM_MAGIC_EVERY_MS, function()
            local now = {}
            for _, army in ipairs(armies) do
                army:modify_winds_of_magic_current(STORM_MAGIC_WINDS, true)
                now[#now + 1] = winds_text(army)
            end
            log("Storm of magic: " .. #armies .. " armies gain " .. STORM_MAGIC_WINDS .. " winds, now " .. table.concat(now, ", "))
        end)
    end,
    winds_drained = function()
        after("Drained winds", WINDS_DRAINED_AT_MS, function()
            for _, army in ipairs(armies_of(bm:get_non_player_alliance())) do
                local before = winds_text(army)
                army:modify_winds_of_magic_current(-WINDS_DRAINED_AMOUNT, true)
                army:modify_winds_of_magic_reserve(-WINDS_DRAINED_AMOUNT)
                log("Drained winds: the enemy's winds " .. before .. " -> " .. winds_text(army))
            end
        end)
    end,

    --- Tzeentchian chaos.
    warp_shift = function(ctx)
        every("Warp shift", WARP_SHIFT_EVERY_MS, function()
            local sunit = pick_fresh(fighters(ctx.all, true))
            if not sunit then return end
            local spot = spot_near(sunit, sunit.unit:position(), WARP_SHIFT_RANGE)
            if spot then warp(sunit, spot, sunit.unit:bearing(), "Warp shift") else log("Warp shift: no spot near " .. sunit.unit:type()) end
        end)
    end,
    jest = function(ctx)
        every("Tzeentch's jest", JEST_EVERY_MS, function()
            local theirs, ours = pick_fresh(fighters(ctx.theirs)), pick_fresh(fighters(ctx.ours))
            if not (theirs and ours) then return end
            local their_centre, our_centre = centre_of(ctx.theirs), centre_of(ctx.ours)
            --- Each lands on the other's spot, pushed back toward its own army, and faces the other army.
            local least, most = JEST_PUSH_BACK[1], JEST_PUSH_BACK[2]
            local their_spot = position_along_line(ours.unit:position(), their_centre, bm:random_number(least, most), true)
            local our_spot = position_along_line(theirs.unit:position(), our_centre, bm:random_number(least, most), true)
            warp(theirs, their_spot, r_to_d(get_bearing(their_spot, our_centre)), "Tzeentch's jest")
            warp(ours, our_spot, r_to_d(get_bearing(our_spot, their_centre)), "Tzeentch's jest")
        end)
    end,
    blink = function(ctx)
        after("Blink strike", BLINK_AT_MS, function()
            local list = riders(teleportable(fighters(ctx.ours)))
            local their_centre, our_centre = centre_of(ctx.theirs), centre_of(ctx.ours)
            if #list == 0 or not their_centre or not our_centre then
                log("Blink strike: no riders, or no enemy to get behind")
                return
            end
            local behind = position_along_line(their_centre, our_centre, -BLINK_BEHIND, true)
            for _, sunit in ipairs(list) do
                local spot = spot_near(sunit, behind, { 0, BLINK_SPREAD })
                if spot then warp(sunit, spot, r_to_d(get_bearing(spot, their_centre)), "Blink strike") else log("Blink strike: no spot for " .. sunit.unit:type()) end
            end
        end)
    end,
    lost_warp = function(ctx)
        after("Lost in the warp", LOST_WARP_AT_MS, function()
            local sunit = pick(teleportable(fighters(ctx.ours)))
            if not sunit then return end
            local from = sunit.unit:position()
            --- Held out of the other teleports while it is gone.
            marked[sunit.unit] = true
            sunit:set_enabled(false)
            log("Lost in the warp: our " .. sunit.unit:type() .. " vanishes")
            after("Lost in the warp", LOST_WARP_MS, function()
                marked[sunit.unit] = nil
                sunit:set_enabled(true)
                warp(sunit, spot_near(sunit, from, LOST_WARP_RANGE) or from, sunit.unit:bearing(), "Lost in the warp")
            end)
        end)
    end,
    scatter = function(ctx)
        local centre = centre_of(ctx.theirs)
        if not centre then return end
        for _, sunit in ipairs(teleportable(ctx.theirs)) do
            local spot = spot_near(sunit, centre, SCATTER_RANGE)
            if spot then warp(sunit, spot, bm:random_number(360), "Scattered ranks") end
        end
    end,
    revealed = function(ctx)
        for _, sunit in ipairs(ctx.all) do sunit:set_always_visible(true) end
        log("Naked plain: " .. #ctx.all .. " units are always visible")
    end,

    --- Free spells.
    wild_winds = function(ctx)
        every("Wild winds", WILD_WINDS_EVERY_MS, function()
            local sunit = pick(fighters(ctx.all, true))
            if not sunit then return end
            local spot = get_position_near_target(sunit.unit:position(), WILD_WINDS_RANGE[1], WILD_WINDS_RANGE[2])
            local key, angle = pick(WILD_WINDS_VORTEXES), math.rad(bm:random_number(360))
            bm:spawn_vortex(key, spot, v(math.cos(angle), 0, math.sin(angle)))
            log("Wild winds: " .. key .. " spawns near " .. sunit.unit:type() .. " at " .. at_text(spot))
        end)
    end,

    --- Morale and respawns.
    enemy_last_stand = function(ctx)
        local holding = {}
        for i, sunit in ipairs(ctx.theirs) do holding[i] = sunit end
        make_fearless(holding, "Last stand")
        local process
        process = every("Last stand", LAST_STAND_POLL_MS, function()
            --- Backward, so a unit can be taken out of the list in place.
            for i = #holding, 1, -1 do
                local sunit = holding[i]
                if sunit.unit:unary_hitpoints() < LAST_STAND_SHARE then
                    sunit:morale_behavior_default()
                    sunit:release_control()
                    table.remove(holding, i)
                    log("Last stand: the enemy's " .. sunit.unit:type() .. " can rout now")
                end
            end
            if #holding == 0 then bm:remove_process(process) end
        end)
    end,
    dead_rise = function(ctx)
        local starts = starts_of(ctx.ours)
        after("The dead rise", RISE_AT_MS, function() raise(starts, #starts, DEAD_RISE_STRENGTH, "The dead rise") end)
    end,
    undying = function(ctx)
        local starts = starts_of(ctx.theirs)
        after("Undying foe", RISE_AT_MS, function() raise(starts, UNDYING_UNITS, UNDYING_STRENGTH, "Undying foe") end)
    end,
}

--- Plays the battle modifiers among the notice names. A failing one is logged and the battle carries on with the others.
--- @param names table The notice names handed to the battle.
--- @param ours table Our script units.
--- @param theirs table The enemy's script units.
local function play_modifiers(names, ours, theirs)
    local keys = {}
    for _, name in ipairs(names) do
        local key = name:match("^" .. MODIFIER_PREFIX .. "(.+)$")
        if key and MODIFIERS[key] then keys[#keys + 1] = key end
    end
    if #keys == 0 then return end
    local allies = script_units_of(bm:get_player_alliance(), function(army) return not army:is_player_controlled() end)
    local ctx = { ours = ours, theirs = theirs, allies = allies, all = {} }
    for _, side in ipairs({ ours, allies, theirs }) do
        for _, sunit in ipairs(side) do ctx.all[#ctx.all + 1] = sunit end
    end
    log("battle modifiers: " .. table.concat(keys, ", "))
    for _, key in ipairs(keys) do safe(key, function() MODIFIERS[key](ctx) end)() end
    --- Nothing teleports, drains or spawns during the victory countdown.
    bm:register_phase_change_callback("VictoryCountdown", function()
        for _, process in ipairs(processes) do bm:remove_process(process) end
    end)
end

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
            if ctx.their_lord and slain(ctx.their_lord) then m.state = "met" elseif ctx.elapsed > m.value then m.state = "failed" end
            return math.max(0, m.value - ctx.elapsed)
        end,
    },
    duelists_challenge = {
        tick = function(m, ctx)
            if ctx.their_lord and slain(ctx.their_lord) then m.state = "met" end
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
    --- The enemy lord and every hero are slain. Ones that flee still live.
    decapitate = hunt(function(unit) return unit:is_commanding_unit() or unit:unit_class() == "com" end, false, slain),
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
--- A battle spot's Spare the captain: fails once the enemy lord is slain, and is met when the battle is decided with that lord still alive.
MISSIONS.spare_the_captain = {
    tick = function(m, ctx)
        if ctx.their_lord and slain(ctx.their_lord) then m.state = "failed" end
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
            if TRICKS[trick] then TRICKS[trick](ours, theirs, targets[trick], name) end
        end
        --- The missions mark their units first, so a modifier that teleports at the start (Scattered Ranks) leaves them alone.
        track_missions(buffs, ours, theirs)
        play_modifiers(buffs, ours, theirs)
    end)
end
