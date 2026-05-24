"""Script to update the 2x unit size mod by merging in the vanilla and modded data tables from supported mods."""

import logging
import time
import os
from typing import Dict, Optional
import pandas as pd
from utilities import (
    extract_tsv_data,
    load_tsv_data,
    log_elapsed_time,
    make_common_argparser,
    run_parallel,
    setup_script_logging,
    write_updated_tsv_file,
    read_and_clean_tsv,
    validate_and_fix_tsv_types,
    sort_tsv_data,
    cleanup_folders,
    merge_move,
    ensure_temp_dir,
    TEMP_DIR,
)
from supported_mods import SUPPORTED_MODS
from pipeline import (
    DuplicateTracker,
    add_folder_to_pack,
    cleanup_modded_folders,
    extract_and_load_table_data,
    extract_variantmeshes_folder,
    make_new_data_buckets,
    move_variantmesh_definitions,
    reset_pack_folders,
    walk_land_unit_to_related_tables,
    workshop_pack_path,
    write_optional_tables,
    TABLE_CONFIGS,
)


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
    if land_units_tables_df is None:
        # Only extract vanilla when we actually need to read from it. Modded callers (workers) already supply the modded land_units_tables_df, so the re-extraction would be a wasted shared-folder write and a thread-safety hazard.
        extract_tsv_data("land_units_tables")
        # Cast to str so later assignments of stringified ints don't trip the float64 dtype FutureWarning.
        land_units_tables_df: pd.DataFrame = read_and_clean_tsv(
            f"{TEMP_DIR}/vanilla_land_units_tables/db/land_units_tables/data__.tsv", "land_units_tables"
        ).astype(str)

    # Normalize int-like columns to clean integer strings. pd.read_csv infers numeric columns as float64,
    # which becomes "4280.0" after .astype(str) and breaks the downstream .astype(int) calls.
    for col in ["bonus_hit_points", "num_mounts", "num_engines", "rank_depth"]:
        if col in land_units_tables_df.columns:
            land_units_tables_df[col] = land_units_tables_df[col].astype(float).astype(int).astype(str)
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


if __name__ == "__main__":
    setup_script_logging()
    start_time = time.time()

    # Get arguments from the CLI.
    args = make_common_argparser().parse_args()
    compat_pack_path = workshop_pack_path("3621939685", f"{MODDED_TABLE_NAME}.pack")

    if args.reset:
        logging.info("Will reset folders in the packfile before writing.")
        cleanup_folders(
            [
                f"../warhammer3_mods/{MODDED_TABLE_NAME}/db",
                f"../warhammer3_mods/{MODDED_TABLE_NAME}/variantmeshes",
            ]
        )

    ensure_temp_dir()

    # Clean up any existing scratch folders.
    cleanup_folders([f"{TEMP_DIR}/{MODDED_TABLE_NAME}"])
    cleanup_modded_folders()

    # Extract vanilla mounts_tables for variantmesh handling.
    extract_tsv_data("mounts_tables")
    vanilla_mounts_tables_dataframe = read_and_clean_tsv(f"{TEMP_DIR}/vanilla_mounts_tables/db/mounts_tables/data__.tsv", "mounts_tables")
    vanilla_mounts_keys = set(vanilla_mounts_tables_dataframe.key.values)

    # Vanilla pass writes the base `_vanilla` TSVs into the shared compat-pack build dir and seeds `VANILLA_LAND_UNITS_TABLES_DF`. Run sequentially so the modded workers see a stable read-only reference.
    logging.info("Processing vanilla...")
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
            table_mappings[table_name] = read_and_clean_tsv(
                f"{TEMP_DIR}/vanilla_{table_name}/db/{table_name}/data__.tsv", table_name, do_not_clean=True
            )
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
        _, headers, version_info = load_tsv_data(f"{TEMP_DIR}/vanilla_{table_name}/db/{table_name}/data__.tsv")
        version_info = version_info.replace(version_info.split("/")[-1], f"{MODDED_TABLE_NAME}_vanilla")
        write_updated_tsv_file(
            table_mappings[table_name].to_dict(orient="records"),
            headers,
            version_info,
            f"{TEMP_DIR}/{MODDED_TABLE_NAME}/db/{table_name}",
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

    # Filter out the vanilla entry and the explicitly-unsupported mods before parallel dispatch.
    skip_mod_names = {"Hooveric Overhaul (HVO) 2.0c", "Nanu's Dynamic Regiments of Renown (Beta)", "[GLF] Battle Mage 战斗法师"}
    modded_mods = [m for m in SUPPORTED_MODS if m["package_name"] != "vanilla" and m["name"] not in skip_mod_names]

    def process_mod(mod: Dict) -> None:
        """Process one mod's main_units / land_units doubling and write its contribution into the shared compat-pack build dir.

        Each worker extracts into a per-mod scratch root (`temp/<package_name>/modded_*`), uses its own `DuplicateTracker`, gets a deep copy of the shared vanilla land_units reference, and writes TSVs whose filenames include `package_name` so workers never collide on output files.

        Args:
            mod (Dict): Entry from `SUPPORTED_MODS` for a non-vanilla mod. Must have `path` and `package_name`.
        """
        # Table names cannot end in numbers.
        package_name = mod["package_name"].replace(".pack", "").replace(" ", "_")
        if package_name[-1].isdigit():
            package_name = package_name[:-1]
        scratch_root = f"{TEMP_DIR}/{package_name}"
        variantmeshes_root = f"{scratch_root}/modded_variantmeshes"

        logging.info(f"Processing mod: {mod['package_name']}")
        tracker = DuplicateTracker()

        # Extract and load all the required and optional tables needed for this mod into the per-mod scratch dir.
        table_data = extract_and_load_table_data(mod["path"], TABLE_CONFIGS, scratch_root=scratch_root)
        if table_data is None:
            cleanup_modded_folders(scratch_root=scratch_root)
            return

        # This script doubles unit sizes, so mods without main_units_tables AND land_units_tables have nothing to process.
        if "main_units_tables_headers" not in table_data or "land_units_tables_headers" not in table_data:
            logging.info(f"Skipping {mod['package_name']}: no main_units_tables/land_units_tables to double.")
            cleanup_modded_folders(scratch_root=scratch_root)
            return

        # Extract the variantmeshes/variantmeshdefinitions folder into the per-mod scratch dir.
        variant_mesh_definitions_to_add = []
        extract_variantmeshes_folder(mod["path"], dest=variantmeshes_root)

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
        # Pass a deep copy of the shared vanilla reference so the fallback branch's in-place mutations stay worker-local.
        try:
            main_units_tables_df, land_units_tables_df = handle_main_units_tables(
                main_units_tables_df, land_units_tables_df, VANILLA_LAND_UNITS_TABLES_DF.copy(deep=True)
            )
        except ValueError as e:
            logging.error(f"Error processing mod: {mod['package_name']}: {e}")
            cleanup_modded_folders(scratch_root=scratch_root)
            return
        ########################################

        # Create mapping from the MODIFIED DataFrames (after doubling) for writing.
        main_units_mapping = {row["unit"]: row.to_dict() for _, row in main_units_tables_df.iterrows()}

        # Process units and collect related tables.
        list_of_data_to_add = []
        for _, row in land_units_tables_df.iterrows():
            data = row.to_dict()
            new_data = make_new_data_buckets(data["key"])

            if data["key"] in main_units_mapping:
                walk_land_unit_to_related_tables(
                    data=data,
                    main_unit_data=main_units_mapping[data["key"]],
                    table_data=table_data,
                    tracker=tracker,
                    new_data=new_data,
                    vanilla_mounts_keys=vanilla_mounts_keys,
                    variant_mesh_definitions_to_add=variant_mesh_definitions_to_add,
                    variantmeshes_root=variantmeshes_root,
                )

            list_of_data_to_add.append(new_data)

        if len(list_of_data_to_add) > 0:
            # Update the version info to include the new TSV name. This will also make RPFM rename to this filename when moving it into the packfile.
            land_units_version_info = modded_land_units_version_info.replace(
                modded_land_units_version_info.split("/")[-1], f"{MODDED_TABLE_NAME}_{package_name}"
            )
            main_units_version_info = modded_main_units_version_info.replace(
                modded_main_units_version_info.split("/")[-1], f"{MODDED_TABLE_NAME}_{package_name}"
            )

            tables_to_sort = [
                f"{TEMP_DIR}/{MODDED_TABLE_NAME}/db/land_units_tables",
                f"{TEMP_DIR}/{MODDED_TABLE_NAME}/db/main_units_tables",
            ]

            # Write the data to required and optional tables. Filenames include `package_name` so concurrent workers never write the same TSV.
            for data_to_add in list_of_data_to_add:
                write_updated_tsv_file(
                    data_to_add["land_units"],
                    modded_land_units_headers,
                    land_units_version_info,
                    f"{TEMP_DIR}/{MODDED_TABLE_NAME}/db/land_units_tables",
                    f"{MODDED_TABLE_NAME}_{package_name}",
                )
                write_updated_tsv_file(
                    data_to_add["main_units"],
                    modded_main_units_headers,
                    main_units_version_info,
                    f"{TEMP_DIR}/{MODDED_TABLE_NAME}/db/main_units_tables",
                    f"{MODDED_TABLE_NAME}_{package_name}",
                )
                write_optional_tables(
                    data_to_add, f"{TEMP_DIR}/{MODDED_TABLE_NAME}", f"{MODDED_TABLE_NAME}_{package_name}", table_data, tables_to_sort
                )

            # Move any captured variantmeshdefinitions (and their wh_variantmodels) out of the per-mod scratch dir into the compat pack.
            move_variantmesh_definitions(
                variant_mesh_definitions_to_add, f"{TEMP_DIR}/{MODDED_TABLE_NAME}", variantmeshes_root=variantmeshes_root
            )

            # After writing is complete, sort the required and optional tables. Each worker only sorts its own per-mod-named TSV file.
            for table_path in tables_to_sort:
                sort_tsv_data(table_path, f"{MODDED_TABLE_NAME}_{package_name}")

        cleanup_modded_folders(scratch_root=scratch_root)

    logging.info(f"Processing {len(modded_mods)} modded mods with {args.workers} worker thread(s).")
    run_parallel(modded_mods, process_mod, args.workers, label_fn=lambda m: f"mod {m.get('package_name', '<unknown>')}")

    # Move the modded folder to the ../warhammer3_mods folder.
    if os.path.exists(f"{TEMP_DIR}/{MODDED_TABLE_NAME}"):
        logging.info(f"Moving {MODDED_TABLE_NAME} to ../warhammer3_mods/.")
        merge_move(f"{TEMP_DIR}/{MODDED_TABLE_NAME}", f"../warhammer3_mods")

    if args.reset:
        reset_pack_folders(compat_pack_path)

    # Now merge the new files into the packfile.
    add_folder_to_pack(compat_pack_path, f"../warhammer3_mods/{MODDED_TABLE_NAME};")

    # Remove the vanilla temp folders.
    cleanup_folders(
        [
            f"{TEMP_DIR}/vanilla__kv_rules_tables",
            f"{TEMP_DIR}/vanilla__kv_unit_ability_scaling_rules_tables",
            f"{TEMP_DIR}/vanilla_battle_currency_army_special_abilities_cost_values_tables",
            f"{TEMP_DIR}/vanilla_land_units_tables",
            f"{TEMP_DIR}/vanilla_main_units_tables",
            f"{TEMP_DIR}/vanilla_special_ability_phases_tables",
            f"{TEMP_DIR}/vanilla_unit_size_global_scalings_tables",
            f"{TEMP_DIR}/vanilla_unit_stat_to_size_scaling_values_tables",
            f"{TEMP_DIR}/vanilla_mounts_tables",
        ]
    )

    log_elapsed_time("updating the double unit size mod", start_time)
