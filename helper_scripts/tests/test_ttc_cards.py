"""Tests for finding units without card art."""

import subprocess

from ttc import ttc_cards, ttc_data


def make_data():
    data = ttc_data.TtcData()
    data.stats = {
        "own_card": ttc_data.UnitStats("own_card", {"land_unit": "own_card"}, {}, set()),
        "variant_card": ttc_data.UnitStats("variant_card", {"land_unit": "variant_card"}, {}, set()),
        "borrowed": ttc_data.UnitStats("borrowed", {"land_unit": "tze_tzaangors"}, {}, set()),
        "unfinished": ttc_data.UnitStats("unfinished", {"land_unit": "unfinished"}, {}, set()),
    }
    data.unit_cards = {"variant_card": "Shared_Card", "tze_tzaangors": "tze_card"}
    return data


def test_has_card_checks_the_variant_card_the_key_and_the_borrowed_land_unit():
    data, cards = make_data(), {"own_card", "shared_card", "tze_card"}
    assert [key for key in data.stats if ttc_cards.has_card(key, data, cards)] == ["own_card", "variant_card", "borrowed"]


def test_list_cards_reads_only_unit_icons(monkeypatch):
    listing = "INFO Logger initialized.\nUI/units/icons/Wolf.png\nui/units/icons/sub/bear.png\nui/skins/default/x.png\n"
    monkeypatch.setattr(ttc_cards, "run_rpfm_cli", lambda *a, **k: subprocess.CompletedProcess([], 0, b"", listing.encode()))
    assert ttc_cards._list_cards("x.pack") == ["UI/units/icons/Wolf.png"]
    monkeypatch.setattr(ttc_cards, "run_rpfm_cli", lambda *a, **k: subprocess.CompletedProcess([], 1, b"", b"error"))
    assert ttc_cards._list_cards("x.pack") is None


def test_card_packs_gives_up_when_a_pack_cannot_be_listed(tmp_path, monkeypatch):
    vanilla, mod = tmp_path / "ui.pack", tmp_path / "1" / "mod.pack"
    mod.parent.mkdir()
    vanilla.write_bytes(b"v")
    mod.write_bytes(b"m")
    (tmp_path / "2").mkdir()
    (tmp_path / "2" / "Alternative_Cards.pack").write_bytes(b"a")
    monkeypatch.setattr(ttc_cards, "VANILLA_UI_PACK", str(vanilla))
    monkeypatch.setattr(ttc_cards, "WORKSHOP_ROOT", str(tmp_path))
    monkeypatch.setattr(ttc_cards, "CARD_INDEX_PATH", str(tmp_path / "index.json"))
    seen = []
    monkeypatch.setattr(ttc_cards, "_list_cards", lambda path: seen.append(path) or (["ui/units/icons/wolf.png"] if path == str(vanilla) else []))
    assert ttc_cards.card_packs() == {str(vanilla): ["ui/units/icons/wolf.png"]}
    assert ttc_cards.card_names(ttc_cards.card_packs()) == {"wolf"}
    assert not any("Alternative_Cards" in path for path in seen)
    # A failed listing must not read as "no cards", or every unit in that pack would be ignored.
    mod.write_bytes(b"changed")
    monkeypatch.setattr(ttc_cards, "_list_cards", lambda path: None)
    assert ttc_cards.card_packs() is None


def test_cardless_units_skip_lords_and_heroes_and_give_up_without_a_listing():
    data = make_data()
    data.stats["a_lord"] = ttc_data.UnitStats("a_lord", {"land_unit": "a_lord", "caste": "lord"}, {}, set())
    packs = {"ui.pack": ["ui/units/icons/own_card.png", "UI/units/icons/Shared_Card.png", "ui/units/icons/tze_card.png"]}
    assert ttc_cards.cardless_units(data, packs) == {"unfinished"}
    assert ttc_cards.cardless_units(data, None) is None
