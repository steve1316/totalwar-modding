"""Reads and edits LEAPOI's `configs/coordinates.lua` line by line, so comments, layout and line endings stay as they are.

Nothing is ever deleted: spots and points of interest are found by their index (towers, marker ids and smithy saves use it), so a removed
entry is marked `disabled = true` in place. Entries may carry other `x = true` flags too, such as `tower = true` for a planted tower site or
`manual = true` for anything placed with the spot map.
"""

import os
import re
import shutil
import time
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Tuple

# Line patterns of the file: campaign blocks, sections, keyed blocks, area comments, spot entries, and the parts of a point-of-interest entry.
CAMPAIGN_RE = re.compile(r"^M\.(\w+)\s*=\s*\{")
SECTION_RE = re.compile(r"^\s*(treasures_and_spots|points_of_interest)\s*=\s*\{")
KEY_RE = re.compile(r'^(\s*)\["([^"]+)"\]\s*=\s*\{')
AREA_RE = re.compile(r"^\s*---\s*(.+?)\s*$")
SPOT_RE = re.compile(r"^(\s*)\{\s*(-?\d+)\s*,\s*(-?\d+)\s*((?:,\s*\w+\s*=\s*true\s*)*)\}\s*(,?)(.*)$")
FLAG_RE = re.compile(r"(\w+)\s*=\s*true")
COORDS_RE = re.compile(r"coordinates\s*=\s*\{\s*(-?\d+)\s*,\s*(-?\d+)\s*\}")
FIELD_RE = re.compile(r'(\w+)\s*=\s*"([^"]*)"')
RETURN_RE = re.compile(r"^return M\s*$")

# Indentation of the IE block, used wherever no neighbouring line sets it.
ZONE_INDENT = "         "
ENTRY_INDENT = "              "
POI_ZONE_INDENT = "        "
POI_LIST_INDENT = "            "
POI_ENTRY_INDENT = "                "


@dataclass
class Spot:
    """One encounter spot entry of a zone."""

    #: Zone key, e.g. "empire".
    zone: str
    #: 1-based index inside the zone, the one LEAPOI uses.
    index: int
    #: Logical x coordinate.
    x: int
    #: Logical y coordinate.
    y: int
    #: Name of the `--- Area` comment above the spot, empty when there is none.
    area: str
    #: Flags set to true on the entry, e.g. {"disabled", "tower"}.
    flags: set
    #: 0-based line number of the entry in the file.
    line: int

    @property
    def disabled(self) -> bool:
        """True when the entry is marked `disabled = true`."""
        return "disabled" in self.flags


@dataclass
class Poi:
    """One point of interest entry, e.g. a smithy or a tavern."""

    #: Zone key.
    zone: str
    #: List it sits in, e.g. "smithies".
    kind: str
    #: 1-based index inside that list.
    index: int
    #: Logical x coordinate.
    x: int
    #: Logical y coordinate.
    y: int
    #: String fields of the entry, e.g. {"initial_owner": "..."}.
    fields: Dict[str, str]
    #: Flags set to true on the entry, e.g. {"disabled", "manual"}.
    flags: set
    #: 0-based line numbers of the entry's first line, its coordinates line and its last line.
    first_line: int
    coords_line: int
    last_line: int
    #: True when the whole entry sits on one line.
    single_line: bool

    @property
    def disabled(self) -> bool:
        """True when the entry is marked `disabled = true`."""
        return "disabled" in self.flags


@dataclass
class PoiList:
    """One kind list of a points-of-interest zone, e.g. `["smithies"] = { ... }`."""

    #: 0-based line numbers of the list's opening and closing lines (the same line for an inline `{}` list).
    open_line: int
    close_line: int
    #: Indentation of the list key.
    indent: str
    #: True for an inline empty list such as `["taverns"] = {},`.
    inline: bool


@dataclass
class PoiZone:
    """One zone of a campaign's `points_of_interest`."""

    #: 0-based line number of the zone's closing brace.
    close_line: int = -1
    #: Indentation of the zone key.
    indent: str = POI_ZONE_INDENT
    #: Kind lists by name.
    lists: Dict[str, PoiList] = field(default_factory=dict)


@dataclass
class Zone:
    """One zone of a campaign's `treasures_and_spots`."""

    #: Zone key.
    name: str
    #: Spots in file order.
    spots: List[Spot] = field(default_factory=list)
    #: 0-based line number of the zone's closing brace.
    close_line: int = -1
    #: Indentation of the zone's entries, copied for new lines.
    indent: str = ENTRY_INDENT


@dataclass
class Campaign:
    """One `M.<key>` block of the file."""

    #: Campaign key, e.g. "immortal_empires".
    key: str
    #: Encounter zones by name, in file order.
    zones: Dict[str, Zone] = field(default_factory=dict)
    #: Points of interest in file order.
    pois: List[Poi] = field(default_factory=list)
    #: Points-of-interest zones by name.
    poi_zones: Dict[str, PoiZone] = field(default_factory=dict)
    #: 0-based line numbers of the closing braces of `treasures_and_spots` and `points_of_interest`.
    spots_close_line: int = -1
    pois_close_line: int = -1
    #: Line of an inline `points_of_interest = {},`, -1 when the section has a body.
    pois_inline_line: int = -1


def read_lines(path: str) -> Tuple[List[str], str]:
    """Reads a file as lines without their line endings.

    Args:
        path (str): File to read.

    Returns:
        The lines, and the line ending the file uses ("\\r\\n" or "\\n").
    """
    raw = open(path, "rb").read().decode("utf-8")
    newline = "\r\n" if "\r\n" in raw else "\n"
    return raw.replace("\r\n", "\n").split("\n"), newline


def _braces(line: str) -> int:
    """Net brace count of a line's code, ignoring a trailing comment.

    Args:
        line (str): One line.

    Returns:
        Opening minus closing braces.
    """
    code = line.split("--")[0]
    return code.count("{") - code.count("}")


def parse(lines: List[str]) -> Dict[str, Campaign]:
    """Parses every campaign block of the file. Depth 1 is a section, 2 a zone; in points_of_interest 3 is a kind list and 4+ an entry.

    Args:
        lines (List[str]): The file's lines.

    Returns:
        Campaigns by key.
    """
    campaigns: Dict[str, Campaign] = {}
    campaign: Optional[Campaign] = None
    section, depth, area = None, 0, ""
    zone: Optional[Zone] = None
    poi_zone, poi_zone_name, poi_kind, entry = None, None, None, None
    for n, line in enumerate(lines):
        m = CAMPAIGN_RE.match(line)
        if m:
            campaign, section = campaigns.setdefault(m.group(1), Campaign(m.group(1))), None
            continue
        if campaign is None:
            continue
        m = SECTION_RE.match(line)
        if m and section is None:
            section, depth = m.group(1), _braces(line)
            if depth == 0:
                if section == "points_of_interest":
                    campaign.pois_inline_line = n
                section = None
            continue
        if section is None:
            continue
        before = depth
        depth += _braces(line)
        key = KEY_RE.match(line)
        if section == "treasures_and_spots":
            if before == 1 and key:
                zone, area = campaign.zones.setdefault(key.group(2), Zone(key.group(2))), ""
            elif before == 2 and zone is not None:
                s, a = SPOT_RE.match(line), AREA_RE.match(line)
                if s:
                    zone.spots.append(Spot(zone.name, len(zone.spots) + 1, int(s.group(2)), int(s.group(3)), area, set(FLAG_RE.findall(s.group(4))), n))
                    zone.indent = s.group(1)
                elif a:
                    area = a.group(1)
                elif depth == 1:
                    zone.close_line, zone = n, None
        else:
            if before == 1 and key:
                poi_zone_name = key.group(2)
                poi_zone = campaign.poi_zones.setdefault(poi_zone_name, PoiZone(indent=key.group(1)))
            elif before == 2 and key:
                poi_kind = key.group(2)
                poi_zone.lists[poi_kind] = PoiList(n, n if depth == 2 else -1, key.group(1), depth == 2)
            elif before == 2 and depth == 1 and poi_zone is not None:
                poi_zone.close_line = n
            elif before == 3 and depth == 2 and entry is None:
                poi_zone.lists[poi_kind].close_line = n
            elif before >= 3 and (entry is not None or "{" in line):
                entry = entry or {"first": n, "lines": []}
                entry["lines"].append(n)
                if depth == 3:
                    text = "\n".join(lines[i] for i in entry["lines"])
                    c = COORDS_RE.search(text)
                    if c:
                        coords_line = next(i for i in entry["lines"] if COORDS_RE.search(lines[i]))
                        index = sum(1 for p in campaign.pois if p.zone == poi_zone_name and p.kind == poi_kind) + 1
                        campaign.pois.append(Poi(poi_zone_name, poi_kind, index, int(c.group(1)), int(c.group(2)), dict(FIELD_RE.findall(text)),
                                                 set(FLAG_RE.findall(text)), entry["first"], coords_line, entry["lines"][-1], len(entry["lines"]) == 1))
                    entry = None
        if depth <= 0:
            if section == "treasures_and_spots":
                campaign.spots_close_line = n
            else:
                campaign.pois_close_line = n
            section = None
    return campaigns


def set_flag(line: str, flag: str, on: bool) -> str:
    """Rewrites one spot entry line with a flag switched on or off, keeping its indentation, other flags and anything after it.

    Args:
        line (str): The spot entry line.
        flag (str): Flag name, e.g. "disabled".
        on (bool): True to set `flag = true`, False to drop it.

    Raises:
        ValueError: When the line is not a spot entry.

    Returns:
        The rewritten line.
    """
    m = SPOT_RE.match(line)
    if not m:
        raise ValueError("not a spot entry: " + line)
    flags = [f for f in FLAG_RE.findall(m.group(4)) if f != flag] + ([flag] if on else [])
    extra = "".join(f", {f} = true" for f in flags)
    return f"{m.group(1)}{{{m.group(2)}, {m.group(3)}{extra}}}{m.group(5) or ','}{m.group(6)}"


def set_coords(line: str, x: int, y: int) -> str:
    """Rewrites the coordinates of a spot entry line or a point-of-interest coordinates line, keeping everything else.

    Args:
        line (str): The line.
        x (int): New logical x coordinate.
        y (int): New logical y coordinate.

    Raises:
        ValueError: When the line holds no coordinates.

    Returns:
        The rewritten line.
    """
    m = SPOT_RE.match(line)
    if m:
        return f"{m.group(1)}{{{int(x)}, {int(y)}{m.group(4).rstrip()}}}{m.group(5) or ','}{m.group(6)}"
    if COORDS_RE.search(line):
        return COORDS_RE.sub(f"coordinates = {{{int(x)}, {int(y)}}}", line, count=1)
    raise ValueError("no coordinates on line: " + line)


def _poi_flag(lines: List[str], poi: Poi, flag: str, on: bool, inserts: List[Tuple[int, List[str]]], removes: List[int]):
    """Switches an `x = true` flag on a point-of-interest entry. One-line entries are edited in place; multi-line entries gain or lose a
    flag line, so the line numbers of later edits stay planned rather than applied.

    Args:
        lines (List[str]): The file's lines, edited in place for one-line entries.
        poi (Poi): The entry.
        flag (str): Flag name, e.g. "disabled".
        on (bool): True to set it, False to drop it.
        inserts (List[Tuple[int, List[str]]]): Insertions to extend.
        removes (List[int]): Line removals to extend.
    """
    if (flag in poi.flags) == on:
        return
    if poi.single_line:
        line = lines[poi.coords_line]
        lines[poi.coords_line] = re.sub(r"\s*\}(\s*,?\s*)$", f", {flag} = true }}\\1", line) if on else re.sub(rf",\s*{flag}\s*=\s*true", "", line)
    elif on:
        inserts.append((poi.coords_line + 1, [re.match(r"^(\s*)", lines[poi.coords_line]).group(1) + f"{flag} = true,"]))
    else:
        removes += [i for i in range(poi.first_line, poi.last_line + 1) if re.match(rf"^\s*{flag}\s*=\s*true\s*,?\s*$", lines[i])]
    (poi.flags.add if on else poi.flags.discard)(flag)


def spot_lines(entries: List[dict], indent: str, area: str = "") -> List[str]:
    """Writes spot entries, with an area comment wherever the area changes.

    Args:
        entries (List[dict]): Spots as {"x", "y", "area", "flags"}, where flags lists names set to true.
        indent (str): Indentation of each line.
        area (str): Area already in effect above the first entry.

    Returns:
        The lines.
    """
    lines = []
    for e in entries:
        if e.get("area") and e["area"] != area:
            area = e["area"]
            lines.append(f"{indent}--- {area}")
        extra = "".join(f", {f} = true" for f in e.get("flags", []))
        lines.append(f"{indent}{{{int(e['x'])}, {int(e['y'])}{extra}}},")
    return lines


def zone_lines(name: str, entries: List[dict]) -> List[str]:
    """Writes a whole encounter zone block at the IE block's indentation.

    Args:
        name (str): Zone key.
        entries (List[dict]): Spots as {"x", "y", "area", "flags"}.

    Returns:
        The lines.
    """
    return [f'{ZONE_INDENT}["{name}"] = {{'] + spot_lines(entries, ENTRY_INDENT) + [f"{ZONE_INDENT}}},"]


def poi_entry(indent: str, x: int, y: int, fields: Dict[str, object]) -> str:
    """Writes one single-line point-of-interest entry. Fields with no value are left out; `True` is written as a flag.

    Args:
        indent (str): Indentation of the line.
        x (int): Logical x coordinate.
        y (int): Logical y coordinate.
        fields (Dict[str, object]): Fields in order, e.g. {"initial_owner": "...", "region": "", "manual": True}.

    Returns:
        The line.
    """
    parts = [f"coordinates = {{{int(x)}, {int(y)}}}"] + [f"{k} = true" if v is True else f'{k} = "{v}"' for k, v in fields.items() if v is not None]
    return f"{indent}{{ {', '.join(parts)} }},"


def campaign_block(key: str, note: str, spots: List[dict], pois: Optional[List[dict]] = None) -> List[str]:
    """Writes a new `M.<key>` campaign block in the file's section style.

    Args:
        key (str): Campaign key.
        note (str): One-line comment above the block.
        spots (List[dict]): Spots as {"zone", "area", "x", "y", "flags"} in order.
        pois (Optional[List[dict]]): Points of interest as {"zone", "list", "x", "y", "fields"} in order.

    Returns:
        The block's lines.
    """
    lines = ["", "--- " + "/" * 98, "--- " + "/" * 98, f"--- {key}", "", f"--- {note}", f"M.{key} = {{", "    treasures_and_spots = {"]
    by_zone: Dict[str, List[dict]] = {}
    for s in spots:
        by_zone.setdefault(s["zone"], []).append(s)
    for name, entries in by_zone.items():
        lines += zone_lines(name, entries)
    lines.append("    },")
    if not pois:
        return lines + ["    points_of_interest = {},", "}"]
    lines.append("    points_of_interest = {")
    by_poi_zone: Dict[str, Dict[str, List[dict]]] = {}
    for p in pois:
        by_poi_zone.setdefault(p["zone"], {}).setdefault(p["list"], []).append(p)
    for name, lists in by_poi_zone.items():
        lines.append(f'{POI_ZONE_INDENT}["{name}"] = {{')
        for kind, entries in lists.items():
            lines += [f'{POI_LIST_INDENT}["{kind}"] = {{'] + [poi_entry(POI_ENTRY_INDENT, e["x"], e["y"], e["fields"]) for e in entries]
            lines.append(f"{POI_LIST_INDENT}}},")
        lines.append(f"{POI_ZONE_INDENT}}},")
    return lines + ["    },", "}"]


def write_block(path: str, key: str, note: str, spots: List[dict], pois: List[dict]) -> bool:
    """Writes `M.<key>` from scratch, replacing the block (with its header comments) when it exists, else adding it before `return M`. Meant
    for draft blocks LEAPOI does not read; a live block must be edited with `apply_edits` so indices stay put.

    Args:
        path (str): The coordinates.lua path.
        key (str): Block key, e.g. "immortal_empires_draft".
        note (str): One-line comment above the block.
        spots (List[dict]): Spots as {"zone", "area", "x", "y", "flags"}.
        pois (List[dict]): Points of interest as {"zone", "list", "x", "y", "fields"}.

    Returns:
        True when an existing block was replaced.
    """
    lines, newline = read_lines(path)
    start = next((i for i, line in enumerate(lines) if re.match(rf"^M\.{re.escape(key)}\s*=\s*\{{", line)), None)
    replaced = start is not None
    if replaced:
        end, depth = start, 0
        for end in range(start, len(lines)):
            depth += _braces(lines[end])
            if depth == 0:
                break
        # The header (blank line, two rules, name, blank line, note) written by `campaign_block` goes with the block.
        while start > 0 and (lines[start - 1].startswith("---") or not lines[start - 1].strip()):
            start -= 1
        del lines[start:end + 1]
        at = start
    else:
        at = next(i for i in range(len(lines) - 1, -1, -1) if RETURN_RE.match(lines[i]))
    lines[at:at] = campaign_block(key, note, spots, pois) + ([""] if not replaced else [])
    with open(path, "wb") as f:
        f.write(newline.join(lines).encode("utf-8"))
    return replaced


def backup(path: str, backup_dir: str) -> str:
    """Copies the file to a timestamped backup.

    Args:
        path (str): The coordinates.lua path.
        backup_dir (str): Folder for the backup copy.

    Returns:
        The backup's path.
    """
    os.makedirs(backup_dir, exist_ok=True)
    target = os.path.join(backup_dir, time.strftime("coordinates_%Y%m%d_%H%M%S.lua"))
    shutil.copyfile(path, target)
    return target


def _comma_before(lines: List[str], replace: Dict[int, str], at: int):
    """Gives the entry just above an insertion point a trailing comma when it ends in a bare `}`, so new entries after it stay valid Lua.

    Args:
        lines (List[str]): The file's lines.
        replace (Dict[int, str]): Line replacements to extend.
        at (int): Line before which something will be inserted.
    """
    i = at - 1
    while i >= 0 and (not lines[i].strip() or lines[i].strip().startswith("--")):
        i -= 1
    line = replace.get(i, lines[i])
    if i >= 0 and "\n" not in line and line.rstrip().endswith("}"):
        replace[i] = line.rstrip() + ","


def _poi_edits(campaign: Campaign, lines: List[str], poi_adds: List[dict], replace: Dict[int, str], inserts: List[Tuple[int, List[str]]]):
    """Plans the line edits that add point-of-interest entries, creating the list, zone or section body when it does not exist yet.

    Args:
        campaign (Campaign): The parsed campaign block.
        lines (List[str]): The file's lines.
        poi_adds (List[dict]): Entries as {"zone", "list", "x", "y", "fields"}.
        replace (Dict[int, str]): Line replacements to extend (a replacement may hold several lines joined by "\\n").
        inserts (List[Tuple[int, List[str]]]): Insertions to extend, as (line before which to insert, lines).
    """
    by_zone: Dict[str, Dict[str, List[dict]]] = {}
    for a in poi_adds:
        by_zone.setdefault(a["zone"], {}).setdefault(a["list"], []).append(a)
    new_zones: List[str] = []
    for zone_name, lists in by_zone.items():
        zone = campaign.poi_zones.get(zone_name)
        if zone is None:
            new_zones.append(f'{POI_ZONE_INDENT}["{zone_name}"] = {{')
            for kind, entries in lists.items():
                new_zones += [f'{POI_LIST_INDENT}["{kind}"] = {{'] + [poi_entry(POI_ENTRY_INDENT, e["x"], e["y"], e["fields"]) for e in entries]
                new_zones.append(f"{POI_LIST_INDENT}}},")
            new_zones.append(f"{POI_ZONE_INDENT}}},")
            continue
        list_indent = next(iter(zone.lists.values())).indent if zone.lists else zone.indent + "    "
        for kind, entries in lists.items():
            plist = zone.lists.get(kind)
            entry_indent = (plist.indent if plist else list_indent) + "    "
            body = [poi_entry(entry_indent, e["x"], e["y"], e["fields"]) for e in entries]
            if plist is None:
                inserts.append((zone.close_line, [f'{list_indent}["{kind}"] = {{'] + body + [f"{list_indent}}},"]))
            elif plist.inline:
                comma = "," if lines[plist.open_line].rstrip().endswith(",") else ""
                replace[plist.open_line] = "\n".join([f'{plist.indent}["{kind}"] = {{'] + body + [f"{plist.indent}}}{comma}"])
            else:
                inserts.append((plist.close_line, body))
    if new_zones:
        if campaign.pois_inline_line >= 0:
            replace[campaign.pois_inline_line] = "\n".join(["    points_of_interest = {"] + new_zones + ["    },"])
        else:
            inserts.append((campaign.pois_close_line, new_zones))


def apply_edits(path: str, campaign_key: str, add: List[dict], disable: List[dict], enable: List[dict], seed: Optional[List[dict]] = None,
                note: str = "", move: Optional[List[dict]] = None) -> dict:
    """Writes changes for one campaign block into the file. Take a `backup` first.

    Args:
        path (str): The coordinates.lua path.
        campaign_key (str): The `M.<key>` block to edit, e.g. "immortal_empires".
        add (List[dict]): New entries. Spots: {"storage": "spot", "zone", "area", "x", "y", "flags"}; points of interest:
            {"storage": "poi", "zone", "list", "x", "y", "fields"}. Missing zones and lists are created.
        disable (List[dict]): Entries to disable: {"target": "spot", "zone", "index"} or {"target": "poi", "zone", "kind", "index"}.
        enable (List[dict]): Disabled entries to switch back on, in the same shape.
        seed (Optional[List[dict]]): When the block does not exist yet, it is first written with these spots, then edited like any other.
        note (str): Comment above a block created from `seed`.
        move (Optional[List[dict]]): Entries to move, in the shape of `disable` plus their new "x" and "y". A moved entry keeps its line and
            index and is marked `manual = true`.

    Raises:
        ValueError: When a referenced entry does not exist, or the block is missing and no seed is given.

    Returns:
        A summary: {"added", "disabled", "enabled", "moved"}, plus "created" when the block was new.
    """
    lines, newline = read_lines(path)
    campaigns = parse(lines)
    created = campaign_key not in campaigns
    if created:
        if not seed:
            raise ValueError(f"campaign block M.{campaign_key} is missing")
        end = next(i for i in range(len(lines) - 1, -1, -1) if RETURN_RE.match(lines[i]))
        lines[end:end] = campaign_block(campaign_key, note, seed) + [""]
        campaigns = parse(lines)
    campaign = campaigns[campaign_key]
    replace: Dict[int, str] = {}
    inserts: List[Tuple[int, List[str]]] = []
    removes: List[int] = []

    def find(ref: dict):
        """Finds the spot or point of interest a change points at.

        Args:
            ref (dict): {"target": "spot", "zone", "index"} or {"target": "poi", "zone", "kind", "index"}.

        Raises:
            ValueError: When there is no such entry.

        Returns:
            The Spot or Poi.
        """
        if ref.get("target", "spot") == "spot":
            zone = campaign.zones.get(ref["zone"])
            if not zone or not 1 <= int(ref["index"]) <= len(zone.spots):
                raise ValueError(f"no spot {ref['zone']} {ref['index']} in M.{campaign_key}")
            return zone.spots[int(ref["index"]) - 1]
        poi = next((p for p in campaign.pois if p.zone == ref["zone"] and p.kind == ref["kind"] and p.index == int(ref["index"])), None)
        if poi is None:
            raise ValueError(f"no {ref['kind']} {ref['zone']} {ref['index']} in M.{campaign_key}")
        return poi

    for m in move or []:
        entry = find(m)
        if isinstance(entry, Spot):
            lines[entry.line] = set_flag(set_coords(lines[entry.line], m["x"], m["y"]), "manual", True)
        else:
            lines[entry.coords_line] = set_coords(lines[entry.coords_line], m["x"], m["y"])
            _poi_flag(lines, entry, "manual", True, inserts, removes)
    for on, entries in ((True, disable), (False, enable)):
        for d in entries:
            entry = find(d)
            if isinstance(entry, Spot):
                lines[entry.line] = set_flag(lines[entry.line], "disabled", on)
            else:
                _poi_flag(lines, entry, "disabled", on, inserts, removes)

    spot_adds: Dict[str, List[dict]] = {}
    for a in add:
        if a.get("storage", "spot") == "spot":
            spot_adds.setdefault(a["zone"], []).append(a)
    new_zones: List[str] = []
    for name, entries in spot_adds.items():
        zone = campaign.zones.get(name)
        if zone is None:
            new_zones += zone_lines(name, entries)
        else:
            inserts.append((zone.close_line, spot_lines(entries, zone.indent, zone.spots[-1].area if zone.spots else "")))
    if new_zones:
        inserts.append((campaign.spots_close_line, new_zones))
    _poi_edits(campaign, lines, [a for a in add if a.get("storage") == "poi"], replace, inserts)

    # Replacements keep line numbers; insertions and removals run bottom-up so earlier numbers stay valid.
    for at, _ in inserts:
        _comma_before(lines, replace, at)
    for n, text in replace.items():
        lines[n] = text
    for at, kind, payload in sorted([(at, 1, new) for at, new in inserts] + [(n, 0, None) for n in removes], key=lambda t: (t[0], t[1]), reverse=True):
        if kind == 0:
            del lines[at]
        else:
            lines[at:at] = payload
    with open(path, "wb") as f:
        f.write(newline.join("\n".join(lines).split("\n")).encode("utf-8"))
    summary = {"added": len(add), "disabled": len(disable), "enabled": len(enable), "moved": len(move or [])}
    if created:
        summary["created"] = campaign_key
    return summary
