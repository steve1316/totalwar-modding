"""Script to check for missing or placeholder text in translation files for Total War: Warhammer 3 modding.

Validates text files from original and translated mods, comparing key counts and content.
"""

import os
import pandas as pd
import logging
import gc
import shutil
import time
from typing import List, Set
from utilities import run_rpfm_cli, STEAM_LIBRARY_DRIVE


mod_paths_to_be_translated = [
    {
        "mod_path": f"{STEAM_LIBRARY_DRIVE}\\SteamLibrary\\steamapps\\workshop\\content\\1142710\\3297754796\\@whc_cth_unit_wuh_7.pack",
        "translation_path": f"{STEAM_LIBRARY_DRIVE}\\SteamLibrary\\steamapps\\workshop\\content\\1142710\\3392058226\\zzz_@whc_cth_unit_wuh_Alternative_English_Translation.pack",
    },
    {
        "mod_path": f"{STEAM_LIBRARY_DRIVE}\\SteamLibrary\\steamapps\\workshop\\content\\1142710\\2901237965\\Zerooz_All_Units.pack",
        "translation_path": f"{STEAM_LIBRARY_DRIVE}\\SteamLibrary\\steamapps\\workshop\\content\\1142710\\3315737452\\Zerooz_English_Translation_corrections.pack",
    },
    {
        "mod_path": f"{STEAM_LIBRARY_DRIVE}\\SteamLibrary\\steamapps\\workshop\\content\\1142710\\3316985957\\archer_fuyuanshan_faction.pack",
        "translation_path": f"{STEAM_LIBRARY_DRIVE}\\SteamLibrary\\steamapps\\workshop\\content\\1142710\\3317696617\\zzz_cth_fuyuanshan_faction_Alternative_English_Translation.pack",
    },
    {
        "mod_path": f"{STEAM_LIBRARY_DRIVE}\\SteamLibrary\\steamapps\\workshop\\content\\1142710\\3442971928\\ghs_great_harmony.pack",
        "translation_path": f"{STEAM_LIBRARY_DRIVE}\\SteamLibrary\\steamapps\\workshop\\content\\1142710\\3393724734\\zzz_Great_Harmony_Sentinel_Alternative_English_Translation.pack",
    },
    {
        "mod_path": f"{STEAM_LIBRARY_DRIVE}\\SteamLibrary\\steamapps\\workshop\\content\\1142710\\3061752415\\!!YL_binzhong.pack",
        "translation_path": f"{STEAM_LIBRARY_DRIVE}\\SteamLibrary\\steamapps\\workshop\\content\\1142710\\3318753302\\zzz_YL_binzhong_Alternative_English_Translation.pack",
    },
    {
        "mod_path": f"{STEAM_LIBRARY_DRIVE}\\SteamLibrary\\steamapps\\workshop\\content\\1142710\\2872222879\\@Deer24batuoniya.pack",
        "translation_path": f"{STEAM_LIBRARY_DRIVE}\\SteamLibrary\\steamapps\\workshop\\content\\1142710\\3393724674\\zzz_DEER24_Alternative_English_Translation.pack",
    },
    {
        "mod_path": f"{STEAM_LIBRARY_DRIVE}\\SteamLibrary\\steamapps\\workshop\\content\\1142710\\2859396310\\@Deer24diguochuanqi.pack",
        "translation_path": f"{STEAM_LIBRARY_DRIVE}\\SteamLibrary\\steamapps\\workshop\\content\\1142710\\3393724674\\zzz_DEER24_Alternative_English_Translation.pack",
    },
    {
        "mod_path": f"{STEAM_LIBRARY_DRIVE}\\SteamLibrary\\steamapps\\workshop\\content\\1142710\\2908711955\\@Deer24HEF.pack",
        "translation_path": f"{STEAM_LIBRARY_DRIVE}\\SteamLibrary\\steamapps\\workshop\\content\\1142710\\3393724674\\zzz_DEER24_Alternative_English_Translation.pack",
    },
    {
        "mod_path": f"{STEAM_LIBRARY_DRIVE}\\SteamLibrary\\steamapps\\workshop\\content\\1142710\\2804084630\\@DEERKSL.pack",
        "translation_path": f"{STEAM_LIBRARY_DRIVE}\\SteamLibrary\\steamapps\\workshop\\content\\1142710\\3393724674\\zzz_DEER24_Alternative_English_Translation.pack",
    },
    {
        "mod_path": f"{STEAM_LIBRARY_DRIVE}\\SteamLibrary\\steamapps\\workshop\\content\\1142710\\2789903784\\DEER24Cathay.pack",
        "translation_path": f"{STEAM_LIBRARY_DRIVE}\\SteamLibrary\\steamapps\\workshop\\content\\1142710\\3393724674\\zzz_DEER24_Alternative_English_Translation.pack",
    },
    {
        "mod_path": f"{STEAM_LIBRARY_DRIVE}\\SteamLibrary\\steamapps\\workshop\\content\\1142710\\2901237965\\Zerooz_All_Units.pack",
        "translation_path": f"{STEAM_LIBRARY_DRIVE}\\SteamLibrary\\steamapps\\workshop\\content\\1142710\\3315737452\\Zerooz_English_Translation_corrections.pack",
    },
]

if os.path.exists("./text_original"):
    for file_path in os.listdir(f"./text_original/"):
        shutil.rmtree(f"./text_original/{file_path}")
if os.path.exists("./text_translation"):
    for file_path in os.listdir(f"./text_translation/"):
        shutil.rmtree(f"./text_translation/{file_path}")

# If "./schemas" does not exist, download the schemas.
if not os.path.exists("./schemas"):
    logging.info("Downloading schemas...")
    run_rpfm_cli(["schemas", "update", "--schema-path", "./schemas"])

    # Now convert them to JSON.
    run_rpfm_cli(["schemas", "to-json", "--schemas-path", "./schemas"])


def read_text_tsv_with_schema(tsv_file_path: str):
    """Read a TSV file containing text entries, skipping the schema header row.

    Args:
        tsv_file_path (str): Path to the TSV file to read

    Returns:
        DataFrame containing the text entries
    """
    df = pd.read_csv(tsv_file_path, sep="\t")
    # Skip the schema header row.
    df = df.iloc[1:]
    return df


def compare_translation_entries(table_name: str, df_original: pd.DataFrame, df_translation: pd.DataFrame, mod_name: str):
    """Compare translation entries between original and translated text data.

    Performs three key checks:
    1. Identifies keys missing in translation when original has more entries.
    2. Identifies extra keys in translation when it has more entries.
    3. Checks for placeholder text in translations where original has valid text.

    Args:
        table_name (str): Name of the table being checked.
        df_original (pd.DataFrame): DataFrame containing original text entries.
        df_translation (pd.DataFrame): DataFrame containing translated text entries.
        mod_name (str): Name of the mod being checked (for error reporting).

    Returns:
        Tuple of (messages, collected_keys, discarded_keys) where messages is the updated list of validation messages,
        collected_keys is a set of keys that had issues, and discarded_keys is a set of keys that were discarded.
    """
    messages = []
    collected_keys = set()
    discarded_keys = set()

    # Use sets for fast comparison of keys between original and translation.
    original_keys = set(df_original["key"])
    translation_keys = set(df_translation["key"])

    # Always check for missing keys in translation (original has more entries).
    missing_in_translation = original_keys - translation_keys
    if missing_in_translation:
        # Filter out keys where the original text is empty/placeholder.
        missing_with_valid_text = set()
        for key in missing_in_translation:
            try:
                original_text = str(df_original[df_original["key"] == key]["text"].iloc[0]).strip().lower()
                # Only include keys where original text is valid (non-empty and non-placeholder).
                if original_text not in ["", "placeholder", "nan"]:
                    missing_with_valid_text.add(key)
            except (IndexError, KeyError):
                # If we can't find the text, skip this key.
                continue

        if missing_with_valid_text:
            explanation = f"The number of strings is higher than the translation."
            messages, keys = process_key_differences(
                missing_with_valid_text, mod_name, table_name, messages, explanation, is_missing_in_translation=True
            )
            collected_keys.update(keys)

    # Always check for discarded keys in translation (translation has more entries).
    discarded_in_translation = translation_keys - original_keys
    if discarded_in_translation:
        explanation = f"The number of strings is lower than the translation."
        messages, keys = process_key_differences(
            discarded_in_translation, mod_name, table_name, messages, explanation, is_missing_in_translation=False
        )
        discarded_keys.update(keys)

    # Check for placeholder texts regardless of key count match.
    messages, placeholder_keys = check_placeholder_translations(df_original, df_translation, mod_name, messages)
    collected_keys.update(placeholder_keys)

    return messages, collected_keys, discarded_keys


def process_key_differences(
    diff_keys: Set[str], mod_name: str, table_name: str, messages: List[str], explanation: str, is_missing_in_translation: bool
):
    """Process key differences between original and translation data.

    Handles two types of discrepancies:
    - Keys present in original but missing in translation.
    - Extra keys present in translation but missing in original.

    Args:
        diff_keys (Set[str]): Set of keys that differ between versions.
        mod_name (str): Name of the mod being checked (for error reporting).
        table_name (str): Name of the table being checked.
        messages (List[str]): List to accumulate validation messages.
        explanation (str): Context message about the key difference origin.
        is_missing_in_translation (bool): Flag indicating direction of mismatch (True = missing in translation).

    Returns:
        Tuple of (updated_messages, collected_keys) where updated_messages is the updated list of messages
        and collected_keys is a set of keys that had issues.
    """
    collected_keys = set()
    for key in diff_keys:
        # Skip automatic update keys by mod authors that don't require translation.
        if key.lower() in ["update", "land_units_onscreen_name_update"]:
            continue
        elif "steamapps/workshop/" in key:
            continue
        elif "----" in key:
            continue

        collected_keys.add(key)

        # Ensure mod name and explanation are only added once per discrepancy group.
        if f"Mod name: {mod_name}" not in messages:
            messages.append("//////////////////////////////////////////////////")
            messages.append(f"Mod name: {mod_name}")
            messages.append(f"Table name: {table_name}")
        if explanation not in messages:
            messages.append(explanation)

        # Create appropriate message based on discrepancy direction.
        if is_missing_in_translation:
            message = f'"{key}" is in the original but not in the translation.'
        else:
            message = f'"{key}" is in the translation but not in the original.'

        messages.append(message)
    return messages, collected_keys


def check_placeholder_translations(df_original: pd.DataFrame, df_translation: pd.DataFrame, mod_name: str, messages: List[str]):
    """Check for placeholder text in translations where original has valid text.

    Args:
        df_original (pd.DataFrame): DataFrame containing original text entries.
        df_translation (pd.DataFrame): DataFrame containing translated text entries.
        mod_name (str): Name of the mod being checked (for error reporting).
        messages (List[str]): List to accumulate validation messages.

    Returns:
        Tuple of (updated_messages, collected_keys) where updated_messages is the updated list of messages
        and collected_keys is a set of keys that had placeholder issues.
    """
    collected_keys = set()
    for _, row in df_translation.iterrows():
        # Normalize translated text for consistent comparison
        translated_text = str(row["text"]).strip().lower()
        if translated_text in ["", "placeholder", "nan"]:
            try:
                # Get corresponding original text using the same key.
                original_text = str(df_original[df_original["key"] == row["key"]]["text"].iloc[0]).strip().lower()

                # Only flag if original text is valid (non-placeholder and non-empty)
                if original_text not in ["", "placeholder", "nan"]:
                    collected_keys.add(row["key"])
                    # Add mod name header if not already present.
                    if mod_name not in messages:
                        messages.append(mod_name)
                    messages.append(f"\"{row['key']}\" is placeholder/empty in the translation but not in the original.")
            except IndexError:
                collected_keys.add(row["key"])
                messages.append(f"Key {row['key']} not found in the original.")
    return messages, collected_keys


def check_missing_files(messages: List[str], mod_name: str, is_collection: bool = False, subfolder_name: str = ""):
    """List .loc files present in the original mod but absent from the translation mod, appending warnings to `messages`.

    Args:
        messages (List[str]): List to accumulate validation messages.
        mod_name (str): Name of the mod being checked.
        is_collection (bool): Flag indicating if this is a mod collection with subfolders.
        subfolder_name (str): Subdirectory path for translation files (collection mods only).

    Returns:
        Updated list of messages with missing file warnings.
    """
    # Get all files from original directory
    original_files = set()
    for root, _, files in os.walk("./text_original/text/"):
        for file_path in files:
            if file_path.endswith(".loc"):
                # Get relative path from text_original/text/
                rel_path = os.path.relpath(os.path.join(root, file_path), "./text_original/text/")
                original_files.add(rel_path)

    # Get all files from translation directory
    translation_files = set()
    translation_base_path = "./text_translation/text/"

    # Handle collection mods with different subfolder structures
    if is_collection:
        for prepend in ["", "@", "@@", "@@@"]:
            potential_path = f"{translation_base_path}{prepend}{subfolder_name}/"
            if os.path.exists(potential_path):
                translation_base_path = potential_path
                break

    if os.path.exists(translation_base_path):
        for root, _, files in os.walk(translation_base_path):
            for file_path in files:
                if file_path.endswith(".loc"):
                    # Get relative path from translation_base_path
                    rel_path = os.path.relpath(os.path.join(root, file_path), translation_base_path)
                    translation_files.add(rel_path)

    # Find missing files
    missing_files = original_files - translation_files

    if missing_files:
        # Add header if not already present
        if f"Mod name: {mod_name}" not in messages:
            messages.append("//////////////////////////////////////////////////")
            messages.append(f"Mod name: {mod_name}")

        messages.append("MISSING FILES IN TRANSLATION:")
        messages.append("The following .loc files exist in the original mod but are missing from the translation mod:")

        for missing_file in sorted(missing_files):
            messages.append(f"  - {missing_file}")

        messages.append("=========================")

    return messages


def check_text_string_amount_diff(messages: List[str], mod_name: str, is_collection: bool = False, subfolder_name: str = ""):
    """Compare original vs translation .loc file counts and per-file content, plus warn on missing files. Prints results.

    Args:
        messages (List[str]): List to accumulate validation messages.
        mod_name (str): Name of the mod being checked.
        is_collection (bool): Flag indicating if this is a mod collection with subfolders.
        subfolder_name (str): Subdirectory path for translation files (collection mods only) without any @ and trailing slashes.
    """
    # Check for missing files first
    messages = check_missing_files(messages, mod_name, is_collection, subfolder_name)

    # Check file count discrepancies for collection mods.
    if is_collection:
        original_count = len(os.listdir("./text_original/text/"))
        translation_count = 0
        for prepend in ["", "@", "@@", "@@@"]:
            if os.path.exists(f"./text_translation/text/{prepend}{subfolder_name}/"):
                translation_count = len(os.listdir(f"./text_translation/text/{prepend}{subfolder_name}/"))
                subfolder_name = f"{prepend}{subfolder_name}/"
                break

        if translation_count == 0:
            logging.warning(f"No translation files found for {subfolder_name}.")
            return messages

        if original_count > translation_count:
            logging.warning("The number of text files from text_original is higher than text_translation.")
        elif original_count < translation_count:
            logging.warning("The number of text files from text_original is lower than text_translation.")

    # Validate content of each loc TSV file pair.
    for root, _, files in os.walk("./text_original/text/"):
        for file_path in files:
            # Handle different translation file naming conventions.
            possible_translation_path_prepends = [
                "",
                "@",
                "@@",
                "@@@",
                "!!!",
                "!!!!!",
                "!!!!!!",
                "db/",
                "db/@",
                "db/@@",
                "db/@@@",
                "db/!!!",
                "db/!!!!!",
                "db/!!!!!!",
                "!!!db/",
            ]
            df_original = read_text_tsv_with_schema(f"{root}/{file_path}")

            for prepend in possible_translation_path_prepends:
                try:
                    df_translation = read_text_tsv_with_schema(f"./text_translation/text/{subfolder_name}{prepend}{file_path}")
                    logging.info(f"Found the alternative translation file at ./text_translation/text/{subfolder_name}{prepend}{file_path}.")

                    # Compare entries between original and translation.
                    messages, collected_keys, discarded_keys = compare_translation_entries(
                        table_name=f"{prepend}{file_path}", df_original=df_original, df_translation=df_translation, mod_name=mod_name
                    )

                    # Report final results to a text file.
                    with open("translation_check_results.txt", "a", encoding="utf-8") as result_file:
                        if len(messages) > 0:
                            for message in messages:
                                result_file.write(f"{message}\n")

                    # Write the regex pattern for this specific file if there were issues
                    if collected_keys:
                        with open("translation_check_results.txt", "a", encoding="utf-8") as result_file:
                            result_file.write("//////////////////////////////////////////////////\n")
                            result_file.write(f"REGEX PATTERN FOR {mod_name} - {prepend}{file_path}:\n")
                            chunk_size = 200

                            collected_keys_list = list(collected_keys)
                            for i in range(0, len(collected_keys_list), chunk_size):
                                chunk = collected_keys_list[i : i + chunk_size]
                                regex_pattern = "|".join(f"\\b{key}\\b" for key in chunk)
                                result_file.write(f"{regex_pattern}\n\n")

                    # Write the regex pattern for discarded keys separately
                    if discarded_keys:
                        with open("translation_check_results.txt", "a", encoding="utf-8") as result_file:
                            result_file.write("//////////////////////////////////////////////////\n")
                            result_file.write(f"DISCARDED KEYS REGEX PATTERN FOR {mod_name} - {prepend}{file_path}:\n")
                            result_file.write("These keys exist in translation but were removed from the original:\n")
                            chunk_size = 200

                            discarded_keys_list = list(discarded_keys)
                            for i in range(0, len(discarded_keys_list), chunk_size):
                                chunk = discarded_keys_list[i : i + chunk_size]
                                regex_pattern = "|".join(f"\\b{key}\\b" for key in chunk)
                                result_file.write(f"{regex_pattern}\n\n")

                    del messages
                    gc.collect()
                except FileNotFoundError:
                    continue


if __name__ == "__main__":
    logging.basicConfig(format="%(asctime)s - %(levelname)s - %(message)s", level=logging.INFO)
    start_time = time.time()

    # If the translation_check_results.txt file exists, delete it.
    if os.path.exists("translation_check_results.txt"):
        os.remove("translation_check_results.txt")

    try:
        for mod in mod_paths_to_be_translated:
            # Check if the mod is installed.
            if not os.path.exists(mod["mod_path"]):
                logging.warning(f"Mod {mod['mod_path']} is not installed.")
                continue

            # Extract files from mod packages.
            # ------------------------------------------------------------------
            logging.info(f"Extracting text folder from {mod['mod_path']}...")
            run_rpfm_cli(["pack", "extract", "--pack-path", mod["mod_path"], "--tables-as-tsv", "./schemas/schema_wh3.ron", "--folder-path", "text;./text_original"])
            run_rpfm_cli(["pack", "extract", "--pack-path", mod["translation_path"], "--tables-as-tsv", "./schemas/schema_wh3.ron", "--folder-path", "text;./text_translation"])

            # Grab the mod name from the mod path without the .pack extension.
            mod_name = os.path.basename(mod["mod_path"]).replace(".pack", "")

            # Perform translation validation.
            # ------------------------------------------------------------------
            if "deer" in mod_name.lower():
                # Specially handle Deer24's mods.
                # Remove a @ if it exists at the beginning of the mod name.
                if mod_name.startswith("@"):
                    mod_name = mod_name[1:]

                check_text_string_amount_diff([], mod_name, is_collection=True, subfolder_name=mod_name)
            else:
                check_text_string_amount_diff([], mod_name)

            if os.path.exists("./text_original"):
                for file_path in os.listdir(f"./text_original/"):
                    shutil.rmtree(f"./text_original/{file_path}")
            if os.path.exists("./text_translation"):
                for file_path in os.listdir(f"./text_translation/"):
                    shutil.rmtree(f"./text_translation/{file_path}")
            gc.collect()
    except Exception as e:
        logging.exception(e)

    # Delete the db/, text_original/, and text_translation/ folders.
    if os.path.exists("./db/"):
        shutil.rmtree("./db/")
    if os.path.exists("./text_original/"):
        shutil.rmtree("./text_original/")
    if os.path.exists("./text_translation/"):
        shutil.rmtree("./text_translation/")

    end_time = round(time.time() - start_time, 2)
    logging.info(f"Total time for processing all text .tsv files: {end_time} seconds or {round(end_time / 60, 2)} minutes.")
