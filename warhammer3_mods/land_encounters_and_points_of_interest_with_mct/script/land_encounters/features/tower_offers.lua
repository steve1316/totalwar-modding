--- Tower offers: draws the roguelite offers onto each go-deeper dilemma, builds their choices and applies the one the player takes. The
--- offer records live in configs/tower_offers.lua. This file holds when each offer can be drawn and what it does.

require("script/land_encounters/utils/random")

local offers_data = require("script/land_encounters/configs/tower_offers")
local tower_data = require("script/land_encounters/configs/tower_data")
local tower_army = require("script/land_encounters/features/tower_army")
local item_pool = require("script/land_encounters/core/item_pool")

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

--- True when the delving army has lost any strength.
--- @param ctx table The offer context: { delve, faction_name, dividends }.
--- @returns boolean True when the army is below full strength.
local function army_damaged(ctx)
    local strength = tower_army.army_strength(ctx.delve.general_cqi)
    return strength ~= nil and strength < 100
end

--- Heals the army by the offer's `heal_share`.
--- @param offer table The offer record.
--- @param ctx table The offer context.
local function heal(offer, ctx)
    tower_army.heal_army(ctx.delve.general_cqi, offer.heal_share)
end

--- Records the offer's next-floor changes (`next_budget`, `next_gold`, `rarity_shift`) on the delve.
--- @param offer table The offer record.
--- @param delve table The delve record.
local function change_next_floor(offer, delve)
    delve.next_floor = { budget = offer.next_budget, gold = offer.next_gold, rarity_shift = offer.rarity_shift }
end

--- Adds an item to the haul unless it already holds it.
--- @param haul table The delve's haul.
--- @param item string The ancillary key.
local function add_item(haul, item)
    for _, held in ipairs(haul.items) do
        if held == item then return end
    end
    haul.items[#haul.items + 1] = item
end

--- Reads the faction's treasury.
--- @param faction_name string The faction key.
--- @returns number The treasury gold, or 0 when the faction is missing.
local function treasury(faction_name)
    local faction = cm:get_faction(faction_name)
    return faction and faction:treasury() or 0
end

--- When each offer can be drawn and what it does. `eligible(ctx)` returns true when the offer would do something. `apply(offer, ctx)` runs
--- after its cost is paid. A stay offer's `apply` returns its outcome (the result loc key suffix) and the values for that line's
--- placeholders. `ctx` is { delve, faction_name, dividends }. An offer with no entry is always eligible and does nothing.
local HANDLERS = {
    tend_wounded = { eligible = army_damaged, apply = heal },
    field_surgeons = { eligible = army_damaged, apply = heal },
    forgotten_shrine = { eligible = army_damaged, apply = heal },
    triage = {
        eligible = army_damaged,
        apply = function(offer, ctx)
            local units = tower_army.unit_strengths(ctx.delve.general_cqi)
            local battered = {}
            for _, entry in ipairs(units) do
                if entry.strength < 100 then battered[#battered + 1] = entry end
            end
            table.sort(battered, function(a, b) return a.strength < b.strength end)
            local healed = {}
            for i = 1, math.min(offer.count, #battered) do
                tower_army.set_strength(battered[i].unit, 100)
                healed[battered[i]] = true
            end
            local healthiest = nil
            for _, entry in ipairs(units) do
                if not healed[entry] and (healthiest == nil or entry.strength > healthiest.strength) then healthiest = entry end
            end
            if healthiest then tower_army.set_strength(healthiest.unit, healthiest.strength - offer.penalty) end
        end,
    },
    blood_transfusion = {
        eligible = army_damaged,
        apply = function(offer, ctx)
            heal(offer, ctx)
            local force = tower_army.delving_force(ctx.delve.general_cqi)
            if force then cm:apply_effect_bundle_to_force(offer.effect_bundle, force:command_queue_index(), offer.turns) end
        end,
    },
    rest_by_the_fire = {
        eligible = army_damaged,
        apply = function(offer, ctx)
            heal(offer, ctx)
            change_next_floor(offer, ctx.delve)
        end,
    },
    reforge_the_fallen = {
        eligible = function(ctx)
            for _, entry in ipairs(tower_army.unit_strengths(ctx.delve.general_cqi)) do
                if entry.strength < find("reforge_the_fallen").below then return true end
            end
            return false
        end,
        apply = function(_, ctx)
            local weakest = nil
            for _, entry in ipairs(tower_army.unit_strengths(ctx.delve.general_cqi)) do
                if weakest == nil or entry.strength < weakest.strength then weakest = entry end
            end
            if weakest then tower_army.set_strength(weakest.unit, 100) end
        end,
    },
    war_rites = {
        apply = function(offer, ctx)
            local force = tower_army.delving_force(ctx.delve.general_cqi)
            if not force then return end
            cm:apply_effect_bundle_to_force(offer.effect_bundle, force:command_queue_index(), 0)
            ctx.delve.war_rites = true
        end,
    },
    loaded_dice = {
        eligible = function(ctx) return has_gold(ctx.delve) end,
        apply = function(_, ctx)
            local haul = ctx.delve.haul
            local won = random_number(2) == 1
            haul.gold = won and haul.gold * 2 or round_gold(haul.gold / 2)
            return won and "loaded_dice_won" or "loaded_dice_lost", { gold_text(haul.gold) }
        end,
    },
    send_a_runner = {
        eligible = function(ctx) return has_gold(ctx.delve) end,
        apply = function(offer, ctx)
            local haul = ctx.delve.haul
            local sent = round_gold(haul.gold * offer.share)
            local banked = round_gold(sent * (1 - offer.fee))
            haul.gold = haul.gold - sent
            cm:treasury_mod(ctx.faction_name, banked)
            return "send_a_runner", { gold_text(banked), gold_text(haul.gold) }
        end,
    },
    tower_vault = {
        --- The legendary is picked once per delve when the vault is first considered, so the offer only shows when one qualifies.
        eligible = function(ctx)
            ctx.delve.vault_item = ctx.delve.vault_item or item_pool.pick_legendary_item(ctx.faction_name)
            return ctx.delve.vault_item ~= nil
        end,
        apply = function(_, ctx)
            local item = ctx.delve.vault_item or item_pool.pick_legendary_item(ctx.faction_name)
            ctx.delve.vault_item = nil
            if not item then return end
            add_item(ctx.delve.haul, item)
            local name = common.get_localised_string("ancillaries_onscreen_name_" .. item)
            return "tower_vault", { name ~= "" and name or item }
        end,
    },
    treasure_map = {
        eligible = function(ctx)
            local next_floor = tower_data.floors[ctx.delve.floor + 1]
            return next_floor ~= nil and next_floor.item_rarities ~= nil
        end,
        apply = function(_, ctx) ctx.delve.next_floor = { rarity_shift = 1 } end,
    },
    greedy_climb = { apply = function(offer, ctx) change_next_floor(offer, ctx.delve) end },
    tower_dividends = {
        apply = function(offer, ctx)
            ctx.dividends[#ctx.dividends + 1] = { faction = ctx.faction_name, amount = offer.per_turn, turns = offer.turns }
            cm:apply_effect_bundle(offer.effect_bundle, ctx.faction_name, offer.turns)
            return "tower_dividends", { gold_text(offer.per_turn), offer.turns }
        end,
    },
    strip_the_dead = {
        eligible = function(ctx) return (ctx.delve.floor_army_size or 0) > 0 end,
        apply = function(offer, ctx)
            local gold = ctx.delve.floor_army_size * offer.per_unit
            ctx.delve.haul.gold = ctx.delve.haul.gold + gold
            return "strip_the_dead", { gold_text(gold), gold_text(ctx.delve.haul.gold) }
        end,
    },
    tithe = {
        eligible = function(ctx) return treasury(ctx.faction_name) >= find("tithe").min_treasury end,
        apply = function(offer, ctx)
            local paid = round_gold(treasury(ctx.faction_name) * offer.share)
            cm:treasury_mod(ctx.faction_name, -paid)
            ctx.delve.haul.gold = ctx.delve.haul.gold + paid * offer.multiplier
            return "tithe", { gold_text(paid), gold_text(paid * offer.multiplier) }
        end,
    },
    cursed_idol = {
        apply = function(offer, ctx)
            ctx.delve.haul.gold = ctx.delve.haul.gold + offer.gold
            change_next_floor(offer, ctx.delve)
        end,
    },
}

--- True when an offer can be drawn: not already taken this delve (unless repeatable) and its condition holds.
--- @param offer table The offer record.
--- @param ctx table The offer context.
--- @returns boolean True when the offer can be drawn.
local function eligible(offer, ctx)
    if ctx.delve.taken[offer.key] and not offer.repeatable then return false end
    local handler = HANDLERS[offer.key]
    return not (handler and handler.eligible) or handler.eligible(ctx)
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
--- @param faction_name string The delving faction.
--- @returns table Offer keys in popup order.
function M.draw(delve, faction_name)
    delve.taken = delve.taken or {}
    local ctx = { delve = delve, faction_name = faction_name }
    local pool = {}
    for _, offer in ipairs(offers_data.offers) do
        if eligible(offer, ctx) then pool[#pool + 1] = offer.key end
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
--- @param dividends table The tower delegate's dividend list, which Tower dividends adds to.
--- @returns table|nil The offer record, or nil when the choice is not an offer on the dilemma.
--- @returns string|nil The offer's result line for the reopened dilemma, or nil when it has none.
function M.take(choice_key, delve, faction_name, dividends)
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
    local outcome, values = handler.apply(offer, { delve = delve, faction_name = faction_name, dividends = dividends })
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
