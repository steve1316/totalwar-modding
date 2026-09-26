"""Roll LEAPOI armies through the mod's real Lua generator and check them against each faction's unit pool and difficulty limits."""

import pytest

from tools import simulate_leapoi_armies as sim

pytestmark = pytest.mark.skipif(sim.find_lua() is None, reason="Lua is not installed, so the army simulator cannot run.")

CONFIG = {"hard": {"tiers": [1, 5], "min_units": 3, "max_units": 4}, "easy": {"tiers": [1, 2], "min_units": 3, "max_units": 4}}


def _army(units, difficulty="hard", lord="lord_a", heroes=()):
    """Build one simulated Wood Elf army.

    Args:
        units (list): Land unit keys.
        difficulty (str): Difficulty key.
        lord (str): Lord subtype, or False for none.
        heroes (tuple): Hero subtypes.

    Returns:
        The army record.
    """
    return {"faction": "wef", "difficulty": difficulty, "lord": lord, "heroes": list(heroes), "units": [{"category": "x", "land_unit": u} for u in units]}


def _result(armies, mods="none"):
    """Wrap armies in a result with a small Wood Elf pool.

    Args:
        armies (list): Army records.
        mods (str): `none` or `all`.

    Returns:
        The simulation result.
    """
    pool = {
        "eternal_guard": [{"tier": 1, "category": "x", "origin": "vanilla"}],
        "dragon": [{"tier": 5, "category": "x", "origin": "vanilla"}],
        "mod_unit": [{"tier": 1, "category": "x", "origin": "some_mod"}],
        "wh_dlc08_wef_forest_dragon_boss": [{"tier": 5, "category": "x", "origin": "vanilla"}],
    }
    return sim.SimResult(CONFIG, {"wef": pool}, armies, mods)


def test_checks_pass_a_valid_army():
    assert sim.find_problems(_result([_army(["eternal_guard", "dragon"])])) == {}


def test_checks_catch_each_kind_of_problem():
    problems = sim.find_problems(
        _result([_army(["harpies", "mod_unit", "wh_dlc08_wef_forest_dragon_boss", "eternal_guard"], lord=False), _army(["dragon", "eternal_guard"], difficulty="easy")])
    )
    assert set(problems) == {"no_lord", "not_in_pool", "mod_unit_with_mods_off", "forbidden_unit", "outside_tier_range", "over_max_size"}


def test_mod_units_are_fine_when_mods_are_on():
    assert sim.find_problems(_result([_army(["mod_unit", "eternal_guard"])], mods="all")) == {}


@pytest.mark.parametrize("mods", ["none", "all"])
def test_generated_armies_pass_every_check(mods):
    assert sim.find_problems(sim.run_simulation(count=60, seed=7, mods=mods)) == {}
