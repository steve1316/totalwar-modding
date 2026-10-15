"""Projects: the mods and units the workbench works on, one JSON config each under `modding-workbench/projects/`.

A config names the checkout the project lives in and, inside its `helper_scripts`, the project's registry, its viewer gallery, its jobs (commands
such as rebuild and deploy) and where its tuning values sit in the registry. Paths are relative to the checkout's `helper_scripts` folder, and the
checkout itself is relative to the repo root (or absolute). `{python}` in a command is this Python. See `projects/advisor_overhaul.json`.
"""

import glob
import hashlib
import json
import os
import shutil
import subprocess
import sys
import threading
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional

from core.json_format import write_json

# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Settings

# Where a project keeps its model thumbnails unless its config names a `thumbs` folder, relative to its `helper_scripts`.
DEFAULT_THUMBS = "_diag/workbench_thumbs"

# The repo root: checkouts in the configs are relative to it.
REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# The project configs.
PROJECTS_DIR = os.path.join(REPO_ROOT, "modding-workbench", "projects")

# Lines of a job log returned to the page.
LOG_TAIL = 12

# Largest size accepted for a hand shift number, in metres.
HAND_SHIFT_LIMIT = 0.05

# The per-weapon tuning maps (weapon model path -> value): how many numbers a value holds (1 for a single number), the range of each, and the
# value meaning "unchanged", which removes the weapon's entry. Offsets are metres, turns degrees, sizes scales.
PROP_MAPS = {"prop_offsets": (3, -0.3, 0.3, 0.0), "prop_turns": (3, -180.0, 180.0, 0.0), "prop_sizes": (1, 0.25, 3.0, 1.0)}

# Largest number, longest text, and largest object (as JSON) an edit may be.
EDIT_NUMBER_LIMIT = 1000000
EDIT_TEXT_LIMIT = 2000
EDIT_OBJECT_LIMIT = 50000


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Registry paths


def get_path(data: Any, path: str) -> Any:
    """A value at a dotted path, e.g. `model.hand_shift`.

    Args:
        data (Any): The registry.
        path (str): The dotted path.

    Returns:
        Any: The value.

    Raises:
        KeyError: When a key is missing.
    """
    for key in path.split("."):
        data = data[key]
    return data


def each_path(data: Any, path: str) -> List[Any]:
    """Every value at a dotted path where `*` stands for every value of a map, e.g. `weapons.*.props`. Missing keys give nothing.

    Args:
        data (Any): The registry.
        path (str): The dotted path.

    Returns:
        List[Any]: The values found.
    """
    found = [data]
    for key in path.split("."):
        found = [v for item in found if isinstance(item, dict) for v in (item.values() if key == "*" else [item[key]] if key in item else [])]
    return found


def set_path(data: Any, path: str, value: Any) -> None:
    """Sets the value at a dotted path, making missing maps on the way.

    Args:
        data (Any): The registry, changed in place.
        path (str): The dotted path.
        value (Any): The new value.
    """
    keys = path.split(".")
    for key in keys[:-1]:
        data = data.setdefault(key, {})
    data[keys[-1]] = value


def delete_path(data: Any, path: str) -> None:
    """Removes the value at a dotted path, then any map it leaves empty. A missing path is left alone.

    Args:
        data (Any): The registry, changed in place.
        path (str): The dotted path.
    """
    keys = path.split(".")
    trail = [data]
    for key in keys[:-1]:
        if not isinstance(trail[-1], dict) or key not in trail[-1]:
            return
        trail.append(trail[-1][key])
    trail[-1].pop(keys[-1], None)
    for depth in range(len(keys) - 1, 0, -1):
        if trail[depth] == {}:
            trail[depth - 1].pop(keys[depth - 1], None)


def path_matches(path: str, pattern: str) -> bool:
    """Whether a dotted path fits a pattern, where `*` stands for any one key.

    Args:
        path (str): The dotted path.
        pattern (str): The pattern, e.g. `weapons.*.stats.*`.

    Returns:
        bool: Whether it fits.
    """
    keys, parts = path.split("."), pattern.split(".")
    return len(keys) == len(parts) and all(part in ("*", key) for key, part in zip(keys, parts))


def edit_value(value: Any) -> Any:
    """Checks an edit's value: on or off, a number, a text, a list of texts, an object (such as a planned skill, kept small), or None (remove the
    value).

    Args:
        value (Any): The value sent.

    Returns:
        Any: The value, with whole numbers as integers and others rounded to four decimals.

    Raises:
        ValueError: When it is none of those.
    """
    if value is None or isinstance(value, bool) or (isinstance(value, str) and len(value) <= EDIT_TEXT_LIMIT):
        return value
    if isinstance(value, (int, float)) and not isinstance(value, bool) and abs(value) <= EDIT_NUMBER_LIMIT:
        return int(value) if float(value).is_integer() else round(float(value), 4)
    if isinstance(value, list) and all(isinstance(v, str) and len(v) <= EDIT_TEXT_LIMIT for v in value):
        return value
    if isinstance(value, dict) and len(json.dumps(value)) <= EDIT_OBJECT_LIMIT:
        return value
    raise ValueError(f"bad value {str(value)[:80]}")


def numbers(value: Any, count: int, low: float, high: float) -> List[float]:
    """Checks a list of numbers.

    Args:
        value (Any): The value sent.
        count (int): How many numbers it must hold.
        low (float): Smallest value of each.
        high (float): Largest value of each.

    Returns:
        List[float]: The numbers, rounded to 4 decimals (tenths of a millimetre for metres).

    Raises:
        ValueError: When it is not `count` numbers within the range.
    """
    if not isinstance(value, list) or len(value) != count or not all(isinstance(v, (int, float)) and low <= v <= high for v in value):
        raise ValueError(f"expected {count} number{'s' if count > 1 else ''} from {low} to {high}")
    return [round(float(v), 4) for v in value]


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Jobs


class Job:
    """A project's one background job and its state. Each job is a list of commands run in order, and a job may publish the new gallery. A job
    with `needs` (another job's name) runs that job first when the registry has changed since it last ended well, as a deploy needs a rebuild.
    """

    # The project it runs for.
    project: "Project"
    # Guards `name`, `running` and `ok`.
    lock: threading.Lock
    # Name of the last job started, or None.
    name: Optional[str]
    # Whether it is still running.
    running: bool
    # Whether it ended well, None while running or before any job.
    ok: Optional[bool]
    # Jobs it ran first, as its `needs` asked.
    ran_first: List[str]

    def __init__(self, project: "Project"):
        self.project = project
        self.lock = threading.Lock()
        self.name, self.running, self.ok, self.ran_first = None, False, None, []

    @property
    def log_path(self) -> str:
        """The job log, next to the project's other run logs."""
        return os.path.join(self.project.root, "_diag", f"workbench_{self.project.key}_job.log")

    def stamp_path(self, name: str) -> str:
        """The file holding the registry's hash when a job last ended well.

        Args:
            name (str): A key of the project's `jobs`.

        Returns:
            str: Its path, next to the job log.
        """
        return os.path.join(self.project.root, "_diag", f"workbench_{self.project.key}_{name}.stamp")

    def registry_hash(self) -> str:
        """The registry's content hash, or empty when there is no registry."""
        return hashlib.sha1(open(self.project.registry, "rb").read()).hexdigest() if os.path.exists(self.project.registry) else ""

    def stale(self, name: str) -> bool:
        """Whether the registry has changed since a job last ended well (or it never has).

        Args:
            name (str): A key of the project's `jobs`.

        Returns:
            bool: True when it should run again.
        """
        path = self.stamp_path(name)
        return not os.path.exists(path) or open(path, encoding="utf-8").read().strip() != self.registry_hash()

    def start(self, name: str) -> bool:
        """Starts a job in a thread unless one is running.

        Args:
            name (str): A key of the project's `jobs`.

        Returns:
            bool: Whether it started.
        """
        with self.lock:
            if self.running:
                return False
            self.name, self.running, self.ok, self.ran_first = name, True, None, []
        threading.Thread(target=self._run, args=(name,), daemon=True).start()
        return True

    def _run(self, name: str) -> None:
        """Runs a job into the job log, first the job its `needs` names when that one is stale.

        Args:
            name (str): A key of the project's `jobs`.
        """
        need = self.project.jobs[name].get("needs")
        os.makedirs(os.path.dirname(self.log_path), exist_ok=True)
        with open(self.log_path, "w", encoding="utf-8") as log:
            ok = True
            if need and self.stale(need):
                log.write(f"the registry changed since the last {need}, so it runs first\n")
                self.ran_first.append(need)
                ok = self._steps(need, log)
            ok = ok and self._steps(name, log)
            log.write("done\n" if ok else "")
        with self.lock:
            self.running, self.ok = False, ok

    def _steps(self, name: str, log) -> bool:
        """Runs one job's commands from the project's `helper_scripts`, then publishes the gallery when the job asks for it. A job that ends well
        stamps the registry's hash it started from.

        Args:
            name (str): A key of the project's `jobs`.
            log: The open job log.

        Returns:
            bool: Whether every command ended well.
        """
        spec, started = self.project.jobs[name], self.registry_hash()
        for command in spec["commands"]:
            command = [sys.executable if part == "{python}" else part for part in command]
            log.write(f"> {' '.join(command[1:])}\n")
            log.flush()
            if subprocess.run(command, cwd=self.project.root, stdout=log, stderr=subprocess.STDOUT).returncode != 0:
                log.write("failed\n")
                return False
        if spec.get("publish"):
            shutil.copytree(self.project.gallery_next, self.project.gallery, dirs_exist_ok=True)
            log.write("published the new gallery\n")
        with open(self.stamp_path(name), "w", encoding="utf-8") as f:
            f.write(started)
        return True

    def state(self) -> Dict[str, Any]:
        """The job state for the page.

        Returns:
            Dict[str, Any]: `name`, `running`, `ok`, `ran_first` (the jobs its `needs` ran first) and `log` (the last lines of the job log).
        """
        with self.lock:
            state = {"name": self.name, "running": self.running, "ok": self.ok, "ran_first": list(self.ran_first)}
        lines = open(self.log_path, encoding="utf-8", errors="replace").read().splitlines() if os.path.exists(self.log_path) else []
        state["log"] = lines[-LOG_TAIL:]
        return state


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Projects


@dataclass
class Project:
    """One project config."""

    # Config file name without `.json`, used in URLs.
    key: str
    # Name shown in the project picker.
    name: str
    # The project checkout's `helper_scripts` folder, where its commands run.
    root: str
    # The registry the tuning values are saved into.
    registry: str
    # The viewer gallery the Viewer tab draws, and the folder a rebuild exports the next one to.
    gallery: str
    gallery_next: str
    # Job name -> {"commands": [[...], ...], "publish": bool}.
    jobs: Dict[str, Dict[str, Any]]
    # Tuning value -> its dotted path in the registry (`PROP_MAPS`, `hand_shift`, `camera_head`), plus `prop_sources`: dotted paths, `*` for
    # every value of a map, to the prop slot maps whose models may get an offset.
    tuning: Dict[str, Any]
    # Dotted path patterns (`*` for any one key) of the registry values the Edit and Skills tabs may set.
    editable: List[str]
    # Dotted paths of registry values the page reads as they are (such as the planned skills).
    readable: List[str]
    # Folders of the project's own model files, which live previews read before the vanilla packs.
    assets: List[str]
    # The folder the page's model thumbnails are kept in.
    thumbs: str
    # The project's running or last job.
    job: Job = field(init=False, repr=False)

    def __post_init__(self):
        self.job = Job(self)

    @classmethod
    def load(cls, path: str) -> "Project":
        """Reads one config.

        Args:
            path (str): The config file.

        Returns:
            Project: The project.
        """
        config = json.load(open(path, encoding="utf-8"))
        root = os.path.normpath(os.path.join(REPO_ROOT, config["checkout"], config.get("helper_scripts", "helper_scripts")))
        return cls(key=os.path.basename(path)[:-len(".json")], name=config["name"], root=root, registry=os.path.join(root, config["registry"]),
                   gallery=os.path.join(root, config["gallery"]), gallery_next=os.path.join(root, config["gallery_next"]), jobs=config["jobs"],
                   tuning=config.get("tuning", {}), editable=config.get("editable", []), readable=config.get("readable", []),
                   assets=[os.path.normpath(os.path.join(root, folder)) for folder in config.get("assets", [])],
                   thumbs=os.path.join(root, config.get("thumbs", DEFAULT_THUMBS)))

    def read_registry(self) -> Dict:
        """The registry as it is on disk."""
        return json.load(open(self.registry, encoding="utf-8"))

    def props(self, registry: Dict) -> List[str]:
        """Every model the registry holds on a bone (a prop slot's [bone, model, ...]), in registry order. Variant mesh references and pieces that
        bend with the body ([model, ...]) are left out.

        Args:
            registry (Dict): The registry.

        Returns:
            List[str]: The model paths.
        """
        paths: List[str] = []
        for source in self.tuning.get("prop_sources", []):
            for slots in each_path(registry, source):
                for prop in slots.values() if isinstance(slots, dict) else []:
                    if isinstance(prop, list) and len(prop) > 1 and prop[1] not in paths and prop[1].lower().endswith((".wsmodel", ".rigid_model_v2")):
                        paths.append(prop[1])
        return paths

    def tuning_values(self, registry: Optional[Dict] = None) -> Dict[str, Any]:
        """The values the Look tab and the portrait page edit, and the weapon models that may get an offset.

        Args:
            registry (Optional[Dict]): The registry, read from disk when None.

        Returns:
            Dict[str, Any]: `PROP_MAPS`, `hand_shift`, `camera_head` (each only when the config names it), `props`, and `registry`: each
            `readable` path -> its value (None when missing).
        """
        registry = registry if registry is not None else self.read_registry()
        values = {name: get_path(registry, path) if name not in PROP_MAPS else (each_path(registry, path) or [{}])[0]
                  for name, path in self.tuning.items() if name != "prop_sources"}
        values["props"] = self.props(registry)
        values["registry"] = {path: (each_path(registry, path) or [None])[0] for path in self.readable}
        return values

    def save_tuning(self, changes: Dict[str, Any]) -> Dict[str, Any]:
        """Writes sent tuning values into the registry. A prop offset of all zeros removes that weapon's entry.

        Args:
            changes (Dict[str, Any]): Any of `prop_offsets`, `prop_turns` and `prop_sizes` (partial maps, see `PROP_MAPS`), `hand_shift`,
                `camera_head` (a partial map), and `registry`: dotted
                path -> value from the Edit tab, each path fitting one of the config's `editable` patterns (None removes the value).

        Returns:
            Dict[str, Any]: The values after the save.

        Raises:
            ValueError: When a value is out of shape, names a weapon the registry does not use, or the config has no path for it.
        """
        registry = self.read_registry()
        for name in changes:
            if name != "registry" and (name not in self.tuning or name == "prop_sources"):
                raise ValueError(f"{self.name} has no {name} to tune")
        for path, value in changes.get("registry", {}).items():
            if not any(path_matches(path, pattern) for pattern in self.editable):
                raise ValueError(f"{path} is not editable")
            value = edit_value(value)
            if value is None:
                delete_path(registry, path)
            else:
                set_path(registry, path, value)
        for name in (n for n in PROP_MAPS if n in changes):
            known, (count, low, high, unchanged) = self.props(registry), PROP_MAPS[name]
            values = dict((each_path(registry, self.tuning[name]) or [{}])[0])
            for path, value in changes[name].items():
                if path not in known:
                    raise ValueError(f"{path} is not a weapon in the registry")
                listed = numbers(value if count > 1 else [value], count, low, high)
                if any(v != unchanged for v in listed):
                    values[path] = listed if count > 1 else listed[0]
                else:
                    values.pop(path, None)
            set_path(registry, self.tuning[name], values)
        if "hand_shift" in changes:
            set_path(registry, self.tuning["hand_shift"], numbers(changes["hand_shift"], 3, -HAND_SHIFT_LIMIT, HAND_SHIFT_LIMIT))
        if "camera_head" in changes:
            camera = get_path(registry, self.tuning["camera_head"])
            for key, value in changes["camera_head"].items():
                if key not in camera or not isinstance(value, (int, float)):
                    raise ValueError(f"bad camera value {key}")
                camera[key] = round(float(value), 4)
        write_json(self.registry, registry)
        return self.tuning_values(registry)


def load_projects() -> Dict[str, Project]:
    """Every project config, in file name order.

    Returns:
        Dict[str, Project]: Projects by key.
    """
    return {project.key: project for project in (Project.load(path) for path in sorted(glob.glob(os.path.join(PROJECTS_DIR, "*.json"))))}
