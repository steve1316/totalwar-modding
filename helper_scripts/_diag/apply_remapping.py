"""One-off: rewrite old effect-bundle keys to new ones in helper_scripts using the bridge mod's mapping.

Safe version: matches only complete Python string literals ("<old_key>") so partial-substring
collisions (where an old key is a prefix of a new key) cannot cause double-substitution.

Run from helper_scripts/ as:
    python _diag/apply_remapping.py
"""
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
SCRIPTS_DIR = HERE.parent
MAPPING_PATH = HERE / "bridge_3561378697" / "old_to_new.json"
TARGET_FILES = ["dynamic_rors_effects.py", "update_dynamic_rors.py"]


def main():
    mapping = json.loads(MAPPING_PATH.read_text(encoding="utf-8"))
    grand_total = 0

    for fname in TARGET_FILES:
        path = SCRIPTS_DIR / fname
        original = path.read_text(encoding="utf-8")
        rewritten = original
        replacements = []

        for old, new in mapping.items():
            # Quote-bounded match: only replace when the old key appears as a complete
            # Python string literal. Prevents substring collisions when old is a prefix of new.
            pattern_dq = f'"{old}"'
            replacement_dq = f'"{new}"'
            count_dq = rewritten.count(pattern_dq)
            if count_dq:
                rewritten = rewritten.replace(pattern_dq, replacement_dq)
                replacements.append((old, new, count_dq))

            # Also handle single-quoted variants for completeness.
            pattern_sq = f"'{old}'"
            replacement_sq = f"'{new}'"
            count_sq = rewritten.count(pattern_sq)
            if count_sq:
                rewritten = rewritten.replace(pattern_sq, replacement_sq)
                # Track separately to keep counts honest.
                replacements.append((old, new, count_sq))

        if rewritten != original:
            path.write_text(rewritten, encoding="utf-8")

        total = sum(c for _, _, c in replacements)
        print(f"{fname}: {len(replacements)} mapping entries hit, {total} total replacements")
        grand_total += total

    print(f"\nGrand total replacements: {grand_total}")


if __name__ == "__main__":
    main()
