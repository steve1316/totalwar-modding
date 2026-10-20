"""Read and write Total War: Warhammer 3 `.anim` files.

Reads versions 4 to 8 (vanilla WH3 ships mostly 8, which is compressed) and writes version 7, the plain format modded animations use. The layout follows
TheAssetEditor's `Shared/GameFiles/Animation/AnimationFile.cs`. Every animation is expanded into full per-frame tracks for each bone, so tools can
edit bones without caring how the file stored them.
"""

import struct
from dataclasses import dataclass, field
from typing import List, Optional, Tuple

# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Data

# A translation (x, y, z).
Vec3 = Tuple[float, float, float]

# A rotation quaternion (x, y, z, w).
Quat = Tuple[float, float, float, float]


@dataclass
class Bone:
    """One bone of the animation's skeleton."""

    # Bone name, e.g. `pelvis`.
    name: str
    # Index of the parent bone, or -1 for the root.
    parent: int


@dataclass
class Animation:
    """An animation with a full track per bone: `translations[frame][bone]` and `rotations[frame][bone]`.

    A bone the file left out is None in every frame, meaning it keeps the skeleton's bind pose.
    """

    # File format version it was read from.
    version: int
    # Unknown header value, always 1.
    unknown: int
    # Frames per second.
    frame_rate: float
    # Skeleton name, e.g. `humanoid01`.
    skeleton: str
    # Flag strings from the header (version 7 and up).
    flags: List[str]
    # Play time in seconds.
    length: float
    # Bones in file order.
    bones: List[Bone]
    # Per frame, per bone translation, or None when the bone keeps its bind pose.
    translations: List[List[Optional[Vec3]]] = field(default_factory=list)
    # Per frame, per bone rotation, or None when the bone keeps its bind pose.
    rotations: List[List[Optional[Quat]]] = field(default_factory=list)


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Reading


class _Reader:
    """Little-endian reader over a byte buffer."""

    def __init__(self, data: bytes):
        self.data = data
        self.offset = 0

    def read(self, fmt: str):
        values = struct.unpack_from("<" + fmt, self.data, self.offset)
        self.offset += struct.calcsize("<" + fmt)
        return values if len(values) > 1 else values[0]

    def string(self) -> str:
        length = self.read("H")
        value = self.data[self.offset:self.offset + length].decode("utf-8")
        self.offset += length
        return value


def _short_quat(values) -> Quat:
    return tuple(v / 32767.0 for v in values)


def _read_header(reader: _Reader) -> Tuple[int, int, float, str, List[str], float, List[Bone]]:
    version, unknown, frame_rate = reader.read("I"), reader.read("I"), reader.read("f")
    skeleton = reader.string()
    flags = [reader.string() for _ in range(reader.read("I"))] if version > 6 else []
    length = reader.read("f")
    bones = []
    for _ in range(reader.read("I")):
        name = reader.string()
        bones.append(Bone(name, reader.read("i")))
    return version, unknown, frame_rate, skeleton, flags, length, bones


def _read_plain(reader: _Reader, bone_count: int, version: int) -> Tuple[List[List[Optional[Vec3]]], List[List[Optional[Quat]]]]:
    t_map = [reader.read("i") for _ in range(bone_count)]
    r_map = [reader.read("i") for _ in range(bone_count)]
    # Only version 7 has the static frame block.
    static_t, static_r = (reader.read("I"), reader.read("I")) if version == 7 else (0, 0)
    static_trans = [reader.read("3f") for _ in range(static_t)]
    static_rots = [_short_quat(reader.read("4h")) for _ in range(static_r)]
    dyn_t, dyn_r, frames = reader.read("i"), reader.read("i"), reader.read("i")
    dyn_trans, dyn_rots = [], []
    if dyn_t or dyn_r:
        for _ in range(frames):
            dyn_trans.append([reader.read("3f") for _ in range(dyn_t)])
            dyn_rots.append([_short_quat(reader.read("4h")) for _ in range(dyn_r)])
    # A pose with only static tracks still declares its frame count. The game divides by frames - 1, so 1 frame crashes it.
    frame_count = len(dyn_trans) or max(frames, 1)

    def pick(mapping: int, static: list, dynamic: list, frame: int):
        if mapping == -1:
            return None
        if mapping >= 10000:
            return static[mapping - 10000]
        return dynamic[frame][mapping] if dynamic else None

    translations = [[pick(m, static_trans, dyn_trans, f) for m in t_map] for f in range(frame_count)]
    rotations = [[pick(m, static_rots, dyn_rots, f) for m in r_map] for f in range(frame_count)]
    return translations, rotations


def _read_v8_part(reader: _Reader, bone_count: int) -> Tuple[List[List[Optional[Vec3]]], List[List[Optional[Quat]]]]:
    t_bits = [reader.read("b") for _ in range(bone_count)]
    r_bits = [reader.read("b") for _ in range(bone_count)]
    # Both range counts come first, then the translation ranges, then the rotation ranges.
    t_ranges_count, r_ranges_count = reader.read("I"), reader.read("I")
    t_ranges = [(reader.read("3f"), reader.read("3f")) for _ in range(t_ranges_count)]
    r_ranges = [(reader.read("4f"), reader.read("4f")) for _ in range(r_ranges_count)]

    def read_frame(dynamic: bool) -> Tuple[List[Optional[Vec3]], List[Optional[Quat]]]:
        trans: List[Optional[Vec3]] = [None] * bone_count
        rots: List[Optional[Quat]] = [None] * bone_count
        for bone in range(bone_count):
            bits = t_bits[bone] if dynamic else -t_bits[bone]
            if bits == 12:
                trans[bone] = reader.read("3f")
            elif bits == 3:
                low, high = t_ranges[bone]
                raw = reader.read("3b")
                trans[bone] = tuple(high[k] + raw[k] / 127.0 * low[k] for k in range(3))
        for bone in range(bone_count):
            bits = r_bits[bone] if dynamic else -r_bits[bone]
            if bits == 8:
                rots[bone] = _short_quat(reader.read("4h"))
            elif bits == 4:
                low, high = r_ranges[bone]
                raw = reader.read("4b")
                rots[bone] = tuple(high[k] + raw[k] / 127.0 * low[k] for k in range(4))
        return trans, rots

    static_t, static_r = reader.read("I"), reader.read("I")
    static = read_frame(False) if static_t or static_r else ([None] * bone_count, [None] * bone_count)
    dyn_t, dyn_r, frames = reader.read("I"), reader.read("I"), reader.read("I")
    dynamic = [read_frame(True) for _ in range(frames)] if dyn_t or dyn_r else []
    # A pose with only static tracks still declares its frame count. The game divides by frames - 1, so 1 frame crashes it.
    frame_count = len(dynamic) or max(frames, 1)
    translations, rotations = [], []
    for frame in range(frame_count):
        dyn = dynamic[frame] if dynamic else ([None] * bone_count, [None] * bone_count)
        translations.append([dyn[0][b] if dyn[0][b] is not None else static[0][b] for b in range(bone_count)])
        rotations.append([dyn[1][b] if dyn[1][b] is not None else static[1][b] for b in range(bone_count)])
    return translations, rotations


def _read_v8(reader: _Reader, bone_count: int) -> Tuple[List[List[Optional[Vec3]]], List[List[Optional[Quat]]]]:
    # Long animations are split into parts that play one after another.
    reader.read("I")
    translations, rotations = [], []
    for _ in range(reader.read("I")):
        part_trans, part_rots = _read_v8_part(reader, bone_count)
        translations += part_trans
        rotations += part_rots
    return translations, rotations


def read_anim(data: bytes) -> Animation:
    """Parses an animation.

    Args:
        data (bytes): The `.anim` file bytes.

    Returns:
        Animation: The animation with full per-bone tracks.

    Raises:
        ValueError: When the version is not 7 or 8, or bytes are left over.
    """
    reader = _Reader(data)
    version, unknown, frame_rate, skeleton, flags, length, bones = _read_header(reader)
    if version == 8:
        translations, rotations = _read_v8(reader, len(bones))
    elif 4 <= version <= 7:
        translations, rotations = _read_plain(reader, len(bones), version)
    else:
        raise ValueError(f"unsupported animation version {version}")
    if reader.offset != len(data):
        raise ValueError(f"{len(data) - reader.offset} bytes left over")
    return Animation(version, unknown, frame_rate, skeleton, flags, length, bones, translations, rotations)


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Writing


def _pack_string(value: str) -> bytes:
    encoded = value.encode("utf-8")
    return struct.pack("<H", len(encoded)) + encoded


def _quat_shorts(quat: Quat) -> Tuple[int, int, int, int]:
    return tuple(max(-32767, min(32767, int(v * 32767))) for v in quat)


def write_anim(anim: Animation) -> bytes:
    """Encodes an animation as version 7. Every bone with data gets its own per-frame track, and bones with none keep their bind pose.

    Args:
        anim (Animation): The animation.

    Returns:
        bytes: The `.anim` file bytes.
    """
    out = [struct.pack("<IIf", 7, anim.unknown, anim.frame_rate), _pack_string(anim.skeleton), struct.pack("<I", len(anim.flags))]
    out += [_pack_string(flag) for flag in anim.flags]
    out.append(struct.pack("<fI", anim.length, len(anim.bones)))
    out += [_pack_string(bone.name) + struct.pack("<i", bone.parent) for bone in anim.bones]

    t_bones = [b for b in range(len(anim.bones)) if anim.translations[0][b] is not None]
    r_bones = [b for b in range(len(anim.bones)) if anim.rotations[0][b] is not None]
    t_map = {bone: index for index, bone in enumerate(t_bones)}
    r_map = {bone: index for index, bone in enumerate(r_bones)}
    out.append(struct.pack(f"<{len(anim.bones)}i", *[t_map.get(b, -1) for b in range(len(anim.bones))]))
    out.append(struct.pack(f"<{len(anim.bones)}i", *[r_map.get(b, -1) for b in range(len(anim.bones))]))
    out.append(struct.pack("<II", 0, 0))
    out.append(struct.pack("<iii", len(t_bones), len(r_bones), len(anim.translations)))
    for frame in range(len(anim.translations)):
        out += [struct.pack("<3f", *anim.translations[frame][b]) for b in t_bones]
        out += [struct.pack("<4h", *_quat_shorts(anim.rotations[frame][b])) for b in r_bones]
    return b"".join(out)
