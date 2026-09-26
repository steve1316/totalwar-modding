--- Loads LEAPOI's Lua code outside the game. Stubs the game's globals, points `require` at the mod folder, silences the mod's debug prints and
--- parses the simulator's `key=value` options.
---
--- Usage from a simulator script: `local write_line, options, to_json = dofile("<this folder>/game_stubs.lua")(arg, defaults)`, where `arg[1]` is the
--- LEAPOI mod folder that holds `script/`.

--- Encodes a Lua value as JSON. Empty tables and tables with a `[1]` entry are arrays, other tables are objects with sorted keys.
--- @param value any The value to encode.
--- @returns string The JSON text.
local function to_json(value)
    local kind = type(value)
    if kind == "string" then
        return '"' .. value:gsub('[%c"\\]', function(c) return string.format("\\u%04x", c:byte()) end) .. '"'
    elseif kind == "number" or kind == "boolean" then
        return tostring(value)
    elseif kind == "table" then
        local parts = {}
        if next(value) == nil or value[1] ~= nil then
            for _, item in ipairs(value) do parts[#parts + 1] = to_json(item) end
            return "[" .. table.concat(parts, ",") .. "]"
        end
        local keys = {}
        for key in pairs(value) do keys[#keys + 1] = tostring(key) end
        table.sort(keys)
        for _, key in ipairs(keys) do parts[#parts + 1] = to_json(key) .. ":" .. to_json(value[key]) end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    return "null"
end

--- Sets up the stubbed game environment and parses the command line.
--- @param script_args table The script's `arg` table: the LEAPOI mod folder, then `key=value` options.
--- @param defaults table Option defaults, overridden by the command line.
--- @returns function, table, function The real `print` for the simulator's own output, the parsed options, and `to_json`.
return function(script_args, defaults)
    package.path = script_args[1] .. "/?.lua;" .. package.path

    local options = defaults
    for i = 2, #script_args do
        local key, value = script_args[i]:match("^(%w+)=(.*)$")
        if key then options[key] = value end
    end

    --- Stand-in for every game global. Any field is a function that returns the stub itself, so chained game calls do nothing.
    local stub
    stub = setmetatable({}, {
        __index = function() return function() return stub end end,
        __call = function() return stub end,
    })
    cm, core, mct = stub, stub, stub
    out = function() end
    get_mct = function() return nil end

    local write_line = print
    print = function() end
    return write_line, options, to_json
end
