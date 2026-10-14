"""Export a source animation set and its retargeted copy for the viewer, and serve it.

Pairs the two sets slot by slot and writes them as one comparison entry (see `tools.anim_viewer.exporter`). All URLs are relative, so the folder
can also be hosted as static files. For the Advisor unit gallery use `python -m generators.advisor_overhaul_gallery`.

Usage (from helper_scripts):
    python -m tools.anim_viewer --source-set <source .bin> --source-root <folder of source .anim files>
        --target-set <retargeted .bin or .animpack> --target-root <folder of retargeted .anim files> --skeletons <folder holding animations/skeletons>
        [--source-variant <variantmeshdefinition>] [--target-variant <variantmeshdefinition>] [--asset-folders <folder> ...] [--asset-packs <pack> ...]
        [--slots <regex>] [--skip-slots <regex>] [--out _diag/anim_viewer] [--port 8765] [--no-serve]

A variant is a local file or a game path. Its meshes are looked up in `--asset-folders`, then `--asset-packs`, then the vanilla packs.
"""

import argparse
import functools
import http.server
import sys

from core.asset_source import AssetSource
from tools.anim_viewer.exporter import Exporter, compare_entry, load_set


def serve(folder: str, port: int, host: str = "localhost") -> None:
    """Serves a viewer folder until Ctrl+C.

    Args:
        folder (str): The exported folder.
        port (int): Port.
        host (str): Address to bind.
    """
    handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=folder)
    print(f"viewer at http://{host}:{port}/ (Ctrl+C to stop)")
    http.server.ThreadingHTTPServer((host, port), handler).serve_forever()


def main() -> int:
    """Exports the sets and serves the viewer.

    Returns:
        int: Process exit code.
    """
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--source-set", required=True)
    parser.add_argument("--source-root", required=True)
    parser.add_argument("--target-set", required=True)
    parser.add_argument("--target-root", required=True)
    parser.add_argument("--skeletons", required=True)
    parser.add_argument("--source-variant")
    parser.add_argument("--target-variant")
    parser.add_argument("--asset-folders", nargs="*", default=[])
    parser.add_argument("--asset-packs", nargs="*", default=[])
    parser.add_argument("--slots", help="only export slots matching this regex")
    parser.add_argument("--skip-slots", help="leave out slots matching this regex")
    parser.add_argument("--out", default="./_diag/anim_viewer")
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--no-serve", action="store_true")
    args = parser.parse_args()
    assets = AssetSource([args.source_root, args.target_root, args.skeletons] + args.asset_folders, args.asset_packs)
    exporter = Exporter(args.out, assets)
    source_set, target_set = load_set(args.source_set), load_set(args.target_set)
    entry = compare_entry(exporter, f"{source_set.name} vs {target_set.name}", source_set, target_set,
                          {"source": args.source_variant, "target": args.target_variant}, args.slots, args.skip_slots)
    exporter.write()
    print(f"exported {len(entry['slots'])} slots to {args.out}")
    if not args.no_serve:
        serve(args.out, args.port)
    return 0


if __name__ == "__main__":
    sys.exit(main())
