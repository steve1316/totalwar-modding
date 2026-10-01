"""Shared pipeline primitives for the update_*.py compat-pack scripts.

The dynamic_rors and double_unit_size scripts each walk every supported mod, follow foreign-key chains from `land_units_tables` to mounts, weapons, projectiles, etc., dedupe across mods, and write trimmed copies into a compat pack. This module owns the bits that are identical between them.
"""

import functools
import logging
import os
from typing import Any, Callable, Dict, Iterable, List, Optional, Set, Tuple

from core.utilities import (
    cleanup_folders,
    extract_modded_tsv_data,
    extract_tsv_data,
    load_multiple_tsv_data,
    load_tsv_data,
    run_rpfm_cli,
    write_updated_tsv_file,
    STEAM_LIBRARY_DRIVE,
    TEMP_DIR,
)


SCHEMA_RON_PATH = "./schemas/schema_wh3.ron"


# Table extraction config used by every compat-pack script. `key_field` is the column whose value uniquely identifies a row in the table.
TABLE_CONFIGS: List[Dict[str, Any]] = [
    {"table_name": "units_to_groupings_military_permissions_tables", "folder_name": "units_to_groupings_military_permissions_tables", "key_field": "unit"},
    {"table_name": "main_units_tables", "folder_name": "main_units_tables", "key_field": "unit"},
    {"table_name": "land_units_tables", "folder_name": "land_units_tables", "key_field": "key"},
    {"table_name": "unit_description_historical_texts_tables", "folder_name": "unit_description_historical_texts_tables", "key_field": "key"},
    {"table_name": "battle_animations_table_tables", "folder_name": "battle_animations_table_tables", "key_field": "key"},
    {"table_name": "battle_entities_tables", "folder_name": "battle_entities_tables", "key_field": "key"},
    {"table_name": "mounts_tables", "folder_name": "mounts_tables", "key_field": "key"},
    {"table_name": "melee_weapons_tables", "folder_name": "melee_weapons_tables", "key_field": "key"},
    {"table_name": "missile_weapons_tables", "folder_name": "missile_weapons_tables", "key_field": "key"},
    {"table_name": "unit_description_short_texts_tables", "folder_name": "unit_description_short_texts_tables", "key_field": "key"},
    {"table_name": "unit_attributes_groups_tables", "folder_name": "unit_attributes_groups_tables", "key_field": "group_name"},
    {"table_name": "battlefield_engines_tables", "folder_name": "battlefield_engines_tables", "key_field": "key"},
    {"table_name": "projectiles_tables", "folder_name": "projectiles_tables", "key_field": "key"},
    {"table_name": "battle_vortexs_tables", "folder_name": "battle_vortexs_tables", "key_field": "vortex_key"},
    {"table_name": "projectiles_scaling_damages_tables", "folder_name": "projectiles_scaling_damages_tables", "key_field": "key"},
    {"table_name": "projectile_shot_type_displays_tables", "folder_name": "projectile_shot_type_displays_tables", "key_field": "key"},
    {"table_name": "unit_spacings_tables", "folder_name": "unit_spacings_tables", "key_field": "key"},
    {"table_name": "first_person_engines_tables", "folder_name": "first_person_engines_tables", "key_field": "key"},
    {"table_name": "land_unit_articulated_vehicles_tables", "folder_name": "land_unit_articulated_vehicles_tables", "key_field": "key"},
    {"table_name": "ui_unit_groupings_tables", "folder_name": "ui_unit_groupings_tables", "key_field": "key"},
    {"table_name": "ui_unit_group_parents_tables", "folder_name": "ui_unit_group_parents_tables", "key_field": "key"},
    {"table_name": "variants_tables", "folder_name": "variants_tables", "key_field": "variant_name"},
]


# Table name -> primary-key column. Used by `DuplicateTracker` to dedupe across mods.
TABLE_KEY_FIELDS: Dict[str, str] = {cfg["table_name"]: cfg["key_field"] for cfg in TABLE_CONFIGS}


# Bucket name -> table name. Buckets are the keys in the per-unit `new_data` dict produced by `walk_land_unit_to_related_tables`. Order here drives the optional-tables write loop.
OPTIONAL_TABLES: List[Tuple[str, str]] = [
    ("unit_description_historical_texts", "unit_description_historical_texts_tables"),
    ("battle_animations", "battle_animations_table_tables"),
    ("battle_entities", "battle_entities_tables"),
    ("mounts", "mounts_tables"),
    ("melee_weapons", "melee_weapons_tables"),
    ("missile_weapons", "missile_weapons_tables"),
    ("unit_description_short_texts", "unit_description_short_texts_tables"),
    ("unit_attributes_groups", "unit_attributes_groups_tables"),
    ("battlefield_engines", "battlefield_engines_tables"),
    ("projectiles", "projectiles_tables"),
    ("battle_vortexs", "battle_vortexs_tables"),
    ("projectiles_scaling_damages", "projectiles_scaling_damages_tables"),
    ("projectile_shot_type_displays", "projectile_shot_type_displays_tables"),
    ("unit_spacings", "unit_spacings_tables"),
    ("first_person_engines", "first_person_engines_tables"),
    ("land_unit_articulated_vehicles", "land_unit_articulated_vehicles_tables"),
    ("ui_unit_groupings", "ui_unit_groupings_tables"),
    ("ui_unit_group_parents", "ui_unit_group_parents_tables"),
    ("variants", "variants_tables"),
]

# Table name -> bucket name, the reverse of `OPTIONAL_TABLES`.
TABLE_BUCKETS: Dict[str, str] = {table_name: bucket_name for bucket_name, table_name in OPTIONAL_TABLES}


def modded_folders_for(scratch_root: str) -> List[str]:
    """Return the list of `modded_*` scratch folders that live under `scratch_root`.

    Used by parallel callers that need per-mod-namespaced scratch dirs (e.g. `f"{TEMP_DIR}/{mod_pkg}"`) so workers do not clobber each other.

    Args:
        scratch_root (str): Folder under which each `modded_<folder_name>` extraction directory lives.

    Returns:
        Full path list, one entry per `TABLE_CONFIGS.folder_name`.
    """
    return [f"{scratch_root}/modded_{cfg['folder_name']}" for cfg in TABLE_CONFIGS]


# Default scratch folders the (sequential) scripts populate during a run and need to clean up after. Every entry lives directly under `TEMP_DIR`. Parallel callers should pass a per-mod `scratch_root` to `modded_folders_for` / `cleanup_modded_folders` / `extract_and_load_table_data` instead.
MODDED_FOLDERS: List[str] = modded_folders_for(TEMP_DIR)


def _is_vanilla_key(table_name: str, key: Optional[str], vanilla_keys: Dict[str, Set[str]]) -> bool:
    """Return True when vanilla already has a row under `key` in `table_name`.

    Args:
        table_name (str): Table to check.
        key (Optional[str]): Primary key to look for.
        vanilla_keys (Dict[str, Set[str]]): Table name -> vanilla primary keys, from `load_vanilla_keys`.

    Returns:
        True if the key is a vanilla key.
    """
    return key in vanilla_keys.get(table_name, ())


def load_vanilla_keys(table_names: Iterable[str]) -> Dict[str, Set[str]]:
    """Load the primary keys of each vanilla table.

    Args:
        table_names (Iterable[str]): Tables to load.

    Returns:
        Table name -> set of vanilla primary keys.
    """
    keys = {}
    for table_name in table_names:
        rows, _, _ = load_tsv_data(f"{extract_tsv_data(table_name)}/db/{table_name}/data__.tsv")
        key_field = TABLE_KEY_FIELDS.get(table_name, "key")
        keys[table_name] = {row[key_field] for row in rows}
    return keys


def drop_vanilla_rows(rows: List[Dict[str, Any]], table_name: str, vanilla_keys: Dict[str, Set[str]]) -> List[Dict[str, Any]]:
    """Drop a mod's rows for keys vanilla already has. Compat packs are always on, so shipping them would push the mod's edits onto players without it.

    Args:
        rows (List[Dict[str, Any]]): The mod's rows for `table_name`.
        table_name (str): Table the rows belong to.
        vanilla_keys (Dict[str, Set[str]]): Table name -> vanilla primary keys, from `load_vanilla_keys`.

    Returns:
        The rows whose key is not in vanilla.
    """
    key_field = TABLE_KEY_FIELDS.get(table_name, "key")
    return [row for row in rows if not _is_vanilla_key(table_name, row.get(key_field), vanilla_keys)]


def _add_related(
    field_key: str,
    source_dict: Dict[str, Any],
    table_name: str,
    table_data: Dict[str, Any],
    tracker: "DuplicateTracker",
    new_data: Dict[str, List[Any]],
    vanilla_keys: Dict[str, Set[str]],
) -> Optional[Dict[str, Any]]:
    """Look up `source_dict[field_key]` in `table_data[table_name]` and, when present, append the row to its `TABLE_BUCKETS` bucket (gated by `tracker`).

    A key vanilla already has is skipped and its chain is not followed, since vanilla's own row and everything it points at already exist.

    Args:
        field_key (str): Column in `source_dict` whose value is the foreign key.
        source_dict (Dict[str, Any]): Row that owns the foreign key, e.g. a land_units row or another related row mid-chain.
        table_name (str): Target table to look the value up in.
        table_data (Dict[str, Any]): Mapping returned by `extract_and_load_table_data`.
        tracker (DuplicateTracker): Dedup state shared across all mods in the run.
        new_data (Dict[str, List[Any]]): Buckets to append to. Mutated in place.
        vanilla_keys (Dict[str, Set[str]]): Table name -> vanilla primary keys, from `load_vanilla_keys`.

    Returns:
        The looked-up row when present, or None. Returning it lets callers continue the foreign-key chain.
    """
    value = source_dict.get(field_key)
    if not value or value not in table_data[table_name] or _is_vanilla_key(table_name, value, vanilla_keys):
        return None
    entry = table_data[table_name][value]
    if tracker.should_add(table_name, entry):
        new_data[TABLE_BUCKETS[table_name]].append(entry)
    return entry


def workshop_pack_path(steam_id: str, pack_name: str) -> str:
    """Return the on-disk path for a Steam Workshop pack file.

    Args:
        steam_id (str): The Steam Workshop ID for the mod.
        pack_name (str): The pack filename including the `.pack` extension.

    Returns:
        Absolute Windows path to the pack file under the configured Steam library.
    """
    return f"{STEAM_LIBRARY_DRIVE}\\SteamLibrary\\steamapps\\workshop\\content\\1142710\\{steam_id}\\{pack_name}"


def clean_folder_name(package_name: str) -> str:
    """Convert a `.pack` filename into a folder-safe identifier.

    RPFM table names cannot end in a digit, so the trailing digit is stripped if present.

    Args:
        package_name (str): The pack filename, e.g. `mymod.pack`.

    Returns:
        A sanitized folder name with the `.pack` suffix removed, spaces replaced with underscores, and any trailing digit stripped.
    """
    folder_name = package_name.replace(".pack", "").replace(" ", "_")
    if folder_name and folder_name[-1].isdigit():
        folder_name = folder_name[:-1]
    return folder_name


def reset_pack_folders(pack_path: str, folders: Tuple[str, ...] = ("db",)) -> None:
    """Delete the named top-level folders inside a pack via the RPFM CLI.

    Doing this folder-by-folder is more reliable than passing an empty `--folder-path`, which sometimes leaves stale content behind.

    Args:
        pack_path (str): Path to the `.pack` file to mutate.
        folders (Tuple[str, ...]): Top-level folder names inside the pack to clear. Defaults to `("db",)`.
    """
    for folder in folders:
        run_rpfm_cli(["pack", "delete", "--pack-path", pack_path, "--folder-path", folder], capture_output=True)


def add_folder_to_pack(pack_path: str, source_folder: str, schema_path: str = SCHEMA_RON_PATH) -> None:
    """Add a folder to a pack via the RPFM CLI, converting any TSV files inline.

    Args:
        pack_path (str): Path to the destination `.pack` file.
        source_folder (str): RPFM `--folder-path` argument; usually `<filesystem_path>;<pack_relative_path>` or just `<filesystem_path>;`.
        schema_path (str): Path to the WH3 schema RON file used to convert TSVs to binary. Defaults to `SCHEMA_RON_PATH`.
    """
    run_rpfm_cli(["pack", "add", "--pack-path", pack_path, "--tsv-to-binary", schema_path, "--folder-path", source_folder], capture_output=True)


class DuplicateTracker:
    """Tracks `(table, primary_key)` combinations seen during a run so the same row is not written twice."""

    def __init__(self):
        self._seen: Dict[str, set] = {table_name: set() for table_name in TABLE_KEY_FIELDS}

    def should_add(self, table_name: str, entry_data: Dict[str, Any]) -> bool:
        """Return True if this entry has not yet been seen for the table. Records the entry as seen as a side effect.

        Args:
            table_name (str): The table the entry belongs to. Tables not in `TABLE_KEY_FIELDS` are always allowed through.
            entry_data (Dict[str, Any]): The row data to check, indexed by column name.

        Returns:
            True if the entry is new (and was just recorded), False if the same primary key was seen earlier for this table.
        """
        if table_name not in TABLE_KEY_FIELDS:
            return True
        key_field = TABLE_KEY_FIELDS[table_name]
        entry_key = entry_data.get(key_field)
        if entry_key is None:
            return True
        if entry_key in self._seen[table_name]:
            logging.debug(f"Skipping duplicate entry {entry_key} for table {table_name}.")
            return False
        self._seen[table_name].add(entry_key)
        return True


def extract_and_load_table_data(
    mod_path: str,
    table_configs: List[Dict[str, Any]] = TABLE_CONFIGS,
    scratch_root: str = TEMP_DIR,
) -> Optional[Dict[str, Any]]:
    """Extract every table in `table_configs` from `mod_path` and load the rows into per-table dictionaries keyed by the primary key.

    Args:
        mod_path (str): Path to the `.pack` file to extract from.
        table_configs (List[Dict[str, Any]]): Per-table extraction config. Each entry must have `table_name`, `folder_name`, and `key_field`, and may have `required`. Defaults to `TABLE_CONFIGS`.
        scratch_root (str): Folder under which the `modded_<folder_name>` extraction directories are created. Pass `f"{TEMP_DIR}/{mod_pkg}"` for parallel callers so workers do not clobber each other. Defaults to `TEMP_DIR` (sequential callers).

    Returns:
        A dictionary with three kinds of entries per table:
            `<table_name>`: dict of `key -> row dict` (always present, possibly empty).
            `<table_name>_headers`: list of headers (only present if the table existed in the pack).
            `<table_name>_version_info`: version_info row string (only present if the table existed in the pack).
        Returns None if a config marked `required=True` produced no extracted folder.
    """
    mappings: Dict[str, Any] = {}

    for config in table_configs:
        table_name = config["table_name"]
        folder_name = config["folder_name"]
        key_field = config.get("key_field", "key")
        required = config.get("required", False)

        extract_dir = f"{scratch_root}/modded_{folder_name}"
        extract_modded_tsv_data(table_name, mod_path, extract_dir)
        new_mapping: Dict[str, Any] = {}

        if os.path.exists(extract_dir):
            merged_data, headers, version_info = load_multiple_tsv_data(f"{extract_dir}/db/{table_name}", table_name)
            for row in merged_data:
                new_mapping[row[key_field]] = row
            mappings[f"{table_name}_headers"] = headers
            mappings[f"{table_name}_version_info"] = version_info
        elif required:
            return None

        mappings[table_name] = new_mapping

    return mappings


def make_new_data_buckets(key: str, with_purchasable_effects: bool = False) -> Dict[str, Any]:
    """Build the empty `new_data` dict for one land_unit, with one bucket per optional table.

    Args:
        key (str): The land_units key for this entry (used for logging only).
        with_purchasable_effects (bool): If True, include the `unit_purchasable_effect_sets` bucket (only the dynamic_rors script writes to that table). Defaults to False.

    Returns:
        Dict with `key`, `land_units`, `main_units`, optional `unit_purchasable_effect_sets`, and one empty list bucket per entry in `OPTIONAL_TABLES`, ready for `walk_land_unit_to_related_tables` to append into.
    """
    buckets: Dict[str, Any] = {"key": key}
    if with_purchasable_effects:
        buckets["unit_purchasable_effect_sets"] = []
    buckets["land_units"] = []
    buckets["main_units"] = []
    for bucket_key, _ in OPTIONAL_TABLES:
        buckets[bucket_key] = []
    return buckets


def walk_land_unit_to_related_tables(
    *,
    data: Dict[str, Any],
    main_unit_data: Dict[str, Any],
    table_data: Dict[str, Any],
    tracker: DuplicateTracker,
    new_data: Dict[str, List[Any]],
    land_units_by_key: Dict[str, Dict[str, Any]],
    vanilla_keys: Dict[str, Set[str]],
) -> None:
    """Walk the foreign-key chain from a `land_units_tables` row and append related rows into `new_data`.

    Rows whose key vanilla already has are never shipped. Compat packs are always on, so the mod's version would reach players without that mod.

    Args:
        data (Dict[str, Any]): The land_units row to walk from.
        main_unit_data (Dict[str, Any]): The main_units row for `data["key"]` (already looked up by the caller).
        table_data (Dict[str, Any]): The mapping returned by `extract_and_load_table_data`.
        tracker (DuplicateTracker): Deduplication state shared across all mods in the run.
        new_data (Dict[str, List[Any]]): Buckets to append to, built by `make_new_data_buckets`. Mutated in place.
        land_units_by_key (Dict[str, Dict[str, Any]]): The mod's land_units rows by key, as the caller will write them. Used to find the land unit `main_unit_data` actually references.
        vanilla_keys (Dict[str, Set[str]]): Table name -> vanilla primary keys, from `load_vanilla_keys`.
    """
    # A main unit can point at a land unit under a different key. Walk that one, or the pack ships a main unit whose land unit is missing.
    data = land_units_by_key.get(main_unit_data.get("land_unit"), data)
    add = functools.partial(_add_related, table_data=table_data, tracker=tracker, new_data=new_data, vanilla_keys=vanilla_keys)

    if not _is_vanilla_key("main_units_tables", main_unit_data.get("unit"), vanilla_keys):
        if tracker.should_add("main_units_tables", main_unit_data):
            new_data["main_units"].append(main_unit_data)
        ui_unit_grouping_data = add("ui_unit_group_land", main_unit_data, "ui_unit_groupings_tables")
        if ui_unit_grouping_data is not None:
            add("parent_group", ui_unit_grouping_data, "ui_unit_group_parents_tables")

    # Vanilla's own land unit and everything it points at already exist.
    if _is_vanilla_key("land_units_tables", data.get("key"), vanilla_keys):
        return
    if tracker.should_add("land_units_tables", data):
        new_data["land_units"].append(data)

    add("historical_description_text", data, "unit_description_historical_texts_tables")
    add("man_animation", data, "battle_animations_table_tables")
    add("man_entity", data, "battle_entities_tables")

    mount_data = add("mount", data, "mounts_tables")
    if mount_data is not None:
        add("entity", mount_data, "battle_entities_tables")
        add("variant", mount_data, "variants_tables")

    melee_weapon_data = add("primary_melee_weapon", data, "melee_weapons_tables")
    if melee_weapon_data is not None:
        add("scaling_damage", melee_weapon_data, "projectiles_scaling_damages_tables")

    missile_weapon_data = add("primary_missile_weapon", data, "missile_weapons_tables")
    if missile_weapon_data is not None:
        projectile_entry = add("default_projectile", missile_weapon_data, "projectiles_tables")
        if projectile_entry is not None:
            add("spawned_vortex", projectile_entry, "battle_vortexs_tables")
            add("projectile_shot_type_display", projectile_entry, "projectile_shot_type_displays_tables")
            # The game rejects a projectile whose scaling_damage row is missing, so ship it with the projectile.
            add("scaling_damage", projectile_entry, "projectiles_scaling_damages_tables")

    add("short_description_text", data, "unit_description_short_texts_tables")
    add("attribute_group", data, "unit_attributes_groups_tables")

    engine_data = add("engine", data, "battlefield_engines_tables")
    if engine_data is not None:
        add("battle_entity", engine_data, "battle_entities_tables")

    add("spacing", data, "unit_spacings_tables")
    add("first_person", data, "first_person_engines_tables")

    articulated_vehicle_data = add("articulated_record", data, "land_unit_articulated_vehicles_tables")
    if articulated_vehicle_data is not None:
        add("articulated_entity", articulated_vehicle_data, "battle_entities_tables")



def _replace_version_info_filename(version_info: str, new_filename: str) -> str:
    """Swap the trailing path component in a version_info row's path field with `new_filename`.

    Args:
        version_info (str): Full version_info row, with shape `#table_name;version;db/table/<existing_filename>`.
        new_filename (str): Replacement value for the trailing path component.

    Returns:
        Updated version_info string with the trailing path component replaced.
    """
    return version_info.replace(version_info.split("/")[-1], new_filename)


def write_optional_tables(
    new_data: Dict[str, Any],
    output_root: str,
    file_suffix: str,
    table_data: Dict[str, Any],
    tables_to_sort: List[str],
    writer: Callable[..., None] = write_updated_tsv_file,
) -> None:
    """Write each non-empty optional-table bucket in `new_data` and record the destination paths in `tables_to_sort`.

    Args:
        new_data (Dict[str, Any]): Per-unit buckets produced by `walk_land_unit_to_related_tables`.
        output_root (str): Root output folder (e.g. `./temp/!!!!!!!_nanu_dynamic_rors_compat`); each bucket is written under `<output_root>/db/<table_name>`.
        file_suffix (str): File suffix used for the TSV filename and the path component of each table's version_info row.
        table_data (Dict[str, Any]): The mapping returned by `extract_and_load_table_data`. Used to look up per-table `headers` and `version_info`.
        tables_to_sort (List[str]): Mutated in place; each newly-written table's directory is appended if not already present, so the caller can sort them all afterwards.
        writer (Callable[..., None]): Takes the same arguments as `write_updated_tsv_file`. Pass a `TsvAppendBuffer.add` to write each file once.
            Defaults to `write_updated_tsv_file`.
    """
    for bucket_key, table_name in OPTIONAL_TABLES:
        if not new_data[bucket_key]:
            continue
        version_info = _replace_version_info_filename(table_data[f"{table_name}_version_info"], file_suffix)
        writer(
            new_data[bucket_key],
            table_data[f"{table_name}_headers"],
            version_info,
            f"{output_root}/db/{table_name}",
            file_suffix,
        )
        path = f"{output_root}/db/{table_name}"
        if path not in tables_to_sort:
            tables_to_sort.append(path)


def cleanup_modded_folders(scratch_root: Optional[str] = None) -> None:
    """Wipe every transient `modded_*` folder a compat-pack run produces.

    Args:
        scratch_root (Optional[str]): When provided, wipe only the per-mod-namespaced folders under `scratch_root` (used by parallel callers, e.g. `f"{TEMP_DIR}/{mod_pkg}"`). When None, wipe the default `MODDED_FOLDERS` that sit directly under `TEMP_DIR` (sequential callers).
    """
    if scratch_root is None:
        cleanup_folders(MODDED_FOLDERS)
    else:
        cleanup_folders(modded_folders_for(scratch_root))
