"""Placement suggestions for the spot map. The script lays out the facts (a brief per zone, built from the spots, points of interest and
settlements), an LLM picks the places and writes `data/suggestions/<block>.json`, and the page shows them as a layer to accept by click.

Usage:
    cd helper_scripts
    python -m tools.spot_map.suggest brief --campaign ie     # writes _diag/spot_map/brief_ie.md for the LLM to read
    python -m tools.spot_map.suggest check --campaign ie     # checks the campaign's suggestion files against coordinates.lua

Suggestions only stand on existing enabled spots, which are known to be reachable land, so a suggestion never lands in the sea.
"""

import argparse
import json
import logging
import math
import os
import sys
from collections import Counter, defaultdict
from typing import Dict, List

from core.utilities import setup_script_logging
from tools.spot_map import campaigns, coordinates_io

SUGGESTION_DIR = os.path.join(campaigns.DATA_DIR, "suggestions")
#: Spots closer than this on both x and y count as crowding a candidate.
CROWD_RANGE = 30
#: Faction key tokens that are not a LEAPOI culture shorthand but belong to one.
CULTURE_ALIASES = {"teb": "emp"}


def culture_of(faction: str):
    """Reads the LEAPOI culture shorthand out of a faction key, e.g. "wh2_main_def_naggarond" -> "def".

    Args:
        faction (str): A faction key, or "" for an abandoned settlement.

    Returns:
        The shorthand, or None when the key names no known culture (rebels, abandoned, modded factions).
    """
    for token in (faction or "").split("_"):
        token = CULTURE_ALIASES.get(token, token)
        if token in campaigns.CULTURES:
            return token
    return None


def _distance(a: dict, b: dict) -> float:
    """Straight-line distance between two {x, y} points, in logical map units."""
    return math.hypot(a["x"] - b["x"], a["y"] - b["y"])


def campaign_facts(key: str) -> dict:
    """Gathers what the brief and the check need for one campaign.

    Args:
        key (str): A `campaigns.CAMPAIGNS` key.

    Raises:
        ValueError: When the campaign is unknown.

    Returns:
        {"campaign", "spots", "pois", "settlements"}, with spots and points of interest as `campaigns.campaign_entries` builds them.
    """
    campaign = campaigns.CAMPAIGN_BY_KEY.get(key)
    if not campaign:
        raise ValueError(f"unknown campaign {key}")
    entries = campaigns.campaign_entries(campaign, coordinates_io.parse(coordinates_io.read_lines(campaigns.COORDINATES_PATH)[0]))
    return {"campaign": campaign, "spots": entries["spots"], "pois": entries["pois"], "settlements": campaigns.settlements_for(campaign)}


def write_brief(key: str) -> str:
    """Writes the brief an LLM reads to pick places: per zone, its cultures, its points of interest and every enabled spot with its
    surroundings.

    Args:
        key (str): A `campaigns.CAMPAIGNS` key.

    Returns:
        The path of the brief.
    """
    facts = campaign_facts(key)
    campaign, settlements = facts["campaign"], facts["settlements"]
    live = [s for s in facts["spots"] if not s["disabled"]]
    pois_by_zone = defaultdict(list)
    for p in facts["pois"]:
        if not p["disabled"]:
            pois_by_zone[p["zone"]].append(p)
    smithies_by_lua = defaultdict(list)
    for p in facts["pois"]:
        if p["kind"] == "smithies" and not p["disabled"]:
            smithies_by_lua[p["lua"]].append(p)
    # Settlements belong to the zone of their nearest spot, so each zone gets the cultures that live in it.
    zone_of = {s["region"]: min(live, key=lambda o: _distance(o, s))["zone"] for s in settlements} if live else {}
    lines = [f"# Spot brief: {campaign['label']}", "",
             f"Map is {campaign['key']}, logical units, y grows north. {len(live)} enabled spots, {len(settlements)} settlements from the F4 dump.",
             "Spot lines: index {x, y} area | nearest settlement (C = province capital, culture, distance) | cultures of the 3 nearest settlements |",
             f"spots within {CROWD_RANGE} on both axes | distance to the nearest smithy | flags.", ""]
    if not settlements:
        lines += ["No settlements for this campaign yet (press F4 in it with debug_coordinates). Use the area names.", ""]
    for zone in sorted({s["zone"] for s in live}):
        zone_spots = [s for s in live if s["zone"] == zone]
        lua = zone_spots[0]["lua"]
        home = [s for s in settlements if zone_of.get(s["region"]) == zone]
        lines += [f"## {zone} (M.{lua}, {len(zone_spots)} spots)"]
        if home:
            cultures = Counter(culture_of(s["owner"]) or "none" for s in home)
            lines += [f"Settlements: {len(home)}. Cultures: " + ", ".join(f"{c} {n}" for c, n in cultures.most_common()) + ".",
                      "Capitals: " + (", ".join(s["name"] for s in home if s["capital"]) or "none") + "."]
        by_kind = defaultdict(list)
        for p in pois_by_zone[zone]:
            by_kind[p["kind"]].append(p)
        for kind in sorted(by_kind):
            lines += [f"{kind.capitalize()}: " + "; ".join(f"{{{p['x']}, {p['y']}}} {p['fields'].get('culture') or ''}".strip() for p in by_kind[kind]) + "."]
        smithies = smithies_by_lua[lua]
        for s in zone_spots:
            parts = [f"{s['index']} {{{s['x']}, {s['y']}}} {s['area'] or '-'}"]
            if settlements:
                near = sorted(settlements, key=lambda n: _distance(n, s))[:3]
                first = near[0]
                parts.append(f"{first['name']}{' C' if first['capital'] else ''} {culture_of(first['owner']) or 'none'} {_distance(first, s):.0f}")
                parts.append("/".join(sorted({culture_of(n["owner"]) or "none" for n in near})))
            crowd = sum(1 for o in live if o is not s and abs(o["x"] - s["x"]) < CROWD_RANGE and abs(o["y"] - s["y"]) < CROWD_RANGE)
            parts.append(f"crowd {crowd}")
            if smithies:
                parts.append(f"smithy {min(_distance(p, s) for p in smithies):.0f}")
            if s["flags"]:
                parts.append(",".join(s["flags"]))
            lines.append("- " + " | ".join(parts))
        lines.append("")
    os.makedirs(campaigns.CACHE_DIR, exist_ok=True)
    path = os.path.join(campaigns.CACHE_DIR, f"brief_{key}.md")
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
    return path


def load(campaign: dict) -> List[dict]:
    """Loads the suggestions of every coordinates.lua block a campaign draws, so IE Expanded shows IE's next to its own.

    Args:
        campaign (dict): One `campaigns.CAMPAIGNS` entry.

    Returns:
        The suggestions in block order, empty when there are none.
    """
    out = []
    for lua in campaign["lua"]:
        path = os.path.join(SUGGESTION_DIR, f"{lua}.json")
        if os.path.isfile(path):
            out += json.load(open(path, encoding="utf-8"))["suggestions"]
    return out


def check(suggestions: List[dict], spots: List[dict], pois: List[dict]) -> List[dict]:
    """Checks suggestions against coordinates.lua and fills in where each one stands. A suggestion names the spot it takes over by its
    "lua", "zone" and "spot" index; it gets that spot's x, y and area. It is "placed" once an entry of its type stands on those coordinates
    (after an export), and gets a "problem" when the spot is missing, disabled without being placed, or named twice.

    Args:
        suggestions (List[dict]): Entries as {"type", "lua", "zone", "spot", "fields", "reason"}.
        spots (List[dict]): The campaign's spots, as `campaigns.campaign_entries` builds them.
        pois (List[dict]): The campaign's points of interest, likewise.

    Returns:
        The suggestions, each with "id", "x", "y", "area", "placed" and "problem" (None when it is fine).
    """
    by_ref = {(s["lua"], s["zone"], s["index"]): s for s in spots}
    # Where each type already stands: (type, lua, x, y). Plain spots stand everywhere, so they never count as placed.
    standing = {(campaigns.type_of_list(p["kind"]), p["lua"], p["x"], p["y"]) for p in pois if not p["disabled"]}
    standing |= {(campaigns.type_of_spot(s["flags"]), s["lua"], s["x"], s["y"]) for s in spots if not s["disabled"] and s["flags"]}
    taken: Dict[tuple, int] = {}
    out = []
    for i, sug in enumerate(suggestions):
        ref = (sug.get("lua"), sug.get("zone"), sug.get("spot"))
        spot = by_ref.get(ref)
        culture = (sug.get("fields") or {}).get("culture")
        placed = bool(spot) and sug.get("type") != "spot" and (sug.get("type"), spot["lua"], spot["x"], spot["y"]) in standing
        problem = None
        if sug.get("type") not in campaigns.TYPE_BY_KEY:
            problem = f"unknown type {sug.get('type')}"
        elif spot is None:
            problem = f"no spot {sug.get('zone')} {sug.get('spot')} in M.{sug.get('lua')}"
        elif spot["disabled"] and not placed:
            problem = f"spot {spot['zone']} {spot['index']} is disabled"
        elif culture and culture not in campaigns.CULTURES:
            problem = f"unknown culture {culture}"
        elif ref in taken:
            problem = f"spot {spot['zone']} {spot['index']} is also suggestion {taken[ref] + 1}"
        taken.setdefault(ref, i)
        where = {k: spot[k] for k in ("x", "y", "area")} if spot else {"x": None, "y": None, "area": ""}
        out.append({**sug, **where, "id": i, "placed": placed, "problem": problem})
    return out


def main() -> int:
    """Runs the brief or check command.

    Returns:
        int: Process exit code, 1 when a check finds problems.
    """
    setup_script_logging()
    parser = argparse.ArgumentParser(description="Spot map placement suggestions")
    parser.add_argument("command", choices=["brief", "check"])
    parser.add_argument("--campaign", required=True, choices=list(campaigns.CAMPAIGN_BY_KEY))
    args = parser.parse_args()
    if args.command == "brief":
        logging.info(f"Wrote {write_brief(args.campaign)}")
        return 0
    facts = campaign_facts(args.campaign)
    checked = check(load(facts["campaign"]), facts["spots"], facts["pois"])
    for sug in checked:
        if sug["problem"]:
            logging.error(f"Suggestion {sug['id'] + 1} ({sug.get('type')} in {sug.get('zone')}): {sug['problem']}")
    counts = Counter(s.get("type") for s in checked if not s["problem"])
    logging.info(f"{len(checked)} suggestions, {sum(counts.values())} fine ({sum(s['placed'] for s in checked)} placed already): {dict(counts)}")
    return 1 if any(s["problem"] for s in checked) else 0


if __name__ == "__main__":
    sys.exit(main())
