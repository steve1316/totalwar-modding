"""Script for merging unit data files for the GLF mod.

For every land_units TSV the GLF mod ships, this:
1. Inner-joins vanilla land_units_tables to the GLF keys (keeps only units GLF supports).
2. Overrides four combat-attribute columns on those vanilla rows with GLF's values.
3. Writes the merged TSVs back into the GLF `.pack` directly via rpfm_cli.

Extraction and pack-writing are fully automated; no manual file placement.
"""

import argparse
import logging
import os
import time
from typing import List, Dict, Set
from utilities import (
    cleanup_folders,
    ensure_temp_dir,
    extract_modded_tsv_data,
    extract_tsv_data,
    load_tsv_data,
    TEMP_DIR,
)
from supported_mods import SUPPORTED_MODS
from pipeline import add_folder_to_pack, clean_folder_name


# The GLF mod this script patches. Switch to the other "[GLF] Battle Mage" package_name if a future need arises.
GLF_TARGET_PACKAGE = "!!!1a_glf_unit_expansion.pack"
TARGET_TABLE = "land_units_tables"


def perform_inner_join(game_data: List[Dict], mod_keys: Set[str]):
    """Filter game data to only include rows with keys present in mod data.

    Args:
        game_data (List[Dict]): Full dataset from gameplay TSV.
        mod_keys (Set[str]): Set of animation keys from reference TSV.

    Returns:
        Filtered list of game data rows with matching keys.
    """
    return [row for row in game_data if row["key"] in mod_keys]


def update_combat_attributes(joined_data: List[Dict], mod_data: List[Dict]):
    """Merge animation and combat attributes from mod data into game data.

    Updates following columns:
    - man_animation
    - primary_missile_weapon
    - primary_ammo
    - ai_usage_group

    Args:
        joined_data (List[Dict]): Filtered game data rows.
        mod_data (List[Dict]): Reference data with animation/combat attributes.

    Returns:
        Updated game data with merged attributes.
    """
    updated_rows = []

    for game_row in joined_data:
        key = game_row["key"]
        mod_row = next((r for r in mod_data if r["key"] == key), None)

        if mod_row:
            merged_row = game_row.copy()
            merged_row.update(
                {
                    "man_animation": mod_row["man_animation"],
                    "primary_missile_weapon": mod_row["primary_missile_weapon"],
                    "primary_ammo": mod_row["primary_ammo"],
                    "ai_usage_group": mod_row["ai_usage_group"],
                }
            )
            updated_rows.append(merged_row)
        else:
            logging.warning(f"No mod data found for key: {key}")
            updated_rows.append(game_row)

    return updated_rows


def write_merged_tsv(output_path: str, headers: List[str], version_info: str, rows: List[Dict]) -> None:
    """Write a merged-data TSV file with the supplied headers and version_info, ordering each row's columns to match `headers`.

    Args:
        output_path (str): Destination TSV path. Parent dir is created if missing.
        headers (List[str]): Column headers to write on the first line (also drives row column order).
        version_info (str): The `#<table>;<version>;<path>` row to write on the second line.
        rows (List[Dict]): Row dicts to serialize. Each row must contain every header.
    """
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    with open(output_path, "w", encoding="utf-8") as f:
        f.write("\t".join(headers) + "\n")
        f.write(version_info + "\n")
        for row in rows:
            ordered_values = [row[header] for header in headers]
            f.write("\t".join(ordered_values) + "\n")


if __name__ == "__main__":
    logging.basicConfig(format="%(asctime)s - %(levelname)s - %(message)s", level=logging.INFO)
    start_time = time.time()

    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--pack",
        default=GLF_TARGET_PACKAGE,
        help="Target GLF .pack filename (must match a SUPPORTED_MODS entry by package_name). Defaults to the Unit Expansion pack.",
    )
    args = parser.parse_args()

    ensure_temp_dir()

    glf_mod = next((m for m in SUPPORTED_MODS if m["package_name"] == args.pack), None)
    if glf_mod is None:
        logging.error(f"Pack '{args.pack}' not found in SUPPORTED_MODS.")
        exit(1)
    if not glf_mod["path"] or not os.path.exists(glf_mod["path"]):
        logging.error(f"Pack '{args.pack}' is not installed at {glf_mod['path']}.")
        exit(1)

    glf_folder = clean_folder_name(args.pack)
    glf_scratch = f"{TEMP_DIR}/{glf_folder}"
    output_root = f"{TEMP_DIR}/{glf_folder}_merged"
    output_table_dir = f"{output_root}/db/{TARGET_TABLE}"

    try:
        # Extract the vanilla and GLF copies of land_units_tables.
        extract_tsv_data(TARGET_TABLE)
        vanilla_tsv_path = f"{TEMP_DIR}/vanilla_{TARGET_TABLE}/db/{TARGET_TABLE}/data__.tsv"

        extract_modded_tsv_data(TARGET_TABLE, glf_mod["path"], glf_scratch)
        glf_table_dir = f"{glf_scratch}/db/{TARGET_TABLE}"
        if not os.path.exists(glf_table_dir):
            logging.error(f"Pack '{args.pack}' does not contain a db/{TARGET_TABLE} folder.")
            exit(1)

        # Load vanilla once; reused for every GLF file.
        game_data, game_headers, game_version = load_tsv_data(vanilla_tsv_path)
        logging.info(f"Loaded {len(game_data)} vanilla rows from {vanilla_tsv_path}.")

        glf_tsv_files = sorted(f for f in os.listdir(glf_table_dir) if f.endswith(".tsv"))
        if not glf_tsv_files:
            logging.error(f"Pack '{args.pack}' has no .tsv files under db/{TARGET_TABLE}.")
            exit(1)

        for filename in glf_tsv_files:
            glf_tsv_path = f"{glf_table_dir}/{filename}"
            mod_data, _, _ = load_tsv_data(glf_tsv_path)

            mod_keys = {row["key"] for row in mod_data}
            joined_data = perform_inner_join(game_data, mod_keys)
            updated_data = update_combat_attributes(joined_data, mod_data)

            # Vanilla's version_info path component is `data__`; swap it for the GLF filename (sans `.tsv`) so rpfm_cli places the binary at the original GLF in-pack path on import.
            output_path_basename = filename[: -len(".tsv")]
            merged_version_info = game_version.replace(game_version.split("/")[-1], output_path_basename)

            write_merged_tsv(f"{output_table_dir}/{filename}", game_headers, merged_version_info, updated_data)
            logging.info(f"Merged {len(updated_data)} rows from {filename} (of {len(mod_data)} GLF rows / {len(game_data)} vanilla rows).")

        # Push the merged folder back into the GLF pack. `--tsv-to-binary` (set inside `add_folder_to_pack`) converts each TSV to its RPFM binary form at import.
        add_folder_to_pack(glf_mod["path"], f"{output_root};")
        logging.info(f"Wrote merged tables back into {glf_mod['path']}.")
    except Exception:
        logging.exception("glf_inner_join failed.")
    finally:
        cleanup_folders([f"{TEMP_DIR}/vanilla_{TARGET_TABLE}", glf_scratch, output_root])

    end_time = round(time.time() - start_time, 2)
    logging.info(f"Total time for inner join: {end_time} seconds or {round(end_time / 60, 2)} minutes.")
