"""Tests for the change note CLI the translator app runs to preview and record Workshop uploads."""

import json

import pytest

from core import delta
from publish import change_notes, workshop_publish

GENERAL = f"[u]Compatibility update[/u]\n\n{workshop_publish.GENERAL_NOTE}"
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


def _fake_pack_shas(monkeypatch, shas):
    """Fake the current Workshop pack hashes by pack path.

    Args:
        monkeypatch (pytest.MonkeyPatch): Pytest fixture used for patching.
        shas (dict): Pack path to fake SHA. Missing paths behave as missing packs.
    """
    monkeypatch.setattr(workshop_publish, "pack_sha256", lambda path: shas.get(path))


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Preview


def test_preview_reports_unrecorded_item_as_pending(state_dir, monkeypatch):
    _fake_pack_shas(monkeypatch, {MELEE.pack_path: "current"})

    assert change_notes.preview([MELEE.steam_id]) == {MELEE.steam_id: {"note": GENERAL, "pack_sha": "current", "pending": True}}


def test_preview_reports_item_matching_last_upload_as_not_pending(state_dir, monkeypatch):
    state_dir.mkdir()
    (state_dir / f"{MELEE.steam_id}.json").write_text(json.dumps({"pack_sha": "current", "pending_mods": ["Mod A"]}))
    _fake_pack_shas(monkeypatch, {MELEE.pack_path: "current"})

    result = change_notes.preview([MELEE.steam_id])[MELEE.steam_id]

    assert result["pending"] is False
    assert result["note"] == "[u]Compatibility update for 1 updated mod[/u]\n\n- Mod A"


def test_preview_maps_unknown_ids_and_missing_packs_to_none(state_dir, monkeypatch):
    _fake_pack_shas(monkeypatch, {})

    assert change_notes.preview(["1", ARC.steam_id]) == {"1": None, ARC.steam_id: None}


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Record


def test_record_marks_the_item_published(state_dir):
    state_dir.mkdir()
    (state_dir / f"{MELEE.steam_id}.json").write_text(json.dumps({"pending_mods": ["Mod A"], "pending_general": True}))

    change_notes.record(MELEE.steam_id, "uploaded", "note text")

    record = json.loads((state_dir / f"{MELEE.steam_id}.json").read_text(encoding="utf-8"))
    assert record["pack_sha"] == "uploaded"
    assert record["last_change_note"] == "note text"
    assert record["pending_mods"] == []
    assert record["pending_general"] is False


def test_record_rejects_unknown_ids(state_dir):
    with pytest.raises(ValueError, match="not a generated Workshop item"):
        change_notes.record("1", "sha", "note")


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Command line


def test_main_preview_prints_one_ascii_json_line(state_dir, monkeypatch, capsys):
    state_dir.mkdir()
    (state_dir / f"{MELEE.steam_id}.json").write_text(json.dumps({"pack_sha": "old", "pending_mods": ["Mod A"]}))
    _fake_pack_shas(monkeypatch, {MELEE.pack_path: "current"})

    assert change_notes.main(["preview", MELEE.steam_id]) == 0

    out = capsys.readouterr().out.strip()
    assert out.isascii()
    assert "\n" not in out
    assert json.loads(out)[MELEE.steam_id]["note"].endswith("- Mod A")


def test_main_record_reads_a_utf8_note_file(state_dir, tmp_path):
    note_file = tmp_path / "note.txt"
    note_file.write_text('[u]Update[/u]\n\n• "Mod" A 苗英', encoding="utf-8")

    assert change_notes.main(["record", MELEE.steam_id, "--pack-sha", "uploaded", "--note-file", str(note_file)]) == 0

    record = json.loads((state_dir / f"{MELEE.steam_id}.json").read_text(encoding="utf-8"))
    assert record["last_change_note"] == '[u]Update[/u]\n\n• "Mod" A 苗英'


def test_main_record_unknown_id_exits_1(state_dir, tmp_path, capsys):
    note_file = tmp_path / "note.txt"
    note_file.write_text("x", encoding="utf-8")

    assert change_notes.main(["record", "1", "--pack-sha", "sha", "--note-file", str(note_file)]) == 1
    assert "not a generated Workshop item" in capsys.readouterr().err
