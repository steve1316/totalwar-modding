"""Shared export pieces of the animation viewer: animation bundles, models and the manifest. The modding workbench (`modding-workbench/`, Viewer
tab) draws an export: point a project config's `gallery` at the output folder.

Each bone of each animation frame is written as 7 int16 values: world position scaled by the animation's `scale`, then the world rotation quaternion
scaled by 32767. Animations are packed into a few bundle files. The manifest lists entries (a unit, or a source/target comparison), each with its
sides (rider, mount, source, target), their models and their slots.
"""

import json
import os
import re
import shutil
from typing import Dict, List, Optional, Tuple

import numpy as np

from core.asset_source import AssetSource, norm
from tools.anim_file import Animation, read_anim
from tools.anim_retarget import world_pose
from tools.anim_viewer.models import export_model
from tools.glf_rebuild_animpack import AnimSet, load_slot_ids, parse_set, read_animpack

# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Settings

# Slot id names.
SLOT_IDS = "./schemas/anim_ids_warhammer_3.csv"

# Largest animation bundle file before a new one is started.
BUNDLE_BYTES = 4 * 1024 * 1024

# Quaternion components are stored as int16 scaled by this.
QUAT_SCALE = 32767


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Helpers


def load_set(path: str) -> AnimSet:
    """Loads an animation set from a `.bin`, or from an `.animpack`: the set named after `#` (e.g. `tables.animpack#hu1_foo`), else its first set.

    Args:
        path (str): The file, optionally with `#<set name>`.

    Returns:
        AnimSet: The set.
    """
    path, _, name = path.partition("#")
    data = open(path, "rb").read()
    if path.endswith(".animpack"):
        sets = [(p, d) for p, d in read_animpack(data) if p.endswith(".bin")]
        data = next(d for p, d in sets if not name or os.path.basename(p) == f"{name}.bin")
    return parse_set(data)


def export_anim(anim: Animation, skeleton: Animation) -> Tuple[bytes, float]:
    """World-space bone transforms of every frame, quantised to int16.

    Args:
        anim (Animation): The animation.
        skeleton (Animation): Its skeleton's bind pose.

    Returns:
        Tuple[bytes, float]: The int16 bytes (frames x bones x 7) and the position scale.
    """
    world = np.array([[(*position, *rotation) for rotation, position in world_pose(anim, skeleton, frame)] for frame in range(len(anim.rotations))])
    scale = max(float(np.abs(world[..., :3]).max()), 1e-4) / 32767
    out = np.empty(world.shape, np.int16)
    out[..., :3] = np.round(world[..., :3] / scale)
    out[..., 3:] = np.round(world[..., 3:] * QUAT_SCALE)
    return out.astype("<i2").tobytes(), scale


def first_refs(anim_set: AnimSet, names: Dict[int, str]) -> Dict[str, str]:
    """The first animation of each slot that has one.

    Args:
        anim_set (AnimSet): The set.
        names (Dict[int, str]): Slot names by id.

    Returns:
        Dict[str, str]: Animation path by slot name.
    """
    refs: Dict[str, str] = {}
    for slot in anim_set.slots:
        name = names.get(slot.slot_id, str(slot.slot_id))
        if slot.refs and name not in refs:
            refs[name] = slot.refs[0].anim
    return refs


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Exporter


class Exporter:
    """Collects animations and models for one viewer folder, then writes the bundles, the manifest and the page."""

    # Output folder.
    out: str
    # Where animations, skeletons and model files are looked up.
    assets: AssetSource
    # Slot names by id.
    names: Dict[int, str]
    # Bind pose skeletons by name.
    skeletons: Dict[str, Animation]
    # Manifest record of each exported animation.
    anims: List[Dict]
    # Index into `anims` by animation path.
    ids: Dict[str, int]
    # Distinct bone lists ([name, parent] pairs).
    rigs: List[List]
    # Animation bundle buffers.
    bundles: List[bytearray]
    # Model json url by (variant, skeleton).
    models: Dict[Tuple[str, str], str]
    # Manifest entries.
    entries: List[Dict]
    # Portrait camera preview data (looks, porthole animation, camera values), or None when the export has no portrait page.
    portrait: Optional[Dict]
    # The tuning values baked into the exported models (prop offsets, hand shift), which the Adjust panel edits from, or None.
    tuning: Optional[Dict]
    # Unit panels by unit key (built with `ttc.unit_panel`), or None.
    panels: Optional[Dict]

    def __init__(self, out: str, assets: AssetSource):
        self.out = out
        self.assets = assets
        self.names = load_slot_ids(open(SLOT_IDS, encoding="utf-8").read())
        self.skeletons = {}
        self.anims = []
        self.ids = {}
        self.rigs = []
        self.bundles = [bytearray()]
        self.models = {}
        self.entries = []
        self.portrait = None
        self.tuning = None
        self.panels = None
        shutil.rmtree(out, ignore_errors=True)
        os.makedirs(os.path.join(out, "anims"), exist_ok=True)

    def read(self, path: str) -> bytes:
        """Reads a game file from the asset folders or packs.

        Args:
            path (str): Game path.

        Returns:
            bytes: The file.

        Raises:
            FileNotFoundError: When no folder or pack has it.
        """
        data = self.assets.fetch([path]).get(norm(path))
        if data is None:
            raise FileNotFoundError(path)
        return data

    def skeleton(self, name: str) -> Animation:
        """The bind pose of a skeleton, e.g. `humanoid01`."""
        if name not in self.skeletons:
            self.skeletons[name] = read_anim(self.read(f"animations/skeletons/{name}.anim"))
        return self.skeletons[name]

    def anim(self, path: str) -> int:
        """Exports one animation once.

        Args:
            path (str): Game path of the `.anim`.

        Returns:
            int: Its index in the manifest's `anims`.
        """
        if path in self.ids:
            return self.ids[path]
        anim = read_anim(self.read(path))
        data, scale = export_anim(anim, self.skeleton(anim.skeleton))
        rig = [[b.name, b.parent] for b in anim.bones]
        if rig not in self.rigs:
            self.rigs.append(rig)
        if self.bundles[-1] and len(self.bundles[-1]) + len(data) > BUNDLE_BYTES:
            self.bundles.append(bytearray())
        self.anims.append({"bundle": len(self.bundles) - 1, "offset": len(self.bundles[-1]), "frames": len(anim.rotations), "rig": self.rigs.index(rig),
                           "fps": anim.frame_rate, "length": anim.length, "scale": scale, "skeleton": anim.skeleton})
        self.bundles[-1].extend(data)
        self.ids[path] = len(self.anims) - 1
        return self.ids[path]

    def model(self, variant: str, skeleton: str) -> Optional[str]:
        """Exports a variant's model once.

        Args:
            variant (str): Variant mesh definition (local file or game path).
            skeleton (str): Skeleton the model is skinned to.

        Returns:
            Optional[str]: The model json url, or None when the variant could not be read.
        """
        key = (variant, skeleton)
        if key not in self.models:
            stem = re.sub(r"[^a-z0-9_]+", "_", os.path.basename(variant).lower().replace(".variantmeshdefinition", ""))
            stem = f"{stem}_{len(self.models):02d}"
            try:
                summary = export_model(stem, variant, skeleton, self.skeleton(skeleton), self.assets, self.out)
            except FileNotFoundError as error:
                print(f"model {variant}: not found ({error})")
                self.models[key] = None
                return None
            print(f"model {stem}: {summary['meshes']} meshes, {summary['vertices']} vertices, {summary['bin_bytes'] // 1024} KB, {summary['textures']} textures")
            for path in summary["missing"]:
                print(f"  missing: {path}")
            self.models[key] = f"models/{stem}.json"
        return self.models[key]

    def write(self) -> None:
        """Writes the bundles and the manifest."""
        for index, bundle in enumerate(self.bundles):
            with open(os.path.join(self.out, "anims", f"bundle_{index:02d}.bin"), "wb") as f:
                f.write(bundle)
        manifest = {"entries": self.entries, "anims": self.anims, "rigs": self.rigs, "bundles": [f"anims/bundle_{i:02d}.bin" for i in range(len(self.bundles))]}
        if self.portrait:
            manifest["portrait"] = self.portrait
        if self.tuning:
            manifest["tuning"] = self.tuning
        if self.panels:
            manifest["panels"] = self.panels
        with open(os.path.join(self.out, "manifest.json"), "w", encoding="utf-8") as f:
            json.dump(manifest, f, separators=(",", ":"))
        size = sum(os.path.getsize(os.path.join(root, n)) for root, _, files in os.walk(self.out) for n in files)
        count = sum(len(files) for _, _, files in os.walk(self.out))
        print(f"{len(self.entries)} entries, {len(self.anims)} animations in {len(self.bundles)} bundles, {count} files, {size / 1048576:.1f} MB in {self.out}")


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Entries


def compare_entry(exporter: Exporter, name: str, source_set: AnimSet, target_set: AnimSet, variants: Dict[str, Optional[str]],
                  keep: Optional[str] = None, skip: Optional[str] = None) -> Dict:
    """Adds an entry that plays a source set and its retargeted copy slot by slot.

    Args:
        exporter (Exporter): The exporter.
        name (str): Entry name shown in the picker.
        source_set (AnimSet): The original set.
        target_set (AnimSet): The retargeted set.
        variants (Dict[str, Optional[str]]): Variant mesh definition by side (`source`, `target`).
        keep (Optional[str]): Only export slots whose name matches this regex.
        skip (Optional[str]): Leave out slots whose name matches this regex.

    Returns:
        Dict: The entry, already added to the exporter.
    """
    refs = {"source": first_refs(source_set, exporter.names), "target": first_refs(target_set, exporter.names)}
    slots = []
    for slot in sorted(set(refs["source"]) | set(refs["target"])):
        if (keep and not re.search(keep, slot)) or (skip and re.search(skip, slot)):
            continue
        entry = {"slot": slot, "anims": {}, "paths": {}}
        for side, side_refs in refs.items():
            if slot in side_refs:
                entry["anims"][side] = exporter.anim(side_refs[slot])
                entry["paths"][side] = side_refs[slot]
        slots.append(entry)
    sides = []
    for key, label, color, anim_set in (("source", "Source", "#f2a33a", source_set), ("target", "Retargeted", "#4fb3ff", target_set)):
        # The model is skinned to the skeleton the side's animations use, which can differ from the set's.
        skeleton = next((exporter.anims[s["anims"][key]]["skeleton"] for s in slots if key in s["anims"]), anim_set.skeleton)
        model = exporter.model(variants[key], skeleton) if variants.get(key) else None
        sides.append({"key": key, "label": label, "color": color, "model": model})
    entry = {"name": name, "kind": "compare", "sets": [source_set.name, target_set.name], "sides": sides, "slots": slots}
    exporter.entries.append(entry)
    return entry
