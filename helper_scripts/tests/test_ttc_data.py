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


def test_regiment_of_renown_detection():
    assert ttc_data.is_regiment_of_renown("any_unit", {"is_renown": "true"}, "plain.pack")
    assert ttc_data.is_regiment_of_renown("wh_dlc_emp_inf_greatswords_ror_0", {}, "plain.pack")
    assert ttc_data.is_regiment_of_renown("ror_beast_shadowg", {}, "plain.pack")
    assert ttc_data.is_regiment_of_renown("grn_brutes1", {}, "ror_all.pack")
    assert not ttc_data.is_regiment_of_renown("chs_horror_knights", {}, "horror_pack.pack")


def test_unit_names_use_the_land_unit_loc_then_the_unit_loc_then_the_key():
    stats = {"u1": ttc_data.UnitStats("u1", {"land_unit": "lu1"}, {}, set()), "u2": ttc_data.UnitStats("u2", {"land_unit": "lu2"}, {}, set())}
    loc = {"land_units_onscreen_name_lu1": "Spearmen", "land_units_onscreen_name_u2": "Own Key Name"}
    assert ttc_data.unit_names(["u1", "u2", "u3"], stats, loc) == {"u1": "Spearmen", "u2": "Own Key Name", "u3": "u3"}


def test_read_loc_names_keeps_only_onscreen_names_and_earlier_sources_win(tmp_path):
    (tmp_path / "text").mkdir()
    (tmp_path / "text" / "units.loc.tsv").write_text(
        "key\ttext\ttooltip\n#Loc;1;text/units.loc\t\t\nland_units_onscreen_name_a\tNew A\tfalse\nland_units_onscreen_name_b\t  Spaced   B \tfalse\n"
        "land_units_onscreen_name_c\t\tfalse\nsomething_else\tIgnored\tfalse\n",
        encoding="utf-8",
    )
    names = {"land_units_onscreen_name_a": "Translated A"}
    ttc_data.read_loc_names(str(tmp_path), names)
    assert names == {"land_units_onscreen_name_a": "Translated A", "land_units_onscreen_name_b": "Spaced B"}


def test_vanilla_targets_cover_what_the_base_list_misses_and_skip_prologue_units():
    rows = [
        _row("wh3_dlc29_new_unit"),
        _row("base_listed"),
        _row("wh3_dlc29_lord", "lord"),
        _row("no_permission"),
        _row("wh3_main_pro_ksl_inf_kossars_0"),
        _row("wh3_main_pro_kho_hounds_simaergul_0"),
        _row("wh3_main_ksl_inf_kossars_tutorial_1"),
    ]
    permissions = {
        "wh3_dlc29_new_unit": {"wh_main_group_empire"},
        "base_listed": {"wh_main_group_empire"},
        "wh3_dlc29_lord": {"wh_main_group_empire"},
        "wh3_main_pro_ksl_inf_kossars_0": {"wh3_main_pro_ksl"},
        "wh3_main_pro_kho_hounds_simaergul_0": {"wh3_main_pro_kho", "wh3_dlc20_group_chs_valkia"},
        "wh3_main_ksl_inf_kossars_tutorial_1": {"wh3_main_ksl", "wh3_main_pro_ksl"},
    }
    targets = ttc_data.select_vanilla_targets(rows, permissions, {"base_listed"})
    assert targets == {"wh3_dlc29_new_unit": ttc_data.VANILLA_PACKAGE, "wh3_main_pro_kho_hounds_simaergul_0": ttc_data.VANILLA_PACKAGE}


def test_faction_of_reads_the_race_code_from_the_unit_key():
    assert ttc_data.faction_of("wh3_dlc29_emp_inf_teutogen_guard") == "Empire"
    assert ttc_data.faction_of("wh3_main_pro_kho_inf_flesh_hounds_of_khorne_simaergul_0") == "Khorne"
    assert ttc_data.faction_of("wh2_dlc11_cst_cav_knights_errant_2") == "Vampire Coast"
    assert ttc_data.faction_of("mystery_unit") == "Other"


def test_unit_faction_falls_back_to_a_vote_across_recruit_groups():
    assert ttc_data.unit_faction("glf_skv_rat_ogre", {"wh_main_group_empire"}) == "Skaven"
    assert ttc_data.unit_faction("rory_welf_bear", set()) == "Wood Elves"
    assert ttc_data.unit_faction("motm_bear", {"wh3_dlc23_group_chaos_dwarfs"}) == "Chaos Dwarfs"
    assert ttc_data.unit_faction("jhared_wolf", {"wh_main_group_empire", "wh_main_group_empire_gold", "wh2_main_skv"}) == "Empire"
    assert ttc_data.unit_faction("jhared_tie", {"wh2_main_skv", "wh_main_group_empire"}) == "Empire"
    assert ttc_data.unit_faction("custom_unit", {"my_custom_group"}) == "Other"


def test_unit_names_resolve_loc_references_to_other_names():
    stats = {"v": ttc_data.UnitStats("v", {"land_unit": "v"}, {}, set()), "w": ttc_data.UnitStats("w", {"land_unit": "w"}, {}, set())}
    loc = {
        "land_units_onscreen_name_v": "{{tr:land_units_onscreen_name_clanrats}}",
        "land_units_onscreen_name_clanrats": "Clanrats",
        "land_units_onscreen_name_w": "{{tr:land_units_onscreen_name_missing}}",
    }
    assert ttc_data.unit_names(["v", "w"], stats, loc) == {"v": "Clanrats", "w": "w"}
