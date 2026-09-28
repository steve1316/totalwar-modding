--- Checks the CLAUDE.md line-width rule on every shipped Lua file.

local h = require("tests/helpers")

--- Shipped Lua files.
local SCRIPT_FILES = {
    "script/campaign/mod/jvj_kadon.lua",
    "script/jvj_kadon/creatures.lua",
    "script/jvj_kadon/creatures_generated.lua",
    "script/jvj_kadon/settings.lua",
    "script/jvj_kadon/drops.lua",
    "script/mct/settings/jvj_kadon.lua",
}

h.test("no code line is over 200 characters", function()
    for _, path in ipairs(SCRIPT_FILES) do
        local line_number = 0
        for line in io.lines(path) do
            line_number = line_number + 1
            h.truthy(#line <= 200, path .. ":" .. line_number .. " is " .. #line .. " characters")
        end
    end
end)

h.run()
