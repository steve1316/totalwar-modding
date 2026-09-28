"""Tests for `tools.generate_kadon_dlc`, which records the paid DLC each Kadon scroll's unit needs."""

import os

import pytest

from tools import generate_kadon_dlc as gen

# Vanilla ownership junctions as extracted by a generator run. Tests that need real vanilla data skip without it.
VANILLA_JUNCTIONS = "temp/vanilla_main_unit_ownership_content_pack_junctions_tables/db/main_unit_ownership_content_pack_junctions_tables/data__.tsv"

PRODUCTS = [
    {"key": "TW_WH2_BASE_GAME", "is_flc": "false"},
    {"key": "TW_WH3_ROC_UPDATE", "is_flc": "false"},
    {"key": "TW_WH2_TWA_03_RAKARTH", "is_flc": "true"},
    {"key": "TW_WH1_BEASTMEN", "is_flc": "false"},
    {"key": "TW_WH2_DLC17_SILENCE", "is_flc": "false"},
]


def test_free_products_are_base_games_the_roc_update_and_flc():
    assert gen.free_products(PRODUCTS) == {"TW_WH2_BASE_GAME", "TW_WH3_ROC_UPDATE", "TW_WH2_TWA_03_RAKARTH"}


def ownership(unit_packs):
    """Builds an `Ownership` with two packs: a base-game pack and a Beastmen pack that Silence & Fury also unlocks."""
    return gen.Ownership(
        unit_packs=unit_packs,
        pack_sets={"core_lzd": {"lzd_req"}, "core_bst": {"bst_req", "bst_req_silence"}, "mixed": {"mixed_req"}},
        set_products={
            "lzd_req": {"TW_WH2_BASE_GAME", "TW_WH2_TWA_03_RAKARTH"},
            "bst_req": {"TW_WH1_BEASTMEN"},
            "bst_req_silence": {"TW_WH2_DLC17_SILENCE"},
            "mixed_req": {"TW_WH1_BEASTMEN", "TW_WH2_DLC17_SILENCE"},
        },
        free={"TW_WH2_BASE_GAME", "TW_WH3_ROC_UPDATE", "TW_WH2_TWA_03_RAKARTH"},
    )


def test_paid_products_is_empty_when_any_requirement_set_is_free():
    own = ownership({"wh2_carnosaur": {"core_lzd"}, "wh_both": {"core_lzd", "core_bst"}})
    assert gen.paid_products("wh2_carnosaur", own) == []
    assert gen.paid_products("wh_both", own) == []


def test_paid_products_lists_every_dlc_that_unlocks_the_unit():
    own = ownership({"wh_minotaurs": {"core_bst"}})
    assert gen.paid_products("wh_minotaurs", own) == ["TW_WH1_BEASTMEN", "TW_WH2_DLC17_SILENCE"]


def test_paid_products_treats_a_unit_without_packs_as_free():
    assert gen.paid_products("wh_unknown", ownership({})) == []


def test_paid_products_rejects_a_set_needing_two_paid_products():
    with pytest.raises(ValueError, match="wh_mixed"):
        gen.paid_products("wh_mixed", ownership({"wh_mixed": {"mixed"}}))


def test_lua_dlc_map_is_a_sorted_returned_table():
    text = gen.lua_dlc_map({"kadon_kin_b": ["TW_B"], "kadon_bind_a": ["TW_A", "TW_C"]})
    assert text.startswith("--- ")
    assert 'return {\n    kadon_bind_a = { "TW_A", "TW_C" },\n    kadon_kin_b = { "TW_B" },\n}\n' in text


@pytest.mark.skipif(not os.path.exists(VANILLA_JUNCTIONS), reason="needs vanilla ownership tables extracted to temp/")
def test_generated_map_matches_the_ownership_tables():
    with open(gen.DLC_LUA, encoding="utf-8") as f:
        assert f.read() == gen.lua_dlc_map(gen.build_dlc_map())
