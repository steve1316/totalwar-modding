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

--- Returns the game tag a model or battle entity key belongs to, from its prefix.
--- @param key string Variant or battle entity key.
--- @returns string|nil "WH1", "WH2", "WH3", or nil for mod-made keys.
local function game_from_prefix(key)
    if key:find("^wh3_") then return "WH3" end
    if key:find("^wh2_") then return "WH2" end
    if key:find("^wh_") then return "WH1" end
    return nil
end

h.test("every game tag matches the DB", function()
    local custom_units = {}
    for _, row in ipairs(h.read_tsv("db/units_custom_battle_permissions_tables/jvj_kadon.tsv").rows) do
        custom_units[row[3]] = true
    end
    local variants = {}
    for _, row in ipairs(h.read_tsv("db/unit_variants_tables/jvj_kadon_binding.tsv").rows) do
        variants[row[2]] = row[4]
    end
    local land_units = h.read_tsv("db/land_units_tables/jvj_kadon_binding.tsv")
    local entity_col
    for i, name in ipairs(land_units.header) do
        if name == "man_entity" then entity_col = i end
    end
    local entities = {}
    for _, row in ipairs(land_units.rows) do
        entities[row[1]] = row[entity_col]
    end

    for _, creature in ipairs(creatures.list) do
        local expected = "Original"
        if not custom_units[creature.kin[1]] then
            local bind_key = creature.bind[1]
            expected = game_from_prefix(variants[bind_key]) or game_from_prefix(entities[bind_key])
        end
        h.eq(creature.game, expected, creature.id .. " game")
    end
end)

h.test("label adds the game tag", function()
    h.eq(creatures.label(creatures.find("carnosaur")), "Carnosaur (WH2)", "carnosaur")
    h.eq(creatures.label(creatures.find("unicorn")), "Unicorns (Original)", "unicorn")
end)

h.test("find returns a creature by id and nil for unknown ids", function()
    h.eq(creatures.find("carnosaur").name, "Carnosaur", "carnosaur")
    h.eq(creatures.find("random"), nil, "random")
    h.eq(creatures.find(nil), nil, "nil")
end)

h.run()
