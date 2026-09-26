"""Roll LEAPOI random armies offline through the mod's real Lua generator, then print samples and check them.

The Lua harness in `leapoi_sim/army_sim.lua` loads the mod's `core/managers.lua` with the game's globals stubbed out, so the armies come from the same
code the game runs. Needs a standalone Lua 5.4 interpreter.

Usage:
    python simulate_leapoi_armies.py --faction wef --difficulty hard --count 10
    python simulate_leapoi_armies.py --count 200 --mods all     Check every faction with every supported mod enabled.
"""

import argparse
import collections
import json
import os
import shutil
import subprocess
from dataclasses import dataclass
from typing import Any, Dict, List, Optional

from process_main_units_tables import LEAPOI_SOURCE_ROOT

SIM_SCRIPT = "./leapoi_sim/army_sim.lua"
SPAWN_SIM_SCRIPT = "./leapoi_sim/spawn_sim.lua"
# Campaign maps in LEAPOI's `configs/coordinates.lua`.
CAMPAIGNS = ["immortal_empires", "realm_of_chaos", "immortal_empires_expanded"]
# Default install location of the standalone Lua interpreter on Windows, used when `lua` is not on PATH.
LUA_FALLBACK_PATH = r"C:\Program Files\Lua\lua.exe"
DIFFICULTIES = "easy,medium,hard"
# Key fragments of vanilla units that should never be in a random army: quest battle, tutorial, prologue and summoned units.
FORBIDDEN_UNIT_PATTERNS = ["_qb", "tutorial", "prologue", "_summon", "_boss"]
# Boss units the culture's base group can really recruit (Norsca's monster hunt rewards), so they are allowed.
ALLOWED_BOSS_UNITS = {"wh_dlc08_nor_mon_frost_wyrm_boss", "wh_dlc08_nor_mon_war_mammoth_boss"}


@dataclass
class SimResult:
    """Output of one simulator run."""

    # Difficulty key to its `tiers` range and `min_units` / `max_units` limits.
    difficulties: Dict[str, Dict[str, Any]]
    # Faction shorthand to land unit key to every tier, category and origin the unit is listed under.
    pools: Dict[str, Dict[str, List[Dict[str, Any]]]]
    # One record per rolled army: faction, difficulty, lord, heroes and units.
    armies: List[Dict[str, Any]]
    # `none` for vanilla units only (the MCT default), or `all` for every supported mod enabled.
    mods: str


def find_lua() -> Optional[str]:
    """Locate the standalone Lua interpreter.

    Returns:
        The interpreter path, or None if Lua is not installed.
    """
    found = shutil.which("lua")
    if found:
        return found
    return LUA_FALLBACK_PATH if os.path.exists(LUA_FALLBACK_PATH) else None


def run_leapoi_script(script: str, options: Dict[str, Any]) -> List[Dict[str, Any]]:
    """Run one of the Lua simulator scripts against the LEAPOI source and parse its JSON lines.

    Args:
        script (str): Path to the Lua script.
        options (Dict[str, Any]): `key=value` options passed to the script.

    Returns:
        One record per output line.

    Raises:
        RuntimeError: If Lua is missing or the script fails.
    """
    lua = find_lua()
    if lua is None:
        raise RuntimeError("Lua is not installed. Install Lua 5.4 or put `lua` on PATH.")
    args = [lua, script, os.path.abspath(LEAPOI_SOURCE_ROOT)] + [f"{key}={value}" for key, value in options.items()]
    completed = subprocess.run(args, capture_output=True, text=True, encoding="utf-8")
    if completed.returncode != 0:
        raise RuntimeError(f"{script} failed: {completed.stderr.strip()}")
    return [json.loads(line) for line in completed.stdout.splitlines()]


def run_simulation(factions: str = "all", difficulties: str = DIFFICULTIES, count: int = 1, seed: int = 1, mods: str = "none") -> SimResult:
    """Roll armies through the mod's generator.

    Args:
        factions (str): `all`, or comma-separated faction shorthands such as `wef,emp`.
        difficulties (str): Comma-separated difficulty keys to roll.
        count (int): Armies per faction and difficulty.
        seed (int): Random seed, so a run can be repeated exactly.
        mods (str): `none` for vanilla units only, or `all` to enable every supported mod.

    Returns:
        The rolled armies with the pools and limits they were drawn from.

    Raises:
        RuntimeError: If Lua is missing or the harness fails.
    """
    options = {"faction": factions, "difficulty": difficulties, "count": count, "seed": seed, "mods": mods}
    difficulty_limits: Dict[str, Dict[str, Any]] = {}
    pools: Dict[str, Dict[str, List[Dict[str, Any]]]] = {}
    armies: List[Dict[str, Any]] = []
    for record in run_leapoi_script(SIM_SCRIPT, options):
        if record["type"] == "config":
            difficulty_limits = record["difficulties"]
        elif record["type"] == "pool":
            pools[record["faction"]] = record["units"]
        else:
            armies.append(record)
    return SimResult(difficulty_limits, pools, armies, mods)


def run_spawn_simulation(campaign: str, percentages: List[float], seed: int = 1) -> List[Dict[str, Any]]:
    """Fill every zone of a campaign like a new campaign does, once per spawn percentage.

    Args:
        campaign (str): A key of `CAMPAIGNS`.
        percentages (List[float]): Values of the MCT spawn percentage slider, e.g. `[0.1, 0.75]`.
        seed (int): Random seed, so a run can be repeated exactly.

    Returns:
        One record per percentage and zone, with the zone's spot count and how many spots became active.
    """
    return run_leapoi_script(SPAWN_SIM_SCRIPT, {"campaign": campaign, "percentage": ",".join(str(p) for p in percentages), "seed": seed})


def widened_tier_range(tiers: List[int]) -> range:
    """Tiers a difficulty may draw from, including the one-tier widening `get_random_units` does when a category is empty.

    Mirrors the `min_tier` / `max_tier` clamp in `collect_units_from_tiers` in LEAPOI's `core/managers.lua`. Easy difficulty never widens above
    tier 2, so it does not cross into tougher tier 3 units.

    Args:
        tiers (List[int]): The difficulty's `tiers` pair, e.g. `[1, 3]`.

    Returns:
        The allowed tiers.
    """
    low = max(tiers[0] - 1, 1)
    high = 2 if tiers[1] == 2 else min(tiers[1] + 1, 5)
    return range(low, high + 1)


def find_problems(result: SimResult) -> Dict[str, List[str]]:
    """Check every rolled army against its faction's pool and its difficulty's limits.

    Args:
        result (SimResult): A simulator run.

    Returns:
        Problem kind to example messages. Empty when every army is valid.
    """
    problems: Dict[str, List[str]] = collections.defaultdict(list)
    for army in result.armies:
        label = f"{army['faction']} {army['difficulty']}"
        limits = result.difficulties[army["difficulty"]]
        allowed_tiers = widened_tier_range(limits["tiers"])
        if not army["lord"]:
            problems["no_lord"].append(label)

        # The lord counts toward the size, like the generator's `count_total_units`.
        size = 1 + len(army["heroes"]) + len(army["units"])
        if size < limits["min_units"]:
            problems["under_min_size"].append(f"{label}: {size} < {limits['min_units']}")
        if size > limits["max_units"]:
            problems["over_max_size"].append(f"{label}: {size} > {limits['max_units']}")

        for unit in army["units"]:
            key = unit["land_unit"]
            entries = result.pools[army["faction"]].get(key)
            if entries is None:
                problems["not_in_pool"].append(f"{label}: {key}")
                continue
            is_vanilla = any(entry["origin"] == "vanilla" for entry in entries)
            if result.mods == "none" and not is_vanilla:
                problems["mod_unit_with_mods_off"].append(f"{label}: {key}")
            if is_vanilla and key not in ALLOWED_BOSS_UNITS and any(pattern in key for pattern in FORBIDDEN_UNIT_PATTERNS):
                problems["forbidden_unit"].append(f"{label}: {key}")
            if not any(entry["tier"] in allowed_tiers for entry in entries):
                problems["outside_tier_range"].append(f"{label}: {key}")
    return dict(problems)


def print_report(result: SimResult, sample: int) -> None:
    """Print sample armies, unit frequencies and any problems.

    Args:
        result (SimResult): A simulator run.
        sample (int): How many armies to print per faction and difficulty.
    """
    by_roll: Dict[tuple, List[Dict[str, Any]]] = collections.defaultdict(list)
    for army in result.armies:
        by_roll[(army["faction"], army["difficulty"])].append(army)

    for (faction, difficulty), armies in by_roll.items():
        print(f"\n=== {faction} {difficulty}: {len(armies)} armies")
        for army in armies[:sample]:
            units = collections.Counter(unit["land_unit"] for unit in army["units"])
            heroes = f" + heroes {', '.join(army['heroes'])}" if army["heroes"] else ""
            print(f"  lord {army['lord']}{heroes}")
            print("    " + ", ".join(f"{count}x {key}" if count > 1 else key for key, count in units.most_common()))
        frequency = collections.Counter(unit["land_unit"] for army in armies for unit in army["units"])
        print(f"  {len(frequency)} distinct units. Most picked: " + ", ".join(f"{key} ({count})" for key, count in frequency.most_common(8)))

    problems = find_problems(result)
    print("\nProblems: none" if not problems else "\nProblems:")
    for kind, messages in problems.items():
        print(f"  {kind}: {len(messages)}, e.g. {messages[:3]}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Roll LEAPOI random armies offline and check them.")
    parser.add_argument("--faction", default="all", help="`all` or comma-separated faction shorthands, e.g. `wef,emp`.")
    parser.add_argument("--difficulty", default=DIFFICULTIES, help="Comma-separated difficulties. Defaults to all three.")
    parser.add_argument("--count", type=int, default=5, help="Armies to roll per faction and difficulty.")
    parser.add_argument("--seed", type=int, default=1, help="Random seed, so a run can be repeated exactly.")
    parser.add_argument("--mods", choices=["none", "all"], default="none", help="`none` uses vanilla units only (the MCT default). `all` enables every supported mod.")
    parser.add_argument("--sample", type=int, default=3, help="Armies to print per faction and difficulty.")
    args = parser.parse_args()
    print_report(run_simulation(args.faction, args.difficulty, args.count, args.seed, args.mods), args.sample)
