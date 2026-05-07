"""Script to update the modified attribute mods from the Steam Workshop to account for latest changes to the vanilla and modded data tables."""

import logging
import time
import shutil
import os
import argparse
from typing import List, Dict
from utilities import (
    extract_tsv_data,
    extract_modded_tsv_data,
    load_tsv_data,
    load_multiple_tsv_data,
    write_updated_tsv_file,
    merge_move,
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


if __name__ == "__main__":
    logging.basicConfig(format="%(asctime)s - %(levelname)s - %(message)s", level=logging.INFO)
    start_time = time.time()

    # Get arguments from argparse.
    parser = argparse.ArgumentParser()
    parser.add_argument("--reset", action="store_true", help="Reset the script.")
    args = parser.parse_args()
    if args.reset:
        logging.info("Will reset folders in the packfile before writing.")
        for mod_name, steam_workshop_id in MODS_AND_STEAM_WORKSHOP_IDS:
            try:
                shutil.rmtree(f"../warhammer3_mods/{mod_name}/db")
            except FileNotFoundError:
                pass

    for mod in SUPPORTED_MODS:
        is_vanilla = False
        if mod["package_name"] == "vanilla":
            folder_name = "vanilla"
            is_vanilla = True
        else:
            # Table names cannot end in numbers.
            folder_name = mod["package_name"].replace(".pack", "").replace(" ", "_")
            if folder_name[-1].isdigit():
                folder_name = folder_name[:-1]

        if "modified_attributes" in mod:
            # For each modified attribute, extract the relevant tables.
            if "melee" in mod["modified_attributes"]:
                if is_vanilla:
                    extract_tsv_data("melee_weapons_tables")
                else:
                    extract_modded_tsv_data("melee_weapons_tables", mod["path"], f"./{folder_name}")
                    extract_modded_tsv_data("projectiles_scaling_damages_tables", mod["path"], f"./{folder_name}")
            if "ranged_arc" in mod["modified_attributes"]:
                if is_vanilla:
                    extract_tsv_data("battle_entities_tables")
                else:
                    extract_modded_tsv_data("battle_entities_tables", mod["path"], f"./{folder_name}")
            if "velocity" in mod["modified_attributes"]:
                if is_vanilla:
                    extract_tsv_data("projectiles_tables")
                else:
                    extract_modded_tsv_data("battle_vortexs_tables", mod["path"], f"./{folder_name}")
                    extract_modded_tsv_data("projectile_shot_type_displays_tables", mod["path"], f"./{folder_name}")
                    extract_modded_tsv_data("projectiles_scaling_damages_tables", mod["path"], f"./{folder_name}")
                    extract_modded_tsv_data("projectiles_tables", mod["path"], f"./{folder_name}")

            logging.info(f"Extracted all relevant TSV data files for {folder_name}.")

            # Update the melee attack intervals.
            if "melee" in mod["modified_attributes"]:
                for table_name, table_version_number in [
                    ("melee_weapons_tables", MELEE_WEAPONS_TABLE_VERSION_NUMBER),
                    ("projectiles_scaling_damages_tables", PROJECTILES_SCALING_DAMAGES_TABLE_VERSION_NUMBER),
                ]:
                    if is_vanilla and table_name == "melee_weapons_tables" and os.path.exists(f"./vanilla_melee_weapons_tables"):
                        melee_data, headers, version_info = load_tsv_data(f"./vanilla_melee_weapons_tables/db/{table_name}/data__.tsv")
                        version_info = version_info.replace("data__", f"{PREPEND_MELEE_TABLE_FILE_NAME}_vanilla_and_dlc")
                        updated_melee_data = update_melee_attack_intervals(melee_data)
                        # Sort the data by the key column ascending.
                        updated_melee_data = sorted(updated_melee_data, key=lambda x: x["key"])
                        write_updated_tsv_file(
                            updated_melee_data,
                            headers,
                            version_info,
                            f"./!!!!!!!50meleeattackspeed_compat/db/{table_name}",
                            f"{PREPEND_MELEE_TABLE_FILE_NAME}_vanilla_and_dlc",
                        )
                    elif os.path.exists(f"./{folder_name}/db/{table_name}") and any(
                        file.endswith(".tsv") for file in os.listdir(f"./{folder_name}/db/{table_name}")
                    ):
                        logging.info(f"There are TSV files in {folder_name}/db/{table_name}.")
                        melee_data, headers, _ = load_multiple_tsv_data(f"./{folder_name}/db/{table_name}")
                        version_info = f"#{table_name};{table_version_number};db/{table_name}/{PREPEND_MELEE_TABLE_FILE_NAME}_{folder_name}"
                        updated_melee_data = update_melee_attack_intervals(melee_data)
                        # Sort the data by the key column ascending.
                        updated_melee_data = sorted(updated_melee_data, key=lambda x: x["key"])
                        write_updated_tsv_file(
                            updated_melee_data,
                            headers,
                            version_info,
                            f"./{PREPEND_MELEE_TABLE_FILE_NAME}/db/{table_name}",
                            f"{PREPEND_MELEE_TABLE_FILE_NAME}_{folder_name}",
                        )

            # Update the ranged firing arcs.
            if "ranged_arc" in mod["modified_attributes"]:
                if is_vanilla and os.path.exists(f"./vanilla_battle_entities_tables"):
                    battle_entities_data, headers, version_info = load_tsv_data(
                        f"./vanilla_battle_entities_tables/db/battle_entities_tables/data__.tsv"
                    )
                    version_info = version_info.replace("data__", f"{PREPEND_RANGED_ARC_TABLE_FILE_NAME}_vanilla_and_dlc")
                    updated_battle_entities_data = update_rows_for_120_degree_ranged_attacks(battle_entities_data)
                    # Sort the data by the key column ascending.
                    updated_battle_entities_data = sorted(updated_battle_entities_data, key=lambda x: x["key"])
                    write_updated_tsv_file(
                        updated_battle_entities_data,
                        headers,
                        version_info,
                        f"./{PREPEND_RANGED_ARC_TABLE_FILE_NAME}/db/battle_entities_tables",
                        f"{PREPEND_RANGED_ARC_TABLE_FILE_NAME}_vanilla_and_dlc",
                    )
                elif os.path.exists(f"./{folder_name}/db/battle_entities_tables") and any(
                    file.endswith(".tsv") for file in os.listdir(f"./{folder_name}/db/battle_entities_tables")
                ):
                    logging.info(f"There are TSV files in {folder_name}/db/battle_entities_tables.")
                    battle_entities_data, headers, _ = load_multiple_tsv_data(f"./{folder_name}/db/battle_entities_tables")
                    version_info = f"#battle_entities_tables;{BATTLE_ENTITIES_TABLE_VERSION_NUMBER};db/battle_entities_tables/{PREPEND_RANGED_ARC_TABLE_FILE_NAME}_{folder_name}"
                    updated_battle_entities_data = update_rows_for_120_degree_ranged_attacks(battle_entities_data)
                    # Sort the data by the key column ascending.
                    updated_battle_entities_data = sorted(updated_battle_entities_data, key=lambda x: x["key"])
                    write_updated_tsv_file(
                        updated_battle_entities_data,
                        headers,
                        version_info,
                        f"./{PREPEND_RANGED_ARC_TABLE_FILE_NAME}/db/battle_entities_tables",
                        f"{PREPEND_RANGED_ARC_TABLE_FILE_NAME}_{folder_name}",
                    )

            # Update the projectile velocities.
            if "velocity" in mod["modified_attributes"]:
                for table_name, table_version_number in [
                    ("battle_vortexs_tables", BATTLE_VORTEXS_TABLE_VERSION_NUMBER),
                    ("projectile_shot_type_displays_tables", PROJECTILE_SHOT_TYPE_DISPLAYS_TABLE_VERSION_NUMBER),
                    ("projectiles_scaling_damages_tables", PROJECTILES_SCALING_DAMAGES_TABLE_VERSION_NUMBER),
                    ("projectiles_tables", PROJECTILES_TABLE_VERSION_NUMBER),
                ]:
                    if is_vanilla and table_name == "projectiles_tables" and os.path.exists(f"./vanilla_projectiles_tables"):
                        projectile_data, headers, version_info = load_tsv_data(f"./vanilla_projectiles_tables/db/{table_name}/data__.tsv")
                        version_info = version_info.replace("data__", f"{PREPEND_VELOCITY_TABLE_FILE_NAME}_vanilla_and_dlc")
                        updated_projectile_data = adjust_muzzle_velocities(projectile_data)
                        # Sort the data by the key column ascending.
                        updated_projectile_data = sorted(updated_projectile_data, key=lambda x: x["key"])
                        write_updated_tsv_file(
                            updated_projectile_data,
                            headers,
                            version_info,
                            f"./{PREPEND_VELOCITY_TABLE_FILE_NAME}/db/{table_name}",
                            f"{PREPEND_VELOCITY_TABLE_FILE_NAME}_vanilla_and_dlc",
                        )
                    elif os.path.exists(f"./{folder_name}/db/{table_name}") and any(
                        file.endswith(".tsv") for file in os.listdir(f"./{folder_name}/db/{table_name}")
                    ):
                        logging.info(f"There are TSV files in {folder_name}/db/{table_name}.")
                        projectile_data, headers, _ = load_multiple_tsv_data(f"./{folder_name}/db/{table_name}")
                        version_info = f"#{table_name};{table_version_number};db/{table_name}/{PREPEND_VELOCITY_TABLE_FILE_NAME}_{folder_name}"
                        updated_projectile_data = adjust_muzzle_velocities(projectile_data)
                        # Sort the data by the key column ascending.
                        key = "key" if table_name != "battle_vortexs_tables" else "vortex_key"
                        updated_projectile_data = sorted(updated_projectile_data, key=lambda x: x[key])
                        write_updated_tsv_file(
                            updated_projectile_data,
                            headers,
                            version_info,
                            f"./{PREPEND_VELOCITY_TABLE_FILE_NAME}/db/{table_name}",
                            f"{PREPEND_VELOCITY_TABLE_FILE_NAME}_{folder_name}",
                        )

            if is_vanilla:
                shutil.rmtree(f"./vanilla_melee_weapons_tables", ignore_errors=True)
                shutil.rmtree(f"./vanilla_battle_entities_tables", ignore_errors=True)
                shutil.rmtree(f"./vanilla_projectiles_tables", ignore_errors=True)
            else:
                shutil.rmtree(f"./{folder_name}", ignore_errors=True)

    # After processing all mods, move the final folders to their destinations.
    for folder_name in [PREPEND_MELEE_TABLE_FILE_NAME, PREPEND_RANGED_ARC_TABLE_FILE_NAME, PREPEND_VELOCITY_TABLE_FILE_NAME]:
        if os.path.exists(f"./{folder_name}"):
            logging.info(f"Moving {folder_name} to ../warhammer3_mods/.")
            merge_move(f"./{folder_name}", "../warhammer3_mods/")

    for mod_name, steam_workshop_id in MODS_AND_STEAM_WORKSHOP_IDS:
        pack_path = workshop_pack_path(steam_workshop_id, f"{mod_name}.pack")
        if args.reset:
            reset_pack_folders(pack_path, ("db",))
        add_folder_to_pack(pack_path, f"../warhammer3_mods/{mod_name}/db;")

    end_time = round(time.time() - start_time, 2)
    logging.info(f"Total time for updating modified attribute mods: {end_time} seconds or {round(end_time / 60, 2)} minutes.")
