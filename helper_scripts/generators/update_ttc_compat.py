"""Generate TTC compat entries for every recruitable modded, vanilla or DLC unit that has no cap yet.

Hand files are authoritative. Auto entries go to `!!!!!!!<mod>_auto.lua`, low-confidence picks are listed in `reports/ttc_review.md`, and the
`script/` folder is packed into the TTC compat Workshop pack. Nothing is written if confident picks miss the accuracy bar.
"""

import collections
import glob
import json
import logging
import os
import time
from typing import Dict, List, Optional, Tuple

from core import delta
from core.extract_cache import cache_enabled
from core.pipeline import add_folder_to_pack, reset_pack_folders, workshop_pack_path
from core.utilities import clear_temp_root, setup_script_logging
from ttc import ttc_cards, ttc_classifier, ttc_compat_io, ttc_data

STEAM_ID = "3310629727"
PACK_PATH = workshop_pack_path(STEAM_ID, "!!!!!!!yet_another_tabletopcaps_compat.pack")
SCRIPT_SOURCE = "../warhammer3_mods/!!!!!!!yet_another_tabletopcaps_compat/script"
REPORT_PATH = "./reports/ttc_review.md"
SUMMARY_PATH = f"{delta.STATE_ROOT}/ttc_summary.json"
# Every auto pick, confident or not, for the `tools.ttc_review` unit browser.
AUTO_PICKS_PATH = f"{delta.STATE_ROOT}/ttc_auto_picks.json"
# Unit key to the mod that last defined it, so entries for a temporarily unsubscribed mod are never removed.
OWNER_HISTORY_PATH = f"{delta.STATE_ROOT}/ttc_unit_owners.json"
# Last trained classifier, reused when its training inputs have not changed.
MODEL_CACHE_PATH = f"{delta.STATE_ROOT}/ttc_model.pkl"


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


def collect_entries(file_mods: Dict[str, str]) -> Dict[str, str]:
    """Map every entry in the compat files to the mod it covers.

    Args:
        file_mods (Dict[str, str]): Compat file name to mod display name. Files not listed fall back to their name without the `!` prefix.

    Returns:
        Unit key to mod display name, the first file in name order winning.
    """
    entries: Dict[str, str] = {}
    for path in sorted(glob.glob(os.path.join(ttc_compat_io.HAND_DIR, "*.lua"))):
        name = os.path.basename(path)
        mod = file_mods.get(name) or name.lstrip("!").removesuffix(".lua")
        for entry in ttc_compat_io.parse_ttc_file(path):
            entries.setdefault(entry.key, mod)
    return entries


def _without_timestamp(text: str) -> List[str]:
    """Drop the report's `Generated ...` line so two reports can be compared by content.

    Args:
        text (str): Report text.

    Returns:
        The report lines without the timestamp line.
    """
    return [line for line in text.splitlines() if not line.startswith("Generated ")]


def write_report(text: str) -> None:
    """Write the review report, unless only its timestamp would change, so an unchanged review does not show up as a git change.

    Args:
        text (str): The new report text.
    """
    if os.path.exists(REPORT_PATH):
        with open(REPORT_PATH, encoding="utf-8") as f:
            if _without_timestamp(f.read()) == _without_timestamp(text):
                return
    os.makedirs(os.path.dirname(REPORT_PATH), exist_ok=True)
    with open(REPORT_PATH, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)


def render_report(
    metrics_line: str, counts: Dict[str, int], review_rows: List[dict], removed: List[Tuple[str, str]], missing_mods: List[str], ignored: List[str]
) -> str:
    """Render the after-action report.

    Args:
        metrics_line (str): Held-out accuracy summary.
        counts (Dict[str, int]): `labeled`, `targets`, `confident`, `review` and `removed` counts.
        review_rows (List[dict]): Review record per low-confidence unit, as written to `REVIEW_DATA_PATH`.
        removed (List[Tuple[str, str]]): `(hand file name, removed line)` pairs.
        missing_mods (List[str]): Supported mods that are not installed.
        ignored (List[str]): Recruitable units left out because no pack ships card art for them.

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
        "| Mod | Unit | Name | Pick | Confidence | Runner-up | Cost | Caste | Class | Men | Lookalikes |",
        "|---|---|---|---|---|---|---|---|---|---|---|",
    ]
    for row in review_rows:
        looks = ", ".join(f"{k} ({label})" for k, label in row["lookalikes"])
        # A `|` in a loc name would split the table cell.
        name = row["name"].replace("|", "\\|")
        lines.append(
            f"| {row['mod']} | {row['key']} | {name} | {row['pick']} | {row['confidence']:.2f} | {row['runner_up']} | {row['cost']} | {row['caste']} "
            f"| {row['class']} | {row['men']} | {looks} |"
        )
    lines += ["", "## Removed hand entries", ""]
    lines += [f"- {name}: `{line.strip()}`" for name, line in removed] or ["- (none)"]
    lines += ["", "## Ignored units (no card art in any pack)", ""]
    lines += [f"- {key}" for key in ignored] or ["- (none)"]
    lines += ["", "## Supported mods not installed", ""]
    lines += [f"- {name}" for name in missing_mods] or ["- (none)"]
    return "\n".join(lines) + "\n"


def name_hand_files(data: ttc_data.TtcData, file_mod: Dict[str, Optional[str]], owners: Dict[str, str]) -> None:
    """Put each hand file's mod display name in its first-line comment, instead of the pack name.

    A file maps to its mod by file name, or else by the mod that defines most of its units. The vanilla file gets `VANILLA_NAME`. A file that maps to
    no mod keeps its header.

    Args:
        data (ttc_data.TtcData): Loaded TTC data, for the hand entries and mod names.
        file_mod (Dict[str, Optional[str]]): Hand file path to the package its name matches.
        owners (Dict[str, str]): Unit key to the package that defines it.
    """
    vanilla_file = os.path.basename(ttc_compat_io.hand_file_path(ttc_data.VANILLA_PACKAGE))
    renamed = []
    for path, entries in sorted(data.hand_entries.items()):
        package = file_mod.get(path)
        if not package and os.path.basename(path) != vanilla_file:
            votes = collections.Counter(owners[entry.key] for entry in entries if entry.key in owners)
            package = votes.most_common(1)[0][0] if votes else None
        name = ttc_data.VANILLA_NAME if os.path.basename(path) == vanilla_file else data.mod_names.get(package or "")
        if name and ttc_compat_io.set_header(path, name):
            renamed.append(os.path.basename(path))
    if renamed:
        logging.info(f"TTC compat: named the mod in the header of {len(renamed)} hand files.")


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
    start = time.time()
    data = ttc_data.load_all()
    logging.info(f"TTC compat: loaded {len(data.stats)} units and {len(data.labels)} existing caps in {time.time() - start:.0f}s.")
    context = ttc_classifier.PeerContext(data.stats, data.labels)
    # `update.py --no-cache` retrains from scratch too.
    cache_path = MODEL_CACHE_PATH if cache_enabled() else None
    model, metrics = ttc_classifier.train(ttc_classifier.training_set(data), ttc_classifier.training_groups(data), context, cache_path)
    metrics_line = (
        f"held-out exact {metrics.exact:.1%}, category {metrics.category:.1%}, confident {metrics.confident:.1%} "
        f"on {metrics.confident_share:.1%} of entries (threshold {metrics.threshold:.3f}), unseen-mod exact {metrics.unseen_mod_exact:.1%}"
    )
    logging.info(f"TTC classifier: {metrics_line}")
    if metrics.confident < ttc_classifier.CONFIDENT_ACCURACY_BAR:
        logging.error("Confident picks are below the accuracy bar. No TTC files were written.")
        write_report(f"# TTC compat review\n\nFAILED: {metrics_line}. Confident picks must reach {ttc_classifier.CONFIDENT_ACCURACY_BAR:.0%}.\n")
        return 1

    step_start = time.time()
    # Units without card art in any pack are unfinished, so they get no cap.
    cardless = ttc_cards.cardless_units(data, ttc_cards.card_packs()) or set()
    targets = ttc_data.select_targets(data.mod_units, data.vanilla_keys, data.permissions, set(data.labels))
    targets.update(ttc_data.select_vanilla_targets(data.vanilla_units, data.permissions, set(data.labels)))
    targets = {key: package for key, package in targets.items() if key not in cardless}
    keys = sorted(targets)
    non_core = [ttc_data.is_regiment_of_renown(key, data.stats[key].main, targets[key]) for key in keys]
    predictions = model.predict([data.stats[key] for key in keys], non_core)
    logging.info(f"TTC compat: classified {len(keys)} units in {time.time() - step_start:.0f}s.")
    step_start = time.time()
    unsure_keys = [key for key, prediction in zip(keys, predictions) if not prediction.confident]
    lookalikes = dict(zip(unsure_keys, model.nearest_labeled_many([data.stats[key] for key in unsure_keys])))
    loc_names = ttc_data.load_loc_names()
    pick_names = ttc_data.unit_names(keys, data.stats, loc_names)
    assignments: Dict[str, Dict[str, List[Tuple[str, str, Optional[int]]]]] = {}
    auto_picks = []
    for key, prediction in zip(keys, predictions):
        package_name = targets[key]
        stats = data.stats[key]
        group = sorted(stats.groups)[0] if stats.groups else "unknown"
        category, weight = _split(prediction.label)
        assignments.setdefault(package_name, {}).setdefault(group, []).append((key, category, weight))
        auto_picks.append(
            {
                "mod": data.mod_names.get(package_name, package_name),
                "package": package_name,
                "key": key,
                "name": pick_names[key],
                "faction": ttc_data.package_unit_faction(key, package_name, stats.groups),
                "pick": prediction.label,
                "confident": prediction.confident,
                "confidence": round(prediction.confidence, 3),
                "runner_up": prediction.runner_up,
                "cost": stats.main.get("multiplayer_cost", ""),
                "caste": stats.main.get("caste", ""),
                "class": stats.land.get("class", ""),
                "men": stats.main.get("num_men", ""),
                "lookalikes": lookalikes.get(key, []),
            }
        )
    auto_picks.sort(key=lambda row: (row["mod"], row["key"]))
    review_rows = [row for row in auto_picks if not row["confident"]]
    write_auto_files(assignments, data.mod_names)
    logging.info(f"TTC compat: wrote auto files and found lookalikes for {len(review_rows)} review rows in {time.time() - step_start:.0f}s.")
    step_start = time.time()

    package_names = [name for name, _ in data.mod_units] + data.missing_mods
    file_mod = {path: ttc_data.hand_file_mod(path, package_names) for path in data.hand_entries}
    history = ttc_data.merge_owner_history(delta._read_json(OWNER_HISTORY_PATH) or {}, data.units_by_mod)
    stale = ttc_data.stale_hand_entries(data.hand_entries, file_mod, data.installed, data.units_by_mod, data.vanilla_keys, history)
    for path, entries in data.hand_entries.items():
        cardless_keys = {entry.key for entry in entries if entry.key in cardless}
        if cardless_keys:
            stale.setdefault(path, set()).update(cardless_keys)
    removed = []
    for path, keys_to_remove in sorted(stale.items()):
        removed += [(os.path.basename(path), line) for line in ttc_compat_io.remove_lines(path, keys_to_remove)]
    name_hand_files(data, file_mod, history)

    confident_count = sum(1 for p in predictions if p.confident)
    counts = {"labeled": metrics.n, "targets": len(keys), "confident": confident_count, "review": len(review_rows), "removed": len(removed)}
    skipped_mods = data.missing_mods + [f"{name} (main_units_tables unreadable, check the rpfm schema)" for name in data.unreadable_mods]
    ignored = sorted(key for key in cardless if data.permissions.get(key))
    write_report(render_report(metrics_line, counts, review_rows, removed, skipped_mods, ignored))
    os.makedirs(os.path.dirname(SUMMARY_PATH), exist_ok=True)
    with open(SUMMARY_PATH, "w", encoding="utf-8") as f:
        json.dump({"auto": len(keys), "review": len(review_rows), "removed": len(removed), "report": REPORT_PATH}, f)
    delta._write_json(AUTO_PICKS_PATH, auto_picks)
    delta._write_json(OWNER_HISTORY_PATH, history)

    file_mods = {os.path.basename(path): data.mod_names[package] for path, package in file_mod.items() if package in data.mod_names}
    file_mods.update({os.path.basename(ttc_compat_io.auto_file_path(package)): data.mod_names.get(package, package) for package in assignments})
    # The hand-written vanilla file is not tied to a mod pack, so map it by name.
    file_mods[os.path.basename(ttc_compat_io.hand_file_path(ttc_data.VANILLA_PACKAGE))] = ttc_data.VANILLA_NAME
    logging.info(f"TTC compat: wrote the review report and pruned stale hand entries in {time.time() - step_start:.0f}s.")
    step_start = time.time()
    entries = collect_entries(file_mods)
    names = ttc_data.unit_names(entries, data.stats, loc_names)
    records = {key: {"mod": mod, "name": names[key]} for key, mod in entries.items()}
    for key, record in records.items():
        if record["mod"] == ttc_data.VANILLA_NAME:
            record.update({"faction": ttc_data.faction_of(key), "vanilla": True})
        else:
            record["faction"] = ttc_data.unit_faction(key, data.permissions.get(key, set()))
    delta._write_json(delta.TTC_ENTRIES_PATH, records)
    logging.info(f"TTC compat: named {len(records)} entries from the loc files in {time.time() - step_start:.0f}s.")

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
