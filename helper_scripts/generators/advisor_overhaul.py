"""Builds the Advisor Overhaul (`!!advisor_overhaul`): a standalone hero, the Advisor, with his own agent subtype, model, weapon and mount units, the
skills that unlock them, and the data the campaign scripts read.

How a pair reaches the battle map:
- A weapon skill and a mount skill unlock that weapon or mount. The default weapon and mount need no skill. The player picks the pair with the
  Change Loadout button in the Advisor's character panel, and `script/campaign/mod/advisor_overhaul.lua` equips the pair's hidden mount ancillary.
- That ancillary's `provided_bodyguard_unit` is the pair's main unit, and `campaign_character_uniform_ancillary_junctions` swaps his uniform to the
  pair's, whose battle variant carries the weapon props (and the disc).
- A weapon with a `missile` gets its own missile weapon and projectile, copied from a vanilla template with the registry's values.
- A missile's `upgrade` is a second missile weapon with its own projectile, and optionally its own explosion and look. Every unit of that weapon swaps to it while he has the
  upgrade's `effect`, the way vanilla upgrades a hero's projectile.

How a weapon's stats are set (all optional, written by the modding workbench's Edit tab):
- `melee`: its own melee weapon, a copy of the vanilla `template` row with the given values (`damage`, `ap_damage`, `bonus_v_large`, ...).
- `stats`: its base land unit values on foot (`STAT_COLUMNS`, plus `armour` as an armour value, written as its own armour type). Mounted pairs add
  the vanilla mounted-minus-foot difference to them, as for the default stats.
- `forms`: mount -> values that replace the computed ones for that one pair, and `props`: prop slots whose model that pair uses instead (its own
  variant then).
- `entity`: its own foot battle entity, a copy of his vanilla foot entity with the given values (`run_speed`, `charge_speed`, ...). Mounted pairs keep
  their mount's rider entity.
- `attributes` adds unit attributes to every pair of the weapon, and `attributes_removed` takes them away. `abilities` and `abilities_removed` do
  the same for unit abilities.
- `apex_form`: a copy of his foot unit given in place of it once he owns the skill of its art `slot`, with `entity` and `melee` values on top of the
  weapon's own and its own `stats`. With a `dragon`, it gets its own dragon form that turns back into it.
  A unit shows only one personality, so several different heroes in one unit are not possible (tested 2026-10-18).

How a weapon looks on every one of its mounts (all optional, written by the workbench's Look tab): `body` picks his outfit from `model.bodies`,
`hood` false takes his hood off (when his head has a hoodless model), and `pieces` adds models such as a hat: slot -> [model, metadata...], or
[bone, model, metadata...] for a prop held on that bone (a book on his hip). `piece_shapes` moves, turns and sizes a prop piece on its own
(slot -> `offset` [x, y, z] metres, `turn` [x, y, z] degrees, `size`), so two pieces of the same model can point different ways. An
outfit in `model.unpainted` (key -> true) is worn without its faction colours or heraldry, as copies `generators.advisor_overhaul_model` writes.

New weapons made with the workbench's New form dialog are marked `workbench`. Their `sets` hold only `humanoid01` sets, which build as they are.
A set picked from another skeleton waits in `retarget` (mount -> `set`, `skeleton`, and `handoff` and `note` once it is handed to Claude) until it
is retargeted into a set of his own and moved to `sets`. A weapon with no sets yet is left out of the build.

His planned skills are the registry's `skills` (written by the workbench's Skills tab): id -> `name`, `description`, `icon` (a file in
`ui/campaign ui/skills`, or in the ability or effect icons, which is copied in), `row` and `tier` in the tree, `rank` it unlocks at, `levels` (each a list of `effect`, `scope`, `value`), `requires` (ids
of skills it needs: all of them, or any `needs` of them), `exclusive` (ids of skills it locks, both ways), `locked_by` (ids of skills that lock it
one way, such as a pact choice), `hidden` (no node shown, for skills a script gives him, with `learned` giving it to him when he is made), `slot`
(an art slot, whose effect is the held weapon's art for that slot), `grant_rank` (the rank at which the game gives it to him by itself) and
`build`. Only skills with `build` (In game in the workbench) are written.
Drafts stay in the workbench. A weapon or mount with `unlock` "script" gets a hidden skill too: only a script unlocks it. With `grant_rank` the loadout script gives
it by itself once he reaches that rank (every mount and weapon). Without an `unlock_rank` it can never be bought first.

The rest of his kit, also in the registry:
- `weapons.<w>.arts`: slot -> `name`, `description`, `effects` (each `effect`, `scope`, `value`). Each is an effect bundle, which the loadout
  script puts on him while he holds that weapon and owns the slot's skill. Every weapon must define every slot a built skill uses.
- `bundles`: id -> `name`, `description`, `icon`, `effects`, optional `hidden` (no portrait icon). Effect bundles the script puts on him (the Polymath bonus).
- `actions`: vanilla hero action keys copied for him, a wizard. Each copy gets its own enable effect (`action_effect_key`) that a skill level
  gives, and the vanilla action's name and description.
- `action_overrides`: action key -> column -> value, swapped into his copy of that action (outcomes, description).
- `items`: id -> `name`, `description`, `type` (a vanilla ancillary type), `category`, `effects`. His quest items.
- `lore_slots`: a list of `row` and `rank`. Each slot is a row holding a copy of every lore, so he picks one lore per slot (at most one lore per slot,
  and never the same lore twice).
- `lores`: vanilla lore key -> `name`, `icon`, `tier`, `build`. One 3-level skill per lore and slot, its spells read from vanilla at
  `--refresh`: level 1 its `LORE_FIRST_SPELLS` cheapest spells, level 2 every spell, level 3 every spell and its overcast.

Each tree row's cards take that row's colour from `ROW_COLOURS`, through a skill category for his subtype only.

The Polymath (the skill with `role` "polymath") grows with every discipline of `DISCIPLINES` in which he has `POLYMATH_SKILLS` skills: the
loadout script puts the bundle `bundles.polymath_<n>` on him for n such disciplines, so the registry needs one from 0 up to every discipline. Each
bundle holds the whole bonus, so the skill itself has no effects and the Polymath box on its card shows the bundle he has now.

Every value comes from vanilla data. His stats are the Amethyst Wizard's (`FOOT_TEMPLATE`), mounted pairs start from a vanilla hero on the same
mount (the registry's `template`) plus the vanilla difference between that hero mounted and on foot. His look (icon, voice, campaign art row,
portrait camera) follows the vanilla Grey Wizard. His 2D portrait, unit card and info picture are cut from the vanilla Advisor bust (the registry's
`portrait`). The stats are placeholders until they are tuned.

A monster mount (the dragon) fights with its template's melee weapon, not his, and gets the mount's `abilities` (its breath). When the template
has a vanilla rider personality, each pair gets a copy that plays his own rider set and variant.

The weapons, mounts and model pieces are in advisor_overhaul_registry.json. The vanilla rows this reads are kept in advisor_overhaul.json. Refresh
it after a game patch. It reads the vanilla tables from db.pack and the vanilla portrait settings from ui.pack, both through the extract cache:

    python -m generators.advisor_overhaul --refresh

Build:

    python -m generators.advisor_overhaul
"""

import argparse
import io
import json
import os
import re
import sys
import zlib
from typing import Any, Dict, Iterable, List, Optional, Tuple

from PIL import Image, ImageChops, ImageDraw

from core.asset_source import AssetSource
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

# Where skill nodes look up their icon, the size of a vanilla skill icon, the black disc centred in it, and the picture on that disc. The disc
# edge keeps the skill frame's bronze ring clear, as vanilla icons do.
SKILL_ICON_FOLDER = "ui/campaign ui/skills"
SKILL_ICON_SIZE = (72, 72)
SKILL_ICON_OUTLINE = (48, 48)
SKILL_ICON_PICTURE = (44, 44)

# Pixels at or under this alpha, or this brightness, count as the border around a copied icon's picture. Battle icons have a black shadow ring.
ICON_ALPHA_FLOOR = 40
ICON_DARK_FLOOR = 16

# Folders a skill icon missing from the skills folder is copied from, in order, such as a contact effect's battle icon.
BORROWED_ICON_FOLDERS = ("ui/battle ui/ability_icons", "ui/campaign ui/effect_bundles")

# Vanilla packs holding the ui icons.
UI_PACKS = re.compile(r"^ui")

# Start of the last paragraph of each art slot skill's description, which points at Change Loadout.
ART_SLOT_NOTE = "What it does follows the weapon"

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
MOUNT_ROW = 0

# Row of every hidden skill node, one tier each in the order they are added. Two nodes in one slot drop one of them.
HIDDEN_ROW = 99

# Hidden vanilla skills his tree holds: (skill, learned when he is made). It raises his hero actions' success chance with his rank. He has no
# hidden skill that turns on hero actions, as the Amethyst Wizard has: each action is unlocked by a point in its own node (row 9).
HIDDEN_SKILLS = [("wh3_main_skill_agent_action_success_scaling", False)]

# Effect bundle values for a bundle on him. `advancement_stage` must be `start_turn_completed`, or the game crashes on load.
BUNDLE_STAGE = "start_turn_completed"

# His agent attribute, which copied hero actions of other agents use instead of their own.
AGENT_ATTRIBUTE = "authority"

# Lores of magic that are no lore a caster can learn: Kroak's own, the Kemmler prologue lore with no spells, and the Cataclysm spells.
LORE_SKIPPED = {"wh2_dlc12_lore_lord_kroak", "wh_pro03_lore_kemmler", "wh3_main_cataclysm_spells"}

# Card colour of each of his tree rows, top to bottom (a `character_skill_categories` row each, for his subtype only).
ROW_COLOURS = ["F1413D", "3DA5F1", "F1C43D", "9B3DF1", "3DF17A", "F13DC4", "F1813D", "3DF1E8", "8A8A8A", "FFFFFF"]

# The Polymath's disciplines: name -> the tree rows whose skills count for it. And how many skills of one discipline make it count.
DISCIPLINES = {"arts": [2, 1], "memory": [4], "magic": [3, 5, 6, 7], "hero_work": [8, 9]}
POLYMATH_SKILLS = 5

# Spells a lore skill's first level gives, the cheapest first, and how many levels a lore skill has.
LORE_FIRST_SPELLS = 3
LORE_LEVELS = 3
# The name each pick slot gives its copy of a lore: `First Tome: Lore of Fire`.
TOME_ORDINALS = ["First", "Second", "Third", "Fourth", "Fifth"]

# Names group of his name row. Frequency 0 keeps the name out of random name rolls.
NAMES_GROUP = "names_emp_empire"

# Land unit stats moved by the template's mounted-minus-foot difference.
DELTA_COLUMNS = ["bonus_hit_points", "charge_bonus", "melee_attack", "melee_defence"]

# Land unit columns that pick the lines he says when selected. Every form, the Iron Dragon too, keeps his foot unit's.
VOICE_COLUMNS = ["selection_vo", "selected_vo_secondary", "selected_vo_tertiary"]

# Land unit columns every pair keeps from his foot unit, so each pair stays the same hero.
IDENTITY_COLUMNS = ["accuracy", "campaign_action_points", "morale", "visibility_spotting_range_min", "visibility_spotting_range_max", "spell_mastery"] + VOICE_COLUMNS

# Main unit columns every pair keeps from his foot unit. The `vo_is_*` flags would swap his voice for a dragon's or dinosaur's.
MAIN_IDENTITY_COLUMNS = ["audio_voiceover_culture", "audio_voiceover_culture_override", "audio_voiceover_actor_group", "has_spoken_vo", "vo_is_dragon",
                         "vo_is_dinosaur", "campaign_cap", "porthole_camera"]

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
    "projectiles_tables", "projectiles_explosions_tables", "projectile_displays_tables", "unit_missile_weapon_junctions_tables", "effect_bonus_value_missile_weapon_junctions_tables",
    "melee_weapons_tables", "battle_entities_tables", "unit_armour_types_tables", "character_skill_node_links_tables",
    "character_skill_level_to_effects_junctions_tables", "character_skill_nodes_skill_locks_tables", "effects_tables", "effect_bundles_tables",
    "effect_bundles_to_effects_junctions_tables", "agent_actions_tables", "effect_bonus_value_agent_action_record_junctions_tables",
    "ancillary_to_effects_tables", "character_skill_categories_tables", "character_skills_to_level_reached_criterias_tables",
    "effect_bonus_value_special_ability_group_junctions_tables", "effect_bonus_value_ids_unit_sets_tables", "special_ability_groups_to_units_junctions_tables",
    "unit_abilities_tables", "unit_special_abilities_tables", "battle_personalities_tables", "land_units_to_battle_personalities_junctions_tables",
    "units_custom_battle_types_tables", *UNIT_ROW_TABLES,
]

# Vanilla rows a missile `upgrade` can copy: registry field, kept-data name, table, and the projectile column pointed at the copy.
UPGRADE_COPIES = [
    ("explosion", "explosions", "projectiles_explosions_tables", "explosion_type"),
    ("display", "displays", "projectile_displays_tables", "projectile_display"),
]

# First unique id of his transform abilities, above every vanilla special ability id.
TRANSFORM_UNIQUE_ID = 1493349900

# Land unit columns a weapon's `stats` and `forms` may set. `armour` is set too, as an armour value.
STAT_COLUMNS = ["melee_attack", "melee_defence", "charge_bonus", "morale", "bonus_hit_points"]

# Template tables -> the column naming the template unit.
TEMPLATE_TABLES = {"land_units_tables": "key", "main_units_tables": "land_unit", "units_custom_battle_permissions_tables": "unit",
                   "unit_attributes_to_groups_junctions_tables": "attribute_group", **UNIT_ROW_TABLES}

# Tables a Custom Battle lore copy repeats from its unit -> the columns naming the unit. Campaign-only rows stay with the unit.
LORE_COPY_TABLES = {
    "land_units_tables": ["key", "attribute_group"], "main_units_tables": ["unit", "land_unit"], "unit_attributes_groups_tables": ["group_name"],
    "unit_attributes_to_groups_junctions_tables": ["attribute_group"], "land_units_to_unit_abilites_junctions_tables": ["land_unit"],
    "unit_variants_tables": ["unit"], "ui_unit_bullet_point_unit_overrides_tables": ["unit_key"], "battle_currency_units_cost_values_tables": ["item_type"],
    "land_units_to_battle_personalities_junctions_tables": ["land_unit"],
    "units_custom_battle_permissions_tables": ["unit"],
}


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
    dragons = [w["dragon"] for w in registry["weapons"].values() if "dragon" in w]
    units = {m[k] for m in registry["mounts"].values() for k in ("template", "template_foot") if k in m} | {FOOT_TEMPLATE} | {d["template"] for d in dragons}
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
    for field, kept, table, _ in UPGRADE_COPIES:
        copied = {w["missile"]["upgrade"][field]["template"] for w in registry["weapons"].values() if field in w.get("missile", {}).get("upgrade", {})}
        data[kept] = {r["key"]: r for r in loaded[table] if r["key"] in copied}
    melees = {w["melee"]["template"] for w in registry["weapons"].values() if "melee" in w}
    melees |= {r["primary_melee_weapon"] for r in data["templates"]["land_units_tables"]}
    data["melee_weapons"] = {r["key"]: r for r in loaded["melee_weapons_tables"] if r["key"] in melees}
    # Template riders of a monster mount (the dragon): each template's junction row, and the personality rows they name.
    data["riders"] = {r["land_unit"]: r for r in loaded["land_units_to_battle_personalities_junctions_tables"] if r["land_unit"] in units}
    named = {r["battle_personality"] for r in data["riders"].values()}
    data["personalities"] = {r["key"]: r for r in loaded["battle_personalities_tables"] if r["key"] in named}
    entities = {r["man_entity"] for r in data["templates"]["land_units_tables"]}
    data["entities"] = {r["key"]: r for r in loaded["battle_entities_tables"] if r["key"] in entities}
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
    transforms = {d[form] for d in dragons for form in ("to_dragon", "to_human")}
    data["transforms"] = {t: {r["key"]: r for r in loaded[t] if r["key"] in transforms} for t in ("unit_abilities_tables", "unit_special_abilities_tables")}
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


def transform_key(human: str, form: str) -> str:
    """The ability that turns a human unit or its dragon into one of the two forms.

    Args:
        human (str): The human unit key.
        form (str): The form it turns into, `dragon` or `human`.

    Returns:
        str: The ability key.
    """
    return f"{human}_{form}_form"


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


def pair_props(registry: Dict, weapon_key: str, mount_key: str) -> Dict[str, List[str]]:
    """The prop slots of a weapon on a mount: the weapon's, the mount's `variant_props`, then the pair's form `props`. A form slot
    set to null is left empty.

    Args:
        registry (Dict): The registry.
        weapon_key (str): Weapon key.
        mount_key (str): Mount key.

    Returns:
        Dict[str, List[str]]: Slot -> [attach bone, model, meta].
    """
    weapon = registry["weapons"][weapon_key]
    props = {**weapon["props"], **registry["mounts"][mount_key].get("variant_props", {}), **weapon.get("forms", {}).get(mount_key, {}).get("props", {})}
    return {slot: prop for slot, prop in props.items() if prop}


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


def lore_short(lore: str) -> str:
    """The short name of a lore of magic, the part after `_lore_`.

    Args:
        lore (str): The vanilla lore key, such as `wh_main_lore_death`.

    Returns:
        str: The short name, such as `death`.
    """
    return lore.split("_lore_", 1)[-1]


def lore_skill_key(lore: str, slot: int = 0) -> str:
    """The skill of one lore of magic in one pick slot.

    Args:
        lore (str): The vanilla lore key, such as `wh_main_lore_death`.
        slot (int): The pick slot, 0 for the first.

    Returns:
        str: The skill key, such as `advisor_overhaul_lore_death`, with `_2` for the second slot and so on.
    """
    return f"{PREFIX}_lore_{lore_short(lore)}" + (f"_{slot + 1}" if slot else "")


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


def entity_key(weapon_key: str) -> str:
    """The key of a weapon's own foot battle entity.

    Args:
        weapon_key (str): The weapon key.

    Returns:
        str: The key.
    """
    return f"{PREFIX}_{weapon_key}_entity"


def copied_row(data: Dict, kept: str, template: str, key: str, values: Dict) -> Dict[str, str]:
    """A copy of a kept vanilla row under his own key, with the given values.

    Args:
        data (Dict): The kept vanilla rows.
        kept (str): The kept-data name, such as `melee_weapons`.
        template (str): The vanilla key to copy.
        key (str): The copy's key.
        values (Dict): Column -> value set on the copy.

    Returns:
        Dict[str, str]: The row.

    Raises:
        SystemExit: When the template is not in the kept rows (run `--refresh`).
    """
    if template not in data.get(kept, {}):
        raise SystemExit(f"{kept} template {template} is not kept, run with --refresh")
    return dict(data[kept][template], key=key, **{k: table_value(v) for k, v in values.items()})


def entity_rows(registry: Dict, data: Dict, advisor: Dict[str, str], rows: Dict[str, List[Dict[str, str]]]) -> None:
    """Adds a foot battle entity for every weapon with an `entity`: a copy of his vanilla foot entity under his own key, with the registry's values.

    Args:
        registry (Dict): The registry.
        data (Dict): The kept vanilla rows.
        advisor (Dict[str, str]): His foot land unit.
        rows (Dict[str, List[Dict[str, str]]]): Rows by table, added to.

    Raises:
        SystemExit: When his foot entity is not in the kept rows (run `--refresh`).
    """
    for weapon_key, weapon in registry["weapons"].items():
        if "entity" in weapon:
            rows["battle_entities_tables"].append(copied_row(data, "entities", advisor["man_entity"], entity_key(weapon_key), weapon["entity"]))


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
        if "melee" in weapon:
            melee = dict(weapon["melee"])
            rows["melee_weapons_tables"].append(copied_row(data, "melee_weapons", melee.pop("template"), melee_key(weapon_key), melee))


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
        row = dict(advisor, key=key, man_animation=set_name, shield=weapon["shield"], attribute_group=key,
                   primary_melee_weapon=weapon_melee(weapon_key, weapon, advisor))
        if "entity" in weapon:
            row["man_entity"] = entity_key(weapon_key)
        return with_form(with_missile(row, weapon_key, weapon), weapon, mount_key)
    mounted, foot = templates[mount["template"]], templates[mount["template_foot"]]
    row = dict(mounted)
    for column in IDENTITY_COLUMNS + ["historical_description_text", "short_description_text"]:
        row[column] = advisor[column]
    for column in DELTA_COLUMNS:
        row[column] = str(int(number(advisor[column]) + number(mounted[column]) - number(foot[column])))
    if mounted["armour"] == foot["armour"]:
        row["armour"] = advisor["armour"]
    # A monster mount fights with its own melee weapon (the dragon's bites and claws), so only a ridden horse takes his.
    if mounted["primary_melee_weapon"] == foot["primary_melee_weapon"]:
        row["primary_melee_weapon"] = weapon_melee(weapon_key, weapon, advisor)
    if mounted["mount"]:
        row["man_entity"] = RIDER_ENTITY
    row.update({"key": key, "man_animation": set_name, "shield": weapon["shield"], "attribute_group": key})
    return with_form(with_missile(row, weapon_key, weapon), weapon, mount_key)


def weapon_melee(weapon_key: str, weapon: Dict, advisor: Dict[str, str]) -> str:
    """The melee weapon he fights with when the weapon decides it: its own, or else his foot unit's.

    Args:
        weapon_key (str): The weapon key.
        weapon (Dict): The registry weapon.
        advisor (Dict[str, str]): His foot land unit.

    Returns:
        str: The melee weapon key.
    """
    return melee_key(weapon_key) if "melee" in weapon else advisor["primary_melee_weapon"]


def with_form(row: Dict[str, str], weapon: Dict, mount_key: str) -> Dict[str, str]:
    """Gives a land unit row the values its weapon's form sets for this one pair.

    Args:
        row (Dict[str, str]): The land unit row, changed in place.
        weapon (Dict): The registry weapon.
        mount_key (str): The mount key.

    Returns:
        Dict[str, str]: The row.
    """
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
    """The weapon and mount skills, where they sit in the tree: every mount but the default and then every weapon, side by side in the top row.

    The default weapon's node only shows that he always has it. A weapon with a `grant_rank` and no `unlock_rank` is only ever given, never bought.

    Args:
        registry (Dict): The registry.

    Returns:
        List[Dict]: `kind`, `key` (item key), `item` (the registry item), `row`, `tier`, `hidden`, `default`, `buy_rank` (its node's `unlocked_at_rank`),
        `free` (costs no point), `skill` and `node` keys, `name` and `icon`. A hidden one (`unlock` "script") takes no tier, since `add_node` puts it
        on `HIDDEN_ROW`.
    """
    skills = []
    tier = 0
    for row, kind, items in ((MOUNT_ROW, "mount", registry["mounts"]), (WEAPON_ROW, "weapon", registry["weapons"])):
        for key, item in items.items():
            default = not unlock_skill(kind, key)
            if default and kind == "mount":
                continue
            hidden = item.get("unlock") == "script"
            # The tree shows `unlocked_at_rank` plus one, like the auto-grant table, so a grant-only item opens one under its `grant_rank`.
            grant_only = bool(item.get("grant_rank") and not item.get("unlock_rank"))
            buy_rank = item["grant_rank"] - 1 if grant_only else item.get("unlock_rank", 1)
            skills.append({"kind": kind, "key": key, "item": item, "row": row, "tier": None if hidden else tier, "hidden": hidden, "default": default,
                           "buy_rank": buy_rank, "free": default or grant_only, "skill": choice_skill(kind, key),
                           "node": f"{PREFIX}_choose_{kind}_node_{key}", "name": item["name"], "icon": item.get("skill_icon") or os.path.basename(item["icon"])})
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
        unlock = ""
        if kind == "weapon":
            opening = "His default weapon, which he always has. Switch back" if fixed["default"] else "Unlocks this weapon for the Advisor. Switch"
            unlock = f"\\\\n\\\\n{opening} to it with the Change Loadout button in his character panel."
        texts.append((f"character_skills_localised_description_{skill}", f"{item['description']}{unlock}"))
        add_node(rows, fixed["node"], skill, fixed["row"], fixed["tier"], fixed["hidden"])
        # Without a level row the skill has 0 levels: the tree draws it as learned while `has_skill` stays false. The default weapon wants exactly that.
        if fixed["default"]:
            continue
        # A grant-only weapon opens at its grant rank, the same rank-up that gives it to him, so there is never a turn to buy it.
        rows["character_skill_level_details_tables"].append({
            "campaign_key": "", "faction_key": "", "level": "1", "skill_key": skill, "subculture_key": "", "image_path": "x",
            "unlocked_at_rank": str(fixed["buy_rank"]),
        })
        # The game's own auto-grant: the node shows "Automatically granted at rank N" and the skill is given at that level.
        if item.get("grant_rank"):
            rows["character_skills_to_level_reached_criterias_tables"].append({"character_skill": skill, "character_level": str(item["grant_rank"] - 1), "upgrade_to_skill_level": "1"})
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
    some gets `SUBSET_REQUIRED` links and `required_num_parents` set to how many. The game counts skill points in those skills, so `needs` may exceed their number.

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
        some = isinstance(needs, int) and needs > 0
        hidden = bool(skill.get("hidden"))
        add_node(rows, node, key, skill.get("row", 1), skill.get("tier", 0), hidden, hidden and bool(skill.get("learned")), needs if some else 0)
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
        # The game's own auto-grant, as for mounts. `grant_rank` is the rank the player sees, so the table gets one less.
        if skill.get("grant_rank"):
            rows["character_skills_to_level_reached_criterias_tables"].append({"character_skill": key, "character_level": str(skill["grant_rank"] - 1), "upgrade_to_skill_level": "1"})
        # `level_ranks` holds the rank of each later level. A level past its end opens at the last rank given.
        level_ranks = [skill.get("rank", 1), *skill.get("level_ranks", [])]
        for level, level_effects in enumerate(skill.get("levels") or [[]], start=1):
            rows["character_skill_level_details_tables"].append({
                "campaign_key": "", "faction_key": "", "level": str(level), "skill_key": key, "subculture_key": "", "image_path": "x",
                "unlocked_at_rank": str(level_ranks[min(level, len(level_ranks)) - 1]),
            })
            rows["character_skill_level_to_effects_junctions_tables"] += [{"character_skill_key": key, "effect_key": e["effect"], "level": str(level),
                                                                           "effect_scope": e["scope"], "value": effect_value(e)} for e in level_effects]


def effect_rows(registry: Dict, rows: Dict[str, List[Dict[str, str]]], vanilla_texts: List[Tuple[str, str]]) -> None:
    """Adds his own effects, the registry's `effects`. One with `groups` changes the Winds of Magic cost of those lores' spells. One with `unit_sets`
    gives its `bonus` to every unit in those sets. Its `priority` sets its place in a skill's tooltip, which lists effects lowest priority first.

    Args:
        registry (Dict): The registry.
        rows (Dict[str, List[Dict[str, str]]]): Rows by table, added to.
        vanilla_texts (List[Tuple[str, str]]): Loc rows with `%n` value markers, added to.
    """
    for effect, entry in registry.get("effects", {}).items():
        icon = entry.get("icon", "magic_character.png")
        rows["effects_tables"].append({"effect": effect, "icon": icon, "priority": str(entry["priority"]), "icon_negative": icon, "category": "battle",
                                       "is_positive_value_good": "true" if entry.get("good") else "false"})
        rows["effect_bonus_value_special_ability_group_junctions_tables"] += [{"bonus_value_id": "cost_percentage_mod", "effect": effect,
                                                                              "special_ability_group": group} for group in entry.get("groups", [])]
        rows["effect_bonus_value_ids_unit_sets_tables"] += [{"bonus_value_id": entry["bonus"], "effect": effect, "unit_set": unit_set}
                                                            for unit_set in entry.get("unit_sets", [])]
        vanilla_texts.append((f"effects_description_{effect}", entry["text"]))


def bundle_rows(key: str, entry: Dict, rows: Dict[str, List[Dict[str, str]]], texts: List[Tuple[str, str]], hidden: bool = False) -> None:
    """Adds one effect bundle for him and its effects.

    Args:
        key (str): The bundle key.
        entry (Dict): `name`, `description`, `icon` (a file in `ui/campaign ui/effect_bundles`) and `effects`.
        rows (Dict[str, List[Dict[str, str]]]): Rows by table, added to.
        texts (List[Tuple[str, str]]): Loc rows, added to.
        hidden (bool): Leaves out the icon, so no icon shows next to his portrait. Vanilla hides its bundles the same way.
    """
    rows["effect_bundles_tables"].append({"key": key, "localised_description": "", "localised_title": "", "bundle_target": "character", "priority": "1",
                                          "ui_icon": "" if hidden else entry.get("icon", "public_order.png"), "is_global_effect": "true", "show_in_3d_space": "false",
                                          "owner_only": "true"})
    rows["effect_bundles_to_effects_junctions_tables"] += [{"effect_bundle_key": key, "effect_key": e["effect"], "effect_scope": e["scope"],
                                                            "value": effect_value(e), "advancement_stage": BUNDLE_STAGE}
                                                           for e in entry.get("effects", [])]
    texts.append((f"effect_bundles_localised_title_{key}", entry["name"]))
    texts.append((f"effect_bundles_localised_description_{key}", entry.get("description", "")))


def box_flavour(skill: Dict, skip: Optional[str] = None) -> str:
    """A skill's description for a script-made box, its loc line breaks turned into real ones.

    Args:
        skill (Dict): The registry skill.
        skip (Optional[str]): Leaves out every paragraph that starts with this, or None to keep them all.

    Returns:
        str: The description, its paragraphs split by a blank line.
    """
    return "\n\n".join(p for p in skill.get("description", "").split("\\\\n\\\\n") if not (skip and p.startswith(skip)))


def slot_skills(registry: Dict) -> Dict[str, str]:
    """The built skill of each art slot.

    Args:
        registry (Dict): The registry.

    Returns:
        Dict[str, str]: Art slot, such as `apex` -> its skill id in the registry's `skills`.
    """
    return {skill["slot"]: skill_id for skill_id, skill in registry.get("skills", {}).items() if skill.get("build") and skill.get("slot")}


def weapon_art_rows(registry: Dict, rows: Dict[str, List[Dict[str, str]]], texts: List[Tuple[str, str]]) -> Dict[str, List[Dict]]:
    """Adds every weapon's arts, one effect bundle per art slot.

    Args:
        registry (Dict): The registry.
        rows (Dict[str, List[Dict[str, str]]]): Rows by table, added to.
        texts (List[Tuple[str, str]]): Loc rows, added to.

    Returns:
        Dict[str, List[Dict]]: Weapon -> one art per built slot, for the loadout script: `skill` (slot skill key), `skill_name`, `bundle`, `name`,
        `flavour` (the slot skill's description without its loadout note), `about` (the art's description) and `requires` (the slot skills it needs,
        each `skill` and `name`).

    Raises:
        SystemExit: When a weapon leaves a built slot undefined.
    """
    skills = registry.get("skills", {})
    slots = {}
    for slot, skill_id in slot_skills(registry).items():
        skill = skills[skill_id]
        # The art tooltip replaces the vanilla one, so the note pointing at Change Loadout is left out.
        flavour = box_flavour(skill, ART_SLOT_NOTE)
        requires = [{"skill": planned_skill_key(r), "name": skills[r].get("name", r)} for r in skill.get("requires", []) if r in skills]
        slots[slot] = (planned_skill_key(skill_id), skill["name"], flavour, requires)
    arts: Dict[str, List[Dict]] = {}
    for weapon_key, weapon in registry["weapons"].items():
        missing = sorted(set(slots) - set(weapon.get("arts", {})))
        if missing:
            raise SystemExit(f"weapon {weapon_key} has no art for slot {', '.join(missing)}")
        for slot, art in weapon.get("arts", {}).items():
            bundle = art_bundle_key(weapon_key, slot)
            # The art box on the Art and Army skill cards lists the effects, so the portrait icons are hidden.
            bundle_rows(bundle, art, rows, texts, hidden=True)
            if slot in slots:
                skill, skill_name, flavour, requires = slots[slot]
                arts.setdefault(weapon_key, []).append({"skill": skill, "skill_name": skill_name, "bundle": bundle,
                                                        "name": art["name"], "flavour": flavour, "about": art.get("description", ""),
                                                        "requires": requires})
    return arts


def story_bundle_rows(registry: Dict, rows: Dict[str, List[Dict[str, str]]], texts: List[Tuple[str, str]]) -> None:
    """Adds the registry's `bundles`, the effect bundles the story script puts on him.

    Args:
        registry (Dict): The registry.
        rows (Dict[str, List[Dict[str, str]]]): Rows by table, added to.
        texts (List[Tuple[str, str]]): Loc rows, added to.
    """
    for bundle_id, entry in registry.get("bundles", {}).items():
        bundle_rows(bundle_key(bundle_id), entry, rows, texts, hidden=entry.get("hidden", False))


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
        # `action_overrides` swaps columns of the copy, such as an outcome that would kill him.
        row.update(registry.get("action_overrides", {}).get(action, {}))
        rows["agent_actions_tables"].append(row)
        rows["effects_tables"].append({"effect": effect, "icon": "", "priority": "0", "icon_negative": "", "category": "campaign", "is_positive_value_good": "true"})
        rows["effect_bonus_value_agent_action_record_junctions_tables"].append({"bonus_value_id": "active", "effect": effect, "agent_action_record": key})
        rows["effect_bonus_value_agent_action_record_junctions_tables"] += [dict(r, agent_action_record=key) for r in kept["links"]
                                                                             if r["agent_action_record"] == action and r["bonus_value_id"] != "active"]
        # The name and description are keyed by the action, so the copy carries the vanilla text. It uses `%n%` value markers.
        name = source["localised_action_name"]
        vanilla_texts.append((f"agent_actions_localised_action_name_{key}", name))
        vanilla_texts.append((f"agent_actions_localised_action_description_{key}", row["localised_action_description"].replace("\\n", "\\\\n")))
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


def lore_slots(registry: Dict) -> List[Tuple[int, int]]:
    """The lore pick slots of the registry.

    Args:
        registry (Dict): The registry.

    Returns:
        List[Tuple[int, int]]: The `(row, rank)` of each slot, in order.
    """
    return [(s["row"], s["rank"]) for s in registry.get("lore_slots", [])]


def lore_node_key(lore: str, slot: int) -> str:
    """The skill node of one lore in one pick slot.

    Args:
        lore (str): The vanilla lore key.
        slot (int): The pick slot, 0 for the first.

    Returns:
        str: The node key.
    """
    return f"{PREFIX}_lore_node_{lore_short(lore)}" + (f"_{slot + 1}" if slot else "")


def lore_rows(registry: Dict, data: Dict, rows: Dict[str, List[Dict[str, str]]], texts: List[Tuple[str, str]]) -> None:
    """Adds one 3-level skill per built lore of the registry's `lores`. Each level lists its full effects, since levels do not stack: level 1 the
    passive and cheapest spells, level 2 every spell, level 3 every spell and its overcast. Each built lore is also a page of his battle Lore panel on every unit.

    Args:
        registry (Dict): The registry.
        data (Dict): The kept vanilla rows (the lores).
        rows (Dict[str, List[Dict[str, str]]]): Rows by table, added to.
        texts (List[Tuple[str, str]]): Loc rows, added to.

    Raises:
        SystemExit: When a lore is not in the kept rows (run `--refresh`).
    """
    me = "character_to_character_own"
    built = [lore for lore, entry in registry.get("lores", {}).items() if entry.get("build")]
    # A unit linked to several lores, each on its own page, gets the Lore panel to switch between them, the way vanilla does it for Mannfred.
    rows["special_ability_groups_to_units_junctions_tables"] += [{"ability_group": lore, "unit": r["unit"], "group_page_order": str(page)}
                                                                 for page, lore in enumerate(built) for r in rows["main_units_tables"]]
    for lore, entry in registry.get("lores", {}).items():
        if not entry.get("build"):
            continue
        if lore not in data.get("lores", {}):
            raise SystemExit(f"lore {lore} is not kept, run with --refresh")
        kept = data["lores"][lore]
        spells = kept["spells"]
        overcasts = [s["overcast"] for s in spells if s["overcast"]]
        passives = kept["passives"]
        levels = [passives + [s["enable"] for s in spells[:LORE_FIRST_SPELLS]], passives + [s["enable"] for s in spells],
                  passives + [s["enable"] for s in spells] + overcasts]
        first = min(LORE_FIRST_SPELLS, len(spells))
        for slot, (slot_row, slot_rank) in enumerate(lore_slots(registry)):
            key, rank = lore_skill_key(lore, slot), str(slot_rank)
            rows["character_skills_tables"].append({
                "key": key, "image_path": entry.get("icon", ""), "unlocked_at_rank": rank, "is_background_skill": "false",
                "is_female_only_background_skill": "false", "is_male_only_background_skill": "false", "background_weighting": "0.0000", "influence_cost": "0",
            })
            add_node(rows, lore_node_key(lore, slot), key, slot_row, entry["tier"])
            for level, effects in enumerate(levels, start=1):
                rows["character_skill_level_details_tables"].append({"campaign_key": "", "faction_key": "", "level": str(level), "skill_key": key,
                                                                     "subculture_key": "", "image_path": "x", "unlocked_at_rank": rank})
                rows["character_skill_level_to_effects_junctions_tables"] += [{"character_skill_key": key, "effect_key": e, "level": str(level),
                                                                               "effect_scope": me, "value": "1.0000"} for e in effects]
            texts.append((f"character_skills_localised_name_{key}", f"{TOME_ORDINALS[slot]} Tome: {entry['name']}"))
            texts.append((f"character_skills_localised_description_{key}", entry.get("description", "He learned this lore in a world that no longer exists.")
                          + f"\\\\n\\\\nLevel 1: {'its passive and ' if passives else ''}{first} of its {len(spells)} spells. Level 2: every spell. "
                          "Level 3: every spell can be overcast."))
            rows["character_skill_nodes_skill_locks_tables"] += [
                {"character_skill": key, "character_skill_node": lore_node_key(other, other_slot), "level": "1"}
                for other in built for other_slot in range(len(lore_slots(registry))) if (other, other_slot) != (lore, slot) and (other_slot == slot or other == lore)]


def custom_battle_lore_rows(registry: Dict, rows: Dict[str, List[Dict[str, str]]], texts: List[Tuple[str, str]]) -> None:
    """Gives Custom Battle a Spell Lore pick, the way vanilla does it for the Bright Wizard: one copy of each of his units per built lore, linked to that
    lore only. His campaign units keep every lore page and leave Custom Battle. Each foot copy lists the other lores of its weapon, and its mounts are
    the copies of the same lore. The first built lore is the one picked by default.

    Args:
        registry (Dict): The registry.
        rows (Dict[str, List[Dict[str, str]]]): Rows by table, changed in place.
        texts (List[Tuple[str, str]]): Loc rows, added to.
    """
    built = [lore for lore, entry in registry.get("lores", {}).items() if entry.get("build")]
    if not built:
        return
    units = [r["unit"] for r in rows["units_custom_battle_permissions_tables"]]
    mounts = rows["units_custom_battle_mounts_tables"]
    mount_of = {unit_key(w, m): registry["mounts"][m] for w, m in pairs(registry)}
    feet = [u for u in units if u not in {m["mounted_unit"] for m in mounts}]
    names = {key: text for key, text in texts}
    unique_index = max(int(r["unique_index"]) for r in rows["main_units_tables"])
    sources: Dict[str, Dict[str, List[Dict[str, str]]]] = {table: {} for table in LORE_COPY_TABLES}
    for table, columns in LORE_COPY_TABLES.items():
        for r in rows[table]:
            sources[table].setdefault(r[columns[0]], []).append(r)
    rows["units_custom_battle_permissions_tables"], rows["units_custom_battle_mounts_tables"] = [], []

    def copy_key(unit: str, lore: str) -> str:
        return f"{unit}_{lore_short(lore)}"

    for order, lore in enumerate(built):
        for unit in units:
            key = copy_key(unit, lore)
            unique_index += 1
            for table, columns in LORE_COPY_TABLES.items():
                extra = {"unique_index": str(unique_index)} if table == "main_units_tables" else {}
                rows[table] += [dict(r, **extra, **{c: key for c in columns if r[c] == unit}) for r in sources[table].get(unit, [])]
            rows["special_ability_groups_to_units_junctions_tables"].append({"ability_group": lore, "unit": key, "group_page_order": "0"})
            texts.append((f"land_units_onscreen_name_{key}", names[f"land_units_onscreen_name_{unit}"]))
        for m in mounts:
            base, mounted = copy_key(m["base_unit"], lore), copy_key(m["mounted_unit"], lore)
            rows["units_custom_battle_mounts_tables"].append(dict(m, base_unit=base, mounted_unit=mounted))
            mount = mount_of[m["mounted_unit"]]
            # Custom Battle's mount list reads these, keyed by both units run together.
            texts.append((f"units_custom_battle_mounts_mount_name_{base}{mounted}", mount["name"]))
            texts.append((f"units_custom_battle_mounts_localised_description_{base}{mounted}", mount["description"]))
        for foot in feet:
            key = copy_key(foot, lore)
            rows["units_custom_battle_types_tables"].append({
                "alternate_unit": key, "base_unit": copy_key(foot, built[0]), "type_category": "type_spell_lore", "type_icon": "",
                "show_base_in_unit_list": "true" if order == 0 else "false", "id": str(zlib.crc32(key.encode()) & 0x7FFFFFFF), "colour": "FFFFFF",
                "sort_order": str(order * 10)})


def category_rows(rows: Dict[str, List[Dict[str, str]]]) -> None:
    """Adds one skill category per tree row, for his subtype only, so each row's cards take its colour from `ROW_COLOURS`.

    Args:
        rows (Dict[str, List[Dict[str, str]]]): Rows by table, added to.
    """
    rows["character_skill_categories_tables"] += [{"key": f"{PREFIX}_row_{row}", "max_indent": str(row), "min_indent": str(row), "order": str(row),
                                                   "agent_subtype_override": SUBTYPE, "col_hex": colour} for row, colour in enumerate(ROW_COLOURS)]


def polymath_data(registry: Dict) -> Optional[Dict]:
    """The Polymath's data for the loadout script: its skill, the skills of each discipline and its bundles.

    Args:
        registry (Dict): The registry.

    Returns:
        Optional[Dict]: `skill`, `name`, `flavour` (its description for the Polymath box), `needed`, `disciplines` (in `DISCIPLINES` order, each
        `name` and `skills`, lores included) and `bundles` (one per number of disciplines, from 0), or None when no Polymath is built.

    Raises:
        SystemExit: When a Polymath bundle is missing from the registry's `bundles`.
    """
    skills = registry.get("skills", {})
    polymaths = [k for k, s in skills.items() if s.get("build") and s.get("role") == "polymath"]
    if not polymaths:
        return None
    missing = [f"polymath_{n}" for n in range(len(DISCIPLINES) + 1) if f"polymath_{n}" not in registry.get("bundles", {})]
    if missing:
        raise SystemExit(f"the Polymath needs the bundles {', '.join(missing)}")
    disciplines = []
    for name, rows in DISCIPLINES.items():
        keys = [planned_skill_key(k) for k, s in skills.items() if s.get("build") and not s.get("hidden") and s.get("row") in rows and k not in polymaths]
        keys += [lore_skill_key(lore, slot) for lore, e in registry.get("lores", {}).items() if e.get("build")
                 for slot, (slot_row, _) in enumerate(lore_slots(registry)) if slot_row in rows]
        disciplines.append({"name": name, "skills": sorted(keys)})
    skill = skills[polymaths[0]]
    return {"skill": planned_skill_key(polymaths[0]), "name": skill["name"], "flavour": box_flavour(skill),
            "needed": POLYMATH_SKILLS, "disciplines": disciplines, "bundles": [bundle_key(f"polymath_{n}") for n in range(len(DISCIPLINES) + 1)]}


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
    the registry's projectile values. A missile's `upgrade` adds a second missile weapon, a copy of the first with its own projectile values. Its optional
    `explosion` and `display` each copy the vanilla row named by their `template`. Its `effect` swaps every unit of that weapon to it.

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
        key = missile_key(weapon_key, weapon)
        missile_weapon = copied_row(data, "missile_weapons", missile["template"], key, {"default_projectile": key})
        projectile = copied_row(data, "projectiles", data["missile_weapons"][missile["template"]]["default_projectile"], key, missile["projectile"])
        rows["missile_weapons_tables"].append(missile_weapon)
        rows["projectiles_tables"].append(projectile)
        if "upgrade" not in missile:
            continue
        upgrade = missile["upgrade"]
        upgraded = dict(projectile, key=upgrade["key"], **{k: table_value(v) for k, v in upgrade["projectile"].items()})
        for field, kept, table, column in UPGRADE_COPIES:
            if field not in upgrade:
                continue
            values = dict(upgrade[field])
            copied = values.pop("template")
            if copied not in data.get(kept, {}):
                raise SystemExit(f"{field} template {copied} is not kept, run with --refresh")
            upgraded[column] = upgrade["key"]
            rows[table].append(dict(data[kept][copied], key=upgrade["key"], **{k: table_value(v) for k, v in values.items()}))
        rows["missile_weapons_tables"].append(dict(missile_weapon, key=upgrade["key"], default_projectile=upgrade["key"]))
        rows["projectiles_tables"].append(upgraded)
        for unit in (unit_key(w, m) for w, m in pairs(registry) if w == weapon_key):
            junction = str(zlib.crc32(f"{unit}_{upgrade['key']}".encode()) & 0x7FFFFFFF)
            rows["unit_missile_weapon_junctions_tables"].append({"id": junction, "missile_weapon": upgrade["key"], "unit": unit, "battle_entity_stats_override": ""})
            rows["effect_bonus_value_missile_weapon_junctions_tables"].append({"bonus_value_id": "enable", "effect": upgrade["effect"], "missile_weapon_junction": junction})


def unit_rows(key: str, template: str, main: Dict[str, str], attributes: Iterable[str], abilities: List[str], variant: str, name: str, unique_index: int,
              data: Dict, rows: Dict[str, List[Dict[str, str]]], texts: List[Tuple[str, str]]) -> None:
    """Adds the rows each of his units has next to its land unit: main unit, attributes, abilities, template copies, variant and name.

    Args:
        key (str): The unit key.
        template (str): The template unit its per-unit rows are copied from.
        main (Dict[str, str]): The main unit row to copy.
        attributes (Iterable[str]): Its unit attributes, before `SKIPPED_ATTRIBUTES` are taken out.
        abilities (List[str]): Its abilities.
        variant (str): Its variant.
        name (str): Its onscreen name.
        unique_index (int): Its main unit index.
        data (Dict): The generator data.
        rows (Dict[str, List[Dict[str, str]]]): Rows by table, added to.
        texts (List[Tuple[str, str]]): Loc rows, added to.
    """
    rows["main_units_tables"].append(dict(main, unit=key, land_unit=key, unique_index=str(unique_index), caste="hero"))
    rows["unit_attributes_groups_tables"].append({"group_name": key})
    rows["unit_attributes_to_groups_junctions_tables"] += [{"attribute": a, "attribute_group": key} for a in sorted(set(attributes) - SKIPPED_ATTRIBUTES)]
    rows["land_units_to_unit_abilites_junctions_tables"] += [{"ability": a, "land_unit": key, "culture": "*"} for a in dict.fromkeys(abilities)]
    for table, column in UNIT_ROW_TABLES.items():
        rows[table] += [dict(r, **{column: key}) for r in data["templates"][table] if r[column] == template]
    rows["unit_variants_tables"].append({"faction": "", "unit": key, "name": SUBTYPE, "variant": variant, "unit_card": UNIT_CARD})
    texts.append((f"land_units_onscreen_name_{key}", name))


def apex_rows(weapon_key: str, weapon: Dict, foot: Dict, art_sets: List[str], unique_index: int, data: Dict, advisor: Dict[str, str],
              rows: Dict[str, List[Dict[str, str]]], texts: List[Tuple[str, str]]) -> str:
    """Adds a weapon's apex form: a copy of its foot unit with its own battle entity and melee weapon, and the rig that gives it.

    Args:
        weapon_key (str): The weapon key.
        weapon (Dict): The registry weapon.
        foot (Dict): The foot pair's `land`, `main`, `attributes`, `abilities`, `variant`, `uniform` and `ancillary_type`.
        art_sets (List[str]): Every weapon's art set, for the rig's uniforms.
        unique_index (int): Its main unit index.
        data (Dict): The kept vanilla rows.
        advisor (Dict[str, str]): His foot land unit.
        rows (Dict[str, List[Dict[str, str]]]): Rows by table, added to.
        texts (List[Tuple[str, str]]): Loc rows, added to.

    Returns:
        str: The rig ancillary key.

    Raises:
        SystemExit: When his foot entity or the melee template is not in the kept rows (run `--refresh`).
    """
    apex, land = weapon["apex_form"], foot["land"]
    key = unit_key(weapon_key, "apex")
    # Its values go on top of the weapon's own entity and melee weapon.
    rows["battle_entities_tables"].append(copied_row(data, "entities", advisor["man_entity"], f"{key}_entity", {**weapon.get("entity", {}), **apex.get("entity", {})}))
    melee = {**weapon.get("melee", {"template": land["primary_melee_weapon"]}), **apex.get("melee", {})}
    rows["melee_weapons_tables"].append(copied_row(data, "melee_weapons", melee.pop("template"), f"{key}_melee", melee))
    rows["land_units_tables"].append(dict(land, key=key, attribute_group=key, man_entity=f"{key}_entity", primary_melee_weapon=f"{key}_melee",
                                          **{c: table_value(v) for c, v in apex.get("stats", {}).items() if c in STAT_COLUMNS}))
    unit_rows(key, FOOT_TEMPLATE, foot["main"], foot["attributes"], foot["abilities"], foot["variant"], f"The Advisor ({weapon['name']}, {apex['name']})",
              unique_index, data, rows, texts)

    ancillary = rig_key(weapon_key, "apex")
    ancillary_rows(rows, ancillary, foot["ancillary_type"], "mount", provided_bodyguard_unit=key)
    rows["campaign_character_uniform_ancillary_junctions_tables"] += [{"ancillary": ancillary, "art_set": a, "uniform": foot["uniform"]} for a in art_sets]
    texts.append((f"ancillaries_onscreen_name_{ancillary}", f"{weapon['name']}, {apex['name']}"))
    texts.append((f"ancillaries_colour_text_{ancillary}", apex["description"]))
    return ancillary


def dragon_rows(registry: Dict, unique_index: int, data: Dict, rows: Dict[str, List[Dict[str, str]]], texts: List[Tuple[str, str]]) -> None:
    """Adds the dragon form of each foot pair whose weapon has one: a unit copied from the vanilla dragon with his stats and voice, and the two
    abilities that swap forms. A weapon's apex form gets a dragon of its own, so it turns back into the apex form.

    Args:
        registry (Dict): The units registry.
        unique_index (int): The first dragon's main unit index, after every pair's.
        data (Dict): The generator data.
        rows (Dict[str, List[Dict[str, str]]]): Rows by table, added to.
        texts (List[Tuple[str, str]]): Loc rows, added to.
    """
    templates = data["templates"]
    foot = next(r for r in templates["main_units_tables"] if r["land_unit"] == FOOT_TEMPLATE)
    foot_land = next(r for r in templates["land_units_tables"] if r["key"] == FOOT_TEMPLATE)
    # He keeps his own voice and campaign cap. The dragon's porthole camera stays, since it frames the dragon.
    voice = {k: foot[k] for k in MAIN_IDENTITY_COLUMNS if k != "porthole_camera"}
    land_voice = {k: foot_land[k] for k in VOICE_COLUMNS}
    for weapon_key, mount_key in pairs(registry):
        weapon, mount = registry["weapons"][weapon_key], registry["mounts"][mount_key]
        if "dragon" not in weapon or "template" in mount:
            continue
        dragon, template = weapon["dragon"], weapon["dragon"]["template"]
        land = next(r for r in templates["land_units_tables"] if r["key"] == template)
        stats = {c: table_value(v) for c, v in dragon.get("stats", {}).items() if c in STAT_COLUMNS}
        main = next(r for r in templates["main_units_tables"] if r["land_unit"] == template)
        attributes = [r["attribute"] for r in templates["unit_attributes_to_groups_junctions_tables"] if r["attribute_group"] == template]
        for human in [unit_key(weapon_key, mount_key)] + ([unit_key(weapon_key, "apex")] if "apex_form" in weapon else []):
            key = f"{human}_dragon"
            rows["land_units_tables"].append(dict(land, **stats, **land_voice, key=key, attribute_group=key, historical_description_text=DESCRIPTION,
                                                  short_description_text=DESCRIPTION))
            abilities = ["wh3_main_unit_passive_single_entity", transform_key(human, "human")] + dragon.get("abilities", [])
            unit_rows(key, template, dict(main, **voice), attributes, abilities, dragon["variant"], f"The Advisor ({dragon['name']})",
                      unique_index, data, rows, texts)
            unique_index += 1
            rows["land_units_to_unit_abilites_junctions_tables"].append({"ability": transform_key(human, "dragon"), "land_unit": human, "culture": "*"})
            for form, spawned in (("dragon", key), ("human", human)):
                ability, vanilla = transform_key(human, form), dragon[f"to_{form}"]
                unique_id = str(TRANSFORM_UNIQUE_ID + len(rows["unit_special_abilities_tables"]))
                rows["unit_abilities_tables"].append(dict(data["transforms"]["unit_abilities_tables"][vanilla], key=ability))
                rows["unit_special_abilities_tables"].append(dict(data["transforms"]["unit_special_abilities_tables"][vanilla], key=ability,
                                                                  spawned_unit=spawned, unique_id=unique_id))
                texts.append((f"unit_abilities_onscreen_name_{ability}", dragon[form]["name"]))
                texts.append((f"unit_abilities_tooltip_text_{ability}", dragon[form]["description"]))


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
    upgrades: List[Tuple[str, str, str, str]] = []
    art_sets = [weapon_art_set(w) for w in registry["weapons"]]
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
        attributes = (set(template_attributes.get(template, [])) | set(weapon.get("attributes", []))) - set(weapon.get("attributes_removed", []))
        abilities = [a for a in ["wh3_main_unit_passive_single_entity"] + mount.get("abilities", []) + weapon.get("abilities", [])
                     if a not in weapon.get("abilities_removed", [])]
        # Only the weapon names him, so a mount swap keeps his name. The default weapon is plain "The Advisor".
        name = "The Advisor" if weapon_key == DEFAULT_WEAPON else f"The Advisor ({weapon['name']})"
        unit_rows(key, template, main, attributes, abilities, variant, name, unique_index, data, rows, texts)
        unique_index += 1
        rows["units_custom_battle_permissions_tables"].append(dict(template_perm, unit=key, general_uniform=uniform, general_portrait=portrait_png,
                                                                   set_piece_character=""))
        if mount_key != DEFAULT_MOUNT:
            rows["units_custom_battle_mounts_tables"].append({"base_unit": unit_key(weapon_key, DEFAULT_MOUNT), "mounted_unit": key, "icon_name": mount["icon"]})
        if junction := data["riders"].get(template):
            # His rider on a monster mount plays his set and wears his variant, held where the template's rider sits.
            rows["battle_personalities_tables"].append(copied_row(data, "personalities", junction["battle_personality"], key, {
                "man_animations_table": land["man_animation"], "variant": variant, "battle_entity": land["man_entity"]}))
            rows["land_units_to_battle_personalities_junctions_tables"].append(dict(junction, battle_personality=key, land_unit=key))

        ancillary_rows(rows, ancillary, mount["ancillary_type"], "mount", provided_bodyguard_unit=key)
        for art_set in art_sets:
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
        variants[variant] = (weapon.get("body", registry["model"]["body"]), pair_props(registry, weapon_key, mount_key), look)
        if "apex_form" in weapon and "template" not in mount:
            foot = {"land": land, "main": main, "attributes": attributes, "abilities": abilities, "variant": variant, "uniform": uniform,
                    "ancillary_type": mount["ancillary_type"]}
            rig = apex_rows(weapon_key, weapon, foot, art_sets, unique_index, data, advisor, rows, texts)
            unique_index += 1
            upgrades.append((weapon_key, mount_key, rig, planned_skill_key(slot_skills(registry)[weapon["apex_form"]["slot"]])))

    dragon_rows(registry, unique_index, data, rows, texts)
    for variant in variants:
        rows["variants_tables"].append({"variant_name": variant, "variant_filename": variant, "mount_scale": "1.0000", "scale": "1.1500", "scale_variation": "0.0000"})
    for set_name in [*anims.SETS, *anims.DERIVED_SETS, *anims.BOW_DISCS]:
        rows["battle_animations_table_tables"].append({"key": set_name, "skeleton": anims.TARGET_SKELETON})
    # Every culture pack loads every animation set he or his mounts play, unless vanilla already does.
    battle_sets = {r["man_animation"] for r in rows["land_units_tables"]} | set(data["mount_animations"].values())
    vanilla_pairs = set(data["culture_animations"])
    # A set missing from `battle_animations_table` loads nothing, so the unit stands in its bind pose in battle.
    unknown = battle_sets - set(data["mount_animations"].values()) - {r["key"] for r in rows["battle_animations_table_tables"]} - {pair.split("|")[0] for pair in vanilla_pairs}
    if unknown:
        raise SystemExit(f"animation sets played but not in battle_animations_table: {', '.join(sorted(unknown))}")
    rows["culture_to_battle_animation_tables_tables"] += [{"battle_animations_table": s, "culture_pack": c} for s in sorted(battle_sets)
                                                          for c in data["culture_packs"] if f"{s}|{c}" not in vanilla_pairs]
    # Text copied from vanilla keeps its `%n%` value markers, so it skips `check_loc`. No script reads it.
    vanilla_texts: List[Tuple[str, str]] = []
    action_rows(registry, data, rows, vanilla_texts)
    effect_rows(registry, rows, vanilla_texts)
    skill_rows(registry, rows, texts)
    planned_skill_rows(registry, rows, texts)
    arts = weapon_art_rows(registry, rows, texts)
    story_bundle_rows(registry, rows, texts)
    item_rows(registry, data, rows, texts)
    lore_rows(registry, data, rows, texts)
    # After `lore_rows`, so the copies link to one lore and not every lore.
    custom_battle_lore_rows(registry, rows, texts)
    category_rows(rows)
    art_rows(registry, data, rows)
    missile_rows(registry, data, rows)
    melee_rows(registry, data, rows)
    entity_rows(registry, data, advisor, rows)
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
    write_skill_icons(rows["character_skills_tables"])
    write_script(registry, combos, upgrades, arts, [n["character_skill_key"] for n in rows["character_skill_nodes_tables"] if n["points_on_creation"] == "1"],
                 polymath_data(registry))
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
                          ("projectiles_tables", "key"), ("unit_special_abilities_tables", "unique_id")):
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


def write_skill_icons(skills: List[Dict[str, str]]) -> None:
    """Copies each skill icon the game keeps only next to its ability or effect icons into his skills folder. Like a vanilla skill icon, it is
    shrunk onto a centred black disc. Icons he no longer uses are removed from that folder.

    Args:
        skills (List[Dict[str, str]]): His `character_skills_tables` rows.

    Raises:
        SystemExit: When an icon is in no vanilla ui folder.
    """
    source = AssetSource([], [], vanilla=UI_PACKS)
    borrowed = {}
    for name in sorted({s["image_path"].lower() for s in skills if s["image_path"]}):
        if f"{SKILL_ICON_FOLDER}/{name}" in source.index:
            continue
        path = next((f"{folder}/{name}" for folder in BORROWED_ICON_FOLDERS if f"{folder}/{name}" in source.index), None)
        if path is None:
            raise SystemExit(f"skill icon {name} is in no vanilla ui folder")
        borrowed[name] = path
    found = source.fetch_all(borrowed.values())
    out = os.path.join(MOD, SKILL_ICON_FOLDER)
    os.makedirs(out, exist_ok=True)
    for name in os.listdir(out):
        if name.endswith(".png") and name not in borrowed:
            os.remove(os.path.join(out, name))
    def disc(size: Tuple[int, int]) -> Image.Image:
        """A round mask, drawn large and shrunk for a smooth edge."""
        big = Image.new("L", (size[0] * 4, size[1] * 4))
        ImageDraw.Draw(big).ellipse((0, 0, big.width - 1, big.height - 1), fill=255)
        return big.resize(size, Image.LANCZOS)

    outline = Image.new("RGBA", SKILL_ICON_OUTLINE, (0, 0, 0, 255))
    outline.putalpha(disc(SKILL_ICON_OUTLINE))
    for name, path in borrowed.items():
        # Crop to the picture first, so an icon with a clear or shadowed border of its own still fills the picture.
        image = Image.open(io.BytesIO(found[path])).convert("RGBA")
        solid = image.getchannel("A").point(lambda a: 255 if a > ICON_ALPHA_FLOOR else 0)
        lit = image.convert("RGB").convert("L").point(lambda v: 255 if v > ICON_DARK_FLOOR else 0)
        image = image.crop(ImageChops.darker(solid, lit).getbbox())
        scale = min(SKILL_ICON_PICTURE[0] / image.width, SKILL_ICON_PICTURE[1] / image.height)
        image = image.resize((round(image.width * scale), round(image.height * scale)), Image.LANCZOS)
        # Trim to a circle, so a square glow does not show at the corners.
        image.putalpha(ImageChops.darker(image.getchannel("A"), disc(image.size)))
        icon = Image.new("RGBA", SKILL_ICON_SIZE)
        icon.alpha_composite(outline, ((SKILL_ICON_SIZE[0] - outline.width) // 2, (SKILL_ICON_SIZE[1] - outline.height) // 2))
        icon.alpha_composite(image,((SKILL_ICON_SIZE[0] - image.width) // 2, (SKILL_ICON_SIZE[1] - image.height) // 2))
        icon.save(os.path.join(out, name), optimize=True)


def write_script(registry: Dict, combos: List[Tuple[str, str, str]], upgrades: List[Tuple[str, str, str, str]], arts: Dict[str, List[Dict]],
                 learned: List[str], polymath: Optional[Dict]) -> None:
    """Writes the Lua data table the campaign scripts read: his subtype, the weapons and mounts with their unlock skills, names and picker icons,
    the ancillary of every valid pair both ways, the rigs that replace a pair's once he owns a skill, the skills he is made with, each weapon's
    arts and the Polymath.

    Args:
        registry (Dict): The registry.
        combos (List[Tuple[str, str, str]]): (weapon, mount, ancillary) per valid pair.
        upgrades (List[Tuple[str, str, str, str]]): (weapon, mount, ancillary, skill) per pair whose rig is replaced once he owns the skill.
        arts (Dict[str, List[Dict]]): Weapon -> its arts, from `weapon_art_rows`.
        learned (List[str]): The skills he is made with.
        polymath (Optional[Dict]): The Polymath, from `polymath_data`, or None.
    """
    quote = lambda text: text.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")
    folder = os.path.join(MOD, "script", "campaign", "mod")
    os.makedirs(folder, exist_ok=True)
    lines = ["--- Generated by generators/advisor_overhaul.py. Do not edit by hand.", "ADVISOR_OVERHAUL_RIGS = {",
             "\t--- The Advisor's agent subtype.", f'\tsubtype = "{SUBTYPE}",',
             "\t--- Weapon he holds when nothing else is chosen. Always unlocked.", f'\tdefault_weapon = "{DEFAULT_WEAPON}",',
             "\t--- Mount he rides when nothing else is chosen. Always unlocked.", f'\tdefault_mount = "{DEFAULT_MOUNT}",']
    for kind, items in (("weapon", registry["weapons"]), ("mount", registry["mounts"])):
        lines.append(f"\t--- {kind.capitalize()}s in skill tree order: key, unlock skill (empty for the default), name loc key, English fallback name and "
                     "picker icon.")
        lines.append("\t--- A `grant_rank` is the rank at which the script gives him that item's skill.")
        if kind == "weapon":
            lines.append("\t--- Weapons also name the art set that shows them in the character panel.")
        lines.append(f"\t{kind}s = {{")
        for key, item in items.items():
            name = quote(item["name"])
            art = f', art_set = "{weapon_art_set(key)}"' if kind == "weapon" else ""
            art += f', grant_rank = {item["grant_rank"]}' if item.get("grant_rank") else ""
            lines.append(f'\t\t{{ key = "{key}", skill = "{unlock_skill(kind, key)}", name = "{ui_name(kind, key)}", fallback = "{name}", '
                         f'icon = "{item["picker_icon"]}"{art} }},')
        lines.append("\t},")
    lines += ['\t--- "weapon|mount" -> the mount ancillary that gives him that unit. Only pairs with a unit are listed.', "\tancillaries = {"]
    lines += [f'\t\t["{w}|{m}"] = "{a}",' for w, m, a in combos]
    lines += ["\t},", "\t--- Mount ancillary -> the weapon and mount of its pair.", "\trigs = {"]
    lines += [f'\t\t["{a}"] = {{ weapon = "{w}", mount = "{m}" }},' for w, m, a in combos + [u[:3] for u in upgrades]]
    lines += ["\t},", '\t--- "weapon|mount" -> the skill that swaps that pair\'s rig for another (an apex form), and that rig.', "\tupgrades = {"]
    lines += [f'\t\t["{w}|{m}"] = {{ skill = "{s}", ancillary = "{a}" }},' for w, m, a, s in upgrades]
    lines += ["\t},", "\t--- Forename loc key of his name.", f'\tname = "names_name_{name_id()}",']
    lines += ["\t--- Hidden skills he is made with. An Advisor from before they were added gets them from the spawn script.", "\tlearned_skills = {"]
    lines += [f'\t\t"{skill}",' for skill in learned]
    lines += ["\t},", "\t--- Weapon -> its arts: the art slot skill he must own and its English name, the effect bundle he wears",
              "\t--- for it while holding that weapon, the art's English name (its loc key is the bundle's title), the slot skill's flavour text,",
              "\t--- the art's description and the slot skills it needs, for the art card tooltip.", "\tarts = {"]
    for weapon, slots in arts.items():
        lines.append(f'\t\t["{weapon}"] = {{')
        for art in slots:
            requires = ", ".join(f'{{ skill = "{r["skill"]}", name = "{quote(r["name"])}" }}' for r in art["requires"])
            lines.append(f'\t\t\t{{ skill = "{art["skill"]}", skill_name = "{quote(art["skill_name"])}", '
                         f'bundle = "{art["bundle"]}", name = "{quote(art["name"])}", flavour = "{quote(art["flavour"])}", '
                         f'about = "{quote(art["about"])}", requires = {{ {requires} }} }},')
        lines += ["\t\t},"]
    lines += ["\t},"]
    if polymath:
        lines += ["\t--- The Polymath: its skill, name and flavour, how many skills of a discipline make it count, each discipline's skills in tree order,",
                  "\t--- and the bundle for each number of disciplines that count, from 0.", "\tpolymath = {", f'\t\tskill = "{polymath["skill"]}",',
                  f'\t\tname = "{quote(polymath["name"])}",', f'\t\tflavour = "{quote(polymath["flavour"])}",', f'\t\tneeded = {polymath["needed"]},', "\t\tdisciplines = {"]
        lines += [f'\t\t\t{{ name = "{d["name"]}", skills = {{ ' + ", ".join(f'"{k}"' for k in d["skills"]) + " } }," for d in polymath["disciplines"]]
        lines += ["\t\t},", "\t\tbundles = { " + ", ".join(f'"{b}"' for b in polymath["bundles"]) + " },", "\t},"]
    lines += ["}"]
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
