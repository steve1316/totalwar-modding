"""Exports models into a viewer gallery, so the modding workbench can show a newly picked weapon, body, head or piece (or its thumbnail) before a
rebuild bakes it in.

Each model is read from the given folders, then the vanilla packs, through a one-slot variant mesh definition, and written next to the gallery's
own models as `models/<stem>.json`. A model with an attach bone is held on it, one without bends with the skeleton. The batch file lists the
models as `model`, `slot`, `attach`, `skeleton` and `stem`. Prints a json map of stem -> the json's path inside the gallery (null when the model
was not found).

With `--serve` it stays running for the workbench instead: each line on stdin is a batch (a json list of models) and each answer is one json line on
stdout, `{"urls": {...}}` or `{"error": "..."}`. The pack listings and skeletons are read once, so a batch only pays for its own models.

Usage:
    python -m tools.anim_viewer.prop_preview --gallery _diag/anim_viewer --batch models.json [--folder <mod folder>]
    python -m tools.anim_viewer.prop_preview --gallery _diag/anim_viewer --serve [--folder <mod folder>]
"""

import argparse
import json
import os
import re
import sys
import tempfile
import traceback
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


class Exporter:
    """Exports batches of models, keeping the pack listings and each skeleton's bind pose between batches."""

    def __init__(self, gallery: str, folders: List[str]):
        """Reads the pack listings.

        Args:
            gallery (str): The gallery folder.
            folders (List[str]): Folders of a mod's own model files, read before the vanilla packs.
        """
        # The gallery folder.
        self.gallery = gallery
        # Where models are read from, and where the skeletons are.
        self.source, self.skeletons = AssetSource(folders, []), AssetSource([], [], SKELETON_PACKS)
        # Skeleton name -> its bind pose.
        self.poses: Dict[str, Animation] = {}

    def export(self, items: List[Dict[str, str]]) -> Dict[str, Optional[str]]:
        """Exports several models. A model in no folder or pack has the mod folders listed again first, for a file a rebuild added.

        Args:
            items (List[Dict[str, str]]): The models, as `export_prop` takes them.

        Returns:
            Dict[str, Optional[str]]: Stem -> the model json's path inside the gallery, or None when it was not found or could not be read (its
            error goes to stderr).
        """
        out = {}
        if any(norm(item["model"]) not in self.source.index and norm(item["model"]) not in self.source.loose for item in items):
            self.source.scan_folders()
        for item in items:
            if item["skeleton"] not in self.poses:
                path = f"animations/skeletons/{item['skeleton']}.anim"
                self.poses[item["skeleton"]] = read_anim(self.skeletons.fetch([path])[norm(path)])
            try:
                out[item["stem"]] = export_prop(self.gallery, item, self.source, self.poses[item["skeleton"]])
            except Exception:
                print(f"could not export {item['model']}", file=sys.stderr)
                traceback.print_exc()
                out[item["stem"]] = None
        return out


def serve(exporter: Exporter):
    """Answers batches read from stdin until it closes.

    Args:
        exporter (Exporter): The exporter.
    """
    answers = sys.stdout
    # Anything the export prints goes to stderr, so stdout holds only answers.
    sys.stdout = sys.stderr
    for line in sys.stdin:
        try:
            answer = {"urls": exporter.export(json.loads(line))}
        except Exception as error:
            traceback.print_exc()
            answer = {"error": f"{type(error).__name__}: {error}"}
        answers.write(json.dumps(answer) + "\n")
        answers.flush()


def main() -> int:
    """Exports the batch named on the command line, or serves batches.

    Returns:
        int: 0.
    """
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--gallery", required=True)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--batch", help="a json list of models to export")
    mode.add_argument("--serve", action="store_true", help="answer batches read from stdin, one json line each")
    parser.add_argument("--folder", action="append", default=[], help="a folder of a mod's own model files, read before the vanilla packs")
    args = parser.parse_args()
    exporter = Exporter(args.gallery, args.folder)
    if args.serve:
        serve(exporter)
    else:
        print(json.dumps(exporter.export(json.load(open(args.batch, encoding="utf-8")))))
    return 0


if __name__ == "__main__":
    sys.exit(main())
