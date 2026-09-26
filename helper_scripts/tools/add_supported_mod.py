"""Add a downloaded Steam Workshop mod to `SUPPORTED_MODS` from its link.

Guesses every registry field from the mod's pack, asks only when a guess is uncertain, and always asks before writing.

Usage:
    cd helper_scripts && python -m tools.add_supported_mod https://steamcommunity.com/sharedfiles/filedetails/?id=3565085095
"""

import ast
import json
import re
import urllib.parse
from dataclasses import dataclass
from typing import Any, Dict, List, Optional, Set, Tuple

from core.utilities import STEAM_LIBRARY_DRIVE
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
# Folder Steam downloads Warhammer 3 Workshop items into, one subfolder per Workshop ID.
WORKSHOP_ROOT = f"{STEAM_LIBRARY_DRIVE}/SteamLibrary/steamapps/workshop/content/1142710"
# Indent of one `SUPPORTED_MODS` element in the registry file.
ENTRY_INDENT = "    "


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


def _literal(value: Any) -> str:
    """Write a value as a Python literal in the registry's style, with double quotes and non-ASCII kept as is.

    Args:
        value (Any): A string, bool, or list or dict of strings.

    Returns:
        The literal text.
    """
    if isinstance(value, bool):
        return repr(value)
    return json.dumps(value, ensure_ascii=False)


def render_entry(entry: Dict[str, Any]) -> str:
    """Render a registry entry as the text of one `SUPPORTED_MODS` element.

    Args:
        entry (Dict[str, Any]): The entry. Its `path` must sit under `WORKSHOP_ROOT`.

    Raises:
        ValueError: The path is outside `WORKSHOP_ROOT` or contains braces, which the f-string cannot hold.

    Returns:
        The element text with `\n` line endings and no trailing newline.
    """
    path = entry["path"]
    if not path.startswith(WORKSHOP_ROOT) or "{" in path or "}" in path:
        raise ValueError(f"Cannot write `{path}` as a registry path.")
    pad = ENTRY_INDENT * 2
    lines = [f"{ENTRY_INDENT}{{"]
    lines.append(f'{pad}"name": {_literal(entry["name"])},')
    lines.append(f'{pad}"package_name": {_literal(entry["package_name"])},')
    lines.append(f'{pad}"path": f{_literal("{STEAM_LIBRARY_DRIVE}" + path[len(STEAM_LIBRARY_DRIVE):])},')
    lines.append(f'{pad}"modified_attributes": {_literal(entry["modified_attributes"])},')
    if "pattern_overrides" in entry:
        lines.append(f'{pad}"pattern_overrides": {_literal(entry["pattern_overrides"])},')
    if "character_overrides" in entry:
        lines.append(f'{pad}"character_overrides": {{')
        for code, lists in entry["character_overrides"].items():
            lines.append(f"{pad}{ENTRY_INDENT}{_literal(code)}: {{")
            for list_name, characters in lists.items():
                lines.append(f"{pad}{ENTRY_INDENT * 2}{_literal(list_name)}: [")
                lines.extend(f"{pad}{ENTRY_INDENT * 3}{_literal(character)}," for character in characters)
                lines.append(f"{pad}{ENTRY_INDENT * 2}],")
            lines.append(f"{pad}{ENTRY_INDENT}}},")
        lines.append(f"{pad}}},")
    if entry.get("ignore_generation"):
        lines.append(f'{pad}"ignore_generation": True,')
    lines.append(f"{ENTRY_INDENT}}},")
    return "\n".join(lines)


def _registry_list(text: str) -> ast.List:
    """Find the `SUPPORTED_MODS` list literal in registry source.

    Args:
        text (str): Registry source.

    Raises:
        ValueError: The text does not parse, or has no `SUPPORTED_MODS = [...]` assignment.

    Returns:
        The list node.
    """
    try:
        module = ast.parse(text)
    except SyntaxError as error:
        raise ValueError(f"The registry text does not parse: {error}") from error
    for node in module.body:
        if isinstance(node, ast.Assign) and any(getattr(target, "id", None) == "SUPPORTED_MODS" for target in node.targets) and isinstance(node.value, ast.List):
            return node.value
    raise ValueError("Could not find `SUPPORTED_MODS = [...]` in the registry.")


def append_entry(registry_text: str, entry_text: str, entry: Dict[str, Any]) -> str:
    """Append a rendered entry to the end of `SUPPORTED_MODS` and check the result parses back to the entry.

    Args:
        registry_text (str): The current `data/supported_mods.py` text.
        entry_text (str): The entry text from `render_entry`.
        entry (Dict[str, Any]): The entry the text must evaluate to.

    Raises:
        ValueError: The registry's closing bracket was not found, or the new text does not parse back to one extra entry equal to `entry`.

    Returns:
        The new registry text, in the original line endings.
    """
    eol = "\r\n" if "\r\n" in registry_text else "\n"
    text = registry_text.replace("\r\n", "\n")
    close = text.rfind("\n]")
    if close == -1:
        raise ValueError("Could not find the end of `SUPPORTED_MODS`.")
    head = text[:close].rstrip()
    if not head.endswith(","):
        head += ","
    new_text = f"{head}\n{entry_text}{text[close:]}"

    before, after = _registry_list(text), _registry_list(new_text)
    added = eval(compile(ast.Expression(after.elts[-1]), "<entry>", "eval"), {"STEAM_LIBRARY_DRIVE": STEAM_LIBRARY_DRIVE})
    if len(after.elts) != len(before.elts) + 1 or added != entry:
        raise ValueError("The new registry text does not parse back to the intended entry. Nothing was written.")
    return new_text.replace("\n", eol)
