# Land Encounters And Points Of Interest + MCT Support

This updated mod takes up the work of the original mod author, `diagonal_zero`.

## A few things to note

- The faction data is generated using `helper_scripts/generators/process_main_units_tables.py` and is expected to be used to keep it up to date for new/updated mods as needed.
- The regex pattern used to sort each unit into specific factions is generalized as many of these mods do not follow a set pattern in their unit key naming.
- Generally removed support for modded factions being spawned in as invasion forces due to needing to tinker with their `startpos`. Failing to do so will result in their lords and heroes spawning in all messed up and glitchy. Their individual units however are still collected into the `Random Encounter Force Generation System` to be distributed into vanilla factions spawning in as invasion forces.
- The `process_main_units_tables.py` script will make sure that the vanilla `main_units_tables`, `faction_agent_permitted_subtypes`, `character_skill_node_set_items_tables`, `character_skill_node_sets_tables`, and `character_skill_nodes_tables` TSV files are extracted and available for use before generating the updated faction JSON/Lua data file.

## Generated rows

Many db and loc rows, plus `script/land_encounters/configs/army_spells.lua` and `configs/victory_gold.lua`, are written by the LEAPOI generators in `helper_scripts/generators/`. Edit the generator or the Lua config it reads, not the generated rows.

- `update_leapoi_spot_offers.py`: the main one. It writes the spot offers, choice lines, notices and bundles, and pulls in the rest below.
- `leapoi_tower_offer_text.py`: tower offer text and bundles that change with difficulty.
- `leapoi_battle_modifiers.py`: battle modifier text and bundles.
- `leapoi_boons.py`: boon and curse bundles, lines, incidents and dilemmas.
- `leapoi_effect_library.py`: custom effects and the trial bundles.
- `leapoi_army_spells.py` and `leapoi_free_spells.py`: the army spell pools and the free lore spell copies.
- `leapoi_stat_icons.py`: stat icons in front of stat names in dilemma lines.

To regenerate, run this from `helper_scripts/`. It writes all of the above in one go, and `--dry-run` shows what would change.

```
python -u -m generators.update_leapoi_spot_offers
```

Engine lessons from building the mod are in `RESEARCH_NOTES.md` in this folder.
