"""Tests that `walk_land_unit_to_related_tables` ships every row a compat pack needs to load on its own."""

import pytest

import core.pipeline as pipeline
from core.pipeline import DuplicateTracker, TABLE_CONFIGS, add_parent_mod_rows, drop_vanilla_rows, fail_on_broken_links, make_new_data_buckets, walk_land_unit_to_related_tables


def _table_data(**tables):
    """Build a `table_data` mapping with every configured table empty except the ones given.

    Args:
        **tables (dict): Table name -> `key -> row` mapping.

    Returns:
        The mapping.
    """
    data = {cfg["table_name"]: {} for cfg in TABLE_CONFIGS}
    data.update(tables)
    return data


def test_projectile_scaling_damage_is_shipped_with_projectile():
    """A projectile's `scaling_damage` row must come along, or the game rejects the projectile at startup."""
    table_data = _table_data(
        missile_weapons_tables={"sartosa_handgun_ror": {"key": "sartosa_handgun_ror", "default_projectile": "sartosa_rifle_bullet_ror"}},
        projectiles_tables={"sartosa_rifle_bullet_ror": {"key": "sartosa_rifle_bullet_ror", "scaling_damage": "sartosa_rifle_bullet_ror"}},
        projectiles_scaling_damages_tables={"sartosa_rifle_bullet_ror": {"key": "sartosa_rifle_bullet_ror", "max_damage_multiplier": "1.0000"}},
    )
    new_data = make_new_data_buckets("sartosa_unit")

    walk_land_unit_to_related_tables(
        data={"key": "sartosa_unit", "primary_missile_weapon": "sartosa_handgun_ror"},
        main_unit_data={"unit": "sartosa_unit"},
        table_data=table_data,
        tracker=DuplicateTracker(),
        new_data=new_data,
        land_units_by_key={},
        vanilla_keys={},
    )

    assert [row["key"] for row in new_data["projectiles"]] == ["sartosa_rifle_bullet_ror"]
    assert [row["key"] for row in new_data["projectiles_scaling_damages"]] == ["sartosa_rifle_bullet_ror"]


def test_ships_the_land_unit_the_main_unit_references():
    """A main unit whose `land_unit` differs from its own key must ship that land unit, or the game crashes at startup on the dangling reference."""
    shipped_row = {"key": "lsh_nehekwight_knight", "primary_melee_weapon": "knight_sword"}
    table_data = _table_data(melee_weapons_tables={"knight_sword": {"key": "knight_sword"}})
    new_data = make_new_data_buckets("lsh_nehekwight_knight_arkhan")

    walk_land_unit_to_related_tables(
        data={"key": "lsh_nehekwight_knight_arkhan"},
        main_unit_data={"unit": "lsh_nehekwight_knight_arkhan", "land_unit": "lsh_nehekwight_knight"},
        table_data=table_data,
        tracker=DuplicateTracker(),
        new_data=new_data,
        land_units_by_key={"lsh_nehekwight_knight": shipped_row},
        vanilla_keys={},
    )

    assert [row["key"] for row in new_data["land_units"]] == ["lsh_nehekwight_knight"]
    assert [row["key"] for row in new_data["melee_weapons"]] == ["knight_sword"]


def test_mod_versions_of_vanilla_rows_are_not_shipped():
    """A compat is always on, so a mod's edit of a vanilla row would reach players without that mod. Vanilla already has the row, so skip it."""
    table_data = _table_data(
        mounts_tables={"vanilla_horse": {"key": "vanilla_horse", "entity": "mod_only_horse_entity"}},
        battle_entities_tables={"mod_only_horse_entity": {"key": "mod_only_horse_entity"}, "new_rider": {"key": "new_rider"}},
        melee_weapons_tables={"vanilla_sword": {"key": "vanilla_sword"}},
    )
    vanilla_keys = {"land_units_tables": {"vanilla_knights"}, "main_units_tables": {"vanilla_knights"}, "mounts_tables": {"vanilla_horse"}, "melee_weapons_tables": {"vanilla_sword"}}

    # A mod's edit of a vanilla unit ships nothing for the unit itself.
    edited = make_new_data_buckets("vanilla_knights")
    walk_land_unit_to_related_tables(
        data={"key": "vanilla_knights", "mount": "vanilla_horse"},
        main_unit_data={"unit": "vanilla_knights", "land_unit": "vanilla_knights"},
        table_data=table_data,
        tracker=DuplicateTracker(),
        new_data=edited,
        land_units_by_key={},
        vanilla_keys=vanilla_keys,
    )
    assert edited["land_units"] == [] and edited["main_units"] == []

    # A new unit still ships, but not the mod's versions of vanilla rows it uses, or anything only those versions point at.
    new_unit = make_new_data_buckets("mod_knights")
    walk_land_unit_to_related_tables(
        data={"key": "mod_knights", "mount": "vanilla_horse", "primary_melee_weapon": "vanilla_sword", "man_entity": "new_rider"},
        main_unit_data={"unit": "mod_knights", "land_unit": "mod_knights"},
        table_data=table_data,
        tracker=DuplicateTracker(),
        new_data=new_unit,
        land_units_by_key={},
        vanilla_keys=vanilla_keys,
    )
    assert [row["key"] for row in new_unit["land_units"]] == ["mod_knights"]
    assert [row["key"] for row in new_unit["battle_entities"]] == ["new_rider"]
    assert new_unit["mounts"] == [] and new_unit["melee_weapons"] == []


def test_drop_vanilla_rows_keeps_only_mod_keys():
    """Attribute compats ship their own transformed vanilla file, so a mod's copy of a vanilla row is dropped."""
    rows = [{"vortex_key": "vanilla_vortex"}, {"vortex_key": "mod_vortex"}]
    assert drop_vanilla_rows(rows, "battle_vortexs_tables", {"battle_vortexs_tables": {"vanilla_vortex"}}) == [{"vortex_key": "mod_vortex"}]
    assert drop_vanilla_rows([{"key": "mod_display"}], "projectile_displays_tables", {}) == [{"key": "mod_display"}]


def test_ships_the_battle_entity_a_unit_borrows_from_its_parent_mod(monkeypatch):
    """A unit whose `man_entity` lives only in its parent mod must ship that row, or new campaigns crash on the dangling reference."""
    parent_data = _table_data(battle_entities_tables={"jbv_wraith": {"key": "jbv_wraith", "type": "giant"}, "jbv2_nurse": {"key": "jbv2_nurse", "type": "parent"}})
    parent_data["battle_entities_tables_headers"] = ["key", "type"]
    parent_data["battle_entities_tables_version_info"] = "#battle_entities_tables;39;db/battle_entities_tables/parent"
    monkeypatch.setattr(pipeline, "extract_and_load_table_data", lambda *args, **kwargs: parent_data)
    monkeypatch.setattr(pipeline, "cleanup_modded_folders", lambda **kwargs: None)

    table_data = _table_data(battle_entities_tables={"jbv2_nurse": {"key": "jbv2_nurse", "type": "child"}})
    table_data["battle_entities_tables_headers"] = ["type", "key"]
    mod = {"package_name": "jade_vamp_pol_IotM.pack", "path": "child.pack", "parent_mods": ["jade_vamp_pol.pack"]}
    add_parent_mod_rows(mod, [mod, {"package_name": "jade_vamp_pol.pack", "path": "parent.pack"}], table_data, "scratch")

    new_data = make_new_data_buckets("jbv_wraith")
    walk_land_unit_to_related_tables(
        data={"key": "jbv_wraith", "man_entity": "jbv_wraith"},
        main_unit_data={"unit": "jbv_wraith"},
        table_data=table_data,
        tracker=DuplicateTracker(),
        new_data=new_data,
        land_units_by_key={},
        vanilla_keys={},
    )

    assert [row["key"] for row in new_data["battle_entities"]] == ["jbv_wraith"]
    assert table_data["battle_entities_tables"]["jbv2_nurse"]["type"] == "child"


def test_build_stops_on_a_broken_link_but_not_a_tolerated_one(tmp_path):
    """A land unit whose `man_entity` is missing must stop the build. A missing `attribute_group` only warns."""
    folder = tmp_path / "db" / "land_units_tables"
    folder.mkdir(parents=True)
    (folder / "!!!mod.tsv").write_text(
        "key\tman_entity\tattribute_group\n#land_units_tables;54;db/land_units_tables/!!!mod\njbv_wraith\tjbv_wraith\tmissing_group\n", encoding="utf-8"
    )

    with pytest.raises(RuntimeError, match="1 broken link"):
        fail_on_broken_links(str(tmp_path), vanilla_keys={})
    fail_on_broken_links(str(tmp_path), vanilla_keys={"battle_entities_tables": {"jbv_wraith"}})
