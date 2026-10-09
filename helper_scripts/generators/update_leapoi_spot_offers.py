"""Writes the LEAPOI spot offer rows: treasure site dilemmas, the pre-battle choices on battle dilemmas, choice lines, battle notices, effect
bundles, traits and every loc string they need.

The sites and offers come from the mod's `configs/spot_offers.lua`, read through the `lua` executable. The text lives here and follows the
tower's reviewed house rules: names in title case, gold without separators, "our" voice, paid lines as "Pay N gold from our treasury to ...",
stat icons beside stat names, and a not-enough-gold line for every paid offer. Every row this script owns is removed and written again on
each run, so it is safe to run after any change to the config or the text.

Run from `helper_scripts/`: `python -m generators.update_leapoi_spot_offers`.
"""

import argparse
import json
import os
import re
import subprocess
from collections import defaultdict
from typing import Dict, List, Pattern, Sequence, Tuple

from generators.leapoi_tower_offer_text import NOTICES as TOWER_NOTICE_TEXT, PAY as TOWER_PAY, SPELL_ICON, TOWER_BUNDLES, TOWER_ICONS, TOWER_LINES, TOWER_NAMES
from generators import leapoi_battle_modifiers as battle_modifiers
from generators import leapoi_effect_library as effect_library
from generators import leapoi_army_spells as army_spells
from generators import leapoi_boons as boons
from generators.leapoi_stat_icons import add_stat_icons

MOD_ROOT = "../warhammer3_mods/land_encounters_and_points_of_interest_with_mct/"
TABLE_FILE = "land_encounters_and_points_of_interest.tsv"
LOC_PREFIX = "text/db/land_enc_and_poi_"

# First id of the option junction and payload rows, clear of the tower's 70179007xx ids.
FIRST_ROW_ID = 7018100000

# Choice order of the offers, in config order from this number. A site's signature sits on the vanilla FIRST key, and Walk away comes last.
FIRST_CHOICE_ORDER = 300
WALK_AWAY_ORDER = 998

# Choice order of the first tower offer granting a boon or curse, after the hand-made tower choices.
TOWER_GRANT_ORDER = 210

DIFFICULTIES = ["easy", "medium", "hard"]

# Words a title-case name keeps lowercase after its first word, as vanilla does.
SMALL_WORDS = {"a", "an", "and", "at", "by", "for", "from", "in", "into", "of", "on", "or", "the", "to", "with"}

# Choice order of Avoid on a battle dilemma with offers: last, as the tower's Leave.
AVOID_ORDER = 999

# Prefix of a battle notice's scripted objective, shared with the tower's notices and the battle script.
NOTICE_PREFIX = "land_enc_tower_buff_"

# Line markers that make a row this script's own, so a run replaces it.
OWNED_MARKERS = ("land_enc_dilemma_site_", "LEAPOI_SPT_", "dummy_land_enc_spot_", "land_enc_effect_spot_", "land_enc_trait_spot_", "event_land_enc_spot_",
                 "string_land_enc_spot_", "land_enc_incident_spot_", "land_enc_tower_buff_modifier_", "land_enc_effect_ability_enable_",
                 "land_enc_ability_enable_", "dummy_land_enc_tower_allies_in_the_dark_", effect_library.BUNDLE_PREFIX,
                 effect_library.CUSTOM_PREFIX)

# The Allies in the Dark offers, whose lines also come in a version naming the theme their allied army rolled.
ALLY_OFFERS = ("allies_in_the_dark_small", "allies_in_the_dark_medium", "allies_in_the_dark_large")

# Generated Lua table of each battle victory incident's gold, which battle modifiers scale.
VICTORY_GOLD_LUA = "script/land_encounters/configs/victory_gold.lua"

# Picture of a result's incident: missions show a victory, everything else a found treasure.
RESULT_IMAGE = "wh2_sea_encounters_1"
MISSION_RESULT_IMAGE = "land_victory"

# Picture of each result's incident, by its key after the result prefix, picked in the art pass. A result not listed shows
# `MISSION_RESULT_IMAGE` for a mission or `RESULT_IMAGE` otherwise.
RESULT_IMAGES = {
    "wake_the_sleeping_champion_won": "nemesis_crown",
    "chip_the_runestone": "winds_of_magic_change",
    "free_the_prisoner_freed": "army_morale_up",
    "free_the_prisoner_chased": "wh2_rogue_army_encountered",
    "research_scrolls": "books_of_nagash",
    "tomb_robbing_spared": "vc_puzzle_1_background",
    "tomb_robbing_haunted": "vc_puzzle_1_background",
    "abandoned_camp": "wh2_rogue_army_encountered",
    "buried_relics": "vc_puzzle_4_background",
    "hidden_temple": "old_ones_temples_up",
    "caravan_remnants": "carnage_weapons",
    "whispers_of_the_gods": "winds_of_magic_change",
    "the_explorer": "elector_region",
    "legendary_bard": "land_victory",
    "arm_wrestle_the_champion_lost": "waaagh_up",
    "arm_wrestle_the_champion_won": "land_victory",
    "bountiful_harvest": "imperial_supplies",
    "buy_rumours": "minor_cult",
    "cast_the_lots_lost": "wulfhart_hunters",
    "cast_the_lots_won": "wulfhart_hunters",
    "chase_the_routers_lost": "ursun_defeat",
    "chase_the_routers_won": "carnage_charge",
    "curse_a_distant_king": "story_panels/chd_pet_curse",
    "dice_with_strangers_lost": "wulfhart_hunters",
    "dice_with_strangers_won": "wulfhart_hunters",
    "double_or_nothing_lost": "elector_politics",
    "drink_from_the_spring_lost": "attrition_disease",
    "drink_from_the_spring_won": "rift_entered",
    "endow_the_province": "elector_region",
    "gamble_with_the_hermit_lost": "wulfhart_hunters",
    "garrison_drill": "victory",
    "mission_against_the_odds_failed": "carnage_weapons",
    "mission_blood_tally_failed": "carnage_weapons",
    "mission_bloodbath_wager_failed": "carnage_weapons",
    "mission_break_them_failed": "carnage_magic",
    "mission_decapitate_failed": "carnage_weapons",
    "mission_duelists_challenge_failed": "carnage_weapons",
    "mission_flawless_victory_failed": "defeat",
    "mission_flawless_victory_met": "victory",
    "mission_guard_the_standard_failed": "defeat",
    "mission_headhunt_failed": "carnage_weapons",
    "mission_hold_the_line_failed": "defeat",
    "mission_lords_glory_failed": "carnage_weapons",
    "mission_monster_slayer_failed": "chaos_invasion",
    "mission_rout_the_riders_failed": "queen_and_crone",
    "mission_rout_the_riders_met": "carnage_charge",
    "mission_silence_the_guns_failed": "carnage_magic",
    "mission_spare_the_captain_failed": "carnage_weapons",
    "mission_steadfast_failed": "defeat",
    "mission_swift_victory_failed": "carnage_weapons",
    "mission_trophy_hunt_failed": "carnage_weapons",
    "mission_untouchable_failed": "defeat",
    "mission_untouchable_met": "army_morale_up",
    "missions_untracked": "messenger",
    "mystery_brew_lost": "attrition_disease",
    "mystery_brew_strikes": "army_morale_up",
    "mystery_brew_spell": "carnage_magic",
    "dice_with_strangers_prize": "wh2_treasure_hunt_2",
    "press_gang_night": "elector_politics",
    "smugglers_cut": "wh2_treasure_hunt_3",
    "open_the_sealed_door_lost": "under_empire_destroyed",
    "open_the_sealed_door_won": "nemesis_crown",
    "point_them_at_each_other": "story_panels/chd_drill_machinations",
    "poison_their_wells": "wh2_disease_attrition",
    "quell_the_unrest": "faction",
    "raise_the_settlement": "elector_confederation",
    "ransom_the_captain": "messenger",
    "sap_their_garrison": "elector_invasion",
    "sell_their_secrets": "story_panels/chd_pet_blood",
    "send_gifts": "messenger",
    "share_the_find": "elector_diplomacy",
    "spread_the_plague": "ai_enters_nurgle_realm",
    "spy_on_their_capital": "wh2_treasure_hunt_2",
    "stir_their_rebels": "elector_politics",
    "touch_the_relic_blessed": "army_morale_up",
    "touch_the_relic_cursed": "nemesis_crown",
    "wake_the_guardian_lost": "chaos_rising",
    "wake_the_guardian_won": "wh2_treasure_hunt_3",
}

# Loc file of the strings the script reads at runtime: the taken missions' lines.
STRINGS_LOC = LOC_PREFIX + "spot_strings.loc.tsv"

# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Text helpers

# Key prefix of the spot offers' own effect bundles.
SPOT_BUNDLE = "land_enc_effect_spot_"

# Key prefix of the tower's effect bundles. The name after it is a one-battle bundle's notice.
TOWER_BUNDLE = "land_enc_effect_tower_"

# Offer fields that put a bundle on something: { bundle, turns }, or for the battle offers and the tower the bundle key alone.
BUNDLE_FIELDS = ("army_bundle", "faction_bundle", "province_bundle", "region_bundle", "target_faction_bundle", "battle_bundle", "enemy_bundle", "effect_bundle",
                 "ally_bundle")


def stat(value: str, icon: str, name: str, colour: str = "green") -> str:
    """Writes a stat change the way tower lines do: the coloured value, the stat's icon, then its name.

    Args:
        value (str): The change, e.g. "+10".
        icon (str): The stat icon's file stem under ui/skins/default/, e.g. "icon_stat_attack".
        name (str): The stat's name, e.g. "melee attack".
        colour (str): The value's colour.

    Returns:
        str: The loc text.
    """
    return f"[[col:{colour}]]{value}[[/col]] [[img:ui/skins/default/{icon}.png]][[/img]] {name}"


ATTACK = ("icon_stat_attack", "melee attack")
DEFENCE = ("icon_stat_defence", "melee defence")
LEADERSHIP = ("icon_stat_morale", "leadership")
SPEED = ("icon_stat_speed", "speed")
CHARGE = ("icon_stat_charge_bonus", "charge bonus")
ARMOUR = ("icon_stat_armour", "armour")
WEAPON = ("icon_stat_damage", "weapon strength")
MISSILE = ("icon_stat_ranged_damage", "missile damage")
RELOAD = ("icon_stat_reload_time", "faster reloads")

# The line under every offer the treasury cannot pay: (icon, text).
UNAFFORDABLE = ("treasury.png", "[[col:red]]We cannot afford this.[[/col]]")

# Start of a paid offer's line, as the tower writes "Pay N gold from the haul to".
PAY = "Pay [[col:yellow]]{cost} gold[[/col]] from our treasury to "

# Start of a mission's line, as the tower writes its missions.
MISSION = "[[col:yellow]]Mission:[[/col]] "

# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Text

# Site key -> (title, description).
SITES = {
    "hidden_tomb": ("Hidden Tomb",
                    "A forgotten tomb lies half-buried in the hillside, its door split by roots and time. Our scouts found it by "
                    "chance.\\\\n\\\\nThe wards carved into the stone are old, but not all of them have failed. The air at the threshold is colder "
                    "than it should be.\\\\n\\\\nWhatever was laid to rest here was buried with care, and with wealth. Something inside still "
                    "remembers how to bite."),
    "abandoned_camp": ("Abandoned Camp",
                       "Cold fires and empty tents stand in a sheltered hollow. The ashes are grey and long dead, and the canvas flaps loose in the "
                       "wind.\\\\n\\\\nWhoever camped here left in a hurry. Bedrolls lie where they were dropped, and a cookpot still hangs over the "
                       "fire pit. There are no bodies and no sign of a fight, only boot prints leading away in every direction.\\\\n\\\\nThey left "
                       "their stores and a fair share of loot behind, and no one has come back for it."),
    "buried_relics": ("Buried Relics",
                      "Bones of something enormous jut from the churned earth. Our soldiers give them a wide berth.\\\\n\\\\nAmong them lie older "
                      "things, weapons and charms buried long before the beast ever died here. Rusted blades and cracked amulets turn up wherever "
                      "the ground is torn.\\\\n\\\\nWhoever buried them meant them to stay hidden. The beast's death has brought them back to the "
                      "surface."),
    "hidden_temple": ("Hidden Temple",
                      "A temple rises from the wilds, its walls choked with vines but its altar swept clean, as if someone still tends it. No path "
                      "leads here.\\\\n\\\\nIts keepers left long ago. The carvings on the pillars are worn smooth and the roof has fallen in "
                      "places, letting the rain onto the old stones.\\\\n\\\\nYet offerings laid here are still answered. The men speak quietly "
                      "inside, and few of them care to stay after dark."),
    "caravan_remnants": ("Caravan Remnants",
                         "A half-sacked caravan lies across the road, its wagons overturned and its goods scattered in the mud. The drivers are dead "
                         "or fled.\\\\n\\\\nThe raiders were in a hurry. They cut open sacks and smashed crates, took what they could carry and rode "
                         "off before anyone could stop them.\\\\n\\\\nThey missed more than they took. There is still plenty here for an army "
                         "willing to dig through the wreckage."),
    "whispers_of_our_god": ("A Voice in the Dream",
                            "Our lord wakes from a dream more vivid than any waking hour. The dream will not fade.\\\\n\\\\nA voice spoke in it, "
                            "offering strength for the trials ahead. It knew our lord's name, our road and the battles still to come.\\\\n\\\\nThe "
                            "voice offered many gifts, but not all of them are free. Some of its gifts come with a price, and it did not say what "
                            "that price would be."),
    "the_explorer": ("The Explorers",
                     "A band of weathered explorers shares our fire for the night. They know the land well.\\\\n\\\\nThey trade maps and tales of "
                     "the road ahead, of passes, rivers and the dangers waiting beyond them. Some of what they say is surely boasting, but much of "
                     "it rings true.\\\\n\\\\nThey ask only for safe passage in return. Few travellers are so easy to deal with in these lands."),
    "legendary_bard": ("Legendary Bard",
                       "A famous bard sits in chains in a bandit camp we have just put to flight. The bandits kept them to sing at their "
                       "fires.\\\\n\\\\nThe bard's name is known in courts and taverns far from here. Their songs travel faster than any "
                       "army.\\\\n\\\\nFreed, they promise to sing of our deeds in every hall and war camp across the land. A song like that could "
                       "carry our name a long way."),
    "ruined_shrine": ("Ruined Shrine",
                      "A burnt-out shrine stands by the road, its idols blackened and cracked. The roof has long since fallen in.\\\\n\\\\nNo one "
                      "knows who burned it. Still, small offerings lie fresh at the foot of the broken altar.\\\\n\\\\nOfferings left here may be "
                      "answered with a blessing, or with something far less kind. Our soldiers keep their distance and watch the shadows."),
    "smugglers_cache": ("Smugglers' Cache",
                        "Crates and barrels lie hidden under a false floor in a ruined barn. Our scouts found them by chance.\\\\n\\\\nTheir owners "
                        "watch us from the treeline. They are armed, but they know better than to start a fight with an army.\\\\n\\\\nThey deal in "
                        "goods and secrets, and they are open to offers. Not everything they sell is honest, but all of it is useful."),
    "beast_lair": ("Beast Lair",
                   "Something big lives in this cave. Fresh bones litter the entrance, some of them still red.\\\\n\\\\nThe stench carries on the "
                   "wind for a mile. Our horses will not go near it, and the men grow quiet as we draw close.\\\\n\\\\nA lair like this often holds "
                   "the remains of those who came before us, along with whatever they carried."),
    "old_battlefield": ("Old Battlefield",
                        "Crows wheel over an old battlefield where two armies broke each other long ago. No one came back to bury the "
                        "dead.\\\\n\\\\nWrecked war machines and unburied bones still lie half sunk in the mud. Rusted armour and broken banners "
                        "cover the ground.\\\\n\\\\nThe dead have no more use for what they left behind. Our soldiers pick their way through the "
                        "field with care."),
    "witchs_hut": ("Witch's Hut",
                   "A crooked hut squats in the marsh, thick with smoke and stranger smells. Charms of bone and feather hang from the "
                   "eaves.\\\\n\\\\nThe witch who lives here deals in pacts and curses. She knew we were coming before our scouts reached her door, "
                   "and she has been waiting for us.\\\\n\\\\nShe will offer her help, but every one of her bargains has a price. Few who deal with "
                   "her walk away unchanged."),
    "collapsed_mine": ("Collapsed Mine",
                       "A collapsed mine yawns in the hillside, its lower galleries half-flooded. Broken carts and rotten timbers block the main "
                       "shaft.\\\\n\\\\nThe deeper tunnels are still rich. Veins of ore glint in the torchlight, and the old miners left tools and "
                       "stores behind when they fled.\\\\n\\\\nThe tunnels are still deadly to anyone who lingers. The roof groans and shifts, and "
                       "the water rises a little more each day."),
    "merchants_wagon": ("Merchant's Wagon",
                        "A travelling merchant has lost the road and most of their escort. Their wagon creaks into our camp on a cracked "
                        "wheel.\\\\n\\\\nThe merchant is shaken, but they know their trade. The wagon is packed with goods from far away, some "
                        "useful, some strange, and all of it for sale.\\\\n\\\\nFar from any market and glad of any customer, they throw open their "
                        "wagon to us. Prices are fair, for once."),
    "sunken_library": ("Sunken Library",
                       "A library has sunk into the marsh, its shelves rotting in black water. Only the upper floors still stand above the "
                       "water.\\\\n\\\\nMost of the books are lost to mould and mud. Some scrolls survive, sealed in wax and lead, holding the "
                       "secrets of other realms.\\\\n\\\\nReaching them means wading into cold, deep water. Our scouts say something moves beneath "
                       "the surface."),
    "spoils_of_war": ("Spoils of War",
                      "The field is ours. Enemy dead lie in heaps, and the wounded are being gathered from the mud. The crows are already "
                      "circling.\\\\n\\\\nTheir baggage stands abandoned where they broke and ran. Wagons, weapons and supplies lie scattered across "
                      "the ground, and our soldiers are already picking through them.\\\\n\\\\nBefore we march on, there is more to take from this "
                      "victory. The men have earned it, and the enemy has no further use for it."),
    "smithy_orders": ("Work Orders",
                      "The apprentices crowd the counter with slates in hand: plate to rivet, edges to grind, runes to cut. Every order is "
                      "work for the whole army, done while we wait.\\\\n\\\\nThe Smiths' Association prices each job like any other, and the "
                      "forge takes one order from us at a time.\\\\n\\\\n[[col:yellow]]By forge level:[[/col]]\\\\n- Level 1: Heavy Plate gives "
                      "+15 armour, Honed Edges +6% weapon strength, and the runesmith cuts an army ability.\\\\n- Level 2: +20 armour, +9% "
                      "weapon strength, and a bound spell.\\\\n- Level 3: +25 armour, +12% weapon strength, a lore spell, and the cursed "
                      "masterwork is a legendary piece."),
    "tavern_bar": ("The Bar",
                   "The keeper leans on the bar beside barrels for every taste. Over at the tables, strangers are rolling dice, and a hulking "
                   "champion waits for anyone brave enough to lock arms with them.\\\\n\\\\nThe barkeep turns to us: \"What'll it "
                   "be?\"\\\\n\\\\n[[col:yellow]]By Tavern level:[[/col]]\\\\n- Level 1: the house brews (Fighting Spirits gives +5), a feast heals "
                   "half of each unit's losses, rumours cover the 3 nearest regions, and beating the champion is worth 500 experience.\\\\n- Level "
                   "2: stronger brews (+10), a feast heals three quarters of the losses, rumours cover 5 regions, and the champion is worth 750 "
                   "experience.\\\\n- Level 3: the strongest brews (+15), a feast heals every loss, rumours cover 7 regions, and the champion is "
                   "worth 1000 experience."),
}

# Shown under every site's description: the rules, said once, then the choice. Loc files store a line break as an escaped `\\n`.
SITE_FOOTER = "\\\\n\\\\n[[col:yellow]]Choose one, or walk away.[[/col]]"
# Footer of a site whose last choice is its own leave line, ending with that line's text, e.g. "go back to the common room.".
LEAVE_FOOTER = "\\\\n\\\\n[[col:yellow]]Choose one, or {}[[/col]]"

# Offer key -> (choice label, line). A line may use {cost}, {gold}, {won_gold}, {lost_gold} and {per_turn}, filled per difficulty.
OFFERS: Dict[str, Tuple[str, str]] = {
    "tomb_robbing": ("Rob the Tomb", "Rob the tomb: [[col:green]]a rare item[[/col]] and [[col:green]]+2000 experience[[/col]] for our lord, but a 1 in 3 chance the "
                     "dead follow, and our lord is struck by [[col:red]]Haunted II[[/col]]."),
    "abandoned_camp": ("Rest in the Camp", "Rest in the camp: every unit regains [[col:green]]{heal}% of its missing strength[[/col]] and our army "
                       "[[col:green]]ignores attrition[[/col]] next turn, but our army [[col:red]]cannot move again this turn[[/col]]."),
    "buried_relics": ("Dig Through the Night", "Dig through the night: [[col:green]]2 items[[/col]] from the cache, but our army [[col:red]]cannot move again "
                      "this turn[[/col]]."),
    "hidden_temple": ("Pray at the Altar", PAY + "pray at the altar: our lord's [[col:green]]worst curse is lifted[[/col]], or our lord gains "
                      "[[col:green]]Warded I[[/col]] when no curse weighs on them."),
    "caravan_remnants": ("Claim the Cargo", "Claim the cargo: [[col:green]]+{gold} gold[[/col]], [[col:green]]a random item[[/col]] and [[col:green]]+{lord_xp} "
                         "experience[[/col]] for our lord, but [[col:red]]-{relations} relations[[/col]] with the owner of this region."),
    "whispers_of_the_gods": ("Heed the Voice", "Heed the voice: our army is [[col:green]]unbreakable[[/col]] and [[col:green]]never tires[[/col]], our lord gains "
                             "[[col:green]]+250 experience[[/col]] each turn, and the named army spell is ours, all for 3 turns, but [[col:red]]-{e0} public "
                             "order[[/col]] in our nearest province for 5 turns."),
    "the_explorer": ("Hire the Explorers", PAY + "hire the explorers: [[col:green]]+{e0}% movement range[[/col]] and [[col:green]]+{e1}% ambush "
                     "defence[[/col]] for {turns} turns, and the {count} nearest regions not our own are [[col:green]]revealed for {reveal_turns} turns[[/col]]."),
    "legendary_bard": ("Patronise the Bard", PAY + "patronise the bard: [[col:green]]+5% income[[/col]] and [[col:green]]-25% construction cost[[/col]] in our "
                       "provinces, and [[col:green]]+{e0} leadership[[/col]] for our army, all for 5 turns."),

    "take_the_gold": ("Take the Gold", "Take the gold: [[col:green]]+{gold} gold[[/col]] to our treasury, but our army [[col:red]]cannot move again this "
                      "turn[[/col]] while it hauls the chests."),
    "strip_the_valuables": ("Strip the Valuables", "Strip everything of value: [[col:green]]+{gold} gold[[/col]] to our treasury, but our army is weighed down: "
                            + stat("-15", *LEADERSHIP, colour="red") + " and " + stat("-10%", *SPEED, colour="red") + " for 3 turns."),
    "pry_open_the_reliquary": ("Pry Open the Reliquary", "Pry open the reliquary: [[col:green]]a random rare item[[/col]], but the reliquary's ghost "
                               "follows, and our lord is struck by {curse}."),
    "search_every_corner": ("Search Every Corner", "Search every corner: [[col:green]]2 random items[[/col]], but our army [[col:red]]cannot move again this turn[[/col]]."),
    "the_hidden_vault": ("Open the Hidden Vault", PAY + "open the hidden vault: [[col:green]]1 unique item[[/col]]."),
    "cast_the_lots": ("Cast the Lots", "Cast the lots: a 50/50 chance of [[col:green]]a random rare item[[/col]] or [[col:red]]losing {lost_gold} gold[[/col]]."),
    "drink_from_the_spring": ("Drink from the Spring", "Drink from the spring: a 50/50 chance every unit is [[col:green]]healed to full[[/col]] or our army suffers [[col:red]]attrition for {lost_turns} turns[[/col]]."),
    "open_the_sealed_door": ("Open the Sealed Door", "Open the sealed door: a 50/50 chance of [[col:green]]1 unique item[[/col]] or our lord [[col:red]]wounded for 3 turns[[/col]]."),
    "wake_the_guardian": ("Wake the Guardian", "Wake the guardian: a 60/40 chance of [[col:green]]a random rare item[[/col]] or [[col:red]]it attacks[[/col]] and a battle starts here."),
    "touch_the_relic": ("Touch the Relic", "Touch the relic: our army gets a random [[col:green]]blessing for 5 turns[[/col]] or [[col:red]]curse for 3 turns[[/col]]."),
    "gamble_with_the_hermit": ("Gamble with the Hermit", PAY + "gamble with the hermit: a 1 in 3 chance of [[col:green]]1 unique item[[/col]]."),
    "leave_an_offering": ("Leave a Blood Offering", "Leave a blood offering: [[col:green]]+{e0}% ward save[[/col]] for our army for 5 turns, but every unit "
                          "loses [[col:red]]{bleed}% of its strength[[/col]] now."),
    "bless_the_banners": ("Bless the Banners", PAY + "bless our banners: " + stat("+{e0}", *ATTACK) + " and " + stat("+{e1}", *LEADERSHIP) + ", and "
                          "[[col:green]]Unbreakable when defending[[/col]], but " + stat("-{e2}%", *SPEED, colour="red") + " from the heavy banners, "
                          "for 5 turns."),
    "stoneskin": ("Stoneskin", PAY + "have the shrine cast a ward of living stone: [[col:green]]+{e0}% physical resistance[[/col]] for our army for 5 turns."),
    "oath_at_the_altar": ("Oath at the Altar", "Swear an oath at the altar: our lord is [[col:green]]Shrine-Sworn[[/col]] for good (" + stat("+5", *LEADERSHIP)
                          + " for our army), but its keepers [[col:red]]attack[[/col]] and a hard battle starts here."),
    "double_or_nothing": ("Double or Nothing", "Stake [[col:yellow]]{cost} gold[[/col]] from our treasury: a 50/50 chance it comes back as [[col:green]]{won_gold} gold[[/col]] "
                          "or is [[col:red]]lost[[/col]]."),
    "enchanted_steel": ("Enchanted Steel", PAY + "enchant our steel: [[col:green]]magical attacks[[/col]] for every unit for {turns} turns."),
    "dark_bargain": ("Strike a Dark Bargain", "Strike a dark bargain: our lord is [[col:green]]Daemon-Marked[[/col]] for good (" + stat("+10", *ATTACK)
                     + ", [[col:green]]+10%[[/col]] [[img:ui/skins/default/icon_stat_damage.png]][[/img]] weapon strength and " + stat("+10%", *SPEED)
                     + "), but is struck by {curse}."),
    "plague_bearer": ("Take the Cursed Hoard", "Take the cursed hoard: [[col:green]]+{gold} gold[[/col]] to our treasury, but our army suffers [[col:red]]attrition for {turns} turns[[/col]]."),
    "bloodstained_blades": ("Take the Bloodstained Blades", "Take up the bloodstained blades: " + stat("+20", *ATTACK) + ", but " + stat("-20", *DEFENCE, colour="red") + " for 5 turns."),
    "feed_the_shadows": ("Feed the Shadows", "Feed the shadows: sacrifice our [[col:red]]weakest unit[[/col]], and every other unit [[col:green]]gains 1 rank[[/col]]."),
    "daemons_deal": ("Strike a Daemon's Deal", "Strike a daemon's deal: [[col:green]]{unique} unique items[[/col]] now, but [[col:red]]{daemon_armies}[[/col]] on our capital."),
    "conscripts": ("Recruit the Survivors", "Recruit the survivors: [[col:green]]{recruits}[[/col]] of our own kind join our army now, but at "
                   "[[col:red]]25% strength[[/col]], and must replenish."),
    "hire_sellswords": ("Hire Sellswords", PAY + "hire sellswords: [[col:green]]a random tier {tiers} unit[[/col]] of our own kind joins our army now."),
    "free_the_prisoner": ("Free the Prisoner", "Free the prisoner: [[col:green]]a rank {hero_rank} hero[[/col]] joins our army, but a 1 in 3 chance the "
                          "jailers give chase and [[col:red]]a battle starts here[[/col]]."),
    "tame_the_beast": ("Tame the Beast", "Tame the beast: [[col:green]]a random tier {tiers} monster[[/col]] of our own kind joins our army now."),
    "regiment_of_renown": ("Hire a Regiment of Renown", PAY + "hire a [[col:green]]Regiment of Renown[[/col]] of our own kind: it joins our army now."),
    "salvage_a_war_machine": ("Salvage a War Machine", PAY + "salvage a war machine: [[col:green]]a random tier {tiers} war machine[[/col]] of our own kind joins our army now."),
    "buy_from_the_trader": ("Buy from the Trader", PAY + "buy from the trader: [[col:green]]a random rare item[[/col]]."),
    "recruitment_cache": ("Pay the Smugglers", PAY + "pay the smugglers: [[col:green]]-{e0}% recruitment cost[[/col]] for 5 turns."),
    "tower_dividends": ("Invest in the Caravan", PAY + "invest in the caravan: [[col:green]]+{per_turn} gold[[/col]] to our treasury each turn for 10 turns."),
    "buy_supplies": ("Buy Supplies", PAY + "buy supplies: our army [[col:green]]ignores attrition[[/col]] for {turns} turns."),
    "research_scrolls": ("Read the Scrolls", "Read the scrolls: [[col:green]]+{faction_e0}% research rate[[/col]] for 5 turns, but the heresy they "
                         "preach costs [[col:red]]-{province_e0} public order[[/col]] in our nearest province for 5 turns."),
    "ancient_tactics": ("Study the Ancient Tactics", "Study the ancient tactics: " + stat("+{e0}", *CHARGE) + " when attacking and " + stat("+{e1}%", *SPEED)
                        + ", but " + stat("-{e2}", *DEFENCE, colour="red") + ", for 5 turns."),

    "endow_the_province": ("Endow the Province", PAY + "endow our nearest region: [[col:green]]+{points} development points[[/col]]."),
    "garrison_drill": ("Garrison Drill", PAY + "drill our nearest garrison: it is [[col:green]]healed to full[[/col]] and has [[col:green]]+{e0}[[/col]] "
                       "[[img:ui/skins/default/icon_stat_attack.png]][[/img]] melee attack, [[img:ui/skins/default/icon_stat_defence.png]][[/img]] melee defence and "
                       "[[img:ui/skins/default/icon_stat_morale.png]][[/img]] leadership for {turns} turns."),
    "raise_the_settlement": ("Raise the Settlement", PAY + "raise our nearest settlement: its [[col:green]]main building goes up one level[[/col]]."),
    "quell_the_unrest": ("Quell the Unrest", "Quell the unrest: [[col:green]]+5 public order[[/col]] in our nearest province for 5 turns."),
    "bountiful_harvest": ("Bountiful Harvest", PAY + "sow a bountiful harvest: [[col:green]]+{e0} growth[[/col]] and [[col:green]]+{e1}% income[[/col]] in our nearest province for 5 turns."),
    "stir_their_rebels": ("Stir Their Rebels", PAY + "stir up rebels: the nearest enemy province has [[col:green]]-{e0} public order[[/col]] for 5 turns."),
    "poison_their_wells": ("Poison Their Wells", PAY + "poison their wells: the nearest enemy region has [[col:green]]-{e0} growth[[/col]], and its armies suffer [[col:green]]attrition[[/col]] for 5 turns."),
    "sap_their_garrison": ("Sap Their Garrison", PAY + "sap their garrison: the nearest enemy settlement's garrison drops to [[col:green]]{garrison}% strength[[/col]] and has "
                           "[[col:green]]-{e0}[[/col]] [[img:ui/skins/default/icon_stat_morale.png]][[/img]] leadership for {turns} turns."),
    "spread_the_plague": ("Spread the Plague", "Spread the plague: the 3 nearest enemy regions have [[col:green]]-5 public order[[/col]] and [[col:green]]-10 growth[[/col]] for 5 turns, but our army suffers [[col:red]]attrition for 3 turns[[/col]]."),
    "send_gifts": ("Send Gifts", PAY + "send gifts: [[col:green]]+{relations} relations[[/col]] with the nearest faction we are not at war with."),
    "spy_on_their_capital": ("Spy on Their Capital", PAY + "spy on their capital: the nearest enemy capital is [[col:green]]revealed for {reveal_turns} turns[[/col]], "
                             "and our spies count its garrison."),
    "curse_a_distant_king": ("Curse a Distant King", PAY + "curse a distant king: the faction with the most regions has [[col:green]]-{e0}% income[[/col]] for 5 turns."),
    "share_the_find": ("Share the Find", "Share the find: [[col:green]]+15% research rate[[/col]] for 5 turns, for us and every neighbour at peace with us, and [[col:green]]+{relations} relations[[/col]] with each of them."),
    "point_them_at_each_other": ("Point Them at Each Other", PAY + "set rivals against each other: the two biggest factions near us have [[col:green]]-{relations} relations[[/col]] with each other."),
    "sell_their_secrets": ("Sell Their Secrets", "Sell their secrets: [[col:green]]+{gold} gold[[/col]] to our treasury, but the nearest enemy has [[col:red]]+{relations} relations[[/col]] with our other enemies."),

    "bribe_the_guards": ("Bribe the Guards", PAY + "bribe their guards: the enemy army is [[col:green]]{weaker}% weaker[[/col]]."),
    "thin_the_ranks": ("Thin the Ranks", PAY + "thin their ranks: the enemy army fields [[col:green]]{fewer_units} fewer units[[/col]]."),
    "poison_the_stores": ("Poison the Stores", "Poison their stores: enemy units start at [[col:green]]{strength}% strength[[/col]], but word gets out: "
                          "[[col:red]]-{relations} relations[[/col]] with the nearest faction of their race."),
    "kill_the_captain": ("Kill the Lieutenants", PAY + "kill their lieutenants: the enemy army has [[col:green]]no heroes[[/col]]."),
    "lower_tiers_only": ("Keep the Veterans Away", PAY + "keep their veterans away: the enemy army has [[col:green]]tier 1-2 units only[[/col]]."),
    "strip_monsters": ("Cull the Beasts", PAY + "cull their beasts: the enemy army fields [[col:green]]no monsters or war beasts[[/col]]."),
    "strip_cavalry": ("Scatter the Herds", PAY + "scatter their riders: the enemy army fields [[col:green]]no cavalry or chariots[[/col]]."),
    "strip_missile": ("Burn the Quivers", PAY + "burn their quivers: the enemy army fields [[col:green]]no missile infantry[[/col]]."),
    "strip_artillery": ("Wreck the Engines", PAY + "wreck their war engines: the enemy army fields [[col:green]]no artillery[[/col]]."),
    "break_their_spirit": ("Break Their Spirit", PAY + "spread dread through their camp: enemy units have [[col:green]]-{e0}[[/col]] "
                           "[[img:ui/skins/default/icon_stat_morale.png]][[/img]] leadership."),
    "curse_their_blades": ("Curse Their Blades", PAY + "curse their weapons: enemy units have [[col:green]]-{e0}[[/col]] "
                           "[[img:ui/skins/default/icon_stat_attack.png]][[/img]] melee attack."),
    "cripple_their_champion": ("Cripple Their Champion", PAY + "cripple their champion: the enemy's [[col:green]]most expensive unit[[/col]] starts at "
                               "[[col:green]]{champion}% strength[[/col]]."),
    "spike_the_guns": ("Spike the Guns", PAY + "spoil their arrows and powder: enemy shooters have [[col:green]]-{e0}%[[/col]] "
                       "[[img:ui/skins/default/icon_stat_ammo.png]][[/img]] ammunition."),
    "bait_and_switch": ("Bait and Switch", PAY + "lure them into a false muster: the enemy army is [[col:red]]{stronger}% bigger[[/col]], but each of its units starts "
                        "at [[col:green]]{strength}% strength[[/col]]."),
    "last_ditch_oath": ("Last-Ditch Oath", "Swear a last-ditch oath: our lord [[col:green]]cannot die[[/col]] in this battle, but our army has "
                        + stat("-{e0}", *LEADERSHIP, colour="red") + "."),
    "lame_their_mounts": ("Lame Their Mounts", PAY + "lame their mounts: enemy cavalry and chariots have " + stat("-{e0}%", *SPEED) + " in this battle."),
    "hunters_snares": ("Hunter's Snares", PAY + "lay hunter's snares: enemy cavalry and chariots have " + stat("-{e0}", *CHARGE) + " in this battle."),
    "turn_a_traitor": ("Turn a Traitor", PAY + "turn a traitor: [[col:green]]a tier {tiers} unit[[/col]] of the enemy's kind joins our army now, and the enemy fields one unit fewer."),
    "war_rites": ("War Rites", "Hold war rites: [[col:green]]+{e0}[[/col]] [[img:ui/skins/default/icon_stat_attack.png]][[/img]] melee attack, "
                  "[[img:ui/skins/default/icon_stat_defence.png]][[/img]] melee defence and [[img:ui/skins/default/icon_stat_morale.png]][[/img]] leadership in this battle, "
                  "but the din draws more foes: the enemy army is [[col:red]]{stronger}% stronger[[/col]]."),
    "whetstones_and_oil": ("Rustbane Oil", "Oil every blade: [[col:green]]+{e0}%[[/col]] [[img:ui/skins/default/icon_stat_damage.png]][[/img]] weapon strength and "
                           "[[col:green]]+{e1}[[/col]] [[img:ui/skins/default/modifier_icon_armour_piercing.png]][[/img]] armour-piercing damage in this battle, but the oil "
                           "eats the steel: our lord is struck by {curse}."),
    "warding_sigils": ("Blood Sigils", "Paint the sigils in our own blood: [[col:green]]+{e0}% ward save[[/col]] in this battle, but every unit loses "
                       "[[col:red]]{bleed}% of its strength[[/col]] now."),
    "battle_scroll": ("Battle Scroll", PAY + "buy a battle scroll: the named army spell is ours to cast in this battle."),
    "cache_of_scrolls": ("Cache of Scrolls", PAY + "open a cache of scrolls: the named army spell is ours to cast in any battle for the next "
                         "{spell_turns} turns."),
    "fire_kissed_blades": ("Fire-Kissed Blades", PAY + "pass our blades through the braziers: [[col:green]]flaming attacks[[/col]] for every unit in this battle."),
    "iron_resolve": ("Iron Resolve", PAY + "steel our resolve: [[col:green]]+{e0}[[/col]] [[img:ui/skins/default/icon_stat_morale.png]][[/img]] leadership and "
                     "[[col:green]]immunity to fear and terror[[/col]] in this battle."),
    "drill_sergeant": ("Hard Drills", "Drive the army through hard drills: [[col:green]]+{e0}%[[/col]] [[img:ui/skins/default/icon_stat_speed.png]][[/img]] speed and "
                       "[[col:green]]+{e1}[[/col]] [[img:ui/skins/default/icon_stat_charge_bonus.png]][[/img]] charge bonus in this battle, but the army starts it "
                       "[[col:red]]Winded[[/col]]."),
    "call_the_winds": ("Call the Winds", "Call the winds: [[col:green]]+{e0} Winds of Magic[[/col]] reserve in this battle, but they do not settle afterwards: our lord "
                       "is struck by {curse}."),
    "blinding_powder": ("Blinding Powder", PAY + "hand out blinding powder: every unit's attacks [[col:green]]blind what they hit[[/col]] in this battle."),
    "hold_the_ground": ("Hold the Ground", PAY + "dig in: [[col:green]]Regeneration and Unbreakable when defending[[/col]] in this battle."),
    "berserker_brew": ("Berserker Brew", "Pass round the berserker brew: every unit gains [[col:green]]Frenzy[[/col]] in this battle, but the howling draws more "
                       "foes: the enemy army is [[col:red]]{stronger}% stronger[[/col]]."),
    "shadow_cloaks": ("Shadow Cloaks", PAY + "hand out shadow cloaks: every unit gains [[col:green]]Stalk and Vanguard Deployment[[/col]] in this battle."),
    "tireless_tonic": ("Tireless Tonic", "Drink the tonic: the army [[col:green]]never tires[[/col]] in this battle, but our lord is struck by {curse}."),
    "exhaust_their_camp": ("Exhaust Their Camp", PAY + "keep their camp awake all night: the enemy army [[col:green]]starts the battle Tired[[/col]]."),
    "smoke_screen": ("Smoke Screen", PAY + "lay a smoke screen: enemy missile units have [[col:green]]-{e0}% range[[/col]] in this battle."),
    "blood_contract": ("Blood Contract", "Sign a contract in blood: the enemy [[col:green]]lord is slain as the battle starts[[/col]], but our lord is struck by "
                       "{curse}."),
    "undermine_their_lines": ("Undermine Their Lines", "Dig tunnels under their camp: the enemy army is [[col:green]]{weaker}% weaker[[/col]], but every unit of "
                              "ours loses [[col:red]]{bleed}% of its strength[[/col]] digging them."),
    "raise_the_stakes": ("Raise the Stakes", "Raise the stakes: the enemy army is [[col:red]]{stronger}% stronger[[/col]], but a win pays "
                         "[[col:green]]{victory_gold}[[/col]]."),
    "tempt_fate": ("Tempt Fate", "Tempt fate: a [[col:yellow]]random battle modifier[[/col]], good or bad, joins this fight, and a win pays "
                   "[[col:green]]{victory_gold}[[/col]]."),
    "quartermasters_cache": ("Quartermaster's Cache", PAY + "raid the quartermaster's stores: [[col:green]]+{e0}%[[/col]] [[img:ui/skins/default/icon_stat_ammo.png]][[/img]] "
                             "ammunition and [[col:green]]{e1}%[[/col]] [[img:ui/skins/default/icon_stat_reload_time.png]][[/img]] faster reloads in this battle."),
    "tower_artillery": ("Call a Barrage", PAY + "haul in salvaged Dwarf guns: gain the [[col:green]]Zhufbar 42 Pounders[[/col]] artillery barrage army ability in this battle."),
    "allies_in_the_dark_small": ("Allies in the Dark: Small", PAY + "hire allies: [[col:green]]a small allied army[[/col]] of {ally_min} to {ally_max} units joins us in this battle."),
    "allies_in_the_dark_medium": ("Allies in the Dark: Medium", PAY + "hire allies: [[col:green]]a medium allied army[[/col]] of {ally_min} to {ally_max} units joins us in this battle."),
    "allies_in_the_dark_large": ("Allies in the Dark: Large", PAY + "hire allies: [[col:green]]a large allied army[[/col]] of {ally_min} to {ally_max} units joins us in this battle."),
    "night_raid": ("Night Raid", "Raid their camp by night: a 50/50 chance the enemy army is [[col:green]]25% weaker[[/col]] or our units start at "
                   "[[col:red]]{lost_strength}% strength[[/col]]."),

    "bottomless_quivers": ("Bottomless Quivers", PAY + "fill bottomless quivers: our missile units [[col:green]]never run out of ammunition[[/col]] in this battle."),
    "oath_of_no_retreat": ("Oath of No Retreat", PAY + "swear an oath of no retreat: our units [[col:green]]cannot rout[[/col]] in this battle."),
    "arm_the_allies": ("Arm the Allies", PAY + "arm our allies: [[col:green]]+{e0}[[/col]] [[img:ui/skins/default/icon_stat_attack.png]][[/img]] melee attack, "
                       "[[img:ui/skins/default/icon_stat_defence.png]][[/img]] melee defence and [[img:ui/skins/default/icon_stat_morale.png]][[/img]] leadership "
                       "for the allied army in this battle."),
    "rally_their_line": ("Rally Their Line", PAY + "rally their line: the allied units [[col:green]]cannot rout[[/col]] in this battle."),
    "lend_them_veterans": ("Lend Them Veterans", PAY + "lend them veterans: the allied units start [[col:green]]{ally_ranks} ranks higher[[/col]]."),
    "reinforce_the_ally_escort": ("Reinforce the Ally", PAY + "reinforce the ally: the allied escort fields [[col:green]]{extra_ally_units} more units[[/col]]."),
    "reinforce_the_ally_army": ("Reinforce the Ally", PAY + "fill the ally's war chest: the allied army has [[col:green]]{ally_stronger}% more gold[[/col]] to muster with."),
    "sacred_ground": ("Sacred Ground", PAY + "fight on sacred ground: after 3 minutes of this battle, our units regain [[col:green]]{battle_value}%[[/col]] of their "
                      "strength."),
    "divine_shield": ("Divine Shield", PAY + "raise a divine shield: our lord [[col:green]]cannot be harmed for the first {minutes} minutes[[/col]] of this battle."),
    "night_terrors": ("Night Terrors", PAY + "send night terrors: the enemy's [[col:green]]{targets}[[/col]] after 1 minute of this battle."),
    "assassinate": ("Assassinate", PAY + "send an assassin: the enemy [[col:green]]lord is slain as the battle starts[[/col]]."),

    "headhunt": ("Headhunt", MISSION + "kill the enemy lord within [[col:yellow]]6 minutes[[/col]] for [[col:green]]a random rare item[[/col]]."),
    "blood_tally": ("Blood Tally", MISSION + "kill [[col:yellow]]40%[[/col]] of the enemy's soldiers for [[col:green]]+{gold} gold[[/col]]."),
    "hold_the_line": ("Hold the Line", MISSION + "lose [[col:yellow]]no more than 2 units[[/col]] for [[col:green]]+{gold} gold[[/col]]."),
    "swift_victory": ("Swift Victory", MISSION + "win within [[col:yellow]]8 minutes[[/col]] for [[col:green]]an extra random item[[/col]] of the battle's rarity."),
    "guard_the_standard": ("Guard the Standard", MISSION + "keep [[col:yellow]]one marked unit[[/col]] alive, and it gains [[col:green]]3 ranks[[/col]]."),
    "break_them": ("Break Them", MISSION + "rout [[col:yellow]]6 enemy units[[/col]] for [[col:green]]+{gold} gold[[/col]]."),
    "trophy_hunt": ("Trophy Hunt", MISSION + "destroy the enemy's [[col:yellow]]most expensive unit[[/col]], and [[col:green]]a copy joins our army[[/col]]."),
    "silence_the_guns": ("Silence the Guns", MISSION + "destroy every enemy [[col:yellow]]missile and artillery unit within 5 minutes[[/col]] for [[col:green]]a random rare item[[/col]]."),
    "bloodbath_wager": ("Bloodbath Wager", MISSION + "wager [[col:yellow]]{cost} gold[[/col]] from our treasury and kill [[col:yellow]]75%[[/col]] of the enemy's soldiers for [[col:green]]+{gold} gold[[/col]]."),
    "duelists_challenge": ("Duellist's Challenge", MISSION + "challenge the enemy lord and [[col:yellow]]kill them in battle[[/col]] for [[col:green]]a unique item[[/col]]."),
    "spare_the_captain": ("Spare the Captain", MISSION + "win with the [[col:yellow]]enemy lord still alive[[/col]], and ransom them for [[col:green]]+{gold} gold[[/col]]."),
    "flawless_victory": ("Flawless Victory", MISSION + "win [[col:yellow]]without losing a single unit[[/col]] for [[col:green]]a unique item[[/col]]."),
    "lords_glory": ("Lord's Glory", MISSION + "our lord kills [[col:yellow]]{battle_value} enemy soldiers[[/col]] for [[col:green]]a random rare item[[/col]]."),
    "monster_slayer": ("Monster Slayer", MISSION + "destroy [[col:yellow]]every enemy monster[[/col]] for [[col:green]]+{gold} gold[[/col]]."),
    "steadfast": ("Steadfast", MISSION + "let [[col:yellow]]no unit of ours rout[[/col]] for [[col:green]]+{gold} gold[[/col]]."),
    "trial_by_fire": ("Trial by Fire", MISSION + "stake our pride: the enemy army is [[col:red]]{stronger}% stronger[[/col]], and a win means our lord gains {boon}."),
    "witch_hunt": ("Witch Hunt", MISSION + "destroy [[col:yellow]]every enemy spellcaster[[/col]] for the named army spell for the next {spell_turns} turns. "
                   "It only counts when the enemy fields a spellcaster."),
    "settle_the_grudge": ("Settle the Grudge", MISSION + "[[col:yellow]]kill the enemy lord[[/col]], and our lord gains {boon}."),
    "penance": ("Penance", MISSION + "win without [[col:yellow]]a single unit of ours routing[[/col]], and [[col:green]]our lord's worst curse is lifted[[/col]]."),
    "oath_of_victory": ("Oath of Victory", MISSION + "win within [[col:yellow]]{minutes} minutes[[/col]] and our lord gains {boon}. Fail, and our lord is "
                        "struck by {fail_curse}."),
    "decapitate": ("Decapitate", MISSION + "kill [[col:yellow]]the enemy lord and every hero[[/col]] for [[col:green]]a unique item[[/col]]."),
    "against_the_odds": ("Against the Odds", MISSION + "win [[col:yellow]]while the enemy outnumbers us[[/col]] for [[col:green]]+{gold} gold[[/col]]."),
    "rout_the_riders": ("Rout the Riders", MISSION + "rout every enemy [[col:yellow]]cavalry and chariot unit within {minutes} minutes[[/col]] for [[col:green]]a random rare item[[/col]]."),
    "untouchable": ("Untouchable", MISSION + "keep our lord [[col:yellow]]above half health[[/col]] to the end of the battle, and they earn "
                    "[[col:green]]+{lord_xp} experience[[/col]]."),
    "strip_the_dead": ("Strip the Dead", "Strip the dead: [[col:green]]+{per_unit} gold[[/col]] to our treasury for each unit in the army we beat."),
    "ransom_the_captain": ("Ransom the Captain", "Ransom their captain: [[col:green]]+{gold} gold[[/col]] to our treasury, but the nearest faction of their kind has [[col:red]]-{relations} relations[[/col]] with us."),
    "tribute_from_the_locals": ("Tribute from the Locals", "Accept tribute from the grateful locals: [[col:green]]+{per_turn} gold[[/col]] to our treasury each turn for 5 turns."),
    "loot_the_baggage": ("Loot the Baggage", "Loot their baggage train: [[col:green]]a random item[[/col]] of the battle's rarity."),
    "recruit_a_captive": ("Recruit a Captive", "Recruit a captive: [[col:green]]a random unit[[/col]] of the army we beat joins our army now."),
    "press_on": ("Press On", "Press on while they flee: [[col:green]]+50% movement range[[/col]] next turn."),
    "victory_feast": ("Victory Feast", PAY + "hold a victory feast: [[col:green]]+{e0}[[/col]] [[img:ui/skins/default/icon_stat_morale.png]][[/img]] leadership and "
                      "[[img:ui/skins/default/icon_stat_attack.png]][[/img]] melee attack for 5 turns."),
    "trophy_of_war": ("Trophy of War", "Take a trophy of war: our lord grows as a [[col:green]]Trophy Hunter[[/col]], a trait that rises with every trophy taken."),
    "chase_the_routers": ("Chase the Routers", "Chase down the routers: a 50/50 chance of [[col:green]]a random rare item[[/col]] or every unit losing "
                          "[[col:red]]10% of its strength[[/col]] in an ambush."),
    "scavenge_their_scrolls": ("Scavenge Their Scrolls", "Scavenge their scrolls: the named army spell is ours to cast in any battle for the next "
                               "{spell_turns} turns."),
    "raise_their_banner": ("Raise Their Banner", "Raise their captured banner over our camp: our lord gains {boon}, but [[col:red]]-{relations} relations[[/col]] "
                           "with the nearest faction of their race."),
    "desecrate_the_fallen": ("Desecrate the Fallen", "Strip the graves of the fallen: [[col:green]]+{gold} gold[[/col]] to our treasury, but our lord is struck by {curse}."),
    "press_the_survivors": ("Press the Survivors", "Press their survivors into service: [[col:green]]2 tier 2-3 units[[/col]] of their race join our army now, but "
                            "[[col:red]]-{relations} relations[[/col]] with the nearest faction of their race."),
    "feast_on_the_fallen": ("Feast on the Fallen", "Feast on the fallen: every unit regains [[col:green]]{heal}% of its missing strength[[/col]], but "
                            "[[col:red]]+{e0} Chaos corruption[[/col]] in every province for {turns} turns."),
    "blood_tithe": ("Blood Tithe", "Offer the blood of the living: our lord gains {boon}, and every unit loses [[col:red]]{bleed}% of its strength[[/col]] now."),
    "dark_offering": ("Make a Dark Offering", "Make a dark offering: sacrifice our [[col:red]]weakest unit[[/col]], and our lord gains [[col:green]]1 rank[[/col]] and our army [[col:green]]+5% ward save[[/col]] for 5 turns."),
    "walk_away": ("Walk Away", "Leave this place be."),
    "fighting_spirits": ("Fighting Spirits", "Order a round of fighting spirits: " + stat("+{e0}", *ATTACK) + " and " + stat("+{e1}%", *WEAPON)
                         + ", but " + stat("-{e2}", *DEFENCE, colour="red") + ", for 5 turns."),
    "shieldbrew": ("Shieldbrew", "Order a round of shieldbrew: " + stat("+{e0}", *DEFENCE) + " and " + stat("+{e1}", *LEADERSHIP)
                   + " when defending, and [[col:green]]Unbreakable when defending[[/col]] at a level 3 Tavern, but " + stat("-{e2}%", *SPEED, colour="red")
                   + ", for 5 turns."),
    "firewater": ("Firewater", "Order a round of firewater: " + stat("+{e0}%", *SPEED) + " and " + stat("+{e1}", *CHARGE) + " when attacking, and "
                  "[[col:green]]Frenzy[[/col]] for every unit, but our army starts every battle [[col:red]]Winded[[/col]], for 5 turns."),
    "marksmans_draught": ("Marksman's Draught", "Order a round of marksman's draught: " + stat("+{e0}%", *MISSILE) + " and [[col:green]]+{e1}% ammunition[[/col]], "
                          "but " + stat("-{e2}", *DEFENCE, colour="red") + ", for 5 turns."),
    "mystery_brew": ("Mystery Brew", "Try the keeper's mystery brew: maybe [[col:green]]Blinding Strikes[[/col]] (every hit blinds) for 5 turns, maybe "
                     "[[col:green]]a random army spell[[/col]] for 5 turns, or maybe a hangover of " + stat("-{lost_e0}", *LEADERSHIP, colour="red") + " and "
                     + stat("-{lost_e1}%", *SPEED, colour="red") + " for {lost_turns} turns."),
    "feast_for_the_army": ("Feast for the Army", "Lay on a feast for the army: every unit regains [[col:green]]{heal}% of its missing strength[[/col]], and our "
                           "army [[col:green]]ignores attrition[[/col]] next turn."),
    "dice_with_strangers": ("Dice with Strangers", "Roll dice with strangers: a 50/50 chance our stake comes back [[col:green]]doubled[[/col]], or now and "
                            "then as a [[col:green]]rare item[[/col]], or is [[col:red]]lost in a brawl that costs every unit {lost_bleed}% of its "
                            "strength[[/col]]."),
    "arm_wrestle_the_champion": ("Arm-Wrestle the Champion", "Arm-wrestle the house champion: a 50/50 chance our lord gains [[col:green]]+{won_xp} "
                                 "experience[[/col]] or is [[col:red]]hurt, losing half their remaining health[[/col]]."),
    "buy_rumours": ("Buy Rumours", "Buy the rumours of the road: the {count} nearest regions not our own are [[col:green]]revealed for {reveal_turns} "
                    "turns[[/col]], and the keeper names the enemy armies nearby."),
    "spell_pedlar": ("The Spell Pedlar", "Buy from the spell pedlar: the named army spell is ours to cast in any battle for the next {spell_turns} turns."),
    "press_gang_night": ("Press-Gang Night", "Press-gang the drinkers: our army gains [[col:green]]{recruits}[[/col]] of our roster now, but "
                         "[[col:red]]-{e0} public order[[/col]] in our nearest province for {turns} turns."),
    "fighting_pit": ("The Fighting Pit", "Send our warriors into the fighting pit: every unit gains [[col:green]]{ranks}[[/col]], but loses "
                     "[[col:red]]{bleed}% of its strength[[/col]] now."),
    "smugglers_cut": ("The Smugglers' Cut", "Take the smugglers' cut: [[col:green]]+{e0}% income[[/col]] for {turns} turns, but [[col:red]]-{relations} "
                      "relations[[/col]] with the owner of this region."),
    "hire_a_pathfinder": ("Hire a Pathfinder", "Hire a pathfinder: [[col:green]]+{e0}% campaign movement and no attrition[[/col]] for {turns} turns, but "
                          "our army [[col:red]]cannot move this turn[[/col]]."),
    "blood_wine": ("Blood Wine", "Drink the blood wine: [[col:green]]Regeneration[[/col]] and " + stat("+{e1}", *LEADERSHIP) + " when defending for {turns} "
                   "turns, but every unit loses [[col:red]]{bleed}% of its strength[[/col]] now."),
    "tavern_back": ("Back", "Go back to the common room."),
    "wake_the_sleeping_champion": ("Wake the Sleeping Champion", "Wake the sleeping champion: [[col:red]]a battle starts here[[/col]] against a guard "
                                   "stronger than this site's, and winning it takes the champion's arms, [[col:green]]a unique item[[/col]] on top of "
                                   "the battle's loot."),
    "loot_the_desecrated_shrine": ("Loot the Desecrated Shrine", "Loot the desecrated shrine: the named army spell is ours to cast in any battle for "
                                   "the next {spell_turns} turns, but our lord is struck by {curse}."),
    "chip_the_runestone": ("Chip the Runestone", "Chip the runestone: the named army spell is ours to cast in any battle for the next {spell_turns} "
                           "turns, but the locals revere the stone, and [[col:red]]-{e0} public order[[/col]] in our nearest province for 5 turns."),
    "sign_the_mercenary_captain": ("Sign the Mercenary Captain", "Sign the mercenary captain: [[col:green]]{recruits}[[/col]] of our own kind joins "
                                   "our army now, but the captain's cut costs [[col:red]]+{e0}% upkeep[[/col]] for {turns} turns."),
    "claim_the_tainted_gold": ("Claim the Tainted Gold", "Claim the tainted gold: [[col:green]]+{gold} gold[[/col]] to our treasury, but our lord is "
                               "struck by {curse}."),
    "raise_the_old_standard": ("Raise the Old Standard", "Raise the old standard: our lord gains {boon}, but the standard draws challengers, and "
                               "[[col:red]]our next battle spot fight is {stronger}% stronger[[/col]]."),
    "loose_the_war_dogs": ("Loose the War Dogs", "Loose the war dogs: [[col:green]]+{e0}% campaign movement[[/col]] and [[col:green]]+{e1}% ambush "
                           "defence[[/col]] for 5 turns, but the beasts bite the hand that feeds them, and every unit loses [[col:red]]{bleed}% of its "
                           "strength[[/col]] now."),
    "drink_from_the_battle_well": ("Drink from the Battle Well", "Drink from the battle well: every unit gains [[col:green]]Frenzy[[/col]] and "
                                   + stat("+{e1}", *ATTACK) + " when attacking, but " + stat("-{e2}", *LEADERSHIP, colour="red") + ", for 5 turns."),
    "heavy_plate": ("Heavy Plate", "Rivet heavy plate onto the army: " + stat("+{e0}", *ARMOUR) + ", but " + stat("-{e1}%", *SPEED, colour="red")
                    + ", for 5 turns."),
    "honed_edges": ("Honed Edges", "Grind every edge thin: " + stat("+{e0}%", *WEAPON) + ", but " + stat("-{e1}", *DEFENCE, colour="red") + ", for 5 turns."),
    "barbed_arrowheads": ("Barbed Arrowheads", "Fit barbed heads to every arrow and bolt: " + stat("+{e0}%", *MISSILE) + ", but [[col:red]]-{e1}% "
                          "ammunition[[/col]], for 5 turns."),
    "shod_and_barded": ("Shod and Barded", "Shoe the mounts and bard the beasts: " + stat("+{e0}", *CHARGE) + " when attacking and "
                        + stat("+{e1}%", *SPEED) + ", but [[col:red]]+{e2}% upkeep[[/col]], for 5 turns."),
    "runesmiths_inscription": ("Runesmith's Inscription", "Have the runesmith cut a rune into our banners: the named army spell is ours to cast in "
                               "any battle for the next {spell_turns} turns."),
    "bloodforged_steel": ("Bloodforged Steel", "Quench the blade in our own blood: [[col:green]]a rare item[[/col]], but every unit loses "
                          "[[col:red]]{bleed}% of its strength[[/col]] now."),
    "cursed_masterwork": ("Cursed Masterwork", "Take the masterwork no smith will sign: [[col:green]]two rare items[[/col]], or [[col:green]]a "
                          "legendary item[[/col]] at a level 3 forge, but our lord is struck by [[col:red]]two level 3 curses[[/col]] from Creeping "
                          "Rust, Brittle Bones and Cursed Coin."),
    "smiths_blessing": ("Smith's Blessing", "Have the master smith bless our lord's arms: our lord gains [[col:green]]Ironhide or Stone "
                        "Rampart[[/col]]."),
    "smithy_back": ("Back", "Go back to the forge."),
}

# Offer key -> its line's vanilla effect-bundle icon, reusing the icons Steve picked for the matching tower offers.
# The fallback bundle icon, which a Tower battle notice does not take over from its bundle.
GARRISON_ICON = "icon_effects_fortify.png"

ICONS = {
    "tomb_robbing": "resource_gold_idols.png", "abandoned_camp": "replenishment.png", "buried_relics": "treasure_map.png",
    "hidden_temple": "temples_of_the_old_ones.png", "caravan_remnants": "convoy_icon.png", "whispers_of_the_gods": "lileaths_blessing.png",
    "the_explorer": "vision.png", "legendary_bard": "income.png", "take_the_gold": "treasury.png", "strip_the_valuables": "nor_spoils.png",
    "pry_open_the_reliquary": "hex_1.png", "search_every_corner": "cotw_track_army.png", "the_hidden_vault": "resource_gold_idols_large.png",
    "cast_the_lots": "random_recipe.png", "drink_from_the_spring": "stat_healing_received.png", "open_the_sealed_door": "concealment.png",
    "wake_the_guardian": "hellforged.png", "touch_the_relic": "fractured_mind.png", "gamble_with_the_hermit": "random_recipe.png", "double_or_nothing": "trickster_cult.png",
    "leave_an_offering": "resistance_ward_save.png", "bless_the_banners": "effect_rite.png", "stoneskin": "resistance_physical.png",
    "oath_at_the_altar": "champions_rift.png", "enchanted_steel": "magical_attacks_force.png", "dark_bargain": "chaos_gifts.png",
    "plague_bearer": "plague.png", "bloodstained_blades": "rampage_savage.png", "feed_the_shadows": "bloodreaper.png",
    "daemons_deal": "daemonic_gift.png", "conscripts": "edict_levy_conscripts.png", "hire_sellswords": "merc_contract.png",
    "free_the_prisoner": "noble.png", "tame_the_beast": "attribute_causes_terror.png", "regiment_of_renown": "champions_essence.png",
    "salvage_a_war_machine": "artillery.png", "buy_from_the_trader": "trade_agreement.png", "recruitment_cache": "military_spending.png",
    "tower_dividends": "income.png", "buy_supplies": "attrition.png",
    "research_scrolls": "technology.png", "ancient_tactics": "charge.png",
    "endow_the_province": "edict_imperial_taxation.png", "garrison_drill": "siege_defence.png", "raise_the_settlement": "exalted_hero.png",
    "quell_the_unrest": "army_morale.png", "bountiful_harvest": "income.png", 
    "stir_their_rebels": "discouraged.png", "poison_their_wells": "phase_posion.png", "sap_their_garrison": "siege_attack.png",
    "spread_the_plague": "plague.png", "send_gifts": "trade_agreement.png", "spy_on_their_capital": "cotw_reveal_shroud.png",
    "curse_a_distant_king": "hex_1.png", "share_the_find": "technology.png", "point_them_at_each_other": "subterfuge.png",
    "sell_their_secrets": "assassin.png", "walk_away": "campaign_movement.png",
    "strip_the_dead": "nor_spoils.png", "ransom_the_captain": "noble.png", "tribute_from_the_locals": "income.png", "loot_the_baggage": "treasure_map.png",
    "recruit_a_captive": "slaves.png", "press_on": "campaign_movement.png",
    "victory_feast": "effect_rite.png", "trophy_of_war": "wh3_cp1_unit_reward.png", "chase_the_routers": "cotw_track_army.png", 
    "dark_offering": "bloodreaper.png", "scavenge_their_scrolls": "magic.png", "raise_their_banner": "vow_knights_positive.png",
    "desecrate_the_fallen": "dlc10_death_night.png", "press_the_survivors": "slaves.png", "feast_on_the_fallen": "edict_ogr_feasts_for_the_strong.png",
    "blood_tithe": "bloodreaper.png", "trial_by_fire": "champions_essence.png", "witch_hunt": "magic.png", "settle_the_grudge": "rampage_harsh.png",
    "penance": "lileaths_blessing.png", "oath_of_victory": "vow_knights_positive.png",
    "bribe_the_guards": "subterfuge.png", "thin_the_ranks": "attrition.png", "poison_the_stores": "phase_posion.png",
    "kill_the_captain": "dlc10_assassination_targets.png", "lower_tiers_only": "peasant.png", "break_their_spirit": "discouraged.png",
    "strip_monsters": "rampage_harsh.png", "strip_cavalry": "charge.png", "strip_missile": "ammo.png", "strip_artillery": "artillery.png",
    "turn_a_traitor": "khainite_assassin.png", "war_rites": "effect_rite.png", "whetstones_and_oil": "weapon_damage.png",
    "battle_scroll": "magic.png", "cache_of_scrolls": "magic.png", "warding_sigils": "resistance_ward_save.png", "fire_kissed_blades": "modifier_icon_flaming.png", "iron_resolve": "attribute_immune_to_psychology.png",
    "call_the_winds": "wh3_dlc24_wind_blast.png", "quartermasters_cache": "ammo.png", "night_raid": "dlc10_death_night.png",
    "blinding_powder": "wh_dlc06_unit_contact_blinded.png", "hold_the_ground": "siege_defence.png", "berserker_brew": "rampage_savage.png",
    "shadow_cloaks": "stalk.png", "tireless_tonic": "vigour.png", "exhaust_their_camp": "attrition.png",
    "smoke_screen": "hex_1.png", "blood_contract": "dlc10_assassination_targets.png", "undermine_their_lines": "siege_attack.png",
    "raise_the_stakes": "treasury.png", "tempt_fate": "random_recipe.png",
    "bottomless_quivers": "ammo_character.png", "oath_of_no_retreat": "morale.png", "divine_shield": "lileaths_blessing.png",
    "arm_the_allies": "effect_rite.png", "rally_their_line": "morale.png", "lend_them_veterans": "vow_knights_positive.png",
    "reinforce_the_ally_escort": "trade_agreement.png", "reinforce_the_ally_army": "trade_agreement.png",
    "night_terrors": "dlc10_death_night.png", "assassinate": "assassin.png", "headhunt": "dlc10_assassination_targets.png", "blood_tally": "casualties.png",
    "hold_the_line": "siege_defence.png", "swift_victory": "vigour.png", "guard_the_standard": "vow_knights_positive.png",
    "break_them": "attribute_causes_terror.png", "trophy_hunt": "wh3_cp1_unit_reward.png", "silence_the_guns": "artillery.png",
    "curse_their_blades": "hex_1.png", "drill_sergeant": "charge.png", "tower_artillery": "siege_attack.png",
    "allies_in_the_dark_small": "trade_agreement.png", "allies_in_the_dark_medium": "trade_agreement.png", "allies_in_the_dark_large": "trade_agreement.png",
    "untouchable": "health_character.png",
    "lame_their_mounts": "attrition.png", "hunters_snares": "discouraged.png", "sacred_ground": "lileaths_blessing.png",
    "cripple_their_champion": "blood_kiss.png", "spike_the_guns": "ammo.png", "bait_and_switch": "trickster_cult.png", "last_ditch_oath": "attribute_unbreakable.png",
    "lords_glory": "rampage_savage.png", "monster_slayer": "hellforged.png", "steadfast": "morale.png", "decapitate": "nemesis_crown_sealed.png",
    "fighting_spirits": "melee.png", "shieldbrew": "armour.png", "firewater": "charge.png", "marksmans_draught": "ranged_damage.png",
    "mystery_brew": "random_recipe.png", "feast_for_the_army": "edict_ogr_feasts_for_the_strong.png", "dice_with_strangers": "trickster_cult.png",
    "arm_wrestle_the_champion": "experience.png", "buy_rumours": "wh2_dlc14_def_tzarkans_whispers.png", "tavern_back": "campaign_movement.png",
    "spell_pedlar": "magic_character.png", "press_gang_night": "peasant.png", "fighting_pit": "experience.png", "smugglers_cut": "cargo.png",
    "hire_a_pathfinder": "campaign_movement.png", "blood_wine": "bloodreaper.png",
    "wake_the_sleeping_champion": "champions_rift.png", "loot_the_desecrated_shrine": "chaos_gifts.png", "chip_the_runestone": "magic_character.png",
    "sign_the_mercenary_captain": "merc_contract.png", "claim_the_tainted_gold": "resource_gold_idols.png", "raise_the_old_standard": "morale.png",
    "loose_the_war_dogs": "campaign_movement.png", "drink_from_the_battle_well": "melee.png",
    "heavy_plate": "armour.png", "honed_edges": "weapon_damage.png", "barbed_arrowheads": "ranged_damage.png", "shod_and_barded": "charge.png",
    "runesmiths_inscription": "magic_character.png", "bloodforged_steel": "bloodreaper.png", "cursed_masterwork": "hex_1.png",
    "smiths_blessing": "resistance_physical.png", "smithy_back": "campaign_movement.png",
    "against_the_odds": "vigour.png", "rout_the_riders": "mount.png", "bloodbath_wager": "khorne_skulls.png", "duelists_challenge": "rampage_harsh.png", "spare_the_captain": "noble.png", "flawless_victory": "champions_rift.png",
}

# Line on a mission already taken on the open battle dilemma: (icon, text).
TAKEN = ("icon_blank.png", "[[col:red]]Already taken.[[/col]]")

# Mission key -> (what it asked, said when met, said when failed). Each becomes a result after a won battle.
MISSION_MESSAGES = {
    "headhunt": ("Headhunt",
                 "The enemy lord fell in time, just as we vowed. We marked them before the first arrow flew, and our best blades went looking for "
                 "them.\\\\n\\\\nThey found them in the thick of the press, and it was over quickly. The body was dragged back to our lines before "
                 "the battle had even turned.\\\\n\\\\nTheir finest possession, a rare item, now belongs to us. Let the next lord who faces us "
                 "remember whose it was.",
                 "The enemy lord lived too long, and our vow goes unfulfilled. We named our target before the battle and sent our best after them, "
                 "but they kept out of reach.\\\\n\\\\nEvery charge that should have found them struck bodyguards instead. By the time we cut a way "
                 "through, the moment had passed.\\\\n\\\\nThe soldiers know a vow was made and broken. There is no prize to show for it, only the "
                 "dead to count."),
    "blood_tally": ("Blood Tally",
                    "The enemy's soldiers fell in their hundreds, and the tally is met. We counted every corpse, and the clerks had to send for more "
                    "ink.\\\\n\\\\nOur soldiers fought for the number as much as for the field. They pressed on long after the enemy began to give "
                    "way, and the bodies piled high along the line.\\\\n\\\\nThe promised gold is counted into our treasury. It was earned in blood, "
                    "and there was plenty of it.",
                    "Too few of the enemy fell, and the tally comes up short. We swore a heavy count before the battle, but the field did not give "
                    "it to us.\\\\n\\\\nToo many of them fled, surrendered or simply stayed out of reach. The clerks walked the field twice and "
                    "found the same number both times.\\\\n\\\\nThere is no gold for a tally half met. The soldiers grumble, and the treasury stays "
                    "as it was."),
    "hold_the_line": ("Hold the Line",
                      "Our line bent but never broke, and few of our units were lost. The enemy threw everything they had at us, and each time we "
                      "pushed them back.\\\\n\\\\nThe sergeants kept the ranks tight, and the wounded were dragged to the rear before gaps could "
                      "open. When the enemy finally gave up, our banners still stood where they had started.\\\\n\\\\nThe reward for holding firm "
                      "goes straight to our treasury.",
                      "Our line held in the end, but too many of our units were lost along the way. We kept the field, but the cost was higher than "
                      "we promised.\\\\n\\\\nWhole companies were ground down where the fighting was worst. The gaps were filled, then filled again, "
                      "until there was little left to fill them with.\\\\n\\\\nA victory bought this dearly earns no reward. Tonight the army counts "
                      "its dead instead of its coin."),
    "swift_victory": ("Swift Victory",
                      "The battle was over almost before it began. Our first charge struck hard, and the enemy never found their feet.\\\\n\\\\nBy "
                      "the time their rear ranks knew what was happening, their front had already broken. The rest ran without waiting to be "
                      "told.\\\\n\\\\nWord of the swift victory spreads, and an extra item comes our way. Those who hear the story will think twice "
                      "before standing against us.",
                      "The battle dragged on too long for the victory to be called swift. We hoped to break them in the first clash, but they held "
                      "longer than anyone expected.\\\\n\\\\nThe fighting wore on through the day, line pushing against line. We won in the end, but "
                      "nobody will tell this one as a quick affair.\\\\n\\\\nThere is no extra item for a slow grind, only tired soldiers and a long "
                      "night of burying the dead."),
    "guard_the_standard": ("Guard the Standard",
                           "The marked unit stood firm through the worst of the fighting. The enemy saw where our attention lay and sent wave after "
                           "wave against them.\\\\n\\\\nThey gave ground when they had to and took it back when they could. When the dust settled, "
                           "they were still standing, bloodied but unbroken.\\\\n\\\\nThey return as hardened veterans, 3 ranks the wiser. The rest "
                           "of the army looks at them differently now.",
                           "The marked unit was lost in the fighting, and their sacrifice earns no reward. We set them a hard task, and they were "
                           "swallowed by it.\\\\n\\\\nThe enemy found them early and did not let go. Help was sent, but it came too late to "
                           "matter.\\\\n\\\\nTheir names will be read out at the fire tonight. The army will remember them, even if there is nothing "
                           "else to show for it."),
    "break_them": ("Break Them",
                   "Unit after unit of theirs broke and fled before us. We pressed every wavering line until it gave, and then we pressed the "
                   "next.\\\\n\\\\nThe enemy's officers shouted themselves hoarse trying to rally them. It did no good. Their courage ran out long "
                   "before their numbers did.\\\\n\\\\nEvery one that ran adds to the purse we were promised. The field is littered with dropped "
                   "shields and abandoned banners.",
                   "Too few of their units broke, and they fought on to the bitter end. We hoped to send them running, but they would not "
                   "run.\\\\n\\\\nEach company held its ground until it was cut down where it stood. It was a grim day's work, and slower than "
                   "anyone wanted.\\\\n\\\\nThe purse we were promised stays closed. Stubborn foes make for poor pay, however well we fought."),
    "trophy_hunt": ("Trophy Hunt",
                    "Their finest unit fell to our blades. We picked them out before the battle and went after them with everything we "
                    "had.\\\\n\\\\nThey fought hard, as their name promised, but in the end they broke like any other. Those left alive threw down "
                    "their weapons rather than die.\\\\n\\\\nThe survivors are pressed into our service, and a fresh unit of their kind now marches "
                    "with our army. They will learn to fight under our banner.",
                    "Their finest unit survived the battle, and the trophy slips through our fingers. We marked them early, but they were never "
                    "where we struck.\\\\n\\\\nThey fell back in good order while the rest of their army took the blows. When the day ended, they "
                    "were still together and still dangerous.\\\\n\\\\nThere will be no new recruits from their ranks this time. We will have to "
                    "meet them again."),
    "silence_the_guns": ("Silence the Guns",
                         "Their guns fell silent before they could do much harm. We sent our fastest units straight at the batteries while the rest "
                         "of the army held the line.\\\\n\\\\nThe crews barely had time to reload before we were among them. Few of them lived to "
                         "see the end of the battle.\\\\n\\\\nPicking through the wrecked carriages, we find a rare item. Their gunners will not be "
                         "needing it now.",
                         "Their guns kept firing for too long, and the mission has failed. Every attempt to reach the batteries was torn apart "
                         "before it got close.\\\\n\\\\nShot after shot ploughed through our ranks. By the time the guns finally stopped, the damage "
                         "was done and the field was full of our dead.\\\\n\\\\nThere is nothing to salvage from the wreckage this time. We will "
                         "remember the sound of those guns."),
    "bloodbath_wager": ("Bloodbath Wager",
                        "The field ran red, and the wager is won. We staked our gold on a slaughter, and our soldiers gave us one.\\\\n\\\\nThe "
                        "enemy dead lie thick across the ground, more than anyone dared to hope for before the battle. Crows have gathered from "
                        "miles around.\\\\n\\\\nThe gold comes back to us many times over. Not a bad return for a day's grim work.",
                        "Too few of the enemy fell, and the gold we wagered is lost. We bet on a slaughter, and the enemy would not "
                        "oblige.\\\\n\\\\nThey fell back too soon, or held too well, and the count never climbed high enough. The bookkeepers shake "
                        "their heads over the ledger.\\\\n\\\\nThe gold is gone, and there is nothing to show for it. Next time, perhaps, we will "
                        "bet more carefully."),
    "duelists_challenge": ("Duellist's Challenge",
                           "Our lord met theirs blade to blade and struck them down. The fighting nearby slowed as soldiers on both sides turned to "
                           "watch.\\\\n\\\\nIt was not a clean fight, and our lord did not come away unmarked. But when it ended, only one of them "
                           "was still standing.\\\\n\\\\nA unique item is pried from the fallen lord's grip. It is ours now, and our lord carries "
                           "the tale with it.",
                           "Our lord did not slay theirs, and the challenge goes unanswered. We sought them out on the field, but the duel never "
                           "ended as it should.\\\\n\\\\nPerhaps the press of bodies kept them apart. Perhaps another blade found the enemy lord "
                           "first. Either way, the deed was not done by our lord's hand.\\\\n\\\\nThe soldiers will not sing of this one. There is "
                           "no prize for a challenge left unmet."),
    "spare_the_captain": ("Spare the Captain",
                          "Their lord was taken alive, just as we planned. We held back our heaviest blows and let the fight wear them down until "
                          "they could no longer resist.\\\\n\\\\nThey were dragged from the field in chains, bruised and furious. Their people paid "
                          "quickly, as people do when a lord's life is on the line.\\\\n\\\\nThe ransom has been paid, and the gold is ours.",
                          "Their lord fell in the fighting, so there is no one left to ransom. We meant to take them alive, but the battle had other "
                          "ideas.\\\\n\\\\nIn the crush of the melee, someone struck too hard, or too soon. By the time word reached the front, the "
                          "lord was already dead.\\\\n\\\\nA corpse fetches no ransom, and their people will not pay for a body. The gold we hoped "
                          "for will never come."),
    "lords_glory": ("Lord's Glory",
                    "Our lord carved through the enemy ranks, and the tally of the slain is sung around every fire. Wherever the fighting was "
                    "thickest, our lord was there.\\\\n\\\\nSoldiers who saw it swear they lost count. The enemy learned to give our lord a wide "
                    "berth, and it did them little good.\\\\n\\\\nA rare item is taken from the field, a fitting prize for such a day.",
                    "Our lord fought well, but not well enough for the songs. The enemy kept their distance, or fell to other blades "
                    "first.\\\\n\\\\nThere was hard fighting, and our lord did their share of it. Yet the count of the slain fell short of what was "
                    "hoped for.\\\\n\\\\nNo prize comes from the field this time. The minstrels will have to find another tale to tell."),
    "monster_slayer": ("Monster Slayer",
                       "Every beast they brought lies dead on the field. Some took a dozen spears to bring down, and some took more.\\\\n\\\\nThe "
                       "ground shook while they lived, and our soldiers paid in blood to put them down. When the last one fell, a cheer went up all "
                       "along the line.\\\\n\\\\nThe bounty on such creatures is paid to us in full. The carcasses will feed the crows for weeks.",
                       "Some of their beasts still live, and the hunt is unfinished. We set out to kill every monster they brought, but not all of "
                       "them fell.\\\\n\\\\nThe survivors limped away bleeding or were driven off before we could finish them. Their roars could be "
                       "heard long after the fighting ended.\\\\n\\\\nThere is no bounty for half a hunt. The beasts will heal, and we will see them "
                       "again."),
    "steadfast": ("Steadfast",
                  "Not one of our units broke, however hard the enemy pressed. Charge after charge struck our lines, and each time our soldiers "
                  "held.\\\\n\\\\nThe sergeants kept the ranks closed and the frightened in their places. Nobody turned to run, not even when the "
                  "dead piled up at their feet.\\\\n\\\\nThe promised gold reaches our treasury before the dead are buried.",
                  "One of our units broke and ran, and the vow broke with it. We swore that no one would flee, and one company could not keep that "
                  "promise.\\\\n\\\\nThe rest of the army held firm, but the rout was seen by all. It will be a long time before the others let them "
                  "forget it.\\\\n\\\\nThere is no gold for a broken vow. The treasury stays as it was."),
    "decapitate": ("Decapitate",
                   "Their lord and every one of their heroes lie dead. We hunted their leaders across the field, one after another, until none were "
                   "left to give orders.\\\\n\\\\nWithout them, the rest of their army was a mob. It broke soon after, and few of them made it "
                   "far.\\\\n\\\\nSearching the bodies, we turn up a unique item. It is a fine prize for a hard day's hunting.",
                   "Some of their leaders escaped the slaughter. We meant to cut off the head of their army, but not every blow found its "
                   "mark.\\\\n\\\\nOne or more of them slipped away in the confusion, guarded by loyal troops or simply lucky. They will lead again, "
                   "and they will remember us.\\\\n\\\\nThere is no prize for a hunt left unfinished. We will meet the survivors again, and next "
                   "time they will not be so lucky."),
    "against_the_odds": ("Against the Odds",
                         "Outnumbered, we fought and won all the same. They came at us with more soldiers than we had, and they expected an easy "
                         "day.\\\\n\\\\nThey did not get one. Our army held its ground and made them pay for every step, until their numbers counted "
                         "for nothing.\\\\n\\\\nThe promised gold is paid out, and the soldiers who earned it toast the victory. Few armies would "
                         "have stood their ground that day.",
                         "We did not face the odds we swore to beat. The vow was to fight a stronger army, but the enemy we met was not strong "
                         "enough to test it.\\\\n\\\\nWe may have won, but a win against an equal or weaker foe was not what we swore. The odds were "
                         "never against us.\\\\n\\\\nThere is no gold for a challenge that never came. The vow goes unfulfilled, and the soldiers "
                         "feel cheated of their glory."),
    "rout_the_riders": ("Rout the Riders",
                        "Their riders scattered before us in time. We met every charge with spears and arrows until their mounts would not face us "
                        "any longer.\\\\n\\\\nThe last of them wheeled away in a panic, leaving the dead and the dying behind. Loose mounts ran wild "
                        "across the field.\\\\n\\\\nAmong the abandoned saddles we find a rare item. Its owner left in too much of a hurry to take "
                        "it with them.",
                        "Their riders held their nerve for too long. We tried to break them, but every charge they made came on as hard as the "
                        "last.\\\\n\\\\nOur spears held them off, but they did not run when we needed them to. By the time they finally pulled back, "
                        "it was too late.\\\\n\\\\nThere is nothing to pick from their saddles this time. They rode away with everything they "
                        "brought, and our losses are all we have to count."),
    "untouchable": ("Untouchable",
                    "Our lord came through the thick of the fighting barely scratched, and the army will not stop talking about it. Blades and "
                    "arrows seemed to turn aside.\\\\n\\\\nSoldiers who fought nearby swear they saw blows that should have killed. Our lord walked "
                    "away from every one of them.\\\\n\\\\nThe day's fighting has taught our lord a great deal, lessons that will serve well in the "
                    "battles ahead.",
                    "Our lord took too many wounds for the vow to hold. The vow was to come through the battle unharmed, and the enemy made sure it "
                    "did not happen.\\\\n\\\\nOur lord fought on through the blood and the pain, but the surgeons have plenty of work "
                    "tonight.\\\\n\\\\nThere is nothing to show for it this time, only scars and the memory of a promise that could not be kept."),
    "flawless_victory": ("Flawless Victory",
                         "Not a single unit of ours was lost. The enemy struck at us again and again, and every company came home.\\\\n\\\\nThe "
                         "sergeants called the roll after the battle and found every banner still in its place. Few armies can say as "
                         "much.\\\\n\\\\nSongs of the flawless victory spread far, and a unique item is ours. It is a rare day when war asks nothing "
                         "of us.",
                         "One of our units fell before the end, and there will be no songs of a flawless victory. We came close, but close does not "
                         "count.\\\\n\\\\nThe enemy found one company and did not let go until it was gone. The rest of the army fought on and won "
                         "the day, but the loss stands.\\\\n\\\\nThere is no prize this time, only the names of the fallen. They will be remembered, "
                         "even if no songs are sung."),
    "trial_by_fire": ("Trial by Fire",
                      "They came at us with more than we had bargained for, and we beat them all the same. Every soldier who stood in that line will "
                      "tell the story for years.\\\\n\\\\nThe enemy outnumbered us and outweighed us, and still they broke first. It was a close "
                      "thing, closer than anyone wants to admit.\\\\n\\\\nSomething of that day stays with our lord now: a boon earned in fire, "
                      "carried into every fight to come.",
                      "The trial was too much for us this time. We staked our pride on a fight against a stronger army, and the gods of war were not "
                      "watching.\\\\n\\\\nThe enemy was every bit as strong as we feared. They pushed us back step by step until there was nothing "
                      "left to give.\\\\n\\\\nThere is no boon to show for it, only the dead to bury and a lesson to remember. Next time, we will "
                      "choose our fights with more care."),
    "witch_hunt": ("Witch Hunt",
                   "Every one of their spellcasters lies dead on the field, and their tools of the trade are ours. We hunted them down one by one "
                   "while the battle raged around them.\\\\n\\\\nAmong the burned robes and broken staves, our scholars find a scroll still intact. "
                   "Its power is ours to call on in the battles to come.\\\\n\\\\nWhoever wrote it will not miss it. Their kind should think hard "
                   "before casting against us again.",
                   "Some of their spellcasters slipped away from the fighting. Whatever secrets they carried went with them, and the hunt comes up "
                   "empty.\\\\n\\\\nWe pressed hard to reach them, but they kept behind their soldiers and fled when the line began to fail. None of "
                   "our riders could catch them.\\\\n\\\\nThe scrolls we hoped to take will burn in some other army's campfire."),
    "settle_the_grudge": ("Settle the Grudge",
                          "Their lord fell to our blades, and the grudge is settled in blood. The old debt has been paid in full.\\\\n\\\\nOur lord "
                          "walked the field afterwards and learned exactly where their kind are weakest. That knowledge will not be "
                          "forgotten.\\\\n\\\\nTheir race will pay for it in every battle to come. The soldiers have already begun to tell the tale, "
                          "and it grows in every telling.",
                          "Their lord lived through the battle, and the grudge stays unsettled. We came for them, and they slipped "
                          "away.\\\\n\\\\nOur soldiers grumble that the debt is still owed. Some of them have already started sharpening their "
                          "blades for the next time.\\\\n\\\\nPerhaps the next meeting will end differently. Our lord has not forgotten, and neither "
                          "have we."),
    "penance": ("Penance",
                "Not one of our units broke, however hard the enemy pressed. The army held firm as a body, and something dark that clung to our lord "
                "has let go.\\\\n\\\\nThe worst of the curses on our lord is lifted, and the camp breathes easier tonight.\\\\n\\\\nThe priests say "
                "the penance has been accepted. Whatever was owed has been paid in blood and sweat, and our lord stands a little straighter for it.",
                "One of our units broke and ran, and the penance was not paid. Whatever darkness clings to our lord stays where it is for "
                "now.\\\\n\\\\nThe rest of the army held, but one broken company was enough. The soldiers avoid our lord's tent "
                "tonight.\\\\n\\\\nThe priests say there will be other chances to make amends. Until then, the curse goes with us into every battle."),
    "oath_of_victory": ("Oath of Victory",
                        "The battle was won before the sun had moved, just as our lord swore it would be. The army roared the oath back at its lord "
                        "as the enemy fled. The enemy never had time to form a proper line.\\\\n\\\\nOur lord carries a boon from that day, won by "
                        "keeping a promise few would dare to make. The soldiers will speak of it for a long time.\\\\n\\\\nAn oath kept in battle is "
                        "worth more than gold.",
                        "Our lord swore a swift victory and could not deliver it. The enemy held, and the fighting dragged on long after the time "
                        "our lord had promised.\\\\n\\\\nThe soldiers saw the oath broken, and they will not forget. Some of them mutter that such "
                        "vows should not be made lightly.\\\\n\\\\nA curse now follows our lord, a mark of the promise that was not kept. It will "
                        "not lift easily."),
}

# Battle objectives this script owns, for the missions added after the tower's hand-written ones: name -> (panel text, banner).
MISSION_OBJECTIVES = {
    "spare_the_captain": ("Spare the Captain: keep the enemy lord alive", "Spare the Captain: win with the enemy lord still alive."),
    "flawless_victory": ("Flawless Victory: our units lost", "Flawless Victory: win without losing a single unit."),
    "lords_glory": ("Lord's Glory: enemy soldiers our lord has slain", "Lord's Glory: our lord must slay enough of the enemy."),
    "monster_slayer": ("Monster Slayer: enemy monsters left", "Monster Slayer: destroy every enemy monster."),
    "steadfast": ("Steadfast: keep every unit of ours from routing", "Steadfast: no unit of ours may rout."),
    "trial_by_fire": ("Trial by Fire: win against the stronger army", "Trial by Fire: win against the stronger army."),
    "witch_hunt": ("Witch Hunt: enemy spellcasters left", "Witch Hunt: destroy every enemy spellcaster."),
    "settle_the_grudge": ("Settle the Grudge: slay the enemy lord", "Settle the Grudge: kill the enemy lord."),
    "penance": ("Penance: keep every unit of ours from routing", "Penance: no unit of ours may rout."),
    "oath_of_victory": ("Oath of Victory: seconds left to win", "Oath of Victory: win within 8 minutes."),
    "decapitate": ("Decapitate: enemy lord and heroes left", "Decapitate: kill the enemy lord and every hero."),
    "against_the_odds": ("Against the Odds: win while outnumbered", "Against the Odds: win while the enemy outnumbers us."),
    "rout_the_riders": ("Rout the Riders: enemy cavalry and chariots still fighting", "Rout the Riders: rout every enemy cavalry and chariot unit within 6 minutes."),
}

# Battle notice name -> (colour, text) the battle script shows for a pre-battle offer: red for what weakens the enemy, green for our help,
# yellow for a cost to our army, as the tower's notices do. A one-battle bundle uses the tower's own notice.
NOTICES = {
    "sacred_ground_now": ("green", "Sacred Ground takes hold: our units regain {battle_value}% of their strength!"),
    "arm_the_allies": ("green", "Arm the Allies: our allies have +{e0} [[img:ui/skins/default/icon_stat_attack.png]][[/img]]"
                       "[[img:ui/skins/default/icon_stat_defence.png]][[/img]][[img:ui/skins/default/icon_stat_morale.png]][[/img]]."),
    "rally_their_line": ("green", "Rally Their Line: our allies cannot rout."),
    "lend_them_veterans": ("green", "Lend Them Veterans: our allies start {ally_ranks} ranks higher."),
    "reinforce_the_ally_escort": ("green", "Reinforce the Ally: our allied escort fields {extra_ally_units} more units."),
    "reinforce_the_ally_army": ("green", "Reinforce the Ally: our allies' army was raised with {ally_stronger}% more gold."),
    "night_raid_won": ("red", "Night Raid: the enemy army is 25% weaker."),
    "night_raid_lost": ("yellow", "Night Raid: our units start at {lost_strength}% strength."),
    "exhaust_their_camp": ("red", "Exhaust Their Camp: the enemy starts the battle Tired."),
    "smoke_screen": ("red", "Smoke Screen: enemy missile units have -{e0}% range."),
    "undermine_their_lines": ("red", "Undermine Their Lines: the enemy army is {weaker}% weaker."),
    "raise_the_stakes": ("yellow", "Raise the Stakes: the enemy army is {stronger}% stronger, for {victory_gold}."),
    "tempt_fate": ("yellow", "Tempt Fate: a win pays {victory_gold}."),
}

# Notice -> its offer, for a notice not named after its offer. The notice shows that offer's numbers and line icon.
NOTICE_OFFERS = {"night_raid_won": "night_raid", "night_raid_lost": "night_raid", "sacred_ground_now": "sacred_ground"}

# Second line under Avoid on every battle dilemma, since avoiding fires the category's avoidance incident.
AVOID_CONSEQUENCES = ("avoid_consequences", "random_recipe.png", "[[col:yellow]]This may have unforeseen consequences.[[/col]]")



# Message suffix after `spot_` -> (title, subtitle, description). Realm messages have no subtitle: their {place} is the target region's name,
# or the target faction's when it holds no region. Each is also a result incident, which shows only the title and description, with the
# place highlighted.
MESSAGES = {
    "wake_the_sleeping_champion_won": ("Wake the Sleeping Champion", "The Champion's Arms",
                                       "The sleeping champion's guard is broken, and the last of them falls across the threshold of the tomb. Our "
                                       "warriors stand panting among the dead.\\\\n\\\\nBeyond them the champion lies on a bier of black stone, "
                                       "still and silent, armed and armoured as if for one last battle that never came.\\\\n\\\\nOur lord takes "
                                       "the champion's arms. Whoever this was, they were a legend in their day, and their weapons have lost none of "
                                       "their edge."),
    "chip_the_runestone": ("Chip the Runestone", "",
                           "A great runestone stands alone on a hill, its carvings worn but still humming with old power. Our runesmiths chip "
                           "away a shard, and the power comes with it.\\\\n\\\\nBut the stone was revered by the people of {place}, who "
                           "left offerings at its foot for generations. Word of what we did has spread.\\\\n\\\\nThe shard's power is ours "
                           "to call on in battle for a while. The people's anger will take longer to fade."),
    "free_the_prisoner_freed": ("Free the Prisoner", "A Debt of Honour",
                                "Our scouts find a prisoner chained in a hidden cell, thin and bloodied but still defiant. The jailers are nowhere "
                                "to be seen.\\\\n\\\\nThe chains are struck off, and the prisoner swears to fight for us in thanks. It turns out "
                                "they are no common soldier, but a seasoned hero of our own kind.\\\\n\\\\nWe slip away before the jailers "
                                "return, with one more blade in our ranks and a debt of honour paid in full."),
    "free_the_prisoner_chased": ("Free the Prisoner", "The Jailers Return",
                                 "Our scouts find a prisoner chained in a hidden cell, and the chains are struck off. The prisoner, a seasoned hero "
                                 "of our own kind, swears to fight for us.\\\\n\\\\nBut the jailers were not far. Horns sound from the "
                                 "hills, and armed men pour down toward the cell to take back what is theirs.\\\\n\\\\nThere is no time "
                                 "to slip away. Our lord turns the army to meet them, with the freed hero already at the front."),
    "research_scrolls": ("Read the Scrolls", "",
                         "The scrolls found at the site are full of strange learning. Our scholars pore over them by candlelight and can "
                         "hardly be made to sleep.\\\\n\\\\nBut the scrolls preach as much as they teach, and word of their teachings "
                         "has reached {place}. The priests there call it heresy, and the people listen to them.\\\\n\\\\nOur research "
                         "runs faster for a while. The province will be harder to keep calm until the talk dies down."),
    "tomb_robbing_spared": ("Hidden Tomb", "A Tomb Robbed",
                            "One of our soldiers falls through a crack in the earth and lands in a great buried tomb. He shouts up from the dark that "
                            "he is unhurt, and that there is more down there than dust.\\\\n\\\\nMore are sent down with torches and ropes, and they "
                            "come back laden with grave goods. Gold cups, old blades and painted urns are hauled up one by one.\\\\n\\\\nOur lord "
                            "takes the pick of them, and learns much from the carvings on the walls. Whoever built this place knew things about war "
                            "that the living have forgotten."),
    "tomb_robbing_haunted": ("Hidden Tomb", "The Dead Follow",
                             "One of our soldiers falls through a crack in the earth and lands in a great buried tomb. More are sent down with torches "
                             "and ropes, and they come back laden with gold cups, old blades and painted urns.\\\\n\\\\nOur lord takes the pick of "
                             "them and studies the carvings on the walls long into the night.\\\\n\\\\nBut something follows the last man up the "
                             "rope. The camp's fires burn low and cold, and our lord wakes to whispers in a tongue no one living speaks."),
    "abandoned_camp": ("Abandoned Camp", "Rest and Recovery",
                       "Our vanguard finds an abandoned camp hidden between the hills, its tents still pitched and its stores still full. There is "
                       "no sign of a fight, and no sign of where its owners went.\\\\n\\\\nWe check it for traps and find none. No poisoned "
                       "water, no loose earth, no tripwires in the grass. Whoever left did so in a hurry.\\\\n\\\\nSo the army stays the night "
                       "and rests. The wounded are tended, the soldiers eat well for once, and they sleep under canvas someone else carried here."),
    "buried_relics": ("Buried Relics", "Two Prizes",
                      "A strange noise draws our scouts to a ruined village. The houses are empty shells and the well is dry, but the sound comes "
                      "again from beneath the old meeting hall.\\\\n\\\\nWhen the floor is cleared, a passage opens into the earth. The army "
                      "camps while our scouts dig through every tunnel by torchlight, all through the night.\\\\n\\\\nBy dawn they have "
                      "brought up two prizes worth the taking. We leave the dead to their rest and march on, a day behind."),
    "hidden_temple": ("Hidden Temple", "A Night at the Altar",
                      "Deep in the ruins of an old city, one temple still has its roof and its doors. The streets around it are broken and "
                      "overgrown, but nothing has touched the inside.\\\\n\\\\nOur lord keeps vigil there for a night and a day, alone before "
                      "the old altar, while the army waits in the rubble outside.\\\\n\\\\nWhen our lord walks out, the shadow that followed "
                      "them is gone. If nothing troubled our lord, the temple's calm settles over them like a ward instead."),
    "caravan_remnants": ("Caravan Remnants", "Cargo Claimed",
                         "Smoke rises not far from our camp. Our scouts ride out to find the cause and come back with grim news.\\\\n\\\\nA "
                         "caravan has been attacked but not fully sacked. Its guards lie dead around the wagons, and much of the cargo is still "
                         "whole.\\\\n\\\\nWe take what was left behind. But the crests on the wagons are known in these lands, and word of who "
                         "took the cargo will reach their owners soon."),
    "whispers_of_the_gods": ("A Voice in the Dream", "The Voice Heeded",
                             "Our lord's sleep is broken by a dream more vivid than any waking hour. There is no sound of the camp, no wind, only a "
                             "great darkness and a voice within it.\\\\n\\\\nThe voice speaks of strength and of trials to come, and teaches "
                             "our lord words of power. By morning the whole army fights as if nothing in the world could break it.\\\\n\\\\nBut "
                             "the tale has spread to our lands as well, and the faithful at home fear the voice that spoke in our lord's dream."),
    "the_explorer": ("The Explorers", "Maps of the Land",
                     "A band of explorers asks to travel under the protection of our weapons until the road grows safer. They are worn and few, "
                     "and they ask a fair price for what they know.\\\\n\\\\nWe pay it. In return they share their maps and their hard-won "
                     "knowledge of the land: the dry fords, the short paths, and the places best avoided.\\\\n\\\\nOur march grows swifter "
                     "and surer for it, and the lands around us are laid bare."),
    "legendary_bard": ("Legendary Bard", "A Song of Our Deeds",
                       "A desperate rider begs us to save their village from a slaver raid. We arrive in time, and the captives are freed from "
                       "their chains.\\\\n\\\\nAmong them is a famous bard, thin and bruised but still in good voice. For a patron's purse, "
                       "the bard swears to sing of our deeds in every hall and market across the land.\\\\n\\\\nThe songs travel faster than "
                       "we do. Builders work cheaper for a famous lord, trade comes easier, and our soldiers march a little prouder."),
    "cast_the_lots_won": ("Cast the Lots", "Fortune Smiles",
                          "The lots tumble from the cup and fall in our favour. A cheer goes up from the soldiers crowded round the table, and a few "
                          "coins change hands among them on side bets.\\\\n\\\\nThe stranger who offered the game scowls, but pays up all the same. "
                          "There are no excuses and no talk of another round.\\\\n\\\\nA rare treasure changes hands. Some of the older soldiers "
                          "mutter that luck like this is never free, but for now the treasure is ours."),
    "cast_the_lots_lost": ("Cast the Lots", "Fortune Frowns",
                           "The lots fall against us, as they so often do for newcomers. The soldiers watching groan, and one of them swears the cup "
                           "tipped before the throw.\\\\n\\\\nThe stranger sweeps up our stake with a crooked grin and is gone before anyone thinks "
                           "to argue. By the time the sergeants push through the crowd, there is only an empty stool.\\\\n\\\\nIt is a hard lesson, "
                           "and an expensive one. Next time, someone says, we bring our own cup."),
    "drink_from_the_spring_won": ("Drink from the Spring", "Healing Waters",
                                  "The water runs cold and clear from the rock. Our scouts taste it first, then call the rest of the army forward "
                                  "when nothing ill befalls them.\\\\n\\\\nWounds close and tired limbs grow strong again as the whole army drinks "
                                  "its fill. Soldiers who limped into camp now stand without a stick, and the surgeons find they have little to "
                                  "do.\\\\n\\\\nEvery flask and skin is filled before we march on. Whatever power lies in this place, it was kind to "
                                  "us today."),
    "drink_from_the_spring_lost": ("Drink from the Spring", "Foul Waters",
                                   "The water tastes of rot and old iron. A few of the soldiers spit it out, but most are too thirsty to care and "
                                   "drink deep.\\\\n\\\\nWithin hours sickness spreads through the camp. Soldiers double over in their tents, and "
                                   "the surgeons run short of clean cloth and patience long before nightfall.\\\\n\\\\nThe army will march weaker "
                                   "for some time. We mark the spring on our maps so that no one is fool enough to drink from it again."),
    "open_the_sealed_door_won": ("Open the Sealed Door", "A Treasure Within",
                                 "The seal breaks and the door grinds open on a chamber untouched for centuries. Stale air rolls out, thick with "
                                 "dust, and the torches gutter as we step inside.\\\\n\\\\nThe walls are carved with figures no one in the army can "
                                 "name. Nothing stirs, and no trap springs as our lord walks slowly toward the far end.\\\\n\\\\nAt its heart, on a "
                                 "bare stone plinth, lies a treasure of legend. It is lifted with care and carried out into the daylight."),
    "open_the_sealed_door_lost": ("Open the Sealed Door", "A Trap Sprung",
                                  "The seal breaks, and so does the trap behind it. Fire and stone fill the passage, and the roar of it is heard all "
                                  "the way back at the camp.\\\\n\\\\nOur lord is caught in the blast and carried from the chamber, badly wounded. "
                                  "The guards who drag the lord clear are burned and coughing, but they do not let go.\\\\n\\\\nWhatever lay beyond "
                                  "that door, it was guarded well. The chamber is choked with rubble now, and no one in the army has any wish to dig "
                                  "it out."),
    "double_or_nothing_won": ("Double or Nothing", "The Stake Doubles",
                              "The bet is called and the throw comes up in our favour. For a moment the whole room is silent, then our soldiers "
                              "burst out cheering.\\\\n\\\\nOur stake returns to the treasury doubled, counted out coin by coin under the watchful "
                              "eyes of our paymasters. Not a single piece is missing.\\\\n\\\\nThe house is not pleased about it. The owner forces a "
                              "smile and wishes us luck on the road, though it is plain we will not be welcome back soon."),
    "double_or_nothing_lost": ("Double or Nothing", "The Stake Is Lost",
                               "The bet is called and the throw turns against us. A groan goes up from the soldiers who crowded in to watch, and "
                               "someone kicks over a stool.\\\\n\\\\nOur stake is gone, swept into the house's coffers before the dice have stopped "
                               "rolling. There is no second throw, and no one offers us one.\\\\n\\\\nThe house thanks us warmly for our custom. Our "
                               "paymasters say nothing on the walk back to camp, but their faces say enough."),
    "wake_the_guardian_won": ("Wake the Guardian", "It Sleeps On",
                              "The great beast snorts and shifts its bulk, then sinks back into its slumber. Every soldier in the lair holds their "
                              "breath until the rumbling stops.\\\\n\\\\nWe creep past it on soft feet, keeping to the shadows along the walls. The "
                              "hoard is piled high, and we take only what we can carry without a sound.\\\\n\\\\nWe make off with a rare treasure "
                              "from its hoard. Only when the lair is far behind us does anyone dare to laugh about it."),
    "wake_the_guardian_lost": ("Wake the Guardian", "It Wakes!",
                               "The ground shakes as the guardian of this place rises from its slumber. Dust and loose stone rain down from the roof "
                               "of the lair as it lifts its head.\\\\n\\\\nIt sees intruders in its lair and charges. There is no time to fall back "
                               "or form proper lines, and the soldiers nearest the beast scatter before it.\\\\n\\\\nOur army must stand and fight! "
                               "The officers bellow orders over the din, and every blade we have turns to face the beast."),
    "touch_the_relic_blessed": ("Touch the Relic", "A Blessing",
                                "The relic is warm to the touch, and a soft glow spreads into the hand that holds it. One by one, the soldiers "
                                "line up to lay a hand on it and share in the glow.\\\\n\\\\nA blessing settles over the army. The priests among us cannot agree on which "
                                "power sent it, but none of them doubt that it is real.\\\\n\\\\nThe soldiers march a little taller for it. Even the "
                                "hardest veterans find themselves humming the old marching songs as we take the road again."),
    "touch_the_relic_cursed": ("Touch the Relic", "A Curse",
                               "The relic is as cold as a grave. The first soldier to touch it loses all feeling up to the elbow and drops it "
                               "with a cry.\\\\n\\\\nA creeping dread spreads through the ranks. Soldiers jump at every shadow, the horses refuse to "
                               "settle, and the sentries swear they hear whispers out past the campfires.\\\\n\\\\nA curse settles over the army, though it should "
                               "not last long. Until it lifts, there is nothing to do but grit our teeth and endure it."),
    "gamble_with_the_hermit_won": ("Gamble with the Hermit", "A Lucky Throw",
                                   "The hermit squints at the dice, then laughs. It is a dry, cracked sound, as if it has not been used in "
                                   "years.\\\\n\\\\nThe hermit shuffles off into the hut, and for a long while we hear things being moved and "
                                   "dropped inside. Our soldiers wait by the door, unsure what to expect.\\\\n\\\\nThey return with a unique "
                                   "treasure and press it into our hands. The hermit asks for nothing else, and waves us back to the road without a "
                                   "word."),
    "gamble_with_the_hermit_lost": ("Gamble with the Hermit", "The Hermit Wins",
                                    "The hermit wins throw after throw, cackling all the while. No matter who takes the dice, the hermit's luck "
                                    "holds.\\\\n\\\\nOur soldiers grow suspicious and check the dice, then the cup, then the table. They find "
                                    "nothing wrong with any of it, which only makes it worse.\\\\n\\\\nWhen the game is done our gold is in the "
                                    "hermit's pouch. By the time we look up from the table, the hermit is gone, and so is the lantern from the hut."),
    "endow_the_province": ("Endow the Province", "",
                           "Our gold pays for new roads and storehouses across {place}. Work crews arrive by the cartload, and the sound of hammers "
                           "carries from one end of the region to the other.\\\\n\\\\nThe region grows stronger and richer. Trade moves faster along "
                           "the new roads, and the storehouses fill before the season is out.\\\\n\\\\nIts people know who paid for it. Our banners "
                           "hang over the new gates, and the locals are careful to speak our name with respect."),
    "garrison_drill": ("Garrison Drill", "",
                       "Fresh supplies reach the garrison of {place}, and its officers drill the defenders from dawn to dusk. Shields are repaired, "
                       "blades sharpened and the walls checked stone by stone.\\\\n\\\\nThe drills are hard and the sergeants harder. Those who "
                       "complain run the walls again, and those who fall behind run them twice.\\\\n\\\\nIts walls are manned by harder soldiers "
                       "now. Any enemy who comes to test them will find the defenders ready and waiting."),
    "raise_the_settlement": ("Raise the Settlement", "",
                             "Builders swarm over {place}, raising new halls and stronger walls. Stone comes in by the cartload, and the work goes "
                             "on by torchlight long after dark.\\\\n\\\\nThe townsfolk watch old buildings come down and new ones rise in their "
                             "place. Few of them have ever seen work move so fast.\\\\n\\\\nIn a matter of days its heart stands a level higher than "
                             "before. The builders pack their tools and move on, leaving a settlement ready for what is coming."),
    "quell_the_unrest": ("Quell the Unrest", "",
                         "Our soldiers walk the streets of {place} in close order, shields up and faces hard. They do not need to draw their "
                         "blades.\\\\n\\\\nThe loudest troublemakers fall quiet. A few are dragged before the magistrates, and the rest decide that "
                         "today is a good day to stay indoors.\\\\n\\\\nOrder returns, for now. The markets reopen and the shutters come down, but "
                         "our captains know that quiet streets do not stay quiet for ever."),
    "bountiful_harvest": ("Bountiful Harvest", "",
                          "The fields around {place} groan under a bountiful harvest. The grain stands tall and heavy, and every hand in the region "
                          "is called out to bring it in.\\\\n\\\\nCarts queue at the granaries for days, and the markets are busier than anyone can "
                          "remember. Bread is cheap, and the taverns are full.\\\\n\\\\nThe farmers give thanks to whatever powers they keep. For "
                          "once, no one in the region goes hungry this season."),
    "stir_their_rebels": ("Stir Their Rebels", "",
                          "Our agents hand out grievances and weapons among the malcontents of {place}. They whisper of unpaid wages, cruel taxes "
                          "and lords who care nothing for the common folk.\\\\n\\\\nIt does not take much. Angry words become angry crowds, and "
                          "angry crowds become mobs with blades in their hands.\\\\n\\\\nUnrest is rising across the enemy's lands. Their rulers "
                          "will have to spend time and soldiers putting it down, and that is time we can use."),
    "poison_their_wells": ("Poison Their Wells", "",
                           "Under cover of night, our agents foul the wells of {place}. They work quickly and quietly, and are long gone before the "
                           "first bucket is drawn at dawn.\\\\n\\\\nSickness spreads through its people. The healers are overwhelmed, and the "
                           "streets fill with the sound of coughing.\\\\n\\\\nAny army camped there will suffer for it. It is cruel work, but war "
                           "rarely leaves room for kindness, and the enemy would do the same to us."),
    "sap_their_garrison": ("Sap Their Garrison", "",
                           "Our saboteurs slip into {place} dressed as merchants and labourers. No one looks twice at them as they find their way to "
                           "the barracks.\\\\n\\\\nThey spoil the grain stores and spread sickness through the barracks. By the time the officers "
                           "notice, half the garrison is too sick to stand a watch.\\\\n\\\\nIts garrison is weakened and shaken. Those still on "
                           "their feet glance at every stranger now, and none of them sleep easily."),
    "spread_the_plague": ("Spread the Plague", "",
                          "We drive the sick and the dying toward the enemy's lands around {place}. It is grim work, and the soldiers who herd them "
                          "wear cloths over their faces.\\\\n\\\\nThe plague spreads quickly through the villages and along the roads. Their healers "
                          "burn what they can, but it is not enough to stop it.\\\\n\\\\nOur own army does not escape it entirely. Coughing is heard "
                          "in our camp too, and the surgeons have their hands full."),
    "mystery_brew_strikes": ("Mystery Brew", "Fire in the Eyes",
                             "The brew goes down like liquid fire. Eyes water, throats burn, and more than one veteran has to sit down after the "
                             "first cup.\\\\n\\\\nBy morning the soldiers swear they see every gap in a shield and every opening in a guard. Their "
                             "blows land where the enemy cannot see them coming.\\\\n\\\\nThe sergeants have never seen the ranks so sharp. For a "
                             "few days, every blade in the army strikes at the eyes."),
    "mystery_brew_spell": ("Mystery Brew", "A Spark of Sorcery",
                           "The brew glows faintly in the cup, and the soldiers who drink it see colours that are not there. One of them starts "
                           "muttering in a tongue none of us know.\\\\n\\\\nBy morning the words have not faded. Our wizards listen closely and "
                           "write them down, and what they write is a working spell.\\\\n\\\\nThe army can call on it for a few days. The keeper "
                           "will not say where the brew came from, only that it should be used before it wears off."),
    "mystery_brew_lost": ("Mystery Brew", "A Foul Brew",
                          "Whatever was in that barrel, it was not meant for drinking. It tasted fine going down, which is the worst "
                          "part.\\\\n\\\\nThe army wakes with sore heads and slow feet. Soldiers stumble out of their tents groaning, and more than "
                          "one is sick behind the wagons before breakfast.\\\\n\\\\nThe keeper will not say what it was. When pressed, the keeper "
                          "only shrugs and says no one forced us to drink it."),
    "dice_with_strangers_won": ("Dice with Strangers", "The Dice Are Kind",
                                "The dice land in our favour, again and again. Each throw draws a louder cheer from the soldiers gathered round the "
                                "table.\\\\n\\\\nThe strangers pay up with sour faces. They mutter among themselves and check the dice more than "
                                "once, but find nothing to complain about.\\\\n\\\\nOur stake comes back doubled. The strangers leave soon after, "
                                "and our soldiers keep a close eye on them until they are out of sight."),
    "dice_with_strangers_prize": ("Dice with Strangers", "A Prize on the Table",
                                  "The strangers run out of coin long before their luck runs out of patience. One of them throws a wrapped bundle "
                                  "onto the table to cover the last bet.\\\\n\\\\nThe dice fall our way once more. The stranger unwraps the bundle "
                                  "with a sour face and pushes it across the table.\\\\n\\\\nIt is worth far more than our stake. The strangers "
                                  "leave without a word, and our soldiers drink to the luck of the dice."),
    "dice_with_strangers_lost": ("Dice with Strangers", "Loaded Dice",
                                 "The dice turn against us, throw after throw. Our soldiers watch in silence as their luck runs dry, until one of "
                                 "them grabs a stranger's wrist and finds a second set of dice up the sleeve.\\\\n\\\\nThe common room erupts. "
                                 "Tables go over, tankards fly, and the strangers' friends draw knives from under their cloaks.\\\\n\\\\nBy the time "
                                 "the watch arrives, the strangers are gone with our stake. Our own soldiers limp back to camp nursing cuts and "
                                 "broken bones."),
    "press_gang_night": ("Press-Gang Night", "",
                         "Our sergeants buy round after round for the common room, then wait for the drinkers to fall asleep at their "
                         "tables.\\\\n\\\\nThey wake in our camp with sore heads and new uniforms. Some curse us, some shrug, and a few even seem "
                         "glad of the pay.\\\\n\\\\nWord travels fast around {place}. Mothers hide their sons when our soldiers pass, and the "
                         "people there will not forgive us soon."),
    "smugglers_cut": ("The Smugglers' Cut", "",
                      "The smugglers meet us in the back room and push a ledger across the table. Our share of their trade is written in a neat "
                      "hand.\\\\n\\\\nThe goods they move through {place} pay no tolls, and the rulers there know it. They know our name now "
                      "too.\\\\n\\\\nOur treasury grows fat on the trade for a while. Their envoys are cold with ours, and they will not forget "
                      "who took the cut."),
    "arm_wrestle_the_champion_won": ("Arm-Wrestle the Champion", "Champion Beaten",
                                     "Our lord and the champion lock hands over a table scarred by a hundred such contests. For a long moment "
                                     "neither arm moves, and the common room goes quiet.\\\\n\\\\nThen the table groans and the crowd roars as the "
                                     "champion's arm slams down. Tankards fly, coin changes hands, and the champion sits stunned.\\\\n\\\\nOur lord "
                                     "walks out a legend of the common room. The story will be told in that tavern for years, and it will grow with "
                                     "each telling."),
    "arm_wrestle_the_champion_lost": ("Arm-Wrestle the Champion", "Arm Broken",
                                      "The champion grins, leans in, and something in our lord's arm gives way with a crack. The sound carries "
                                      "across the whole common room.\\\\n\\\\nOur lord leaves the table hurt, cradling the arm and refusing all "
                                      "help. Our surgeons are waiting by the door with splints and harsh words.\\\\n\\\\nThe crowd cheers the "
                                      "champion, who raises a tankard to the room. It is a bitter lesson in picking the right fights."),
    "buy_rumours": ("Buy Rumours", "",
                    "The keeper leans close and talks of the roads around {place} and beyond. Our coin buys a great deal of talk, and some of it is "
                    "even true.\\\\n\\\\nThe keeper speaks too of the enemy camped nearby: {detail}. Our officers write it all down and mark their "
                    "maps by candlelight.\\\\n\\\\nWe will see those lands for some time yet. Whatever moves on those roads, we will know of it "
                    "before it reaches us."),
    "send_gifts": ("Send Gifts", "",
                   "Our gifts are well received at {place}. Fine cloth, good wine and worked silver are laid before their rulers in the great "
                   "hall.\\\\n\\\\nTheir rulers speak of us more warmly now. Old suspicions do not vanish overnight, but the tone of their letters "
                   "has plainly changed.\\\\n\\\\nOur envoys are welcome at their table. Where they once waited for days at the gate, they are now "
                   "shown in at once."),
    "spy_on_their_capital": ("Spy on Their Capital", "",
                             "Our spies slip into {place} to map its walls and gates and count its garrison. They pass as traders, pilgrims and "
                             "beggars, and no one stops them.\\\\n\\\\nWhat they bring back is worth the risk: {detail}. Our officers study it "
                             "closely and copy it into every map we carry.\\\\n\\\\nWe will see its streets for some time yet. Should we ever march "
                             "on those walls, we will not go in blind."),
    "curse_a_distant_king": ("Curse a Distant King", "",
                             "A curse falls on the treasury of the court at {place}. It is spoken far away, over smoke and old bones, and carried on "
                             "the wind.\\\\n\\\\nTheir wealth dwindles. Coins go missing from locked chests, ledgers fail to balance and the "
                             "stewards blame one another for the loss.\\\\n\\\\nThey will never know why. Their rulers will hang a few clerks and "
                             "double the guards, and the gold will keep slipping away all the same."),
    "share_the_find": ("Share the Find", "",
                       "We share what we found with our neighbours, starting with {place}. Copies are made and sent off by our fastest "
                       "riders.\\\\n\\\\nTheir scholars are grateful. They pore over what we sent for days, and their letters back are full of "
                       "questions and thanks.\\\\n\\\\nThey think better of us for it. It costs us little to share, and a good name among our "
                       "neighbours may be worth more than any secret."),
    "point_them_at_each_other": ("Point Them at Each Other", "",
                                 "Rumours spread from {place}, carefully planted by our agents. A forged letter here, a careless word in a tavern "
                                 "there, and the story takes on a life of its own.\\\\n\\\\nTwo rivals now eye each other with suspicion. Each is "
                                 "sure the other has been plotting behind their back.\\\\n\\\\nNeither of them looks our way. While they watch each "
                                 "other, our own plans can move forward with fewer eyes upon them."),
    "sell_their_secrets": ("Sell Their Secrets", "",
                           "The secrets fetch a fine price in {place}. The buyers pay without haggling, which tells us we could have asked for "
                           "more.\\\\n\\\\nBut word travels. It does not take long for the ones we sold out to learn who did it, and they are not "
                           "the forgiving sort.\\\\n\\\\nOur enemies grow closer to one another. Old quarrels are set aside, and we may yet find "
                           "them standing together against us."),
    "ransom_the_captain": ("Ransom the Captain", "",
                           "Their captain is ransomed back to {place}, and the price is paid in full. The coin arrives under guard and is counted "
                           "twice before the captain is let go.\\\\n\\\\nThe captain rides home with head bowed, past the jeering of our soldiers. "
                           "It is not the return any officer hopes for.\\\\n\\\\nTheir kin will not forget the humiliation. The ransom fills our "
                           "coffers, but it has bought us no friends among them."),
    "raise_their_banner": ("Raise Their Banner", "",
                           "Their captured banner now flies over our camp, and our soldiers march taller beneath it. They point it out to every new "
                           "recruit and every passing trader.\\\\n\\\\nIn {place}, the insult is felt keenly. That banner was carried by their "
                           "fathers and grandfathers, and now it hangs over a foreign camp.\\\\n\\\\nTheir kin will remember who flew it. They will "
                           "want it back one day, and they will want blood with it."),
    "press_the_survivors": ("Press the Survivors", "",
                            "The survivors are given a choice that is no choice at all, and they take up arms under our banner. Some do it with "
                            "bitter faces, others with blank ones.\\\\n\\\\nOur sergeants watch them closely for the first few days. A soldier "
                            "pressed into service is a soldier who might run, or worse.\\\\n\\\\nWord reaches {place}, and their kin do not take "
                            "kindly to it. To them, every pressed soldier is a son or brother stolen."),
    "chase_the_routers_won": ("Chase the Routers", "A Rich Catch",
                              "Our fastest troops run the fleeing enemy down before they reach safety. The chase goes on for miles, over fields and "
                              "through ditches, until the last of them is caught.\\\\n\\\\nAlong the way the enemy threw away everything that slowed "
                              "them down. Shields, packs and helmets lie scattered across the ground.\\\\n\\\\nAmong the gear they threw away to run "
                              "faster is a rare item. It is brought back to our lord with no small pride."),
    "chase_the_routers_lost": ("Chase the Routers", "Ambushed",
                               "The fleeing enemy were bait. They run just fast enough to stay ahead, and our pursuers take the lure without a "
                               "second thought.\\\\n\\\\nThey turn on our pursuers in a narrow pass. The enemy we thought were beaten stand and "
                               "fight with sudden fury, and the trap closes fast.\\\\n\\\\nEvery unit of ours comes back bloodied. We were lucky it "
                               "was not worse, and our officers will be slower to give chase next time."),
}

# Message suffix -> the words its event feed message uses for {place}, which only the result incident can show by name.
FALLBACK_PLACES = {
    "endow_the_province": "that region", "garrison_drill": "that settlement", "raise_the_settlement": "the settlement",
    "quell_the_unrest": "the settlement", "research_scrolls": "the nearest province", "chip_the_runestone": "the nearest province", "bountiful_harvest": "that region", "stir_their_rebels": "that region", "poison_their_wells": "that region",
    "sap_their_garrison": "the enemy settlement", "spread_the_plague": "that region", "buy_rumours": "that region", "press_gang_night": "our province", "smugglers_cut": "their lands", "send_gifts": "their court",
    "spy_on_their_capital": "the enemy capital", "curse_a_distant_king": "their capital", "share_the_find": "the nearest",
    "point_them_at_each_other": "that region", "sell_their_secrets": "that region", "ransom_the_captain": "their own people",
}

# Result -> (colour, text) of the effect line under a result's incident, for results whose payload shows no gold, item or unit card.
# Every mission failed gets its own line.
RESULT_LINES = {
    "tomb_robbing_haunted": ("red", "Our lord is struck by Haunted II."),
    "cast_the_lots_lost": ("red", "Our stake is lost."),
    "drink_from_the_spring_won": ("green", "Every unit is healed to full."),
    "drink_from_the_spring_lost": ("red", "Attrition on our army for {lost_turns} turns."),
    "open_the_sealed_door_lost": ("red", "Our lord is wounded for 3 turns."),
    "free_the_prisoner_chased": ("red", "The jailers attack our army!"),
    "double_or_nothing_lost": ("red", "Our stake of {cost} gold is lost."),
    "wake_the_guardian_lost": ("red", "The guardian attacks our army!"),
    "touch_the_relic_blessed": ("green", "A blessing on our army for 5 turns."),
    "touch_the_relic_cursed": ("red", "A curse on our army for 3 turns."),
    "gamble_with_the_hermit_lost": ("red", "The hermit keeps our {cost} gold."),
    "chase_the_routers_lost": ("red", "Every unit loses {lost_bleed}% of its strength."),
    "mystery_brew_strikes": ("green", "Blinding Strikes on our army for 5 turns."),
    "mystery_brew_spell": ("green", "The named army spell is ours to cast for 5 turns."),
    "mystery_brew_lost": ("red", "A hangover on our army for {lost_turns} turns."),
    "dice_with_strangers_lost": ("red", "Our stake is lost, and every unit loses {lost_bleed}% of its strength."),
    "press_gang_night": ("red", "-{e0} public order in our nearest province for {turns} turns."),
    "smugglers_cut": ("red", "-{relations} relations with the owner of this region."),
    "arm_wrestle_the_champion_won": ("green", "+{won_xp} experience for our lord."),
    "arm_wrestle_the_champion_lost": ("red", "Our lord loses half their remaining health."),
    "buy_rumours": ("green", "{count} regions revealed for {reveal_turns} turns."),
    "endow_the_province": ("green", "+{points} development points."),
    "garrison_drill": ("green", "Garrison healed, and +{e0} melee attack, melee defence and leadership for {turns} turns."),
    "raise_the_settlement": ("green", "Main building +1 level."),
    "quell_the_unrest": ("green", "+{e0} public order for {turns} turns."),
    "bountiful_harvest": ("green", "+{e0} growth and +{e1}% income for {turns} turns."),
    "stir_their_rebels": ("green", "-{e0} public order for {turns} turns."),
    "poison_their_wells": ("green", "-{e0} growth and attrition for {turns} turns."),
    "sap_their_garrison": ("green", "Garrison at {garrison}% strength, and -{e0} leadership for {turns} turns."),
    "spread_the_plague": ("green", "-{e0} public order and -{e1} growth for {turns} turns, and attrition on our army for 3 turns."),
    "send_gifts": ("green", "+{relations} relations."),
    "spy_on_their_capital": ("green", "Revealed for {reveal_turns} turns."),
    "curse_a_distant_king": ("green", "-{e0}% income for {turns} turns."),
    "share_the_find": ("green", "+{e0}% research rate for {turns} turns, and +{relations} relations."),
    "point_them_at_each_other": ("green", "-{relations} relations between them."),
    "sell_their_secrets": ("yellow", "+{relations} relations between our enemies."),
    "ransom_the_captain": ("yellow", "-{relations} relations with their kin."),
    "mission_guard_the_standard_met": ("green", "The marked unit gains 3 ranks."),
    "mission_untouchable_met": ("green", "+{lord_xp} experience for our lord."),
    "missions_untracked": ("yellow", "No mission was counted. Any wager comes back to our treasury."),
}

# Bundle key suffix after `land_enc_effect_spot_` -> (target, icon, title, description, [(effect, scope, value)]). A value written as
# (easy, medium, hard) makes a tiered bundle, one per difficulty named with it, e.g. land_enc_effect_spot_stoneskin_medium. A None step leaves
# the effect out at that difficulty, so such an effect comes last: offer lines number the effects by position ({e0}, {e1}...).
BUNDLES = {
    "reinforcement_time_25": ("force", "military.png", "Swift Reinforcements", "Scouts have marked the fastest paths for our relief columns. Reinforcements reach this army sooner.",
                              [("wh3_main_effect_own_reinforcement_time_percentage_mod", "force_to_force_own", -25)]),
    "reinforcement_time_50": ("force", "military.png", "Swift Reinforcements", "Scouts have marked the fastest paths for our relief columns. Reinforcements reach this army sooner.",
                              [("wh3_main_effect_own_reinforcement_time_percentage_mod", "force_to_force_own", -50)]),
    "reinforcement_time_75": ("force", "military.png", "Swift Reinforcements", "Scouts have marked the fastest paths for our relief columns. Reinforcements reach this army sooner.",
                              [("wh3_main_effect_own_reinforcement_time_percentage_mod", "force_to_force_own", -75)]),
    "camping": ("force", "campaign_movement.png", "Searching Every Corner", "Our army searches every corner and cannot march until our next turn.",
                [("wh_main_effect_force_all_campaign_movement_range", "force_to_force_own", -100)]),
    "strip_the_valuables": ("force", "nor_spoils.png", "Weighed Down", "Every wagon and pack is stuffed with stripped valuables. The army moves slowly under the weight.",
                            [("wh_main_effect_force_stat_leadership", "force_to_force_own", -15), ("wh_main_effect_force_stat_speed", "force_to_force_own", -10)]),
    "bless_the_banners": ("force", "devotion.png", "Blessed Banners", "Our banners were held over the smoke of an old shrine's fire. The warriors stand firmer beneath them.",
                          [("wh_main_effect_force_stat_melee_attack", "force_to_force_own", 5),
                           ("wh_main_effect_force_stat_leadership", "force_to_force_own", 5)]),
    "stoneskin": ("force", "resistance_physical.png", "Stoneskin", "A ward of living stone hardens our army's hide.",
                   [("wh_main_effect_force_stat_physical_resistance", "force_to_force_own", (5, 10, 15))]),
    "ancient_tactics": ("force", "experience.png", "Ancient Tactics", "Faded battle orders found in the ruins have our captains drilling the ranks in forgotten formations.",
                        [("wh2_dlc14_effect_force_charge_bonus_add", "force_to_force_own", 5), ("wh_main_effect_force_stat_speed", "force_to_force_own", 5)]),
    "touch_the_relic_frailty": ("force", "fractured_mind.png", "Relic's Frailty", "Since our lord touched the relic, shields feel heavy and parries come a beat too late.",
                                [("wh_main_effect_force_stat_melee_defence", "force_to_force_own", -10), ("wh_main_effect_force_stat_armour", "force_to_force_own", -10)]),
    "leave_an_offering": ("force", "temples_of_the_old_ones.png", "Offering Made", "We left gifts at a wayside shrine before marching on. Blows that should land seem to glance away.",
                          [("wh_main_effect_force_stat_ward_save", "force_to_force_own", (10, 15, 20))]),
    "enchanted_steel": ("force", "hellforged.png", "Enchanted Steel", "Strange marks found at the site were etched into every blade. Our weapons now bite where plain steel would not.",
                        [("wh_main_effect_force_stat_enable_magic_attacks", "force_to_force_own", 1)]),
    "bloodstained_blades": ("force", "dlc10_blood_voyage.png", "Bloodstained Blades",
                            "Our warriors took up blades found still stained with old blood. They cut deep, and no one wants to clean them.",
                            [("wh_main_effect_force_stat_melee_attack", "force_to_force_own", 20), ("wh_main_effect_force_stat_melee_defence", "force_to_force_own", -20)]),
    "buy_supplies": ("force", "supplies.png", "Well Supplied", "A full baggage train rides with the army. No one goes hungry on the march.",
                     [("wh_main_effect_force_army_campaign_attrition_all_immunity", "force_to_force_own", 1)]),
    "recruitment_cache": ("faction", "military_spending.png", "Smugglers' Cache", "Smugglers left a hidden store of arms and kit behind. New recruits can be outfitted for far less.",
                          [("wh_main_effect_force_all_campaign_recruitment_cost_all", "faction_to_force_own", (-10, -20, -30))]),
    "share_the_find": ("faction", "technology.png", "Shared Knowledge", "We shared what we found with our neighbours, and their scholars sent their own notes back.",
                       [("wh_main_effect_technology_research_rate_mod", "faction_to_faction_own", 15)]),
    "curse_a_distant_king": ("faction", "chaos_gifts.png", "Cursed Coffers", "A curse has settled on this ruler's treasury. Gold goes missing, and no one can say where.",
                             [("wh_main_effect_economy_gdp_mod_all", "faction_to_region_own", (-5, -10, -15))]),
    "garrison_drill": ("region", "siege_defence.png", "Garrison Drill", "Fresh supplies and hard drill have the defenders ready for anything.",
                       [("wh_main_effect_force_stat_melee_attack", "region_to_force_own_regionwide_if_garrison", 10),
                        ("wh_main_effect_force_stat_melee_defence", "region_to_force_own_regionwide_if_garrison", 10),
                        ("wh_main_effect_force_stat_leadership", "region_to_force_own_regionwide_if_garrison", 10)]),
    "poison_their_wells": ("region", "chaos_gifts.png", "Poisoned Wells", "The wells here have been fouled with carrion and filth. Anyone who drinks from them sickens.",
                           [("wh_main_effect_province_growth_events", "region_to_province_own", (-10, -20, -30)),
                            ("wh_main_effect_campaign_enable_attrition", "region_to_force_own", 1)]),
    "sap_their_garrison": ("region", "chaos_gifts.png", "Sapped Garrison", "Spoiled stores and sickness in the barracks have the defenders shaken.",
                           [("wh_main_effect_force_stat_leadership", "region_to_force_own_regionwide_if_garrison", -10)]),
    "spread_the_plague": ("region", "chaos_gifts.png", "Plague", "Sickness spreads from house to house, and the dead are carted out each morning.",
                          [("wh_main_effect_public_order_events", "region_to_province_own", -5), ("wh_main_effect_province_growth_events", "region_to_province_own", -10)]),
    "quell_the_unrest": ("province", "income.png", "Order Restored", "Our soldiers walked the streets and broke up the mobs. The province has settled.",
                         [("wh_main_effect_public_order_events", "province_to_province_own", 5)]),
    "bountiful_harvest": ("province", "income.png", "Bountiful Harvest", "The fields and herds of the province have given more than anyone hoped. The stores are full.",
                          [("wh_main_effect_province_growth_events", "province_to_province_own", (10, 20, 30)),
                           ("wh_main_effect_economy_gdp_mod_all", "province_to_region_own", (5, 10, 15))]),
    "stir_their_rebels": ("province", "chaos_gifts.png", "Stirred Rebels", "Our agents spread rumours and gold among the malcontents here. Armed bands now gather in the hills.",
                          [("wh_main_effect_public_order_events", "province_to_province_own", (-10, -15, -20))]),
    "press_on": ("force", "icon_effects_forced_march.png", "Pressing On", "The enemy broke and ran. Our army follows hard on their heels before they can regroup.",
                 [("wh_main_effect_force_all_campaign_movement_range", "force_to_force_own", 50)]),
    "victory_feast": ("force", "icon_effects_fortify.png", "Victory Feast", "The army feasted long into the night on what the beaten enemy left behind. Spirits are high on the march.",
                      [("wh_main_effect_force_stat_leadership", "force_to_force_own", (5, 10, 15)),
                       ("wh_main_effect_force_stat_melee_attack", "force_to_force_own", (5, 10, 15))]),
    "dark_offering": ("force", "defiled_bloodground.png", "Dark Offering", "Blood was spilled on an old altar before we marched. Something unseen now turns blows from our warriors.",
                      [("wh_main_effect_force_stat_ward_save", "force_to_force_own", 5)]),
    "fallen_feast": ("faction", "corruption_tzeentch.png", "Feast on the Fallen", "Our army fed on the dead after the battle. Dark rumours of it spread through our lands.",
                     [("wh3_main_effect_corruption_chaos_events_bad", "faction_to_province_own", 5)]),
    "tavern_fighting_spirits": ("force", "edict_sla_festival_of_drinking_and_delights.png", "Fighting Spirits",
                                "The tavern's fighting spirits burned all the way down. Our warriors marched out spoiling for a brawl.",
                                [("wh_main_effect_force_stat_melee_attack", "force_to_force_own", (6, 10, 14)),
                                 ("wh_main_effect_force_stat_weapon_strength", "force_to_force_own", (5, 8, 12)),
                                 ("wh_main_effect_force_stat_melee_defence", "force_to_force_own", (-4, -6, -8))]),
    "tavern_shieldbrew": ("force", "edict_sla_festival_of_drinking_and_delights.png", "Shieldbrew",
                          "The shieldbrew sat in every belly like a stone. Our warriors stand their ground like rocks, though they are slow to move.",
                          [("land_enc_lib_fx_melee_defence_defending", "force_to_force_own", (8, 12, 16)),
                           ("land_enc_lib_fx_leadership_defending", "force_to_force_own", (8, 12, 16)),
                           ("wh_main_effect_force_stat_speed", "force_to_force_own", -5),
                           ("land_enc_lib_fx_unbreakable_defending", "force_to_force_own", (None, None, 1))]),
    "tavern_firewater": ("force", "edict_sla_festival_of_drinking_and_delights.png", "Firewater",
                         "The firewater left every throat burning and every foot itching to run. Our warriors charge like madmen, and tire as fast.",
                         [("land_enc_lib_fx_speed_attacking", "force_to_force_own", (8, 12, 16)),
                          ("land_enc_lib_fx_charge_attacking", "force_to_force_own", (8, 12, 16)),
                          ("wh3_dlc27_effect_ability_enable_frenzy_all", "force_to_force_own", 1),
                          ("wh_main_effect_force_campaign_stance_begin_fatigued_3_winded", "force_to_force_own", 3)]),
    "tavern_marksmans_draught": ("force", "edict_sla_festival_of_drinking_and_delights.png", "Marksman's Draught",
                                 "A round of marksman's draught steadied the hands of our shooters, and filled every quiver. Nobody thought to drill the spears.",
                                 [("wh_main_effect_force_stat_missile_damage", "force_to_force_own", (8, 12, 16)),
                                  ("wh_main_effect_force_stat_ammunition", "force_to_force_own", (20, 30, 40)),
                                  ("wh_main_effect_force_stat_melee_defence", "force_to_force_own", (-5, -8, -10))]),
    "tavern_blinding_strikes": ("force", "wh_dlc06_unit_contact_blinded.png", "Blinding Strikes", "The mystery brew sharpened every eye in the army. Our blows find the enemy's eyes.",
                                [("land_enc_lib_fx_blinded_hits", "force_to_force_own", 1)]),
    "tavern_press_gang": ("province", "public_order_unhappy.png", "Press-Ganged", "Our sergeants dragged drinkers from the tavern into our ranks. The people here have not forgiven it.",
                          [("wh_main_effect_public_order_events", "province_to_province_own", (-5, -8, -10))]),
    "tavern_smugglers_cut": ("faction", "income.png", "The Smugglers' Cut", "Our share of the smugglers' trade fills the treasury.",
                             [("wh_main_effect_economy_gdp_mod_all", "faction_to_region_own", (10, 15, 20))]),
    "tavern_pathfinder": ("force", "campaign_movement.png", "Pathfinder", "A pathfinder from the tavern knows every short cut and every well along the way.",
                          [("wh_main_effect_force_all_campaign_movement_range", "force_to_force_own", (20, 30, 40)),
                           ("wh_main_effect_force_army_campaign_attrition_all_immunity", "force_to_force_own", 1)]),
    "tavern_blood_wine": ("force", "bloodreaper.png", "Blood Wine", "The blood wine runs hot in every vein. Wounds close as fast as they open when our warriors hold their ground.",
                          [("land_enc_lib_fx_regeneration_defending", "force_to_force_own", 1),
                           ("land_enc_lib_fx_leadership_defending", "force_to_force_own", (8, 12, 16))]),
    "smithy_heavy_plate": ("force", "armour.png", "Heavy Plate", "The Smithy riveted heavy plate onto every warrior. Blows glance off, though the march is slower.",
                           [("wh_main_effect_force_stat_armour", "force_to_force_own", (15, 20, 25)),
                            ("wh_main_effect_force_stat_speed", "force_to_force_own", (-5, -8, -10))]),
    "smithy_honed_edges": ("force", "weapon_damage.png", "Honed Edges", "Every edge in the army was ground thin at the Smithy. They bite deep, and turn a parry poorly.",
                           [("wh_main_effect_force_stat_weapon_strength", "force_to_force_own", (6, 9, 12)),
                            ("wh_main_effect_force_stat_melee_defence", "force_to_force_own", (-4, -6, -8))]),
    "smithy_barbed_arrowheads": ("force", "ranged_damage.png", "Barbed Arrowheads", "Barbed heads tear through flesh, but the fletchers could not make as many.",
                                 [("wh_main_effect_force_stat_missile_damage", "force_to_force_own", (10, 15, 20)),
                                  ("wh_main_effect_force_stat_ammunition", "force_to_force_own", -20)]),
    "smithy_shod_and_barded": ("force", "charge.png", "Shod and Barded", "Iron-shod mounts and barded beasts hit like a hammer, and eat twice as much.",
                               [("land_enc_lib_fx_charge_attacking", "force_to_force_own", (10, 15, 20)),
                                ("wh_main_effect_force_stat_speed", "force_to_force_own", 5),
                                ("wh_main_effect_force_all_campaign_upkeep", "force_to_force_own", 10)]),
    "smithy_arms_trade": ("province", "income.png", "Arms Trade", "Merchants come from far away for the Smithy's steel, and their trade fills the province's coffers.",
                          [("wh_main_effect_economy_gdp_mod_all", "province_to_province_own", (3, 6, 9))]),
    "smithy_armoury": ("region", "icon_effects_fortify.png", "Garrison Armoury", "The Smithy arms the garrison with its best plate and shields.",
                       [("wh_main_effect_force_stat_armour", "region_to_force_own_regionwide_if_garrison", (10, 15, 20)),
                        ("wh_main_effect_force_stat_melee_defence", "region_to_force_own_regionwide_if_garrison", (5, 8, 10))]),
    "sig_troubled_faithful": ("province", "public_order_unhappy.png", "Troubled Faithful", "The faithful at home have heard of our lord's dream, and they fear the voice that spoke in it.",
                              [("wh_main_effect_public_order_events", "province_to_province_own", -10)]),
    "sig_explorers": ("force", "campaign_movement.png", "The Explorers' Maps", "The explorers' maps show every dry ford and short path, and every place an enemy could lie in wait.",
                      [("wh_main_effect_force_all_campaign_movement_range", "force_to_force_own", 15),
                       ("wh_main_effect_force_army_campaign_ambush_defence_success_chance", "force_to_force_own", 15)]),
    "sig_bard_song": ("force", "morale.png", "Song of Our Deeds", "The bard's songs of our deeds run ahead of the army, and every soldier stands a little taller for them.",
                      [("wh_main_effect_force_stat_leadership", "force_to_force_own", 10)]),
    "blessed_banners": ("force", "devotion.png", "Blessed Banners", "Our banners were blessed at an old shrine. The warriors stand firmer beneath them, though the heavy cloth slows the march.",
                        [("wh_main_effect_force_stat_melee_attack", "force_to_force_own", (10, 12, 15)),
                         ("wh_main_effect_force_stat_leadership", "force_to_force_own", (10, 12, 15)),
                         ("wh_main_effect_force_stat_speed", "force_to_force_own", -10),
                         ("land_enc_lib_fx_unbreakable_defending", "force_to_force_own", 1)]),
    "ancient_drills": ("force", "charge.png", "Ancient Drills", "Faded battle orders have our captains drilling the ranks in forgotten formations: all attack, and little guard.",
                       [("land_enc_lib_fx_charge_attacking", "force_to_force_own", (10, 15, 20)),
                        ("wh_main_effect_force_stat_speed", "force_to_force_own", 5),
                        ("wh_main_effect_force_stat_melee_defence", "force_to_force_own", (-5, -6, -8))]),
    "scroll_research": ("faction", "technology.png", "Forbidden Scrolls", "The scrolls found at the site are full of strange learning, and our scholars cannot put them down.",
                        [("wh_main_effect_technology_research_rate_mod", "faction_to_faction_own", (25, 30, 35))]),
    "scroll_heresy": ("province", "public_order_unhappy.png", "Heresy Preached", "Word of the scrolls' teachings has spread through the province, and the priests are furious.",
                      [("wh_main_effect_public_order_events", "province_to_province_own", -10)]),
    "runestone_revered": ("province", "public_order_unhappy.png", "The Stone Defiled", "The locals revered the runestone we chipped, and they have not forgiven us.",
                          [("wh_main_effect_public_order_events", "province_to_province_own", -5)]),
    "captains_cut": ("force", "merc_contract.png", "The Captain's Cut", "The mercenary captain takes a share of every pay chest, as agreed.",
                     [("wh_main_effect_force_all_campaign_upkeep", "force_to_force_own", 10)]),
    "war_dogs": ("force", "campaign_movement.png", "War Dogs", "The war dogs run ahead of the column, sniffing out the short paths and every enemy lying in wait.",
                 [("wh_main_effect_force_all_campaign_movement_range", "force_to_force_own", (20, 25, 30)),
                  ("wh_main_effect_force_army_campaign_ambush_defence_success_chance", "force_to_force_own", 15)]),
    "battle_well": ("force", "melee.png", "Battle Fury", "The water of the battle well burns in the blood. Our warriors crave the charge, and care little for orders.",
                    [("wh3_dlc27_effect_ability_enable_frenzy_all", "force_to_force_own", 1),
                     ("wh2_dlc12_effect_force_stat_melee_attack_attacking", "force_to_force_own", (8, 12, 16)),
                     ("wh_main_effect_force_stat_leadership", "force_to_force_own", (-8, -10, -12))]),
    "tavern_hangover": ("force", "discouraged.png", "Hangover", "The mystery brew tasted of old boots and worse. Half the army spent the next morning groaning.",
                        [("wh_main_effect_force_stat_leadership", "force_to_force_own", -10), ("wh_main_effect_force_stat_speed", "force_to_force_own", -10)]),
}

# Dividends bundle: shows a faction's gold each turn through the tower's dividends effect, one bundle per amount the config pays.
DIVIDENDS = ("faction", "treasury.png", "Dividends", "The venture we bought into sends our share of its profits each turn.", "land_enc_effect_tower_dividends_income", "faction_to_faction_own")

# Trait key -> (icon, [(points needed, name, flavour, what earned it, [(effect, scope, value)])] one per level).
TRAITS = {
    "land_enc_trait_spot_shrine_sworn": ("trait_good", [
        (1, "Shrine-Sworn", "Swore an oath at a ruined altar, and the army believes it.", "Swore an oath at a ruined shrine",
         [("wh_main_effect_force_stat_leadership", "character_to_force_own", 5)]),
    ]),
    "land_enc_trait_spot_trophy_hunter": ("trait_good", [
        (1, "Trophy Hunter", "Keeps a trophy from every field won.", "Took a trophy of war",
         [("wh_main_effect_force_stat_leadership", "character_to_force_own", 4)]),
        (3, "Seasoned Trophy Hunter", "The trophies pile up, and so does the army's pride.", "Took 3 trophies of war",
         [("wh_main_effect_force_stat_leadership", "character_to_force_own", 8), ("wh_main_effect_force_stat_melee_attack", "character_to_force_own", 4)]),
        (6, "Famed Trophy Hunter", "Every army in the land has heard of this lord's trophies.", "Took 6 trophies of war",
         [("wh_main_effect_force_stat_leadership", "character_to_force_own", 12), ("wh_main_effect_force_stat_melee_attack", "character_to_force_own", 8)]),
    ]),
}

# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Config and rows

LUA_DUMP = r"""
package.path = arg[1] .. "?.lua;" .. package.path
local data = require("script/land_encounters/configs/spot_offers")
local tower = require("script/land_encounters/configs/tower_offers")
local steps = require("script/land_encounters/utils/steps")
local at, tower_at = {}, {}
for _, difficulty in ipairs(steps.DIFFICULTIES) do
    at[difficulty], tower_at[difficulty] = {}, {}
    for _, offer in ipairs(data.all_at(difficulty)) do at[difficulty][offer.key] = offer end
    for _, offer in ipairs(tower.offers) do tower_at[difficulty][offer.key] = tower.at(offer.key, difficulty) end
end
--- Which offers and notices differ by difficulty, as the scripts decide it: a tower offer's line, and a notice (spot gamble outcomes too).
local tower_varies, notice_varies = {}, {}
for _, offer in ipairs(tower.offers) do
    tower_varies[offer.key] = steps.varies(offer)
    notice_varies[offer.key] = steps.notice(offer.key, offer, "easy") ~= offer.key
end
for _, offer in ipairs(data.offers) do
    if notice_varies[offer.key] == nil then notice_varies[offer.key] = steps.notice(offer.key, offer, "easy") ~= offer.key end
    for _, outcome in ipairs(offer.gamble or {}) do
        local name = offer.key .. "_" .. outcome[2]
        notice_varies[name] = steps.notice(name, outcome, "easy") ~= name
    end
end
--- The tower's go-deeper dilemmas, which list every tower offer.
local tower_deeper_dilemmas = {}
for _, key in ipairs(require("script/land_encounters/configs/events").tower_spot) do
    if key:find("_deeper_floor_", 1, true) then tower_deeper_dilemmas[#tower_deeper_dilemmas + 1] = key end
end
local battle_dilemmas = {}
for key in pairs(require("script/land_encounters/configs/battle_categories").dilemma_keys) do battle_dilemmas[#battle_dilemmas + 1] = key end
local battle_modifiers = require("script/land_encounters/configs/battle_modifiers")
local boons = require("script/land_encounters/configs/boons")
table.sort(battle_dilemmas)
local function encode(v)
    local t = type(v)
    if t == "number" then return tostring(v) end
    if t == "boolean" then return tostring(v) end
    if t == "string" then return string.format("%q", v):gsub("\\\n", "\\n") end
    local n, count = #v, 0
    for _ in pairs(v) do count = count + 1 end
    local parts = {}
    if count == n then
        for i = 1, n do parts[i] = encode(v[i]) end
        return "[" .. table.concat(parts, ",") .. "]"
    end
    for k, value in pairs(v) do parts[#parts + 1] = string.format("%q", tostring(k)) .. ":" .. encode(value) end
    return "{" .. table.concat(parts, ",") .. "}"
end
io.write(encode({ sites = data.sites, spoils = data.spoils, venues = data.venues, offers = data.all_at("easy"), at = at, dividends_bundle_prefix = data.dividends_bundle_prefix,
    tower_offers = tower.offers, tower_at = tower_at, tower_varies = tower_varies, notice_varies = notice_varies,
    tower_unaffordable_suffix = tower.unaffordable_suffix, tower_line_prefix = tower.line_prefix, tower_choice_key_prefix = tower.choice_key_prefix,
    tower_deeper_dilemmas = tower_deeper_dilemmas,
    choice_key_prefix = data.choice_key_prefix, walk_away_choice_key = data.walk_away_choice_key, signature_choice_key = data.signature_choice_key,
    dilemma_prefix = data.dilemma_prefix, line_prefix = data.line_prefix, message_prefix = data.message_prefix, camp_bundle = data.camp_bundle,
    result_incident_prefix = data.result_incident_prefix, result_place_context = data.result_place_context, battle_pools = data.battle_pools,
    avoid_choice_key = data.avoid_choice_key,
    unaffordable_line = data.unaffordable_line, taken_line = data.taken_line, missions_context = data.missions_context,
    mission_set_loc_prefix = data.mission_set_loc_prefix, battle_dilemmas = battle_dilemmas, result_detail_context = data.result_detail_context,
    battle_modifiers = battle_modifiers, boons = boons }))
"""


def load_config() -> Dict:
    """Reads `configs/spot_offers.lua` through the `lua` executable.

    Returns:
        Dict: The sites, offers and naming constants. `offers` lists the offers at Easy, in config order, for their keys, pools and the other
        fields that never vary. `at` maps each difficulty to its offers by key, and `tower_at` the tower's. `tower_varies` says which tower
        offers differ by difficulty, and `notice_varies` which notices (tower offers and spot gamble outcomes) do.

    Raises:
        subprocess.CalledProcessError: When Lua cannot load the config.
    """
    output = subprocess.run(["lua", "-", MOD_ROOT], input=LUA_DUMP, capture_output=True, text=True, check=True).stdout
    config = json.loads(output)
    battle_modifiers.add_lore(config["battle_modifiers"]["list"])
    # The offers granting boons and curses take their text from the boons catalogue, as the lore armies take theirs from the config.
    texts, icons = boons.offer_texts(config["offers"], PAY)
    OFFERS.update(texts)
    # An offer angering the beaten army's kin says so on its result, and names them plainly where the event feed cannot.
    for offer in config["offers"]:
        if offer.get("beaten_kin"):
            RESULT_LINES.setdefault(offer["key"], RESULT_LINES["ransom_the_captain"])
            FALLBACK_PLACES.setdefault(offer["key"], FALLBACK_PLACES["ransom_the_captain"])
    ICONS.update(icons)
    tower_texts, tower_icons = boons.offer_texts(config["tower_offers"], TOWER_PAY)
    TOWER_ICONS.update(tower_icons)
    TOWER_LINES.update({key: (line, None) for key, (_, line) in tower_texts.items()})
    return config


def title_case(text: str) -> str:
    """Title-cases a name the way vanilla does: every word capitalised except small words between the first and the last, as in "Press On".

    Args:
        text (str): The name.

    Returns:
        str: The name in title case.
    """
    words = text.split(" ")
    for i, word in enumerate(words):
        bare = word.lower().rstrip(".,:;!?'")
        words[i] = word[0].lower() + word[1:] if 0 < i < len(words) - 1 and bare in SMALL_WORDS else word[0].upper() + word[1:]
    return " ".join(words)


def tiers_text(tiers: List[int]) -> str:
    """Writes a tier list as a range, e.g. [3, 4] as "3-4" and [4] as "4".

    Args:
        tiers (List[int]): The tiers, in order.

    Returns:
        str: The range.
    """
    return str(tiers[0]) if len(tiers) == 1 else f"{tiers[0]}-{tiers[-1]}"


def expand_bundles(config: Dict) -> Dict[str, Tuple]:
    """Lists every bundle this script writes by its full key: the spot's, a tiered bundle as one bundle per difficulty (named as
    `steps.tiered` names them), the tower's tiered battle bundles, one dividends bundle per gold amount either feature pays each turn, the effect library's bundles, and every
    boon, curse and faction-wide bundle.

    Args:
        config (Dict): The loaded config.

    Returns:
        Dict[str, Tuple]: Bundle key -> (target, icon, title, description, [(effect, scope, value)]).
    """
    flat = {}
    tower = {name: entry[:5] for name, entry in TOWER_BUNDLES.items()}
    for prefix, table in ((SPOT_BUNDLE, BUNDLES), (TOWER_BUNDLE, tower)):
        for suffix, (target, icon, title, description, effects) in table.items():
            if not any(isinstance(value, tuple) for _, _, value in effects):
                flat[prefix + suffix] = (target, icon, title, description, effects)
                continue
            for i, difficulty in enumerate(DIFFICULTIES):
                picked = ((effect, scope, value[i] if isinstance(value, tuple) else value) for effect, scope, value in effects)
                stepped = [(effect, scope, value) for effect, scope, value in picked if value is not None]
                flat[f"{prefix}{suffix}_{difficulty}"] = (target, icon, title, description, stepped)
    modifiers = config["battle_modifiers"]
    for modifier in modifiers["list"]:
        if not modifier.get("bundle"):
            continue
        for side in modifier["sides"]:
            flat[modifiers["bundle_prefix"] + modifier["key"] + "_" + side] = battle_modifiers.bundle(modifier["key"], side)
    target, icon, title, description, effect, scope = DIVIDENDS
    amounts = {offer["dividends"]["per_turn"] for offers in config["at"].values() for offer in offers.values() if "dividends" in offer}
    amounts |= {offer["per_turn"] for offers in config["tower_at"].values() for offer in offers.values() if "per_turn" in offer}
    for amount in sorted(amounts):
        flat[config["dividends_bundle_prefix"] + str(amount)] = (target, icon, title, description, [(effect, scope, amount)])
    flat.update(effect_library.bundles())
    flat.update(boons.bundles(config["boons"]))
    return flat


def plural(count: int, word: str) -> str:
    """Writes a count with its word, e.g. "1 rank" or "2 ranks".

    Args:
        count (int): The count.
        word (str): The singular word.

    Returns:
        str: The count and word.
    """
    return f"{count} {word}" if count == 1 else f"{count} {word}s"


def line_values(offer: Dict, bundles: Dict[str, Tuple]) -> Dict[str, str]:
    """Works out the values an offer's line or notice names, from the offer at one difficulty (a spot or a tower offer). Every number on the
    offer is there under its own name, e.g. {cost} or {hero_rank}, and any placeholder the offer has no value for reads as empty.

    Args:
        offer (Dict): The offer record at one difficulty.
        bundles (Dict[str, Tuple]): Every bundle the generator writes, from `expand_bundles`.

    Returns:
        Dict[str, str]: Placeholder -> value. Besides the offer's numbers: {won_gold}, {lost_gold}, {lost_turns}, {lost_strength}, {won_xp}, {won_e0}... (an outcome bundle's effects), {turns},
        {per_turn}, {per_unit}, {tiers}, {relations} (in tens), {daemon_armies}, {armies}, {heal}, {stronger}, {weaker}, {strength}, {champion}, {ally_stronger},
        {ranks}, {targets}, {minutes} (of a battle value in seconds), {garrison} (as a percent), {ally_min}, {ally_max} and {e0}, {e1}... for the
        effects of the bundle it gives, signs dropped. With more than one bundle, {e0}... are the last one's, and each bundle's are also named
        by its field, e.g. {faction_e0} and {province_e0}.
    """
    values = defaultdict(str, {key: str(value) for key, value in offer.items() if isinstance(value, int) and not isinstance(value, bool)})
    for outcome in offer.get("gamble", []):
        if not isinstance(outcome, dict):
            continue
        if "gold" in outcome:
            values[outcome["2"] + "_gold"] = str(abs(outcome["gold"]))
        if "army_bundle" in outcome:
            values[outcome["2"] + "_turns"] = str(outcome["army_bundle"][1])
            for i, (_, _, value) in enumerate(bundles.get(outcome["army_bundle"][0], ("", "", "", "", []))[4]):
                values[f"{outcome['2']}_e{i}"] = str(abs(value))
        if "own_strength" in outcome:
            values[outcome["2"] + "_strength"] = str(round(outcome["own_strength"] * 100))
        if "lord_xp" in outcome:
            values[outcome["2"] + "_xp"] = str(outcome["lord_xp"])
        if "bleed" in outcome:
            values[outcome["2"] + "_bleed"] = str(outcome["bleed"])
    for field in BUNDLE_FIELDS:
        if field not in offer:
            continue
        bundle = offer[field] if isinstance(offer[field], str) else offer[field][0]
        if not isinstance(offer[field], str):
            values["turns"] = str(offer[field][1])
        for i, (_, _, value) in enumerate(bundles.get(bundle, ("", "", "", "", []))[4]):
            values[f"e{i}"] = str(abs(value))
            values[f"{field[:-len('_bundle')]}_e{i}"] = str(abs(value))
    if "dividends" in offer:
        values["per_turn"] = str(offer["dividends"]["per_turn"])
    if "gold_per_enemy_unit" in offer:
        values["per_unit"] = str(offer["gold_per_enemy_unit"])
    tiers = offer.get("tiers") or offer.get("recruit", {}).get("tiers") or offer.get("traitor", {}).get("tiers")
    if tiers:
        values["tiers"] = tiers_text(tiers)
    if "relations" in offer:
        values["relations"] = str(abs(offer["relations"]) * 10)
    if "recruit" in offer:
        values["recruits"] = plural(offer["recruit"]["count"], "tier " + tiers_text(offer["recruit"]["tiers"]) + " unit")
    for kind in ("boon", "curse"):
        if offer.get(kind):
            values[kind] = boons.grant_text(kind, offer[kind])
    if offer.get("fail_curse"):
        values["fail_curse"] = boons.grant_text("curse", offer["fail_curse"])
    if "victory_gold" in offer:
        multiplier = offer["victory_gold"]
        values["victory_gold"] = "double victory gold" if multiplier == 2 else f"+{round((multiplier - 1) * 100)}% victory gold"
    if "garrison_strength" in offer:
        values["garrison"] = str(round(offer["garrison_strength"] * 100))
    armies = offer.get("daemon_armies", offer.get("armies"))
    if armies:
        values["daemon_armies"] = values["armies"] = "a hard Chaos army marches" if armies == 1 else f"{armies} hard Chaos armies march"
    if "heal_share" in offer:
        values["heal"] = str(round(offer["heal_share"] * 100))
    budget = offer.get("budget", offer.get("next_budget"))
    if budget:
        values["stronger"] = str(round((budget - 1) * 100))
        values["weaker"] = str(round((1 - budget) * 100))
    if "enemy_strength" in offer:
        values["strength"] = str(round(offer["enemy_strength"] * 100))
    if "champion_strength" in offer:
        values["champion"] = str(round(offer["champion_strength"] * 100))
    if "ally_budget" in offer:
        values["ally_stronger"] = str(round((offer["ally_budget"] - 1) * 100))
    if "ranks" in offer:
        values["ranks"] = plural(offer["ranks"], "rank")
    if isinstance(offer.get("battle_value"), int) and offer["battle_value"] >= 60:
        values["minutes"] = str(offer["battle_value"] // 60)
    if "targets" in offer:
        count = offer["targets"]
        values["targets"] = "most expensive unit flees" if count == 1 else f"{count} most expensive units flee"
    allies = offer.get("allies", offer.get("ally_units"))
    if allies:
        values["ally_min"], values["ally_max"] = str(allies[0]), str(allies[1])
    return values


def all_sites(config: Dict) -> List[Dict]:
    """Lists every site with a dilemma: the treasure sites, the spoils pick, the Tavern bar and the Smithy's Work Orders.

    Args:
        config (Dict): The loaded config.

    Returns:
        List[Dict]: The site records.
    """
    return config["sites"] + [config["spoils"]] + config["venues"]


def build_rows(config: Dict) -> Dict[str, List[str]]:
    """Builds every row this script owns, by file path under the mod root.

    Args:
        config (Dict): The loaded config.

    Returns:
        Dict[str, List[str]]: File path -> rows, each a tab-joined line without its line ending.
    """
    rows: Dict[str, List[str]] = {}

    def add(path: str, *fields) -> None:
        rows.setdefault(path, []).append("\t".join(str(f) for f in fields))

    def table(name: str) -> str:
        return f"db/{name}/{TABLE_FILE}"

    def line(component: str, icon: str, text: str, keep: Sequence[str] = ()) -> None:
        add(table("campaign_payload_ui_details_tables"), component, "ui/campaign ui/effect_bundles/" + icon, "default", 0)
        add(LOC_PREFIX + "campaign_payload_ui_details.loc.tsv", "campaign_payload_ui_details_description_" + component, add_stat_icons(text, keep), "false")

    def label(dilemma: str, choice: str, text: str) -> None:
        add(table("cdir_events_dilemma_choice_details_tables"), choice, dilemma, "", "")
        add(LOC_PREFIX + "cdir_events_dilemma_choice_details.loc.tsv", "cdir_events_dilemma_choice_details_localised_choice_label_" + dilemma + choice,
            text, "false")

    def add_dilemma(key: str, image: str, title: str, description: str, choices: List[str]) -> None:
        nonlocal row_id
        add(table("dilemmas_tables"), key, "false", "", "", image, "false", "Event", "UI_CAM_EVENT_Dilemma", "", "", "false")
        for option, value in [("GEN_TARGET_NONE", ""), ("VAR_CHANCE", "100"), ("VAR_FOLLOWUP_CHANCE", "100")]:
            add(table("cdir_events_dilemma_option_junctions_tables"), row_id, key, option, value, "default")
            row_id += 1
        for choice in choices:
            add(table("cdir_events_dilemma_payloads_tables"), row_id, choice, key, "TEXT_DISPLAY", "LOOKUP[dummy_do_nothing]", "default")
            row_id += 1
        add(LOC_PREFIX + "dilemmas.loc.tsv", "dilemmas_localised_title_" + key, title_case(title), "false")
        add(LOC_PREFIX + "dilemmas.loc.tsv", "dilemmas_localised_description_" + key, description, "false")

    def add_incident(key: str, image: str, title: str, description: str) -> None:
        nonlocal row_id
        add(table("incidents_tables"), key, "false", image, "false", "Event", "", "false", "", "0.0000", "false")
        for option, value in [("GEN_TARGET_NONE", ""), ("VAR_CHANCE", "100")]:
            add(table("cdir_events_incident_option_junctions_tables"), row_id, key, option, value, "default")
            row_id += 1
        add(LOC_PREFIX + "incidents.loc.tsv", "incidents_localised_title_" + key, title_case(title), "false")
        add(LOC_PREFIX + "incidents.loc.tsv", "incidents_localised_description_" + key, description, "false")

    def objective(name: str, icon: str, text: str, banner: str) -> None:
        for suffix, shown in [("", text), ("_message", banner)]:
            add(table("scripted_objectives_tables"), NOTICE_PREFIX + name + suffix, "ui/campaign ui/effect_bundles/" + icon)
            add(LOC_PREFIX + "scripted_objectives.loc.tsv", "scripted_objectives_localised_text_" + NOTICE_PREFIX + name + suffix, shown, "false")
            add(LOC_PREFIX + "scripted_objectives.loc.tsv", "scripted_objectives_localised_description_" + NOTICE_PREFIX + name + suffix, "", "false")

    by_key = {o["key"]: o for o in config["offers"]}
    bundles = expand_bundles(config)
    choice_keys = [(config["choice_key_prefix"] + o["key"].upper(), o["key"]) for o in config["offers"]] + [(config["walk_away_choice_key"], "walk_away")]
    site_keys = [(c, k) for c, k in choice_keys if k == "walk_away" or by_key[k]["pool"] not in config["battle_pools"]]
    battle_keys = [(c, k) for c, k in choice_keys if k != "walk_away" and by_key[k]["pool"] in config["battle_pools"]]
    row_id = FIRST_ROW_ID
    for site in all_sites(config):
        site_dilemma = config["dilemma_prefix"] + site["key"]
        title, description = SITES[site["key"]]
        leave = site.get("leave_line")
        footer = LEAVE_FOOTER.format(OFFERS[leave][1][0].lower() + OFFERS[leave][1][1:]) if leave else SITE_FOOTER
        add_dilemma(site_dilemma, site["ui_image"], title, description + footer, ["FIRST"])
        labels = site_keys + ([(config["signature_choice_key"], site["signature"])] if site.get("signature") else [])
        for choice, key in labels:
            # A site with its own leave line labels Walk away after it.
            shown = site.get("leave_line", key) if key == "walk_away" else key
            label(site_dilemma, choice, title_case(OFFERS[shown][0]))
        if site.get("leave_line"):
            line(config["line_prefix"] + site["leave_line"], ICONS[site["leave_line"]], OFFERS[site["leave_line"]][1])

    avoid_labels = read_labels(config["battle_dilemmas"], "SECOND")
    line(config["unaffordable_line"], UNAFFORDABLE[0], UNAFFORDABLE[1])
    line(config["taken_line"], TAKEN[0], TAKEN[1])
    for name, (text, banner) in MISSION_OBJECTIVES.items():
        objective(name, ICONS[name], text, banner)
    consequences = config["line_prefix"] + AVOID_CONSEQUENCES[0]
    line(consequences, AVOID_CONSEQUENCES[1], AVOID_CONSEQUENCES[2])
    for dilemma in config["battle_dilemmas"]:
        for choice, key in battle_keys:
            label(dilemma, choice, title_case(OFFERS[key][0]))
        label(dilemma, config["avoid_choice_key"], avoid_labels[dilemma])
    add(table("cdir_events_dilemma_choices_tables"), config["avoid_choice_key"], AVOID_ORDER)
    for notice, (colour, text) in NOTICES.items():
        offer_key = NOTICE_OFFERS.get(notice, notice)
        for difficulty, name in stepped_names(notice, config["notice_varies"].get(notice, config["notice_varies"].get(offer_key))):
            shown = text.format_map(line_values(config["at"][difficulty][offer_key], bundles))
            objective(name, ICONS[offer_key], f"[[col:{colour}]]{shown}[[/col]]", shown)
    for name, (_, _, _, _, effects, notice) in TOWER_BUNDLES.items():
        if notice:
            for _, bundle_name in stepped_names(name, any(isinstance(value, tuple) for _, _, value in effects)):
                shown = notice[1].format_map(line_values({"effect_bundle": TOWER_BUNDLE + bundle_name}, bundles))
                objective(bundle_name, notice_icon(name), f"[[col:{notice[0]}]]{shown}[[/col]]", shown)
    for spell in army_spells.spells():
        shown = army_spells.charges_text(spell, enemy=True)
        objective(army_spells.BUNDLE_NAME + spell["id"] + army_spells.ENEMY_NOTICE, SPELL_ICON, f"[[col:red]]{shown}[[/col]]", shown)
    for key, (colour, text) in TOWER_NOTICE_TEXT.items():
        for difficulty, name in notice_names(key, config):
            shown = text.format_map(line_values(config["tower_at"][difficulty][key], bundles))
            objective(name, notice_icon(key), f"[[col:{colour}]]{shown}[[/col]]", shown)
    for key in tower_line_keys(config):
        line_text, broke_text = TOWER_LINES[key]
        for difficulty, name in stepped_names(key, config["tower_varies"].get(key)):
            offer = config["tower_at"][difficulty][key]
            values = line_values(offer, bundles)
            component = config["tower_line_prefix"] + name
            line(component, tower_icon(key), line_text.format_map(values))
            if broke_text and "cost" in offer:
                line(component + config["tower_unaffordable_suffix"], tower_icon(key), broke_text.format_map(values))
    # Allies in the Dark names the theme its allied army rolled: a line per size and generic army composition, per difficulty for spots.
    for key in ALLY_OFFERS:
        tower_line, tower_broke = TOWER_LINES[key]
        for theme in battle_modifiers.ALLY_THEMES:
            ending = " " + battle_modifiers.ally_theme_text(theme)
            for difficulty in DIFFICULTIES:
                text = OFFERS[key][1].format_map(line_values(config["at"][difficulty][key], bundles))
                line(config["line_prefix"] + key + "_" + difficulty + "_" + theme, ICONS[key], text + ending)
            for difficulty, name in stepped_names(key, config["tower_varies"].get(key)):
                values = line_values(config["tower_at"][difficulty][key], bundles)
                component = config["tower_line_prefix"] + name + "_" + theme
                line(component, tower_icon(key), tower_line.format_map(values) + ending)
                line(component + config["tower_unaffordable_suffix"], tower_icon(key), tower_broke.format_map(values))

    for i, (choice, key) in enumerate(choice_keys):
        add(table("cdir_events_dilemma_choices_tables"), choice, WALK_AWAY_ORDER if key == "walk_away" else FIRST_CHOICE_ORDER + i)
        _, text = OFFERS[key]
        if key == "walk_away":
            line(config["line_prefix"] + "walk_away", ICONS[key], text)
            continue
        offer = by_key[key]
        for difficulty in DIFFICULTIES:
            values = line_values(config["at"][difficulty][key], bundles)
            component = config["line_prefix"] + key + "_" + difficulty
            line(component, ICONS[key], text.format_map(values))
            if offer["pool"] == "mission":
                taken = text.format_map(values).replace(MISSION, f"[[col:yellow]]{title_case(OFFERS[key][0])} (Mission):[[/col]] ", 1)
                add(STRINGS_LOC, config["mission_set_loc_prefix"] + key + "_" + difficulty, taken, "false")

    modifiers = config["battle_modifiers"]
    for modifier in modifiers["list"]:
        key, harm = modifier["key"], modifier["harm"]
        add(STRINGS_LOC, modifiers["line_prefix"] + key, battle_modifiers.line_text(key), "false")
        shown = battle_modifiers.notice_text(key)
        _, _, icon, _ = battle_modifiers.MODIFIERS[key]
        line(modifiers["payload_prefix"] + key, icon, battle_modifiers.payload_text(key, harm))
        objective(modifiers["notice_prefix"] + key, icon, f"[[col:{battle_modifiers.HARM_COLOUR[harm]}]]{shown}[[/col]]", shown)
    for effect, (junction, ability, name) in battle_modifiers.ABILITY_EFFECTS.items():
        add(table("effects_tables"), effect, "general_ability.png", 310, "general_ability.png", "battle", "true")
        add(LOC_PREFIX + "effects.loc.tsv", "effects_description_" + effect, f'Passive ability: "{name}" for all units', "false")
        add(table("unit_set_unit_ability_junctions_tables"), junction, ability, "all_units")
        add(table("effect_bonus_value_unit_set_unit_ability_junctions_tables"), "enable", effect, junction)

    for table_name, fields in effect_library.custom_rows():
        add(table(table_name), *fields)
    for loc, key, text in effect_library.custom_texts():
        add(LOC_PREFIX + loc + ".loc.tsv", key, text, "false")

    for key, (target, icon, title, description, effects) in bundles.items():
        add(table("effect_bundles_tables"), key, "", "", target, 1, icon, "true" if target == "faction" else "false", "false", "true")
        for effect, scope, value in effects:
            add(table("effect_bundles_to_effects_junctions_tables"), key, effect, scope, f"{value:.4f}", "start_turn_completed")
        add(LOC_PREFIX + "effect_bundles.loc.tsv", "effect_bundles_localised_title_" + key, title_case(title), "false")
        add(LOC_PREFIX + "effect_bundles.loc.tsv", "effect_bundles_localised_description_" + key, description, "false")

    messages = dict(MESSAGES)
    for key, (title, met, failed) in MISSION_MESSAGES.items():
        messages["mission_" + key + "_met"] = (title, "Mission Met", met)
        messages["mission_" + key + "_failed"] = (title, "Mission Failed", failed)
    messages["missions_untracked"] = ("Missions", "Not Counted",
                                      "The battle was fought without our watchful eyes on it. The armies clashed and the matter was settled, but nobody "
                                      "was there to count what happened.\\n\\nSo none of our missions could be judged. No vow was kept and no "
                                      "vow was broken, and no reward or penalty comes of them.\\n\\nAny gold we wagered on them is returned to our "
                                      "treasury. Next time, our officers will have to watch the fighting closely, from the first charge to the last "
                                      "man standing.")

    for key, (icon, levels) in TRAITS.items():
        add(table("character_traits_tables"), key, 0, "false", 999, icon, 1, "", "false")
        add(table("trait_info_tables"), key)
        for number, (points, name, colour, explanation, effects) in enumerate(levels, 1):
            level = f"{key}_{number}"
            add(table("character_trait_levels_tables"), level, number, key, points)
            for effect, scope, value in effects:
                add(table("trait_level_effects_tables"), level, effect, scope, f"{value:.4f}")
            for field, text in [("onscreen_name", title_case(name)), ("colour_text", colour), ("explanation_text", explanation), ("removal", "")]:
                add(LOC_PREFIX + "character_traits.loc.tsv", f"character_trait_levels_{field}_{level}", text, "false")

    lines = dict(RESULT_LINES)
    for key, (title, _, _) in MISSION_MESSAGES.items():
        lines["mission_" + key + "_failed"] = ("red", f"{title_case(title)}: mission failed.")
    for suffix, (title, subtitle, description) in messages.items():
        name = config["message_prefix"] + suffix
        for field, text in [("title", title_case(title)), ("subtitle", title_case(subtitle or title)), ("description", fallback_text(description, FALLBACK_PLACES.get(suffix, "")))]:
            add(LOC_PREFIX + "event_feed_strings.loc.tsv", f"event_feed_strings_text_{field}_event_land_enc_{name}", text, "false")
        image = RESULT_IMAGES.get(suffix) or (MISSION_RESULT_IMAGE if suffix.startswith("mission") else RESULT_IMAGE)
        place = f'{{{{CcoCampaignEventIncident:ScriptObjectContext("{config["result_place_context"]}").StringValue}}}}'
        detail = f'{{{{CcoCampaignEventIncident:ScriptObjectContext("{config["result_detail_context"]}").StringValue}}}}'
        shown = description.replace("{place}", f"[[col:yellow]]{place}[[/col]]").replace("{detail}", f"[[col:yellow]]{detail}[[/col]]")
        add_incident(config["result_incident_prefix"] + suffix, image, title, shown)
        if suffix in lines:
            colour, text = lines[suffix]
            offer_key = result_key(suffix)
            offer_key = offer_key if offer_key in config["at"][DIFFICULTIES[0]] else ""
            for difficulty in DIFFICULTIES:
                shown = text.format_map(line_values(config["at"][difficulty][offer_key], bundles)) if offer_key else text
                line(config["line_prefix"] + "result_" + suffix + "_" + difficulty, result_icon(suffix), f"[[col:{colour}]]{shown}[[/col]]")
    boon_config = config["boons"]
    for component, icon, text in boons.lines(boon_config):
        line(component, icon, text)
    for effect, text in boons.clocks(boon_config):
        add(table("effects_tables"), effect, boons.CLOCK_ICON, boons.CLOCK_PRIORITY, boons.CLOCK_ICON, "campaign", "true")
        add(LOC_PREFIX + "effects.loc.tsv", "effects_description_" + effect, text, "false")
    boon_dilemmas = boons.dilemmas(boon_config)
    drop_label, new_label = boons.FULL_DILEMMA[3:]
    title, description, image = boon_dilemmas["full"]
    full_choices = boon_config["full_choices"] + [boon_config["full_new_choice"]]
    add_dilemma(boon_config["full_dilemma"], image, title, description, full_choices)
    for i, choice in enumerate(full_choices):
        add(table("cdir_events_dilemma_choices_tables"), choice, boons.FULL_CHOICE_ORDER + i)
        label(boon_config["full_dilemma"], choice, title_case(new_label if choice == boon_config["full_new_choice"] else drop_label))
    # The tower offers granting boons and curses get their choice rows here. Every other tower choice is a hand row.
    for i, (choice, key) in enumerate(tower_grant_choices(config)):
        add(table("cdir_events_dilemma_choices_tables"), choice, TOWER_GRANT_ORDER + i)
        for tower_dilemma in config["tower_deeper_dilemmas"]:
            label(tower_dilemma, choice, title_case(TOWER_NAMES.get(key) or boons.OFFERS[key]))
    title, description, image = boon_dilemmas["pick"]
    pick_label = boons.PICK_DILEMMA[3]
    add_dilemma(boon_config["pick_dilemma"], image, title, description, boon_config["pick_choices"])
    for i, choice in enumerate(boon_config["pick_choices"]):
        add(table("cdir_events_dilemma_choices_tables"), choice, boons.PICK_CHOICE_ORDER + i)
        label(boon_config["pick_dilemma"], choice, title_case(pick_label))
    for room, name in (("smithy_room", "smithy"), ("witch_room", "witch")):
        title, description, image = boon_dilemmas[name]
        add_dilemma(boon_config[room]["dilemma"], image, title, description, boons.room_choices(boon_config, room))
    for choice, order, shown in boons.service_choices(boon_config):
        add(table("cdir_events_dilemma_choices_tables"), choice, order)
        for dilemma, text in shown:
            label(dilemma, choice, title_case(text))
    for component, icon, text in boons.service_lines(boon_config):
        line(component, icon, text)
    for spell in army_spells.spells():
        line(army_spells.LINE_PREFIX + spell["id"], "magic.png", army_spells.line_text(spell), [spell["name"]])
    for key, text in boons.results(boon_config):
        add(STRINGS_LOC, key, text, "false")
    spot_names = {key: name for key, (name, _) in OFFERS.items()}
    for _, _, key, text in boons.guide(boon_config, config["offers"], config["tower_offers"], {**spot_names, **TOWER_NAMES}):
        add(STRINGS_LOC, key, add_stat_icons(text), "false")
    for event, (title, description, image) in boons.incidents(boon_config).items():
        add_incident(boon_config["incident_prefix"] + event, image, title, description)
    return rows


def result_key(result: str) -> str:
    """Strips a result name down to the offer or mission it belongs to.

    Args:
        result (str): The result name, e.g. "cast_the_lots_lost", "mission_untouchable_met" or "bountiful_harvest".

    Returns:
        str: The offer or mission key, e.g. "cast_the_lots" or "untouchable". A result of no offer comes back as it is, e.g. "missions_untracked".
    """
    result = re.sub(r"^mission_", "", result)
    keys = [key for key in list(OFFERS) + list(MISSION_MESSAGES) if result == key or result.startswith(key + "_")]
    return max(keys, key=len) if keys else result


def fallback_text(description: str, place: str) -> str:
    """Words a result's description for its fallback message, which cannot name the place, so {place} becomes the message's own words for it.

    Args:
        description (str): The description, maybe with {place}.
        place (str): What the message says in place of {place}, from `FALLBACK_PLACES`, e.g. "that region".

    Returns:
        str: The description for the event feed message.
    """
    if description.startswith("{place}"):
        description = place[0].upper() + place[1:] + description[len("{place}"):]
    return description.replace("{place}", place).replace(": {detail}", "").replace("{detail}", "")


def result_icon(result: str) -> str:
    """Picks the icon of a result's effect line: its offer's or mission's icon, or the treasury or wound icon.

    Args:
        result (str): The result name, e.g. "cast_the_lots_won" or "mission_headhunt_failed".

    Returns:
        str: The icon file under the effect bundle icons.
    """
    if result == "missions_untracked":
        return "treasury.png"
    return ICONS[result_key(result)]


def read_labels(dilemmas: List[str], choice: str) -> Dict[str, str]:
    """Reads each dilemma's existing label for a vanilla choice key, e.g. the Avoid text of the battle dilemmas' SECOND choice.

    Args:
        dilemmas (List[str]): The dilemma keys.
        choice (str): The choice key, e.g. "SECOND".

    Returns:
        Dict[str, str]: Dilemma key -> its label.

    Raises:
        SystemExit: When a dilemma has no label for the choice.
    """
    prefix = "cdir_events_dilemma_choice_details_localised_choice_label_"
    labels = {}
    for line in open(MOD_ROOT + LOC_PREFIX + "cdir_events_dilemma_choice_details.loc.tsv", encoding="utf-8").read().splitlines():
        key, _, rest = line.partition("\t")
        if key.startswith(prefix) and key.endswith(choice):
            labels[key[len(prefix):-len(choice)]] = rest.split("\t")[0]
    missing = [d for d in dilemmas if d not in labels]
    if missing:
        raise SystemExit(f"No {choice} label for: " + ", ".join(missing))
    return labels


def hook_battle_descriptions(config: Dict, dry_run: bool) -> None:
    """Starts every battle dilemma's description with the missions-taken context, as the tower's floors start with their results.

    Args:
        config (Dict): The loaded config.
        dry_run (bool): True to only print how many would change.
    """
    hook = '{{CcoCampaignEventDilemma:ScriptObjectContext("' + config["missions_context"] + '").StringValue}}'
    path = MOD_ROOT + LOC_PREFIX + "dilemmas.loc.tsv"
    lines = open(path, "rb").read().decode("utf-8").splitlines(keepends=True)
    wanted = {"dilemmas_localised_description_" + d for d in config["battle_dilemmas"]}
    changed = 0
    for i, line in enumerate(lines):
        fields = line.split("\t")
        if fields[0] in wanted and not fields[1].startswith(hook):
            fields[1] = hook + fields[1]
            lines[i] = "\t".join(fields)
            changed += 1
    print(f"{LOC_PREFIX}dilemmas.loc.tsv: {changed} battle descriptions hooked")
    if changed and not dry_run:
        open(path, "wb").write("".join(lines).encode("utf-8"))


def notice_icon(key: str) -> str:
    """Picks a Tower battle notice's icon: its bundle's own, unless that is the garrison fallback, else the tower line's.

    Args:
        key (str): The bundle or notice key.

    Returns:
        str: The icon file, or an empty string when there is none.
    """
    bundle = TOWER_BUNDLES.get(key)
    return bundle[1] if bundle and bundle[1] != GARRISON_ICON else tower_icon(key)


def tower_icon(key: str) -> str:
    """Picks a tower line's or notice's icon: its own, or the spot offer's of the same key.

    Args:
        key (str): The offer key.

    Returns:
        str: The icon file, or an empty string when neither has one.
    """
    return TOWER_ICONS.get(key) or ICONS.get(key, "")


def notice_names(notice: str, config: Dict) -> List[Tuple[str, str]]:
    """Lists a notice's names: one per difficulty when its effect differs by it, else its own name once, shown with the Easy numbers.

    Args:
        notice (str): The notice's base name, e.g. "thin_the_ranks" or "night_raid_lost".
        config (Dict): The loaded config.

    Returns:
        List[Tuple[str, str]]: (difficulty, notice name) pairs.
    """
    return stepped_names(notice, config["notice_varies"].get(notice))


def stepped_names(base: str, stepped: bool) -> List[Tuple[str, str]]:
    """Names a row that may differ by difficulty: one name per difficulty when it does, else the base name once, shown with the Easy numbers.

    Args:
        base (str): The base name.
        stepped (bool): True when the row differs by difficulty.

    Returns:
        List[Tuple[str, str]]: (difficulty, name) pairs.
    """
    if stepped:
        return [(difficulty, f"{base}_{difficulty}") for difficulty in DIFFICULTIES]
    return [(DIFFICULTIES[0], base)]


def tower_line_keys(config: Dict) -> List[str]:
    """Lists the tower offers whose lines this script writes: those that differ by difficulty, and those with text in `TOWER_LINES`.

    Args:
        config (Dict): The loaded config.

    Returns:
        List[str]: Offer keys in config order.
    """
    return [offer["key"] for offer in config["tower_offers"] if config["tower_varies"].get(offer["key"]) or offer["key"] in TOWER_LINES]


def tower_grant_choices(config: Dict) -> List[Tuple[str, str]]:
    """The tower offers whose choice rows this script writes: those granting boons and curses, and those named in `TOWER_NAMES`. Every other
    tower choice is a hand row.

    Args:
        config (Dict): The loaded config.

    Returns:
        List[Tuple[str, str]]: (choice key, offer key) in config order.
    """
    return [(config["tower_choice_key_prefix"] + o["key"].upper(), o["key"]) for o in config["tower_offers"] if boons.grants(o) or o["key"] in TOWER_NAMES]


def owned_patterns(config: Dict) -> List[Pattern]:
    """Builds the patterns of the tower rows this script owns, by the key a row starts with (a loc key ends with it): the lines of the tower
    offers that differ by difficulty, the tiered tower bundles, and the notices of both, with or without a difficulty.

    Args:
        config (Dict): The loaded config.

    Returns:
        List[Pattern]: One pattern per kind of row.
    """
    tower_notices = list(TOWER_NOTICE_TEXT)
    bundle_notices = [name for name, entry in TOWER_BUNDLES.items() if entry[5]]
    bundle_notices += [army_spells.BUNDLE_NAME + spell["id"] + army_spells.ENEMY_NOTICE for spell in army_spells.spells()]
    difficulty = f"(?:_(?:{'|'.join(DIFFICULTIES)}))?"
    kinds = [(config["tower_line_prefix"], tower_line_keys(config), "(?:_unaffordable)?"), (TOWER_BUNDLE, list(TOWER_BUNDLES), ""),
             (NOTICE_PREFIX, tower_notices + bundle_notices + list(NOTICES) + list(MISSION_OBJECTIVES), "(?:_message)?")]
    patterns = [re.compile(f"(?:^|_){prefix}(?:{'|'.join(names)}){difficulty}{tail}$") for prefix, names, tail in kinds]
    patterns.append(re.compile(f"(?:^|_)(?:{'|'.join(re.escape(p) for p in boons.owned_prefixes(config['boons']))})"))
    patterns.append(re.compile(f"(?:{'|'.join(choice for choice, _ in tower_grant_choices(config))})$"))
    patterns.append(re.compile(f"(?:{'|'.join(choice for choice, _, _ in boons.service_choices(config['boons']))})$"))
    return patterns


def owned(line: str, patterns: List[Pattern]) -> bool:
    """True when a row belongs to this script, so a run replaces it.

    Args:
        line (str): The row.
        patterns (List[Pattern]): The owned tower row patterns, from `owned_patterns`.

    Returns:
        bool: True for spot offer rows, including the FIRST choice rows on site dilemmas, and the tower rows in `patterns`.
    """
    key = line.split("\t", 1)[0]
    return any(marker in line for marker in OWNED_MARKERS) or line.startswith("70181") or any(p.search(key) for p in patterns)


def write_rows(rows: Dict[str, List[str]], patterns: List[Pattern], dry_run: bool) -> None:
    """Replaces this script's rows in each file, keeping every other row and the file's header as they are.

    Args:
        rows (Dict[str, List[str]]): File path -> rows from `build_rows`.
        patterns (List[Pattern]): The owned tower row patterns, from `owned_patterns`.
        dry_run (bool): True to only print what would change.
    """
    for path, new_rows in sorted(rows.items()):
        full = MOD_ROOT + path
        if not os.path.exists(full):
            name = path.split("/")[-1].replace(".tsv", "")
            open(full, "wb").write(f"key\ttext\ttooltip\r\n#Loc;1;text/db/{name}\t\t\r\n".encode("utf-8"))
        lines = open(full, "rb").read().decode("utf-8").splitlines(keepends=True)
        kept = lines[:2] + [line for line in lines[2:] if not owned(line, patterns)]
        if kept and not kept[-1].endswith("\n"):
            kept[-1] += "\r\n"
        print(f"{path}: -{len(lines) - len(kept)} +{len(new_rows)}")
        if not dry_run:
            with open(full, "wb") as f:
                f.write(("".join(kept) + "".join(row + "\r\n" for row in new_rows)).encode("utf-8"))


def write_army_spells(dry_run: bool) -> None:
    """Writes the Lua list of the army spell pools the offers roll from.

    Args:
        dry_run (bool): True to only print what would be written.
    """
    text = army_spells.lua()
    print(f"{army_spells.LUA}: {sum(len(v) for v in army_spells.load().values())} spells")
    if not dry_run:
        open(MOD_ROOT + army_spells.LUA, "w", encoding="utf-8", newline="\n").write(text)


def write_victory_gold(dry_run: bool) -> None:
    """Writes the Lua table of each battle victory incident's treasury gold, read from the incidents' payload rows.

    Args:
        dry_run (bool): True to only print what would be written.
    """
    rows = open(MOD_ROOT + "db/cdir_events_incident_payloads_tables/" + TABLE_FILE, encoding="utf-8").read().splitlines()[2:]
    gold = {}
    for row in rows:
        fields = row.split("\t")
        if len(fields) > 3 and fields[1].startswith("land_enc_incident_battle_won") and fields[2] == "TREASURY":
            gold[fields[1]] = int(fields[3].split("[")[1].rstrip("]"))
    body = "".join(f'    ["{key}"] = {amount},\n' for key, amount in sorted(gold.items()))
    text = ("--- Each battle victory incident's treasury gold, which battle modifiers scale. Generated by\n"
            "--- helper_scripts/generators/update_leapoi_spot_offers.py from the incidents' payload rows: do not edit by hand.\n\n"
            "return {\n" + body + "}\n")
    print(f"{VICTORY_GOLD_LUA}: {len(gold)} incidents")
    if not dry_run:
        open(MOD_ROOT + VICTORY_GOLD_LUA, "w", encoding="utf-8", newline="\n").write(text)


def check_text(config: Dict) -> None:
    """Stops when an offer or site has no text or icon, a paid offer has no not-enough-gold line, or any text writes gold with a separator.

    Args:
        config (Dict): The loaded config.

    Raises:
        SystemExit: Naming every problem found.
    """
    problems = [f"no text for {o['key']}" for o in config["offers"] if o["key"] not in OFFERS]
    problems += [f"no story for {o['key']}" for o in config["offers"] if o.get("story") and o["key"] not in MESSAGES]
    problems += [f"no text for leave line {s['leave_line']}" for s in all_sites(config) if s.get("leave_line") and s["leave_line"] not in OFFERS]
    modifier_keys = {m["key"] for m in config["battle_modifiers"]["list"]}
    generic = {m["key"] for m in config["battle_modifiers"]["list"] if "army" in m and "faction" not in m}
    problems += [f"no allied theme text for {key}" for key in sorted(generic ^ set(battle_modifiers.ALLY_THEMES))]
    problems += [f"no text for battle modifier {key}" for key in sorted(modifier_keys - set(battle_modifiers.MODIFIERS))]
    problems += [f"text for unknown battle modifier {key}" for key in sorted(set(battle_modifiers.MODIFIERS) - modifier_keys)]
    problems += [f"no text for site {s['key']}" for s in all_sites(config) if s["key"] not in SITES]
    problems += [f"no icon for {key}" for key in OFFERS if key not in ICONS]
    problems += [f"no notice for {o['key']}" for o in config["offers"]
                 if o["pool"] == "pre_battle" and "battle_bundle" not in o and "spell_pool" not in o and "gamble" not in o and "trick" not in o
                 and o["key"] not in NOTICES
                 and o["key"] not in config["tower_at"]["easy"]]
    problems += [f"no messages for mission {o['key']}" for o in config["offers"] if o["pool"] == "mission" and o["key"] not in MISSION_MESSAGES]
    problems += [f"no notice icon for tower bundle {name}" for name, entry in TOWER_BUNDLES.items() if entry[5] and not tower_icon(name)]
    problems += [f"no tower line for {key}" for key in tower_line_keys(config) if key not in TOWER_LINES or not tower_icon(key)]
    problems += [f"no tower notice for {key}" for key, varies in config["notice_varies"].items()
                 if varies and key not in TOWER_NOTICE_TEXT and key in config["tower_at"]["easy"]
                 and (config["tower_at"]["easy"][key].get("trick") or config["tower_at"]["easy"][key]["guide_section"] == "sabotage")]
    problems += [f"no result for line {key}" for key in RESULT_LINES if key not in MESSAGES and not key.startswith("mission")]
    problems += boons.problems(config["boons"])
    problems += [f"no fallback place for {key}" for key, (_, _, description) in MESSAGES.items() if "{place}" in description and key not in FALLBACK_PLACES]
    bundles = expand_bundles(config)
    problems += [f"no bundle {bundle} for {key}" for offers in config["at"].values() for key, offer in offers.items()
                 for fields in [offer] + offer.get("gamble", []) for field in BUNDLE_FIELDS
                 for bundle in [fields.get(field, [""])[0] if isinstance(fields, dict) else ""] if bundle.startswith(SPOT_BUNDLE) and bundle not in bundles]
    every = [t for entry in OFFERS.values() for t in entry if t] + [t for entry in MESSAGES.values() for t in entry] + [d for _, d in SITES.values()]
    every += [t for _, t in RESULT_LINES.values()]
    problems += [f"gold with a separator: {t}" for t in every if re.search(r"\d,\d{3}", t)]
    if problems:
        raise SystemExit("\n".join(problems))


def check_event_lengths() -> None:
    """Stops when any dilemma or incident description in the mod's loc files is too short to fill the notification panel's description box,
    which leaves a dark gap under it. Covers the hand-written rows as well as the generated ones. A long one only scrolls, which the dilemmas
    that list a Tower floor or a Tavern room need.

    Raises:
        SystemExit: Naming every description under `boons.MIN_LINES` lines, with its line count.
    """
    problems = []
    for name in ("dilemmas", "incidents"):
        prefix = f"{name}_localised_description_"
        rows = [line.split("\t") for line in open(MOD_ROOT + LOC_PREFIX + name + ".loc.tsv", encoding="utf-8").read().splitlines()[2:]]
        for key, text, *_ in rows:
            lines = boons.shown_lines(text)
            if key.startswith(prefix) and lines < boons.MIN_LINES:
                problems.append(f"{key[len(prefix):]} fills {lines} lines, not {boons.MIN_LINES} or more")
    if problems:
        raise SystemExit("Event descriptions that would leave a gap:\n  " + "\n  ".join(problems))


def main() -> None:
    """Loads the config, checks the text, and writes the rows."""
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--dry-run", action="store_true", help="Print what would change without writing.")
    args = parser.parse_args()
    if not os.path.isdir(MOD_ROOT):
        raise SystemExit(f"Mod folder not found at {MOD_ROOT}. Run from helper_scripts/.")
    config = load_config()
    check_text(config)
    write_rows(build_rows(config), owned_patterns(config), args.dry_run)
    write_victory_gold(args.dry_run)
    write_army_spells(args.dry_run)
    hook_battle_descriptions(config, args.dry_run)
    check_event_lengths()


if __name__ == "__main__":
    main()
