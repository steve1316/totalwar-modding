"""The Workbench tab: a project's studio. Forms and slots, a Battle stage (3D models and animations, with each form's vanilla equivalent) and a
Portrait stage (the porthole camera), inspector tabs (Stats, Adjust, Portrait, more to come) and a bar to save, rebuild and deploy.

The page is `index.html` with its modules in `studio/`, served from this folder. A project's gallery data (exported by `tools.anim_viewer.exporter`) is served under
`/viewer/p/<project>/data/`, and its tuning and job routes under `/viewer/p/<project>/api/`:
- `GET tuning`: the tuning values, the weapon models that may get an offset, and the job state. `POST tuning`: saves values into the registry.
- `POST run/<job>`: starts one of the project's jobs (rebuild, deploy). `GET job`: the job state and the end of its log.
- `POST props`: exports models (`items`, each with `model`, `slot`, `attach` and `skeleton`) into the gallery for the live previews and
  thumbnails, answering `urls` (null for a model not found).
"""

import json
import os
from typing import Dict, List, Tuple

from workbench.plugins.viewer.previews import prop_previews
from workbench.projects import Project

# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Settings

# The pages.
PAGE_DIR = os.path.dirname(os.path.abspath(__file__))


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Plugin


class Viewer:
    """The Workbench plugin."""

    # URL prefix.
    key = "viewer"
    # Projects by key.
    projects: Dict[str, Project]

    def __init__(self, projects: Dict[str, Project]):
        self.projects = projects

    def tabs(self) -> List[Tuple[str, str]]:
        """The tab strip entries."""
        return [("Workbench", "/viewer/")]

    def project_route(self, handler, route: str) -> Tuple[Project, str]:
        """Splits `p/<project>/<rest>`, answering 404 for an unknown project.

        Args:
            handler: The request handler.
            route (str): The route after `/viewer/`.

        Returns:
            Tuple[Project, str]: The project and the rest, or (None, "") when the 404 was sent.
        """
        _, key, rest = (route.split("/", 2) + ["", ""])[:3]
        project = self.projects.get(key)
        if not project:
            handler.send_json(404, {"error": f"no project {key}"})
        return project, rest

    def get(self, handler, route: str) -> None:
        """Answers a GET under `/viewer/`: a page, a project's gallery file, or a project API route.

        Args:
            handler: The request handler (`send_json`, `send_static`).
            route (str): The path after `/viewer/`.
        """
        if not route.startswith("p/"):
            handler.send_static(PAGE_DIR, route or "index.html")
            return
        project, rest = self.project_route(handler, route)
        if not project:
            return
        if rest.startswith("data/"):
            handler.send_static(project.gallery, rest[len("data/"):])
        elif rest == "api/tuning":
            handler.send_json(200, dict(project.tuning_values(), job=project.job.state()))
        elif rest == "api/job":
            handler.send_json(200, project.job.state())
        else:
            handler.send_json(404, {"error": "unknown route"})

    def post(self, handler, route: str, body: bytes) -> None:
        """Answers `api/tuning` (save) and `api/run/<job>` (start a job) of a project.

        Args:
            handler: The request handler.
            route (str): The path after `/viewer/`.
            body (bytes): The request body.
        """
        project, rest = self.project_route(handler, route) if route.startswith("p/") else (None, "")
        if not project:
            if not route.startswith("p/"):
                handler.send_json(404, {"error": "unknown route"})
            return
        try:
            changes = json.loads(body or b"{}")
        except json.JSONDecodeError:
            handler.send_json(400, {"error": "bad json"})
            return
        if rest == "api/tuning":
            if project.job.state()["running"]:
                handler.send_json(409, {"error": "a job is running"})
                return
            try:
                handler.send_json(200, project.save_tuning(changes))
            except ValueError as error:
                handler.send_json(400, {"error": str(error)})
        elif rest == "api/props":
            try:
                handler.send_json(200, {"urls": prop_previews(project, changes.get("items"))})
            except ValueError as error:
                handler.send_json(400, {"error": str(error)})
        elif rest.startswith("api/run/") and rest[len("api/run/"):] in project.jobs:
            started = project.job.start(rest[len("api/run/"):])
            handler.send_json(200 if started else 409, project.job.state())
        else:
            handler.send_json(404, {"error": "unknown route"})
