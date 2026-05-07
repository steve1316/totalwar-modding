"""Shared pipeline primitives for the update_*.py compat-pack scripts.

The dynamic_rors and double_unit_size scripts each walk every supported mod, follow foreign-key chains from `land_units_tables` to mounts, weapons, projectiles, etc., dedupe across mods, and write trimmed copies into a compat pack. This module owns the bits that are identical between them.
"""

import logging
import os
import shutil
import subprocess
from typing import Any, Dict, List, Optional, Tuple

from utilities import (
    cleanup_folders,
    extract_model_paths_from_variantmeshdefinition,
    extract_modded_tsv_data,
    load_multiple_tsv_data,
    sort_tsv_data,
    write_updated_tsv_file,
    STEAM_LIBRARY_DRIVE,
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


# Scratch folders the scripts populate during a run and need to clean up after.
MODDED_FOLDERS: List[str] = [
    "./modded_units_to_groupings_military_permissions_tables",
    "./modded_land_units_tables",
    "./modded_main_units_tables",
    "./modded_unit_description_historical_texts_tables",
    "./modded_battle_animations_table_tables",
    "./modded_battle_entities_tables",
    "./modded_mounts_tables",
    "./modded_melee_weapons_tables",
    "./modded_missile_weapons_tables",
    "./modded_unit_description_short_texts_tables",
    "./modded_unit_attributes_groups_tables",
    "./modded_battlefield_engines_tables",
    "./modded_projectiles_tables",
    "./modded_battle_vortexs_tables",
    "./modded_projectiles_scaling_damages_tables",
    "./modded_projectile_shot_type_displays_tables",
    "./modded_unit_spacings_tables",
    "./modded_first_person_engines_tables",
    "./modded_land_unit_articulated_vehicles_tables",
    "./modded_ui_unit_groupings_tables",
    "./modded_ui_unit_group_parents_tables",
    "./modded_variants_tables",
    "./modded_variantmeshes",
]


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


def reset_pack_folders(pack_path: str, folders: Tuple[str, ...] = ("db", "variantmeshes")) -> None:
    """Delete the named top-level folders inside a pack via the RPFM CLI.

    Doing this folder-by-folder is more reliable than passing an empty `--folder-path`, which sometimes leaves stale content behind.

    Args:
        pack_path (str): Path to the `.pack` file to mutate.
        folders (Tuple[str, ...]): Top-level folder names inside the pack to clear. Defaults to `("db", "variantmeshes")`.
    """
    for folder in folders:
        subprocess.run(
            ["./rpfm_cli.exe", "--game", "warhammer_3", "pack", "delete", "--pack-path", pack_path, "--folder-path", folder],
            capture_output=True,
        )


def add_folder_to_pack(pack_path: str, source_folder: str, schema_path: str = SCHEMA_RON_PATH) -> None:
    """Add a folder to a pack via the RPFM CLI, converting any TSV files inline.

    Args:
        pack_path (str): Path to the destination `.pack` file.
        source_folder (str): RPFM `--folder-path` argument; usually `<filesystem_path>;<pack_relative_path>` or just `<filesystem_path>;`.
        schema_path (str): Path to the WH3 schema RON file used to convert TSVs to binary. Defaults to `SCHEMA_RON_PATH`.
    """
    subprocess.run(
        ["./rpfm_cli.exe", "--game", "warhammer_3", "pack", "add", "--pack-path", pack_path, "--tsv-to-binary", schema_path, "--folder-path", source_folder],
        capture_output=True,
    )


def extract_variantmeshes_folder(mod_path: str, dest: str = "./modded_variantmeshes") -> None:
    """Extract the `variantmeshes` folder from a mod pack to the named destination.

    Args:
        mod_path (str): Path to the source `.pack` file.
        dest (str): Local destination folder. Defaults to `./modded_variantmeshes`.
    """
    subprocess.run(
        ["./rpfm_cli.exe", "--game", "warhammer_3", "pack", "extract", "--pack-path", mod_path, "--folder-path", f"variantmeshes;{dest}"],
        capture_output=True,
    )


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


def extract_and_load_table_data(mod_path: str, table_configs: List[Dict[str, Any]] = TABLE_CONFIGS) -> Optional[Dict[str, Any]]:
    """Extract every table in `table_configs` from `mod_path` and load the rows into per-table dictionaries keyed by the primary key.

    Args:
        mod_path (str): Path to the `.pack` file to extract from.
        table_configs (List[Dict[str, Any]]): Per-table extraction config. Each entry must have `table_name`, `folder_name`, and `key_field`, and may have `required`. Defaults to `TABLE_CONFIGS`.

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

        extract_modded_tsv_data(table_name, mod_path, f"./modded_{folder_name}")
        new_mapping: Dict[str, Any] = {}

        if os.path.exists(f"./modded_{folder_name}"):
            merged_data, headers, version_info = load_multiple_tsv_data(f"./modded_{folder_name}/db/{table_name}", table_name)
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
    vanilla_mounts_keys: Optional[set] = None,
    variant_mesh_definitions_to_add: Optional[List[str]] = None,
) -> None:
    """Walk the foreign-key chain from a `land_units_tables` row, append related rows into `new_data`, and record any vanilla-mount variantmeshdefinitions to copy into the compat pack.

    Args:
        data (Dict[str, Any]): The land_units row to walk from.
        main_unit_data (Dict[str, Any]): The main_units row for `data["key"]` (already looked up by the caller).
        table_data (Dict[str, Any]): The mapping returned by `extract_and_load_table_data`.
        tracker (DuplicateTracker): Deduplication state shared across all mods in the run.
        new_data (Dict[str, List[Any]]): Buckets to append to, built by `make_new_data_buckets`. Mutated in place.
        vanilla_mounts_keys (Optional[set]): Set of vanilla mount keys; only mounts whose key is in this set have their variantmeshdefinitions captured. If None, no variantmesh capture happens.
        variant_mesh_definitions_to_add (Optional[List[str]]): List that is appended to with paths of variantmeshdefinition files to move into the compat pack. Mutated in place.
    """
    if tracker.should_add("main_units_tables", main_unit_data):
        new_data["main_units"].append(main_unit_data)
    if tracker.should_add("land_units_tables", data):
        new_data["land_units"].append(data)

    if data.get("historical_description_text") and data["historical_description_text"] in table_data["unit_description_historical_texts_tables"]:
        entry = table_data["unit_description_historical_texts_tables"][data["historical_description_text"]]
        if tracker.should_add("unit_description_historical_texts_tables", entry):
            new_data["unit_description_historical_texts"].append(entry)

    if data.get("man_animation") and data["man_animation"] in table_data["battle_animations_table_tables"]:
        entry = table_data["battle_animations_table_tables"][data["man_animation"]]
        if tracker.should_add("battle_animations_table_tables", entry):
            new_data["battle_animations"].append(entry)

    if data.get("man_entity") and data["man_entity"] in table_data["battle_entities_tables"]:
        entry = table_data["battle_entities_tables"][data["man_entity"]]
        if tracker.should_add("battle_entities_tables", entry):
            new_data["battle_entities"].append(entry)

    if data.get("mount") and data["mount"] in table_data["mounts_tables"]:
        mount_data = table_data["mounts_tables"][data["mount"]]
        if tracker.should_add("mounts_tables", mount_data):
            new_data["mounts"].append(mount_data)
        mount_battle_entity = mount_data.get("entity")
        if mount_battle_entity and mount_battle_entity in table_data["battle_entities_tables"]:
            entry = table_data["battle_entities_tables"][mount_battle_entity]
            if tracker.should_add("battle_entities_tables", entry):
                new_data["battle_entities"].append(entry)
        if mount_data.get("variant") and mount_data["variant"] in table_data["variants_tables"]:
            variant_data = table_data["variants_tables"][mount_data["variant"]]
            if tracker.should_add("variants_tables", variant_data):
                new_data["variants"].append(variant_data)

            # Capture variantmeshdefinitions for vanilla mounts so the compat pack remains standalone.
            if (
                vanilla_mounts_keys is not None
                and variant_mesh_definitions_to_add is not None
                and mount_data.get("key") in vanilla_mounts_keys
                and variant_data.get("variant_filename")
                and os.path.exists(f"./modded_variantmeshes/variantmeshes/variantmeshdefinitions/{variant_data['variant_filename']}.variantmeshdefinition")
            ):
                variant_mesh_definitions_to_add.append(
                    f"./modded_variantmeshes/variantmeshes/variantmeshdefinitions/{variant_data['variant_filename']}.variantmeshdefinition"
                )

    if data.get("primary_melee_weapon") and data["primary_melee_weapon"] in table_data["melee_weapons_tables"]:
        melee_weapon_data = table_data["melee_weapons_tables"][data["primary_melee_weapon"]]
        if tracker.should_add("melee_weapons_tables", melee_weapon_data):
            new_data["melee_weapons"].append(melee_weapon_data)
        if melee_weapon_data.get("scaling_damage") and melee_weapon_data["scaling_damage"] in table_data["projectiles_scaling_damages_tables"]:
            entry = table_data["projectiles_scaling_damages_tables"][melee_weapon_data["scaling_damage"]]
            if tracker.should_add("projectiles_scaling_damages_tables", entry):
                new_data["projectiles_scaling_damages"].append(entry)

    if data.get("primary_missile_weapon") and data["primary_missile_weapon"] in table_data["missile_weapons_tables"]:
        missile_weapon_data = table_data["missile_weapons_tables"][data["primary_missile_weapon"]]
        if tracker.should_add("missile_weapons_tables", missile_weapon_data):
            new_data["missile_weapons"].append(missile_weapon_data)
        if missile_weapon_data.get("default_projectile") and missile_weapon_data["default_projectile"] in table_data["projectiles_tables"]:
            entry = table_data["projectiles_tables"][missile_weapon_data["default_projectile"]]
            if tracker.should_add("projectiles_tables", entry):
                new_data["projectiles"].append(entry)
            if entry.get("spawned_vortex") and entry["spawned_vortex"] in table_data["battle_vortexs_tables"]:
                vortex_entry = table_data["battle_vortexs_tables"][entry["spawned_vortex"]]
                if tracker.should_add("battle_vortexs_tables", vortex_entry):
                    new_data["battle_vortexs"].append(vortex_entry)
            if entry.get("projectile_shot_type_display") and entry["projectile_shot_type_display"] in table_data["projectile_shot_type_displays_tables"]:
                display_entry = table_data["projectile_shot_type_displays_tables"][entry["projectile_shot_type_display"]]
                if tracker.should_add("projectile_shot_type_displays_tables", display_entry):
                    new_data["projectile_shot_type_displays"].append(display_entry)
        if missile_weapon_data.get("scaling_damage") and missile_weapon_data["scaling_damage"] in table_data["projectiles_scaling_damages_tables"]:
            entry = table_data["projectiles_scaling_damages_tables"][missile_weapon_data["scaling_damage"]]
            if tracker.should_add("projectiles_scaling_damages_tables", entry):
                new_data["projectiles_scaling_damages"].append(entry)

    if data.get("short_description_text") and data["short_description_text"] in table_data["unit_description_short_texts_tables"]:
        entry = table_data["unit_description_short_texts_tables"][data["short_description_text"]]
        if tracker.should_add("unit_description_short_texts_tables", entry):
            new_data["unit_description_short_texts"].append(entry)

    if data.get("attribute_group") and data["attribute_group"] in table_data["unit_attributes_groups_tables"]:
        entry = table_data["unit_attributes_groups_tables"][data["attribute_group"]]
        if tracker.should_add("unit_attributes_groups_tables", entry):
            new_data["unit_attributes_groups"].append(entry)

    if data.get("engine") and data["engine"] in table_data["battlefield_engines_tables"]:
        engine_data = table_data["battlefield_engines_tables"][data["engine"]]
        if tracker.should_add("battlefield_engines_tables", engine_data):
            new_data["battlefield_engines"].append(engine_data)
        if engine_data.get("battle_entity") and engine_data["battle_entity"] in table_data["battle_entities_tables"]:
            entry = table_data["battle_entities_tables"][engine_data["battle_entity"]]
            if tracker.should_add("battle_entities_tables", entry):
                new_data["battle_entities"].append(entry)

    if data.get("spacing") and data["spacing"] in table_data["unit_spacings_tables"]:
        entry = table_data["unit_spacings_tables"][data["spacing"]]
        if tracker.should_add("unit_spacings_tables", entry):
            new_data["unit_spacings"].append(entry)

    if data.get("first_person") and data["first_person"] in table_data["first_person_engines_tables"]:
        entry = table_data["first_person_engines_tables"][data["first_person"]]
        if tracker.should_add("first_person_engines_tables", entry):
            new_data["first_person_engines"].append(entry)

    if data.get("articulated_record") and data["articulated_record"] in table_data["land_unit_articulated_vehicles_tables"]:
        articulated_vehicle_data = table_data["land_unit_articulated_vehicles_tables"][data["articulated_record"]]
        if tracker.should_add("land_unit_articulated_vehicles_tables", articulated_vehicle_data):
            new_data["land_unit_articulated_vehicles"].append(articulated_vehicle_data)
        if articulated_vehicle_data.get("articulated_entity") and articulated_vehicle_data["articulated_entity"] in table_data["battle_entities_tables"]:
            entry = table_data["battle_entities_tables"][articulated_vehicle_data["articulated_entity"]]
            if tracker.should_add("battle_entities_tables", entry):
                new_data["battle_entities"].append(entry)

    if main_unit_data.get("ui_unit_group_land") and main_unit_data["ui_unit_group_land"] in table_data["ui_unit_groupings_tables"]:
        ui_unit_grouping_data = table_data["ui_unit_groupings_tables"][main_unit_data["ui_unit_group_land"]]
        if tracker.should_add("ui_unit_groupings_tables", ui_unit_grouping_data):
            new_data["ui_unit_groupings"].append(ui_unit_grouping_data)
        if ui_unit_grouping_data.get("parent_group") and ui_unit_grouping_data["parent_group"] in table_data["ui_unit_group_parents_tables"]:
            entry = table_data["ui_unit_group_parents_tables"][ui_unit_grouping_data["parent_group"]]
            if tracker.should_add("ui_unit_group_parents_tables", entry):
                new_data["ui_unit_group_parents"].append(entry)


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
) -> None:
    """Write each non-empty optional-table bucket in `new_data` and record the destination paths in `tables_to_sort`.

    Args:
        new_data (Dict[str, Any]): Per-unit buckets produced by `walk_land_unit_to_related_tables`.
        output_root (str): Root output folder (e.g. `./!!!!!!!_nanu_dynamic_rors_compat`); each bucket is written under `<output_root>/db/<table_name>`.
        file_suffix (str): File suffix used for the TSV filename and the path component of each table's version_info row.
        table_data (Dict[str, Any]): The mapping returned by `extract_and_load_table_data`. Used to look up per-table `headers` and `version_info`.
        tables_to_sort (List[str]): Mutated in place; each newly-written table's directory is appended if not already present, so the caller can sort them all afterwards.
    """
    for bucket_key, table_name in OPTIONAL_TABLES:
        if not new_data[bucket_key]:
            continue
        version_info = _replace_version_info_filename(table_data[f"{table_name}_version_info"], file_suffix)
        write_updated_tsv_file(
            new_data[bucket_key],
            table_data[f"{table_name}_headers"],
            version_info,
            f"{output_root}/db/{table_name}",
            file_suffix,
        )
        path = f"{output_root}/db/{table_name}"
        if path not in tables_to_sort:
            tables_to_sort.append(path)


def move_variantmesh_definitions(variant_mesh_definitions: List[str], output_root: str) -> None:
    """Move variantmeshdefinitions and their referenced wh_variantmodels into the compat pack folder structure.

    Each definition file is moved out of `./modded_variantmeshes/...` into `<output_root>/variantmeshes/variantmeshdefinitions/`, then any model paths referenced inside it are moved out of `./modded_variantmeshes/variantmeshes/wh_variantmodels/` into `<output_root>/variantmeshes/wh_variantmodels/`. Missing source files are skipped silently.

    Args:
        variant_mesh_definitions (List[str]): Source paths for the variantmeshdefinition files to move. May contain duplicates; missing entries are skipped.
        output_root (str): Root output folder (e.g. `./!!!!!!!_nanu_dynamic_rors_compat`).
    """
    if not variant_mesh_definitions:
        return
    for variant_mesh_definition in variant_mesh_definitions:
        if not os.path.exists(variant_mesh_definition):
            continue
        os.makedirs(f"{output_root}/variantmeshes/variantmeshdefinitions", exist_ok=True)
        try:
            shutil.move(
                variant_mesh_definition,
                f"{output_root}/variantmeshes/variantmeshdefinitions/{os.path.basename(variant_mesh_definition)}",
            )
            mesh_model_paths = extract_model_paths_from_variantmeshdefinition(
                f"{output_root}/variantmeshes/variantmeshdefinitions/{os.path.basename(variant_mesh_definition)}"
            )
            for mesh_model_path in mesh_model_paths:
                target = f"{output_root}/variantmeshes/wh_variantmodels/{mesh_model_path}"
                if os.path.exists(target):
                    os.remove(target)
                os.makedirs(f"{output_root}/variantmeshes/wh_variantmodels", exist_ok=True)
                source = f"./modded_variantmeshes/variantmeshes/wh_variantmodels/{mesh_model_path}"
                if os.path.exists(source):
                    shutil.move(source, target)
        except FileNotFoundError:
            logging.error(f"variantmeshdefinition not found: {variant_mesh_definition}.")


def cleanup_modded_folders() -> None:
    """Wipe every transient `./modded_*` folder a compat-pack run produces."""
    cleanup_folders(MODDED_FOLDERS)
