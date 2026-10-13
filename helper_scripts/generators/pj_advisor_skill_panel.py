"""Builds the Addvisor Overhaul's skill panel layout with 10 skill rows instead of vanilla's 6.

The vanilla layout (`ui/campaign ui/character_details_panel_skills.twui.xml` in ui3.pack) has six row containers, `chain0` to `chain5`. A skill on
indent 6 or more has no row to sit in and never shows. This copies the vanilla file and changes it as tested in game on 2026-10-13:

- adds `chain6` to `chain9` as copies of `chain5`,
- makes rows 1-9 70 px tall like vanilla's row 5 (rows stack by height, the offsets are ignored),
- leaves `chain0` alone, since it holds the card templates and changing it froze the game,
- makes the list box 740 px tall, lets it hold 12 items per row so the last row does not wrap, and moves it 30 px down so row 0 is not clipped.

The layout replaces the vanilla file for every character, so re-run this after a game patch that changes it:

    python -m generators.pj_advisor_skill_panel
"""

import os
import re
import shutil
import sys
import uuid

from core.utilities import STEAM_LIBRARY_DRIVE, run_rpfm_cli

# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Settings

# The vanilla pack holding the skill panel layout.
UI_PACK = f"{STEAM_LIBRARY_DRIVE}\\SteamLibrary\\steamapps\\common\\Total War WARHAMMER III\\data\\ui3.pack"

# Path of the layout inside the pack and inside the mod.
LAYOUT = "ui/campaign ui/character_details_panel_skills.twui.xml"

# Where the vanilla layout is extracted to while building.
EXTRACT = "./temp/pj_advisor_skill_panel"

# The mod source folder.
MOD = "../warhammer3_mods/!!pj_advisor_overhaul"

# Number of skill rows the new layout has.
ROWS = 10

# Height of rows 1 and up. Vanilla's row 5 already uses it.
ROW_HEIGHT = 70

# Height of the list box: the 20 px top spacer, row 0 at its vanilla 90 px, then the other rows.
LIST_HEIGHT = 20 + 90 + (ROWS - 1) * ROW_HEIGHT

# Items per row of the list box. It must exceed the top spacer plus every row, or the last row wraps into a second column.
ITEMS_PER_ROW = 12

# Vertical dock offset of the list box. Vanilla's -10 clips the top row once the box is taller.
DOCK_OFFSET = "0.00,20.00"


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Build

def guid() -> str:
    """A new component id in the layout's format (8-4-4-16 hex digits).

    Returns:
        str: The id.
    """
    value = str(uuid.uuid4()).upper()
    return value[:23] + value[24:]


def component(layout: str, name: str) -> re.Match:
    """Finds a component definition (not its hierarchy entry) by tag name.

    Args:
        layout (str): The layout text.
        name (str): The component's tag, e.g. `chain5`.

    Returns:
        re.Match: The match spanning the whole definition.

    Raises:
        SystemExit: When the component is missing, e.g. after a game patch.
    """
    match = re.search(rf"\t\t<{name}\n.*?\t\t</{name}>\n", layout, re.S)
    if not match:
        raise SystemExit(f"component {name} not found in {LAYOUT}")
    return match


def patch(layout: str) -> str:
    """Applies the 10-row changes to the vanilla layout.

    Args:
        layout (str): The vanilla layout text.

    Returns:
        str: The changed layout.
    """
    last = component(layout, "chain5").group(0)
    last_id = re.search(r'this="([^"]+)"', last).group(1)
    hierarchy = re.search(rf'\t*<chain5 this="{last_id}"/>\n', layout).group(0)
    new_hierarchy, new_components = "", ""
    for row in range(6, ROWS):
        copy = last.replace("chain5", f"chain{row}")
        # Rows stack by height, so the offset is only kept tidy at vanilla's 90 px steps.
        copy = re.sub(r'offset="10\.00,\d+\.00"', f'offset="10.00,{20 + 90 * row}.00"', copy, count=1)
        for old_id in set(re.findall(r'this="([^"]+)"', last)):
            copy = copy.replace(old_id, guid())
        new_components += copy
        new_hierarchy += hierarchy.replace("chain5", f"chain{row}").replace(last_id, re.search(r'this="([^"]+)"', copy).group(1))
    layout = layout.replace(hierarchy, hierarchy + new_hierarchy).replace(last, last + new_components)

    for row in range(1, ROWS):
        match = component(layout, f"chain{row}")
        changed = re.sub(r'height="\d+"', f'height="{ROW_HEIGHT}"', match.group(0), count=1)
        layout = layout[:match.start()] + changed + layout[match.end():]

    match = component(layout, "list_box")
    box = match.group(0)
    box = re.sub(r'height="\d+"', f'height="{LIST_HEIGHT}"', box, count=1)
    box = re.sub(r'itemsperrow="\d+"', f'itemsperrow="{ITEMS_PER_ROW}"', box, count=1)
    box = re.sub(r'dock_offset="[^"]+"', f'dock_offset="{DOCK_OFFSET}"', box, count=1)
    return layout[:match.start()] + box + layout[match.end():]


def build() -> None:
    """Extracts the vanilla layout, changes it and writes it into the mod folder."""
    shutil.rmtree(EXTRACT, ignore_errors=True)
    try:
        run_rpfm_cli(["pack", "extract", "--pack-path", UI_PACK, "--file-path", f"{LAYOUT};{EXTRACT}"], capture_output=True)
        source = os.path.join(EXTRACT, LAYOUT)
        if not os.path.exists(source):
            raise SystemExit(f"{LAYOUT} not found in {UI_PACK}")
        layout = patch(open(source, encoding="utf-8").read())
    finally:
        shutil.rmtree(EXTRACT, ignore_errors=True)
    target = os.path.join(MOD, LAYOUT)
    os.makedirs(os.path.dirname(target), exist_ok=True)
    with open(target, "w", encoding="utf-8", newline="") as f:
        f.write(layout)
    print(f"wrote {target} with {ROWS} skill rows")


if __name__ == "__main__":
    build()
    sys.exit(0)
