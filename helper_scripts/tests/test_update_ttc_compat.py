"""Tests for the TTC compat generator's file writing and report."""

import ttc_compat_io
import update_ttc_compat as gen


def test_obsolete_auto_files_are_deleted(tmp_path, monkeypatch):
    monkeypatch.setattr(ttc_compat_io, "HAND_DIR", str(tmp_path))
    (tmp_path / "!!!!!!!old_mod_auto.lua").write_text("old")
    (tmp_path / "!!!!!!!hand_mod.lua").write_text("hand")

    written = gen.write_auto_files({"new_mod.pack": {"grp": [("k", "rare", 1)]}}, {"new_mod.pack": "New Mod"})

    assert sorted(p.name for p in tmp_path.iterdir()) == ["!!!!!!!hand_mod.lua", "!!!!!!!new_mod_auto.lua"]
    assert len(written) == 1
    assert "-- New Mod (auto-generated" in (tmp_path / "!!!!!!!new_mod_auto.lua").read_text()


def test_report_lists_review_rows_and_removals():
    text = gen.render_report(
        metrics_line="held-out exact 90.0%",
        counts={"labeled": 10, "targets": 3, "confident": 2, "review": 1, "removed": 1},
        review_rows=[("New Mod", "k1", "rare,2", 0.41, "special,2", "900", "monster", "mon", "1", [("x", "rare,2"), ("y", "rare,3"), ("z", "special,2")])],
        removed=[("!!!!!!!hand_mod.lua", '    {"gone", "rare", 1},')],
        missing_mods=["missing.pack"],
    )
    assert "| New Mod | k1 | rare,2 | 0.41 | special,2 | 900 | monster | mon | 1 | x (rare,2), y (rare,3), z (special,2) |" in text
    assert '!!!!!!!hand_mod.lua: `{"gone", "rare", 1},`' in text
    assert "missing.pack" in text
