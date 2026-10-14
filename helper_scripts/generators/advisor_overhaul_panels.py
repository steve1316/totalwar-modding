"""Builds the modding workbench's unit panels for the Advisor's forms and their vanilla equivalents, laid out like the in-game unit panel.

Each weapon in the registry names a vanilla unit per mount (`vanilla`) to compare against. The numbers come from `ttc.unit_panel`, the same code the
TTC unit browser uses, fed with the mod's generated tables over the vanilla ones. The card art, ability icons and stat icons each panel shows are
copied into the gallery's `art/` folder. Called by `generators.advisor_overhaul_gallery`.
"""

import os
import re
from typing import Dict, List, Tuple

from core.asset_source import AssetSource, norm
from core.extract_cache import extracted_tree
from core.utilities import extract_tsv_data, load_tsv_data
from generators.advisor_overhaul import MOD, STAT_COLUMNS, pairs, unit_key
from tools.ttc_review.catalog import ABILITY_FOLDER, ABILITY_NAME_PREFIX, SKIN_FILES
from ttc.ttc_cards import CARD_FOLDER
from ttc.ttc_data import LOC_NAME_PREFIX, VANILLA_LOC_PACK, loc_name, read_loc_names
from ttc.unit_panel import PANEL_TABLES, PanelTables, index_rows, panel_stats, visible_abilities

# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Settings

# Unit tables read next to `PANEL_TABLES`.
UNIT_TABLES = ["main_units_tables", "land_units_tables", "unit_variants_tables", "unit_attributes_to_groups_junctions_tables"]

# Loc prefix of an attribute's bullet text: its name, then `||` and its tooltip.
ATTRIBUTE_PREFIX = "unit_attributes_bullet_text_"

# Loc prefixes the panels read.
LOC_PREFIXES = (LOC_NAME_PREFIX, ABILITY_NAME_PREFIX, ATTRIBUTE_PREFIX)

# Vanilla packs holding the card art, ability icons and stat icons.
UI_PACKS = re.compile(r"^ui2?\.pack$")

# Gallery folder the art is copied into, mirroring the pack paths.
ART_FOLDER = "art"

# Melee weapon and projectile columns the Edit tab shows.
MELEE_COLUMNS = ["damage", "ap_damage", "bonus_v_large", "bonus_v_infantry"]
PROJECTILE_COLUMNS = ["damage", "ap_damage", "effective_range", "base_reload_time"]


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Data


def load_tables() -> Dict[str, List[Dict[str, str]]]:
    """The panel and unit tables: the mod's generated rows first, so they win, then vanilla's.

    Returns:
        Dict[str, List[Dict[str, str]]]: Rows by table.
    """
    tables = {}
    for table in PANEL_TABLES + UNIT_TABLES:
        mod = []
        for name in sorted(os.listdir(os.path.join(MOD, "db", table))) if os.path.isdir(os.path.join(MOD, "db", table)) else []:
            mod += load_tsv_data(os.path.join(MOD, "db", table, name))[0]
        tables[table] = mod + load_tsv_data(f"{extract_tsv_data(table)}/db/{table}/data__.tsv")[0]
    return tables


def load_loc() -> Dict[str, str]:
    """Unit, ability and attribute texts: the mod's first, then vanilla's.

    Returns:
        Dict[str, str]: Loc key to text.
    """
    loc: Dict[str, str] = {}
    read_loc_names(os.path.join(MOD, "text"), loc, LOC_PREFIXES)
    with extracted_tree(VANILLA_LOC_PACK, "text") as folder:
        if folder:
            read_loc_names(folder, loc, LOC_PREFIXES)
    return loc


def comparisons(registry: Dict) -> Dict[str, str]:
    """Each Advisor form's unit and the vanilla unit it is compared against.

    Args:
        registry (Dict): The registry.

    Returns:
        Dict[str, str]: Advisor unit key -> vanilla unit key.
    """
    return {unit_key(weapon, mount): registry["weapons"][weapon]["vanilla"][mount] for weapon, mount in pairs(registry)
            if mount in registry["weapons"][weapon].get("vanilla", {})}


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Panels


class PanelBuilder:
    """Builds unit panels and gathers the art they show."""

    # The indexed panel tables.
    tables: PanelTables
    # Unit key to `main_units_tables` row.
    main: Dict[str, Dict[str, str]]
    # Land unit key to `land_units_tables` row.
    land: Dict[str, Dict[str, str]]
    # Unit key to the card name of its first `unit_variants_tables` row.
    cards: Dict[str, str]
    # Attribute group to its attribute keys.
    attributes: Dict[str, List[str]]
    # Loc key to text.
    loc: Dict[str, str]
    # The packs and the mod folder art is read from.
    assets: AssetSource
    # Pack-relative art paths the panels show, lowercase.
    art: List[str]

    def __init__(self, tables: Dict[str, List[Dict[str, str]]], loc: Dict[str, str]):
        """Indexes the tables.

        Args:
            tables (Dict[str, List[Dict[str, str]]]): `PANEL_TABLES` and `UNIT_TABLES` rows, the mod's first.
            loc (Dict[str, str]): Loc key to text.
        """
        self.tables = PanelTables(tables)
        self.main = index_rows(tables["main_units_tables"], "unit")
        self.land = index_rows(tables["land_units_tables"])
        self.cards = {}
        for row in tables["unit_variants_tables"]:
            if row.get("unit_card"):
                self.cards.setdefault(row["unit"], row["unit_card"])
        self.attributes = {}
        for row in tables["unit_attributes_to_groups_junctions_tables"]:
            keys = self.attributes.setdefault(row["attribute_group"], [])
            if row["attribute"] not in keys:
                keys.append(row["attribute"])
        self.loc = loc
        self.assets = AssetSource([MOD], [], UI_PACKS)
        self.art = [f"ui/skins/default/{name}.png" for name in (path.rsplit("/", 1)[-1][:-4] for path in SKIN_FILES)]

    def art_path(self, folder: str, name: str) -> str:
        """The lowercase pack-relative path of an art file when the mod or a vanilla pack has it, noted for copying.

        Args:
            folder (str): Pack-relative folder.
            name (str): File name without `.png`.

        Returns:
            str: The path, or an empty string when none has it.
        """
        path = norm(f"{folder}/{name}.png")
        if not name or (path not in self.assets.index and path not in self.assets.loose):
            return ""
        if path not in self.art:
            self.art.append(path)
        return path

    def panel(self, key: str) -> Dict:
        """One unit's panel.

        Args:
            key (str): Unit key.

        Returns:
            Dict: `key`, `name`, `card`, `caste`, `class`, `hp_estimate`, `stats`, `abilities` and `attributes` (each with `key`, `name`, `text`).
        """
        main = self.main[key]
        land = self.land[main["land_unit"]]
        stats, hp_estimate = panel_stats(main, land, self.tables)
        card = next((path for name in (self.cards.get(key), key, main["land_unit"]) if name and (path := self.art_path(CARD_FOLDER, name))), "")
        attributes = []
        for attribute in self.attributes.get(land.get("attribute_group", ""), []):
            name, _, text = loc_name(ATTRIBUTE_PREFIX, attribute, self.loc).partition("||")
            attributes.append({"key": attribute, "name": name, "text": text})
        return {
            "key": key, "name": loc_name(LOC_NAME_PREFIX, main["land_unit"], self.loc), "card": card, "caste": main.get("caste", ""),
            "class": land.get("class", ""), "hp_estimate": hp_estimate, "stats": stats,
            "abilities": [{"key": ability, "name": loc_name(ABILITY_NAME_PREFIX, ability, self.loc), "icon": self.art_path(ABILITY_FOLDER, icon)}
                          for ability, icon in visible_abilities(land["key"], self.tables)],
            "attributes": attributes,
        }

    def form_values(self, key: str, weapon_key: str, mount_key: str, registry: Dict) -> Dict:
        """The values an Advisor form's Edit tab starts from: its land unit stats, armour value, melee weapon and missile values as built, and
        which of them its own form overrides.

        Args:
            key (str): The form's unit key.
            weapon_key (str): Its weapon.
            mount_key (str): Its mount.
            registry (Dict): The registry.

        Returns:
            Dict: `weapon`, `mount`, `stats` (`STAT_COLUMNS` and `armour`), `melee` (with its current `key`), `melee_template`, `own_melee` (whether
            the weapon has its own melee weapon yet), `missile` (or None, with `ammo`), `overrides` (the fields its form sets), and the weapon's
            `attributes` and `attributes_removed`.
        """
        land = self.land[self.main[key]["land_unit"]]
        num = lambda value: float(value) if value not in ("", None) else 0.0
        stats = {c: num(land.get(c)) for c in STAT_COLUMNS}
        stats["armour"] = num(self.tables.armour.get(land["armour"], {}).get("armour_value"))
        melee_row = self.tables.weapons.get(land["primary_melee_weapon"], {})
        missile = None
        if land.get("primary_missile_weapon"):
            projectile = self.tables.projectiles.get(self.tables.missile_weapons.get(land["primary_missile_weapon"], {}).get("default_projectile", ""), {})
            missile = dict({c: num(projectile.get(c)) for c in PROJECTILE_COLUMNS}, ammo=num(land.get("primary_ammo")))
        weapon = registry["weapons"][weapon_key]
        return {"weapon": weapon_key, "mount": mount_key, "stats": stats, "melee": dict({c: num(melee_row.get(c)) for c in MELEE_COLUMNS}, key=land["primary_melee_weapon"]),
                "melee_template": weapon.get("melee", {}).get("template", land["primary_melee_weapon"]), "own_melee": "melee" in weapon, "missile": missile,
                "overrides": sorted(weapon.get("forms", {}).get(mount_key, {})), "attributes": weapon.get("attributes", []),
                "attributes_removed": weapon.get("attributes_removed", [])}

    def attribute_catalog(self) -> Dict[str, Dict[str, str]]:
        """Every unit attribute with an in-game name, for the Edit tab's checklist.

        Returns:
            Dict[str, Dict[str, str]]: Attribute key -> `name` and `text` (its tooltip), sorted by name.
        """
        catalog = {}
        for loc_key in self.loc:
            if loc_key.startswith(ATTRIBUTE_PREFIX):
                name, _, text = loc_name(ATTRIBUTE_PREFIX, loc_key[len(ATTRIBUTE_PREFIX):], self.loc).partition("||")
                if name:
                    catalog[loc_key[len(ATTRIBUTE_PREFIX):]] = {"name": name, "text": text}
        return dict(sorted(catalog.items(), key=lambda item: item[1]["name"]))

    def copy_art(self, out: str) -> int:
        """Copies every noted art file into the gallery's `art/` folder.

        Args:
            out (str): The gallery folder.

        Returns:
            int: How many files were copied.
        """
        files = self.assets.fetch(self.art)
        for path, data in files.items():
            target = os.path.join(out, ART_FOLDER, path)
            os.makedirs(os.path.dirname(target), exist_ok=True)
            with open(target, "wb") as f:
                f.write(data)
        return len(files)


def build_panels(registry: Dict, out: str) -> Tuple[Dict[str, Dict], Dict[str, str], Dict]:
    """The panels of every Advisor form and its vanilla equivalent, with their art copied into the gallery, and the Edit tab's data.

    Args:
        registry (Dict): The registry.
        out (str): The gallery folder.

    Returns:
        Tuple[Dict[str, Dict], Dict[str, str], Dict]: Panels by unit key, Advisor unit key -> vanilla unit key, and the Edit tab's data
        (`forms`: unit key -> `PanelBuilder.form_values`, and `attributes`: the attribute catalog).
    """
    pairs_to_vanilla = comparisons(registry)
    builder = PanelBuilder(load_tables(), load_loc())
    panels = {key: builder.panel(key) for key in list(pairs_to_vanilla) + list(dict.fromkeys(pairs_to_vanilla.values()))}
    editor = {"forms": {unit_key(w, m): builder.form_values(unit_key(w, m), w, m, registry) for w, m in pairs(registry)}, "attributes": builder.attribute_catalog()}
    print(f"panels: {len(panels)} units, {builder.copy_art(out)} art files, {len(editor['attributes'])} attributes")
    return panels, pairs_to_vanilla, editor
