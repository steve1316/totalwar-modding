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
from typing import Dict, List, Tuple

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
                 "string_land_enc_spot_", "land_enc_incident_spot_")

# Picture of a result's incident: missions show a victory, everything else a found treasure.
RESULT_IMAGE = "wh2_sea_encounters_1"
MISSION_RESULT_IMAGE = "land_victory"

# Loc file of the strings the script reads at runtime: the taken missions' lines.
STRINGS_LOC = LOC_PREFIX + "spot_strings.loc.tsv"

# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Text helpers


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
    "hidden_tomb": ("Hidden Tomb", "A forgotten tomb lies half-buried here. Its wards are old, but not all of them have failed."),
    "abandoned_camp": ("Abandoned Camp", "Cold fires and empty tents. Whoever camped here left in a hurry, and left their supplies behind."),
    "buried_relics": ("Buried Relics", "Bones of something enormous jut from the earth, with older treasures buried among them."),
    "hidden_temple": ("Hidden Temple", "A temple untouched by time stands in the wilds. Its priests are long gone, but its power is not."),
    "caravan_remnants": ("Caravan Remnants", "A half-sacked caravan lies by the road. The raiders missed more than they took."),
    "whispers_of_our_god": ("Whispers of Our God", "In a dream, our god speaks to our lord. Some gifts come with a price."),
    "the_explorer": ("The Explorer", "A band of explorers shares a fire with us, and the maps of what they found on the road."),
    "legendary_bard": ("Legendary Bard", "A famous bard, held captive by bandits, offers songs of our deeds in return for freedom."),
    "ruined_shrine": ("Ruined Shrine", "A burnt shrine still hums with old power. It may bless us, or it may curse us."),
    "smugglers_cache": ("Smugglers' Cache", "A smugglers' cache, and the smugglers are still nearby. They deal in goods, and in secrets."),
    "beast_lair": ("Beast Lair", "Something big lives here. The bones outside are fresh."),
    "old_battlefield": ("Old Battlefield", "Crows wheel over an old battlefield. Broken engines and lost banners lie in the mud."),
    "witchs_hut": ("Witch's Hut", "A witch's hut, thick with smoke. She trades in gambles, pacts and curses."),
    "collapsed_mine": ("Collapsed Mine", "A collapsed mine, half-flooded. The deeper tunnels are still rich, and still dangerous."),
    "merchants_wagon": ("Merchant's Wagon", "A travelling merchant, far from any market, is glad of customers."),
    "sunken_library": ("Sunken Library", "A sunken library, its shelves rotting. Some scrolls still hold the secrets of other realms."),
    "spoils_of_war": ("Spoils of War", "The field is ours. Before we march on, there is more to take from it."),
}

# Shown under every site's description: the rules, said once, then the choice. Loc files store a line break as an escaped `\\n`.
SITE_FOOTER = "\\\\n\\\\n[[col:yellow]]Choose one, or walk away.[[/col]]"

# Offer key -> (choice label, line). A line may use {cost}, {gold}, {won_gold}, {lost_gold} and {per_turn}, filled per difficulty.
OFFERS: Dict[str, Tuple[str, str]] = {
    "tomb_robbing": ("Rob the Tomb", "Rob the tomb: [[col:green]]+1500 gold[[/col]] to our treasury, a random item and experience for our lord."),
    "abandoned_camp": ("Rest at the Camp", "Rest at the camp: [[col:green]]+8% replenishment[[/col]] and [[col:green]]+8% movement range[[/col]] for 8 turns, and our lord gains experience each turn."),
    "buried_relics": ("Dig Up the Relics", "Dig up the relics: [[col:green]]2 random items[[/col]] and the [[col:green]]Talisman of Preservation[[/col]]."),
    "hidden_temple": ("Pray at the Temple", "Pray at the temple: [[col:green]]+8% unit health[[/col]] and [[col:green]]+4% ward save[[/col]] for 5 turns, and our lord gains experience each turn."),
    "caravan_remnants": ("Salvage the Caravan", "Salvage the caravan: [[col:green]]+5000 gold[[/col]] to our treasury, a random item and experience for our lord."),
    "whispers_of_the_gods": ("Heed the Whisper", "Heed the whisper: our army is [[col:green]]unbreakable[[/col]] and [[col:green]]never tires[[/col]] for 4 turns, and our lord gains experience each turn."),
    "the_explorer": ("Hear the Explorers Out", "Hear the explorers out: [[col:green]]+16% movement range[[/col]], [[col:green]]+16% ambush defence[[/col]] and [[col:green]]no attrition[[/col]] for 10 turns."),
    "legendary_bard": ("Free the Bard", "Free the bard: [[col:green]]+10% income[[/col]] and [[col:green]]-30% construction cost[[/col]] in our provinces for 10 turns."),

    "take_the_gold": ("Take the Gold", "Take the gold: [[col:green]]+{gold} gold[[/col]] to our treasury."),
    "strip_the_valuables": ("Strip the Valuables", "Strip everything of value: [[col:green]]+{gold} gold[[/col]] to our treasury, but our army is weighed down: "
                            + stat("-10", *LEADERSHIP, colour="red") + " for 5 turns."),
    "pry_open_the_reliquary": ("Pry Open the Reliquary", "Pry open the reliquary: [[col:green]]a random rare item[[/col]], but our lord is [[col:red]]wounded for 2 turns[[/col]] at the start of our next turn."),
    "search_every_corner": ("Search Every Corner", "Search every corner: [[col:green]]2 random items[[/col]], but our army [[col:red]]cannot move again this turn[[/col]]."),
    "the_hidden_vault": ("Open the Hidden Vault", PAY + "open the hidden vault: [[col:green]]1 unique item[[/col]]."),
    "roll_the_bones": ("Roll the Bones", "Roll the bones: a 50/50 chance of [[col:green]]a random rare item[[/col]] or [[col:red]]losing {lost_gold} gold[[/col]]."),
    "drink_from_the_spring": ("Drink from the Spring", "Drink from the spring: a 50/50 chance every unit is [[col:green]]healed to full[[/col]] or our army suffers [[col:red]]attrition for 3 turns[[/col]]."),
    "open_the_sealed_door": ("Open the Sealed Door", "Open the sealed door: a 50/50 chance of [[col:green]]1 unique item[[/col]] or our lord [[col:red]]wounded for 3 turns[[/col]] at the start of our next turn."),
    "stake_the_treasury": ("Stake the Treasury", "Stake [[col:yellow]]{cost} gold[[/col]] from our treasury: a 50/50 chance it comes back as [[col:green]]{won_gold} gold[[/col]] or is [[col:red]]lost[[/col]]."),
    "wake_the_guardian": ("Wake the Guardian", "Wake the guardian: a 60/40 chance of [[col:green]]a random rare item[[/col]] or [[col:red]]it attacks[[/col]] and a battle starts here."),
    "touch_the_relic": ("Touch the Relic", "Touch the relic: our army gets a random [[col:green]]blessing[[/col]] or [[col:red]]curse[[/col]] for 5 turns."),
    "gamble_with_the_hermit": ("Gamble with the Hermit", PAY + "gamble with the hermit: a 1 in 3 chance of [[col:green]]1 unique item[[/col]]."),
    "leave_an_offering": ("Leave an Offering", PAY + "leave an offering: [[col:green]]+10% ward save[[/col]] for our army for 5 turns."),
    "bless_the_banners": ("Bless the Banners", PAY + "bless our banners: [[col:green]]+10[[/col]] [[img:ui/skins/default/icon_stat_attack.png]][[/img]] melee attack and "
                          "[[img:ui/skins/default/icon_stat_morale.png]][[/img]] leadership for 8 turns."),
    "holy_water": ("Holy Water", PAY + "buy holy water: [[col:green]]+15% physical resistance[[/col]] for our army for 5 turns."),
    "oath_at_the_altar": ("Oath at the Altar", "Swear an oath at the altar: our lord is [[col:green]]Shrine-Sworn[[/col]] for good (" + stat("+5", *LEADERSHIP) + " for our army)."),
    "sanctified_weapons": ("Sanctify the Weapons", PAY + "sanctify our weapons: [[col:green]]magical attacks[[/col]] for every unit for 5 turns."),
    "dark_pact": ("Make a Dark Pact", "Make a dark pact: our lord is [[col:green]]Pact-Bound[[/col]] for good (" + stat("+10", *ATTACK) + "), but is [[col:red]]wounded for 5 turns[[/col]] at the start of our next turn."),
    "cursed_hoard": ("Take the Cursed Hoard", "Take the cursed hoard: [[col:green]]+{gold} gold[[/col]] to our treasury, but our army suffers [[col:red]]attrition for 3 turns[[/col]]."),
    "bloodstained_blades": ("Take the Bloodstained Blades", "Take up the bloodstained blades: " + stat("+20", *ATTACK) + ", but " + stat("-20", *DEFENCE, colour="red") + " for 5 turns."),
    "feed_the_shadows": ("Feed the Shadows", "Feed the shadows: sacrifice our [[col:red]]weakest unit[[/col]], and every other unit [[col:green]]gains 1 rank[[/col]]."),
    "daemons_bargain": ("Strike a Daemon's Bargain", "Strike a daemon's bargain: [[col:green]]2 unique items[[/col]] now, but [[col:red]]a hard Chaos army marches on our capital[[/col]]."),
    "recruit_the_survivors": ("Recruit the Survivors", "Recruit the survivors: [[col:green]]2 random units[[/col]] of our own kind join our army now."),
    "hire_sellswords": ("Hire Sellswords", PAY + "hire sellswords: [[col:green]]a random elite unit[[/col]] of our own kind joins our army now."),
    "free_the_prisoner": ("Free the Prisoner", "Free the prisoner: [[col:green]]a rank 5 hero[[/col]] joins our army."),
    "tame_the_beast": ("Tame the Beast", "Tame the beast: [[col:green]]a random monster[[/col]] of our own kind joins our army now."),
    "hire_a_regiment_of_renown": ("Hire a Regiment of Renown", PAY + "hire a [[col:green]]Regiment of Renown[[/col]] of our own kind: it joins our army now."),
    "salvage_a_war_machine": ("Salvage a War Machine", PAY + "salvage a war machine: [[col:green]]a random war machine[[/col]] of our own kind joins our army now."),
    "buy_from_the_trader": ("Buy from the Trader", PAY + "buy from the trader: [[col:green]]a random rare item[[/col]]."),
    "pay_the_smugglers": ("Pay the Smugglers", PAY + "pay the smugglers: [[col:green]]-25% recruitment cost[[/col]] for 5 turns."),
    "invest_in_the_caravan": ("Invest in the Caravan", PAY + "invest in the caravan: [[col:green]]+{per_turn} gold[[/col]] to our treasury each turn for 10 turns."),
    "hire_guides": ("Hire Guides", PAY + "hire guides: [[col:green]]+25% movement range[[/col]] for 5 turns."),
    "buy_supplies": ("Buy Supplies", PAY + "buy supplies: our army [[col:green]]ignores attrition[[/col]] for 5 turns."),
    "read_the_scrolls": ("Read the Scrolls", "Read the scrolls: [[col:green]]+20% research rate[[/col]] for 5 turns."),
    "map_the_passes": ("Map the Passes", "Map the passes: [[col:green]]+20% movement range[[/col]] and [[col:green]]+20% ambush defence[[/col]] for 10 turns."),
    "ancient_tactics": ("Study the Ancient Tactics", "Study the ancient tactics: " + stat("+10", *CHARGE) + " and " + stat("+10%", *SPEED) + " for 5 turns."),

    "endow_the_province": ("Endow the Province", PAY + "endow our nearest region: [[col:green]]+50 development points[[/col]]."),
    "shore_up_the_walls": ("Shore Up the Walls", PAY + "shore up our nearest settlement: its garrison is [[col:green]]healed to full[[/col]], and its defenders take "
                           "[[col:green]]50% less attrition under siege[[/col]] for 10 turns."),
    "raise_the_settlement": ("Raise the Settlement", PAY + "raise our nearest settlement: its [[col:green]]main building goes up one level[[/col]]."),
    "quell_the_unrest": ("Quell the Unrest", "Quell the unrest: [[col:green]]+10 public order[[/col]] in our nearest province for 10 turns."),
    "bountiful_harvest": ("Bountiful Harvest", PAY + "sow a bountiful harvest: [[col:green]]+30 growth[[/col]] and [[col:green]]+10% income[[/col]] in our nearest province for 10 turns."),
    "hidden_mint": ("Seize the Hidden Mint", "Seize the hidden mint: [[col:green]]+5% income[[/col]] from all buildings for 10 turns."),
    "stir_their_rebels": ("Stir Their Rebels", PAY + "stir up rebels: the nearest enemy province has [[col:green]]-15 public order[[/col]] for 5 turns."),
    "poison_their_wells": ("Poison Their Wells", PAY + "poison their wells: the nearest enemy region has [[col:green]]-20 growth[[/col]], and its armies suffer [[col:green]]attrition[[/col]] for 5 turns."),
    "undermine_their_walls": ("Undermine Their Walls", PAY + "undermine their walls: the nearest enemy settlement's defenders take [[col:green]]50% more attrition under siege[[/col]] for 5 turns."),
    "spread_the_plague": ("Spread the Plague", "Spread the plague: the 3 nearest enemy regions have [[col:green]]-5 public order[[/col]] and [[col:green]]-20 growth[[/col]] for 5 turns, but our army suffers [[col:red]]attrition for 2 turns[[/col]]."),
    "send_gifts": ("Send Gifts", PAY + "send gifts: [[col:green]]better relations[[/col]] with the nearest faction we are not at war with."),
    "spy_on_their_capital": ("Spy on Their Capital", PAY + "spy on their capital: [[col:green]]the shroud lifts[[/col]] over the nearest enemy capital."),
    "curse_a_distant_king": ("Curse a Distant King", PAY + "curse a distant king: the faction with the most regions has [[col:green]]-10% income[[/col]] for 10 turns."),
    "share_the_find": ("Share the Find", "Share the find: [[col:green]]+10% research rate[[/col]] for 5 turns, for us and every neighbour at peace with us, who think [[col:green]]better of us[[/col]] for it."),
    "point_them_at_each_other": ("Point Them at Each Other", PAY + "set rivals against each other: the two biggest factions near us have [[col:green]]worse relations[[/col]] with each other."),
    "sell_their_secrets": ("Sell Their Secrets", "Sell their secrets: [[col:green]]+{gold} gold[[/col]] to our treasury, but the nearest enemy has [[col:red]]better relations[[/col]] with our other enemies."),

    "bribe_a_scout": ("Bribe a Scout", PAY + "bribe one of their scouts: the enemy army is [[col:green]]25% weaker[[/col]]."),
    "thin_their_ranks": ("Thin Their Ranks", PAY + "thin their ranks: the enemy army fields [[col:green]]3 fewer units[[/col]]."),
    "poison_their_stores": ("Poison Their Stores", PAY + "poison their stores: enemy units start at [[col:green]]75% strength[[/col]]."),
    "kill_the_captain": ("Kill the Captain", PAY + "kill their captain: the enemy army has [[col:green]]no heroes[[/col]]."),
    "keep_the_veterans_away": ("Keep the Veterans Away", PAY + "keep their veterans away: the enemy army has [[col:green]]tier 1-2 units only[[/col]]."),
    "spread_dread": ("Spread Dread", PAY + "spread dread through their camp: enemy units have " + stat("-15", *LEADERSHIP) + "."),
    "turn_a_traitor": ("Turn a Traitor", PAY + "turn a traitor: [[col:green]]a random unit[[/col]] of the enemy's kind joins our army now, and the enemy fields one unit fewer."),
    "hold_war_rites": ("Hold War Rites", PAY + "hold war rites: [[col:green]]+10[[/col]] [[img:ui/skins/default/icon_stat_attack.png]][[/img]] melee attack, "
                       "[[img:ui/skins/default/icon_stat_defence.png]][[/img]] melee defence and [[img:ui/skins/default/icon_stat_morale.png]][[/img]] leadership in this battle."),
    "hone_the_blades": ("Hone the Blades", PAY + "hone every blade: [[col:green]]+15%[[/col]] [[img:ui/skins/default/icon_stat_damage.png]][[/img]] weapon strength and "
                        "[[col:green]]+15[[/col]] [[img:ui/skins/default/modifier_icon_armour_piercing.png]][[/img]] armour-piercing damage in this battle."),
    "paint_warding_sigils": ("Paint Warding Sigils", PAY + "paint warding sigils: [[col:green]]+10% ward save[[/col]] in this battle."),
    "fire_kissed_blades": ("Fire-Kissed Blades", PAY + "pass our blades through the braziers: [[col:green]]flaming attacks[[/col]] for every unit in this battle."),
    "steel_our_resolve": ("Steel Our Resolve", PAY + "steel our resolve: " + stat("+20", *LEADERSHIP) + " and [[col:green]]immunity to fear and terror[[/col]] in this battle."),
    "call_the_winds": ("Call the Winds", PAY + "call the winds: [[col:green]]+30 Winds of Magic[[/col]] reserve in this battle."),
    "raid_the_quartermaster": ("Raid the Quartermaster", PAY + "raid the quartermaster's stores: [[col:green]]+50%[[/col]] [[img:ui/skins/default/icon_stat_ammo.png]][[/img]] ammunition "
                               "and [[col:green]]20%[[/col]] [[img:ui/skins/default/icon_stat_reload_time.png]][[/img]] faster reloads in this battle."),
    "hire_local_allies": ("Hire Local Allies", PAY + "hire local allies: [[col:green]]a small allied army[[/col]] of 5 to 7 units joins us in this battle."),
    "night_raid": ("Night Raid", "Raid their camp by night: a 50/50 chance the enemy army is [[col:green]]25% weaker[[/col]] or our units start at [[col:red]]90% strength[[/col]]."),

    "bottomless_quivers": ("Bottomless Quivers", PAY + "fill bottomless quivers: our missile units [[col:green]]never run out of ammunition[[/col]] in this battle."),
    "oath_of_no_retreat": ("Oath of No Retreat", PAY + "swear an oath of no retreat: our units [[col:green]]cannot rout[[/col]] in this battle."),
    "divine_shield": ("Divine Shield", PAY + "raise a divine shield: our lord [[col:green]]cannot be harmed for the first 5 minutes[[/col]] of this battle."),
    "night_terrors": ("Night Terrors", PAY + "send night terrors: the enemy's [[col:green]]2 most expensive units flee[[/col]] after 1 minute of this battle."),
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
    "strip_the_dead": ("Strip the Dead", "Strip the dead: [[col:green]]+{per_unit} gold[[/col]] to our treasury for each unit in the army we beat."),
    "ransom_the_captain": ("Ransom the Captain", "Ransom their captain: [[col:green]]+{gold} gold[[/col]] to our treasury, but the nearest faction of their kind has [[col:red]]worse relations[[/col]] with us."),
    "tribute_from_the_locals": ("Tribute from the Locals", "Accept tribute from the grateful locals: [[col:green]]+{per_turn} gold[[/col]] to our treasury each turn for 5 turns."),
    "loot_the_baggage": ("Loot the Baggage", "Loot their baggage train: [[col:green]]a random item[[/col]] of the battle's rarity."),
    "recruit_a_captive": ("Recruit a Captive", "Recruit a captive: [[col:green]]a random unit[[/col]] of the army we beat joins our army now."),
    "freed_captives": ("Free the Captives", "Free their captives: [[col:green]]2 random units[[/col]] of our own kind join our army now."),
    "bury_the_dead": ("Bury the Dead", "Bury our dead with honour: " + stat("+10", *LEADERSHIP) + " for 5 turns."),
    "press_on": ("Press On", "Press on while they flee: [[col:green]]+25% movement range[[/col]] next turn."),
    "victory_feast": ("Victory Feast", PAY + "hold a victory feast: " + stat("+10", *LEADERSHIP) + " and " + stat("+5", *ATTACK) + " for 5 turns."),
    "trophy_of_war": ("Trophy of War", "Take a trophy of war: our lord grows as a [[col:green]]Trophy Hunter[[/col]], a trait that rises with every trophy taken."),
    "chase_the_routers": ("Chase the Routers", "Chase down the routers: a 50/50 chance of [[col:green]]a random rare item[[/col]] or our lord [[col:red]]wounded for 2 turns[[/col]] at the start of our next turn."),
    "cursed_trophy": ("Take the Cursed Trophy", "Take the cursed trophy: [[col:green]]+{gold} gold[[/col]] to our treasury, but our army suffers [[col:red]]attrition for 3 turns[[/col]]."),
    "dark_offering": ("Make a Dark Offering", "Make a dark offering: sacrifice our [[col:red]]weakest unit[[/col]], and our lord gains [[col:green]]2 ranks[[/col]] and [[col:green]]+10% ward save[[/col]] for our army for 5 turns."),
    "walk_away": ("Walk Away", "Leave this place be."),
}

# Offer key -> its line's vanilla effect-bundle icon, reusing the icons Steve picked for the matching tower offers.
ICONS = {
    "tomb_robbing": "resource_gold_idols.png", "abandoned_camp": "replenishment.png", "buried_relics": "treasure_map.png",
    "hidden_temple": "temples_of_the_old_ones.png", "caravan_remnants": "convoy_icon.png", "whispers_of_the_gods": "lileaths_blessing.png",
    "the_explorer": "vision.png", "legendary_bard": "income.png", "take_the_gold": "treasury.png", "strip_the_valuables": "nor_spoils.png",
    "pry_open_the_reliquary": "hex_1.png", "search_every_corner": "cotw_track_army.png", "the_hidden_vault": "resource_gold_idols_large.png",
    "roll_the_bones": "random_recipe.png", "drink_from_the_spring": "stat_healing_received.png", "open_the_sealed_door": "concealment.png",
    "stake_the_treasury": "trickster_cult.png", "wake_the_guardian": "hellforged.png", "touch_the_relic": "fractured_mind.png", "gamble_with_the_hermit": "random_recipe.png",
    "leave_an_offering": "resistance_ward_save.png", "bless_the_banners": "effect_rite.png", "holy_water": "resistance_physical.png",
    "oath_at_the_altar": "champions_rift.png", "sanctified_weapons": "magical_attacks_force.png", "dark_pact": "chaos_gifts.png",
    "cursed_hoard": "plague.png", "bloodstained_blades": "rampage_savage.png", "feed_the_shadows": "bloodreaper.png",
    "daemons_bargain": "daemonic_gift.png", "recruit_the_survivors": "edict_levy_conscripts.png", "hire_sellswords": "merc_contract.png",
    "free_the_prisoner": "noble.png", "tame_the_beast": "attribute_causes_terror.png", "hire_a_regiment_of_renown": "champions_essence.png",
    "salvage_a_war_machine": "artillery.png", "buy_from_the_trader": "trade_agreement.png", "pay_the_smugglers": "military_spending.png",
    "invest_in_the_caravan": "income.png", "hire_guides": "campaign_movement.png", "buy_supplies": "attrition.png",
    "read_the_scrolls": "technology.png", "map_the_passes": "vision.png", "ancient_tactics": "charge.png",
    "endow_the_province": "edict_imperial_taxation.png", "shore_up_the_walls": "siege_defence.png", "raise_the_settlement": "exalted_hero.png",
    "quell_the_unrest": "army_morale.png", "bountiful_harvest": "income.png", "hidden_mint": "resource_gold_idols_large.png",
    "stir_their_rebels": "discouraged.png", "poison_their_wells": "phase_posion.png", "undermine_their_walls": "siege_attack.png",
    "spread_the_plague": "plague.png", "send_gifts": "trade_agreement.png", "spy_on_their_capital": "cotw_reveal_shroud.png",
    "curse_a_distant_king": "hex_1.png", "share_the_find": "technology.png", "point_them_at_each_other": "subterfuge.png",
    "sell_their_secrets": "assassin.png", "walk_away": "campaign_movement.png",
    "strip_the_dead": "nor_spoils.png", "ransom_the_captain": "noble.png", "tribute_from_the_locals": "income.png", "loot_the_baggage": "treasure_map.png",
    "recruit_a_captive": "slaves.png", "freed_captives": "edict_levy_conscripts.png", "bury_the_dead": "army_morale.png", "press_on": "campaign_movement.png",
    "victory_feast": "effect_rite.png", "trophy_of_war": "wh3_cp1_unit_reward.png", "chase_the_routers": "cotw_track_army.png", "cursed_trophy": "plague.png",
    "dark_offering": "bloodreaper.png",
    "bribe_a_scout": "subterfuge.png", "thin_their_ranks": "attrition.png", "poison_their_stores": "phase_posion.png",
    "kill_the_captain": "dlc10_assassination_targets.png", "keep_the_veterans_away": "peasant.png", "spread_dread": "discouraged.png",
    "turn_a_traitor": "khainite_assassin.png", "hold_war_rites": "effect_rite.png", "hone_the_blades": "weapon_damage.png",
    "paint_warding_sigils": "resistance_ward_save.png", "fire_kissed_blades": "modifier_icon_flaming.png", "steel_our_resolve": "attribute_immune_to_psychology.png",
    "call_the_winds": "wh3_dlc24_wind_blast.png", "raid_the_quartermaster": "ammo.png", "hire_local_allies": "trade_agreement.png", "night_raid": "dlc10_death_night.png",
    "bottomless_quivers": "ammo_character.png", "oath_of_no_retreat": "morale.png", "divine_shield": "lileaths_blessing.png",
    "night_terrors": "dlc10_death_night.png", "assassinate": "assassin.png", "headhunt": "dlc10_assassination_targets.png", "blood_tally": "casualties.png",
    "hold_the_line": "siege_defence.png", "swift_victory": "vigour.png", "guard_the_standard": "vow_knights_positive.png",
    "break_them": "attribute_causes_terror.png", "trophy_hunt": "wh3_cp1_unit_reward.png", "silence_the_guns": "artillery.png",
    "bloodbath_wager": "khorne_skulls.png", "duelists_challenge": "rampage_harsh.png", "spare_the_captain": "noble.png", "flawless_victory": "champions_rift.png",
}

# Line on a mission already taken on the open battle dilemma: (icon, text).
TAKEN = ("icon_blank.png", "[[col:red]]Already taken.[[/col]]")

# Mission key -> (what it asked, said when met, said when failed). Each becomes a result after a won battle.
MISSION_MESSAGES = {
    "headhunt": ("Headhunt",
        "The enemy lord fell in time, just as we vowed. Their finest possession, a rare item, now belongs to us.",
        "The enemy lord lived too long, and our vow goes unfulfilled."),
    "blood_tally": ("Blood Tally",
        "The enemy's soldiers fell in their hundreds, and the tally is met. The gold we were promised is ours.",
        "Too few of the enemy fell, and the tally comes up short."),
    "hold_the_line": ("Hold the Line",
        "Our line bent but never broke, and few of our units were lost. The gold we were promised is ours.",
        "Our line held in the end, but too many of our units were lost along the way."),
    "swift_victory": ("Swift Victory",
        "The battle was over almost before it began. Word of the swift victory spreads, and an extra item comes our way.",
        "The battle dragged on too long for the victory to be called swift."),
    "guard_the_standard": ("Guard the Standard",
        "The marked unit stood firm through the worst of the fighting. They return as hardened veterans, 3 ranks the wiser.",
        "The marked unit was lost in the fighting, and their sacrifice earns no reward."),
    "break_them": ("Break Them",
        "Unit after unit of theirs broke and fled before us. The gold we were promised is ours.",
        "Too few of their units broke, and they fought on to the bitter end."),
    "trophy_hunt": ("Trophy Hunt",
        "Their finest unit fell to our blades. Its survivors are pressed into our service, and a copy of it joins our army.",
        "Their finest unit survived the battle, and the trophy slips through our fingers."),
    "silence_the_guns": ("Silence the Guns",
        "Their guns fell silent before they could do much harm. Among the wreckage we find a rare item, and it is ours.",
        "Their guns kept firing for too long, and the mission is failed."),
    "bloodbath_wager": ("Bloodbath Wager",
        "The field ran red, and the wager is won. The gold comes back to us many times over.",
        "Too few of the enemy fell, and the gold we wagered is lost."),
    "duelists_challenge": ("Duellist's Challenge",
        "Our lord met theirs blade to blade and struck them down. A unique item is taken from the fallen lord, and it is ours.",
        "Our lord did not slay theirs, and the challenge goes unanswered."),
    "spare_the_captain": ("Spare the Captain",
        "Their lord was taken alive, just as we planned. The ransom has been paid, and the gold is ours.",
        "Their lord fell in the fighting, so there is no one left to ransom."),
    "flawless_victory": ("Flawless Victory",
        "Not a single unit of ours was lost. Songs of the flawless victory spread far, and a unique item is ours.",
        "We lost a unit, and the victory was not flawless."),
}

# Battle objectives for the missions the tower does not have: name -> (panel text, banner).
MISSION_OBJECTIVES = {
    "spare_the_captain": ("Spare the Captain: keep the enemy lord alive", "Spare the Captain: win with the enemy lord still alive."),
    "flawless_victory": ("Flawless Victory: our units lost", "Flawless Victory: win without losing a single unit."),
}

# Battle notice name -> (colour, text) the battle script shows for a pre-battle offer: red for what weakens the enemy, green for our help,
# yellow for a cost to our army, as the tower's notices do. A one-battle bundle uses the tower's own notice.
NOTICES = {
    "bribe_a_scout": ("red", "Bribe a Scout: the enemy army is 25% weaker."),
    "thin_their_ranks": ("red", "Thin Their Ranks: the enemy fields 3 fewer units."),
    "poison_their_stores": ("red", "Poison Their Stores: enemy units start at 75% strength."),
    "keep_the_veterans_away": ("red", "Keep the Veterans Away: the enemy has tier 1-2 units only."),
    "spread_dread": ("red", "Spread Dread: enemy units have -15 [[img:ui/skins/default/icon_stat_morale.png]][[/img]]."),
    "hire_local_allies": ("green", "Hire Local Allies: an allied army joins the battle."),
    "night_raid_won": ("red", "Night Raid: the enemy army is 25% weaker."),
    "night_raid_lost": ("yellow", "Night Raid: our units start at 90% strength."),
}

# Pre-battle offers that share a key and an effect with a tower offer, so the battle script shows the tower's notice for them.
TOWER_NOTICES = {"kill_the_captain", "turn_a_traitor"}

# Notice -> the offer whose line icon it shows.
NOTICE_ICONS = {"night_raid_won": "night_raid", "night_raid_lost": "night_raid"}

# Second line under Avoid on every battle dilemma, since avoiding fires the category's avoidance incident.
AVOID_CONSEQUENCES = ("avoid_consequences", "random_recipe.png", "[[col:yellow]]This may have unforeseen consequences.[[/col]]")



# Message suffix after `spot_` -> (title, subtitle, description). Realm messages have no subtitle: their {place} is the target region's name,
# or the target faction's when it holds no region. Each is also a result incident, which shows only the title and description, with the
# place highlighted.
MESSAGES = {
    "roll_the_bones_won": ("Roll the Bones", "Fortune Smiles",
        "The old bones clatter across the stone and land in our favour. The stranger who offered the game scowls, but pays up all the same, and a rare item is ours."),
    "roll_the_bones_lost": ("Roll the Bones", "Fortune Frowns",
        "The bones tumble and settle against us. The stranger sweeps up our gold with a crooked grin and is gone before anyone thinks to argue."),
    "drink_from_the_spring_won": ("Drink from the Spring", "Healing Waters",
        "The water runs cold and clear. Wounds close and tired limbs grow strong again as the whole army drinks its fill."),
    "drink_from_the_spring_lost": ("Drink from the Spring", "Foul Waters",
        "The water tastes of rot. Within hours sickness spreads through the camp, and it will be 3 turns before the army is itself again."),
    "open_the_sealed_door_won": ("Open the Sealed Door", "A Treasure Within",
        "The seal breaks and the door grinds open on a chamber untouched for centuries. At its heart lies a treasure of legend, and now it is ours."),
    "open_the_sealed_door_lost": ("Open the Sealed Door", "A Trap Sprung",
        "The seal breaks, and so does the trap behind it. Our lord is caught in the blast, and the wound will lay them low for 3 turns at the start of our next turn."),
    "stake_the_treasury_won": ("Stake the Treasury", "The Stake Pays",
        "The venture pays off handsomely. Our stake comes back to the treasury with a healthy profit on top."),
    "stake_the_treasury_lost": ("Stake the Treasury", "The Stake Is Lost",
        "The venture collapses, and the merchants we backed are nowhere to be found. Our stake is gone."),
    "wake_the_guardian_won": ("Wake the Guardian", "It Sleeps On",
        "The great beast stirs, snorts and settles back into its slumber. We creep past it and make off with a rare treasure from its hoard."),
    "wake_the_guardian_lost": ("Wake the Guardian", "It Wakes!",
        "The ground shakes as the guardian of this place rises from its slumber. It sees intruders in its lair and charges, and our army must stand and fight!"),
    "touch_the_relic_blessed": ("Touch the Relic", "A Blessing",
        "Warmth spreads from the relic into the hands that hold it. A blessing settles over our army and will stay with it for 5 turns."),
    "touch_the_relic_cursed": ("Touch the Relic", "A Curse",
        "The relic is cold as a grave, and a creeping dread spreads through the ranks. A curse settles over our army for 5 turns."),
    "gamble_with_the_hermit_won": ("Gamble with the Hermit", "A Lucky Throw",
        "The hermit squints at the dice, then laughs and shuffles off into the hut. They return with a unique treasure and press it into our hands."),
    "gamble_with_the_hermit_lost": ("Gamble with the Hermit", "The Hermit Wins",
        "The hermit wins throw after throw, cackling all the while. When the game is done our gold is in the hermit's pouch, and the hermit is gone."),
    "endow_the_province": ("Endow the Province", "", "Our gold builds up {place}: [[col:green]]+50 development points[[/col]]."),
    "shore_up_the_walls": ("Shore Up the Walls", "", "The garrison of {place} is healed and its walls are shored up."),
    "raise_the_settlement": ("Raise the Settlement", "", "{place} grows, its main building raised a level."),
    "quell_the_unrest": ("Quell the Unrest", "", "Order returns to {place}."),
    "bountiful_harvest": ("Bountiful Harvest", "", "{place} prospers with a bountiful harvest."),
    "stir_their_rebels": ("Stir Their Rebels", "", "Unrest spreads through the enemy's lands around {place}."),
    "poison_their_wells": ("Poison Their Wells", "", "The wells of {place} are fouled."),
    "undermine_their_walls": ("Undermine Their Walls", "", "The walls of {place} are undermined."),
    "spread_the_plague": ("Spread the Plague", "", "Plague spreads through the enemy's lands around {place}."),
    "send_gifts": ("Send Gifts", "", "Our gifts are well received at {place}."),
    "spy_on_their_capital": ("Spy on Their Capital", "", "Our spies have mapped the enemy's capital, {place}."),
    "curse_a_distant_king": ("Curse a Distant King", "", "A curse falls on the coffers of the king at {place}."),
    "share_the_find": ("Share the Find", "", "Our neighbours at {place} learn from what we found, and think better of us."),
    "point_them_at_each_other": ("Point Them at Each Other", "", "Rumours spread from {place}, and two rivals now eye each other with suspicion."),
    "sell_their_secrets": ("Sell Their Secrets", "", "The secrets are sold at {place}, and our enemies grow closer."),
    "ransom_the_captain": ("Ransom the Captain", "", "Their captain is ransomed to {place}, and their kin will not forget it."),
    "chase_the_routers_won": ("Chase the Routers", "A Rich Catch",
        "Our fastest troops run the fleeing enemy down before they reach safety. Among the spoils they drop is a rare item, and it is ours."),
    "chase_the_routers_lost": ("Chase the Routers", "Ambushed",
        "The fleeing enemy were bait. They turn on our pursuers in a narrow pass, and our lord takes a wound that will lay them low for 2 turns at the start of our next turn."),
}

# Shown when a wound an offer owed lands, by its turns. The bundle title for the owed wound is the same for every length.
WOUND_PAID = ("The Price Is Paid", "Our Lord Is Wounded", "The price of what we took has come due. Our lord is struck down by a wound that will take {turns} turns to heal.")
WOUND_OWED = ("A Price Owed", "What we took will take its due when our next turn starts.")
WOUND_OWED_EFFECT = "Our lord is wounded for %n turns at the start of our next turn"

# Result -> (colour, text) of the effect line under a result's incident, for results whose payload shows no gold, item or unit card.
# Every mission failed gets its own line, and every wound paid one built from WOUND_PAID_LINE.
RESULT_LINES = {
    "roll_the_bones_lost": ("red", "The gold we staked is lost."),
    "drink_from_the_spring_won": ("green", "Every unit in our army is healed."),
    "drink_from_the_spring_lost": ("red", "Our army is sick for 3 turns."),
    "open_the_sealed_door_lost": ("red", "Our lord is wounded for 3 turns at the start of our next turn."),
    "stake_the_treasury_lost": ("red", "The gold we staked is lost."),
    "wake_the_guardian_lost": ("red", "The guardian attacks our army!"),
    "touch_the_relic_blessed": ("green", "A blessing settles on our army for 5 turns."),
    "touch_the_relic_cursed": ("red", "A curse settles on our army for 5 turns."),
    "gamble_with_the_hermit_lost": ("red", "The hermit keeps our gold."),
    "chase_the_routers_lost": ("red", "Our lord is wounded for 2 turns at the start of our next turn."),
    "endow_the_province": ("green", "+50 development points in the region."),
    "shore_up_the_walls": ("green", "The garrison is healed and the walls are shored up."),
    "raise_the_settlement": ("green", "The settlement's main building is raised a level."),
    "quell_the_unrest": ("green", "Order returns to the province."),
    "bountiful_harvest": ("green", "The province prospers with a bountiful harvest."),
    "stir_their_rebels": ("green", "Unrest spreads through the enemy's province."),
    "poison_their_wells": ("green", "The enemy's wells are fouled."),
    "undermine_their_walls": ("green", "The enemy's walls are undermined."),
    "spread_the_plague": ("green", "Plague spreads through the enemy's lands."),
    "send_gifts": ("green", "Their opinion of us improves."),
    "spy_on_their_capital": ("green", "The enemy's capital is revealed to us."),
    "curse_a_distant_king": ("green", "A distant king's income falls."),
    "share_the_find": ("green", "Our neighbours think better of us."),
    "point_them_at_each_other": ("green", "Two rivals now eye each other with suspicion."),
    "sell_their_secrets": ("yellow", "Our enemies think better of each other."),
    "ransom_the_captain": ("yellow", "Their captain's kin think worse of us."),
    "mission_guard_the_standard_met": ("green", "The marked unit gains 3 ranks."),
    "missions_untracked": ("yellow", "No mission was counted. Any wager comes back to our treasury."),
}
WOUND_PAID_LINE = ("red", "Our lord is wounded for {turns} turns.")

# Bundle key suffix after `land_enc_effect_spot_` -> (target, icon, title, description, [(effect, scope, value)]).
BUNDLES = {
    "reinforcement_time_25": ("force", "military.png", "Swift Reinforcements", "Reinforcements for this army arrive sooner.",
                              [("wh3_main_effect_own_reinforcement_time_percentage_mod", "force_to_force_own", -25)]),
    "reinforcement_time_50": ("force", "military.png", "Swift Reinforcements", "Reinforcements for this army arrive sooner.",
                              [("wh3_main_effect_own_reinforcement_time_percentage_mod", "force_to_force_own", -50)]),
    "reinforcement_time_75": ("force", "military.png", "Swift Reinforcements", "Reinforcements for this army arrive sooner.",
                              [("wh3_main_effect_own_reinforcement_time_percentage_mod", "force_to_force_own", -75)]),
    "camping": ("force", "icon_effects_fortify.png", "Searching Every Corner", "Our army searches every corner and cannot march until our next turn.",
                [("wh_main_effect_force_all_campaign_movement_range", "force_to_force_own", -100)]),
    "strip_the_valuables": ("force", "icon_effects_fortify.png", "Weighed Down", "Our army carries heavy loot.",
                            [("wh_main_effect_force_stat_leadership", "force_to_force_own", -10)]),
    "bless_the_banners": ("force", "icon_effects_fortify.png", "Blessed Banners", "Our banners were blessed at a shrine.",
                          [("wh_main_effect_force_stat_melee_attack", "force_to_force_own", 10), ("wh_main_effect_force_stat_leadership", "force_to_force_own", 10)]),
    "holy_water": ("force", "icon_effects_fortify.png", "Holy Water", "Our army was anointed with holy water.",
                   [("wh_main_effect_force_stat_physical_resistance", "force_to_force_own", 15)]),
    "ancient_tactics": ("force", "icon_effects_fortify.png", "Ancient Tactics", "Our army drills in tactics from an older age.",
                        [("wh2_dlc14_effect_force_charge_bonus_add", "force_to_force_own", 10), ("wh_main_effect_force_stat_speed", "force_to_force_own", 10)]),
    "touch_the_relic_frailty": ("force", "icon_effects_fortify.png", "Relic's Frailty", "A relic's curse saps our army's guard.",
                                [("wh_main_effect_force_stat_melee_defence", "force_to_force_own", -10), ("wh_main_effect_force_stat_armour", "force_to_force_own", -10)]),
    "leave_an_offering": ("force", "icon_effects_fortify.png", "Offering Made", "An offering at a shrine wards our army.",
                          [("wh_main_effect_force_stat_ward_save", "force_to_force_own", 10)]),
    "sanctified_weapons": ("force", "icon_effects_fortify.png", "Sanctified Weapons", "Our army's weapons were sanctified.",
                           [("wh_main_effect_force_stat_enable_magic_attacks", "force_to_force_own", 1)]),
    "bloodstained_blades": ("force", "icon_effects_fortify.png", "Bloodstained Blades", "Our army fights with cursed blades.",
                            [("wh_main_effect_force_stat_melee_attack", "force_to_force_own", 20), ("wh_main_effect_force_stat_melee_defence", "force_to_force_own", -20)]),
    "hire_guides": ("force", "icon_effects_fortify.png", "Local Guides", "Hired guides lead our army by hidden paths.",
                    [("wh_main_effect_force_all_campaign_movement_range", "force_to_force_own", 25)]),
    "buy_supplies": ("force", "icon_effects_fortify.png", "Well Supplied", "Our army carries plenty of supplies.",
                     [("wh_main_effect_force_army_campaign_attrition_all_immunity", "force_to_force_own", 1)]),
    "map_the_passes": ("force", "icon_effects_fortify.png", "Mapped Passes", "Our army knows the land's passes.",
                       [("wh_main_effect_force_all_campaign_movement_range", "force_to_force_own", 20),
                        ("wh_main_effect_force_army_campaign_ambush_defence_success_chance", "force_to_force_own", 20)]),
    "read_the_scrolls": ("faction", "technology.png", "Ancient Scrolls", "Scrolls from a lost library speed our research.",
                         [("wh_main_effect_technology_research_rate_mod", "faction_to_faction_own", 20)]),
    "hidden_mint": ("faction", "income.png", "Hidden Mint", "A hidden mint fills our coffers.",
                    [("wh_main_effect_economy_gdp_mod_all", "faction_to_region_own", 5)]),
    "share_the_find": ("faction", "technology.png", "Shared Knowledge", "Knowledge shared between neighbours.",
                       [("wh_main_effect_technology_research_rate_mod", "faction_to_faction_own", 10)]),
    "curse_a_distant_king": ("faction", "chaos_gifts.png", "Cursed Coffers", "A curse drains this king's coffers.",
                             [("wh_main_effect_economy_gdp_mod_all", "faction_to_region_own", -10)]),
    "shore_up_the_walls": ("region", "income.png", "Shored-Up Walls", "The walls are shored up and the stores filled.",
                           [("wh_main_effect_force_army_campaign_siege_defend_attrition", "region_to_force_own", -50)]),
    "poison_their_wells": ("region", "chaos_gifts.png", "Poisoned Wells", "The wells here are fouled.",
                           [("wh_main_effect_province_growth_events", "region_to_province_own", -20), ("wh_main_effect_campaign_enable_attrition", "region_to_force_own", 1)]),
    "undermine_their_walls": ("region", "chaos_gifts.png", "Undermined Walls", "The walls here are undermined.",
                              [("wh_main_effect_force_army_campaign_siege_defend_attrition", "region_to_force_own", 50)]),
    "spread_the_plague": ("region", "chaos_gifts.png", "Plague", "Plague spreads through the region.",
                          [("wh_main_effect_public_order_events", "region_to_province_own", -5), ("wh_main_effect_province_growth_events", "region_to_province_own", -20)]),
    "quell_the_unrest": ("province", "income.png", "Order Restored", "Order is restored in the province.",
                         [("wh_main_effect_public_order_events", "province_to_province_own", 10)]),
    "bountiful_harvest": ("province", "income.png", "Bountiful Harvest", "A bountiful harvest across the province.",
                          [("wh_main_effect_province_growth_events", "province_to_province_own", 30), ("wh_main_effect_economy_gdp_mod_all", "province_to_region_own", 10)]),
    "stir_their_rebels": ("province", "chaos_gifts.png", "Stirred Rebels", "Rebels stir in the province.",
                          [("wh_main_effect_public_order_events", "province_to_province_own", -15)]),
    "bury_the_dead": ("force", "icon_effects_fortify.png", "Honoured Dead", "Our dead were buried with honour.",
                      [("wh_main_effect_force_stat_leadership", "force_to_force_own", 10)]),
    "press_on": ("force", "icon_effects_fortify.png", "Pressing On", "Our army presses on while the enemy flees.",
                 [("wh_main_effect_force_all_campaign_movement_range", "force_to_force_own", 25)]),
    "victory_feast": ("force", "icon_effects_fortify.png", "Victory Feast", "Our army feasted on its victory.",
                      [("wh_main_effect_force_stat_leadership", "force_to_force_own", 10), ("wh_main_effect_force_stat_melee_attack", "force_to_force_own", 5)]),
    "dark_offering": ("force", "icon_effects_fortify.png", "Dark Offering", "A dark offering wards our army.",
                      [("wh_main_effect_force_stat_ward_save", "force_to_force_own", 10)]),
}

# Trait key -> (icon, [(points needed, name, flavour, what earned it, [(effect, scope, value)])] one per level).
TRAITS = {
    "land_enc_trait_spot_shrine_sworn": ("trait_good", [
        (1, "Shrine-Sworn", "Swore an oath at a ruined altar, and the army believes it.", "Swore an oath at a ruined shrine",
         [("wh_main_effect_force_stat_leadership", "character_to_force_own", 5)]),
    ]),
    "land_enc_trait_spot_pact_bound": ("chaos", [
        (1, "Pact-Bound", "The power is real, and so is the price.", "Struck a dark pact in a witch's hut",
         [("wh_main_effect_character_stat_melee_attack", "character_to_character_own", 10)]),
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
local battle_dilemmas = {}
for key in pairs(require("script/land_encounters/configs/battle_categories").dilemma_keys) do battle_dilemmas[#battle_dilemmas + 1] = key end
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
io.write(encode({ sites = data.sites, spoils = data.spoils, offers = data.offers, gold_multiplier = data.gold_multiplier, gold_step = data.gold_step,
    choice_key_prefix = data.choice_key_prefix, walk_away_choice_key = data.walk_away_choice_key, signature_choice_key = data.signature_choice_key,
    dilemma_prefix = data.dilemma_prefix, line_prefix = data.line_prefix, message_prefix = data.message_prefix, camp_bundle = data.camp_bundle,
    result_incident_prefix = data.result_incident_prefix, result_place_context = data.result_place_context, battle_pools = data.battle_pools,
    wound_bundle_prefix = data.wound_bundle_prefix, avoid_choice_key = data.avoid_choice_key,
    unaffordable_line = data.unaffordable_line, taken_line = data.taken_line, missions_context = data.missions_context,
    mission_set_loc_prefix = data.mission_set_loc_prefix, battle_dilemmas = battle_dilemmas }))
"""


def load_config() -> Dict:
    """Reads `configs/spot_offers.lua` through the `lua` executable.

    Returns:
        Dict: The sites, offers and naming constants.

    Raises:
        subprocess.CalledProcessError: When Lua cannot load the config.
    """
    output = subprocess.run(["lua", "-", MOD_ROOT], input=LUA_DUMP, capture_output=True, text=True, check=True).stdout
    return json.loads(output)


def title_case(text: str) -> str:
    """Title-cases a name the way vanilla does: every word capitalised except small words after the first.

    Args:
        text (str): The name.

    Returns:
        str: The name in title case.
    """
    words = text.split(" ")
    for i, word in enumerate(words):
        bare = word.lower().rstrip(".,:;!?'")
        words[i] = word[0].lower() + word[1:] if i > 0 and bare in SMALL_WORDS else word[0].upper() + word[1:]
    return " ".join(words)


def gold_text(amount: int) -> str:
    """Writes gold as a whole number with no thousands separator, the way vanilla and the tower write it.

    Args:
        amount (int): The gold.

    Returns:
        str: E.g. "1500".
    """
    return str(amount)


def scale(amount: int, difficulty: str, offer: Dict, config: Dict) -> int:
    """Scales gold the way `features/spot_offers.lua` does.

    Args:
        amount (int): The Easy amount.
        difficulty (str): The difficulty key.
        offer (Dict): The offer record. `fixed_gold` keeps the amount.
        config (Dict): The loaded config.

    Returns:
        int: The scaled amount, rounded to the gold step.
    """
    if offer.get("fixed_gold"):
        return amount
    step = config["gold_step"]
    return int(amount * config["gold_multiplier"][difficulty] / step + 0.5) * step


def line_values(offer: Dict, difficulty: str, config: Dict) -> Dict[str, str]:
    """Works out the gold an offer's lines name at a difficulty.

    Args:
        offer (Dict): The offer record.
        difficulty (str): The difficulty key.
        config (Dict): The loaded config.

    Returns:
        Dict[str, str]: Values for {cost}, {gold}, {won_gold}, {lost_gold}, {per_turn} and {per_unit}.
    """
    values = {"cost": "", "gold": "", "won_gold": "", "lost_gold": "", "per_turn": "", "per_unit": ""}
    if "cost" in offer:
        values["cost"] = gold_text(scale(offer["cost"], difficulty, offer, config))
    if "gold" in offer:
        values["gold"] = gold_text(scale(offer["gold"], difficulty, offer, config))
    for outcome in offer.get("gamble", []):
        if "gold" in outcome:
            values[outcome["2"] + "_gold"] = gold_text(abs(scale(outcome["gold"], difficulty, offer, config)))
    if "dividends" in offer:
        values["per_turn"] = gold_text(scale(offer["dividends"]["per_turn"], difficulty, offer, config))
    if "gold_per_enemy_unit" in offer:
        values["per_unit"] = gold_text(scale(offer["gold_per_enemy_unit"], difficulty, offer, config))
    return values


def wound_turns(config: Dict) -> List[int]:
    """Lists every wound length an offer or gamble outcome can owe.

    Args:
        config (Dict): The loaded config.

    Returns:
        List[int]: The distinct turns, sorted.
    """
    turns = set()
    for offer in config["offers"]:
        for fields in [offer] + offer.get("gamble", []):
            if "wound" in fields:
                turns.add(fields["wound"])
    return sorted(turns)


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
        add(LOC_PREFIX + "campaign_payload_ui_details.loc.tsv", "campaign_payload_ui_details_description_" + component, text, "false")

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
    choice_keys = [(config["choice_key_prefix"] + o["key"].upper(), o["key"]) for o in config["offers"]] + [(config["walk_away_choice_key"], "walk_away")]
    site_keys = [(c, k) for c, k in choice_keys if k == "walk_away" or by_key[k]["pool"] not in config["battle_pools"]]
    battle_keys = [(c, k) for c, k in choice_keys if k != "walk_away" and by_key[k]["pool"] in config["battle_pools"]]
    row_id = FIRST_ROW_ID
    for site in config["sites"] + [config["spoils"]]:
        dilemma = config["dilemma_prefix"] + site["key"]
        title, description = SITES[site["key"]]
        add(table("dilemmas_tables"), dilemma, "false", "", "", site["ui_image"], "false", "Event", "UI_CAM_EVENT_Dilemma", "", "", "false")
        for option, value in [("GEN_TARGET_NONE", ""), ("VAR_CHANCE", "100"), ("VAR_FOLLOWUP_CHANCE", "100")]:
            add(table("cdir_events_dilemma_option_junctions_tables"), row_id, dilemma, option, value, "default")
            row_id += 1
        add(table("cdir_events_dilemma_payloads_tables"), row_id, "FIRST", dilemma, "TEXT_DISPLAY", "LOOKUP[dummy_do_nothing]", "default")
        row_id += 1
        add(LOC_PREFIX + "dilemmas.loc.tsv", "dilemmas_localised_title_" + dilemma, title_case(title), "false")
        add(LOC_PREFIX + "dilemmas.loc.tsv", "dilemmas_localised_description_" + dilemma, description + SITE_FOOTER, "false")
        labels = site_keys + ([(config["signature_choice_key"], site["signature"])] if site.get("signature") else [])
        for choice, key in labels:
            label(dilemma, choice, title_case(OFFERS[key][0]))

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
        objective(notice, ICONS[NOTICE_ICONS.get(notice, notice)], f"[[col:{colour}]]{text}[[/col]]", text)

    for i, (choice, key) in enumerate(choice_keys):
        add(table("cdir_events_dilemma_choices_tables"), choice, WALK_AWAY_ORDER if key == "walk_away" else FIRST_CHOICE_ORDER + i)
        _, text = OFFERS[key]
        if key == "walk_away":
            line(config["line_prefix"] + "walk_away", ICONS[key], text)
            continue
        offer = by_key[key]
        for difficulty in DIFFICULTIES:
            values = line_values(offer, difficulty, config)
            component = config["line_prefix"] + key + "_" + difficulty
            line(component, ICONS[key], text.format(**values))
            if offer["pool"] == "mission":
                taken = text.format(**values).replace(MISSION, f"[[col:yellow]]{title_case(OFFERS[key][0])} (Mission):[[/col]] ", 1)
                add(STRINGS_LOC, config["mission_set_loc_prefix"] + key + "_" + difficulty, taken, "false")

    for suffix, (target, icon, title, description, effects) in BUNDLES.items():
        key = "land_enc_effect_spot_" + suffix
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
    owed_effect = config["wound_bundle_prefix"].rstrip("_")
    add(table("effects_tables"), owed_effect, "chaos_gifts.png", 2, "chaos_gifts.png", "campaign", "false")
    add(LOC_PREFIX + "effects.loc.tsv", "effects_description_" + owed_effect, WOUND_OWED_EFFECT, "false")
    for turns in wound_turns(config):
        key = config["wound_bundle_prefix"] + str(turns)
        add(table("effect_bundles_tables"), key, "", "", "force", 1, "chaos_gifts.png", "false", "false", "true")
        add(table("effect_bundles_to_effects_junctions_tables"), key, owed_effect, "force_to_force_own", f"{turns:.4f}", "start_turn_completed")
        add(LOC_PREFIX + "effect_bundles.loc.tsv", "effect_bundles_localised_title_" + key, title_case(WOUND_OWED[0]), "false")
        add(LOC_PREFIX + "effect_bundles.loc.tsv", "effect_bundles_localised_description_" + key, WOUND_OWED[1], "false")
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
        for field, text in [("title", title_case(title)), ("subtitle", title_case(subtitle or title)), ("description", fallback_text(description))]:
            add(LOC_PREFIX + "event_feed_strings.loc.tsv", f"event_feed_strings_text_{field}_event_land_enc_{name}", text, "false")
        incident = config["result_incident_prefix"] + suffix
        image = MISSION_RESULT_IMAGE if suffix.startswith("mission") else RESULT_IMAGE
        add(table("incidents_tables"), incident, "false", image, "false", "Event", "", "false", "", "0.0000", "false")
        for option, value in [("GEN_TARGET_NONE", ""), ("VAR_CHANCE", "100")]:
            add(table("cdir_events_incident_option_junctions_tables"), row_id, incident, option, value, "default")
            row_id += 1
        place = f'{{{{CcoCampaignEventIncident:ScriptObjectContext("{config["result_place_context"]}").StringValue}}}}'
        shown = description.replace("{place}", f"[[col:yellow]]{place}[[/col]]")
        add(LOC_PREFIX + "incidents.loc.tsv", "incidents_localised_title_" + incident, title_case(title), "false")
        add(LOC_PREFIX + "incidents.loc.tsv", "incidents_localised_description_" + incident, shown, "false")
        if suffix in lines:
            colour, text = lines[suffix]
            line(config["line_prefix"] + "result_" + suffix, result_icon(suffix), f"[[col:{colour}]]{text}[[/col]]")
    return rows


def fallback_text(description: str) -> str:
    """Words a result's description for its fallback message, whose subtitle names the place, so {place} becomes "the place named above".

    Args:
        description (str): The description, maybe with {place}.

    Returns:
        str: The description for the event feed message.
    """
    if description.startswith("{place}"):
        description = "The place named above" + description[len("{place}"):]
    return description.replace("{place}", "the place named above")


def result_icon(result: str) -> str:
    """Picks the icon of a result's effect line: its offer's or mission's icon, or the treasury or wound icon.

    Args:
        result (str): The result name, e.g. "roll_the_bones_won" or "mission_headhunt_failed".

    Returns:
        str: The icon file under the effect bundle icons.
    """
    if result.startswith("wound_paid_"):
        return "chaos_gifts.png"
    if result == "missions_untracked":
        return "treasury.png"
    key = re.sub(r"^mission_|_(won|lost|blessed|cursed|met|failed)$", "", result)
    return ICONS[key]


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


def owned(line: str) -> bool:
    """True when a row belongs to this script, so a run replaces it.

    Args:
        line (str): The row.

    Returns:
        bool: True for spot offer rows, including the FIRST choice rows on site dilemmas.
    """
    key = line.split("\t", 1)[0]
    names = list(NOTICES) + list(MISSION_OBJECTIVES)
    notice = key.startswith(NOTICE_PREFIX) and key[len(NOTICE_PREFIX):].replace("_message", "") in names
    loc_notice = key.startswith("scripted_objectives_localised_") and any(key.endswith(NOTICE_PREFIX + n + s) for n in names for s in ("", "_message"))
    return any(marker in line for marker in OWNED_MARKERS) or line.startswith("70181") or notice or loc_notice


def write_rows(rows: Dict[str, List[str]], dry_run: bool) -> None:
    """Replaces this script's rows in each file, keeping every other row and the file's header as they are.

    Args:
        rows (Dict[str, List[str]]): File path -> rows from `build_rows`.
        dry_run (bool): True to only print what would change.
    """
    for path, new_rows in sorted(rows.items()):
        full = MOD_ROOT + path
        if not os.path.exists(full):
            name = path.split("/")[-1].replace(".tsv", "")
            open(full, "wb").write(f"key\ttext\ttooltip\r\n#Loc;1;text/db/{name}\t\t\r\n".encode("utf-8"))
        lines = open(full, "rb").read().decode("utf-8").splitlines(keepends=True)
        kept = lines[:2] + [line for line in lines[2:] if not owned(line)]
        if kept and not kept[-1].endswith("\n"):
            kept[-1] += "\r\n"
        print(f"{path}: -{len(lines) - len(kept)} +{len(new_rows)}")
        if not dry_run:
            with open(full, "wb") as f:
                f.write(("".join(kept) + "".join(row + "\r\n" for row in new_rows)).encode("utf-8"))


def check_text(config: Dict) -> None:
    """Stops when an offer or site has no text or icon, a paid offer has no not-enough-gold line, or any text writes gold with a separator.

    Args:
        config (Dict): The loaded config.

    Raises:
        SystemExit: Naming every problem found.
    """
    problems = [f"no text for {o['key']}" for o in config["offers"] if o["key"] not in OFFERS]
    problems += [f"no text for site {s['key']}" for s in config["sites"] + [config["spoils"]] if s["key"] not in SITES]
    problems += [f"no icon for {key}" for key in OFFERS if key not in ICONS]
    problems += [f"no notice for {o['key']}" for o in config["offers"]
                 if o["pool"] == "pre_battle" and "battle_bundle" not in o and "gamble" not in o and "trick" not in o and o["key"] not in NOTICES
                 and o["key"] not in TOWER_NOTICES]
    problems += [f"no messages for mission {o['key']}" for o in config["offers"] if o["pool"] == "mission" and o["key"] not in MISSION_MESSAGES]
    problems += [f"no result for line {key}" for key in RESULT_LINES if key not in MESSAGES and not key.startswith("mission")]
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
    write_rows(build_rows(config), args.dry_run)
    hook_battle_descriptions(config, args.dry_run)


if __name__ == "__main__":
    main()
