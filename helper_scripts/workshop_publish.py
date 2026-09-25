"""Publish generated packs to the Steam Workshop after `update.py` builds them.

An item is pending when its Workshop pack differs from the one last uploaded. Rebuild reasons pile up per item until the next upload and become its
change note. The upload itself runs through `workshop_publisher/publish.js`, which uses the logged-in Steam client, so no credentials are stored here.
"""

import collections
import json
import logging
import os
import shutil
import subprocess
import sys
import time
from dataclasses import dataclass
from typing import Any, Callable, Dict, List, Optional, Set, Tuple

import delta
from extract_cache import file_sha256, normalize_path, pack_sha256
from pipeline import workshop_pack_path
from supported_mods import SUPPORTED_MODS
from utilities import FILEPATH_TO_VANILLA_DATA_TABLES, TEMP_DIR


PUBLISHED_STATE_DIR = f"{delta.STATE_ROOT}/published"
WORKSHOP_URL = "https://steamcommunity.com/sharedfiles/filedetails/?id="
GENERAL_NOTE = "Rebuilt against the latest game patch and the latest versions of all supported mods."
MAX_NOTE_MODS = 10
# Steam's change note limit (`k_cchPublishedDocumentChangeDescriptionMax`).
CHANGE_NOTE_LIMIT = 8000
# The TTC compat item gets a per-unit change note built from its entries instead of the list of changed mods.
TTC_STEAM_ID = "3310629727"
PUBLISHER_DIR = "./workshop_publisher"
PUBLISH_TEMP_DIR = f"{TEMP_DIR}/publish"

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
    # SHA-256 of the pack when it was listed. The staged copy must match it, and it is what gets recorded once the upload succeeds.
    pack_sha: str


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


def _ttc_snapshot_path() -> str:
    """Return the path of the TTC entries saved at the last upload.

    Returns:
        Path of the JSON snapshot next to the TTC publish record.
    """
    return f"{PUBLISHED_STATE_DIR}/{TTC_STEAM_ID}_entries.json"


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


def _names_list(names: List[str]) -> str:
    """Join unit names, collapsing repeats to `Name (x2)`.

    Args:
        names (List[str]): Unit names, possibly repeated.

    Returns:
        The names sorted case-insensitively and joined with commas.
    """
    counts = collections.Counter(names)
    return ", ".join(name if count == 1 else f"{name} (x{count})" for name, count in sorted(counts.items(), key=lambda item: item[0].lower()))


def _plural(count: int, noun: str) -> str:
    """Write a count with its noun, adding an `s` unless the count is one.

    Args:
        count (int): How many.
        noun (str): Singular noun, e.g. `unit`.

    Returns:
        e.g. `1 unit` or `3 units`.
    """
    return f"{count} {noun}" if count == 1 else f"{count} {noun}s"


def _group_lines(groups: Dict[str, List[str]], with_names: bool) -> List[str]:
    """Render one `[b]Group[/b] (+N): names` line per group, sorted case-insensitively.

    Args:
        groups (Dict[str, List[str]]): Group name (a mod or a faction) to the names of its added units.
        with_names (bool): List the unit names, or only the count.

    Returns:
        The lines.
    """
    lines = []
    for group, names in sorted(groups.items(), key=lambda item: item[0].lower()):
        lines.append(f"[b]{group}[/b] (+{len(names)})" + (f": {_names_list(names)}" if with_names else ""))
    return lines


def build_ttc_change_note(published: Dict[str, Dict[str, str]], current: Dict[str, Dict[str, str]], limit: int = CHANGE_NOTE_LIMIT) -> Optional[str]:
    """Build the TTC compat change note from the units added and removed since the last upload.

    Added vanilla and DLC units (entries with a `faction`) are listed by in-game name under their faction, and modded units under their mod, each in
    their own section when both appear. Past the limit, only each group's count is kept. Removed units are always listed by key at the bottom, and
    the note is cut at the limit as a last resort.

    Args:
        published (Dict[str, Dict[str, str]]): Unit key to `{mod, name, faction}` for the last uploaded pack. `faction` is only set on vanilla units.
        current (Dict[str, Dict[str, str]]): Unit key to `{mod, name, faction}` for the pack about to be uploaded.
        limit (int): Maximum note length.

    Returns:
        The change note, or None when no unit was added or removed.
    """
    by_faction: Dict[str, List[str]] = collections.defaultdict(list)
    by_mod: Dict[str, List[str]] = collections.defaultdict(list)
    removed: Dict[str, List[str]] = collections.defaultdict(list)
    for key, info in current.items():
        if key not in published:
            (by_faction[info["faction"]] if info.get("faction") else by_mod[info["mod"]]).append(info["name"])
    for key, info in published.items():
        if key not in current:
            removed[f"{info['faction']} (vanilla)" if info.get("faction") else info["mod"]].append(key)
    if not by_faction and not by_mod and not removed:
        return None

    added_parts = []
    if by_faction:
        added_parts.append(_plural(sum(map(len, by_faction.values())), "vanilla and DLC unit"))
    if by_mod:
        added_parts.append(f"{_plural(sum(map(len, by_mod.values())), 'unit')} across {_plural(len(by_mod), 'mod')}")
    summary = ["added for " + " and ".join(added_parts)] if added_parts else []
    if removed:
        summary.append(f"removed for {_plural(sum(map(len, removed.values())), 'unit')}")
    header = ["[u]Tabletop caps " + ", ".join(summary) + "[/u]"]
    removed_lines = ["", "[b]Removed (no longer in their mods)[/b]"] if removed else []
    removed_lines += [f"[b]{group}[/b] (-{len(keys)}): {', '.join(sorted(keys))}" for group, keys in sorted(removed.items(), key=lambda item: item[0].lower())]
    both = bool(by_faction) and bool(by_mod)
    for with_names in (True, False):
        lines = list(header)
        if by_faction:
            lines += [""] + (["[b]Vanilla and DLC[/b]"] if both else []) + _group_lines(by_faction, with_names)
        if by_mod:
            lines += [""] + (["[b]Mods[/b]"] if both else []) + _group_lines(by_mod, with_names)
        note = "\n".join(lines + removed_lines)
        if len(note) <= limit:
            return note
    cut = note[: limit - 4]
    return cut[: cut.rfind("\n") if "\n" in cut else len(cut)] + "\n..."


def ttc_change_note() -> Optional[str]:
    """Build the TTC compat change note from the entries saved by the last generation and by the last upload.

    Returns:
        The change note, or None when either snapshot is missing or no unit was added or removed.
    """
    published = delta._read_json(_ttc_snapshot_path())
    current = delta._read_json(delta.TTC_ENTRIES_PATH)
    if published is None or current is None:
        return None
    return build_ttc_change_note(published, current)


def pending_items(failed_units: List[str], steam_ids: Optional[Set[str]] = None) -> List[PendingItem]:
    """List generated Workshop items whose current pack differs from the last published one.

    Args:
        failed_units (List[str]): Names of units whose generator failed this run. Their outputs are never offered.
        steam_ids (Optional[Set[str]]): Only consider these Workshop items. Defaults to every generated item.

    Returns:
        The pending items, in `delta.UNITS` order.
    """
    items = []
    for unit in delta.UNITS:
        if unit.name in failed_units:
            continue
        for output in unit.outputs:
            if steam_ids is not None and output.steam_id not in steam_ids:
                continue
            current_sha = pack_sha256(output.pack_path)
            if current_sha is None:
                continue
            record = _read_record(output.steam_id)
            if record is None or record.get("pack_sha") != current_sha:
                note = (ttc_change_note() if output.steam_id == TTC_STEAM_ID else None) or build_change_note(record)
                items.append(PendingItem(output, note, current_sha))
    return items


def mark_published(output: delta.Output, change_note: str, pack_sha: str) -> None:
    """Record a successful upload and clear the item's pending reasons.

    The hash of the uploaded bytes is recorded, not the live Workshop folder, because Steam may re-sync that folder while other items are still uploading.

    Args:
        output (delta.Output): The item that was uploaded.
        change_note (str): The change note sent with the upload.
        pack_sha (str): SHA-256 of the pack that was uploaded.
    """
    record = _read_record(output.steam_id) or {}
    record.update(
        {
            "pack_sha": pack_sha,
            "published_at": time.strftime("%Y-%m-%d %H:%M:%S"),
            "last_change_note": change_note,
            "pending_mods": [],
            "pending_general": False,
        }
    )
    _write_record(output.steam_id, record)
    if output.steam_id == TTC_STEAM_ID and os.path.exists(delta.TTC_ENTRIES_PATH):
        shutil.copyfile(delta.TTC_ENTRIES_PATH, _ttc_snapshot_path())


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
        entry = _parse_publisher_line(line)
        if entry is None:
            continue
        if "fatal" in entry:
            fatal = entry["fatal"]
        else:
            results[str(entry["id"])] = entry
    return fatal, results


def _parse_publisher_line(line: str) -> Optional[Dict[str, Any]]:
    """Parse one line printed by `publish.js`.

    Args:
        line (str): A single stdout line.

    Returns:
        The result or fatal entry, or None for any other output such as Steamworks log lines.
    """
    line = line.strip()
    if not line.startswith("{"):
        return None
    try:
        entry = json.loads(line)
    except json.JSONDecodeError:
        return None
    return entry if isinstance(entry, dict) and ("fatal" in entry or "id" in entry) else None


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Uploader and publish flow


def publisher_problem() -> Optional[str]:
    """Check that the Node uploader can run.

    Returns:
        A message describing what is missing, or None when the uploader is ready.
    """
    if shutil.which("node") is None:
        return "Node.js is not installed or not on PATH."
    if not os.path.isdir(f"{PUBLISHER_DIR}/node_modules/steamworks.js"):
        return "The uploader is not set up. Run `cd helper_scripts/workshop_publisher && npm install` first."
    return None


def run_publisher(
    jobs: List[Dict[str, str]], check_only: bool, on_result: Optional[Callable[[Dict[str, Any]], None]] = None
) -> Tuple[Optional[str], Dict[str, Dict[str, Any]]]:
    """Run `publish.js` on a list of jobs, handing each result to `on_result` as soon as the uploader prints it.

    Upload progress from the uploader's stderr goes straight to the terminal. On Ctrl+C the uploader is stopped and `KeyboardInterrupt` is re-raised,
    after every result printed so far has already reached `on_result`.

    Args:
        jobs (List[Dict[str, str]]): Jobs with `id`, `contentPath` and `changeNote`.
        check_only (bool): Only check that each item exists and is owned by the logged-in account, without uploading.
        on_result (Optional[Callable[[Dict[str, Any]], None]]): Called with each item result as it arrives.

    Returns:
        A tuple of the fatal error message (or None) and the per-item results keyed by Workshop ID.
    """
    os.makedirs(PUBLISH_TEMP_DIR, exist_ok=True)
    jobs_path = os.path.abspath(f"{PUBLISH_TEMP_DIR}/jobs.json")
    with open(jobs_path, "w", encoding="utf-8") as f:
        json.dump(jobs, f, ensure_ascii=False)
    command = ["node", "publish.js", *(["--check"] if check_only else []), jobs_path]
    fatal = None
    results: Dict[str, Dict[str, Any]] = {}
    process = subprocess.Popen(command, cwd=PUBLISHER_DIR, stdout=subprocess.PIPE, text=True, encoding="utf-8", errors="replace")
    try:
        for line in process.stdout:
            entry = _parse_publisher_line(line)
            if entry is None:
                continue
            if "fatal" in entry:
                fatal = entry["fatal"]
                continue
            results[str(entry["id"])] = entry
            if on_result:
                on_result(entry)
        return_code = process.wait()
    except KeyboardInterrupt:
        process.terminate()
        process.wait()
        raise
    if fatal is None and return_code != 0 and not results:
        fatal = f"uploader exited with code {return_code}"
    return fatal, results


def _log_urls(items: List[PendingItem], statuses: Dict[str, str]) -> None:
    """Log the Workshop URL and final status of every item this run worked on.

    Args:
        items (List[PendingItem]): Items that were pending this run.
        statuses (Dict[str, str]): Status text keyed by Workshop ID.
    """
    logging.info("Workshop items worked on:")
    for item in items:
        logging.info(f"  {WORKSHOP_URL}{item.output.steam_id}  {statuses.get(item.output.steam_id, 'not published')}")


def publish_pending(
    items: List[PendingItem],
    dry_run: bool,
    no_publish: bool,
    confirm: Callable[[str], str] = input,
    is_interactive: Optional[Callable[[], bool]] = None,
) -> None:
    """Show the pending Workshop uploads, ask for confirmation, upload them and log each item's URL and result.

    Nothing is uploaded on a dry run, with `--no-publish`, outside an interactive terminal, or without an explicit `y`. An item that fails its
    preflight or upload stays pending for the next run.

    Args:
        items (List[PendingItem]): Items whose current pack has not been published yet.
        dry_run (bool): Only list the pending items.
        no_publish (bool): Only list the pending items, because the user asked to skip publishing.
        confirm (Callable[[str], str]): Prompt function. Defaults to `input`.
        is_interactive (Optional[Callable[[], bool]]): Returns whether a person can answer the prompt. Defaults to checking that stdin is a TTY.
    """
    if not items:
        logging.info("Nothing to publish.")
        return
    logging.info("Pending Workshop uploads:")
    for item in items:
        logging.info(f"  {item.output.steam_id} {item.output.pack_name} - {item.change_note}")
    if dry_run or no_publish:
        logging.info("Not publishing (" + ("--dry-run" if dry_run else "--no-publish") + "). The items stay pending.")
        return
    if not (is_interactive or sys.stdin.isatty)():
        logging.info("Not an interactive terminal, skipping publish. The items stay pending.")
        return
    problem = publisher_problem()
    if problem:
        logging.warning(f"Cannot publish: {problem}")
        return

    fatal, checks = run_publisher([{"id": item.output.steam_id, "contentPath": "", "changeNote": ""} for item in items], check_only=True)
    if fatal:
        logging.warning(f"Cannot publish: {fatal}. Nothing was uploaded.")
        return
    statuses: Dict[str, str] = {}
    ready = []
    for item in items:
        check = checks.get(item.output.steam_id, {})
        if check.get("ok"):
            ready.append(item)
        else:
            statuses[item.output.steam_id] = f"not published (preflight: {check.get('error', 'no result')})"
    if not ready:
        _log_urls(items, statuses)
        return

    try:
        answer = confirm(f"Publish {len(ready)} item(s) to the Steam Workshop? [y/N] ")
    except EOFError:
        # Nobody can answer when input is closed, so treat it as a no.
        answer = ""
    if answer.strip().lower() not in ("y", "yes"):
        logging.info("Publishing cancelled. The items stay pending.")
        _log_urls(items, statuses)
        return

    by_id = {item.output.steam_id: item for item in ready}

    def record_result(result: Dict[str, Any]) -> None:
        """Record one upload result the moment the uploader reports it, so an interruption cannot lose it.

        Args:
            result (Dict[str, Any]): A result line from `publish.js`.
        """
        item = by_id.get(str(result["id"]))
        if item is None:
            return
        if not result.get("ok"):
            statuses[item.output.steam_id] = f"FAILED: {result.get('error', 'unknown error')}"
            return
        try:
            mark_published(item.output, item.change_note, item.pack_sha)
        except OSError as err:
            statuses[item.output.steam_id] = f"published, but recording it failed ({err}), so it will be offered again"
            return
        agreement = " (accept the Steam Workshop legal agreement on the Steam site before it becomes visible)" if result.get("needsToAcceptAgreement") else ""
        statuses[item.output.steam_id] = f"published{agreement}"

    fatal = None
    interrupted = False
    try:
        jobs = []
        for item in ready:
            content = stage_content(item.output, PUBLISH_TEMP_DIR)
            if file_sha256(os.path.join(content, item.output.pack_name)) != item.pack_sha:
                statuses[item.output.steam_id] = "FAILED: the pack changed since it was listed. Run update.py again."
                continue
            jobs.append({"id": item.output.steam_id, "contentPath": content, "changeNote": item.change_note})
        if jobs:
            logging.info(f"Uploading {len(jobs)} item(s). Large packs can take several minutes...")
            fatal, _ = run_publisher(jobs, check_only=False, on_result=record_result)
    except KeyboardInterrupt:
        interrupted = True
        logging.warning("Upload interrupted. Items that finished uploading are recorded. The rest stay pending.")
    finally:
        shutil.rmtree(PUBLISH_TEMP_DIR, ignore_errors=True)
    for item in ready:
        if item.output.steam_id not in statuses:
            if interrupted:
                statuses[item.output.steam_id] = "not published (interrupted)"
            else:
                statuses[item.output.steam_id] = f"FAILED: {fatal or 'no result from the uploader'}"
    _log_urls(items, statuses)
