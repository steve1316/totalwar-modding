"""Builds the Advisor Overhaul (`!!advisor_overhaul`): a standalone hero, the Advisor, with his own agent subtype, model, weapon and mount units, the
skills that unlock them, and the data the campaign scripts read.

How a pair reaches the battle map:
- A weapon skill and a mount skill unlock that weapon or mount. The default weapon and mount need no skill. The player picks the pair with the
  Change Loadout button in the Advisor's character panel, and `script/campaign/mod/advisor_overhaul.lua` equips the pair's hidden mount ancillary.
- That ancillary's `provided_bodyguard_unit` is the pair's main unit, and `campaign_character_uniform_ancillary_junctions` swaps his uniform to the
  pair's, whose battle variant carries the weapon props (and the disc).
- A weapon with a `missile` gets its own missile weapon and projectile, copied from a vanilla template with the registry's values.

How a weapon's stats are set (all optional, written by the modding workbench's Edit tab):
- `melee`: its own melee weapon, a copy of the vanilla `template` row with the given values (`damage`, `ap_damage`, `bonus_v_large`, ...).
- `stats`: its base land unit values on foot (`STAT_COLUMNS`, plus `armour` as an armour value, written as its own armour type). Mounted pairs add
  the vanilla mounted-minus-foot difference to them, as for the default stats.
- `forms`: mount -> values that replace the computed ones for that one pair.
- `attributes` adds unit attributes to every pair of the weapon, and `attributes_removed` takes them away.

Every value comes from vanilla data. His stats are the Amethyst Wizard's (`FOOT_TEMPLATE`), mounted pairs start from a vanilla hero on the same
mount (the registry's `template`) plus the vanilla difference between that hero mounted and on foot. His look (icon, voice, campaign art row,
portrait camera) follows the vanilla Grey Wizard. His 2D portrait, unit card and info picture are cut from the vanilla Advisor bust (the registry's
`portrait`). The stats are placeholders until they are tuned.

The weapons, mounts and model pieces are in advisor_overhaul_registry.json. The vanilla rows this reads are kept in advisor_overhaul.json. Refresh
it after a game patch. It reads the vanilla tables from db.pack and the vanilla portrait settings from ui.pack, both through the extract cache:

    python -m generators.advisor_overhaul --refresh

Build:

    python -m generators.advisor_overhaul
"""

import argparse
import json
import os
import shutil
import sys
import zlib
from typing import Any, Dict, List, Optional, Tuple

from PIL import Image

from core.extract_cache import cached_pack_extract
from core.utilities import STEAM_LIBRARY_DRIVE, extract_tsv_data, load_tsv_data, run_rpfm_cli
from generators import advisor_overhaul_anims as anims

# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Settings

# Weapons, mounts and model pieces.
REGISTRY = os.path.join(os.path.dirname(os.path.abspath(__file__)), "advisor_overhaul_registry.json")

# Folder of the weapon copies `model.prop_offsets` moves (written by `generators.advisor_overhaul_model`).
PROP_FOLDER = "variantmeshes/wh_variantmodels/hu1/advisor_overhaul/props"

# The kept vanilla rows and table headers.
DATA = os.path.join(os.path.dirname(os.path.abspath(__file__)), "advisor_overhaul.json")

# The mod source folder.
MOD = "../warhammer3_mods/!!advisor_overhaul"

# File name of every table and loc file this generator writes.
FILE = "advisor_overhaul"

# The vanilla pack holding the portrait settings, and where the refresh and the build extract portrait files to (through the extract cache).
UI_PACK = f"{STEAM_LIBRARY_DRIVE}\\SteamLibrary\\steamapps\\common\\Total War WARHAMMER III\\data\\ui.pack"
PORTRAIT_EXTRACT = "./temp/advisor_overhaul_portraits"

# Size of the 2D porthole image, the unit card and the unit info picture, as in vanilla.
PORTHOLE_SIZE = (300, 164)
CARD_SIZE = (60, 130)
INFOPIC_SIZE = (120, 260)

# Portrait folders that each get a settings file.
PORTRAIT_FOLDERS = ("portholes", "units")

# Every key of the mod starts with this.
PREFIX = "advisor_overhaul"

# The Advisor's agent type and subtype.
AGENT_TYPE = "wizard"
SUBTYPE = f"{PREFIX}_advisor"

# His skill node set.
NODE_SET = f"{PREFIX}_advisor_skill_node_set"

# Key of his unit description texts.
DESCRIPTION = f"{PREFIX}_advisor"

# His campaign animation set on foot.
CAMPAIGN_ANIMATION = "cam_hu1_pr8_amethyst_staff_and_sword"

# Vanilla foot wizard whose stats he starts from: the Amethyst Wizard.
FOOT_TEMPLATE = "wh2_pro07_emp_cha_wizard_death_0"

# Vanilla agent subtype whose recruitment and caster settings he starts from: the Amethyst Wizard.
STATS_SUBTYPE = "wh2_pro07_emp_amethyst_wizard"

# Vanilla agent subtype whose icon and voice he uses: the Grey Wizard.
LOOK_SUBTYPE = "wh_dlc05_emp_grey_wizard"

# Vanilla art set whose campaign art row and portrait camera he uses: the Grey Wizard.
LOOK_ART_SET = "wh_dlc05_art_set_emp_grey_wizard_01"

# Unit card value of his units. Vanilla heroes use `placeholder` or a key with no card file, since a hero's card comes from the `units` portrait
# settings. His points at his own card and info picture anyway, so no screen can fall back to a vanilla one.
UNIT_CARD = f"{PREFIX}_advisor"

# The rider entity for ordinary mounts. Mounts whose template uses another entity (the disc) keep the template's.
RIDER_ENTITY = "wh_main_infantry_standard_wizard_rider_blood_dismembers"

# The default pair. Both are always unlocked, so they get no skill.
DEFAULT_WEAPON = "staff_and_sword"
DEFAULT_MOUNT = "foot"

# Skill tree rows of the weapon and the mount skills. Two of the six vanilla rows.
WEAPON_ROW = 0
MOUNT_ROW = 1

# Names group of his name row. Frequency 0 keeps the name out of random name rolls.
NAMES_GROUP = "names_emp_empire"

# Land unit stats moved by the template's mounted-minus-foot difference.
DELTA_COLUMNS = ["bonus_hit_points", "charge_bonus", "melee_attack", "melee_defence"]

# Land unit columns every pair keeps from his foot unit, so each pair stays the same hero.
IDENTITY_COLUMNS = ["accuracy", "campaign_action_points", "morale", "visibility_spotting_range_min", "visibility_spotting_range_max", "selection_vo",
                    "selected_vo_tertiary", "spell_mastery"]

# Main unit columns every pair keeps from his foot unit.
MAIN_IDENTITY_COLUMNS = ["audio_voiceover_culture", "audio_voiceover_culture_override", "audio_voiceover_actor_group", "campaign_cap", "porthole_camera"]

# Tables with one row per template unit that every pair copies from its template, with the column naming the unit.
UNIT_ROW_TABLES = {
    "ui_unit_bullet_point_unit_overrides_tables": "unit_key",
    "battle_currency_units_cost_values_tables": "item_type",
    "campaign_map_attrition_unit_immunities_tables": "unit",
    "cdir_military_generator_unit_qualities_tables": "unit_key",
}

# AI usage group of a pair that shoots, by the group of its template: the vanilla hybrid of the same caster group.
RANGED_AI_GROUPS = {"mage_highvalue": "hybrid_mage_highvalue", "flying_mage_highvalue": "flying_hybrid_highvalue",
                    "flying_melee_mage_highvalue": "flying_melee_mage_hybrid_highvalue"}

# Unit attributes left off the pairs: the disc template's Mark of Tzeentch.
SKIPPED_ATTRIBUTES = {"mark_tzeentch"}

# Every table the generator writes. The refresh keeps its header and version.
TABLES = [
    "agent_subtypes_tables", "faction_agent_permitted_subtypes_tables", "names_tables", "campaign_character_art_sets_tables",
    "campaign_character_arts_tables", "agent_uniforms_tables", "variants_tables", "unit_variants_tables", "land_units_tables", "main_units_tables",
    "unit_description_historical_texts_tables", "unit_description_short_texts_tables", "unit_attributes_groups_tables",
    "unit_attributes_to_groups_junctions_tables", "land_units_to_unit_abilites_junctions_tables", "units_custom_battle_permissions_tables",
    "units_custom_battle_mounts_tables", "battle_animations_table_tables", "culture_to_battle_animation_tables_tables",
    "campaign_mount_animation_set_overrides_tables", "ancillaries_tables", "ancillary_info_tables", "ancillaries_included_agent_subtypes_tables",
    "campaign_character_uniform_ancillary_junctions_tables", "character_skill_node_sets_tables", "character_skills_tables",
    "character_skill_nodes_tables", "character_skill_node_set_items_tables", "character_skill_level_details_tables", "missile_weapons_tables",
    "projectiles_tables", "melee_weapons_tables", "unit_armour_types_tables", *UNIT_ROW_TABLES,
]

# Land unit columns a weapon's `stats` and `forms` may set. `armour` is set too, as an armour value.
STAT_COLUMNS = ["melee_attack", "melee_defence", "charge_bonus", "morale", "bonus_hit_points"]

# Template tables -> the column naming the template unit.
TEMPLATE_TABLES = {"land_units_tables": "key", "main_units_tables": "land_unit", "units_custom_battle_permissions_tables": "unit",
                   "unit_attributes_to_groups_junctions_tables": "attribute_group", **UNIT_ROW_TABLES}


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Refresh


def vanilla_portraits(art_set: str) -> Dict:
    """Reads one art set's entry from the vanilla portrait settings of every portrait folder.

    Args:
        art_set (str): The art set id.

    Returns:
        Dict: `version` -> the file version, and portrait folder -> the entry.

    Raises:
        SystemExit: When a folder has no entry for the art set.
    """
    out: Dict = {}
    for folder in PORTRAIT_FOLDERS:
        path = f"ui/portraits/{folder}/portrait_settings__.bin"
        cached_pack_extract(UI_PACK, path, PORTRAIT_EXTRACT, source_kind="file", tables_as_tsv=False)
        json_path = os.path.join(PORTRAIT_EXTRACT, f"{folder}.json")
        run_rpfm_cli(["portrait-settings", "to-json", "--bin-path", os.path.join(PORTRAIT_EXTRACT, path), "--json-path", json_path], capture_output=True)
        settings = json.load(open(json_path, encoding="utf-8"))
        os.remove(json_path)
        entry = next((e for e in settings["entries"] if e["id"] == art_set), None)
        if entry is None:
            raise SystemExit(f"no vanilla {folder} portrait entry for {art_set}")
        out["version"] = settings["version"]
        out[folder] = entry
    return out


def read_vanilla(table: str) -> Tuple[List[Dict[str, str]], List[str], str]:
    """Reads one vanilla table from db.pack, through the extract cache.

    Args:
        table (str): The table name.

    Returns:
        Tuple[List[Dict[str, str]], List[str], str]: The rows, the header and the version line.
    """
    return load_tsv_data(f"{extract_tsv_data(table)}/db/{table}/data__.tsv")


def refresh() -> None:
    """Keeps the vanilla rows the build reads and every written table's header and version."""
    registry = json.load(open(REGISTRY, encoding="utf-8"))
    units = {m[k] for m in registry["mounts"].values() for k in ("template", "template_foot") if k in m} | {FOOT_TEMPLATE}
    data: Dict = {"tables": {}, "templates": {}}
    loaded: Dict[str, List[Dict[str, str]]] = {}
    for table in TABLES:
        rows, header, version = read_vanilla(table)
        loaded[table] = rows
        data["tables"][table] = {"header": header, "version": version.split("\t")[0].split(";")[1]}
        if table in TEMPLATE_TABLES and table != "unit_attributes_to_groups_junctions_tables":
            data["templates"][table] = [r for r in rows if r[TEMPLATE_TABLES[table]] in units]
    groups = {r["attribute_group"] for r in data["templates"]["land_units_tables"]}
    data["templates"]["unit_attributes_to_groups_junctions_tables"] = [r for r in loaded["unit_attributes_to_groups_junctions_tables"]
                                                                       if r["attribute_group"] in groups]
    data["agent_subtypes"] = {r["key"]: r for r in loaded["agent_subtypes_tables"] if r["key"] in (STATS_SUBTYPE, LOOK_SUBTYPE)}
    data["node_set"] = next(r for r in loaded["character_skill_node_sets_tables"] if r["agent_subtype_key"] == STATS_SUBTYPE)
    data["art"] = next(r for r in loaded["campaign_character_arts_tables"] if r["art_set_id"] == LOOK_ART_SET)
    data["factions"] = sorted({r["faction"] for r in loaded["faction_agent_permitted_subtypes_tables"]})
    mounts = {r["mount"] for r in data["templates"]["land_units_tables"] if r["mount"]}
    data["mount_animations"] = {r["key"]: r["animation"] for r in read_vanilla("mounts_tables")[0] if r["key"] in mounts}
    culture_rows = loaded["culture_to_battle_animation_tables_tables"]
    data["culture_packs"] = sorted({r["culture_pack"] for r in culture_rows if r["culture_pack"]})
    data["culture_animations"] = sorted(f"{r['battle_animations_table']}|{r['culture_pack']}" for r in culture_rows)
    data["vanilla_names"] = sorted(r["id"] for r in loaded["names_tables"])
    missiles = {w["missile"]["template"] for w in registry["weapons"].values() if "missile" in w}
    data["missile_weapons"] = {r["key"]: r for r in loaded["missile_weapons_tables"] if r["key"] in missiles}
    projectiles = {r["default_projectile"] for r in data["missile_weapons"].values()}
    data["projectiles"] = {r["key"]: r for r in loaded["projectiles_tables"] if r["key"] in projectiles}
    melees = {w["melee"]["template"] for w in registry["weapons"].values() if "melee" in w}
    melees |= {r["primary_melee_weapon"] for r in data["templates"]["land_units_tables"]}
    data["melee_weapons"] = {r["key"]: r for r in loaded["melee_weapons_tables"] if r["key"] in melees}
    armours = {r["armour"] for r in data["templates"]["land_units_tables"]}
    data["armour_types"] = {r["key"]: r for r in loaded["unit_armour_types_tables"] if r["key"] in armours}
    data["portraits"] = vanilla_portraits(LOOK_ART_SET)
    json.dump(data, open(DATA, "w", encoding="utf-8"), indent=1, sort_keys=True)
    print(f"kept {len(data['templates']['land_units_tables'])} template units, {len(data['factions'])} factions in {DATA}")


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Keys


def unit_key(weapon: str, mount: str) -> str:
    """The land and main unit key of a pair.

    Args:
        weapon (str): Weapon key.
        mount (str): Mount key.

    Returns:
        str: The unit key.
    """
    return f"{PREFIX}_{weapon}_{mount}"


def rig_key(weapon: str, mount: str) -> str:
    """The hidden mount ancillary that gives him a pair's unit.

    Args:
        weapon (str): Weapon key.
        mount (str): Mount key.

    Returns:
        str: The ancillary key.
    """
    return f"{PREFIX}_rig_{weapon}_{mount}"


def uniform_key(weapon: str, mount: str) -> str:
    """The agent uniform of a pair.

    Args:
        weapon (str): Weapon key.
        mount (str): Mount key.

    Returns:
        str: The uniform name.
    """
    return f"{PREFIX}_{weapon}_{mount}"


def foot_variant(weapon: str) -> str:
    """The variant of a weapon on foot. The campaign map, the character panel and the portraits use it on every mount.

    Args:
        weapon (str): Weapon key.

    Returns:
        str: The variant name, also its variant mesh definition's file name.
    """
    return f"{PREFIX}_{weapon}"


def missile_key(weapon_key: str, weapon: Dict) -> str:
    """The missile weapon of a weapon with a `missile`, also its projectile's key: the missile's own `key`, or one named after the weapon.

    Args:
        weapon_key (str): The weapon key.
        weapon (Dict): The registry weapon.

    Returns:
        str: The missile weapon key.
    """
    return weapon["missile"].get("key", f"{PREFIX}_{weapon_key}_missile")


def weapon_art_set(weapon: str) -> str:
    """The art set that shows a weapon in the character panel.

    Args:
        weapon (str): The weapon key.

    Returns:
        str: The art set key.
    """
    return f"{PREFIX}_art_{weapon}"


def choice_skill(kind: str, key: str) -> str:
    """The skill that unlocks a weapon or mount.

    Args:
        kind (str): `weapon` or `mount`.
        key (str): The weapon or mount key.

    Returns:
        str: The skill key.
    """
    return f"{PREFIX}_choose_{kind}_{key}"


def ui_name(kind: str, key: str) -> str:
    """The loc key of a weapon or mount name, shown in the Change Loadout picker.

    Args:
        kind (str): `weapon` or `mount`.
        key (str): The weapon or mount key.

    Returns:
        str: The loc key.
    """
    return f"{PREFIX}_ui_{kind}_{key}"


def unlock_skill(kind: str, key: str) -> str:
    """The skill that unlocks a weapon or mount, or an empty string for the always unlocked default.

    Args:
        kind (str): `weapon` or `mount`.
        key (str): The weapon or mount key.

    Returns:
        str: The skill key, or an empty string.
    """
    if key == (DEFAULT_WEAPON if kind == "weapon" else DEFAULT_MOUNT):
        return ""
    return choice_skill(kind, key)


def name_id() -> str:
    """The id of his name row, from a hash of the mod prefix.

    Returns:
        str: The id.
    """
    return str(zlib.crc32(f"{PREFIX}_name".encode()) & 0x7FFFFFFF)


def pairs(registry: Dict) -> List[Tuple[str, str]]:
    """Every valid (weapon, mount) pair: those with an animation set for that mount.

    Args:
        registry (Dict): The registry.

    Returns:
        List[Tuple[str, str]]: The pairs in registry order.
    """
    return [(w, m) for w, weapon in registry["weapons"].items() for m in registry["mounts"] if m in weapon["sets"]]


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Build


def number(value: str) -> float:
    """Reads a TSV number, treating empty as 0.

    Args:
        value (str): The cell.

    Returns:
        float: The number.
    """
    return float(value) if value else 0.0


def table_value(value: Any) -> str:
    """A registry value as a table cell: booleans as `true`/`false`, whole numbers plain, other numbers with four decimals like vanilla.

    Args:
        value (Any): The value.

    Returns:
        str: The cell.
    """
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, float) and not value.is_integer():
        return f"{value:.4f}"
    if isinstance(value, float):
        return str(int(value))
    return str(value)


def melee_key(weapon_key: str) -> str:
    """The key of a weapon's own melee weapon.

    Args:
        weapon_key (str): The weapon key.

    Returns:
        str: The key.
    """
    return f"{PREFIX}_{weapon_key}_melee"


def melee_rows(registry: Dict, data: Dict, rows: Dict[str, List[Dict[str, str]]]) -> None:
    """Adds a melee weapon for every weapon with a `melee`: a copy of the vanilla template's row under his own key, with the registry's values.

    Args:
        registry (Dict): The registry.
        data (Dict): The kept vanilla rows.
        rows (Dict[str, List[Dict[str, str]]]): Rows by table, added to.

    Raises:
        SystemExit: When a template is not in the kept rows (run `--refresh`).
    """
    for weapon_key, weapon in registry["weapons"].items():
        if "melee" not in weapon:
            continue
        melee = dict(weapon["melee"])
        template = melee.pop("template")
        if template not in data.get("melee_weapons", {}):
            raise SystemExit(f"melee template {template} is not kept, run with --refresh")
        rows["melee_weapons_tables"].append(dict(data["melee_weapons"][template], key=melee_key(weapon_key), **{k: table_value(v) for k, v in melee.items()}))


def armour_row(row: Dict[str, str], weapon: Dict, mount_key: str, mount: Dict, templates: Dict, armour_types: Dict) -> Optional[Dict[str, str]]:
    """A pair's own armour type when its weapon sets an armour value: the form's own value, else the weapon's base plus the vanilla mounted-minus-foot
    difference. The land unit row is pointed at it.

    Args:
        row (Dict[str, str]): The pair's land unit row, changed in place.
        weapon (Dict): The registry weapon.
        mount_key (str): The mount key.
        mount (Dict): The registry mount.
        templates (Dict): Template land units by key.
        armour_types (Dict): The kept armour type rows by key.

    Returns:
        Optional[Dict[str, str]]: The armour type row, or None when the weapon sets no armour.
    """
    form, base = weapon.get("forms", {}).get(mount_key, {}).get("armour"), weapon.get("stats", {}).get("armour")
    if form is None and base is None:
        return None
    value = form
    if value is None:
        value = base
        if "template" in mount:
            mounted, foot = templates[mount["template"]], templates[mount["template_foot"]]
            value += number(armour_types[mounted["armour"]]["armour_value"]) - number(armour_types[foot["armour"]]["armour_value"])
    template = armour_types[row["armour"]]
    row["armour"] = f"{row['key']}_armour"
    return dict(template, key=row["armour"], armour_value=table_value(int(value)))


def land_unit(key: str, weapon_key: str, weapon: Dict, set_name: str, mount_key: str, mount: Dict, templates: Dict, advisor: Dict[str, str]) -> Dict[str, str]:
    """A pair's land unit row.

    Args:
        key (str): The unit key.
        weapon_key (str): The weapon key.
        weapon (Dict): The registry weapon.
        set_name (str): The battle animation set.
        mount_key (str): The mount key.
        mount (Dict): The registry mount.
        templates (Dict): Template land units by key.
        advisor (Dict[str, str]): His foot land unit.

    Returns:
        Dict[str, str]: The row.
    """
    # The weapon's base stats replace his foot unit's before the mount's difference is added.
    advisor = dict(advisor, **{c: table_value(v) for c, v in weapon.get("stats", {}).items() if c in STAT_COLUMNS})
    if "template" not in mount:
        row = dict(advisor, key=key, man_animation=set_name, shield=weapon["shield"], attribute_group=key)
        return with_form(with_missile(row, weapon_key, weapon), weapon_key, weapon, mount_key)
    mounted, foot = templates[mount["template"]], templates[mount["template_foot"]]
    row = dict(mounted)
    for column in IDENTITY_COLUMNS + ["historical_description_text", "short_description_text"]:
        row[column] = advisor[column]
    for column in DELTA_COLUMNS:
        row[column] = str(int(number(advisor[column]) + number(mounted[column]) - number(foot[column])))
    if mounted["armour"] == foot["armour"]:
        row["armour"] = advisor["armour"]
    if mounted["primary_melee_weapon"] == foot["primary_melee_weapon"]:
        row["primary_melee_weapon"] = advisor["primary_melee_weapon"]
    if mounted["mount"]:
        row["man_entity"] = RIDER_ENTITY
    row.update({"key": key, "man_animation": set_name, "shield": weapon["shield"], "attribute_group": key})
    return with_form(with_missile(row, weapon_key, weapon), weapon_key, weapon, mount_key)


def with_form(row: Dict[str, str], weapon_key: str, weapon: Dict, mount_key: str) -> Dict[str, str]:
    """Gives a land unit row its weapon's own melee weapon and the values its form sets for this one pair.

    Args:
        row (Dict[str, str]): The land unit row, changed in place.
        weapon_key (str): The weapon key.
        weapon (Dict): The registry weapon.
        mount_key (str): The mount key.

    Returns:
        Dict[str, str]: The row.
    """
    if "melee" in weapon:
        row["primary_melee_weapon"] = melee_key(weapon_key)
    row.update({c: table_value(v) for c, v in weapon.get("forms", {}).get(mount_key, {}).items() if c in STAT_COLUMNS})
    return row


def with_missile(row: Dict[str, str], weapon_key: str, weapon: Dict) -> Dict[str, str]:
    """Gives a land unit row its weapon's missile weapon and ammo, and the AI group of a caster that shoots. Rows of weapons with no missile are
    returned as they are.

    Args:
        row (Dict[str, str]): The land unit row, changed in place.
        weapon_key (str): The weapon key.
        weapon (Dict): The registry weapon.

    Returns:
        Dict[str, str]: The row.
    """
    if "missile" in weapon:
        row.update(primary_missile_weapon=missile_key(weapon_key, weapon), primary_ammo=str(weapon["missile"]["ammo"]),
                   ai_usage_group=RANGED_AI_GROUPS.get(row["ai_usage_group"], row["ai_usage_group"]))
    return row


def agent_rows(data: Dict, rows: Dict[str, List[Dict[str, str]]], texts: List[Tuple[str, str]]) -> None:
    """Adds the agent subtype, its faction permissions, his name and his unit descriptions.

    Args:
        data (Dict): The kept vanilla rows.
        rows (Dict[str, List[Dict[str, str]]]): Rows by table, added to.
        texts (List[Tuple[str, str]]): Loc rows, added to.
    """
    stats, look = data["agent_subtypes"][STATS_SUBTYPE], data["agent_subtypes"][LOOK_SUBTYPE]
    # One per faction, spawned by script and kept alive by it, so he is never in the recruitment pool and never counts toward the hero cap.
    rows["agent_subtypes_tables"].append(dict(stats, key=SUBTYPE, auto_generate="false", small_icon=look["small_icon"],
                                              associated_unit_override=unit_key(DEFAULT_WEAPON, DEFAULT_MOUNT),
                                              audio_voiceover_actor_group=look["audio_voiceover_actor_group"], cap="1", contributes_to_agent_cap="false",
                                              recruitable="false"))
    rows["faction_agent_permitted_subtypes_tables"] += [{"agent": AGENT_TYPE, "faction": f, "subtype": SUBTYPE, "mod_disabled": "false"}
                                                        for f in data["factions"]]
    if name_id() in data["vanilla_names"]:
        raise SystemExit(f"name id {name_id()} is already a vanilla name")
    rows["names_tables"].append({"id": name_id(), "names_group": NAMES_GROUP, "type": "forename", "gender": "m", "frequency": "0"})
    texts.append((f"names_name_{name_id()}", "The Advisor"))
    rows["unit_description_historical_texts_tables"].append({"key": DESCRIPTION})
    rows["unit_description_short_texts_tables"].append({"key": DESCRIPTION})
    rows["character_skill_node_sets_tables"].append(dict(data["node_set"], key=NODE_SET, agent_key=AGENT_TYPE, agent_subtype_key=SUBTYPE))
    texts += [
        (f"agent_subtypes_onscreen_name_override_{SUBTYPE}", "The Advisor"),
        (f"agent_subtypes_description_text_override_{SUBTYPE}",
         "An old wizard of the Empire who has spent longer giving counsel than most kingdoms have stood. He follows your faction leader from the "
         "first day of the campaign, and he will not stay dead for long."),
        (f"unit_description_historical_texts_text_{DESCRIPTION}",
         "Nobody at court remembers hiring him. He was simply there one morning, leaning on his staff by the war table, already correcting the "
         "maps.\\\\n\\\\nHe has outlived the generals who ignored him and quietly buried the ones who listened too late. Some say he trained at "
         "every College in Altdorf and was thrown out of each in turn. He says only that he has seen how this ends, and would rather it ended "
         "differently."),
        (f"unit_description_short_texts_text_{DESCRIPTION}", "An old, hooded Imperial wizard who fights with staff and sword beside your faction leader."),
    ]


def skill_rows(registry: Dict, rows: Dict[str, List[Dict[str, str]]], texts: List[Tuple[str, str]]) -> None:
    """Adds the weapon and mount skills. Each unlocks its item for the Change Loadout picker.

    Args:
        registry (Dict): The registry.
        rows (Dict[str, List[Dict[str, str]]]): Rows by table, added to.
        texts (List[Tuple[str, str]]): Loc rows, added to.
    """
    for row, kind, items, default in ((WEAPON_ROW, "weapon", registry["weapons"], DEFAULT_WEAPON), (MOUNT_ROW, "mount", registry["mounts"], DEFAULT_MOUNT)):
        for item_key, item in items.items():
            texts.append((ui_name(kind, item_key), item["name"]))
        for tier, (item_key, item) in enumerate(i for i in items.items() if i[0] != default):
            skill = choice_skill(kind, item_key)
            node = f"{PREFIX}_choose_{kind}_node_{item_key}"
            rows["character_skills_tables"].append({
                "key": skill, "image_path": item.get("skill_icon") or os.path.basename(item["icon"]), "unlocked_at_rank": "0", "is_background_skill": "false",
                "is_female_only_background_skill": "false", "is_male_only_background_skill": "false", "background_weighting": "0.0000", "influence_cost": "0",
            })
            texts.append((f"character_skills_localised_name_{skill}", item["name"]))
            texts.append((f"character_skills_localised_description_{skill}", f"{item['description']}\\\\n\\\\nUnlocks this {kind} for the Advisor. "
                          "Switch to it with the Change Loadout button in his character panel."))
            rows["character_skill_nodes_tables"].append({
                "key": node, "character_skill_key": skill, "indent": str(row), "tier": str(tier), "points_on_creation": "0", "required_num_parents": "0",
                "visible_in_ui": "true",
            })
            rows["character_skill_node_set_items_tables"].append({"set": NODE_SET, "item": node, "mod_disabled": "false"})
            # Without a level row the skill has 0 levels: the tree draws it as learned while `has_skill` stays false.
            rows["character_skill_level_details_tables"].append({
                "campaign_key": "", "faction_key": "", "level": "1", "skill_key": skill, "subculture_key": "", "image_path": "x",
                "unlocked_at_rank": str(item.get("unlock_rank", 1)),
            })


def art_rows(registry: Dict, data: Dict, rows: Dict[str, List[Dict[str, str]]]) -> None:
    """Adds one art set per weapon. The character panel's model follows only the art set, so the script switches it with the weapon.

    Args:
        registry (Dict): The registry.
        data (Dict): The kept vanilla rows.
        rows (Dict[str, List[Dict[str, str]]]): Rows by table, added to.
    """
    for weapon_key, weapon in registry["weapons"].items():
        art_set = weapon_art_set(weapon_key)
        rows["campaign_character_art_sets_tables"].append({
            "art_set_id": art_set, "agent_type": AGENT_TYPE, "culture": "", "subculture": "", "faction": "", "is_custom": "false", "is_male": "true",
            "agent_subtype": SUBTYPE, "campaign_map_scale": "1.0000", "prebattle_separation_offset": "0.0000",
        })
        rows["campaign_character_arts_tables"].append(dict(data["art"], id=str(zlib.crc32(art_set.encode()) & 0x7FFFFFFF), art_set_id=art_set,
                                                           uniform=uniform_key(weapon_key, DEFAULT_MOUNT),
                                                           land_animation=weapon.get("campaign_set", CAMPAIGN_ANIMATION)))


def missile_rows(registry: Dict, data: Dict, rows: Dict[str, List[Dict[str, str]]]) -> None:
    """Adds a missile weapon and its projectile for every weapon with a `missile`: copies of the vanilla template's rows under his own keys, with
    the registry's projectile values.

    Args:
        registry (Dict): The registry.
        data (Dict): The kept vanilla rows.
        rows (Dict[str, List[Dict[str, str]]]): Rows by table, added to.

    Raises:
        SystemExit: When a template is not in the kept rows (run `--refresh`).
    """
    for weapon_key, weapon in registry["weapons"].items():
        if "missile" not in weapon:
            continue
        missile = weapon["missile"]
        if missile["template"] not in data.get("missile_weapons", {}):
            raise SystemExit(f"missile template {missile['template']} is not kept, run with --refresh")
        template = data["missile_weapons"][missile["template"]]
        key = missile_key(weapon_key, weapon)
        rows["missile_weapons_tables"].append(dict(template, key=key, default_projectile=key))
        rows["projectiles_tables"].append(dict(data["projectiles"][template["default_projectile"]], key=key,
                                               **{k: table_value(v) for k, v in missile["projectile"].items()}))


def build() -> None:
    """Writes every table, variant, portrait setting, loc row and the script data file into the mod folder."""
    registry = json.load(open(REGISTRY, encoding="utf-8"))
    data = json.load(open(DATA, encoding="utf-8"))
    specs, templates = data["tables"], data["templates"]
    template_units = {r["key"]: r for r in templates["land_units_tables"]}
    template_main = {r["land_unit"]: r for r in templates["main_units_tables"]}
    template_perm = next(r for r in templates["units_custom_battle_permissions_tables"] if r["unit"] == FOOT_TEMPLATE)
    template_attributes: Dict[str, List[str]] = {}
    for r in templates["unit_attributes_to_groups_junctions_tables"]:
        template_attributes.setdefault(r["attribute_group"], []).append(r["attribute"])
    advisor = dict(template_units[FOOT_TEMPLATE], historical_description_text=DESCRIPTION, short_description_text=DESCRIPTION)
    portrait_png = portrait_path(registry["portrait"]).lower()

    rows: Dict[str, List[Dict[str, str]]] = {table: [] for table in TABLES}
    texts: List[Tuple[str, str]] = []
    variants: Dict[str, Dict] = {}
    combos: List[Tuple[str, str, str]] = []
    unique_index = 1493349200
    agent_rows(data, rows, texts)

    for weapon_key, mount_key in pairs(registry):
        weapon, mount = registry["weapons"][weapon_key], registry["mounts"][mount_key]
        key = unit_key(weapon_key, mount_key)
        template = mount.get("template", FOOT_TEMPLATE)
        ancillary = rig_key(weapon_key, mount_key)
        uniform = uniform_key(weapon_key, mount_key)
        variant = foot_variant(weapon_key) + ("_" + mount_key if "variant_props" in mount else "")
        combos.append((weapon_key, mount_key, ancillary))

        land = land_unit(key, weapon_key, weapon, weapon["sets"][mount_key], mount_key, mount, template_units, advisor)
        armour = armour_row(land, weapon, mount_key, mount, template_units, data["armour_types"])
        if armour:
            rows["unit_armour_types_tables"].append(armour)
        rows["land_units_tables"].append(land)
        # Voice, campaign cap and portrait camera stay his own on every mount, since the disc template is a Chaos Sorcerer.
        main = dict(template_main[template], **{k: template_main[FOOT_TEMPLATE][k] for k in MAIN_IDENTITY_COLUMNS})
        rows["main_units_tables"].append(dict(main, unit=key, land_unit=key, unique_index=str(unique_index), caste="hero"))
        unique_index += 1
        rows["unit_attributes_groups_tables"].append({"group_name": key})
        attributes = (set(template_attributes.get(template, [])) | set(weapon.get("attributes", []))) - SKIPPED_ATTRIBUTES - set(weapon.get("attributes_removed", []))
        rows["unit_attributes_to_groups_junctions_tables"] += [{"attribute": a, "attribute_group": key} for a in sorted(attributes)]
        rows["land_units_to_unit_abilites_junctions_tables"].append({"ability": "wh3_main_unit_passive_single_entity", "land_unit": key, "culture": "*"})
        for table, column in UNIT_ROW_TABLES.items():
            rows[table] += [dict(r, **{column: key}) for r in templates[table] if r[column] == template]
        rows["units_custom_battle_permissions_tables"].append(dict(template_perm, unit=key, general_uniform=uniform, general_portrait=portrait_png,
                                                                   set_piece_character=""))
        if mount_key != DEFAULT_MOUNT:
            rows["units_custom_battle_mounts_tables"].append({"base_unit": unit_key(weapon_key, DEFAULT_MOUNT), "mounted_unit": key, "icon_name": mount["icon"]})
        rows["unit_variants_tables"].append({"faction": "", "unit": key, "name": SUBTYPE, "variant": variant, "unit_card": UNIT_CARD})
        texts.append((f"land_units_onscreen_name_{key}", "The Advisor" if key == unit_key(DEFAULT_WEAPON, DEFAULT_MOUNT)
                      else f"The Advisor ({weapon['name']}, {mount['name']})"))

        rows["ancillaries_tables"].append({
            "key": ancillary, "type": mount["ancillary_type"], "applies_to": ".", "transferrable": "false", "unique_to_world": "false",
            "unique_to_faction": "false", "precedence": "1", "start_date": "0", "end_date": "9999", "legendary_item": "false", "mp_exclusive": "false",
            "is_wife_ancillary": "false", "category": "mount", "min_starting_age": "16", "max_starting_age": "30", "min_expiry_age": "30",
            "max_expiry_age": "50", "immortal": "true", "provided_bodyguard_unit": key, "uniqueness_score": "1", "turns_before_swap_allowed": "0",
            "randomly_dropped": "false", "can_be_stolen": "false", "can_be_destroyed": "false", "faction_set": "all",
        })
        rows["ancillary_info_tables"].append({"ancillary": ancillary})
        rows["ancillaries_included_agent_subtypes_tables"].append({"agent_subtype": SUBTYPE, "ancillary": ancillary})
        for art_set in (weapon_art_set(w) for w in registry["weapons"]):
            rows["campaign_character_uniform_ancillary_junctions_tables"].append({"ancillary": ancillary, "art_set": art_set, "uniform": uniform})
        # The campaign map model and the character panel model show the weapon. Both use the weapon's foot variant, so mount props such as the disc
        # stay out of them.
        rows["agent_uniforms_tables"].append({"uniform_name": uniform, "filename": foot_variant(weapon_key), "battle_filename": variant,
                                              "campaign_porthole_filename": foot_variant(weapon_key)})
        if "campaign_rider_set" in mount and mount_key != DEFAULT_MOUNT:
            # Both his foot set and the weapon's own campaign set get the rider pose.
            rider = weapon.get("campaign_rider_sets", {}).get(mount_key, mount["campaign_rider_set"])
            for character_set in dict.fromkeys([CAMPAIGN_ANIMATION, weapon.get("campaign_set", CAMPAIGN_ANIMATION)]):
                rows["campaign_mount_animation_set_overrides_tables"].append({"character_animation_set": character_set, "mount_unit": key,
                                                                             "rider_animation_set": rider, "vfx_filter_override": "0"})
        texts.append((f"ancillaries_onscreen_name_{ancillary}", f"{weapon['name']}, {mount['name']}"))
        texts.append((f"ancillaries_colour_text_{ancillary}", f"{weapon['description']} {mount['description']}"))
        variants[variant] = (weapon.get("body", registry["model"]["body"]), dict(weapon["props"], **mount.get("variant_props", {})))

    for variant in variants:
        rows["variants_tables"].append({"variant_name": variant, "variant_filename": variant, "mount_scale": "1.0000", "scale": "1.1500", "scale_variation": "0.0000"})
    for set_name in [*anims.SETS, *anims.DERIVED_SETS]:
        rows["battle_animations_table_tables"].append({"key": set_name, "skeleton": anims.TARGET_SKELETON})
    # Every culture pack loads every animation set he or his mounts play, unless vanilla already does.
    battle_sets = {r["man_animation"] for r in rows["land_units_tables"]} | set(data["mount_animations"].values())
    vanilla_pairs = set(data["culture_animations"])
    rows["culture_to_battle_animation_tables_tables"] += [{"battle_animations_table": s, "culture_pack": c} for s in sorted(battle_sets)
                                                          for c in data["culture_packs"] if f"{s}|{c}" not in vanilla_pairs]
    skill_rows(registry, rows, texts)
    art_rows(registry, data, rows)
    missile_rows(registry, data, rows)
    melee_rows(registry, data, rows)
    check_duplicates(rows)
    check_loc(texts)

    for table, table_rows in rows.items():
        write(table, table_rows, specs[table])
    write_variants(registry["model"], variants)
    # Art set entries show their weapon's foot variant. Campaign variant entries show their own.
    portrait_ids = [(weapon_art_set(w), foot_variant(w)) for w in registry["weapons"]] + [(foot_variant(w), foot_variant(w)) for w in registry["weapons"]]
    write_portraits(data["portraits"], registry["portrait"], portrait_ids)
    write_portrait_images(registry["portrait"])
    write_script(registry, combos)
    with open(os.path.join(MOD, "text", "db", f"{FILE}.loc.tsv"), "w", encoding="utf-8", newline="\n") as f:
        f.write(f"key\ttext\ttooltip\n#Loc;1;text/db/{FILE}.loc\t\t\n")
        f.write("".join(f"{key}\t{text}\ttrue\n" for key, text in texts))
    print(f"wrote {len(combos)} pairs ({len(rows['land_units_tables'])} units, {len(variants)} variants, {sum(map(len, rows.values()))} rows) to {MOD}")


def check_duplicates(rows: Dict[str, List[Dict[str, str]]]) -> None:
    """Stops the build on a repeated key.

    Args:
        rows (Dict[str, List[Dict[str, str]]]): Rows by table.

    Raises:
        SystemExit: When a key column repeats.
    """
    for table, column in (("land_units_tables", "key"), ("character_skills_tables", "key"), ("ancillaries_tables", "key"),
                          ("agent_uniforms_tables", "uniform_name"), ("main_units_tables", "unique_index"), ("missile_weapons_tables", "key"),
                          ("projectiles_tables", "key")):
        keys = [r[column] for r in rows[table]]
        if len(keys) != len(set(keys)):
            raise SystemExit(f"duplicate keys in {table}: {sorted(k for k in set(keys) if keys.count(k) > 1)}")


def check_loc(texts: List[Tuple[str, str]]) -> None:
    """Stops the build on loc text the game cannot show safely: a `%` (reading it through `common.get_localised_string` broke every script and
    crashed the game), a tab or a raw line break.

    Args:
        texts (List[Tuple[str, str]]): Loc rows.

    Raises:
        SystemExit: On a bad row.
    """
    for key, text in texts:
        if "%" in text or "\t" in text or "\n" in text or not text.isascii():
            raise SystemExit(f"loc {key} has a percent sign, a tab, a raw line break or a non-ASCII character")


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Writers


def write(table: str, rows: List[Dict[str, str]], spec: Dict) -> None:
    """Writes one table file of the mod. A table with no rows (a weapon stat nothing sets yet) is left out, and its old file removed.

    Args:
        table (str): The table name.
        rows (List[Dict[str, str]]): The rows.
        spec (Dict): The table's kept header and version.
    """
    folder = os.path.join(MOD, "db", table)
    if not rows:
        shutil.rmtree(folder, ignore_errors=True)
        return
    os.makedirs(folder, exist_ok=True)
    header = spec["header"]
    lines = ["\t".join(header), "\t".join([f"#{table};{spec['version']};db/{table}/{FILE}"] + [""] * (len(header) - 1))]
    lines += ["\t".join(row.get(column, "") for column in header) for row in rows]
    with open(os.path.join(folder, f"{FILE}.tsv"), "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")


def prop_copy_path(path: str) -> str:
    """Game path of the copy of a weapon model that `model.prop_offsets` moves.

    Args:
        path (str): The vanilla weapon model.

    Returns:
        str: The copy's path.
    """
    return f"{PROP_FOLDER}/{os.path.basename(path).lower()}"


def write_variants(model: Dict, variants: Dict[str, Tuple[str, Dict]]) -> None:
    """Writes one variant mesh definition per weapon (and per weapon on a prop mount such as the disc): his model pieces, the dismemberment stumps
    and the props.

    Args:
        model (Dict): The registry's `model` (the bodies, the head switches with their heads, and stumps).
        variants (Dict[str, Tuple[str, Dict]]): Variant name -> (key of its body in `model.bodies`, slot -> (attach point, model, metadata)).
    """
    folder = os.path.join(MOD, "variantmeshes", "variantmeshdefinitions")
    os.makedirs(folder, exist_ok=True)
    slots = {"weapon_1": "be_prop_0", "weapon_2": "be_prop_1", "shield": "be_prop_2", "weapon_3": "be_prop_3", "weapon_4": "be_prop_4", "weapon_5": "be_prop_5"}
    # The head goes right after the body's first slot, like in vanilla variants. A head with no hoodless model keeps its own when the hood is off.
    head = model["heads"][model["head"]]
    head_piece = ("head", head["hooded"] if model["hood"] else head.get("hoodless", head["hooded"]))
    for name, (body_key, props) in variants.items():
        body = list(model["bodies"][body_key].items())
        pieces = dict([body[0], head_piece] + body[1:])
        lines = ["<VARIANT_MESH>"]
        for slot, (mesh, *meta) in pieces.items():
            tail = "".join(f"<META_DATA>{m}</META_DATA>" for m in meta)
            lines += [f'\t<SLOT name="{slot}" >', f'\t\t<VARIANT_MESH model="{mesh}" >{tail}</VARIANT_MESH>', "\t</SLOT>"]
        for slot, point in slots.items():
            if slot not in props:
                lines.append(f'\t<SLOT name="{slot}" attach_point="{point}" />')
                continue
            _, mesh, meta = props[slot]
            if mesh in model.get("prop_offsets", {}):
                mesh = prop_copy_path(mesh)
            lines.append(f'\t<SLOT name="{slot}" attach_point="{point}" >')
            if mesh.lower().endswith(".variantmeshdefinition"):
                lines.append(f'\t\t<VARIANT_MESH_REFERENCE definition="{mesh}" />')
            else:
                tail = f"<META_DATA>{meta}</META_DATA>" if meta else ""
                lines.append(f'\t\t<VARIANT_MESH model="{mesh}" >{tail}</VARIANT_MESH>')
            lines.append("\t</SLOT>")
        for slot, (point, mesh) in model["stumps"].items():
            lines += [f'\t<SLOT name="{slot}" attach_point="{point}" >',
                      f'\t\t<VARIANT_MESH model="{mesh}" ><META_DATA>equipment</META_DATA><META_DATA>is_stump</META_DATA></VARIANT_MESH>', "\t</SLOT>"]
        lines.append("</VARIANT_MESH>")
        with open(os.path.join(folder, f"{name}.variantmeshdefinition"), "w", encoding="utf-8", newline="\n") as f:
            f.write("\n".join(lines) + "\n")


def portrait_path(portrait: Dict) -> str:
    """Game path of his 2D porthole image, in the vanilla spelling of `file_diffuse`. His unit card has the same name under `units`.

    Args:
        portrait (Dict): The registry's `portrait`.

    Returns:
        str: The path.
    """
    return f"UI/Portraits/Portholes/no_culture/{portrait['image']}.png"


def write_portraits(portraits: Dict, portrait: Dict, ids: List[Tuple[str, str]]) -> None:
    """Writes portrait settings for his art sets and campaign variants: the vanilla Grey Wizard's body camera, the registry's head camera and his
    own portrait image under each id. Without them a character on a new art set has no portrait.

    Args:
        portraits (Dict): The kept vanilla entries (`version` and one entry per portrait folder).
        portrait (Dict): The registry's `portrait`.
        ids (List[Tuple[str, str]]): (entry id, variant file name) per entry to write.

    Raises:
        SystemExit: When rpfm_cli cannot write a file.
    """
    for folder in PORTRAIT_FOLDERS:
        entries = []
        for entry_id, filename in ids:
            entry = json.loads(json.dumps(portraits[folder]))
            entry["id"] = entry_id
            entry["camera_settings_head"].update(portrait["camera_head"])
            for variant in entry["variants"]:
                # No faction colour masks: vanilla leaves them empty on about half its entries.
                variant.update(filename=filename, file_diffuse=portrait_path(portrait), file_mask_1="", file_mask_2="", file_mask_3="")
            entries.append(entry)
        out = os.path.join(MOD, "ui", "portraits", folder)
        os.makedirs(out, exist_ok=True)
        json_path = os.path.join(out, f"portrait_settings__{FILE}.json")
        bin_path = os.path.join(out, f"portrait_settings__{FILE}.bin")
        json.dump({"version": portraits["version"], "entries": entries}, open(json_path, "w", encoding="utf-8"), indent=1)
        try:
            result = run_rpfm_cli(["portrait-settings", "from-json", "--json-path", json_path, "--bin-path", bin_path], capture_output=True, text=True)
            if result.returncode != 0 or not os.path.exists(bin_path):
                raise SystemExit(f"rpfm_cli could not write {bin_path}: {result.stderr}")
        finally:
            os.remove(json_path)


def write_portrait_images(portrait: Dict) -> None:
    """Writes his 2D porthole image, unit card and unit info picture, cut from the vanilla Advisor bust. The porthole keeps a clear background, as
    in vanilla. The card and info picture put the bust at the bottom over a gradient, like the vanilla Empire wizard cards.

    Args:
        portrait (Dict): The registry's `portrait`.

    Raises:
        SystemExit: When the bust is not in its pack.
    """
    pack, path = portrait["source"]
    source = os.path.join(PORTRAIT_EXTRACT, path)
    cached_pack_extract(os.path.join(os.path.dirname(UI_PACK), pack), path, PORTRAIT_EXTRACT, source_kind="file", tables_as_tsv=False)
    if not os.path.exists(source):
        raise SystemExit(f"{path} is not in {pack}")
    bust = Image.open(source).convert("RGBA")

    def scaled(scale: float) -> Image.Image:
        return bust.resize((round(bust.width * scale), round(bust.height * scale)), Image.LANCZOS)

    def card(size: Tuple[int, int], scale: float) -> Image.Image:
        top, bottom = portrait["card"]["top"], portrait["card"]["bottom"]
        out = Image.new("RGBA", size)
        for y in range(size[1]):
            t = y / (size[1] - 1)
            out.paste(tuple(round(a + (b - a) * t) for a, b in zip(top, bottom)) + (255,), (0, y, size[0], y + 1))
        image = scaled(scale)
        out.alpha_composite(image, ((size[0] - image.width) // 2, size[1] - image.height))
        return out

    porthole = Image.new("RGBA", PORTHOLE_SIZE)
    porthole.alpha_composite(scaled(portrait["porthole"]["scale"]), (portrait["porthole"]["x"], portrait["porthole"]["y"]))
    name = portrait["image"]
    unit_card = card(CARD_SIZE, portrait["card"]["scale"])
    images = {
        f"ui/portraits/portholes/no_culture/{name}.png": porthole,
        f"ui/portraits/units/no_culture/{name}.png": unit_card,
        f"ui/units/icons/{UNIT_CARD}.png": unit_card,
        f"ui/units/infopics/{UNIT_CARD}.png": card(INFOPIC_SIZE, portrait["card"]["scale"] * INFOPIC_SIZE[0] / CARD_SIZE[0]),
    }
    for game_path, image in images.items():
        out = os.path.join(MOD, game_path)
        os.makedirs(os.path.dirname(out), exist_ok=True)
        image.save(out, optimize=True)


def write_script(registry: Dict, combos: List[Tuple[str, str, str]]) -> None:
    """Writes the Lua data table the campaign scripts read: his subtype, the weapons and mounts with their unlock skills, names and picker icons,
    and the ancillary of every valid pair both ways.

    Args:
        registry (Dict): The registry.
        combos (List[Tuple[str, str, str]]): (weapon, mount, ancillary) per valid pair.
    """
    folder = os.path.join(MOD, "script", "campaign", "mod")
    os.makedirs(folder, exist_ok=True)
    lines = ["--- Generated by generators/advisor_overhaul.py. Do not edit by hand.", "ADVISOR_OVERHAUL_RIGS = {",
             "\t--- The Advisor's agent subtype.", f'\tsubtype = "{SUBTYPE}",',
             "\t--- Weapon he holds when nothing else is chosen. Always unlocked.", f'\tdefault_weapon = "{DEFAULT_WEAPON}",',
             "\t--- Mount he rides when nothing else is chosen. Always unlocked.", f'\tdefault_mount = "{DEFAULT_MOUNT}",']
    for kind, items in (("weapon", registry["weapons"]), ("mount", registry["mounts"])):
        lines.append(f"\t--- {kind.capitalize()}s in skill tree order: key, unlock skill (empty for the default), name loc key, English fallback name and "
                     "picker icon.")
        if kind == "weapon":
            lines.append("\t--- Weapons also name the art set that shows them in the character panel.")
        lines.append(f"\t{kind}s = {{")
        for key, item in items.items():
            name = item["name"].replace('"', '\\"')
            art = f', art_set = "{weapon_art_set(key)}"' if kind == "weapon" else ""
            lines.append(f'\t\t{{ key = "{key}", skill = "{unlock_skill(kind, key)}", name = "{ui_name(kind, key)}", fallback = "{name}", '
                         f'icon = "{item["picker_icon"]}"{art} }},')
        lines.append("\t},")
    lines += ['\t--- "weapon|mount" -> the mount ancillary that gives him that unit. Only pairs with a unit are listed.', "\tancillaries = {"]
    lines += [f'\t\t["{w}|{m}"] = "{a}",' for w, m, a in combos]
    lines += ["\t},", "\t--- Mount ancillary -> the weapon and mount of its pair.", "\trigs = {"]
    lines += [f'\t\t["{a}"] = {{ weapon = "{w}", mount = "{m}" }},' for w, m, a in combos]
    lines += ["\t},", "\t--- Forename loc key of his name.", f'\tname = "names_name_{name_id()}",', "}"]
    with open(os.path.join(folder, f"{FILE}_rigs.lua"), "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--refresh", action="store_true", help="refresh the kept vanilla rows from the installed game's packs")
    args = parser.parse_args()
    if args.refresh:
        refresh()
    else:
        build()
    sys.exit(0)
