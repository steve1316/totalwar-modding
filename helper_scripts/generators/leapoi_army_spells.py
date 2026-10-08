"""The army spell pools: every spell LEAPOI can hand an army for a battle, cast from the army ability bar at no Winds of Magic cost. Three
pools, read from the vanilla tables:

- lore: lore spells without a bound version, each made free by generators/leapoi_free_spells.py, with 3 uses up to 8 Winds of Magic, 2 up to
  14 and 1 above;
- bound: the bound (item, mount and character) spells, which already cost nothing, with their own uses;
- army: CA's own army abilities, with their own uses.

Each spell gets an army ability custom effect in generators/leapoi_effect_library.py, a one-battle bundle, a payload line naming it, and a
battle notice. The pools are kept in leapoi_army_spells.json. Refresh it from a folder of vanilla TSVs extracted with rpfm_cli
(`db/<table>/data__.tsv` and `text/db/unit_abilities__.loc.tsv`):

    python -m generators.leapoi_army_spells <folder>
"""

import json
import os
import re
import sys
from typing import Dict, List

from core.utilities import load_tsv_data

# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Pools

# Where the pools are kept.
DATA = os.path.join(os.path.dirname(os.path.abspath(__file__)), "leapoi_army_spells.json")

# The pools in the order they are written.
POOLS = ("lore", "bound", "army")

# Name of each spell's bundle after the tower bundle prefix, so its battle notice works like a tower buff's, and the prefix of its payload line
# (owned with the spot offer lines). The spell's id follows both.
BUNDLE_NAME = "spell_"
LINE_PREFIX = "dummy_land_enc_spot_spell_"

# The generated Lua list of the pools.
LUA = "script/land_encounters/configs/army_spells.lua"

# Army ability unique ids: bound spells count up from the first, lore copies from the second. CA's army abilities keep their own rows.
BOUND_ID_BASE, LORE_ID_BASE = 1700183000, 1700184000

# Pool -> the first sentence of a spell's bundle description. "{name}" is the spell's name.
POOL_TEXT = {
    "lore": "The army carries a scroll of {name}.",
    "bound": "The army carries a relic with {name} bound into it.",
    "army": "The army has learned the old rite of {name}.",
}

# Unique ids of the free lore copies' abilities count up from this.
FREE_ID_BASE = 1700182000

# Character-specific copies of a lore spell, which the lore pool leaves out.
VARIANT = re.compile(r"_(summoned|kihar|arzik|helman|strigoi|branchwraith|ror|\d)$")

# Army abilities that only exist for scripted quest battles or the AI, which the army pool leaves out.
SCRIPTED = re.compile(r"_ai$|qb|hidden|trigger|_scripted")


def load() -> Dict[str, List[Dict]]:
    """The kept pools.

    Returns:
        Dict[str, List[Dict]]: Pool -> spells, each { id, source, name, uses, army (CA's army ability key, army pool only), winds (lore only) }.
    """
    return json.load(open(DATA, encoding="utf-8"))


def spells() -> List[Dict]:
    """Every pool's spells, in pool order.

    Returns:
        List[Dict]: The spells, each with its `pool`.
    """
    data = load()
    return [{**spell, "pool": pool} for pool in POOLS for spell in data[pool]]


def line_text(spell: Dict) -> str:
    """A spell's payload line. A lore spell's says it costs no Winds of Magic, since only lore spells usually cost them.

    Args:
        spell (Dict): The spell, with its `pool`.

    Returns:
        str: The line.
    """
    free = ", at no Winds of Magic cost" if spell["pool"] == "lore" else ""
    return f"[[col:green]]Army spell: {spell['name']}[[/col]], {casts_text(spell['uses'])}{free}."


def lua() -> str:
    """The Lua list of the pools, which the offers roll a spell from.

    Returns:
        str: The file's text.
    """
    body = []
    for pool, spells in load().items():
        entries = "".join(f'        {{ id = "{s["id"]}", name = "{s["name"].replace(chr(34), chr(39))}" }},\n' for s in spells)
        body.append(f"    {pool} = {{\n{entries}    }},\n")
    return ("--- Army spell pools, written by helper_scripts/generators/update_leapoi_spot_offers.py from generators/leapoi_army_spells.json. Do not edit by\n"
            "--- hand. Each spell's bundle is land_enc_effect_tower_spell_<id> and its payload line dummy_land_enc_spot_spell_<id>.\n\n"
            "local M = {}\n\n--- Pool -> its spells, each { id, name }.\nM.pools = {\n" + "".join(body) + "}\n\nreturn M\n")


def name_of(loc: Dict[str, str], key: str) -> str:
    """An ability's English screen name, with the names it links to filled in and the "Upgraded" CA puts on stronger versions left off.

    Args:
        loc (Dict[str, str]): The vanilla unit_abilities loc, key -> text.
        key (str): The ability key.

    Returns:
        str: The name, empty when it has none.
    """
    text = loc.get("unit_abilities_onscreen_name_" + key, "")
    for _ in range(3):
        text = re.sub(r"\{\{tr:([^}]*)\}\}", lambda m: loc.get(m.group(1), ""), text)
    text = re.sub(r"\[\[/?[^\]]*\]\]|\{\{[^}]*\}\}", "", text).strip()
    return re.sub(r"\s+Upgraded$", "", text)


def description(spell: Dict) -> str:
    """A spell's bundle description: where the army's spell comes from, and how often it can be cast.

    Args:
        spell (Dict): The spell, with its `pool`.

    Returns:
        str: The description.
    """
    casts = casts_text(spell["uses"])
    return f"{POOL_TEXT[spell['pool']].format(name=spell['name'])} {casts[0].upper()}{casts[1:]}."


def casts_text(uses: int) -> str:
    """Names how often a spell can be cast, e.g. "2 casts in each battle".

    Args:
        uses (int): The uses, -1 for unlimited.

    Returns:
        str: The text.
    """
    return "no limit on casts" if uses < 0 else f"{uses} cast{'' if uses == 1 else 's'} in each battle"


def lore_uses(winds: int) -> int:
    """How many uses a free lore copy gets, from the spell's usual Winds of Magic cost.

    Args:
        winds (int): The spell's usual cost.

    Returns:
        int: 3, 2 or 1.
    """
    return 3 if winds <= 8 else 2 if winds <= 14 else 1


def uses_text(uses: int) -> str:
    """Names a spell's uses for its line, e.g. "2 uses".

    Args:
        uses (int): The uses, -1 for unlimited.

    Returns:
        str: The text.
    """
    return "unlimited uses" if uses < 0 else f"{uses} use" + ("" if uses == 1 else "s")


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Refresh

def refresh(folder: str) -> None:
    """Keeps every pool's spells, read from extracted vanilla TSVs. A spell's name is its English screen name, and a spell whose name is
    already in the pool is left out.

    Args:
        folder (str): The folder holding the vanilla TSVs.
    """
    def table(name: str) -> List[Dict[str, str]]:
        return load_tsv_data(os.path.join(folder, "db", name, "data__.tsv"))[0]

    loc = {r["key"]: r["text"] for r in load_tsv_data(os.path.join(folder, "text", "db", "unit_abilities__.loc.tsv"))[0]}
    hidden = {r["key"] for r in table("unit_abilities_tables") if r["is_hidden_in_ui"] == "true"}
    army_key = {}
    for r in table("army_special_abilities_tables"):
        army_key.setdefault(r["unit_special_ability"], r["army_special_ability"])
    pools: Dict[str, Dict[str, Dict]] = {pool: {} for pool in POOLS}
    for r in table("unit_special_abilities_tables"):
        key, name = r["key"], name_of(loc, r["key"])
        mana, uses = float(r["mana_cost"] or 0), int(float(r["num_uses"] or 0))
        if r["passive"] == "true" or key in hidden or not name:
            continue
        if "_bound_" in key and mana == 0 and uses != 0:
            pool, entry = "bound", {"source": key, "name": name, "uses": uses}
        elif key in army_key and mana == 0 and uses != 0 and not SCRIPTED.search(key):
            pool, entry = "army", {"source": key, "name": name, "uses": uses, "army": army_key[key]}
        elif mana > 0 and "_spell_" in key and not key.endswith("_upgraded") and not VARIANT.search(key):
            pool, entry = "lore", {"source": key, "name": name, "winds": int(mana), "uses": lore_uses(int(mana))}
        else:
            continue
        kept = pools[pool].get(name.lower())
        if kept is None or (re.search(r"_dlc\d+_", kept["source"]) and not re.search(r"_dlc\d+_", key)):
            pools[pool][name.lower()] = entry
    bound_names = set(pools["bound"])
    pools["lore"] = {n: e for n, e in pools["lore"].items() if n not in bound_names}
    out = {}
    for pool in POOLS:
        spells = sorted(pools[pool].values(), key=lambda e: e["source"])
        for number, spell in enumerate(spells, 1):
            spell["id"] = f"{pool}_{number:03d}"
        out[pool] = spells
    json.dump(out, open(DATA, "w", encoding="utf-8"), indent=1, sort_keys=True)
    print(f"kept {', '.join(f'{len(out[p])} {p}' for p in POOLS)} spells in {DATA}")


if __name__ == "__main__":
    refresh(sys.argv[1])
