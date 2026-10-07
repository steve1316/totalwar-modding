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
from typing import Dict, List, Pattern, Tuple

from generators.leapoi_tower_offer_text import NOTICES as TOWER_NOTICE_TEXT, TOWER_BUNDLES, TOWER_ICONS, TOWER_LINES
from generators import leapoi_battle_modifiers as battle_modifiers
from generators.leapoi_stat_icons import add_stat_icons

MOD_ROOT = "../warhammer3_mods/land_encounters_and_points_of_interest_with_mct/"
TABLE_FILE = "land_encounters_and_points_of_interest.tsv"
LOC_PREFIX = "text/db/land_enc_and_poi_"

# First id of the option junction and payload rows, clear of the tower's 70179007xx ids.
FIRST_ROW_ID = 7018100000

# Choice order of the offers, in config order from this number. A site's signature sits on the vanilla FIRST key, and Walk away comes last.
FIRST_CHOICE_ORDER = 300
WALK_AWAY_ORDER = 998

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
                 "land_enc_ability_enable_", "dummy_land_enc_tower_allies_in_the_dark_")

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
    "mystery_brew_won": "army_morale_up",
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
    "wound_paid_2": "attrition_disease",
    "wound_paid_3": "attrition_disease",
    "wound_paid_5": "attrition_disease",
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
    "hidden_tomb": ("Hidden Tomb", "A forgotten tomb lies half-buried in the hillside, its door split by roots and time. The wards carved into the stone are old, "
                    "but not all of them have failed, and something inside still remembers how to bite."),
    "abandoned_camp": ("Abandoned Camp", "Cold fires and empty tents stand in a sheltered hollow. Whoever camped here left in a hurry, "
                       "and left their stores and a fair share of loot behind."),
    "buried_relics": ("Buried Relics", "Bones of something enormous jut from the churned earth. Among them lie older things, weapons and charms buried long "
                      "before the beast ever died here."),
    "hidden_temple": ("Hidden Temple", "A temple rises from the wilds, its walls choked with vines but its altar swept clean, as if someone still "
                      "tends it. Its keepers left long ago, yet offerings laid here are still answered."),
    "caravan_remnants": ("Caravan Remnants", "A half-sacked caravan lies across the road, its wagons overturned and its goods scattered in the mud. The raiders "
                         "were in a hurry, and they missed more than they took."),
    "whispers_of_our_god": ("A Voice in the Dream", "Our lord wakes from a dream more vivid than any waking hour. A voice spoke in it, offering strength for the "
                            "trials ahead, and some of its gifts come with a price."),
    "the_explorer": ("The Explorers", "A band of weathered explorers shares our fire for the night. They trade maps and tales of the road ahead, and ask only "
                     "for safe passage in return."),
    "legendary_bard": ("Legendary Bard", "A famous bard sits in chains in a bandit camp we have just put to flight. Freed, they promise to sing of our deeds "
                       "in every hall and war camp across the land."),
    "ruined_shrine": ("Ruined Shrine", "A burnt-out shrine stands by the road, its idols blackened and cracked. Offerings left here may be answered with a blessing, or "
                      "with something far less kind."),
    "smugglers_cache": ("Smugglers' Cache", "Crates and barrels lie hidden under a false floor, and their owners watch us from the treeline. They deal in "
                        "goods and secrets, and they are open to offers."),
    "beast_lair": ("Beast Lair", "Something big lives in this cave. Fresh bones litter the entrance, and the stench carries on the "
                   "wind for a mile."),
    "old_battlefield": ("Old Battlefield", "Crows wheel over an old battlefield where two armies broke each other long ago. Wrecked war machines "
                        "and unburied bones still lie half sunk in the mud."),
    "witchs_hut": ("Witch's Hut", "A crooked hut squats in the marsh, thick with smoke and stranger smells. The witch who lives here deals in pacts "
                   "and curses, and every one of them has a price."),
    "collapsed_mine": ("Collapsed Mine", "A collapsed mine yawns in the hillside, its lower galleries half-flooded. The deeper tunnels are still rich, and "
                       "still deadly to anyone who lingers."),
    "merchants_wagon": ("Merchant's Wagon", "A travelling merchant has lost the road and most of their escort. Far from any market and glad of any customer, "
                        "they throw open their wagon to us."),
    "sunken_library": ("Sunken Library", "A library has sunk into the marsh, its shelves rotting in black water. Some scrolls survive, sealed in wax and lead, "
                       "holding the secrets of other realms."),
    "spoils_of_war": ("Spoils of War", "The field is ours. Enemy dead lie in heaps, and their baggage stands abandoned where they broke and ran. "
                      "Before we march on, there is more to take from this victory."),
    "tavern_bar": ("The Bar", "The keeper leans on the bar beside barrels for every taste. Over at the tables, strangers are rolling dice, and a "
                   "hulking champion waits for anyone brave enough to lock arms with them.\\\\n\\\\nThe barkeep turns to us: \"What'll it be?\""
                   "\\\\n\\\\n[[col:yellow]]By Tavern level:[[/col]]\\\\n- Level 1: the house brews (Fighting Spirits gives +5), a feast heals half of each unit's losses, "
                   "rumours cover the 3 nearest regions, and beating the champion is worth 500 experience."
                   "\\\\n- Level 2: stronger brews (+10), a feast heals three quarters of the losses, rumours cover 5 regions, "
                   "and the champion is worth 750 experience."
                   "\\\\n- Level 3: the strongest brews (+15), a feast heals every loss, rumours cover 7 regions, "
                   "and the champion is worth 1000 experience."),
}

# Shown under every site's description: the rules, said once, then the choice. Loc files store a line break as an escaped `\\n`.
SITE_FOOTER = "\\\\n\\\\n[[col:yellow]]Choose one, or walk away.[[/col]]"
# Footer of a site whose last choice is its own leave line, ending with that line's text, e.g. "go back to the common room.".
LEAVE_FOOTER = "\\\\n\\\\n[[col:yellow]]Choose one, or {}[[/col]]"

# Offer key -> (choice label, line). A line may use {cost}, {gold}, {won_gold}, {lost_gold} and {per_turn}, filled per difficulty.
OFFERS: Dict[str, Tuple[str, str]] = {
    "tomb_robbing": ("Rob the Tomb", "Rob the tomb: [[col:green]]a random item[[/col]] and [[col:green]]+2000 experience[[/col]] for our lord."),
    "abandoned_camp": ("Rest at the Camp", "Rest at the camp: [[col:green]]+5% replenishment[[/col]] for 3 turns."),
    "buried_relics": ("Dig Up the Relics", "Dig up the relics: [[col:green]]a random item[[/col]]."),
    "hidden_temple": ("Pray at the Temple", "Pray at the temple: [[col:green]]+5% ward save[[/col]] for 5 turns, and our lord gains [[col:green]]+250 experience[[/col]] each turn."),
    "caravan_remnants": ("Salvage the Caravan", "Salvage the caravan: [[col:green]]+2500 gold[[/col]] to our treasury, [[col:green]]a random item[[/col]] and [[col:green]]+500 experience[[/col]] for our lord."),
    "whispers_of_the_gods": ("Heed the Whisper", "Heed the whisper: our army is [[col:green]]unbreakable[[/col]] and [[col:green]]never tires[[/col]] for 3 turns, and our lord gains [[col:green]]+250 experience[[/col]] each turn."),
    "the_explorer": ("Hear the Explorers Out", "Hear the explorers out: [[col:green]]+15% movement range[[/col]] and [[col:green]]+15% ambush defence[[/col]] for 5 turns."),
    "legendary_bard": ("Free the Bard", "Free the bard: [[col:green]]+5% income[[/col]] and [[col:green]]-25% construction cost[[/col]] in our provinces for 5 turns."),

    "take_the_gold": ("Take the Gold", "Take the gold: [[col:green]]+{gold} gold[[/col]] to our treasury."),
    "strip_the_valuables": ("Strip the Valuables", "Strip everything of value: [[col:green]]+{gold} gold[[/col]] to our treasury, but our army is weighed down: "
                            + stat("-15", *LEADERSHIP, colour="red") + " and " + stat("-10%", *SPEED, colour="red") + " for 3 turns."),
    "pry_open_the_reliquary": ("Pry Open the Reliquary", "Pry open the reliquary: [[col:green]]a random rare item[[/col]], but our lord is [[col:red]]wounded for 2 turns[[/col]]."),
    "search_every_corner": ("Search Every Corner", "Search every corner: [[col:green]]2 random items[[/col]], but our army [[col:red]]cannot move again this turn[[/col]]."),
    "the_hidden_vault": ("Open the Hidden Vault", PAY + "open the hidden vault: [[col:green]]1 unique item[[/col]]."),
    "cast_the_lots": ("Cast the Lots", "Cast the lots: a 50/50 chance of [[col:green]]a random rare item[[/col]] or [[col:red]]losing {lost_gold} gold[[/col]]."),
    "drink_from_the_spring": ("Drink from the Spring", "Drink from the spring: a 50/50 chance every unit is [[col:green]]healed to full[[/col]] or our army suffers [[col:red]]attrition for {lost_turns} turns[[/col]]."),
    "open_the_sealed_door": ("Open the Sealed Door", "Open the sealed door: a 50/50 chance of [[col:green]]1 unique item[[/col]] or our lord [[col:red]]wounded for 3 turns[[/col]]."),
    "wake_the_guardian": ("Wake the Guardian", "Wake the guardian: a 60/40 chance of [[col:green]]a random rare item[[/col]] or [[col:red]]it attacks[[/col]] and a battle starts here."),
    "touch_the_relic": ("Touch the Relic", "Touch the relic: our army gets a random [[col:green]]blessing for 5 turns[[/col]] or [[col:red]]curse for 3 turns[[/col]]."),
    "gamble_with_the_hermit": ("Gamble with the Hermit", PAY + "gamble with the hermit: a 1 in 3 chance of [[col:green]]1 unique item[[/col]]."),
    "leave_an_offering": ("Leave an Offering", PAY + "leave an offering: [[col:green]]+{e0}% ward save[[/col]] for our army for 5 turns."),
    "bless_the_banners": ("Bless the Banners", PAY + "bless our banners: [[col:green]]+{e0}[[/col]] [[img:ui/skins/default/icon_stat_attack.png]][[/img]] melee attack and "
                          "[[img:ui/skins/default/icon_stat_morale.png]][[/img]] leadership for 5 turns."),
    "stoneskin": ("Stoneskin", PAY + "have the shrine cast a ward of living stone: [[col:green]]+{e0}% physical resistance[[/col]] for our army for 5 turns."),
    "oath_at_the_altar": ("Oath at the Altar", "Swear an oath at the altar: our lord is [[col:green]]Shrine-Sworn[[/col]] for good (" + stat("+5", *LEADERSHIP)
                          + " for our army), but its keepers [[col:red]]attack[[/col]] and a hard battle starts here."),
    "double_or_nothing": ("Double or Nothing", "Stake [[col:yellow]]{cost} gold[[/col]] from our treasury: a 50/50 chance it comes back as [[col:green]]{won_gold} gold[[/col]] "
                          "or is [[col:red]]lost[[/col]]."),
    "enchanted_steel": ("Enchanted Steel", PAY + "enchant our steel: [[col:green]]magical attacks[[/col]] for every unit for {turns} turns."),
    "dark_bargain": ("Strike a Dark Bargain", "Strike a dark bargain: our lord is [[col:green]]Daemon-Marked[[/col]] for good (" + stat("+10", *ATTACK)
                     + ", [[col:green]]+10%[[/col]] [[img:ui/skins/default/icon_stat_damage.png]][[/img]] weapon strength and " + stat("+10%", *SPEED)
                     + "), but is [[col:red]]wounded for 5 turns[[/col]]."),
    "plague_bearer": ("Take the Cursed Hoard", "Take the cursed hoard: [[col:green]]+{gold} gold[[/col]] to our treasury, but our army suffers [[col:red]]attrition for {turns} turns[[/col]]."),
    "bloodstained_blades": ("Take the Bloodstained Blades", "Take up the bloodstained blades: " + stat("+20", *ATTACK) + ", but " + stat("-20", *DEFENCE, colour="red") + " for 5 turns."),
    "feed_the_shadows": ("Feed the Shadows", "Feed the shadows: sacrifice our [[col:red]]weakest unit[[/col]], and every other unit [[col:green]]gains 1 rank[[/col]]."),
    "daemons_deal": ("Strike a Daemon's Deal", "Strike a daemon's deal: [[col:green]]{unique} unique items[[/col]] now, but [[col:red]]{daemon_armies}[[/col]] on our capital."),
    "conscripts": ("Recruit the Survivors", "Recruit the survivors: [[col:green]]2 random tier 1-2 units[[/col]] of our own kind join our army now."),
    "hire_sellswords": ("Hire Sellswords", PAY + "hire sellswords: [[col:green]]a random tier {tiers} unit[[/col]] of our own kind joins our army now."),
    "free_the_prisoner": ("Free the Prisoner", "Free the prisoner: [[col:green]]a rank {hero_rank} hero[[/col]] joins our army."),
    "tame_the_beast": ("Tame the Beast", "Tame the beast: [[col:green]]a random tier {tiers} monster[[/col]] of our own kind joins our army now."),
    "regiment_of_renown": ("Hire a Regiment of Renown", PAY + "hire a [[col:green]]Regiment of Renown[[/col]] of our own kind: it joins our army now."),
    "salvage_a_war_machine": ("Salvage a War Machine", PAY + "salvage a war machine: [[col:green]]a random tier {tiers} war machine[[/col]] of our own kind joins our army now."),
    "buy_from_the_trader": ("Buy from the Trader", PAY + "buy from the trader: [[col:green]]a random rare item[[/col]]."),
    "recruitment_cache": ("Pay the Smugglers", PAY + "pay the smugglers: [[col:green]]-{e0}% recruitment cost[[/col]] for 5 turns."),
    "tower_dividends": ("Invest in the Caravan", PAY + "invest in the caravan: [[col:green]]+{per_turn} gold[[/col]] to our treasury each turn for 10 turns."),
    "buy_supplies": ("Buy Supplies", PAY + "buy supplies: our army [[col:green]]ignores attrition[[/col]] for {turns} turns."),
    "research_scrolls": ("Read the Scrolls", "Read the scrolls: [[col:green]]+25% research rate[[/col]] for 5 turns."),
    "ancient_tactics": ("Study the Ancient Tactics", "Study the ancient tactics: " + stat("+5", *CHARGE) + " and " + stat("+5%", *SPEED) + " for 5 turns."),

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
    "poison_the_stores": ("Poison the Stores", PAY + "poison their stores: enemy units start at [[col:green]]{strength}% strength[[/col]]."),
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
    "war_rites": ("War Rites", PAY + "hold war rites: [[col:green]]+{e0}[[/col]] [[img:ui/skins/default/icon_stat_attack.png]][[/img]] melee attack, "
                  "[[img:ui/skins/default/icon_stat_defence.png]][[/img]] melee defence and [[img:ui/skins/default/icon_stat_morale.png]][[/img]] leadership in this battle."),
    "whetstones_and_oil": ("Whetstones and Oil", PAY + "hone every blade: [[col:green]]+{e0}%[[/col]] [[img:ui/skins/default/icon_stat_damage.png]][[/img]] weapon strength and "
                           "[[col:green]]+{e1}[[/col]] [[img:ui/skins/default/modifier_icon_armour_piercing.png]][[/img]] armour-piercing damage in this battle."),
    "warding_sigils": ("Warding Sigils", PAY + "paint warding sigils: [[col:green]]+{e0}% ward save[[/col]] in this battle."),
    "fire_kissed_blades": ("Fire-Kissed Blades", PAY + "pass our blades through the braziers: [[col:green]]flaming attacks[[/col]] for every unit in this battle."),
    "iron_resolve": ("Iron Resolve", PAY + "steel our resolve: [[col:green]]+{e0}[[/col]] [[img:ui/skins/default/icon_stat_morale.png]][[/img]] leadership and "
                     "[[col:green]]immunity to fear and terror[[/col]] in this battle."),
    "drill_sergeant": ("Hard Drills", PAY + "drive the army through hard drills: [[col:green]]+{e0}%[[/col]] [[img:ui/skins/default/icon_stat_speed.png]][[/img]] speed and "
                       "[[col:green]]+{e1}[[/col]] [[img:ui/skins/default/icon_stat_charge_bonus.png]][[/img]] charge bonus in this battle."),
    "call_the_winds": ("Call the Winds", PAY + "call the winds: [[col:green]]+{e0} Winds of Magic[[/col]] reserve in this battle."),
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
    "chase_the_routers": ("Chase the Routers", "Chase down the routers: a 50/50 chance of [[col:green]]a random rare item[[/col]] or our lord [[col:red]]wounded for 2 turns[[/col]]."),
    "dark_offering": ("Make a Dark Offering", "Make a dark offering: sacrifice our [[col:red]]weakest unit[[/col]], and our lord gains [[col:green]]1 rank[[/col]] and our army [[col:green]]+5% ward save[[/col]] for 5 turns."),
    "walk_away": ("Walk Away", "Leave this place be."),
    "fighting_spirits": ("Fighting Spirits", "Order a round of fighting spirits: " + stat("+{e0}", *ATTACK) + " and " + stat("+{e1}", *DEFENCE) + " for 5 turns."),
    "shieldbrew": ("Shieldbrew", "Order a round of shieldbrew: " + stat("+{e0}", *DEFENCE) + " and " + stat("+{e1}", *ARMOUR) + " for 5 turns."),
    "firewater": ("Firewater", "Order a round of firewater: " + stat("+{e0}%", *SPEED) + " and " + stat("+{e1}", *CHARGE) + " for 5 turns."),
    "marksmans_draught": ("Marksman's Draught", "Order a round of marksman's draught: " + stat("+{e0}%", *MISSILE) + " and " + stat("{e1}%", *RELOAD)
                          + " for 5 turns."),
    "mystery_brew": ("Mystery Brew", "Try the keeper's mystery brew: a 50/50 chance of " + stat("+{won_e0}", *ATTACK) + " and " + stat("+{won_e1}", *LEADERSHIP)
                     + " for 5 turns, or a hangover of " + stat("-{lost_e0}", *LEADERSHIP, colour="red") + " and " + stat("-{lost_e1}%", *SPEED, colour="red")
                     + " for {lost_turns} turns."),
    "feast_for_the_army": ("Feast for the Army", "Lay on a feast for the army: every unit regains [[col:green]]{heal}% of its missing strength[[/col]], and our "
                           "army [[col:green]]ignores attrition[[/col]] next turn."),
    "dice_with_strangers": ("Dice with Strangers", "Roll dice with strangers: a 50/50 chance our stake comes back [[col:green]]doubled[[/col]] or is "
                            "[[col:red]]lost[[/col]]."),
    "arm_wrestle_the_champion": ("Arm-Wrestle the Champion", "Arm-wrestle the house champion: a 50/50 chance our lord gains [[col:green]]+{won_xp} "
                                 "experience[[/col]] or is [[col:red]]hurt, losing half their remaining health[[/col]]."),
    "buy_rumours": ("Buy Rumours", "Buy the rumours of the road: the {count} nearest regions not our own are [[col:green]]revealed for {reveal_turns} "
                    "turns[[/col]], and the keeper names the enemy armies nearby."),
    "tavern_back": ("Back", "Go back to the common room."),
}

# Offer key -> its line's vanilla effect-bundle icon, reusing the icons Steve picked for the matching tower offers.
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
    "dark_offering": "bloodreaper.png",
    "bribe_the_guards": "subterfuge.png", "thin_the_ranks": "attrition.png", "poison_the_stores": "phase_posion.png",
    "kill_the_captain": "dlc10_assassination_targets.png", "lower_tiers_only": "peasant.png", "break_their_spirit": "discouraged.png",
    "strip_monsters": "rampage_harsh.png", "strip_cavalry": "charge.png", "strip_missile": "ammo.png", "strip_artillery": "artillery.png",
    "turn_a_traitor": "khainite_assassin.png", "war_rites": "effect_rite.png", "whetstones_and_oil": "weapon_damage.png",
    "warding_sigils": "resistance_ward_save.png", "fire_kissed_blades": "modifier_icon_flaming.png", "iron_resolve": "attribute_immune_to_psychology.png",
    "call_the_winds": "wh3_dlc24_wind_blast.png", "quartermasters_cache": "ammo.png", "night_raid": "dlc10_death_night.png",
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
    "against_the_odds": "vigour.png", "rout_the_riders": "mount.png", "bloodbath_wager": "khorne_skulls.png", "duelists_challenge": "rampage_harsh.png", "spare_the_captain": "noble.png", "flawless_victory": "champions_rift.png",
}

# Line on a mission already taken on the open battle dilemma: (icon, text).
TAKEN = ("icon_blank.png", "[[col:red]]Already taken.[[/col]]")

# Mission key -> (what it asked, said when met, said when failed). Each becomes a result after a won battle.
MISSION_MESSAGES = {
    "headhunt": ("Headhunt",
        "The enemy lord fell in time, just as we vowed. Their finest possession, a rare item, now belongs to us.",
        "The enemy lord lived too long, and our vow goes unfulfilled."),
    "blood_tally": ("Blood Tally",
        "The enemy's soldiers fell in their hundreds, and the tally is met. The promised gold is counted into our treasury.",
        "Too few of the enemy fell, and the tally comes up short."),
    "hold_the_line": ("Hold the Line",
        "Our line bent but never broke, and few of our units were lost. The reward for holding firm goes straight to our treasury.",
        "Our line held in the end, but too many of our units were lost along the way."),
    "swift_victory": ("Swift Victory",
        "The battle was over almost before it began. Word of the swift victory spreads, and an extra item comes our way.",
        "The battle dragged on too long for the victory to be called swift."),
    "guard_the_standard": ("Guard the Standard",
        "The marked unit stood firm through the worst of the fighting. They return as hardened veterans, 3 ranks the wiser.",
        "The marked unit was lost in the fighting, and their sacrifice earns no reward."),
    "break_them": ("Break Them",
        "Unit after unit of theirs broke and fled before us. Every one that ran adds to the purse we were promised.",
        "Too few of their units broke, and they fought on to the bitter end."),
    "trophy_hunt": ("Trophy Hunt",
        "Their finest unit fell to our blades. Its survivors are pressed into our service, and a fresh unit of their kind now marches with our army.",
        "Their finest unit survived the battle, and the trophy slips through our fingers."),
    "silence_the_guns": ("Silence the Guns",
        "Their guns fell silent before they could do much harm. Picking through the wrecked carriages, we find a rare item.",
        "Their guns kept firing for too long, and the mission has failed."),
    "bloodbath_wager": ("Bloodbath Wager",
        "The field ran red, and the wager is won. The gold comes back to us many times over.",
        "Too few of the enemy fell, and the gold we wagered is lost."),
    "duelists_challenge": ("Duellist's Challenge",
        "Our lord met theirs blade to blade and struck them down. A unique item is pried from the fallen lord's grip.",
        "Our lord did not slay theirs, and the challenge goes unanswered."),
    "spare_the_captain": ("Spare the Captain",
        "Their lord was taken alive, just as we planned. The ransom has been paid, and the gold is ours.",
        "Their lord fell in the fighting, so there is no one left to ransom."),
    "lords_glory": ("Lord's Glory",
        "Our lord carved through the enemy ranks, and the tally of the slain is sung around every fire. A rare item is taken from the field.",
        "Our lord fought well, but not well enough for the songs."),
    "monster_slayer": ("Monster Slayer",
        "Every beast they brought lies dead on the field. The bounty on such creatures is paid to us in full.",
        "Some of their beasts still live, and the hunt is unfinished."),
    "steadfast": ("Steadfast",
        "Not one of our units broke, however hard the enemy pressed. The promised gold reaches our treasury before the dead are buried.",
        "One of our units broke and ran, and the vow broke with it."),
    "decapitate": ("Decapitate",
        "Their lord and every one of their heroes lie dead. Searching the bodies, we turn up a unique item.",
        "Some of their leaders escaped the slaughter."),
    "against_the_odds": ("Against the Odds",
        "Outnumbered, we fought and won all the same. The promised gold is paid out, and the soldiers who earned it toast the victory.",
        "We did not face the odds we swore to beat."),
    "rout_the_riders": ("Rout the Riders",
        "Their riders scattered before us in time. Among the abandoned saddles we find a rare item.",
        "Their riders held their nerve for too long."),
    "untouchable": ("Untouchable",
        "Our lord came through the thick of the fighting barely scratched, and the army will not stop talking about it. The day's fighting has taught "
        "our lord a great deal.",
        "Our lord took too many wounds for the vow to hold."),
    "flawless_victory": ("Flawless Victory",
        "Not a single unit of ours was lost. Songs of the flawless victory spread far, and a unique item is ours.",
        "One of our units fell before the end, and there will be no songs of a flawless victory."),
}

# Battle objectives this script owns, for the missions added after the tower's hand-written ones: name -> (panel text, banner).
MISSION_OBJECTIVES = {
    "spare_the_captain": ("Spare the Captain: keep the enemy lord alive", "Spare the Captain: win with the enemy lord still alive."),
    "flawless_victory": ("Flawless Victory: our units lost", "Flawless Victory: win without losing a single unit."),
    "lords_glory": ("Lord's Glory: enemy soldiers our lord has slain", "Lord's Glory: our lord must slay enough of the enemy."),
    "monster_slayer": ("Monster Slayer: enemy monsters left", "Monster Slayer: destroy every enemy monster."),
    "steadfast": ("Steadfast: keep every unit of ours from routing", "Steadfast: no unit of ours may rout."),
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
}

# Notice -> its offer, for a notice not named after its offer. The notice shows that offer's numbers and line icon.
NOTICE_OFFERS = {"night_raid_won": "night_raid", "night_raid_lost": "night_raid", "sacred_ground_now": "sacred_ground"}

# Second line under Avoid on every battle dilemma, since avoiding fires the category's avoidance incident.
AVOID_CONSEQUENCES = ("avoid_consequences", "random_recipe.png", "[[col:yellow]]This may have unforeseen consequences.[[/col]]")



# Message suffix after `spot_` -> (title, subtitle, description). Realm messages have no subtitle: their {place} is the target region's name,
# or the target faction's when it holds no region. Each is also a result incident, which shows only the title and description, with the
# place highlighted.
MESSAGES = {
    "cast_the_lots_won": ("Cast the Lots", "Fortune Smiles",
        "The lots tumble from the cup and fall in our favour. The stranger who offered the game scowls, but pays up all the same, and a rare treasure "
        "changes hands."),
    "cast_the_lots_lost": ("Cast the Lots", "Fortune Frowns",
        "The lots fall against us, as they so often do for newcomers. The stranger sweeps up our stake with a crooked grin and is gone before anyone "
        "thinks to argue."),
    "drink_from_the_spring_won": ("Drink from the Spring", "Healing Waters",
        "The water runs cold and clear from the rock. Wounds close and tired limbs grow strong again as the whole army drinks its fill."),
    "drink_from_the_spring_lost": ("Drink from the Spring", "Foul Waters",
        "The water tastes of rot and old iron. Within hours sickness spreads through the camp, and the army will march weaker for some time."),
    "open_the_sealed_door_won": ("Open the Sealed Door", "A Treasure Within",
        "The seal breaks and the door grinds open on a chamber untouched for centuries. At its heart, on a bare stone plinth, lies a treasure of legend."),
    "open_the_sealed_door_lost": ("Open the Sealed Door", "A Trap Sprung",
        "The seal breaks, and so does the trap behind it. Our lord is caught in the blast and carried from the chamber, badly wounded."),
    "double_or_nothing_won": ("Double or Nothing", "The Stake Doubles",
        "The bet is called and the throw comes up in our favour. Our stake returns to the treasury doubled, and the house is not pleased about it."),
    "double_or_nothing_lost": ("Double or Nothing", "The Stake Is Lost",
        "The bet is called and the throw turns against us. Our stake is gone, and the house thanks us warmly for our custom."),
    "wake_the_guardian_won": ("Wake the Guardian", "It Sleeps On",
        "The great beast snorts and shifts its bulk, then sinks back into its slumber. We creep past it and make off with a rare treasure from its hoard."),
    "wake_the_guardian_lost": ("Wake the Guardian", "It Wakes!",
        "The ground shakes as the guardian of this place rises from its slumber. It sees intruders in its lair and charges, and our army must stand and "
        "fight!"),
    "touch_the_relic_blessed": ("Touch the Relic", "A Blessing",
        "Warmth spreads from the relic into the hands that hold it. A blessing settles over the army, and the soldiers march a little taller for it."),
    "touch_the_relic_cursed": ("Touch the Relic", "A Curse",
        "The relic is cold as a grave, and a creeping dread spreads through the ranks. A curse settles over the army, though it should not last long."),
    "gamble_with_the_hermit_won": ("Gamble with the Hermit", "A Lucky Throw",
        "The hermit squints at the dice, then laughs and shuffles off into the hut. They return with a unique treasure and press it into our hands."),
    "gamble_with_the_hermit_lost": ("Gamble with the Hermit", "The Hermit Wins",
        "The hermit wins throw after throw, cackling all the while. When the game is done our gold is in the hermit's pouch, and the hermit is gone."),
    "endow_the_province": ("Endow the Province", "",
        "Our gold pays for new roads and storehouses across {place}. The region grows stronger and richer, and its people know who paid for it."),
    "garrison_drill": ("Garrison Drill", "",
        "Fresh supplies reach the garrison of {place}, and its officers drill the defenders from dawn to dusk. Its walls are manned by harder soldiers now."),
    "raise_the_settlement": ("Raise the Settlement", "",
        "Builders swarm over {place}, raising new halls and stronger walls. In a matter of days its heart stands a level higher than before."),
    "quell_the_unrest": ("Quell the Unrest", "",
        "Our soldiers walk the streets of {place}, and the loudest troublemakers fall quiet. Order returns, for now."),
    "bountiful_harvest": ("Bountiful Harvest", "",
        "The fields around {place} groan under a bountiful harvest. Carts queue at the granaries for days, and the markets are busier than anyone "
        "can remember."),
    "stir_their_rebels": ("Stir Their Rebels", "",
        "Our agents hand out grievances and weapons among the malcontents of {place}. Unrest is rising across the enemy's lands."),
    "poison_their_wells": ("Poison Their Wells", "",
        "Under cover of night, our agents foul the wells of {place}. Sickness spreads through its people, and any army camped there will suffer for it."),
    "sap_their_garrison": ("Sap Their Garrison", "",
        "Our saboteurs slip into {place}, spoiling the grain stores and spreading sickness through the barracks. Its garrison is weakened and shaken."),
    "spread_the_plague": ("Spread the Plague", "",
        "We drive the sick and the dying toward the enemy's lands around {place}. The plague spreads, though our own army does not escape it entirely."),
    "mystery_brew_won": ("Mystery Brew", "A Fine Brew",
        "The brew goes down like liquid fire and settles in the belly as courage. By morning the whole army is spoiling for a fight."),
    "mystery_brew_lost": ("Mystery Brew", "A Foul Brew",
        "Whatever was in that barrel, it was not meant for drinking. The army wakes with sore heads and slow feet, and the keeper will not say what it was."),
    "dice_with_strangers_won": ("Dice with Strangers", "The Dice Are Kind",
        "The dice land in our favour, again and again. The strangers pay up with sour faces, and our stake comes back doubled."),
    "dice_with_strangers_lost": ("Dice with Strangers", "Loaded Dice",
        "The dice turn against us, and the strangers sweep our stake from the table. Only later does anyone wonder whose dice they were."),
    "arm_wrestle_the_champion_won": ("Arm-Wrestle the Champion", "Champion Beaten",
        "The table groans and the crowd roars as the champion's arm slams down. Our lord walks out a legend of the common room."),
    "arm_wrestle_the_champion_lost": ("Arm-Wrestle the Champion", "Arm Broken",
        "The champion grins, leans in, and something in our lord's arm gives way with a crack. Our lord leaves the table hurt, and the crowd cheers the champion."),
    "buy_rumours": ("Buy Rumours", "",
        "The keeper leans close and talks of the roads around {place} and beyond, and of the enemy camped nearby: {detail}. We will see those lands "
        "for some time yet."),
    "send_gifts": ("Send Gifts", "",
        "Our gifts are well received at {place}. Their rulers speak of us more warmly now, and our envoys are welcome at their table."),
    "spy_on_their_capital": ("Spy on Their Capital", "",
        "Our spies slip into {place} to map its walls and gates and count its garrison: {detail}. We will see its streets for some time yet."),
    "curse_a_distant_king": ("Curse a Distant King", "",
        "A curse falls on the treasury of the court at {place}. Their wealth dwindles, and they will never know why."),
    "share_the_find": ("Share the Find", "",
        "We share what we found with our neighbours, starting with {place}. Their scholars are grateful, and think better of us for it."),
    "point_them_at_each_other": ("Point Them at Each Other", "",
        "Rumours spread from {place}, carefully planted by our agents. Two rivals now eye each other with suspicion."),
    "sell_their_secrets": ("Sell Their Secrets", "",
        "The secrets fetch a fine price in {place}. But word travels, and our enemies grow closer to one another."),
    "ransom_the_captain": ("Ransom the Captain", "",
        "Their captain is ransomed back to {place}, and the price is paid in full. Their kin will not forget the humiliation."),
    "chase_the_routers_won": ("Chase the Routers", "A Rich Catch",
        "Our fastest troops run the fleeing enemy down before they reach safety. Among the gear they threw away to run faster is a rare item."),
    "chase_the_routers_lost": ("Chase the Routers", "Ambushed",
        "The fleeing enemy were bait. They turn on our pursuers in a narrow pass, and our lord takes a wound that will lay them low for a time."),
}

# Message suffix -> the words its event feed message uses for {place}, which only the result incident can show by name.
FALLBACK_PLACES = {
    "endow_the_province": "that region", "garrison_drill": "that settlement", "raise_the_settlement": "the settlement",
    "quell_the_unrest": "the settlement", "bountiful_harvest": "that region", "stir_their_rebels": "that region", "poison_their_wells": "that region",
    "sap_their_garrison": "the enemy settlement", "spread_the_plague": "that region", "buy_rumours": "that region", "send_gifts": "their court",
    "spy_on_their_capital": "the enemy capital", "curse_a_distant_king": "their capital", "share_the_find": "the nearest",
    "point_them_at_each_other": "that region", "sell_their_secrets": "that region", "ransom_the_captain": "their own people",
}

# Shown when an offer's price is a wound, by its turns.
WOUND_PAID = ("The Price Is Paid", "Our Lord Is Wounded", "The price of what we took comes due at once. Our lord is struck down by a wound that will take {turns} turns to heal.")

# Result -> (colour, text) of the effect line under a result's incident, for results whose payload shows no gold, item or unit card.
# Every mission failed gets its own line, and every wound paid one built from WOUND_PAID_LINE.
RESULT_LINES = {
    "cast_the_lots_lost": ("red", "Our stake is lost."),
    "drink_from_the_spring_won": ("green", "Every unit is healed to full."),
    "drink_from_the_spring_lost": ("red", "Attrition on our army for {lost_turns} turns."),
    "open_the_sealed_door_lost": ("red", "Our lord is wounded for 3 turns."),
    "double_or_nothing_lost": ("red", "Our stake of {cost} gold is lost."),
    "wake_the_guardian_lost": ("red", "The guardian attacks our army!"),
    "touch_the_relic_blessed": ("green", "A blessing on our army for 5 turns."),
    "touch_the_relic_cursed": ("red", "A curse on our army for 3 turns."),
    "gamble_with_the_hermit_lost": ("red", "The hermit keeps our {cost} gold."),
    "chase_the_routers_lost": ("red", "Our lord is wounded for 2 turns."),
    "mystery_brew_won": ("green", "A fine brew on our army for 5 turns."),
    "mystery_brew_lost": ("red", "A hangover on our army for {lost_turns} turns."),
    "dice_with_strangers_lost": ("red", "Our stake is lost."),
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
WOUND_PAID_LINE = ("red", "Our lord is wounded for {turns} turns.")

# Bundle key suffix after `land_enc_effect_spot_` -> (target, icon, title, description, [(effect, scope, value)]). A value written as
# (easy, medium, hard) makes a tiered bundle, one per difficulty named with it, e.g. land_enc_effect_spot_stoneskin_medium.
BUNDLES = {
    "reinforcement_time_25": ("force", "military.png", "Swift Reinforcements", "Scouts have marked the fastest paths for our relief columns. Reinforcements reach this army sooner.",
                              [("wh3_main_effect_own_reinforcement_time_percentage_mod", "force_to_force_own", -25)]),
    "reinforcement_time_50": ("force", "military.png", "Swift Reinforcements", "Scouts have marked the fastest paths for our relief columns. Reinforcements reach this army sooner.",
                              [("wh3_main_effect_own_reinforcement_time_percentage_mod", "force_to_force_own", -50)]),
    "reinforcement_time_75": ("force", "military.png", "Swift Reinforcements", "Scouts have marked the fastest paths for our relief columns. Reinforcements reach this army sooner.",
                              [("wh3_main_effect_own_reinforcement_time_percentage_mod", "force_to_force_own", -75)]),
    "camping": ("force", "icon_effects_fortify.png", "Searching Every Corner", "Our army searches every corner and cannot march until our next turn.",
                [("wh_main_effect_force_all_campaign_movement_range", "force_to_force_own", -100)]),
    "strip_the_valuables": ("force", "icon_effects_fortify.png", "Weighed Down", "Every wagon and pack is stuffed with stripped valuables. The army moves slowly under the weight.",
                            [("wh_main_effect_force_stat_leadership", "force_to_force_own", -15), ("wh_main_effect_force_stat_speed", "force_to_force_own", -10)]),
    "bless_the_banners": ("force", "icon_effects_fortify.png", "Blessed Banners", "Our banners were held over the smoke of an old shrine's fire. The warriors stand firmer beneath them.",
                          [("wh_main_effect_force_stat_melee_attack", "force_to_force_own", (5, 10, 15)),
                           ("wh_main_effect_force_stat_leadership", "force_to_force_own", (5, 10, 15))]),
    "stoneskin": ("force", "icon_effects_fortify.png", "Stoneskin", "A ward of living stone hardens our army's hide.",
                   [("wh_main_effect_force_stat_physical_resistance", "force_to_force_own", (5, 10, 15))]),
    "ancient_tactics": ("force", "icon_effects_fortify.png", "Ancient Tactics", "Faded battle orders found in the ruins have our captains drilling the ranks in forgotten formations.",
                        [("wh2_dlc14_effect_force_charge_bonus_add", "force_to_force_own", 5), ("wh_main_effect_force_stat_speed", "force_to_force_own", 5)]),
    "touch_the_relic_frailty": ("force", "icon_effects_fortify.png", "Relic's Frailty", "Since our lord touched the relic, shields feel heavy and parries come a beat too late.",
                                [("wh_main_effect_force_stat_melee_defence", "force_to_force_own", -10), ("wh_main_effect_force_stat_armour", "force_to_force_own", -10)]),
    "leave_an_offering": ("force", "icon_effects_fortify.png", "Offering Made", "We left gifts at a wayside shrine before marching on. Blows that should land seem to glance away.",
                          [("wh_main_effect_force_stat_ward_save", "force_to_force_own", (5, 10, 15))]),
    "enchanted_steel": ("force", "icon_effects_fortify.png", "Enchanted Steel", "Strange marks found at the site were etched into every blade. Our weapons now bite where plain steel would not.",
                        [("wh_main_effect_force_stat_enable_magic_attacks", "force_to_force_own", 1)]),
    "bloodstained_blades": ("force", "icon_effects_fortify.png", "Bloodstained Blades",
                            "Our warriors took up blades found still stained with old blood. They cut deep, and no one wants to clean them.",
                            [("wh_main_effect_force_stat_melee_attack", "force_to_force_own", 20), ("wh_main_effect_force_stat_melee_defence", "force_to_force_own", -20)]),
    "buy_supplies": ("force", "icon_effects_fortify.png", "Well Supplied", "A full baggage train rides with the army. No one goes hungry on the march.",
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
    "press_on": ("force", "icon_effects_fortify.png", "Pressing On", "The enemy broke and ran. Our army follows hard on their heels before they can regroup.",
                 [("wh_main_effect_force_all_campaign_movement_range", "force_to_force_own", 50)]),
    "victory_feast": ("force", "icon_effects_fortify.png", "Victory Feast", "The army feasted long into the night on what the beaten enemy left behind. Spirits are high on the march.",
                      [("wh_main_effect_force_stat_leadership", "force_to_force_own", (5, 10, 15)),
                       ("wh_main_effect_force_stat_melee_attack", "force_to_force_own", (5, 10, 15))]),
    "dark_offering": ("force", "icon_effects_fortify.png", "Dark Offering", "Blood was spilled on an old altar before we marched. Something unseen now turns blows from our warriors.",
                      [("wh_main_effect_force_stat_ward_save", "force_to_force_own", 5)]),
    "tavern_fighting_spirits": ("force", "edict_sla_festival_of_drinking_and_delights.png", "Fighting Spirits",
                                "The tavern's fighting spirits burned all the way down. Our warriors marched out spoiling for a brawl.",
                                [("wh_main_effect_force_stat_melee_attack", "force_to_force_own", (5, 10, 15)),
                                 ("wh_main_effect_force_stat_melee_defence", "force_to_force_own", (5, 10, 15))]),
    "tavern_shieldbrew": ("force", "edict_sla_festival_of_drinking_and_delights.png", "Shieldbrew",
                          "The shieldbrew sat in every belly like a stone. Our warriors marched out steady on their feet and hard to knock down.",
                          [("wh_main_effect_force_stat_melee_defence", "force_to_force_own", (5, 10, 15)),
                           ("wh_main_effect_force_stat_armour", "force_to_force_own", (10, 15, 20))]),
    "tavern_firewater": ("force", "edict_sla_festival_of_drinking_and_delights.png", "Firewater",
                         "The firewater left every throat burning and every foot itching to run. Our warriors marched out eager to charge.",
                         [("wh_main_effect_force_stat_speed", "force_to_force_own", (5, 10, 15)),
                          ("wh2_dlc14_effect_force_charge_bonus_add", "force_to_force_own", (6, 10, 14))]),
    "tavern_marksmans_draught": ("force", "edict_sla_festival_of_drinking_and_delights.png", "Marksman's Draught",
                                 "A round of marksman's draught steadied the hands of our shooters. They marched out keen to test their aim.",
                                 [("wh_main_effect_force_stat_missile_damage", "force_to_force_own", (8, 12, 16)),
                                  ("wh_main_effect_force_stat_reload_time_reduction", "force_to_force_own", (10, 15, 20))]),
    "tavern_mystery_brew": ("force", "edict_sla_festival_of_drinking_and_delights.png", "A Fine Brew", "The mystery brew turned out smooth and strong. Our warriors marched out in high spirits.",
                            [("wh_main_effect_force_stat_melee_attack", "force_to_force_own", (12, 16, 20)),
                             ("wh_main_effect_force_stat_leadership", "force_to_force_own", (12, 16, 20))]),
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
local battle_dilemmas = {}
for key in pairs(require("script/land_encounters/configs/battle_categories").dilemma_keys) do battle_dilemmas[#battle_dilemmas + 1] = key end
local battle_modifiers = require("script/land_encounters/configs/battle_modifiers")
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
io.write(encode({ sites = data.sites, spoils = data.spoils, tavern = data.tavern, offers = data.all_at("easy"), at = at, dividends_bundle_prefix = data.dividends_bundle_prefix,
    tower_offers = tower.offers, tower_at = tower_at, tower_varies = tower_varies, notice_varies = notice_varies,
    tower_unaffordable_suffix = tower.unaffordable_suffix, tower_line_prefix = tower.line_prefix,
    choice_key_prefix = data.choice_key_prefix, walk_away_choice_key = data.walk_away_choice_key, signature_choice_key = data.signature_choice_key,
    dilemma_prefix = data.dilemma_prefix, line_prefix = data.line_prefix, message_prefix = data.message_prefix, camp_bundle = data.camp_bundle,
    result_incident_prefix = data.result_incident_prefix, result_place_context = data.result_place_context, battle_pools = data.battle_pools,
    avoid_choice_key = data.avoid_choice_key,
    unaffordable_line = data.unaffordable_line, taken_line = data.taken_line, missions_context = data.missions_context,
    mission_set_loc_prefix = data.mission_set_loc_prefix, battle_dilemmas = battle_dilemmas, result_detail_context = data.result_detail_context,
    battle_modifiers = battle_modifiers }))
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
    `steps.tiered` names them), the tower's tiered battle bundles, and one dividends bundle per gold amount either feature pays each turn.

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
                stepped = [(effect, scope, value[i] if isinstance(value, tuple) else value) for effect, scope, value in effects]
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
        effects of the bundle it gives, signs dropped.
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
    for field in BUNDLE_FIELDS:
        if field not in offer:
            continue
        bundle = offer[field] if isinstance(offer[field], str) else offer[field][0]
        if not isinstance(offer[field], str):
            values["turns"] = str(offer[field][1])
        for i, (_, _, value) in enumerate(bundles.get(bundle, ("", "", "", "", []))[4]):
            values[f"e{i}"] = str(abs(value))
    if "dividends" in offer:
        values["per_turn"] = str(offer["dividends"]["per_turn"])
    if "gold_per_enemy_unit" in offer:
        values["per_unit"] = str(offer["gold_per_enemy_unit"])
    tiers = offer.get("tiers") or offer.get("recruit", {}).get("tiers") or offer.get("traitor", {}).get("tiers")
    if tiers:
        values["tiers"] = tiers_text(tiers)
    if "relations" in offer:
        values["relations"] = str(abs(offer["relations"]) * 10)
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


def wound_turns(config: Dict) -> List[int]:
    """Lists every wound length an offer or gamble outcome can give, at any difficulty.

    Args:
        config (Dict): The loaded config.

    Returns:
        List[int]: The distinct turns, sorted.
    """
    return sorted({fields["wound"] for offers in config["at"].values() for offer in offers.values() for fields in [offer] + offer.get("gamble", [])
                   if "wound" in fields})


def all_sites(config: Dict) -> List[Dict]:
    """Lists every site with a dilemma: the treasure sites, the spoils pick and the Tavern bar.

    Args:
        config (Dict): The loaded config.

    Returns:
        List[Dict]: The site records.
    """
    return config["sites"] + [config["spoils"], config["tavern"]]


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

    def line(component: str, icon: str, text: str) -> None:
        add(table("campaign_payload_ui_details_tables"), component, "ui/campaign ui/effect_bundles/" + icon, "default", 0)
        add(LOC_PREFIX + "campaign_payload_ui_details.loc.tsv", "campaign_payload_ui_details_description_" + component, add_stat_icons(text), "false")

    def label(dilemma: str, choice: str, text: str) -> None:
        add(table("cdir_events_dilemma_choice_details_tables"), choice, dilemma, "", "")
        add(LOC_PREFIX + "cdir_events_dilemma_choice_details.loc.tsv", "cdir_events_dilemma_choice_details_localised_choice_label_" + dilemma + choice,
            text, "false")

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
        dilemma = config["dilemma_prefix"] + site["key"]
        title, description = SITES[site["key"]]
        add(table("dilemmas_tables"), dilemma, "false", "", "", site["ui_image"], "false", "Event", "UI_CAM_EVENT_Dilemma", "", "", "false")
        for option, value in [("GEN_TARGET_NONE", ""), ("VAR_CHANCE", "100"), ("VAR_FOLLOWUP_CHANCE", "100")]:
            add(table("cdir_events_dilemma_option_junctions_tables"), row_id, dilemma, option, value, "default")
            row_id += 1
        add(table("cdir_events_dilemma_payloads_tables"), row_id, "FIRST", dilemma, "TEXT_DISPLAY", "LOOKUP[dummy_do_nothing]", "default")
        row_id += 1
        add(LOC_PREFIX + "dilemmas.loc.tsv", "dilemmas_localised_title_" + dilemma, title_case(title), "false")
        leave = site.get("leave_line")
        footer = LEAVE_FOOTER.format(OFFERS[leave][1][0].lower() + OFFERS[leave][1][1:]) if leave else SITE_FOOTER
        add(LOC_PREFIX + "dilemmas.loc.tsv", "dilemmas_localised_description_" + dilemma, description + footer, "false")
        labels = site_keys + ([(config["signature_choice_key"], site["signature"])] if site.get("signature") else [])
        for choice, key in labels:
            # A site with its own leave line labels Walk away after it.
            shown = site.get("leave_line", key) if key == "walk_away" else key
            label(dilemma, choice, title_case(OFFERS[shown][0]))
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
                objective(bundle_name, tower_icon(name), f"[[col:{notice[0]}]]{shown}[[/col]]", shown)
    for key, (colour, text) in TOWER_NOTICE_TEXT.items():
        for difficulty, name in notice_names(key, config):
            shown = text.format_map(line_values(config["tower_at"][difficulty][key], bundles))
            objective(name, tower_icon(key), f"[[col:{colour}]]{shown}[[/col]]", shown)
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
                                      "The battle was fought without our watchful eyes on it, so none of our missions could be judged. Any gold we wagered is returned to our treasury.")
    for turns in wound_turns(config):
        messages["wound_paid_" + str(turns)] = (WOUND_PAID[0], WOUND_PAID[1], WOUND_PAID[2].format(turns=turns))

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
    for turns in wound_turns(config):
        lines["wound_paid_" + str(turns)] = (WOUND_PAID_LINE[0], WOUND_PAID_LINE[1].format(turns=turns))
    for suffix, (title, subtitle, description) in messages.items():
        name = config["message_prefix"] + suffix
        for field, text in [("title", title_case(title)), ("subtitle", title_case(subtitle or title)), ("description", fallback_text(description, FALLBACK_PLACES.get(suffix, "")))]:
            add(LOC_PREFIX + "event_feed_strings.loc.tsv", f"event_feed_strings_text_{field}_event_land_enc_{name}", text, "false")
        incident = config["result_incident_prefix"] + suffix
        image = RESULT_IMAGES.get(suffix) or (MISSION_RESULT_IMAGE if suffix.startswith("mission") else RESULT_IMAGE)
        add(table("incidents_tables"), incident, "false", image, "false", "Event", "", "false", "", "0.0000", "false")
        for option, value in [("GEN_TARGET_NONE", ""), ("VAR_CHANCE", "100")]:
            add(table("cdir_events_incident_option_junctions_tables"), row_id, incident, option, value, "default")
            row_id += 1
        place = f'{{{{CcoCampaignEventIncident:ScriptObjectContext("{config["result_place_context"]}").StringValue}}}}'
        detail = f'{{{{CcoCampaignEventIncident:ScriptObjectContext("{config["result_detail_context"]}").StringValue}}}}'
        shown = description.replace("{place}", f"[[col:yellow]]{place}[[/col]]").replace("{detail}", f"[[col:yellow]]{detail}[[/col]]")
        add(LOC_PREFIX + "incidents.loc.tsv", "incidents_localised_title_" + incident, title_case(title), "false")
        add(LOC_PREFIX + "incidents.loc.tsv", "incidents_localised_description_" + incident, shown, "false")
        if suffix in lines:
            colour, text = lines[suffix]
            offer_key = result_key(suffix)
            offer_key = offer_key if offer_key in config["at"][DIFFICULTIES[0]] else ""
            for difficulty in DIFFICULTIES:
                shown = text.format_map(line_values(config["at"][difficulty][offer_key], bundles)) if offer_key else text
                line(config["line_prefix"] + "result_" + suffix + "_" + difficulty, result_icon(suffix), f"[[col:{colour}]]{shown}[[/col]]")
    return rows


def result_key(result: str) -> str:
    """Strips a result name down to the offer or mission it belongs to.

    Args:
        result (str): The result name, e.g. "cast_the_lots_lost", "mission_untouchable_met" or "bountiful_harvest".

    Returns:
        str: The offer or mission key, e.g. "cast_the_lots" or "untouchable". A result of no offer comes back as it is, e.g. "wound_paid_5".
    """
    return re.sub(r"^mission_|_(won|lost|blessed|cursed|met|failed)$", "", result)


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
    if result.startswith("wound_paid_"):
        return "chaos_gifts.png"
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
    difficulty = f"(?:_(?:{'|'.join(DIFFICULTIES)}))?"
    kinds = [(config["tower_line_prefix"], tower_line_keys(config), "(?:_unaffordable)?"), (TOWER_BUNDLE, list(TOWER_BUNDLES), ""),
             (NOTICE_PREFIX, tower_notices + bundle_notices + list(NOTICES) + list(MISSION_OBJECTIVES), "(?:_message)?")]
    return [re.compile(f"(?:^|_){prefix}(?:{'|'.join(names)}){difficulty}{tail}$") for prefix, names, tail in kinds]


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
    problems += [f"no text for leave line {s['leave_line']}" for s in all_sites(config) if s.get("leave_line") and s["leave_line"] not in OFFERS]
    modifier_keys = {m["key"] for m in config["battle_modifiers"]["list"]}
    generic = {m["key"] for m in config["battle_modifiers"]["list"] if "army" in m and "faction" not in m}
    problems += [f"no allied theme text for {key}" for key in sorted(generic ^ set(battle_modifiers.ALLY_THEMES))]
    problems += [f"no text for battle modifier {key}" for key in sorted(modifier_keys - set(battle_modifiers.MODIFIERS))]
    problems += [f"text for unknown battle modifier {key}" for key in sorted(set(battle_modifiers.MODIFIERS) - modifier_keys)]
    problems += [f"no text for site {s['key']}" for s in all_sites(config) if s["key"] not in SITES]
    problems += [f"no icon for {key}" for key in OFFERS if key not in ICONS]
    problems += [f"no notice for {o['key']}" for o in config["offers"]
                 if o["pool"] == "pre_battle" and "battle_bundle" not in o and "gamble" not in o and "trick" not in o and o["key"] not in NOTICES
                 and o["key"] not in config["tower_at"]["easy"]]
    problems += [f"no messages for mission {o['key']}" for o in config["offers"] if o["pool"] == "mission" and o["key"] not in MISSION_MESSAGES]
    problems += [f"no tower line for {key}" for key in tower_line_keys(config) if key not in TOWER_LINES or not tower_icon(key)]
    problems += [f"no tower notice for {key}" for key, varies in config["notice_varies"].items()
                 if varies and key not in TOWER_NOTICE_TEXT and key in config["tower_at"]["easy"]
                 and (config["tower_at"]["easy"][key].get("trick") or config["tower_at"]["easy"][key]["guide_section"] == "sabotage")]
    problems += [f"no result for line {key}" for key in RESULT_LINES if key not in MESSAGES and not key.startswith("mission")]
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
    hook_battle_descriptions(config, args.dry_run)


if __name__ == "__main__":
    main()
