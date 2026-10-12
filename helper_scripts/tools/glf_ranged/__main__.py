"""Runs the GLF ranged picker on a local server and opens it in the browser.

Usage:
    cd helper_scripts && python -m tools.glf_ranged [--port 8766] [--no-browser]

The catalog is built once at start. Saving writes `tools/glf_ranged/selection.json`. Unit card images are extracted from `ui.pack` into
`_diag/glf_ranged_cards/` on the first start, and again whenever the game updates `ui.pack`.
"""

import argparse
import json
import logging
import os
import subprocess
import sys
import threading
import webbrowser
from dataclasses import asdict
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Dict

from core.utilities import clear_temp_root, setup_script_logging
from tools.glf_ranged import catalog, generate

STATIC_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "static")
# Filled once at start so page loads do not rebuild the catalog.
STATE: Dict = {}
# Log of the last apply run, and a lock so only one apply runs at a time.
APPLY_LOG = "./_diag/glf_ranged_apply.log"
APPLY_LOCK = threading.Lock()
# Land unit key to its extracted card image path, filled at start.
CARDS: Dict[str, str] = {}


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


def load_state() -> None:
    """Build the catalog and fill `STATE` and `CARDS` for the page."""
    try:
        built = catalog.load_catalog(cards=True)
    finally:
        clear_temp_root()
    STATE.update(units=[asdict(row) for row in built.units], missiles=built.missiles, selection=catalog.load_selection())
    CARDS.clear()
    CARDS.update({row.key: os.path.join(catalog.CARDS_DIR, row.card) for row in built.units if row.card})
    logging.info(f"Catalog ready with {len(built.units)} units, {len(CARDS)} with card art.")


def game_running() -> bool:
    """Tell whether Warhammer 3 is running, which keeps its packs locked.

    Returns:
        True when `Warhammer3.exe` is in the task list.
    """
    tasks = subprocess.run(["tasklist", "/FI", "IMAGENAME eq Warhammer3.exe"], capture_output=True, text=True).stdout
    return "warhammer3.exe" in tasks.lower()


def apply_selection(body: Dict) -> Dict:
    """Save a selection, run the generator with `--deploy`, and reload the catalog so the page shows the new status.

    Args:
        body (Dict): The selection, as for `save_selection`.

    Raises:
        ValueError: If the selection is invalid, the game is running, another apply is running, or the generator fails.

    Returns:
        The save result plus the generator report.
    """
    if game_running():
        raise ValueError("Close Warhammer 3 first. The game locks the GLF pack.")
    if not APPLY_LOCK.acquire(blocking=False):
        raise ValueError("An apply is already running.")
    try:
        saved = save_selection(body)
        with open(APPLY_LOG, "w", encoding="utf-8") as log:
            run = subprocess.run([sys.executable, "-u", "-m", "tools.glf_ranged.generate", "--deploy"], stdout=log, stderr=subprocess.STDOUT)
        if run.returncode != 0:
            raise ValueError(f"The generator failed. See {APPLY_LOG}.")
        with open(generate.REPORT_PATH, encoding="utf-8") as f:
            report = f.read()
        load_state()
        return {**saved, "report": report}
    finally:
        APPLY_LOCK.release()


class Handler(BaseHTTPRequestHandler):
    """Serves the page and the catalog, and saves selections."""

    def _send(self, code: int, body: bytes, content_type: str, cache: str = "no-store"):
        """Sends a complete response.

        Args:
            code (int): HTTP status code.
            body (bytes): Response body.
            content_type (str): Content-Type header value.
            cache (str): Cache-Control header value. Card images are cached for a day; everything else is always fresh.
        """
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", cache)
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
        elif self.path.startswith("/card/") and self.path.endswith(".png"):
            path = CARDS.get(self.path[len("/card/") : -len(".png")])
            if path is None:
                self._json(404, {"error": "no card"})
                return
            with open(path, "rb") as f:
                self._send(200, f.read(), "image/png", cache="max-age=86400")
        else:
            self._json(404, {"error": "not found"})

    def do_POST(self):
        """Saves a selection, or saves and applies it."""
        routes = {"/api/selection": save_selection, "/api/apply": apply_selection}
        if self.path not in routes:
            self._json(404, {"error": "not found"})
            return
        try:
            body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))) or b"{}")
            self._json(200, routes[self.path](body))
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
    load_state()

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
