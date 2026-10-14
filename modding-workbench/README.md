# Modding workbench

One local web app for in-depth modding workflows: designing a new lord, hero or unit from start to finish, reviewing units, and checking models and
animations, from the PC or a phone on the home network.

```
cd modding-workbench
python -m workbench [--host 0.0.0.0] [--port 8765] [--open]
```

Then open `http://<this PC's LAN address>:8765/`. There is no login, so keep it on the home network.

## Tabs

- **Workbench**: the open project's studio.
  - **Left:** its forms, grouped by weapon with each mount under it (references such as vanilla units and retarget checks last), and the
    animation slots. On a phone these are two drop-downs above the stage.
  - **Stage:** **Battle** plays the form in 3D with Vs vanilla (its vanilla equivalent beside it), Models, Bones, Props and Close-up.
    **Portrait** shows the 3D portrait camera in the in-game porthole frame, with the vanilla reference beside it. **Skills** shows the unit's
    skill tree like the game's: the fixed weapon and mount skills, then the planned skills with their links. Tap a + cell to plan a skill.
  - **Inspector tabs:** **Stats** (the in-game unit panel, on its own until **Compare with ...** draws the vanilla equivalent into the bars),
    **Adjust** (slide weapons along their grip and move the hands, live), **Portrait** (camera sliders, presets, hood) and **Edit** (unit stats
    for every form of a weapon or for one form, the weapon's own melee and missile values, and its attributes, previewed in Stats at once). Skills
    (name, description, icon, unlock rank, place in the tree, up to three levels of in-game effects with their scopes, the skills it needs, and
    Plan or Build: only built skills are written into the mod). On a phone the inspector is a sheet
    below the stage: tap the handle for half or most of the screen.
  - **Bar:** playback, then one **Save** for every tab's edits, **Undo**, **Rebuild** (saves first, then runs the project's rebuild job),
    **Deploy** and the job **Log**.
- **Unit Browser**: the TTC unit browser, a copy of the in-game Unit & Spell Browser for reviewing TTC caps. It builds its data the first time it is
  opened, and needs `helper_scripts/delta_state/ttc_auto_picks.json` from `update.py`.

## Projects

A project is one config in `projects/`. It names:
- the checkout the project lives in (relative to the repo root),
- its registry, its viewer gallery and the folder a rebuild exports the next gallery to (relative to that checkout's `helper_scripts`),
- its jobs: named lists of commands run from that `helper_scripts`, with `{python}` for this Python and `publish` to swap in the new gallery,
- where its tuning values sit in the registry,
- `editable`: the registry paths the Edit and Skills tabs may set, with `*` for any one key. Anything else is refused,
- and `readable`: registry values the page reads as they are (the planned skills).

See `projects/advisor_overhaul.json`. The project picker sits at the right of the tab strip.

## Code

| Path | Holds |
|---|---|
| `workbench/__main__.py` | starts the server from the repo's `helper_scripts`, whose libraries the plugins import |
| `workbench/server.py` | routing, shared files (`/static/`), and the tab strip data (`/api/nav`) |
| `workbench/projects.py` | project configs, their jobs, and reading and saving tuning values |
| `workbench/plugins/` | one package per tab. A plugin has a URL `key`, `tabs()`, and `get` and `post` handlers. Add new ones in `make_plugins` |
| `workbench/plugins/viewer/studio/` | the Workbench page's modules: `main.js` (layout and wiring), `stage.js` (Battle), `portrait.js` (Portrait stage and tab), `stats.js`, `adjust.js` and `jobs.js`. A new inspector tab is a module with `render(container)` added to `TABS` in `main.js` |
| `workbench/static/` | the tab strip, and the in-game unit panel (`unit_panel.js` and `.css`) whose numbers come from `helper_scripts/ttc/unit_panel.py` |

A project's gallery is exported by its own generator with `helper_scripts/tools/anim_viewer/exporter.py`.
