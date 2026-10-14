"""The dashboard's Unit Browser tab: the TTC unit browser (`tools.ttc_review`), served under `/browser/`.

Its rosters, caps and art take about a minute to build, so they load in the background the first time the tab is opened. Until then the state route
answers 503 and the page waits.
"""

import json
import logging
import os
import threading
from typing import Optional

from tools.ttc_review import catalog

# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Settings

# The browser page.
PAGE = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "ttc_review", "static", "index.html")


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Session


class Browser:
    """The TTC review session, loaded once on first use."""

    # Guards `session`, `error` and `loading`.
    lock: threading.Lock
    # The loaded session, or None before it is ready.
    session: Optional[catalog.ReviewSession]
    # Why loading failed, or None.
    error: Optional[str]
    # Whether the load thread is running.
    loading: bool

    def __init__(self):
        self.lock = threading.Lock()
        self.session, self.error, self.loading = None, None, False

    def ready(self) -> Optional[catalog.ReviewSession]:
        """The session, starting its load in the background the first time it is asked for.

        Returns:
            Optional[catalog.ReviewSession]: The session, or None while it loads or after it failed.
        """
        with self.lock:
            if self.session or self.loading or self.error:
                return self.session
            self.loading = True
        threading.Thread(target=self._load, daemon=True).start()
        return None

    def _load(self) -> None:
        """Loads the session and records the result."""
        try:
            session, error = catalog.load_session(), None
        except FileNotFoundError as e:
            session, error = None, str(e)
            logging.error(error)
        with self.lock:
            self.session, self.error, self.loading = session, error, False

    def get(self, handler, route: str) -> None:
        """Answers a GET under `/browser/`.

        Args:
            handler: The request handler (`send_bytes`, `send_json`, `send_file`).
            route (str): The path after `/browser/`.
        """
        if route in ("", "index.html"):
            self.ready()
            handler.send_file(PAGE)
            return
        session = self.ready()
        if route == "api/state":
            if session:
                handler.send_json(200, session.state())
            else:
                handler.send_json(500 if self.error else 503, {"error": self.error or "loading"})
        elif not session:
            handler.send_json(503, {"error": self.error or "loading"})
        elif route.startswith("api/unit/"):
            try:
                handler.send_json(200, session.unit(route[len("api/unit/"):]))
            except KeyError:
                handler.send_json(404, {"error": "unknown unit"})
        elif route.startswith("art/"):
            # Only files the art index knows are served, so the path cannot reach anything else on disk.
            path = session.catalog.art.get(route[len("art/"):].lower())
            if path:
                handler.send_file(path, cache="max-age=86400")
            else:
                handler.send_json(404, {"error": "no art"})
        else:
            handler.send_json(404, {"error": "not found"})

    def post(self, handler, route: str, body: bytes) -> None:
        """Answers `api/save` with `{"changes": [{key, category, weight}, ...]}`: the written files and the refreshed state.

        Args:
            handler: The request handler.
            route (str): The path after `/browser/`.
            body (bytes): The request body.
        """
        session = self.ready()
        if route != "api/save" or not session:
            handler.send_json(404 if session else 503, {"error": "not found" if session else "loading"})
            return
        try:
            files = session.save(json.loads(body.decode("utf-8")).get("changes", []))
            handler.send_json(200, {"files": files, "state": session.state()})
        except ValueError as e:
            logging.error(f"Save failed: {e}")
            handler.send_json(400, {"error": str(e)})
