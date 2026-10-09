--- Marked spots: a site placed on the map near a place and seen by one faction only, through CA's `Interactive_Marker_Manager` (loaded by CA
--- for every campaign and copied into `_G` like `cm`). A mark shows one marker until its last turns, then counts down one marker per turn.
--- Walking onto any of them fires the mark's entered event, and they stay put so a lost battle can be fought again. Shared by the Tavern's
--- marked contracts and the Smithy's Fetch Star-Metal commission.

require("script/land_encounters/utils/common")

local M = {}

--- Marker skins a mark steps through: the far one until the last turns, then the countdown.
M.INFOS = { "invasion_marker_5", "invasion_marker_3", "invasion_marker_2", "invasion_marker_1" }

--- The regions within `regions_away` steps of a region, itself included, in a fixed order so every multiplayer client agrees.
--- @param region region The starting region.
--- @param regions_away number How many neighbour steps to go.
--- @returns table Region interfaces.
function M.regions_near(region, regions_away)
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

--- Where something appears near a place: a random region within `regions_away` regions of it, at a valid spot as far as `distance` from
--- that region's settlement as the land allows, halving the distance until a spot is found, as the vanilla monster hunts do.
--- @param coordinates table The place's { x, y }.
--- @param faction_key string The faction the spot must suit: an army's, or the holder's for a marker.
--- @param regions_away number How many regions away it may appear.
--- @param distance number The farthest it may stand from the region's settlement.
--- @returns number|nil The map x position, or nil when no spot was found.
--- @returns number|nil The map y position.
--- @returns string|nil The region's key.
function M.spawn_point(coordinates, faction_key, regions_away, distance)
    local home = region_at(coordinates)
    local regions = home and M.regions_near(home, regions_away) or {}
    if #regions == 0 then return nil end
    local region = regions[random_number(#regions)]
    while distance >= 1 do
        local x, y = cm:find_valid_spawn_location_for_character_from_settlement(faction_key, region:name(), false, true, distance)
        if x ~= -1 then return x, y, region:name() end
        distance = math.floor(distance / 2)
    end
    return nil
end

--- Places a mark at a position for one faction: its first marker lasts until the last turns, then each countdown marker one turn, spawned
--- by `countdown_event`. Walking onto any of them fires `entered_event`, and none despawns when entered. The mark's marker types are named
--- `mark` followed by _1 to _4.
--- @param mark string The mark's key, unique to its holder and mission.
--- @param faction_name string The faction that sees it.
--- @param x number The map x position.
--- @param y number The map y position.
--- @param turns number Turns until it is gone.
--- @param entered_event string The event fired when a lord walks onto it.
--- @param countdown_event string The event that steps it to its next marker.
function M.place(mark, faction_name, x, y, turns, entered_event, countdown_event)
    M.clear(mark)
    local first = nil
    for i, info in ipairs(M.INFOS) do
        local duration = i == 1 and math.max(1, turns - #M.INFOS + 1) or 1
        local marker = Interactive_Marker_Manager:new_marker_type(mark .. "_" .. i, info, duration, 1, faction_name)
        if i < #M.INFOS then marker:add_timeout_event(countdown_event, mark .. "_" .. (i + 1)) end
        marker:add_interaction_event(entered_event)
        marker:despawn_on_interaction(false)
        first = first or marker
    end
    first:spawn_at_location(x, y, false, true, 0)
end

--- Removes a mark's markers, their marker types and the listeners CA's marker manager set up for them, when it has any. CA's own
--- `clear_marker_type` counts a marker's instances with `#` on a keyed table, so it never despawns them (`despawn_all` does first), and it
--- leaves the listeners behind, which a later mark with the same key would hear twice.
--- @param mark string The mark's key.
function M.clear(mark)
    for i = 1, #M.INFOS do
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

return M
