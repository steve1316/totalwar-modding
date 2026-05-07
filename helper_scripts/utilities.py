"""Utility functions for Total War Warhammer 3 modding."""

import pandas as pd
import subprocess
import os
import shutil
import re
import logging
import json
from typing import List, Dict


STEAM_LIBRARY_DRIVE = "F:"
FILEPATH_TO_VANILLA_DATA_TABLES = f"{STEAM_LIBRARY_DRIVE}\\SteamLibrary\\steamapps\\common\\Total War WARHAMMER III\\data\\db.pack"
SCHEMA_PATH = "./schemas/schema_wh3.json"

# TSV file structure constants
HEADER_ROW_INDEX = 0
VERSION_ROW_INDEX = 1
DATA_START_ROW = 2

# Schema cache: maps schema_path -> schema["definitions"] dictionary.
_SCHEMA_CACHE: Dict[str, Dict] = {}


FIELD_TYPE_FIXERS = {
    "I32": int,
    "F32": float,
    "StringU8": str,
    "Bool": lambda x: str(x).lower() in ("true", "1"),
}


def extract_tsv_data(table_name: str):
    """Extract the TSV data for a given table name from the vanilla data tables to a folder prepended with \"vanilla_\".

    Args:
        table_name (str): The name of the table to extract.
    """
    subprocess.run(
        [
            "./rpfm_cli.exe",
            "--game",
            "warhammer_3",
            "pack",
            "extract",
            "--pack-path",
            FILEPATH_TO_VANILLA_DATA_TABLES,
            "--tables-as-tsv",
            "./schemas/schema_wh3.ron",
            "--file-path",
            f"db/{table_name}/data__;./vanilla_{table_name}",
        ]
    )

    logging.info(f'TSV file "{table_name}" successfully extracted.')


def extract_modded_tsv_data(table_name: str, packfile_path: str, extract_path: str):
    """Extract the TSV data for a given table name from the modded data tables.

    Args:
        table_name (str): The name of the table to extract.
        packfile_path (str): The path to the packfile to extract from.
        extract_path (str): The path to extract the TSV data to.
    """
    subprocess.run(
        [
            "./rpfm_cli.exe",
            "--game",
            "warhammer_3",
            "pack",
            "extract",
            "--pack-path",
            packfile_path,
            "--tables-as-tsv",
            "./schemas/schema_wh3.ron",
            "--folder-path",
            f"db/{table_name};{extract_path}",
        ]
    )

    if not os.path.exists(extract_path):
        logging.warning(f"No TSV file(s) for \"{table_name}\" found in {extract_path} for the mod \"{packfile_path.split('/')[-1]}\".")
    else:
        logging.info(f"TSV file(s) for \"{table_name}\" successfully extracted to {extract_path} for the mod \"{packfile_path.split('/')[-1]}\".")


def load_tsv_data(file_path: str):
    """Load and parse TSV file into structured data.

    Args:
        file_path (str): Path to TSV file to load.

    Returns:
        A tuple of a list of row dictionaries with header keys, the headers, and version information.
    """
    with open(file_path, "r", encoding="utf-8") as f:
        lines = f.readlines()

    headers = lines[HEADER_ROW_INDEX].strip().split("\t")
    version_info = lines[VERSION_ROW_INDEX].strip()

    data = []
    for line in lines[DATA_START_ROW:]:
        if not line.strip():
            # Skip empty lines
            continue
        # Split by tab and ensure we have the same number of values as headers.
        # If a row has fewer values, pad with empty strings.
        values = line.rstrip("\n\r").split("\t")
        # Pad values to match header count if needed.
        while len(values) < len(headers):
            values.append("")
        # Truncate if there are too many values (shouldn't happen, but be safe).
        values = values[: len(headers)]
        data.append(dict(zip(headers, values)))

    return data, headers, version_info


def load_multiple_tsv_data(folder_path: str, table_name: str = None, schema_path: str = SCHEMA_PATH):
    """Load all TSV files in a folder and parse them all into a single list of structured data.

    If table_name is provided, each TSV file will be updated to the latest schema version before loading.

    Args:
        folder_path (str): Path to the folder containing the TSV files.
        table_name (str, optional): Name of the table. If provided, files will be updated to latest version before loading.
        schema_path (str, optional): Path to the schema JSON file. Defaults to SCHEMA_PATH.

    Returns:
        A tuple of a list of row dictionaries with header keys, the headers, and version information of which the latter belongs to the first TSV file found.
    """
    merged_data_set = set()
    headers = None
    version_info = None
    skipped_count = 0

    for file_name in os.listdir(folder_path):
        if file_name.endswith(".tsv"):
            file_path = os.path.join(folder_path, file_name)

            # Update file to latest version if table_name is provided.
            if table_name:
                if not update_single_tsv_file_to_latest_version(file_path, table_name, schema_path):
                    logging.warning(f"Skipping file '{file_name}' due to update failure.")
                    skipped_count += 1
                    continue

            temp_data, temp_headers, temp_version_info = load_tsv_data(file_path)
            # Convert each row dict to a tuple of items for set storage.
            for row in temp_data:
                merged_data_set.add(tuple(row.items()))
            if headers is None:
                headers = temp_headers
            if version_info is None:
                version_info = temp_version_info

    # Convert back to list of dictionaries. Sort the deduplicated rows so the iteration order is stable across runs (sets have hash-randomized iteration order).
    merged_data = [dict(row_tuple) for row_tuple in sorted(merged_data_set)]
    if skipped_count > 0:
        logging.info(f"Loaded a total of {len(merged_data)} unique rows for {folder_path} (skipped {skipped_count} outdated file(s)).")
    else:
        logging.info(f"Loaded a total of {len(merged_data)} unique rows for {folder_path}.")
    return merged_data, headers, version_info


def read_and_clean_tsv(tsv_file_path: str, table_type: str, allowed_patterns: List[str] = None, do_not_clean: bool = False):
    """Load and clean TSV file based on the table type.

    Args:
        tsv_file_path (str): Path to the TSV file.
        table_type (str): Type of the table to determine cleaning rules.
        allowed_patterns (List[str], optional): Patterns to allow in specific columns.
        do_not_clean (bool, optional): Whether to not clean the TSV file. Defaults to False.

    Returns:
        Cleaned DataFrame.
    """
    df = pd.read_csv(tsv_file_path, sep="\t")
    df = df.iloc[1:]  # Remove the first row

    if not do_not_clean and table_type == "main_units_tables":
        df = df[~df["land_unit"].str.contains("_summoned")]
        df = df[~df["land_unit"].str.contains("_dummy")]
        df = df[~((df["multiplayer_cost"] == 0) & ~df["caste"].isin(["lord", "hero", "generic"]))]

    elif not do_not_clean and table_type == "character_skill_node_set_items_tables":
        if allowed_patterns:
            df = df[df["item"].str.contains("|".join(allowed_patterns))]
        df = df[~df["item"].str.contains("dummy")]

    elif not do_not_clean and table_type == "character_skill_nodes_tables":
        if allowed_patterns:
            df = df[df["key"].str.contains("|".join(allowed_patterns))]
        df = df[~df["key"].str.contains("dummy")]

    logging.info(f"TSV file '{tsv_file_path}' successfully read and cleaned for table '{table_type}'.")
    return df


def write_updated_tsv_file(data: List[Dict], headers: List[str], version_info: str, target_path: str, file_name: str, allow_duplicates: bool = False):
    """Write the updated TSV file to the target path.

    Args:
        data (List[Dict]): List of dictionaries representing the data to write to the TSV file.
        headers (List[str]): List of headers for the TSV file.
        version_info (str): String containing the version information for the TSV file.
        target_path (str): Path to the target directory where the updated TSV file will be written.
        file_name (str): Name of the TSV file to write.
        allow_duplicates (bool, optional): Whether to allow duplicates in the TSV file. Defaults to False.
    """
    # Create the target directory if it doesn't exist
    os.makedirs(target_path, exist_ok=True)

    file_path = f"{target_path}/{file_name}.tsv"
    file_exists = os.path.exists(file_path)

    # If file doesn't exist, we need to write headers and version info
    if not file_exists:
        with open(file_path, "w", encoding="utf-8") as f:
            f.write("\t".join(headers) + "\n")
            f.write(version_info + "\n")

    # Read existing data to check for duplicates if needed.
    # For unit_purchasable_effect_sets_tables, use a composite key (unit + purchasable_effect).
    existing_keys = set()
    if not allow_duplicates and file_exists:
        try:
            existing_data, _, _ = load_tsv_data(file_path)
            # Check if this is unit_purchasable_effect_sets_tables which uses a composite key.
            if "unit" in headers and "purchasable_effect" in headers:
                existing_keys = {(row["unit"], row["purchasable_effect"]) for row in existing_data}
            else:
                existing_keys = {row[headers[0]] for row in existing_data}
        except:
            pass

    # Append new data to the file.
    with open(file_path, "a", encoding="utf-8") as f:
        for row in data:
            # For unit_purchasable_effect_sets_tables, use a composite key.
            if not allow_duplicates and "unit" in headers and "purchasable_effect" in headers:
                composite_key = (row["unit"], row["purchasable_effect"])
                if composite_key in existing_keys:
                    continue
                existing_keys.add(composite_key)
            else:
                key_column = headers[0]
                if not allow_duplicates and row[key_column] in existing_keys:
                    continue
                existing_keys.add(row[key_column])
            # Sometimes the mod's table is outdated. The provided headers is always the latest so it may have new columns that these old tables do not have.
            # In that case, we set the cell to an empty string.
            ordered_values = [row[header] if row.get(header) else "" for header in headers]
            f.write("\t".join(ordered_values) + "\n")


def sort_tsv_data(target_path: str, file_name: str, sort_key: str = None):
    """Sort the data in a TSV file by a specified column.

    Args:
        target_path (str): Path to the directory containing the TSV file.
        file_name (str): Name of the TSV file without the .tsv extension.
        sort_key (str, optional): Column name to sort by. If None, sorts by the first column. Defaults to None.
    """
    file_path = f"{target_path}/{file_name}.tsv"
    if not os.path.exists(file_path):
        logging.error(f"TSV file {file_path} does not exist to sort.")
        return

    # Load the existing data.
    data, headers, version_info = load_tsv_data(file_path)

    # Determine the sort key and defaults to the first column if not specified.
    sort_key = sort_key or headers[0]

    # Sort the data.
    data.sort(key=lambda x: x.get(sort_key, ""))

    # Write the sorted data back to the file.
    with open(file_path, "w", encoding="utf-8") as f:
        # Write headers and version info.
        f.write("\t".join(headers) + "\n")
        f.write(version_info + "\n")

        # Write all data rows and handle missing columns with empty strings.
        for row in data:
            ordered_values = [row.get(header, "") for header in headers]
            f.write("\t".join(ordered_values) + "\n")


def merge_move(source_path: str, destination_path: str):
    """Moves a folder to its destination and overwrite any existing files.

    Args:
        source_path (str): The path to the source folder.
        destination_path (str): The path to the destination folder.
    """
    destination_path = os.path.join(destination_path, os.path.basename(source_path))
    os.makedirs(destination_path, exist_ok=True)

    for root, _, files in os.walk(source_path):
        # Determine the relative path to recreate the folder structure.
        relative_path = os.path.relpath(root, source_path)
        destination_dir = os.path.join(destination_path, relative_path)
        os.makedirs(destination_dir, exist_ok=True)

        # Move files to the destination folder while overwriting any existing files.
        for file in files:
            source_file = os.path.join(root, file)
            destination_file = os.path.join(destination_dir, file)
            if os.path.exists(destination_file):
                os.remove(destination_file)
            shutil.move(source_file, destination_file)

    # Remove the source folder afterwards.
    shutil.rmtree(source_path)


def cleanup_folders(folders_to_cleanup: List[str]):
    """Clean up the folders that were created during the extraction process.

    Args:
        folders_to_cleanup (List[str]): List of folders to cleanup.
    """
    for folder in folders_to_cleanup:
        if os.path.exists(folder):
            shutil.rmtree(folder)


def extract_model_paths_from_variantmeshdefinition(file_path):
    """Extract model paths from a variantmeshdefinition file.

    Args:
        file_path (str): Path to the variantmeshdefinition file.

    Returns:
        List[str]: List of normalized model directory paths.
    """
    model_paths = []
    try:
        with open(file_path, "r", encoding="utf-8") as f:
            content = f.read()
            # Use regex to find all model paths
            matches = re.findall(r'model="([^"]+)"', content)

            for match in matches:
                # Normalize path (convert backslashes to forward slashes).
                normalized_path = match.replace("\\", "/")

                # Remove the variantmeshes/wh_variantmodels/ prefix if present (case insensitive).
                normalized_path = re.sub(r"^(?:variantmeshes/|VariantMeshes/)?(?:wh_variantmodels/)?", "", normalized_path)

                # Extract just the directory path without the filename.
                dir_path = os.path.dirname(normalized_path)

                model_paths.append(dir_path)
    except Exception as e:
        logging.error(f"Error reading {file_path}: {e}")

    return model_paths


def _load_schema_table_info(schema_path: str, table_name: str):
    """Load schema JSON and find the latest version for a table.

    Args:
        schema_path (str): Path to the schema JSON file.
        table_name (str): Name of the table to find.

    Returns:
        A tuple of (latest_version, fields_list) or None if table not found.
        Fields are sorted by ca_order.
    """
    try:
        # Check cache first.
        if schema_path not in _SCHEMA_CACHE:
            # Load schema from file and cache it.
            with open(schema_path, "r", encoding="utf-8") as f:
                _SCHEMA_CACHE[schema_path] = json.load(f)["definitions"]

        schema = _SCHEMA_CACHE[schema_path]

        if table_name not in schema:
            logging.error(f"Table '{table_name}' not found in schema.")
            return None

        table_versions = schema[table_name]
        if not isinstance(table_versions, list) or len(table_versions) == 0:
            logging.error(f"No versions found for table '{table_name}' in schema.")
            return None

        # Find the version with the highest version number.
        # Note that for main_units_tables, there are multiple versions in the 30s that are missing some fields so we need to use the version number less than 30.
        if table_name == "main_units_tables":
            latest_version_entry = max(table_versions, key=lambda x: x.get("version", 0) if x.get("version", 0) < 30 else 0)
        else:
            latest_version_entry = max(table_versions, key=lambda x: x.get("version", 0))
        latest_version = latest_version_entry.get("version")
        fields = latest_version_entry.get("fields", [])

        # Sort fields by ca_order.
        fields_sorted = sorted(fields, key=lambda x: x.get("ca_order", 0))

        return latest_version, fields_sorted
    except Exception as e:
        logging.error(f"Error loading schema from {schema_path}: {e}")
        return None


def _parse_version_from_version_info(version_info: str):
    """Parse version number from version_info row.

    Args:
        version_info (str): The version_info row string (format: #table_name;version;path).

    Returns:
        The version number as an integer, or None if parsing fails.
    """
    try:
        # Format is: #table_name;version;path
        parts = version_info.split(";")
        if len(parts) >= 2:
            version_str = parts[1].strip()
            return int(version_str)
        return None
    except (ValueError, IndexError) as e:
        logging.warning(f"Failed to parse version from version_info '{version_info}': {e}")
        return None


def _update_version_info(version_info: str, new_version: int):
    """Update the version number in version_info row while preserving path.

    Args:
        version_info (str): The original version_info row string.
        new_version (int): The new version number to use.

    Returns:
        Updated version_info string with new version number.
    """
    try:
        # Format is: #table_name;version;path
        parts = version_info.split(";")
        if len(parts) >= 3:
            # Preserve table_name and path, update version.
            return f"{parts[0]};{new_version};{parts[2]}"
        elif len(parts) == 2:
            # Only table_name and version, no path.
            return f"{parts[0]};{new_version};"
        else:
            # Malformed, try to reconstruct.
            return f"{version_info.split(';')[0]};{new_version};"
    except Exception as e:
        logging.warning(f"Failed to update version_info '{version_info}': {e}")
        return version_info


def check_tsv_files_at_latest_version(folder_path: str, table_name: str, schema_path: str = SCHEMA_PATH):
    """Check if all TSV files in a folder are at the latest schema version.

    Args:
        folder_path (str): Path to the folder containing TSV files for the table.
        table_name (str): Name of the table (e.g., "battle_entities_tables").
        schema_path (str, optional): Path to the schema JSON file. Defaults to SCHEMA_PATH.

    Returns:
        Tuple of (bool, int): (True if all files are at latest version, latest_version_number).
        Returns (False, None) if schema not found or folder doesn't exist.
    """
    # Load schema and get latest version info.
    schema_info = _load_schema_table_info(schema_path, table_name)
    if schema_info is None:
        return False, None

    latest_version, _ = schema_info

    # Check each TSV file in the folder.
    if not os.path.exists(folder_path):
        return False, None

    tsv_files = [f for f in os.listdir(folder_path) if f.endswith(".tsv")]
    if len(tsv_files) == 0:
        return True, latest_version  # No files means technically "all" are at latest version.

    for file_name in tsv_files:
        file_path = os.path.join(folder_path, file_name)
        try:
            # Load just the version_info row to check version.
            with open(file_path, "r", encoding="utf-8") as f:
                lines = f.readlines()

            if len(lines) <= VERSION_ROW_INDEX:
                logging.warning(f"File {file_name} does not have a version_info row.")
                return False, latest_version

            version_info = lines[VERSION_ROW_INDEX].strip()
            current_version = _parse_version_from_version_info(version_info)

            if current_version is None or current_version < latest_version:
                logging.debug(f"File {file_name} is at version {current_version}, but latest is {latest_version}.")
                return False, latest_version
        except Exception as e:
            logging.warning(f"Error checking version for {file_name}: {e}")
            return False, latest_version

    return True, latest_version


def update_single_tsv_file_to_latest_version(file_path: str, table_name: str, schema_path: str = SCHEMA_PATH):
    """Update a single TSV file to the latest schema version.

    Args:
        file_path (str): Path to the TSV file to update.
        table_name (str): Name of the table (e.g., "battle_entities_tables").
        schema_path (str, optional): Path to the schema JSON file. Defaults to SCHEMA_PATH.

    Returns:
        True if the file was updated or was already at latest version, False if update failed.
    """
    # Load schema and get latest version info.
    schema_info = _load_schema_table_info(schema_path, table_name)
    if schema_info is None:
        logging.error(f"Cannot update TSV file '{file_path}': schema not found for table '{table_name}'.")
        return False

    latest_version, schema_fields = schema_info

    try:
        # Load the TSV data.
        data, headers, version_info = load_tsv_data(file_path)

        # Parse current version.
        current_version = _parse_version_from_version_info(version_info)

        # Check if update is needed.
        if current_version is not None and current_version >= latest_version:
            logging.debug(f"File {os.path.basename(file_path)} is already at version {current_version} (latest is {latest_version}).")
            return True
        elif table_name == "main_units_tables" and current_version < latest_version:
            logging.info(
                f"Updating {os.path.basename(file_path)} from version {current_version} to {latest_version} but will keep the current version number as is."
            )
        else:
            logging.info(f"Updating {os.path.basename(file_path)} from version {current_version} to {latest_version}.")

        # Create a mapping of field names to their default values and ca_order.
        field_defaults = {}
        field_order = {}
        for field in schema_fields:
            field_name = field.get("name")
            default_value = field.get("default_value")
            ca_order = field.get("ca_order", 0)

            if field_name:
                # Convert null default values to empty strings.
                field_defaults[field_name] = "" if default_value is None else str(default_value)
                field_order[field_name] = ca_order

        # Get the correct column order sorted by ca_order.
        ordered_headers = sorted(field_order.keys(), key=lambda x: field_order[x])

        # Add missing columns to each data row with default values.
        missing_columns = set(ordered_headers) - set(headers)
        if missing_columns:
            logging.info(f"Adding {len(missing_columns)} missing column(s): {', '.join(sorted(missing_columns))}.")
            for row in data:
                for col in missing_columns:
                    row[col] = field_defaults[col]

        # Reorder all columns according to schema order.
        # Also ensure all rows have values for all columns (use defaults for any still missing).
        updated_data = []
        for row in data:
            updated_row = {}
            for col in ordered_headers:
                # Use existing value if present, otherwise use default.
                updated_row[col] = row.get(col, field_defaults[col])
            updated_data.append(updated_row)

        # Update version_info with new version.
        if table_name == "main_units_tables" and current_version < latest_version:
            updated_version_info = version_info
        else:
            updated_version_info = _update_version_info(version_info, latest_version)

        # Write the updated TSV back to file.
        with open(file_path, "w", encoding="utf-8") as f:
            # Write headers in correct order.
            header_line = "\t".join(ordered_headers) + "\n"
            f.write(header_line)

            # Write updated version info with the same number of tab-separated columns as headers.
            version_info_columns = [updated_version_info] + [""] * (len(ordered_headers) - 1)
            version_info_line = "\t".join(version_info_columns) + "\n"
            # Verify the version_info row has the correct number of tab-separated values.
            version_info_values = version_info_line.rstrip("\n").split("\t")
            if len(version_info_values) != len(ordered_headers):
                logging.error(f"Version info row has {len(version_info_values)} columns but expected {len(ordered_headers)}. This should not happen!")
                # Force correct format.
                version_info_columns = [updated_version_info] + [""] * (len(ordered_headers) - 1)
                version_info_line = "\t".join(version_info_columns) + "\n"
            f.write(version_info_line)

            # Write all data rows.
            for row in updated_data:
                # Ensure we have exactly the same number of values as headers.
                ordered_values = [str(row.get(header, "")) for header in ordered_headers]
                # Verify we have the correct number of columns.
                if len(ordered_values) != len(ordered_headers):
                    logging.warning(f"Row has {len(ordered_values)} values but expected {len(ordered_headers)} headers. Padding or truncating.")
                    while len(ordered_values) < len(ordered_headers):
                        ordered_values.append("")
                    ordered_values = ordered_values[: len(ordered_headers)]
                f.write("\t".join(ordered_values) + "\n")

        logging.info(f"Successfully updated {os.path.basename(file_path)}.")
        return True

    except Exception as e:
        logging.error(f"Error updating file {os.path.basename(file_path)}: {e}")
        return False


def update_tsv_files_to_latest_version(folder_path: str, table_name: str, schema_path: str = SCHEMA_PATH):
    """Update all TSV files in a folder to the latest schema version.

    This function processes all TSV files in the given folder, adds missing columns
    with default values, reorders columns according to ca_order, and updates the
    version number in the version_info row.

    Args:
        folder_path (str): Path to the folder containing TSV files for the table.
        table_name (str): Name of the table (e.g., "battle_entities_tables").
        schema_path (str, optional): Path to the schema JSON file. Defaults to SCHEMA_PATH.
    """
    if not os.path.exists(folder_path):
        logging.error(f"Folder path does not exist: {folder_path}")
        return

    tsv_files = [f for f in os.listdir(folder_path) if f.endswith(".tsv")]
    if len(tsv_files) == 0:
        logging.warning(f"No TSV files found in folder: {folder_path}")
        return

    logging.info(f"Processing {len(tsv_files)} TSV file(s) in {folder_path}.")

    for file_name in tsv_files:
        file_path = os.path.join(folder_path, file_name)
        update_single_tsv_file_to_latest_version(file_path, table_name, schema_path)


def validate_and_fix_tsv_types(df: pd.DataFrame, table_name: str, schema_path: str = SCHEMA_PATH):
    """
    Validate and fix DataFrame values according to schema field types.

    Args:
        df (pd.DataFrame): Input DataFrame to validate/fix.
        table_name (str): Name of table in schema.
        schema_path (str, optional): Path to the schema JSON file. Defaults to SCHEMA_PATH.

    Returns:
        A new DataFrame with corrected values.
    """
    logging.info(f"Validating and fixing TSV data for table '{table_name}' with df having {len(df)} rows.")
    schema_info = _load_schema_table_info(schema_path, table_name)
    if schema_info is None:
        logging.error(f"Schema not found for table '{table_name}'.")
        return df

    _, schema_fields = schema_info

    # Build the field type mapping.
    field_types = {field["name"]: field["field_type"] for field in schema_fields}

    for col in df.columns:
        expected_type = field_types.get(col)
        if expected_type is None:
            continue

        fixer = FIELD_TYPE_FIXERS.get(expected_type, str)

        for idx, value in df[col].items():
            try:
                if value == "nan":
                    df.at[idx, col] = ""
                    continue
                if value == "" or value is None:
                    continue

                if expected_type == "I32":
                    value = value.split(".")[0]
                fixed_value = fixer(value)

                # Apply formatting for specific types.
                if expected_type == "F32":
                    fixed_value = f"{fixed_value:.4f}"
                else:
                    fixed_value = str(fixed_value)

                df.at[idx, col] = fixed_value

            except Exception as e:
                logging.warning(f"Failed to convert value '{value}' in column '{col}' " f"to {expected_type}. Keeping original. Error: {e}")
                continue

    logging.info(f"Validation and fixing completed for table '{table_name}' with df having {len(df)} rows.")
    return df
