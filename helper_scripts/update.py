"""Delta-update every generated Workshop pack with one command.

Each generator script is only re-run when a table it read on its last run changed, when its code or the rpfm schema changed, or when its Workshop pack
no longer matches the last build. Rebuilt packs whose generated files are identical to the previous build are left untouched, and the summary lists the
Workshop IDs that need uploading. Hand-made mods get review flags when the tables they depend on change.

Usage:
    python update.py             Rebuild only what changed.
    python update.py --dry-run   Show what would be rebuilt and why.
    python update.py --full      Rebuild every pack, still using the extraction cache.
    python update.py --no-cache  Rebuild every pack from a cold rpfm extraction.

The rpfm schemas are updated first so tables changed by a game patch can still be read. Pass `--no-schema-update` to skip that.
"""

import argparse
import logging
import os
import signal
import subprocess
import time
from typing import Dict, List, Optional

import delta
from extract_cache import prune_cache
from utilities import log_elapsed_time, run_rpfm_cli, setup_script_logging


WORKSHOP_URL = "https://steamcommunity.com/sharedfiles/filedetails/?id="
RUN_REPORT_PATH = f"{delta.PENDING_DIR}/run_report.jsonl"


def run_script(cmd: List[str], env: Dict[str, str]) -> int:
    """Run a script and return its exit code, forwarding Ctrl+C to it.

    Args:
        cmd (List[str]): The command to run.
        env (Dict[str, str]): Environment variables for the child process.

    Returns:
        The exit code of the script.
    """
    p = subprocess.Popen(cmd, env=env)
    try:
        return p.wait()
    except KeyboardInterrupt:
        p.send_signal(signal.SIGINT)
        p.wait()
        raise


def summarize_reasons(reasons: List[str], limit: int = 5) -> str:
    """Join rebuild reasons into one line, truncating long lists.

    Args:
        reasons (List[str]): Reasons from `delta.check_unit`.
        limit (int): Maximum reasons to show. Defaults to 5.

    Returns:
        A single display line.
    """
    shown = "; ".join(reasons[:limit])
    return shown + (f"; and {len(reasons) - limit} more" if len(reasons) > limit else "")


def log_summary(
    checks: List[delta.UnitCheck], statuses: Dict[str, str], failed: List[str], reduce_winds_changed: List[str], ttc_lines: Optional[List[str]], dry_run: bool
) -> None:
    """Log the end-of-run summary, including the Workshop upload list and hand-made mod review flags.

    Args:
        checks (List[delta.UnitCheck]): Staleness results for every unit.
        statuses (Dict[str, str]): Output statuses reported by `delta.publish_pack` during this run.
        failed (List[str]): Names of units whose script exited with an error.
        reduce_winds_changed (List[str]): Vanilla trait tables that changed since the last run.
        ttc_lines (Optional[List[str]]): Mods whose unit tables changed, for the TTC compat review. None when the review could not run.
        dry_run (bool): True when nothing was rebuilt.
    """
    logging.info("=" * 100)
    logging.info("Delta update summary" + (" (dry run, nothing was rebuilt)" if dry_run else ""))
    needs_upload, unchanged = [], []
    for check in checks:
        for output in check.unit.outputs:
            status = statuses.get(output.steam_id)
            line = f"{output.steam_id} {output.pack_name}"
            if check.unit.name in failed:
                continue
            if dry_run and check.stale:
                needs_upload.append(f"{line} - would rebuild: {summarize_reasons(check.reasons)}")
            elif status == "updated":
                needs_upload.append(f"{line} - {summarize_reasons(check.reasons)}")
            elif status == "unchanged":
                unchanged.append(f"{line} (rebuilt, identical output)")
            elif check.stale and not dry_run:
                needs_upload.append(f"{line} - rebuilt but no pack write was reported, check the log above")
            else:
                unchanged.append(f"{line} (inputs unchanged, skipped)")

    logging.info("Would rebuild:" if dry_run else "Needs Workshop upload:")
    for line in needs_upload or ["(none)"]:
        logging.info(f"  {line}")
    logging.info("Unchanged:")
    for line in unchanged or ["(none)"]:
        logging.info(f"  {line}")
    if failed:
        logging.info(f"Failed (state not saved, will retry next run): {', '.join(failed)}")

    logging.info("Hand-made mods to review:")
    if ttc_lines is None:
        logging.info("  3310629727 yet_another_tabletopcaps_compat - not checked on full rebuilds or the first tracked run")
    elif ttc_lines:
        logging.info(f"  3310629727 yet_another_tabletopcaps_compat - unit tables changed in: {', '.join(ttc_lines)}")
    else:
        logging.info("  3310629727 yet_another_tabletopcaps_compat - no tracked unit table changes")
    if reduce_winds_changed:
        logging.info(f"  3012881957 reduce_winds_of_magic_cost - vanilla tables changed: {', '.join(reduce_winds_changed)}")
    else:
        logging.info("  3012881957 reduce_winds_of_magic_cost - no vanilla trait table changes")
    logging.info("  3387635246 !!!1a_glf_battle_mage_Dante - upstream Battle Mage mod is not installed, so it is not tracked")

    if needs_upload and not dry_run:
        logging.info("Upload links:")
        for check in checks:
            for output in check.unit.outputs:
                if statuses.get(output.steam_id) == "updated":
                    logging.info(f"  {WORKSHOP_URL}{output.steam_id}")
    logging.info("=" * 100)


if __name__ == "__main__":
    setup_script_logging()
    start_time = time.time()

    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--workers",
        type=int,
        default=None,
        help="Worker thread count forwarded to each parallel-capable subscript. When omitted, each subscript uses its own default of min(8, cpu_count()).",
    )
    parser.add_argument("--full", action="store_true", help="Rebuild every pack even if its inputs are unchanged. Still uses the extraction cache.")
    parser.add_argument("--no-cache", action="store_true", help="Rebuild every pack from a cold rpfm extraction. Implies --full.")
    parser.add_argument("--dry-run", action="store_true", help="Only report which packs would be rebuilt and why.")
    parser.add_argument("--no-schema-update", action="store_true", help="Skip pulling the latest rpfm schemas before checking for changes.")
    args = parser.parse_args()
    workers_args = ["--workers", str(args.workers)] if args.workers is not None else []
    if args.no_cache:
        os.environ["EXTRACT_CACHE"] = "0"
        args.full = True

    # An outdated schema makes rpfm silently extract patched tables as binary, which drops them from every compat pack.
    if not args.no_schema_update:
        logging.info("Updating rpfm schemas...")
        schema_update = run_rpfm_cli(["schemas", "update", "--schema-path", "./schemas"], capture_output=True, text=True)
        # rpfm exits with 1 and "No updates available" when the schemas are already current.
        if "No updates available" in f"{schema_update.stdout}{schema_update.stderr}":
            logging.info("rpfm schemas are already up to date.")
        elif schema_update.returncode != 0:
            logging.warning("Schema update failed. Continuing with the current schemas.")
        else:
            logging.info("rpfm schemas updated.")
    run_rpfm_cli(["schemas", "to-json", "--schemas-path", "./schemas"], capture_output=True)

    # Decide which units are stale.
    checks: List[delta.UnitCheck] = []
    for unit in delta.UNITS:
        if args.full:
            check = delta.UnitCheck(unit, stale=True, reasons=["full rebuild requested"])
        else:
            logging.info(f"Checking {unit.name} for changed inputs...")
            check = delta.check_unit(unit)
        logging.info(f"{unit.name}: {'REBUILD - ' + summarize_reasons(check.reasons) if check.stale else 'up to date'}")
        checks.append(check)

    # The TTC review needs the recorded dynamic_rors accesses, which only exist after a tracked build and are not replayed on full rebuilds.
    dynamic_rors_check = next(check for check in checks if check.unit.name == "dynamic_rors")
    ttc_lines = None if args.full or "no previous tracked build" in dynamic_rors_check.reasons else delta.ttc_review(checks)
    reduce_winds_changed = delta.check_reduce_winds_tables(commit=not args.dry_run)

    failed: List[str] = []
    statuses: Dict[str, str] = {}
    if not args.dry_run:
        os.makedirs(delta.PENDING_DIR, exist_ok=True)
        if os.path.exists(RUN_REPORT_PATH):
            os.remove(RUN_REPORT_PATH)

        for check in checks:
            if not check.stale:
                continue
            unit = check.unit
            access_log = f"{delta.PENDING_DIR}/{unit.name}.jsonl"
            if os.path.exists(access_log):
                os.remove(access_log)
            env = {**os.environ, "DELTA_ACCESS_LOG": access_log, "DELTA_REPORT": RUN_REPORT_PATH, "DELTA_SKIP_UNCHANGED": "1"}

            logging.info(f"Rebuilding {unit.name}: python {' '.join(unit.command + workers_args)}")
            exit_code = run_script(["python", *unit.command, *workers_args], env)
            if exit_code == 0:
                delta.commit_unit(unit, access_log)
            else:
                logging.error(f"{unit.name} exited with code {exit_code}. Its state was not saved, so it will be rebuilt next run.")
                failed.append(unit.name)

        statuses = delta.read_report(RUN_REPORT_PATH)
        removed = prune_cache(delta.referenced_pack_shas())
        if removed:
            logging.info(f"Pruned cached extractions for {removed} outdated pack version(s).")

    log_summary(checks, statuses, failed, reduce_winds_changed, ttc_lines, args.dry_run)
    log_elapsed_time("updating all mods", start_time)
