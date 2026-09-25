"""Load TTC labels and unit tables, pick the units that need auto entries, and find stale hand entries."""

import glob
import logging
import os
import re
from dataclasses import dataclass, field
from typing import Dict, Iterable, List, Optional, Set, Tuple

from extract_cache import cached_pack_extract
from pipeline import workshop_pack_path
from supported_mods import SUPPORTED_MODS
from ttc_compat_io import TtcEntry, hand_files, parse_ttc_file, parse_ttc_text
from utilities import FILEPATH_TO_VANILLA_DATA_TABLES, TEMP_DIR, load_tsv_data

BASE_TTC_PACK = workshop_pack_path("3386989556", "groovy_ttc.pack")
UNIT_TABLES = ["main_units_tables", "land_units_tables", "units_to_groupings_military_permissions_tables"]
EXCLUDED_CASTES = {"lord", "hero"}
# `ror` as its own word in a unit key or mod name marks a Regiment of Renown, without matching words like `horror`.
RENOWN_PATTERN = re.compile(r"(^|_)ror(_|\d|$)")
# Prologue campaign recruit groups like `wh3_main_pro_ksl`. Units only these groups recruit never appear outside the prologue.
PROLOGUE_GROUP_PATTERN = re.compile(r"_pro_")
# Package name and display name for auto entries covering vanilla and DLC units the base TTC list misses.
VANILLA_PACKAGE = "vanilla"
VANILLA_NAME = "Vanilla + DLC"
SCRATCH = f"{TEMP_DIR}/ttc"
LOC_NAME_PREFIX = "land_units_onscreen_name_"
VANILLA_LOC_PACK = os.path.join(os.path.dirname(FILEPATH_TO_VANILLA_DATA_TABLES), "local_en.pack")
# English translation mods kept in this repo. Their unit names win over the text a mod ships itself.
TRANSLATION_MOD_PATTERN = re.compile(r"english|translation", re.I)
TRANSLATION_MODS_GLOB = "../warhammer3_mods/*"


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
    # Vanilla `main_units_tables` rows, for covering units the base TTC list misses.
    vanilla_units: List[Dict[str, str]] = field(default_factory=list)
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
    # Unit key to where its label came from (base list faction, hand file name or `mod:<package>`), used to keep lookalikes in one CV fold.
    label_sources: Dict[str, str] = field(default_factory=dict)
    # Keys labeled by a supported mod's own TTC scripts. The mod author's caps are never overridden.
    mod_labeled_keys: Set[str] = field(default_factory=set)
    # Installed supported mods whose `main_units_tables` could not be read, so they are not trusted for stale-entry removal.
    unreadable_mods: List[str] = field(default_factory=list)


def label_of(category: str, weight: Optional[int]) -> str:
    """Build a classifier label from an entry.

    TTC treats a missing weight as 1 (`unit_weight or 1`), so `core` and `core,1` get the same label.

    Args:
        category (str): `core`, `special` or `rare`.
        weight (Optional[int]): Point weight, or None.

    Returns:
        `category,weight`, with a missing weight written as 1.
    """
    return f"{category},{1 if weight is None else weight}"


def mod_ttc_entries(root: str) -> Dict[str, str]:
    """Collect the TTC caps a mod ships itself, from `script/ttc/*.lua` and `script/campaign/mod/*ttc*.lua`.

    Args:
        root (str): Folder the mod's `script/` folder was extracted into.

    Returns:
        Unit key to label, first file in sorted path order winning.
    """
    paths = glob.glob(os.path.join(root, "script", "ttc", "**", "*.lua"), recursive=True)
    paths += [p for p in glob.glob(os.path.join(root, "script", "campaign", "mod", "*.lua")) if "ttc" in os.path.basename(p).lower()]
    labels: Dict[str, str] = {}
    for path in sorted(paths):
        for entry in parse_ttc_file(path):
            labels.setdefault(entry.key, label_of(entry.category, entry.weight))
    return labels


def read_loc_names(folder: str, names: Dict[str, str]) -> None:
    """Add the unit onscreen names from every loc TSV under a folder, keeping names already found.

    Args:
        folder (str): Folder holding extracted or source `.loc.tsv` files.
        names (Dict[str, str]): Loc key to text, updated in place.
    """
    for path in sorted(glob.glob(f"{folder}/**/*.tsv", recursive=True)):
        try:
            rows, _, _ = load_tsv_data(path)
        except (UnicodeDecodeError, IndexError):
            continue
        for row in rows:
            key, text = row.get("key", ""), " ".join(row.get("text", "").split())
            if key.startswith(LOC_NAME_PREFIX) and text:
                names.setdefault(key, text)


def load_loc_names() -> Dict[str, str]:
    """Load unit onscreen names from the repo's English translation mods, then each installed supported mod, then vanilla.

    Returns:
        Loc key to text, the first source to name a key winning.
    """
    names: Dict[str, str] = {}
    for folder in sorted(glob.glob(TRANSLATION_MODS_GLOB)):
        if TRANSLATION_MOD_PATTERN.search(os.path.basename(folder)):
            read_loc_names(folder, names)
    packs = [(mod["package_name"], mod["path"]) for mod in SUPPORTED_MODS if mod["path"] and os.path.exists(mod["path"])]
    for tag, pack_path in packs + [("vanilla_local_en", VANILLA_LOC_PACK)]:
        dest = f"{SCRATCH}/loc/{tag.replace('.pack', '').replace(' ', '_')}"
        cached_pack_extract(pack_path, "text", dest, capture_output=True)
        read_loc_names(dest, names)
    return names


def unit_names(keys: Iterable[str], stats: Dict[str, UnitStats], loc: Dict[str, str]) -> Dict[str, str]:
    """Look up the in-game name of each unit.

    Args:
        keys (Iterable[str]): Unit keys.
        stats (Dict[str, UnitStats]): Unit key to stats, for the `land_unit` the name hangs off.
        loc (Dict[str, str]): Loc key to text.

    Returns:
        Unit key to name, falling back to the key when no loc text names it.
    """
    names = {}
    for key in keys:
        land_unit = stats[key].main.get("land_unit", "") if key in stats else ""
        names[key] = loc.get(LOC_NAME_PREFIX + land_unit) or loc.get(LOC_NAME_PREFIX + key) or key
    return names


def table_readable(folder: str) -> bool:
    """Check that an extracted table folder holds only TSV files, so an rpfm schema gap cannot make a mod look empty.

    Args:
        folder (str): Extraction destination of one table.

    Returns:
        True when the folder has at least one `.tsv` and no binary fallbacks.
    """
    files = [p for p in glob.glob(os.path.join(folder, "**", "*"), recursive=True) if os.path.isfile(p)]
    return bool(files) and all(p.endswith(".tsv") for p in files)


def is_regiment_of_renown(key: str, main_row: Dict[str, str], package_name: str) -> bool:
    """Decide whether a unit is a Regiment of Renown, which is never capped as `core`.

    Args:
        key (str): Unit key.
        main_row (Dict[str, str]): The unit's `main_units_tables` row.
        package_name (str): Package name of the mod that defines it.

    Returns:
        True when the game flags it as renown, or `ror` appears as its own word in the key or the mod name.
    """
    mod_name = package_name.lower().lstrip("!").removesuffix(".pack")
    return main_row.get("is_renown") == "true" or bool(RENOWN_PATTERN.search(key.lower())) or bool(RENOWN_PATTERN.search(mod_name))


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


def select_vanilla_targets(rows: List[Dict[str, str]], permissions: Dict[str, Set[str]], labeled: Set[str]) -> Dict[str, str]:
    """Pick the vanilla and DLC units that neither the base TTC list nor a hand file caps.

    Prologue-only and tutorial units are skipped. A unit drops out on the next run once the base TTC list covers it.

    Args:
        rows (List[Dict[str, str]]): Vanilla `main_units_tables` rows.
        permissions (Dict[str, Set[str]]): Unit key to the military groups that can recruit it.
        labeled (Set[str]): Keys that already have a cap.

    Returns:
        Unit key to `VANILLA_PACKAGE`.
    """
    targets: Dict[str, str] = {}
    for row in rows:
        key = row.get("unit", "")
        groups = permissions.get(key, set())
        if not key or key in labeled or row.get("caste") in EXCLUDED_CASTES or not groups:
            continue
        if "tutorial" in key or all(PROLOGUE_GROUP_PATTERN.search(group) for group in groups):
            continue
        targets[key] = VANILLA_PACKAGE
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
    owner_history: Optional[Dict[str, str]] = None,
) -> Dict[str, Set[str]]:
    """Find hand entries whose unit no longer exists anywhere, only for files mapped to an installed mod.

    A hand file may list units from other mods, so an entry is only stale when no installed mod and not vanilla defines the unit. A unit last seen in a
    mod that is not installed right now is kept, since it may come back when that mod is re-subscribed.

    Args:
        entries_by_file (Dict[str, List[TtcEntry]]): Hand file path to its entries.
        file_mod (Dict[str, Optional[str]]): Hand file path to its package name, or None when unmapped.
        installed (Set[str]): Installed package names.
        units_by_mod (Dict[str, Set[str]]): Package name to the unit keys it defines.
        vanilla_keys (Set[str]): Keys in vanilla `main_units_tables`.
        owner_history (Optional[Dict[str, str]]): Unit key to the package that defined it on earlier runs.

    Returns:
        Hand file path to the stale keys to remove. Files with nothing stale are omitted.
    """
    stale: Dict[str, Set[str]] = {}
    known = set(vanilla_keys).union(*units_by_mod.values())
    history = owner_history or {}
    for path, entries in entries_by_file.items():
        package_name = file_mod.get(path)
        if package_name is None or package_name not in installed:
            continue
        gone = {entry.key for entry in entries if entry.key not in known and history.get(entry.key, package_name) in installed}
        if gone:
            stale[path] = gone
    return stale


def merge_owner_history(history: Dict[str, str], units_by_mod: Dict[str, Set[str]]) -> Dict[str, str]:
    """Update which mod last defined each unit, keeping entries for units that are not currently installed.

    Args:
        history (Dict[str, str]): Unit key to package name from earlier runs.
        units_by_mod (Dict[str, Set[str]]): Package name to the unit keys it defines now, in `SUPPORTED_MODS` order.

    Returns:
        The merged history. A unit defined now takes the first mod that defines it.
    """
    current: Dict[str, str] = {}
    for package_name, keys in units_by_mod.items():
        for key in keys:
            current.setdefault(key, package_name)
    return {**history, **current}


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
        The loaded data. Labels come from the base vanilla list, then hand files in filename order, then each mod's own TTC scripts. The first label
        for a key wins.
    """
    data = TtcData()
    cached_pack_extract(BASE_TTC_PACK, "script/ttc", f"{SCRATCH}/base", tables_as_tsv=False, capture_output=True)
    base_list = f"{SCRATCH}/base/script/ttc/ttc_vanilla_units.lua"
    if os.path.exists(base_list):
        with open(base_list, "r", encoding="utf-8", errors="replace") as f:
            for entry in parse_ttc_text(f.read()):
                if entry.key not in data.labels:
                    data.labels[entry.key] = label_of(entry.category, entry.weight)
                    data.label_sources[entry.key] = "vanilla:" + "_".join(entry.key.split("_")[:3])
    for path in hand_files():
        entries = parse_ttc_file(path)
        data.hand_entries[path] = entries
        for entry in entries:
            if entry.key not in data.labels:
                data.labels[entry.key] = label_of(entry.category, entry.weight)
                data.label_sources[entry.key] = os.path.basename(path)

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
    data.vanilla_units = vanilla["main_units_tables"]
    data.vanilla_keys = {row["unit"] for row in data.vanilla_units if row.get("unit")}
    data.mod_names[VANILLA_PACKAGE] = VANILLA_NAME
    absorb(vanilla)
    for mod in SUPPORTED_MODS:
        if not mod["path"]:
            continue
        data.mod_names[mod["package_name"]] = mod["name"]
        if not os.path.exists(mod["path"]):
            data.missing_mods.append(mod["package_name"])
            continue
        tag = mod["package_name"].replace(".pack", "").replace(" ", "_")
        tables = _load_tables(mod["path"], tag, vanilla=False)
        main_units_dir = f"{SCRATCH}/{tag}/main_units_tables"
        if os.path.exists(main_units_dir) and not table_readable(main_units_dir):
            logging.warning(f"Could not read main_units_tables from {mod['package_name']}. Its units are skipped and its hand entries are left alone.")
            data.unreadable_mods.append(mod["package_name"])
            continue
        scripts_root = f"{SCRATCH}/{tag}/scripts"
        for source in ("script/ttc", "script/campaign/mod"):
            cached_pack_extract(mod["path"], source, scripts_root, tables_as_tsv=False, capture_output=True)
        for key, label in mod_ttc_entries(scripts_root).items():
            data.mod_labeled_keys.add(key)
            if key not in data.labels:
                data.labels[key] = label
                data.label_sources[key] = f"mod:{mod['package_name']}"
        data.installed.add(mod["package_name"])
        data.mod_units.append((mod["package_name"], tables["main_units_tables"]))
        data.units_by_mod[mod["package_name"]] = {row["unit"] for row in tables["main_units_tables"] if row.get("unit")}
        absorb(tables)
    for key, row in main_rows.items():
        data.stats[key] = UnitStats(key, row, land_rows.get(row.get("land_unit", ""), {}), data.permissions.get(key, set()))
    return data
