"""Command line access to Workshop change notes and publish records, for the translator app.

The app publishes compat packs itself through SteamCMD, so it runs this module from `helper_scripts/` to fetch the note `update.py` would send and
to record a successful upload so `update.py` stops offering it. All note logic lives in `workshop_publish`.

Usage:
    python -m publish.change_notes preview <steam_id> [<steam_id> ...]
    python -m publish.change_notes record <steam_id> --pack-sha <sha> --note-file <path>
"""

import argparse
import json
import sys
from typing import Any, Dict, List, Optional

from core import delta
from publish import workshop_publish


def find_output(steam_id: str) -> Optional[delta.Output]:
    """Find the generated Workshop item with a given ID.

    Args:
        steam_id (str): Workshop ID of the item.

    Returns:
        The item's output, or None if no generator writes it.
    """
    for unit in delta.UNITS:
        for output in unit.outputs:
            if output.steam_id == steam_id:
                return output
    return None


def preview(steam_ids: List[str]) -> Dict[str, Optional[Dict[str, Any]]]:
    """Build the change note each item would be uploaded with right now.

    Args:
        steam_ids (List[str]): Workshop IDs of the items.

    Returns:
        Each ID mapped to `{note, pack_sha, pending}`, or None when the ID is not a generated item or its pack is missing. `pending` is False when
        the pack matches the last recorded upload.
    """
    result: Dict[str, Optional[Dict[str, Any]]] = {}
    for steam_id in steam_ids:
        output = find_output(steam_id)
        pack_sha = workshop_publish.pack_sha256(output.pack_path) if output is not None else None
        if output is None or pack_sha is None:
            result[steam_id] = None
            continue
        record = workshop_publish._read_record(steam_id)
        result[steam_id] = {
            "note": workshop_publish._change_note(steam_id, record),
            "pack_sha": pack_sha,
            "pending": record is None or record.get("pack_sha") != pack_sha,
        }
    return result


def record(steam_id: str, pack_sha: str, note: str) -> None:
    """Record a successful upload made outside `update.py`.

    Args:
        steam_id (str): Workshop ID of the uploaded item.
        pack_sha (str): SHA-256 of the pack that was uploaded.
        note (str): The change note sent with the upload.

    Raises:
        ValueError: When the ID is not a generated Workshop item.
    """
    output = find_output(steam_id)
    if output is None:
        raise ValueError(f"{steam_id} is not a generated Workshop item")
    workshop_publish.mark_published(output, note, pack_sha)


def main(argv: Optional[List[str]] = None) -> int:
    """Run the `preview` or `record` command.

    Args:
        argv (Optional[List[str]]): Command line arguments. Defaults to `sys.argv[1:]`.

    Returns:
        The process exit code.
    """
    parser = argparse.ArgumentParser(description="Preview or record Workshop change notes for generated packs.")
    commands = parser.add_subparsers(dest="command", required=True)
    preview_parser = commands.add_parser("preview", help="Print the change note for each item as one JSON line.")
    preview_parser.add_argument("steam_ids", nargs="+")
    record_parser = commands.add_parser("record", help="Record a successful upload of an item.")
    record_parser.add_argument("steam_id")
    record_parser.add_argument("--pack-sha", required=True)
    record_parser.add_argument("--note-file", required=True)
    args = parser.parse_args(argv)

    if args.command == "preview":
        # ASCII-only JSON on one line, so the caller can parse the last stdout line regardless of the console encoding.
        print(json.dumps(preview(args.steam_ids)))
        return 0

    with open(args.note_file, "r", encoding="utf-8") as f:
        note = f.read()
    try:
        record(args.steam_id, args.pack_sha, note)
    except ValueError as err:
        print(err, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
