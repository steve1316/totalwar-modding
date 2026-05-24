"""Script to automatically add missing effects from mod packfile to dynamic_rors_effects.py.

This script performs the following steps:
    1. Extracts effect bundles from the mod packfile.
    2. Loads and merges TSV files containing effect data.
    3. Filters for relevant effects and compares with existing effects.
    4. Categorizes missing effects based on naming patterns.
    5. Adds missing effects to dynamic_rors_effects.py in their appropriate categories.
    6. Recategorizes any effects in the misc category.
    7. Cleans up temporary files.
"""

import os
import re
import logging
import time
from typing import Dict, List, Tuple
from utilities import (
    extract_modded_tsv_data,
    load_multiple_tsv_data,
    cleanup_folders,
    ensure_temp_dir,
    STEAM_LIBRARY_DRIVE,
    TEMP_DIR,
)
from dynamic_rors_effects import SUPPORTED_EFFECTS

# Configure logging.
logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")

MOD_PACKFILE_PATH = f"{STEAM_LIBRARY_DRIVE}\\SteamLibrary\\steamapps\\workshop\\content\\1142710\\3278112051\\!!_nanu_dynamic_rors.pack"
TABLE_NAME = "unit_purchasable_effects_tables"
TEMP_EXTRACT_PATH = f"{TEMP_DIR}/temp_unit_purchasable_effects_tables"
DYNAMIC_RORS_EFFECTS_FILE = "dynamic_rors_effects.py"


# Pattern matching rules for categorization.
_PREFIX_PATTERNS: List[Tuple[str, str]] = [
    ("nanu_dynamic_ror_basic_artillery_", "artillery"),
    ("nanu_dynamic_ror_basic_cavalry_", "cavalry"),
    ("nanu_dynamic_ror_basic_melee_", "melee"),
    ("nanu_dynamic_ror_basic_monster_", "monster"),
    ("nanu_dynamic_ror_basic_ranged_", "ranged"),
    ("nanu_dynamic_ror_ability_melee_", "melee"),
    ("nanu_dynamic_ror_ability_powder_", "ranged"),
    ("nanu_dynamic_ror_ability_ranged_", "ranged"),
    ("nanu_dynamic_ror_attribute_melee_", "melee"),
    ("nanu_dynamic_ror_attribute_ranged_", "ranged"),
    ("nanu_dynamic_ror_contact_ranged_", "ranged"),
    ("nanu_dynamic_ror_ranged_ammo_type_", "ranged"),
    ("nanu_dynamic_ror_scripted_ammo_type_", "ranged"),
    ("nanu_dynamic_ror_basic_all_", "generic"),
    ("nanu_dynamic_ror_basic_elite_", "generic"),
    ("nanu_dynamic_ror_basic_single_entity_", "generic"),
    ("nanu_dynamic_ror_ability_all_", "generic"),
    ("nanu_dynamic_ror_ability_single_entity_", "generic"),
    ("nanu_dynamic_ror_attribute_all_", "generic"),
    ("nanu_dynamic_ror_contact_all_", "generic"),
    ("nanu_dynamic_ror_climate_", "generic"),
]

_CONTAINS_PATTERNS: List[Tuple[str, str]] = [
    ("special_forces_of_order_enemy_ability_all_", "anti_order_generic"),
    ("special_forces_of_order_enemy_contact_all_", "anti_order_generic"),
    ("special_forces_of_order_enemy_ability_melee_", "anti_order_melee"),
    ("special_forces_of_order_enemy_attribute_melee_", "anti_order_melee"),
    ("special_forces_of_order_enemy_ability_ranged_", "anti_order_ranged"),
    ("special_forces_of_destruction_enemy_ranged_ability_", "anti_destruction_ranged"),
    ("special_chaos_enemy_melee_", "anti_destruction_melee"),
    ("special_chaos_enemy_ranged_", "anti_destruction_ranged"),
    ("special_chaos_enemy_powder_", "anti_destruction_ranged"),
    ("special_cathay_ally_ability_melee_", "cathay_melee"),
    ("special_cathay_ally_ability_ranged_", "ranged"),
    ("special_cathay_enemy_ability_melee_", "melee"),
    ("special_cathay_enemy_contact_all_", "generic"),
    ("contact_bretonnia_", "bretonnia_artillery"),
    ("bretonnia_special_", "bretonnia_artillery"),
    ("death_explosion_all_", "generic"),
    ("special_nurgle_all_", "nurgle_generic"),
]

_REGEX_PATTERNS: List[Tuple[str, str]] = [
    (r"special_\w+_enemy_all_", "generic"),
    (r"special_\w+_enemy_melee_", "melee"),
    (r"special_\w+_enemy_ranged_", "ranged"),
    (r"special_\w+_enemy_powder_", "ranged"),
    (r"special_\w+_ally_all_", "generic"),
    (r"special_\w+_ally_melee_", "melee"),
    (r"special_\w+_ally_ranged_", "ranged"),
    (r"special_\w+_ally_powder_", "ranged"),
    (r"special_\w+_ally_cavalry_", "cavalry"),
]

_FACTION_RULES: Dict[str, List[Tuple[str, str]]] = {
    "nanu_dynamic_ror_cathay_": [
        ("_ability_melee_", "cathay_melee"),
        ("_ability_all_", "cathay_generic"),
        ("_attribute_all_", "cathay_generic"),
    ],
    "nanu_dynamic_ror_chaos_": [
        ("_ability_melee_", "chaos_melee"),
        ("_daemon_ability_", "chaos_generic"),
        ("_contact_", "generic"),
    ],
    "nanu_dynamic_ror_chorf_": [
        ("_ability_melee_", "melee"),
        ("_ability_all_", "generic"),
    ],
    "nanu_dynamic_ror_dwarf_": [
        ("_ability_melee_", "dwarfs_melee"),
        ("_ability_powder_", "dwarfs_ranged"),
        ("_ability_ranged_", "dwarfs_ranged"),
        ("_ability_all_", "dwarfs_generic"),
    ],
    "nanu_dynamic_ror_dwarfs_": [
        ("_ability_melee_", "dwarfs_melee"),
        ("_ability_powder_", "dwarfs_ranged"),
        ("_ability_ranged_", "dwarfs_ranged"),
        ("_ability_all_", "dwarfs_generic"),
    ],
    "nanu_dynamic_ror_empire_": [
        ("_ability_melee_", "empire_melee"),
        ("_special_melee_", "empire_melee"),
        ("_ability_swordsmen_", "empire_melee"),
        ("_basic_knight_", "empire_cavalry"),
        ("_attribute_all_", "empire_generic"),
        ("_attribute_ranged_", "empire_generic"),
        ("_ability_all_", "empire_generic"),
        ("_special_", "empire_generic"),
        ("_basic_archer_", "generic"),
    ],
    "nanu_dynamic_ror_greenskin_": [
        ("_ability_melee_", "greenskins_melee"),
        ("_ability_all_", "greenskins_generic"),
    ],
    "nanu_dynamic_ror_high_elf_": [
        ("_ability_ranged_", "ranged"),
    ],
    "nanu_dynamic_ror_khorne_": [
        ("_ability_melee_", "khorne_melee"),
        ("_attribute_melee_", "khorne_melee"),
        ("_ability_monster_", "khorne_monster"),
        ("_ability_bloodthirster_", "khorne_monster"),
        ("_ability_all_", "khorne_generic"),
    ],
    "nanu_dynamic_ror_kislev_": [
        ("_ability_melee_", "kislev_melee"),
        ("_ability_ranged_", "kislev_ranged"),
    ],
    "nanu_dynamic_ror_nurgle_": [
        ("_ability_melee_", "nurgle_melee"),
        ("_ability_monster_", "nurgle_monster"),
        ("_ability_single_entity_", "nurgle_generic"),
        ("_ability_all_", "nurgle_generic"),
        ("_special_death_explosion_", "nurgle_generic"),
        ("_basic_", "nurgle_generic"),
    ],
    "nanu_dynamic_ror_ogre_": [
        ("_ability_melee_", "ogre_melee"),
    ],
    "nanu_dynamic_ror_skaven_": [
        ("_ability_melee_", "skaven_melee"),
        ("_ability_all_", "skaven_generic"),
        ("_contact_all_", "skaven_generic"),
        ("_death_explosion_", "skaven_generic"),
    ],
    "nanu_dynamic_ror_slaanesh_": [
        ("_ability_melee_", "slaanesh_melee"),
        ("_basic_", "generic"),
    ],
    "nanu_dynamic_ror_tzeentch_": [
        ("_ability_melee_", "tzeentch_melee"),
        ("_ability_all_", "tzeentch_generic"),
        ("_attribute_all_", "tzeentch_generic"),
        ("_ability_lord_of_change_", "tzeentch_generic"),
    ],
}

_LEGACY_FACTION_RULES: Dict[str, List[Tuple[str, str]]] = {
    "ability_cathay_": [("_melee_", "cathay_melee"), ("", "cathay_generic")],
    "ability_dwarf_": [("_melee_", "dwarfs_melee"), ("_ranged_", "dwarfs_ranged"), ("powder_", "dwarfs_ranged"), ("", "dwarfs_generic")],
    "ability_empire_": [("_melee_", "empire_melee"), ("_cavalry_", "empire_cavalry"), ("", "empire_generic")],
    "ability_greenskin_": [("_melee_", "greenskins_melee"), ("", "greenskins_generic")],
    "ability_khorne_": [("_melee_", "khorne_melee"), ("_monster_", "khorne_monster"), ("", "khorne_generic")],
    "ability_kislev_": [("_melee_", "kislev_melee"), ("_ranged_", "kislev_ranged")],
    "ability_nurgle_": [("_melee_", "nurgle_melee"), ("_monster_", "nurgle_monster"), ("", "nurgle_generic")],
    "ability_ogre_": [("_melee_", "ogre_melee")],
    "ability_skaven_": [("_melee_", "skaven_melee"), ("", "skaven_generic")],
    "ability_slaanesh_": [("_melee_", "slaanesh_melee")],
    "ability_tzeentch_": [("_melee_", "tzeentch_melee"), ("", "tzeentch_generic")],
}


def categorize_effect(effect_key: str) -> str:
    """Categorize an effect key based on naming patterns.

    Args:
        effect_key: The effect key to categorize.

    Returns:
        The category name, or "misc" if no pattern matches.
    """
    # Check against patterns.
    for prefix, category in _PREFIX_PATTERNS:
        if effect_key.startswith(prefix):
            return category

    for pattern, category in _CONTAINS_PATTERNS:
        if pattern in effect_key:
            return category

    for pattern, category in _REGEX_PATTERNS:
        if re.search(pattern, effect_key):
            return category

    # Check faction-specific rules.
    for prefix, rules in _FACTION_RULES.items():
        if effect_key.startswith(prefix):
            for pattern, category in rules:
                if pattern in effect_key:
                    # Special handling for nurgle monster vs generic.
                    if prefix == "nanu_dynamic_ror_nurgle_" and category == "nurgle_generic" and "_monster_" in effect_key:
                        return "nurgle_monster"
                    return category

    # Check legacy faction patterns.
    for pattern, rules in _LEGACY_FACTION_RULES.items():
        if pattern in effect_key:
            for subpattern, category in rules:
                if subpattern == "" or subpattern in effect_key:
                    return category

    # Check specifically for Lizardmen patterns.
    if any(x in effect_key for x in ["lizard_ability_", "lizard_contact_", "lizard_attribute_"]):
        return "lizardmen_melee" if "_melee_" in effect_key else "lizardmen_generic"

    return "misc"


def read_dynamic_rors_effects_file() -> str:
    """Read the dynamic_rors_effects.py file as text.

    Returns:
        The complete file content as a string.
    """
    with open(DYNAMIC_RORS_EFFECTS_FILE, "r", encoding="utf-8") as f:
        return f.read()


def write_dynamic_rors_effects_file(content: str):
    """Write the updated content to dynamic_rors_effects.py.

    Args:
        content: The file content to write.
    """
    with open(DYNAMIC_RORS_EFFECTS_FILE, "w", encoding="utf-8") as f:
        f.write(content)


def insert_effects_into_category(file_content: str, category: str, effects: List[str]) -> str:
    """Insert multiple effects into a category in alphabetical order.

    Args:
        file_content: The file content as a string.
        category: The category name.
        effects: List of effect keys to insert.

    Returns:
        Updated file content.
    """
    if not effects:
        return file_content

    category_pattern = rf'    "{re.escape(category)}": \['
    match = re.search(category_pattern, file_content)

    if not match:
        # Add new category.
        last_bracket = file_content.rfind("    ],")
        insert_pos = file_content.find("\n", last_bracket) + 1 if last_bracket != -1 else file_content.rfind("}")
        indented = [f'        "{e}",' for e in sorted(effects)]
        new_category = f'    "{category}": [\n' + "\n".join(indented) + "\n    ],\n"
        return file_content[:insert_pos] + new_category + file_content[insert_pos:]

    # Find the matching closing bracket for the category's list.
    # Uses bracket counting to handle nested brackets correctly.
    list_start = match.end()
    bracket_count = 1
    pos = list_start
    list_end = -1
    while pos < len(file_content) and bracket_count > 0:
        if file_content[pos] == "[":
            bracket_count += 1
        elif file_content[pos] == "]":
            bracket_count -= 1
            if bracket_count == 0:
                list_end = pos
                break
        pos += 1

    if list_end == -1:
        logging.warning(f"Could not find end of category {category}, skipping insertion.")
        return file_content

    # Extract existing effects and add new ones, then sort and return the updated content.
    existing = re.findall(r'"([^"]+)"', file_content[list_start:list_end])
    all_effects = sorted(set(existing) | set(effects))
    indented = [f'        "{e}",' for e in all_effects]

    return file_content[:list_start] + "\n" + "\n".join(indented) + "\n" + file_content[list_end:]


def _recategorize_misc_effects(file_content: str) -> str:
    """Re-run categorization on effects in the misc bucket and move any that now match a real category.

    Args:
        file_content: The file content as a string.

    Returns:
        Updated file content with misc effects recategorized where possible.
    """
    misc_pattern = r'    "misc": \[(.*?)(?=\n    "[^"]+": \[|\n\})'
    misc_match = re.search(misc_pattern, file_content, re.DOTALL)

    if not misc_match:
        return file_content

    misc_effects = re.findall(r'"([^"]+)"', misc_match.group(1))
    if not misc_effects:
        return re.sub(r'    "misc": \[.*?\],\n', "", file_content, flags=re.DOTALL)

    recategorized: Dict[str, List[str]] = {}
    still_misc: List[str] = []

    for effect in misc_effects:
        category = categorize_effect(effect)
        if category == "misc":
            still_misc.append(effect)
        else:
            recategorized.setdefault(category, []).append(effect)

    if not recategorized:
        return file_content

    # Update or remove misc category.
    if still_misc:
        indented = [f'        "{e}",' for e in sorted(still_misc)]
        new_misc = "\n" + "\n".join(indented) + "\n"
        file_content = file_content[: misc_match.start(1)] + new_misc + file_content[misc_match.end(1) :]
    else:
        file_content = re.sub(r'    "misc": \[.*?\],\n', "", file_content, flags=re.DOTALL)

    # Add recategorized effects.
    for category, effects in recategorized.items():
        file_content = insert_effects_into_category(file_content, category, effects)
        logging.info(f"  Recategorized {len(effects)} effects from misc to {category}.")

    return file_content


if __name__ == "__main__":
    logging.info("Starting missing effects detection and addition process.")
    start_time = time.time()

    ensure_temp_dir()

    extract_modded_tsv_data(TABLE_NAME, MOD_PACKFILE_PATH, TEMP_EXTRACT_PATH)
    tsv_folder_path = os.path.join(TEMP_EXTRACT_PATH, f"db/{TABLE_NAME}")

    if not os.path.exists(tsv_folder_path):
        logging.error(f"Extracted folder not found: {tsv_folder_path}.")
        cleanup_folders([TEMP_EXTRACT_PATH])
        exit()

    merged_data, headers, _ = load_multiple_tsv_data(tsv_folder_path)
    key_column = next((h for h in headers if h.lower() == "key"), None)

    if not key_column:
        logging.error(f"Could not find 'Key' column. Available columns: {headers}.")
        cleanup_folders([TEMP_EXTRACT_PATH])
        exit()

    mod_effects = {row.get(key_column, "") for row in merged_data if row.get(key_column, "").startswith("nanu_dynamic_ror_")}
    missing_effects = mod_effects - {effect for effects in SUPPORTED_EFFECTS.values() for effect in effects}

    logging.info(f"Found {len(mod_effects)} total nanu_dynamic_ror_* effects in mod.")
    logging.info(f"Found {len(missing_effects)} missing effects to add.")

    if not missing_effects:
        logging.info("No missing effects found. Nothing to add.")
        cleanup_folders([TEMP_EXTRACT_PATH])
        exit()

    # Categorize and add missing effects.
    categorized: Dict[str, List[str]] = {}
    for effect in missing_effects:
        categorized.setdefault(categorize_effect(effect), []).append(effect)

    for category, effects in sorted(categorized.items()):
        logging.info(f"  {category}: {len(effects)} effects")

    file_content = read_dynamic_rors_effects_file()
    for category, effects in categorized.items():
        file_content = insert_effects_into_category(file_content, category, effects)
        logging.info(f"  Added {len(effects)} effects to {category}.")

    write_dynamic_rors_effects_file(file_content)
    logging.info("Successfully updated dynamic_rors_effects.py.")

    # Recategorize misc effects.
    logging.info("Recategorizing misc effects...")
    file_content = _recategorize_misc_effects(read_dynamic_rors_effects_file())
    write_dynamic_rors_effects_file(file_content)
    logging.info("Successfully recategorized misc effects.")

    cleanup_folders([TEMP_EXTRACT_PATH])

    end_time = round(time.time() - start_time, 2)
    logging.info(f"Total time for updating dynamic_rors_effects.py: {end_time} seconds or {round(end_time / 60, 2)} minutes.")
