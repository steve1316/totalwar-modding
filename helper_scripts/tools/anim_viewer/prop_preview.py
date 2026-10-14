"""Exports one model into a viewer gallery, so the modding workbench can show a newly picked weapon, body, head or piece before a rebuild bakes
it in.

The model is read from the given folders, then the vanilla packs, through a one-slot variant mesh definition, and written next to the gallery's
own models as `models/<stem>.json`. A model with an attach bone is held on it, one without bends with the skeleton. Prints the json's path inside
the gallery.

Usage:
    python -m tools.anim_viewer.prop_preview --gallery _diag/anim_viewer --model <path> --slot weapon_5 --attach be_prop_5 --stem preview_x
"""

import argparse
import os
import re
import sys
import tempfile
from typing import List

from core.asset_source import AssetSource, norm
from tools.anim_file import read_anim
from tools.anim_viewer.models import export_model

# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Settings

# The vanilla packs holding the skeletons.
SKELETON_PACKS = re.compile(r"^anim.*\.pack$")

# The variant mesh definition the model is exported through.
VARIANT = '<VARIANT_MESH><SLOT name="{slot}"{attach}><VARIANT_MESH model="{model}"/></SLOT></VARIANT_MESH>'


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Export


def export_prop(gallery: str, model: str, slot: str, attach: str, skeleton: str, stem: str, folders: List[str]) -> str:
    """Exports a model on its slot (and attach bone) into a gallery.

    Args:
        gallery (str): The gallery folder.
        model (str): The model's game path (`.wsmodel` or `.rigid_model_v2`).
        slot (str): The variant slot, e.g. `weapon_5` or `head`.
        attach (str): The bone it is held on, e.g. `be_prop_5`, or empty for a model that bends with the skeleton.
        skeleton (str): The skeleton of the unit holding it.
        stem (str): The model file name without its extension.
        folders (List[str]): Folders of a mod's own model files, read before the vanilla packs.

    Returns:
        str: The model json's path inside the gallery.

    Raises:
        FileNotFoundError: When no folder or vanilla pack has the model.
    """
    source = AssetSource(folders, [])
    if norm(model) not in source.index and norm(model) not in source.loose:
        raise FileNotFoundError(model)
    skeleton_path = f"animations/skeletons/{skeleton}.anim"
    bind_pose = read_anim(AssetSource([], [], SKELETON_PACKS).fetch([skeleton_path])[norm(skeleton_path)])
    with tempfile.TemporaryDirectory() as folder:
        variant = os.path.join(folder, "preview.variantmeshdefinition")
        with open(variant, "w", encoding="utf-8") as f:
            f.write(VARIANT.format(slot=slot, attach=f' attach_point="{attach}"' if attach else "", model=model))
        summary = export_model(stem, variant, skeleton, bind_pose, source, gallery)
    if not summary["meshes"]:
        raise FileNotFoundError(model)
    return f"models/{stem}.json"


def main() -> int:
    """Exports the model named on the command line.

    Returns:
        int: 0 when exported, 1 when the model was not found.
    """
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--gallery", required=True)
    parser.add_argument("--model", required=True)
    parser.add_argument("--slot", required=True)
    parser.add_argument("--attach", required=True)
    parser.add_argument("--skeleton", default="humanoid01")
    parser.add_argument("--stem", required=True)
    parser.add_argument("--folder", action="append", default=[], help="a folder of a mod's own model files, read before the vanilla packs")
    args = parser.parse_args()
    try:
        print(export_prop(args.gallery, args.model, args.slot, args.attach, args.skeleton, args.stem, args.folder))
    except FileNotFoundError as error:
        print(f"not found: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
