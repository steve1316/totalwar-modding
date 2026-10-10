--- The boon and curse services: the Smithy's Temper and Break room and the Tavern's hedge-witch (configs/boons.lua `smithy_room` and
--- `witch_room`). Each room lists the visiting lord's boons and curses with a price each, charged by the dilemma payload. features/smithy.lua
--- and features/tavern.lua open the rooms, keep the open room on their state (so it is saved with it) and hand its choices back here.

require("script/land_encounters/utils/common")
require("script/land_encounters/utils/random")

local data = require("script/land_encounters/configs/boons")
local offers_data = require("script/land_encounters/configs/spot_offers")
local tower_offers = require("script/land_encounters/configs/tower_offers")
local boons = require("script/land_encounters/features/boons")
local dilemmas = require("script/land_encounters/core/dilemmas")
local tower_army = require("script/land_encounters/features/tower_army")

local M = {
    --- Faction key -> the result line of the service it just used, shown at the top of the room when it reopens.
    last_result = {},
}

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Constants

--- Payload text under a service the treasury cannot pay, shared with the spot offers.
local LINE_UNAFFORDABLE = offers_data.unaffordable_line

--- Loc key prefix of the services' result lines.
local RESULT_LOC = "campaign_localised_strings_string_" .. data.result_prefix

--- Payload text of the hedge-witch's Back, shared with the bar.
local LINE_BACK = offers_data.line_prefix .. offers_data.tavern.leave_line

--- The Rust for Iron pact the Smithy room offers, read from the tower offers.
local RUST_OFFER = tower_offers.by_key[data.smithy_room.rust_offer]

--- The services that work on a boon. Every other one works on a curse.
local BOON_SERVICES = { temper = true, feed = true, reweave = true }

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Helpers

--- A service payload line, e.g. "top".
--- @param name string The line's name after `service_line_prefix`.
--- @returns string The payload line key.
function M.line(name)
    return data.service_line_prefix .. name
end

--- The line saying why a boon cannot be tempered, fed or rewoven, or nil when it can.
--- @param boon table The boon.
--- @returns string|nil The payload line key.
local function boon_closed(boon)
    if boon.charges then return M.line("charged") end
    if not boons.can_grow(boon) then return M.line("top") end
    return nil
end

--- True when a lord carries at least one boon or curse, so the hedge-witch has something to do.
--- @param character userdata|nil The lord.
--- @returns boolean True when they carry a boon or a curse.
function M.has_work(character)
    if character == nil then return false end
    local record = boons.find_record(character)
    return #record.boon > 0 or #record.curse > 0
end

--- Starts a room's slots and choices. `add` puts in one slot: a service with no price, one closed with a reason (its price dropped), one the
--- treasury cannot pay (still showing its price, marked so a click on it anyway is refunded), or one it can.
--- @param treasury number The visiting faction's gold.
--- @returns table, table, function The slots, the choices, and `add(choice_key, kind, index, entry, gold, lines, closed_line)`.
local function room(treasury)
    local slots, choices = {}, {}
    local function add(choice_key, kind, index, entry, gold, lines, closed_line)
        if closed_line then gold = nil end
        local slot = { choice = choice_key, kind = kind, list = BOON_SERVICES[kind] and "boon" or "curse", index = index, key = entry and entry.key,
            level = entry and entry.level, price = gold }
        local choice = { key = choice_key, lines = lines, lines_first = true }
        if closed_line then
            lines[#lines + 1] = closed_line
            choice.closed = true
        elseif gold and treasury < gold then
            lines[#lines + 1] = LINE_UNAFFORDABLE
            choice.gold = -gold
            choice.unaffordable = true
        else
            slot.ok = true
            if gold then choice.gold = -gold end
        end
        slots[#slots + 1] = slot
        choices[#choices + 1] = choice
    end
    return slots, choices, add
end

--- Logs what a room shows and opens it for a lord, naming the lord in its description.
--- @param dilemma_key string The room's dilemma.
--- @param character userdata The visiting lord.
--- @param faction_name string The visiting faction.
--- @param what string The room and anything else to log, e.g. "smithy room".
--- @param slots table The slots it shows.
--- @param choices table Its choices.
--- @returns table The open room: { cqi, slots }.
local function launch(dilemma_key, character, faction_name, what, slots, choices)
    local shown = {}
    for _, slot in ipairs(slots) do
        shown[#shown + 1] = slot.kind .. (slot.key and (" " .. slot.key .. " " .. slot.level) or "") .. (slot.price and (" for " .. slot.price) or "")
            .. (slot.ok and "" or " (closed)")
    end
    local cqi = character:command_queue_index()
    log("boons: " .. what .. " for lord " .. cqi .. " of " .. faction_name .. ": " .. (#shown > 0 and table.concat(shown, ", ") or "nothing"))
    common.set_context_value(data.lord_context, lord_name(character))
    common.set_context_value(data.result_context, text_block(M.last_result[faction_name] and { M.last_result[faction_name] } or {}))
    M.last_result[faction_name] = nil
    dilemmas.launch(dilemma_key, choices, faction_name)
    return { cqi = cqi, slots = slots }
end

--- A boon's or curse's name and level as the game shows it, e.g. "Bloodsworn III".
--- @param kind string "boon" or "curse".
--- @param entry table|nil The entry.
--- @returns string The name, or "" for none.
local function title(kind, entry)
    return entry and common.get_localised_string("character_trait_levels_onscreen_name_" .. boons.trait(kind, entry) .. "_" .. entry.level) or ""
end

--- Keeps a service's result line for the room's next opening, with the names filled in.
--- @param faction_name string The faction that used the service.
--- @param service string The result's name, e.g. "gamble_lost".
--- @param old string The name of the boon or curse before.
--- @param new string|nil The name after, for a temper, a failed gamble or Rust for Iron.
local function keep_result(faction_name, service, old, new)
    local text = common.get_localised_string(RESULT_LOC .. service)
    text = text:gsub("{old}", (old:gsub("%%", "%%%%"))):gsub("{new}", ((new or ""):gsub("%%", "%%%%")))
    M.last_result[faction_name] = text
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Rooms

--- Opens the Smithy's Temper and Break room for a lord: a temper per boon (showing the level it reaches), a break per curse, Rust for Iron
--- unless taken on this visit, and Back to the forge. A charged boon or one at its highest level cannot be tempered and says why.
--- @param character userdata The visiting lord.
--- @param faction_name string The visiting faction.
--- @param price function Base gold -> the gold this Smithy charges for it.
--- @param rust_taken boolean|nil True when the lord took Rust for Iron on this visit already.
--- @param back_line string The payload text of Back, shared with the forge's Work Orders.
--- @returns table The open room to keep on the Smithy: { cqi, slots, rust_taken }.
function M.open_smithy(character, faction_name, price, rust_taken, back_line)
    local spec, record = data.smithy_room, boons.find_record(character)
    local slots, choices, add = room(dilemmas.treasury(faction_name))
    for i, boon in ipairs(record.boon) do
        local closed = boon_closed(boon)
        local shown = closed and boon or { key = boon.key, level = boon.level + 1, race = boon.race }
        add(spec.temper_choices[i], "temper", i, boon, price(spec.temper_price * (boon.level + 1)), { boons.line("boon", shown) }, closed)
    end
    for i, curse in ipairs(record.curse) do
        add(spec.break_choices[i], "break", i, curse, price(spec.break_price * curse.level), { boons.line("curse", curse) })
    end
    if RUST_OFFER and not rust_taken then
        add(spec.rust_choice, "rust", nil, nil, nil, { boons.line("boon", { key = RUST_OFFER.boon[1], level = RUST_OFFER.boon[2] }),
            boons.line("curse", { key = RUST_OFFER.curse[1], level = RUST_OFFER.curse[2] }) })
    end
    choices[#choices + 1] = { key = spec.back_choice, lines = { back_line } }
    local open_room = launch(spec.dilemma, character, faction_name, "smithy room", slots, choices)
    open_room.rust_taken = rust_taken == true
    return open_room
end

--- Opens the hedge-witch for a lord: a feed and a reweave per boon, a cleanse, a gamble and a blood rite per curse, then Back. A service is
--- closed, saying for how long, while the lord's last use of it at this Tavern cools down. A charged boon or one at its highest level cannot
--- be fed or rewoven and says why.
--- @param character userdata The visiting lord.
--- @param faction_name string The visiting faction.
--- @param price function Base gold -> the gold this Tavern charges the visitor for it.
--- @param cooling table Service kind (each of `cooldowns`) -> turns until the lord may use it here again, 0 or nil when now.
--- @returns table The open room to keep on the Tavern: { cqi, slots }.
function M.open_witch(character, faction_name, price, cooling)
    local spec, record = data.witch_room, boons.find_record(character)
    local slots, choices, add = room(dilemmas.treasury(faction_name))
    --- The line closing a service while it cools down, or nil.
    local function cooled(kind)
        local turns = cooling[kind] or 0
        return turns > 0 and M.line(kind .. "_cooling_" .. turns) or nil
    end
    for i, boon in ipairs(record.boon) do
        local closed = boon_closed(boon)
        add(spec.feed_choices[i], "feed", i, boon, price(spec.feed_price * boon.level), { boons.line("boon", boon), M.line("feed") }, closed or cooled("feed"))
        add(spec.reweave_choices[i], "reweave", i, boon, price(spec.reweave_price * boon.level), { boons.line("boon", boon), M.line("reweave") },
            closed or cooled("reweave"))
    end
    for i, curse in ipairs(record.curse) do
        add(spec.cleanse_choices[i], "cleanse", i, curse, price(spec.cleanse_price * curse.level), { boons.line("curse", curse) })
        add(spec.gamble_choices[i], "gamble", i, curse, price(spec.gamble_price * curse.level), { boons.line("curse", curse), M.line("gamble") }, cooled("gamble"))
        add(spec.blood_choices[i], "blood", i, curse, nil, { boons.line("curse", curse), M.line("blood_" .. curse.level) }, cooled("blood"))
    end
    choices[#choices + 1] = { key = spec.back_choice, lines = { LINE_BACK } }
    local cooling_note = {}
    for kind, turns in pairs(cooling) do
        if turns > 0 then cooling_note[#cooling_note + 1] = kind .. " " .. turns end
    end
    table.sort(cooling_note)
    return launch(spec.dilemma, character, faction_name, "hedge-witch (cooling: " .. (#cooling_note > 0 and table.concat(cooling_note, ", ") or "none") .. ")",
        slots, choices)
end

--- Applies a room choice. The payload already charged the price. A closed or unpaid choice clicked anyway is refunded and changes nothing,
--- and so does one whose boon or curse changed since the room opened.
--- @param open_room table The open room, from `open_smithy` or `open_witch`.
--- @param faction_name string The faction that chose.
--- @param dilemma_key string The room's dilemma.
--- @param choice_key string The chosen choice key.
--- @returns string, table|nil, userdata|nil "leave" for Leave or Back (or a lord who is gone), else "reopen", the slot that was used, if any, and
--- the lord.
function M.resolve(open_room, faction_name, dilemma_key, choice_key)
    dilemmas.refund(faction_name, dilemma_key, choice_key)
    local character = tower_army.character(open_room.cqi)
    local slot = dilemmas.find_slot(open_room.slots, choice_key)
    M.last_result[faction_name] = nil
    if not (character and slot) then
        log("boons: " .. faction_name .. " leaves " .. dilemma_key)
        return "leave", nil
    end
    if not slot.ok then
        log("boons: " .. faction_name .. " chose " .. choice_key .. ", shown as closed, so nothing happens")
        return "reopen", nil, character
    end
    local record = boons.find_record(character)
    local list = record[slot.list]
    local entry = slot.index and list[slot.index]
    if slot.index and not (entry and entry.key == slot.key and entry.level == slot.level) then
        log("boons: " .. faction_name .. " chose " .. choice_key .. ", but that slot changed since the room opened, so nothing happens")
        if slot.price then cm:treasury_mod(faction_name, slot.price) end
        return "reopen", nil, character
    end
    log("boons: lord " .. open_room.cqi .. " of " .. faction_name .. " uses " .. slot.kind .. (slot.key and (" on " .. slot.key .. " " .. slot.level) or "")
        .. (slot.price and (" for " .. slot.price .. " gold") or ""))
    if slot.kind == "temper" then
        local before = title("boon", entry)
        boons.raise(character, "boon", entry, "boon_tempered")
        keep_result(faction_name, "temper", before, title("boon", entry))
    elseif slot.kind == "break" or slot.kind == "cleanse" then
        keep_result(faction_name, slot.kind, title("curse", entry))
        boons.remove(character, "curse", slot.index, slot.kind == "break" and "curse_broken" or "curse_cleansed")
    elseif slot.kind == "gamble" then
        local before = title("curse", entry)
        local lifted = random_chance(data.witch_room.gamble_lift_chance)
        log("boons: the gamble " .. (lifted and "lifts the curse" or "shifts the curse"))
        if not lifted and boons.shift(character, "curse", slot.index, "curse_shifted") then
            keep_result(faction_name, "gamble_lost", before, title("curse", record.curse[slot.index]))
        else
            keep_result(faction_name, "gamble_won", before)
            boons.remove(character, "curse", slot.index, "gamble_won")
        end
    elseif slot.kind == "blood" then
        local bleed = data.witch_room.blood_bleed * entry.level
        tower_army.bleed_army(open_room.cqi, bleed, "blood rite")
        keep_result(faction_name, "blood", title("curse", entry))
        boons.remove(character, "curse", slot.index, "blood_rite")
    elseif slot.kind == "feed" then
        local before = title("boon", entry)
        local raised = boons.add_wins(character, entry, data.witch_room.feed_wins, "boon_fed")
        keep_result(faction_name, raised and "feed_raised" or "feed", before, title("boon", entry))
    elseif slot.kind == "reweave" then
        local before = title("boon", entry)
        local rises = random_chance(data.witch_room.reweave_rise_chance)
        log("boons: the reweave " .. (rises and "raises the boon" or "shifts the boon"))
        if rises and boons.raise(character, "boon", entry, "boon_rewoven") then
            keep_result(faction_name, "reweave_won", before, title("boon", entry))
        elseif boons.shift(character, "boon", slot.index, "boon_shifted") then
            keep_result(faction_name, "reweave_lost", before, title("boon", record.boon[slot.index]))
        else
            keep_result(faction_name, "reweave_held", before)
        end
    elseif slot.kind == "rust" then
        local _, boon = boons.gain(character, "boon", RUST_OFFER.boon[1], RUST_OFFER.boon[2], nil, false)
        local _, curse = boons.gain(character, "curse", RUST_OFFER.curse[1], RUST_OFFER.curse[2], nil, false)
        local lines = {}
        if boon then lines[#lines + 1] = boons.line("boon", boon) end
        if curse then lines[#lines + 1] = boons.line("curse", curse) end
        boons.announce("rust_struck", character, lines)
        keep_result(faction_name, "rust", title("curse", curse), title("boon", boon))
        open_room.rust_taken = true
    end
    return "reopen", slot, character
end

return M
