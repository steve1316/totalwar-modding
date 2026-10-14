"""Serve the modding workbench: one local server with a tab per workflow, reachable from a phone on the home network.

Usage:
    cd modding-workbench && python -m workbench [--host 0.0.0.0] [--port 8765] [--open]

The workbench imports the repo's `helper_scripts` libraries and runs from that folder, since they use paths relative to it. Projects (the mods and
units it works on) are the configs in `projects/`. Plugins (the tabs) are listed in `workbench.plugins`. There is no login: keep the server on the
home network.
"""

import argparse
import os
import sys

# The repo's helper_scripts, whose libraries the plugins import.
HELPER_SCRIPTS = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "helper_scripts")
sys.path.insert(0, HELPER_SCRIPTS)
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import webbrowser  # noqa: E402
from http.server import ThreadingHTTPServer  # noqa: E402

from core.utilities import clear_temp_root, setup_script_logging  # noqa: E402
from workbench.plugins import make_plugins  # noqa: E402
from workbench.projects import load_projects  # noqa: E402
from workbench.server import Handler  # noqa: E402


def main() -> int:
    """Serves the workbench until Ctrl+C.

    Returns:
        int: Process exit code.
    """
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--host", default="0.0.0.0", help="address to bind (default: every network interface, for the phone)")
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--open", action="store_true", help="open the workbench in the browser once the server is up")
    args = parser.parse_args()
    os.chdir(HELPER_SCRIPTS)
    Handler.projects = load_projects()
    Handler.plugins = make_plugins(Handler.projects)
    for project in Handler.projects.values():
        if not os.path.isdir(project.gallery):
            print(f"{project.name}: no gallery at {project.gallery} yet, run its rebuild job")
    server = ThreadingHTTPServer((args.host, args.port), Handler)
    print(f"workbench at http://127.0.0.1:{args.port}/ with {len(Handler.projects)} projects (Ctrl+C to stop)")
    if args.open:
        webbrowser.open(f"http://127.0.0.1:{args.port}/")
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
