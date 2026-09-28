--- Creature data for Kadon's Scrolls. Each entry maps one creature to its Kin and Binding scroll keys, and is the source of the MCT creature
--- toggles and the scroll picker's pool.

local scroll_dlc = require("script/jvj_kadon/scroll_dlc")

local M = {}

--- Builds one creature entry. Kin and Bind keys default to `kadon_kin_<id>` and `kadon_bind_<id>`.
--- @param id string Creature id. Also used in the MCT option key `creature_<id>`.
--- @param name string Display name shown in MCT.
--- @param game string Where the creature comes from: "Original" for the mod's own custom units, otherwise "WH1", "WH2" or "WH3".
--- @param kin table|nil Kin scroll keys, when they differ from the default.
--- @param bind table|nil Binding scroll keys, when they differ from the default.
--- @returns table The creature entry.
local function creature(id, name, game, kin, bind)
    return { id = id, name = name, game = game, kin = kin or { "kadon_kin_" .. id }, bind = bind or { "kadon_bind_" .. id } }
end

--- Every creature with a scroll: the hand-made ones sorted by id, then the generated ones from `creatures_generated.lua`.
M.list = {
    creature("arcane_phoenix", "Arcane Phoenix", "WH2"),
    creature("bastiladon", "Bastiladon", "WH2"),
    creature("black_dragon", "Black Dragon", "WH2", { "kadon_kin_def_black_dragon" }),
    creature("carnosaur", "Carnosaur", "WH2"),
    creature("chaos_dragon", "Chaos Dragon", "Original"),
    creature("chaos_spawn", "Chaos Spawn", "WH1"),
    creature("chaos_warhounds", "Chaos Warhounds", "WH1"),
    creature("chs_trolls", "Chaos Trolls", "WH1"),
    creature("cold_ones", "Cold Ones", "WH2"),
    creature("cygor", "Cygor", "WH1"),
    creature("dragon_ogre", "Dragon Ogre", "WH1"),
    creature("dread_saurian", "Dread Saurian", "WH2"),
    creature("fimir", "Fimir", "WH1"),
    creature("flamespyre_phoenix", "Flamespyre Phoenix", "WH2"),
    creature("forest_dragon", "Forest Dragon", "WH1"),
    creature("frost_wyrm", "Frost Wyrm", "WH1"),
    creature("frostheart_phoenix", "Frostheart Phoenix", "WH2"),
    creature("giant", "Giant", "WH1", { "kadon_kin_giant", "kadon_kin_bst_giant", "kadon_kin_chs_giant", "kadon_kin_nor_giant" }),
    creature("great_cave_squigs", "Great Cave Squigs", "Original"),
    creature("great_eagle", "Great Eagle", "WH1"),
    creature("griffon", "Griffon", "Original"),
    creature("harpies", "Harpies", "WH1"),
    creature("hydra", "Hydra", "WH2"),
    creature("kharibdyss", "Kharibdyss", "WH2"),
    creature("manticore", "Manticore", "WH1"),
    creature("moon_dragon", "Moon Dragon", "WH2", { "kadon_kin_hef_moon_dragon" }),
    creature("mourngul", "Mourngul", "WH2"),
    creature("necrofex_colossus", "Necrofex Colossus", "WH2"),
    creature("nor_ice_trolls", "Norscan Ice Trolls", "WH1"),
    creature("razorgor", "Razorgor Herd", "WH1"),
    creature("ripperdactyls", "Ripperdactyls", "Original"),
    creature("rogue_idol", "Rogue Idol", "WH2"),
    creature("skinwolves", "Skinwolves", "WH1"),
    creature("spiders", "Giant Spiders", "WH2"),
    creature("stag", "Great Stags", "Original"),
    creature("star_dragon", "Star Dragon", "WH2", { "kadon_kin_hef_star_dragon" }),
    creature("stegadon", "Stegadon", "WH2"),
    creature("sun_dragon", "Sun Dragon", "WH2"),
    creature("terradons", "Terradons", "Original"),
    creature("trolls", "Trolls", "WH1"),
    creature("unicorn", "Unicorns", "Original"),
    creature("war_lions_of_chrace", "War Lions of Chrace", "WH2"),
    creature("war_mammoth", "War Mammoth", "WH1"),
    creature("wyvern", "Wyvern", "WH2"),
}

for _, entry in ipairs(require("script/jvj_kadon/creatures_generated")) do
    table.insert(M.list, creature(entry.id, entry.name, entry.game))
end

--- Marks a creature as DLC when every one of its scrolls needs paid DLC. A creature with any free scroll, like the Giant, is not DLC.
for _, entry in ipairs(M.list) do
    entry.dlc = true
    for _, list in ipairs({ entry.kin, entry.bind }) do
        for _, key in ipairs(list) do
            if not scroll_dlc[key] then entry.dlc = false end
        end
    end
end

--- Returns the MCT label of a creature: its display name followed by its game tag, e.g. "Carnosaur (WH2)" or "Coatl (WH2 DLC)".
--- @param entry table Creature entry from `list`.
--- @returns string The label.
function M.label(entry)
    return entry.name .. " (" .. entry.game .. (entry.dlc and " DLC" or "") .. ")"
end

--- Returns the creature with the given id.
--- @param id string|nil Creature id.
--- @returns table|nil The creature entry, or nil when no creature has that id.
function M.find(id)
    for _, entry in ipairs(M.list) do
        if entry.id == id then return entry end
    end
    return nil
end

return M
