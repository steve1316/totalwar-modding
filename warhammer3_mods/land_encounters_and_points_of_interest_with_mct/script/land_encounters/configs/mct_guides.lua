--- Guide text for the MCT pages: the short intros and the order of the Towers and Encounters page offer sections. Pure data - no runtime
--- logic.
--- The offer, battle and treasure lines themselves are built from their own configs by core/mct_guides.lua.

local M = {}

--- Intro of the Encounters page battle spot guide.
M.battle_spots_intro = "Most encounter spots start a battle when a lord walks onto them. A dilemma first shows the enemy, and winning pays gold and "
    .. "often an item. Rarer battles come up more on higher difficulties. Sometimes the dilemma also offers ways to tip the battle, or missions "
    .. "that pay out if you meet them. A win can also open a pick of spoils (see Battle Events above). Some battle modifiers "
    .. "and spoils leave a boon or curse on your lord. In battle, a button next to the menu bar hides or shows the objectives panel."

--- Intro of the Encounters page treasure spot guide.
M.treasure_spots_intro = "The rest of the encounter spots hold treasure instead, and Battle chance on the General page sets the split. Walking onto "
    .. "one opens a treasure site with its own special offer, listed by site below, two more drawn from the site offers, and Walk away. Costs "
    .. "and gold grow with the difficulty. The offer guides show the Easy amounts. AI factions take a flat reward instead."

--- Text of the Towers page guide on how towers work.
M.towers_intro = "One tower stands in each map zone, held by a random faction. Move a lord onto it to delve. Each floor is a battle somewhere "
    .. "new on the map, and each floor won adds its rewards to the haul. After each win, pick one offer to help the climb, or leave with the "
    .. "haul. Losing a floor loses the whole haul. After a delve the tower stays closed for the cooldown, then passes to a new faction. The floor "
    .. "gold below is at the default Floor gold setting."

--- Intro of the Smithies page guide. The per-level lines follow it.
M.smithy_intro = "Walk a lord onto an unclaimed Smithy to claim it, or onto your own to pick one of two free items. The forge then cools for "
    .. "the Smithy cooldown, plus extra turns at lower forge levels. While it cools, Rush the Forge ends the wait for 500 gold per turn left, "
    .. "times the forge level. The forge's Work Orders offer three orders for the whole army, listed below, and serve you again 5 turns after "
    .. "you take one. Upgrade the forge for better items, a shorter cooldown and more frequent tribute. A "
    .. "Smithy held by anyone else can be taken by beating its garrison, which gets harder at higher levels. Taking one from a faction you are not "
    .. "at war with costs 20 [[img:icon_diplomacy]][[/img]] relations with them. Enemies can besiege or retake yours, and AI owners upgrade theirs now and then. "
    .. "While you hold both a Smithy and its region, Arms Trade raises the province's income and the Garrison Armoury arms the region's garrison, "
    .. "more at each forge level. Every few turns your highest-level Smithy offers a Smith's Commission: a kill count, beating armies of your "
    .. "nearest enemy, or winning a battle at a marked spot near it, for an item named on the mission. Failing one costs nothing. Every Smithy "
    .. "belongs to the Smiths' Association. A Generous Donation of 50000 gold at your own forge raises every Smithy to at least level 2 and blesses "
    .. "your armies' weapons for good. A second donation of 100000 gold raises every Smithy to level 3 and doubles the blessing. The prices "
    .. "below are at the default Smithy prices setting."

--- Intro of the Taverns page guide. The per-level lines follow it.
M.tavern_intro = "Each map zone has one racial Tavern, run by a single race, and one neutral Tavern open to all. Walk a lord onto an unclaimed "
    .. "Tavern to claim it, onto your own to open its hub, or onto one held by an ally or a neutral faction to visit as a guest. Any Tavern you do "
    .. "not own can be taken by beating its garrison, which gets harder at higher levels. Taking one from a faction you are not at war with costs "
    .. "20 [[img:icon_diplomacy]][[/img]] relations with them. Enemies at war with you can besiege yours. You then fight them with its garrison or surrender it, and a Tavern "
    .. "you lose drops a level. Only the owner can upgrade a Tavern, and AI owners do so now and then.\n\n"
    .. "The mercenary hall hires out units of the Tavern's race (two random races at a neutral one), famous regiments, a hero and a few units of "
    .. "your own kind. Each costs gold over its [[img:icon_money]][[/img]] recruitment cost (1000 by default), and a famous regiment 1500 more. The stock is shared by every "
    .. "visitor and changes every few turns. You can hire a few per visit (2 by default), then the hall closes to your faction for a few turns. "
    .. "The hall also offers a veteran company with extra ranks for half again the price, and a cut-price sellsword at half price but a "
    .. "quarter of its strength.\n\n"
    .. "At the bar, 3 of the drinks and games below are on offer each visit. Their price rises with the campaign's difficulty, and a higher level "
    .. "makes each drink stronger. Taking one closes the bar to your faction for a few turns. The owner pays a quarter less at their own bar.\n\n"
    .. "Every Tavern belongs to the Tavern Keepers' Guild. Its contract board posts bounties, culls and marked spots (and a three-step quest at "
    .. "level 3) for a deposit, which comes back with a reward on success. You can hold 1 contract at a time across every Tavern, and drop it from "
    .. "the missions panel. If you fail or drop one, you lose the deposit and every Guild Tavern charges you more for a while (a quarter more "
    .. "for 10 turns by default). Bounties, "
    .. "marked spots and quests can roll battle modifiers like any other fight. The board shows them before you take the contract, and they do not "
    .. "change the reward. One bounty or marked spot on each board pays hazard pay: half again the gold, for one more harmful battle modifier. "
    .. "A bounty or marked spot fight can also come with contract terms, a battle mission that pays a bonus if you meet it. You can buy out a "
    .. "contract you hold for half the deposit back.\n\n"
    .. "The hedge-witch at any Tavern cleanses a curse or gambles on one, feeds a boon toward its next level, reweaves a boon into a stronger "
    .. "or different one, or lifts a curse with a blood rite paid in your army's strength. Each service then waits a few turns for that lord "
    .. "at that Tavern.\n\n"
    .. "A Generous Donation of 50000 gold at any Tavern raises every Tavern to at least level 2 and ends the Guild's surcharge for you. It also "
    .. "blesses your faction's [[img:icon_income]][[/img]] income, trade and armies for good, with [[img:icon_experience]][[/img]] experience for "
    .. "every lord and hero each turn. A second donation of 100000 gold raises every Tavern to level 3 and doubles the blessing."

--- Intro of the Boons and Curses page guide. Every boon, curse and faction-wide effect follows it.
M.boons_intro = "A lord can carry lasting boons and curses. A boon grows one level for every 5 battles the lord wins, up to level 5. A curse "
    .. "gets one level worse every 5 turns, up to level 5. A few curses that stay at level 5 for 10 turns turn into a boon. A lord has 3 boon "
    .. "slots and 3 curse slots by default. A new boon on a lord with every slot full asks which one to give up, and a new curse makes the "
    .. "mildest one worse instead. Gaining one the lord already carries raises it a level. A lord who dies or leaves the faction loses them all, "
    .. "and AI lords get none.\n\n"
    .. "By default a hard or modified LEAPOI win, a lost LEAPOI battle and each battle modifier of a fight each have a 3% chance to leave a boon "
    .. "or curse. The sliders above change these chances. A Tower champion floor has a 3% chance to bless the whole faction for 10 turns "
    .. "when won, or curse it when lost. Pacts at treasure sites, the Tavern bar and the Tower trade a curse for a stronger "
    .. "boon. At a Smithy you own, the smith tempers a boon one level or breaks a curse. At any Tavern, the hedge-witch cleanses a curse, or "
    .. "gambles on one: half the time it lifts, otherwise it becomes another curse. The hedge-witch can also feed or reweave "
    .. "a boon, or lift a curse with a blood rite. Charged boons last a few battles instead of growing."

--- Encounters page spot offer sections in page order, one per offer pool in configs/spot_offers.lua.
M.spot_offer_sections = {
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
    { key = "pacts", title = "Pacts" },
    { key = "the_climb", title = "The Climb" },
    { key = "missions", title = "Missions" },
}

return M
