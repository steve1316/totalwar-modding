"""Exports models for the live previews and thumbnails of the Look tab, so a newly picked weapon, body, head or piece shows on the
stage before a rebuild bakes it into the gallery.

The export runs `tools.anim_viewer.prop_preview --serve` in the project's `helper_scripts`, where its jobs run and its pack tools are, reading the
project's own model folders before the vanilla packs. That worker stays running, so each batch only pays for its own models. A model already
exported is reused. One batch runs at a time, and a try-on (`urgent`) goes ahead of the thumbnails waiting.
"""

import hashlib
import json
import os
import re
import subprocess
import sys
import threading
from typing import Dict, List, Optional

from workbench.projects import Project

# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Settings

# A model's game path, or a variant definition's (a set such as a shield's).
MODEL_PATH = re.compile(r"^[\w ./-]+\.(wsmodel|rigid_model_v2|variantmeshdefinition)$", re.IGNORECASE)

# A slot, attach bone or skeleton name. A model with no attach bone bends with the skeleton.
NAME = re.compile(r"^[a-z0-9_]*$")

# Models one request may ask for at most.
MAX_MODELS = 40

# Version of the export, part of each file name, so a model exported before a change to the export (such as faction colour masks) is made again.
EXPORT_VERSION = 3

# Each project's export worker.
_workers: Dict[str, "ExportWorker"] = {}
_workers_lock = threading.Lock()


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Worker


class ExportWorker:
    """A project's running `prop_preview --serve`, taking one batch at a time: urgent batches first, then the rest in the order they came."""

    def __init__(self, project: Project):
        """Prepares the worker. It starts with the first batch.

        Args:
            project (Project): The project.
        """
        # The project.
        self.project = project
        # The running process, or None before the first batch and after it died.
        self.process: Optional[subprocess.Popen] = None
        # Guards the queues and `busy`, and wakes the waiting batches.
        self.turn = threading.Condition()
        # Batches waiting for their turn, by ticket: urgent ones and the rest.
        self.urgent: List[object] = []
        self.waiting: List[object] = []
        # Whether a batch is running.
        self.busy = False

    @property
    def log_path(self) -> str:
        """The worker's log, next to the project's job log."""
        return os.path.join(self.project.root, "_diag", f"workbench_{self.project.key}_exports.log")

    def start(self):
        """Starts the process, its errors going to `log_path`."""
        command = [sys.executable, "-m", "tools.anim_viewer.prop_preview", "--gallery", self.project.gallery, "--serve"]
        command += [arg for folder in self.project.assets for arg in ("--folder", folder)]
        os.makedirs(os.path.dirname(self.log_path), exist_ok=True)
        log = open(self.log_path, "a", encoding="utf-8")
        self.process = subprocess.Popen(command, cwd=self.project.root, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=log, text=True,
                                        encoding="utf-8", bufsize=1)
        log.close()

    def ask(self, batch: List[Dict[str, str]]):
        """Sends one batch and waits for its answer, starting the process again when it has stopped.

        Args:
            batch (List[Dict[str, str]]): The models, as `prop_preview` takes them.

        Raises:
            RuntimeError: When the export failed.
        """
        if not self.process or self.process.poll() is not None:
            self.start()
        try:
            self.process.stdin.write(json.dumps(batch) + "\n")
            self.process.stdin.flush()
            line = self.process.stdout.readline()
        except OSError:
            line = ""
        if not line:
            self.process = None
            raise RuntimeError(f"the export worker stopped, see {self.log_path}")
        answer = json.loads(line)
        if "error" in answer:
            raise RuntimeError(answer["error"])

    def run(self, batch: List[Dict[str, str]], urgent: bool):
        """Waits for the batch's turn, then exports it.

        Args:
            batch (List[Dict[str, str]]): The models.
            urgent (bool): Whether it goes ahead of the batches that are not.
        """
        ticket = object()
        with self.turn:
            queue = self.urgent if urgent else self.waiting
            queue.append(ticket)
            while self.busy or (self.urgent or self.waiting)[0] is not ticket:
                self.turn.wait()
            queue.pop(0)
            self.busy = True
        try:
            self.ask(batch)
        finally:
            with self.turn:
                self.busy = False
                self.turn.notify_all()


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Export


def prop_previews(project: Project, items: List[Dict[str, str]], urgent: bool = False) -> List[Optional[str]]:
    """Exports models on their slots (and attach bones) into the project's gallery, each once.

    Args:
        project (Project): The project.
        items (List[Dict[str, str]]): Each with `model` (its game path), `slot` (e.g. `weapon_5` or `head`), `attach` (the bone it is held on,
            or empty for a model that bends with the skeleton) and optionally `skeleton` (`humanoid01` when left out).
        urgent (bool): Whether the batch goes ahead of the ones waiting that are not (a try-on before thumbnails).

    Returns:
        List[Optional[str]]: Each model json's path inside the gallery, in order, or None when neither the project's folders nor a vanilla pack has
        the model.

    Raises:
        ValueError: When a value is out of shape or there are too many models.
        RuntimeError: When the export failed.
    """
    if not isinstance(items, list) or not 0 < len(items) <= MAX_MODELS:
        raise ValueError(f"expected 1 to {MAX_MODELS} models")
    batch = []
    for item in items:
        model, slot, attach, skeleton = (str(item.get(k, d)) for k, d in (("model", ""), ("slot", ""), ("attach", ""), ("skeleton", "humanoid01")))
        if not MODEL_PATH.match(model) or ".." in model or not all(NAME.match(v) for v in (slot, attach, skeleton)) or not slot or not skeleton:
            raise ValueError("bad model, slot, attach bone or skeleton")
        stem = "preview_" + hashlib.sha1(f"{model.lower()}|{slot}|{attach}|{skeleton}|{EXPORT_VERSION}".encode()).hexdigest()[:12]
        batch.append({"model": model, "slot": slot, "attach": attach, "skeleton": skeleton, "stem": stem})
    exists = lambda item: os.path.exists(os.path.join(project.gallery, f"models/{item['stem']}.json"))
    missing = [item for item in batch if not exists(item)]
    if missing:
        with _workers_lock:
            worker = _workers.setdefault(project.key, ExportWorker(project))
        worker.run(missing, urgent)
    return [f"models/{item['stem']}.json" if exists(item) else None for item in batch]
