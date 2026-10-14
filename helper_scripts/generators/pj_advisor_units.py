"""Builds the Addvisor Overhaul's weapon and mount units: one land unit per valid (weapon, mount) pair, plus the skills, ancillaries, uniforms and
variants that let the player switch between them in campaign and pick them in custom battles.

How a pair reaches the battle map:
- A weapon skill and a mount skill unlock that weapon or mount. The default weapon and mount need no skill. The player picks the pair with the
  Change Loadout button in the Advisor's character panel, and `script/campaign/mod/pj_advisor_overhaul.lua` equips the pair's hidden mount ancillary.
- That ancillary's `provided_bodyguard_unit` is the pair's main unit, and `campaign_character_uniform_ancillary_junctions` swaps his uniform to the
  pair's, whose battle variant carries the weapon props (and the disc).

Unit rows start from a vanilla hero riding the same mount (the registry's `template`). His own stats go on top, plus the vanilla difference
between that hero mounted and on foot (hit points, charge, armour, melee). Monster mounts keep the template's melee weapon, which is the mount's.

The weapons, mounts and their animation sets are in pj_advisor_units_registry.json. The vanilla template rows are kept in pj_advisor_units.json.
Refresh it from a folder of vanilla TSVs after a game patch:

    python -m generators.pj_advisor_units --refresh _diag/vanilla_all/db

Build:

    python -m generators.pj_advisor_units
"""

import argparse
import json
import os
import shutil
import struct
import sys
import zlib
from typing import Dict, List, Tuple

from core.extract_cache import cached_pack_extract
from core.utilities import STEAM_LIBRARY_DRIVE, load_tsv_data
from generators import pj_advisor_anims as anims
from generators import pj_advisor_overhaul as lores

# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Settings

# Weapons and mounts.
REGISTRY = os.path.join(os.path.dirname(os.path.abspath(__file__)), "pj_advisor_units_registry.json")

# The vanilla template rows and table headers.
DATA = os.path.join(os.path.dirname(os.path.abspath(__file__)), "pj_advisor_units.json")

# The subscribed base Addvisor pack and where it is extracted to.
BASE_PACK = lores.BASE_PACK
BASE_EXTRACT = "./temp/pj_advisor_units_base"

# Portrait folders whose settings file the base mod ships.
PORTRAIT_FOLDERS = ("portholes", "units")

# The mod source folder.
MOD = lores.MOD

# File name of every table file this generator writes. It is new, so its rows add to the base mod's.
FILE = "pj_advisor_overhaul_units"

# The advisor's own foot unit, campaign art set, agent subtype and campaign animation set.
BASE_UNIT = "pj_advisor"
ART_SET = "pj_advisor"
SUBTYPE = "pj_advisor"
CAMPAIGN_ANIMATION = "cam_hu1_pr8_amethyst_staff_and_sword"

# A vanilla foot wizard whose row fills the columns the base mod's older land unit and main unit rows lack.
FOOT_TEMPLATE = "wh2_pro07_emp_cha_wizard_death_0"

# The rider entity for ordinary mounts. Mounts whose template uses another entity (the disc) keep the template's.
RIDER_ENTITY = "wh_main_infantry_standard_wizard_rider_blood_dismembers"

# The default pair. Both are always unlocked, so they get no skill.
DEFAULT_WEAPON = "staff_and_sword"
DEFAULT_MOUNT = "foot"

# Skill tree rows of the weapon and the mount skills (the 10-row skill panel).
WEAPON_ROW = 6
MOUNT_ROW = 7

# Land unit columns copied from the advisor, so every pair keeps his identity.
IDENTITY_COLUMNS = ["historical_description_text", "short_description_text", "accuracy", "campaign_action_points", "morale",
                    "visibility_spotting_range_min", "visibility_spotting_range_max", "selection_vo", "selected_vo_tertiary", "spell_mastery"]

# Land unit stats moved by the template's mounted-minus-foot difference.
DELTA_COLUMNS = ["bonus_hit_points", "charge_bonus", "melee_attack", "melee_defence"]

# Vanilla tables the refresh keeps headers for, and the tables whose template rows it keeps.
TABLES = [
    "land_units_tables", "main_units_tables", "unit_variants_tables", "variants_tables", "agent_uniforms_tables",
    "campaign_character_uniform_ancillary_junctions_tables", "ancillaries_tables", "ancillary_info_tables", "ancillaries_included_agent_subtypes_tables",
    "campaign_mount_animation_set_overrides_tables", "unit_attributes_groups_tables", "unit_attributes_to_groups_junctions_tables",
    "land_units_to_unit_abilites_junctions_tables", "special_ability_groups_to_units_junctions_tables", "units_custom_battle_permissions_tables",
    "units_custom_battle_mounts_tables", "battle_animations_table_tables", "character_skills_tables", "character_skill_nodes_tables",
    "character_skill_node_set_items_tables", "character_skill_level_details_tables", "character_skill_nodes_skill_locks_tables",
    "campaign_character_art_sets_tables", "campaign_character_arts_tables",
]
TEMPLATE_TABLES = {"land_units_tables": "key", "main_units_tables": "land_unit", "unit_attributes_to_groups_junctions_tables": "attribute_group"}


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Refresh


def refresh(folder: str) -> None:
    """Keeps the vanilla template rows the registry names and every written table's header and version.

    Args:
        folder (str): The folder holding `<table>/data__.tsv`.
    """
    registry = json.load(open(REGISTRY, encoding="utf-8"))
    wanted = {m[k] for m in registry["mounts"].values() for k in ("template", "template_foot") if k in m} | {FOOT_TEMPLATE}
    data = {"tables": {}, "templates": {}}
    for table in TABLES:
        rows, header, version = load_tsv_data(os.path.join(folder, table, "data__.tsv"))
        data["tables"][table] = {"header": header, "version": version.split("\t")[0].split(";")[1]}
        if table in TEMPLATE_TABLES:
            column = TEMPLATE_TABLES[table]
            land_groups = {r["attribute_group"] for r in data["templates"].get("land_units_tables", [])}
            keys = land_groups if table == "unit_attributes_to_groups_junctions_tables" else wanted
            data["templates"][table] = [r for r in rows if r[column] in keys]
    json.dump(data, open(DATA, "w", encoding="utf-8"), indent=1, sort_keys=True)
    print(f"kept {len(data['templates']['land_units_tables'])} template units in {DATA}")


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Build


def unit_key(weapon: str, mount: str, registry: Dict) -> str:
    """The land and main unit key of a pair. The base mod's own units keep their keys.

    Args:
        weapon (str): Weapon key.
        mount (str): Mount key.
        registry (Dict): The registry.

    Returns:
        str: The unit key.
    """
    if weapon == DEFAULT_WEAPON and mount == DEFAULT_MOUNT:
        return BASE_UNIT
    if weapon == DEFAULT_WEAPON and "existing_unit" in registry["mounts"][mount]:
        return registry["mounts"][mount]["existing_unit"]
    return f"pj_advisor_{weapon}_{mount}"


def weapon_art_set(weapon: str) -> str:
    """The art set that shows a weapon in the character panel.

    Args:
        weapon (str): The weapon key.

    Returns:
        str: The art set key.
    """
    return f"pj_advisor_art_{weapon}"


def choice_skill(kind: str, key: str) -> str:
    """The skill that picks a weapon or mount. The `choose` part keeps it clear of the base mod's `pj_advisor_mount_warhorse` (its Pegasus).

    Args:
        kind (str): `weapon` or `mount`.
        key (str): The weapon or mount key.

    Returns:
        str: The skill key.
    """
    return f"pj_advisor_choose_{kind}_{key}"


def ui_name(kind: str, key: str) -> str:
    """The loc key of a weapon or mount name, shown in the Change Loadout picker.

    Args:
        kind (str): `weapon` or `mount`.
        key (str): The weapon or mount key.

    Returns:
        str: The loc key.
    """
    return f"pj_advisor_overhaul_ui_{kind}_{key}"


def unlock_skill(kind: str, key: str, item: Dict) -> str:
    """The skill that unlocks a weapon or mount, or an empty string for the always unlocked default.

    Args:
        kind (str): `weapon` or `mount`.
        key (str): The weapon or mount key.
        item (Dict): The registry weapon or mount.

    Returns:
        str: The skill key, or an empty string.
    """
    if key == (DEFAULT_WEAPON if kind == "weapon" else DEFAULT_MOUNT):
        return ""
    return item.get("existing_skill") or choice_skill(kind, key)


def pairs(registry: Dict) -> List[Tuple[str, str]]:
    """Every valid (weapon, mount) pair: those with an animation set for that mount.

    Args:
        registry (Dict): The registry.

    Returns:
        List[Tuple[str, str]]: The pairs in registry order.
    """
    return [(w, m) for w, weapon in registry["weapons"].items() for m in registry["mounts"] if m in weapon["sets"]]


def base_rows() -> Tuple[Dict[str, List[Dict[str, str]]], Dict[str, bytes]]:
    """The base Addvisor's land unit, main unit, custom battle and art rows, plus its portrait settings files.

    Returns:
        Tuple[Dict[str, List[Dict[str, str]]], Dict[str, bytes]]: Table -> rows, and portrait folder (`portholes` / `units`) -> settings file bytes.

    Raises:
        SystemExit: When the base pack is not subscribed.
    """
    if not os.path.exists(BASE_PACK):
        raise SystemExit(f"base Addvisor pack not found at {BASE_PACK}")
    shutil.rmtree(BASE_EXTRACT, ignore_errors=True)
    try:
        cached_pack_extract(BASE_PACK, "db", BASE_EXTRACT)
        cached_pack_extract(BASE_PACK, "ui/portraits", BASE_EXTRACT)
        out = {}
        for table in ("land_units_tables", "main_units_tables", "units_custom_battle_permissions_tables", "campaign_character_arts_tables"):
            out[table] = load_tsv_data(os.path.join(BASE_EXTRACT, "db", table, "pj_advisor.tsv"))[0]
        portraits = {}
        for folder in PORTRAIT_FOLDERS:
            with open(os.path.join(BASE_EXTRACT, "ui", "portraits", folder, f"portrait_settings__{BASE_UNIT}.bin"), "rb") as f:
                portraits[folder] = f.read()
        return out, portraits
    finally:
        shutil.rmtree(BASE_EXTRACT, ignore_errors=True)


def number(value: str) -> float:
    """Reads a TSV number, treating empty as 0.

    Args:
        value (str): The cell.

    Returns:
        float: The number.
    """
    return float(value) if value else 0.0


def land_unit(key: str, weapon: Dict, set_name: str, mount: Dict, templates: Dict, advisor: Dict[str, str]) -> Dict[str, str]:
    """A pair's land unit row.

    Args:
        key (str): The unit key.
        weapon (Dict): The registry weapon.
        set_name (str): The battle animation set.
        mount (Dict): The registry mount.
        templates (Dict): Template land units by key.
        advisor (Dict[str, str]): The advisor's foot land unit.

    Returns:
        Dict[str, str]: The row.
    """
    if "template" not in mount:
        row = dict(advisor)
        row.update({"key": key, "man_animation": set_name, "shield": weapon["shield"], "attribute_group": BASE_UNIT})
        return row
    mounted, foot = templates[mount["template"]], templates[mount["template_foot"]]
    row = dict(mounted)
    for column in IDENTITY_COLUMNS:
        row[column] = advisor.get(column, row[column])
    for column in DELTA_COLUMNS:
        row[column] = str(int(number(advisor[column]) + number(mounted[column]) - number(foot[column])))
    if mounted["armour"] == foot["armour"]:
        row["armour"] = advisor["armour"]
    if mounted["primary_melee_weapon"] == foot["primary_melee_weapon"]:
        row["primary_melee_weapon"] = advisor["primary_melee_weapon"]
    if mounted["mount"]:
        row["man_entity"] = RIDER_ENTITY
    row.update({"key": key, "man_animation": set_name, "shield": weapon["shield"], "attribute_group": key})
    return row


def build() -> None:
    """Writes every unit, skill, ancillary, uniform and variant of the registry's pairs into the mod folder."""
    registry = json.load(open(REGISTRY, encoding="utf-8"))
    data = json.load(open(DATA, encoding="utf-8"))
    specs, templates = data["tables"], data["templates"]
    template_units = {r["key"]: r for r in templates["land_units_tables"]}
    template_main = {r["land_unit"]: r for r in templates["main_units_tables"]}
    template_attributes = {}
    for r in templates["unit_attributes_to_groups_junctions_tables"]:
        template_attributes.setdefault(r["attribute_group"], []).append(r["attribute"])
    base, portraits = base_rows()
    # The base rows are an older table version, so they go on top of a vanilla foot wizard's to fill the newer columns.
    advisor = dict(template_units[FOOT_TEMPLATE], **next(r for r in base["land_units_tables"] if r["key"] == BASE_UNIT))
    advisor_main = dict(template_main[FOOT_TEMPLATE], **next(r for r in base["main_units_tables"] if r["unit"] == BASE_UNIT))
    lore_groups = sorted(json.load(open(lores.DATA, encoding="utf-8"))["lores"])

    rows: Dict[str, List[Dict[str, str]]] = {table: [] for table in TABLES}
    texts: List[Tuple[str, str]] = []
    variants: Dict[str, str] = {}
    combos: List[Tuple[str, str, str]] = []
    unique_index = 1493349200

    for weapon_key, mount_key in pairs(registry):
        weapon, mount = registry["weapons"][weapon_key], registry["mounts"][mount_key]
        key = unit_key(weapon_key, mount_key, registry)
        ancillary = f"pj_advisor_rig_{weapon_key}_{mount_key}"
        uniform = f"pj_advisor_{weapon_key}_{mount_key}"
        variant = f"pj_advisor_{weapon_key}" + ("_" + mount_key if "variant_props" in mount else "")
        combos.append((weapon_key, mount_key, ancillary))
        new_unit = key not in (BASE_UNIT, mount.get("existing_unit"))

        if new_unit:
            rows["land_units_tables"].append(land_unit(key, weapon, weapon["sets"][mount_key], mount, template_units, advisor))
            main = dict(template_main[mount["template"]]) if "template" in mount else dict(advisor_main)
            main.update({k: advisor_main.get(k, main[k]) for k in ("audio_voiceover_culture", "audio_voiceover_actor_group", "campaign_cap")})
            main.update({"unit": key, "land_unit": key, "unique_index": str(unique_index), "caste": "hero"})
            unique_index += 1
            rows["main_units_tables"].append(main)
            rows["unit_attributes_groups_tables"].append({"group_name": key})
            attributes = set(template_attributes.get(mount.get("template", ""), [])) | {"encourages", "spell_mastery"}
            attributes -= {"mark_tzeentch"}
            rows["unit_attributes_to_groups_junctions_tables"] += [{"attribute": a, "attribute_group": key} for a in sorted(attributes)]
            rows["land_units_to_unit_abilites_junctions_tables"].append({"ability": "wh3_main_unit_passive_single_entity", "land_unit": key, "culture": "*"})
            rows["special_ability_groups_to_units_junctions_tables"] += [{"ability_group": g, "unit": key, "group_page_order": str(i)} for i, g in enumerate(lore_groups)]
            for perm in base["units_custom_battle_permissions_tables"]:
                if perm["unit"] == BASE_UNIT:
                    rows["units_custom_battle_permissions_tables"].append(dict(perm, unit=key, set_piece_character=BASE_UNIT, general_uniform=uniform))
            if mount_key != DEFAULT_MOUNT:
                rows["units_custom_battle_mounts_tables"].append({"base_unit": unit_key(weapon_key, DEFAULT_MOUNT, registry), "mounted_unit": key,
                                                                  "icon_name": mount["icon"]})
            rows["unit_variants_tables"].append({"unit": key, "name": BASE_UNIT, "variant": variant, "unit_card": BASE_UNIT})
            texts.append((f"land_units_onscreen_name_{key}", f"The Advisor ({weapon['name']}, {mount['name']})"))

        rows["ancillaries_tables"].append({
            "key": ancillary, "type": mount["ancillary_type"], "applies_to": ".", "transferrable": "false", "unique_to_world": "false",
            "unique_to_faction": "false", "precedence": "1", "start_date": "0", "end_date": "9999", "legendary_item": "false", "mp_exclusive": "false",
            "is_wife_ancillary": "false", "category": "mount", "min_starting_age": "16", "max_starting_age": "30", "min_expiry_age": "30",
            "max_expiry_age": "50", "immortal": "true", "provided_bodyguard_unit": key, "uniqueness_score": "1", "turns_before_swap_allowed": "0",
            "randomly_dropped": "false", "can_be_stolen": "false", "can_be_destroyed": "false", "faction_set": "all",
        })
        rows["ancillary_info_tables"].append({"ancillary": ancillary})
        rows["ancillaries_included_agent_subtypes_tables"].append({"agent_subtype": SUBTYPE, "ancillary": ancillary})
        for art_set in [ART_SET, *(weapon_art_set(w) for w in registry["weapons"])]:
            rows["campaign_character_uniform_ancillary_junctions_tables"].append({"ancillary": ancillary, "art_set": art_set, "uniform": uniform})
        # The campaign map model and the character panel model show the weapon. Both use the weapon's foot variant, so mount props such as the disc
        # stay out of them.
        rows["agent_uniforms_tables"].append({"uniform_name": uniform, "filename": f"pj_advisor_{weapon_key}", "battle_filename": variant,
                                              "campaign_porthole_filename": f"pj_advisor_{weapon_key}"})
        if "campaign_rider_set" in mount and mount_key != DEFAULT_MOUNT:
            # The base art set keeps the staff idle, and each weapon art set uses its weapon's, so both get the rider pose.
            rider = weapon.get("campaign_rider_sets", {}).get(mount_key, mount["campaign_rider_set"])
            for character_set in dict.fromkeys([CAMPAIGN_ANIMATION, weapon.get("campaign_set", CAMPAIGN_ANIMATION)]):
                rows["campaign_mount_animation_set_overrides_tables"].append({"character_animation_set": character_set, "mount_unit": key,
                                                                             "rider_animation_set": rider, "vfx_filter_override": "0"})
        texts.append((f"ancillaries_onscreen_name_{ancillary}", f"{weapon['name']}, {mount['name']}"))
        texts.append((f"ancillaries_colour_text_{ancillary}", f"{weapon['description']} {mount['description']}"))
        props = dict(weapon["props"])
        props.update(mount.get("variant_props", {}))
        variants[variant] = props

    for variant in variants:
        rows["variants_tables"].append({"variant_name": variant, "variant_filename": variant, "mount_scale": "1.0000", "scale": "1.1500", "scale_variation": "0.0000"})
    for set_name in [*anims.SETS, *anims.DERIVED_SETS]:
        rows["battle_animations_table_tables"].append({"key": set_name, "skeleton": anims.TARGET_SKELETON})

    # Weapon and mount skills: each unlocks its item for the Change Loadout picker.
    for row, kind, items, default in ((WEAPON_ROW, "weapon", registry["weapons"], DEFAULT_WEAPON), (MOUNT_ROW, "mount", registry["mounts"], DEFAULT_MOUNT)):
        for item_key, item in items.items():
            texts.append((ui_name(kind, item_key), item["name"]))
        for tier, (item_key, item) in enumerate(items.items()):
            # The default is always unlocked. A base mod skill (the Pegasus) already has its own node.
            if item_key == default or "existing_skill" in item:
                continue
            skill = choice_skill(kind, item_key)
            node = f"pj_advisor_choose_{kind}_node_{item_key}"
            rows["character_skills_tables"].append({
                "key": skill, "image_path": item.get("skill_icon") or os.path.basename(item["icon"]), "unlocked_at_rank": "0", "is_background_skill": "false",
                "is_female_only_background_skill": "false", "is_male_only_background_skill": "false", "background_weighting": "0.0000", "influence_cost": "0",
            })
            texts.append((f"character_skills_localised_name_{skill}", item["name"]))
            texts.append((f"character_skills_localised_description_{skill}", f"{item['description']}\\\\n\\\\nUnlocks this {kind} for the Advisor's loadout. "
                          "Switch to it with the Change Loadout button in his character panel."))
            rows["character_skill_nodes_tables"].append({
                "key": node, "character_skill_key": skill, "indent": str(row), "tier": str(tier), "points_on_creation": "0", "required_num_parents": "0",
                "visible_in_ui": "true",
            })
            rows["character_skill_node_set_items_tables"].append({"set": SUBTYPE, "item": node, "mod_disabled": "false"})
            # Without a level row the skill has 0 levels: the tree draws it as learned while `has_skill` stays false.
            rows["character_skill_level_details_tables"].append({
                "campaign_key": "", "faction_key": "", "level": "1", "skill_key": skill, "subculture_key": "", "image_path": "x",
                "unlocked_at_rank": str(item.get("unlock_rank", 1)),
            })

    # One art set per weapon. The character panel's model follows only the art set, so the script switches it with the weapon.
    base_art = next(r for r in base["campaign_character_arts_tables"] if r["art_set_id"] == ART_SET)
    for weapon_key in registry["weapons"]:
        art_set = weapon_art_set(weapon_key)
        rows["campaign_character_art_sets_tables"].append({
            "art_set_id": art_set, "agent_type": "wizard", "culture": "", "subculture": "", "faction": "", "is_custom": "false", "is_male": "true",
            "agent_subtype": SUBTYPE, "campaign_map_scale": "1.0000", "prebattle_separation_offset": "0.0000",
        })
        rows["campaign_character_arts_tables"].append(dict(base_art, id=str(zlib.crc32(art_set.encode()) & 0x7FFFFFFF), art_set_id=art_set,
                                                           uniform=f"pj_advisor_{weapon_key}_{DEFAULT_MOUNT}",
                                                           land_animation=registry["weapons"][weapon_key].get("campaign_set", CAMPAIGN_ANIMATION)))

    for table, column in (("land_units_tables", "key"), ("character_skills_tables", "key"), ("ancillaries_tables", "key"),
                          ("agent_uniforms_tables", "uniform_name")):
        keys = [r[column] for r in rows[table]]
        if len(keys) != len(set(keys)):
            raise SystemExit(f"duplicate keys in {table}: {sorted(k for k in set(keys) if keys.count(k) > 1)}")
    for table, table_rows in rows.items():
        if table_rows:
            lores.write(table, FILE, table_rows, specs[table])
    write_variants(variants)
    # The base entry's id is both the base art set and the base variant, so the new entries cover the weapon art sets and the weapon variants.
    write_portraits(portraits, [weapon_art_set(w) for w in registry["weapons"]] + [f"pj_advisor_{w}" for w in registry["weapons"]])
    write_script(registry, combos)
    loc = os.path.join(MOD, "text", "db", f"{FILE}.loc.tsv")
    with open(loc, "w", encoding="utf-8", newline="\n") as f:
        f.write(f"key\ttext\ttooltip\n#Loc;1;text/db/{FILE}.loc\t\t\n")
        f.write("".join(f"{key}\t{text}\ttrue\n" for key, text in texts))
    print(f"wrote {len(combos)} pairs ({len(rows['land_units_tables'])} new units, {len(variants)} variants) to {MOD}")


def write_variants(variants: Dict[str, Dict]) -> None:
    """Writes one variant mesh definition per weapon (and per weapon on a prop mount such as the disc).

    Args:
        variants (Dict[str, Dict]): Variant name -> slot -> (attach point, model, metadata).
    """
    folder = os.path.join(MOD, "variantmeshes", "variantmeshdefinitions")
    os.makedirs(folder, exist_ok=True)
    slots = {"weapon_1": "be_prop_0", "weapon_2": "be_prop_1", "shield": "be_prop_2", "weapon_3": "be_prop_3", "weapon_4": "be_prop_4", "weapon_5": "be_prop_5"}
    for name, props in variants.items():
        lines = ["<VARIANT_MESH>", '\t<SLOT name="body" >', '\t\t<VARIANT_MESH model="pj_advisor\\pj_advisor_body.wsmodel" >',
                 "\t\t\t<META_DATA>audio_armour_type:leather</META_DATA></VARIANT_MESH>", "\t</SLOT>", '\t<SLOT name="head" >',
                 '\t\t<VARIANT_MESH model="pj_advisor\\pj_advisor_head.wsmodel" />', "\t</SLOT>"]
        for slot, point in slots.items():
            if slot not in props:
                lines.append(f'\t<SLOT name="{slot}" attach_point="{point}" />')
                continue
            _, model, meta = props[slot]
            lines.append(f'\t<SLOT name="{slot}" attach_point="{point}" >')
            if model.lower().endswith(".variantmeshdefinition"):
                lines.append(f'\t\t<VARIANT_MESH_REFERENCE definition="{model}" />')
            else:
                tail = f"<META_DATA>{meta}</META_DATA>" if meta else ""
                lines.append(f'\t\t<VARIANT_MESH model="{model}" >{tail}</VARIANT_MESH>')
            lines.append("\t</SLOT>")
        lines.append("</VARIANT_MESH>")
        with open(os.path.join(folder, f"{name}.variantmeshdefinition"), "w", encoding="utf-8", newline="\n") as f:
            f.write("\n".join(lines) + "\n")


def write_portraits(portraits: Dict[str, bytes], art_sets: List[str]) -> None:
    """Writes portrait settings for the weapon art sets: one copy of the base Advisor's entry per art set, with the art set id swapped in. Without
    them a character on a new art set has no portrait.

    The file is a u32 version, a u32 entry count, then the entries. Each entry starts with its id as a u16-length-prefixed string.

    Args:
        portraits (Dict[str, bytes]): Portrait folder -> the base settings file.
        art_sets (List[str]): The ids to write entries for.

    Raises:
        SystemExit: When the base file does not hold exactly one entry for the base art set.
    """
    base_id = ART_SET.encode("ascii")
    for folder, data in portraits.items():
        version, count = struct.unpack_from("<II", data, 0)
        prefix = struct.pack("<H", len(base_id)) + base_id
        if count != 1 or data[8:8 + len(prefix)] != prefix:
            raise SystemExit(f"unexpected base portrait settings in {folder}: {count} entries")
        tail = data[8 + len(prefix):]
        entries = b"".join(struct.pack("<H", len(a)) + a.encode("ascii") + tail for a in art_sets)
        out = os.path.join(MOD, "ui", "portraits", folder)
        os.makedirs(out, exist_ok=True)
        with open(os.path.join(out, f"portrait_settings__{FILE}.bin"), "wb") as f:
            f.write(struct.pack("<II", version, len(art_sets)) + entries)


def write_script(registry: Dict, combos: List[Tuple[str, str, str]]) -> None:
    """Writes the Lua data table the campaign script reads: the weapons and mounts with their unlock skills and names, and the ancillary of every
    valid pair.

    Args:
        registry (Dict): The registry.
        combos (List[Tuple[str, str, str]]): (weapon, mount, ancillary) per valid pair.
    """
    folder = os.path.join(MOD, "script", "campaign", "mod")
    os.makedirs(folder, exist_ok=True)
    lines = ["--- Generated by generators/pj_advisor_units.py. Do not edit by hand.", "PJ_ADVISOR_OVERHAUL_RIGS = {",
             "\t--- Weapon he holds when nothing else is chosen. Always unlocked.", f'\tdefault_weapon = "{DEFAULT_WEAPON}",',
             "\t--- Mount he rides when nothing else is chosen. Always unlocked.", f'\tdefault_mount = "{DEFAULT_MOUNT}",']
    for kind, items in (("weapon", registry["weapons"]), ("mount", registry["mounts"])):
        lines += [f"\t--- {kind.capitalize()}s in skill tree order: key, unlock skill (empty for the default), name loc key, an English fallback name and,"
                  " for weapons, the art set that shows it in the character panel.",
                  f"\t{kind}s = {{"]
        for key, item in items.items():
            name = item["name"].replace('"', '\\"')
            art = f', art_set = "{weapon_art_set(key)}"' if kind == "weapon" else ""
            lines.append(f'\t\t{{ key = "{key}", skill = "{unlock_skill(kind, key, item)}", name = "{ui_name(kind, key)}", fallback = "{name}"{art} }},')
        lines += ["\t},", f"\t--- Unlock skill key -> {kind} key.", f"\t{kind}_skills = {{"]
        lines += [f'\t\t["{unlock_skill(kind, key, item)}"] = "{key}",' for key, item in items.items() if unlock_skill(kind, key, item)]
        lines.append("\t},")
    lines += ['\t--- "weapon|mount" -> the mount ancillary that gives him that unit. Only pairs with a unit are listed.', "\tancillaries = {"]
    lines += [f'\t\t["{w}|{m}"] = "{a}",' for w, m, a in combos]
    lines += ["\t},", "\t--- Ancillaries from the base mod that the script must also remove when it swaps.", "\tlegacy_ancillaries = {"]
    lines += [f'\t\t"{m["existing_ancillary"]}",' for m in registry["mounts"].values() if "existing_ancillary" in m]
    lines += ["\t},", "}"]
    with open(os.path.join(folder, "pj_advisor_overhaul_rigs.lua"), "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--refresh", metavar="FOLDER", help="refresh the kept vanilla template rows from a folder of vanilla TSVs")
    args = parser.parse_args()
    if args.refresh:
        refresh(args.refresh)
    else:
        build()
    sys.exit(0)
