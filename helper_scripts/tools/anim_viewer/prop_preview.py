"""Exports models into a viewer gallery, so the modding workbench can show a newly picked weapon, body, head or piece (or its thumbnail) before a
rebuild bakes it in.

Each model is read from the given folders, then the vanilla packs, through a one-slot variant mesh definition, and written next to the gallery's
own models as `models/<stem>.json`. A model with an attach bone is held on it, one without bends with the skeleton. The batch file lists the
models as `model`, `slot`, `attach`, `skeleton` and `stem`. Prints a json map of stem -> the json's path inside the gallery (null when the model
was not found).

Usage:
    python -m tools.anim_viewer.prop_preview --gallery _diag/anim_viewer --batch models.json [--folder <mod folder>]
"""

import argparse
import json
import os
import re
import sys
import tempfile
from typing import Dict, List, Optional

from core.asset_source import AssetSource, norm
from tools.anim_file import Animation, read_anim
from tools.anim_viewer.models import export_model

# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Settings

# The vanilla packs holding the skeletons.
SKELETON_PACKS = re.compile(r"^anim.*\.pack$")

# The variant mesh definition a model is exported through.
VARIANT = '<VARIANT_MESH><SLOT name="{slot}"{attach}>{mesh}</SLOT></VARIANT_MESH>'

# What the slot holds: a model, or a variant definition (a set such as a shield's), whose meshes keep their own slot names.
MESH = '<VARIANT_MESH model="{model}"/>'
REFERENCE = '<VARIANT_MESH_REFERENCE definition="{model}"/>'


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Export


def export_prop(gallery: str, item: Dict[str, str], source: AssetSource, bind_pose: Animation) -> Optional[str]:
    """Exports one model on its slot (and attach bone) into a gallery.

    Args:
        gallery (str): The gallery folder.
        item (Dict[str, str]): `model` (its game path), `slot` (e.g. `weapon_5` or `head`), `attach` (the bone it is held on, or empty for a model
            that bends with the skeleton), `skeleton` and `stem` (the file name without its extension).
        source (AssetSource): Where the model is read from.
        bind_pose (Animation): The skeleton's bind pose.

    Returns:
        Optional[str]: The model json's path inside the gallery, or None when no folder or pack has the model.
    """
    if norm(item["model"]) not in source.index and norm(item["model"]) not in source.loose:
        return None
    with tempfile.TemporaryDirectory() as folder:
        variant = os.path.join(folder, "preview.variantmeshdefinition")
        with open(variant, "w", encoding="utf-8") as f:
            mesh = (REFERENCE if item["model"].lower().endswith(".variantmeshdefinition") else MESH).format(model=item["model"])
            f.write(VARIANT.format(slot=item["slot"], attach=f' attach_point="{item["attach"]}"' if item["attach"] else "", mesh=mesh))
        summary = export_model(item["stem"], variant, item["skeleton"], bind_pose, source, gallery)
    return f"models/{item['stem']}.json" if summary["meshes"] else None


def export_batch(gallery: str, items: List[Dict[str, str]], folders: List[str]) -> Dict[str, Optional[str]]:
    """Exports several models, reading the pack listings and each skeleton once.

    Args:
        gallery (str): The gallery folder.
        items (List[Dict[str, str]]): The models, as `export_prop` takes them.
        folders (List[str]): Folders of a mod's own model files, read before the vanilla packs.

    Returns:
        Dict[str, Optional[str]]: Stem -> the model json's path inside the gallery, or None when it was not found.
    """
    source, skeletons, poses = AssetSource(folders, []), AssetSource([], [], SKELETON_PACKS), {}
    out = {}
    for item in items:
        if item["skeleton"] not in poses:
            path = f"animations/skeletons/{item['skeleton']}.anim"
            poses[item["skeleton"]] = read_anim(skeletons.fetch([path])[norm(path)])
        out[item["stem"]] = export_prop(gallery, item, source, poses[item["skeleton"]])
    return out


def main() -> int:
    """Exports the batch named on the command line.

    Returns:
        int: 0.
    """
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--gallery", required=True)
    parser.add_argument("--batch", required=True, help="a json list of models to export")
    parser.add_argument("--folder", action="append", default=[], help="a folder of a mod's own model files, read before the vanilla packs")
    args = parser.parse_args()
    items = json.load(open(args.batch, encoding="utf-8"))
    print(json.dumps(export_batch(args.gallery, items, args.folder)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
