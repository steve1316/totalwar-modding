"""The thumbnail cache: the pictures the page draws of models (the Look tab's lists), kept in the project's `thumbs` folder so they show at once the
next time. `index.json` there maps each model's game path to its picture.
"""

import atexit
import base64
import hashlib
import json
import os
import threading
from typing import Dict, Set

from workbench.plugins.viewer.previews import MODEL_PATH
from workbench.projects import Project

# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Settings

# The start of a picture the page sends.
PNG_PREFIX = "data:image/png;base64,"

# Largest picture kept, in bytes.
MAX_BYTES = 300_000

# The highest drawing style a picture may carry.
MAX_STYLE = 99

# Seconds a changed index waits before it is written, so a run of new pictures writes it once.
WRITE_DELAY = 2.0

# Each project's index in memory (model -> file), the projects whose index has unwritten changes, and the lock guarding both.
_indexes: Dict[str, Dict[str, str]] = {}
_unwritten: Set[str] = set()
_lock = threading.Lock()


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Cache


def _loaded(project: Project) -> Dict[str, str]:
    """The project's index, read from `index.json` the first time. Call with `_lock` held."""
    if project.key not in _indexes:
        path = os.path.join(project.thumbs, "index.json")
        _indexes[project.key] = json.load(open(path, encoding="utf-8")) if os.path.exists(path) else {}
        atexit.register(_write, project)
    return _indexes[project.key]


def _write(project: Project):
    """Writes the project's index if it changed since the last write."""
    with _lock:
        if project.key not in _unwritten:
            return
        _unwritten.discard(project.key)
        text = json.dumps(_indexes[project.key], indent=0, sort_keys=True)
    path = os.path.join(project.thumbs, "index.json")
    with open(path + ".tmp", "w", encoding="utf-8") as f:
        f.write(text)
    os.replace(path + ".tmp", path)


def thumb_index(project: Project) -> Dict[str, str]:
    """The cached pictures.

    Args:
        project (Project): The project.

    Returns:
        Dict[str, str]: Model game path -> its picture's file name in the `thumbs` folder.
    """
    with _lock:
        return dict(_loaded(project))


def save_thumb(project: Project, model: str, image: str, style: int) -> str:
    """Keeps a picture of a model. Its file name ends with the page's drawing style, so the page can tell a picture drawn the old way and draw it again.
    The index is written a moment later, once for a run of pictures, and when the server stops.

    Args:
        project (Project): The project.
        model (str): The model's game path.
        image (str): The picture as a PNG data URL.
        style (int): The drawing style it was drawn with.

    Returns:
        str: Its file name in the `thumbs` folder.

    Raises:
        ValueError: When the model path, the picture or the style is out of shape.
    """
    if not MODEL_PATH.match(model) or not isinstance(image, str) or not image.startswith(PNG_PREFIX):
        raise ValueError("bad model or picture")
    if type(style) is not int or not 1 <= style <= MAX_STYLE:
        raise ValueError("bad style")
    data = base64.b64decode(image[len(PNG_PREFIX):], validate=True)
    if len(data) > MAX_BYTES or not data.startswith(b"\x89PNG"):
        raise ValueError("bad picture")
    name = f"{hashlib.sha1(model.lower().encode()).hexdigest()[:16]}_{style}.png"
    os.makedirs(project.thumbs, exist_ok=True)
    with open(os.path.join(project.thumbs, name), "wb") as f:
        f.write(data)
    with _lock:
        _loaded(project)[model] = name
        if project.key not in _unwritten:
            _unwritten.add(project.key)
            timer = threading.Timer(WRITE_DELAY, _write, (project,))
            timer.daemon = True
            timer.start()
    return name
