"""Tests for the spot map's coordinates.lua reader and writer: parsing, flags in place, appending spots and points of interest, and creating a
new campaign block."""

import os
import subprocess

import pytest

from tools.spot_map import coordinates_io as cio

FIXTURE = """--- Coordinates for testing.

local M = {}

M.immortal_empires = {
    treasures_and_spots = {
         ["alpha"] = {
              --- North Hills
              {10, 20},
              {30, 40},
              --- South Marsh
              {50, 60, disabled = true},
         },
         ["beta"] = {
              --- Beta Plains
              {70, 80},
         },
    },
    points_of_interest = {
        ["alpha"] = {
            ["smithies"] = {
                { coordinates = {11, 22}, initial_owner = "owner_a", owner_if_player = "owner_b", region = "" }
            },

            ["taverns"] = {},

            ["resources"] = {}
         },
        ["beta"] = {
            ["smithies"] = {
                {
                    coordinates = {33, 44},
                    initial_owner = "owner_c",
                    owner_if_player = "owner_d",
                    region = ""
                },
            },
            ["resources"] = {}
         },
    },
}

return M
"""


@pytest.fixture
def lua_file(tmp_path):
    """Writes the fixture with CRLF line endings, like the real file.

    Args:
        tmp_path (pathlib.Path): Pytest temporary folder.

    Returns:
        The fixture's path as a string.
    """
    path = tmp_path / "coordinates.lua"
    path.write_bytes(FIXTURE.replace("\n", "\r\n").encode("utf-8"))
    return str(path)


def _parse(path):
    """Parses a file.

    Args:
        path (str): File to parse.

    Returns:
        Campaigns by key.
    """
    return cio.parse(cio.read_lines(path)[0])


def _pois(path, key="immortal_empires"):
    """Lists a campaign's points of interest as plain tuples.

    Args:
        path (str): File to parse.
        key (str): Campaign key.

    Returns:
        (zone, kind, index, x, y, disabled, initial_owner) per entry.
    """
    return [(p.zone, p.kind, p.index, p.x, p.y, p.disabled, p.fields.get("initial_owner")) for p in _parse(path)[key].pois]


def _lua_loads(path):
    """Checks the file still loads as Lua, when Lua is installed.

    Args:
        path (str): File to load.
    """
    try:
        result = subprocess.run(["lua", "-e", f"dofile([[{path}]])"], capture_output=True, text=True)
    except FileNotFoundError:
        return
    assert result.returncode == 0, result.stderr


def test_parse_reads_zones_spots_areas_and_pois(lua_file):
    campaign = _parse(lua_file)["immortal_empires"]
    alpha = campaign.zones["alpha"]
    assert [(s.index, s.x, s.y, s.area, s.disabled) for s in alpha.spots] == [
        (1, 10, 20, "North Hills", False), (2, 30, 40, "North Hills", False), (3, 50, 60, "South Marsh", True)]
    assert _pois(lua_file) == [("alpha", "smithies", 1, 11, 22, False, "owner_a"), ("beta", "smithies", 1, 33, 44, False, "owner_c")]
    assert campaign.poi_zones["alpha"].lists["taverns"].inline
    assert not campaign.poi_zones["alpha"].lists["smithies"].inline


def test_disable_and_enable_rewrite_lines_in_place(lua_file):
    before = open(lua_file, "rb").read()
    cio.apply_edits(lua_file, "immortal_empires", [], [{"zone": "alpha", "index": 1}], [{"zone": "alpha", "index": 3}])
    after = open(lua_file, "rb").read()
    assert b"{10, 20, disabled = true},\r\n" in after
    assert b"{50, 60},\r\n" in after
    assert after.count(b"\r\n") == before.count(b"\r\n")
    assert [(s.index, s.disabled) for s in _parse(lua_file)["immortal_empires"].zones["alpha"].spots] == [(1, True), (2, False), (3, False)]


def test_add_spots_with_flags_at_zone_end(lua_file):
    cio.apply_edits(lua_file, "immortal_empires", [{"zone": "alpha", "area": "South Marsh", "x": 91, "y": 92},
                                                   {"zone": "alpha", "area": "Far Cape", "x": 93, "y": 94, "flags": ["tower"]}], [], [])
    text = open(lua_file, encoding="utf-8", newline="").read()
    assert "{50, 60, disabled = true},\r\n              {91, 92},\r\n              --- Far Cape\r\n              {93, 94, tower = true},\r\n         }," in text
    spots = _parse(lua_file)["immortal_empires"].zones["alpha"].spots
    assert [(s.index, s.x, s.area, s.flags) for s in spots][-2:] == [(4, 91, "South Marsh", set()), (5, 93, "Far Cape", {"tower"})]
    _lua_loads(lua_file)


def test_add_to_a_new_zone_creates_it_inside_the_section(lua_file):
    cio.apply_edits(lua_file, "immortal_empires", [{"zone": "gamma", "area": "New Land", "x": 5, "y": 6}], [], [])
    campaign = _parse(lua_file)["immortal_empires"]
    assert [(s.x, s.y, s.area) for s in campaign.zones["gamma"].spots] == [(5, 6, "New Land")]
    assert len(campaign.pois) == 2
    _lua_loads(lua_file)


def test_add_pois_to_every_kind_of_list(lua_file):
    smithy = {"initial_owner": "owner_x", "owner_if_player": "owner_y", "region": ""}
    cio.apply_edits(lua_file, "immortal_empires", [
        {"storage": "poi", "zone": "alpha", "list": "smithies", "x": 12, "y": 23, "fields": smithy},
        {"storage": "poi", "zone": "alpha", "list": "taverns", "x": 13, "y": 24, "fields": {"culture": "emp", "initial_owner": "o", "owner_if_player": "p"}},
        {"storage": "poi", "zone": "beta", "list": "taverns", "x": 34, "y": 45, "fields": {"culture": None, "initial_owner": "o", "owner_if_player": "p"}},
        {"storage": "poi", "zone": "gamma", "list": "smithies", "x": 56, "y": 67, "fields": smithy},
    ], [], [])
    assert _pois(lua_file) == [
        ("alpha", "smithies", 1, 11, 22, False, "owner_a"), ("alpha", "smithies", 2, 12, 23, False, "owner_x"),
        ("alpha", "taverns", 1, 13, 24, False, "o"), ("beta", "smithies", 1, 33, 44, False, "owner_c"),
        ("beta", "taverns", 1, 34, 45, False, "o"), ("gamma", "smithies", 1, 56, 67, False, "owner_x")]
    neutral = next(p for p in _parse(lua_file)["immortal_empires"].pois if p.zone == "beta" and p.kind == "taverns")
    assert "culture" not in neutral.fields
    _lua_loads(lua_file)


def test_planted_entries_are_written_as_manual(lua_file):
    from tools.spot_map import campaigns
    tower = campaigns.to_entry({"type": "tower", "zone": "alpha", "area": "Far Cape", "x": 1, "y": 2})
    smithy = campaigns.to_entry({"type": "smithy", "zone": "alpha", "x": 3, "y": 4, "fields": {"initial_owner": "o", "owner_if_player": "p"}})
    cio.apply_edits(lua_file, "immortal_empires", [tower, smithy], [], [])
    campaign = _parse(lua_file)["immortal_empires"]
    assert campaign.zones["alpha"].spots[-1].flags == {"tower", "manual"}
    planted = next(p for p in campaign.pois if p.x == 3)
    assert planted.flags == {"manual"} and planted.fields == {"initial_owner": "o", "owner_if_player": "p", "region": ""}
    cio.apply_edits(lua_file, "immortal_empires", [], [{"target": "poi", "zone": "alpha", "kind": "smithies", "index": planted.index}], [])
    assert next(p for p in _parse(lua_file)["immortal_empires"].pois if p.x == 3).flags == {"manual", "disabled"}
    _lua_loads(lua_file)


def test_disable_and_enable_pois_single_and_multi_line(lua_file):
    targets = [{"target": "poi", "zone": "alpha", "kind": "smithies", "index": 1}, {"target": "poi", "zone": "beta", "kind": "smithies", "index": 1}]
    cio.apply_edits(lua_file, "immortal_empires", [], targets, [])
    assert [p[5] for p in _pois(lua_file)] == [True, True]
    _lua_loads(lua_file)
    cio.apply_edits(lua_file, "immortal_empires", [], [], targets)
    assert [p[5] for p in _pois(lua_file)] == [False, False]
    assert open(lua_file, encoding="utf-8").read() == FIXTURE


def test_move_rewrites_coordinates_in_place_and_marks_manual(lua_file):
    moves = [{"target": "spot", "zone": "alpha", "index": 3, "x": 55, "y": 66},
             {"target": "poi", "zone": "alpha", "kind": "smithies", "index": 1, "x": 12, "y": 21},
             {"target": "poi", "zone": "beta", "kind": "smithies", "index": 1, "x": 34, "y": 43}]
    result = cio.apply_edits(lua_file, "immortal_empires", [], [], [], move=moves)
    assert result["moved"] == 3
    campaign = _parse(lua_file)["immortal_empires"]
    spot = campaign.zones["alpha"].spots[2]
    assert (spot.index, spot.x, spot.y, spot.flags) == (3, 55, 66, {"disabled", "manual"})
    assert [(p.x, p.y, p.flags, p.index) for p in campaign.pois] == [(12, 21, {"manual"}, 1), (34, 43, {"manual"}, 1)]
    assert campaign.pois[1].fields["initial_owner"] == "owner_c"
    _lua_loads(lua_file)
    cio.apply_edits(lua_file, "immortal_empires", [], [], [{"target": "poi", "zone": "beta", "kind": "smithies", "index": 1}],
                    move=[{"target": "poi", "zone": "beta", "kind": "smithies", "index": 1, "x": 35, "y": 44}])
    _lua_loads(lua_file)


def test_missing_campaign_is_created_from_seed_and_takes_pois(lua_file):
    seed = [{"zone": "draft", "area": "Lakeland", "x": 101, "y": 1395}, {"zone": "draft", "area": "Lakeland", "x": 151, "y": 1407}]
    result = cio.apply_edits(lua_file, "old_world", [{"zone": "draft", "area": "Neuland", "x": 164, "y": 1329},
                                                     {"storage": "poi", "zone": "draft", "list": "smithies", "x": 1, "y": 2, "fields": {"region": ""}}],
                             [{"zone": "draft", "index": 2}], [], seed=seed, note="Draft spots.")
    assert result["created"] == "old_world"
    campaigns = _parse(lua_file)
    spots = campaigns["old_world"].zones["draft"].spots
    assert [(s.x, s.area, s.disabled) for s in spots] == [(101, "Lakeland", False), (151, "Lakeland", True), (164, "Neuland", False)]
    assert [(p.zone, p.kind, p.x) for p in campaigns["old_world"].pois] == [("draft", "smithies", 1)]
    assert len(campaigns["immortal_empires"].zones["alpha"].spots) == 3
    _lua_loads(lua_file)


def test_draft_block_is_written_then_replaced(lua_file):
    spots = [{"zone": "east", "area": "Hills", "x": 1, "y": 2, "flags": ["manual"]}, {"zone": "east", "area": "Hills", "x": 3, "y": 4, "flags": ["tower", "manual"]}]
    pois = [{"zone": "east", "list": "smithies", "x": 5, "y": 6, "fields": {"initial_owner": "o", "region": "", "manual": True}}]
    assert not cio.write_block(lua_file, "immortal_empires_draft", "Draft.", spots, pois)
    draft = _parse(lua_file)["immortal_empires_draft"]
    assert [(s.x, s.flags) for s in draft.zones["east"].spots] == [(1, {"manual"}), (3, {"tower", "manual"})]
    assert [(p.kind, p.x, p.fields["initial_owner"]) for p in draft.pois] == [("smithies", 5, "o")]
    _lua_loads(lua_file)
    assert cio.write_block(lua_file, "immortal_empires_draft", "Draft.", spots[:1], [])
    text = open(lua_file, encoding="utf-8").read()
    assert text.count("M.immortal_empires_draft") == 1 and text.count("--- immortal_empires_draft") == 1
    assert [s.x for s in _parse(lua_file)["immortal_empires_draft"].zones["east"].spots] == [1]
    assert len(_parse(lua_file)["immortal_empires"].zones["alpha"].spots) == 3
    _lua_loads(lua_file)


def test_unknown_entries_are_rejected(lua_file):
    with pytest.raises(ValueError):
        cio.apply_edits(lua_file, "immortal_empires", [], [{"zone": "alpha", "index": 9}], [])
    with pytest.raises(ValueError):
        cio.apply_edits(lua_file, "immortal_empires", [], [{"target": "poi", "zone": "alpha", "kind": "taverns", "index": 1}], [])
    with pytest.raises(ValueError):
        cio.apply_edits(lua_file, "old_world", [], [], [])


def test_backup_copies_the_file(lua_file, tmp_path):
    target = cio.backup(lua_file, str(tmp_path / "backups"))
    assert open(target, "rb").read() == open(lua_file, "rb").read()


REAL = "../warhammer3_mods/land_encounters_and_points_of_interest_with_mct/script/land_encounters/configs/coordinates.lua"


@pytest.mark.skipif(not os.path.isfile(REAL), reason="LEAPOI coordinates.lua is not in this checkout.")
def test_real_file_parses_every_spot_and_smithy():
    campaigns = _parse(REAL)
    counts = {k: sum(len(z.spots) for z in c.zones.values()) for k, c in campaigns.items()}
    assert counts["immortal_empires"] >= 588 and counts["realm_of_chaos"] >= 179 and counts["immortal_empires_expanded"] >= 72
    assert sum(1 for p in campaigns["immortal_empires"].pois if p.kind == "smithies") == 54
    assert all(z.close_line > 0 for c in campaigns.values() for z in c.zones.values())
    assert all(c.spots_close_line > 0 and c.pois_close_line > 0 for c in campaigns.values())
