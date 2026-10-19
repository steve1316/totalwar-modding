"""Builds the Advisor Overhaul's custom animation sets into the mod's animpack. There are two kinds.

Retargeted sets copy a vanilla set from another human skeleton onto the advisor's `humanoid01`. The first one is the Disc of Tzeentch: vanilla
has no humanoid01 disc rider, so the Chaos Sorcerer Lord's humanoid01c disc set is copied. Every animation the set plays is retargeted with
`tools.anim_retarget`, and so is every animation its `.anm.meta` files splice in. Metas that splice a source animation are copied and pointed at
the retargeted copy, or the game layers the source skeleton's animation over the advisor (his staff then stops spinning while he casts).
Metas with no spliced animation keep their vanilla path. The second is the Glaive, Taoyan's humanoid01e trident set. `FILL_SLOTS` gives it
Settra's casts, which she lacks, `PROP_PINS` holds her sword, scabbard and glaive where her docking would have them, and `BAKED_DOCKING` bakes
the docks into the tracks. The third is the Iron Hand, Zhao Ming's unarmed humanoid01e human form set with his own casts. The fourth is the
bow on the Carmine Dragon, the High Elf princess's humanoid01b dragon set, and the staff on it. `MOUNTS` points the dragon sets at the carmine
dragon's animations. The rest give the Glaive Boris Todbringer's horse set, and the Greatsword, Glaive and bow the disc, with `PROP_PINS` holding
each weapon where his own sets hold it.

Derived sets copy a vanilla `humanoid01` set, or one built before, under a new name with up to two fixes. Named slots take their animations from
another vanilla set (several vanilla horse sets play foot casts in their rider cast slots, so the rider sinks into the mount, and the Huntsmarshal's
short casts are bow tricks). And for the shield sets, the cast animations, which are staff-and-sword ones that put the shield on his back, get copies that hold the
shield on his left hand the way his stand does.

`ADDED_SLOTS` then gives the staff sets the fire slots of his staff bolt, GLF Battle Mage style: each fire slot copies a forward-facing cast whose
meta has a `FIRE_POS`, plus a combat-ready stance where the set has none.

`CAMPAIGN_SETS` retargets vanilla campaign sets for the campaign map, e.g. Taoyan's for the Glaive and Zhao Ming's for the Iron Hand.

The vanilla files come through `core.asset_source`, which caches pack listings and extracts.

Usage:
    python -m generators.advisor_overhaul_anims
"""

import copy
import os
import re
import shutil
import struct
import sys
from dataclasses import replace
from typing import Callable, Dict, List, Optional, Tuple

from core.asset_source import AssetSource, norm
from tools.anim_file import Animation, read_anim, write_anim
from tools.anim_retarget import Transform, compose, relative, retarget, world_pose
from tools.anim_viewer.docking import DOCK_POINTS, apply_docking, set_docking
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

# Folder for the new sets' animations.
DERIVED_FOLDER = "animations/battle/humanoid01/advisor_overhaul"

# New set name -> (vanilla source set, source skeleton, folder for the retargeted animations, file name prefix).
SETS = {
    "hu1_advisor_overhaul_disc01_staff_and_sword": ("hu1c_wh3_dlc20_tzeentch_sorcerer_wm_disc01_staff_sword", "humanoid01c", f"{DERIVED_FOLDER}/disc_staff_and_sword",
                                                    "aod"),
    "hu1_advisor_overhaul_glaive": ("hu1e_cp1_taoyan_trident", "humanoid01e", f"{DERIVED_FOLDER}/glaive", "aog"),
    # Zhao Ming's human form. He fights unarmed and has his own casts, so the set copies as it is.
    "hu1_advisor_overhaul_iron_hand": ("hu1e_mage_iron_dragon", "humanoid01e", f"{DERIVED_FOLDER}/iron_hand", "aoz"),
    # The High Elf princess's dragon set. It holds the bow and arrow in the same props as his bow kit (`be_prop_3` left, `be_prop_4` right).
    "hu1_advisor_overhaul_dr1_dragon_sword_and_bow": ("hu1b_elf_dr1_dragon_wb_sword_and_bow", "humanoid01b", f"{DERIVED_FOLDER}/dr1_dragon_sword_and_bow",
                                                      "aodb"),
    # The High Elf staff dragon set. It holds the sword and staff in the same props as his staff kit (`be_prop_1` right, `be_prop_5` left).
    "hu1_advisor_overhaul_dr1_dragon_staff_and_sword": ("hu1b_elf_dr1_dragon_wb_staff_and_sword", "humanoid01b", f"{DERIVED_FOLDER}/dr1_dragon_staff_and_sword",
                                                        "aodz"),
    # Boris Todbringer's Kislev glaive horse set. It holds the glaive in `be_prop_1`, as his Glaive kit does.
    "hu1_advisor_overhaul_hr1_warhorse_glaive": ("hu1c_wh3_boris_hr1_warhorse_glaive", "humanoid01c", f"{DERIVED_FOLDER}/hr1_warhorse_glaive", "aogh"),
    # The Tzeentch Exalted Hero's two-handed halberd disc set, for the Greatsword and the Glaive on the disc. Vanilla has no other two-handed disc rider.
    "hu1_advisor_overhaul_disc01_two_handed": ("hu1m_dlc24_exalted_hero_tzeentch_wm_disc01_2h_halberd", "humanoid01m", f"{DERIVED_FOLDER}/disc_two_handed", "aodt"),
    # A second copy of the sorcerer's disc set for the bow. Vanilla has no disc archer, so the bow is held in his left hand and shot like the staff bolt.
    "hu1_advisor_overhaul_disc01_sword_and_bow": ("hu1c_wh3_dlc20_tzeentch_sorcerer_wm_disc01_staff_sword", "humanoid01c", f"{DERIVED_FOLDER}/disc_sword_and_bow",
                                                  "aodw"),
}

# Source skeleton -> its bones that humanoid01 names differently. Humanoid01e's `weapon_1` to `weapon_6` are humanoid01's `be_prop_0` to `be_prop_5`,
# in the same order the docking metadata counts props in (prop 3 is `weapon_3` on one and `be_prop_2` on the other).
BONE_RENAMES = {
    "humanoid01e": {**{f"weapon_{i + 1}": f"be_prop_{i}" for i in range(6)}, "head_0": "head", "jaw_0": "jaw", "eyebrows_0": "eyebrow",
                    "shoulderpad_left_0": "shoulder_pad_left", "shoulderpad_right_0": "shoulder_pad_right"},
}

# Every set casts with `CAST_SPELL_*` on foot and `RIDER_CAST_SPELL_*` when mounted.
FOOT_CASTS = r"^CAST_SPELL_"
RIDER_CASTS = r"^RIDER_CAST_SPELL_"

# The staff-and-sword horse set. Its rider casts are proper seated ones (`hu1_hr1_sfsw_rider1_cast_*`), unlike the foot casts several vanilla
# rider sets play, so it donates them to every derived horse set.
HORSE_CAST_DONOR = "hu1_empire_hr1_warhorse_staff_and_sword"

# Every vanilla humanoid01 pegasus rider flies with the same `hu1_hr1_sps_rider1_fly_*` animations whatever he holds, and the rest of a pegasus set
# is its horse set. So a pegasus set is his horse set for that weapon plus these flying slots.
PEGASUS_FLY_DONOR = "hu1_empire_hr1_pegasus_staff_and_sword"
PEGASUS_FLY = r"^RIDER_FLY_"

# Set name -> (the set that gives it the slots it lacks, regex of the slots it gives). The giving set is a vanilla humanoid01 set or one
# built before it. Taoyan casts no spells, so her set has no casts, and Settra's halberd set gives them. Chosen 2026-10-17: the rest of the Glaive
# stays pure Taoyan, so only the casts come over.
FILL_SLOTS = {
    "hu1_advisor_overhaul_glaive": ("hu1_settra_2handed_halberd", FOOT_CASTS),
    # The princess's dragon set has only two rider casts, both a seated horse cast, so the other four are his seated horse casts too.
    "hu1_advisor_overhaul_dr1_dragon_sword_and_bow": (HORSE_CAST_DONOR, RIDER_CASTS),
    # Boris casts no spells.
    "hu1_advisor_overhaul_hr1_warhorse_glaive": (HORSE_CAST_DONOR, RIDER_CASTS),
    # The Exalted Hero has only the three forward casts, so the up casts are the sorcerer's disc ones.
    "hu1_advisor_overhaul_disc01_two_handed": ("hu1_advisor_overhaul_disc01_staff_and_sword", FOOT_CASTS),
    "hu1_advisor_overhaul_hr1_pegasus_sword_and_bow": (PEGASUS_FLY_DONOR, PEGASUS_FLY),
    "hu1_advisor_overhaul_hr1_pegasus_greatsword": (PEGASUS_FLY_DONOR, PEGASUS_FLY),
    "hu1_advisor_overhaul_hr1_pegasus_glaive": (PEGASUS_FLY_DONOR, PEGASUS_FLY),
}

# Set name -> the mount animation it rides with, for a set copied from a rider of another mount. Each vanilla dragon rider set names its own dragon.
MOUNTS = {
    "hu1_advisor_overhaul_dr1_dragon_sword_and_shield": "dr1_dragon_carmine",
    "hu1_advisor_overhaul_dr1_dragon_sword_and_bow": "dr1_dragon_carmine",
    "hu1_advisor_overhaul_dr1_dragon_staff_and_sword": "dr1_dragon_carmine",
    "hu1_advisor_overhaul_hr1_pegasus_sword_and_bow": "hr1_pegasus",
    "hu1_advisor_overhaul_hr1_pegasus_greatsword": "hr1_pegasus",
    "hu1_advisor_overhaul_hr1_pegasus_glaive": "hr1_pegasus",
}

# Taoyan's sword and scabbard, held to the hip where her right waist dock has them.
TAOYAN_HIP = {prop: DOCK_POINTS["RWAIST"] for prop in ("be_prop_2", "be_prop_3")}
# The same, for sets of other riders: the offsets come from his Glaive set's own right waist dock pose.
GLAIVE_HIP = {prop: (f"hu1_advisor_overhaul_glaive:{pose}", anchor) for prop, (pose, anchor) in TAOYAN_HIP.items()}

# Every slot but the dock poses and the persistent metadata.
ALL_POSES = r"^(?!DOCK_EQUIPMENT_|PERSISTENT_METADATA_)"

# Set name -> list of (slot regex, `grips`, `pins`, folder, file name prefix). Each matching slot plays a copy of its animation with props held, and a
# copy of its meta pointed at the copy:
# - `grips`: prop -> (the bone whose place it takes in the first frame, the bone it is then held to).
# - `pins`: prop -> (the slot whose first frame gives its offset, the bone it is held to). A slot of another set is named `set:SLOT`.
# Settra's casts are the staff-and-sword ones with his halberd slung on his back. The Glaive's copies put the polearm where the staff starts, in his
# left hand, and keep it there: the staff twirls in his fingers, which a long blade turns into a jitter. Both models lie centred along the same axis.
# His casts also turn the persistent docks off, which would leave Taoyan's sword and scabbard on his props, so they stay at the hip.
# Taoyan's ladder dismount (shared with the Jade Warriors) leaves the polearm's track behind and relies on her persistent right hand dock, which
# holds her own polearm bone, so the copy holds the glaive to the right hand as that dock would.
# Every disc cast throws the staff up to spin above him, which suits a spell but not a bolt from the staff, so `FIRE_LEVEL` keeps it in his hand.
# Boris holds his sword and scabbard in his left hand, so on the Glaive's horse they stay at the hip too.
# The Exalted Hero's halberd sits far from his hand, so each two-handed weapon is held to his right hand as in its own stand, and the bow on the
# disc to his left hand as in his bow's shooting stance.
PROP_PINS = {
    "hu1_advisor_overhaul_glaive": [
        (r"^CAST_SPELL_", {"be_prop_1": ("be_prop_5", "hand_left")}, TAOYAN_HIP, f"{DERIVED_FOLDER}/glaive/casts", "aogc"),
        (r"^CLIMB_OFF_LADDER_WALL$", {}, {"be_prop_1": DOCK_POINTS["RHAND"]}, f"{DERIVED_FOLDER}/glaive/climbs", "aogk"),
    ],
    "hu1_advisor_overhaul_disc01_staff_and_sword": [
        (r"^FIRE_LEVEL$", {}, {"be_prop_5": ("STAND", "hand_left")}, f"{DERIVED_FOLDER}/disc_staff_and_sword/fire", "aodf"),
    ],
    "hu1_advisor_overhaul_hr1_warhorse_glaive": [(ALL_POSES, {}, GLAIVE_HIP, f"{DERIVED_FOLDER}/hr1_warhorse_glaive/held", "aoghh")],
    "hu1_advisor_overhaul_disc01_two_handed": [
        (ALL_POSES, {}, {"be_prop_0": ("hu1_dlc29_walach_harkon_2handed_sword:STAND", "hand_right"), "be_prop_1": ("hu1_advisor_overhaul_glaive:STAND", "hand_right"),
                         **GLAIVE_HIP}, f"{DERIVED_FOLDER}/disc_two_handed/held", "aodth"),
    ],
    "hu1_advisor_overhaul_disc01_sword_and_bow": [
        (ALL_POSES, {}, {"be_prop_3": ("hu1_huntsmarshal_sword_bow:SHOOT_READY", "hand_left")}, f"{DERIVED_FOLDER}/disc_sword_and_bow/held", "aodwh"),
    ],
}

# Set name -> (folder, file name prefix) for the copies of vanilla animations its docking is baked into. Taoyan's glaive, sword and scabbard ride on
# her set's docks and their raw tracks wander, so the tracks get the docks baked in and look the same whether or not the game docks them.
BAKED_DOCKING = {"hu1_advisor_overhaul_glaive": (f"{DERIVED_FOLDER}/glaive/docked", "aogd")}

# Folder of campaign set files inside packs.
CAMPAIGN_SET_FOLDER = "animations/campaign/database/bin"

# New campaign set -> (vanilla campaign set, its skeleton, folder for the retargeted animations, file name prefix). Taoyan's campaign animations hold
# her glaive, sword and scabbard in their tracks and her campaign persistent meta docks nothing, so a plain retarget plays as she does.
CAMPAIGN_SETS = {
    "cam_hu1_advisor_overhaul_glaive": ("cam_hero_hu1e_cp1_taoyan_trident", "humanoid01e", f"{DERIVED_FOLDER}/glaive_campaign", "aogm"),
    "cam_hu1_advisor_overhaul_iron_hand": ("cam_hu1e_mage_iron_dragon", "humanoid01e", f"{DERIVED_FOLDER}/iron_hand_campaign", "aozm"),
    "cam_hu1_advisor_overhaul_dr1_dragon_staff_and_sword": ("cam_lord_hu1b_elf_dr1_dragon_wb_staff_and_sword", "humanoid01b",
                                                            f"{DERIVED_FOLDER}/dr1_dragon_staff_and_sword_campaign", "aodc"),
}

# The shield and the bone it is held to. In vanilla shield animations the shield moves with this bone to within 2 mm.
SHIELD_PIN = {"be_prop_2": "hand_left"}

# New set name -> how it is made:
# - `base`: the vanilla set it copies, or one built before it.
# - `donor` and `donor_slots`: a vanilla set and a regex of the slot names it replaces.
# - `pins`: prop bone -> the bone it is held to in the cast slots (`PIN_SLOTS`).
# - `folder` and `prefix`: where the pinned animations go and the prefix marking them. Sets that pin nothing need neither.
# - `stand`: the slot whose first frame gives the pin offsets, when it is not `RIDER_STAND` (mounted) or `STAND` (on foot).
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
    # Every vanilla pegasus rider set is its horse set plus the generic `RIDER_FLY_*` slots, so these copy his own horse sets and `FILL_SLOTS` adds those.
    "hu1_advisor_overhaul_hr1_pegasus_sword_and_bow": {"base": "hu1_advisor_overhaul_hr1_warhorse_sword_and_bow"},
    "hu1_advisor_overhaul_hr1_pegasus_greatsword": {"base": "hu1_advisor_overhaul_hr1_warhorse_greatsword"},
    "hu1_advisor_overhaul_hr1_pegasus_glaive": {"base": "hu1_advisor_overhaul_hr1_warhorse_glaive"},
    # Mannfred's zombie dragon set plays standing foot casts in its rider cast slots, which Elspeth's own dragon set does not, so all six are his seated
    # horse casts. Its `RIDER_STAND` is empty and it sits in `STAND`.
    "hu1_advisor_overhaul_dr1_dragon_sword_and_shield": {"base": "hu1_vampire_counts_dr1_zombie_dragon_wb_sword_and_shield", "donor": HORSE_CAST_DONOR,
                                                         "donor_slots": RIDER_CASTS, "pins": SHIELD_PIN, "stand": "STAND",
                                                         "folder": f"{DERIVED_FOLDER}/dr1_dragon_sword_and_shield", "prefix": "aosd"},
}

# The staff bolt's rider fire slots, all playing his seated staff cast `hu1_hr1_sfsw_rider1_cast_up_short` with its vanilla meta (`FIRE_POS` at 1.0 s
# of 4.0 s). GLF Battle Mage fires from the same horse sets with this cast. The slot list is GLF's: the four `RIDER_FIRE_*` directions and the two
# turns. The combat-ready stance is added in case the set lacks one.
RIDER_SHOTS = [(slot, "RIDER_CAST_SPELL_UP_SHORT") for slot in ("RIDER_FIRE_FORWARD_LEVEL", "RIDER_FIRE_LEFT_LEVEL", "RIDER_FIRE_RIGHT_LEVEL",
                                                                "RIDER_FIRE_BACK_LEVEL", "RIDER_SHOOT_TURN_LEFT_90", "RIDER_SHOOT_TURN_RIGHT_90")]
RIDER_FIRE = RIDER_SHOTS + [("RIDER_COMBAT_READY", "RIDER_STAND")]

# The staff bolt on the disc: `FIRE_LEVEL` plays his forward short cast (its retargeted meta has `FIRE_POS` at 1.0 s of 4.0 s), as GLF does for the
# vanilla disc sorcerer. The disc set has no combat-ready stance, and a fire slot without one leaves him in a T-pose after the shot.
DISC_FIRE = [("FIRE_LEVEL", "CAST_SPELL_FORWARD_SHORT"), ("COMBAT_READY", "STAND"), ("FLY_COMBAT_READY", "FLY_STAND")]

# The staff bolt on the dragon fires from the rider slots, as the High Elf dragon bow set does. The staff dragon set sits in `STAND` and has no
# combat-ready stance of either kind.
DRAGON_FIRE = RIDER_SHOTS + [("COMBAT_READY", "STAND"), ("RIDER_COMBAT_READY", "STAND")]

# Set name -> (new slot, the slot of the same set it copies), added when the set lacks the new slot. The on-foot staff set needs none: vanilla
# `hu1_pr8_amethyst_staff_and_sword` already has `FIRE_LEVEL` (`hu1_sfsw_aim_fire_stand_01`, `FIRE_POS` at 0.9 s of 2.2 s) and `COMBAT_READY`.
# The bow on the disc has no vanilla shot to copy, so it fires like the staff bolt.
ADDED_SLOTS = {
    "hu1_advisor_overhaul_disc01_staff_and_sword": DISC_FIRE,
    "hu1_advisor_overhaul_disc01_sword_and_bow": DISC_FIRE,
    "hu1_advisor_overhaul_hr1_warhorse_staff_and_sword": RIDER_FIRE,
    "hu1_advisor_overhaul_hr1_pegasus_staff_and_sword": RIDER_FIRE,
    "hu1_advisor_overhaul_dr1_dragon_staff_and_sword": DRAGON_FIRE,
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
    if name.startswith("hu") and "_" in name:
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
    files = assets.fetch(anims + skeletons + metas)
    missing = [path for path in anims + skeletons if norm(path) not in files]
    if missing:
        raise SystemExit(f"not in any searched pack: {', '.join(missing)}")
    # Some vanilla slots name a meta no pack has, such as Taoyan's docking ones. The game skips those, so they keep their vanilla path.
    meta_data = {m: files[norm(m)] for m in metas if norm(m) in files}
    spliced = sorted({p.decode() for data in meta_data.values() for p in ANIM_PATH.findall(data)} - set(anims))
    files.update(assets.fetch_all(spliced))

    def load(path: str) -> Animation:
        return read_anim(files[norm(path)])

    source_bind, target_bind = load(skeletons[0]), load(skeletons[1])
    renames = BONE_RENAMES.get(source_skeleton)
    retargeted = {path: write_anim(retarget(load(path), source_bind, target_bind, TARGET_SKELETON, renames=renames)) for path in anims + spliced}
    new = copy.deepcopy(source)
    new.name, new.skeleton = name, TARGET_SKELETON
    copied = write_copies(name, retargeted, meta_data, folder, prefix, new.slots)
    print(f"{name}: {len(new.slots)} slots, {len(anims)} animations + {len(spliced)} spliced retargeted, {copied} metas repointed")
    return write_set(new)


def hold_props(anim: Animation, skeleton: Animation, holds: Dict[str, Tuple[str, Transform]]) -> None:
    """Holds props at fixed offsets from their anchor bones in every frame. No anchor may be one of the props.

    Args:
        anim (Animation): The animation, changed in place.
        skeleton (Animation): The skeleton's bind pose.
        holds (Dict[str, Tuple[str, Transform]]): Prop bone, e.g. `be_prop_2` -> (the bone it is held to, its transform relative to that bone).

    Raises:
        SystemExit: When the animation's bones are not the skeleton's.
    """
    if [b.name for b in anim.bones] != [b.name for b in skeleton.bones]:
        raise SystemExit(f"{anim.skeleton} animation bones differ from the skeleton's")
    index = {bone.name: i for i, bone in enumerate(anim.bones)}
    held = [(index[prop], index[anchor], offset) for prop, (anchor, offset) in holds.items()]
    for frame in range(len(anim.rotations)):
        world = world_pose(anim, skeleton, frame)
        for prop, anchor, offset in held:
            parent = anim.bones[prop].parent
            pinned = compose(world[anchor], offset)
            anim.rotations[frame][prop], anim.translations[frame][prop] = relative(world[parent], pinned) if parent >= 0 else pinned


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
    stand = spec.get("stand") or ("RIDER_STAND" if new.mount else "STAND")
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
        hold_props(anim, skeleton, {prop: (anchor, offsets[prop]) for prop, anchor in pins.items()})
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


def fill_slots(data: bytes, donor_data: bytes, pattern: str, names: Dict[int, str]) -> bytes:
    """Adds every matching slot the donor set plays and the set does not, as the donor has it. An empty slot of the set is replaced.

    Args:
        data (bytes): The set `.bin`.
        donor_data (bytes): The donor set `.bin`.
        pattern (str): Regex of the slot names to fill.
        names (Dict[int, str]): Slot names by id.

    Returns:
        bytes: The changed set `.bin`.
    """
    anim_set = parse_set(data)
    present = {slot.slot_id for slot in anim_set.slots if slot.refs}
    added = [slot for slot in parse_set(donor_data).slots if slot.refs and slot.slot_id not in present and re.match(pattern, names.get(slot.slot_id, ""))]
    filled = {slot.slot_id for slot in added}
    anim_set.slots = [slot for slot in anim_set.slots if slot.refs or slot.slot_id not in filled] + added
    print(f"{anim_set.name}: filled {len(added)} {pattern} slots from the donor")
    return write_set(anim_set)


def read_files(paths: List[str], assets: AssetSource) -> Callable[[str], Optional[bytes]]:
    """Reads game files in one go. Files the mod folder has win, the rest come from the vanilla packs.

    Args:
        paths (List[str]): Game paths.
        assets (AssetSource): The vanilla packs.

    Returns:
        Callable[[str], Optional[bytes]]: Reads one of the paths, None when no pack has it.
    """
    local = {p: open(os.path.join(MOD, p), "rb").read() for p in set(paths) if os.path.exists(os.path.join(MOD, p))}
    vanilla = assets.fetch(sorted(set(paths) - set(local)))
    return lambda path: local[path] if path in local else vanilla.get(norm(path))


def pin_props(data: bytes, pattern: str, grips: Dict[str, Tuple[str, str]], pins: Dict[str, Tuple[str, str]], folder: str, prefix: str, names: Dict[int, str],
              sets: Dict[str, bytes], assets: AssetSource) -> bytes:
    """Points the matching slots at copies of their animations with props held, and at copies of their metas pointed at them.

    Args:
        data (bytes): The set `.bin`.
        pattern (str): Regex of the slot names to change.
        grips (Dict[str, Tuple[str, str]]): Prop bone -> (the bone whose place it takes in the first frame, the bone it is held to).
        pins (Dict[str, Tuple[str, str]]): Prop bone -> (the slot whose first frame gives its offset, the bone it is held to). `set:SLOT` names another set's slot.
        folder (str): Output folder for the copies, relative to the mod folder.
        prefix (str): Short prefix marking the copies.
        names (Dict[int, str]): Slot names by id.
        sets (Dict[str, bytes]): Set `.bin` files by set name, for poses of other sets.
        assets (AssetSource): The vanilla packs, for files the mod folder lacks.

    Returns:
        bytes: The changed set `.bin`.

    Raises:
        SystemExit: When no slot matches or a slot giving an offset is missing.
    """
    anim_set = parse_set(data)
    slots = [slot for slot in anim_set.slots if slot.refs and re.match(pattern, names.get(slot.slot_id, ""))]

    def first_anim(pose: str) -> Optional[str]:
        set_name, _, slot = pose.rpartition(":")
        source = parse_set(sets[set_name]).slots if set_name else anim_set.slots
        return next((s.refs[0].anim for s in source if s.refs and names.get(s.slot_id) == slot), None)

    poses = {pose: first_anim(pose) for pose, _ in pins.values()}
    missing = sorted(pose for pose, anim in poses.items() if anim is None)
    if not slots or missing:
        raise SystemExit(f"{anim_set.name}: no {pattern} slot or no {', '.join(missing)} to pin to")

    skeleton_path = f"animations/skeletons/{TARGET_SKELETON}.anim"
    anims = sorted({r.anim for slot in slots for r in slot.refs if r.anim})
    metas = sorted({r.meta for slot in slots for r in slot.refs if r.meta})
    read = read_files([skeleton_path, *anims, *metas, *poses.values()], assets)
    skeleton = read_anim(read(skeleton_path))
    index = {bone.name: i for i, bone in enumerate(skeleton.bones)}
    pose_worlds = {pose: world_pose(read_anim(read(anim)), skeleton, 0) for pose, anim in poses.items()}
    pinned = {prop: (anchor, relative(pose_worlds[pose][index[anchor]], pose_worlds[pose][index[prop]])) for prop, (pose, anchor) in pins.items()}
    moved: Dict[str, bytes] = {}
    for path in anims:
        anim = read_anim(read(path))
        first = world_pose(anim, skeleton, 0) if grips else None
        gripped = {prop: (hand, relative(first[index[hand]], first[index[leader]])) for prop, (leader, hand) in grips.items()}
        hold_props(anim, skeleton, {**gripped, **pinned})
        moved[path] = write_anim(anim)
    # Some vanilla slots name a meta that no pack has, e.g. Taoyan's ladder dismount.
    copied = write_copies(anim_set.name, moved, {m: read(m) for m in metas if read(m)}, folder, prefix, slots)
    held = [f"{prop} held to {hand} where {leader} starts" for prop, (leader, hand) in grips.items()] + [f"{p} held to {a} as in {pose}" for p, (pose, a) in pins.items()]
    print(f"{anim_set.name}: {len(moved)} {pattern} animations with {', '.join(held)}, {copied} metas repointed")
    return write_set(anim_set)


def bake_docking(data: bytes, folder: str, prefix: str, names: Dict[int, str], assets: AssetSource) -> bytes:
    """Bakes the set's equipment docking into its animations, so the props sit where the docks hold them even when the game does not dock them.
    Animations in the mod folder are changed in place, vanilla ones get copies the slots are pointed at.

    Args:
        data (bytes): The set `.bin`.
        folder (str): Output folder for the vanilla animations' copies, relative to the mod folder.
        prefix (str): Short prefix marking the copies.
        names (Dict[int, str]): Slot names by id.
        assets (AssetSource): The vanilla packs, for files the mod folder lacks.

    Returns:
        bytes: The changed set `.bin`.

    Raises:
        SystemExit: When the set docks nothing.
    """
    anim_set = parse_set(data)
    skeleton_path = f"animations/skeletons/{TARGET_SKELETON}.anim"
    read = read_files([skeleton_path] + [path for slot in anim_set.slots for r in slot.refs for path in (r.anim, r.meta) if path], assets)
    docking = set_docking(anim_set, names, read)
    if docking is None:
        raise SystemExit(f"{anim_set.name}: no docks to bake")
    skeleton = read_anim(read(skeleton_path))
    # The dock poses and the persistent slot stay as they are, since the poses give the docks their offsets.
    slots = [slot for slot in anim_set.slots if slot.refs and not names.get(slot.slot_id, "").startswith(("DOCK_EQUIPMENT_", "PERSISTENT_METADATA_"))]
    in_place, copies = 0, {}
    for path in sorted({r.anim for slot in slots for r in slot.refs if r.anim}):
        anim = read_anim(read(path))
        if not apply_docking(anim, path, docking, lambda pose: read_anim(read(pose)), skeleton):
            continue
        if os.path.exists(os.path.join(MOD, path)):
            with open(os.path.join(MOD, path), "wb") as f:
                f.write(write_anim(anim))
            in_place += 1
        else:
            copies[path] = write_anim(anim)
    metas = sorted({r.meta for slot in slots for r in slot.refs if r.meta and r.anim in copies})
    copied = write_copies(anim_set.name, copies, {m: read(m) for m in metas if read(m)}, folder, prefix, [s for s in slots if any(r.anim in copies for r in s.refs)])
    print(f"{anim_set.name}: docking baked into {in_place} animations in place and {len(copies)} copies, {copied} metas repointed")
    return write_set(anim_set)


def split_campaign_set(data: bytes) -> Tuple[bytes, List[str]]:
    """Splits a campaign set `.bin`, which `parse_set()` does not read, into its slot block and its strings. The second u32 is the length of the
    block after it, which names strings by their number, and u16-length-prefixed strings fill the rest of the file.

    Args:
        data (bytes): The campaign set `.bin`.

    Returns:
        Tuple[bytes, List[str]]: Everything before the strings, and the strings in order.

    Raises:
        SystemExit: When the strings do not end with the file.
    """
    head_end = 4 + struct.unpack_from("<I", data, 4)[0]
    strings, offset = [], head_end
    while offset + 2 <= len(data):
        length = struct.unpack_from("<H", data, offset)[0]
        strings.append(data[offset + 2:offset + 2 + length].decode())
        offset += 2 + length
    if offset != len(data):
        raise SystemExit(f"campaign set strings end at byte {offset} of {len(data)}")
    return data[:head_end], strings


def build_campaign_set(name: str, source: str, source_skeleton: str, folder: str, prefix: str, assets: AssetSource) -> None:
    """Retargets one vanilla campaign set and writes it and its animations into the mod folder. Its metas keep their vanilla paths.

    Args:
        name (str): The new set's name.
        source (str): The vanilla campaign set.
        source_skeleton (str): The vanilla set's skeleton.
        folder (str): Output folder for the retargeted animations, relative to the mod folder.
        prefix (str): Short prefix marking the copies.
        assets (AssetSource): The vanilla packs.

    Raises:
        SystemExit: When a file is missing or two animations map to the same file name.
    """
    source_path = f"{CAMPAIGN_SET_FOLDER}/{source}.bin"
    skeletons = [f"animations/skeletons/{source_skeleton}.anim", f"animations/skeletons/{TARGET_SKELETON}.anim"]
    data = assets.fetch([source_path]).get(norm(source_path))
    if data is None:
        raise SystemExit(f"{name}: {source_path} is not in any searched pack")
    head, strings = split_campaign_set(data)
    anims = sorted({s for s in strings if s.endswith(".anim")})
    files = assets.fetch(anims + skeletons)
    missing = [path for path in anims + skeletons if norm(path) not in files]
    if missing:
        raise SystemExit(f"not in any searched pack: {', '.join(missing)}")
    source_bind, target_bind = (read_anim(files[norm(path)]) for path in skeletons)
    renamed = {path: renamed_path(path, folder, prefix) for path in anims}
    if len(set(renamed.values())) != len(renamed):
        raise SystemExit(f"{name}: two animations map to the same file name")
    os.makedirs(os.path.join(MOD, folder), exist_ok=True)
    for path, copy_path in renamed.items():
        anim = retarget(read_anim(files[norm(path)]), source_bind, target_bind, TARGET_SKELETON, renames=BONE_RENAMES.get(source_skeleton))
        with open(os.path.join(MOD, copy_path), "wb") as f:
            f.write(write_anim(anim))
    swaps = {**renamed, source: name, source_skeleton: TARGET_SKELETON}
    os.makedirs(os.path.join(MOD, CAMPAIGN_SET_FOLDER), exist_ok=True)
    with open(os.path.join(MOD, CAMPAIGN_SET_FOLDER, f"{name}.bin"), "wb") as f:
        f.write(head + b"".join(pack_string(swaps.get(s, s)) for s in strings))
    print(f"{name}: {len(anims)} animations of {source} retargeted")


def with_mount(name: str, data: bytes) -> bytes:
    """Points a set at the mount animation `MOUNTS` gives it. Sets with none are returned as they are.

    Args:
        name (str): The set's name.
        data (bytes): The set `.bin`.

    Returns:
        bytes: The set `.bin`.
    """
    if name not in MOUNTS:
        return data
    anim_set = parse_set(data)
    anim_set.mount = MOUNTS[name]
    return write_set(anim_set)


def build() -> None:
    """Builds every set in `SETS` and `DERIVED_SETS` into the mod's animpack, and every set in `CAMPAIGN_SETS`."""
    vanilla = {os.path.basename(path)[:-4]: data for path, data in load_vanilla_sets().items() if path.startswith(SET_FOLDER) and path.endswith(".bin")}
    names = load_slot_ids(open(f"{SCHEMAS_DIR}/{SLOT_IDS_FILE}", encoding="utf-8").read())
    assets = AssetSource([], [], VANILLA_PACKS)
    # Sets built so far, so later sets can copy, fill from or pin to them.
    sets = dict(vanilla)
    entries = []

    def finish(name: str, data: bytes) -> None:
        if name in FILL_SLOTS:
            donor, pattern = FILL_SLOTS[name]
            data = fill_slots(data, sets[donor], pattern, names)
        if name in ADDED_SLOTS:
            data = add_slots(data, ADDED_SLOTS[name], names)
        for spec in PROP_PINS.get(name, []):
            data = pin_props(data, *spec, names, sets, assets)
        if name in BAKED_DOCKING:
            data = bake_docking(data, *BAKED_DOCKING[name], names, assets)
        sets[name] = with_mount(name, data)
        entries.append((f"{SET_FOLDER}/{name}.bin", sets[name]))

    for name, (source, skeleton, folder, prefix) in SETS.items():
        shutil.rmtree(os.path.join(MOD, folder), ignore_errors=True)
        finish(name, build_set(name, vanilla[source], skeleton, folder, prefix, assets))
    for name, spec in DERIVED_SETS.items():
        if spec.get("folder"):
            shutil.rmtree(os.path.join(MOD, spec["folder"]), ignore_errors=True)
        finish(name, build_derived(name, spec, sets, assets, names))
    os.makedirs(os.path.dirname(os.path.join(MOD, ANIMPACK)), exist_ok=True)
    with open(os.path.join(MOD, ANIMPACK), "wb") as f:
        f.write(write_animpack(entries))
    print(f"wrote {len(entries)} sets to {ANIMPACK}")
    shutil.rmtree(os.path.join(MOD, CAMPAIGN_SET_FOLDER), ignore_errors=True)
    for name, (source, skeleton, folder, prefix) in CAMPAIGN_SETS.items():
        shutil.rmtree(os.path.join(MOD, folder), ignore_errors=True)
        build_campaign_set(name, source, skeleton, folder, prefix, assets)


if __name__ == "__main__":
    build()
    sys.exit(0)
