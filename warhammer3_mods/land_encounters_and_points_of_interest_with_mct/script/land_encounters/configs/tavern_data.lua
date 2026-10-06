--- Tavern data: the level table. Taverns stand at the entries of `points_of_interest.<zone>.taverns` in configs/coordinates.lua:
--- `{ coordinates = {x, y}, culture = "<shorthand>" or nil, initial_owner = "<faction>" or nil, owner_if_player = ... }`. An entry with a
--- culture is a racial Tavern, one without is neutral, and one without an owner starts unowned. The AI takeover chance and the subcultures that
--- never take a Tavern are shared with Smithies, in core/owned_point.lua.

local M = {}

--- What each level (index 1-3) costs to reach. `upgrade_price` is the gold the owner pays to go from this level to the next, or nil at the
--- top level. Stock, contracts and drink strength by level come with the rooms in later phases.
M.levels = {
    { upgrade_price = 10000 },
    { upgrade_price = 20000 },
    { upgrade_price = nil },
}

return M
