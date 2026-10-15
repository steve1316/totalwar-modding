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
- `forms`: mount -> values that replace the computed ones for that one pair, and `props`: prop slots whose model that pair uses instead (its own
  variant then).
- `attributes` adds unit attributes to every pair of the weapon, and `attributes_removed` takes them away. `abilities` and `abilities_removed` do
  the same for unit abilities.

How a weapon looks on every one of its mounts (all optional, written by the workbench's Look tab): `body` picks his outfit from `model.bodies`,
`hood` false takes his hood off (when his head has a hoodless model), and `pieces` adds models such as a hat: slot -> [model, metadata...], or
[bone, model, metadata...] for a prop held on that bone (a book on his hip). `piece_shapes` moves, turns and sizes a prop piece on its own
(slot -> `offset` [x, y, z] metres, `turn` [x, y, z] degrees, `size`), so two pieces of the same model can point different ways. An
outfit in `model.unpainted` (key -> true) is worn without its faction colours or heraldry, as copies `generators.advisor_overhaul_model` writes.

New weapons made with the workbench's New form dialog are marked `workbench`. Their `sets` hold only `humanoid01` sets, which build as they are.
A set picked from another skeleton waits in `retarget` (mount -> `set`, `skeleton`, and `handoff` and `note` once it is handed to Claude) until it
is retargeted into a set of his own and moved to `sets`. A weapon with no sets yet is left out of the build.

His planned skills are the registry's `skills` (written by the workbench's Skills tab): id -> `name`, `description`, `icon` (a file in
`ui/campaign ui/skills`), `row` and `tier` in the tree, `rank` it unlocks at, `levels` (each a list of `effect`, `scope`, `value`), `requires` (ids
of skills it needs: all of them, or any `needs` of them), `exclusive` (ids of skills it locks, both ways), `locked_by` (ids of skills that lock it
one way, such as a pact choice), `hidden` (no node shown, for skills a script gives him, with `learned` giving it to him when he is made), `slot`
(an art slot, whose effect is the held weapon's art for that slot) and `build`. Only skills with `build` (In game in the workbench) are written.
Drafts stay in the workbench. A weapon or mount with `unlock` "script" gets a hidden skill too: only a script unlocks it (the Disc, from the pact).

The rest of his kit, also in the registry:
- `weapons.<w>.arts`: slot -> `name`, `description`, `effects` (each `effect`, `scope`, `value`). Each is an effect bundle, which the loadout
  script puts on him while he holds that weapon and owns the slot's skill. Every weapon must define every slot a built skill uses.
- `bundles`: id -> `name`, `description`, `icon`, `effects`. Effect bundles the story script puts on him (the pact's corruption, its debt).
- `actions`: vanilla hero action keys copied for him, a wizard. Each copy gets its own enable effect (`action_effect_key`) that a skill level
  gives, and the vanilla action's name and description.
- `items`: id -> `name`, `description`, `type` (a vanilla ancillary type), `category`, `effects`. His quest items.
- `lores`: vanilla lore key -> `name`, `icon`, `row`, `tier`, `rank`, `build`. One 3-level skill per lore, its spells read from vanilla at
  `--refresh`: level 1 the lore's passive and its `LORE_FIRST_SPELLS` cheapest spells, level 2 every spell, level 3 every spell and its overcast.
- `zones`: groups of skills spanning two rows, each `title`, `description`, `rows` (top and bottom) and `skills` (ids in reading order, top to
  bottom then left to right, placed in the two rows by turns). `script/campaign/mod/advisor_overhaul_zones.lua` heads each zone with a label
  column and pads the rows so every zone lines up.

Each tree row's cards take that row's colour from `ROW_COLOURS`, through a skill category for his subtype only.

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

# The registry's `model` maps of weapon changes (model path -> offset, turn or size). A weapon in any of them gets a changed copy.
PROP_CHANGES = ("prop_offsets", "prop_turns", "prop_sizes")

# Folder of the weapon copies `PROP_CHANGES` make (written by `generators.advisor_overhaul_model`).
PROP_FOLDER = "variantmeshes/wh_variantmodels/hu1/advisor_overhaul/props"

# Folder of the outfit copies `model.unpainted` makes, their materials in its `materials` folder (written by `generators.advisor_overhaul_model`).
UNPAINTED_FOLDER = "variantmeshes/wh_variantmodels/hu1/advisor_overhaul/unpainted"

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

# Row of every hidden skill node, one tier each in the order they are added. Two nodes in one slot drop one of them.
HIDDEN_ROW = 99

# Hidden vanilla skills his tree holds: (skill, learned when he is made). It raises his hero actions' success chance with his rank. He has no
# hidden skill that turns on hero actions, as the Amethyst Wizard has: each action is unlocked by a point in its own node (rows 6 and 7).
HIDDEN_SKILLS = [("wh3_main_skill_agent_action_success_scaling", False)]

# Effect bundle values for a bundle on him. `advancement_stage` must be `start_turn_completed`, or the game crashes on load.
BUNDLE_STAGE = "start_turn_completed"

# His agent attribute, which copied hero actions of other agents use instead of their own.
AGENT_ATTRIBUTE = "authority"

# Lores of magic that are no lore a caster can learn: Kroak's own, the Kemmler prologue lore with no spells, and the Cataclysm spells.
LORE_SKIPPED = {"wh2_dlc12_lore_lord_kroak", "wh_pro03_lore_kemmler", "wh3_main_cataclysm_spells"}

# Card colour of each of his tree rows, top to bottom (a `character_skill_categories` row each, for his subtype only).
ROW_COLOURS = ["F1413D", "3DA5F1", "F1C43D", "9B3DF1", "3DF17A", "F13DC4", "F1813D", "3DF1E8", "8A8A8A", "FFFFFF"]

# Spells a lore skill's first level gives, the cheapest first, and how many levels a lore skill has.
LORE_FIRST_SPELLS = 3
LORE_LEVELS = 3

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
    "projectiles_tables", "melee_weapons_tables", "unit_armour_types_tables", "character_skill_node_links_tables",
    "character_skill_level_to_effects_junctions_tables", "character_skill_nodes_skill_locks_tables", "effects_tables", "effect_bundles_tables",
    "effect_bundles_to_effects_junctions_tables", "agent_actions_tables", "effect_bonus_value_agent_action_record_junctions_tables",
    "ancillary_to_effects_tables", "character_skill_categories_tables", *UNIT_ROW_TABLES,
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


def load_registry() -> Dict:
    """The registry, without the weapons that have no animation set yet (new forms waiting for their sets to be retargeted).

    Returns:
        Dict: The registry.
    """
    registry = json.load(open(REGISTRY, encoding="utf-8"))
    registry["weapons"] = {key: weapon for key, weapon in registry["weapons"].items() if weapon.get("sets")}
    return registry


def read_vanilla(table: str) -> Tuple[List[Dict[str, str]], List[str], str]:
    """Reads one vanilla table from db.pack, through the extract cache.

    Args:
        table (str): The table name.

    Returns:
        Tuple[List[Dict[str, str]], List[str], str]: The rows, the header and the version line.
    """
    return load_tsv_data(f"{extract_tsv_data(table)}/db/{table}/data__.tsv")


def vanilla_lores() -> Dict[str, Dict]:
    """Every learnable lore of magic, with the effect that enables each of its spells and the one that lets it be overcast.

    Each spell is enabled by several effects: its own, a whole-lore one and some for single characters. The one kept enables only that spell, and
    one a vanilla skill uses is preferred. Spells with no overcast effect of their own keep none.

    Returns:
        Dict[str, Dict]: Lore key -> `passives` (enable effects) and `spells` (each `enable`, `overcast` or None, and `cost`), cheapest first.
    """
    groups = read_vanilla("special_ability_groups_tables")[0]
    lores = sorted(r["ability_group"] for r in groups if r["is_composite_group"] == "false" and r["show_lore_icon"] == "true"
                   and r["ability_group"] not in LORE_SKIPPED)
    abilities = {r["key"]: r for r in read_vanilla("unit_special_abilities_tables")[0]}
    used = {r["effect_key"] for r in read_vanilla("character_skill_level_to_effects_junctions_tables")[0]}
    targets: Dict[Tuple[str, str], set] = {}
    for r in read_vanilla("effect_bonus_value_unit_ability_junctions_tables")[0]:
        targets.setdefault((r["effect"], r["bonus_value_id"]), set()).add(r["unit_ability"])

    def own(spell: str, bonus: str) -> Optional[str]:
        """The effect giving only this spell this bonus value, or None."""
        keys = sorted((e for (e, b), t in targets.items() if b == bonus and t == {spell}), key=lambda e: (e not in used, len(e), e))
        return keys[0] if keys else None

    out: Dict[str, Dict] = {}
    members = read_vanilla("special_ability_groups_to_unit_abilities_junctions_tables")[0]
    for lore in lores:
        passives, spells = [], []
        for spell in sorted(r["unit_special_abilities"] for r in members if r["special_ability_groups"] == lore):
            enable, row = own(spell, "enable"), abilities.get(spell, {})
            if not enable:
                continue
            if row.get("passive") == "true":
                passives.append(enable)
            else:
                spells.append({"enable": enable, "overcast": own(spell, "enable_overchage"), "cost": float(row.get("mana_cost") or 0)})
        out[lore] = {"passives": passives, "spells": sorted(spells, key=lambda s: (s["cost"], s["enable"]))}
    return out


def refresh() -> None:
    """Keeps the vanilla rows the build reads and every written table's header and version."""
    registry = load_registry()
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
    data["effects"] = sorted(r["effect"] for r in loaded["effects_tables"])
    data["ancillary_types"] = sorted(r["type"] for r in read_vanilla("ancillary_types_tables")[0])
    data["lores"] = vanilla_lores()
    actions = set(registry.get("actions", []))
    data["actions"] = {"rows": {r["unique_id"]: r for r in loaded["agent_actions_tables"] if r["unique_id"] in actions},
                       "links": [r for r in loaded["effect_bonus_value_agent_action_record_junctions_tables"] if r["agent_action_record"] in actions]}
    data["scopes"] = sorted(r["key"] for r in read_vanilla("campaign_effect_scopes_tables")[0])
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


def art_bundle_key(weapon: str, slot: str) -> str:
    """The effect bundle of a weapon's art for one art slot.

    Args:
        weapon (str): The weapon key.
        slot (str): The art slot.

    Returns:
        str: The bundle key.
    """
    return f"{PREFIX}_weapon_art_{weapon}_{slot}"


def bundle_key(bundle_id: str) -> str:
    """The effect bundle of one of the registry's `bundles`.

    Args:
        bundle_id (str): Its id.

    Returns:
        str: The bundle key.
    """
    return f"{PREFIX}_bundle_{bundle_id}"


def action_short(action: str) -> str:
    """A vanilla hero action key without its game and pack prefix: `champion_assist_army_scavenge`.

    Args:
        action (str): The vanilla action key.

    Returns:
        str: The short name.
    """
    return action.split("agent_action_", 1)[-1]


def action_key(action: str) -> str:
    """His copy of a vanilla hero action.

    Args:
        action (str): The vanilla action key.

    Returns:
        str: The copy's key.
    """
    return f"{PREFIX}_action_{action_short(action)}"


def action_effect_key(action: str) -> str:
    """The effect that enables his copy of a vanilla hero action, given by a skill level.

    Args:
        action (str): The vanilla action key.

    Returns:
        str: The effect key.
    """
    return f"{PREFIX}_effect_enable_{action_short(action)}"


def lore_skill_key(lore: str) -> str:
    """The skill of one lore of magic.

    Args:
        lore (str): The vanilla lore key, such as `wh_main_lore_death`.

    Returns:
        str: The skill key, such as `advisor_overhaul_lore_death`.
    """
    return f"{PREFIX}_lore_{lore.split('_lore_', 1)[-1]}"


def item_key(item_id: str) -> str:
    """The ancillary of one of his quest items.

    Args:
        item_id (str): Its id in the registry's `items`.

    Returns:
        str: The ancillary key.
    """
    return f"{PREFIX}_item_{item_id}"


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


def fixed_skills(registry: Dict) -> List[Dict]:
    """The weapon and mount skills, where they sit in the tree: every weapon and mount but the defaults, one row each.

    Args:
        registry (Dict): The registry.

    Returns:
        List[Dict]: `kind`, `key` (item key), `item` (the registry item), `row`, `tier`, `hidden`, `skill` and `node` keys, `name` and `icon`. A
        hidden one (`unlock` "script") takes no tier, since `add_node` puts it on `HIDDEN_ROW`.
    """
    skills = []
    for row, kind, items, default in ((WEAPON_ROW, "weapon", registry["weapons"], DEFAULT_WEAPON), (MOUNT_ROW, "mount", registry["mounts"], DEFAULT_MOUNT)):
        tier = 0
        for key, item in items.items():
            if key == default:
                continue
            hidden = item.get("unlock") == "script"
            skills.append({"kind": kind, "key": key, "item": item, "row": row, "tier": None if hidden else tier, "hidden": hidden,
                           "skill": choice_skill(kind, key), "node": f"{PREFIX}_choose_{kind}_node_{key}", "name": item["name"],
                           "icon": item.get("skill_icon") or os.path.basename(item["icon"])})
            tier += 0 if hidden else 1
    return skills


def add_node(rows: Dict[str, List[Dict[str, str]]], node: str, skill: str, row: Any, tier: Any, hidden: bool = False, learned: bool = False,
             parents: int = 0) -> None:
    """Adds one node to his tree. A hidden node goes unseen on `HIDDEN_ROW`, in the next free tier, whatever row and tier it was given.

    Args:
        rows (Dict[str, List[Dict[str, str]]]): Rows by table, added to.
        node (str): The node key.
        skill (str): The skill key.
        row (Any): Its row.
        tier (Any): Its place in the row.
        hidden (bool): Whether the tree hides it.
        learned (bool): Whether he is made with it.
        parents (int): `required_num_parents`.
    """
    nodes = rows["character_skill_nodes_tables"]
    if hidden:
        row, tier = HIDDEN_ROW, sum(1 for n in nodes if n["indent"] == str(HIDDEN_ROW))
    nodes.append({"key": node, "character_skill_key": skill, "indent": str(row), "tier": str(tier), "points_on_creation": "1" if learned else "0",
                  "required_num_parents": str(parents), "visible_in_ui": "false" if hidden else "true"})
    rows["character_skill_node_set_items_tables"].append({"set": NODE_SET, "item": node, "mod_disabled": "false"})


def effect_value(effect: Dict) -> str:
    """An effect's value as the effect junction tables write it.

    Args:
        effect (Dict): `effect`, `scope`, `value`.

    Returns:
        str: The value with four decimals.
    """
    return f"{float(effect.get('value', 0)):.4f}"


def ancillary_rows(rows: Dict[str, List[Dict[str, str]]], key: str, kind: str, category: str, **columns: str) -> None:
    """Adds one ancillary only he can hold.

    Args:
        rows (Dict[str, List[Dict[str, str]]]): Rows by table, added to.
        key (str): The ancillary key.
        kind (str): Its ancillary type.
        category (str): Its category.
        **columns (str): Other columns that differ from the defaults.
    """
    rows["ancillaries_tables"].append({
        "key": key, "type": kind, "applies_to": ".", "transferrable": "false", "unique_to_world": "false", "unique_to_faction": "false",
        "precedence": "1", "start_date": "0", "end_date": "9999", "legendary_item": "false", "mp_exclusive": "false", "is_wife_ancillary": "false",
        "category": category, "min_starting_age": "16", "max_starting_age": "30", "min_expiry_age": "30", "max_expiry_age": "50", "immortal": "true",
        "provided_bodyguard_unit": "", "uniqueness_score": "1", "turns_before_swap_allowed": "0", "randomly_dropped": "false", "can_be_stolen": "false",
        "can_be_destroyed": "false", "faction_set": "all", **columns,
    })
    rows["ancillary_info_tables"].append({"ancillary": key})
    rows["ancillaries_included_agent_subtypes_tables"].append({"agent_subtype": SUBTYPE, "ancillary": key})


def skill_rows(registry: Dict, rows: Dict[str, List[Dict[str, str]]], texts: List[Tuple[str, str]]) -> None:
    """Adds the weapon and mount skills. Each unlocks its item for the Change Loadout picker.

    Args:
        registry (Dict): The registry.
        rows (Dict[str, List[Dict[str, str]]]): Rows by table, added to.
        texts (List[Tuple[str, str]]): Loc rows, added to.
    """
    for kind, items in (("weapon", registry["weapons"]), ("mount", registry["mounts"])):
        for item_key, item in items.items():
            texts.append((ui_name(kind, item_key), item["name"]))
    for fixed in fixed_skills(registry):
        kind, item, skill = fixed["kind"], fixed["item"], fixed["skill"]
        rows["character_skills_tables"].append({
            "key": skill, "image_path": fixed["icon"], "unlocked_at_rank": "0", "is_background_skill": "false",
            "is_female_only_background_skill": "false", "is_male_only_background_skill": "false", "background_weighting": "0.0000", "influence_cost": "0",
        })
        texts.append((f"character_skills_localised_name_{skill}", item["name"]))
        texts.append((f"character_skills_localised_description_{skill}", f"{item['description']}\\\\n\\\\nUnlocks this {kind} for the Advisor. "
                      "Switch to it with the Change Loadout button in his character panel."))
        add_node(rows, fixed["node"], skill, fixed["row"], fixed["tier"], fixed["hidden"])
        # Without a level row the skill has 0 levels: the tree draws it as learned while `has_skill` stays false.
        rows["character_skill_level_details_tables"].append({
            "campaign_key": "", "faction_key": "", "level": "1", "skill_key": skill, "subculture_key": "", "image_path": "x",
            "unlocked_at_rank": str(item.get("unlock_rank", 1)),
        })
    # The vanilla skills keep their own levels and effects, so only the nodes are his.
    for skill, learned in HIDDEN_SKILLS:
        add_node(rows, f"{PREFIX}_hidden_node_{skill}", skill, HIDDEN_ROW, 0, hidden=True, learned=learned)


def planned_skill_key(skill_id: str) -> str:
    """The skill key of a planned skill.

    Args:
        skill_id (str): Its id in the registry's `skills`.

    Returns:
        str: The key.
    """
    return f"{PREFIX}_skill_{skill_id}"


def planned_skill_rows(registry: Dict, rows: Dict[str, List[Dict[str, str]]], texts: List[Tuple[str, str]]) -> None:
    """Adds every planned skill marked `build`: the skill, its node in his tree (or on `HIDDEN_ROW`, unseen, when `hidden`), a level row per level
    with that level's effects, a link from each skill it needs (which must be built too), a lock from each built skill it is exclusive with, and a
    lock from each built skill it is `locked_by`.

    A skill that needs all of its skills gets `REQUIRED` links, which the game checks one by one (`required_num_parents` 0). One that needs only
    some gets `SUBSET_REQUIRED` links and `required_num_parents` set to how many.

    Args:
        registry (Dict): The registry.
        rows (Dict[str, List[Dict[str, str]]]): Rows by table, added to.
        texts (List[Tuple[str, str]]): Loc rows, added to.

    Raises:
        SystemExit: When a built skill needs, or is locked by, a skill that is not built.
    """
    skills = registry.get("skills", {})
    built = {skill_id for skill_id, skill in skills.items() if skill.get("build")}
    for skill_id in sorted(built):
        skill = skills[skill_id]
        key, node = planned_skill_key(skill_id), f"{PREFIX}_skill_node_{skill_id}"
        rows["character_skills_tables"].append({
            "key": key, "image_path": skill.get("icon", ""), "unlocked_at_rank": str(skill.get("rank", 1)), "is_background_skill": "false",
            "is_female_only_background_skill": "false", "is_male_only_background_skill": "false", "background_weighting": "0.0000", "influence_cost": "0",
        })
        texts.append((f"character_skills_localised_name_{key}", skill.get("name", skill_id)))
        texts.append((f"character_skills_localised_description_{key}", skill.get("description", "")))
        requires = [r for r in skill.get("requires", []) if r in skills]
        missing = [r for r in requires if r not in built]
        if missing:
            raise SystemExit(f"skill {skill_id} needs {', '.join(missing)}, which is not built")
        needs = skill.get("needs")
        some = isinstance(needs, int) and 0 < needs < len(requires)
        hidden = bool(skill.get("hidden"))
        add_node(rows, node, key, skill.get("row", 2), skill.get("tier", 0), hidden, hidden and bool(skill.get("learned")), needs if some else 0)
        for other in skill.get("exclusive", []):
            if other in built:
                rows["character_skill_nodes_skill_locks_tables"].append({"character_skill": key, "character_skill_node": f"{PREFIX}_skill_node_{other}", "level": "1"})
        for other in skill.get("locked_by", []):
            if other not in built:
                raise SystemExit(f"skill {skill_id} is locked by {other}, which is not built")
            rows["character_skill_nodes_skill_locks_tables"].append({"character_skill": planned_skill_key(other), "character_skill_node": node, "level": "1"})
        for parent in requires:
            rows["character_skill_node_links_tables"].append({
                "child_key": node, "parent_key": f"{PREFIX}_skill_node_{parent}", "initial_descent_tiers": "0", "parent_link_position": "1",
                "child_link_position": "1", "parent_link_position_offset": "0.0000", "child_link_position_offset": "0.0000",
                "link_type": "SUBSET_REQUIRED" if some else "REQUIRED",
            })
        for level, level_effects in enumerate(skill.get("levels") or [[]], start=1):
            rows["character_skill_level_details_tables"].append({
                "campaign_key": "", "faction_key": "", "level": str(level), "skill_key": key, "subculture_key": "", "image_path": "x",
                "unlocked_at_rank": str(skill.get("rank", 1)),
            })
            rows["character_skill_level_to_effects_junctions_tables"] += [{"character_skill_key": key, "effect_key": e["effect"], "level": str(level),
                                                                           "effect_scope": e["scope"], "value": effect_value(e)} for e in level_effects]


def bundle_rows(key: str, entry: Dict, rows: Dict[str, List[Dict[str, str]]], texts: List[Tuple[str, str]]) -> None:
    """Adds one effect bundle for him and its effects.

    Args:
        key (str): The bundle key.
        entry (Dict): `name`, `description`, `icon` (a file in `ui/campaign ui/effect_bundles`) and `effects`.
        rows (Dict[str, List[Dict[str, str]]]): Rows by table, added to.
        texts (List[Tuple[str, str]]): Loc rows, added to.
    """
    rows["effect_bundles_tables"].append({"key": key, "localised_description": "", "localised_title": "", "bundle_target": "character", "priority": "1",
                                          "ui_icon": entry.get("icon", "public_order.png"), "is_global_effect": "true", "show_in_3d_space": "false",
                                          "owner_only": "true"})
    rows["effect_bundles_to_effects_junctions_tables"] += [{"effect_bundle_key": key, "effect_key": e["effect"], "effect_scope": e["scope"],
                                                            "value": effect_value(e), "advancement_stage": BUNDLE_STAGE}
                                                           for e in entry.get("effects", [])]
    texts.append((f"effect_bundles_localised_title_{key}", entry["name"]))
    texts.append((f"effect_bundles_localised_description_{key}", entry.get("description", "")))


def weapon_art_rows(registry: Dict, rows: Dict[str, List[Dict[str, str]]], texts: List[Tuple[str, str]]) -> Dict[str, List[Tuple[str, str, str]]]:
    """Adds every weapon's arts, one effect bundle per art slot.

    Args:
        registry (Dict): The registry.
        rows (Dict[str, List[Dict[str, str]]]): Rows by table, added to.
        texts (List[Tuple[str, str]]): Loc rows, added to.

    Returns:
        Dict[str, List[Tuple[str, str, str]]]: Weapon -> (slot skill key, bundle key, art name) for each built art slot, for the loadout script.

    Raises:
        SystemExit: When a weapon leaves a built slot undefined.
    """
    slots = {skill["slot"]: planned_skill_key(skill_id) for skill_id, skill in registry.get("skills", {}).items() if skill.get("build") and skill.get("slot")}
    arts: Dict[str, List[Tuple[str, str, str]]] = {}
    for weapon_key, weapon in registry["weapons"].items():
        missing = sorted(set(slots) - set(weapon.get("arts", {})))
        if missing:
            raise SystemExit(f"weapon {weapon_key} has no art for slot {', '.join(missing)}")
        for slot, art in weapon.get("arts", {}).items():
            bundle = art_bundle_key(weapon_key, slot)
            bundle_rows(bundle, art, rows, texts)
            if slot in slots:
                arts.setdefault(weapon_key, []).append((slots[slot], bundle, art["name"]))
    return arts


def story_bundle_rows(registry: Dict, rows: Dict[str, List[Dict[str, str]]], texts: List[Tuple[str, str]]) -> None:
    """Adds the registry's `bundles`, the effect bundles the story script puts on him.

    Args:
        registry (Dict): The registry.
        rows (Dict[str, List[Dict[str, str]]]): Rows by table, added to.
        texts (List[Tuple[str, str]]): Loc rows, added to.
    """
    for bundle_id, entry in registry.get("bundles", {}).items():
        bundle_rows(bundle_key(bundle_id), entry, rows, texts)


def action_rows(registry: Dict, data: Dict, rows: Dict[str, List[Dict[str, str]]], vanilla_texts: List[Tuple[str, str]]) -> None:
    """Adds his copy of each of the registry's `actions`: the vanilla action row for his agent type, a new enable effect, and the vanilla action's
    other bonus values (cost, success chance). A skill level then gives the enable effect.

    Args:
        registry (Dict): The registry.
        data (Dict): The kept vanilla rows (the actions and their bonus values).
        rows (Dict[str, List[Dict[str, str]]]): Rows by table, added to.
        vanilla_texts (List[Tuple[str, str]]): Loc rows copied from vanilla text, added to.

    Raises:
        SystemExit: When an action is not in the kept rows (run `--refresh`).
    """
    kept = data["actions"]
    for action in registry.get("actions", []):
        if action not in kept["rows"]:
            raise SystemExit(f"hero action {action} is not kept, run with --refresh")
        source, key, effect = kept["rows"][action], action_key(action), action_effect_key(action)
        row = dict(source, unique_id=key, agent=AGENT_TYPE)
        row.update({column: AGENT_ATTRIBUTE for column in ("attribute", "target_attribute") if row[column] == source["attribute"]})
        rows["agent_actions_tables"].append(row)
        rows["effects_tables"].append({"effect": effect, "icon": "", "priority": "0", "icon_negative": "", "category": "campaign", "is_positive_value_good": "true"})
        rows["effect_bonus_value_agent_action_record_junctions_tables"].append({"bonus_value_id": "active", "effect": effect, "agent_action_record": key})
        rows["effect_bonus_value_agent_action_record_junctions_tables"] += [dict(r, agent_action_record=key) for r in kept["links"]
                                                                             if r["agent_action_record"] == action and r["bonus_value_id"] != "active"]
        # The name and description are keyed by the action, so the copy carries the vanilla text. It uses `%n%` value markers.
        name = source["localised_action_name"]
        vanilla_texts.append((f"agent_actions_localised_action_name_{key}", name))
        vanilla_texts.append((f"agent_actions_localised_action_description_{key}", source["localised_action_description"].replace("\\n", "\\\\n")))
        vanilla_texts.append((f"effects_description_{effect}", f"Hero action: {name}"))


def item_rows(registry: Dict, data: Dict, rows: Dict[str, List[Dict[str, str]]], texts: List[Tuple[str, str]]) -> None:
    """Adds his quest items, the registry's `items`: one ancillary each, only for him, with its effects.

    Args:
        registry (Dict): The registry.
        data (Dict): The kept vanilla rows (the ancillary types).
        rows (Dict[str, List[Dict[str, str]]]): Rows by table, added to.
        texts (List[Tuple[str, str]]): Loc rows, added to.

    Raises:
        SystemExit: When an item's type is unknown.
    """
    for item_id, item in registry.get("items", {}).items():
        key = item_key(item_id)
        if item.get("type") not in data.get("ancillary_types", []):
            raise SystemExit(f"item {item_id}: unknown ancillary type {item.get('type')}")
        ancillary_rows(rows, key, item["type"], item.get("category", "talisman"), legendary_item="true", uniqueness_score="100")
        rows["ancillary_to_effects_tables"] += [{"ancillary": key, "effect": e["effect"], "effect_scope": e["scope"], "value": effect_value(e)}
                                                for e in item.get("effects", [])]
        texts.append((f"ancillaries_onscreen_name_{key}", item["name"]))
        texts.append((f"ancillaries_colour_text_{key}", item.get("description", "")))


def lore_rows(registry: Dict, data: Dict, rows: Dict[str, List[Dict[str, str]]], texts: List[Tuple[str, str]]) -> None:
    """Adds one 3-level skill per built lore of the registry's `lores`. Each level lists its full effects, since levels do not stack: level 1 the
    passive and the cheapest spells, level 2 every spell, level 3 every spell and its overcast.

    Args:
        registry (Dict): The registry.
        data (Dict): The kept vanilla rows (the lores).
        rows (Dict[str, List[Dict[str, str]]]): Rows by table, added to.
        texts (List[Tuple[str, str]]): Loc rows, added to.

    Raises:
        SystemExit: When a lore is not in the kept rows (run `--refresh`).
    """
    me = "character_to_character_own"
    for lore, entry in registry.get("lores", {}).items():
        if not entry.get("build"):
            continue
        if lore not in data.get("lores", {}):
            raise SystemExit(f"lore {lore} is not kept, run with --refresh")
        kept, key = data["lores"][lore], lore_skill_key(lore)
        passives, spells = kept["passives"], kept["spells"]
        overcasts = [s["overcast"] for s in spells if s["overcast"]]
        levels = [passives + [s["enable"] for s in spells[:LORE_FIRST_SPELLS]], passives + [s["enable"] for s in spells],
                  passives + [s["enable"] for s in spells] + overcasts]
        rank = str(entry.get("rank", 1))
        rows["character_skills_tables"].append({
            "key": key, "image_path": entry.get("icon", ""), "unlocked_at_rank": rank, "is_background_skill": "false", "is_female_only_background_skill": "false",
            "is_male_only_background_skill": "false", "background_weighting": "0.0000", "influence_cost": "0",
        })
        add_node(rows, f"{PREFIX}_lore_node_{lore.split('_lore_', 1)[-1]}", key, entry["row"], entry["tier"])
        for level, effects in enumerate(levels, start=1):
            rows["character_skill_level_details_tables"].append({"campaign_key": "", "faction_key": "", "level": str(level), "skill_key": key,
                                                                 "subculture_key": "", "image_path": "x", "unlocked_at_rank": rank})
            rows["character_skill_level_to_effects_junctions_tables"] += [{"character_skill_key": key, "effect_key": e, "level": str(level),
                                                                           "effect_scope": me, "value": "1.0000"} for e in effects]
        first = min(LORE_FIRST_SPELLS, len(spells))
        texts.append((f"character_skills_localised_name_{key}", entry["name"]))
        texts.append((f"character_skills_localised_description_{key}", entry.get("description", "He learned this lore in a world that no longer exists.")
                      + f"\\\\n\\\\nLevel 1: the lore's passive and {first} of its {len(spells)} spells. Level 2: every spell. Level 3: every spell can be overcast."))


def category_rows(rows: Dict[str, List[Dict[str, str]]]) -> None:
    """Adds one skill category per tree row, for his subtype only, so each row's cards take its colour from `ROW_COLOURS`.

    Args:
        rows (Dict[str, List[Dict[str, str]]]): Rows by table, added to.
    """
    rows["character_skill_categories_tables"] += [{"key": f"{PREFIX}_row_{row}", "max_indent": str(row), "min_indent": str(row), "order": str(row),
                                                   "agent_subtype_override": SUBTYPE, "col_hex": colour} for row, colour in enumerate(ROW_COLOURS)]


def zone_rows(registry: Dict, texts: List[Tuple[str, str]]) -> List[Dict]:
    """Checks the registry's `zones` and adds their texts.

    Args:
        registry (Dict): The registry.
        texts (List[Tuple[str, str]]): Loc rows, added to.

    Returns:
        List[Dict]: Per zone, its `title` and `description` loc keys with their English fallbacks, its `top` and `bottom` rows and its `cards`
        (skill keys in reading order), for the zones script.

    Raises:
        SystemExit: When a zone names a skill that is not built and shown, or one outside its two rows.
    """
    skills, zones = registry.get("skills", {}), []
    for i, zone in enumerate(registry.get("zones", []), start=1):
        top, bottom = zone["rows"]
        for skill_id in zone["skills"]:
            skill = skills.get(skill_id, {})
            if not skill.get("build") or skill.get("hidden") or skill.get("row") not in (top, bottom):
                raise SystemExit(f"zone {zone['title']}: skill {skill_id} is not built, is hidden or is not on row {top} or {bottom}")
        title, description = f"{PREFIX}_ui_zone_{i}_title", f"{PREFIX}_ui_zone_{i}_description"
        texts += [(title, zone["title"]), (description, zone.get("description", ""))]
        zones.append({"title": title, "title_fallback": zone["title"], "description": description, "description_fallback": zone.get("description", ""),
                      "top": top, "bottom": bottom, "cards": [planned_skill_key(s) for s in zone["skills"]]})
    return zones


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
    registry = load_registry()
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
        form_props = weapon.get("forms", {}).get(mount_key, {}).get("props", {})
        variant = foot_variant(weapon_key) + ("_" + mount_key if "variant_props" in mount or form_props else "")
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
        abilities = [a for a in dict.fromkeys(["wh3_main_unit_passive_single_entity"] + weapon.get("abilities", [])) if a not in weapon.get("abilities_removed", [])]
        rows["land_units_to_unit_abilites_junctions_tables"] += [{"ability": a, "land_unit": key, "culture": "*"} for a in abilities]
        for table, column in UNIT_ROW_TABLES.items():
            rows[table] += [dict(r, **{column: key}) for r in templates[table] if r[column] == template]
        rows["units_custom_battle_permissions_tables"].append(dict(template_perm, unit=key, general_uniform=uniform, general_portrait=portrait_png,
                                                                   set_piece_character=""))
        if mount_key != DEFAULT_MOUNT:
            rows["units_custom_battle_mounts_tables"].append({"base_unit": unit_key(weapon_key, DEFAULT_MOUNT), "mounted_unit": key, "icon_name": mount["icon"]})
        rows["unit_variants_tables"].append({"faction": "", "unit": key, "name": SUBTYPE, "variant": variant, "unit_card": UNIT_CARD})
        texts.append((f"land_units_onscreen_name_{key}", "The Advisor" if key == unit_key(DEFAULT_WEAPON, DEFAULT_MOUNT)
                      else f"The Advisor ({weapon['name']}, {mount['name']})"))

        ancillary_rows(rows, ancillary, mount["ancillary_type"], "mount", provided_bodyguard_unit=key)
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
        look = {"weapon": weapon_key, "hood": weapon.get("hood", registry["model"]["hood"]), "pieces": weapon.get("pieces", {}),
                "piece_shapes": weapon.get("piece_shapes", {})}
        variants[variant] = (weapon.get("body", registry["model"]["body"]), dict(weapon["props"], **mount.get("variant_props", {}), **form_props), look)

    for variant in variants:
        rows["variants_tables"].append({"variant_name": variant, "variant_filename": variant, "mount_scale": "1.0000", "scale": "1.1500", "scale_variation": "0.0000"})
    for set_name in [*anims.SETS, *anims.DERIVED_SETS]:
        rows["battle_animations_table_tables"].append({"key": set_name, "skeleton": anims.TARGET_SKELETON})
    # Every culture pack loads every animation set he or his mounts play, unless vanilla already does.
    battle_sets = {r["man_animation"] for r in rows["land_units_tables"]} | set(data["mount_animations"].values())
    vanilla_pairs = set(data["culture_animations"])
    rows["culture_to_battle_animation_tables_tables"] += [{"battle_animations_table": s, "culture_pack": c} for s in sorted(battle_sets)
                                                          for c in data["culture_packs"] if f"{s}|{c}" not in vanilla_pairs]
    # Text copied from vanilla keeps its `%n%` value markers, so it skips `check_loc`. No script reads it.
    vanilla_texts: List[Tuple[str, str]] = []
    action_rows(registry, data, rows, vanilla_texts)
    skill_rows(registry, rows, texts)
    planned_skill_rows(registry, rows, texts)
    arts = weapon_art_rows(registry, rows, texts)
    story_bundle_rows(registry, rows, texts)
    item_rows(registry, data, rows, texts)
    lore_rows(registry, data, rows, texts)
    category_rows(rows)
    zones = zone_rows(registry, texts)
    art_rows(registry, data, rows)
    missile_rows(registry, data, rows)
    melee_rows(registry, data, rows)
    check_duplicates(rows)
    check_node_slots(rows["character_skill_nodes_tables"])
    check_effects(rows, data)
    check_loc(texts)
    texts += vanilla_texts

    for table, table_rows in rows.items():
        write(table, table_rows, specs[table])
    write_variants(registry["model"], variants)
    # Art set entries show their weapon's foot variant. Campaign variant entries show their own.
    portrait_ids = [(weapon_art_set(w), foot_variant(w)) for w in registry["weapons"]] + [(foot_variant(w), foot_variant(w)) for w in registry["weapons"]]
    write_portraits(data["portraits"], registry["portrait"], portrait_ids)
    write_portrait_images(registry["portrait"])
    write_script(registry, combos, arts, [n["character_skill_key"] for n in rows["character_skill_nodes_tables"] if n["points_on_creation"] == "1"], zones)
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
    for table, column in (("land_units_tables", "key"), ("character_skills_tables", "key"), ("ancillaries_tables", "key"), ("agent_actions_tables", "unique_id"),
                          ("effect_bundles_tables", "key"),
                          ("agent_uniforms_tables", "uniform_name"), ("main_units_tables", "unique_index"), ("missile_weapons_tables", "key"),
                          ("projectiles_tables", "key")):
        keys = [r[column] for r in rows[table]]
        if len(keys) != len(set(keys)):
            raise SystemExit(f"duplicate keys in {table}: {sorted(k for k in set(keys) if keys.count(k) > 1)}")


def check_node_slots(nodes: List[Dict[str, str]]) -> None:
    """Stops the build on two of his skill nodes in one slot. The game keeps one and drops the other, and `cm:add_skill` on the dropped one's
    skill then does nothing.

    Args:
        nodes (List[Dict[str, str]]): His skill node rows.

    Raises:
        SystemExit: When an indent and tier pair repeats.
    """
    slots: Dict[Tuple[str, str], str] = {}
    for node in nodes:
        slot = (node["indent"], node["tier"])
        if slot in slots:
            raise SystemExit(f"skill nodes {slots[slot]} and {node['key']} share indent {slot[0]} tier {slot[1]}")
        slots[slot] = node["key"]


def check_effects(rows: Dict[str, List[Dict[str, str]]], data: Dict) -> None:
    """Stops the build on an effect or scope the game lacks, in any skill level, effect bundle or item. His own effects (the hero action enables)
    count as known.

    Args:
        rows (Dict[str, List[Dict[str, str]]]): Rows by table.
        data (Dict): The kept vanilla rows (the effect and scope keys).

    Raises:
        SystemExit: On an unknown effect or scope.
    """
    known, scopes = set(data["effects"]) | {r["effect"] for r in rows["effects_tables"]}, set(data["scopes"])
    for table, owner, effect, scope in (("character_skill_level_to_effects_junctions_tables", "character_skill_key", "effect_key", "effect_scope"),
                                        ("effect_bundles_to_effects_junctions_tables", "effect_bundle_key", "effect_key", "effect_scope"),
                                        ("ancillary_to_effects_tables", "ancillary", "effect", "effect_scope")):
        for row in rows[table]:
            if row[effect] not in known or row[scope] not in scopes:
                raise SystemExit(f"{row[owner]}: unknown effect {row[effect]} or scope {row[scope]}")


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
    """Writes one table file of the mod. A table with no rows (a weapon stat nothing sets yet) is left out, and its old file removed. Other files of
    the table (such as test rows) are kept.

    Args:
        table (str): The table name.
        rows (List[Dict[str, str]]): The rows.
        spec (Dict): The table's kept header and version.
    """
    folder = os.path.join(MOD, "db", table)
    if not rows:
        if os.path.exists(os.path.join(folder, f"{FILE}.tsv")):
            os.remove(os.path.join(folder, f"{FILE}.tsv"))
        if os.path.isdir(folder) and not os.listdir(folder):
            os.rmdir(folder)
        return
    os.makedirs(folder, exist_ok=True)
    header = spec["header"]
    lines = ["\t".join(header), "\t".join([f"#{table};{spec['version']};db/{table}/{FILE}"] + [""] * (len(header) - 1))]
    lines += ["\t".join(row.get(column, "") for column in header) for row in rows]
    with open(os.path.join(folder, f"{FILE}.tsv"), "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")


def prop_copy_path(path: str) -> str:
    """Game path of the copy of a weapon model that `model.prop_offsets`, `prop_turns` or `prop_sizes` changes.

    Args:
        path (str): The vanilla weapon model.

    Returns:
        str: The copy's path.
    """
    return f"{PROP_FOLDER}/{os.path.basename(path).lower()}"


def piece_copy_path(weapon_key: str, slot: str, path: str) -> str:
    """Game path of the copy of a prop piece that the weapon's `piece_shapes` moves, turns or sizes. Each piece has its own.

    Args:
        weapon_key (str): The weapon whose look holds the piece.
        slot (str): The piece's slot, e.g. `piece_2`.
        path (str): The vanilla model.

    Returns:
        str: The copy's path.
    """
    return f"{PROP_FOLDER}/{weapon_key}_{slot}_{os.path.basename(path).lower()}"


def unpainted_copy_path(path: str) -> str:
    """Game path of the copy of an outfit's `.wsmodel` that `model.unpainted` writes, without its colour masks.

    Args:
        path (str): The outfit's `.wsmodel`.

    Returns:
        str: The copy's path.
    """
    return f"{UNPAINTED_FOLDER}/{os.path.basename(path).lower()}"


def write_variants(model: Dict, variants: Dict[str, Tuple[str, Dict, Dict]]) -> None:
    """Writes one variant mesh definition per weapon (and per weapon on a prop mount such as the disc): his model pieces, the dismemberment stumps
    and the props.

    Args:
        model (Dict): The registry's `model` (the bodies, the heads, and stumps).
        variants (Dict[str, Tuple[str, Dict, Dict]]): Variant name -> (key of its body in `model.bodies`, slot -> (attach point, model, metadata),
            and its look: `weapon` (its key), `hood`, `pieces` (slot -> [model, metadata...] or [bone, model, metadata...]) and `piece_shapes`).
    """
    folder = os.path.join(MOD, "variantmeshes", "variantmeshdefinitions")
    os.makedirs(folder, exist_ok=True)
    slots = {"weapon_1": "be_prop_0", "weapon_2": "be_prop_1", "shield": "be_prop_2", "weapon_3": "be_prop_3", "weapon_4": "be_prop_4", "weapon_5": "be_prop_5"}
    head = model["heads"][model["head"]]
    for name, (body_key, props, look) in variants.items():
        # The head goes right after the body's first slot, like in vanilla variants. A head with no hoodless model keeps its own when the hood is off.
        head_piece = ("head", head["hooded"] if look["hood"] else head.get("hoodless", head["hooded"]))
        body = list(model["bodies"][body_key].items())
        # An unpainted outfit wears the copies of its `.wsmodel` pieces.
        if model.get("unpainted", {}).get(body_key):
            body = [(slot, [unpainted_copy_path(mesh) if mesh.lower().endswith(".wsmodel") else mesh, *meta]) for slot, (mesh, *meta) in body]
        pieces = dict([body[0], head_piece] + body[1:] + list(look["pieces"].items()))
        lines = ["<VARIANT_MESH>"]
        for slot, piece in pieces.items():
            # A piece held on a bone starts with the bone, one that bends with the body with its model.
            bone, (mesh, *meta) = (None, piece) if piece[0].lower().endswith((".wsmodel", ".rigid_model_v2")) else (piece[0], piece[1:])
            if bone and slot in look.get("piece_shapes", {}):
                mesh = piece_copy_path(look["weapon"], slot, mesh)
            tail = "".join(f"<META_DATA>{m}</META_DATA>" for m in meta if m)
            point = f' attach_point="{bone}"' if bone else ""
            lines += [f'\t<SLOT name="{slot}"{point} >', f'\t\t<VARIANT_MESH model="{mesh}" >{tail}</VARIANT_MESH>', "\t</SLOT>"]
        for slot, point in slots.items():
            if slot not in props:
                lines.append(f'\t<SLOT name="{slot}" attach_point="{point}" />')
                continue
            _, mesh, meta = props[slot]
            if any(mesh in model.get(name, {}) for name in PROP_CHANGES):
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


def write_script(registry: Dict, combos: List[Tuple[str, str, str]], arts: Dict[str, List[Tuple[str, str, str]]], learned: List[str], zones: List[Dict]) -> None:
    """Writes the Lua data table the campaign scripts read: his subtype, the weapons and mounts with their unlock skills, names and picker icons,
    the ancillary of every valid pair both ways, the skills he is made with, each weapon's arts and the skill tree's zones.

    Args:
        registry (Dict): The registry.
        combos (List[Tuple[str, str, str]]): (weapon, mount, ancillary) per valid pair.
        arts (Dict[str, List[Tuple[str, str, str]]]): Weapon -> (slot skill, art bundle, art name) per built art slot.
        learned (List[str]): The skills he is made with.
        zones (List[Dict]): The zones, from `zone_rows`.
    """
    quote = lambda text: text.replace("\\", "\\\\").replace('"', '\\"')
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
    lines += ["\t},", "\t--- Forename loc key of his name.", f'\tname = "names_name_{name_id()}",']
    lines += ["\t--- Hidden skills he is made with. An Advisor from before they were added gets them from the spawn script.", "\tlearned_skills = {"]
    lines += [f'\t\t"{skill}",' for skill in learned]
    lines += ["\t},", "\t--- Weapon -> its arts: the art slot skill he must own, the effect bundle he wears for it while holding that weapon, and the art's",
              "\t--- English name (its loc key is the bundle's title).", "\tarts = {"]
    for weapon, slots in arts.items():
        lines += [f'\t\t["{weapon}"] = {{'] + [f'\t\t\t{{ skill = "{s}", bundle = "{b}", name = "{n.replace(chr(34), chr(92) + chr(34))}" }},' for s, b, n in slots]
        lines += ["\t\t},"]
    lines += ["\t},", "\t--- Skill tree zones, in order: title and description loc keys with English fallbacks, the top and bottom rows they span, and their",
              "\t--- cards (skill keys) in reading order.", "\tzones = {"]
    for zone in zones:
        lines += [f'\t\t{{ title = "{zone["title"]}", title_fallback = "{quote(zone["title_fallback"])}", description = "{zone["description"]}",',
                  f'\t\t\tdescription_fallback = "{quote(zone["description_fallback"])}", top = {zone["top"]}, bottom = {zone["bottom"]},',
                  "\t\t\tcards = { " + ", ".join(f'"{c}"' for c in zone["cards"]) + " } },"]
    lines += ["\t},", "}"]
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
