"""Tests that `walk_land_unit_to_related_tables` ships every row a compat pack needs to load on its own."""

from core.pipeline import DuplicateTracker, TABLE_CONFIGS, make_new_data_buckets, walk_land_unit_to_related_tables


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
    )

    assert [row["key"] for row in new_data["projectiles"]] == ["sartosa_rifle_bullet_ror"]
    assert [row["key"] for row in new_data["projectiles_scaling_damages"]] == ["sartosa_rifle_bullet_ror"]
