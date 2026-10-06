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

--- Each level (index 1-3). `upgrade_price` is the gold the owner pays to go from this level to the next, or nil at the top level. `hall` is
--- the mercenary hall's stock: `units` regular units of `tiers`, `renown` Regiments of Renown as { min, max }, a hero of `hero_rank` for
--- `hero_price` gold before the hall's markup (none when nil), and `own` slots of the visitor's own culture, rolled for each visit.
--- Contracts by level come with the contract board in a later phase.
M.levels = {
    { upgrade_price = 10000, hall = { units = 4, tiers = { 1, 2 }, renown = { 0, 0 }, own = 1 } },
    { upgrade_price = 20000, hall = { units = 6, tiers = { 1, 2, 3 }, renown = { 1, 1 }, hero_rank = 5, hero_price = 2000, own = 1 } },
    { upgrade_price = nil, hall = { units = 8, tiers = { 1, 2, 3, 4 }, renown = { 1, 2 }, hero_rank = 10, hero_price = 3500, own = 2 } },
}

return M
