--- Offer effects shared by tower offers and spot offers: checks and changes on a lord's army (damage, room, recruits, ranks, unit removal)
--- and on a faction (bundles, treasury, unique items). Each takes the lord's command queue index or the faction key, never a delve.

require("script/land_encounters/utils/random")

local tower_army = require("script/land_encounters/features/tower_army")
local dilemmas = require("script/land_encounters/core/dilemmas")
local tower_lords = require("script/land_encounters/features/tower_lords")
local item_pool = require("script/land_encounters/core/item_pool")
local army_generator = require("script/land_encounters/core/army_generator")
local Army = require("script/land_encounters/core/army")

local M = {}

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Army checks

--- True when a lord's army has lost any strength.
--- @param general_cqi number The lord's command queue index.
--- @returns boolean True when the army is below full strength.
function M.army_damaged(general_cqi)
    local strength = tower_army.army_strength(general_cqi)
    return strength ~= nil and strength < 100
end

--- True when a lord's army has room for `count` more units.
--- @param general_cqi number The lord's command queue index.
--- @param count number The units an offer adds.
--- @returns boolean True with at least `count` free slots.
function M.has_room(general_cqi, count)
    local force = tower_army.delving_force(general_cqi)
    return force ~= nil and tower_army.free_slots(force) >= count
end

--- True when a lord's army has missile units or artillery.
--- @param general_cqi number The lord's command queue index.
--- @returns boolean True when a regular unit shoots.
function M.army_shoots(general_cqi)
    for _, entry in ipairs(tower_army.regular_units(general_cqi)) do
        local class = entry.unit:unit_class()
        if class:find("_mis$") or class:find("^art") then return true end
    end
    return false
end

--- True when an offer fits the army it would affect: `shoots` and `caster` need our army to have a shooter or a spellcaster, `roster` needs
--- the enemy faction to field one of those unit types (a strip offer's `strip_types` stand in for it), and `max_units` needs our army at
--- or under that many regular units.
--- @param offer table The offer record.
--- @param enemy_faction string|nil The enemy faction's shorthand, when known.
--- @param general_cqi number Our lord's command queue index.
--- @returns boolean True when every condition the offer sets holds.
function M.army_fits(offer, enemy_faction, general_cqi)
    if offer.shoots and not M.army_shoots(general_cqi) then return false end
    if offer.caster and not M.army_has_caster(general_cqi) then return false end
    local roster = offer.roster or offer.strip_types
    if roster and not army_generator.can_field(enemy_faction, roster) then return false end
    if offer.max_units and #tower_army.regular_units(general_cqi) > offer.max_units then return false end
    return true
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Unit picks

--- Finds the faction shorthand of a faction's culture.
--- @param faction_name string The faction key.
--- @returns string|nil The shorthand, or nil when its culture has no army data.
function M.culture_shorthand(faction_name)
    local faction = cm:get_faction(faction_name)
    return faction and Army.faction_shorthand_for_subculture(faction:subculture()) or nil
end

--- Picks a recruit offer's units: `offer.count` units of `offer.tiers` and `offer.unit_types` from a faction's army data, when the army has
--- room for them.
--- @param general_cqi number The lord's command queue index.
--- @param shorthand string|nil The faction shorthand to recruit from.
--- @param offer table The offer record: `count`, `tiers` and `unit_types`.
--- @param exclude table|nil Unit key -> true set to leave out, e.g. the units other offers on the same dilemma already show.
--- @returns table The picked unit keys, empty without room or a shorthand.
function M.pick_recruits(general_cqi, shorthand, offer, exclude)
    if not M.has_room(general_cqi, offer.count) or not shorthand then return {} end
    return army_generator.pick_units(shorthand, offer.tiers, offer.unit_types, offer.count, { exclude = exclude })
end

--- Picks Regiments of Renown of a faction's culture that the army does not field, when the army has room for them.
--- @param general_cqi number The lord's command queue index.
--- @param faction_name string The lord's faction key.
--- @param count number How many to pick.
--- @param exclude table|nil Unit key -> true set to leave out as well, e.g. the units other offers on the same dilemma already show.
--- @returns table The picked unit keys, empty without room.
function M.pick_renown(general_cqi, faction_name, count, exclude)
    if not M.has_room(general_cqi, count) then return {} end
    local shorthand = M.culture_shorthand(faction_name)
    local fielded = {}
    for key in pairs(exclude or {}) do fielded[key] = true end
    for _, entry in ipairs(tower_army.unit_strengths(general_cqi)) do fielded[entry.unit:unit_key()] = true end
    return shorthand and army_generator.pick_units(shorthand, { 0, 1, 2, 3, 4, 5 }, nil, count, { renown = true, exclude = fielded }) or {}
end

--- Picks distinct legendary items for a faction.
--- @param faction_name string The faction key.
--- @param count number How many items to pick.
--- @param held table|nil Item keys the reward already holds (e.g. a tower haul), which are not picked again.
--- @returns table The picked item keys, fewer than `count` when the pool runs dry.
function M.pick_unique_items(faction_name, count, held)
    local items = {}
    for _ = 1, count do
        local item = item_pool.pick_legendary_item(faction_name, held, items)
        if item == nil then break end
        items[#items + 1] = item
    end
    return items
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Army changes

--- Logs a lord's army now and again half a second later, once the game has applied an offer's changes, so they can be checked.
--- @param general_cqi number The lord's command queue index.
--- @param offer_key string The offer's key for the log.
function M.log_army_change(general_cqi, offer_key)
    tower_army.log_army(general_cqi, "before " .. offer_key)
    cm:callback(function() tower_army.log_army(general_cqi, "after " .. offer_key) end, tower_army.AFTER_PAYLOAD_SECONDS)
end

--- Removes one unit from a lord's army. The game only removes by unit key, taking a copy of its own choosing, so when the army has other
--- copies the ones left are given the strengths they had beside this unit, strongest to strongest. The result matches removing this one.
--- @param general_cqi number The lord's command queue index.
--- @param entry table The unit's `tower_army.unit_strengths` entry.
function M.remove_unit(general_cqi, entry)
    local key = entry.unit:unit_key()
    local kept = {}
    for _, other in ipairs(tower_army.regular_units(general_cqi)) do
        if other.index ~= entry.index and other.unit:unit_key() == key then kept[#kept + 1] = other.strength end
    end
    local lookup = cm:char_lookup_str(cm:get_character_by_cqi(general_cqi))
    log("offer: removing unit " .. key .. " at " .. entry.index .. " (" .. math.floor(entry.strength + 0.5) .. "%) from " .. lookup)
    cm:remove_unit_from_character(lookup, key)
    if #kept == 0 then return end
    local copies = {}
    for _, other in ipairs(tower_army.regular_units(general_cqi)) do
        if other.unit:unit_key() == key then copies[#copies + 1] = other end
    end
    table.sort(kept, function(a, b) return a > b end)
    table.sort(copies, function(a, b) return a.strength > b.strength end)
    for i, copy in ipairs(copies) do
        if kept[i] then tower_army.set_strength(copy.unit, kept[i]) end
    end
end

--- True when an army has a spellcaster: its lord or one of the heroes in it.
--- @param general_cqi number The army's lord's command queue index.
--- @returns boolean True when one of its characters is a caster.
function M.army_has_caster(general_cqi)
    local force = tower_army.delving_force(general_cqi)
    if not force then return false end
    local characters = force:character_list()
    for i = 0, characters:num_items() - 1 do
        if characters:item_at(i):is_caster() then return true end
    end
    return false
end

--- Gives a lord experience points.
--- @param general_cqi number The lord's command queue index.
--- @param xp number The experience.
function M.add_lord_xp(general_cqi, xp)
    local general = tower_army.character(general_cqi)
    if not general then
        log("offer: no lord " .. tostring(general_cqi) .. " to give " .. xp .. " experience")
        return
    end
    cm:add_agent_experience(cm:char_lookup_str(general), xp)
    log("offer: lord " .. general_cqi .. " gains " .. xp .. " experience")
end

--- Gives `offer.ranks` ranks to `offer.count` random units that can take them, every such unit when `count` is `math.huge`.
--- @param general_cqi number The lord's command queue index.
--- @param offer table The offer record: `count`, `ranks` and `max_rank`.
function M.add_ranks(general_cqi, offer)
    local pool = tower_army.rankable_units(general_cqi, offer.ranks, offer.max_rank)
    for _ = 1, math.min(offer.count, #pool) do
        local entry = table.remove(pool, random_number(#pool))
        log("offer: +" .. offer.ranks .. " ranks to " .. entry.unit:unit_key() .. " at " .. entry.index)
        cm:add_experience_to_unit(entry.unit, offer.ranks)
    end
end

--- Removes the weakest regular unit and heals every other unit by `heal_share` of its missing strength.
--- @param general_cqi number The lord's command queue index.
--- @param heal_share number The share of missing strength healed, e.g. 0.5.
function M.blood_price(general_cqi, heal_share)
    local weakest = tower_army.weakest_regular_unit(general_cqi)
    for _, entry in ipairs(tower_army.unit_strengths(general_cqi)) do
        if entry.index ~= weakest.index then tower_army.set_strength(entry.unit, entry.strength + heal_share * (100 - entry.strength)) end
    end
    M.remove_unit(general_cqi, weakest)
end

--- Gives a lord a dark bargain: its trait and its army bundle.
--- @param general_cqi number The lord's command queue index.
--- @param offer table The offer record: `trait` and `effect_bundle`.
function M.dark_bargain(general_cqi, offer)
    tower_lords.add_trait(general_cqi, offer.trait, 1, true)
    tower_army.apply_bundle(general_cqi, offer.effect_bundle)
end

--- Folds one offer's sabotage into what the enemy army is built and weakened with: `no_heroes`, `fewer_units` (added up), `max_tier` (the
--- lowest), `min_tier` (the highest), `enemy_strength` and `champion_strength` (the lowest), `enemy_bundles` (each `enemy_bundle`) and
--- `strip_types` (each offer's `strip_types`, as one set).
--- @param into table The battle event or sabotage options to fold into.
--- @param offer table The offer record or gamble outcome.
function M.merge_sabotage(into, offer)
    if offer.no_heroes then into.no_heroes = true end
    if offer.fewer_units then into.fewer_units = (into.fewer_units or 0) + offer.fewer_units end
    if offer.max_tier then into.max_tier = math.min(into.max_tier or offer.max_tier, offer.max_tier) end
    if offer.min_tier then into.min_tier = math.max(into.min_tier or offer.min_tier, offer.min_tier) end
    if offer.enemy_strength then into.enemy_strength = math.min(into.enemy_strength or 1, offer.enemy_strength) end
    if offer.champion_strength then into.champion_strength = math.min(into.champion_strength or 1, offer.champion_strength) end
    if offer.enemy_bundle then
        into.enemy_bundles = into.enemy_bundles or {}
        into.enemy_bundles[#into.enemy_bundles + 1] = offer.enemy_bundle
    end
    if offer.strip_types then
        into.strip_types = into.strip_types or {}
        for _, unit_type in ipairs(offer.strip_types) do into.strip_types[unit_type] = true end
    end
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Faction changes

--- Puts a bundle on a faction.
--- @param faction_name string The faction key.
--- @param bundle string The effect bundle key.
--- @param turns number How many turns it lasts.
function M.faction_bundle(faction_name, bundle, turns)
    cm:apply_effect_bundle(bundle, faction_name, turns)
    log("offer: " .. bundle .. " on faction " .. faction_name .. " for " .. turns .. " turns")
end

--- Reads a faction's treasury.
--- @param faction_name string The faction key.
--- @returns number The treasury gold, or 0 when the faction is missing.
function M.treasury(faction_name)
    return dilemmas.treasury(faction_name)
end

return M
