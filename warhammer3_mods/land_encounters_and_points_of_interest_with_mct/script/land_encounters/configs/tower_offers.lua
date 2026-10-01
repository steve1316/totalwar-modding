--- Tower offers: the roguelite choices drawn onto each go-deeper dilemma between Climb and Leave. Each record's choice key is
--- "LEAPOI_TWR_" plus its key in capitals, and its popup text is the `dummy_land_enc_tower_<key>` payload line. What each offer does, and when
--- it can be drawn, lives in features/tower_offers.lua.

local M = {}

--- Choice key of Leave on the per-floor go-deeper dilemmas. Its DB order is the highest, so Leave is always the last choice.
M.leave_choice_key = "LEAPOI_TWR_LEAVE"

--- Most offers drawn onto one go-deeper dilemma.
M.offers_per_floor = 4

--- Offer records in popup order. `cost` is gold taken from the haul (none means free). A `stay` offer reopens the same floor's dilemma
--- after it applies, and any other offer climbs to the next floor. A `repeatable` offer can be drawn again after it is taken. `next_budget`
--- and `next_gold` multiply the next floor's army budget and gold.
M.offers = {
    --- Heals `heal_share` of each unit's missing strength.
    { key = "tend_wounded", cost = 1000, repeatable = true, heal_share = 0.5 },
    --- Heals every unit to full.
    { key = "field_surgeons", cost = 2500, repeatable = true, heal_share = 1 },
    --- Heals `heal_share` of each unit's missing strength for free.
    { key = "forgotten_shrine", repeatable = true, heal_share = 0.3 },
    --- Heals the `count` most battered units to full, and the healthiest other unit loses `penalty` strength points.
    { key = "triage", repeatable = true, count = 3, penalty = 20 },
    --- Heals `heal_share` of each unit's missing strength, then drains the army with `effect_bundle` for `turns` turns.
    { key = "blood_transfusion", repeatable = true, heal_share = 0.4, effect_bundle = "land_enc_effect_tower_drained", turns = 5 },
    --- Heals `heal_share` of each unit's missing strength, but the next floor's army is bigger.
    { key = "rest_by_the_fire", repeatable = true, heal_share = 0.25, next_budget = 1.1 },
    --- Brings the weakest unit back to full strength when it is below `below` strength points.
    { key = "reforge_the_fallen", cost = 2000, repeatable = true, below = 50 },
    --- Battle buffs put `effect_bundle` on the army for the next floor's battle only. A `per_floor` bundle has one version per floor, named
    --- with the floor number, and `cost_share` charges that share of the haul's gold instead of a fixed cost.
    { key = "war_rites", cost = 1500, effect_bundle = "land_enc_effect_tower_war_rites" },
    { key = "whetstones_and_oil", cost = 1000, effect_bundle = "land_enc_effect_tower_whetstones_and_oil" },
    { key = "warding_sigils", cost = 1500, effect_bundle = "land_enc_effect_tower_warding_sigils" },
    { key = "fire_kissed_blades", cost = 1000, effect_bundle = "land_enc_effect_tower_fire_kissed_blades" },
    { key = "enchanted_steel", cost = 1200, effect_bundle = "land_enc_effect_tower_enchanted_steel" },
    { key = "quartermasters_cache", cost = 800, effect_bundle = "land_enc_effect_tower_quartermasters_cache" },
    { key = "drill_sergeant", cost = 800, effect_bundle = "land_enc_effect_tower_drill_sergeant" },
    { key = "iron_resolve", cost = 1000, effect_bundle = "land_enc_effect_tower_iron_resolve" },
    { key = "stoneskin", cost = 1500, effect_bundle = "land_enc_effect_tower_stoneskin" },
    { key = "scaling_blessing", cost_share = 0.25, per_floor = true, effect_bundle = "land_enc_effect_tower_scaling_blessing" },
    --- In-battle tricks act in the next floor's battle only. An `effect_bundle` grants a vanilla army ability or more winds of magic, and
    --- `effect_bundles` picks one of several at random. A `trick` is done by the battle script (script/battle/mod/land_enc_tower_buffs.lua),
    --- which holds its timings. Night terrors routs the floor army's `targets` most expensive units.
    { key = "tower_artillery", cost = 2000, effect_bundle = "land_enc_effect_tower_tower_artillery" },
    { key = "call_the_winds", cost = 1000, effect_bundle = "land_enc_effect_tower_call_the_winds" },
    { key = "vortex_scroll", cost = 1500, effect_bundles = { "land_enc_effect_tower_vortex_scroll_storm_of_fire", "land_enc_effect_tower_vortex_scroll_wraith_storm",
        "land_enc_effect_tower_vortex_scroll_soul_storm" } },
    { key = "bottomless_quivers", cost = 1200, trick = true },
    { key = "oath_of_no_retreat", cost = 1500, trick = true },
    { key = "divine_shield", cost = 2500, trick = true },
    { key = "night_terrors", cost = 1500, trick = true, targets = 2 },
    --- The next floor's army budget is multiplied by `next_budget`.
    { key = "bribe_the_guards", cost = 1500, next_budget = 0.8 },
    --- Sabotage weakens the next floor's army. `no_heroes`, `fewer_units` (off its unit cap) and `max_tier` (its highest unit tier) shape how it
    --- is built. `enemy_strength` (each unit's starting strength) and `enemy_bundle` are put on it once it spawns.
    { key = "poison_the_stores", cost = 1000, enemy_strength = 0.75 },
    { key = "kill_the_captain", cost = 1500, no_heroes = true },
    { key = "thin_the_ranks", cost = 1200, fewer_units = 4 },
    { key = "lower_tiers_only", cost = 1000, max_tier = 2 },
    { key = "break_their_spirit", cost = 1000, enemy_bundle = "land_enc_effect_tower_break_their_spirit" },
    { key = "curse_their_blades", cost = 1200, enemy_bundle = "land_enc_effect_tower_curse_their_blades" },
    --- The battle script slays the enemy lord as the battle starts. Not offered against a Tower champion.
    { key = "assassinate", cost = 2500 },
    --- A unit of `tiers` from the tower's faction turns: it joins the army now, and the next floor's army fields `fewer_units` fewer.
    { key = "turn_a_traitor", cost = 2000, count = 1, tiers = { 2, 3, 4 }, from_tower = true, fewer_units = 1 },
    --- A 50/50 roll that doubles the haul's gold or halves it.
    { key = "loaded_dice", stay = true },
    --- Sends `share` of the haul's gold to the treasury, keeping it safe from a loss. The runner keeps `fee` of it.
    { key = "send_a_runner", stay = true, share = 0.5, fee = 0.2 },
    --- Adds one legendary item to the haul.
    { key = "tower_vault", cost = 2000, stay = true },
    --- Raises the next floor's item rarities by one step. Not offered when the next floor already gives legendaries.
    { key = "treasure_map", cost = 1000 },
    --- The next floor pays more gold, but its army is bigger.
    { key = "greedy_climb", next_gold = 2, next_budget = 1.2 },
    --- Pays `per_turn` gold into the treasury at each of the next `turns` turn starts, even if the delve is lost. `effect_bundle` shows it on
    --- the faction for those turns (its dummy effect's value matches `per_turn`).
    { key = "tower_dividends", cost = 1500, stay = true, per_turn = 250, turns = 10, effect_bundle = "land_enc_effect_tower_dividends" },
    --- Adds `per_unit` gold to the haul for each unit in the army just beaten.
    { key = "strip_the_dead", stay = true, per_unit = 100 },
    --- Takes `share` of the treasury and adds `multiplier` times that to the haul. Needs `min_treasury` gold in the treasury.
    { key = "tithe", stay = true, share = 0.1, multiplier = 2, min_treasury = 1000 },
    --- Adds `gold` to the haul now, but the next floor's army is bigger.
    { key = "cursed_idol", gold = 1500, next_budget = 1.15 },
    --- Unit offers show their `count` units as cards, picked when drawn, and the choice's payload adds them to the army. Each needs room
    --- for all of them. Ransom takes a unit from the army just beaten. The others pick units of `tiers` (and `unit_types` when set) from the
    --- delving faction's culture, or from the tower's faction when `from_tower` is set.
    { key = "ransom_a_captive", cost = 1000, count = 1 },
    { key = "elite_recruit", cost = 2500, count = 2, tiers = { 4, 5 } },
    { key = "conscripts", cost = 500, count = 2, tiers = { 1 } },
    { key = "captured_war_machine", cost = 2000, count = 1, tiers = { 1, 2, 3, 4, 5 }, unit_types = { "warmachine" }, from_tower = true },
    --- Regiment of renown shows one Regiment of Renown of the delving faction's culture that the army does not already field.
    { key = "regiment_of_renown", cost = 3000, count = 1 },
    --- Gives `count` random regular units `ranks` ranks each. Units already within `ranks` of `max_rank` are skipped.
    { key = "veterans_oath", cost = 1500, count = 3, ranks = 2, max_rank = 9 },
    --- Trades the weakest regular unit for a random unit from the army just beaten.
    { key = "swap_the_chaff" },
    --- Removes the weakest regular unit and heals every other unit to full.
    { key = "blood_price" },
    --- Gives the delving lord `ranks` ranks.
    { key = "lessons_in_blood", cost = 1000, ranks = 2 },
    { key = "rousing_speech", cost = 500, effect_bundle = "land_enc_effect_tower_rousing_speech" },
    --- Frees a hero of `rank` from the tower's faction, or of the delving faction's culture when that fails. It joins the army.
    { key = "freed_prisoner", cost = 2000, rank = 7 },
    --- Puts `trait` on the lord for good. When the delve ends, the lord is wounded for `wound_turns` turns at the start of the next turn.
    --- `effect_bundle` shows that price on the army until it is paid.
    { key = "dark_bargain", trait = "land_enc_trait_tower_daemon_marked", wound_turns = 3, effect_bundle = "land_enc_effect_tower_dark_bargain" },
    --- On clearing the tower the lord takes `trait` and the title in the `title_loc` loc key after their name. Not offered to a lord who has it.
    { key = "epithet", trait = "land_enc_trait_tower_towerbreaker", title_loc = "campaign_localised_strings_string_land_enc_tower_epithet" },
    --- Faction offers put `effect_bundle` on the delving faction for `turns` turns.
    { key = "towers_favour", cost = 1000, stay = true, effect_bundle = "land_enc_effect_tower_towers_favour", turns = 5 },
    { key = "research_scrolls", cost = 1000, stay = true, effect_bundle = "land_enc_effect_tower_research_scrolls", turns = 5 },
    { key = "recruitment_cache", cost = 1000, stay = true, effect_bundle = "land_enc_effect_tower_recruitment_cache", turns = 5 },
    --- The next floor's gold doubles when the army loses under `max_loss` strength points on it, and is lost otherwise.
    { key = "double_or_nothing", max_loss = 25 },
    --- Puts `effect_bundle` on the army for the rest of the delve. One haul item is lost after every floor won from then on.
    { key = "hellforge_pact", effect_bundle = "land_enc_effect_tower_hellforge" },
    --- The next floor is fought and paid as the Master's floor. Not offered when the next floor is the Master's.
    { key = "blood_moon", climb_difficulty = "hard" },
    --- A random blessing or curse, shown when the dilemma reopens: free war rites, `gold` more in the haul, a `next_budget` bigger next
    --- army, or every unit losing `bleed` strength points.
    { key = "roll_the_bones", stay = true, gold = 1000, next_budget = 1.2, bleed = 10 },
    --- A one-battle bundle that trades defence for attack.
    { key = "glass_cannon", effect_bundle = "land_enc_effect_tower_glass_cannon" },
    --- Heals `heal_share` of each unit's missing strength. Losing the next floor then destroys the whole army, lord included.
    { key = "last_stand", heal_share = 1 },
    --- Adds `gold` to the haul and puts `effect_bundle` (attrition) on the army for `turns` turns.
    { key = "plague_bearer", gold = 2000, effect_bundle = "land_enc_effect_tower_plague_bearer", turns = 3 },
    --- The next floor's army copies the delving army's regular units. Winning it adds the gold of the first `bonus` step whose `units` the copy
    --- reaches.
    { key = "mirror_curse", bonus = { { units = 20, gold = 2000 }, { units = 15, gold = 1500 }, { units = 10, gold = 1000 } } },
    --- Adds `items` unique items to the haul now. When the delve ends, a `difficulty` army of one of `factions` marches on the delving faction's
    --- capital and stays until beaten. It lands `spawn_distance` (min, max) away from the settlement of a random region in the capital's province.
    { key = "daemons_deal", stay = true, items = 2, difficulty = "hard", factions = { "chs", "kho", "nur", "sla", "tze" }, spawn_distance = { 10, 20 } },
    --- Skips the next floor for `reward_share` of its gold and half its items, and the floor after becomes hard. Not offered when the next
    --- floor is the Master's.
    { key = "tempt_fate", skips = 1, reward_share = 0.5, climb_difficulty = "hard" },
    --- Redraws the dilemma's offers.
    { key = "reroll", cost = 300, stay = true, repeatable = true },
    --- Skips the next floor with no rewards from it. Not offered when the next floor is the Master's.
    { key = "secret_stair", cost = 1500, skips = 1 },
    --- Fights `tower_data.hidden_floor` next, a bonus floor that does not count toward the climb.
    { key = "hidden_floor", bonus_floor = true },
    --- The next floor's army is one difficulty lower and pays `reward_share` of its gold. Not offered when it is already easy.
    { key = "soft_landing", reward_share = 0.5, climb_difficulty = "lower" },
    --- The next floor is led by one of the tower faction's legendary lords (configs/tower_champions.lua) that no human faction holds, with no
    --- heroes and a small guard (`fewer_units` off the cap, tiers `min_tier` and up). Its gold is multiplied by `next_gold`.
    { key = "tower_champion", next_gold = 1.5, no_heroes = true, fewer_units = 13, min_tier = 4, climb_difficulty = "champion" },
    --- This tower remembers the faction: its later delves here start on floor 2 with floor 1's base gold in the haul.
    { key = "echoes_of_the_climb" },
    --- Builds the next floor's army now and lists its units. The floor is fought against that army unless a later offer changes the floor.
    { key = "scout_the_floor", cost = 500, stay = true },
    --- Pauses the delve until the start of the next turn, so the army can replenish. `effect_bundle` stops the army moving meanwhile and says why.
    { key = "camp_in_the_tower", camp = true, effect_bundle = "land_enc_effect_tower_camping" },
    --- An allied army joins the next floor's battle.
    { key = "allies_in_the_dark", cost = 1500 },
    --- A rival army joins the next floor's battle. If it kills more than our army, it takes `rival_share` of the floor's gold and items, rounded up.
    { key = "rival_delvers", rival_share = 0.5 },
    --- In-battle missions are free stay offers that stack, tracked by the battle script. `battle_value` is handed to the battle as the mission's
    --- target. Meeting the goal on a won floor pays the reward: `gold`, `gold_share` of the floor's gold, an item of `item_rarity` (or of the
    --- floor's own rarities with `floor_item`), `unit_ranks` for the guarded unit, `lord_ranks`, or a sworn copy of the trophy unit.
    { key = "blood_tally", stay = true, mission = true, battle_value = 0.4, gold_share = 0.5 },
    { key = "headhunt", stay = true, mission = true, battle_value = 360, item_rarity = "rare" },
    { key = "hold_the_line", stay = true, mission = true, battle_value = 2, gold_share = 0.5 },
    { key = "swift_victory", stay = true, mission = true, battle_value = 480, floor_item = true },
    { key = "guard_the_standard", stay = true, mission = true, unit_ranks = 3 },
    { key = "break_them", stay = true, mission = true, battle_value = 6, gold = 1000 },
    { key = "trophy_hunt", stay = true, mission = true, sworn_copy = true },
    { key = "silence_the_guns", stay = true, mission = true, battle_value = 300, item_rarity = "rare" },
    { key = "untouchable", stay = true, mission = true, battle_value = 0.5, lord_ranks = 1 },
    { key = "bloodbath_wager", cost = 1000, stay = true, mission = true, battle_value = 0.8, gold = 3000 },
    --- A mission that climbs: killing the enemy lord adds a unique item.
    { key = "duelists_challenge", mission = true, item_rarity = "legendary" },
}

--- Each offer record by its key.
M.by_key = {}
for _, offer in ipairs(M.offers) do M.by_key[offer.key] = offer end

return M
