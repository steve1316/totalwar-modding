"""Script to update the 2x unit size mod by merging in the vanilla and modded data tables from supported mods."""

import logging
import time
import os
from typing import Dict, Optional
import pandas as pd
from core.utilities import (
    extract_tsv_data,
    load_tsv_data,
    log_elapsed_time,
    make_common_argparser,
    run_parallel,
    setup_script_logging,
    write_updated_tsv_file,
    TsvAppendBuffer,
    read_and_clean_tsv,
    validate_and_fix_tsv_types,
    sort_tsv_data,
    cleanup_folders,
    drop_duplicate_rows,
    merge_move,
    ensure_temp_dir,
    clear_temp_root,
    TEMP_DIR,
)
from core.delta import publish_pack
from core.pipeline import (
    DuplicateTracker,
    add_folder_to_pack,
    cleanup_modded_folders,
    extract_and_load_table_data,
    load_vanilla_keys,
    make_new_data_buckets,
    reset_pack_folders,
    walk_land_unit_to_related_tables,
    workshop_pack_path,
    write_optional_tables,
    TABLE_CONFIGS,
    TABLE_KEY_FIELDS,
)
from data.supported_mods import SUPPORTED_MODS


MODDED_TABLE_NAME = "!!!!!!!2xunitsize_compat"
VANILLA_LAND_UNITS_TABLES_DF = None
VANILLA_ENGINE_TYPES: Dict[str, str] = {}
# Submods that only rebalance their parent mod's units. The compat is always on, so shipping their rows would force them on players who only have the parent.
PARENT_OVERRIDE_SUBMODS = {"Lost Calm: Nakai Submod"}


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
    df: pd.DataFrame,
    engine_types: Dict[str, str],
    land_units_tables_df: pd.DataFrame = None,
    reference_vanilla_land_units_tables_df: pd.DataFrame = None,
):
    """Handle the main_units_tables table. In addition, it also modifies the land_units_tables table to match.

    Args:
        df (pd.DataFrame): DataFrame containing the main_units_tables table.
        engine_types (Dict[str, str]): battlefield_engines_tables key -> engine_type, used to tell crewless vehicles from crewed guns.
        land_units_tables_df (pd.DataFrame): DataFrame containing the land_units_tables table.
        reference_vanilla_land_units_tables_df (pd.DataFrame): DataFrame containing the reference vanilla land_units_tables table.

    Returns:
        Tuple containing the modified main_units_tables and land_units_tables dataframes.
    """
    df["num_men"] = df["num_men"].astype(float).astype(int).astype(str)

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

    # For each main unit, double num_men and its land unit's num_mounts, num_engines and rank_depth, plus bonus_hit_points for lords, heroes and monsters.
    # Single vehicles keep their size and a land unit shared by several main units is only doubled once.
    doubled_land_units = set()
    for index, row in df.iterrows():
        mask = land_units_tables_df["key"] == row["land_unit"]

        if mask.sum() == 0:
            # The mod's main unit points at a vanilla land unit, so read it from the vanilla reference instead.
            mask = reference_vanilla_land_units_tables_df["key"] == row["land_unit"]
            if mask.sum() == 0:
                logging.error(f"No matching row found for {row['land_unit']} in the land_units_tables table.")
                raise ValueError("No matching row found for the land unit in the land_units_tables table.")

            # Writes land in this throwaway copy and are dropped. The vanilla compat file already ships the doubled row, so writing it again would double it twice.
            src_df = reference_vanilla_land_units_tables_df
        else:
            src_df = land_units_tables_df

        # A unit built on one crewless vehicle (Steam Tank, Luminark, Land Ship) has its crew and draught animals fixed to that model, so it keeps its size.
        num_engines = int(float(src_df.loc[mask, "num_engines"].iloc[0]))
        engine_type = engine_types.get(src_df.loc[mask, "engine"].iloc[0], "")
        single_vehicle = num_engines == 1 and engine_type.startswith("Generic_No_Crew")

        # Double the num_men column but only if the original value is greater than 1.
        if not single_vehicle and int(row["num_men"]) > 1:
            df.loc[index, "num_men"] = str(int(row["num_men"]) * 2)

        # Several main units can share one land unit (e.g. Imperial Supply copies). Only double it once.
        if row["land_unit"] in doubled_land_units:
            continue
        doubled_land_units.add(row["land_unit"])

        # Double the bonus HP of lords, heroes and monsters.
        if row["caste"] in ["lord", "hero", "monster"]:
            src_df.loc[mask, "bonus_hit_points"] = (src_df.loc[mask, "bonus_hit_points"].astype(int) * 2).astype(str)

        if single_vehicle:
            continue

        if row["caste"] in ["warmachine", "chariot"]:
            if num_engines == 0:
                # If num_engines is 0, the value was stored in num_mounts instead, so always double num_mounts, even if it's 1.
                src_df.loc[mask, "num_mounts"] = str(int(src_df.loc[mask, "num_mounts"].iloc[0]) * 2)
            else:
                # A single crewed gun (Hellcannon, Queen Bess) stays one gun and only doubles its crew.
                if num_engines > 1:
                    src_df.loc[mask, "num_engines"] = str(num_engines * 2)
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
        cleanup_folders([f"../warhammer3_mods/{MODDED_TABLE_NAME}/db"])

    ensure_temp_dir()

    try:

        # Clean up any existing scratch folders.
        cleanup_folders([f"{TEMP_DIR}/{MODDED_TABLE_NAME}"])
        cleanup_modded_folders()

        # Mods' versions of vanilla rows are never shipped, so the compat cannot push one mod's edits onto everyone.
        vanilla_keys = load_vanilla_keys(TABLE_KEY_FIELDS)

        # Extract vanilla battlefield_engines_tables so single vehicles can be told apart from crewed guns.
        extract_tsv_data("battlefield_engines_tables")
        vanilla_engines_dataframe = read_and_clean_tsv(f"{TEMP_DIR}/vanilla_battlefield_engines_tables/db/battlefield_engines_tables/data__.tsv", "battlefield_engines_tables")
        VANILLA_ENGINE_TYPES = dict(zip(vanilla_engines_dataframe["key"], vanilla_engines_dataframe["engine_type"]))

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
                df, land_units_tables_df = handle_main_units_tables(df, VANILLA_ENGINE_TYPES)
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
        for name in sorted(PARENT_OVERRIDE_SUBMODS):
            logging.info(f"Skipping {name}: it only rebalances its parent mod's units, which the compat already doubles.")
        skip_mod_names |= PARENT_OVERRIDE_SUBMODS
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
                # The mod's own engines override vanilla ones with the same key.
                engine_types = {**VANILLA_ENGINE_TYPES, **{key: row["engine_type"] for key, row in table_data["battlefield_engines_tables"].items()}}
                main_units_tables_df, land_units_tables_df = handle_main_units_tables(
                    main_units_tables_df, engine_types, land_units_tables_df, VANILLA_LAND_UNITS_TABLES_DF.copy(deep=True)
                )
            except ValueError as e:
                logging.error(f"Error processing mod: {mod['package_name']}: {e}")
                cleanup_modded_folders(scratch_root=scratch_root)
                return
            ########################################

            # Create mapping from the MODIFIED DataFrames (after doubling) for writing.
            main_units_mapping = {row["unit"]: row.to_dict() for _, row in main_units_tables_df.iterrows()}

            land_units_records = land_units_tables_df.to_dict("records")
            land_units_by_key = {row["key"]: row for row in land_units_records}

            # Process units and collect related tables.
            list_of_data_to_add = []
            for data in land_units_records:
                new_data = make_new_data_buckets(data["key"])

                if data["key"] in main_units_mapping:
                    walk_land_unit_to_related_tables(
                        data=data,
                        main_unit_data=main_units_mapping[data["key"]],
                        table_data=table_data,
                        tracker=tracker,
                        new_data=new_data,
                        land_units_by_key=land_units_by_key,
                        vanilla_keys=vanilla_keys,
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
                # The buffer writes each file once instead of re-reading it for every unit.
                tsv_buffer = TsvAppendBuffer()
                for data_to_add in list_of_data_to_add:
                    tsv_buffer.add(
                        data_to_add["land_units"],
                        modded_land_units_headers,
                        land_units_version_info,
                        f"{TEMP_DIR}/{MODDED_TABLE_NAME}/db/land_units_tables",
                        f"{MODDED_TABLE_NAME}_{package_name}",
                    )
                    tsv_buffer.add(
                        data_to_add["main_units"],
                        modded_main_units_headers,
                        main_units_version_info,
                        f"{TEMP_DIR}/{MODDED_TABLE_NAME}/db/main_units_tables",
                        f"{MODDED_TABLE_NAME}_{package_name}",
                    )
                    write_optional_tables(
                        data_to_add, f"{TEMP_DIR}/{MODDED_TABLE_NAME}", f"{MODDED_TABLE_NAME}_{package_name}", table_data, tables_to_sort, writer=tsv_buffer.add
                    )
                tsv_buffer.flush()

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

        # Mods that share a unit write the same rows into their own files. Keep one copy of each.
        logging.info(f"Dropped {drop_duplicate_rows(f'../warhammer3_mods/{MODDED_TABLE_NAME}/db')} duplicate rows from {MODDED_TABLE_NAME}.")

        def write_compat_pack() -> None:
            """Replace the compat pack's contents with the regenerated files."""
            if args.reset:
                reset_pack_folders(compat_pack_path)
            add_folder_to_pack(compat_pack_path, f"../warhammer3_mods/{MODDED_TABLE_NAME};")

        publish_pack("3621939685", compat_pack_path, f"../warhammer3_mods/{MODDED_TABLE_NAME}", write_compat_pack)

    finally:
        clear_temp_root()

    log_elapsed_time("updating the double unit size mod", start_time)
