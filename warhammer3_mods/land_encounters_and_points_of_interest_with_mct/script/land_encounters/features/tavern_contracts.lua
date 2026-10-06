--- The Tavern's contract board: bounties (hunt a lord who spawns near the Tavern) and culls (beat armies of a nearby enemy), posted by the
--- Tavern Keepers' Guild that runs every Tavern, taken for a deposit and tracked as missions in the vanilla missions panel. A faction holds at
--- most a few contracts at once across every Tavern, and failing or dropping one costs it standing with the whole Guild. The
--- missions' own success, failure and cancellation events settle them, so nothing needs re-declaring after a load. features/tavern.lua opens
--- the board from its hub, routes its choices here and saves the contracts held (`M.held_by_faction`) with the Taverns. Functions that settle
--- contracts take the TavernEventDelegate, to find a contract's Tavern and to reach the invasion battle manager.

require("script/land_encounters/utils/common")
require("script/land_encounters/utils/random")

local tavern_data = require("script/land_encounters/configs/tavern_data")
local offers_data = require("script/land_encounters/configs/spot_offers")
local dilemmas = require("script/land_encounters/core/dilemmas")
local item_pool = require("script/land_encounters/core/item_pool")
local realm_effects = require("script/land_encounters/core/realm_effects")
local Army = require("script/land_encounters/core/army")

local M = {
    --- Faction key -> the contracts it holds: { key, kind, zone, index, level, deposit, target, invasion, force_cqi }. `key` is the mission,
    --- `zone` and `index` the Tavern it came from, `target` a cull's faction, and `invasion` and `force_cqi` a bounty lord's army.
    held_by_faction = {},
    --- Faction key -> the turn every Guild Tavern stops charging that faction more, after it failed or dropped a contract.
    penalty_until = {},
}

--- The board's dilemma.
M.DILEMMA = "land_enc_dilemma_tavern_board"

--- The kinds of contract, in the order a board rolls them from.
local KINDS = { "bounty", "cull" }

--- Choice key prefix of a contract on the board, followed by its number, e.g. LEAPOI_TVN_CONTRACT_1.
local CHOICE_PREFIX = "LEAPOI_TVN_CONTRACT_"

--- Choice key of Back, shared with the hall.
local BACK_CHOICE = "LEAPOI_TVN_BACK"

--- Mission key prefix, followed by the kind and a slot number, e.g. land_enc_mission_tavern_bounty_2. A faction's contracts of one kind
--- use different slots.
local MISSION_PREFIX = "land_enc_mission_tavern_"

--- Issuer shown on a contract's mission, the same as the Smithy's missions.
local MISSION_ISSUER = "CLAN_ELDERS"

--- Payload text prefix of a contract, followed by its kind and the Tavern's level, e.g. dummy_land_enc_tavern_contract_cull_2.
local LINE_PREFIX = "dummy_land_enc_tavern_contract_"

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

--- Rolls a Tavern's board: `board_size` contracts of random kinds.
--- @param tavern TavernState The Tavern.
--- @returns table { turn, offers = { kind, ... } }.
function M.roll_board(tavern)
    local board = { turn = cm:turn_number(), offers = {} }
    for i = 1, tavern_data.contracts.board_size do board.offers[i] = KINDS[random_number(#KINDS)] end
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

--- Opens the board for a lord: each posted contract with its deposit as a treasury card, then Back. A contract the faction cannot take (it
--- holds the most it can, a cull has no enemy near, or the deposit is more than the treasury) shows why and no card.
--- @param tavern TavernState The Tavern.
--- @param faction faction The visiting faction.
--- @param general_cqi number The visiting lord's command queue index.
function M.open(tavern, faction, general_cqi)
    local faction_name = faction:name()
    tavern.pending_hub, tavern.pending_hall = nil, nil
    M.ensure_board(tavern)
    local full = #M.held(faction_name) >= tavern_data.contracts.max_held
    local deposit = tavern:charge(tavern_data.levels[tavern.level].contracts.deposit, faction_name)
    local treasury = faction:treasury()
    --- A cull's target, the nearest enemy that holds land, is the same for every cull on the board.
    local enemy = nil
    for _, kind in ipairs(tavern.board.offers) do
        if kind == "cull" and enemy == nil then enemy = realm_effects.nearest_enemy(faction, tavern.coordinates[1], tavern.coordinates[2]) or false end
    end
    local slots, choices = {}, {}
    for i, kind in ipairs(tavern.board.offers) do
        local slot = { choice = CHOICE_PREFIX .. i, kind = kind, target = kind == "cull" and enemy and enemy:name() or nil }
        local choice = { key = slot.choice, lines = { LINE_PREFIX .. kind .. "_" .. tavern.level } }
        if full then
            choice.lines[2] = LINE_HELD_FULL
        elseif kind == "cull" and slot.target == nil then
            choice.lines[2] = LINE_NO_TARGET
        elseif treasury < deposit then
            choice.lines[2] = LINE_UNAFFORDABLE
        else
            slot.ok = true
            choice.gold = -deposit
        end
        slots[#slots + 1] = slot
        choices[#choices + 1] = choice
    end
    choices[#choices + 1] = { key = BACK_CHOICE, lines = { LINE_BACK } }
    tavern.pending_board = { general_cqi = general_cqi, deposit = deposit, slots = slots }
    local shown = {}
    for _, slot in ipairs(slots) do shown[#shown + 1] = slot.kind .. (slot.target and " of " .. slot.target or "") .. (slot.ok and "" or " (closed)") end
    log("tavern: board of the " .. tavern:describe() .. " for " .. faction_name .. " (holds " .. #M.held(faction_name) .. ", deposit " .. deposit .. ", treasury "
        .. treasury .. "): " .. table.concat(shown, ", "))
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

--- The first mission slot of a kind a faction's contracts do not use. There is always one, since the board takes no contract from a faction
--- that holds `max_held` already.
--- @param faction_name string The faction key.
--- @param kind string "bounty" or "cull".
--- @returns string The mission key, e.g. land_enc_mission_tavern_cull_1.
local function free_mission_key(faction_name, kind)
    local used = {}
    for _, contract in ipairs(M.held(faction_name)) do used[contract.key] = true end
    for slot = 1, tavern_data.contracts.max_held do
        local key = MISSION_PREFIX .. kind .. "_" .. slot
        if not used[key] then return key end
    end
end

--- Returns a contract's deposit and tells the faction it is void, when it can no longer be met.
--- @param faction_name string The faction that held it.
--- @param contract table The contract.
--- @param tavern TavernState|nil The Tavern it came from, for the message's position.
local function void(faction_name, contract, tavern)
    cm:treasury_mod(faction_name, contract.deposit)
    log("tavern: " .. faction_name .. "'s contract " .. contract.key .. " is void, so the deposit of " .. contract.deposit .. " is returned")
    if tavern then tavern:show_message(faction_name, "tavern_contract_void") end
end

--- Issues a contract's mission: one objective, its deposit back plus the reward gold and an item on success, a deadline and the Tavern's
--- position to zoom to.
--- @param faction_name string The faction that took the contract.
--- @param contract table The contract.
--- @param tavern TavernState The Tavern it came from.
--- @param objective string The objective type, e.g. "ENGAGE_FORCE".
--- @param conditions table The objective's conditions, e.g. { "cqi 123", "requires_victory" }.
--- @param turns number Turns until the deadline.
local function issue_mission(faction_name, contract, tavern, objective, conditions, turns)
    local level = tavern_data.levels[contract.level].contracts
    local mm = mission_manager:new(faction_name, contract.key)
    mm:set_mission_issuer(MISSION_ISSUER)
    mm:add_new_objective(objective)
    for _, condition in ipairs(conditions) do mm:add_condition(condition) end
    mm:add_payload("money " .. (contract.deposit + level[contract.kind .. "_gold"]))
    local item = item_pool.pick_items(faction_name, level.item_rarities, 1)[1]
    if item then mm:add_payload("add_ancillary_to_faction_pool{ancillary_key " .. item .. ";}") end
    mm:set_turn_limit(turns)
    mm:set_position(tavern.coordinates[1], tavern.coordinates[2])
    mm:set_should_whitelist(false)
    mm:trigger()
    log("tavern: " .. faction_name .. " takes " .. contract.key .. " (" .. objective .. " " .. table.concat(conditions, ", ") .. ") for a deposit of "
        .. contract.deposit .. ", reward " .. level[contract.kind .. "_gold"] .. " gold and " .. tostring(item) .. ", " .. turns .. " turns")
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

--- Spawns a bounty's lord in a random region near the Tavern, at war with the contract holder only, and issues the mission once the army
--- exists. Returns false when no region or spawn point was found.
--- @param tavern TavernState The Tavern.
--- @param faction_name string The faction that took the bounty.
--- @param contract table The contract.
--- @param invasion_battle_manager InvasionBattleManager The shared invasion battle manager.
--- @returns boolean True when the army is being spawned.
local function start_bounty(tavern, faction_name, contract, invasion_battle_manager)
    local home = region_at(tavern.coordinates)
    local regions = home and regions_near(home, tavern_data.contracts.bounty_regions_away) or {}
    if #regions == 0 then return false end
    local region = regions[random_number(#regions)]
    local settlement = region:settlement()
    local identifier = "tavern_" .. contract.key .. "_" .. faction_name
    local army = Army:new_from_event({
        dilemma = "tavern_bounty",
        faction = get_random_faction(),
        difficulty = DIFFICULTY_KEYS[contract.level],
        intervention = INTERCEPTION_TYPE,
        force_identifier = identifier .. "_force",
        invasion_identifier = identifier,
    }, nil)
    contract.invasion = identifier
    local x, y = settlement:logical_position_x(), settlement:logical_position_y()
    log("tavern: the bounty " .. contract.key .. " for " .. faction_name .. " spawns a " .. contract.level .. " army of " .. army.faction .. " in " .. region:name())
    return invasion_battle_manager:spawn_patrol(army, faction_name, x, y, function(force_cqi)
        contract.force_cqi = force_cqi
        issue_mission(faction_name, contract, tavern, "ENGAGE_FORCE", { "cqi " .. tostring(force_cqi), "requires_victory" }, tavern_data.contracts.bounty_turns)
        show_located_message(faction_name, "tavern_bounty_sighted", { x, y })
    end)
end

--- Takes a contract from the board: the payload already charged its deposit, so the contract starts and joins the faction's held list. A
--- bounty that cannot spawn its lord is void at once.
--- @param tavern TavernState The Tavern.
--- @param faction_name string The faction taking it.
--- @param slot table The board slot taken.
--- @param deposit number The deposit the payload charged.
--- @param invasion_battle_manager InvasionBattleManager The shared invasion battle manager.
local function take(tavern, faction_name, slot, deposit, invasion_battle_manager)
    for i = 1, #tavern.board.offers do
        if CHOICE_PREFIX .. i == slot.choice then
            table.remove(tavern.board.offers, i)
            break
        end
    end
    local contract = { key = free_mission_key(faction_name, slot.kind), kind = slot.kind, zone = tavern.zone_name, index = tavern.index_in_zone,
        level = tavern.level, deposit = deposit, target = slot.target }
    if slot.kind == "cull" then
        local armies = tavern_data.levels[tavern.level].contracts.cull_armies
        issue_mission(faction_name, contract, tavern, "DEFEAT_N_ARMIES_OF_FACTION", { "total " .. armies, "faction " .. slot.target }, tavern_data.contracts.cull_turns)
    elseif not start_bounty(tavern, faction_name, contract, invasion_battle_manager) then
        log("tavern: the bounty for " .. faction_name .. " found nowhere to spawn")
        void(faction_name, contract, tavern)
        return
    end
    M.held_by_faction[faction_name] = M.held_by_faction[faction_name] or {}
    table.insert(M.held_by_faction[faction_name], contract)
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
        take(tavern, faction_name, slot, pending.deposit, invasion_battle_manager)
    else
        log("tavern: " .. faction_name .. " chose " .. choice_key .. ", shown as closed, so no contract is taken and the board reopens")
    end
    M.open(tavern, faction, pending.general_cqi)
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Settling contracts

--- Finds and removes one of a faction's contracts by its mission key.
--- @param faction_name string The faction key.
--- @param key string The mission key.
--- @returns table|nil The contract, or nil when the faction holds none with that key.
local function remove_contract(faction_name, key)
    local held = M.held(faction_name)
    for i, contract in ipairs(held) do
        if contract.key == key then return table.remove(held, i) end
    end
    return nil
end

--- True when a contract can no longer be met: its bounty lord's army is gone, or its cull target is dead.
--- @param contract table The contract.
--- @returns boolean True when it is void.
local function is_void(contract)
    if contract.kind == "bounty" then
        return contract.force_cqi ~= nil and not cm:model():has_military_force_command_queue_index(contract.force_cqi)
    end
    local target = cm:get_faction(contract.target)
    return not target or target:is_dead()
end

--- Keeps a bounty lord at war with its contract's holder only, by making peace with any AI faction its faction fights.
--- @param contract table The bounty contract, whose lord's army is alive.
local function keep_bounty_at_peace(contract)
    local lord_faction = cm:model():military_force_for_command_queue_index(contract.force_cqi):faction()
    local enemies = lord_faction:factions_at_war_with()
    for i = 0, enemies:num_items() - 1 do
        local enemy = enemies:item_at(i)
        if not enemy:is_human() then
            cm:force_make_peace(lord_faction:name(), enemy:name())
            log("tavern: the bounty lord of " .. contract.key .. " makes peace with " .. enemy:name())
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

--- Settles a contract whose mission ended. The mission's payload already paid the deposit back with the reward on success. A failed or
--- dropped contract loses the deposit, and every Guild Tavern charges that faction more for a while. A bounty lord's army leaves the map
--- either way, so a beaten one does not linger.
--- @param delegate TavernEventDelegate The Tavern delegate.
--- @param faction_name string The faction whose mission ended.
--- @param key string The mission key.
--- @param outcome string "succeeded", "failed" or "cancelled".
function M.on_mission_ended(delegate, faction_name, key, outcome)
    local contract = remove_contract(faction_name, key)
    if contract == nil then return end
    log("tavern: " .. faction_name .. "'s contract " .. key .. " " .. outcome .. " (deposit " .. contract.deposit .. ")")
    if contract.invasion then delegate.invasion_battle_manager:remove_invasion_force_by_identifier(contract.invasion) end
    if outcome == "succeeded" then return end
    M.penalty_until[faction_name] = cm:turn_number() + tavern_data.contracts.standing_turns
    log("tavern: every Guild Tavern charges " .. faction_name .. " more until turn " .. M.penalty_until[faction_name])
    local tavern = delegate:find(contract.zone, contract.index)
    if tavern then tavern:show_message(faction_name, outcome == "failed" and "tavern_contract_failed" or "tavern_contract_dropped") end
end

--- At a faction's turn start, voids its contracts that can no longer be met (a bounty lord killed by someone else, a cull target destroyed)
--- and returns their deposits, and keeps each living bounty lord at war with the holder only.
--- @param delegate TavernEventDelegate The Tavern delegate.
--- @param faction_name string The faction whose turn starts.
function M.on_faction_turn_start(delegate, faction_name)
    local held = M.held(faction_name)
    for i = #held, 1, -1 do
        local contract = held[i]
        if is_void(contract) then
            --- The contract leaves the held list before its mission is cancelled, so the cancellation event finds nothing to settle and does not
            --- take the deposit that `void` returns.
            table.remove(held, i)
            void(faction_name, contract, delegate:find(contract.zone, contract.index))
            cm:cancel_custom_mission(faction_name, contract.key)
        elseif contract.kind == "bounty" and contract.force_cqi then
            keep_bounty_at_peace(contract)
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
