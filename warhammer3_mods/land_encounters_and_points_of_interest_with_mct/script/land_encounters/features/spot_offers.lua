--- Spot offers on treasure sites: a human lord entering a treasure spot rolls a site, whose dilemma offers its signature reward, 2 more offers
--- drawn toward its tags, and Walk away. Offers are paid from the treasury and act through the shared offer effects and realm effects. The
--- offer and site records live in configs/spot_offers.lua.

require("script/land_encounters/utils/random")
require("script/land_encounters/utils/common")

local offers_data = require("script/land_encounters/configs/spot_offers")
local treasure_events = require("script/land_encounters/configs/events").treasure_type
local debug_config = require("script/land_encounters/configs/debug")
local offer_effects = require("script/land_encounters/core/offer_effects")
local realm_effects = require("script/land_encounters/core/realm_effects")
local item_pool = require("script/land_encounters/core/item_pool")
local dilemmas = require("script/land_encounters/core/dilemmas")
local tower_army = require("script/land_encounters/features/tower_army")
local tower_lords = require("script/land_encounters/features/tower_lords")

local M = {
    --- Faction key -> the site dilemma it has open: { site, offers, signature, general_cqi, x, y, difficulty, cards, targets, shown_affordable }.
    --- `cards` maps an offer's key to the { units, items } it shows, and `targets` a realm offer's key to its target, so a reopened site shows
    --- the same ones. `shown_affordable` says whether each offer's button could be bought when the dilemma was last shown.
    pending_by_faction = {},
    --- Lords who may move again at their faction's next turn start: { faction, general_cqi }.
    camps = {},
    --- Caravan investments still paying out: { faction, amount, turns }, paid at each of that faction's turn starts.
    dividends = {},
    --- Sends Daemon's deal armies at a faction's capital: (faction_name, count). Set by the POI manager to the tower's sender, which owns the
    --- invasion plumbing.
    send_daemon_army = nil,
    --- Starts Wake the guardian's battle for a lord at a map position. Set by the spot event manager to the battle spots' own battle start.
    start_guardian_battle = nil,
}

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Helpers

--- An offer's cost, or the debug `spot_cost` (configs/debug.lua) for every paid offer while it is set.
--- @param offer table The offer record at its difficulty, with a `cost`.
--- @returns number The gold it costs.
function M.offer_cost(offer)
    return debug_config.spot_cost[1] or offer.cost
end

--- Builds an offer's choice key.
--- @param key string The offer key.
--- @returns string The choice key, e.g. LEAPOI_SPT_TAKE_THE_GOLD.
function M.choice_key(key)
    return offers_data.choice_key_prefix .. key:upper()
end

--- Finds the old treasure incident's targets, for a signature offer that fires it.
--- @param incident string The incident key.
--- @returns table The targets flag map.
local function incident_targets(incident)
    for _, event in ipairs(treasure_events) do
        if event.incident == incident then return event.targets end
    end
    return { character = true }
end

--- Shows a result as an incident built in script: its payload grants the result's gold, items and units as cards, and shows its effect line
--- when it has one. If the incident cannot be built, the rewards are granted in script and the result's old event message shows instead,
--- so nothing is lost.
--- @param faction_name string The faction the result is for.
--- @param result string The result name, e.g. "roll_the_bones_won".
--- @param rewards table { gold, items, units, character }: gold to add or take, item keys, and unit keys to join the lord `character`'s army.
--- @param position table The { x, y } map position of the fallback message.
--- @param subtitle string|nil A loc key for the fallback message's subtitle. A realm result's incident names it in its text.
function M.show_result(faction_name, result, rewards, position, subtitle)
    local faction = cm:get_faction(faction_name)
    local character = rewards.character
    local force = character and character:has_military_force() and character:military_force() or nil
    local line = offers_data.line_prefix .. "result_" .. result
    local ok, err = pcall(function()
        common.set_context_value(offers_data.result_place_context, subtitle and common.get_localised_string(subtitle) or "")
        local builder = cm:create_incident_builder(offers_data.result_incident_prefix .. result)
        local payload = cm:create_payload()
        if rewards.gold and rewards.gold ~= 0 then payload:treasury_adjustment(rewards.gold) end
        for _, item in ipairs(rewards.items or {}) do payload:faction_ancillary_gain(faction, item) end
        for _, unit in ipairs(force and rewards.units or {}) do payload:add_unit(force, unit, 1, 0) end
        if common.get_localised_string("campaign_payload_ui_details_description_" .. line) ~= "" then payload:text_display(line) end
        builder:set_payload(payload)
        cm:launch_custom_incident_from_builder(builder, faction)
    end)
    if ok then
        log("spot: result " .. result .. " shown for " .. faction_name .. " with gold " .. tostring(rewards.gold) .. ", items "
            .. table.concat(rewards.items or {}, ", ") .. ", units " .. table.concat(rewards.units or {}, ", "))
        return
    end
    log("spot: result incident " .. result .. " could not be built (" .. tostring(err) .. "), granting in script and showing its message")
    if rewards.gold and rewards.gold ~= 0 then cm:treasury_mod(faction_name, rewards.gold) end
    for _, item in ipairs(rewards.items or {}) do cm:add_ancillary_to_faction(faction, item, false) end
    for _, unit in ipairs(character and rewards.units or {}) do cm:grant_unit_to_character(cm:char_lookup_str(character), unit) end
    show_located_message(faction_name, offers_data.message_prefix .. result, position, subtitle)
end

--- True when one of an offer's gamble outcomes has a field, e.g. `unique` or `guardian`.
--- @param offer table The offer record.
--- @param field string The outcome field.
--- @returns boolean True when an outcome sets it.
local function gamble_has(offer, field)
    for _, outcome in ipairs(offer.gamble or {}) do
        if outcome[field] then return true end
    end
    return false
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Drawing

--- True when an offer would do something for this lord right now. Its cost is not a condition: an offer the treasury cannot pay is still
--- drawn and says so, as tower offers do. Unit and item rewards are picked here and kept on `ctx.cards`, and realm targets on `ctx.targets`,
--- so the dilemma shows exactly what the offer gives.
--- @param offer table The offer record at the draw's difficulty.
--- @param ctx table { faction, faction_name, general_cqi, x, y, difficulty, cards, targets, event }. `event` is the won battle's, on the
--- spoils pick only.
--- @returns boolean True when the offer can be drawn.
local function eligible(offer, ctx)
    if offer.trait and tower_lords.has_trait(ctx.general_cqi, offer.trait) then return false end
    if offer.heal and not offer_effects.army_damaged(ctx.general_cqi) then return false end
    if offer.hero_rank and not offer_effects.has_room(ctx.general_cqi, 1) then return false end
    if offer.sacrifice and #tower_army.regular_units(ctx.general_cqi) < 2 then return false end
    if offer.daemon_armies and not ctx.faction:has_home_region() then return false end
    if gamble_has(offer, "unique") and item_pool.pick_legendary_item(ctx.faction_name) == nil then return false end
    local enemy_units = ctx.event and ctx.event.enemy_units or {}
    if (offer.gold_per_enemy_unit or offer.captive) and #enemy_units == 0 then return false end
    if offer.captive and not offer_effects.has_room(ctx.general_cqi, 1) then return false end

    local cards = {}
    --- Units another offer on this dilemma already shows are left out, so no unit is offered twice.
    ctx.shown_units = ctx.shown_units or {}
    if offer.recruit then
        cards.units = offer_effects.pick_recruits(ctx.general_cqi, offer_effects.culture_shorthand(ctx.faction_name), offer.recruit, ctx.shown_units)
        if #cards.units < offer.recruit.count then return false end
    end
    if offer.renown then
        cards.units = offer_effects.pick_renown(ctx.general_cqi, ctx.faction_name, offer.renown, ctx.shown_units)
        if #cards.units < offer.renown then return false end
    end
    if offer.unique then
        cards.items = offer_effects.pick_unique_items(ctx.faction_name, offer.unique)
        if #cards.items < offer.unique then return false end
    end
    if offer.items then
        cards.items = item_pool.pick_items(ctx.faction_name, offer.items.rarities, offer.items.count)
        if #cards.items == 0 then return false end
    end
    if offer.battle_item then
        local rarities = ctx.event and ctx.event.victory_items and ctx.event.victory_items.rarities or offers_data.default_battle_rarities
        cards.items = item_pool.pick_items(ctx.faction_name, rarities, 1)
        if #cards.items == 0 then return false end
    end
    if offer.captive then
        local captives = {}
        for _, key in ipairs(enemy_units) do
            if not ctx.shown_units[key] then captives[#captives + 1] = key end
        end
        if #captives == 0 then return false end
        cards.units = { captives[random_number(#captives)] }
    end
    for _, key in ipairs(cards.units or {}) do ctx.shown_units[key] = true end
    if offer.gold_per_enemy_unit then cards.gold = offer.gold_per_enemy_unit * #enemy_units end
    if offer.ransom then
        local beaten = ctx.event and ctx.event.faction
        local kin = realm_effects.nearest_factions(ctx.faction, ctx.x, ctx.y, 1, function(other)
            return offer_effects.culture_shorthand(other:name()) == beaten
        end)[1]
        if kin == nil then return false end
        ctx.targets[offer.key] = { regions = {}, factions = { kin:name() } }
    end
    if offer.realm then
        local target = realm_effects.find_target(offer.realm, ctx.faction, ctx.x, ctx.y, offer.count)
        if target == nil then return false end
        ctx.targets[offer.key] = target
    end
    ctx.cards[offer.key] = cards
    return true
end

--- Draws a site's offers: its signature offer when eligible, then `extras_per_site` more from the treasure and realm pools, weighted toward
--- offers that share a tag with the site. Eligible offers in the debug `force_spot_offers` list are drawn first. An offer is only checked once
--- it is drawn, since checking runs map searches and item picks: one that fails leaves the pool and the roll goes again, which draws the same
--- way as checking every offer first. Uses `random_number`, so every multiplayer client draws the same ones.
--- @param site table The site record.
--- @param ctx table The draw context, see `eligible`.
--- @returns table Offer keys in popup order.
--- @returns string|nil The signature offer's key when it was drawn, first in the list.
function M.draw(site, ctx)
    local signature = site.signature and offers_data.at(site.signature, ctx.difficulty)
    local signature_key = signature and eligible(signature, ctx) and signature.key or nil
    local keys = { signature_key }
    local site_tags, pools = {}, {}
    for _, tag in ipairs(site.tags) do site_tags[tag] = true end
    for _, pool in ipairs(site.pools or { "treasure", "realm" }) do pools[pool] = true end
    --- Candidates as { offer, weight } pairs.
    local pool = {}
    for _, offer in ipairs(offers_data.all_at(ctx.difficulty)) do
        if (pools[offer.pool] or (site.pools and offer.spoils)) and offer.key ~= signature_key then
            local weight = 1
            for _, tag in ipairs(offer.tags) do
                if site_tags[tag] then weight = offers_data.tag_weight end
            end
            pool[#pool + 1] = { offer, weight }
        end
    end
    --- Without its signature offer a site draws one more extra, so it still shows 3 offers.
    local wanted = offers_data.extras_per_site + (signature_key and 0 or 1)
    local extras, forced = 0, 0
    --- Takes the candidate at `i` out of the pool, and keeps it when it is eligible.
    local function try(i)
        local offer = table.remove(pool, i)[1]
        if not eligible(offer, ctx) then return false end
        keys[#keys + 1] = offer.key
        extras = extras + 1
        return true
    end
    for _, forced_key in ipairs(debug_config.force_spot_offers) do
        for i, entry in ipairs(pool) do
            if entry[1].key == forced_key and extras < wanted then
                if try(i) then forced = forced + 1 end
                break
            end
        end
    end
    while extras < wanted and #pool > 0 do
        local picked = pick_weighted(pool)
        for i, entry in ipairs(pool) do
            if entry[1] == picked then
                try(i)
                break
            end
        end
    end
    log("spot: drew for " .. ctx.faction_name .. " at " .. site.key .. " (" .. ctx.difficulty .. "): " .. table.concat(keys, ", ") .. " (" .. #pool
        .. " candidates left unchecked, " .. forced .. " forced)")
    return keys, signature_key
end

--- Picks the site for a treasure spot. The first known site in the debug `force_treasure_site` list wins.
--- @returns table The site record.
local function pick_site()
    for _, key in ipairs(debug_config.force_treasure_site) do
        if offers_data.site_by_key[key] then
            log("spot: debug force_treasure_site picks " .. key)
            return offers_data.site_by_key[key]
        end
    end
    return offers_data.sites[random_number(#offers_data.sites)]
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Site dilemma

--- True when the faction's treasury covers an offer's cost.
--- @param offer table The offer record at the site's or battle's difficulty.
--- @param faction_name string The faction key.
--- @returns boolean True for a free offer or one the treasury can pay.
function M.affordable(offer, faction_name)
    return not offer.cost or offer_effects.treasury(faction_name) >= M.offer_cost(offer)
end

--- An offer's choice key on its open site: the signature offer sits on the first key.
--- @param pending table The open site.
--- @param key string The offer key.
--- @returns string The choice key.
local function site_choice_key(pending, key)
    return key == pending.signature and offers_data.signature_choice_key or M.choice_key(key)
end

--- Builds an offer's choice: its line for this difficulty, plus the gold, items and units it gives as cards. An offer the treasury cannot pay
--- shows its line with the not-enough-gold line under it, and no cards. Which way each offer was shown is kept on `pending.shown_affordable`.
--- @param offer table The offer record at the site's difficulty.
--- @param pending table The open site.
--- @param faction_name string The faction key.
--- @param choice_key string The choice key it sits on.
--- @returns table A choice record for `dilemmas.launch`.
local function build_choice(offer, pending, faction_name, choice_key)
    local line = offers_data.line_prefix .. offer.key .. "_" .. pending.difficulty
    pending.shown_affordable[offer.key] = M.affordable(offer, faction_name)
    if not pending.shown_affordable[offer.key] then return { key = choice_key, lines = { line, offers_data.unaffordable_line } } end
    --- An offer that may start a battle says so, as every battle spot choice that leads to a fight does.
    local choice = { key = choice_key, lines = gamble_has(offer, "guardian") and { line, offers_data.fight_line } or { line } }
    local cards = pending.cards[offer.key] or {}
    if offer.gold and not offer.gamble then choice.gold = offer.gold end
    if cards.gold then choice.gold = cards.gold end
    choice.items = cards.items
    local force = cards.units and tower_army.delving_force(pending.general_cqi)
    if force then choice.units = { force = force, keys = cards.units } end
    return choice
end

--- Shows a faction's open site dilemma: the signature offer on the first key, the other offers on their own keys, and Walk away last.
--- @param faction_name string The faction key.
function M.launch_site(faction_name)
    local pending = M.pending_by_faction[faction_name]
    pending.shown_affordable = {}
    local choices = {}
    for _, key in ipairs(pending.offers) do
        choices[#choices + 1] = build_choice(offers_data.at(key, pending.difficulty), pending, faction_name, site_choice_key(pending, key))
    end
    choices[#choices + 1] = { key = offers_data.walk_away_choice_key, lines = { offers_data.line_prefix .. "walk_away" } }
    dilemmas.launch(offers_data.dilemma_prefix .. pending.site, choices, faction_name)
end

--- Opens a treasure site for a human lord: rolls the site, or uses the one given, draws its offers and shows its dilemma.
--- @param character character The lord who entered the spot.
--- @param faction faction The lord's faction.
--- @param site table|nil The site record to open, e.g. the spoils pick, or nil to roll a treasure site.
--- @param event table|nil The won battle's event, for the spoils pick.
function M.open_site(character, faction, site, event)
    local faction_name = faction:name()
    site = site or pick_site()
    local ctx = {
        faction = faction,
        faction_name = faction_name,
        general_cqi = character:command_queue_index(),
        x = character:logical_position_x(),
        y = character:logical_position_y(),
        difficulty = event and event.difficulty or get_current_difficulty(),
        cards = {},
        targets = {},
        event = event,
    }
    local keys, signature = M.draw(site, ctx)
    local pending = { site = site.key, offers = keys, signature = signature, general_cqi = ctx.general_cqi, x = ctx.x, y = ctx.y,
        difficulty = ctx.difficulty, cards = {}, targets = {} }
    for _, key in ipairs(keys) do
        pending.cards[key] = ctx.cards[key]
        pending.targets[key] = ctx.targets[key]
    end
    M.pending_by_faction[faction_name] = pending
    log("spot: " .. faction_name .. " opens " .. site.key .. " with lord " .. ctx.general_cqi .. ", treasury " .. offer_effects.treasury(faction_name))
    M.launch_site(faction_name)
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Taking an offer

--- Applies the effects an offer's payload does not: bundles, traits, wounds, camps, heals, sacrifices, heroes, dividends, the Daemon's
--- deal armies and the old incident. A gamble outcome has no cards, so its gold and items are picked here for its result to grant. A wound
--- lands at once, and an offer's own wound (not a gamble's, whose result says so) shows its own result.
--- @param fields table The offer record or a gamble outcome, at the site's difficulty.
--- @param offer table The offer record, for the log.
--- @param state table { faction_name, general_cqi, x, y }.
--- @param rolled boolean True for a gamble outcome, whose `gold`, `items` and `unique` are picked here and granted by its result.
--- @returns table The outcome's rewards { gold, items } for its result, empty for an offer.
local function apply_fields(fields, offer, state, rolled)
    local faction_name, general_cqi = state.faction_name, state.general_cqi
    local general = tower_army.character(general_cqi)
    local rewards = { items = {} }
    if rolled then
        if fields.gold then rewards.gold = fields.gold end
        if fields.items then rewards.items = item_pool.pick_items(faction_name, fields.items.rarities, fields.items.count) end
        if fields.unique then rewards.items = offer_effects.pick_unique_items(faction_name, fields.unique) end
        log("spot: " .. offer.key .. " rolls gold " .. tostring(rewards.gold) .. ", items " .. table.concat(rewards.items, ", "))
    end
    if fields.army_bundle then tower_army.apply_bundle(general_cqi, fields.army_bundle[1], fields.army_bundle[2]) end
    if fields.faction_bundle then offer_effects.faction_bundle(faction_name, fields.faction_bundle[1], fields.faction_bundle[2]) end
    if fields.trait then tower_lords.add_trait(general_cqi, fields.trait, 1, true) end
    if fields.trait_points then tower_lords.add_trait(general_cqi, fields.trait_points, 1, true) end
    if fields.lord_ranks and general then
        cm:add_agent_experience(cm:char_lookup_str(general), fields.lord_ranks, true)
        log("spot: lord " .. general_cqi .. " gains " .. fields.lord_ranks .. " ranks")
    end
    if fields.lord_xp and general then
        cm:add_agent_experience(cm:char_lookup_str(general), fields.lord_xp)
        log("spot: lord " .. general_cqi .. " gains " .. fields.lord_xp .. " experience")
    end
    if fields.heal then tower_army.heal_army(general_cqi, 1) end
    if fields.sacrifice then
        offer_effects.remove_unit(general_cqi, tower_army.weakest_regular_unit(general_cqi))
        if fields.sacrifice.ranks > 0 then
            for _, entry in ipairs(tower_army.regular_units(general_cqi)) do cm:add_experience_to_unit(entry.unit, fields.sacrifice.ranks) end
        end
    end
    if fields.hero_rank then
        tower_lords.free_hero(general_cqi, faction_name, { offer_effects.culture_shorthand(faction_name) }, fields.hero_rank)
    end
    if fields.wound and general then
        cm:wound_character(cm:char_lookup_str(general), fields.wound)
        log("spot: lord " .. general_cqi .. " wounded for " .. fields.wound .. " turns")
        if not rolled then M.show_result(faction_name, "wound_paid_" .. fields.wound, { character = general }, { state.x, state.y }) end
    end
    if fields.camp and general then
        cm:disable_movement_for_character(cm:char_lookup_str(general))
        tower_army.apply_bundle(general_cqi, offers_data.camp_bundle)
        M.camps[#M.camps + 1] = { faction = faction_name, general_cqi = general_cqi }
        log("spot: lord " .. general_cqi .. " cannot move until the next turn")
    end
    if fields.dividends then
        local amount = fields.dividends.per_turn
        M.dividends[#M.dividends + 1] = { faction = faction_name, amount = amount, turns = fields.dividends.turns }
        cm:apply_effect_bundle(offers_data.dividends_bundle_prefix .. amount, faction_name, fields.dividends.turns)
        log("spot: " .. faction_name .. " gets " .. amount .. " gold for " .. fields.dividends.turns .. " turns")
    end
    if fields.daemon_armies then
        if M.send_daemon_army then M.send_daemon_army(faction_name, fields.daemon_armies) else log("spot: no Daemon's deal sender is set") end
    end
    if fields.incident and general then
        trigger_incident_for_character(fields.incident, incident_targets(fields.incident), general)
        log("spot: " .. offer.key .. " fires " .. fields.incident)
    end
    rewards.character = general
    return rewards
end

--- Rolls a gamble's outcome with `random_number`, weighted by each outcome's weight.
--- @param gamble table The offer's outcomes, each { weight, name, ...fields }.
--- @returns table The outcome.
local function roll_outcome(gamble)
    local entries = {}
    for i, outcome in ipairs(gamble) do entries[i] = { outcome, outcome[1] } end
    return pick_weighted(entries)
end

--- Rolls a gamble's outcome, shared with the battle offers. See `roll_outcome`.
M.roll_outcome = roll_outcome

--- Starts Wake the guardian's battle at the site against the lord.
--- @param state table { general_cqi, x, y } of the site taken.
local function wake_guardian(state)
    local general = tower_army.character(state.general_cqi)
    if M.start_guardian_battle and general then
        M.start_guardian_battle(general, state.x, state.y)
    else
        log("spot: no guardian battle could start for lord " .. tostring(state.general_cqi))
    end
end

--- Takes a choice from a faction's open site dilemma: pays the offer's cost, applies it, and shows where a realm offer landed or how a gamble
--- went. The payload already granted the offer's gold, item and unit cards. An offer the treasury cannot pay changes nothing and reopens the
--- site. Walk away and unknown choices only close the site.
--- @param faction_name string The faction that chose.
--- @param choice_key string The chosen choice key.
function M.take(faction_name, choice_key)
    local pending = M.pending_by_faction[faction_name]
    if pending == nil then
        log("spot: " .. faction_name .. " chose " .. tostring(choice_key) .. " with no site open")
        return
    end
    local offer = nil
    for _, key in ipairs(pending.offers) do
        if site_choice_key(pending, key) == choice_key then offer = offers_data.at(key, pending.difficulty) end
    end
    if offer == nil then
        M.pending_by_faction[faction_name] = nil
        log("spot: " .. faction_name .. " walks away from " .. pending.site)
        return
    end
    --- The button decides: one shown as unaffordable had no cards, so it buys nothing even if the treasury has grown since, and the reopened
    --- site shows the offer as it stands now.
    if pending.shown_affordable and pending.shown_affordable[offer.key] == false then
        log("spot: " .. offer.key .. " was shown as unaffordable (cost " .. M.offer_cost(offer) .. ", treasury now "
            .. offer_effects.treasury(faction_name) .. "), nothing is bought and the site reopens")
        M.launch_site(faction_name)
        return
    end
    M.pending_by_faction[faction_name] = nil
    local state = { faction_name = faction_name, general_cqi = pending.general_cqi, x = pending.x, y = pending.y }
    local before = offer_effects.treasury(faction_name)
    offer_effects.log_army_change(pending.general_cqi, offer.key)
    if offer.cost then cm:treasury_mod(faction_name, -M.offer_cost(offer)) end
    apply_fields(offer, offer, state, false)
    if offer.gamble then
        local outcome = roll_outcome(offer.gamble)
        log("spot: " .. offer.key .. " rolls " .. outcome[2])
        local rewards = apply_fields(outcome, offer, state, true)
        M.show_result(faction_name, offer.key .. "_" .. outcome[2], rewards, { pending.x, pending.y },
            rewards.items[1] and "ancillaries_onscreen_name_" .. rewards.items[1] or nil)
        --- The battle waits until the result is shown: a result incident fired while the battle was pending froze the game when hovered.
        if outcome.guardian then cm:callback(function() wake_guardian(state) end, 0.5) end
    end
    local target = pending.targets and pending.targets[offer.key]
    if target then
        realm_effects.apply(offer, target, faction_name)
        local position, region_key = realm_effects.target_position(target)
        --- The result names the target region, or the target faction when it holds none.
        local place = region_key and "regions_onscreen_" .. region_key or target.factions[1] and "factions_screen_name_" .. target.factions[1] or nil
        M.show_result(faction_name, offer.key, { character = tower_army.character(pending.general_cqi) }, position or { pending.x, pending.y }, place)
    end
    log("spot: " .. faction_name .. " took " .. offer.key .. " at " .. pending.site .. ", treasury " .. before .. " -> " .. offer_effects.treasury(faction_name)
        .. " (payload cards land after this)")
end

--- Greys out the offers on a faction's open site dilemma that the treasury could not pay when it was shown. UI only: one clicked anyway
--- reopens the site.
--- @param faction_name string The local faction key.
function M.grey_out_unaffordable(faction_name)
    local pending = M.pending_by_faction[faction_name]
    if pending == nil or pending.shown_affordable == nil then return end
    local keys = {}
    for _, key in ipairs(pending.offers) do
        if pending.shown_affordable[key] == false then
            keys[#keys + 1] = site_choice_key(pending, key)
        end
    end
    dilemmas.grey_out(offers_data.dilemma_prefix .. pending.site, keys)
end

--- True when a dilemma key is a treasure site's.
--- @param dilemma_key string The dilemma key.
--- @returns boolean True for a site dilemma.
function M.is_site_dilemma(dilemma_key)
    return dilemma_key:sub(1, #offers_data.dilemma_prefix) == offers_data.dilemma_prefix
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Turn start and saves

--- At a faction's turn start: frees camping lords and pays caravan investments.
--- @param faction_name string The faction whose turn starts.
function M.on_faction_turn_start(faction_name)
    for i = #M.camps, 1, -1 do
        local camp = M.camps[i]
        if camp.faction == faction_name then
            table.remove(M.camps, i)
            local general = tower_army.character(camp.general_cqi)
            if general then
                tower_army.remove_bundle(camp.general_cqi, offers_data.camp_bundle)
                cm:enable_movement_for_character(cm:char_lookup_str(general))
            end
        end
    end
    for i = #M.dividends, 1, -1 do
        local dividend = M.dividends[i]
        if dividend.faction == faction_name then
            cm:treasury_mod(faction_name, dividend.amount)
            dividend.turns = dividend.turns - 1
            log("spot: caravan pays " .. faction_name .. " " .. dividend.amount .. ", " .. dividend.turns .. " turns left")
            if dividend.turns <= 0 then table.remove(M.dividends, i) end
        end
    end
end

--- Exports the open site dilemmas, camps and dividends for the save file.
--- @returns table { pending_by_faction, camps, dividends }.
function M.export_state()
    return { pending_by_faction = M.pending_by_faction, camps = M.camps, dividends = M.dividends }
end

--- Restores the state saved by `M.export_state`, from the load callback. A save from before spot offers restores nothing. A camping lord is
--- frozen again on the first tick, once the game's characters can be looked up, since a frozen lord is not kept in the save.
--- @param saved table|nil The saved state.
function M.restore_state(saved)
    saved = saved or {}
    M.pending_by_faction = saved.pending_by_faction or {}
    M.camps = saved.camps or {}
    M.dividends = saved.dividends or {}
    if #M.camps == 0 then return end
    cm:add_first_tick_callback(function()
        for _, camp in ipairs(M.camps) do
            local general = tower_army.character(camp.general_cqi)
            if general then cm:disable_movement_for_character(cm:char_lookup_str(general)) end
        end
    end)
end

return M
