"""Add a downloaded Steam Workshop mod to `SUPPORTED_MODS` from its link.

Guesses every registry field from the mod's pack, asks only when a guess is uncertain, and always asks before writing.

Usage:
    cd helper_scripts && python -m tools.add_supported_mod https://steamcommunity.com/sharedfiles/filedetails/?id=3565085095
"""

import re
import urllib.parse
from dataclasses import dataclass
from typing import Dict, List, Optional, Set, Tuple

from generators.process_main_units_tables import faction_keys
from ttc.ttc_data import FACTION_NAMES, unit_faction

# Table whose presence in a pack turns on each modified attribute, in registry order.
ATTRIBUTE_TABLES = {"melee": "melee_weapons_tables", "ranged_arc": "battle_entities_tables", "velocity": "projectiles_tables"}
# Faction codes the LEAPOI generator recognizes, in the order it checks them.
FACTION_CODES = [code for faction in faction_keys for code in faction]
# Faction name from `unit_faction` back to its code. The first code listed for a name wins, so `wef` beats `welf`.
NAME_TO_CODE = {name: code for code, name in reversed(list(FACTION_NAMES.items()))}
# Trailing `_<digits>` on a land unit key, which marks its mount variants.
VARIANT_SUFFIX = re.compile(r"_\d+$")
# Castes the LEAPOI generator reads lord and hero overrides for.
CHARACTER_CASTES = ("lord", "hero")


@dataclass
class FactionGuess:
    """The faction guess for a mod's units."""

    # The `pattern_overrides` to write, or None when the guess is uncertain.
    overrides: Optional[Dict[str, str]]
    # Faction code to the land units it covers.
    by_code: Dict[str, List[str]]
    # Land units no faction could be found for.
    unknown: List[str]


@dataclass
class Candidate:
    """A lord or hero unit that could go into `character_overrides`."""

    # `lord` or `hero`.
    caste: str
    # Land unit key.
    land_unit: str
    # Agent subtype the unit belongs to.
    agent_subtype: str


def parse_workshop_id(link: str) -> str:
    """Pull the Workshop ID out of a Steam Workshop link or a bare ID.

    Args:
        link (str): A `...filedetails/?id=NNN` link or the bare number.

    Raises:
        ValueError: No numeric `id` was found.

    Returns:
        The Workshop ID.
    """
    text = link.strip()
    if text.isdigit():
        return text
    ids = urllib.parse.parse_qs(urllib.parse.urlparse(text).query).get("id", [])
    if len(ids) == 1 and ids[0].isdigit():
        return ids[0]
    raise ValueError(f"Could not find a Workshop ID in `{link}`.")


def guess_attributes(tables: Set[str]) -> List[str]:
    """Pick the modified attributes a pack can take part in from the tables it has.

    Args:
        tables (Set[str]): The pack's db table names, e.g. `melee_weapons_tables`.

    Returns:
        The attributes in registry order.
    """
    return [attribute for attribute, table in ATTRIBUTE_TABLES.items() if table in tables]


def match_factions(land_unit: str, pattern_overrides: Dict[str, str]) -> List[str]:
    """Find the faction codes the LEAPOI generator would give a land unit, following `tsv_to_faction_data`.

    Args:
        land_unit (str): Land unit key.
        pattern_overrides (Dict[str, str]): The mod's `pattern_overrides`.

    Returns:
        The faction codes, or an empty list when none match.
    """
    if "*" in pattern_overrides:
        return [code.strip() for code in pattern_overrides["*"].split(",")]
    keys = [(code, code) for code in FACTION_CODES] + [(pattern.replace("*", ""), code) for pattern, code in pattern_overrides.items()]
    use_underscores = not any("*" in pattern or "_" in pattern for pattern in pattern_overrides)
    for key, code in keys:
        if (f"_{key}_" if use_underscores else key) in land_unit:
            return [code]
    return []


def _group_by_code(codes_by_unit: Dict[str, List[str]]) -> Tuple[Dict[str, List[str]], List[str]]:
    """Split land units into those per faction code and those with none.

    Args:
        codes_by_unit (Dict[str, List[str]]): Land unit to its faction codes.

    Returns:
        A tuple of faction code to land units, and the land units with no code.
    """
    by_code: Dict[str, List[str]] = {}
    unknown = []
    for land_unit, codes in codes_by_unit.items():
        if not codes:
            unknown.append(land_unit)
        for code in codes:
            by_code.setdefault(code, []).append(land_unit)
    return by_code, unknown


def guess_pattern_overrides(main_rows: List[Dict[str, str]], permissions: Dict[str, Set[str]]) -> FactionGuess:
    """Guess a mod's `pattern_overrides` from its units.

    `{}` when every land unit carries a `_<code>_` race code, `{"*": code}` when every unit resolves to one faction, and uncertain otherwise.

    Args:
        main_rows (List[Dict[str, str]]): The mod's `main_units_tables` rows.
        permissions (Dict[str, Set[str]]): Main unit key to the military groups that can recruit it.

    Returns:
        The guess.
    """
    rows = [row for row in main_rows if row.get("land_unit")]
    underscore = {row["land_unit"]: match_factions(row["land_unit"], {}) for row in rows}
    if underscore and all(underscore.values()):
        by_code, _ = _group_by_code(underscore)
        return FactionGuess({}, by_code, [])

    resolved = {}
    for row in rows:
        code = NAME_TO_CODE.get(unit_faction(row["unit"], permissions.get(row["unit"], set())))
        resolved[row["land_unit"]] = [code] if code in FACTION_CODES else []
    by_code, unknown = _group_by_code(resolved)
    if len(by_code) == 1 and not unknown:
        return FactionGuess({"*": next(iter(by_code))}, by_code, [])
    return FactionGuess(None, by_code, unknown)


def lord_hero_candidates(subtype_rows: List[Dict[str, str]], main_rows: List[Dict[str, str]]) -> List[Candidate]:
    """List the generic lords and heroes a mod adds, with their mount variants.

    Only subtypes with `auto_generate` set are used, which leaves out most legendary lords.

    Args:
        subtype_rows (List[Dict[str, str]]): The mod's `agent_subtypes_tables` rows.
        main_rows (List[Dict[str, str]]): The mod's `main_units_tables` rows.

    Returns:
        The candidates in table order.
    """
    by_unit = {row["unit"]: row for row in main_rows}
    candidates: List[Candidate] = []
    for subtype in subtype_rows:
        if subtype.get("auto_generate", "").lower() != "true":
            continue
        row = by_unit.get(subtype.get("associated_unit_override", ""))
        if row is None or row["caste"] not in CHARACTER_CASTES:
            continue
        stem = VARIANT_SUFFIX.sub("", row["land_unit"])
        for variant in main_rows:
            candidate = Candidate(row["caste"], variant["land_unit"], subtype["key"])
            if variant["caste"] == row["caste"] and VARIANT_SUFFIX.sub("", variant["land_unit"]) == stem and candidate not in candidates:
                candidates.append(candidate)
    return candidates
