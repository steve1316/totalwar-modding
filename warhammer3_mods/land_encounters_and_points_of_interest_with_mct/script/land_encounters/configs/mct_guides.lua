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
    .. "A Smithy held by anyone else can be taken by beating its garrison, harder at higher levels. Taking it from a faction you are not at war "
    .. "with costs 20 relations with them. Enemies at war with you can besiege or retake yours, and AI owners upgrade theirs now and then. "
    .. "Every Smithy belongs to the Smiths' Association. A Generous Donation of 50000 gold at your own forge raises every Smithy to at least "
    .. "level 2 and blesses your armies' weapons for good, and a second of 100000 gold raises every Smithy to level 3 and doubles the blessing."

--- Intro of the Taverns page guide. The per-level lines follow it.
M.tavern_intro = "Each map zone has a racial Tavern, run by one race, and a neutral one open to all. Walk a lord onto an unclaimed Tavern "
    .. "to claim it, onto your own to open its hub, and onto one held by an ally or a neutral faction to visit it as a guest. Any Tavern you do "
    .. "not own can be taken by beating its garrison, harder at higher levels, and taking it from a faction you are not at war with costs 20 "
    .. "relations with them. Only the owner can upgrade it, and AI owners do so now and then. The mercenary hall hires out "
    .. "units of the Tavern's race (two random races at a neutral one), famous regiments, a hero and a few units of your own kind, for 1000 "
    .. "gold over their recruitment cost (2500 for a famous regiment). Its stock is shared by every visitor and changes every few turns. Hire up to 2 per visit, after which the hall "
    .. "closes to that faction for a few turns. At the bar, 3 of the drinks and games below are on offer each visit, for gold that rises with "
    .. "the campaign's difficulty, and a higher level makes each drink stronger. Taking one closes the bar to that faction for a few turns, and "
    .. "the owner pays a quarter less there. Every Tavern belongs to the Tavern Keepers' Guild, whose contract board posts bounties, culls and "
    .. "marked spots (and a three-step quest at level 3) for a deposit, returned with a reward on success. You can hold 1 contract at a time across every Tavern, and drop it from the missions panel. "
    .. "Fail or drop one and you lose its deposit, and every Guild Tavern charges you a quarter more for 10 turns. Bounties, marked spots and "
    .. "quests can roll battle modifiers like any other fight, shown on the board before you take them. They leave the reward as it is. A "
    .. "Generous Donation of 50000 gold at any Tavern raises every Tavern to at least level 2, ends the Guild's surcharge for you and blesses "
    .. "your faction's income, trade and armies for good, with experience for every lord and hero each turn. A second donation of 100000 gold "
    .. "raises every Tavern to level 3 and doubles the blessing."

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
