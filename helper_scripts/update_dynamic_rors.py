"""Script to update the dynamic RORs for Nanu from the Steam Workshop to account for latest changes to modded data tables."""

from utilities import (
    extract_tsv_data,
    read_and_clean_tsv,
    load_tsv_data,
    extract_modded_tsv_data,
    load_multiple_tsv_data,
    write_updated_tsv_file,
    sort_tsv_data,
    merge_move,
    cleanup_folders,
    extract_model_paths_from_variantmeshdefinition,
    STEAM_LIBRARY_DRIVE,
)
from supported_mods import SUPPORTED_MODS
from dynamic_rors_effects import SUPPORTED_EFFECTS
import time
import os
import subprocess
import logging
from typing import Dict, Any, List
import gc
import re
import shutil
import argparse


MISSING_MODS = []

# Faction keys are found in groupings_military_tables.

CHAOS_FACTIONS = [
    "wh_main_group_chaos",
    "wh3_main_dae",
    "wh3_main_group_belakor",
    "wh3_main_kho",
    "wh3_main_nur",
    "wh3_main_pro_kho",
    "wh3_main_pro_tze",
    "wh3_main_sla",
    "wh3_main_tze",
    "wh3_dlc20_group_chs_azazel",
    "wh3_dlc20_group_chs_festus",
    "wh3_dlc20_group_chs_valkia",
    "wh3_dlc20_group_chs_vilitch",
    "wh3_dlc25_nur_tamurkhan",
]

EMPIRE_SPECIFIC_FACTIONS = [
    "wh_main_group_empire",
    "wh_main_group_empire_golden_order",
    "wh_main_group_empire_reikland",
    "wh3_dlc25_group_elspeth",
]

HIGH_ELF_SPECIFIC_FACTIONS = [
    "wh2_main_hef",
    "wh2_main_hef_imrik",
]

KISLEV_SPECIFIC_FACTIONS = [
    "wh3_main_ksl",
    "wh3_main_pro_ksl",
]

GREENSKINS_SPECIFIC_FACTIONS = [
    "wh_main_group_greenskins",
    "wh_main_group_savage_orcs",
    "wh2_dlc12_grn_leaf_cutterz_tribe",
]

NORSCA_SPECIFIC_FACTIONS = [
    "wh_main_group_norsca",
    "wh_main_group_norsca_steppe",
]

DARK_ELF_SPECIFIC_FACTIONS = [
    "wh2_main_def",
    "wh3_main_def_morathi",
]

SKAVEN_SPECIFIC_FACTIONS = [
    "wh2_main_skv",
    "wh2_main_skv_ikit",
]

TOMB_KINGS_SPECIFIC_FACTIONS = [
    "wh2_dlc09_tomb_kings",
    "wh2_dlc09_tomb_kings_arkhan",
]

VAMPIRE_COAST_SPECIFIC_FACTIONS = [
    "wh2_dlc11_group_vampire_coast",
    "wh2_dlc11_group_vampire_coast_sartosa",
    "wh2_dlc11_cst_harpoon_the_sunken_land_corsairs",
    "wh2_dlc11_cst_shanty_dragon_spine_privateers",
    "wh2_dlc11_cst_shanty_middle_sea_brigands",
    "wh2_dlc11_cst_shanty_shark_straight_seadogs",
]

KHORNE_SPECIFIC_FACTIONS = [
    "wh3_main_kho",
    "wh3_main_pro_kho",
    "wh3_dlc20_group_chs_valkia",
]

NURGLE_SPECIFIC_FACTIONS = [
    "wh3_main_nur",
    "wh3_dlc20_group_chs_festus",
    "wh3_dlc25_nur_tamurkhan",
]

SLAANESH_SPECIFIC_FACTIONS = [
    "wh3_main_sla",
    "wh3_dlc20_group_chs_azazel",
]

TZEENTCH_SPECIFIC_FACTIONS = [
    "wh3_main_tze",
    "wh3_main_pro_tze",
    "wh3_dlc20_group_chs_vilitch",
]

ANTI_ORDER_FACTIONS = [
    "wh_main_group_chaos",
    "wh_main_group_greenskins",
    "wh_main_group_norsca",
    "wh_main_group_norsca_steppe",
    "wh_main_group_savage_orcs",
    "wh_main_group_vampire_counts",
    "wh_dlc03_group_beastmen",
    "wh2_main_def",
    "wh2_main_skv",
    "wh2_main_skv_ikit",
    "wh2_dlc09_tomb_kings",
    "wh2_dlc09_tomb_kings_arkhan",
    "wh2_dlc11_group_vampire_coast",
    "wh2_dlc11_group_vampire_coast_sartosa",
    "wh2_dlc11_cst_harpoon_the_sunken_land_corsairs",
    "wh2_dlc11_cst_shanty_dragon_spine_privateers",
    "wh2_dlc11_cst_shanty_middle_sea_brigands",
    "wh2_dlc11_cst_shanty_shark_straight_seadogs",
    "wh2_dlc12_grn_leaf_cutterz_tribe",
    "wh2_dlc16_group_drycha",
    "wh3_main_dae",
    "wh3_main_def_morathi",
    "wh3_main_group_belakor",
    "wh3_main_kho",
    "wh3_main_nur",
    "wh3_main_ogr",
    "wh3_main_pro_kho",
    "wh3_main_pro_tze",
    "wh3_main_sla",
    "wh3_main_tze",
    "wh3_dlc20_group_chs_azazel",
    "wh3_dlc20_group_chs_festus",
    "wh3_dlc20_group_chs_valkia",
    "wh3_dlc20_group_chs_vilitch",
    "wh3_dlc23_group_chaos_dwarfs",
    "wh3_dlc25_nur_tamurkhan",
]

ANTI_DESTRUCTION_FACTIONS = [
    "wh_main_group_bretonnia",
    "wh_main_group_dwarfs",
    "wh_main_group_empire",
    "wh_main_group_empire_golden_order",
    "wh_main_group_empire_reikland",
    "wh_main_group_kislev",
    "wh_main_group_teb",
    "wh_dlc05_group_wood_elves",
    "wh2_main_hef",
    "wh2_main_hef_imrik",
    "wh2_main_lzd",
    "wh3_main_cth",
    "wh3_main_ksl",
    "wh3_main_pro_ksl",
    "wh3_dlc25_group_elspeth",
]

FACTION_SHORTHAND_KEY_MAPPING = {
    "bst": "wh_dlc03_group_beastmen",
    "brt": "wh_main_group_bretonnia",
    "chd": "wh3_dlc23_group_chaos_dwarfs",
    "chs": "wh_main_group_chaos",
    "dae": "wh3_main_dae",
    "def": "wh2_main_def",
    "dwf": "wh_main_group_dwarfs",
    "emp": "wh_main_group_empire",
    "cth": "wh3_main_cth",
    "grn": "wh_main_group_greenskins",
    "hef": "wh2_main_hef",
    "kho": "wh3_main_kho",
    "ksl": "wh3_main_ksl",
    "lzd": "wh2_main_lzd",
    "nor": "wh_main_group_norsca",
    "nur": "wh3_main_nur",
    "ogr": "wh3_main_ogr",
    "skv": "wh2_main_skv",
    "sla": "wh3_main_sla",
    "tmb": "wh2_dlc09_tomb_kings",
    "tze": "wh3_main_tze",
    "cst": "wh2_dlc11_group_vampire_coast",
    "vmp": "wh_main_group_vampire_counts",
    "chs": "wh_main_group_chaos",
    "wef": "wh_dlc05_group_wood_elves",
}


def add_anti_order_generic_effects(faction: str):
    """Add anti-order generic effects based on faction.

    Args:
        faction (str): The faction of the unit.
    """
    unit_effects = []
    if faction in ANTI_ORDER_FACTIONS:
        unit_effects += SUPPORTED_EFFECTS["anti_order_generic"]

        if faction in GREENSKINS_SPECIFIC_FACTIONS:
            unit_effects += SUPPORTED_EFFECTS["greenskins_generic"]
        elif faction in SKAVEN_SPECIFIC_FACTIONS:
            unit_effects += SUPPORTED_EFFECTS["skaven_generic"]
        elif faction in CHAOS_FACTIONS:
            unit_effects += SUPPORTED_EFFECTS["chaos_generic"]
            if faction in KHORNE_SPECIFIC_FACTIONS:
                unit_effects += SUPPORTED_EFFECTS["khorne_generic"]
            elif faction in NURGLE_SPECIFIC_FACTIONS:
                unit_effects += SUPPORTED_EFFECTS["nurgle_generic"]
            elif faction in TZEENTCH_SPECIFIC_FACTIONS:
                unit_effects += SUPPORTED_EFFECTS["tzeentch_generic"]

    return unit_effects


def add_anti_destruction_generic_effects(faction: str):
    """Add anti-destruction generic effects based on faction.

    Args:
        faction (str): The faction of the unit.
    """
    unit_effects = []
    if faction in ANTI_DESTRUCTION_FACTIONS:
        if faction == "wh3_main_cth":
            unit_effects += SUPPORTED_EFFECTS["cathay_generic"]
        elif faction == "wh_main_group_dwarfs":
            unit_effects += SUPPORTED_EFFECTS["dwarfs_generic"]
        elif faction in EMPIRE_SPECIFIC_FACTIONS:
            unit_effects += SUPPORTED_EFFECTS["empire_generic"]
        elif faction == "wh2_main_lzd":
            unit_effects += SUPPORTED_EFFECTS["lizardmen_generic"]

    return unit_effects


def add_melee_effects(faction: str):
    """Add melee effects.

    Args:
        faction (str): The faction of the unit.
    """
    unit_effects = []
    unit_effects += SUPPORTED_EFFECTS["melee"]

    if faction in ANTI_ORDER_FACTIONS:
        unit_effects += SUPPORTED_EFFECTS["anti_order_melee"]

        if faction in CHAOS_FACTIONS:
            unit_effects += SUPPORTED_EFFECTS["chaos_melee"]

        if faction in GREENSKINS_SPECIFIC_FACTIONS:
            unit_effects += SUPPORTED_EFFECTS["greenskins_melee"]
        elif faction == "wh3_main_ogr":
            unit_effects += SUPPORTED_EFFECTS["ogre_melee"]
        elif faction in SKAVEN_SPECIFIC_FACTIONS:
            unit_effects += SUPPORTED_EFFECTS["skaven_melee"]
        elif faction in KHORNE_SPECIFIC_FACTIONS:
            unit_effects += SUPPORTED_EFFECTS["khorne_melee"]
        elif faction in NURGLE_SPECIFIC_FACTIONS:
            unit_effects += SUPPORTED_EFFECTS["nurgle_melee"]
        elif faction in SLAANESH_SPECIFIC_FACTIONS:
            unit_effects += SUPPORTED_EFFECTS["slaanesh_melee"]
        elif faction in TZEENTCH_SPECIFIC_FACTIONS:
            unit_effects += SUPPORTED_EFFECTS["tzeentch_melee"]
    elif faction in ANTI_DESTRUCTION_FACTIONS:
        unit_effects += SUPPORTED_EFFECTS["anti_destruction_melee"]

        if faction == "wh3_main_cth":
            unit_effects += SUPPORTED_EFFECTS["cathay_melee"]
        elif faction == "wh_main_group_dwarfs":
            unit_effects += SUPPORTED_EFFECTS["dwarfs_melee"]
        elif faction in EMPIRE_SPECIFIC_FACTIONS:
            unit_effects += SUPPORTED_EFFECTS["empire_melee"]
        elif faction in KISLEV_SPECIFIC_FACTIONS:
            unit_effects += SUPPORTED_EFFECTS["kislev_melee"]
        elif faction == "wh2_main_lzd":
            unit_effects += SUPPORTED_EFFECTS["lizardmen_melee"]

    return unit_effects


def add_ranged_effects(faction: str):
    """Add ranged effects.

    Args:
        faction (str): The faction of the unit.
    """
    unit_effects = []
    unit_effects += SUPPORTED_EFFECTS["ranged"]

    if faction in ANTI_ORDER_FACTIONS:
        unit_effects += SUPPORTED_EFFECTS["anti_order_ranged"]
    elif faction in ANTI_DESTRUCTION_FACTIONS:
        unit_effects += SUPPORTED_EFFECTS["anti_destruction_ranged"]

        if faction == "wh_main_group_dwarfs":
            unit_effects += SUPPORTED_EFFECTS["dwarfs_ranged"]
        elif faction in KISLEV_SPECIFIC_FACTIONS:
            unit_effects += SUPPORTED_EFFECTS["kislev_ranged"]

    return unit_effects


def add_artillery_effects(faction: str):
    """Add artillery effects.

    Args:
        faction (str): The faction of the unit.
    """
    unit_effects = []
    unit_effects += SUPPORTED_EFFECTS["artillery"]

    if faction == "wh_main_group_bretonnia":
        unit_effects += SUPPORTED_EFFECTS["bretonnia_artillery"]

    return unit_effects


def add_cavalry_effects(faction: str):
    """Add cavalry effects.

    Args:
        faction (str): The faction of the unit.
    """
    unit_effects = []
    unit_effects += SUPPORTED_EFFECTS["cavalry"]

    if faction in EMPIRE_SPECIFIC_FACTIONS:
        unit_effects += SUPPORTED_EFFECTS["empire_cavalry"]

    return unit_effects


def add_monster_effects(faction: str):
    """Add monster effects.

    Args:
        faction (str): The faction of the unit.
    """
    unit_effects = []
    unit_effects += SUPPORTED_EFFECTS["monster"]

    if faction in KHORNE_SPECIFIC_FACTIONS:
        unit_effects += SUPPORTED_EFFECTS["khorne_monster"]
    elif faction in NURGLE_SPECIFIC_FACTIONS:
        unit_effects += SUPPORTED_EFFECTS["nurgle_monster"]

    return unit_effects


def check_if_unit_is_ror(unit_data: Dict[str, Any], main_units_mapping: Dict[str, Any]):
    """Check if the unit is already a Regiment of Renown unit.

    Args:
        unit_data (Dict[str, Any]): The unit data.
        main_units_mapping (Dict[str, Any]): The mapping of unit keys to their main_units_tables data.

    Returns:
        True if the unit is a Regiment of Renown unit, False otherwise.
    """
    key = unit_data["key"]
    if main_units_mapping.get(key) and main_units_mapping[key].get("is_renown") == "true":
        return True
    for pattern in ["ror_", "_ror_", "_ror"]:
        if pattern in key:
            return True
    return False


def process_unit_by_category(unit_data: Dict[str, Any], main_units_mapping: Dict[str, Any], faction: str):
    """Process a unit based on its category and assign appropriate effects.

    Args:
        unit_data (Dict[str, Any]): The unit data.
        main_units_mapping (Dict[str, Any]): The mapping of unit keys to their main_units_tables data.
        faction (str): The faction of the unit.

    Returns:
        A list of strings representing the effects to add to the unit.
    """
    # Ignore Lords and Heroes.
    if unit_data["class"] == "com":
        logging.debug(f"Skipping the unit {unit_data['key']} because it is designated as a commander class.")
        return []
    # Also ignore if the unit is already a Regiment of Renown unit.
    if check_if_unit_is_ror(unit_data, main_units_mapping):
        logging.debug(f"Skipping the unit {unit_data['key']} because it is already a Regiment of Renown unit.")
        return []

    logging.debug(f"Processing unit {unit_data['key']} in category {unit_data['category']} for faction {faction}.")
    category = unit_data["category"]
    # This needs to be initialized to an empty list to avoid memory conflicts that causes Python to keep the old list in memory.
    unit_effects = []
    unit_effects += SUPPORTED_EFFECTS["generic"]
    unit_effects += add_anti_order_generic_effects(faction)
    unit_effects += add_anti_destruction_generic_effects(faction)

    if category == "artillery":
        unit_effects += add_ranged_effects(faction)
        unit_effects += add_artillery_effects(faction)
    elif category == "cavalry" and int(unit_data["primary_ammo"]) > 0:
        unit_effects += add_ranged_effects(faction)
        unit_effects += add_cavalry_effects(faction)
    elif category == "cavalry" or category == "war_beast":
        unit_effects += add_melee_effects(faction)
        unit_effects += add_cavalry_effects(faction)
    elif category == "war_machine" and int(unit_data["primary_ammo"]) > 0:
        unit_effects += add_ranged_effects(faction)
        unit_effects += add_artillery_effects(faction)
    elif category == "war_machine":
        unit_effects += add_melee_effects(faction)
    elif category == "inf_melee":
        unit_effects += add_melee_effects(faction)
    elif category == "inf_ranged":
        unit_effects += add_ranged_effects(faction)
    elif category == "monster":
        unit_effects += add_melee_effects(faction)
        unit_effects += add_monster_effects(faction)

    # # Remove all effects that have "_enemy_" in the name to try to keep the file size down.
    # unit_effects = [effect for effect in unit_effects if "_enemy_" not in effect]

    if unit_data["key"] in main_units_mapping and int(main_units_mapping[unit_data["key"]]["num_men"]) > 1:
        for single_entity_effect in [
            "nanu_dynamic_ror_basic_single_entity_1",
            "nanu_dynamic_ror_basic_single_entity_2",
            "nanu_dynamic_ror_basic_single_entity_3",
            "nanu_dynamic_ror_ability_single_entity_slime_trail",
            "nanu_dynamic_ror_nurgle_ability_single_entity_slime_trail",
            "nanu_dynamic_ror_nurgle_ability_single_entity_spurting_acid_blood",
            "nanu_dynamic_ror_nurgle_ability_single_entity_spurting_bile_blood",
        ]:
            try:
                unit_effects.remove(single_entity_effect)
            except ValueError:
                pass

    # Sort the effects by name ascending.
    unit_effects.sort()

    return unit_effects


def extract_and_load_table_data(mod_path: str, table_configs: List[Dict[str, Any]]):
    """Extract and load multiple tables for a mod based on the provided configs.

    The table configs are dictionaries with the following keys:
        table_name: Name of the table to extract.
        folder_name: Name of the folder to extract to.
        key_field: Field to use as dictionary key (default: "key").
        required: Whether the table is required (default: False).

    Args:
        mod_path (str): Path to the mod packfile.
        table_configs (List[Dict]): List of table configuration dictionaries.

    Returns:
        Dictionary containing mappings for each table with the table names as keys.
    """
    mappings = {}

    for config in table_configs:
        table_name = config["table_name"]
        folder_name = config["folder_name"]
        key_field = config.get("key_field", "key")
        required = config.get("required", False)

        # Extract the table data from the mod.
        extract_modded_tsv_data(table_name, mod_path, f"./modded_{folder_name}")
        new_mapping = {}

        if os.path.exists(f"./modded_{folder_name}"):
            merged_data, headers, version_info = load_multiple_tsv_data(f"./modded_{folder_name}/db/{table_name}", table_name)

            # Save each entry in the table to the new mapping. The column keys in RPFM are what is used as the keys in the new mapping.
            for data in merged_data:
                new_mapping[data[key_field]] = data

            # Store the table headers and version info.
            mappings[f"{table_name}_headers"] = headers
            mappings[f"{table_name}_version_info"] = version_info
        elif required:
            return None

        # Save the new mapping to the table name as a key in the mappings dictionary.
        mappings[table_name] = new_mapping

    return mappings


if __name__ == "__main__":
    logging.basicConfig(format="%(asctime)s - %(levelname)s - %(message)s", level=logging.INFO)
    start_time = time.time()

    # Get arguments from argparse.
    parser = argparse.ArgumentParser()
    parser.add_argument("--reset", action="store_true", help="Reset the script.")
    parser.add_argument("--vanilla", action="store_true", help="Process vanilla units only.")
    args = parser.parse_args()
    if args.reset:
        logging.info("Will reset folders in the packfile before writing.")
        for folder in ["db", "variantmeshes"]:
            try:
                shutil.rmtree(f"../mods/!!!!!!!_nanu_dynamic_rors_compat/{folder}")
            except FileNotFoundError:
                pass

    # Ensure all folders are cleaned up before the script starts if they exist.
    cleanup_folders(
        [
            "./vanilla_unit_purchasable_effect_sets_tables",
            "./vanilla_mounts_tables",
            "./!!!!!!!_nanu_dynamic_rors_leftover_vanilla" "./vanilla_main_units_tables",
            "./vanilla_land_units_tables",
            "./vanilla_units_to_groupings_military_permissions_tables",
            "./nanu_unit_purchasable_effect_sets_tables",
            "./modded_units_to_groupings_military_permissions_tables",
            "./modded_land_units_tables",
            "./modded_main_units_tables",
            "./modded_unit_description_historical_texts_tables",
            "./modded_battle_animations_table_tables",
            "./modded_battle_entities_tables",
            "./modded_mounts_tables",
            "./modded_melee_weapons_tables",
            "./modded_missile_weapons_tables",
            "./modded_unit_description_short_texts_tables",
            "./modded_unit_attributes_groups_tables",
            "./modded_battlefield_engines_tables",
            "./modded_projectiles_tables",
            "./modded_battle_vortexs_tables",
            "./modded_projectiles_scaling_damages_tables",
            "./modded_projectile_shot_type_displays_tables",
            "./modded_unit_spacings_tables",
            "./modded_first_person_engines_tables",
            "./modded_land_unit_articulated_vehicles_tables",
            "./modded_ui_unit_groupings_tables",
            "./modded_ui_unit_group_parents_tables",
            "./modded_variants_tables",
            "./modded_variantmeshes",
        ]
    )

    try:
        # Extract the vanilla unit_purchasable_effect_sets_tables and mounts_tables data.
        extract_tsv_data("unit_purchasable_effect_sets_tables")
        _, vanilla_unit_purchasable_effect_sets_tables_headers, vanilla_unit_purchasable_effect_sets_tables_version_info = load_tsv_data(
            "vanilla_unit_purchasable_effect_sets_tables/db/unit_purchasable_effect_sets_tables/data__.tsv"
        )
        extract_tsv_data("mounts_tables")
        vanilla_mounts_tables_dataframe = read_and_clean_tsv("vanilla_mounts_tables/db/mounts_tables/data__.tsv", "mounts_tables")

        # Secondary mode: Process vanilla units only.
        if args.vanilla:
            # Extract the vanilla main_units_tables, land_units_tables and units_to_groupings_military_permissions_tables data.
            extract_tsv_data("main_units_tables")
            vanilla_main_units_tables_dataframe = read_and_clean_tsv("vanilla_main_units_tables/db/main_units_tables/data__.tsv", "main_units_tables")
            extract_tsv_data("land_units_tables")
            vanilla_land_units_tables_dataframe = read_and_clean_tsv("vanilla_land_units_tables/db/land_units_tables/data__.tsv", "land_units_tables")
            extract_tsv_data("units_to_groupings_military_permissions_tables")
            vanilla_units_to_groupings_military_permissions_tables_dataframe = read_and_clean_tsv(
                "vanilla_units_to_groupings_military_permissions_tables/db/units_to_groupings_military_permissions_tables/data__.tsv",
                "units_to_groupings_military_permissions_tables",
            )

            # Extract Nanu's unit_purchasable_effect_sets_tables data.
            extract_modded_tsv_data(
                "unit_purchasable_effect_sets_tables",
                f"{STEAM_LIBRARY_DRIVE}\\SteamLibrary\\steamapps\\workshop\\content\\1142710\\3278112051\\!!_nanu_dynamic_rors.pack",
                "./nanu_unit_purchasable_effect_sets_tables",
            )

            processed_unit_keys = set()
            for faction in FACTION_SHORTHAND_KEY_MAPPING.keys():
                list_of_vanilla_data_to_add = []
                try:
                    nanu_faction_data, _, _ = load_tsv_data(
                        f"./nanu_unit_purchasable_effect_sets_tables/db/unit_purchasable_effect_sets_tables/nanu_dynamic_rors_{faction}.tsv"
                    )
                except FileNotFoundError:
                    nanu_faction_data = []
                nanu_main_unit_keys = set(data["unit"] for data in nanu_faction_data)
                units_not_supported_by_nanu = set()
                for vanilla_main_unit_key in vanilla_units_to_groupings_military_permissions_tables_dataframe["unit"].values:
                    # Get all military groups for this unit.
                    military_groups = vanilla_units_to_groupings_military_permissions_tables_dataframe.loc[
                        vanilla_units_to_groupings_military_permissions_tables_dataframe["unit"] == vanilla_main_unit_key, "military_group"
                    ].values

                    # Check if any of the military groups match the current faction.
                    if (
                        vanilla_main_unit_key not in nanu_main_unit_keys
                        and FACTION_SHORTHAND_KEY_MAPPING[faction] in military_groups
                        and vanilla_main_unit_key not in processed_unit_keys
                    ):
                        units_not_supported_by_nanu.add(vanilla_main_unit_key)
                        processed_unit_keys.add(vanilla_main_unit_key)

                logging.info(f"{faction} - {len(units_not_supported_by_nanu)} units not supported by Nanu's Dynamic Regiment of Renown units.")

                for vanilla_main_unit_key in units_not_supported_by_nanu:
                    try:
                        vanilla_main_unit = (
                            vanilla_main_units_tables_dataframe.loc[vanilla_main_units_tables_dataframe["unit"] == vanilla_main_unit_key]
                            .iloc[0]
                            .to_dict()
                        )
                        vanilla_land_unit = (
                            vanilla_land_units_tables_dataframe.loc[vanilla_land_units_tables_dataframe["key"] == vanilla_main_unit_key]
                            .iloc[0]
                            .to_dict()
                        )
                    except IndexError:
                        logging.info(f"Skipping {vanilla_main_unit_key} because it is not in the main_units_tables or land_units_tables.")
                        continue
                    for effect in process_unit_by_category(vanilla_land_unit, vanilla_main_unit, FACTION_SHORTHAND_KEY_MAPPING[faction]):
                        if effect:
                            list_of_vanilla_data_to_add.append(
                                {
                                    "unit": vanilla_land_unit["key"],
                                    "purchasable_effect": effect,
                                    "is_exclusive": "False",
                                }
                            )

                if len(list_of_vanilla_data_to_add) > 0:
                    logging.info(f"There are {len(list_of_vanilla_data_to_add)} effects to add for {faction}.")
                    unit_purchasable_effect_sets_tables_version_info = vanilla_unit_purchasable_effect_sets_tables_version_info.replace(
                        "data__", f"!!!nanu_dynamic_rors_{faction}"
                    )
                    write_updated_tsv_file(
                        list_of_vanilla_data_to_add,
                        vanilla_unit_purchasable_effect_sets_tables_headers,
                        unit_purchasable_effect_sets_tables_version_info,
                        "./!!!!!!!_nanu_dynamic_rors_leftover_vanilla/db/unit_purchasable_effect_sets_tables",
                        f"!!!nanu_dynamic_rors_{faction}",
                        allow_duplicates=True,
                    )
                    nanu_main_unit_keys.clear()
                    list_of_vanilla_data_to_add.clear()
                    units_not_supported_by_nanu.clear()
                    gc.collect()

                    sort_tsv_data(
                        "./!!!!!!!_nanu_dynamic_rors_leftover_vanilla/db/unit_purchasable_effect_sets_tables",
                        f"!!!nanu_dynamic_rors_{faction}",
                    )

            # After processing all mods, move the mod folder to the destination folder.
            if os.path.exists("./!!!!!!!_nanu_dynamic_rors_leftover_vanilla"):
                logging.info(f"Moving !!!!!!!_nanu_dynamic_rors_leftover_vanilla to ../mods/.")
                merge_move("./!!!!!!!_nanu_dynamic_rors_leftover_vanilla", "../mods/")

            if args.reset:
                # Use the RPFM CLI to delete all files from the required folders.
                subprocess.run(
                    [
                        "./rpfm_cli.exe",
                        "--game",
                        "warhammer_3",
                        "pack",
                        "delete",
                        "--pack-path",
                        f"{STEAM_LIBRARY_DRIVE}\\SteamLibrary\\steamapps\\workshop\\content\\1142710\\3532864014\\!!!!!!!_nanu_dynamic_rors_leftover_vanilla.pack",
                        "--folder-path",
                        "db",
                    ],
                    capture_output=True,
                )

            subprocess.run(
                [
                    "./rpfm_cli.exe",
                    "--game",
                    "warhammer_3",
                    "pack",
                    "add",
                    "--pack-path",
                    f"{STEAM_LIBRARY_DRIVE}\\SteamLibrary\\steamapps\\workshop\\content\\1142710\\3532864014\\!!!!!!!_nanu_dynamic_rors_leftover_vanilla.pack",
                    "--tsv-to-binary",
                    "./schemas/schema_wh3.ron",
                    "--folder-path",
                    f"../mods/!!!!!!!_nanu_dynamic_rors_leftover_vanilla/db/unit_purchasable_effect_sets_tables;db/unit_purchasable_effect_sets_tables",
                ],
                capture_output=True,
            )

            exit(0)

        # Primary mode: Process modded units.
        # Define table configurations for extraction.
        table_configs = [
            {
                "table_name": "units_to_groupings_military_permissions_tables",
                "folder_name": "units_to_groupings_military_permissions_tables",
                "key_field": "unit",
                "required": True,
            },
            {"table_name": "main_units_tables", "folder_name": "main_units_tables", "key_field": "unit", "required": True},
            {"table_name": "land_units_tables", "folder_name": "land_units_tables", "key_field": "key", "required": True},
            {"table_name": "unit_description_historical_texts_tables", "folder_name": "unit_description_historical_texts_tables", "key_field": "key"},
            {"table_name": "battle_animations_table_tables", "folder_name": "battle_animations_table_tables", "key_field": "key"},
            {"table_name": "battle_entities_tables", "folder_name": "battle_entities_tables", "key_field": "key"},
            {"table_name": "mounts_tables", "folder_name": "mounts_tables", "key_field": "key"},
            {"table_name": "melee_weapons_tables", "folder_name": "melee_weapons_tables", "key_field": "key"},
            {"table_name": "missile_weapons_tables", "folder_name": "missile_weapons_tables", "key_field": "key"},
            {"table_name": "unit_description_short_texts_tables", "folder_name": "unit_description_short_texts_tables", "key_field": "key"},
            {"table_name": "unit_attributes_groups_tables", "folder_name": "unit_attributes_groups_tables", "key_field": "group_name"},
            {"table_name": "battlefield_engines_tables", "folder_name": "battlefield_engines_tables", "key_field": "key"},
            {"table_name": "projectiles_tables", "folder_name": "projectiles_tables", "key_field": "key"},
            {"table_name": "battle_vortexs_tables", "folder_name": "battle_vortexs_tables", "key_field": "vortex_key"},
            {"table_name": "projectiles_scaling_damages_tables", "folder_name": "projectiles_scaling_damages_tables", "key_field": "key"},
            {"table_name": "projectile_shot_type_displays_tables", "folder_name": "projectile_shot_type_displays_tables", "key_field": "key"},
            {"table_name": "unit_spacings_tables", "folder_name": "unit_spacings_tables", "key_field": "key"},
            {"table_name": "first_person_engines_tables", "folder_name": "first_person_engines_tables", "key_field": "key"},
            {"table_name": "land_unit_articulated_vehicles_tables", "folder_name": "land_unit_articulated_vehicles_tables", "key_field": "key"},
            {"table_name": "ui_unit_groupings_tables", "folder_name": "ui_unit_groupings_tables", "key_field": "key"},
            {"table_name": "ui_unit_group_parents_tables", "folder_name": "ui_unit_group_parents_tables", "key_field": "key"},
            {"table_name": "variants_tables", "folder_name": "variants_tables", "key_field": "variant_name"},
        ]

        # Track processed unit+effect combinations across all mods to prevent duplicates.
        processed_unit_effects = set()

        # Track processed keys for each table type to prevent duplicates.
        # Map table names to their key field names.
        table_key_fields = {
            "unit_description_historical_texts_tables": "key",
            "battle_animations_table_tables": "key",
            "battle_entities_tables": "key",
            "mounts_tables": "key",
            "melee_weapons_tables": "key",
            "missile_weapons_tables": "key",
            "unit_description_short_texts_tables": "key",
            "unit_attributes_groups_tables": "group_name",
            "battlefield_engines_tables": "key",
            "projectiles_tables": "key",
            "battle_vortexs_tables": "vortex_key",
            "projectiles_scaling_damages_tables": "key",
            "projectile_shot_type_displays_tables": "key",
            "unit_spacings_tables": "key",
            "first_person_engines_tables": "key",
            "land_unit_articulated_vehicles_tables": "key",
            "ui_unit_groupings_tables": "key",
            "ui_unit_group_parents_tables": "key",
            "variants_tables": "variant_name",
            "land_units_tables": "key",
            "main_units_tables": "unit",
        }

        # Initialize tracking sets for each table.
        processed_table_keys = {table_name: set() for table_name in table_key_fields.keys()}

        def should_add_table_entry(table_name: str, entry_data: Dict[str, Any]):
            """Check if a table entry should be added (not a duplicate).

            Args:
                table_name: Name of the table.
                entry_data: Dictionary containing the entry data.

            Returns:
                True if the entry should be added, False if it's a duplicate.
            """
            if table_name not in table_key_fields:
                return True  # Unknown table, allow it.
            key_field = table_key_fields[table_name]
            entry_key = entry_data.get(key_field)
            if entry_key is None:
                return True  # No key field, allow it.
            if entry_key in processed_table_keys[table_name]:
                logging.debug(f"Skipping duplicate entry {entry_key} for table {table_name}.")
                return False
            processed_table_keys[table_name].add(entry_key)
            return True

        for mod in SUPPORTED_MODS:
            # Check if the mod is installed.
            if mod["path"] and not os.path.exists(mod["path"]):
                MISSING_MODS.append(mod["package_name"])
                continue
            # Otherwise, it will need to be skipped due to it causing the final TSV file to be corrupted.
            if mod["package_name"] in ["vanilla"]:
                continue
            # Ignore mods that are just a collection of Regiment of Renown units.
            if re.search(r"ror_|_ror_|_ror", mod["package_name"]):
                logging.info(f"Skipping {mod['package_name']} because it is just a collection of Regiment of Renown units.")
                continue

            logging.info(f"Processing the mod: {mod['package_name']}")

            # Table names cannot end in numbers.
            folder_name = mod["package_name"].replace(".pack", "").replace(" ", "_")
            if folder_name[-1].isdigit():
                folder_name = folder_name[:-1]

            # Extract and load all the required and optional tables needed for this mod.
            table_data = extract_and_load_table_data(mod["path"], table_configs)
            if table_data is None:
                continue

            # Extract the variantmeshes/variantmeshdefinitions folder if it exists.
            variant_mesh_definitions_to_add = []
            variant_mesh_models_to_add = []
            subprocess.run(
                [
                    "./rpfm_cli.exe",
                    "--game",
                    "warhammer_3",
                    "pack",
                    "extract",
                    "--pack-path",
                    mod["path"],
                    "--folder-path",
                    "variantmeshes;./modded_variantmeshes",
                ],
                capture_output=True,
            )

            # Load required tables into separate mappings.
            units_to_factions_mapping = {}
            main_units_mapping = {}
            for data in table_data["units_to_groupings_military_permissions_tables"].values():
                units_to_factions_mapping[data["unit"]] = data["military_group"]
            for data in table_data["main_units_tables"].values():
                main_units_mapping[data["unit"]] = data
            merged_modded_land_units_data = list(table_data["land_units_tables"].values())
            modded_land_units_headers = table_data["land_units_tables_headers"]
            modded_land_units_version_info = table_data["land_units_tables_version_info"]
            modded_main_units_headers = table_data["main_units_tables_headers"]
            modded_main_units_version_info = table_data["main_units_tables_version_info"]

            list_of_data_to_add = []
            for data in merged_modded_land_units_data:
                new_data = {
                    "key": data["key"],
                    "unit_purchasable_effect_sets": [],
                    "land_units": [],
                    "main_units": [],
                    "unit_description_historical_texts": [],
                    "battle_animations": [],
                    "battle_entities": [],
                    "mounts": [],
                    "melee_weapons": [],
                    "missile_weapons": [],
                    "unit_description_short_texts": [],
                    "unit_attributes_groups": [],
                    "battlefield_engines": [],
                    "projectiles": [],
                    "battle_vortexs": [],
                    "projectiles_scaling_damages": [],
                    "projectile_shot_type_displays": [],
                    "unit_spacings": [],
                    "first_person_engines": [],
                    "land_unit_articulated_vehicles": [],
                    "ui_unit_groupings": [],
                    "ui_unit_group_parents": [],
                    "variants": [],
                }

                faction = units_to_factions_mapping.get(data["key"])
                if not faction:
                    continue
                logging.debug(f"Processing the unit key: {data['key']}.")

                # Collect all possible effects for the unit.
                for effect in process_unit_by_category(data, main_units_mapping, faction):
                    if effect:
                        # Check if this unit+effect combination has already been processed.
                        unit_effect_key = (data["key"], effect)
                        if unit_effect_key in processed_unit_effects:
                            logging.debug(f"Skipping duplicate effect {effect} for unit {data['key']}.")
                            continue
                        # Mark this combination as processed.
                        processed_unit_effects.add(unit_effect_key)
                        new_data["unit_purchasable_effect_sets"].append(
                            {
                                "unit": data["key"],
                                "purchasable_effect": effect,
                                "is_exclusive": "False",
                            }
                        )
                if len(new_data["unit_purchasable_effect_sets"]) > 0:
                    try:
                        # If the unit key does not exist in the main_units_tables, that means the mod edited a vanilla unit. So it is okay if there is no record for it.
                        # This will raise the KeyError.
                        if data["key"] in main_units_mapping:
                            main_unit_data = main_units_mapping[data["key"]]
                            if should_add_table_entry("main_units_tables", main_unit_data):
                                new_data["main_units"].append(main_unit_data)
                            if should_add_table_entry("land_units_tables", data):
                                new_data["land_units"].append(data)

                            # Use the entry from land_units_tables to get the entries from the following tables.
                            # This is to make the mod standalone while keeping it as trimmed down as possible without crashing.
                            if (
                                data.get("historical_description_text")
                                and data["historical_description_text"] in table_data["unit_description_historical_texts_tables"]
                            ):
                                entry = table_data["unit_description_historical_texts_tables"][data["historical_description_text"]]
                                if should_add_table_entry("unit_description_historical_texts_tables", entry):
                                    new_data["unit_description_historical_texts"].append(entry)
                            if data.get("man_animation") and data["man_animation"] in table_data["battle_animations_table_tables"]:
                                entry = table_data["battle_animations_table_tables"][data["man_animation"]]
                                if should_add_table_entry("battle_animations_table_tables", entry):
                                    new_data["battle_animations"].append(entry)
                            if data.get("man_entity") and data["man_entity"] in table_data["battle_entities_tables"]:
                                entry = table_data["battle_entities_tables"][data["man_entity"]]
                                if should_add_table_entry("battle_entities_tables", entry):
                                    new_data["battle_entities"].append(entry)
                            if data.get("mount") and data["mount"] in table_data["mounts_tables"]:
                                mount_data = table_data["mounts_tables"][data["mount"]]
                                if should_add_table_entry("mounts_tables", mount_data):
                                    new_data["mounts"].append(mount_data)
                                mount_battle_entity = mount_data.get("entity")
                                if mount_battle_entity and mount_battle_entity in table_data["battle_entities_tables"]:
                                    entry = table_data["battle_entities_tables"][mount_battle_entity]
                                    if should_add_table_entry("battle_entities_tables", entry):
                                        new_data["battle_entities"].append(entry)
                                if mount_data.get("variant") and mount_data["variant"] in table_data["variants_tables"]:
                                    variant_data = table_data["variants_tables"][mount_data["variant"]]
                                    if should_add_table_entry("variants_tables", variant_data):
                                        new_data["variants"].append(variant_data)

                                    # Add the variantmeshdefinition for this mount if it exists. This applies to vanilla mounts only.
                                    if (
                                        mount_data.get("key") in vanilla_mounts_tables_dataframe.key.values
                                        and variant_data.get("variant_filename")
                                        and os.path.exists(
                                            f"./modded_variantmeshes/variantmeshes/variantmeshdefinitions/{variant_data['variant_filename']}.variantmeshdefinition"
                                        )
                                    ):
                                        variant_mesh_definitions_to_add.append(
                                            f"./modded_variantmeshes/variantmeshes/variantmeshdefinitions/{variant_data['variant_filename']}.variantmeshdefinition"
                                        )
                            if data.get("primary_melee_weapon") and data["primary_melee_weapon"] in table_data["melee_weapons_tables"]:
                                melee_weapon_data = table_data["melee_weapons_tables"][data["primary_melee_weapon"]]
                                if should_add_table_entry("melee_weapons_tables", melee_weapon_data):
                                    new_data["melee_weapons"].append(melee_weapon_data)

                                # Use the entry from melee_weapons_tables if available to get the entry from projectiles_scaling_damages_tables.
                                if melee_weapon_data.get("scaling_damage"):
                                    entry = table_data["projectiles_scaling_damages_tables"][melee_weapon_data["scaling_damage"]]
                                    if should_add_table_entry("projectiles_scaling_damages_tables", entry):
                                        new_data["projectiles_scaling_damages"].append(entry)

                            if data.get("primary_missile_weapon") and data["primary_missile_weapon"] in table_data["missile_weapons_tables"]:
                                missile_weapon_data = table_data["missile_weapons_tables"][data["primary_missile_weapon"]]
                                if should_add_table_entry("missile_weapons_tables", missile_weapon_data):
                                    new_data["missile_weapons"].append(missile_weapon_data)

                                # Use the entry from missile_weapons_tables if available to get the entries from the following tables.
                                if (
                                    missile_weapon_data.get("default_projectile")
                                    and missile_weapon_data["default_projectile"] in table_data["projectiles_tables"]
                                ):
                                    entry = table_data["projectiles_tables"][missile_weapon_data["default_projectile"]]
                                    if should_add_table_entry("projectiles_tables", entry):
                                        new_data["projectiles"].append(entry)
                                    if entry.get("spawned_vortex") and entry["spawned_vortex"] in table_data["battle_vortexs_tables"]:
                                        vortex_entry = table_data["battle_vortexs_tables"][entry["spawned_vortex"]]
                                        if should_add_table_entry("battle_vortexs_tables", vortex_entry):
                                            new_data["battle_vortexs"].append(vortex_entry)
                                    if (
                                        entry.get("projectile_shot_type_display")
                                        and entry["projectile_shot_type_display"] in table_data["projectile_shot_type_displays_tables"]
                                    ):
                                        display_entry = table_data["projectile_shot_type_displays_tables"][entry["projectile_shot_type_display"]]
                                        if should_add_table_entry("projectile_shot_type_displays_tables", display_entry):
                                            new_data["projectile_shot_type_displays"].append(display_entry)
                                if (
                                    missile_weapon_data.get("scaling_damage")
                                    and missile_weapon_data["scaling_damage"] in table_data["projectiles_scaling_damages_tables"]
                                ):
                                    entry = table_data["projectiles_scaling_damages_tables"][missile_weapon_data["scaling_damage"]]
                                    if should_add_table_entry("projectiles_scaling_damages_tables", entry):
                                        new_data["projectiles_scaling_damages"].append(entry)

                            if (
                                data.get("short_description_text")
                                and data["short_description_text"] in table_data["unit_description_short_texts_tables"]
                            ):
                                entry = table_data["unit_description_short_texts_tables"][data["short_description_text"]]
                                if should_add_table_entry("unit_description_short_texts_tables", entry):
                                    new_data["unit_description_short_texts"].append(entry)
                            if data.get("attribute_group") and data["attribute_group"] in table_data["unit_attributes_groups_tables"]:
                                entry = table_data["unit_attributes_groups_tables"][data["attribute_group"]]
                                if should_add_table_entry("unit_attributes_groups_tables", entry):
                                    new_data["unit_attributes_groups"].append(entry)
                            if data.get("engine") and data["engine"] in table_data["battlefield_engines_tables"]:
                                engine_data = table_data["battlefield_engines_tables"][data["engine"]]
                                if should_add_table_entry("battlefield_engines_tables", engine_data):
                                    new_data["battlefield_engines"].append(engine_data)

                                if engine_data.get("battle_entity") and engine_data["battle_entity"] in table_data["battle_entities_tables"]:
                                    entry = table_data["battle_entities_tables"][engine_data["battle_entity"]]
                                    if should_add_table_entry("battle_entities_tables", entry):
                                        new_data["battle_entities"].append(entry)
                            if data.get("spacing") and data["spacing"] in table_data["unit_spacings_tables"]:
                                entry = table_data["unit_spacings_tables"][data["spacing"]]
                                if should_add_table_entry("unit_spacings_tables", entry):
                                    new_data["unit_spacings"].append(entry)
                            if data.get("first_person") and data["first_person"] in table_data["first_person_engines_tables"]:
                                entry = table_data["first_person_engines_tables"][data["first_person"]]
                                if should_add_table_entry("first_person_engines_tables", entry):
                                    new_data["first_person_engines"].append(entry)
                            if data.get("articulated_record") and data["articulated_record"] in table_data["land_unit_articulated_vehicles_tables"]:
                                articulated_vehicle_data = table_data["land_unit_articulated_vehicles_tables"][data["articulated_record"]]
                                if should_add_table_entry("land_unit_articulated_vehicles_tables", articulated_vehicle_data):
                                    new_data["land_unit_articulated_vehicles"].append(articulated_vehicle_data)

                                # Use the entry from land_unit_articulated_vehicles_tables if available to get the entry from battle_entities_tables.
                                if (
                                    articulated_vehicle_data.get("articulated_entity")
                                    and articulated_vehicle_data["articulated_entity"] in table_data["battle_entities_tables"]
                                ):
                                    entry = table_data["battle_entities_tables"][articulated_vehicle_data["articulated_entity"]]
                                    if should_add_table_entry("battle_entities_tables", entry):
                                        new_data["battle_entities"].append(entry)
                            if (
                                main_unit_data.get("ui_unit_group_land")
                                and main_unit_data["ui_unit_group_land"] in table_data["ui_unit_groupings_tables"]
                            ):
                                ui_unit_grouping_data = table_data["ui_unit_groupings_tables"][main_unit_data["ui_unit_group_land"]]
                                if should_add_table_entry("ui_unit_groupings_tables", ui_unit_grouping_data):
                                    new_data["ui_unit_groupings"].append(ui_unit_grouping_data)

                                if (
                                    ui_unit_grouping_data.get("parent_group")
                                    and ui_unit_grouping_data["parent_group"] in table_data["ui_unit_group_parents_tables"]
                                ):
                                    entry = table_data["ui_unit_group_parents_tables"][ui_unit_grouping_data["parent_group"]]
                                    if should_add_table_entry("ui_unit_group_parents_tables", entry):
                                        new_data["ui_unit_group_parents"].append(entry)

                        list_of_data_to_add.append(new_data)
                    except KeyError as e:
                        logging.exception(e)
                        pass

            if len(list_of_data_to_add) > 0:
                # Write the updated data tables to the required TSV files.
                unit_purchasable_effect_sets_tables_version_info = vanilla_unit_purchasable_effect_sets_tables_version_info.replace(
                    "data__", f"!!!{folder_name}"
                )
                land_units_version_info = modded_land_units_version_info.replace(modded_land_units_version_info.split("/")[-1], f"!!!{folder_name}")
                main_units_version_info = modded_main_units_version_info.replace(modded_main_units_version_info.split("/")[-1], f"!!!{folder_name}")

                tables_to_sort = [
                    "./!!!!!!!_nanu_dynamic_rors_compat/db/land_units_tables",
                    "./!!!!!!!_nanu_dynamic_rors_compat/db/main_units_tables",
                    "./!!!!!!!_nanu_dynamic_rors_compat/db/unit_purchasable_effect_sets_tables",
                ]

                # Write the data to required and optional tables.
                for data_to_add in list_of_data_to_add:
                    logging.debug(
                        f"Writing {len(data_to_add['unit_purchasable_effect_sets'])} unit purchasable effect sets for {data_to_add['key']}."
                    )

                    # Write to the required tables first.
                    # Set allow_duplicates=False so write_updated_tsv_file checks for duplicates using composite key (unit + purchasable_effect).
                    write_updated_tsv_file(
                        data_to_add["unit_purchasable_effect_sets"],
                        vanilla_unit_purchasable_effect_sets_tables_headers,
                        unit_purchasable_effect_sets_tables_version_info,
                        "./!!!!!!!_nanu_dynamic_rors_compat/db/unit_purchasable_effect_sets_tables",
                        f"!!!{folder_name}",
                        allow_duplicates=False,
                    )
                    write_updated_tsv_file(
                        data_to_add["land_units"],
                        modded_land_units_headers,
                        land_units_version_info,
                        "./!!!!!!!_nanu_dynamic_rors_compat/db/land_units_tables",
                        f"!!!{folder_name}",
                    )
                    write_updated_tsv_file(
                        data_to_add["main_units"],
                        modded_main_units_headers,
                        main_units_version_info,
                        "./!!!!!!!_nanu_dynamic_rors_compat/db/main_units_tables",
                        f"!!!{folder_name}",
                    )

                    # Now write to all of the available optional tables.
                    optional_tables = [
                        ("unit_description_historical_texts", "unit_description_historical_texts_tables"),
                        ("battle_animations", "battle_animations_table_tables"),
                        ("battle_entities", "battle_entities_tables"),
                        ("mounts", "mounts_tables"),
                        ("melee_weapons", "melee_weapons_tables"),
                        ("missile_weapons", "missile_weapons_tables"),
                        ("unit_description_short_texts", "unit_description_short_texts_tables"),
                        ("unit_attributes_groups", "unit_attributes_groups_tables"),
                        ("battlefield_engines", "battlefield_engines_tables"),
                        ("projectiles", "projectiles_tables"),
                        ("battle_vortexs", "battle_vortexs_tables"),
                        ("projectiles_scaling_damages", "projectiles_scaling_damages_tables"),
                        ("projectile_shot_type_displays", "projectile_shot_type_displays_tables"),
                        ("unit_spacings", "unit_spacings_tables"),
                        ("first_person_engines", "first_person_engines_tables"),
                        ("land_unit_articulated_vehicles", "land_unit_articulated_vehicles_tables"),
                        ("ui_unit_groupings", "ui_unit_groupings_tables"),
                        ("ui_unit_group_parents", "ui_unit_group_parents_tables"),
                        ("variants", "variants_tables"),
                    ]
                    for data_key, table_name in optional_tables:
                        if data_to_add[data_key]:
                            version_info = table_data[f"{table_name}_version_info"].replace(
                                table_data[f"{table_name}_version_info"].split("/")[-1], f"!!!{folder_name}"
                            )
                            write_updated_tsv_file(
                                data_to_add[data_key],
                                table_data[f"{table_name}_headers"],
                                version_info,
                                f"./!!!!!!!_nanu_dynamic_rors_compat/db/{table_name}",
                                f"!!!{folder_name}",
                            )
                            tables_to_sort.append(f"./!!!!!!!_nanu_dynamic_rors_compat/db/{table_name}")

                            # Add the variantmeshdefinition for mounts if available.
                            if table_name == "mounts_tables" and variant_mesh_definitions_to_add:
                                for variant_mesh_definition in variant_mesh_definitions_to_add:
                                    os.makedirs(f"./!!!!!!!_nanu_dynamic_rors_compat/variantmeshes/variantmeshdefinitions", exist_ok=True)
                                    try:
                                        shutil.move(
                                            variant_mesh_definition,
                                            f"./!!!!!!!_nanu_dynamic_rors_compat/variantmeshes/variantmeshdefinitions/{os.path.basename(variant_mesh_definition)}",
                                        )
                                        mesh_model_paths = extract_model_paths_from_variantmeshdefinition(
                                            f"./!!!!!!!_nanu_dynamic_rors_compat/variantmeshes/variantmeshdefinitions/{os.path.basename(variant_mesh_definition)}"
                                        )
                                        for mesh_model_path in mesh_model_paths:
                                            if os.path.exists(f"./!!!!!!!_nanu_dynamic_rors_compat/variantmeshes/wh_variantmodels/{mesh_model_path}"):
                                                os.remove(f"./!!!!!!!_nanu_dynamic_rors_compat/variantmeshes/wh_variantmodels/{mesh_model_path}")
                                            os.makedirs("./!!!!!!!_nanu_dynamic_rors_compat/variantmeshes/wh_variantmodels", exist_ok=True)
                                            shutil.move(
                                                f"./modded_variantmeshes/variantmeshes/wh_variantmodels/{mesh_model_path}",
                                                f"./!!!!!!!_nanu_dynamic_rors_compat/variantmeshes/wh_variantmodels/{mesh_model_path}",
                                            )
                                    except FileNotFoundError:
                                        logging.error(f"variantmeshdefinition not found: {variant_mesh_definition}.")
                                        pass

                # After writing is complete, sort the required and optional tables.
                for table_path in tables_to_sort:
                    sort_tsv_data(
                        table_path,
                        f"!!!{folder_name}",
                    )

            # Perform cleanup of modded folders.
            cleanup_folders(
                [
                    "./modded_units_to_groupings_military_permissions_tables",
                    "./modded_land_units_tables",
                    "./modded_main_units_tables",
                    "./modded_unit_description_historical_texts_tables",
                    "./modded_battle_animations_table_tables",
                    "./modded_battle_entities_tables",
                    "./modded_mounts_tables",
                    "./modded_melee_weapons_tables",
                    "./modded_missile_weapons_tables",
                    "./modded_unit_description_short_texts_tables",
                    "./modded_unit_attributes_groups_tables",
                    "./modded_battlefield_engines_tables",
                    "./modded_projectiles_tables",
                    "./modded_battle_vortexs_tables",
                    "./modded_projectiles_scaling_damages_tables",
                    "./modded_projectile_shot_type_displays_tables",
                    "./modded_unit_spacings_tables",
                    "./modded_first_person_engines_tables",
                    "./modded_land_unit_articulated_vehicles_tables",
                    "./modded_ui_unit_groupings_tables",
                    "./modded_ui_unit_group_parents_tables",
                    "./modded_variants_tables",
                    "./modded_variantmeshes",
                ]
            )

            logging.info(f"Processed {len(list_of_data_to_add)} units for {mod['package_name']}.")

            # Clear the data list from memory to avoid accessing old data in the next iteration.
            list_of_data_to_add.clear()
            main_units_mapping.clear()
            units_to_factions_mapping.clear()
            table_data.clear()

            gc.collect()
    except Exception as e:
        logging.exception(e)

    # After processing all mods, move the mod folder to the destination folder.
    if os.path.exists("./!!!!!!!_nanu_dynamic_rors_compat"):
        logging.info(f"Moving !!!!!!!_nanu_dynamic_rors_compat to ../mods/.")
        merge_move("./!!!!!!!_nanu_dynamic_rors_compat", "../mods/")

    # Reset if necessary.
    if args.reset:
        # Use the RPFM CLI to delete all files from the packfile.
        subprocess.run(
            [
                "./rpfm_cli.exe",
                "--game",
                "warhammer_3",
                "pack",
                "delete",
                "--pack-path",
                f"{STEAM_LIBRARY_DRIVE}\\SteamLibrary\\steamapps\\workshop\\content\\1142710\\3513364573\\!!!!!!!_nanu_dynamic_rors_compat.pack",
                "--folder-path",
                "",
            ],
            capture_output=True,
        )

    # Then merge the updated mod files into the packfile.
    subprocess.run(
        [
            "./rpfm_cli.exe",
            "--game",
            "warhammer_3",
            "pack",
            "add",
            "--pack-path",
            f"{STEAM_LIBRARY_DRIVE}\\SteamLibrary\\steamapps\\workshop\\content\\1142710\\3513364573\\!!!!!!!_nanu_dynamic_rors_compat.pack",
            "--tsv-to-binary",
            "./schemas/schema_wh3.ron",
            "--folder-path",
            f"../mods/!!!!!!!_nanu_dynamic_rors_compat;",
        ],
        capture_output=True,
    )

    # Perform final cleanup of vanilla folders.
    cleanup_folders(
        [
            "./vanilla_unit_purchasable_effect_sets_tables",
            "./vanilla_mounts_tables",
            "./vanilla_main_units_tables",
            "./vanilla_land_units_tables",
            "./vanilla_units_to_groupings_military_permissions_tables",
            "./nanu_unit_purchasable_effect_sets_tables",
        ]
    )

    if MISSING_MODS:
        logging.info(f"Missing mods: {MISSING_MODS}")

    end_time = round(time.time() - start_time, 2)
    logging.info(f"Total time: {end_time} seconds or {round(end_time / 60, 2)} minutes.")
