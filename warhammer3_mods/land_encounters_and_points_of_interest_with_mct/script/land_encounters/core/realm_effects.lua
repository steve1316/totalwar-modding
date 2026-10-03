--- Realm effects for spot offers: bundles on regions, provinces and factions (yours or another faction's), relations, development points,
--- garrison heals, settlement upgrades and shroud reveals. Targets are measured from a map position, usually the spot.
--- `run_test` is the in-game realm test: it tries each CA call's likely signatures and logs which one changed the game.

require("script/land_encounters/utils/common")

--- Turns every test bundle lasts.
local TEST_TURNS = 5

--- Test bundle keys from the database. The templates are empty records that custom bundles are built on.
local TEST_BUNDLES = {
    template_region = "land_enc_effect_test_template_region",
    template_province = "land_enc_effect_test_template_province",
    template_faction = "land_enc_effect_test_template_faction",
    region = "land_enc_effect_test_region",
    province = "land_enc_effect_test_province",
}

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

--- Returns the region whose settlement is nearest a map position, among regions that pass a filter.
--- @param x number The map x position.
--- @param y number The map y position.
--- @param filter function Called with each owned region, returns true to keep it.
--- @param skip table|nil Region keys -> true to leave out.
--- @returns region The nearest region, or nil when none passes.
function M.nearest_region(x, y, filter, skip)
    local regions = cm:model():world():region_manager():region_list()
    local best, best_distance = nil, nil
    for i = 0, regions:num_items() - 1 do
        local region = regions:item_at(i)
        if not region:is_abandoned() and not (skip and skip[region:name()]) and filter(region) then
            local settlement = region:settlement()
            local dx, dy = settlement:logical_position_x() - x, settlement:logical_position_y() - y
            local distance = dx * dx + dy * dy
            if best_distance == nil or distance < best_distance then
                best, best_distance = region, distance
            end
        end
    end
    return best
end

--- Returns the nearest region owned by a faction.
--- @param faction_name string The owning faction key.
--- @param x number The map x position.
--- @param y number The map y position.
--- @param skip table|nil Region keys -> true to leave out.
--- @returns region The region, or nil when the faction owns none.
function M.nearest_own_region(faction_name, x, y, skip)
    return M.nearest_region(x, y, function(region) return region:owning_faction():name() == faction_name end, skip)
end

--- Returns the nearest region owned by a faction at war with the given one.
--- @param faction faction The faction whose enemies are searched.
--- @param x number The map x position.
--- @param y number The map y position.
--- @returns region The region, or nil when no enemy owns one.
function M.nearest_enemy_region(faction, x, y)
    return M.nearest_region(x, y, function(region)
        local owner = region:owning_faction()
        return is_other_living_faction(owner, faction:name()) and faction:at_war_with(owner)
    end)
end

--- Returns the owners of the nearest regions that pass a filter, nearest first, each faction once.
--- @param faction faction The faction searching (never returned).
--- @param x number The map x position.
--- @param y number The map y position.
--- @param count number How many factions to return at most.
--- @param filter function|nil Called with each candidate faction, returns true to keep it.
--- @returns table A list of faction interfaces.
function M.nearest_factions(faction, x, y, count, filter)
    local found, seen = {}, {}
    while #found < count do
        local region = M.nearest_region(x, y, function(candidate)
            local owner = candidate:owning_faction()
            return is_other_living_faction(owner, faction:name()) and not seen[owner:name()] and (filter == nil or filter(owner))
        end)
        if region == nil then break end
        local owner = region:owning_faction()
        seen[owner:name()] = true
        table.insert(found, owner)
    end
    return found
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Realm test

--- Returns a readable state string from a check function, or the error it raised.
--- @param check function Returns the state to log.
--- @returns string The state, or "error: ..." when the check failed.
local function read_state(check)
    local ok, state = pcall(check)
    return ok and tostring(state) or ("error: " .. tostring(state))
end

--- Tries each variant of a CA call until the state read by `check` changes, logging every attempt. Without a check, the first variant that
--- runs without an error is kept, and the result has to be looked at in game.
--- @param label string What the step tests, for the log.
--- @param check function|nil Returns the state that the call should change.
--- @param variants table A list of { name, function } pairs, tried in order.
local function try_variants(label, check, variants)
    local before = check and read_state(check) or "-"
    for _, variant in ipairs(variants) do
        local ok, err = pcall(variant[2])
        local after = check and read_state(check) or "-"
        log("realm test " .. label .. " | " .. variant[1] .. " | ok=" .. tostring(ok) .. (ok and "" or " err=" .. tostring(err)) .. " | before=" .. before .. " after=" .. after)
        if ok and check == nil then
            log("realm test " .. label .. " | RAN with " .. variant[1] .. " (check in game)")
            return
        end
        if ok and after ~= before then
            log("realm test " .. label .. " | WORKS with " .. variant[1])
            return
        end
    end
    log("realm test " .. label .. " | NO VARIANT CHANGED THE STATE (check in game)")
end

--- Builds a custom bundle on a database template, or returns nil and logs why it failed.
--- @param template string The template bundle key.
--- @param effects table A list of { effect_key, scope, value }.
--- @returns userdata The custom bundle, or nil.
local function build_custom_bundle(template, effects)
    local ok, bundle = pcall(function()
        local custom = cm:create_new_custom_effect_bundle(template)
        for _, effect in ipairs(effects) do
            custom:add_effect(effect[1], effect[2], effect[3])
        end
        custom:set_duration(TEST_TURNS)
        return custom
    end)
    if not ok or bundle == nil then
        log("realm test custom bundle " .. template .. " | build FAILED: " .. tostring(bundle))
        return nil
    end
    return bundle
end

--- Logs a region and its owner, or that there is none.
--- @param label string What the region is for.
--- @param region region The region, or nil.
local function log_target(label, region)
    if region == nil then
        log("realm test target " .. label .. ": none found")
    else
        log("realm test target " .. label .. ": " .. region:name() .. " (" .. region:province_name() .. "), owner " .. region:owning_faction():name())
    end
end

--- Region and province bundles, plain and custom, on your nearest region and the nearest enemy region.
--- @param faction faction The faction running the test.
--- @param own region Your nearest region, or nil.
--- @param enemy region The nearest enemy region, or nil.
local function test_bundles(faction, own, enemy)
    local targets = { { "own", own, 1 }, { "enemy", enemy, -1 } }
    for _, target in ipairs(targets) do
        local side, region, sign = target[1], target[2], target[3]
        if region ~= nil then
            local region_key, owner_key = region:name(), region:owning_faction():name()
            local province_key = region:province_name()

            try_variants("region bundle (" .. side .. ")", function() return region:has_effect_bundle(TEST_BUNDLES.region) end, {
                { "apply_effect_bundle_to_region(key, region_key, turns)", function() cm:apply_effect_bundle_to_region(TEST_BUNDLES.region, region_key, TEST_TURNS) end },
            })

            try_variants("province bundle (" .. side .. ")", function() return region:faction_province_has_effect_bundle(TEST_BUNDLES.province) end, {
                { "apply_effect_bundle_to_faction_province(key, region, turns)", function() cm:apply_effect_bundle_to_faction_province(TEST_BUNDLES.province, region, TEST_TURNS) end },
                { "apply_effect_bundle_to_faction_province(key, region_key, turns)", function() cm:apply_effect_bundle_to_faction_province(TEST_BUNDLES.province, region_key, TEST_TURNS) end },
                { "apply_effect_bundle_to_faction_province(key, faction_key, province_key, turns)", function() cm:apply_effect_bundle_to_faction_province(TEST_BUNDLES.province, owner_key, province_key, TEST_TURNS) end },
            })

            local custom_region = build_custom_bundle(TEST_BUNDLES.template_region, {
                { "wh_main_effect_economy_gdp_mod_all", "region_to_region_own", 10 * sign },
                { "wh_main_effect_public_order_events", "region_to_province_own", 5 * sign },
                { "wh_main_effect_force_army_campaign_siege_defend_attrition", "region_to_force_own", -50 * sign },
            })
            if custom_region ~= nil then
                try_variants("custom region bundle (" .. side .. ")", function() return region:has_effect_bundle(TEST_BUNDLES.template_region) end, {
                    { "apply_custom_effect_bundle_to_region(bundle, region)", function() cm:apply_custom_effect_bundle_to_region(custom_region, region) end },
                    { "apply_custom_effect_bundle_to_region(bundle, region_key)", function() cm:apply_custom_effect_bundle_to_region(custom_region, region_key) end },
                })
            end

            local custom_province = build_custom_bundle(TEST_BUNDLES.template_province, {
                { "wh_main_effect_public_order_events", "province_to_province_own", 10 * sign },
                { "wh_main_effect_province_growth_events", "province_to_province_own", 30 * sign },
            })
            if custom_province ~= nil then
                try_variants("custom province bundle (" .. side .. ")", function() return region:faction_province_has_effect_bundle(TEST_BUNDLES.template_province) end, {
                    { "apply_custom_effect_bundle_to_faction_province(bundle, region)", function() cm:apply_custom_effect_bundle_to_faction_province(custom_province, region) end },
                    { "apply_custom_effect_bundle_to_faction_province(bundle, faction_province)", function() cm:apply_custom_effect_bundle_to_faction_province(custom_province, region:faction_province()) end },
                    { "apply_custom_effect_bundle_to_faction_province(bundle, faction_key, province_key)", function() cm:apply_custom_effect_bundle_to_faction_province(custom_province, owner_key, province_key) end },
                })
            end
        end
    end

    if enemy ~= nil then
        local other = enemy:owning_faction()
        local custom_faction = build_custom_bundle(TEST_BUNDLES.template_faction, {
            { "wh_main_effect_technology_research_rate_mod", "faction_to_faction_own", -10 },
        })
        if custom_faction ~= nil then
            try_variants("custom faction bundle (" .. other:name() .. ")", function() return other:has_effect_bundle(TEST_BUNDLES.template_faction) end, {
                { "apply_custom_effect_bundle_to_faction(bundle, faction)", function() cm:apply_custom_effect_bundle_to_faction(custom_faction, other) end },
                { "apply_custom_effect_bundle_to_faction(bundle, faction_key)", function() cm:apply_custom_effect_bundle_to_faction(custom_faction, other:name()) end },
            })
        end
    end
end

--- Relations: you and the nearest faction at peace with you, then the two nearest other factions with each other.
--- @param faction faction The faction running the test.
--- @param x number The map x position.
--- @param y number The map y position.
local function test_relations(faction, x, y)
    local self_name = faction:name()
    local friend = M.nearest_factions(faction, x, y, 1, function(other) return not faction:at_war_with(other) end)[1]
    if friend == nil then
        log("realm test relations (you): no faction at peace with you")
    else
        local friend_name = friend:name()
        local check = function()
            return "standing " .. faction:diplomatic_standing_with(friend_name) .. ", their attitude " .. friend:diplomatic_attitude_towards(self_name)
        end
        try_variants("relations (you + " .. friend_name .. ")", check, {
            { "apply_dilemma_diplomatic_bonus(self, other, 3)", function() cm:apply_dilemma_diplomatic_bonus(self_name, friend_name, 3) end },
            { "apply_dilemma_diplomatic_bonus(other, self, 3)", function() cm:apply_dilemma_diplomatic_bonus(friend_name, self_name, 3) end },
        })
    end

    local pair = M.nearest_factions(faction, x, y, 2)
    if #pair < 2 then
        log("realm test relations (others): fewer than 2 other factions found")
        return
    end
    local a, b = pair[1], pair[2]
    local check = function()
        return "standing " .. a:diplomatic_standing_with(b:name()) .. ", attitude " .. b:diplomatic_attitude_towards(a:name())
    end
    try_variants("relations (" .. a:name() .. " + " .. b:name() .. ")", check, {
        { "apply_dilemma_diplomatic_bonus(a, b, -3)", function() cm:apply_dilemma_diplomatic_bonus(a:name(), b:name(), -3) end },
    })
end

--- Development points, garrison heal and settlement upgrade on your regions, and a shroud reveal on the nearest enemy capital.
--- @param faction faction The faction running the test.
--- @param own region Your nearest region, or nil.
--- @param second region Your second-nearest region, or nil.
--- @param x number The map x position.
--- @param y number The map y position.
local function test_settlements(faction, own, second, x, y)
    if own ~= nil then
        local region_key = own:name()
        try_variants("development points (" .. region_key .. ")", function() return own:has_development_points_to_upgrade() end, {
            { "add_development_points_to_region(region_key, 50)", function() cm:add_development_points_to_region(region_key, 50) end },
        })

        try_variants("heal garrison (" .. region_key .. ")", nil, {
            { "heal_garrison(region_cqi)", function() cm:heal_garrison(own:cqi()) end },
        })
    end

    local target = second or own
    if target ~= nil then
        local settlement = target:settlement()
        local level = function() return settlement:primary_slot():building():building_level() end
        local next_level = (tonumber(read_state(level)) or 0) + 1
        try_variants("settlement upgrade (" .. target:name() .. " to " .. next_level .. ")", level, {
            { "instantly_set_settlement_primary_slot_level(settlement, level)", function() cm:instantly_set_settlement_primary_slot_level(settlement, next_level) end },
            { "instantly_set_settlement_primary_slot_level(region, level)", function() cm:instantly_set_settlement_primary_slot_level(target, next_level) end },
            { "instantly_set_settlement_primary_slot_level(region_key, level)", function() cm:instantly_set_settlement_primary_slot_level(target:name(), next_level) end },
        })
    end

    local enemy = M.nearest_factions(faction, x, y, 1, function(other) return faction:at_war_with(other) and other:has_home_region() end)[1]
    if enemy == nil then
        log("realm test shroud: no enemy with a capital")
        return
    end
    local capital = enemy:home_region():name()
    try_variants("shroud (" .. capital .. ")", nil, {
        { "make_region_visible_in_shroud(faction_key, region_key)", function() cm:make_region_visible_in_shroud(faction:name(), capital) end },
    })
end

--- Runs every realm call LEAPOI has not used yet, measured from a map position, and logs which signature worked. Bundles last
--- `TEST_TURNS` turns. Some results (garrison heal, shroud, relations text) only show in game, so the log names what to look at.
--- @param faction faction The human faction that entered the spot.
--- @param x number The map x position of the spot.
--- @param y number The map y position of the spot.
function M.run_test(faction, x, y)
    log("realm test START for " .. faction:name() .. " at (" .. x .. ", " .. y .. ")")
    local own = M.nearest_own_region(faction:name(), x, y)
    local second = own and M.nearest_own_region(faction:name(), x, y, { [own:name()] = true }) or nil
    local enemy = M.nearest_enemy_region(faction, x, y)
    log_target("own region", own)
    log_target("second own region", second)
    log_target("enemy region", enemy)

    local steps = {
        { "bundles", function() test_bundles(faction, own, enemy) end },
        { "relations", function() test_relations(faction, x, y) end },
        { "settlements", function() test_settlements(faction, own, second, x, y) end },
    }
    for _, step in ipairs(steps) do
        local ok, err = pcall(step[2])
        if not ok then
            log("realm test step " .. step[1] .. " CRASHED: " .. tostring(err))
        end
    end
    log("realm test END")
end

return M
