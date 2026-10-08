--- The Tavern's mercenary hall: a stock of sellswords, Regiments of Renown and a hero shared by every visitor, rolled again every few turns,
--- plus slots of the visitor's own culture rolled for each visit. Each hire shows the unit as a card and its price as a treasury card, both
--- granted and charged by the dilemma payload, and the hall reopens without it. features/tavern.lua opens the hall from its hub and routes its
--- choices here. The stock and the open hall live on the TavernState (`hall_stock`, `pending_hall`), so they are saved with it. A Tavern has
--- its hub or its hall open at most, never both.

require("script/land_encounters/utils/common")
require("script/land_encounters/utils/random")

local tavern_data = require("script/land_encounters/configs/tavern_data")
local army_generator = require("script/land_encounters/core/army_generator")
local offer_effects = require("script/land_encounters/core/offer_effects")
local dilemmas = require("script/land_encounters/core/dilemmas")
local offers_data = require("script/land_encounters/configs/spot_offers")
local tower_army = require("script/land_encounters/features/tower_army")
local tower_lords = require("script/land_encounters/features/tower_lords")

local M = {}

--- The hall's dilemma.
M.DILEMMA = "land_enc_dilemma_tavern_hall"

--- Choice key of Back, last on the hall.
local BACK_CHOICE = "LEAPOI_TVN_BACK"

--- Choice key prefix of a slot, followed by its kind in capitals and its number, e.g. LEAPOI_TVN_UNIT_1.
local CHOICE_PREFIX = "LEAPOI_TVN_"

--- Every tier a Regiment of Renown can sit in.
local ALL_TIERS = { 0, 1, 2, 3, 4, 5 }

--- Payload text of the hero's slot, followed by its rank. A unit's slot has no text: its unit card and price say it all.
local LINE_HERO = "dummy_land_enc_tavern_hall_hero_"

--- Payload text under a unit the army has no room for.
local LINE_NO_ROOM = "dummy_land_enc_tavern_hall_no_room"

--- Payload text under a hire the treasury cannot pay, shared with the spot offers.
local LINE_UNAFFORDABLE = offers_data.unaffordable_line

--- Payload text of Back, shared with the bar.
local LINE_BACK = offers_data.line_prefix .. offers_data.tavern.leave_line

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Stock

--- The cultures a Tavern stocks: its own for a racial Tavern, or `neutral_cultures` different random ones.
--- @param tavern TavernState The Tavern.
--- @returns table Faction shorthands.
local function stock_cultures(tavern)
    if tavern.culture ~= "" then return { tavern.culture } end
    local cultures, chosen, tries = {}, {}, 0
    while #cultures < tavern_data.hall.neutral_cultures and tries < 20 do
        tries = tries + 1
        local shorthand = get_random_faction()
        if not chosen[shorthand] then
            chosen[shorthand] = true
            cultures[#cultures + 1] = shorthand
        end
    end
    return cultures
end

--- Rolls a Tavern's stock at its level: different units and Regiments of Renown, taking turns between its cultures, and a hero of one of them.
--- @param tavern TavernState The Tavern.
--- @returns table { turn, level, units, renown, hero = { culture, rank } or nil }.
function M.roll_stock(tavern)
    local level = tavern_data.levels[tavern.level].hall
    local cultures = stock_cultures(tavern)
    local stock = { turn = cm:turn_number(), level = tavern.level, units = {}, renown = {} }
    local exclude = {}
    --- Adds `count` different units of `tiers` to `list`, taking turns between the cultures.
    local function fill(list, count, tiers, renown)
        for i = 1, count do
            local key = army_generator.pick_distinct_units(cultures[(i - 1) % #cultures + 1], tiers, 1, { renown = renown, exclude = exclude })[1]
            if key then list[#list + 1] = key end
        end
    end
    fill(stock.units, level.units, level.tiers, false)
    fill(stock.renown, random_range(level.renown[1], level.renown[2]), ALL_TIERS, true)
    if level.hero_rank then stock.hero = { culture = cultures[random_number(#cultures)], rank = level.hero_rank } end
    log("tavern: the hall of the " .. tavern:describe() .. " restocks from " .. table.concat(cultures, ", ") .. ": units " .. table.concat(stock.units, ", ")
        .. "; renown " .. table.concat(stock.renown, ", ") .. "; hero " .. (stock.hero and ("rank " .. stock.hero.rank .. " " .. stock.hero.culture) or "none"))
    return stock
end

--- Rolls the stock again when there is none yet, the Tavern has levelled up since, the MCT `tavern_hall_restock` turns have passed since it was rolled, or it
--- holds more units than its level now stocks (a save from before the hall was made smaller).
--- @param tavern TavernState The Tavern.
function M.ensure_stock(tavern)
    local stock = tavern.hall_stock
    if stock == nil or stock.level ~= tavern.level or #stock.units > tavern_data.levels[tavern.level].hall.units
        or cm:turn_number() >= stock.turn + get_mct_settings().tavern_hall_restock then
        tavern.hall_stock = M.roll_stock(tavern)
    end
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- The hall dilemma

--- Opens the hall for a lord: every unit, Regiment of Renown and hero in stock, then the visitor's own slots, then Back. A hire the army has
--- no room for, or the treasury cannot pay, shows why and no cards. A hero needs no room, since one that cannot join waits beside the army.
--- @param tavern TavernState The Tavern.
--- @param faction faction The visiting faction.
--- @param general_cqi number The visiting lord's command queue index.
--- @param own table|nil The visitor's own slots when the hall reopens, or nil to roll them.
--- @param hired number|nil Hires made on this visit so far, 0 when nil.
function M.open(tavern, faction, general_cqi, own, hired)
    local faction_name = faction:name()
    tavern.pending_hub, tavern.pending_board = nil, nil
    if not tower_army.character(general_cqi) then
        log("tavern: lord " .. tostring(general_cqi) .. " of " .. faction_name .. " is gone, so the hall does not open")
        return
    end
    M.ensure_stock(tavern)
    local stock = tavern.hall_stock
    local level = tavern_data.levels[tavern.level].hall
    if own == nil then
        local shorthand = offer_effects.culture_shorthand(faction_name)
        local exclude = {}
        for _, key in ipairs(stock.units) do exclude[key] = true end
        own = shorthand and army_generator.pick_distinct_units(shorthand, level.tiers, level.own, { exclude = exclude }) or {}
    end
    local force = tower_army.delving_force(general_cqi)
    local room = force and tower_army.free_slots(force) or 0
    local treasury = dilemmas.treasury(faction_name)
    local slots, choices = {}, {}
    --- Adds one slot and its choice. `key` is its unit, or nil for the hero, whose `line` describes it. A hire the treasury cannot pay still
    --- shows its price and unit, and is marked unaffordable so a click on it anyway is undone.
    local function add(kind, number, key, base, line)
        local markup = get_mct_settings().tavern_hire_markup + (kind == "renown" and tavern_data.hall.renown_extra or 0)
        local slot = { choice = CHOICE_PREFIX .. kind:upper() .. "_" .. number, kind = kind, index = number, key = key, price = tavern:charge(base + markup, faction_name) }
        local choice = { key = slot.choice, lines = { line } }
        if key and room < 1 then
            choice.lines[#choice.lines + 1] = LINE_NO_ROOM
            choice.closed = true
        elseif treasury < slot.price then
            choice.lines[#choice.lines + 1] = LINE_UNAFFORDABLE
            choice.gold = -slot.price
            if key then choice.units = { force = force, keys = { key } } end
            choice.unaffordable = true
        else
            slot.ok = true
            choice.gold = -slot.price
            if key then choice.units = { force = force, keys = { key } } end
        end
        slots[#slots + 1] = slot
        choices[#choices + 1] = choice
    end
    for i, key in ipairs(stock.units) do add("unit", i, key, army_generator.unit_price_by_key(key)) end
    for i, key in ipairs(stock.renown) do add("renown", i, key, army_generator.unit_price_by_key(key)) end
    if stock.hero then add("hero", 1, nil, level.hero_price, LINE_HERO .. stock.hero.rank) end
    for i, key in ipairs(own) do add("own", i, key, army_generator.unit_price_by_key(key)) end
    choices[#choices + 1] = { key = BACK_CHOICE, lines = { LINE_BACK } }
    tavern.pending_hall = { general_cqi = general_cqi, own = own, slots = slots, hired = hired or 0 }
    local shown = {}
    for _, slot in ipairs(slots) do shown[#shown + 1] = (slot.key or "hero") .. " " .. slot.price .. (slot.ok and "" or " (closed)") end
    log("tavern: hall of the " .. tavern:describe() .. " for " .. faction_name .. " (hired " .. (hired or 0) .. ", treasury " .. treasury .. ", room " .. room
        .. "): " .. table.concat(shown, ", "))
    dilemmas.launch(M.DILEMMA, choices, faction_name)
end

--- Applies a hall choice. A hire the payload granted and charged leaves the stock (a hero is freed here), and the first one of a visit closes
--- the hall to the faction for its cooldown. One shown as closed buys nothing. The hall reopens for the same lord until the visit's last hire,
--- and then, or on Back, the hub reopens.
--- @param tavern TavernState The Tavern.
--- @param faction_name string The faction that chose.
--- @param choice_key string The chosen choice key.
function M.resolve(tavern, faction_name, choice_key)
    local pending, stock = tavern.pending_hall, tavern.hall_stock
    tavern.pending_hall = nil
    if pending == nil then return end
    local faction = cm:get_faction(faction_name)
    local slot = dilemmas.find_slot(pending.slots, choice_key)
    if slot == nil then
        log("tavern: " .. faction_name .. " goes back from the hall of the " .. tavern:describe())
        tavern:open_hub(faction, pending.general_cqi)
        return
    end
    if not slot.ok then
        log("tavern: " .. faction_name .. " chose " .. choice_key .. ", shown as closed, so nothing is hired and the hall reopens")
        --- A closed hire that showed its price and unit was paid out by its payload, so the gold goes back and the unit leaves.
        if dilemmas.refund(faction_name, M.DILEMMA, choice_key) and slot.key then
            cm:remove_unit_from_character(cm:char_lookup_str(pending.general_cqi), slot.key)
        end
    else
        log("tavern: " .. faction_name .. " hires " .. (slot.key or "a hero") .. " for " .. slot.price .. " gold at the " .. tavern:describe())
        if slot.kind == "hero" then
            tower_lords.free_hero(pending.general_cqi, faction_name, { stock.hero.culture }, stock.hero.rank)
            stock.hero = nil
        elseif slot.kind == "own" then
            table.remove(pending.own, slot.index)
        else
            table.remove(slot.kind == "unit" and stock.units or stock.renown, slot.index)
        end
        if pending.hired == 0 then
            tavern.hall_closed_until[faction_name] = cm:turn_number() + get_mct_settings().tavern_cooldown
            log("tavern: the hall of the " .. tavern:describe() .. " is closed to " .. faction_name .. " until turn " .. tavern.hall_closed_until[faction_name])
        end
        pending.hired = pending.hired + 1
        if pending.hired >= get_mct_settings().tavern_hires_per_visit then
            log("tavern: " .. faction_name .. " has hired " .. pending.hired .. " this visit, so the hub reopens")
            tavern:open_hub(faction, pending.general_cqi)
            return
        end
    end
    M.open(tavern, faction, pending.general_cqi, pending.own, pending.hired)
end

return M
