"""Builds the Advisor Overhaul's custom animation sets into the mod's animpack. There are two kinds.

Retargeted sets copy a vanilla set from another human skeleton onto the advisor's `humanoid01`. The first one is the Disc of Tzeentch: vanilla
has no humanoid01 disc rider, so the Chaos Sorcerer Lord's humanoid01c disc set is copied. Every animation the set plays is retargeted with
`tools.anim_retarget`, and so is every animation its `.anm.meta` files splice in. Metas that splice a source animation are copied and pointed at
the retargeted copy, or the game layers the source skeleton's animation over the advisor (his staff then stops spinning while he casts).
Metas that name bones are copied with the bones renumbered for `humanoid01`. Metas with neither keep their vanilla path. The second is the Glaive, Taoyan's humanoid01e trident set. `FILL_SLOTS` gives it
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
import math
import os
import re
import shutil
import struct
import sys
from dataclasses import replace
from typing import Callable, Dict, List, Optional, Tuple

from core.asset_source import AssetSource, norm
from tools.anim_file import Animation, Vec3, read_anim, write_anim
from tools.anim_retarget import Transform, _blend, _qconj, _qmul, _qnorm, compose, relative, retarget, world_pose
from tools.anim_viewer.docking import DOCK_POINTS, PROP_BONE, Dock, apply_docking, dock_offset, read_disables, read_docks, set_docking
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
    # The High Elf halberd horse set. Its right hand dock holds `be_prop_1`, where his Glaive kit has the glaive, as Boris Todbringer holds his.
    # Boris's own set places him from the saddle, which the Empire warhorse and the pegasus ignore (he sat in the ground), so it is not used.
    "hu1_advisor_overhaul_hr1_warhorse_glaive": ("hu1d_elf_hr1_warhorse_halberd", "humanoid01d", f"{DERIVED_FOLDER}/hr1_warhorse_glaive", "aogh"),
    # The Tzeentch Exalted Hero's halberd disc set, for the Greatsword and the Glaive on the disc. Vanilla has no other two-handed disc rider.
    "hu1_advisor_overhaul_disc01_two_handed": ("hu1m_dlc24_exalted_hero_tzeentch_wm_disc01_2h_halberd", "humanoid01m", f"{DERIVED_FOLDER}/disc_two_handed", "aodt"),
}

# Source skeleton -> its bones that humanoid01 names differently. Humanoid01e's `weapon_1` to `weapon_6` are humanoid01's `be_prop_0` to `be_prop_5`,
# in the same order the docking metadata counts props in (prop 3 is `weapon_3` on one and `be_prop_2` on the other).
BONE_RENAMES = {
    "humanoid01e": {**{f"weapon_{i + 1}": f"be_prop_{i}" for i in range(6)}, "head_0": "head", "jaw_0": "jaw", "eyebrows_0": "eyebrow",
                    "shoulderpad_left_0": "shoulder_pad_left", "shoulderpad_right_0": "shoulder_pad_right"},
}

# Meta tags that name bones by index -> where each index sits after the entry's filter string. `SPLICE` also names one, after two strings.
# Each skeleton numbers its bones its own way, so a meta copied from another skeleton gets renumbered to match humanoid01.
BONE_FIELDS = {"TRANSFORM": (0, 4), "DISMEMBER": (0,)}

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

# The lowest the disc bone goes in the disc's own stand. The Exalted Hero's attacks sink it below this, his charge into the ground, so he is raised
# in those frames until it is back at this height.
DISC_FLOOR = 0.45

# Set name -> (the set that gives it the slots it lacks, regex of the slots it gives). The giving set is a vanilla humanoid01 set or one
# built before it. Taoyan casts no spells, so her set has no casts, and Settra's halberd set gives them. Chosen 2026-10-17: the rest of the Glaive
# stays pure Taoyan, so only the casts come over.
FILL_SLOTS = {
    "hu1_advisor_overhaul_glaive": ("hu1_settra_2handed_halberd", FOOT_CASTS),
    # The princess's dragon set has only two rider casts, both a seated horse cast, so the other four are his seated horse casts too.
    "hu1_advisor_overhaul_dr1_dragon_sword_and_bow": (HORSE_CAST_DONOR, RIDER_CASTS),
    # The High Elf halberd rider casts no spells.
    "hu1_advisor_overhaul_hr1_warhorse_glaive": (HORSE_CAST_DONOR, RIDER_CASTS),
    # The Exalted Hero has only the three forward casts, so the up casts are the sorcerer's disc ones.
    "hu1_advisor_overhaul_disc01_two_handed": ("hu1_advisor_overhaul_disc01_staff_and_sword", FOOT_CASTS),
    "hu1_advisor_overhaul_hr1_pegasus_sword_and_bow": (PEGASUS_FLY_DONOR, PEGASUS_FLY),
    "hu1_advisor_overhaul_hr1_pegasus_greatsword": (PEGASUS_FLY_DONOR, PEGASUS_FLY),
    "hu1_advisor_overhaul_hr1_pegasus_glaive": (PEGASUS_FLY_DONOR, PEGASUS_FLY),
}

# Set flag of rider sets that place the rider from the mount's saddle. The other sets place him from the mount's own origin, so their rider animations
# carry the mount's height and motion and float about 1.6 m over the saddle when a saddle set plays them.
SADDLE_SPACE = 256
# Rider slots a saddle set may take from the other kind of set. Copies of those animations are moved into saddle space.
SEATED_SLOTS = r"^RIDER_(CAST_SPELL|FLY)_"
# Of those, the slots where the mount moves under him. In the pegasus's flying animations the rider stays within 3 cm of this bone, so its motion
# in the mount's animation of the same slot is taken out frame by frame.
CARRIED_SLOTS = r"^RIDER_FLY_"
SADDLE_BONE = "spine_1"
# The seated stand every origin-placed humanoid01 rider set shares. Its hips give the saddle's place in those sets.
ORIGIN_SEAT = (HORSE_CAST_DONOR, "RIDER_STAND")
# An origin-placed rider animation starts with his hips at least this far over the saddle set's own stand (1.6 m on a horse).
ORIGIN_HEIGHT = 1.0

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

# Set name -> list of (slot regex, `grips`, `pins`, folder, file name prefix, optional `floor`). Each matching slot plays a copy of its animation
# with props held, and a copy of its meta pointed at the copy:
# - `grips`: prop -> (the bone whose place it takes in the first frame, the bone it is then held to).
# - `pins`: prop -> (the slot whose first frame gives its offset, the bone it is held to). A slot of another set is named `set:SLOT`.
# - `floor`: (bone, height). In frames where the bone is lower, his body and props are raised until it is at that height.
# A slot's weapon bools say which props it shows, bit N for `be_prop_N`, so each matching slot also shows the props it holds.
# Settra's casts are the staff-and-sword ones with his halberd slung on his back. The Glaive's copies put the polearm where the staff starts, in his
# left hand, and keep it there: the staff twirls in his fingers, which a long blade turns into a jitter. Both models lie centred along the same axis.
# His casts also turn the persistent docks off, which would leave Taoyan's sword and scabbard on his props, so they stay at the hip.
# Taoyan's ladder dismount (shared with the Jade Warriors) leaves the polearm's track behind and relies on her persistent right hand dock, which
# holds her own polearm bone, so the copy holds the glaive to the right hand as that dock would.
# Every disc cast throws the staff up to spin above him, which suits a spell but not a bolt from the staff, so `FIRE_LEVEL` keeps it in his hand.
# The High Elf halberd rider rides unarmed between attacks, so on the Glaive's horse the glaive stays in his right hand dock and the sword at the hip.
# The Exalted Hero's halberd sits far from his hand, so each two-handed weapon is held to his right hand as in its own stand. The Glaive on the disc
# holds it in `be_prop_0`, the slot the Exalted Hero's halberd uses, since in `be_prop_1` it vanished in his attacks.
PROP_PINS = {
    "hu1_advisor_overhaul_glaive": [
        (r"^CAST_SPELL_", {"be_prop_1": ("be_prop_5", "hand_left")}, TAOYAN_HIP, f"{DERIVED_FOLDER}/glaive/casts", "aogc"),
        (r"^CLIMB_OFF_LADDER_WALL$", {}, {"be_prop_1": DOCK_POINTS["RHAND"]}, f"{DERIVED_FOLDER}/glaive/climbs", "aogk"),
    ],
    "hu1_advisor_overhaul_disc01_staff_and_sword": [
        (r"^FIRE_LEVEL$", {}, {"be_prop_5": ("STAND", "hand_left")}, f"{DERIVED_FOLDER}/disc_staff_and_sword/fire", "aodf"),
    ],
    "hu1_advisor_overhaul_hr1_warhorse_glaive": [
        (ALL_POSES, {}, {"be_prop_1": DOCK_POINTS["RHAND"], **GLAIVE_HIP}, f"{DERIVED_FOLDER}/hr1_warhorse_glaive/held", "aoghh"),
    ],
    "hu1_advisor_overhaul_disc01_two_handed": [
        (ALL_POSES, {}, {"be_prop_0": ("hu1_dlc29_walach_harkon_2handed_sword:STAND", "hand_right"), "be_prop_1": ("hu1_advisor_overhaul_glaive:STAND", "hand_right"),
                         **GLAIVE_HIP}, f"{DERIVED_FOLDER}/disc_two_handed/held", "aodth", ("be_prop_4", DISC_FLOOR)),
    ],
    "hu1_advisor_overhaul_disc01_glaive": [(ALL_POSES, {"be_prop_0": ("be_prop_1", "hand_right")}, {}, f"{DERIVED_FOLDER}/disc_glaive", "aodg")],
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
    # Every vanilla pegasus rider set is its horse set plus the generic `RIDER_FLY_*` slots, so these copy his horse sets and `FILL_SLOTS` adds those.
    "hu1_advisor_overhaul_hr1_pegasus_sword_and_bow": {"base": "hu1_advisor_overhaul_hr1_warhorse_sword_and_bow"},
    "hu1_advisor_overhaul_hr1_pegasus_greatsword": {"base": "hu1_advisor_overhaul_hr1_warhorse_greatsword"},
    "hu1_advisor_overhaul_hr1_pegasus_glaive": {"base": "hu1_advisor_overhaul_hr1_warhorse_glaive"},
    # The two-handed disc set with the glaive moved from `be_prop_1` to `be_prop_0` (`PROP_PINS`).
    "hu1_advisor_overhaul_disc01_glaive": {"base": "hu1_advisor_overhaul_disc01_two_handed"},
    # Mannfred's zombie dragon set plays standing foot casts in its rider cast slots, which Elspeth's dragon set does not, so all six are his seated
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
ADDED_SLOTS = {
    "hu1_advisor_overhaul_disc01_staff_and_sword": DISC_FIRE,
    "hu1_advisor_overhaul_hr1_warhorse_staff_and_sword": RIDER_FIRE,
    "hu1_advisor_overhaul_hr1_pegasus_staff_and_sword": RIDER_FIRE,
    "hu1_advisor_overhaul_dr1_dragon_staff_and_sword": DRAGON_FIRE,
}

# Fire slots copied from a cast play in every weapon state, as GLF's do. One copied from a bow shot keeps the shot's own states, or the shot can
# end in his sword state with the bow put away on his back.
FIRE_SLOT = re.compile(r"^(FIRE_|RIDER_FIRE_|RIDER_SHOOT_TURN_)")

# Slots whose animations get the pinned props.
PIN_SLOTS = re.compile(r"^(RIDER_)?CAST_SPELL_")

# Paths of `.anim` files named inside a meta.
ANIM_PATH = re.compile(rb"animations/[\w/\.-]+?\.anim")

# Bow disc set -> (the disc set whose moves it plays, his foot bow set whose shots it adds, folder, file name prefix). He stands on the disc as the
# Greatsword does, and each shot keeps that set's legs, disc and hunch under the bow's arms, so drawing the bow does not straighten him up. One
# entity, like the vanilla Herald of Tzeentch, who shoots from his disc. Chosen 2026-10-19.
BOW_DISCS = {"hu1_advisor_overhaul_disc01_sword_and_bow": ("hu1_advisor_overhaul_disc01_two_handed", "hu1_advisor_overhaul_sword_and_bow",
                                                           f"{DERIVED_FOLDER}/disc01_sword_and_bow", "aodsb")}
# The bow set's shots, aims and changes into them. The disc set has none of them.
BOW_SHOTS = r"^(SHOOT_|AIM_|FIRE_|MOVING_FIRE_)|_TO_(SHOOT|AIM)_"
# The disc set's resting slots, which hold the bow ready instead of the sword. In the air he rests in `FLY_IDLE_*` between shots, so with the sword
# there he swapped weapons after every shot. Melee slots keep the sword. Chosen 2026-10-19.
DISC_BOW_RESTS = r"^(STAND|STAND_IDLE_\d|FLY_IDLE_\d|WALK_\d|RUN_\d|STEP_\w+|TURN_\w+)$"
# The disc moves from `be_prop_4`, where his bow set holds the arrow, to this bone.
DISC_MOVE = ("be_prop_4", "be_prop_5")
# In the disc set's moves the sword is in his right hand and the bow on his back, held as his bow set's dock poses hold them: prop -> (dock point,
# prop number in the docks).
DISC_BOW_DOCKS = {"be_prop_1": ("RHAND", 2), "be_prop_3": ("BACK", 4)}
# A shot takes this bone and every bone under it (his chest, arms and head) from the bow set. The rest (hips, legs, lower back and disc) comes from
# the disc set's slot `shot_legs()` names.
UPPER_BODY = "spine_1"
# A shot's props keep their place on the nearest of these bones: a hand holding it, the hips for the sword at his side, or his chest for the bow
# on his back.
PROP_ANCHORS = ("hand_left", "hand_right", "root", "spine_2")
# These bones turn as in the disc set, plus the bow's turn away from its `SHOOT_READY` start, so his back keeps the disc stance's hunch.
HUNCH_BONES = ("spine_1", "spine_2")
# His chest turns so this shoulder line faces as in the bow shot, since the disc stance turns his hips sideways and would turn the aim with them.
SHOULDERS = ("upperarm_left", "upperarm_right")
# Meta entries baked into a shot's animation and cut from its meta: whole-body poses spliced in at ground height, and docks, which would use the
# disc set's dock poses.
BAKED_ENTRIES = re.compile(r"^(SPLICE|DOCK_EQPT_\w+)$")
# The game plays a moving shot over his current move. Without an override the disc came from the shot and his legs from the move, so in flight
# the disc bobbed out of step with his feet. Chosen 2026-10-19: these shots get a `SPLICE_OVERRIDE`, as the vanilla Herald of Tzeentch disc's do.
MOVING_SHOTS = r"^MOVING_FIRE_"
# Its weights for the generic bone, neck, torso, left arm, right arm and legs. They match the Herald's but for the left arm, which holds his book at
# 0.5 and here raises the bow. Generic and legs stay 0, so his legs and the disc keep the move under him.
MOVING_SPLICE_WEIGHTS = (0.0, 0.7, 1.0, 1.0, 1.0, 0.0)
# That splice takes every prop bone from the move, so the shot's animated bow on `be_prop_3` stayed with the move and vanished (tested 2026-10-19).
# A moving shot hangs each animated prop off the hand holding it instead, as the Herald's book hangs off his forearm. An `ANIMATED_PROP` v14 ends
# with its position, orientation, scale, bone, attach method, replaced prop and blend in and out times, laid out as AssetEditor's `Prop_v14`.
ANIMATED_PROP_TAIL = 52
# The first four of those, read and written in place.
ANIMATED_PROP_PLACE = "<3f4ffi"
# A meta entry starts with its tag as a length-prefixed upper case string, then a small version number.
META_ENTRY = re.compile(rb"(?=([\x04-\x28])\x00([A-Z][A-Z0-9_]{3,39}))")


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


def renumber_bones(data: bytes, bones: List[Optional[int]]) -> bytes:
    """Points a meta's bone fields at the target skeleton's numbering and drops entries on bones the target lacks. A bone of -1 means every bone.

    Args:
        data (bytes): The meta file, numbered for the source skeleton.
        bones (List[Optional[int]]): Source bone index -> the target's index of the same bone, or None when the target has no such bone.

    Returns:
        bytes: The renumbered meta.
    """
    entries = meta_entries(data)
    out, kept = bytearray(data[:8]), 0
    for i, (offset, tag) in enumerate(entries):
        entry = bytearray(data[offset:entries[i + 1][0] if i + 1 < len(entries) else len(data)])
        at = entry_body(data, offset, tag)[2] - offset
        if tag == "SPLICE":
            # The bone follows the spliced animation's path and one more string.
            for _ in range(2):
                at += 2 + struct.unpack_from("<H", entry, at)[0]
            fields = [at]
        else:
            fields = [at + field for field in BONE_FIELDS.get(tag, ())]
        targets = [struct.unpack_from("<i", entry, field)[0] for field in fields]
        if any(bone >= len(bones) or (bone >= 0 and bones[bone] is None) for bone in targets):
            continue
        for field, bone in zip(fields, targets):
            if bone >= 0:
                struct.pack_into("<i", entry, field, bones[bone])
        out += entry
        kept += 1
    struct.pack_into("<I", out, 4, kept)
    return bytes(out)


def write_copies(name: str, anims: Dict[str, bytes], metas: Dict[str, bytes], folder: str, prefix: str, slots: List[Slot],
                 bones: Optional[List[Optional[int]]] = None) -> int:
    """Writes a new set's animations into the mod folder, copies each meta that splices one of them with the path pointed at the copy, and points
    the slots at the copies.

    Args:
        name (str): The new set's name, for errors.
        anims (Dict[str, bytes]): Source animation path -> the new animation file.
        metas (Dict[str, bytes]): Meta path -> the vanilla meta file, for every meta the slots name.
        folder (str): Output folder, relative to the mod folder.
        prefix (str): Short prefix marking the copies.
        slots (List[Slot]): The slots whose references are pointed at the copies, changed in place.
        bones (Optional[List[Optional[int]]]): For metas from another skeleton, its bone index -> the advisor's, as `renumber_bones` takes it.

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

    # Only a meta that splices a copied animation or names a renumbered bone needs a copy. The rest keep their vanilla path.
    new_metas: Dict[str, str] = {}
    for meta, data in metas.items():
        changed = repoint(data, renamed)
        if bones:
            changed = renumber_bones(changed, bones)
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
    index = {bone.name: i for i, bone in enumerate(target_bind.bones)}
    bones = [index.get((renames or {}).get(bone.name, bone.name)) for bone in source_bind.bones]
    copied = write_copies(name, retargeted, meta_data, folder, prefix, new.slots, bones)
    print(f"{name}: {len(new.slots)} slots, {len(anims)} animations + {len(spliced)} spliced retargeted, {copied} metas repointed")
    return write_set(new)


def hold_props(anim: Animation, skeleton: Animation, holds: Dict[str, Tuple[str, Transform]]) -> None:
    """Holds props at fixed offsets from their anchor bones in every frame. Anchors are read before any prop moves, so a prop held to another follows its old place.

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
        print(f"{name}: {len(new.slots)} slots, {swapped} swapped")
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
    """Adds each new slot the set lacks as a copy of another slot of the same set. Fire slots copied from a cast play in every weapon state.

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
        weapons = ALL_WEAPONS if FIRE_SLOT.match(target) and "FIRE_" not in source else template.weapon_bools
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


def first_ref(slots: List[Slot], names: Dict[int, str], slot: str) -> Optional[AnimRef]:
    """Finds the first animation entry a slot plays.

    Args:
        slots (List[Slot]): The set's slots.
        names (Dict[int, str]): Slot names by id.
        slot (str): The slot name.

    Returns:
        Optional[AnimRef]: The entry, or None when the slot is missing or empty.
    """
    return next((s.refs[0] for s in slots if s.refs and names.get(s.slot_id) == slot), None)


def first_anim(slots: List[Slot], names: Dict[int, str], slot: str) -> Optional[str]:
    """Finds the first animation a slot plays.

    Args:
        slots (List[Slot]): The set's slots.
        names (Dict[int, str]): Slot names by id.
        slot (str): The slot name.

    Returns:
        Optional[str]: The animation path, or None when the slot is missing or empty.
    """
    ref = first_ref(slots, names, slot)
    return ref.anim if ref else None


def pin_props(data: bytes, names: Dict[int, str], sets: Dict[str, bytes], assets: AssetSource, pattern: str, grips: Dict[str, Tuple[str, str]],
              pins: Dict[str, Tuple[str, str]], folder: str, prefix: str, floor: Optional[Tuple[str, float]] = None) -> bytes:
    """Points the matching slots at copies of their animations with props held, and at copies of their metas pointed at them. Each slot also shows
    the props it holds, unless it shows none at all (a slot of weapon bools 0, such as an unarmed stand).

    Args:
        data (bytes): The set `.bin`.
        names (Dict[int, str]): Slot names by id.
        sets (Dict[str, bytes]): Set `.bin` files by set name, for poses of other sets.
        assets (AssetSource): The vanilla packs, for files the mod folder lacks.
        pattern (str): Regex of the slot names to change.
        grips (Dict[str, Tuple[str, str]]): Prop bone -> (the bone whose place it takes in the first frame, the bone it is held to).
        pins (Dict[str, Tuple[str, str]]): Prop bone -> (the slot whose first frame gives its offset, the bone it is held to). `set:SLOT` names another set's slot.
        folder (str): Output folder for the copies, relative to the mod folder.
        prefix (str): Short prefix marking the copies.
        floor (Optional[Tuple[str, float]]): (bone, height). In frames where the bone is lower he is raised until it is at that height.

    Returns:
        bytes: The changed set `.bin`.

    Raises:
        SystemExit: When no slot matches or a slot giving an offset is missing.
    """
    anim_set = parse_set(data)
    slots = [slot for slot in anim_set.slots if slot.refs and re.match(pattern, names.get(slot.slot_id, ""))]

    def pose_anim(pose: str) -> Optional[str]:
        set_name, _, slot = pose.rpartition(":")
        return first_anim(parse_set(sets[set_name]).slots if set_name else anim_set.slots, names, slot)

    poses = {pose: pose_anim(pose) for pose, _ in pins.values()}
    missing = sorted(pose for pose, anim in poses.items() if anim is None)
    if not slots or missing:
        raise SystemExit(f"{anim_set.name}: no {pattern} slot or no {', '.join(missing)} to pin to")

    skeleton_path = f"animations/skeletons/{anim_set.skeleton}.anim"
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
        heights = [0.0] * len(anim.translations)
        if floor:
            bone, low = floor
            heights = [max(0.0, low - world_pose(anim, skeleton, f)[index[bone]][1][1]) for f in range(len(heights))]
        if any(heights):
            # Every bone under the animation root moves with him: his body and the props.
            children = [bone for bone, info in enumerate(anim.bones) if info.parent == 0]
            for frame, height in zip(anim.translations, heights):
                for bone in children:
                    x, y, z = frame[bone] or skeleton.translations[0][bone]
                    frame[bone] = (x, y + height, z)
        first = world_pose(anim, skeleton, 0) if grips else None
        gripped = {prop: (hand, relative(first[index[hand]], first[index[leader]])) for prop, (leader, hand) in grips.items()}
        hold_props(anim, skeleton, {**gripped, **pinned})
        moved[path] = write_anim(anim)
    # Some vanilla slots name a meta that no pack has, e.g. Taoyan's ladder dismount.
    copied = write_copies(anim_set.name, moved, {m: read(m) for m in metas if read(m)}, folder, prefix, slots)
    shown = sum(1 << int(prop.rpartition("_")[2]) for prop in {**grips, **pins})
    for slot in slots:
        if slot.weapon_bools:
            slot.weapon_bools |= shown
    held = [f"{prop} held to {hand} where {leader} starts" for prop, (leader, hand) in grips.items()] + [f"{p} held to {a} as in {pose}" for p, (pose, a) in pins.items()]
    held += [f"raised until {floor[0]} is {floor[1]} m up"] if floor else []
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


def meta_entries(data: bytes) -> List[Tuple[int, str]]:
    """Finds the entries of a meta file.

    Args:
        data (bytes): The `.anm.meta` file.

    Returns:
        List[Tuple[int, str]]: (offset, tag) of each entry, in file order.

    Raises:
        SystemExit: When the entries found are not as many as its header says.
    """
    found = []
    for match in META_ENTRY.finditer(data, 8):
        size, tag = match.group(1)[0], match.group(2)[:match.group(1)[0]]
        body = match.start() + 2 + size
        if len(tag) == size and re.fullmatch(rb"[A-Z][A-Z0-9_]*", tag) and body + 4 <= len(data) and struct.unpack_from("<I", data, body)[0] < 64:
            found.append((match.start(), tag.decode()))
    if len(found) != struct.unpack_from("<I", data, 4)[0] or (found and found[0][0] != 8):
        raise SystemExit(f"meta of {len(data)} bytes: found {len(found)} entries, the header says {struct.unpack_from('<I', data, 4)[0]}")
    return found


def entry_body(data: bytes, offset: int, tag: str) -> Tuple[float, float, int]:
    """Reads the window of a meta entry and finds where its own fields start.

    Args:
        data (bytes): The meta file.
        offset (int): Where the entry starts.
        tag (str): Its tag.

    Returns:
        Tuple[float, float, int]: Its start and end seconds, and the offset of the fields after its filter string.
    """
    at = offset + 2 + len(tag) + 4
    begin, end = struct.unpack_from("<ff", data, at)
    at += 8
    return begin, end, at + 2 + struct.unpack_from("<H", data, at)[0] + 4


def splice_weight(time: float, begin: float, end: float, length: float) -> float:
    """How much of a spliced pose plays at a time. A window from the start fades the pose out, a later one fades it in and holds it to the end.

    Args:
        time (float): Seconds into the animation.
        begin (float): Window start.
        end (float): Window end. The same as `begin` for a pose held from then on.
        length (float): The animation's length.

    Returns:
        float: 0 to 1.
    """
    end = min(end, length)
    if end <= begin:
        return float(time >= begin)
    ramp = min(1.0, max(0.0, (time - begin) / (end - begin)))
    return 1.0 - ramp if begin <= 0.0 else ramp


def bake_splices(anim: Animation, meta: bytes, read: Callable[[str], Optional[bytes]], skeleton: Animation) -> None:
    """Plays a meta's spliced poses into its animation. A splice of bone -1 covers every bone the pose has, any other covers that bone and those under it.

    Args:
        anim (Animation): The animation, changed in place.
        meta (bytes): Its meta file.
        read (Callable[[str], Optional[bytes]]): Reads the spliced poses.
        skeleton (Animation): The skeleton's bind pose.
    """
    for offset, tag in meta_entries(meta):
        if tag != "SPLICE":
            continue
        begin, end, at = entry_body(meta, offset, tag)
        size = struct.unpack_from("<H", meta, at)[0]
        pose = read_anim(read(meta[at + 2:at + 2 + size].decode()))
        at += 2 + size
        bone = struct.unpack_from("<i", meta, at + 2 + struct.unpack_from("<H", meta, at)[0])[0]
        spliced = set() if bone >= 0 else set(range(len(anim.bones)))
        for index, info in enumerate(anim.bones):
            if index == bone or info.parent in spliced:
                spliced.add(index)
        for frame in range(len(anim.rotations)):
            weight = splice_weight(frame / anim.frame_rate, begin, end, anim.length)
            for index in spliced:
                here = (anim.rotations[frame][index] or skeleton.rotations[0][index], anim.translations[frame][index] or skeleton.translations[0][index])
                there = (pose.rotations[0][index] or here[0], pose.translations[0][index] or here[1])
                anim.rotations[frame][index], anim.translations[frame][index] = _blend(here, there, weight)


def shot_legs(slot: str) -> Tuple[str, str]:
    """The disc set's slot whose legs and disc a shot slot plays.

    Args:
        slot (str): The shot slot, e.g. `SHOOT_READY_TURN_LEFT_90`.

    Returns:
        Tuple[str, str]: The slot, and the pace (see `rest_arms()`). Walks, runs, steps and turns "stretch" to the legs, so they move as the disc does.
            Other shots keep their own length as "shot".
    """
    move = re.match(r"^SHOOT_(?:READY_)?(WALK|RUN|STEP|TURN)_(\w+)$", slot)
    if move:
        kind, way = move.groups()
        return {"WALK": "WALK_1", "RUN": "RUN_1"}.get(kind, f"{kind}_{'BACKWARD' if way == 'BACK' else way}"), "stretch"
    return ("WALK_1" if slot.startswith("MOVING_FIRE_") else "STAND"), "shot"


def rest_arms(slot: str) -> Tuple[str, str]:
    """The bow set's slot whose arms a resting slot of the disc set (see `DISC_BOW_RESTS`) plays over its own legs.

    Args:
        slot (str): The resting slot, e.g. `TURN_LEFT_90`.

    Returns:
        Tuple[str, str]: The bow set's slot, and its pace: "stretch" fits it to the legs' length, as a step or turn turns his chest with his hips.
            "loop" repeats it over them. A shot's own pace is "shot", its length with the legs looping under it.
    """
    move = re.match(r"^(STEP|TURN)_(\w+)$", slot)
    if move:
        kind, way = move.groups()
        return f"SHOOT_READY_{kind}_{'BACK' if way == 'BACKWARD' else way}", "stretch"
    return "SHOOT_READY", "loop"


def pose_at(anim: Animation, skeleton: Animation, at: float) -> List[Transform]:
    """Local transforms of every bone between two frames, the bind pose for bones without data.

    Args:
        anim (Animation): The animation.
        skeleton (Animation): Its skeleton's bind pose.
        at (float): The frame, with a fraction for a point between two frames.

    Returns:
        List[Transform]: One local transform per bone.
    """
    first = min(int(at), len(anim.rotations) - 1)
    second = min(first + 1, len(anim.rotations) - 1)

    def frame(index: int) -> List[Transform]:
        return [(_qnorm(anim.rotations[index][b] or skeleton.rotations[0][b]), anim.translations[index][b] or skeleton.translations[0][b]) for b in range(len(anim.bones))]

    return [_blend(a, b, at - first) for a, b in zip(frame(first), frame(second))]


def chain(anim: Animation, local: List[Transform]) -> List[Transform]:
    """World transforms from local ones.

    Args:
        anim (Animation): The animation, for its bone parents.
        local (List[Transform]): One local transform per bone.

    Returns:
        List[Transform]: One world transform per bone.
    """
    world: List[Transform] = []
    for index, bone in enumerate(anim.bones):
        world.append(local[index] if bone.parent < 0 else compose(world[bone.parent], local[index]))
    return world


def facing(world: List[Transform], left: int, right: int) -> float:
    """The way a line between two bones faces, as an angle about the up axis.

    Args:
        world (List[Transform]): World transforms per bone.
        left (int): The first bone.
        right (int): The second bone.

    Returns:
        float: The angle in radians.
    """
    return math.atan2(world[right][1][0] - world[left][1][0], world[right][1][2] - world[left][1][2])


def build_bow_disc(name: str, moves_name: str, shots_name: str, folder: str, prefix: str, sets: Dict[str, bytes], names: Dict[int, str],
                   assets: AssetSource) -> bytes:
    """Builds a bow disc set (see `BOW_DISCS`): the disc set's slots with the disc, sword and bow moved, plus his bow set's shots on the disc.

    Args:
        name (str): The new set's name.
        moves_name (str): The disc set, already built.
        shots_name (str): His foot bow set, already built.
        folder (str): Output folder, relative to the mod folder.
        prefix (str): Short prefix marking the files.
        sets (Dict[str, bytes]): Set `.bin` files by set name.
        names (Dict[int, str]): Slot names by id.
        assets (AssetSource): The vanilla packs, for files the mod folder lacks.

    Returns:
        bytes: The new set `.bin`.

    Raises:
        SystemExit: When a slot, dock pose or the bow's rest stance is missing.
    """
    moves, shots = parse_set(sets[moves_name]), parse_set(sets[shots_name])
    new = copy.deepcopy(moves)
    new.name = name
    present = {names.get(slot.slot_id, "") for slot in moves.slots if slot.refs}
    shot_slots = [slot for slot in shots.slots if slot.refs and re.search(BOW_SHOTS, names.get(slot.slot_id, "")) and names.get(slot.slot_id) not in present]
    legs = {names.get(slot.slot_id, ""): shot_legs(names.get(slot.slot_id, "")) for slot in shot_slots}
    leg_paths = {slot: first_anim(moves.slots, names, slot) for slot, _ in legs.values()}
    rests = {slot: rest_arms(slot) for slot in present if re.search(DISC_BOW_RESTS, slot)}
    arms_refs = {arms: first_ref(shots.slots, names, arms) for arms in {"SHOOT_READY", *(arms for arms, _ in rests.values())}}
    missing = sorted(slot for slot, found in {**leg_paths, **arms_refs}.items() if found is None)
    if missing:
        raise SystemExit(f"{name}: no {', '.join(missing)} to build the shots from")

    # A resting slot's own animation is only read for its legs, so it gets no moved copy unless another slot plays it too.
    skeleton_path = f"animations/skeletons/{TARGET_SKELETON}.anim"
    kept, resting = [slot for slot in new.slots if names.get(slot.slot_id, "") not in rests], [slot for slot in moves.slots if names.get(slot.slot_id, "") in rests]
    move_paths = sorted({r.anim for slot in kept for r in slot.refs if r.anim})
    move_metas = sorted({r.meta for slot in kept for r in slot.refs if r.meta})
    rest_legs = sorted({r.anim for slot in resting for r in slot.refs if r.anim})
    shot_files = [path for slot in shots.slots for r in slot.refs for path in (r.anim, r.meta) if path]
    first = read_files([skeleton_path, *move_paths, *move_metas, *rest_legs, *shot_files], assets)
    spliced = sorted({p.decode() for r in (ref for slot in shot_slots for ref in slot.refs) if r.meta for p in ANIM_PATH.findall(first(r.meta) or b"")})
    poses = read_files(spliced, assets)

    def read(path: str) -> Optional[bytes]:
        data = first(path)
        return poses(path) if data is None else data

    def load(path: str) -> Animation:
        return read_anim(read(path))

    skeleton = load(skeleton_path)
    index = {bone.name: i for i, bone in enumerate(skeleton.bones)}
    docking = set_docking(shots, names, read)
    held = {prop: (DOCK_POINTS[point][1], dock_offset(docking, Dock(point, number, 0.0, 0.0), load, skeleton)) for prop, (point, number) in DISC_BOW_DOCKS.items()}
    if docking is None or any(offset is None for _, offset in held.values()):
        raise SystemExit(f"{shots_name}: no dock pose for {', '.join(DISC_BOW_DOCKS)}")

    # His moves on the disc: the disc on its new bone, the sword in his hand and the bow on his back.
    source, target = index[DISC_MOVE[0]], index[DISC_MOVE[1]]
    moved: Dict[str, bytes] = {}
    for path in move_paths:
        anim = load(path)
        for rotations, translations in zip(anim.rotations, anim.translations):
            rotations[target], translations[target] = rotations[source] or skeleton.rotations[0][source], translations[source] or skeleton.translations[0][source]
        hold_props(anim, skeleton, held)
        moved[path] = write_anim(anim)
    copied = write_copies(name, moved, {m: read(m) for m in move_metas if read(m)}, folder, prefix, new.slots)
    disc_bit = 1 << int(DISC_MOVE[1].rpartition("_")[2])
    shown = disc_bit | sum(1 << int(prop.rpartition("_")[2]) for prop in DISC_BOW_DOCKS)
    for slot in new.slots:
        if slot.weapon_bools:
            slot.weapon_bools = shown

    # Built poses by path, since many resting slots share one bow pose and one set of legs. Neither is changed once built.
    baked_cache: Dict[Tuple[str, str], Animation] = {}
    leg_cache: Dict[str, Animation] = {}

    def baked(path: str, meta: str) -> Animation:
        # Docks of this slot's own meta only, since several slots play one animation with different docks.
        if (path, meta) not in baked_cache:
            anim, data = load(path), read(meta) if meta else None
            if data:
                bake_splices(anim, data, read, skeleton)
            own = replace(docking, own={path: read_docks(data) if data else []}, disabled={path: read_disables(data) if data else []})
            apply_docking(anim, path, own, load, skeleton)
            baked_cache[path, meta] = anim
        return baked_cache[path, meta]

    def legs_of(path: str) -> Animation:
        # The disc set's animation a composite takes its legs and disc from.
        if path not in leg_cache:
            leg_cache[path] = load(path)
        return leg_cache[path]

    upper = {index[UPPER_BODY]}
    for i, bone in enumerate(skeleton.bones):
        if bone.parent in upper:
            upper.add(i)
    props = [i for i, bone in enumerate(skeleton.bones) if PROP_BONE.match(bone.name) and i != target]
    lower = {i for i in range(1, len(skeleton.bones)) if i not in upper and i not in props and i != target}
    hunch = [index[bone] for bone in HUNCH_BONES]
    spine, chest, shoulders = index[UPPER_BODY], index["spine_2"], [index[bone] for bone in SHOULDERS]
    rest = pose_at(baked(arms_refs["SHOOT_READY"].anim, arms_refs["SHOOT_READY"].meta), skeleton, 0)
    anchors = [index[bone] for bone in PROP_ANCHORS]
    shot_folder = f"{folder}/shots"
    os.makedirs(os.path.join(MOD, shot_folder, "meta"), exist_ok=True)

    def nearest(world: List[Transform], prop: int) -> int:
        # The one of `PROP_ANCHORS` closest to the prop.
        return min(anchors, key=lambda b: sum((p - q) ** 2 for p, q in zip(world[b][1], world[prop][1])))

    def composite(bow: Animation, step: Animation, pace: str) -> Tuple[Animation, List[Tuple[Transform, Transform]]]:
        # The bow's arms over the disc set's legs, timed by `pace` (see `rest_arms()`), with his and the bow's chest per frame for its `FIRE_POS`.
        by_shot = pace == "shot"
        timing = bow if by_shot else step
        anim = copy.deepcopy(timing)
        frames, bow_frames, step_frames = len(timing.rotations), len(bow.rotations) - 1, len(step.rotations) - 1
        bow_at = {"shot": lambda f: f, "stretch": lambda f: f * bow_frames / max(1, frames - 1), "loop": lambda f: f % max(1, bow_frames)}[pace]
        leg_at = (lambda f: f % max(1, step_frames)) if by_shot else (lambda f: f)
        chests = []
        for frame in range(frames):
            shot, leg = pose_at(bow, skeleton, bow_at(frame)), pose_at(step, skeleton, leg_at(frame))
            local = [(shot if by_shot else leg)[0]] + [leg[i] if i in lower else shot[i] for i in range(1, len(shot))]
            for i in hunch:
                local[i] = (_qnorm(_qmul(_qmul(leg[i][0], _qconj(rest[i][0])), shot[i][0])), leg[i][1])
            local[target] = leg[source]
            shot_world, world = chain(bow, shot), chain(anim, local)
            turn = math.remainder(facing(shot_world, *shoulders) - facing(world, *shoulders), math.tau)
            parent = world[anim.bones[spine].parent][0]
            around = _qmul(_qmul(_qconj(parent), (0.0, math.sin(turn / 2), 0.0, math.cos(turn / 2))), parent)
            local[spine] = (_qnorm(_qmul(around, local[spine][0])), local[spine][1])
            world = chain(anim, local)
            chests.append((world[chest], shot_world[chest]))
            # Each prop keeps its place on the nearest of `PROP_ANCHORS` as in the shot, so a held prop stays in his hand.
            for prop in props:
                near = nearest(shot_world, prop)
                placed = compose(world[near], relative(shot_world[near], shot_world[prop]))
                local[prop] = relative(world[anim.bones[prop].parent], placed)
            anim.rotations[frame], anim.translations[frame] = [t[0] for t in local], [t[1] for t in local]
        return anim, chests

    def build(slot_name: str, number: int, arms: AnimRef, leg_path: str, pace: str, sound: str) -> AnimRef:
        # Writes one composite and its bow meta, with each `FIRE_POS` moved to where his hands now are.
        anim, chests = composite(baked(arms.anim, arms.meta), legs_of(leg_path), pace)
        stem = f"{shot_folder}/hu1_{prefix}_{slot_name.lower()}{f'_{number}' if number else ''}"
        with open(os.path.join(MOD, f"{stem}.anim"), "wb") as f:
            f.write(write_anim(anim))
        data = read(arms.meta) if arms.meta else None
        if not data:
            return AnimRef(f"{stem}.anim", "", sound)

        def moved_fire(time: float, position: Vec3) -> Vec3:
            his, bows = chests[min(len(chests) - 1, max(0, round(time * anim.frame_rate)))]
            return compose(his, relative(bows, ((0.0, 0.0, 0.0, 1.0), position)))[1]

        extra, held = (), None
        if re.search(MOVING_SHOTS, slot_name):
            start = chain(anim, pose_at(anim, skeleton, 0))
            extra = (splice_override(MOVING_SPLICE_WEIGHTS),)
            held = {}
            for prop in props:
                near = nearest(start, prop)
                held[prop] = (near, relative(start[near], start[prop]))
        meta = f"{shot_folder}/meta/{os.path.basename(stem)}.anm.meta"
        with open(os.path.join(MOD, meta), "wb") as f:
            f.write(shot_meta(data, moved_fire, extra, held))
        return AnimRef(f"{stem}.anim", meta, sound)

    for slot in shot_slots:
        slot_name = names.get(slot.slot_id, "")
        leg_slot, pace = legs[slot_name]
        refs = [build(slot_name, number, ref, leg_paths[leg_slot], pace, ref.sound) for number, ref in enumerate(slot.refs)]
        new.slots.append(replace(slot, refs=refs, weapon_bools=slot.weapon_bools | disc_bit if slot.weapon_bools else 0))

    # His resting slots hold the bow ready over the disc set's own legs, so he keeps it in hand between shots.
    for old, slot in zip(moves.slots, new.slots):
        slot_name = names.get(slot.slot_id, "")
        if slot_name in rests:
            arms_slot, pace = rests[slot_name]
            slot.refs = [build(slot_name, number, arms_refs[arms_slot], ref.anim, pace, ref.sound) for number, ref in enumerate(old.refs)]
    print(f"{name}: {len(moved)} {moves_name} animations with the disc, sword and bow moved ({copied} metas repointed), {len(shot_slots)} shots of {shots_name} added, "
          f"{len(rests)} resting slots holding the bow")
    return write_set(new)


def splice_override(weights: Tuple[float, ...]) -> bytes:
    """Builds a `SPLICE_OVERRIDE` meta entry over the whole animation, laid out as AssetEditor's `SpliceOverride_v12`, with weapon poses on.

    Args:
        weights (Tuple[float, ...]): Weights for the generic bone, neck, torso, left arm, right arm and legs.

    Returns:
        bytes: The entry.
    """
    # Tag, version, start and end time, filter, id, animation, reference animation, generic bone and its depth.
    head = pack_string("SPLICE_OVERRIDE") + struct.pack("<Iff", 12, 0.0, 0.0) + pack_string("") + struct.pack("<i", 0) + pack_string("") * 2 + struct.pack("<ii", -1, 0)
    # The weights, no blend in or out, then additive, weapon pose, stretch, exclude stripped and one unknown flag.
    return head + struct.pack("<8f", *weights, 0.0, 0.0) + b"".join(pack_string(flag) for flag in ("false", "true", "false", "false", "false"))


def shot_meta(data: bytes, moved_fire: Callable[[float, Vec3], Vec3], extra: Tuple[bytes, ...] = (), held: Optional[Dict[int, Tuple[int, Transform]]] = None) -> bytes:
    """Copies a shot's meta without the entries baked into its animation (`BAKED_ENTRIES`), with each `FIRE_POS` moved to where his hands now are.

    Args:
        data (bytes): The bow set's meta file.
        moved_fire (Callable[[float, Vec3], Vec3]): Takes a fire position's time and place, gives its new place.
        extra (Tuple[bytes, ...]): Whole entries to add, e.g. a moving shot's `splice_override()`.
        held (Optional[Dict[int, Tuple[int, Transform]]]): Prop bone -> (the bone holding it, its place on that bone), to move its `ANIMATED_PROP`.

    Raises:
        ValueError: If an `ANIMATED_PROP` to move is not version 14.

    Returns:
        bytes: The new meta file.
    """
    entries = meta_entries(data)
    kept = []
    for number, (offset, tag) in enumerate(entries):
        entry = bytearray(data[offset:entries[number + 1][0] if number + 1 < len(entries) else len(data)])
        if BAKED_ENTRIES.match(tag):
            continue
        if tag == "FIRE_POS":
            begin, _, at = entry_body(data, offset, tag)
            struct.pack_into("<fff", entry, at - offset, *moved_fire(begin, struct.unpack_from("<fff", data, at)))
        if tag == "ANIMATED_PROP" and held:
            tail = len(entry) - ANIMATED_PROP_TAIL
            fields = struct.unpack_from(ANIMATED_PROP_PLACE, entry, tail)
            if fields[8] in held:
                # The version follows the length-prefixed tag.
                version = struct.unpack_from("<I", entry, 2 + len(tag))[0]
                if version != 14:
                    raise ValueError(f"ANIMATED_PROP version {version} is not 14")
                anchor, from_anchor = held[fields[8]]
                turn, place = compose(from_anchor, (fields[3:7], fields[0:3]))
                struct.pack_into(ANIMATED_PROP_PLACE, entry, tail, *place, *turn, fields[7], anchor)
        kept.append(bytes(entry))
    kept.extend(extra)
    return struct.pack("<II", struct.unpack_from("<I", data, 0)[0], len(kept)) + b"".join(kept)


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


def seat_riders(data: bytes, names: Dict[int, str], sets: Dict[str, bytes], assets: AssetSource) -> bytes:
    """Moves the origin-placed rider animations of a saddle set into saddle space: copies with his hips on the set's own seat, and in slots where the
    mount moves under him, without the mount's motion. Sets that place riders from the mount's origin are returned as they are.

    Args:
        data (bytes): The set `.bin`.
        names (Dict[int, str]): Slot names by id.
        sets (Dict[str, bytes]): Set `.bin` files by set name, for the origin seat and the mount's animations.
        assets (AssetSource): The vanilla packs, for files the mod folder lacks.

    Returns:
        bytes: The changed set `.bin`.

    Raises:
        SystemExit: When the set has no stand or the mount has no animation for a carried slot.
    """
    anim_set = parse_set(data)
    if not anim_set.flag & SADDLE_SPACE:
        return data

    stand = first_anim(anim_set.slots, names, "RIDER_STAND") or first_anim(anim_set.slots, names, "STAND")
    if stand is None:
        raise SystemExit(f"{anim_set.name}: no stand to seat riders on")
    mount = parse_set(sets[anim_set.mount])
    slots = [slot for slot in anim_set.slots if slot.refs and re.match(SEATED_SLOTS, names.get(slot.slot_id, ""))]
    carriers = {names[s.slot_id]: first_anim(mount.slots, names, names[s.slot_id].removeprefix("RIDER_")) for s in slots if re.match(CARRIED_SLOTS, names[s.slot_id])}
    if None in carriers.values():
        raise SystemExit(f"{anim_set.name}: {anim_set.mount} has no animation for {', '.join(k for k, v in carriers.items() if v is None)}")
    skeleton_path, mount_skeleton_path = f"animations/skeletons/{TARGET_SKELETON}.anim", f"animations/skeletons/{mount.skeleton}.anim"
    origin_set, origin_slot = ORIGIN_SEAT
    origin_stand, mount_stand = first_anim(parse_set(sets[origin_set]).slots, names, origin_slot), first_anim(mount.slots, names, "STAND")
    anims = sorted({r.anim for slot in slots for r in slot.refs if r.anim})
    metas = sorted({r.meta for slot in slots for r in slot.refs if r.meta})
    read = read_files([p for p in (skeleton_path, mount_skeleton_path, stand, origin_stand, mount_stand, *anims, *metas, *carriers.values()) if p], assets)
    skeleton = read_anim(read(skeleton_path))
    hips = [bone.name for bone in skeleton.bones].index("root")
    seat = world_pose(read_anim(read(stand)), skeleton, 0)[hips][1]
    origin = world_pose(read_anim(read(origin_stand)), skeleton, 0)[hips][1]
    offset = tuple(origin[k] - seat[k] for k in range(3))
    # The saddle bone's motion relative to the mount's stand, per frame of each carried slot's mount animation.
    identity: Transform = ((0.0, 0.0, 0.0, 1.0), (0.0, 0.0, 0.0))
    motions: Dict[str, List[Transform]] = {}
    if carriers:
        mount_skeleton = read_anim(read(mount_skeleton_path))
        saddle = [bone.name for bone in mount_skeleton.bones].index(SADDLE_BONE)
        from_rest = relative(world_pose(read_anim(read(mount_stand)), mount_skeleton, 0)[saddle], identity)
        for path in set(carriers.values()):
            mount_anim = read_anim(read(path))
            motions[path] = [compose(world_pose(mount_anim, mount_skeleton, f)[saddle], from_rest) for f in range(len(mount_anim.rotations))]

    # Every slot playing an animation goes with it. One taken from an origin-placed set starts far over the seat.
    seated: Dict[str, bytes] = {}
    moved_slots = []
    for slot in slots:
        path = slot.refs[0].anim
        if path not in seated:
            anim = read_anim(read(path))
            if world_pose(anim, skeleton, 0)[hips][1][1] - seat[1] < ORIGIN_HEIGHT:
                continue
            motion = motions.get(carriers.get(names[slot.slot_id]), [identity])
            tops = [bone for bone, info in enumerate(anim.bones) if info.parent < 0]
            frames = len(anim.rotations)
            for frame in range(frames):
                carried = motion[frame * len(motion) // frames]
                for bone in tops:
                    local = (anim.rotations[frame][bone] or skeleton.rotations[0][bone], anim.translations[frame][bone] or skeleton.translations[0][bone])
                    rotation, translation = relative(carried, local)
                    anim.rotations[frame][bone], anim.translations[frame][bone] = rotation, tuple(translation[k] - offset[k] for k in range(3))
            seated[path] = write_anim(anim)
        moved_slots.append(slot)
    if not seated:
        return data
    folder = f"{DERIVED_FOLDER}/seated/{anim_set.name.removeprefix('hu1_advisor_overhaul_')}"
    copied = write_copies(anim_set.name, seated, {m: read(m) for m in metas if read(m)}, folder, "seat", moved_slots)
    print(f"{anim_set.name}: {len(seated)} origin-placed rider animations seated for {len(moved_slots)} slots, {copied} metas repointed")
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
            data = pin_props(data, names, sets, assets, *spec)
        if name in BAKED_DOCKING:
            data = bake_docking(data, *BAKED_DOCKING[name], names, assets)
        sets[name] = seat_riders(with_mount(name, data), names, sets, assets)
        entries.append((f"{SET_FOLDER}/{name}.bin", sets[name]))

    shutil.rmtree(os.path.join(MOD, DERIVED_FOLDER, "seated"), ignore_errors=True)
    for name, (source, skeleton, folder, prefix) in SETS.items():
        shutil.rmtree(os.path.join(MOD, folder), ignore_errors=True)
        finish(name, build_set(name, vanilla[source], skeleton, folder, prefix, assets))
    for name, spec in DERIVED_SETS.items():
        if spec.get("folder"):
            shutil.rmtree(os.path.join(MOD, spec["folder"]), ignore_errors=True)
        finish(name, build_derived(name, spec, sets, assets, names))
    for name, (moves, shots, folder, prefix) in BOW_DISCS.items():
        shutil.rmtree(os.path.join(MOD, folder), ignore_errors=True)
        finish(name, build_bow_disc(name, moves, shots, folder, prefix, sets, names, assets))
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
