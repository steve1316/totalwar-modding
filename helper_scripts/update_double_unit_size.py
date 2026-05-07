"""Script to update the 2x unit size mod by merging in the vanilla and modded data tables from supported mods."""

import logging
import time
import shutil
import os
import argparse
import subprocess
import pandas as pd
import re
from typing import Dict, Any, List
from utilities import (
    extract_tsv_data,
    extract_modded_tsv_data,
    load_tsv_data,
    load_multiple_tsv_data,
    write_updated_tsv_file,
    read_and_clean_tsv,
    validate_and_fix_tsv_types,
    sort_tsv_data,
    cleanup_folders,
    extract_model_paths_from_variantmeshdefinition,
    merge_move,
)
from supported_mods import SUPPORTED_MODS


MODDED_TABLE_NAME = "!!!!!!!2xunitsize_compat"
VANILLA_LAND_UNITS_TABLES_DF = None


def handle_kv_rules_tables(df: pd.DataFrame):
    """Handle the _kv_rules_tables table. Only the unit_max_drag_width key will be set to a static value while the rest are doubled.

    Args:
        df (pd.DataFrame): DataFrame containing the _kv_rules_tables table.

    Returns:
        DataFrame containing the modified _kv_rules_tables table.
    """
    valid_keys = ["unit_tier1_kills", "unit_tier2_kills", "unit_tier3_kills"]
    df = df[df["key"].isin(["unit_max_drag_width", *valid_keys])]
    df.loc[df["key"] == "unit_max_drag_width", "value"] = "100.0"
    for key in valid_keys:
        df.loc[df["key"] == key, "value"] = str(float(df.loc[df["key"] == key, "value"].iloc[0]) * 2)
    return df


def handle_kv_unit_ability_scaling_rules_tables(df: pd.DataFrame):
    """Handle the _kv_unit_ability_scaling_rules_tables table. All column values are doubled.

    Args:
        df (pd.DataFrame): DataFrame containing the _kv_unit_ability_scaling_rules_tables table.

    Returns:
        DataFrame containing the modified _kv_unit_ability_scaling_rules_tables table.
    """
    valid_keys = ["direct_damage_large", "direct_damage_medium", "direct_damage_small", "direct_damage_ultra"]
    df = df[df["key"].isin(valid_keys)]
    for key in valid_keys:
        df.loc[df["key"] == key, "value"] = str(float(df.loc[df["key"] == key, "value"].iloc[0]) * 2)
    return df


def handle_battle_currency_army_special_abilities_cost_values_tables(df: pd.DataFrame):
    """Handle the battle_currency_army_special_abilities_cost_values_tables table. Some army abilities are removed because they are specific to the Trials of Fate game mode.

    Args:
        df (pd.DataFrame): DataFrame containing the battle_currency_army_special_abilities_cost_values_tables table.

    Returns:
        DataFrame containing the modified battle_currency_army_special_abilities_cost_values_tables table.
    """
    remove_keys = [
        "wh3_pro10_army_abilities_diabolical_puppetry_upgrade_1",
        "wh3_pro10_army_abilities_diabolical_puppetry_upgrade_2",
        "wh3_pro10_army_abilities_diabolical_puppetry_upgrade_3",
        "wh3_pro10_army_abilities_diabolical_puppetry",
        "wh3_pro10_army_abilities_inevitable_fate_upgrade_1",
        "wh3_pro10_army_abilities_inevitable_fate_upgrade_2",
        "wh3_pro10_army_abilities_inevitable_fate_upgrade_3",
        "wh3_pro10_army_abilities_inevitable_fate",
        "wh3_pro10_army_abilities_tempest_of_blue_flame_upgrade_1",
        "wh3_pro10_army_abilities_tempest_of_blue_flame_upgrade_2",
        "wh3_pro10_army_abilities_tempest_of_blue_flame_upgrade_3",
        "wh3_pro10_army_abilities_tempest_of_blue_flame",
    ]
    df = df[~df["item_type"].isin(remove_keys)]
    for index, row in df.iterrows():
        df.loc[index, "cost_value"] = str(float(row["cost_value"]) * 2)
    return df


def handle_main_units_tables(
    df: pd.DataFrame, land_units_tables_df: pd.DataFrame = None, reference_vanilla_land_units_tables_df: pd.DataFrame = None
):
    """Handle the main_units_tables table. In addition, it also modifies the land_units_tables table to match.

    Args:
        df (pd.DataFrame): DataFrame containing the main_units_tables table.
        land_units_tables_df (pd.DataFrame): DataFrame containing the land_units_tables table.
        reference_vanilla_land_units_tables_df (pd.DataFrame): DataFrame containing the reference vanilla land_units_tables table.

    Returns:
        Tuple containing the modified main_units_tables and land_units_tables dataframes.
    """
    # Double the values of the num_men column but only if the original value is greater than 1.
    df["num_men"] = df["num_men"].astype(float).astype(int).astype(str)
    df.loc[df["num_men"].astype(int) > 1, "num_men"] = (df.loc[df["num_men"].astype(int) > 1, "num_men"].astype(int) * 2).astype(str)

    # Update the land_units_tables table as well.
    # For all rows in the main_units_tables table via the unit column key, update the corresponding row in the land_units_tables table via the key column key
    # by doubling the num_mounts column value.
    # Also double the value of the rank_depth column.
    # In addition, double the value of the bonus_hit_points column for the "lord", "hero" and "monster" caste categories.
    extract_tsv_data("land_units_tables")
    if land_units_tables_df is None:
        land_units_tables_df: pd.DataFrame = read_and_clean_tsv("vanilla_land_units_tables/db/land_units_tables/data__.tsv", "land_units_tables")
    for _, row in df.iterrows():
        mask = land_units_tables_df["key"] == row["land_unit"]

        if mask.sum() == 0:
            # fallback to vanilla reference
            mask = reference_vanilla_land_units_tables_df["key"] == row["land_unit"]
            if mask.sum() == 0:
                logging.error(f"No matching row found for {row['land_unit']} in the land_units_tables table.")
                raise ValueError("No matching row found for the land unit in the land_units_tables table.")

            # Use the vanilla DF for reference, but still write into the actual modded DF
            src_df = reference_vanilla_land_units_tables_df
        else:
            src_df = land_units_tables_df

        # Conditionally double the bonus HP, rank depth and number of engines.
        if row["caste"] in ["lord", "hero", "monster"]:
            src_df.loc[mask, "bonus_hit_points"] = (src_df.loc[mask, "bonus_hit_points"].astype(int) * 2).astype(str)
        # else:
        #     src_df.loc[mask, "bonus_hit_points"] = (src_df.loc[mask, "bonus_hit_points"].astype(int) // 2).astype(str)

        if row["caste"] in ["warmachine", "chariot"]:
            # Check the original num_engines value from the reference dataframe.
            if mask.sum() > 0:
                original_num_engines = src_df.loc[mask, "num_engines"].iloc[0]
                original_num_engines_int = int(original_num_engines)

                if original_num_engines_int == 0:
                    # If num_engines is 0, the value was stored in num_mounts instead, so double num_mounts.
                    # Always double num_mounts in this case, even if it's 1.
                    original_num_mounts = src_df.loc[mask, "num_mounts"].iloc[0]
                    src_df.loc[mask, "num_mounts"] = str(int(original_num_mounts) * 2)
                else:
                    # Double the engines, but only if the original value was not '1'.
                    engine_mask = mask & (src_df["num_engines"].astype(int) != 1)
                    src_df.loc[engine_mask, "num_engines"] = (src_df.loc[engine_mask, "num_engines"].astype(int) * 2).astype(str)
                    # Also double the mounts, but only if the original value was not '1'.
                    mount_mask = mask & (src_df["num_mounts"].astype(int) != 1)
                    src_df.loc[mount_mask, "num_mounts"] = (src_df.loc[mount_mask, "num_mounts"].astype(int) * 2).astype(str)
        else:
            # Double the mounts, but only if the original value was not '1'.
            mount_mask = mask & (src_df["num_mounts"].astype(int) != 1)
            src_df.loc[mount_mask, "num_mounts"] = (src_df.loc[mount_mask, "num_mounts"].astype(int) * 2).astype(str)
            src_df.loc[mask, "rank_depth"] = (src_df.loc[mask, "rank_depth"].astype(int) * 2).astype(str)

    # # Now remove all rows from the main_units_tables table that are a "lord" or "hero" caste category.
    # df = df[~df["caste"].isin(["lord", "hero"])]
    return df, land_units_tables_df


def handle_special_ability_phases_tables(df: pd.DataFrame):
    """Handle the special_ability_phases_tables table. The heal_amount column is halved.

    Args:
        df (pd.DataFrame): DataFrame containing the special_ability_phases_tables table.

    Returns:
        DataFrame containing the modified special_ability_phases_tables table.
    """
    # Remove all rows whose heal_amount column value is 0.
    df = df[df["heal_amount"].astype(float) > 0.0]
    # Halve the value of the heal_amount column.
    df.loc[:, "heal_amount"] = (df.loc[:, "heal_amount"].astype(float) / 2).astype(str)
    return df


def handle_unit_size_global_scalings_tables(df: pd.DataFrame):
    """Handle the unit_size_global_scalings_tables table. All column values except the battle_type column are doubled.

    Args:
        df (pd.DataFrame): DataFrame containing the unit_size_global_scalings_tables table.

    Returns:
        DataFrame containing the modified unit_size_global_scalings_tables table.
    """
    # Double the values of all columns except the battle_type column.
    columns = df.columns.tolist()
    columns.remove("battle_type")
    df.loc[:, columns] = (df.loc[:, columns].astype(float) * 2).astype(str)
    return df


def handle_unit_stat_to_size_scaling_values_tables(df: pd.DataFrame):
    """Handle the unit_stat_to_size_scaling_values_tables table. Only the single_entity_value column values are doubled.

    Args:
        df (pd.DataFrame): DataFrame containing the unit_stat_to_size_scaling_values_tables table.

    Returns:
        DataFrame containing the modified unit_stat_to_size_scaling_values_tables table.
    """
    # Double the value of the single_entity_value column for all rows.
    df.loc[:, "single_entity_value"] = (df.loc[:, "single_entity_value"].astype(float) * 2).astype(str)
    return df


def extract_and_load_table_data(mod_path: str, table_configs: List[Dict[str, Any]]):
    """Extract and load multiple tables for a mod based on the provided configs.

    The table configs are dictionaries with the following keys:
        table_name: Name of the table to extract.
        folder_name: Name of the folder to extract to.
        key_field: Field to use as dictionary key (default: "key").
        required: Whether the table is required (default: False).

    Args:
        mod_path (str): Path to the mod packfile.
        table_configs (List[Dict]): List of table configuration dictionaries.

    Returns:
        Dictionary containing mappings for each table with the table names as keys.
    """
    mappings = {}

    for config in table_configs:
        table_name = config["table_name"]
        folder_name = config["folder_name"]
        key_field = config.get("key_field", "key")
        required = config.get("required", False)

        # Extract the table data from the mod.
        extract_modded_tsv_data(table_name, mod_path, f"./modded_{folder_name}")
        new_mapping = {}

        if os.path.exists(f"./modded_{folder_name}"):
            merged_data, headers, version_info = load_multiple_tsv_data(f"./modded_{folder_name}/db/{table_name}", table_name)

            # Save each entry in the table to the new mapping. The column keys in RPFM are what is used as the keys in the new mapping.
            for data in merged_data:
                new_mapping[data[key_field]] = data

            # Store the table headers and version info.
            mappings[f"{table_name}_headers"] = headers
            mappings[f"{table_name}_version_info"] = version_info
        elif required:
            return None

        # Save the new mapping to the table name as a key in the mappings dictionary.
        mappings[table_name] = new_mapping

    return mappings


if __name__ == "__main__":
    logging.basicConfig(format="%(asctime)s - %(levelname)s - %(message)s", level=logging.INFO)
    start_time = time.time()

    # Get arguments from argparse.
    parser = argparse.ArgumentParser()
    parser.add_argument("--reset", action="store_true", help="Reset the script.")
    args = parser.parse_args()
    if args.reset:
        logging.info("Will reset folders in the packfile before writing.")
        try:
            shutil.rmtree(f"../warhammer3_mods/{MODDED_TABLE_NAME}/db")
            shutil.rmtree(f"../warhammer3_mods/{MODDED_TABLE_NAME}/variantmeshes")
        except FileNotFoundError:
            pass

    # Clean up any existing modded folders.
    cleanup_folders(
        [
            f"./{MODDED_TABLE_NAME}",
            "./modded_main_units_tables",
            "./modded_land_units_tables",
            "./modded_units_to_groupings_military_permissions_tables",
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
    )

    # Extract vanilla mounts_tables for variantmesh handling.
    extract_tsv_data("mounts_tables")
    vanilla_mounts_tables_dataframe = read_and_clean_tsv("vanilla_mounts_tables/db/mounts_tables/data__.tsv", "mounts_tables")

    for mod in SUPPORTED_MODS:
        is_vanilla = False
        if mod["package_name"] == "vanilla":
            package_name = "vanilla"
            is_vanilla = True
        elif mod["name"] in ["Hooveric Overhaul (HVO) 2.0c", "Nanu's Dynamic Regiments of Renown (Beta)", "[GLF] Battle Mage 战斗法师"]:
            logging.info(f"Skipping {mod['package_name']} because it is not supported.")
            continue
        else:
            # Table names cannot end in numbers.
            package_name = mod["package_name"].replace(".pack", "").replace(" ", "_")
            if package_name[-1].isdigit():
                package_name = package_name[:-1]

        ########################################
        if is_vanilla:
            logging.info(f"Processing vanilla...")

            # Define the mapping of table names to their dataframes.
            table_mappings = {
                "_kv_rules_tables": None,
                "_kv_unit_ability_scaling_rules_tables": None,
                "battle_currency_army_special_abilities_cost_values_tables": None,
                "main_units_tables": None,
                "land_units_tables": None,
                "special_ability_phases_tables": None,
                "unit_size_global_scalings_tables": None,
                "unit_stat_to_size_scaling_values_tables": None,
            }
            for table_name in [
                "_kv_rules_tables",
                "_kv_unit_ability_scaling_rules_tables",
                "battle_currency_army_special_abilities_cost_values_tables",
                "main_units_tables",
                "land_units_tables",
                "special_ability_phases_tables",
                "unit_size_global_scalings_tables",
                "unit_stat_to_size_scaling_values_tables",
            ]:
                extract_tsv_data(table_name)
                if table_name != "land_units_tables" and table_name in table_mappings:
                    table_mappings[table_name] = read_and_clean_tsv(f"vanilla_{table_name}/db/{table_name}/data__.tsv", table_name, do_not_clean=True)
                    logging.info(f"Number of rows in {table_name} table: {len(table_mappings[table_name])}")

                ########################################
                df: pd.DataFrame = table_mappings[table_name].astype(str)

                if table_name == "_kv_rules_tables":
                    df = handle_kv_rules_tables(df)
                elif table_name == "_kv_unit_ability_scaling_rules_tables":
                    df = handle_kv_unit_ability_scaling_rules_tables(df)
                elif table_name == "battle_currency_army_special_abilities_cost_values_tables":
                    df = handle_battle_currency_army_special_abilities_cost_values_tables(df)
                elif table_name == "main_units_tables":
                    df, land_units_tables_df = handle_main_units_tables(df)
                    table_mappings["land_units_tables"] = land_units_tables_df
                    VANILLA_LAND_UNITS_TABLES_DF = land_units_tables_df.copy(deep=True)
                elif table_name == "special_ability_phases_tables":
                    df = handle_special_ability_phases_tables(df)
                elif table_name == "unit_size_global_scalings_tables":
                    df = handle_unit_size_global_scalings_tables(df)
                elif table_name == "unit_stat_to_size_scaling_values_tables":
                    df = handle_unit_stat_to_size_scaling_values_tables(df)
                ########################################

                # Save the modified dataframe back to the table_mappings dictionary.
                table_mappings[table_name] = validate_and_fix_tsv_types(df, table_name)

                # Now write this to a new TSV file.
                # Note that the battle_currency_army_special_abilities_cost_values_tables and unit_stat_to_size_scaling_values_tables tables allow duplicates.
                _, headers, version_info = load_tsv_data(f"./vanilla_{table_name}/db/{table_name}/data__.tsv")
                version_info = version_info.replace(version_info.split("/")[-1], f"{MODDED_TABLE_NAME}_vanilla")
                write_updated_tsv_file(
                    table_mappings[table_name].to_dict(orient="records"),
                    headers,
                    version_info,
                    f"./{MODDED_TABLE_NAME}/db/{table_name}",
                    MODDED_TABLE_NAME,
                    (
                        False
                        if (
                            table_name != "battle_currency_army_special_abilities_cost_values_tables"
                            and table_name != "unit_stat_to_size_scaling_values_tables"
                        )
                        else True
                    ),
                )
        else:
            logging.info(f"Processing mod: {mod['package_name']}")

            # Define table configurations for extraction.
            table_configs = [
                {
                    "table_name": "units_to_groupings_military_permissions_tables",
                    "folder_name": "units_to_groupings_military_permissions_tables",
                    "key_field": "unit",
                },
                {"table_name": "main_units_tables", "folder_name": "main_units_tables", "key_field": "unit"},
                {"table_name": "land_units_tables", "folder_name": "land_units_tables", "key_field": "key"},
                {
                    "table_name": "unit_description_historical_texts_tables",
                    "folder_name": "unit_description_historical_texts_tables",
                    "key_field": "key",
                },
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

            # Track processed keys for each table type to prevent duplicates.
            # Map table names to their key field names.
            table_key_fields = {
                "unit_description_historical_texts_tables": "key",
                "battle_animations_table_tables": "key",
                "battle_entities_tables": "key",
                "mounts_tables": "key",
                "melee_weapons_tables": "key",
                "missile_weapons_tables": "key",
                "unit_description_short_texts_tables": "key",
                "unit_attributes_groups_tables": "group_name",
                "battlefield_engines_tables": "key",
                "projectiles_tables": "key",
                "battle_vortexs_tables": "vortex_key",
                "projectiles_scaling_damages_tables": "key",
                "projectile_shot_type_displays_tables": "key",
                "unit_spacings_tables": "key",
                "first_person_engines_tables": "key",
                "land_unit_articulated_vehicles_tables": "key",
                "ui_unit_groupings_tables": "key",
                "ui_unit_group_parents_tables": "key",
                "variants_tables": "variant_name",
                "land_units_tables": "key",
                "main_units_tables": "unit",
            }

            # Initialize tracking sets for each table.
            processed_table_keys = {table_name: set() for table_name in table_key_fields.keys()}

            def should_add_table_entry(table_name: str, entry_data: Dict[str, Any]):
                """Check if a table entry should be added (not a duplicate).

                Args:
                    table_name: Name of the table.
                    entry_data: Dictionary containing the entry data.

                Returns:
                    True if the entry should be added, False if it's a duplicate.
                """
                if table_name not in table_key_fields:
                    return True  # Unknown table, allow it.
                key_field = table_key_fields[table_name]
                entry_key = entry_data.get(key_field)
                if entry_key is None:
                    return True  # No key field, allow it.
                if entry_key in processed_table_keys[table_name]:
                    logging.debug(f"Skipping duplicate entry {entry_key} for table {table_name}.")
                    return False
                processed_table_keys[table_name].add(entry_key)
                return True

            # Extract and load all the required and optional tables needed for this mod.
            table_data = extract_and_load_table_data(mod["path"], table_configs)
            if table_data is None:
                continue

            # Extract the variantmeshes/variantmeshdefinitions folder if it exists.
            variant_mesh_definitions_to_add = []
            subprocess.run(
                [
                    "./rpfm_cli.exe",
                    "--game",
                    "warhammer_3",
                    "pack",
                    "extract",
                    "--pack-path",
                    mod["path"],
                    "--folder-path",
                    "variantmeshes;./modded_variantmeshes",
                ],
                capture_output=True,
            )

            # Load required tables into separate mappings.
            modded_land_units_headers = table_data["land_units_tables_headers"]
            modded_land_units_version_info = table_data["land_units_tables_version_info"]
            modded_main_units_headers = table_data["main_units_tables_headers"]
            modded_main_units_version_info = table_data["main_units_tables_version_info"]

            # Convert to DataFrames for processing.
            main_units_tables_df: pd.DataFrame = pd.DataFrame(list(table_data["main_units_tables"].values())).astype(str)
            land_units_tables_df: pd.DataFrame = pd.DataFrame(list(table_data["land_units_tables"].values())).astype(str)

            ########################################
            # Mods are only concerned with just these two tables and are tasked with the following:
            # - Double the num_men and num_mounts from both tables. Double the rank_depth conditionally as well for land_units_tables.
            # - If the caste is "lord", "hero" or "monster", double the bonus_hit_points column value.
            try:
                main_units_tables_df, land_units_tables_df = handle_main_units_tables(
                    main_units_tables_df, land_units_tables_df, VANILLA_LAND_UNITS_TABLES_DF
                )
            except ValueError as e:
                logging.error(f"Error processing mod: {mod['package_name']}: {e}")
                cleanup_folders(
                    [
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
                )
                continue
            ########################################

            # Create mapping from the MODIFIED DataFrames (after doubling) for writing.
            main_units_mapping = {}
            for _, row in main_units_tables_df.iterrows():
                main_units_mapping[row["unit"]] = row.to_dict()

            # Process units and collect related tables.
            list_of_data_to_add = []
            for _, row in land_units_tables_df.iterrows():
                data = row.to_dict()
                new_data = {
                    "key": data["key"],
                    "land_units": [],
                    "main_units": [],
                    "unit_description_historical_texts": [],
                    "battle_animations": [],
                    "battle_entities": [],
                    "mounts": [],
                    "melee_weapons": [],
                    "missile_weapons": [],
                    "unit_description_short_texts": [],
                    "unit_attributes_groups": [],
                    "battlefield_engines": [],
                    "projectiles": [],
                    "battle_vortexs": [],
                    "projectiles_scaling_damages": [],
                    "projectile_shot_type_displays": [],
                    "unit_spacings": [],
                    "first_person_engines": [],
                    "land_unit_articulated_vehicles": [],
                    "ui_unit_groupings": [],
                    "ui_unit_group_parents": [],
                    "variants": [],
                }

                try:
                    # If the unit key does not exist in the main_units_tables, that means the mod edited a vanilla unit. So it is okay if there is no record for it.
                    if data["key"] in main_units_mapping:
                        main_unit_data = main_units_mapping[data["key"]]
                        if should_add_table_entry("main_units_tables", main_unit_data):
                            new_data["main_units"].append(main_unit_data)
                        if should_add_table_entry("land_units_tables", data):
                            new_data["land_units"].append(data)

                        # Use the entry from land_units_tables to get the entries from the following tables.
                        # This is to make the mod standalone while keeping it as trimmed down as possible without crashing.
                        if (
                            data.get("historical_description_text")
                            and data["historical_description_text"] in table_data["unit_description_historical_texts_tables"]
                        ):
                            entry = table_data["unit_description_historical_texts_tables"][data["historical_description_text"]]
                            if should_add_table_entry("unit_description_historical_texts_tables", entry):
                                new_data["unit_description_historical_texts"].append(entry)
                        if data.get("man_animation") and data["man_animation"] in table_data["battle_animations_table_tables"]:
                            entry = table_data["battle_animations_table_tables"][data["man_animation"]]
                            if should_add_table_entry("battle_animations_table_tables", entry):
                                new_data["battle_animations"].append(entry)
                        if data.get("man_entity") and data["man_entity"] in table_data["battle_entities_tables"]:
                            entry = table_data["battle_entities_tables"][data["man_entity"]]
                            if should_add_table_entry("battle_entities_tables", entry):
                                new_data["battle_entities"].append(entry)
                        if data.get("mount") and data["mount"] in table_data["mounts_tables"]:
                            mount_data = table_data["mounts_tables"][data["mount"]]
                            if should_add_table_entry("mounts_tables", mount_data):
                                new_data["mounts"].append(mount_data)
                            mount_battle_entity = mount_data.get("entity")
                            if mount_battle_entity and mount_battle_entity in table_data["battle_entities_tables"]:
                                entry = table_data["battle_entities_tables"][mount_battle_entity]
                                if should_add_table_entry("battle_entities_tables", entry):
                                    new_data["battle_entities"].append(entry)
                            if mount_data.get("variant") and mount_data["variant"] in table_data["variants_tables"]:
                                variant_data = table_data["variants_tables"][mount_data["variant"]]
                                if should_add_table_entry("variants_tables", variant_data):
                                    new_data["variants"].append(variant_data)

                                # Add the variantmeshdefinition for this mount if it exists. This applies to vanilla mounts only.
                                if (
                                    mount_data.get("key") in vanilla_mounts_tables_dataframe.key.values
                                    and variant_data.get("variant_filename")
                                    and os.path.exists(
                                        f"./modded_variantmeshes/variantmeshes/variantmeshdefinitions/{variant_data['variant_filename']}.variantmeshdefinition"
                                    )
                                ):
                                    variant_mesh_definitions_to_add.append(
                                        f"./modded_variantmeshes/variantmeshes/variantmeshdefinitions/{variant_data['variant_filename']}.variantmeshdefinition"
                                    )
                        if data.get("primary_melee_weapon") and data["primary_melee_weapon"] in table_data["melee_weapons_tables"]:
                            melee_weapon_data = table_data["melee_weapons_tables"][data["primary_melee_weapon"]]
                            if should_add_table_entry("melee_weapons_tables", melee_weapon_data):
                                new_data["melee_weapons"].append(melee_weapon_data)

                            # Use the entry from melee_weapons_tables if available to get the entry from projectiles_scaling_damages_tables.
                            if (
                                melee_weapon_data.get("scaling_damage")
                                and melee_weapon_data["scaling_damage"] in table_data["projectiles_scaling_damages_tables"]
                            ):
                                entry = table_data["projectiles_scaling_damages_tables"][melee_weapon_data["scaling_damage"]]
                                if should_add_table_entry("projectiles_scaling_damages_tables", entry):
                                    new_data["projectiles_scaling_damages"].append(entry)

                        if data.get("primary_missile_weapon") and data["primary_missile_weapon"] in table_data["missile_weapons_tables"]:
                            missile_weapon_data = table_data["missile_weapons_tables"][data["primary_missile_weapon"]]
                            if should_add_table_entry("missile_weapons_tables", missile_weapon_data):
                                new_data["missile_weapons"].append(missile_weapon_data)

                            # Use the entry from missile_weapons_tables if available to get the entries from the following tables.
                            if (
                                missile_weapon_data.get("default_projectile")
                                and missile_weapon_data["default_projectile"] in table_data["projectiles_tables"]
                            ):
                                entry = table_data["projectiles_tables"][missile_weapon_data["default_projectile"]]
                                if should_add_table_entry("projectiles_tables", entry):
                                    new_data["projectiles"].append(entry)
                                if entry.get("spawned_vortex") and entry["spawned_vortex"] in table_data["battle_vortexs_tables"]:
                                    vortex_entry = table_data["battle_vortexs_tables"][entry["spawned_vortex"]]
                                    if should_add_table_entry("battle_vortexs_tables", vortex_entry):
                                        new_data["battle_vortexs"].append(vortex_entry)
                                if (
                                    entry.get("projectile_shot_type_display")
                                    and entry["projectile_shot_type_display"] in table_data["projectile_shot_type_displays_tables"]
                                ):
                                    display_entry = table_data["projectile_shot_type_displays_tables"][entry["projectile_shot_type_display"]]
                                    if should_add_table_entry("projectile_shot_type_displays_tables", display_entry):
                                        new_data["projectile_shot_type_displays"].append(display_entry)
                            if (
                                missile_weapon_data.get("scaling_damage")
                                and missile_weapon_data["scaling_damage"] in table_data["projectiles_scaling_damages_tables"]
                            ):
                                entry = table_data["projectiles_scaling_damages_tables"][missile_weapon_data["scaling_damage"]]
                                if should_add_table_entry("projectiles_scaling_damages_tables", entry):
                                    new_data["projectiles_scaling_damages"].append(entry)

                        if data.get("short_description_text") and data["short_description_text"] in table_data["unit_description_short_texts_tables"]:
                            entry = table_data["unit_description_short_texts_tables"][data["short_description_text"]]
                            if should_add_table_entry("unit_description_short_texts_tables", entry):
                                new_data["unit_description_short_texts"].append(entry)
                        if data.get("attribute_group") and data["attribute_group"] in table_data["unit_attributes_groups_tables"]:
                            entry = table_data["unit_attributes_groups_tables"][data["attribute_group"]]
                            if should_add_table_entry("unit_attributes_groups_tables", entry):
                                new_data["unit_attributes_groups"].append(entry)
                        if data.get("engine") and data["engine"] in table_data["battlefield_engines_tables"]:
                            engine_data = table_data["battlefield_engines_tables"][data["engine"]]
                            if should_add_table_entry("battlefield_engines_tables", engine_data):
                                new_data["battlefield_engines"].append(engine_data)

                            if engine_data.get("battle_entity") and engine_data["battle_entity"] in table_data["battle_entities_tables"]:
                                entry = table_data["battle_entities_tables"][engine_data["battle_entity"]]
                                if should_add_table_entry("battle_entities_tables", entry):
                                    new_data["battle_entities"].append(entry)
                        if data.get("spacing") and data["spacing"] in table_data["unit_spacings_tables"]:
                            entry = table_data["unit_spacings_tables"][data["spacing"]]
                            if should_add_table_entry("unit_spacings_tables", entry):
                                new_data["unit_spacings"].append(entry)
                        if data.get("first_person") and data["first_person"] in table_data["first_person_engines_tables"]:
                            entry = table_data["first_person_engines_tables"][data["first_person"]]
                            if should_add_table_entry("first_person_engines_tables", entry):
                                new_data["first_person_engines"].append(entry)
                        if data.get("articulated_record") and data["articulated_record"] in table_data["land_unit_articulated_vehicles_tables"]:
                            articulated_vehicle_data = table_data["land_unit_articulated_vehicles_tables"][data["articulated_record"]]
                            if should_add_table_entry("land_unit_articulated_vehicles_tables", articulated_vehicle_data):
                                new_data["land_unit_articulated_vehicles"].append(articulated_vehicle_data)

                            # Use the entry from land_unit_articulated_vehicles_tables if available to get the entry from battle_entities_tables.
                            if (
                                articulated_vehicle_data.get("articulated_entity")
                                and articulated_vehicle_data["articulated_entity"] in table_data["battle_entities_tables"]
                            ):
                                entry = table_data["battle_entities_tables"][articulated_vehicle_data["articulated_entity"]]
                                if should_add_table_entry("battle_entities_tables", entry):
                                    new_data["battle_entities"].append(entry)
                        if (
                            main_unit_data.get("ui_unit_group_land")
                            and main_unit_data["ui_unit_group_land"] in table_data["ui_unit_groupings_tables"]
                        ):
                            ui_unit_grouping_data = table_data["ui_unit_groupings_tables"][main_unit_data["ui_unit_group_land"]]
                            if should_add_table_entry("ui_unit_groupings_tables", ui_unit_grouping_data):
                                new_data["ui_unit_groupings"].append(ui_unit_grouping_data)

                            if (
                                ui_unit_grouping_data.get("parent_group")
                                and ui_unit_grouping_data["parent_group"] in table_data["ui_unit_group_parents_tables"]
                            ):
                                entry = table_data["ui_unit_group_parents_tables"][ui_unit_grouping_data["parent_group"]]
                                if should_add_table_entry("ui_unit_group_parents_tables", entry):
                                    new_data["ui_unit_group_parents"].append(entry)

                    list_of_data_to_add.append(new_data)
                except KeyError as e:
                    logging.exception(e)
                    pass

            if len(list_of_data_to_add) > 0:
                # Update the version info to include the new TSV name. This will also make RPFM rename to this filename when moving it into the packfile.
                land_units_version_info = modded_land_units_version_info.replace(
                    modded_land_units_version_info.split("/")[-1], f"{MODDED_TABLE_NAME}_{package_name}"
                )
                main_units_version_info = modded_main_units_version_info.replace(
                    modded_main_units_version_info.split("/")[-1], f"{MODDED_TABLE_NAME}_{package_name}"
                )

                tables_to_sort = [
                    f"./{MODDED_TABLE_NAME}/db/land_units_tables",
                    f"./{MODDED_TABLE_NAME}/db/main_units_tables",
                ]

                # Deduplicate variantmesh definitions list.
                variant_mesh_definitions_to_add = list(set(variant_mesh_definitions_to_add))

                # Write the data to required and optional tables.
                for data_to_add in list_of_data_to_add:
                    # Write to the required tables first.
                    write_updated_tsv_file(
                        data_to_add["land_units"],
                        modded_land_units_headers,
                        land_units_version_info,
                        f"./{MODDED_TABLE_NAME}/db/land_units_tables",
                        f"{MODDED_TABLE_NAME}_{package_name}",
                    )
                    write_updated_tsv_file(
                        data_to_add["main_units"],
                        modded_main_units_headers,
                        main_units_version_info,
                        f"./{MODDED_TABLE_NAME}/db/main_units_tables",
                        f"{MODDED_TABLE_NAME}_{package_name}",
                    )

                    # Now write to all of the available optional tables.
                    optional_tables = [
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
                    for data_key, table_name in optional_tables:
                        if data_to_add[data_key]:
                            version_info = table_data[f"{table_name}_version_info"].replace(
                                table_data[f"{table_name}_version_info"].split("/")[-1], f"{MODDED_TABLE_NAME}_{package_name}"
                            )
                            write_updated_tsv_file(
                                data_to_add[data_key],
                                table_data[f"{table_name}_headers"],
                                version_info,
                                f"./{MODDED_TABLE_NAME}/db/{table_name}",
                                f"{MODDED_TABLE_NAME}_{package_name}",
                            )
                            tables_to_sort.append(f"./{MODDED_TABLE_NAME}/db/{table_name}")

                # Add the variantmeshdefinition for mounts if available (process once per mod, not per unit).
                if variant_mesh_definitions_to_add:
                    for variant_mesh_definition in variant_mesh_definitions_to_add:
                        os.makedirs(f"./{MODDED_TABLE_NAME}/variantmeshes/variantmeshdefinitions", exist_ok=True)
                        try:
                            if os.path.exists(variant_mesh_definition):
                                shutil.move(
                                    variant_mesh_definition,
                                    f"./{MODDED_TABLE_NAME}/variantmeshes/variantmeshdefinitions/{os.path.basename(variant_mesh_definition)}",
                                )
                                mesh_model_paths = extract_model_paths_from_variantmeshdefinition(
                                    f"./{MODDED_TABLE_NAME}/variantmeshes/variantmeshdefinitions/{os.path.basename(variant_mesh_definition)}"
                                )
                                for mesh_model_path in mesh_model_paths:
                                    if os.path.exists(f"./{MODDED_TABLE_NAME}/variantmeshes/wh_variantmodels/{mesh_model_path}"):
                                        os.remove(f"./{MODDED_TABLE_NAME}/variantmeshes/wh_variantmodels/{mesh_model_path}")
                                    os.makedirs(f"./{MODDED_TABLE_NAME}/variantmeshes/wh_variantmodels", exist_ok=True)
                                    if os.path.exists(f"./modded_variantmeshes/variantmeshes/wh_variantmodels/{mesh_model_path}"):
                                        shutil.move(
                                            f"./modded_variantmeshes/variantmeshes/wh_variantmodels/{mesh_model_path}",
                                            f"./{MODDED_TABLE_NAME}/variantmeshes/wh_variantmodels/{mesh_model_path}",
                                        )
                        except FileNotFoundError:
                            logging.error(f"variantmeshdefinition not found: {variant_mesh_definition}.")
                            pass

                # After writing is complete, sort the required and optional tables.
                for table_path in tables_to_sort:
                    sort_tsv_data(
                        table_path,
                        f"{MODDED_TABLE_NAME}_{package_name}",
                    )

            # Perform cleanup of modded folders.
            cleanup_folders(
                [
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
            )

    # Move the modded folder to the ../warhammer3_mods folder.
    if os.path.exists(f"./{MODDED_TABLE_NAME}"):
        logging.info(f"Moving {MODDED_TABLE_NAME} to ../warhammer3_mods/.")
        merge_move(f"./{MODDED_TABLE_NAME}", f"../warhammer3_mods")

    if args.reset:
        # Reset the contents of the packfile. Delete db and variantmeshes folders explicitly because pack delete with empty --folder-path does not reliably clear the pack.
        for folder in ["db", "variantmeshes"]:
            subprocess.run(
                [
                    "./rpfm_cli.exe",
                    "--game",
                    "warhammer_3",
                    "pack",
                    "delete",
                    "--pack-path",
                    f"F:\\SteamLibrary\\steamapps\\workshop\\content\\1142710\\3621939685\\{MODDED_TABLE_NAME}.pack",
                    "--folder-path",
                    folder,
                ],
                capture_output=True,
            )

    # Now merge the new files into the packfile.
    subprocess.run(
        [
            "./rpfm_cli.exe",
            "--game",
            "warhammer_3",
            "pack",
            "add",
            "--pack-path",
            f"F:\\SteamLibrary\\steamapps\\workshop\\content\\1142710\\3621939685\\{MODDED_TABLE_NAME}.pack",
            "--tsv-to-binary",
            "./schemas/schema_wh3.ron",
            "--folder-path",
            f"../warhammer3_mods/{MODDED_TABLE_NAME};",
        ],
        capture_output=True,
    )

    # Remove the vanilla temp folders.
    cleanup_folders(
        [
            "vanilla__kv_rules_tables",
            "vanilla__kv_unit_ability_scaling_rules_tables",
            "vanilla_battle_currency_army_special_abilities_cost_values_tables",
            "vanilla_land_units_tables",
            "vanilla_main_units_tables",
            "vanilla_special_ability_phases_tables",
            "vanilla_unit_size_global_scalings_tables",
            "vanilla_unit_stat_to_size_scaling_values_tables",
            "vanilla_mounts_tables",
        ]
    )

    end_time = round(time.time() - start_time, 2)
    logging.info(f"Total time for updating modified attribute mods: {end_time} seconds or {round(end_time / 60, 2)} minutes.")
