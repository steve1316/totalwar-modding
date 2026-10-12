--- Standalone debug mod for authoring fixed-position content (encounter spot lists, tavern sites, quest battle anchors) on the campaign map.
---
--- Workflow:
---   F2 - capture the camera's look-at point and the region and province under it, log it to debug_coordinates.txt, and teleport the last
---        selected army there, so placing and checking a position takes one key.
---   F3 - pop the most recent capture off the list and delete its line from debug_coordinates.txt. Use this to undo a mis-aimed F2.
---   F4 - dump every settlement (region, name, position, province, owner, capital) to debug_settlements.tsv, and every LEAPOI spot with
---        the region it sits in plus a spot count per region to debug_spot_density.tsv.
--- The fog of war stays off for the whole session. The player's armies refill their movement on select and after every move, and their
--- lords are renamed to their map position ("359, 537").
---
--- The log files live in the game install directory (next to script_log.txt). Each game session writes a divider + timestamp header at
--- startup so multiple sessions stay distinguishable. Coordinates are logical map coordinates, the ones spot lists and markers use.
---
--- Disable this mod for any production / shipped build. It is a developer tool only.

--- Defensive guard against double-load. CA auto-load picks up files in script/campaign/mod/ but
--- if a parent mod ever require()s this file, we don't want duplicate listener registrations.
if _G._coord_logger_loaded then
    out("[COORDS LOGGER] Already loaded - skipping duplicate init.")
    return
end
_G._coord_logger_loaded = true

local CAPTURE_SHORTCUT = "script_F2"
local POP_SHORTCUT     = "script_F3"
local DUMP_SHORTCUT    = "script_F4"

--- Path of the persistent log file. Relative paths resolve against the game install directory.
local LOG_FILE = "debug_coordinates.txt"
--- Path of the settlement dump F4 writes, overwritten on each press. Tab-separated, one settlement per line.
local SETTLEMENTS_FILE = "debug_settlements.tsv"
--- Path of the LEAPOI spot list F4 also writes: every spot with the region it sits in, then a count per region, busiest first.
local SPOTS_FILE = "debug_spot_density.tsv"
--- LEAPOI's pure-data coordinate config, read straight from its pack. Needs LEAPOI loaded.
local LEAPOI_COORDINATES = "script/land_encounters/configs/coordinates"
--- LEAPOI's campaign keys in its coordinate config, by the game's campaign name.
local LEAPOI_CAMPAIGNS = { main_warhammer = "immortal_empires", wh3_main_chaos = "realm_of_chaos" }
--- LEAPOI's name for the Immortal Empires Expanded mod, whose spots are added on top of Immortal Empires when it is enabled.
local IEEE_MOD = "!cr_immortal_empires_expanded"

local captures = {}
--- Command queue index of the local player's last selected army, the one F2 teleports. Nil until an army is selected.
local selected_cqi = nil

--- Appends a single line to the log file. Silently degrades to script_log.txt on io failure so a
--- broken file write never blocks the in-game workflow.
local function append_log(line)
    local f, err = io.open(LOG_FILE, "a")
    if not f then
        out("[COORDS ERROR] Failed to open " .. LOG_FILE .. ": " .. tostring(err))
        return
    end
    f:write(line .. "\n")
    f:close()
end

--- Writes a session-start header to the log file. If the file already has content, the header is
--- preceded by a blank line so the previous session's entries stay visually separated. If the file
--- is brand new, the header is written at the top.
local function write_session_header()
    local timestamp = os.date("%Y-%m-%d %H:%M:%S")
    local existing = io.open(LOG_FILE, "r")
    local file_has_content = false
    if existing then
        local first_byte = existing:read(1)
        file_has_content = (first_byte ~= nil)
        existing:close()
    end

    local f, err = io.open(LOG_FILE, "a")
    if not f then
        out("[COORDS ERROR] Failed to open " .. LOG_FILE .. ": " .. tostring(err))
        return
    end
    if file_has_content then
        f:write("\n=== Session: " .. timestamp .. " ===\n")
    else
        f:write("=== Session: " .. timestamp .. " ===\n")
    end
    f:close()
    out("[COORDS LOGGER] Logging to " .. LOG_FILE .. " under session " .. timestamp)
end

--- Reads the point the campaign camera looks at, in logical map coordinates. The camera reports display coordinates, which the spot lists,
--- markers, teleports and region lookups do not use, so they go through `cm:dis_to_log` first.
--- @returns number|nil The logical x coordinate, nil when the camera API returns nothing.
--- @returns number|nil The logical y coordinate.
local function camera_point()
    cm:cache_camera_position()
    local dx, dy = cm:get_cached_camera_position()
    cm:delete_cached_camera_position()
    if dx == nil or dy == nil then
        out("[COORDS ERROR] No coordinates returned from camera API - aborting.")
        return nil, nil
    end
    local x, y = cm:dis_to_log(dx, dy)
    if x == nil or y == nil then
        out("[COORDS ERROR] Could not convert display {" .. tostring(dx) .. ", " .. tostring(dy) .. "} to logical coordinates - aborting.")
        return nil, nil
    end
    return math.floor(x), math.floor(y)
end

--- True when a character is a general of the local player's faction with an army.
--- @param character userdata The character interface.
--- @returns boolean True for the local player's army generals.
local function is_local_general(character)
    return not character:is_null_interface() and character:has_military_force()
        and character:faction():name() == cm:get_local_faction_name(true)
end

--- Refills a general's movement points, so the debug player's armies never run out of movement.
--- @param character userdata The character interface.
local function refill_movement(character)
    if is_local_general(character) then
        cm:replenish_action_points(cm:char_lookup_str(character))
    end
end

--- Renames one of the debug player's generals to their logical map position, e.g. "359, 537", so the position reads off the army banner.
--- @param character userdata The character interface.
local function name_after_position(character)
    if is_local_general(character) then
        cm:change_character_custom_name(character, character:logical_position_x() .. ", " .. character:logical_position_y(), "", "", "")
    end
end

--- Names the region and province at a logical position. Sea tiles and shrouded areas may return nil or error, so missing pieces read
--- "unknown" and the capture is still logged.
--- @param x number Logical x coordinate.
--- @param y number Logical y coordinate.
--- @returns string The region key.
--- @returns string The province key.
local function region_and_province_at(x, y)
    local ok, result = pcall(function()
        local rd = cm:get_region_data_at_position(x, y)
        if not rd or rd:is_null_interface() then return nil end
        local region = rd:region()
        if not region or region:is_null_interface() then return nil end
        local province = region:province()
        return { region = region:name(), province = province and not province:is_null_interface() and province:key() or nil }
    end)
    if not ok or not result then return "unknown", "unknown" end
    return result.region or "unknown", result.province or "unknown"
end

--- Teleports the last selected army to a logical position, nudged onto the nearest spot the army can stand on. Does nothing when no
--- army of the local player is selected.
--- @param x number Logical x coordinate.
--- @param y number Logical y coordinate.
local function teleport_selected(x, y)
    local character = selected_cqi and cm:get_character_by_cqi(selected_cqi)
    if not character or character:is_null_interface() or not is_local_general(character) then
        out("[COORDS] No army of yours selected - captured without teleporting.")
        return
    end
    local tx, ty = cm:find_valid_spawn_location_for_character_from_position(character:faction():name(), x, y, false, 1)
    if tx == -1 or ty == -1 then
        out("[COORDS] No valid spot near {" .. x .. ", " .. y .. "} - captured without teleporting.")
        return
    end
    local lookup = cm:char_lookup_str(character)
    --- Deferred because direct calls from a ShortcutTriggered listener silently no-op for some campaign API calls.
    cm:callback(function()
        cm:teleport_to(lookup, tx, ty)
        cm:replenish_action_points(lookup)
        out("[COORDS] Teleported " .. lookup .. " to {" .. tx .. ", " .. ty .. "}")
    end, 0)
    --- The new position reads back a moment after the teleport.
    cm:callback(function() name_after_position(cm:get_character_by_cqi(selected_cqi)) end, 0.5)
end

--- Captures the camera's look-at point: logs it with its region and province, then teleports the selected army there.
local function capture_at_camera()
    local x, y = camera_point()
    if not x then return end
    local region_key, province_key = region_and_province_at(x, y)
    table.insert(captures, { x = x, y = y, region = region_key, province = province_key })
    local line = "[ADD] {" .. tostring(x) .. ", " .. tostring(y) .. "}, -- region: " .. region_key .. ", province: " .. province_key
    append_log(line)
    out("[COORDS] " .. line)
    teleport_selected(x, y)
end

--- Pops the most recent capture and physically deletes the matching `[ADD]` line from the log
--- file. Only scans within the CURRENT session (lines after the most recent `=== Session: ===`
--- header) so F3 never reaches back into earlier sessions. The whole file is read into memory,
--- the one target line is removed, and the file is rewritten - simple and safe at the entry
--- volumes we're dealing with.
local function pop_last_capture()
    if #captures == 0 then
        out("[COORDS] Nothing to pop - captures list is empty.")
        return
    end
    local last = table.remove(captures, #captures)

    local f, err = io.open(LOG_FILE, "r")
    if not f then
        out("[COORDS ERROR] Cannot read " .. LOG_FILE .. " to pop entry: " .. tostring(err))
        return
    end
    local content = f:read("*all") or ""
    f:close()
    out("[COORDS DEBUG] Read " .. tostring(#content) .. " bytes from " .. LOG_FILE)

    --- Manual split. f:lines() proved unreliable in the WH3 sandbox - sometimes returns zero
    --- iterations on files that clearly have content. read("*all") + gmatch sidesteps that.
    --- Trailing "\n" appended so the final line (which may not end with \n) still gets matched.
    local lines = {}
    for line in (content .. "\n"):gmatch("([^\r\n]*)[\r\n]") do
        table.insert(lines, line)
    end
    out("[COORDS DEBUG] Parsed " .. tostring(#lines) .. " lines")

    --- Use string.sub prefix matching instead of Lua patterns. Patterns proved unreliable here -
    --- maybe a sandbox issue, maybe a hidden char issue. Direct substring compare is bulletproof.
    local SESSION_PREFIX = "=== Session:"
    local ADD_PREFIX = "[ADD]"

    local session_start = 0
    for i = #lines, 1, -1 do
        if string.sub(lines[i], 1, #SESSION_PREFIX) == SESSION_PREFIX then
            session_start = i
            break
        end
    end
    out("[COORDS DEBUG] session_start=" .. tostring(session_start))
    if session_start == 0 then
        --- No session header in file at all - scan from the top. Shouldn't happen since
        --- write_session_header always writes one at startup, but defensive.
        session_start = 1
    end

    local target_index = 0
    for i = #lines, session_start, -1 do
        if string.sub(lines[i], 1, #ADD_PREFIX) == ADD_PREFIX then
            target_index = i
            break
        end
    end
    if target_index == 0 then
        out("[COORDS ERROR] No [ADD] line found in current session to remove. In-memory pop already done.")
        out("[COORDS DEBUG] Dump of all parsed lines:")
        for i, line in ipairs(lines) do
            out("[COORDS DEBUG]   " .. tostring(i) .. ": [" .. tostring(line) .. "] (len=" .. tostring(#line) .. ")")
        end
        return
    end

    table.remove(lines, target_index)

    local f2, err2 = io.open(LOG_FILE, "w")
    if not f2 then
        out("[COORDS ERROR] Cannot reopen " .. LOG_FILE .. " for rewrite: " .. tostring(err2))
        return
    end
    for _, line in ipairs(lines) do
        f2:write(line .. "\n")
    end
    f2:close()

    out("[COORDS] Popped {" .. tostring(last.x) .. ", " .. tostring(last.y) .. "} - deleted log line " .. tostring(target_index) .. ".")
end

--- Writes every settlement on the map to `SETTLEMENTS_FILE`: region key, on-screen name, logical x and y, province key, owner and whether it is
--- a province capital. One pass over the region list, each region read under pcall so one odd region cannot stop the dump.
local function dump_settlements()
    local f, err = io.open(SETTLEMENTS_FILE, "w")
    if not f then
        out("[COORDS ERROR] Failed to open " .. SETTLEMENTS_FILE .. ": " .. tostring(err))
        return
    end
    f:write("# campaign: " .. tostring(cm:get_campaign_name()) .. ", turn " .. tostring(cm:model():turn_number()) .. "\n")
    f:write("region\tname\tx\ty\tprovince\towner\tprovince_capital\n")
    local regions = cm:model():world():region_manager():region_list()
    local written = 0
    for i = 0, regions:num_items() - 1 do
        local ok, row = pcall(function()
            local region = regions:item_at(i)
            local settlement = region:settlement()
            if settlement:is_null_interface() then return nil end
            local owner = region:owning_faction()
            local province = region:province()
            return table.concat({
                region:name(),
                common.get_localised_string("regions_onscreen_" .. region:name()),
                tostring(settlement:logical_position_x()),
                tostring(settlement:logical_position_y()),
                province:is_null_interface() and "" or province:key(),
                owner:is_null_interface() and "" or owner:name(),
                tostring(region:is_province_capital()),
            }, "\t")
        end)
        if ok and row then
            f:write(row .. "\n")
            written = written + 1
        elseif not ok then
            out("[COORDS ERROR] Region " .. tostring(i) .. " failed: " .. tostring(row))
        end
    end
    f:close()
    out("[COORDS] Wrote " .. written .. " settlements to " .. SETTLEMENTS_FILE)
end

--- Names the region at a logical position, "sea" when there is none.
--- @param x number Logical x coordinate.
--- @param y number Logical y coordinate.
--- @returns string The region key and its on-screen name, tab-separated.
local function region_at(x, y)
    local key = region_and_province_at(x, y)
    if key == "unknown" then return "sea\t" end
    return key .. "\t" .. common.get_localised_string("regions_onscreen_" .. key)
end

--- Reads LEAPOI's coordinate sets for this campaign: Immortal Empires gets the IE Expanded set on top when that mod is enabled.
--- @returns string|nil LEAPOI's campaign key, nil when LEAPOI is not loaded or the campaign has no spots.
--- @returns table|nil The coordinate sets, each with `treasures_and_spots` and `points_of_interest`.
local function leapoi_sets()
    local ok, coordinates = pcall(require, LEAPOI_COORDINATES)
    local campaign = LEAPOI_CAMPAIGNS[cm:get_campaign_name()]
    if not ok or not campaign then
        out("[COORDS] No LEAPOI spots for campaign " .. tostring(cm:get_campaign_name()) .. ": " .. tostring(ok and "unknown campaign" or coordinates))
        return nil, nil
    end
    local sets = { coordinates[campaign] }
    local mct_ok, enabled_mods = pcall(function() return get_mct_settings().enabled_mods end)
    if campaign == "immortal_empires" and mct_ok and enabled_mods then
        for _, mod in ipairs(enabled_mods) do
            if mod == IEEE_MOD then sets[#sets + 1] = coordinates.immortal_empires_expanded end
        end
    end
    return campaign, sets
end

--- Writes `SPOTS_FILE`: every LEAPOI encounter spot and point of interest of this campaign with the region it sits in, then each region's
--- encounter spot count, busiest first. Logs the five busiest regions.
local function dump_spot_density()
    local campaign, sets = leapoi_sets()
    if not campaign then return end
    local f, err = io.open(SPOTS_FILE, "w")
    if not f then
        out("[COORDS ERROR] Failed to open " .. SPOTS_FILE .. ": " .. tostring(err))
        return
    end
    f:write("# campaign: " .. campaign .. "\nzone\tkind\tindex\tx\ty\tregion\tregion_name\n")
    local per_region, written = {}, 0
    for _, set in ipairs(sets) do
        for zone, spots in pairs(set.treasures_and_spots) do
            for i, spot in ipairs(spots) do
                --- Disabled spots (`disabled = true`) never become encounters, so they are listed but not counted.
                local region = region_at(spot[1], spot[2])
                if not spot.disabled then per_region[region] = (per_region[region] or 0) + 1 end
                f:write(zone .. "\t" .. (spot.disabled and "disabled" or "spot") .. "\t" .. i .. "\t" .. spot[1] .. "\t" .. spot[2] .. "\t" .. region .. "\n")
                written = written + 1
            end
        end
        for zone, poi in pairs(set.points_of_interest) do
            for kind, list in pairs(poi) do
                for i, entry in ipairs(list) do
                    local x, y = entry.coordinates[1], entry.coordinates[2]
                    f:write(zone .. "\t" .. kind .. "\t" .. i .. "\t" .. x .. "\t" .. y .. "\t" .. region_at(x, y) .. "\n")
                    written = written + 1
                end
            end
        end
    end
    local regions = {}
    for region, count in pairs(per_region) do regions[#regions + 1] = { region = region, count = count } end
    table.sort(regions, function(a, b) return a.count > b.count or (a.count == b.count and a.region < b.region) end)
    f:write("\n# encounter spots per region, busiest first\nregion\tregion_name\tspots\n")
    for _, entry in ipairs(regions) do f:write(entry.region .. "\t" .. entry.count .. "\n") end
    f:close()
    local top = {}
    for i = 1, math.min(5, #regions) do top[#top + 1] = regions[i].region:gsub("\t", " (") .. ") " .. regions[i].count end
    out("[COORDS] Wrote " .. written .. " LEAPOI spots and points of interest to " .. SPOTS_FILE .. ". Busiest regions: " .. table.concat(top, ", "))
end

--- Turns the fog of war off: stops drawing the shroud and reveals every region to the local player. The reveal only lasts the turn, so it
--- is redone at each of the local player's turn starts. Scripts reload after every battle, so first tick covers loading back from one too.
local function lift_fog()
    cm:show_shroud(false)
    cm:lift_all_shroud()
end

write_session_header()

core:add_listener(
    "coord_logger_capture",
    "ShortcutTriggered",
    function(context) return context.string == CAPTURE_SHORTCUT end,
    function() capture_at_camera() end,
    true
)

core:add_listener(
    "coord_logger_pop",
    "ShortcutTriggered",
    function(context) return context.string == POP_SHORTCUT end,
    function() pop_last_capture() end,
    true
)

core:add_listener(
    "coord_logger_dump",
    "ShortcutTriggered",
    function(context) return context.string == DUMP_SHORTCUT end,
    function()
        cm:callback(function()
            dump_settlements()
            dump_spot_density()
        end, 0)
    end,
    true
)

--- Remembers the selected army, the one F2 teleports, refills its movement and names it after its position.
core:add_listener(
    "coord_logger_selected",
    "CharacterSelected",
    function(context) return is_local_general(context:character()) end,
    function(context)
        selected_cqi = context:character():command_queue_index()
        refill_movement(context:character())
        name_after_position(context:character())
    end,
    true
)

--- Refills movement after every move, so one army can keep going all turn, and renames the army to where it stopped.
core:add_listener(
    "coord_logger_moved",
    "CharacterFinishedMovingEvent",
    function(context) return is_local_general(context:character()) end,
    function(context)
        refill_movement(context:character())
        name_after_position(context:character())
    end,
    true
)

cm:add_first_tick_callback(lift_fog)

core:add_listener(
    "coord_logger_fog",
    "FactionTurnStart",
    function(context) return context:faction():name() == cm:get_local_faction_name(true) end,
    function() lift_fog() end,
    true
)

out("[COORDS LOGGER] Initialized. F2=capture camera point + teleport selected army there, F3=pop last capture, F4=dump settlements + LEAPOI"
    .. " spot density. Fog of war is off, armies refill movement and are named after their position.")
