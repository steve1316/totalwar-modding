"""Load TTC labels and unit tables, pick the units that need auto entries, and find stale hand entries."""

import glob
import os
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Set, Tuple

from extract_cache import cached_pack_extract
from pipeline import workshop_pack_path
from supported_mods import SUPPORTED_MODS
from ttc_compat_io import TtcEntry, hand_files, parse_ttc_file, parse_ttc_text
from utilities import FILEPATH_TO_VANILLA_DATA_TABLES, TEMP_DIR, load_tsv_data

BASE_TTC_PACK = workshop_pack_path("3386989556", "groovy_ttc.pack")
UNIT_TABLES = ["main_units_tables", "land_units_tables", "units_to_groupings_military_permissions_tables"]
EXCLUDED_CASTES = {"lord", "hero"}
SCRATCH = f"{TEMP_DIR}/ttc"


@dataclass
class UnitStats:
    """Everything the classifier knows about one unit."""

    # Unit key from `main_units_tables`.
    key: str
    # The unit's `main_units_tables` row.
    main: Dict[str, str]
    # The `land_units_tables` row its `land_unit` points at, or empty when none exists.
    land: Dict[str, str]
    # Military groups that can recruit the unit.
    groups: Set[str]


@dataclass
class TtcData:
    """Inputs for one TTC generation run."""

    # Unit key to label (`core`, `special,2`, ...) from the base vanilla list and the hand files.
    labels: Dict[str, str] = field(default_factory=dict)
    # Unit key to stats for every vanilla and modded unit.
    stats: Dict[str, UnitStats] = field(default_factory=dict)
    # Keys present in vanilla `main_units_tables`.
    vanilla_keys: Set[str] = field(default_factory=set)
    # `(package_name, main_units rows)` per installed supported mod, in `SUPPORTED_MODS` order.
    mod_units: List[Tuple[str, List[Dict[str, str]]]] = field(default_factory=list)
    # Package name to the unit keys that mod defines.
    units_by_mod: Dict[str, Set[str]] = field(default_factory=dict)
    # Unit key to the military groups that can recruit it.
    permissions: Dict[str, Set[str]] = field(default_factory=dict)
    # Package names of supported mods found on disk.
    installed: Set[str] = field(default_factory=set)
    # Package names of supported mods that are not installed.
    missing_mods: List[str] = field(default_factory=list)
    # Hand file path to its entries.
    hand_entries: Dict[str, List[TtcEntry]] = field(default_factory=dict)
    # Package name to the mod's display name.
    mod_names: Dict[str, str] = field(default_factory=dict)


def label_of(category: str, weight: Optional[int]) -> str:
    """Build a classifier label from an entry.

    Args:
        category (str): `core`, `special` or `rare`.
        weight (Optional[int]): Point weight, or None.

    Returns:
        `category` alone when there is no weight, otherwise `category,weight`.
    """
    return category if weight is None else f"{category},{weight}"


def select_targets(
    mod_units: List[Tuple[str, List[Dict[str, str]]]], vanilla_keys: Set[str], permissions: Dict[str, Set[str]], labeled: Set[str]
) -> Dict[str, str]:
    """Pick the modded units that need an auto entry.

    Args:
        mod_units (List[Tuple[str, List[Dict[str, str]]]]): `(package_name, main_units rows)` in `SUPPORTED_MODS` order.
        vanilla_keys (Set[str]): Keys in vanilla `main_units_tables`.
        permissions (Dict[str, Set[str]]): Unit key to the military groups that can recruit it.
        labeled (Set[str]): Keys that already have a vanilla or hand entry.

    Returns:
        Unit key to the package name of the first mod that defines it.
    """
    targets: Dict[str, str] = {}
    for package_name, rows in mod_units:
        for row in rows:
            key = row.get("unit", "")
            if not key or key in targets or key in vanilla_keys or key in labeled:
                continue
            if row.get("caste") in EXCLUDED_CASTES or not permissions.get(key):
                continue
            targets[key] = package_name
    return targets


def _normalized_name(name: str) -> str:
    """Normalize a mod or file name for matching hand files to mods.

    Args:
        name (str): A package name or hand file basename.

    Returns:
        Lowercase name without leading `!`, the extension or spaces.
    """
    base = os.path.basename(name).lstrip("!")
    for suffix in (".pack", ".lua"):
        base = base.removesuffix(suffix)
    return base.replace(" ", "_").lower()


def hand_file_mod(path: str, package_names: List[str]) -> Optional[str]:
    """Find the supported mod a hand file belongs to.

    Args:
        path (str): Hand file path.
        package_names (List[str]): Supported mods' package names.

    Returns:
        The matching package name, or None when no mod matches.
    """
    target = _normalized_name(path)
    for package_name in package_names:
        if _normalized_name(package_name) == target:
            return package_name
    return None


def stale_hand_entries(
    entries_by_file: Dict[str, List[TtcEntry]],
    file_mod: Dict[str, Optional[str]],
    installed: Set[str],
    units_by_mod: Dict[str, Set[str]],
    vanilla_keys: Set[str],
) -> Dict[str, Set[str]]:
    """Find hand entries whose unit no longer exists anywhere, only for files mapped to an installed mod.

    A hand file may list units from other mods, so an entry is only stale when no installed mod and not vanilla defines the unit.

    Args:
        entries_by_file (Dict[str, List[TtcEntry]]): Hand file path to its entries.
        file_mod (Dict[str, Optional[str]]): Hand file path to its package name, or None when unmapped.
        installed (Set[str]): Installed package names.
        units_by_mod (Dict[str, Set[str]]): Package name to the unit keys it defines.
        vanilla_keys (Set[str]): Keys in vanilla `main_units_tables`.

    Returns:
        Hand file path to the stale keys to remove. Files with nothing stale are omitted.
    """
    stale: Dict[str, Set[str]] = {}
    known = set(vanilla_keys).union(*units_by_mod.values())
    for path, entries in entries_by_file.items():
        package_name = file_mod.get(path)
        if package_name is None or package_name not in installed:
            continue
        gone = {entry.key for entry in entries if entry.key not in known}
        if gone:
            stale[path] = gone
    return stale


def _rows(folder: str) -> List[Dict[str, str]]:
    """Read every TSV row under an extracted folder.

    Args:
        folder (str): Extraction destination.

    Returns:
        Row dicts keyed by column name.
    """
    rows: List[Dict[str, str]] = []
    for path in sorted(glob.glob(f"{folder}/**/*.tsv", recursive=True)):
        data, _, _ = load_tsv_data(path)
        rows.extend(data)
    return rows


def _load_tables(pack_path: str, tag: str, vanilla: bool) -> Dict[str, List[Dict[str, str]]]:
    """Extract the unit tables from one pack through the extraction cache.

    Args:
        pack_path (str): Pack to read.
        tag (str): Scratch folder name.
        vanilla (bool): Read the vanilla `data__` files instead of whole table folders.

    Returns:
        Table name to rows.
    """
    tables = {}
    for table in UNIT_TABLES:
        dest = f"{SCRATCH}/{tag}/{table}"
        if vanilla:
            cached_pack_extract(pack_path, f"db/{table}/data__", dest, source_kind="file", capture_output=True)
        else:
            cached_pack_extract(pack_path, f"db/{table}", dest, capture_output=True)
        tables[table] = _rows(dest)
    return tables


def load_all() -> TtcData:
    """Load every input for a TTC generation run.

    Returns:
        The loaded data. Vanilla labels come first, then hand files in filename order, so the first label for a key wins.
    """
    data = TtcData()
    cached_pack_extract(BASE_TTC_PACK, "script/ttc", f"{SCRATCH}/base", tables_as_tsv=False, capture_output=True)
    base_list = f"{SCRATCH}/base/script/ttc/ttc_vanilla_units.lua"
    if os.path.exists(base_list):
        with open(base_list, "r", encoding="utf-8", errors="replace") as f:
            for entry in parse_ttc_text(f.read()):
                data.labels.setdefault(entry.key, label_of(entry.category, entry.weight))
    for path in hand_files():
        entries = parse_ttc_file(path)
        data.hand_entries[path] = entries
        for entry in entries:
            data.labels.setdefault(entry.key, label_of(entry.category, entry.weight))

    land_rows: Dict[str, Dict[str, str]] = {}
    main_rows: Dict[str, Dict[str, str]] = {}

    def absorb(tables: Dict[str, List[Dict[str, str]]]) -> None:
        """Merge one pack's tables into the shared lookups.

        Args:
            tables (Dict[str, List[Dict[str, str]]]): Table name to rows.
        """
        for row in tables["land_units_tables"]:
            if row.get("key"):
                land_rows.setdefault(row["key"], row)
        for row in tables["main_units_tables"]:
            if row.get("unit"):
                main_rows.setdefault(row["unit"], row)
        for row in tables["units_to_groupings_military_permissions_tables"]:
            if row.get("unit"):
                data.permissions.setdefault(row["unit"], set()).add(row.get("military_group", ""))

    vanilla = _load_tables(FILEPATH_TO_VANILLA_DATA_TABLES, "vanilla", vanilla=True)
    data.vanilla_keys = {row["unit"] for row in vanilla["main_units_tables"] if row.get("unit")}
    absorb(vanilla)
    for mod in SUPPORTED_MODS:
        if not mod["path"]:
            continue
        data.mod_names[mod["package_name"]] = mod["name"]
        if not os.path.exists(mod["path"]):
            data.missing_mods.append(mod["package_name"])
            continue
        tables = _load_tables(mod["path"], mod["package_name"].replace(".pack", "").replace(" ", "_"), vanilla=False)
        data.installed.add(mod["package_name"])
        data.mod_units.append((mod["package_name"], tables["main_units_tables"]))
        data.units_by_mod[mod["package_name"]] = {row["unit"] for row in tables["main_units_tables"] if row.get("unit")}
        absorb(tables)
    for key, row in main_rows.items():
        data.stats[key] = UnitStats(key, row, land_rows.get(row.get("land_unit", ""), {}), data.permissions.get(key, set()))
    return data
