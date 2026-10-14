"""Serve the modding dashboard: one local server with a tab per tool, reachable from a phone on the home network.

Usage:
    cd helper_scripts && python -m tools.dashboard [--host 0.0.0.0] [--port 8765] [--open browser|workbench]

Tabs:
- Workbench (`/workbench/`): the Advisor Overhaul gallery with its Adjust panel and portrait page (`tools.dashboard.workbench`).
- Unit Browser (`/browser/`): the TTC unit browser (`tools.dashboard.browser`), built the first time it is opened.

`/shared/` holds the files every tab loads: the tab strip and the in-game unit panel. There is no login: keep the server on the home network.
"""

import argparse
import json
import mimetypes
import os
import sys
import urllib.parse
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any, Optional

from core.utilities import clear_temp_root, setup_script_logging
from tools.dashboard.browser import Browser
from tools.dashboard.workbench import SERVED, Workbench

# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Settings

# Files every tab loads.
SHARED_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "static")

# Where `/` goes.
HOME = "/workbench/"

# Tab name -> its first page, for `--open`.
PAGES = {"workbench": "/workbench/", "browser": "/browser/"}


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Server


class Handler(BaseHTTPRequestHandler):
    """Routes each request to its tab and sends files and JSON."""

    # The tabs, shared by every request.
    tabs: dict

    def send_bytes(self, code: int, body: bytes, content_type: str, cache: str = "no-store") -> None:
        """Sends a complete response.

        Args:
            code (int): HTTP status code.
            body (bytes): Response body.
            content_type (str): Content-Type header value.
            cache (str): Cache-Control header value. Game art is cached, everything else is always fresh so a rebuild shows on the next load.
        """
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", cache)
        self.end_headers()
        self.wfile.write(body)

    def send_json(self, code: int, data: Any) -> None:
        """Sends a JSON response.

        Args:
            code (int): HTTP status code.
            data (Any): The payload.
        """
        self.send_bytes(code, json.dumps(data, ensure_ascii=False).encode("utf-8"), "application/json; charset=utf-8")

    def send_file(self, path: str, cache: str = "no-cache") -> None:
        """Sends a local file, typed by its extension.

        Args:
            path (str): Local file path.
            cache (str): Cache-Control header value.
        """
        content_type = mimetypes.guess_type(path)[0] or "application/octet-stream"
        if content_type.startswith("text/") or content_type.endswith(("javascript", "json")):
            content_type += "; charset=utf-8"
        with open(path, "rb") as f:
            self.send_bytes(200, f.read(), content_type, cache)

    def send_static(self, root: str, route: str) -> None:
        """Sends a file from under a folder, or a 404 when the path leaves it or is missing.

        Args:
            root (str): The folder.
            route (str): The path inside it.
        """
        base = os.path.realpath(root)
        path = os.path.realpath(os.path.join(base, route))
        if os.path.commonpath([base, path]) != base or not os.path.isfile(path):
            self.send_json(404, {"error": "not found"})
            return
        self.send_file(path)

    def route(self) -> Optional[tuple]:
        """Splits the request path into its tab and the route inside it, redirecting `/` and bare tab paths.

        Returns:
            Optional[tuple]: (tab name, route), or None when a redirect was sent.
        """
        path = urllib.parse.unquote(urllib.parse.urlsplit(self.path).path)
        if path == "/":
            self.redirect(HOME)
            return None
        tab, _, rest = path.lstrip("/").partition("/")
        if not _ and tab in self.tabs:
            self.redirect(f"/{tab}/")
            return None
        return tab, rest

    def redirect(self, location: str) -> None:
        """Sends a redirect.

        Args:
            location (str): Where to.
        """
        self.send_response(302)
        self.send_header("Location", location)
        self.send_header("Content-Length", "0")
        self.end_headers()

    def do_GET(self) -> None:
        """Serves `/shared/<file>`, else hands the request to its tab."""
        routed = self.route()
        if not routed:
            return
        tab, rest = routed
        if tab == "shared":
            self.send_static(SHARED_DIR, rest)
        elif tab in self.tabs:
            self.tabs[tab].get(self, rest)
        else:
            self.send_json(404, {"error": "not found"})

    def do_POST(self) -> None:
        """Hands the request and its body to its tab."""
        routed = self.route()
        if not routed:
            return
        tab, rest = routed
        body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        if tab in self.tabs:
            self.tabs[tab].post(self, rest, body)
        else:
            self.send_json(404, {"error": "not found"})

    def log_message(self, format: str, *args: Any) -> None:
        """Logs only saves and jobs, not every file or poll."""
        if self.command == "POST":
            super().log_message(format, *args)


def main() -> int:
    """Serves the dashboard until Ctrl+C.

    Returns:
        int: Process exit code.
    """
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--host", default="0.0.0.0", help="address to bind (default: every network interface, for the phone)")
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--open", choices=sorted(PAGES), help="open this tab in the browser once the server is up")
    args = parser.parse_args()
    if not os.path.isdir(SERVED):
        print(f"no gallery at {SERVED} yet: the Workbench tab stays empty until python -m generators.advisor_overhaul_gallery --out {SERVED} runs")
    Handler.tabs = {"workbench": Workbench(), "browser": Browser()}
    server = ThreadingHTTPServer((args.host, args.port), Handler)
    print(f"dashboard at http://{'127.0.0.1' if args.host == '0.0.0.0' else args.host}:{args.port}/ (Ctrl+C to stop)")
    if args.open:
        webbrowser.open(f"http://127.0.0.1:{args.port}{PAGES[args.open]}")
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
    sys.exit(exit_code)
