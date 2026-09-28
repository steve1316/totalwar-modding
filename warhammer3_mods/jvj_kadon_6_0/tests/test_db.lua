--- Checks the DB edits the script-owned drops depend on.

local h = require("tests/helpers")

--- Both scroll ancillary tables.
local ANCILLARY_TSVS = {
    "db/ancillaries_tables/jvj_kadon_binding.tsv",
    "db/ancillaries_tables/jvj_kadon_kinship.tsv",
    "db/ancillaries_tables/jvj_kadon_generated_binding.tsv",
    "db/ancillaries_tables/jvj_kadon_generated_kinship.tsv",
}

--- Binding file stems: the hand-made scrolls and the generated ones.
local BIND_STEMS = { "jvj_kadon_binding", "jvj_kadon_generated_binding" }

--- Returns the 1-based index of `name` in a TSV header.
--- @param header table Header cells.
--- @param name string Column name.
--- @returns number Column index.
local function column(header, name)
    for i, cell in ipairs(header) do
        if cell == name then return i end
    end
    error("column not found: " .. name)
end

h.test("every scroll has randomly_dropped false", function()
    local total = 0
    for _, path in ipairs(ANCILLARY_TSVS) do
        local tsv = h.read_tsv(path)
        local col = column(tsv.header, "randomly_dropped")
        for _, row in ipairs(tsv.rows) do
            h.eq(row[col], "false", row[1] .. " randomly_dropped")
            total = total + 1
        end
    end
    h.eq(total, 309, "scroll count")
end)

--- Vanilla `ancillary_uniqueness_groupings` ranges. A score outside every range shows no rarity in game ("Scroll Name ()").
local RARITY_RANGES = {
    { file = "db/ancillaries_tables/jvj_kadon_binding.tsv", name = "uncommon", min = 80, max = 100 },
    { file = "db/ancillaries_tables/jvj_kadon_kinship.tsv", name = "rare", min = 130, max = 150 },
    { file = "db/ancillaries_tables/jvj_kadon_generated_binding.tsv", name = "uncommon", min = 80, max = 100 },
    { file = "db/ancillaries_tables/jvj_kadon_generated_kinship.tsv", name = "rare", min = 130, max = 150 },
}

h.test("bind scrolls are uncommon and kin scrolls are rare", function()
    for _, range in ipairs(RARITY_RANGES) do
        local tsv = h.read_tsv(range.file)
        local col = column(tsv.header, "uniqueness_score")
        for _, row in ipairs(tsv.rows) do
            local score = tonumber(row[col])
            h.truthy(score and score >= range.min and score <= range.max, row[1] .. " score " .. tostring(row[col]) .. " is " .. range.name)
        end
    end
end)

h.test("every bind land unit has the unbinding passive", function()
    for _, stem in ipairs(BIND_STEMS) do
        local tsv = h.read_tsv("db/land_units_to_unit_abilites_junctions_tables/" .. stem .. ".tsv")
        local ability_col = column(tsv.header, "ability")
        local unit_col = column(tsv.header, "land_unit")
        local has_unbinding = {}
        for _, row in ipairs(tsv.rows) do
            if row[ability_col] == "kadon_bind_unbinding" then has_unbinding[row[unit_col]] = true end
            h.truthy(row[ability_col] ~= row[unit_col], row[unit_col] .. " must not carry its own summon ability")
        end
        local units = h.read_tsv("db/land_units_tables/" .. stem .. ".tsv")
        for _, row in ipairs(units.rows) do
            h.truthy(has_unbinding[row[1]], row[1] .. " has kadon_bind_unbinding")
        end
    end
end)

h.run()
