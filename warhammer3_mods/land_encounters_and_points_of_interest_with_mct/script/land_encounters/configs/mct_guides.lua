--- Guide text for the MCT pages: the short intros and the order of the Towers page offer sections. Pure data - no runtime logic.
--- The offer, battle and treasure lines themselves are built from their own configs by core/mct_guides.lua.

local M = {}

--- Intro of the Encounters page battle spot guide.
M.battle_spots_intro = "Most encounter spots start a battle when a lord walks onto them. A dilemma first shows the enemy, and winning pays gold "
    .. "and often an item. Rarer battles come up more on higher difficulties."

--- Intro of the Encounters page treasure spot guide.
M.treasure_spots_intro = "The rest of the encounter spots hold treasure instead (see Battle chance on the General page). Walking onto one "
    .. "grants its reward at once."

--- Text of the Towers page guide on how towers work.
M.towers_intro = "One tower stands in each map zone, held by a random faction. Move a lord onto it to delve. Each floor is a battle somewhere "
    .. "new on the map, and each floor won adds its rewards to the haul. After each win, pick one offer to help the climb, or leave with the "
    .. "haul. Losing a floor loses the whole haul. After a delve the tower stays closed for the cooldown, then passes to a new faction."

--- Intro of the Smithies page guide. The per-level lines follow it.
M.smithy_intro = "Walk a lord onto an unclaimed Smithy to claim it, and onto your own to pick a free item. The forge then cools for the Smithy "
    .. "cooldown, plus the extra turns of a lower forge level. Upgrade the forge for better items, a shorter cooldown and more frequent tribute. "
    .. "Enemies at war with you can besiege or retake it."

--- Towers page offer sections in page order. Each offer's `guide_section` in configs/tower_offers.lua names one of these keys.
M.tower_offer_sections = {
    { key = "healing", title = "Healing" },
    { key = "battle_buffs", title = "Battle Buffs" },
    { key = "spells", title = "Spells" },
    { key = "tricks", title = "Tricks" },
    { key = "sabotage", title = "Sabotage" },
    { key = "gold_and_loot", title = "Gold and Loot" },
    { key = "units_and_lord", title = "Units and Lord" },
    { key = "faction_boons", title = "Faction Boons" },
    { key = "gambles", title = "Gambles" },
    { key = "the_climb", title = "The Climb" },
    { key = "missions", title = "Missions" },
}

return M
