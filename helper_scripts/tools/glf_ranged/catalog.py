"""List every vanilla lord and hero with its mount variants, its GLF ranged status, and a guessed GLF missile.

Usage:
    cd helper_scripts && python -u -m tools.glf_ranged.catalog [--seed] > _diag/glf_ranged_catalog.log 2>&1

The report goes to `_diag/glf_ranged_report.txt`. `--seed` writes `selection.json` from GLF's current units when it does not exist yet.
"""

import argparse
import collections
import glob
import json
import logging
import os
import re
import shutil
import time
from dataclasses import dataclass, field
from typing import Dict, Iterable, List, Optional, Set, Tuple

from core.extract_cache import cached_pack_extract
from core.utilities import FILEPATH_TO_VANILLA_DATA_TABLES, TEMP_DIR, clear_temp_root, load_tsv_data, log_elapsed_time, run_rpfm_cli, setup_script_logging
from tools.glf_rebuild_animpack import GLF_ANIMPACK_PATH, GLF_MOD_DIR, SCHEMAS_DIR, SLOT_IDS_FILE, AnimSet, load_slot_ids, load_vanilla_sets, parse_set, read_animpack
from ttc.ttc_data import LOC_NAME_PREFIX, LOC_REFERENCE_PATTERN, VANILLA_LOC_PACK, read_loc_names, unit_faction

TOOL_DIR = os.path.dirname(os.path.abspath(__file__))
SELECTION_PATH = os.path.join(TOOL_DIR, "selection.json")
# The selection as of the last Workshop upload, so the picker can highlight what is not published yet.
PUBLISHED_PATH = os.path.join(TOOL_DIR, "published.json")
REPORT_PATH = "./_diag/glf_ranged_report.txt"
SCRATCH = f"{TEMP_DIR}/glf_ranged"
# Loc key prefix of agent subtype names, which some unit names refer to.
SUBTYPE_NAME_PREFIX = "agent_subtypes_onscreen_name_override_"
# The pack holding unit card images and the portrait settings that name them.
VANILLA_UI_PACK = os.path.join(os.path.dirname(FILEPATH_TO_VANILLA_DATA_TABLES), "ui.pack")
PORTRAIT_SETTINGS = "ui/portraits/portholes/portrait_settings__.bin"
# Where unit card images are kept between runs, the `ui.pack` folder they come from, and the file recording which `ui.pack` they came from.
CARDS_DIR = "./_diag/glf_ranged_cards"
CARDS_FOLDER = "ui/portraits/units"
CARDS_STAMP = ".ui_pack_stamp"
# The game and DLC prefix of a unit key, e.g. `wh2_dlc15_`.
GAME_PREFIX = re.compile(r"^wh\d*_(main|dlc\d+|pro\d+|cp\d+|twa\d+|survival)_")
# Quest battle and boss copies of a lord or hero, which never get ranged support and are hidden in the picker (2026-10-12). `qb` can also sit
# mid-key, e.g. `wh3_dlc29_qb_brt_cha_lord_warhorse`. Greenskin Big Bosses are real heroes, so `_big_boss` does not count.
SPECIAL_COPY = re.compile(r"(?<!_big)_(qb|boss)(_\d+)?$|_qb_", re.IGNORECASE)
# A trailing variant number on a unit key, e.g. `_1` in `wh_dlc07_brt_cha_damsel_beasts_1`.
VARIANT_NUMBER = re.compile(r"_\d+$")
# The race and `mnt_` part of a mount key, and trailing parts that do not name the mount, e.g. `brt_mnt_` and `_deprecated`.
MOUNT_PREFIX = re.compile(r"^[a-z]{2,4}_mnt_")
MOUNT_SUFFIX = re.compile(r"(_(deprecated|360|\d+))+$")
# Trailing variant parts of a unit key that copies share with the original, e.g. `_1`, `_qb`, `_boss` or `_MP`.
VARIANT_SUFFIX = re.compile(r"(_(\d+|qb|boss|mp|summoned))+$", re.IGNORECASE)
VANILLA_TABLES = [
    "main_units_tables",
    "land_units_tables",
    "agent_subtypes_tables",
    "units_custom_battle_mounts_tables",
    "special_ability_groups_to_units_junctions_tables",
    "unit_attributes_to_groups_junctions_tables",
    "units_to_groupings_military_permissions_tables",
    "land_units_to_battle_personalities_junctions_tables",
    "battle_personalities_tables",
    "campaign_character_art_sets_tables",
    "battle_entities_tables",
    "land_unit_articulated_vehicles_tables",
    "articulation_nodes_in_land_articulated_vehicles_tables",
]
GLF_LAND_UNITS = f"{GLF_MOD_DIR}/db/land_units_tables/!!!1a_glf_battle_mage_dante.tsv"
GLF_MISSILES = f"{GLF_MOD_DIR}/db/missile_weapons_tables/glf_battle_mage.tsv"
CHARACTER_CASTES = {"lord", "hero"}
# Sort order of the castes in the picker.
CASTE_ORDER = {"lord": 0, "hero": 1}
ANIMPACK_BIN_FOLDER = "animations/database/battle/bin"
# Unit attribute that lets a unit fire while moving, for infantry and cavalry alike.
FWM_ATTRIBUTE = "mounted_fire_move"
# A generic GLF missile, e.g. `glf_mage_lord_life_missile`, captures the lore.
GENERIC_MISSILE = re.compile(r"^glf_mage_(lord|hero)_(.+)_missile$")
# A named GLF missile, e.g. `glf_emp_balthasar_gelt_missile`, captures the name after the race code.
SPECIAL_MISSILE = re.compile(r"^glf_[a-z]+_(.+)_missile$")
# Slots that let a set fire, whatever the unit kind, and the slots each kind needs to fire while moving.
FIRE_SLOT_NAMES = {"FIRE_LEVEL", "RIDER_FIRE_FORWARD_LEVEL"}
MOVING_FIRE_SLOTS = ["MOVING_FIRE_FORWARD_LEVEL", "MOVING_FIRE_LEFT_LEVEL", "MOVING_FIRE_RIGHT_LEVEL", "MOVING_FIRE_BACKWARD_LEVEL"]
FWM_SLOTS = {"foot": MOVING_FIRE_SLOTS, "flyer": MOVING_FIRE_SLOTS, "rider": ["RIDER_FIRE_LEFT_LEVEL", "RIDER_FIRE_RIGHT_LEVEL", "RIDER_FIRE_BACK_LEVEL"]}
# Cast slots a fire slot can borrow its animation from, best first.
CAST_SLOTS = {
    "foot": ["CAST_SPELL_UP_SHORT", "CAST_SPELL_FORWARD_SHORT", "CAST_SPELL_UP_MEDIUM", "CAST_SPELL_FORWARD_MEDIUM", "CAST_SPELL_UP_LONG", "CAST_SPELL_FORWARD_LONG"],
    "rider": ["RIDER_CAST_SPELL_UP_SHORT", "RIDER_CAST_SPELL_FORWARD_SHORT", "RIDER_CAST_SPELL_UP_MEDIUM", "RIDER_CAST_SPELL_FORWARD_MEDIUM", "RIDER_CAST_SPELL_UP_LONG", "RIDER_CAST_SPELL_FORWARD_LONG"],
}
CAST_SLOTS["flyer"] = CAST_SLOTS["foot"]


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Data


@dataclass
class UnitRow:
    """One vanilla lord or hero land unit and its GLF ranged status."""

    # Land unit key.
    key: str
    # In-game name, or the key when no loc names it.
    name: str
    # Faction name, e.g. `High Elves`.
    faction: str
    # `lord` or `hero`.
    caste: str
    # Land unit key of the on-foot unit this one is a mount variant of. Equal to `key` for the base unit.
    base: str
    # Mount icon name for mount variants, e.g. `mount_great_eagle`, or empty.
    mount: str
    # Animation set name from `land_units.man_animation`.
    anim_set: str
    # `foot`, `rider` or `flyer`, or empty when the set is missing.
    kind: str
    # True when the agent subtype or a spell lore marks the unit as a caster.
    is_caster: bool
    # Missile weapon in vanilla `land_units`, usually empty.
    vanilla_missile: str
    # Missile weapon GLF gives the unit, or empty when GLF does not cover it.
    glf_missile: str
    # GLF missile guessed for the unit.
    guess: str
    # Why `guess` was picked.
    guess_source: str
    # True when the set GLF or vanilla ships has a fire slot.
    fire_slot: bool
    # True when the set has `COMBAT_READY`, which on-foot firing needs to avoid a T-pose.
    combat_ready: bool
    # True when the set fires on foot but has no `COMBAT_READY`, so the unit T-poses after firing.
    tpose_risk: bool
    # Cast slot a new fire slot would borrow from, or empty when the set has none.
    cast_slot: str
    # True when the unit's attribute group has `fire_whilst_moving`.
    fwm_attribute: bool
    # True when the set has the unit kind's fire-while-moving slots.
    fwm_slots: bool
    # Other lord and hero units that use the same animation set.
    set_shared_with: List[str] = field(default_factory=list)
    # Path of the unit card image inside `CARDS_DIR`, or empty when none was found or cards were not loaded.
    card: str = ""
    # True for quest battle (`_qb`) and boss (`_boss`) copies, which never get ranged support.
    special_copy: bool = False


@dataclass
class SetEntry:
    """One animation set as vanilla and GLF ship it."""

    # Path inside the animpack, e.g. `animations/database/battle/bin/hu1_empire_staff_and_sword.bin`.
    path: str
    # The vanilla set.
    vanilla: AnimSet
    # GLF's copy of the set, or None when GLF does not ship it.
    glf: Optional[AnimSet]

    @property
    def live(self) -> AnimSet:
        """The set the game uses with GLF loaded."""
        return self.glf or self.vanilla


@dataclass
class Catalog:
    """Every vanilla lord and hero row plus the choices the GUI offers."""

    # Rows by faction, then lords before heroes, then the base unit's name, with each base unit's mounts after it.
    units: List[UnitRow]
    # Every GLF missile weapon key.
    missiles: List[str]


@dataclass
class Inputs:
    """Everything the catalog is built from, kept for the generator."""

    # Vanilla table name to rows.
    tables: Dict[str, List[Dict[str, str]]]
    # Animation set name to its vanilla and GLF copies.
    sets: Dict[str, SetEntry]
    # Slot name by id.
    names: Dict[int, str]
    # The built catalog.
    catalog: Catalog


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Loading


def _rows(folder: str) -> List[Dict[str, str]]:
    """Read every TSV under a folder.

    Args:
        folder (str): Extraction folder.

    Returns:
        Row dicts.
    """
    rows: List[Dict[str, str]] = []
    for path in sorted(glob.glob(f"{folder}/**/*.tsv", recursive=True)):
        rows.extend(load_tsv_data(path)[0])
    return rows


def load_vanilla_tables() -> Dict[str, List[Dict[str, str]]]:
    """Extract the vanilla tables the catalog reads, through the extraction cache.

    Raises:
        FileNotFoundError: If a table could not be extracted.

    Returns:
        Table name to rows.
    """
    tables = {}
    for table in VANILLA_TABLES:
        dest = f"{SCRATCH}/vanilla/{table}"
        cached_pack_extract(FILEPATH_TO_VANILLA_DATA_TABLES, f"db/{table}/data__", dest, source_kind="file", capture_output=True)
        tables[table] = _rows(dest)
        if not tables[table]:
            raise FileNotFoundError(f"Vanilla {table} could not be extracted")
    return tables


def vanilla_layout(table: str) -> Tuple[List[str], int]:
    """Read the column order and version of a vanilla table extracted by `load_vanilla_tables`, for writing new GLF files of it.

    Args:
        table (str): Table name, one of `VANILLA_TABLES`.

    Returns:
        The column names and the table version.
    """
    path = sorted(glob.glob(f"{SCRATCH}/vanilla/{table}/**/*.tsv", recursive=True))[0]
    _, header, version_info = load_tsv_data(path)
    return list(header), int(version_info.split(";")[1])


def load_names() -> Dict[str, str]:
    """Load vanilla English unit names.

    Returns:
        Loc key to text.
    """
    names: Dict[str, str] = {}
    dest = f"{SCRATCH}/loc"
    cached_pack_extract(VANILLA_LOC_PACK, "text", dest, capture_output=True)
    # Some unit names point at agent subtype names, so those are loaded too.
    read_loc_names(dest, names, (LOC_NAME_PREFIX, SUBTYPE_NAME_PREFIX))
    return names


def ensure_cards() -> Dict[str, str]:
    """Extract the unit card images unless `CARDS_DIR` already matches the installed `ui.pack`, then index them.

    Returns:
        Lowercase file name, e.g. `hef_teclis_0.png`, to its path inside `CARDS_DIR`. The first path in sorted order wins.
    """
    info = os.stat(VANILLA_UI_PACK)
    stamp = f"{info.st_size}:{int(info.st_mtime)}"
    stamp_path = os.path.join(CARDS_DIR, CARDS_STAMP)
    current = ""
    if os.path.exists(stamp_path):
        with open(stamp_path, encoding="utf-8") as f:
            current = f.read()
    if current != stamp:
        shutil.rmtree(CARDS_DIR, ignore_errors=True)
        os.makedirs(CARDS_DIR)
        logging.info("Extracting unit card images from ui.pack...")
        run_rpfm_cli(["pack", "extract", "--pack-path", VANILLA_UI_PACK, "-F", f"{CARDS_FOLDER};{CARDS_DIR}"], capture_output=True)
        with open(stamp_path, "w", encoding="utf-8") as f:
            f.write(stamp)
    files: Dict[str, str] = {}
    for path in sorted(glob.glob(f"{CARDS_DIR}/**/*.png", recursive=True)):
        files.setdefault(os.path.basename(path).lower(), os.path.relpath(path, CARDS_DIR).replace("\\", "/"))
    return files


def load_portraits() -> Dict[str, str]:
    """Read the vanilla portrait settings and note each art set's first portrait file name.

    Returns:
        Art set id to the lowercase file name of its portrait, e.g. `hef_teclis_0.png`. Unit cards share these names.
    """
    folder = f"{SCRATCH}/portraits"
    cached_pack_extract(VANILLA_UI_PACK, PORTRAIT_SETTINGS, folder, source_kind="file", tables_as_tsv=False, capture_output=True)
    json_path = f"{folder}/portrait_settings.json"
    run_rpfm_cli(["portrait-settings", "to-json", "-b", f"{folder}/{PORTRAIT_SETTINGS}", "-j", json_path], capture_output=True)
    if not os.path.exists(json_path):
        logging.warning("Portrait settings could not be read. Unit cards will be missing.")
        return {}
    with open(json_path, encoding="utf-8") as f:
        entries = json.load(f)["entries"]
    names = {}
    for entry in entries:
        diffuse = next((variant["file_diffuse"] for variant in entry["variants"] if variant["file_diffuse"]), "")
        if diffuse:
            names[entry["id"]] = os.path.basename(diffuse.replace("\\", "/")).lower()
    return names


def unit_cards(keys: Iterable[str], base_of: Dict[str, str], subtypes_of: Dict[str, List[str]], art_sets_of: Dict[str, List[str]], portraits: Dict[str, str], card_files: Dict[str, str]) -> Dict[str, str]:
    """Find each unit's card image through its agent subtype and art set, accepting only images the game ships.

    A unit with no card of its own borrows its base unit's card, then the card of a unit with the same key apart from trailing variant parts, then a
    card whose file name matches the key without its game prefix and `cha_`, e.g. `brt_alberic_bordeleaux` for `wh_dlc07_brt_cha_alberic_bordeleaux_0`.

    Args:
        keys (Iterable[str]): Land unit keys.
        base_of (Dict[str, str]): Mount variant to its base unit.
        subtypes_of (Dict[str, List[str]]): Land unit to the agent subtypes that use it.
        art_sets_of (Dict[str, List[str]]): Agent subtype to its art set ids.
        portraits (Dict[str, str]): Art set id to portrait file name, from `load_portraits`.
        card_files (Dict[str, str]): Card file name to its path, from `ensure_cards`.

    Returns:
        Land unit key to card path inside `CARDS_DIR`, or empty when none was found.
    """
    keys = list(keys)
    own = {key: next((card_files[portraits[art]] for subtype in subtypes_of.get(key, []) for art in art_sets_of.get(subtype, []) if portraits.get(art) in card_files), "") for key in keys}
    by_stem: Dict[str, str] = {}
    for key in keys:
        if own[key]:
            by_stem.setdefault(VARIANT_SUFFIX.sub("", key), own[key])
    by_file = {}
    for name, path in sorted(card_files.items()):
        by_file.setdefault(VARIANT_SUFFIX.sub("", os.path.splitext(name)[0]), path)

    def by_name(key: str) -> str:
        return by_file.get(VARIANT_SUFFIX.sub("", GAME_PREFIX.sub("", key).replace("_cha_", "_")).lower(), "")

    return {key: own[key] or own.get(base_of.get(key, ""), "") or by_stem.get(VARIANT_SUFFIX.sub("", key), "") or by_name(key) for key in keys}


def load_sets() -> Dict[str, SetEntry]:
    """Load each animation set as vanilla ships it and as GLF ships it.

    Returns:
        Set name to its entry.
    """
    vanilla = {path: parse_set(data) for path, data in load_vanilla_sets().items() if path.startswith(ANIMPACK_BIN_FOLDER) and path.endswith(".bin")}
    with open(GLF_ANIMPACK_PATH, "rb") as f:
        glf = {path: parse_set(data) for path, data in read_animpack(f.read())}
    return {anim_set.name: SetEntry(path, anim_set, glf.get(path)) for path, anim_set in vanilla.items()}


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Catalog


def display_name(key: str, loc: Dict[str, str]) -> str:
    """Look up a unit's in-game name, following `{{tr:...}}` references to other loc entries a few levels deep.

    Args:
        key (str): Land unit key.
        loc (Dict[str, str]): Loc key to text.

    Returns:
        The name, or the key when no loc text names the unit.
    """
    name = loc.get(LOC_NAME_PREFIX + key, key)
    for _ in range(3):
        name = LOC_REFERENCE_PATTERN.sub(lambda match: loc.get(match.group(1), match.group(0)), name)
    return name


def mount_name(mount: str) -> str:
    """Turn a mount key into the `mount_<name>` form the picker shows for mount icons.

    Args:
        mount (str): `mounts` key, e.g. `wh_main_brt_mnt_warhorse_deprecated`, or empty.

    Returns:
        E.g. `mount_warhorse`, or empty when there is no mount.
    """
    if not mount:
        return ""
    return "mount_" + MOUNT_SUFFIX.sub("", MOUNT_PREFIX.sub("", GAME_PREFIX.sub("", mount)))


def missile_family(missile: str) -> str:
    """Reduce a GLF missile to its lore for generic missiles, or keep a named special as is.

    Args:
        missile (str): GLF missile weapon key.

    Returns:
        The lore token, e.g. `life`, or the missile key.
    """
    match = GENERIC_MISSILE.match(missile)
    return match.group(2) if match else missile


def family_missile(family: str, caste: str, missiles: Set[str]) -> str:
    """Turn a lore or special back into a missile key for a caste.

    Args:
        family (str): Lore token or special missile key.
        caste (str): `lord` or `hero`.
        missiles (Set[str]): Every GLF missile key.

    Returns:
        The missile key, or empty when none exists.
    """
    if family in missiles:
        return family
    for candidate in (f"glf_mage_{caste}_{family}_missile", f"glf_mage_lord_{family}_missile"):
        if candidate in missiles:
            return candidate
    return ""


def learn_lores(units: Dict[str, Set[str]], glf_missiles: Dict[str, str]) -> Dict[str, collections.Counter]:
    """Learn which GLF missile family each vanilla lore feature goes with, from the units GLF already covers.

    Args:
        units (Dict[str, Set[str]]): Land unit to its lore features (spell ability groups and subtype magic lore).
        glf_missiles (Dict[str, str]): Land unit to the missile GLF gives it.

    Returns:
        Feature to missile family vote counts.
    """
    votes: Dict[str, collections.Counter] = collections.defaultdict(collections.Counter)
    for key, missile in glf_missiles.items():
        for feature in units.get(key, ()):
            votes[feature][missile_family(missile)] += 1
    return votes


def guess_missile(key: str, caste: str, features: Set[str], faction: str, votes: Dict[str, collections.Counter], faction_votes: Dict[str, collections.Counter], missiles: Set[str], lores: List[str]) -> Tuple[str, str]:
    """Guess the GLF missile for a unit.

    Args:
        key (str): Land unit key.
        caste (str): `lord` or `hero`.
        features (Set[str]): The unit's lore features.
        faction (str): Faction name.
        votes (Dict[str, collections.Counter]): Feature to missile family votes from `learn_lores`.
        faction_votes (Dict[str, collections.Counter]): Faction to missile family votes over GLF's units.
        missiles (Set[str]): Every GLF missile key.
        lores (List[str]): Generic lore tokens, longest first.

    Returns:
        The missile key and why it was picked. The key is empty when nothing matched. A named special whose name is in the key wins, then lore
        votes, then a lore token in the key, then the faction's most common GLF lore.
    """
    for missile in sorted(missiles, key=len, reverse=True):
        stem = SPECIAL_MISSILE.match(missile)
        if stem and not GENERIC_MISSILE.match(missile) and re.search(rf"(^|_){re.escape(stem.group(1))}(_|\d|$)", key):
            return missile, f"named special `{stem.group(1)}`"
    tally: collections.Counter = collections.Counter()
    for feature in features:
        tally.update(votes.get(feature, {}))
    if tally:
        family = min(tally.items(), key=lambda item: (-item[1], item[0]))[0]
        missile = family_missile(family, caste, missiles)
        if missile:
            return missile, "lore " + ", ".join(sorted(f for f in features if f in votes))
    for lore in lores:
        if re.search(rf"(^|_){re.escape(lore)}(_|\d|$)", key):
            return family_missile(lore, caste, missiles), f"key token `{lore}`"
    if faction_votes.get(faction):
        family = min(faction_votes[faction].items(), key=lambda item: (-item[1], item[0]))[0]
        missile = family_missile(missile_family(family), caste, missiles)
        if missile:
            return missile, f"{faction} default"
    return "", "no match"


def unit_kind(anim_set: AnimSet, names: Dict[int, str]) -> str:
    """Tell whether a set is for a unit on foot, a rider, or a flyer on foot.

    Args:
        anim_set (AnimSet): The vanilla set.
        names (Dict[int, str]): Slot name by id.

    Returns:
        `rider`, `flyer` or `foot`.
    """
    slot_names = {names.get(slot.slot_id, "") for slot in anim_set.slots}
    # Chariot and war machine sets (`_wm_`) have no mount or RIDER_STAND but cast and fire through the rider slots.
    # Sets that only cast through rider slots, e.g. the Wu Xing War Compass, are ridden too.
    rider_only = any(name in slot_names for name in CAST_SLOTS["rider"]) and not any(name in slot_names for name in CAST_SLOTS["foot"])
    if anim_set.mount or "RIDER_STAND" in slot_names or "_wm_" in anim_set.name or rider_only:
        return "rider"
    return "flyer" if "FLY_STAND" in slot_names else "foot"


def build_catalog(tables: Dict[str, List[Dict[str, str]]], sets: Dict[str, SetEntry], loc: Dict[str, str], glf_rows: List[Dict[str, str]], missiles: List[str], names: Dict[int, str], portraits: Dict[str, str], card_files: Dict[str, str]) -> Catalog:
    """Build one row per vanilla lord and hero land unit.

    Args:
        tables (Dict[str, List[Dict[str, str]]]): Vanilla tables from `load_vanilla_tables`.
        sets (Dict[str, SetEntry]): Animation sets from `load_sets`.
        loc (Dict[str, str]): Loc key to text.
        glf_rows (List[Dict[str, str]]): GLF's land_units rows.
        missiles (List[str]): Every GLF missile key.
        names (Dict[int, str]): Slot name by id.
        portraits (Dict[str, str]): Art set id to portrait file name, from `load_portraits`.
        card_files (Dict[str, str]): Card file name to its path, from `ensure_cards`.

    Returns:
        The catalog.
    """
    land = {row["key"]: row for row in tables["land_units_tables"]}
    main = [row for row in tables["main_units_tables"] if row["caste"] in CHARACTER_CASTES and row["land_unit"] in land]
    caste_of = {row["land_unit"]: row["caste"] for row in main}
    unit_of = {row["land_unit"]: row["unit"] for row in main}
    base_of, mount_of = {}, {}
    for row in tables["units_custom_battle_mounts_tables"]:
        base_of[row["mounted_unit"]] = row["base_unit"]
        mount_of[row["mounted_unit"]] = os.path.splitext(os.path.basename(row["icon_name"]))[0]
    # Versions missing from the custom battle mounts list, e.g. `wh_dlc07_brt_cha_damsel_beasts_1`, join the same character's `_0` unit.
    for key in caste_of:
        first = VARIANT_NUMBER.sub("_0", key)
        if key not in base_of and first != key and caste_of.get(first) == caste_of[key]:
            base_of[key] = first
            mount_of[key] = mount_name(land[key]["mount"])
    # A version whose base is not a lord or hero row is its own base.
    base_of = {key: base for key, base in base_of.items() if base in caste_of}
    groups: Dict[str, Set[str]] = collections.defaultdict(set)
    for row in tables["units_to_groupings_military_permissions_tables"]:
        groups[row["unit"]].add(row["military_group"])

    features: Dict[str, Set[str]] = collections.defaultdict(set)
    casters = set()
    for row in tables["special_ability_groups_to_units_junctions_tables"]:
        if "lore" in row["ability_group"]:
            features[row["unit"]].add(row["ability_group"])
            casters.add(row["unit"])
    for row in tables["agent_subtypes_tables"]:
        unit = row["associated_unit_override"]
        if row["magic_lore"]:
            features[unit].add(row["magic_lore"])
        if row["is_caster"].lower() == "true":
            casters.add(unit)
    # Mount variants share the base unit's lore and caster flag.
    for key in caste_of:
        base = base_of.get(key, key)
        features[key] |= features.get(base, set())
        if base in casters:
            casters.add(key)

    fwm_groups = {row["attribute_group"] for row in tables["unit_attributes_to_groups_junctions_tables"] if row["attribute"] == FWM_ATTRIBUTE}
    glf_missiles = {row["key"]: row["primary_missile_weapon"] for row in glf_rows if row.get("primary_missile_weapon")}
    missile_set = set(missiles)
    votes = learn_lores(features, glf_missiles)
    faction_votes: Dict[str, collections.Counter] = collections.defaultdict(collections.Counter)
    for key, missile in glf_missiles.items():
        faction_votes[unit_faction(key, groups.get(unit_of.get(key, key), set()))][missile_family(missile)] += 1
    lores = sorted({m.group(2) for m in map(GENERIC_MISSILE.match, missiles) if m}, key=len, reverse=True)

    users: Dict[str, List[str]] = collections.defaultdict(list)
    for key in caste_of:
        users[land[key]["man_animation"]].append(key)

    rows = []
    for key, caste in caste_of.items():
        land_row = land[key]
        base = base_of.get(key, key)
        faction = unit_faction(key, groups.get(unit_of[key], set()))
        guess, source = guess_missile(key, caste, features[key], faction, votes, faction_votes, missile_set, lores)
        entry = sets.get(land_row["man_animation"])
        kind = unit_kind(entry.vanilla, names) if entry else ""
        live = entry.live if entry else None
        slot_names = {names.get(slot.slot_id, "") for slot in live.slots} if live else set()
        fire_slot = bool(FIRE_SLOT_NAMES & slot_names)
        combat_ready = "COMBAT_READY" in slot_names
        rows.append(
            UnitRow(
                key=key,
                name=display_name(key, loc),
                faction=faction,
                caste=caste,
                base=base,
                mount=mount_of.get(key, ""),
                anim_set=land_row["man_animation"],
                kind=kind,
                is_caster=key in casters,
                vanilla_missile=land_row["primary_missile_weapon"],
                glf_missile=glf_missiles.get(key, ""),
                guess=guess,
                guess_source=source,
                fire_slot=fire_slot,
                combat_ready=combat_ready,
                tpose_risk=fire_slot and kind != "rider" and not combat_ready,
                cast_slot=next((name for name in CAST_SLOTS.get(kind, []) if name in slot_names), ""),
                fwm_attribute=land_row["attribute_group"] in fwm_groups,
                fwm_slots=bool(kind) and all(name in slot_names for name in FWM_SLOTS[kind]),
                set_shared_with=sorted(other for other in users[land_row["man_animation"]] if other != key),
                special_copy=bool(SPECIAL_COPY.search(key)),
            )
        )
    subtypes_of: Dict[str, List[str]] = collections.defaultdict(list)
    for row in tables["agent_subtypes_tables"]:
        subtypes_of[row["associated_unit_override"]].append(row["key"])
    art_sets_of: Dict[str, List[str]] = collections.defaultdict(list)
    for row in tables["campaign_character_art_sets_tables"]:
        art_sets_of[row["agent_subtype"]].append(row["art_set_id"])
    cards = unit_cards(caste_of, base_of, subtypes_of, art_sets_of, portraits, card_files)
    for row in rows:
        row.card = cards[row.key]
    # Within a faction: lords then heroes, each by the base unit's in-game name so versions of one character (e.g. every Damsel) sit together. A
    # base unit's mounts follow it in key order.
    by_key = {row.key: row for row in rows}
    rows.sort(key=lambda row: (row.faction, CASTE_ORDER.get(by_key[row.base].caste, 9), by_key[row.base].name.lower(), row.base, row.key != row.base, row.key))
    return Catalog(rows, missiles)


def load_inputs(cards: bool = False) -> Inputs:
    """Load every input and build the catalog.

    Args:
        cards (bool): Also find each unit's card image, extracting the images from `ui.pack` when needed. Only the picker shows them.

    Returns:
        The inputs and the catalog.
    """
    with open(f"{SCHEMAS_DIR}/{SLOT_IDS_FILE}", encoding="utf-8") as f:
        names = load_slot_ids(f.read())
    glf_rows = load_tsv_data(GLF_LAND_UNITS)[0]
    missiles = [row["key"] for row in load_tsv_data(GLF_MISSILES)[0]]
    tables, sets = load_vanilla_tables(), load_sets()
    portraits, card_files = (load_portraits(), ensure_cards()) if cards else ({}, {})
    return Inputs(tables, sets, names, build_catalog(tables, sets, load_names(), glf_rows, missiles, names, portraits, card_files))


def load_catalog(cards: bool = False) -> Catalog:
    """Load every input and build the catalog.

    Args:
        cards (bool): Also find each unit's card image.

    Returns:
        The catalog.
    """
    return load_inputs(cards).catalog


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Selection and report


def seed_selection(catalog: Catalog) -> Dict:
    """Build a selection that marks every unit GLF covers today as ranged with its current missile.

    Args:
        catalog (Catalog): The catalog.

    Returns:
        The selection.
    """
    units = {row.key: {"ranged": True, "fwm": False, "missile": row.glf_missile} for row in catalog.units if row.glf_missile}
    return {"units": units, "ignore": []}


def load_selection(path: Optional[str] = None) -> Dict:
    """Read a saved selection, or an empty one.

    Args:
        path (Optional[str]): `PUBLISHED_PATH` for the selection as last published. Defaults to `SELECTION_PATH`.

    Returns:
        The selection with `units` and `ignore`.
    """
    path = path or SELECTION_PATH
    if not os.path.exists(path):
        return {"units": {}, "ignore": []}
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def write_selection(selection: Dict, path: Optional[str] = None) -> None:
    """Save a selection with sorted keys so git diffs stay small.

    Args:
        selection (Dict): The selection with `units` and `ignore`.
        path (Optional[str]): `PUBLISHED_PATH` for the selection as last published. Defaults to `SELECTION_PATH`.
    """
    with open(path or SELECTION_PATH, "w", encoding="utf-8") as f:
        json.dump(selection, f, indent=1, sort_keys=True)


def report_lines(catalog: Catalog) -> List[str]:
    """Summarise the catalog per faction.

    Args:
        catalog (Catalog): The catalog.

    Returns:
        Report lines.
    """
    lines = []
    by_faction: Dict[str, List[UnitRow]] = collections.defaultdict(list)
    for row in catalog.units:
        by_faction[row.faction].append(row)
    lines.append(f"{'faction':22} units  GLF  casters-missing  no-set  T-pose-risk")
    for faction, rows in sorted(by_faction.items()):
        glf = sum(1 for row in rows if row.glf_missile)
        missing = [row for row in rows if row.is_caster and not row.glf_missile]
        no_set = sum(1 for row in rows if not row.kind)
        risk = sum(1 for row in rows if row.glf_missile and row.tpose_risk)
        lines.append(f"{faction:22} {len(rows):5}  {glf:3}  {len(missing):15}  {no_set:6}  {risk:11}")
    lines.append("")
    lines.append("Casters GLF does not cover (key | kind | cast slot | guess | source):")
    for row in catalog.units:
        if row.is_caster and not row.glf_missile:
            lines.append(f"    {row.key} | {row.kind or 'no set'} | {row.cast_slot or 'NO CAST SLOT'} | {row.guess or '-'} | {row.guess_source}")
    lines.append("")
    lines.append("GLF units whose guess differs from GLF's missile (guess check):")
    differ = [row for row in catalog.units if row.glf_missile and row.guess != row.glf_missile]
    lines.append(f"    {len(differ)} of {sum(1 for row in catalog.units if row.glf_missile)}")
    lines += [f"    {row.key}: GLF {row.glf_missile}, guess {row.guess} ({row.guess_source})" for row in differ[:40]]
    return lines


def main():
    """Build the catalog, write the report, and seed the selection when asked."""
    parser = argparse.ArgumentParser(description="List vanilla lords and heroes with their GLF ranged status.")
    parser.add_argument("--seed", action="store_true", help="Write selection.json from GLF's current units when it does not exist.")
    args = parser.parse_args()

    setup_script_logging()
    start_time = time.time()
    try:
        catalog = load_catalog()
        logging.info(f"Catalog has {len(catalog.units)} lord and hero units.")
        os.makedirs(os.path.dirname(REPORT_PATH), exist_ok=True)
        with open(REPORT_PATH, "w", encoding="utf-8") as f:
            f.write("\n".join(report_lines(catalog)) + "\n")
        logging.info(f"Report written to {REPORT_PATH}.")
        if args.seed:
            if os.path.exists(SELECTION_PATH):
                logging.info(f"{SELECTION_PATH} already exists. Not seeding.")
            else:
                write_selection(seed_selection(catalog))
                logging.info(f"Seeded {SELECTION_PATH}.")
    finally:
        clear_temp_root()
    log_elapsed_time("GLF ranged catalog", start_time)


if __name__ == "__main__":
    main()
