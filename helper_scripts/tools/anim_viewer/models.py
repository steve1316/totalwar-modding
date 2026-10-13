"""Export a unit's 3D model for the animation viewer.

Resolves a `.variantmeshdefinition` to its meshes (first mesh of each slot), pulls the `.wsmodel`, `.rigid_model_v2`, material and texture files
from loose folders, mod packs or the vanilla packs, and writes `models/<side>.json` plus `models/<side>.bin` (vertex buffers) and base colour images.
Skinned meshes carry the skeleton's inverse bind matrices, built from the skeleton `.anim` bind pose. Meshes in a slot with an `attach_point` are
drawn rigidly on that bone.
"""

import hashlib
import io
import json
import os
import re
import xml.etree.ElementTree as ElementTree
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, field
from typing import Dict, Iterable, List, Optional, Tuple

import numpy as np
from PIL import Image

from core.utilities import run_rpfm_cli
from tools.anim_file import Animation
from tools.anim_retarget import _world
from tools.glf_rebuild_animpack import VANILLA_DATA_DIR
from tools.rmv2_file import FORMAT_STATIC, TEXTURE_BASE_COLOUR, TEXTURE_DIFFUSE, read_material_xml, read_rmv2, read_wsmodel

# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Settings

# Cache of pack listings and extracted files, shared between runs.
CACHE_DIR = "./_diag/anim_viewer_cache"

# Vanilla packs searched for models and textures.
VANILLA_PACK_PATTERN = re.compile(r"^(variants|models|warmachines|commontextures|data\.pack)")

# Files per rpfm extract call (Windows command-line limit).
EXTRACT_BATCH = 20

# Largest texture side kept in the viewer.
MAX_TEXTURE = 1024

# Folder of variant mesh definitions, used to resolve VARIANT_MESH_REFERENCE names.
VARIANT_FOLDER = "variantmeshes/variantmeshdefinitions"

# sRGB DXGI formats Pillow cannot read, mapped to the same layout without sRGB (BC1, BC2, BC3, BC7, RGBA8, BGRA8).
SRGB_FORMATS = {72: 71, 75: 74, 78: 77, 99: 98, 29: 28, 91: 87}

# Material XML texture slots that hold the base colour, best first.
BASE_COLOUR_SLOTS = ("t_xml_base_colour", "t_xml_diffuse")


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Data


@dataclass
class Part:
    """One model file of a variant."""

    # Slot name, e.g. `body` or `weapon_2`.
    slot: str
    # Model path (`.wsmodel` or `.rigid_model_v2`).
    model: str
    # Bone the model is attached to, or None when skinned.
    attach: Optional[str] = None


@dataclass
class AssetSource:
    """Looks files up in loose folders, then mod packs, then the vanilla packs, and extracts them on demand."""

    # Loose folders searched first.
    folders: List[str]
    # Packs searched next, in order.
    packs: List[str]
    # Lowercase path to (pack path, path as the pack spells it).
    index: Dict[str, Tuple[str, str]] = field(default_factory=dict)
    # Lowercase path to a file in the loose folders.
    loose: Dict[str, str] = field(default_factory=dict)

    def __post_init__(self):
        for folder in reversed(self.folders):
            for root, _, names in os.walk(folder):
                for name in names:
                    full = os.path.join(root, name)
                    self.loose[_norm(os.path.relpath(full, folder))] = full
        vanilla = sorted(os.path.join(VANILLA_DATA_DIR, n) for n in os.listdir(VANILLA_DATA_DIR) if n.endswith(".pack") and VANILLA_PACK_PATTERN.match(n))
        packs = self.packs + vanilla
        with ThreadPoolExecutor(8) as pool:
            listings = list(pool.map(_list_pack, packs))
        for pack, paths in zip(packs, listings):
            for path in paths:
                self.index.setdefault(path.lower(), (pack, path))

    def fetch(self, paths: Iterable[str]) -> Dict[str, bytes]:
        """Reads files by game path, extracting from packs in batches.

        Args:
            paths (Iterable[str]): Game paths, any case and slash style.

        Returns:
            Dict[str, bytes]: Contents by the normalised (lowercase, forward slash) path. Missing files are left out.
        """
        found: Dict[str, bytes] = {}
        wanted: Dict[str, List[Tuple[str, str]]] = {}
        for raw in paths:
            path = _norm(raw)
            if not path or path in found:
                continue
            if path in self.loose:
                found[path] = open(self.loose[path], "rb").read()
                continue
            if path not in self.index:
                continue
            pack, spelled = self.index[path]
            target = os.path.join(_pack_cache(pack), spelled)
            if os.path.exists(target):
                found[path] = open(target, "rb").read()
            else:
                wanted.setdefault(pack, []).append((path, spelled))
        for pack, items in wanted.items():
            dest = _pack_cache(pack)
            for start in range(0, len(items), EXTRACT_BATCH):
                args = ["pack", "extract", "--pack-path", pack]
                for _, spelled in items[start:start + EXTRACT_BATCH]:
                    args += ["--file-path", f"{spelled};{dest}"]
                run_rpfm_cli(args, capture_output=True)
            for path, spelled in items:
                target = os.path.join(dest, spelled)
                if os.path.exists(target):
                    found[path] = open(target, "rb").read()
        return found


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Helpers


def _norm(path: str) -> str:
    """Normalises a game path: lowercase, forward slashes, no leading slash."""
    return path.strip().replace("\\", "/").lstrip("/").lower()


def _pack_cache(pack: str) -> str:
    """Extract folder of one pack inside the cache."""
    key = hashlib.sha1(os.path.abspath(pack).lower().encode()).hexdigest()[:10]
    return os.path.join(CACHE_DIR, "files", f"{os.path.basename(pack)}_{key}")


def _list_pack(pack: str) -> List[str]:
    """Lists a pack's files, cached by pack size and modified time.

    Args:
        pack (str): Pack path.

    Returns:
        List[str]: File paths inside the pack.
    """
    stat = os.stat(pack)
    cache = os.path.join(CACHE_DIR, "listings", f"{os.path.basename(pack)}_{stat.st_size}_{int(stat.st_mtime)}.txt")
    if os.path.exists(cache):
        return open(cache, encoding="utf-8").read().splitlines()
    output = run_rpfm_cli(["pack", "list", "--pack-path", pack], capture_output=True, text=True).stdout
    paths = [line.strip() for line in output.splitlines() if line.strip()]
    os.makedirs(os.path.dirname(cache), exist_ok=True)
    with open(cache, "w", encoding="utf-8") as f:
        f.write("\n".join(paths))
    return paths


def _quat_matrix(quat, position) -> np.ndarray:
    """4x4 matrix (column vectors) from a quaternion (x, y, z, w) and a position."""
    x, y, z, w = quat
    m = np.eye(4)
    m[:3, :3] = [[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                 [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                 [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]]
    m[:3, 3] = position
    return m


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Variant resolution


def resolve_variant(variant: str, source: AssetSource) -> List[Part]:
    """Lists the model of each slot of a variant, following VARIANT_MESH_REFERENCE links.

    Args:
        variant (str): A local `.variantmeshdefinition` file, or its game path.
        source (AssetSource): Where to look files up.

    Returns:
        List[Part]: One part per slot that has a mesh. Blood-pack stumps are skipped.

    Raises:
        FileNotFoundError: When the variant or a referenced variant cannot be found.
    """
    if os.path.exists(variant):
        text = open(variant, "rb").read()
    else:
        text = source.fetch([variant]).get(_norm(variant))
        if text is None:
            raise FileNotFoundError(variant)
    parts: Dict[str, Part] = {}
    references: List[Tuple[str, Optional[str]]] = []
    root = ElementTree.fromstring(text.decode("utf-8-sig", "replace"))
    for element in root.findall("VARIANT_MESH_REFERENCE"):
        references.append((element.get("definition", ""), None))
    for element in root.iter("SLOT"):
        attach = element.get("attach_point")
        # A reference inside a slot puts the referenced meshes on that slot's attach point.
        for reference in element.findall("VARIANT_MESH_REFERENCE"):
            references.append((reference.get("definition", ""), attach))
        meshes = element.findall("VARIANT_MESH")
        if not meshes or not meshes[0].get("model"):
            continue
        if any((m.text or "").strip() == "is_stump" for m in meshes[0].iter("META_DATA")):
            continue
        slot = element.get("name", "")
        parts[slot] = Part(slot, meshes[0].get("model"), attach)
    # Referenced definitions fill the slots this file leaves empty.
    for name, attach in references:
        path = name if "/" in name.replace("\\", "/") else f"{VARIANT_FOLDER}/{name}"
        for part in resolve_variant(path, source):
            parts.setdefault(part.slot, Part(part.slot, part.model, part.attach or attach))
    return list(parts.values())


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Export


def _texture_image(data: bytes) -> Tuple[bytes, str, bool]:
    """Converts a DDS texture to a downscaled JPEG, or PNG when it has real alpha.

    Args:
        data (bytes): DDS bytes.

    Returns:
        Tuple[bytes, str, bool]: Image bytes, file extension and whether alpha is used.
    """
    # A DX10 header keeps the DXGI format at byte 128. Swap sRGB formats for their plain twin, the colour data is the same.
    if data[84:88] == b"DX10" and int.from_bytes(data[128:132], "little") in SRGB_FORMATS:
        data = data[:128] + SRGB_FORMATS[int.from_bytes(data[128:132], "little")].to_bytes(4, "little") + data[132:]
    image = Image.open(io.BytesIO(data))
    image.load()
    if max(image.size) > MAX_TEXTURE:
        scale = MAX_TEXTURE / max(image.size)
        image = image.resize((max(1, int(image.width * scale)), max(1, int(image.height * scale))), Image.LANCZOS)
    has_alpha = image.mode in ("RGBA", "LA") and image.getchannel("A").getextrema()[0] < 250
    out = io.BytesIO()
    if has_alpha:
        image.convert("RGBA").save(out, "PNG", optimize=True)
        return out.getvalue(), "png", True
    image.convert("RGB").save(out, "JPEG", quality=88)
    return out.getvalue(), "jpg", False


def export_model(side: str, variant: str, skeleton_name: str, skeleton: Animation, source: AssetSource, out: str) -> Dict:
    """Writes one side's model files into `<out>/models`.

    Args:
        side (str): File stem, e.g. `source`.
        variant (str): Variant mesh definition (local file or game path).
        skeleton_name (str): Skeleton the side's animations use.
        skeleton (Animation): That skeleton's bind pose.
        source (AssetSource): Where to look files up.
        out (str): Viewer output folder.

    Returns:
        Dict: Summary with `meshes`, `vertices`, `bin_bytes`, `textures` and `missing` (paths that were not found).
    """
    folder = os.path.join(out, "models")
    os.makedirs(folder, exist_ok=True)
    parts = resolve_variant(variant, source)
    missing: List[str] = []

    # Stage 1: models. A wsmodel names its rmv2 and the material XML of each part. A bare rmv2 uses the wsmodel next to it if any.
    for part in parts:
        sibling = re.sub(r"\.rigid_model_v2$", ".wsmodel", _norm(part.model))
        if sibling != _norm(part.model) and (sibling in source.index or sibling in source.loose):
            part.model = sibling
    files = source.fetch(p.model for p in parts)
    geometry: Dict[str, Tuple[str, Dict[Tuple[int, int], str]]] = {}
    for part in parts:
        path = _norm(part.model)
        if path not in files:
            missing.append(part.model)
        elif path.endswith(".wsmodel"):
            geometry[path] = read_wsmodel(files[path].decode("utf-8-sig", "replace"))
        else:
            geometry[path] = (path, {})
    files.update(source.fetch([g for g, _ in geometry.values()] + [m for _, mats in geometry.values() for (lod, _), m in mats.items() if lod == 0]))

    # Stage 2: meshes and their base colour textures.
    meshes = []
    for part in parts:
        path = _norm(part.model)
        if path not in geometry:
            continue
        rmv2_path, materials = geometry[path]
        if _norm(rmv2_path) not in files:
            missing.append(rmv2_path)
            continue
        model = read_rmv2(files[_norm(rmv2_path)], max_lods=1)
        for index, mesh in enumerate(model.lods[0]):
            texture, alpha_hint = None, False
            material_path = materials.get((0, index))
            if material_path and _norm(material_path) in files:
                slots = read_material_xml(files[_norm(material_path)].decode("utf-8-sig", "replace"))
                texture = next((slots[s] for s in BASE_COLOUR_SLOTS if slots.get(s)), None)
                alpha_hint = "alpha_on" in material_path.lower()
            if not texture:
                texture = mesh.textures.get(TEXTURE_BASE_COLOUR) or mesh.textures.get(TEXTURE_DIFFUSE)
            meshes.append((part, mesh, texture, alpha_hint))
    images = source.fetch(t for _, _, t, _ in meshes if t)

    # Stage 3: write the buffers, images and the json.
    names = [b.name for b in skeleton.bones]
    inverse = [np.linalg.inv(_quat_matrix(q, p)) for q, p in _world(skeleton, skeleton, 0)]
    blob = bytearray()
    texture_files: Dict[str, Tuple[str, bool]] = {}
    entries = []

    def put(array: np.ndarray) -> int:
        offset = len(blob)
        blob.extend(array.tobytes())
        blob.extend(b"\0" * (-len(blob) % 4))
        return offset

    for part, mesh, texture, alpha_hint in meshes:
        skinned = part.attach is None and mesh.vertex_format != FORMAT_STATIC
        entry = {"slot": part.slot, "name": mesh.name, "attach": part.attach, "skinned": skinned, "count": len(mesh.positions), "index_count": len(mesh.indices)}
        # A rigid prop is moved by its pivot point first, then placed on its bone. Without it a sword sits centred on the hand, not by its grip.
        positions = mesh.positions if skinned else mesh.positions + np.array(mesh.pivot, np.float32)
        entry["position"] = put(positions.astype("<f4"))
        entry["normal"] = put(mesh.normals.astype("<f4"))
        entry["uv"] = put(mesh.uvs.astype("<f4"))
        if skinned:
            bones = np.zeros((len(mesh.positions), 4), np.uint16)
            weights = np.zeros((len(mesh.positions), 4), np.float32)
            k = mesh.bone_indices.shape[1]
            bones[:, :k] = mesh.bone_indices
            weights[:, :k] = mesh.bone_weights
            weights /= np.maximum(weights.sum(1, keepdims=True), 1e-6)
            entry["skin_index"] = put(bones.astype("<u2"))
            entry["skin_weight"] = put(weights.astype("<f4"))
        entry["index"] = put(mesh.indices.astype("<u2"))
        if texture and _norm(texture) in images:
            if _norm(texture) not in texture_files:
                try:
                    # Images are named after their game path, so models sharing a texture share one file.
                    stem = "tex_" + hashlib.sha1(_norm(texture).encode()).hexdigest()[:12]
                    done = [e for e in ("jpg", "png") if os.path.exists(os.path.join(folder, f"{stem}.{e}"))]
                    if done:
                        name, alpha = f"{stem}.{done[0]}", done[0] == "png"
                    else:
                        data, ext, alpha = _texture_image(images[_norm(texture)])
                        name = f"{stem}.{ext}"
                        with open(os.path.join(folder, name), "wb") as f:
                            f.write(data)
                    texture_files[_norm(texture)] = (name, alpha)
                except Exception as error:
                    missing.append(f"{texture} ({error})")
                    texture_files[_norm(texture)] = ("", False)
            name, alpha = texture_files[_norm(texture)]
            if name:
                entry["texture"] = name
                entry["alpha"] = alpha or alpha_hint
        elif texture:
            missing.append(texture)
        entries.append(entry)

    with open(os.path.join(folder, f"{side}.bin"), "wb") as f:
        f.write(blob)
    doc = {"variant": variant, "skeleton": skeleton_name, "bones": names, "inverse_bind": [[round(v, 6) for v in m.T.flatten()] for m in inverse],
           "bin": f"{side}.bin", "meshes": entries, "missing": sorted(set(missing))}
    with open(os.path.join(folder, f"{side}.json"), "w", encoding="utf-8") as f:
        json.dump(doc, f, separators=(",", ":"))
    return {"meshes": len(entries), "vertices": sum(e["count"] for e in entries), "bin_bytes": len(blob), "textures": len(texture_files),
            "missing": doc["missing"]}
