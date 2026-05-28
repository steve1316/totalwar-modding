--- Side-effect module that publishes shared utility globals: log(), boolean/string helpers,
--- and the AMBUSH/INTERCEPTION/ALLIED_REINFORCEMENTS_PERMITTED battle-type constants.

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

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- string helpers
--- (from utils/strings.lua)

local LAND_ENCOUNTER_TYPE = 0
local SMITHY_TYPE = 1

--- Parses a marker id of the form "land_enc_marker_<zone>_<index>" (16-char prefix) and returns {zone, index, type}.
--- A "_smithy_" infix marks the marker as a smithy POI instead of a land encounter.
--- @param marker_id string The full marker id to parse.
--- @returns table A 3-element array { zone_name string, spot_index number, type number } where type is LAND_ENCOUNTER_TYPE or SMITHY_TYPE.
function process_marker_id(marker_id)
    beginning_index, ending_index = string.find(marker_id, "_smithy_")
    if beginning_index ~= nil then
        local zone_name = string.sub(marker_id, 17, beginning_index - 1)
        local spot_index = string.sub(marker_id, ending_index + 1, #marker_id)
        return { zone_name, tonumber(spot_index), SMITHY_TYPE }
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
