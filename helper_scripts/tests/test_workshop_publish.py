"""Tests for Workshop publish state, change notes, staging and uploader output parsing."""

import hashlib
import json
import os

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
    assert items[0].pack_sha == "current"


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


def test_mark_published_records_uploaded_hash_not_the_live_pack(state_dir, monkeypatch):
    state_dir.mkdir()
    (state_dir / f"{MELEE.steam_id}.json").write_text(json.dumps({"pending_mods": ["Mod A"], "pending_general": True}))
    _fake_pack_shas(monkeypatch, {MELEE.pack_path: "live-pack-changed-meanwhile"})

    workshop_publish.mark_published(MELEE, "Updated for changes in: Mod A.", "uploaded")

    record = json.loads((state_dir / f"{MELEE.steam_id}.json").read_text(encoding="utf-8"))
    assert record["pack_sha"] == "uploaded"
    assert record["last_change_note"] == "Updated for changes in: Mod A."
    assert record["pending_mods"] == []
    assert record["pending_general"] is False


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


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Publish flow


class FakePublisher:
    """Stand-in for `run_publisher` that records calls and streams canned results."""

    def __init__(self, check_results=None, upload_results=None, fatal=None, interrupt_after=None):
        """Set up the canned responses.

        Args:
            check_results (dict): Workshop ID to preflight result.
            upload_results (dict): Workshop ID to upload result.
            fatal (str): Fatal message returned by every call, if set.
            interrupt_after (int): Raise `KeyboardInterrupt` after streaming this many upload results, if set.
        """
        self.check_results = check_results or {}
        self.upload_results = upload_results or {}
        self.fatal = fatal
        self.interrupt_after = interrupt_after
        self.calls = []

    def __call__(self, jobs, check_only, on_result=None):
        """Record the call, stream each result to `on_result` like the real uploader, and return the canned response.

        Args:
            jobs (list): Jobs passed by `publish_pending`.
            check_only (bool): Whether this is the preflight call.
            on_result (callable): Called with each result as it arrives.

        Returns:
            A `(fatal, results)` tuple like `run_publisher`.
        """
        self.calls.append((check_only, [job["id"] for job in jobs]))
        canned = self.check_results if check_only else self.upload_results
        streamed = {}
        for job in jobs:
            if job["id"] not in canned:
                continue
            if not check_only and self.interrupt_after is not None and len(streamed) == self.interrupt_after:
                raise KeyboardInterrupt
            streamed[job["id"]] = {"id": job["id"], **canned[job["id"]]}
            if on_result:
                on_result(streamed[job["id"]])
        return self.fatal, streamed


@pytest.fixture
def flow(monkeypatch, state_dir):
    """Isolate `publish_pending` from Node, Steam and the real Workshop folder.

    Args:
        monkeypatch (pytest.MonkeyPatch): Pytest fixture used for patching.
        state_dir (pathlib.Path): Temporary published state folder.

    Returns:
        A dict collecting the outputs passed to `mark_published`.
    """
    marked = {}
    monkeypatch.setattr(workshop_publish, "PUBLISH_TEMP_DIR", str(state_dir.parent / "publish"))
    monkeypatch.setattr(workshop_publish, "publisher_problem", lambda: None)
    monkeypatch.setattr(workshop_publish, "stage_content", _fake_stage)
    monkeypatch.setattr(workshop_publish, "mark_published", lambda output, note, pack_sha: marked.__setitem__(output.steam_id, (note, pack_sha)))
    return marked


def _staged_bytes(output):
    """Return the fake pack bytes that `_fake_stage` writes for an output.

    Args:
        output (delta.Output): The staged item.

    Returns:
        The fake pack bytes.
    """
    return f"pack-{output.steam_id}".encode()


def _fake_stage(output, root):
    """Stage a fake pack file instead of copying the real Workshop pack.

    Args:
        output (delta.Output): The item to stage.
        root (str): Staging root folder.

    Returns:
        The staged content folder.
    """
    content = os.path.join(root, output.steam_id)
    os.makedirs(content, exist_ok=True)
    with open(os.path.join(content, output.pack_name), "wb") as f:
        f.write(_staged_bytes(output))
    return content


def _item(output, note):
    """Build a pending item whose listed hash matches what `_fake_stage` writes.

    Args:
        output (delta.Output): The item.
        note (str): Its change note.

    Returns:
        The pending item.
    """
    return workshop_publish.PendingItem(output, note, hashlib.sha256(_staged_bytes(output)).hexdigest())


ITEMS = [_item(MELEE, "note melee"), _item(VELOCITY, "note velocity")]


def test_dry_run_lists_pending_without_contacting_steam(flow, monkeypatch, caplog):
    monkeypatch.setattr(workshop_publish, "run_publisher", FakePublisher(fatal="must not be called"))
    publisher = workshop_publish.run_publisher

    with caplog.at_level("INFO"):
        workshop_publish.publish_pending(ITEMS, dry_run=True, no_publish=False, confirm=lambda prompt: "y", is_interactive=lambda: True)

    assert publisher.calls == []
    assert "note melee" in caplog.text
    assert flow == {}


def test_non_interactive_terminal_never_publishes(flow, monkeypatch, caplog):
    monkeypatch.setattr(workshop_publish, "run_publisher", FakePublisher())
    publisher = workshop_publish.run_publisher

    with caplog.at_level("INFO"):
        workshop_publish.publish_pending(ITEMS, dry_run=False, no_publish=False, confirm=lambda prompt: "y", is_interactive=lambda: False)

    assert publisher.calls == []
    assert "Not an interactive terminal" in caplog.text
    assert flow == {}


def test_declining_the_prompt_uploads_nothing(flow, monkeypatch, caplog):
    ok = {MELEE.steam_id: {"ok": True}, VELOCITY.steam_id: {"ok": True}}
    monkeypatch.setattr(workshop_publish, "run_publisher", FakePublisher(check_results=ok))
    publisher = workshop_publish.run_publisher

    with caplog.at_level("INFO"):
        workshop_publish.publish_pending(ITEMS, dry_run=False, no_publish=False, confirm=lambda prompt: "n", is_interactive=lambda: True)

    assert publisher.calls == [(True, [MELEE.steam_id, VELOCITY.steam_id])]
    assert flow == {}
    assert f"{workshop_publish.WORKSHOP_URL}{MELEE.steam_id}" in caplog.text


def test_confirmed_publish_records_successes_and_lists_every_url(flow, monkeypatch, caplog):
    checks = {MELEE.steam_id: {"ok": True}, VELOCITY.steam_id: {"ok": True}}
    uploads = {MELEE.steam_id: {"ok": True, "needsToAcceptAgreement": False}, VELOCITY.steam_id: {"ok": False, "error": "k_EResultTimeout"}}
    monkeypatch.setattr(workshop_publish, "run_publisher", FakePublisher(check_results=checks, upload_results=uploads))

    with caplog.at_level("INFO"):
        workshop_publish.publish_pending(ITEMS, dry_run=False, no_publish=False, confirm=lambda prompt: "y", is_interactive=lambda: True)

    assert flow == {MELEE.steam_id: ("note melee", ITEMS[0].pack_sha)}
    assert f"{workshop_publish.WORKSHOP_URL}{MELEE.steam_id}  published" in caplog.text
    assert f"{workshop_publish.WORKSHOP_URL}{VELOCITY.steam_id}  FAILED: k_EResultTimeout" in caplog.text


def test_preflight_failure_skips_only_that_item(flow, monkeypatch, caplog):
    checks = {MELEE.steam_id: {"ok": True}, VELOCITY.steam_id: {"ok": False, "error": "not owned by the logged-in account"}}
    uploads = {MELEE.steam_id: {"ok": True}}
    monkeypatch.setattr(workshop_publish, "run_publisher", FakePublisher(check_results=checks, upload_results=uploads))
    publisher = workshop_publish.run_publisher

    with caplog.at_level("INFO"):
        workshop_publish.publish_pending(ITEMS, dry_run=False, no_publish=False, confirm=lambda prompt: "y", is_interactive=lambda: True)

    assert publisher.calls[1] == (False, [MELEE.steam_id])
    assert flow == {MELEE.steam_id: ("note melee", ITEMS[0].pack_sha)}
    assert "not owned by the logged-in account" in caplog.text


def test_steam_unreachable_publishes_nothing(flow, monkeypatch, caplog):
    monkeypatch.setattr(workshop_publish, "run_publisher", FakePublisher(fatal="Steam is not running or not logged in"))

    with caplog.at_level("INFO"):
        workshop_publish.publish_pending(ITEMS, dry_run=False, no_publish=False, confirm=lambda prompt: "y", is_interactive=lambda: True)

    assert flow == {}
    assert "Steam is not running or not logged in" in caplog.text


def test_nothing_pending_says_so(flow, caplog):
    with caplog.at_level("INFO"):
        workshop_publish.publish_pending([], dry_run=False, no_publish=False, confirm=lambda prompt: "y", is_interactive=lambda: True)

    assert "Nothing to publish." in caplog.text


def test_pack_changed_since_listing_is_not_uploaded(flow, monkeypatch, caplog):
    checks = {MELEE.steam_id: {"ok": True}, VELOCITY.steam_id: {"ok": True}}
    monkeypatch.setattr(workshop_publish, "run_publisher", FakePublisher(check_results=checks, upload_results={VELOCITY.steam_id: {"ok": True}}))
    publisher = workshop_publish.run_publisher
    items = [workshop_publish.PendingItem(MELEE, "note melee", "hash-when-listed"), ITEMS[1]]

    with caplog.at_level("INFO"):
        workshop_publish.publish_pending(items, dry_run=False, no_publish=False, confirm=lambda prompt: "y", is_interactive=lambda: True)

    assert publisher.calls[1] == (False, [VELOCITY.steam_id])
    assert MELEE.steam_id not in flow
    assert f"{workshop_publish.WORKSHOP_URL}{MELEE.steam_id}  FAILED: the pack changed since it was listed" in caplog.text


def test_interrupted_upload_keeps_completed_results(flow, monkeypatch, caplog):
    checks = {MELEE.steam_id: {"ok": True}, VELOCITY.steam_id: {"ok": True}}
    uploads = {MELEE.steam_id: {"ok": True}, VELOCITY.steam_id: {"ok": True}}
    monkeypatch.setattr(workshop_publish, "run_publisher", FakePublisher(check_results=checks, upload_results=uploads, interrupt_after=1))

    with caplog.at_level("INFO"):
        workshop_publish.publish_pending(ITEMS, dry_run=False, no_publish=False, confirm=lambda prompt: "y", is_interactive=lambda: True)

    assert flow == {MELEE.steam_id: ("note melee", ITEMS[0].pack_sha)}
    assert f"{workshop_publish.WORKSHOP_URL}{MELEE.steam_id}  published" in caplog.text
    assert f"{workshop_publish.WORKSHOP_URL}{VELOCITY.steam_id}  not published (interrupted)" in caplog.text


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Uploader process


def _fake_publisher_dir(tmp_path, monkeypatch, script):
    """Point `run_publisher` at a fake `publish.js` that prints canned output.

    Args:
        tmp_path (pathlib.Path): Temporary folder provided by pytest.
        monkeypatch (pytest.MonkeyPatch): Pytest fixture used for patching.
        script (str): JavaScript source for the fake uploader.
    """
    publisher_dir = tmp_path / "publisher"
    publisher_dir.mkdir()
    (publisher_dir / "publish.js").write_text(script, encoding="utf-8")
    monkeypatch.setattr(workshop_publish, "PUBLISHER_DIR", str(publisher_dir))
    monkeypatch.setattr(workshop_publish, "PUBLISH_TEMP_DIR", str(tmp_path / "publish"))


def test_run_publisher_streams_results_before_a_failed_exit(tmp_path, monkeypatch):
    lines = ["Setting breakpad minidump AppID = 1142710", json.dumps({"id": "1", "ok": True})]
    _fake_publisher_dir(tmp_path, monkeypatch, "".join(f"console.log({json.dumps(line)});\n" for line in lines) + "process.exit(1);\n")
    streamed = []

    fatal, results = workshop_publish.run_publisher([{"id": "1", "contentPath": "", "changeNote": ""}], check_only=False, on_result=streamed.append)

    assert fatal is None
    assert streamed == [{"id": "1", "ok": True}]
    assert results == {"1": {"id": "1", "ok": True}}


def test_run_publisher_without_results_reports_the_exit_code(tmp_path, monkeypatch):
    _fake_publisher_dir(tmp_path, monkeypatch, "process.exit(3);\n")

    fatal, results = workshop_publish.run_publisher([{"id": "1", "contentPath": "", "changeNote": ""}], check_only=True)

    assert "exited with code 3" in fatal
    assert results == {}


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# TTC change notes

TTC = next(output for unit in delta.UNITS for output in unit.outputs if output.steam_id == workshop_publish.TTC_STEAM_ID)


def _entry(mod, name, faction="Empire"):
    """Build one TTC entries record for a modded unit.

    Args:
        mod (str): Mod display name.
        name (str): In-game unit name.
        faction (str): Faction display name.

    Returns:
        The record.
    """
    return {"mod": mod, "name": name, "faction": faction}


def test_ttc_note_lists_added_units_per_mod_by_faction_and_removed_keys_at_the_bottom():
    published = {"kept": _entry("Mod A", "Kept"), "gone_unit": _entry("Mod B", "Gone")}
    current = {
        "kept": _entry("Mod A", "Kept"),
        "a_new": _entry("Mod A", "Swordsmen"),
        "a_new_summoned": _entry("Mod A", "Swordsmen"),
        "b_new": _entry("mod b", "Archers", "Skaven"),
    }
    note = workshop_publish.build_ttc_change_note(published, current)
    assert note == (
        "[u]Tabletop caps added for 3 units across 2 mods, removed for 1 unit[/u]\n"
        "\n"
        "[b]Mod A[/b] (+2): [i]Empire[/i]: Swordsmen (x2)\n"
        "[b]mod b[/b] (+1): [i]Skaven[/i]: Archers\n"
        "\n"
        "[b]Removed (no longer in their mods)[/b]\n"
        "[b]Mod B[/b] (-1): gone_unit"
    )


def test_ttc_note_drops_unit_names_for_faction_counts_when_too_long_but_keeps_removed_keys():
    current = {f"k{i}": _entry("Big Mod", f"Unit Name {i}", "Skaven" if i < 20 else "Empire") for i in range(50)}
    note = workshop_publish.build_ttc_change_note({"old": _entry("Old Mod", "Old")}, current, limit=300)
    assert "[b]Big Mod[/b] (+50): Empire +30, Skaven +20\n" in note
    assert "Unit Name" not in note
    assert note.endswith("[b]Old Mod[/b] (-1): old")
    assert len(note) <= 300


def test_ttc_note_drops_to_mod_totals_when_faction_counts_are_still_too_long():
    current = {f"k{i}": _entry("Big Mod", "Unit", f"A Rather Long Faction Name {i}") for i in range(20)}
    note = workshop_publish.build_ttc_change_note({}, current, limit=150)
    assert note == "[u]Tabletop caps added for 20 units across 1 mod[/u]\n\n[b]Big Mod[/b] (+20)"


def test_ttc_note_is_cut_to_the_limit_as_a_last_resort():
    published = {f"gone_{i}": _entry("Mod", "x") for i in range(100)}
    note = workshop_publish.build_ttc_change_note(published, {}, limit=200)
    assert len(note) <= 200
    assert note.endswith("...")


def test_ttc_note_is_none_when_no_unit_was_added_or_removed():
    entries = {"k": _entry("Mod", "Unit")}
    assert workshop_publish.build_ttc_change_note(entries, dict(entries)) is None


def test_pending_ttc_item_uses_the_unit_note_and_publishing_snapshots_the_entries(state_dir, monkeypatch, tmp_path):
    current_path = tmp_path / "ttc_entries.json"
    current_path.write_text(json.dumps({"k1": _entry("Mod", "Unit One"), "k2": _entry("Mod", "Unit Two")}))
    monkeypatch.setattr(delta, "TTC_ENTRIES_PATH", str(current_path))
    state_dir.mkdir()
    (state_dir / f"{TTC.steam_id}.json").write_text(json.dumps({"pack_sha": "old", "pending_mods": ["Mod"]}))
    (state_dir / f"{TTC.steam_id}_entries.json").write_text(json.dumps({"k1": _entry("Mod", "Unit One")}))
    _fake_pack_shas(monkeypatch, {TTC.pack_path: "new"})

    [item] = workshop_publish.pending_items([])
    assert item.change_note == "[u]Tabletop caps added for 1 unit across 1 mod[/u]\n\n[b]Mod[/b] (+1): [i]Empire[/i]: Unit Two"

    workshop_publish.mark_published(TTC, item.change_note, "new")
    assert json.loads((state_dir / f"{TTC.steam_id}_entries.json").read_text()) == json.loads(current_path.read_text())


def test_ttc_item_without_a_published_snapshot_keeps_the_general_note(state_dir, monkeypatch, tmp_path):
    current_path = tmp_path / "ttc_entries.json"
    current_path.write_text(json.dumps({"k1": _entry("Mod", "Unit One")}))
    monkeypatch.setattr(delta, "TTC_ENTRIES_PATH", str(current_path))
    _fake_pack_shas(monkeypatch, {TTC.pack_path: "new"})

    [item] = workshop_publish.pending_items([])
    assert item.change_note == GENERAL


def test_closed_input_at_the_prompt_uploads_nothing(flow, monkeypatch, caplog):
    ok = {MELEE.steam_id: {"ok": True}, VELOCITY.steam_id: {"ok": True}}
    monkeypatch.setattr(workshop_publish, "run_publisher", FakePublisher(check_results=ok))
    publisher = workshop_publish.run_publisher

    def closed(prompt):
        raise EOFError

    with caplog.at_level("INFO"):
        workshop_publish.publish_pending(ITEMS, dry_run=False, no_publish=False, confirm=closed, is_interactive=lambda: True)

    assert publisher.calls == [(True, [MELEE.steam_id, VELOCITY.steam_id])]
    assert flow == {}
    assert "Publishing cancelled" in caplog.text


def test_pending_items_can_be_limited_to_some_workshop_ids(state_dir, monkeypatch):
    _fake_pack_shas(monkeypatch, {MELEE.pack_path: "a", ARC.pack_path: "b", VELOCITY.pack_path: "c"})

    items = workshop_publish.pending_items([], steam_ids={ARC.steam_id})

    assert [item.output.steam_id for item in items] == [ARC.steam_id]


def _vanilla(faction, name):
    """Build one TTC entries record for a vanilla or DLC unit.

    Args:
        faction (str): Faction display name.
        name (str): In-game unit name.

    Returns:
        The record.
    """
    return {"mod": "Vanilla + DLC", "name": name, "faction": faction, "vanilla": True}


def test_ttc_note_lists_vanilla_units_by_faction_instead_of_as_a_mod():
    current = {"emp_a": _vanilla("Empire", "Teutogen Guard"), "skv_a": _vanilla("Skaven", "Pusbags"), "emp_b": _vanilla("Empire", "Wolf-kin")}
    assert workshop_publish.build_ttc_change_note({}, current) == (
        "[u]Tabletop caps added for 3 vanilla and DLC units[/u]\n"
        "\n"
        "[b]Empire[/b] (+2): Teutogen Guard, Wolf-kin\n"
        "[b]Skaven[/b] (+1): Pusbags"
    )


def test_ttc_note_with_vanilla_and_mod_units_gives_each_its_own_section():
    current = {"emp_a": _vanilla("Empire", "Teutogen Guard"), "m1": _entry("Mod A", "Swordsmen")}
    published = {"gone_vanilla": _vanilla("Skaven", "Old Rat"), "gone_mod": _entry("Mod A", "Old")}
    assert workshop_publish.build_ttc_change_note(published, current) == (
        "[u]Tabletop caps added for 1 vanilla and DLC unit and 1 unit across 1 mod, removed for 2 units[/u]\n"
        "\n"
        "[b]Vanilla and DLC[/b]\n"
        "[b]Empire[/b] (+1): Teutogen Guard\n"
        "\n"
        "[b]Mods[/b]\n"
        "[b]Mod A[/b] (+1): [i]Empire[/i]: Swordsmen\n"
        "\n"
        "[b]Removed (no longer in their mods)[/b]\n"
        "[b]Mod A[/b] (-1): gone_mod\n"
        "[b]Skaven (vanilla)[/b] (-1): gone_vanilla"
    )


def test_ttc_note_names_each_faction_once_within_a_mod():
    current = {"a1": _entry("Mod A", "Rat Ogres", "Skaven"), "a2": _entry("Mod A", "Swordsmen", "Empire"), "a3": _entry("Mod A", "Clanrats", "Skaven")}
    assert workshop_publish.build_ttc_change_note({}, current).endswith("[b]Mod A[/b] (+3): [i]Empire[/i]: Swordsmen; [i]Skaven[/i]: Clanrats, Rat Ogres")
