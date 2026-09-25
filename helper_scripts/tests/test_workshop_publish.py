"""Tests for Workshop publish state, change notes, staging and uploader output parsing."""

import json

import pytest

import delta
import workshop_publish
from extract_cache import normalize_path
from pipeline import workshop_pack_path
from supported_mods import SUPPORTED_MODS
from utilities import FILEPATH_TO_VANILLA_DATA_TABLES

GENERAL = workshop_publish.GENERAL_NOTE
MELEE, ARC, VELOCITY = delta.UNITS[3].outputs


@pytest.fixture
def state_dir(monkeypatch, tmp_path):
    """Point the published state at a temporary folder.

    Args:
        monkeypatch (pytest.MonkeyPatch): Pytest fixture used for patching.
        tmp_path (pathlib.Path): Temporary folder provided by pytest.

    Returns:
        The temporary published state folder.
    """
    published = tmp_path / "published"
    monkeypatch.setattr(workshop_publish, "PUBLISHED_STATE_DIR", str(published))
    return published


def _first_mod():
    """Return the first supported mod entry that has a pack path.

    Returns:
        The `SUPPORTED_MODS` entry.
    """
    return next(mod for mod in SUPPORTED_MODS if mod["path"])


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Display names


def test_display_name_for_supported_mod_uses_its_name():
    mod = _first_mod()
    assert workshop_publish.mod_display_name(normalize_path(mod["path"])) == mod["name"]


def test_display_name_for_vanilla_and_parent_pack():
    assert workshop_publish.mod_display_name(normalize_path(FILEPATH_TO_VANILLA_DATA_TABLES)) == "the base game"
    parent = normalize_path(workshop_pack_path("3278112051", "!!_nanu_dynamic_rors.pack"))
    assert workshop_publish.mod_display_name(parent) == "Nanu's Dynamic Regiments of Renown"


def test_display_name_for_unknown_pack_falls_back_to_filename():
    assert workshop_publish.mod_display_name("c:\\somewhere\\mystery_mod.pack") == "mystery_mod.pack"


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Change notes


def test_change_note_for_never_published_item_is_general():
    assert workshop_publish.build_change_note(None) == GENERAL


def test_change_note_lists_changed_mods():
    record = {"pack_sha": "a", "pending_mods": ["Mod A", "Mod B"], "pending_general": False}
    assert workshop_publish.build_change_note(record) == "Updated for changes in: Mod A, Mod B."


def test_change_note_combines_mods_and_general():
    record = {"pack_sha": "a", "pending_mods": ["Mod A"], "pending_general": True}
    assert workshop_publish.build_change_note(record) == f"Updated for changes in: Mod A. {GENERAL}"


def test_change_note_truncates_after_ten_mods():
    record = {"pack_sha": "a", "pending_mods": [f"Mod {i:02}" for i in range(13)], "pending_general": False}
    note = workshop_publish.build_change_note(record)
    assert note.startswith("Updated for changes in: Mod 00, Mod 01,")
    assert "Mod 09, and 3 more mods." in note
    assert "Mod 10" not in note


def test_change_note_without_recorded_reasons_is_general():
    assert workshop_publish.build_change_note({"pack_sha": "a", "pending_mods": [], "pending_general": False}) == GENERAL


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Recording rebuilds


def test_record_rebuild_only_touches_updated_outputs(state_dir):
    mod = _first_mod()
    check = delta.UnitCheck(delta.UNITS[3], stale=True, changed_packs=[normalize_path(mod["path"])])

    workshop_publish.record_rebuild(check, {VELOCITY.steam_id: "updated", MELEE.steam_id: "unchanged"})

    velocity = json.loads((state_dir / f"{VELOCITY.steam_id}.json").read_text(encoding="utf-8"))
    assert velocity["pending_mods"] == [mod["name"]]
    assert velocity["pending_general"] is False
    assert not (state_dir / f"{MELEE.steam_id}.json").exists()


def test_record_rebuild_merges_with_earlier_pending_reasons(state_dir):
    state_dir.mkdir()
    (state_dir / f"{VELOCITY.steam_id}.json").write_text(json.dumps({"pack_sha": "old", "pending_mods": ["Zeta Mod"], "pending_general": False}))
    check = delta.UnitCheck(delta.UNITS[3], stale=True, changed_packs=["c:\\x\\alpha.pack"], general=True)

    workshop_publish.record_rebuild(check, {VELOCITY.steam_id: "updated"})

    velocity = json.loads((state_dir / f"{VELOCITY.steam_id}.json").read_text(encoding="utf-8"))
    assert velocity["pending_mods"] == ["Zeta Mod", "alpha.pack"]
    assert velocity["pending_general"] is True
    assert velocity["pack_sha"] == "old"


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Pending items and publishing records


def _fake_pack_shas(monkeypatch, shas):
    """Fake the current Workshop pack hashes by pack path.

    Args:
        monkeypatch (pytest.MonkeyPatch): Pytest fixture used for patching.
        shas (dict): Pack path to fake SHA. Missing paths behave as missing packs.
    """
    monkeypatch.setattr(workshop_publish, "pack_sha256", lambda path: shas.get(path))


def test_item_without_record_is_pending(state_dir, monkeypatch):
    _fake_pack_shas(monkeypatch, {MELEE.pack_path: "current"})

    items = workshop_publish.pending_items([])

    assert [item.output.steam_id for item in items] == [MELEE.steam_id]
    assert items[0].change_note == GENERAL


def test_item_matching_last_publish_is_not_pending(state_dir, monkeypatch):
    state_dir.mkdir()
    (state_dir / f"{MELEE.steam_id}.json").write_text(json.dumps({"pack_sha": "current"}))
    _fake_pack_shas(monkeypatch, {MELEE.pack_path: "current", ARC.pack_path: "new"})

    items = workshop_publish.pending_items([])

    assert [item.output.steam_id for item in items] == [ARC.steam_id]


def test_outputs_of_failed_units_are_not_offered(state_dir, monkeypatch):
    _fake_pack_shas(monkeypatch, {MELEE.pack_path: "current", delta.UNITS[4].outputs[0].pack_path: "current"})

    items = workshop_publish.pending_items(["modified_attributes"])

    assert [item.output.steam_id for item in items] == [delta.UNITS[4].outputs[0].steam_id]


def test_mark_published_records_hash_and_clears_pending(state_dir, monkeypatch):
    state_dir.mkdir()
    (state_dir / f"{MELEE.steam_id}.json").write_text(json.dumps({"pending_mods": ["Mod A"], "pending_general": True}))
    _fake_pack_shas(monkeypatch, {MELEE.pack_path: "uploaded"})

    workshop_publish.mark_published(MELEE, "Updated for changes in: Mod A.")

    record = json.loads((state_dir / f"{MELEE.steam_id}.json").read_text(encoding="utf-8"))
    assert record["pack_sha"] == "uploaded"
    assert record["last_change_note"] == "Updated for changes in: Mod A."
    assert record["pending_mods"] == []
    assert record["pending_general"] is False
    assert MELEE.steam_id not in [item.output.steam_id for item in workshop_publish.pending_items([])]


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Staging and uploader output


def _fake_output(tmp_path, with_png):
    """Create a fake Workshop item folder with a pack and optionally a preview png.

    Args:
        tmp_path (pathlib.Path): Temporary folder provided by pytest.
        with_png (bool): Whether to create the `.png` next to the pack.

    Returns:
        A `delta.Output` whose `pack_path` points at the fake pack.
    """
    item_dir = tmp_path / "workshop" / "123"
    item_dir.mkdir(parents=True)
    (item_dir / "my_mod.pack").write_bytes(b"pack-bytes")
    if with_png:
        (item_dir / "my_mod.png").write_bytes(b"png-bytes")

    class FakeOutput(delta.Output):
        @property
        def pack_path(self):
            return str(item_dir / "my_mod.pack")

    return FakeOutput("123", "my_mod.pack")


def test_stage_content_copies_pack_and_png(tmp_path):
    output = _fake_output(tmp_path, with_png=True)

    content = workshop_publish.stage_content(output, str(tmp_path / "staging"))

    assert sorted(p.name for p in (tmp_path / "staging" / "123").iterdir()) == ["my_mod.pack", "my_mod.png"]
    assert content == str((tmp_path / "staging" / "123").resolve())


def test_stage_content_without_png_copies_only_pack(tmp_path):
    output = _fake_output(tmp_path, with_png=False)

    workshop_publish.stage_content(output, str(tmp_path / "staging"))

    assert [p.name for p in (tmp_path / "staging" / "123").iterdir()] == ["my_mod.pack"]


def test_parse_publisher_output_reads_results_and_ignores_noise():
    stdout = 'Setting breakpad minidump AppID = 1142710\n{"id": "1", "ok": true}\nnot json {\n{"id": "2", "ok": false, "error": "item not found"}\n'

    fatal, results = workshop_publish.parse_publisher_output(stdout)

    assert fatal is None
    assert results == {"1": {"id": "1", "ok": True}, "2": {"id": "2", "ok": False, "error": "item not found"}}


def test_parse_publisher_output_reports_fatal():
    fatal, results = workshop_publish.parse_publisher_output('{"fatal": "Steam is not running or not logged in"}\n')

    assert fatal == "Steam is not running or not logged in"
    assert results == {}
