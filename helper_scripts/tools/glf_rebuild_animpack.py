"""Rebuild the GLF Battle Mage animpack on top of the current vanilla animation sets.

GLF ships a full copy of each caster's vanilla animation set (`.bin`) with firing slots added. Those copies go stale every time CA patches the
game. CA also renumbers slot ids now and then, which silently moves GLF's slots onto the wrong actions. For every set in the GLF animpack this:
1. Translates GLF's slot ids into the current numbering (`--source-ids-rev` names the schemas commit whose numbering the pack was saved with).
2. Starts from the current vanilla set and adds back what GLF added or deliberately changed.
3. Applies the per-set fixes in `SLOT_PATCHES`.

Usage:
    cd helper_scripts && python -u -m tools.glf_rebuild_animpack --dry-run > _diag/glf_anims_dry.log 2>&1
"""

import argparse
import logging
import os
import re
import struct
import subprocess
import time
from dataclasses import dataclass, field, replace
from typing import Dict, List, Optional, Set, Tuple

from core.extract_cache import cached_pack_extract
from core.utilities import FILEPATH_TO_VANILLA_DATA_TABLES, TEMP_DIR, clear_temp_root, log_elapsed_time, run_rpfm_cli, setup_script_logging

GLF_MOD_DIR = "../warhammer3_mods/1a_glf_battle_mage_Dante"
GLF_ANIMPACK_PATH = f"{GLF_MOD_DIR}/animations/database/battle/bin/!!!glf_battle_mage.animpack"
VANILLA_DATA_DIR = os.path.dirname(FILEPATH_TO_VANILLA_DATA_TABLES)
# The pack holding the vanilla animation tables, then every pack whose file list counts as "exists in vanilla" for the reference check.
VANILLA_TABLES_PACK = "anim.pack"
VANILLA_ASSET_PACKS = ["anim.pack", "anim2.pack", "anim_3.pack", "data.pack"]
VANILLA_TABLES_FOLDER = "animations/database/battle/bin"
SCHEMAS_DIR = "./schemas"
SLOT_IDS_FILE = "anim_ids_warhammer_3.csv"
EXTRACT_DIR = f"{TEMP_DIR}/glf_rebuild_animpack"
REPORT_PATH = "./_diag/glf_rebuild_animpack_report.txt"

# Slot families GLF adds or edits to make casters fire. A GLF change to one of these that swaps in a cast animation is kept over vanilla.
GLF_FIRING_SLOTS = re.compile(r"^(FIRE_|MOVING_FIRE_|RIDER_FIRE_|RIDER_SHOOT_|SHOOT_|AIM_|COMBAT_READY|FLY_COMBAT_READY|RIDER_COMBAT_READY)")
# Weapon bools GLF's firing and combat-ready slots use, so they match the unit in any weapon state.
ALL_WEAPONS = 0x3F

# Per-set fixes applied after the merge, as (target slot, slot whose animations it copies). A target that exists is replaced, otherwise added.
SLOT_PATCHES: Dict[str, List[Tuple[str, str]]] = {
    # Yuan Bo fired with Zhao Ming's cast and had no combat-ready slots, so he T-posed after firing. His long cast (in the MEDIUM slot) marks FIRE_POS.
    # His short cast is not used: its animroot is turned 180 degrees, so he fired backwards with no projectile.
    "hu1e_dlc24_yuan_bo_dragon_jade.bin": [
        ("FIRE_LEVEL", "CAST_SPELL_FORWARD_MEDIUM"),
        ("COMBAT_READY", "STAND"),
        ("COMBAT_READY_MOVE_1", "WALK_1"),
        ("COMBAT_READY_MOVE_2", "RUN_1"),
        ("COMBAT_READY_MOVE_3", "RUN_2"),
        ("COMBAT_READY_STEP_FORWARD", "STEP_FORWARD"),
        ("COMBAT_READY_STEP_BACK", "STEP_BACKWARD"),
        ("COMBAT_READY_STEP_LEFT", "STEP_LEFT"),
        ("COMBAT_READY_STEP_RIGHT", "STEP_RIGHT"),
        ("COMBAT_READY_TURN_LEFT_90", "TURN_LEFT_90"),
        ("COMBAT_READY_TURN_RIGHT_90", "TURN_RIGHT_90"),
    ],
}


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Data


@dataclass(frozen=True)
class AnimRef:
    """One animation a slot can play."""

    # Path of the `.anim` file.
    anim: str
    # Path of the `.anm.meta` file, or empty.
    meta: str
    # Path of the `.snd.meta` file, or empty.
    sound: str


@dataclass
class Slot:
    """One slot of an animation set."""

    # Slot id, e.g. 1 for `STAND`.
    slot_id: int
    # Blend-in time in seconds.
    blend_in: float
    # Weight used when the slot has several entries to pick from.
    weight: float
    # Bit mask of the weapon states the slot applies to.
    weapon_bools: int
    # Unknown flag byte, kept as is.
    flag: int
    # Animations the slot can play.
    refs: List[AnimRef] = field(default_factory=list)


@dataclass
class AnimSet:
    """An animation set (`.bin`) in the WH3 v4.3 format."""

    # Format version, 4 for WH3.
    version: int
    # Format sub version, 3 for WH3.
    sub_version: int
    # Set name.
    name: str
    # Mount set name for riders, or empty.
    mount: str
    # Unknown string, empty in every vanilla set.
    unknown: str
    # Skeleton name.
    skeleton: str
    # Locomotion graph path, or empty.
    locomotion: str
    # Unknown flag, 256 on some flying mounts.
    flag: int
    # Slots in file order.
    slots: List[Slot] = field(default_factory=list)


@dataclass
class MergeReport:
    """What the merge did to one set."""

    # Slot names vanilla has and the GLF copy was missing.
    gained: List[str] = field(default_factory=list)
    # Slot names only GLF has, added after the vanilla slots.
    glf_added: List[str] = field(default_factory=list)
    # Slot names both have where GLF's version was kept.
    glf_kept: List[str] = field(default_factory=list)
    # Firing slot names both have where vanilla's newer version was used.
    vanilla_kept: List[str] = field(default_factory=list)
    # Header fields that differed, as "field: glf -> vanilla".
    header_changes: List[str] = field(default_factory=list)


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Binary format


class _Reader:
    """Little-endian reader over a byte buffer."""

    def __init__(self, data: bytes):
        self.data = data
        self.offset = 0

    def unpack(self, fmt: str):
        """Read one value with the given struct format.

        Args:
            fmt (str): Struct format such as `<I`.

        Returns:
            The value read.
        """
        value = struct.unpack_from(fmt, self.data, self.offset)[0]
        self.offset += struct.calcsize(fmt)
        return value

    def string(self) -> str:
        """Read a u16-length-prefixed UTF-8 string.

        Returns:
            The string read.
        """
        return self.raw(self.unpack("<H")).decode("utf-8")

    def raw(self, length: int) -> bytes:
        """Read raw bytes.

        Args:
            length (int): Byte count.

        Returns:
            The bytes read.
        """
        value = self.data[self.offset : self.offset + length]
        self.offset += length
        return value


def _pack_string(value: str) -> bytes:
    """Encode a u16-length-prefixed UTF-8 string.

    Args:
        value (str): String to encode.

    Returns:
        The encoded bytes.
    """
    encoded = value.encode("utf-8")
    return struct.pack("<H", len(encoded)) + encoded


def read_animpack(data: bytes) -> List[Tuple[str, bytes]]:
    """Split an animpack into its files.

    Args:
        data (bytes): Animpack bytes.

    Returns:
        (path, bytes) pairs in file order.
    """
    reader = _Reader(data)
    files = []
    for _ in range(reader.unpack("<I")):
        path = reader.string()
        files.append((path, reader.raw(reader.unpack("<I"))))
    return files


def write_animpack(files: List[Tuple[str, bytes]]) -> bytes:
    """Join files into animpack bytes.

    Args:
        files (List[Tuple[str, bytes]]): (path, bytes) pairs in file order.

    Returns:
        The animpack bytes.
    """
    out = [struct.pack("<I", len(files))]
    for path, data in files:
        out.append(_pack_string(path) + struct.pack("<I", len(data)) + data)
    return b"".join(out)


def parse_set(data: bytes) -> AnimSet:
    """Parse an animation set.

    Args:
        data (bytes): `.bin` bytes.

    Raises:
        ValueError: If the bytes are not a WH3 v4 set or have trailing data.

    Returns:
        The parsed set.
    """
    reader = _Reader(data)
    version, sub_version = reader.unpack("<I"), reader.unpack("<I")
    if version != 4:
        raise ValueError(f"unsupported set version {version}.{sub_version}")
    anim_set = AnimSet(version, sub_version, reader.string(), reader.string(), reader.string(), reader.string(), reader.string(), reader.unpack("<H"))
    for _ in range(reader.unpack("<I")):
        slot = Slot(reader.unpack("<I"), reader.unpack("<f"), reader.unpack("<f"), reader.unpack("<I"), reader.unpack("<B"))
        slot.refs = [AnimRef(reader.string(), reader.string(), reader.string()) for _ in range(reader.unpack("<I"))]
        anim_set.slots.append(slot)
    if reader.offset != len(data):
        raise ValueError(f"{len(data) - reader.offset} trailing bytes")
    return anim_set


def write_set(anim_set: AnimSet) -> bytes:
    """Encode an animation set.

    Args:
        anim_set (AnimSet): Set to encode.

    Returns:
        The `.bin` bytes.
    """
    out = [struct.pack("<II", anim_set.version, anim_set.sub_version)]
    out += [_pack_string(s) for s in (anim_set.name, anim_set.mount, anim_set.unknown, anim_set.skeleton, anim_set.locomotion)]
    out.append(struct.pack("<HI", anim_set.flag, len(anim_set.slots)))
    for slot in anim_set.slots:
        out.append(struct.pack("<IffIBI", slot.slot_id, slot.blend_in, slot.weight, slot.weapon_bools, slot.flag, len(slot.refs)))
        out += [_pack_string(ref.anim) + _pack_string(ref.meta) + _pack_string(ref.sound) for ref in slot.refs]
    return b"".join(out)


def load_slot_ids(text: str) -> Dict[int, str]:
    """Parse a slot id table (`<id> <name>` per line).

    Args:
        text (str): Contents of an `anim_ids_*.csv` file.

    Returns:
        Slot name by id.
    """
    names = {}
    for line in text.splitlines():
        parts = line.split()
        if len(parts) >= 2:
            names[int(parts[0])] = parts[-1]
    return names


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Merge


def translate_ids(anim_set: AnimSet, source_names: Dict[int, str], target_ids: Dict[str, int]) -> None:
    """Renumber a set's slots from an old slot id table to the current one, by slot name.

    Args:
        anim_set (AnimSet): Set to renumber in place.
        source_names (Dict[int, str]): Slot name by id in the numbering the set was saved with.
        target_ids (Dict[str, int]): Slot id by name in the current numbering.

    Raises:
        KeyError: If a slot id or name is missing from either table.
    """
    for slot in anim_set.slots:
        slot.slot_id = target_ids[source_names[slot.slot_id]]


def _group(slots: List[Slot]) -> Dict[int, List[Slot]]:
    """Group slots by id, keeping file order inside each group.

    Args:
        slots (List[Slot]): Slots to group.

    Returns:
        Slots by id, in order of first appearance.
    """
    groups: Dict[int, List[Slot]] = {}
    for slot in slots:
        groups.setdefault(slot.slot_id, []).append(slot)
    return groups


def _is_cast(path: str) -> bool:
    """Tell whether an animation path is a spell cast.

    Args:
        path (str): Animation path.

    Returns:
        True for cast animations.
    """
    return "cast" in path.lower() or "spell" in path.lower()


def is_glf_edit(glf_slots: List[Slot], vanilla_slots: List[Slot], name: str) -> bool:
    """Tell whether GLF's version of a slot both sides have is a deliberate change rather than an older vanilla copy.

    Args:
        glf_slots (List[Slot]): GLF's slots with this id.
        vanilla_slots (List[Slot]): Vanilla's slots with this id.
        name (str): Slot name.

    Returns:
        True to keep GLF's version.
    """
    glf_refs = [ref for slot in glf_slots for ref in slot.refs]
    vanilla_refs = [ref for slot in vanilla_slots for ref in slot.refs]
    if any("glf_" in path for ref in glf_refs for path in (ref.anim, ref.meta, ref.sound)):
        return True
    if not GLF_FIRING_SLOTS.match(name):
        return False
    # GLF filled a slot vanilla leaves empty, or swapped a cast into a firing slot.
    return (glf_refs and not vanilla_refs) or (any(_is_cast(ref.anim) for ref in glf_refs) and not any(_is_cast(ref.anim) for ref in vanilla_refs))


def merge_set(glf: AnimSet, vanilla: AnimSet, names: Dict[int, str]) -> Tuple[AnimSet, MergeReport]:
    """Rebuild a GLF set from the current vanilla set plus GLF's own slots.

    Args:
        glf (AnimSet): GLF's set, already in the current slot numbering.
        vanilla (AnimSet): The current vanilla set of the same name.
        names (Dict[int, str]): Slot name by id.

    Returns:
        The merged set and what changed.
    """
    report = MergeReport()
    merged = replace(vanilla, slots=[])
    # GLF clears the mount on every flying-mount set, so that stays. Any other header change is CA's.
    if not glf.mount and vanilla.mount:
        merged.mount, merged.flag = glf.mount, glf.flag
    for attr in ("name", "mount", "unknown", "skeleton", "locomotion", "flag"):
        if getattr(glf, attr) != getattr(merged, attr):
            report.header_changes.append(f"{attr}: {getattr(glf, attr)!r} -> {getattr(merged, attr)!r}")

    glf_groups, vanilla_groups = _group(glf.slots), _group(vanilla.slots)
    for slot_id, vanilla_slots in vanilla_groups.items():
        name = names[slot_id]
        glf_slots = glf_groups.get(slot_id)
        if glf_slots is None:
            report.gained.append(name)
            merged.slots += vanilla_slots
            continue
        changed = glf_slots != vanilla_slots
        if changed and is_glf_edit(glf_slots, vanilla_slots, name):
            report.glf_kept.append(name)
            merged.slots += glf_slots
            continue
        if changed and GLF_FIRING_SLOTS.match(name):
            report.vanilla_kept.append(name)
        merged.slots += vanilla_slots
    for slot_id, glf_slots in glf_groups.items():
        if slot_id not in vanilla_groups:
            report.glf_added.append(names[slot_id])
            merged.slots += glf_slots
    return merged, report


def apply_patches(anim_set: AnimSet, patches: List[Tuple[str, str]], ids_by_name: Dict[str, int]) -> None:
    """Point target slots at the animations of source slots, replacing or adding each target.

    Args:
        anim_set (AnimSet): Set to change in place.
        patches (List[Tuple[str, str]]): (target slot, source slot) names.
        ids_by_name (Dict[str, int]): Slot id by name.

    Raises:
        KeyError: If a source slot is missing from the set.
    """
    for target, source in patches:
        source_slot = next((slot for slot in anim_set.slots if slot.slot_id == ids_by_name[source]), None)
        if source_slot is None:
            raise KeyError(f"{anim_set.name} has no {source} slot to copy into {target}")
        new_slot = replace(source_slot, slot_id=ids_by_name[target], weapon_bools=ALL_WEAPONS, refs=list(source_slot.refs))
        position = next((i for i, slot in enumerate(anim_set.slots) if slot.slot_id == new_slot.slot_id), len(anim_set.slots))
        anim_set.slots = [slot for slot in anim_set.slots if slot.slot_id != new_slot.slot_id]
        anim_set.slots.insert(position, new_slot)


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Script


def _read_schema_file(revision: Optional[str]) -> str:
    """Read the slot id table at a schemas commit, or the checked-out one.

    Args:
        revision (Optional[str]): Commit in the schemas clone, or None for the current file.

    Returns:
        The table text.
    """
    if revision is None:
        with open(f"{SCHEMAS_DIR}/{SLOT_IDS_FILE}", encoding="utf-8") as f:
            return f.read()
    return subprocess.run(["git", "-C", SCHEMAS_DIR, "show", f"{revision}:{SLOT_IDS_FILE}"], capture_output=True, text=True, check=True).stdout


def _load_vanilla_sets() -> Dict[str, bytes]:
    """Extract the vanilla animation tables and collect every set by path.

    Raises:
        FileNotFoundError: If no vanilla animpack was extracted.

    Returns:
        Set bytes by path. A set in several animpacks takes the last one.
    """
    cached_pack_extract(f"{VANILLA_DATA_DIR}\\{VANILLA_TABLES_PACK}", VANILLA_TABLES_FOLDER, EXTRACT_DIR, tables_as_tsv=False, capture_output=True)
    folder = f"{EXTRACT_DIR}/{VANILLA_TABLES_FOLDER}"
    animpacks = sorted(f for f in os.listdir(folder) if f.endswith(".animpack")) if os.path.isdir(folder) else []
    if not animpacks:
        raise FileNotFoundError(f"No vanilla animpacks extracted to {folder}")
    sets: Dict[str, bytes] = {}
    for animpack in animpacks:
        with open(f"{folder}/{animpack}", "rb") as f:
            for path, data in read_animpack(f.read()):
                if path.startswith(VANILLA_TABLES_FOLDER) and path in sets and sets[path] != data:
                    logging.warning(f"{path} differs between vanilla animpacks. Using the one in {animpack}.")
                sets[path] = data
    logging.info(f"Loaded {len(sets)} vanilla files from {len(animpacks)} animpacks.")
    return sets


def _known_paths() -> Set[str]:
    """List every file in the vanilla packs and the GLF mod folder.

    Returns:
        Lowercase file paths.
    """
    paths = set()
    for pack in VANILLA_ASSET_PACKS:
        listing = run_rpfm_cli(["pack", "list", "--pack-path", f"{VANILLA_DATA_DIR}\\{pack}"], capture_output=True, text=True).stdout
        paths.update(line.strip().lower() for line in listing.splitlines() if line.strip())
    for root, _, files in os.walk(GLF_MOD_DIR):
        for name in files:
            paths.add(os.path.relpath(os.path.join(root, name), GLF_MOD_DIR).replace("\\", "/").lower())
    return paths


def _check_round_trip(files: Dict[str, bytes], label: str) -> None:
    """Abort if any animation set does not write back to the same bytes.

    Args:
        files (Dict[str, bytes]): Set bytes by path. Only paths under the tables folder are checked.
        label (str): Name used in the error.

    Raises:
        ValueError: If a set fails to parse or round-trip.
    """
    for path, data in files.items():
        if path.startswith(VANILLA_TABLES_FOLDER) and write_set(parse_set(data)) != data:
            raise ValueError(f"{label} set {path} does not round-trip")


def _rebuild_set(path: str, glf_data: bytes, vanilla_data: bytes, source_names: Dict[int, str], names: Dict[int, str]) -> Tuple[bytes, List[str], Set[AnimRef]]:
    """Rebuild one GLF set from its vanilla set and apply its patches.

    Args:
        path (str): Set path in the animpack.
        glf_data (bytes): GLF's set.
        vanilla_data (bytes): The current vanilla set.
        source_names (Dict[int, str]): Slot name by id in the numbering GLF's set uses.
        names (Dict[int, str]): Slot name by id in the current numbering.

    Returns:
        The new set bytes, its report lines, and the animations in slots that came from GLF or a patch.
    """
    ids_by_name = {name: slot_id for slot_id, name in names.items()}
    glf = parse_set(glf_data)
    translate_ids(glf, source_names, ids_by_name)
    merged, report = merge_set(glf, parse_set(vanilla_data), names)
    file_name = path.split("/")[-1]
    patches = SLOT_PATCHES.get(file_name, [])
    apply_patches(merged, patches, ids_by_name)
    patched = [target for target, _ in patches]

    glf_ids = {ids_by_name[name] for name in report.glf_added + report.glf_kept + patched}
    refs = {ref for slot in merged.slots if slot.slot_id in glf_ids for ref in slot.refs}
    slot_ids = {slot.slot_id for slot in merged.slots}
    risk = "  [FIRE_LEVEL without COMBAT_READY]" if ids_by_name["FIRE_LEVEL"] in slot_ids and ids_by_name["COMBAT_READY"] not in slot_ids else ""
    lines = [f"{file_name}: gained {len(report.gained)}, GLF added {len(report.glf_added)}, GLF kept {len(report.glf_kept)}{risk}"]
    for label, values in (("header", report.header_changes), ("GLF kept", report.glf_kept), ("vanilla over GLF", report.vanilla_kept), ("patched", patched)):
        if values:
            lines.append(f"    {label}: {', '.join(values)}")
    return write_set(merged), lines, refs


def main():
    """Rebuild every GLF set, write the report, and write the animpack unless `--dry-run` is set."""
    parser = argparse.ArgumentParser(description="Rebuild the GLF Battle Mage animpack on top of the current vanilla animation sets.")
    parser.add_argument("--dry-run", action="store_true", help="Write the report only.")
    parser.add_argument("--source-ids-rev", default=None, help="Schemas commit whose slot numbering the GLF animpack uses. Defaults to the current one.")
    args = parser.parse_args()

    setup_script_logging()
    start_time = time.time()
    try:
        names = load_slot_ids(_read_schema_file(None))
        source_names = load_slot_ids(_read_schema_file(args.source_ids_rev))

        with open(GLF_ANIMPACK_PATH, "rb") as f:
            glf_files = read_animpack(f.read())
        vanilla_sets = _load_vanilla_sets()
        _check_round_trip(dict(glf_files), "GLF")
        _check_round_trip(vanilla_sets, "vanilla")
        logging.info(f"All {len(glf_files)} GLF sets and every vanilla set round-trip.")

        lines, glf_refs, output = [], set(), []
        for path, data in glf_files:
            if path not in vanilla_sets:
                raise KeyError(f"{path} has no vanilla set")
            new_data, set_lines, set_refs = _rebuild_set(path, data, vanilla_sets[path], source_names, names)
            output.append((path, new_data))
            lines += set_lines
            glf_refs |= set_refs

        known = _known_paths()
        # Vanilla sets also point at movement metas CA never shipped, so only animations and GLF's own metas are checked.
        checked = {p for ref in glf_refs for p in (ref.anim, ref.meta) if p.endswith(".anim") or "glf_" in p}
        missing = sorted(p for p in checked if p.replace("\\", "/").lower() not in known)
        lines.append(f"\nMissing files referenced by GLF slots: {len(missing)}")
        lines += [f"    {p}" for p in missing]

        os.makedirs(os.path.dirname(REPORT_PATH), exist_ok=True)
        with open(REPORT_PATH, "w", encoding="utf-8") as f:
            f.write("\n".join(lines) + "\n")
        logging.info(f"Report written to {REPORT_PATH}.")
        if missing:
            logging.warning(f"{len(missing)} files referenced by GLF slots do not exist. See {REPORT_PATH}.")

        if args.dry_run:
            logging.info("Dry run: animpack not written.")
        else:
            with open(GLF_ANIMPACK_PATH, "wb") as f:
                f.write(write_animpack(output))
            logging.info(f"Wrote {len(output)} sets to {GLF_ANIMPACK_PATH}.")
    finally:
        clear_temp_root()
    log_elapsed_time("GLF animpack rebuild", start_time)


if __name__ == "__main__":
    main()
