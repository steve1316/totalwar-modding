"""Tests for `tools.sync_kadon_units`, which copies current vanilla values onto the Kadon scroll units."""

import os

from data.kadon_sources import KADON_KEEP_COLUMNS, KADON_SOURCES
from tools import sync_kadon_units as sync

MOD_DB = "../warhammer3_mods/jvj_kadon_6_0/db"


def test_land_unit_row_takes_vanilla_values_except_key_and_kept_columns():
    mod_row = {"key": "kadon_bind_x", "armour": "wh2_main_body_100", "morale": "60", "mount": ""}
    vanilla_row = {"key": "wh2_x_0", "armour": "wh2_main_body_120", "morale": "65", "mount": "wh2_crew"}
    row, changes = sync.sync_land_unit_row(mod_row, vanilla_row, keep={"mount"})
    assert row == {"key": "kadon_bind_x", "armour": "wh2_main_body_120", "morale": "65", "mount": ""}
    assert changes == {"armour": ("wh2_main_body_100", "wh2_main_body_120"), "morale": ("60", "65")}


def test_main_unit_row_only_touches_synced_columns():
    mod_row = {"unit": "kadon_bind_x", "land_unit": "kadon_bind_x", "tier": "5", "melee_cp": "1600.0000", "recruitment_cost": "0", "num_men": "1"}
    vanilla_row = {"unit": "wh2_x_0", "land_unit": "wh2_x_0", "tier": "4", "melee_cp": "1500.0000", "recruitment_cost": "1800", "num_men": "5"}
    row, changes = sync.sync_main_unit_row(mod_row, vanilla_row, keep={"num_men"})
    assert row == {"unit": "kadon_bind_x", "land_unit": "kadon_bind_x", "tier": "4", "melee_cp": "1500.0000", "recruitment_cost": "0", "num_men": "1"}
    assert changes == {"tier": ("5", "4"), "melee_cp": ("1600.0000", "1500.0000")}


def test_pick_main_unit_prefers_exact_key_then_single_clean_candidate():
    main_rows = [
        {"unit": "wh3_dlc25_nur_chieftain_mon_fimir_0", "land_unit": "wh_dlc08_nor_mon_fimir_0"},
        {"unit": "wh_dlc08_nor_mon_fimir_0", "land_unit": "wh_dlc08_nor_mon_fimir_0"},
        {"unit": "wh2_main_def_mon_war_hydra", "land_unit": "wh2_main_def_mon_war_hydra_0"},
        {"unit": "a_one", "land_unit": "shared"},
        {"unit": "a_two", "land_unit": "shared"},
    ]
    assert sync.pick_main_unit("wh_dlc08_nor_mon_fimir_0", main_rows)["unit"] == "wh_dlc08_nor_mon_fimir_0"
    assert sync.pick_main_unit("wh2_main_def_mon_war_hydra_0", main_rows)["unit"] == "wh2_main_def_mon_war_hydra"
    assert sync.pick_main_unit("shared", main_rows) is None
    assert sync.pick_main_unit("missing", main_rows) is None


def test_ability_rows_follow_vanilla_and_keep_kadon_rows():
    mod_rows = [
        {"ability": "old_passive", "land_unit": "kadon_bind_a", "culture": "*"},
        {"ability": "kadon_bind_unbinding", "land_unit": "kadon_bind_a", "culture": "*"},
        {"ability": "custom_passive", "land_unit": "kadon_bind_original", "culture": "*"},
        {"ability": "stale_passive", "land_unit": "kadon_bind_a", "culture": "*"},
    ]
    vanilla_by_land_unit = {
        "wh_a": [{"ability": "new_passive", "land_unit": "wh_a", "culture": "wh2_main_lzd_lizardmen"}],
        "wh_b": [{"ability": "b_passive", "land_unit": "wh_b", "culture": "*"}],
    }
    sources = {"kadon_bind_a": "wh_a", "kadon_bind_b": "wh_b"}
    rows = sync.sync_ability_rows(mod_rows, vanilla_by_land_unit, sources)
    assert rows == [
        {"ability": "kadon_bind_unbinding", "land_unit": "kadon_bind_a", "culture": "*"},
        {"ability": "new_passive", "land_unit": "kadon_bind_a", "culture": "wh2_main_lzd_lizardmen"},
        {"ability": "custom_passive", "land_unit": "kadon_bind_original", "culture": "*"},
        {"ability": "b_passive", "land_unit": "kadon_bind_b", "culture": "*"},
    ]


def test_tsv_round_trip_keeps_header_metadata_and_line_endings(tmp_path):
    path = tmp_path / "table.tsv"
    original = "key\tvalue\n#table;1;db/table\t\nrow_a\t1\nrow_b\t2\n"
    path.write_bytes(original.encode())
    header, meta, rows = sync.read_tsv(str(path))
    assert header == ["key", "value"]
    assert rows == [{"key": "row_a", "value": "1"}, {"key": "row_b", "value": "2"}]
    sync.write_tsv(str(path), header, meta, rows)
    assert path.read_bytes().decode() == original


def test_sources_cover_every_vanilla_scroll_unit_and_no_originals():
    scroll_units = set()
    for kind in ("binding", "kinship"):
        _, _, rows = sync.read_tsv(os.path.join(MOD_DB, "land_units_tables", f"jvj_kadon_{kind}.tsv"))
        scroll_units.update(row["key"] for row in rows if not row["historical_description_text"].startswith("jvj_kadon_"))
    assert set(KADON_SOURCES) == scroll_units
    assert set(KADON_KEEP_COLUMNS) <= set(KADON_SOURCES)
