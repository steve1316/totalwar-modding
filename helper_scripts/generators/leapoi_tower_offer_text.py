"""Text for the LEAPOI tower offers whose numbers differ by difficulty, and for the battle bundles and notices the tower shares with the spot
battle offers. `update_leapoi_spot_offers` writes one line, bundle or notice per difficulty from it. Offers with one set of numbers keep
their hand-written rows.

A line or notice may use {cost} and any other number on the offer at that difficulty under its own name (e.g. {fewer_units}, {per_turn}),
plus the derived {heal}, {stronger}, {weaker}, {strength}, {tiers}, {ranks}, {targets}, {armies} and {e0}, {e1}... for the effects of the
bundle it gives.
"""

from typing import Dict, Tuple

from generators import leapoi_army_spells as army_spells
from generators import leapoi_boons as boons
from generators import leapoi_effect_library as library

# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Text helpers

# Start of a paid tower offer's line.
PAY = "Pay [[col:yellow]]{cost} gold[[/col]] from the haul to "

# Start of a mission's line.
MISSION = "[[col:yellow]]Mission:[[/col]] "

# Said on its own line under a bundle whose effect lists units, which the game draws from the viewer's own roster rather than the army's. Loc
# files store a line break as an escaped `\\n`, as SITE_FOOTER does.
DISCLAIMER = "\\\\n\\\\nThe units listed below come from your own roster, but only this army's riders are affected."

# Icon of every army spell's bundle and battle notice.
SPELL_ICON = "magic_character.png"


def broke(why: str, climbs: bool = True) -> str:
    """Builds the line of an offer the haul cannot pay.

    Args:
        why (str): What does not happen, e.g. "no rites are held".
        climbs (bool): False for a stay offer, whose line does not say the army climbs on.

    Returns:
        str: The line.
    """
    return "[[col:red]]The haul holds less than {cost} gold[[/col]], so " + why + "." + (" The army climbs as it is." if climbs else "")


def spell(name: str) -> Tuple[str, str, int]:
    """The bundle effect that grants one of the library's army spells.

    Args:
        name (str): The ARMY_SPELLS name, e.g. "banishment".

    Returns:
        Tuple[str, str, int]: (effect, scope, value).
    """
    return (library.effect_key(name + "_army_ability"), "force_to_force_own", 1)


def icon(name: str) -> str:
    """Writes a stat icon for loc text.

    Args:
        name (str): The icon file name without its extension, e.g. "icon_stat_attack".

    Returns:
        str: The image tag.
    """
    return f"[[img:ui/skins/default/{name}.png]][[/img]]"


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Tower offer lines

# Offer key -> (line, line when the haul cannot pay or None for a free offer).
TOWER_LINES: Dict[str, Tuple[str, str]] = {
    "tend_wounded": (PAY + "tend the wounded: heal [[col:green]]{heal}%[[/col]] of each unit's losses.", broke("no one is tended")),
    "rest_by_the_fire": ("Rest by the fire: heal [[col:green]]25%[[/col]] of each unit's losses, but the tower regroups and the next army is "
                         "[[col:red]]{stronger}% stronger[[/col]].", None),
    "war_rites": (PAY + "hold war rites: [[col:green]]+{e0}[[/col]] " + icon("icon_stat_attack") + " melee attack, " + icon("icon_stat_defence")
                  + " melee defence and " + icon("icon_stat_morale") + " leadership in the next battle.", broke("no rites are held")),
    "whetstones_and_oil": (PAY + "hone every blade: [[col:green]]+{e0}%[[/col]] " + icon("icon_stat_damage") + " weapon strength and [[col:green]]+{e1}[[/col]] "
                           + icon("modifier_icon_armour_piercing") + " armour-piercing damage in the next battle.", broke("the blades stay dull")),
    "warding_sigils": ("Paint the sigils in our own blood: [[col:green]]+{e0}% ward save[[/col]] in the next battle, but every unit loses "
                       "[[col:red]]{bleed}% of its strength[[/col]] now.", None),
    "enchanted_steel": (PAY + "enchant our steel: [[col:green]]magical attacks[[/col]] for every unit in the next battle.", broke("the steel stays plain")),
    "quartermasters_cache": (PAY + "raid the quartermaster's cache: [[col:green]]+{e0}%[[/col]] " + icon("icon_stat_ammo") + " ammunition and [[col:green]]{e1}%[[/col]] "
                             + icon("icon_stat_reload_time") + " faster reloads for the [[col:green]]next {battle_floors} floors[[/col]].", broke("the cache stays shut")),
    "drill_sergeant": ("Drive the army through hard drills: [[col:green]]+{e0}%[[/col]] " + icon("icon_stat_speed") + " speed and [[col:green]]+{e1}[[/col]] "
                       + icon("icon_stat_charge_bonus") + " charge bonus in the next battle, but the army [[col:red]]starts that battle Winded[[/col]].", None),
    "blinding_powder": (PAY + "pack blinding powder into every pouch: our attacks [[col:green]]blind what they hit[[/col]] in the next battle.",
                        broke("the powder stays in its sacks")),
    "hold_the_stair": (PAY + "fortify the stairwell: [[col:green]]Regeneration and Unbreakable when defending[[/col]] in the next battle.",
                       broke("the stair stays open")),
    "berserker_brew": ("Drink the berserker brew: every unit gains [[col:green]]Frenzy[[/col]] in the next battle, but the next army is "
                       "[[col:red]]{stronger}% stronger[[/col]].", None),
    "shadow_cloaks": (PAY + "hand out shadow cloaks: every unit gains [[col:green]]Stalk and Vanguard Deployment[[/col]] in the next battle.",
                      broke("the cloaks stay folded")),
    "tireless_tonic": ("Drink the tireless tonic: the army [[col:green]]never tires[[/col]] in the next battle, but our lord is struck by "
                       + boons.grant_text("curse", ["weary_ranks", 1]) + ".", None),
    "scroll_of_banishment": (PAY + "unroll a scroll of banishment: army spell [[col:green]]Banishment, 1 use[[/col]], in the next battle.",
                             broke("the scroll stays sealed")),
    "net_of_amyntok": (PAY + "take the Net of Amyntok: army spell [[col:green]]Net of Amyntok, 3 uses[[/col]], in the next battle.",
                       broke("the net stays in its case")),
    "earthblood": (PAY + "drink from the tower's roots: army spell [[col:green]]Earthblood, 2 uses[[/col]], in the next battle.",
                   broke("the roots stay dry")),
    "curse_of_years": ("Read from the Book of Years: army spell [[col:green]]Curse of Years, 2 uses[[/col]], in the next battle, but our lord is struck by "
                       + boons.grant_text("curse", ["shunned_by_the_winds", 1]) + ".", None),
    "the_dwellers_below": ("Wake what sleeps beneath the tower: army spell [[col:green]]The Dwellers Below, 1 use[[/col]], in the next battle, but our lord "
                           "is [[col:red]]wounded for {wound_turns} turns[[/col]] when the delve ends.", None),
    "falling_star": ("Call down a star: army spell [[col:green]]Comet of Casandora, 1 use[[/col]], in the next battle, but every unit loses "
                     "[[col:red]]{bleed}% of its strength[[/col]] in the blast now.", None),
    "grand_scroll": (PAY + "read a grand scroll: the lore spell below is ours to cast in the next battle.", broke("the scroll stays rolled")),
    "bound_relic": (PAY + "take up a bound relic: the spell below is ours to cast in the next battle.", broke("the relic stays on its plinth")),
    "war_horn": (PAY + "sound an old war horn: the army ability below is ours to use in the next battle.", broke("the horn stays silent")),
    "iron_resolve": (PAY + "steel our resolve: [[col:green]]+{e0}[[/col]] " + icon("icon_stat_morale") + " leadership and [[col:green]]immunity to fear and terror[[/col]] "
                     "in the next battle.", broke("our resolve goes unsteeled")),
    "stoneskin": ("Cast a ward of living stone: [[col:green]]+{e0}% physical resistance[[/col]] in the next battle, but the tower notices and the next "
                  "army is [[col:red]]{stronger}% stronger[[/col]].", None),
    "call_the_winds": (PAY + "call the winds: [[col:green]]+{e0} Winds of Magic[[/col]] reserve in the next battle.", broke("the winds stay still")),
    "bottomless_quivers": (PAY + "fill bottomless quivers: our missile units [[col:green]]never run out of ammunition[[/col]] in the next battle.",
                           broke("the quivers can still run dry")),
    "oath_of_no_retreat": (PAY + "swear an oath of no retreat: our units [[col:green]]cannot rout[[/col]] in the next battle.", broke("the oath goes unsworn")),
    "sacred_ground": (PAY + "bless the next floor's ground: after 3 minutes of the battle, our units regain [[col:green]]{battle_value}%[[/col]] of their "
                      "strength.", broke("the ground stays unblessed")),
    "divine_shield": (PAY + "raise a divine shield: our lord [[col:green]]cannot be harmed for the first {minutes} minutes[[/col]] of the next battle.",
                      broke("no shield is raised")),
    "night_terrors": (PAY + "send night terrors: the enemy's [[col:green]]{targets}[[/col]] after 1 minute of the next battle.", broke("the enemy sleeps soundly")),
    "bribe_the_guards": (PAY + "bribe the guards: the next army is [[col:green]]{weaker}% weaker[[/col]].", broke("the guards stay loyal")),
    "poison_the_stores": (PAY + "poison the next floor's stores: its units start at [[col:green]]{strength}% strength[[/col]].", broke("the stores stay clean")),
    "thin_the_ranks": (PAY + "thin the next floor's ranks: its army fields [[col:green]]{fewer_units} fewer units[[/col]].", broke("the ranks stay full")),
    "allies_in_the_dark_small": (PAY + "call allies from the dark: [[col:green]]a small allied army[[/col]] of {ally_min} to {ally_max} units joins us in "
                                 "the next battle.", broke("no allies answer")),
    "allies_in_the_dark_medium": (PAY + "call allies from the dark: [[col:green]]a medium allied army[[/col]] of {ally_min} to {ally_max} units joins us "
                                  "in the next battle.", broke("no allies answer")),
    "allies_in_the_dark_large": (PAY + "call allies from the dark: [[col:green]]a large allied army[[/col]] of {ally_min} to {ally_max} units joins us in "
                                 "the next battle.", broke("no allies answer")),
    "lower_tiers_only": (PAY + "keep the next floor's veterans away: its army has [[col:green]]tier 1-2 units only[[/col]].", broke("the veterans stand ready")),
    "strip_monsters": (PAY + "cull the next floor's beasts: its army fields [[col:green]]no monsters or war beasts[[/col]].", broke("the beasts stay hungry")),
    "strip_cavalry": (PAY + "scatter the next floor's riders: its army fields [[col:green]]no cavalry or chariots[[/col]].", broke("the herds stay penned")),
    "strip_missile": (PAY + "burn the next floor's quivers: its army fields [[col:green]]no missile infantry[[/col]].", broke("the quivers stay full")),
    "strip_artillery": (PAY + "wreck the next floor's war engines: its army fields [[col:green]]no artillery[[/col]].", broke("the engines stay whole")),
    "break_their_spirit": (PAY + "spread dread through the next floor: its units have [[col:green]]-{e0}[[/col]] " + icon("icon_stat_morale") + " leadership.",
                           broke("their spirit holds")),
    "curse_their_blades": (PAY + "curse the next floor's weapons: its units have [[col:green]]-{e0}[[/col]] " + icon("icon_stat_attack") + " melee attack.",
                           broke("their blades stay sharp")),
    "assassinate": (PAY + "send an assassin up the stairs: the next floor's [[col:green]]lord is slain as the battle starts[[/col]].", broke("no assassin climbs the stairs")),
    "cripple_their_champion": (PAY + "cripple the next floor's champion: its [[col:green]]most expensive unit[[/col]] starts at [[col:green]]{champion}% strength[[/col]].",
                               broke("their champion stands ready")),
    "spike_the_guns": (PAY + "spoil the next floor's arrows and powder: its shooters have [[col:green]]-{e0}%[[/col]] " + icon("icon_stat_ammo") + " ammunition.",
                       broke("their shot stays dry")),
    "bait_and_switch": (PAY + "lure the next floor into a false muster: its army is [[col:red]]{stronger}% bigger[[/col]], but each of its units starts at "
                        "[[col:green]]{strength}% strength[[/col]].", broke("no bait is laid")),
    "last_ditch_oath": ("Swear a last-ditch oath: our lord [[col:green]]cannot die[[/col]] in the next battle, but our army has [[col:red]]-{e0}[[/col]] "
                        + icon("icon_stat_morale") + " leadership.", None),
    "lame_their_mounts": (PAY + "lame the next floor's mounts: its cavalry and chariots have [[col:green]]-{e0}%[[/col]] " + icon("icon_stat_speed") + " speed.",
                          broke("their mounts run free")),
    "hunters_snares": (PAY + "lay snares for the next floor's riders: its cavalry and chariots have [[col:green]]-{e0}[[/col]] " + icon("icon_stat_charge_bonus")
                       + " charge bonus.", broke("no snares are laid")),
    "turn_a_traitor": (PAY + "turn a traitor: [[col:green]]a tier {tiers} unit[[/col]] of the next floor's army joins ours now, and that army fields one unit fewer.",
                       broke("no one turns")),
    "tower_dividends": (PAY + "buy a share of the tower's vaults: [[col:green]]+{per_turn} gold[[/col]] to our treasury each turn for {turns} turns, kept even if the "
                        "delve is lost.", broke("no share is bought", climbs=False)),
    "cursed_idol": ("Take the idol: [[col:green]]+{gold} gold[[/col]] in the haul now, but the next army is [[col:red]]15% stronger[[/col]].", None),
    "conscripts": (PAY + "press conscripts into service: [[col:green]]2 tier 1-2 units[[/col]] of our own kind join our army now.", broke("no one is pressed")),
    "captured_war_machine": (PAY + "salvage a war machine from the tower's armoury: [[col:green]]a tier {tiers} war machine[[/col]] joins our army now.",
                             broke("the war machine stays in the tower")),
    "regiment_of_renown": (PAY + "hire a [[col:green]]Regiment of Renown[[/col]] of our own kind: it joins our army now.", broke("the regiment moves on")),
    "veterans_oath": (PAY + "swear the veterans' oath: [[col:green]]3 units[[/col]] gain [[col:green]]{ranks}[[/col]] each.", broke("no oath is sworn")),
    "lessons_in_blood": (PAY + "study the fallen: our lord gains [[col:green]]+{lord_xp} experience[[/col]].", broke("the lesson goes unlearned")),
    "freed_prisoner": (PAY + "free a prisoner from the tower's cells: [[col:green]]a rank {rank} hero[[/col]] joins our army.", broke("the cells stay locked")),
    "towers_favour": ("Win the tower's favour: [[col:green]]+{e0}% income[[/col]] from all buildings for {turns} turns, but [[col:red]]-{relations} relations[[/col]] with the "
                      "nearest faction of the tower's race.", None),
    "research_scrolls": (PAY + "take the tower's research scrolls: [[col:green]]+25% research rate[[/col]] for {turns} turns.", broke("the scrolls stay on the shelf", climbs=False)),
    "recruitment_cache": ("Open a recruitment cache: [[col:green]]-{e0}% recruitment cost[[/col]] for {turns} turns, but [[col:red]]-{e1} public order[[/col]] in "
                          "every province for those turns.", None),
    "exhaust_the_garrison": (PAY + "keep the next floor's garrison awake all night: its army [[col:green]]starts the battle Tired[[/col]].",
                             broke("the garrison sleeps soundly")),
    "foul_the_winds": (PAY + "foul the winds around the next floor: its army pays [[col:green]]+{e0}% Winds of Magic[[/col]] for every spell.",
                       broke("the winds stay clean")),
    "smoke_the_halls": (PAY + "fill the next floor's halls with smoke: its missile units have [[col:green]]-{e0}% range[[/col]].", broke("the halls stay clear")),
    "blood_contract": ("Sign a contract in blood: the next floor's [[col:green]]lord is slain as the battle starts[[/col]], but our lord is struck by "
                       + boons.grant_text("curse", ["marked_prey", 1]) + ".", None),
    "collapse_the_stair": ("Bring the stairwell down on the floor above: its army is [[col:green]]{weaker}% weaker[[/col]], but every unit of ours loses "
                           "[[col:red]]{bleed}% of its strength[[/col]] in the rubble now.", None),
    "press_the_prisoners": ("Press the tower's prisoners into service: [[col:green]]{count} tier {tiers} units[[/col]] of the tower's race join our army now, "
                            "but [[col:red]]-{relations} relations[[/col]] with the nearest faction of that race.", None),
    "loot_the_reliquary": ("Loot the tower's reliquary: [[col:green]]a rare item[[/col]] joins the haul, but [[col:red]]+{e0} Chaos corruption[[/col]] in every "
                           "province for {turns} turns.", None),
    "blood_for_glory": ("Throw our lord into the bloodiest fighting: our lord gains [[col:green]]+{lord_xp} experience[[/col]], but our army suffers "
                        "[[col:red]]attrition for {turns} turns[[/col]].", None),
    "plague_bearer": ("Carry the tower's plague out: [[col:green]]+{gold} gold[[/col]] in the haul, but our army suffers [[col:red]]attrition for {turns} turns[[/col]].", None),
    "daemons_deal": ("Deal with a daemon: [[col:green]]{items} unique items[[/col]] join the haul now, but [[col:red]]when the delve ends, {armies} on our capital[[/col]].",
                     None),
    "lords_glory": (MISSION + "our lord kills [[col:yellow]]{battle_value} soldiers[[/col]] on the next floor for [[col:green]]a random rare item[[/col]] in the haul.",
                    None),
    "spare_the_captain": (MISSION + "win with the [[col:yellow]]enemy lord still alive[[/col]], and ransom them for [[col:green]]+{gold} gold[[/col]] in the haul.", None),
}

# Offer key -> its line's icon, for the lines above whose spot offer of the same key has no icon or another one.
TOWER_ICONS = {
    "tend_wounded": "replenishment.png", "rest_by_the_fire": "icon_effects_fortify.png", "stoneskin": "resistance_physical.png",
    "cursed_idol": "resource_gold_idols_large.png", "captured_war_machine": "artillery.png", "veterans_oath": "experience.png",
    "lessons_in_blood": "general_ability.png", "freed_prisoner": "noble.png", "towers_favour": "income.png",
    "blinding_powder": "wh_dlc06_unit_contact_blinded.png", "hold_the_stair": "icon_effects_fortify.png", "berserker_brew": "rampage_savage.png",
    "shadow_cloaks": "stalk.png", "tireless_tonic": "replenishment.png", "scroll_of_banishment": "magic.png", "net_of_amyntok": "magic.png",
    "earthblood": "magic.png", "curse_of_years": "magic.png", "the_dwellers_below": "magic.png", "falling_star": "magic.png",
    "grand_scroll": "magic.png", "bound_relic": "magic.png", "war_horn": "magic.png",
    "blood_sigils": "resistance_ward_save.png", "hard_drills": "charge.png", "hold_the_ground": "siege_defence.png", "spell_banishment": SPELL_ICON,
    "spell_net_of_amyntok": SPELL_ICON, "spell_earthblood": SPELL_ICON, "spell_curse_of_years": SPELL_ICON, "spell_dwellers_below": SPELL_ICON,
    "spell_falling_star": SPELL_ICON,
    "exhaust_the_garrison": "attrition.png", "foul_the_winds": "magic.png", "smoke_the_halls": "hex_1.png", "blood_contract": "dlc10_assassination_targets.png",
    "collapse_the_stair": "siege_attack.png", "press_the_prisoners": "peasant.png", "loot_the_reliquary": "corruption_tzeentch.png",
    "blood_for_glory": "general_ability.png",
}


# Choice names of the tower offers added by the roguelite content pass, whose choice rows the generator writes. Every older tower choice is a
# hand row, apart from the offers granting boons and curses.
TOWER_NAMES: Dict[str, str] = {
    "blinding_powder": "Blinding Powder", "hold_the_stair": "Hold the Stair", "berserker_brew": "Berserker Brew", "shadow_cloaks": "Shadow Cloaks",
    "tireless_tonic": "Tireless Tonic", "scroll_of_banishment": "Scroll of Banishment", "net_of_amyntok": "Net of Amyntok", "earthblood": "Earthblood",
    "curse_of_years": "Curse of Years", "the_dwellers_below": "The Dwellers Below", "falling_star": "Call Down a Star",
    "grand_scroll": "Grand Scroll", "bound_relic": "Bound Relic", "war_horn": "War Horn",
    "exhaust_the_garrison": "Exhaust the Garrison", "foul_the_winds": "Foul the Winds", "smoke_the_halls": "Smoke the Halls", "blood_contract": "Blood Contract",
    "collapse_the_stair": "Collapse the Stair", "press_the_prisoners": "Press the Prisoners", "loot_the_reliquary": "Loot the Reliquary",
    "blood_for_glory": "Blood for Glory",
}

# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Battle bundles and notices

# Effects of the bundles that make the army hold its ground: Hold the Stair on a tower floor, Hold the Ground at a battle spot.
HOLD_EFFECTS = [(library.effect_key("regeneration_defending"), "force_to_force_own", 1), (library.effect_key("unbreakable_defending"), "force_to_force_own", 1)]

# Tiered tower bundle name after `land_enc_effect_tower_` -> (target, icon, title, description, [(effect, scope, (easy, medium, hard) or value)],
# notice or None). A notice (colour, text) names the battle notice of a bundle on our army. A bundle on the enemy is announced by its
# offer's notice in `NOTICES` instead.
TOWER_BUNDLES = {
    "war_rites": ("force", "effect_rite.png", "War Rites", "The army held its war rites before the battle. The fervour lasts for that battle only.",
                  [("wh_main_effect_force_stat_melee_attack", "force_to_force_own", (5, 10, 15)),
                   ("wh_main_effect_force_stat_melee_defence", "force_to_force_own", (5, 10, 15)),
                   ("wh_main_effect_force_stat_leadership", "force_to_force_own", (5, 10, 15))],
                  ("green", "War Rites: +{e0} " + icon("icon_stat_attack") + icon("icon_stat_defence") + icon("icon_stat_morale") + ".")),
    "whetstones_and_oil": ("force", "chd_armaments.png", "Whetstones and Oil", "Every blade in the army is honed and oiled for one battle.",
                           [("wh_main_effect_force_stat_weapon_strength", "force_to_force_own", (5, 10, 15)),
                            ("wh_main_effect_force_stat_ap_damage", "force_to_force_own", (5, 10, 15))],
                           ("green", "Whetstones and Oil: +{e0}% " + icon("icon_stat_damage") + " and +{e1} " + icon("modifier_icon_armour_piercing") + ".")),
    "quartermasters_cache": ("force", "increase_projectiles.png", "Quartermaster's Cache", "A cache of spare shot and arrows tops up every pouch and quiver for the next battle.",
                             [("wh_main_effect_force_stat_ammunition", "force_to_force_own", (25, 50, 75)),
                              ("wh_main_effect_force_stat_reload_time_reduction", "force_to_force_own", (15, 25, 35))],
                             ("green", "Quartermaster's Cache: +{e0}% " + icon("icon_stat_ammo") + " and {e1}% faster " + icon("icon_stat_reload_time") + ".")),
    "iron_resolve": ("force", "attribute_immune_to_psychology.png", "Iron Resolve", "The army swore to hold whatever comes. Nothing frightens it for one battle.",
                     [("wh_main_effect_force_stat_leadership", "force_to_force_own", (10, 20, 30)),
                      ("wh_main_effect_attribute_enable_immune_to_psychology", "force_to_force_own", 1)],
                     ("green", "Iron Resolve: +{e0} " + icon("icon_stat_morale") + ", immune to fear and terror.")),
    "stoneskin": ("force", "resistance_physical.png", "Stoneskin", "A ward of living stone hardens the army's hide for one battle.",
                  [("wh_main_effect_force_stat_physical_resistance", "force_to_force_own", (10, 15, 20))], ("green", "Stoneskin: +{e0}% physical resistance.")),
    "blood_sigils": ("force", "resistance_ward_save.png", "Blood Sigils", "Sigils painted in our own blood turn blows aside for one battle.",
                     [("wh_main_effect_force_stat_ward_save", "force_to_force_own", (10, 15, 20))], ("green", "Blood Sigils: +{e0}% ward save.")),
    "hard_drills": ("force", "battle_movement_character.png", "Hard Drills", "A brutal morning of drill has the army moving and charging faster, but already winded, for one battle.",
                    [("wh_main_effect_force_stat_speed", "force_to_force_own", (10, 15, 20)),
                     ("wh2_dlc14_effect_force_charge_bonus_add", "force_to_force_own", (10, 15, 20)),
                     ("wh_main_effect_force_campaign_stance_begin_fatigued_3_winded", "force_to_force_own", 3)],
                    ("yellow", "Hard Drills: +{e0}% " + icon("icon_stat_speed") + " and +{e1} " + icon("icon_stat_charge_bonus") + ", but our army starts Winded.")),
    "blinding_powder": ("force", "wh_dlc06_unit_contact_blinded.png", "Blinding Powder", "Every pouch is packed with blinding powder for one battle.",
                        [(library.effect_key("blinded_hits"), "force_to_force_own", 1)], ("green", "Blinding Powder: our attacks blind what they hit.")),
    "hold_the_stair": ("force", "siege_defence.png", "Hold the Stair", "The stairwell is fortified. The army will not give ground for one battle.",
                       HOLD_EFFECTS,
                       ("green", "Hold the Stair: Regeneration and Unbreakable when defending.")),
    "hold_the_ground": ("force", "siege_defence.png", "Hold the Ground", "The army has dug in. It will not give ground for one battle.",
                        HOLD_EFFECTS,
                        ("green", "Hold the Ground: Regeneration and Unbreakable when defending.")),
    "berserker_brew": ("force", "icon_flask.png", "Berserker Brew", "The brew burns in every throat. The army fights in a frenzy for one battle.",
                       [("wh3_dlc27_effect_ability_enable_frenzy_all", "force_to_force_own", 1)], ("green", "Berserker Brew: every unit is Frenzied.")),
    "shadow_cloaks": ("force", "concealment.png", "Shadow Cloaks", "Cloaks of shadow hide the army as it takes the field for one battle.",
                      [("wh_main_effect_attribute_enable_stalk", "force_to_force_own", 1), ("wh_main_effect_attribute_enable_vanguard_deployment", "force_to_force_own", 1)],
                      ("green", "Shadow Cloaks: Stalk and Vanguard Deployment.")),
    "tireless_tonic": ("force", "attribute_fatigue_immune.png", "Tireless Tonic", "The tonic keeps every warrior fresh for one battle.",
                       [("wh2_dlc10_effect_attribute_enable_perfect_vigour", "force_to_force_own", 1)], ("green", "Tireless Tonic: our army never tires.")),
    "spell_banishment": ("force", SPELL_ICON, "Scroll of Banishment", "A scroll of banishment, ready to be read in the next battle.",
                         [spell("banishment")], ("green", "We gain +1 charge of Banishment.")),
    "spell_net_of_amyntok": ("force", SPELL_ICON, "Net of Amyntok", "The Net of Amyntok, ready to be cast in the next battle.",
                             [spell("net_of_amyntok")], ("green", "We gain +3 charges of Net of Amyntok.")),
    "spell_earthblood": ("force", SPELL_ICON, "Earthblood", "The tower's roots lend their strength for the next battle.",
                         [spell("earthblood")], ("green", "We gain +2 charges of Earthblood.")),
    "spell_curse_of_years": ("force", SPELL_ICON, "Curse of Years", "A page from the Book of Years, ready to be read in the next battle.",
                             [spell("curse_of_years")], ("green", "We gain +2 charges of Curse of Years.")),
    "spell_dwellers_below": ("force", SPELL_ICON, "The Dwellers Below", "Something beneath the tower answers our call in the next battle.",
                             [spell("dwellers_below")], ("green", "We gain +1 charge of The Dwellers Below.")),
    "spell_falling_star": ("force", SPELL_ICON, "Call Down a Star", "A star waits to fall at our word in the next battle.",
                           [spell("comet")], ("green", "We gain +1 charge of Comet of Casandora.")),
    "call_the_winds": ("force", "magic_campaign.png", "Call the Winds", "The Winds of Magic gather close for one battle.",
                       [("wh3_main_effect_winds_of_magic_pool_min", "force_to_force_own", (20, 30, 40)),
                        ("wh3_main_effect_winds_of_magic_pool_cap", "force_to_force_own", (20, 30, 40))],
                       ("green", "Call the Winds: +{e0} Winds of Magic in reserve.")),
    "break_their_spirit": ("force", "discouraged.png", "Broken Spirit", "Word of what waits has spread through the ranks. This army fights afraid.",
                           [("wh_main_effect_force_stat_leadership", "force_to_force_own", (-10, -15, -20))], None),
    "curse_their_blades": ("force", "melee.png", "Cursed Blades", "A curse dulls every blade in this army.",
                           [("wh_main_effect_force_stat_melee_attack", "force_to_force_own", (-10, -15, -20))], None),
    "spike_the_guns": ("force", "ammo.png", "Spoiled Ammunition", "Spoiled powder and arrows leave this army short of shot.",
                       [("wh_main_effect_force_stat_ammunition", "force_to_force_own", (-30, -40, -50))], None),
    "last_ditch_oath": ("force", "grudges.png", "Last-Ditch Oath", "Our lord swore to stand to the last, and the army knows what it may cost.",
                        [("wh_main_effect_force_stat_leadership", "force_to_force_own", -10)],
                        ("yellow", "Last-Ditch Oath: our lord cannot die, but our army has -{e0} " + icon("icon_stat_morale") + ".")),
    # Vanilla effects on the cavalry_chariots unit set, which takes every rider by type, modded ones too. The game fills an effect's unit list
    # from the viewer's own roster, so the description says so. Effects on unit classes leave no list but never apply.
    "lame_their_mounts": ("force", "battle_movement.png", "Lamed Mounts", "Caltrops and cut girths slow this army's cavalry and chariots in battle."
                          + DISCLAIMER, [("wh3_dlc27_effect_force_stat_speed_cavalry_chariots", "force_to_force_own", (-15, -20, -25))], None),
    "hunters_snares": ("force", "charge.png", "Snared Charges", "Snares and pits lie in wait for this army's cavalry and chariots." + DISCLAIMER,
                       [("wh3_dlc27_effect_force_stat_charge_bonus_cavalry_chariots_add", "force_to_force_own", (-15, -20, -25))], None),
    "towers_favour": ("faction", "income.png", "Tower's Favour", "The tower's masters speak well of us. Trade flows a little easier.",
                      [("wh_main_effect_economy_gdp_mod_all", "faction_to_region_own", (5, 10, 15))], None),
    "recruitment_cache": ("faction", "income.png", "Recruitment Cache", "The tower's armoury equips our recruits cheaply, and the provinces resent the levies.",
                          [("wh_main_effect_force_all_campaign_recruitment_cost_all", "faction_to_force_own", -20),
                           ("wh_main_effect_public_order_faction", "faction_to_province_own", -10)], None),
    "reliquary_corruption": ("faction", "corruption_tzeentch.png", "Looted Reliquary", "Whatever was sealed in the tower's reliquary is loose in our lands now.",
                             [("wh3_main_effect_corruption_chaos_events_bad", "faction_to_province_own", 5)], None),
    "exhausted_garrison": ("force", "vigour.png", "Exhausted Garrison", "This army spent the night awake and starts the battle tired.",
                           [("wh_main_effect_force_campaign_stance_begin_fatigued_4_tired", "force_to_force_own", 4)], None),
    "fouled_winds": ("force", "magic.png", "Fouled Winds", "The winds around this army are fouled. Every spell costs more.",
                     [("wh2_dlc14_effect_magic_cost_all_lores_percentage", "force_to_force_own", 50)], None),
    "smoked_halls": ("force", "accuracy.png", "Smoke-Filled Halls", "Smoke fills the halls. This army's shooters cannot see far.",
                     [("wh_main_effect_force_stat_range", "force_to_force_own", -30)], None),
}

# One bundle per army spell (generators/leapoi_army_spells.py), for the battle it is cast in, with its battle notice.
for _spell in army_spells.spells():
    TOWER_ICONS[army_spells.BUNDLE_NAME + _spell["id"]] = SPELL_ICON
    TOWER_BUNDLES[army_spells.BUNDLE_NAME + _spell["id"]] = (
        "force", SPELL_ICON, _spell["name"], army_spells.description(_spell),
        [spell(_spell["id"])], ("green", army_spells.charges_text(_spell)))

# Offer key -> (colour, text) of the notice of a shared sabotage or trick whose effect differs by difficulty. Red weakens the enemy, green
# helps us, yellow costs us. The numbers come from the tower offer at each difficulty.
NOTICES = {
    "bribe_the_guards": ("red", "Bribe the Guards: the enemy army is {weaker}% weaker."),
    "thin_the_ranks": ("red", "Thin the Ranks: the enemy fields {fewer_units} fewer units."),
    "strip_monsters": ("red", "Cull the Beasts: the enemy fields no monsters or war beasts."),
    "strip_cavalry": ("red", "Scatter the Herds: the enemy fields no cavalry or chariots."),
    "strip_missile": ("red", "Burn the Quivers: the enemy fields no missile infantry."),
    "strip_artillery": ("red", "Wreck the Engines: the enemy fields no artillery."),
    "poison_the_stores": ("red", "Poison the Stores: enemy units start at {strength}% strength."),
    "break_their_spirit": ("red", "Break Their Spirit: enemy units have -{e0} " + icon("icon_stat_morale") + "."),
    "curse_their_blades": ("red", "Curse Their Blades: enemy units have -{e0} " + icon("icon_stat_attack") + "."),
    "turn_a_traitor": ("green", "Turn a Traitor: one of the enemy's units fights for us."),
    "night_terrors": ("green", "Night Terrors: the enemy's {targets} after 1 minute."),
    "divine_shield": ("green", "Divine Shield: our lord cannot be harmed for the first {minutes} minutes."),
    "sacred_ground": ("green", "Sacred Ground: after 3 minutes, our units regain {battle_value}% of their strength."),
    "lame_their_mounts": ("red", "Lame Their Mounts: enemy cavalry and chariots have -{e0}% " + icon("icon_stat_speed") + "."),
    "hunters_snares": ("red", "Hunter's Snares: enemy cavalry and chariots have -{e0} " + icon("icon_stat_charge_bonus") + "."),
    "cripple_their_champion": ("red", "Cripple Their Champion: the enemy's finest unit starts at {champion}% strength."),
    "spike_the_guns": ("red", "Spike the Guns: enemy shooters have -{e0}% " + icon("icon_stat_ammo") + "."),
    "bait_and_switch": ("red", "Bait and Switch: the enemy army is {stronger}% bigger, but each of its units starts at {strength}% strength."),
    "exhaust_the_garrison": ("red", "Exhaust the Garrison: the enemy starts the battle Tired."),
    "foul_the_winds": ("red", "Foul the Winds: enemy spells cost {e0}% more Winds of Magic."),
    "smoke_the_halls": ("red", "Smoke the Halls: enemy missile units have -{e0}% range."),
    "blood_contract": ("red", "Blood Contract: the enemy lord is slain as the battle starts."),
}
