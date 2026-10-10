"""Writes the LEAPOI help pages: the pages in the game's help panel, their help index entries and link tooltips, the Home page card and the
intro message that links to them. Numbers in the text are `{placeholders}` filled with the defaults read from the mod's configs, so the pages
follow the configs. The runtime side is `script/land_encounters/features/help_pages.lua`, which reads the generated `configs/help_pages.lua`.
"""
import os
from typing import Dict, List, Tuple

from generators import leapoi_boons as boons

# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Files and keys

# Generated Lua list of the pages and their record builders, read by `features/help_pages.lua`.
LUA = "script/land_encounters/configs/help_pages.lua"

# The help page records (one row per line of a page), the help index entries and the loc of both. All three files are wholly generated.
ADVICE_TSV = "db/advice_info_texts_tables/land_encounters_and_points_of_interest.tsv"
INDEX_TSV = "db/help_page_index_records_tables/land_encounters_and_points_of_interest.tsv"
LOC_TSV = "text/db/land_enc_and_poi_help_pages.loc.tsv"

# The tooltip layout behind each page's link tooltip. A `{{tt:<key>}}` tooltip needs its row here, or the game shows the raw key.
TOOLTIPS_TSV = "db/ui_tooltips_tables/land_encounters_and_points_of_interest.tsv"

# The intro message's event feed string rows. Without them the message still shows, but its links do nothing in game.
EVENT_FEED_TSV = "db/event_feed_strings_tables/land_enc_help_pages.tsv"

# Most lines the intro message may fill (by `leapoi_boons.shown_lines`). Text this short sits in the message panel as plain text, where its
# links work and it leaves no gap. At about 12 lines the panel moved it into a scrolling view, where clicks on its links did nothing.
INTRO_MAX_LINES = 9

# Help index position of the header page, after the game's own Battles section (1700-1711). The other pages follow it, one level in.
INDEX_ORDER = 1800

# Record builder (CA's `hpr_*` helpers) for each kind of line.
BUILDERS = {"title": "hpr_title", "leader": "hpr_leader", "heading": "hpr_normal_unfaded", "bullet": "hpr_bulleted", "text": "hpr_normal",
            "small": "hpr_small"}

# Lua run inside the generator's config dump (update_leapoi_spot_offers.LUA_DUMP), which sets `help_values`: the defaults the page
# placeholders stand for, read from the configs and modules that own them.
VALUES_LUA = r"""
require("script/land_encounters/core/mct")
local help_mct = get_mct_settings()
local help_offers = require("script/land_encounters/configs/spot_offers")
local help_boons = require("script/land_encounters/configs/boons")
local smithy = require("script/land_encounters/configs/smithy_data")
local tavern = require("script/land_encounters/configs/tavern_data")
local spot = require("script/land_encounters/core/spot")
help_values = {
    spawn_percent = math.floor(help_mct.spawn_percentage * 100 + 0.5), battle_chance = help_mct.battle_chance,
    medium_turn = help_mct.turn_number_from_easy_to_medium, hard_turn = help_mct.turn_number_from_medium_to_hard,
    expire_turns = spot.AUTOMATIC_DEACTIVATION_COOLDOWN, empty_turns = spot.SPOT_TURN_ACTIVATION_COOLDOWN,
    legendary_chance = require("script/land_encounters/configs/battle_categories").hard_legendary_chance,
    pre_battle_chance = help_mct.pre_battle_chance, offers_per_battle = help_offers.offers_per_battle,
    missions_per_battle = help_offers.missions_per_battle, modifier_chance = help_mct.battle_modifier_chance, spoils_chance = help_mct.spoils_chance,
    site_count = #help_offers.sites, extras = help_offers.extras_per_site, floors = #require("script/land_encounters/configs/tower_data").floors,
    tower_offers = help_mct.tower_offers_per_floor, tower_cooldown = help_mct.tower_cooldown, champion_realm_chance = help_boons.champion_realm_chance,
    realm_turns = help_boons.realm_turns, relations = math.abs(require("script/land_encounters/core/owned_point").CAPTURE_RELATIONS_STEPS) * 10,
    smithy_cooldown = help_mct.smithy_cooldown, rush = smithy.rush_price_per_turn, orders_cooldown = smithy.orders_cooldown,
    commission_interval = help_mct.smithy_mission_interval, smithy_donation_1 = smithy.donations[1].price,
    smithy_donation_2 = smithy.donations[2].price, markup = help_mct.tavern_hire_markup, hires = help_mct.tavern_hires_per_visit,
    tavern_cooldown = help_mct.tavern_cooldown, restock = help_mct.tavern_hall_restock, penalty = help_mct.tavern_penalty_percent,
    penalty_turns = help_mct.tavern_penalty_turns, tavern_donation_1 = tavern.donations[1].price, tavern_donation_2 = tavern.donations[2].price,
    wins = help_boons.wins_per_level, max = help_boons.max_level, turns = help_boons.turns_per_level, turns_to_turn = help_boons.turns_to_turn,
    slots = help_mct.boon_slots, boon_chance = help_mct.boon_win_chance, curse_chance = help_mct.curse_loss_chance,
    linger_chance = help_mct.linger_chance,
}
"""

# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Text

GOLD = "[[img:icon_money]][[/img]]"
REL = "[[img:icon_diplomacy]][[/img]]"
INCOME = "[[img:icon_income]][[/img]]"
XP = "[[img:icon_experience]][[/img]]"


def link(page: str, text: str) -> str:
    """A link in a help page to another page, which the game's link parser turns into a link with that page's tooltip.

    Args:
        page (str): The linked page's key in `PAGES`.
        text (str): The linked words.

    Returns:
        str: The link markup.
    """
    return f"[[sl:land_enc_{page}]]{text}[[/sl]]"


def event_link(page: str, text: str) -> str:
    """A link in event text, where the link parser does not run, so it is written out the way vanilla event text writes its links. Its
    tooltip needs the page's `TOOLTIPS_TSV` row.

    Args:
        page (str): The linked page's key in `PAGES`.
        text (str): The linked words.

    Returns:
        str: The link markup.
    """
    return f"[[url:script_link_land_enc_{page}]][[tooltip:{{{{tt:tooltip_land_enc_{page}}}}}]]{text}[[/tooltip]][[/url]]"


# Page key -> (index title, tooltip line, lines). A line is (kind, text), with the kinds in `BUILDERS`. The first page heads the others in the
# help index and on the Home page card.
PAGES: Dict[str, Tuple[str, str, List[Tuple[str, str]]]] = {
    "leapoi": ("Land Encounters", "What the mod adds to the campaign, and where to start.", [
        ("title", "Land Encounters"),
        ("leader", "Land Encounters And Points Of Interest fills the campaign map with places worth a detour. Almost everything it adds sits on "
                   "the map as a marker your lords can walk onto."),
        ("heading", "What You Will Find"),
        ("bullet", link("encounters", "Encounter spots") + " hold a battle or a treasure site. They come and go across every map zone."),
        ("bullet", "An " + link("towers", "Ancient Tower") + " stands in each map zone. Climb it floor by floor for a growing haul."),
        ("bullet", link("smithies", "Smithies") + " and " + link("taverns", "Taverns") + " can be claimed and held. They offer items, "
                   "mercenaries, contracts and services."),
        ("bullet", "Your lords bring home lasting " + link("boons_and_curses", "boons and curses") + ", and your armies can win "
                   + link("army_spells", "army spells") + "."),
        ("heading", "Getting Started"),
        ("text", "Send a lord in the default, channelling or ambush stance onto any marker. A dilemma always shows what is on offer before "
                 "anything is spent, and almost every choice can be turned down. Early fights are easy. Enemies grow stronger from turn "
                 "{medium_turn}, and again from turn {hard_turn}."),
        ("heading", "Making It Your Own"),
        ("text", "Every feature can be tuned or turned off in the mod's settings, which also hold a guide to every offer. See "
                 + link("settings", "Settings and Compatibility") + "."),
    ]),
    "encounters": ("Encounter Spots", "Map markers that hold a battle or a treasure site.", [
        ("title", "Encounter Spots"),
        ("leader", "Encounter spots are the markers scattered across each map zone. Walk a lord onto one to find out what it holds: a battle, "
                   "or a treasure site."),
        ("heading", "How Spots Appear"),
        ("bullet", "Each map zone keeps about {spawn_percent}% of its spots active at a time."),
        ("bullet", "A spot nobody visits fades after {expire_turns} turns. A used spot stays empty for {empty_turns} turns before the zone "
                   "fills up again."),
        ("bullet", "When a lord steps on, the spot is a battle {battle_chance}% of the time. Otherwise it is a "
                   + link("treasure", "treasure site") + "."),
        ("bullet", "Only a lord in the default, channelling or ambush stance can use a spot. Anyone else just gets a message."),
        ("heading", "Battles"),
        ("text", "A battle spot opens a dilemma naming the enemy and their faction. Choose Fight, or Avoid to walk away. Avoiding costs no "
                 "gold, but some foes leave a parting gift that lingers for a few turns."),
        ("bullet", "Fights come in kinds, from a Skirmish or Bandits up to a Battlefield or a Daemonic Gift. The rarer kinds turn up more "
                   "often on higher difficulties."),
        ("bullet", "Some fights are an Ally in Peril: an ally's army is beset beside you, or needs a relief column. Saving them improves "
                   + REL + " relations with their kin."),
        ("bullet", "Winning pays " + GOLD + " gold and, for most fights, an item. Hard fights have a {legendary_chance}% chance of a "
                   "Unique or Crafted item."),
        ("bullet", "A battle can also come with offers, missions and twists. See " + link("battle_events", "Battle Offers and Missions") + "."),
        ("heading", "Difficulty"),
        ("text", "Enemies start Easy, become Medium from turn {medium_turn} and Hard from turn {hard_turn}. Their armies are built from a gold "
                 "budget and an army recipe, so a fight can be a shield wall, a monster horde or a gunline. The Enemy Forces page of the "
                 "mod's settings changes both."),
        ("heading", "AI Factions"),
        ("text", "AI lords use spots too. They take a flat reward of gold, and sometimes an item, instead of fighting."),
    ]),
    "battle_events": ("Battle Offers and Missions", "Offers, missions and twists that can come with a battle.", [
        ("title", "Battle Offers and Missions"),
        ("leader", "Many battle spots come with extra choices before the fight, and some fights carry a twist of their own."),
        ("heading", "Pre-Battle Offers"),
        ("text", "{pre_battle_chance}% of battle dilemmas also offer {offers_per_battle} ways to tip the fight: bribe guards, thin the enemy's "
                 "ranks, hire allies, bless your banners or raise the stakes for a bigger prize. Each choice shows its price, in " + GOLD
                 + " gold, blood or risk. One you cannot afford is shown greyed out."),
        ("heading", "Missions"),
        ("bullet", "The same dilemma can offer {missions_per_battle} missions: optional goals like keeping your lord alive or killing their "
                   "champion."),
        ("bullet", "Taking a mission opens the dilemma again, so you can take several before you fight."),
        ("bullet", "Each mission met in a won battle pays its reward. Failing one usually costs nothing, but a few vows carry a curse."),
        ("bullet", "Missions are only judged in a battle you fight yourself. If you auto-resolve, none count, and any wager comes back."),
        ("heading", "Battle Modifiers"),
        ("text", "Each fight has a {modifier_chance}% chance to roll battle modifiers: storms, last stands, enemy heroes, whole armies of a "
                 "faction's famous units and more. Some help you, some hurt you, and some cut both ways. A harmful modifier raises the "
                 "victory gold and a helpful one lowers it. The dilemma lists them before you choose."),
        ("heading", "Spoils of War"),
        ("text", "After a won battle, there is a {spoils_chance}% chance to pick from the spoils: loot, prisoners, captured spells and more, "
                 "or simply the gold."),
        ("heading", "In Battle"),
        ("text", "When a fight carries buffs, missions or modifiers, a button beside the menu bar shows or hides the objectives panel that "
                 "tracks them. In a battle beside an allied army, your reinforcements may arrive sooner than usual."),
    ]),
    "treasure": ("Treasure Sites", "Encounter spots that hold treasure, offers and the odd guardian.", [
        ("title", "Treasure Sites"),
        ("leader", "When an encounter spot is not a battle, it is a treasure site: one of {site_count} kinds of place, each with a story of "
                   "its own."),
        ("heading", "How a Site Works"),
        ("bullet", "Every site has its own special offer, plus {extras} more drawn from the treasure and realm offers. Offers that suit the "
                   "site come up more often."),
        ("bullet", "Take one, or Walk away for nothing. Prices in " + GOLD + " gold rise with the encounter difficulty."),
        ("bullet", "Some offers cost more than gold: a curse, a tougher next fight, worse " + REL + " relations, or a battle with a guardian."),
        ("heading", "Kinds of Offer"),
        ("bullet", "Treasure: gold, items, " + link("army_spells", "army spells") + ", " + link("boons_and_curses", "boons") + ", and pacts "
                   "that trade a curse for a stronger boon."),
        ("bullet", "Realm: offers that reach beyond the army, like improving a region, sending gifts to a friend or hiring raiders against "
                   "an enemy. Each names its target before you choose."),
        ("bullet", "Guardians: wake a sleeping champion for a Unique or Crafted item, if you can beat it."),
        ("heading", "The Sites"),
        ("text", "Hidden Tomb, Abandoned Camp, Buried Relics, Hidden Temple, Caravan Remnants, A Voice in the Dream, The Explorers, Legendary "
                 "Bard, Ruined Shrine, Smugglers' Cache, Beast Lair, Old Battlefield, Witch's Hut, Collapsed Mine, Merchant's Wagon and "
                 "Sunken Library."),
        ("heading", "AI Factions"),
        ("text", "AI lords take a flat reward of gold, an item and a short blessing instead."),
    ]),
    "towers": ("Ancient Towers", "A tower in each map zone to climb for a growing haul.", [
        ("title", "Ancient Towers"),
        ("leader", "One ancient tower stands in each map zone, held by a random faction. Delve it floor by floor for a growing haul, if your "
                   "army can survive the climb."),
        ("heading", "The Climb"),
        ("bullet", "Walk a lord onto a tower and choose Enter the Tower. Each of its {floors} floors is a battle somewhere new on the map."),
        ("bullet", "Each floor won adds " + GOLD + " gold and items to the haul. The fewer men you lose, the more the floor pays."),
        ("bullet", "From floor 3, some of the beaten army's units swear themselves to you. The last floor holds the tower's master, "
                   "guarding Unique or Crafted items."),
        ("heading", "Between Floors"),
        ("text", "After each win, pick one of up to {tower_offers} offers to help the climb, or leave with the haul. Offers range from "
                 "healing and fresh troops to " + link("army_spells", "army spells") + ", a sealed vault, a hidden floor, or a champion to "
                 "fight for a " + link("boons_and_curses", "boon") + ". Some are pacts with a price."),
        ("heading", "Losing and Leaving"),
        ("bullet", "Losing a floor loses the whole haul. Units already sworn to you stay."),
        ("bullet", "Leaving pays the haul in full. Beating the master lets you claim the tower's treasure."),
        ("bullet", "After any delve, the tower closes for {tower_cooldown} turns, then passes to a new faction."),
        ("heading", "Champions"),
        ("text", "A champion floor pits you against a legendary lord. Win it and your lord picks a boon, with a {champion_realm_chance}% "
                 "chance to bless your whole faction for {realm_turns} turns instead. Lose it, and there is the same chance of a curse on "
                 "your faction."),
    ]),
    "smithies": ("Smithies", "Forges to claim for free items, work orders and smithing services.", [
        ("title", "Smithies"),
        ("leader", "Smithies are forges scattered across the map. Claim one and its master smith works for you: free gear, work orders for "
                   "your army, and help with your boons and curses."),
        ("heading", "Claiming and Holding"),
        ("bullet", "Walk a lord onto an unclaimed Smithy to claim it for free."),
        ("bullet", "A Smithy held by anyone else must be taken by beating its garrison, which is tougher at higher levels. Taking one from "
                   "a faction you are not at war with costs {relations} " + REL + " relations with them."),
        ("bullet", "Enemies at war with you can besiege your Smithy. Fight them with its garrison, or surrender it. A Smithy you lose drops "
                   "a level."),
        ("heading", "The Forge"),
        ("bullet", "Take one of 2 free items, of better rarity at higher forge levels. The forge then cools for {smithy_cooldown} turns or "
                   "more."),
        ("bullet", "While it cools, Rush the Forge ends the wait for {rush} " + GOLD + " gold per turn left, times the forge level."),
        ("bullet", "Work Orders offer 3 orders for the whole army for a few turns, like heavier plate or honed edges. Taking one closes "
                   "the counter for {orders_cooldown} turns."),
        ("bullet", "Commission a masterwork, or upgrade the forge for better items, a shorter cooldown and more frequent tribute."),
        ("heading", "Temper and Break"),
        ("text", "At a Smithy you own, the smith tempers a boon one level or breaks a curse, for gold per level. Trade Rust for Iron gives a "
                 "boon and a curse together, for free. See " + link("boons_and_curses", "Boons and Curses") + "."),
        ("heading", "Owning a Smithy"),
        ("bullet", "Your Smithies send you an item as tribute every few turns. A level 3 forge sometimes sends a Unique or Crafted one."),
        ("bullet", "While you hold both a Smithy and its region, Arms Trade raises the province's " + INCOME + " income and the Garrison "
                   "Armoury arms its garrison."),
        ("bullet", "Every {commission_interval} turns, your best Smithy offers a Smith's Commission: a kill count, beating armies of your "
                   "nearest enemy, or winning at a marked spot, for an item named on the mission. Failing one costs nothing."),
        ("heading", "The Smiths' Association"),
        ("text", "A Generous Donation of {smithy_donation_1} " + GOLD + " gold at your own forge raises every Smithy to at least level 2, and "
                 "blesses your armies' weapons for good. A second donation of {smithy_donation_2} gold raises every Smithy to level 3 and "
                 "doubles the blessing."),
    ]),
    "taverns": ("Taverns", "Taverns to claim for mercenaries, drinks, contracts and the hedge-witch.", [
        ("title", "Taverns"),
        ("leader", "Each map zone has two Taverns: one run by a single race, and a neutral house open to all. Hire swords, try your luck at "
                   "the bar, take contracts and visit the hedge-witch."),
        ("heading", "Claiming and Visiting"),
        ("bullet", "Walk a lord onto an unclaimed Tavern to claim it, onto your own to open it, or onto an ally's or a neutral one to visit "
                   "as a guest."),
        ("bullet", "Any Tavern you do not own can be taken by beating its garrison. Taking one from a faction you are not at war with costs "
                   "{relations} " + REL + " relations."),
        ("bullet", "Enemies at war with you can besiege yours. A Tavern you lose drops a level."),
        ("heading", "The Mercenary Hall"),
        ("bullet", "Hire units of the Tavern's race, famous regiments, a hero and a few units of your own kind. A neutral Tavern stocks two "
                   "races, picked at random."),
        ("bullet", "Each costs its " + GOLD + " recruitment cost plus {markup} gold. A veteran company costs half again as much, and a "
                   "cut-price sellsword costs half but arrives at a quarter of its strength."),
        ("bullet", "You can hire {hires} per visit, then the hall closes to your faction for {tavern_cooldown} turns. The stock changes every "
                   "{restock} turns."),
        ("heading", "The Bar"),
        ("text", "Three drinks and games are on offer each visit, each a gamble or a short-lived boost. Prices rise with the campaign's "
                 "difficulty, and the owner pays a quarter less. Taking one closes the bar to your faction for {tavern_cooldown} turns."),
        ("heading", "The Contract Board"),
        ("bullet", "The Tavern Keepers' Guild posts bounties, culls and marked spots, and a three-step quest at level 3. Each takes a deposit, "
                   "which comes back with the reward."),
        ("bullet", "You can hold 1 contract at a time. Fail or drop one and you lose the deposit, and every Guild Tavern charges you "
                   "{penalty}% more for {penalty_turns} turns. Buying a contract out returns half the deposit, with no surcharge."),
        ("bullet", "Hazard pay offers half again the gold for one more harmful battle modifier. Contract terms add a bonus mission to the "
                   "fight."),
        ("heading", "The Hedge-Witch"),
        ("text", "The hedge-witch cleanses a curse or gambles on one, feeds a boon toward its next level, reweaves a boon, or lifts a curse "
                 "with a blood rite paid in your army's strength. See " + link("boons_and_curses", "Boons and Curses") + "."),
        ("heading", "The Tavern Keepers' Guild"),
        ("text", "A Generous Donation of {tavern_donation_1} " + GOLD + " gold at any Tavern raises every Tavern to at least level 2 and ends "
                 "the Guild's surcharge for you. It also blesses your faction's " + INCOME + " income, trade and armies for good, with " + XP
                 + " experience for every lord and hero each turn. A second donation of {tavern_donation_2} gold raises every Tavern to "
                 "level 3 and doubles the blessing."),
    ]),
    "boons_and_curses": ("Boons and Curses", "Lasting blessings and burdens your lords carry from fight to fight.", [
        ("title", "Boons and Curses"),
        ("leader", "A lord can carry lasting boons and curses. Each one is a trait on the lord, whose levels you can hover to see what they "
                   "do, and an icon in the army's effects says when it next changes."),
        ("heading", "How Boons Grow"),
        ("bullet", "A boon grows one level for every {wins} battles the lord wins, up to level {max}. Lost battles never take a level away."),
        ("bullet", "A charged boon does not grow. It lasts a set number of battles, then fades."),
        ("bullet", "Gaining a boon the lord already has raises it a level, or refills its charges."),
        ("heading", "How Curses Grow"),
        ("bullet", "A curse worsens one level every {turns} turns, up to level {max}."),
        ("bullet", "Some curses turn into a boon after {turns_to_turn} turns at their worst. The rest stay until lifted."),
        ("bullet", "When the lord has no room for another curse, the mildest one worsens instead."),
        ("heading", "Slots"),
        ("text", "A lord has {slots} boon slots and {slots} curse slots. A new boon on a lord with every slot full asks which one to give up. "
                 "A lord who dies or leaves the faction loses them all, and AI lords get none."),
        ("heading", "Where They Come From"),
        ("bullet", "A hard or modified win has a {boon_chance}% chance to leave a boon, and a lost battle or failed contract a "
                   "{curse_chance}% chance to leave a curse. Each battle modifier has a {linger_chance}% chance to linger as one."),
        ("bullet", "Pacts at " + link("treasure", "treasure sites") + ", the " + link("taverns", "Tavern") + " bar and the "
                   + link("towers", "Towers") + " trade a curse for a stronger boon. Tower champions and Tavern contracts give boons too."),
        ("bullet", "A Tower champion floor can bless or curse your whole faction for {realm_turns} turns. These take no lord's slot."),
        ("heading", "Lifting Curses and Raising Boons"),
        ("bullet", "At a " + link("smithies", "Smithy") + " you own, the smith tempers a boon one level or breaks a curse."),
        ("bullet", "At any " + link("taverns", "Tavern") + ", the hedge-witch cleanses a curse or gambles on one, feeds or reweaves a boon, or "
                   "lifts a curse with a blood rite."),
        ("small", "These are the default numbers. The Boons and Curses page of the mod's settings changes them."),
    ]),
    "army_spells": ("Army Spells", "Spells and abilities an army can cast without spending the Winds of Magic.", [
        ("title", "Army Spells"),
        ("leader", "An army spell lets an army cast a spell or ability in battle without spending the Winds of Magic, whoever leads it."),
        ("heading", "How They Work"),
        ("bullet", "An army spell shows on the army as an effect, naming the spell and how many casts it has in each battle."),
        ("bullet", "Lore spells give 1 to 3 casts, more for cheaper spells. Bound spells and army abilities keep their own uses."),
        ("bullet", "Most last 5 turns. Some last only for the next battle."),
        ("bullet", "Over 400 can turn up, from every lore of magic, bound item and army ability in the game."),
        ("heading", "Where to Find Them"),
        ("bullet", link("treasure", "Treasure sites") + ": scrolls, shrines and runestones."),
        ("bullet", link("battle_events", "Battles") + ": pre-battle scrolls, the Witch Hunt mission and the spoils of war."),
        ("bullet", link("taverns", "Taverns") + ": the Spell Pedlar at the bar, and won marked-spot contracts."),
        ("bullet", link("smithies", "Smithies") + ": the Runesmith's Inscription work order."),
        ("bullet", link("towers", "Towers") + ": scrolls, relics and war horns between floors, for the next floor."),
    ]),
    "settings": ("Settings and Compatibility", "The mod's settings pages, and what it changes in the base game.", [
        ("title", "Settings and Compatibility"),
        ("leader", "Everything in Land Encounters can be tuned through the Mod Configuration Tool (MCT). Each feature has its own page, "
                   "with an in-game guide to how it works and what every offer does."),
        ("heading", "Settings Pages"),
        ("bullet", "General: how many spots are active, and how many are battles."),
        ("bullet", "Encounters: battle types, event chances, marker skins, and guides to every offer."),
        ("bullet", "Enemy Forces: difficulty, budgets, army recipes, and units from other mods."),
        ("bullet", "Towers, Smithies, Taverns, and Boons and Curses: each can be tuned or turned off. Smithies and Taverns can be removed "
                   "from the map."),
        ("heading", "Changes to the Base Game"),
        ("bullet", "Dilemma layout: a dilemma with more than three rows of choices, or one too tall for your screen, shows its choices in a "
                   "scrolling list. This applies to every dilemma in the game."),
        ("bullet", "Battle scripts: the mod's battle scripts load in every battle, but only act in its own fights."),
        ("bullet", "Objectives button: in the mod's fights that carry buffs, missions or modifiers, a button beside the menu bar shows or "
                   "hides the objectives panel."),
        ("heading", "Good to Know"),
        ("bullet", "Works in Immortal Empires, the Realm of Chaos and The Old World, and with Immortal Empires Expanded."),
        ("bullet", "Multiplayer is untested."),
    ]),
}

# The Home page card: title, image record (no text) and text.
CONTENTS = ["Land Encounters", "",
            "Battles, treasure, Towers, Smithies and Taverns off the beaten road, and the boons and curses your lords carry home."]

# Intro message after the opening cutscene: title, subtitle and paragraphs.
INTRO = ("Land Encounters", "Places Worth a Detour", [
    "Lords who leave the road find more than mud. Battles, treasure, an Ancient Tower, Smithies and Taverns wait in every map zone. Walk "
    "a lord onto any marker to see what it holds.",
    "Learn more in the help pages: " + event_link("leapoi", "Land Encounters") + ", " + event_link("encounters", "Encounter Spots") + ", "
    + event_link("towers", "Ancient Towers") + ", " + event_link("smithies", "Smithies") + ", " + event_link("taverns", "Taverns") + " and "
    + event_link("boons_and_curses", "Boons and Curses") + ".",
])

# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Writing


def record_key(page: str, line: object) -> str:
    """The `advice_info_texts` key of a page's line: numbered from 1, or a name like "tip".

    Args:
        page (str): The page's key in `PAGES`, or "contents" for the Home page card.
        line (object): The line's number on the page, or its name.

    Returns:
        str: The record key.
    """
    return f"land_enc_hp_{page}_{line:03d}" if isinstance(line, int) else f"land_enc_hp_{page}_{line}"


def lua_config() -> str:
    """The generated Lua list of the pages and their record builders.

    Returns:
        str: The Lua file's text.
    """
    body = ""
    for key, (_, _, lines) in PAGES.items():
        builders = [f'"{BUILDERS[kind]}"' for kind, _ in lines]
        rows = ["        " + ", ".join(builders[i:i + 6]) + "," for i in range(0, len(builders), 6)]
        body += f'    {{ key = "{key}", records = {{\n' + "\n".join(rows) + "\n    } },\n"
    return ("--- The LEAPOI help pages in index order, each with the record builder of every line. Line n of page `key` reads the\n"
            "--- `advice_info_texts` record `land_enc_hp_<key>_<nnn>`. Generated by helper_scripts/generators/leapoi_help_pages.py: do not\n"
            "--- edit by hand.\n\n"
            "return {\n" + body + "}\n")


def write(mod_root: str, values: Dict[str, int], dry_run: bool) -> None:
    """Writes the help page records, index entries, link tooltips, loc and the runtime's page list.

    Args:
        mod_root (str): The mod folder, ending in a slash.
        values (Dict[str, int]): Placeholder -> default, from the generator's config dump (`VALUES_LUA`).
        dry_run (bool): True to only print what would be written.

    Raises:
        SystemExit: When the intro message is too long to stay out of the panel's scrolling view.
    """
    advice, index, tooltips, event_feed, loc = [], [], [], [], []

    def add_record(key: str, text: str, header: bool, order: int) -> None:
        advice.append([key, "true", "false", "true", "true" if header else "false", str(order)])
        loc.append(["advice_info_texts_localised_text_" + key, text.format_map(values), "false"])

    for order, (page, (index_title, tooltip, lines)) in enumerate(PAGES.items()):
        for i, (kind, text) in enumerate(lines, 1):
            add_record(record_key(page, i), text, kind == "title", i - 1)
        add_record(record_key(page, "tip"), tooltip, False, len(lines))
        index.append([f"land_enc_{page}", str(INDEX_ORDER + order), "0" if order == 0 else "1", "false", "true"])
        tooltips.append([f"tooltip_land_enc_{page}", "tooltip_title_and_text"])
        loc.append([f"help_page_index_records_text_land_enc_{page}", link(page, index_title), "false"])
    for i, text in enumerate(CONTENTS, 1):
        add_record(record_key("contents", i), text, i == 1, i - 1)
    title, subtitle, paragraphs = INTRO
    description = boons.BREAK.join(paragraphs)
    if boons.shown_lines(description) > INTRO_MAX_LINES:
        raise SystemExit(f"The intro message fills {boons.shown_lines(description)} lines, more than {INTRO_MAX_LINES}")
    for field, text in (("title", title), ("subtitle", subtitle), ("description", description)):
        event_feed.append([f"{field}_event_land_enc_intro"])
        loc.append([f"event_feed_strings_text_{field}_event_land_enc_intro", text, "false"])

    files = [
        (ADVICE_TSV, ["key\tpersistant\tshow_instant\tshow_on_navigate\tis_header\tnavigation_order",
                      "#advice_info_texts_tables;3;db/advice_info_texts_tables/land_encounters_and_points_of_interest\t\t\t\t\t"], advice),
        (INDEX_TSV, ["key\tdisplay_order\tinset_level\tis_battle\tenabled",
                     "#help_page_index_records_tables;2;db/help_page_index_records_tables/land_encounters_and_points_of_interest\t\t\t\t"], index),
        (TOOLTIPS_TSV, ["key\tlayout_name", "#ui_tooltips_tables;0;db/ui_tooltips_tables/land_encounters_and_points_of_interest\t"], tooltips),
        (EVENT_FEED_TSV, ["key", "#event_feed_strings_tables;0;db/event_feed_strings_tables/land_enc_help_pages"], event_feed),
        (LOC_TSV, ["key\ttext\ttooltip", "#Loc;1;text/db/land_enc_and_poi_help_pages.loc\t\t"], loc),
    ]
    for path, header, rows in files:
        print(f"{path}: {len(rows)} rows")
        if not dry_run:
            text = "".join(line + "\r\n" for line in header + ["\t".join(row) for row in rows])
            os.makedirs(os.path.dirname(mod_root + path), exist_ok=True)
            open(mod_root + path, "wb").write(text.encode("utf-8"))
    print(f"{LUA}: {len(PAGES)} pages")
    if not dry_run:
        open(mod_root + LUA, "w", encoding="utf-8", newline="\n").write(lua_config())
