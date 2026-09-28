--- Checks the DB edits the script-owned drops depend on.

local h = require("tests/helpers")

--- Both scroll ancillary tables.
local ANCILLARY_TSVS = {
    "db/ancillaries_tables/jvj_kadon_binding.tsv",
    "db/ancillaries_tables/jvj_kadon_kinship.tsv",
}

--- Binding land-unit-to-ability junctions.
local BIND_JUNCTIONS_TSV = "db/land_units_to_unit_abilites_junctions_tables/jvj_kadon_binding.tsv"

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
    h.eq(total, 91, "scroll count")
end)

h.test("every bind land unit has the unbinding passive", function()
    local tsv = h.read_tsv(BIND_JUNCTIONS_TSV)
    local ability_col = column(tsv.header, "ability")
    local unit_col = column(tsv.header, "land_unit")
    local has_unbinding = {}
    for _, row in ipairs(tsv.rows) do
        if row[ability_col] == "kadon_bind_unbinding" then has_unbinding[row[unit_col]] = true end
        h.truthy(row[ability_col] ~= row[unit_col], row[unit_col] .. " must not carry its own summon ability")
    end
    local units = h.read_tsv("db/land_units_tables/jvj_kadon_binding.tsv")
    for _, row in ipairs(units.rows) do
        h.truthy(has_unbinding[row[1]], row[1] .. " has kadon_bind_unbinding")
    end
end)

h.run()
