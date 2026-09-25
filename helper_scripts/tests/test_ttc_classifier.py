"""Tests for the TTC classifier."""

import random

import ttc_classifier as clf
from ttc_data import UnitStats


def _unit(i, cost, caste="melee_infantry", land=True):
    """Build a synthetic unit whose stats scale with its cost.

    Args:
        i (int): Index used for the unit key.
        cost (int): Multiplayer cost.
        caste (str): Unit caste.
        land (bool): Whether the unit has a `land_units_tables` row.

    Returns:
        The unit stats.
    """
    main = {"unit": f"u{i}", "caste": caste, "multiplayer_cost": str(cost), "upkeep_cost": str(cost // 4), "tier": "1", "num_men": "100", "is_monstrous": "false", "is_renown": "false"}
    land_row = {"class": "inf_mel", "category": "inf_melee", "melee_attack": "30", "melee_defence": "30", "bonus_hit_points": "10", "morale": "50", "charge_bonus": "10", "accuracy": "0", "primary_missile_weapon": ""} if land else {}
    return UnitStats(f"u{i}", main, land_row, {"grp_a"})


def _synthetic(n=400):
    """Build labeled synthetic units where cost cleanly decides the label.

    Args:
        n (int): Number of units.

    Returns:
        `(stats, label)` pairs.
    """
    rng = random.Random(0)
    data = []
    for i in range(n):
        cost = rng.randint(200, 2000)
        label = "core" if cost < 700 else ("special,2" if cost < 1300 else "rare,3")
        data.append((_unit(i, cost), label))
    return data


def test_features_without_land_row():
    features = clf.feature_dict(_unit(1, 500, land=False))
    assert features["has_land"] == 0
    assert features["melee_attack"] == 0


def test_features_include_combat_power_and_cost_per_model():
    stats = _unit(2, 1000)
    stats.main.update({"melee_cp": "250", "missile_cp": "0", "is_high_threat": "true", "ui_unit_group_land": "grp_elite"})
    features = clf.feature_dict(stats)
    assert features["melee_cp"] == 250
    assert features["cost_per_man"] == 10
    assert features["is_high_threat"] == 1
    assert features["ui_group=grp_elite"] == 1


def test_threshold_needs_the_lower_bound_to_clear_the_bar():
    import numpy as np

    small = clf._pick_threshold(np.full(20, 0.9), np.ones(20, dtype=bool))
    large = clf._pick_threshold(np.full(200, 0.9), np.ones(200, dtype=bool))
    assert small == float("inf")
    assert large == 0.9


def test_groups_add_an_unseen_mod_accuracy_without_changing_the_gate():
    data = _synthetic()
    plain_model, plain = clf.train(data)
    _, grouped = clf.train(data, groups=[f"g{i % 20}" for i in range(len(data))])
    assert plain.unseen_mod_exact is None
    assert 0.0 < grouped.unseen_mod_exact <= 1.0
    assert grouped.threshold == plain.threshold
    assert grouped.confident == plain.confident


def test_rare_labels_are_merged():
    labels = ["special,2"] * 6 + ["special,5"] * 2 + ["core"] * 6
    assert clf.merge_rare_labels(labels) == ["special,2"] * 8 + ["core"] * 6


def test_confident_picks_meet_the_bar_on_synthetic_data():
    _, metrics = clf.train(_synthetic())
    assert metrics.confident >= clf.CONFIDENT_ACCURACY_BAR
    assert metrics.confident_share > 0.5


def test_train_is_deterministic():
    data = _synthetic()
    probe = [_unit(9000 + i, 300 + i * 40) for i in range(40)]
    first = [(p.label, round(p.confidence, 9)) for p in clf.train(data)[0].predict(probe)]
    second = [(p.label, round(p.confidence, 9)) for p in clf.train(data)[0].predict(probe)]
    assert first == second


def test_nearest_labeled_returns_lookalikes():
    model, _ = clf.train(_synthetic())
    nearest = model.nearest_labeled(_unit(5000, 1800), k=3)
    assert len(nearest) == 3
    assert all(label == "rare,3" for _, label in nearest)
