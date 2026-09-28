"""Tests for `tools.generate_kadon_scrolls`, which builds Kin and Binding scrolls for vanilla creatures."""

import os

import pytest

from data.kadon_new_creatures import KADON_NEW_CREATURES
from tools import generate_kadon_scrolls as gen

# Vanilla main units as extracted by a generator or sync run. Tests that need real vanilla data skip without it.
VANILLA_MAIN_UNITS = "temp/vanilla_main_units_tables/db/main_units_tables/data__.tsv"


def test_summon_uses_is_two_for_war_beasts_and_big_packs():
    assert gen.summon_uses({"caste": "war_beast", "num_men": "16"}) == 2
    assert gen.summon_uses({"caste": "monstrous_infantry", "num_men": "60"}) == 2
    assert gen.summon_uses({"caste": "monstrous_infantry", "num_men": "24"}) == 2
    assert gen.summon_uses({"caste": "monstrous_infantry", "num_men": "16"}) == 1
    assert gen.summon_uses({"caste": "monster", "num_men": "4"}) == 1
    assert gen.summon_uses({"caste": "monster", "num_men": "1"}) == 1
    assert gen.summon_uses({"caste": "war_beast", "num_men": "1"}) == 1


@pytest.mark.skipif(not os.path.exists(VANILLA_MAIN_UNITS), reason="needs vanilla main_units extracted to temp/")
def test_new_creatures_split_into_22_two_use_and_87_one_use():
    main_units = {row["unit"]: row for row in gen.read_tsv(VANILLA_MAIN_UNITS)[2]}
    uses = [gen.summon_uses(main_units[key]) for _, key, _ in KADON_NEW_CREATURES]
    assert (uses.count(2), uses.count(1)) == (22, 87)


def test_spawn_proxy_vfx_matches_existing_scrolls():
    assert gen.spawn_proxy_vfx(60, flies=True) == "wh_main_targeting_pre_spawn_solo_flying_ui_central"
    assert gen.spawn_proxy_vfx(1, flies=False) == "wh_main_targeting_pre_spawn_solo_ui_central"
    assert gen.spawn_proxy_vfx(16, flies=False) == "wh_main_targeting_pre_spawn_group_ui_central"


def test_unique_ids_are_distinct_per_scroll():
    assert gen.unique_ids(0) == (97000000, 97000001)
    assert gen.unique_ids(3) == (97000006, 97000007)
    all_ids = [i for index in range(len(KADON_NEW_CREATURES)) for i in gen.unique_ids(index)]
    assert len(set(all_ids)) == len(all_ids)
    assert max(all_ids) <= 97000999


def test_summons_text_uses_an_article_only_for_single_models():
    assert gen.summons_text("Carrion", 24) == "[[col:green]]Summons Carrion[[/col]]"
    assert gen.summons_text("Terrorgheist", 1) == "[[col:green]]Summons a Terrorgheist[[/col]]"
    assert gen.summons_text("Ancient Salamander", 1) == "[[col:green]]Summons an Ancient Salamander[[/col]]"


def test_game_tag_comes_from_the_key_prefix():
    assert gen.game_tag("wh_main_vmp_mon_terrorgheist") == "WH1"
    assert gen.game_tag("wh2_pro06_tmb_mon_bone_giant_0") == "WH2"
    assert gen.game_tag("wh3_main_kho_mon_bloodthirster_0") == "WH3"


def test_swap_cells_replaces_whole_cells_only():
    rows = [{"a": "kadon_bind_hydra", "b": "kadon_hydra", "c": "kadon_bind_hydra_extra"}]
    assert gen.swap_cells(rows, {"kadon_bind_hydra": "kadon_bind_x", "kadon_hydra": "kadon_x"}) == [
        {"a": "kadon_bind_x", "b": "kadon_x", "c": "kadon_bind_hydra_extra"}
    ]


def test_main_unit_row_is_vanilla_plus_kadon_constants():
    vanilla = {"unit": "wh_x", "land_unit": "wh_x_lu", "tier": "4", "upkeep_cost": "250", "mount": "wh_mount", "is_renown": "true"}
    row = gen.build_main_unit_row(vanilla, "kadon_bind_x")
    assert row["unit"] == "kadon_bind_x"
    assert row["land_unit"] == "kadon_bind_x"
    assert row["tier"] == "4"
    assert row["upkeep_cost"] == "0"
    assert row["mount"] == ""
    assert row["is_renown"] == "false"


def test_ability_rows_copy_vanilla_passives_and_add_unbinding_on_bind():
    vanilla = [{"ability": "p1", "land_unit": "wh_x", "culture": "*"}, {"ability": "p2", "land_unit": "wh_x", "culture": "wh_main_vmp_vampire_counts"}]
    bind = gen.build_ability_rows("kadon_bind_x", vanilla, is_bind=True)
    kin = gen.build_ability_rows("kadon_kin_x", vanilla, is_bind=False)
    assert bind == [
        {"ability": "kadon_bind_unbinding", "land_unit": "kadon_bind_x", "culture": "*"},
        {"ability": "p1", "land_unit": "kadon_bind_x", "culture": "*"},
        {"ability": "p2", "land_unit": "kadon_bind_x", "culture": "wh_main_vmp_vampire_counts"},
    ]
    assert kin == [
        {"ability": "p1", "land_unit": "kadon_kin_x", "culture": "*"},
        {"ability": "p2", "land_unit": "kadon_kin_x", "culture": "wh_main_vmp_vampire_counts"},
    ]


def test_pick_unit_variant_prefers_the_factionless_row():
    rows = [
        {"faction": "wh_main_emp_empire", "unit": "wh_x", "variant": "emp", "unit_card": "emp_card"},
        {"faction": "", "unit": "wh_x", "variant": "base", "unit_card": "base_card"},
        {"faction": "", "unit": "wh_y", "variant": "other", "unit_card": "other_card"},
    ]
    assert gen.pick_unit_variant("wh_x", rows)["variant"] == "base"
    assert gen.pick_unit_variant("wh_y", rows)["variant"] == "other"
    assert gen.pick_unit_variant("missing", rows) is None


def test_find_unit_variant_falls_back_to_a_unit_sharing_the_land_unit():
    main_units = {
        "wh3_bst_basilisk": {"unit": "wh3_bst_basilisk", "land_unit": "wh3_chs_basilisk"},
        "wh3_chs_basilisk": {"unit": "wh3_chs_basilisk", "land_unit": "wh3_chs_basilisk"},
        "wh_lonely": {"unit": "wh_lonely", "land_unit": "wh_lonely_lu"},
    }
    variants = [{"faction": "", "unit": "wh3_chs_basilisk", "variant": "chs_basilisk", "unit_card": "chs_card"}]
    assert gen.find_unit_variant("wh3_bst_basilisk", main_units, variants)["variant"] == "chs_basilisk"
    assert gen.find_unit_variant("wh_lonely", main_units, variants) is None
    main_units["wh3_flamers"] = {"unit": "wh3_flamers", "land_unit": "wh3_flamer_lu"}
    variants.append({"faction": "", "unit": "wh3_flamer_lu", "variant": "flamer", "unit_card": "flamer_card"})
    assert gen.find_unit_variant("wh3_flamers", main_units, variants)["variant"] == "flamer"


def test_validate_reports_every_problem():
    creatures = [("good", "wh_good", None), ("trolls", "wh_trolls", None), ("no_unit", "wh_missing", None), ("good", "wh_good", None)]
    errors = gen.validate(
        creatures,
        existing_ids={"trolls"},
        main_units={"wh_good": {}, "wh_trolls": {}},
        names={"wh_good": "Good", "wh_trolls": "Trolls"},
        variants={"wh_good", "wh_trolls"},
        taken_unique_ids=set(),
    )
    assert any("trolls" in e and "hand-made" in e for e in errors)
    assert any("wh_missing" in e for e in errors)
    assert any("good" in e and "duplicate" in e for e in errors)


def test_validate_reports_unique_id_collisions():
    errors = gen.validate([("a", "wh_a", None)], existing_ids=set(), main_units={"wh_a": {}}, names={"wh_a": "A"}, variants={"wh_a"}, taken_unique_ids={97000001})
    assert any("97000001" in e for e in errors)


def test_lua_creature_list_is_a_returned_table():
    text = gen.lua_creature_list([("carrion", "Carrion", "WH2"), ("cursd_ettin", "Curs'd Ettin", "WH3")])
    assert text.startswith("--- ")
    assert 'return {\n    { id = "carrion", name = "Carrion", game = "WH2" },\n    { id = "cursd_ettin", name = "Curs\'d Ettin", game = "WH3" },\n}\n' in text


def test_generated_meta_points_at_the_generated_file():
    meta = "#ancillaries_tables;0;db/ancillaries_tables/jvj_kadon_binding\t"
    assert gen._generated_meta(meta, "jvj_kadon_binding", "jvj_kadon_generated_binding") == "#ancillaries_tables;0;db/ancillaries_tables/jvj_kadon_generated_binding\t"
    ui_meta = "#unit_abilities_additional_ui_effects_tables;3;db/unit_abilities_additional_ui_effects_tables/jvj_kadon\t\t"
    assert gen._generated_meta(ui_meta, "jvj_kadon", "jvj_kadon_generated").endswith("/jvj_kadon_generated\t\t")


def test_generated_lua_tags_follow_the_main_unit_key():
    with open(gen.GENERATED_LUA, encoding="utf-8") as f:
        text = f.read()
    for cid, key, _ in KADON_NEW_CREATURES:
        assert f'{{ id = "{cid}",' in text and f'game = "{gen.game_tag(key)}" }}' in text.split(f'{{ id = "{cid}",', 1)[1].split("\n", 1)[0]


def test_new_creature_ids_are_snake_case_and_unique():
    ids = [cid for cid, _, _ in KADON_NEW_CREATURES]
    assert len(ids) == 109
    assert len(set(ids)) == len(ids)
    assert all(cid.replace("_", "").isalnum() and cid == cid.lower() for cid in ids)
