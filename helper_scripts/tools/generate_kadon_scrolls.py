"""Generate a Kin and a Binding scroll for every vanilla creature listed in `data/kadon_new_creatures.py`.

Usage:
    cd helper_scripts && python -m tools.generate_kadon_scrolls [--dry-run]

The hand-made Hydra scrolls are the template for every scroll-level row (item, effect, summon ability, UI effect). The summoned unit itself is
copied from vanilla, the same way `tools/sync_kadon_units.py` keeps the hand-made scrolls current. All output goes to `jvj_kadon_generated_*`
files that are rewritten on every run, so the hand-made scrolls are never touched.
"""

import argparse
import logging
import os
import re
import sys
from typing import Dict, List, Optional, Set, Tuple

from core.extract_cache import cached_pack_extract
from core.utilities import STEAM_LIBRARY_DRIVE, TEMP_DIR, ensure_temp_dir, setup_script_logging
from data.kadon_new_creatures import KADON_NEW_CREATURES
from tools.sync_kadon_units import MOD_DB, load_vanilla, read_tsv, sync_land_unit_row, write_tsv

MOD_ROOT = "../warhammer3_mods/jvj_kadon_6_0"
CREATURES_LUA = f"{MOD_ROOT}/script/jvj_kadon/creatures.lua"
GENERATED_LUA = f"{MOD_ROOT}/script/jvj_kadon/creatures_generated.lua"
GENERATED_LOC = f"{MOD_ROOT}/text/jvj_kadon_generated.loc.tsv"
LOCAL_EN_PACK = f"{STEAM_LIBRARY_DRIVE}\\SteamLibrary\\steamapps\\common\\Total War WARHAMMER III\\data\\local_en.pack"

# Hand-made creature every generated scroll copies its scroll-level rows from.
TEMPLATE_ID = "hydra"

# Scroll kinds: file suffix, key prefix, and the name used in scroll titles.
KINDS = [("binding", "bind", "Binding"), ("kinship", "kin", "Kin")]

# Tables whose rows are copied from the template scroll with its keys swapped.
SCROLL_TABLES = [
    "ancillaries_tables", "ancillary_info_tables", "ancillary_to_effects_tables", "ancillary_to_included_agents_tables", "effects_tables",
    "effect_bonus_value_unit_ability_junctions_tables", "unit_abilities_tables", "unit_special_abilities_tables",
    "unit_abilities_to_additional_ui_effects_juncs_tables", "ui_unit_bullet_point_unit_overrides_tables",
]

# Tables whose rows describe the summoned unit and come from vanilla.
UNIT_TABLES = ["land_units_tables", "main_units_tables", "land_units_to_unit_abilites_junctions_tables", "unit_variants_tables"]

# UI effect table with one row per creature rather than per scroll.
UI_EFFECTS_TABLE = "unit_abilities_additional_ui_effects_tables"

# main_units values shared by every hand-made scroll. They replace the vanilla values on generated units.
KADON_MAIN_UNIT_CONSTANTS = {
    "additional_building_requirement": "", "is_naval": "false", "multiplayer_cap": "0", "naval_unit": "wh_main_shp_transport", "num_ships": "1",
    "min_men_per_ship": "1", "upkeep_cost": "0", "resource_requirement": "", "special_edition_mask": "0", "mount": "", "food_cost": "0",
    "optional_ui_element": "", "barrier_health": "0.0000", "can_be_bribed": "true", "point_allowance_weight": "1", "is_renown": "false",
}

# Summon abilities take unique ids from a block unused by vanilla and the hand-made scrolls.
UNIQUE_ID_BASE = 97000000
UNIQUE_ID_MAX = 97000999

Row = Dict[str, str]


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Rules


def summon_uses(main_row: Row) -> int:
    """Return how many times per battle a scroll can summon its creature: 2 for multi-model war beasts and packs of 24 or more models, else 1.

    Args:
        main_row (Row): The vanilla main unit row.

    Returns:
        int: 1 or 2.
    """
    num_men = int(main_row["num_men"])
    return 2 if num_men > 1 and (main_row["caste"] == "war_beast" or num_men >= 24) else 1


def spawn_proxy_vfx(num_men: int, flies: bool) -> str:
    """Return the pre-spawn targeting marker, matching the hand-made scrolls.

    Args:
        num_men (int): Models in the summoned unit.
        flies (bool): Whether the unit can fly.

    Returns:
        str: The `spawn_proxy_vfx` key.
    """
    if flies:
        return "wh_main_targeting_pre_spawn_solo_flying_ui_central"
    return "wh_main_targeting_pre_spawn_solo_ui_central" if num_men == 1 else "wh_main_targeting_pre_spawn_group_ui_central"


def unique_ids(index: int) -> Tuple[int, int]:
    """Return the Bind and Kin summon ability unique ids for the creature at `index` in the input list.

    Args:
        index (int): Position in `KADON_NEW_CREATURES`.

    Returns:
        Tuple[int, int]: The Bind id and the Kin id.
    """
    bind_id = UNIQUE_ID_BASE + 2 * index
    return bind_id, bind_id + 1


def summons_text(name: str, num_men: int) -> str:
    """Return the green "Summons ..." line shown on the scroll's ability.

    Args:
        name (str): Creature display name.
        num_men (int): Models in the summoned unit. Single models get "a" or "an".

    Returns:
        str: The localised text.
    """
    if num_men == 1:
        article = "an" if name[:1].lower() in "aeiou" else "a"
        return f"[[col:green]]Summons {article} {name}[[/col]]"
    return f"[[col:green]]Summons {name}[[/col]]"


def game_tag(main_unit_key: str) -> str:
    """Return the game a vanilla unit comes from, from its key prefix.

    Args:
        main_unit_key (str): Vanilla main unit key.

    Returns:
        str: "WH1", "WH2" or "WH3".
    """
    if main_unit_key.startswith("wh3_"):
        return "WH3"
    if main_unit_key.startswith("wh2_"):
        return "WH2"
    return "WH1"


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Row builders


def swap_cells(rows: List[Row], mapping: Dict[str, str]) -> List[Row]:
    """Copy rows, replacing every cell whose whole value is a key of `mapping`.

    Args:
        rows (List[Row]): Template rows.
        mapping (Dict[str, str]): Old cell value to new cell value.

    Returns:
        List[Row]: The new rows.
    """
    return [{column: mapping.get(value, value) for column, value in row.items()} for row in rows]


def build_main_unit_row(vanilla_row: Row, key: str, template: Optional[Row] = None) -> Row:
    """Build a scroll's main unit: the vanilla row with the scroll key and the Kadon constants.

    Args:
        vanilla_row (Row): The vanilla main unit row.
        key (str): Scroll key, used as both `unit` and `land_unit`.
        template (Optional[Row]): A hand-made main unit row. When given, the result has exactly its columns, so the file keeps its schema.

    Returns:
        Row: The main unit row.
    """
    row = dict(template) if template else {}
    row.update({column: value for column, value in vanilla_row.items() if template is None or column in template})
    row["unit"] = key
    row["land_unit"] = key
    row.update({column: value for column, value in KADON_MAIN_UNIT_CONSTANTS.items() if template is None or column in template or column in row})
    return row


def build_ability_rows(key: str, vanilla_rows: List[Row], is_bind: bool) -> List[Row]:
    """Build a scroll unit's passive ability rows: `kadon_bind_unbinding` first on Bind units, then the vanilla passives.

    Args:
        key (str): Scroll land unit key.
        vanilla_rows (List[Row]): The vanilla unit's junction rows.
        is_bind (bool): Whether this is the Binding scroll.

    Returns:
        List[Row]: The junction rows.
    """
    rows = [{"ability": "kadon_bind_unbinding", "land_unit": key, "culture": "*"}] if is_bind else []
    return rows + [{**row, "land_unit": key} for row in vanilla_rows]


def pick_unit_variant(main_unit_key: str, variant_rows: List[Row]) -> Optional[Row]:
    """Find a vanilla unit's model and unit card, preferring the row that applies to every faction.

    Args:
        main_unit_key (str): Vanilla main unit key.
        variant_rows (List[Row]): Every vanilla `unit_variants` row.

    Returns:
        Optional[Row]: The row, or None when the unit has none.
    """
    candidates = [row for row in variant_rows if row["unit"] == main_unit_key]
    factionless = [row for row in candidates if not row["faction"]]
    return (factionless or candidates or [None])[0]


def find_unit_variant(main_unit_key: str, main_units: Dict[str, Row], variant_rows: List[Row]) -> Optional[Row]:
    """Find a vanilla unit's model and unit card, falling back to its land unit key and then to main units that share its land unit.

    Some units reuse another faction's land unit (the Beastmen Basilisk uses the Chaos one), and vanilla stores the model under that unit. A few
    rows are keyed by the land unit itself (Exalted Flamer, Norscan Ice Wolves).

    Args:
        main_unit_key (str): Vanilla main unit key.
        main_units (Dict[str, Row]): Vanilla main units by key.
        variant_rows (List[Row]): Every vanilla `unit_variants` row.

    Returns:
        Optional[Row]: The row, or None when no unit sharing the land unit has one.
    """
    land_unit = main_units[main_unit_key]["land_unit"]
    siblings = sorted((key for key, row in main_units.items() if row["land_unit"] == land_unit and key != main_unit_key), key=lambda key: key != land_unit)
    for key in [main_unit_key, land_unit] + siblings:
        row = pick_unit_variant(key, variant_rows)
        if row:
            return row
    return None


def validate(creatures: List[Tuple[str, str, Optional[str]]], existing_ids: Set[str], main_units: Dict[str, Row], names: Dict[str, str],
             variants: Set[str], taken_unique_ids: Set[int]) -> List[str]:
    """Check the input list before anything is written.

    Args:
        creatures (List[Tuple[str, str, Optional[str]]]): The input list.
        existing_ids (Set[str]): Ids of the hand-made creatures.
        main_units (Dict[str, Row]): Vanilla main units by key.
        names (Dict[str, str]): Display name per vanilla main unit key.
        variants (Set[str]): Vanilla main unit keys that have a `unit_variants` row.
        taken_unique_ids (Set[int]): Summon ability unique ids already used by vanilla or the hand-made scrolls.

    Returns:
        List[str]: One message per problem, empty when the input is valid.
    """
    errors = []
    seen = set()
    for index, (cid, key, override) in enumerate(creatures):
        if cid in seen:
            errors.append(f"{cid}: duplicate creature id")
        seen.add(cid)
        if cid in existing_ids:
            errors.append(f"{cid}: id already used by a hand-made creature")
        if key not in main_units:
            errors.append(f"{cid}: vanilla main unit {key} not found")
            continue
        if not (override or names.get(key)):
            errors.append(f"{cid}: no display name for {key}")
        if key not in variants:
            errors.append(f"{cid}: no unit_variants row for {key}")
        for unique_id in unique_ids(index):
            if unique_id in taken_unique_ids:
                errors.append(f"{cid}: unique id {unique_id} is already taken")
            if unique_id > UNIQUE_ID_MAX:
                errors.append(f"{cid}: unique id {unique_id} is past {UNIQUE_ID_MAX}")
    return errors


def lua_creature_list(entries: List[Tuple[str, str, str]]) -> str:
    """Render the generated creature list as a Lua module.

    Args:
        entries (List[Tuple[str, str, str]]): (id, display name, game tag) per creature.

    Returns:
        str: The Lua source.
    """
    def quote(text: str) -> str:
        return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'

    lines = ["--- Generated by helper_scripts/tools/generate_kadon_scrolls.py from data/kadon_new_creatures.py. Do not edit by hand.", "", "return {"]
    lines += [f"    {{ id = {quote(cid)}, name = {quote(name)}, game = {quote(game)} }}," for cid, name, game in entries]
    return "\n".join(lines + ["}"]) + "\n"


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Generation


def _table_path(table: str, file_stem: str) -> str:
    """Return the path of a mod table file.

    Args:
        table (str): Table folder name.
        file_stem (str): File name without `.tsv`.

    Returns:
        str: The path.
    """
    return os.path.join(MOD_DB, table, f"{file_stem}.tsv")


def _generated_meta(meta: str, old_stem: str, new_stem: str) -> str:
    """Point a template metadata line at the generated file.

    Args:
        meta (str): Template metadata line, e.g. `#ancillaries_tables;0;db/ancillaries_tables/jvj_kadon_binding`.
        old_stem (str): Template file stem.
        new_stem (str): Generated file stem.

    Returns:
        str: The metadata line for the generated file.
    """
    return meta.replace(f"/{old_stem}", f"/{new_stem}", 1)


def _read_loc(path: str) -> Dict[str, str]:
    """Read a loc TSV into a key to text map.

    Args:
        path (str): Path to the loc TSV.

    Returns:
        Dict[str, str]: Text per loc key.
    """
    return {row["key"]: row["text"] for row in read_tsv(path)[2]}


def _load_vanilla_names() -> Dict[str, str]:
    """Extract vanilla English unit names from `local_en.pack`.

    Returns:
        Dict[str, str]: Display name per vanilla land unit key.
    """
    dest = f"{TEMP_DIR}/vanilla_land_units_loc"
    ensure_temp_dir()
    cached_pack_extract(LOCAL_EN_PACK, "text/db/land_units__.loc", dest, source_kind="file")
    prefix = "land_units_onscreen_name_"
    return {key[len(prefix):]: text for key, text in _read_loc(os.path.join(dest, "text", "db", "land_units__.loc.tsv")).items() if key.startswith(prefix)}


def _existing_creature_ids() -> Set[str]:
    """Read the hand-made creature ids from `creatures.lua`.

    Returns:
        Set[str]: The ids.
    """
    with open(CREATURES_LUA, encoding="utf-8") as f:
        return set(re.findall(r'^\s*creature\("([a-z0-9_]+)"', f.read(), re.MULTILINE))


def _unique_ids_in(path: str) -> Set[int]:
    """Read the summon ability unique ids from a `unit_special_abilities` TSV.

    Args:
        path (str): Path to the TSV.

    Returns:
        Set[int]: The ids.
    """
    return {int(row["unique_id"]) for row in read_tsv(path)[2] if row.get("unique_id")}


def generate(dry_run: bool) -> int:
    """Build every generated scroll and write the generated files.

    Args:
        dry_run (bool): Validate and log a summary without writing any file.

    Returns:
        int: Process exit code, 1 when validation fails.
    """
    main_units = {row["unit"]: row for row in load_vanilla("main_units_tables")}
    land_units = {row["key"]: row for row in load_vanilla("land_units_tables")}
    variant_rows = load_vanilla("unit_variants_tables")
    entities = {row["key"]: row for row in load_vanilla("battle_entities_tables")}
    vanilla_abilities: Dict[str, List[Row]] = {}
    for row in load_vanilla("land_units_to_unit_abilites_junctions_tables"):
        vanilla_abilities.setdefault(row["land_unit"], []).append(row)
    land_names = _load_vanilla_names()

    names = {key: land_names.get(row["land_unit"], "") for key, row in main_units.items()}
    taken = {int(row["unique_id"]) for row in load_vanilla("unit_special_abilities_tables") if row.get("unique_id")}
    for kind, _, _ in KINDS:
        taken |= _unique_ids_in(_table_path("unit_special_abilities_tables", f"jvj_kadon_{kind}"))
    variants = {key: find_unit_variant(key, main_units, variant_rows) for _, key, _ in KADON_NEW_CREATURES if key in main_units}
    errors = validate(KADON_NEW_CREATURES, _existing_creature_ids(), main_units, names, {key for key, row in variants.items() if row}, taken)
    if errors:
        for error in errors:
            logging.error(error)
        return 1

    loc_ancillaries = _read_loc(f"{MOD_ROOT}/text/jvj_kadon_ancillaries.loc.tsv")
    loc_abilities = _read_loc(f"{MOD_ROOT}/text/jvj_kadon_unit_abilities.loc.tsv")

    # Per table and kind: (header, meta, rows).
    outputs: Dict[Tuple[str, str], Tuple[List[str], str, List[Row]]] = {}
    templates: Dict[Tuple[str, str], List[Row]] = {}
    for table in SCROLL_TABLES + UNIT_TABLES:
        for kind, prefix, _ in KINDS:
            header, meta, rows = read_tsv(_table_path(table, f"jvj_kadon_{kind}"))
            template_key = f"kadon_{prefix}_{TEMPLATE_ID}"
            templates[(table, kind)] = [row for row in rows if template_key in row.values() or f"kadon_{TEMPLATE_ID}" in row.values()]
            outputs[(table, kind)] = (header, _generated_meta(meta, f"jvj_kadon_{kind}", f"jvj_kadon_generated_{kind}"), [])
    ui_header, ui_meta, ui_rows = read_tsv(_table_path(UI_EFFECTS_TABLE, "jvj_kadon"))
    ui_template = [row for row in ui_rows if row["key"] == f"kadon_{TEMPLATE_ID}"]
    ui_out: List[Row] = []
    loc_rows: List[Row] = []
    lua_entries: List[Tuple[str, str, str]] = []
    two_use = 0

    for index, (cid, main_key, override) in enumerate(KADON_NEW_CREATURES):
        vanilla_main = main_units[main_key]
        vanilla_land = land_units[vanilla_main["land_unit"]]
        name = override or names[main_key]
        num_men = int(vanilla_main["num_men"])
        flies = float(entities.get(vanilla_land["man_entity"], {}).get("fly_speed", "0") or 0) > 0
        uses = summon_uses(vanilla_main)
        two_use += uses == 2
        variant = variants[main_key]
        ids = dict(zip(("bind", "kin"), unique_ids(index)))

        for kind, prefix, title in KINDS:
            key = f"kadon_{prefix}_{cid}"
            mapping = {f"kadon_{prefix}_{TEMPLATE_ID}": key, f"kadon_{TEMPLATE_ID}": f"kadon_{cid}"}
            for table in SCROLL_TABLES:
                rows = swap_cells(templates[(table, kind)], mapping)
                if table == "unit_special_abilities_tables":
                    for row in rows:
                        row.update({"num_uses": str(uses), "unique_id": str(ids[prefix]), "spawn_proxy_vfx": spawn_proxy_vfx(num_men, flies)})
                outputs[(table, kind)][2].extend(rows)

            land_row, _ = sync_land_unit_row(templates[("land_units_tables", kind)][0], vanilla_land, keep=set())
            land_row["key"] = key
            outputs[("land_units_tables", kind)][2].append(land_row)
            outputs[("main_units_tables", kind)][2].append(build_main_unit_row(vanilla_main, key, templates[("main_units_tables", kind)][0]))
            outputs[("land_units_to_unit_abilites_junctions_tables", kind)][2].extend(
                build_ability_rows(key, vanilla_abilities.get(vanilla_main["land_unit"], []), is_bind=prefix == "bind"))
            outputs[("unit_variants_tables", kind)][2].append({"faction": "", "unit": key, "name": key, "variant": variant["variant"], "unit_card": variant["unit_card"]})

            scroll_name = f"Kadon Scroll of {title} ({name})"
            flavour = loc_ancillaries[f"ancillaries_colour_text_kadon_{prefix}_{TEMPLATE_ID}"]
            loc_rows += [
                {"key": f"ancillaries_onscreen_name_{key}", "text": scroll_name, "tooltip": "true"},
                {"key": f"ancillaries_colour_text_{key}", "text": flavour, "tooltip": "true"},
                {"key": f"effects_description_{key}", "text": f'Ability: "{scroll_name}"', "tooltip": "true"},
                {"key": f"land_units_onscreen_name_{key}", "text": name, "tooltip": "true"},
                {"key": f"land_units_concealed_name_{key}", "text": "", "tooltip": "true"},
                {"key": f"unit_abilities_onscreen_name_{key}", "text": scroll_name, "tooltip": "true"},
                {"key": f"unit_abilities_tooltip_text_{key}", "text": loc_abilities[f"unit_abilities_tooltip_text_kadon_{prefix}_{TEMPLATE_ID}"], "tooltip": "true"},
            ]

        ui_out.extend(swap_cells(ui_template, {f"kadon_{TEMPLATE_ID}": f"kadon_{cid}"}))
        loc_rows.append({"key": f"unit_abilities_additional_ui_effects_localised_text_kadon_{cid}", "text": summons_text(name, num_men), "tooltip": "true"})
        lua_entries.append((cid, name, game_tag(main_key)))

    logging.info(f"{len(KADON_NEW_CREATURES)} creatures, {2 * len(KADON_NEW_CREATURES)} scrolls, {two_use} two-use creatures.")
    for (table, kind), (_, _, rows) in sorted(outputs.items()):
        logging.info(f"{table} {kind}: {len(rows)} rows")
    if dry_run:
        logging.info("Dry run, nothing written.")
        return 0

    for (table, kind), (header, meta, rows) in outputs.items():
        write_tsv(_table_path(table, f"jvj_kadon_generated_{kind}"), header, meta, rows)
    write_tsv(_table_path(UI_EFFECTS_TABLE, "jvj_kadon_generated"), ui_header, _generated_meta(ui_meta, "jvj_kadon", "jvj_kadon_generated"), ui_out)
    write_tsv(GENERATED_LOC, ["key", "text", "tooltip"], "#Loc;1;text/jvj_kadon_generated.loc\t\t", loc_rows)
    with open(GENERATED_LUA, "w", encoding="utf-8", newline="") as f:
        f.write(lua_creature_list(lua_entries))
    logging.info("Generated files written.")
    return 0


def main() -> int:
    """Parse arguments and run the generator.

    Returns:
        int: Process exit code.
    """
    parser = argparse.ArgumentParser(description="Generate Kadon scrolls for the vanilla creatures in data/kadon_new_creatures.py.")
    parser.add_argument("--dry-run", action="store_true", help="Validate and log a summary without writing any file.")
    args = parser.parse_args()
    setup_script_logging()
    return generate(args.dry_run)


if __name__ == "__main__":
    sys.exit(main())
