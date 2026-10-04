"""Text for the LEAPOI tower offers whose numbers differ by difficulty, and for the battle bundles and notices the tower shares with the spot
battle offers. `update_leapoi_spot_offers` writes one line, bundle or notice per difficulty from it. Offers with one set of numbers keep
their hand-written rows.

A line or notice may use {cost} and any other number on the offer at that difficulty under its own name (e.g. {fewer_units}, {per_turn}),
plus the derived {heal}, {stronger}, {weaker}, {strength}, {tiers}, {ranks}, {targets}, {armies} and {e0}, {e1}... for the effects of the
bundle it gives.
"""

from typing import Dict, Tuple

# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Text helpers

# Start of a paid tower offer's line.
PAY = "Pay [[col:yellow]]{cost} gold[[/col]] from the haul to "

# Start of a mission's line.
MISSION = "[[col:yellow]]Mission:[[/col]] "


def broke(why: str, climbs: bool = True) -> str:
    """Builds the line of an offer the haul cannot pay.

    Args:
        why (str): What does not happen, e.g. "no rites are held".
        climbs (bool): False for a stay offer, whose line does not say the army climbs on.

    Returns:
        str: The line.
    """
    return "[[col:red]]The haul holds less than {cost} gold[[/col]], so " + why + "." + (" The army climbs as it is." if climbs else "")


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
    "warding_sigils": (PAY + "paint warding sigils: [[col:green]]+{e0}% ward save[[/col]] in the next battle.", broke("no sigils are painted")),
    "enchanted_steel": (PAY + "enchant our steel: [[col:green]]magical attacks[[/col]] for every unit in the next battle.", broke("the steel stays plain")),
    "quartermasters_cache": (PAY + "raid the quartermaster's cache: [[col:green]]+{e0}%[[/col]] " + icon("icon_stat_ammo") + " ammunition and [[col:green]]{e1}%[[/col]] "
                             + icon("icon_stat_reload_time") + " faster reloads in the next battle.", broke("the cache stays shut")),
    "drill_sergeant": (PAY + "hire a drill sergeant: [[col:green]]+{e0}%[[/col]] " + icon("icon_stat_speed") + " speed and [[col:green]]+{e1}[[/col]] "
                       + icon("icon_stat_charge_bonus") + " charge bonus in the next battle.", broke("no drill is held")),
    "iron_resolve": (PAY + "steel our resolve: [[col:green]]+{e0}[[/col]] " + icon("icon_stat_morale") + " leadership and [[col:green]]immunity to fear and terror[[/col]] "
                     "in the next battle.", broke("our resolve goes unsteeled")),
    "stoneskin": (PAY + "cast a ward of living stone: [[col:green]]+{e0}% physical resistance[[/col]] in the next battle.", broke("no ward of stone is cast")),
    "call_the_winds": (PAY + "call the winds: [[col:green]]+{e0} Winds of Magic[[/col]] reserve in the next battle.", broke("the winds stay still")),
    "bottomless_quivers": (PAY + "fill bottomless quivers: our missile units [[col:green]]never run out of ammunition[[/col]] in the next battle.",
                           broke("the quivers can still run dry")),
    "oath_of_no_retreat": (PAY + "swear an oath of no retreat: our units [[col:green]]cannot rout[[/col]] in the next battle.", broke("the oath goes unsworn")),
    "divine_shield": (PAY + "raise a divine shield: our lord [[col:green]]cannot be harmed for the first {minutes} minutes[[/col]] of the next battle.",
                      broke("no shield is raised")),
    "night_terrors": (PAY + "send night terrors: the enemy's [[col:green]]{targets}[[/col]] after 1 minute of the next battle.", broke("the enemy sleeps soundly")),
    "bribe_the_guards": (PAY + "bribe the guards: the next army is [[col:green]]{weaker}% weaker[[/col]].", broke("the guards stay loyal")),
    "poison_the_stores": (PAY + "poison the next floor's stores: its units start at [[col:green]]{strength}% strength[[/col]].", broke("the stores stay clean")),
    "thin_the_ranks": (PAY + "thin the next floor's ranks: its army fields [[col:green]]{fewer_units} fewer units[[/col]].", broke("the ranks stay full")),
    "lower_tiers_only": (PAY + "keep the next floor's veterans away: its army has [[col:green]]tier 1-2 units only[[/col]].", broke("the veterans stand ready")),
    "break_their_spirit": (PAY + "spread dread through the next floor: its units have [[col:green]]-{e0}[[/col]] " + icon("icon_stat_morale") + " leadership.",
                           broke("their spirit holds")),
    "curse_their_blades": (PAY + "curse the next floor's weapons: its units have [[col:green]]-{e0}[[/col]] " + icon("icon_stat_attack") + " melee attack.",
                           broke("their blades stay sharp")),
    "assassinate": (PAY + "send an assassin up the stairs: the next floor's [[col:green]]lord is slain as the battle starts[[/col]].", broke("no assassin climbs the stairs")),
    "cripple_their_champion": (PAY + "cripple the next floor's champion: its [[col:green]]most expensive unit[[/col]] starts at [[col:green]]{champion}% strength[[/col]].",
                               broke("their champion stands ready")),
    "spike_the_guns": (PAY + "spike the next floor's guns: its shooters have [[col:green]]-{e0}%[[/col]] " + icon("icon_stat_ammo") + " ammunition.",
                       broke("their guns stay loaded")),
    "bait_and_switch": (PAY + "lure the next floor into a false muster: its army is [[col:red]]{stronger}% bigger[[/col]], but every unit starts at "
                        "[[col:green]]{strength}% strength[[/col]].", broke("no bait is laid")),
    "last_ditch_oath": ("Swear a last ditch oath: our lord [[col:green]]cannot die[[/col]] in the next battle, but our army has [[col:red]]-{e0}[[/col]] "
                        + icon("icon_stat_morale") + " leadership.", None),
    "turn_a_traitor": (PAY + "turn a traitor: [[col:green]]a tier {tiers} unit[[/col]] of the next floor's army joins ours now, and that army fields one unit fewer.",
                       broke("no one turns")),
    "tower_dividends": (PAY + "buy a share of the tower's vaults: [[col:green]]+{per_turn} gold[[/col]] to our treasury each turn for {turns} turns, kept even if the "
                        "delve is lost.", broke("no share is bought", climbs=False)),
    "cursed_idol": ("Take the idol: [[col:green]]+{gold} gold[[/col]] in the haul now, but the next army is [[col:red]]15% stronger[[/col]].", None),
    "conscripts": (PAY + "press conscripts into service: [[col:green]]2 tier 1-2 units[[/col]] of our own kind join our army now.", broke("no one is pressed")),
    "captured_war_machine": (PAY + "salvage a war machine from the tower's armoury: [[col:green]]a tier {tiers} war machine[[/col]] joins our army now.",
                             broke("the war machine stays in the tower")),
    "regiment_of_renown": (PAY + "hire a [[col:green]]Regiment of Renown[[/col]] of our own kind: it joins our army now.", broke("the regiment rides on")),
    "veterans_oath": (PAY + "swear the veterans' oath: [[col:green]]3 units[[/col]] gain [[col:green]]{ranks}[[/col]] each.", broke("no oath is sworn")),
    "lessons_in_blood": (PAY + "study the fallen: our lord gains [[col:green]]+{lord_xp} experience[[/col]].", broke("the lesson goes unlearned")),
    "freed_prisoner": (PAY + "free a prisoner from the tower's cells: [[col:green]]a rank {rank} hero[[/col]] joins our army.", broke("the cells stay locked")),
    "towers_favour": (PAY + "win the tower's favour: [[col:green]]+{e0}% income[[/col]] from all buildings for {turns} turns.",
                      broke("the tower's masters pay us no heed", climbs=False)),
    "research_scrolls": (PAY + "take the tower's research scrolls: [[col:green]]+25% research rate[[/col]] for {turns} turns.", broke("the scrolls stay on the shelf", climbs=False)),
    "recruitment_cache": (PAY + "open a recruitment cache: [[col:green]]-{e0}% recruitment cost[[/col]] for {turns} turns.", broke("the cache stays sealed", climbs=False)),
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
}

# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Battle bundles and notices

# Tiered tower bundle name after `land_enc_effect_tower_` -> (target, icon, title, description, [(effect, scope, (easy, medium, hard) or value)],
# notice or None). A notice (colour, text) names the battle notice of a bundle on our army. A bundle on the enemy is announced by its
# offer's notice in `NOTICES` instead.
TOWER_BUNDLES = {
    "war_rites": ("force", "icon_effects_fortify.png", "War Rites", "The army held its war rites before the battle. The fervour lasts for that battle only.",
                  [("wh_main_effect_force_stat_melee_attack", "force_to_force_own", (5, 10, 15)),
                   ("wh_main_effect_force_stat_melee_defence", "force_to_force_own", (5, 10, 15)),
                   ("wh_main_effect_force_stat_leadership", "force_to_force_own", (5, 10, 15))],
                  ("green", "War Rites: +{e0} " + icon("icon_stat_attack") + icon("icon_stat_defence") + icon("icon_stat_morale") + ".")),
    "whetstones_and_oil": ("force", "icon_effects_fortify.png", "Whetstones and Oil", "Every blade in the army is honed and oiled for one battle.",
                           [("wh_main_effect_force_stat_weapon_strength", "force_to_force_own", (5, 10, 15)),
                            ("wh_main_effect_force_stat_ap_damage", "force_to_force_own", (5, 10, 15))],
                           ("green", "Whetstones and Oil: +{e0}% " + icon("icon_stat_damage") + " and +{e1} " + icon("modifier_icon_armour_piercing") + ".")),
    "warding_sigils": ("force", "icon_effects_fortify.png", "Warding Sigils", "Sigils painted on shields and banners turn blows aside for one battle.",
                       [("wh_main_effect_force_stat_ward_save", "force_to_force_own", (5, 10, 15))], ("green", "Warding Sigils: +{e0}% ward save.")),
    "quartermasters_cache": ("force", "icon_effects_fortify.png", "Quartermaster's Cache", "A cache of powder, shot and arrows fills every quiver for the next battle.",
                             [("wh_main_effect_force_stat_ammunition", "force_to_force_own", (25, 50, 75)),
                              ("wh_main_effect_force_stat_reload_time_reduction", "force_to_force_own", (15, 25, 35))],
                             ("green", "Quartermaster's Cache: +{e0}% " + icon("icon_stat_ammo") + " and {e1}% faster " + icon("icon_stat_reload_time") + ".")),
    "drill_sergeant": ("force", "icon_effects_fortify.png", "Drill Sergeant", "A hard morning of drill has the army moving and charging faster for one battle.",
                       [("wh_main_effect_force_stat_speed", "force_to_force_own", (5, 10, 15)),
                        ("wh2_dlc14_effect_force_charge_bonus_add", "force_to_force_own", (5, 10, 15))],
                       ("green", "Drill Sergeant: +{e0}% " + icon("icon_stat_speed") + " and +{e1} " + icon("icon_stat_charge_bonus") + ".")),
    "iron_resolve": ("force", "icon_effects_fortify.png", "Iron Resolve", "The army swore to hold whatever comes. Nothing frightens it for one battle.",
                     [("wh_main_effect_force_stat_leadership", "force_to_force_own", (10, 20, 30)),
                      ("wh_main_effect_attribute_enable_immune_to_psychology", "force_to_force_own", 1)],
                     ("green", "Iron Resolve: +{e0} " + icon("icon_stat_morale") + ", immune to fear and terror.")),
    "stoneskin": ("force", "icon_effects_fortify.png", "Stoneskin", "A ward of living stone hardens the army's hide for one battle.",
                  [("wh_main_effect_force_stat_physical_resistance", "force_to_force_own", (5, 10, 15))], ("green", "Stoneskin: +{e0}% physical resistance.")),
    "call_the_winds": ("force", "icon_effects_fortify.png", "Call the Winds", "The Winds of Magic gather close for one battle.",
                       [("wh3_main_effect_winds_of_magic_pool_min", "force_to_force_own", (20, 30, 40)),
                        ("wh3_main_effect_winds_of_magic_pool_cap", "force_to_force_own", (20, 30, 40))],
                       ("green", "Call the Winds: +{e0} Winds of Magic in reserve.")),
    "break_their_spirit": ("force", "icon_effects_fortify.png", "Broken Spirit", "Word of what waits has spread through the ranks. This army fights afraid.",
                           [("wh_main_effect_force_stat_leadership", "force_to_force_own", (-10, -15, -20))], None),
    "curse_their_blades": ("force", "icon_effects_fortify.png", "Cursed Blades", "A curse dulls every blade in this army.",
                           [("wh_main_effect_force_stat_melee_attack", "force_to_force_own", (-5, -10, -15))], None),
    "spike_the_guns": ("force", "icon_effects_fortify.png", "Spiked Guns", "Spiked guns and spoiled arrows leave this army short of shot.",
                       [("wh_main_effect_force_stat_ammunition", "force_to_force_own", (-30, -40, -50))], None),
    "last_ditch_oath": ("force", "icon_effects_fortify.png", "Last Ditch Oath", "Our lord swore to stand to the last, and the army knows what it may cost.",
                        [("wh_main_effect_force_stat_leadership", "force_to_force_own", -10)],
                        ("yellow", "Last Ditch Oath: our lord cannot die, but our army has -{e0} " + icon("icon_stat_morale") + ".")),
    "towers_favour": ("faction", "income.png", "Tower's Favour", "The tower's masters speak well of us. Trade flows a little easier.",
                      [("wh_main_effect_economy_gdp_mod_all", "faction_to_region_own", (5, 10, 15))], None),
}

# Offer key -> (colour, text) of the notice of a shared sabotage or trick whose effect differs by difficulty. Red weakens the enemy, green
# helps us, yellow costs us. The numbers come from the tower offer at each difficulty.
NOTICES = {
    "bribe_the_guards": ("red", "Bribe the Guards: the enemy army is {weaker}% weaker."),
    "thin_the_ranks": ("red", "Thin the Ranks: the enemy fields {fewer_units} fewer units."),
    "poison_the_stores": ("red", "Poison the Stores: enemy units start at {strength}% strength."),
    "break_their_spirit": ("red", "Break Their Spirit: enemy units have -{e0} " + icon("icon_stat_morale") + "."),
    "curse_their_blades": ("red", "Curse Their Blades: enemy units have -{e0} " + icon("icon_stat_attack") + "."),
    "turn_a_traitor": ("red", "Turn a Traitor: one of the enemy's units fights for us."),
    "night_terrors": ("green", "Night Terrors: the enemy's {targets} after 1 minute."),
    "divine_shield": ("green", "Divine Shield: our lord cannot be harmed for the first {minutes} minutes."),
    "cripple_their_champion": ("red", "Cripple Their Champion: the enemy's finest unit starts at {champion}% strength."),
    "spike_the_guns": ("red", "Spike the Guns: enemy shooters have -{e0}% " + icon("icon_stat_ammo") + "."),
    "bait_and_switch": ("red", "Bait and Switch: the enemy army is {stronger}% bigger, but every unit starts at {strength}% strength."),
}
