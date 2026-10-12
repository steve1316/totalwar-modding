"""Runs the TTC unit browser on a local server and opens it in the browser.

Usage:
    cd helper_scripts && python -m tools.ttc_review [--port 8767] [--no-browser]

Lays out each culture's roster like the in-game Unit & Spell Browser with every unit's TTC cap, flags the low-confidence auto picks for review, and
writes confirmed or changed picks to the mods' hand files when Save is pressed. Rerun `update.py` afterwards to refresh the auto files and the TTC pack.
"""

import argparse
import json
import logging
import os
import urllib.parse
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Optional

from core.utilities import clear_temp_root, setup_script_logging
from tools.ttc_review import catalog

STATIC_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "static")
SESSION: Optional[catalog.ReviewSession] = None


class Handler(BaseHTTPRequestHandler):
    """Serves the page, the review state and the art, and takes saves."""

    def _send(self, code: int, body: bytes, content_type: str, cache: str = "no-store"):
        """Sends a complete response.

        Args:
            code (int): HTTP status code.
            body (bytes): Response body.
            content_type (str): Content-Type header value.
            cache (str): Cache-Control header value. Art is cached for the session, everything else is always fresh.
        """
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", cache)
        self.end_headers()
        self.wfile.write(body)

    def _json(self, code: int, data: dict):
        """Sends a JSON response.

        Args:
            code (int): HTTP status code.
            data (dict): The payload.
        """
        self._send(code, json.dumps(data, ensure_ascii=False).encode("utf-8"), "application/json; charset=utf-8")

    def _png(self, path: Optional[str]):
        """Sends a PNG, or a 404 when there is none.

        Args:
            path (Optional[str]): Local file path.
        """
        if not path:
            self._json(404, {"error": "no art"})
            return
        with open(path, "rb") as f:
            self._send(200, f.read(), "image/png", cache="max-age=86400")

    def do_GET(self):
        """Serves `/`, `/api/state`, `/api/unit/<unit key>` (one unit panel) and `/art/<pack-relative path>` (extracted game art)."""
        path = urllib.parse.unquote(self.path)
        if path in ("/", "/index.html"):
            with open(os.path.join(STATIC_DIR, "index.html"), "rb") as f:
                self._send(200, f.read(), "text/html; charset=utf-8")
        elif path == "/api/state":
            self._json(200, SESSION.state())
        elif path.startswith("/api/unit/"):
            try:
                self._json(200, SESSION.unit(path[len("/api/unit/"):]))
            except KeyError:
                self._json(404, {"error": "unknown unit"})
        elif path.startswith("/art/"):
            # Only files the art index knows are served, so the path cannot reach anything else on disk.
            self._png(SESSION.catalog.art.get(path[len("/art/"):].lower()))
        else:
            self._json(404, {"error": "not found"})

    def do_POST(self):
        """Takes `/api/save` with `{"changes": [{key, category, weight}, ...]}` and returns the written files and the refreshed state."""
        if self.path != "/api/save":
            self._json(404, {"error": "not found"})
            return
        try:
            body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))).decode("utf-8"))
            files = SESSION.save(body.get("changes", []))
            self._json(200, {"files": files, "state": SESSION.state()})
        except ValueError as e:
            logging.error(f"Save failed: {e}")
            self._json(400, {"error": str(e)})

    def log_message(self, fmt, *args):
        """Keeps request logging quiet. Errors still go through `logging`.

        Args:
            fmt (str): Format string from the base class.
            *args: Format arguments.
        """


def main() -> int:
    """Loads the review data, starts the server and opens the page.

    Returns:
        int: Process exit code.
    """
    global SESSION
    parser = argparse.ArgumentParser(description="TTC unit browser")
    parser.add_argument("--port", type=int, default=8767, help="Local port to serve on.")
    parser.add_argument("--no-browser", action="store_true", help="Do not open the browser.")
    args = parser.parse_args()
    try:
        SESSION = catalog.load_session()
    except FileNotFoundError as e:
        logging.error(str(e))
        return 1
    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    url = f"http://127.0.0.1:{args.port}/"
    logging.info(f"TTC unit browser at {url} (Ctrl+C to stop)")
    if not args.no_browser:
        webbrowser.open(url)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    setup_script_logging()
    try:
        exit_code = main()
    finally:
        clear_temp_root()
    raise SystemExit(exit_code)
