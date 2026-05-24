"""Script to update the modified attribute mods from the Steam Workshop to account for latest changes to the vanilla and modded data tables."""

import logging
import time
import shutil
import os
from typing import Callable, List, Dict, Tuple
from utilities import (
    extract_tsv_data,
    extract_modded_tsv_data,
    load_tsv_data,
    load_multiple_tsv_data,
    log_elapsed_time,
    make_common_argparser,
    run_parallel,
    setup_script_logging,
    write_updated_tsv_file,
    merge_move,
    ensure_temp_dir,
    TEMP_DIR,
)
from supported_mods import SUPPORTED_MODS
from pipeline import add_folder_to_pack, reset_pack_folders, workshop_pack_path


MODS_AND_STEAM_WORKSHOP_IDS = [
    ("!!!!!!!50meleeattackspeed_compat", "3311361199"),
    ("!!!!!!!firing_arc_120_compat", "3311361345"),
    ("!!!!!!!double_projectile_velocity_compat", "3311361464"),
]
PREPEND_MELEE_TABLE_FILE_NAME = MODS_AND_STEAM_WORKSHOP_IDS[0][0]
PREPEND_RANGED_ARC_TABLE_FILE_NAME = MODS_AND_STEAM_WORKSHOP_IDS[1][0]
PREPEND_VELOCITY_TABLE_FILE_NAME = MODS_AND_STEAM_WORKSHOP_IDS[2][0]

MELEE_WEAPONS_TABLE_VERSION_NUMBER = 25
PROJECTILES_SCALING_DAMAGES_TABLE_VERSION_NUMBER = 0
BATTLE_ENTITIES_TABLE_VERSION_NUMBER = 38
BATTLE_VORTEXS_TABLE_VERSION_NUMBER = 19
PROJECTILE_SHOT_TYPE_DISPLAYS_TABLE_VERSION_NUMBER = 1
PROJECTILES_TABLE_VERSION_NUMBER = 53


def update_melee_attack_intervals(unit_data: List[Dict]):
    """Adjust melee attack intervals to improve combat responsiveness.

    Args:
        unit_data (List[Dict]): List of unit data dictionaries from battle_entities_tables.

    Returns:
        List of modified unit data with updated attack intervals.
    """
    modified_data = []

    for row in unit_data:
        try:
            current_interval = row["melee_attack_interval"]
            modified_row = row.copy()
            modified_row["melee_attack_interval"] = str(float(current_interval) / 2)
            logging.debug(f"Updated {row['key']} melee attack interval from {current_interval} to {modified_row['melee_attack_interval']}.")
            modified_data.append(modified_row)
        except ValueError:
            logging.debug(f"Invalid interval value: {current_interval} - preserving original")
            modified_data.append(row)
        except KeyError:
            modified_data.append(row)

    return modified_data


def update_rows_for_120_degree_ranged_attacks(joined_data: List[Dict]):
    """Adjust fire arc values for ranged units to ensure minimum 120 degree coverage.

    Args:
        joined_data (List[Dict]): List of dictionaries representing unit data rows from battle_entities_tables db.

    Returns:
        Modified list with updated fire_arc_close values where applicable.
    """
    # Only modifies values between 0 and 120 (exclusive).
    # Preserves existing 0, negative, or values >= 120.
    for row in joined_data:
        current_arc = float(row["fire_arc_close"])
        if 0 < current_arc < 120:
            row["fire_arc_close"] = "120"
            logging.debug(f"Updated {row['key']} firing arc from {current_arc} to 120 degrees.")

    return joined_data


def adjust_muzzle_velocities(projectile_data: List[Dict]):
    """Double velocity values for valid positive entries.

    Args:
        projectile_data: List of projectile data dictionaries.

    Returns:
        List of modified projectile data with updated velocities.
    """
    modified = []
    for row in projectile_data:
        try:
            velocity = float(row["muzzle_velocity"])
            new_row = row.copy()
            if velocity > 0:
                new_row["muzzle_velocity"] = str(velocity * 2)
                logging.debug(f"Updated {row['key']} projectile velocity from {velocity} to {new_row['muzzle_velocity']}.")
            else:
                logging.debug(f"Invalid velocity ({velocity}) - preserving original value")

            modified.append(new_row)
        except ValueError as e:
            logging.debug(f"Error processing row: {str(e)} - using original data")
            modified.append(row)
        except KeyError:
            modified.append(row)

    return modified


def _process_attribute_tables(
    is_vanilla: bool,
    folder_name: str,
    prepend_name: str,
    vanilla_table_name: str,
    tables: List[Tuple[str, int]],
    transform_fn: Callable[[List[Dict]], List[Dict]],
) -> None:
    """Walk a set of `(table_name, version_number)` pairs, transform each via `transform_fn`, and write the result into the per-attribute compat-pack build dir.

    The vanilla branch fires only when `is_vanilla` is true and the current table matches `vanilla_table_name` (so non-vanilla tables in the list are skipped during a vanilla run). The modded branch fires when the per-mod scratch dir exists and contains TSVs.

    Args:
        is_vanilla (bool): True when called for the special vanilla entry, False for modded mods.
        folder_name (str): Per-mod scratch dir name under `TEMP_DIR` for the modded branch (`"vanilla"` for vanilla).
        prepend_name (str): Per-attribute prepend constant (e.g. `PREPEND_MELEE_TABLE_FILE_NAME`) used to namespace the output.
        vanilla_table_name (str): Table whose `temp/vanilla_<name>` extraction triggers the vanilla branch.
        tables (List[Tuple[str, int]]): Tables to process. Each entry is `(table_name, version_number)`.
        transform_fn (Callable[[List[Dict]], List[Dict]]): Row transformer applied to the loaded TSV data.
    """
    for table_name, table_version_number in tables:
        sort_key = "vortex_key" if table_name == "battle_vortexs_tables" else "key"
        if is_vanilla and table_name == vanilla_table_name and os.path.exists(f"{TEMP_DIR}/vanilla_{vanilla_table_name}"):
            data, headers, version_info = load_tsv_data(f"{TEMP_DIR}/vanilla_{vanilla_table_name}/db/{table_name}/data__.tsv")
            version_info = version_info.replace("data__", f"{prepend_name}_vanilla_and_dlc")
            updated = sorted(transform_fn(data), key=lambda x: x[sort_key])
            write_updated_tsv_file(updated, headers, version_info, f"{TEMP_DIR}/{prepend_name}/db/{table_name}", f"{prepend_name}_vanilla_and_dlc")
        elif os.path.exists(f"{TEMP_DIR}/{folder_name}/db/{table_name}") and any(file.endswith(".tsv") for file in os.listdir(f"{TEMP_DIR}/{folder_name}/db/{table_name}")):
            logging.info(f"There are TSV files in {folder_name}/db/{table_name}.")
            data, headers, _ = load_multiple_tsv_data(f"{TEMP_DIR}/{folder_name}/db/{table_name}")
            version_info = f"#{table_name};{table_version_number};db/{table_name}/{prepend_name}_{folder_name}"
            updated = sorted(transform_fn(data), key=lambda x: x[sort_key])
            write_updated_tsv_file(updated, headers, version_info, f"{TEMP_DIR}/{prepend_name}/db/{table_name}", f"{prepend_name}_{folder_name}")


def process_mod(mod: Dict) -> None:
    """Process one mod's modified-attribute tables and write its contribution into the compat-pack build dirs.

    The output TSV filenames include `folder_name` (per-mod), so multiple workers can write into the same `{TEMP_DIR}/{PREPEND_*}/db/...` folders without colliding. The vanilla branch is only entered by the single mod whose `package_name == "vanilla"`, and the caller is expected to run that one sequentially before any threaded calls.

    Args:
        mod (Dict): Entry from `SUPPORTED_MODS`. Must have `package_name`; non-vanilla entries must also have `path` and `modified_attributes`.
    """
    is_vanilla = False
    if mod["package_name"] == "vanilla":
        folder_name = "vanilla"
        is_vanilla = True
    else:
        # Table names cannot end in numbers.
        folder_name = mod["package_name"].replace(".pack", "").replace(" ", "_")
        if folder_name[-1].isdigit():
            folder_name = folder_name[:-1]

    if "modified_attributes" not in mod:
        return

    # For each modified attribute, extract the relevant tables.
    if "melee" in mod["modified_attributes"]:
        if is_vanilla:
            extract_tsv_data("melee_weapons_tables")
        else:
            extract_modded_tsv_data("melee_weapons_tables", mod["path"], f"{TEMP_DIR}/{folder_name}")
            extract_modded_tsv_data("projectiles_scaling_damages_tables", mod["path"], f"{TEMP_DIR}/{folder_name}")
    if "ranged_arc" in mod["modified_attributes"]:
        if is_vanilla:
            extract_tsv_data("battle_entities_tables")
        else:
            extract_modded_tsv_data("battle_entities_tables", mod["path"], f"{TEMP_DIR}/{folder_name}")
    if "velocity" in mod["modified_attributes"]:
        if is_vanilla:
            extract_tsv_data("projectiles_tables")
        else:
            extract_modded_tsv_data("battle_vortexs_tables", mod["path"], f"{TEMP_DIR}/{folder_name}")
            extract_modded_tsv_data("projectile_shot_type_displays_tables", mod["path"], f"{TEMP_DIR}/{folder_name}")
            extract_modded_tsv_data("projectiles_scaling_damages_tables", mod["path"], f"{TEMP_DIR}/{folder_name}")
            extract_modded_tsv_data("projectiles_tables", mod["path"], f"{TEMP_DIR}/{folder_name}")

    logging.info(f"Extracted all relevant TSV data files for {folder_name}.")

    # Update the melee attack intervals.
    if "melee" in mod["modified_attributes"]:
        _process_attribute_tables(
            is_vanilla,
            folder_name,
            PREPEND_MELEE_TABLE_FILE_NAME,
            "melee_weapons_tables",
            [("melee_weapons_tables", MELEE_WEAPONS_TABLE_VERSION_NUMBER), ("projectiles_scaling_damages_tables", PROJECTILES_SCALING_DAMAGES_TABLE_VERSION_NUMBER)],
            update_melee_attack_intervals,
        )

    # Update the ranged firing arcs.
    if "ranged_arc" in mod["modified_attributes"]:
        _process_attribute_tables(
            is_vanilla,
            folder_name,
            PREPEND_RANGED_ARC_TABLE_FILE_NAME,
            "battle_entities_tables",
            [("battle_entities_tables", BATTLE_ENTITIES_TABLE_VERSION_NUMBER)],
            update_rows_for_120_degree_ranged_attacks,
        )

    # Update the projectile velocities.
    if "velocity" in mod["modified_attributes"]:
        _process_attribute_tables(
            is_vanilla,
            folder_name,
            PREPEND_VELOCITY_TABLE_FILE_NAME,
            "projectiles_tables",
            [
                ("battle_vortexs_tables", BATTLE_VORTEXS_TABLE_VERSION_NUMBER),
                ("projectile_shot_type_displays_tables", PROJECTILE_SHOT_TYPE_DISPLAYS_TABLE_VERSION_NUMBER),
                ("projectiles_scaling_damages_tables", PROJECTILES_SCALING_DAMAGES_TABLE_VERSION_NUMBER),
                ("projectiles_tables", PROJECTILES_TABLE_VERSION_NUMBER),
            ],
            adjust_muzzle_velocities,
        )

    if is_vanilla:
        shutil.rmtree(f"{TEMP_DIR}/vanilla_melee_weapons_tables", ignore_errors=True)
        shutil.rmtree(f"{TEMP_DIR}/vanilla_battle_entities_tables", ignore_errors=True)
        shutil.rmtree(f"{TEMP_DIR}/vanilla_projectiles_tables", ignore_errors=True)
    else:
        shutil.rmtree(f"{TEMP_DIR}/{folder_name}", ignore_errors=True)


if __name__ == "__main__":
    setup_script_logging()
    start_time = time.time()

    # Get arguments from the CLI.
    args = make_common_argparser().parse_args()
    if args.reset:
        logging.info("Will reset folders in the packfile before writing.")
        for mod_name, steam_workshop_id in MODS_AND_STEAM_WORKSHOP_IDS:
            try:
                shutil.rmtree(f"../warhammer3_mods/{mod_name}/db")
            except FileNotFoundError:
                pass

    ensure_temp_dir()

    # The vanilla pass writes the shared `_vanilla_and_dlc` TSVs into the compat-pack build dirs and is the only producer of `temp/vanilla_*` extracts. Run it serially before the pool so workers never race on those paths.
    vanilla_mods = [m for m in SUPPORTED_MODS if m["package_name"] == "vanilla"]
    modded_mods = [m for m in SUPPORTED_MODS if m["package_name"] != "vanilla"]

    for mod in vanilla_mods:
        process_mod(mod)

    logging.info(f"Processing {len(modded_mods)} modded mods with {args.workers} worker thread(s).")
    run_parallel(modded_mods, process_mod, args.workers, label_fn=lambda m: f"mod {m.get('package_name', '<unknown>')}")

    # After processing all mods, move the final folders to their destinations.
    for folder_name in [PREPEND_MELEE_TABLE_FILE_NAME, PREPEND_RANGED_ARC_TABLE_FILE_NAME, PREPEND_VELOCITY_TABLE_FILE_NAME]:
        if os.path.exists(f"{TEMP_DIR}/{folder_name}"):
            logging.info(f"Moving {folder_name} to ../warhammer3_mods/.")
            merge_move(f"{TEMP_DIR}/{folder_name}", "../warhammer3_mods/")

    for mod_name, steam_workshop_id in MODS_AND_STEAM_WORKSHOP_IDS:
        pack_path = workshop_pack_path(steam_workshop_id, f"{mod_name}.pack")
        if args.reset:
            reset_pack_folders(pack_path, ("db",))
        add_folder_to_pack(pack_path, f"../warhammer3_mods/{mod_name}/db;")

    log_elapsed_time("updating modified attribute mods", start_time)
