"""Open the TTC unit browser, which now runs as the Unit Browser tab of the modding dashboard (`tools.dashboard`).

Usage:
    cd helper_scripts && python -m tools.ttc_review [--port 8765]

Lays out each culture's roster like the in-game Unit & Spell Browser with every unit's TTC cap, flags the low-confidence auto picks for review, and
writes confirmed or changed picks to the mods' hand files when Save is pressed. Rerun `update.py` afterwards to refresh the auto files and the TTC pack.
"""

import sys

from tools.dashboard.__main__ import main

if __name__ == "__main__":
    sys.argv[1:1] = ["--open", "browser"]
    from core.utilities import clear_temp_root, setup_script_logging
    setup_script_logging()
    try:
        exit_code = main()
    finally:
        clear_temp_root()
    sys.exit(exit_code)
