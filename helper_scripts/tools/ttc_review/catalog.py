"""Build the TTC unit browser's data: each culture's roster in the game's category sections, per-unit stats, abilities, caps and art, and write
confirmed picks to the hand files.

The roster follows the in-game Unit & Spell Browser (`ui/common ui/spell_browser.twui.xml`): cultures come from the custom battle permissions, and units
are grouped by their `ui_unit_group_parents` category, with campaign-exclusive units under the Extended Roster.
"""

import glob
import logging
import os
import re
from typing import Dict, List, Optional, Set, Tuple

from core import delta
from core.extract_cache import cached_pack_extract, extracted_tree
from core.utilities import FILEPATH_TO_VANILLA_DATA_TABLES
from generators.update_ttc_compat import AUTO_PICKS_PATH
from ttc import ttc_cards, ttc_compat_io, ttc_data
from ttc.ttc_cards import CARD_FOLDER
from ttc.ttc_classifier import parse_number

DETAIL_TABLES = [
    "battle_entities_tables",
    "melee_weapons_tables",
    "unit_armour_types_tables",
    "mounts_tables",
    "battlefield_engines_tables",
    "unit_abilities_tables",
    "land_units_to_unit_abilites_junctions_tables",
    "units_custom_battle_permissions_tables",
    "factions_tables",
    "cultures_subcultures_tables",
    "cultures_tables",
    "ui_unit_groupings_tables",
    "ui_unit_group_parents_tables",
    "building_units_allowed_tables",
    "building_levels_tables",
    "building_culture_variants_tables",
]
GAME_DATA_DIR = os.path.dirname(FILEPATH_TO_VANILLA_DATA_TABLES)
ABILITY_NAME_PREFIX = "unit_abilities_onscreen_name_"
CULTURE_NAME_PREFIX = "cultures_name_"
GROUP_PARENT_NAME_PREFIX = "ui_unit_group_parents_onscreen_name_"
BUILDING_NAME_PREFIX = "building_culture_variants_name_"
BUILDING_CHAIN_NAME_PREFIX = "building_chains_chain_tooltip_"
# Loc keys the browser reads: unit, ability, culture, unit category, building level and building chain names.
LOC_PREFIXES = (ttc_data.LOC_NAME_PREFIX, ABILITY_NAME_PREFIX, CULTURE_NAME_PREFIX, GROUP_PARENT_NAME_PREFIX, BUILDING_NAME_PREFIX, BUILDING_CHAIN_NAME_PREFIX)
ABILITY_FOLDER = "ui/battle ui/ability_icons"
CATEGORY_ICON_FOLDER = "ui/common ui/unit_category_icons"
RACE_STRIP_FOLDER = "ui/frontend ui/race_strip_images"
BUILDING_ICON_FOLDER = "ui/buildings/icons"
TTC_ART_FOLDER = "ui/custom/recruitment_controls"
# Art folders read from vanilla `ui.pack` and then every installed mod, so a mod's file wins like in the game's load order. Unit cards come from
# every pack `ttc_cards.card_packs` lists instead.
ART_FOLDERS = [ABILITY_FOLDER, CATEGORY_ICON_FOLDER, RACE_STRIP_FOLDER, BUILDING_ICON_FOLDER]
# Card frames, section headers and stat icons the browser and unit panel use, all in vanilla `ui2.pack`.
SKIN_FILES = [
    f"ui/skins/default/{name}.png"
    for name in (
        "unit_card_background",
        "unit_card_hover",
        "unit_card_selected",
        "unit_card_semicircle",
        "unit_card_semicircle_renown",
        "parchment_header_max",
        "icon_stat_health_noframe",
        "icon_entity_small",
        "icon_stat_armour",
        "icon_stat_morale",
        "icon_stat_speed",
        "icon_stat_attack",
        "icon_stat_defence",
        "icon_stat_damage",
        "icon_stat_charge_bonus",
    )
]
ART_DIR = "./_diag/ttc_review_art"
ART_STAMP = ".pack_stamp"
# Category sections the browser leaves out. Lords and heroes never get TTC caps.
SKIPPED_SECTIONS = {"commander", "heroes_agents"}
# Rogue army settlements recruit nearly every unit, so they are left out of "Recruited from".
ROGUE_BUILDING = "rogue"
# Mod scripts that unlock units per building tier by filling a mercenary pool, like Animals for Wood Elves (`rhox_we_animals.lua`):
#   local tiers = { ["wh_dlc05_wef_animals_02"] = 2, ... }
#   local tier_02 = { {"rory_welf_small_wolf", 2, 15, 2}, ... }
#   local lookup = { [2] = tier_02, ... }
SCRIPT_FOLDER = "script/campaign/mod"
SCRIPT_POOL_CALL = "add_unit_to_province_mercenary_pool"
SCRIPT_BUILDING_TIER = re.compile(r'\[\s*"([\w-]+)"\s*\]\s*=\s*(\d+)')
SCRIPT_TIER_TABLE = re.compile(r"\[\s*(\d+)\s*\]\s*=\s*([A-Za-z_]\w*)")
SCRIPT_TABLE = re.compile(r"local\s+([A-Za-z_]\w*)\s*=\s*\{(.*?)\n\}", re.S)
SCRIPT_UNIT_ENTRY = re.compile(r'\{\s*"([\w-]+)"')
EXTENDED_ROSTER = "campaign_exclusives"
# Section for auto picks the browser would hide (no category, or a lord or hero category), so every pick stays reviewable. It sits before the
# Extended Roster.
UNSORTED = "unsorted"
UNSORTED_ORDER = 98
OTHER_CULTURE = "other"
CATEGORIES = ("core", "special", "rare")
MAX_WEIGHT = 10


def load_detail_tables() -> Dict[str, List[Dict[str, str]]]:
    """Read the extra tables from vanilla, then every installed supported mod.

    Returns:
        Table name to rows, vanilla rows first.
    """
    merged: Dict[str, List[Dict[str, str]]] = {table: [] for table in DETAIL_TABLES}
    sources = [(FILEPATH_TO_VANILLA_DATA_TABLES, "vanilla", True)] + [(mod["path"], ttc_data.pack_tag(mod["package_name"]), False) for mod in ttc_data.installed_mods()]
    for pack_path, tag, vanilla in sources:
        for table, rows in ttc_data.load_tables(pack_path, f"review_{tag}", vanilla, DETAIL_TABLES).items():
            merged[table].extend(rows)
    return merged


def _index(rows: List[Dict[str, str]], column: str = "key") -> Dict[str, Dict[str, str]]:
    """Index rows by a column, the first row for a value winning like the game's vanilla-first load in `ttc_data`.

    Args:
        rows (List[Dict[str, str]]): Table rows.
        column (str): Column to index by.

    Returns:
        Column value to row.
    """
    index: Dict[str, Dict[str, str]] = {}
    for row in rows:
        if row.get(column):
            index.setdefault(row[column], row)
    return index


def _extract_once(pack_path: str, sources: List[Tuple[str, str]], dest: str) -> None:
    """Extract folders or files from a pack, skipping the work when the pack and the source list have not changed since the last extraction.

    Args:
        pack_path (str): Pack to read.
        sources (List[Tuple[str, str]]): `(pack-relative path, "folder" or "file")` pairs.
        dest (str): Local destination. Files keep their pack-relative paths under it.
    """
    stat = os.stat(pack_path)
    stamp = f"{stat.st_size}:{stat.st_mtime_ns}:{sorted(sources)}"
    stamp_path = os.path.join(dest, ART_STAMP)
    if os.path.exists(stamp_path):
        with open(stamp_path, encoding="utf-8") as f:
            if f.read() == stamp:
                return
    for source, kind in sources:
        cached_pack_extract(pack_path, source, dest, source_kind=kind, tables_as_tsv=False)
    os.makedirs(dest, exist_ok=True)
    with open(stamp_path, "w", encoding="utf-8") as f:
        f.write(stamp)


def extract_art(card_packs: Dict[str, List[str]]) -> Dict[str, str]:
    """Extract the browser's art: unit cards, ability and category icons, race banners, card skins and the TTC gem overlays.

    Args:
        card_packs (Dict[str, List[str]]): `ttc_cards.card_packs` result, so asset packs outside the supported mods count too.

    Returns:
        Lowercase pack-relative path to local file. A mod's file wins over vanilla, like the game's load order.
    """
    folders = [(folder, "folder") for folder in ART_FOLDERS]
    jobs = [(os.path.join(GAME_DATA_DIR, "ui.pack"), "vanilla", folders), (os.path.join(GAME_DATA_DIR, "ui2.pack"), "vanilla_skins", [(path, "file") for path in SKIN_FILES])]
    jobs.append((ttc_data.BASE_TTC_PACK, "ttc", [(TTC_ART_FOLDER, "folder")]))
    jobs += [(mod["path"], ttc_data.pack_tag(mod["package_name"]), folders) for mod in ttc_data.installed_mods()]
    # Card folders are extracted with the pack's own spelling, since rpfm extraction is case-sensitive.
    for path, files in card_packs.items():
        card_folders = sorted({os.path.dirname(file) for file in files})
        jobs.append((path, f"cards_{os.path.basename(os.path.dirname(path))}_{os.path.basename(path)[:-len('.pack')]}", [(folder, "folder") for folder in card_folders]))
    art: Dict[str, str] = {}
    for pack_path, tag, sources in jobs:
        if not os.path.exists(pack_path):
            continue
        dest = os.path.join(ART_DIR, tag)
        _extract_once(pack_path, sources, dest)
        for path in glob.glob(os.path.join(dest, "**", "*.png"), recursive=True):
            art[os.path.relpath(path, dest).replace(os.sep, "/").lower()] = path
    return art


def parse_script_unlocks(text: str, building_keys: set) -> Dict[str, List[str]]:
    """Read which building levels unlock which units in a mod script that fills a mercenary pool per building tier.

    Args:
        text (str): Lua source.
        building_keys (set): Known building level keys, so only real buildings count as tiers.

    Returns:
        Unit key to the building levels whose construction adds it to the pool. Empty when the script does not follow the pattern.
    """
    if SCRIPT_POOL_CALL not in text:
        return {}
    buildings_by_tier: Dict[str, List[str]] = {}
    for building, tier in SCRIPT_BUILDING_TIER.findall(text):
        if building in building_keys:
            buildings_by_tier.setdefault(tier, []).append(building)
    tables = {name: SCRIPT_UNIT_ENTRY.findall(body) for name, body in SCRIPT_TABLE.findall(text)}
    unlocks: Dict[str, List[str]] = {}
    for tier, table in SCRIPT_TIER_TABLE.findall(text):
        for unit in tables.get(table, []):
            for building in buildings_by_tier.get(tier, []):
                unlocks.setdefault(unit, []).append(building)
    return unlocks


def load_script_unlocks(building_keys: set) -> Dict[str, List[str]]:
    """Read script-driven building unlocks from every installed supported mod's campaign scripts.

    Args:
        building_keys (set): Known building level keys.

    Returns:
        Unit key to the building levels that unlock it through a script.
    """
    unlocks: Dict[str, List[str]] = {}
    for mod in ttc_data.installed_mods():
        with extracted_tree(mod["path"], SCRIPT_FOLDER, tables_as_tsv=False) as folder:
            for path in glob.glob(os.path.join(folder, "**", "*.lua"), recursive=True) if folder else []:
                with open(path, encoding="utf-8", errors="replace") as f:
                    for unit, buildings in parse_script_unlocks(f.read(), building_keys).items():
                        unlocks.setdefault(unit, []).extend(b for b in buildings if b not in unlocks[unit])
    return unlocks


def label_source(source: str) -> str:
    """Name where an existing cap came from, from `TtcData.label_sources`.

    Args:
        source (str): `vanilla:<faction>`, a hand file name or `mod:<package>`.

    Returns:
        `base` (the TTC mod's own list), `hand` or `mod`.
    """
    if source.startswith("vanilla:"):
        return "base"
    return "mod" if source.startswith("mod:") else "hand"


class UnitCatalog:
    """Stats, abilities, art and roster placement for every loaded unit, looked up the way the in-game browser shows them."""

    # Unit key to stats from `ttc_data`.
    stats: Dict[str, ttc_data.UnitStats]
    # Loc key to text: unit, ability, culture and category names.
    loc: Dict[str, str]
    # Lowercase pack-relative art path to local file.
    art: Dict[str, str]
    # Battle entity key to row.
    entities: Dict[str, Dict[str, str]]
    # Melee weapon key to row.
    weapons: Dict[str, Dict[str, str]]
    # Armour type key to row.
    armour: Dict[str, Dict[str, str]]
    # Mount key to row.
    mounts: Dict[str, Dict[str, str]]
    # Battlefield engine key to row.
    engines: Dict[str, Dict[str, str]]
    # Unit key to the card name its first `unit_variants_tables` row uses.
    unit_cards: Dict[str, str]
    # Ability key to row.
    abilities: Dict[str, Dict[str, str]]
    # Land unit key to its ability keys.
    unit_abilities: Dict[str, List[str]]
    # `ui_unit_group_land` key to its grouping row (icon and parent category).
    groupings: Dict[str, Dict[str, str]]
    # Parent category key to its row (icon and order).
    parents: Dict[str, Dict[str, str]]
    # Unit key to the building levels that unlock it, rogue army settlements left out.
    unit_buildings: Dict[str, List[str]]
    # Unit key to the building levels that unlock it through a mod script instead of `building_units_allowed_tables`.
    script_buildings: Dict[str, List[str]]
    # Building level key to its `building_levels_tables` row (chain and 0-based level).
    building_levels: Dict[str, Dict[str, str]]
    # Building level key to its first `building_culture_variants_tables` row (icon).
    building_variants: Dict[str, Dict[str, str]]
    # Culture key to the units its factions can field in custom battle, each with whether it is campaign-exclusive for every faction.
    culture_units: Dict[str, Dict[str, bool]]

    def __init__(
        self,
        stats: Dict[str, ttc_data.UnitStats],
        loc: Dict[str, str],
        tables: Dict[str, List[Dict[str, str]]],
        art: Dict[str, str],
        unit_cards: Optional[Dict[str, str]] = None,
        script_buildings: Optional[Dict[str, List[str]]] = None,
    ):
        """Index the tables.

        Args:
            stats (Dict[str, ttc_data.UnitStats]): Unit key to stats.
            loc (Dict[str, str]): Loc key to text.
            tables (Dict[str, List[Dict[str, str]]]): `DETAIL_TABLES` rows, vanilla first.
            art (Dict[str, str]): Lowercase pack-relative art path to local file.
            unit_cards (Optional[Dict[str, str]]): Unit key to its variant card name, from `TtcData.unit_cards`.
            script_buildings (Optional[Dict[str, List[str]]]): Unit key to building levels that unlock it through a mod script.
        """
        self.stats, self.loc, self.art, self.unit_cards, self.script_buildings = stats, loc, art, unit_cards or {}, script_buildings or {}
        self.entities = _index(tables["battle_entities_tables"])
        self.weapons = _index(tables["melee_weapons_tables"])
        self.armour = _index(tables["unit_armour_types_tables"])
        self.mounts = _index(tables["mounts_tables"])
        self.engines = _index(tables["battlefield_engines_tables"])
        self.abilities = _index(tables["unit_abilities_tables"])
        self.groupings = _index(tables["ui_unit_groupings_tables"])
        self.parents = _index(tables["ui_unit_group_parents_tables"])
        self.building_levels = _index(tables["building_levels_tables"], "level_name")
        self.building_variants = _index(tables["building_culture_variants_tables"], "building")
        self.unit_buildings = {}
        for row in tables["building_units_allowed_tables"]:
            building, key = row.get("building", ""), row.get("unit", "")
            if building and key and ROGUE_BUILDING not in building and ROGUE_BUILDING not in self.building_levels.get(building, {}).get("chain", ""):
                buildings = self.unit_buildings.setdefault(key, [])
                if building not in buildings:
                    buildings.append(building)
        self.unit_abilities = {}
        for row in tables["land_units_to_unit_abilites_junctions_tables"]:
            keys = self.unit_abilities.setdefault(row.get("land_unit", ""), [])
            if row.get("ability") and row["ability"] not in keys:
                keys.append(row["ability"])

        subculture_culture = {row["subculture"]: row["culture"] for row in tables["cultures_subcultures_tables"] if row.get("subculture")}
        faction_culture = {row["key"]: subculture_culture.get(row.get("subculture", "")) for row in tables["factions_tables"] if row.get("key")}
        self.culture_units = {}
        for row in tables["units_custom_battle_permissions_tables"]:
            culture, key = faction_culture.get(row.get("faction", "")), row.get("unit", "")
            if not culture or not self.in_browser(key):
                continue
            units = self.culture_units.setdefault(culture, {})
            # A unit only goes under the Extended Roster when every faction of the culture has it as campaign-exclusive.
            units[key] = units.get(key, True) and row.get("campaign_exclusive") == "true"

    def in_browser(self, key: str) -> bool:
        """Check that a unit belongs in the browser: a loaded land unit that is not a lord or hero.

        Args:
            key (str): Unit key.

        Returns:
            True when the browser shows it.
        """
        unit = self.stats.get(key)
        return bool(unit and unit.land) and unit.main.get("caste") not in ttc_data.EXCLUDED_CASTES

    def culture_name(self, culture: str) -> str:
        """Look up a culture's onscreen name.

        Args:
            culture (str): Culture key, or `OTHER_CULTURE`.

        Returns:
            The name, or the key when no loc text names it.
        """
        if culture == OTHER_CULTURE:
            return "Other"
        return ttc_data.loc_name(CULTURE_NAME_PREFIX, culture, self.loc)

    def art_path(self, folder: str, name: str) -> str:
        """Build the pack-relative path of an art file when some pack ships it.

        Args:
            folder (str): Pack-relative folder.
            name (str): File name without `.png`.

        Returns:
            The lowercase pack-relative path, or an empty string when no pack has it.
        """
        path = f"{folder}/{name}.png".lower()
        return path if name and path in self.art else ""

    def buildings(self, key: str) -> List[dict]:
        """List the buildings that recruit a unit, the lowest tier of each building only, since that is where the unit unlocks.

        Buildings are grouped by their in-game chain name, so a mod's per-province copies of one building (e.g. 22 Barracks chains) show once.

        Args:
            key (str): Unit key.

        Returns:
            `{name, chain, tier, icon, script}` per building, lowest tier first. `tier` counts from 1 like the game shows it. `name` is empty when no
            loc text names the building level. `script` marks a building that unlocks the unit through a mod script.
        """
        groups: Dict[str, dict] = {}
        sources = [(b, False) for b in self.unit_buildings.get(key, [])] + [(b, True) for b in self.script_buildings.get(key, [])]
        for building, script in sources:
            level = self.building_levels.get(building, {})
            chain = level.get("chain") or building
            chain_name = ttc_data.loc_name(BUILDING_CHAIN_NAME_PREFIX, chain, self.loc)
            entry = {
                "name": ttc_data.loc_name(BUILDING_NAME_PREFIX, building, self.loc, ""),
                "chain": chain_name,
                "tier": int(parse_number(level.get("level"))) + 1,
                "icon": self.art_path(BUILDING_ICON_FOLDER, self.building_variants.get(building, {}).get("icon", "")),
                "script": script,
            }
            best = groups.get(chain_name)
            # The lowest tier wins, then a copy with a translated name. Any copy's icon fills a gap.
            if best is None or (entry["tier"], not entry["name"]) < (best["tier"], not best["name"]):
                entry["icon"] = entry["icon"] or (best or {}).get("icon", "")
                groups[chain_name] = entry
            elif not best["icon"]:
                best["icon"] = entry["icon"]
        return sorted(groups.values(), key=lambda entry: (entry["tier"], entry["chain"]))

    def section_name(self, section: str) -> str:
        """Look up a category section's onscreen name.

        Args:
            section (str): Parent category key.

        Returns:
            The name, or the key when no loc text names it.
        """
        return ttc_data.loc_name(GROUP_PARENT_NAME_PREFIX, section, self.loc)

    def card_path(self, key: str) -> str:
        """Find a unit's card art.

        Args:
            key (str): Unit key.

        Returns:
            Pack-relative path of the card, or an empty string when no pack ships one.
        """
        return next((path for name in ttc_cards.card_candidates(key, self.stats, self.unit_cards) if (path := self.art_path(CARD_FOLDER, name))), "")

    def section(self, key: str, exclusive: bool) -> str:
        """Find the category section a unit is listed under.

        Args:
            key (str): Unit key.
            exclusive (bool): Whether the unit is campaign-exclusive for its culture.

        Returns:
            The parent category key, or an empty string when the unit has none.
        """
        if exclusive:
            return EXTENDED_ROSTER
        return self.groupings.get(self.stats[key].main.get("ui_unit_group_land", ""), {}).get("parent_group", "")

    def card(self, key: str) -> dict:
        """Build what a unit card in the roster shows.

        Args:
            key (str): Unit key.

        Returns:
            Name, card art, category icon, renown flag and cost.
        """
        main = self.stats[key].main
        icon = self.groupings.get(main.get("ui_unit_group_land", ""), {}).get("icon", "")
        return {
            "name": ttc_data.unit_name(key, self.stats, self.loc),
            "card": self.card_path(key),
            "icon": self.art_path(CATEGORY_ICON_FOLDER, icon),
            "renown": main.get("is_renown") == "true",
            "cost": int(parse_number(main.get("multiplayer_cost"))),
        }

    def details(self, key: str) -> dict:
        """Build the in-game panel numbers for one unit.

        HP is the man entity's hit points plus `bonus_hit_points`, times the number of men, plus the mount and engine entities' hit points. That matches
        the panel exactly for infantry and monsters. Speed is the mount's run speed when the unit has one, shown x10 like the panel.

        Args:
            key (str): Unit key.

        Returns:
            Name, card art, panel stats, abilities and the buildings that recruit it.
        """
        unit = self.stats.get(key)
        main, land = (unit.main, unit.land) if unit else ({}, {})
        man = self.entities.get(land.get("man_entity", ""), {})
        mount = self.entities.get(self.mounts.get(land.get("mount", ""), {}).get("entity", ""), {})
        engine = self.entities.get(self.engines.get(land.get("engine", ""), {}).get("battle_entity", ""), {})
        weapon = self.weapons.get(land.get("primary_melee_weapon", ""), {})
        men = int(parse_number(main.get("num_men")))
        hp = (parse_number(man.get("hit_points")) + parse_number(land.get("bonus_hit_points"))) * men
        hp += parse_number(mount.get("hit_points")) * parse_number(land.get("num_mounts")) + parse_number(engine.get("hit_points")) * parse_number(land.get("num_engines"))
        abilities = []
        for ability in self.unit_abilities.get(land.get("key", ""), []):
            row = self.abilities.get(ability, {})
            if row.get("is_hidden_in_ui") == "true":
                continue
            name = ttc_data.loc_name(ABILITY_NAME_PREFIX, ability, self.loc)
            abilities.append({"key": ability, "name": name, "icon": self.art_path(ABILITY_FOLDER, row.get("icon_name", ""))})
        return {
            "key": key,
            "name": ttc_data.unit_name(key, self.stats, self.loc),
            "card": self.card_path(key),
            "cost": main.get("multiplayer_cost", ""),
            "caste": main.get("caste", ""),
            "class": land.get("class", ""),
            "hp_estimate": bool(mount or engine),
            "stats": {
                "hp": round(hp),
                "tier": int(parse_number(main.get("tier"))),
                "men": men,
                "armour": int(parse_number(self.armour.get(land.get("armour", ""), {}).get("armour_value"))),
                "leadership": int(parse_number(land.get("morale"))),
                "speed": round(parse_number((mount or man).get("run_speed")) * 10),
                "melee_attack": int(parse_number(land.get("melee_attack"))),
                "melee_defence": int(parse_number(land.get("melee_defence"))),
                "weapon_strength": int(parse_number(weapon.get("damage")) + parse_number(weapon.get("ap_damage"))),
                "charge_bonus": int(parse_number(land.get("charge_bonus"))),
            },
            "abilities": abilities,
            "buildings": self.buildings(key),
        }


class ReviewSession:
    """The browser's rosters and caps, and writing confirmed or changed auto picks to the hand files."""

    # Unit details, art and roster placement.
    catalog: UnitCatalog
    # Unit key to `(label, source)` for caps that are not auto picks: `base`, `hand` or `mod`.
    labels: Dict[str, Tuple[str, str]]
    # Unit key to its auto pick record from `update_ttc_compat.py`, for picks not saved to a hand file yet.
    picks: Dict[str, dict]
    # Package name to its existing hand file path.
    hand_paths: Dict[str, str]
    # Unit key to the display name of the mod that adds it, or `ttc_data.VANILLA_NAME` for base game units.
    owners: Dict[str, str]
    # Culture key to unit key to whether it is campaign-exclusive, including auto picks that no custom battle permission lists.
    rosters: Dict[str, Dict[str, bool]]
    # Number of picks saved this session.
    saved: int
    # Units without card art in any pack, which the browser hides like the generator ignores them. Empty when some pack could not be listed.
    cardless: Set[str]
    # Unit key to its built panel details, filled on first use.
    details: Dict[str, dict]

    def __init__(
        self,
        catalog: UnitCatalog,
        labels: Dict[str, Tuple[str, str]],
        picks: Dict[str, dict],
        hand_paths: Dict[str, str],
        owners: Dict[str, str],
        cardless: Optional[Set[str]] = None,
    ):
        """Hold the session state and place auto picks the custom battle permissions miss.

        Args:
            catalog (UnitCatalog): Unit details.
            labels (Dict[str, Tuple[str, str]]): Unit key to `(label, source)` for existing caps.
            picks (Dict[str, dict]): Unit key to auto pick record.
            hand_paths (Dict[str, str]): Package name to its existing hand file path.
            owners (Dict[str, str]): Unit key to the display name of the mod that adds it.
            cardless (Optional[Set[str]]): Units to hide because no pack has card art for them.
        """
        self.catalog, self.labels, self.picks, self.hand_paths, self.owners, self.saved, self.details = catalog, labels, picks, hand_paths, owners, 0, {}
        self.cardless = cardless or set()
        self.rosters = {culture: dict(units) for culture, units in catalog.culture_units.items()}
        listed = {key for units in self.rosters.values() for key in units}
        # The race code in a culture key names its faction, e.g. `wh_dlc05_wef_wood_elves` is Wood Elves.
        culture_by_faction = {}
        for culture in sorted(catalog.culture_units):
            culture_by_faction.setdefault(ttc_data.faction_of(culture), culture)
        for key, pick in picks.items():
            if key not in listed and catalog.in_browser(key):
                culture = culture_by_faction.get(pick["faction"], OTHER_CULTURE)
                self.rosters.setdefault(culture, {})[key] = False

    def cap(self, key: str) -> dict:
        """Describe a unit's current cap.

        Args:
            key (str): Unit key.

        Returns:
            `label` (or None), `source` (`base`, `hand`, `mod`, `auto`, or None), and `review` for a low-confidence auto pick.
        """
        if key in self.picks:
            return {"label": self.picks[key]["pick"], "source": "auto", "review": not self.picks[key]["confident"]}
        label, source = self.labels.get(key, (None, None))
        return {"label": label, "source": source, "review": False}

    def state(self) -> dict:
        """Build the page state.

        Returns:
            Cultures with their sections in browser order, a card per listed unit, and the save count.
        """
        cultures, units = [], {}
        for culture in sorted(self.rosters, key=self.catalog.culture_name):
            sections: Dict[str, List[str]] = {}
            for key, exclusive in self.rosters[culture].items():
                # A unit no pack has card art for is unfinished, and the generator ignores it too.
                if key in self.cardless:
                    continue
                section = self.catalog.section(key, exclusive)
                if not section or section in SKIPPED_SECTIONS:
                    if key not in self.picks:
                        continue
                    section = UNSORTED
                sections.setdefault(section, []).append(key)
                units.setdefault(key, {**self.catalog.card(key), **self.cap(key), "mod": self.owners.get(key, "")})
            if not sections:
                continue
            order = sorted(sections, key=lambda s: (UNSORTED_ORDER if s == UNSORTED else int(parse_number(self.catalog.parents.get(s, {}).get("order"))), s))
            cultures.append(
                {
                    "key": culture,
                    "name": self.catalog.culture_name(culture),
                    "banner": self.catalog.art_path(RACE_STRIP_FOLDER, f"{culture}_large"),
                    "sections": [
                        {
                            "key": section,
                            "name": "Unsorted" if section == UNSORTED else self.catalog.section_name(section),
                            "icon": self.catalog.art_path(CATEGORY_ICON_FOLDER, self.catalog.parents.get(section, {}).get("icon", "")),
                            # Regiments of Renown sit after the regular units, then cheapest first like the in-game roster.
                            "units": sorted(sections[section], key=lambda k: (units[k]["renown"], units[k]["cost"], units[k]["name"])),
                        }
                        for section in order
                    ],
                }
            )
        return {"cultures": cultures, "units": units, "saved": self.saved}

    def unit(self, key: str) -> dict:
        """Build the unit panel for one unit, with its cap and, for an auto pick, the pick details and lookalikes.

        Args:
            key (str): Unit key.

        Returns:
            Panel details plus `cap` and, for auto picks, `pick`.

        Raises:
            KeyError: No loaded unit has this key.
        """
        if key not in self.catalog.stats:
            raise KeyError(key)
        if key not in self.details:
            self.details[key] = self.catalog.details(key)
        result = {**self.details[key], "cap": self.cap(key)}
        pick = self.picks.get(key)
        if pick:
            lookalikes = [{"key": k, "label": label, "name": ttc_data.unit_name(k, self.catalog.stats, self.catalog.loc)} for k, label in pick["lookalikes"]]
            result["pick"] = {field: pick[field] for field in ("mod", "pick", "confident", "confidence", "runner_up")} | {"lookalikes": lookalikes}
        return result

    def save(self, changes: List[dict]) -> List[str]:
        """Write picks to each mod's hand file under the unit's faction comment.

        Args:
            changes (List[dict]): `{key, category, weight}` per unit. `weight` is ignored for `core`.

        Returns:
            Names of the hand files written.

        Raises:
            ValueError: A change names a unit without an auto pick, or an unknown category or weight.
        """
        # Hand file path to `(mod name for a new file's header, faction to entries)`.
        files: Dict[str, Tuple[str, Dict[str, List[Tuple[str, str, Optional[int]]]]]] = {}
        labels = {}
        for change in changes:
            pick = self.picks.get(change.get("key"))
            category, weight = change.get("category"), change.get("weight")
            if pick is None:
                raise ValueError(f"{change.get('key')} has no auto pick to confirm.")
            if category not in CATEGORIES:
                raise ValueError(f"{pick['key']}: unknown category {category}.")
            if category == "core":
                weight = None
            elif not isinstance(weight, int) or not 1 <= weight <= MAX_WEIGHT:
                raise ValueError(f"{pick['key']}: weight must be 1-{MAX_WEIGHT}.")
            path = self.hand_paths.get(pick["package"]) or ttc_compat_io.hand_file_path(pick["package"])
            files.setdefault(path, (pick["mod"], {}))[1].setdefault(pick["faction"], []).append((pick["key"], category, weight))
            labels[pick["key"]] = ttc_data.label_of(category, weight)
        for path, (header, groups) in files.items():
            ttc_compat_io.add_entries(path, header, groups)
            entries = sum(len(entries) for entries in groups.values())
            logging.info(f"TTC review: wrote {entries} entries to {os.path.basename(path)}.")
        for key, label in labels.items():
            del self.picks[key]
            self.labels[key] = (label, "hand")
        self.saved += len(labels)
        return sorted(os.path.basename(path) for path in files)


def load_session() -> ReviewSession:
    """Load the auto picks, unit tables, loc names and art.

    Returns:
        A ready session.

    Raises:
        FileNotFoundError: `update_ttc_compat.py` has not written the auto picks yet.
    """
    records = delta._read_json(AUTO_PICKS_PATH)
    if records is None:
        raise FileNotFoundError(f"{AUTO_PICKS_PATH} is missing. Run `python update.py` or `python -m generators.update_ttc_compat` first.")
    data = ttc_data.load_all()
    picks = {record["key"]: record for record in records if record["key"] not in data.labels}
    labels = {key: (label, label_source(data.label_sources.get(key, ""))) for key, label in data.labels.items()}
    logging.info(f"TTC review: {len(picks)} auto picks ({sum(not p['confident'] for p in picks.values())} to review), {len(labels)} existing caps.")
    # `mod_names` includes the vanilla package, so `!!!!!!!vanilla.lua` maps too.
    package_names = list(data.mod_names)
    hand_paths = {}
    for path in ttc_compat_io.hand_files():
        package = ttc_data.hand_file_mod(path, package_names)
        if package:
            hand_paths.setdefault(package, path)
    tables = load_detail_tables()
    packs = ttc_cards.card_packs()
    cardless = ttc_cards.cardless_units(data, packs)
    art = extract_art(packs or {})
    logging.info(f"TTC review: {len(art)} art files ready.")
    # Vanilla wins over a mod that overrides a base game unit, then the first supported mod that defines a unit adds it.
    owners = dict.fromkeys(data.vanilla_keys, ttc_data.VANILLA_NAME)
    for package, keys in data.units_by_mod.items():
        for key in keys:
            owners.setdefault(key, data.mod_names.get(package, package))
    script_buildings = load_script_unlocks({row["level_name"] for row in tables["building_levels_tables"] if row.get("level_name")})
    logging.info(f"TTC review: {len(script_buildings)} units unlocked by building scripts.")
    unit_catalog = UnitCatalog(data.stats, ttc_data.load_loc_names(LOC_PREFIXES), tables, art, data.unit_cards, script_buildings)
    return ReviewSession(unit_catalog, labels, picks, hand_paths, owners, cardless)
