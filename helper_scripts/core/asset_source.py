"""Read game files by path from loose folders, mod packs or the vanilla packs, with cached pack listings and extracts.

Pack listings are cached by pack size and modified time. Extracted files are kept in a per-pack folder, so a file is only extracted once. Used by
the animation viewer and the unit generators.
"""

import hashlib
import os
import re
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, field
from typing import Dict, Iterable, List, Pattern, Tuple

from core.utilities import FILEPATH_TO_VANILLA_DATA_TABLES, run_rpfm_cli

# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Settings

# Cache of pack listings and extracted files, shared between runs.
CACHE_DIR = "./_diag/anim_viewer_cache"

# The game's data folder, holding the vanilla packs.
VANILLA_DATA_DIR = os.path.dirname(FILEPATH_TO_VANILLA_DATA_TABLES)

# Vanilla packs searched by default: models and textures.
VANILLA_PACK_PATTERN = re.compile(r"^(variants|models|warmachines|commontextures|data\.pack)")

# Files per rpfm extract call. More overflows the Windows command line.
EXTRACT_BATCH = 20


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Helpers


def norm(path: str) -> str:
    """Normalises a game path: lowercase, forward slashes, no leading slash.

    Args:
        path (str): The game path in any case and slash style.

    Returns:
        str: The normalised path.
    """
    return path.strip().replace("\\", "/").lstrip("/").lower()


def _pack_cache(pack: str) -> str:
    """Extract folder of one pack inside the cache."""
    key = hashlib.sha1(os.path.abspath(pack).lower().encode()).hexdigest()[:10]
    return os.path.join(CACHE_DIR, "files", f"{os.path.basename(pack)}_{key}")


def _list_pack(pack: str) -> List[str]:
    """Lists a pack's files, cached by pack size and modified time.

    Args:
        pack (str): Pack path.

    Returns:
        List[str]: File paths inside the pack.
    """
    stat = os.stat(pack)
    cache = os.path.join(CACHE_DIR, "listings", f"{os.path.basename(pack)}_{stat.st_size}_{int(stat.st_mtime)}.txt")
    if os.path.exists(cache):
        return open(cache, encoding="utf-8").read().splitlines()
    output = run_rpfm_cli(["pack", "list", "--pack-path", pack], capture_output=True, text=True).stdout
    paths = [line.strip() for line in output.splitlines() if line.strip()]
    os.makedirs(os.path.dirname(cache), exist_ok=True)
    with open(cache, "w", encoding="utf-8") as f:
        f.write("\n".join(paths))
    return paths


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Asset source


@dataclass
class AssetSource:
    """Looks files up in loose folders, then mod packs, then the vanilla packs, and extracts them on demand."""

    # Loose folders searched first.
    folders: List[str]
    # Packs searched next, in order.
    packs: List[str]
    # Vanilla packs searched last: every pack in the data folder whose name matches, in sorted order.
    vanilla: Pattern = VANILLA_PACK_PATTERN
    # Lowercase path to (pack path, path as the pack spells it).
    index: Dict[str, Tuple[str, str]] = field(default_factory=dict)
    # Lowercase path to a file in the loose folders.
    loose: Dict[str, str] = field(default_factory=dict)

    def __post_init__(self):
        for folder in reversed(self.folders):
            for root, _, names in os.walk(folder):
                for name in names:
                    full = os.path.join(root, name)
                    self.loose[norm(os.path.relpath(full, folder))] = full
        vanilla = sorted(os.path.join(VANILLA_DATA_DIR, n) for n in os.listdir(VANILLA_DATA_DIR) if n.endswith(".pack") and self.vanilla.match(n))
        packs = self.packs + vanilla
        with ThreadPoolExecutor(8) as pool:
            listings = list(pool.map(_list_pack, packs))
        for pack, paths in zip(packs, listings):
            for path in paths:
                self.index.setdefault(path.lower(), (pack, path))

    def fetch(self, paths: Iterable[str]) -> Dict[str, bytes]:
        """Reads files by game path, extracting from packs in batches.

        Args:
            paths (Iterable[str]): Game paths, any case and slash style.

        Returns:
            Dict[str, bytes]: Contents by the normalised (lowercase, forward slash) path. Missing files are left out.
        """
        found: Dict[str, bytes] = {}
        wanted: Dict[str, List[Tuple[str, str]]] = {}
        for raw in paths:
            path = norm(raw)
            if not path or path in found:
                continue
            if path in self.loose:
                found[path] = open(self.loose[path], "rb").read()
                continue
            if path not in self.index:
                continue
            pack, spelled = self.index[path]
            target = os.path.join(_pack_cache(pack), spelled)
            if os.path.exists(target):
                found[path] = open(target, "rb").read()
            else:
                wanted.setdefault(pack, []).append((path, spelled))
        for pack, items in wanted.items():
            dest = _pack_cache(pack)
            for start in range(0, len(items), EXTRACT_BATCH):
                args = ["pack", "extract", "--pack-path", pack]
                for _, spelled in items[start:start + EXTRACT_BATCH]:
                    args += ["--file-path", f"{spelled};{dest}"]
                run_rpfm_cli(args, capture_output=True)
            for path, spelled in items:
                target = os.path.join(dest, spelled)
                if os.path.exists(target):
                    found[path] = open(target, "rb").read()
        return found

    def fetch_all(self, paths: Iterable[str]) -> Dict[str, bytes]:
        """Reads files by game path like `fetch`, but stops when any is missing.

        Args:
            paths (Iterable[str]): Game paths, any case and slash style.

        Returns:
            Dict[str, bytes]: Contents by the normalised path.

        Raises:
            SystemExit: When a path is in no folder or pack.
        """
        paths = list(paths)
        found = self.fetch(paths)
        missing = sorted({p for p in paths if norm(p) not in found})
        if missing:
            raise SystemExit(f"not in any searched pack: {', '.join(missing)}")
        return found
