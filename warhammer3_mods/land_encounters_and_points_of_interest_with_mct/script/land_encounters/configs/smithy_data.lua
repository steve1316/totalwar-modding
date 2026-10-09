--- Smithy data: the forge level table and the smithy missions per player subculture.

local tiered = require("script/land_encounters/utils/steps").tiered

local M = {}

--- What each forge level (index 1-3) offers. Rarities are CA's ancillary rarities ("common", "uncommon", "rare").
--- - free_pick_rarities: the rarities of the free picks and of the tribute and AI items. Each item rolls one of them.
--- - commission: the paid option - `count` items of `rarities` for `price` gold.
--- - legendary_commission: an optional second paid option - one item from configs/legendary_items.lua for `price` gold.
--- - cooldown_offset: turns added to the MCT `smithy_cooldown` slider (the level 3 cooldown) after a free pick, before the next one.
--- - tribute_interval: turns between tribute items for a player owner.
--- - legendary_tribute_chance: percent chance a player's tribute is a legendary item instead (Master's Mark), or nil for none.
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
        legendary_tribute_chance = 20,
        upgrade_price = nil,
    },
}

--- The Generous Donations a faction can make to the Smiths' Association at its own Smithy's forge, in order: its `price`, the `place_level`
--- every Smithy rises to, and the faction `bundle` it keeps for good (replacing the last donation's). See features/guild_patron.lua.
M.donations = {
    { price = 50000, place_level = 2, bundle = "land_enc_effect_smithy_patron_1" },
    { price = 100000, place_level = 3, bundle = "land_enc_effect_smithy_patron_2" },
}

--- The owner's perks, on while a player holds both the Smithy and its region, at the forge level: `arms_trade` raises the income of the
--- province, and `armoury` hardens the region's garrison. Each is a tiered bundle, whose `steps[level]` is its version for that forge level.
M.perks = {
    arms_trade = tiered("land_enc_effect_spot_smithy_arms_trade"),
    armoury = tiered("land_enc_effect_spot_smithy_armoury"),
}

--- The Work Orders counter on the forge: 3 offers drawn from the `smithy` pool (configs/spot_offers.lua), acting at the forge level. Taking
--- one closes the counter to that faction at that Smithy for `orders_cooldown` turns.
M.orders_cooldown = 5

--- Rush the Forge, shown while the free picks cool: it ends the cooldown for `rush_price_per_turn` gold per turn left, times the forge level.
M.rush_price_per_turn = 500

--- Maximum of the MCT `smithy_cooldown` slider (the level 3 cooldown).
M.cooldown_slider_max = 30

--- Turns between the item an AI owner gets from its smithy.
M.ai_item_interval = 10

--- Smith's Commissions (features/smithy_commissions.lua). A player faction holds at most one. While it holds none, its highest-level Smithy
--- offers one on every turn that is a multiple of the MCT `smithy_mission_interval`. Each is a mission named `mission_prefix` and its kind,
--- issued by `issuer`. Its reward is rolled when it is issued: a legendary item `legendary_chance` percent of the time, else an item of the
--- level's `reward_rarities`. By level, Blood the Steel asks for `kills` kills and Test the Steel for `armies` beaten armies of the nearest
--- enemy. Fetch Star-Metal's mark appears within `spawn_regions_away` regions of the Smithy, as far as `spawn_distance` from that region's
--- settlement. Each kind gives `turns` turns. Failing one costs nothing.
M.commissions = {
    mission_prefix = "land_enc_mission_smithy_",
    issuer = "CLAN_ELDERS",
    spawn_regions_away = 1,
    spawn_distance = 100,
    levels = {
        { reward_rarities = { "uncommon" }, legendary_chance = 0, kills = 2500, armies = 1 },
        { reward_rarities = { "rare" }, legendary_chance = 0, kills = 5000, armies = 2 },
        { reward_rarities = { "rare" }, legendary_chance = 25, kills = 7500, armies = 3 },
    },
    kinds = {
        { key = "blood_the_steel", turns = 10 },
        { key = "test_the_steel", turns = 15 },
        { key = "fetch_star_metal", turns = 10 },
    },
    --- Subculture -> its named items. Blood the Steel for that subculture pays one of them, on its own mission, instead of a rolled reward.
    named = {
        ["wh2_main_sc_def_dark_elves"] = {
            { mission = "land_enc_mission_smithy_dark_elves_armour_of_living_death", ancillary = "wh2_main_anc_armour_armour_of_living_death" },
            { mission = "land_enc_mission_smithy_dark_elves_armour_armour_of_eternal_servitude", ancillary = "wh2_main_anc_armour_armour_of_eternal_servitude" },
            { mission = "land_enc_mission_smithy_dark_elves_anc_weapon_chillblade", ancillary = "wh2_main_anc_weapon_chillblade" },
        },
    },
}

return M
