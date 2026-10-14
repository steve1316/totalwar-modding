"""Builds the Advisor Overhaul's own model: the vanilla campaign Advisor's body and hooded head, moved from his `advisor01` skeleton onto `humanoid01`.

`advisor01` shares the `humanoid01` bone names for the spine, arms, hands, legs, neck, head, jaw and eyes, and has 150 more bones (face, robe skirts,
cape chains, buttons, scrolls). Each vertex is re-weighted bone by bone:
- Robe and cape chains go to the nearest (by bind position) bone of the matching humanoid01 chain in `CHAINS`. The front and side skirts follow
  humanoid01's front skirt bones, which hang from the thighs, so the robe still moves with his legs.
- Arm twist bones keep their name (`TWIST_BONES`): they only turn about the arm, so their different spot along it does not matter.
- Any other bone keeps its name when humanoid01 has it within `MAX_SHARED_GAP` of the same bind position. Otherwise its weight goes to its closest
  ancestor that does. The face bones fold into `head` and `jaw`, buttons and scrolls into the spine or root.
- The middle and pinky fingers follow the index and ring finger bones of the same joint (`FINGER_STAND_INS`), as on vanilla humanoid01 models, so
  they curl with them around a grip. Folded into `hand` they stayed straight while the other fingers closed.

Vertices on the arms and legs (`MOVED_BONES`) are also moved from the advisor01 bind pose to the humanoid01 one, bone by bone. His arms are about
2 cm longer, and without the move the hands sit off the humanoid01 hand bones that hold the props. His hands are then shifted by the registry's
`model.hand_shift`, so his fist closes around the weapon grip like a vanilla hand does. The spine, neck and head bind poses already
match, and every other bone keeps its vertices in place (moving the 9-64 cm robe and cape offsets would tear the mesh).

The hoodless head drops the hood, which is its own piece of the head mesh (no shared vertices, its own texture islands). A full scalp and the
hair cards sit under it. The vanilla files are read and written with `tools.rmv2_file`, which keeps every other byte, and the models point at the
vanilla Advisor's materials and textures. The vanilla files come through `core.asset_source`, which caches pack listings and extracts. Run it
before `generators.advisor_overhaul`.

Usage:
    python -m generators.advisor_overhaul_model [--preview]

`--preview` also writes the body without the arm and leg move, plus a variant using it, into the Advisor gallery's preview folder.
"""

import argparse
import json
import os
import re
import shutil
import sys
from typing import Dict, List, Tuple

import numpy as np

from core.asset_source import AssetSource, norm
from tools.anim_file import Animation, read_anim
from tools.anim_retarget import quat_matrix, world_pose
from generators.advisor_overhaul import REGISTRY, prop_copy_path
from tools.rmv2_file import Mesh, read_rmv2, read_wsmodel, set_attachment_points, set_pivot, set_positions, set_skin, write_rmv2

# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Settings

# The mod source folder.
MOD = "../warhammer3_mods/!!advisor_overhaul"

# The vanilla packs holding the skeletons and models below.
VANILLA_PACKS = re.compile(r"^(anim2|variants|variants4)\.pack$")

# The Advisor gallery's preview folder, written by `--preview`. Each variant mesh definition in it becomes a "Preview: <name>" entry.
PREVIEWS = "./temp/anim_viewer_gallery_previews"

# The vanilla skeletons: the Advisor's own and the one the mod's hero uses.
SOURCE_SKELETON = "animations/skeletons/advisor01.anim"
TARGET_SKELETON = "animations/skeletons/humanoid01.anim"

# A vanilla humanoid01 mesh whose attachment points (one per humanoid01 bone) the new models copy: the Grey Wizard body.
POINTS_MODEL = "variantmeshes/wh_variantmodels/hu1/emp/emp_wizard/grey/body/emp_grey_wizard_body_01.rigid_model_v2"

# Folder of the vanilla Advisor's materials.
MATERIALS = "VariantMeshes/wh_variantmodels/hu1/misc/misc_advisor/materials"

# Each model built: output name -> (vanilla model, material per mesh part, drop the hood).
MODELS = {
    "advisor_overhaul_body_01": ("variantmeshes/wh_variantmodels/ad1/misc/misc_advisor_body_01_ad1.rigid_model_v2",
                                 [f"{MATERIALS}/misc_advisor_body_01_weighted4_alpha_off.xml.material"], False),
    "advisor_overhaul_head_01": ("variantmeshes/wh_variantmodels/ad1/misc/misc_advisor_head_01_ad1.rigid_model_v2",
                                 [f"{MATERIALS}/misc_advisor_head_01_weighted4_alpha_off.xml.material",
                                  f"{MATERIALS}/misc_advisor_head_01_weighted4_alpha_on.xml.material"], False),
    "advisor_overhaul_head_01_hoodless": ("variantmeshes/wh_variantmodels/ad1/misc/misc_advisor_head_01_ad1.rigid_model_v2",
                                          [f"{MATERIALS}/misc_advisor_head_01_weighted4_alpha_off.xml.material",
                                           f"{MATERIALS}/misc_advisor_head_01_weighted4_alpha_on.xml.material"], True),
}

# Game folder of the new models.
OUTPUT = "variantmeshes/wh_variantmodels/hu1/advisor_overhaul"

# Robe and cape chains: advisor01 bone pattern -> the humanoid01 bones it may go to (the nearest by bind position wins).
CHAINS = [
    (r"^skirt_(front|side)_left_", ["skirt_front_left_0", "skirt_front_left_1"]),
    (r"^skirt_(front|side)_right_", ["skirt_front_right_0", "skirt_front_right_1"]),
    (r"^skirt_back_", ["skirt_back_0", "skirt_back_1", "skirt_back_2"]),
    (r"^cape_middle_", ["cape_0", "cape_1", "cape_middle_0", "cape_middle_1"]),
    (r"^cape_shoulder_left_", ["shoulder_pad_left"]),
    (r"^cape_shoulder_right_", ["shoulder_pad_right"]),
    (r"^cape_left_", ["shoulder_pad_left", "cape_left_0", "cape_left_1"]),
    (r"^cape_right_", ["shoulder_pad_right", "cape_right_0", "cape_right_1"]),
]

# Twist bones that keep their name whatever their bind gap.
TWIST_BONES = r"^(upper|lower)arm_roll_(left|right)_0$"

# Largest bind gap for a bone to keep its name, in metres.
MAX_SHARED_GAP = 0.03

# Fingers humanoid01 lacks -> the finger whose bones they follow, for both the weights and the vertex move.
FINGER_STAND_INS = {"middle": "index", "pinky": "ring"}

# Bones whose vertices move from the advisor01 bind pose to the humanoid01 one (when they keep their name). Others use their closest such ancestor,
# or stay in place.
MOVED_BONES = r"^(upperarm|lowerarm|hand|finger|thumb|upperleg|lowerleg|foot|toe)_(left|right)(_\d)?$"


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Helpers


def quantise(weights: np.ndarray) -> np.ndarray:
    """Turns weight rows into bytes that add up to exactly 255 (largest remainder).

    Args:
        weights (np.ndarray): Float weights, (n, k), rows adding up to 1.

    Returns:
        np.ndarray: uint8 weights, (n, k).
    """
    scaled = weights * 255.0
    out = np.floor(scaled).astype(np.int32)
    short = 255 - out.sum(1)
    order = np.argsort(-(scaled - out), axis=1)
    for row in np.nonzero(short)[0]:
        out[row, order[row, :short[row]]] += 1
    return out.astype(np.uint8)


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Rig


class Rig:
    """The bone map and per-bone vertex moves from `advisor01` to `humanoid01`."""

    # The two skeletons.
    source: Animation
    target: Animation
    # Target bone index per source bone.
    target_of: np.ndarray
    # Per source bone, the 4x4 move applied to its vertices (identity for bones that stay in place).
    moves: np.ndarray
    # Per source bone that keeps its name: (name, bind gap in metres).
    gaps: List[Tuple[str, float]]

    def __init__(self, source: Animation, target: Animation, hand_shift: List[float]):
        self.source, self.target = source, target
        names = {b.name: i for i, b in enumerate(target.bones)}
        source_world, target_world = world_pose(source, source, 0), world_pose(target, target, 0)
        source_bind = [quat_matrix(q, p) for q, p in source_world]
        target_bind = [quat_matrix(q, p) for q, p in target_world]

        def gap(index: int) -> float:
            return float(np.linalg.norm(np.subtract(source_world[index][1], target_world[names[source.bones[index].name]][1])))

        def shared(index: int) -> bool:
            name = source.bones[index].name
            return name in names and (gap(index) <= MAX_SHARED_GAP or re.match(TWIST_BONES, name) is not None)

        self.target_of = np.zeros(len(source.bones), np.int64)
        self.moves = np.repeat(np.eye(4)[None], len(source.bones), 0)
        self.gaps = []
        source_names = {b.name: i for i, b in enumerate(source.bones)}
        for index, bone in enumerate(source.bones):
            # A finger humanoid01 lacks is handled as the finger it follows.
            finger = re.match(r"^finger_(middle|pinky)_", bone.name)
            if finger:
                index = source_names[bone.name.replace(finger.group(1), FINGER_STAND_INS[finger.group(1)], 1)]
            row = source_names[bone.name]
            if bone.name in names:
                self.gaps.append((bone.name, gap(index)))
            bone = source.bones[index]
            chain = next((c for pattern, c in CHAINS if re.match(pattern, bone.name)), None)
            if chain:
                self.target_of[row] = min((names[c] for c in chain), key=lambda t: np.linalg.norm(np.subtract(source_world[index][1], target_world[t][1])))
            else:
                walk = index
                while not shared(walk):
                    walk = source.bones[walk].parent
                self.target_of[row] = names[source.bones[walk].name]
            # The move comes from the bone itself or its closest moved ancestor.
            walk = index
            while walk >= 0 and not (re.match(MOVED_BONES, source.bones[walk].name) and shared(walk)):
                walk = source.bones[walk].parent
            if walk >= 0:
                self.moves[row] = target_bind[names[source.bones[walk].name]] @ np.linalg.inv(source_bind[walk])
            hand = re.match(r"^(hand|finger_\w+|thumb)_(left|right)(_\d)?$", source.bones[row].name)
            if hand:
                side = hand.group(2)
                shift = np.eye(4)
                shift[:3, 3] = target_bind[names[f"hand_{side}"]][:3, :3] @ np.multiply(hand_shift, (1, 1, 1 if side == "right" else -1))
                self.moves[row] = shift @ self.moves[row]

    def apply(self, mesh: Mesh, move: bool) -> Dict[Tuple[str, str], float]:
        """Re-weights one mesh to humanoid01 and, when asked, moves its vertices into the humanoid01 bind pose.

        Args:
            mesh (Mesh): A mesh read by `read_rmv2`.
            move (bool): Whether to move the arm and leg vertices.

        Returns:
            Dict[Tuple[str, str], float]: Weight totals by (source bone, target bone).
        """
        weights = mesh.bone_weights / np.maximum(mesh.bone_weights.sum(1, keepdims=True), 1e-6)
        if move:
            homogeneous = np.hstack([mesh.positions, np.ones((len(mesh.positions), 1), np.float32)])
            moved = np.einsum("nk,nkij,nj->ni", weights, self.moves[mesh.bone_indices], homogeneous)[:, :3]
            # Rounded to tenths of a millimetre, so vertices on bones that stay keep their stored bytes.
            set_positions(mesh, np.where(np.abs(moved - mesh.positions) < 1e-4, mesh.positions, moved).astype(np.float32))

        # Merge the influences that now share a bone, heaviest first.
        bones = self.target_of[mesh.bone_indices]
        merged_bones = np.zeros_like(bones)
        merged = np.zeros_like(weights)
        totals: Dict[Tuple[str, str], float] = {}
        for row in range(len(bones)):
            sums: Dict[int, float] = {}
            for source_bone, bone, weight in zip(mesh.bone_indices[row], bones[row], weights[row]):
                if weight > 0:
                    sums[int(bone)] = sums.get(int(bone), 0.0) + float(weight)
                    key = (self.source.bones[source_bone].name, self.target.bones[bone].name)
                    totals[key] = totals.get(key, 0.0) + float(weight)
            for slot, (bone, weight) in enumerate(sorted(sums.items(), key=lambda item: -item[1])):
                merged_bones[row, slot], merged[row, slot] = bone, weight
        set_skin(mesh, merged_bones.astype(np.uint8), quantise(merged))
        return totals


def drop_hood(mesh: Mesh) -> int:
    """Drops the hood from the head's main mesh: the connected piece (vertices welded by position) holding the top-most vertex.

    Args:
        mesh (Mesh): The head's first mesh.

    Returns:
        int: The number of triangles dropped.
    """
    _, weld = np.unique(np.round(mesh.positions, 4), axis=0, return_inverse=True)
    weld = weld.ravel()
    parent = np.arange(weld.max() + 1)

    def find(x: int) -> int:
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    triangles = mesh.indices.reshape(-1, 3)
    for a, b, c in weld[triangles]:
        parent[find(b)] = find(a)
        parent[find(c)] = find(a)
    hood = find(weld[int(np.argmax(mesh.positions[:, 1]))])
    keep = np.array([find(weld[t[0]]) != hood for t in triangles])
    mesh.indices = triangles[keep].ravel().astype(np.uint16)
    return int((~keep).sum())


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Build


def rerig(data: bytes, rig: Rig, points_data: bytes, hoodless: bool, move: bool = True) -> Tuple[bytes, Dict[Tuple[str, str], float]]:
    """Moves an `advisor01` model onto `humanoid01`.

    Args:
        data (bytes): The vanilla `.rigid_model_v2`.
        rig (Rig): The bone map and moves.
        points_data (bytes): A vanilla humanoid01 model whose attachment points are copied.
        hoodless (bool): Whether to drop the hood from the first mesh.
        move (bool): Whether to move the arm and leg vertices into the humanoid01 bind pose.

    Returns:
        Tuple[bytes, Dict[Tuple[str, str], float]]: The new file and the weight totals by (source bone, target bone).

    Raises:
        SystemExit: When the vanilla file does not round trip, or the result does not read back as a humanoid01 model.
    """
    model = read_rmv2(data)
    if write_rmv2(model) != data:
        sys.exit("a vanilla Advisor model does not round trip through tools.rmv2_file")
    points = read_rmv2(points_data, max_lods=1).lods[0][0].attachment_points
    model.skeleton = rig.target.skeleton
    totals: Dict[Tuple[str, str], float] = {}
    for mesh in (m for lod in model.lods for m in lod):
        for key, weight in rig.apply(mesh, move).items():
            totals[key] = totals.get(key, 0.0) + weight
        set_attachment_points(mesh, points)
    if hoodless:
        print(f"  dropped {drop_hood(model.lods[0][0])} hood triangles")
    out = write_rmv2(model)
    check = read_rmv2(out)
    if check.skeleton != rig.target.skeleton or any(int(m.bone_indices.max()) >= len(rig.target.bones) for lod in check.lods for m in lod):
        sys.exit("a new model does not read back as a humanoid01 model")
    return out, totals


def write_model(folder: str, game_folder: str, name: str, data: bytes, materials: List[str]) -> None:
    """Writes a `.rigid_model_v2` and the `.wsmodel` naming it and one material per mesh part of lod 0.

    Args:
        folder (str): Root folder the game path is written under.
        game_folder (str): Game folder of the model.
        name (str): File name without extension.
        data (bytes): The model.
        materials (List[str]): Material paths by part.
    """
    os.makedirs(os.path.join(folder, game_folder), exist_ok=True)
    with open(os.path.join(folder, game_folder, f"{name}.rigid_model_v2"), "wb") as f:
        f.write(data)
    lines = ['<model version="1">', f"  <geometry>{game_folder}/{name}.rigid_model_v2</geometry>", "  <materials>"]
    lines += [f'    <material part_index="{i}" lod_index="0">{m}</material>' for i, m in enumerate(materials)]
    lines += ["  </materials>", "</model>"]
    with open(os.path.join(folder, game_folder, f"{name}.wsmodel"), "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines))


def write_preview(rig: Rig, files: Dict[str, bytes]) -> None:
    """Writes the body without the arm and leg move, and a gallery preview variant wearing it with the hooded head.

    Args:
        rig (Rig): The bone map and moves.
        files (Dict[str, bytes]): The vanilla files by normalised path.
    """
    source, materials, _ = MODELS["advisor_overhaul_body_01"]
    data, _ = rerig(files[norm(source)], rig, files[norm(POINTS_MODEL)], False, move=False)
    folder = f"{OUTPUT}_preview"
    write_model(PREVIEWS, folder, "advisor_overhaul_body_01_unmoved", data, materials)
    variant = os.path.join(MOD, "variantmeshes", "variantmeshdefinitions", "advisor_overhaul_staff_and_sword.variantmeshdefinition")
    text = open(variant, encoding="utf-8").read().replace(f"{OUTPUT}/advisor_overhaul_body_01.wsmodel", f"{folder}/advisor_overhaul_body_01_unmoved.wsmodel")
    with open(os.path.join(PREVIEWS, "advisor_body_unmoved.variantmeshdefinition"), "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    print(f"wrote the unmoved body preview to {PREVIEWS}")


def write_prop_copies(assets: AssetSource, offsets: Dict[str, List[float]]) -> None:
    """Writes a copy of each weapon in the registry's `model.prop_offsets` with its pivot moved by the offset, in the weapon's own axes. A positive x
    moves the weapon blade first, so his hand sits further down the grip, toward the pommel. A `.wsmodel` weapon gets a copy of its `.wsmodel` too,
    pointing at the moved geometry and keeping its materials.

    Args:
        assets (AssetSource): The vanilla packs.
        offsets (Dict[str, List[float]]): Weapon model path -> [x, y, z] metres.

    Raises:
        SystemExit: When a weapon is neither a `.rigid_model_v2` nor a `.wsmodel`.
    """
    shutil.rmtree(os.path.join(MOD, os.path.dirname(prop_copy_path("x"))), ignore_errors=True)
    if any(not path.lower().endswith((".rigid_model_v2", ".wsmodel")) for path in offsets):
        sys.exit("model.prop_offsets takes .rigid_model_v2 and .wsmodel weapons only")
    files = assets.fetch_all(list(offsets))
    for path, offset in offsets.items():
        geometry, text = path, None
        if path.lower().endswith(".wsmodel"):
            text = files[norm(path)].decode("utf-8-sig")
            geometry = read_wsmodel(text)[0]
        model = read_rmv2(assets.fetch_all([geometry])[norm(geometry)])
        for mesh in (m for lod in model.lods for m in lod):
            set_pivot(mesh, tuple(p + o for p, o in zip(mesh.pivot, offset)))
        copy = prop_copy_path(geometry)
        os.makedirs(os.path.dirname(os.path.join(MOD, copy)), exist_ok=True)
        with open(os.path.join(MOD, copy), "wb") as f:
            f.write(write_rmv2(model))
        if text is not None:
            with open(os.path.join(MOD, prop_copy_path(path)), "w", encoding="utf-8", newline="\n") as f:
                f.write(text.replace(geometry, copy))
        print(f"wrote {prop_copy_path(path)}, moved {', '.join(f'{o * 100:.1f}' for o in offset)} cm")


def build(preview: bool) -> None:
    """Writes the re-rigged body and heads into the mod folder.

    Args:
        preview (bool): Also write the unmoved body preview for the gallery.
    """
    model = json.load(open(REGISTRY, encoding="utf-8"))["model"]
    assets = AssetSource([], [], VANILLA_PACKS)
    write_prop_copies(assets, model.get("prop_offsets", {}))
    files = assets.fetch_all([SOURCE_SKELETON, TARGET_SKELETON, POINTS_MODEL] + [source for source, _, _ in MODELS.values()])
    rig = Rig(read_anim(files[norm(SOURCE_SKELETON)]), read_anim(files[norm(TARGET_SKELETON)]), model["hand_shift"])
    print("bind gaps over 1 cm of bones both skeletons have:")
    for name, gap in rig.gaps:
        if gap > 0.01:
            print(f"  {name:>24} {gap * 100:6.2f} cm")
    for name, (source, materials, hoodless) in MODELS.items():
        data, totals = rerig(files[norm(source)], rig, files[norm(POINTS_MODEL)], hoodless)
        write_model(MOD, OUTPUT, name, data, materials)
        print(f"wrote {name} ({len(data)} bytes)")
        for (source_bone, target_bone), weight in sorted(totals.items(), key=lambda item: -item[1]):
            if source_bone != target_bone:
                print(f"  {source_bone:>28} -> {target_bone:<20} {weight:8.1f}")
    if preview:
        write_preview(rig, files)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--preview", action="store_true", help="also write the unmoved body preview for the Advisor gallery")
    build(parser.parse_args().preview)
