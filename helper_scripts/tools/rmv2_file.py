"""Read Total War: Warhammer 3 `.rigid_model_v2` models, plus the `.wsmodel` and material XML files that point at them.

Reads RMV2 versions 6 to 8. The layout follows TheAssetEditor's `Shared/GameFiles/RigidModel` (ModelFactory, WeightedMaterial and the vertex
creators). Only the weighted material header is read, which covers characters, props and every other unit mesh. Vertices come back as numpy arrays.
"""

import struct
import xml.etree.ElementTree as ElementTree
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Tuple

import numpy as np

# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Formats

# Material types that use the weighted material header (TheAssetEditor `GetAllWeightedMaterials`).
WEIGHTED_MATERIALS = {58, 65, 68, 70, 71, 72, 73, 77, 78, 79, 80, 81, 82, 85, 96}

# Vertex format ids.
FORMAT_STATIC = 0
FORMAT_WEIGHTED = 3
FORMAT_CINEMATIC = 4

# Texture type ids used in the rmv2 material header.
TEXTURE_DIFFUSE = 0
TEXTURE_NORMAL = 1
TEXTURE_MASK = 3
TEXTURE_BASE_COLOUR = 27

# File header: magic, version, lod count, 128-byte skeleton name.
FILE_HEADER = struct.Struct("<4sII128s")

# Lod headers: mesh count, vertex size, index size, first mesh offset, camera distance (+ lod level, quality and padding for v7/v8).
LOD_HEADER_V6 = struct.Struct("<IIIIf")
LOD_HEADER_V7 = struct.Struct("<IIIIfI4B")

# Mesh common header: material type, render flag, section size, vertex offset/count, index offset/count, bounding box, shader params.
COMMON_HEADER = struct.Struct("<HHIIIII6f12s10s10s")

# Weighted material header up to the counts, then 124 bytes of padding.
MATERIAL_HEADER = struct.Struct("<H32s256s256s2B3f36fiiIIIIII124x")

# Attachment point: 32-byte name, 3x4 matrix, bone index.
ATTACHMENT_POINT = struct.Struct("<32s12fi")

# Texture: type and 256-byte path.
TEXTURE = struct.Struct("<i256s")

# Vertex layouts as numpy dtypes. The v8 weighted formats add a colour at the end.
STATIC_VERTEX = np.dtype([("pos", "<f2", 4), ("uv", "<f2", 2), ("uv1", "<f2", 2), ("normal", "u1", 4), ("tangent", "u1", 4), ("binormal", "u1", 4),
                          ("colour", "u1", 4)])
WEIGHTED2_VERTEX = np.dtype([("pos", "<f2", 4), ("bone", "u1", 2), ("weight", "u1", 2), ("normal", "u1", 4), ("uv", "<f2", 2), ("binormal", "u1", 4),
                             ("tangent", "u1", 4)])
WEIGHTED4_VERTEX = np.dtype([("pos", "<f2", 4), ("bone", "u1", 4), ("weight", "u1", 4), ("normal", "u1", 4), ("uv", "<f2", 2), ("binormal", "u1", 4),
                             ("tangent", "u1", 4)])


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Data


@dataclass
class AttachmentPoint:
    """A named point on a mesh tied to a bone."""

    # Point name, e.g. `be_prop_1`.
    name: str
    # Row-major 3x4 matrix.
    matrix: Tuple[float, ...]
    # Skeleton bone index.
    bone: int


@dataclass
class Mesh:
    """One mesh of one lod."""

    # Material type id (65 = weighted, 68 = default, ...).
    material: int
    # Vertex format id (0 static, 3 weighted, 4 cinematic).
    vertex_format: int
    # Mesh name from the material header.
    name: str
    # Texture paths by texture type id.
    textures: Dict[int, str]
    # Attachment points of the mesh.
    attachment_points: List[AttachmentPoint]
    # Bone the whole mesh follows, or -1.
    matrix_index: int
    # Positions, float32 (n, 3).
    positions: np.ndarray
    # Normals, float32 (n, 3).
    normals: np.ndarray
    # Texture coordinates, float32 (n, 2).
    uvs: np.ndarray
    # Bone indices, uint8 (n, k), k = 0, 2 or 4.
    bone_indices: np.ndarray
    # Bone weights, float32 (n, k).
    bone_weights: np.ndarray
    # Triangle indices, uint16.
    indices: np.ndarray
    # Pivot point: a local offset added to every vertex before the mesh is placed (TheAssetEditor `Rmv2MeshNode.PivotPoint`).
    pivot: Tuple[float, float, float] = (0.0, 0.0, 0.0)


@dataclass
class RigidModel:
    """A parsed `.rigid_model_v2`."""

    # File version (6, 7 or 8).
    version: int
    # Skeleton name, empty for unskinned props.
    skeleton: str
    # Meshes per lod.
    lods: List[List[Mesh]] = field(default_factory=list)


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Reading


def _text(raw: bytes) -> str:
    """Decodes a zero-padded fixed-length string."""
    return raw.split(b"\0", 1)[0].decode("utf-8", "replace").strip()


def _unpack_normals(raw: np.ndarray) -> np.ndarray:
    """Byte normals to floats, scaled by w when w is positive (TheAssetEditor `CreatVector3_FromByte`)."""
    values = raw.astype(np.float32) / 255.0 * 2.0 - 1.0
    xyz, w = values[:, :3], values[:, 3:4]
    return np.where(w > 0, xyz * w, xyz)


def _unpack_positions(raw: np.ndarray) -> np.ndarray:
    """Half positions to floats, scaled by w when w is not zero (TheAssetEditor `CreatVector4HalfFloat2`)."""
    values = raw.astype(np.float32)
    xyz, w = values[:, :3], values[:, 3:4]
    return np.where(w != 0, xyz * w, xyz)


def _read_vertices(data: bytes, offset: int, count: int, vertex_format: int, version: int) -> Tuple[np.ndarray, ...]:
    """Reads one mesh's vertices.

    Args:
        data (bytes): File bytes.
        offset (int): First vertex offset.
        count (int): Vertex count.
        vertex_format (int): Vertex format id.
        version (int): RMV2 version.

    Returns:
        Tuple[np.ndarray, ...]: Positions, normals, uvs, bone indices and bone weights.

    Raises:
        ValueError: When the vertex format is not supported.
    """
    if vertex_format == FORMAT_STATIC:
        verts = np.frombuffer(data, STATIC_VERTEX, count, offset)
        # The default format stores normals with X and Z swapped.
        normals = _unpack_normals(verts["normal"])[:, ::-1]
        empty = np.zeros((count, 0))
        return _unpack_positions(verts["pos"]), normals, verts["uv"].astype(np.float32), empty.astype(np.uint8), empty.astype(np.float32)
    if vertex_format in (FORMAT_WEIGHTED, FORMAT_CINEMATIC):
        base = WEIGHTED2_VERTEX if vertex_format == FORMAT_WEIGHTED else WEIGHTED4_VERTEX
        dtype = np.dtype(base.descr + [("colour", "u1", 4)]) if version == 8 else base
        verts = np.frombuffer(data, dtype, count, offset)
        weights = verts["weight"].astype(np.float32) / 255.0
        return _unpack_positions(verts["pos"]), _unpack_normals(verts["normal"]), verts["uv"].astype(np.float32), verts["bone"].copy(), weights
    raise ValueError(f"unsupported vertex format {vertex_format}")


def _vertex_size(vertex_format: int, version: int) -> int:
    """Bytes per vertex for a format and version."""
    if vertex_format == FORMAT_STATIC:
        return STATIC_VERTEX.itemsize
    base = WEIGHTED2_VERTEX if vertex_format == FORMAT_WEIGHTED else WEIGHTED4_VERTEX
    return base.itemsize + (4 if version == 8 else 0)


def _read_mesh(data: bytes, start: int, version: int) -> Tuple[Mesh, int]:
    """Reads one mesh block.

    Args:
        data (bytes): File bytes.
        start (int): Block offset.
        version (int): RMV2 version.

    Returns:
        Tuple[Mesh, int]: The mesh and the block size.

    Raises:
        ValueError: When the material or vertex format is not supported, or the sizes do not add up.
    """
    header = COMMON_HEADER.unpack_from(data, start)
    material, _, section_size, vertex_offset, vertex_count, index_offset, index_count = header[:7]
    if material not in WEIGHTED_MATERIALS:
        raise ValueError(f"unsupported material type {material}")
    offset = start + COMMON_HEADER.size
    fields = MATERIAL_HEADER.unpack_from(data, offset)
    offset += MATERIAL_HEADER.size
    vertex_format, name = fields[0], _text(fields[1])
    matrix_index = fields[45]
    point_count, texture_count, string_count, float_count, int_count, vec4_count = fields[47:53]

    points = []
    for _ in range(point_count):
        values = ATTACHMENT_POINT.unpack_from(data, offset)
        offset += ATTACHMENT_POINT.size
        points.append(AttachmentPoint(_text(values[0]), tuple(values[1:13]), values[13]))
    textures: Dict[int, str] = {}
    for _ in range(texture_count):
        kind, path = TEXTURE.unpack_from(data, offset)
        offset += TEXTURE.size
        textures[kind] = _text(path)
    # Parameter lists: each entry is an int32 index then the value (string = int16 length + utf-8 bytes).
    for _ in range(string_count):
        length = struct.unpack_from("<h", data, offset + 4)[0]
        offset += 6 + length
    offset += float_count * 8 + int_count * 8 + vec4_count * 20
    if offset != start + vertex_offset:
        raise ValueError(f"material header of {name} ends at {offset - start}, vertices start at {vertex_offset}")

    size = _vertex_size(vertex_format, version)
    if (index_offset - vertex_offset) != size * vertex_count:
        raise ValueError(f"vertex size mismatch in {name}: format {vertex_format} is {size} bytes")
    positions, normals, uvs, bones, weights = _read_vertices(data, start + vertex_offset, vertex_count, vertex_format, version)
    indices = np.frombuffer(data, "<u2", index_count, start + index_offset).copy()
    mesh = Mesh(material, vertex_format, name, textures, points, matrix_index, positions, normals, uvs, bones, weights, indices, tuple(fields[6:9]))
    return mesh, section_size


def read_rmv2(data: bytes, max_lods: Optional[int] = None) -> RigidModel:
    """Parses a `.rigid_model_v2` file.

    Args:
        data (bytes): File bytes.
        max_lods (Optional[int]): Read only this many lods (None reads all).

    Returns:
        RigidModel: The model.

    Raises:
        ValueError: When the file is not an RMV2 file or uses an unsupported version.
    """
    magic, version, lod_count, skeleton = FILE_HEADER.unpack_from(data, 0)
    if magic != b"RMV2":
        raise ValueError("not an RMV2 file")
    if version not in (6, 7, 8):
        raise ValueError(f"unsupported RMV2 version {version}")
    lod_struct = LOD_HEADER_V6 if version == 6 else LOD_HEADER_V7
    model = RigidModel(version, _text(skeleton))
    for lod in range(lod_count if max_lods is None else min(lod_count, max_lods)):
        mesh_count, _, _, first_offset = lod_struct.unpack_from(data, FILE_HEADER.size + lod * lod_struct.size)[:4]
        meshes, offset = [], first_offset
        for _ in range(mesh_count):
            mesh, size = _read_mesh(data, offset, version)
            meshes.append(mesh)
            offset += size
        model.lods.append(meshes)
    return model


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# WsModel and material XML


def read_wsmodel(text: str) -> Tuple[str, Dict[Tuple[int, int], str]]:
    """Parses a `.wsmodel` file.

    Args:
        text (str): File text.

    Returns:
        Tuple[str, Dict[Tuple[int, int], str]]: The rmv2 path and material XML paths by (lod index, part index).
    """
    root = ElementTree.fromstring(text.lstrip("\ufeff"))
    geometry = root.findtext("geometry", "").strip()
    materials = {}
    for item in root.iter("material"):
        materials[(int(item.get("lod_index", 0)), int(item.get("part_index", 0)))] = (item.text or "").strip()
    return geometry, materials


def read_material_xml(text: str) -> Dict[str, str]:
    """Parses a `.xml.material` file.

    Args:
        text (str): File text.

    Returns:
        Dict[str, str]: Texture paths by slot name, e.g. `t_xml_base_colour`.
    """
    root = ElementTree.fromstring(text.lstrip("\ufeff"))
    return {(t.findtext("slot") or "").strip(): (t.findtext("source") or "").strip() for t in root.iter("texture")}
