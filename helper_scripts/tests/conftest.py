"""Shared pytest setup. The helper scripts use paths relative to `helper_scripts/`, so tests run from there with it on `sys.path`."""

import os
import sys

import pytest

HELPER_SCRIPTS_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, HELPER_SCRIPTS_DIR)


@pytest.fixture(autouse=True)
def run_from_helper_scripts(monkeypatch):
    """Run every test with `helper_scripts/` as the working directory.

    Args:
        monkeypatch (pytest.MonkeyPatch): Pytest fixture used to change the working directory for the test only.
    """
    monkeypatch.chdir(HELPER_SCRIPTS_DIR)
