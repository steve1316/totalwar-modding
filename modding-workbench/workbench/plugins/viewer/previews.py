"""Exports models for the live previews and thumbnails of the Adjust and Look tabs, so a newly picked weapon, body, head or piece shows on the
stage before a rebuild bakes it into the gallery.

The export runs `tools.anim_viewer.prop_preview` in the project's `helper_scripts`, where its jobs run and its pack tools are, reading the project's
own model folders before the vanilla packs. A model already exported is reused, and the rest are exported in one run.
"""

import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
import threading
from typing import Dict, List, Optional

from workbench.projects import Project

# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Settings

# A model's game path.
MODEL_PATH = re.compile(r"^[\w ./-]+\.(wsmodel|rigid_model_v2)$", re.IGNORECASE)

# A slot, attach bone or skeleton name. A model with no attach bone bends with the skeleton.
NAME = re.compile(r"^[a-z0-9_]*$")

# Models one request may ask for at most.
MAX_MODELS = 40

# Seconds an export run may take.
TIMEOUT = 600

# One export run at a time.
_lock = threading.Lock()


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Export


def prop_previews(project: Project, items: List[Dict[str, str]]) -> List[Optional[str]]:
    """Exports models on their slots (and attach bones) into the project's gallery, each once.

    Args:
        project (Project): The project.
        items (List[Dict[str, str]]): Each with `model` (its game path), `slot` (e.g. `weapon_5` or `head`), `attach` (the bone it is held on,
            or empty for a model that bends with the skeleton) and optionally `skeleton` (`humanoid01` when left out).

    Returns:
        List[Optional[str]]: Each model json's path inside the gallery, in order, or None when neither the project's folders nor a vanilla pack has
        the model.

    Raises:
        ValueError: When a value is out of shape or there are too many models.
    """
    if not isinstance(items, list) or not 0 < len(items) <= MAX_MODELS:
        raise ValueError(f"expected 1 to {MAX_MODELS} models")
    batch = []
    for item in items:
        model, slot, attach, skeleton = (str(item.get(k, d)) for k, d in (("model", ""), ("slot", ""), ("attach", ""), ("skeleton", "humanoid01")))
        if not MODEL_PATH.match(model) or ".." in model or not all(NAME.match(v) for v in (slot, attach, skeleton)) or not slot or not skeleton:
            raise ValueError("bad model, slot, attach bone or skeleton")
        stem = "preview_" + hashlib.sha1(f"{model.lower()}|{slot}|{attach}|{skeleton}".encode()).hexdigest()[:12]
        batch.append({"model": model, "slot": slot, "attach": attach, "skeleton": skeleton, "stem": stem})
    exists = lambda item: os.path.exists(os.path.join(project.gallery, f"models/{item['stem']}.json"))
    with _lock:
        missing = [item for item in batch if not exists(item)]
        if missing:
            with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False, encoding="utf-8") as f:
                json.dump(missing, f)
            try:
                command = [sys.executable, "-m", "tools.anim_viewer.prop_preview", "--gallery", project.gallery, "--batch", f.name]
                command += [arg for folder in project.assets for arg in ("--folder", folder)]
                subprocess.run(command, cwd=project.root, capture_output=True, text=True, timeout=TIMEOUT)
            finally:
                os.remove(f.name)
    return [f"models/{item['stem']}.json" if exists(item) else None for item in batch]
