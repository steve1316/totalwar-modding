"""Runs the spot map page on a local server and opens it in the browser.

Usage:
    cd helper_scripts && python -m tools.spot_map [--port 8765] [--no-browser]

The first run extracts each campaign's minimap from its pack into `_diag/spot_map/`. A fresh F4 dump from the debug_coordinates mod
(`debug_settlements.tsv` in the game folder) is saved for the campaign it came from on every start and every page reload.
"""

import argparse
import json
import logging
import os
import sys
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from core.utilities import setup_script_logging
from tools.spot_map import campaigns, suggest

STATIC_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "static")


def page_state() -> dict:
    """Builds the page state with each campaign's suggestions attached, checked against its spots.

    Returns:
        `campaigns.state()` with a "suggestions" list on every campaign.
    """
    data = campaigns.state()
    for campaign in data["campaigns"]:
        source = campaigns.CAMPAIGN_BY_KEY[campaign["key"]]
        campaign["suggestions"] = suggest.check(suggest.load(source), campaign["spots"], campaign["pois"])
        # Zones only new suggestions use still need a place in the pending list's zone picker.
        known = {(z["lua"], z["zone"]) for z in campaign["zones"]}
        campaign["zones"] += [{"lua": lua, "zone": zone} for lua, zone in dict.fromkeys((s["lua"], s["zone"]) for s in campaign["suggestions"]) if (lua, zone) not in known]
        campaign["reviews"] = suggest.check_reviews(suggest.load_reviews(source), campaign["spots"], campaign["pois"])
    return data


class Handler(BaseHTTPRequestHandler):
    """Serves the page, the campaign state, the minimaps, and takes exports."""

    def _send(self, code: int, body: bytes, content_type: str, cache: str = "no-store"):
        """Sends a complete response.

        Args:
            code (int): HTTP status code.
            body (bytes): Response body.
            content_type (str): Content-Type header value.
            cache (str): Cache-Control header value. Map images are cached for the session; everything else is always fresh.
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

    def do_GET(self):
        """Serves `/`, `/api/state`, `/map/<campaign>.png` (minimap) and `/map/<campaign>-detail.jpg` (detailed map)."""
        if self.path in ("/", "/index.html"):
            self._send(200, open(os.path.join(STATIC_DIR, "index.html"), "rb").read(), "text/html; charset=utf-8")
        elif self.path == "/api/state":
            campaigns.import_settlement_dump()
            self._json(200, page_state())
        elif self.path.startswith("/map/") and self.path.endswith("-detail.jpg"):
            campaign = campaigns.CAMPAIGN_BY_KEY.get(self.path[len("/map/"):-len("-detail.jpg")])
            jpeg = campaign and campaigns.detail_map(campaign)
            if not jpeg:
                self._json(404, {"error": "no detailed map"})
                return
            self._send(200, open(jpeg, "rb").read(), "image/jpeg", cache="max-age=86400")
        elif self.path.startswith("/map/") and self.path.endswith(".png"):
            key = self.path[len("/map/"):-len(".png")]
            campaign = campaigns.CAMPAIGN_BY_KEY.get(key)
            files = campaign and campaigns.map_files(campaign)
            if not files:
                self._json(404, {"error": f"no map for {key}"})
                return
            self._send(200, open(files["minimap"], "rb").read(), "image/png", cache="max-age=86400")
        else:
            self._json(404, {"error": "not found"})

    def do_POST(self):
        """Takes `/api/export` (pending changes to coordinates.lua), `/api/layout` (save a clean-slate layout) and `/api/export-draft` (write a
        clean-slate layout as draft blocks)."""
        routes = {"/api/export": campaigns.export, "/api/layout": campaigns.save_layout, "/api/export-draft": campaigns.export_draft}
        if self.path not in routes:
            self._json(404, {"error": "not found"})
            return
        try:
            body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))).decode("utf-8"))
            result = routes[self.path](body)
            self._json(200, {"result": result} if self.path == "/api/layout" else {"result": result, "state": page_state()})
        except (ValueError, KeyError) as e:
            logging.error(f"Export failed: {e}")
            self._json(400, {"error": str(e)})

    def log_message(self, fmt, *args):
        """Keeps request logging quiet; errors still go through `logging`.

        Args:
            fmt (str): Format string from the base class.
            *args: Format arguments.
        """


def main() -> int:
    """Starts the server and opens the page.

    Returns:
        int: Process exit code.
    """
    setup_script_logging()
    parser = argparse.ArgumentParser(description="LEAPOI encounter spot map")
    parser.add_argument("--port", type=int, default=8765, help="Local port to serve on.")
    parser.add_argument("--no-browser", action="store_true", help="Do not open the browser.")
    parser.add_argument("--coordinates", help="Edit this coordinates.lua instead of LEAPOI's, e.g. a copy for trying exports out.")
    args = parser.parse_args()
    if args.coordinates:
        campaigns.COORDINATES_PATH = args.coordinates
    if not os.path.isfile(campaigns.COORDINATES_PATH):
        logging.error(f"coordinates.lua not found at {campaigns.COORDINATES_PATH}. Run from helper_scripts/.")
        return 1
    campaigns.import_settlement_dump()
    for campaign in campaigns.CAMPAIGNS:
        campaigns.map_files(campaign)
    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    url = f"http://127.0.0.1:{args.port}/"
    logging.info(f"Spot map at {url} (Ctrl+C to stop)")
    if not args.no_browser:
        webbrowser.open(url)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
