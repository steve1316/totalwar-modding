"""Copy current vanilla values onto the Kadon scroll units, so summons match the game's latest balance.

Usage:
    cd helper_scripts && python -m tools.sync_kadon_units [--dry-run]

Each scroll unit that copies a vanilla creature is listed in `data/kadon_sources.py`. For those units the sync:
    1. Copies every `land_units` column from the vanilla source, except the key and any columns in `KADON_KEEP_COLUMNS`.
    2. Copies the combat, UI and audio columns of `main_units` from the source's main unit. Costs, caps and campaign settings stay as the mod has them.
    3. Replaces the unit's passive abilities with the vanilla source's, keeping the mod's own `kadon_*` abilities such as `kadon_bind_unbinding`.
"""

import argparse
import logging
import os
import re
import sys
from typing import Dict, List, Optional, Set, Tuple

from core.utilities import extract_tsv_data, setup_script_logging
from data.kadon_sources import KADON_KEEP_COLUMNS, KADON_SOURCES

MOD_DB = "../warhammer3_mods/jvj_kadon_6_0/db"
SCROLL_KINDS = ("binding", "kinship")

# main_units columns taken from vanilla. Everything else (costs, caps, porthole, campaign flags) stays as the mod has it.
MAIN_UNIT_SYNC_COLUMNS = [
    "caste", "tier", "is_high_threat", "melee_cp", "missile_cp", "weight", "ui_unit_group_land", "is_monstrous", "can_siege", "barrier_health",
    "num_men", "min_men_per_ship", "max_men_per_ship", "has_spoken_vo", "vo_is_dragon", "vo_is_dinosaur", "audio_voiceover_culture",
    "audio_voiceover_culture_override", "audio_voiceover_actor_group",
]

# Vanilla main units that are copies of a creature for another faction or event, never the canonical unit.
NON_CANONICAL_MAIN_UNIT = re.compile(r"nur_chieftain|throgg|summoned|_ror|boss|_qb|pro0|monst_arcanum")

Row = Dict[str, str]
Changes = Dict[str, Tuple[str, str]]


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# TSV reading and writing


def read_tsv(path: str) -> Tuple[List[str], str, List[Row]]:
    """Read an RPFM TSV into its header, its `#table;version;path` metadata line, and its rows.

    Args:
        path (str): Path to the TSV file.

    Returns:
        Tuple[List[str], str, List[Row]]: The column names, the raw metadata line, and one dict per data row.
    """
    with open(path, encoding="utf-8", newline="") as f:
        lines = f.read().split("\n")
    header = lines[0].split("\t")
    rows = [dict(zip(header, line.split("\t"))) for line in lines[2:] if line]
    return header, lines[1], rows


def write_tsv(path: str, header: List[str], meta: str, rows: List[Row]) -> None:
    """Write rows back as an RPFM TSV with LF line endings and a trailing newline.

    Args:
        path (str): Path to the TSV file.
        header (List[str]): Column names in file order.
        meta (str): The raw metadata line.
        rows (List[Row]): Rows to write, one dict per row.
    """
    lines = ["\t".join(header), meta] + ["\t".join(row[column] for column in header) for row in rows]
    with open(path, "w", encoding="utf-8", newline="") as f:
        f.write("\n".join(lines) + "\n")


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Row syncing


def sync_land_unit_row(mod_row: Row, vanilla_row: Row, keep: Set[str]) -> Tuple[Row, Changes]:
    """Copy every vanilla land unit column onto a scroll unit, except its key and the kept columns.

    Args:
        mod_row (Row): The scroll's land unit row.
        vanilla_row (Row): The vanilla source's land unit row.
        keep (Set[str]): Columns the scroll keeps.

    Returns:
        Tuple[Row, Changes]: The synced row, and each changed column mapped to its old and new value.
    """
    return _copy_columns(mod_row, vanilla_row, [column for column in mod_row if column != "key" and column not in keep])


def sync_main_unit_row(mod_row: Row, vanilla_row: Row, keep: Set[str]) -> Tuple[Row, Changes]:
    """Copy the `MAIN_UNIT_SYNC_COLUMNS` of a vanilla main unit onto a scroll's main unit, except the kept columns.

    Args:
        mod_row (Row): The scroll's main unit row.
        vanilla_row (Row): The vanilla source's main unit row.
        keep (Set[str]): Columns the scroll keeps.

    Returns:
        Tuple[Row, Changes]: The synced row, and each changed column mapped to its old and new value.
    """
    return _copy_columns(mod_row, vanilla_row, [column for column in MAIN_UNIT_SYNC_COLUMNS if column in mod_row and column not in keep])


def _copy_columns(mod_row: Row, vanilla_row: Row, columns: List[str]) -> Tuple[Row, Changes]:
    """Copy the given columns from a vanilla row onto a copy of the mod row.

    Args:
        mod_row (Row): Row to copy onto.
        vanilla_row (Row): Row to copy from. Columns it lacks are left alone.
        columns (List[str]): Columns to copy.

    Returns:
        Tuple[Row, Changes]: The new row, and each changed column mapped to its old and new value.
    """
    row = dict(mod_row)
    changes = {}
    for column in columns:
        if column in vanilla_row and vanilla_row[column] != row[column]:
            changes[column] = (row[column], vanilla_row[column])
            row[column] = vanilla_row[column]
    return row, changes


def pick_main_unit(source_land_unit: str, main_rows: List[Row]) -> Optional[Row]:
    """Find the canonical vanilla main unit for a land unit.

    Prefers the main unit with the same key. Otherwise takes the only candidate that is not an event or faction copy.

    Args:
        source_land_unit (str): Vanilla land unit key.
        main_rows (List[Row]): Every vanilla main unit row.

    Returns:
        Optional[Row]: The main unit row, or None when there is no clear canonical one.
    """
    candidates = [row for row in main_rows if row["land_unit"] == source_land_unit]
    for row in candidates:
        if row["unit"] == source_land_unit:
            return row
    clean = [row for row in candidates if not NON_CANONICAL_MAIN_UNIT.search(row["unit"])]
    return clean[0] if len(clean) == 1 else None


def sync_ability_rows(mod_rows: List[Row], vanilla_by_land_unit: Dict[str, List[Row]], sources: Dict[str, str]) -> List[Row]:
    """Rebuild the ability junction rows so each mapped scroll unit has its vanilla source's abilities plus the mod's own `kadon_*` ones.

    Units not in `sources` keep their rows untouched. Mapped units are rebuilt where their first row sat, and mapped units with no rows yet
    are appended at the end.

    Args:
        mod_rows (List[Row]): The junction rows in file order.
        vanilla_by_land_unit (Dict[str, List[Row]]): Vanilla junction rows grouped by vanilla land unit.
        sources (Dict[str, str]): Scroll land unit to vanilla land unit, limited to the units in this file.

    Returns:
        List[Row]: The new junction rows.
    """
    rows = []
    done = set()
    for row in mod_rows:
        unit = row["land_unit"]
        if unit not in sources:
            rows.append(row)
        elif unit not in done:
            rows.extend(_unit_ability_rows(unit, mod_rows, vanilla_by_land_unit.get(sources[unit], [])))
            done.add(unit)
    for unit, source in sources.items():
        if unit not in done:
            rows.extend(_unit_ability_rows(unit, mod_rows, vanilla_by_land_unit.get(source, [])))
    return rows


def _unit_ability_rows(unit: str, mod_rows: List[Row], vanilla_rows: List[Row]) -> List[Row]:
    """Build one scroll unit's junction rows: its `kadon_*` rows first, then its vanilla source's rows.

    Args:
        unit (str): Scroll land unit key.
        mod_rows (List[Row]): Every junction row in the mod file.
        vanilla_rows (List[Row]): The vanilla source's junction rows.

    Returns:
        List[Row]: The unit's rows.
    """
    kept = [row for row in mod_rows if row["land_unit"] == unit and row["ability"].startswith("kadon_")]
    return kept + [{**row, "land_unit": unit} for row in vanilla_rows]


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Sync


def load_vanilla(table_name: str) -> List[Row]:
    """Extract a vanilla table from the game's `db.pack` and read its rows.

    Args:
        table_name (str): Table folder name, e.g. `land_units_tables`.

    Returns:
        List[Row]: The vanilla rows.
    """
    folder = extract_tsv_data(table_name)
    return read_tsv(os.path.join(folder, "db", table_name, "data__.tsv"))[2]


def sync(dry_run: bool) -> int:
    """Sync every mapped scroll unit with its vanilla source and log each change.

    Args:
        dry_run (bool): Log the changes without writing any file.

    Returns:
        int: Number of changed values, counting each added or removed ability row as one.
    """
    vanilla_land = {row["key"]: row for row in load_vanilla("land_units_tables")}
    vanilla_main = load_vanilla("main_units_tables")
    vanilla_abilities: Dict[str, List[Row]] = {}
    for row in load_vanilla("land_units_to_unit_abilites_junctions_tables"):
        vanilla_abilities.setdefault(row["land_unit"], []).append(row)

    total = 0
    for kind in SCROLL_KINDS:
        land_path = os.path.join(MOD_DB, "land_units_tables", f"jvj_kadon_{kind}.tsv")
        header, meta, land_rows = read_tsv(land_path)
        file_sources = {row["key"]: KADON_SOURCES[row["key"]] for row in land_rows if row["key"] in KADON_SOURCES}
        synced = []
        for row in land_rows:
            if row["key"] in file_sources:
                row, changes = sync_land_unit_row(row, vanilla_land[file_sources[row["key"]]], _keep(row["key"], "land_units"))
                total += _log_changes("land_units", row["key"], changes)
            synced.append(row)
        if not dry_run:
            write_tsv(land_path, header, meta, synced)

        main_path = os.path.join(MOD_DB, "main_units_tables", f"jvj_kadon_{kind}.tsv")
        header, meta, main_rows = read_tsv(main_path)
        synced = []
        for row in main_rows:
            source = file_sources.get(row["land_unit"])
            vanilla_row = pick_main_unit(source, vanilla_main) if source else None
            if source and vanilla_row is None:
                logging.warning(f"No canonical vanilla main unit for {source}, leaving {row['unit']} unchanged.")
            if vanilla_row:
                row, changes = sync_main_unit_row(row, vanilla_row, _keep(row["land_unit"], "main_units"))
                total += _log_changes("main_units", row["unit"], changes)
            synced.append(row)
        if not dry_run:
            write_tsv(main_path, header, meta, synced)

        ability_path = os.path.join(MOD_DB, "land_units_to_unit_abilites_junctions_tables", f"jvj_kadon_{kind}.tsv")
        header, meta, ability_rows = read_tsv(ability_path)
        new_rows = sync_ability_rows(ability_rows, vanilla_abilities, file_sources)
        old_pairs = {(row["land_unit"], row["ability"]) for row in ability_rows}
        new_pairs = {(row["land_unit"], row["ability"]) for row in new_rows}
        for unit, ability in sorted(new_pairs - old_pairs):
            logging.info(f"abilities {unit}: + {ability}")
        for unit, ability in sorted(old_pairs - new_pairs):
            logging.info(f"abilities {unit}: - {ability}")
        total += len(new_pairs ^ old_pairs)
        if not dry_run:
            write_tsv(ability_path, header, meta, new_rows)

    logging.info(f"{total} change(s){' (dry run, nothing written)' if dry_run else ''}.")
    return total


def _keep(unit: str, table: str) -> Set[str]:
    """Return the columns a scroll unit keeps in a table.

    Args:
        unit (str): Scroll land unit key.
        table (str): `land_units` or `main_units`.

    Returns:
        Set[str]: The kept columns, possibly empty.
    """
    return KADON_KEEP_COLUMNS.get(unit, {}).get(table, set())


def _log_changes(table: str, unit: str, changes: Changes) -> int:
    """Log one line per changed column.

    Args:
        table (str): Table name for the log line.
        unit (str): Unit key for the log line.
        changes (Changes): Changed columns with their old and new values.

    Returns:
        int: Number of changed columns.
    """
    for column, (old, new) in changes.items():
        logging.info(f"{table} {unit}: {column} {old} -> {new}")
    return len(changes)


def main() -> int:
    """Parse arguments and run the sync.

    Returns:
        int: Process exit code.
    """
    parser = argparse.ArgumentParser(description="Copy current vanilla values onto the Kadon scroll units.")
    parser.add_argument("--dry-run", action="store_true", help="Log the changes without writing any file.")
    args = parser.parse_args()
    setup_script_logging()
    sync(args.dry_run)
    return 0


if __name__ == "__main__":
    sys.exit(main())
