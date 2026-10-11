"""List every vanilla lord and hero with its mount variants, its GLF ranged status, and a guessed GLF missile.

Usage:
    cd helper_scripts && python -u -m tools.glf_ranged.catalog [--seed] > _diag/glf_ranged_catalog.log 2>&1

The report goes to `_diag/glf_ranged_report.txt`. `--seed` writes `selection.json` from GLF's current units when it does not exist yet.
"""

import argparse
import collections
import glob
import json
import logging
import os
import re
import time
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Set, Tuple

from core.extract_cache import cached_pack_extract
from core.utilities import FILEPATH_TO_VANILLA_DATA_TABLES, TEMP_DIR, clear_temp_root, load_tsv_data, log_elapsed_time, setup_script_logging
from tools.glf_rebuild_animpack import GLF_ANIMPACK_PATH, GLF_MOD_DIR, SCHEMAS_DIR, SLOT_IDS_FILE, AnimSet, load_slot_ids, load_vanilla_sets, parse_set, read_animpack
from ttc.ttc_data import LOC_NAME_PREFIX, VANILLA_LOC_PACK, read_loc_names, unit_faction

TOOL_DIR = os.path.dirname(os.path.abspath(__file__))
SELECTION_PATH = os.path.join(TOOL_DIR, "selection.json")
REPORT_PATH = "./_diag/glf_ranged_report.txt"
SCRATCH = f"{TEMP_DIR}/glf_ranged"
VANILLA_TABLES = [
    "main_units_tables",
    "land_units_tables",
    "agent_subtypes_tables",
    "units_custom_battle_mounts_tables",
    "special_ability_groups_to_units_junctions_tables",
    "unit_attributes_to_groups_junctions_tables",
    "units_to_groupings_military_permissions_tables",
]
GLF_LAND_UNITS = f"{GLF_MOD_DIR}/db/land_units_tables/!!!1a_glf_battle_mage_dante.tsv"
GLF_MISSILES = f"{GLF_MOD_DIR}/db/missile_weapons_tables/glf_battle_mage.tsv"
CHARACTER_CASTES = {"lord", "hero"}
ANIMPACK_BIN_FOLDER = "animations/database/battle/bin"
FWM_ATTRIBUTE = "fire_whilst_moving"
# A generic GLF missile, e.g. `glf_mage_lord_life_missile`, captures the lore.
GENERIC_MISSILE = re.compile(r"^glf_mage_(lord|hero)_(.+)_missile$")
# A named GLF missile, e.g. `glf_emp_balthasar_gelt_missile`, captures the name after the race code.
SPECIAL_MISSILE = re.compile(r"^glf_[a-z]+_(.+)_missile$")
# Slots each unit kind needs to fire, and to fire while moving.
FIRE_SLOT = {"foot": "FIRE_LEVEL", "flyer": "FIRE_LEVEL", "rider": "RIDER_FIRE_FORWARD_LEVEL"}
FWM_SLOTS = {"foot": ["MOVING_FIRE_FORWARD_LEVEL"], "flyer": ["MOVING_FIRE_FORWARD_LEVEL"], "rider": ["RIDER_FIRE_LEFT_LEVEL", "RIDER_FIRE_RIGHT_LEVEL"]}
# Cast slots a fire slot can borrow its animation from, best first.
CAST_SLOTS = {
    "foot": ["CAST_SPELL_UP_SHORT", "CAST_SPELL_FORWARD_SHORT", "CAST_SPELL_UP_MEDIUM", "CAST_SPELL_FORWARD_MEDIUM", "CAST_SPELL_UP_LONG", "CAST_SPELL_FORWARD_LONG"],
    "rider": ["RIDER_CAST_SPELL_UP_SHORT", "RIDER_CAST_SPELL_FORWARD_SHORT", "RIDER_CAST_SPELL_UP_MEDIUM", "RIDER_CAST_SPELL_FORWARD_MEDIUM", "RIDER_CAST_SPELL_UP_LONG", "RIDER_CAST_SPELL_FORWARD_LONG"],
}
CAST_SLOTS["flyer"] = CAST_SLOTS["foot"]


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Data


@dataclass
class UnitRow:
    """One vanilla lord or hero land unit and its GLF ranged status."""

    # Land unit key.
    key: str
    # In-game name, or the key when no loc names it.
    name: str
    # Faction name, e.g. `High Elves`.
    faction: str
    # `lord` or `hero`.
    caste: str
    # Land unit key of the on-foot unit this one is a mount variant of. Equal to `key` for the base unit.
    base: str
    # Mount icon name for mount variants, e.g. `mount_great_eagle`, or empty.
    mount: str
    # Animation set name from `land_units.man_animation`.
    anim_set: str
    # `foot`, `rider` or `flyer`, or empty when the set is missing.
    kind: str
    # True when the agent subtype or a spell lore marks the unit as a caster.
    is_caster: bool
    # Missile weapon in vanilla `land_units`, usually empty.
    vanilla_missile: str
    # Missile weapon GLF gives the unit, or empty when GLF does not cover it.
    glf_missile: str
    # GLF missile guessed for the unit.
    guess: str
    # Why `guess` was picked.
    guess_source: str
    # True when the set GLF or vanilla ships has the unit kind's fire slot.
    fire_slot: bool
    # True when the set has `COMBAT_READY`, which on-foot firing needs to avoid a T-pose.
    combat_ready: bool
    # Cast slot a new fire slot would borrow from, or empty when the set has none.
    cast_slot: str
    # True when the unit's attribute group has `fire_whilst_moving`.
    fwm_attribute: bool
    # True when the set has the unit kind's fire-while-moving slots.
    fwm_slots: bool
    # Other lord and hero units that use the same animation set.
    set_shared_with: List[str] = field(default_factory=list)


@dataclass
class Catalog:
    """Every vanilla lord and hero row plus the choices the GUI offers."""

    # Rows in faction, then base unit, then key order.
    units: List[UnitRow]
    # Every GLF missile weapon key.
    missiles: List[str]


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Loading


def _rows(folder: str) -> List[Dict[str, str]]:
    """Read every TSV under a folder.

    Args:
        folder (str): Extraction folder.

    Returns:
        Row dicts.
    """
    rows: List[Dict[str, str]] = []
    for path in sorted(glob.glob(f"{folder}/**/*.tsv", recursive=True)):
        rows.extend(load_tsv_data(path)[0])
    return rows


def load_vanilla_tables() -> Dict[str, List[Dict[str, str]]]:
    """Extract the vanilla tables the catalog reads, through the extraction cache.

    Raises:
        FileNotFoundError: If a table could not be extracted.

    Returns:
        Table name to rows.
    """
    tables = {}
    for table in VANILLA_TABLES:
        dest = f"{SCRATCH}/vanilla/{table}"
        cached_pack_extract(FILEPATH_TO_VANILLA_DATA_TABLES, f"db/{table}/data__", dest, source_kind="file", capture_output=True)
        tables[table] = _rows(dest)
        if not tables[table]:
            raise FileNotFoundError(f"Vanilla {table} could not be extracted")
    return tables


def load_names() -> Dict[str, str]:
    """Load vanilla English unit names.

    Returns:
        Loc key to text.
    """
    names: Dict[str, str] = {}
    dest = f"{SCRATCH}/loc"
    cached_pack_extract(VANILLA_LOC_PACK, "text", dest, capture_output=True)
    read_loc_names(dest, names)
    return names


def load_sets() -> Dict[str, Tuple[AnimSet, Optional[AnimSet]]]:
    """Load each animation set as vanilla ships it and as GLF ships it.

    Returns:
        Set name to (vanilla set, GLF set or None).
    """
    vanilla = {path: parse_set(data) for path, data in load_vanilla_sets().items() if path.startswith(ANIMPACK_BIN_FOLDER) and path.endswith(".bin")}
    with open(GLF_ANIMPACK_PATH, "rb") as f:
        glf = {path: parse_set(data) for path, data in read_animpack(f.read())}
    return {anim_set.name: (anim_set, glf.get(path)) for path, anim_set in vanilla.items()}


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Catalog


def missile_family(missile: str) -> str:
    """Reduce a GLF missile to its lore for generic missiles, or keep a named special as is.

    Args:
        missile (str): GLF missile weapon key.

    Returns:
        The lore token, e.g. `life`, or the missile key.
    """
    match = GENERIC_MISSILE.match(missile)
    return match.group(2) if match else missile


def family_missile(family: str, caste: str, missiles: Set[str]) -> str:
    """Turn a lore or special back into a missile key for a caste.

    Args:
        family (str): Lore token or special missile key.
        caste (str): `lord` or `hero`.
        missiles (Set[str]): Every GLF missile key.

    Returns:
        The missile key, or empty when none exists.
    """
    if family in missiles:
        return family
    for candidate in (f"glf_mage_{caste}_{family}_missile", f"glf_mage_lord_{family}_missile"):
        if candidate in missiles:
            return candidate
    return ""


def learn_lores(units: Dict[str, Set[str]], glf_missiles: Dict[str, str]) -> Dict[str, collections.Counter]:
    """Learn which GLF missile family each vanilla lore feature goes with, from the units GLF already covers.

    Args:
        units (Dict[str, Set[str]]): Land unit to its lore features (spell ability groups and subtype magic lore).
        glf_missiles (Dict[str, str]): Land unit to the missile GLF gives it.

    Returns:
        Feature to missile family vote counts.
    """
    votes: Dict[str, collections.Counter] = collections.defaultdict(collections.Counter)
    for key, missile in glf_missiles.items():
        for feature in units.get(key, ()):
            votes[feature][missile_family(missile)] += 1
    return votes


def guess_missile(key: str, caste: str, features: Set[str], faction: str, votes: Dict[str, collections.Counter], faction_votes: Dict[str, collections.Counter], missiles: Set[str], lores: List[str]) -> Tuple[str, str]:
    """Guess the GLF missile for a unit.

    Args:
        key (str): Land unit key.
        caste (str): `lord` or `hero`.
        features (Set[str]): The unit's lore features.
        faction (str): Faction name.
        votes (Dict[str, collections.Counter]): Feature to missile family votes from `learn_lores`.
        faction_votes (Dict[str, collections.Counter]): Faction to missile family votes over GLF's units.
        missiles (Set[str]): Every GLF missile key.
        lores (List[str]): Generic lore tokens, longest first.

    Returns:
        The missile key and why it was picked. The key is empty when nothing matched. A named special whose name is in the key wins, then lore
        votes, then a lore token in the key, then the faction's most common GLF lore.
    """
    for missile in sorted(missiles, key=len, reverse=True):
        stem = SPECIAL_MISSILE.match(missile)
        if stem and not GENERIC_MISSILE.match(missile) and re.search(rf"(^|_){re.escape(stem.group(1))}(_|\d|$)", key):
            return missile, f"named special `{stem.group(1)}`"
    tally: collections.Counter = collections.Counter()
    for feature in features:
        tally.update(votes.get(feature, {}))
    if tally:
        family = min(tally.items(), key=lambda item: (-item[1], item[0]))[0]
        missile = family_missile(family, caste, missiles)
        if missile:
            return missile, "lore " + ", ".join(sorted(f for f in features if f in votes))
    for lore in lores:
        if re.search(rf"(^|_){re.escape(lore)}(_|\d|$)", key):
            return family_missile(lore, caste, missiles), f"key token `{lore}`"
    if faction_votes.get(faction):
        family = min(faction_votes[faction].items(), key=lambda item: (-item[1], item[0]))[0]
        missile = family_missile(missile_family(family), caste, missiles)
        if missile:
            return missile, f"{faction} default"
    return "", "no match"


def unit_kind(anim_set: AnimSet, names: Dict[int, str]) -> str:
    """Tell whether a set is for a unit on foot, a rider, or a flyer on foot.

    Args:
        anim_set (AnimSet): The vanilla set.
        names (Dict[int, str]): Slot name by id.

    Returns:
        `rider`, `flyer` or `foot`.
    """
    slot_names = {names.get(slot.slot_id, "") for slot in anim_set.slots}
    if anim_set.mount or "RIDER_STAND" in slot_names:
        return "rider"
    return "flyer" if "FLY_STAND" in slot_names else "foot"


def build_catalog(tables: Dict[str, List[Dict[str, str]]], sets: Dict[str, Tuple[AnimSet, Optional[AnimSet]]], loc: Dict[str, str], glf_rows: List[Dict[str, str]], missiles: List[str], names: Dict[int, str]) -> Catalog:
    """Build one row per vanilla lord and hero land unit.

    Args:
        tables (Dict[str, List[Dict[str, str]]]): Vanilla tables from `load_vanilla_tables`.
        sets (Dict[str, Tuple[AnimSet, Optional[AnimSet]]]): Animation sets from `load_sets`.
        loc (Dict[str, str]): Loc key to text.
        glf_rows (List[Dict[str, str]]): GLF's land_units rows.
        missiles (List[str]): Every GLF missile key.
        names (Dict[int, str]): Slot name by id.

    Returns:
        The catalog.
    """
    land = {row["key"]: row for row in tables["land_units_tables"]}
    main = [row for row in tables["main_units_tables"] if row["caste"] in CHARACTER_CASTES and row["land_unit"] in land]
    caste_of = {row["land_unit"]: row["caste"] for row in main}
    unit_of = {row["land_unit"]: row["unit"] for row in main}
    base_of, mount_of = {}, {}
    for row in tables["units_custom_battle_mounts_tables"]:
        base_of[row["mounted_unit"]] = row["base_unit"]
        mount_of[row["mounted_unit"]] = os.path.splitext(os.path.basename(row["icon_name"]))[0]
    groups: Dict[str, Set[str]] = collections.defaultdict(set)
    for row in tables["units_to_groupings_military_permissions_tables"]:
        groups[row["unit"]].add(row["military_group"])

    features: Dict[str, Set[str]] = collections.defaultdict(set)
    casters = set()
    for row in tables["special_ability_groups_to_units_junctions_tables"]:
        if "lore" in row["ability_group"]:
            features[row["unit"]].add(row["ability_group"])
            casters.add(row["unit"])
    for row in tables["agent_subtypes_tables"]:
        unit = row["associated_unit_override"]
        if row["magic_lore"]:
            features[unit].add(row["magic_lore"])
        if row["is_caster"].lower() == "true":
            casters.add(unit)
    # Mount variants share the base unit's lore and caster flag.
    for key in caste_of:
        base = base_of.get(key, key)
        features[key] |= features.get(base, set())
        if base in casters:
            casters.add(key)

    fwm_groups = {row["attribute_group"] for row in tables["unit_attributes_to_groups_junctions_tables"] if row["attribute"] == FWM_ATTRIBUTE}
    glf_missiles = {row["key"]: row["primary_missile_weapon"] for row in glf_rows if row.get("primary_missile_weapon")}
    missile_set = set(missiles)
    votes = learn_lores(features, glf_missiles)
    faction_votes: Dict[str, collections.Counter] = collections.defaultdict(collections.Counter)
    for key, missile in glf_missiles.items():
        faction_votes[unit_faction(key, groups.get(unit_of.get(key, key), set()))][missile_family(missile)] += 1
    lores = sorted({m.group(2) for m in map(GENERIC_MISSILE.match, missiles) if m}, key=len, reverse=True)

    users: Dict[str, List[str]] = collections.defaultdict(list)
    for key in caste_of:
        users[land[key]["man_animation"]].append(key)

    rows = []
    for key, caste in caste_of.items():
        land_row = land[key]
        faction = unit_faction(key, groups.get(unit_of[key], set()))
        guess, source = guess_missile(key, caste, features[key], faction, votes, faction_votes, missile_set, lores)
        vanilla_set, glf_set = sets.get(land_row["man_animation"], (None, None))
        kind = unit_kind(vanilla_set, names) if vanilla_set else ""
        live = glf_set or vanilla_set
        slot_names = {names.get(slot.slot_id, "") for slot in live.slots} if live else set()
        rows.append(
            UnitRow(
                key=key,
                name=loc.get(LOC_NAME_PREFIX + key, key),
                faction=faction,
                caste=caste,
                base=base_of.get(key, key),
                mount=mount_of.get(key, ""),
                anim_set=land_row["man_animation"],
                kind=kind,
                is_caster=key in casters,
                vanilla_missile=land_row["primary_missile_weapon"],
                glf_missile=glf_missiles.get(key, ""),
                guess=guess,
                guess_source=source,
                fire_slot=bool(kind) and FIRE_SLOT[kind] in slot_names,
                combat_ready="COMBAT_READY" in slot_names,
                cast_slot=next((name for name in CAST_SLOTS.get(kind, []) if name in slot_names), ""),
                fwm_attribute=land_row["attribute_group"] in fwm_groups,
                fwm_slots=bool(kind) and all(name in slot_names for name in FWM_SLOTS[kind]),
                set_shared_with=sorted(other for other in users[land_row["man_animation"]] if other != key),
            )
        )
    rows.sort(key=lambda row: (row.faction, row.base, row.key != row.base, row.key))
    return Catalog(rows, missiles)


def load_catalog() -> Catalog:
    """Load every input and build the catalog.

    Returns:
        The catalog.
    """
    with open(f"{SCHEMAS_DIR}/{SLOT_IDS_FILE}", encoding="utf-8") as f:
        names = load_slot_ids(f.read())
    glf_rows = load_tsv_data(GLF_LAND_UNITS)[0]
    missiles = [row["key"] for row in load_tsv_data(GLF_MISSILES)[0]]
    return build_catalog(load_vanilla_tables(), load_sets(), load_names(), glf_rows, missiles, names)


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Selection and report


def seed_selection(catalog: Catalog) -> Dict:
    """Build a selection that marks every unit GLF covers today as ranged with its current missile.

    Args:
        catalog (Catalog): The catalog.

    Returns:
        The selection.
    """
    units = {row.key: {"ranged": True, "fwm": False, "missile": row.glf_missile} for row in catalog.units if row.glf_missile}
    return {"units": units, "ignore": []}


def report_lines(catalog: Catalog) -> List[str]:
    """Summarise the catalog per faction.

    Args:
        catalog (Catalog): The catalog.

    Returns:
        Report lines.
    """
    lines = []
    by_faction: Dict[str, List[UnitRow]] = collections.defaultdict(list)
    for row in catalog.units:
        by_faction[row.faction].append(row)
    lines.append(f"{'faction':22} units  GLF  casters-missing  no-set  T-pose-risk")
    for faction, rows in sorted(by_faction.items()):
        glf = sum(1 for row in rows if row.glf_missile)
        missing = [row for row in rows if row.is_caster and not row.glf_missile]
        no_set = sum(1 for row in rows if not row.kind)
        risk = sum(1 for row in rows if row.glf_missile and row.kind != "rider" and row.fire_slot and not row.combat_ready)
        lines.append(f"{faction:22} {len(rows):5}  {glf:3}  {len(missing):15}  {no_set:6}  {risk:11}")
    lines.append("")
    lines.append("Casters GLF does not cover (key | kind | cast slot | guess | source):")
    for row in catalog.units:
        if row.is_caster and not row.glf_missile:
            lines.append(f"    {row.key} | {row.kind or 'no set'} | {row.cast_slot or 'NO CAST SLOT'} | {row.guess or '-'} | {row.guess_source}")
    lines.append("")
    lines.append("GLF units whose guess differs from GLF's missile (guess check):")
    differ = [row for row in catalog.units if row.glf_missile and row.guess != row.glf_missile]
    lines.append(f"    {len(differ)} of {sum(1 for row in catalog.units if row.glf_missile)}")
    lines += [f"    {row.key}: GLF {row.glf_missile}, guess {row.guess} ({row.guess_source})" for row in differ[:40]]
    return lines


def main():
    """Build the catalog, write the report, and seed the selection when asked."""
    parser = argparse.ArgumentParser(description="List vanilla lords and heroes with their GLF ranged status.")
    parser.add_argument("--seed", action="store_true", help="Write selection.json from GLF's current units when it does not exist.")
    args = parser.parse_args()

    setup_script_logging()
    start_time = time.time()
    try:
        catalog = load_catalog()
        logging.info(f"Catalog has {len(catalog.units)} lord and hero units.")
        os.makedirs(os.path.dirname(REPORT_PATH), exist_ok=True)
        with open(REPORT_PATH, "w", encoding="utf-8") as f:
            f.write("\n".join(report_lines(catalog)) + "\n")
        logging.info(f"Report written to {REPORT_PATH}.")
        if args.seed:
            if os.path.exists(SELECTION_PATH):
                logging.info(f"{SELECTION_PATH} already exists. Not seeding.")
            else:
                with open(SELECTION_PATH, "w", encoding="utf-8") as f:
                    json.dump(seed_selection(catalog), f, indent=1, sort_keys=True)
                logging.info(f"Seeded {SELECTION_PATH}.")
    finally:
        clear_temp_root()
    log_elapsed_time("GLF ranged catalog", start_time)


if __name__ == "__main__":
    main()
