"""Builds the Advisor Overhaul's custom animation sets into the mod's animpack. There are two kinds.

Retargeted sets copy a vanilla set from another human skeleton onto the advisor's `humanoid01`. The first one is the Disc of Tzeentch: vanilla
has no humanoid01 disc rider, so the Chaos Sorcerer Lord's humanoid01c disc set is copied. Every animation the set plays is retargeted with
`tools.anim_retarget`, and so is every animation its `.anm.meta` files splice in. Metas that splice a source animation are copied and pointed at
the retargeted copy, or the game layers the source skeleton's animation over the advisor (his staff then stops spinning while he casts).
Metas with no spliced animation keep their vanilla path.

Derived sets copy a vanilla `humanoid01` set under a new name with up to two fixes. Named slots take their animations from another vanilla set
(several vanilla horse sets play foot casts in their rider cast slots, so the rider sinks into the mount, and the Huntsmarshal's short casts are bow
tricks). And for the shield sets, the cast animations, which are staff-and-sword ones that put the shield on his back, get copies that hold the
shield on his left hand the way his stand does.

`ADDED_SLOTS` then gives the staff sets the fire slots of his staff bolt, GLF Battle Mage style: each fire slot copies a forward-facing cast whose
meta has a `FIRE_POS`, plus a combat-ready stance where the set has none.

The vanilla files come through `core.asset_source`, which caches pack listings and extracts.

Usage:
    python -m generators.advisor_overhaul_anims
"""

import copy
import os
import re
import shutil
import sys
from dataclasses import replace
from typing import Dict, List, Tuple

from core.asset_source import AssetSource, norm
from tools.anim_file import Animation, read_anim, write_anim
from tools.anim_retarget import Transform, compose, relative, retarget, world_pose
from tools.glf_rebuild_animpack import (ALL_WEAPONS, SCHEMAS_DIR, SLOT_IDS_FILE, AnimRef, Slot, load_slot_ids, load_vanilla_sets, pack_string, parse_set, write_animpack,
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

# Every derived set casts with `CAST_SPELL_*` on foot and `RIDER_CAST_SPELL_*` when mounted.
FOOT_CASTS = r"^CAST_SPELL_"
RIDER_CASTS = r"^RIDER_CAST_SPELL_"

# The staff-and-sword horse set. Its rider casts are proper seated ones (`hu1_hr1_sfsw_rider1_cast_*`), unlike the foot casts several vanilla
# rider sets play, so it donates them to every derived horse set.
HORSE_CAST_DONOR = "hu1_empire_hr1_warhorse_staff_and_sword"

# The shield and the bone it is held to. In vanilla shield animations the shield moves with this bone to within 2 mm.
SHIELD_PIN = {"be_prop_2": "hand_left"}

# New set name -> how it is made:
# - `base`: the vanilla set it copies.
# - `donor` and `donor_slots`: a vanilla set and a regex of the slot names it replaces.
# - `pins`: prop bone -> the bone it is held to in the cast slots (`PIN_SLOTS`).
# - `folder` and `prefix`: where the pinned animations go and the prefix marking them. Sets that pin nothing need neither.
DERIVED_SETS = {
    "hu1_advisor_overhaul_sword_and_shield": {"base": "hu1_empire_sword_and_shield", "pins": SHIELD_PIN, "folder": f"{DERIVED_FOLDER}/sword_and_shield",
                                              "prefix": "aos"},
    "hu1_advisor_overhaul_hr1_warhorse_sword_and_shield": {"base": "hu1_empire_hr1_warhorse_sword_and_shield", "donor": HORSE_CAST_DONOR,
                                                           "donor_slots": RIDER_CASTS, "pins": SHIELD_PIN,
                                                           "folder": f"{DERIVED_FOLDER}/hr1_warhorse_sword_and_shield", "prefix": "aosw"},
    "hu1_advisor_overhaul_hr1_pegasus_sword_and_shield": {"base": "hu1_empire_hr1_pegasus_sword_and_shield", "donor": "hu1_empire_hr1_pegasus_staff_and_sword",
                                                          "donor_slots": RIDER_CASTS, "pins": SHIELD_PIN,
                                                          "folder": f"{DERIVED_FOLDER}/hr1_pegasus_sword_and_shield", "prefix": "aosp"},
    # Walach Harkon's horse set plays a foot cast in `RIDER_CAST_SPELL_UP_SHORT`. The other five are already the donor's.
    "hu1_advisor_overhaul_hr1_warhorse_greatsword": {"base": "hu1_dlc29_hr1_warhorse_walach_2handed_sword", "donor": HORSE_CAST_DONOR,
                                                     "donor_slots": RIDER_CASTS},
    # The Huntsmarshal's short and medium casts are bow tricks (an oil flask and a trick shot), so all six come from the Amethyst Wizard.
    "hu1_advisor_overhaul_sword_and_bow": {"base": "hu1_huntsmarshal_sword_bow", "donor": "hu1_pr8_amethyst_staff_and_sword", "donor_slots": FOOT_CASTS},
    # The Mounted Yeomen's horse set plays foot casts in all six rider cast slots.
    "hu1_advisor_overhaul_hr1_warhorse_sword_and_bow": {"base": "hu1_empire_hr1_warhorse_sword_and_bow", "donor": HORSE_CAST_DONOR, "donor_slots": RIDER_CASTS},
    # The staff-and-sword horse sets as they are, plus the fire slots in `ADDED_SLOTS`.
    "hu1_advisor_overhaul_hr1_warhorse_staff_and_sword": {"base": "hu1_empire_hr1_warhorse_staff_and_sword"},
    "hu1_advisor_overhaul_hr1_pegasus_staff_and_sword": {"base": "hu1_empire_hr1_pegasus_staff_and_sword"},
}

# The staff bolt's rider fire slots, all playing his seated staff cast `hu1_hr1_sfsw_rider1_cast_up_short` with its vanilla meta (`FIRE_POS` at 1.0 s
# of 4.0 s). GLF Battle Mage fires from the same horse sets with this cast. The slot list is GLF's: the four `RIDER_FIRE_*` directions and the two
# turns. The combat-ready stance is added in case the set lacks one.
RIDER_FIRE = [(slot, "RIDER_CAST_SPELL_UP_SHORT") for slot in ("RIDER_FIRE_FORWARD_LEVEL", "RIDER_FIRE_LEFT_LEVEL", "RIDER_FIRE_RIGHT_LEVEL",
                                                               "RIDER_FIRE_BACK_LEVEL", "RIDER_SHOOT_TURN_LEFT_90", "RIDER_SHOOT_TURN_RIGHT_90")]
RIDER_FIRE += [("RIDER_COMBAT_READY", "RIDER_STAND")]

# The staff bolt on the disc: `FIRE_LEVEL` plays his forward short cast (its retargeted meta has `FIRE_POS` at 1.0 s of 4.0 s), as GLF does for the
# vanilla disc sorcerer. The disc set has no combat-ready stance, and a fire slot without one leaves him in a T-pose after the shot.
DISC_FIRE = [("FIRE_LEVEL", "CAST_SPELL_FORWARD_SHORT"), ("COMBAT_READY", "STAND"), ("FLY_COMBAT_READY", "FLY_STAND")]

# Every disc cast throws the staff up to spin above him, which suits a spell but not a bolt from the staff. Set name -> (slot, prop -> anchor bone,
# folder, file name prefix): that slot plays a copy of its animation with the staff held to his left hand at its stand offset, and a copy of its
# meta whose self-splice points at the copy.
FIRE_PINS = {
    "hu1_advisor_overhaul_disc01_staff_and_sword": ("FIRE_LEVEL", {"be_prop_5": "hand_left"},
                                                    "animations/battle/humanoid01/advisor_overhaul/disc_staff_and_sword/fire", "aodf"),
}

# Set name -> (new slot, the slot of the same set it copies), added when the set lacks the new slot. The on-foot staff set needs none: vanilla
# `hu1_pr8_amethyst_staff_and_sword` already has `FIRE_LEVEL` (`hu1_sfsw_aim_fire_stand_01`, `FIRE_POS` at 0.9 s of 2.2 s) and `COMBAT_READY`.
ADDED_SLOTS = {
    "hu1_advisor_overhaul_disc01_staff_and_sword": DISC_FIRE,
    "hu1_advisor_overhaul_hr1_warhorse_staff_and_sword": RIDER_FIRE,
    "hu1_advisor_overhaul_hr1_pegasus_staff_and_sword": RIDER_FIRE,
}

# Fire slots play in every weapon state, as GLF's do.
FIRE_SLOT = re.compile(r"^(FIRE_|RIDER_FIRE_|RIDER_SHOOT_TURN_)")

# Slots whose animations get the pinned props.
PIN_SLOTS = re.compile(r"^(RIDER_)?CAST_SPELL_")

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


def pin_prop(anim: Animation, skeleton: Animation, prop_name: str, anchor_name: str, offset: Transform) -> None:
    """Holds a prop at a fixed offset from its anchor bone in every frame.

    Args:
        anim (Animation): The animation, changed in place.
        skeleton (Animation): The skeleton's bind pose.
        prop_name (str): The prop bone, e.g. `be_prop_2`.
        anchor_name (str): The bone it is held to, e.g. `hand_left`.
        offset (Transform): The prop's transform relative to the anchor bone.

    Raises:
        SystemExit: When the animation's bones are not the skeleton's.
    """
    if [b.name for b in anim.bones] != [b.name for b in skeleton.bones]:
        raise SystemExit(f"{anim.skeleton} animation bones differ from the skeleton's")
    index = {bone.name: i for i, bone in enumerate(anim.bones)}
    prop, anchor = index[prop_name], index[anchor_name]
    parent = anim.bones[prop].parent
    for frame in range(len(anim.rotations)):
        world = world_pose(anim, skeleton, frame)
        pinned = compose(world[anchor], offset)
        local = relative(world[parent], pinned) if parent >= 0 else pinned
        anim.rotations[frame][prop], anim.translations[frame][prop] = local


def build_derived(name: str, spec: Dict, sets: Dict[str, bytes], assets: AssetSource, names: Dict[int, str]) -> bytes:
    """Copies a vanilla set, swaps in the donor's slots and pins props in its cast animations, writing the pinned animations into the mod folder.

    Args:
        name (str): The new set's name.
        spec (Dict): How it is made (see `DERIVED_SETS`).
        sets (Dict[str, bytes]): Vanilla set `.bin` files by set name.
        assets (AssetSource): The vanilla packs.
        names (Dict[int, str]): Slot names by id.

    Returns:
        bytes: The new set `.bin`.

    Raises:
        SystemExit: When the donor lacks a slot or the set has no stand animation.
    """
    new = parse_set(sets[spec["base"]])
    new.name = name
    pins = spec.get("pins", {})

    def slot_name(slot) -> str:
        return names.get(slot.slot_id, "")

    # Donor slots keep the base's blend, weight and weapon states. Only what they play changes.
    swapped = 0
    if spec.get("donor"):
        donor: Dict[str, List[AnimRef]] = {}
        for slot in parse_set(sets[spec["donor"]]).slots:
            if slot.refs:
                donor.setdefault(slot_name(slot), slot.refs)
        for slot in new.slots:
            if re.match(spec["donor_slots"], slot_name(slot)):
                if slot_name(slot) not in donor:
                    raise SystemExit(f"{name}: donor set has no {slot_name(slot)}")
                slot.refs = list(donor[slot_name(slot)])
                swapped += 1
    if not pins:
        print(f"{name}: {len(new.slots)} slots, {swapped} from the donor")
        return write_set(new)

    # Each prop's offset from its anchor in the first frame of the stand animation.
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
    offsets = {prop: relative(stand_world[index[anchor]], stand_world[index[prop]]) for prop, anchor in pins.items()}

    pinned: Dict[str, bytes] = {}
    for path in anims:
        anim = load(path)
        for prop, anchor in pins.items():
            pin_prop(anim, skeleton, prop, anchor, offsets[prop])
        pinned[path] = write_anim(anim)
    copied = write_copies(name, pinned, {m: files[norm(m)] for m in metas}, spec["folder"], spec["prefix"], pinned_slots)
    held = ", ".join(f"{prop} to {anchor}" for prop, anchor in pins.items())
    print(f"{name}: {len(new.slots)} slots, {swapped} from the donor, {len(anims)} animations pinned ({held}), {copied} metas repointed")
    return write_set(new)


def add_slots(data: bytes, pairs: List[Tuple[str, str]], names: Dict[int, str]) -> bytes:
    """Adds each new slot the set lacks as a copy of another slot of the same set. Fire slots play in every weapon state.

    Args:
        data (bytes): The set `.bin`.
        pairs (List[Tuple[str, str]]): (new slot, slot it copies) names.
        names (Dict[int, str]): Slot names by id.

    Returns:
        bytes: The changed set `.bin`.

    Raises:
        SystemExit: When a slot to copy is missing or empty.
    """
    anim_set = parse_set(data)
    ids = {name: slot_id for slot_id, name in names.items()}
    present = {names.get(slot.slot_id, "") for slot in anim_set.slots}
    added = []
    for target, source in pairs:
        if target in present:
            continue
        template = next((slot for slot in anim_set.slots if names.get(slot.slot_id) == source and slot.refs), None)
        if template is None:
            raise SystemExit(f"{anim_set.name}: no {source} to copy into {target}")
        weapons = ALL_WEAPONS if FIRE_SLOT.match(target) else template.weapon_bools
        anim_set.slots.append(replace(template, slot_id=ids[target], weapon_bools=weapons, refs=list(template.refs)))
        present.add(target)
        added.append(target)
    print(f"{anim_set.name}: added {', '.join(added) or 'nothing'}")
    return write_set(anim_set)


def pin_slot(data: bytes, slot_name: str, pins: Dict[str, str], folder: str, prefix: str, names: Dict[int, str], assets: AssetSource) -> bytes:
    """Points one slot at copies of its animation with props pinned to their stand offset, and of its meta pointed at the copy.

    Args:
        data (bytes): The set `.bin`.
        slot_name (str): The slot to change.
        pins (Dict[str, str]): Prop bone -> the bone it is held to.
        folder (str): Output folder for the copies, relative to the mod folder.
        prefix (str): Short prefix marking the copies.
        names (Dict[int, str]): Slot names by id.
        assets (AssetSource): The vanilla packs, for files the mod folder lacks.

    Returns:
        bytes: The changed set `.bin`.

    Raises:
        SystemExit: When the slot or the stand animation is missing.
    """
    anim_set = parse_set(data)
    slot = next((s for s in anim_set.slots if names.get(s.slot_id) == slot_name and s.refs), None)
    stand = next((s.refs[0].anim for s in anim_set.slots if names.get(s.slot_id) == "STAND" and s.refs), None)
    if slot is None or stand is None:
        raise SystemExit(f"{anim_set.name}: no {slot_name} or STAND to pin")
    ref, skeleton_path = slot.refs[0], f"animations/skeletons/{TARGET_SKELETON}.anim"

    def read(path: str) -> bytes:
        local = os.path.join(MOD, path)
        return open(local, "rb").read() if os.path.exists(local) else assets.fetch_all([path])[norm(path)]

    skeleton = read_anim(read(skeleton_path))
    stand_world = world_pose(read_anim(read(stand)), skeleton, 0)
    index = {bone.name: i for i, bone in enumerate(skeleton.bones)}
    anim = read_anim(read(ref.anim))
    for prop, anchor in pins.items():
        pin_prop(anim, skeleton, prop, anchor, relative(stand_world[index[anchor]], stand_world[index[prop]]))
    write_copies(anim_set.name, {ref.anim: write_anim(anim)}, {ref.meta: read(ref.meta)} if ref.meta else {}, folder, prefix, [slot])
    print(f"{anim_set.name}: {slot_name} plays {slot.refs[0].anim} with {', '.join(f'{p} held to {a}' for p, a in pins.items())}")
    return write_set(anim_set)


def build() -> None:
    """Builds every set in `SETS` and `DERIVED_SETS` into the mod's animpack."""
    vanilla = {os.path.basename(path)[:-4]: data for path, data in load_vanilla_sets().items() if path.startswith(SET_FOLDER) and path.endswith(".bin")}
    names = load_slot_ids(open(f"{SCHEMAS_DIR}/{SLOT_IDS_FILE}", encoding="utf-8").read())
    assets = AssetSource([], [], VANILLA_PACKS)
    entries = []
    for name, (source, skeleton, folder, prefix) in SETS.items():
        shutil.rmtree(os.path.join(MOD, folder), ignore_errors=True)
        data = build_set(name, vanilla[source], skeleton, folder, prefix, assets)
        if name in ADDED_SLOTS:
            data = add_slots(data, ADDED_SLOTS[name], names)
        if name in FIRE_PINS:
            data = pin_slot(data, *FIRE_PINS[name], names, assets)
        entries.append((f"{SET_FOLDER}/{name}.bin", data))
    for name, spec in DERIVED_SETS.items():
        if spec.get("folder"):
            shutil.rmtree(os.path.join(MOD, spec["folder"]), ignore_errors=True)
        data = build_derived(name, spec, vanilla, assets, names)
        if name in ADDED_SLOTS:
            data = add_slots(data, ADDED_SLOTS[name], names)
        entries.append((f"{SET_FOLDER}/{name}.bin", data))
    os.makedirs(os.path.dirname(os.path.join(MOD, ANIMPACK)), exist_ok=True)
    with open(os.path.join(MOD, ANIMPACK), "wb") as f:
        f.write(write_animpack(entries))
    print(f"wrote {len(entries)} sets to {ANIMPACK}")


if __name__ == "__main__":
    build()
    sys.exit(0)
