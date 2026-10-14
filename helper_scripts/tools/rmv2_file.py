"""Read and write Total War: Warhammer 3 `.rigid_model_v2` models, plus the `.wsmodel` and material XML files that point at them.

Reads RMV2 versions 6 to 8. The layout follows TheAssetEditor's `Shared/GameFiles/RigidModel` (ModelFactory, WeightedMaterial and the vertex
creators). Only the weighted material header is read, which covers characters, props and every other unit mesh. Vertices come back as numpy arrays.

Each mesh also keeps its raw blocks (headers, attachment points, textures, parameters and vertex records), so `write_rmv2` writes a file back
byte for byte. Tools edit a model through `set_positions`, `set_skin` and `set_attachment_points`, which change both the arrays and the raw blocks.
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

# Inside the common header: section size, vertex offset, vertex count, index offset and index count, then the bounding box.
COMMON_SIZES = struct.Struct("<IIIII")
COMMON_SIZES_AT = 4
BOUNDS = struct.Struct("<6f")
BOUNDS_AT = 24

# Inside the weighted material header: the attachment point and texture counts.
MATERIAL_COUNTS = struct.Struct("<II")
MATERIAL_COUNTS_AT = 712

# Start of a lod header: mesh count, vertex bytes, index bytes and first mesh offset.
LOD_SIZES = struct.Struct("<IIII")

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
class MeshBlocks:
    """The raw bytes of one mesh block, kept so a model can be written back unchanged."""

    # Common header (material type, sizes, bounding box, shader name).
    common: bytes
    # Weighted material header, padding included.
    material: bytes
    # Attachment point records.
    points: bytes
    # Texture records.
    textures: bytes
    # String, float, int and vec4 parameter lists.
    params: bytes
    # Vertex records as a numpy structured array.
    vertices: np.ndarray


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
    # Raw blocks used by `write_rmv2`.
    blocks: Optional[MeshBlocks] = None


@dataclass
class RigidModel:
    """A parsed `.rigid_model_v2`."""

    # File version (6, 7 or 8).
    version: int
    # Skeleton name, empty for unskinned props.
    skeleton: str
    # Meshes per lod.
    lods: List[List[Mesh]] = field(default_factory=list)
    # Raw lod headers. The camera distance, lod level and quality are kept from these.
    lod_headers: List[bytes] = field(default_factory=list)


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


def _vertex_dtype(vertex_format: int, version: int) -> np.dtype:
    """Vertex record layout for a format and version.

    Args:
        vertex_format (int): Vertex format id.
        version (int): RMV2 version.

    Returns:
        np.dtype: The record dtype.

    Raises:
        ValueError: When the vertex format is not supported.
    """
    if vertex_format == FORMAT_STATIC:
        return STATIC_VERTEX
    if vertex_format in (FORMAT_WEIGHTED, FORMAT_CINEMATIC):
        base = WEIGHTED2_VERTEX if vertex_format == FORMAT_WEIGHTED else WEIGHTED4_VERTEX
        return np.dtype(base.descr + [("colour", "u1", 4)]) if version == 8 else base
    raise ValueError(f"unsupported vertex format {vertex_format}")


def _unpack_vertices(verts: np.ndarray, vertex_format: int) -> Tuple[np.ndarray, ...]:
    """Unpacks vertex records.

    Args:
        verts (np.ndarray): Vertex records.
        vertex_format (int): Vertex format id.

    Returns:
        Tuple[np.ndarray, ...]: Positions, normals, uvs, bone indices and bone weights.
    """
    if vertex_format == FORMAT_STATIC:
        # The default format stores normals with X and Z swapped.
        normals = _unpack_normals(verts["normal"])[:, ::-1]
        empty = np.zeros((len(verts), 0))
        return _unpack_positions(verts["pos"]), normals, verts["uv"].astype(np.float32), empty.astype(np.uint8), empty.astype(np.float32)
    weights = verts["weight"].astype(np.float32) / 255.0
    return _unpack_positions(verts["pos"]), _unpack_normals(verts["normal"]), verts["uv"].astype(np.float32), verts["bone"].copy(), weights


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
    material_start = start + COMMON_HEADER.size
    fields = MATERIAL_HEADER.unpack_from(data, material_start)
    offset = points_start = material_start + MATERIAL_HEADER.size
    vertex_format, name = fields[0], _text(fields[1])
    matrix_index = fields[45]
    point_count, texture_count, string_count, float_count, int_count, vec4_count = fields[47:53]

    points = []
    for _ in range(point_count):
        values = ATTACHMENT_POINT.unpack_from(data, offset)
        offset += ATTACHMENT_POINT.size
        points.append(AttachmentPoint(_text(values[0]), tuple(values[1:13]), values[13]))
    textures: Dict[int, str] = {}
    textures_start = offset
    for _ in range(texture_count):
        kind, path = TEXTURE.unpack_from(data, offset)
        offset += TEXTURE.size
        textures[kind] = _text(path)
    # Parameter lists: each entry is an int32 index then the value (string = int16 length + utf-8 bytes).
    params_start = offset
    for _ in range(string_count):
        length = struct.unpack_from("<h", data, offset + 4)[0]
        offset += 6 + length
    offset += float_count * 8 + int_count * 8 + vec4_count * 20
    if offset != start + vertex_offset:
        raise ValueError(f"material header of {name} ends at {offset - start}, vertices start at {vertex_offset}")

    dtype = _vertex_dtype(vertex_format, version)
    if (index_offset - vertex_offset) != dtype.itemsize * vertex_count:
        raise ValueError(f"vertex size mismatch in {name}: format {vertex_format} is {dtype.itemsize} bytes")
    verts = np.frombuffer(data, dtype, vertex_count, start + vertex_offset).copy()
    positions, normals, uvs, bones, weights = _unpack_vertices(verts, vertex_format)
    indices = np.frombuffer(data, "<u2", index_count, start + index_offset).copy()
    blocks = MeshBlocks(data[start:material_start], data[material_start:points_start], data[points_start:textures_start], data[textures_start:params_start],
                        data[params_start:offset], verts)
    mesh = Mesh(material, vertex_format, name, textures, points, matrix_index, positions, normals, uvs, bones, weights, indices, tuple(fields[6:9]), blocks)
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
        header_start = FILE_HEADER.size + lod * lod_struct.size
        model.lod_headers.append(data[header_start:header_start + lod_struct.size])
        mesh_count, _, _, first_offset = lod_struct.unpack_from(data, header_start)[:4]
        meshes, offset = [], first_offset
        for _ in range(mesh_count):
            mesh, size = _read_mesh(data, offset, version)
            meshes.append(mesh)
            offset += size
        model.lods.append(meshes)
    return model


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Editing


def set_positions(mesh: Mesh, positions: np.ndarray) -> None:
    """Replaces a mesh's vertex positions and refits its bounding box. Vertices that did not move keep their stored bytes.

    Positions are half floats stored as xyz / w with w in [1, 2), like vanilla files, which keeps an extra bit of precision.

    Args:
        mesh (Mesh): A mesh read by `read_rmv2`.
        positions (np.ndarray): New positions, (n, 3).
    """
    moved = np.abs(positions - mesh.positions).max(1) > 1e-6
    w = np.clip(np.abs(positions[moved]).max(1, keepdims=True), 1.0, 1.999).astype(np.float16)
    packed = mesh.blocks.vertices["pos"].copy()
    packed[moved] = np.hstack([positions[moved] / w.astype(np.float32), w]).astype(np.float16)
    mesh.blocks.vertices["pos"] = packed
    mesh.positions = _unpack_positions(packed)
    common = bytearray(mesh.blocks.common)
    BOUNDS.pack_into(common, BOUNDS_AT, *mesh.positions.min(0), *mesh.positions.max(0))
    mesh.blocks.common = bytes(common)


def set_skin(mesh: Mesh, bones: np.ndarray, weights: np.ndarray) -> None:
    """Replaces a weighted mesh's bone indices and weights.

    Args:
        mesh (Mesh): A weighted mesh read by `read_rmv2`.
        bones (np.ndarray): Bone indices, uint8 (n, k) with k the format's influence count.
        weights (np.ndarray): Weights as bytes, uint8 (n, k). Each row should add up to 255.
    """
    mesh.blocks.vertices["bone"] = bones
    mesh.blocks.vertices["weight"] = weights
    mesh.bone_indices = bones.astype(np.uint8)
    mesh.bone_weights = weights.astype(np.float32) / 255.0


def set_attachment_points(mesh: Mesh, points: List[AttachmentPoint]) -> None:
    """Replaces a mesh's attachment points.

    Args:
        mesh (Mesh): A mesh read by `read_rmv2`.
        points (List[AttachmentPoint]): The new points.
    """
    mesh.attachment_points = list(points)
    mesh.blocks.points = b"".join(ATTACHMENT_POINT.pack(p.name.encode("utf-8"), *p.matrix, p.bone) for p in points)


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Writing


def _mesh_block(mesh: Mesh) -> bytes:
    """Encodes one mesh block from its raw blocks, with the sizes and counts recomputed.

    Args:
        mesh (Mesh): A mesh read by `read_rmv2`.

    Returns:
        bytes: The block.
    """
    blocks = mesh.blocks
    material = bytearray(blocks.material)
    MATERIAL_COUNTS.pack_into(material, MATERIAL_COUNTS_AT, len(blocks.points) // ATTACHMENT_POINT.size, len(blocks.textures) // TEXTURE.size)
    vertices, indices = blocks.vertices.tobytes(), mesh.indices.astype("<u2").tobytes()
    vertex_offset = len(blocks.common) + len(material) + len(blocks.points) + len(blocks.textures) + len(blocks.params)
    index_offset = vertex_offset + len(vertices)
    common = bytearray(blocks.common)
    COMMON_SIZES.pack_into(common, COMMON_SIZES_AT, index_offset + len(indices), vertex_offset, len(blocks.vertices), index_offset, len(mesh.indices))
    return b"".join([bytes(common), bytes(material), blocks.points, blocks.textures, blocks.params, vertices, indices])


def write_rmv2(model: RigidModel) -> bytes:
    """Encodes a model read by `read_rmv2` with every lod. Raw blocks are kept and the sizes, counts and offsets are recomputed.

    Args:
        model (RigidModel): The model.

    Returns:
        bytes: The `.rigid_model_v2` file bytes.

    Raises:
        ValueError: When a mesh has no raw blocks or the lod headers do not match the lods.
    """
    if len(model.lod_headers) != len(model.lods) or any(m.blocks is None for lod in model.lods for m in lod):
        raise ValueError("model was not read with every lod")
    offset = FILE_HEADER.size + sum(len(h) for h in model.lod_headers)
    lod_headers, bodies = [], []
    for header, meshes in zip(model.lod_headers, model.lods):
        blocks = [_mesh_block(m) for m in meshes]
        patched = bytearray(header)
        LOD_SIZES.pack_into(patched, 0, len(meshes), sum(m.blocks.vertices.nbytes for m in meshes), sum(len(m.indices) * 2 for m in meshes), offset)
        lod_headers.append(bytes(patched))
        bodies += blocks
        offset += sum(len(b) for b in blocks)
    head = FILE_HEADER.pack(b"RMV2", model.version, len(model.lods), model.skeleton.encode("utf-8"))
    return b"".join([head] + lod_headers + bodies)


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
