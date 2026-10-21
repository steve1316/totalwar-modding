"""Export the Advisor Overhaul gallery for the modding workbench's Viewer tab: every weapon and mount pair with its model, props, mount and animations.

Each pair of the generator's registry becomes one entry. The rider uses the pair's land unit animation set and its variant (from the generated
agent uniforms). A mounted pair also gets the mount from the land unit's `mount` key: the mount's own animation set and model. Rider slots are
named `RIDER_<slot>` and play next to the mount's `<slot>`. Both animations are authored around the same origin, so the rider needs no attach
bone. His default look comes first (on foot, and on the Pegasus), then the hoodless head, then every pair. A vanilla reference hero, the vanilla
campaign Advisor on his own skeleton and a comparison for each retargeted set of `generators.advisor_overhaul_anims` are added as extra
entries. Any variant mesh definition left in `PREVIEWS` (with the models it needs under the same folder) becomes a preview entry, for trying looks
without touching the mod. None are shown when it is empty.
The export also carries the data of the workbench's Portrait tab: his hooded and hoodless looks and a vanilla Grey Wizard in the porthole idle animation, with
the registry's head camera, so the campaign portrait camera can be tuned without restarting the game.

Usage (from helper_scripts):
    python -u -m generators.advisor_overhaul_gallery --out ./_diag/anim_viewer_next

The workbench's Advisor Overhaul project (`modding-workbench/projects/advisor_overhaul.json`) runs this in its rebuild job and draws the result.
"""

import argparse
import glob
import json
import os
import sys
from typing import Dict, List, Optional, Tuple

from core.asset_source import VANILLA_DATA_DIR, AssetSource
from core.utilities import extract_tsv_data, load_tsv_data
from generators import advisor_overhaul_anims as anims
from generators.advisor_overhaul import DATA, DEFAULT_MOUNT, DEFAULT_WEAPON, MOD, PROP_CHANGES, load_registry, pairs, uniform_key, unit_key
from generators.advisor_overhaul_model import PREVIEWS
from generators.advisor_overhaul_panels import build_panels
from tools.anim_file import read_anim
from tools.anim_retarget import Transform, compose, world_pose
from tools.anim_viewer.exporter import Exporter, compare_entry, first_refs
from tools.glf_rebuild_animpack import AnimSet, load_vanilla_sets, parse_set, read_animpack

# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Settings

# The mod's animation pack.
MOD_ANIMPACK = f"{MOD}/{anims.ANIMPACK}"

# Folder of animation set files inside packs.
SET_FOLDER = anims.SET_FOLDER

# Vanilla packs holding the `.anim` files and skeletons.
ANIM_PACKS = ("anim.pack", "anim2.pack", "anim_3.pack")

# The table naming the mount bone a monster's rider sits on.
JUNCTIONS = "land_units_to_battle_personalities_junctions_tables"

# Vanilla tables read for mounts, variants, rider bones and the reference units.
VANILLA_TABLES = ("land_units_tables", "mounts_tables", "variants_tables", "unit_variants_tables", JUNCTIONS)

# The mount side each rider side sits on.
MOUNT_SIDES = {"rider": "mount", "v_rider": "v_mount"}
# Slots exported for every unit. A mounted rider plays `RIDER_<slot>`. A slot the set lacks is left out, so the fire slots only show for archers
# (`FIRE_LEVEL` on foot, `RIDER_FIRE_FORWARD_LEVEL` mounted).
SLOTS = ["STAND", "WALK_1", "RUN_1", "CHARGE", "ATTACK_1", "ATTACK_2", "ATTACK_3", "ATTACK_4", "CAST_SPELL_FORWARD_SHORT", "CAST_SPELL_FORWARD_MEDIUM",
         "CAST_SPELL_FORWARD_LONG", "CAST_SPELL_UP_SHORT", "CAST_SPELL_UP_MEDIUM", "CAST_SPELL_UP_LONG", "DEFEND_1", "DEATH_STAND_1", "SHOOT_READY",
         "AIM_LEVEL", "FIRE_LEVEL", "MOVING_FIRE_FORWARD_LEVEL", "FIRE_FORWARD_LEVEL", "FIRE_LEFT_LEVEL"]

# Extra slots for units that fly.
FLY_SLOTS = ["FLY_STAND", "FLY_WALK_1", "FLY_ATTACK_1"]

# Vanilla units exported next to the Advisor's, to compare the rider's seat and props.
REFERENCE_UNITS = {"wh_main_emp_cha_captain_0": "Vanilla: Empire Captain - Sword and Shield",
                   "wh2_pro07_emp_cha_wizard_death_3": "Vanilla: Amethyst Wizard - Barded Warhorse"}

# Retarget comparisons: vanilla source set of a retargeted set -> (entry name, the vanilla model it is shown on). A set missing here is compared
# without a source model.
COMPARE_SOURCES = {"hu1c_wh3_dlc20_tzeentch_sorcerer_wm_disc01_staff_sword": (
    "Disc retarget: Tzeentch sorcerer vs Advisor", "variantmeshes/variantmeshdefinitions/dae_tze_chaos_sorcerer_disc.variantmeshdefinition"),
                   "hu1e_cp1_taoyan_trident": ("Glaive retarget: Taoyan vs Advisor", "variantmeshes/variantmeshdefinitions/cth_taoyan.variantmeshdefinition")}

# The look checks: the mount of his mounted default look, the slots of his default look on foot and mounted, the folder for the hoodless variant,
# and the vanilla campaign Advisor (variant, skeleton and its animations by slot name).
LOOK_MOUNT = "pegasus"
LOOK_SLOTS = ["STAND", "WALK_1", "RUN_1", "CAST_SPELL_FORWARD_SHORT", "CAST_SPELL_UP_LONG", "ATTACK_1"]
LOOK_MOUNTED_SLOTS = ["STAND", "CAST_SPELL_FORWARD_SHORT", "FLY_STAND", "FLY_WALK_1"]
LOOK_VARIANTS = "./temp/anim_viewer_gallery_looks"
ADVISOR_VARIANT = "variantmeshes/variantmeshdefinitions/misc_advisor_ad1.variantmeshdefinition"
ADVISOR_SKELETON = "advisor01"
ADVISOR_ANIMS = {"PORTHOLE_IDLE": "animations/battle/advisor01/porthole/ad1_porthole_stand_idle_01.anim",
                 "HARVEST_IDLE": "animations/cinematic/library/anim/advisor01/realm_win_igc/harvest/idle/advisor01_rwin_harvest_idle.anim",
                 "REVEAL_WALK": "animations/cinematic/library/anim/advisor01/realm_win_igc/reveal/walk/advisor01_rwin_reveal_walk.anim"}

# Portrait camera preview: the porthole idle animation, the vanilla reference's label and the head camera fields shown. The reference's art set,
# variant and camera come from the vanilla portrait entry kept in the generator's snapshot.
PORTHOLE_ANIM = "animations/battle/humanoid01/unarmed/porthole/hu1_un_porthole_idle_01.anim"
PORTRAIT_REFERENCE_LABEL = "Vanilla Grey Wizard"
CAMERA_FIELDS = ("z", "y", "yaw", "pitch", "fov")

# Head camera values tried in game, oldest first, with what each showed. The page offers them as presets.
PORTRAIT_ROUNDS = [({"z": 1.0, "y": 0.05, "yaw": 0.0, "pitch": 0.0, "fov": 30.0}, "looked up at him"),
                   ({"z": 1.0, "y": 0.12, "yaw": 0.0, "pitch": 8.0, "fov": 30.0}, "level, but small and low"),
                   ({"z": 0.8, "y": 0.06, "yaw": 0.0, "pitch": 8.0, "fov": 30.0}, "better, face a bit low"),
                   ({"z": 0.8, "y": 0.03, "yaw": 0.0, "pitch": 8.0, "fov": 30.0}, "face centred, slightly too close")]

# Slots left out of the disc comparison to keep the export small: matched combat, portholes and all but the first death.
COMPARE_SKIP = r"^(RIDER_)?(COMBAT_|PORTHOLE|PERSISTENT|STAND_NO_WEAPON|DEATH_(?!STAND_1$)|DEATH_SHOOT|KNOCKBACK|KNOCKDOWN|HIT_REACTION_STAND_[2-9])"

# Side colours: rider and mount, then the vanilla equivalent's rider and mount.
RIDER_COLOUR = "#f2a33a"
MOUNT_COLOUR = "#4fb3ff"
VANILLA_RIDER_COLOUR = "#d8d0b8"
VANILLA_MOUNT_COLOUR = "#8fa0b4"


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
    """Reads the vanilla tables the gallery needs, through the extract cache.

    Returns:
        Dict[str, List[Dict[str, str]]]: Rows by table.
    """
    return {table: load_tsv_data(f"{extract_tsv_data(table)}/db/{table}/data__.tsv")[0] for table in VANILLA_TABLES}


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


def matching_slot(slot: str, mounted: bool, refs: Dict[str, str], saddled: bool = False) -> Optional[str]:
    """The slot a rider or foot unit plays for a gallery slot: `RIDER_<slot>` when mounted, else the slot itself, falling back to its stand (or fly
    stand). A rider in the saddle (`anims.SADDLE_SPACE`, as on the dragons) sits through his mount's moves and attacks: the foot slots his set also
    holds never play on the mount, so he plays only his `RIDER_` slots and his seated stand (`RIDER_STAND` in Elspeth's set, `STAND` in most).

    Args:
        slot (str): The gallery slot, e.g. `ATTACK_1`.
        mounted (bool): Whether the unit rides.
        refs (Dict[str, str]): The set's slots.
        saddled (bool): Whether the rider sits in the saddle.

    Returns:
        Optional[str]: The slot, or None when the set has neither it nor a stand.
    """
    stands = ("FLY_STAND" if slot.startswith("FLY_") else "STAND", "STAND")
    if saddled:
        names = ["RIDER_" + slot, *("RIDER_" + stand for stand in stands), *stands]
    else:
        names = [prefix + name for name in (slot, *stands) for prefix in (("RIDER_", "") if mounted else ("",))]
    return next((name for name in names if name in refs), None)


def rider_seat(exporter: Exporter, unit: str, rider_set: AnimSet, mount_key: str, tables: Dict[str, List[Dict[str, str]]]) -> Optional[Tuple[int, Transform]]:
    """Where a rider set placed from the mount's rider bone (`anims.SADDLE_SPACE`, as on the dragons) sits: the bone the unit's rider row names, as
    the mount's tech skeleton holds it. Other rider sets carry the mount's height and stand on its origin.

    Args:
        exporter (Exporter): The exporter, for the tech skeleton.
        unit (str): The land unit key.
        rider_set (AnimSet): The rider's set.
        mount_key (str): The `mounts_tables` key.
        tables (Dict[str, List[Dict[str, str]]]): Vanilla tables, with his own variant and rider rows.

    Returns:
        Optional[Tuple[int, Transform]]: The bone's parent on the mount's skeleton and its offset from that parent, or None when the rider stands on
        the mount's origin or no tech skeleton has the bone.
    """
    if not rider_set.flag & anims.SADDLE_SPACE:
        return None
    bone = next((r["riders_attachment_point"] for r in tables[JUNCTIONS] if r["land_unit"] == unit), "")
    mount = next(r for r in tables["mounts_tables"] if r["key"] == mount_key)
    variant = next(r for r in tables["variants_tables"] if r["variant_name"] == mount["variant"])
    folder = variant.get("tech_folder", "").replace("\\", "/").lower()
    for path in sorted(p for p in exporter.assets.index if bone and folder and p.startswith(folder) and p.endswith(".anim")):
        tech = read_anim(exporter.read(path))
        found = next((i for i, b in enumerate(tech.bones) if b.name == bone), None)
        if found is not None:
            return tech.bones[found].parent, (tech.rotations[0][found], tech.translations[0][found])
    print(f"warning: {unit} sits on {bone or 'no rider bone'} of {mount_key}, which no tech skeleton has, so it stands on the mount's origin")
    return None


def seat_track(exporter: Exporter, path: str, parent: int, offset: Transform) -> Dict:
    """The world place of a mount's rider bone in each frame of one of its animations.

    Args:
        exporter (Exporter): The exporter.
        path (str): The mount animation.
        parent (int): The rider bone's parent on the mount's skeleton.
        offset (Transform): The rider bone's offset from that parent.

    Returns:
        Dict: `fps` and `frames`, each frame the position then the quaternion (x, y, z, w), as the viewer's animations hold bones.
    """
    anim = read_anim(exporter.read(path))
    skeleton = exporter.skeleton(anim.skeleton)
    seats = [compose(world_pose(anim, skeleton, frame)[parent], offset) for frame in range(len(anim.rotations))]
    return {"fps": anim.frame_rate, "frames": [[round(v, 4) for v in (*position, *rotation)] for rotation, position in seats]}


def unit_entry(exporter: Exporter, name: str, rider_set: AnimSet, rider_variant: str, mount_set: Optional[AnimSet], mount_variant: Optional[str],
               info: List[str], slot_names: Optional[List[str]] = None, versus: Optional[Tuple[str, AnimSet, str, Optional[AnimSet], Optional[str]]] = None,
               seats: Optional[Dict[str, Tuple[int, Transform]]] = None) -> Dict:
    """Adds one unit: the rider and, when mounted, the mount, playing matching slots together. With `versus`, the vanilla equivalent is added as two
    more sides (`v_rider`, `v_mount`) playing the same slots, or its stand where its sets lack one.

    Args:
        exporter (Exporter): The exporter.
        name (str): Entry name shown in the picker.
        rider_set (AnimSet): The rider's (or foot unit's) animation set.
        rider_variant (str): The rider's variant mesh definition.
        mount_set (Optional[AnimSet]): The mount's animation set, or None on foot.
        mount_variant (Optional[str]): The mount's variant mesh definition.
        info (List[str]): Lines shown under the name.
        slot_names (Optional[List[str]]): Slots to export, `SLOTS` (plus `FLY_SLOTS` for flyers) when None.
        versus (Optional[Tuple[str, AnimSet, str, Optional[AnimSet], Optional[str]]]): The vanilla equivalent's unit key, rider set, rider variant,
            mount set and mount variant.
        seats (Optional[Dict[str, Tuple[int, Transform]]]): Rider side -> its rider bone (see `rider_seat`). That side then follows the bone in
            each slot's animation of its mount side.

    Returns:
        Dict: The entry, already added to the exporter.
    """
    rider_refs = first_refs(rider_set, exporter.names)
    mount_refs = first_refs(mount_set, exporter.names) if mount_set else {}
    # Props docked by a set's metadata are held where the game holds them, as in the retarget comparisons.
    rider_docking, mount_docking = exporter.docking(rider_set), exporter.docking(mount_set) if mount_set else None
    flyer = "FLY_STAND" in (mount_refs or rider_refs)
    saddled = bool(mount_set) and bool(rider_set.flag & anims.SADDLE_SPACE)
    slots = []
    for slot in slot_names or SLOTS + (FLY_SLOTS if flyer else []):
        if saddled:
            # He sits in the saddle, so a slot only his mount plays is shown with him in his stand.
            rider_slot = matching_slot(slot, True, rider_refs, saddled) if "RIDER_" + slot in rider_refs or slot in mount_refs else None
        else:
            rider_slot = "RIDER_" + slot if mount_set and "RIDER_" + slot in rider_refs else slot
        if rider_slot not in rider_refs:
            continue
        entry = {"slot": slot, "anims": {"rider": exporter.anim(rider_refs[rider_slot], rider_docking)}, "paths": {"rider": rider_refs[rider_slot]}, "slots": {"rider": rider_slot}}
        if mount_set:
            # A slot the mount lacks (such as a cast) plays the mount's idle.
            mount_slot = slot if slot in mount_refs else ("FLY_STAND" if slot.startswith("FLY_") and "FLY_STAND" in mount_refs else "STAND")
            entry["anims"]["mount"] = exporter.anim(mount_refs[mount_slot], mount_docking)
            entry["paths"]["mount"] = mount_refs[mount_slot]
            entry["slots"]["mount"] = mount_slot
        if versus:
            _, v_rider_set, _, v_mount_set, _ = versus
            for side, anim_set, mounted in (("v_rider", v_rider_set, bool(v_mount_set)), ("v_mount", v_mount_set, False)):
                refs = first_refs(anim_set, exporter.names) if anim_set else {}
                played = matching_slot(slot, mounted, refs, mounted and bool(anim_set.flag & anims.SADDLE_SPACE))
                if played:
                    entry["anims"][side] = exporter.anim(refs[played], exporter.docking(anim_set))
                    entry["paths"][side] = refs[played]
                    entry["slots"][side] = played
        for side, seat in (seats or {}).items():
            if MOUNT_SIDES[side] in entry["paths"] and side in entry["paths"]:
                entry.setdefault("seats", {})[side] = seat_track(exporter, entry["paths"][MOUNT_SIDES[side]], *seat)
        slots.append(entry)
    sides = [{"key": "rider", "label": "Rider" if mount_set else "Unit", "color": RIDER_COLOUR,
              "model": exporter.model(rider_variant, exporter.anims[slots[0]["anims"]["rider"]]["skeleton"])}]
    if mount_set:
        sides.append({"key": "mount", "label": "Mount", "color": MOUNT_COLOUR, "model": exporter.model(mount_variant, mount_set.skeleton) if mount_variant else None})
    if versus:
        _, v_rider_set, v_rider_variant, v_mount_set, v_mount_variant = versus
        v_skeleton = next((exporter.anims[s["anims"]["v_rider"]]["skeleton"] for s in slots if "v_rider" in s["anims"]), v_rider_set.skeleton)
        sides.append({"key": "v_rider", "label": "Vanilla", "color": VANILLA_RIDER_COLOUR, "group": "vanilla", "model": exporter.model(v_rider_variant, v_skeleton)})
        if v_mount_set:
            sides.append({"key": "v_mount", "label": "Vanilla mount", "color": VANILLA_MOUNT_COLOUR, "group": "vanilla",
                          "model": exporter.model(v_mount_variant, v_mount_set.skeleton) if v_mount_variant else None})
    entry = {"name": name, "kind": "unit", "sets": [rider_set.name] + ([mount_set.name] if mount_set else []), "info": info, "sides": sides, "slots": slots}
    if versus:
        entry["versus"] = versus[0]
    exporter.entries.append(entry)
    print(f"{name}: {len(slots)} slots")
    return entry


def mount_parts(mount_key: str, tables: Dict[str, List[Dict[str, str]]], sets: Dict[str, AnimSet]) -> Tuple[AnimSet, str]:
    """The animation set and variant of a `mounts_tables` key.

    Args:
        mount_key (str): Mount key, e.g. `wh_main_emp_mnt_pegasus`.
        tables (Dict[str, List[Dict[str, str]]]): Vanilla tables, with his own variant rows.
        sets (Dict[str, AnimSet]): Animation sets by name.

    Returns:
        Tuple[AnimSet, str]: The set and the variant path.
    """
    mount = next(r for r in tables["mounts_tables"] if r["key"] == mount_key)
    variant = next(r for r in tables["variants_tables"] if r["variant_name"] == mount["variant"])
    return sets[mount["animation"]], variant_path(variant["variant_filename"])


def vanilla_parts(key: str, tables: Dict[str, List[Dict[str, str]]], sets: Dict[str, AnimSet], variants: Dict[str, Dict[str, str]]) -> Tuple[
        Dict[str, str], AnimSet, str, Optional[AnimSet], Optional[str]]:
    """A vanilla unit's land unit row, rider set and variant, and mount set and variant.

    Args:
        key (str): The vanilla unit key.
        tables (Dict[str, List[Dict[str, str]]]): Vanilla tables.
        sets (Dict[str, AnimSet]): Animation sets by name.
        variants (Dict[str, Dict[str, str]]): `variants_tables` rows by variant name.

    Returns:
        Tuple[Dict[str, str], AnimSet, str, Optional[AnimSet], Optional[str]]: The row, rider set, rider variant path, mount set and mount variant path.
    """
    row = next(r for r in tables["land_units_tables"] if r["key"] == key)
    variant_name = next(r["variant"] for r in tables["unit_variants_tables"] if r["unit"] == key)
    mount_set, mount_variant = mount_parts(row["mount"], tables, sets) if row["mount"] else (None, None)
    return row, sets[row["man_animation"]], variant_path(variants[variant_name]["variant_filename"]), mount_set, mount_variant


def look_entries(exporter: Exporter, registry: Dict, foot: Tuple[AnimSet, str], mounted: Tuple[str, AnimSet, str, AnimSet, str]) -> Optional[str]:
    """Adds his default look on foot and mounted, and the same look with the hoodless head.

    Args:
        exporter (Exporter): The exporter.
        registry (Dict): The units registry.
        foot (Tuple[AnimSet, str]): His foot set and foot variant mesh definition (local file).
        mounted (Tuple[str, AnimSet, str, AnimSet, str]): A mounted pair's mount name, rider set, rider variant, mount set and mount variant.

    Returns:
        Optional[str]: The hoodless variant file, or None when his head has no hoodless model.
    """
    foot_set, foot_variant = foot
    unit_entry(exporter, "Advisor (default)", foot_set, foot_variant, None, None, [f"variant {foot_variant}", f"rider set {foot_set.name}"], LOOK_SLOTS)
    mount_name, rider_set, rider_variant, mount_set, mount_variant = mounted
    unit_entry(exporter, f"Advisor (default) - {mount_name}", rider_set, rider_variant, mount_set, mount_variant,
               [f"variant {rider_variant}", f"rider set {rider_set.name}", f"mount set {mount_set.name}"], LOOK_MOUNTED_SLOTS)
    head = registry["model"]["heads"][registry["model"]["head"]]
    if "hoodless" in head:
        os.makedirs(LOOK_VARIANTS, exist_ok=True)
        variant = os.path.join(LOOK_VARIANTS, "advisor_overhaul_hoodless.variantmeshdefinition")
        with open(variant, "w", encoding="utf-8", newline="\n") as f:
            f.write(open(foot_variant, encoding="utf-8").read().replace(f'model="{head["hooded"][0]}"', f'model="{head["hoodless"][0]}"'))
        unit_entry(exporter, "Advisor hoodless", foot_set, variant, None, None, [f"head {head['hoodless'][0]}", f"rider set {foot_set.name}"], LOOK_SLOTS)
        return variant
    return None


def advisor_entry(exporter: Exporter) -> None:
    """Adds the vanilla campaign Advisor on his own skeleton.

    Args:
        exporter (Exporter): The exporter.
    """
    slots = [{"slot": slot, "anims": {"rider": exporter.anim(path)}, "paths": {"rider": path}, "slots": {"rider": slot}} for slot, path in ADVISOR_ANIMS.items()]
    sides = [{"key": "rider", "label": "Unit", "color": RIDER_COLOUR, "model": exporter.model(ADVISOR_VARIANT, ADVISOR_SKELETON)}]
    exporter.entries.append({"name": "Vanilla: campaign Advisor (advisor01)", "kind": "unit", "sets": [], "sides": sides, "slots": slots,
                             "info": [f"variant {ADVISOR_VARIANT}", f"skeleton {ADVISOR_SKELETON}"]})
    print(f"Vanilla: campaign Advisor (advisor01): {len(slots)} slots")


def portrait_data(exporter: Exporter, registry: Dict, hooded: str, hoodless: Optional[str]) -> None:
    """Sets the portrait preview data: his looks and the vanilla reference on humanoid01, the porthole idle animation and the camera values.

    Args:
        exporter (Exporter): The exporter.
        registry (Dict): The units registry.
        hooded (str): His default variant.
        hoodless (Optional[str]): His hoodless variant, if any.
    """
    looks = [{"name": "Hooded", "model": exporter.model(hooded, "humanoid01")}]
    if hoodless:
        looks.append({"name": "Hoodless", "model": exporter.model(hoodless, "humanoid01")})
    vanilla = json.load(open(DATA, encoding="utf-8"))["portraits"]["portholes"]
    variant = variant_path(vanilla["variants"][0]["filename"])
    camera = {field: vanilla["camera_settings_head"][field] for field in CAMERA_FIELDS}
    reference = {"name": PORTRAIT_REFERENCE_LABEL, "art_set": vanilla["id"], "model": exporter.model(variant, "humanoid01"), "camera": camera}
    exporter.portrait = {"anim": exporter.anim(PORTHOLE_ANIM), "anim_path": PORTHOLE_ANIM, "camera": registry["portrait"]["camera_head"],
                         "looks": [look for look in looks if look["model"]], "reference": reference if reference["model"] else None,
                         "rounds": [{"camera": camera, "note": note} for camera, note in PORTRAIT_ROUNDS]}
    print(f"portrait: {len(exporter.portrait['looks'])} looks, reference {'yes' if reference['model'] else 'missing'}")


def build(out: str) -> Exporter:
    """Exports every gallery entry.

    Args:
        out (str): Output folder.

    Returns:
        Exporter: The exporter, already written.
    """
    registry = load_registry()
    tables = vanilla_tables()
    # His variants are rows of his own, and so are his dragon riders' rider rows.
    for table in ("variants_tables", JUNCTIONS):
        tables[table] = read_table(MOD, table) + tables[table]
    sets = load_sets()
    land_units = {r["key"]: r for r in read_table(MOD, "land_units_tables")}
    uniforms = {r["uniform_name"]: r for r in read_table(MOD, "agent_uniforms_tables")}
    variants = {r["variant_name"]: r for r in tables["variants_tables"]}
    packs = [os.path.join(VANILLA_DATA_DIR, p) for p in ANIM_PACKS]
    exporter = Exporter(out, AssetSource([MOD] + ([PREVIEWS] if os.path.isdir(PREVIEWS) else []), packs))
    exporter.panels, versus, editor = build_panels(registry, out, sets)
    exporter.extra["editor"] = editor

    def pair_variant(weapon: str, mount: str) -> str:
        return variant_path(variants[uniforms[uniform_key(weapon, mount)]["battle_filename"]]["variant_filename"])

    foot_key, mounted_key = unit_key(DEFAULT_WEAPON, DEFAULT_MOUNT), unit_key(DEFAULT_WEAPON, LOOK_MOUNT)
    mount_set, mount_variant = mount_parts(land_units[mounted_key]["mount"], tables, sets)
    hoodless = look_entries(exporter, registry, (sets[land_units[foot_key]["man_animation"]], pair_variant(DEFAULT_WEAPON, DEFAULT_MOUNT)),
                            (registry["mounts"][LOOK_MOUNT]["name"], sets[land_units[mounted_key]["man_animation"]], pair_variant(DEFAULT_WEAPON, LOOK_MOUNT),
                             mount_set, mount_variant))

    for weapon, mount in pairs(registry):
        key = unit_key(weapon, mount)
        row = land_units[key]
        set_name = row["man_animation"]
        if set_name != registry["weapons"][weapon]["sets"][mount]:
            print(f"warning: {key} land unit plays {set_name}, registry says {registry['weapons'][weapon]['sets'][mount]}")
        variant = variants[uniforms[uniform_key(weapon, mount)]["battle_filename"]]["variant_filename"]
        mount_set, mount_variant = mount_parts(row["mount"], tables, sets) if row["mount"] else (None, None)
        name = f"{registry['weapons'][weapon]['name']} - {registry['mounts'][mount]['name']}"
        info = [f"unit {key}", f"rider set {set_name}", f"variant {variant}"] + ([f"mount {row['mount']} ({mount_set.name})"] if mount_set else [])
        seats = {"rider": rider_seat(exporter, key, sets[set_name], row["mount"], tables)} if mount_set else {}
        v_key, v_parts = versus.get(key), None
        if v_key:
            v_row, *v_sides = vanilla_parts(v_key, tables, sets, variants)
            v_parts = (v_key, *v_sides)
            seats["v_rider"] = rider_seat(exporter, v_key, v_sides[0], v_row["mount"], tables) if v_row["mount"] else None
        unit_entry(exporter, name, sets[set_name], variant_path(variant), mount_set, mount_variant, info, versus=v_parts,
                   seats={side: seat for side, seat in seats.items() if seat})["unit"] = key

    advisor_entry(exporter)
    exporter.tuning = {name: registry["model"].get(name, {}) for name in PROP_CHANGES}
    exporter.tuning["hand_shift"] = registry["model"]["hand_shift"]
    portrait_data(exporter, registry, pair_variant(DEFAULT_WEAPON, DEFAULT_MOUNT), hoodless)
    for variant in sorted(glob.glob(os.path.join(PREVIEWS, "*.variantmeshdefinition"))):
        name = os.path.basename(variant)[:-len(".variantmeshdefinition")]
        unit_entry(exporter, f"Preview: {name}", sets[land_units[foot_key]["man_animation"]], variant, None, None, [f"preview variant {variant}"], LOOK_SLOTS)

    for key, name in REFERENCE_UNITS.items():
        row, rider_set, variant, mount_set, mount_variant = vanilla_parts(key, tables, sets, variants)
        info = [f"unit {key}", f"rider set {row['man_animation']}", f"variant {variant}"] + ([f"mount {row['mount']} ({mount_set.name})"] if mount_set else [])
        unit_entry(exporter, name, rider_set, variant, mount_set, mount_variant, info)

    # One comparison per retargeted set, shown on the first pair that plays it.
    for target_set, (source_set, *_) in anims.SETS.items():
        name, source_variant = COMPARE_SOURCES.get(source_set, (f"Retarget: {source_set} vs {target_set}", None))
        target_variant = next((pair_variant(w, m) for w, m in pairs(registry) if registry["weapons"][w]["sets"][m] == target_set), None)
        entry = compare_entry(exporter, name, sets[source_set], sets[target_set], {"source": source_variant, "target": target_variant}, skip=COMPARE_SKIP)
        print(f"{entry['name']}: {len(entry['slots'])} slots")
    exporter.write()
    return exporter


def main() -> int:
    """Exports the gallery.

    Returns:
        int: Process exit code.
    """
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--out", default="./_diag/anim_viewer_next")
    build(parser.parse_args().out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
