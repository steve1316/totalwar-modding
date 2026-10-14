"""The numbers of the in-game unit panel (health, armour, speed, weapon and missile strength, abilities), worked out from a unit's table rows.

Shared by the TTC unit browser (`tools.ttc_review`) and the Advisor Overhaul dashboard, so both show what the game shows. The page side lives in
`tools/dashboard/static/unit_panel.*`.
"""

from typing import Dict, List, Tuple

from ttc.ttc_classifier import parse_number

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
]


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
