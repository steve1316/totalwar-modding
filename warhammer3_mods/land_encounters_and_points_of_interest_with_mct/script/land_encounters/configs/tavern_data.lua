--- Tavern data: the level table. Taverns stand at the entries of `points_of_interest.<zone>.taverns` in configs/coordinates.lua:
--- `{ coordinates = {x, y}, culture = "<shorthand>" or nil, initial_owner = "<faction>" or nil, owner_if_player = ... }`. An entry with a
--- culture is a racial Tavern, one without is neutral, and one without an owner starts unowned. The AI takeover chance and the subcultures that
--- never take a Tavern are shared with Smithies, in core/owned_point.lua.

local M = {}

--- Share of a bar offer's price the Tavern's owner pays. Guests pay the full price.
M.owner_price_share = 0.75

--- Turns the bar stays closed to a faction after it takes an offer there.
M.bar_cooldown = 5

--- The mercenary hall. Its stock is shared by every visitor and rolled again `restock_turns` after it was last rolled, or at once when the
--- Tavern levels up. A racial Tavern stocks its own culture, a neutral one `neutral_cultures` random cultures. A hire costs the unit's
--- recruitment cost plus `price_markup` gold, for every visitor. A faction hires at most `hires_per_visit` per visit, and its first hire
--- closes the hall to it for `cooldown` turns.
M.hall = {
    restock_turns = 5,
    neutral_cultures = 2,
    price_markup = 1000,
    hires_per_visit = 2,
    cooldown = 5,
}

--- The contract board. Every Tavern belongs to the Tavern Keepers' Guild. Each shows `board_size` contracts, rolled again `restock_turns`
--- after they were last rolled, and taking one removes it for every visitor. A faction holds at most `max_held` contracts at once across
--- every Tavern. Taking one pays its deposit. Success returns the deposit with the reward. Failing or dropping one (from the missions panel)
--- loses the deposit, and every Guild Tavern then charges that faction `standing_surcharge` more for `standing_turns` turns. A bounty lord
--- spawns at most `bounty_regions_away` regions from the Tavern and patrols there.
M.contracts = {
    board_size = 2,
    restock_turns = 5,
    max_held = 3,
    standing_surcharge = 0.25,
    standing_turns = 10,
    bounty_regions_away = 2,
    bounty_turns = 10,
    cull_turns = 15,
}

--- Each level (index 1-3). `upgrade_price` is the gold the owner pays to go from this level to the next, or nil at the top level. `hall` is
--- the mercenary hall's stock: `units` regular units of `tiers`, `renown` Regiments of Renown as { min, max }, a hero of `hero_rank` for
--- `hero_price` gold before the hall's markup (none when nil), and `own` slots of the visitor's own culture, rolled for each visit.
--- `contracts` is the board at this level: the `deposit`, an item of `item_rarities` with each reward, a bounty's `bounty_gold` reward, and a
--- cull's `cull_gold` reward for beating `cull_armies` armies. A bounty lord's army is as hard as a battle spot at the Tavern's level.
M.levels = {
    { upgrade_price = 10000, hall = { units = 4, tiers = { 1, 2 }, renown = { 0, 0 }, own = 1 },
        contracts = { deposit = 1000, item_rarities = { "uncommon" }, bounty_gold = 2000, cull_gold = 1500, cull_armies = 2 } },
    { upgrade_price = 20000, hall = { units = 6, tiers = { 1, 2, 3 }, renown = { 1, 1 }, hero_rank = 5, hero_price = 2000, own = 1 },
        contracts = { deposit = 2000, item_rarities = { "rare" }, bounty_gold = 3500, cull_gold = 3000, cull_armies = 3 } },
    { upgrade_price = nil, hall = { units = 8, tiers = { 1, 2, 3, 4 }, renown = { 1, 2 }, hero_rank = 10, hero_price = 3500, own = 2 },
        contracts = { deposit = 3000, item_rarities = { "rare" }, bounty_gold = 5000, cull_gold = 4500, cull_armies = 4 } },
}

return M
