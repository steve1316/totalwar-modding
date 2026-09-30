--- Tower offers: the roguelite choices drawn onto each go-deeper dilemma between Climb and Leave. Each record's choice key is
--- "LEAPOI_TWR_" plus its key in capitals, and its popup text is the `dummy_land_enc_tower_<key>` payload line. What each offer does, and when
--- it can be drawn, lives in features/tower_offers.lua.

local M = {}

--- Choice key of Leave on the per-floor go-deeper dilemmas. Its DB order is the highest, so Leave is always the last choice.
M.leave_choice_key = "LEAPOI_TWR_LEAVE"

--- Most offers drawn onto one go-deeper dilemma.
M.offers_per_floor = 4

--- Offer records in popup order. `cost` is gold taken from the haul (none means free). A `stay` offer reopens the same floor's dilemma
--- after it applies, and any other offer climbs to the next floor. A `repeatable` offer can be drawn again after it is taken.
M.offers = {
    --- Heals `heal_share` of each unit's missing strength.
    { key = "tend_wounded", cost = 1000, repeatable = true, heal_share = 0.5 },
    --- Puts `effect_bundle` on the army for the next floor's battle only.
    { key = "war_rites", cost = 1500, effect_bundle = "land_enc_effect_tower_war_rites" },
    --- A 50/50 roll that doubles the haul's gold or halves it.
    { key = "loaded_dice", stay = true },
    --- Sends `share` of the haul's gold to the treasury, keeping it safe from a loss. The runner keeps `fee` of it.
    { key = "send_a_runner", stay = true, share = 0.5, fee = 0.2 },
}

return M
