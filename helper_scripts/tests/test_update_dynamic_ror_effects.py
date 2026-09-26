"""Tests that `remove_effects_from_file` drops exactly the named keys from `dynamic_rors_effects.py` content."""

import update_dynamic_ror_effects

CONTENT = """SUPPORTED_EFFECTS = {
    "melee": [
        "nanu_dynamic_ror_a",
        "nanu_dynamic_ror_a_greater",
        "nanu_dynamic_ror_b",
    ],
    "misc": [
        "nanu_dynamic_ror_c",
    ],
}
"""


def test_removes_only_whole_keys():
    result = update_dynamic_ror_effects.remove_effects_from_file(CONTENT, {"nanu_dynamic_ror_a", "nanu_dynamic_ror_c"})
    assert '"nanu_dynamic_ror_a",' not in result
    assert '"nanu_dynamic_ror_a_greater",' in result
    assert '"nanu_dynamic_ror_b",' in result
    assert '"nanu_dynamic_ror_c",' not in result
    assert '    "misc": [\n    ],' in result


SYNC_CONTENT = """SUPPORTED_EFFECTS = {
    "melee": [
        "nanu_dynamic_ror_basic_melee_kept",
        "nanu_dynamic_ror_basic_melee_renamed_away",
    ],
    "generic": [
        "nanu_dynamic_ror_basic_all_kept",
    ],
}
"""


def test_sync_adds_new_and_removes_deleted_effects():
    mod_effects = {"nanu_dynamic_ror_basic_melee_kept", "nanu_dynamic_ror_basic_all_kept", "nanu_dynamic_ror_basic_melee_new"}
    content, result = update_dynamic_ror_effects.sync_effects_content(SYNC_CONTENT, mod_effects)
    effects = update_dynamic_ror_effects.parse_effects(content)
    assert effects["melee"] == ["nanu_dynamic_ror_basic_melee_kept", "nanu_dynamic_ror_basic_melee_new"]
    assert effects["generic"] == ["nanu_dynamic_ror_basic_all_kept"]
    assert result.added == ["nanu_dynamic_ror_basic_melee_new"]
    assert result.removed == ["nanu_dynamic_ror_basic_melee_renamed_away"]
    assert result.uncategorized == []
    assert result.changed


def test_sync_reports_effects_left_uncategorized():
    mod_effects = {"nanu_dynamic_ror_basic_melee_kept", "nanu_dynamic_ror_basic_melee_renamed_away", "nanu_dynamic_ror_basic_all_kept", "nanu_dynamic_ror_mystery"}
    content, result = update_dynamic_ror_effects.sync_effects_content(SYNC_CONTENT, mod_effects)
    assert update_dynamic_ror_effects.parse_effects(content)["misc"] == ["nanu_dynamic_ror_mystery"]
    assert result.uncategorized == ["nanu_dynamic_ror_mystery"]


def test_sync_leaves_matching_content_unchanged():
    mod_effects = {"nanu_dynamic_ror_basic_melee_kept", "nanu_dynamic_ror_basic_melee_renamed_away", "nanu_dynamic_ror_basic_all_kept"}
    content, result = update_dynamic_ror_effects.sync_effects_content(SYNC_CONTENT, mod_effects)
    assert content == SYNC_CONTENT
    assert not result.changed
