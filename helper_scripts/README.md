# Total War: Warhammer 3 Modding Tools

This repository contains a suite of tools designed to assist me in creating and maintaining my mods for Total War: Warhammer 3. These scripts mainly focus on automating my workflows.

## Important Notes

- **rpfm_cli**: Ensure that `rpfm_cli.exe` from https://github.com/Frodo45127/rpfm is located in the same directory as the scripts. This tool is used for schema updates and data extraction.
- **schemas**: Ensure that the `schemas` are downloaded from https://github.com/Frodo45127/rpfm-schemas and placed in a `/schemas` folder in the same directory as the scripts and `rpfm_cli.exe`.
- **temp folder**: All transient scratch (vanilla extractions, per-mod modded extractions, compat-pack build dirs) is written under `helper_scripts/temp/` and gitignored. Each script calls `ensure_temp_dir()` on startup so the folder exists.
- **Parallelism**: Most of the `update_*.py` and `process_main_units_tables.py` scripts accept a `--workers N` flag (defaults to `min(8, os.cpu_count())`); use `--workers 1` for sequential debugging or byte-equivalence diffs.
- **Pre-extracted TSVs**: `check_new_rows.py` and `correct_quotation_marks.py` are dev-utility scripts that read TSVs you place in the script's working directory yourself; the other scripts fetch tables via `rpfm_cli` automatically.

## Scripts Overview

### `update.py` (orchestrator)
Runs `process_main_units_tables.py`, then `update_dynamic_rors.py --reset`, `update_modified_attribute_mods.py --reset`, and `update_double_unit_size.py --reset` in sequence. Forwards an optional `--workers N` flag to each subscript.

### `update_dynamic_rors.py`
Builds Nanu's Dynamic RoR Compatibility Megapack (`!!!!!!!_nanu_dynamic_rors_compat.pack`). For each mod in `SUPPORTED_MODS`, walks the foreign-key chain starting from `land_units_tables` across the 22 tables in `pipeline.TABLE_CONFIGS` (mounts, weapons, projectiles, animations, attributes, etc.), assigns Nanu's RoR effects per unit category/faction, and writes a trimmed standalone compat pack. The `--vanilla` mode instead emits the "leftover vanilla" pack (`!!!!!!!_nanu_dynamic_rors_leftover_vanilla.pack`) by reading vanilla `unit_purchasable_effect_sets_tables`, `mounts_tables`, `main_units_tables`, `land_units_tables`, and `units_to_groupings_military_permissions_tables`.

### `update_double_unit_size.py`
Builds the 2x unit size compat pack (`!!!!!!!2xunitsize_compat.pack`). Doubles `num_men`/`num_mounts`/`rank_depth`/`bonus_hit_points` across vanilla and modded units, plus tweaks `_kv_rules_tables`, `_kv_unit_ability_scaling_rules_tables`, `battle_currency_army_special_abilities_cost_values_tables`, `special_ability_phases_tables`, `unit_size_global_scalings_tables`, and `unit_stat_to_size_scaling_values_tables` to keep the math consistent. Reads the same 22-table FK chain as `update_dynamic_rors.py` for each supported mod.

### `update_modified_attribute_mods.py`
Builds the three "modified attribute" compat packs in one run:
- `!!!!!!!50meleeattackspeed_compat.pack` halves `melee_weapons_tables.melee_attack_interval` (also reads `projectiles_scaling_damages_tables`).
- `!!!!!!!firing_arc_120_compat.pack` raises `battle_entities_tables.fire_arc_close` to 120 if it sits between 0 and 120.
- `!!!!!!!double_projectile_velocity_compat.pack` doubles `projectiles_tables.muzzle_velocity` for positive values (also reads `battle_vortexs_tables`, `projectile_shot_type_displays_tables`, `projectiles_scaling_damages_tables`).

Processes vanilla `db.pack` plus every mod in `SUPPORTED_MODS` whose `modified_attributes` field includes `melee`, `ranged_arc`, or `velocity`.

### `process_main_units_tables.py`
Generates `factions_data.lua` and `factions_data.json` for the Land Encounters and Points of Interest mod. Reads vanilla and modded `main_units_tables`, `faction_agent_permitted_subtypes_tables`, `character_skill_node_set_items_tables`, `character_skill_node_sets_tables`, and `character_skill_nodes_tables` for every supported mod, classifies each unit into a faction/tier/caste, and writes the Lua file straight into the Land Encounters mod folder under `../warhammer3_mods/`, then injects it back into the Workshop `.pack`.

### `update_dynamic_ror_effects.py`
Codegen helper. Extracts `unit_purchasable_effects_tables` from Nanu's parent pack (Steam ID `3278112051`), diffs the keys against `SUPPORTED_EFFECTS` in `dynamic_rors_effects.py`, categorizes any new ones via regex pattern matching, and rewrites `dynamic_rors_effects.py` in place to add them. Also reshuffles entries currently in `misc` if they can now be properly classified. Re-run whenever the parent mod adds new effect bundles. Not part of `update.py`.

### `update_supported_mods_list.py`
Codegen helper. Walks `SUPPORTED_MODS` and generates Steam Workshop BBCode-formatted lists, one per pack (melee, ranged_arc, velocity, dynamic_rors, land_encounters). The user pastes the output into each pack's Steam Workshop description. Reads only `SUPPORTED_MODS`; touches no tables. Not part of `update.py`.

### `glf_inner_join.py`
Patches the GLF Unit Expansion mod's `land_units_tables` by inner-joining its rows against vanilla `land_units_tables` (from `data/db.pack`), then overriding `man_animation`, `primary_missile_weapon`, `primary_ammo`, and `ai_usage_group` on each row with the GLF mod's values. Extracts both sides via `rpfm_cli`, merges in-memory, and writes the result back into the GLF `.pack`. Defaults to `!!!1a_glf_unit_expansion.pack`; pass `--pack <package_name>` to target a different mod from `SUPPORTED_MODS`.

### `check_translations.py`
Validates English translation packs against their original-language source packs. Reads the localization `text/db/` tables from a hardcoded list of `(mod_path, translation_path)` pairs at the top of the file, then reports missing keys, placeholder strings (`???`), and inconsistencies. Manual setup required: edit the list to point at the pack pairs you want to audit. Not used by any orchestrator.

### `check_new_rows.py`
Dev utility. Reads `./original.tsv` and `./modded.tsv` (any table, only the `key` column is inspected) and prints keys present in the original but missing in the modded one. You extract the two TSVs yourself before running; nothing automated.

### `correct_quotation_marks.py`
Dev utility for localization cleanup. Reads `./original.tsv` (source-language reference) and `./modded.tsv` (translation), removes redundant nested quotation marks, converts Chinese `『』` to Western `""` when the original uses them, strips spurious Western quotes elsewhere, and writes the result to `./corrected.tsv`. You extract the two TSVs yourself before running.

### `pipeline.py`
Shared module used by `update_dynamic_rors.py` and `update_double_unit_size.py`. Owns `TABLE_CONFIGS` (the 22-table FK walker config), `DuplicateTracker` (cross-mod dedup of `(table, primary_key)` pairs), `extract_and_load_table_data` (per-mod table extraction + load), `walk_land_unit_to_related_tables` (the FK walker), and the rpfm_cli wrappers `reset_pack_folders` / `add_folder_to_pack` / `extract_variantmeshes_folder`.

### `utilities.py`
Generic TSV/RPFM/schema helpers shared across every script. Exposes `TEMP_DIR`, `extract_tsv_data` (vanilla extraction), `extract_modded_tsv_data` (modded extraction), `load_tsv_data` / `load_multiple_tsv_data`, schema-version migration via `update_single_tsv_file_to_latest_version`, and the `_SCHEMA_CACHE` (lock-guarded for thread-safe access).

### `supported_mods.py`
Registry. A single module-level list `SUPPORTED_MODS` of ~166 dict entries with `name`, `package_name`, `path`, `modified_attributes`, and optional `pattern_overrides` / `character_overrides` / `ignore_generation`. Pure data, no logic.

### `dynamic_rors_effects.py`
Catalog. A single module-level dict `SUPPORTED_EFFECTS` mapping ~30 categories to lists of `nanu_dynamic_ror_*` effect-bundle keys (~7,000 effects total). Consumed by `update_dynamic_rors.py`'s `process_unit_by_category` function. Edited by hand or via `update_dynamic_ror_effects.py`.
