"""Find which units have unit card art in vanilla or any subscribed Workshop pack.

A unit without a card anywhere is treated as unfinished (dummy units, bosses, bodyguard retinues): it gets no TTC cap and the browser hides it. Asset
packs count too, since some mods keep their cards apart from their data (e.g. Sigmar's Heirs ships them in `@xou_emp_assets.pack`).
"""

import glob
import logging
import os
from concurrent.futures import ThreadPoolExecutor
from typing import Dict, List, Optional, Set, Tuple

from core import delta
from core.pipeline import WORKSHOP_ROOT
from core.utilities import FILEPATH_TO_VANILLA_DATA_TABLES, run_rpfm_cli
from ttc.ttc_data import EXCLUDED_CASTES, TtcData, UnitStats

CARD_FOLDER = "ui/units/icons"
VANILLA_UI_PACK = os.path.join(os.path.dirname(FILEPATH_TO_VANILLA_DATA_TABLES), "ui.pack")
# Packs whose cards are ignored. Alternative_Cards only restyles cards that already exist, decided 2026-10-12.
IGNORED_CARD_PACKS = {"alternative_cards.pack"}
# Pack path to `{"stamp": size:mtime, "files": [card paths as the pack spells them]}`, so unchanged packs are not listed again.
CARD_INDEX_PATH = f"{delta.STATE_ROOT}/ttc_card_index.json"
LIST_WORKERS = 8


def _stamp(pack_path: str) -> str:
    """Identify a pack's current contents cheaply.

    Args:
        pack_path (str): Pack to stamp.

    Returns:
        `size:mtime_ns`.
    """
    stat = os.stat(pack_path)
    return f"{stat.st_size}:{stat.st_mtime_ns}"


def _list_cards(pack_path: str) -> Optional[List[str]]:
    """List the unit card files a pack ships, spelled as in the pack. Some packs use `UI/units/icons`, and rpfm extraction is case-sensitive.

    Args:
        pack_path (str): Pack to list.

    Returns:
        Pack-relative card paths, or None when rpfm could not list the pack.
    """
    # Read bytes and decode as UTF-8 ourselves. Text mode uses the Windows code page, which fails on packs with Chinese file names.
    result = run_rpfm_cli(["pack", "list", "--pack-path", pack_path], capture_output=True)
    if result.returncode != 0:
        return None
    # rpfm prints the listing to stderr together with its log lines.
    lines = (result.stdout + result.stderr).decode("utf-8", errors="replace").splitlines()
    paths = (line.strip() for line in lines)
    return sorted({path for path in paths if os.path.dirname(path).lower() == CARD_FOLDER and path.lower().endswith(".png")})


def card_packs() -> Optional[Dict[str, List[str]]]:
    """List the unit cards in vanilla `ui.pack` and every subscribed Workshop pack.

    Returns:
        Pack path to its card file paths, vanilla first and only packs with cards, or None when any pack could not be listed. Callers must then
        skip anything that relies on a unit having no card, since a failed listing would look like missing art.
    """
    index = delta._read_json(CARD_INDEX_PATH) or {}
    packs = [VANILLA_UI_PACK] + sorted(p for p in glob.glob(os.path.join(WORKSHOP_ROOT, "*", "*.pack")) if os.path.basename(p).lower() not in IGNORED_CARD_PACKS)
    stamps = {p: _stamp(p) for p in packs}
    stale = [p for p in packs if index.get(p, {}).get("stamp") != stamps[p] or "files" not in index[p]]
    with ThreadPoolExecutor(LIST_WORKERS) as pool:
        listed = dict(zip(stale, pool.map(_list_cards, stale)))
    failed = [p for p, cards in listed.items() if cards is None]
    for pack_path, cards in listed.items():
        if cards is not None:
            index[pack_path] = {"stamp": stamps[pack_path], "files": cards}
    if listed or set(index) != {p for p in packs if p in index}:
        delta._write_json(CARD_INDEX_PATH, {p: index[p] for p in packs if p in index})
    if failed or not index.get(VANILLA_UI_PACK, {}).get("files"):
        logging.error(f"Could not list unit cards in {len(failed)} pack(s), e.g. {failed[:3]}. Cardless units are not ignored this run.")
        return None
    return {p: index[p]["files"] for p in packs if index[p]["files"]}


def card_names(packs: Dict[str, List[str]]) -> Set[str]:
    """Merge the card names of every pack.

    Args:
        packs (Dict[str, List[str]]): Pack path to its card file paths.

    Returns:
        Every card name, lowercase and without `.png`.
    """
    return {os.path.basename(path)[: -len(".png")].lower() for paths in packs.values() for path in paths}


def card_candidates(key: str, stats: Dict[str, UnitStats], unit_cards: Dict[str, str]) -> Tuple[str, ...]:
    """List the card names a unit may use, in lookup order.

    The unit's `unit_variants_tables` card, then its own key, then the same for the land unit it borrows (the Beastmen Tzaangors use the Tzeentch
    land unit's card).

    Args:
        key (str): Unit key.
        stats (Dict[str, UnitStats]): Unit key to stats, for the land unit.
        unit_cards (Dict[str, str]): Unit key to its variant card name.

    Returns:
        Lowercase card names, without empty ones.
    """
    land_unit = stats[key].main.get("land_unit", "") if key in stats else ""
    names = (unit_cards.get(key), key, unit_cards.get(land_unit), land_unit)
    return tuple(name.lower() for name in names if name)


def has_card(key: str, data: TtcData, cards: Set[str]) -> bool:
    """Check that some pack ships a card for a unit.

    Args:
        key (str): Unit key.
        data (TtcData): Loaded TTC data, for the unit's land unit and variant cards.
        cards (Set[str]): Every card name.

    Returns:
        True when a card exists.
    """
    return any(name in cards for name in card_candidates(key, data.stats, data.unit_cards))


def cardless_units(data: TtcData, packs: Optional[Dict[str, List[str]]]) -> Optional[Set[str]]:
    """Find the units no pack ships card art for, leaving out lords and heroes, whose art is a portrait instead.

    Args:
        data (TtcData): Loaded TTC data.
        packs (Optional[Dict[str, List[str]]]): `card_packs()` result.

    Returns:
        Unit keys without a card, or None when some pack could not be listed.
    """
    if packs is None:
        return None
    cards = card_names(packs)
    cardless = {key for key, stats in data.stats.items() if stats.main.get("caste") not in EXCLUDED_CASTES and not has_card(key, data, cards)}
    logging.info(f"TTC cards: {len(cardless)} units have no card art in any pack and are ignored.")
    return cardless
