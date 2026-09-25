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


def test_label_of_treats_a_missing_weight_as_one():
    # TTC uses `unit_weight or 1`, so `core` and `core,1` are the same cap in game.
    assert ttc_data.label_of("core", None) == "core,1"
    assert ttc_data.label_of("core", 1) == "core,1"
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


def test_mod_provided_ttc_entries_are_collected(tmp_path):
    ttc_dir = tmp_path / "script" / "ttc"
    ttc_dir.mkdir(parents=True)
    (ttc_dir / "mod_units.lua").write_text('local u = {\n    {"author_unit", "rare", 2},\n}\n', encoding="utf-8")
    campaign = tmp_path / "script" / "campaign" / "mod"
    campaign.mkdir(parents=True)
    (campaign / "mod_ttc_setup.lua").write_text('{"campaign_unit", "special", 1}', encoding="utf-8")
    (campaign / "unrelated.lua").write_text('{"not_ttc", "core", 1}', encoding="utf-8")
    assert ttc_data.mod_ttc_entries(str(tmp_path)) == {"author_unit": "rare,2", "campaign_unit": "special,1"}


def test_table_readable_rejects_binary_and_missing_extractions(tmp_path):
    good = tmp_path / "good" / "db" / "main_units_tables"
    good.mkdir(parents=True)
    (good / "mod.tsv").write_text("unit\n#v\nx\n")
    binary = tmp_path / "binary" / "db" / "main_units_tables"
    binary.mkdir(parents=True)
    (binary / "mod.tsv").write_text("unit\n#v\nx\n")
    (binary / "patched").write_bytes(bytes([0, 1]))
    assert ttc_data.table_readable(str(tmp_path / "good"))
    assert not ttc_data.table_readable(str(tmp_path / "binary"))
    assert not ttc_data.table_readable(str(tmp_path / "missing"))


def test_owner_history_keeps_old_owners_and_takes_first_current_owner():
    history = {"old_unit": "gone.pack", "moved_unit": "old_home.pack"}
    merged = ttc_data.merge_owner_history(history, {"a.pack": {"moved_unit", "shared"}, "b.pack": {"shared"}})
    assert merged == {"old_unit": "gone.pack", "moved_unit": "a.pack", "shared": "a.pack"}


def test_entry_owned_by_a_currently_uninstalled_mod_is_kept():
    entries = {"whc.lua": [TtcEntry("cth_samurai_shun", "special", 1, 1), TtcEntry("really_gone", "rare", 1, 2)]}
    history = {"cth_samurai_shun": "shun.pack", "really_gone": "whc.pack"}
    stale = ttc_data.stale_hand_entries(entries, {"whc.lua": "whc.pack"}, {"whc.pack"}, {"whc.pack": set()}, set(), history)
    assert stale == {"whc.lua": {"really_gone"}}



def test_units_the_author_left_out_are_still_covered_until_the_author_lists_them():
    mod_units = [("author.pack", [_row("author_listed"), _row("author_skipped")])]
    permissions = {"author_listed": {"grp"}, "author_skipped": {"grp"}}
    assert ttc_data.select_targets(mod_units, set(), permissions, {"author_listed"}) == {"author_skipped": "author.pack"}
    assert ttc_data.select_targets(mod_units, set(), permissions, {"author_listed", "author_skipped"}) == {}
