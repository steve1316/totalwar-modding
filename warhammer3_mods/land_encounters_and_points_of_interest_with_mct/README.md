# Land Encounters And Points Of Interest + MCT Support

This updated mod takes up the work of the original mod author, `diagonal_zero`.

## A few things to note

- The faction data is generated using the `process_main_units_tables.py` from the helper scripts and is expected to be used to keep it up to date for new/updated mods as needed.
- The regex pattern used to sort each unit into specific factions is generalized as many of these mods do not follow a set pattern in their unit key naming.
- Generally removed support for modded factions being spawned in as invasion forces due to needing to tinker with their `startpos`. Failing to do so will result in their lords and heroes spawning in all messed up and glitchy. Thei individual units however are still collected into the `Random Encounter Force Generation System` to be distributed into vanilla factions spawning in as invasion forces.
- The `process_main_units_tables.py` script will make sure that the vanilla `main_units_tables`, `faction_agent_permitted_subtypes`, `character_skill_node_set_items_tables`, `character_skill_node_sets_tables`, and `character_skill_nodes_tables` TSV files are extracted and available for use before generating the updated faction JSON/Lua data file.
