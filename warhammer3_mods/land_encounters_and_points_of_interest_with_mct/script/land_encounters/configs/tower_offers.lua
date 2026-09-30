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
    --- The next floor's army budget is multiplied by `next_budget`.
    { key = "bribe_the_guards", cost = 1500, next_budget = 0.8 },
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
    --- The next floor's gold doubles when the army loses under `max_loss` strength points on it, and is lost otherwise.
    { key = "double_or_nothing", max_loss = 25 },
    --- Puts `effect_bundle` on the army for the rest of the delve. One haul item is lost after every floor won from then on.
    { key = "hellforge_pact", effect_bundle = "land_enc_effect_tower_hellforge" },
    --- The next floor is fought and paid as the Master's floor. Not offered when the next floor is the Master's.
    { key = "blood_moon" },
    --- A random blessing or curse, shown when the dilemma reopens: free war rites, `gold` more in the haul, a `next_budget` bigger next
    --- army, or every unit losing `bleed` strength points.
    { key = "roll_the_bones", stay = true, gold = 1000, next_budget = 1.2, bleed = 10 },
    --- Skips the next floor for `reward_share` of its gold and half its items, and the floor after becomes hard. Not offered when the next
    --- floor is the Master's.
    { key = "tempt_fate", skips = 1, reward_share = 0.5 },
    --- Redraws the dilemma's offers.
    { key = "reroll", cost = 300, stay = true, repeatable = true },
    --- Skips the next floor with no rewards from it. Not offered when the next floor is the Master's.
    { key = "secret_stair", cost = 1500, skips = 1 },
    --- Fights `tower_data.hidden_floor` next, a bonus floor that does not count toward the climb.
    { key = "hidden_floor", bonus_floor = true },
    --- The next floor's army is one difficulty lower and pays `reward_share` of its gold. Not offered when it is already easy.
    { key = "soft_landing", reward_share = 0.5 },
    --- This tower remembers the faction: its later delves here start on floor 2 with floor 1's base gold in the haul.
    { key = "echoes_of_the_climb" },
}

return M
