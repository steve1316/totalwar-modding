"""The numbers of the in-game unit panel (health, armour, speed, weapon and missile strength, abilities), worked out from a unit's table rows, and
the tooltips of its abilities and attributes (type, cooldown, duration, phases with their stat and attribute effects, description).

Shared by the TTC unit browser (`tools.ttc_review`) and the modding workbench's unit panels, so both show what the game shows. The page side lives in
`modding-workbench/workbench/static/unit_panel.*`.
"""

import re
from typing import Dict, List, Tuple

from ttc.ttc_classifier import parse_number
from ttc.ttc_data import resolve_loc

# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Settings

# Tables the panel numbers come from.
PANEL_TABLES = [
    "battle_entities_tables",
    "melee_weapons_tables",
    "unit_armour_types_tables",
    "mounts_tables",
    "battlefield_engines_tables",
    "missile_weapons_tables",
    "projectiles_tables",
    "projectiles_explosions_tables",
    "unit_abilities_tables",
    "land_units_to_unit_abilites_junctions_tables",
    "unit_special_abilities_tables",
    "special_ability_to_special_ability_phase_junctions_tables",
    "special_ability_phases_tables",
    "special_ability_phase_stat_effects_tables",
    "special_ability_phase_attribute_effects_tables",
    "ui_tagged_images_tables",
]

# Loc key prefixes the tooltips read.
ABILITY_NAME_PREFIX = "unit_abilities_onscreen_name_"
ABILITY_TEXT_PREFIX = "unit_abilities_tooltip_text_"
ABILITY_TYPE_PREFIX = "unit_ability_types_onscreen_name_"
PHASE_NAME_PREFIX = "special_ability_phases_onscreen_name_"
STAT_NAME_PREFIX = "unit_stat_localisations_onscreen_name_"
ATTRIBUTE_PREFIX = "unit_attributes_bullet_text_"
TOOLTIP_LOC_PREFIXES = (ABILITY_NAME_PREFIX, ABILITY_TEXT_PREFIX, ABILITY_TYPE_PREFIX, PHASE_NAME_PREFIX, STAT_NAME_PREFIX, ATTRIBUTE_PREFIX)

# Folder of the ability icons.
ABILITY_FOLDER = "ui/battle ui/ability_icons"

# Folder an inline image with a bare name (`[[img:icon_morale]]`) is read from when `ui_tagged_images` does not name it.
INLINE_IMAGE_FOLDER = "ui/skins/default"

# An inline image in loc text.
INLINE_IMAGE = re.compile(r"\[\[img:([^\]]+)\]\]")

# Phase flags the tooltip lists: column -> text.
PHASE_FLAGS = {"imbue_magical": "Attacks become magical", "imbue_ignition": "Attacks become flaming", "cant_move": "Cannot move", "freeze_fatigue": "No fatigue",
               "replenish_ammo": "Replenishes ammunition", "resurrect": "Revives fallen models", "remove_magical": "Removes magical attacks"}


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Tables


def index_rows(rows: List[Dict[str, str]], column: str = "key") -> Dict[str, Dict[str, str]]:
    """Index rows by a column, the first row for a value winning like the game's load order (put overriding rows first).

    Args:
        rows (List[Dict[str, str]]): Table rows.
        column (str): Column to index by.

    Returns:
        Dict[str, Dict[str, str]]: Column value to row.
    """
    index: Dict[str, Dict[str, str]] = {}
    for row in rows:
        if row.get(column):
            index.setdefault(row[column], row)
    return index


class PanelTables:
    """`PANEL_TABLES` indexed for the panel numbers."""

    # Battle entity key to row (hit points, run speed).
    entities: Dict[str, Dict[str, str]]
    # Melee weapon key to row.
    weapons: Dict[str, Dict[str, str]]
    # Armour type key to row.
    armour: Dict[str, Dict[str, str]]
    # Mount key to row (its entity).
    mounts: Dict[str, Dict[str, str]]
    # Battlefield engine key to row (its entity and missile weapon).
    engines: Dict[str, Dict[str, str]]
    # Missile weapon key to row (its projectile).
    missile_weapons: Dict[str, Dict[str, str]]
    # Projectile key to row.
    projectiles: Dict[str, Dict[str, str]]
    # Projectile explosion key to row.
    explosions: Dict[str, Dict[str, str]]
    # Ability key to row (icon, hidden flag).
    abilities: Dict[str, Dict[str, str]]
    # Land unit key to its ability keys, in table order.
    unit_abilities: Dict[str, List[str]]
    # Special ability key to row (cooldown, duration, uses, range, mana cost).
    special: Dict[str, Dict[str, str]]
    # Special ability key to its phase keys, in order.
    phases: Dict[str, List[str]]
    # Phase key to row (duration, flags).
    phase_rows: Dict[str, Dict[str, str]]
    # Phase key to its stat effect rows, and to its attribute effect rows.
    phase_stats: Dict[str, List[Dict[str, str]]]
    phase_attributes: Dict[str, List[Dict[str, str]]]
    # Inline image name (`icon_morale`) to its image path.
    tagged: Dict[str, str]

    def __init__(self, tables: Dict[str, List[Dict[str, str]]]):
        """Indexes the tables.

        Args:
            tables (Dict[str, List[Dict[str, str]]]): `PANEL_TABLES` rows, overriding rows first.
        """
        self.entities = index_rows(tables["battle_entities_tables"])
        self.weapons = index_rows(tables["melee_weapons_tables"])
        self.armour = index_rows(tables["unit_armour_types_tables"])
        self.mounts = index_rows(tables["mounts_tables"])
        self.engines = index_rows(tables["battlefield_engines_tables"])
        self.missile_weapons = index_rows(tables["missile_weapons_tables"])
        self.projectiles = index_rows(tables["projectiles_tables"])
        self.explosions = index_rows(tables["projectiles_explosions_tables"])
        self.abilities = index_rows(tables["unit_abilities_tables"])
        self.unit_abilities = {}
        for row in tables["land_units_to_unit_abilites_junctions_tables"]:
            keys = self.unit_abilities.setdefault(row.get("land_unit", ""), [])
            if row.get("ability") and row["ability"] not in keys:
                keys.append(row["ability"])
        # The tooltip tables are optional: a caller that only needs the numbers may leave them out.
        self.special = index_rows(tables.get("unit_special_abilities_tables", []))
        self.phase_rows = index_rows(tables.get("special_ability_phases_tables", []), "id")
        self.phases, self.phase_stats, self.phase_attributes = {}, {}, {}
        for row in sorted(tables.get("special_ability_to_special_ability_phase_junctions_tables", []), key=lambda r: parse_number(r.get("order"))):
            if row.get("phase") not in self.phases.setdefault(row.get("special_ability", ""), []):
                self.phases[row["special_ability"]].append(row["phase"])
        for row in tables.get("special_ability_phase_stat_effects_tables", []):
            self.phase_stats.setdefault(row.get("phase", ""), []).append(row)
        for row in tables.get("special_ability_phase_attribute_effects_tables", []):
            self.phase_attributes.setdefault(row.get("phase", ""), []).append(row)
        self.tagged = {row["key"]: row.get("image_path", "") for row in tables.get("ui_tagged_images_tables", []) if row.get("key")}


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Numbers


def missile_stats(land: Dict[str, str], tables: PanelTables) -> Dict[str, int]:
    """The panel's missile rows for a unit that shoots.

    Missile Strength is the projectile's damage plus armour-piercing damage, plus its explosion's when it has one. Artillery and chariots with a gun
    take the weapon from their battlefield engine.

    Args:
        land (Dict[str, str]): The unit's `land_units_tables` row.
        tables (PanelTables): The indexed tables.

    Returns:
        Dict[str, int]: `ammunition`, `range` and `missile_strength`, or an empty dict when the unit has no missile weapon.
    """
    weapon = land.get("primary_missile_weapon") or tables.engines.get(land.get("engine", ""), {}).get("missile_weapon", "")
    projectile = tables.projectiles.get(tables.missile_weapons.get(weapon, {}).get("default_projectile", ""))
    if not projectile:
        return {}
    explosion = tables.explosions.get(projectile.get("explosion_type", ""), {})
    damage = sum(parse_number(row.get(column)) for row, column in ((projectile, "damage"), (projectile, "ap_damage"), (explosion, "detonation_damage"),
                                                                   (explosion, "detonation_damage_ap")))
    return {"ammunition": int(parse_number(land.get("primary_ammo"))), "range": int(parse_number(projectile.get("effective_range"))), "missile_strength": int(damage)}


def panel_stats(main: Dict[str, str], land: Dict[str, str], tables: PanelTables) -> Tuple[Dict[str, int], bool]:
    """The in-game panel numbers of one unit.

    HP is the man entity's hit points plus `bonus_hit_points`, times the number of men, plus the mount and engine entities' hit points. That matches the
    panel exactly for infantry and monsters. Speed is the mount's run speed when the unit has one, shown x10 like the panel.

    Args:
        main (Dict[str, str]): The unit's `main_units_tables` row.
        land (Dict[str, str]): Its `land_units_tables` row.
        tables (PanelTables): The indexed tables.

    Returns:
        Tuple[Dict[str, int], bool]: The stats by panel row key, and whether HP is an estimate (a mount or engine adds to it).
    """
    man = tables.entities.get(land.get("man_entity", ""), {})
    mount = tables.entities.get(tables.mounts.get(land.get("mount", ""), {}).get("entity", ""), {})
    engine = tables.entities.get(tables.engines.get(land.get("engine", ""), {}).get("battle_entity", ""), {})
    weapon = tables.weapons.get(land.get("primary_melee_weapon", ""), {})
    men = int(parse_number(main.get("num_men")))
    hp = (parse_number(man.get("hit_points")) + parse_number(land.get("bonus_hit_points"))) * men
    hp += parse_number(mount.get("hit_points")) * parse_number(land.get("num_mounts")) + parse_number(engine.get("hit_points")) * parse_number(land.get("num_engines"))
    stats = {
        "hp": round(hp),
        "tier": int(parse_number(main.get("tier"))),
        "men": men,
        "armour": int(parse_number(tables.armour.get(land.get("armour", ""), {}).get("armour_value"))),
        "leadership": int(parse_number(land.get("morale"))),
        "speed": round(parse_number((mount or man).get("run_speed")) * 10),
        "melee_attack": int(parse_number(land.get("melee_attack"))),
        "melee_defence": int(parse_number(land.get("melee_defence"))),
        "weapon_strength": int(parse_number(weapon.get("damage")) + parse_number(weapon.get("ap_damage"))),
        "charge_bonus": int(parse_number(land.get("charge_bonus"))),
        **missile_stats(land, tables),
    }
    return stats, bool(mount or engine)


def visible_abilities(land_key: str, tables: PanelTables) -> List[Tuple[str, str]]:
    """The abilities the panel shows for a land unit: every linked ability not hidden in the UI.

    Args:
        land_key (str): The land unit key.
        tables (PanelTables): The indexed tables.

    Returns:
        List[Tuple[str, str]]: (ability key, icon name) pairs in table order.
    """
    shown = []
    for ability in tables.unit_abilities.get(land_key, []):
        row = tables.abilities.get(ability, {})
        if row.get("is_hidden_in_ui") != "true":
            shown.append((ability, row.get("icon_name", "")))
    return shown


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Tooltips


def inline_images(text: str) -> List[str]:
    """The pack paths of the images a loc text shows inline. A bare name is a skin icon.

    Args:
        text (str): The loc text.

    Returns:
        List[str]: Lowercase paths, e.g. `ui/skins/default/icon_morale.png`.
    """
    return [inline_image_path(name) for name in INLINE_IMAGE.findall(text or "")]


def inline_image_path(name: str, tagged: Dict[str, str] = None) -> str:
    """The pack path of an inline image name: a path as it is, else the `ui_tagged_images` entry, else a skin icon of that name.

    Args:
        name (str): The name inside `[[img:...]]`.
        tagged (Dict[str, str]): `PanelTables.tagged`.

    Returns:
        str: The lowercase path.
    """
    name = name.strip()
    if "/" in name:
        return name.lower()
    return ((tagged or {}).get(name) or f"{INLINE_IMAGE_FOLDER}/{name}.png").lower()


def resolve_images(text: str, tables: PanelTables) -> str:
    """Rewrites a loc text's inline image names as their paths, so a page can show them without the game's tables.

    Args:
        text (str): The loc text.
        tables (PanelTables): The indexed tables.

    Returns:
        str: The text.
    """
    return INLINE_IMAGE.sub(lambda match: f"[[img:{inline_image_path(match.group(1), tables.tagged)}]]", text or "")


def loc_text(loc: Dict[str, str], key: str) -> str:
    """A loc text with its `{{tr:...}}` references followed, or an empty string."""
    return resolve_loc(loc.get(key, ""), loc) or ""


def ability_tooltip(ability: str, tables: PanelTables, loc: Dict[str, str]) -> Dict:
    """An ability's tooltip, like the game's: its type, whether it is passive, its numbers, each phase with its effects, and its description.

    Args:
        ability (str): The ability key.
        tables (PanelTables): The indexed tables, with the tooltip tables.
        loc (Dict[str, str]): Loc key to text, with `TOOLTIP_LOC_PREFIXES`.

    Returns:
        Dict: `name`, `type` (loc text with inline images), `passive`, `numbers` ([label, value] pairs), `phases` (each with `name`, `duration`,
        `effects`: [label, value] pairs, and `attributes`: [name, positive] pairs) and `text`.
    """
    row, special = tables.abilities.get(ability, {}), tables.special.get(ability, {})
    number = lambda column: parse_number(special.get(column))
    numbers: List[Tuple[str, str]] = []
    passive = special.get("passive") == "true" or row.get("source_type") == "passive"
    if special and not passive:
        if number("mana_cost") > 0:
            numbers.append(("Cost", f"{number('mana_cost'):g}"))
        if number("recharge_time") > 0:
            numbers.append(("Cooldown", f"{number('recharge_time'):g}s"))
        numbers.append(("Duration", f"{number('active_time'):g}s" if number("active_time") > 0 else "Instant"))
        numbers.append(("Uses", f"{number('num_uses'):g}" if number("num_uses") > 0 else "Unlimited"))
    if special and number("effect_range") > 0:
        numbers.append(("Range", f"{number('effect_range'):g}m"))
    phases = []
    for phase in tables.phases.get(ability, []):
        phase_row = tables.phase_rows.get(phase, {})
        if phase_row.get("is_hidden_in_ui") == "true":
            continue
        effects = []
        for effect in tables.phase_stats.get(phase, []):
            value, label = parse_number(effect.get("value")), resolve_images(loc_text(loc, STAT_NAME_PREFIX + effect.get("stat", "")), tables) or effect.get("stat", "")
            # The game shows a multiplier as a percentage change.
            effects.append((label, f"{(value - 1) * 100:+.0f}%" if effect.get("how") == "mult" else f"{value:+g}"))
        for column, text in PHASE_FLAGS.items():
            if phase_row.get(column) == "true":
                effects.append((text, ""))
        if parse_number(phase_row.get("heal_amount")) > 0:
            effects.append(("Heals", f"{parse_number(phase_row.get('heal_amount')):g}"))
        if parse_number(phase_row.get("damage_amount")) > 0:
            effects.append(("Damage", f"{parse_number(phase_row.get('damage_amount')):g}"))
        attributes = [(loc_text(loc, ATTRIBUTE_PREFIX + a.get("attribute", "")).partition("||")[0] or a.get("attribute", ""), a.get("attribute_type") != "negative")
                      for a in tables.phase_attributes.get(phase, [])]
        duration = parse_number(phase_row.get("duration"))
        phases.append({"name": loc_text(loc, PHASE_NAME_PREFIX + phase), "duration": f"{duration:g}s" if duration > 0 else "", "effects": effects, "attributes": attributes})
    return {"name": loc_text(loc, ABILITY_NAME_PREFIX + ability) or ability, "type": resolve_images(loc_text(loc, ABILITY_TYPE_PREFIX + row.get("type", "")), tables),
            "passive": passive, "numbers": numbers, "phases": phases, "text": resolve_images(loc_text(loc, ABILITY_TEXT_PREFIX + ability), tables)}


def attribute_tooltip(attribute: str, loc: Dict[str, str], tables: PanelTables) -> Dict[str, str]:
    """An attribute's name and tooltip text (loc text with inline images). An attribute the game gives no text is not shown in game: its `name` is
    then empty.

    Args:
        attribute (str): The attribute key.
        loc (Dict[str, str]): Loc key to text.
        tables (PanelTables): The indexed tables, for the inline images.

    Returns:
        Dict[str, str]: `key`, `name` and `text`.
    """
    name, _, text = loc_text(loc, ATTRIBUTE_PREFIX + attribute).partition("||")
    return {"key": attribute, "name": name, "text": resolve_images(text, tables)}


def tooltip_images(tooltip: Dict) -> List[str]:
    """Every inline image a tooltip's texts show.

    Args:
        tooltip (Dict): An ability or attribute tooltip.

    Returns:
        List[str]: Lowercase pack paths.
    """
    labels = [label for phase in tooltip.get("phases", []) for label, _ in phase["effects"]]
    return [path for text in [tooltip.get("type", ""), tooltip.get("text", "")] + labels for path in inline_images(text)]
