"""Add a downloaded Steam Workshop mod to `SUPPORTED_MODS` from its link.

Guesses every registry field from the mod's pack, asks only when a guess is uncertain, and always asks before writing.

Usage:
    cd helper_scripts && python -m tools.add_supported_mod https://steamcommunity.com/sharedfiles/filedetails/?id=3565085095
"""

import argparse
import ast
import glob
import json
import os
import re
import shutil
import subprocess
import sys
import urllib.parse
import urllib.request
from dataclasses import dataclass
from typing import Any, Callable, Dict, List, Optional, Set, Tuple

from core.extract_cache import cached_pack_extract
from core.utilities import STEAM_LIBRARY_DRIVE, TEMP_DIR, load_tsv_data, run_rpfm_cli
from data.supported_mods import SUPPORTED_MODS
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
# Registry file the new entry is appended to.
REGISTRY_PATH = "data/supported_mods.py"
# Steam's public item details endpoint. It needs no API key.
STEAM_DETAILS_URL = "https://api.steampowered.com/ISteamRemoteStorage/GetPublishedFileDetails/v1/"
# Scratch folder for the pack tables read while guessing.
SCRATCH = f"{TEMP_DIR}/add_supported_mod"
# Sample land unit keys shown per faction in the uncertain-faction prompt.
SAMPLE_COUNT = 3


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


def parse_pattern_answer(answer: str) -> Dict[str, str]:
    """Read the user's faction answer as `pattern_overrides`.

    Args:
        answer (str): A faction code, a comma list of codes, `{}`, or a pattern dict literal.

    Raises:
        ValueError: The answer names an unknown code or is not a dict of strings.

    Returns:
        The `pattern_overrides` to write.
    """
    text = answer.strip()
    if text.startswith("{"):
        try:
            value = ast.literal_eval(text)
        except (ValueError, SyntaxError) as error:
            raise ValueError(f"`{text}` is not a valid dict.") from error
        if not isinstance(value, dict) or not all(isinstance(k, str) and isinstance(v, str) for k, v in value.items()):
            raise ValueError("A pattern dict maps strings to faction codes.")
        codes = [code.strip() for v in value.values() for code in v.split(",")]
    else:
        codes = [code.strip() for code in text.split(",") if code.strip()]
        value = {"*": ",".join(codes)}
    unknown = [code for code in codes if code not in FACTION_CODES]
    # `{}` is the only answer allowed to name no codes.
    if unknown or (not codes and value != {}):
        raise ValueError(f"Unknown faction code(s): {', '.join(unknown) or text}. Known codes: {', '.join(FACTION_CODES)}.")
    return value


def choose_pattern_overrides(guess: FactionGuess, ask: Callable[[str], str]) -> Dict[str, str]:
    """Show the uncertain faction breakdown and ask until the answer is valid.

    Args:
        guess (FactionGuess): The uncertain guess.
        ask (Callable[[str], str]): Prompt function.

    Returns:
        The chosen `pattern_overrides`.
    """
    print("Could not place every unit in one faction:")
    for code, units in sorted(guess.by_code.items(), key=lambda item: -len(item[1])):
        print(f"  {code}: {len(units)} units, e.g. {', '.join(units[:SAMPLE_COUNT])}")
    if guess.unknown:
        print(f"  unknown: {len(guess.unknown)} units, e.g. {', '.join(guess.unknown[:SAMPLE_COUNT])}")
    while True:
        try:
            return parse_pattern_answer(ask("Faction for this mod (a code, a comma list, {} or a pattern dict): "))
        except ValueError as error:
            print(error)


def parse_selection(answer: str, count: int) -> List[int]:
    """Read an `all` / `none` / `1,3-5` answer as 0-based indices.

    Args:
        answer (str): The user's answer. Blank means none.
        count (int): How many numbered items were shown.

    Raises:
        ValueError: An index is out of range or the answer is not understood.

    Returns:
        The picked indices, sorted.
    """
    text = answer.strip().lower()
    if text in ("", "none"):
        return []
    if text == "all":
        return list(range(count))
    picked = set()
    for part in text.split(","):
        bounds = part.strip().split("-")
        if len(bounds) > 2 or not all(b.strip().isdigit() for b in bounds):
            raise ValueError(f"`{part.strip()}` is not a number or range.")
        low, high = int(bounds[0]), int(bounds[-1])
        if not 1 <= low <= high <= count:
            raise ValueError(f"`{part.strip()}` is outside 1-{count}.")
        picked.update(range(low - 1, high))
    return sorted(picked)


def choose_characters(candidates: List[Candidate], pattern_overrides: Dict[str, str], ask: Callable[[str], str]) -> Dict[str, Dict[str, List[Dict[str, str]]]]:
    """Ask which lord and hero candidates to allow, one prompt per faction.

    Args:
        candidates (List[Candidate]): Candidates from `lord_hero_candidates`.
        pattern_overrides (Dict[str, str]): The chosen `pattern_overrides`, used to place each candidate like the generator does.
        ask (Callable[[str], str]): Prompt function.

    Returns:
        The `character_overrides` to write. Empty when nothing was picked.
    """
    by_code: Dict[str, List[Candidate]] = {}
    for candidate in candidates:
        codes = match_factions(candidate.land_unit, pattern_overrides)
        if not codes:
            print(f"  {candidate.land_unit} matches no faction, so it cannot be offered.")
        for code in codes:
            by_code.setdefault(code, []).append(candidate)

    chosen: Dict[str, Dict[str, List[Dict[str, str]]]] = {}
    for code, faction_candidates in by_code.items():
        print(f"Lord and hero candidates for `{code}`:")
        for number, candidate in enumerate(faction_candidates, 1):
            print(f"  {number:>2}. {candidate.caste:<4}  {candidate.land_unit} -> {candidate.agent_subtype}")
        while True:
            try:
                picked = parse_selection(ask(f"Allow which for `{code}`? (all, none, or e.g. 1,3-5) [none]: "), len(faction_candidates))
                break
            except ValueError as error:
                print(error)
        lists: Dict[str, List[Dict[str, str]]] = {}
        for index in picked:
            candidate = faction_candidates[index]
            list_name = "allowed_lords" if candidate.caste == "lord" else "allowed_heroes"
            lists.setdefault(list_name, []).append({"land_unit": candidate.land_unit, "agent_subtype": candidate.agent_subtype})
        if lists:
            chosen[code] = {name: lists[name] for name in ("allowed_lords", "allowed_heroes") if name in lists}
    return chosen


def already_supported(workshop_id: str) -> bool:
    """Check whether a Workshop ID already has a registry entry.

    Args:
        workshop_id (str): Workshop ID.

    Returns:
        True when some entry's path sits in that ID's Workshop folder.
    """
    return any(f"/1142710/{workshop_id}/" in mod["path"].replace("\\", "/") for mod in SUPPORTED_MODS)


def find_pack(workshop_id: str, ask: Callable[[str], str]) -> str:
    """Find the downloaded pack for a Workshop ID, asking when there are several.

    Args:
        workshop_id (str): Workshop ID.
        ask (Callable[[str], str]): Prompt function.

    Raises:
        FileNotFoundError: The item folder has no `.pack` file.

    Returns:
        The pack filename.
    """
    packs = sorted(os.path.basename(path) for path in glob.glob(f"{WORKSHOP_ROOT}/{workshop_id}/*.pack"))
    if not packs:
        raise FileNotFoundError(f"No .pack in {WORKSHOP_ROOT}/{workshop_id}. Subscribe to the mod and let Steam download it first.")
    if len(packs) == 1:
        return packs[0]
    for number, pack in enumerate(packs, 1):
        print(f"  {number}. {pack}")
    while True:
        try:
            picked = parse_selection(ask("This item has several packs. Which one? "), len(packs))
            if len(picked) == 1:
                return packs[picked[0]]
        except ValueError as error:
            print(error)


def fetch_title(workshop_id: str) -> Optional[str]:
    """Look up a Workshop item's title through Steam's public API.

    Args:
        workshop_id (str): Workshop ID.

    Returns:
        The title, or None when the lookup fails for any reason.
    """
    body = urllib.parse.urlencode({"itemcount": 1, "publishedfileids[0]": workshop_id}).encode()
    try:
        with urllib.request.urlopen(STEAM_DETAILS_URL, data=body, timeout=10) as response:
            details = json.load(response)["response"]["publishedfiledetails"][0]
        return details.get("title") or None
    except Exception:
        return None


def pack_tables(pack_path: str) -> Set[str]:
    """List the db table names inside a pack.

    Args:
        pack_path (str): Path to the pack.

    Raises:
        RuntimeError: rpfm could not list the pack.

    Returns:
        Table names such as `main_units_tables`.
    """
    result = run_rpfm_cli(["pack", "list", "--pack-path", pack_path], capture_output=True)
    if result.returncode != 0:
        raise RuntimeError(f"rpfm could not list {pack_path}.")
    lines = result.stdout.decode("utf-8", errors="replace").splitlines()
    return {line.split("/")[1] for line in lines if line.startswith("db/") and line.count("/") >= 2}


def read_table(pack_path: str, table: str) -> List[Dict[str, str]]:
    """Read every row of one db table from a pack through the extraction cache.

    Args:
        pack_path (str): Path to the pack.
        table (str): Table name, e.g. `main_units_tables`.

    Returns:
        Row dicts keyed by column name. Empty when the pack lacks the table.
    """
    dest = f"{SCRATCH}/{table}"
    shutil.rmtree(dest, ignore_errors=True)
    cached_pack_extract(pack_path, f"db/{table}", dest, capture_output=True)
    rows: List[Dict[str, str]] = []
    for path in sorted(glob.glob(f"{dest}/**/*.tsv", recursive=True)):
        rows.extend(load_tsv_data(path)[0])
    return rows


def propose_entry(workshop_id: str, pack_name: str, name: str, ask: Callable[[str], str]) -> Dict[str, Any]:
    """Build the registry entry for a pack, asking only where a guess is uncertain.

    Args:
        workshop_id (str): Workshop ID.
        pack_name (str): Pack filename in the item folder.
        name (str): Mod name for the entry.
        ask (Callable[[str], str]): Prompt function.

    Returns:
        The entry dict.
    """
    path = f"{WORKSHOP_ROOT}/{workshop_id}/{pack_name}"
    tables = pack_tables(path)
    entry: Dict[str, Any] = {"name": name, "package_name": pack_name, "path": path, "modified_attributes": guess_attributes(tables)}
    print(f"modified_attributes: {', '.join(entry['modified_attributes']) or 'none'} (from pack tables)")

    main_rows = read_table(path, "main_units_tables") if "main_units_tables" in tables else []
    if not main_rows:
        print("No main_units_tables rows, so LEAPOI has nothing to use. Setting ignore_generation.")
        entry["ignore_generation"] = True
        return entry

    permissions: Dict[str, Set[str]] = {}
    for row in read_table(path, "units_to_groupings_military_permissions_tables"):
        permissions.setdefault(row.get("unit", ""), set()).add(row.get("military_group", ""))
    guess = guess_pattern_overrides(main_rows, permissions)
    entry["pattern_overrides"] = guess.overrides if guess.overrides is not None else choose_pattern_overrides(guess, ask)
    print(f"pattern_overrides: {entry['pattern_overrides']}")

    subtypes = read_table(path, "agent_subtypes_tables") if "agent_subtypes_tables" in tables else []
    characters = choose_characters(lord_hero_candidates(subtypes, main_rows), entry["pattern_overrides"], ask)
    if characters:
        entry["character_overrides"] = characters
    return entry


def main(argv: Optional[List[str]] = None, ask: Callable[[str], str] = input, fetch: Callable[[str], Optional[str]] = fetch_title) -> int:
    """Add one Workshop mod to `SUPPORTED_MODS`.

    Args:
        argv (Optional[List[str]]): Command line arguments. Defaults to `sys.argv[1:]`.
        ask (Callable[[str], str]): Prompt function.
        fetch (Callable[[str], Optional[str]]): Title lookup.

    Returns:
        The exit code.
    """
    parser = argparse.ArgumentParser(description="Add a downloaded Steam Workshop mod to SUPPORTED_MODS.")
    parser.add_argument("link", help="Workshop link or bare Workshop ID")
    parser.add_argument("--name", help="Mod name to use instead of the Workshop title")
    parser.add_argument("--no-update", action="store_true", help="Skip the `update.py --dry-run` after writing")
    args = parser.parse_args(argv)

    workshop_id = parse_workshop_id(args.link)
    if already_supported(workshop_id):
        print(f"Workshop item {workshop_id} is already in SUPPORTED_MODS. Nothing to do.")
        return 1
    pack_name = find_pack(workshop_id, ask)
    name = args.name or fetch(workshop_id) or ask("Could not fetch the Workshop title. Mod name: ").strip()
    try:
        entry = propose_entry(workshop_id, pack_name, name, ask)
    finally:
        shutil.rmtree(SCRATCH, ignore_errors=True)

    entry_text = render_entry(entry)
    print(entry_text)
    if ask("Write? [y/N] ").strip().lower() != "y":
        print("Nothing written.")
        return 0
    with open(REGISTRY_PATH, encoding="utf-8", newline="") as fh:
        registry_text = fh.read()
    new_text = append_entry(registry_text, entry_text, entry)
    with open(REGISTRY_PATH, "w", encoding="utf-8", newline="") as fh:
        fh.write(new_text)
    print(f"Added `{name}` to {REGISTRY_PATH}. Commit it, then run `python -m tools.update_supported_mods_list` for the Workshop descriptions.")
    if not args.no_update:
        subprocess.run([sys.executable, "update.py", "--dry-run"])
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print("\nCancelled. Nothing written.")
        sys.exit(1)
    except (ValueError, FileNotFoundError, RuntimeError) as error:
        print(error)
        sys.exit(1)
