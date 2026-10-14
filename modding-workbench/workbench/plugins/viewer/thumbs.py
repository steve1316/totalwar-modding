"""The thumbnail cache: the pictures the page draws of models (the Look tab's lists), kept in the project's `thumbs` folder so they show at once the
next time. `index.json` there maps each model's game path to its picture.
"""

import base64
import hashlib
import json
import os
import re
import threading
from typing import Dict

from workbench.projects import Project

# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Settings

# A model's game path.
MODEL_PATH = re.compile(r"^[\w ./-]+\.(wsmodel|rigid_model_v2)$", re.IGNORECASE)

# The start of a picture the page sends.
PNG_PREFIX = "data:image/png;base64,"

# Largest picture kept, in bytes.
MAX_BYTES = 300_000

# One write to an index at a time.
_lock = threading.Lock()


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Cache


def thumb_index(project: Project) -> Dict[str, str]:
    """The cached pictures.

    Args:
        project (Project): The project.

    Returns:
        Dict[str, str]: Model game path -> its picture's file name in the `thumbs` folder.
    """
    path = os.path.join(project.thumbs, "index.json")
    return json.load(open(path, encoding="utf-8")) if os.path.exists(path) else {}


def save_thumb(project: Project, model: str, image: str) -> str:
    """Keeps a picture of a model.

    Args:
        project (Project): The project.
        model (str): The model's game path.
        image (str): The picture as a PNG data URL.

    Returns:
        str: Its file name in the `thumbs` folder.

    Raises:
        ValueError: When the model path or the picture is out of shape.
    """
    if not MODEL_PATH.match(model) or ".." in model or not isinstance(image, str) or not image.startswith(PNG_PREFIX):
        raise ValueError("bad model or picture")
    data = base64.b64decode(image[len(PNG_PREFIX):], validate=True)
    if len(data) > MAX_BYTES or not data.startswith(b"\x89PNG"):
        raise ValueError("bad picture")
    name = hashlib.sha1(model.lower().encode()).hexdigest()[:16] + ".png"
    with _lock:
        os.makedirs(project.thumbs, exist_ok=True)
        with open(os.path.join(project.thumbs, name), "wb") as f:
            f.write(data)
        index = thumb_index(project)
        index[model] = name
        with open(os.path.join(project.thumbs, "index.json"), "w", encoding="utf-8") as f:
            json.dump(index, f, indent=0, sort_keys=True)
    return name
