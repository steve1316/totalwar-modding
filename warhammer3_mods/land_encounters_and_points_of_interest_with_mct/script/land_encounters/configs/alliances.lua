-- Two faction pools (Order and Destruction) and a player-subculture -> pool map. Used by the
-- Allied Reinforcement intervention to pick a random allied faction that spawns alongside the
-- player during a random-encounter battle.
--
-- Pool entries use the 3-letter SHORTHAND keys from core/managers.lua's
-- faction_shorthand_key_to_full_key (emp, brt, dwf, etc.) - the same shorthand returned by
-- get_random_faction() for enemy forces. start_force_makeup_generation and
-- convert_force_makeup_to_usable_format both consume shorthand keys directly.
--
-- random_number() is a global published by utils/random; pick_for_subculture is only called from
-- core/army.lua, which requires utils/random at module-load, so the global is in _G by call time.

local M = {}

-- Order pool: factions that ally with "good" subcultures.
M.order_factions = {
    "emp", -- Empire
    "brt", -- Bretonnia
    "dwf", -- Dwarfs
    "hef", -- High Elves
    "lzd", -- Lizardmen
    "wef", -- Wood Elves
    "ksl", -- Kislev
    "cth", -- Cathay
}

-- Destruction pool: factions that ally with "evil" subcultures.
M.destruction_factions = {
    "grn", -- Greenskins
    "nor", -- Norsca
    "chs", -- Warriors of Chaos
    "vmp", -- Vampire Counts
    "bst", -- Beastmen
    "kho", -- Khorne
    "tze", -- Tzeentch
    "nur", -- Nurgle
    "sla", -- Slaanesh
    "chd", -- Chaos Dwarfs
    "ogr", -- Ogre Kingdoms
    "def", -- Dark Elves
    "skv", -- Skaven
    "cst", -- Vampire Coast
    "tmb", -- Tomb Kings
}

-- Player subculture -> pool name. Unmapped subcultures fall through to the union pool (any faction).
M.subculture_to_pool = {
    -- Order
    ["wh_main_sc_emp_empire"]            = "order",
    ["wh_main_sc_brt_bretonnia"]         = "order",
    ["wh_main_sc_dwf_dwarfs"]            = "order",
    ["wh2_main_sc_hef_high_elves"]       = "order",
    ["wh2_main_sc_lzd_lizardmen"]        = "order",
    ["wh_dlc05_sc_wef_wood_elves"]       = "order",
    ["wh3_main_sc_cth_cathay"]           = "order",
    ["wh3_main_sc_ksl_kislev"]           = "order",
    -- Destruction
    ["wh_main_sc_grn_greenskins"]        = "destruction",
    ["wh_main_sc_nor_norsca"]            = "destruction",
    ["wh_main_sc_chs_chaos"]             = "destruction",
    ["wh3_main_sc_kho_khorne"]           = "destruction",
    ["wh3_main_sc_tze_tzeentch"]         = "destruction",
    ["wh3_main_sc_nur_nurgle"]           = "destruction",
    ["wh3_main_sc_sla_slaanesh"]         = "destruction",
    ["wh3_main_sc_chd_chaos_dwarfs"]     = "destruction",
    ["wh3_main_sc_ogr_ogre_kingdoms"]    = "destruction",
    ["wh_dlc03_sc_bst_beastmen"]         = "destruction",
    ["wh_main_sc_vmp_vampire_counts"]    = "destruction",
    ["wh2_dlc11_sc_cst_vampire_coast"]   = "destruction",
    ["wh2_main_sc_def_dark_elves"]       = "destruction",
    ["wh2_main_sc_skv_skaven"]           = "destruction",
    ["wh2_main_sc_tmb_tomb_kings"]       = "destruction",
}

-- Picks a random ally faction shorthand key for the given player subculture.
-- Returns nil only if both pools are empty (defensive guard; should never happen in normal use).
function M.pick_for_subculture(player_subculture)
    local pool_name = M.subculture_to_pool[player_subculture]
    local pool
    if pool_name == "order" then
        pool = M.order_factions
    elseif pool_name == "destruction" then
        pool = M.destruction_factions
    else
        pool = {}
        for _, faction in ipairs(M.order_factions) do table.insert(pool, faction) end
        for _, faction in ipairs(M.destruction_factions) do table.insert(pool, faction) end
    end
    if #pool == 0 then return nil end
    return pool[random_number(#pool)]
end

return M
