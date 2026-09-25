"""Tests for TTC target selection and the stale hand-entry guard."""

import ttc_data
from ttc_compat_io import TtcEntry


def _row(key, caste="melee_infantry"):
    """Build a minimal `main_units_tables` row.

    Args:
        key (str): Unit key.
        caste (str): Unit caste.

    Returns:
        The row dict.
    """
    return {"unit": key, "caste": caste}


def test_label_of_formats_weightless_core():
    assert ttc_data.label_of("core", None) == "core"
    assert ttc_data.label_of("special", 2) == "special,2"


def test_select_targets_excludes_lords_heroes_labeled_vanilla_and_unrecruitable():
    mod_units = [("a.pack", [_row("new_unit"), _row("lord_unit", "lord"), _row("hero_unit", "hero"), _row("labeled_unit"), _row("vanilla_unit"), _row("no_perm")])]
    permissions = {k: {"grp"} for k in ["new_unit", "lord_unit", "hero_unit", "labeled_unit", "vanilla_unit"]}
    targets = ttc_data.select_targets(mod_units, {"vanilla_unit"}, permissions, {"labeled_unit"})
    assert targets == {"new_unit": "a.pack"}


def test_select_targets_first_mod_wins_for_duplicate_keys():
    mod_units = [("first.pack", [_row("dup")]), ("second.pack", [_row("dup")])]
    assert ttc_data.select_targets(mod_units, set(), {"dup": {"grp"}}, set()) == {"dup": "first.pack"}


def test_hand_file_mod_matches_case_insensitively():
    names = ["!!AM_HelfuryMachinegunsFIXED.pack", "other.pack"]
    assert ttc_data.hand_file_mod("x/!!!!!!!AM_HelfuryMachineGunsFIXED.lua", names) == "!!AM_HelfuryMachinegunsFIXED.pack"
    assert ttc_data.hand_file_mod("x/!!!!!!!nothing_like_it.lua", names) is None


def test_stale_entries_only_for_installed_mapped_mods():
    entries = {"f1": [TtcEntry("gone", "rare", 1, 1), TtcEntry("still_here", "rare", 1, 2), TtcEntry("vanilla_now", "core", None, 3)]}
    stale = ttc_data.stale_hand_entries(entries, {"f1": "m.pack"}, {"m.pack"}, {"m.pack": {"still_here"}}, {"vanilla_now"})
    assert stale == {"f1": {"gone"}}


def test_unmapped_hand_file_is_never_edited():
    entries = {"f1": [TtcEntry("gone", "rare", 1, 1)]}
    assert ttc_data.stale_hand_entries(entries, {"f1": None}, {"m.pack"}, {"m.pack": set()}, set()) == {}


def test_uninstalled_mod_entries_are_kept():
    entries = {"f1": [TtcEntry("gone", "rare", 1, 1)]}
    assert ttc_data.stale_hand_entries(entries, {"f1": "m.pack"}, set(), {}, set()) == {}


def test_entry_for_a_unit_defined_by_another_installed_mod_is_kept():
    entries = {"f1": [TtcEntry("cross_mod_unit", "rare", 1, 1), TtcEntry("truly_gone", "rare", 1, 2)]}
    units_by_mod = {"m.pack": set(), "other.pack": {"cross_mod_unit"}}
    stale = ttc_data.stale_hand_entries(entries, {"f1": "m.pack"}, {"m.pack", "other.pack"}, units_by_mod, set())
    assert stale == {"f1": {"truly_gone"}}
