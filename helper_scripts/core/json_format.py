"""Writes hand-edited JSON files (such as generator registries) in one stable layout, so a tool saving them keeps the diffs small.

Nested objects and lists are expanded one key per line with a one-space indent. Lists of plain values stay on one line, and so do nested objects of
plain values when they are short.
"""

import json
from typing import Any

# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Settings

# Longest nested object of plain values kept on one line, in characters.
INLINE_OBJECT = 100


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Format


def _plain(value: Any) -> bool:
    """Tells whether a value is not an object or list."""
    return not isinstance(value, (dict, list))


def format_json(value: Any, depth: int = 0) -> str:
    """Formats a JSON value in the stable layout.

    Args:
        value (Any): The value.
        depth (int): Nesting depth, for the indent.

    Returns:
        str: The text, without a trailing newline.
    """
    pad = " " * (depth + 1)
    if isinstance(value, dict):
        if not value:
            return "{}"
        if depth > 0 and all(_plain(v) for v in value.values()) and len(json.dumps(value, ensure_ascii=False)) <= INLINE_OBJECT:
            return json.dumps(value, ensure_ascii=False)
        lines = [f"{pad}{json.dumps(k, ensure_ascii=False)}: {format_json(v, depth + 1)}" for k, v in value.items()]
        return "{\n" + ",\n".join(lines) + "\n" + " " * depth + "}"
    if isinstance(value, list) and not all(_plain(v) for v in value):
        return "[\n" + ",\n".join(f"{pad}{format_json(v, depth + 1)}" for v in value) + "\n" + " " * depth + "]"
    return json.dumps(value, ensure_ascii=False)


def write_json(path: str, value: Any) -> None:
    """Writes a JSON file in the stable layout, with a trailing newline.

    Args:
        path (str): File path.
        value (Any): The value.
    """
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(format_json(value) + "\n")
