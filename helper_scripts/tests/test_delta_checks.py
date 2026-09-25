"""Tests for `delta.check_unit` reporting which packs changed and whether a non-mod reason applied."""

import json

import pytest

import delta


def _write_state(tmp_path, unit, accesses):
    """Write a unit state and matching output records into a temporary state folder.

    Args:
        tmp_path (pathlib.Path): Temporary folder used as the state root.
        unit (delta.Unit): Unit whose state is written.
        accesses (list): Access records to store for the unit.
    """
    units_dir = tmp_path / "units"
    outputs_dir = tmp_path / "outputs"
    units_dir.mkdir()
    outputs_dir.mkdir()
    (units_dir / f"{unit.name}.json").write_text(json.dumps({"code_hash": delta.code_hash(unit), "accesses": accesses}))
    for output in unit.outputs:
        (outputs_dir / f"{output.steam_id}.json").write_text(json.dumps({"source_hash": "x", "pack_sha": f"sha-{output.steam_id}"}))


def _patch_state(monkeypatch, tmp_path, pack_shas, content_shas):
    """Point `delta` at a temporary state folder and fake pack and extraction hashes.

    Args:
        monkeypatch (pytest.MonkeyPatch): Pytest fixture used for patching.
        tmp_path (pathlib.Path): Temporary state root.
        pack_shas (dict): Pack path to fake SHA. Missing paths behave as uninstalled packs.
        content_shas (dict): `(pack, source)` to fake extraction content SHA.
    """
    monkeypatch.setattr(delta, "UNITS_STATE_DIR", str(tmp_path / "units"))
    monkeypatch.setattr(delta, "OUTPUTS_STATE_DIR", str(tmp_path / "outputs"))
    monkeypatch.setattr(delta, "pack_sha256", lambda path: pack_shas.get(path))
    monkeypatch.setattr(delta, "extraction_content_sha", lambda pack, source, kind, tsv: content_shas.get((pack, source)))


def _access(pack, source, pack_sha, content_sha):
    """Build one access record as `extract_cache` logs it.

    Args:
        pack (str): Pack path.
        source (str): Extracted source path.
        pack_sha (str): Recorded pack SHA.
        content_sha (str): Recorded content SHA.

    Returns:
        The access record dict.
    """
    return {"pack": pack, "source": source, "source_kind": "folder", "tables_as_tsv": True, "pack_sha": pack_sha, "content_sha": content_sha}


def test_changed_table_reports_its_pack_and_no_general_reason(monkeypatch, tmp_path):
    unit = delta.UNITS[4]
    _write_state(tmp_path, unit, [_access("mod_a.pack", "db/land_units_tables", "old", "c1"), _access("mod_b.pack", "db/land_units_tables", "same", "c2")])
    pack_shas = {"mod_a.pack": "new", "mod_b.pack": "same", **{o.pack_path: f"sha-{o.steam_id}" for o in unit.outputs}}
    _patch_state(monkeypatch, tmp_path, pack_shas, {("mod_a.pack", "db/land_units_tables"): "c1-changed"})

    check = delta.check_unit(unit)

    assert check.stale
    assert check.changed_packs == ["mod_a.pack"]
    assert check.general is False


def test_newly_installed_pack_is_reported_as_changed(monkeypatch, tmp_path):
    unit = delta.UNITS[4]
    _write_state(tmp_path, unit, [{"pack": "mod_c.pack", "source": "db/x", "source_kind": "folder", "tables_as_tsv": True, "missing": True}])
    pack_shas = {"mod_c.pack": "now-here", **{o.pack_path: f"sha-{o.steam_id}" for o in unit.outputs}}
    _patch_state(monkeypatch, tmp_path, pack_shas, {})

    check = delta.check_unit(unit)

    assert check.changed_packs == ["mod_c.pack"]
    assert check.general is False


def test_workshop_copy_mismatch_is_a_general_reason(monkeypatch, tmp_path):
    unit = delta.UNITS[4]
    _write_state(tmp_path, unit, [])
    _patch_state(monkeypatch, tmp_path, {o.pack_path: "resynced" for o in unit.outputs}, {})

    check = delta.check_unit(unit)

    assert check.stale
    assert check.changed_packs == []
    assert check.general is True


def test_missing_state_is_a_general_reason(monkeypatch, tmp_path):
    unit = delta.UNITS[4]
    (tmp_path / "units").mkdir()
    _patch_state(monkeypatch, tmp_path, {}, {})

    check = delta.check_unit(unit)

    assert check.general is True


def test_code_hash_changes_when_an_input_glob_file_changes(tmp_path):
    hand = tmp_path / "!!!!!!!mod.lua"
    hand.write_text("a")
    (tmp_path / "!!!!!!!mod_auto.lua").write_text("x")
    unit = delta.Unit("t", ["x.py"], [], [], [str(tmp_path / "!!!!!!!*.lua")])
    before = delta.code_hash(unit)
    (tmp_path / "!!!!!!!mod_auto.lua").write_text("changed auto files are outputs, not inputs")
    assert delta.code_hash(unit) == before
    hand.write_text("b")
    assert delta.code_hash(unit) != before


def test_ttc_compat_unit_is_registered():
    unit = next(u for u in delta.UNITS if u.name == "ttc_compat")
    assert [o.steam_id for o in unit.outputs] == ["3310629727"]
    assert unit.input_globs


def test_units_for_items_picks_the_units_that_build_them():
    ttc = next(unit for unit in delta.UNITS if unit.name == "ttc_compat")
    arc = delta.UNITS[3].outputs[1]
    assert delta.units_for_items({ttc.outputs[0].steam_id}) == [ttc]
    assert delta.units_for_items({arc.steam_id, ttc.outputs[0].steam_id}) == [delta.UNITS[3], ttc]


def test_units_for_items_rejects_unknown_ids():
    with pytest.raises(ValueError, match="123"):
        delta.units_for_items({"123"})
