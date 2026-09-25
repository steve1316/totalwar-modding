"""Generate TTC compat entries for every recruitable modded unit that has no hand-written entry.

Hand files are authoritative. Auto entries go to `!!!!!!!<mod>_auto.lua`, low-confidence picks are listed in `reports/ttc_review.md`, and the
`script/` folder is packed into the TTC compat Workshop pack. Nothing is written if confident picks miss the accuracy bar.
"""

import glob
import json
import logging
import os
import time
from typing import Dict, List, Optional, Tuple

import delta
import ttc_classifier
import ttc_compat_io
import ttc_data
from pipeline import add_folder_to_pack, reset_pack_folders, workshop_pack_path
from utilities import clear_temp_root, setup_script_logging

STEAM_ID = "3310629727"
PACK_PATH = workshop_pack_path(STEAM_ID, "!!!!!!!yet_another_tabletopcaps_compat.pack")
SCRIPT_SOURCE = "../warhammer3_mods/!!!!!!!yet_another_tabletopcaps_compat/script"
REPORT_PATH = "./reports/ttc_review.md"
SUMMARY_PATH = f"{delta.STATE_ROOT}/ttc_summary.json"
# Unit key to the mod that last defined it, so entries for a temporarily unsubscribed mod are never removed.
OWNER_HISTORY_PATH = f"{delta.STATE_ROOT}/ttc_unit_owners.json"


def write_auto_files(assignments: Dict[str, Dict[str, List[Tuple[str, str, Optional[int]]]]], mod_names: Dict[str, str]) -> List[str]:
    """Write one `_auto.lua` per mod and delete auto files for mods that no longer have targets.

    Args:
        assignments (Dict[str, Dict[str, List[Tuple[str, str, Optional[int]]]]]): Package name to group comment to entries.
        mod_names (Dict[str, str]): Package name to display name for the header.

    Returns:
        Paths of the files written.
    """
    written = []
    for package_name, groups in sorted(assignments.items()):
        path = ttc_compat_io.auto_file_path(package_name)
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            f.write(ttc_compat_io.render_auto_file(mod_names.get(package_name, package_name), groups))
        written.append(path)
    keep = {os.path.normcase(os.path.abspath(p)) for p in written}
    for path in glob.glob(os.path.join(ttc_compat_io.HAND_DIR, "*_auto.lua")):
        if os.path.normcase(os.path.abspath(path)) not in keep:
            os.remove(path)
    return written


def render_report(metrics_line: str, counts: Dict[str, int], review_rows: List[tuple], removed: List[Tuple[str, str]], missing_mods: List[str]) -> str:
    """Render the after-action report.

    Args:
        metrics_line (str): Held-out accuracy summary.
        counts (Dict[str, int]): `labeled`, `targets`, `confident`, `review` and `removed` counts.
        review_rows (List[tuple]): `(mod, key, pick, confidence, runner_up, cost, caste, class, num_men, lookalikes)` per low-confidence unit.
        removed (List[Tuple[str, str]]): `(hand file name, removed line)` pairs.
        missing_mods (List[str]): Supported mods that are not installed.

    Returns:
        Markdown text.
    """
    lines = [
        "# TTC compat review",
        "",
        f"Generated {time.strftime('%Y-%m-%d %H:%M:%S')} by `update_ttc_compat.py`.",
        "",
        "## Summary",
        "",
        f"- Labeled entries (vanilla list + hand files): {counts['labeled']}",
        f"- Units auto-assigned: {counts['targets']} ({counts['confident']} confident, {counts['review']} need review)",
        f"- Hand entries removed: {counts['removed']}",
        f"- Classifier: {metrics_line}",
        "",
        "## Needs review",
        "",
        "To confirm or fix a pick, copy its line from the mod's `_auto.lua` into the mod's hand file and adjust it. It then counts as a hand entry.",
        "",
        "| Mod | Unit | Pick | Confidence | Runner-up | Cost | Caste | Class | Men | Lookalikes |",
        "|---|---|---|---|---|---|---|---|---|---|",
    ]
    for mod, key, pick, confidence, runner_up, cost, caste, cls, men, lookalikes in review_rows:
        looks = ", ".join(f"{k} ({label})" for k, label in lookalikes)
        lines.append(f"| {mod} | {key} | {pick} | {confidence:.2f} | {runner_up} | {cost} | {caste} | {cls} | {men} | {looks} |")
    lines += ["", "## Removed hand entries", ""]
    lines += [f"- {name}: `{line.strip()}`" for name, line in removed] or ["- (none)"]
    lines += ["", "## Supported mods not installed", ""]
    lines += [f"- {name}" for name in missing_mods] or ["- (none)"]
    return "\n".join(lines) + "\n"


def _split(label: str) -> Tuple[str, Optional[int]]:
    """Split a label into category and weight.

    Args:
        label (str): e.g. `special,2` or `core`.

    Returns:
        `(category, weight or None)`.
    """
    category, _, weight = label.partition(",")
    return category, int(weight) if weight else None


def main() -> int:
    """Run one TTC generation.

    Returns:
        Process exit code: 0 on success, 1 if confident picks miss the accuracy bar.
    """
    data = ttc_data.load_all()
    context = ttc_classifier.PeerContext(data.stats, data.labels)
    model, metrics = ttc_classifier.train(ttc_classifier.training_set(data), ttc_classifier.training_groups(data), context)
    metrics_line = (
        f"held-out exact {metrics.exact:.1%}, category {metrics.category:.1%}, confident {metrics.confident:.1%} "
        f"on {metrics.confident_share:.1%} of entries (threshold {metrics.threshold:.3f}), unseen-mod exact {metrics.unseen_mod_exact:.1%}"
    )
    logging.info(f"TTC classifier: {metrics_line}")
    if metrics.confident < ttc_classifier.CONFIDENT_ACCURACY_BAR:
        logging.error("Confident picks are below the accuracy bar. No TTC files were written.")
        os.makedirs(os.path.dirname(REPORT_PATH), exist_ok=True)
        with open(REPORT_PATH, "w", encoding="utf-8", newline="\n") as f:
            f.write(f"# TTC compat review\n\nFAILED: {metrics_line}. Confident picks must reach {ttc_classifier.CONFIDENT_ACCURACY_BAR:.0%}.\n")
        return 1

    targets = ttc_data.select_targets(data.mod_units, data.vanilla_keys, data.permissions, set(data.labels))
    keys = sorted(targets)
    non_core = [ttc_data.is_regiment_of_renown(key, data.stats[key].main, targets[key]) for key in keys]
    predictions = model.predict([data.stats[key] for key in keys], non_core)
    assignments: Dict[str, Dict[str, List[Tuple[str, str, Optional[int]]]]] = {}
    review_rows = []
    for key, prediction in zip(keys, predictions):
        package_name = targets[key]
        stats = data.stats[key]
        group = sorted(stats.groups)[0] if stats.groups else "unknown"
        category, weight = _split(prediction.label)
        assignments.setdefault(package_name, {}).setdefault(group, []).append((key, category, weight))
        if not prediction.confident:
            review_rows.append(
                (
                    data.mod_names.get(package_name, package_name),
                    key,
                    prediction.label,
                    prediction.confidence,
                    prediction.runner_up,
                    stats.main.get("multiplayer_cost", ""),
                    stats.main.get("caste", ""),
                    stats.land.get("class", ""),
                    stats.main.get("num_men", ""),
                    model.nearest_labeled(stats),
                )
            )
    review_rows.sort(key=lambda row: (row[0], row[1]))
    write_auto_files(assignments, data.mod_names)

    package_names = [name for name, _ in data.mod_units] + data.missing_mods
    file_mod = {path: ttc_data.hand_file_mod(path, package_names) for path in data.hand_entries}
    history = ttc_data.merge_owner_history(delta._read_json(OWNER_HISTORY_PATH) or {}, data.units_by_mod)
    stale = ttc_data.stale_hand_entries(data.hand_entries, file_mod, data.installed, data.units_by_mod, data.vanilla_keys, history)
    removed = []
    for path, keys_to_remove in sorted(stale.items()):
        removed += [(os.path.basename(path), line) for line in ttc_compat_io.remove_lines(path, keys_to_remove)]

    confident_count = sum(1 for p in predictions if p.confident)
    counts = {"labeled": metrics.n, "targets": len(keys), "confident": confident_count, "review": len(review_rows), "removed": len(removed)}
    os.makedirs(os.path.dirname(REPORT_PATH), exist_ok=True)
    with open(REPORT_PATH, "w", encoding="utf-8", newline="\n") as f:
        skipped_mods = data.missing_mods + [f"{name} (main_units_tables unreadable, check the rpfm schema)" for name in data.unreadable_mods]
        f.write(render_report(metrics_line, counts, review_rows, removed, skipped_mods))
    os.makedirs(os.path.dirname(SUMMARY_PATH), exist_ok=True)
    with open(SUMMARY_PATH, "w", encoding="utf-8") as f:
        json.dump({"auto": len(keys), "review": len(review_rows), "removed": len(removed), "report": REPORT_PATH}, f)
    delta._write_json(OWNER_HISTORY_PATH, history)

    def write_pack() -> None:
        """Replace the pack's `script/` folder with the regenerated compat files."""
        reset_pack_folders(PACK_PATH, ("script",))
        add_folder_to_pack(PACK_PATH, f"{SCRIPT_SOURCE};script")

    delta.publish_pack(STEAM_ID, PACK_PATH, SCRIPT_SOURCE, write_pack)
    logging.info(f"TTC compat: {len(keys)} auto-assigned, {len(review_rows)} need review, {len(removed)} hand entries removed. Report: {REPORT_PATH}")
    return 0


if __name__ == "__main__":
    setup_script_logging()
    try:
        exit_code = main()
    finally:
        clear_temp_root()
    raise SystemExit(exit_code)
