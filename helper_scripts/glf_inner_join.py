"""Script for merging unit data files for the GLF mod.

Processes TSV files to:
1. Perform inner join on unit keys between gameplay data and animation data.
2. Update specific combat attributes from reference data.
"""

from utilities import load_tsv_data, ensure_temp_dir, TEMP_DIR
import logging
import os
import time
from typing import List, Dict, Set


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


if __name__ == "__main__":
    logging.basicConfig(format="%(asctime)s - %(levelname)s - %(message)s", level=logging.INFO)
    start_time = time.time()

    ensure_temp_dir()

    try:
        # Load TSV data. Inputs and outputs all live under TEMP_DIR to keep the helper_scripts root clean.
        # ------------------------------------------------------------------
        mod_data, _, _ = load_tsv_data(f"{TEMP_DIR}/glf.tsv")
        game_data, game_headers, game_version = load_tsv_data(f"{TEMP_DIR}/data__.tsv")

        # Process data merge.
        # ------------------------------------------------------------------
        mod_keys = {row["key"] for row in mod_data}
        joined_data = perform_inner_join(game_data, mod_keys)
        updated_data = update_combat_attributes(joined_data, mod_data)

        # Write merged output.
        # ------------------------------------------------------------------
        output_path = f"{TEMP_DIR}/new_glf.tsv"
        os.makedirs(os.path.dirname(output_path), exist_ok=True)

        with open(output_path, "w", encoding="utf-8") as f:
            f.write("\t".join(game_headers) + "\n")
            f.write(game_version + "\n")

            for row in updated_data:
                ordered_values = [row[header] for header in game_headers]
                f.write("\t".join(ordered_values) + "\n")

        logging.info(f"Successfully created {output_path} with merged data.")

    except FileNotFoundError as e:
        logging.error(f"Missing required file: {e.filename}")
    except ValueError as e:
        logging.error(f"Data validation error: {str(e)}")
    except Exception as e:
        logging.exception(e)

    end_time = round(time.time() - start_time, 2)
    logging.info(f"Total time for inner join: {end_time} seconds or {round(end_time / 60, 2)} minutes.")
