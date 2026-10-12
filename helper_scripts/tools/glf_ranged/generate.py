"""Write GLF Battle Mage's data, animation slots and fire metas for the units ticked in `selection.json`.

Usage:
    cd helper_scripts && python -u -m tools.glf_ranged.generate [--dry-run] [--deploy] > _diag/glf_ranged_generate.log 2>&1

For each ticked unit this sets its GLF missile in `land_units`, points monster-mount rider personalities at the missile, and makes sure its animation
set can fire. A set missing its fire slot borrows one of its own cast animations that faces forward, with a `glf_*_fire.anm.meta` fire marker when
the cast has none. On-foot sets also get `COMBAT_READY` slots so the unit does not T-pose after firing. Units no longer ticked lose their GLF rows.
`--deploy` copies the changed files into the subscribed GLF pack. Run `tools.glf_rebuild_animpack` first after a game patch, since the generator
builds on the animation sets GLF ships.
"""

import argparse
import collections
import logging
import os
import re
import statistics
import time
from dataclasses import dataclass, field, replace
from typing import Callable, Dict, Iterable, List, Optional, Set, Tuple

from core.pipeline import SCHEMA_RON_PATH
from core.utilities import TEMP_DIR, clear_temp_root, log_elapsed_time, run_rpfm_cli, setup_script_logging
from data.supported_mods import SUPPORTED_MODS
from tools.glf_ranged import catalog
from tools.glf_ranged.anim_meta import AnimHeader, FirePos, add_fire_pos, faces_backward, faces_forward, read_anim_header, read_fire_pos
from tools.glf_rebuild_animpack import (
    ALL_WEAPONS,
    GLF_ANIMPACK_PATH,
    GLF_MOD_DIR,
    VANILLA_DATA_DIR,
    AnimRef,
    AnimSet,
    Slot,
    apply_patches,
    list_vanilla_files,
    read_animpack,
    write_animpack,
    write_set,
)

PERSONALITIES_TSV = f"{GLF_MOD_DIR}/db/battle_personalities_tables/glf_battle_mage.tsv"
STATS_TSV = f"{GLF_MOD_DIR}/db/battle_entity_stats_tables/glf_battle_mage.tsv"
REPORT_PATH = "./_diag/glf_ranged_generate_report.txt"
FILES_DIR = f"{TEMP_DIR}/glf_ranged_files"
GLF_PACKAGE = "!!!1a_glf_battle_mage_Dante.pack"
# Columns a new GLF land unit row changes from vanilla, besides the missile.
NEW_UNIT_COLUMNS = {"primary_ammo": "20", "ai_usage_group": "hybrid_mage_highvalue"}
# Junction attach type for riders on monster mounts, whose personality needs GLF's missile stats to fire.
AUTONOMOUS_RIDER = "autonomous_rider"
# Fire slots each unit kind needs, all filled with the same cast animation.
FIRE_SLOTS = {
    "foot": ["FIRE_LEVEL"],
    "flyer": ["FIRE_LEVEL"],
    "rider": ["RIDER_FIRE_FORWARD_LEVEL", "RIDER_SHOOT_TURN_LEFT_90", "RIDER_SHOOT_TURN_RIGHT_90"],
}
# Slots that play a fire animation, checked for animations that face backwards.
FIRE_FAMILY = re.compile(r"^(FIRE_|MOVING_FIRE_|RIDER_FIRE_|RIDER_SHOOT_TURN_)")
# Set name to the animation its fire slots play instead of a cast, for riders whose only casts stand them up. The Astromancer's Great Moon Bird
# casts are his on-foot casts, so he fires with his seated staff swing (2026-10-12).
FIRE_ANIM_OVERRIDES = {
    "hu1e_dlc24_bi1_eagle_mage_hero": "animations/battle/humanoid01e/rider/eagle/attacks/hu1e_dlc24_bi1_eagle_mage_hero_astromancer_attack_01.anim",
}
# Shoot stance slots and the slots they copy, which vanilla units that fire while moving on foot also have.
SHOOT_SOURCES = [
    ("SHOOT_STAND", "STAND"),
    ("SHOOT_STAND_IDLE_1", "STAND_IDLE_1"),
    ("SHOOT_READY", "STAND"),
    ("SHOOT_READY_IDLE_1", "STAND_IDLE_1"),
    ("SHOOT_WALK_1", "WALK_1"),
    ("SHOOT_RUN_1", "RUN_1"),
]
ATTRIBUTE_JUNCTIONS_TSV = f"{GLF_MOD_DIR}/db/unit_attributes_to_groups_junctions_tables/glf_battle_mage.tsv"
ATTRIBUTE_GROUPS_TSV = f"{GLF_MOD_DIR}/db/unit_attributes_groups_tables/glf_battle_mage.tsv"
ENTITIES_TSV = f"{GLF_MOD_DIR}/db/battle_entities_tables/glf_battle_mage.tsv"
VEHICLES_TSV = f"{GLF_MOD_DIR}/db/land_unit_articulated_vehicles_tables/glf_battle_mage.tsv"
NODES_TSV = f"{GLF_MOD_DIR}/db/articulation_nodes_in_land_articulated_vehicles_tables/glf_battle_mage.tsv"
# Firing arc that vanilla units which fire while moving almost always have, so they can shoot at targets off to the side or behind.
FULL_ARC = "360.0000"
# Combat-ready slots and the movement slots they copy, so an on-foot unit has a stance to return to after firing.
COMBAT_READY_SOURCES = [
    ("COMBAT_READY", "STAND"),
    ("COMBAT_READY_MOVE_1", "WALK_1"),
    ("COMBAT_READY_MOVE_2", "RUN_1"),
    ("COMBAT_READY_MOVE_3", "RUN_2"),
    ("COMBAT_READY_STEP_FORWARD", "STEP_FORWARD"),
    ("COMBAT_READY_STEP_BACK", "STEP_BACKWARD"),
    ("COMBAT_READY_STEP_LEFT", "STEP_LEFT"),
    ("COMBAT_READY_STEP_RIGHT", "STEP_RIGHT"),
    ("COMBAT_READY_TURN_LEFT_45", "TURN_LEFT_45"),
    ("COMBAT_READY_TURN_RIGHT_45", "TURN_RIGHT_45"),
    ("COMBAT_READY_TURN_LEFT_90", "TURN_LEFT_90"),
    ("COMBAT_READY_TURN_RIGHT_90", "TURN_RIGHT_90"),
    ("COMBAT_READY_TURN_LEFT_180", "TURN_LEFT_180"),
    ("COMBAT_READY_TURN_RIGHT_180", "TURN_RIGHT_180"),
]
# Fallback fire marker when no GLF meta exists for a skeleton: part way through the cast, chest high, a little forward.
DEFAULT_FIRE_RATIO = 0.45
DEFAULT_FIRE_POSITION = (0.0, 1.2, 0.5)
# Files per rpfm extract call, to stay under the Windows command line limit.
EXTRACT_BATCH = 40


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Files


@dataclass
class TsvFile:
    """A table TSV edited line by line, so rows the generator does not touch are written back unchanged."""

    # File path.
    path: str
    # Line ending used by the file.
    newline: str
    # Column names.
    header: List[str]
    # The header and version lines as read.
    head_lines: List[str]
    # Row values by key, in file order.
    rows: Dict[str, List[str]]
    # True when the file ended with a line ending.
    trailing_newline: bool

    @classmethod
    def load(cls, path: str) -> "TsvFile":
        """Read a TSV.

        Args:
            path (str): File path.

        Returns:
            The file.
        """
        with open(path, encoding="utf-8", newline="") as f:
            text = f.read()
        newline = "\r\n" if "\r\n" in text else "\n"
        lines = text.split(newline)
        trailing = lines[-1] == ""
        if trailing:
            lines = lines[:-1]
        rows = {line.split("\t")[0]: line.split("\t") for line in lines[2:] if line}
        return cls(path, newline, lines[0].split("\t"), lines[:2], rows, trailing)

    @classmethod
    def create(cls, path: str, table: str, version: int, header: List[str]) -> "TsvFile":
        """Start an empty table TSV in RPFM's layout, for a table GLF does not ship yet.

        Args:
            path (str): File path. Its name without `.tsv` becomes the table file name in the pack.
            table (str): Table name, e.g. `unit_attributes_groups_tables`.
            version (int): Table version.
            header (List[str]): Column names.

        Returns:
            The empty file.
        """
        name = os.path.splitext(os.path.basename(path))[0]
        version_line = f"#{table};{version};db/{table}/{name}" + "\t" * (len(header) - 1)
        return cls(path, "\r\n", header, ["\t".join(header), version_line], {}, True)

    def set(self, key: str, column: str, value: str) -> None:
        """Change one cell.

        Args:
            key (str): Row key.
            column (str): Column name.
            value (str): New value.
        """
        self.rows[key][self.header.index(column)] = value

    def get(self, key: str, column: str) -> str:
        """Read one cell.

        Args:
            key (str): Row key.
            column (str): Column name.

        Returns:
            The value.
        """
        return self.rows[key][self.header.index(column)]

    def add(self, row: Dict[str, str]) -> None:
        """Add a row from a dict, in this file's column order. Rows are keyed by their first column, or by every column when the first repeats.

        Args:
            row (Dict[str, str]): Column name to value. Missing columns are left empty.
        """
        values = [row.get(column, "") for column in self.header]
        key = values[0] if values[0] not in self.rows else "\t".join(values)
        self.rows[key] = values

    def text(self) -> str:
        """Render the file.

        Returns:
            The TSV text.
        """
        lines = self.head_lines + ["\t".join(values) for values in self.rows.values()]
        return self.newline.join(lines) + (self.newline if self.trailing_newline else "")


class GameFiles:
    """Reads animation and meta files from the GLF mod folder first, then from the vanilla packs."""

    def __init__(self):
        self.pack_of = {path: entry for path, entry in list_vanilla_files().items() if path.startswith("animations/")}
        self.cache: Dict[str, Optional[bytes]] = {}

    def _local(self, path: str) -> str:
        """Map a pack path to the GLF mod folder.

        Args:
            path (str): Pack path.

        Returns:
            The file path in the mod folder.
        """
        return os.path.join(GLF_MOD_DIR, path.replace("\\", "/"))

    def _extracted(self, path: str) -> str:
        """Map a pack path to where `prefetch` extracts it.

        Args:
            path (str): Pack path.

        Returns:
            The extracted file path, or empty when no vanilla pack has the file.
        """
        entry = self.pack_of.get(path.replace("\\", "/").lower())
        return os.path.join(FILES_DIR, entry[1]) if entry else ""

    def prefetch(self, paths: Iterable[str]) -> None:
        """Extract every listed vanilla file that GLF does not ship and that is not extracted yet, a batch per pack.

        Args:
            paths (Iterable[str]): Pack paths.
        """
        wanted = collections.defaultdict(list)
        for path in {p.replace("\\", "/") for p in paths if p}:
            extracted = self._extracted(path)
            if extracted and not os.path.exists(self._local(path)) and not os.path.exists(extracted):
                pack, real = self.pack_of[path.lower()]
                wanted[pack].append(real)
        for pack, reals in wanted.items():
            for start in range(0, len(reals), EXTRACT_BATCH):
                args = ["pack", "extract", "--pack-path", f"{VANILLA_DATA_DIR}\\{pack}"]
                for real in reals[start : start + EXTRACT_BATCH]:
                    args += ["-f", f"{real};{FILES_DIR}"]
                run_rpfm_cli(args, capture_output=True)

    def read(self, path: str) -> Optional[bytes]:
        """Read a file.

        Args:
            path (str): Pack path.

        Returns:
            The bytes, or None when neither GLF nor vanilla has the file.
        """
        path = path.replace("\\", "/")
        if path.lower() not in self.cache:
            self.prefetch([path])
            found = next((candidate for candidate in (self._local(path), self._extracted(path)) if candidate and os.path.exists(candidate)), None)
            data = None
            if found:
                with open(found, "rb") as f:
                    data = f.read()
            self.cache[path.lower()] = data
        return self.cache[path.lower()]


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Generation


@dataclass
class Result:
    """What one generation run changed, for the report and the deploy."""

    # Land unit keys added to GLF.
    added: List[str] = field(default_factory=list)
    # Land unit keys removed from GLF.
    removed: List[str] = field(default_factory=list)
    # Land unit keys whose missile changed.
    changed: List[str] = field(default_factory=list)
    # Ticked units left out, with why.
    skipped: List[str] = field(default_factory=list)
    # Personality keys added, changed or removed.
    personalities: List[str] = field(default_factory=list)
    # Set name to the slot names added to it.
    sets: Dict[str, List[str]] = field(default_factory=dict)
    # Fire metas written, by pack path.
    metas: Dict[str, bytes] = field(default_factory=dict)
    # Sets that could not get a fire slot, with why.
    manual: List[str] = field(default_factory=list)
    # Land unit keys given the fire-whilst-moving attribute, with the group it went on.
    fwm: List[str] = field(default_factory=list)
    # Chariot units given a full firing arc, with the GLF chariot they now use.
    arcs: List[str] = field(default_factory=list)


def fire_defaults(inputs: catalog.Inputs, files: GameFiles) -> Dict[str, Tuple[float, Tuple[float, float, float]]]:
    """Work out a default fire time ratio and position per skeleton from GLF's existing fire metas.

    Args:
        inputs (catalog.Inputs): Catalog inputs.
        files (GameFiles): File reader.

    Returns:
        Skeleton name to (time as a share of the animation, median position). The key `*` holds the median over every skeleton.
    """
    refs = []
    for entry in inputs.sets.values():
        if entry.glf is None:
            continue
        for slot in entry.glf.slots:
            if inputs.names.get(slot.slot_id) in catalog.FIRE_SLOT_NAMES and slot.refs and slot.refs[0].meta:
                refs.append((entry.glf.skeleton, slot.refs[0]))
    files.prefetch(path for _, ref in refs for path in (ref.anim, ref.meta))
    samples = collections.defaultdict(list)
    for skeleton, ref in refs:
        meta, anim = files.read(ref.meta), files.read(ref.anim)
        fire = read_fire_pos(meta) if meta else None
        if fire and anim:
            length = read_anim_header(anim).length
            if length > 0:
                samples[skeleton].append((fire.time / length, fire.position))
                samples["*"].append((fire.time / length, fire.position))

    def median(values: List[Tuple[float, Tuple[float, float, float]]]) -> Tuple[float, Tuple[float, float, float]]:
        return statistics.median(v[0] for v in values), tuple(statistics.median(v[1][i] for v in values) for i in range(3))

    defaults = {skeleton: median(values) for skeleton, values in samples.items()}
    defaults.setdefault("*", (DEFAULT_FIRE_RATIO, DEFAULT_FIRE_POSITION))
    return defaults


def fire_meta_path(anim_path: str) -> str:
    """Name the GLF fire meta for a cast animation, next to it.

    Args:
        anim_path (str): Pack path of the `.anim`.

    Returns:
        Pack path of `glf_<name>_fire.anm.meta`.
    """
    folder, name = os.path.split(anim_path.replace("\\", "/"))
    return f"{folder}/glf_{os.path.splitext(name)[0]}_fire.anm.meta"


def find_fire_ref(anim_set: AnimSet, kind: str, ids: Dict[str, int], files: GameFiles, defaults: Dict, override: Optional[List[float]], result: Result) -> Optional[Tuple[Slot, AnimRef]]:
    """Pick a forward-facing cast animation in the set and make sure it has a fire marker.

    Args:
        anim_set (AnimSet): The set to add fire slots to.
        kind (str): `foot`, `rider` or `flyer`.
        ids (Dict[str, int]): Slot id by name.
        files (GameFiles): File reader.
        defaults (Dict): Fire defaults from `fire_defaults`.
        override (Optional[List[float]]): `[time, x, y, z]` from the selection, or None.
        result (Result): Collects fire metas written.

    Returns:
        The cast slot and the reference the fire slots should use, or None when no cast animation faces forward.
    """
    by_id = {slot.slot_id: slot for slot in anim_set.slots}
    candidates = [by_id[ids[name]] for name in catalog.CAST_SLOTS[kind] if ids.get(name) in by_id and by_id[ids[name]].refs]
    files.prefetch(path for slot in candidates for path in (slot.refs[0].anim, slot.refs[0].meta))
    for slot in candidates:
        ref = slot.refs[0]
        anim = files.read(ref.anim)
        if anim is None:
            continue
        header = read_anim_header(anim)
        if not faces_forward(header):
            continue
        return slot, marked_ref(ref, header, files, defaults, override, result)
    return None


def marked_ref(ref: AnimRef, header: AnimHeader, files: GameFiles, defaults: Dict, override: Optional[List[float]], result: Result) -> AnimRef:
    """Make sure an animation has a fire marker, writing a GLF copy of its meta with one when it does not.

    Args:
        ref (AnimRef): The animation, meta and sound to fire with.
        header (AnimHeader): The animation's header.
        files (GameFiles): File reader.
        defaults (Dict): Fire defaults from `fire_defaults`.
        override (Optional[List[float]]): `[time, x, y, z]` from the selection, or None.
        result (Result): Collects fire metas written.

    Returns:
        The reference the fire slots should use.
    """
    meta = files.read(ref.meta) if ref.meta else None
    if override is None and meta and read_fire_pos(meta):
        return ref
    new_path = fire_meta_path(ref.anim)
    if override is not None:
        fire = FirePos(override[0], tuple(override[1:4]))
    else:
        ratio, position = defaults.get(header.skeleton, defaults["*"])
        fire = FirePos(round(ratio * header.length, 3), position)
    result.metas[new_path] = add_fire_pos(meta, fire)
    return AnimRef(ref.anim, new_path, ref.sound)


def use_fire_anim_override(anim_set: AnimSet, ids: Dict[str, int], files: GameFiles, defaults: Dict, override: Optional[List[float]], result: Result) -> List[str]:
    """Point every fire slot of a set listed in `FIRE_ANIM_OVERRIDES` at its chosen animation.

    Args:
        anim_set (AnimSet): Set to change in place.
        ids (Dict[str, int]): Slot id by name.
        files (GameFiles): File reader.
        defaults (Dict): Fire defaults from `fire_defaults`.
        override (Optional[List[float]]): Fire marker override from the selection, or None.
        result (Result): Collects fire metas written.

    Returns:
        The changed slot names, each marked `(override)`.
    """
    anim_path = FIRE_ANIM_OVERRIDES.get(anim_set.name)
    if anim_path is None:
        return []
    names = {slot_id: name for name, slot_id in ids.items()}
    meta_path = os.path.splitext(anim_path)[0] + ".anm.meta"
    files.prefetch([anim_path, meta_path])
    anim = files.read(anim_path)
    if anim is None:
        result.manual.append(f"{anim_set.name}: fire animation override {anim_path} not found")
        return []
    header = read_anim_header(anim)
    changed = []
    for i, slot in enumerate(anim_set.slots):
        name = names.get(slot.slot_id, "")
        if FIRE_FAMILY.match(name) and slot.refs and slot.refs[0].anim != anim_path:
            sound = slot.refs[0].sound
            ref = marked_ref(AnimRef(anim_path, meta_path if files.read(meta_path) is not None else "", sound), header, files, defaults, override, result)
            anim_set.slots[i] = replace(slot, refs=[ref])
            changed.append(f"{name} (override)")
    return changed


def replace_backwards_fire(anim_set: AnimSet, ids: Dict[str, int], files: GameFiles, defaults: Dict, override: Optional[List[float]], result: Result) -> List[str]:
    """Point fire slots whose animation is turned around at a forward-facing cast instead, so the unit does not fire backwards.

    Only animations whose animroot is read as turned are swapped. A moving or unread animroot is left alone.

    Args:
        anim_set (AnimSet): Set to change in place.
        ids (Dict[str, int]): Slot id by name.
        files (GameFiles): File reader.
        defaults (Dict): Fire defaults from `fire_defaults`.
        override (Optional[List[float]]): Fire marker override from the selection, or None.
        result (Result): Collects fire metas and sets that need a manual animation.

    Returns:
        The swapped slot names, each marked `(was backwards)`.
    """
    names = {slot_id: name for name, slot_id in ids.items()}

    def is_backwards(slot: Slot) -> bool:
        anim = files.read(slot.refs[0].anim) if slot.refs else None
        return anim is not None and faces_backward(read_anim_header(anim))

    swapped = []
    for kind in ("foot", "rider"):
        fire_slots = [i for i, slot in enumerate(anim_set.slots) if FIRE_FAMILY.match(names.get(slot.slot_id, "")) and names[slot.slot_id].startswith("RIDER_") == (kind == "rider")]
        backwards = [i for i in fire_slots if is_backwards(anim_set.slots[i])]
        if not backwards:
            continue
        found = find_fire_ref(anim_set, kind, ids, files, defaults, override, result)
        if found is None:
            result.manual.append(f"{anim_set.name} ({kind}): fire animation is backwards and no forward-facing cast animation exists")
            continue
        for i in backwards:
            anim_set.slots[i] = replace(anim_set.slots[i], refs=[found[1]])
            swapped.append(f"{names[anim_set.slots[i].slot_id]} (was backwards)")
    return swapped


def is_rider_anim(path: str) -> bool:
    """Tell whether an animation is a seated rider animation, from its folder.

    Args:
        path (str): Animation path.

    Returns:
        True when the path is under a `rider` folder.
    """
    return "/rider/" in path.replace("\\", "/").lower()


def replace_standing_rider_fire(anim_set: AnimSet, ids: Dict[str, int], files: GameFiles, defaults: Dict, override: Optional[List[float]], result: Result) -> List[str]:
    """Point rider fire slots that play a standing cast at the set's seated rider cast, so the rider does not stand up on the mount to fire.

    Sets with no seated rider cast are left alone, since vanilla uses the standing cast for those riders too.

    Args:
        anim_set (AnimSet): Set to change in place.
        ids (Dict[str, int]): Slot id by name.
        files (GameFiles): File reader.
        defaults (Dict): Fire defaults from `fire_defaults`.
        override (Optional[List[float]]): Fire marker override from the selection, or None.
        result (Result): Collects fire metas written.

    Returns:
        The swapped slot names, each marked `(was standing)`.
    """
    names = {slot_id: name for name, slot_id in ids.items()}
    standing = [i for i, slot in enumerate(anim_set.slots) if FIRE_FAMILY.match(names.get(slot.slot_id, "")) and names[slot.slot_id].startswith("RIDER_") and slot.refs and not is_rider_anim(slot.refs[0].anim)]
    if not standing:
        return []
    found = find_fire_ref(anim_set, "rider", ids, files, defaults, override, result)
    if found is None or not is_rider_anim(found[1].anim):
        return []
    for i in standing:
        anim_set.slots[i] = replace(anim_set.slots[i], refs=[found[1]])
    return [f"{names[anim_set.slots[i].slot_id]} (was standing)" for i in standing]


def patch_set(anim_set: AnimSet, kinds: Set[str], ids: Dict[str, int], files: GameFiles, defaults: Dict, override: Optional[List[float]], result: Result, fwm_kinds: Set[str] = frozenset()) -> List[str]:
    """Add the fire, combat-ready and fire-while-moving slots a set is missing.

    Args:
        anim_set (AnimSet): Set to change in place.
        kinds (Set[str]): Unit kinds of the ticked units using the set.
        fwm_kinds (Set[str]): Unit kinds of the units using the set that should fire while moving.
        ids (Dict[str, int]): Slot id by name.
        files (GameFiles): File reader.
        defaults (Dict): Fire defaults from `fire_defaults`.
        override (Optional[List[float]]): Fire marker override from the selection, or None.
        result (Result): Collects fire metas and sets that need a manual animation.

    Returns:
        The slot names added.
    """
    added = []
    added += replace_backwards_fire(anim_set, ids, files, defaults, override, result)
    added += replace_standing_rider_fire(anim_set, ids, files, defaults, override, result)
    present = {slot.slot_id for slot in anim_set.slots}
    # A set that already fires through any fire slot keeps GLF's choice of slots.
    fires = any(ids[name] in present for name in catalog.FIRE_SLOT_NAMES)
    for kind in sorted(kinds):
        missing = [] if fires else [name for name in FIRE_SLOTS[kind] if ids[name] not in present]
        if missing:
            found = find_fire_ref(anim_set, kind, ids, files, defaults, override, result)
            added += add_fire_slots(anim_set, missing, found, ids, present, result, kind)
        if kind != "rider" and ids["COMBAT_READY"] not in present and ids["FIRE_LEVEL"] in present:
            added += copy_slots(anim_set, COMBAT_READY_SOURCES, ids, present)
    for kind in sorted(fwm_kinds):
        added += add_moving_fire(anim_set, kind, ids, present, files, defaults, override, result)
    added += use_fire_anim_override(anim_set, ids, files, defaults, override, result)
    return added


def add_fire_slots(anim_set: AnimSet, names: List[str], found: Optional[Tuple[Slot, AnimRef]], ids: Dict[str, int], present: Set[int], result: Result, label: str) -> List[str]:
    """Add fire slots that all play one fire animation, or note the set for a manual animation when there is none.

    Args:
        anim_set (AnimSet): Set to change in place.
        names (List[str]): Slot names to add.
        found (Optional[Tuple[Slot, AnimRef]]): Slot to copy blend and weight from, and the animation to play, or None when none was found.
        ids (Dict[str, int]): Slot id by name.
        present (Set[int]): Slot ids in the set, updated in place.
        result (Result): Collects sets that need a manual animation.
        label (str): What the slots are for, used in the manual note.

    Returns:
        The slot names added.
    """
    if found is None:
        result.manual.append(f"{anim_set.name} ({label}): no forward-facing cast animation")
        return []
    template, ref = found
    for name in names:
        anim_set.slots.append(replace(template, slot_id=ids[name], weapon_bools=ALL_WEAPONS, refs=[ref]))
        present.add(ids[name])
    return names


def copy_slots(anim_set: AnimSet, pairs: List[Tuple[str, str]], ids: Dict[str, int], present: Set[int]) -> List[str]:
    """Add each missing target slot as a copy of its source slot, when the set has the source.

    Args:
        anim_set (AnimSet): Set to change in place.
        pairs (List[Tuple[str, str]]): (target slot, source slot) names.
        ids (Dict[str, int]): Slot id by name.
        present (Set[int]): Slot ids in the set, updated in place.

    Returns:
        The slot names added.
    """
    pairs = [(target, source) for target, source in pairs if ids[target] not in present and ids[source] in present]
    apply_patches(anim_set, pairs, ids)
    present |= {ids[target] for target, _ in pairs}
    return [target for target, _ in pairs]


def add_moving_fire(anim_set: AnimSet, kind: str, ids: Dict[str, int], present: Set[int], files: GameFiles, defaults: Dict, override: Optional[List[float]], result: Result) -> List[str]:
    """Add the slots a unit kind needs to fire while moving, reusing the set's own fire animation.

    Args:
        anim_set (AnimSet): Set to change in place.
        kind (str): `foot`, `rider` or `flyer`.
        ids (Dict[str, int]): Slot id by name.
        present (Set[int]): Slot ids in the set, updated in place.
        files (GameFiles): File reader.
        defaults (Dict): Fire defaults from `fire_defaults`.
        override (Optional[List[float]]): Fire marker override from the selection, or None.
        result (Result): Collects fire metas and sets that need a manual animation.

    Returns:
        The slot names added.
    """
    added = []
    missing = [name for name in catalog.FWM_SLOTS[kind] if ids[name] not in present]
    if missing:
        fire = next((slot for slot in anim_set.slots if slot.slot_id == ids[FIRE_SLOTS[kind][0]] and slot.refs), None)
        found = (fire, fire.refs[0]) if fire else find_fire_ref(anim_set, kind, ids, files, defaults, override, result)
        added += add_fire_slots(anim_set, missing, found, ids, present, result, f"{kind}, fire whilst moving")
        if found is None:
            return added
    if kind != "rider":
        added += copy_slots(anim_set, SHOOT_SOURCES, ids, present)
    return added


def update_land_units(missiles: Dict[str, str], rows: Dict[str, catalog.UnitRow], inputs: catalog.Inputs, result: Result) -> TsvFile:
    """Add, update and remove GLF land unit rows to match the ticked units.

    Args:
        missiles (Dict[str, str]): Ticked land unit to its missile.
        rows (Dict[str, catalog.UnitRow]): Catalog rows by key.
        inputs (catalog.Inputs): Catalog inputs.
        result (Result): Collects the added, changed and removed units.

    Returns:
        The edited table.
    """
    land = TsvFile.load(catalog.GLF_LAND_UNITS)
    vanilla_land = {row["key"]: row for row in inputs.tables["land_units_tables"]}
    for key in list(land.rows):
        if key not in missiles and key in rows:
            del land.rows[key]
            result.removed.append(key)
    for key, missile in missiles.items():
        if key in land.rows:
            if land.get(key, "primary_missile_weapon") != missile:
                land.set(key, "primary_missile_weapon", missile)
                result.changed.append(key)
        else:
            land.add({**vanilla_land[key], "primary_missile_weapon": missile, **NEW_UNIT_COLUMNS})
            result.added.append(key)
    return land


def update_personalities(missiles: Dict[str, str], rows: Dict[str, catalog.UnitRow], inputs: catalog.Inputs, result: Result) -> Tuple[TsvFile, TsvFile]:
    """Point monster-mount rider personalities at their unit's missile, and add the entity stats rows they need.

    GLF's existing rows are kept as they are unless their unit's missile changes. A newly added unit only gets a row when no regular unit shares
    the personality, which would otherwise gain the missile too.

    Args:
        missiles (Dict[str, str]): Ticked land unit to its missile.
        rows (Dict[str, catalog.UnitRow]): Catalog rows by key.
        inputs (catalog.Inputs): Catalog inputs.
        result (Result): Holds the unit changes and collects the personality changes.

    Returns:
        The edited personalities and entity stats tables.
    """
    personalities = TsvFile.load(PERSONALITIES_TSV)
    stats = TsvFile.load(STATS_TSV)
    vanilla_personalities = {row["key"]: row for row in inputs.tables["battle_personalities_tables"]}
    users = collections.defaultdict(set)
    for junction in inputs.tables["land_units_to_battle_personalities_junctions_tables"]:
        if junction["attach"] == AUTONOMOUS_RIDER:
            users[junction["battle_personality"]].add(junction["land_unit"])
    # Crews that carry their own weapon in vanilla, e.g. the skinks on Mazdamundi's Stegadon, keep it rather than firing the lord's spell.
    for key in list(personalities.rows):
        if vanilla_personalities.get(key, {}).get("battle_entity_stats") and personalities.get(key, "battle_entity_stats").startswith("glf_"):
            del personalities.rows[key]
            result.personalities.append(f"removed armed crew {key}")
    for key, units in sorted(users.items()):
        ticked_units = sorted(unit for unit in units if unit in missiles)
        if key in personalities.rows:
            if not ticked_units and units & set(result.removed):
                del personalities.rows[key]
                result.personalities.append(f"removed {key}")
            elif any(unit in result.changed for unit in ticked_units):
                personalities.set(key, "battle_entity_stats", missiles[ticked_units[0]])
                result.personalities.append(f"changed {key}")
        elif any(unit in result.added for unit in ticked_units):
            if vanilla_personalities[key]["battle_entity_stats"]:
                result.personalities.append(f"left armed crew {key} alone")
                continue
            if not units <= rows.keys():
                result.personalities.append(f"left shared {key} alone")
                continue
            personalities.add({**vanilla_personalities[key], "battle_entity_stats": missiles[ticked_units[0]]})
            result.personalities.append(f"added {key}")
    for key in personalities.rows:
        missile = personalities.get(key, "battle_entity_stats")
        if missile.startswith("glf_") and missile not in stats.rows:
            stats.add({"key": missile, "primary_missile_weapon": missile})
    return personalities, stats


def update_attributes(fwm_units: Set[str], missiles: Dict[str, str], inputs: catalog.Inputs, land: TsvFile, result: Result) -> Tuple[TsvFile, TsvFile]:
    """Give units ticked for fire whilst moving the vanilla attribute that allows it.

    A unit whose attribute group is shared with other units gets its own `glf_<unit>` group, a copy of the vanilla group plus the attribute, so the
    other units do not gain it. GLF owns both tables outright, so they are rebuilt from the selection on every run.

    Args:
        fwm_units (Set[str]): Land units ticked for fire whilst moving.
        missiles (Dict[str, str]): Every ticked land unit, whose GLF rows are in `land`.
        inputs (catalog.Inputs): Catalog inputs.
        land (TsvFile): GLF's land units table, edited in place when a unit moves to its own group or back.
        result (Result): Collects the units given the attribute.

    Returns:
        The attribute junctions and attribute groups tables.
    """
    junctions = TsvFile.create(ATTRIBUTE_JUNCTIONS_TSV, "unit_attributes_to_groups_junctions_tables", 2, ["attribute", "attribute_group"])
    groups = TsvFile.create(ATTRIBUTE_GROUPS_TSV, "unit_attributes_groups_tables", 0, ["group_name"])
    vanilla_group = {row["key"]: row["attribute_group"] for row in inputs.tables["land_units_tables"]}
    members = collections.Counter(vanilla_group.values())
    attributes = collections.defaultdict(list)
    for row in inputs.tables["unit_attributes_to_groups_junctions_tables"]:
        attributes[row["attribute_group"]].append(row["attribute"])
    for key in sorted(missiles):
        base = vanilla_group[key]
        group = base
        if key in fwm_units and catalog.FWM_ATTRIBUTE not in attributes[base]:
            if members[base] > 1:
                group = f"glf_{key}"
                groups.add({"group_name": group})
                for attribute in attributes[base]:
                    junctions.add({"attribute": attribute, "attribute_group": group})
            junctions.add({"attribute": catalog.FWM_ATTRIBUTE, "attribute_group": group})
            result.fwm.append(f"{key} on {group}")
        # Only touch the group column for units ticked for fire whilst moving, or ones moved to a GLF group before.
        if group != base or land.get(key, "attribute_group").startswith("glf_"):
            land.set(key, "attribute_group", group)
    return junctions, groups


def update_chariot_arcs(fwm_units: Set[str], missiles: Dict[str, str], inputs: catalog.Inputs, land: TsvFile, result: Result, layout: Callable[[str], Tuple[List[str], int]] = catalog.vanilla_layout) -> List[TsvFile]:
    """Give chariot units ticked for fire whilst moving a full firing arc, through a GLF copy of their chariot.

    A chariot unit's firing arc appears to come from the chariot's own body, so a chariot whose body is under 360 gets a GLF copy of its record,
    `glf_<key>`, with its articulation nodes and a 360 copy of its body. The rider and draught mount stay vanilla: copying either stopped the chariot
    firing, and a chariot record copied without its articulation nodes crashed the game (both 2026-10-12). GLF owns these tables outright, so they
    are rebuilt from the selection on every run, and an unticked chariot goes back to its vanilla record.

    Args:
        fwm_units (Set[str]): Land units ticked for fire whilst moving.
        missiles (Dict[str, str]): Every ticked land unit, whose GLF rows are in `land`.
        inputs (catalog.Inputs): Catalog inputs.
        land (TsvFile): GLF's land units table, edited in place when a unit moves to a GLF chariot or back.
        result (Result): Collects the chariots widened.
        layout (Callable[[str], Tuple[List[str], int]]): Reads a vanilla table's columns and version.

    Returns:
        The battle entities, articulated vehicles and articulation nodes tables.
    """
    entities = TsvFile.create(ENTITIES_TSV, "battle_entities_tables", *reversed(layout("battle_entities_tables")))
    vehicles = TsvFile.create(VEHICLES_TSV, "land_unit_articulated_vehicles_tables", *reversed(layout("land_unit_articulated_vehicles_tables")))
    nodes = TsvFile.create(NODES_TSV, "articulation_nodes_in_land_articulated_vehicles_tables", *reversed(layout("articulation_nodes_in_land_articulated_vehicles_tables")))
    vanilla_entities = {row["key"]: row for row in inputs.tables["battle_entities_tables"]}
    vanilla_vehicles = {row["key"]: row for row in inputs.tables["land_unit_articulated_vehicles_tables"]}
    vanilla_nodes = collections.defaultdict(list)
    for row in inputs.tables["articulation_nodes_in_land_articulated_vehicles_tables"]:
        vanilla_nodes[row["land_unit_articulated_vehicle"]].append(row)
    vanilla_land = {row["key"]: row for row in inputs.tables["land_units_tables"]}

    for key in sorted(missiles):
        record = vanilla_land[key]["articulated_record"]
        wanted = record
        vehicle = vanilla_vehicles.get(record)
        if key in fwm_units and vehicle and vanilla_nodes.get(record):
            body = vehicle["articulated_entity"]
            if body in vanilla_entities and float(vanilla_entities[body]["fire_arc_close"]) < float(FULL_ARC):
                wanted = f"glf_{record}"
                if wanted not in vehicles.rows:
                    entities.add({**vanilla_entities[body], "key": f"glf_{body}", "fire_arc_close": FULL_ARC})
                    vehicles.add({**vehicle, "key": wanted, "articulated_entity": f"glf_{body}"})
                    for node in vanilla_nodes[record]:
                        nodes.add({**node, "land_unit_articulated_vehicle": wanted})
                result.arcs.append(f"{key}: {wanted}")
        # Only touch the column for chariots ticked for fire whilst moving, or ones pointed at a GLF chariot before.
        if record and (wanted != record or land.get(key, "articulated_record").startswith("glf_")):
            land.set(key, "articulated_record", wanted)
    return [entities, vehicles, nodes]


def patch_sets(missiles: Dict[str, str], fwm_units: Set[str], ticked: Dict[str, Dict], rows: Dict[str, catalog.UnitRow], inputs: catalog.Inputs, files: GameFiles, result: Result) -> Dict[str, AnimSet]:
    """Add the fire and combat-ready slots each ticked unit's animation set is missing.

    Args:
        missiles (Dict[str, str]): Ticked land unit to its missile.
        fwm_units (Set[str]): Ticked land units that should fire while moving.
        ticked (Dict[str, Dict]): Ticked land unit to its selection entry, for `fire_pos` overrides.
        rows (Dict[str, catalog.UnitRow]): Catalog rows by key.
        inputs (catalog.Inputs): Catalog inputs.
        files (GameFiles): File reader.
        result (Result): Collects the patched sets, fire metas and sets that need a manual animation.

    Returns:
        The changed sets by animpack path.
    """
    ids = {name: slot_id for slot_id, name in inputs.names.items()}
    defaults = fire_defaults(inputs, files)
    kinds_by_set = collections.defaultdict(set)
    fwm_kinds_by_set = collections.defaultdict(set)
    overrides: Dict[str, List[float]] = {}
    for key in missiles:
        kinds_by_set[rows[key].anim_set].add(rows[key].kind)
        if key in fwm_units:
            fwm_kinds_by_set[rows[key].anim_set].add(rows[key].kind)
        if ticked[key].get("fire_pos"):
            overrides[rows[key].anim_set] = ticked[key]["fire_pos"]
    # Fetch every cast and fire animation the patched sets might use or check, in one batch per pack.
    wanted_ids = {ids[name] for kind_slots in catalog.CAST_SLOTS.values() for name in kind_slots} | {slot_id for name, slot_id in ids.items() if FIRE_FAMILY.match(name)}
    files.prefetch(
        path
        for set_name in kinds_by_set
        if set_name in inputs.sets
        for slot in inputs.sets[set_name].live.slots
        if slot.slot_id in wanted_ids and slot.refs
        for path in (slot.refs[0].anim, slot.refs[0].meta)
    )
    changed_sets: Dict[str, AnimSet] = {}
    for set_name, kinds in sorted(kinds_by_set.items()):
        entry = inputs.sets.get(set_name)
        if entry is None:
            result.manual.append(f"{set_name}: not a vanilla animation set")
            continue
        anim_set = replace(entry.live, slots=list(entry.live.slots))
        added = patch_set(anim_set, kinds, ids, files, defaults, overrides.get(set_name), result, fwm_kinds_by_set[set_name])
        if added:
            result.sets[set_name] = added
            changed_sets[entry.path] = anim_set
    return changed_sets


def generate(inputs: catalog.Inputs, selection: Dict, files: GameFiles) -> Tuple[Result, List[TsvFile], Dict[str, AnimSet]]:
    """Work out every change for the selection without writing anything.

    Args:
        inputs (catalog.Inputs): Catalog inputs.
        selection (Dict): The saved selection.
        files (GameFiles): File reader.

    Returns:
        The result, the edited tables, and the changed sets by animpack path.
    """
    result = Result()
    rows = {row.key: row for row in inputs.catalog.units}
    ignore = set(selection.get("ignore", []))
    ticked = {key: entry for key, entry in selection.get("units", {}).items() if entry.get("ranged") and key not in ignore and key in rows and not rows[key].special_copy}
    result.skipped += [f"{key}: quest battle or boss copy" for key, entry in selection.get("units", {}).items() if entry.get("ranged") and key in rows and rows[key].special_copy]
    result.skipped += [f"{key}: fire whilst moving needs Ranged ticked" for key, entry in selection.get("units", {}).items() if entry.get("fwm") and not entry.get("ranged")]

    # Missile per ticked unit: the saved choice, else the guess.
    missiles = {}
    for key, entry in ticked.items():
        missile = entry.get("missile") or rows[key].guess
        if not missile:
            result.skipped.append(f"{key}: no missile picked and no guess")
        elif not rows[key].kind:
            result.skipped.append(f"{key}: no animation set")
        else:
            missiles[key] = missile

    land = update_land_units(missiles, rows, inputs, result)
    personalities, stats = update_personalities(missiles, rows, inputs, result)
    fwm_units = {key for key in missiles if ticked[key].get("fwm")}
    junctions, groups = update_attributes(fwm_units, missiles, inputs, land, result)
    chariot_tables = update_chariot_arcs(fwm_units, missiles, inputs, land, result)
    changed_sets = patch_sets(missiles, fwm_units, ticked, rows, inputs, files, result)
    return result, [land, personalities, stats, junctions, groups, *chariot_tables], changed_sets


def write_outputs(result: Result, tables: List[TsvFile], changed_sets: Dict[str, AnimSet]) -> List[str]:
    """Write the tables, the animpack and the fire metas into the GLF mod folder.

    Args:
        result (Result): The generation result.
        tables (List[TsvFile]): Edited tables.
        changed_sets (Dict[str, AnimSet]): Changed sets by animpack path.

    Returns:
        Mod-folder paths of every file written.
    """
    written = []
    for table in tables:
        before = None
        if os.path.exists(table.path):
            with open(table.path, encoding="utf-8", newline="") as f:
                before = f.read()
        if before is None and not table.rows:
            continue
        os.makedirs(os.path.dirname(table.path), exist_ok=True)
        text = table.text()
        if text != before:
            with open(table.path, "w", encoding="utf-8", newline="") as f:
                f.write(text)
            written.append(table.path)
    if changed_sets:
        with open(GLF_ANIMPACK_PATH, "rb") as f:
            files = read_animpack(f.read())
        known = {path for path, _ in files}
        files = [(path, write_set(changed_sets[path]) if path in changed_sets else data) for path, data in files]
        files += [(path, write_set(changed_sets[path])) for path in sorted(changed_sets) if path not in known]
        with open(GLF_ANIMPACK_PATH, "wb") as f:
            f.write(write_animpack(files))
        written.append(GLF_ANIMPACK_PATH)
    for path, data in result.metas.items():
        local = os.path.join(GLF_MOD_DIR, path)
        os.makedirs(os.path.dirname(local), exist_ok=True)
        with open(local, "wb") as f:
            f.write(data)
        written.append(local)
    return written


def deploy(written: List[str]) -> None:
    """Copy written files into the subscribed GLF pack.

    Args:
        written (List[str]): Mod-folder paths of the files to copy.

    Raises:
        FileNotFoundError: If the GLF pack is not installed.
    """
    pack = next(mod["path"] for mod in SUPPORTED_MODS if mod["package_name"] == GLF_PACKAGE)
    if not os.path.exists(pack):
        raise FileNotFoundError(pack)
    args = ["pack", "add", "--pack-path", pack, "--tsv-to-binary", SCHEMA_RON_PATH]
    for local in written:
        folder = os.path.dirname(os.path.relpath(local, GLF_MOD_DIR)).replace("\\", "/")
        args += ["-f", f"{local};{folder}/"]
    run_rpfm_cli(args, capture_output=True)
    logging.info(f"Deployed {len(written)} files to {pack}.")


def report_lines(result: Result) -> List[str]:
    """Describe a generation run.

    Args:
        result (Result): The generation result.

    Returns:
        Report lines.
    """
    lines = [f"Units added {len(result.added)}, removed {len(result.removed)}, missile changed {len(result.changed)}, skipped {len(result.skipped)}"]
    for label, values in (("added", result.added), ("removed", result.removed), ("changed", result.changed), ("skipped", result.skipped), ("personalities", result.personalities), ("fire whilst moving", result.fwm), ("full firing arc", result.arcs)):
        lines += [f"  {label}: {value}" for value in values]
    lines.append(f"\nSets patched {len(result.sets)}")
    lines += [f"  {name}: {', '.join(slots)}" for name, slots in sorted(result.sets.items())]
    lines.append(f"\nFire metas written {len(result.metas)}")
    lines += [f"  {path}" for path in sorted(result.metas)]
    lines.append(f"\nNeeds a manual animation {len(result.manual)}")
    lines += [f"  {value}" for value in result.manual]
    return lines


def main():
    """Generate GLF data and animations for the selection."""
    parser = argparse.ArgumentParser(description="Generate GLF Battle Mage ranged support for the units in selection.json.")
    parser.add_argument("--dry-run", action="store_true", help="Write the report only.")
    parser.add_argument("--deploy", action="store_true", help="Copy the changed files into the subscribed GLF pack.")
    args = parser.parse_args()

    setup_script_logging()
    start_time = time.time()
    try:
        inputs = catalog.load_inputs()
        files = GameFiles()
        result, tables, changed_sets = generate(inputs, catalog.load_selection(), files)
        os.makedirs(os.path.dirname(REPORT_PATH), exist_ok=True)
        with open(REPORT_PATH, "w", encoding="utf-8") as f:
            f.write("\n".join(report_lines(result)) + "\n")
        logging.info(f"Report written to {REPORT_PATH}.")
        if args.dry_run:
            logging.info("Dry run: nothing written.")
            return
        written = write_outputs(result, tables, changed_sets)
        logging.info(f"Wrote {len(written)} files.")
        if args.deploy and written:
            deploy(written)
    finally:
        clear_temp_root()
        log_elapsed_time("GLF ranged generate", start_time)


if __name__ == "__main__":
    main()
