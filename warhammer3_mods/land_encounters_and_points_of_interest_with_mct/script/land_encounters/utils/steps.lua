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

--- A value at one difficulty, with every stepped value inside it picked for that difficulty. Tables are copied.
--- @param value any The value.
--- @param index number The difficulty's step index.
--- @returns any The value for that difficulty.
local function pick(value, index)
    if type(value) ~= "table" then return value end
    if value.steps then return value.steps[index] end
    local copy = {}
    for key, inner in pairs(value) do copy[key] = pick(inner, index) end
    return copy
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
