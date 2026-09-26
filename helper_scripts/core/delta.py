"""Per-output delta tracking for `update.py`.

Each generator script is a "unit" that builds one or more Workshop packs. While a unit runs, every rpfm extraction it makes is recorded (see
`extract_cache.py`). On the next run, a unit is only rebuilt when one of those exact extractions changed content, when its code or the rpfm toolchain
changed, or when its Workshop pack no longer matches what was last built. After a rebuild, `publish_pack` leaves a Workshop pack untouched when the
generated source files are identical to the previous build, so the summary only lists packs that really need a Workshop upload.
"""

import glob
import json
import logging
import os
import hashlib
import time
from dataclasses import dataclass, field
from typing import Any, Callable, Dict, List, Optional, Set, Tuple

from core.extract_cache import ensure_extracted, extraction_content_sha, file_sha256, pack_sha256, toolchain_hash, tree_sha256
from core.pipeline import workshop_pack_path
from core.utilities import FILEPATH_TO_VANILLA_DATA_TABLES


STATE_ROOT = "./delta_state"
UNITS_STATE_DIR = f"{STATE_ROOT}/units"
OUTPUTS_STATE_DIR = f"{STATE_ROOT}/outputs"
PENDING_DIR = f"{STATE_ROOT}/pending"
WATCHES_STATE_PATH = f"{STATE_ROOT}/watches.json"
# Unit key to its mod and in-game name for every entry in the TTC compat pack, written by `update_ttc_compat.py` for its change notes.
TTC_ENTRIES_PATH = f"{STATE_ROOT}/ttc_entries.json"

# Code every unit depends on. Unit-specific scripts are added per unit below.
SHARED_CODE_FILES = ["core/utilities.py", "core/pipeline.py", "data/supported_mods.py"]


@dataclass
class Output:
    """One generated Workshop pack."""

    # Steam Workshop ID of the published item.
    steam_id: str
    # Pack filename inside the Workshop item folder.
    pack_name: str

    @property
    def pack_path(self) -> str:
        """Return the on-disk path of the subscribed Workshop copy.

        Returns:
            Absolute path under the Workshop content folder.
        """
        return workshop_pack_path(self.steam_id, self.pack_name)


@dataclass
class Unit:
    """One generator script invocation and the Workshop packs it writes."""

    # Short identifier used for state file names and logs.
    name: str
    # Arguments passed to `python`, e.g. `["-m", "generators.update_dynamic_rors", "--reset"]`.
    command: List[str]
    # Packs this invocation writes.
    outputs: List[Output]
    # Code files whose contents change this unit's output, relative to `helper_scripts/`.
    code_files: List[str] = field(default_factory=list)
    # Glob patterns of hand-maintained input files whose contents change this unit's output. Matches ending in `_auto.lua` are skipped.
    input_globs: List[str] = field(default_factory=list)


UNITS: List[Unit] = [
    Unit(
        "land_encounters_factions",
        ["-m", "generators.process_main_units_tables"],
        [Output("3397481450", "land_encounters_and_points_of_interest_6_0.pack")],
        ["generators/process_main_units_tables.py"],
    ),
    Unit(
        "dynamic_rors",
        ["-m", "generators.update_dynamic_rors", "--reset"],
        [Output("3513364573", "!!!!!!!_nanu_dynamic_rors_compat.pack")],
        ["generators/update_dynamic_rors.py", "data/dynamic_rors_effects.py"],
    ),
    Unit(
        "dynamic_rors_leftover_vanilla",
        ["-m", "generators.update_dynamic_rors", "--reset", "--vanilla"],
        [Output("3532864014", "!!!!!!!_nanu_dynamic_rors_leftover_vanilla.pack")],
        ["generators/update_dynamic_rors.py", "data/dynamic_rors_effects.py"],
    ),
    Unit(
        "modified_attributes",
        ["-m", "generators.update_modified_attribute_mods", "--reset"],
        [
            Output("3311361199", "!!!!!!!50meleeattackspeed_compat.pack"),
            Output("3311361345", "!!!!!!!firing_arc_120_compat.pack"),
            Output("3311361464", "!!!!!!!double_projectile_velocity_compat.pack"),
        ],
        ["generators/update_modified_attribute_mods.py"],
    ),
    Unit(
        "double_unit_size",
        ["-m", "generators.update_double_unit_size", "--reset"],
        [Output("3621939685", "!!!!!!!2xunitsize_compat.pack")],
        ["generators/update_double_unit_size.py"],
    ),
    Unit(
        "ttc_compat",
        ["-m", "generators.update_ttc_compat"],
        [Output("3310629727", "!!!!!!!yet_another_tabletopcaps_compat.pack")],
        ["generators/update_ttc_compat.py", "ttc/ttc_classifier.py", "ttc/ttc_data.py", "ttc/ttc_compat_io.py"],
        ["../warhammer3_mods/!!!!!!!yet_another_tabletopcaps_compat/script/ttc/!!!!!!!*.lua"],
    ),
]

# Vanilla tables overridden by the hand-made reduce winds of magic mod (3012881957).
# A change after a game patch means the mod may need a manual update.
REDUCE_WINDS_WATCHED_TABLES = [
    "character_trait_levels_tables",
    "character_traits_tables",
    "trait_categories_tables",
    "trait_info_tables",
    "trait_level_effects_tables",
]


@dataclass
class UnitCheck:
    """Result of checking whether a unit needs a rebuild."""

    # The unit that was checked.
    unit: Unit
    # True when the unit must be rebuilt.
    stale: bool
    # Human-readable reasons for a rebuild.
    reasons: List[str] = field(default_factory=list)
    # Access records whose extracted content changed since the last build.
    changed_accesses: List[Dict[str, Any]] = field(default_factory=list)
    # Normalized paths of packs whose recorded tables changed, or that were installed or removed since the last build.
    changed_packs: List[str] = field(default_factory=list)
    # True when a rebuild reason is not tied to a mod pack, e.g. no previous build, a code or schema change, or a Steam re-sync.
    general: bool = False


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# State helpers


def _read_json(path: str) -> Optional[Any]:
    """Read a JSON file.

    Args:
        path (str): Path to the file.

    Returns:
        The parsed value, or None if the file is missing or invalid.
    """
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return None


def _write_json(path: str, value: Any) -> None:
    """Atomically write a JSON file, creating parent folders as needed.

    Args:
        path (str): Destination path.
        value (Any): JSON-serializable value.
    """
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp_path = f"{path}.tmp"
    with open(tmp_path, "w", encoding="utf-8") as f:
        json.dump(value, f, indent=1, sort_keys=True)
    os.replace(tmp_path, path)


def _access_key(access: Dict[str, Any]) -> Tuple[str, str, str, bool]:
    """Build the identity of one extraction, independent of the pack's content.

    Args:
        access (Dict[str, Any]): An access record from the access log.

    Returns:
        A `(pack, source, source_kind, tables_as_tsv)` tuple.
    """
    return (access["pack"], access["source"], access["source_kind"], access["tables_as_tsv"])


def _pack_label(pack: str) -> str:
    """Return a short display name for a pack path.

    Args:
        pack (str): Normalized pack path.

    Returns:
        The pack filename.
    """
    return os.path.basename(pack)


def code_hash(unit: Unit) -> str:
    """Hash the code and rpfm toolchain that determine a unit's output.

    Args:
        unit (Unit): The unit to hash.

    Raises:
        FileNotFoundError: A listed code file does not exist, e.g. a path left stale after a script moved.

    Returns:
        The hex digest.
    """
    digest = hashlib.sha256(toolchain_hash().encode())
    for path in sorted(set(SHARED_CODE_FILES + unit.code_files)):
        digest.update(path.encode())
        if not os.path.exists(path):
            raise FileNotFoundError(f"Code file `{path}` listed for {unit.name} does not exist. Fix its path in `core/delta.py`.")
        digest.update(file_sha256(path).encode())
    for pattern in unit.input_globs:
        for path in sorted(p for p in glob.glob(pattern) if not p.endswith("_auto.lua")):
            digest.update(os.path.basename(path).encode())
            digest.update(file_sha256(path).encode())
    return digest.hexdigest()


def load_access_log(log_path: str) -> List[Dict[str, Any]]:
    """Read and dedupe an access log written by `extract_cache` during a unit run.

    Args:
        log_path (str): Path to the JSON-lines log.

    Returns:
        One record per unique extraction, sorted for stable state files.
    """
    accesses: Dict[Tuple[str, str, str, bool], Dict[str, Any]] = {}
    if os.path.exists(log_path):
        with open(log_path, "r", encoding="utf-8") as f:
            for line in f:
                if line.strip():
                    access = json.loads(line)
                    accesses[_access_key(access)] = access
    return [accesses[key] for key in sorted(accesses)]


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Unit staleness


def units_for_items(steam_ids: Set[str]) -> List[Unit]:
    """Pick the units that build the given Workshop items.

    Args:
        steam_ids (Set[str]): Workshop IDs of generated items.

    Raises:
        ValueError: If an ID is not a generated Workshop item.

    Returns:
        The units in `UNITS` order.
    """
    known = {output.steam_id for unit in UNITS for output in unit.outputs}
    unknown = sorted(steam_ids - known)
    if unknown:
        raise ValueError(f"Not a generated Workshop item: {', '.join(unknown)}. Choose from: {', '.join(sorted(known))}")
    return [unit for unit in UNITS if any(output.steam_id in steam_ids for output in unit.outputs)]


def check_unit(unit: Unit) -> UnitCheck:
    """Decide whether a unit must be rebuilt by replaying the extractions recorded on its last successful run.

    Packs whose hash is unchanged are skipped without extracting. For a changed pack, only the recorded extractions are re-run (through the cache),
    so a mod update that only touched unrelated tables does not trigger a rebuild.

    Args:
        unit (Unit): The unit to check.

    Returns:
        The check result with the reasons for a rebuild, if any.
    """
    state = _read_json(f"{UNITS_STATE_DIR}/{unit.name}.json")
    check = UnitCheck(unit, stale=False)
    if state is None:
        check.stale = True
        check.general = True
        check.reasons.append("no previous tracked build")
        return check
    if state.get("code_hash") != code_hash(unit):
        check.stale = True
        check.general = True
        check.reasons.append("generator code, `supported_mods.py` or rpfm schema changed")

    for output in unit.outputs:
        output_state = _read_json(f"{OUTPUTS_STATE_DIR}/{output.steam_id}.json")
        if output_state is None:
            check.stale = True
            check.general = True
            check.reasons.append(f"{output.steam_id} has no recorded build")
        elif pack_sha256(output.pack_path) != output_state.get("pack_sha"):
            check.stale = True
            check.general = True
            check.reasons.append(f"Workshop copy of {output.steam_id} no longer matches the last build (Steam re-sync?)")

    for access in state.get("accesses", []):
        label = f"{access['source']} in {_pack_label(access['pack'])}"
        current_sha = pack_sha256(access["pack"])
        if access.get("missing"):
            if current_sha is not None:
                check.stale = True
                check.reasons.append(f"{_pack_label(access['pack'])} is now installed")
                check.changed_packs.append(access["pack"])
            continue
        if current_sha is None:
            check.stale = True
            check.reasons.append(f"{_pack_label(access['pack'])} is no longer installed")
            check.changed_packs.append(access["pack"])
            continue
        if current_sha == access["pack_sha"]:
            continue
        content_sha = extraction_content_sha(access["pack"], access["source"], access["source_kind"], access["tables_as_tsv"])
        if content_sha is None or content_sha != access["content_sha"]:
            check.stale = True
            check.reasons.append(f"{label} changed")
            check.changed_accesses.append(access)
            check.changed_packs.append(access["pack"])

    # Collapse duplicate pack-level reasons, e.g. a newly installed pack recorded for several tables.
    check.reasons = list(dict.fromkeys(check.reasons))
    check.changed_packs = list(dict.fromkeys(check.changed_packs))
    return check


def commit_unit(unit: Unit, log_path: str) -> None:
    """Record a successful unit run so the next run can compare against it.

    Args:
        unit (Unit): The unit that just finished.
        log_path (str): Access log written during the run.
    """
    _write_json(
        f"{UNITS_STATE_DIR}/{unit.name}.json",
        {"code_hash": code_hash(unit), "accesses": load_access_log(log_path), "completed_at": time.strftime("%Y-%m-%d %H:%M:%S")},
    )


def referenced_pack_shas() -> List[str]:
    """Collect every pack hash still referenced by unit and watch state, for cache pruning.

    Returns:
        The referenced SHA-256 digests.
    """
    shas = set()
    if os.path.exists(UNITS_STATE_DIR):
        for name in os.listdir(UNITS_STATE_DIR):
            state = _read_json(f"{UNITS_STATE_DIR}/{name}") or {}
            shas.update(access["pack_sha"] for access in state.get("accesses", []) if access.get("pack_sha"))
    watches = _read_json(WATCHES_STATE_PATH) or {}
    shas.update(entry["pack_sha"] for entry in watches.values() if entry.get("pack_sha"))
    return sorted(shas)


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Output gate used by the generator scripts


def _report(steam_id: str, status: str) -> None:
    """Append an output result to the `DELTA_REPORT` file when `update.py` set one.

    Args:
        steam_id (str): Workshop ID of the output.
        status (str): `updated` or `unchanged`.
    """
    report_path = os.environ.get("DELTA_REPORT")
    if report_path:
        with open(report_path, "a", encoding="utf-8") as f:
            f.write(json.dumps({"steam_id": steam_id, "status": status}) + "\n")


def publish_pack(steam_id: str, pack_path: str, source_path: str, write_fn: Callable[[], None]) -> bool:
    """Write a generated pack unless its source files and Workshop copy are identical to the last build.

    Skipping only happens under `update.py` (`DELTA_SKIP_UNCHANGED=1`). Running a generator script directly always writes the pack, but still records state.

    Args:
        steam_id (str): Workshop ID of the output.
        pack_path (str): Path of the Workshop pack to write.
        source_path (str): Generated file or folder that goes into the pack.
        write_fn (Callable[[], None]): Performs the actual rpfm writes into `pack_path`.

    Returns:
        True if the pack was written, False if it was left untouched.
    """
    state_path = f"{OUTPUTS_STATE_DIR}/{steam_id}.json"
    state = _read_json(state_path)
    source_hash = tree_sha256(source_path)
    current_pack_sha = pack_sha256(pack_path)
    unchanged = state is not None and current_pack_sha is not None and state.get("source_hash") == source_hash and state.get("pack_sha") == current_pack_sha

    if unchanged and os.environ.get("DELTA_SKIP_UNCHANGED") == "1":
        logging.info(f"Generated files for {steam_id} are identical to the last build. Leaving the Workshop pack untouched.")
        _report(steam_id, "unchanged")
        return False

    write_fn()
    _write_json(state_path, {"source_hash": source_hash, "pack_sha": pack_sha256(pack_path), "updated_at": time.strftime("%Y-%m-%d %H:%M:%S")})
    _report(steam_id, "unchanged" if unchanged else "updated")
    return True


def read_report(report_path: str) -> Dict[str, str]:
    """Read the output results written by `publish_pack` during a run.

    Args:
        report_path (str): Path to the JSON-lines report.

    Returns:
        Mapping of Workshop ID to its last reported status.
    """
    statuses: Dict[str, str] = {}
    if os.path.exists(report_path):
        with open(report_path, "r", encoding="utf-8") as f:
            for line in f:
                if line.strip():
                    entry = json.loads(line)
                    statuses[entry["steam_id"]] = entry["status"]
    return statuses


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Hand-made mod review flags


def check_reduce_winds_tables(commit: bool) -> List[str]:
    """Report vanilla trait tables overridden by the reduce winds of magic mod that changed since the last run.

    Args:
        commit (bool): Save the current table hashes as the new baseline.

    Returns:
        Names of changed tables. The first run only records a baseline and reports nothing.
    """
    watches = _read_json(WATCHES_STATE_PATH) or {}
    changed = []
    vanilla_sha = pack_sha256(FILEPATH_TO_VANILLA_DATA_TABLES)
    for table_name in REDUCE_WINDS_WATCHED_TABLES:
        key = f"reduce_winds:{table_name}"
        previous = watches.get(key)
        if previous and previous["pack_sha"] == vanilla_sha:
            continue
        result = ensure_extracted(FILEPATH_TO_VANILLA_DATA_TABLES, f"db/{table_name}/data__", "file", True, capture_output=True)
        if result is None:
            continue
        if previous and previous["content_sha"] != result["content_sha"]:
            changed.append(table_name)
        watches[key] = {"pack_sha": result["pack_sha"], "content_sha": result["content_sha"]}
    if commit:
        _write_json(WATCHES_STATE_PATH, watches)
    return changed
