"""Script to update the dynamic RORs for Nanu from the Steam Workshop to account for latest changes to modded data tables."""

from utilities import (
    extract_tsv_data,
    read_and_clean_tsv,
    load_tsv_data,
    extract_modded_tsv_data,
    write_updated_tsv_file,
    sort_tsv_data,
    merge_move,
    cleanup_folders,
    ensure_temp_dir,
    TEMP_DIR,
)
from supported_mods import SUPPORTED_MODS
from dynamic_rors_effects import SUPPORTED_EFFECTS
from pipeline import (
    DuplicateTracker,
    add_folder_to_pack,
    clean_folder_name,
    cleanup_modded_folders,
    extract_and_load_table_data,
    extract_variantmeshes_folder,
    make_new_data_buckets,
    move_variantmesh_definitions,
    reset_pack_folders,
    walk_land_unit_to_related_tables,
    workshop_pack_path,
    write_optional_tables,
    TABLE_CONFIGS,
)
import time
import os
import logging
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass
from typing import Dict, Any, List, Optional
import gc
import re
import argparse


MISSING_MODS = []


@dataclass
class ModExtractResult:
    """Worker-extracted state for one mod, consumed by the serial merge pass."""

    mod_index: int
    mod: Dict[str, Any]
    folder_name: str
    scratch_root: str
    variantmeshes_root: str
    table_data: Dict[str, Any]
    modded_land_units_headers: List[str]
    modded_land_units_version_info: str
    modded_main_units_headers: List[str]
    modded_main_units_version_info: str
    units_to_factions_mapping: Dict[str, str]
    main_units_mapping: Dict[str, Any]
    merged_modded_land_units_data: List[Dict[str, Any]]

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


if __name__ == "__main__":
    logging.basicConfig(format="%(asctime)s - %(levelname)s - %(message)s", level=logging.INFO)
    start_time = time.time()

    # Get arguments from argparse.
    parser = argparse.ArgumentParser()
    parser.add_argument("--reset", action="store_true", help="Reset the script.")
    parser.add_argument("--vanilla", action="store_true", help="Process vanilla units only.")
    parser.add_argument(
        "--workers",
        type=int,
        default=min(8, (os.cpu_count() or 4)),
        help="Number of worker threads for parallel mod extraction. Use 1 to force sequential (e.g. for debugging or output-equivalence diffs). Does not affect the serial dedup/write pass.",
    )
    args = parser.parse_args()
    compat_pack_path = workshop_pack_path("3513364573", "!!!!!!!_nanu_dynamic_rors_compat.pack")
    leftover_pack_path = workshop_pack_path("3532864014", "!!!!!!!_nanu_dynamic_rors_leftover_vanilla.pack")

    if args.reset:
        logging.info("Will reset folders in the packfile before writing.")
        cleanup_folders(
            [
                "../warhammer3_mods/!!!!!!!_nanu_dynamic_rors_compat/db",
                "../warhammer3_mods/!!!!!!!_nanu_dynamic_rors_compat/variantmeshes",
            ]
        )

    ensure_temp_dir()

    # Ensure all folders are cleaned up before the script starts if they exist.
    cleanup_folders(
        [
            f"{TEMP_DIR}/vanilla_unit_purchasable_effect_sets_tables",
            f"{TEMP_DIR}/vanilla_mounts_tables",
            f"{TEMP_DIR}/!!!!!!!_nanu_dynamic_rors_leftover_vanilla",
            f"{TEMP_DIR}/vanilla_main_units_tables",
            f"{TEMP_DIR}/vanilla_land_units_tables",
            f"{TEMP_DIR}/vanilla_units_to_groupings_military_permissions_tables",
            f"{TEMP_DIR}/nanu_unit_purchasable_effect_sets_tables",
        ]
    )
    cleanup_modded_folders()

    try:
        # Extract the vanilla unit_purchasable_effect_sets_tables and mounts_tables data.
        extract_tsv_data("unit_purchasable_effect_sets_tables")
        _, vanilla_unit_purchasable_effect_sets_tables_headers, vanilla_unit_purchasable_effect_sets_tables_version_info = load_tsv_data(
            f"{TEMP_DIR}/vanilla_unit_purchasable_effect_sets_tables/db/unit_purchasable_effect_sets_tables/data__.tsv"
        )
        extract_tsv_data("mounts_tables")
        vanilla_mounts_tables_dataframe = read_and_clean_tsv(f"{TEMP_DIR}/vanilla_mounts_tables/db/mounts_tables/data__.tsv", "mounts_tables")

        # Secondary mode: Process vanilla units only.
        if args.vanilla:
            # Extract the vanilla main_units_tables, land_units_tables and units_to_groupings_military_permissions_tables data.
            extract_tsv_data("main_units_tables")
            vanilla_main_units_tables_dataframe = read_and_clean_tsv(
                f"{TEMP_DIR}/vanilla_main_units_tables/db/main_units_tables/data__.tsv", "main_units_tables"
            )
            extract_tsv_data("land_units_tables")
            vanilla_land_units_tables_dataframe = read_and_clean_tsv(
                f"{TEMP_DIR}/vanilla_land_units_tables/db/land_units_tables/data__.tsv", "land_units_tables"
            )
            extract_tsv_data("units_to_groupings_military_permissions_tables")
            vanilla_units_to_groupings_military_permissions_tables_dataframe = read_and_clean_tsv(
                f"{TEMP_DIR}/vanilla_units_to_groupings_military_permissions_tables/db/units_to_groupings_military_permissions_tables/data__.tsv",
                "units_to_groupings_military_permissions_tables",
            )

            # Extract Nanu's unit_purchasable_effect_sets_tables data.
            extract_modded_tsv_data(
                "unit_purchasable_effect_sets_tables",
                workshop_pack_path("3278112051", "!!_nanu_dynamic_rors.pack"),
                f"{TEMP_DIR}/nanu_unit_purchasable_effect_sets_tables",
            )

            processed_unit_keys = set()
            for faction in FACTION_SHORTHAND_KEY_MAPPING.keys():
                list_of_vanilla_data_to_add = []
                try:
                    nanu_faction_data, _, _ = load_tsv_data(
                        f"{TEMP_DIR}/nanu_unit_purchasable_effect_sets_tables/db/unit_purchasable_effect_sets_tables/nanu_dynamic_rors_{faction}.tsv"
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
                        f"{TEMP_DIR}/!!!!!!!_nanu_dynamic_rors_leftover_vanilla/db/unit_purchasable_effect_sets_tables",
                        f"!!!nanu_dynamic_rors_{faction}",
                        allow_duplicates=True,
                    )
                    nanu_main_unit_keys.clear()
                    list_of_vanilla_data_to_add.clear()
                    units_not_supported_by_nanu.clear()
                    gc.collect()

                    sort_tsv_data(
                        f"{TEMP_DIR}/!!!!!!!_nanu_dynamic_rors_leftover_vanilla/db/unit_purchasable_effect_sets_tables",
                        f"!!!nanu_dynamic_rors_{faction}",
                    )

            # After processing all mods, move the mod folder to the destination folder.
            if os.path.exists(f"{TEMP_DIR}/!!!!!!!_nanu_dynamic_rors_leftover_vanilla"):
                logging.info(f"Moving !!!!!!!_nanu_dynamic_rors_leftover_vanilla to ../warhammer3_mods/.")
                merge_move(f"{TEMP_DIR}/!!!!!!!_nanu_dynamic_rors_leftover_vanilla", "../warhammer3_mods/")

            if args.reset:
                reset_pack_folders(leftover_pack_path, ("db",))

            add_folder_to_pack(
                leftover_pack_path,
                "../warhammer3_mods/!!!!!!!_nanu_dynamic_rors_leftover_vanilla/db/unit_purchasable_effect_sets_tables;db/unit_purchasable_effect_sets_tables",
            )

            exit(0)

        # Primary mode: Process modded units.
        # Mark the three required tables since extraction failure for any of them means we skip the mod entirely.
        primary_table_configs = [
            {**cfg, "required": True} if cfg["table_name"] in ("units_to_groupings_military_permissions_tables", "main_units_tables", "land_units_tables") else cfg
            for cfg in TABLE_CONFIGS
        ]
        vanilla_mounts_keys = set(vanilla_mounts_tables_dataframe.key.values)

        # Track processed unit+effect combinations across all mods to prevent duplicates.
        processed_unit_effects = set()
        tracker = DuplicateTracker()

        # Pre-filter the mod list: missing-on-disk go to MISSING_MODS, "vanilla" and pure-RoR-collection mods are skipped. Whatever remains is what gets extracted in parallel and then merged serially in original-index order.
        mods_to_process: List[tuple] = []
        for idx, mod in enumerate(SUPPORTED_MODS):
            if mod["path"] and not os.path.exists(mod["path"]):
                MISSING_MODS.append(mod["package_name"])
                continue
            if mod["package_name"] in ["vanilla"]:
                continue
            if re.search(r"ror_|_ror_|_ror", mod["package_name"]):
                logging.info(f"Skipping {mod['package_name']} because it is just a collection of Regiment of Renown units.")
                continue
            mods_to_process.append((idx, mod))

        def extract_mod_data(idx: int, mod: Dict[str, Any]) -> Optional[ModExtractResult]:
            """Extract one mod's table data and variantmeshes into a per-mod scratch dir and build the per-mod mappings consumed by the serial merge pass.

            All I/O-heavy work (rpfm_cli subprocess, TSV parsing) happens here. The dedup-gated FK walk and TSV writes are deferred to the serial pass so the global `processed_unit_effects` / `DuplicateTracker` stay deterministic.

            Args:
                idx (int): Original index of `mod` in `SUPPORTED_MODS`. Preserved on the result so the serial pass can re-sort.
                mod (Dict[str, Any]): Entry from `SUPPORTED_MODS`.

            Returns:
                A `ModExtractResult` if extraction yielded the three required tables, otherwise None (mod is silently dropped).
            """
            logging.info(f"Extracting the mod: {mod['package_name']}")
            folder_name = clean_folder_name(mod["package_name"])
            scratch_root = f"{TEMP_DIR}/{folder_name}"
            variantmeshes_root = f"{scratch_root}/modded_variantmeshes"

            table_data = extract_and_load_table_data(mod["path"], primary_table_configs, scratch_root=scratch_root)
            if table_data is None:
                cleanup_modded_folders(scratch_root=scratch_root)
                return None

            extract_variantmeshes_folder(mod["path"], dest=variantmeshes_root)

            units_to_factions_mapping = {data["unit"]: data["military_group"] for data in table_data["units_to_groupings_military_permissions_tables"].values()}
            main_units_mapping = {data["unit"]: data for data in table_data["main_units_tables"].values()}
            merged_modded_land_units_data = list(table_data["land_units_tables"].values())

            return ModExtractResult(
                mod_index=idx,
                mod=mod,
                folder_name=folder_name,
                scratch_root=scratch_root,
                variantmeshes_root=variantmeshes_root,
                table_data=table_data,
                modded_land_units_headers=table_data["land_units_tables_headers"],
                modded_land_units_version_info=table_data["land_units_tables_version_info"],
                modded_main_units_headers=table_data["main_units_tables_headers"],
                modded_main_units_version_info=table_data["main_units_tables_version_info"],
                units_to_factions_mapping=units_to_factions_mapping,
                main_units_mapping=main_units_mapping,
                merged_modded_land_units_data=merged_modded_land_units_data,
            )

        logging.info(f"Extracting {len(mods_to_process)} mods with {args.workers} worker thread(s).")
        extract_results: List[Optional[ModExtractResult]] = []
        if args.workers <= 1:
            for idx, mod in mods_to_process:
                extract_results.append(extract_mod_data(idx, mod))
        else:
            with ThreadPoolExecutor(max_workers=args.workers) as executor:
                futures = {executor.submit(extract_mod_data, idx, mod): (idx, mod) for idx, mod in mods_to_process}
                for future in as_completed(futures):
                    idx, mod = futures[future]
                    try:
                        extract_results.append(future.result())
                    except Exception:
                        logging.exception(f"Extraction worker failed for mod {mod.get('package_name', '<unknown>')}.")
                        raise

        # Re-sort by original SUPPORTED_MODS index so the serial dedup pass is deterministic regardless of worker completion order.
        ordered_results = sorted((r for r in extract_results if r is not None), key=lambda r: r.mod_index)

        logging.info(f"Merging {len(ordered_results)} extracted mods serially.")
        for result in ordered_results:
            mod = result.mod
            folder_name = result.folder_name
            table_data = result.table_data
            units_to_factions_mapping = result.units_to_factions_mapping
            main_units_mapping = result.main_units_mapping

            variant_mesh_definitions_to_add: List[str] = []

            list_of_data_to_add = []
            for data in result.merged_modded_land_units_data:
                new_data = make_new_data_buckets(data["key"], with_purchasable_effects=True)

                faction = units_to_factions_mapping.get(data["key"])
                if not faction:
                    continue
                logging.debug(f"Processing the unit key: {data['key']}.")

                # Collect all possible effects for the unit, filtered through the global first-wins dedup set.
                for effect in process_unit_by_category(data, main_units_mapping, faction):
                    if not effect:
                        continue
                    unit_effect_key = (data["key"], effect)
                    if unit_effect_key in processed_unit_effects:
                        logging.debug(f"Skipping duplicate effect {effect} for unit {data['key']}.")
                        continue
                    processed_unit_effects.add(unit_effect_key)
                    new_data["unit_purchasable_effect_sets"].append(
                        {"unit": data["key"], "purchasable_effect": effect, "is_exclusive": "False"}
                    )

                if not new_data["unit_purchasable_effect_sets"]:
                    continue

                # If the unit key does not exist in main_units_tables, the mod edited a vanilla unit and we skip the FK walk.
                if data["key"] in main_units_mapping:
                    walk_land_unit_to_related_tables(
                        data=data,
                        main_unit_data=main_units_mapping[data["key"]],
                        table_data=table_data,
                        tracker=tracker,
                        new_data=new_data,
                        vanilla_mounts_keys=vanilla_mounts_keys,
                        variant_mesh_definitions_to_add=variant_mesh_definitions_to_add,
                        variantmeshes_root=result.variantmeshes_root,
                    )

                list_of_data_to_add.append(new_data)

            if len(list_of_data_to_add) > 0:
                # Write the updated data tables to the required TSV files.
                unit_purchasable_effect_sets_tables_version_info = vanilla_unit_purchasable_effect_sets_tables_version_info.replace(
                    "data__", f"!!!{folder_name}"
                )
                land_units_version_info = result.modded_land_units_version_info.replace(
                    result.modded_land_units_version_info.split("/")[-1], f"!!!{folder_name}"
                )
                main_units_version_info = result.modded_main_units_version_info.replace(
                    result.modded_main_units_version_info.split("/")[-1], f"!!!{folder_name}"
                )

                tables_to_sort = [
                    f"{TEMP_DIR}/!!!!!!!_nanu_dynamic_rors_compat/db/land_units_tables",
                    f"{TEMP_DIR}/!!!!!!!_nanu_dynamic_rors_compat/db/main_units_tables",
                    f"{TEMP_DIR}/!!!!!!!_nanu_dynamic_rors_compat/db/unit_purchasable_effect_sets_tables",
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
                        f"{TEMP_DIR}/!!!!!!!_nanu_dynamic_rors_compat/db/unit_purchasable_effect_sets_tables",
                        f"!!!{folder_name}",
                        allow_duplicates=False,
                    )
                    write_updated_tsv_file(
                        data_to_add["land_units"],
                        result.modded_land_units_headers,
                        land_units_version_info,
                        f"{TEMP_DIR}/!!!!!!!_nanu_dynamic_rors_compat/db/land_units_tables",
                        f"!!!{folder_name}",
                    )
                    write_updated_tsv_file(
                        data_to_add["main_units"],
                        result.modded_main_units_headers,
                        main_units_version_info,
                        f"{TEMP_DIR}/!!!!!!!_nanu_dynamic_rors_compat/db/main_units_tables",
                        f"!!!{folder_name}",
                    )

                    # Now write to all of the available optional tables.
                    write_optional_tables(
                        data_to_add, f"{TEMP_DIR}/!!!!!!!_nanu_dynamic_rors_compat", f"!!!{folder_name}", table_data, tables_to_sort
                    )

                # Move any captured variantmeshdefinitions (and their wh_variantmodels) into the compat pack. Source dir is this mod's per-worker scratch.
                move_variantmesh_definitions(
                    variant_mesh_definitions_to_add,
                    f"{TEMP_DIR}/!!!!!!!_nanu_dynamic_rors_compat",
                    variantmeshes_root=result.variantmeshes_root,
                )

                # After writing is complete, sort the required and optional tables.
                for table_path in tables_to_sort:
                    sort_tsv_data(table_path, f"!!!{folder_name}")

            cleanup_modded_folders(scratch_root=result.scratch_root)

            logging.info(f"Processed {len(list_of_data_to_add)} units for {mod['package_name']}.")

            # Clear the data list from memory to avoid retaining the per-mod state across the rest of the loop.
            list_of_data_to_add.clear()
            main_units_mapping.clear()
            units_to_factions_mapping.clear()
            table_data.clear()

            gc.collect()
    except Exception as e:
        logging.exception(e)

    # After processing all mods, move the mod folder to the destination folder.
    if os.path.exists(f"{TEMP_DIR}/!!!!!!!_nanu_dynamic_rors_compat"):
        logging.info(f"Moving !!!!!!!_nanu_dynamic_rors_compat to ../warhammer3_mods/.")
        merge_move(f"{TEMP_DIR}/!!!!!!!_nanu_dynamic_rors_compat", "../warhammer3_mods/")

    if args.reset:
        reset_pack_folders(compat_pack_path)

    # Then merge the updated mod files into the packfile.
    add_folder_to_pack(compat_pack_path, "../warhammer3_mods/!!!!!!!_nanu_dynamic_rors_compat;")

    # Perform final cleanup of vanilla folders.
    cleanup_folders(
        [
            f"{TEMP_DIR}/vanilla_unit_purchasable_effect_sets_tables",
            f"{TEMP_DIR}/vanilla_mounts_tables",
            f"{TEMP_DIR}/vanilla_main_units_tables",
            f"{TEMP_DIR}/vanilla_land_units_tables",
            f"{TEMP_DIR}/vanilla_units_to_groupings_military_permissions_tables",
            f"{TEMP_DIR}/nanu_unit_purchasable_effect_sets_tables",
        ]
    )

    if MISSING_MODS:
        logging.info(f"Missing mods: {MISSING_MODS}")

    end_time = round(time.time() - start_time, 2)
    logging.info(f"Total time: {end_time} seconds or {round(end_time / 60, 2)} minutes.")
