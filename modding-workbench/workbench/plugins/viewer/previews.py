"""Exports one weapon model for the Adjust tab's live preview, so a newly picked model shows on the stage before a rebuild bakes it into the gallery.

The export runs `tools.anim_viewer.prop_preview` in the project's `helper_scripts`, where its jobs run and its pack tools are. A model already
exported is reused.
"""

import hashlib
import os
import re
import subprocess
import sys
import threading

from workbench.projects import Project

# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Settings

# A weapon model's game path.
MODEL_PATH = re.compile(r"^[\w ./-]+\.(wsmodel|rigid_model_v2)$", re.IGNORECASE)

# A slot, attach bone or skeleton name.
NAME = re.compile(r"^[a-z0-9_]+$")

# Seconds an export may take.
TIMEOUT = 300

# One export at a time.
_lock = threading.Lock()


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Export


def prop_preview(project: Project, model: str, slot: str, attach: str, skeleton: str) -> str:
    """Exports a weapon model on its slot and attach bone into the project's gallery, once.

    Args:
        project (Project): The project.
        model (str): The model's game path (`.wsmodel` or `.rigid_model_v2`).
        slot (str): The variant slot, e.g. `weapon_5`.
        attach (str): The bone it is held on, e.g. `be_prop_5`.
        skeleton (str): The skeleton of the unit holding it.

    Returns:
        str: The model json's path inside the gallery.

    Raises:
        ValueError: When a value is out of shape.
        FileNotFoundError: When no vanilla pack has the model.
    """
    if not MODEL_PATH.match(model) or ".." in model or not all(NAME.match(v) for v in (slot, attach, skeleton)):
        raise ValueError("bad model, slot, attach bone or skeleton")
    stem = "preview_" + hashlib.sha1(f"{model.lower()}|{slot}|{attach}|{skeleton}".encode()).hexdigest()[:12]
    url = f"models/{stem}.json"
    with _lock:
        if os.path.exists(os.path.join(project.gallery, url)):
            return url
        command = [sys.executable, "-m", "tools.anim_viewer.prop_preview", "--gallery", project.gallery, "--model", model, "--slot", slot,
                   "--attach", attach, "--skeleton", skeleton, "--stem", stem]
        done = subprocess.run(command, cwd=project.root, capture_output=True, text=True, timeout=TIMEOUT)
    if done.returncode != 0:
        raise FileNotFoundError((done.stderr.strip().splitlines() or [model])[-1])
    return url
