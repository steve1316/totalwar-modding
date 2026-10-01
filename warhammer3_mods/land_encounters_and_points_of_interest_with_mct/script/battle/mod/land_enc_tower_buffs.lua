--- Announces the tower buffs on the delving army when a tower floor battle starts: one banner per buff above the army panel, and one entry per
--- buff in the objectives panel for the rest of the battle. It also does the in-battle tricks bought between floors. The campaign saves the
--- buff list under `land_enc_tower_battle_buffs` just before a floor battle and clears it once the floor resolves, so other battles see an
--- empty list.

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Config

--- svr key holding the comma-separated buff names. Mirrored in script/land_encounters/features/tower_offers.lua.
local BUFFS_SVR_KEY = "land_enc_tower_battle_buffs"
--- svr key holding Night terrors' comma-separated target unit keys. Mirrored in script/land_encounters/features/tower_offers.lua.
local NIGHT_TERRORS_SVR_KEY = "land_enc_tower_night_terrors"
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
--- How long Divine shield keeps our lord from harm, in ms. The notice text says 5 minutes.
local DIVINE_SHIELD_MS = 300000
--- How long Night terrors waits before the enemy units flee, in ms. The notice text says 1 minute.
local NIGHT_TERRORS_MS = 60000

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

--- Wraps every unit of an alliance in a script unit, army by army.
--- @param alliance userdata The battle alliance.
--- @returns table The script units.
local function script_units_of(alliance)
    local sunits = {}
    local armies = alliance:armies()
    for a = 1, armies:count() do
        local units = armies:item(a):units()
        for u = 1, units:count() do
            sunits[#sunits + 1] = script_unit:new(units:item(u))
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

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Tricks

--- What each in-battle trick does once the battle starts, given our script units and the enemy's. Control is handed back after each change to
--- our units, so the player can still command them.
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
    divine_shield = function(ours)
        local lord = lord_of(ours)
        if not lord then
            log("Divine shield: no lord found")
            return
        end
        lord:set_invincible(true)
        lord:release_control()
        bm:callback(function()
            lord:set_invincible(false)
            lord:release_control()
            log("Divine shield: the lord can be harmed again")
        end, DIVINE_SHIELD_MS, "land_enc_tower_divine_shield")
        log("Divine shield: the lord " .. lord.unit:type() .. " cannot be harmed for " .. DIVINE_SHIELD_MS / 1000 .. " s")
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
--- Entry

local buffs = svr_list(BUFFS_SVR_KEY)
if #buffs > 0 then
    bm:out("[LEAPOI] tower floor battle with buffs: " .. table.concat(buffs, ", "))
    --- Banners queued during deployment would play before the fight, so the announcement and the tricks wait for the battle to start.
    bm:register_phase_change_callback("Deployed", function()
        local ours, theirs = nil, nil
        for _, name in ipairs(buffs) do
            bm:set_objective(OBJECTIVE_PREFIX .. name)
            bm:queue_help_message(OBJECTIVE_PREFIX .. name .. MESSAGE_SUFFIX, MESSAGE_MS, FADE_MS)
            if TRICKS[name] then
                ours = ours or script_units_of(bm:get_player_alliance())
                theirs = theirs or script_units_of(bm:get_non_player_alliance())
                TRICKS[name](ours, theirs)
            end
        end
    end)
end
