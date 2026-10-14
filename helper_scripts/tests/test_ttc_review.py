"""Tests for the TTC unit browser's catalog, rosters and save."""

from tools.ttc_review import catalog
from ttc import ttc_compat_io, ttc_data
from ttc.unit_panel import missile_stats

# Wolves from Animals for Wood Elves, checked against the in-game unit panel: 6624 HP, 15 armour, 55 leadership, 95 speed, 26/21 melee, 42 weapon
# strength, 38 charge.
WOLF_MAIN = {
    "unit": "rory_welf_small_wolf", "land_unit": "rory_welf_small_wolf", "num_men": "48", "tier": "1", "multiplayer_cost": "700", "caste": "war_beast",
    "ui_unit_group_land": "war_beasts",
}
WOLF_LAND = {
    "key": "rory_welf_small_wolf",
    "man_entity": "wolf_entity",
    "bonus_hit_points": "130",
    "armour": "wh_main_leather_15",
    "morale": "55",
    "melee_attack": "26",
    "melee_defence": "21",
    "charge_bonus": "38",
    "primary_melee_weapon": "wolf_claw",
    "class": "inf_mel",
}
ART = {
    **{f"ui/units/icons/{key}.png": f"{key}.png" for key in ("wef_guard", "wef_exclusive", "wef_loose", "wef_tank")},
    "ui/units/icons/rory_welf_small_wolf.png": "card.png",
    "ui/battle ui/ability_icons/howl_icon.png": "howl.png",
    "ui/common ui/unit_category_icons/war_beasts.png": "cat.png",
}


def unit(key, caste="war_beast", group="war_beasts", cost="500"):
    main = {"unit": key, "land_unit": key, "num_men": "60", "caste": caste, "ui_unit_group_land": group, "multiplayer_cost": cost}
    return ttc_data.UnitStats(key, main, {"key": key}, set())


def make_catalog(**extra_tables):
    tables = {table: [] for table in catalog.DETAIL_TABLES}
    tables["battle_entities_tables"] = [{"key": "wolf_entity", "hit_points": "8", "run_speed": "9.5000"}, {"key": "horse", "hit_points": "10", "run_speed": "8.0000"}]
    tables["melee_weapons_tables"] = [{"key": "wolf_claw", "damage": "29", "ap_damage": "13"}]
    tables["unit_armour_types_tables"] = [{"key": "wh_main_leather_15", "armour_value": "15"}]
    tables["unit_abilities_tables"] = [{"key": "howl", "icon_name": "Howl_Icon", "is_hidden_in_ui": "false"}, {"key": "secret", "icon_name": "x", "is_hidden_in_ui": "true"}]
    tables["land_units_to_unit_abilites_junctions_tables"] = [{"ability": "howl", "land_unit": "rory_welf_small_wolf"}, {"ability": "secret", "land_unit": "rory_welf_small_wolf"}]
    tables["ui_unit_groupings_tables"] = [{"key": "war_beasts", "icon": "war_beasts", "parent_group": "monster_beasts"}, {"key": "lord", "icon": "lord", "parent_group": "commander"},
                                          {"key": "infantry_sword", "icon": "sword", "parent_group": "infantry"}]
    tables["ui_unit_group_parents_tables"] = [{"key": "infantry", "order": "3"}, {"key": "monster_beasts", "order": "7"}, {"key": "campaign_exclusives", "order": "99"}]
    tables["factions_tables"] = [{"key": "wh_dlc05_wef_wood_elves", "subculture": "wh_dlc05_sc_wef_wood_elves"}]
    tables["cultures_subcultures_tables"] = [{"subculture": "wh_dlc05_sc_wef_wood_elves", "culture": "wh_dlc05_wef_wood_elves"}]
    tables.update(extra_tables)
    stats = {"rory_welf_small_wolf": ttc_data.UnitStats("rory_welf_small_wolf", WOLF_MAIN, WOLF_LAND, set())}
    for key, caste, group in (("wef_lord", "lord", "lord"), ("wef_guard", "melee_infantry", "infantry_sword"), ("wef_exclusive", "melee_infantry", "infantry_sword"),
                              ("wef_loose", "melee_infantry", "infantry_sword")):
        stats[key] = unit(key, caste, group)
    loc = {
        "land_units_onscreen_name_rory_welf_small_wolf": "Wolves", "unit_abilities_onscreen_name_howl": "{{tr:howl_text}}", "howl_text": "Howl",
        "cultures_name_wh_dlc05_wef_wood_elves": "Wood Elves", "ui_unit_group_parents_onscreen_name_infantry": "Infantry",
    }
    return catalog.UnitCatalog(stats, loc, tables, ART)


def wood_elf_permissions():
    rows = [("rory_welf_small_wolf", "false"), ("wef_lord", "false"), ("wef_guard", "false"), ("wef_exclusive", "true")]
    return [{"faction": "wh_dlc05_wef_wood_elves", "unit": key, "campaign_exclusive": exclusive} for key, exclusive in rows]


def pick(key, label="special,2", confident=False):
    return {"mod": "Animals", "package": "!!!calm_animals.pack", "key": key, "faction": "Wood Elves", "pick": label, "confident": confident, "confidence": 0.5,
            "runner_up": "special,1", "lookalikes": [["wef_guard", "core,1"]]}


def test_details_match_the_in_game_panel():
    details = make_catalog().details("rory_welf_small_wolf")
    assert details["name"] == "Wolves"
    assert details["stats"] == {
        "hp": 6624, "tier": 1, "men": 48, "armour": 15, "leadership": 55, "speed": 95,
        "melee_attack": 26, "melee_defence": 21, "weapon_strength": 42, "charge_bonus": 38,
    }
    assert [{k: a[k] for k in ("key", "name", "icon")} for a in details["abilities"]] == [{"key": "howl", "name": "Howl", "icon": "ui/battle ui/ability_icons/howl_icon.png"}]
    assert details["abilities"][0]["tip"]["name"] == "Howl"
    assert details["card"] == "ui/units/icons/rory_welf_small_wolf.png" and not details["hp_estimate"]


def test_missile_stats_show_only_for_units_that_shoot():
    # Ungor Raiders: 22 ammunition, 115 range, 12 + 1 missile damage. A cannon's engine weapon adds its explosion.
    cat = make_catalog(
        missile_weapons_tables=[{"key": "ungor_bow", "default_projectile": "ungor_arrow"}, {"key": "cannon", "default_projectile": "cannon_ball"}],
        projectiles_tables=[
            {"key": "ungor_arrow", "damage": "12", "ap_damage": "1", "effective_range": "115"},
            {"key": "cannon_ball", "damage": "88", "ap_damage": "352", "effective_range": "450", "explosion_type": "boom"},
        ],
        projectiles_explosions_tables=[{"key": "boom", "detonation_damage": "10", "detonation_damage_ap": "5"}],
        battlefield_engines_tables=[{"key": "great_cannon", "missile_weapon": "cannon"}],
    )
    assert missile_stats({"primary_missile_weapon": "ungor_bow", "primary_ammo": "22"}, cat.panel) == {"ammunition": 22, "range": 115, "missile_strength": 13}
    assert missile_stats({"engine": "great_cannon", "primary_ammo": "20"}, cat.panel) == {"ammunition": 20, "range": 450, "missile_strength": 455}
    assert missile_stats(WOLF_LAND, cat.panel) == {}
    assert "range" not in cat.details("rory_welf_small_wolf")["stats"]


def test_mounted_units_use_the_mount_speed_and_add_its_hp():
    wolf = make_catalog(mounts_tables=[{"key": "warhorse", "entity": "horse"}])
    wolf.stats["rory_welf_small_wolf"].land = {**WOLF_LAND, "mount": "warhorse", "num_mounts": "48"}
    details = wolf.details("rory_welf_small_wolf")
    assert details["stats"]["speed"] == 80
    assert details["stats"]["hp"] == 6624 + 10 * 48
    assert details["hp_estimate"]


def test_buildings_list_the_lowest_level_of_each_chain_and_skip_rogue_settlements():
    cat = make_catalog(
        building_units_allowed_tables=[
            {"building": "wef_glade_3", "unit": "rory_welf_small_wolf"},
            {"building": "wef_glade_2", "unit": "rory_welf_small_wolf"},
            {"building": "wef_beasts_1", "unit": "rory_welf_small_wolf"},
            {"building": "wh2_main_rogue_settlement_major_2", "unit": "rory_welf_small_wolf"},
        ],
        building_levels_tables=[
            {"level_name": "wef_glade_2", "chain": "wef_glade", "level": "1"},
            {"level_name": "wef_glade_3", "chain": "wef_glade", "level": "2"},
            {"level_name": "wef_beasts_1", "chain": "wef_beasts", "level": "0"},
        ],
        building_culture_variants_tables=[{"building": "wef_glade_2", "icon": "glade"}],
    )
    cat.art["ui/buildings/icons/glade.png"] = "glade.png"
    cat.loc.update({"building_culture_variants_name_wef_glade_2": "Hunting Glade", "building_chains_chain_tooltip_wef_glade": "Glades"})
    # A second chain with the same in-game name merges into one entry, keeping the lowest tier and borrowing the icon.
    cat.building_levels["wef_glade_copy_1"] = {"level_name": "wef_glade_copy_1", "chain": "wef_glade_copy", "level": "3"}
    cat.loc["building_chains_chain_tooltip_wef_glade_copy"] = "Glades"
    cat.unit_buildings["rory_welf_small_wolf"].append("wef_glade_copy_1")
    assert cat.details("rory_welf_small_wolf")["buildings"] == [
        {"name": "", "chain": "wef_beasts", "tier": 1, "icon": "", "script": False},
        {"name": "Hunting Glade", "chain": "Glades", "tier": 2, "icon": "ui/buildings/icons/glade.png", "script": False},
    ]


ANIMAL_SCRIPT = """local tiers = {
    ["wef_pool_01"] = 1,
    ["wef_pool_02"] = 2,
    ["not_a_building"] = 3
};

local tier_01 = {
    {"rory_welf_elk", 2, 20, 2}
};

local tier_02 = {
    {"rory_welf_small_wolf", 2, 15, 2},
    {"rory_welf_elk", 2, 20, 2}
};

local lookup = {
    [1] = tier_01,
    [2] = tier_02
};

cm:add_unit_to_province_mercenary_pool(region, unit[1], pool, unit[2], unit[3], unit[4], 0, "", "", "", false, "")
"""


def test_script_unlocks_map_each_tier_table_to_its_buildings():
    unlocks = catalog.parse_script_unlocks(ANIMAL_SCRIPT, {"wef_pool_01", "wef_pool_02"})
    assert unlocks == {"rory_welf_elk": ["wef_pool_01", "wef_pool_02"], "rory_welf_small_wolf": ["wef_pool_02"]}
    assert catalog.parse_script_unlocks(ANIMAL_SCRIPT.replace("add_unit_to_province_mercenary_pool", "other_call"), {"wef_pool_02"}) == {}


def test_script_buildings_show_in_recruited_from():
    cat = make_catalog(building_levels_tables=[{"level_name": "wef_pool_02", "chain": "wef_pool", "level": "1"}])
    cat.script_buildings = {"rory_welf_small_wolf": ["wef_pool_02"]}
    cat.loc.update({"building_culture_variants_name_wef_pool_02": "Brook", "building_chains_chain_tooltip_wef_pool": "Spring"})
    assert cat.details("rory_welf_small_wolf")["buildings"] == [{"name": "Brook", "chain": "Spring", "tier": 2, "icon": "", "script": True}]


def test_card_falls_back_to_the_variant_card_name():
    cat = make_catalog()
    cat.unit_cards = {"other_unit": "Rory_Welf_Small_Wolf"}
    assert cat.card_path("other_unit") == "ui/units/icons/rory_welf_small_wolf.png"
    assert cat.card_path("no_such_unit") == ""


def test_rosters_follow_the_custom_battle_permissions_and_skip_lords():
    session = catalog.ReviewSession(make_catalog(units_custom_battle_permissions_tables=wood_elf_permissions()), {}, {}, {}, {})
    (culture,) = session.state()["cultures"]
    assert culture["name"] == "Wood Elves"
    assert [(s["key"], s["name"], s["units"]) for s in culture["sections"]] == [
        ("infantry", "Infantry", ["wef_guard"]),
        ("monster_beasts", "monster_beasts", ["rory_welf_small_wolf"]),
        ("campaign_exclusives", "campaign_exclusives", ["wef_exclusive"]),
    ]


def test_cardless_units_are_hidden():
    permissions = wood_elf_permissions() + [{"faction": "wh_dlc05_wef_wood_elves", "unit": "wef_cardless"}]
    cat = make_catalog(units_custom_battle_permissions_tables=permissions)
    cat.stats["wef_cardless"] = unit("wef_cardless", "melee_infantry", "infantry_sword")
    cat.culture_units["wh_dlc05_wef_wood_elves"]["wef_cardless"] = False
    assert "wef_cardless" not in catalog.ReviewSession(cat, {}, {}, {}, {}, {"wef_cardless"}).state()["units"]
    # No cardless set (the card listing failed) hides nothing.
    assert "wef_cardless" in catalog.ReviewSession(cat, {}, {}, {}, {}, None).state()["units"]


def test_auto_picks_without_a_permission_join_their_faction_culture():
    picks = {"wef_loose": pick("wef_loose")}
    session = catalog.ReviewSession(make_catalog(units_custom_battle_permissions_tables=wood_elf_permissions()), {}, picks, {}, {"wef_loose": "Animals"})
    state = session.state()
    infantry = state["cultures"][0]["sections"][0]
    assert infantry["units"] == ["wef_guard", "wef_loose"]
    loose = state["units"]["wef_loose"]
    assert (loose["label"], loose["source"], loose["review"], loose["mod"]) == ("special,2", "auto", True, "Animals")
    assert state["units"]["wef_guard"]["mod"] == ""


def test_auto_picks_in_a_hidden_category_go_under_unsorted():
    cat = make_catalog(units_custom_battle_permissions_tables=wood_elf_permissions() + [{"faction": "wh_dlc05_wef_wood_elves", "unit": "wef_tank"}])
    cat.stats["wef_tank"] = unit("wef_tank", "warmachine", "lord")
    session = catalog.ReviewSession(cat, {}, {"wef_tank": pick("wef_tank")}, {}, {})
    sections = session.state()["cultures"][0]["sections"]
    assert [(s["key"], s["name"], s["units"]) for s in sections[-2:]] == [("unsorted", "Unsorted", ["wef_tank"]), ("campaign_exclusives", "campaign_exclusives", ["wef_exclusive"])]


def test_caps_show_their_source():
    labels = {"wef_guard": ("core,1", "hand")}
    picks = {"rory_welf_small_wolf": pick("rory_welf_small_wolf", confident=True)}
    session = catalog.ReviewSession(make_catalog(units_custom_battle_permissions_tables=wood_elf_permissions()), labels, picks, {}, {})
    assert session.cap("wef_guard") == {"label": "core,1", "source": "hand", "review": False}
    assert session.cap("rory_welf_small_wolf") == {"label": "special,2", "source": "auto", "review": False}
    assert session.cap("wef_exclusive") == {"label": None, "source": None, "review": False}
    assert session.unit("rory_welf_small_wolf")["pick"]["lookalikes"] == [{"key": "wef_guard", "label": "core,1", "name": "wef_guard"}]


def test_save_writes_each_pick_under_its_faction_and_marks_it_hand(tmp_path, monkeypatch):
    monkeypatch.setattr(ttc_compat_io, "HAND_DIR", str(tmp_path))
    picks = {"rory_welf_small_wolf": pick("rory_welf_small_wolf"), "wef_guard": pick("wef_guard", confident=True)}
    session = catalog.ReviewSession(make_catalog(), {}, picks, {}, {})
    files = session.save([{"key": "rory_welf_small_wolf", "category": "special", "weight": 2}, {"key": "wef_guard", "category": "core", "weight": 3}])
    assert files == ["!!!!!!!calm_animals.lua"]
    text = (tmp_path / "!!!!!!!calm_animals.lua").read_text()
    assert '    -- Wood Elves\n    {"rory_welf_small_wolf", "special", 2},\n    {"wef_guard", "core"},' in text
    assert session.cap("wef_guard") == {"label": "core,1", "source": "hand", "review": False}
    assert session.picks == {} and session.saved == 2


def test_saved_and_existing_hand_caps_can_be_edited_again_in_place(tmp_path, monkeypatch):
    monkeypatch.setattr(ttc_compat_io, "HAND_DIR", str(tmp_path))
    existing = tmp_path / "!!!!!!!other.lua"
    existing.write_text('local caps = {\n    -- Wood Elves\n    {"wef_guard", "core"},\n}\n')
    session = catalog.ReviewSession(make_catalog(), {"wef_guard": ("core,1", "hand")}, {"rory_welf_small_wolf": pick("rory_welf_small_wolf")}, {}, {},
                                    hand_entry_paths={"wef_guard": str(existing)})
    session.save([{"key": "rory_welf_small_wolf", "category": "special", "weight": 2}])
    session.save([{"key": "rory_welf_small_wolf", "category": "rare", "weight": 1}, {"key": "wef_guard", "category": "special", "weight": 3}])
    text = (tmp_path / "!!!!!!!calm_animals.lua").read_text()
    assert '{"rory_welf_small_wolf", "rare", 1},' in text and "special" not in text
    assert existing.read_text() == 'local caps = {\n    -- Wood Elves\n    {"wef_guard", "special", 3},\n}\n'
    assert session.cap("wef_guard") == {"label": "special,3", "source": "hand", "review": False}


def test_save_rejects_bad_changes():
    session = catalog.ReviewSession(make_catalog(), {"wef_guard": ("core,1", "hand")}, {"k": pick("k")}, {}, {})
    for change in ({"key": "wef_guard", "category": "core"}, {"key": "k", "category": "epic"}, {"key": "k", "category": "rare", "weight": 0}):
        try:
            session.save([change])
        except ValueError:
            continue
        raise AssertionError(f"accepted {change}")


def test_label_source_names_where_a_cap_came_from():
    assert [catalog.label_source(s) for s in ("vanilla:wh_main_emp", "!!!!!!!mod.lua", "mod:x.pack")] == ["base", "hand", "mod"]
