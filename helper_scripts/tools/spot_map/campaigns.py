"""Campaign sources for the spot map: which pack holds each campaign's minimap, which coordinates.lua blocks hold its spots, and the
settlement positions from the debug_coordinates F4 dump.
"""

import json
import logging
import os
import re
import struct
from typing import Dict, List, Optional

from core.extract_cache import cached_pack_extract
from core.pipeline import workshop_pack_path
from core.utilities import FILEPATH_TO_VANILLA_DATA_TABLES, run_rpfm_cli
from tools.spot_map import coordinates_io

GAME_DATA_FOLDER = os.path.dirname(FILEPATH_TO_VANILLA_DATA_TABLES)
SETTLEMENT_DUMP = os.path.join(os.path.dirname(GAME_DATA_FOLDER), "debug_settlements.tsv")
COORDINATES_PATH = "../warhammer3_mods/land_encounters_and_points_of_interest_with_mct/script/land_encounters/configs/coordinates.lua"
CACHE_DIR = "./_diag/spot_map"
BACKUP_DIR = "./_diag/spot_map/backups"
DATA_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data")
#: Clean-slate layouts, one JSON file per campaign, saved as the page changes them.
LAYOUT_DIR = os.path.join(DATA_DIR, "layouts")
#: Suffix of the coordinates.lua block a clean-slate layout is exported to. LEAPOI never reads these blocks.
DRAFT_SUFFIX = "_draft"

#: Every campaign the tool shows. `lua` lists the coordinates.lua blocks whose spots it draws (IEE draws IE's too); `maps` is the folder
#: prefix inside the pack, the newest numbered folder wins; `dump_names` match the campaign name in the F4 dump's header;
#: `settlements_from` borrows another campaign's settlements until this one has its own dump.
CAMPAIGNS = [
    {"key": "ie", "label": "Immortal Empires", "pack": os.path.join(GAME_DATA_FOLDER, "data_maps.pack"), "maps": "wh3_main_combi_map_",
     "minimap": "wh3_main_combi_map_minimap.png", "lua": ["immortal_empires"], "dump_names": ["main_warhammer"]},
    {"key": "iee", "label": "Immortal Empires Expanded", "pack": workshop_pack_path("3007996493", "!cr_immortal_empires_expanded.pack"),
     "maps": "cr_combi_expanded_map_", "minimap": "cr_combi_expanded_map_minimap.png", "lua": ["immortal_empires", "immortal_empires_expanded"],
     "dump_names": ["cr_combi_expanded", "expanded"], "settlements_from": "ie"},
    {"key": "roc", "label": "Realm of Chaos", "pack": os.path.join(GAME_DATA_FOLDER, "data_maps.pack"), "maps": "wh3_main_chaos_map_",
     "minimap": "wh3_main_chaos_map_minimap.png", "lua": ["realm_of_chaos"], "dump_names": ["wh3_main_chaos"]},
    {"key": "ow", "label": "The Old World", "pack": workshop_pack_path("3081800026", "!cr_oldworld_campaign.pack"), "maps": "cr_oldworld_map_",
     "minimap": "cr_oldworld_map_minimap.png", "lua": ["old_world"], "dump_names": ["cr_oldworld", "oldworld"], "seed": "oldworld_draft.json",
     "seed_note": "Draft spots for The Old World campaign (!cr_oldworld_campaign). LEAPOI does not load this campaign yet."},
]
CAMPAIGN_BY_KEY = {c["key"]: c for c in CAMPAIGNS}

#: What the map can plant, and how each is stored in coordinates.lua. "spot" types are encounter spot entries, with an optional `flag`
#: set to true (`tower = true` makes the spot its zone's tower site). "poi" types are entries of `points_of_interest.<zone>.<list>`; their
#: `fields` are written in order, where "owner" is pre-filled from the nearest settlement's owner, "culture" is picked from `CULTURES` (empty
#: for neutral) and any other value is written as is. Add a row here to plant a new kind of spot.
SPOT_TYPES = [
    {"key": "spot", "label": "Encounter spot", "storage": "spot"},
    {"key": "tower", "label": "Tower site", "storage": "spot", "flag": "tower"},
    {"key": "smithy", "label": "Smithy", "storage": "poi", "list": "smithies", "fields": {"initial_owner": "owner", "owner_if_player": "owner", "region": ""}},
    {"key": "tavern", "label": "Tavern", "storage": "poi", "list": "taverns", "fields": {"culture": "culture", "initial_owner": "owner", "owner_if_player": "owner"}},
]
TYPE_BY_KEY = {t["key"]: t for t in SPOT_TYPES}
#: LEAPOI's culture shorthands (configs/factions_data.lua), for racial taverns.
CULTURES = ["bst", "brt", "chd", "chs", "cst", "cth", "def", "dwf", "emp", "grn", "hef", "kho", "ksl", "lzd", "nor", "nur", "ogr", "skv", "sla", "tmb",
            "tze", "vmp", "wef"]

#: Map files found per campaign key this run, None for a campaign whose map could not be found, so a miss is not retried every request.
_maps: Dict[str, Optional[Dict[str, str]]] = {}
#: Pack listings this run, by pack path. IE and Realm of Chaos share data_maps.pack.
_listings: Dict[str, str] = {}


def png_size(path: str) -> tuple:
    """Reads a PNG's width and height from its header.

    Args:
        path (str): The PNG file.

    Returns:
        (width, height).
    """
    with open(path, "rb") as f:
        head = f.read(24)
    return struct.unpack(">II", head[16:24])


def map_files(campaign: dict) -> Optional[Dict[str, str]]:
    """Finds the campaign's minimap and prebattle map in the newest map folder of its pack. Extraction goes through the shared pack cache,
    so a pack update brings the new map in on the next run.

    Args:
        campaign (dict): One `CAMPAIGNS` entry.

    Returns:
        {"minimap": path, "prebattle": path}, or None when the pack or its map is missing.
    """
    key = campaign["key"]
    if key in _maps:
        return _maps[key]
    _maps[key] = None
    pack = campaign["pack"]
    if not os.path.isfile(pack):
        logging.warning(f"{campaign['label']}: pack not found at {pack}")
        return None
    if pack not in _listings:
        _listings[pack] = run_rpfm_cli(["pack", "list", "--pack-path", pack], capture_output=True, text=True).stdout or ""
    versions = sorted(int(m.group(1)) for m in re.finditer(re.escape(campaign["maps"]) + r"(\d+)/" + re.escape(campaign["minimap"]), _listings[pack]))
    if not versions:
        logging.warning(f"{campaign['label']}: no {campaign['minimap']} in {pack}")
        return None
    folder = f"campaign_maps/{campaign['maps']}{versions[-1]}"
    dest = os.path.join(CACHE_DIR, key)
    for name in (campaign["minimap"], "prebattle_map.png"):
        cached_pack_extract(pack, f"{folder}/{name}", dest, source_kind="file", tables_as_tsv=False, capture_output=True)
    files = {"minimap": os.path.join(dest, folder, campaign["minimap"]), "prebattle": os.path.join(dest, folder, "prebattle_map.png")}
    if not all(os.path.isfile(f) for f in files.values()):
        logging.warning(f"{campaign['label']}: extracting {folder} failed")
        return None
    _maps[key] = files
    return files


def import_settlement_dump() -> Optional[str]:
    """Saves the game folder's latest F4 settlement dump for the campaign its header names, so each campaign keeps its own copy. A dump
    that is older than the saved copy is skipped.

    Returns:
        The campaign key the dump was saved for, or None when there is nothing new or its campaign is unknown.
    """
    if not os.path.isfile(SETTLEMENT_DUMP):
        return None
    lines = open(SETTLEMENT_DUMP, encoding="utf-8").read().splitlines()
    m = re.match(r"# campaign: ([^,]+)", lines[0] if lines else "")
    if not m:
        return None
    name = m.group(1).strip()
    campaign = next((c for c in CAMPAIGNS if name in c["dump_names"]), None) or next((c for c in CAMPAIGNS if any(n in name for n in c["dump_names"])), None)
    if not campaign:
        logging.warning(f"F4 dump is for campaign '{name}', which matches no campaign here")
        return None
    target = os.path.join(DATA_DIR, f"settlements_{campaign['key']}.json")
    if os.path.isfile(target) and os.path.getmtime(target) >= os.path.getmtime(SETTLEMENT_DUMP):
        return None
    settlements = []
    for line in lines[2:]:
        parts = line.split("\t")
        if len(parts) >= 7:
            settlements.append({"region": parts[0], "name": parts[1], "x": int(parts[2]), "y": int(parts[3]), "province": parts[4],
                                "owner": parts[5], "capital": parts[6] == "true"})
    os.makedirs(DATA_DIR, exist_ok=True)
    with open(target, "w", encoding="utf-8") as f:
        json.dump({"campaign": name, "settlements": settlements}, f, indent=1, ensure_ascii=False)
    logging.info(f"Saved {len(settlements)} settlements from the F4 dump for {campaign['label']}")
    return campaign["key"]


def settlements_for(campaign: dict) -> List[dict]:
    """Loads a campaign's saved settlements, or those of `settlements_from` until it has its own dump.

    Args:
        campaign (dict): One `CAMPAIGNS` entry.

    Returns:
        Settlements as {"region", "name", "x", "y", "province", "owner", "capital"}.
    """
    for key in (campaign["key"], campaign.get("settlements_from")):
        path = os.path.join(DATA_DIR, f"settlements_{key}.json")
        if key and os.path.isfile(path):
            return json.load(open(path, encoding="utf-8"))["settlements"]
    return []


def seed_spots(campaign: dict) -> List[dict]:
    """Loads the starting spots of a campaign that has no coordinates.lua block yet.

    Args:
        campaign (dict): One `CAMPAIGNS` entry.

    Returns:
        Spots as {"zone", "area", "x", "y"}, empty when the campaign has no seed.
    """
    if not campaign.get("seed"):
        return []
    return json.load(open(os.path.join(DATA_DIR, campaign["seed"]), encoding="utf-8"))["spots"]


def load_layout(campaign: dict, blocks: Dict[str, coordinates_io.Campaign]) -> List[dict]:
    """Loads a campaign's clean-slate layout, or rebuilds it from its exported draft blocks when there is no layout file yet.

    Args:
        campaign (dict): One `CAMPAIGNS` entry.
        blocks (Dict[str, coordinates_io.Campaign]): The parsed coordinates.lua.

    Returns:
        Entries as {"type", "lua", "zone", "area", "x", "y", "fields"}.
    """
    path = os.path.join(LAYOUT_DIR, f"{campaign['key']}.json")
    if os.path.isfile(path):
        return json.load(open(path, encoding="utf-8"))["entries"]
    entries = []
    for lua in campaign["lua"]:
        block = blocks.get(lua + DRAFT_SUFFIX)
        if block is None:
            continue
        for zone in block.zones.values():
            entries += [{"type": "tower" if "tower" in s.flags else "spot", "lua": lua, "zone": s.zone, "area": s.area, "x": s.x, "y": s.y, "fields": {}}
                        for s in zone.spots]
        for p in block.pois:
            kind = next((t["key"] for t in SPOT_TYPES if t.get("list") == p.kind), None)
            if kind:
                entries.append({"type": kind, "lua": lua, "zone": p.zone, "area": "", "x": p.x, "y": p.y, "fields": dict(p.fields)})
    return entries


def save_layout(body: dict) -> int:
    """Saves a campaign's clean-slate layout from the page.

    Args:
        body (dict): {"campaign": key, "entries": [...]}.

    Raises:
        ValueError: When the campaign is unknown.

    Returns:
        The number of entries saved.
    """
    campaign = CAMPAIGN_BY_KEY.get(body.get("campaign"))
    if not campaign:
        raise ValueError(f"unknown campaign {body.get('campaign')}")
    os.makedirs(LAYOUT_DIR, exist_ok=True)
    entries = body.get("entries", [])
    with open(os.path.join(LAYOUT_DIR, f"{campaign['key']}.json"), "w", encoding="utf-8") as f:
        json.dump({"campaign": campaign["key"], "entries": entries}, f, indent=1, ensure_ascii=False)
    return len(entries)


def export_draft(body: dict) -> dict:
    """Writes a campaign's clean-slate layout to coordinates.lua as `M.<lua>_draft` blocks, replacing earlier drafts, after one backup.

    Args:
        body (dict): {"campaign": key}.

    Raises:
        ValueError: When the campaign is unknown or its layout is empty.

    Returns:
        {"backup", "blocks": {draft key: {"spots", "pois", "replaced"}}}.
    """
    campaign = CAMPAIGN_BY_KEY.get(body.get("campaign"))
    if not campaign:
        raise ValueError(f"unknown campaign {body.get('campaign')}")
    entries = load_layout(campaign, coordinates_io.parse(coordinates_io.read_lines(COORDINATES_PATH)[0]))
    if not entries:
        raise ValueError(f"the {campaign['label']} clean-slate layout is empty")
    backup = coordinates_io.backup(COORDINATES_PATH, BACKUP_DIR)
    summaries = {}
    for lua in campaign["lua"]:
        mine = [to_entry(e) for e in entries if e.get("lua", campaign["lua"][0]) == lua]
        if not mine:
            continue
        spots, pois = [e for e in mine if e["storage"] == "spot"], [e for e in mine if e["storage"] == "poi"]
        note = f"Clean-slate draft of {campaign['label']} from the spot map. LEAPOI does not read this block."
        replaced = coordinates_io.write_block(COORDINATES_PATH, lua + DRAFT_SUFFIX, note, spots, pois)
        summaries[lua + DRAFT_SUFFIX] = {"spots": len(spots), "pois": len(pois), "replaced": replaced}
    logging.info(f"Exported the {campaign['label']} clean-slate draft: {summaries} (backup {backup})")
    return {"backup": os.path.abspath(backup), "blocks": summaries}


def state() -> dict:
    """Builds everything the page draws, for every campaign whose map could be found. A campaign without its block yet shows its seed.

    Returns:
        {"campaigns": [...]} with each campaign's map size, spots, points of interest, settlements and zones.
    """
    blocks = coordinates_io.parse(coordinates_io.read_lines(COORDINATES_PATH)[0])
    out = []
    for campaign in CAMPAIGNS:
        files = map_files(campaign)
        if not files:
            continue
        width, height = png_size(files["minimap"])
        logical_width, logical_height = png_size(files["prebattle"])
        spots, pois, zones, seeded = [], [], [], False
        for lua in campaign["lua"]:
            block = blocks.get(lua)
            if block is None:
                block = coordinates_io.parse(coordinates_io.campaign_block(lua, "", seed_spots(campaign)))[lua]
                seeded = True
            for zone in block.zones.values():
                zones.append({"lua": lua, "zone": zone.name})
                spots += [{"lua": lua, "zone": s.zone, "index": s.index, "x": s.x, "y": s.y, "area": s.area, "disabled": s.disabled,
                           "flags": sorted(s.flags - {"disabled"})} for s in zone.spots]
            pois += [{"lua": lua, "zone": p.zone, "kind": p.kind, "index": p.index, "x": p.x, "y": p.y, "fields": p.fields, "disabled": p.disabled,
                      "flags": sorted(p.flags - {"disabled"})} for p in block.pois]
        out.append({"key": campaign["key"], "label": campaign["label"], "W": width, "H": height, "LW": logical_width, "LH": logical_height,
                    "spots": spots, "pois": pois, "zones": zones, "settlements": settlements_for(campaign), "seeded": seeded,
                    "layout": load_layout(campaign, blocks)})
    return {"campaigns": out, "types": SPOT_TYPES, "cultures": CULTURES}


def to_entry(change: dict) -> dict:
    """Turns a planted change from the page into the writer's entry, using its type's storage.

    Args:
        change (dict): {"type", "zone", "area", "x", "y", "fields"}.

    Raises:
        ValueError: When the type is unknown.

    Returns:
        A spot entry {"storage": "spot", ...} or a point-of-interest entry {"storage": "poi", "list", ...}.
    """
    kind = TYPE_BY_KEY.get(change.get("type", "spot"))
    if kind is None:
        raise ValueError(f"unknown spot type {change.get('type')}")
    entry = {"storage": kind["storage"], "zone": change["zone"], "area": change.get("area", ""), "x": change["x"], "y": change["y"]}
    # Everything planted with the map is marked manual, so a later spacing trim leaves it alone unless asked to.
    if kind["storage"] == "spot":
        entry["flags"] = ([kind["flag"]] if kind.get("flag") else []) + ["manual"]
    else:
        given = change.get("fields", {})
        entry["list"] = kind["list"]
        entry["fields"] = {name: (given.get(name) or None) if hint in ("owner", "culture") else hint for name, hint in kind["fields"].items()}
        entry["fields"]["manual"] = True
    return entry


def export(changes: dict) -> dict:
    """Writes one campaign's pending changes into coordinates.lua, after one backup.

    Args:
        changes (dict): {"campaign": key, "add": [...], "disable": [...], "enable": [...], "move": [...]}, each change carrying its "lua"
            block. Additions carry their `SPOT_TYPES` key as "type"; deletions and moves carry "target" ("spot" or "poi"), moves their new x, y.

    Raises:
        ValueError: When the campaign is unknown or a change points at a missing spot.

    Returns:
        {"backup", "blocks": {lua: summary}}.
    """
    campaign = CAMPAIGN_BY_KEY.get(changes.get("campaign"))
    if not campaign:
        raise ValueError(f"unknown campaign {changes.get('campaign')}")
    backup = coordinates_io.backup(COORDINATES_PATH, BACKUP_DIR)
    seed = seed_spots(campaign)
    summaries = {}
    for lua in campaign["lua"]:
        add, disable, enable, move = ([c for c in changes.get(kind, []) if c.get("lua") == lua] for kind in ("add", "disable", "enable", "move"))
        add = [to_entry(c) for c in add]
        if add or disable or enable or move:
            summaries[lua] = coordinates_io.apply_edits(COORDINATES_PATH, lua, add, disable, enable, seed=seed, note=campaign.get("seed_note", ""), move=move)
    logging.info(f"Exported {campaign['label']}: {summaries} (backup {backup})")
    return {"backup": os.path.abspath(backup), "blocks": summaries}
