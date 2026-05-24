"""This update script is used to perform the following tasks:
1. Update the faction data for the land encounters mod.
2. Update the Dynamic RoR mod.
3. Update the modified attribute mods.
"""

import argparse
import logging
import time
import subprocess
import signal
from typing import List
from utilities import log_elapsed_time, setup_script_logging


def run_script(cmd: List[str]):
    """Runs a script and returns the exit code.

    Args:
        cmd (List[str]): The command to run.

    Returns:
        The exit code of the script.
    """
    p = subprocess.Popen(cmd)
    try:
        return p.wait()
    except KeyboardInterrupt:
        p.send_signal(signal.SIGINT)
        p.wait()
        raise


if __name__ == "__main__":
    setup_script_logging()
    start_time = time.time()

    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--workers",
        type=int,
        default=None,
        help="Worker thread count forwarded to each parallel-capable subscript. When omitted, each subscript uses its own default of min(8, cpu_count()).",
    )
    args = parser.parse_args()
    workers_args = ["--workers", str(args.workers)] if args.workers is not None else []

    tasks = [
        ("Updating the faction data for the land encounters mod...", ["process_main_units_tables.py"]),
        ("Updating the Dynamic RoR mod...", ["update_dynamic_rors.py", "--reset"]),
        ("Updating the modified attribute mods...", ["update_modified_attribute_mods.py", "--reset"]),
        ("Updating the double unit size mod...", ["update_double_unit_size.py", "--reset"]),
    ]
    for description, script_args in tasks:
        logging.info(description)
        run_script(["python", *script_args, *workers_args])

    log_elapsed_time("updating all mods", start_time)
