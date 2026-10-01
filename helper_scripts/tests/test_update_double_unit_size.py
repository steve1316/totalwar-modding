"""Tests that `handle_main_units_tables` doubles each land unit once and leaves single vehicles alone."""

import pandas as pd

from generators.update_double_unit_size import handle_main_units_tables

LAND_COLUMNS = ["key", "engine", "bonus_hit_points", "num_mounts", "num_engines", "rank_depth"]
ENGINE_TYPES = {"cannon": "Generic_3_Crew", "luminark": "Generic_No_Crew_Fixed", "tank": "Generic_No_Crew_Rotate", "hellcannon": "Generic_3_Crew"}


def _frames(main_rows, land_rows):
    """Build the main_units and land_units frames the handler expects.

    Args:
        main_rows (list): `(unit, land_unit, caste, num_men)` tuples.
        land_rows (list): Rows in `LAND_COLUMNS` order.

    Returns:
        Tuple of the main_units and land_units dataframes.
    """
    main = pd.DataFrame(main_rows, columns=["unit", "land_unit", "caste", "num_men"]).astype(str)
    land = pd.DataFrame(land_rows, columns=LAND_COLUMNS).astype(str)
    return main, land


def _land(land, key, column):
    """Read one land_units value as an int."""
    return int(land.loc[land["key"] == key, column].iloc[0])


def test_shared_land_unit_is_doubled_once():
    """Two main units on one land unit (e.g. an Imperial Supply copy) must not double it twice."""
    main, land = _frames(
        [("knights", "knights_lu", "cavalry", "60"), ("knights_supply", "knights_lu", "cavalry", "60")],
        [("knights_lu", "", "0", "60", "0", "4")],
    )
    main, land = handle_main_units_tables(main, ENGINE_TYPES, land, land.copy())
    assert _land(land, "knights_lu", "num_mounts") == 120
    assert _land(land, "knights_lu", "rank_depth") == 8
    assert list(main["num_men"]) == ["120", "120"]


def test_shared_artillery_engines_doubled_once():
    """A shared artillery land unit gets 4 -> 8 engines, not 4 -> 16."""
    main, land = _frames(
        [("cannon", "cannon_lu", "warmachine", "44"), ("cannon_supply", "cannon_lu", "warmachine", "44")],
        [("cannon_lu", "cannon", "0", "0", "4", "5")],
    )
    _, land = handle_main_units_tables(main, ENGINE_TYPES, land, land.copy())
    assert _land(land, "cannon_lu", "num_engines") == 8


def test_single_vehicle_keeps_crew_and_draughts():
    """A unit built on one crewless vehicle (Steam Tank, Luminark, Land Ship) keeps its crew, mounts and rank depth."""
    main, land = _frames(
        [("luminark", "luminark_lu", "chariot", "2"), ("tank", "tank_lu", "chariot", "3"), ("chariot_lord", "chariot_lord_lu", "lord", "2")],
        [("luminark_lu", "luminark", "0", "2", "1", "1"), ("tank_lu", "tank", "0", "1", "1", "1"), ("chariot_lord_lu", "luminark", "1000", "2", "1", "1")],
    )
    main, land = handle_main_units_tables(main, ENGINE_TYPES, land, land.copy())
    assert list(main["num_men"]) == ["2", "3", "2"]
    assert _land(land, "luminark_lu", "num_mounts") == 2
    assert _land(land, "chariot_lord_lu", "num_mounts") == 2
    assert _land(land, "chariot_lord_lu", "rank_depth") == 1
    # Lords still get their bonus hit points doubled.
    assert _land(land, "chariot_lord_lu", "bonus_hit_points") == 2000


def test_single_crewed_gun_doubles_crew_only():
    """A single gun with crew on foot (Hellcannon, Queen Bess) doubles its crew but stays one gun."""
    main, land = _frames([("hellcannon", "hellcannon_lu", "warmachine", "12")], [("hellcannon_lu", "hellcannon", "0", "0", "1", "4")])
    main, land = handle_main_units_tables(main, ENGINE_TYPES, land, land.copy())
    assert list(main["num_men"]) == ["24"]
    assert _land(land, "hellcannon_lu", "num_engines") == 1
