"""Builds the modding workbench's unit panels for the Advisor's forms and their vanilla equivalents, laid out like the in-game unit panel.

Each weapon in the registry names a vanilla unit per mount (`vanilla`) to compare against. The numbers come from `ttc.unit_panel`, the same code the
TTC unit browser uses, fed with the mod's generated tables over the vanilla ones. The card art, ability icons and stat icons each panel shows are
copied into the gallery's `art/` folder. Called by `generators.advisor_overhaul_gallery`.
"""

import json
import os
import re
from typing import Dict, List, Tuple

from core.asset_source import AssetSource, norm
from core.extract_cache import extracted_tree
from core.utilities import extract_tsv_data, load_tsv_data
from generators.advisor_overhaul import DATA, LORE_LEVELS, MOD, STAT_COLUMNS, fixed_skills, pairs, unit_key
from tools.glf_rebuild_animpack import AnimSet
from tools.skill_catalog import CATALOG_LOC_PREFIXES, SKILL_CATALOG_TABLES, SKILL_ICON_FOLDER, catalog_art, skill_catalog
from tools.ttc_review.catalog import ABILITY_FOLDER, ABILITY_NAME_PREFIX, SKIN_FILES
from ttc.ttc_cards import CARD_FOLDER
from ttc.ttc_data import LOC_NAME_PREFIX, VANILLA_LOC_PACK, loc_name, read_loc_names
from ttc.unit_panel import PANEL_TABLES, TOOLTIP_LOC_PREFIXES, PanelTables, ability_tooltip, attribute_tooltip, index_rows, panel_stats, tooltip_images, visible_abilities

# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Settings

# Unit tables read next to `PANEL_TABLES`.
UNIT_TABLES = ["main_units_tables", "land_units_tables", "unit_variants_tables", "unit_attributes_to_groups_junctions_tables"]

# Loc prefix of an attribute's bullet text: its name, then `||` and its tooltip.
ATTRIBUTE_PREFIX = "unit_attributes_bullet_text_"

# Loc prefix of a faction's name.
FACTION_NAME_PREFIX = "factions_screen_name_"

# Loc prefixes the panels read: names, everything the ability and attribute tooltips show, and faction names.
LOC_PREFIXES = (LOC_NAME_PREFIX, ABILITY_NAME_PREFIX, ATTRIBUTE_PREFIX, *TOOLTIP_LOC_PREFIXES, *CATALOG_LOC_PREFIXES, FACTION_NAME_PREFIX)

# The faction whose uniform colours the workbench shows first: Reikland, the Advisor's home.
DEFAULT_FACTION = "wh_main_emp_empire"

# Names of his ten skill tree rows, top to bottom, for the Skills tab.
SKILL_ROWS = ["Weapons", "Mounts", "Arts", "Memory", "Winds", "Elsewhere", "Martial", "Civic", "Pact", "Spare"]

# Columns of `factions_tables` holding a faction's three uniform colours (hex), in the order of the mask's red, green and blue channels.
UNIFORM_COLUMNS = ("uniform_colour_primary", "uniform_colour_secondary", "uniform_colour_tertiary")

# Vanilla packs holding the card art, ability icons and stat icons.
UI_PACKS = re.compile(r"^ui2?\.pack$")

# Gallery folder the art is copied into, mirroring the pack paths.
ART_FOLDER = "art"

# Packs and folders the weapon model picker lists.
PROP_PACKS = re.compile(r"^variants\d*\.pack$")
PROP_FOLDER = re.compile(r"/wh_variantmodels/.*/[^/]*props[^/]*/")

# The folder of the humanoid01 models the Look tab picks outfits and pieces from. Props and dismemberment stumps are left out.
LOOK_FOLDER = re.compile(r"/wh_variantmodels/hu1/")
LOOK_SKIPPED = re.compile(r"blood_pack")

# The skeleton every form's set must be on. A set on another skeleton needs retargeting first.
FORM_SKELETON = "humanoid01"

# Units the New form dialog names for each set at most.
SET_USERS = 4

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


def faction_colours(loc: Dict[str, str]) -> Dict:
    """The uniform colours of every faction the Advisor joins, for the workbench's faction picker. Factions sharing a name (a campaign's copies)
    are listed once, under the shortest key.

    Args:
        loc (Dict[str, str]): Loc key to text, with the faction names.

    Returns:
        Dict: `default` (a faction key) and `factions`: [key, name, [three hex colours]] each, by name.
    """
    joins = set(json.load(open(DATA, encoding="utf-8"))["factions"])
    rows = load_tsv_data(f"{extract_tsv_data('factions_tables')}/db/factions_tables/data__.tsv")[0]
    named: Dict[str, list] = {}
    for row in sorted((r for r in rows if r["key"] in joins), key=lambda r: (len(r["key"]), r["key"])):
        name = loc.get(FACTION_NAME_PREFIX + row["key"])
        if name and all(len(row[c]) == 6 for c in UNIFORM_COLUMNS):
            named.setdefault(name, [row["key"], name, [row[c] for c in UNIFORM_COLUMNS]])
    return {"default": DEFAULT_FACTION, "factions": sorted(named.values(), key=lambda f: f[1])}


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

    def note_art(self, path: str) -> str:
        """Notes a lowercase pack path for copying when the mod or a vanilla pack has it.

        Args:
            path (str): The pack path.

        Returns:
            str: The path, or an empty string when none has it.
        """
        path = norm(path)
        if path not in self.assets.index and path not in self.assets.loose:
            return ""
        if path not in self.art:
            self.art.append(path)
        return path

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
        # Attributes the game gives no text are not shown in game either.
        attributes = [tip for tip in (self.attribute(a) for a in self.attributes.get(land.get("attribute_group", ""), [])) if tip["name"]]
        abilities = []
        for ability, icon in visible_abilities(land["key"], self.tables):
            tip = ability_tooltip(ability, self.tables, self.loc)
            abilities.append({"key": ability, "name": loc_name(ABILITY_NAME_PREFIX, ability, self.loc), "icon": self.art_path(ABILITY_FOLDER, icon), "tip": tip})
        # The icons the tooltips show inline.
        for tip in [a["tip"] for a in abilities] + attributes:
            for path in tooltip_images(tip):
                self.note_art(path)
        return {
            "key": key, "name": loc_name(LOC_NAME_PREFIX, main["land_unit"], self.loc), "card": card, "caste": main.get("caste", ""),
            "class": land.get("class", ""), "hp_estimate": hp_estimate, "stats": stats,
            "abilities": abilities, "attributes": attributes,
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
            `attributes`, `attributes_removed`, `abilities` and `abilities_removed`, `props` (prop slot -> [bone, model, metadata] as the form uses
            them), `prop_overrides` (the slots its form sets), `mount_props` (the slots its mount fills, such as the disc) and `look` (the
            weapon's `body`, `hood` and `pieces`, shared by all its mounts).
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
                "overrides": sorted(k for k in weapon.get("forms", {}).get(mount_key, {}) if k != "props"), "attributes": weapon.get("attributes", []),
                "props": dict(weapon["props"], **registry["mounts"][mount_key].get("variant_props", {}), **weapon.get("forms", {}).get(mount_key, {}).get("props", {})),
                "prop_overrides": sorted(weapon.get("forms", {}).get(mount_key, {}).get("props", {})),
                "mount_props": sorted(registry["mounts"][mount_key].get("variant_props", {})),
                "look": {"body": weapon.get("body", registry["model"]["body"]), "hood": weapon.get("hood", registry["model"]["hood"]), "pieces": weapon.get("pieces", {}),
                         "piece_shapes": weapon.get("piece_shapes", {})},
                "attributes_removed": weapon.get("attributes_removed", []), "abilities": weapon.get("abilities", []),
                "abilities_removed": weapon.get("abilities_removed", [])}

    def attribute(self, key: str) -> Dict[str, str]:
        """An attribute's tooltip with its icon, which the game keeps next to the ability icons under the attribute's key.

        Args:
            key (str): The attribute key.

        Returns:
            Dict[str, str]: `key`, `name`, `text` and `icon` (empty when the game has none).
        """
        return dict(attribute_tooltip(key, self.loc, self.tables), icon=self.art_path(ABILITY_FOLDER, key))

    def attribute_catalog(self) -> Dict[str, Dict[str, str]]:
        """Every unit attribute with an in-game name, for the Stats tab's "+ Attribute" picker.

        Returns:
            Dict[str, Dict[str, str]]: Attribute key -> `name`, `text` (its tooltip) and `icon`, sorted by name.
        """
        catalog = {}
        for loc_key in self.loc:
            if loc_key.startswith(ATTRIBUTE_PREFIX):
                tip = self.attribute(loc_key[len(ATTRIBUTE_PREFIX):])
                if tip["name"]:
                    catalog[tip["key"]] = {"name": tip["name"], "text": tip["text"], "icon": tip["icon"]}
                    for path in tooltip_images(tip):
                        self.note_art(path)
        return dict(sorted(catalog.items(), key=lambda item: item[1]["name"]))

    def ability_catalog(self) -> Dict[str, Dict]:
        """Every ability the game gives a land unit directly and shows in the UI, for the Stats tab's "+ Ability" picker.

        Returns:
            Dict[str, Dict]: Ability key -> `name`, `icon` and `tip` (as on a panel), sorted by name.
        """
        catalog = {}
        for ability in dict.fromkeys(a for linked in self.tables.unit_abilities.values() for a in linked):
            row = self.tables.abilities.get(ability, {})
            name = loc_name(ABILITY_NAME_PREFIX, ability, self.loc) if self.loc.get(ABILITY_NAME_PREFIX + ability) else ""
            if not name or row.get("is_hidden_in_ui") == "true":
                continue
            tip = ability_tooltip(ability, self.tables, self.loc)
            catalog[ability] = {"name": name, "icon": self.art_path(ABILITY_FOLDER, row.get("icon_name", "")), "tip": tip}
            for path in tooltip_images(tip):
                self.note_art(path)
        return dict(sorted(catalog.items(), key=lambda item: item[1]["name"]))

    def new_form_data(self, registry: Dict, sets: Dict[str, AnimSet]) -> Dict:
        """What the workbench's New form dialog picks from: every animation set of a humanoid skeleton with the units that play it, and how each of
        his mounts' sets are recognised.

        Args:
            registry (Dict): The registry.
            sets (Dict[str, AnimSet]): Every vanilla set plus the mod's own, by name.

        Returns:
            Dict: `skeleton` (`FORM_SKELETON`), `sets` ([name, skeleton, mount set, [[unit key, unit name], ...]], sorted by name) and `mounts` (mount
            key -> `name`, `mount` (the mount set its rider sets name, empty on foot) and `word` (a word its set names have, for mounts carried as a
            prop such as the disc, whose sets name no mount set)).
        """
        # The vanilla units that play each set. His own forms are left out.
        users: Dict[str, List[str]] = {}
        own = {unit_key(w, m) for w, m in pairs(registry)}
        for unit, main in self.main.items():
            set_name = self.land.get(main["land_unit"], {}).get("man_animation")
            if set_name and unit not in own:
                users.setdefault(set_name, []).append(unit)
        rows = [[name, s.skeleton, s.mount, [[u, loc_name(LOC_NAME_PREFIX, self.main[u]["land_unit"], self.loc)] for u in users.get(name, [])[:SET_USERS]]]
                for name, s in sorted(sets.items()) if s.skeleton.startswith("humanoid")]
        mounts = {}
        for key, mount in registry["mounts"].items():
            template = sets.get(self.land.get(mount.get("template", ""), {}).get("man_animation", ""))
            word = re.search(r"_wm_([a-z]+)", template.name) if template and not template.mount else None
            mounts[key] = {"name": mount["name"], "mount": template.mount if template else "", "word": word.group(1) if word else ""}
        return {"skeleton": FORM_SKELETON, "sets": rows, "mounts": mounts}

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


def build_panels(registry: Dict, out: str, sets: Dict[str, AnimSet]) -> Tuple[Dict[str, Dict], Dict[str, str], Dict]:
    """The panels of every Advisor form and its vanilla equivalent, with their art copied into the gallery, and the Edit tab's data.

    Args:
        registry (Dict): The registry.
        out (str): The gallery folder.
        sets (Dict[str, AnimSet]): Every vanilla set plus the mod's own, by name, for the New form dialog.

    Returns:
        Tuple[Dict[str, Dict], Dict[str, str], Dict]: Panels by unit key, Advisor unit key -> vanilla unit key, and the Edit and Skills tabs' data
        (`forms`: unit key -> `PanelBuilder.form_values`, `attributes` and `abilities`: the attribute and ability catalogs, `skills`: the skill
        catalog, the fixed weapon and mount skills and the names of their rows, `new_form`: `PanelBuilder.new_form_data`, `prop_models`: the
        weapon models a slot may swap to, `look`: the Look tab's outfits, head and piece models, and `colours`: `faction_colours`).
    """
    pairs_to_vanilla = comparisons(registry)
    builder = PanelBuilder(load_tables(), load_loc())
    panels = {key: builder.panel(key) for key in list(pairs_to_vanilla) + list(dict.fromkeys(pairs_to_vanilla.values()))}
    editor = {"forms": {unit_key(w, m): builder.form_values(unit_key(w, m), w, m, registry) for w, m in pairs(registry)}, "attributes": builder.attribute_catalog(),
              "abilities": builder.ability_catalog()}
    # The Skills tab: the vanilla catalog to pick from, and the weapon and mount skills the tree already has.
    catalog = skill_catalog({t: load_tsv_data(f"{extract_tsv_data(t)}/db/{t}/data__.tsv")[0] for t in SKILL_CATALOG_TABLES}, builder.loc)
    for path in catalog_art(catalog):
        builder.note_art(path)
    # Each fixed skill's points: one for a weapon or mount, one per level for a lore.
    fixed = [{"row": f["row"], "tier": f["tier"], "name": f["name"], "icon": builder.note_art(f"{SKILL_ICON_FOLDER}/{f['icon']}"), "kind": f["kind"], "cost": 1}
             for f in fixed_skills(registry) if not f["hidden"]]
    fixed += [{"row": e["row"], "tier": e["tier"], "name": e["name"], "icon": builder.note_art(f"{SKILL_ICON_FOLDER}/{e['icon']}"), "kind": "lore", "cost": LORE_LEVELS}
              for e in registry.get("lores", {}).values() if e.get("build")]
    # The weapon models a prop slot may switch to: every vanilla model in a props folder.
    models = AssetSource([], [], PROP_PACKS).index
    editor["prop_models"] = sorted(p for p in models if p.endswith(".wsmodel") and PROP_FOLDER.search(p))
    # The Look tab: his outfits (slot -> model), his head with and without the hood, and the humanoid models a piece can be.
    head = registry["model"]["heads"][registry["model"]["head"]]
    editor["look"] = {"bodies": {k: {slot: piece[0] for slot, piece in body.items()} for k, body in registry["model"]["bodies"].items()},
                      "head": {"hooded": head["hooded"][0], "hoodless": head.get("hoodless", [""])[0]},
                      "models": sorted(p for p in models if p.endswith(".wsmodel") and LOOK_FOLDER.search(p) and not PROP_FOLDER.search(p) and not LOOK_SKIPPED.search(p))}
    editor["skills"] = {"catalog": catalog, "fixed": fixed, "rows": dict(enumerate(SKILL_ROWS))}
    editor["new_form"] = builder.new_form_data(registry, sets)
    editor["colours"] = faction_colours(builder.loc)
    print(f"panels: {len(panels)} units, {builder.copy_art(out)} art files, {len(editor['attributes'])} attributes, {len(editor['abilities'])} abilities")
    return panels, pairs_to_vanilla, editor
