"""Builds the Advisor Overhaul's custom animation sets into the mod's animpack. There are two kinds.

Retargeted sets copy a vanilla set from another human skeleton onto the advisor's `humanoid01`. The first one is the Disc of Tzeentch: vanilla
has no humanoid01 disc rider, so the Chaos Sorcerer Lord's humanoid01c disc set is copied. Every animation the set plays is retargeted with
`tools.anim_retarget`, and so is every animation its `.anm.meta` files splice in. Metas that splice a source animation are copied and pointed at
the retargeted copy, or the game layers the source skeleton's animation over the advisor (his staff then stops spinning while he casts).
Metas with no spliced animation keep their vanilla path.

Derived sets copy a vanilla `humanoid01` set under a new name with two fixes. Named slots take their animations from another vanilla set (vanilla's
sword-and-shield horse sets play foot casts in their rider cast slots, so the rider sinks into the mount). And the cast animations, which are
staff-and-sword ones that put the shield on his back, get copies that hold the shield on his left hand the way his stand does.

The vanilla files come through `core.asset_source`, which caches pack listings and extracts.

Usage:
    python -m generators.advisor_overhaul_anims
"""

import copy
import os
import re
import shutil
import sys
from typing import Dict, List

from core.asset_source import AssetSource, norm
from tools.anim_file import Animation, read_anim, write_anim
from tools.anim_retarget import Transform, compose, relative, retarget, world_pose
from tools.glf_rebuild_animpack import (SCHEMAS_DIR, SLOT_IDS_FILE, AnimRef, Slot, load_slot_ids, load_vanilla_sets, pack_string, parse_set, write_animpack,
                                        write_set)

# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Settings

# The mod source folder.
MOD = "../warhammer3_mods/!!advisor_overhaul"

# The vanilla packs holding the animations, metas and skeletons, first match wins: anim.pack, anim2.pack, anim_3.pack and data.pack.
VANILLA_PACKS = re.compile(r"^(anim.*|data)\.pack$")

# The animpack every new set goes into, relative to the mod folder.
ANIMPACK = "animations/database/battle/bin/advisor_overhaul.animpack"

# Folder of animation set files inside packs.
SET_FOLDER = "animations/database/battle/bin"

# The advisor's skeleton.
TARGET_SKELETON = "humanoid01"

# New set name -> (vanilla source set, source skeleton, folder for the retargeted animations, file name prefix).
SETS = {
    "hu1_advisor_overhaul_disc01_staff_and_sword": ("hu1c_wh3_dlc20_tzeentch_sorcerer_wm_disc01_staff_sword", "humanoid01c",
                                                    "animations/battle/humanoid01/advisor_overhaul/disc_staff_and_sword", "aod"),
}

# Folder for the derived sets' animations.
DERIVED_FOLDER = "animations/battle/humanoid01/advisor_overhaul"

# New set name -> (vanilla base set, vanilla donor set for `DONOR_SLOTS` or None, folder for the pinned animations, file name prefix).
DERIVED_SETS = {
    "hu1_advisor_overhaul_sword_and_shield": ("hu1_empire_sword_and_shield", None, f"{DERIVED_FOLDER}/sword_and_shield", "aos"),
    "hu1_advisor_overhaul_hr1_warhorse_sword_and_shield": ("hu1_empire_hr1_warhorse_sword_and_shield", "hu1_empire_hr1_warhorse_staff_and_sword",
                                                           f"{DERIVED_FOLDER}/hr1_warhorse_sword_and_shield", "aosw"),
    "hu1_advisor_overhaul_hr1_pegasus_sword_and_shield": ("hu1_empire_hr1_pegasus_sword_and_shield", "hu1_empire_hr1_pegasus_staff_and_sword",
                                                          f"{DERIVED_FOLDER}/hr1_pegasus_sword_and_shield", "aosp"),
}

# Slots a derived set takes from its donor set.
DONOR_SLOTS = re.compile(r"^RIDER_CAST_SPELL_")

# Slots whose animations get the pinned prop.
PIN_SLOTS = re.compile(r"^(RIDER_)?CAST_SPELL_")

# The pinned prop (the shield) and the bone it is held to. In vanilla shield animations the shield moves with this bone to within 2 mm.
PIN_PROP = "be_prop_2"
PIN_ANCHOR = "hand_left"

# Paths of `.anim` files named inside a meta.
ANIM_PATH = re.compile(rb"animations/[\w/\.-]+?\.anim")


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Build


def renamed_path(path: str, folder: str, prefix: str) -> str:
    """Where a retargeted animation goes.

    Args:
        path (str): The source animation path.
        folder (str): The set's output folder.
        prefix (str): Short prefix marking the copy.

    Returns:
        str: The new path, e.g. `.../hu1_aod_tzeentch_..._stand_01.anim`.
    """
    name = os.path.basename(path)
    skeleton_prefix = name.split("_", 1)[0]
    if skeleton_prefix.startswith("hu"):
        return f"{folder}/hu1_{prefix}_{name.split('_', 1)[1]}"
    return f"{folder}/{prefix}_{name}"


def repoint(data: bytes, renamed: Dict[str, str]) -> bytes:
    """Swaps every length-prefixed source animation path in a meta for its retargeted copy.

    Args:
        data (bytes): The meta file.
        renamed (Dict[str, str]): Source path -> retargeted path.

    Returns:
        bytes: The changed meta.
    """
    for old, new in renamed.items():
        data = data.replace(pack_string(old), pack_string(new))
    return data


def write_copies(name: str, anims: Dict[str, bytes], metas: Dict[str, bytes], folder: str, prefix: str, slots: List[Slot]) -> int:
    """Writes a new set's animations into the mod folder, copies each meta that splices one of them with the path pointed at the copy, and points
    the slots at the copies.

    Args:
        name (str): The new set's name, for errors.
        anims (Dict[str, bytes]): Source animation path -> the new animation file.
        metas (Dict[str, bytes]): Meta path -> the vanilla meta file, for every meta the slots name.
        folder (str): Output folder, relative to the mod folder.
        prefix (str): Short prefix marking the copies.
        slots (List[Slot]): The slots whose references are pointed at the copies, changed in place.

    Returns:
        int: How many metas were copied.

    Raises:
        SystemExit: When two animations map to the same file name.
    """
    renamed: Dict[str, str] = {}
    os.makedirs(os.path.join(MOD, folder), exist_ok=True)
    for path, data in anims.items():
        renamed[path] = renamed_path(path, folder, prefix)
        with open(os.path.join(MOD, renamed[path]), "wb") as f:
            f.write(data)
    if len(set(renamed.values())) != len(renamed):
        raise SystemExit(f"{name}: two animations map to the same file name")

    # Only a meta that splices a copied animation needs a copy. The rest keep their vanilla path.
    new_metas: Dict[str, str] = {}
    for meta, data in metas.items():
        changed = repoint(data, renamed)
        if changed != data:
            new_metas[meta] = f"{folder}/meta/{os.path.basename(meta)}"
            os.makedirs(os.path.join(MOD, folder, "meta"), exist_ok=True)
            with open(os.path.join(MOD, new_metas[meta]), "wb") as f:
                f.write(changed)

    for slot in slots:
        slot.refs = [AnimRef(renamed.get(r.anim, r.anim), new_metas.get(r.meta, r.meta), r.sound) for r in slot.refs]
    return len(new_metas)


def build_set(name: str, source_data: bytes, source_skeleton: str, folder: str, prefix: str, assets: AssetSource) -> bytes:
    """Retargets one vanilla set and writes its animations and metas into the mod folder.

    Args:
        name (str): The new set's name.
        source_data (bytes): The vanilla set `.bin`.
        source_skeleton (str): The vanilla set's skeleton.
        folder (str): Output folder for the retargeted files, relative to the mod folder.
        prefix (str): Short prefix marking the copies.
        assets (AssetSource): The vanilla packs.

    Returns:
        bytes: The new set `.bin`.
    """
    source = parse_set(source_data)
    anims = sorted({r.anim for slot in source.slots for r in slot.refs if r.anim})
    metas = sorted({r.meta for slot in source.slots for r in slot.refs if r.meta})
    skeletons = [f"animations/skeletons/{source_skeleton}.anim", f"animations/skeletons/{TARGET_SKELETON}.anim"]
    files = assets.fetch_all(anims + metas + skeletons)
    meta_data = {m: files[norm(m)] for m in metas}
    spliced = sorted({p.decode() for data in meta_data.values() for p in ANIM_PATH.findall(data)} - set(anims))
    files.update(assets.fetch_all(spliced))

    def load(path: str) -> Animation:
        return read_anim(files[norm(path)])

    source_bind, target_bind = load(skeletons[0]), load(skeletons[1])
    retargeted = {path: write_anim(retarget(load(path), source_bind, target_bind, TARGET_SKELETON)) for path in anims + spliced}
    new = copy.deepcopy(source)
    new.name, new.skeleton = name, TARGET_SKELETON
    copied = write_copies(name, retargeted, meta_data, folder, prefix, new.slots)
    print(f"{name}: {len(new.slots)} slots, {len(anims)} animations + {len(spliced)} spliced retargeted, {copied} metas repointed")
    return write_set(new)


def pin_prop(anim: Animation, skeleton: Animation, offset: Transform) -> None:
    """Holds `PIN_PROP` at a fixed offset from `PIN_ANCHOR` in every frame.

    Args:
        anim (Animation): The animation, changed in place.
        skeleton (Animation): The skeleton's bind pose.
        offset (Transform): The prop's transform relative to the anchor bone.

    Raises:
        SystemExit: When the animation's bones are not the skeleton's.
    """
    if [b.name for b in anim.bones] != [b.name for b in skeleton.bones]:
        raise SystemExit(f"{anim.skeleton} animation bones differ from the skeleton's")
    index = {bone.name: i for i, bone in enumerate(anim.bones)}
    prop, anchor = index[PIN_PROP], index[PIN_ANCHOR]
    parent = anim.bones[prop].parent
    for frame in range(len(anim.rotations)):
        world = world_pose(anim, skeleton, frame)
        pinned = compose(world[anchor], offset)
        local = relative(world[parent], pinned) if parent >= 0 else pinned
        anim.rotations[frame][prop], anim.translations[frame][prop] = local


def build_derived(name: str, base_data: bytes, donor_data: bytes, folder: str, prefix: str, assets: AssetSource, names: Dict[int, str]) -> bytes:
    """Copies a vanilla set, swaps in the donor's slots and pins the prop in its cast animations, writing the new animations into the mod folder.

    Args:
        name (str): The new set's name.
        base_data (bytes): The vanilla set `.bin` to copy.
        donor_data (bytes): The vanilla set `.bin` whose `DONOR_SLOTS` replace the base's, or empty for none.
        folder (str): Output folder for the pinned animations, relative to the mod folder.
        prefix (str): Short prefix marking the copies.
        assets (AssetSource): The vanilla packs.
        names (Dict[int, str]): Slot names by id.

    Returns:
        bytes: The new set `.bin`.

    Raises:
        SystemExit: When the donor lacks a slot or the set has no stand animation.
    """
    new = parse_set(base_data)
    new.name = name

    def slot_name(slot) -> str:
        return names.get(slot.slot_id, "")

    # Donor slots keep the base's blend, weight and weapon states. Only what they play changes.
    swapped = 0
    if donor_data:
        donor: Dict[str, List[AnimRef]] = {}
        for slot in parse_set(donor_data).slots:
            if slot.refs:
                donor.setdefault(slot_name(slot), slot.refs)
        for slot in new.slots:
            if DONOR_SLOTS.match(slot_name(slot)):
                if slot_name(slot) not in donor:
                    raise SystemExit(f"{name}: donor set has no {slot_name(slot)}")
                slot.refs = list(donor[slot_name(slot)])
                swapped += 1

    # The prop's offset from its anchor in the first frame of the stand animation.
    stand = "RIDER_STAND" if new.mount else "STAND"
    reference = next((s.refs[0].anim for s in new.slots if slot_name(s) == stand and s.refs), None)
    if reference is None:
        raise SystemExit(f"{name}: no {stand} animation")
    pinned_slots = [slot for slot in new.slots if PIN_SLOTS.match(slot_name(slot))]
    anims = sorted({r.anim for slot in pinned_slots for r in slot.refs if r.anim})
    metas = sorted({r.meta for slot in pinned_slots for r in slot.refs if r.meta})
    skeleton_path = f"animations/skeletons/{TARGET_SKELETON}.anim"
    files = assets.fetch_all(sorted(set(anims + metas + [reference, skeleton_path])))

    def load(path: str) -> Animation:
        return read_anim(files[norm(path)])

    skeleton = load(skeleton_path)
    stand_world = world_pose(load(reference), skeleton, 0)
    index = {bone.name: i for i, bone in enumerate(skeleton.bones)}
    offset = relative(stand_world[index[PIN_ANCHOR]], stand_world[index[PIN_PROP]])

    pinned: Dict[str, bytes] = {}
    for path in anims:
        anim = load(path)
        pin_prop(anim, skeleton, offset)
        pinned[path] = write_anim(anim)
    copied = write_copies(name, pinned, {m: files[norm(m)] for m in metas}, folder, prefix, pinned_slots)
    print(f"{name}: {len(new.slots)} slots, {swapped} from the donor, {len(anims)} animations pinned to {PIN_ANCHOR}, {copied} metas repointed")
    return write_set(new)


def build() -> None:
    """Builds every set in `SETS` and `DERIVED_SETS` into the mod's animpack."""
    vanilla = {os.path.basename(path)[:-4]: data for path, data in load_vanilla_sets().items() if path.startswith(SET_FOLDER) and path.endswith(".bin")}
    names = load_slot_ids(open(f"{SCHEMAS_DIR}/{SLOT_IDS_FILE}", encoding="utf-8").read())
    assets = AssetSource([], [], VANILLA_PACKS)
    entries = []
    for name, (source, skeleton, folder, prefix) in SETS.items():
        shutil.rmtree(os.path.join(MOD, folder), ignore_errors=True)
        data = build_set(name, vanilla[source], skeleton, folder, prefix, assets)
        entries.append((f"{SET_FOLDER}/{name}.bin", data))
    for name, (base, donor, folder, prefix) in DERIVED_SETS.items():
        shutil.rmtree(os.path.join(MOD, folder), ignore_errors=True)
        data = build_derived(name, vanilla[base], vanilla[donor] if donor else b"", folder, prefix, assets, names)
        entries.append((f"{SET_FOLDER}/{name}.bin", data))
    os.makedirs(os.path.dirname(os.path.join(MOD, ANIMPACK)), exist_ok=True)
    with open(os.path.join(MOD, ANIMPACK), "wb") as f:
        f.write(write_animpack(entries))
    print(f"wrote {len(entries)} sets to {ANIMPACK}")


if __name__ == "__main__":
    build()
    sys.exit(0)
