--- Smithy data: the forge level table and the smithy missions per player subculture.

local M = {}

--- What each forge level (index 1-3) offers. Rarities are CA's ancillary rarities ("common", "uncommon", "rare").
--- - free_pick_rarities: the rarities of the free picks and of the tribute and AI items. Each item rolls one of them.
--- - commission: the paid option - `count` items of `rarities` for `price` gold.
--- - legendary_commission: an optional second paid option - one item from configs/legendary_items.lua for `price` gold.
--- - cooldown_offset: turns added to the MCT `smithy_cooldown` slider (the level 3 cooldown) after a free pick, before the next one.
--- - tribute_interval: turns between tribute items for a player owner.
--- - upgrade_price: gold to reach the next level, or nil at the top level.
M.levels = {
    {
        free_pick_rarities = { "common", "uncommon" },
        commission = { rarities = { "rare" }, count = 1, price = 5000 },
        cooldown_offset = 5,
        tribute_interval = 15,
        upgrade_price = 10000,
    },
    {
        free_pick_rarities = { "uncommon", "rare" },
        commission = { rarities = { "rare" }, count = 1, price = 10000 },
        cooldown_offset = 2,
        tribute_interval = 10,
        upgrade_price = 20000,
    },
    {
        free_pick_rarities = { "rare" },
        commission = { rarities = { "rare" }, count = 2, price = 15000 },
        legendary_commission = { price = 20000 },
        cooldown_offset = 0,
        tribute_interval = 5,
        upgrade_price = nil,
    },
}

--- The Generous Donations a faction can make to the Smiths' Association at its own Smithy's forge, in order: its `price`, the `place_level`
--- every Smithy rises to, and the faction `bundle` it keeps for good (replacing the last donation's). See features/guild_patron.lua.
M.donations = {
    { price = 50000, place_level = 2, bundle = "land_enc_effect_smithy_patron_1" },
    { price = 100000, place_level = 3, bundle = "land_enc_effect_smithy_patron_2" },
}

--- Maximum of the MCT `smithy_cooldown` slider (the level 3 cooldown).
M.cooldown_slider_max = 30

--- Turns between the item an AI owner gets from its smithy.
M.ai_item_interval = 10

--- PLAYER ONLY. Each mission gives a set or one of the useful racial items given certain conditions are met. Only X (1/2/3) missions can be active given smithy level at a time per faction.
M.missions_by_subculture = {
    --- WH1
    --- Dwarfs
    ["wh_main_sc_dwf_dwarfs"] = {
    },
    --- Greenskins
    ["wh_main_sc_grn_greenskins"] = {
    },
    --- The Empire
    ["wh_main_sc_emp_empire"] = {

    },
    --- Vampire Counts
    ["wh_main_sc_vmp_vampire_counts"] = {
    },
    --- Warriors of Chaos
    ["wh_main_sc_chs_chaos"] = {

    },
    --- Beastmen
    ["wh_dlc03_sc_bst_beastmen"] = {

    },
    --- Bretonnia
    ["wh_main_sc_brt_bretonnia"] = {

    },
    --- Wood Elves
    ["wh_dlc05_sc_wef_wood_elves"] = {

    },
    --- Norsca
    ["wh_dlc08_sc_nor_norsca"] = {

    },

    --- WH2
    --- Dark Elves
    ["wh2_main_sc_def_dark_elves"] = {
        [1] = {
            mission = "land_enc_mission_smithy_dark_elves_armour_of_living_death",
            ancillaries = { "wh2_main_anc_armour_armour_of_living_death" }
        },

        [2] = {
            mission = "land_enc_mission_smithy_dark_elves_armour_armour_of_eternal_servitude",
            ancillaries = { "wh2_main_anc_armour_armour_of_eternal_servitude" }
        },

        [3] = {
            mission = "land_enc_mission_smithy_dark_elves_anc_weapon_chillblade",
            ancillaries = { "wh2_main_anc_weapon_chillblade" }
        }
    },
    --- High Elves
    ["wh2_main_sc_hef_high_elves"] = {

    },
    --- Lizardmen
    ["wh2_main_sc_lzd_lizardmen"] = {
    },
    --- Skaven
    ["wh2_main_sc_skv_skaven"] = {

    },
    --- Tomb Kings
    ["wh2_dlc09_sc_tmb_tomb_kings"] = {
    },
    --- Vampire Coast
    ["wh2_dlc11_sc_cst_vampire_coast"] = {
    },

    --- WH3
    --- Kislev
    ["wh3_main_sc_ksl_kislev"] = {
    },

    --- Daemons
    ["wh3_main_sc_dae_daemons"] = {
    },

    --- Cathay
    ["wh3_main_sc_cth_cathay"] = {
    },

    --- Ogre Kingdoms
    ["wh3_main_sc_ogr_ogre_kingdoms"] = {
    },

    --- Nurgle
    ["wh3_main_sc_nur_nurgle"] = {
    },

    --- Khorne
    ["wh3_main_sc_kho_khorne"] = {
    },

    --- Slaanesh
    ["wh3_main_sc_sla_slaanesh"] = {

    },

    --- Tzeentch
    ["wh3_main_sc_tze_tzeentch"] = {

    }

}

return M
