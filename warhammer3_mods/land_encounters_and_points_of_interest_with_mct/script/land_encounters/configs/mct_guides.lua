--- Guide text for the MCT pages: the short intros and the order of the Towers and Encounters page offer sections. Pure data - no runtime
--- logic.
--- The offer, battle and treasure lines themselves are built from their own configs by core/mct_guides.lua.

local M = {}

--- Intro of the Encounters page battle spot guide.
M.battle_spots_intro = "Most encounter spots start a battle when a lord walks onto them. A dilemma first shows the enemy, and winning pays gold "
    .. "and often an item. Rarer battles come up more on higher difficulties. Sometimes the dilemma also offers ways to tip the battle and "
    .. "missions that pay out if met, and a win can open a pick of spoils (see Battle Events above)."

--- Intro of the Encounters page treasure spot guide.
M.treasure_spots_intro = "The rest of the encounter spots hold treasure instead (see Battle chance on the General page). Walking onto one "
    .. "opens a treasure site: its own special offer, two more drawn from the site offers below, and Walk away. Costs and gold grow with the "
    .. "difficulty. The offer guides show the Easy amounts. AI factions take a flat reward instead."

--- Text of the Towers page guide on how towers work.
M.towers_intro = "One tower stands in each map zone, held by a random faction. Move a lord onto it to delve. Each floor is a battle somewhere "
    .. "new on the map, and each floor won adds its rewards to the haul. After each win, pick one offer to help the climb, or leave with the "
    .. "haul. Losing a floor loses the whole haul. After a delve the tower stays closed for the cooldown, then passes to a new faction."

--- Intro of the Smithies page guide. The per-level lines follow it.
M.smithy_intro = "Walk a lord onto an unclaimed Smithy to claim it, and onto your own to pick a free item. The forge then cools for the Smithy "
    .. "cooldown, plus the extra turns of a lower forge level. Upgrade the forge for better items, a shorter cooldown and more frequent tribute. "
    .. "Enemies at war with you can besiege or retake it."

--- Intro of the Taverns page guide. The per-level lines follow it.
M.tavern_intro = "Each map zone has a racial Tavern, run by one race, and a neutral one open to all. Walk a lord onto an unclaimed Tavern "
    .. "to claim it, onto your own to open its hub, and onto one held by an ally or a neutral faction to visit it as a guest. A Tavern held by "
    .. "a faction at war with you can be taken in battle, harder at higher levels. Only the owner can upgrade it. The mercenary hall hires out "
    .. "units of the Tavern's race (two random races at a neutral one), famous regiments, a hero and a few units of your own kind, for 1000 "
    .. "gold over their recruitment cost. Its stock is shared by every visitor and changes every few turns. Hire up to 2 per visit, after which the hall "
    .. "closes to that faction for a few turns. At the bar, 3 of the drinks and games below are on offer each visit, for gold that rises with "
    .. "the campaign's difficulty, and a higher level makes each drink stronger. Taking one closes the bar to that faction for a few turns, and "
    .. "the owner pays a quarter less there. The contract board opens in a later update."

--- Encounters page spot offer sections in page order, one per offer pool in configs/spot_offers.lua.
M.spot_offer_sections = {
    { key = "signature", title = "Site Specials" },
    { key = "treasure", title = "Treasure Sites" },
    { key = "realm", title = "Realm" },
    { key = "pre_battle", title = "Pre-Battle" },
    { key = "mission", title = "Missions" },
    { key = "spoils", title = "Spoils of War" },
}

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
