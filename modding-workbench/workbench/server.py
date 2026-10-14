"""The workbench's web server: routes each request to its plugin, serves the shared page files, and answers the tab strip's `/api/nav`.

A plugin is an object with a `key` (its URL prefix, `/<key>/`), `tabs()` (the tab strip entries it adds, as (label, href) pairs), and `get` and
`post` methods taking the request handler and the route after its prefix. Plugins answer through the handler's `send_json`, `send_file` and
`send_static`. The plugin list is `workbench.plugins.PLUGINS`.
"""

import json
import mimetypes
import os
import urllib.parse
from http.server import BaseHTTPRequestHandler
from typing import Any, Dict, List, Optional, Tuple

from workbench.projects import Project

# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Settings

# Page files every tab loads: the tab strip, the theme and the in-game unit panel.
STATIC_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "static")


# //////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////////////////////////////////////////////////////////////////
# Server


class Handler(BaseHTTPRequestHandler):
    """Routes each request to its plugin and sends files and JSON."""

    # Plugins by URL prefix, in tab order.
    plugins: Dict[str, Any]
    # Projects by key.
    projects: Dict[str, Project]

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

    def redirect(self, location: str) -> None:
        """Sends a redirect.

        Args:
            location (str): Where to.
        """
        self.send_response(302)
        self.send_header("Location", location)
        self.send_header("Content-Length", "0")
        self.end_headers()

    def nav(self) -> Dict[str, List[Dict[str, str]]]:
        """The tab strip: every plugin's tabs and the projects for the picker."""
        tabs = [{"label": label, "href": href} for plugin in self.plugins.values() for label, href in plugin.tabs()]
        return {"tabs": tabs, "projects": [{"key": p.key, "name": p.name} for p in self.projects.values()]}

    def route(self) -> Optional[Tuple[str, str]]:
        """Splits the request path into its first segment and the rest, redirecting `/` and bare plugin paths.

        Returns:
            Optional[Tuple[str, str]]: (prefix, route), or None when a redirect was sent.
        """
        path = urllib.parse.unquote(urllib.parse.urlsplit(self.path).path)
        if path == "/":
            self.redirect(self.nav()["tabs"][0]["href"])
            return None
        prefix, slash, rest = path.lstrip("/").partition("/")
        if not slash and prefix in self.plugins:
            query = urllib.parse.urlsplit(self.path).query
            self.redirect(f"/{prefix}/" + (f"?{query}" if query else ""))
            return None
        return prefix, rest

    def do_GET(self) -> None:
        """Serves `/static/<file>` and `/api/nav`, else hands the request to its plugin."""
        routed = self.route()
        if not routed:
            return
        prefix, rest = routed
        if prefix == "static":
            self.send_static(STATIC_DIR, rest)
        elif prefix == "api" and rest == "nav":
            self.send_json(200, self.nav())
        elif prefix in self.plugins:
            self.plugins[prefix].get(self, rest)
        else:
            self.send_json(404, {"error": "not found"})

    def do_POST(self) -> None:
        """Hands the request and its body to its plugin."""
        routed = self.route()
        if not routed:
            return
        prefix, rest = routed
        body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        if prefix in self.plugins:
            self.plugins[prefix].post(self, rest, body)
        else:
            self.send_json(404, {"error": "not found"})

    def log_message(self, format: str, *args: Any) -> None:
        """Logs only saves and jobs, not every file or poll."""
        if self.command == "POST":
            super().log_message(format, *args)
