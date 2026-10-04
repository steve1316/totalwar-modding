--- Difficulty steps for offer values: a value that differs on Easy, Medium and Hard is written as `M.of(easy, medium, hard)` in the offer
--- configs, and `M.resolve` turns an offer record into the plain record for one difficulty. Pure Lua, so the generators and the harness read
--- the same configs.

local M = {}

--- Difficulty keys in step order, easiest first. utils/common.lua publishes them as `DIFFICULTY_KEYS`.
M.DIFFICULTIES = { "easy", "medium", "hard" }

--- Step index of each difficulty key.
local INDEX = {}
for i, difficulty in ipairs(M.DIFFICULTIES) do INDEX[difficulty] = i end

--- Resolved records by difficulty and then by the record itself, so each record resolves once per difficulty.
local cache = {}
for _, difficulty in ipairs(M.DIFFICULTIES) do cache[difficulty] = {} end

--- A value with one step per difficulty.
--- @param easy any The Easy value.
--- @param medium any The Medium value.
--- @param hard any The Hard value.
--- @returns table The stepped value, `{ steps = { easy, medium, hard } }`.
function M.of(easy, medium, hard)
    return { steps = { easy, medium, hard } }
end

--- An effect bundle with one version per difficulty, named with the difficulty, e.g. land_enc_effect_spot_leave_an_offering_medium. The
--- spot generator names the bundles it writes the same way.
--- @param key string The bundle key without the difficulty.
--- @returns table The stepped bundle key.
function M.tiered(key)
    return M.of(key .. "_easy", key .. "_medium", key .. "_hard")
end

--- True when a value or anything inside it differs by difficulty.
--- @param value any The value.
--- @param skip string|nil A field of a table value to leave out, e.g. "cost".
--- @returns boolean True when it holds a stepped value.
function M.varies(value, skip)
    if type(value) ~= "table" then return false end
    if value.steps then return true end
    for key, inner in pairs(value) do
        if key ~= skip and M.varies(inner) then return true end
    end
    return false
end

--- An offer's battle notice name: its key, with the difficulty added when the offer's effect (not just its cost) differs by difficulty, e.g.
--- thin_the_ranks_medium. Each such notice has one scripted objective per difficulty with that difficulty's numbers.
--- @param key string The notice's base name, usually the offer key.
--- @param record table The offer record as configured, before it is resolved.
--- @param difficulty string "easy", "medium" or "hard".
--- @returns string The notice name.
function M.notice(key, record, difficulty)
    return M.varies(record, "cost") and key .. "_" .. difficulty or key
end

--- Splits a notice name into its base name and difficulty, e.g. "thin_the_ranks_medium" into "thin_the_ranks" and "medium".
--- @param name string The notice name.
--- @returns string The base name.
--- @returns string|nil The difficulty, or nil when the name has none.
function M.split(name)
    for _, difficulty in ipairs(M.DIFFICULTIES) do
        local base = name:match("^(.+)_" .. difficulty .. "$")
        if base then return base, difficulty end
    end
    return name, nil
end

--- A value at one difficulty, with every stepped value inside it picked for that difficulty. A table holding steps is copied, and any other
--- value is returned as it is.
--- @param value any The value.
--- @param index number The difficulty's step index.
--- @returns any The value for that difficulty.
local function pick(value, index)
    if type(value) ~= "table" then return value end
    if value.steps then return value.steps[index] end
    local copy, changed = {}, false
    for key, inner in pairs(value) do
        copy[key] = pick(inner, index)
        changed = changed or copy[key] ~= inner
    end
    return changed and copy or value
end

--- An offer record at one difficulty. The copy is made once and kept, so the same record and difficulty always give the same table.
--- @param record table The offer record.
--- @param difficulty string "easy", "medium" or "hard".
--- @returns table The record for that difficulty.
function M.resolve(record, difficulty)
    local by_record = cache[difficulty]
    local resolved = by_record[record]
    if resolved == nil then
        resolved = pick(record, INDEX[difficulty])
        by_record[record] = resolved
    end
    return resolved
end

return M
