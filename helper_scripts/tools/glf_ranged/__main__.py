"""Runs the GLF ranged picker on a local server and opens it in the browser.

Usage:
    cd helper_scripts && python -m tools.glf_ranged [--port 8766] [--no-browser]

The catalog is built once at start. Saving writes `tools/glf_ranged/selection.json`.
"""

import argparse
import json
import logging
import os
import webbrowser
from dataclasses import asdict
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Dict

from core.utilities import clear_temp_root, setup_script_logging
from tools.glf_ranged import catalog

STATIC_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "static")
# Filled once at start so page loads do not rebuild the catalog.
STATE: Dict = {}


def save_selection(body: Dict) -> Dict:
    """Check and save a selection sent by the page.

    Args:
        body (Dict): The selection, with `units` (key to `ranged`, `fwm`, `missile`) and `ignore` (list of keys).

    Raises:
        ValueError: If a key is not in the catalog or a missile is not a GLF missile.

    Returns:
        A short result for the page.
    """
    known = {row["key"] for row in STATE["units"]}
    missiles = set(STATE["missiles"])
    units, ignore = body.get("units", {}), body.get("ignore", [])
    bad_keys = [key for key in list(units) + list(ignore) if key not in known]
    bad_missiles = [entry["missile"] for entry in units.values() if entry.get("missile") and entry["missile"] not in missiles]
    if bad_keys or bad_missiles:
        raise ValueError(f"Unknown units {bad_keys[:5]} or missiles {bad_missiles[:5]}")
    selection = {
        "units": {key: {"ranged": bool(entry.get("ranged")), "fwm": bool(entry.get("fwm")), "missile": entry.get("missile", "")} for key, entry in units.items()},
        "ignore": sorted(set(ignore)),
    }
    catalog.write_selection(selection)
    STATE["selection"] = selection
    return {"saved": len(selection["units"]), "ignored": len(selection["ignore"])}


class Handler(BaseHTTPRequestHandler):
    """Serves the page and the catalog, and saves selections."""

    def _send(self, code: int, body: bytes, content_type: str):
        """Sends a complete response.

        Args:
            code (int): HTTP status code.
            body (bytes): Response body.
            content_type (str): Content-Type header value.
        """
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _json(self, code: int, data: Dict):
        """Sends a JSON response.

        Args:
            code (int): HTTP status code.
            data (Dict): Body to encode.
        """
        self._send(code, json.dumps(data).encode("utf-8"), "application/json")

    def do_GET(self):
        """Serves the page or the state."""
        if self.path == "/":
            with open(os.path.join(STATIC_DIR, "index.html"), "rb") as f:
                self._send(200, f.read(), "text/html; charset=utf-8")
        elif self.path == "/api/state":
            self._json(200, STATE)
        else:
            self._json(404, {"error": "not found"})

    def do_POST(self):
        """Saves a selection."""
        if self.path != "/api/selection":
            self._json(404, {"error": "not found"})
            return
        try:
            body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))) or b"{}")
            self._json(200, save_selection(body))
        except ValueError as error:
            self._json(400, {"error": str(error)})

    def log_message(self, format, *args):
        """Keeps request logging quiet."""


def main():
    """Build the catalog, start the server, and open the page."""
    parser = argparse.ArgumentParser(description="Pick vanilla lords and heroes for GLF Battle Mage ranged support.")
    parser.add_argument("--port", type=int, default=8766, help="Local port to serve on.")
    parser.add_argument("--no-browser", action="store_true", help="Do not open the page.")
    args = parser.parse_args()

    setup_script_logging()
    try:
        built = catalog.load_catalog()
    finally:
        clear_temp_root()
    STATE.update(units=[asdict(row) for row in built.units], missiles=built.missiles, selection=catalog.load_selection())
    logging.info(f"Catalog ready with {len(built.units)} units.")

    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    url = f"http://127.0.0.1:{args.port}/"
    logging.info(f"Serving {url} (Ctrl+C to stop).")
    if not args.no_browser:
        webbrowser.open(url)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
