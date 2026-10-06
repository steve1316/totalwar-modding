--- The Tavern's contract board: bounties (hunt a lord who spawns near the Tavern), culls (beat armies of a nearby enemy), marked spots (win a
--- battle at a marked site before its countdown runs out) and, at a level 3 Tavern, quest chains (a hunt, a marked spot, then a boss).
--- Contracts are posted by the Tavern Keepers' Guild that runs every Tavern, taken for a deposit and tracked as missions in the vanilla
--- missions panel. A faction holds at most a few contracts at once across every Tavern, and failing or dropping one costs it standing with
--- the whole Guild. The missions' own success, failure and cancellation events settle them, so nothing needs re-declaring after a load.
--- features/tavern.lua opens the board from its hub, routes its choices here and saves the contracts held (`M.held_by_faction`) with the
--- Taverns. Functions that settle contracts take the TavernEventDelegate, to find a contract's Tavern and to reach the invasion battle
--- manager. Marked spots use CA's Interactive_Marker_Manager, which saves and rebuilds its markers itself.

require("script/land_encounters/utils/common")
require("script/land_encounters/utils/random")

local tavern_data = require("script/land_encounters/configs/tavern_data")
local offers_data = require("script/land_encounters/configs/spot_offers")
local dilemmas = require("script/land_encounters/core/dilemmas")
local item_pool = require("script/land_encounters/core/item_pool")
local offer_effects = require("script/land_encounters/core/offer_effects")
local realm_effects = require("script/land_encounters/core/realm_effects")
local tower_lords = require("script/land_encounters/features/tower_lords")
local Army = require("script/land_encounters/core/army")
local debug_config = require("script/land_encounters/configs/debug")

local M = {
    --- Faction key -> the contracts it holds: { key, kind, slot, step, zone, index, level, deposit, general_cqi, target, invasion, force_cqi,
    --- battle_event, hero_reward }. `key` is the mission, `slot` its number among the faction's contracts of that kind, `step` a chain's step,
    --- `zone` and `index` the Tavern it came from, `general_cqi` the lord who took it, `target` a cull's faction, `invasion` and `force_cqi` a
    --- hunted lord's army, `battle_event` the army a marked spot's battle is fought against while that battle is in flight, and `hero_reward` a
    --- chain's end that frees a hero for want of a legendary item.
    held_by_faction = {},
    --- Faction key -> the turn every Guild Tavern stops charging that faction more, after it failed or dropped a contract.
    penalty_until = {},
}

--- The board's dilemma.
M.DILEMMA = "land_enc_dilemma_tavern_board"

--- Event the marked spots' markers fire when a lord walks onto one, with the lord and the marker.
M.MARK_ENTERED_EVENT = "ScriptEventLeapoiTavernMarkEntered"


--- The kinds of contract a board rolls from. A level 3 board also posts a quest chain.
local KINDS = { "bounty", "cull", "marked" }

--- Choice key prefix of a contract on the board, followed by its number, e.g. LEAPOI_TVN_CONTRACT_1.
local CHOICE_PREFIX = "LEAPOI_TVN_CONTRACT_"

--- Choice key of Back, shared with the hall.
local BACK_CHOICE = "LEAPOI_TVN_BACK"

--- Mission key prefix, followed by the kind and a slot number, e.g. land_enc_mission_tavern_bounty_2. A chain's key also names its step,
--- e.g. land_enc_mission_tavern_chain_2_1.
local MISSION_PREFIX = "land_enc_mission_tavern_"

--- Issuer shown on a contract's mission, the same as the Smithy's missions.
local MISSION_ISSUER = "CLAN_ELDERS"

--- Objective text of a hunt (a bounty, or a chain's first or last step) and of a marked spot, as mission_text loc keys.
local HUNT_TEXT = "mission_text_text_land_enc_tavern_hunt"
local MARK_TEXT = "mission_text_text_land_enc_tavern_mark"

--- Marker key prefix of a marked spot, followed by the faction and the mission key. Each of its markers adds its number, e.g. `_1`.
local MARK_PREFIX = "leapoi_tavern_mark_"

--- Marker infos of a marked spot in order: the one shown until the last turns, then the countdown, one marker per turn.
local MARK_INFOS = { "invasion_marker_5", "invasion_marker_3", "invasion_marker_2", "invasion_marker_1" }

--- Events a marked spot's markers fire when they run out. CA's marker manager needs one to spawn the next marker. Nothing listens for them:
--- the mission's own deadline fails the contract.
local MARK_COUNTDOWN_EVENT = "ScriptEventLeapoiTavernMarkCountdown"
local MARK_EXPIRED_EVENT = "ScriptEventLeapoiTavernMarkExpired"

--- Payload text prefix of a contract, followed by its kind and the Tavern's level, e.g. dummy_land_enc_tavern_contract_cull_2.
local LINE_PREFIX = "dummy_land_enc_tavern_contract_"

--- Payload text prefix of a mission reward's note that it includes the deposit, followed by the amount, e.g. ..._deposit_back_1000.
local DEPOSIT_LINE_PREFIX = "dummy_land_enc_tavern_deposit_back_"

--- Payload text under a contract someone has already accepted from this board.
local LINE_TAKEN = "dummy_land_enc_tavern_contract_taken"

--- Payload text under a contract when the faction already holds the most it can.
local LINE_HELD_FULL = "dummy_land_enc_tavern_contract_held_full"

--- Payload text under a cull with no enemy near enough to cull.
local LINE_NO_TARGET = "dummy_land_enc_tavern_contract_no_target"

--- Payload text under a contract the treasury cannot pay the deposit for, shared with the spot offers.
local LINE_UNAFFORDABLE = offers_data.unaffordable_line

--- Payload text of Back, shared with the bar and the hall.
local LINE_BACK = offers_data.line_prefix .. offers_data.tavern.leave_line

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Board

--- Rolls a Tavern's board: `board_size` contracts of random kinds, and a quest chain at a level 3 Tavern. The debug `tavern_board` list
--- (configs/debug.lua) replaces them while it is set. A contract taken stays on the board, marked in `taken` by its place.
--- @param tavern TavernState The Tavern.
--- @returns table { turn, offers = { kind, ... }, taken = { [place] = faction key } }.
function M.roll_board(tavern)
    if #debug_config.tavern_board > 0 then
        log("tavern: debug tavern_board posts " .. table.concat(debug_config.tavern_board, ", ") .. " at the " .. tavern:describe())
        local offers = {}
        for i, kind in ipairs(debug_config.tavern_board) do offers[i] = kind end
        return { turn = cm:turn_number(), offers = offers, taken = {} }
    end
    local board = { turn = cm:turn_number(), offers = {}, taken = {} }
    for i = 1, tavern_data.contracts.board_size do board.offers[i] = KINDS[random_number(#KINDS)] end
    if tavern_data.levels[tavern.level].contracts.chain then board.offers[#board.offers + 1] = "chain" end
    log("tavern: the board of the " .. tavern:describe() .. " posts " .. table.concat(board.offers, ", "))
    return board
end

--- Rolls the board again when there is none yet or `restock_turns` have passed since it was rolled. Rewards follow the Tavern's level when
--- the board opens, so a level-up needs no new roll.
--- @param tavern TavernState The Tavern.
function M.ensure_board(tavern)
    local board = tavern.board
    if board == nil or cm:turn_number() >= board.turn + tavern_data.contracts.restock_turns then
        tavern.board = M.roll_board(tavern)
    end
end

--- The contracts a faction holds. Read only: a faction that holds none gets a new empty list, not one kept in the save.
--- @param faction_name string The faction key.
--- @returns table Its contracts.
function M.held(faction_name)
    return M.held_by_faction[faction_name] or {}
end

--- Opens the board for a lord: each posted contract with its deposit as a treasury card, then Back. A contract that cannot be taken (someone
--- accepted it already, the faction holds the most it can, a cull has no enemy near, or the deposit is more than the treasury) shows why and
--- no card.
--- @param tavern TavernState The Tavern.
--- @param faction faction The visiting faction.
--- @param general_cqi number The visiting lord's command queue index.
function M.open(tavern, faction, general_cqi)
    local faction_name = faction:name()
    tavern.pending_hub, tavern.pending_hall = nil, nil
    M.ensure_board(tavern)
    local full = #M.held(faction_name) >= tavern_data.contracts.max_held
    local treasury = faction:treasury()
    --- A cull's target, the nearest enemy that holds land, is the same for every cull on the board.
    local enemy = nil
    for _, kind in ipairs(tavern.board.offers) do
        if kind == "cull" and enemy == nil then enemy = realm_effects.nearest_enemy(faction, tavern.coordinates[1], tavern.coordinates[2]) or false end
    end
    local slots, choices = {}, {}
    for i, kind in ipairs(tavern.board.offers) do
        local base = kind == "chain" and tavern_data.contracts.chain.deposit or tavern_data.levels[tavern.level].contracts.deposit
        local slot = { choice = CHOICE_PREFIX .. i, index = i, kind = kind, deposit = tavern:charge(base, faction_name),
            target = kind == "cull" and enemy and enemy:name() or nil }
        local choice = { key = slot.choice, lines = { LINE_PREFIX .. kind .. "_" .. tavern.level } }
        if (tavern.board.taken or {})[i] then
            choice.lines[2] = LINE_TAKEN
        elseif full then
            choice.lines[2] = LINE_HELD_FULL
        elseif kind == "cull" and slot.target == nil then
            choice.lines[2] = LINE_NO_TARGET
        elseif treasury < slot.deposit then
            choice.lines[2] = LINE_UNAFFORDABLE
        else
            slot.ok = true
            choice.gold = -slot.deposit
        end
        slots[#slots + 1] = slot
        choices[#choices + 1] = choice
    end
    choices[#choices + 1] = { key = BACK_CHOICE, lines = { LINE_BACK } }
    tavern.pending_board = { general_cqi = general_cqi, slots = slots }
    local shown = {}
    for _, slot in ipairs(slots) do
        shown[#shown + 1] = slot.kind .. " for " .. slot.deposit .. (slot.target and " against " .. slot.target or "") .. (slot.ok and "" or " (closed)")
    end
    log("tavern: board of the " .. tavern:describe() .. " for " .. faction_name .. " (holds " .. #M.held(faction_name) .. ", treasury " .. treasury .. "): "
        .. table.concat(shown, ", "))
    dilemmas.launch(M.DILEMMA, choices, faction_name)
end

--- The open board's choices that cannot be taken.
--- @param tavern TavernState The Tavern.
--- @returns string, table The board's dilemma key and the choice keys to grey out.
function M.closed_choices(tavern)
    return M.DILEMMA, dilemmas.closed_keys(tavern.pending_board.slots)
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Missions

--- A contract's mission key, from its kind, slot and a chain's step.
--- @param contract table The contract.
--- @returns string The mission key, e.g. land_enc_mission_tavern_cull_1 or land_enc_mission_tavern_chain_2_1.
local function mission_key(contract)
    if contract.kind == "chain" then return MISSION_PREFIX .. "chain_" .. contract.step .. "_" .. contract.slot end
    return MISSION_PREFIX .. contract.kind .. "_" .. contract.slot
end

--- The first slot of a kind a faction's contracts do not use. There is always one, since the board takes no contract from a faction that
--- holds `max_held` already.
--- @param faction_name string The faction key.
--- @param kind string The contract's kind.
--- @returns number The slot number.
local function free_slot(faction_name, kind)
    local used = {}
    for _, contract in ipairs(M.held(faction_name)) do
        if contract.kind == kind then used[contract.slot] = true end
    end
    for slot = 1, tavern_data.contracts.max_held do
        if not used[slot] then return slot end
    end
end

--- What a contract's mission pays on success: the reward gold, the deposit back when the contract ends with this mission (not a chain's
--- earlier steps), and an item (a legendary one at a chain's end).
--- @param faction_name string The faction that holds it.
--- @param contract table The contract.
--- @returns number The reward gold.
--- @returns number The deposit paid back, 0 for a chain's earlier steps.
--- @returns string|nil The item key, or nil when none could be picked.
--- @returns boolean True for a chain's end with no legendary item left, which frees a hero instead.
local function reward(faction_name, contract)
    if contract.kind == "chain" then
        local steps = tavern_data.contracts.chain.steps
        local step = steps[contract.step]
        if contract.step < #steps then return step.gold, 0, item_pool.pick_items(faction_name, step.item_rarities, 1)[1], false end
        local item = item_pool.pick_legendary_item(faction_name)
        return step.gold, contract.deposit, item, item == nil
    end
    local level = tavern_data.levels[contract.level].contracts
    return level[contract.kind .. "_gold"], contract.deposit, item_pool.pick_items(faction_name, level.item_rarities, 1)[1], false
end

--- Issues a contract's mission: one objective, its reward on success, a deadline and the Tavern's position to zoom to. A chain's end that
--- found no legendary item remembers to free a hero instead.
--- @param faction_name string The faction that took the contract.
--- @param contract table The contract.
--- @param tavern TavernState The Tavern it came from.
--- @param objective string The objective type, e.g. "ENGAGE_FORCE", or "SCRIPTED" for a marked spot.
--- @param conditions table The objective's conditions, e.g. { "cqi 123", "requires_victory" }.
--- @param turns number Turns until the deadline.
local function issue_mission(faction_name, contract, tavern, objective, conditions, turns)
    local gold, deposit_back, item, hero = reward(faction_name, contract)
    local mm = mission_manager:new(faction_name, contract.key)
    mm:set_mission_issuer(MISSION_ISSUER)
    if objective == "SCRIPTED" then
        --- The objective never completes by itself: winning the marked spot's battle completes it (see `M.on_mark_battle`).
        mm:add_new_scripted_objective(MARK_TEXT, M.MARK_ENTERED_EVENT, function() return false end, contract.key)
    else
        mm:add_new_objective(objective)
        for _, condition in ipairs(conditions) do mm:add_condition(condition) end
    end
    --- One treasury payload: a mission given two `money` payloads is silently dropped by the game. A text line names the deposit inside it,
    --- when there is loc for that amount.
    mm:add_payload("money " .. (gold + deposit_back))
    local deposit_line = DEPOSIT_LINE_PREFIX .. deposit_back
    if deposit_back > 0 and common.get_localised_string("campaign_payload_ui_details_description_" .. deposit_line) ~= "" then
        mm:add_payload("text_display " .. deposit_line)
    end
    if item then mm:add_payload("add_ancillary_to_faction_pool{ancillary_key " .. item .. ";}") end
    contract.hero_reward = hero or nil
    mm:set_turn_limit(turns)
    mm:set_position(tavern.coordinates[1], tavern.coordinates[2])
    mm:set_should_whitelist(false)
    mm:trigger()
    log("tavern: " .. faction_name .. " gets " .. contract.key .. " (" .. objective .. " " .. table.concat(conditions, ", ") .. ") for a deposit of "
        .. contract.deposit .. " (" .. deposit_back .. " back), reward " .. gold .. " gold and " .. tostring(item or (contract.hero_reward and "a hero")) .. ", " .. turns .. " turns")
end

--- The regions within `regions_away` steps of a region, itself included, in a fixed order so every multiplayer client agrees.
--- @param region region The starting region.
--- @param regions_away number How many neighbour steps to go.
--- @returns table Region interfaces.
local function regions_near(region, regions_away)
    local seen, found, frontier = { [region:name()] = true }, { region }, { region }
    for _ = 1, regions_away do
        local next_frontier = {}
        for _, current in ipairs(frontier) do
            local adjacent = current:adjacent_region_list()
            for i = 0, adjacent:num_items() - 1 do
                local other = adjacent:item_at(i)
                if not seen[other:name()] and not other:is_abandoned() then
                    seen[other:name()] = true
                    found[#found + 1] = other
                    next_frontier[#next_frontier + 1] = other
                end
            end
        end
        frontier = next_frontier
    end
    return found
end

--- Where a contract's lord or marker appears: a random region within `spawn_regions_away` regions of the Tavern, at a valid spot as far as
--- `spawn_distance` from its settlement as the land allows, halving the distance until a spot is found, as the vanilla monster hunts do.
--- @param tavern TavernState The Tavern.
--- @param faction_key string The faction the spot must suit: the army's, or the contract holder's for a marker.
--- @returns number|nil The map x position, or nil when no spot was found.
--- @returns number|nil The map y position.
--- @returns string|nil The region's key.
local function spawn_point(tavern, faction_key)
    local home = region_at(tavern.coordinates)
    local regions = home and regions_near(home, tavern_data.contracts.spawn_regions_away) or {}
    if #regions == 0 then return nil end
    local region = regions[random_number(#regions)]
    local distance = tavern_data.contracts.spawn_distance
    while distance >= 1 do
        local x, y = cm:find_valid_spawn_location_for_character_from_settlement(faction_key, region:name(), false, true, distance)
        if x ~= -1 then return x, y, region:name() end
        distance = math.floor(distance / 2)
    end
    return nil
end

--- The difficulty of a contract's enemy: the Tavern's level for a single contract, or the step's own for a chain.
--- @param contract table The contract.
--- @returns string "easy", "medium" or "hard".
local function difficulty_of(contract)
    if contract.kind == "chain" then return tavern_data.contracts.chain.steps[contract.step].difficulty end
    return DIFFICULTY_KEYS[contract.level]
end

--- The army a contract's hunt or marked battle is fought against: a random culture at the contract's difficulty.
--- @param faction_name string The faction that holds the contract.
--- @param contract table The contract.
--- @returns table The `Army:new_from_event` event, kept so the army can be built again after a load.
local function army_event(faction_name, contract)
    local identifier = "tavern_" .. contract.key .. "_" .. faction_name
    return { dilemma = "tavern_contract", faction = get_random_faction(), difficulty = difficulty_of(contract), intervention = INTERCEPTION_TYPE,
        force_identifier = identifier .. "_force", invasion_identifier = identifier }
end

--- Spawns a hunted lord (a bounty, or a chain's first or last step) near the Tavern, at war with the contract holder only, patrolling
--- halfway towards the Tavern and back, and issues the mission once the army exists.
--- @param tavern TavernState The Tavern.
--- @param faction_name string The faction that holds the contract.
--- @param contract table The contract.
--- @param invasion_battle_manager InvasionBattleManager The shared invasion battle manager.
--- @param turns number Turns until the deadline.
--- @returns boolean True when the army is being spawned.
local function start_hunt(tavern, faction_name, contract, invasion_battle_manager, turns)
    local event = army_event(faction_name, contract)
    local army = Army:new_from_event(event, nil)
    local x, y, region_key = spawn_point(tavern, army.faction)
    if x == nil then return false end
    contract.invasion = event.invasion_identifier
    log("tavern: " .. contract.key .. " for " .. faction_name .. " spawns a " .. event.difficulty .. " army of " .. army.faction .. " in " .. region_key)
    return invasion_battle_manager:spawn_patrol(army, faction_name, x, y, function(force_cqi)
        contract.force_cqi = force_cqi
        issue_mission(faction_name, contract, tavern, "ENGAGE_FORCE", { "cqi " .. tostring(force_cqi), "requires_victory", "override_text " .. HUNT_TEXT }, turns)
        show_located_message(faction_name, "tavern_bounty_sighted", { x, y })
    end, { (x + tavern.coordinates[1]) / 2, (y + tavern.coordinates[2]) / 2 })
end

--- A contract's marked spot key: the prefix of its markers' keys.
--- @param faction_name string The faction that holds the contract.
--- @param key string The contract's mission key.
--- @returns string The mark, e.g. leapoi_tavern_mark_<faction>_<mission>.
local function mark_of(faction_name, key)
    return MARK_PREFIX .. faction_name .. "_" .. key
end

--- Removes a contract's marked spot markers, their marker types and the listeners CA's marker manager set up for them, when it has any.
--- CA's own `clear_marker_type` counts a marker's instances with `#` on a keyed table, so it never despawns them (`despawn_all` does first),
--- and it leaves the listeners behind, which a later contract on the same mission slot would hear twice.
--- @param mark string The marked spot's key.
local function clear_mark(mark)
    for i = 1, #MARK_INFOS do
        local key = mark .. "_" .. i
        local marker = Interactive_Marker_Manager:get_marker(key)
        if marker then
            marker:despawn_all()
            Interactive_Marker_Manager:clear_marker_type(key)
            core:remove_listener(key .. "AreaEntered")
            core:remove_listener("ScriptEventMarkerCountdownCompleted" .. key)
        end
    end
end

--- Puts a marked spot near the Tavern, seen only by the contract holder: one marker until the last turns, then a countdown of one marker
--- per turn. Walking onto any of them starts the battle (see `M.on_mark_entered`), and they stay put so a lost battle can be fought again.
--- The mission is a scripted objective the battle's win completes, and its own deadline fails it.
--- @param tavern TavernState The Tavern.
--- @param faction_name string The faction that holds the contract.
--- @param contract table The contract.
--- @param turns number Turns until the deadline.
--- @returns boolean True when the marker was placed.
local function start_marked(tavern, faction_name, contract, turns)
    local x, y, region_key = spawn_point(tavern, faction_name)
    if x == nil then return false end
    local mark = mark_of(faction_name, contract.key)
    clear_mark(mark)
    local first = nil
    for i, info in ipairs(MARK_INFOS) do
        local duration = i == 1 and math.max(1, turns - #MARK_INFOS + 1) or 1
        local marker = Interactive_Marker_Manager:new_marker_type(mark .. "_" .. i, info, duration, 1, faction_name)
        if i < #MARK_INFOS then marker:add_timeout_event(MARK_COUNTDOWN_EVENT, mark .. "_" .. (i + 1)) else marker:add_timeout_event(MARK_EXPIRED_EVENT) end
        marker:add_interaction_event(M.MARK_ENTERED_EVENT)
        marker:despawn_on_interaction(false)
        first = first or marker
    end
    first:spawn_at_location(x, y, false, true, 0)
    log("tavern: " .. contract.key .. " for " .. faction_name .. " marks a site in " .. region_key .. " at (" .. x .. ", " .. y .. ")")
    issue_mission(faction_name, contract, tavern, "SCRIPTED", {}, turns)
    show_located_message(faction_name, "tavern_mark_spotted", { x, y })
    return true
end

--- Starts a contract, or its chain's current step: a hunt, a cull or a marked spot.
--- @param tavern TavernState The Tavern it came from.
--- @param faction_name string The faction that holds it.
--- @param contract table The contract.
--- @param invasion_battle_manager InvasionBattleManager The shared invasion battle manager.
--- @returns boolean False when it found no place to start, so it is void.
local function start(tavern, faction_name, contract, invasion_battle_manager)
    local data = tavern_data.contracts
    contract.key = mission_key(contract)
    contract.invasion, contract.force_cqi = nil, nil
    if contract.kind == "cull" then
        local armies = tavern_data.levels[contract.level].contracts.cull_armies
        issue_mission(faction_name, contract, tavern, "DEFEAT_N_ARMIES_OF_FACTION", { "total " .. armies, "faction " .. contract.target }, data.cull_turns)
        return true
    end
    local step = contract.kind == "chain" and data.chain.steps[contract.step].kind or contract.kind
    local turns = contract.kind == "chain" and data.chain.step_turns or data[contract.kind .. "_turns"]
    if step == "marked" then return start_marked(tavern, faction_name, contract, turns) end
    return start_hunt(tavern, faction_name, contract, invasion_battle_manager, turns)
end

--- Returns a contract's deposit and tells the faction it is void, when it can no longer be met.
--- @param faction_name string The faction that held it.
--- @param contract table The contract.
--- @param tavern TavernState|nil The Tavern it came from, for the message's position.
local function void(faction_name, contract, tavern)
    cm:treasury_mod(faction_name, contract.deposit)
    log("tavern: " .. faction_name .. "'s contract " .. tostring(contract.key) .. " is void, so the deposit of " .. contract.deposit .. " is returned")
    if tavern then tavern:show_message(faction_name, "tavern_contract_void") end
end

--- Takes a contract from the board: the payload already charged its deposit, so the contract starts and joins the faction's held list, and
--- the board shows it as accepted. One that finds no place to start is void at once and stays on the board.
--- @param tavern TavernState The Tavern.
--- @param faction_name string The faction taking it.
--- @param slot table The board slot taken.
--- @param general_cqi number The lord who took it.
--- @param invasion_battle_manager InvasionBattleManager The shared invasion battle manager.
local function take(tavern, faction_name, slot, general_cqi, invasion_battle_manager)
    local contract = { kind = slot.kind, slot = free_slot(faction_name, slot.kind), step = slot.kind == "chain" and 1 or nil, zone = tavern.zone_name,
        index = tavern.index_in_zone, level = tavern.level, deposit = slot.deposit, target = slot.target, general_cqi = general_cqi }
    if not start(tavern, faction_name, contract, invasion_battle_manager) then
        log("tavern: " .. contract.key .. " for " .. faction_name .. " found nowhere to start")
        void(faction_name, contract, tavern)
        return
    end
    M.held_by_faction[faction_name] = M.held_by_faction[faction_name] or {}
    table.insert(M.held_by_faction[faction_name], contract)
    tavern.board.taken = tavern.board.taken or {}
    tavern.board.taken[slot.index] = faction_name
end

--- Applies a board choice. A contract the payload charged the deposit for starts, and one shown as closed takes nothing. Either way the board
--- reopens for the same lord, while Back reopens the hub.
--- @param tavern TavernState The Tavern.
--- @param faction_name string The faction that chose.
--- @param choice_key string The chosen choice key.
--- @param invasion_battle_manager InvasionBattleManager The shared invasion battle manager.
function M.resolve(tavern, faction_name, choice_key, invasion_battle_manager)
    local pending = tavern.pending_board
    tavern.pending_board = nil
    if pending == nil then return end
    local faction = cm:get_faction(faction_name)
    local slot = dilemmas.find_slot(pending.slots, choice_key)
    if slot == nil then
        log("tavern: " .. faction_name .. " goes back from the board of the " .. tavern:describe())
        tavern:open_hub(faction, pending.general_cqi)
        return
    end
    if slot.ok then
        take(tavern, faction_name, slot, pending.general_cqi, invasion_battle_manager)
    else
        log("tavern: " .. faction_name .. " chose " .. choice_key .. ", shown as closed, so no contract is taken and the board reopens")
    end
    M.open(tavern, faction, pending.general_cqi)
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Marked spot battles

--- Finds one of a faction's contracts by its mission key.
--- @param faction_name string The faction key.
--- @param key string The mission key.
--- @returns table|nil The contract.
--- @returns number|nil Its place in the held list.
local function find_contract(faction_name, key)
    for i, contract in ipairs(M.held(faction_name)) do
        if contract.key == key then return contract, i end
    end
    return nil, nil
end

--- Waits for a marked spot's battle and hands its result to `on_mark_battle`. Used when the battle starts and again after a load.
--- @param delegate TavernEventDelegate The Tavern delegate.
--- @param faction_name string The faction fighting.
--- @param contract table The contract.
--- @param army Army The army fought.
local function await_mark_battle(delegate, faction_name, contract, army)
    local key = contract.key
    delegate.invasion_battle_manager:await_battle({ trigger_event_given_battle_result = function(_, won) M.on_mark_battle(delegate, faction_name, key, won) end },
        "TavernSpot", nil, army)
end

--- A lord walked onto a marked spot: when it is one of their faction's contracts, the battle starts there against the spot's army.
--- @param delegate TavernEventDelegate The Tavern delegate.
--- @param character character The lord.
--- @param marker_ref string The marker type's key, e.g. leapoi_tavern_mark_<faction>_<mission>_2.
--- @param instance_ref string The marker's instance, to find where it stands.
function M.on_mark_entered(delegate, character, marker_ref, instance_ref)
    local faction_name = character:faction():name()
    local prefix = mark_of(faction_name, "")
    if marker_ref:sub(1, #prefix) ~= prefix then return end
    local contract = find_contract(faction_name, (marker_ref:sub(#prefix + 1):gsub("_%d+$", "")))
    if contract == nil or contract.battle_event then return end
    local x, y = Interactive_Marker_Manager:get_coords_from_instance_ref(instance_ref)
    local ibm = delegate.invasion_battle_manager
    local event = army_event(faction_name, contract)
    local army = Army:new_from_event(event, character:faction():subculture())
    if not ibm:can_generate_battle(army, { x, y }) then
        log("tavern: no room for the battle at the marked spot of " .. contract.key)
        return
    end
    contract.battle_event = event
    log("tavern: " .. faction_name .. " fights at the marked spot of " .. contract.key .. " against a " .. event.difficulty .. " army")
    ibm:generate_battle(army, character, { x, y })
    await_mark_battle(delegate, faction_name, contract, army)
end

--- Settles a marked spot's battle: a win completes the mission's objective (whose success event then pays it out) and clears the markers. A
--- loss leaves the spot in place to try again before the deadline.
--- @param delegate TavernEventDelegate The Tavern delegate.
--- @param faction_name string The faction that fought.
--- @param key string The contract's mission key.
--- @param won boolean True when the faction won.
function M.on_mark_battle(delegate, faction_name, key, won)
    --- A battle no longer awaited (backed out of, and cleared at turn start) is someone else's.
    local contract = find_contract(faction_name, key)
    if contract == nil or contract.battle_event == nil then return end
    contract.battle_event = nil
    log("tavern: the marked spot battle of " .. key .. " was " .. (won and "won" or "lost") .. " by " .. faction_name)
    if not won then
        local tavern = delegate:find(contract.zone, contract.index)
        if tavern then tavern:show_message(faction_name, "tavern_mark_repelled") end
        return
    end
    clear_mark(mark_of(faction_name, key))
    cm:complete_scripted_mission_objective(faction_name, key, key, true)
end

--- After a load, waits again for any marked spot battle that was in flight when the game was saved.
--- @param delegate TavernEventDelegate The Tavern delegate.
function M.rearm_battles(delegate)
    for faction_name, held in pairs(M.held_by_faction) do
        for _, contract in ipairs(held) do
            if contract.battle_event then
                local army = Army:new_from_event(contract.battle_event, nil)
                delegate.invasion_battle_manager:set_auxiliary_army_for_reset(army)
                await_mark_battle(delegate, faction_name, contract, army)
                log("tavern: waiting again for the marked spot battle of " .. contract.key)
            end
        end
    end
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Settling contracts

--- True when a contract can no longer be met: its hunted lord's army is gone, or its cull target is dead. A marked spot waits for its
--- deadline.
--- @param contract table The contract.
--- @returns boolean True when it is void.
local function is_void(contract)
    if contract.force_cqi then return not cm:model():has_military_force_command_queue_index(contract.force_cqi) end
    if contract.kind ~= "cull" then return false end
    local target = cm:get_faction(contract.target)
    return not target or target:is_dead()
end

--- Keeps a hunted lord at war with its contract's holder only, by making peace with any AI faction its faction fights.
--- @param contract table The contract, whose lord's army is alive.
local function keep_hunted_at_peace(contract)
    local lord_faction = cm:model():military_force_for_command_queue_index(contract.force_cqi):faction()
    local enemies = lord_faction:factions_at_war_with()
    for i = 0, enemies:num_items() - 1 do
        local enemy = enemies:item_at(i)
        if not enemy:is_human() then
            cm:force_make_peace(lord_faction:name(), enemy:name())
            log("tavern: the hunted lord of " .. contract.key .. " makes peace with " .. enemy:name())
        end
    end
end

--- Turns every Guild Tavern still charges a faction more for, after it failed or dropped a contract.
--- @param faction_name string The faction key.
--- @returns number The penalty's turns left, 0 when there is none.
function M.penalty_turns_left(faction_name)
    return math.max(0, (M.penalty_until[faction_name] or 0) - cm:turn_number())
end

--- True for a mission key the contract board issues.
--- @param key string The mission key.
--- @returns boolean True for a Tavern contract.
function M.is_contract_mission(key)
    return key:sub(1, #MISSION_PREFIX) == MISSION_PREFIX
end

--- Moves a chain to its next step after a step's success. A chain whose next step cannot start (no place for it, or its Tavern is gone) is
--- void, so its deposit comes back.
--- @param delegate TavernEventDelegate The Tavern delegate.
--- @param faction_name string The faction that holds it.
--- @param contract table The chain, still in the held list.
--- @param tavern TavernState|nil The Tavern it came from.
--- @returns boolean True when the next step started and the chain stays held.
local function advance_chain(delegate, faction_name, contract, tavern)
    contract.step = contract.step + 1
    if tavern and start(tavern, faction_name, contract, delegate.invasion_battle_manager) then
        show_located_message(faction_name, "tavern_chain_next", tavern.coordinates)
        return true
    end
    void(faction_name, contract, tavern)
    return false
end

--- Settles a contract whose mission ended. The mission's payload already paid its reward on success. A chain that is not finished moves to
--- its next step instead of ending, and its end frees a hero when it found no legendary item. A failed or dropped contract loses the
--- deposit, and every Guild Tavern charges that faction more for a while. A hunted lord's army and a marked spot's markers leave the map
--- either way.
--- @param delegate TavernEventDelegate The Tavern delegate.
--- @param faction_name string The faction whose mission ended.
--- @param key string The mission key.
--- @param outcome string "succeeded", "failed" or "cancelled".
function M.on_mission_ended(delegate, faction_name, key, outcome)
    local contract, i = find_contract(faction_name, key)
    if contract == nil then return end
    log("tavern: " .. faction_name .. "'s contract " .. key .. " " .. outcome .. " (deposit " .. contract.deposit .. ")")
    if contract.invasion then delegate.invasion_battle_manager:remove_invasion_force_by_identifier(contract.invasion) end
    clear_mark(mark_of(faction_name, key))
    local tavern = delegate:find(contract.zone, contract.index)
    local chain_goes_on = outcome == "succeeded" and contract.kind == "chain" and contract.step < #tavern_data.contracts.chain.steps
    if chain_goes_on and advance_chain(delegate, faction_name, contract, tavern) then return end
    table.remove(M.held(faction_name), i)
    if chain_goes_on then return end
    if outcome == "succeeded" then
        if contract.hero_reward then
            tower_lords.free_hero(contract.general_cqi, faction_name, { offer_effects.culture_shorthand(faction_name) }, tavern_data.contracts.chain.hero_rank)
        end
        return
    end
    M.penalty_until[faction_name] = cm:turn_number() + tavern_data.contracts.standing_turns
    log("tavern: every Guild Tavern charges " .. faction_name .. " more until turn " .. M.penalty_until[faction_name])
    if tavern then tavern:show_message(faction_name, outcome == "failed" and "tavern_contract_failed" or "tavern_contract_dropped") end
end

--- At a faction's turn start, voids its contracts that can no longer be met (a hunted lord killed by someone else, a cull target destroyed,
--- or a mission the game does not have active), returns their deposits and clears their armies and marks, and keeps each living hunted lord
--- at war with the holder only.
--- @param delegate TavernEventDelegate The Tavern delegate.
--- @param faction_name string The faction whose turn starts.
function M.on_faction_turn_start(delegate, faction_name)
    local held = M.held(faction_name)
    for i = #held, 1, -1 do
        local contract = held[i]
        --- A marked spot battle the lord backed out of last turn no longer blocks the mark.
        contract.battle_event = nil
        --- A contract whose mission the game never issued (or lost) can never end, so it is void as well.
        local issued = cm:mission_is_active_for_faction(cm:get_faction(faction_name), contract.key)
        if is_void(contract) or not issued then
            --- The contract leaves the held list before its mission is cancelled, so the cancellation event finds nothing to settle and does not
            --- take the deposit that `void` returns.
            table.remove(held, i)
            log("tavern: " .. faction_name .. "'s contract " .. contract.key .. (issued and " can no longer be met" or " has no active mission"))
            if contract.invasion then delegate.invasion_battle_manager:remove_invasion_force_by_identifier(contract.invasion) end
            clear_mark(mark_of(faction_name, contract.key))
            void(faction_name, contract, delegate:find(contract.zone, contract.index))
            cm:cancel_custom_mission(faction_name, contract.key)
        elseif contract.force_cqi then
            keep_hunted_at_peace(contract)
        end
    end
end

--- Exports the contracts held and the Guild's penalties for the save file.
--- @returns table { held_by_faction, penalty_until }.
function M.export_state()
    return { held_by_faction = M.held_by_faction, penalty_until = M.penalty_until }
end

--- Restores the contracts held and the Guild's penalties from the save file. A save from before contracts restores none.
--- @param saved table|nil The saved state.
function M.restore_state(saved)
    saved = saved or {}
    M.held_by_faction = saved.held_by_faction or {}
    M.penalty_until = saved.penalty_until or {}
end

return M
