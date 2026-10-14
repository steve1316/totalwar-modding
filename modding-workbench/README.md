# Modding workbench

One local web app for in-depth modding workflows: designing a new lord, hero or unit from start to finish, reviewing units, and checking models and
animations, from the PC or a phone on the home network.

```
cd modding-workbench
python -m workbench [--host 0.0.0.0] [--port 8765] [--open]
```

Then open `http://<this PC's LAN address>:8765/`. There is no login, so keep it on the home network.

## Tabs

- **Viewer**: the open project's 3D gallery. Every unit form plays its animation slots, with bones, props and a close-up.
  - **Vs vanilla** stands each form's vanilla equivalent beside it. **Stats** opens the in-game unit panel with the vanilla numbers drawn into
    the bars.
  - **Adjust** slides weapons along their grip and moves the hands live, saves the values into the project's registry, then rebuilds and deploys.
- **Portrait**: the 3D portrait camera, previewed in the in-game porthole frame and saved into the registry.
- **Unit Browser**: the TTC unit browser, a copy of the in-game Unit & Spell Browser for reviewing TTC caps. It builds its data the first time it is
  opened, and needs `helper_scripts/delta_state/ttc_auto_picks.json` from `update.py`.

## Projects

A project is one config in `projects/`. It names:
- the checkout the project lives in (relative to the repo root),
- its registry, its viewer gallery and the folder a rebuild exports the next gallery to (relative to that checkout's `helper_scripts`),
- its jobs: named lists of commands run from that `helper_scripts`, with `{python}` for this Python and `publish` to swap in the new gallery,
- and where its tuning values sit in the registry.

See `projects/advisor_overhaul.json`. The project picker sits at the right of the tab strip.

## Code

| Path | Holds |
|---|---|
| `workbench/__main__.py` | starts the server from the repo's `helper_scripts`, whose libraries the plugins import |
| `workbench/server.py` | routing, shared files (`/static/`), and the tab strip data (`/api/nav`) |
| `workbench/projects.py` | project configs, their jobs, and reading and saving tuning values |
| `workbench/plugins/` | one package per tab group. A plugin has a URL `key`, `tabs()`, and `get` and `post` handlers. Add new ones in `make_plugins` |
| `workbench/static/` | the tab strip, and the in-game unit panel (`unit_panel.js` and `.css`) whose numbers come from `helper_scripts/ttc/unit_panel.py` |

A project's gallery is exported by its own generator with `helper_scripts/tools/anim_viewer/exporter.py`.
