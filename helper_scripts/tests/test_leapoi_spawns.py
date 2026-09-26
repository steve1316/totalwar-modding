"""Fill every LEAPOI zone through the mod's real spot code and check the MCT spawn percentage slider caps active encounters."""

import math

import pytest

from tools import simulate_leapoi_armies as sim

pytestmark = pytest.mark.skipif(sim.find_lua() is None, reason="Lua is not installed, so the spawn simulator cannot run.")

PERCENTAGES = [0.1, 0.5, 0.75, 1.0]


@pytest.mark.parametrize("campaign", sim.CAMPAIGNS)
def test_each_zone_activates_the_slider_share_of_its_spots(campaign):
    wrong = [
        f"{zone['zone']} at {zone['percentage']:.0%}: {zone['active']} of {zone['spots']} active"
        for zone in sim.run_spawn_simulation(campaign, PERCENTAGES)
        if zone["active"] != math.ceil(zone["percentage"] * zone["spots"])
    ]
    assert wrong == []
