"""Writes the Advisor Overhaul's in-game test rows for the skills plan, kept apart from the generator so they come out cleanly afterwards.

Four questions, each logged by `script/campaign/mod/advisor_overhaul_spike.lua`:
- S1: does an effect bundle put on him by script give a spell, a personal stat and an army stat, and come off again? The bundle is on while he
  holds the Greatsword, the way weapon arts will work.
- S2: can a wizard use hero actions only champions have, through a wizard copy of the action record and a new enable effect?
- S3: does a skill added by script (no point spent) open a visible node that needs it?
- S4: does adding the Disc's unlock skill by script make the Disc pickable in Change Loadout? It also puts +10 Tzeentch corruption on him.
- S5: does a skill added by script lock a visible node through `character_skill_nodes_skill_locks`? The pact skill should lock "Test: Defiance".

Every key starts with `advisor_overhaul_spike_`, and every file is named `advisor_overhaul_spike`.

Usage (from helper_scripts):
    python -m generators.advisor_overhaul_spike            # write the test rows
    python -m generators.advisor_overhaul_spike --remove   # take them out again
"""

import argparse
import glob
import os
import shutil
from typing import Dict, List

from core.utilities import load_tsv_data
from generators.advisor_overhaul import MOD, NODE_SET, check_node_slots, read_vanilla

# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Settings

# Prefix of every key, and the name of every file.
PREFIX = "advisor_overhaul_spike"

# S1: the bundle he wears while holding the Greatsword. A Lore of Death spell, his own melee attack and his army's melee attack.
ART_BUNDLE = f"{PREFIX}_art_greatsword"
ART_EFFECTS = [("wh_main_effect_ability_enable_spirit_leech", "character_to_character_own", 1), ("wh_main_effect_character_stat_melee_attack", "character_to_character_own", 20),
               ("wh_main_effect_force_stat_melee_attack", "character_to_force_own", 10)]

# S2: champion actions copied for wizards. Their own attribute, zeal, becomes the wizard's authority.
COPIED_ACTIONS = ["wh2_main_agent_action_champion_passive_stimulate_growth", "wh2_main_agent_action_champion_assist_army_scavenge"]

# S2 and S3: the hidden skill that enables the copied actions, and the hidden pact skill the script adds.
ACTIONS_SKILL = f"{PREFIX}_actions"
PACT_SKILL = f"{PREFIX}_pact"

# S3: a visible node on row 5 that needs the hidden pact skill.
GIFT_SKILL = f"{PREFIX}_gift"

# S5: a visible node on row 5 that the hidden pact skill locks.
DEFY_SKILL = f"{PREFIX}_defy"

# S4: the pact's corruption, on him.
PACT_BUNDLE = f"{PREFIX}_pact"
PACT_EFFECTS = [("wh3_main_effect_corruption_tzeentch_characters", "character_to_province_any", 10)]

# Rows of hidden nodes, below the visible ones (vanilla puts its hidden dummies on 8 and 99).
HIDDEN_ROW = 8


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Rows


def skill(key: str, row: int, tier: int, visible: bool, rows: Dict[str, List[Dict[str, str]]], effects: List = ()) -> None:
    """Adds one skill, its node in his tree and its one level with its effects.

    Args:
        key (str): The skill key. Its node is `<key>_node`.
        row (int): The node's row (indent).
        tier (int): The node's place in the row.
        visible (bool): Whether the tree shows it.
        rows (Dict[str, List[Dict[str, str]]]): Rows by table, added to.
        effects (List): (effect, scope, value) each.
    """
    rows["character_skills_tables"].append({"key": key, "image_path": "item_weapon.png", "unlocked_at_rank": "1", "is_background_skill": "false",
                                            "is_female_only_background_skill": "false", "is_male_only_background_skill": "false",
                                            "background_weighting": "0.0000", "influence_cost": "0"})
    rows["character_skill_nodes_tables"].append({"key": f"{key}_node", "character_skill_key": key, "indent": str(row), "tier": str(tier), "points_on_creation": "0",
                                                 "required_num_parents": "0", "visible_in_ui": "true" if visible else "false"})
    rows["character_skill_node_set_items_tables"].append({"set": NODE_SET, "item": f"{key}_node", "mod_disabled": "false"})
    rows["character_skill_level_details_tables"].append({"campaign_key": "", "faction_key": "", "level": "1", "skill_key": key, "subculture_key": "", "image_path": "x",
                                                         "unlocked_at_rank": "1"})
    for effect, scope, value in effects:
        rows["character_skill_level_to_effects_junctions_tables"].append({"character_skill_key": key, "effect_key": effect, "level": "1", "effect_scope": scope,
                                                                          "value": f"{value:.4f}"})


def bundle(key: str, title: str, effects: List, rows: Dict[str, List[Dict[str, str]]]) -> None:
    """Adds one effect bundle for a character, and its effects.

    Args:
        key (str): The bundle key.
        title (str): Its title.
        effects (List): (effect, scope, value) each.
        rows (Dict[str, List[Dict[str, str]]]): Rows by table, added to.
    """
    rows["effect_bundles_tables"].append({"key": key, "localised_description": "", "localised_title": title, "bundle_target": "character", "priority": "1",
                                          "ui_icon": "public_order.png", "is_global_effect": "true", "show_in_3d_space": "false", "owner_only": "true"})
    for effect, scope, value in effects:
        rows["effect_bundles_to_effects_junctions_tables"].append({"effect_bundle_key": key, "effect_key": effect, "effect_scope": scope, "value": f"{value:.4f}",
                                                                   "advancement_stage": "start_turn_completed"})


def build_rows() -> Dict[str, List[Dict[str, str]]]:
    """Every test row, by table.

    Returns:
        Dict[str, List[Dict[str, str]]]: Rows by table.

    Raises:
        SystemExit: When a vanilla row or effect the test copies is missing.
    """
    rows: Dict[str, List[Dict[str, str]]] = {t: [] for t in (
        "character_skills_tables", "character_skill_nodes_tables", "character_skill_node_set_items_tables", "character_skill_level_details_tables",
        "character_skill_level_to_effects_junctions_tables", "character_skill_node_links_tables", "character_skill_nodes_skill_locks_tables", "effect_bundles_tables",
        "effect_bundles_to_effects_junctions_tables", "effects_tables", "agent_actions_tables", "effect_bonus_value_agent_action_record_junctions_tables")}
    effects = {r["effect"]: r for r in read_vanilla("effects_tables")[0]}
    for effect, _, _ in ART_EFFECTS + PACT_EFFECTS:
        if effect not in effects:
            raise SystemExit(f"unknown effect {effect}")
    bundle(ART_BUNDLE, "Test: Greatsword art", ART_EFFECTS, rows)
    bundle(PACT_BUNDLE, "Test: Tzeentch pact", PACT_EFFECTS, rows)

    # S2: each champion action copied for wizards, with its own enable effect, which the hidden actions skill gives.
    actions = {r["unique_id"]: r for r in read_vanilla("agent_actions_tables")[0]}
    links = read_vanilla("effect_bonus_value_agent_action_record_junctions_tables")[0]
    enables = []
    for source in COPIED_ACTIONS:
        if source not in actions:
            raise SystemExit(f"unknown action {source}")
        copy_key = f"{PREFIX}_" + source.split("_agent_action_champion_")[1]
        enable = f"{PREFIX}_effect_enable_" + source.split("_agent_action_champion_")[1]
        row = dict(actions[source], unique_id=copy_key, agent="wizard")
        row.update({column: "authority" for column in ("attribute", "target_attribute") if row[column] == "zeal"})
        rows["agent_actions_tables"].append(row)
        rows["effects_tables"].append({"effect": enable, "icon": "", "priority": "0", "icon_negative": "", "category": "campaign", "is_positive_value_good": "true"})
        rows["effect_bonus_value_agent_action_record_junctions_tables"].append({"bonus_value_id": "active", "effect": enable, "agent_action_record": copy_key})
        # Every other bonus value (cost, success chance) the champion action has, the copy gets too.
        rows["effect_bonus_value_agent_action_record_junctions_tables"] += [dict(r, agent_action_record=copy_key) for r in links
                                                                             if r["agent_action_record"] == source and r["bonus_value_id"] != "active"]
        enables.append((enable, "character_to_character_own", 1))

    # Tier 0 of the hidden row holds his vanilla actions skill. Two nodes in one slot drops one of them.
    skill(ACTIONS_SKILL, HIDDEN_ROW, 2, False, rows, enables)
    skill(PACT_SKILL, HIDDEN_ROW, 1, False, rows)
    skill(GIFT_SKILL, 5, 0, True, rows, [("wh_main_effect_character_stat_melee_defence", "character_to_character_own", 10)])
    rows["character_skill_node_links_tables"].append({"child_key": f"{GIFT_SKILL}_node", "parent_key": f"{PACT_SKILL}_node", "initial_descent_tiers": "0",
                                                      "parent_link_position": "1", "child_link_position": "1", "parent_link_position_offset": "0.0000",
                                                      "child_link_position_offset": "0.0000", "link_type": "REQUIRED"})
    skill(DEFY_SKILL, 5, 1, True, rows, [("wh_main_effect_character_stat_melee_attack", "character_to_character_own", 10)])
    rows["character_skill_nodes_skill_locks_tables"].append({"character_skill": PACT_SKILL, "character_skill_node": f"{DEFY_SKILL}_node", "level": "1"})
    return rows


def texts() -> List[List[str]]:
    """The test rows' loc texts.

    Returns:
        List[List[str]]: [key, text] each.
    """
    out = [[f"effect_bundles_localised_title_{ART_BUNDLE}", "Test: Greatsword art"], [f"effect_bundles_localised_title_{PACT_BUNDLE}", "Test: Tzeentch pact"],
           [f"character_skills_localised_name_{ACTIONS_SKILL}", "Test: champion actions"], [f"character_skills_localised_name_{PACT_SKILL}", "Test: pact"],
           [f"character_skills_localised_name_{GIFT_SKILL}", "Test: Gift of Change"],
           [f"character_skills_localised_description_{GIFT_SKILL}", "Test node. It opens only once the script has added the hidden pact skill."],
           [f"character_skills_localised_name_{DEFY_SKILL}", "Test: Defiance"],
           [f"character_skills_localised_description_{DEFY_SKILL}", "Test node. It locks once the script has added the hidden pact skill."]]
    # The action name and description are keyed by the action record, so each copy needs its own.
    names = {"passive_stimulate_growth": "Test: Stimulate Growth", "assist_army_scavenge": "Test: Scavenge"}
    for source in COPIED_ACTIONS:
        name = source.split("_agent_action_champion_")[1]
        out.append([f"effects_description_{PREFIX}_effect_enable_{name}", "Test: enables a champion action for the Advisor"])
        out.append([f"agent_actions_localised_action_name_{PREFIX}_{name}", names[name]])
        out.append([f"agent_actions_localised_action_description_{PREFIX}_{name}", f"{names[name]}, a champion action copied for the Advisor."])
    return out


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Files


def write(rows: Dict[str, List[Dict[str, str]]]) -> None:
    """Writes each table's test file and the loc file.

    Args:
        rows (Dict[str, List[Dict[str, str]]]): Rows by table.
    """
    for table, table_rows in rows.items():
        _, header, version = read_vanilla(table)
        folder = os.path.join(MOD, "db", table)
        os.makedirs(folder, exist_ok=True)
        lines = ["\t".join(header), "\t".join([f"#{table};{version.split(chr(9))[0].split(';')[1]};db/{table}/{PREFIX}"] + [""] * (len(header) - 1))]
        lines += ["\t".join(row.get(column, "") for column in header) for row in table_rows]
        with open(os.path.join(folder, f"{PREFIX}.tsv"), "w", encoding="utf-8", newline="\n") as f:
            f.write("\n".join(lines) + "\n")
        print(f"wrote {len(table_rows)} rows to db/{table}/{PREFIX}.tsv")
    with open(os.path.join(MOD, "text", "db", f"{PREFIX}.loc.tsv"), "w", encoding="utf-8", newline="\n") as f:
        f.write(f"key\ttext\ttooltip\n#Loc;1;text/db/{PREFIX}.loc\t\t\n" + "".join(f"{key}\t{text}\ttrue\n" for key, text in texts()))


def remove() -> None:
    """Deletes every test file, and each table folder it leaves empty."""
    for path in glob.glob(os.path.join(MOD, "db", "*", f"{PREFIX}.tsv")) + [os.path.join(MOD, "text", "db", f"{PREFIX}.loc.tsv")]:
        if os.path.exists(path):
            os.remove(path)
            print(f"removed {os.path.relpath(path, MOD)}")
            if os.path.basename(os.path.dirname(path)) != "db" and not os.listdir(os.path.dirname(path)):
                shutil.rmtree(os.path.dirname(path))


def main() -> int:
    """Writes or removes the test rows.

    Returns:
        int: Process exit code.
    """
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--remove", action="store_true", help="take the test rows out")
    if parser.parse_args().remove:
        remove()
    else:
        rows = build_rows()
        # The test nodes share his tree with the generator's nodes, so no slot may repeat across both.
        check_node_slots(load_tsv_data(os.path.join(MOD, "db", "character_skill_nodes_tables", "advisor_overhaul.tsv"))[0] + rows["character_skill_nodes_tables"])
        write(rows)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
