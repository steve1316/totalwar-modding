"""Retarget a Warhammer 3 animation from one humanoid skeleton onto another that shares its bone names (e.g. humanoid01c onto humanoid01).

Both skeletons use the same bone axes, so a bone's animated local rotation means the same pose on either. The retarget:
- copies the rotation of every bone both skeletons have,
- keeps the target's own bone lengths, so the body keeps its proportions,
- moves the root bones by the source's offset from its own bind pose, so height changes (hovering, crouching) carry over,
- copies prop bones (`be_prop_*`) and `animroot` as they are, so props such as a disc sit where the source put them,
- then moves held props (weapons) so they keep their offset from the hand or root they were nearest in the source. Without this a staff floats
  away from a hand that sits somewhere else on the target's shorter arm.

Bones only the target has keep their bind pose. Bones only the source has are dropped. Bones the skeletons name differently (humanoid01e's
`head_0` and `weapon_1` are humanoid01's `head` and `be_prop_0`) can be renamed first. A bone whose parent differs between the skeletons gets its
source world rotation instead of its local one.
"""

import math
from dataclasses import replace
from typing import Dict, Iterable, List, Optional, Tuple

import numpy as np

from tools.anim_file import Animation, Bone, Quat, Vec3

# Bones whose translation is copied from the source as is.
COPIED_TRANSLATION_PREFIXES = ("animroot", "be_prop_")

# Bones moved by the source's offset from its bind pose.
OFFSET_BONES = ("root",)

# Bones a held prop can follow. Each frame a prop follows the one it is nearest to in the source.
ANCHOR_BONES = ("hand_left", "hand_right", "root")

# Prop bones left exactly where the source put them, such as the disc a rider stands on.
FIXED_PROPS = ("be_prop_4",)

# A prop that left the hand follows this bone instead, so a staff spinning above a caster stays above him.
RELEASE_ANCHOR = "root"

# Metres past a prop's closest distance to its hand where it starts and finishes blending from the hand to `RELEASE_ANCHOR`.
RELEASE_START = 0.15
RELEASE_END = 0.45

# A world transform: rotation and position.
Transform = Tuple[Quat, Vec3]


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Math


def _qmul(a: Quat, b: Quat) -> Quat:
    ax, ay, az, aw = a
    bx, by, bz, bw = b
    return (aw * bx + ax * bw + ay * bz - az * by, aw * by - ax * bz + ay * bw + az * bx, aw * bz + ax * by - ay * bx + az * bw,
            aw * bw - ax * bx - ay * by - az * bz)


def _qconj(q: Quat) -> Quat:
    return (-q[0], -q[1], -q[2], q[3])


def _qnorm(q: Quat) -> Quat:
    length = math.sqrt(sum(c * c for c in q)) or 1.0
    return tuple(c / length for c in q)


def _qrot(q: Quat, v: Vec3) -> Vec3:
    x, y, z, _ = _qmul(_qmul(q, (v[0], v[1], v[2], 0.0)), _qconj(q))
    return (x, y, z)


def compose(parent: Transform, local: Transform) -> Transform:
    """Places a local transform under its parent's world transform.

    Args:
        parent (Transform): The parent's world transform.
        local (Transform): The transform relative to the parent.

    Returns:
        Transform: The world transform.
    """
    rotation = _qnorm(_qmul(parent[0], local[0]))
    offset = _qrot(parent[0], local[1])
    return rotation, tuple(parent[1][k] + offset[k] for k in range(3))


def relative(anchor: Transform, world: Transform) -> Transform:
    """The inverse of `compose`: a world transform seen from an anchor's world transform.

    Args:
        anchor (Transform): The anchor's world transform.
        world (Transform): The world transform to express.

    Returns:
        Transform: The transform relative to the anchor.
    """
    inverse = _qconj(anchor[0])
    return _qnorm(_qmul(inverse, world[0])), _qrot(inverse, tuple(world[1][k] - anchor[1][k] for k in range(3)))


def _blend(a: Transform, b: Transform, weight: float) -> Transform:
    """Blends two transforms: weight 0 gives `a`, 1 gives `b`."""
    if weight <= 0.0:
        return a
    if weight >= 1.0:
        return b
    qb = b[0] if sum(x * y for x, y in zip(a[0], b[0])) >= 0 else tuple(-c for c in b[0])
    rotation = _qnorm(tuple(a[0][k] * (1 - weight) + qb[k] * weight for k in range(4)))
    return rotation, tuple(a[1][k] * (1 - weight) + b[1][k] * weight for k in range(3))


def world_pose(anim: Animation, skeleton: Animation, frame: int) -> List[Transform]:
    """World transforms of every bone of one frame, using the skeleton's bind pose for bones without data.

    Args:
        anim (Animation): The animation.
        skeleton (Animation): Its skeleton's bind pose.
        frame (int): The frame index.

    Returns:
        List[Transform]: One world transform per bone.
    """
    out: List[Transform] = []
    for index, bone in enumerate(anim.bones):
        rotation = anim.rotations[frame][index] or skeleton.rotations[0][index]
        translation = anim.translations[frame][index] or skeleton.translations[0][index]
        local = (_qnorm(rotation), translation)
        out.append(local if bone.parent < 0 else compose(out[bone.parent], local))
    return out


def quat_matrix(quat: Quat, position: Vec3) -> np.ndarray:
    """4x4 matrix (column vectors) from a rotation and a position.

    Args:
        quat (Quat): The rotation quaternion (x, y, z, w).
        position (Vec3): The position.

    Returns:
        np.ndarray: The matrix.
    """
    x, y, z, w = quat
    m = np.eye(4)
    m[:3, :3] = [[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                 [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                 [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]]
    m[:3, 3] = position
    return m


def _anchor_props(source: Animation, source_worlds: List[List[Transform]], target: Animation, target_skeleton: Animation) -> None:
    """Moves each held prop of the target so it keeps its source offset from the nearest hand or root, given the source's world pose per frame."""
    source_index = {bone.name: i for i, bone in enumerate(source.bones)}
    target_index = {bone.name: i for i, bone in enumerate(target.bones)}
    props = [b.name for b in target.bones if b.name.startswith("be_prop_") and b.name not in FIXED_PROPS and b.name in source_index]
    anchors = [name for name in ANCHOR_BONES if name in source_index and name in target_index]
    frames = len(source.rotations)

    # One anchor per prop for the whole animation, so a prop never jumps between hands mid-swing.
    def mean_distance(prop: str, anchor: str) -> float:
        p, a = source_index[prop], source_index[anchor]
        return sum(math.dist(world[p][1], world[a][1]) for world in source_worlds) / frames

    chosen = {prop: min(anchors, key=lambda anchor: mean_distance(prop, anchor)) for prop in props}

    # How close each prop gets to its anchor. A prop further than that by RELEASE_START has left the hand (e.g. a staff thrown up while casting).
    held = {prop: min(math.dist(world[source_index[prop]][1], world[source_index[chosen[prop]]][1]) for world in source_worlds) for prop in props}
    for frame in range(frames):
        source_world = source_worlds[frame]
        target_world = world_pose(target, target_skeleton, frame)
        for prop in props:
            s_prop, t_prop = source_index[prop], target_index[prop]
            if source.translations[frame][s_prop] is None or source.rotations[frame][s_prop] is None:
                continue
            anchor = chosen[prop]
            prop_world = source_world[s_prop]
            in_hand = compose(target_world[target_index[anchor]], relative(source_world[source_index[anchor]], prop_world))
            on_root = compose(target_world[target_index[RELEASE_ANCHOR]], relative(source_world[source_index[RELEASE_ANCHOR]], prop_world))
            gap = math.dist(prop_world[1], source_world[source_index[anchor]][1]) - held[prop]
            weight = min(1.0, max(0.0, (gap - RELEASE_START) / (RELEASE_END - RELEASE_START)))
            new_world = _blend(in_hand, on_root, weight)
            parent = target.bones[t_prop].parent
            local = relative(target_world[parent], new_world) if parent >= 0 else new_world
            target.rotations[frame][t_prop] = local[0]
            target.translations[frame][t_prop] = local[1]


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Retarget


def renamed(anim: Animation, renames: Dict[str, str]) -> Animation:
    """A copy of an animation or skeleton with some bones renamed.

    Args:
        anim (Animation): The animation or skeleton bind pose.
        renames (Dict[str, str]): Old bone name -> new bone name.

    Returns:
        Animation: The copy. Its tracks are shared with `anim`.
    """
    return replace(anim, bones=[Bone(renames.get(bone.name, bone.name), bone.parent) for bone in anim.bones])


def _match_world_rotations(source: Animation, source_worlds: List[List[Transform]], target: Animation, target_skeleton: Animation) -> None:
    """Gives each bone whose parent differs between the skeletons the world rotation it has in the source, given the source's world pose per frame.

    Copying a local rotation only works under the same parent. Humanoid01e has `neck_1` between `neck_0` and the head, so a copied head rotation
    would lose the neck's turn.
    """
    source_index = {bone.name: i for i, bone in enumerate(source.bones)}

    def parent_name(anim: Animation, index: int) -> str:
        parent = anim.bones[index].parent
        return anim.bones[parent].name if parent >= 0 else ""

    moved = {i for i, bone in enumerate(target.bones)
             if bone.name in source_index and bone.parent >= 0 and parent_name(source, source_index[bone.name]) != parent_name(target, i)}
    if not moved:
        return
    for frame, source_world in enumerate(source_worlds):
        world: List[Quat] = []
        for i, bone in enumerate(target.bones):
            local = target.rotations[frame][i] or target_skeleton.rotations[0][i]
            if i in moved:
                local = _qnorm(_qmul(_qconj(world[bone.parent]), source_world[source_index[bone.name]][0]))
                target.rotations[frame][i] = local
            world.append(_qnorm(local) if bone.parent < 0 else _qnorm(_qmul(world[bone.parent], local)))


def retarget(source: Animation, source_skeleton: Animation, target_skeleton: Animation, skeleton_name: str,
             offset_bones: Iterable[str] = OFFSET_BONES, renames: Optional[Dict[str, str]] = None) -> Animation:
    """Retargets an animation onto another skeleton.

    Args:
        source (Animation): The animation to convert.
        source_skeleton (Animation): The source skeleton's bind pose (its `animations/skeletons/<name>.anim`).
        target_skeleton (Animation): The target skeleton's bind pose.
        skeleton_name (str): The target skeleton's name, written into the new animation.
        offset_bones (Iterable[str]): Bones moved by the source's offset from its bind pose.
        renames (Optional[Dict[str, str]]): Source bone name -> the target bone it drives, for bones the skeletons name differently.

    Returns:
        Animation: The animation on the target skeleton.
    """
    if renames:
        source, source_skeleton = renamed(source, renames), renamed(source_skeleton, renames)
    source_index = {bone.name: i for i, bone in enumerate(source.bones)}
    source_bind = {bone.name: i for i, bone in enumerate(source_skeleton.bones)}
    offset_bones = set(offset_bones)
    frames = len(source.rotations)
    translations: List[List[Optional[Vec3]]] = [[] for _ in range(frames)]
    rotations: List[List[Optional[Quat]]] = [[] for _ in range(frames)]
    for target_bone, bone in enumerate(target_skeleton.bones):
        index = source_index.get(bone.name)
        bind = target_skeleton.translations[0][target_bone]
        for frame in range(frames):
            rotation = source.rotations[frame][index] if index is not None else None
            translation = source.translations[frame][index] if index is not None else None
            if translation is not None and not bone.name.startswith(COPIED_TRANSLATION_PREFIXES):
                if bone.name in offset_bones and bone.name in source_bind:
                    source_rest = source_skeleton.translations[0][source_bind[bone.name]]
                    translation = tuple(bind[k] + translation[k] - source_rest[k] for k in range(3))
                else:
                    translation = bind
            rotations[frame].append(rotation)
            translations[frame].append(translation)
    bones = [Bone(bone.name, bone.parent) for bone in target_skeleton.bones]
    target = Animation(7, source.unknown, source.frame_rate, skeleton_name, list(source.flags), source.length, bones, translations, rotations)
    source_worlds = [world_pose(source, source_skeleton, frame) for frame in range(len(source.rotations))]
    _match_world_rotations(source, source_worlds, target, target_skeleton)
    _anchor_props(source, source_worlds, target, target_skeleton)
    return target
