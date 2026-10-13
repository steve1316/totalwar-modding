"""Export the Addvisor unit gallery for the animation viewer: every weapon and mount pair with its model, props, mount and animations.

Each pair of the units registry becomes one entry. The rider uses the pair's land unit animation set and its variant (from the generated
agent uniforms). A mounted pair also gets the mount from the land unit's `mount` key: the mount's own animation set and model. Rider slots are
named `RIDER_<slot>` and play next to the mount's `<slot>`. Both animations are authored around the same origin, so the rider needs no attach
bone. A vanilla reference hero and the disc retarget comparison are added as extra entries.

Usage (from helper_scripts):
    python -u -m tools.anim_viewer.gallery [--out _diag/anim_viewer_next] [--serve 8767] [--host 127.0.0.1]
"""

import argparse
import glob
import json
import os
import sys
from typing import Dict, List, Optional, Tuple

from core.extract_cache import cached_pack_extract
from core.utilities import FILEPATH_TO_VANILLA_DATA_TABLES, STEAM_LIBRARY_DRIVE, load_tsv_data
from tools.anim_viewer.__main__ import serve
from tools.anim_viewer.exporter import Exporter, compare_entry, first_refs
from tools.anim_viewer.models import AssetSource
from tools.glf_rebuild_animpack import VANILLA_DATA_DIR, AnimSet, load_vanilla_sets, parse_set, read_animpack

# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Settings

# Generated mod folder and its animation pack.
MOD = "../warhammer3_mods/!!pj_advisor_overhaul"
MOD_ANIMPACK = f"{MOD}/animations/database/battle/bin/pj_advisor_overhaul.animpack"

# The units registry: weapons, mounts and their animation sets.
REGISTRY = "./generators/pj_advisor_units_registry.json"

# The base Addvisor pack (his body and head meshes, and his two original units) and where its tables are extracted.
BASE_PACK = f"{STEAM_LIBRARY_DRIVE}/SteamLibrary/steamapps/workshop/content/1142710/2795714008/pj_advisor.pack"
BASE_EXTRACT = "./temp/anim_viewer_gallery_base"

# The base mod's own units, which the generator keeps instead of writing new ones: (weapon, mount) -> unit key.
BASE_UNITS = {("staff_and_sword", "foot"): "pj_advisor", ("staff_and_sword", "pegasus"): "pj_advisor_mount_warhorse"}

# Folder of animation set files inside packs.
SET_FOLDER = "animations/database/battle/bin"

# Vanilla packs holding the `.anim` files and skeletons.
ANIM_PACKS = ("anim.pack", "anim2.pack", "anim_3.pack")

# Vanilla tables read for mounts, variants and the reference units, and where they are extracted.
VANILLA_TABLES = ("land_units_tables", "mounts_tables", "variants_tables", "unit_variants_tables")
VANILLA_EXTRACT = "./temp/anim_viewer_gallery_db"

# Slots exported for every unit. A mounted rider plays `RIDER_<slot>`.
SLOTS = ["STAND", "WALK_1", "RUN_1", "CHARGE", "ATTACK_1", "ATTACK_2", "ATTACK_3", "ATTACK_4", "CAST_SPELL_FORWARD_SHORT", "CAST_SPELL_FORWARD_MEDIUM",
         "CAST_SPELL_FORWARD_LONG", "CAST_SPELL_UP_SHORT", "CAST_SPELL_UP_MEDIUM", "CAST_SPELL_UP_LONG", "DEFEND_1", "DEATH_STAND_1"]

# Extra slots for units that fly.
FLY_SLOTS = ["FLY_STAND", "FLY_WALK_1", "FLY_ATTACK_1"]

# Vanilla units exported next to the Addvisor's, to compare the rider's seat and props.
REFERENCE_UNITS = {"wh_main_emp_cha_captain_0": "Vanilla: Empire Captain - Sword and Shield",
                   "wh2_pro07_emp_cha_wizard_death_3": "Vanilla: Amethyst Wizard - Barded Warhorse"}

# The disc retarget comparison: the vanilla Tzeentch sorcerer's set and model against the Addvisor's disc set.
DISC_SOURCE_SET = "hu1c_wh3_dlc20_tzeentch_sorcerer_wm_disc01_staff_sword"
DISC_SOURCE_VARIANT = "variantmeshes/variantmeshdefinitions/dae_tze_chaos_sorcerer_disc.variantmeshdefinition"
DISC_TARGET_SET = "hu1_pj_advisor_disc01_staff_and_sword"

# Slots left out of the disc comparison to keep the export small: matched combat, portholes and all but the first death.
COMPARE_SKIP = r"^(RIDER_)?(COMBAT_|PORTHOLE|PERSISTENT|STAND_NO_WEAPON|DEATH_(?!STAND_1$)|DEATH_SHOOT|KNOCKBACK|KNOCKDOWN|HIT_REACTION_STAND_[2-9])"

# Side colours: rider and mount.
RIDER_COLOUR = "#f2a33a"
MOUNT_COLOUR = "#4fb3ff"


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Data


def read_table(folder: str, table: str) -> List[Dict[str, str]]:
    """Rows of every TSV of one table in a `db` folder.

    Args:
        folder (str): The folder holding `db`.
        table (str): Table folder name.

    Returns:
        List[Dict[str, str]]: The rows.
    """
    rows: List[Dict[str, str]] = []
    for path in sorted(glob.glob(os.path.join(folder, "db", table, "*.tsv"))):
        rows += load_tsv_data(path)[0]
    return rows


def vanilla_tables() -> Dict[str, List[Dict[str, str]]]:
    """Extracts and reads the vanilla tables the gallery needs.

    Returns:
        Dict[str, List[Dict[str, str]]]: Rows by table.
    """
    for table in VANILLA_TABLES:
        if not os.path.isdir(os.path.join(VANILLA_EXTRACT, "db", table)):
            cached_pack_extract(FILEPATH_TO_VANILLA_DATA_TABLES, f"db/{table}", VANILLA_EXTRACT)
    return {table: read_table(VANILLA_EXTRACT, table) for table in VANILLA_TABLES}


def load_sets() -> Dict[str, AnimSet]:
    """Every vanilla animation set plus the mod's own, by set name. The mod's win.

    Returns:
        Dict[str, AnimSet]: Sets by name.
    """
    files = dict(load_vanilla_sets())
    files.update(read_animpack(open(MOD_ANIMPACK, "rb").read()))
    return {os.path.basename(p)[:-4]: parse_set(d) for p, d in files.items() if p.startswith(SET_FOLDER) and p.endswith(".bin")}


def variant_path(filename: str) -> str:
    """The variant mesh definition for a `variant_filename`: the generated mod file if there is one, else the game path.

    Args:
        filename (str): Value of `variants_tables.variant_filename`.

    Returns:
        str: Local file or game path.
    """
    local = f"{MOD}/variantmeshes/variantmeshdefinitions/{filename}.variantmeshdefinition"
    return local if os.path.exists(local) else f"variantmeshes/variantmeshdefinitions/{filename}.variantmeshdefinition"


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Entries


def unit_entry(exporter: Exporter, name: str, rider_set: AnimSet, rider_variant: str, mount_set: Optional[AnimSet], mount_variant: Optional[str],
               info: List[str]) -> Dict:
    """Adds one unit: the rider and, when mounted, the mount, playing matching slots together.

    Args:
        exporter (Exporter): The exporter.
        name (str): Entry name shown in the picker.
        rider_set (AnimSet): The rider's (or foot unit's) animation set.
        rider_variant (str): The rider's variant mesh definition.
        mount_set (Optional[AnimSet]): The mount's animation set, or None on foot.
        mount_variant (Optional[str]): The mount's variant mesh definition.
        info (List[str]): Lines shown under the name.

    Returns:
        Dict: The entry, already added to the exporter.
    """
    rider_refs = first_refs(rider_set, exporter.names)
    mount_refs = first_refs(mount_set, exporter.names) if mount_set else {}
    flyer = "FLY_STAND" in (mount_refs or rider_refs)
    slots = []
    for slot in SLOTS + (FLY_SLOTS if flyer else []):
        rider_slot = f"RIDER_{slot}" if mount_set else slot
        if rider_slot not in rider_refs:
            continue
        entry = {"slot": slot, "anims": {"rider": exporter.anim(rider_refs[rider_slot])}, "paths": {"rider": rider_refs[rider_slot]}, "slots": {"rider": rider_slot}}
        if mount_set:
            # A slot the mount lacks (such as a cast) plays the mount's idle.
            mount_slot = slot if slot in mount_refs else ("FLY_STAND" if slot.startswith("FLY_") and "FLY_STAND" in mount_refs else "STAND")
            entry["anims"]["mount"] = exporter.anim(mount_refs[mount_slot])
            entry["paths"]["mount"] = mount_refs[mount_slot]
            entry["slots"]["mount"] = mount_slot
        slots.append(entry)
    sides = [{"key": "rider", "label": "Rider" if mount_set else "Unit", "color": RIDER_COLOUR,
              "model": exporter.model(rider_variant, exporter.anims[slots[0]["anims"]["rider"]]["skeleton"])}]
    if mount_set:
        sides.append({"key": "mount", "label": "Mount", "color": MOUNT_COLOUR, "model": exporter.model(mount_variant, mount_set.skeleton) if mount_variant else None})
    entry = {"name": name, "kind": "unit", "sets": [rider_set.name] + ([mount_set.name] if mount_set else []), "info": info, "sides": sides, "slots": slots}
    exporter.entries.append(entry)
    print(f"{name}: {len(slots)} slots")
    return entry


def mount_parts(mount_key: str, tables: Dict[str, List[Dict[str, str]]], sets: Dict[str, AnimSet]) -> Tuple[AnimSet, str]:
    """The animation set and variant of a `mounts_tables` key.

    Args:
        mount_key (str): Mount key, e.g. `wh_main_emp_mnt_pegasus`.
        tables (Dict[str, List[Dict[str, str]]]): Vanilla tables.
        sets (Dict[str, AnimSet]): Animation sets by name.

    Returns:
        Tuple[AnimSet, str]: The set and the variant path.
    """
    mount = next(r for r in tables["mounts_tables"] if r["key"] == mount_key)
    variant = next(r for r in tables["variants_tables"] if r["variant_name"] == mount["variant"])
    return sets[mount["animation"]], variant_path(variant["variant_filename"])


def build(out: str) -> Exporter:
    """Exports every gallery entry.

    Args:
        out (str): Output folder.

    Returns:
        Exporter: The exporter, already written.
    """
    registry = json.load(open(REGISTRY, encoding="utf-8"))
    tables = vanilla_tables()
    sets = load_sets()
    if not os.path.isdir(os.path.join(BASE_EXTRACT, "db", "land_units_tables")):
        cached_pack_extract(BASE_PACK, "db/land_units_tables", BASE_EXTRACT)
    land_units = {r["key"]: r for r in read_table(MOD, "land_units_tables") + read_table(BASE_EXTRACT, "land_units_tables")}
    uniforms = {r["uniform_name"]: r for r in read_table(MOD, "agent_uniforms_tables")}
    variants = {r["variant_name"]: r for r in read_table(MOD, "variants_tables") + tables["variants_tables"]}
    packs = [BASE_PACK] + [os.path.join(VANILLA_DATA_DIR, p) for p in ANIM_PACKS]
    exporter = Exporter(out, AssetSource([MOD], packs))

    for weapon, mount in [(w, m) for w, item in registry["weapons"].items() for m in registry["mounts"] if m in item["sets"]]:
        key = BASE_UNITS.get((weapon, mount), f"pj_advisor_{weapon}_{mount}")
        row = land_units[key]
        set_name = row["man_animation"]
        if set_name != registry["weapons"][weapon]["sets"][mount]:
            print(f"warning: {key} land unit plays {set_name}, registry says {registry['weapons'][weapon]['sets'][mount]}")
        variant = variants[uniforms[f"pj_advisor_{weapon}_{mount}"]["battle_filename"]]["variant_filename"]
        mount_set, mount_variant = mount_parts(row["mount"], tables, sets) if row["mount"] else (None, None)
        name = f"{registry['weapons'][weapon]['name']} - {registry['mounts'][mount]['name']}"
        info = [f"unit {key}", f"rider set {set_name}", f"variant {variant}"] + ([f"mount {row['mount']} ({mount_set.name})"] if mount_set else [])
        unit_entry(exporter, name, sets[set_name], variant_path(variant), mount_set, mount_variant, info)

    for key, name in REFERENCE_UNITS.items():
        row = next(r for r in tables["land_units_tables"] if r["key"] == key)
        variant_name = next(r["variant"] for r in tables["unit_variants_tables"] if r["unit"] == key)
        variant = variants[variant_name]["variant_filename"]
        mount_set, mount_variant = mount_parts(row["mount"], tables, sets) if row["mount"] else (None, None)
        info = [f"unit {key}", f"rider set {row['man_animation']}", f"variant {variant}"] + ([f"mount {row['mount']} ({mount_set.name})"] if mount_set else [])
        unit_entry(exporter, name, sets[row["man_animation"]], variant_path(variant), mount_set, mount_variant, info)

    disc_variant = variant_path(variants[uniforms["pj_advisor_staff_and_sword_disc"]["battle_filename"]]["variant_filename"])
    entry = compare_entry(exporter, "Disc retarget: Tzeentch sorcerer vs Addvisor", sets[DISC_SOURCE_SET], sets[DISC_TARGET_SET],
                          {"source": DISC_SOURCE_VARIANT, "target": disc_variant}, skip=COMPARE_SKIP)
    print(f"{entry['name']}: {len(entry['slots'])} slots")
    exporter.write()
    return exporter


def main() -> int:
    """Exports the gallery and optionally serves it.

    Returns:
        int: Process exit code.
    """
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--out", default="./_diag/anim_viewer_next")
    parser.add_argument("--serve", type=int, metavar="PORT", help="serve the folder on this port after exporting")
    parser.add_argument("--host", default="127.0.0.1")
    args = parser.parse_args()
    build(args.out)
    if args.serve:
        serve(args.out, args.serve, args.host)
    return 0


if __name__ == "__main__":
    sys.exit(main())
