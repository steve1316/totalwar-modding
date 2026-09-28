"""Record which paid DLC each Kadon scroll's vanilla unit needs, so the mod can skip scrolls a player does not own.

Usage:
    cd helper_scripts && python -m tools.generate_kadon_dlc [--dry-run]

Reads CA's ownership tables: a main unit belongs to content packs, a pack is unlocked by any of its requirement sets, and a set needs all of its
products. A unit is free when any set needs only free products (base games, the Realm of Chaos update, or free LCs). Otherwise the scroll
maps to every paid product that unlocks it, and owning any one of them is enough. The result is written to `script/jvj_kadon/scroll_dlc.lua`.
"""

import argparse
import logging
import sys
from dataclasses import dataclass
from typing import Dict, List, Set

from core.utilities import setup_script_logging
from data.kadon_new_creatures import KADON_NEW_CREATURES
from data.kadon_sources import KADON_SOURCES
from tools.sync_kadon_units import load_vanilla, pick_main_unit

DLC_LUA = "../warhammer3_mods/jvj_kadon_6_0/script/jvj_kadon/scroll_dlc.lua"

# Free product keys that `is_flc` does not flag.
ALWAYS_FREE = {"TW_WH1_BASE_GAME", "TW_WH2_BASE_GAME", "TW_WH3_BASE_GAME", "TW_WH3_ROC_UPDATE"}

# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Ownership


@dataclass
class Ownership:
    """CA's ownership tables, indexed for lookups."""

    # Main unit key to the content packs it belongs to.
    unit_packs: Dict[str, Set[str]]
    # Content pack key to the requirement sets that unlock it.
    pack_sets: Dict[str, Set[str]]
    # Requirement set key to the products it needs.
    set_products: Dict[str, Set[str]]
    # Product keys every player owns.
    free: Set[str]


def free_products(product_rows: List[Dict[str, str]]) -> Set[str]:
    """Return the product keys every player owns: base games, the Realm of Chaos update, and free LCs.

    Args:
        product_rows (List[Dict[str, str]]): `ownership_products` rows.

    Returns:
        Set[str]: The free product keys.
    """
    return {row["key"] for row in product_rows if row["key"] in ALWAYS_FREE or row["is_flc"] == "true"}


def paid_products(main_unit: str, ownership: Ownership) -> List[str]:
    """Return the paid products that unlock a main unit. Owning any one of them is enough.

    Args:
        main_unit (str): Vanilla main unit key.
        ownership (Ownership): Indexed ownership tables.

    Raises:
        ValueError: A requirement set needs two or more paid products, which the any-of list cannot express.

    Returns:
        List[str]: Sorted paid product keys, or an empty list when the unit is free.
    """
    paid = set()
    for pack in ownership.unit_packs.get(main_unit, set()):
        for requirement_set in ownership.pack_sets.get(pack, set()):
            needed = ownership.set_products.get(requirement_set, set()) - ownership.free
            if not needed:
                return []
            if len(needed) > 1:
                raise ValueError(f"{main_unit}: requirement set {requirement_set} needs several paid products {sorted(needed)}")
            paid |= needed
    return sorted(paid)


def load_ownership() -> Ownership:
    """Extract and index the vanilla ownership tables.

    Returns:
        Ownership: The indexed tables.
    """
    ownership = Ownership({}, {}, {}, free_products(load_vanilla("ownership_products_tables")))
    for row in load_vanilla("main_unit_ownership_content_pack_junctions_tables"):
        ownership.unit_packs.setdefault(row["main_unit"], set()).add(row["ownership_content_pack"])
    for row in load_vanilla("ownership_content_pack_requirements_tables"):
        ownership.pack_sets.setdefault(row["content_pack"], set()).add(row["key"])
    for row in load_vanilla("ownership_content_pack_required_products_tables"):
        ownership.set_products.setdefault(row["requirement_set"], set()).add(row["product"])
    return ownership


def build_dlc_map() -> Dict[str, List[str]]:
    """Map every vanilla Kadon scroll key to the paid products its unit needs. Free scrolls are left out.

    Raises:
        ValueError: A hand-made scroll's vanilla land unit has no single canonical main unit.

    Returns:
        Dict[str, List[str]]: Scroll key to sorted paid product keys.
    """
    ownership = load_ownership()
    main_rows = load_vanilla("main_units_tables")
    scroll_units = {}
    for scroll_key, land_unit in KADON_SOURCES.items():
        main_row = pick_main_unit(land_unit, main_rows)
        if main_row is None:
            raise ValueError(f"{scroll_key}: no canonical vanilla main unit for {land_unit}")
        scroll_units[scroll_key] = main_row["unit"]
    for cid, main_unit, _ in KADON_NEW_CREATURES:
        for prefix in ("kin", "bind"):
            scroll_units[f"kadon_{prefix}_{cid}"] = main_unit

    dlc_map = {}
    for scroll_key, main_unit in scroll_units.items():
        products = paid_products(main_unit, ownership)
        if products:
            dlc_map[scroll_key] = products
    return dlc_map


def lua_dlc_map(dlc_map: Dict[str, List[str]]) -> str:
    """Render the scroll-to-DLC map as a Lua module that returns it.

    Args:
        dlc_map (Dict[str, List[str]]): Scroll key to paid product keys.

    Returns:
        str: The Lua source.
    """
    lines = [
        "--- Generated by helper_scripts/tools/generate_kadon_dlc.py from the vanilla ownership tables. Do not edit by hand.",
        "--- Maps each scroll whose unit needs paid DLC to the products that unlock it. Owning any one is enough. Free scrolls are left out.",
        "",
        "return {",
    ]
    for key in sorted(dlc_map):
        products = ", ".join(f'"{product}"' for product in dlc_map[key])
        lines.append(f"    {key} = {{ {products} }},")
    lines.append("}")
    return "\n".join(lines) + "\n"


def generate(dry_run: bool) -> int:
    """Build the scroll-to-DLC map and write it to `DLC_LUA`.

    Args:
        dry_run (bool): Log the summary without writing the file.

    Returns:
        int: Process exit code.
    """
    dlc_map = build_dlc_map()
    logging.info(f"{len(dlc_map)} of {len(KADON_SOURCES) + 2 * len(KADON_NEW_CREATURES)} vanilla scrolls need paid DLC.")
    if dry_run:
        logging.info("Dry run, nothing written.")
        return 0
    with open(DLC_LUA, "w", encoding="utf-8", newline="") as f:
        f.write(lua_dlc_map(dlc_map))
    logging.info(f"Wrote {DLC_LUA}.")
    return 0


def main() -> int:
    """Parse arguments and run the generator.

    Returns:
        int: Process exit code.
    """
    parser = argparse.ArgumentParser(description="Record the paid DLC each Kadon scroll's vanilla unit needs.")
    parser.add_argument("--dry-run", action="store_true", help="Log a summary without writing the file.")
    args = parser.parse_args()
    setup_script_logging()
    return generate(args.dry_run)


if __name__ == "__main__":
    sys.exit(main())
