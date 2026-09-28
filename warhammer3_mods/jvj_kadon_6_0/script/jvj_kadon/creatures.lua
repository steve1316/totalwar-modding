--- Creature data for Kadon's Scrolls. Each entry maps one creature to its Kin and Binding scroll keys, and is the source of the MCT creature
--- toggles and the scroll picker's pool.

local M = {}

--- Builds one creature entry. Kin and Bind keys default to `kadon_kin_<id>` and `kadon_bind_<id>`.
--- @param id string Creature id. Also used in the MCT option key `creature_<id>`.
--- @param name string Display name shown in MCT.
--- @param kin table|nil Kin scroll keys, when they differ from the default.
--- @param bind table|nil Binding scroll keys, when they differ from the default.
--- @returns table The creature entry.
local function creature(id, name, kin, bind)
    return { id = id, name = name, kin = kin or { "kadon_kin_" .. id }, bind = bind or { "kadon_bind_" .. id } }
end

--- Every creature with a scroll, sorted by id.
M.list = {
    creature("arcane_phoenix", "Arcane Phoenix"),
    creature("bastiladon", "Bastiladon"),
    creature("black_dragon", "Black Dragon", { "kadon_kin_def_black_dragon" }),
    creature("carnosaur", "Carnosaur"),
    creature("chaos_dragon", "Chaos Dragon"),
    creature("chaos_spawn", "Chaos Spawn"),
    creature("chaos_warhounds", "Chaos Warhounds"),
    creature("chs_trolls", "Chaos Trolls"),
    creature("cold_ones", "Cold Ones"),
    creature("cygor", "Cygor"),
    creature("dragon_ogre", "Dragon Ogre"),
    creature("dread_saurian", "Dread Saurian"),
    creature("fimir", "Fimir"),
    creature("flamespyre_phoenix", "Flamespyre Phoenix"),
    creature("forest_dragon", "Forest Dragon"),
    creature("frost_wyrm", "Frost Wyrm"),
    creature("frostheart_phoenix", "Frostheart Phoenix"),
    creature("giant", "Giant", { "kadon_kin_giant", "kadon_kin_bst_giant", "kadon_kin_chs_giant", "kadon_kin_nor_giant" }),
    creature("great_cave_squigs", "Great Cave Squigs"),
    creature("great_eagle", "Great Eagle"),
    creature("griffon", "Griffon"),
    creature("harpies", "Harpies"),
    creature("hydra", "Hydra"),
    creature("kharibdyss", "Kharibdyss"),
    creature("manticore", "Manticore"),
    creature("moon_dragon", "Moon Dragon", { "kadon_kin_hef_moon_dragon" }),
    creature("mourngul", "Mourngul"),
    creature("necrofex_colossus", "Necrofex Colossus"),
    creature("nor_ice_trolls", "Norscan Ice Trolls"),
    creature("razorgor", "Razorgor Herd"),
    creature("ripperdactyls", "Ripperdactyls"),
    creature("rogue_idol", "Rogue Idol"),
    creature("skinwolves", "Skinwolves"),
    creature("spiders", "Giant Spiders"),
    creature("stag", "Great Stags"),
    creature("star_dragon", "Star Dragon", { "kadon_kin_hef_star_dragon" }),
    creature("stegadon", "Stegadon"),
    creature("sun_dragon", "Sun Dragon"),
    creature("terradons", "Terradons"),
    creature("trolls", "Trolls"),
    creature("unicorn", "Unicorns"),
    creature("war_lions_of_chrace", "War Lions of Chrace"),
    creature("war_mammoth", "War Mammoth"),
    creature("wyvern", "Wyvern"),
}

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
