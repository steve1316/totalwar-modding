"""Equipment docking for the viewer. The game holds a prop on a hand, hip or back where a set's metadata docks it, whatever the animation does with the
prop's bone. A `DOCK_EQPT_*` entry in the set's persistent metadata docks it in every animation that does not disable that, and an entry in an
animation's own metadata docks it for a time window. The offset from the dock bone comes from the set's `DOCK_EQUIPMENT_*` pose.
"""

import re
import struct
from dataclasses import dataclass
from typing import Callable, Dict, List, Optional, Tuple

from tools.anim_file import Animation
from tools.anim_retarget import Transform, compose, relative, world_pose
from tools.glf_rebuild_animpack import AnimSet

# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Settings

# Dock point in a `DOCK_EQPT_*` tag -> (the set's slot holding its pose, the bone the prop is held to). Which bone the game uses for a hip or the back
# is a guess: the hips and the upper spine.
DOCK_POINTS = {
    "RHAND": ("DOCK_EQUIPMENT_RIGHT_HAND", "hand_right"),
    "RHAND_2": ("DOCK_EQUIPMENT_RIGHT_HAND_2", "hand_right"),
    "LHAND": ("DOCK_EQUIPMENT_LEFT_HAND", "hand_left"),
    "LHAND_2": ("DOCK_EQUIPMENT_LEFT_HAND_2", "hand_left"),
    "RWAIST": ("DOCK_EQUIPMENT_RIGHT_WAIST", "root"),
    "LWAIST": ("DOCK_EQUIPMENT_LEFT_WAIST", "root"),
    "BACK": ("DOCK_EQUIPMENT_BACK", "spine_2"),
}

# A `DOCK_EQPT_*` entry: its tag, then version, start and end seconds, a filter string, a field of unknown use and the prop number.
DOCK_ENTRY = re.compile(rb"DOCK_EQPT_([A-Z0-9_]+)")
# A `DISABLE_PERSISTENT` entry: its tag, then version, start and end seconds.
DISABLE_ENTRY = re.compile(rb"DISABLE_PERSISTENT")

# Prop bones in skeleton order. Prop number N in the metadata is the Nth of them.
PROP_BONE = re.compile(r"^(be_prop|weapon)_\d+$")


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Docking


@dataclass
class Dock:
    """One prop held to a dock point."""

    # The dock point, e.g. `RWAIST`.
    point: str
    # The prop number (1 for the first prop bone).
    prop: int
    # Seconds the dock starts and ends, see `in_window()`.
    start: float
    end: float


@dataclass
class SetDocking:
    """A set's docks and dock poses."""

    # Docks from the set's persistent metadata.
    persistent: List[Dock]
    # Docks of each animation's own metadata, by animation path.
    own: Dict[str, List[Dock]]
    # Windows in which an animation's own metadata turns the persistent docks off, by animation path.
    disabled: Dict[str, List[Tuple[float, float]]]
    # Dock pose animation path by dock point.
    poses: Dict[str, str]
    # Pose offsets already worked out, by (dock point, prop number). None when the set has no pose for it.
    offsets: Dict[Tuple[str, int], Optional[Transform]]


def read_docks(meta: bytes) -> List[Dock]:
    """Finds the `DOCK_EQPT_*` entries of a meta file.

    Args:
        meta (bytes): `.anm.meta` bytes.

    Returns:
        List[Dock]: Its docks.
    """
    docks = []
    for match in DOCK_ENTRY.finditer(meta):
        offset = match.end() + 4
        start, end = struct.unpack_from("<ff", meta, offset)
        offset += 8
        offset += 2 + struct.unpack_from("<H", meta, offset)[0] + 4
        docks.append(Dock(match.group(1).decode(), struct.unpack_from("<i", meta, offset)[0], start, end))
    return docks


def read_disables(meta: bytes) -> List[Tuple[float, float]]:
    """Finds the `DISABLE_PERSISTENT` windows of a meta file.

    Args:
        meta (bytes): `.anm.meta` bytes.

    Returns:
        List[Tuple[float, float]]: Start and end seconds of each.
    """
    return [struct.unpack_from("<ff", meta, match.end() + 4) for match in DISABLE_ENTRY.finditer(meta)]


def in_window(time: float, start: float, end: float) -> bool:
    """Whether a time falls in a metadata window. A window whose start and end are the same lasts from then to the end of the animation.

    Args:
        time (float): Seconds into the animation.
        start (float): Window start.
        end (float): Window end.

    Returns:
        bool: True when the window covers the time.
    """
    return start <= time and (start == end or time <= end)


def set_docking(anim_set: AnimSet, names: Dict[int, str], read: Callable[[str], Optional[bytes]]) -> Optional[SetDocking]:
    """Collects a set's docks.

    Args:
        anim_set (AnimSet): The set.
        names (Dict[int, str]): Slot names by id.
        read (Callable[[str], Optional[bytes]]): Reads a game file, None when it is missing.

    Returns:
        Optional[SetDocking]: The docks, or None when the set docks nothing.
    """
    docking = SetDocking([], {}, {}, {}, {})
    for slot in anim_set.slots:
        name = names.get(slot.slot_id, "")
        for ref in slot.refs:
            meta = read(ref.meta) if ref.meta else None
            if not meta:
                continue
            if name == "PERSISTENT_METADATA_ALIVE":
                docking.persistent += read_docks(meta)
            elif ref.anim:
                docking.own.setdefault(ref.anim, []).extend(read_docks(meta))
                docking.disabled.setdefault(ref.anim, []).extend(read_disables(meta))
        for point, (pose_slot, _) in DOCK_POINTS.items():
            if name == pose_slot and slot.refs and point not in docking.poses:
                docking.poses[point] = slot.refs[0].anim
    if not docking.persistent and not any(docking.own.values()):
        return None
    return docking


def dock_offset(docking: SetDocking, dock: Dock, load: Callable[[str], Animation], skeleton: Animation) -> Optional[Transform]:
    """The prop's transform relative to its dock bone in the set's pose for that dock point.

    Args:
        docking (SetDocking): The set's docks.
        dock (Dock): The dock.
        load (Callable[[str], Animation]): Reads an animation.
        skeleton (Animation): The skeleton's bind pose.

    Returns:
        Optional[Transform]: The offset, or None when the set has no pose for the dock point.
    """
    key = (dock.point, dock.prop)
    if key not in docking.offsets:
        docking.offsets[key] = None
        if dock.point in DOCK_POINTS and dock.point in docking.poses:
            pose = load(docking.poses[dock.point])
            index = {bone.name: i for i, bone in enumerate(pose.bones)}
            props = [bone.name for bone in pose.bones if PROP_BONE.match(bone.name)]
            bone = DOCK_POINTS[dock.point][1]
            if 0 < dock.prop <= len(props) and bone in index:
                world = world_pose(pose, skeleton, 0)
                docking.offsets[key] = relative(world[index[bone]], world[index[props[dock.prop - 1]]])
    return docking.offsets[key]


def apply_docking(anim: Animation, path: str, docking: SetDocking, load: Callable[[str], Animation], skeleton: Animation) -> bool:
    """Holds each docked prop to its dock bone in the frames it is docked.

    Args:
        anim (Animation): The animation, changed in place.
        path (str): Its game path.
        docking (SetDocking): Its set's docks.
        load (Callable[[str], Animation]): Reads an animation.
        skeleton (Animation): The skeleton's bind pose.

    Returns:
        bool: True when a prop was moved.
    """
    disables = docking.disabled.get(path, [])
    docks = [(dock, True) for dock in docking.persistent] + [(dock, False) for dock in docking.own.get(path, [])]
    index = {bone.name: i for i, bone in enumerate(anim.bones)}
    props = [bone.name for bone in anim.bones if PROP_BONE.match(bone.name)]
    held = []
    for dock, persistent in docks:
        offset = dock_offset(docking, dock, load, skeleton)
        if offset is not None and 0 < dock.prop <= len(props):
            held.append((dock, persistent, index[props[dock.prop - 1]], index[DOCK_POINTS[dock.point][1]], offset))
    if not held:
        return False
    for frame in range(len(anim.rotations)):
        time = frame / anim.frame_rate if anim.frame_rate else 0.0
        # Later docks win, so an animation's own docks override the persistent ones.
        off = any(in_window(time, start, end) for start, end in disables)
        active = {prop: (bone, offset) for dock, persistent, prop, bone, offset in held if not (persistent and off) and in_window(time, dock.start, dock.end)}
        if not active:
            continue
        world = world_pose(anim, skeleton, frame)
        for prop, (bone, offset) in active.items():
            parent = anim.bones[prop].parent
            pinned = compose(world[bone], offset)
            anim.rotations[frame][prop], anim.translations[frame][prop] = relative(world[parent], pinned) if parent >= 0 else pinned
    return True
