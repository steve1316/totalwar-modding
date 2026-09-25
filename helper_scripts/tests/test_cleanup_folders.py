"""Tests that `cleanup_folders` removes read-only and briefly locked files, and fails loudly when a file stays locked."""

import os
import stat
import threading

import pytest

import utilities


@pytest.fixture(autouse=True)
def fast_retries(monkeypatch):
    """Keep the retry wait short so the tests run fast."""
    monkeypatch.setattr(utilities, "RMTREE_RETRY_DELAY_SECONDS", 0.05)


def _make_tree(tmp_path):
    """Create a folder with one nested file.

    Args:
        tmp_path: Pytest temp directory.

    Returns:
        The folder path and the file path.
    """
    folder = tmp_path / "scratch"
    (folder / "nested").mkdir(parents=True)
    file_path = folder / "nested" / "model.rigid_model_v2"
    file_path.write_bytes(b"data")
    return folder, file_path


def test_removes_read_only_file(tmp_path):
    folder, file_path = _make_tree(tmp_path)
    os.chmod(file_path, stat.S_IREAD)
    utilities.cleanup_folders([str(folder)])
    assert not folder.exists()


@pytest.mark.skipif(os.name != "nt", reason="Open files only block deletes on Windows.")
def test_retries_until_lock_is_released(tmp_path):
    folder, file_path = _make_tree(tmp_path)
    handle = open(file_path, "rb")
    threading.Timer(0.1, handle.close).start()
    utilities.cleanup_folders([str(folder)])
    assert not folder.exists()


@pytest.mark.skipif(os.name != "nt", reason="Open files only block deletes on Windows.")
def test_raises_when_file_stays_locked(tmp_path):
    folder, file_path = _make_tree(tmp_path)
    with open(file_path, "rb"), pytest.raises(PermissionError):
        utilities.cleanup_folders([str(folder)])
