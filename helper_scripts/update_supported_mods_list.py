"""Script to generate a formatted list of supported mods that all of the mods (modified attributes, double unit size, dynamic RORs, land encounters) are using.
"""

import logging
import time
from datetime import datetime
from supported_mods import SUPPORTED_MODS
from utilities import log_elapsed_time, setup_script_logging
import os
import re


if __name__ == "__main__":
    setup_script_logging()
    start_time = time.time()

    mods_map = {
        "melee": [],
        "ranged_arc": [],
        "velocity": [],
        "land_encounters": [],
        "dynamic_rors": [],
    }
    missing_mods = []

    for mod in SUPPORTED_MODS:
        if mod["package_name"] == "vanilla":
            continue
        mod_id = mod["path"].split("/")[-2]
        list_item = f"[*] [url=https://steamcommunity.com/sharedfiles/filedetails/?id={mod_id}]{mod['name']}[/url]"
        if "melee" in mod["modified_attributes"]:
            mods_map["melee"].append(list_item)
        if "ranged_arc" in mod["modified_attributes"]:
            mods_map["ranged_arc"].append(list_item)
        if "velocity" in mod["modified_attributes"]:
            mods_map["velocity"].append(list_item)
        if "ignore_generation" not in mod or not mod["ignore_generation"]:
            mods_map["land_encounters"].append(list_item)
        if not re.search(r"ror_|_ror_|_ror", mod["package_name"]):
            mods_map["dynamic_rors"].append(list_item)

        # Check if the mod is installed in the file system.
        if not os.path.exists(mod["path"]):
            missing_mods.append(f"{mod['name']} - https://steamcommunity.com/sharedfiles/filedetails/?id={mod_id}")

    for type in ["melee", "ranged_arc", "velocity", "land_encounters", "dynamic_rors"]:
        text_body = f"""[h1]Quick Overview[/h1]
Auto-generated on {datetime.now().strftime("%Y-%m-%d %H:%M:%S")} via Python script.

[list]

INSERT_LIST_HERE

[/list]
"""

        list_of_mods = mods_map.get(type)

        text_body = text_body.replace(f"INSERT_LIST_HERE", "\n".join(list_of_mods))
        with open(f"supported_mods_list_to_update_{type}.txt", "w", encoding="utf-8") as f:
            f.write(text_body)

    # Write a separate text file listing the mods that are missing.
    with open("missing_mods.txt", "w", encoding="utf-8") as f:
        f.write("\n".join(missing_mods))

    logging.info(f"Total mods: {len(SUPPORTED_MODS)}")
    logging.info(f"There are {len(missing_mods)} mods that are missing.")

    log_elapsed_time("generating updated lists of supported mods", start_time)
