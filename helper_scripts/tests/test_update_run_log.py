"""Tests that `update.py` overwrites its run log each run and copies both its own and child script output into it."""

import logging
import os
import sys

import update


def test_run_log_is_overwritten_with_timestamp_then_logs(tmp_path, monkeypatch, caplog):
    caplog.set_level(logging.INFO)
    path = tmp_path / "run.log"
    path.write_text("old run\n", encoding="utf-8")
    monkeypatch.setattr(update, "RUN_LOG_PATH", str(path))
    monkeypatch.setattr(logging.getLogger(), "handlers", [])
    monkeypatch.setattr(sys, "excepthook", sys.excepthook)
    run_log = update.open_run_log()
    try:
        logging.info("parent line")
        update.run_script([sys.executable, "-c", "print('child line é')"], dict(os.environ), run_log)
    finally:
        run_log.close()

    lines = path.read_text(encoding="utf-8").splitlines()
    assert lines[0].startswith("Run started ")
    assert "old run" not in lines
    assert lines[2].endswith("INFO - parent line")
    assert lines[3] == "child line é"
