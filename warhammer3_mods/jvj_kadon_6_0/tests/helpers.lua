--- Shared helpers for the Kadon plain-Lua tests. Run every test file from the mod root, e.g. `lua tests/test_db.lua`.

package.path = "./?.lua;" .. package.path

local M = {}

--- Registered tests in order. Each entry is `{ name = string, fn = function }`.
M.tests = {}

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Assertions and runner

--- Registers a test.
--- @param name string Test name printed in the results.
--- @param fn function Test body. Raises an error to fail.
function M.test(name, fn)
    table.insert(M.tests, { name = name, fn = fn })
end

--- Fails when `actual` is not equal to `expected`.
--- @param actual any Value produced by the code under test.
--- @param expected any Value the test expects.
--- @param label string|nil Name shown in the failure message.
function M.eq(actual, expected, label)
    if actual ~= expected then
        error((label or "value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

--- Fails when `value` is false or nil.
--- @param value any Value that must be truthy.
--- @param label string|nil Name shown in the failure message.
function M.truthy(value, label)
    if not value then
        error((label or "value") .. " expected to be truthy", 2)
    end
end

--- Runs every registered test, prints one line per test, and exits non-zero when any test failed.
function M.run()
    local failed = 0
    for _, t in ipairs(M.tests) do
        local ok, err = pcall(t.fn)
        if ok then
            print("PASS " .. t.name)
        else
            failed = failed + 1
            print("FAIL " .. t.name .. ": " .. tostring(err))
        end
    end
    print(string.format("%d passed, %d failed", #M.tests - failed, failed))
    os.exit(failed == 0 and 0 or 1)
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- TSV reading

--- Reads an RPFM TSV. Line 1 is the header and line 2 is the `#table;version;path` line, which is skipped.
--- @param path string Path relative to the mod root.
--- @returns table `{ header = {string}, rows = {{string}} }`.
function M.read_tsv(path)
    local result = { header = {}, rows = {} }
    local line_number = 0
    for line in io.lines(path) do
        line_number = line_number + 1
        local cells = {}
        for cell in (line .. "\t"):gmatch("([^\t]*)\t") do
            table.insert(cells, cell)
        end
        if line_number == 1 then
            result.header = cells
        elseif line_number > 2 and line ~= "" then
            table.insert(result.rows, cells)
        end
    end
    return result
end

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Game stubs

--- Installs stub `cm`, `core` and `out` globals and returns the table that records what the code under test did.
--- @param random_values table|nil Queue of numbers `cm:random_number` returns in order. Returns 1 once the queue is empty.
--- @returns table Recorder with `listeners`, `added`, `forced`, `first_tick`, `battle`, `factions`, `human`, `logs`, `owned_dlc`.
--- `owned_dlc` is nil to own every DLC, or a set of owned product keys for human factions.
function M.install_game_stubs(random_values)
    local queue = random_values or {}
    local stubs = {
        listeners = {},
        added = {},
        forced = {},
        first_tick = {},
        battle = { attacker_cqi = 1, attacker_name = "attacker", defender_cqi = 2, defender_name = "defender" },
        factions = {},
        human = {},
        logs = {},
        owned_dlc = nil,
    }
    _G.out = function(text)
        table.insert(stubs.logs, text)
    end
    _G.core = {
        add_listener = function(_, name, event, condition, callback, persistent)
            table.insert(stubs.listeners, { name = name, event = event, condition = condition, callback = callback, persistent = persistent })
        end,
    }
    _G.cm = {
        random_number = function(_, max)
            local value = table.remove(queue, 1) or 1
            if value > (max or 100) then
                error("random_number stub value " .. value .. " is above max " .. tostring(max))
            end
            return value
        end,
        add_ancillary_to_faction = function(_, faction, key, suppress)
            table.insert(stubs.added, { faction = faction:name(), key = key })
        end,
        force_add_ancillary = function(_, character, key, force_equip, suppress)
            table.insert(stubs.forced, { character = character, key = key, force_equip = force_equip })
        end,
        add_first_tick_callback_new = function(_, callback)
            table.insert(stubs.first_tick, callback)
        end,
        pending_battle_cache_get_attacker = function(_, index)
            return stubs.battle.attacker_cqi, 0, stubs.battle.attacker_name
        end,
        pending_battle_cache_get_defender = function(_, index)
            return stubs.battle.defender_cqi, 0, stubs.battle.defender_name
        end,
        get_faction = function(_, key)
            return stubs.factions[key]
        end,
        get_human_factions = function()
            return stubs.human
        end,
        --- Mirrors CA: AI factions own everything, humans own what `owned_dlc` lists.
        faction_has_dlc_or_is_ai = function(_, dlc_key, faction_key)
            if stubs.owned_dlc == nil then return true end
            local faction = stubs.factions[faction_key]
            if faction and not faction:is_human() then return true end
            return stubs.owned_dlc[dlc_key] == true
        end,
    }
    return stubs
end

--- Builds a fake faction interface.
--- @param opts table|nil Fields: `name`, `human` (default true), `rebel`, `quest`, `owned` (list of ancillary keys), `leader`.
--- @returns table Object with the faction methods the mod calls.
function M.fake_faction(opts)
    opts = opts or {}
    local owned = {}
    for _, key in ipairs(opts.owned or {}) do
        owned[key] = true
    end
    return {
        name = function() return opts.name or "wh_main_emp_empire" end,
        is_human = function() return opts.human ~= false end,
        is_rebel = function() return opts.rebel == true end,
        is_quest_battle_faction = function() return opts.quest == true end,
        ancillary_exists = function(_, key) return owned[key] == true end,
        has_faction_leader = function() return opts.leader ~= nil end,
        faction_leader = function() return opts.leader end,
    }
end

return M
