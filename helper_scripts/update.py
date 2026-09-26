"""Delta-update every generated Workshop pack with one command.

Nanu's Dynamic RoR effect list is synced from his pack first, so renamed or removed effects never reach the compat packs. Each generator script is
only re-run when a table it read on its last run changed, when its code or the rpfm schema changed, or when its Workshop pack no longer matches the
last build. Rebuilt packs whose generated files are identical to the previous build are left untouched. Hand-made mods get review flags when the
tables they depend on change. Finally, every generated pack that differs from what was last published is offered for upload to its Steam Workshop
item, which happens only after an interactive `y`.

Usage:
    python update.py               Rebuild only what changed, then offer to publish.
    python update.py --dry-run     Show what would be rebuilt and what is waiting to be published.
    python update.py --no-publish  Rebuild only what changed and list what is waiting to be published, without uploading.
    python update.py --only 3310629727  Update and publish only these Workshop items. Everything else waits for the next run.
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

from core import delta
from core.extract_cache import prune_cache
from core.utilities import log_elapsed_time, run_rpfm_cli, setup_script_logging
from tools import update_dynamic_ror_effects
from tools.update_dynamic_ror_effects import EffectSync
from publish import workshop_publish


RUN_REPORT_PATH = f"{delta.PENDING_DIR}/run_report.jsonl"
# Nanu's effect list, synced from his pack before the staleness check. Units that read it rebuild when the sync changes it.
EFFECTS_FILE = update_dynamic_ror_effects.DYNAMIC_RORS_EFFECTS_FILE


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


def sync_dynamic_ror_effects(units: List[delta.Unit], dry_run: bool) -> Optional[EffectSync]:
    """Sync the Dynamic RoR effect list with Nanu's pack when a Dynamic RoR pack is being updated.

    Args:
        units (List[delta.Unit]): Units in scope for this run.
        dry_run (bool): Only report what would change, without writing the file.

    Returns:
        What changed, or None when no unit in scope reads the effect list.
    """
    if not any(EFFECTS_FILE in unit.code_files for unit in units):
        return None
    logging.info("Syncing Nanu's Dynamic RoR effects...")
    return update_dynamic_ror_effects.sync_effects(write=not dry_run)


def flag_pending_effect_sync(check: delta.UnitCheck, effect_sync: Optional[EffectSync], dry_run: bool) -> delta.UnitCheck:
    """Mark a unit stale in a dry run when it reads an effect list the sync would change, since the file itself is left unwritten.

    A real run writes the file, so the unit's code hash already makes it stale.

    Args:
        check (delta.UnitCheck): The unit's staleness result.
        effect_sync (Optional[EffectSync]): This run's sync result, or None if no sync ran.
        dry_run (bool): True for a dry run.

    Returns:
        A stale check for an affected unit, otherwise `check` unchanged.
    """
    if not dry_run or effect_sync is None or not effect_sync.changed or check.stale or EFFECTS_FILE not in check.unit.code_files:
        return check
    return delta.UnitCheck(check.unit, stale=True, reasons=["Nanu's effect list changed"], general=True)


def log_summary(
    checks: List[delta.UnitCheck], statuses: Dict[str, str], failed: List[str], reduce_winds_changed: List[str], dry_run: bool
) -> None:
    """Log the end-of-run summary, including which packs changed this run and the hand-made mod review flags.

    Args:
        checks (List[delta.UnitCheck]): Staleness results for every unit.
        statuses (Dict[str, str]): Output statuses reported by `delta.publish_pack` during this run.
        failed (List[str]): Names of units whose script exited with an error.
        reduce_winds_changed (List[str]): Vanilla trait tables that changed since the last run.
        dry_run (bool): True when nothing was rebuilt.
    """
    logging.info("=" * 100)
    logging.info("Delta update summary" + (" (dry run, nothing was rebuilt)" if dry_run else ""))
    changed, unchanged = [], []
    for check in checks:
        for output in check.unit.outputs:
            status = statuses.get(output.steam_id)
            line = f"{output.steam_id} {output.pack_name}"
            if check.unit.name in failed:
                continue
            if dry_run and check.stale:
                changed.append(f"{line} - would rebuild: {summarize_reasons(check.reasons)}")
            elif status == "updated":
                changed.append(f"{line} - {summarize_reasons(check.reasons)}")
            elif status == "unchanged":
                unchanged.append(f"{line} (rebuilt, identical output)")
            elif check.stale and not dry_run:
                changed.append(f"{line} - rebuilt but no pack write was reported, check the log above")
            else:
                unchanged.append(f"{line} (inputs unchanged, skipped)")

    logging.info("Would rebuild:" if dry_run else "Changed this run:")
    for line in changed or ["(none)"]:
        logging.info(f"  {line}")
    logging.info("Unchanged:")
    for line in unchanged or ["(none)"]:
        logging.info(f"  {line}")
    if failed:
        logging.info(f"Failed (state not saved, will retry next run): {', '.join(failed)}")

    ttc_summary = delta._read_json(f"{delta.STATE_ROOT}/ttc_summary.json")
    if ttc_summary:
        report = ttc_summary["report"].removeprefix("./")
        logging.info(f"TTC compat (3310629727): {ttc_summary['auto']} auto-assigned, {ttc_summary['review']} need review -> helper_scripts/{report}")
    else:
        logging.info("TTC compat (3310629727): not generated yet")

    logging.info("Hand-made mods to review:")
    if reduce_winds_changed:
        logging.info(f"  3012881957 reduce_winds_of_magic_cost - vanilla tables changed: {', '.join(reduce_winds_changed)}")
    else:
        logging.info("  3012881957 reduce_winds_of_magic_cost - no vanilla trait table changes")
    logging.info("  3387635246 !!!1a_glf_battle_mage_Dante - upstream Battle Mage mod is not installed, so it is not tracked")
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
    parser.add_argument("--no-publish", action="store_true", help="Build only. List the packs waiting to be published without uploading them.")
    parser.add_argument("--only", nargs="+", metavar="WORKSHOP_ID", help="Only rebuild and publish these generated Workshop items. Everything else waits for the next run.")
    args = parser.parse_args()
    only = set(args.only) if args.only else None
    try:
        units = delta.units_for_items(only) if only else delta.UNITS
    except ValueError as err:
        parser.error(str(err))
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

    effect_sync = sync_dynamic_ror_effects(units, args.dry_run)

    # Decide which units are stale.
    checks: List[delta.UnitCheck] = []
    for unit in units:
        if args.full:
            check = delta.UnitCheck(unit, stale=True, reasons=["full rebuild requested"], general=True)
        else:
            logging.info(f"Checking {unit.name} for changed inputs...")
            check = flag_pending_effect_sync(delta.check_unit(unit), effect_sync, args.dry_run)
        logging.info(f"{unit.name}: {'REBUILD - ' + summarize_reasons(check.reasons) if check.stale else 'up to date'}")
        checks.append(check)

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
        for check in checks:
            if check.stale and check.unit.name not in failed:
                workshop_publish.record_rebuild(check, statuses)
        removed = prune_cache(delta.referenced_pack_shas())
        if removed:
            logging.info(f"Pruned cached extractions for {removed} outdated pack version(s).")

    log_summary(checks, statuses, failed, reduce_winds_changed, args.dry_run)
    log_elapsed_time("updating all mods", start_time)
    workshop_publish.publish_pending(workshop_publish.pending_items(failed, only), args.dry_run, args.no_publish)
