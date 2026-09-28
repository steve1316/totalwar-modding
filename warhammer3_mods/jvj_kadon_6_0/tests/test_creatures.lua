--- Checks the creature data against the scroll ancillary tables.

local h = require("tests/helpers")

--- Both scroll ancillary tables.
local ANCILLARY_TSVS = {
    "db/ancillaries_tables/jvj_kadon_binding.tsv",
    "db/ancillaries_tables/jvj_kadon_kinship.tsv",
}

local creatures = require("script/jvj_kadon/creatures")

h.test("44 creatures with unique ids and names", function()
    h.eq(#creatures.list, 44, "creature count")
    local seen = {}
    for _, creature in ipairs(creatures.list) do
        h.truthy(not seen[creature.id], "duplicate id " .. creature.id)
        seen[creature.id] = true
        h.truthy(creature.name ~= nil and creature.name ~= "", creature.id .. " name")
        h.truthy(#creature.kin >= 1 and #creature.bind >= 1, creature.id .. " has kin and bind keys")
    end
end)

h.test("creature keys match the ancillary tables exactly", function()
    local db_keys = {}
    local db_count = 0
    for _, path in ipairs(ANCILLARY_TSVS) do
        for _, row in ipairs(h.read_tsv(path).rows) do
            db_keys[row[1]] = true
            db_count = db_count + 1
        end
    end
    local data_count = 0
    local used = {}
    for _, creature in ipairs(creatures.list) do
        for _, list in ipairs({ creature.kin, creature.bind }) do
            for _, key in ipairs(list) do
                h.truthy(db_keys[key], key .. " exists in the ancillaries tables")
                h.truthy(not used[key], key .. " used once")
                used[key] = true
                data_count = data_count + 1
            end
        end
    end
    h.eq(data_count, db_count, "keys covered")
    h.eq(data_count, 91, "total keys")
end)

h.test("giant has four kin keys and one bind key", function()
    for _, creature in ipairs(creatures.list) do
        if creature.id == "giant" then
            h.eq(#creature.kin, 4, "giant kin keys")
            h.eq(#creature.bind, 1, "giant bind keys")
            return
        end
    end
    error("giant not found")
end)

h.test("find returns a creature by id and nil for unknown ids", function()
    h.eq(creatures.find("carnosaur").name, "Carnosaur", "carnosaur")
    h.eq(creatures.find("random"), nil, "random")
    h.eq(creatures.find(nil), nil, "nil")
end)

h.run()
