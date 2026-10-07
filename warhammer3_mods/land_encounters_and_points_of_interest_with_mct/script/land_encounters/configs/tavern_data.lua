--- Tavern data: the level table. Taverns stand at the entries of `points_of_interest.<zone>.taverns` in configs/coordinates.lua:
--- `{ coordinates = {x, y}, culture = "<shorthand>" or nil, initial_owner = "<faction>" or nil, owner_if_player = ... }`. An entry with a
--- culture is a racial Tavern, one without is neutral, and one without an owner starts unowned. The AI takeover chance and the subcultures that
--- never take a Tavern are shared with Smithies, in core/owned_point.lua.

local M = {}

--- The hub's opening scene, picked on each visit from text/db/land_enc_and_poi_tavern_strings.loc.tsv: one of `scenes_per_level` scenes for
--- the Tavern's level, and `moment_chance` percent of the time one of `moments` things happening tonight. The keeper then answers what was
--- just described: tonight's moment when there is one, else one of `owner_greetings` lines for the owner, else the scene's own line.
--- `clashes` lists, by scene, the moments that would repeat or contradict it, which that scene never shows.
M.flavour = {
    scenes_per_level = 4,
    moments = 8,
    moment_chance = 35,
    owner_greetings = 3,
    --- 1_1: the storyteller by the fire and the old veteran telling his tale. 2_2: the full benches of caravan drivers trading road news,
    --- and the caravan that just came in or the wedding filling the room. 3_3: the keeper pouring from the ancient barrel, and the good
    --- barrel drunk dry. 3_4: the envoys at the one long table, and the wedding party that has taken it over.
    clashes = {
        ["1_1"] = { [7] = true },
        ["2_2"] = { [4] = true, [5] = true },
        ["3_3"] = { [3] = true },
        ["3_4"] = { [5] = true },
    },
}

--- Share of a bar offer's price the Tavern's owner pays. Guests pay the full price.
M.owner_price_share = 0.75

--- The mercenary hall. Its stock is shared by every visitor and rolled again the MCT `tavern_hall_restock` turns after it was last rolled, or at once when the
--- Tavern levels up. A racial Tavern stocks its own culture, a neutral one `neutral_cultures` random cultures. A hire costs the unit's
--- recruitment cost plus the MCT `tavern_hire_markup` gold, and `renown_extra` more for a Regiment of Renown, for every visitor. A faction
--- hires at most the MCT `tavern_hires_per_visit` per visit, and its first hire closes the hall to it for the MCT `tavern_cooldown` turns.
M.hall = {
    neutral_cultures = 2,
    renown_extra = 1500,
}

--- The contract board. Every Tavern belongs to the Tavern Keepers' Guild. Each shows `board_size` contracts of different kinds, rolled again
--- `restock_turns` after they were last rolled, and taking one removes it for every visitor. A faction holds at most `max_held` contracts at once across
--- every Tavern. Taking one pays its deposit. Success returns the deposit with the reward. Failing or dropping one (from the missions panel)
--- loses the deposit, and every Guild Tavern then charges that faction the MCT `tavern_penalty_percent` more for `tavern_penalty_turns`. A bounty lord
--- or a marked spot appears at most `spawn_regions_away` regions from the Tavern, as far as `spawn_distance` from that region's settlement as
--- the land allows. A level 3 Tavern also posts a quest chain: its `steps` in
--- order (a hunt, a marked spot, then a boss hunt), each against an enemy of its `difficulty`, paying its `gold` and an item of its
--- `item_rarities`. The last step pays the deposit back with a legendary item, or frees a hero of `hero_rank` when none is left.
M.contracts = {
    board_size = 2,
    restock_turns = 5,
    max_held = 1,
    spawn_regions_away = 1,
    spawn_distance = 100,
    --- Turns a cull gets on top of the MCT `tavern_contract_turns` deadline, since it needs several armies beaten.
    cull_extra_turns = 5,
    chain = {
        deposit = 4000,
        --- Turns each quest step gets on top of the MCT `tavern_contract_turns` deadline.
        step_extra_turns = 2,
        hero_rank = 15,
        steps = {
            { kind = "bounty", difficulty = "medium", gold = 2000, item_rarities = { "rare" } },
            { kind = "marked", difficulty = "hard", gold = 3500, item_rarities = { "rare" } },
            { kind = "bounty", difficulty = "hard", gold = 6000 },
        },
    },
}

--- The Generous Donations a faction can make to the Tavern Keepers' Guild at any Tavern's hub, in order: its `price`, the `place_level`
--- every Tavern rises to, and the faction `bundle` it keeps for good (replacing the last donation's), whose effects include experience for
--- every lord and hero each turn. A donor no longer pays the Guild's surcharge after a failed or dropped contract (see
--- features/guild_patron.lua).
M.donations = {
    { price = 50000, place_level = 2, bundle = "land_enc_effect_tavern_patron_1" },
    { price = 100000, place_level = 3, bundle = "land_enc_effect_tavern_patron_2" },
}

--- Each level (index 1-3). `upgrade_price` is the gold the owner pays to go from this level to the next, or nil at the top level. `hall` is
--- the mercenary hall's stock: `units` regular units of `tiers`, `renown` Regiments of Renown as { min, max }, a hero of `hero_rank` for
--- `hero_price` gold before the hall's markup (none when nil), and `own` slots of the visitor's own culture, rolled for each visit.
--- `contracts` is the board at this level: the `deposit`, an item of `item_rarities` with each reward, a bounty's `bounty_gold` reward, a
--- cull's `cull_gold` reward for beating `cull_armies` armies, a marked spot's `marked_gold` reward, and `chain` when it posts a quest chain.
--- A bounty lord's army, and a marked spot's, is as hard as a battle spot at the Tavern's level.
M.levels = {
    { upgrade_price = 10000, hall = { units = 3, tiers = { 1, 2 }, renown = { 0, 0 }, own = 1 },
        contracts = { deposit = 1000, item_rarities = { "uncommon" }, bounty_gold = 2000, cull_gold = 1500, cull_armies = 2,
            marked_gold = 1500 } },
    { upgrade_price = 20000, hall = { units = 4, tiers = { 1, 2, 3 }, renown = { 1, 1 }, hero_rank = 5, hero_price = 2000, own = 1 },
        contracts = { deposit = 2000, item_rarities = { "rare" }, bounty_gold = 3500, cull_gold = 3000, cull_armies = 3,
            marked_gold = 3000 } },
    { upgrade_price = nil, hall = { units = 5, tiers = { 1, 2, 3, 4 }, renown = { 1, 2 }, hero_rank = 10, hero_price = 3500, own = 2 },
        contracts = { deposit = 3000, item_rarities = { "rare" }, bounty_gold = 5000, cull_gold = 4500, cull_armies = 4,
            marked_gold = 4500, chain = true } },
}

return M
