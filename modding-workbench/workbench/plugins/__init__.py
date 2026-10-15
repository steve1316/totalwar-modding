"""The workbench's plugins, in tab order. A new workflow is a new package here with a plugin class (see `workbench.server` for the interface),
added to `make_plugins`.
"""

from typing import Dict

from workbench.plugins.browser import Browser
from workbench.plugins.viewer import Viewer
from workbench.projects import Project


def make_plugins(projects: Dict[str, Project]) -> Dict:
    """Builds every plugin.

    Args:
        projects (Dict[str, Project]): Projects by key.

    Returns:
        Dict: Plugins by URL prefix, in tab order.
    """
    plugins = [Viewer(projects), Browser()]
    return {plugin.key: plugin for plugin in plugins}
