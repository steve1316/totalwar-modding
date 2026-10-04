--- Side-effect module that publishes shared utility globals: log(), boolean/string helpers,
--- and the AMBUSH/INTERCEPTION/ALLIED_REINFORCEMENTS_PERMITTED battle-type constants.

--- Event feed picture shown on located LEAPOI messages.
EVENT_IMAGE_ID_LOCATION_OF_INTEREST = 1017

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- logger
--- (from utils/logger.lua)

--- Prefixes the message with the LEAPOI mod tag and writes it to the campaign log.
--- @param text any The value to log. Coerced to a string via tostring().
--- @param test any Unused legacy parameter kept for backwards compatibility.
function log(text, test)
    local mod_header_text = "LEAPOI";
    local logText = tostring(text)
    local logContext = tostring(mod_header_text)
    out(logContext .. ":  "..logText .. "\n")
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- boolean helpers
--- (from utils/boolean.lua)

stringtoboolean = { ["true"] = true, ["false"] = false }
booleantostring = { [true] = "true", [false] = "false" }

--- Returns true when the named faction is played by a human. Multiplayer-safe replacement for comparing against cm:get_local_faction_name.
--- @param faction_name string The faction key to check. May be nil or empty.
--- @returns boolean True when the faction exists and is human.
function is_human_faction_name(faction_name)
    if faction_name == nil or faction_name == "" then return false end
    local faction = cm:get_faction(faction_name)
    return faction and faction:is_human() or false
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- string helpers
--- (from utils/strings.lua)

local LAND_ENCOUNTER_TYPE = 0
local SMITHY_TYPE = 1
local TOWER_TYPE = 2

--- Parses a marker id of the form "land_enc_marker_<zone>_<index>" (16-char prefix) and returns {zone, index, type}.
--- A "_smithy_" infix marks the marker as a smithy POI and a "_tower_" infix as a tower, instead of a land encounter.
--- @param marker_id string The full marker id to parse.
--- @returns table A 3-element array { zone_name string, spot_index number, type number } where type is LAND_ENCOUNTER_TYPE, SMITHY_TYPE or
--- TOWER_TYPE.
function process_marker_id(marker_id)
    --- Two-argument string.find only. A version using a plain-text find over a pairs() loop crashed the game when a lord entered a smithy.
    local infix_start, infix_end = string.find(marker_id, "_smithy_")
    if infix_start ~= nil then
        return { string.sub(marker_id, 17, infix_start - 1), tonumber(string.sub(marker_id, infix_end + 1, #marker_id)), SMITHY_TYPE }
    end
    infix_start, infix_end = string.find(marker_id, "_tower_")
    if infix_start ~= nil then
        return { string.sub(marker_id, 17, infix_start - 1), tonumber(string.sub(marker_id, infix_end + 1, #marker_id)), TOWER_TYPE }
    end

    --- The maximum number of points in a zone is <99, so look at the last 3 chars to find the trailing underscore.
    beginning_index, ending_index = string.find(marker_id, "_", (#marker_id - 3))
    local zone_name = string.sub(marker_id, 17, beginning_index - 1)
    local spot_index = string.sub(marker_id, ending_index + 1, #marker_id)
    return { zone_name, tonumber(spot_index), LAND_ENCOUNTER_TYPE }
end


--- Splits a string on any of the characters in `separator` (treated as a regex character class).
--- @param splittable_string string The input string to split.
--- @param separator string A character class of delimiter chars (e.g. " ,;").
--- @returns table An array of non-empty substrings between delimiters.
function split_by_regex(splittable_string, separator)
    local string_parts = {}
    for part in string.gmatch(splittable_string, '([^' .. separator .. ']+)') do
        table.insert(string_parts, part)
    end
    return string_parts
end


--- Returns the number of keys in a table.
--- @param tbl table The table to count.
--- @returns number The number of key/value pairs in tbl.
function Count_keys(tbl)
    local count = 0
    for _ in pairs(tbl) do
        count = count + 1
    end
    return count
end


--- Recursively serializes a Lua table to a human-readable string for debugging.
--- @param t table The table to serialize.
--- @param indent number Current indent depth (tabs). Defaults to 0 when nil.
--- @returns string A pretty-printed representation of the table.
function table_to_string(t, indent)
    if not indent then
        indent = 0
    end
    local prefix = ""
    for i = 1, indent do
        prefix = prefix .. "\t"
    end
    local result = "{" .. "".."\n"
    local first_result = false
    for k, v in pairs(t) do
        if not first_result then
            first_result = true
        else
            result = result .. ",\n"
        end
        local layer_indent = "\t"
        if type(k) == "string" then
            k = string.format("%q", k)
        end
        if v == "" then
            v = "\"\"" --empty string
        elseif type(v) == "boolean" or type(v) == "number" then
            v = tostring(v)
        elseif type(v) == "string" then
            v = string.format("%q", v)
        elseif type(v) == "table" then
            v = table_to_string(v, indent + 1)
        end
        result = result ..layer_indent..prefix.."[" .. k .. "] = " .. v
    end
    result = result .. "\n"..prefix.."}"
    return result
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- common constants/helpers
--- (from constants/utils/common.lua)

--- Battle-type tags used across the spot/army/intervention pipeline.
AMBUSH_TYPE = 1
INTERCEPTION_TYPE = 2
ALLIED_REINFORCEMENTS_PERMITTED_TYPE = 3


--- Encounter difficulty keys from easiest to hardest.
DIFFICULTY_KEYS = require("script/land_encounters/utils/steps").DIFFICULTIES

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Weighted pick

--- Picks one entry from a list of {key, weight} pairs by weighted random.
--- @param entries table A list of {key, weight} 2-element arrays.
--- @returns string The picked key, or the last key as a fallback when the roll lands on the boundary.
function pick_weighted(entries)
    local total = 0
    for _, entry in ipairs(entries) do total = total + entry[2] end
    local roll = random_number(total)
    local acc = 0
    for _, entry in ipairs(entries) do
        acc = acc + entry[2]
        if roll <= acc then return entry[1] end
    end
    return entries[#entries][1]
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Located messages

--- Returns the region at a map position.
--- @param coordinates table The { x, y } map position.
--- @returns region The region interface, or nil when the position has none.
function region_at(coordinates)
    local region_data = cm:get_region_data_at_position(coordinates[1], coordinates[2])
    if region_data and not region_data:is_null_interface() and region_data:region() ~= nil then
        return region_data:region()
    end
    return nil
end

--- Shows one of the LEAPOI event feed messages at a map position.
--- @param faction_name string The faction that sees the message.
--- @param message string The message suffix, e.g. "smithy_lost" for event_feed_strings_text_title_event_land_enc_smithy_lost.
--- @param coordinates table The { x, y } map position.
--- @param subtitle_key string|nil A loc key to use as the subtitle instead of the message's own.
function show_located_message(faction_name, message, coordinates, subtitle_key)
    cm:show_message_event_located(faction_name,
        "event_feed_strings_text_title_event_land_enc_" .. message,
        subtitle_key or "event_feed_strings_text_subtitle_event_land_enc_" .. message,
        "event_feed_strings_text_description_event_land_enc_" .. message,
        coordinates[1],
        coordinates[2],
        false,
        EVENT_IMAGE_ID_LOCATION_OF_INTEREST
    )
end

--- Tells a living human faction that a Smithy or Tower is ready again, at its position on the map. The subtitle names the region under it,
--- or falls back to the message's own subtitle. Does nothing while the MCT `ready_notices` option is off.
--- @param faction_name string The faction to tell.
--- @param message string The event feed message suffix, e.g. "smithy_visit_available".
--- @param coordinates table The { x, y } map position of the Smithy or Tower.
function show_ready_notice(faction_name, message, coordinates)
    if not get_mct_settings().ready_notices then
        log("ready notice " .. message .. " for " .. tostring(faction_name) .. " skipped: ready notices are off")
        return
    end
    if not is_human_faction_name(faction_name) or not cm:faction_is_alive(cm:get_faction(faction_name)) then
        log("ready notice " .. message .. " skipped: " .. tostring(faction_name) .. " is not a living human faction")
        return
    end
    local region = region_at(coordinates)
    local subtitle = region and "regions_onscreen_" .. region:name() or nil
    log("ready notice " .. message .. " sent to " .. faction_name .. " at (" .. coordinates[1] .. ", " .. coordinates[2] .. "), subtitle " .. tostring(subtitle))
    show_located_message(faction_name, message, coordinates, subtitle)
end
