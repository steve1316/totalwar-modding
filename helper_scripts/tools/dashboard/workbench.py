"""The dashboard's Workbench tab: the Advisor Overhaul gallery (3D viewer, Adjust panel, portrait page) served under `/workbench/`, with routes that
save tuning values into the generator registry, rebuild the mod and the gallery, and redeploy the test pack.

The values it saves are `model.prop_offsets`, `model.hand_shift` and `portrait.camera_head` (see the registry's descriptions). Rebuild runs the
model generator, the main generator and the gallery export, then copies the gallery over the served folder. Deploy runs
`tools.redeploy_advisor_overhaul`, which refuses while the game is running. One job runs at a time.
"""

import json
import os
import shutil
import subprocess
import sys
import threading
from typing import Any, Dict, List, Optional

from core.json_format import write_json
from generators.advisor_overhaul import REGISTRY

# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Settings

# The served gallery, and where a rebuild exports the next one before copying it over.
SERVED = "./_diag/anim_viewer"
NEXT = "./_diag/anim_viewer_next"

# Log of the last job, next to the other run logs.
JOB_LOG = "./_diag/advisor_overhaul_dashboard_job.log"

# Lines of the job log returned to the page.
LOG_TAIL = 12

# Each job's commands, run in order from helper_scripts. A failing command stops the job.
JOBS = {
    "rebuild": [[sys.executable, "-u", "-m", "generators.advisor_overhaul_model"], [sys.executable, "-u", "-m", "generators.advisor_overhaul"],
                [sys.executable, "-u", "-m", "generators.advisor_overhaul_gallery", "--out", NEXT]],
    "deploy": [[sys.executable, "-u", "-m", "tools.redeploy_advisor_overhaul"]],
}

# Largest size accepted for each prop offset and hand shift number, in metres.
LIMITS = {"prop": 0.3, "hand": 0.05}


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Jobs


class Job:
    """The one background job (rebuild or deploy) and its state."""

    # Guards `name`, `running` and `ok`.
    lock: threading.Lock
    # Name of the last job started, or None.
    name: Optional[str]
    # Whether it is still running.
    running: bool
    # Whether it ended well, None while running or before any job.
    ok: Optional[bool]

    def __init__(self):
        self.lock = threading.Lock()
        self.name, self.running, self.ok = None, False, None

    def start(self, name: str) -> bool:
        """Starts a job in a thread unless one is running.

        Args:
            name (str): A key of `JOBS`.

        Returns:
            bool: Whether it started.
        """
        with self.lock:
            if self.running:
                return False
            self.name, self.running, self.ok = name, True, None
        threading.Thread(target=self._run, args=(name,), daemon=True).start()
        return True

    def _run(self, name: str) -> None:
        """Runs a job's commands into the job log, then copies the new gallery over the served one after a rebuild.

        Args:
            name (str): A key of `JOBS`.
        """
        ok = True
        with open(JOB_LOG, "w", encoding="utf-8") as log:
            for command in JOBS[name]:
                log.write(f"> {' '.join(command[1:])}\n")
                log.flush()
                if subprocess.run(command, stdout=log, stderr=subprocess.STDOUT).returncode != 0:
                    log.write("failed\n")
                    ok = False
                    break
            if ok and name == "rebuild":
                shutil.copytree(NEXT, SERVED, dirs_exist_ok=True)
                log.write("copied the gallery over the served folder\n")
            log.write("done\n" if ok else "")
        with self.lock:
            self.running, self.ok = False, ok

    def state(self) -> Dict[str, Any]:
        """The job state for the page.

        Returns:
            Dict[str, Any]: `name`, `running`, `ok` and `log` (the last lines of the job log).
        """
        with self.lock:
            state = {"name": self.name, "running": self.running, "ok": self.ok}
        lines = open(JOB_LOG, encoding="utf-8", errors="replace").read().splitlines() if os.path.exists(JOB_LOG) else []
        state["log"] = lines[-LOG_TAIL:]
        return state


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Tuning


def weapon_props(registry: Dict) -> List[str]:
    """Every weapon model path the registry's weapons and mounts put on a prop slot.

    Args:
        registry (Dict): The registry.

    Returns:
        List[str]: The paths, in registry order, without duplicates.
    """
    paths: List[str] = []
    for group in ("weapons", "mounts"):
        for item in registry.get(group, {}).values():
            for prop in list(item.get("props", {}).values()) + list(item.get("variant_props", {}).values()):
                if isinstance(prop, list) and len(prop) > 1 and prop[1] not in paths and not prop[1].lower().endswith(".variantmeshdefinition"):
                    paths.append(prop[1])
    return paths


def tuning(registry: Dict) -> Dict[str, Any]:
    """The values the dashboard edits.

    Args:
        registry (Dict): The registry.

    Returns:
        Dict[str, Any]: `prop_offsets`, `hand_shift`, `camera_head` and `props` (the weapon models that may get an offset).
    """
    model = registry["model"]
    return {"prop_offsets": model.get("prop_offsets", {}), "hand_shift": model["hand_shift"], "camera_head": registry["portrait"]["camera_head"],
            "props": weapon_props(registry)}


def numbers(value: Any, count: int, limit: float) -> List[float]:
    """Checks a list of numbers.

    Args:
        value (Any): The value sent.
        count (int): How many numbers it must hold.
        limit (float): Largest size of each.

    Returns:
        List[float]: The numbers, rounded to tenths of a millimetre.

    Raises:
        ValueError: When it is not `count` numbers within the limit.
    """
    if not isinstance(value, list) or len(value) != count or not all(isinstance(v, (int, float)) and abs(v) <= limit for v in value):
        raise ValueError(f"expected {count} numbers within {limit}")
    return [round(float(v), 4) for v in value]


def save_tuning(changes: Dict[str, Any]) -> Dict[str, Any]:
    """Writes the sent values into the registry. A prop offset of all zeros removes that weapon's entry.

    Args:
        changes (Dict[str, Any]): Any of `prop_offsets` (a partial map), `hand_shift` and `camera_head`.

    Returns:
        Dict[str, Any]: The values after the save.

    Raises:
        ValueError: When a value is out of shape or names a weapon the registry does not use.
    """
    registry = json.load(open(REGISTRY, encoding="utf-8"))
    model = registry["model"]
    if "prop_offsets" in changes:
        known = weapon_props(registry)
        offsets = dict(model.get("prop_offsets", {}))
        for path, value in changes["prop_offsets"].items():
            if path not in known:
                raise ValueError(f"{path} is not a weapon in the registry")
            offset = numbers(value, 3, LIMITS["prop"])
            if any(offset):
                offsets[path] = offset
            else:
                offsets.pop(path, None)
        model["prop_offsets"] = offsets
    if "hand_shift" in changes:
        model["hand_shift"] = numbers(changes["hand_shift"], 3, LIMITS["hand"])
    if "camera_head" in changes:
        camera = registry["portrait"]["camera_head"]
        for key, value in changes["camera_head"].items():
            if key not in camera or not isinstance(value, (int, float)):
                raise ValueError(f"bad camera value {key}")
            camera[key] = round(float(value), 4)
    write_json(REGISTRY, registry)
    return tuning(registry)


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Routes


class Workbench:
    """The Workbench tab's routes."""

    # The one background job.
    job: Job

    def __init__(self):
        self.job = Job()

    def get(self, handler, route: str) -> None:
        """Answers a GET under `/workbench/`: the API routes, else a file of the served gallery.

        Args:
            handler: The request handler (`send_json`, `send_file`).
            route (str): The path after `/workbench/`.
        """
        if route == "api/tuning":
            handler.send_json(200, dict(tuning(json.load(open(REGISTRY, encoding="utf-8"))), job=self.job.state()))
        elif route == "api/job":
            handler.send_json(200, self.job.state())
        else:
            handler.send_static(SERVED, route or "index.html")

    def post(self, handler, route: str, body: bytes) -> None:
        """Answers `api/tuning` (save) and `api/run/<job>` (start a job).

        Args:
            handler: The request handler.
            route (str): The path after `/workbench/`.
            body (bytes): The request body.
        """
        try:
            changes = json.loads(body or b"{}")
        except json.JSONDecodeError:
            handler.send_json(400, {"error": "bad json"})
            return
        if route == "api/tuning":
            if self.job.state()["running"]:
                handler.send_json(409, {"error": "a job is running"})
                return
            try:
                handler.send_json(200, save_tuning(changes))
            except ValueError as error:
                handler.send_json(400, {"error": str(error)})
        elif route.startswith("api/run/") and route[len("api/run/"):] in JOBS:
            started = self.job.start(route[len("api/run/"):])
            handler.send_json(200 if started else 409, self.job.state())
        else:
            handler.send_json(404, {"error": "unknown route"})
