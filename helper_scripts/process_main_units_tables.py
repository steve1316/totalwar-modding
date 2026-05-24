"""Processes Total War: Warhammer 3 unit data from TSV files into faction-specific JSON/Lua outputs.

Key functionalities:
1. Extracts and transforms unit data from game files.
2. Handles vanilla and modded content through configurable patterns.
3. Generates both JSON and Lua representations of faction data.
"""

import argparse
import subprocess
import os
import pandas as pd
import json
import logging
import gc
import shutil
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from utilities import extract_tsv_data, read_and_clean_tsv, ensure_temp_dir, STEAM_LIBRARY_DRIVE, TEMP_DIR
from supported_mods import SUPPORTED_MODS
from typing import List, Dict, Optional, Tuple


FAILED_MODS = []
MISSING_MODS = []


# Pack-relative folders that every non-vanilla mod gets extracted for. Pre-computed once so workers do not rebuild it.
MOD_FOLDERS_TO_EXTRACT = [
    "db/main_units_tables",
    "db/faction_agent_permitted_subtypes_tables",
    "db/character_skill_node_set_items_tables",
    "db/character_skill_node_sets_tables",
    "db/character_skill_nodes_tables",
]


def extract_mod_dataframes(mod: Dict) -> Optional[Dict[str, pd.DataFrame]]:
    """Extract a non-vanilla mod's required tables to a per-mod scratch dir and load each one into a DataFrame.

    Workers may run this in parallel - each writes only under its own `temp/<folder_name>/` scratch dir, so there is no contention on the previously-shared `./db/` extraction target. The per-mod scratch is deleted before the function returns.

    Args:
        mod (Dict): Entry from `SUPPORTED_MODS`. Must have `path` and `package_name`.

    Returns:
        Mapping of table-name (without the `db/` prefix) to its loaded DataFrame, ready to feed `tsv_to_faction_data`. Returns None if the mod path does not exist on disk.
    """
    if mod["path"] and not os.path.exists(mod["path"]):
        return None

    folder_name = mod["package_name"].replace(".pack", "").replace(" ", "_")
    if folder_name and folder_name[-1].isdigit():
        folder_name = folder_name[:-1]
    scratch_root = f"{TEMP_DIR}/{folder_name}"
    os.makedirs(scratch_root, exist_ok=True)

    logging.info(f"Extracting mod data from {mod['package_name']}...")
    for folder in MOD_FOLDERS_TO_EXTRACT:
        subprocess.run(
            [
                "./rpfm_cli.exe",
                "--game",
                "warhammer_3",
                "pack",
                "extract",
                "--pack-path",
                mod["path"],
                "--tables-as-tsv",
                "./schemas/schema_wh3.ron",
                "--folder-path",
                f"{folder};{scratch_root}/",
            ]
        )

    dfs = {
        "main_units_tables": process_tsv_files(f"{scratch_root}/db/main_units_tables/", "main_units_tables"),
        "faction_agent_permitted_subtypes_tables": process_tsv_files(
            f"{scratch_root}/db/faction_agent_permitted_subtypes_tables/", "faction_agent_permitted_subtypes"
        ),
        "character_skill_node_set_items_tables": process_tsv_files(
            f"{scratch_root}/db/character_skill_node_set_items_tables/",
            "character_skill_node_set_items_tables",
            allowed_patterns=allowed_character_skill_key_patterns,
        ),
        "character_skill_node_sets_tables": process_tsv_files(
            f"{scratch_root}/db/character_skill_node_sets_tables/", "character_skill_node_sets_tables"
        ),
        "character_skill_nodes_tables": process_tsv_files(
            f"{scratch_root}/db/character_skill_nodes_tables/", "character_skill_nodes_tables", allowed_patterns=allowed_character_skill_key_patterns
        ),
    }

    shutil.rmtree(scratch_root, ignore_errors=True)
    return dfs


# If "./schemas" does not exist, download the schemas.
if not os.path.exists("./schemas"):
    logging.info("Downloading schemas...")
    subprocess.run(["./rpfm_cli.exe", "--game", "warhammer_3", "schemas", "update", "--schema-path", "./schemas"])

    # Now convert them to JSON.
    subprocess.run(["./rpfm_cli.exe", "--game", "warhammer_3", "schemas", "to-json", "--schemas-path", "./schemas"])

# =====================================================================================
# Configuration Constants
# =====================================================================================

# These are the faction keys acquired from "db/cultures_subcultures_tables".
faction_keys = [
    # {"neu": "neu"},
    {"tmb": "tmb"},
    {"cst": "cst"},
    {"def": "def"},
    {"hef": "hef"},
    {"lzd": "lzd"},
    {"skv": "skv"},
    {"chd": "chd"},
    {"kho": "kho"},
    {"ksl": "ksl"},
    {"tze": "tze"},
    {"cth": "cth"},
    # {"dae": "dae"},
    {"nur": "nur"},
    {"ogr": "ogr"},
    {"sla": "sla"},
    {"bst": "bst"},
    {"wef": "wef"},
    {"nor": "nor"},
    {"brt": "brt"},
    {"chs": "chs"},
    {"dwf": "dwf"},
    {"emp": "emp"},
    {"grn": "grn"},
    {"vmp": "vmp"},
]

allowed_character_skill_key_patterns = [
    "_army_",
    "_generic_",
    "_magic_",
    "_unique_",
    "_self_",
    "_personal_",
    "_ability_",
    "_misc_",
    "_battle_",
    "_ranged_",
    "_combat_",
]

# =====================================================================================
# Core Data Processing Functions
# =====================================================================================


def dict_to_lua_table(data_dict: Dict, indent: int = 0):
    """Convert Python dictionary to Warhammer modding-friendly Lua table format.

    Args:
        data_dict (Dict): Nested dictionary of faction data.
        indent (int, optional): Current indentation level for pretty-printing. Defaults to 0.

    Returns:
        Lua table string ready for file output.
    """
    # Check if the dictionary is empty.
    if not data_dict:
        return "{}"

    lua_str = "{\n"
    for key, value in data_dict.items():
        lua_str += " " * (indent + 4)
        if isinstance(key, str):
            lua_str += f'["{key}"] = '
        else:
            lua_str += f"[{key}] = "

        if isinstance(value, dict):
            lua_str += dict_to_lua_table(value, indent + 4)
        elif isinstance(value, list):
            # Check if the list is empty.
            if not value:
                lua_str += "{}"
            else:
                # Check if the list contains only strings.
                if all(isinstance(item, str) for item in value):
                    lua_str += "{ " + ", ".join(f'"{item}"' for item in value) + " }"
                else:
                    lua_str += "{\n"
                    for item in value:
                        lua_str += " " * (indent + 8) + "{"
                        if isinstance(item, dict):
                            # Handle allowed_lords and character_skill_overrides.
                            if "land_unit" in item:
                                lua_str += f'land_unit="{item["land_unit"]}"'
                                if "agent_subtype" in item:
                                    lua_str += f', agent_subtype="{item["agent_subtype"]}"'
                                if "agent_type" in item:
                                    lua_str += f', agent_type="{item["agent_type"]}"'
                                if "origin" in item:
                                    lua_str += f', origin="{item["origin"]}"'
                                if "recruitment_cost" in item:
                                    lua_str += f', recruitment_cost={item["recruitment_cost"]}'
                                if "multiplayer_cost" in item:
                                    lua_str += f', multiplayer_cost={item["multiplayer_cost"]}'
                                if "skill_overrides" in item:
                                    lua_str += ", skill_overrides={ " + ", ".join(f'"{skill}"' for skill in item["skill_overrides"]) + " }"
                            else:
                                lua_str += ", ".join(f'{k}="{v}"' for k, v in item.items())
                        else:
                            lua_str += f'"{item}"'
                        lua_str += "},\n"
                    lua_str += " " * (indent + 4) + "}"
        else:
            lua_str += f'"{value}"'
        lua_str += ",\n"
    lua_str += " " * indent + "}"
    return lua_str


def process_tsv_files(directory: str, table_type: str, allowed_patterns: List[str] = None):
    """Process TSV files in a directory, read, clean, and merge them into a single DataFrame.

    Args:
        directory (str): Directory containing TSV files.
        table_type (str): Type of the table to determine cleaning rules.
        allowed_patterns (List[str], optional): Patterns to allow in specific columns.

    Returns:
        Merged and cleaned DataFrame.
    """
    merged_df = pd.DataFrame()
    if os.path.exists(directory):
        for file_path in os.listdir(directory):
            temp_df = read_and_clean_tsv(os.path.join(directory, file_path), table_type, allowed_patterns)
            merged_df = pd.concat([merged_df, temp_df])
        merged_df = merged_df.drop_duplicates()
    return merged_df


def tsv_to_faction_data(
    mod: Dict,
    factions_data: Dict,
    faction_keys: List[str],
    df_main_units_tables: pd.DataFrame,
    df_faction_agent_permitted_subtypes: pd.DataFrame,
    df_character_skill_node_set_items: pd.DataFrame,
    df_character_skill_node_sets: pd.DataFrame,
    df_character_skill_nodes: pd.DataFrame,
    default_faction: str = None,
    do_not_use_underscore_pattern: bool = False,
):
    """Transform TSV data into structured faction data dictionary.

    The caller is responsible for passing the correct dataframes: vanilla dfs for the `vanilla` mod, per-mod-extracted dfs for everything else. Loading is no longer done inline here so the caller can parallelize extraction.

    Args:
        mod (Dict): Mod data.
        factions_data (Dict): Existing data to augment.
        faction_keys (List[str]): Faction detection patterns.
        df_main_units_tables (pd.DataFrame): Processed units data (already loaded; vanilla or per-mod).
        df_faction_agent_permitted_subtypes (pd.DataFrame): Allowed agent subtypes.
        df_character_skill_node_set_items (pd.DataFrame): Skill node items data.
        df_character_skill_node_sets (pd.DataFrame): Skill node sets data.
        df_character_skill_nodes (pd.DataFrame): Skill nodes data.
        default_faction (str): Fallback faction if none detected. Can be comma-delimited list.
        do_not_use_underscore_pattern (bool): Disable underscore pattern matching.

    Returns:
        Updated factions data with new units and skills.
    """
    try:
        # Iterate over each unit row in the DataFrame
        for _, row in df_main_units_tables.iterrows():
            if default_faction:
                # Handle comma-delimited faction list
                if "," in default_faction:
                    faction_values = [faction.strip() for faction in default_faction.split(",")]
                else:
                    faction_values = [default_faction]
            elif do_not_use_underscore_pattern:
                faction_key, faction_value = next(
                    ((key, faction[key]) for faction in faction_keys for key in faction if f"{key}" in row["land_unit"]), (None, None)
                )
                faction_values = [faction_value] if faction_value else []
            else:
                faction_key, faction_value = next(
                    ((key, faction[key]) for faction in faction_keys for key in faction if f"_{key}_" in row["land_unit"]),
                    (None, None),
                )
                faction_values = [faction_value] if faction_value else []

            if not faction_values or all(faction_value is None for faction_value in faction_values):
                logging.warning(f"No valid faction key found for land unit '{row['land_unit']}'")
                continue

            # Process the unit for each faction
            for faction_value in faction_values:
                if faction_value is None:
                    continue

                # Check if the extracted faction key is in any of the dictionaries in faction_keys
                if not any(faction_value in faction_dict for faction_dict in faction_keys):
                    logging.warning(f"Faction key '{faction_value}' not recognized for land unit '{row['land_unit']}'")
                    continue

                logging.info(f"Processing {row['land_unit']} for faction {faction_value}...")

                # Initialize the faction and tier if they don't exist.
                if faction_value not in factions_data:
                    factions_data[faction_value] = {"units": {"tier_0": {}, "tier_1": {}, "tier_2": {}, "tier_3": {}, "tier_4": {}, "tier_5": {}}}
                    # Initialize categories within each tier
                    for tier in factions_data[faction_value]["units"]:
                        factions_data[faction_value]["units"][tier] = {
                            "melee_infantry": [],
                            "missile_infantry": [],
                            "melee_cavalry": [],
                            "missile_cavalry": [],
                            "monstrous_infantry": [],
                            "monstrous_cavalry": [],
                            "chariot": [],
                            "warmachine": [],
                            "war_beast": [],
                            "monster": [],
                            "generic": [],
                            "lord": [],
                            "hero": [],
                        }

                # Save the unit data.
                tier = f"tier_{int(row['tier'])}"
                caste_category = row["caste"]
                if caste_category in factions_data[faction_value]["units"][tier]:
                    # Save lords and heroes into their own lists.
                    if caste_category != "lord" and caste_category != "hero":
                        factions_data[faction_value]["units"][tier][caste_category].append(
                            {
                                "land_unit": row["land_unit"],
                                "recruitment_cost": int(row["recruitment_cost"]),
                                "multiplayer_cost": int(row["multiplayer_cost"]),
                                "origin": mod["package_name"].replace(".pack", ""),
                            }
                        )

                    # Check if the unit key is in the allowed_lords field.
                    if "character_overrides" in mod and faction_value in mod["character_overrides"]:
                        for key_substring in ["lords", "heroes"]:
                            if f"allowed_{key_substring}" not in factions_data[faction_value]:
                                factions_data[faction_value][f"allowed_{key_substring}"] = []

                            if f"allowed_{key_substring}" in mod["character_overrides"][faction_value]:
                                for allowed_object in mod["character_overrides"][faction_value][f"allowed_{key_substring}"]:
                                    if row["land_unit"] == allowed_object["land_unit"]:
                                        logging.info(f"Adding {row['land_unit']} to allowed_{key_substring} for faction {faction_value}.")
                                        new_allowed_object = {
                                            "land_unit": allowed_object["land_unit"],
                                            "agent_subtype": allowed_object["agent_subtype"],
                                            "origin": mod["package_name"].replace(".pack", ""),
                                            "skill_overrides": [],
                                        }

                                        # Use the character_skill_node_sets_tables to grab key by referencing its agent_subtype_key with the agent_subtype from the allowed_object.
                                        agent_subtype = allowed_object["agent_subtype"]
                                        df_character_skill_node_sets_key = df_character_skill_node_sets.loc[
                                            df_character_skill_node_sets["agent_subtype_key"] == agent_subtype, "key"
                                        ].values[0]

                                        # Inside character_skill_node_set_items_tables, all skill rows for a character belong to a set which is the key from the previous step.
                                        df_character_skill_node_set_items_skills = df_character_skill_node_set_items.loc[
                                            df_character_skill_node_set_items["set"] == df_character_skill_node_sets_key, "item"
                                        ].values

                                        # Now from each skill row, grab all the skill keys from character_skill_nodes_tables by referencing the key column and then grabbing the value from the character_skill_key column.
                                        skills = []
                                        try:
                                            for skill_node in df_character_skill_node_set_items_skills:
                                                skill_node_skill_key = df_character_skill_nodes.loc[
                                                    df_character_skill_nodes["key"] == skill_node, "character_skill_key"
                                                ].values[0]
                                                skills.append(skill_node_skill_key)
                                        except:
                                            pass

                                        # Save the skills.
                                        new_allowed_object["skill_overrides"] = skills

                                        # Check if the agent_subtype for heroes is in the df_agent_permitted_subtypes DataFrame.
                                        if new_allowed_object["agent_subtype"] in df_faction_agent_permitted_subtypes["subtype"].values:
                                            # Retrieve the corresponding agent value.
                                            agent_value = df_faction_agent_permitted_subtypes.loc[
                                                df_faction_agent_permitted_subtypes["subtype"] == new_allowed_object["agent_subtype"], "agent"
                                            ].values[0]
                                            new_allowed_object["agent_type"] = agent_value

                                        factions_data[faction_value][f"allowed_{key_substring}"].append(new_allowed_object)
    except Exception as e:
        FAILED_MODS.append(mod["package_name"])
        logging.exception(e)

    return factions_data


# =====================================================================================
# Main Execution Flow
# =====================================================================================

if __name__ == "__main__":
    logging.basicConfig(format="%(asctime)s - %(levelname)s - %(message)s", level=logging.INFO)
    start_time = time.time()

    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--workers",
        type=int,
        default=min(8, (os.cpu_count() or 4)),
        help="Number of worker threads for parallel mod extraction. Use 1 to force sequential (e.g. for debugging or output-equivalence diffs). Does not affect the serial dedup/write pass.",
    )
    args = parser.parse_args()

    ensure_temp_dir()

    # If the required vanilla data files are not present, extract them from the game.
    for table_name in [
        "main_units_tables",
        "faction_agent_permitted_subtypes_tables",
        "character_skill_node_set_items_tables",
        "character_skill_node_sets_tables",
        "character_skill_nodes_tables",
    ]:
        if not os.path.exists(f"{TEMP_DIR}/vanilla_{table_name}.tsv"):
            extract_tsv_data(table_name)
            # Now move the data__.tsv file to the root and rename it.
            shutil.move(f"{TEMP_DIR}/vanilla_{table_name}/db/{table_name}/data__.tsv", f"{TEMP_DIR}/vanilla_{table_name}.tsv")
            shutil.rmtree(f"{TEMP_DIR}/vanilla_{table_name}")
    try:
        factions_data = {}

        # Load vanilla data foundations.
        # ------------------------------------------------------------------
        df_main_units_tables_vanilla = read_and_clean_tsv(f"{TEMP_DIR}/vanilla_main_units_tables.tsv", "main_units_tables")
        df_faction_agent_permitted_subtypes_vanilla = read_and_clean_tsv(
            f"{TEMP_DIR}/vanilla_faction_agent_permitted_subtypes_tables.tsv", "faction_agent_permitted_subtypes"
        )
        df_character_skill_node_set_items_vanilla = read_and_clean_tsv(
            f"{TEMP_DIR}/vanilla_character_skill_node_set_items_tables.tsv", "character_skill_node_set_items_tables"
        )
        df_character_skill_node_sets_vanilla = read_and_clean_tsv(
            f"{TEMP_DIR}/vanilla_character_skill_node_sets_tables.tsv", "character_skill_node_sets_tables"
        )
        df_character_skill_nodes_vanilla = read_and_clean_tsv(f"{TEMP_DIR}/vanilla_character_skill_nodes_tables.tsv", "character_skill_nodes_tables")

        # Convert the schemas from Ron to JSON.
        subprocess.run(["./rpfm_cli.exe", "--game", "warhammer_3", "schemas", "to-json", "--schemas-path", "./schemas"])

        # Load the schema.
        with open("schemas/schema_wh3.json", "r", encoding="utf-8") as schema_file:
            schema = json.load(schema_file)

        # Process supported mods.
        # ------------------------------------------------------------------
        # Pre-filter (single pass, sequential): drop ignore_generation mods, collect supported names, flag missing mods, decide which mods need a parallel extraction. Order is preserved by carrying the original SUPPORTED_MODS index.
        list_of_supported_package_names: List[str] = []
        mods_to_extract: List[Tuple[int, Dict]] = []
        process_order: List[Tuple[int, Dict]] = []
        for idx, mod in enumerate(SUPPORTED_MODS):
            if "ignore_generation" in mod and mod["ignore_generation"]:
                logging.info(f"Skipping {mod['package_name']} because it is marked to be ignored.")
                continue
            list_of_supported_package_names.append(mod["package_name"].replace(".pack", ""))
            if mod["path"] and not os.path.exists(mod["path"]):
                MISSING_MODS.append(mod["package_name"])
                continue
            process_order.append((idx, mod))
            if mod["package_name"] != "vanilla":
                mods_to_extract.append((idx, mod))

        # Parallel extraction: each worker writes only to its own `temp/<folder_name>/` scratch and returns loaded dataframes. The vanilla mod is not extracted; the serial pass uses the pre-loaded vanilla dataframes.
        logging.info(f"Extracting {len(mods_to_extract)} mods with {args.workers} worker thread(s).")
        per_mod_dfs: Dict[int, Dict[str, pd.DataFrame]] = {}
        if args.workers <= 1:
            for idx, mod in mods_to_extract:
                dfs = extract_mod_dataframes(mod)
                if dfs is not None:
                    per_mod_dfs[idx] = dfs
        else:
            with ThreadPoolExecutor(max_workers=args.workers) as executor:
                futures = {executor.submit(extract_mod_dataframes, mod): (idx, mod) for idx, mod in mods_to_extract}
                for future in as_completed(futures):
                    idx, mod = futures[future]
                    try:
                        dfs = future.result()
                    except Exception:
                        logging.exception(f"Extraction worker failed for mod {mod.get('package_name', '<unknown>')}.")
                        raise
                    if dfs is not None:
                        per_mod_dfs[idx] = dfs

        # Serial merge pass in original SUPPORTED_MODS order so `factions_data`, `faction_keys`, and the in-tier list ordering stay deterministic (the lists in `factions_data[faction]["units"][tier][category]` are append-only and order-sensitive).
        for idx, mod in process_order:
            if mod["package_name"] == "vanilla":
                logging.info(f"Processing vanilla units...")
                factions_data = tsv_to_faction_data(
                    mod,
                    factions_data,
                    faction_keys,
                    df_main_units_tables_vanilla,
                    df_faction_agent_permitted_subtypes_vanilla,
                    df_character_skill_node_set_items_vanilla,
                    df_character_skill_node_sets_vanilla,
                    df_character_skill_nodes_vanilla,
                )
                continue

            dfs = per_mod_dfs.get(idx)
            if dfs is None:
                # Worker skipped (missing path was caught earlier, so this branch only fires if `extract_mod_dataframes` returned None for a mod whose path went missing between pre-filter and extraction).
                continue

            logging.info(f"Now processing {mod['package_name']}...")

            default_faction = None
            do_not_use_underscore_pattern = False
            pattern_overrides = mod["pattern_overrides"]
            if "*" in pattern_overrides:
                default_faction = pattern_overrides["*"]
                logging.info(f"Pattern is the wildcard itself so we will use '{default_faction}' for all units in this mod.")
            elif any("*" in key for key in pattern_overrides):
                logging.info(f"Pattern is a wildcard pattern, so we will not use the underscore pattern.")
                do_not_use_underscore_pattern = True

            # If the mod has a factions_override field, add the contents to faction_keys. Mutation of the shared `faction_keys` list persists across mods, matching the pre-parallel behavior.
            if "faction_overrides" in mod:
                for new_faction_key in mod["faction_overrides"]:
                    faction_keys.append({new_faction_key: new_faction_key})
            temp_faction_keys = faction_keys.copy()

            if pattern_overrides and "*" not in pattern_overrides:
                for temp_faction_key, temp_faction_value in pattern_overrides.items():
                    temp_faction_keys.append({temp_faction_key.replace("*", ""): temp_faction_value})
                    if "_" in temp_faction_key:
                        do_not_use_underscore_pattern = True

            factions_data = tsv_to_faction_data(
                mod,
                factions_data,
                temp_faction_keys,
                dfs["main_units_tables"],
                dfs["faction_agent_permitted_subtypes_tables"],
                dfs["character_skill_node_set_items_tables"],
                dfs["character_skill_node_sets_tables"],
                dfs["character_skill_nodes_tables"],
                default_faction=default_faction,
                do_not_use_underscore_pattern=do_not_use_underscore_pattern,
            )

            # Release this mod's dataframes now that they've been merged so the merge pass keeps a flat memory footprint.
            del per_mod_dfs[idx]
            gc.collect()

        # Write output files.
        # ------------------------------------------------------------------
        with open("factions_data.json", "w", encoding="utf-8") as json_file:
            json.dump(factions_data, json_file, indent=4)

        # Convert the factions_data to Lua table format.
        lua_data = "return " + dict_to_lua_table(factions_data)

        # Save the Lua table to a file.
        with open("factions_data.lua", "w", encoding="utf-8") as lua_file:
            lua_file.write(lua_data)
    except Exception as e:
        logging.exception(e)

    # After processing all mods, move the final factions_data.lua to the destination folder.
    if os.path.exists("factions_data.lua"):
        destination_filepath = "../warhammer3_mods/land_encounters_and_points_of_interest_with_mct/script/land_encounters/constants/battles/factions_data.lua"
        if os.path.exists(destination_filepath):
            os.remove(destination_filepath)
        shutil.move("factions_data.lua", destination_filepath)
        os.remove("factions_data.json")

    # Use the RPFM CLI to delete the existing factions_data.lua file from the mod.
    subprocess.run(
        [
            "./rpfm_cli.exe",
            "--game",
            "warhammer_3",
            "pack",
            "delete",
            "--pack-path",
            f"{STEAM_LIBRARY_DRIVE}\\SteamLibrary\\steamapps\\workshop\\content\\1142710\\3397481450\\land_encounters_and_points_of_interest_6_0.pack",
            "--file-path",
            "script/land_encounters/constants/battles/factions_data.lua",
        ],
        capture_output=True,
    )

    # Now use the RPFM CLI to add the new factions_data.lua file into the packfile.
    subprocess.run(
        [
            "./rpfm_cli.exe",
            "--game",
            "warhammer_3",
            "pack",
            "add",
            "--pack-path",
            f"{STEAM_LIBRARY_DRIVE}\\SteamLibrary\\steamapps\\workshop\\content\\1142710\\3397481450\\land_encounters_and_points_of_interest_6_0.pack",
            "--tsv-to-binary",
            "./schemas/schema_wh3.ron",
            "--file-path",
            f"../warhammer3_mods/land_encounters_and_points_of_interest_with_mct/script/land_encounters/constants/battles/factions_data.lua;script/land_encounters/constants/battles/factions_data.lua",
        ],
        capture_output=True,
    )

    # Perform final cleanup.
    for cleanup_file in [
        f"{TEMP_DIR}/vanilla_main_units_tables.tsv",
        f"{TEMP_DIR}/vanilla_faction_agent_permitted_subtypes_tables.tsv",
        f"{TEMP_DIR}/vanilla_character_skill_node_set_items_tables.tsv",
        f"{TEMP_DIR}/vanilla_character_skill_node_sets_tables.tsv",
        f"{TEMP_DIR}/vanilla_character_skill_nodes_tables.tsv",
    ]:
        if os.path.exists(cleanup_file):
            os.remove(cleanup_file)

    if MISSING_MODS:
        logging.info(f"Missing mods: {MISSING_MODS}")
    if FAILED_MODS:
        logging.info(f"Failed mods: {FAILED_MODS}")

    # Output the list of supported mod package names to be updated in mct_settings.lua.
    print(f'\t"!cr_immortal_empires_expanded", -- Immortal Empires Expanded')
    for package_name in list_of_supported_package_names:
        print(f'\t"{package_name}",')

    end_time = round(time.time() - start_time, 2)
    logging.info(f"Total time for processing all main_units_tables .tsv files: {end_time} seconds or {round(end_time / 60, 2)} minutes.")
