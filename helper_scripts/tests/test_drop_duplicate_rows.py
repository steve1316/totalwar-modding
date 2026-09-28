"""Tests that `drop_duplicate_rows` removes exact repeats across a pack's table files and keeps anything that differs."""

import json

import pytest

from core import utilities

HEADER = "key\tskeleton"


@pytest.fixture
def schema(tmp_path):
    """Write a schema where the latest `battle_vortexs_tables` adds a float `radius` column that defaults to 0.

    Args:
        tmp_path (pathlib.Path): Pytest temp directory.

    Returns:
        The schema path.
    """
    path = tmp_path / "schema.json"
    fields = [{"name": "key", "ca_order": 0}, {"name": "damage", "ca_order": 1}, {"name": "radius", "ca_order": 2, "default_value": "0", "field_type": "F32"}]
    path.write_text(json.dumps({"definitions": {"battle_vortexs_tables": [{"version": 2, "fields": fields}]}}), encoding="utf-8")
    return str(path)


def _write(folder, name, rows, header=HEADER):
    """Write one table TSV.

    Args:
        folder (pathlib.Path): Table folder.
        name (str): File name without `.tsv`.
        rows (list): Data lines.
        header (str): Header line.

    Returns:
        The file path.
    """
    folder.mkdir(parents=True, exist_ok=True)
    path = folder / f"{name}.tsv"
    path.write_text("\n".join([header, f"#{folder.name};0;db/{folder.name}/{name}", *rows]) + "\n", encoding="utf-8")
    return path


def _rows(path):
    """Read the data lines of a TSV.

    Args:
        path (pathlib.Path): File to read.

    Returns:
        The data lines.
    """
    return path.read_text(encoding="utf-8").splitlines()[2:]


def test_keeps_first_copy_and_drops_exact_repeats(tmp_path, schema):
    table = tmp_path / "db" / "battle_animations_table_tables"
    first = _write(table, "compat_a", ["axe\thumanoid03", "bow\thumanoid01"])
    second = _write(table, "compat_b", ["axe\thumanoid03", "sword\thumanoid01"])

    assert utilities.drop_duplicate_rows(str(tmp_path / "db"), schema) == 1
    assert _rows(first) == ["axe\thumanoid03", "bow\thumanoid01"]
    assert _rows(second) == ["sword\thumanoid01"]


def test_rows_that_differ_at_all_are_kept(tmp_path, schema):
    table = tmp_path / "db" / "land_units_tables"
    _write(table, "compat_a", ["unit\tTrue"])
    second = _write(table, "compat_b", ["unit\ttrue", "unit\tFalse"])

    assert utilities.drop_duplicate_rows(str(tmp_path / "db"), schema) == 0
    assert _rows(second) == ["unit\ttrue", "unit\tFalse"]


def test_same_value_in_a_different_column_is_kept(tmp_path, schema):
    table = tmp_path / "db" / "melee_weapons_tables"
    _write(table, "compat_a", ["axe\t10"], header="key\tdamage")
    second = _write(table, "compat_b", ["axe\t10"], header="key\tap_damage")

    assert utilities.drop_duplicate_rows(str(tmp_path / "db"), schema) == 0
    assert _rows(second) == ["axe\t10"]


def test_older_version_row_matches_once_defaults_are_filled(tmp_path, schema):
    table = tmp_path / "db" / "battle_vortexs_tables"
    _write(table, "compat_a", ["vortex\t10"], header="key\tdamage")
    second = _write(table, "compat_b", ["vortex\t10\t0.0000", "other\t10\t5.0000"], header="key\tdamage\tradius")

    assert utilities.drop_duplicate_rows(str(tmp_path / "db"), schema) == 1
    assert _rows(second) == ["other\t10\t5.0000"]


def test_other_tables_are_not_compared(tmp_path, schema):
    _write(tmp_path / "db" / "a_tables", "compat_a", ["axe\thumanoid03"])
    other = _write(tmp_path / "db" / "b_tables", "compat_a", ["axe\thumanoid03"])

    assert utilities.drop_duplicate_rows(str(tmp_path / "db"), schema) == 0
    assert _rows(other) == ["axe\thumanoid03"]


def test_file_left_empty_is_deleted(tmp_path, schema):
    table = tmp_path / "db" / "battle_animations_table_tables"
    _write(table, "compat_a", ["axe\thumanoid03"])
    second = _write(table, "compat_b", ["axe\thumanoid03"])

    assert utilities.drop_duplicate_rows(str(tmp_path / "db"), schema) == 1
    assert not second.exists()
