"""Puts the game's own stat icon in front of each stat a LEAPOI line names, the way the tower lines already show melee attack or leadership.

Used by `update_leapoi_spot_offers` on every dilemma line it writes, and run once over the hand-written lines in the same loc file.
Gold is left without an icon: prices are everywhere and the treasury card already shows them.
"""

import re
from typing import List, Pattern, Sequence, Tuple

# Folder of the unit stat icons.
STAT_ICON_FOLDER = "ui/skins/default/"

# Stat phrase pattern -> icon, longest phrases first so "movement range" is matched before "range". An icon without a folder is one of the
# game's named loc icons (as vanilla text uses, e.g. [[img:icon_income]][[/img]]). Unit strength only counts after a percentage.
STAT_ICONS: List[Tuple[str, str]] = [
    (r"movement range", "icon_effect_campaign_movement"),
    (r"recruitment costs?", "icon_money"),
    (r"winds of magic", "icon_wom_recharge"),
    (r"physical resistance", "icon_resistance_physical"),
    (r"missile resistance", "icon_resistance_missile"),
    (r"magic resistance", "icon_resistance_magic"),
    (r"fire resistance", "icon_resistance_fire"),
    (r"ward save", "ui/battle ui/ability_icons/resistance_ward_save.png"),
    (r"public order", "icon_public_order"),
    (r"melee attack", STAT_ICON_FOLDER + "icon_stat_attack.png"),
    (r"melee defence", STAT_ICON_FOLDER + "icon_stat_defence.png"),
    (r"weapon strength", STAT_ICON_FOLDER + "icon_stat_damage.png"),
    (r"missile damage", STAT_ICON_FOLDER + "icon_stat_ranged_damage.png"),
    (r"charge bonus", STAT_ICON_FOLDER + "icon_stat_charge_bonus.png"),
    (r"replenishment", "icon_replenishment"),
    (r"growth", "icon_growth"),
    (r"income", "icon_income"),
    (r"attrition", "icon_attrition"),
    (r"experience", "icon_experience"),
    (r"research rate", "icon_tech"),
    (r"relations", "icon_diplomacy"),
    (r"health", "icon_hp"),
    (r"(?<=%\[\[/col\]\] )strength|(?<=% )strength", "icon_hp"),
    (r"leadership", STAT_ICON_FOLDER + "icon_stat_morale.png"),
    (r"armour", STAT_ICON_FOLDER + "icon_stat_armour.png"),
    (r"speed", STAT_ICON_FOLDER + "icon_stat_speed.png"),
    (r"ammunition", STAT_ICON_FOLDER + "icon_stat_ammo.png"),
    (r"range", STAT_ICON_FOLDER + "icon_stat_range.png"),
]

# The compiled patterns, each matching its phrase as whole words in any case.
COMPILED: List[Tuple[Pattern, str]] = [(re.compile(r"(?<![\w/])(?:" + phrase + r")(?![\w.])", re.IGNORECASE), icon) for phrase, icon in STAT_ICONS]

# Markup spans a stat phrase must not be matched inside: icon tags and colour tags.
TAG = re.compile(r"\[\[[^\]]*\]\]")

# An icon tag right before a phrase, so the phrase already has its icon.
ICON_BEFORE = re.compile(r"\[\[/img\]\]\s*(?:\[\[col:[a-z]+\]\])?\s*$")


def add_stat_icons(text: str, keep: Sequence[str] = ()) -> str:
    """Adds the stat icon in front of every stat phrase in the text that does not have one yet.

    Args:
        text (str): The loc text.
        keep (Sequence[str]): Names left without icons, e.g. a spell called "Oath of Replenishment".

    Returns:
        str: The text with stat icons.
    """
    tags = [(m.start(), m.end()) for m in TAG.finditer(text)]
    tags += [(m.start(), m.end()) for name in keep if name for m in re.finditer(re.escape(name), text)]
    inserts = {}
    taken = []
    for pattern, icon in COMPILED:
        for m in pattern.finditer(text):
            start, end = m.start(), m.end()
            if any(a <= start < b for a, b in tags) or any(a < end and start < b for a, b in taken):
                continue
            taken.append((start, end))
            if not ICON_BEFORE.search(text[:start]):
                inserts[start] = f"[[img:{icon}]][[/img]] "
    for position in sorted(inserts, reverse=True):
        text = text[:position] + inserts[position] + text[position:]
    return text
