"""Which of the gallery's humanoid models are full bodies, the only ones the Look tab offers as an outfit. A full body follows his spine, both upper
arms and both lower legs, read from the skin weights of the model's preview export (the one its thumbnail uses, made here when missing). Low
detail stand-ins are left out. The answers are kept in the project's `thumbs` folder as `bodies.json`, so each model is read once.
"""

import json
import os
import re
import threading
from typing import Dict, List

import numpy as np

from workbench.plugins.viewer.previews import MAX_MODELS, prop_previews
from workbench.projects import Project

# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Settings

# Bones a full body follows: one of each group.
FULL_BODY_BONES = ({"spine_2"}, {"upperarm_left"}, {"upperarm_right"}, {"lowerleg_left", "foot_left"}, {"lowerleg_right", "foot_right"})

# Smallest skin weight that counts as following a bone.
MIN_WEIGHT = 0.2

# Names of low detail stand-ins (far away crowds), never an outfit.
LOW_DETAIL = re.compile(r"imposter|lowlod", re.IGNORECASE)

# One check of a project at a time.
_lock = threading.Lock()


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Bodies


def is_full_body(gallery: str, url: str) -> bool:
    """Whether an exported model follows every bone group of `FULL_BODY_BONES`.

    Args:
        gallery (str): The gallery folder.
        url (str): The model json's path inside the gallery.

    Returns:
        bool: True for a full body.
    """
    doc = json.load(open(os.path.join(gallery, url), encoding="utf-8"))
    data = open(os.path.join(gallery, os.path.dirname(url), doc["bin"]), "rb").read()
    followed = set()
    for mesh in (m for m in doc["meshes"] if m.get("skinned")):
        bones = np.frombuffer(data, np.uint16, mesh["count"] * 4, mesh["skin_index"])
        weights = np.frombuffer(data, np.float32, mesh["count"] * 4, mesh["skin_weight"])
        followed |= {doc["bones"][i] for i in np.unique(bones[weights > MIN_WEIGHT])}
    return all(followed & group for group in FULL_BODY_BONES)


def full_bodies(project: Project) -> List[str]:
    """The full bodies among the gallery's humanoid models (`editor.look.models` of its manifest).

    Args:
        project (Project): The project.

    Returns:
        List[str]: The models' game paths, in manifest order.
    """
    manifest = json.load(open(os.path.join(project.gallery, "manifest.json"), encoding="utf-8"))
    models = [m for m in ((manifest.get("editor") or {}).get("look") or {}).get("models", []) if not LOW_DETAIL.search(m)]
    path = os.path.join(project.thumbs, "bodies.json")
    with _lock:
        known: Dict[str, bool] = json.load(open(path, encoding="utf-8")) if os.path.exists(path) else {}
        unknown = [m for m in models if m not in known]
        for start in range(0, len(unknown), MAX_MODELS):
            batch = unknown[start:start + MAX_MODELS]
            urls = prop_previews(project, [{"model": m, "slot": "thumb", "attach": ""} for m in batch])
            known.update({m: bool(url) and is_full_body(project.gallery, url) for m, url in zip(batch, urls)})
        if unknown:
            os.makedirs(project.thumbs, exist_ok=True)
            with open(path, "w", encoding="utf-8") as f:
                json.dump(known, f, indent=0, sort_keys=True)
    return [m for m in models if known.get(m)]
