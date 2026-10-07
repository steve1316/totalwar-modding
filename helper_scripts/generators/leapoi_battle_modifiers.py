"""Text and bundle effects of the LEAPOI battle modifiers. The keys, sides and rolling rules live in
script/land_encounters/configs/battle_modifiers.lua. Written into the mod by update_leapoi_spot_offers.py."""

from typing import Dict, List, Tuple

# Scope every modifier bundle effect uses: the army carrying the bundle.
SCOPE = "force_to_force_own"

# Icon of every modifier bundle.
BUNDLE_ICON = "icon_effects_fortify.png"

# Our own effects that grant a vanilla passive ability to every unit, where vanilla has none: key -> (unit_set_unit_ability junction key,
# ability key, ability name). Vanilla already has Frenzy, Berserk, Feasting on Fear and Pleasure Through Pain for all units.
ABILITY_EFFECTS: Dict[str, Tuple[str, str, str]] = {
    "land_enc_effect_ability_enable_regeneration_all_units": ("land_enc_ability_enable_regeneration_all_units", "wh_main_unit_passive_regeneration",
                                                              "Regeneration"),
    "land_enc_effect_ability_enable_deathblow_all_units": ("land_enc_ability_enable_deathblow_all_units", "wh_main_unit_passive_deathblow", "Deathblow"),
    "land_enc_effect_ability_enable_strength_in_numbers_all_units": ("land_enc_ability_enable_strength_in_numbers_all_units",
                                                                     "wh2_main_unit_passive_strength_in_numbers", "Strength in Numbers"),
    "land_enc_effect_ability_enable_cloud_of_flies_all_units": ("land_enc_ability_enable_cloud_of_flies_all_units", "wh3_main_unit_passive_cloud_of_flies",
                                                                "Cloud of Flies"),
    "land_enc_effect_ability_enable_aura_of_immolation_all_units": ("land_enc_ability_enable_aura_of_immolation_all_units",
                                                                    "wh3_main_unit_passive_aura_of_immolation", "Aura of Immolation"),
    "land_enc_effect_ability_enable_too_horrible_to_die_all_units": ("land_enc_ability_enable_too_horrible_to_die_all_units",
                                                                     "wh2_main_unit_passive_too_horrible_to_die", "Too Horrible to Die"),
    "land_enc_effect_ability_enable_gorefeast_all_units": ("land_enc_ability_enable_gorefeast_all_units", "wh3_main_unit_passive_gorefeast", "Gorefeast"),
    "land_enc_effect_ability_enable_unholy_vigour_all_units": ("land_enc_ability_enable_unholy_vigour_all_units", "wh_main_unit_abilities_unholy_vigour",
                                                               "Unholy Vigour"),
}

# Effects whose tooltip lists the units they touch. The game fills the list from the viewer's own roster, so a bundle with one on another
# army says so. Ability grants show no list.
UNIT_LIST_EFFECTS = {
    "wh_main_effect_force_stat_physical_resistance", "wh_main_effect_force_stat_speed", "wh2_dlc14_effect_force_charge_bonus_add",
    "wh_main_effect_force_stat_weapon_strength", "wh_main_effect_force_stat_ward_save", "wh_main_effect_force_stat_range",
    "wh_main_effect_force_stat_vigour_loss_reduction",
}

# Said on its own paragraph under such a bundle on another army. Loc files store a line break as an escaped `\\n`.
DISCLAIMER = "\\\\n\\\\nThe units listed below come from your own roster, but only this army's units are affected."

# Notice colour by harm: what helps us is green, what hurts us red, what cuts both ways yellow.
HARM_COLOUR = {"+": "green", "-": "red", "~": "yellow"}

# What the army fields under each generic army composition: its modifier line, and the Allies in the Dark lines that name it.
ALLY_THEMES: Dict[str, str] = {
    "comp_monsters": "mostly monsters and war beasts",
    "comp_riders": "mostly cavalry and chariots",
    "comp_shieldwall": "infantry only",
    "comp_gunline": "mostly missile infantry and artillery",
}

# Modifier key -> (name, what it does, objective icon under ui/campaign ui/effect_bundles/, [(effect, value)]). The text reads after
# "Modifier: <name> - " on the dilemma and after "<name>:" in the battle notice.
MODIFIERS: Dict[str, Tuple[str, str, str, List[Tuple[str, float]]]] = {
    "hallowed": ("Hallowed Ground", "Our units +10 leadership.", "morale.png", [("wh_main_effect_force_stat_leadership", 10)]),
    "cursed_earth": ("Cursed Earth", "Our units -10 leadership.", "morale.png", [("wh_main_effect_force_stat_leadership", -10)]),
    "blood_moon": ("Blood Moon", "Every unit on the field +10 melee attack.", "weapon_damage.png", [("wh_main_effect_force_stat_melee_attack", 10)]),
    "iron_hides": ("Iron Hides", "Every unit on the field +5% physical resistance.", "resistance_physical.png",
                   [("wh_main_effect_force_stat_physical_resistance", 5)]),
    "swift_winds": ("Tailwind", "Every unit on the field +20% speed.", "vigour.png", [("wh_main_effect_force_stat_speed", 20)]),
    "heavy_ground": ("Heavy Ground", "Every unit on the field -10% speed.", "attrition.png", [("wh_main_effect_force_stat_speed", -10)]),
    "thunder_charge": ("Thunderous Charge", "Every unit on the field +25 charge bonus.", "weapon_damage.png", [("wh2_dlc14_effect_force_charge_bonus_add", 25)]),
    "brittle": ("Brittle Blades", "Enemy units -10% weapon strength.", "weapon_damage.png", [("wh_main_effect_force_stat_weapon_strength", -10)]),
    "wards": ("Wards of the Old Ones", "Enemy units +5% ward save.", "resistance_ward_save.png", [("wh_main_effect_force_stat_ward_save", 5)]),
    "gale": ("Howling Gale", "Every missile unit on the field -25% range.", "ammo.png", [("wh_main_effect_force_stat_range", -25)]),
    "winds_surge": ("Surge of the Winds", "Every army starts with +30 Winds of Magic reserve.", "wh3_dlc24_wind_blast.png",
                    [("wh3_main_effect_winds_of_magic_pool_min", 30), ("wh3_main_effect_winds_of_magic_pool_cap", 30)]),
    "exhausting": ("Sweltering Heat", "Every unit on the field tires 10% faster.", "attrition.png", [("wh_main_effect_force_stat_vigour_loss_reduction", -10)]),
    "frenzy": ("Blood Frenzy", "Every enemy unit gains Frenzy.", "blood_kiss.png", [("wh3_dlc27_effect_ability_enable_frenzy_all", 1)]),
    "berserkers": ("Berserkers", "Our units gain Berserk.", "blood_kiss.png", [("wh3_dlc27_effect_ability_enable_berserk_all_units", 1)]),
    "regen_enemy": ("Flesh That Knits", "Every enemy unit gains Regeneration.", "lileaths_blessing.png",
                    [("land_enc_effect_ability_enable_regeneration_all_units", 1)]),
    "regen_ours": ("Troll Blood", "Every unit of ours gains Regeneration.", "lileaths_blessing.png", [("land_enc_effect_ability_enable_regeneration_all_units", 1)]),
    "killing_blow": ("Executioners' Edge", "Every unit of ours gains Deathblow.", "assassin.png", [("land_enc_effect_ability_enable_deathblow_all_units", 1)]),
    "strength_numbers": ("Strength in Numbers", "Every enemy unit gains Strength in Numbers.", "morale.png",
                         [("land_enc_effect_ability_enable_strength_in_numbers_all_units", 1)]),
    "feasting": ("Feasting on Fear", "Our units gain Feasting on Fear.", "dlc10_death_night.png", [("wh3_dlc27_effect_ability_feasting_on_fear_all_units", 1)]),
    "flies": ("Cloud of Flies", "Every unit on the field gains Cloud of Flies.", "phase_posion.png", [("land_enc_effect_ability_enable_cloud_of_flies_all_units", 1)]),
    "immolation": ("Aura of Immolation", "Every enemy unit gains Aura of Immolation.", "modifier_icon_flaming.png",
                   [("land_enc_effect_ability_enable_aura_of_immolation_all_units", 1)]),
    "too_horrible": ("Too Horrible to Die", "Every enemy unit gains Too Horrible to Die.", "lileaths_blessing.png",
                     [("land_enc_effect_ability_enable_too_horrible_to_die_all_units", 1)]),
    "pleasure_pain": ("Pleasure Through Pain", "Every unit on the field gains Pleasure Through Pain.", "blood_kiss.png",
                      [("wh3_dlc27_effect_ability_enable_pleasure_through_pain_all_units", 1)]),
    "gorefeast": ("Gorefeast", "Every enemy unit gains Gorefeast.", "blood_kiss.png", [("land_enc_effect_ability_enable_gorefeast_all_units", 1)]),
    "unholy_vigour": ("Unholy Vigour", "Our units gain Unholy Vigour.", "vigour.png", [("land_enc_effect_ability_enable_unholy_vigour_all_units", 1)]),
    "bleeding_field": ("Bleeding Field", "Every unit on the field loses 1% of its strength every 15 seconds.", "casualties.png", []),
    "miasma": ("Plague Miasma", "Every enemy unit loses 1% of its strength every 15 seconds.", "phase_posion.png", []),
    "rot": ("Rot of Nurgle", "Every unit of ours loses 1% of its strength every 15 seconds.", "phase_posion.png", []),
    "second_wind": ("Second Wind", "Our units regain 5% of their strength at 2 and 4 minutes.", "lileaths_blessing.png", []),
    "lord_vigil": ("Lord's Vigil", "Our lord regains 1% of their strength every 30 seconds.", "lileaths_blessing.png", []),
    "short_shot": ("Short of Shot", "Every missile unit on the field starts with half its ammunition.", "ammo.png", []),
    "plenty_shot": ("Endless Quivers", "Every missile unit on the field never runs out of ammunition.", "ammo_character.png", []),
    "panic": ("Panic", "At 3:00 the enemy's two weakest units rout.", "dlc10_death_night.png", []),
    "cowards": ("Cowards' Ground", "At 3:00 our weakest unit routs.", "discouraged.png", []),
    "duel_lords": ("Fated Lords", "Both lords cannot be harmed for the first 3 minutes.", "nemesis_crown_sealed.png", []),
    "hold_fast": ("Hold Fast", "No unit on the field can rout for the first 3 minutes.", "morale.png", []),
    "terror_field": ("Field of Dread", "Every enemy unit causes terror.", "attribute_causes_terror.png", []),
    "grim_resolve": ("Grim Resolve", "Our units cannot break for the first 3 minutes.", "attribute_unbreakable.png", []),
    "ambush_country": ("Ambush Country", "Every unit can hide in forests and stays hidden while it moves.", "attribute_stalk.png", []),
    "silence_enemy": ("Silence the Casters", "Enemy spellcasters are Silenced and cannot cast spells.", "magic_cooldown.png",
                      [("wh3_main_effect_attribute_enable_silenced_enemy", 1)]),
    "silence_all": ("Dead Winds", "Every spellcaster on the field is Silenced and cannot cast spells.", "magic_cooldown.png",
                    [("wh3_main_effect_attribute_enable_silenced_enemy", 1)]),
    "mud": ("Sucking Mud", "No unit on the field can run.", "attrition.png", []),
    "fire_moving": ("Skirmish Drill", "Our missile units can fire while moving.", "wh2_dlc17_attribute_mounted_fire_move.png", []),
    "strider": ("Sure Footing", "Our units ignore difficult ground.", "attribute_ignore_forest_penalties.png", []),
    "disarmed": ("Wet Powder", "Enemy missile units cannot shoot for the first 3 minutes.", "ammo_switch.png", []),
    "glorious": ("Glorious Charge", "Our cavalry and chariots gain Glorious Charge.", "attribute_glorious_charge.png",
                 [("wh3_dlc27_effect_attribute_enable_glorious_charge_cavalry_chaiots", 1)]),
    "expendable": ("Callous Ranks", "Enemy units have Expendable and routing does not shake the rest of their army.", "attribute_expendable.png", []),
    "tireless_enemy": ("Tireless Foe", "Enemy units never tire.", "attribute_fatigue_immune.png", []),
    "run_amok": ("Maddened Beasts", "Monsters and war beasts on both sides may run amok.", "bst_rampage.png", []),
    "grim_presence": ("Grim Presence", "Enemy units within 25m of our lord lose 0.5% of their strength every 10 seconds.", "death_hag.png", []),
    "storm_magic": ("Storm of Magic", "Every army gains 20 Winds of Magic every minute.", "attribute_mastery_of_elemental_winds.png", []),
    "winds_drained": ("Drained Winds", "The enemy's Winds of Magic are drained to nothing at the start.", "emp_winds_of_shyish.png", []),
    "warp_shift": ("Warp Shift", "Every 2 minutes a random unit of any side is flung to a nearby spot.", "teleport.png", []),
    "jest": ("Tzeentch's Jest", "Every 2 minutes a random enemy unit and a random unit of ours swap places.", "attribute_mark_tzeentch.png", []),
    "blink": ("Blink Strike", "At 2:00 our cavalry and chariots are flung behind the enemy line.", "teleport.png", []),
    "lost_warp": ("Lost in the Warp", "At 2:00 a random unit of ours vanishes for 30 seconds, then reappears nearby.", "corruption_tzeentch.png", []),
    "scatter": ("Scattered Ranks", "The enemy's units start the battle scattered around their centre.", "attribute_guerrilla_deploy.png", []),
    "revealed": ("Naked Plain", "Every unit is always visible, no hiding for anyone.", "attribute_revealed.png", []),
    "wild_winds": ("Wild Winds", "Every 3 minutes a magical storm spawns near a random unit of any side.", "wh3_dlc24_wind_blast.png", []),
    "enemy_last_stand": ("Last Stand", "Enemy units cannot rout until they fall below half strength.", "attribute_unyielding_assault.png", []),
    "dead_rise": ("The Dead Rise", "At 5:00 our destroyed units return where they started, at 25% strength.", "attribute_undead.png", []),
    "comp_monsters": ("Monster Horde", f"The enemy army is {ALLY_THEMES['comp_monsters']}.", "rampage_cataclysmic.png", []),
    "comp_riders": ("Riders' Host", f"The enemy army is {ALLY_THEMES['comp_riders']}.", "charge.png", []),
    "comp_shieldwall": ("Shield Wall", f"The enemy army is {ALLY_THEMES['comp_shieldwall']}.", "icon_effects_fortify.png", []),
    "comp_gunline": ("Gunline", f"The enemy army is {ALLY_THEMES['comp_gunline']}.", "artillery.png", []),
    "undying": ("Undying Foe", "At 5:00 two destroyed enemy units return where they started, at half strength.", "icon_necromantic_power.png", []),
}

# Icon of every lore army composition's notice.
LORE_ICON = "attribute_encourages.png"

# Flavour text of each modifier's bundle, which the tooltip shows above its effects.
FLAVOUR: Dict[str, str] = {
    "hallowed": "Old blessings linger on this ground, and our warriors feel them.",
    "cursed_earth": "Something buried here whispers of defeat to our warriors.",
    "blood_moon": "A red moon hangs over the field and stirs every warrior to fury.",
    "iron_hides": "The air hangs thick and heavy, and blows land softer than they should.",
    "swift_winds": "A strong wind at every back hurries each warrior along.",
    "heavy_ground": "Mud and loose stone drag at every step.",
    "thunder_charge": "The ground drums underfoot, and every charge hits like thunder.",
    "brittle": "A creeping rust has eaten into this army's blades.",
    "wards": "Old runes hum around this army and turn blows aside.",
    "gale": "A howling gale snatches arrows and shot from the air.",
    "winds_surge": "The Winds of Magic run high and wild over this field.",
    "exhausting": "The heat is cruel, and every warrior tires before their time.",
    "frenzy": "Bloodlust runs through this army's ranks like fire.",
    "berserkers": "A red haze takes our warriors, and they fight without thought of retreat.",
    "regen_enemy": "Dark sorcery knits this army's wounds as fast as they are made.",
    "regen_ours": "A strange vigour knits our wounds closed as we fight.",
    "killing_blow": "Our warriors know where to strike to end a foe in one blow.",
    "strength_numbers": "This army takes heart from its sheer numbers.",
    "feasting": "Our warriors grow stronger on the fear of their foes.",
    "flies": "Clouds of buzzing flies choke every foe that draws near.",
    "immolation": "This army burns with a heat that sears all who touch it.",
    "too_horrible": "This army's warriors refuse to fall, however terrible their wounds.",
    "pleasure_pain": "Pain only drives these warriors on.",
    "gorefeast": "Every kill feeds this army's strength.",
    "unholy_vigour": "An unholy strength fills our warriors.",
    "silence_enemy": "A stillness falls on the enemy's casters, and the winds will not answer them.",
    "silence_all": "The Winds of Magic have died away over this field, and no caster can call them.",
    "glorious": "Our riders burn to charge home, and nothing will turn them aside.",
}


def add_lore(modifiers: List[Dict]) -> None:
    """Adds the lore army compositions to `MODIFIERS`. Their name and line live in configs/lore_armies.lua, so the config carries them.

    Args:
        modifiers (List[Dict]): The config's modifier records.
    """
    for modifier in modifiers:
        if "faction" in modifier:
            MODIFIERS[modifier["key"]] = (modifier["name"], modifier["effect"], LORE_ICON, [])


def ally_theme_text(key: str) -> str:
    """The sentence an Allies in the Dark line ends with, naming the theme its allied army rolled.

    Args:
        key (str): The generic army composition key.

    Returns:
        str: The loc text.
    """
    return f"They march as a [[col:yellow]]{MODIFIERS[key][0]}[[/col]]: {ALLY_THEMES[key]}."


def line_text(key: str) -> str:
    """The dilemma line of a modifier.

    Args:
        key (str): The modifier key.

    Returns:
        str: The loc text.
    """
    name, effect, _, _ = MODIFIERS[key]
    return f"[[col:yellow]]Modifier:[[/col]] {name} - {effect}"


def payload_text(key: str, harm: str) -> str:
    """The line of a modifier on a dilemma choice, where text shows green unless told otherwise: its name and effect take the colour of
    what it does to us.

    Args:
        key (str): The modifier key.
        harm (str): "-" when it hurts us, "+" when it helps, "~" when it cuts both ways.

    Returns:
        str: The loc text.
    """
    name, effect, _, _ = MODIFIERS[key]
    return f"[[col:yellow]]Modifier:[[/col]] [[col:{HARM_COLOUR[harm]}]]{name} - {effect}[[/col]]"


def notice_text(key: str) -> str:
    """The battle notice of a modifier, uncoloured.

    Args:
        key (str): The modifier key.

    Returns:
        str: The loc text.
    """
    name, effect, _, _ = MODIFIERS[key]
    return f"{name}: {effect[0].lower()}{effect[1:]}"


def bundle(key: str, side: str) -> Tuple[str, str, str, str, List[Tuple[str, str, float]]]:
    """The bundle a modifier puts on one side's army, in the generator's bundle shape.

    Args:
        key (str): The modifier key.
        side (str): "ours", "enemy" or "allies".

    Returns:
        Tuple: (target, icon, title, description, [(effect, scope, value)]).
    """
    name, _, _, effects = MODIFIERS[key]
    description = FLAVOUR[key]
    if side != "ours" and any(e in UNIT_LIST_EFFECTS for e, _ in effects):
        description += DISCLAIMER
    return "force", BUNDLE_ICON, name, description, [(e, SCOPE, v) for e, v in effects]
