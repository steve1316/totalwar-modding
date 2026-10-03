--- Realm effects for spot offers: bundles on regions, provinces and factions (yours or another faction's), relations, development points,
--- garrison heals, settlement upgrades and shroud reveals. Targets are measured from a map position, usually the spot. Every call here was
--- checked in game on 2026-10-02 with the signature used below.

require("script/land_encounters/utils/common")

--- How many of the nearest factions a `rival_pair` target is picked from.
local RIVAL_POOL = 6

--- Main building level a province capital can reach.
local PROVINCE_CAPITAL_MAX_LEVEL = 5

--- Main building level a settlement that is not a province capital can reach.
local MINOR_SETTLEMENT_MAX_LEVEL = 3

local M = {}

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Targeting

--- Returns true for a faction that offers can target: alive, not rebels and not the given faction.
--- @param faction faction The faction to check.
--- @param self_name string The faction key to exclude.
--- @returns boolean True when the faction can be targeted.
local function is_other_living_faction(faction, self_name)
    return faction ~= nil and not faction:is_null_interface() and not faction:is_dead() and not faction:is_rebel() and faction:name() ~= self_name
end

--- Returns how many regions a faction owns.
--- @param faction faction The faction.
--- @returns number The region count.
local function region_count(faction)
    return faction:region_list():num_items()
end

--- Sorts factions by region count, most first, then by key so every client agrees. Each count is read once.
--- @param factions table A list of faction interfaces, sorted in place.
local function sort_by_size(factions)
    local counts = {}
    for _, faction in ipairs(factions) do counts[faction:name()] = region_count(faction) end
    table.sort(factions, function(a, b)
        local count_a, count_b = counts[a:name()], counts[b:name()]
        if count_a ~= count_b then return count_a > count_b end
        return a:name() < b:name()
    end)
end

--- Returns a settlement's main building level.
--- @param region region The region.
--- @returns number|nil The level, or nil when it cannot be read.
local function settlement_level(region)
    local ok, level = pcall(function() return region:settlement():primary_slot():building():building_level() end)
    return ok and level or nil
end

--- Walks every region that is not abandoned once, with its owner and its settlement's squared distance from a map position.
--- @param x number The map x position.
--- @param y number The map y position.
--- @param visit function Called with (region, owner, distance, index) for each region.
local function each_region(x, y, visit)
    local regions = cm:model():world():region_manager():region_list()
    for i = 0, regions:num_items() - 1 do
        local region = regions:item_at(i)
        if not region:is_abandoned() then
            local settlement = region:settlement()
            local dx, dy = settlement:logical_position_x() - x, settlement:logical_position_y() - y
            visit(region, region:owning_faction(), dx * dx + dy * dy, i)
        end
    end
end

--- Sorts { value, distance, index } entries nearest first, then by map order so every client agrees.
--- @param entries table The entries, sorted in place.
local function sort_nearest(entries)
    table.sort(entries, function(a, b)
        if a[2] ~= b[2] then return a[2] < b[2] end
        return a[3] < b[3]
    end)
end

--- Returns the regions whose settlements are nearest a map position, among regions that pass a filter, nearest first.
--- @param x number The map x position.
--- @param y number The map y position.
--- @param filter function Called with each region and its owner, returns true to keep it.
--- @param count number How many regions to return at most.
--- @returns table A list of region interfaces.
function M.nearest_regions(x, y, filter, count)
    local found = {}
    each_region(x, y, function(region, owner, distance, index)
        if filter(region, owner) then found[#found + 1] = { region, distance, index } end
    end)
    sort_nearest(found)
    local regions = {}
    for i = 1, math.min(count, #found) do regions[i] = found[i][1] end
    return regions
end

--- Returns the region whose settlement is nearest a map position, among regions that pass a filter.
--- @param x number The map x position.
--- @param y number The map y position.
--- @param filter function Called with each region and its owner, returns true to keep it.
--- @returns region The nearest region, or nil when none passes.
function M.nearest_region(x, y, filter)
    return M.nearest_regions(x, y, filter, 1)[1]
end

--- Builds a region filter for regions owned by a faction.
--- @param faction_name string The owning faction key.
--- @returns function The filter.
local function owned_by(faction_name)
    return function(_, owner) return owner:name() == faction_name end
end

--- Builds a region filter for regions owned by a faction at war with the given one.
--- @param faction faction The faction whose enemies are searched.
--- @returns function The filter.
local function owned_by_enemy_of(faction)
    local self_name = faction:name()
    return function(_, owner) return is_other_living_faction(owner, self_name) and faction:at_war_with(owner) end
end

--- Returns the owners of the nearest regions that pass a filter, nearest first, each faction once. Walks the map once.
--- @param faction faction The faction searching (never returned).
--- @param x number The map x position.
--- @param y number The map y position.
--- @param count number How many factions to return at most.
--- @param filter function|nil Called once with each candidate faction, returns true to keep it.
--- @returns table A list of faction interfaces.
function M.nearest_factions(faction, x, y, count, filter)
    local self_name = faction:name()
    local kept, nearest = {}, {}
    each_region(x, y, function(_, owner, distance, index)
        if owner:is_null_interface() then return end
        local name = owner:name()
        if kept[name] == nil then kept[name] = is_other_living_faction(owner, self_name) and (filter == nil or filter(owner)) end
        if not kept[name] then return end
        local entry = nearest[name]
        if entry == nil then
            nearest[name] = { owner, distance, index }
        elseif distance < entry[2] then
            entry[2], entry[3] = distance, index
        end
    end)
    local entries = {}
    for _, entry in pairs(nearest) do entries[#entries + 1] = entry end
    sort_nearest(entries)
    local found = {}
    for i = 1, math.min(count, #entries) do found[i] = entries[i][1] end
    return found
end

--- Wraps one region and its owner as a target.
--- @param region region The region, or nil.
--- @param with_owner boolean True to list the region's owner as a target faction too.
--- @returns table|nil { regions, factions }, or nil without a region.
local function region_target(region, with_owner)
    if region == nil then return nil end
    return { regions = { region:name() }, factions = with_owner and { region:owning_faction():name() } or {} }
end

--- Finders by target kind. Each returns { regions = { region keys }, factions = { faction keys } }, or nil when there is no target.
local FINDERS = {
    own_region = function(faction, x, y) return region_target(M.nearest_region(x, y, owned_by(faction:name()))) end,
    raise_region = function(faction, x, y)
        local self_name = faction:name()
        return region_target(M.nearest_region(x, y, function(candidate, owner)
            if owner:name() ~= self_name then return false end
            local level = settlement_level(candidate)
            return level ~= nil and level < (candidate:is_province_capital() and PROVINCE_CAPITAL_MAX_LEVEL or MINOR_SETTLEMENT_MAX_LEVEL)
        end))
    end,
    enemy_region = function(faction, x, y) return region_target(M.nearest_region(x, y, owned_by_enemy_of(faction)), true) end,
    enemy_regions = function(faction, x, y, count)
        local target = { regions = {}, factions = {} }
        for _, region in ipairs(M.nearest_regions(x, y, owned_by_enemy_of(faction), count or 1)) do table.insert(target.regions, region:name()) end
        return #target.regions > 0 and target or nil
    end,
    enemy_capital = function(faction, x, y)
        local enemy = M.nearest_factions(faction, x, y, 1, function(other) return faction:at_war_with(other) and other:has_home_region() end)[1]
        return enemy and { regions = { enemy:home_region():name() }, factions = { enemy:name() } } or nil
    end,
    friend = function(faction, x, y)
        local friend = M.nearest_factions(faction, x, y, 1, function(other) return not faction:at_war_with(other) end)[1]
        return friend and { regions = {}, factions = { friend:name() } } or nil
    end,
    biggest_faction = function(faction)
        local self_name, best, best_count = faction:name(), nil, 0
        local factions = cm:model():world():faction_list()
        for i = 0, factions:num_items() - 1 do
            local other = factions:item_at(i)
            if is_other_living_faction(other, self_name) then
                local count = region_count(other)
                if count > best_count or (count == best_count and best and other:name() < best:name()) then best, best_count = other, count end
            end
        end
        return best and { regions = {}, factions = { best:name() } } or nil
    end,
    neighbours = function(faction)
        local seen, names = {}, {}
        local regions = faction:region_list()
        for i = 0, regions:num_items() - 1 do
            local adjacent = regions:item_at(i):adjacent_region_list()
            for j = 0, adjacent:num_items() - 1 do
                local owner = adjacent:item_at(j):owning_faction()
                if is_other_living_faction(owner, faction:name()) and not faction:at_war_with(owner) and not seen[owner:name()] then
                    seen[owner:name()] = true
                    table.insert(names, owner:name())
                end
            end
        end
        table.sort(names)
        return #names > 0 and { regions = {}, factions = names } or nil
    end,
    rival_pair = function(faction, x, y)
        local pool = M.nearest_factions(faction, x, y, RIVAL_POOL)
        if #pool < 2 then return nil end
        sort_by_size(pool)
        return { regions = {}, factions = { pool[1]:name(), pool[2]:name() } }
    end,
    enemy_friends = function(faction, x, y)
        local enemy = M.nearest_factions(faction, x, y, 1, function(other) return faction:at_war_with(other) end)[1]
        if enemy == nil then return nil end
        local names = { enemy:name() }
        local enemies = faction:factions_at_war_with()
        for i = 0, enemies:num_items() - 1 do
            local other = enemies:item_at(i)
            if is_other_living_faction(other, faction:name()) and other:name() ~= enemy:name() then table.insert(names, other:name()) end
        end
        return #names > 1 and { regions = {}, factions = names } or nil
    end,
}

--- Province kinds find the same region as their region kinds. The offer's province bundle is what reaches the whole province.
FINDERS.own_province = FINDERS.own_region
FINDERS.enemy_province = FINDERS.enemy_region

--- Finds a realm offer's target from a map position.
--- @param kind string The target kind, one of `configs/spot_offers.lua` `realm_kinds`.
--- @param faction faction The faction taking the offer.
--- @param x number The map x position.
--- @param y number The map y position.
--- @param count number|nil How many targets, for kinds that take several.
--- @returns table|nil { regions = { region keys }, factions = { faction keys } }, or nil when there is no target.
function M.find_target(kind, faction, x, y, count)
    local finder = FINDERS[kind]
    if finder == nil then
        log("realm: unknown target kind " .. tostring(kind))
        return nil
    end
    return finder(faction, x, y, count)
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Effects

--- Changes relations between two factions.
--- @param a string The first faction key.
--- @param b string The second faction key.
--- @param amount number The bonus, e.g. 3 or -3.
local function change_relations(a, b, amount)
    cm:apply_dilemma_diplomatic_bonus(a, b, amount)
    log("realm: relations " .. a .. " / " .. b .. " " .. (amount > 0 and "+" or "") .. amount)
end

--- Applies the parts of a realm offer that act on one target region.
--- @param offer table The offer record from `configs/spot_offers.lua`.
--- @param region region The target region.
--- @param faction_name string The faction that took the offer.
local function apply_to_region(offer, region, faction_name)
    local region_key, owner = region:name(), region:owning_faction():name()
    if offer.region_bundle then
        cm:apply_effect_bundle_to_region(offer.region_bundle[1], region_key, offer.region_bundle[2])
        log("realm: " .. offer.region_bundle[1] .. " on region " .. region_key .. " (" .. owner .. ") for " .. offer.region_bundle[2] .. " turns")
    end
    if offer.province_bundle then
        cm:apply_effect_bundle_to_faction_province(offer.province_bundle[1], region, offer.province_bundle[2])
        log("realm: " .. offer.province_bundle[1] .. " on province " .. region:province_name() .. " (" .. owner .. ") for " .. offer.province_bundle[2] .. " turns")
    end
    if offer.points then
        cm:add_development_points_to_region(region_key, offer.points)
        log("realm: +" .. offer.points .. " development points in " .. region_key)
    end
    if offer.heal_garrison then
        cm:heal_garrison(region:cqi())
        log("realm: garrison of " .. region_key .. " healed")
    end
    if offer.realm == "raise_region" then
        local level = settlement_level(region)
        if level then
            cm:instantly_set_settlement_primary_slot_level(region:settlement(), level + 1)
            log("realm: " .. region_key .. " main building " .. level .. " -> " .. tostring(settlement_level(region)))
        end
    end
    if offer.realm == "enemy_capital" then
        cm:make_region_visible_in_shroud(faction_name, region_key)
        log("realm: shroud lifted over " .. region_key .. " for " .. faction_name)
    end
end

--- Applies a realm offer to its target: region and province bundles on the target regions, a bundle on the target factions, relations,
--- development points, a garrison heal, a settlement upgrade and a shroud reveal, as the offer's fields ask.
--- @param offer table The offer record from `configs/spot_offers.lua`.
--- @param target table The target from `M.find_target`.
--- @param faction_name string The faction that took the offer.
function M.apply(offer, target, faction_name)
    for _, region_key in ipairs(target.regions) do
        local region = cm:get_region(region_key)
        if region and not region:is_null_interface() then apply_to_region(offer, region, faction_name) end
    end
    if offer.target_faction_bundle then
        for _, other in ipairs(target.factions) do
            cm:apply_effect_bundle(offer.target_faction_bundle[1], other, offer.target_faction_bundle[2])
            log("realm: " .. offer.target_faction_bundle[1] .. " on faction " .. other .. " for " .. offer.target_faction_bundle[2] .. " turns")
        end
    end
    if offer.relations then
        if offer.realm == "rival_pair" then
            change_relations(target.factions[1], target.factions[2], offer.relations)
        elseif offer.realm == "enemy_friends" then
            for i = 2, #target.factions do change_relations(target.factions[1], target.factions[i], offer.relations) end
        else
            for _, other in ipairs(target.factions) do change_relations(faction_name, other, offer.relations) end
        end
    end
end

--- Returns where a realm offer's message points: the first target region's settlement, or else the first target faction's capital.
--- @param target table The target from `M.find_target`.
--- @returns table|nil The { x, y } position, or nil when the target has neither.
--- @returns string|nil The region key at that position.
function M.target_position(target)
    local region = target.regions[1] and cm:get_region(target.regions[1]) or nil
    if region == nil and target.factions[1] then
        local faction = cm:get_faction(target.factions[1])
        region = faction and faction:has_home_region() and faction:home_region() or nil
    end
    if region == nil or region:is_null_interface() then return nil, nil end
    local settlement = region:settlement()
    return { settlement:logical_position_x(), settlement:logical_position_y() }, region:name()
end

return M
