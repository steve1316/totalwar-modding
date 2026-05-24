"""Script to validate and correct quotation mark usage in Total War: Warhammer 3 localization files.

Processes modded TSV files to:
1. Remove redundant quotation mark nesting
2. Ensure proper Western quote usage for Chinese source text
3. Maintain original file structure and version information
"""

from utilities import load_tsv_data, log_elapsed_time, setup_script_logging
import logging
import time
import os
from typing import List, Dict


def correct_quotation_marks(mod_data: List[Dict[str, str]], game_data: List[Dict[str, str]]):
    """Normalize quotation marks in localization text entries.

    Args:
        mod_data (List[Dict[str, str]]): Modded localization entries to correct.
        game_data (List[Dict[str, str]]): Original game localization entries for reference.

    Returns:
        List of corrected mod entries.
    """
    # Processing rules:
    # 1. Remove redundant double quotes wrapping single quotes.
    # 2. Convert Chinese quotation marks (『』) to Western quotes ("") when present in original.
    # 3. Remove unnecessary Western quotes when not present in original Chinese text.
    corrected_data = []

    for idx, mod_row in enumerate(mod_data):
        try:
            original_row = game_data[idx]
            original_text = original_row["text"]
            mod_text = mod_row["text"]

            # Remove redundant quote wrapping.
            if mod_text.startswith('"') and mod_text.endswith('"'):
                if mod_text[1] == "'" and mod_text[-2] == "'":
                    mod_text = mod_text[2:-2]

            # Chinese quote replacement logic.
            if original_text.startswith("『") and original_text.endswith("』"):
                if not (mod_text.startswith('"') and mod_text.endswith('"')):
                    # Strip existing single quotes if present.
                    if mod_text.startswith("'") and mod_text.endswith("'"):
                        mod_text = mod_text[1:-1]
                    mod_text = f'"{mod_text}"'
            elif mod_text.startswith('"') and mod_text.endswith('"'):
                # Remove quotes when not matching Chinese original.
                mod_text = mod_text[1:-1]

            corrected_row = mod_row.copy()
            corrected_row["text"] = mod_text
            corrected_data.append(corrected_row)

        except (IndexError, KeyError) as e:
            logging.warning(f"Skipping row {idx} due to error: {str(e)}")
            corrected_data.append(mod_row)

    return corrected_data


if __name__ == "__main__":
    setup_script_logging()
    start_time = time.time()

    try:
        # Load TSV data.
        # ------------------------------------------------------------------
        game_data, game_headers, game_version = load_tsv_data("original.tsv")
        mod_data, _, _ = load_tsv_data("modded.tsv")

        # Perform corrections.
        # ------------------------------------------------------------------
        corrected_data = correct_quotation_marks(mod_data, game_data)

        # Write output file.
        # ------------------------------------------------------------------
        os.makedirs(os.path.dirname("corrected.tsv"), exist_ok=True)

        with open("corrected.tsv", "w", encoding="utf-8") as f:
            f.write("\t".join(game_headers) + "\n")
            f.write(game_version + "\n")

            for row in corrected_data:
                ordered_values = [row[header] for header in game_headers]
                f.write("\t".join(ordered_values) + "\n")

        logging.info("Successfully created corrected.tsv")

    except FileNotFoundError as e:
        logging.error(f"Missing required file: {e.filename}")
    except Exception as e:
        logging.exception(e)

    log_elapsed_time("correcting quotation marks", start_time)
