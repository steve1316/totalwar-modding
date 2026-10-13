"""Build the Addvisor Overhaul test pack in the game data folder from the mod source files.

Usage:
    cd helper_scripts && python -m tools.redeploy_pj_advisor

The mod is not on the Workshop yet, so the pack goes straight into the game's data folder as `!!pj_advisor_overhaul.pack`. It is rebuilt from scratch
each run. The mod source lives at `../warhammer3_mods/!!pj_advisor_overhaul`.
"""

import logging
import os
import subprocess
import sys

from core.utilities import run_rpfm_cli, STEAM_LIBRARY_DRIVE

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")

PACK_PATH = f"{STEAM_LIBRARY_DRIVE}\\SteamLibrary\\steamapps\\common\\Total War WARHAMMER III\\data\\!!pj_advisor_overhaul.pack"
MOD_SOURCE = "../warhammer3_mods/!!pj_advisor_overhaul"
SCHEMA_RON_PATH = "./schemas/schema_wh3.ron"

# Top-level mod folders that should be packed. RESEARCH_NOTES.md is skipped.
FOLDERS = ["db", "script", "text", "ui", "variantmeshes", "animations"]


def game_running() -> bool:
    """Checks whether Warhammer 3 is running, since it locks its data packs.

    Returns:
        bool: True when Warhammer3.exe is in the task list.
    """
    result = subprocess.run(["tasklist", "/FI", "IMAGENAME eq Warhammer3.exe"], capture_output=True, text=True)
    return "Warhammer3.exe" in result.stdout


def main() -> int:
    """Recreate the pack and add every configured folder from the mod source tree.

    Returns:
        int: Process exit code (0 on success, 1 if the game is running or the mod source is missing).
    """
    if game_running():
        logging.error("Warhammer 3 is running. Close it first.")
        return 1
    if not os.path.isdir(MOD_SOURCE):
        logging.error(f"Mod source folder not found at {MOD_SOURCE}")
        return 1
    if os.path.exists(PACK_PATH):
        os.remove(PACK_PATH)
    run_rpfm_cli(["pack", "create", "--pack-path", PACK_PATH], capture_output=True)
    for folder in FOLDERS:
        source = f"{MOD_SOURCE}/{folder}"
        if not os.path.isdir(source):
            continue
        logging.info(f"Adding {folder}/ ...")
        result = run_rpfm_cli(["pack", "add", "--pack-path", PACK_PATH, "--tsv-to-binary", SCHEMA_RON_PATH, "--folder-path", f"{source};{folder}"],
                              capture_output=True, text=True)
        errors = [line for line in (result.stdout + result.stderr).splitlines() if "ERROR" in line.upper()]
        for line in errors:
            logging.error(line)
        if result.returncode != 0 or errors:
            return 1
    logging.info(f"Built {PACK_PATH}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
