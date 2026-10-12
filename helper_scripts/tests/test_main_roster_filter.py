"""Tests that a culture's random army pool only keeps vanilla units its base recruitment group can field, plus Regiments of Renown."""

import pandas as pd

from generators import process_main_units_tables as pmu

GROUPS = {
    "wh_dlc05_wef_inf_eternal_guard_0": {"wh_dlc05_group_wood_elves", "wh2_dlc16_group_drycha"},
    "wh2_dlc16_wef_mon_harpies_0": {"wh2_dlc16_group_drycha"},
    "wh_dlc05_bst_mon_harpies_0": {"wh_dlc03_group_beastmen"},
}


def test_base_group_unit_is_kept():
    assert pmu.is_in_main_roster("wh_dlc05_wef_inf_eternal_guard_0", "wef", False, GROUPS)


def test_unit_only_another_lord_can_recruit_is_dropped():
    assert not pmu.is_in_main_roster("wh2_dlc16_wef_mon_harpies_0", "wef", False, GROUPS)


def test_unit_nobody_can_recruit_is_dropped():
    assert not pmu.is_in_main_roster("wh2_dlc17_bst_mon_ghorgon_boss_0", "bst", False, GROUPS)


def test_regiment_of_renown_is_kept_without_a_group():
    assert pmu.is_in_main_roster("wh2_dlc16_wef_inf_dryads_ror_0", "wef", True, GROUPS)


def test_boss_unit_flagged_as_renown_is_dropped():
    assert not pmu.is_in_main_roster("wh_dlc08_wef_forest_dragon_boss", "wef", True, GROUPS)


def test_culture_without_a_base_group_keeps_everything():
    assert pmu.is_in_main_roster("mod_unit", "mod_added_culture", False, GROUPS)


def test_renown_flag_reads_strings_bools_and_missing_values():
    assert pmu.is_renown({"is_renown": "true"})
    assert pmu.is_renown({"is_renown": True})
    assert not pmu.is_renown({"is_renown": "false"})
    assert not pmu.is_renown({})


def test_recruit_groups_collect_every_group_per_unit():
    table = pd.DataFrame({"unit": ["a", "b", "a"], "military_group": ["g1", "g2", "g3"]})
    assert pmu.build_recruit_groups(table) == {"a": {"g1", "g3"}, "b": {"g2"}}


def _pool_units(package_name):
    """Run `tsv_to_faction_data` on one Drycha-only Wood Elf unit.

    Args:
        package_name (str): The source mod, `vanilla` or a mod pack name.

    Returns:
        The land units that ended up in the Wood Elf pool, and the units the roster filter left out by culture.
    """
    units = pd.DataFrame(
        [{"unit": "wh2_dlc16_wef_mon_harpies_0", "land_unit": "wh2_dlc16_wef_mon_harpies_0", "tier": "1", "caste": "monstrous_infantry",
          "recruitment_cost": "600", "multiplayer_cost": "500", "is_renown": "false"}]
    )
    empty = pd.DataFrame()
    dropped = {}
    data = pmu.tsv_to_faction_data({"package_name": package_name}, {}, [{"wef": "wef"}], units, empty, empty, empty, empty, recruit_groups=GROUPS, dropped_units=dropped)
    return [u["land_unit"] for tier in data["wef"]["units"].values() for units in tier.values() for u in units], dropped


def test_vanilla_units_outside_the_main_roster_are_dropped():
    assert _pool_units("vanilla") == ([], {"wef": ["wh2_dlc16_wef_mon_harpies_0"]})


def test_mod_units_follow_supported_mods_placement_unfiltered():
    assert _pool_units("some_mod.pack") == (["wh2_dlc16_wef_mon_harpies_0"], {})


def test_faction_key_matches_at_the_start_and_end_of_a_unit_key():
    keys = [{"hef": "hef"}, {"tze": "tze"}]
    assert pmu.match_faction("wh2_main_hef_inf_spearmen_0", keys, False) == "hef"
    assert pmu.match_faction("hef_cha_prince_caledor", keys, False) == "hef"
    assert pmu.match_faction("marauder_hunters_tze", keys, False) == "tze"


def test_faction_key_must_be_a_whole_token_unless_substring_matching():
    keys = [{"def": "def"}]
    assert pmu.match_faction("wh_main_emp_inf_defenders", keys, False) is None
    assert pmu.match_faction("wh_main_emp_inf_defenders", keys, True) == "def"


def test_unmatched_units_are_collected_instead_of_warned():
    units = pd.DataFrame([{"unit": "teb_captain", "land_unit": "wh_main_teb_cha_captain_0", "tier": 1, "caste": "lord"}])
    empty = pd.DataFrame()
    unmatched = []
    data = pmu.tsv_to_faction_data({"package_name": "vanilla"}, {}, [{"emp": "emp"}], units, empty, empty, empty, empty, unmatched_units=unmatched)
    assert data == {}
    assert unmatched == ["wh_main_teb_cha_captain_0"]


def test_out_of_range_tier_is_clamped():
    assert pmu.unit_tier({"land_unit": "ok", "tier": "3"}) == "tier_3"
    assert pmu.unit_tier({"land_unit": "ete_ror", "tier": "1600"}) == "tier_5"
    assert pmu.unit_tier({"land_unit": "neg", "tier": "-2"}) == "tier_0"
