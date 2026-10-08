"""Free army versions of lore spells, made the way CA makes its own (e.g. wh3_dlc27_army_high_magic_tempest): a copy of the spell's ability with
set uses, a 60 second initial recharge and no Winds of Magic cost, the stronger upgraded phases when the spell has them, marked as an army
ability, and the original's targeting and UI tags. The copies leave out the lore groups, so lore cost effects do not touch them. Their names
point at the original's text.

The vanilla rows each copy is made from are kept in leapoi_free_spells.json. Refresh it after adding a spell, from a folder of vanilla TSVs
extracted with rpfm_cli (`db/<table>/data__.tsv`):

    python -m generators.leapoi_free_spells <folder>
"""

import json
import os
import sys
from typing import Dict, List, Tuple

from core.utilities import load_tsv_data

# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Spells

# Where the vanilla rows of the copied spells are kept.
DATA = os.path.join(os.path.dirname(os.path.abspath(__file__)), "leapoi_free_spells.json")

# Prefix of every free spell's ability key. The spell's name follows.
KEY_PREFIX = "land_enc_lib_free_"

# Free spell name -> (vanilla spell ability, uses per battle, unique id of the copy, name in text).
FREE_SPELLS: Dict[str, Tuple[str, int, str, str]] = {
    "blizzard": ("wh3_main_spell_tempest_blizzard", 2, "1700182001", "Blizzard"),
}

# Tables a copy takes rows from, and the column that names the ability in each.
COPIED: Dict[str, str] = {
    "unit_special_abilities_tables": "key",
    "unit_abilities_tables": "key",
    "special_ability_to_special_ability_phase_junctions_tables": "special_ability",
    "special_ability_to_invalid_target_flags_tables": "special_ability",
    "unit_abilities_to_additional_ui_effects_juncs_tables": "ability",
}

# Columns a copy changes in unit_special_abilities and unit_abilities, as CA's army versions do. "{uses}" and "{unique_id}" are the spell's.
CHANGED: Dict[str, Dict[str, str]] = {
    "unit_special_abilities_tables": {"num_uses": "{uses}", "initial_recharge": "60.0000", "target_intercept_range": "-1.0000", "unique_id": "{unique_id}",
                                      "mana_cost": "0.0000"},
    "unit_abilities_tables": {"overpower_option": "", "source_type": "army"},
}


def key(name: str) -> str:
    """The ability key of a free spell.

    Args:
        name (str): The FREE_SPELLS name.

    Returns:
        str: The key, e.g. land_enc_lib_free_blizzard.
    """
    return KEY_PREFIX + name


def sources(name: str) -> List[str]:
    """The vanilla abilities a free spell copies from: the spell, and its upgraded version, whose phases the copy uses when it has one.

    Args:
        name (str): The FREE_SPELLS name.

    Returns:
        List[str]: The ability keys.
    """
    return [FREE_SPELLS[name][0], FREE_SPELLS[name][0] + "_upgraded"]


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Rows

def rows() -> List[Tuple[str, Tuple]]:
    """The DB rows of every free spell.

    Returns:
        List[Tuple[str, Tuple]]: (table, fields) per row.
    """
    data = json.load(open(DATA, encoding="utf-8"))
    out = []
    for name, (_, uses, unique_id, _) in FREE_SPELLS.items():
        source, upgraded = sources(name)
        for table, column in COPIED.items():
            header, kept = data[table]["header"], data[table]["rows"]
            index = header.index(column)
            phases = table == "special_ability_to_special_ability_phase_junctions_tables" and kept.get(upgraded)
            picked = phases or kept.get(source, [])
            for row in picked:
                row = list(row)
                row[index] = key(name)
                for changed, value in CHANGED.get(table, {}).items():
                    row[header.index(changed)] = value.format(uses=uses, unique_id=unique_id)
                out.append((table, tuple(row)))
    return out


def texts() -> List[Tuple[str, str, str]]:
    """The loc rows of every free spell: its name and tooltip, pointing at the original's.

    Returns:
        List[Tuple[str, str, str]]: (loc file name without ".loc", key, text) per row.
    """
    out = []
    for name, (source, _, _, _) in FREE_SPELLS.items():
        for field in ("onscreen_name", "tooltip_text"):
            out.append(("unit_abilities", f"unit_abilities_{field}_{key(name)}", f"{{{{tr:unit_abilities_{field}_{source}}}}}"))
    return out


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Refresh

def refresh(folder: str) -> None:
    """Keeps the vanilla rows every free spell copies from, read from extracted vanilla TSVs.

    Args:
        folder (str): The folder holding `db/<table>/data__.tsv`.
    """
    wanted = {source for name in FREE_SPELLS for source in sources(name)}
    data = {}
    for table, column in COPIED.items():
        records, header, version = load_tsv_data(os.path.join(folder, "db", table, "data__.tsv"))
        kept: Dict[str, List[List[str]]] = {}
        for record in records:
            if record.get(column) in wanted:
                kept.setdefault(record[column], []).append([record.get(field, "") for field in header])
        data[table] = {"header": header, "version": version.split("	"), "rows": kept}
    json.dump(data, open(DATA, "w", encoding="utf-8"), indent=1, sort_keys=True)
    print(f"kept rows for {len(wanted)} abilities in {DATA}")


if __name__ == "__main__":
    refresh(sys.argv[1])
