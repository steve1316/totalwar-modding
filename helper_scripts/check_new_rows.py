"""Script to check for new rows in a TSV file for Total War: Warhammer 3 modding.

Compares two TSV files and identifies rows that exist in the original file but not in the modded file.
"""

from utilities import load_tsv_data, log_elapsed_time, setup_script_logging
import time
import logging
from typing import List, Dict


def find_missing_keys(original_data: List[Dict], modded_data: List[Dict], key_field: str = "key"):
    """Identify keys present in original data but missing in modded data.

    Args:
        original_data (List[Dict]): Data from original TSV.
        modded_data (List[Dict]): Data from modded TSV.
        key_field (str): Field name to use for comparison.

    Returns:
        Missing keys not found in modded data.
    """
    original_keys = {row[key_field] for row in original_data}
    modded_keys = {row[key_field] for row in modded_data}
    return list(original_keys - modded_keys)


if __name__ == "__main__":
    setup_script_logging(log_format="%(levelname)s: %(message)s")
    start_time = time.time()

    try:
        # Load TSV data.
        # ------------------------------------------------------------------
        original_data, _, _ = load_tsv_data("original.tsv")
        modded_data, _, _ = load_tsv_data("modded.tsv")

        # Perform key comparison.
        # ------------------------------------------------------------------
        missing_keys = find_missing_keys(original_data, modded_data)

        if missing_keys:
            logging.info(f"Found {len(missing_keys)} missing keys in modded data:")
            for key in missing_keys:
                logging.info(f" - {key}")
        else:
            logging.info("No missing keys found - modded data contains all original entries")

    except FileNotFoundError as e:
        logging.error(f"File not found: {e.filename}")
    except Exception as e:
        logging.exception(e)

    log_elapsed_time("checking new rows", start_time)
