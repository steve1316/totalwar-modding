"""Builds the Addvisor Overhaul (`!!pj_advisor_overhaul`) skill tree on top of Prop Joe's Addvisor (Workshop 2795714008).

Every standalone vanilla lore becomes two skills: a first lore on row 3 and a second lore on row 4 that opens at rank 14. Each lore skill has three
levels. Level 1 gives the spells at vanilla cost, level 2 adds overcast, and level 3 makes them cheaper and faster to recharge. Every lore locks every
other lore on its row and its own twin on the other row, and the advisor's units are linked to every lore group so the battle lore switch shows.

The pack replaces the base mod's skill tree files by using the same file paths, the way Path of Doubt (3065001847) did. Each lore's effect file uses
the name Path of Doubt gave it, so having that mod enabled at the same time adds nothing.

The vanilla lore rows are kept in pj_advisor_overhaul.json. Refresh it after a game patch from a folder of vanilla TSVs (`<table>/data__.tsv`):

    python -m generators.pj_advisor_overhaul --refresh _diag/vanilla_all/db

Build the mod's TSVs (reads the subscribed base Addvisor pack):

    python -m generators.pj_advisor_overhaul
"""

import argparse
import collections
import glob
import json
import os
import shutil
import sys
from typing import Dict, List, Set, Tuple

from core.extract_cache import cached_pack_extract
from core.utilities import STEAM_LIBRARY_DRIVE, load_tsv_data

# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Settings

# Where the vanilla lore rows are kept.
DATA = os.path.join(os.path.dirname(os.path.abspath(__file__)), "pj_advisor_overhaul.json")

# The subscribed base Addvisor pack.
BASE_PACK = f"{STEAM_LIBRARY_DRIVE}\\SteamLibrary\\steamapps\\workshop\\content\\1142710\\2795714008\\pj_advisor.pack"

# Where the base pack is extracted to while building.
BASE_EXTRACT = "./temp/pj_advisor_base"

# The mod source folder the TSVs are written to.
MOD = "../warhammer3_mods/!!pj_advisor_overhaul"

# File name of every table this mod writes. It matches the base mod's, so ours replaces it.
FILE = "pj_advisor"

# The advisor's land units that get the lore groups.
UNITS = ["pj_advisor", "pj_advisor_mount_warhorse"]

# Lore groups that are not shared lores. Kroak's is his alone. Groups with no spell enable effects (Kemmler, Cataclysm) are skipped on their own.
EXCLUDED_GROUPS = {"wh2_dlc12_lore_lord_kroak"}

# Lore group -> the skill key suffix the base mod or Path of Doubt already used, so old saves keep their lores. Other lores use the group's own name.
OLD_SUFFIXES = {
    "wh_main_lore_death": "death",
    "wh_main_lore_fire": "fire",
    "wh_main_lore_heavens": "heavens",
    "wh_dlc05_lore_life": "life",
    "wh_main_lore_light": "light",
    "wh_dlc05_lore_shadows": "shadows",
    "wh_dlc03_lore_beasts": "beasts",
    "wh_main_lore_metal": "metal",
    "wh3_main_lore_tzeentch": "tzeench",
    "wh3_main_lore_slaanesh": "slaneesh",
    "wh3_main_lore_nurgle": "nurgle",
    "wh2_main_lore_dark_magic": "Ghrond",
    "wh2_main_lore_high_magic": "high_magic",
    "wh2_main_lore_ruin": "skaven",
    "wh_main_lore_vampires": "vampire",
}

# Skill icons for the lores whose group icon has no skill-sized copy in ui/campaign ui/skills/.
ICON_OVERRIDES = {
    "wh2_dlc09_lore_nehekhara": "wh2_dlc09_lore_nehekhara.png",
    "wh2_dlc11_lore_deep": "wh2_dlc11_lore_deeps.png",
    "wh2_dlc14_lore_stealth": "wh2_dlc14_skill_all_magic_stealth_02_toxic_rain_lore_attribute.png",
}

# Skill tree rows of the first and second lore.
FIRST_ROW = 3
SECOND_ROW = 4

# Rank each level of a lore skill opens at, for the first and the second lore.
FIRST_RANKS = {1: 0, 2: 8, 3: 16}
SECOND_RANKS = {1: 14, 2: 20, 3: 26}

# Level 3 mastery: Winds of Magic cost change per spell, and cooldown change in percent.
MASTERY_COST = -1
MASTERY_COOLDOWN = -25

# Scope of every lore effect.
SCOPE = "character_to_character_own"

# The effect file of every second-lore skill. The base mod uses the same name, so ours replaces it.
SECOND_EFFECT_FILE = "pj_advisor_second"

# The effects junction table. Unlike the others it is spread over many files.
EFFECT_TABLE = "character_skill_level_to_effects_junctions_tables"

# Tables written in full (base rows kept, lore rows rebuilt). Their header and version come from the vanilla dump the refresh read.
WRITTEN_TABLES = [
    "character_skills_tables",
    "character_skill_nodes_tables",
    "character_skill_node_set_items_tables",
    "character_skill_nodes_skill_locks_tables",
    "character_skill_level_details_tables",
    "special_ability_groups_to_units_junctions_tables",
    EFFECT_TABLE,
]

# Table -> the column naming the skill, for the tables whose base lore rows are dropped by skill.
SKILL_COLUMNS = {
    "character_skills_tables": "key",
    "character_skill_nodes_tables": "character_skill_key",
    "character_skill_nodes_skill_locks_tables": "character_skill",
    "character_skill_level_details_tables": "skill_key",
}


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Refresh

def refresh(folder: str) -> None:
    """Keeps every standalone lore's spells and effects, read from extracted vanilla TSVs.

    An effect belongs to a lore when it touches one of the lore's spells and nothing else but that spell's upgraded version. That skips whole-lore
    effects, which would stack with the per-spell ones, and effects shared with other abilities, such as the Blue Scribes ones. The headers and
    versions of the written tables are kept too, so the output matches the schema of the game the refresh read.

    Args:
        folder (str): The folder holding `<table>/data__.tsv`.
    """
    def read(table: str) -> List[Dict[str, str]]:
        return load_tsv_data(os.path.join(folder, table, "data__.tsv"))[0]

    groups = [g for g in read("special_ability_groups_tables")
              if g["is_composite_group"] == "false" and g["show_lore_icon"] == "true" and g["ability_group"] not in EXCLUDED_GROUPS]
    spells = collections.defaultdict(list)
    for row in read("special_ability_groups_to_unit_abilities_junctions_tables"):
        spells[row["special_ability_groups"]].append(row["unit_special_abilities"])
    touched: Dict[str, Set[str]] = collections.defaultdict(set)
    bonuses: Dict[str, Set[str]] = collections.defaultdict(set)
    for row in read("effect_bonus_value_unit_ability_junctions_tables"):
        touched[row["effect"]].add(row["unit_ability"])
        bonuses[row["effect"]].add(row["bonus_value_id"])

    # Effect -> the one spell it belongs to, counting a spell's upgraded version as the spell. Effects touching several spells are left out.
    owner: Dict[str, str] = {}
    for effect, abilities in touched.items():
        spell = {ability.removesuffix("_upgraded") for ability in abilities}
        if len(spell) == 1:
            owner[effect] = spell.pop()

    lores = {}
    for group in groups:
        key = group["ability_group"]
        base = set(spells[key])
        effects = {"enable": set(), "overcast": set(), "cost": set(), "cooldown": set()}
        for effect, spell in owner.items():
            if spell not in base:
                continue
            if "enable_overchage" in bonuses[effect]:
                effects["overcast"].add(effect)
            elif bonuses[effect] == {"enable"} and touched[effect] == {spell}:
                effects["enable"].add(effect)
            elif bonuses[effect] == {"cost_mod"}:
                effects["cost"].add(effect)
            elif bonuses[effect] == {"recharge_mod"}:
                effects["cooldown"].add(effect)
        if not effects["enable"]:
            print(f"skipped {key}: no spell enable effects")
            continue
        icon = ICON_OVERRIDES.get(key, group["icon_path"].replace("\\", "/").split("/")[-1])
        lores[key] = {"sort": int(group["sort_order"]), "icon": icon, "spells": spells[key], "effects": {k: sorted(v) for k, v in effects.items()}}

    tables = {}
    for table in WRITTEN_TABLES:
        _, header, version = load_tsv_data(os.path.join(folder, table, "data__.tsv"))
        tables[table] = {"header": header, "version": version.split("\t")[0].split(";")[1]}
    json.dump({"lores": lores, "tables": tables}, open(DATA, "w", encoding="utf-8"), indent=1, sort_keys=True)
    print(f"kept {len(lores)} lores in {DATA}")


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Lores

def suffix(group: str) -> str:
    """The skill key suffix of a lore.

    Args:
        group (str): The lore's ability group key.

    Returns:
        str: The old suffix when the base mod or Path of Doubt had the lore, else the group key without its `wh*_` prefix.
    """
    if group in OLD_SUFFIXES:
        return OLD_SUFFIXES[group]
    return group.split("_", 2)[2].replace("lore_of_", "").replace("lore_", "")


def lore_name(group: str) -> str:
    """The vanilla name of a lore, as a `{{tr:}}` reference so it follows the game's language.

    Args:
        group (str): The lore's ability group key.

    Returns:
        str: The loc reference.
    """
    return f"{{{{tr:special_ability_groups_name_{group}}}}}"


def level_effects(lore: Dict, level: int) -> List[Tuple[str, str]]:
    """The effects a lore skill gives at a level. Each level lists all of its effects, since levels replace each other.

    Args:
        lore (Dict): The kept lore.
        level (int): 1, 2 or 3.

    Returns:
        List[Tuple[str, str]]: (effect, value) pairs.
    """
    effects = lore["effects"]
    out = [(e, "1.0000") for e in effects["enable"]]
    if level >= 2:
        out += [(e, "1.0000") for e in effects["overcast"]]
    if level >= 3:
        out += [(e, f"{MASTERY_COST:.4f}") for e in effects["cost"]]
        out += [(e, f"{MASTERY_COOLDOWN:.4f}") for e in effects["cooldown"]]
    return out


def describe(group: str, second: bool) -> str:
    """The skill description of a lore.

    Args:
        group (str): The lore's ability group key.
        second (bool): True for the second-lore skill.

    Returns:
        str: The loc text.
    """
    lore = lore_name(group)
    if second:
        first = f"The Advisor masters a second school of magic and learns the spells of the {lore}. It cannot be the lore he chose first."
    else:
        first = f"The Advisor chooses his first school of magic and learns the spells of the {lore}. Taking it closes every other first lore."
    lines = [
        first,
        "",
        "Level 1: learn the lore's spells at their normal cost.",
        "Level 2: the spells can be overcast.",
        f"Level 3: the spells cost {-MASTERY_COST} less Winds of Magic and recharge {-MASTERY_COOLDOWN}% faster.",
    ]
    return "\\\\n".join(lines)


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Build

def base_rows(path: str, header: List[str]) -> List[Dict[str, str]]:
    """The rows of one base mod table file, fitted to the current header.

    Args:
        path (str): The extracted TSV file.
        header (List[str]): The current header. Columns the base file lacks are left empty.

    Returns:
        List[Dict[str, str]]: The rows, or none when the file does not exist.
    """
    if not os.path.exists(path):
        return []
    return [{column: row.get(column, "") for column in header} for row in load_tsv_data(path)[0]]


def read_base(specs: Dict[str, Dict]) -> Dict[str, Dict[str, List[Dict[str, str]]]]:
    """Reads every written table from the base Addvisor pack.

    Args:
        specs (Dict[str, Dict]): The kept header and version of each table.

    Returns:
        Dict[str, Dict[str, List[Dict[str, str]]]]: Table -> file name -> rows.

    Raises:
        SystemExit: When the base pack is not subscribed.
    """
    if not os.path.exists(BASE_PACK):
        raise SystemExit(f"base Addvisor pack not found at {BASE_PACK}")
    shutil.rmtree(BASE_EXTRACT, ignore_errors=True)
    try:
        cached_pack_extract(BASE_PACK, "db", BASE_EXTRACT)
        return {table: {os.path.basename(path)[:-4]: base_rows(path, specs[table]["header"]) for path in glob.glob(os.path.join(BASE_EXTRACT, "db", table, "*.tsv"))}
                for table in WRITTEN_TABLES}
    finally:
        shutil.rmtree(BASE_EXTRACT, ignore_errors=True)


def write(table: str, file: str, rows: List[Dict[str, str]], spec: Dict) -> None:
    """Writes one table file of the mod.

    Args:
        table (str): The table name.
        file (str): The file name without `.tsv`.
        rows (List[Dict[str, str]]): The rows.
        spec (Dict): The table's kept header and version.
    """
    folder = os.path.join(MOD, "db", table)
    os.makedirs(folder, exist_ok=True)
    header = spec["header"]
    lines = ["\t".join(header), "\t".join([f"#{table};{spec['version']};db/{table}/{file}"] + [""] * (len(header) - 1))]
    lines += ["\t".join(row.get(column, "") for column in header) for row in rows]
    with open(os.path.join(folder, f"{file}.tsv"), "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")


def build() -> None:
    """Writes every lore table and the loc file into the mod folder."""
    data = json.load(open(DATA, encoding="utf-8"))
    lores, specs = data["lores"], data["tables"]
    order = sorted(lores, key=lambda g: (lores[g]["sort"], g))
    base = read_base(specs)
    rows = {table: base[table].get(FILE, []) for table in WRITTEN_TABLES if table != EFFECT_TABLE}

    # Drop every base skill that enables a lore's spells, with its nodes, locks, levels and effects. Ours replace them.
    lore_enables = {e for lore in lores.values() for e in lore["effects"]["enable"]}
    dropped = {r["character_skill_key"] for file_rows in base[EFFECT_TABLE].values() for r in file_rows if r["effect_key"] in lore_enables}
    dropped_nodes = {r["key"] for r in rows["character_skill_nodes_tables"] if r["character_skill_key"] in dropped}
    for table, column in SKILL_COLUMNS.items():
        rows[table] = [r for r in rows[table] if r[column] not in dropped]
    rows["character_skill_node_set_items_tables"] = [r for r in rows["character_skill_node_set_items_tables"] if r["item"] not in dropped_nodes]
    rows["special_ability_groups_to_units_junctions_tables"] = []
    effects = {file: [r for r in file_rows if r["character_skill_key"] not in dropped] for file, file_rows in base[EFFECT_TABLE].items()}

    texts: List[Tuple[str, str]] = []
    nodes = {g: (f"pj_advisor_lore_{suffix(g)}", f"pj_advisor_lore_{suffix(g)}_2") for g in order}

    for tier, group in enumerate(order):
        lore, name = lores[group], suffix(group)
        for twin in (0, 1):
            skill = f"pj_advisor_{name}" + ("_2" if twin else "")
            ranks = SECOND_RANKS if twin else FIRST_RANKS
            file = SECOND_EFFECT_FILE if twin else f"pj_advisor_{name}"
            rows["character_skills_tables"].append({
                "key": skill, "image_path": lore["icon"], "localised_description": "", "localised_name": "", "unlocked_at_rank": "0",
                "is_background_skill": "false", "is_female_only_background_skill": "false", "is_male_only_background_skill": "false",
                "background_weighting": "0.0000", "influence_cost": "0",
            })
            rows["character_skill_nodes_tables"].append({
                "key": nodes[group][twin], "campaign_key": "", "character_skill_key": skill, "faction_key": "", "indent": str(SECOND_ROW if twin else FIRST_ROW),
                "tier": str(tier), "subculture": "", "points_on_creation": "0", "required_num_parents": "0", "visible_in_ui": "true",
            })
            rows["character_skill_node_set_items_tables"].append({"set": FILE, "item": nodes[group][twin], "mod_disabled": "false"})
            for level, rank in ranks.items():
                rows["character_skill_level_details_tables"].append({
                    "campaign_key": "", "faction_key": "", "level": str(level), "skill_key": skill, "subculture_key": "", "image_path": "x",
                    "unlocked_at_rank": str(rank),
                })
                for effect, value in level_effects(lore, level):
                    effects.setdefault(file, []).append({"character_skill_key": skill, "effect_key": effect, "level": str(level), "effect_scope": SCOPE, "value": value})

            # Locks: every other lore on this row, and this lore's twin on the other row.
            for target in [nodes[other][twin] for other in order if other != group] + [nodes[group][1 - twin]]:
                rows["character_skill_nodes_skill_locks_tables"].append({"character_skill": skill, "character_skill_node": target, "level": "1"})

            texts.append((f"character_skills_localised_name_{skill}", lore_name(group) + (" (Second Lore)" if twin else "")))
            texts.append((f"character_skills_localised_description_{skill}", describe(group, bool(twin))))

        for unit in UNITS:
            rows["special_ability_groups_to_units_junctions_tables"].append({"ability_group": group, "unit": unit, "group_page_order": str(tier)})

    for table, table_rows in rows.items():
        write(table, FILE, table_rows, specs[table])
    for file, file_rows in sorted(effects.items()):
        write(EFFECT_TABLE, file, file_rows, specs[EFFECT_TABLE])

    loc_folder = os.path.join(MOD, "text", "db")
    os.makedirs(loc_folder, exist_ok=True)
    with open(os.path.join(loc_folder, "!!pj_advisor_overhaul.loc.tsv"), "w", encoding="utf-8", newline="\n") as f:
        f.write("key\ttext\ttooltip\n#Loc;1;text/db/!!pj_advisor_overhaul.loc\t\t\n")
        f.write("".join(f"{key}\t{text}\ttrue\n" for key, text in texts))
    print(f"wrote {len(order)} lores ({len(order) * 2} skills), dropped {len(dropped)} base lore skills, to {MOD}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--refresh", metavar="FOLDER", help="refresh the kept vanilla lore rows from a folder of vanilla TSVs")
    args = parser.parse_args()
    if args.refresh:
        refresh(args.refresh)
    else:
        build()
    sys.exit(0)
