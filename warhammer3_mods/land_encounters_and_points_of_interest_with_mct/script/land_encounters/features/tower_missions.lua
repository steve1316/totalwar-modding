--- Tower missions and Rival delvers: what the floor battle is told to track, what it reports back, and what a won floor pays for it. The battle
--- side is script/battle/mod/land_enc_tower_buffs.lua. Mission records live in configs/tower_offers.lua.

require("script/land_encounters/utils/random")

local offers_data = require("script/land_encounters/configs/tower_offers")
local tower_data = require("script/land_encounters/configs/tower_data")
local tower_army = require("script/land_encounters/features/tower_army")
local item_pool = require("script/land_encounters/core/item_pool")

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Constants

--- svr key holding each mission's target for the battle, "key=value" pairs. Mirrored in script/battle/mod/land_enc_tower_buffs.lua.
local TARGETS_SVR_KEY = "land_enc_tower_mission_targets"
--- svr key the battle writes each mission's outcome to, "key=met" or "key=failed" pairs. Mirrored in the battle script.
local RESULTS_SVR_KEY = "land_enc_tower_mission_results"
--- svr key the battle writes Rival delvers' kills to, "ours,theirs". Mirrored in the battle script.
local RIVAL_SVR_KEY = "land_enc_tower_rival_kills"
--- Prefix of the loc keys holding the mission and rival result lines.
local RESULT_LOC_PREFIX = "campaign_localised_strings_string_land_enc_tower_result_"

local M = {}

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Helpers

--- Finds an offer record by its key.
--- @param key string The offer key.
--- @returns table|nil The offer record.
local function find(key)
    return offers_data.by_key[key]
end

--- Fills a result line template from the tower results loc. The offers' result lines use it too.
--- @param name string The template name after `RESULT_LOC_PREFIX`.
--- @param ... any The values for its `%s` slots.
--- @returns string|nil The line, or nil when the template is missing.
function M.result_line(name, ...)
    local template = common.get_localised_string(RESULT_LOC_PREFIX .. name)
    if template == "" then return nil end
    return string.format(template, ...)
end

local result_line = M.result_line

--- Splits a "key=value,key=value" svr string.
--- @param key string The svr key.
--- @returns table A key -> value map.
local function load_pairs(key)
    local map = {}
    for name, value in (core:svr_load_string(key) or ""):gmatch("([%w_]+)=([^,]*)") do map[name] = value end
    return map
end

--- Finds the guarded unit in the delving army: the `nth` regular unit with its key.
--- @param delve table The delve record.
--- @param standard table { key, nth }.
--- @returns table|nil Its `tower_army.unit_strengths` entry.
local function standard_unit(delve, standard)
    local seen = 0
    for _, entry in ipairs(tower_army.regular_units(delve.general_cqi)) do
        if entry.unit:unit_key() == standard.key then
            seen = seen + 1
            if seen == standard.nth then return entry end
        end
    end
    return nil
end

--- Picks one item for a mission reward.
--- @param faction_name string The delving faction.
--- @param rarities table|nil Rarities to pick from, or nil for a unique item.
--- @returns string|nil The ancillary key.
local function reward_item(faction_name, rarities)
    if not rarities then return item_pool.pick_legendary_item(faction_name) end
    return item_pool.pick_items(faction_name, rarities, 1)[1]
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- API

--- Takes a mission for the next floor's battle. Guard the standard marks one random regular unit of the delving army.
--- @param offer table The mission's offer record.
--- @param delve table The delve record.
function M.take(offer, delve)
    delve.missions = delve.missions or {}
    delve.missions[#delve.missions + 1] = offer.key
    if offer.key == "guard_the_standard" then
        local units = tower_army.regular_units(delve.general_cqi)
        local entry = units[random_number(#units)]
        local key, nth = entry.unit:unit_key(), 0
        for _, other in ipairs(units) do
            if other.unit:unit_key() == key and other.index <= entry.index then nth = nth + 1 end
        end
        delve.standard = { key = key, nth = nth }
        log("tower: guard the standard marks " .. key .. " #" .. nth)
    end
    log("tower: mission " .. offer.key .. " set for the next battle")
end

--- True when Guard the standard has a regular unit to mark.
--- @param delve table The delve record.
--- @returns boolean True when the army has a regular unit.
function M.has_standard(delve)
    return #tower_army.regular_units(delve.general_cqi) > 0
end

--- Saves each mission's target for the next battle. Trophy hunt targets the floor army's most expensive unit, which `delve.trophy` keeps for
--- the reward. The battle's reports are left alone, since the game reloads the campaign after a battle and re-arms it before they are read.
--- @param delve table|nil The delve record. nil clears everything.
function M.hand_to_battle(delve)
    local targets = {}
    delve = delve or {}
    delve.trophy = nil
    for _, key in ipairs(delve.missions or {}) do
        local offer = find(key)
        local value = offer.battle_value
        if key == "trophy_hunt" then
            delve.trophy = tower_army.most_expensive(delve.floor_units or {}, 1)[1]
            value = delve.trophy
        elseif key == "guard_the_standard" and delve.standard then
            value = delve.standard.key .. "#" .. delve.standard.nth
        end
        if value then targets[#targets + 1] = key .. "=" .. value end
    end
    if #targets > 0 then log("tower: mission targets: " .. table.concat(targets, ", ")) end
    core:svr_save_string(TARGETS_SVR_KEY, table.concat(targets, ","))
end

--- Clears what the last battle reported, before a new floor battle starts or once the reports were read.
function M.clear_reports()
    core:svr_save_string(RESULTS_SVR_KEY, "")
    core:svr_save_string(RIVAL_SVR_KEY, "")
end

--- Reads what the battle reported for the delve's missions and Rival delvers. Call it before the battle's values are cleared.
--- @param delve table The delve record.
--- An auto-resolved battle runs no battle script, so it reports nothing and its missions and kills are `untracked`.
--- @returns table { missions = { { key, met } } in the order taken, rival = { ours, theirs } or nil, untracked, standard, trophy }.
function M.read_outcomes(delve)
    local results = load_pairs(RESULTS_SVR_KEY)
    local outcomes = { missions = {}, standard = delve.standard, trophy = delve.trophy, untracked = (core:svr_load_string(RESULTS_SVR_KEY) or "") == ""
        and (core:svr_load_string(RIVAL_SVR_KEY) or "") == "" }
    for _, key in ipairs(delve.missions or {}) do
        outcomes.missions[#outcomes.missions + 1] = { key = key, met = results[key] == "met" }
    end
    if delve.rival then
        local ours, theirs = (core:svr_load_string(RIVAL_SVR_KEY) or ""):match("^(%d+),(%d+)$")
        outcomes.rival = { ours = tonumber(ours) or 0, theirs = tonumber(theirs) or 0 }
    end
    log("tower: battle reported missions " .. (core:svr_load_string(RESULTS_SVR_KEY) or "") .. ", rival kills " .. tostring(core:svr_load_string(RIVAL_SVR_KEY)))
    return outcomes
end

--- Pays a won floor's missions met and settles Rival delvers. Each mission adds a result line for the next dilemma, met or failed. After an
--- auto-resolved battle nothing was counted: each mission says so, a paid mission's cost goes back to the haul, and the rivals take nothing.
--- @param delve table The delve record.
--- @param faction_name string The delving faction.
--- @param outcomes table From `M.read_outcomes`.
--- @param floor table { gold = the floor's gold, items = the floor's items, record = the floor record }.
--- @returns table The result lines.
function M.settle(delve, faction_name, outcomes, floor)
    local lines = {}
    for _, mission in ipairs(outcomes.missions) do
        local offer = find(mission.key)
        local line = nil
        if outcomes.untracked then
            delve.haul.gold = delve.haul.gold + (offer.cost or 0)
            line = result_line("mission_untracked_" .. offer.key)
        elseif not mission.met then
            line = result_line("mission_failed_" .. offer.key)
        elseif offer.gold_share or offer.gold then
            local gold = offer.gold or tower_data.round_gold(floor.gold * offer.gold_share)
            delve.haul.gold = delve.haul.gold + gold
            line = result_line("mission_met_" .. offer.key, tower_data.gold_text(gold))
        elseif offer.item_rarity or offer.floor_item then
            --- A floor item on a floor that pays legendary items (no `item_rarities`) is a legendary item too.
            local rarities = nil
            if offer.floor_item then
                rarities = floor.record.item_rarities
            elseif offer.item_rarity ~= "legendary" then
                rarities = { offer.item_rarity }
            end
            local item = reward_item(faction_name, rarities)
            if item then tower_data.add_items(delve.haul, { item }) end
            line = result_line("mission_met_" .. offer.key)
        elseif offer.unit_ranks then
            local entry = outcomes.standard and standard_unit(delve, outcomes.standard)
            if entry then
                local unit, before = entry.unit, entry.unit:experience_level()
                cm:add_experience_to_unit(unit, offer.unit_ranks)
                --- Read back once the game has applied the ranks.
                cm:callback(function()
                    log("tower: guard the standard raises " .. unit:unit_key() .. " from rank " .. before .. " to rank " .. unit:experience_level()
                        .. " (+" .. offer.unit_ranks .. " given)")
                end, 0.5)
            else
                log("tower: guard the standard found no marked unit to rank")
            end
            line = result_line("mission_met_" .. offer.key)
        elseif offer.lord_ranks then
            local general = tower_army.character(delve.general_cqi)
            if general then cm:add_agent_experience(cm:char_lookup_str(general), offer.lord_ranks, true) end
            line = result_line("mission_met_" .. offer.key)
        elseif offer.sworn_copy and outcomes.trophy then
            delve.haul.units[#delve.haul.units + 1] = outcomes.trophy
            line = result_line("mission_met_" .. offer.key)
        end
        log("tower: mission " .. offer.key .. " " .. (outcomes.untracked and "not counted" or mission.met and "met" or "failed") .. ", haul " .. delve.haul.gold .. " gold, "
            .. #delve.haul.items .. " items")
        if line then lines[#lines + 1] = line end
    end
    local rival = outcomes.rival
    if rival and outcomes.untracked then
        lines[#lines + 1] = result_line("rival_untracked")
        log("tower: the rival battle was auto-resolved, no kills were counted")
    elseif rival then
        local share = find("rival_delvers").rival_share
        if rival.theirs > rival.ours then
            local gold = math.min(delve.haul.gold, math.ceil(floor.gold * share))
            local taken = math.ceil(#floor.items * share)
            delve.haul.gold = delve.haul.gold - gold
            for _ = 1, taken do
                for i = #delve.haul.items, 1, -1 do
                    if delve.haul.items[i] == floor.items[#floor.items] then
                        table.remove(delve.haul.items, i)
                        break
                    end
                end
                table.remove(floor.items)
            end
            lines[#lines + 1] = result_line("rival_won", rival.theirs, rival.ours, gold, taken)
            log("tower: the rivals out-killed us " .. rival.theirs .. " to " .. rival.ours .. " and took " .. gold .. " gold and " .. taken .. " items")
        else
            lines[#lines + 1] = result_line("rival_lost", rival.ours, rival.theirs)
            log("tower: we out-killed the rivals " .. rival.ours .. " to " .. rival.theirs)
        end
    end
    return lines
end

--- Clears the missions and Rival delvers once their battle is over.
--- @param delve table The delve record.
function M.end_battle(delve)
    delve.missions, delve.standard, delve.trophy, delve.rival = nil, nil, nil, nil
    M.hand_to_battle(nil)
    M.clear_reports()
end

return M
