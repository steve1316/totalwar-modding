--- Battle categories for battle spots. Pure data - no runtime logic.
--- Each category gives its battles an army style, a budget multiplier, a minimum difficulty and a battle type, and lists its dilemmas.
--- A battle is either flavoured (a dilemma written for one faction, which then spawns that faction) or neutral (a faction-free dilemma for a
--- random enabled faction). Adding a dilemma or incident needs matching DB rows and .loc text (see `configs/events.lua`).

local M = {}

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Rarity

--- Weight of each tier (index 1-4) per difficulty. Categories that share a tier split its weight equally.
M.tier_weights = {
    easy = { 50, 35, 12, 3 },
    medium = { 30, 40, 20, 10 },
    hard = { 15, 35, 30, 20 },
}

--- Percent chance that a category with a neutral dilemma uses one of its flavoured dilemmas instead.
M.flavoured_chance = 50

--- Percent chance that winning a battle on hard difficulty also grants one item from configs/legendary_items.lua.
M.hard_legendary_chance = 5

--- Gold an Ally in Peril win pays per step of `ally.relations` when no faction of the ally's culture is near and at peace with us.
M.ally_relations_gold = 500

--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- //////////////////////////////////////////////////////////////////////////////////////////////////
--- Categories

--[[
Fields of each category:
- key / text: id and display name.
- guide: one short line for the MCT Encounters page guide. The rest of the guide line is built from the fields below.
- tier: rarity tier, 1 (common) to 4 (rare). See `tier_weights`.
- archetypes: army archetype keys the generator should use (configs/archetypes.lua). It falls back when none are enabled or fieldable.
- budget_multiplier: scales the difficulty's gold budget.
- min_difficulty: the lowest difficulty the battle uses, or nil.
- intervention: "ambush", "interception" or "allied" to force a battle type, or nil for the MCT pick. A forced type the user turned off
  falls back to Interception, then to the MCT pick.
- victory_incident / avoidance_incident: shared incidents. A flavoured entry may override either.
- victory_targets / avoidance_targets: who each incident targets.
- victory_items: the item a victory grants at runtime (`count` items of `rarities`), or nil for none. The victory incident itself only
  carries gold and buffs.
- ally: makes the category an Ally in Peril battle, which always has an allied army and only fires while the MCT allows allied battles.
  `mode` "beside" (we attack and the ally marches in to join us) or "relief" (the ally holds the field, the enemy charges it and we march in as
  its reinforcement), `units` (the ally's units, its lord included, or nil for a full army), `strengths` (the share of full strength the ally
  starts at, one picked at random), `relations` (dilemma steps of relations, 10 each, with the nearest real faction of the ally's culture on
  a win) and `gift_unit` (a random surviving allied unit joins us on a win).
- neutral: the faction-free dilemma, or nil when the category only has flavoured dilemmas.
- flavoured: dilemmas written for one faction (3-letter shorthand).
--]]
M.list = {
    {
        key = "skirmish",
        victory_items = { rarities = { "common", "uncommon" }, count = 1 },
        text = "Skirmish",
        guide = "A small band blocks the road.",
        tier = 1,
        archetypes = { "battle_line" },
        budget_multiplier = 0.6,
        min_difficulty = nil,
        intervention = "interception",
        victory_incident = "land_enc_incident_battle_won_skirmish",
        avoidance_incident = "land_enc_incident_battle_avoided_skirmish",
        victory_targets = { character = true, force = false, faction = false, region = false },
        avoidance_targets = { character = true, force = false, faction = false, region = false },
        neutral = { dilemma = "land_enc_dilemma_skirmish_neutral" },
        flavoured = {
            { faction = "cth", dilemma = "land_enc_dilemma_skirmish_cth" },
            { faction = "ksl", dilemma = "land_enc_dilemma_skirmish_kis" },
            { faction = "ogr", dilemma = "land_enc_dilemma_skirmish_ogr" },
            { faction = "nur", dilemma = "land_enc_dilemma_skirmish_nur" },
            { faction = "tze", dilemma = "land_enc_dilemma_skirmish_tze" },
        },
    },
    {
        key = "underground",
        text = "Nascent Rebellion",
        guide = "Rebels gather in hiding and strike from ambush.",
        tier = 1,
        archetypes = { "horde" },
        budget_multiplier = 0.8,
        min_difficulty = nil,
        intervention = "ambush",
        victory_incident = "land_enc_incident_battle_won_underground",
        avoidance_incident = "land_enc_incident_battle_avoided_underground",
        victory_targets = { character = true, force = false, faction = false, region = false },
        avoidance_targets = { character = true, force = false, faction = false, region = false },
        neutral = { dilemma = "land_enc_dilemma_underground_neutral" },
        flavoured = {
            { faction = "cth", dilemma = "land_enc_dilemma_underground_cth" },
            { faction = "ksl", dilemma = "land_enc_dilemma_underground_kis" },
            { faction = "ogr", dilemma = "land_enc_dilemma_underground_ogr" },
            { faction = "tze", dilemma = "land_enc_dilemma_underground_tze" },
        },
    },
    {
        key = "bandits",
        victory_items = { rarities = { "uncommon", "rare" }, count = 1 },
        text = "Bandits",
        guide = "Fast raiders prey on travellers.",
        tier = 2,
        archetypes = { "raiders" },
        budget_multiplier = 0.8,
        min_difficulty = nil,
        intervention = "interception",
        victory_incident = "land_enc_incident_battle_won_bandits",
        avoidance_incident = "land_enc_incident_battle_avoided_bandits",
        victory_targets = { character = true, force = false, faction = false, region = false },
        avoidance_targets = { character = true, force = false, faction = false, region = false },
        neutral = { dilemma = "land_enc_dilemma_bandits_neutral" },
        flavoured = {
            { faction = "emp", dilemma = "land_enc_dilemma_bandits_emp" },
            { faction = "wef", dilemma = "land_enc_dilemma_bandits_wef" },
            { faction = "nor", dilemma = "land_enc_dilemma_bandits_nor" },
            { faction = "chd", dilemma = "land_enc_dilemma_bandits_chads" },
        },
    },
    {
        key = "surprise_attack",
        text = "Surprise Attack",
        guide = "A horde or a pack of monsters springs an ambush.",
        tier = 2,
        archetypes = { "horde", "monster_hunt" },
        budget_multiplier = 1.0,
        min_difficulty = nil,
        intervention = "ambush",
        victory_incident = "land_enc_incident_battle_won_surprise_neutral",
        avoidance_incident = "land_enc_incident_battle_avoided_surprise",
        victory_targets = { character = true, force = true, faction = false, region = false },
        avoidance_targets = { character = false, force = true, faction = false, region = false },
        neutral = { dilemma = "land_enc_dilemma_surprise_attack_neutral" },
        flavoured = {
            { faction = "bst", dilemma = "land_enc_dilemma_surprise_attack_bst", victory_incident = "land_enc_incident_battle_won_surprise_bst" },
            { faction = "skv", dilemma = "land_enc_dilemma_surprise_attack_skv", victory_incident = "land_enc_incident_battle_won_surprise_skv" },
        },
    },
    {
        key = "incursion",
        victory_items = { rarities = { "rare" }, count = 1 },
        text = "Incursion",
        guide = "An invading army digs in with artillery.",
        tier = 2,
        archetypes = { "siege", "battle_line" },
        budget_multiplier = 1.0,
        min_difficulty = nil,
        intervention = nil,
        victory_incident = "land_enc_incident_battle_won_incursion_neutral",
        avoidance_incident = "land_enc_incident_battle_avoided_incursion",
        victory_targets = { character = true, force = true, faction = false, region = false },
        avoidance_targets = { character = false, force = true, faction = false, region = false },
        neutral = { dilemma = "land_enc_dilemma_incursion_army_neutral" },
        flavoured = {
            { faction = "hef", dilemma = "land_enc_dilemma_incursion_army_hef", victory_incident = "land_enc_incident_battle_won_incursion_hef" },
            { faction = "lzd", dilemma = "land_enc_dilemma_incursion_army_lzd", victory_incident = "land_enc_incident_battle_won_incursion_lzd" },
            { faction = "cst", dilemma = "land_enc_dilemma_incursion_army_vco", victory_incident = "land_enc_incident_battle_won_incursion_vco" },
        },
    },
    {
        key = "battlefield",
        victory_items = { rarities = { "rare" }, count = 1 },
        text = "Battlefield",
        guide = "Two armies clash, and allies can join our side.",
        tier = 3,
        archetypes = { "battle_line" },
        budget_multiplier = 1.3,
        min_difficulty = "medium",
        intervention = "allied",
        victory_incident = "land_enc_incident_battle_won_battlefield_neutral",
        avoidance_incident = "land_enc_incident_battle_avoided_battlefield",
        victory_targets = { character = true, force = false, faction = false, region = false },
        avoidance_targets = { character = false, force = true, faction = false, region = false },
        neutral = { dilemma = "land_enc_dilemma_battlefield_neutral" },
        flavoured = {
            { faction = "grn", dilemma = "land_enc_dilemma_battlefield_grn", victory_incident = "land_enc_incident_battle_won_battlefield_grn" },
            { faction = "def", dilemma = "land_enc_dilemma_battlefield_def", victory_incident = "land_enc_incident_battle_won_battlefield_def" },
            { faction = "vmp", dilemma = "land_enc_dilemma_battlefield_vmp", victory_incident = "land_enc_incident_battle_won_battlefield_vmp" },
            { faction = "tmb", dilemma = "land_enc_dilemma_battlefield_tmb", victory_incident = "land_enc_incident_battle_won_battlefield_tmb" },
            { faction = "dwf", dilemma = "land_enc_dilemma_battlefield_dwf", victory_incident = "land_enc_incident_battle_won_battlefield_dwf" },
        },
    },
    {
        key = "daemonic_gift",
        text = "Daemonic Gift",
        guide = "A daemon's champion guards a gift of Khorne or Slaanesh.",
        tier = 4,
        archetypes = { "elite" },
        budget_multiplier = 1.3,
        min_difficulty = "hard",
        intervention = nil,
        victory_targets = { character = true, force = false, faction = false, region = false },
        avoidance_targets = { character = false, force = true, faction = false, region = false },
        neutral = nil,
        flavoured = {
            { faction = "kho", dilemma = "land_enc_dilemma_daemonic_gift_chainsword", victory_incident = "land_enc_incident_battle_won_daemonic_gift_chainsword", avoidance_incident = "land_enc_incident_battle_avoided_daemonic_gift_khorne" },
            { faction = "kho", dilemma = "land_enc_dilemma_daemonic_gift_the_bane_spear", victory_incident = "land_enc_incident_battle_won_daemonic_gift_the_bane_spear", avoidance_incident = "land_enc_incident_battle_avoided_daemonic_gift_khorne" },
            { faction = "kho", dilemma = "land_enc_dilemma_daemonic_gift_skars_kraken_killer", victory_incident = "land_enc_incident_battle_won_daemonic_gift_skars_kraken_killer", avoidance_incident = "land_enc_incident_battle_avoided_daemonic_gift_khorne" },
            { faction = "kho", dilemma = "land_enc_dilemma_daemonic_gift_gilellions_soulnetter", victory_incident = "land_enc_incident_battle_won_daemonic_gift_gilellions_soulnetter", avoidance_incident = "land_enc_incident_battle_avoided_daemonic_gift_khorne" },
            { faction = "sla", dilemma = "land_enc_dilemma_daemonic_gift_slaaneshs_blade", victory_incident = "land_enc_incident_battle_won_daemonic_gift_slaaneshs_blade", avoidance_incident = "land_enc_incident_battle_avoided_daemonic_gift_slaanesh" },
            { faction = "sla", dilemma = "land_enc_dilemma_daemonic_gift_personal_sycophant", victory_incident = "land_enc_incident_battle_won_daemonic_gift_personal_sycophant", avoidance_incident = "land_enc_incident_battle_avoided_daemonic_gift_slaanesh" },
            { faction = "sla", dilemma = "land_enc_dilemma_daemonic_gift_dark_princes_paramour", victory_incident = "land_enc_incident_battle_won_daemonic_gift_dark_princes_paramour", avoidance_incident = "land_enc_incident_battle_avoided_daemonic_gift_slaanesh" },
        },
    },
    {
        key = "ally_beset",
        text = "An Ally Beset",
        guide = "An allied army is attacked, and we can march to its side.",
        tier = 2,
        archetypes = { "battle_line" },
        budget_multiplier = 1.3,
        min_difficulty = nil,
        intervention = "allied",
        ally = { mode = "beside", relations = 2 },
        victory_incident = "land_enc_incident_battle_won_ally_beset",
        avoidance_incident = "land_enc_incident_battle_avoided_ally",
        victory_targets = { character = true, force = false, faction = false, region = false },
        avoidance_targets = { character = false, force = true, faction = false, region = false },
        neutral = { dilemma = "land_enc_dilemma_ally_beset" },
        flavoured = {},
    },
    {
        key = "turn_the_tables",
        victory_items = { rarities = { "uncommon", "rare" }, count = 1 },
        text = "Turn the Tables",
        guide = "Our allied escort spots an ambush, and we can strike first together.",
        tier = 2,
        archetypes = { "raiders" },
        budget_multiplier = 1.0,
        min_difficulty = nil,
        intervention = "allied",
        ally = { mode = "beside", units = 6, relations = 2 },
        victory_incident = "land_enc_incident_battle_won_turn_the_tables",
        avoidance_incident = "land_enc_incident_battle_avoided_ally",
        victory_targets = { character = true, force = false, faction = false, region = false },
        avoidance_targets = { character = false, force = true, faction = false, region = false },
        neutral = { dilemma = "land_enc_dilemma_turn_the_tables" },
        flavoured = {},
    },
    {
        key = "relief_column",
        text = "Relief Column",
        guide = "An allied army is overrun, and we must reach it before it breaks.",
        tier = 3,
        archetypes = { "horde" },
        budget_multiplier = 1.0,
        min_difficulty = nil,
        intervention = "allied",
        ally = { mode = "relief", strengths = { 0.5, 0.75, 1 }, gift_unit = true },
        victory_incident = "land_enc_incident_battle_won_relief_column",
        avoidance_incident = "land_enc_incident_battle_avoided_ally",
        victory_targets = { character = true, force = false, faction = false, region = false },
        avoidance_targets = { character = false, force = true, faction = false, region = false },
        neutral = { dilemma = "land_enc_dilemma_relief_column" },
        flavoured = {},
    },
}

--- Set of every battle-spot dilemma key (neutral and flavoured), built from `list`. Used to recognise battle dilemma choices.
M.dilemma_keys = {}

for _, category in ipairs(M.list) do
    if category.neutral then
        M.dilemma_keys[category.neutral.dilemma] = true
    end
    for _, entry in ipairs(category.flavoured) do
        M.dilemma_keys[entry.dilemma] = true
    end
end

return M
