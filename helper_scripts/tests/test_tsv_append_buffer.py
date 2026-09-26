"""Tests that `TsvAppendBuffer` writes the same bytes as calling `write_updated_tsv_file` once per batch."""

from core import utilities

EFFECT_HEADERS = ["unit", "purchasable_effect", "is_exclusive"]
LAND_HEADERS = ["key", "category", "num_men"]


def _effects(unit, effects):
    """Build effect-set rows for one unit.

    Args:
        unit (str): Unit key.
        effects (list): Effect keys.

    Returns:
        The rows.
    """
    return [{"unit": unit, "purchasable_effect": effect, "is_exclusive": "False"} for effect in effects]


# Each call is `(data, headers, version_info, table folder, file name, allow_duplicates)`.
CALLS = [
    (_effects("u1", ["e1", "e2"]), EFFECT_HEADERS, "#effects;1;db/effects/f", "effects", "f", False),
    ([{"key": "u1", "category": "inf", "num_men": "100"}], LAND_HEADERS, "#land;7;db/land/f", "land", "f", False),
    (_effects("u2", ["e1", "e2", "e2"]), EFFECT_HEADERS, "#effects;1;db/effects/f", "effects", "f", False),
    (_effects("u1", ["e2", "e3"]), EFFECT_HEADERS, "#effects;1;db/effects/f", "effects", "f", False),
    ([{"key": "u1", "category": "cav", "num_men": ""}, {"key": "u2", "num_men": "5"}], LAND_HEADERS, "#land;7;db/land/f", "land", "f", False),
    ([{"key": "u2", "category": "dup", "num_men": "1"}], LAND_HEADERS, "#land;7;db/land/f", "land", "f", True),
    ([{"key": "u2", "category": "again", "num_men": "1"}], LAND_HEADERS, "#land;7;db/land/f", "land", "f", False),
    (_effects("u3", ["e1"]), EFFECT_HEADERS, "#effects;1;db/effects/g", "effects", "g", False),
]


def _read_tree(root):
    """Read every file under a folder.

    Args:
        root (pathlib.Path): Folder to read.

    Returns:
        Relative path to file bytes.
    """
    return {str(p.relative_to(root)): p.read_bytes() for p in sorted(root.rglob("*")) if p.is_file()}


def _run_direct(root, calls):
    """Apply the calls with `write_updated_tsv_file`.

    Args:
        root (pathlib.Path): Output root.
        calls (list): Calls to apply.
    """
    for data, headers, version, table, name, allow in calls:
        utilities.write_updated_tsv_file(data, headers, version, str(root / table), name, allow_duplicates=allow)


def _run_buffered(root, calls):
    """Apply the calls through a `TsvAppendBuffer` and flush once.

    Args:
        root (pathlib.Path): Output root.
        calls (list): Calls to apply.
    """
    buffer = utilities.TsvAppendBuffer()
    for data, headers, version, table, name, allow in calls:
        buffer.add(data, headers, version, str(root / table), name, allow_duplicates=allow)
    buffer.flush()


def test_buffered_writes_match_direct_writes(tmp_path):
    _run_direct(tmp_path / "direct", CALLS)
    _run_buffered(tmp_path / "buffered", CALLS)
    assert _read_tree(tmp_path / "buffered") == _read_tree(tmp_path / "direct")


def test_buffered_writes_respect_rows_already_in_the_file(tmp_path):
    for label in ("direct", "buffered"):
        _run_direct(tmp_path / label, CALLS[:2])
    _run_direct(tmp_path / "direct", CALLS[2:])
    _run_buffered(tmp_path / "buffered", CALLS[2:])
    assert _read_tree(tmp_path / "buffered") == _read_tree(tmp_path / "direct")


def test_nothing_is_written_before_flush(tmp_path):
    data, headers, version, table, name, _ = CALLS[0]
    buffer = utilities.TsvAppendBuffer()
    buffer.add(data, headers, version, str(tmp_path / table), name)
    assert not (tmp_path / table).exists()
    buffer.flush()
    assert (tmp_path / table / f"{name}.tsv").exists()
