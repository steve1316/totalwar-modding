"""Publish generated packs to the Steam Workshop after `update.py` builds them.

An item is pending when its Workshop pack differs from the one last uploaded. Rebuild reasons pile up per item until the next upload and become its change
note. The upload itself runs through `workshop_publisher/publish.js`, which uses the logged-in Steam client, so no credentials are stored here.
"""

import json
import os
import shutil
import time
from dataclasses import dataclass
from typing import Any, Dict, List, Optional, Tuple

import delta
from extract_cache import normalize_path, pack_sha256
from pipeline import workshop_pack_path
from supported_mods import SUPPORTED_MODS
from utilities import FILEPATH_TO_VANILLA_DATA_TABLES


PUBLISHED_STATE_DIR = f"{delta.STATE_ROOT}/published"
WORKSHOP_URL = "https://steamcommunity.com/sharedfiles/filedetails/?id="
GENERAL_NOTE = "Rebuilt against the latest game patch and the latest versions of all supported mods."
MAX_NOTE_MODS = 10

# Display names for packs that are not in `SUPPORTED_MODS`.
SPECIAL_PACK_NAMES = {
    normalize_path(FILEPATH_TO_VANILLA_DATA_TABLES): "the base game",
    normalize_path(workshop_pack_path("3278112051", "!!_nanu_dynamic_rors.pack")): "Nanu's Dynamic Regiments of Renown",
}


@dataclass
class PendingItem:
    """A generated Workshop item whose current pack has not been published yet."""

    # The generated pack and its Workshop item.
    output: delta.Output
    # Change note that will be sent with the upload.
    change_note: str


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Publish state


def _record_path(steam_id: str) -> str:
    """Return the publish record path for a Workshop item.

    Args:
        steam_id (str): Workshop ID of the item.

    Returns:
        Path of the item's JSON record.
    """
    return f"{PUBLISHED_STATE_DIR}/{steam_id}.json"


def _read_record(steam_id: str) -> Optional[Dict[str, Any]]:
    """Read a Workshop item's publish record.

    Args:
        steam_id (str): Workshop ID of the item.

    Returns:
        The record, or None if the item has never been recorded.
    """
    try:
        with open(_record_path(steam_id), "r", encoding="utf-8") as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return None


def _write_record(steam_id: str, record: Dict[str, Any]) -> None:
    """Atomically write a Workshop item's publish record.

    Args:
        steam_id (str): Workshop ID of the item.
        record (Dict[str, Any]): Record to store.
    """
    os.makedirs(PUBLISHED_STATE_DIR, exist_ok=True)
    tmp_path = f"{_record_path(steam_id)}.tmp"
    with open(tmp_path, "w", encoding="utf-8") as f:
        json.dump(record, f, indent=1, sort_keys=True, ensure_ascii=False)
    os.replace(tmp_path, _record_path(steam_id))


def mod_display_name(pack_path: str) -> str:
    """Turn a pack path into the name used in change notes.

    Args:
        pack_path (str): Pack path, normalized or not.

    Returns:
        The mod's `SUPPORTED_MODS` name, a fixed name for the base game and Nanu's parent mod, or the pack filename as a fallback.
    """
    key = normalize_path(pack_path)
    if key in SPECIAL_PACK_NAMES:
        return SPECIAL_PACK_NAMES[key]
    for mod in SUPPORTED_MODS:
        if mod["path"] and normalize_path(mod["path"]) == key:
            return mod["name"]
    return os.path.basename(pack_path)


def record_rebuild(check: delta.UnitCheck, statuses: Dict[str, str]) -> None:
    """Add a unit's rebuild reasons to the pending change notes of every output it actually changed.

    Args:
        check (delta.UnitCheck): Staleness result for the unit that was rebuilt.
        statuses (Dict[str, str]): Output statuses reported by `delta.publish_pack`, keyed by Workshop ID.
    """
    names = {mod_display_name(pack) for pack in check.changed_packs}
    for output in check.unit.outputs:
        if statuses.get(output.steam_id) != "updated":
            continue
        record = _read_record(output.steam_id) or {}
        record["pending_mods"] = sorted(set(record.get("pending_mods", [])) | names)
        record["pending_general"] = bool(record.get("pending_general")) or check.general
        _write_record(output.steam_id, record)


def build_change_note(record: Optional[Dict[str, Any]]) -> str:
    """Build the Workshop change note from an item's pending rebuild reasons.

    Args:
        record (Optional[Dict[str, Any]]): The item's publish record, or None if it has never been recorded.

    Returns:
        The change note text.
    """
    mods = (record or {}).get("pending_mods", [])
    general = record is None or not record.get("pack_sha") or bool(record.get("pending_general"))
    parts = []
    if mods:
        listed = ", ".join(mods[:MAX_NOTE_MODS])
        extra = len(mods) - MAX_NOTE_MODS
        parts.append(f"Updated for changes in: {listed}" + (f", and {extra} more mods." if extra > 0 else "."))
    if general or not parts:
        parts.append(GENERAL_NOTE)
    return " ".join(parts)


def pending_items(failed_units: List[str]) -> List[PendingItem]:
    """List generated Workshop items whose current pack differs from the last published one.

    Args:
        failed_units (List[str]): Names of units whose generator failed this run. Their outputs are never offered.

    Returns:
        The pending items, in `delta.UNITS` order.
    """
    items = []
    for unit in delta.UNITS:
        if unit.name in failed_units:
            continue
        for output in unit.outputs:
            current_sha = pack_sha256(output.pack_path)
            if current_sha is None:
                continue
            record = _read_record(output.steam_id)
            if record is None or record.get("pack_sha") != current_sha:
                items.append(PendingItem(output, build_change_note(record)))
    return items


def mark_published(output: delta.Output, change_note: str) -> None:
    """Record a successful upload and clear the item's pending reasons.

    Args:
        output (delta.Output): The item that was uploaded.
        change_note (str): The change note sent with the upload.
    """
    record = _read_record(output.steam_id) or {}
    record.update(
        {
            "pack_sha": pack_sha256(output.pack_path),
            "published_at": time.strftime("%Y-%m-%d %H:%M:%S"),
            "last_change_note": change_note,
            "pending_mods": [],
            "pending_general": False,
        }
    )
    _write_record(output.steam_id, record)


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Staging and uploader output


def stage_content(output: delta.Output, staging_root: str) -> str:
    """Copy an item's pack and preview png into a fresh folder to upload as its Workshop content.

    Args:
        output (delta.Output): The item to stage.
        staging_root (str): Folder under which `<steam_id>/` is created.

    Returns:
        Absolute path of the staged content folder.
    """
    dest = os.path.join(staging_root, output.steam_id)
    shutil.rmtree(dest, ignore_errors=True)
    os.makedirs(dest)
    item_dir = os.path.dirname(output.pack_path)
    shutil.copy2(output.pack_path, dest)
    for name in os.listdir(item_dir):
        if name.lower().endswith(".png"):
            shutil.copy2(os.path.join(item_dir, name), dest)
    return os.path.abspath(dest)


def parse_publisher_output(stdout: str) -> Tuple[Optional[str], Dict[str, Dict[str, Any]]]:
    """Read the JSON result lines printed by `publish.js`, ignoring any other output from Steamworks.

    Args:
        stdout (str): Captured stdout of the uploader.

    Returns:
        A tuple of the fatal error message (or None) and the per-item results keyed by Workshop ID.
    """
    fatal = None
    results: Dict[str, Dict[str, Any]] = {}
    for line in stdout.splitlines():
        line = line.strip()
        if not line.startswith("{"):
            continue
        try:
            entry = json.loads(line)
        except json.JSONDecodeError:
            continue
        if "fatal" in entry:
            fatal = entry["fatal"]
        elif "id" in entry:
            results[str(entry["id"])] = entry
    return fatal, results
