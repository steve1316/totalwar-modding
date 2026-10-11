"""Read WH3 animation headers and add fire markers (`FIRE_POS`) to animation metadata (`.anm.meta`) files."""

import struct
from dataclasses import dataclass
from typing import Optional, Tuple

from tools.glf_rebuild_animpack import ByteReader, pack_string

META_VERSION = 2
# The FIRE_POS tag name as it is stored, with its length prefix.
FIRE_POS_KEY = pack_string("FIRE_POS")
FIRE_POS_VERSION = 10
# The 6 bytes between a FIRE_POS's end time and its position. Every vanilla and GLF fire marker has them as zero.
FIRE_POS_PADDING = b"\x00" * 6
# How close to 1 the animroot quaternion's w must be for the animation to count as facing forward.
FORWARD_TOLERANCE = 0.01


@dataclass
class FirePos:
    """When and where a projectile leaves the animation."""

    # Seconds into the animation.
    time: float
    # Position relative to the animroot: x sideways, y up, z forward.
    position: Tuple[float, float, float]


@dataclass
class AnimHeader:
    """The parts of an `.anim` file the generator needs."""

    # Skeleton name, e.g. `humanoid01`.
    skeleton: str
    # Length in seconds.
    length: float
    # Static animroot rotation as (x, y, z, w), or None when the animroot moves or the format is not v8.
    root_rotation: Optional[Tuple[float, float, float, float]]


def read_fire_pos(meta: bytes) -> Optional[FirePos]:
    """Find the first fire marker in a meta file.

    Args:
        meta (bytes): `.anm.meta` bytes.

    Returns:
        The fire marker, or None when the file has none.
    """
    index = meta.find(FIRE_POS_KEY)
    if index < 0:
        return None
    offset = index + len(FIRE_POS_KEY) + 4
    time = struct.unpack_from("<f", meta, offset)[0]
    position = struct.unpack_from("<3f", meta, offset + 8 + len(FIRE_POS_PADDING))
    return FirePos(time, position)


def add_fire_pos(meta: Optional[bytes], fire: FirePos) -> bytes:
    """Append a fire marker to a meta file, or make a new meta file holding only the marker.

    Args:
        meta (Optional[bytes]): Existing `.anm.meta` bytes, or None to start a new file.
        fire (FirePos): The marker to add.

    Returns:
        The new meta bytes with the entry count raised by one.
    """
    base = meta if meta else struct.pack("<II", META_VERSION, 0)
    count = struct.unpack_from("<I", base, 4)[0]
    entry = FIRE_POS_KEY + struct.pack("<Iff", FIRE_POS_VERSION, fire.time, fire.time) + FIRE_POS_PADDING + struct.pack("<3f", *fire.position)
    return base[:4] + struct.pack("<I", count + 1) + base[8:] + entry


def read_anim_header(data: bytes) -> AnimHeader:
    """Read an `.anim` file's skeleton, length and static animroot rotation.

    Args:
        data (bytes): `.anim` bytes.

    Returns:
        The header. `root_rotation` is only read for v8 files whose animroot rotation is static.
    """
    reader = ByteReader(data)
    version = reader.unpack("<I")
    reader.raw(8)
    skeleton = reader.string()
    if version > 6:
        for _ in range(reader.unpack("<I")):
            reader.string()
    length = reader.unpack("<f")
    if version != 8:
        return AnimHeader(skeleton, length, None)

    bones = reader.unpack("<I")
    for _ in range(bones):
        reader.string()
        reader.raw(4)
    reader.raw(8)
    translation_bits = struct.unpack(f"<{bones}b", reader.raw(bones))
    rotation_bits = struct.unpack(f"<{bones}b", reader.raw(bones))
    translation_ranges, rotation_ranges = reader.unpack("<I"), reader.unpack("<I")
    reader.raw(translation_ranges * 24)
    rotation_range = struct.unpack("<8f", reader.raw(32)) if rotation_ranges else None
    reader.raw(max(rotation_ranges - 1, 0) * 32)
    if rotation_bits[0] >= 0:
        return AnimHeader(skeleton, length, None)

    # Walk the static frame: two counts, every static translation, then every static rotation in bone order. The animroot's rotation comes first.
    reader.raw(8 + sum({-12: 12, -3: 3}.get(bits, 0) for bits in translation_bits))
    if rotation_bits[0] == -8:
        rotation = tuple(value / 32767 for value in struct.unpack("<4h", reader.raw(8)))
    else:
        raw = struct.unpack("<4b", reader.raw(4))
        rotation = tuple(value / 127 * rotation_range[i] + rotation_range[4 + i] for i, value in enumerate(raw))
    return AnimHeader(skeleton, length, rotation)


def faces_forward(header: AnimHeader) -> bool:
    """Tell whether an animation keeps the unit facing forward, which a fire animation needs.

    Args:
        header (AnimHeader): The animation header.

    Returns:
        True when the static animroot rotation is the identity. A moving or unread animroot counts as not forward.
    """
    return header.root_rotation is not None and abs(abs(header.root_rotation[3]) - 1) < FORWARD_TOLERANCE


def faces_backward(header: AnimHeader) -> bool:
    """Tell whether an animation is known to turn the unit away from its target.

    Args:
        header (AnimHeader): The animation header.

    Returns:
        True only when the static animroot rotation was read and is not the identity. A moving or unread animroot counts as not backward.
    """
    return header.root_rotation is not None and not faces_forward(header)
