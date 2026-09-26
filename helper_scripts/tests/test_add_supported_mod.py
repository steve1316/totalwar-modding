"""Tests for `tools.add_supported_mod`: field guessing, entry writing and the prompts."""

import pytest

from data.supported_mods import SUPPORTED_MODS
from tools import add_supported_mod as asm


def _unit(land_unit, unit=None, caste="melee_infantry"):
    """Build a minimal `main_units_tables` row.

    Args:
        land_unit (str): Land unit key.
        unit (str): Main unit key. Defaults to `land_unit`.
        caste (str): Unit caste.

    Returns:
        The row dict.
    """
    return {"unit": unit or land_unit, "land_unit": land_unit, "caste": caste}


def _subtype(key, unit, auto="true"):
    """Build a minimal `agent_subtypes_tables` row.

    Args:
        key (str): Agent subtype key.
        unit (str): Main unit key in `associated_unit_override`.
        auto (str): `auto_generate` value as rpfm writes it.

    Returns:
        The row dict.
    """
    return {"key": key, "associated_unit_override": unit, "auto_generate": auto}


@pytest.mark.parametrize("link", [
    "https://steamcommunity.com/sharedfiles/filedetails/?id=3565085095",
    "http://steamcommunity.com/sharedfiles/filedetails/?searchtext=ete&id=3565085095",
    "https://steamcommunity.com/workshop/filedetails/?id=3565085095&l=english",
    "  3565085095 ",
])
def test_parse_workshop_id_accepts_links_and_bare_ids(link):
    assert asm.parse_workshop_id(link) == "3565085095"


@pytest.mark.parametrize("link", ["", "not a link", "https://steamcommunity.com/sharedfiles/filedetails/?id=abc", "https://example.com/?foo=1"])
def test_parse_workshop_id_rejects_junk(link):
    with pytest.raises(ValueError):
        asm.parse_workshop_id(link)


def test_guess_attributes_follows_table_presence_in_registry_order():
    assert asm.guess_attributes({"projectiles_tables", "melee_weapons_tables"}) == ["melee", "velocity"]
    assert asm.guess_attributes({"battle_entities_tables"}) == ["ranged_arc"]
    assert asm.guess_attributes({"melee_weapons_tables", "battle_entities_tables", "projectiles_tables"}) == ["melee", "ranged_arc", "velocity"]
    assert asm.guess_attributes({"land_units_tables"}) == []


def test_match_factions_wildcard_returns_every_listed_code():
    assert asm.match_factions("anything", {"*": "chd, nur"}) == ["chd", "nur"]


def test_match_factions_plain_overrides_use_the_underscore_rule():
    # No `*` or `_` in any key, so the generator wraps every key in underscores.
    assert asm.match_factions("aaa_khorne_knight", {"khorne": "kho"}) == ["kho"]
    assert asm.match_factions("aaa_emp_knight", {}) == ["emp"]
    assert asm.match_factions("khorneknight", {"khorne": "kho"}) == []


def test_match_factions_substring_overrides_check_base_codes_first():
    # With a `*` key the generator matches plain substrings, and the base codes come first, so `hef` inside `hefty` wins over the override.
    assert asm.match_factions("stg_hefty_kho_guard", {"*_kho_*": "kho"}) == ["hef"]
    assert asm.match_factions("stg_mutant_kho_guard", {"*_kho_*": "kho"}) == ["kho"]


def test_guess_pattern_overrides_all_race_coded_gives_empty_dict():
    rows = [_unit("xx_emp_inf_a"), _unit("xx_brt_cav_b")]
    guess = asm.guess_pattern_overrides(rows, {})
    assert guess.overrides == {}
    assert guess.by_code == {"emp": ["xx_emp_inf_a"], "brt": ["xx_brt_cav_b"]}


def test_guess_pattern_overrides_one_faction_by_recruit_group_gives_wildcard():
    rows = [_unit("gun_a"), _unit("gun_b")]
    permissions = {"gun_a": {"wh_main_group_empire"}, "gun_b": {"wh_main_group_empire"}}
    guess = asm.guess_pattern_overrides(rows, permissions)
    assert guess.overrides == {"*": "emp"}


def test_guess_pattern_overrides_mixed_or_unknown_is_uncertain():
    rows = [_unit("gun_a"), _unit("axe_b"), _unit("mystery_c")]
    permissions = {"gun_a": {"wh_main_group_empire"}, "axe_b": {"wh_main_group_dwarfs"}}
    guess = asm.guess_pattern_overrides(rows, permissions)
    assert guess.overrides is None
    assert guess.by_code == {"emp": ["gun_a"], "dwf": ["axe_b"]}
    assert guess.unknown == ["mystery_c"]


def test_guess_pattern_overrides_names_without_a_generator_code_are_unknown():
    # Araby has a faction name in `ttc_data` but no LEAPOI faction code.
    guess = asm.guess_pattern_overrides([_unit("camel_a")], {"camel_a": {"ovn_group_araby"}})
    assert guess.overrides is None
    assert guess.unknown == ["camel_a"]


def test_lord_hero_candidates_filters_generic_subtypes_and_adds_mount_variants():
    main_rows = [
        _unit("bm_lord_0", "bm_lord_unit", "lord"),
        _unit("bm_lord_1", "bm_lord_unit_mounted", "lord"),
        _unit("champ_0", "champ_unit", "hero"),
        _unit("legend_0", "legend_unit", "lord"),
        _unit("inf_0", "inf_unit"),
    ]
    subtypes = [
        _subtype("bm_lord", "bm_lord_unit"),
        _subtype("champ", "champ_unit"),
        _subtype("legend", "legend_unit", auto="false"),
        _subtype("ghost", "missing_unit"),
        _subtype("grunt", "inf_unit"),
    ]
    candidates = asm.lord_hero_candidates(subtypes, main_rows)
    assert candidates == [
        asm.Candidate("lord", "bm_lord_0", "bm_lord"),
        asm.Candidate("lord", "bm_lord_1", "bm_lord"),
        asm.Candidate("hero", "champ_0", "champ"),
    ]


def _entry(name="ETE Unit Pack", pack="pwner1_wh3_ete_unit_pack.pack", **extra):
    """Build a registry entry dict for the writer tests.

    Args:
        name (str): Mod name.
        pack (str): Pack filename.
        **extra: Extra fields to add.

    Returns:
        The entry dict.
    """
    entry = {
        "name": name,
        "package_name": pack,
        "path": f"{asm.WORKSHOP_ROOT}/3565085095/{pack}",
        "modified_attributes": ["melee", "ranged_arc", "velocity"],
    }
    entry.update(extra)
    return entry


def _registry_text():
    """Read the real registry text, line endings kept.

    Returns:
        The file text.
    """
    with open("data/supported_mods.py", encoding="utf-8", newline="") as fh:
        return fh.read()


def test_render_entry_matches_the_registry_style():
    entry = _entry(
        pattern_overrides={"*": "emp"},
        character_overrides={"emp": {"allowed_lords": [{"land_unit": "a_0", "agent_subtype": "a"}], "allowed_heroes": [{"land_unit": "b_0", "agent_subtype": "b"}]}},
    )
    assert asm.render_entry(entry) == "\n".join([
        "    {",
        '        "name": "ETE Unit Pack",',
        '        "package_name": "pwner1_wh3_ete_unit_pack.pack",',
        '        "path": f"{STEAM_LIBRARY_DRIVE}/SteamLibrary/steamapps/workshop/content/1142710/3565085095/pwner1_wh3_ete_unit_pack.pack",',
        '        "modified_attributes": ["melee", "ranged_arc", "velocity"],',
        '        "pattern_overrides": {"*": "emp"},',
        '        "character_overrides": {',
        '            "emp": {',
        '                "allowed_lords": [',
        '                    {"land_unit": "a_0", "agent_subtype": "a"},',
        "                ],",
        '                "allowed_heroes": [',
        '                    {"land_unit": "b_0", "agent_subtype": "b"},',
        "                ],",
        "            },",
        "        },",
        "    },",
    ])


def test_render_entry_writes_ignore_generation_as_python_true():
    assert '        "ignore_generation": True,' in asm.render_entry(_entry(ignore_generation=True))


@pytest.mark.parametrize("name, pack", [
    ("ETE Unit Pack", "pwner1_wh3_ete_unit_pack.pack"),
    ("[Zerooz] 兵种合集", "Zerooz_All_Units.pack"),
    ('Trajann\'s "Best" Pack \\ v2', "The Gunpowder Road2.0.pack"),
    ("Spaced Out", "possibly a verminlord.pack"),
])
def test_append_entry_round_trips_on_the_real_registry(name, pack):
    registry = _registry_text()
    entry = _entry(name, pack, pattern_overrides={"*_tze_*": "tze"})
    new_text = asm.append_entry(registry, asm.render_entry(entry), entry)
    assert new_text.startswith(registry[: registry.rindex("]")].rstrip())
    assert "\r\n" in new_text and "\n" not in new_text.replace("\r\n", "")
    namespace = {}
    exec(compile(new_text, "supported_mods.py", "exec"), namespace)
    assert namespace["SUPPORTED_MODS"][-1] == entry
    assert len(namespace["SUPPORTED_MODS"]) == len(SUPPORTED_MODS) + 1


def test_append_entry_refuses_text_that_does_not_parse_back():
    entry = _entry()
    broken = asm.render_entry(entry).replace('"ETE Unit Pack"', '"Other Name"')
    with pytest.raises(ValueError):
        asm.append_entry(_registry_text(), broken, entry)


def _asker(*answers):
    """Build a scripted `ask` that returns the given answers in order.

    Args:
        *answers (str): Answers to hand back, one per prompt.

    Returns:
        The `ask` callable. It records every prompt in its `prompts` list.
    """
    queue = list(answers)

    def ask(prompt):
        ask.prompts.append(prompt)
        return queue.pop(0)

    ask.prompts = []
    return ask


@pytest.mark.parametrize("answer, expected", [
    ("emp", {"*": "emp"}),
    (" chd , nur ", {"*": "chd,nur"}),
    ("{}", {}),
    ('{"*_tze_*": "tze", "khorne_": "kho"}', {"*_tze_*": "tze", "khorne_": "kho"}),
])
def test_parse_pattern_answer_accepts_codes_lists_and_dicts(answer, expected):
    assert asm.parse_pattern_answer(answer) == expected


@pytest.mark.parametrize("answer", ["", "empire", "emp,xyz", "{", '{"a": 1}', '{"a": "xyz"}', "[1]"])
def test_parse_pattern_answer_rejects_bad_answers(answer):
    with pytest.raises(ValueError):
        asm.parse_pattern_answer(answer)


def test_choose_pattern_overrides_asks_again_after_a_bad_answer():
    guess = asm.FactionGuess(None, {"emp": ["gun_a"], "dwf": ["axe_b"]}, ["mystery_c"])
    ask = _asker("empire", "{bad", "emp,dwf")
    assert asm.choose_pattern_overrides(guess, ask) == {"*": "emp,dwf"}
    assert len(ask.prompts) == 3


@pytest.mark.parametrize("answer, expected", [("", []), ("none", []), ("all", [0, 1, 2, 3]), ("1,3-4", [0, 2, 3]), (" 2 ", [1])])
def test_parse_selection_reads_all_none_and_ranges(answer, expected):
    assert asm.parse_selection(answer, 4) == expected


@pytest.mark.parametrize("answer", ["0", "5", "2-9", "a", "3-1"])
def test_parse_selection_rejects_out_of_range_or_junk(answer):
    with pytest.raises(ValueError):
        asm.parse_selection(answer, 4)


def test_choose_characters_groups_by_faction_and_keeps_only_picked():
    candidates = [asm.Candidate("lord", "x_emp_lord_0", "emp_lord"), asm.Candidate("hero", "x_emp_hero_0", "emp_hero"), asm.Candidate("lord", "x_brt_lord_0", "brt_lord")]
    ask = _asker("9", "1-2", "none")
    chosen = asm.choose_characters(candidates, {}, ask)
    assert chosen == {"emp": {"allowed_lords": [{"land_unit": "x_emp_lord_0", "agent_subtype": "emp_lord"}], "allowed_heroes": [{"land_unit": "x_emp_hero_0", "agent_subtype": "emp_hero"}]}}


def test_choose_characters_adds_to_every_faction_of_a_multi_faction_mod():
    candidates = [asm.Candidate("lord", "merc_lord_0", "merc_lord")]
    chosen = asm.choose_characters(candidates, {"*": "chd,nur"}, _asker("all", "all"))
    assert set(chosen) == {"chd", "nur"}


def test_choose_characters_without_candidates_asks_nothing():
    ask = _asker()
    assert asm.choose_characters([], {}, ask) == {}
    assert ask.prompts == []


def test_main_writes_nothing_when_the_user_declines(tmp_path, monkeypatch):
    registry = tmp_path / "supported_mods.py"
    registry.write_bytes(_registry_text().encode("utf-8"))
    monkeypatch.setattr(asm, "REGISTRY_PATH", str(registry))
    monkeypatch.setattr(asm, "already_supported", lambda workshop_id: False)
    monkeypatch.setattr(asm, "find_pack", lambda workshop_id, ask: "x.pack")
    monkeypatch.setattr(asm, "propose_entry", lambda workshop_id, pack_name, name, ask: _entry(name, pack_name))
    before = registry.read_bytes()
    assert asm.main(["3565085095", "--no-update"], ask=_asker("n"), fetch=lambda workshop_id: "Some Mod") == 0
    assert registry.read_bytes() == before


def test_main_appends_the_entry_when_the_user_confirms(tmp_path, monkeypatch):
    registry = tmp_path / "supported_mods.py"
    registry.write_bytes(_registry_text().encode("utf-8"))
    monkeypatch.setattr(asm, "REGISTRY_PATH", str(registry))
    monkeypatch.setattr(asm, "already_supported", lambda workshop_id: False)
    monkeypatch.setattr(asm, "find_pack", lambda workshop_id, ask: "x.pack")
    monkeypatch.setattr(asm, "propose_entry", lambda workshop_id, pack_name, name, ask: _entry(name, pack_name))
    assert asm.main(["3565085095", "--no-update"], ask=_asker("y"), fetch=lambda workshop_id: "Some Mod") == 0
    namespace = {}
    exec(compile(registry.read_text(encoding="utf-8"), "supported_mods.py", "exec"), namespace)
    assert namespace["SUPPORTED_MODS"][-1]["name"] == "Some Mod"


def test_main_stops_on_an_already_supported_mod(monkeypatch):
    monkeypatch.setattr(asm, "already_supported", lambda workshop_id: True)
    assert asm.main(["3565085095", "--no-update"], ask=_asker(), fetch=lambda workshop_id: "x") == 1


def test_already_supported_finds_registry_ids():
    assert asm.already_supported("3565085095")
    assert not asm.already_supported("1")
