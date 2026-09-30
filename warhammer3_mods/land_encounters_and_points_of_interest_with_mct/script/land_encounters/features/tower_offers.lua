--- Tower offers: draws the roguelite offers onto each go-deeper dilemma, builds their choices and applies the one the player takes. The
--- offer records live in configs/tower_offers.lua. This file holds when each offer can be drawn and what it does.

require("script/land_encounters/utils/random")

local offers_data = require("script/land_encounters/configs/tower_offers")
local tower_data = require("script/land_encounters/configs/tower_data")
local tower_army = require("script/land_encounters/features/tower_army")

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Constants

--- Prefix of every offer's choice key. The rest is the offer's key in capitals.
local CHOICE_KEY_PREFIX = "LEAPOI_TWR_"
--- Prefix of every offer's payload line. The rest is the offer's key.
local LINE_PREFIX = "dummy_land_enc_tower_"
--- Payload line telling the player a stay offer brings them back to the same choice.
local RETURNS_HERE_LINE = "dummy_land_enc_tower_returns_here"
--- Script context value shown at the top of every per-floor go-deeper description through `ScriptObjectContext`.
local RESULT_CONTEXT_KEY = "land_enc_tower_result"
--- Prefix of the loc keys holding each stay offer's result line. The rest is the outcome, e.g. "loaded_dice_won".
local RESULT_LOC_PREFIX = "campaign_localised_strings_string_land_enc_tower_result_"

local M = {
    --- Choice key of Leave on the per-floor go-deeper dilemmas.
    LEAVE = offers_data.leave_choice_key,
}

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Helpers

--- Rounds gold to the tower's gold step.
--- @param gold number The gold amount.
--- @returns number The amount rounded to a multiple of `tower_data.gold_step`.
local function round_gold(gold)
    return math.floor(gold / tower_data.gold_step + 0.5) * tower_data.gold_step
end

--- Writes gold with thousands separators, e.g. 3000 as "3,000".
--- @param gold number The gold amount.
--- @returns string The formatted amount.
local function gold_text(gold)
    local text = tostring(math.floor(gold)):reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return (text:gsub("^,", ""))
end

--- True when the haul holds enough gold for a gold offer to change it.
--- @param delve table The delve record.
--- @returns boolean True with at least two gold steps in the haul.
local function has_gold(delve)
    return delve.haul.gold >= 2 * tower_data.gold_step
end

--- Finds an offer record by its key.
--- @param key string The offer key, e.g. "war_rites".
--- @returns table|nil The offer record.
local function find(key)
    for _, offer in ipairs(offers_data.offers) do
        if offer.key == key then return offer end
    end
    return nil
end

--- When each offer can be drawn and what it does. `eligible(delve)` returns true when the offer would do something. `apply(offer, delve,
--- faction_name)` runs after its cost is paid. A stay offer's `apply` returns its outcome (the result loc key suffix) and the values for
--- that line's placeholders. An offer with no entry is always eligible and does nothing.
local HANDLERS = {
    tend_wounded = {
        eligible = function(delve)
            local strength = tower_army.army_strength(delve.general_cqi)
            return strength ~= nil and strength < 100
        end,
        apply = function(offer, delve) tower_army.heal_army(delve.general_cqi, offer.heal_share) end,
    },
    war_rites = {
        apply = function(offer, delve)
            local force = tower_army.delving_force(delve.general_cqi)
            if not force then return end
            cm:apply_effect_bundle_to_force(offer.effect_bundle, force:command_queue_index(), 0)
            delve.war_rites = true
        end,
    },
    loaded_dice = {
        eligible = has_gold,
        apply = function(_, delve)
            local won = random_number(2) == 1
            delve.haul.gold = won and delve.haul.gold * 2 or round_gold(delve.haul.gold / 2)
            return won and "loaded_dice_won" or "loaded_dice_lost", { gold_text(delve.haul.gold) }
        end,
    },
    send_a_runner = {
        eligible = has_gold,
        apply = function(offer, delve, faction_name)
            local sent = round_gold(delve.haul.gold * offer.share)
            local banked = round_gold(sent * (1 - offer.fee))
            delve.haul.gold = delve.haul.gold - sent
            cm:treasury_mod(faction_name, banked)
            return "send_a_runner", { gold_text(banked), gold_text(delve.haul.gold) }
        end,
    },
}

--- True when an offer can be drawn: not already taken this delve (unless repeatable) and its condition holds.
--- @param offer table The offer record.
--- @param delve table The delve record.
--- @returns boolean True when the offer can be drawn.
local function eligible(offer, delve)
    if delve.taken[offer.key] and not offer.repeatable then return false end
    local handler = HANDLERS[offer.key]
    return not (handler and handler.eligible) or handler.eligible(delve)
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Offers

--- Builds an offer's choice key.
--- @param offer table The offer record.
--- @returns string The choice key, e.g. "LEAPOI_TWR_WAR_RITES".
function M.choice_key(offer)
    return CHOICE_KEY_PREFIX .. offer.key:upper()
end

--- Draws up to `offers_per_floor` eligible offers with `random_number`, so every multiplayer client draws the same ones.
--- @param delve table The delve record.
--- @returns table Offer keys in popup order.
function M.draw(delve)
    delve.taken = delve.taken or {}
    local pool = {}
    for _, offer in ipairs(offers_data.offers) do
        if eligible(offer, delve) then pool[#pool + 1] = offer.key end
    end
    local picked = {}
    for _ = 1, math.min(offers_data.offers_per_floor, #pool) do
        picked[table.remove(pool, random_number(#pool))] = true
    end
    local keys = {}
    for _, offer in ipairs(offers_data.offers) do
        if picked[offer.key] then keys[#keys + 1] = offer.key end
    end
    return keys
end

--- Builds an offer's go-deeper choice: its line (or its not-enough-gold line when the haul cannot pay), then where it leads.
--- @param offer_key string The offer key.
--- @param delve table The delve record.
--- @param next_floor number The floor a climbing offer leads to.
--- @returns table A choice record for `launch_dilemma`.
function M.choice(offer_key, delve, next_floor)
    local offer = find(offer_key)
    local line = LINE_PREFIX .. offer.key
    if offer.cost and delve.haul.gold < offer.cost then line = line .. "_unaffordable" end
    local after = offer.stay and RETURNS_HERE_LINE or "dummy_land_enc_tower_descend_floor_" .. next_floor
    return { key = M.choice_key(offer), lines = { line, after } }
end

--- Takes an offer from the delve's dilemma. It leaves the dilemma, and when the haul can pay its cost it is paid, marked taken and applied.
--- @param choice_key string The chosen choice key.
--- @param delve table The delve record.
--- @param faction_name string The delving faction.
--- @returns table|nil The offer record, or nil when the choice is not an offer on the dilemma.
--- @returns string|nil The offer's result line for the reopened dilemma, or nil when it has none.
function M.take(choice_key, delve, faction_name)
    local offer = nil
    for i, key in ipairs(delve.offers or {}) do
        if CHOICE_KEY_PREFIX .. key:upper() == choice_key then
            offer = find(table.remove(delve.offers, i))
            break
        end
    end
    if offer == nil or (offer.cost and delve.haul.gold < offer.cost) then return offer end
    delve.haul.gold = delve.haul.gold - (offer.cost or 0)
    delve.taken = delve.taken or {}
    delve.taken[offer.key] = true
    local handler = HANDLERS[offer.key]
    if not (handler and handler.apply) then return offer end
    local outcome, values = handler.apply(offer, delve, faction_name)
    local template = outcome and common.get_localised_string(RESULT_LOC_PREFIX .. outcome) or ""
    if template == "" then return offer end
    values = values or {}
    return offer, string.format(template, values[1], values[2])
end

--- Shows the floor's stay-offer results at the top of the per-floor go-deeper descriptions, one line each in the order taken, then a blank
--- line before the description. No results clears it.
--- @param delve table The delve record. `delve.results` holds this floor's result lines.
function M.show_results(delve)
    local results = delve.results or {}
    common.set_context_value(RESULT_CONTEXT_KEY, #results > 0 and table.concat(results, "\n") .. "\n\n" or "")
end

--- Takes the one-battle effects off the delving army once the floor they were bought for is over.
--- @param delve table The delve record.
function M.end_battle_effects(delve)
    if not delve.war_rites then return end
    delve.war_rites = nil
    local force = tower_army.delving_force(delve.general_cqi)
    if force then cm:remove_effect_bundle_from_force(find("war_rites").effect_bundle, force:command_queue_index()) end
end

return M
