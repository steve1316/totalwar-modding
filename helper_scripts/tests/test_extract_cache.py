"""Tests for the extraction cache: cache hits, quiet rpfm failures, in-place reads and the shared-cache prune grace period."""

import os
import subprocess
import time
from pathlib import Path

import pytest

from core import extract_cache as ec


@pytest.fixture
def cache(tmp_path, monkeypatch):
    """Point the cache at a temp folder and replace rpfm with a fake that writes one db table.

    Args:
        tmp_path: Pytest temp folder.
        monkeypatch: Pytest monkeypatch fixture.

    Returns:
        A dict with the fake pack path and the list of rpfm sources that were extracted.
    """
    monkeypatch.setattr(ec, "OBJECTS_ROOT", str(tmp_path / "objects"))
    monkeypatch.setattr(ec, "STAGING_ROOT", str(tmp_path / "staging"))
    monkeypatch.setattr(ec, "MANIFEST_PATH", str(tmp_path / "pack_hashes.json"))
    monkeypatch.setattr(ec, "CACHE_ROOT", str(tmp_path))
    monkeypatch.setattr(ec, "_MANIFEST", None)
    monkeypatch.setattr(ec, "_RUN_MEMO", {})
    pack = tmp_path / "mod.pack"
    pack.write_bytes(b"pack")
    calls = []

    def fake_extract(pack_path, source_kind, source, tables_as_tsv, staging):
        calls.append(source)
        if source == "db/broken_tables":
            return subprocess.CompletedProcess([], 1, "", "Error: the table is broken")
        os.makedirs(f"{staging}/{source}", exist_ok=True)
        with open(f"{staging}/{source}/mod.tsv", "w", encoding="utf-8") as f:
            f.write(source)
        return subprocess.CompletedProcess([], 0, "", "")

    monkeypatch.setattr(ec, "_run_extract", fake_extract)
    return {"pack": str(pack), "calls": calls}


def test_a_second_extraction_of_the_same_table_is_a_cache_hit(cache, tmp_path):
    ec.cached_pack_extract(cache["pack"], "db/a_tables", str(tmp_path / "first"))
    ec.cached_pack_extract(cache["pack"], "db/a_tables", str(tmp_path / "second"))
    assert cache["calls"] == ["db/a_tables"]
    assert (tmp_path / "second/db/a_tables/mod.tsv").read_text(encoding="utf-8") == "db/a_tables"


def test_a_failed_extraction_logs_what_rpfm_said(cache, tmp_path, caplog):
    ec.cached_pack_extract(cache["pack"], "db/broken_tables", str(tmp_path / "out"))
    assert "the table is broken" in caplog.text


def test_prune_keeps_entries_another_worktree_used_recently(cache, tmp_path):
    objects = tmp_path / "objects"
    for group in ("old", "recent"):
        os.makedirs(objects / group / "entry")
        (objects / group / "entry/meta.json").write_text("{}", encoding="utf-8")
    long_ago = time.time() - ec.PRUNE_GRACE_SECONDS - 60
    for path in (objects / "old/entry/meta.json", objects / "old/entry"):
        os.utime(path, (long_ago, long_ago))
    assert ec.prune_cache([]) == 1
    assert not (objects / "old").exists()
    assert (objects / "recent").exists()


def test_extracted_tree_reads_the_cache_in_place(cache, tmp_path):
    with ec.extracted_tree(cache["pack"], "db/a_tables") as folder:
        assert tmp_path / "objects" in Path(folder).parents
        assert open(f"{folder}/db/a_tables/mod.tsv", encoding="utf-8").read() == "db/a_tables"
    with ec.extracted_tree(str(tmp_path / "no.pack"), "db/a_tables") as folder:
        assert folder is None
