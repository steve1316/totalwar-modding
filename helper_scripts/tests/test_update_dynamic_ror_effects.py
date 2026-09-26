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
